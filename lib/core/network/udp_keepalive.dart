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

/// UDP keepalive for **confirmed NAT-traversal peers**.
///
/// Architecture §2.4.5 / §7.6: keepalive HOLE_PUNCH_PING packets maintain
/// carrier-NAT pinholes (typical lifetime 30–60 s). Registration is gated
/// by the caller (`_needsKeepalive` in CleonaNode): only peers reachable
/// through an actual NAT boundary are registered — LAN peers (private IPv4,
/// same-/64 IPv6) are excluded because no pinhole exists to maintain.
///
/// Newly registered peers start as **unconfirmed** and receive at most
/// [maxUnconfirmedPings] attempts (default 3). A PONG promotes the peer
/// to **confirmed** (= successful NAT traversal); confirmed peers are
/// pinged indefinitely. Unconfirmed peers that exhaust their attempts are
/// **suspended** until a network-change event calls [resetUnconfirmed].
///
/// Distinguished from [NatTraversal]'s built-in keepalive which only runs
/// for [PunchedConnection]s — those require a coordinated hole punch first.
///
/// Architecture §7.6: after 3 consecutive rounds where **all** active
/// (non-suspended) peers fail to PONG (~75 s), [onAllPeersFailed] is
/// invoked so the node can run a full `onNetworkChanged()` cycle. A 5-min
/// cooldown prevents spamming this callback after the trigger fires.
///
/// All public methods are exception-safe — register/send/receive/dispose
/// never throw.
class UdpKeepalive {
  final CLogger _log;

  /// Fixed keepalive interval — sub-30s to stay safely under typical
  /// carrier-NAT pinhole lifetimes (Telekom DE / O2 documented at ≥30 s;
  /// 25 s + Timer-Periodic jitter sat too close to the edge, 20 s gives
  /// 33 % safety margin at +0.5 B/s/peer additional traffic).
  /// Per `docs/SPEC_HYBRID_BULK_TRANSPORT.md` Patch D.
  static const Duration interval = Duration(seconds: 20);

  /// PONG must arrive within this window after a PING for the round to
  /// count as successful.
  static const Duration pongWindow = Duration(seconds: 10);

  /// After this many consecutive rounds where ALL peers fail,
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

  /// Number of consecutive rounds where every registered peer failed.
  int _consecutiveFullFailures = 0;

  /// Last time [onAllPeersFailed] fired (for cooldown).
  DateTime? _lastTriggerAt;

  /// Whether this instance has been disposed.
  bool _disposed = false;

  // ── Wired callbacks (set by CleonaNode) ─────────────────────────────

