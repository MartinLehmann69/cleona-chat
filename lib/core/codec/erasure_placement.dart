// S123 Erasure-F1: ACK-verified Reed-Solomon fragment placement (K-of-N).
//
// Pure, network-independent wave planner + confirmation counter. Kept
// separate from CleonaService (and until the CUT of 2026-08-31 also from
// `CleonaNode`, which no longer exists since then) so the
// wave/candidate-rotation logic can be smoke-tested without sockets,
// timers, or a running node:
// the actual FRAGMENT_STORE send + ACK-wait is injected via [sendAndWait]
// (mirrors the Completer+timeout pattern used by the pre-existing F1
// S&F path `_storeSafOnNetworkPeers` in cleona_service.dart) — this class
// only decides WHO gets WHICH fragment in WHICH wave, and counts distinct
// confirmed fragment indices.
//
// Design (Architecture §5.4 + S123 Erasure-F1 spec):
//  - Wave 1 (initial): every fragment index 0..N-1 is sent to
//    `min(initialReplicaCount, pool.length)` peers from [initialPool],
//    rotated `pool[(i + r) % pool.length]` — identical to the pre-F1
//    fire-and-forget placement.
//  - Success = at least [requiredFragments] (K) distinct fragment indices
//    confirmed via FRAGMENT_STORE_ACK.
//  - Up to [maxRetryWaves] additional waves target ONLY unconfirmed
//    indices, drawing one fresh (not-yet-tried-for-this-index) candidate
//    per index from a deeper pool ([deeperPool], re-queried per wave so
//    callers can reflect a live routing table). Confirmed peers are
//    preferred first when [isPeerConfirmed] is supplied.
//  - Per-fragment copy cap ([maxCopiesPerFragment]) bounds total replicas
//    of a single fragment across all waves (Design decision #6: max 5
//    copies per fragment network-wide — 3 initial + 1 per retry wave).
//  - A wave that finds no untried candidate for any remaining unconfirmed
//    index ends immediately (pool-exhaustion early-out) rather than
//    padding with a no-op send.
library;

/// Outcome of a full placement run.
class ErasurePlacementResult {
  const ErasurePlacementResult({
    required this.success,
    required this.confirmedCount,
    required this.totalFragments,
    required this.requiredFragments,
    required this.wavesUsed,
  });

  final bool success;
  final int confirmedCount;
  final int totalFragments;
  final int requiredFragments;
  final int wavesUsed;

  /// True when placement succeeded (>=K confirmed) but fewer than N
  /// indices confirmed — the offline copy is deliverable but has reduced
  /// erasure headroom (fewer peer failures tolerated before K is at risk).
  bool get fragile => success && confirmedCount < totalFragments;
}

/// One planned (fragmentIndex -> peer) send.
class PlannedFragmentSend<Peer> {
  const PlannedFragmentSend(this.fragmentIndex, this.peer);
  final int fragmentIndex;
  final Peer peer;
}

class ErasurePlacementCoordinator<Peer> {
  ErasurePlacementCoordinator({
    required this.totalFragments,
    required this.requiredFragments,
    required this._peerId,
    this.initialReplicaCount = 3,
    this.maxCopiesPerFragment = 5,
    this.maxRetryWaves = 2,
    this.distinctPeerPerWave = false,
    this._isPeerConfirmed,
  });

  final int totalFragments;
  final int requiredFragments;
  final int initialReplicaCount;
  final int maxCopiesPerFragment;
  final int maxRetryWaves;

  /// May a peer receive several fragment indices in ONE wave?
  ///
  /// ── WHY THIS IS A CHOICE AND NOT A DEFAULT (S372) ──────────────
  ///
  /// The first wave distributes a different peer per index anyway
  /// (`pool[(i + r) % pool.length]`). A RETRY wave does not: for each
  /// unconfirmed index it looks for the first peer that has not yet been
  /// tried for THIS index — and that is the same one for all unconfirmed
  /// indices. Four indices then land on one peer.
  ///
  /// For the original use (S123, fragments in the DHT) that was right:
  /// there the only thing that counted was getting `K` distinct indices
  /// confirmed, and a peer was allowed to hold several. For the stripe
  /// coding of the media lane (§9.3) it is wrong — its design
  /// `N = K + d` (`codec/erasure_stripes.dart`) only holds as long as the
  /// `N` fragments of a stripe lie on `N` DIFFERENT holders; four on one
  /// holder means that its failure alone kills the stripe.
  ///
  /// That is why it is a switch and not a change: the old use stays word
  /// for word as it was (`smoke_erasure_placement.dart` sections 2 and 3
  /// explicitly rely on a retry peer serving several indices).
  final bool distinctPeerPerWave;

