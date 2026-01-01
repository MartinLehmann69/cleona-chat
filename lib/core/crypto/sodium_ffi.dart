/// Dart FFI bindings for libsodium.
///
/// Provides cryptographic primitives for the Cleona P2P messenger:
/// Ed25519, X25519, AES-256-GCM, SHA-256, HKDF-SHA256,
/// XSalsa20-Poly1305 (secretbox), Argon2id, and secure random.
library;

import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// ---------------------------------------------------------------------------
// libsodium constants
// ---------------------------------------------------------------------------

/// Ed25519 public key size in bytes.
const int cryptoSignPublicKeyBytes = 32;

/// Ed25519 secret key size in bytes.
const int cryptoSignSecretKeyBytes = 64;

/// Ed25519 signature size in bytes.
const int cryptoSignBytes = 64;

/// X25519 public key size in bytes.
const int cryptoScalarMultBytes = 32;

/// X25519 secret key size in bytes.
const int cryptoScalarMultScalarBytes = 32;

/// AES-256-GCM key size in bytes.
const int cryptoAeadAes256GcmKeyBytes = 32;

/// AES-256-GCM nonce size in bytes.
const int cryptoAeadAes256GcmNpubBytes = 12;

/// AES-256-GCM authentication tag overhead in bytes.
const int cryptoAeadAes256GcmABytes = 16;

/// SHA-256 digest size in bytes.
const int cryptoHashSha256Bytes = 32;

/// HMAC-SHA256 output size in bytes.
const int cryptoAuthHmacSha256Bytes = 32;

/// HMAC-SHA256 key size in bytes.
const int cryptoAuthHmacSha256KeyBytes = 32;

/// XSalsa20-Poly1305 (secretbox) key size in bytes.
const int cryptoSecretBoxKeyBytes = 32;

/// XSalsa20-Poly1305 (secretbox) nonce size in bytes.
const int cryptoSecretBoxNonceBytes = 24;

/// XSalsa20-Poly1305 (secretbox) authentication tag overhead in bytes.
const int cryptoSecretBoxMacBytes = 16;

/// Argon2id algorithm identifier.
const int cryptoPwhashAlgArgon2id13 = 2;

/// Argon2id default ops limit (moderate).
const int cryptoPwhashOpsLimitModerate = 3;

/// Argon2id default mem limit (moderate) — 256 MiB.
const int cryptoPwhashMemLimitModerate = 268435456;

/// Argon2id salt size in bytes.
const int cryptoPwhashSaltBytes = 16;

/// Ed25519 point (compressed) size in bytes.
const int cryptoCoreEd25519Bytes = 32;

/// Ed25519 scalar (mod L) size in bytes.
const int cryptoCoreEd25519ScalarBytes = 32;

/// Ed25519 uniform input (for hash-to-point) size in bytes.
const int cryptoCoreEd25519UniformBytes = 32;

/// Input size for crypto_core_ed25519_scalar_reduce (64 bytes, hash output).
const int cryptoCoreEd25519NonReducedScalarBytes = 64;

/// SHA-512 digest size in bytes.
const int cryptoHashSha512Bytes = 64;

// ---------------------------------------------------------------------------
// Native function typedefs
// ---------------------------------------------------------------------------

// sodium_init
typedef _SodiumInitNative = Int32 Function();
typedef _SodiumInitDart = int Function();

// randombytes_buf
typedef _RandombytesBufNative = Void Function(Pointer<Uint8>, Size);
typedef _RandombytesBufDart = void Function(Pointer<Uint8>, int);

// crypto_sign_keypair
typedef _SignKeypairNative = Int32 Function(
    Pointer<Uint8>, Pointer<Uint8>);
typedef _SignKeypairDart = int Function(Pointer<Uint8>, Pointer<Uint8>);

// crypto_sign_seed_keypair
typedef _SignSeedKeypairNative = Int32 Function(
    Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>);
typedef _SignSeedKeypairDart = int Function(
    Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>);

// crypto_sign_detached
typedef _SignDetachedNative = Int32 Function(Pointer<Uint8>,
    Pointer<Uint64>, Pointer<Uint8>, Uint64, Pointer<Uint8>);
typedef _SignDetachedDart = int Function(Pointer<Uint8>, Pointer<Uint64>,
    Pointer<Uint8>, int, Pointer<Uint8>);

// crypto_sign_verify_detached
typedef _SignVerifyDetachedNative = Int32 Function(
    Pointer<Uint8>, Pointer<Uint8>, Uint64, Pointer<Uint8>);
typedef _SignVerifyDetachedDart = int Function(
    Pointer<Uint8>, Pointer<Uint8>, int, Pointer<Uint8>);

// crypto_sign_ed25519_pk_to_curve25519
typedef _Ed25519PkToCurve25519Native = Int32 Function(
    Pointer<Uint8>, Pointer<Uint8>);
typedef _Ed25519PkToCurve25519Dart = int Function(
    Pointer<Uint8>, Pointer<Uint8>);

// crypto_sign_ed25519_sk_to_curve25519
typedef _Ed25519SkToCurve25519Native = Int32 Function(
    Pointer<Uint8>, Pointer<Uint8>);
typedef _Ed25519SkToCurve25519Dart = int Function(
    Pointer<Uint8>, Pointer<Uint8>);

// crypto_scalarmult_base
typedef _ScalarMultBaseNative = Int32 Function(
    Pointer<Uint8>, Pointer<Uint8>);
typedef _ScalarMultBaseDart = int Function(
    Pointer<Uint8>, Pointer<Uint8>);

// crypto_scalarmult
typedef _ScalarMultNative = Int32 Function(
    Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>);
typedef _ScalarMultDart = int Function(
    Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>);

// crypto_aead_aes256gcm_encrypt
typedef _AesGcmEncryptNative = Int32 Function(
    Pointer<Uint8>,
    Pointer<Uint64>,
    Pointer<Uint8>,
    Uint64,
    Pointer<Uint8>,
    Uint64,
    Pointer<Uint8>,
    Pointer<Uint8>,
    Pointer<Uint8>);
