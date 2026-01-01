import 'dart:isolate';
import 'dart:typed_data';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:fixnum/fixnum.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Proof of Work: SHA-256 hashcash-style with leading zero bits.
///
/// compute() finds a nonce such that SHA-256(digest || nonce_8LE) has at least
/// [difficulty] leading zero bits, where digest = SHA-256(data). Pre-hashing
/// makes iteration time O(1) in payload size — critical for large payloads
/// (131KB image: 66s full-data vs <0.1s pre-hashed on ARM64).
class ProofOfWork {
  static const int defaultDifficulty = 20;

  /// Minimum difficulty accepted during verification (transition period).
  static const int minAcceptedDifficulty = 16;

  /// Compute PoW for [data]. Returns proto with nonce, difficulty, hash.
  /// Pre-hashes data to a 32-byte digest before iterating — PoW time is
  /// independent of payload size (~20ms for difficulty 20 regardless of input).
  static proto.ProofOfWork compute(Uint8List data, {int difficulty = defaultDifficulty}) {
    final sodium = SodiumFFI();
    // Pre-hash: reduce arbitrarily-sized payload to fixed 32-byte digest.
    final dataDigest = sodium.sha256(data);
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
        // Return serializable data (proto objects may not cross isolate boundaries)
        return (pow.nonce.toInt(), pow.difficulty, Uint8List.fromList(pow.hash));
      });
      return proto.ProofOfWork()
        ..nonce = Int64(result.$1)
        ..difficulty = result.$2
        ..hash = result.$3;
    } catch (_) {
      // Fallback: compute synchronously (blocks UI but at least works)
      return compute(data, difficulty: difficulty);
    }
  }

  /// Verify PoW: recompute hash and check leading zero bits.
  /// Accepts both pre-hashed format (current) and legacy full-data format
  /// for backward compatibility with cached S&F messages.
  static bool verify(Uint8List data, proto.ProofOfWork pow) {
    if (pow.difficulty < minAcceptedDifficulty) return false;
    final sodium = SodiumFFI();
    final nonce = pow.nonce.toInt();

    // Try pre-hashed format first (current: SHA-256(SHA-256(data) || nonce))
    final dataDigest = sodium.sha256(data);
    final preHashBuf = Uint8List(32 + 8);
    preHashBuf.setRange(0, 32, dataDigest);
    ByteData.sublistView(preHashBuf, 32).setUint64(0, nonce, Endian.little);
    final preHashResult = sodium.sha256(preHashBuf);
    if (_hasLeadingZeroBits(preHashResult, pow.difficulty) &&
        _bytesEqual(preHashResult, pow.hash)) {
      return true;
    }

    // Legacy full-data format: SHA-256(data || nonce)
    final buffer = Uint8List(data.length + 8);
    buffer.setRange(0, data.length, data);
    ByteData.sublistView(buffer, data.length)
        .setUint64(0, nonce, Endian.little);
    final hash = sodium.sha256(buffer);
    if (!_hasLeadingZeroBits(hash, pow.difficulty)) return false;
    if (hash.length != pow.hash.length) return false;
    for (int i = 0; i < hash.length; i++) {
      if (hash[i] != pow.hash[i]) return false;
    }
    return true;
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
