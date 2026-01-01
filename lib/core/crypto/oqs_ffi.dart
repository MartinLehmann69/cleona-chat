/// Dart FFI bindings for liboqs (Open Quantum Safe).
///
/// Provides post-quantum cryptographic primitives:
/// - ML-KEM-768 (Key Encapsulation Mechanism)
/// - ML-DSA-65 (Digital Signature Algorithm)
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:cleona/core/crypto/sodium_ffi.dart' show SodiumFFI;

// ---------------------------------------------------------------------------
// liboqs C function typedefs (native + dart)
// ---------------------------------------------------------------------------

// OQS_init
typedef _OqsInitNative = Void Function();
typedef _OqsInitDart = void Function();

// OQS_KEM_new / OQS_KEM_free
typedef _KemNewNative = Pointer<Void> Function(Pointer<Utf8> methodName);
typedef _KemNewDart = Pointer<Void> Function(Pointer<Utf8> methodName);

typedef _KemFreeNative = Void Function(Pointer<Void> kem);
typedef _KemFreeDart = void Function(Pointer<Void> kem);

// OQS_KEM_keypair
typedef _KemKeypairNative = Int32 Function(
  Pointer<Void> kem,
  Pointer<Uint8> publicKey,
  Pointer<Uint8> secretKey,
);
typedef _KemKeypairDart = int Function(
  Pointer<Void> kem,
  Pointer<Uint8> publicKey,
  Pointer<Uint8> secretKey,
);

// OQS_KEM_encaps
typedef _KemEncapsNative = Int32 Function(
  Pointer<Void> kem,
  Pointer<Uint8> ciphertext,
  Pointer<Uint8> sharedSecret,
  Pointer<Uint8> publicKey,
);
typedef _KemEncapsDart = int Function(
  Pointer<Void> kem,
  Pointer<Uint8> ciphertext,
  Pointer<Uint8> sharedSecret,
  Pointer<Uint8> publicKey,
);

// OQS_KEM_decaps
typedef _KemDecapsNative = Int32 Function(
  Pointer<Void> kem,
  Pointer<Uint8> sharedSecret,
  Pointer<Uint8> ciphertext,
  Pointer<Uint8> secretKey,
);
typedef _KemDecapsDart = int Function(
  Pointer<Void> kem,
  Pointer<Uint8> sharedSecret,
  Pointer<Uint8> ciphertext,
  Pointer<Uint8> secretKey,
);

// OQS_SIG_new / OQS_SIG_free
typedef _SigNewNative = Pointer<Void> Function(Pointer<Utf8> methodName);
typedef _SigNewDart = Pointer<Void> Function(Pointer<Utf8> methodName);

typedef _SigFreeNative = Void Function(Pointer<Void> sig);
typedef _SigFreeDart = void Function(Pointer<Void> sig);

// OQS_SIG_keypair
typedef _SigKeypairNative = Int32 Function(
  Pointer<Void> sig,
  Pointer<Uint8> publicKey,
  Pointer<Uint8> secretKey,
);
typedef _SigKeypairDart = int Function(
  Pointer<Void> sig,
  Pointer<Uint8> publicKey,
  Pointer<Uint8> secretKey,
);

// OQS_randombytes_custom_algorithm
typedef _RandCustomNative = Void Function(
  Pointer<NativeFunction<Void Function(Pointer<Uint8>, Size)>> algorithmPtr,
);
typedef _RandCustomDart = void Function(
  Pointer<NativeFunction<Void Function(Pointer<Uint8>, Size)>> algorithmPtr,
);

// OQS_randombytes_switch_algorithm
typedef _RandSwitchNative = Int32 Function(Pointer<Utf8> algorithm);
typedef _RandSwitchDart = int Function(Pointer<Utf8> algorithm);

// OQS_SIG_sign
typedef _SigSignNative = Int32 Function(
  Pointer<Void> sig,
  Pointer<Uint8> signature,
  Pointer<Size> signatureLen,
  Pointer<Uint8> message,
  Size messageLen,
  Pointer<Uint8> secretKey,
);
typedef _SigSignDart = int Function(
  Pointer<Void> sig,
  Pointer<Uint8> signature,
  Pointer<Size> signatureLen,
  Pointer<Uint8> message,
  int messageLen,
  Pointer<Uint8> secretKey,
);

