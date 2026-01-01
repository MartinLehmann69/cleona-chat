import 'dart:async';
import 'dart:io';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/core/network/udp_keepalive.dart' show SendInfraDirectFn;
import 'package:fixnum/fixnum.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// DV-cascade V3 InfrastructureFrame sender contract used by
/// [NatTraversal] for HOLE_PUNCH_REQUEST → coordinator and HOLE_PUNCH_NOTIFY
/// → target. The implementation builds a V3 NetworkPacketV3 and routes it
/// through the DV cascade (max 3 routes + default-gateway fallback).
/// Fire-and-forget; returns false on (a) messageType outside §2.3.5,
/// (b) no Device-KEM-PK known, (c) DV cascade exhausted.
typedef SendInfraFn = Future<bool> Function(
  proto.MessageTypeV3 messageType,
  Uint8List innerPayload,
  Uint8List recipientDeviceId,
);

/// Decentralized STUN + NAT Hole Punch + Keepalive.
///
/// Three responsibilities:
/// 1. Track public IP observations from peers (decentralized STUN).
/// 2. Coordinate UDP hole punches via a mutual third-party node.
/// 3. Maintain keepalive for punched connections (only periodic traffic in the system).
class NatTraversal {
  final CLogger _log;
  final Map<String, String> _observations = {}; // peerNodeIdHex -> observedIp
  String? _confirmedPublicIp;
  int? _confirmedPublicPort;
  NatClassification natType = NatClassification.unknown;

  // Port mapping state (set by PortMapper via setPortMapping/clearPortMapping).
  String? _mappedPublicIp;
  int? _mappedPublicPort;
  bool _hasPortMapping = false;

  // ── NAT-Wizard signals (§27.9.1) — set by PortMapper, read by NetworkStats.
  // Populated by instance I1 (backend). Until then they stay at unknown/null
  // and the wizard trigger evaluates as "not ready" — safe default.
  /// UPnP IGD status. Use [setUpnpStatus] to mutate.
  String _upnpStatus = 'unknown'; // stored as enum-name to avoid circular import
  /// PCP / NAT-PMP status. Use [setPcpStatus] to mutate.
  String _pcpStatus = 'unknown';
  /// Parsed UPnP rootDesc. Use [setUpnpRouterInfoJson] to mutate.
  Map<String, dynamic>? _upnpRouterInfoJson;

  // External IP discovered without verified port mapping (ipify, UPnP IP-only).
  // Used for NAT context (same-NAT detection) but NOT advertised to peers
  // as a reachable address — the port is not forwarded.
  String? _externalIpOnly;

  /// Minimum number of peer confirmations before accepting a public IP.
  static const int minConfirmations = 2;

  /// Active hole punch sessions: requestIdHex → HolePunchSession
  final Map<String, HolePunchSession> _activePunches = {};

  /// Established punched connections: peerNodeIdHex → PunchedConnection
  final Map<String, PunchedConnection> _punchedConnections = {};

  /// V3-direct DV-cascade InfrastructureFrame sender. Wires to
  /// `cleona_node.sendInfraTo`. Used for HOLE_PUNCH_REQUEST →
  /// coordinator and HOLE_PUNCH_NOTIFY → target.
  ///
  /// V3.0: the §2.3.5 InfraFrame pipeline owns Device-Sig +
  /// KEM-AEAD + HMAC; this module hands off via `(type, body, nodeId)`.
  SendInfraFn? sendInfraFn;

  /// V3-direct address-targeted InfrastructureFrame sender. Wires to
  /// `cleona_node.sendInfraDirectTo`. Used for HOLE_PUNCH_PING /
  /// HOLE_PUNCH_PONG and pinhole-keepalive where we have an explicit
  /// `(addr, port)` and bypassing the DV cascade is mandatory (we want
  /// to hit *that* address, not whatever route DV thinks is cheapest).
  ///
  /// V3.0: hole-punch + pinhole-keepalive ship via `NetworkPacketV3`
  /// (the receiver only parses V3 since Welle 1 — see
  /// `transport.dart:_processUdpDatagram`). Pinholes
  /// expire ~30-60 s after last real traffic, NAT keepalive probing
  /// never advanced past its first interval, and `_punchedConnections`
  /// were torn down spuriously.
  SendInfraDirectFn? sendInfraDirectFn;

  /// Own node ID (set by CleonaNode on start).
  Uint8List? ownNodeId;

  /// Keepalive timers per punched connection.
  final Map<String, Timer> _keepaliveTimers = {};

