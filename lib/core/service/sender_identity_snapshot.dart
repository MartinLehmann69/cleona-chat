// MOVED ON 2026-08-31 (CUT, step 0) from
// `lib/core/network/sender_identity_snapshot.dart`.
//
// WHY THE FILE BELONGS HERE. It is a pure value object: its
// only import is `dart:typed_data`, it opens no socket, it
// knows no packet format, it holds no transport state. The
// relation to the network layer was exclusively the folder name.
//
// The price of this folder name was measurable. Six files outside the
// V3 tree imported it — `service/harvest_event.dart`,
// `service/node_host.dart`, `service/channel_moderation_service.dart`,
// `service/poll_service.dart`, `service/cleona_service.dart` and
// `platform/ios_background_fetch.dart` — and each of these imports counted
// as an edge of the application layer onto `lib/core/network/`. Six of 89
// edges for a class that needs nothing from the network layer.
//
// It goes to `lib/core/service/` because its readers sit there: five of the
// six are already in this directory, and the sixth
// (`ios_background_fetch.dart`) talks to them via `NodeHost`. The
// producer — the V3 receive path in `lib/core/node/cleona_node.dart` — is
// the exception, and that is the right direction: the network layer delivers
// to the service layer, not the other way round.
//
// WHAT IT IS NOT: a V4.1 class. `outerSigStatus` describes step
// §2.4 [4] of the V3 receive, and `senderDeviceId` is a V3 PACKET field without
// a counterpart on the tagline (§14.2, see the comment on the field itself).
// The file moves with the V3 receive path, it is not freed
// from it. Its deletion belongs in a later step of the CUT, not
// in step 0 — step 0 moves and switches over.

import 'dart:typed_data';

/// V3.0 §2.4.0 — Sender Identity Snapshot.
///
/// Captures the outcome of step §2.4 [4] (Outer Device-Sig-Verify) at the
/// receive boundary and is threaded through the inner-frame pipeline. Type-
/// specific handlers consult `outerSigStatus` to gate trust-elevating
/// actions (Re-Contact-Auto-Overwrite, key replace) per §8.1 / §6.3.
///
/// Per-packet ephemeral — never persisted.
class SenderIdentitySnapshot {
  /// Wire-level senderDeviceId from `NetworkPacketV3.senderDeviceId`.
  ///
  /// **Optional, and honestly so since S351.** This is a V3 PACKET field.
  /// The V4.1 delivery path has no device level (§14.2: "One delivery serves
  /// all devices. The delivery path has **no device level**"), so there
  /// is nothing there that could stand here. Until S351 this place held
  /// a `Uint8List(0)` — a placeholder that looks like a value.
  ///
  /// `null` means: no packet, no device. S349 already did the same cleanup
  /// for `HarvestEvent.senderDeviceId` (B-32); this here was
  /// the last remaining instance of the same pattern. Safe, because the field
  /// has **not a single reader** outside this class (counted
  /// over `lib/`: the three V3 paths set it, nobody reads it).
  final Uint8List? senderDeviceId;

  /// Wire-level senderUserId from `ApplicationFrameV3.senderUserId`.
  /// Empty for `InfrastructureFrame` (no user-identity claim).
  final Uint8List senderUserId;

  /// Outcome of step §2.4 [4].
  final OuterSigStatus outerSigStatus;

  /// Populated iff `outerSigStatus == verified`.
  final Uint8List? verifiedDeviceEd25519Pk;
  final Uint8List? verifiedDeviceMlDsaPk;

  /// True iff the sender's `senderUserId` was previously known with
  /// different user-pubkeys. Set best-effort by inner handlers; the receive
  /// pipeline cannot determine this before user-sig-verify.
  final bool newKeyDetectedForSenderUser;

  /// Wall-clock at packet arrival, post timestamp-window pass.
  final DateTime receivedAt;

  const SenderIdentitySnapshot({
    required this.senderDeviceId,
    required this.senderUserId,
    required this.outerSigStatus,
    required this.verifiedDeviceEd25519Pk,
    required this.verifiedDeviceMlDsaPk,
    required this.newKeyDetectedForSenderUser,
    required this.receivedAt,
  });

  /// Convenience for handlers that only care whether the outer authentic-
  /// ation produced a verified Device-Sig-Pubkey.
  bool get isOuterVerified => outerSigStatus == OuterSigStatus.verified;

  /// Returns a copy with `newKeyDetectedForSenderUser` toggled. Used by
  /// the bridge layer once it has compared the inner-claimed
  /// `senderUserId` against the contact-store entry.
  SenderIdentitySnapshot withNewKeyDetected(bool detected) {
    return SenderIdentitySnapshot(
      senderDeviceId: senderDeviceId,
      senderUserId: senderUserId,
      outerSigStatus: outerSigStatus,
      verifiedDeviceEd25519Pk: verifiedDeviceEd25519Pk,
      verifiedDeviceMlDsaPk: verifiedDeviceMlDsaPk,
      newKeyDetectedForSenderUser: detected,
      receivedAt: receivedAt,
    );
  }

  /// Returns a copy with `senderUserId` replaced. Used post-inner-decap
  /// to attach the inner-claimed userId for downstream handlers that
  /// were given an InfrastructureFrame snapshot first.
  SenderIdentitySnapshot withSenderUserId(Uint8List userId) {
    return SenderIdentitySnapshot(
      senderDeviceId: senderDeviceId,
      senderUserId: userId,
      outerSigStatus: outerSigStatus,
      verifiedDeviceEd25519Pk: verifiedDeviceEd25519Pk,
      verifiedDeviceMlDsaPk: verifiedDeviceMlDsaPk,
      newKeyDetectedForSenderUser: newKeyDetectedForSenderUser,
      receivedAt: receivedAt,
    );
  }
}

/// Status semantics from §2.4.0:
///
/// - `verified`: step [4] passed against routing-table pubkey. Standard.
/// - `skippedBootstrap`: no pubkey on file (first contact / fresh routing
///   table). Inner handlers MUST verify all inner-auth strictly. NO auto-
///   trust actions.
/// - `skippedWhitelist`: reserved for forward compatibility. V3.0 Welle 6
///   chose Variant B (InfrastructureFrame migration) over Pre-Verify
///   whitelist; this status is currently unreachable.
enum OuterSigStatus {
  verified,
  skippedBootstrap,
  skippedWhitelist,
}
