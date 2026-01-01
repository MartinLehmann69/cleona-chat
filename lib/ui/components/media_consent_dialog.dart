// lib/ui/components/media_consent_dialog.dart
//
// The one question the interface asks (§12.1): before a file takes a
// media lane (lane 2 or 3, §9.4), the sender consents for THIS transfer
// only, with the linkability named (§24.4.5, B-29). Without consent
// nothing is sent.
//
// What the dialog says, in the order prescribed by §24.4.5:
//   1. the consent applies to this one file; the chat keeps its usual
//      protection afterwards (a remembered blanket consent is the silent
//      mode switch §12 exists to prevent);
//   2. the transfer is an event visible from outside — it does not ride
//      the cover stream, so start, end, rate and approximate size are
//      visible at both egresses;
//   3. one holding device sees both ends of the same transfer;
//   4. the object stays with strangers for up to `TTL_media`;
//   5. in a group only: the holders also see which members collect;
//   6. what stays protected: the content stays encrypted, and the
//      recipient does not learn the sender's address.
//
// Two wording constraints of §24.4.5 are load-bearing and live in the
// texts (`media_consent_lane_*` in translations.dart):
//   - no text borrows the name of a stronger guarantee — a media lane is
//     graded weaker or equal to an ordinary message (B-29);
//   - the content is "encrypted", never "post-quantum".
//
// No duration is shown: the only figure §24.4.5 would allow (the
// sender's upload share) depends on `R_bulk`, which is unmeasured (§9.4).
//
// No "don't ask again", no remembered answer, no second send path: the
// dialog returns a plain yes/no and keeps no state.
//
// ONE GATE FOR EVERY WAY OUT ([mediaLaneConsentFor]): the chat screen
// (attach, camera, file picker, voice note, clipboard, drop area), the
// Android share target and "Forward" all ask through it, so no way a file
// leaves the interface can skip the question
// (`test/smoke/smoke_media_consent_paths.dart`).

import 'package:flutter/material.dart';
import 'package:mycelium/bulk_piece.dart' show kTtlMedia;
import 'package:mycelium/media.dart' as mycelium show Lane, laneChoose;

import 'package:cleona/core/i18n/app_locale.dart';

/// The consent to hand to the service for a file of [length] bytes
/// (§9.4 "Consent"):
///
///  * `false` — the file fits lane 1; nothing is asked (D-29: consent per
///    file only before lanes 2 and 3);
///  * `true`  — the file takes a media lane and the user said yes;
///  * `null`  — the file takes a media lane and the user did not say yes:
///    the caller sends nothing.
///
/// [length] is the size of the file as the interface knows it. The service
/// decides by the object it builds (a voice wrapper can push a file just
/// below the limit over it) and then refuses for missing consent instead of
/// sending on a media lane unasked.
Future<bool?> mediaLaneConsentFor(
  BuildContext context, {
  required int length,
  required bool isGroup,
}) async {
  if (mycelium.laneChoose(length: length) == mycelium.Lane.inline) {
    return false;
  }
  if (!context.mounted) return null;
  return await showMediaLaneConsent(context, isGroup: isGroup) ? true : null;
}

/// Asks whether THIS file may take a media lane (§9.4, §24.4.5).
///
/// Returns `true` only when the user explicitly taps "Send". Cancel,
/// the back button and any other way of closing the dialog return
/// `false`. [isGroup] adds the point that holders see which members
/// collect (B-29).
///
/// No `SafeArea` is needed: this is a dialog, not a Scaffold body —
/// `AlertDialog` already keeps clear of the system bars via its inset
/// padding, and the content scrolls inside it.
Future<bool> showMediaLaneConsent(
  BuildContext context, {
  required bool isGroup,
}) async {
  final answer = await showDialog<bool>(
    context: context,
    // A stray tap next to the dialog must not stand in for a decision.
    barrierDismissible: false,
    builder: (ctx) => MediaLaneConsentDialog(isGroup: isGroup),
  );
  return answer == true;
}

/// The dialog body of [showMediaLaneConsent]; public for widget tests.
class MediaLaneConsentDialog extends StatelessWidget {
  final bool isGroup;

  const MediaLaneConsentDialog({super.key, required this.isGroup});

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.of(context);
    final theme = Theme.of(context);
    final heading = theme.textTheme.titleSmall;
    return AlertDialog(
      scrollable: true,
      title: Text(locale.get('media_consent_lane_title')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(locale.get('media_consent_lane_this_file')),
          const SizedBox(height: 16),
          Text(locale.get('media_consent_lane_changes'), style: heading),
          const SizedBox(height: 8),
          _ConsentPoint(locale.get('media_consent_lane_visible')),
          _ConsentPoint(locale.get('media_consent_lane_both_ends')),
          _ConsentPoint(locale.tr('media_consent_lane_retention',
              {'days': '${kTtlMedia.inDays}'})),
          if (isGroup) _ConsentPoint(locale.get('media_consent_lane_group')),
          const SizedBox(height: 8),
          Text(locale.get('media_consent_lane_protected'), style: heading),
          const SizedBox(height: 8),
          _ConsentPoint(locale.get('media_consent_lane_content')),
          _ConsentPoint(locale.get('media_consent_lane_address')),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(locale.get('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(locale.get('send')),
        ),
      ],
    );
  }
}

/// One consequence in the dialog body.
class _ConsentPoint extends StatelessWidget {
  final String text;
  const _ConsentPoint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsetsDirectional.only(top: 7),
            child: Icon(Icons.circle, size: 6),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
