import 'dart:convert';
import 'dart:typed_data';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:meta/meta.dart';

/// Plain-Dart KEM-header tuple returned by [PerMessageKem.encrypt] and
/// consumed by [PerMessageKem.decrypt]. Field names mirror the V3 wire
/// shape ([proto.PerMessageKemV3]); the codec layer is responsible for
/// packing/unpacking against the wire type.
///
/// This deliberately replaces the historical V2 wire-message
/// `proto.PerMessageKem` (dropped Wave 9 Beta) — the API no longer leaks
/// the deprecated wire shape.
class KemHeader {
  final Uint8List ephemeralX25519Pk; // 32 bytes — X25519 ephemeral pubkey
  final Uint8List mlKemCiphertext;   // 1088 bytes — ML-KEM-768 ciphertext
  final Uint8List aesNonce;          // 12 bytes — AEAD nonce
  final int version;                 // KEM version (Sec H-5: v2)

  const KemHeader({
    required this.ephemeralX25519Pk,
    required this.mlKemCiphertext,
    required this.aesNonce,
    required this.version,
  });
}

/// Thrown by [PerMessageKem.decrypt] when the header carries a KEM version
/// that is not in [PerMessageKem.acceptKemVersions].
///
/// **Caller contract:** drop the message silently — no DELIVERY_RECEIPT,
/// no Reputation-Strike, no exception propagation up the receive pipeline.
/// Caller MUST also WARN-log the rejection with the [receivedVersion] for
/// observability (Spec §9 Error-Handling). The crypto utility itself does
/// no logging; logging is the call-site's responsibility (see §16.4.5
/// receive pipeline in cleona_service.dart).
///
/// Typical version values:
///  - 0 → pre-rollout sender (proto3-default, missing field 4)
///  - 1 → legacy v1 sender (dropped V3.1.72)
///  - 3+ → unknown future version
class KemVersionRejectedException implements Exception {
  final int receivedVersion;
  KemVersionRejectedException(this.receivedVersion);
  @override
  String toString() => 'KemVersionRejectedException(version=$receivedVersion)';
}

/// Per-Message Key Encapsulation: stateless E2E encryption.
/// Every message is encrypted with a fresh ephemeral key pair.
/// No session state, no handshake, no synchronization.
class PerMessageKem {
  static final _sodium = SodiumFFI();
  static final _oqs = OqsFFI();

  /// Current KEM version (Sec H-5: Per-Message-KEM HKDF-Salt v2).
  static const int currentKemVersion = 2;

  /// Version we send. After Phase-1 cutover this is permanently 2.
  static const int kemSendVersion = 2;

  /// Versions we accept on receive. v1 (Zero-Bytes-Salt) dropped in V3.1.72.
  static const Set<int> acceptKemVersions = {2};

  /// HKDF salt for v2: SHA-256("cleona-per-message-kem/salt/v2").
  /// Pinned-at-build-time in `_saltV2` for runtime efficiency.
  static final Uint8List _saltV2 = _sodium.sha256(
    Uint8List.fromList(utf8.encode('cleona-per-message-kem/salt/v2')),
  );

  /// Test-only accessor for `_saltV2`. Not for production use.
  @visibleForTesting
  static Uint8List get saltV2ForTest => _saltV2;

  static Uint8List _saltForVersion(int v) {
    switch (v) {
      case 2:
        return _saltV2;
      default:
        throw ArgumentError('unsupported KEM version: $v');
    }
  }

  /// Domain-separation info string for HKDF, version-suffixed.
  /// Unlike `_saltForVersion` (which uses an explicit switch because each
  /// version has a unique salt-bytes value), the info string is a parametric
  /// template — adding a new accepted version requires only updating
  /// `acceptKemVersions`, no code change here.
  static String _infoForVersion(int v) {
    if (!acceptKemVersions.contains(v)) {
      throw ArgumentError('unsupported KEM version: $v');
    }
    return 'cleona-msg-v$v';
  }

