// §7.5 Device Co-Authorization for Emergency Key Rotation.
//
// Device-Sig keys are locally generated (NOT seed-derived). A seed thief
// cannot forge Device-Sig countersigs. Contacts verify rotation broadcasts
// against the Device-Sig pubkeys cached from the pre-rotation AuthManifest.

import 'dart:typed_data';

import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Device-Sig pubkeys for one authorized device (AuthManifest field 12).
class DeviceSigInfo {
  final Uint8List deviceNodeId;
  final Uint8List deviceEd25519Pk;
  final Uint8List deviceMlDsaPk;
  final bool isPrimary;

  DeviceSigInfo({
    required this.deviceNodeId,
    required this.deviceEd25519Pk,
    required this.deviceMlDsaPk,
    required this.isPrimary,
  });

  proto.AuthorizedDeviceSigningKeys toProto() {
    return proto.AuthorizedDeviceSigningKeys()
      ..deviceNodeId = deviceNodeId
      ..deviceEd25519Pk = deviceEd25519Pk
      ..deviceMlDsaPk = deviceMlDsaPk
      ..isPrimary = isPrimary;
  }

  static DeviceSigInfo fromProto(proto.AuthorizedDeviceSigningKeys p) {
    return DeviceSigInfo(
      deviceNodeId: Uint8List.fromList(p.deviceNodeId),
      deviceEd25519Pk: Uint8List.fromList(p.deviceEd25519Pk),
      deviceMlDsaPk: Uint8List.fromList(p.deviceMlDsaPk),
      isPrimary: p.isPrimary,
    );
  }
}

/// A single device's countersig on a rotation (KeyRotationBroadcast field 7).
class RotationApprovalToken {
  final Uint8List deviceNodeId;
  final Uint8List rotationHash;
  final Uint8List deviceEd25519Sig;
  final Uint8List deviceMlDsaSig;

  RotationApprovalToken({
    required this.deviceNodeId,
    required this.rotationHash,
    required this.deviceEd25519Sig,
    required this.deviceMlDsaSig,
  });

  bool verify(Uint8List deviceEd25519Pk, Uint8List deviceMlDsaPk) {
    final edOk = SodiumFFI().verifyEd25519(
        rotationHash, deviceEd25519Sig, deviceEd25519Pk);
    if (!edOk) return false;
    return OqsFFI().mlDsaVerify(
        rotationHash, deviceMlDsaSig, deviceMlDsaPk);
  }

  proto.RotationApprovalToken toProto() {
    return proto.RotationApprovalToken()
      ..deviceNodeId = deviceNodeId
      ..rotationHash = rotationHash
      ..deviceEd25519Sig = deviceEd25519Sig
      ..deviceMlDsaSig = deviceMlDsaSig;
  }

  static RotationApprovalToken fromProto(proto.RotationApprovalToken p) {
    return RotationApprovalToken(
      deviceNodeId: Uint8List.fromList(p.deviceNodeId),
      rotationHash: Uint8List.fromList(p.rotationHash),
      deviceEd25519Sig: Uint8List.fromList(p.deviceEd25519Sig),
      deviceMlDsaSig: Uint8List.fromList(p.deviceMlDsaSig),
    );
  }
}

/// Proof that a device-set shrink was co-authorized (AuthManifest field 13).
class DeviceSetChangeProof {
  final int previousDeviceCount;
  final Uint8List changeHash;
  final List<RotationApprovalToken> approvals;

  DeviceSetChangeProof({
    required this.previousDeviceCount,
    required this.changeHash,
    required this.approvals,
  });

  proto.DeviceSetChangeProof toProto() {
    return proto.DeviceSetChangeProof()
      ..previousDeviceCount = previousDeviceCount
      ..changeHash = changeHash
      ..approvals.addAll(approvals.map((a) => a.toProto()));
  }

  static DeviceSetChangeProof fromProto(proto.DeviceSetChangeProof p) {
    return DeviceSetChangeProof(
      previousDeviceCount: p.previousDeviceCount,
      changeHash: Uint8List.fromList(p.changeHash),
      approvals:
          p.approvals.map(RotationApprovalToken.fromProto).toList(),
    );
  }
}

