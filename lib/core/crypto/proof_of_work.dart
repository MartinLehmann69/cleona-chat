import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/platform/app_paths.dart';
import 'package:fixnum/fixnum.dart';
import 'package:cleona/generated/proto/transport_v3.pb.dart' as proto;

// ---------------------------------------------------------------------------
// Native PoW FFI (libcleona_pow) — optional, graceful fallback to Dart loop
// ---------------------------------------------------------------------------

typedef _PowFindNonceNative = ffi.Uint64 Function(
  ffi.Pointer<ffi.Uint8> digest,
  ffi.Int32 difficulty,
  ffi.Pointer<ffi.Uint8> resultHash,
);
typedef _PowFindNonceDart = int Function(
  ffi.Pointer<ffi.Uint8> digest,
  int difficulty,
  ffi.Pointer<ffi.Uint8> resultHash,
);

_PowFindNonceDart? _nativePowFindNonce;
bool _nativePowTried = false;

_PowFindNonceDart? _loadNativePow() {
  if (_nativePowTried) return _nativePowFindNonce;
  _nativePowTried = true;

  // `AppPaths.bundleDir` instead of `File(exe).parent.path` (S367) — the
  // daemon lies in `<bundleDir>/bin/`, its own directory is no longer
  // the bundle root. For the GUI both are the same.
  final candidates = <String>[];
  if (Platform.isLinux) {
    candidates.add('libcleona_pow.so');
    try {
      candidates.add('${AppPaths.bundleDir}/lib/libcleona_pow.so');
    } catch (_) {}
    final home = Platform.environment['HOME'] ?? '';
    if (home.isNotEmpty) {
      candidates.add('$home/cleona-app/lib/libcleona_pow.so');
    }
    candidates.add('${Directory.current.path}/native/cleona_pow/build/libcleona_pow.so');
  } else if (Platform.isWindows) {
    candidates.add('cleona_pow.dll');
    try {
      candidates.add('${AppPaths.bundleDir}\\cleona_pow.dll');
    } catch (_) {}
  } else if (Platform.isMacOS) {
    candidates.add('libcleona_pow.dylib');
    try {
      candidates.add('${AppPaths.macFrameworksDir}/libcleona_pow.dylib');
    } catch (_) {}
    candidates.add('@executable_path/../Frameworks/libcleona_pow.dylib');
  } else if (Platform.isIOS) {
    try {
      final lib = ffi.DynamicLibrary.process();
      _nativePowFindNonce = lib.lookupFunction<_PowFindNonceNative,
          _PowFindNonceDart>('cleona_pow_find_nonce');
      return _nativePowFindNonce;
    } catch (_) {}
    return null;
  } else if (Platform.isAndroid) {
    try {
      final lib = ffi.DynamicLibrary.open('libcleona_pow.so');
      _nativePowFindNonce = lib.lookupFunction<_PowFindNonceNative,
          _PowFindNonceDart>('cleona_pow_find_nonce');
      return _nativePowFindNonce;
    } catch (_) {}
    return null;
  }

  for (final c in candidates) {
    try {
      final lib = ffi.DynamicLibrary.open(c);
      _nativePowFindNonce = lib.lookupFunction<_PowFindNonceNative,
          _PowFindNonceDart>('cleona_pow_find_nonce');
      return _nativePowFindNonce;
    } catch (_) {}
  }
  return null;
}

// ---------------------------------------------------------------------------
// ProofOfWork
// ---------------------------------------------------------------------------

/// Proof of Work: SHA-256 hashcash-style with leading zero bits.
///
/// compute() finds a nonce such that SHA-256(digest || nonce_8LE) has at least
/// [difficulty] leading zero bits, where digest = SHA-256(data). Pre-hashing
/// makes iteration time O(1) in payload size — critical for large payloads
/// (131KB image: 66s full-data vs <0.1s pre-hashed on ARM64).
class ProofOfWork {
  static const int defaultDifficulty = 20;

  /// True when the native `cleona_pow_find_nonce` loop is available on this
  /// platform. Exposed so startup can log which path is active: the Dart
  /// fallback is ~2-4 s per message on mobile versus <10 ms native, and a
  /// missing library is otherwise silent (V3.1.156 shipped the Android APK
  /// without `libcleona_pow.so` and nothing surfaced it).
  static bool get nativeLoopAvailable => _loadNativePow() != null;

  /// Minimum difficulty accepted during verification (transition period).
  static const int minAcceptedDifficulty = 16;

  /// Compute PoW for [data]. Returns proto with nonce, difficulty, hash.
  /// Uses native C loop (libcleona_pow) when available, otherwise falls back
  /// to Dart loop with per-iteration SHA-256 FFI calls.
  static proto.ProofOfWork compute(Uint8List data, {int difficulty = defaultDifficulty}) {
    final sodium = SodiumFFI();
    final dataDigest = sodium.sha256(data);

    final native = _loadNativePow();
    if (native != null) {
      return _computeNative(native, dataDigest, difficulty);
    }
    return _computeDart(sodium, dataDigest, difficulty);
  }

