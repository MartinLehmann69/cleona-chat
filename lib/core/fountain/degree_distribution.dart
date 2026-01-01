import 'dart:math' as math;
import 'dart:typed_data';

import 'fountain_prng.dart';

/// Degree distribution of an LT code: **robust soliton distribution**
/// (Luby 2002).
///
/// ── WHAT A "DEGREE" IS ───────────────────────────────────────────────
///
/// An encoded block is the XOR of `d` source blocks; `d` is its degree.
/// The decoder works by **peeling**: it looks for a block of degree 1
/// (which is directly a source block), computes it out of all others,
/// and looks again. The distribution from which `d` is drawn thus alone
/// decides whether and at what cost that succeeds:
///
/// - **too many small degrees** → many blocks cover the same few source
///   blocks over and over, the last ones are never hit;
/// - **too many large degrees** → peeling never gets going, because
///   no block ever drops to degree 1.
///
/// ── THE IDEAL SOLITON DISTRIBUTION AND WHY IT IS NOT ENOUGH ─────────
///
/// ```
/// ideal(1) = 1/k
/// ideal(d) = 1 / (d * (d-1))     for d = 2..k
/// ```
///
/// In expectation, per processed block **exactly one** newly drops to
/// degree 1 here — the peeling wave sustains itself exactly. That is its
/// strength and at the same time its flaw: a wave that runs at strength
/// 1 on average breaks off constantly in practice. The expected value is
/// right, the variance finishes it off.
///
/// ── THE ROBUST VERSION ──────────────────────────────────────────────
///
/// Luby places a second share on top, which keeps the wave at width
/// `R` and sets a **spike** at `d = k/R`. The spike is the part that
/// collects the last source blocks that would otherwise never be hit.
///
/// ```
/// R          = c * ln(k / failureBound) * sqrt(k)
/// extra(d)   = R / (d * k)                  for d = 1 .. floor(k/R)-1
/// extra(k/R) = R * ln(R / failureBound) / k
/// extra(d)   = 0                            for d > floor(k/R)
/// ```
///
/// Normalised over the sum of both shares this yields the distribution
/// from which [sampleDegree] draws.
///
/// ── THE TWO ADJUSTING SCREWS ────────────────────────────────────────
///
/// [c] and [failureBound] are not fixed in the literature; they are the
/// subject of the measurement requirement §27-O-3. The defaults here are
/// **measured, not adopted** — `test/perf/perf_fountain.dart` runs a grid
/// of both values and re-measures the candidates with a high repetition
/// count.
///
/// Both names are deliberately spelled out: [failureBound] is the bound
/// on the probability that peeling stalls despite sufficiently many
/// blocks, [c] a dimensionless scale factor on the wave width.
///
/// ── WHY EXACTLY THESE TWO NUMBERS (measured 2026-08-30) ───────────
///
/// The choice was made by the **upper end**, not by the mean. A promise
/// of the form "this many blocks suffice" is not redeemed by the mean
/// but by the bad case; a recipient whose harvest does not suffice in 1
/// percent of cases sees a hanging download, not a slightly raised
/// average.
///
/// Overhead figure (blocks used divided by k), failureBound 0.5 in each
/// case:
///
/// ```
/// k = 64      (64 KB, 3000 runs)     mean     p95     p99    max    fail
///   c = 0.02                         1.449   2.125   2.703  3.422   11
///   c = 0.03                         1.410   1.953   2.594  3.328    3
///   c = 0.04                         1.396   1.875   2.313  3.359    0
///   c = 0.06                         1.370   1.766   2.078  2.781    0
///
/// k = 5120    (5 MB, 400 runs)
///   c = 0.02                         1.065   1.147   1.207  1.240    0
///   c = 0.03                         1.065   1.119   1.150  1.208    0
///   c = 0.04                         1.068   1.110   1.148  1.166    0
///   c = 0.06                         1.079   1.104   1.114  1.127    0
///
/// k = 204800  (200 MB, 8 runs)
///   c = 0.02                         1.013   1.023   1.023  1.023    0
///   c = 0.06                         1.022   1.023   1.023  1.023    0
/// ```
///
/// The pattern is the same across all three sizes: **a larger [c] buys a
/// tighter upper end and costs a little on the mean.** At 5 MB the step
/// from 0.02 to 0.06 costs 1.3 percentage points on the mean and saves 11
/// on the maximum. At 200 MB the maximum is the same across all
/// candidates (1.023), the mean 0.8 percentage points more expensive —
/// on a 200 MB binary that is 1.6 MB. At 64 KB, with the larger [c], the
/// **total failures** also disappear: at c = 0.02 peeling stalled in 11
/// of 3000 runs even after three times k, at c = 0.06 in none.
///
/// [failureBound] = 0.5 wins on **both** axes at once and is therefore
/// no trade-off: it lowers both the overhead figure and the mean degree
/// (at k = 5120 from 16.2 to 13.5), i.e. also the computing effort.
///
/// **What these numbers are not:** a statement about the weakest target
/// platform. §27-O-3 requires the figure **and** the throughput there;
/// so far only a Linux workstation has been measured. The figure itself
/// is platform-independent (it follows from the graph), the throughput
/// is not.
class DegreeDistribution {
  /// Scale factor on the wave width `R`.
  final double c;