  NatTraversal({String? profileDir})
      : _log = CLogger.get('nat', profileDir: profileDir);

  // ── Public IP Observation (Decentralized STUN) ────────────────────────

  /// Record a peer's observation of our public address.
  void addObservation(String peerNodeIdHex, String observedIp, int observedPort) {
    if (observedIp.isEmpty || observedIp == '0.0.0.0') return;
    // Private IPs are normally rejected (an echo of our own LAN IP can't be
    // a public address), but a *cross-class* private observation IS a real
    // egress: e.g. an Android emulator on 10.0.2.x sees its packets exit
    // through the host's 192.168.x.x LAN, or a mobile device on carrier
    // CGNAT (100.64.x.x) shows up to a home peer as 192.168.x.x. In both
    // cases the observation tells us the legit reachable address from the
    // observer's perspective — accept and confirm only when we have NO
    // local IP in the same class as the observation.
    if (PeerAddress.isPrivateIp(observedIp)) {
      final localPrivates =
          PeerAddress.currentLocalIps.where(PeerAddress.isPrivateIp).toList();
      if (localPrivates.isEmpty) return; // can't disambiguate
      final sameClassFound = localPrivates
          .any((local) => PeerAddress.samePrivateClass(observedIp, local));
      if (sameClassFound) {
        // Observation is in the same RFC1918 class as a local IP — most
        // likely an echo of our own LAN, not a real egress. Reject.
        return;
      }
      // Cross-class private: accept as bridged-LAN egress.
    }
    _observations[peerNodeIdHex] = observedIp;

    // Count confirmations for the most-reported IP
    final ipCounts = <String, int>{};
    for (final ip in _observations.values) {
      ipCounts[ip] = (ipCounts[ip] ?? 0) + 1;
    }

    final sorted = ipCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (sorted.isNotEmpty && sorted.first.value >= minConfirmations) {
      final newIp = sorted.first.key;
      if (_confirmedPublicIp != newIp) {
        _log.info('Public IP confirmed: $newIp (${sorted.first.value} confirmations)');
        _confirmedPublicIp = newIp;
        _confirmedPublicPort = observedPort;
        _classifyNat();
      }
    }
  }

  void _classifyNat() {
    if (_confirmedPublicIp == null) {
      natType = NatClassification.unknown;
      return;
    }
    natType = NatClassification.fullCone; // Assume full cone for now
  }

  // ── Hole Punch Coordination ───────────────────────────────────────────

  /// Initiate a hole punch to targetNodeId via coordinatorNodeId.
  ///
  /// Flow:
  /// 1. We send HOLE_PUNCH_REQUEST to the coordinator
  /// 2. Coordinator forwards HOLE_PUNCH_NOTIFY to the target
  /// 3. Both sides send HOLE_PUNCH_PING to each other's public IP
  /// 4. NAT pinholes open, HOLE_PUNCH_PONG confirms connectivity
  void initiateHolePunch(Uint8List targetNodeId, Uint8List coordinatorNodeId) {
    if (ownNodeId == null || !hasPublicIp) return;
    if (sendInfraFn == null) return;

    final targetHex = bytesToHex(targetNodeId);

    // Already punched or in progress?
    if (_punchedConnections.containsKey(targetHex)) return;
    if (_activePunches.values.any((s) => s.targetHex == targetHex)) return;

    // Generate request ID
    final requestId = _randomBytes(16);
    final requestIdHex = bytesToHex(requestId);

    final session = HolePunchSession(
      requestId: requestId,
      targetNodeId: targetNodeId,
      coordinatorNodeId: coordinatorNodeId,
      initiatedAt: DateTime.now(),
    );
    _activePunches[requestIdHex] = session;

    // Auto-cleanup after 30s
    Timer(const Duration(seconds: 30), () {
      _activePunches.remove(requestIdHex);
    });

    // Build and send HOLE_PUNCH_REQUEST to coordinator via DV-cascade.
    final req = proto.HolePunchRequest()
      ..targetNodeId = targetNodeId
      ..myPublicIp = _confirmedPublicIp!
      ..myPublicPort = _confirmedPublicPort!
      ..requestId = requestId;

    sendInfraFn!(
      proto.MessageTypeV3.MTV3_HOLE_PUNCH_REQUEST,
      req.writeToBuffer(),
      coordinatorNodeId,
    );
    _log.info('Hole punch initiated for ${targetHex.substring(0, 8)} '
        'via coordinator ${bytesToHex(coordinatorNodeId).substring(0, 8)}');
  }