typedef _AesGcmEncryptDart = int Function(
    Pointer<Uint8>,
    Pointer<Uint64>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    Pointer<Uint8>,
    Pointer<Uint8>);

// crypto_aead_aes256gcm_decrypt
typedef _AesGcmDecryptNative = Int32 Function(
    Pointer<Uint8>,
    Pointer<Uint64>,
    Pointer<Uint8>,
    Pointer<Uint8>,
    Uint64,
    Pointer<Uint8>,
    Uint64,
    Pointer<Uint8>,
    Pointer<Uint8>);
typedef _AesGcmDecryptDart = int Function(
    Pointer<Uint8>,
    Pointer<Uint64>,
    Pointer<Uint8>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    Pointer<Uint8>);

// crypto_aead_aes256gcm_keygen
typedef _AesGcmKeygenNative = Void Function(Pointer<Uint8>);
typedef _AesGcmKeygenDart = void Function(Pointer<Uint8>);

// crypto_hash_sha256
typedef _HashSha256Native = Int32 Function(
    Pointer<Uint8>, Pointer<Uint8>, Uint64);
typedef _HashSha256Dart = int Function(
    Pointer<Uint8>, Pointer<Uint8>, int);

// crypto_auth_hmacsha256
typedef _HmacSha256Native = Int32 Function(
    Pointer<Uint8>, Pointer<Uint8>, Uint64, Pointer<Uint8>);
typedef _HmacSha256Dart = int Function(
    Pointer<Uint8>, Pointer<Uint8>, int, Pointer<Uint8>);

// crypto_secretbox_easy
typedef _SecretBoxEasyNative = Int32 Function(
    Pointer<Uint8>, Pointer<Uint8>, Uint64, Pointer<Uint8>, Pointer<Uint8>);
typedef _SecretBoxEasyDart = int Function(
    Pointer<Uint8>, Pointer<Uint8>, int, Pointer<Uint8>, Pointer<Uint8>);

// crypto_secretbox_open_easy
typedef _SecretBoxOpenEasyNative = Int32 Function(
    Pointer<Uint8>, Pointer<Uint8>, Uint64, Pointer<Uint8>, Pointer<Uint8>);
typedef _SecretBoxOpenEasyDart = int Function(
    Pointer<Uint8>, Pointer<Uint8>, int, Pointer<Uint8>, Pointer<Uint8>);

// crypto_pwhash
typedef _PwhashNative = Int32 Function(
    Pointer<Uint8>,
    Uint64,
    Pointer<Uint8>,
    Uint64,
    Pointer<Uint8>,
    Uint64,
    Size,
    Int32);
typedef _PwhashDart = int Function(Pointer<Uint8>, int, Pointer<Uint8>,
    int, Pointer<Uint8>, int, int, int);

// crypto_hash_sha512
typedef _HashSha512Native = Int32 Function(
    Pointer<Uint8>, Pointer<Uint8>, Uint64);
typedef _HashSha512Dart = int Function(
    Pointer<Uint8>, Pointer<Uint8>, int);

// crypto_core_ed25519_is_valid_point
typedef _Ed25519IsValidPointNative = Int32 Function(Pointer<Uint8>);
typedef _Ed25519IsValidPointDart = int Function(Pointer<Uint8>);

// crypto_core_ed25519_from_uniform
typedef _Ed25519FromUniformNative = Int32 Function(
    Pointer<Uint8>, Pointer<Uint8>);
typedef _Ed25519FromUniformDart = int Function(
    Pointer<Uint8>, Pointer<Uint8>);

// crypto_core_ed25519_add
typedef _Ed25519AddNative = Int32 Function(
    Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>);
typedef _Ed25519AddDart = int Function(
    Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>);

// crypto_scalarmult_ed25519_base_noclamp
typedef _Ed25519ScalarmultBaseNative = Int32 Function(
    Pointer<Uint8>, Pointer<Uint8>);
typedef _Ed25519ScalarmultBaseDart = int Function(
    Pointer<Uint8>, Pointer<Uint8>);

// crypto_scalarmult_ed25519_noclamp
typedef _Ed25519ScalarmultNative = Int32 Function(
    Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>);
typedef _Ed25519ScalarmultDart = int Function(
    Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>);

// crypto_core_ed25519_scalar_reduce
typedef _Ed25519ScalarReduceNative = Void Function(
    Pointer<Uint8>, Pointer<Uint8>);
typedef _Ed25519ScalarReduceDart = void Function(
    Pointer<Uint8>, Pointer<Uint8>);

// crypto_core_ed25519_scalar_add / sub / mul
typedef _Ed25519ScalarOpNative = Void Function(
    Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>);
typedef _Ed25519ScalarOpDart = void Function(
    Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>);

// crypto_core_ed25519_scalar_random
typedef _Ed25519ScalarRandomNative = Void Function(Pointer<Uint8>);
typedef _Ed25519ScalarRandomDart = void Function(Pointer<Uint8>);

// ---------------------------------------------------------------------------
// SodiumFFI — singleton with lazy initialisation
// ---------------------------------------------------------------------------

/// Exception thrown when a libsodium operation fails.
class SodiumException implements Exception {
  final String message;
  const SodiumException(this.message);

  @override
  String toString() => 'SodiumException: $message';
}

/// Low-level FFI bindings and high-level wrappers for libsodium.
///
/// Usage:
/// ```dart
/// final sodium = SodiumFFI();
/// final kp = sodium.generateEd25519KeyPair();
/// ```
class SodiumFFI {
  // Singleton
  static SodiumFFI? _instance;

  factory SodiumFFI() {
    return _instance ??= SodiumFFI._internal();
  }

