import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/crypto/network_secret.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/udp_fragmenter.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Magic bytes for LAN discovery packets: "CLEO" (0x43 0x4C 0x45 0x4F)
const List<int> cleoMagic = [0x43, 0x4C, 0x45, 0x4F];

/// Magic bytes for port probe: "CPRB" (Cleona Port Probe)
/// Packet format: [4B "CPRB"][16B probe_id] = 20 bytes payload (28 on wire with HMAC)
const List<int> cprbMagic = [0x43, 0x50, 0x52, 0x42];
const int cprbPacketSize = 20; // 4 magic + 16 probe_id

/// CLEO discovery packet size: 8B HMAC + 4B magic + 32B nodeId + 2B port = 46 bytes.
const int cleoPacketSize = 46;

/// Callback for received envelopes.
typedef EnvelopeCallback = void Function(
  proto.MessageEnvelope envelope,
  InternetAddress remoteAddress,
  int remotePort, {
  bool isUdp,
});

/// Callback for raw discovery packets.
typedef DiscoveryCallback = void Function(
  Uint8List nodeId,
  int port,
  InternetAddress remoteAddress,
  int remotePort,
);

/// UDP + TLS transport layer. Single UDP port for all traffic, TLS on port+2 as anti-censorship fallback.
///
/// Protocol escalation (V3.1.7): Start with lightest protocol, escalate only on failure.
/// UDP (single packet) → UDP (fragmented + NACK retry) → TLS (TCP, last resort).
/// Sticky: once a protocol works for a peer, keep using it until network change.
class Transport {
  int port;
  final CLogger _log;
  final String? _profileDir;
  RawDatagramSocket? _udpSocket;
  RawDatagramSocket? _udpSocket6; // IPv6 dual-stack (§27 IPv6 Transport)
  RawDatagramSocket? _udpSocketMobile; // Mobile fallback (§27 WiFi-dead detection)
  String? _mobileFallbackIp; // The local IP the mobile socket is bound to
  SecureServerSocket? _tlsServer;
  SecureServerSocket? _tlsServer6; // IPv6 TLS (§27)
  Timer? _tlsRebindTimer;
  int _tlsRebindAttempt = 0;
  /// Set when TLS context cannot be obtained (missing openssl, no profile
  /// dir, etc.). Permanent failure — disables rebind retry to avoid log spam
  /// on platforms without openssl (Android).
  bool _tlsContextUnavailable = false;
  final FragmentReassembler _reassembler = FragmentReassembler();

  /// Cache of recently sent fragments for NACK-based resend.
  /// Key: "destIp:fragmentId", Value: list of fragment packets.
  /// Auto-expires after 30 seconds.
  final Map<String, List<Uint8List>> _sentFragmentCache = {};

  EnvelopeCallback? onEnvelope;
  DiscoveryCallback? onDiscovery;
  /// Callback when a CPRB port probe packet arrives: (probeId, fromAddress, fromPort).
  void Function(Uint8List probeId, InternetAddress from, int fromPort)? onPortProbe;
  void Function(int bytes)? onBytesSent;
  void Function(int bytes)? onBytesReceived;

  Transport({required this.port, String? profileDir})
      : _profileDir = profileDir,
        _log = CLogger.get('transport', profileDir: profileDir);

  /// Start listening on UDP and TLS (anti-censorship fallback on port+2).
  Future<void> start() async {
    // UDP — primary transport for all traffic
    _udpSocket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
    );
    _udpSocket!.broadcastEnabled = true;
    _udpSocket!.readEventsEnabled = true;
    // Increase receive buffer to prevent drops under load (relay nodes).
    // Default 208KB is too small for bursty relay traffic with fragmentation.
    try {
      final size = 2 * 1024 * 1024; // 2 MB
      final sizeBytes = Uint8List(4)..buffer.asByteData().setInt32(0, size, Endian.host);
      // SOL_SOCKET=1, SO_RCVBUF=8 (Linux)
      _udpSocket!.setRawOption(RawSocketOption(1, 8, sizeBytes));
      _log.info('UDP receive buffer set to 2MB');
    } catch (e) {
      _log.debug('Could not set UDP receive buffer: $e');
    }
    _udpSocket!.listen(
      _onUdpEvent,
      onError: (e) => _log.warn('UDP socket error: $e'),
    );
    _log.info('UDP listening on port $port');

