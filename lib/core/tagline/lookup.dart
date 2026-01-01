// The iterative lookup — the only place that turns a tag into a set
// of reachable responsible nodes.
//
// WHY THE I/O IS HANDED IN.
//
// E-L (from M9): lookups run over the onion, not directly. Reason:
// a direct iterative lookup shows every queried node the pair
// (initiator address, sought tag) — a fleet with 25 % would see 78 % of the
// individual lookups and at the same time with 99.3 % hold one of the R
// responsible ones, thus sees „A searches T" and „B collects from T" and thereby has
// A <-> B. Exactly the linkage that §10.1 declares
// closed.
//
// This file therefore knows NO socket. It gets a query
// function handed in and does not know whether it goes directly or through two
// onion shells. The driver does not have to change when WP-2 puts the
// onion underneath.
//
// TERMINATION. Per M9: asking continues as long as among the k nearest
// known nodes there is an unasked one — BUT NOT LONGER THAN UNTIL
// CONVERGENCE (see [iterativeLookup], `stopWhenStable`). Measured this gives
// 1.1 / 1.8 / 2.3 rounds and 3.3 / 5.3 / 7.0 requests at 10^3 / 10^4
// / 10^5 nodes, at recall 1.00.
library;

import 'dart:typed_data';

import 'package:cleona/core/bulk/responsibility.dart';
import 'routing_table.dart';

/// How many requests run side by side per round.
///
/// Three — and the number is not free: M9 names „7.0 requests" at 2.3
/// rounds and 10^5 nodes. `7,0 / 2,3 = 3,04`. Whoever changes it changes
/// the measurement basis of §9.1 and the cold-start calculation of §7.2 as well.
const int kLookupParallelism = 3;

/// Asks a node for the nearest nodes to [target] known to it.
///
/// May throw or answer empty — both count as „did not
/// answer" and do not end the lookup. A node that is gone
/// is the normal case, not an error.
typedef LookupQuery = Future<List<KnownNode>> Function(
    KnownNode peer, Uint8List target);

final class LookupResult {
  /// The nearest nodes found, ascending by distance.
  final List<KnownNode> closest;

  /// How many rounds have run.
  final int rounds;

  /// How many nodes were queried.
  final int queried;

  /// How many of them did not answer.
  final int silent;

  /// After which round the result set no longer changed.
  ///
  /// That is the quantity M9 measures as CONVERGENCE and that counts for
  /// latency: from here on the searcher knows where to. The rounds after that
  /// only query the found responsible nodes — that is the
  /// delivery itself, not search effort.
  final int roundsToStable;

  LookupResult(this.closest, this.rounds, this.queried, this.silent,
      this.roundsToStable);

  @override
  String toString() => 'LookupResult(${closest.length} found, '
      '$rounds rounds, $roundsToStable of them until stable, '
      '$queried queried, $silent silent)';
}

