import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';

import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Direct-address V3 InfrastructureFrame sender contract used by
/// [UdpKeepalive] and [NatTraversal]. The implementation builds a
/// V3 NetworkPacketV3 (HMAC + KEM-AEAD + Outer-Sig) and pushes it via
/// UDP to the explicit `(addr, port)` — bypassing the DV-cascade so we
/// can hit a known pinhole. Fire-and-forget; returns false on
/// (a) messageType outside the §2.3.5 InfraFrame selector,
/// (b) no Device-KEM-PK known for `recipientDeviceId`, or
/// (c) transport rejection.
typedef SendInfraDirectFn = Future<bool> Function(
  proto.MessageTypeV3 messageType,
  Uint8List innerPayload,
  Uint8List recipientDeviceId,
  InternetAddress addr,
  int port,
);

/// UDP keepalive for **confirmed NAT-traversal peers** with adaptive
/// per-peer interval probing (Architecture §7.6).
///
/// Each peer's keepalive interval starts at [initialIntervalMs] and is
/// probed upward (×1.5) after [_stableRoundsToEscalate] consecutive
/// successful PONGs, discovering the carrier's NAT pinhole lifetime.
/// On failure the interval falls back to the last confirmed-safe value.
/// The operational interval converges to ~80% of the actual NAT timeout
/// (since ×1.5 probing overshoots by at most 50%, falling back to the
/// previous step lands at 67–100% of the true timeout).
///
/// Registration is gated by the caller (`_needsKeepalive` in CleonaNode):
/// only peers reachable through an actual NAT boundary are registered —
/// LAN peers (private IPv4, same-/64 IPv6) are excluded.
///
/// Newly registered peers start as **unconfirmed** and receive at most
/// [maxUnconfirmedPings] attempts (default 3). A PONG promotes the peer
/// to **confirmed** (= successful NAT traversal); confirmed peers are
/// pinged indefinitely. Unconfirmed peers that exhaust their attempts are
/// **suspended** until a network-change event calls [resetUnconfirmed].
///
/// Architecture §7.6: after 3 consecutive tick-rounds where **all** active
/// (non-suspended) peers fail to PONG, [onAllPeersFailed] is invoked so
/// the node can run a full `onNetworkChanged()` cycle. A 5-min cooldown
/// prevents spamming this callback after the trigger fires.
///
/// All public methods are exception-safe — register/send/receive/dispose
/// never throw.
class UdpKeepalive {
  final CLogger _log;

  /// Tick interval for the global round timer. Each tick checks which
  /// peers are due for their next adaptive-interval ping.
  static const Duration _tickInterval = Duration(seconds: 5);

  /// Initial per-peer keepalive interval (conservative safe default).
  static const int initialIntervalMs = 20000;

  /// Minimum per-peer keepalive interval (floor).
  static const int minIntervalMs = 15000;

  /// Maximum per-peer keepalive interval (ceiling).
  static const int maxIntervalMs = 120000;

  /// After this many consecutive PONGs at the current interval, try ×1.5.
  static const int _stableRoundsToEscalate = 3;

  /// PONG must arrive within this window after a PING for the round to
  /// count as successful.
  static const Duration pongWindow = Duration(seconds: 10);

  /// After this many consecutive tick-rounds where ALL peers fail,
  /// [onAllPeersFailed] is invoked.
  static const int failureThreshold = 3;

  /// After [onAllPeersFailed] fires, wait this long before allowing
  /// another trigger (prevents spam).
  static const Duration triggerCooldown = Duration(minutes: 5);

  /// Per-peer failure threshold for the topology-aware quorum filter
  /// (Architektur §2.7.2 / §7.6). Once a peer has failed this many
  /// consecutive keepalive rounds it is treated as structurally unreachable
  /// in the current network (e.g. LAN peer behind AP isolation, public peer
  /// whose port mapping is gone) and excluded from the all-failed quorum so
  /// it does not, on its own, trigger a network-change cycle. The peer stays
  /// registered and can rejoin the quorum the moment a single PONG arrives
  /// (`onPongReceived` resets `consecutiveFailures` to 0).
  static const int peerExclusionThreshold = 5;

  /// Unconfirmed peers (no PONG ever received) are pinged at most this many
  /// times before being suspended. A PONG promotes to confirmed; network
  /// change resets suspended peers for another round of attempts.
  static const int maxUnconfirmedPings = 3;

  /// Registered peers: peerHex → entry.
  final Map<String, _KeepalivePeer> _peers = {};

  /// Periodic timer running rounds.
  Timer? _roundTimer;

