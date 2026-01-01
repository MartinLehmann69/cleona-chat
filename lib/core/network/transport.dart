import 'dart:async';
import 'dart:io';
import 'dart:math' show min;
import 'dart:typed_data';
import 'package:cleona/core/crypto/network_secret.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/multi_interface.dart';
import 'package:cleona/core/network/android_udp_sender.dart';
import 'package:cleona/core/network/native_udp_sender.dart';
import 'package:cleona/core/network/ios_udp_sender.dart';
import 'package:cleona/core/network/udp_fragmenter.dart';
import 'package:cleona/core/update/binary_http_server.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Magic bytes for LAN discovery packets: "CLEO" (0x43 0x4C 0x45 0x4F)
const List<int> cleoMagic = [0x43, 0x4C, 0x45, 0x4F];

/// Magic bytes for port probe: "CPRB" (Cleona Port Probe)
/// Packet format: [4B "CPRB"][16B probe_id] = 20 bytes payload (28 on wire with HMAC)
const List<int> cprbMagic = [0x43, 0x50, 0x52, 0x42];
const int cprbPacketSize = 20; // 4 magic + 16 probe_id

/// Magic bytes for EPOCH_EXPIRED hint: "CEEP" (Cleona Epoch Expired)
/// Packet format: [8B HMAC][4B "CEEP"][2B minVersionLE][2B epochLE] = 16 bytes
const List<int> ceepMagic = [0x43, 0x45, 0x45, 0x50];

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

/// F4 (S123 UDP-dead RCA, 2026-07-03 Pixel field test): edge-triggered
/// dead-socket detector, extracted from [Transport] so the edge/re-arm
/// semantics are unit-testable without a real socket
/// (`test/smoke/smoke_udp_dead_recovery.dart`).
///
/// Counts consecutive 0-byte UDP sends (a single failed send counts 1; a
/// fragment burst that all returned 0 counts the fragment count). Once the
/// running count crosses [threshold] the detector reports the crossing
/// EXACTLY ONCE — every further zero-send while still "armed" is silently
/// counted, not re-reported — until re-armed by [noteSendSuccess] (a send
/// returned >0 bytes) or [noteReconnectCompleted] (a `reconnectUdpSockets()`
/// finished). Both re-arm paths also reset the counter to 0.
///
/// Before this fix, `Transport.sendUdp` fired the dead-warning log +
/// `onUdpSocketDead` callback on EVERY 0-send once the threshold was
/// crossed — during a ~2.5 min WLAN-zombie period (interface kept its IPs,
/// uplink dead) this produced 36,030 warn-log lines and 5,156
/// `onUdpSocketDead` invocations in a single field-test minute.
class ZeroSendDeadEdgeDetector {
  ZeroSendDeadEdgeDetector({
    this.threshold = 10,
    this.clamp = 1000000,
    this.minWindowMs = 3000,
  });

  /// Consecutive-0-send count at which the socket is considered dead.
  final int threshold;

  /// Hard cap on the internal counter — purely a safety clamp against
  /// unbounded growth during a long dead period; the edge-gate already
  /// prevents repeat firing regardless of how high the count climbs.
  final int clamp;

  /// Minimum elapsed time (ms) from first failure before the detector fires.
  /// Prevents a single DHT K=10 fanout burst (<100ms) from triggering
  /// dead-edge — only sustained failure over this window is evidence of
  /// actual socket death.
  final int minWindowMs;

  int _consecutiveZeroSends = 0;
  bool _edgeFired = false;
  int _firstFailureMs = 0;

  /// Current consecutive-0-send count (for logging).
  int get consecutiveZeroSends => _consecutiveZeroSends;

  /// Whether the dead-edge has already fired for the current run (i.e.
  /// further 0-sends will be counted but not re-reported).
  bool get edgeFired => _edgeFired;

  /// Record a successful send (>0 bytes). Resets the counter and re-arms
  /// the edge so the next dead period can be detected again.
  void noteSendSuccess() {
    _consecutiveZeroSends = 0;
    _edgeFired = false;
    _firstFailureMs = 0;
  }

  /// Record a completed `reconnectUdpSockets()`. Same effect as
  /// [noteSendSuccess] — kept as a separate method for call-site clarity
  /// (F1/F4 design: re-arm "on successful send OR completed reconnect").
  void noteReconnectCompleted() {
    _consecutiveZeroSends = 0;
    _edgeFired = false;
    _firstFailureMs = 0;
  }