/// Compute the canonical rotation hash for co-auth verification.
Uint8List computeRotationHash({
  required Uint8List newEd25519Pk,
  required Uint8List newMlDsaPk,
  required Uint8List newX25519Pk,
  required Uint8List newMlKemPk,
  required Uint8List userId,
}) {
  final buf = BytesBuilder(copy: false)
    ..add(newEd25519Pk)
    ..add(newMlDsaPk)
    ..add(newX25519Pk)
    ..add(newMlKemPk)
    ..add(userId);
  return SodiumFFI().sha256(buf.toBytes());
}

/// Compute the canonical device-set change hash.
Uint8List computeDeviceSetChangeHash({
  required Uint8List userId,
  required List<Uint8List> newDeviceNodeIds,
  required int newSeq,
}) {
  final sorted = List<Uint8List>.from(newDeviceNodeIds)
    ..sort((a, b) {
      for (var i = 0; i < a.length && i < b.length; i++) {
        if (a[i] != b[i]) return a[i].compareTo(b[i]);
      }
      return a.length.compareTo(b.length);
    });
  final buf = BytesBuilder(copy: false)..add(userId);
  for (final id in sorted) {
    buf.add(id);
  }
  final seqBytes = ByteData(4)..setUint32(0, newSeq, Endian.little);
  buf.add(seqBytes.buffer.asUint8List());
  return SodiumFFI().sha256(buf.toBytes());
}

/// Minimum countersigs required for an Emergency KEY ROTATION over [
/// totalDevices] devices — every device of the identity survives a key
/// rotation, so "total" and "remaining" are the same set here.
///
/// N=1 → 0 (single device, no co-auth possible).
/// N>=2 → max(2, ceil(N/2)) — at least Primary + 1 Linked.
///
/// UNCHANGED ON PURPOSE. [deviceSetChangeQuorum] relaxes the floor of 2 for
/// its own case only; applying that relaxation here would let a stolen Primary
/// of a two-device identity rotate the User keys on its own signature alone,
/// which is precisely the attack §7.5 was written against.
int rotationQuorum(int totalDevices) {
  if (totalDevices <= 1) return 0;
  final half = (totalDevices + 1) ~/ 2; // ceil(N/2)
  return half < 2 ? 2 : half;
}

/// Minimum countersigs required for a DEVICE-SET CHANGE, counted over the
/// devices that REMAIN after the change.
///
/// WHY THIS IS NOT [rotationQuorum]. A device-set change is the one co-auth
/// occasion whose signer set shrinks with the event being authorised. Charging
/// it `max(2, …)` over the pre-change count made it unsatisfiable in the most
/// common multi-device setup there is: removing one of two devices leaves ONE
/// device, and one device cannot produce two countersignatures. The proof was
/// therefore never constructible for N_pre=2 — the mechanism was dead exactly
/// where users meet it first.
///
/// Counting over the remainder fixes that without inventing a signature: with
/// one device left, that device's own consent IS the complete set of consents
/// obtainable, and it is what the receiver can verify against the pubkeys
/// cached from the PRE-change manifest. What this cannot do — and does not
/// claim to do — is protect a two-device identity against the theft of one of
/// its two devices: the survivor is then the thief's device. That limit is
/// inherent to the situation, not to the formula; no quorum over one signer
/// can distinguish the two cases.
///
/// M=0 → 0 (nothing left that could sign).
/// M=1 → 1 (the sole survivor's consent).
/// M>=2 → max(2, ceil(M/2)) — same shape as [rotationQuorum].
int deviceSetChangeQuorum(int remainingDevices) {
  if (remainingDevices <= 0) return 0;
  if (remainingDevices == 1) return 1;
  final half = (remainingDevices + 1) ~/ 2; // ceil(M/2)
  return half < 2 ? 2 : half;
}

/// Which of the two §7.5 occasions a set of approval tokens belongs to.
/// Decides the denominator of the quorum — see [verifyRotationCoAuth].
enum CoAuthOccasion {
  /// Emergency Key Rotation: quorum over the full device set
  /// ([rotationQuorum]).
  keyRotation,

