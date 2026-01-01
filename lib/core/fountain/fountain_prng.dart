import 'dart:typed_data';

/// Deterministic random generator of the fountain codec.
///
/// ── WHY NOT `dart:math`'s `Random(seed)` ──────────────────────────
///
/// The neighbourhood of an encoded block is **wire format**: the recipient
/// reconstructs it solely from `k` and the block seed in the header
/// (`fountain_block.dart`). If he computed it differently from the
/// sender, the block would be silently wrong — decoding would run
/// through and yield garbage. The generator is thus a format component
/// and must be **specified**, not merely "somehow random".
///
/// `dart:math`'s `Random(seed)` promises exactly that not: the sequence is
/// a property of the respective VM implementation, not of the language. A
/// change of the SDK version or a change of backend (AOT versus dart2js
/// for the browser assembler, §26.6.5) could change the sequence without
/// any test in this tree noticing — both sides of a test run on the same
/// VM, after all. Hence a generator of our own, written out here.
///
/// ── WHICH ONE ──────────────────────────────────────────────────────────
///
/// **xoshiro128\*\*** (Blackman/Vigna, 2018) — four 32-bit words of
/// state, period 2^128-1, exclusively 32-bit operations. The restriction
/// to 32 bits is intentional: it fixes the sequence at a width that no
/// backend has to interpret, and thus turns the neighbourhood into a
/// recomputable quantity instead of a VM property. Multiplications run
/// via [_mul32] following the `Math.imul` pattern (two 16-bit halves), so
/// that no intermediate value exceeds 2^48.
///
/// **Not measured:** whether a dart2js compilation (browser assembler,
/// §26.6.5) runs bit-identically. There `int` is a floating-point number,
/// and `&` on values above 2^32 is not the same as on native 64-bit
/// `int`. Splitting into 16-bit halves is half the battle, the
/// confirmation is outstanding — a finding, not a promise.
///
/// The generator is **not** cryptographic and need not be: it chooses
/// neighbourhoods, not keys. The confidentiality of the blocks lies in
/// the AEAD cell (§5.2), their integrity in the content hash that the
/// caller checks after reconstruction (§26.6.1 step 5).
class FountainPrng {
  static const int _mask = 0xFFFFFFFF;

  int _s0;
  int _s1;
  int _s2;
  int _s3;

  FountainPrng._(this._s0, this._s1, this._s2, this._s3);

  /// Generator for the block with the seed [blockSeed] of an object of
  /// [sourceBlocks] source blocks.
  ///
  /// The neighbourhood deliberately depends **only** on these two numbers
  /// and not on the object identifier. Consequence: two nodes that encode
  /// the same binary with the same seed produce **the same** block. For
  /// in-network distribution (§26.6.1) that is desired — the cache is
  /// content-addressed, and identical blocks coincide there instead of
  /// multiplying.
  ///
  /// ── THE TRAP IN THIS FUNCTION (measured, not suspected) ────────
  ///
  /// The first version built set
  ///
  /// ```
  /// h1 = _fmix32(sourceBlocks ^ 0x85EBCA77)   // depends ONLY on k
  /// ```
  ///
  /// and was thereby silently broken. The first output of xoshiro128\*\*
  /// is `rotl(s1 * 5, 7) * 9` — it depends **on s1 alone**. If a value
  /// that derives only from `k` stands there, the generator delivers the
  /// same first value for **every** block seed of the same object. Exactly
  /// this first value draws the degree. Result: every encoded block had
  /// degree 2, measured over 5000 seeds at k = 5 and k = 98
  /// (`Gradhistogramm: 2:5000`). The neighbours meanwhile looked
  /// impeccably scattered — the malfunction was visible only in the
  /// degree drawing, and only because peeling choked on it (k = 5 did not
  /// reconstruct from 150 blocks).
  ///
  /// Therefore: **each** of the four state words depends on both inputs,
  /// and afterwards four discard steps run, so that the first delivered
  /// number also comes from a mixed state. The effort is four rounds per
  /// block — not measurable against the mean degree of about a dozen XOR
  /// passes over 1024 B.
  factory FountainPrng.forBlock(int sourceBlocks, int blockSeed) {
    final h0 = _fmix32((blockSeed ^ 0x9E3779B9) & _mask);
    final h1 = _fmix32((h0 ^ sourceBlocks ^ 0x85EBCA77) & _mask);
    final h2 = _fmix32((h1 ^ blockSeed ^ 0xC2B2AE3D) & _mask);
    final h3 = _fmix32((h2 ^ sourceBlocks ^ 0x27D4EB2F) & _mask);
    // xoshiro must not start in the all-zero state.
    final g = FountainPrng._((h0 | h1 | h2 | h3) == 0 ? 1 : h0, h1, h2, h3);
    for (var i = 0; i < 4; i++) {
      g.next();
    }
    return g;
  }