// OQS_SIG_verify
typedef _SigVerifyNative = Int32 Function(
  Pointer<Void> sig,
  Pointer<Uint8> message,
  Size messageLen,
  Pointer<Uint8> signature,
  Size signatureLen,
  Pointer<Uint8> publicKey,
);
typedef _SigVerifyDart = int Function(
  Pointer<Void> sig,
  Pointer<Uint8> message,
  int messageLen,
  Pointer<Uint8> signature,
  int signatureLen,
  Pointer<Uint8> publicKey,
);

// ---------------------------------------------------------------------------
// OQS_STATUS
// ---------------------------------------------------------------------------

/// OQS return codes.
class OqsStatus {
  OqsStatus._();

  static const int success = 0;
  static const int error = -1;
}

// ---------------------------------------------------------------------------
// OqsFFI — singleton with high-level wrapper methods
// ---------------------------------------------------------------------------

/// FFI bindings to liboqs for post-quantum cryptography.
///
/// Usage:
/// ```dart
/// final oqs = OqsFFI();
/// oqs.init();
/// final (pk, sk) = oqs.mlKemKeypair();
/// final (ct, ss) = oqs.mlKemEncapsulate(pk);
/// final ss2 = oqs.mlKemDecapsulate(ct, sk);
/// assert(ss == ss2);
/// ```
class OqsFFI {
  factory OqsFFI() => _instance ??= OqsFFI._internal();

  OqsFFI._internal() {
    _lib = _openLib();
    _bindFunctions();
  }

  static OqsFFI? _instance;

  static DynamicLibrary _openLib() {
    if (Platform.isIOS) return DynamicLibrary.process();
    if (Platform.isAndroid || Platform.isLinux) return DynamicLibrary.open('liboqs.so');
    if (Platform.isMacOS) {
      for (final p in [
        'liboqs.dylib',
        '@executable_path/../Frameworks/liboqs.dylib',
        '/opt/homebrew/lib/liboqs.dylib',
        '/usr/local/lib/liboqs.dylib',
      ]) {
        try { return DynamicLibrary.open(p); } catch (_) {}
      }
      throw StateError('liboqs.dylib not found');
    }
    if (Platform.isWindows) return DynamicLibrary.open('liboqs.dll');
    return DynamicLibrary.open('liboqs.so');
  }

  // ---- ML-KEM-768 sizes ----

  /// ML-KEM-768 public key length in bytes.
  static const int mlKemPublicKeyLength = 1184;

  /// ML-KEM-768 secret key length in bytes.
  static const int mlKemSecretKeyLength = 2400;

  /// ML-KEM-768 ciphertext length in bytes.
  static const int mlKemCiphertextLength = 1088;

  /// ML-KEM-768 shared secret length in bytes.
  static const int mlKemSharedSecretLength = 32;

  // ---- ML-DSA-65 sizes ----

  /// ML-DSA-65 public key length in bytes.
  static const int mlDsaPublicKeyLength = 1952;

  /// ML-DSA-65 secret key length in bytes.
  static const int mlDsaSecretKeyLength = 4032;

  /// ML-DSA-65 maximum signature length in bytes.
  static const int mlDsaSignatureLength = 3309;

  // ---- Algorithm identifiers ----

  static const String _kemAlgorithm = 'ML-KEM-768';
  static const String _sigAlgorithm = 'ML-DSA-65';

  // ---- Native library & resolved functions ----

  late final DynamicLibrary _lib;

  late final _OqsInitDart _oqsInit;
  late final _KemNewDart _kemNew;
  late final _KemFreeDart _kemFree;
  late final _KemKeypairDart _kemKeypair;
  late final _KemEncapsDart _kemEncaps;
  late final _KemDecapsDart _kemDecaps;
  late final _SigNewDart _sigNew;
  late final _SigFreeDart _sigFree;
  late final _SigKeypairDart _sigKeypair;
  late final _SigSignDart _sigSign;
  late final _SigVerifyDart _sigVerify;
  late final _RandCustomDart _randCustom;
  late final _RandSwitchDart _randSwitch;

  bool _initialized = false;