    // IPv6 socket — dual-stack transport for DS-Lite/CGNAT (§27)
    try {
      _udpSocket6 = await RawDatagramSocket.bind(
        InternetAddress.anyIPv6,
        port,
      );
      _udpSocket6!.readEventsEnabled = true;
      try {
        final size = 2 * 1024 * 1024; // 2 MB
        final sizeBytes = Uint8List(4)..buffer.asByteData().setInt32(0, size, Endian.host);
        _udpSocket6!.setRawOption(RawSocketOption(1, 8, sizeBytes));
      } catch (_) {}
      _udpSocket6!.listen(
        _onUdpEvent6,
        onError: (e) => _log.warn('UDP6 socket error: $e'),
      );
      _log.info('UDP6 listening on port $port');
    } catch (e) {
      _log.info('IPv6 socket not available: $e');
      _udpSocket6 = null;
    }

    // Wire fragment reassembler logging
    _reassembler.onLog = (msg) => _log.debug(msg);

    // Wire fragment NACK callback — sends HMAC-wrapped NACK packets to sender
    _reassembler.onNack = (sourceIp, sourcePort, fragmentId, missing) {
      final nackPacket = UdpFragmenter.buildNack(fragmentId, missing);
      final wrapped = NetworkSecret.wrapPacket(nackPacket);
      try {
        final addr = InternetAddress(sourceIp);
        _socketFor(addr)?.send(wrapped, addr, sourcePort);
        _log.debug('Fragment NACK sent: id=$fragmentId missing=${missing.length} to $sourceIp:$sourcePort');
      } catch (_) {}
    };