  /// V3-direct InfrastructureFrame sender at an explicit address. See
  /// [SendInfraDirectFn]. Wires to `cleona_node.sendInfraDirectTo`.
  ///
  /// V3.0: keepalive PINGs ship via `NetworkPacketV3` (the receiver
  /// only parses V3 since Welle 1 — see
  /// `transport.dart:_processUdpDatagram`); the legacy raw-bytes path was
  /// silently dropped at the upstream — pinholes expired ~30-60 s after
  /// the last real traffic. The V3-direct fn ensures the packet is
  /// wrapped, KEM-AEAD'd, Outer-Sig'd and HMAC'd correctly.
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
        // Idempotent: refresh address if it changed, but don't reset state.
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
  /// peer. Resets the consecutive-full-failure counter (a single PONG
  /// proves at least one pinhole is alive).
  void onPongReceived(String peerHex) {
    if (_disposed) return;
    try {
      final entry = _peers[peerHex];
      if (entry == null) return;
      entry.lastPongAt = DateTime.now();
      entry.pendingPong = false;
      if (!entry.confirmed) {
        entry.confirmed = true;
        _log.info('NAT keepalive confirmed for ${peerHex.substring(0, 8)} '
            '— pinhole alive');
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
  /// [maxUnconfirmedPings] attempts. Called on network change — the NAT
  /// context may have changed, so previously-unreachable peers might now
  /// respond. Confirmed peers keep their status.
  void resetUnconfirmed() {
    if (_disposed) return;
    var reset = 0;
    for (final p in _peers.values) {
      if (!p.confirmed && p.unconfirmedPingsSent >= maxUnconfirmedPings) {
        p.unconfirmedPingsSent = 0;
        reset++;
      }
    }
    if (reset > 0) {
      _log.info('Network change: reset $reset suspended peers for retry');
    }
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
    _roundTimer = Timer.periodic(interval, (_) => _runRound());
  }

  void _runRound({DateTime? now}) {
    if (_disposed) return;
    if (_peers.isEmpty) return;

    final tNow = now ?? DateTime.now();

    try {
      // 1. Score the previous round: any peer whose pendingPong is still
      //    true AND whose ping went out before (now - pongWindow) failed.
      //
      // Topology-aware filter (Architektur §2.7.2): peers that have failed
      // [peerExclusionThreshold] consecutive rounds are considered
      // structurally unreachable (e.g. LAN peer behind AP isolation, public
      // peer whose port mapping has gone) and are excluded from the
      // all-failed quorum. They still get pinged so they can rejoin the
      // quorum the instant a PONG arrives — a single success resets the
      // counter via `onPongReceived`.
      var allFailed = true;
      var anyEvaluated = false;
      for (final p in _peers.values) {
        // Suspended (unconfirmed + exhausted attempts) → not pinged, skip.
        if (!p.confirmed && p.unconfirmedPingsSent >= maxUnconfirmedPings) continue;
        // Only evaluate peers we sent a ping to last round.
        final pingAt = p.lastPingAt;
        if (pingAt == null) continue;
        if (tNow.difference(pingAt) < pongWindow) {
          // Still inside its pong window → not yet failed (treat as
          // "not evaluated" for this round's allFailed decision).
          continue;
        }
        if (p.pendingPong) {
          // Did not pong in time. Bookkeep the failure regardless of
          // exclusion — counter must keep climbing for cooldown logic.
          p.consecutiveFailures++;
          // Only structurally-eligible peers contribute to the quorum.
          if (p.consecutiveFailures < peerExclusionThreshold) {
            anyEvaluated = true;
          }
        } else {
          // Pong arrived in time.
          anyEvaluated = true;
          allFailed = false;
          p.consecutiveFailures = 0;
        }
      }

      // Update the consecutive-full-failure counter only if we actually
      // evaluated at least one peer's previous round.
      if (anyEvaluated) {
        if (allFailed) {
          _consecutiveFullFailures++;
          _log.info('Full keepalive round failed '
              '(consecutive: $_consecutiveFullFailures / $failureThreshold)');
        } else {
          _consecutiveFullFailures = 0;
        }
      }

      // 2. Fire the network-change callback if threshold reached and
      //    cooldown elapsed. Either way, reset the counter so we
      //    re-evaluate the next 3 rounds fresh (avoids unbounded growth
      //    while cooldown is active).
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

      // 3. Send pings for the current round.
      for (final p in _peers.values) {
        _sendPing(p, tNow);
      }
    } catch (e) {
      _log.debug('round error: $e');
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

      // V3-direct: build NetworkPacketV3 (HMAC + KEM-AEAD + Outer-Sig)
      // and push to (addr, port). Fire-and-forget — implementation
      // swallows its own errors and reports false on KEM-PK miss.
      send(
        proto.MessageTypeV3.MTV3_HOLE_PUNCH_PING,
        ping.writeToBuffer(),
        p.peerNodeId,
        addr,
        p.port,
      ).catchError((_) => false);

      p.lastPingAt = now;
      p.pendingPong = true;
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

/// Per-peer keepalive bookkeeping.
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

  /// Number of pings sent while unconfirmed. Capped at
  /// [UdpKeepalive.maxUnconfirmedPings]; once reached the peer is suspended
  /// until a network change resets the counter.
  int unconfirmedPingsSent = 0;

  _KeepalivePeer({
    required this.peerHex,
    required this.peerNodeId,
    required this.ip,
    required this.port,
  });
}
