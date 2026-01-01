import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/network/clogger.dart';
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

  /// Called when a peer is discovered.
  void Function(Uint8List nodeId, int port, InternetAddress address, int remotePort)? onDiscovered;

  LocalDiscovery({
    required this.nodeId,
    required this.nodePort,
    String? profileDir,
  }) : _log = CLogger.get('local-disc', profileDir: profileDir);

  Future<void> start() async {
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPort, reuseAddress: true, reusePort: true);
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
    } catch (e) {
      _log.warn('Local discovery failed to start: $e');
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

    // Don't discover ourselves
    if (_bytesEqual(peerId, nodeId)) return;

    onDiscovered?.call(peerId, peerPort, datagram.address, datagram.port);
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
    // IPv4 Broadcast (same /24 subnet — works everywhere)
    try {
      _socket?.send(packet, InternetAddress('255.255.255.255'), discoveryPort);
    } catch (_) {}
    // IPv4 Multicast (cross-subnet — requires IGMP on router)
    try {
      _socket?.send(packet, InternetAddress(multicastGroupV4), discoveryPort);
    } catch (_) {}
  }

  /// Trigger fast discovery burst (on network change): 3x burst, then silence.
  void triggerFastDiscovery() {
    _sendBurst(burstCount);
  }

  // ── Cross-Subnet Unicast Scan ──────────────────────────────────────

  Timer? _scanTimer;
  bool _scanActive = false;

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

    // Determine /16 prefix from first private IP
    final ownIp = localIps.first;
    final octets = ownIp.split('.');
    if (octets.length != 4) return;
    final a = int.tryParse(octets[0]);
    final b = int.tryParse(octets[1]);
    final ownC = int.tryParse(octets[2]);
    if (a == null || b == null || ownC == null) return;
    // Only scan private ranges
    if (a != 10 && a != 172 && a != 192) return;

    _scanActive = true;
    _log.info('Subnet scan: starting on $a.$b.0.0/16 (own /$a.$b.$ownC.0)');

    final packet = Transport.buildDiscoveryPacket(nodeId, nodePort);

    // Build scan order: DHCP hotspots first per subnet
    // Offsets: 1, 50, 100, 150, 200, 2, 51, 101, 151, 201, 3, 52, ...
    final hotspots = [1, 50, 100, 150, 200];
    final iterator = _subnetScanIterator(a, b, ownC, hotspots);

    // Send in batches of 50, with 100ms pause between batches (~500/s)
    const batchSize = 50;
    const batchDelay = Duration(milliseconds: 100);

    void sendBatch() {
      if (!_scanActive || shouldStop()) {
        _scanActive = false;
        if (shouldStop()) {
          _log.info('Subnet scan: peer found, stopping');
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
          _log.info('Subnet scan: complete, no peers found');
          return;
        }
        try {
          _socket?.send(packet, InternetAddress(ip), discoveryPort);
        } catch (_) {}
        sent++;
      }

      _scanTimer = Timer(batchDelay, sendBatch);
    }

    sendBatch();
  }

  /// Generates IPs in DHCP-hotspot-first order across all /24 subnets.
  /// Returns null when all addresses have been enumerated.
  static String? Function() _subnetScanIterator(
      int a, int b, int ownC, List<int> hotspots) {
    // Phase 1: hotspots (1, 50, 100, 150, 200) across all subnets
    // Phase 2: fill remaining hosts (skip hotspots) across all subnets
    var phase = 0; // 0 = hotspots, 1 = fill
    var subnetIdx = 0; // 0..255 (skips ownC)
    var hostIdx = 0;

    // Build subnet order: 0, 1, 2, ... but skip ownC
    final subnets = <int>[];
    for (var c = 0; c < 256; c++) {
      if (c != ownC) subnets.add(c);
    }

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
    stopSubnetScan();
    _socket?.close();
    _socket = null;
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
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv6, nodePort, reuseAddress: true, reusePort: true);
      _socket!.readEventsEnabled = true;

      try {
        _socket!.joinMulticast(InternetAddress(multicastGroupV6));
      } catch (e) {
        _log.debug('IPv6 multicast join failed: $e');
      }

      _socket!.listen(_onEvent); // Listener stays PERMANENTLY active
      _sendBurst(burstCount);
      _log.info('IPv6 multicast discovery started on port $nodePort');
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
      _socket!.send(packet, InternetAddress(multicastGroupV6), nodePort);
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
