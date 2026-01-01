import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/ios_udp_sender.dart';
import 'package:cleona/core/network/native_udp_sender.dart';
import 'package:cleona/core/network/transport.dart';

/// LAN Discovery: IPv4 Broadcast + IPv4 Multicast + IPv6 Multicast.
///
/// V3.1: All three mechanisms in parallel on each burst:
///   - IPv4 Broadcast (255.255.255.255) — same /24, no IGMP needed
///   - IPv4 Multicast (239.192.67.76)   — cross-subnet, requires IGMP
///   - IPv6 Multicast (ff02::1:636c)    — if IPv6 available
///
/// V3: 3x burst on startup, then silence. Listener stays permanently active.
class LocalDiscovery {
  static const int discoveryPort = 41338;
  static const Duration burstInterval = Duration(seconds: 2);
  static const int burstCount = 3;

  /// IPv4 Multicast group for cross-subnet LAN discovery.
  /// 239.192.x.x = Organization-Local Scope (RFC 2365).
  /// 67.76 = ASCII "CL" (Cleona).
  static const String multicastGroupV4 = '239.192.67.76';

  final Uint8List nodeId;
  final int nodePort;
  final CLogger _log;
  RawDatagramSocket? _socket;
  Timer? _timer;

  /// Native UDP send-path shim (§4.5.2). Send-only — receive remains on
  /// [_socket] (Dart's RawDatagramSocket). On Linux/Windows desktop this is
  /// loaded eagerly in [start] and a missing library raises a hard error.
  /// On other platforms (Android/macOS) it stays null and all sends fall
  /// through to the Dart-RawDatagramSocket path.
  NativeUdpSender? _nativeSender;

  /// iOS native sendto() bypass for discovery. Dart's send() returns 0 on
  /// iOS (errno 64/65). Same fd-based approach as Transport.IosUdpSender —
  /// finds the discovery socket's fd and calls sendto() directly.
  IosUdpSender? _iosSender;

  // Receive-side diagnostics for LAN-Discovery (2026-05-15). The pre-existing
  // _onEvent path silently drops malformed datagrams; without per-source
  // counters we cannot tell if a Windows peer's 65k subnet-scan probes reach
  // the receiver's OS at all, or where they get filtered. These counters get rolled into
  // a periodic 60s summary so the per-receive cost stays at one integer
  // increment.
  int _rxTotal = 0;            // every RawSocketEvent.read with a datagram
  int _rxPassed = 0;           // accepted by all filters (size, magic, !self)
  int _rxWrongSize = 0;        // datagram.length != 38
  int _rxWrongMagic = 0;       // CLEO magic mismatch
  int _rxSelfId = 0;           // peerId == own nodeId
  // First-seen-from-IP tracker: first probe per distinct source-IP gets one
  // explicit log line with its disposition. Bounded so a /16 scanner can't
  // flood us with one-line-per-IP — 64 distinct sources is plenty.
  final Set<String> _rxFirstSeenIps = {};
  static const _rxFirstSeenCap = 64;
  Timer? _rxSummaryTimer;

  /// Backpressure for non-blocking send() on Windows.
  ///
  /// Dart's RawDatagramSocket.send() is non-blocking; when the kernel send-
  /// buffer is full it returns 0 instead of waiting (PowerShell's UdpClient
  /// blocks instead — verified 2026-05-09: same socket setup, PS 100%, Dart
  /// ~10% on Windows). The proper async pattern is: enable writeEvents, send,
  /// if zero await the next RawSocketEvent.write (= buffer has space again).
  /// One waiter at a time — sendBatch iterates serially with awaits, so this
  /// is safe.
  Completer<void>? _writeReady;

  /// Called when a peer is discovered.
  void Function(Uint8List nodeId, int port, InternetAddress address, int remotePort)? onDiscovered;

  LocalDiscovery({
    required this.nodeId,
    required this.nodePort,
    String? profileDir,
  }) : _log = CLogger.get('local-disc', profileDir: profileDir);

