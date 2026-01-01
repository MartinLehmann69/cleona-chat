// S123 Erasure-F1: ACK-verified Reed-Solomon fragment placement (K-of-N).
//
// Pure, network-independent wave planner + confirmation counter. Kept
// separate from CleonaService/CleonaNode so the wave/candidate-rotation
// logic can be smoke-tested without sockets, timers, or a running node:
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
    required String Function(Peer peer) peerId,
    this.initialReplicaCount = 3,
    this.maxCopiesPerFragment = 5,
    this.maxRetryWaves = 2,
    bool Function(Peer peer)? isPeerConfirmed,
  })  : _peerId = peerId,
        _isPeerConfirmed = isPeerConfirmed;

  final int totalFragments;
  final int requiredFragments;
  final int initialReplicaCount;
  final int maxCopiesPerFragment;
  final int maxRetryWaves;
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
    for (var i = 0; i < totalFragments; i++) {
      if (confirmedIndices.contains(i)) continue;
      if ((_copies[i] ?? 0) >= maxCopiesPerFragment) continue;
      final triedIds = _attemptedPeerIds[i] ?? const <String>{};
      Peer? candidate;
      for (final p in pool) {
        if (!triedIds.contains(_peerId(p))) {
          candidate = p;
          break;
        }
      }
      if (candidate == null) continue; // pool exhausted for this index
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
