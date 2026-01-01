/// Device-Sig keypair (Ed25519 + ML-DSA-65 hybrid) for V3.0 Outer-Frame
/// authentication.
///
/// V3.0 separates identity into two crypto subjects:
///
/// * **User-Sig keypair** — long-lived, seed-derived via HD-Wallet, signs the
///   Inner ApplicationFrameV3 (end-to-end identity). Lives in
///   `IdentityContext` / `identity_manager.dart`.
/// * **Device-Sig keypair** — *this module*. Locally generated, NOT
///   seed-derived, NOT migrated across devices. Signs the Outer
///   NetworkPacketV3 (`deviceEd25519Sig` + optional `deviceMlDsaSig`) and the
///   2D-DHT Liveness-Record. Disposable — if the device is lost, it is removed
///   from the Auth-Manifest via §7.4 and a fresh keypair is generated on the
///   replacement device.
///
/// See `Cleona_Chat_Architecture_v3_0.md` §3.5 (Device Identity Sigs) and §2
/// (NetworkPacketV3 wire format, fields 10/11).
///
/// **Selectivity** (§3.5): the `signMlDsa()` half is invoked ONLY for
/// application frames (TEXT, MEDIA, GROUP_*, CHANNEL_*, CALENDAR_*, POLL_*,
/// CONTACT_REQUEST, REACTION, …). Infrastructure frames (DHT publish/retrieve,
/// hole-punch, RTT probes, CALL_AUDIO/VIDEO, ACKs, heartbeats) carry only the
/// Ed25519 sig. The caller (transport / outer-frame builder) decides which to
/// emit; this module just exposes both primitives.
///
/// ---------------------------------------------------------------------------
/// INTEGRATION POINTS — open hooks for follow-up tasks (NOT done in this file)
/// ---------------------------------------------------------------------------
///
/// 1. **KeyManager / IdentityContext branch** (Task #6, Welle 2 Service-Layer):
///    `IdentityContext` (lib/core/node/identity_context.dart) currently only
///    holds the User-Sig keypair (`ed25519SecretKey`, `mlDsaSecretKey`). It
///    must be extended with a `deviceKeyPair` field of type [DeviceKeyPair],
///    populated on identity load. The Outer-Frame signer uses
///    `identity.deviceKeyPair.signEd25519(packetBytes)` and
///    `identity.deviceKeyPair.signMlDsa(packetBytes)`; the Inner-Frame signer
///    keeps using the existing User-Sig path (`SodiumFFI().signEd25519(...,
///    identity.ed25519SecretKey)`).
///
/// 2. **Persistence path**: store the serialised keypair under the identity's
///    profile directory at e.g. `<profileDir>/device_sig.bin`, encrypted with
///    the same per-identity DB key used by the rest of the profile (see
///    `lib/core/crypto/file_encryption.dart` and the DB-key derivation in
///    §3.7). The on-disk format is [DeviceKeyPair.serialize()] /
///    [DeviceKeyPair.deserialize] — a length-prefixed concatenation of the
///    four key blobs.
///
/// 3. **Lifecycle — first-launch / restore / wipe**:
///    * Fresh install or post-recovery wipe: call [DeviceKeyPair.generate]
///      after the User-Sig keys exist, persist, then start the node so the
///      Liveness-Record carries the new device pubkey.
///    * Restore on a 2nd device (§6.3.5, §7): generate a fresh
///      [DeviceKeyPair] — same User-Sig keys (from the seed phrase), but a
///      NEW DeviceID. The old device is later evicted from the Auth-Manifest
///      via §7.4.
///    * Profile reset: delete the persisted blob; next launch regenerates.
///
/// 4. **Auth-Manifest publication**: when (re)publishing the Auth-Manifest
///    (§4.3, `lib/core/identity_resolution/auth_manifest.dart`) the entry for
///    *this* device must include the Ed25519 + ML-DSA-65 pubkeys exposed by
///    [DeviceKeyPair.ed25519PublicKey] / [DeviceKeyPair.mlDsaPublicKey].
///
/// 5. **Outer-Frame verification** (receiver side): the recipient pulls the
///    sender's Device-Pubkeys from the cached Auth-Manifest and uses
///    [verifyEd25519] / [verifyMlDsa] from this module — no [DeviceKeyPair]
///    instance required (we only hold our own private keys).
///
/// 6. **Spec note for the human reviewer**: §3.5 last paragraph currently
///    reads "Key generation: derived from the User-Master-Seed via HD-Wallet-
///    Derivation, with a device-specific salt (see §3.6)." This contradicts
///    the rest of the document (§6.3.5, §7 multi-device restore, the
///    "disposable Device-Sig-Key" rationale, and the operational reality that
///    liboqs `OQS_SIG_keypair` does not accept a seed argument so ML-DSA-65
///    cannot be HD-derived through the libsodium primitive). This module
///    follows the prevailing intent: **locally generated, fresh per device**.
///    The §3.5 paragraph should be updated to match.
library;