  /// Number of consecutive tick-rounds where every registered peer failed.
  int _consecutiveFullFailures = 0;

  /// Last time [onAllPeersFailed] fired (for cooldown).
  DateTime? _lastTriggerAt;

  /// Whether this instance has been disposed.
  bool _disposed = false;

  // ── Wired callbacks (set by CleonaNode) ─────────────────────────────

  /// V3-direct InfrastructureFrame sender at an explicit address. See
  /// [SendInfraDirectFn]. Wires to `cleona_node.sendInfraDirectTo`.
  SendInfraDirectFn? sendInfraFn;

  /// Own deviceNodeId — set on init.
  Uint8List? ownNodeId;

  /// Called once when [failureThreshold] consecutive full-failure rounds
  /// occur. Caller is expected to run a full network-change cycle.
  void Function()? onAllPeersFailed;

  // ── Construction ─────────────────────────────────────────────────────

  UdpKeepalive({String? profileDir})
      : _log = CLogger.get('udp-keepalive', profileDir: profileDir);

  // ── Public API ───────────────────────────────────────────────────────

  /// Register a public-IP peer for keepalive (idempotent).
  ///
  /// Skips RFC1918 / loopback IPs — keepalive is only meaningful for
  /// peers behind a NAT pinhole that would otherwise expire.
  void register(
    String peerHex,
    String ip,
    int port,
    Uint8List peerNodeId,
  ) {
    if (_disposed) return;
    try {
      if (ip.isEmpty || port <= 0 || port > 65535) return;
      if (PeerAddress.isPrivateIp(ip)) return;

      final existing = _peers[peerHex];
      if (existing != null) {
        if (existing.ip != ip || existing.port != port) {
          existing.ip = ip;
          existing.port = port;
          _log.debug(
              'Address updated for ${peerHex.substring(0, 8)}: $ip:$port');
        }
        return;
      }

      _peers[peerHex] = _KeepalivePeer(
        peerHex: peerHex,
        peerNodeId: Uint8List.fromList(peerNodeId),
        ip: ip,
        port: port,
      );
      _log.info('Registered ${peerHex.substring(0, 8)} at $ip:$port '
          '(total: ${_peers.length})');

      _ensureTimerRunning();
    } catch (e) {
      _log.debug('register error: $e');
    }
  }

  /// Remove a peer from the keepalive set.
  void unregister(String peerHex) {
    if (_disposed) return;
    try {
      final removed = _peers.remove(peerHex);
      if (removed != null) {
        _log.debug('Unregistered ${peerHex.substring(0, 8)} '
            '(remaining: ${_peers.length})');
      }
      if (_peers.isEmpty) {
        _roundTimer?.cancel();
        _roundTimer = null;
      }
    } catch (e) {
      _log.debug('unregister error: $e');
    }
  }

  /// Update the address of an already-registered peer (e.g. on network
  /// change or learned new endpoint). Filters private IPs.
  void updateAddress(String peerHex, String ip, int port) {
    if (_disposed) return;
    try {
      final entry = _peers[peerHex];
      if (entry == null) return;
      if (ip.isEmpty || port <= 0 || port > 65535) return;
      if (PeerAddress.isPrivateIp(ip)) {
        unregister(peerHex);
        return;
      }
      if (entry.ip == ip && entry.port == port) return;
      entry.ip = ip;
      entry.port = port;
      _log.debug('Address updated for ${peerHex.substring(0, 8)}: $ip:$port');
    } catch (e) {
      _log.debug('updateAddress error: $e');
    }
  }

  /// Called by the receive path when ANY PONG is observed for a registered
  /// peer. Updates adaptive interval probing state.
  void onPongReceived(String peerHex) {
    if (_disposed) return;
    try {
      final p = _peers[peerHex];
      if (p == null) return;
      p.lastPongAt = DateTime.now();
      p.pendingPong = false;
      if (!p.confirmed) {
        p.confirmed = true;
        _log.info('NAT keepalive confirmed for ${peerHex.substring(0, 8)} '
            '— pinhole alive');
      }
      // Adaptive probing: PONG at current interval → count as stable.
      p.stableRounds++;
      p.probeFailures = 0;
      p.lastConfirmedIntervalMs = p.adaptiveIntervalMs;
      if (!p.converged && p.stableRounds >= _stableRoundsToEscalate) {
        final nextMs = (p.adaptiveIntervalMs * 1.5).round();
        if (nextMs <= maxIntervalMs) {
          _log.info('${peerHex.substring(0, 8)} stable at '
              '${p.adaptiveIntervalMs}ms — probing ${nextMs}ms');
          p.adaptiveIntervalMs = nextMs;
          p.stableRounds = 0;
        } else {
          p.converged = true;
          _log.info('${peerHex.substring(0, 8)} converged at '
              '${p.adaptiveIntervalMs}ms (max reached)');
        }
      }
      if (_consecutiveFullFailures > 0) {
        _log.debug('PONG from ${peerHex.substring(0, 8)} '
            '— resetting full-failure counter '
            '(was: $_consecutiveFullFailures)');
      }
      _consecutiveFullFailures = 0;
    } catch (e) {
      _log.debug('onPongReceived error: $e');
    }
  }

