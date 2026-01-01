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

/// Minimum countersigs required for a given device count.
/// N=1 → 0 (single device, no co-auth possible).
/// N>=2 → max(2, ceil(N/2)) — at least Primary + 1 Linked.
int rotationQuorum(int totalDevices) {
  if (totalDevices <= 1) return 0;
  final half = (totalDevices + 1) ~/ 2; // ceil(N/2)
  return half < 2 ? 2 : half;
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

/// Verify rotation approval tokens against cached Device-Sig pubkeys.
RotationCoAuthResult verifyRotationCoAuth({
  required List<RotationApprovalToken> tokens,
  required List<DeviceSigInfo> cachedDeviceSigKeys,
  required Uint8List rotationHash,
  required int preRotationDeviceCount,
}) {
  if (cachedDeviceSigKeys.isEmpty) return RotationCoAuthResult.legacy;
  final n = cachedDeviceSigKeys.length;
  if (n <= 1) return RotationCoAuthResult.singleDevice;
  if (tokens.isEmpty) return RotationCoAuthResult.quorumNotMet;

  final required = rotationQuorum(n);
  var valid = 0;
  for (final token in tokens) {
    final deviceHex = _bytesToHex(token.deviceNodeId);
    final info = cachedDeviceSigKeys
        .where((d) => _bytesToHex(d.deviceNodeId) == deviceHex)
        .firstOrNull;
    if (info == null) continue;
    if (!_bytesEqual(token.rotationHash, rotationHash)) continue;
    if (token.verify(info.deviceEd25519Pk, info.deviceMlDsaPk)) {
      valid++;
    }
  }
  return valid >= required
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