/// Searches the [count] nearest nodes to [target].
///
/// [alpha] requests run side by side per round. That is the
/// parallelism of the NETWORK — at egress the cover cycle serialises them
/// anyway (§7), which does not change the number of rounds, only the wall clock.
///
/// ── WHY IT ABORTS AT CONVERGENCE (S356) ────────────────────
///
/// [stopWhenStable] ends the search as soon as a whole round no longer
/// changed the set of the [count] nearest. Without this abort
/// the strict Kademlia rule applies „keep asking while among the k
/// nearest there is an unasked one" — and that queries ALL k in the end. With
/// `count = R = 20` that is about twenty requests.
///
/// That is not what was measured and what was budgeted. M9 counts
/// explicitly up to CONVERGENCE („measured separately from the
/// subsequent queries to those R") and arrives at 7.0 requests at 10^5
/// nodes; §7.2 calculates the cold start with „~7 slots ~ 56 s at
/// R_cover = 1/8 s". Twenty requests are twenty slots — 160 s instead of
/// 56 s, i.e. 2.9 times the budget, and that per target and epoch.
///
/// The difference to M9 is that the requests AFTER convergence there
/// are the delivery itself. Here they are not: the delivery
/// goes as storing or harvest to the same R relays and is paid
/// separately. Asking on after convergence thus yields nothing.
///
/// `false` switches back to the strict rule — the reverse test with
/// which it can be shown that the abort does not cost recall.
Future<LookupResult> iterativeLookup({
  required Uint8List target,
  required RoutingTable table,
  required LookupQuery query,
  int alpha = kLookupParallelism,
  int count = kResponsibleRelays,
  int maxRounds = 60,
  bool stopWhenStable = true,
}) async {
  final known = <String, KnownNode>{};
  for (final n in table.closest(target, count: count)) {
    known[n.positionHex] = n;
  }

  final queried = <String>{};
  var rounds = 0;
  var silent = 0;
  var roundsToStable = 0;
  var lastBest = '';

  while (rounds < maxRounds) {
    final best = closestTo<KnownNode>(
        target, known.values, (n) => n.position,
        count: count);
    final next = best
        .where((n) => !queried.contains(n.positionHex))
        .take(alpha)
        .toList();
    if (next.isEmpty) break;

    rounds++;
    for (final peer in next) {
      queried.add(peer.positionHex);
    }

    final answers = await Future.wait(next.map((peer) async {
      try {
        return await query(peer, target);
      } catch (_) {
        return const <KnownNode>[];
      }
    }));

    for (final batch in answers) {
      if (batch.isEmpty) silent++;
      for (final n in batch) {
        known.putIfAbsent(n.positionHex, () => n);
      }
    }

    final nowBest = closestTo<KnownNode>(target, known.values, (n) => n.position,
            count: count)
        .map((n) => n.positionHex)
        .join();
    if (nowBest != lastBest) {
      lastBest = nowBest;
      roundsToStable = rounds;
    } else if (stopWhenStable) {
      // A full round no longer moved the set of the nearest.
      // Asking more costs slots and does not change the result.
      break;
    }
  }

  return LookupResult(
      closestTo<KnownNode>(target, known.values, (n) => n.position,
          count: count),
      rounds,
      queried.length,
      silent,
      roundsToStable);
}

// ── THE CACHE ────────────────────────────────────────────────────────────
//
// WHY IT MUST EXIST, and why it is not convenient but necessary.
//
// A lookup costs about seven requests, and every request is a cell
// from the own cover cycle: 7 slots ~ 56 s at `R_cover = 1/8 s` (§7.2).
// If the lookup were in the send path, EVERY message would cost a minute of search
// before the first storing went out — and a conversation with ten
// messages ten minutes of it.
//
// §7.2 says the opposite: the cold start pays the lookup FIRST,
// „below the harvest cadence that dominates it". Once per target and
// epoch, not per message. Exactly this bookkeeping is what this class keeps.
//
// WHY THE TARGET IS THE KEY. The target is `H(T ‖ e)` (E-H) — the
// epoch is already in it. An epoch change thus automatically yields
// a different key and with it a new lookup; there is nothing
// to invalidate. What remains is cleaning up old entries, and
// [expire] does that.
//
// WHY FULL AND PARTIAL SETS ARE VALID FOR DIFFERENT DURATIONS. A full
// set (R nodes) is valid for the whole epoch: 10 Speed contacts x m=3
// families = 30 targets x 7 slots = 210 slots ~ 28 min PER DAY. That fits.
// With hourly refresh it would be 28 min PER HOUR — that does not
// fit, and that is why there is no round hour value here.
//
// An incomplete set, by contrast, is the situation of a cold or
// small network, and that changes in minutes. Holding it for a whole epoch
// would mean nailing a node that knew three relays at 09:00 down to
// three relays until the next day — even if at 09:05
// twenty are reachable. Hence [partialTtl].
//
// NO EMPTY SET IS STORED. A lookup that found nothing is
// no statement about the network but about the own state
// (table empty, no partner). Storing it would mean cementing the own
// cold start.

/// How long a FULL responsibility set is valid: one epoch (E-J).
const Duration kResponsibleSetTtl = Duration(seconds: kEpochSeconds);

/// How long an incomplete set is valid.
const Duration kPartialResponsibleSetTtl = Duration(minutes: 10);

/// How many targets are held at the same time.
///
/// 256, the same size as `V41Node.kOwnRequestMemory` — at m = 3
/// families per pair and direction that covers about 40 counterparts, and
/// §7 names no more Speed contacts.
const int kMaxCachedTargets = 256;

final class _CachedSet {
  final List<KnownNode> nodes;
  final DateTime until;
  final bool full;
  _CachedSet(this.nodes, this.until, this.full);
}