  // Native function pointers
  late final _SodiumInitDart _sodiumInit;
  late final _RandombytesBufDart _randombytes;
  late final _SignKeypairDart _signKeypair;
  late final _SignSeedKeypairDart _signSeedKeypair;
  late final _SignDetachedDart _signDetached;
  late final _SignVerifyDetachedDart _signVerifyDetached;
  late final _Ed25519PkToCurve25519Dart _ed25519PkToCurve;
  late final _Ed25519SkToCurve25519Dart _ed25519SkToCurve;
  late final _ScalarMultBaseDart _scalarMultBase;
  late final _ScalarMultDart _scalarMult;
  late final _AesGcmEncryptDart _aesGcmEncrypt;
  late final _AesGcmDecryptDart _aesGcmDecrypt;
  late final _AesGcmKeygenDart _aesGcmKeygen;
  late final _HashSha256Dart _hashSha256;
  late final _HmacSha256Dart _hmacSha256;
  late final _SecretBoxEasyDart _secretBoxEasy;
  late final _SecretBoxOpenEasyDart _secretBoxOpenEasy;
  late final _PwhashDart _pwhash;
  late final _HashSha512Dart _hashSha512;
  late final _Ed25519IsValidPointDart _ed25519IsValidPoint;
  late final _Ed25519FromUniformDart _ed25519FromUniform;
  late final _Ed25519AddDart _ed25519Add;
  late final _Ed25519ScalarmultBaseDart _ed25519ScalarmultBase;
  late final _Ed25519ScalarmultDart _ed25519Scalarmult;
  late final _Ed25519ScalarReduceDart _ed25519ScalarReduce;
  late final _Ed25519ScalarOpDart _ed25519ScalarAdd;
  late final _Ed25519ScalarOpDart _ed25519ScalarSub;
  late final _Ed25519ScalarOpDart _ed25519ScalarMul;
  late final _Ed25519ScalarRandomDart _ed25519ScalarRandom;

  SodiumFFI._internal() {
    final lib = _openLibsodium();
    _bindFunctions(lib);

    final rc = _sodiumInit();
    if (rc < 0) {
      throw const SodiumException('sodium_init() failed');
    }
  }

  /// Opens the libsodium shared library for the current platform.
  static DynamicLibrary _openLibsodium() {
    if (Platform.isLinux) {
      return DynamicLibrary.open('libsodium.so');
    } else if (Platform.isMacOS) {
      return DynamicLibrary.open('libsodium.dylib');
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('libsodium.dll');
    } else if (Platform.isAndroid) {
      return DynamicLibrary.open('libsodium.so');
    } else if (Platform.isIOS) {
      // On iOS libsodium is typically statically linked.
      return DynamicLibrary.process();
    }
    throw const SodiumException(
        'Unsupported platform for libsodium');
  }

  void _bindFunctions(DynamicLibrary lib) {
    _sodiumInit =
        lib.lookupFunction<_SodiumInitNative, _SodiumInitDart>('sodium_init');

    _randombytes = lib.lookupFunction<_RandombytesBufNative,
        _RandombytesBufDart>('randombytes_buf');

    _signKeypair = lib.lookupFunction<_SignKeypairNative, _SignKeypairDart>(
        'crypto_sign_keypair');
    _signSeedKeypair = lib.lookupFunction<_SignSeedKeypairNative, _SignSeedKeypairDart>(
        'crypto_sign_seed_keypair');

    _signDetached =
        lib.lookupFunction<_SignDetachedNative, _SignDetachedDart>(
            'crypto_sign_detached');

    _signVerifyDetached = lib.lookupFunction<_SignVerifyDetachedNative,
        _SignVerifyDetachedDart>('crypto_sign_verify_detached');

    _ed25519PkToCurve = lib.lookupFunction<_Ed25519PkToCurve25519Native,
        _Ed25519PkToCurve25519Dart>('crypto_sign_ed25519_pk_to_curve25519');

    _ed25519SkToCurve = lib.lookupFunction<_Ed25519SkToCurve25519Native,
        _Ed25519SkToCurve25519Dart>('crypto_sign_ed25519_sk_to_curve25519');

    _scalarMultBase =
        lib.lookupFunction<_ScalarMultBaseNative, _ScalarMultBaseDart>(
            'crypto_scalarmult_base');

    _scalarMult = lib.lookupFunction<_ScalarMultNative, _ScalarMultDart>(
        'crypto_scalarmult');

    _aesGcmEncrypt =
        lib.lookupFunction<_AesGcmEncryptNative, _AesGcmEncryptDart>(
            'crypto_aead_aes256gcm_encrypt');

    _aesGcmDecrypt =
        lib.lookupFunction<_AesGcmDecryptNative, _AesGcmDecryptDart>(
            'crypto_aead_aes256gcm_decrypt');

    _aesGcmKeygen =
        lib.lookupFunction<_AesGcmKeygenNative, _AesGcmKeygenDart>(
            'crypto_aead_aes256gcm_keygen');

    _hashSha256 = lib.lookupFunction<_HashSha256Native, _HashSha256Dart>(
        'crypto_hash_sha256');

    _hmacSha256 = lib.lookupFunction<_HmacSha256Native, _HmacSha256Dart>(
        'crypto_auth_hmacsha256');

    _secretBoxEasy =
        lib.lookupFunction<_SecretBoxEasyNative, _SecretBoxEasyDart>(
            'crypto_secretbox_easy');

    _secretBoxOpenEasy =
        lib.lookupFunction<_SecretBoxOpenEasyNative, _SecretBoxOpenEasyDart>(
            'crypto_secretbox_open_easy');

    _pwhash =
        lib.lookupFunction<_PwhashNative, _PwhashDart>('crypto_pwhash');

    _hashSha512 = lib.lookupFunction<_HashSha512Native, _HashSha512Dart>(
        'crypto_hash_sha512');

    _ed25519IsValidPoint = lib.lookupFunction<_Ed25519IsValidPointNative,
        _Ed25519IsValidPointDart>('crypto_core_ed25519_is_valid_point');

    _ed25519FromUniform = lib.lookupFunction<_Ed25519FromUniformNative,
        _Ed25519FromUniformDart>('crypto_core_ed25519_from_uniform');

    _ed25519Add = lib.lookupFunction<_Ed25519AddNative, _Ed25519AddDart>(
        'crypto_core_ed25519_add');

    _ed25519ScalarmultBase = lib.lookupFunction<_Ed25519ScalarmultBaseNative,
        _Ed25519ScalarmultBaseDart>(
        'crypto_scalarmult_ed25519_base_noclamp');

    _ed25519Scalarmult = lib.lookupFunction<_Ed25519ScalarmultNative,
        _Ed25519ScalarmultDart>('crypto_scalarmult_ed25519_noclamp');

    _ed25519ScalarReduce = lib.lookupFunction<_Ed25519ScalarReduceNative,
        _Ed25519ScalarReduceDart>('crypto_core_ed25519_scalar_reduce');

    _ed25519ScalarAdd = lib.lookupFunction<_Ed25519ScalarOpNative,
        _Ed25519ScalarOpDart>('crypto_core_ed25519_scalar_add');
    _ed25519ScalarSub = lib.lookupFunction<_Ed25519ScalarOpNative,
        _Ed25519ScalarOpDart>('crypto_core_ed25519_scalar_sub');
    _ed25519ScalarMul = lib.lookupFunction<_Ed25519ScalarOpNative,
        _Ed25519ScalarOpDart>('crypto_core_ed25519_scalar_mul');

    _ed25519ScalarRandom = lib.lookupFunction<_Ed25519ScalarRandomNative,
        _Ed25519ScalarRandomDart>('crypto_core_ed25519_scalar_random');
  }