  Future<void> start() async {
    try {
      // SO_REUSEPORT is POSIX-only. On Windows the option does not exist and
      // setting it on the broadcastEnabled+multicast-joined socket leaves the
      // socket in a state where send() either throws WSAEINVAL or silently
      // returns 0 — discovered 2026-05-08 after a full day of Windows peer peers=0.
      // SO_REUSEADDR alone is sufficient on Windows for our daemon+GUI
      // co-bind use case.
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      );
      _socket!.broadcastEnabled = true;
      _socket!.readEventsEnabled = true;
      // TTL ≥ 4 so multicast can cross subnet boundaries (if IGMP routing is active).
      // Default TTL=1 stays within the local subnet — useless for cross-subnet discovery.
      _socket!.multicastHops = 4;

      // Join IPv4 multicast group for cross-subnet discovery
      try {
        _socket!.joinMulticast(InternetAddress(multicastGroupV4));
        _log.info('Joined IPv4 multicast group $multicastGroupV4');
      } catch (e) {
        _log.debug('IPv4 multicast join failed (IGMP not available): $e');
      }

      _socket!.listen(_onEvent); // Listener stays PERMANENTLY active
      _sendBurst(burstCount);
      _log.info('Local discovery started on port $discoveryPort');
      // Receive-side summary every 60s. See _logRxSummary docs.
      _rxSummaryTimer = Timer.periodic(const Duration(seconds: 60), (_) => _logRxSummary());
    } catch (e) {
      _log.warn('Local discovery failed to start: $e');
    }

    // Open native send-path on Linux/Windows desktop. Hard dependency: a
    // missing libcleona_net.so / cleona_net.dll throws here so the daemon's
    // startup error handler logs + exits non-zero. We deliberately do NOT
    // catch + log + swallow — see §4.5.2 "What happens when something is
    // wrong" for why a silent fallback is the wrong shape for this case.
    if (nativeUdpSupportedPlatform()) {
      // localPort=0: let the OS assign an ephemeral source port.
      //
      // Using discoveryPort (41338) here caused a critical receive-path bug:
      // on Linux with SO_REUSEPORT the kernel distributes unicast packets by
      // 4-tuple hash across ALL sockets bound to the same port. The Windows
      // peer's entire subnet scan (fixed src+dst IP pair) hashed to this
      // send-only socket and was never read, so the receiver never discovered
      // the Windows peer. Peer port is
      // carried in the CLEO payload (bytes 36-37), not in the UDP src-port,
      // so the source port of outgoing packets is irrelevant. (2026-05-15)
      _nativeSender = NativeUdpSender.open(
        localPort: 0,
        reuseAddr: true,
        broadcastEnable: true,
      );
      _nativeSender!.setBuffers(rcvBytes: 2 * 1024 * 1024, sndBytes: 4 * 1024 * 1024);
      _log.info('Native UDP sender attached (${NativeUdpSender.libraryVersion()})');
    }

