import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/identity_resolution/auth_manifest.dart';
import 'package:cleona/core/identity_resolution/device_delegation.dart';
import 'package:cleona/core/node/identity_context.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;
import 'package:fixnum/fixnum.dart';

/// Device-published liveness record: aktuelle Adressen + TTL.
/// Ed25519-only signiert (kein PQ — Threat-Modell siehe Spec §3 / Architektur §4).
///
/// §7.1.4 (delegierte Signatur): der Record ist **geraetebezogen**, also
/// signiert ihn ein Linked Device unter **geraetebezogener Autoritaet** —
/// mit seinem delegierten Ed25519-SK und [signerEd25519Pk] als Zeiger auf den
/// benutzten Schluessel. Primary/Legacy lassen das Feld leer und signieren wie
/// bisher direkt unter dem User-SK; proto3 serialisiert leere Felder nicht,
/// Legacy-Records bleiben byte-identisch.
///
/// P6 (Arbeitsregel #5): das Delegationszertifikat reist NICHT mit. Es kostete
/// ~5,3 KB pro Record und fragmentierte jeden 15-Minuten-Republish an bis zu
/// 10 Replikatoren. Der Empfaenger holt es aus dem AuthManifest, das er fuer
/// den User ohnehin haelt — siehe [verifyAnchored].
class LivenessRecord {
  final Uint8List userId;
  final Uint8List deviceNodeId;
  final List<proto.PeerAddressProto> addresses;
  final int ttlSeconds;
  final int sequenceNumber;
  final int publishedAtMs;

  /// §7.1.4: leer = direkt unter dem User-SK signiert (Primary-Pfad).
  /// Gesetzt = delegiert signiert; das zugehoerige Zertifikat sucht der
  /// Empfaenger unter diesem PK im AuthManifest.
  Uint8List signerEd25519Pk;

  Uint8List ed25519Sig;

  LivenessRecord({
    required this.userId,
    required this.deviceNodeId,
    required this.addresses,
    required this.ttlSeconds,
    required this.sequenceNumber,
    required this.publishedAtMs,
    required this.ed25519Sig,
    Uint8List? signerEd25519Pk,
  }) : signerEd25519Pk = signerEd25519Pk ?? Uint8List(0);

  /// True sobald der Record beansprucht, delegiert signiert zu sein.
  /// Abstreifen ist keine Downgrade-Option: [signerEd25519Pk] liegt UNTER der
  /// Record-Signatur, ein geleertes Feld bricht sie.
  bool get isDelegatedSigned => signerEd25519Pk.isNotEmpty;

  Uint8List _bytesToSign() {
    final unsigned = proto.LivenessRecordProto()
      ..userId = userId
      ..deviceNodeId = deviceNodeId
      ..addresses.addAll(addresses)
      ..ttlSeconds = ttlSeconds
      ..sequenceNumber = Int64(sequenceNumber)
      ..publishedAtMs = Int64(publishedAtMs);
    // Signer-Bindung liegt UNTER der Signatur: sonst koennte ein Angreifer den
    // Signierer-PK tauschen oder streichen, ohne dass sich die signierten
    // Bytes aendern — und damit auswaehlen, gegen welche Delegation der
    // Empfaenger prueft. Bleibt auch nach P6 im Scope (das Zertifikat faellt
    // raus, dieses Feld nicht).
    if (signerEd25519Pk.isNotEmpty) {
      unsigned.signerEd25519Pk = signerEd25519Pk;
    }
    return Uint8List.fromList(unsigned.writeToBuffer());
  }

