import 'package:cleona/core/network/clogger.dart';

/// Tracks consecutive send failures per peer and decides when to
/// fall back to TLS on port+2.
///
/// V3: TLS is last resort. Threshold: 15 consecutive failures → enter TLS mode.
/// TLS mode only kicks in after the entire routing cascade (Direct, Relay, DV, S&F).
/// While in TLS mode, sends go directly via TLS. UDP probes attempt recovery.
/// On UDP success, TLS mode is exited.
/// After 10 minutes without failures, the counter decays to zero.
class TlsFallbackManager {
  static const int failureThreshold = 15;
  static const Duration _baseProbeInterval = Duration(minutes: 1);
  static const Duration _maxProbeInterval = Duration(minutes: 30);
  static const Duration _decayTimeout = Duration(minutes: 10);

  final _consecutiveFailures = <String, int>{};
  final _inTlsMode = <String, bool>{};
  final _lastFailure = <String, DateTime>{};
  final _lastProbeAttempt = <String, DateTime>{};
  final _probeAttemptCount = <String, int>{};
  final _log = CLogger.get('tls-fallback');

  /// Record a successful UDP/TCP send to [peerId].
  void recordSuccess(String peerId) {
    _consecutiveFailures.remove(peerId);
    _probeAttemptCount.remove(peerId);
    _lastProbeAttempt.remove(peerId);
    if (_inTlsMode[peerId] == true) {
      _inTlsMode.remove(peerId);
      _log.info('Peer ${peerId.substring(0, 8)}: UDP success → exiting TLS mode');
    }
  }

  /// Record a successful TLS send (stays in TLS mode, but resets failure count).
  void recordTlsSuccess(String peerId) {
    _consecutiveFailures.remove(peerId);
    // Stay in TLS mode — don't exit until UDP probe succeeds
  }

  /// Record a failed send to [peerId]. Increments failure counter.
  void recordFailure(String peerId) {
    _consecutiveFailures[peerId] = (_consecutiveFailures[peerId] ?? 0) + 1;
    _lastFailure[peerId] = DateTime.now();
    if (_consecutiveFailures[peerId] == failureThreshold && _inTlsMode[peerId] != true) {
      _inTlsMode[peerId] = true;
      _probeAttemptCount.remove(peerId);
      _lastProbeAttempt.remove(peerId);
      _log.info('Peer ${peerId.substring(0, 8)}: $failureThreshold consecutive failures → entering TLS mode');
    }
  }

  /// Whether this peer is in TLS mode (should send via TLS directly).
  bool isInTlsMode(String peerId) {
    if (_inTlsMode[peerId] != true) {
      // Check for decay: if last failure was > 10 min ago, reset counter
      final lastFail = _lastFailure[peerId];
      if (lastFail != null && DateTime.now().difference(lastFail) > _decayTimeout) {
        _consecutiveFailures.remove(peerId);
        _lastFailure.remove(peerId);
      }
      return false;
    }
    return true;
  }

  /// Whether a UDP probe should be attempted (exponential backoff: 1min, 2min, 4min, ... 30min cap).
  bool shouldProbeUdp(String peerId) {
    if (_inTlsMode[peerId] != true) return false;
    final lastProbe = _lastProbeAttempt[peerId];
    if (lastProbe == null) return true; // First probe
    final attempts = _probeAttemptCount[peerId] ?? 0;
    final intervalMs = (_baseProbeInterval.inMilliseconds * (1 << attempts.clamp(0, 5)))
        .clamp(0, _maxProbeInterval.inMilliseconds);
    return DateTime.now().difference(lastProbe).inMilliseconds >= intervalMs;
  }

  /// Reset probe timer (call after each UDP probe attempt).
  void resetProbeTimer(String peerId) {
    _lastProbeAttempt[peerId] = DateTime.now();
    _probeAttemptCount[peerId] = (_probeAttemptCount[peerId] ?? 0) + 1;
  }

  /// Legacy: whether TLS should be attempted (>= threshold failures).
  bool shouldUseTls(String peerId) => isInTlsMode(peerId);

  /// Current failure count for a peer.
  int failureCount(String peerId) => _consecutiveFailures[peerId] ?? 0;

  /// Reset all state (network topology changed — old failure data is stale).
  void reset() {
    final wasTls = _inTlsMode.keys.toList();
    _consecutiveFailures.clear();
    _inTlsMode.clear();
    _lastFailure.clear();
    _lastProbeAttempt.clear();
    _probeAttemptCount.clear();
    if (wasTls.isNotEmpty) {
      _log.info('Reset: cleared TLS mode for ${wasTls.length} peer(s) (network change)');
    }
  }
}