    // iOS: Dart's RawDatagramSocket.send() returns 0 for all destinations
    // (errno 64/65). Find the discovery socket's fd and use native sendto().
    if (Platform.isIOS) {
      try {
        _iosSender = IosUdpSender.open(discoveryPort);
        if (_iosSender != null) {
          _log.info('iOS native discovery sender attached (fd=${_iosSender!.fd} port $discoveryPort)');
        } else {
          _log.warn('iOS native discovery sender: fd not found for port $discoveryPort');
        }
      } catch (e) {
        _log.warn('iOS native discovery sender init failed: $e');
      }
    }
  }

  void _onEvent(RawSocketEvent event) {
    if (event == RawSocketEvent.write) {
      // Buffer has drained — wake any send-side waiter.
      final c = _writeReady;
      _writeReady = null;
      if (c != null && !c.isCompleted) c.complete();
      return;
    }
    if (event != RawSocketEvent.read) return;
    final datagram = _socket?.receive();
    if (datagram == null) return;
    _rxTotal++;
    final data = datagram.data;
    final fromIp = datagram.address.address;
    final fromPort = datagram.port;

    // First-seen-per-source explicit log line. Useful to distinguish "no
    // probes arriving from X" from "probes arriving from X but rejected by
    // a filter". Bounded by _rxFirstSeenCap to avoid /16-scanner flood.
    final firstSeen = !_rxFirstSeenIps.contains(fromIp);
    if (firstSeen && _rxFirstSeenIps.length < _rxFirstSeenCap) {
      _rxFirstSeenIps.add(fromIp);
    }

    if (data.length != 38) {
      _rxWrongSize++;
      if (firstSeen) {
        _log.debug('RX from $fromIp:$fromPort REJECT size=${data.length} (expected 38)');
      }
      return;
    }
    if (data[0] != 0x43 || data[1] != 0x4C || data[2] != 0x45 || data[3] != 0x4F) {
      _rxWrongMagic++;
      if (firstSeen) {
        final magic = data.sublist(0, 4).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        _log.debug('RX from $fromIp:$fromPort REJECT magic=0x$magic (expected 0x434c454f "CLEO")');
      }
      return;
    }

    final peerId = Uint8List.fromList(data.sublist(4, 36));
    final peerPort = (data[36] << 8) | data[37];

    // Don't discover ourselves
    if (_bytesEqual(peerId, nodeId)) {
      _rxSelfId++;
      return;
    }

    _rxPassed++;
    if (firstSeen) {
      final pidHex = peerId.sublist(0, 4).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      _log.debug('RX from $fromIp:$fromPort ACCEPT peerId=$pidHex... peerPort=$peerPort');
    }

    onDiscovered?.call(peerId, peerPort, datagram.address, datagram.port);
  }

  /// Periodic 60s summary of receive-side counters. Logged unconditionally
  /// (even at all-zero) so a stretch of zero receives stays diagnosable —
  /// "I see 0 probes per 60s on peer A while peer B claims to be sending 65k
  /// in 130s" is the smoking gun for a layer-2/3 drop between the sender and
  /// the receiver's NIC. Started in [start], cancelled in [close].
  void _logRxSummary() {
    _log.info('LAN-discovery RX last 60s: '
        'total=$_rxTotal pass=$_rxPassed '
        'rejSize=$_rxWrongSize rejMagic=$_rxWrongMagic rejSelf=$_rxSelfId '
        'distinctIps=${_rxFirstSeenIps.length}');
    _rxTotal = 0;
    _rxPassed = 0;
    _rxWrongSize = 0;
    _rxWrongMagic = 0;
    _rxSelfId = 0;
    // _rxFirstSeenIps is intentionally NOT cleared — its purpose is "have I
    // ever seen this source in this daemon lifetime", so explicit per-IP
    // log lines fire only once. The set is bounded by _rxFirstSeenCap.
  }

  /// Send with kernel-buffer backpressure: try once, on zero re-arm
  /// writeEvents and await the next RawSocketEvent.write (buffer-drained
  /// signal from the kernel) before retrying. Up to 2 retries with a 50ms
  /// timeout per wait — well under one batch interval (20ms ... wait, fix
  /// timeout to be safe). On Linux the socket never returns 0 spuriously,
  /// so this path is dead-weight there but costs nothing.
  ///
  /// Returns the bytes-sent count (>0 on success, 0 if the kernel never
  /// drained within the per-attempt timeout).
  Future<int> _sendDrainSafe(
      Uint8List packet, InternetAddress addr, int port) async {
    // Native send-path (§4.5.2). Synchronous WSASendTo/sendto via libcleona_net.
    // Hard-required on Linux + Windows desktop; null on Android/iOS/macOS where
    // Dart's RawDatagramSocket.send() has no observed drop pattern.
    if (_nativeSender != null) {
      final n = _nativeSender!.send(addr.address, port, packet);
      // Diagnostic capture (2026-05-15): preserve native errno into scan-scope
      // counters before we clamp to the 0/positive contract that the caller
      // expects. The scan-complete log surfaces this so a silent WSASendTo
      // error (e.g. WSAEHOSTUNREACH = -10065 on Windows) becomes visible.
      if (n < 0) {
        _scanNativeFallbackNegative++;
        if (_scanNativeErrnoSamples.length < 5) {
          _scanNativeErrnoSamples.add(n);
        }
        _scanFirstNegativeIp ??= addr.address;
      } else if (n > 0) {
        _scanNativeFallbackPositive++;
      }
      return n < 0 ? 0 : n;
    }

    // iOS native sendto() bypass (same pattern as Transport.IosUdpSender).
    if (_iosSender != null) {
      final n = _iosSender!.send(addr.address, port, packet);
      if (n > 0) {
        _scanNativeFallbackPositive++;
      } else if (n < 0) {
        _scanNativeFallbackNegative++;
        if (_scanNativeErrnoSamples.length < 5) _scanNativeErrnoSamples.add(n);
        _scanFirstNegativeIp ??= addr.address;
      }
      return n < 0 ? 0 : n;
    }

    // Dart-RawDatagramSocket fallback path (Android/macOS only).
    var n = _socket?.send(packet, addr, port) ?? 0;
    if (n > 0) return n;
    for (var attempt = 0; attempt < 2 && n == 0; attempt++) {
      // Re-arm: writeEventsEnabled is auto-disabled after firing once.
      _socket?.writeEventsEnabled = true;
      final c = Completer<void>();
      _writeReady = c;
      try {
        await c.future.timeout(const Duration(milliseconds: 15));
      } on TimeoutException {
        _writeReady = null;
        // Buffer never reported drain — give up this attempt.
        return 0;
      }
      n = _socket?.send(packet, addr, port) ?? 0;
    }
    return n;
  }

  /// Sends count packets at burstInterval spacing, then silence.
  void _sendBurst(int count) {
    _timer?.cancel();
    var remaining = count;
    _trySendPacket(); // First packet immediately
    remaining--;
    if (remaining <= 0) {
      _timer = null;
      return;
    }
    _timer = Timer.periodic(burstInterval, (_) {
      _trySendPacket();
      remaining--;
      if (remaining <= 0) {
        _timer?.cancel();
        _timer = null; // Silence — no continuous firing
      }
    });
  }

  void _trySendPacket() {
    final packet = Transport.buildDiscoveryPacket(nodeId, nodePort);
    // Native send-path (§4.5.2) if attached, else Dart's RawDatagramSocket.
    // Returns raw native value (incl. negative errno) so the caller can log
    // the actual failure mode — earlier code clobbered <0 to 0, which left
    // "returned 0 (buffer full or socket dead)" as the only visible signal
    // for both backpressure AND hard WSASendTo errors. Confusion 2026-05-15.
    int sendUdp(String ip, int port) {
      if (_nativeSender != null) {
        return _nativeSender!.send(ip, port, packet);
      }
      if (_iosSender != null) {
        return _iosSender!.send(ip, port, packet);
      }
      return _socket?.send(packet, InternetAddress(ip), port) ?? 0;
    }

    // IPv4 Broadcast (same /24 subnet — works everywhere)
    try {
      final n = sendUdp('255.255.255.255', discoveryPort);
      if (n <= 0) {
        _log.debug('discovery broadcast send → n=$n (>0=bytes, 0=backpressure, <0=errno)');
      }
    } catch (e) {
      _log.debug('discovery broadcast send failed: $e');
    }
    // IPv4 Multicast (cross-subnet — requires IGMP on router)
    try {
      final n = sendUdp(multicastGroupV4, discoveryPort);
      if (n <= 0) {
        _log.debug('discovery multicast send to $multicastGroupV4 → n=$n (>0=bytes, 0=backpressure, <0=errno)');
      }
    } catch (e) {
      _log.debug('discovery multicast send to $multicastGroupV4 failed: $e');
    }
  }

  /// Trigger fast discovery burst (on network change): 3x burst, then silence.
  void triggerFastDiscovery() {
    _sendBurst(burstCount);
  }

  /// Send a single unicast discovery probe to a specific (ip, port). Used by
  /// `CleonaService.addManualPeer` when the user supplies an IP+port pair
  /// without prior knowledge of the recipient's deviceId — V3
  /// InfrastructureFrame paths require a known deviceId, but the LAN-Discovery
  /// wire format only carries the SENDER's nodeId and lets the receiver learn
  /// us by reverse-direction. The recipient's `LocalDiscovery._onEvent`
  /// handles the packet just like a multicast probe and triggers
  /// `onDiscovered` → routing-table registration → standard V3 BOOT-bonding.
  ///
  /// `port` defaults to `discoveryPort` (41338, the well-known port every
  /// daemon binds for LAN-Discovery). Callers MAY pass a non-standard port
  /// for setups where the recipient's discovery socket is bound elsewhere
  /// (typically only test fixtures).
  ///
  /// No-op when the socket is closed (e.g. start() failed). The probe is
  /// fire-and-forget; the discovery response (if any) arrives asynchronously
  /// on the receive listener established in `start()`.
  void sendUnicastDiscovery(String ip, [int? port]) {
    if (_socket == null) return;
    final packet = Transport.buildDiscoveryPacket(nodeId, nodePort);
    final targetPort = port ?? discoveryPort;
    try {
      if (_nativeSender != null) {
        _nativeSender!.send(ip, targetPort, packet);
      } else if (_iosSender != null) {
        _iosSender!.send(ip, targetPort, packet);
      } else {
        _socket!.send(packet, InternetAddress(ip), targetPort);
      }
    } catch (e) {
      _log.debug('Unicast discovery to $ip:$targetPort failed: $e');
    }
  }

  // ── Cross-Subnet Unicast Scan ──────────────────────────────────────

  Timer? _scanTimer;
  bool _scanActive = false;
  // Aggregated diagnostics for the subnet scan — per-IP logging would flood
  // at 500 sends/s on a stuck socket. We surface the totals when the scan
  // ends (peer found / scan complete) so a Windows-side socket-stall is
  // visible without log-spam.
  int _scanZeroSends = 0;
  String? _scanLastException;
  int _scanTotalAttempts = 0;
  int _scanRetrySaves = 0;

  // Per-class send-outcome counters (added 2026-05-15 to investigate Windows
  // "65k probes claimed sent, 0 received by peer"). Without these, the
  // scan-complete summary collapses positive Dart-socket returns, positive
  // native-sender returns, and silent kernel drops into a single "sent=N"
  // value — useless for narrowing the loss-layer.
  int _scanDartFirstPositive = 0;   // Dart-socket first try returned > 0
  int _scanNativeFallbackPositive = 0; // native sender returned > 0 after fallback
  int _scanNativeFallbackNegative = 0; // native sender returned < 0 (errno)
  // First few distinct errno values from the native sender. Bounded to keep
  // the log line short; sample suffices because errnos rarely vary across a
  // single scan (same socket, same NIC, same target subnet class).
  final Set<int> _scanNativeErrnoSamples = {};
  // First IP for which native sender returned a negative — useful when the
  // errno is ambiguous (e.g. EHOSTUNREACH on .1 = router; on .201 = actual
  // peer). Only the first occurrence is captured.
  String? _scanFirstNegativeIp;

  /// Scans all /24 subnets in the own /16 range via unicast on port 41338.
  /// Sends the standard CLEO discovery packet to each host.
  /// Scan order: DHCP hotspots first (.1, .50, .100, .150, .200), then fill.
  /// Stops immediately when [shouldStop] returns true (peer found).
  ///
  /// [localIps] — own IPs to determine the /16 range and skip own subnet.
  /// [shouldStop] — callback checked after each batch; return true to abort.
  void startSubnetScan(List<String> localIps, bool Function() shouldStop) {
    if (_scanActive || _socket == null) return;
    if (localIps.isEmpty) return;

    // Determine /16 prefix from first RFC1918 private IP.
    // Skip CGNAT (100.64/10), carrier (192.0.0/24), and other non-private
    // addresses that localIps may list first (e.g. Android Mobilfunk).
    String? ownIp;
    for (final ip in localIps) {
      final o = ip.split('.');
      if (o.length != 4) continue;
      final a0 = int.tryParse(o[0]);
      final b0 = int.tryParse(o[1]);
      if (a0 == null || b0 == null) continue;
      if (a0 == 10 || (a0 == 172 && b0 >= 16 && b0 <= 31) || (a0 == 192 && b0 == 168)) {
        ownIp = ip;
        break;
      }
    }
    if (ownIp == null) return;
    final octets = ownIp.split('.');
    final a = int.parse(octets[0]);
    final b = int.parse(octets[1]);
    final ownC = int.parse(octets[2]);

    _scanActive = true;
    _scanZeroSends = 0;
    _scanLastException = null;
    _scanTotalAttempts = 0;
    _scanRetrySaves = 0;
    _scanDartFirstPositive = 0;
    _scanNativeFallbackPositive = 0;
    _scanNativeFallbackNegative = 0;
    _scanNativeErrnoSamples.clear();
    _scanFirstNegativeIp = null;
    _log.info('Subnet scan: starting on $a.$b.0.0/16 (own /$a.$b.$ownC.0)');

    final packet = Transport.buildDiscoveryPacket(nodeId, nodePort);

    // Build scan order: DHCP hotspots first per subnet
    // Offsets: 1, 50, 100, 150, 200, 2, 51, 101, 151, 201, 3, 52, ...
    final hotspots = [1, 50, 100, 150, 200];
    final iterator = _subnetScanIterator(a, b, ownC, hotspots);

    // Send in small batches with proportional pauses, sustaining ~500 pps
    // average AS SPECIFIED BY THE ARCHITECTURE (Architecture §Discovery: "~500
    // packets/s = ~130s maximum"). Earlier implementation (batch=50, delay=100ms)
    // hit the same average but with a 50× over-spec spike (50 sends in <1ms),
    // which on Windows causes the stack to drop ~80% of each burst at fixed
    // positions (verified 2026-05-09 via pktmon: only positions 0,5,10,…,45 of
    // each 50-burst leave the NIC; subnets like 192.0.2.0/24 — Bootstrap! —
    // are never contacted because their array index never coincides with a
    // surviving slot). Spreading the burst (10 sends per 20ms) keeps the same
    // average rate but stays well below the Windows stack's per-tick threshold.
    // Linux behaviour is unchanged because Linux tolerated the spike already.
    const batchSize = 10;
    const batchDelay = Duration(milliseconds: 20);

    Future<void> sendBatch() async {
      if (!_scanActive || shouldStop()) {
        _scanActive = false;
        if (shouldStop()) {
          _log.info('Subnet scan: peer found, stopping ${_scanBreakdown()}');
        }
        _scanTimer?.cancel();
        _scanTimer = null;
        return;
      }

      var sent = 0;
      while (sent < batchSize) {
        final ip = iterator();
        if (ip == null) {
          // Scan complete
          _scanActive = false;
          _scanTimer?.cancel();
          _scanTimer = null;
          _log.info('Subnet scan: complete, no peers found ${_scanBreakdown()}');
          return;
        }
        _scanTotalAttempts++;
        try {
          // Backpressure-aware send: on the first attempt we go to the
          // kernel directly (fast path); if the buffer is full we await the
          // next write-ready event, up to 2 retries × 15ms. PowerShell's
          // UdpClient.Send blocks on full-buffer (0% zero-rate on Windows);
          // Dart's RawDatagramSocket.send() is non-blocking and returns 0,
          // which we now propagate as backpressure instead of swallowing.
          // Verified 2026-05-09 baseline (synchronous retries): zero=58194
          // of 65025 (~89% drop). Expected post-fix: drop rate close to
          // PowerShell-equivalent (<5%).
          //
          // Diagnostics added 2026-05-15: split first-try-positive vs
          // fallback-positive vs fallback-negative so the scan-complete log
          // shows which layer believes it sent (Dart-socket Reports OK, but
          // packets do not arrive at the receiver — observed on Windows).
          final int firstTry;
          if (_iosSender != null) {
            final n = _iosSender!.send(ip, discoveryPort, packet);
            firstTry = n > 0 ? n : 0;
          } else {
            firstTry = _socket?.send(packet, InternetAddress(ip), discoveryPort) ?? 0;
          }
          if (firstTry > 0) {
            _scanDartFirstPositive++;
          } else {
            // Dart-socket returned 0 — fall back to native sender path.
            // _sendDrainSafe records the native-side outcome before returning
            // a clamped >=0 value to keep the legacy caller contract.
            final n = await _sendDrainSafe(packet, InternetAddress(ip), discoveryPort);
            if (n == 0) {
              _scanZeroSends++;
            } else {
              _scanRetrySaves++;
            }
          }
        } catch (e) {
          _scanLastException ??= '$e';
        }
        sent++;
      }

      _scanTimer = Timer(batchDelay, () { sendBatch(); });
    }

    sendBatch();
  }

  /// Compact breakdown of the current subnet-scan counters. Format chosen
  /// to fit on one log line and to distinguish all three layers the packet
  /// passes through on a Windows daemon:
  ///   dartPos = Dart-socket first try returned > 0 (kernel accepted it)
  ///   natPos  = native-sender fallback returned > 0 (WSASendTo accepted)
  ///   natNeg  = native-sender returned negative errno (WSASendTo refused)
  ///   zero    = native-sender returned 0 (kernel still drained — backpressure
  ///             exceeded retry budget)
  String _scanBreakdown() {
    final errnos = _scanNativeErrnoSamples.isEmpty
        ? 'none'
        : _scanNativeErrnoSamples.toList().toString();
    return '(sent=$_scanTotalAttempts '
        'dartPos=$_scanDartFirstPositive '
        'natPos=$_scanNativeFallbackPositive '
        'natNeg=$_scanNativeFallbackNegative '
        'zero=$_scanZeroSends '
        'retries=$_scanRetrySaves '
        'errnos=$errnos '
        'firstNegIp=${_scanFirstNegativeIp ?? "none"} '
        'lastErr=$_scanLastException)';
  }

  /// Generates IPs in DHCP-hotspot-first order across all /24 subnets.
  /// Returns null when all addresses have been enumerated.
  static String? Function() _subnetScanIterator(
      int a, int b, int ownC, List<int> hotspots) {
    // Phase 1: hotspots (1, 50, 100, 150, 200) across all subnets
    // Phase 2: fill remaining hosts (skip hotspots) across all subnets
    var phase = 0; // 0 = hotspots, 1 = fill
    var subnetIdx = 0;
    var hostIdx = 0;

    // Build subnet order: other /24s first, own /24 last.
    //
    // The own /24 is placed at the END rather than skipped entirely. This
    // handles topologies where the own /24 is split across L2 segments joined
    // by ARP-proxy (e.g. parprouted: KVM bridge ↔ WiFi). In that topology
    // IPv4-broadcast does NOT cross the proxy boundary, so same-/24 peers on
    // a different segment are unreachable via burst-discovery and only found by
    // unicast scan. Since ICMP (and therefore unicast UDP) routes correctly
    // via the ARP-proxy/IP-forward chain, scanning the own /24 does reach
    // them. Cost: 255 extra probes ≈ 0.5 s on a 500 pps budget — negligible.
    // (2026-05-15 fix: was always skipping ownC, causing cross-platform peer misses)
    final subnets = <int>[];
    for (var c = 0; c < 256; c++) {
      if (c != ownC) subnets.add(c);
    }
    subnets.add(ownC); // own /24 last

    return () {
      while (true) {
        if (phase == 0) {
          // Hotspot phase
          if (subnetIdx >= subnets.length) {
            // All subnets done for this hotspot
            subnetIdx = 0;
            hostIdx++;
            if (hostIdx >= hotspots.length) {
              // All hotspots done → fill phase
              phase = 1;
              subnetIdx = 0;
              hostIdx = 0;
              continue;
            }
          }
          final c = subnets[subnetIdx++];
          return '$a.$b.$c.${hotspots[hostIdx]}';
        } else {
          // Fill phase: hosts 2..254 skipping hotspots
          while (hostIdx < 255) {
            final host = hostIdx + 1; // 1..254
            if (subnetIdx >= subnets.length) {
              subnetIdx = 0;
              hostIdx++;
              continue;
            }
            if (hotspots.contains(host)) {
              // Skip hotspots (already scanned)
              if (subnetIdx == 0) hostIdx++;
              subnetIdx = 0;
              continue;
            }
            final c = subnets[subnetIdx++];
            if (subnetIdx >= subnets.length) {
              subnetIdx = 0;
              hostIdx++;
            }
            return '$a.$b.$c.$host';
          }
          return null; // All done
        }
      }
    };
  }

  void stopSubnetScan() {
    _scanActive = false;
    _scanTimer?.cancel();
    _scanTimer = null;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _rxSummaryTimer?.cancel();
    _rxSummaryTimer = null;
    stopSubnetScan();
    _socket?.close();
    _socket = null;
    _nativeSender?.close();
    _nativeSender = null;
    _iosSender = null;
  }
}

