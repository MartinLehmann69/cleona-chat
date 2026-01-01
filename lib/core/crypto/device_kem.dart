/// Device-KEM keypair (X25519 + ML-KEM-768 hybrid) for V3.0 device-addressed
/// encryption.
///
/// V3.0 separates KEM into two crypto subjects:
///
/// * **User-KEM keypair** — long-lived, seed-derived via HD-Wallet, used for
///   end-to-end encryption of ApplicationFrames addressed to a *user* (Inner
///   Identity Layer, §3.3). Lives alongside the User-Sig keys in
///   `IdentityContext` / `identity_manager.dart`.
/// * **Device-KEM keypair** — *this module*. Locally generated, NOT
///   seed-derived, NOT migrated across devices. Used as the cryptographic
///   subject for operations addressed to a *device*: InfrastructureFrame
///   payload encryption (DHT, routing probes, NAT, peer-list, fragment
///   storage, S&F, identity resolution), First-Contact-Request bootstrap,
///   and the per-hop subject for the future onion layer (§2.5).
///
/// See `Cleona_Chat_Architecture_v3_0.md` §3.5b (Device KEM Keypair) and
/// §3.6 #5 (rationale for why the `m/device` branch is NOT seed-derived —
/// a seed compromise must not retroactively decrypt past or pending
/// device-addressed payloads).
///
/// Lifecycle is identical to the Device-Sig keypair (§3.5): generated once
/// at device setup, persisted in the same `device_keys.enc` container
/// (§3.7), rotated only when the device is replaced (the old DeviceID is
/// then evicted from the Auth-Manifest via §7.4).
///
/// ---------------------------------------------------------------------------
/// INTEGRATION POINTS — open hooks for follow-up tasks (NOT done in this file)
/// ---------------------------------------------------------------------------
///
/// 1. **Container persistence**: this module produces `serialize()` /
///    `deserialize` blobs. The actual on-disk container is owned by
///    [DeviceKeysStore] in `device_keys_store.dart`, which now stores both
///    the Device-Sig keypair AND this Device-KEM keypair side-by-side under
///    a v2 header (the v1-on-disk container that held only the Sig keypair
///    is migrated on first load by generating a fresh KEM keypair).
///
/// 2. **CleonaNode wiring** (Subagent D): `CleonaNode._deviceKeyPair` becomes
///    a sibling field `_deviceKemKeyPair` of type [DeviceKemKeyPair].
///    Populated from [DeviceKeysStore.loadOrCreate] alongside the Sig pair.
///
/// 3. **DeviceKemRecord publication** (Subagent B, §4.3): when (re)publishing
///    the third 2D-DHT record class (storage-key
///    `SHA-256("kem" || userId || deviceId)`), the entry MUST contain
///    [DeviceKemKeyPair.x25519PublicKey] (32 B) and
///    [DeviceKemKeyPair.mlKemPublicKey] (1184 B). See
///    `proto/cleona.proto` `DeviceKemRecordV3` fields 3 + 4.
///
/// 4. **ContactSeed URI** (Subagent B, §8.1.1): `dxk` (X25519) and `dmk`
///    (ML-KEM-768) parameters carry the same two pubkeys for
///    First-Contact-Request bootstrap.
///
/// 5. **InfrastructureFrame KEM-Encap** (Subagent C): sender encapsulates
///    under recipient's [DeviceKemKeyPair.x25519PublicKey] +
///    [DeviceKemKeyPair.mlKemPublicKey]; recipient decapsulates with its
///    own [x25519PrivateKey] + [mlKemPrivateKey]. The encap/decap math is
///    the SAME hybrid primitive used by [PerMessageKem.encrypt] /
///    [PerMessageKem.decrypt] in `per_message_kem.dart` — that module
///    already implements X25519-DH || ML-KEM-768-encapsulate combined via
///    HKDF-SHA-256 with the v2 salt. There is no need for a parallel
///    encap/decap helper in this file: callers feed the pubkeys exposed
///    here directly into `PerMessageKem.encrypt(...)` and the privkeys
///    exposed here into `PerMessageKem.decrypt(...)`.
library;

