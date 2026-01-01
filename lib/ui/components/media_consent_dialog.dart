// lib/ui/components/media_consent_dialog.dart
//
// The question from §9.3 ("Mode coupling"): in a high-secure chat a
// file only goes out when the user has consented FOR THIS TRANSFER.
// Where the wordings come from is stated in the block above the
// `media_consent_*` keys in lib/core/i18n/translations.dart
// (owner approval 2026-08-31).
//
// ── TWO ANSWERS, NOT ONE (owner decision 31.08./02.09.2026) ──
//
// Until 02.09.2026 this dialog offered the secure path as "takes longer"
// and left the time open, because the old premise read: "A
// file of this size cannot take this path." That is no longer
// the cut. The owner decided:
//
//   "The data transfer of files shall also be possible in secure
//    mode. […] leaves the user the choice to send the file in secure
//    mode […] or whether he wants to send the file in speed mode
//    and lists the security disadvantages in doing so. If he
//    chooses speed mode this applies only to this file transfer."
//
// ── AND WHY THERE IS STILL NO DURATION HERE (03.09.2026) ───────────
//
// The same decision named "an approximate time indication of how long it
// would take". Between 02. and 03.09.2026 it DID stand here —
// as a range, computed by `estimateMediaSend`. It is out again,
// and not out of taste, but because its most expensive item depends on
// a constant that nobody has measured on the wire:
//
//   `Cleona_Chat_Architecture_v4_1.md`, Appendix A, l. 11936, on `R_bulk`:
//   "**32 cells/s (38.4 KB/s)** … proposed — to be measured …
//    **No user-visible duration may be derived from it until it is
//    measured on the wire**, or the UI shows a figure no code honours"
//
// The block share of every duration shown here fell out of exactly this number
// (`media_send_estimate.dart`, item 2). To this day it is measured only
// LOCALLY: 82 000-117 000 cells/s on the workshop machine, i.e.
// 2 560 times the document number — what the NETWORK carries is explicitly
// unknown (S363, `docs/v4-redesign/S363-messungen-bulk-und-mobilanteil.md`,
// section 2.1/2.2). A number from an unmeasured rate looks in
// a consent dialog like a promise and is none.
//
// On 03.09.2026 the owner chose option A from 2.4: `R_bulk`
// stays at 32, the TIME INDICATION goes away until a wire measurement
// exists. §24.4.5 ALLOWS a duration for the secure path, does not require
// it — Appendix A forbids it meanwhile. That resolves the contradiction
// without touching the architecture document.
//
// WHAT REMAINS INSTEAD, and it is what §12 requires: the
// linkability statement. The secure button says "takes longer"
// (`media_consent_send_secure`) — a DIRECTION, not a promise —, the
// list of disadvantages names every price of the fast path, and
// `media_consent_difference` says what the difference consists of.
//
// The way back is described and ready: `estimateMediaSend`
// (`lib/core/service/media_send_estimate.dart`) still computes the range
// and has its own guard; since 03.09.2026 it just has no
// display customer any more. When the wire measurement comes
// (`docs/v4-redesign/S363-ARBEITSPAKET-rbulk-drahtmessung.md`),
// this dialog gets its range back — then with a number that someone
// has seen.
//
// ── FIVE i18n KEYS STAY DELIBERATELY UNUSED ─────────────
//
// They are the way back, and they are listed here by name so that the
// next cleanup run does not remove them as ballast (re-measured on
// 2026-09-03 over `lib/ test/ scripts/ assets/ android/ ios/ macos/
// windows/ linux/ proto/ web/ docs/`):
//
//   `media_consent_send_secure_eta`    — 0 calls, only comment mentions
//   `media_consent_send_fast_eta`      — 0 calls, only comment mentions
//   `media_consent_basis`              — 0 calls, only comment mentions
//   `media_consent_egress_note`        — 0 calls, only comment mentions
//   `media_consent_send_secure_range`  — 0 calls in `lib/`; ONE reader in
//                                        `test/smoke/smoke_secure_media_dialog.dart:179`
//
// Each of them costs 34 translations. Re-creating them would
// thus be 34 times the work for something that already exists — and that on the day
// the wire measurement is available. Whoever wants to remove them anyway
// needs an owner decision for it, not a cleanup run.
//
// ── TWO THINGS THIS DIALOG DELIBERATELY DOES NOT SAY ────────────────
//
// 1. "post-quantum secure" as a DIFFERENCE between the two paths.
//
//    Until 31.08.2026 the opposite stood here: the pairwise media path
//    runs only on classical X25519, therefore the dialog must not make a
//    PQ promise for media. **This reasoning is settled, and
//    because the branch itself has fallen** — `BulkTransferKeys
//    .pairwise` no longer exists (`bulk_keys.dart`, header: no
//    PQ coverage, no forward secrecy, a confirmation oracle). The
//    transfer root is now ALWAYS drawn and travels in the offer via the
//    cell path, i.e. under X25519 + ML-KEM-768 (`message_seal.dart:374`).
//
//    Both paths are thus post-quantum covered, and precisely therefore
//    the term no longer serves as a distinction: it would claim a difference
//    that does not exist. The durable distinction is the
//    ANONYMITY (`media_consent_difference`).
//
// 2. "Speed mode" as the label of the fast button. The dialog
//    does not change the CHAT's MODE — `setChatMode` is not
//    touched, and the next message goes via the storage again.
//    It chooses the path for EXACTLY THIS transfer. "Send fast"
//    describes the action, not a mode.

