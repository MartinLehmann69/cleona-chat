import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/identity_resolution/auth_manifest.dart';
import 'package:cleona/core/identity_resolution/device_delegation.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;
import 'package:fixnum/fixnum.dart';

/// User-signed Device-KEM-Record fuer den 2D-DHT-Lookup (Welle 5, §3.5b + §4.3).
///
/// Traegt die Device-KEM-Pubkeys (X25519 + ML-KEM-768), die Sender brauchen
/// um InfrastructureFrameV3 (und spaeter ONION_LAYER) gegen das Empfaenger-
/// Geraet zu encappen. Lebenszyklus ist langsam (Multi-Year-Cadence,
/// gleicher Trust-Anchor wie AuthManifestV3): Republish alle 3 Tage, TTL 7 Tage
/// (matcht das Mailbox/S&F-Retention-Fenster, §4.3 / §5.5b).
///
/// **Trust-Chain**: der Record haengt am **User-Master-Ed25519-Key** — der
/// eingebettete [userEd25519Pk] muss dem Anker aus AuthManifestV3 entsprechen.
/// Signiert wird er auf zwei Wegen (§7.1.4):
///   * **Primary** — direkt mit dem User-Master-SK, [signerEd25519Pk] leer.
///   * **Linked Device** — mit dem **delegierten** Ed25519-SK; [signerEd25519Pk]
///     benennt ihn, das Zertifikat holt der Empfaenger aus dem AuthManifest
///     (P6, siehe [verifyAnchored]). Ein gekoppeltes Geraet besitzt den
///     User-SK nach einer LD-8-Rotation nicht mehr (§7.1.1), koennte also
///     sonst gar keinen gueltigen Record mehr publizieren.
/// ML-DSA deckt hier bewusst nur das **Zertifikat** ab, nicht den Record: das
/// Trust-Modell des Records ist dasselbe wie bei LivenessRecordV3
/// (Ed25519-only); die Delegation selbst ist hybrid abgesichert, weil sie
/// Autoritaet uebertraegt.
class DeviceKemRecord {
  final Uint8List userId;
  final Uint8List deviceId;
  final Uint8List deviceX25519Pk;
  final Uint8List deviceMlKemPk;
  final int ttlSeconds;
  final int sequenceNumber;
  final int publishedAtMs;
  final Uint8List userEd25519Pk;

  /// §7.1.4: leer = direkt unter dem User-SK signiert (Primary-Pfad).
  Uint8List signerEd25519Pk;

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
    Uint8List? signerEd25519Pk,
  }) : signerEd25519Pk = signerEd25519Pk ?? Uint8List(0);

  /// Siehe `LivenessRecord.isDelegatedSigned` — das Feld liegt unter der
  /// Record-Signatur, Abstreifen bricht sie.
  bool get isDelegatedSigned => signerEd25519Pk.isNotEmpty;

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
    // Signer-Bindung liegt UNTER der Signatur — siehe LivenessRecord.
    if (signerEd25519Pk.isNotEmpty) {
      unsigned.signerEd25519Pk = signerEd25519Pk;
    }
    return Uint8List.fromList(unsigned.writeToBuffer());
  }

  /// Build + sign. Ohne [delegatedSigner] wird direkt mit dem
  /// User-Master-Ed25519-Key signiert (Primary). Mit [delegatedSigner]
  /// signiert ein Linked Device unter seinem delegierten Schluessel und legt
  /// den Signer-PK bei (§7.1.4); [userEd25519Sk] wird dann NICHT
  /// benutzt — auf einem gekoppelten Geraet ist er nach einer LD-8-Rotation
  /// veraltet und wuerde den Record fuer jeden Empfaenger unbrauchbar machen.
  static DeviceKemRecord sign({
    required Uint8List userId,
    required Uint8List deviceId,
    required Uint8List deviceX25519Pk,
    required Uint8List deviceMlKemPk,
    required Uint8List userEd25519Sk,
    required Uint8List userEd25519Pk,
    required int ttlSeconds,
    required int sequenceNumber,
    DelegatedSigner? delegatedSigner,
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
      signerEd25519Pk: delegatedSigner?.ed25519Pk,
    );
    final sk = delegatedSigner?.ed25519Sk ?? userEd25519Sk;
    final dataToSign = r._bytesToSign();
    r.ed25519Sig = SodiumFFI().signEd25519(dataToSign, sk);
    return r;
  }

  /// Verifizieren der Sig gegen den uebergebenen User-Master-Pubkey. Caller
  /// MUSS den Pubkey aus AuthManifestV3 (oder Contact-Registry) ziehen — hier
  /// nicht aus dem Record, sonst verlieren wir den Trust-Anchor.
  bool verify(Uint8List userPubkeyEd25519) {
    return SodiumFFI()
        .verifyEd25519(_bytesToSign(), ed25519Sig, userPubkeyEd25519);
  }

  /// §4.3 D1 + §7.1.4: Verifikation gegen das verankernde AuthManifest.
  /// Delegiert signierte Records durchlaufen zuerst die Zertifikatskette
  /// (hybrid-Sig, PK-Bindung, Ablauf, Geraete-Bindung an [deviceId]), erst
  /// danach wird der Record gegen den delegierten PK geprueft.
  ///
  /// P6: das Zertifikat kommt aus [anchorManifest] (`delegationFor(deviceId)`)
  /// statt aus dem Record — fehlt es dort, ist das ein Drop.
  ///
  /// Die Bindung `userEd25519Pk == Anker` bleibt Sache des Callers — sie gilt
  /// in BEIDEN Pfaden, auch delegiert.
  bool verifyAnchored(AuthManifest anchorManifest) {
    if (!isDelegatedSigned) return verify(anchorManifest.userEd25519Pk);
    if (!DeviceDelegation.verifyDelegatedSigner(
      signerEd25519Pk: signerEd25519Pk,
      cert: anchorManifest.delegationFor(deviceId),
      anchorUserEd25519Pk: anchorManifest.userEd25519Pk,
      anchorUserMlDsaPk: anchorManifest.userMlDsaPk,
      recordDeviceId: deviceId,
    )) {
      return false;
    }
    return verify(signerEd25519Pk);
  }

  bool isExpired() {
    final ageMs = DateTime.now().millisecondsSinceEpoch - publishedAtMs;
    return ageMs > ttlSeconds * 1000;
  }

  proto.DeviceKemRecordV3 toProto() {
    final out = proto.DeviceKemRecordV3()
      ..userId = userId
      ..deviceId = deviceId
      ..deviceX25519Pk = deviceX25519Pk
      ..deviceMlKemPk = deviceMlKemPk
      ..ttlSeconds = Int64(ttlSeconds)
      ..sequenceNumber = Int64(sequenceNumber)
      ..publishedAtMs = Int64(publishedAtMs)
      ..userEd25519Pk = userEd25519Pk
      ..ed25519Sig = ed25519Sig;
    if (signerEd25519Pk.isNotEmpty) out.signerEd25519Pk = signerEd25519Pk;
    return out;
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
      signerEd25519Pk: Uint8List.fromList(p.signerEd25519Pk),
    );
  }
}
