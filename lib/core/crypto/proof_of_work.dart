import 'dart:isolate';
import 'dart:typed_data';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:fixnum/fixnum.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Proof of Work: SHA-256 hashcash-style with leading zero bits.
///
/// compute() finds a nonce such that SHA-256(data || nonce_8LE) has at least
/// [difficulty] leading zero bits. Difficulty 20 ≈ 1M hashes ≈ 50-100ms.
class ProofOfWork {
  static const int defaultDifficulty = 20;

  /// Minimum difficulty accepted during verification (transition period).
  static const int minAcceptedDifficulty = 16;

  /// Compute PoW for [data]. Returns proto with nonce, difficulty, hash.
  static proto.ProofOfWork compute(Uint8List data, {int difficulty = defaultDifficulty}) {
    final sodium = SodiumFFI();
    final buffer = Uint8List(data.length + 8);
    buffer.setRange(0, data.length, data);
    final nonceView = ByteData.sublistView(buffer, data.length);

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
  static bool verify(Uint8List data, proto.ProofOfWork pow) {
    if (pow.difficulty < minAcceptedDifficulty) return false;
    final sodium = SodiumFFI();
    final buffer = Uint8List(data.length + 8);
    buffer.setRange(0, data.length, data);
    ByteData.sublistView(buffer, data.length)
        .setUint64(0, pow.nonce.toInt(), Endian.little);
    final hash = sodium.sha256(buffer);
    if (!_hasLeadingZeroBits(hash, pow.difficulty)) return false;
    // Verify stored hash matches
    if (hash.length != pow.hash.length) return false;
    for (int i = 0; i < hash.length; i++) {
      if (hash[i] != pow.hash[i]) return false;
    }
    return true;
  }

  /// Check if [hash] has at least [bits] leading zero bits.
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