  // =========================================================================
  // Helper: copy Uint8List into native memory, run callback, free.
  // =========================================================================

  /// Allocates [length] bytes of native memory, copies [data] into it,
  /// and returns the pointer. Caller must [calloc.free] the result.
  Pointer<Uint8> _toNative(Uint8List data) {
    final ptr = calloc<Uint8>(data.length);
    ptr.asTypedList(data.length).setAll(0, data);
    return ptr;
  }

  /// Reads [length] bytes from [ptr] into a new [Uint8List].
  Uint8List _fromNative(Pointer<Uint8> ptr, int length) {
    return Uint8List.fromList(ptr.asTypedList(length));
  }

  // =========================================================================
  // Random
  // =========================================================================

  /// Generates [length] cryptographically secure random bytes.
  Uint8List randomBytes(int length) {
    if (length <= 0) {
      throw const SodiumException('randomBytes: length must be > 0');
    }
    final buf = calloc<Uint8>(length);
    try {
      _randombytes(buf, length);
      return _fromNative(buf, length);
    } finally {
      calloc.free(buf);
    }
  }

  // =========================================================================
  // Ed25519 Signing
  // =========================================================================

  /// Generates a new Ed25519 key pair.
  ///
  /// Returns a record of (publicKey, secretKey).
  ({Uint8List publicKey, Uint8List secretKey}) generateEd25519KeyPair() {
    final pk = calloc<Uint8>(cryptoSignPublicKeyBytes);
    final sk = calloc<Uint8>(cryptoSignSecretKeyBytes);
    try {
      final rc = _signKeypair(pk, sk);
      if (rc != 0) {
        throw const SodiumException('crypto_sign_keypair failed');
      }
      return (
        publicKey: _fromNative(pk, cryptoSignPublicKeyBytes),
        secretKey: _fromNative(sk, cryptoSignSecretKeyBytes),
      );
    } finally {
      calloc.free(pk);
      calloc.free(sk);
    }
  }

  /// Generate an Ed25519 key pair from a 32-byte seed (deterministic).
  ({Uint8List publicKey, Uint8List secretKey}) generateEd25519KeyPairFromSeed(
      Uint8List seed) {
    if (seed.length != 32) {
      throw SodiumException('Ed25519 seed must be 32 bytes, got ${seed.length}');
    }
    final pk = calloc<Uint8>(cryptoSignPublicKeyBytes);
    final sk = calloc<Uint8>(cryptoSignSecretKeyBytes);
    final s = _toNative(seed);
    try {
      final rc = _signSeedKeypair(pk, sk, s);
      if (rc != 0) {
        throw const SodiumException('crypto_sign_seed_keypair failed');
      }
      return (
        publicKey: _fromNative(pk, cryptoSignPublicKeyBytes),
        secretKey: _fromNative(sk, cryptoSignSecretKeyBytes),
      );
    } finally {
      calloc.free(pk);
      calloc.free(sk);
      calloc.free(s);
    }
  }

  /// Signs [message] with the Ed25519 [secretKey].
  ///
  /// Returns the detached 64-byte signature.
  Uint8List signEd25519(Uint8List message, Uint8List secretKey) {
    if (secretKey.length != cryptoSignSecretKeyBytes) {
      throw SodiumException(
          'signEd25519: secretKey must be $cryptoSignSecretKeyBytes bytes, '
          'got ${secretKey.length}');
    }
    final sig = calloc<Uint8>(cryptoSignBytes);
    final sigLen = calloc<Uint64>(1);
    final msg = _toNative(message);
    final sk = _toNative(secretKey);
    try {
      final rc = _signDetached(sig, sigLen, msg, message.length, sk);
      if (rc != 0) {
        throw const SodiumException('crypto_sign_detached failed');
      }
      return _fromNative(sig, cryptoSignBytes);
    } finally {
      calloc.free(sig);
      calloc.free(sigLen);
      calloc.free(msg);
      calloc.free(sk);
    }
  }

  /// Verifies an Ed25519 [signature] on [message] with [publicKey].
  bool verifyEd25519(
      Uint8List message, Uint8List signature, Uint8List publicKey) {
    if (signature.length != cryptoSignBytes) {
      return false;
    }
    if (publicKey.length != cryptoSignPublicKeyBytes) {
      return false;
    }
    final sig = _toNative(signature);
    final msg = _toNative(message);
    final pk = _toNative(publicKey);
    try {
      final rc = _signVerifyDetached(sig, msg, message.length, pk);
      return rc == 0;
    } finally {
      calloc.free(sig);
      calloc.free(msg);
      calloc.free(pk);
    }
  }

  // =========================================================================
  // Ed25519 → X25519 conversion
  // =========================================================================

