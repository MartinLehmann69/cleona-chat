// How many CONSECUTIVE seeds an object really needs (§9.3).
//
// ── WHY THIS EXISTS AT ALL ───────────────────────────────────────
//
// On 31.08.2026 the lower bound of the media lanes fell from 256 KB to 32 KB
// (`bulk_params.dart:kFountainWorthwhileBytes`). The 256 KB were
// not arbitrary: the rateless overshoot is large AND long-tailed for small objects,
// and `bulkOvershoot` plans with a
// MEAN CURVE. Before lowering, the obvious safeguard was to use the
// measured MAXIMUM instead of the mean. Two measurements settled that
// path and opened this one.
//
// **MEASUREMENT 1 — the maximum is not a bound** (31.08.2026, k = 64,
// random seeds, the same graph counter as `test/perf/perf_fountain.dart`):
//
//     runs        max
//        100   2,2188
//      1 000   2,8750
//     10 000   3,3594
//    100 000   4,3438
//    400 000   4,4375
//
// The "maximum 2.750" from §9.3 is the maximum of ONE sample of 3 000
// runs, not a property of the codec. It keeps growing with the number of runs;
// basing a promise on it would mean tying the promise to the duration
// of the measurement.
//
// **MEASUREMENT 2 — the sender does not roll dice at all.** `BulkSender` uses
// [SequentialSeeds] as the default (`bulk_keys.dart`: the only consumer
// has EXACTLY ONE seeder). Its seeds are 0, 1, 2, … — the block set is
// thus a FUNCTION OF k, not a random quantity. The whole
// mean/maximum question is the wrong question for it; the right one is:
// how long must the prefix 0..N-1 be for it to peel? Exactly that
// is computed by [exactSequentialPrefix] — not estimated, but counted on the
// graph.
//
// **WHAT STOOD OUT IN THE PROCESS, and it is a bug in the existing code, not a by-product:**
// in the band 32 KiB..256 KiB **57 of 225** object sizes are UNDERPLANNED —
// the receiver does not finish with ZERO loss, because
// `ceil(k * measuredFountainOverhead)` lies below the necessary prefix.
//
// ── UNTIL S363 THE NUMBER WAS "56", AND THAT WAS A DIFFERENT MEASUREMENT ──────
//
// Back then it was counted against `bulkOvershoot`, and that was
// `max(Kurve, 1,3)` — the floor lifted ONE size above the necessary
// prefix and hid it: k = 199 (203 776 B) needs 259, the curve
// plans 258, the floor gave 259. Since S363 `bulkOvershoot` is a
// derivation with coverage (`bulk_params.dart`) and no longer the curve;
// therefore it is counted against the curve itself, and there it is 57.
// Examples:
//
//     k = 42  (43 008 B): needed 117 (2,786), planned  60 (1,421)
//     k = 64  (65 536 B): needed  95 (1,484), planned  88 (1,367)
//     k = 104 (106 496 B): needed 189 (1,817), planned 139 (1,335)
//
// It does not stop above 256 KB: in the band k = 256..2200 there are
// still 24 of 1945, the last at k = 1131 (1.16 MB, needed 1.330 against
// planned 1.300). From there on the curve holds in the measured range.
//
// **WHY NOT A FIXED FACTOR THAT COVERS EVERYTHING.** It would have to be >= 2.786
// (k = 42) and would cost, compared with the exact value, **+120.8 %**
// traffic in the band 32..256 KiB, in the band 256..2200 still +29.4 %. The exact
// value instead costs computing time, and little of it: measured 0 ms at
// k = 32, 8 ms at k = 256, 21 ms at k = 1024, 50 ms at k = 4096.
//
// NO STATE, NO I/O, NO CRYPTO. Pure Dart on the graph —
// the same property from which `lib/core/fountain/` gets by without FFI
// (E-42).
library;

import 'dart:typed_data';

import 'package:cleona/core/fountain/degree_distribution.dart';

/// Up to which number of source blocks the exact prefix is computed.
///
/// **4096 blocks = 4 MiB.** The number has two sides, both measured:
///
///   * **Benefit.** Exhaustively measured is the band k = 32..2200; the
///     last underplanned size lies at k = 1131. 4096 covers it by a
///     margin. Samples above that (k = 4096: 1,0737; 16 384: 1,0598;
///     65 536: 1,0350; 204 800: 1,0204) all lie clearly below the
///     default 1.3 from appendix A — there the curve holds.
///   * **Price.** The counter costs, as measured, 50 ms at k = 4096, but
///     652 ms at k = 65 536 and 3.1 s at k = 204 800. It runs
///     SYNCHRONOUSLY in the send path; 3 s of frozen screen on a phone (which on the
///     bulk lane only sends, `bulk_sender.dart`) would be visible
///     damage for a gain that the measurement does not show there.
const int kExactPrefixMaxSourceBlocks = 4096;

