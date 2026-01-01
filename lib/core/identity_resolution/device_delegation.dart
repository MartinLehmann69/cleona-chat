// §7.1 LD-1: Linked-Device Delegation Certificate.
//
// Authorizes a Linked Device to sign ApplicationFrames on behalf of the user
// identity using a per-device delegated Sig-Key. The certificate is embedded
// in the AuthManifest (field 11) and hybrid-signed by the User-Key.
//
// Key derivation (Primary-side, at pairing time):
//   delegated_ed25519_seed = HKDF-SHA256(user_ed25519_sk,
//       "cleona-deleg-ed25519-v1" || device_id, 32)
//   delegated_ml_dsa_seed  = HKDF-SHA256(master_seed,
//       "cleona-deleg-mldsa-v1" || device_id, 64)
//
// The delegated keys are deterministic per device_id — Primary can re-derive
// at any time without storing additional state.

import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';

import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

class DeviceDelegation {
  final Uint8List deviceId;
  final Uint8List delegatedEd25519Pk;
  final Uint8List delegatedMlDsaPk;
  final int capabilities;
  final int issuedAtMs;
  final int maxValidUntilMs;
  Uint8List userEd25519Sig;
  Uint8List userMlDsaSig;

  DeviceDelegation({
    required this.deviceId,
    required this.delegatedEd25519Pk,
    required this.delegatedMlDsaPk,
    required this.capabilities,
    required this.issuedAtMs,
    required this.maxValidUntilMs,
    required this.userEd25519Sig,
    required this.userMlDsaSig,
  });

  static const int capSendMessages = 1;
  static const int capManageContacts = 2;
  static const int capManageGroups = 4;
  static const int capManageChannels = 8;
  static const int capAllStandard = 15;

  bool hasCapability(int cap) => (capabilities & cap) == cap;

  bool isExpired() {
    if (maxValidUntilMs == 0) return false;
    return DateTime.now().millisecondsSinceEpoch > maxValidUntilMs;
  }

  Uint8List _bytesToSign() {
    final p = proto.DeviceDelegationCertProto()
      ..deviceId = deviceId
      ..delegatedEd25519Pk = delegatedEd25519Pk
      ..delegatedMlDsaPk = delegatedMlDsaPk
      ..capabilities = capabilities
      ..issuedAtMs = Int64(issuedAtMs)
      ..maxValidUntilMs = Int64(maxValidUntilMs)
      // Sig fields excluded from signing (zeroed in proto3 default)
      ;
    return Uint8List.fromList(p.writeToBuffer());
  }

  static DeviceDelegation sign({
    required Uint8List deviceId,
    required Uint8List delegatedEd25519Pk,
    required Uint8List delegatedMlDsaPk,
    required int capabilities,
    required int maxValidUntilMs,
    required Uint8List userEd25519Sk,
    required Uint8List userMlDsaSk,
  }) {
    final issuedAtMs = DateTime.now().millisecondsSinceEpoch;
    final cert = DeviceDelegation(
      deviceId: deviceId,
      delegatedEd25519Pk: delegatedEd25519Pk,
      delegatedMlDsaPk: delegatedMlDsaPk,
      capabilities: capabilities,
      issuedAtMs: issuedAtMs,
      maxValidUntilMs: maxValidUntilMs,
      userEd25519Sig: Uint8List(0),
      userMlDsaSig: Uint8List(0),
    );
    final data = cert._bytesToSign();
    cert.userEd25519Sig = SodiumFFI().signEd25519(data, userEd25519Sk);
    cert.userMlDsaSig = OqsFFI().mlDsaSign(data, userMlDsaSk);
    return cert;
  }

  bool verify(Uint8List userEd25519Pk, Uint8List userMlDsaPk) {
    final data = _bytesToSign();
    final edOk =
        SodiumFFI().verifyEd25519(data, userEd25519Sig, userEd25519Pk);
    if (!edOk) return false;
    return OqsFFI().mlDsaVerify(data, userMlDsaSig, userMlDsaPk);
  }

  proto.DeviceDelegationCertProto toProto() {
    return proto.DeviceDelegationCertProto()
      ..deviceId = deviceId
      ..delegatedEd25519Pk = delegatedEd25519Pk
      ..delegatedMlDsaPk = delegatedMlDsaPk
      ..capabilities = capabilities
      ..issuedAtMs = Int64(issuedAtMs)
      ..maxValidUntilMs = Int64(maxValidUntilMs)
      ..userEd25519Sig = userEd25519Sig
      ..userMlDsaSig = userMlDsaSig;
  }

  static DeviceDelegation fromProto(proto.DeviceDelegationCertProto p) {
    return DeviceDelegation(
      deviceId: Uint8List.fromList(p.deviceId),
      delegatedEd25519Pk: Uint8List.fromList(p.delegatedEd25519Pk),
      delegatedMlDsaPk: Uint8List.fromList(p.delegatedMlDsaPk),
      capabilities: p.capabilities,
      issuedAtMs: p.issuedAtMs.toInt(),
      maxValidUntilMs: p.maxValidUntilMs.toInt(),
      userEd25519Sig: Uint8List.fromList(p.userEd25519Sig),
      userMlDsaSig: Uint8List.fromList(p.userMlDsaSig),
    );
  }

  Uint8List toProtoBytes() => toProto().writeToBuffer();

  static DeviceDelegation fromProtoBytes(Uint8List bytes) =>
      fromProto(proto.DeviceDelegationCertProto.fromBuffer(bytes));
}