/// Holds the results of the lookup per target and hands them to the send path
/// SYNCHRONOUSLY.
///
/// The split is the whole idea:
///
///   * [cached] is synchronous, does no I/O and returns `null`
///     if nothing valid is there. The send path only calls that. It
///     thus NEVER waits for a search and on `null` falls back to the
///     local table — the old approximation, but never a halt.
///   * [ensure] is asynchronous and belongs in the cycle (cold start,
///     epoch change, slot driver), not in `send`.
///
/// NO CLOCK OF ITS OWN where avoidable: [now] comes
/// in, so that every statement here stays testable without waiting.
final class ResponsibleSetCache {
  /// How many nodes a set holds (`R`, E-H).
  final int count;

  /// Validity of a full set.
  final Duration ttl;

  /// Validity of an incomplete set.
  final Duration partialTtl;

  /// How many targets are held.
  final int maxTargets;

  ResponsibleSetCache({
    this.count = kResponsibleRelays,
    this.ttl = kResponsibleSetTtl,
    this.partialTtl = kPartialResponsibleSetTtl,
    this.maxTargets = kMaxCachedTargets,
  });

  final Map<String, _CachedSet> _sets = <String, _CachedSet>{};
  final Map<String, Future<List<KnownNode>>> _inFlight =
      <String, Future<List<KnownNode>>>{};

  /// How many searches have really run — the number from which
  /// it can be read whether the lookup hangs in the send path.
  int lookupsRun = 0;

  /// How often a search was attached to one already running.
  int lookupsCoalesced = 0;

  /// How often it was served from the cache.
  int servedFromCache = 0;

  /// How many network requests the searches that ran cost together.
  int queriesSpent = 0;

  static String _key(Uint8List target) =>
      target.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// The stored set for [target], or `null`.
  ///
  /// SYNCHRONOUS AND WITHOUT I/O — that is the promise to the send path.
  List<KnownNode>? cached(Uint8List target, {DateTime? now}) {
    final e = _sets[_key(target)];
    if (e == null) return null;
    final current = (now ?? DateTime.now()).toUtc();
    if (!current.isBefore(e.until)) return null;
    servedFromCache++;
    return e.nodes;
  }

  /// Ensures that a set exists for [target], and returns
  /// it.
  ///
  /// If a valid one is already there, the call costs nothing. If a
  /// search to the same target is already running, it is attached to instead of
  /// starting a second — with m = 3 families and two counterparts on
  /// the same mark there would otherwise be several searches over the same
  /// seven slots.
  Future<List<KnownNode>> ensure({
    required Uint8List target,
    required RoutingTable table,
    required LookupQuery query,
    DateTime? now,
    int alpha = kLookupParallelism,
    bool force = false,
  }) {
    final k = _key(target);
    final current = (now ?? DateTime.now()).toUtc();
    if (!force) {
      final e = _sets[k];
      if (e != null && current.isBefore(e.until)) {
        servedFromCache++;
        return Future.value(e.nodes);
      }
      final running = _inFlight[k];
      if (running != null) {
        lookupsCoalesced++;
        return running;
      }
    }

    lookupsRun++;
    final f = iterativeLookup(
      target: target,
      table: table,
      query: query,
      alpha: alpha,
      count: count,
    ).then((res) {
      queriesSpent += res.queried;
      // EMPTY IS NOT STORED — see head of this section.
      if (res.closest.isNotEmpty) {
        final full = res.closest.length >= count;
        _sets[k] = _CachedSet(
            List<KnownNode>.unmodifiable(res.closest),
            current.add(full ? ttl : partialTtl),
            full);
        _trim();
      }
      return res.closest;
    }).whenComplete(() {
      _inFlight.remove(k);
    });
    _inFlight[k] = f;
    return f;
  }

  /// Clears out what has expired. Returns how many entries went.
  int expire({DateTime? now}) {
    final current = (now ?? DateTime.now()).toUtc();
    final dead = _sets.entries
        .where((e) => !current.isBefore(e.value.until))
        .map((e) => e.key)
        .toList();
    for (final k in dead) {
      _sets.remove(k);
    }
    return dead.length;
  }

  /// Keeps the cache at [maxTargets]; the oldest entry goes.
  void _trim() {
    while (_sets.length > maxTargets) {
      _sets.remove(_sets.keys.first);
    }
  }

  /// How many targets are held.
  int get size => _sets.length;

  /// How many lookups are currently running.
  int get inFlight => _inFlight.length;

  @override
  String toString() => 'ResponsibleSetCache($size targets, '
      '$lookupsRun lookups / $queriesSpent queries, '
      '$servedFromCache from the cache, '
      '$lookupsCoalesced coalesced)';
}