import 'dart:typed_data';

import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';

/// Exception thrown for Device-Sig-Keypair errors (malformed serialisation,
/// wrong key sizes, …).
class DeviceSignatureException implements Exception {
  final String message;
  const DeviceSignatureException(this.message);

  @override
  String toString() => 'DeviceSignatureException: $message';
}

/// A device-bound Ed25519 + ML-DSA-65 hybrid signing keypair.
///
/// Holds the four key blobs that make up the Outer-Frame signing identity of
/// a single Cleona device. Instances are NOT shared across devices — see the
/// `INTEGRATION POINTS` block at the top of this file for lifecycle rules.
///
/// All key buffers are exposed read-only via getters. Mutation must go through
/// [generate] (fresh keys) or [deserialize] (load from disk).
class DeviceKeyPair {
  /// Ed25519 secret key — libsodium 64-byte format (`seed[0..32] ||
  /// pubkey[32..64]`). Same encoding as the User-Sig key in [SodiumFFI].
  final Uint8List ed25519PrivateKey;

  /// Ed25519 public key — 32 bytes. Equal to `ed25519PrivateKey[32..64]`,
  /// kept separately for verifier-only flows that should not touch the secret
  /// half.
  final Uint8List ed25519PublicKey;

  /// ML-DSA-65 secret key — 4032 bytes (see [OqsFFI.mlDsaSecretKeyLength]).
  final Uint8List mlDsaPrivateKey;

  /// ML-DSA-65 public key — 1952 bytes (see [OqsFFI.mlDsaPublicKeyLength]).
  final Uint8List mlDsaPublicKey;

  DeviceKeyPair._({
    required this.ed25519PrivateKey,
    required this.ed25519PublicKey,
    required this.mlDsaPrivateKey,
    required this.mlDsaPublicKey,
  }) {
    if (ed25519PrivateKey.length != cryptoSignSecretKeyBytes) {
      throw DeviceSignatureException(
          'ed25519PrivateKey must be $cryptoSignSecretKeyBytes bytes, '
          'got ${ed25519PrivateKey.length}');
    }
    if (ed25519PublicKey.length != cryptoSignPublicKeyBytes) {
      throw DeviceSignatureException(
          'ed25519PublicKey must be $cryptoSignPublicKeyBytes bytes, '
          'got ${ed25519PublicKey.length}');
    }
    if (mlDsaPrivateKey.length != OqsFFI.mlDsaSecretKeyLength) {
      throw DeviceSignatureException(
          'mlDsaPrivateKey must be ${OqsFFI.mlDsaSecretKeyLength} bytes, '
          'got ${mlDsaPrivateKey.length}');
    }
    if (mlDsaPublicKey.length != OqsFFI.mlDsaPublicKeyLength) {
      throw DeviceSignatureException(
          'mlDsaPublicKey must be ${OqsFFI.mlDsaPublicKeyLength} bytes, '
          'got ${mlDsaPublicKey.length}');
    }
  }