  /// Converts an Ed25519 public key to an X25519 public key.
  Uint8List ed25519PkToX25519(Uint8List ed25519Pk) {
    if (ed25519Pk.length != cryptoSignPublicKeyBytes) {
      throw SodiumException(
          'ed25519PkToX25519: ed25519Pk must be $cryptoSignPublicKeyBytes bytes');
    }
    final x25519Pk = calloc<Uint8>(cryptoScalarMultBytes);
    final edPk = _toNative(ed25519Pk);
    try {
      final rc = _ed25519PkToCurve(x25519Pk, edPk);
      if (rc != 0) {
        throw const SodiumException(
            'crypto_sign_ed25519_pk_to_curve25519 failed');
      }
      return _fromNative(x25519Pk, cryptoScalarMultBytes);
    } finally {
      calloc.free(x25519Pk);
      calloc.free(edPk);
    }
  }

  /// Converts an Ed25519 secret key to an X25519 secret key.
  Uint8List ed25519SkToX25519(Uint8List ed25519Sk) {
    if (ed25519Sk.length != cryptoSignSecretKeyBytes) {
      throw SodiumException(
          'ed25519SkToX25519: ed25519Sk must be $cryptoSignSecretKeyBytes bytes');
    }
    final x25519Sk = calloc<Uint8>(cryptoScalarMultScalarBytes);
    final edSk = _toNative(ed25519Sk);
    try {
      final rc = _ed25519SkToCurve(x25519Sk, edSk);
      if (rc != 0) {
        throw const SodiumException(
            'crypto_sign_ed25519_sk_to_curve25519 failed');
      }
      return _fromNative(x25519Sk, cryptoScalarMultScalarBytes);
    } finally {
      calloc.free(x25519Sk);
      calloc.free(edSk);
    }
  }

  // =========================================================================
  // X25519 (Diffie-Hellman)
  // =========================================================================

  /// Generates a standalone X25519 key pair.
  ///
  /// Uses Ed25519 key generation internally and converts to X25519.
  ({Uint8List publicKey, Uint8List secretKey}) generateX25519KeyPair() {
    final ed = generateEd25519KeyPair();
    final x25519Sk = ed25519SkToX25519(ed.secretKey);
    // Derive public key from the X25519 secret key via base-point
    // multiplication. This is equivalent to ed25519PkToX25519 but more
    // direct for standalone X25519 usage.
    final pk = calloc<Uint8>(cryptoScalarMultBytes);
    final sk = _toNative(x25519Sk);
    try {
      final rc = _scalarMultBase(pk, sk);
      if (rc != 0) {
        throw const SodiumException('crypto_scalarmult_base failed');
      }
      return (
        publicKey: _fromNative(pk, cryptoScalarMultBytes),
        secretKey: x25519Sk,
      );
    } finally {
      calloc.free(pk);
      calloc.free(sk);
    }
  }

  /// Performs X25519 scalar multiplication (Diffie-Hellman).
  ///
  /// Computes the shared secret from our [secretKey] and the peer's
  /// [publicKey]. Both must be 32 bytes (X25519 format).
  Uint8List x25519ScalarMult(Uint8List secretKey, Uint8List publicKey) {
    if (secretKey.length != cryptoScalarMultScalarBytes) {
      throw SodiumException(
          'x25519ScalarMult: secretKey must be $cryptoScalarMultScalarBytes bytes');
    }
    if (publicKey.length != cryptoScalarMultBytes) {
      throw SodiumException(
          'x25519ScalarMult: publicKey must be $cryptoScalarMultBytes bytes');
    }
    final q = calloc<Uint8>(cryptoScalarMultBytes);
    final n = _toNative(secretKey);
    final p = _toNative(publicKey);
    try {
      final rc = _scalarMult(q, n, p);
      if (rc != 0) {
        throw const SodiumException('crypto_scalarmult failed');
      }
      return _fromNative(q, cryptoScalarMultBytes);
    } finally {
      calloc.free(q);
      calloc.free(n);
      calloc.free(p);
    }
  }

  // =========================================================================
  // AES-256-GCM
  // =========================================================================

  /// Generates a random AES-256-GCM key (32 bytes).
  Uint8List generateAesKey() {
    final key = calloc<Uint8>(cryptoAeadAes256GcmKeyBytes);
    try {
      _aesGcmKeygen(key);
      return _fromNative(key, cryptoAeadAes256GcmKeyBytes);
    } finally {
      calloc.free(key);
    }
  }

  /// Generates a random nonce suitable for AES-256-GCM (12 bytes).
  Uint8List generateNonce() {
    return randomBytes(cryptoAeadAes256GcmNpubBytes);
  }

  /// Encrypts [plaintext] with AES-256-GCM.
  ///
  /// [key] must be 32 bytes, [nonce] must be 12 bytes.
  /// Optional [ad] for additional authenticated data.
  /// Returns ciphertext with appended authentication tag.
  Uint8List aesGcmEncrypt(Uint8List plaintext, Uint8List key, Uint8List nonce,
      {Uint8List? ad}) {
    if (key.length != cryptoAeadAes256GcmKeyBytes) {
      throw SodiumException(
          'aesGcmEncrypt: key must be $cryptoAeadAes256GcmKeyBytes bytes');
    }
    if (nonce.length != cryptoAeadAes256GcmNpubBytes) {
      throw SodiumException(
          'aesGcmEncrypt: nonce must be $cryptoAeadAes256GcmNpubBytes bytes');
    }

    final cLen = plaintext.length + cryptoAeadAes256GcmABytes;
    final c = calloc<Uint8>(cLen);
    final cLenOut = calloc<Uint64>(1);
    final m = _toNative(plaintext);
    final k = _toNative(key);
    final n = _toNative(nonce);
    final adPtr = ad != null ? _toNative(ad) : nullptr.cast<Uint8>();
    final adLen = ad?.length ?? 0;

    try {
      final rc = _aesGcmEncrypt(
        c,
        cLenOut,
        m,
        plaintext.length,
        adPtr,
        adLen,
        nullptr.cast<Uint8>(), // nsec (unused, must be null)
        n,
        k,
      );
      if (rc != 0) {
        throw const SodiumException(
            'crypto_aead_aes256gcm_encrypt failed');
      }
      return _fromNative(c, cLen);
    } finally {
      calloc.free(c);
      calloc.free(cLenOut);
      calloc.free(m);
      calloc.free(k);
      calloc.free(n);
      if (ad != null) calloc.free(adPtr);
    }
  }

