import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/node/identity_context.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;
import 'package:fixnum/fixnum.dart';

/// Device-published liveness record: aktuelle Adressen + TTL.
/// Ed25519-only signiert (kein PQ — Threat-Modell siehe Spec §3 / Architektur §4).
class LivenessRecord {
  final Uint8List userId;
  final Uint8List deviceNodeId;
  final List<proto.PeerAddressProto> addresses;
  final int ttlSeconds;
  final int sequenceNumber;
  final int publishedAtMs;
  Uint8List ed25519Sig;

  LivenessRecord({
    required this.userId,
    required this.deviceNodeId,
    required this.addresses,
    required this.ttlSeconds,
    required this.sequenceNumber,
    required this.publishedAtMs,
    required this.ed25519Sig,
  });

  Uint8List _bytesToSign() {
    final unsigned = proto.LivenessRecordProto()
      ..userId = userId
      ..deviceNodeId = deviceNodeId
      ..addresses.addAll(addresses)
      ..ttlSeconds = ttlSeconds
      ..sequenceNumber = Int64(sequenceNumber)
      ..publishedAtMs = Int64(publishedAtMs);
    return Uint8List.fromList(unsigned.writeToBuffer());
  }

  static LivenessRecord sign(
    IdentityContext id,
    Uint8List deviceNodeId,
    List<proto.PeerAddressProto> addresses, {
    required int ttlSeconds,
    required int sequenceNumber,
  }) {
    final publishedAtMs = DateTime.now().millisecondsSinceEpoch;
    final r = LivenessRecord(
      userId: id.userId,
      deviceNodeId: deviceNodeId,
      addresses: addresses,
      ttlSeconds: ttlSeconds,
      sequenceNumber: sequenceNumber,
      publishedAtMs: publishedAtMs,
      ed25519Sig: Uint8List(0),
    );
    final dataToSign = r._bytesToSign();
    r.ed25519Sig = SodiumFFI().signEd25519(dataToSign, id.ed25519SecretKey);
    return r;
  }

  bool verify(Uint8List userPubkeyEd25519) {
    // SodiumFFI.verifyEd25519 signature: (message, signature, publicKey)
    return SodiumFFI()
        .verifyEd25519(_bytesToSign(), ed25519Sig, userPubkeyEd25519);
  }

  bool isExpired() {
    final ageMs = DateTime.now().millisecondsSinceEpoch - publishedAtMs;
    return ageMs > ttlSeconds * 1000;
  }

  proto.LivenessRecordProto toProto() {
    return proto.LivenessRecordProto()
      ..userId = userId
      ..deviceNodeId = deviceNodeId
      ..addresses.addAll(addresses)
      ..ttlSeconds = ttlSeconds
      ..sequenceNumber = Int64(sequenceNumber)
      ..publishedAtMs = Int64(publishedAtMs)
      ..ed25519Sig = ed25519Sig;
  }

  static LivenessRecord fromProto(proto.LivenessRecordProto p) {
    return LivenessRecord(
      userId: Uint8List.fromList(p.userId),
      deviceNodeId: Uint8List.fromList(p.deviceNodeId),
      addresses: p.addresses.toList(),
      ttlSeconds: p.ttlSeconds,
      sequenceNumber: p.sequenceNumber.toInt(),
      publishedAtMs: p.publishedAtMs.toInt(),
      ed25519Sig: Uint8List.fromList(p.ed25519Sig),
    );
  }
}