    // TLS on port+2 (anti-censorship fallback, activates after 15 consecutive UDP failures)
    await _tryBindTlsListeners();
    if (_tlsServer == null || _tlsServer6 == null) {
      _scheduleTlsRebind();
    }
  }

  /// Try to bind TLS IPv4 and IPv6 listeners. Returns whether IPv4 is bound.
  /// Safe to call repeatedly — skips already-bound sockets.
  Future<bool> _tryBindTlsListeners() async {
    final ctx = await _getOrCreateTlsContext();
    if (ctx == null) {
      _tlsContextUnavailable = true;
      return false;
    }
    if (_tlsServer == null) {
      try {
        _tlsServer = await SecureServerSocket.bind(InternetAddress.anyIPv4, port + 2, ctx);
        _tlsServer!.listen(_onTlsConnection);
        _log.info('TLS listening on port ${port + 2}');
      } catch (e) {
        _log.info('TLS listener not available (port ${port + 2}): $e');
      }
    }
    if (_tlsServer6 == null) {
      try {
        _tlsServer6 = await SecureServerSocket.bind(InternetAddress.anyIPv6, port + 2, ctx, v6Only: true);
        _tlsServer6!.listen(_onTlsConnection);
        _log.info('TLS6 listening on port ${port + 2}');
      } catch (e) {
        _log.info('TLS6 listener not available (port ${port + 2}): $e');
      }
    }
    return _tlsServer != null;
  }

  /// Schedule a rebind attempt with backoff (5s → 10s → 30s → 60s cap).
  /// Recovers from transient bind failures (port in TIME_WAIT after restart).
  void _scheduleTlsRebind() {
    if (_tlsRebindTimer != null) return;
    if (_tlsServer != null && _tlsServer6 != null) return;
    if (_tlsContextUnavailable) return; // permanent — openssl missing, no profile dir
    const backoffSec = [5, 10, 30, 60];
    final delay = backoffSec[_tlsRebindAttempt.clamp(0, backoffSec.length - 1)];
    _log.info('TLS rebind scheduled in ${delay}s (attempt ${_tlsRebindAttempt + 1})');
    _tlsRebindTimer = Timer(Duration(seconds: delay), () async {
      _tlsRebindTimer = null;
      _tlsRebindAttempt++;
      await _tryBindTlsListeners();
      if (_tlsServer == null || _tlsServer6 == null) {
        _scheduleTlsRebind();
      } else {
        _tlsRebindAttempt = 0;
      }
    });
  }

  /// Select the correct UDP socket for an address (IPv4 vs IPv6).
  /// When mobile fallback is active, non-LAN IPv4 destinations use the mobile socket
  /// to bypass broken WiFi (captive portals, dead NAT, etc.).
  RawDatagramSocket? _socketFor(InternetAddress addr) {
    if (addr.type == InternetAddressType.IPv6) {
      return _udpSocket6 ?? _udpSocket;
    }
    // Mobile fallback: use mobile-bound socket for non-LAN destinations
    if (_udpSocketMobile != null && !_isPrivateIpAddr(addr.address)) {
      return _udpSocketMobile!;
    }
    return _udpSocket;
  }

  void _onUdpEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    for (;;) {
      final datagram = _udpSocket?.receive();
      if (datagram == null) break;
      // WiFi recovery: packet arrived on main socket → WiFi works again
      if (_udpSocketMobile != null) {
        _log.info('WiFi recovered — deactivating mobile fallback');
        stopMobileFallback();
      }
      _processUdpDatagram(datagram);
    }
  }

  void _onUdpEvent6(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    for (;;) {
      final datagram = _udpSocket6?.receive();
      if (datagram == null) break;
      _processUdpDatagram(datagram);
    }
  }

  void _processUdpDatagram(Datagram datagram) {
    final data = datagram.data;

    // --- HMAC verification (Architecture 17.5.4) ---
    // Every UDP packet is prefixed with 8-byte HMAC. Invalid HMAC → silent drop
    // before any further processing (no protobuf parsing, no DHT lookup, no error response).
    final payload = NetworkSecret.unwrapPacket(Uint8List.fromList(data));
    if (payload == null) {
      // Silent drop — invalid HMAC or too short. No error response to prevent
      // revealing our existence to forked/scanning nodes.
      return;
    }

    // Check for CLEO discovery packet (38 bytes: 4 magic + 32 nodeId + 2 port)
    if (payload.length == 38 &&
        payload[0] == cleoMagic[0] &&
        payload[1] == cleoMagic[1] &&
        payload[2] == cleoMagic[2] &&
        payload[3] == cleoMagic[3]) {
      final nodeId = Uint8List.fromList(payload.sublist(4, 36));
      final discPort = (payload[36] << 8) | payload[37];
      onDiscovery?.call(
        nodeId,
        discPort,
        datagram.address,
        datagram.port,
      );
      return;
    }

    // Check for port probe (CPRB magic) — verify public port reachability
    if (payload.length == cprbPacketSize &&
        payload[0] == cprbMagic[0] &&
        payload[1] == cprbMagic[1] &&
        payload[2] == cprbMagic[2] &&
        payload[3] == cprbMagic[3]) {
      final probeId = Uint8List.fromList(payload.sublist(4, 20));
      onPortProbe?.call(probeId, datagram.address, datagram.port);
      return;
    }

    // Check for fragment NACK (CFNK magic) — resend missing fragments
    if (UdpFragmenter.isFragmentNack(payload)) {
      final nack = UdpFragmenter.parseNack(payload);
      if (nack != null) {
        _handleFragmentNack(nack.fragmentId, nack.missing, datagram.address, datagram.port);
      }
      return;
    }

    // Check for fragment (CFRA magic)
    if (UdpFragmenter.isFragment(payload)) {
      onBytesReceived?.call(payload.length);
      final reassembled = _reassembler.addFragment(
        payload,
        datagram.address.address,
        datagram.port,
      );
      if (reassembled != null) {
        // All fragments received — parse the reassembled protobuf
        try {
          final envelope = proto.MessageEnvelope.fromBuffer(reassembled);
          onEnvelope?.call(envelope, datagram.address, datagram.port, isUdp: true);
        } catch (e) {
          _log.debug('Fragment reassembly parse error from '
              '${datagram.address}:${datagram.port}: $e');
        }
      }
      return;
    }

    // Protobuf message (non-fragmented)
    try {
      onBytesReceived?.call(payload.length);
      final envelope = proto.MessageEnvelope.fromBuffer(payload);
      onEnvelope?.call(envelope, datagram.address, datagram.port, isUdp: true);
    } catch (e) {
      _log.debug('UDP parse error from ${datagram.address}:${datagram.port}: $e');
    }
  }

  /// Send a protobuf envelope via UDP to a specific address.
  /// For payloads >1200 bytes, automatically fragments the data.
  Future<bool> sendUdp(
    proto.MessageEnvelope envelope,
    InternetAddress address,
    int remotePort,
  ) async {
    // Transport invariant: 0.0.0.0 / :: are never valid destinations.
    // Sending to them causes EINVAL which kills the Dart UDP socket.
    if (address.address == '0.0.0.0' || address.address == '::' || remotePort <= 0) {
      _log.warn('sendUdp: rejected invalid destination ${address.address}:$remotePort');
      return false;
    }
    final socket = _socketFor(address);
    if (socket == null) {
      _log.debug('sendUdp: no ${address.type == InternetAddressType.IPv6 ? "IPv6" : "IPv4"} socket for ${address.address}');
      return false;
    }
    try {
      final data = envelope.writeToBuffer();

      // Fragment if payload exceeds UDP-safe size
      if (data.length > maxFragmentPacketSize) {
        final fragments = UdpFragmenter.fragment(Uint8List.fromList(data));
        var anySent = false;
        // HMAC-wrap each fragment individually (Architecture 17.5.4)
        final wrappedFragments = <Uint8List>[];
        for (final frag in fragments) {
          final wrapped = NetworkSecret.wrapPacket(frag);
          wrappedFragments.add(wrapped);
          final sent = socket.send(wrapped, address, remotePort);
          if (sent > 0) anySent = true;
        }
        if (anySent) {
          onBytesSent?.call(data.length);
          final header = UdpFragmenter.parseHeader(fragments.first);
          if (header != null) {
            final cacheKey = '${address.address}:${header.fragmentId}';
            _sentFragmentCache[cacheKey] = wrappedFragments;
            Timer(const Duration(seconds: 30), () => _sentFragmentCache.remove(cacheKey));
          }
        }
        return anySent;
      }

      // HMAC-wrap non-fragmented packet (Architecture 17.5.4)
      final wrapped = NetworkSecret.wrapPacket(Uint8List.fromList(data));
      final sent = socket.send(wrapped, address, remotePort);
      if (sent > 0) {
        onBytesSent?.call(data.length);
        return true;
      }
      return false;
    } catch (e) {
      _log.debug('UDP send error to ${address.address}:$remotePort: $e');
      return false;
    }
  }

  /// Handle NACK: resend missing fragments from cache.
  void _handleFragmentNack(int fragmentId, List<int> missing, InternetAddress from, int fromPort) {
    // The NACK comes FROM the receiver — look up cache by receiver's address
    // We stored with dest=receiver, so the key matches.
    final cacheKey = '${from.address}:$fragmentId';
    final cached = _sentFragmentCache[cacheKey];
    if (cached == null) {
      _log.debug('Fragment NACK: no cache for id=$fragmentId from ${from.address}:$fromPort');
      return;
    }

    final socket = _socketFor(from);
    var resent = 0;
    for (final idx in missing) {
      if (idx >= 0 && idx < cached.length) {
        try {
          final sent = socket?.send(cached[idx], from, fromPort);
          if (sent != null && sent > 0) resent++;
        } catch (_) {}
      }
    }
    _log.debug('Fragment NACK resend: id=$fragmentId resent=$resent/${missing.length} to ${from.address}:$fromPort');
  }

  /// Send a CPRB port probe packet to a target address.
  /// Used to verify if a peer's public port is reachable.
  Future<bool> sendPortProbe(
    Uint8List probeId,
    InternetAddress address,
    int remotePort,
  ) async {
    if (probeId.length != 16) return false;
    if (address.address == '0.0.0.0' || address.address == '::' || remotePort <= 0) return false;
    final socket = _socketFor(address);
    if (socket == null) return false;
    final packet = Uint8List(cprbPacketSize);
    packet[0] = cprbMagic[0];
    packet[1] = cprbMagic[1];
    packet[2] = cprbMagic[2];
    packet[3] = cprbMagic[3];
    packet.setRange(4, 20, probeId);
    final wrapped = NetworkSecret.wrapPacket(packet);
    try {
      final sent = socket.send(wrapped, address, remotePort);
      if (sent > 0) {
        _log.debug('Port probe sent to ${address.address}:$remotePort');
        return true;
      }
    } catch (e) {
      _log.debug('Port probe send error: $e');
    }
    return false;
  }

  /// Send raw bytes via UDP (for discovery packets).
  /// Data is HMAC-wrapped before sending (Architecture 17.5.4).
  Future<bool> sendUdpRaw(
    Uint8List data,
    InternetAddress address,
    int remotePort,
  ) async {
    try {
      final socket = _socketFor(address);
      if (socket == null) return false;
      final wrapped = NetworkSecret.wrapPacket(data);
      final sent = socket.send(wrapped, address, remotePort);
      if (sent > 0) {
        onBytesSent?.call(data.length);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Handle incoming TLS connection (anti-censorship fallback).
  void _onTlsConnection(Socket client) {
    final key = '${client.remoteAddress.address}:${client.remotePort}';
    _log.debug('TLS connection from $key');

    final buffer = BytesBuilder();
    client.listen(
      (data) {
        onBytesReceived?.call(data.length);
        buffer.add(data);
        _tryParseTlsBuffer(buffer, client);
      },
      onDone: () => client.destroy(),
      onError: (e) {
        _log.debug('TLS error from $key: $e');
        client.destroy();
      },
    );
  }

  void _tryParseTlsBuffer(BytesBuilder buffer, Socket client) {
    while (true) {
      final bytes = buffer.toBytes();
      if (bytes.length < 4) return;
      final len = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
      if (len <= 0 || len > 10 * 1024 * 1024) {
        buffer.clear();
        return;
      }
      if (bytes.length < 4 + len) return;

      try {
        final msgBytes = bytes.sublist(4, 4 + len);
        final envelope = proto.MessageEnvelope.fromBuffer(msgBytes);
        onEnvelope?.call(envelope, client.remoteAddress, client.remotePort);
      } catch (e) {
        _log.debug('TLS parse error: $e');
      }

      final remaining = bytes.sublist(4 + len);
      buffer.clear();
      if (remaining.isNotEmpty) {
        buffer.add(remaining);
      } else {
        return;
      }
    }
  }

  /// Send an envelope via TLS (port+2). Anti-censorship fallback when UDP is blocked.
  Future<bool> sendTls(
    proto.MessageEnvelope envelope,
    InternetAddress address,
    int remotePort, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      final data = envelope.writeToBuffer();
      final lenPrefix = Uint8List(4);
      lenPrefix[0] = (data.length >> 24) & 0xFF;
      lenPrefix[1] = (data.length >> 16) & 0xFF;
      lenPrefix[2] = (data.length >> 8) & 0xFF;
      lenPrefix[3] = data.length & 0xFF;

      // Connect TLS on port+2, accept self-signed certs (verified via Cleona signatures)
      final socket = await SecureSocket.connect(
        address,
        remotePort + 2,
        timeout: timeout,
        onBadCertificate: (_) => true,
      );
      socket.add(lenPrefix);
      socket.add(data);
      await socket.flush();
      await socket.close();
      onBytesSent?.call(data.length + 4);
      return true;
    } catch (e) {
      _log.debug('TLS send error to ${address.address}:${remotePort + 2}: $e');
      return false;
    }
  }

  /// Get or create self-signed TLS certificate for the listener.
  /// Returns null on any failure (missing openssl, bad cert, no profile dir).
  Future<SecurityContext?> _getOrCreateTlsContext() async {
    if (_profileDir == null) return null;
    final certPath = '$_profileDir/tls_cert.pem';
    final keyPath = '$_profileDir/tls_key.pem';

    if (!File(certPath).existsSync() || !File(keyPath).existsSync()) {
      try {
        final result = await Process.run('openssl', [
          'req', '-x509', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:prime256v1',
          '-keyout', keyPath, '-out', certPath,
          '-days', '3650', '-nodes',
          '-subj', '/CN=cleona-node',
        ]);
        if (result.exitCode != 0) {
          _log.info('openssl cert generation failed: ${result.stderr}');
          return null;
        }
      } catch (e) {
        // ProcessException when openssl binary is missing (e.g. Android).
        _log.info('openssl not available: $e');
        return null;
      }
    }

    try {
      return SecurityContext()
        ..useCertificateChain(certPath)
        ..usePrivateKey(keyPath);
    } catch (e) {
      _log.info('TLS context creation failed: $e');
      return null;
    }
  }

  /// Send envelope to all given addresses in parallel (UDP only).
  /// Total operation is capped at 5 seconds to prevent cascade timeouts.
  Future<bool> sendToAll(
    proto.MessageEnvelope envelope,
    List<({InternetAddress address, int port})> targets,
  ) async {
    if (targets.isEmpty) return false;

    final futures = <Future<bool>>[];
    for (final target in targets) {
      futures.add(sendUdp(envelope, target.address, target.port));
    }

    // Cap total wait to 5 seconds — prevents cascade when multiple peers unreachable
    final results = await Future.wait(futures).timeout(
      const Duration(seconds: 5),
      onTimeout: () => futures.map((_) => false).toList(),
    );
    return results.any((r) => r);
  }

  /// Build a CLEO discovery packet (38 bytes payload, becomes 46 on wire with HMAC prefix).
  static Uint8List buildDiscoveryPacket(Uint8List nodeId, int port) {
    assert(nodeId.length == 32);
    final packet = Uint8List(38);
    packet[0] = cleoMagic[0];
    packet[1] = cleoMagic[1];
    packet[2] = cleoMagic[2];
    packet[3] = cleoMagic[3];
    packet.setRange(4, 36, nodeId);
    packet[36] = (port >> 8) & 0xFF;
    packet[37] = port & 0xFF;
    return packet;
  }

  /// Get the local IP address (non-loopback, non-0.0.0.0).
  /// Prefers private/WiFi IPs over carrier/public IPs.
  static Future<String> getLocalIp() async {
    final ips = await getAllLocalIps();
    return ips.isNotEmpty ? ips.first : '127.0.0.1';
  }

  /// Get ALL local addresses (non-loopback).
  /// Sorted: private IPv4 first (LAN), then public IPv4, then global IPv6.
  /// This ensures WiFi/LAN interfaces are preferred over mobile data.
  static Future<List<String>> getAllLocalIps() async {
    final interfaces4 = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    final privateIps = <String>[];
    final publicIps = <String>[];

    for (final iface in interfaces4) {
      for (final addr in iface.addresses) {
        if (addr.isLoopback || addr.address == '0.0.0.0') continue;
        final ip = addr.address;
        if (_isPrivateIpAddr(ip)) {
          privateIps.add(ip);
        } else {
          publicIps.add(ip);
        }
      }
    }

    // IPv6: only global addresses (skip loopback ::1 and link-local fe80::)
    final ipv6Global = <String>[];
    try {
      final interfaces6 = await NetworkInterface.list(
        type: InternetAddressType.IPv6,
      );
      for (final iface in interfaces6) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback || addr.isLinkLocal) continue;
          ipv6Global.add(addr.address);
        }
      }
    } catch (_) {
      // IPv6 enumeration not available on this platform
    }

    return [...privateIps, ...publicIps, ...ipv6Global];
  }

  static bool _isPrivateIpAddr(String ip) {
    if (ip.contains(':')) {
      // IPv6: link-local and ULA are private
      final lower = ip.toLowerCase();
      return lower.startsWith('fe80:') || lower.startsWith('fc') ||
             lower.startsWith('fd') || lower == '::1';
    }
    if (ip.startsWith('192.168.')) return true;
    if (ip.startsWith('10.')) return true;
    if (ip.startsWith('172.')) {
      final second = int.tryParse(ip.split('.')[1]);
      if (second != null && second >= 16 && second <= 31) return true;
    }
    // CGNAT ranges — not routable from the internet
    if (ip.startsWith('100.')) {
      final second = int.tryParse(ip.split('.')[1]) ?? 0;
      if (second >= 64 && second <= 127) return true; // 100.64.0.0/10
    }
    if (ip.startsWith('192.0.0.')) return true; // IETF reserved / DS-Lite
    return false;
  }

  // ── Mobile Fallback Socket (§27 WiFi-dead detection) ───────────────
  //
  // When WiFi is connected but broken (captive portal, firewall, dead NAT),
  // all UDP traffic goes into the void because the OS routes through WiFi.
  // Mobile data would work but the OS ignores it.
  //
  // Solution: bind a second UDP socket to the mobile interface IP. Packets
  // sent through this socket are forced through the mobile interface because
  // the source IP is bound to it. Auto-deactivates when WiFi recovers
  // (packet arrives on main socket).

  /// Probe a specific local IP by sending a raw PING-like packet to a target.
  /// Returns true if the socket.send() succeeds (packet left the interface).
  /// Does NOT wait for a response — the caller checks for confirmed peers later.
  Future<bool> probeViaInterface(String localIp, InternetAddress dest, int destPort, Uint8List pingData) async {
    RawDatagramSocket? probe;
    try {
      probe = await RawDatagramSocket.bind(InternetAddress(localIp), 0);
      final wrapped = NetworkSecret.wrapPacket(pingData);
      final sent = probe.send(wrapped, dest, destPort);
      probe.close();
      return sent > 0;
    } catch (e) {
      probe?.close();
      _log.debug('Interface probe failed for $localIp: $e');
      return false;
    }
  }

  /// Activate mobile fallback: create a UDP socket bound to the mobile IP.
  /// Outgoing non-LAN IPv4 traffic will use this socket instead of the main one.
  /// Uses port 0 (OS-assigned) because the main socket on 0.0.0.0:port already
  /// claims all interfaces on the original port. Peers learn our mobile address
  /// from PONG source fields and CGNAT mapping — they don't need our original port.
  Future<bool> startMobileFallback(String mobileIp) async {
    if (_udpSocketMobile != null) return true; // Already active
    try {
      // Port 0: OS assigns a free port. Cannot use `port` because 0.0.0.0:port
      // (main socket) already binds all interfaces on that port → EADDRINUSE.
      _udpSocketMobile = await RawDatagramSocket.bind(
        InternetAddress(mobileIp),
        0,
      );
      _udpSocketMobile!.readEventsEnabled = true;
      _udpSocketMobile!.listen(
        _onUdpEventMobile,
        onError: (e) => _log.warn('UDP mobile socket error: $e'),
      );
      _mobileFallbackIp = mobileIp;
      final actualPort = _udpSocketMobile!.port;
      _log.info('Mobile fallback activated: bound to $mobileIp:$actualPort');
      onMobileFallbackChanged?.call(true);
      return true;
    } catch (e) {
      _log.info('Mobile fallback failed: $e');
      _udpSocketMobile = null;
      _mobileFallbackIp = null;
      return false;
    }
  }

  /// Deactivate mobile fallback (WiFi recovered or network changed).
  void stopMobileFallback() {
    if (_udpSocketMobile == null) return;
    _udpSocketMobile!.close();
    _udpSocketMobile = null;
    _log.info('Mobile fallback deactivated (was on $_mobileFallbackIp)');
    _mobileFallbackIp = null;
    onMobileFallbackChanged?.call(false);
  }

  /// Whether mobile fallback socket is currently active.
  bool get isMobileFallbackActive => _udpSocketMobile != null;

  /// Callback when mobile fallback state changes (for icon update).
  void Function(bool active)? onMobileFallbackChanged;

  void _onUdpEventMobile(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    for (;;) {
      final datagram = _udpSocketMobile?.receive();
      if (datagram == null) break;
      _processUdpDatagram(datagram);
    }
  }

  /// Stop the transport.
  /// Rebind to a new port at runtime. Closes old sockets, binds new ones.
  /// Throws SocketException if new port is unavailable.
  Future<void> rebind(int newPort) async {
    _log.info('Rebinding transport: $port → $newPort');
    // Probe first — fail fast before tearing down existing socket
    final probe = await RawDatagramSocket.bind(InternetAddress.anyIPv4, newPort);
    probe.close();
    // Tear down old
    await stop();
    port = newPort;
    // Bring up new
    await start();
    _log.info('Transport rebound to port $newPort');
  }

  Future<void> stop() async {
    _tlsRebindTimer?.cancel();
    _tlsRebindTimer = null;
    _tlsRebindAttempt = 0;
    _udpSocket?.close();
    _udpSocket = null;
    _udpSocket6?.close();
    _udpSocket6 = null;
    stopMobileFallback();
    await _tlsServer?.close();
    _tlsServer = null;
    await _tlsServer6?.close();
    _tlsServer6 = null;
    _log.info('Transport stopped');
  }

  bool get isRunning => _udpSocket != null;

  /// Whether IPv6 transport is available.
  bool get hasIpv6 => _udpSocket6 != null;
}