  /// Sec-hardening: zero native key material before freeing.
  /// Uses SodiumFFI's public memzero which wraps sodium_memzero.
  void _zeroAndFree(Pointer<Uint8> ptr, int length) {
    SodiumFFI().memzero(ptr, length);
    calloc.free(ptr);
  }

  // Cached OQS context handles — allocated once, reused across calls.
  // Thread-safe: Dart is single-threaded per isolate.
  Pointer<Void> _cachedKem = nullptr;
  Pointer<Void> _cachedSig = nullptr;

  Pointer<Void> get _kem {
    if (_cachedKem == nullptr) {
      final name = _kemAlgorithm.toNativeUtf8();
      _cachedKem = _kemNew(name);
      calloc.free(name);
      if (_cachedKem == nullptr) {
        throw StateError('OQS_KEM_new("$_kemAlgorithm") returned null');
      }
    }
    return _cachedKem;
  }

  Pointer<Void> get _sig {
    if (_cachedSig == nullptr) {
      final name = _sigAlgorithm.toNativeUtf8();
      _cachedSig = _sigNew(name);
      calloc.free(name);
      if (_cachedSig == nullptr) {
        throw StateError('OQS_SIG_new("$_sigAlgorithm") returned null');
      }
    }
    return _cachedSig;
  }

  void _bindFunctions() {
    _oqsInit = _lib.lookupFunction<_OqsInitNative, _OqsInitDart>('OQS_init');

    _kemNew = _lib.lookupFunction<_KemNewNative, _KemNewDart>('OQS_KEM_new');
    _kemFree =
        _lib.lookupFunction<_KemFreeNative, _KemFreeDart>('OQS_KEM_free');
    _kemKeypair = _lib
        .lookupFunction<_KemKeypairNative, _KemKeypairDart>('OQS_KEM_keypair');
    _kemEncaps = _lib
        .lookupFunction<_KemEncapsNative, _KemEncapsDart>('OQS_KEM_encaps');
    _kemDecaps = _lib
        .lookupFunction<_KemDecapsNative, _KemDecapsDart>('OQS_KEM_decaps');

    _sigNew = _lib.lookupFunction<_SigNewNative, _SigNewDart>('OQS_SIG_new');
    _sigFree =
        _lib.lookupFunction<_SigFreeNative, _SigFreeDart>('OQS_SIG_free');
    _sigKeypair = _lib
        .lookupFunction<_SigKeypairNative, _SigKeypairDart>('OQS_SIG_keypair');
    _sigSign =
        _lib.lookupFunction<_SigSignNative, _SigSignDart>('OQS_SIG_sign');
    _sigVerify = _lib
        .lookupFunction<_SigVerifyNative, _SigVerifyDart>('OQS_SIG_verify');
    _randCustom = _lib.lookupFunction<_RandCustomNative, _RandCustomDart>(
        'OQS_randombytes_custom_algorithm');
    _randSwitch = _lib.lookupFunction<_RandSwitchNative, _RandSwitchDart>(
        'OQS_randombytes_switch_algorithm');
  }

  // --------------------------------------------------------------------------
  // Initialization
  // --------------------------------------------------------------------------