  final String Function(Peer peer) _peerId;
  final bool Function(Peer peer)? _isPeerConfirmed;

  /// Peers already attempted per fragment index (across all waves).
  final Map<int, Set<String>> _attemptedPeerIds = {};

  /// Total copies dispatched per fragment index so far.
  final Map<int, int> _copies = {};

  /// Distinct fragment indices confirmed via ACK so far.
  final Set<int> confirmedIndices = {};

  /// Total number of (fragmentIndex, peer) sends issued across all waves.
  int get sendsIssued => _copies.values.fold(0, (a, b) => a + b);

  Map<int, int> get copiesPerFragment => Map.unmodifiable(_copies);

  /// Runs the initial wave, then up to [maxRetryWaves] retry waves for any
  /// indices still unconfirmed, stopping early once K is reached or a wave
  /// finds no eligible candidate at all.
  ///
  /// [sendAndWait] performs one FRAGMENT_STORE dispatch for
  /// `(fragmentIndex, peer)` and resolves `true` iff a FRAGMENT_STORE_ACK
  /// for that index was observed before its own timeout budget — this
  /// coordinator implements no waiting/timeout of its own.
  Future<ErasurePlacementResult> run({
    required List<Peer> initialPool,
    required List<Peer> Function() deeperPool,
    required Future<bool> Function(int fragmentIndex, Peer peer) sendAndWait,
  }) async {
    if (initialPool.isEmpty) {
      return ErasurePlacementResult(
        success: false,
        confirmedCount: 0,
        totalFragments: totalFragments,
        requiredFragments: requiredFragments,
        wavesUsed: 0,
      );
    }

    await _runWave(_planInitialWave(initialPool), sendAndWait);

    var wave = 1;
    while (confirmedIndices.length < requiredFragments &&
        wave <= maxRetryWaves) {
      final pool = _sortConfirmedFirst(deeperPool());
      final sends = _planRetryWave(pool);
      if (sends.isEmpty) break; // no untried candidate anywhere — stop
      await _runWave(sends, sendAndWait);
      wave++;
    }

    return ErasurePlacementResult(
      success: confirmedIndices.length >= requiredFragments,
      confirmedCount: confirmedIndices.length,
      totalFragments: totalFragments,
      requiredFragments: requiredFragments,
      wavesUsed: wave,
    );
  }

  /// The same as [run], only without waiting — for a carrier that gets
  /// no RECEIPT for a placement.
  ///
  /// ── WHY THIS SECOND VERSION EXISTS SINCE S372 ─────────────────
  ///
  /// [run] presupposes that `sendAndWait` can wait for a
  /// FRAGMENT_STORE_ACK. On the V4.1 line that does not exist: `BulkOp`
  /// (`bulk/bulk_frames.dart`) knows `place`, `scanRequest`,
  /// `scanResponse`, `scanEnd` and `publicBlock` — **no placement
  /// receipt**, and the PLACE frame carries no request identifier by
  /// which one could find its way back. Measured on 06.09.2026.
  ///
  /// **This version therefore says LESS, and it says so explicitly:**
  /// [send] returns `true` if the fragment was handed over to THIS holder
  /// — queued or held itself —, **not** that the holder has stored it.
  /// Whoever wants the stronger promise needs the wire change (request
  /// identifier in the PLACE frame, return path via `PendingRequests`,
  /// sixth opcode; price: one additional cell per fragment). It lies
  /// with the owner as a proposal and is not built on the side.
  ///
  /// **Even the weaker statement holds**, and that is the reason why
  /// this version was built at all: it replaces today's SILENT loss when
  /// no next hop is known to a responsible holder
  /// (`media_bulk_transport_v41.dart`, `placeOnce` drops such blocks)
  /// with a resubmission to ANOTHER holder. With a stripe coding exactly
  /// that is the difference between "a stripe is missing" and "the object
  /// is there": a stripe with more than `N-K` gaps is irretrievable, and
  /// there is no re-request that would heal it.
  ErasurePlacementResult runSync({
    required List<Peer> initialPool,
    required List<Peer> Function() deeperPool,
    required bool Function(int fragmentIndex, Peer peer) send,
  }) {
    if (initialPool.isEmpty) {
      return ErasurePlacementResult(
        success: false,
        confirmedCount: 0,
        totalFragments: totalFragments,
        requiredFragments: requiredFragments,
        wavesUsed: 0,
      );
    }

    _runWaveSync(_planInitialWave(initialPool), send);

    var wave = 1;
    while (confirmedIndices.length < requiredFragments &&
        wave <= maxRetryWaves) {
      final pool = _sortConfirmedFirst(deeperPool());
      final sends = _planRetryWave(pool);
      if (sends.isEmpty) break; // no untried candidate anywhere — stop
      _runWaveSync(sends, send);
      wave++;
    }

    return ErasurePlacementResult(
      success: confirmedIndices.length >= requiredFragments,
      confirmedCount: confirmedIndices.length,
      totalFragments: totalFragments,
      requiredFragments: requiredFragments,
      wavesUsed: wave,
    );
  }