import 'dart:typed_data';

import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';

/// Exception thrown for Device-KEM-Keypair errors (malformed serialisation,
/// wrong key sizes, …).
class DeviceKemException implements Exception {
  final String message;
  const DeviceKemException(this.message);

  @override
  String toString() => 'DeviceKemException: $message';
}

/// A device-bound X25519 + ML-KEM-768 hybrid KEM keypair.
///
/// Holds the four key blobs that make up the device-addressed KEM identity
/// of a single Cleona device. Instances are NOT shared across devices — see
/// the `INTEGRATION POINTS` block at the top of this file for lifecycle
/// rules.
///
/// All key buffers are exposed read-only via getters. Mutation must go
/// through [generate] (fresh keys) or [deserialize] (load from disk).
///
/// **Note on KEM encap/decap**: this class deliberately does NOT expose
/// `encap` / `decap` helpers. The math is identical to the Per-Message-KEM
/// primitive used for User-addressed encryption — callers feed the public
/// keys exposed here into [PerMessageKem.encrypt] and the private keys into
/// [PerMessageKem.decrypt]. Duplicating the HKDF/AES-GCM glue here would
/// risk drift between the two code paths.
class DeviceKemKeyPair {
  /// X25519 secret key — 32 bytes (libsodium scalar format).
  final Uint8List x25519PrivateKey;

  /// X25519 public key — 32 bytes. Carried in `DeviceKemRecordV3.device_x25519_pk`
  /// and `ContactSeed.dxk`.
  final Uint8List x25519PublicKey;

  /// ML-KEM-768 secret key — 2400 bytes (see [OqsFFI.mlKemSecretKeyLength]).
  final Uint8List mlKemPrivateKey;

  /// ML-KEM-768 public key — 1184 bytes (see [OqsFFI.mlKemPublicKeyLength]).
  /// Carried in `DeviceKemRecordV3.device_ml_kem_pk` and `ContactSeed.dmk`.
  final Uint8List mlKemPublicKey;

  DeviceKemKeyPair._({
    required this.x25519PrivateKey,
    required this.x25519PublicKey,
    required this.mlKemPrivateKey,
    required this.mlKemPublicKey,
  }) {
    if (x25519PrivateKey.length != cryptoScalarMultScalarBytes) {
      throw DeviceKemException(
          'x25519PrivateKey must be $cryptoScalarMultScalarBytes bytes, '
          'got ${x25519PrivateKey.length}');
    }
    if (x25519PublicKey.length != cryptoScalarMultBytes) {
      throw DeviceKemException(
          'x25519PublicKey must be $cryptoScalarMultBytes bytes, '
          'got ${x25519PublicKey.length}');
    }
    if (mlKemPrivateKey.length != OqsFFI.mlKemSecretKeyLength) {
      throw DeviceKemException(
          'mlKemPrivateKey must be ${OqsFFI.mlKemSecretKeyLength} bytes, '
          'got ${mlKemPrivateKey.length}');
    }
    if (mlKemPublicKey.length != OqsFFI.mlKemPublicKeyLength) {
      throw DeviceKemException(
          'mlKemPublicKey must be ${OqsFFI.mlKemPublicKeyLength} bytes, '
          'got ${mlKemPublicKey.length}');
    }
  }