  /// Handle incoming HOLE_PUNCH_REQUEST (we are the coordinator).
  ///
  /// Forward a HOLE_PUNCH_NOTIFY to the target peer.
  ///
  /// Welle 5.x V3 hard-cut: arguments now reflect the V3 receive-side
  /// shape — the parsed [proto.HolePunchRequest] body plus the sender
  /// deviceNodeId extracted from the InfrastructureFrameV3 envelope.
  /// Receive-side dispatch wiring (cleona_service `_handleHolePunch...V3`)
  /// is owned by Subagent C4.
  void handleHolePunchRequest(
      proto.HolePunchRequest req, Uint8List requesterDeviceNodeId) {
    if (sendInfraFn == null) return;

    final requestIdHex = bytesToHex(Uint8List.fromList(req.requestId));
    final targetNodeId = Uint8List.fromList(req.targetNodeId);

    _log.info('Hole punch coordinator: ${bytesToHex(requesterDeviceNodeId).substring(0, 8)} '
        '→ ${bytesToHex(targetNodeId).substring(0, 8)} ($requestIdHex)');

    // Forward HOLE_PUNCH_NOTIFY to target via DV-cascade.
    final notify = proto.HolePunchNotify()
      ..requesterNodeId = requesterDeviceNodeId
      ..requesterIp = req.myPublicIp
      ..requesterPort = req.myPublicPort
      ..requestId = req.requestId;

    sendInfraFn!(
      proto.MessageTypeV3.MTV3_HOLE_PUNCH_NOTIFY,
      notify.writeToBuffer(),
      targetNodeId,
    );
  }

  /// Handle incoming HOLE_PUNCH_NOTIFY (someone wants to punch us).
  ///
  /// Send HOLE_PUNCH_PING to the requester's public IP.
  ///
  /// Welle 5.x V3 hard-cut: arguments now reflect the V3 receive-side
  /// shape — parsed [proto.HolePunchNotify] body plus the coordinator's
  /// deviceNodeId from the InfrastructureFrameV3 envelope.
  void handleHolePunchNotify(
      proto.HolePunchNotify notify, Uint8List coordinatorDeviceNodeId) {
    if (sendInfraDirectFn == null || ownNodeId == null) return;

    final requesterNodeId = Uint8List.fromList(notify.requesterNodeId);
    final requesterIp = notify.requesterIp;
    final requesterPort = notify.requesterPort;
    final requestId = Uint8List.fromList(notify.requestId);
    final requestIdHex = bytesToHex(requestId);

    _log.info('Hole punch notify: ${bytesToHex(requesterNodeId).substring(0, 8)} '
        'at $requesterIp:$requesterPort ($requestIdHex)');

    // Register session (we are the target side)
    final session = HolePunchSession(
      requestId: requestId,
      targetNodeId: requesterNodeId, // from our perspective, the requester is the "target"
      coordinatorNodeId: coordinatorDeviceNodeId,
      initiatedAt: DateTime.now(),
      remotePublicIp: requesterIp,
      remotePublicPort: requesterPort,
    );
    _activePunches[requestIdHex] = session;
    Timer(const Duration(seconds: 30), () => _activePunches.remove(requestIdHex));

    // Send HOLE_PUNCH_PING to requester's public IP (opens our NAT pinhole).
    // Recipient device ID is the requester (we know it from the notify).
    _sendHolePunchPing(requestId, requesterNodeId, requesterIp, requesterPort);
  }

  /// Handle incoming HOLE_PUNCH_PING — respond with PONG.
  ///
  /// Welle 5.x V3 hard-cut: arguments now reflect the V3 receive-side
  /// shape — parsed [proto.HolePunchPing] body plus the on-wire address
  /// from the UDP datagram (used as the PONG destination so the reply
  /// traverses the freshly-opened pinhole).
  void handleHolePunchPing(
      proto.HolePunchPing ping, InternetAddress from, int fromPort) {
    if (sendInfraDirectFn == null || ownNodeId == null) return;

    final requestIdHex = bytesToHex(Uint8List.fromList(ping.requestId));
    final senderNodeId = Uint8List.fromList(ping.senderNodeId);

    _log.debug('Hole punch PING from ${bytesToHex(senderNodeId).substring(0, 8)} '
        '($from:$fromPort, $requestIdHex)');

    // If we have an active session, also send our PING (both sides need to punch)
    final session = _activePunches[requestIdHex];
    if (session != null && session.remotePublicIp != null && !session.pingSent) {
      session.pingSent = true;
      _sendHolePunchPing(Uint8List.fromList(ping.requestId), senderNodeId,
          session.remotePublicIp!, session.remotePublicPort!);
    }

    // Send PONG back to the sender (via the punched pinhole) as a V3
    // InfrastructureFrame at the explicit on-wire address.
    final pong = proto.HolePunchPong()
      ..requestId = ping.requestId
      ..senderNodeId = ownNodeId!
      ..pingTimestampMs = ping.timestampMs;

    sendInfraDirectFn!(
      proto.MessageTypeV3.MTV3_HOLE_PUNCH_PONG,
      pong.writeToBuffer(),
      senderNodeId,
      from,
      fromPort,
    );
  }

