import 'dart:typed_data';

import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/node/identity_context.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;
import 'package:fixnum/fixnum.dart';

/// User-signed manifest deklarierend, welche Devices zu einem User gehoeren.
/// Hybrid-signiert (Ed25519 + ML-DSA-65) fuer PQ-Sicherheit. Langlebig (24h).
class AuthManifest {
  final Uint8List userId;
  final List<Uint8List> authorizedDeviceNodeIds;
  final int ttlSeconds;
  final int sequenceNumber;
  final int publishedAtMs;
  Uint8List ed25519Sig;
  Uint8List mlDsaSig;

  AuthManifest({
    required this.userId,
    required this.authorizedDeviceNodeIds,
    required this.ttlSeconds,
    required this.sequenceNumber,
    required this.publishedAtMs,
    required this.ed25519Sig,
    required this.mlDsaSig,
  });

  /// Build canonical bytes-to-sign: deterministische Serialisierung WITHOUT
  /// signature fields. Signing-side and verifying-side muessen denselben Pfad
  /// nehmen, sonst stimmen die Sigs nicht ueberein.
  Uint8List _bytesToSign() {
    final unsigned = proto.AuthManifestProto()
      ..userId = userId
      ..authorizedDeviceNodeIds.addAll(authorizedDeviceNodeIds)
      ..ttlSeconds = ttlSeconds
      ..sequenceNumber = Int64(sequenceNumber)
      ..publishedAtMs = Int64(publishedAtMs);
    return Uint8List.fromList(unsigned.writeToBuffer());
  }

  static AuthManifest sign(
    IdentityContext id,
    List<Uint8List> devices, {
    required int ttlSeconds,
    required int sequenceNumber,
  }) {
    final publishedAtMs = DateTime.now().millisecondsSinceEpoch;
    final m = AuthManifest(
      userId: id.userId,
      authorizedDeviceNodeIds: devices,
      ttlSeconds: ttlSeconds,
      sequenceNumber: sequenceNumber,
      publishedAtMs: publishedAtMs,
      ed25519Sig: Uint8List(0),
      mlDsaSig: Uint8List(0),
    );
    final dataToSign = m._bytesToSign();
    m.ed25519Sig = SodiumFFI().signEd25519(dataToSign, id.ed25519SecretKey);
    m.mlDsaSig = OqsFFI().mlDsaSign(dataToSign, id.mlDsaSecretKey);
    return m;
  }

  bool verify(Uint8List userPubkeyEd25519, Uint8List userPubkeyMlDsa) {
    final dataToSign = _bytesToSign();
    // SodiumFFI.verifyEd25519 signature: (message, signature, publicKey)
    final edOk =
        SodiumFFI().verifyEd25519(dataToSign, ed25519Sig, userPubkeyEd25519);
    if (!edOk) return false;
    // OqsFFI.mlDsaVerify signature: (message, signature, publicKey)
    final mlOk =
        OqsFFI().mlDsaVerify(dataToSign, mlDsaSig, userPubkeyMlDsa);
    return mlOk;
  }

  bool isExpired() {
    final ageMs = DateTime.now().millisecondsSinceEpoch - publishedAtMs;
    return ageMs > ttlSeconds * 1000;
  }

  proto.AuthManifestProto toProto() {
    return proto.AuthManifestProto()
      ..userId = userId
      ..authorizedDeviceNodeIds.addAll(authorizedDeviceNodeIds)
      ..ttlSeconds = ttlSeconds
      ..sequenceNumber = Int64(sequenceNumber)
      ..publishedAtMs = Int64(publishedAtMs)
      ..ed25519Sig = ed25519Sig
      ..mlDsaSig = mlDsaSig;
  }

  static AuthManifest fromProto(proto.AuthManifestProto p) {
    return AuthManifest(
      userId: Uint8List.fromList(p.userId),
      authorizedDeviceNodeIds: p.authorizedDeviceNodeIds
          .map((e) => Uint8List.fromList(e))
          .toList(),
      ttlSeconds: p.ttlSeconds,
      sequenceNumber: p.sequenceNumber.toInt(),
      publishedAtMs: p.publishedAtMs.toInt(),
      ed25519Sig: Uint8List.fromList(p.ed25519Sig),
      mlDsaSig: Uint8List.fromList(p.mlDsaSig),
    );
  }
}