  /// Generate a fresh Device-KEM-Keypair from the OS CSPRNG.
  ///
  /// Both halves use their respective primitive's keygen
  /// ([SodiumFFI.generateX25519KeyPair] for X25519, [OqsFFI.mlKemKeypair]
  /// for ML-KEM-768). Keys are NOT seed-derived — see §3.6 #5 in the
  /// architecture doc for the rationale.
  ///
  /// Caller is responsible for persisting the result via [serialize]
  /// (through [DeviceKeysStore]) before the node first publishes its
  /// DeviceKemRecord.
  factory DeviceKemKeyPair.generate() {
    final x = SodiumFFI().generateX25519KeyPair();
    final oqs = OqsFFI()..init();
    final ml = oqs.mlKemKeypair();
    return DeviceKemKeyPair._(
      x25519PrivateKey: x.secretKey,
      x25519PublicKey: x.publicKey,
      mlKemPrivateKey: ml.secretKey,
      mlKemPublicKey: ml.publicKey,
    );
  }

  // ===========================================================================
  // Serialisation
  //
  // Wire layout (little-endian length prefixes; same shape as
  // DeviceKeyPair.serialize() in device_signature.dart so the on-disk
  // container can stitch the two blobs together verbatim):
  //
  //   [4B u32  xSkLen][xSk]
  //   [4B u32  xPkLen][xPk]
  //   [4B u32  mlSkLen][mlSk]
  //   [4B u32  mlPkLen][mlPk]
  //
  // Total: 16 + 32 + 32 + 2400 + 1184 = 3664 bytes.
  // ===========================================================================

  /// Total serialised size in bytes.
  static const int serializedLength = 4 +
      cryptoScalarMultScalarBytes +
      4 +
      cryptoScalarMultBytes +
      4 +
      OqsFFI.mlKemSecretKeyLength +
      4 +
      OqsFFI.mlKemPublicKeyLength;

  /// Serialise this keypair to a single flat byte buffer suitable for
  /// at-rest persistence. The caller must apply transport/at-rest
  /// encryption (the [DeviceKeysStore] container does this) — this
  /// function does NOT encrypt.
  Uint8List serialize() {
    final out = BytesBuilder(copy: false);
    void writeBlob(Uint8List blob) {
      final lenBytes = ByteData(4)..setUint32(0, blob.length, Endian.little);
      out.add(lenBytes.buffer.asUint8List());
      out.add(blob);
    }

    writeBlob(x25519PrivateKey);
    writeBlob(x25519PublicKey);
    writeBlob(mlKemPrivateKey);
    writeBlob(mlKemPublicKey);
    return out.toBytes();
  }

  /// Deserialise a buffer produced by [serialize]. Throws
  /// [DeviceKemException] on truncation, length-mismatch, or wrong key
  /// sizes.
  factory DeviceKemKeyPair.deserialize(Uint8List bytes) {
    if (bytes.length != serializedLength) {
      throw DeviceKemException(
          'deserialize: expected $serializedLength bytes, got ${bytes.length}');
    }
    final view = ByteData.sublistView(bytes);
    var off = 0;

    Uint8List readBlob(int expectedLen) {
      if (off + 4 > bytes.length) {
        throw const DeviceKemException(
            'deserialize: truncated (length prefix)');
      }
      final len = view.getUint32(off, Endian.little);
      off += 4;
      if (len != expectedLen) {
        throw DeviceKemException(
            'deserialize: blob length mismatch — expected $expectedLen, got $len');
      }
      if (off + len > bytes.length) {
        throw const DeviceKemException(
            'deserialize: truncated (blob body)');
      }
      final blob = Uint8List.fromList(bytes.sublist(off, off + len));
      off += len;
      return blob;
    }

    final xSk = readBlob(cryptoScalarMultScalarBytes);
    final xPk = readBlob(cryptoScalarMultBytes);
    final mlSk = readBlob(OqsFFI.mlKemSecretKeyLength);
    final mlPk = readBlob(OqsFFI.mlKemPublicKeyLength);

    return DeviceKemKeyPair._(
      x25519PrivateKey: xSk,
      x25519PublicKey: xPk,
      mlKemPrivateKey: mlSk,
      mlKemPublicKey: mlPk,
    );
  }
}
