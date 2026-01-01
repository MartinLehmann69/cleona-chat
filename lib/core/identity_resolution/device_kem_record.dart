import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;
import 'package:fixnum/fixnum.dart';

/// User-signed Device-KEM-Record fuer den 2D-DHT-Lookup (Welle 5, §3.5b + §4.3).
///
/// Traegt die Device-KEM-Pubkeys (X25519 + ML-KEM-768), die Sender brauchen
/// um InfrastructureFrameV3 (und spaeter ONION_LAYER) gegen das Empfaenger-
/// Geraet zu encappen. Lebenszyklus ist langsam (Multi-Year-Cadence,
/// gleicher Trust-Anchor wie AuthManifestV3): Republish alle 20h, TTL 24h.
///
/// **Wichtig**: Signatur kommt vom **User-Master-Ed25519-Key** (nicht vom
/// Device-Key!). Damit teilt sich dieser Record dieselbe Trust-Chain wie
/// AuthManifestV3 — der User vouches fuer die Device-KEM-PK seines
/// authorisierten Geraets. ML-DSA wird hier bewusst NICHT mitgesigned: das
/// Trust-Modell ist dasselbe wie LivenessRecordV3 (Ed25519-only, das
/// Empfaenger-Endgeraet baut nach Auth-Verify ein eigenes Vertrauen auf).
class DeviceKemRecord {
  final Uint8List userId;
  final Uint8List deviceId;
  final Uint8List deviceX25519Pk;
  final Uint8List deviceMlKemPk;
  final int ttlSeconds;
  final int sequenceNumber;
  final int publishedAtMs;
  final Uint8List userEd25519Pk;
  Uint8List ed25519Sig;

  DeviceKemRecord({
    required this.userId,
    required this.deviceId,
    required this.deviceX25519Pk,
    required this.deviceMlKemPk,
    required this.ttlSeconds,
    required this.sequenceNumber,
    required this.publishedAtMs,
    required this.userEd25519Pk,
    required this.ed25519Sig,
  });

  /// Build canonical bytes-to-sign: deterministische Serialisierung WITHOUT
  /// signature field. Signing-side und verifying-side muessen denselben Pfad
  /// nehmen, sonst stimmen die Sigs nicht ueberein. (Selber Pattern wie
  /// AuthManifest._bytesToSign / LivenessRecord._bytesToSign.)
  Uint8List _bytesToSign() {
    final unsigned = proto.DeviceKemRecordV3()
      ..userId = userId
      ..deviceId = deviceId
      ..deviceX25519Pk = deviceX25519Pk
      ..deviceMlKemPk = deviceMlKemPk
      ..ttlSeconds = Int64(ttlSeconds)
      ..sequenceNumber = Int64(sequenceNumber)
      ..publishedAtMs = Int64(publishedAtMs)
      ..userEd25519Pk = userEd25519Pk;
    return Uint8List.fromList(unsigned.writeToBuffer());
  }

  /// Build + sign mit dem User-Master-Ed25519-Key. Caller liefert die
  /// Device-KEM-Pubkeys (kommen in Welle 5 Teil 2 aus
  /// `lib/core/crypto/device_kem.dart` — Subagent A).
  static DeviceKemRecord sign({
    required Uint8List userId,
    required Uint8List deviceId,
    required Uint8List deviceX25519Pk,
    required Uint8List deviceMlKemPk,
    required Uint8List userEd25519Sk,
    required Uint8List userEd25519Pk,
    required int ttlSeconds,
    required int sequenceNumber,
  }) {
    final publishedAtMs = DateTime.now().millisecondsSinceEpoch;
    final r = DeviceKemRecord(
      userId: userId,
      deviceId: deviceId,
      deviceX25519Pk: deviceX25519Pk,
      deviceMlKemPk: deviceMlKemPk,
      ttlSeconds: ttlSeconds,
      sequenceNumber: sequenceNumber,
      publishedAtMs: publishedAtMs,
      userEd25519Pk: userEd25519Pk,
      ed25519Sig: Uint8List(0),
    );
    final dataToSign = r._bytesToSign();
    r.ed25519Sig = SodiumFFI().signEd25519(dataToSign, userEd25519Sk);
    return r;
  }

  /// Verifizieren der Sig gegen den uebergebenen User-Master-Pubkey. Caller
  /// MUSS den Pubkey aus AuthManifestV3 (oder Contact-Registry) ziehen — hier
  /// nicht aus dem Record, sonst verlieren wir den Trust-Anchor.
  bool verify(Uint8List userPubkeyEd25519) {
    return SodiumFFI()
        .verifyEd25519(_bytesToSign(), ed25519Sig, userPubkeyEd25519);
  }

  bool isExpired() {
    final ageMs = DateTime.now().millisecondsSinceEpoch - publishedAtMs;
    return ageMs > ttlSeconds * 1000;
  }

  proto.DeviceKemRecordV3 toProto() {
    return proto.DeviceKemRecordV3()
      ..userId = userId
      ..deviceId = deviceId
      ..deviceX25519Pk = deviceX25519Pk
      ..deviceMlKemPk = deviceMlKemPk
      ..ttlSeconds = Int64(ttlSeconds)
      ..sequenceNumber = Int64(sequenceNumber)
      ..publishedAtMs = Int64(publishedAtMs)
      ..userEd25519Pk = userEd25519Pk
      ..ed25519Sig = ed25519Sig;
  }

  static DeviceKemRecord fromProto(proto.DeviceKemRecordV3 p) {
    return DeviceKemRecord(
      userId: Uint8List.fromList(p.userId),
      deviceId: Uint8List.fromList(p.deviceId),
      deviceX25519Pk: Uint8List.fromList(p.deviceX25519Pk),
      deviceMlKemPk: Uint8List.fromList(p.deviceMlKemPk),
      ttlSeconds: p.ttlSeconds.toInt(),
      sequenceNumber: p.sequenceNumber.toInt(),
      publishedAtMs: p.publishedAtMs.toInt(),
      userEd25519Pk: Uint8List.fromList(p.userEd25519Pk),
      ed25519Sig: Uint8List.fromList(p.ed25519Sig),
    );
  }
}