  /// Initialize liboqs. Must be called before any other method.
  void init() {
    if (_initialized) return;
    _oqsInit();
    _initialized = true;
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('OqsFFI.init() must be called before using crypto ops');
    }
  }

  /// Release cached OQS context handles. Safe to call multiple times;
  /// subsequent crypto calls lazily re-allocate the contexts.
  void dispose() {
    if (_cachedKem != nullptr) {
      _kemFree(_cachedKem);
      _cachedKem = nullptr;
    }
    if (_cachedSig != nullptr) {
      _sigFree(_cachedSig);
      _cachedSig = nullptr;
    }
  }

  // --------------------------------------------------------------------------
  // ML-KEM-768  (Key Encapsulation Mechanism)
  // --------------------------------------------------------------------------

  /// Generate an ML-KEM-768 keypair.
  ///
  /// Returns a record of (publicKey, secretKey) as [Uint8List].
  ({Uint8List publicKey, Uint8List secretKey}) mlKemKeypair() {
    _ensureInitialized();

    final pk = calloc<Uint8>(mlKemPublicKeyLength);
    final sk = calloc<Uint8>(mlKemSecretKeyLength);

    try {
      final status = _kemKeypair(_kem, pk, sk);
      if (status != OqsStatus.success) {
        throw StateError('OQS_KEM_keypair failed with status $status');
      }

      return (
        publicKey: _copyToUint8List(pk, mlKemPublicKeyLength),
        secretKey: _copyToUint8List(sk, mlKemSecretKeyLength),
      );
    } finally {
      // Sec-hardening: zero secret key before freeing native memory.
      _zeroAndFree(sk, mlKemSecretKeyLength);
      calloc.free(pk);
    }
  }

  /// Generate a deterministic ML-KEM-768 keypair from a 64-byte seed.
  ///
  /// Same DRBG-injection technique as mlDsaKeypairDerand: replaces liboqs's
  /// randomness source with a SHA-256 counter-mode PRNG seeded from the
  /// provided seed, then restores the system DRBG after keygen.
  ({Uint8List publicKey, Uint8List secretKey}) mlKemKeypairDerand(
      Uint8List seed) {
    _ensureInitialized();
    if (seed.length != 64) {
      throw ArgumentError('seed must be 64 bytes, got ${seed.length}');
    }

    _derandSeed = Uint8List.fromList(seed);
    _derandOffset = 0;
    _derandCallable ??= NativeCallable<Void Function(Pointer<Uint8>, Size)>
        .isolateLocal(_derandCallback);
    _randCustom(_derandCallable!.nativeFunction);

    final pk = calloc<Uint8>(mlKemPublicKeyLength);
    final sk = calloc<Uint8>(mlKemSecretKeyLength);

    try {
      final status = _kemKeypair(_kem, pk, sk);
      if (status != OqsStatus.success) {
        throw StateError('OQS_KEM_keypair (derand) failed with status $status');
      }
      return (
        publicKey: _copyToUint8List(pk, mlKemPublicKeyLength),
        secretKey: _copyToUint8List(sk, mlKemSecretKeyLength),
      );
    } finally {
      // Sec-hardening: zero secret key before freeing native memory.
      _zeroAndFree(sk, mlKemSecretKeyLength);
      calloc.free(pk);
      _restoreSystemDrbg();
    }
  }

  /// Encapsulate against an ML-KEM-768 public key.
  ///
  /// Returns a record of (ciphertext, sharedSecret).
  ({Uint8List ciphertext, Uint8List sharedSecret}) mlKemEncapsulate(
    Uint8List publicKey,
  ) {
    _ensureInitialized();

    if (publicKey.length != mlKemPublicKeyLength) {
      throw ArgumentError(
        'publicKey must be $mlKemPublicKeyLength bytes, '
        'got ${publicKey.length}',
      );
    }

    final ct = calloc<Uint8>(mlKemCiphertextLength);
    final ss = calloc<Uint8>(mlKemSharedSecretLength);
    final pkNative = _allocFromUint8List(publicKey);

    try {
      final status = _kemEncaps(_kem, ct, ss, pkNative);
      if (status != OqsStatus.success) {
        throw StateError('OQS_KEM_encaps failed with status $status');
      }

      return (
        ciphertext: _copyToUint8List(ct, mlKemCiphertextLength),
        sharedSecret: _copyToUint8List(ss, mlKemSharedSecretLength),
      );
    } finally {
      // Sec-hardening: zero shared secret before freeing native memory.
      _zeroAndFree(ss, mlKemSharedSecretLength);
      calloc.free(ct);
      calloc.free(pkNative);
    }
  }

  /// Decapsulate an ML-KEM-768 ciphertext with the secret key.
  ///
  /// Returns the shared secret as [Uint8List].
  Uint8List mlKemDecapsulate(Uint8List ciphertext, Uint8List secretKey) {
    _ensureInitialized();

    if (ciphertext.length != mlKemCiphertextLength) {
      throw ArgumentError(
        'ciphertext must be $mlKemCiphertextLength bytes, '
        'got ${ciphertext.length}',
      );
    }
    if (secretKey.length != mlKemSecretKeyLength) {
      throw ArgumentError(
        'secretKey must be $mlKemSecretKeyLength bytes, '
        'got ${secretKey.length}',
      );
    }

    final ss = calloc<Uint8>(mlKemSharedSecretLength);
    final ctNative = _allocFromUint8List(ciphertext);
    final skNative = _allocFromUint8List(secretKey);

    try {
      final status = _kemDecaps(_kem, ss, ctNative, skNative);
      if (status != OqsStatus.success) {
        throw StateError('OQS_KEM_decaps failed with status $status');
      }

      return _copyToUint8List(ss, mlKemSharedSecretLength);
    } finally {
      // Sec-hardening: zero shared secret and secret key copy before freeing.
      _zeroAndFree(ss, mlKemSharedSecretLength);
      _zeroAndFree(skNative, secretKey.length);
      calloc.free(ctNative);
    }
  }

  // --------------------------------------------------------------------------
  // ML-DSA-65  (Digital Signature Algorithm)
  // --------------------------------------------------------------------------

  /// Generate an ML-DSA-65 keypair.
  ///
  /// Returns a record of (publicKey, secretKey) as [Uint8List].
  ({Uint8List publicKey, Uint8List secretKey}) mlDsaKeypair() {
    _ensureInitialized();

    final pk = calloc<Uint8>(mlDsaPublicKeyLength);
    final sk = calloc<Uint8>(mlDsaSecretKeyLength);

    try {
      final status = _sigKeypair(_sig, pk, sk);
      if (status != OqsStatus.success) {
        throw StateError('OQS_SIG_keypair failed with status $status');
      }

      return (
        publicKey: _copyToUint8List(pk, mlDsaPublicKeyLength),
        secretKey: _copyToUint8List(sk, mlDsaSecretKeyLength),
      );
    } finally {
      // Sec-hardening: zero secret key before freeing native memory.
      _zeroAndFree(sk, mlDsaSecretKeyLength);
      calloc.free(pk);
    }
  }

  // --------------------------------------------------------------------------
  // Deterministic ML-DSA-65 keygen (§7.1 Linked-Device delegation)
  // --------------------------------------------------------------------------

  // Seed buffer for the custom DRBG callback. Only valid during
  // mlDsaKeypairDerand — set before keygen, cleared after.
  static Uint8List _derandSeed = Uint8List(0);
  static int _derandOffset = 0;

  /// NativeCallable-compatible DRBG: expand _derandSeed via SHA-256
  /// counter-mode into the requested buffer. Thread-safety: Dart is
  /// single-threaded per isolate, and OQS keygen is synchronous.
  static void _derandCallback(Pointer<Uint8> buf, int len) {
    final sodium = SodiumFFI();
    var produced = 0;
    while (produced < len) {
      final counterBytes = Uint8List(4)
        ..buffer.asByteData().setUint32(0, _derandOffset, Endian.big);
      final block = Uint8List(_derandSeed.length + 4)
        ..setAll(0, _derandSeed)
        ..setAll(_derandSeed.length, counterBytes);
      final hash = sodium.sha256(block);
      final take = (len - produced) < 32 ? (len - produced) : 32;
      for (var i = 0; i < take; i++) {
        buf[produced + i] = hash[i];
      }
      produced += take;
      _derandOffset++;
    }
  }

  static NativeCallable<Void Function(Pointer<Uint8>, Size)>? _derandCallable;

  /// Generate a deterministic ML-DSA-65 keypair from a 64-byte seed.
  ///
  /// Uses OQS_randombytes_custom_algorithm to inject a seeded PRNG,
  /// then restores the system DRBG. The seed MUST be derived via HKDF
  /// and unique per device — reuse across devices breaks key separation.
  ({Uint8List publicKey, Uint8List secretKey}) mlDsaKeypairDerand(
      Uint8List seed) {
    _ensureInitialized();
    if (seed.length != 64) {
      throw ArgumentError('seed must be 64 bytes, got ${seed.length}');
    }

    // Set up the seeded PRNG
    _derandSeed = Uint8List.fromList(seed);
    _derandOffset = 0;
    _derandCallable ??= NativeCallable<Void Function(Pointer<Uint8>, Size)>
        .isolateLocal(_derandCallback);
    _randCustom(_derandCallable!.nativeFunction);

    final pk = calloc<Uint8>(mlDsaPublicKeyLength);
    final sk = calloc<Uint8>(mlDsaSecretKeyLength);

    try {
      final status = _sigKeypair(_sig, pk, sk);
      if (status != OqsStatus.success) {
        throw StateError('OQS_SIG_keypair (derand) failed with status $status');
      }
      return (
        publicKey: _copyToUint8List(pk, mlDsaPublicKeyLength),
        secretKey: _copyToUint8List(sk, mlDsaSecretKeyLength),
      );
    } finally {
      // Sec-hardening: zero secret key before freeing native memory.
      _zeroAndFree(sk, mlDsaSecretKeyLength);
      calloc.free(pk);
      _restoreSystemDrbg();
    }
  }

  void _restoreSystemDrbg() {
    final sysAlg = 'system'.toNativeUtf8();
    _randSwitch(sysAlg);
    calloc.free(sysAlg);
    // Sec-hardening: zero the seed buffer before replacing it.
    for (var i = 0; i < _derandSeed.length; i++) {
      _derandSeed[i] = 0;
    }
    _derandSeed = Uint8List(0);
    _derandOffset = 0;
  }

  /// Sign a message with an ML-DSA-65 secret key.
  ///
  /// Returns the signature as [Uint8List].
  Uint8List mlDsaSign(Uint8List message, Uint8List secretKey) {
    _ensureInitialized();

    if (secretKey.length != mlDsaSecretKeyLength) {
      throw ArgumentError(
        'secretKey must be $mlDsaSecretKeyLength bytes, '
        'got ${secretKey.length}',
      );
    }

    final sigBuf = calloc<Uint8>(mlDsaSignatureLength);
    final sigLen = calloc<Size>(1);
    final msgNative = _allocFromUint8List(message);
    final skNative = _allocFromUint8List(secretKey);

    try {
      final status = _sigSign(
        _sig,
        sigBuf,
        sigLen,
        msgNative,
        message.length,
        skNative,
      );
      if (status != OqsStatus.success) {
        throw StateError('OQS_SIG_sign failed with status $status');
      }

      final actualLen = sigLen.value;
      return _copyToUint8List(sigBuf, actualLen);
    } finally {
      // Sec-hardening: zero secret key copy before freeing native memory.
      _zeroAndFree(skNative, secretKey.length);
      calloc.free(sigBuf);
      calloc.free(sigLen);
      calloc.free(msgNative);
    }
  }

  /// Verify a signature against a message and ML-DSA-65 public key.
  ///
  /// Returns `true` if the signature is valid, `false` otherwise.
  bool mlDsaVerify(
    Uint8List message,
    Uint8List signature,
    Uint8List publicKey,
  ) {
    _ensureInitialized();

    if (publicKey.length != mlDsaPublicKeyLength) {
      throw ArgumentError(
        'publicKey must be $mlDsaPublicKeyLength bytes, '
        'got ${publicKey.length}',
      );
    }
    if (signature.length > mlDsaSignatureLength) {
      throw ArgumentError(
        'signature must be at most $mlDsaSignatureLength bytes, '
        'got ${signature.length}',
      );
    }

    final msgNative = _allocFromUint8List(message);
    final sigNative = _allocFromUint8List(signature);
    final pkNative = _allocFromUint8List(publicKey);

    try {
      final status = _sigVerify(
        _sig,
        msgNative,
        message.length,
        sigNative,
        signature.length,
        pkNative,
      );
      return status == OqsStatus.success;
    } finally {
      calloc.free(msgNative);
      calloc.free(sigNative);
      calloc.free(pkNative);
    }
  }

  // --------------------------------------------------------------------------
  // Memory helpers
  // --------------------------------------------------------------------------

  /// Copy native memory to a Dart [Uint8List].
  Uint8List _copyToUint8List(Pointer<Uint8> ptr, int length) {
    final list = Uint8List(length);
    for (var i = 0; i < length; i++) {
      list[i] = ptr[i];
    }
    return list;
  }

  /// Allocate native memory and copy a Dart [Uint8List] into it.
  Pointer<Uint8> _allocFromUint8List(Uint8List data) {
    final ptr = calloc<Uint8>(data.length);
    for (var i = 0; i < data.length; i++) {
      ptr[i] = data[i];
    }
    return ptr;
  }
}