/// The smallest number `N` for which the seeds `0..N-1` completely peel the object with
/// [sourceBlocks] source blocks.
///
/// Returns `-1` if even `12 * k + 64` blocks do not suffice — that has never
/// happened in the measured range (sweep k = 32..2200, largest value
/// 2.786 at k = 42) and stands here as a latch against an endless loop,
/// not as an expected outcome.
///
/// THE CALLER NEED NOT KNOW THE ORDER: peeling depends
/// only on the SET of blocks, not on the sequence in which they
/// arrive. The receiver may thus harvest them in any order.
///
/// **Only valid for [BulkSeedPolicy.sequential].** A seeder with
/// [KeyedSeeds] draws other seeds; for it this number is meaningless,
/// and `BulkSender.plannedBlocks` then does not ask for it.
int exactSequentialPrefix(int sourceBlocks) {
  if (sourceBlocks < 1) {
    throw ArgumentError.value(sourceBlocks, 'sourceBlocks', 'must be >= 1');
  }
  final dist = DegreeDistribution(sourceBlocks);
  final peeler = _Peeler(sourceBlocks, dist);
  final limit = sourceBlocks * 12 + 64;
  var n = 0;
  while (!peeler.isComplete) {
    if (n >= limit) return -1;
    peeler.offer(n);
    n++;
  }
  return n;
}

/// The peeling loop of `FountainDecoder` WITHOUT payloads.
///
/// WHY NOT `FountainDecoder` ITSELF. It holds a 1024 B buffer per source block
/// and XORs them; for the question "does every
/// block eventually fall to remainder 1?" the bytes are irrelevant — XOR is associative
/// and commutative, the answer depends solely on the bipartite graph. Without
/// payloads the answer costs, as measured, 50 ms at k = 4096 instead of a
/// multiple of that, and it does not occupy 4 MiB.
///
/// Kept as a mirror image of the decoder: number of open neighbours plus
/// XOR sum of their indices, no neighbour list.
final class _Peeler {
  final int k;
  final DegreeDistribution dist;
  final List<int> _remaining = <int>[];
  final List<int> _remainingSum = <int>[];
  final List<bool> _retired = <bool>[];
  final List<List<int>?> _waitingOn;
  final List<bool> _known;
  int resolved = 0;

  _Peeler(this.k, this.dist)
      : _waitingOn = List<List<int>?>.filled(k, null),
        _known = List<bool>.filled(k, false);

  bool get isComplete => resolved == k;

  void offer(int blockSeed) {
    if (isComplete) return;
    final neigh = dist.neighbours(blockSeed);
    final open = Uint32List(neigh.length);
    var openCount = 0;
    var openSum = 0;
    for (var i = 0; i < neigh.length; i++) {
      if (!_known[neigh[i]]) {
        open[openCount++] = neigh[i];
        openSum ^= neigh[i];
      }
    }
    if (openCount == 0) return;
    final id = _remaining.length;
    _remaining.add(openCount);
    _remainingSum.add(openSum);
    _retired.add(false);
    if (openCount == 1) {
      _cascade(id);
      return;
    }
    for (var i = 0; i < openCount; i++) {
      (_waitingOn[open[i]] ??= <int>[]).add(id);
    }
  }

  void _cascade(int start) {
    final work = <int>[start];
    while (work.isNotEmpty) {
      final p = work.removeLast();
      if (_retired[p] || _remaining[p] != 1) continue;
      _retired[p] = true;
      final idx = _remainingSum[p];
      if (_known[idx]) continue;
      _known[idx] = true;
      resolved++;
      final waiters = _waitingOn[idx];
      if (waiters == null) continue;
      _waitingOn[idx] = null;
      for (final w in waiters) {
        if (_retired[w]) continue;
        _remaining[w]--;
        _remainingSum[w] ^= idx;
        if (_remaining[w] == 0) {
          _retired[w] = true;
        } else if (_remaining[w] == 1) {
          work.add(w);
        }
      }
    }
  }
}