  /// Generate a fresh Device-Sig-Keypair from the OS CSPRNG.
  ///
  /// Both halves use their respective primitive's keygen (libsodium
  /// `crypto_sign_keypair` for Ed25519, liboqs `OQS_SIG_keypair` for
  /// ML-DSA-65). Keys are NOT seed-derived — see the `INTEGRATION POINTS`
  /// block above for the rationale.
  ///
  /// Caller is responsible for persisting the result via [serialize] before
  /// the node first publishes its Auth-Manifest entry.
  factory DeviceKeyPair.generate() {
    final ed = SodiumFFI().generateEd25519KeyPair();
    final oqs = OqsFFI()..init();
    final ml = oqs.mlDsaKeypair();
    return DeviceKeyPair._(
      ed25519PrivateKey: ed.secretKey,
      ed25519PublicKey: ed.publicKey,
      mlDsaPrivateKey: ml.secretKey,
      mlDsaPublicKey: ml.publicKey,
    );
  }

  // ===========================================================================
  // Serialisation
  //
  // Wire layout (little-endian length prefixes are unnecessary because all
  // four blob lengths are constants, but we still embed them so a corrupted
  // blob fails fast rather than silently mis-aligning):
  //
  //   [4B u32  edSkLen][edSk]
  //   [4B u32  edPkLen][edPk]
  //   [4B u32  mlSkLen][mlSk]
  //   [4B u32  mlPkLen][mlPk]
  //
  // Total: 16 + 64 + 32 + 4032 + 1952 = 6096 bytes.
  // ===========================================================================

  /// Total serialised size in bytes.
  static const int serializedLength = 4 +
      cryptoSignSecretKeyBytes +
      4 +
      cryptoSignPublicKeyBytes +
      4 +
      OqsFFI.mlDsaSecretKeyLength +
      4 +
      OqsFFI.mlDsaPublicKeyLength;

  /// Serialise this keypair to a single flat byte buffer suitable for
  /// at-rest persistence. The caller must apply transport/at-rest encryption
  /// (e.g. `FileEncryption`) before writing to disk — this function does NOT
  /// encrypt.
  Uint8List serialize() {
    final out = BytesBuilder(copy: false);
    void writeBlob(Uint8List blob) {
      final lenBytes = ByteData(4)..setUint32(0, blob.length, Endian.little);
      out.add(lenBytes.buffer.asUint8List());
      out.add(blob);
    }

    writeBlob(ed25519PrivateKey);
    writeBlob(ed25519PublicKey);
    writeBlob(mlDsaPrivateKey);
    writeBlob(mlDsaPublicKey);
    return out.toBytes();
  }

  /// Deserialise a buffer produced by [serialize]. Throws
  /// [DeviceSignatureException] on truncation, length-mismatch, or wrong
  /// key sizes.
  factory DeviceKeyPair.deserialize(Uint8List bytes) {
    if (bytes.length != serializedLength) {
      throw DeviceSignatureException(
          'deserialize: expected $serializedLength bytes, got ${bytes.length}');
    }
    final view = ByteData.sublistView(bytes);
    var off = 0;

    Uint8List readBlob(int expectedLen) {
      if (off + 4 > bytes.length) {
        throw const DeviceSignatureException(
            'deserialize: truncated (length prefix)');
      }
      final len = view.getUint32(off, Endian.little);
      off += 4;
      if (len != expectedLen) {
        throw DeviceSignatureException(
            'deserialize: blob length mismatch — expected $expectedLen, got $len');
      }
      if (off + len > bytes.length) {
        throw const DeviceSignatureException(
            'deserialize: truncated (blob body)');
      }
      final blob = Uint8List.fromList(bytes.sublist(off, off + len));
      off += len;
      return blob;
    }

    final edSk = readBlob(cryptoSignSecretKeyBytes);
    final edPk = readBlob(cryptoSignPublicKeyBytes);
    final mlSk = readBlob(OqsFFI.mlDsaSecretKeyLength);
    final mlPk = readBlob(OqsFFI.mlDsaPublicKeyLength);

    return DeviceKeyPair._(
      ed25519PrivateKey: edSk,
      ed25519PublicKey: edPk,
      mlDsaPrivateKey: mlSk,
      mlDsaPublicKey: mlPk,
    );
  }