  /// Handle incoming HOLE_PUNCH_PONG — hole punch successful!
  ///
  /// Welle 5.x V3 hard-cut: arguments now reflect the V3 receive-side
  /// shape — parsed [proto.HolePunchPong] body plus the on-wire address.
  void handleHolePunchPong(
      proto.HolePunchPong pong, InternetAddress from, int fromPort) {
    final requestIdHex = bytesToHex(Uint8List.fromList(pong.requestId));
    final senderNodeId = Uint8List.fromList(pong.senderNodeId);
    final senderHex = bytesToHex(senderNodeId);

    // Check if this is a keepalive/probing PONG for an established connection
    final existingConn = _punchedConnections[senderHex];
    if (existingConn != null && existingConn.pendingProbeRequestIdHex == requestIdHex) {
      // This is a keepalive/probing response — update connection and advance probing
      recordPong(senderNodeId, from, fromPort);
      return;
    }

    final session = _activePunches.remove(requestIdHex);
    if (session == null) {
      // Still check if it's a keepalive PONG by sender (requestId might have rotated)
      if (existingConn != null) {
        recordPong(senderNodeId, from, fromPort);
        return;
      }
      _log.debug('Hole punch PONG for unknown session $requestIdHex');
      return;
    }

    // Calculate RTT
    final now = DateTime.now().millisecondsSinceEpoch;
    final rtt = now - pong.pingTimestampMs.toInt();

    _log.info('Hole punch SUCCESS: ${senderHex.substring(0, 8)} '
        'at $from:$fromPort (RTT: ${rtt}ms)');

    // Record the punched connection
    final conn = PunchedConnection(
      peerNodeId: senderNodeId,
      peerIp: from.address,
      peerPort: fromPort,
      establishedAt: DateTime.now(),
      lastRtt: rtt,
    );
    _punchedConnections[senderHex] = conn;

    // Start NAT timeout probing (begins keepalive)
    _startNatTimeoutProbing(senderHex, conn);

    // Notify callback
    onHolePunchSuccess?.call(senderNodeId, from.address, fromPort);
  }

  /// Callback when a hole punch succeeds.
  void Function(Uint8List peerNodeId, String ip, int port)? onHolePunchSuccess;

  // ── NAT Timeout Probing ───────────────────────────────────────────────

  /// Probe the NAT timeout for a punched connection.
  ///
  /// Algorithm:
  /// 1. Start with 15s keepalive interval
  /// 2. Double: 15s → 30s → 60s → 90s → 120s
  /// 3. When PONG fails, use 80% of the last working interval
  /// 4. Persist per connection
  void _startNatTimeoutProbing(String peerHex, PunchedConnection conn) {
    // Cancel existing probing
    _keepaliveTimers[peerHex]?.cancel();

    // Start probing with intervals
    conn.probeIntervalIndex = 0;
    _scheduleNextProbe(peerHex, conn);
  }

  static const List<int> _probeIntervals = [15, 30, 60, 90, 120]; // seconds

  void _scheduleNextProbe(String peerHex, PunchedConnection conn) {
    if (conn.probeIntervalIndex >= _probeIntervals.length) {
      // All intervals tested — use the last successful one at 80%
      final keepaliveSeconds = (conn.lastSuccessfulInterval * 0.8).round();
      _startKeepalive(peerHex, conn, keepaliveSeconds);
      return;
    }

    final interval = _probeIntervals[conn.probeIntervalIndex];
    _keepaliveTimers[peerHex]?.cancel();
    _keepaliveTimers[peerHex] = Timer(Duration(seconds: interval), () {
      _sendKeepalivePing(peerHex, conn, interval);
    });
  }

