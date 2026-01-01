import 'dart:convert';
import 'dart:typed_data';

import 'onion.dart';

/// Resolves which link a path block belongs to — by trying
/// (decision (a), 2026-08-22).
///
/// THE PROBLEM. The path block is sealed under the link key B<->r2.
/// r2 thus only knows AFTER opening that it is about B —
/// and needs B's key to open. Chicken and egg.
///
/// THE RESOLUTION. r2 tries its link keys and remembers
/// the assignment seed -> link. Because the path block is CONSTANT per pair and epoch,
/// the cache hits from the second cell on: the full
/// pass happens once per pair and epoch, not per cell.
///
/// WHAT THAT COSTS, measured: 41.6 us with four partners (24 064 cells/s
/// on one core). Whoever wants to force the node into a full pass with garbage
/// must push 29 MB/s into it for that — a bandwidth problem, not a
/// computing problem. The cap below is there nevertheless, because an unbounded
/// loop is never a good idea.
///
/// WHY NOT AN IDENTIFIER IN PLAINTEXT. It would be O(1), but would cost
/// a property: the path block today differs per PAIR, a
/// link identifier would be the same per TARGET. r1 could thereby group flows
/// of different senders heading for the same B
/// — today it cannot.
final class ReplyBlockResolver {
  /// The link keys of the own partners. Live list: if a
  /// partner is added, it is included in the next pass.
  final List<Uint8List> linkKeys;

  /// Maximum number of remembered assignments.
  ///
  /// An entry is a 16-B seed and an index. At 2048 entries that is
  /// a good 120 KB — enough for the pairs a node forwards for in an
  /// epoch, and little enough that no one notices.
  final int cacheSize;

  /// Maximum number of full passes per release ([resetScanBudget]).
  ///
  /// With four partners 500 passes are about 21 ms, i.e. a good 2 % of a
  /// second on one core.
  final int scanBudget;

  final Map<String, int> _bySeed = <String, int>{};
  final List<String> _lru = <String>[];
  int _scansLeft;

  /// Counters for the status line — never a log per cell.
  int scans = 0;
  int cacheHits = 0;
  int refused = 0;

  ReplyBlockResolver({
    required this.linkKeys,
    this.cacheSize = 2048,
    this.scanBudget = 500,
  }) : _scansLeft = scanBudget;

  /// Releases the pass budget again.
  ///
  /// CALLER: `V41Node.run` in `driver.onSlotDone` — i.e. **per slot**,
  /// not per second. Until 2026-08-29 (S351) this said „the caller
  /// calls this every second", and there was none at all in `lib/`: the
  /// cap was thus not a cap but an end point. After
  /// [scanBudget] cache misses [resolve] returned `null` forever
  /// and the node forwarded nothing more as r2 — silently,
  /// because an unresolved path block cannot be told apart from a foreign
  /// one.
  ///
  /// The slot cycle instead of a clock of its own, because a second rhythm
  /// would be recognisable from outside (invariant 1). At `kSlotInterval`
  /// = 8 s that is on average a good 62 passes per second — tighter than
  /// the old comment promised, not looser.
  void resetScanBudget() => _scansLeft = scanBudget;

  int get cachedPairs => _bySeed.length;

  /// The link key for this forwarded cell, or `null`.
  Uint8List? resolve(Uint8List forwarded, int epoch) {
    if (forwarded.length < kReplyBlockBytes) return null;
    final seed =
        base64.encode(Uint8List.sublistView(forwarded, 0, kSeedBytes));

    // 1. Remembered? Then try only THIS one. If it fails,
    //    the memory was stale — then the full pass counts.
    final remembered = _bySeed[seed];
    if (remembered != null && remembered < linkKeys.length) {
      if (_fits(forwarded, linkKeys[remembered], epoch)) {
        cacheHits++;
        _touch(seed);
        return linkKeys[remembered];
      }
      _forget(seed);
    }

    // 2. Full pass — capped.
    if (_scansLeft <= 0) {
      refused++;
      return null;
    }
    _scansLeft--;
    scans++;
    for (var i = 0; i < linkKeys.length; i++) {
      if (_fits(forwarded, linkKeys[i], epoch)) {
        _remember(seed, i);
        return linkKeys[i];
      }
    }
    return null;
  }

  /// Tries ONE key. The epoch tolerance lies with
  /// `deliverSecondHop`; here only the named epoch is checked, otherwise
  /// the pass would triple.
  bool _fits(Uint8List forwarded, Uint8List key, int epoch) =>
      redeemReplyBlock(forwarded: forwarded, linkKeyToB: key, epoch: epoch) !=
      null;

  void _remember(String seed, int idx) {
    if (!_bySeed.containsKey(seed) && _bySeed.length >= cacheSize) {
      final route = _lru.removeAt(0);
      _bySeed.remove(route);
    }
    _bySeed[seed] = idx;
    _touch(seed);
  }

  void _touch(String seed) {
    _lru.remove(seed);
    _lru.add(seed);
  }

  void _forget(String seed) {
    _bySeed.remove(seed);
    _lru.remove(seed);
  }
}
