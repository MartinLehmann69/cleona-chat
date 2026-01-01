// lib/ui/components/forward_picker.dart
//
// The target list of "Forward": every accepted contact, every group, and
// every channel this identity may post to. A tap forwards [msg] there —
// a file that takes a media lane only after the per-file consent of §9.4
// (`mediaLaneConsentFor`).

import 'package:flutter/material.dart';

import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/ui/components/media_consent_dialog.dart';

/// Opens the target list for forwarding [msg] out of
/// [sourceConversationId].
///
/// No `SafeArea` is needed: this is a dialog, not a Scaffold body.
void showForwardPicker(
  BuildContext context,
  ICleonaService service, {
  required String sourceConversationId,
  required UiMessage msg,
}) {
  final locale = AppLocale.read(context);
  // The messenger is taken before any await: the BuildContext must not
  // cross an async gap.
  final messenger = ScaffoldMessenger.maybeOf(context);
  final targets = <MapEntry<String, String>>[]; // id -> display name
  // Every target that is not a contact is a group or a channel — the
  // consent then names what holders see of a group (B-29).
  final contactIds = <String>{};
  for (final c in service.acceptedContacts) {
    targets.add(MapEntry(c.nodeIdHex, c.displayName));
    contactIds.add(c.nodeIdHex);
  }
  for (final g in service.groups.values) {
    targets.add(MapEntry(g.groupIdHex, '${g.name} (${locale.get('group')})'));
  }
  for (final ch in service.channels.values) {
    // Only channels this identity may post to.
    final myRole = ch.members[service.nodeIdHex]?.role ?? 'subscriber';
    if (myRole == 'owner' || myRole == 'admin') {
      targets.add(MapEntry(
          ch.channelIdHex, '${ch.name} (${locale.get('channel')})'));
    }
  }

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(locale.get('forward_to')),
      content: SizedBox(
        width: 300,
        height: 400,
        child: ListView.builder(
          itemCount: targets.length,
          itemBuilder: (_, i) {
            final target = targets[i];
            return ListTile(
              title: Text(target.value),
              onTap: () async {
                Navigator.pop(ctx);
                // §9.4 "Consent": a forwarded file that takes a media lane
                // is asked for like any other, through the same gate. A
                // text has no size to ask about.
                final consent = await mediaLaneConsentFor(context,
                    length: msg.isMedia ? (msg.fileSize ?? 0) : 0,
                    isGroup: !contactIds.contains(target.key));
                if (consent == null) return;
                final result = await service.forwardMessage(
                    sourceConversationId, msg.id, target.key,
                    consent: consent);
                if (result == null) {
                  messenger?.showSnackBar(
                    SnackBar(
                        content: Text(
                            locale.get('forward_media_not_available'))),
                  );
                }
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(locale.get('cancel')),
        ),
      ],
    ),
  );
}