  /// Device-set change: quorum over the remaining devices
  /// ([deviceSetChangeQuorum]).
  deviceSetChange,
}

/// Result of verifying rotation co-authorization.
enum RotationCoAuthResult {
  /// Quorum met — standard Key-Change-Detection applies.
  quorumMet,
  /// Quorum NOT met — elevated warning (possible Primary theft).
  quorumNotMet,
  /// No tokens present — legacy sender, standard Key-Change-Detection.
  legacy,
  /// Single-device identity — no co-auth expected.
  singleDevice,
}

/// Verify approval tokens against cached Device-Sig pubkeys.
///
/// [cachedDeviceSigKeys] is always the PRE-change set — the pubkeys the
/// receiver had before this manifest/broadcast arrived. Tokens are only ever
/// counted against those, for both occasions: the keys carried by the incoming
/// record are asserted by the very sender under suspicion, so verifying
/// against them would let anyone who can write a manifest also nominate its
/// approvers.
///
/// [occasion] selects the DENOMINATOR of the quorum, and only that:
///  * [CoAuthOccasion.keyRotation] — [rotationQuorum] over
///    `cachedDeviceSigKeys.length`. Every device survives a key rotation, so
///    the pre-change count is also the set that could have signed.
///  * [CoAuthOccasion.deviceSetChange] — [deviceSetChangeQuorum] over
///    [remainingDeviceCount], the number of devices left AFTER the change.
///    Devices that were just removed obviously cannot be required to consent
///    to their own removal, and demanding two signatures from a one-device
///    remainder made the proof unbuildable (see [deviceSetChangeQuorum]).
///
/// [remainingDeviceCount] is ignored for [CoAuthOccasion.keyRotation]. It must
/// be the count of devices in the incoming record that are able to
/// countersign, i.e. its `device_sig_keys` length — the sender computes its
/// quorum from the same quantity, so both sides agree without transmitting it.
///
/// (This replaces the former `preRotationDeviceCount` parameter, which was
/// never read in the body: callers passed a number that had no effect on the
/// result, so the quorum silently ran over the cached count in every case.)
RotationCoAuthResult verifyRotationCoAuth({
  required List<RotationApprovalToken> tokens,
  required List<DeviceSigInfo> cachedDeviceSigKeys,
  required Uint8List rotationHash,
  CoAuthOccasion occasion = CoAuthOccasion.keyRotation,
  int remainingDeviceCount = 0,
}) {
  if (cachedDeviceSigKeys.isEmpty) return RotationCoAuthResult.legacy;
  final n = cachedDeviceSigKeys.length;
  if (n <= 1) return RotationCoAuthResult.singleDevice;
  if (tokens.isEmpty) return RotationCoAuthResult.quorumNotMet;

  final required = occasion == CoAuthOccasion.deviceSetChange
      ? deviceSetChangeQuorum(remainingDeviceCount)
      : rotationQuorum(n);
  // Count DISTINCT signing devices, not valid tokens. The quorum asks "how
  // many devices consented"; a plain token counter answers "how many valid
  // signatures were attached", and those differ by exactly the repetition an
  // attacker controls. Whoever holds ONE device's Device-Sig key can list its
  // token twice and clear a quorum of 2 — the entire mechanism, for both
  // occasions, with a single stolen device. The signature is genuine each
  // time, so nothing else in this function would notice.
  final approvers = <String>{};
  for (final token in tokens) {
    final deviceHex = _bytesToHex(token.deviceNodeId);
    if (approvers.contains(deviceHex)) continue;
    final info = cachedDeviceSigKeys
        .where((d) => _bytesToHex(d.deviceNodeId) == deviceHex)
        .firstOrNull;
    if (info == null) continue;
    if (!_bytesEqual(token.rotationHash, rotationHash)) continue;
    if (token.verify(info.deviceEd25519Pk, info.deviceMlDsaPk)) {
      approvers.add(deviceHex);
    }
  }
  return approvers.length >= required
      ? RotationCoAuthResult.quorumMet
      : RotationCoAuthResult.quorumNotMet;
}

String _bytesToHex(Uint8List bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