  // ===========================================================================
  // Signing
  // ===========================================================================

  /// Sign [data] with the Ed25519 half of this device key. Returns a 64-byte
  /// detached signature suitable for `NetworkPacketV3.deviceEd25519Sig`.
  Uint8List signEd25519(Uint8List data) {
    return SodiumFFI().signEd25519(data, ed25519PrivateKey);
  }

  /// Sign [data] with the ML-DSA-65 half of this device key. Returns the
  /// detached signature suitable for `NetworkPacketV3.deviceMlDsaSig`.
  ///
  /// **Bandwidth note** (§3.5): only call this for application frames. For
  /// infrastructure frames (DHT, hole-punch, ACKs, calls, heartbeats) leave
  /// `deviceMlDsaSig` empty — the receiver tolerates absence per the
  /// selectivity rules.
  Uint8List signMlDsa(Uint8List data) {
    final oqs = OqsFFI()..init();
    return oqs.mlDsaSign(data, mlDsaPrivateKey);
  }

  /// Convenience: produce both sigs over the same payload in a single call.
  ///
  /// Use for application frames where both sigs are required. Prefer the
  /// individual [signEd25519] / [signMlDsa] for infrastructure frames so the
  /// caller can skip the expensive ML-DSA op explicitly.
  ({Uint8List ed25519Sig, Uint8List mlDsaSig}) signHybrid(Uint8List data) {
    return (
      ed25519Sig: signEd25519(data),
      mlDsaSig: signMlDsa(data),
    );
  }
}

// =============================================================================
// Verification helpers (top-level — no DeviceKeyPair instance needed)
//
// The receiver does not hold the sender's private keys; it only has the
// sender's public keys (fetched from the Auth-Manifest in the 2D-DHT). These
// helpers are the canonical entry points for verifying Outer-Frame sigs.
// =============================================================================

/// Verify an Ed25519 device signature.
///
/// Returns `true` iff [signature] (64 bytes) is a valid detached Ed25519
/// signature over [data] under [publicKey] (32 bytes). Wrong-size inputs
/// return `false` (never throw) so verifier loops can stay tight.
bool verifyEd25519(Uint8List signature, Uint8List data, Uint8List publicKey) {
  return SodiumFFI().verifyEd25519(data, signature, publicKey);
}

/// Verify an ML-DSA-65 device signature.
///
/// Returns `true` iff [signature] is a valid detached ML-DSA-65 signature over
/// [data] under [publicKey] (1952 bytes). Returns `false` on size mismatch.
bool verifyMlDsa(Uint8List signature, Uint8List data, Uint8List publicKey) {
  if (publicKey.length != OqsFFI.mlDsaPublicKeyLength) return false;
  if (signature.length > OqsFFI.mlDsaSignatureLength) return false;
  final oqs = OqsFFI()..init();
  return oqs.mlDsaVerify(data, signature, publicKey);
}

/// Verify both halves of a hybrid Outer-Frame device signature.
///
/// Returns `true` iff BOTH the Ed25519 and the ML-DSA-65 signatures verify.
/// Use for application frames; for infrastructure frames where
/// `deviceMlDsaSig` is empty, call [verifyEd25519] alone.
bool verifyHybrid({
  required Uint8List data,
  required Uint8List ed25519Sig,
  required Uint8List ed25519PublicKey,
  required Uint8List mlDsaSig,
  required Uint8List mlDsaPublicKey,
}) {
  if (!verifyEd25519(ed25519Sig, data, ed25519PublicKey)) return false;
  return verifyMlDsa(mlDsaSig, data, mlDsaPublicKey);
}
