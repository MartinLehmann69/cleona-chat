// §7.1 LD-2: Linked-Device Pairing Service.
//
// Implements the new pairing flow where the Primary device issues a
// DeviceDelegationCert + delegated sig keys + User-KEM-SK to the new device,
// WITHOUT transferring the master seed.
//
// Flow:
//   1. Primary shows QR: {userId, pairToken (5min expiry)}
//   2. New device scans QR, generates Device-Sig keys, sends DEVICE_PAIR_REQUEST
//   3. Primary receives request, derives delegated keys, builds DevicePairApproveV3
//   4. Primary sends DEVICE_PAIR_APPROVE (KEM-encrypted to new device)
//   5. Primary updates AuthManifest with new device + delegation cert
//   6. New device receives approval, stores delegated keys, starts participating

import 'dart:typed_data';

import 'package:cleona/core/crypto/hd_wallet.dart';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/identity_resolution/device_delegation.dart';
import 'package:cleona/core/identity_resolution/linked_device_keys.dart';
import 'package:cleona/core/node/identity_context.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

class DevicePairingResult {
  final DeviceDelegation delegationCert;
  final proto.DevicePairApproveV3 approvePayload;

  DevicePairingResult({
    required this.delegationCert,
    required this.approvePayload,
  });
}

class DevicePairingService {

  /// Called on the PRIMARY device when a DEVICE_PAIR_REQUEST arrives.
  /// Derives delegated keys, signs the delegation cert, and builds the
  /// approval payload to send back (KEM-encrypted by the caller).
  ///
  /// [identity] must have a non-null masterSeed (= this is the Primary).
  /// [newDeviceId] is the requesting device's node-ID.
  /// [capabilities] defaults to all standard capabilities.
  /// [maxValidDays] sets the dead-man-switch expiry (0 = no expiry).
  DevicePairingResult buildApproval({
    required IdentityContext identity,
    required Uint8List newDeviceId,
    int capabilities = DeviceDelegation.capAllStandard,
    int maxValidDays = 30,
  }) {
    final masterSeed = identity.masterSeed;
    if (masterSeed == null) {
      throw StateError(
          'Cannot pair: this device does not hold the master seed (not Primary)');
    }

    // 1. Derive delegated Ed25519 sig keypair for this device
    final delegEd = HdWallet.deriveDelegatedEd25519(masterSeed, newDeviceId);

    // 2. Derive deterministic ML-DSA delegation keypair from HKDF seed.
    final mlDsaSeed =
        HdWallet.deriveDelegatedMlDsaSeed(masterSeed, newDeviceId);
    final oqs = OqsFFI();
    final delegMlDsa = oqs.mlDsaKeypairDerand(mlDsaSeed);

    // 3. Sign the delegation certificate
    final maxValidUntilMs = maxValidDays > 0
        ? DateTime.now().millisecondsSinceEpoch +
            maxValidDays * 24 * 60 * 60 * 1000
        : 0;

    final cert = DeviceDelegation.sign(
      deviceId: newDeviceId,
      delegatedEd25519Pk: delegEd.publicKey,
      delegatedMlDsaPk: delegMlDsa.publicKey,
      capabilities: capabilities,
      maxValidUntilMs: maxValidUntilMs,
      userEd25519Sk: identity.ed25519SecretKey,
      userMlDsaSk: identity.mlDsaSecretKey,
    );

    // 4. Build the approval payload
    final approve = proto.DevicePairApproveV3()
      ..delegatedEd25519Pk = delegEd.publicKey
      ..delegatedEd25519Sk = delegEd.secretKey
      ..delegatedMlDsaPk = delegMlDsa.publicKey
      ..delegatedMlDsaSk = delegMlDsa.secretKey
      ..userX25519Sk = identity.x25519SecretKey
      ..userMlKemSk = identity.mlKemSecretKey
      ..delegationCert = cert.toProto()
      ..userId = identity.userId
      ..displayName = identity.displayName;

    return DevicePairingResult(
      delegationCert: cert,
      approvePayload: approve,
    );
  }

  /// Called on the LINKED device when DEVICE_PAIR_APPROVE is received.
  /// Returns the parsed delegation material for storage.
  LinkedDeviceKeys parseApproval(proto.DevicePairApproveV3 approve) {
    return LinkedDeviceKeys(
      delegatedEd25519Pk: Uint8List.fromList(approve.delegatedEd25519Pk),
      delegatedEd25519Sk: Uint8List.fromList(approve.delegatedEd25519Sk),
      delegatedMlDsaPk: Uint8List.fromList(approve.delegatedMlDsaPk),
      delegatedMlDsaSk: Uint8List.fromList(approve.delegatedMlDsaSk),
      userX25519Sk: Uint8List.fromList(approve.userX25519Sk),
      userMlKemSk: Uint8List.fromList(approve.userMlKemSk),
      delegationCert: DeviceDelegation.fromProto(approve.delegationCert),
      userId: Uint8List.fromList(approve.userId),
      displayName: approve.displayName,
    );
  }
}

