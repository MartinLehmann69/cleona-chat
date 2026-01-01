import 'dart:typed_data';

import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/node/identity_context.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;
import 'package:fixnum/fixnum.dart';

/// Outcome of the D1 trust-anchor verification (§4.3 "Trust anchor & record
/// verification").
///
/// `legacy` = pre-D1 record without embedded pubkeys — accepted at lower
/// precedence until the Phase-2 enforcement gate (`minRequiredVersion`,
/// §19.5.7). `forged` = embedded keys present but signature or identity
/// binding fails. `contactMismatch` = cryptographically valid but the
/// embedded key contradicts the stored contact key without a bridging
/// rotation chain — must raise key-change detection (§8.3).
enum AnchorStatus { verified, legacy, forged, contactMismatch }

/// One soft-re-key link old→new (§7.4b). Link shape mirrors
/// KeyRotationBroadcast: the OLD key signs the successor pubkeys, proving
/// continuity from the founding key (whose hash is the userId) to the
/// currently embedded manifest keys.
class RotationChainLink {
  final Uint8List oldEd25519Pk;
  final Uint8List newEd25519Pk;
  final Uint8List newMlDsaPk;
  final Uint8List oldSignatureEd25519;

  RotationChainLink({
    required this.oldEd25519Pk,
    required this.newEd25519Pk,
    required this.newMlDsaPk,
    required this.oldSignatureEd25519,
  });

  /// Bytes the OLD key signs: new_ed25519_pk || new_ml_dsa_pk.
  Uint8List signedContent() {
    final c = Uint8List(newEd25519Pk.length + newMlDsaPk.length);
    c.setRange(0, newEd25519Pk.length, newEd25519Pk);
    c.setRange(newEd25519Pk.length, c.length, newMlDsaPk);
    return c;
  }

  proto.RotationChainLinkProto toProto() {
    return proto.RotationChainLinkProto()
      ..oldEd25519Pk = oldEd25519Pk
      ..newEd25519Pk = newEd25519Pk
      ..newMlDsaPk = newMlDsaPk
      ..oldSignatureEd25519 = oldSignatureEd25519;
  }

  static RotationChainLink fromProto(proto.RotationChainLinkProto p) {
    return RotationChainLink(
      oldEd25519Pk: Uint8List.fromList(p.oldEd25519Pk),
      newEd25519Pk: Uint8List.fromList(p.newEd25519Pk),
      newMlDsaPk: Uint8List.fromList(p.newMlDsaPk),
      oldSignatureEd25519: Uint8List.fromList(p.oldSignatureEd25519),
    );
  }
}

/// User-signed manifest deklarierend, welche Devices zu einem User gehoeren.
/// Hybrid-signiert (Ed25519 + ML-DSA-65) fuer PQ-Sicherheit. Langlebig (24h).
///
/// D1 (§4.3 Trust anchor): self-certifying — traegt die User-Pubkeys im
/// Record (von der Hybrid-Sig abgedeckt) und ist an die userId gebunden via
/// Founding-Key-Hash, Rotationskette oder Contact-Match. Ein Resolver, der
/// nur die userId (einen Hash) kennt, kann damit ohne externen Pubkey-Cache
/// verifizieren.
class AuthManifest {
  final Uint8List userId;
  final List<Uint8List> authorizedDeviceNodeIds;
  final int ttlSeconds;
  final int sequenceNumber;
  final int publishedAtMs;

  /// Embedded trust anchor (D1). Empty on legacy (pre-D1) records.
  final Uint8List userEd25519Pk;
  final Uint8List userMlDsaPk;