  void _sendKeepalivePing(String peerHex, PunchedConnection conn, int intervalSec) {
    if (sendInfraDirectFn == null || ownNodeId == null) return;

    final requestId = _randomBytes(16);
    conn.lastPingTime = DateTime.now();

    final ping = proto.HolePunchPing()
      ..requestId = requestId
      ..senderNodeId = ownNodeId!
      ..timestampMs = Int64(conn.lastPingTime!.millisecondsSinceEpoch);

    try {
      sendInfraDirectFn!(
        proto.MessageTypeV3.MTV3_HOLE_PUNCH_PING,
        ping.writeToBuffer(),
        conn.peerNodeId,
        InternetAddress(conn.peerIp),
        conn.peerPort,
      );
    } catch (_) {}

    // Wait for PONG (timeout after 5 seconds)
    conn.pendingProbeRequestIdHex = bytesToHex(requestId);
    _keepaliveTimers['${peerHex}_probe'] = Timer(const Duration(seconds: 5), () {
      // Probe failed — this interval is too long
      _log.debug('NAT probe failed at ${intervalSec}s for ${peerHex.substring(0, 8)}');
      final keepaliveSeconds = (conn.lastSuccessfulInterval * 0.8).round();
      if (keepaliveSeconds > 0) {
        _startKeepalive(peerHex, conn, keepaliveSeconds);
      } else {
        // No interval worked — connection dead
        _removePunchedConnection(peerHex);
      }
    });
  }

  /// Called when a keepalive PONG is received during probing.
  void onKeepalivePong(String peerHex, PunchedConnection conn) {
    _keepaliveTimers['${peerHex}_probe']?.cancel();
    final interval = _probeIntervals[conn.probeIntervalIndex];
    conn.lastSuccessfulInterval = interval;
    conn.probeIntervalIndex++;
    conn.lastPongTime = DateTime.now();

    _log.debug('NAT probe OK at ${interval}s for ${peerHex.substring(0, 8)}');
    _scheduleNextProbe(peerHex, conn);
  }

  // ── Keepalive (Only Periodic Traffic in the System!) ──────────────────