import 'package:flutter/material.dart';

import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/media_send_estimate.dart'
    show MediaConsentResult;

// [MediaConsentResult] and [choiceFrom] live in
// `lib/core/service/media_send_estimate.dart` — the pure file without
// Flutter. Not out of love of order: the statement "a cancel is NOT
// consent" should be checked by a guard, and a smoke test
// runs without Flutter. If the enum stood here, it could not
// import them and would have to SEARCH for them in the source — a
// proxy instead of the statement.

/// Shows the consent question from §9.3 for EXACTLY ONE transfer.
///
/// [isGroup] shows the additional point about the visible
/// members — in the 1:1 case there is only the one recipient, whom the
/// other points already cover.
///
/// **NO estimate as an argument, and that is intentional** (03.09.2026,
/// owner option A on finding B-3): this dialog shows no duration, so
/// it also does not need to have one passed in. A `estimate` parameter
/// still dragged along would be an argument without effect —
/// and the next session would have displayed it again because it was there.
/// The full reasoning is in the file header.
///
/// No `SafeArea` here: this is a dialog, not a Scaffold body, and neither
/// sibling dialog in this directory (`crash_report_dialog.dart`,
/// `pending_security_dialogs.dart`) wraps one either — edge-to-edge only
/// bites full-screen content that scrolls under the system bars.
Future<MediaConsentResult> showMediaConsentDialog({
  required BuildContext context,
  required bool isGroup,
}) async {
  final locale = AppLocale.read(context);

  final result = await showDialog<MediaConsentResult>(
    context: context,
    // An accidental tap outside the dialog must never stand in for a
    // decision — sending a file over the fast lane instead of the secure
    // one is a real, one-shot privacy trade-off (§12 / working rule:
    // "no silent mode switch" applies to the file-level choice too,
    // even though the CHAT's mode itself never changes here).
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(locale.get('media_consent_title')),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(locale.get('media_consent_intro')),
              const SizedBox(height: 12),
              Text(locale.get('media_consent_fast_heading')),
              const SizedBox(height: 8),
              _ConsentPoint(locale.get('media_consent_point_visible')),
              _ConsentPoint(locale.get('media_consent_point_foreign_host')),
              _ConsentPoint(locale.get('media_consent_point_isp')),
              _ConsentPoint(locale.get('media_consent_point_retention')),
              _ConsentPoint(locale.get('media_consent_point_size')),
              if (isGroup) _ConsentPoint(locale.get('media_consent_point_group')),
              const SizedBox(height: 12),
              Text(locale.get('media_consent_closing')),
              const SizedBox(height: 8),
              // THE DURABLE DISTINCTION. It stands DELIBERATELY below the
              // list of disadvantages and not above it: the list is the price,
              // this sentence says what does NOT belong to it.
              Text(locale.get('media_consent_difference')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(MediaConsentResult.cancel),
          child: Text(locale.get('cancel')),
        ),
        // "Send securely (takes longer)" — a DIRECTION, not a number.
        // The number depends on `R_bulk`, and that is unmeasured (file header).
        OutlinedButton(
          onPressed: () => Navigator.of(ctx).pop(MediaConsentResult.sendSecure),
          child: Text(locale.get('media_consent_send_secure')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(MediaConsentResult.sendFast),
          child: Text(locale.get('media_consent_send_fast')),
        ),
      ],
    ),
  );

  return result ?? MediaConsentResult.cancel;
}

/// One numbered consequence in the dialog body.
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
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.circle, size: 6),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