  static proto.ProofOfWork _computeNative(
    _PowFindNonceDart native,
    Uint8List dataDigest,
    int difficulty,
  ) {
    final digestPtr = calloc<ffi.Uint8>(32);
    final hashPtr = calloc<ffi.Uint8>(32);
    try {
      for (int i = 0; i < 32; i++) {
        digestPtr[i] = dataDigest[i];
      }
      final nonce = native(digestPtr, difficulty, hashPtr);
      final hash = Uint8List(32);
      for (int i = 0; i < 32; i++) {
        hash[i] = hashPtr[i];
      }
      return proto.ProofOfWork()
        ..nonce = Int64(nonce)
        ..difficulty = difficulty
        ..hash = hash;
    } finally {
      calloc.free(digestPtr);
      calloc.free(hashPtr);
    }
  }

  static proto.ProofOfWork _computeDart(
    SodiumFFI sodium,
    Uint8List dataDigest,
    int difficulty,
  ) {
    final buffer = Uint8List(32 + 8);
    buffer.setRange(0, 32, dataDigest);
    final nonceView = ByteData.sublistView(buffer, 32);

    for (int nonce = 0; ; nonce++) {
      nonceView.setUint64(0, nonce, Endian.little);
      final hash = sodium.sha256(buffer);
      if (_hasLeadingZeroBits(hash, difficulty)) {
        return proto.ProofOfWork()
          ..nonce = Int64(nonce)
          ..difficulty = difficulty
          ..hash = hash;
      }
    }
  }

  /// Compute PoW in a separate isolate to avoid blocking the UI.
  /// Falls back to synchronous computation if isolate fails (e.g. FFI loading on Android).
  static Future<proto.ProofOfWork> computeAsync(Uint8List data, {int difficulty = defaultDifficulty}) async {
    try {
      final result = await Isolate.run(() {
        SodiumFFI(); // Init FFI in isolate
        final pow = ProofOfWork.compute(data, difficulty: difficulty);
        return (pow.nonce.toInt(), pow.difficulty, Uint8List.fromList(pow.hash));
      });
      return proto.ProofOfWork()
        ..nonce = Int64(result.$1)
        ..difficulty = result.$2
        ..hash = result.$3;
    } catch (_) {
      return compute(data, difficulty: difficulty);
    }
  }

  /// Verify PoW: recompute hash and check leading zero bits.
  ///
  /// **ONLY THE PRE-HASHED FORMAT ANY MORE** — `SHA-256(SHA-256(data) ‖ nonce)`.
  ///
  /// ── THE SECOND BRANCH IS GONE (S368) ─────────────────────────────────
  ///
  /// Below it stood a fallback to `SHA-256(data ‖ nonce)`, with the
  /// reasoning "backward compatibility with cached S&F messages".
  /// Store-and-forward is the V3 layer; on the V4.1 line it does not
  /// exist — `storeAndForward` has zero occurrences there. So there is
  /// also no cached message in the old format that the branch could
  /// still hit. Under the owner invariant ("V4.1 is not backward
  /// compatible") it is dead.
  ///
  /// It was moreover MORE EXPENSIVE than the living branch and was run on
  /// EVERY failed forward attempt: it hashes the COMPLETE payload, whereas
  /// the reason for pre-hashing was precisely to no longer do that
  /// (section 6 of `test/smoke/smoke_pow_prehash.dart` measures exactly
  /// this difference, 1 KB versus 131 KB). A sender who sent 131 KB with
  /// an arbitrary wrong proof thereby bought a second, full hashing round
  /// on the receiving side — a fallback that only made work.
  ///
  /// **Measured what hangs on it:** `ProofOfWork.verify` has ZERO callers
  /// in `lib/` and `bin/` (05.09.2026); the only user is
  /// `smoke_pow_prehash.dart`. That is explicitly named here and not
  /// silently taken along: the function stays, because a missing proof
  /// checker would be a different decision than a removed legacy-format
  /// branch.
  static bool verify(Uint8List data, proto.ProofOfWork pow) {
    if (pow.difficulty < minAcceptedDifficulty) return false;
    final sodium = SodiumFFI();
    final nonce = pow.nonce.toInt();

    final dataDigest = sodium.sha256(data);
    final preHashBuf = Uint8List(32 + 8);
    preHashBuf.setRange(0, 32, dataDigest);
    ByteData.sublistView(preHashBuf, 32).setUint64(0, nonce, Endian.little);
    final preHashResult = sodium.sha256(preHashBuf);
    return _hasLeadingZeroBits(preHashResult, pow.difficulty) &&
        _bytesEqual(preHashResult, pow.hash);
  }

  static bool _bytesEqual(Uint8List a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Check if [hash] has at least [bits] leading zero bits.
  /// Public: shared with AdmissionPow (D3, §13.1.2).
  static bool hasLeadingZeroBits(Uint8List hash, int bits) =>
      _hasLeadingZeroBits(hash, bits);

  static bool _hasLeadingZeroBits(Uint8List hash, int bits) {
    int remaining = bits;
    for (final byte in hash) {
      if (remaining <= 0) return true;
      if (remaining >= 8) {
        if (byte != 0) return false;
        remaining -= 8;
      } else {
        // Check top [remaining] bits of this byte
        final mask = 0xFF << (8 - remaining);
        if (byte & mask != 0) return false;
        return true;
      }
    }
    return remaining <= 0;
  }
}
