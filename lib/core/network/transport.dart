import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/crypto/network_secret.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/native_udp_sender.dart';
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

/// Callback for received NetworkPacketV3 frames (Outer / Routing layer).
/// The transport has already verified `network_tag` (Closed-Network HMAC);
/// the callback is responsible for everything else in the v3.0 receive
/// pipeline (Architecture v3.0 §2.4 receiver steps 3-14).
typedef NetworkPacketCallback = void Function(
  proto.NetworkPacketV3 packet,
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

/// UDP + TLS transport layer. Single port for all traffic — UDP primary, TLS on the same port as anti-censorship fallback.
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
  int _consecutiveZeroSends = 0;
  bool _reconnecting = false;
  int _lastUdpReceiveMs = 0;
  SecureServerSocket? _tlsServer;
  SecureServerSocket? _tlsServer6; // IPv6 TLS (§27)
  Timer? _tlsRebindTimer;
  int _tlsRebindAttempt = 0;
  /// Set when TLS context cannot be obtained (missing openssl, no profile
  /// dir, etc.). Permanent failure — disables rebind retry to avoid log spam
  /// on platforms without openssl (Android).
  bool _tlsContextUnavailable = false;
  final FragmentReassembler _reassembler = FragmentReassembler();

  // ── Sender-side fragment pacing (Architecture §2.9.10) ───────────
  /// When a single payload fragments into more than this many packets,
  /// pacing is enabled to avoid burst-loss at mobile-carrier-NAT egress
  /// devices (small per-flow token buckets).
  static const int pacingThreshold = 4;

  /// Minimum delay between successive fragment sends to one destination
  /// when pacing is active. 1 ms × 29 fragments = ~28 ms added latency.
  static const Duration interFragmentDelay = Duration(milliseconds: 1);

  /// Cache of recently sent fragments for NACK-based resend.
  /// Key: "destIp:fragmentId", Value: list of fragment packets.
  /// Auto-expires after 30 seconds.
  final Map<String, List<Uint8List>> _sentFragmentCache = {};

  // ── Hybrid Bulk Transport — TLS Capability Cache ─────────────────
  // docs/SPEC_HYBRID_BULK_TRANSPORT.md §5.3. Per-destination tristate so
  // bulk-media path-selection can skip a doomed TLS connect after the
  // first observed failure, but still re-probe occasionally in case the
  // peer recovered (e.g. firewall reconfigured, daemon redeployed).
  /// Maximum size of a single TLS bulk frame (length-prefix payload).
  /// Matches `relay_chunker.dart` theoretical maximum
  /// (`maxChunksPerTransfer × maxChunkDataSize` ≈ 60 MB) so any
  /// envelope that fits the chunked-relay path also fits a single
  /// TLS bulk frame.
  static const int maxBulkFrameSize = 60 * 1024 * 1024;

  /// Hard cap on concurrent outbound TLS connections (C-3 EMFILE guard).
  /// Each SecureSocket.connect() holds an fd for up to [timeout] seconds.
  /// Under sustained load (video-call + rate-limiting), hundreds can queue
  /// simultaneously → EMFILE (errno=24) → event loop block → daemon crash.
  /// 20 concurrent slots keeps fd usage well below the typical 1024 limit
  /// while still allowing parallel bulk transfers to different peers.
  static const int _tlsMaxConcurrent = 20;
  int _tlsActiveConcurrent = 0;

  /// Re-probe cooldown — once a peer's TLS attempt failed, wait this long
  /// before letting path-selection try again. Prevents log-spam loops on
  /// hard-blocked carrier networks while still recovering after firewall
  /// reconfiguration or peer restart.
  static const Duration tlsCapabilityProbeCooldown = Duration(hours: 1);

  /// Per-destination TLS-bulk capability tristate. Key: `ip:port`.
  /// `null` (absent) → unknown, attempt one probe-and-cache.
  /// `capable=true`  → most recent attempt succeeded.
  /// `capable=false` → most recent attempt failed; re-probe-eligible
  /// once `lastProbeAt` is older than `tlsCapabilityProbeCooldown`.
  final Map<String, _TlsCapabilityEntry> _tlsCapability = {};

  /// Native UDP sender (libcleona_net) for platforms where Dart's
  /// RawDatagramSocket.send() is unreliable (Windows: returns 0 despite
  /// valid socket — see §4.5.2). Initialized in [start] on supported
  /// platforms; null on Android/iOS/macOS or when the library is missing.
  NativeUdpSender? _nativeSender;

  NetworkPacketCallback? onPacketV3;
  DiscoveryCallback? onDiscovery;
  /// Callback when a CPRB port probe packet arrives: (probeId, fromAddress, fromPort).
  void Function(Uint8List probeId, InternetAddress from, int fromPort)? onPortProbe;
  void Function(int bytes)? onBytesSent;
  void Function(int bytes)? onBytesReceived;

  Transport({required this.port, String? profileDir})
      : _profileDir = profileDir,
        _log = CLogger.get('transport', profileDir: profileDir);

  /// Start listening on UDP and TLS (anti-censorship fallback on the same port).
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

    // Native UDP sender for Transport.sendUdp — bypasses Dart's
    // RawDatagramSocket.send() which silently returns 0 on Windows.
    //
    // §4.5.2 (V3.1.72): the main data-port native sender is **Windows-only**.
    // `cleona_udp_open` binds a real SO_REUSEADDR socket on the data port;
    // on Linux the kernel then delivered inbound datagrams to *that* socket,
    // which is send-only and never read — starving the Dart receive socket
    // (`_udpSocket`) and breaking ALL inbound processing (no PONG → no peer
    // ever confirmed). This was the 2fbc879 regression. §4.5.2: "Linux is
    // unaffected — Dart's POSIX path behaves identically", so on Linux the
    // main port uses the Dart socket for send too (see `_udpSendRaw`'s
    // null-`_nativeSender` fallback). The discovery-port shim (LocalDiscovery,
    // port 41338) is a separate instance and unchanged.
    if (Platform.isWindows && nativeUdpSupportedPlatform()) {
      try {
        _nativeSender = NativeUdpSender.open(
          localPort: port,
          reuseAddr: true,
          broadcastEnable: true,
        );
        _nativeSender!.setBuffers(sndBytes: 4 * 1024 * 1024);
        _log.info('Native UDP transport sender attached '
            '(${NativeUdpSender.libraryVersion()})');
      } catch (e) {
        _log.warn('Native UDP transport sender unavailable, '
            'falling back to Dart socket: $e');
        _nativeSender = null;
      }
    }

    // IPv6 socket — dual-stack transport for DS-Lite/CGNAT (§27). Linux'
    // default dual-stack mode (`IPV6_V6ONLY=0`) was investigated as a
    // possible silent-drop source on 2026-05-08 and ruled out: the kernel
    // routes IPv4 datagrams to `_udpSocket` (`anyIPv4:port`) deterministically
    // when both sockets are bound, so `_onUdpEvent` sees them. Setting
    // `IPV6_V6ONLY=1` via `setRawOption` post-bind is rejected by Linux
    // with `EINVAL` and was therefore removed.
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

    // §4.5.2 invariant (V3.1.72): exactly ONE process socket must own the
    // IPv4 data port. A second bound socket (e.g. a NativeUdpSender opened on
    // the main port) silently captures inbound datagrams it never reads — the
    // 2fbc879 regression. Self-check via /proc/net/udp on Linux (log-only) so
    // any future re-introduction of a duplicate data-port socket announces
    // itself loudly at startup instead of manifesting as a dead mesh.
    if (Platform.isLinux) {
      try {
        final portHex =
            port.toRadixString(16).toUpperCase().padLeft(4, '0');
        final n = File('/proc/net/udp').readAsLinesSync().where((l) {
          final p = l.trim().split(RegExp(r'\s+'));
          return p.length > 1 && p[1].endsWith(':$portHex');
        }).length;
        if (n > 1) {
          _log.error('§4.5.2 INVARIANT VIOLATED: $n IPv4 UDP sockets bound to '
              'data port $port (expected 1) — a second socket captures inbound '
              'and breaks receive. Check for an extra socket on the main port.');
        } else {
          _log.debug('§4.5.2 invariant OK: $n IPv4 UDP socket on data port $port');
        }
      } catch (e) {
        _log.debug('data-port socket self-check skipped: $e');
      }
    }

    // Wire fragment reassembler logging
    _reassembler.onLog = (msg) => _log.debug(msg);

    // Wire fragment NACK callback — sends HMAC-wrapped NACK packets to sender
    _reassembler.onNack = (sourceIp, sourcePort, fragmentId, missing) {
      final nackPacket = UdpFragmenter.buildNack(fragmentId, missing);
      final wrapped = NetworkSecret.wrapPacket(nackPacket);
      try {
        final addr = InternetAddress(sourceIp);
        final s = _socketFor(addr);
        if (s != null) _udpSendRaw(wrapped, addr, sourcePort, s);
        _log.debug('Fragment NACK sent: id=$fragmentId missing=${missing.length} to $sourceIp:$sourcePort');
      } catch (_) {}
    };

    // TLS on same port as UDP (anti-censorship fallback, activates after 15 consecutive UDP failures).
    // UDP (SOCK_DGRAM) and TCP (SOCK_STREAM) live in separate kernel namespaces, so sharing the port number is safe.
    //
    // Bind TLS in the BACKGROUND: it is NOT on the critical path. The UDP sockets
    // (primary transport) are already bound+listening above, and TLS is only the
    // last-resort anti-censorship fallback. On first run _getOrCreateTlsContext()
    // spawns an `openssl` subprocess (seconds on a slow VM); awaiting it here
    // previously blocked transport.start() → node.startQuick() → IpcServer.start(),
    // delaying cleona.port past the GUI's connect timeout (Windows first-run hang).
    unawaited(() async {
      await _tryBindTlsListeners();
      if (_tlsServer == null || _tlsServer6 == null) {
        _scheduleTlsRebind();
      }
    }());
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
        _tlsServer = await SecureServerSocket.bind(InternetAddress.anyIPv4, port, ctx);
        _tlsServer!.listen(_onTlsConnection, onError: (e) {
          _log.debug('TLS accept error (non-fatal): $e');
        });
        _log.info('TLS listening on port $port');
      } catch (e) {
        _log.info('TLS listener not available (port $port): $e');
      }
    }
    if (_tlsServer6 == null) {
      try {
        _tlsServer6 = await SecureServerSocket.bind(InternetAddress.anyIPv6, port, ctx, v6Only: true);
        _tlsServer6!.listen(_onTlsConnection, onError: (e) {
          _log.debug('TLS6 accept error (non-fatal): $e');
        });
        _log.info('TLS6 listening on port $port');
      } catch (e) {
        _log.info('TLS6 listener not available (port $port): $e');
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
      _lastUdpReceiveMs = DateTime.now().millisecondsSinceEpoch;
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
      _lastUdpReceiveMs = DateTime.now().millisecondsSinceEpoch;
      _processUdpDatagram(datagram);
    }
  }

  void _processUdpDatagram(Datagram datagram) {
    final data = Uint8List.fromList(datagram.data);

    // V3.0 wire-layer discriminator (Architecture v3.0 §2.4):
    //
    // Two distinct framing schemes share the UDP socket:
    //   (a) Discovery / CPRB / Fragment / Fragment-NACK — raw byte packets
    //       wrapped with an 8-byte prefix HMAC (NetworkSecret.wrapPacket).
    //   (b) NetworkPacketV3 — protobuf-encoded with the HMAC inside the
    //       `network_tag` field (16 bytes, HMAC-SHA256-128). No prefix.
    //
    // The 4-byte ASCII magic ("CLEO" / "CPRB" / "CFRA" / "CFNK") sits at
    // offset 8 in scheme (a) — right after the prefix HMAC. We dispatch by
    // looking at exactly that window. If it matches, scheme (a) wins;
    // otherwise the bytes are treated as a NetworkPacketV3.
    //
    // Collision risk: scheme (b) bytes 8..11 fall inside the 32-byte
    // next_hop_device_id (a SHA-256 hash, effectively random) — the chance
    // of a hash matching one of four fixed 4-byte magics is ~4/2^32. On
    // false-positive the prefix-HMAC verify fails → silent drop, sender's
    // subsequent retry recovers cleanly.
    if (data.length >= NetworkSecret.hmacPrefixLength + 4) {
      final m0 = data[8];
      final m1 = data[9];
      final m2 = data[10];
      final m3 = data[11];
      final isDiscoveryMagic =
          // CLEO / CPRB / CFRA / CFNK all start with 'C' (0x43)
          m0 == 0x43 &&
              ((m1 == cleoMagic[1] && m2 == cleoMagic[2] && m3 == cleoMagic[3]) ||
                  (m1 == cprbMagic[1] && m2 == cprbMagic[2] && m3 == cprbMagic[3]) ||
                  (m1 == fragmentMagic[1] && m2 == fragmentMagic[2] && m3 == fragmentMagic[3]) ||
                  (m1 == fragmentNackMagic[1] && m2 == fragmentNackMagic[2] && m3 == fragmentNackMagic[3]));
      if (isDiscoveryMagic) {
        _processPrefixWrappedPacket(data, datagram.address, datagram.port);
        return;
      }
    }

    // Default path: NetworkPacketV3 (Outer / Routing layer).
    _processNetworkPacketV3(data, datagram.address, datagram.port, isUdp: true);
  }

  /// Scheme (a): packet wrapped with 8-byte HMAC prefix. Discovery, CPRB,
  /// fragment, fragment-NACK all use this. Verifies the prefix HMAC and
  /// dispatches by the 4-byte magic that follows.
  void _processPrefixWrappedPacket(
      Uint8List data, InternetAddress remoteAddress, int remotePort) {
    final payload = NetworkSecret.unwrapPacket(data);
    if (payload == null) {
      // Silent drop — invalid HMAC. No error response to avoid revealing our
      // existence to forked/scanning nodes.
      return;
    }

    // CLEO discovery packet (38 bytes: 4 magic + 32 nodeId + 2 port)
    if (payload.length == 38 &&
        payload[0] == cleoMagic[0] &&
        payload[1] == cleoMagic[1] &&
        payload[2] == cleoMagic[2] &&
        payload[3] == cleoMagic[3]) {
      final nodeId = Uint8List.fromList(payload.sublist(4, 36));
      final discPort = (payload[36] << 8) | payload[37];
      onDiscovery?.call(nodeId, discPort, remoteAddress, remotePort);
      return;
    }

    // Port probe (CPRB magic)
    if (payload.length == cprbPacketSize &&
        payload[0] == cprbMagic[0] &&
        payload[1] == cprbMagic[1] &&
        payload[2] == cprbMagic[2] &&
        payload[3] == cprbMagic[3]) {
      final probeId = Uint8List.fromList(payload.sublist(4, 20));
      onPortProbe?.call(probeId, remoteAddress, remotePort);
      return;
    }

    // Fragment NACK (CFNK magic)
    if (UdpFragmenter.isFragmentNack(payload)) {
      final nack = UdpFragmenter.parseNack(payload);
      if (nack != null) {
        unawaited(_handleFragmentNack(
            nack.fragmentId, nack.missing, remoteAddress, remotePort));
      }
      return;
    }

    // Fragment (CFRA magic) — accumulate, dispatch when complete
    if (UdpFragmenter.isFragment(payload)) {
      onBytesReceived?.call(payload.length);
      final reassembled = _reassembler.addFragment(
          payload, remoteAddress.address, remotePort);
      if (reassembled != null) {
        // The reassembled bytes are a NetworkPacketV3 (the only frame type
        // that ever needs fragmentation — Discovery/CPRB are <=46 bytes).
        _processNetworkPacketV3(reassembled, remoteAddress, remotePort,
            isUdp: true);
      }
      return;
    }

    // Magic-window matched but inner type unknown — silent drop.
    _log.debug('Unknown prefix-wrapped packet from $remoteAddress:$remotePort');
  }

  /// Scheme (b): bytes are a serialized NetworkPacketV3. Verifies the in-frame
  /// `network_tag` (Closed-Network HMAC, Architecture v3.0 §2.4 [11]) and
  /// dispatches the parsed packet to the [onPacketV3] callback.
  void _processNetworkPacketV3(
    Uint8List bytes,
    InternetAddress remoteAddress,
    int remotePort, {
    required bool isUdp,
  }) {
    onBytesReceived?.call(bytes.length);
    final packet = parseAndVerifyNetworkPacketV3(bytes);
    if (packet == null) {
      _log.debug('NetworkPacketV3 parse/HMAC fail from $remoteAddress:$remotePort');
      return;
    }
    if (onPacketV3 == null) {
      _log.warn('V3 onPacketV3 not wired — packet dropped from $remoteAddress:$remotePort');
      return;
    }
    _log.debug('V3 dispatch: HMAC ok, ${bytes.length}B from $remoteAddress:$remotePort isUdp=$isUdp');
    onPacketV3!.call(packet, remoteAddress, remotePort, isUdp: isUdp);
  }

  /// Parse [bytes] as NetworkPacketV3 and verify the in-frame HMAC.
  /// Returns the parsed packet on success, null on parse failure or HMAC
  /// mismatch (both → silent drop at caller). Public so non-UDP entrypoints
  /// (e.g. §5.4 Reed-Solomon reassembly in [CleonaNode.dispatchReassembledPacket])
  /// can validate frame integrity without reaching into transport internals.
  proto.NetworkPacketV3? parseAndVerifyNetworkPacketV3(Uint8List bytes) {
    final proto.NetworkPacketV3 packet;
    try {
      packet = proto.NetworkPacketV3.fromBuffer(bytes);
    } catch (_) {
      return null;
    }
    final tag = Uint8List.fromList(packet.networkTag);
    if (tag.length != NetworkSecret.networkTagLength) return null;
    // Re-serialize without the tag field to recover the input to the HMAC
    // computation (sender computed HMAC over (frame - network_tag), then set
    // the field, then serialized for transmission — so verifier mirrors that).
    // Mutate-and-restore avoids a deep copy: the packet object is freshly
    // parsed from the wire and only ever observed by the dispatch chain
    // after this method returns, so the brief clear is invisible to callers.
    packet.clearNetworkTag();
    final probeBytes = packet.writeToBuffer();
    packet.networkTag = tag;
    if (!NetworkSecret.verifyNetworkTag(tag, probeBytes)) return null;
    return packet;
  }

  /// Serialize a NetworkPacketV3 for the wire: compute the in-frame HMAC
  /// (`network_tag`, Architecture v3.0 §2.4 [11]), set the field, and return
  /// the protobuf bytes ready to send. The packet object is modified in
  /// place so callers should not reuse it for other destinations without
  /// re-signing — the routing fields (nextHopDeviceId, ttl, hopCount) are
  /// per-destination anyway. Public so non-UDP send paths (e.g. §5.4
  /// Reed-Solomon offline-delivery, which serializes the canonical packet
  /// bytes for fragmentation) can produce identical wire bytes that the
  /// receiver's HMAC-verify will accept.
  Uint8List serializeWithTag(proto.NetworkPacketV3 packet) {
    packet.clearNetworkTag();
    final withoutTag = packet.writeToBuffer();
    final tag = NetworkSecret.computeNetworkTag(withoutTag);
    packet.networkTag = tag;
    return packet.writeToBuffer();
  }

  /// Low-level UDP send: uses native sender (libcleona_net) when available,
  /// falls back to Dart RawDatagramSocket. Returns bytes sent (>0 on success).
  int _udpSendRaw(Uint8List data, InternetAddress address, int remotePort,
      RawDatagramSocket socket) {
    if (_nativeSender != null && address.type == InternetAddressType.IPv4) {
      final sent = _nativeSender!.send(address.address, remotePort, data);
      if (sent > 0) return sent;
      // Negative = errno from WSASendTo/sendto; fall through to Dart socket
      // only if the native sender returned a transient error.
    }
    return socket.send(data, address, remotePort);
  }

  /// Send a NetworkPacketV3 via UDP to a specific address.
  /// For wire bytes >1200, automatically fragments. Computes and sets the
  /// in-frame `network_tag` (Closed-Network HMAC) before serialization;
  /// the caller is responsible for filling all other Outer-Frame fields
  /// (sigs, PoW, routing ids — Architecture v3.0 §2.4 sender steps 8-10).
  Future<bool> sendUdp(
    proto.NetworkPacketV3 packet,
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
      _log.info('sendUdp: no ${address.type == InternetAddressType.IPv6 ? "IPv6" : "IPv4"} socket for ${address.address}');
      return false;
    }
    try {
      final data = serializeWithTag(packet);

      // Fragment if payload exceeds UDP-safe size. Fragments still use the
      // 8-byte prefix HMAC (UdpFragmenter packets have their own framing —
      // see _processPrefixWrappedPacket dispatcher). The reassembled bytes
      // on the receiver side are then parsed as NetworkPacketV3 with its
      // own in-frame tag verified end-to-end.
      if (data.length > maxFragmentPacketSize) {
        final fragments = UdpFragmenter.fragment(data);
        var anySent = false;
        final wrappedFragments = <Uint8List>[];
        for (final frag in fragments) {
          wrappedFragments.add(NetworkSecret.wrapPacket(frag));
        }
        // Pacing: insert `interFragmentDelay` between sends when more than
        // `pacingThreshold` fragments go to one destination, to avoid burst
        // loss at carrier-NAT egress (Architecture §2.9.10).
        final pacingActive = fragments.length > pacingThreshold;
        final pacing = fragments.length > 5
            ? const Duration(milliseconds: 3)
            : interFragmentDelay;
        var frag0Failed = false;
        for (var i = 0; i < wrappedFragments.length; i++) {
          final sent = _udpSendRaw(wrappedFragments[i], address, remotePort, socket);
          if (sent > 0) {
            anySent = true;
          } else {
            if (i == 0) frag0Failed = true;
            _log.debug('sendUdp: fragment $i/${wrappedFragments.length} returned $sent '
                'for ${address.address}:$remotePort');
          }
          if (pacingActive && i < wrappedFragments.length - 1) {
            await Future.delayed(pacing);
          }
        }
        if (frag0Failed && anySent) {
          await Future.delayed(const Duration(milliseconds: 5));
          final retry = _udpSendRaw(wrappedFragments[0], address, remotePort, socket);
          if (retry > 0) {
            _log.debug('sendUdp: fragment-0 retry succeeded for ${address.address}:$remotePort');
          }
        }
        if (anySent) {
          _consecutiveZeroSends = 0;
          onBytesSent?.call(data.length);
          final header = UdpFragmenter.parseHeader(fragments.first);
          if (header != null) {
            final cacheKey = '${address.address}:${header.fragmentId}';
            _sentFragmentCache[cacheKey] = wrappedFragments;
            Timer(const Duration(seconds: 30), () => _sentFragmentCache.remove(cacheKey));
          }
        } else {
          _consecutiveZeroSends += wrappedFragments.length;
          _log.info('sendUdp: all ${wrappedFragments.length} fragments returned 0 for ${address.address}:$remotePort');
          if (_consecutiveZeroSends >= 10 && !_reconnecting) {
            _log.warn('UDP socket appears dead ($_consecutiveZeroSends consecutive 0-sends)');
            onUdpSocketDead?.call();
          }
        }
        return anySent;
      }

      // Non-fragmented: NetworkPacketV3 carries its tag in-band (no prefix).
      final sent = _udpSendRaw(data, address, remotePort, socket);
      if (sent > 0) {
        _consecutiveZeroSends = 0;
        onBytesSent?.call(data.length);
        return true;
      }
      _consecutiveZeroSends++;
      _log.info('sendUdp: socket.send returned $sent for ${address.address}:$remotePort (${data.length}B)');
      if (_consecutiveZeroSends >= 10 && !_reconnecting) {
        _log.warn('UDP socket appears dead ($_consecutiveZeroSends consecutive 0-sends)');
        onUdpSocketDead?.call();
      }
      return false;
    } catch (e) {
      _log.info('UDP send error to ${address.address}:$remotePort: $e');
      return false;
    }
  }

  /// Handle NACK: resend missing fragments from cache.
  Future<void> _handleFragmentNack(int fragmentId, List<int> missing, InternetAddress from, int fromPort) async {
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
    // Pacing: same threshold/delay as initial send (Architecture §2.9.10).
    final pacingActive = missing.length > pacingThreshold;
    for (var i = 0; i < missing.length; i++) {
      final idx = missing[i];
      if (idx >= 0 && idx < cached.length) {
        try {
          final sent = socket != null
              ? _udpSendRaw(cached[idx], from, fromPort, socket)
              : 0;
          if (sent > 0) resent++;
        } catch (_) {}
        if (pacingActive && i < missing.length - 1) {
          await Future.delayed(interFragmentDelay);
        }
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
      final sent = _udpSendRaw(wrapped, address, remotePort, socket);
      if (sent > 0) {
        _log.debug('Port probe sent to ${address.address}:$remotePort');
        return true;
      }
    } catch (e) {
      _log.debug('Port probe send error: $e');
    }
    return false;
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
      _log.debug('TLS parse: buf=${bytes.length}B from ${client.remoteAddress.address}:${client.remotePort}');
      if (bytes.length < 4) return;
      final len = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
      if (len <= 0 || len > maxBulkFrameSize) {
        // Hybrid Bulk Transport: oversized frame is unauthenticated input
        // we must not buffer. Drop the entire connection — sender will
        // see TLS reset, fall back to UDP-chunked-relay.
        _log.warn('TLS parse: invalid len=$len from ${client.remoteAddress.address}:${client.remotePort} — dropping connection');
        buffer.clear();
        return;
      }
      if (bytes.length < 4 + len) {
        _log.debug('TLS parse: partial ${bytes.length}/${4 + len}B from ${client.remoteAddress.address}:${client.remotePort} — waiting');
        return;
      }

      final msgBytes = Uint8List.fromList(bytes.sublist(4, 4 + len));
      _processNetworkPacketV3(
          msgBytes, client.remoteAddress, client.remotePort, isUdp: false);

      final remaining = bytes.sublist(4 + len);
      buffer.clear();
      if (remaining.isNotEmpty) {
        buffer.add(remaining);
      } else {
        return;
      }
    }
  }

  /// Send a NetworkPacketV3 via TLS (same port as UDP). Anti-censorship
  /// fallback when UDP is blocked. The in-frame `network_tag` is filled by
  /// [serializeWithTag]; outer Device-Sig integrity is the caller's
  /// responsibility (Architecture v3.0 §2.4 sender step 9).
  Future<bool> sendTls(
    proto.NetworkPacketV3 packet,
    InternetAddress address,
    int remotePort, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      final data = serializeWithTag(packet);
      final lenPrefix = Uint8List(4);
      lenPrefix[0] = (data.length >> 24) & 0xFF;
      lenPrefix[1] = (data.length >> 16) & 0xFF;
      lenPrefix[2] = (data.length >> 8) & 0xFF;
      lenPrefix[3] = data.length & 0xFF;

      // Connect TLS on the same port as UDP. Accept only self-signed certs
      // matching the Cleona convention (CN=cleona-node, not expired). The
      // Outer-Frame Device-Sig + in-frame network_tag still authenticate the
      // payload end-to-end; this callback rejects obviously foreign certs
      // (MitM hardening, H-3).
      final socket = await SecureSocket.connect(
        address,
        remotePort,
        timeout: timeout,
        onBadCertificate: _isAcceptableCleonaCert,
      );
      socket.add(lenPrefix);
      socket.add(data);
      await socket.flush();
      await socket.close();
      onBytesSent?.call(data.length + 4);
      return true;
    } catch (e) {
      _log.debug('TLS send error to ${address.address}:$remotePort: $e');
      return false;
    }
  }

  // ── Hybrid Bulk Transport (docs/SPEC_HYBRID_BULK_TRANSPORT.md §5) ──

  /// Whether [address]:[port] is currently considered TLS-bulk capable.
  /// Returns true on `null` (unknown — caller should attempt) or `true`
  /// (last attempt succeeded). Returns false on `false` while still in
  /// the cooldown window; returns true once cooldown elapsed (re-probe
  /// eligible).
  bool tlsBulkCapable(InternetAddress address, int port) {
    if (_tlsContextUnavailable) return false;
    final entry = _tlsCapability['${address.address}:$port'];
    if (entry == null) return true; // unknown → let caller try
    if (entry.capable == true) return true;
    final last = entry.lastProbeAt;
    if (last == null) return true;
    return DateTime.now().difference(last) >= tlsCapabilityProbeCooldown;
  }

  /// Drop the TLS-capability entry for a destination — forces the next
  /// path-selection to treat the peer as `null` (try-and-cache) again.
  /// Use when an address changes or the peer publishes a new endpoint.
  void invalidateTlsCapability(InternetAddress address, int port) {
    _tlsCapability.remove('${address.address}:$port');
  }

  /// Send a bulk NetworkPacketV3 (>maxChunkDataSize, typical inline /
  /// two-stage media) via a short-lived TLS connection. Returns true on
  /// success, false on any transport failure — caller MUST be prepared to
  /// fall back to UDP-chunked-relay; this method never throws.
  ///
  /// This method only runs the TLS attempt and updates the per-peer
  /// capability cache; bulk path-selection is handled in the V3 sender.
  /// Connection lifecycle is connect → write length-prefix + payload →
  /// flush → close. A future revision may add connection caching (see Spec §13.1).
  Future<bool> sendBulkViaTLS(
    proto.NetworkPacketV3 packet,
    InternetAddress address,
    int remotePort, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final key = '${address.address}:$remotePort';
    if (_tlsActiveConcurrent >= _tlsMaxConcurrent) {
      _log.debug('sendBulkViaTLS: concurrent limit ($_tlsMaxConcurrent) reached, dropping $key');
      return false;
    }
    _tlsActiveConcurrent++;
    SecureSocket? socket;
    try {
      final data = serializeWithTag(packet);
      if (data.length > maxBulkFrameSize) {
        _log.warn('sendBulkViaTLS: packet ${data.length}B exceeds maxBulkFrameSize');
        return false;
      }
      final lenPrefix = Uint8List(4);
      lenPrefix[0] = (data.length >> 24) & 0xFF;
      lenPrefix[1] = (data.length >> 16) & 0xFF;
      lenPrefix[2] = (data.length >> 8) & 0xFF;
      lenPrefix[3] = data.length & 0xFF;

      socket = await SecureSocket.connect(
        address,
        remotePort,
        timeout: timeout,
        onBadCertificate: _isAcceptableCleonaCert,
      );
      socket.add(lenPrefix);
      socket.add(data);
      await socket.flush();
      onBytesSent?.call(data.length + 4);
      _tlsCapability[key] = _TlsCapabilityEntry(capable: true, lastProbeAt: DateTime.now());
      _log.info('sendBulkViaTLS: ${data.length}B → $key OK');
      return true;
    } catch (e) {
      _tlsCapability[key] = _TlsCapabilityEntry(capable: false, lastProbeAt: DateTime.now());
      _log.info('sendBulkViaTLS: $key failed → cap=false: $e');
      return false;
    } finally {
      _tlsActiveConcurrent--;
      try {
        await socket?.close();
      } catch (_) {}
    }
  }

  /// Gate for self-signed peer certs during TLS fallback (H-3).
  /// Cleona generates certs with `CN=cleona-node` in _getOrCreateTlsContext;
  /// here we accept only certs that match that convention and are not
  /// expired. A blanket-accept would let a MitM terminate TLS with any
  /// cert — while envelope signatures still protect content integrity, this
  /// gate raises the cost of passive correlation / active tampering attempts.
  /// Pubkey pinning against the node identity would require out-of-band
  /// fingerprint distribution (not yet in protocol) and is tracked separately.
  static bool _isAcceptableCleonaCert(X509Certificate cert) {
    try {
      final now = DateTime.now();
      if (now.isBefore(cert.startValidity) || now.isAfter(cert.endValidity)) {
        return false;
      }
      // Subject + issuer must both carry the Cleona self-signed marker.
      final subject = cert.subject;
      final issuer = cert.issuer;
      if (!subject.contains('cleona-node')) return false;
      if (!issuer.contains('cleona-node')) return false;
      return true;
    } catch (_) {
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

  /// Send a NetworkPacketV3 to all given addresses in parallel (UDP only).
  /// Total operation is capped at 5 seconds to prevent cascade timeouts.
  /// Each fan-out re-serializes the packet (so fragmenter cache keys don't
  /// collide and a per-destination tag is computed correctly even though
  /// the routing fields are identical).
  Future<bool> sendToAll(
    proto.NetworkPacketV3 packet,
    List<({InternetAddress address, int port})> targets,
  ) async {
    if (targets.isEmpty) return false;

    final futures = <Future<bool>>[];
    for (final target in targets) {
      futures.add(sendUdp(packet, target.address, target.port));
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
    // WIN-2: also skip tunnel pseudo-interfaces (Teredo, 6to4, documentation,
    // IPv4-mapped) — these flap as Windows kernel re-creates them, and
    // every flap would otherwise trigger a full network-change soft-reset.
    final ipv6Global = <String>[];
    try {
      final interfaces6 = await NetworkInterface.list(
        type: InternetAddressType.IPv6,
      );
      for (final iface in interfaces6) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback || addr.isLinkLocal) continue;
          if (isTunnelIpv6(addr.address)) continue;
          ipv6Global.add(addr.address);
        }
      }
    } catch (_) {
      // IPv6 enumeration not available on this platform
    }

    return [...privateIps, ...publicIps, ...ipv6Global];
  }

  /// WIN-2: classify pseudo-interface IPv6 addresses that should NOT count
  /// as part of our network identity for the purposes of network-change
  /// detection. These ranges flap on Windows (Teredo) and don't represent
  /// actual reachable interfaces.
  ///
  /// - 2001:0::/32 — Teredo (RFC 4380), Microsoft IPv6-via-IPv4-NAT-Tunnel
  /// - 2002::/16 — 6to4 (RFC 3056), legacy IPv6-via-IPv4 transition
  /// - 2001:db8::/32 — documentation prefix (RFC 3849), should not appear in production
  /// - ::ffff:0:0/96 — IPv4-mapped IPv6
  static bool isTunnelIpv6(String ip) {
    if (!ip.contains(':')) return false;
    final lower = ip.toLowerCase();
    // Strip zone-id (fe80::1%eth0) — not relevant since fe80 is link-local
    final core = lower.split('%').first;
    if (core.startsWith('2001:0:') || core.startsWith('2001::')) return true; // Teredo
    if (core.startsWith('2002:')) return true;                                // 6to4
    if (core.startsWith('2001:db8:')) return true;                            // Documentation
    if (core.startsWith('::ffff:')) return true;                              // IPv4-mapped
    return false;
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

  /// Callback when UDP socket is detected as dead (10+ consecutive 0-sends).
  /// CleonaNode uses this to trigger onNetworkChanged().
  void Function()? onUdpSocketDead;

  /// Windows UDP receive watchdog. Dart's IOCP-based RawDatagramSocket
  /// silently stops delivering RawSocketEvent.read after sustained traffic
  /// bursts — same defect class as the send-path 87.9% drop that
  /// libcleona_net fixed. Triggers the full network-change recovery cycle
  /// (reconnect sockets + re-PING neighbors + re-publish addresses).
  void checkReceiveHealth() {
    if (!Platform.isWindows) return;
    if (_lastUdpReceiveMs == 0) return;
    if (_reconnecting) return;
    final silenceMs = DateTime.now().millisecondsSinceEpoch - _lastUdpReceiveMs;
    if (silenceMs > 120000) {
      _log.warn('UDP receive stale (${silenceMs ~/ 1000}s silence) — triggering recovery');
      _lastUdpReceiveMs = DateTime.now().millisecondsSinceEpoch;
      onUdpSocketDead?.call();
    }
  }

  /// Close and reopen UDP sockets on the same port. Called on network change
  /// to recover from dead sockets (Android invalidates sockets when the active
  /// network interface changes). TLS listeners are left intact.
  Future<void> reconnectUdpSockets() async {
    if (_reconnecting) return;
    _reconnecting = true;
    try {
      _log.info('Reconnecting UDP sockets on port $port');
      _udpSocket?.close();
      _udpSocket = null;
      _udpSocket6?.close();
      _udpSocket6 = null;
      stopMobileFallback();

      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
      _udpSocket!.broadcastEnabled = true;
      _udpSocket!.readEventsEnabled = true;
      try {
        final size = 2 * 1024 * 1024;
        final sizeBytes = Uint8List(4)..buffer.asByteData().setInt32(0, size, Endian.host);
        _udpSocket!.setRawOption(RawSocketOption(1, 8, sizeBytes));
      } catch (_) {}
      _udpSocket!.listen(
        _onUdpEvent,
        onError: (e) => _log.warn('UDP socket error: $e'),
      );

      try {
        _udpSocket6 = await RawDatagramSocket.bind(InternetAddress.anyIPv6, port);
        _udpSocket6!.readEventsEnabled = true;
        try {
          final size = 2 * 1024 * 1024;
          final sizeBytes = Uint8List(4)..buffer.asByteData().setInt32(0, size, Endian.host);
          _udpSocket6!.setRawOption(RawSocketOption(1, 8, sizeBytes));
        } catch (_) {}
        _udpSocket6!.listen(
          _onUdpEvent6,
          onError: (e) => _log.warn('UDP6 socket error: $e'),
        );
      } catch (e) {
        _udpSocket6 = null;
      }
      _consecutiveZeroSends = 0;
      _log.info('UDP sockets reconnected on port $port');
    } catch (e) {
      _log.warn('UDP socket reconnect failed: $e');
    } finally {
      _reconnecting = false;
    }
  }

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
    _nativeSender?.close();
    _nativeSender = null;
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

/// TLS-bulk capability tristate for one destination — see Spec §5.3.
/// Cache lives only daemon-lifetime in `Transport._tlsCapability`; re-probed
/// on restart so a redeployed peer is rediscovered without manual reset.
class _TlsCapabilityEntry {
  bool? capable;
  DateTime? lastProbeAt;
  _TlsCapabilityEntry({this.capable, this.lastProbeAt});
}