  /// Bound on the failure probability of peeling.
  final double failureBound;

  /// Number of source blocks.
  final int sourceBlocks;

  /// Cumulative distribution, index = degree, length `k+1` (index 0 unused).
  final Float64List _cumulative;

  /// Mean degree — that is at the same time the mean number of XOR steps
  /// per encoded block and thus the throughput driver.
  final double meanDegree;

  DegreeDistribution._(
    this.c,
    this.failureBound,
    this.sourceBlocks,
    this._cumulative,
    this.meanDegree,
  );

  /// Defaults, measured (see class documentation).
  ///
  /// **These two numbers are wire format**, not configuration: the
  /// neighbourhood of every block follows from them. Whoever changes them
  /// makes every block unusable that already lies in the network, and must
  /// increment `kFountainVersion`.
  static const double defaultC = 0.06;
  static const double defaultFailureBound = 0.5;

  factory DegreeDistribution(
    int sourceBlocks, {
    double c = defaultC,
    double failureBound = defaultFailureBound,
  }) {
    if (sourceBlocks < 1) {
      throw ArgumentError.value(sourceBlocks, 'sourceBlocks', 'must be >= 1');
    }
    if (c <= 0) throw ArgumentError.value(c, 'c', 'must be > 0');
    if (failureBound <= 0 || failureBound >= 1) {
      throw ArgumentError.value(
        failureBound,
        'failureBound',
        'must lie in (0,1)',
      );
    }

    final k = sourceBlocks;

    // k == 1: there is exactly one source block, every encoded block has
    // degree 1. The formulas below would yield a division by
    // ln(1) = 0 in the spike and an empty distribution here — the special
    // case is therefore caught before them, not in them.
    if (k == 1) {
      final cum = Float64List(2);
      cum[1] = 1.0;
      return DegreeDistribution._(c, failureBound, 1, cum, 1.0);
    }

    final weights = Float64List(k + 1);

    // Ideal share.
    weights[1] = 1.0 / k;
    for (var d = 2; d <= k; d++) {
      weights[d] = 1.0 / (d * (d - 1));
    }

    // Robust share.
    final r = c * math.log(k / failureBound) * math.sqrt(k);
    var spike = (k / r).floor();
    if (spike < 1) spike = 1;
    if (spike > k) spike = k;
    for (var d = 1; d < spike; d++) {
      weights[d] += r / (d * k);
    }
    // ln(R/failureBound) can become negative if R is very small
    // (small k, large c). A negative weight would no longer be a
    // distribution — then the spike is dropped.
    final spikeWeight = r * math.log(r / failureBound) / k;
    if (spikeWeight > 0) weights[spike] += spikeWeight;

    var sum = 0.0;
    for (var d = 1; d <= k; d++) {
      sum += weights[d];
    }

    final cum = Float64List(k + 1);
    var acc = 0.0;
    var mean = 0.0;
    for (var d = 1; d <= k; d++) {
      final p = weights[d] / sum;
      mean += d * p;
      acc += p;
      cum[d] = acc;
    }
    // Rounding drift: the last entry must be exactly 1, otherwise
    // nextDouble() can run beyond it and the search would come up empty.
    cum[k] = 1.0;

    return DegreeDistribution._(c, failureBound, k, cum, mean);
  }

  /// Draws a degree from `[1, k]`.
  ///
  /// Inverse distribution function via binary search: O(log k) per block.
  int sampleDegree(FountainPrng rng) {
    if (sourceBlocks == 1) return 1;
    final u = rng.nextDouble();
    var lo = 1;
    var hi = sourceBlocks;
    while (lo < hi) {
      final mid = lo + ((hi - lo) >> 1);
      if (_cumulative[mid] > u) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }

  /// Neighbourhood of the block with the seed [blockSeed]: the indices of
  /// the source blocks whose XOR yields the payload. Ascending, without
  /// repetition.
  ///
  /// **This function is the wire format.** Sender and recipient must get
  /// the same list for the same `(k, blockSeed)`, otherwise the recipient
  /// silently reconstructs wrongly.
  Uint32List neighbours(int blockSeed) {
    final rng = FountainPrng.forBlock(sourceBlocks, blockSeed);
    final d = sampleDegree(rng);
    return rng.distinctIndices(sourceBlocks, d);
  }
}