  /// Decrypts AES-256-GCM [ciphertext] (with appended auth tag).
  ///
  /// [key] must be 32 bytes, [nonce] must be 12 bytes.
  /// Throws [SodiumException] if decryption or authentication fails.
  Uint8List aesGcmDecrypt(
      Uint8List ciphertext, Uint8List key, Uint8List nonce,
      {Uint8List? ad}) {
    if (key.length != cryptoAeadAes256GcmKeyBytes) {
      throw SodiumException(
          'aesGcmDecrypt: key must be $cryptoAeadAes256GcmKeyBytes bytes');
    }
    if (nonce.length != cryptoAeadAes256GcmNpubBytes) {
      throw SodiumException(
          'aesGcmDecrypt: nonce must be $cryptoAeadAes256GcmNpubBytes bytes');
    }
    if (ciphertext.length < cryptoAeadAes256GcmABytes) {
      throw const SodiumException(
          'aesGcmDecrypt: ciphertext too short');
    }

    final mLen = ciphertext.length - cryptoAeadAes256GcmABytes;
    final m = calloc<Uint8>(mLen == 0 ? 1 : mLen);
    final mLenOut = calloc<Uint64>(1);
    final c = _toNative(ciphertext);
    final k = _toNative(key);
    final n = _toNative(nonce);
    final adPtr = ad != null ? _toNative(ad) : nullptr.cast<Uint8>();
    final adLen = ad?.length ?? 0;

    try {
      final rc = _aesGcmDecrypt(
        m,
        mLenOut,
        nullptr.cast<Uint8>(), // nsec (unused)
        c,
        ciphertext.length,
        adPtr,
        adLen,
        n,
        k,
      );
      if (rc != 0) {
        throw const SodiumException(
            'crypto_aead_aes256gcm_decrypt failed — '
            'authentication or decryption error');
      }
      return _fromNative(m, mLen);
    } finally {
      calloc.free(m);
      calloc.free(mLenOut);
      calloc.free(c);
      calloc.free(k);
      calloc.free(n);
      if (ad != null) calloc.free(adPtr);
    }
  }

  // =========================================================================
  // SHA-256
  // =========================================================================

  /// Computes the SHA-256 hash of [data].
  Uint8List sha256(Uint8List data) {
    final out = calloc<Uint8>(cryptoHashSha256Bytes);
    final inp = _toNative(data);
    try {
      final rc = _hashSha256(out, inp, data.length);
      if (rc != 0) {
        throw const SodiumException('crypto_hash_sha256 failed');
      }
      return _fromNative(out, cryptoHashSha256Bytes);
    } finally {
      calloc.free(out);
      calloc.free(inp);
    }
  }

  // =========================================================================
  // HMAC-SHA256
  // =========================================================================

  /// Computes HMAC-SHA256([data], [key]). Returns 32 bytes.
  Uint8List hmacSha256(Uint8List key, Uint8List data) {
    return _hmacSha256Compute(key, data);
  }

  Uint8List _hmacSha256Compute(Uint8List key, Uint8List data) {
    final out = calloc<Uint8>(cryptoAuthHmacSha256Bytes);
    final inp = _toNative(data);
    final k = _toNative(key);
    try {
      final rc = _hmacSha256(out, inp, data.length, k);
      if (rc != 0) {
        throw const SodiumException('crypto_auth_hmacsha256 failed');
      }
      return _fromNative(out, cryptoAuthHmacSha256Bytes);
    } finally {
      calloc.free(out);
      calloc.free(inp);
      calloc.free(k);
    }
  }

  // =========================================================================
  // HKDF-SHA256 (RFC 5869)
  // =========================================================================

  /// Derives key material using HKDF-SHA256.
  ///
  /// [ikm]: input keying material.
  /// [salt]: optional salt (if null or empty, a zero-filled salt is used).
  /// [info]: context/application-specific info.
  /// [length]: desired output length in bytes (max 255 * 32 = 8160).
  Uint8List hkdfSha256(
    Uint8List ikm, {
    Uint8List? salt,
    Uint8List? info,
    required int length,
  }) {
    if (length <= 0 || length > 255 * cryptoAuthHmacSha256Bytes) {
      throw SodiumException(
          'hkdfSha256: length must be 1..${255 * cryptoAuthHmacSha256Bytes}');
    }

    // --- Extract ---
    final effectiveSalt = (salt != null && salt.isNotEmpty)
        ? salt
        : Uint8List(cryptoAuthHmacSha256Bytes); // all zeros
    final prk = _hmacSha256Compute(effectiveSalt, ikm);

    // --- Expand ---
    final infoBytes = info ?? Uint8List(0);
    final n = (length + cryptoAuthHmacSha256Bytes - 1) ~/
        cryptoAuthHmacSha256Bytes;
    final okm = BytesBuilder(copy: false);
    var prev = Uint8List(0);

    for (var i = 1; i <= n; i++) {
      final input = BytesBuilder(copy: false)
        ..add(prev)
        ..add(infoBytes)
        ..add(Uint8List.fromList([i]));
      prev = _hmacSha256Compute(prk, input.toBytes());
      okm.add(prev);
    }

    return Uint8List.fromList(okm.toBytes().sublist(0, length));
  }

  // =========================================================================
  // XSalsa20-Poly1305 (secretbox) — for DB encryption
  // =========================================================================