  /// Generator from four freely chosen words — only for tests and
  /// measurement runs, not on the wire path.
  factory FountainPrng.fromWords(int a, int b, int c, int d) {
    final w = [a & _mask, b & _mask, c & _mask, d & _mask];
    if (w.every((x) => x == 0)) w[0] = 1;
    return FountainPrng._(w[0], w[1], w[2], w[3]);
  }

  /// 32-bit multiplication following the `Math.imul` pattern.
  ///
  /// `aLo * b` stays below 2^48, `aHi * b` as well. A direct `a * b` would
  /// run up to 2^64 and would thus depend on the int width of the backend;
  /// the split removes this dependency.
  static int _mul32(int a, int b) {
    final aLo = a & 0xFFFF;
    final aHi = (a >> 16) & 0xFFFF;
    return (((aHi * b) & 0xFFFF) * 0x10000 + aLo * b) & _mask;
  }

  static int _rotl(int x, int n) => ((x * _pow2[n]) & _mask) | (x >> (32 - n));

  static final List<int> _pow2 = List<int>.generate(
    32,
    (i) => 1 << i,
    growable: false,
  );

  /// MurmurHash3 finalizer — scatters a counter over all 32 bits.
  static int _fmix32(int h) {
    var x = h & _mask;
    x ^= x >> 16;
    x = _mul32(x, 0x85EBCA6B);
    x ^= x >> 13;
    x = _mul32(x, 0xC2B2AE35);
    x ^= x >> 16;
    return x & _mask;
  }

  /// Next 32-bit word.
  int next() {
    final result = (_mul32(_rotl(_mul32(_s1, 5), 7), 9)) & _mask;
    final t = (_s1 * 512) & _mask; // s1 << 9
    _s2 ^= _s0;
    _s3 ^= _s1;
    _s1 ^= _s2;
    _s0 ^= _s3;
    _s2 ^= t;
    _s3 = _rotl(_s3, 11);
    return result;
  }

  /// Uniformly distributed number from `[0, bound)`, [bound] > 0.
  ///
  /// Discards the upper, incomplete remainder values instead of taking
  /// the modulus. A mere `next() % bound` would be measurably skewed for
  /// the degrees near `k`, and the degree distribution is exactly the
  /// quantity on which the overhead figure hangs.
  int nextInt(int bound) {
    if (bound <= 0) throw ArgumentError.value(bound, 'bound', 'must be > 0');
    if (bound == 1) return 0;
    final limit = _mask - (0x100000000 % bound);
    while (true) {
      final v = next();
      if (v <= limit) return v % bound;
    }
  }

  /// Uniformly distributed from `[0, 1)`.
  double nextDouble() => next() / 4294967296.0;

  /// [count] **distinct** indices from `[0, universe)`, ascending.
  ///
  /// Partial Fisher-Yates with a sparse swap table: the cost depends on
  /// [count], not on [universe]. At k = 204 800 and a measured mean degree
  /// of 19.9, a full shuffle of the universe per block would be ten
  /// thousand times the necessary work.
  Uint32List distinctIndices(int universe, int count) {
    if (count < 0 || count > universe) {
      throw ArgumentError('count=$count outside of [0,$universe]');
    }
    final swaps = <int, int>{};
    final out = Uint32List(count);
    for (var i = 0; i < count; i++) {
      final j = i + nextInt(universe - i);
      out[i] = swaps[j] ?? j;
      swaps[j] = swaps[i] ?? i;
    }
    out.sort();
    return out;
  }
}