/// IPv6 multicast discovery on ff02::1:636c.
/// V3: 3x burst on startup, then silence. Listener stays permanently active.
class MulticastDiscovery {
  static const Duration burstInterval = Duration(seconds: 2);
  static const int burstCount = 3;

  /// IPv6 multicast group: ff02::1:636c (link-local, "cl" = Cleona).
  static const String multicastGroupV6 = 'ff02::1:636c';

  final Uint8List nodeId;
  final int nodePort;
  final CLogger _log;
  RawDatagramSocket? _socket;
  Timer? _timer;

  void Function(Uint8List nodeId, int port, InternetAddress address, int remotePort)? onDiscovered;

  MulticastDiscovery({
    required this.nodeId,
    required this.nodePort,
    String? profileDir,
  }) : _log = CLogger.get('multicast', profileDir: profileDir);

  Future<void> start() async {
    // Check if IPv6 is available first
    if (!await _isIpv6Available()) {
      _log.info('IPv6 unavailable, skipping multicast discovery');
      return;
    }
    try {
      // Bind to discoveryPort (41338), NOT nodePort. All nodes share the same
      // fixed discovery port so multicast packets reach every peer regardless
      // of their data port. Binding to nodePort caused a §4.5.2-class bug:
      // on Linux with SO_REUSEPORT the kernel distributed inbound IPv6 unicast
      // packets between Transport._udpSocket6 and this socket — packets that
      // landed here were silently dropped (not 38-byte CLEO frames). Same
      // pattern as LocalDiscovery using discoveryPort for IPv4.
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv6,
        LocalDiscovery.discoveryPort,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      );
      _socket!.readEventsEnabled = true;

      try {
        _socket!.joinMulticast(InternetAddress(multicastGroupV6));
      } catch (e) {
        _log.debug('IPv6 multicast join failed: $e');
      }

      _socket!.listen(_onEvent); // Listener stays PERMANENTLY active
      _sendBurst(burstCount);
      _log.info('IPv6 multicast discovery started on port ${LocalDiscovery.discoveryPort}');
    } catch (e) {
      _log.warn('IPv6 multicast discovery unavailable: $e');
      _socket?.close();
      _socket = null;
    }
  }

  static Future<bool> _isIpv6Available() async {
    try {
      final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv6);
      return ifaces.any((iface) => iface.addresses.any((a) => !a.isLoopback));
    } catch (_) {
      return false;
    }
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _socket?.receive();
    if (datagram == null) return;
    final data = datagram.data;
    if (data.length != 38) return;
    if (data[0] != 0x43 || data[1] != 0x4C || data[2] != 0x45 || data[3] != 0x4F) return;

    final peerId = Uint8List.fromList(data.sublist(4, 36));
    final peerPort = (data[36] << 8) | data[37];

    if (_bytesEqual(peerId, nodeId)) return;

    onDiscovered?.call(peerId, peerPort, datagram.address, datagram.port);
  }

  void _sendBurst(int count) {
    _timer?.cancel();
    var remaining = count;
    if (!_trySendPacket()) return;
    remaining--;
    if (remaining <= 0) {
      _timer = null;
      return;
    }
    _timer = Timer.periodic(burstInterval, (_) {
      _trySendPacket();
      remaining--;
      if (remaining <= 0) {
        _timer?.cancel();
        _timer = null;
      }
    });
  }

  bool _trySendPacket() {
    if (_socket == null) return false;
    final packet = Transport.buildDiscoveryPacket(nodeId, nodePort);
    try {
      // IPv6 multicast: Dart's send() is the only path. The iOS native
      // sendto() shim only supports AF_INET (IPv4). On iOS, IPv6 multicast
      // may silently fail — IPv4 broadcast/unicast via LocalDiscovery is
      // the primary iOS discovery mechanism.
      final n = _socket!.send(packet, InternetAddress(multicastGroupV6), LocalDiscovery.discoveryPort);
      if (n <= 0 && Platform.isIOS) {
        _log.debug('IPv6 multicast send → n=$n (expected on iOS — Dart send broken, no IPv6 native shim)');
      }
      return true;
    } catch (e) {
      _log.debug('IPv6 multicast send failed: $e');
      stop();
      return false;
    }
  }

  void triggerFastDiscovery() {
    if (_socket == null) return;
    _sendBurst(burstCount);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
  }
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