  /// Encrypts [plaintext] using XSalsa20-Poly1305 (secretbox).
  ///
  /// [key] must be 32 bytes, [nonce] must be 24 bytes.
  /// Returns ciphertext with prepended MAC (16 + plaintext.length bytes).
  Uint8List secretBoxEncrypt(
      Uint8List plaintext, Uint8List key, Uint8List nonce) {
    if (key.length != cryptoSecretBoxKeyBytes) {
      throw SodiumException(
          'secretBoxEncrypt: key must be $cryptoSecretBoxKeyBytes bytes');
    }
    if (nonce.length != cryptoSecretBoxNonceBytes) {
      throw SodiumException(
          'secretBoxEncrypt: nonce must be $cryptoSecretBoxNonceBytes bytes');
    }
    final cLen = cryptoSecretBoxMacBytes + plaintext.length;
    final c = calloc<Uint8>(cLen);
    final m = _toNative(plaintext);
    final n = _toNative(nonce);
    final k = _toNative(key);
    try {
      final rc = _secretBoxEasy(c, m, plaintext.length, n, k);
      if (rc != 0) {
        throw const SodiumException('crypto_secretbox_easy failed');
      }
      return _fromNative(c, cLen);
    } finally {
      calloc.free(c);
      calloc.free(m);
      calloc.free(n);
      calloc.free(k);
    }
  }

  /// Decrypts XSalsa20-Poly1305 (secretbox) [ciphertext].
  ///
  /// [key] must be 32 bytes, [nonce] must be 24 bytes.
  /// Throws [SodiumException] if authentication fails.
  Uint8List secretBoxDecrypt(
      Uint8List ciphertext, Uint8List key, Uint8List nonce) {
    if (key.length != cryptoSecretBoxKeyBytes) {
      throw SodiumException(
          'secretBoxDecrypt: key must be $cryptoSecretBoxKeyBytes bytes');
    }
    if (nonce.length != cryptoSecretBoxNonceBytes) {
      throw SodiumException(
          'secretBoxDecrypt: nonce must be $cryptoSecretBoxNonceBytes bytes');
    }
    if (ciphertext.length < cryptoSecretBoxMacBytes) {
      throw const SodiumException(
          'secretBoxDecrypt: ciphertext too short');
    }
    final mLen = ciphertext.length - cryptoSecretBoxMacBytes;
    final m = calloc<Uint8>(mLen == 0 ? 1 : mLen);
    final c = _toNative(ciphertext);
    final n = _toNative(nonce);
    final k = _toNative(key);
    try {
      final rc = _secretBoxOpenEasy(m, c, ciphertext.length, n, k);
      if (rc != 0) {
        throw const SodiumException(
            'crypto_secretbox_open_easy failed — authentication error');
      }
      return _fromNative(m, mLen);
    } finally {
      calloc.free(m);
      calloc.free(c);
      calloc.free(n);
      calloc.free(k);
    }
  }

  // =========================================================================
  // Argon2id (password hashing / key derivation)
  // =========================================================================

  /// Derives a key from [password] using Argon2id.
  ///
  /// [salt] must be 16 bytes. [keyLength] is the desired output length.
  /// [opsLimit] and [memLimit] default to moderate values.
  Uint8List argon2id(
    Uint8List password,
    Uint8List salt, {
    required int keyLength,
    int opsLimit = cryptoPwhashOpsLimitModerate,
    int memLimit = cryptoPwhashMemLimitModerate,
  }) {
    if (salt.length != cryptoPwhashSaltBytes) {
      throw SodiumException(
          'argon2id: salt must be $cryptoPwhashSaltBytes bytes');
    }
    if (keyLength <= 0 || keyLength > 64) {
      throw const SodiumException(
          'argon2id: keyLength must be 1..64');
    }
    final out = calloc<Uint8>(keyLength);
    final pwd = _toNative(password);
    final s = _toNative(salt);
    try {
      final rc = _pwhash(
        out,
        keyLength,
        pwd.cast<Uint8>(),
        password.length,
        s,
        opsLimit,
        memLimit,
        cryptoPwhashAlgArgon2id13,
      );
      if (rc != 0) {
        throw const SodiumException('crypto_pwhash (argon2id) failed');
      }
      return _fromNative(out, keyLength);
    } finally {
      calloc.free(out);
      calloc.free(pwd);
      calloc.free(s);
    }
  }

  // =========================================================================
  // SHA-512 (needed for Ed25519 scalar derivation)
  // =========================================================================

  /// SHA-512 digest (64 bytes).
  Uint8List sha512(Uint8List data) {
    final out = calloc<Uint8>(cryptoHashSha512Bytes);
    final inPtr = _toNative(data);
    try {
      final rc = _hashSha512(out, inPtr, data.length);
      if (rc != 0) throw const SodiumException('crypto_hash_sha512 failed');
      return _fromNative(out, cryptoHashSha512Bytes);
    } finally {
      calloc.free(out);
      calloc.free(inPtr);
    }
  }

  // =========================================================================
  // Ed25519 curve arithmetic (§24.4 Linkable Ring Signatures).
  //
  // These wrap libsodium's low-level ed25519 primitives. Callers are
  // responsible for feeding valid scalars (mod L) and points (on-curve).
  // =========================================================================

  /// Returns true if [point] is a valid compressed Ed25519 point.
  bool ed25519IsValidPoint(Uint8List point) {
    if (point.length != cryptoCoreEd25519Bytes) return false;
    final p = _toNative(point);
    try {
      return _ed25519IsValidPoint(p) == 1;
    } finally {
      calloc.free(p);
    }
  }

  /// Maps a 32-byte uniform value to an Ed25519 point (hash-to-curve).
  Uint8List ed25519FromUniform(Uint8List uniform) {
    if (uniform.length != cryptoCoreEd25519UniformBytes) {
      throw SodiumException(
          'ed25519FromUniform: uniform must be $cryptoCoreEd25519UniformBytes bytes');
    }
    final out = calloc<Uint8>(cryptoCoreEd25519Bytes);
    final u = _toNative(uniform);
    try {
      final rc = _ed25519FromUniform(out, u);
      if (rc != 0) {
        throw const SodiumException('crypto_core_ed25519_from_uniform failed');
      }
      return _fromNative(out, cryptoCoreEd25519Bytes);
    } finally {
      calloc.free(out);
      calloc.free(u);
    }
  }

