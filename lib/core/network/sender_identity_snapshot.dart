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
  final Uint8List senderDeviceId;

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