  /// Founding-key → current-key continuity after soft re-key (§7.4b).
  /// Empty unless the identity has rotated.
  final List<RotationChainLink> rotationChain;

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
    Uint8List? userEd25519Pk,
    Uint8List? userMlDsaPk,
    this.rotationChain = const [],
  })  : userEd25519Pk = userEd25519Pk ?? Uint8List(0),
        userMlDsaPk = userMlDsaPk ?? Uint8List(0);

  bool get hasEmbeddedKeys =>
      userEd25519Pk.isNotEmpty && userMlDsaPk.isNotEmpty;

  /// Build canonical bytes-to-sign: deterministische Serialisierung WITHOUT
  /// signature fields. Signing-side and verifying-side muessen denselben Pfad
  /// nehmen, sonst stimmen die Sigs nicht ueberein. Leere D1-Felder werden
  /// von proto3 nicht serialisiert — Legacy-Records bleiben byte-identisch.
  Uint8List _bytesToSign() {
    final unsigned = proto.AuthManifestProto()
      ..userId = userId
      ..authorizedDeviceNodeIds.addAll(authorizedDeviceNodeIds)
      ..ttlSeconds = ttlSeconds
      ..sequenceNumber = Int64(sequenceNumber)
      ..publishedAtMs = Int64(publishedAtMs);
    if (userEd25519Pk.isNotEmpty) unsigned.userEd25519Pk = userEd25519Pk;
    if (userMlDsaPk.isNotEmpty) unsigned.userMlDsaPk = userMlDsaPk;
    if (rotationChain.isNotEmpty) {
      unsigned.rotationChain.addAll(rotationChain.map((l) => l.toProto()));
    }
    return Uint8List.fromList(unsigned.writeToBuffer());
  }

  /// [userId] uebersteuert die userId der Identitaet — noetig nach Soft
  /// Re-Key (§7.4b): das Manifest laeuft unter der Founding-userId weiter,
  /// signiert mit den AKTUELLEN Keys + Rotationskette als Bindungsbeweis.
  static AuthManifest sign(
    IdentityContext id,
    List<Uint8List> devices, {
    required int ttlSeconds,
    required int sequenceNumber,
    List<RotationChainLink> rotationChain = const [],
    Uint8List? userId,
  }) {
    final publishedAtMs = DateTime.now().millisecondsSinceEpoch;
    final m = AuthManifest(
      userId: userId ?? id.userId,
      authorizedDeviceNodeIds: devices,
      ttlSeconds: ttlSeconds,
      sequenceNumber: sequenceNumber,
      publishedAtMs: publishedAtMs,
      userEd25519Pk: id.ed25519PublicKey,
      userMlDsaPk: id.mlDsaPublicKey,
      rotationChain: rotationChain,
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

  /// D1 trust-anchor verification (§4.3): hybrid signature against the
  /// EMBEDDED pubkeys plus identity binding to the userId via one of three
  /// equivalent paths — founding-key hash, rotation chain, contact match.
  ///
  /// [deriveUserId] computes `SHA-256(network_secret || ed25519Pk)`
  /// (injected so tests don't depend on the production NetworkSecret).
  /// [contactEd25519Pk] is the stored contact key when the userId is a
  /// known contact — then the embedded key MUST match or a rotation chain
  /// must bridge from it, else `contactMismatch`.
  AnchorStatus verifySelfCertified({
    required Uint8List Function(Uint8List ed25519Pk) deriveUserId,
    Uint8List? contactEd25519Pk,
  }) {
    if (!hasEmbeddedKeys) return AnchorStatus.legacy;
    if (!verify(userEd25519Pk, userMlDsaPk)) return AnchorStatus.forged;

    var bound = _bytesEqual(deriveUserId(userEd25519Pk), userId);
    if (!bound && rotationChain.isNotEmpty) {
      bound = _verifyChain(deriveUserId);
    }
    if (!bound &&
        contactEd25519Pk != null &&
        _bytesEqual(contactEd25519Pk, userEd25519Pk)) {
      // Rotated contact: stored contact key is current (tracked via
      // KEY_ROTATION_BROADCAST) even though the founding hash no longer
      // matches.
      bound = true;
    }
    if (!bound) return AnchorStatus.forged;

    // Contact continuity (mandatory, §4.3): embedded key must equal the
    // stored contact key, or the chain must bridge old→new.
    if (contactEd25519Pk != null &&
        !_bytesEqual(contactEd25519Pk, userEd25519Pk)) {
      final bridged = rotationChain
          .any((l) => _bytesEqual(l.oldEd25519Pk, contactEd25519Pk));
      if (!bridged) return AnchorStatus.contactMismatch;
    }
    return AnchorStatus.verified;
  }

  /// Verify the founding-key → embedded-key continuity chain (§7.4b).
  bool _verifyChain(Uint8List Function(Uint8List ed25519Pk) deriveUserId) {
    final sodium = SodiumFFI();
    // link[0]'s old pk must hash to the userId (founding anchor).
    if (!_bytesEqual(deriveUserId(rotationChain.first.oldEd25519Pk), userId)) {
      return false;
    }
    for (var i = 0; i < rotationChain.length; i++) {
      final link = rotationChain[i];
      if (i > 0 &&
          !_bytesEqual(link.oldEd25519Pk, rotationChain[i - 1].newEd25519Pk)) {
        return false;
      }
      if (!sodium.verifyEd25519(
          link.signedContent(), link.oldSignatureEd25519, link.oldEd25519Pk)) {
        return false;
      }
    }
    final last = rotationChain.last;
    return _bytesEqual(last.newEd25519Pk, userEd25519Pk) &&
        _bytesEqual(last.newMlDsaPk, userMlDsaPk);
  }

  bool isExpired() {
    final ageMs = DateTime.now().millisecondsSinceEpoch - publishedAtMs;
    return ageMs > ttlSeconds * 1000;
  }

  proto.AuthManifestProto toProto() {
    final p = proto.AuthManifestProto()
      ..userId = userId
      ..authorizedDeviceNodeIds.addAll(authorizedDeviceNodeIds)
      ..ttlSeconds = ttlSeconds
      ..sequenceNumber = Int64(sequenceNumber)
      ..publishedAtMs = Int64(publishedAtMs)
      ..ed25519Sig = ed25519Sig
      ..mlDsaSig = mlDsaSig;
    if (userEd25519Pk.isNotEmpty) p.userEd25519Pk = userEd25519Pk;
    if (userMlDsaPk.isNotEmpty) p.userMlDsaPk = userMlDsaPk;
    if (rotationChain.isNotEmpty) {
      p.rotationChain.addAll(rotationChain.map((l) => l.toProto()));
    }
    return p;
  }

  static AuthManifest fromProto(proto.AuthManifestProto p) {
    return AuthManifest(
      userId: Uint8List.fromList(p.userId),
      authorizedDeviceNodeIds:
          p.authorizedDeviceNodeIds.map(Uint8List.fromList).toList(),
      ttlSeconds: p.ttlSeconds,
      sequenceNumber: p.sequenceNumber.toInt(),
      publishedAtMs: p.publishedAtMs.toInt(),
      userEd25519Pk: Uint8List.fromList(p.userEd25519Pk),
      userMlDsaPk: Uint8List.fromList(p.userMlDsaPk),
      rotationChain:
          p.rotationChain.map(RotationChainLink.fromProto).toList(),
      ed25519Sig: Uint8List.fromList(p.ed25519Sig),
      mlDsaSig: Uint8List.fromList(p.mlDsaSig),
    );
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