  /// Encrypt a message for a recipient.
  static (KemHeader, Uint8List) encrypt({
    required Uint8List plaintext,
    required Uint8List recipientX25519Pk,
    required Uint8List recipientMlKemPk,
  }) {
    // 1. Generate ephemeral X25519 key pair
    final ephEd25519 = _sodium.generateEd25519KeyPair();
    final ephX25519Pk = _sodium.ed25519PkToX25519(ephEd25519.publicKey);
    final ephX25519Sk = _sodium.ed25519SkToX25519(ephEd25519.secretKey);

    // 2. X25519 DH
    final dhSecret = _sodium.x25519ScalarMult(ephX25519Sk, recipientX25519Pk);

    // 3. ML-KEM-768 encapsulation
    final kemResult = _oqs.mlKemEncapsulate(recipientMlKemPk);
    final kemCiphertext = kemResult.ciphertext;
    final kemSecret = kemResult.sharedSecret;

    // 4. Derive message key with v-versioned salt + info
    final version = kemSendVersion;
    final ikm = Uint8List(dhSecret.length + kemSecret.length);
    ikm.setRange(0, dhSecret.length, dhSecret);
    ikm.setRange(dhSecret.length, ikm.length, kemSecret);
    final msgKey = _sodium.hkdfSha256(
      ikm,
      salt: _saltForVersion(version),
      info: Uint8List.fromList(utf8.encode(_infoForVersion(version))),
      length: 32,
    );

    // 5. Encrypt with AES-256-GCM
    final nonce = _sodium.generateNonce();
    final ciphertext = _sodium.aesGcmEncrypt(plaintext, msgKey, nonce);

    // 6. Build KEM header WITH version
    final header = KemHeader(
      ephemeralX25519Pk: ephX25519Pk,
      mlKemCiphertext: kemCiphertext,
      aesNonce: nonce,
      version: version,
    );

    // 7. Zero ephemeral secrets
    for (var i = 0; i < ephX25519Sk.length; i++) { ephX25519Sk[i] = 0; }
    for (var i = 0; i < ephEd25519.secretKey.length; i++) { ephEd25519.secretKey[i] = 0; }

    return (header, ciphertext);
  }

  /// Decrypt a message using our private keys.
  static Uint8List decrypt({
    required KemHeader kemHeader,
    required Uint8List ciphertext,
    required Uint8List ourX25519Sk,
    required Uint8List ourMlKemSk,
  }) {
    // 0. Validate KEM version BEFORE any expensive crypto ops.
    //    Unaccepted versions throw — caller drops silently (no ACK, no strike).
    final version = kemHeader.version;
    if (!acceptKemVersions.contains(version)) {
      throw KemVersionRejectedException(version);
    }

    // 1. X25519 DH with ephemeral public key
    final ephPk = kemHeader.ephemeralX25519Pk;
    final dhSecret = _sodium.x25519ScalarMult(ourX25519Sk, ephPk);

    // 2. ML-KEM-768 decapsulation
    final kemCiphertext = kemHeader.mlKemCiphertext;
    final kemSecret = _oqs.mlKemDecapsulate(kemCiphertext, ourMlKemSk);

    // 3. Derive the same message key with version-correct salt + info
    final ikm = Uint8List(dhSecret.length + kemSecret.length);
    ikm.setRange(0, dhSecret.length, dhSecret);
    ikm.setRange(dhSecret.length, ikm.length, kemSecret);
    final msgKey = _sodium.hkdfSha256(
      ikm,
      salt: _saltForVersion(version),
      info: Uint8List.fromList(utf8.encode(_infoForVersion(version))),
      length: 32,
    );

    // 4. Decrypt with AES-256-GCM
    final nonce = kemHeader.aesNonce;
    return _sodium.aesGcmDecrypt(ciphertext, msgKey, nonce);
  }

  // Encryption decision lives in V3FrameCodec; ephemeral / erasure-skip
  // logic lives in CleonaService._handleApplicationFrame.
}