  /// Record [count] consecutive 0-byte sends. Returns `true` exactly once
  /// per dead period — the call where the running count crosses
  /// [threshold] AND the temporal hysteresis window has elapsed — and
  /// `false` on every other call.
  bool noteZeroSends(int count) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (_consecutiveZeroSends == 0) _firstFailureMs = nowMs;
    _consecutiveZeroSends += count;
    if (_consecutiveZeroSends > clamp) _consecutiveZeroSends = clamp;
    if (_edgeFired) return false;
    if (_consecutiveZeroSends >= threshold &&
        (nowMs - _firstFailureMs) >= minWindowMs) {
      _edgeFired = true;
      return true;
    }
    return false;
  }
}

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
  /// F4 (S123 UDP-dead RCA): edge-triggered dead-socket detector. Fires
  /// [onUdpSocketDead] (via the call sites below) EXACTLY ONCE per dead
  /// period instead of on every subsequent 0-send — a WLAN-zombie period in
  /// the field produced 36,030 warn-log lines / 5,156 dead-callbacks in one
  /// minute before this fix. See [ZeroSendDeadEdgeDetector] doc.
  final ZeroSendDeadEdgeDetector _deadEdge = ZeroSendDeadEdgeDetector();
  bool _reconnecting = false;
  int _consecutiveDeadFromBirth = 0;
  int _lastReconnectMs = 0;
  int _lastUdpReceiveMs = 0;
  int _startedAtMs = 0;
  bool _selfProbeAcked = false;
  bool _staleProbeInFlight = false;
  int externalPacketsReceived = 0;
  bool firewallWarningEmitted = false;
  /// Plain TCP listeners (§19.6.6 First-Byte-Sniffing). No longer a
  /// [SecureServerSocket] — the TLS handshake happened automatically at
  /// accept time, which left no way to route a plain HTTP request (used by
  /// the censorship-resistant binary distribution web app) to the same
  /// port. Every accepted [Socket] is sniffed in [_onRawTcpConnection] and
  /// either upgraded to TLS in-process ([_upgradeToTls], preserving the
  /// existing [_onTlsConnection] pipeline unchanged) or handed to
  /// [httpServer].
  ServerSocket? _tlsServer;
  ServerSocket? _tlsServer6; // IPv6 TLS+HTTP (§27, §19.6.6)
  Timer? _tlsRebindTimer;
  int _tlsRebindAttempt = 0;
  /// Set when TLS context cannot be obtained (missing openssl, no profile
  /// dir, etc.). Permanent failure — no further [_getOrCreateTlsContext]
  /// calls to avoid log spam / repeated openssl spawns on platforms without
  /// openssl (Android). Does NOT stop the plain TCP listener from binding
  /// or rebinding — §19.6.6 HTTP binary distribution has no TLS dependency,
  /// so it must keep working even where the TLS upgrade branch cannot.
  bool _tlsContextUnavailable = false;
  /// Cached TLS [SecurityContext], resolved once by [_tryBindTlsListeners]
  /// and reused for every in-process TLS upgrade in [_upgradeToTls] — a
  /// fresh [_getOrCreateTlsContext] call re-reads the cert/key PEM files
  /// from disk, which would be wasteful per incoming connection.
  SecurityContext? _tlsSecurityContext;
  /// §19.6.6 — embedded HTTP server for censorship-resistant binary
  /// distribution, served on the same port via First-Byte-Sniffing. Not
  /// constructed here — the owning service layer sets this (and its
  /// providers) after [Transport] is created; connections are dropped if
  /// unset (see [_routeSniffedConnection]).
  BinaryHttpServer? httpServer;
  final FragmentReassembler _reassembler = FragmentReassembler();

  // ── Sender-side fragment pacing (Architecture §2.9.10) ───────────
  /// When a single payload fragments into more than this many packets,
  /// pacing is enabled to avoid burst-loss at mobile-carrier-NAT egress
  /// devices (small per-flow token buckets).
  static const int pacingThreshold = 4;

  /// Minimum delay between successive fragment sends to one destination
  /// when pacing is active. 2 ms × 29 fragments = ~58 ms added latency.
  static const Duration interFragmentDelay = Duration(milliseconds: 2);

  /// §2.9.10: CGNAT burst size — max fragments per burst before pausing.
  /// Empirically derived: DS-Lite CGNAT passes groups of ≤8 reliably,
  /// drops larger bursts completely (zero fragments arrive).
  static const int _cgnatBurstSize = 8;

  /// Pause between fragment bursts for CGNAT-safe delivery.
  static const Duration _cgnatInterGroupDelay = Duration(milliseconds: 50);

  /// Cache of recently sent fragments for NACK-based resend.
  /// Key: "destIp:fragmentId", Value: list of fragment packets.
  /// Auto-expires after 30 seconds; refreshed on each NACK receipt.
  /// Bounded to [_sentFragmentCacheMaxEntries] — oldest entry evicted on overflow.
  final Map<String, List<Uint8List>> _sentFragmentCache = {};
  final Map<String, Timer> _sentFragmentCacheTimers = {};

  /// Max entries in `_sentFragmentCache` — bounds memory under adversarial
  /// NACK patterns. Dart Maps preserve insertion order, so removing
  /// `.keys.first` evicts the oldest entry.
  static const int _sentFragmentCacheMaxEntries = 500;

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

  /// Max entries in `_tlsCapability` — safety net against unbounded growth.
  static const int _tlsCapabilityMaxEntries = 1000;

  /// TTL for TLS capability entries — entries older than this are evicted
  /// by the periodic cleanup. NOT LRU: we don't want to evict a peer
  /// mid-conversation just because it hasn't done a TLS transfer recently.
  static const Duration _tlsCapabilityTtl = Duration(hours: 24);

  /// Periodic cleanup timer for `_tlsCapability`.
  Timer? _tlsCapabilityCleanupTimer;

  // ── Send burst limiter (Ingo crash: GetStackPointerForStackBounds) ──
  // Caps rapid-fire FFI calls from onNetworkChanged bursts. When more than
  // [_burstLimit] sends fire within [_burstWindowMs], sendUdp yields to the
  // event loop before continuing. This breaks up the synchronous FFI call
  // chain that exhausts Dart's stack-guard pages on Windows.
  static const int _burstLimit = 15;
  static const int _burstWindowMs = 50;
  int _burstWindowStart = 0;
  int _burstCount = 0;

  /// Native UDP sender (libcleona_net) for platforms where Dart's
  /// RawDatagramSocket.send() is unreliable (Windows: returns 0 despite
  /// valid socket — see §4.5.2). Initialized in [start] on supported
  /// platforms; null on Android/macOS or when the library is missing.
  NativeUdpSender? _nativeSender;
  NativeUdpSender6? _nativeSender6;

  /// iOS native sendto() bypass. Dart's RawDatagramSocket.send() returns 0
  /// on iOS (errno 64/65). Uses the SAME fd as the Dart socket — no second
  /// socket, no §4.5.2 dual-socket risk.
  IosUdpSender? _iosUdpSender;

  /// Android native sendto() via libcleona_net.so. Same fd as Dart socket
  /// (found via /proc/self/fd scan). Returns actual errno on failure —
  /// allows distinguishing ENETUNREACH (socket dead) from EHOSTUNREACH
  /// (peer-specific, normal).
  AndroidUdpSender? _androidUdpSender;

  // ── Multi-Interface Send (Architecture §23.2) ─────────────────────
  /// Per-interface socket manager for multi-path sending over WiFi +
  /// cellular in parallel. Null when mode is [MultiInterfaceMode.off]
  /// (the default — saves battery/data).
  MultiInterfaceManager? _multiIfaceManager;

  // ── iOS Native Receive ─────────────────────────────────────────────
  // Dart's RawDatagramSocket on iOS has proven defects in BOTH directions:
  //   Send: returns 0 for all destinations (fixed via native sendto).
  //   Receive: kqueue/CFSocket stops delivering read events after a burst
  //     of native sendto() calls on the same fd. The kernel socket has no
  //     data (peek=-35), but packets from the network stop arriving at the
  //     socket entirely after the initial 1-2.
  // Fix: poll the socket with native recvfrom() on a 50ms timer, completely
  // bypassing Dart's broken kqueue event delivery.
  Timer? _iosDiagTimer;
  Timer? _iosRecvTimer;
  int _iosRxEventCount = 0;
  int _iosNativeRxCount = 0;

  NetworkPacketCallback? onPacketV3;
  DiscoveryCallback? onDiscovery;
  /// Callback when a CPRB port probe packet arrives: (probeId, fromAddress, fromPort).
  void Function(Uint8List probeId, InternetAddress from, int fromPort)? onPortProbe;
  void Function(int bytes)? onBytesSent;
  void Function(int bytes)? onBytesReceived;

  /// Callback when an EPOCH_EXPIRED hint is received from a newer peer.
  /// [minVersion] is the minimum secret version the network now requires.
  void Function(int minVersion)? onEpochExpired;

  /// Rate-limit EPOCH_EXPIRED hint responses: max 1 per source IP per hour.
  final Map<String, int> _epochExpiredSentAt = {};


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
    // Socket constants differ: Linux SOL_SOCKET=1/SO_RCVBUF=8,
    // Windows+BSD/macOS/iOS SOL_SOCKET=0xFFFF/SO_RCVBUF=0x1002.
    _setRecvBuffer(_udpSocket!);
    _udpSocket!.listen(
      _onUdpEvent,
      onError: (e) {
        _log.warn('UDP socket error: $e');
        if ('$e'.contains('errno = 9') && !_reconnecting) {
          onUdpSocketDead?.call();
        }
      },
    );
    _startedAtMs = DateTime.now().millisecondsSinceEpoch;
    _log.info('UDP listening on port $port');

    // iOS: Dart's RawDatagramSocket.send() returns 0 for ALL sends (errno
    // 64/65). Find the Dart socket's fd and use native sendto() directly.
    // Same fd = same port, no §4.5.2 dual-socket risk.
    if (Platform.isIOS) {
      try {
        _iosUdpSender = IosUdpSender.open(port);
        if (_iosUdpSender != null) {
          _log.info('iOS native sendto() activated on fd=${_iosUdpSender!.fd} fd6=${_iosUdpSender!.fd6} (port $port)');
        } else {
          _log.warn('iOS native sendto(): could not find UDP fd for port $port');
        }
      } catch (e) {
        _log.warn('iOS native sendto() init failed: $e');
      }
      _startIosDiagnostics();
    }

    // Android: native sendto() on Dart's existing fd for errno visibility.
    // Allows the dead-edge detector to distinguish ENETUNREACH (socket/route
    // dead) from EHOSTUNREACH (peer offline — normal, don't count).
    if (Platform.isAndroid) {
      try {
        _androidUdpSender = AndroidUdpSender.open(port);
        if (_androidUdpSender != null) {
          _log.info('Android native sendto() activated '
              '(${AndroidUdpSender.libraryVersion() ?? "unknown"})');
        } else {
          _log.info('Android native sendto(): fd not found for port $port '
              '— using Dart socket (no errno visibility)');
        }
      } catch (e) {
        _log.warn('Android native sendto() init failed: $e');
      }
    }

    // Native UDP sender for Transport.sendUdp — bypasses Dart's
    // RawDatagramSocket.send() which silently returns 0 on Windows.
    //
    // §4.5.2 (V3.1.72+): localPort=0 (ephemeral) so this send-only socket
    // does NOT share the data port with the Dart receive socket. The same
    // dual-socket starvation hit Linux (2fbc879) and was fixed by removing
    // the native sender there; on Windows it persisted because Dart's
    // send() is broken. localPort=0 eliminates the conflict: the Dart
    // socket is the sole owner of the data port and receives 100% of
    // inbound traffic. The UDP source port is irrelevant — peers learn
    // our data port from the CLEO discovery payload (bytes 36-37), not
    // from the UDP header. Same pattern as LocalDiscovery (2026-05-15).
    if (Platform.isWindows && nativeUdpSupportedPlatform()) {
      try {
        _nativeSender = NativeUdpSender.open(
          localPort: 0,
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

    // Native IPv6 sender — same rationale as IPv4 native sender: bypass
    // Dart's IOCP-based RawDatagramSocket.send() which can crash the VM
    // on Windows when IPv6 routes are unreachable (Ingo crash report).
    if (Platform.isWindows && nativeUdpSupportedPlatform()) {
      try {
        _nativeSender6 = NativeUdpSender6.open(localPort: 0, reuseAddr: true);
        _nativeSender6!.setBuffers(sndBytes: 4 * 1024 * 1024);
        _log.info('Native UDP6 transport sender attached');
      } catch (e) {
        _log.info('Native UDP6 transport sender unavailable: $e');
        _nativeSender6 = null;
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
        final isBsd = Platform.isMacOS || Platform.isIOS;
        _udpSocket6!.setRawOption(RawSocketOption(
            isBsd ? 0xFFFF : 1, isBsd ? 0x1002 : 8, sizeBytes));
      } catch (_) {}
      _udpSocket6!.listen(
        _onUdpEvent6,
        onError: (e) {
          _log.warn('UDP6 socket error: $e');
          if ('$e'.contains('errno = 9') && !_reconnecting) {
            onUdpSocketDead?.call();
          }
        },
      );
      _log.info('UDP6 listening on port $port');
    } catch (e) {
      _log.info('IPv6 socket not available: $e');
      _udpSocket6 = null;
    }

    // iOS: rescan fd6 now that the IPv6 socket exists. The initial
    // IosUdpSender.open() above ran before _udpSocket6 was bound, so
    // cleona_ios_find_udp6_fd() returned -1 (hasIpv6=false). Without this
    // rescan, all IPv6 sends fall through to Dart's broken socket.send()
    // which always returns 0 on iOS — causing total IPv6 send failure at
    // startup until the first reconnectUdpSockets() cycle.
    if (Platform.isIOS && _iosUdpSender != null && !_iosUdpSender!.hasIpv6 &&
        _udpSocket6 != null) {
      _iosUdpSender = IosUdpSender.open(port);
      if (_iosUdpSender != null && _iosUdpSender!.hasIpv6) {
        _log.info('iOS native sendto6() activated after IPv6 bind '
            '(fd6=${_iosUdpSender!.fd6})');
      }
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
        final n4 = File('/proc/net/udp').readAsLinesSync().where((l) {
          final p = l.trim().split(RegExp(r'\s+'));
          return p.length > 1 && p[1].endsWith(':$portHex');
        }).length;
        if (n4 > 1) {
          _log.error('§4.5.2 INVARIANT VIOLATED: $n4 IPv4 UDP sockets bound to '
              'data port $port (expected 1) — a second socket captures inbound '
              'and breaks receive. Check for an extra socket on the main port.');
        } else {
          _log.debug('§4.5.2 invariant OK: $n4 IPv4 UDP socket on data port $port');
        }
        if (_udpSocket6 != null) {
          final n6 = File('/proc/net/udp6').readAsLinesSync().where((l) {
            final p = l.trim().split(RegExp(r'\s+'));
            return p.length > 1 && p[1].endsWith(':$portHex');
          }).length;
          if (n6 > 1) {
            _log.error('§4.5.2 INVARIANT VIOLATED: $n6 IPv6 UDP sockets bound to '
                'data port $port (expected 1) — a second socket captures inbound '
                'IPv6 and breaks receive. Check for an extra socket on the main port.');
          } else {
            _log.debug('§4.5.2 invariant OK: $n6 IPv6 UDP socket on data port $port');
          }
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

    // Self-probe: send a tiny packet to localhost to verify the receive path.
    // On Windows, Dart's IOCP-based RawDatagramSocket can be dead from birth
    // (never delivers RawSocketEvent.read). The watchdog at checkReceiveHealth()
    // catches sockets that stop working, but cannot detect sockets that NEVER
    // worked (_lastUdpReceiveMs stays 0 → early return). A loopback probe
    // fixes this: if the socket is alive, _onUdpEvent fires within ~50ms and
    // sets _lastUdpReceiveMs; the probe payload is too short for HMAC
    // validation so it's silently dropped by _processUdpDatagram. If the
    // socket is dead, nothing arrives, and checkReceiveHealth() can now
    // detect the 0-state after a grace period.
    if (Platform.isWindows) {
      _sendSelfProbe();
    }

    // TLS on same port as UDP (anti-censorship fallback, activates after 15 consecutive UDP failures).
    // UDP (SOCK_DGRAM) and TCP (SOCK_STREAM) live in separate kernel namespaces, so sharing the port number is safe.
    // The TCP listener itself is a plain ServerSocket, not a SecureServerSocket: §19.6.6 First-Byte-Sniffing
    // (_onRawTcpConnection) inspects the first bytes of each accepted connection and either upgrades it to TLS
    // in-process (_upgradeToTls) or hands it to the embedded HTTP server (censorship-resistant binary distribution).
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

    // Periodic cleanup for TLS capability cache — evict entries older than 24h.
    _tlsCapabilityCleanupTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _cleanupTlsCapabilityCache(),
    );
  }

  /// Try to bind plain TCP IPv4 and IPv6 listeners on [port]. Returns
  /// whether IPv4 is bound. Safe to call repeatedly — skips already-bound
  /// sockets. Binding no longer depends on the TLS [SecurityContext]: the
  /// §19.6.6 HTTP branch must keep working on platforms where TLS is
  /// unavailable (no bundled openssl — see [_findOpenssl] on Android).
  Future<bool> _tryBindTlsListeners() async {
    // Best-effort, resolved at most once (permanent failure is cached in
    // _tlsContextUnavailable — see field doc). A missing context only
    // disables the TLS-upgrade branch in _upgradeToTls; the listener still
    // binds below so plain HTTP keeps working.
    if (_tlsSecurityContext == null && !_tlsContextUnavailable) {
      final ctx = await _getOrCreateTlsContext();
      if (ctx == null) {
        _tlsContextUnavailable = true;
      } else {
        _tlsSecurityContext = ctx;
      }
    }
    if (_tlsServer == null) {
      try {
        _tlsServer = await ServerSocket.bind(InternetAddress.anyIPv4, port);
        _tlsServer!.listen(_onRawTcpConnection, onError: (e) {
          _log.debug('TCP accept error (non-fatal): $e');
        });
        _log.info('TCP (TLS+HTTP First-Byte-Sniffing) listening on port $port');
      } catch (e) {
        _log.info('TCP listener not available (port $port): $e');
      }
    }
    if (_tlsServer6 == null) {
      try {
        _tlsServer6 = await ServerSocket.bind(InternetAddress.anyIPv6, port, v6Only: true);
        _tlsServer6!.listen(_onRawTcpConnection, onError: (e) {
          _log.debug('TCP6 accept error (non-fatal): $e');
        });
        _log.info('TCP6 (TLS+HTTP First-Byte-Sniffing) listening on port $port');
      } catch (e) {
        _log.info('TCP6 listener not available (port $port): $e');
      }
    }
    return _tlsServer != null;
  }

  /// Schedule a rebind attempt with backoff (5s → 10s → 30s → 60s cap).
  /// Recovers from transient bind failures (port in TIME_WAIT after restart).
  /// Not gated on TLS-context availability (unlike the old SecureServerSocket
  /// design) — the plain TCP bind itself has no TLS dependency, so a missing
  /// openssl must not stop retrying it.
  void _scheduleTlsRebind() {
    if (_tlsRebindTimer != null) return;
    if (_tlsServer != null && _tlsServer6 != null) return;
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

  /// Evict TLS capability entries older than [_tlsCapabilityTtl] (24h).
  /// Also enforces [_tlsCapabilityMaxEntries] as a hard cap — if still
  /// over the limit after TTL eviction, remove the oldest by timestamp.
  void _cleanupTlsCapabilityCache() {
    if (_tlsCapability.isEmpty) return;
    final cutoff = DateTime.now().subtract(_tlsCapabilityTtl);
    _tlsCapability.removeWhere((_, entry) {
      final ts = entry.lastProbeAt;
      return ts != null && ts.isBefore(cutoff);
    });
    // Hard cap: if still over limit, sort by timestamp and trim oldest.
    if (_tlsCapability.length > _tlsCapabilityMaxEntries) {
      final sorted = _tlsCapability.entries.toList()
        ..sort((a, b) {
          final ta = a.value.lastProbeAt ?? DateTime(0);
          final tb = b.value.lastProbeAt ?? DateTime(0);
          return ta.compareTo(tb);
        });
      final excess = _tlsCapability.length - _tlsCapabilityMaxEntries;
      for (var i = 0; i < excess; i++) {
        _tlsCapability.remove(sorted[i].key);
      }
      _log.info('TLS capability cache: evicted $excess entries (hard cap)');
    }
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
    if (_iosDiagTimer != null) _iosRxEventCount++;
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
    if (_iosDiagTimer != null) _iosRxEventCount++;
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
          // CLEO / CPRB / CFRA / CFNK / CEEP all start with 'C' (0x43)
          m0 == 0x43 &&
              ((m1 == cleoMagic[1] && m2 == cleoMagic[2] && m3 == cleoMagic[3]) ||
                  (m1 == cprbMagic[1] && m2 == cprbMagic[2] && m3 == cprbMagic[3]) ||
                  (m1 == fragmentMagic[1] && m2 == fragmentMagic[2] && m3 == fragmentMagic[3]) ||
                  (m1 == fragmentNackMagic[1] && m2 == fragmentNackMagic[2] && m3 == fragmentNackMagic[3]) ||
                  (m1 == ceepMagic[1] && m2 == ceepMagic[2] && m3 == ceepMagic[3]));
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
      _maybeSendEpochExpiredHint(data, remoteAddress, remotePort);
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

    // EPOCH_EXPIRED hint (CEEP magic) — a newer peer tells us our build
    // is expired. Parse and notify via callback.
    if (payload.length >= 8 &&
        payload[0] == ceepMagic[0] &&
        payload[1] == ceepMagic[1] &&
        payload[2] == ceepMagic[2] &&
        payload[3] == ceepMagic[3]) {
      final minVer = NetworkSecret.parseEpochExpiredPayload(payload);
      if (minVer != null) {
        _log.warn('EPOCH_EXPIRED from $remoteAddress: network requires secret version $minVer (ours: ${NetworkSecret.currentSecretVersion})');
        onEpochExpired?.call(minVer);
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
      // Self-probe is a 4-byte raw packet to loopback — too short for V3
      // parsing. Suppress misleading HMAC-fail log for it.
      if (!(remoteAddress.isLoopback && bytes.length <= 4)) {
        _log.debug('NetworkPacketV3 parse/HMAC fail from $remoteAddress:$remotePort');
        if (isUdp) _maybeSendEpochExpiredHintV3(bytes, remoteAddress, remotePort);
      }
      return;
    }
    if (onPacketV3 == null) {
      _log.warn('V3 onPacketV3 not wired — packet dropped from $remoteAddress:$remotePort');
      return;
    }
    if (!remoteAddress.isLoopback) externalPacketsReceived++;
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
  /// falls back to Dart RawDatagramSocket. Returns bytes sent (>0 on success),
  /// 0 on Dart-send failure, or negative errno from native sendto.
  int _udpSendRaw(Uint8List data, InternetAddress address, int remotePort,
      RawDatagramSocket socket) {
    // iOS native sendto() — same fd as Dart socket, bypasses broken send()
    if (_iosUdpSender != null) {
      if (address.type == InternetAddressType.IPv6) {
        if (_iosUdpSender!.hasIpv6) {
          return _iosUdpSender!.send6(address.address, remotePort, data);
        }
      } else {
        return _iosUdpSender!.send(address.address, remotePort, data);
      }
    }
    // Android native sendto() — same fd as Dart socket, errno visibility
    if (_androidUdpSender != null) {
      if (address.type == InternetAddressType.IPv6) {
        if (_androidUdpSender!.hasIpv6) {
          return _androidUdpSender!.send6(address.address, remotePort, data);
        }
      } else {
        return _androidUdpSender!.send(address.address, remotePort, data);
      }
    }
    if (_nativeSender != null && address.type == InternetAddressType.IPv4) {
      final sent = _nativeSender!.send(address.address, remotePort, data);
      if (sent > 0) return sent;
      // Negative = errno from WSASendTo/sendto; fall through to Dart socket
      // only if the native sender returned a transient error.
    }
    if (_nativeSender6 != null && address.type == InternetAddressType.IPv6) {
      final sent = _nativeSender6!.send(address.address, remotePort, data);
      if (sent > 0) return sent;
    }
    try {
      return socket.send(data, address, remotePort);
    } catch (e) {
      _log.warn('socket.send() threw for ${address.address}:$remotePort: $e');
      return 0;
    }
  }

  /// Whether a send failure (return value <= 0 from _udpSendRaw) should count
  /// toward the dead-edge detector. On Android/iOS with native errno, only
  /// socket/route-level errors (ENETUNREACH, ENETDOWN, EBADF, ...) count.
  /// Peer-specific errors (EHOSTUNREACH, ECONNREFUSED) indicate the peer is
  /// offline, not the local socket — those are normal and must NOT trigger
  /// dead-edge escalation.
  ///
  /// Befund 11: before this iOS branch existed, `_androidUdpSender == null`
  /// was true on every iOS device (that sender is Android-only), so this
  /// method always returned `true` on iOS regardless of the actual errno —
  /// every peer-specific send failure (e.g. EHOSTUNREACH) incorrectly
  /// escalated to "socket dead". The iOS check below must run before the
  /// Android/legacy fallback so a live `_iosUdpSender` gets real Darwin
  /// errno classification instead of falling into that catch-all.
  bool _shouldCountAsSocketDead(int sendResult) {
    if (sendResult == 0) return true; // Dart socket 0-return (no native sender used)
    if (sendResult > 0) return false; // success (should never be called with this)
    if (_iosUdpSender != null) {
      return IosUdpSender.isSocketDeadErrnoDarwin(sendResult);
    }
    if (_androidUdpSender == null) return true; // no errno info → legacy path
    return AndroidUdpSender.isSocketDeadErrno(sendResult);
  }

  /// Send a NetworkPacketV3 via UDP to a specific address.
  /// Serializes the packet (via [serializeWithTag]) and delegates to
  /// [sendUdpSerialized]. For callers that send the same packet to many
  /// addresses, prefer serializing once and calling [sendUdpSerialized]
  /// directly to avoid redundant protobuf serialization.
  Future<bool> sendUdp(
    proto.NetworkPacketV3 packet,
    InternetAddress address,
    int remotePort,
  ) async {
    final data = serializeWithTag(packet);
    return sendUdpSerialized(data, address, remotePort);
  }

  /// Send pre-serialized wire bytes via UDP to a specific address.
  /// For wire bytes >1200, automatically fragments. The caller is
  /// responsible for producing [serialized] via [serializeWithTag] (which
  /// computes and embeds the Closed-Network HMAC `network_tag`).
  Future<bool> sendUdpSerialized(
    Uint8List serialized,
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
      if (_deadEdge.noteZeroSends(1) && !_reconnecting) {
        onUdpSocketDead?.call();
      }
      return false;
    }

    // Burst limiter: yield to event loop when sends pile up faster than the
    // FFI boundary can safely handle (Windows: GetStackPointerForStackBounds).
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _burstWindowStart > _burstWindowMs) {
      _burstWindowStart = nowMs;
      _burstCount = 0;
    }
    if (++_burstCount > _burstLimit) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
      _burstWindowStart = DateTime.now().millisecondsSinceEpoch;
      _burstCount = 0;
    }

    try {
      final data = serialized;

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
        // §2.9.10 CGNAT-safe fragment pacing: carrier NAT has per-flow
        // burst limits (~8 packets). Sending >8 fragments in a tight burst
        // causes total drop (zero fragments arrive → no NACK possible).
        // Two measures:
        //  1. Group-based sending: bursts of cgnatBurstSize with inter-group
        //     pauses that let the NAT drain its token bucket.
        //  2. Fragment-0 redundancy: re-send fragment 0 after all others so
        //     the receiver can create the reassembly buffer and NACK the rest
        //     even if the burst head was dropped.
        final n = wrappedFragments.length;
        final needsGroupPacing = n > _cgnatBurstSize;
        final pacing = n > 5
            ? const Duration(milliseconds: 4)
            : interFragmentDelay;
        var frag0Failed = false;
        var fragOkCount = 0;
        var lastFragErrno = 0;
        for (var i = 0; i < n; i++) {
          final sent = _udpSendRaw(wrappedFragments[i], address, remotePort, socket);
          if (sent > 0) {
            anySent = true;
            fragOkCount++;
            _log.debug('sendUdp: fragment $i/$n OK ($sent B) '
                'to ${address.address}:$remotePort');
          } else {
            if (i == 0) frag0Failed = true;
            if (sent < 0) lastFragErrno = sent;
            _log.debug('sendUdp: fragment $i/$n returned $sent '
                'for ${address.address}:$remotePort');
          }
          if (i < n - 1) {
            if (needsGroupPacing && (i + 1) % _cgnatBurstSize == 0) {
              await Future.delayed(_cgnatInterGroupDelay);
            } else if (n > pacingThreshold) {
              await Future.delayed(pacing);
            }
          }
        }
        // Fragment-0 redundancy: re-send after the full group so the
        // receiver creates the buffer even if the burst head was dropped.
        if (n > _cgnatBurstSize || frag0Failed) {
          await Future.delayed(
              needsGroupPacing ? _cgnatInterGroupDelay : const Duration(milliseconds: 5));
          final retry = _udpSendRaw(wrappedFragments[0], address, remotePort, socket);
          if (retry > 0) {
            _log.debug('sendUdp: fragment-0 redundancy OK for ${address.address}:$remotePort');
          }
        }
        if (anySent) {
          if (fragOkCount > n ~/ 2) {
            _deadEdge.noteSendSuccess();
          }
          onBytesSent?.call(data.length);
          _log.info('sendUdp: ${wrappedFragments.length} fragments (${data.length}B) '
              'sent to ${address.address}:$remotePort');
          final header = UdpFragmenter.parseHeader(fragments.first);
          if (header != null) {
            final cacheKey = '${address.address}:${header.fragmentId}';
            // Evict oldest entry if cache is full (Dart Map preserves insertion order).
            if (_sentFragmentCache.length >= _sentFragmentCacheMaxEntries &&
                !_sentFragmentCache.containsKey(cacheKey)) {
              final oldest = _sentFragmentCache.keys.first;
              _sentFragmentCache.remove(oldest);
              _sentFragmentCacheTimers[oldest]?.cancel();
              _sentFragmentCacheTimers.remove(oldest);
            }
            _sentFragmentCache[cacheKey] = wrappedFragments;
            _resetFragmentCacheTimer(cacheKey);
          }
        } else {
          _log.info('sendUdp: all ${wrappedFragments.length} fragments returned $lastFragErrno for ${address.address}:$remotePort');
          if (_shouldCountAsSocketDead(lastFragErrno) &&
              _deadEdge.noteZeroSends(wrappedFragments.length) && !_reconnecting) {
            _log.warn('UDP socket appears dead (${_deadEdge.consecutiveZeroSends} consecutive 0-sends)');
            onUdpSocketDead?.call();
          }
        }
        return anySent;
      }

      // Non-fragmented: NetworkPacketV3 carries its tag in-band (no prefix).
      final sent = _udpSendRaw(data, address, remotePort, socket);
      if (sent > 0) {
        _deadEdge.noteSendSuccess();
        onBytesSent?.call(data.length);
        return true;
      }
      final v6Hint = address.type == InternetAddressType.IPv6 ? ' [IPv6]' : '';
      _log.info('sendUdp: socket.send returned $sent for ${address.address}:$remotePort (${data.length}B)$v6Hint');
      if (_shouldCountAsSocketDead(sent) &&
          _deadEdge.noteZeroSends(1) && !_reconnecting) {
        _log.warn('UDP socket appears dead (${_deadEdge.consecutiveZeroSends} consecutive 0-sends)');
        onUdpSocketDead?.call();
      }
      return false;
    } catch (e) {
      _log.info('UDP send error to ${address.address}:$remotePort: $e');
      return false;
    }
  }

  /// Reset (or start) the 30s expiry timer for a fragment cache entry.
  /// Called on initial cache and on each NACK receipt to keep fragments
  /// alive as long as the receiver is still requesting them.
  void _resetFragmentCacheTimer(String cacheKey) {
    _sentFragmentCacheTimers[cacheKey]?.cancel();
    _sentFragmentCacheTimers[cacheKey] = Timer(const Duration(seconds: 30), () {
      _sentFragmentCache.remove(cacheKey);
      _sentFragmentCacheTimers.remove(cacheKey);
    });
  }

  /// Handle NACK: resend missing fragments from cache.
  Future<void> _handleFragmentNack(int fragmentId, List<int> missing, InternetAddress from, int fromPort) async {
    final cacheKey = '${from.address}:$fragmentId';
    final cached = _sentFragmentCache[cacheKey];
    if (cached == null) {
      _log.info('Fragment NACK: cache expired for id=$fragmentId from ${from.address}:$fromPort');
      return;
    }

    // Refresh cache TTL — receiver is still actively requesting fragments.
    _resetFragmentCacheTimer(cacheKey);

    final socket = _socketFor(from);
    var resent = 0;
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
    _log.info('Fragment NACK resend: id=$fragmentId resent=$resent/${missing.length} to ${from.address}:$fromPort');
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

  // ── §19.6.6 First-Byte-Sniffing: plain TCP → TLS or HTTP ────────────

  /// Entry point for every connection accepted on the plain TCP listener
  /// ([_tlsServer] / [_tlsServer6]). Sniffs the very first byte to tell a
  /// TLS ClientHello (record type `0x16`) apart from an HTTP request line
  /// (uppercase-ASCII method token), then dispatches via
  /// [_routeSniffedConnection]. Anything else (unrecognized protocol, or
  /// the client stalls without sending any bytes within 5s) is dropped —
  /// this port only ever speaks TLS (anti-censorship fallback) or plain
  /// HTTP (§19.6.6 binary distribution), never arbitrary TCP.
  ///
  /// IMPORTANT: the sniff subscription is *paused*, never cancelled, once a
  /// decision is made — cancelling would flip the underlying `_Socket`'s
  /// `_controller.hasListener` to false, which makes the VM's `Socket`
  /// implementation shut down the raw socket's receive direction
  /// (`_onSubscriptionStateChange` → `raw.shutdown(SocketDirection.receive)`,
  /// see `dart-sdk/lib/_internal/vm/bin/socket_patch.dart`). That shutdown
  /// silently breaks both the in-process TLS handshake (no more ClientHello
  /// bytes can arrive) and any further HTTP body read — verified live: an
  /// earlier cancel()-based version of this method made every sniffed TLS
  /// connection fail with `HandshakeException: Connection terminated during
  /// handshake`. Pausing only disables read events; no bytes are lost and
  /// the subscription is safely resumable/detachable by the callee.
  void _onRawTcpConnection(Socket client) {
    final key = '${client.remoteAddress.address}:${client.remotePort}';
    final sniff = BytesBuilder();
    Timer? timeout;
    StreamSubscription<Uint8List>? sub;

    timeout = Timer(const Duration(seconds: 5), () {
      _log.debug('TCP sniff timeout from $key — destroying connection');
      timeout = null;
      sub?.cancel();
      client.destroy();
    });

    sub = client.listen(
      (data) {
        sniff.add(data);
        final bytes = sniff.toBytes();
        if (bytes.isEmpty) return;
        timeout?.cancel();
        timeout = null;
        sub!.pause();
        _routeSniffedConnection(client, bytes, sub);
      },
      onDone: () {
        timeout?.cancel();
        client.destroy();
      },
      onError: (e) {
        _log.debug('TCP sniff error from $key: $e');
        timeout?.cancel();
        sub?.cancel();
        client.destroy();
      },
    );
  }

  /// Route a sniffed connection based on its first byte (§19.6.6). [sub] is
  /// the (paused) sniff subscription — see [_onRawTcpConnection] doc for
  /// why it must never be cancelled while the raw socket is still needed.
  void _routeSniffedConnection(
      Socket client, Uint8List firstBytes, StreamSubscription<Uint8List> sub) {
    final key = '${client.remoteAddress.address}:${client.remotePort}';
    if (firstBytes[0] == 0x16) {
      // TLS ClientHello: record content type = handshake. No legitimate
      // HTTP method starts with a control byte, so this single byte is a
      // reliable signal on its own.
      unawaited(_upgradeToTls(client, firstBytes, sub));
      return;
    }
    if (firstBytes[0] >= 0x41 && firstBytes[0] <= 0x5A) {
      // Looks like an HTTP request line (method token starts with an
      // uppercase ASCII letter, e.g. 'G'/'H' for GET/HEAD). The exact
      // method is validated again inside BinaryHttpServer, which reuses
      // this subscription instead of listening again — a Socket's stream
      // can only ever be listened to once.
      final srv = httpServer;
      if (srv == null) {
        _log.debug('TCP sniff: HTTP request from $key but no httpServer configured — destroying');
        sub.cancel();
        client.destroy();
        return;
      }
      srv.handleConnection(client, bufferedData: firstBytes, subscription: sub);
      return;
    }
    _log.debug('TCP sniff: unrecognized protocol from $key '
        '(first byte 0x${firstBytes[0].toRadixString(16).padLeft(2, '0')}) — destroying');
    sub.cancel();
    client.destroy();
  }

  /// Upgrade a sniffed plain-TCP connection to TLS in-process, preserving
  /// the existing [_onTlsConnection] pipeline unchanged. Uses the cached
  /// [_tlsSecurityContext] — see its field doc for why it's not re-resolved
  /// per connection. [bufferedData] (the bytes already consumed while
  /// sniffing) is fed back into the TLS engine via `SecureSocket.secureServer`'s
  /// `bufferedData` parameter, which exists precisely for this
  /// protocol-detection pattern; `secureServer` detaches the raw socket
  /// from [client] itself, so [sub] (still paused, never cancelled up to
  /// this point) is only cancelled here for cleanup — by then `client`'s
  /// raw socket reference is already null, so the cancel is a no-op rather
  /// than the receive-shutdown described in [_onRawTcpConnection].
  Future<void> _upgradeToTls(
      Socket client, Uint8List bufferedData, StreamSubscription<Uint8List> sub) async {
    final key = '${client.remoteAddress.address}:${client.remotePort}';
    final ctx = _tlsSecurityContext;
    if (ctx == null) {
      _log.debug('TLS upgrade for $key failed: no security context available');
      await sub.cancel();
      client.destroy();
      return;
    }
    try {
      final secure = await SecureSocket.secureServer(client, ctx, bufferedData: bufferedData);
      await sub.cancel();
      _onTlsConnection(secure);
    } catch (e) {
      _log.debug('TLS handshake failed for $key: $e');
      await sub.cancel();
      client.destroy();
    }
  }

  /// Handle incoming TLS connection (anti-censorship fallback).
  void _onTlsConnection(Socket client) {
    final key = '${client.remoteAddress.address}:${client.remotePort}';
    _log.debug('TLS connection from $key');

    final buffer = BytesBuilder();
    // TLS close-race guard (§4.1): _RawSecureSocket.read() throws
    // SocketException synchronously inside the data callback when the
    // TLS layer has already closed but raw TCP events are still enqueued.
    // That throw bypasses the stream's onError — runZonedGuarded catches it.
    runZonedGuarded(() {
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
    }, (e, st) {
      _log.debug('TLS zone error from $key: $e');
      try { client.destroy(); } catch (_) {}
    });
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
        client.destroy();
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
      final opensslBin = _findOpenssl();
      if (opensslBin == null) {
        _log.info('openssl not available on this platform');
        return null;
      }
      try {
        final result = await Process.run(opensslBin, [
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
        _log.info('openssl execution failed: $e');
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

  /// Locate the openssl binary. On Linux/macOS it's on PATH; on Windows
  /// check Git for Windows and common install locations before PATH.
  static String? _findOpenssl() {
    if (!Platform.isWindows) return 'openssl';
    const winPaths = [
      r'C:\Program Files\Git\usr\bin\openssl.exe',
      r'C:\Program Files\OpenSSL-Win64\bin\openssl.exe',
      r'C:\Program Files (x86)\OpenSSL-Win32\bin\openssl.exe',
      r'C:\msys64\usr\bin\openssl.exe',
    ];
    for (final p in winPaths) {
      if (File(p).existsSync()) return p;
    }
    // Fall back to PATH lookup
    try {
      final r = Process.runSync('where', ['openssl']);
      if (r.exitCode == 0) return 'openssl';
    } catch (_) {}
    return null;
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
    final privateIps = <String>[];
    final publicIps = <String>[];

    try {
      final interfaces4 = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
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
    } catch (_) {
      // IPv4 enumeration can fail during iOS interface transitions
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

  /// Send a 4-byte probe to 127.0.0.1:port. If the receive path is alive,
  /// _onUdpEvent fires and sets _lastUdpReceiveMs (the probe is silently
  /// dropped by _processUdpDatagram — too short for HMAC). If the IOCP
  /// socket is dead from birth, nothing arrives and checkReceiveHealth()
  /// detects the 0-state.
  void _sendSelfProbe() {
    final probe = Uint8List.fromList([0x43, 0x50, 0x52, 0x42]); // "CPRB"
    // Try Dart socket first; on Windows send() may silently return 0,
    // so also send via NativeUdpSender (ephemeral port → data port).
    try {
      _udpSocket?.send(probe, InternetAddress.loopbackIPv4, port);
    } catch (_) {}
    if (_nativeSender != null) {
      try {
        _nativeSender!.send('127.0.0.1', port, probe);
      } catch (_) {}
    }
    _log.debug('Self-probe sent to 127.0.0.1:$port');
  }

  void _setRecvBuffer(RawDatagramSocket socket) {
    try {
      final size = 2 * 1024 * 1024; // 2 MB
      final sizeBytes = Uint8List(4)..buffer.asByteData().setInt32(0, size, Endian.host);
      // Winsock uses the same SOL_SOCKET/SO_RCVBUF values as BSD.
      final isLinux = !Platform.isMacOS && !Platform.isIOS && !Platform.isWindows;
      final solSocket = isLinux ? 1 : 0xFFFF;
      final soRcvBuf = isLinux ? 8 : 0x1002;
      socket.setRawOption(RawSocketOption(solSocket, soRcvBuf, sizeBytes));
    } catch (e) {
      _log.debug('Could not set UDP receive buffer: $e');
    }
  }

  /// Windows UDP receive watchdog. Dart's IOCP-based RawDatagramSocket
  /// silently stops delivering RawSocketEvent.read after sustained traffic
  /// bursts — same defect class as the send-path 87.9% drop that
  /// libcleona_net fixed. Triggers the full network-change recovery cycle
  /// (reconnect sockets + re-PING neighbors + re-publish addresses).
  ///
  /// Dead-from-birth detection: after start(), a self-probe is sent to
  /// loopback. If the socket is alive, _lastUdpReceiveMs is set within
  /// ~50ms. If after 30s it is still 0, the socket never delivered any
  /// event — trigger recovery and re-probe.
  void checkReceiveHealth() {
    if (!Platform.isWindows) return;
    if (_reconnecting) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastUdpReceiveMs == 0) {
      // Socket has never received anything. After start() a self-probe was
      // sent; if 30s passed and it still hasn't arrived, the IOCP socket is
      // dead from birth.
      if (!_selfProbeAcked && _startedAtMs > 0 && (now - _startedAtMs) > 30000) {
        _consecutiveDeadFromBirth++;
        // Exponential backoff: after repeated dead-from-birth, delay reconnect
        // to avoid a tight 15s cycle that never recovers (observed: Dart IOCP
        // bug produces dead sockets on every RawDatagramSocket.bind(), cycling
        // 4x/min until the VM GCs the old completion port — typically 2-10min).
        final cooldownMs = _consecutiveDeadFromBirth <= 2
            ? 15000
            : min(60000, 5000 * (1 << (_consecutiveDeadFromBirth - 2)));
        final sinceLast = now - _lastReconnectMs;
        if (sinceLast < cooldownMs) {
          _selfProbeAcked = true;
          return;
        }
        _log.warn('UDP socket dead from birth (self-probe not received after '
            '${(now - _startedAtMs) ~/ 1000}s, attempt=$_consecutiveDeadFromBirth) '
            '— triggering recovery');
        _selfProbeAcked = true;
        _lastReconnectMs = now;
        onUdpSocketDead?.call();
      }
      return;
    }
    // Socket received at least once — reset dead-from-birth counter.
    _consecutiveDeadFromBirth = 0;
    final silenceMs = now - _lastUdpReceiveMs;
    if (silenceMs > 30000) {
      final sinceLast = now - _lastReconnectMs;
      if (sinceLast < 60000) return;
      if (!_staleProbeInFlight) {
        _staleProbeInFlight = true;
        _sendSelfProbe();
        return;
      }
      // Self-probe was sent on the previous tick but _lastUdpReceiveMs did
      // not advance — the IOCP socket is genuinely dead.
      _staleProbeInFlight = false;
      _log.warn('UDP receive stale (${silenceMs ~/ 1000}s silence, '
          'self-probe unreceived) — triggering recovery');
      _lastUdpReceiveMs = now;
      _lastReconnectMs = now;
      onUdpSocketDead?.call();
    } else {
      _staleProbeInFlight = false;
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

      // IPv4 bind with retry: transient failures (port-release race on iOS,
      // interface transition) resolve within ~1s. 3 attempts × 500ms covers
      // the common case without blocking onNetworkChanged excessively.
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
          break;
        } catch (e) {
          _log.warn('UDP IPv4 bind attempt ${attempt + 1}/3 failed: $e');
          if (attempt < 2) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
      }

      if (_udpSocket != null) {
        _udpSocket!.broadcastEnabled = true;
        _udpSocket!.readEventsEnabled = true;
        _setRecvBuffer(_udpSocket!);
        _udpSocket!.listen(
          _onUdpEvent,
          onError: (e) {
            _log.warn('UDP socket error: $e');
            if ('$e'.contains('errno = 9') && !_reconnecting) {
              onUdpSocketDead?.call();
            }
          },
        );
      } else {
        _log.warn('UDP reconnect: IPv4 bind failed after 3 attempts');
      }

      // IPv6 bind — independent of IPv4 success. On iOS cellular (DS-Lite,
      // CGNAT) IPv4 may be unavailable while IPv6 works fine. The old code
      // returned early on IPv4 failure, leaving BOTH sockets null.
      try {
        _udpSocket6 = await RawDatagramSocket.bind(InternetAddress.anyIPv6, port);
        _udpSocket6!.readEventsEnabled = true;
        _setRecvBuffer(_udpSocket6!);
        _udpSocket6!.listen(
          _onUdpEvent6,
          onError: (e) => _log.warn('UDP6 socket error: $e'),
        );
      } catch (e) {
        _udpSocket6 = null;
      }

      if (_udpSocket == null && _udpSocket6 == null) {
        _log.warn('UDP reconnect: both IPv4 and IPv6 bind failed — '
            'scheduling deferred recovery');
        // iOS: cancel stale polling on closed fds to prevent fd-recycling bugs
        if (Platform.isIOS) {
          _iosRecvTimer?.cancel();
          _iosRecvTimer = null;
          _iosUdpSender = null;
        }
        // Re-arm dead-edge detector so it can fire again on subsequent failures
        _deadEdge.noteReconnectCompleted();
        Future.delayed(const Duration(seconds: 5), () {
          if (_udpSocket == null && _udpSocket6 == null && !_reconnecting) {
            onUdpSocketDead?.call();
          }
        });
        return;
      }

      _deadEdge.noteReconnectCompleted();
      _lastUdpReceiveMs = 0;
      _selfProbeAcked = false;
      _staleProbeInFlight = false;
      _startedAtMs = DateTime.now().millisecondsSinceEpoch;
      if (_udpSocket != null || _udpSocket6 != null) {
        _log.info('UDP reconnect: IPv4=${_udpSocket != null} IPv6=${_udpSocket6 != null}');
      }
      if (Platform.isWindows) _sendSelfProbe();
      // iOS: old fd is stale after socket close+reopen — must rescan.
      // Restart native receive polling with the new fd.
      if (Platform.isIOS) {
        _iosRecvTimer?.cancel();
        _iosRecvTimer = null;
        _iosUdpSender = null;
        try {
          _iosUdpSender = IosUdpSender.open(port);
          if (_iosUdpSender != null) {
            _log.info('iOS native sendto() reattached on fd=${_iosUdpSender!.fd} fd6=${_iosUdpSender!.fd6}');
            if (_iosUdpSender!.hasRecvFrom) {
              _iosRecvTimer = Timer.periodic(
                  const Duration(milliseconds: 50), (_) {
                _iosNativeRecvPoll();
              });
            }
          }
        } catch (e) {
          _log.warn('iOS native sendto() reattach failed: $e');
        }
      }
      // Android: old fds are stale after socket close+reopen — rescan.
      if (Platform.isAndroid) {
        _androidUdpSender = null;
        try {
          _androidUdpSender = AndroidUdpSender.open(port);
          if (_androidUdpSender != null) {
            _log.info('Android native sendto() reattached');
          }
        } catch (e) {
          _log.warn('Android native sendto() reattach failed: $e');
        }
      }
      // Windows IPv6 native sender: close stale handle, reopen
      if (_nativeSender6 != null) {
        _nativeSender6!.close();
        _nativeSender6 = null;
        try {
          _nativeSender6 = NativeUdpSender6.open(localPort: 0, reuseAddr: true);
          _nativeSender6!.setBuffers(sndBytes: 4 * 1024 * 1024);
          _log.info('Native UDP6 transport sender reattached');
        } catch (e) {
          _log.info('Native UDP6 transport sender reattach failed: $e');
        }
      }
      // Multi-interface: refresh per-interface sockets after reconnect
      unawaited(refreshMultiInterface());
      _log.info('UDP sockets reconnected on port $port');
    } catch (e) {
      _log.warn('UDP socket reconnect failed: $e');
      if (_udpSocket == null && _udpSocket6 == null) {
        Future.delayed(const Duration(seconds: 5), () {
          if (_udpSocket == null && _udpSocket6 == null && !_reconnecting) {
            onUdpSocketDead?.call();
          }
        });
      }
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

  // ── iOS Native Receive + Diagnostics (§4.5.2 iOS) ──────────────────
  void _startIosDiagnostics() {
    _iosRxEventCount = 0;
    _iosNativeRxCount = 0;
    _iosDiagTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      final peek = _iosUdpSender?.recvPeek() ?? -999;
      final peek6 = _iosUdpSender?.recvPeek6() ?? -999;
      _log.info('iOS UDP diag: rxEvents=$_iosRxEventCount nativeRx=$_iosNativeRxCount peek=$peek peek6=$peek6');
      if ((peek == -9 || peek6 == -9) && !_reconnecting) {
        _log.warn('iOS UDP socket dead (EBADF) — triggering reconnect');
        _iosRxEventCount = 0;
        _iosNativeRxCount = 0;
        onUdpSocketDead?.call();
        return;
      }
      // Silence watchdog: if both Dart kqueue and native poll have received
      // nothing for 30+ seconds, the sockets are alive but deaf — reconnect.
      if (_lastUdpReceiveMs > 0 && !_reconnecting) {
        final silenceMs = DateTime.now().millisecondsSinceEpoch - _lastUdpReceiveMs;
        if (silenceMs > 30000) {
          _log.warn('iOS UDP silence watchdog: ${silenceMs ~/ 1000}s without receive — triggering recovery');
          _lastUdpReceiveMs = DateTime.now().millisecondsSinceEpoch;
          onUdpSocketDead?.call();
          _iosRxEventCount = 0;
          _iosNativeRxCount = 0;
          return;
        }
      }
      _iosRxEventCount = 0;
      _iosNativeRxCount = 0;
    });
    // Native receive polling: 50ms timer that calls recvfrom() in a loop.
    // This is the PRIMARY receive path on iOS — Dart's kqueue delivery is
    // unreliable and stops after burst sends on the same fd.
    if (_iosUdpSender != null && _iosUdpSender!.hasRecvFrom) {
      _iosRecvTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        _iosNativeRecvPoll();
      });
      _log.info('iOS native recvfrom() polling active (50ms interval)');
    }
    // Localhost echo: verify Dart's kqueue still works (diagnostic only).
    if (_iosUdpSender != null) {
      final echo = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
      final sent = _iosUdpSender!.send('127.0.0.1', port, echo);
      _log.info('iOS localhost echo: sendto→$sent to 127.0.0.1:$port');
      Timer(const Duration(seconds: 2), () {
        _log.info('iOS localhost echo result: '
            '${_iosRxEventCount > 0 ? "OK (rxEvents=$_iosRxEventCount)" : "FAILED — 0 read events in 2s"}');
      });
    }
  }

  void _iosNativeRecvPoll() {
    if (_iosUdpSender == null) return;
    // Poll IPv4 fd
    _iosNativeRecvPollFd(false);
    // Poll IPv6 fd
    if (_iosUdpSender!.hasIpv6) {
      _iosNativeRecvPollFd(true);
    }
  }

  void _iosNativeRecvPollFd(bool ipv6) {
    for (var i = 0; i < 100; i++) {
      final result = ipv6
          ? _iosUdpSender!.recvFrom6()
          : _iosUdpSender!.recvFrom();
      if (result == null) break;
      _iosNativeRxCount++;
      _lastUdpReceiveMs = DateTime.now().millisecondsSinceEpoch;
      if (_udpSocketMobile != null) {
        _log.info('WiFi recovered (native rx) — deactivating mobile fallback');
        stopMobileFallback();
      }
      final InternetAddress addr;
      try {
        addr = InternetAddress(result.sourceIp);
      } catch (_) {
        continue;
      }
      final datagram = Datagram(result.data, addr, result.sourcePort);
      _processUdpDatagram(datagram);
    }
  }

  Future<void> stop() async {
    _iosRecvTimer?.cancel();
    _iosRecvTimer = null;
    _iosDiagTimer?.cancel();
    _iosDiagTimer = null;
    _tlsRebindTimer?.cancel();
    _tlsRebindTimer = null;
    _tlsCapabilityCleanupTimer?.cancel();
    _tlsCapabilityCleanupTimer = null;
    _tlsRebindAttempt = 0;
    _nativeSender?.close();
    _nativeSender = null;
    _nativeSender6?.close();
    _nativeSender6 = null;
    _iosUdpSender = null;
    _androidUdpSender = null;
    _udpSocket?.close();
    _udpSocket = null;
    _udpSocket6?.close();
    _udpSocket6 = null;
    stopMobileFallback();
    _multiIfaceManager?.closeAll();
    _multiIfaceManager = null;
    await _tlsServer?.close();
    _tlsServer = null;
    await _tlsServer6?.close();
    _tlsServer6 = null;
    _log.info('Transport stopped');
  }

  // ── EPOCH_EXPIRED hint (§13.2) ──────────────────────────────────────

  /// When prefix-wrapped or V3 HMAC verification fails, check if the
  /// sender is using an expired secret. If so, respond with an
  /// EPOCH_EXPIRED hint (wrapped with their old secret so they can parse
  /// it). Rate-limited to 1 per source IP per hour.
  void _maybeSendEpochExpiredHint(
      Uint8List rawData, InternetAddress remoteAddress, int remotePort) {
    if (!NetworkSecret.verifyPrefixHmacWithExpiredHint(rawData)) return;
    _sendEpochExpiredHint(remoteAddress, remotePort);
  }

  void _maybeSendEpochExpiredHintV3(Uint8List rawData,
      InternetAddress remoteAddress, int remotePort) {
    try {
      final packet = proto.NetworkPacketV3.fromBuffer(rawData);
      final tag = Uint8List.fromList(packet.networkTag);
      if (tag.length != NetworkSecret.networkTagLength) return;
      packet.clearNetworkTag();
      final probeBytes = packet.writeToBuffer();
      if (!NetworkSecret.verifyNetworkTagWithExpiredHint(tag, probeBytes)) {
        return;
      }
      _sendEpochExpiredHint(remoteAddress, remotePort);
    } catch (_) {
      // Not parseable as V3 at all — not an expired peer, just garbage
    }
  }

  void _sendEpochExpiredHint(InternetAddress remoteAddress, int remotePort) {
    final ip = remoteAddress.address;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final lastSent = _epochExpiredSentAt[ip];
    if (lastSent != null && nowMs - lastSent < 3600000) return;
    final hint = NetworkSecret.buildEpochExpiredPacket();
    if (hint == null) return;
    _epochExpiredSentAt[ip] = nowMs;
    // Prune stale entries (keep map bounded)
    if (_epochExpiredSentAt.length > 100) {
      _epochExpiredSentAt.removeWhere((_, ts) => nowMs - ts > 3600000);
    }
    final socket = _udpSocket;
    if (socket == null) return;
    try {
      _udpSendRaw(hint, remoteAddress, remotePort, socket);
      _log.info('EPOCH_EXPIRED hint sent to $ip:$remotePort');
    } catch (_) {}
  }

  bool get isRunning => _udpSocket != null;

  /// Whether IPv6 transport is available.
  bool get hasIpv6 => _udpSocket6 != null;

  // ── Multi-Interface Send (Architecture §23.2) ─────────────────────

  /// Current multi-interface mode. Returns [MultiInterfaceMode.off] when
  /// the manager is not initialized.
  MultiInterfaceMode get multiInterfaceMode =>
      _multiIfaceManager?.mode ?? MultiInterfaceMode.auto;

  /// Whether multi-interface sockets are actively bound and ready.
  bool get isMultiInterfaceActive => _multiIfaceManager?.isActive ?? false;

  /// Active per-interface sockets (empty when mode is off or no manager).
  List<InterfaceSocket> get multiInterfaceSockets =>
      _multiIfaceManager?.sockets ?? const [];

  /// Set the multi-interface mode. Creates the manager on first non-off
  /// call; destroys it when switched back to off. Safe to call at any time.
  Future<void> setMultiInterfaceMode(MultiInterfaceMode mode) async {
    if (mode == MultiInterfaceMode.off) {
      _multiIfaceManager?.closeAll();
      _multiIfaceManager = null;
      _log.info('Multi-interface: disabled');
      return;
    }
    if (_multiIfaceManager == null) {
      _multiIfaceManager = MultiInterfaceManager(
        port: port,
        mode: mode,
        profileDir: _profileDir,
      );
      _multiIfaceManager!.onDatagram = (datagram, iface) {
        _lastUdpReceiveMs = DateTime.now().millisecondsSinceEpoch;
        _processUdpDatagram(datagram);
      };
    } else {
      _multiIfaceManager!.mode = mode;
    }
    await _multiIfaceManager!.refresh();
  }

  /// Refresh multi-interface sockets (e.g. after network change).
  /// No-op if mode is off or manager not initialized.
  Future<void> refreshMultiInterface() async {
    if (_multiIfaceManager == null) return;
    if (_multiIfaceManager!.mode == MultiInterfaceMode.off) return;
    await _multiIfaceManager!.refresh();
  }

  /// Send a serialized packet via multi-interface (§23.2).
  ///
  /// Behavior depends on mode:
  ///   - [on]:   send on ALL interfaces simultaneously
  ///   - [auto]: send on best interface only (caller uses [sendUdpMultiAll]
  ///             for retransmits)
  ///   - [off]:  falls through to false (caller uses normal sendUdp)
  ///
  /// Returns true if at least one interface succeeded.
  bool sendUdpMultiBest(
    Uint8List data,
    InternetAddress address,
    int destPort,
  ) {
    final mgr = _multiIfaceManager;
    if (mgr == null || !mgr.isActive) return false;

    if (mgr.mode == MultiInterfaceMode.on) {
      // Parallel on all interfaces
      return mgr.sendAll(data, address, destPort);
    }

    // Auto or fallback: send on cheapest interface
    final sent = mgr.sendBest(data, address, destPort);
    return sent > 0;
  }

  /// Send a serialized packet on ALL active interfaces (§23.2).
  /// Used for retransmits and high-priority messages in [auto] mode.
  /// Returns true if at least one interface succeeded.
  bool sendUdpMultiAll(
    Uint8List data,
    InternetAddress address,
    int destPort,
  ) {
    final mgr = _multiIfaceManager;
    if (mgr == null || !mgr.isActive) return false;
    return mgr.sendAll(data, address, destPort);
  }

  /// Record an ACK on the interface that delivered to [peerAddress].
  /// Used for per-interface ACK tracking (§23.2).
  void recordMultiInterfaceAck(LocalInterface iface) {
    final mgr = _multiIfaceManager;
    if (mgr == null) return;
    for (final s in mgr.sockets) {
      if (s.interfaceInfo.type == iface) {
        s.recordAck();
        return;
      }
    }
  }

  /// Record an ACK failure on a specific interface.
  void recordMultiInterfaceFailure(LocalInterface iface) {
    final mgr = _multiIfaceManager;
    if (mgr == null) return;
    for (final s in mgr.sockets) {
      if (s.interfaceInfo.type == iface) {
        s.recordFailure();
        return;
      }
    }
  }
}

/// TLS-bulk capability tristate for one destination — see Spec §5.3.
/// Cache lives only daemon-lifetime in `Transport._tlsCapability`; re-probed
/// on restart so a redeployed peer is rediscovered without manual reset.
class _TlsCapabilityEntry {
  bool? capable;
  DateTime? lastProbeAt;
  _TlsCapabilityEntry({this.capable, this.lastProbeAt});
}
