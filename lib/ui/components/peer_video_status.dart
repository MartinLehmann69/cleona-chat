// lib/ui/components/peer_video_status.dart
//
// V1.6 — renders what the peer last announced about *its own* video
// (§10.6, V1.12 `CALL_MEDIA_STATE`, Spec-Erratum E2:
// docs/SPEC_VOICE_VIDEO_REWORK.md §13).
//
// Erratum E2's whole point is that "no picture from the peer" is not one
// fact, it is (at least) three different ones, and they must not look the
// same:
//   - the peer switched their own camera off on purpose
//     ([CallVideoOffReason.userDisabled]),
//   - the peer's network cannot carry video right now
//     ([CallVideoOffReason.bandwidthInsufficient]) — a fact about the
//     network, not a choice, and rendering it identically to the first case
//     would tell the user the peer chose silence when they did not,
//   - or this build does not know why ([CallVideoOffReason.unspecified]) —
//     kept distinct from "user disabled" on purpose: claiming intent for a
//     reason we could not read would state a fact we do not have.
//
// [PeerVideoOffOverlay] below maps each reason to its own icon, color and
// text — mapping bandwidthInsufficient and userDisabled onto the same text
// is exactly the defect this file exists to prevent (see the negative
// control in test/smoke/smoke_peer_video_status.dart).
//
// **I12 stays intact.** This widget only ever displays what the peer
// volunteered about *its own* transmission. There is nothing here — and
// nothing may be added here — that reads as a control reaching the peer's
// camera.
import 'package:flutter/material.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/cleona_service.dart' show CallVideoOffReason;

/// Full-bleed placeholder shown in the remote-video area while the peer has
/// announced `sendingVideo == false` for the active call.
///
/// Deliberately stateless and self-contained (icon+text+color only, no
/// network access) so it can be smoke-tested with `flutter test` against
/// all three [CallVideoOffReason] values without a live call — see
/// `test/smoke/smoke_peer_video_status.dart`.
class PeerVideoOffOverlay extends StatelessWidget {
  final CallVideoOffReason reason;

  const PeerVideoOffOverlay({super.key, required this.reason});

  /// Neutral — the peer made a deliberate choice, not a fault.
  static const neutralColor = Colors.white70;

  /// Distinct from [neutralColor] on purpose (E2): a network fact reads
  /// differently from a user choice.
  static const bandwidthColor = Colors.amberAccent;

  IconData get icon {
    switch (reason) {
      case CallVideoOffReason.userDisabled:
        return Icons.videocam_off;
      case CallVideoOffReason.bandwidthInsufficient:
        // Distinct glyph from videocam_off (E2) — a connectivity symbol,
        // not a camera symbol, because the camera is not the problem.
        return Icons.signal_cellular_connected_no_internet_4_bar;
      case CallVideoOffReason.unspecified:
        return Icons.videocam_off_outlined;
    }
  }

  Color get color {
    switch (reason) {
      case CallVideoOffReason.bandwidthInsufficient:
        return bandwidthColor;
      case CallVideoOffReason.userDisabled:
      case CallVideoOffReason.unspecified:
        return neutralColor;
    }
  }

  /// i18n key for [reason] — kept as a separate, table-driven getter (rather
  /// than folded into [build]) so a smoke test can assert the three keys are
  /// pairwise distinct without pumping a widget tree.
  String i18nKey(CallVideoOffReason r) {
    switch (r) {
      case CallVideoOffReason.userDisabled:
        return 'call_video_off_by_user';
      case CallVideoOffReason.bandwidthInsufficient:
        return 'call_video_off_bandwidth';
      case CallVideoOffReason.unspecified:
        return 'call_video_off_unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.of(context);
    final text = locale.get(i18nKey(reason));
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(color: color, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