  /// Adds two Ed25519 points: r = p + q.
  Uint8List ed25519Add(Uint8List p, Uint8List q) {
    if (p.length != cryptoCoreEd25519Bytes ||
        q.length != cryptoCoreEd25519Bytes) {
      throw const SodiumException('ed25519Add: points must be 32 bytes each');
    }
    final out = calloc<Uint8>(cryptoCoreEd25519Bytes);
    final pPtr = _toNative(p);
    final qPtr = _toNative(q);
    try {
      final rc = _ed25519Add(out, pPtr, qPtr);
      if (rc != 0) {
        throw const SodiumException('crypto_core_ed25519_add failed');
      }
      return _fromNative(out, cryptoCoreEd25519Bytes);
    } finally {
      calloc.free(out);
      calloc.free(pPtr);
      calloc.free(qPtr);
    }
  }

  /// Returns scalar · G (base-point scalar multiplication, no clamping).
  Uint8List ed25519ScalarmultBase(Uint8List scalar) {
    if (scalar.length != cryptoCoreEd25519ScalarBytes) {
      throw SodiumException(
          'ed25519ScalarmultBase: scalar must be $cryptoCoreEd25519ScalarBytes bytes');
    }
    final out = calloc<Uint8>(cryptoCoreEd25519Bytes);
    final s = _toNative(scalar);
    try {
      final rc = _ed25519ScalarmultBase(out, s);
      if (rc != 0) {
        throw const SodiumException(
            'crypto_scalarmult_ed25519_base_noclamp failed');
      }
      return _fromNative(out, cryptoCoreEd25519Bytes);
    } finally {
      calloc.free(out);
      calloc.free(s);
    }
  }

  /// Returns scalar · point (variable-base scalar multiplication, no clamping).
  Uint8List ed25519Scalarmult(Uint8List scalar, Uint8List point) {
    if (scalar.length != cryptoCoreEd25519ScalarBytes) {
      throw const SodiumException('ed25519Scalarmult: scalar must be 32 bytes');
    }
    if (point.length != cryptoCoreEd25519Bytes) {
      throw const SodiumException('ed25519Scalarmult: point must be 32 bytes');
    }
    final out = calloc<Uint8>(cryptoCoreEd25519Bytes);
    final s = _toNative(scalar);
    final p = _toNative(point);
    try {
      final rc = _ed25519Scalarmult(out, s, p);
      if (rc != 0) {
        throw const SodiumException(
            'crypto_scalarmult_ed25519_noclamp failed');
      }
      return _fromNative(out, cryptoCoreEd25519Bytes);
    } finally {
      calloc.free(out);
      calloc.free(s);
      calloc.free(p);
    }
  }

  /// Reduces a 64-byte input modulo the Ed25519 subgroup order L.
  Uint8List ed25519ScalarReduce(Uint8List wide) {
    if (wide.length != cryptoCoreEd25519NonReducedScalarBytes) {
      throw const SodiumException(
          'ed25519ScalarReduce: input must be 64 bytes');
    }
    final out = calloc<Uint8>(cryptoCoreEd25519ScalarBytes);
    final w = _toNative(wide);
    try {
      _ed25519ScalarReduce(out, w);
      return _fromNative(out, cryptoCoreEd25519ScalarBytes);
    } finally {
      calloc.free(out);
      calloc.free(w);
    }
  }

  /// a + b mod L.
  Uint8List ed25519ScalarAdd(Uint8List a, Uint8List b) {
    final out = calloc<Uint8>(cryptoCoreEd25519ScalarBytes);
    final aPtr = _toNative(a);
    final bPtr = _toNative(b);
    try {
      _ed25519ScalarAdd(out, aPtr, bPtr);
      return _fromNative(out, cryptoCoreEd25519ScalarBytes);
    } finally {
      calloc.free(out);
      calloc.free(aPtr);
      calloc.free(bPtr);
    }
  }

  /// a - b mod L.
  Uint8List ed25519ScalarSub(Uint8List a, Uint8List b) {
    final out = calloc<Uint8>(cryptoCoreEd25519ScalarBytes);
    final aPtr = _toNative(a);
    final bPtr = _toNative(b);
    try {
      _ed25519ScalarSub(out, aPtr, bPtr);
      return _fromNative(out, cryptoCoreEd25519ScalarBytes);
    } finally {
      calloc.free(out);
      calloc.free(aPtr);
      calloc.free(bPtr);
    }
  }

  /// a · b mod L.
  Uint8List ed25519ScalarMul(Uint8List a, Uint8List b) {
    final out = calloc<Uint8>(cryptoCoreEd25519ScalarBytes);
    final aPtr = _toNative(a);
    final bPtr = _toNative(b);
    try {
      _ed25519ScalarMul(out, aPtr, bPtr);
      return _fromNative(out, cryptoCoreEd25519ScalarBytes);
    } finally {
      calloc.free(out);
      calloc.free(aPtr);
      calloc.free(bPtr);
    }
  }

  /// Returns a uniformly random scalar in [0, L).
  Uint8List ed25519ScalarRandom() {
    final out = calloc<Uint8>(cryptoCoreEd25519ScalarBytes);
    try {
      _ed25519ScalarRandom(out);
      return _fromNative(out, cryptoCoreEd25519ScalarBytes);
    } finally {
      calloc.free(out);
    }
  }

  /// Derives the Ed25519 scalar "a" from a libsodium 64-byte secret key
  /// (which stores seed[0..32] || pk[32..64]). Uses the standard
  /// SHA-512(seed)[0..32] + clamp + mod-L-reduction.
  Uint8List ed25519ScalarFromSecretKey(Uint8List sk) {
    if (sk.length != cryptoSignSecretKeyBytes) {
      throw const SodiumException(
          'ed25519ScalarFromSecretKey: sk must be 64 bytes');
    }
    final seed = Uint8List.fromList(sk.sublist(0, 32));
    final h = sha512(seed);
    // Clamp h[0..32] per RFC 8032.
    final a = Uint8List.fromList(h.sublist(0, 32));
    a[0] &= 248;
    a[31] &= 127;
    a[31] |= 64;
    // Reduce clamped scalar into canonical [0, L) range by padding to 64 bytes.
    final padded = Uint8List(64);
    padded.setRange(0, 32, a);
    return ed25519ScalarReduce(padded);
  }
}