  /// [delegatedSigner] ueberschreibt die Ableitung aus [id] (Tests / expliziter
  /// Aufruf). Default: ein Linked Device signiert delegiert, ein Primary direkt.
  static LivenessRecord sign(
    IdentityContext id,
    Uint8List deviceNodeId,
    List<proto.PeerAddressProto> addresses, {
    required int ttlSeconds,
    required int sequenceNumber,
    DelegatedSigner? delegatedSigner,
  }) {
    final ld = id.linkedDeviceKeys;
    final signer = delegatedSigner ??
        (ld == null
            ? null
            : DelegatedSigner(
                ed25519Pk: ld.delegatedEd25519Pk,
                ed25519Sk: ld.delegatedEd25519Sk,
              ));
    final publishedAtMs = DateTime.now().millisecondsSinceEpoch;
    final r = LivenessRecord(
      userId: id.userId,
      deviceNodeId: deviceNodeId,
      addresses: addresses,
      ttlSeconds: ttlSeconds,
      sequenceNumber: sequenceNumber,
      publishedAtMs: publishedAtMs,
      ed25519Sig: Uint8List(0),
      signerEd25519Pk: signer?.ed25519Pk,
    );
    // §7.1.1: auf einem Linked Device passt `id.ed25519SecretKey` nach einer
    // LD-8-Rotation NICHT mehr zu `id.ed25519PublicKey` — hier darf er nie
    // mehr benutzt werden.
    final sk = signer?.ed25519Sk ?? id.ed25519SecretKey;
    final dataToSign = r._bytesToSign();
    r.ed25519Sig = SodiumFFI().signEd25519(dataToSign, sk);
    return r;
  }

  bool verify(Uint8List userPubkeyEd25519) {
    // SodiumFFI.verifyEd25519 signature: (message, signature, publicKey)
    return SodiumFFI()
        .verifyEd25519(_bytesToSign(), ed25519Sig, userPubkeyEd25519);
  }

  /// §4.3 D1 + §7.1.4: Verifikation gegen das verankernde AuthManifest.
  /// Direkt signiert → wie bisher gegen `anchorManifest.userEd25519Pk`.
  /// Delegiert signiert → erst die Zertifikatskette (hybrid, PK-Bindung,
  /// Ablauf, Geraete-Bindung), dann der Record gegen den delegierten PK.
  ///
  /// P6: das Zertifikat kommt aus [anchorManifest] statt aus dem Record.
  /// Fehlt dort ein Eintrag fuer [deviceNodeId], ist das ein Drop —
  /// `verifyDelegatedSigner(cert: null)` liefert false. Das ist keine neue
  /// Abhaengigkeit: schon P5 lehnte einen delegierten Record ohne verankertes
  /// Manifest ab, weil die ML-DSA-Haelfte des Zertifikats sonst nicht
  /// pruefbar ist.
  ///
  /// [anchorManifest] MUSS ein verifiziertes Manifest mit embedded Keys sein
  /// (§4.3 D1) — der Caller stellt das sicher.
  bool verifyAnchored(AuthManifest anchorManifest) {
    if (!isDelegatedSigned) return verify(anchorManifest.userEd25519Pk);
    if (!DeviceDelegation.verifyDelegatedSigner(
      signerEd25519Pk: signerEd25519Pk,
      cert: anchorManifest.delegationFor(deviceNodeId),
      anchorUserEd25519Pk: anchorManifest.userEd25519Pk,
      anchorUserMlDsaPk: anchorManifest.userMlDsaPk,
      recordDeviceId: deviceNodeId,
    )) {
      return false;
    }
    return verify(signerEd25519Pk);
  }

  bool isExpired() {
    final ageMs = DateTime.now().millisecondsSinceEpoch - publishedAtMs;
    return ageMs > ttlSeconds * 1000;
  }

  proto.LivenessRecordProto toProto() {
    final out = proto.LivenessRecordProto()
      ..userId = userId
      ..deviceNodeId = deviceNodeId
      ..addresses.addAll(addresses)
      ..ttlSeconds = ttlSeconds
      ..sequenceNumber = Int64(sequenceNumber)
      ..publishedAtMs = Int64(publishedAtMs)
      ..ed25519Sig = ed25519Sig;
    if (signerEd25519Pk.isNotEmpty) out.signerEd25519Pk = signerEd25519Pk;
    return out;
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
      signerEd25519Pk: Uint8List.fromList(p.signerEd25519Pk),
    );
  }
}