  void _startKeepalive(String peerHex, PunchedConnection conn, int intervalSeconds) {
    _keepaliveTimers[peerHex]?.cancel();
    conn.keepaliveIntervalSec = intervalSeconds;

    _log.info('Keepalive started for ${peerHex.substring(0, 8)}: '
        'every ${intervalSeconds}s (NAT timeout: ${conn.lastSuccessfulInterval}s)');

    _keepaliveTimers[peerHex] = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (_) => _sendKeepalive(peerHex, conn),
    );
  }

  void _sendKeepalive(String peerHex, PunchedConnection conn) {
    if (sendInfraDirectFn == null || ownNodeId == null) return;

    final ping = proto.HolePunchPing()
      ..requestId = _randomBytes(16)
      ..senderNodeId = ownNodeId!
      ..timestampMs = Int64(DateTime.now().millisecondsSinceEpoch);

    try {
      sendInfraDirectFn!(
        proto.MessageTypeV3.MTV3_HOLE_PUNCH_PING,
        ping.writeToBuffer(),
        conn.peerNodeId,
        InternetAddress(conn.peerIp),
        conn.peerPort,
      );
    } catch (_) {}

    // Track consecutive failures
    conn.consecutiveKeepaliveFailures++;
    Timer(const Duration(seconds: 5), () {
      if (conn.consecutiveKeepaliveFailures > 3) {
        _log.info('Keepalive lost for ${peerHex.substring(0, 8)} — removing punched connection');
        _removePunchedConnection(peerHex);
      }
    });
  }

  /// Called when any PONG is received for a punched connection.
  void recordPong(Uint8List peerNodeId, InternetAddress from, int fromPort) {
    final peerHex = bytesToHex(peerNodeId);
    final conn = _punchedConnections[peerHex];
    if (conn == null) return;

    // Update connection
    conn.peerIp = from.address;
    conn.peerPort = fromPort;
    conn.lastPongTime = DateTime.now();
    conn.consecutiveKeepaliveFailures = 0;

    // If we are probing, advance to next interval
    if (conn.probeIntervalIndex < _probeIntervals.length) {
      onKeepalivePong(peerHex, conn);
    }
  }

  // ── Queries ───────────────────────────────────────────────────────────

  /// Get the punched connection to a peer, if any.
  PunchedConnection? getPunchedConnection(String peerHex) =>
      _punchedConnections[peerHex];

  /// Whether we have an active punched connection to a peer.
  bool hasPunchedConnection(String peerHex) =>
      _punchedConnections.containsKey(peerHex);

  /// All active punched connections.
  Map<String, PunchedConnection> get punchedConnections =>
      Map.unmodifiable(_punchedConnections);

  /// Whether a hole punch is in progress for a peer.
  bool isPunchInProgress(Uint8List targetNodeId) {
    final targetHex = bytesToHex(targetNodeId);
    return _activePunches.values.any((s) => s.targetHex == targetHex);
  }

  /// Public IP — prefers port-mapped address over STUN-observed.
  /// Only returns IPs where port reachability has been verified.
  String? get publicIp => _mappedPublicIp ?? _confirmedPublicIp;

  /// Public port — prefers port-mapped port over STUN-observed.
  int? get publicPort => _mappedPublicPort ?? _confirmedPublicPort;

  bool get hasPublicIp => _mappedPublicIp != null || _confirmedPublicIp != null;

  /// Public IPv6 — globally routable, no NAT (§27 DS-Lite/CGNAT bypass).
  String? _publicIpv6;
  String? get publicIpv6 => _publicIpv6;

  /// §4.7 IPv6 Inbound Probe: whether the self-announced global IPv6 address
  /// has been confirmed inbound-reachable via a CPRB echo from a peer.
  ///
  /// Three-state:
  ///   null  — no probe has been issued yet (address just set, probe pending)
  ///   true  — CPRB probe arrived inbound → address is fully bidirectional
  ///   false — probe timed out → carrier likely blocks inbound IPv6; address
  ///           is kept as an advertise-only relay hint but excluded from
  ///           Priority-3 Direct sends (see [currentSelfAddresses] in
  ///           cleona_node.dart).
  ///
  /// Reset to null on every [reset] so that a network-change re-probes.
  bool? _ipv6InboundVerified;

  /// Whether the global IPv6 has been confirmed inbound-reachable.
  /// Null = probe pending / not yet run. See [_ipv6InboundVerified].
  bool? get ipv6InboundVerified => _ipv6InboundVerified;

  /// Mark the IPv6 inbound probe as succeeded (CPRB arrived on IPv6 socket).
  void confirmIpv6InboundReachable() {
    if (_ipv6InboundVerified != true) {
      _ipv6InboundVerified = true;
      _log.info('IPv6 inbound confirmed: $_publicIpv6 is bidirectionally reachable');
    }
  }

  /// Mark the IPv6 inbound probe as timed out (carrier likely blocks IPv6 in).
  /// The address is kept for relay-hint advertising but removed from Direct.
  void markIpv6InboundUnreachable() {
    if (_ipv6InboundVerified != false) {
      _ipv6InboundVerified = false;
      _log.info('IPv6 inbound TIMEOUT: $_publicIpv6 may not be inbound-reachable '
          '(carrier filter?) — keeping as relay hint only');
    }
  }

  /// Set public IPv6 address (from ipify or interface enumeration).
  /// Resets the inbound-verified flag so [CleonaNode._probeIpv6Inbound]
  /// issues a fresh probe for the new address.
  void setPublicIpv6(String ip) {
    if (_publicIpv6 != ip) {
      _publicIpv6 = ip;
      _ipv6InboundVerified = null; // arm a fresh probe
      _log.info('Public IPv6 set: $ip — inbound probe pending');
    }
  }

  /// External IP including unverified (no port mapping).
  /// Use for NAT context (same-NAT detection), NOT for advertising to peers.
  String? get publicIpForNatContext => publicIp ?? _externalIpOnly;

  /// Whether we have a port mapping (NAT-PMP/PCP/UPnP).
  bool get hasPortMapping => _hasPortMapping;

  // ── NAT-Wizard signal getters/setters (§27.9.1) ────────────────────
  // Strings to avoid importing network_stats.dart (circular). NetworkStats
  // translates these back to its UpnpStatus/PcpStatus enums.

  /// Current UPnP status as enum-name (unknown|ok|unavailable|rejected).
  String get upnpStatusName => _upnpStatus;

  /// Current PCP status as enum-name (unknown|ok|failed).
  String get pcpStatusName => _pcpStatus;

  /// Parsed UPnP rootDesc (manufacturer/modelName/modelNumber/friendlyName)
  /// as JSON map. Null if UPnP yielded nothing.
  Map<String, dynamic>? get upnpRouterInfoJson => _upnpRouterInfoJson;

  /// Set by PortMapper/UPnP layer. `status` MUST be one of unknown|ok|unavailable|rejected.
  void setUpnpStatus(String status) {
    const valid = {'unknown', 'ok', 'unavailable', 'rejected'};
    if (!valid.contains(status)) return;
    _upnpStatus = status;
  }

  /// Set by PortMapper/PCP layer. `status` MUST be one of unknown|ok|failed.
  void setPcpStatus(String status) {
    const valid = {'unknown', 'ok', 'failed'};
    if (!valid.contains(status)) return;
    _pcpStatus = status;
  }

  /// Set by UPnP layer when rootDesc.xml was parsed successfully.
  /// Pass null to clear (e.g. on UPnP unavailable).
  void setUpnpRouterInfoJson(Map<String, dynamic>? json) {
    _upnpRouterInfoJson = json;
  }

  /// Store external IP without port verification (ipify, UPnP GetExternalIP).
  /// Only used for NAT context — NOT advertised as reachable address.
  void setExternalIpOnly(String ip) {
    if (PeerAddress.isPrivateIp(ip)) return;
    if (_externalIpOnly != ip) {
      _externalIpOnly = ip;
      _log.info('External IP known (no port mapping): $ip — NAT context only');
    }
  }

  /// Directly confirm a public IP address (e.g. from ipify or external probe).
  /// Bypasses the multi-peer confirmation requirement of reportObservedAddress.
  void confirmPublicAddress(String ip, int port) {
    if (PeerAddress.isPrivateIp(ip)) {
      _log.warn('confirmPublicAddress called with private IP $ip — ignoring');
      return;
    }
    if (_confirmedPublicIp != ip || _confirmedPublicPort != port) {
      _log.info('Public address confirmed externally: $ip:$port');
      _confirmedPublicIp = ip;
      _confirmedPublicPort = port;
      _classifyNat();
    }
  }

  /// Set a port mapping acquired by PortMapper.
  /// Overrides STUN-observed public address. Sets natType to fullCone
  /// (port-mapped address is always directly reachable).
  void setPortMapping(String ip, int port) {
    if (PeerAddress.isPrivateIp(ip)) {
      _log.warn('setPortMapping called with private IP $ip — ignoring');
      return;
    }
    _mappedPublicIp = ip;
    _mappedPublicPort = port;
    _hasPortMapping = true;
    natType = NatClassification.fullCone;
    _log.info('Port mapping set: $ip:$port (fullCone)');
  }

  /// Clear port mapping state. Falls back to STUN-observed address.
  void clearPortMapping() {
    _mappedPublicIp = null;
    _mappedPublicPort = null;
    _hasPortMapping = false;
    _classifyNat();
    _log.info('Port mapping cleared — falling back to STUN');
  }

  // ── Gateway Keepalive (CGNAT without Hole Punch) ───────────────────

  /// Register a gateway connection for NAT keepalive when behind CGNAT.
  /// Called when we receive a PONG from a public-IP peer while on CGNAT.
  /// Reuses the existing NAT-Timeout-Probing + Keepalive infrastructure
  /// without requiring a coordinated Hole Punch.
  void registerGatewayConnection(Uint8List peerNodeId, String peerIp, int peerPort) {
    final peerHex = bytesToHex(peerNodeId);
    if (_punchedConnections.containsKey(peerHex)) return; // Already tracked

    _log.info('Gateway keepalive registered for ${peerHex.substring(0, 8)} '
        'at $peerIp:$peerPort (CGNAT → NAT-Timeout-Probing)');

    final conn = PunchedConnection(
      peerNodeId: peerNodeId,
      peerIp: peerIp,
      peerPort: peerPort,
      establishedAt: DateTime.now(),
      lastRtt: 0,
    );
    _punchedConnections[peerHex] = conn;
    _startNatTimeoutProbing(peerHex, conn);
  }

  // ── Cleanup ───────────────────────────────────────────────────────────

  void _removePunchedConnection(String peerHex) {
    _punchedConnections.remove(peerHex);
    _keepaliveTimers[peerHex]?.cancel();
    _keepaliveTimers.remove(peerHex);
    _keepaliveTimers['${peerHex}_probe']?.cancel();
    _keepaliveTimers.remove('${peerHex}_probe');
  }

  /// Reset all state (network change).
  void reset() {
    _observations.clear();
    _confirmedPublicIp = null;
    _confirmedPublicPort = null;
    _mappedPublicIp = null;
    _mappedPublicPort = null;
    _hasPortMapping = false;
    _externalIpOnly = null;
    _publicIpv6 = null;
    _ipv6InboundVerified = null;
    natType = NatClassification.unknown;

    for (final timer in _keepaliveTimers.values) {
      timer.cancel();
    }
    _keepaliveTimers.clear();
    _activePunches.clear();
    _punchedConnections.clear();

    _log.info('NAT state reset');
  }

  /// Stop all timers.
  void dispose() {
    for (final timer in _keepaliveTimers.values) {
      timer.cancel();
    }
    _keepaliveTimers.clear();
  }

  // ── Internal Helpers ──────────────────────────────────────────────────

  /// Send HOLE_PUNCH_PING to a known on-wire address — opens our local
  /// pinhole + (with ±10 port-prediction) targets sequential symmetric-NAT
  /// allocations. `peerDeviceNodeId` from the caller
  /// (handleHolePunchNotify / handleHolePunchPing) is wired into the
  /// InfrastructureFrameV3 recipient field so the KEM-AEAD derivation
  /// lines up.
  void _sendHolePunchPing(
      Uint8List requestId, Uint8List peerDeviceNodeId, String ip, int port) {
    if (sendInfraDirectFn == null || ownNodeId == null) return;

    final ping = proto.HolePunchPing()
      ..requestId = requestId
      ..senderNodeId = ownNodeId!
      ..timestampMs = Int64(DateTime.now().millisecondsSinceEpoch);

    final body = ping.writeToBuffer();
    final addr = InternetAddress(ip);

    // Send to the exact reported port
    try {
      sendInfraDirectFn!(proto.MessageTypeV3.MTV3_HOLE_PUNCH_PING, body,
          peerDeviceNodeId, addr, port);
    } catch (e) {
      _log.debug('Hole punch PING send error to $ip:$port: $e');
    }

    // §27 Port-Prediction: Symmetric NATs often allocate ports sequentially.
    // Send additional PINGs to neighboring ports (±1..±10) to increase the
    // chance of hitting the actual NATted port. Low cost (10 extra UDP packets),
    // high payoff if the carrier NAT uses sequential allocation.
    for (var delta = 1; delta <= 10; delta++) {
      final above = port + delta;
      final below = port - delta;
      if (above > 0 && above <= 65535) {
        try {
          sendInfraDirectFn!(proto.MessageTypeV3.MTV3_HOLE_PUNCH_PING, body,
              peerDeviceNodeId, addr, above);
        } catch (_) {}
      }
      if (below > 0 && below <= 65535) {
        try {
          sendInfraDirectFn!(proto.MessageTypeV3.MTV3_HOLE_PUNCH_PING, body,
              peerDeviceNodeId, addr, below);
        } catch (_) {}
      }
    }
    _log.debug('Hole punch PING sent to $ip:$port (+ ±10 port prediction)');
  }

  /// CSPRNG-backed random bytes for hole-punch requestIds.
  ///
  /// Security C-3: Previously used `DateTime.now().microsecondsSinceEpoch` as
  /// sole entropy source, making requestIds predictable to an attacker who
  /// could observe or estimate the sender's clock. Now uses `Random.secure()`
  /// (OS CSPRNG: getrandom/CryptGenRandom/SecRandomCopyBytes).
  static final Random _secureRng = Random.secure();
  static Uint8List _randomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _secureRng.nextInt(256);
    }
    return bytes;
  }
}