  /// Reset suspended (unconfirmed) peers so they get another round of
  /// [maxUnconfirmedPings] attempts. Also resets adaptive probing for all
  /// confirmed peers — the NAT context may have changed (new carrier,
  /// new NAT device), so previously-measured timeouts are invalid.
  void resetUnconfirmed() {
    if (_disposed) return;
    var reset = 0;
    for (final p in _peers.values) {
      if (!p.confirmed && p.unconfirmedPingsSent >= maxUnconfirmedPings) {
        p.unconfirmedPingsSent = 0;
        reset++;
      }
      if (p.confirmed) {
        p.adaptiveIntervalMs = initialIntervalMs;
        p.lastConfirmedIntervalMs = initialIntervalMs;
        p.stableRounds = 0;
        p.probeFailures = 0;
        p.converged = false;
      }
    }
    if (reset > 0) {
      _log.info('Network change: reset $reset suspended peers for retry');
    }
    _log.info('Network change: reset adaptive intervals to ${initialIntervalMs}ms');
  }

  /// Stop all timers and clear state. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try {
      _roundTimer?.cancel();
    } catch (_) {}
    _roundTimer = null;
    _peers.clear();
    _consecutiveFullFailures = 0;
    _log.debug('disposed');
  }

  // ── Diagnostic / Test Properties ────────────────────────────────────

  /// Number of currently registered peers.
  int get peerCount => _peers.length;

  /// Current consecutive-full-failure round count.
  int get consecutiveFullFailures => _consecutiveFullFailures;

  /// Whether the periodic round timer is currently armed.
  bool get isRunning => _roundTimer != null && _roundTimer!.isActive;

  /// Run one keepalive round synchronously (for tests). The normal path
  /// uses [Timer.periodic]; this method drives the same logic without
  /// real wall-clock waits.
  ///
  /// `simulatedNow` lets tests advance "logical time" so the pong-window
  /// expiry check can be exercised without real delays. If null,
  /// `DateTime.now()` is used.
  ///
  /// Test-only API — not used by production code.
  void doRoundForTest({DateTime? simulatedNow}) {
    _runRound(now: simulatedNow);
  }

  // ── Internal: Timer + Round Loop ─────────────────────────────────────

  void _ensureTimerRunning() {
    if (_disposed) return;
    if (_roundTimer != null && _roundTimer!.isActive) return;
    _roundTimer = Timer.periodic(_tickInterval, (_) => _runRound());
  }

  void _runRound({DateTime? now}) {
    if (_disposed) return;
    if (_peers.isEmpty) return;

    final tNow = now ?? DateTime.now();

    try {
      // 1. Score peers whose pong window has elapsed since their last ping.
      var allFailed = true;
      var anyEvaluated = false;
      for (final p in _peers.values) {
        if (!p.confirmed && p.unconfirmedPingsSent >= maxUnconfirmedPings) continue;
        final pingAt = p.lastPingAt;
        if (pingAt == null) continue;
        if (tNow.difference(pingAt) < pongWindow) continue;
        if (!p.scored) {
          p.scored = true;
          if (p.pendingPong) {
            p.consecutiveFailures++;
            _onPeerPingFailed(p);
            if (p.consecutiveFailures < peerExclusionThreshold) {
              anyEvaluated = true;
            }
          } else {
            anyEvaluated = true;
            allFailed = false;
            p.consecutiveFailures = 0;
          }
        }
      }

      if (anyEvaluated) {
        if (allFailed) {
          _consecutiveFullFailures++;
          _log.info('Full keepalive round failed '
              '(consecutive: $_consecutiveFullFailures / $failureThreshold)');
        } else {
          _consecutiveFullFailures = 0;
        }
      }

      // 2. Fire the network-change callback if threshold reached.
      if (_consecutiveFullFailures >= failureThreshold) {
        final last = _lastTriggerAt;
        final cooldownPassed = last == null ||
            tNow.difference(last) >= triggerCooldown;
        _consecutiveFullFailures = 0;
        if (cooldownPassed) {
          _lastTriggerAt = tNow;
          _log.warn('All peers failed for $failureThreshold rounds '
              '— triggering onAllPeersFailed');
          try {
            onAllPeersFailed?.call();
          } catch (e) {
            _log.debug('onAllPeersFailed callback error: $e');
          }
        } else {
          _log.debug('Threshold reached but cooldown active — skip trigger');
        }
      }

      // 3. Send pings only to peers whose adaptive interval has elapsed.
      for (final p in _peers.values) {
        final pingAt = p.lastPingAt;
        if (pingAt != null) {
          final elapsed = tNow.difference(pingAt).inMilliseconds;
          if (elapsed < p.adaptiveIntervalMs) continue;
        }
        _sendPing(p, tNow);
      }
    } catch (e) {
      _log.debug('round error: $e');
    }
  }

  /// Handle a ping failure for adaptive probing. If we were probing at a
  /// higher interval and it failed, fall back to the last confirmed value.
  void _onPeerPingFailed(_KeepalivePeer p) {
    if (p.converged) return;
    p.probeFailures++;
    if (p.probeFailures >= 2 &&
        p.adaptiveIntervalMs > p.lastConfirmedIntervalMs) {
      p.adaptiveIntervalMs = p.lastConfirmedIntervalMs;
      p.converged = true;
      p.stableRounds = 0;
      _log.info('${p.peerHex.substring(0, 8)} NAT probe failed at higher '
          'interval — converged at ${p.adaptiveIntervalMs}ms');
    }
  }

  void _sendPing(_KeepalivePeer p, DateTime now) {
    final send = sendInfraFn;
    final me = ownNodeId;
    if (send == null || me == null) return;

    if (!p.confirmed && p.unconfirmedPingsSent >= maxUnconfirmedPings) return;

    try {
      final reqId = _randomBytes(16);
      final ping = proto.HolePunchPing()
        ..requestId = reqId
        ..senderNodeId = me
        ..timestampMs = Int64(now.millisecondsSinceEpoch);

      InternetAddress addr;
      try {
        addr = InternetAddress(p.ip);
      } catch (_) {
        return;
      }

      send(
        proto.MessageTypeV3.MTV3_HOLE_PUNCH_PING,
        ping.writeToBuffer(),
        p.peerNodeId,
        addr,
        p.port,
      ).catchError((_) => false);

      p.lastPingAt = now;
      p.pendingPong = true;
      p.scored = false;
      if (!p.confirmed) {
        p.unconfirmedPingsSent++;
        if (p.unconfirmedPingsSent >= maxUnconfirmedPings) {
          _log.info('Suspending ${p.peerHex.substring(0, 8)} — '
              '$maxUnconfirmedPings pings without PONG');
        }
      }
    } catch (e) {
      _log.debug('send error to ${p.peerHex.substring(0, 8)}: $e');
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  static Uint8List _randomBytes(int length) {
    final bytes = Uint8List(length);
    final now = DateTime.now().microsecondsSinceEpoch;
    for (var i = 0; i < length; i++) {
      bytes[i] = ((now >> (i * 3)) ^ (i * 17 + now)) & 0xFF;
    }
    return bytes;
  }
}

/// Per-peer keepalive bookkeeping with adaptive interval state.
class _KeepalivePeer {
  final String peerHex;
  final Uint8List peerNodeId;
  String ip;
  int port;
  DateTime? lastPingAt;
  DateTime? lastPongAt;
  bool pendingPong = false;
  int consecutiveFailures = 0;

  /// True once a PONG has been received — the NAT pinhole is confirmed alive.
  bool confirmed = false;

  /// Number of pings sent while unconfirmed.
  int unconfirmedPingsSent = 0;

  /// Whether this ping's result has been scored already (prevents
  /// double-scoring across multiple ticks within the same pong window).
  bool scored = false;

  // ── Adaptive interval probing (§7.6) ───────────────────────────────

  /// Current keepalive interval for this peer (milliseconds).
  int adaptiveIntervalMs = UdpKeepalive.initialIntervalMs;

  /// Highest interval at which a PONG was received.
  int lastConfirmedIntervalMs = UdpKeepalive.initialIntervalMs;

  /// Consecutive PONGs at the current interval.
  int stableRounds = 0;

  /// Consecutive failures while probing a higher interval.
  int probeFailures = 0;

  /// True when the NAT timeout has been discovered — no more probing.
  bool converged = false;

  _KeepalivePeer({
    required this.peerHex,
    required this.peerNodeId,
    required this.ip,
    required this.port,
  });
}