  void _runWaveSync(List<PlannedFragmentSend<Peer>> sends,
      bool Function(int fragmentIndex, Peer peer) send) {
    for (final s in sends) {
      if (send(s.fragmentIndex, s.peer)) confirmedIndices.add(s.fragmentIndex);
    }
  }

  List<Peer> _sortConfirmedFirst(List<Peer> pool) {
    final isConfirmed = _isPeerConfirmed;
    if (isConfirmed == null) return pool;
    final confirmed = <Peer>[];
    final rest = <Peer>[];
    for (final p in pool) {
      (isConfirmed(p) ? confirmed : rest).add(p);
    }
    return [...confirmed, ...rest];
  }

  List<PlannedFragmentSend<Peer>> _planInitialWave(List<Peer> pool) {
    final sends = <PlannedFragmentSend<Peer>>[];
    final replicaCount =
        pool.length < initialReplicaCount ? pool.length : initialReplicaCount;
    for (var i = 0; i < totalFragments; i++) {
      for (var r = 0; r < replicaCount; r++) {
        final peer = pool[(i + r) % pool.length];
        sends.add(PlannedFragmentSend(i, peer));
        _markAttempted(i, peer);
      }
    }
    return sends;
  }

  List<PlannedFragmentSend<Peer>> _planRetryWave(List<Peer> pool) {
    final sends = <PlannedFragmentSend<Peer>>[];
    // Only filled with [distinctPeerPerWave] — the reasoning is there.
    final inThisWave = <String>{};
    for (var i = 0; i < totalFragments; i++) {
      if (confirmedIndices.contains(i)) continue;
      if ((_copies[i] ?? 0) >= maxCopiesPerFragment) continue;
      final triedIds = _attemptedPeerIds[i] ?? const <String>{};
      Peer? candidate;
      for (final p in pool) {
        final id = _peerId(p);
        if (triedIds.contains(id)) continue;
        if (distinctPeerPerWave && inThisWave.contains(id)) continue;
        candidate = p;
        break;
      }
      if (candidate == null) continue; // pool exhausted for this index
      if (distinctPeerPerWave) inThisWave.add(_peerId(candidate));
      sends.add(PlannedFragmentSend(i, candidate));
      _markAttempted(i, candidate);
    }
    return sends;
  }

  void _markAttempted(int fragmentIndex, Peer peer) {
    (_attemptedPeerIds[fragmentIndex] ??= <String>{}).add(_peerId(peer));
    _copies[fragmentIndex] = (_copies[fragmentIndex] ?? 0) + 1;
  }

  Future<void> _runWave(
    List<PlannedFragmentSend<Peer>> sends,
    Future<bool> Function(int fragmentIndex, Peer peer) sendAndWait,
  ) async {
    if (sends.isEmpty) return;
    await Future.wait(sends.map((s) async {
      final ok = await sendAndWait(s.fragmentIndex, s.peer);
      if (ok) confirmedIndices.add(s.fragmentIndex);
    }));
  }
}