// ── Data Classes ────────────────────────────────────────────────────────

/// An active hole punch session (in progress, not yet established).
class HolePunchSession {
  final Uint8List requestId;
  final Uint8List targetNodeId;
  final Uint8List coordinatorNodeId;
  final DateTime initiatedAt;
  String? remotePublicIp;
  int? remotePublicPort;
  bool pingSent = false;

  String get requestIdHex => bytesToHex(requestId);
  String get targetHex => bytesToHex(targetNodeId);

  HolePunchSession({
    required this.requestId,
    required this.targetNodeId,
    required this.coordinatorNodeId,
    required this.initiatedAt,
    this.remotePublicIp,
    this.remotePublicPort,
  });
}

/// An established punched connection.
class PunchedConnection {
  final Uint8List peerNodeId;
  String peerIp;
  int peerPort;
  final DateTime establishedAt;
  int lastRtt; // ms

  /// NAT timeout probing state.
  int probeIntervalIndex = 0;
  int lastSuccessfulInterval = 15; // seconds, default to minimum
  DateTime? lastPingTime;
  DateTime? lastPongTime;
  String? pendingProbeRequestIdHex;
  int keepaliveIntervalSec = 12; // Default: 80% of 15s
  int consecutiveKeepaliveFailures = 0;

  String get peerHex => bytesToHex(peerNodeId);

  PunchedConnection({
    required this.peerNodeId,
    required this.peerIp,
    required this.peerPort,
    required this.establishedAt,
    this.lastRtt = 0,
  });
}
