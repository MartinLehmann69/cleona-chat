import 'dart:typed_data';

/// XOR of two byte sequences of equal length: `dst ^= src`.
///
/// ── WHY THIS IS A FILE OF ITS OWN ──────────────────────────────────
///
/// This is the **only** hot loop of the codec. Everything else —
/// degree drawing, neighbourhood, bookkeeping — runs once per block;
/// this loop runs `degree x 1024` times per block.
///
/// Recomputed on the measured case (200 MiB, k = 204 800, mean
/// degree 19.9): 276 496 generated blocks times 19.9 neighbours times
/// 1024 B = **5.6 x 10^9 bytes** that wander through memory just for
/// encoding, and once more the same order of magnitude for decoding.
///
/// Measured on this machine: the word path manages **1.60 GB/s**.
/// The pure XOR work of a 200 MB object thus lies at about 3.5 s per
/// direction — the entire measured encoding run takes 7.3 s. The loop
/// is thus not a part of the costs, it is about half of them.
///
/// [kFountainBlockPayloadBytes] is therefore evenly divisible by 8
/// (1024 = 128 x 8) and every block payload begins at an 8-byte multiple
/// of its buffer — both prerequisites for the word path, both justified
/// in `fountain_block.dart`.
class BlockXor {
  BlockXor._();

  /// Is the 64-bit path usable on this backend?
  ///
  /// On native Dart always. On a version compiled to JavaScript
  /// (browser assembler, §26.6.5) `Uint64List` does not exist — the
  /// access throws. The probe runs once, the result is kept; the byte
  /// path stays as a fallback and is checked with the same result
  /// (`smoke_fountain.dart`).
  static final bool wordPathAvailable = _probe();

  static bool _probe() {
    try {
      final t = Uint64List(1);
      t[0] = 1;
      return t[0] == 1;
    } catch (_) {
      return false;
    }
  }

  /// `dst ^= src`. Both must be the same length.
  static void xorInto(Uint8List dst, Uint8List src) {
    final n = dst.length;
    if (src.length != n) {
      throw ArgumentError('Lengths differ: $n versus ${src.length}');
    }
    if (wordPathAvailable &&
        (n & 7) == 0 &&
        (dst.offsetInBytes & 7) == 0 &&
        (src.offsetInBytes & 7) == 0) {
      final d = dst.buffer.asUint64List(dst.offsetInBytes, n >> 3);
      final s = src.buffer.asUint64List(src.offsetInBytes, n >> 3);
      for (var i = 0; i < d.length; i++) {
        d[i] ^= s[i];
      }
      return;
    }
    xorIntoBytewise(dst, src);
  }

  /// The fallback path, callable on its own, so that a test can pit both
  /// paths against each other instead of only the one this machine
  /// happens to choose.
  static void xorIntoBytewise(Uint8List dst, Uint8List src) {
    for (var i = 0; i < dst.length; i++) {
      dst[i] ^= src[i];
    }
  }
}
