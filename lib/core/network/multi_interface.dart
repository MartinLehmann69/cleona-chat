import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/network/clogger.dart';

/// Architecture 23.2 — Multi-Interface Send.
///
/// Enumerates local network interfaces, classifies them (wifi/cellular/
/// ethernet/other), and maintains per-interface UDP sockets so the transport
/// layer can send packets over a specific physical path.
///
/// Battery/data policy is governed by [MultiInterfaceMode]:
///   - [off]: single socket on 0.0.0.0 (default, saves battery+data)
///   - [on]:  parallel send on ALL active interfaces for every packet
///   - [auto]: primary interface for first send; parallel only for retransmits
///             and high-priority messages

/// User-facing multi-interface mode setting.
/// Persisted as `multi_interface_mode` in the profile JSON.
enum MultiInterfaceMode {
  /// Single socket (0.0.0.0), no multi-path. Saves battery and
  /// mobile data. Identical to pre-23.2 behavior.
  off,

  /// Parallel send on all active interfaces for every packet. Maximum
  /// reliability at the cost of doubled data consumption on metered
  /// connections.
  on,

  /// Smart mode (default): use the cheapest interface (wifi preferred) for
  /// normal sends. Parallel send on all interfaces only for:
  ///   - ACK-timeout retransmits
  ///   - High-priority messages (e.g. call signaling)
  /// Balances reliability vs. data cost.
  auto,
}

/// Classification of a local network interface.
enum LocalInterface {
  wifi,
  cellular,
  ethernet,
  other,
}

/// Snapshot of a detected local network interface.
class NetworkInterfaceInfo {
  /// OS-reported interface name (e.g. "wlan0", "eth0", "rmnet0").
  final String name;

  /// Classified type.
  final LocalInterface type;

  /// All IPv4 addresses on this interface (non-loopback).
  final List<InternetAddress> ipv4Addresses;

  /// All IPv6 addresses on this interface (non-loopback, non-link-local).
  final List<InternetAddress> ipv6Addresses;

  const NetworkInterfaceInfo({
    required this.name,
    required this.type,
    required this.ipv4Addresses,
    required this.ipv6Addresses,
  });

  /// Best IPv4 address for binding a socket (first non-loopback).
  InternetAddress? get primaryIpv4 =>
      ipv4Addresses.isNotEmpty ? ipv4Addresses.first : null;

  @override
  String toString() =>
      'NetworkInterfaceInfo($name, ${type.name}, '
      'v4=${ipv4Addresses.map((a) => a.address).join(",")}, '
      'v6=${ipv6Addresses.map((a) => a.address).join(",")})';
}

/// Per-interface bound UDP socket with its metadata.
class InterfaceSocket {
  final NetworkInterfaceInfo interfaceInfo;
  final RawDatagramSocket socket;
  final InternetAddress boundAddress;

  /// Per-interface send statistics for ACK-rate tracking.
  int sendCount = 0;
  int ackCount = 0;
  int failCount = 0;

  InterfaceSocket({
    required this.interfaceInfo,
    required this.socket,
    required this.boundAddress,
  });

  /// ACK success rate for this interface (0.0 .. 1.0).
  /// Returns 1.0 if no sends have been tracked yet.
  double get ackRate {
    final total = ackCount + failCount;
    if (total == 0) return 1.0;
    return ackCount / total;
  }

  /// Record a successful ACK on this interface.
  void recordAck() => ackCount++;

  /// Record an ACK failure (timeout) on this interface.
  void recordFailure() => failCount++;

  void close() {
    socket.close();
  }
}

/// Enumerates and classifies local network interfaces.
///
/// Classification heuristics by interface name:
///   - wifi:     wlan*, wl*, en0 (macOS), Wi-Fi (Windows)
///   - cellular: rmnet*, wwan*, pdp_ip*, cellular*, Mobile* (Windows)
///   - ethernet: eth*, en[1-9]* (macOS), enp*, ens*, Ethernet (Windows)
///   - other:    everything else (VPN, tunnels, etc.)
class InterfaceEnumerator {
  static final _log = CLogger.get('multi-iface');

  /// Detect all active non-loopback network interfaces.
  static Future<List<NetworkInterfaceInfo>> enumerate() async {
    final result = <String, _InterfaceBuilder>{};

    // IPv4 interfaces
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final iface in ifaces) {
        final builder = result.putIfAbsent(
          iface.name,
          () => _InterfaceBuilder(iface.name),
        );
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.address != '0.0.0.0') {
            builder.ipv4.add(addr);
          }
        }
      }
    } catch (e) {
      _log.warn('IPv4 interface enumeration failed: $e');
    }

    // IPv6 interfaces (global only — skip loopback, link-local, tunnel)
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv6,
      );
      for (final iface in ifaces) {
        final builder = result.putIfAbsent(
          iface.name,
          () => _InterfaceBuilder(iface.name),
        );
        for (final addr in iface.addresses) {
          if (addr.isLoopback || addr.isLinkLocal) continue;
          if (_isTunnelIpv6(addr.address)) continue;
          builder.ipv6.add(addr);
        }
      }
    } catch (e) {
      _log.debug('IPv6 interface enumeration failed: $e');
    }

    // Build result, filtering out interfaces with no usable addresses
    final out = <NetworkInterfaceInfo>[];
    for (final b in result.values) {
      if (b.ipv4.isEmpty && b.ipv6.isEmpty) continue;
      out.add(NetworkInterfaceInfo(
        name: b.name,
        type: classifyInterface(b.name),
        ipv4Addresses: b.ipv4,
        ipv6Addresses: b.ipv6,
      ));
    }

    _log.info('Enumerated ${out.length} interfaces: '
        '${out.map((i) => "${i.name}(${i.type.name})").join(", ")}');
    return out;
  }

  /// Classify an interface name to [LocalInterface].
  static LocalInterface classifyInterface(String name) {
    final lower = name.toLowerCase();

    // WiFi
    if (lower.startsWith('wlan') || lower.startsWith('wl')) {
      return LocalInterface.wifi;
    }
    // macOS: en0 is typically WiFi
    if (lower == 'en0' && (Platform.isMacOS || Platform.isIOS)) {
      return LocalInterface.wifi;
    }
    // Windows
    if (lower.startsWith('wi-fi') || lower.contains('wireless')) {
      return LocalInterface.wifi;
    }

    // Cellular
    if (lower.startsWith('rmnet') ||
        lower.startsWith('wwan') ||
        lower.startsWith('pdp_ip') ||
        lower.startsWith('cellular') ||
        lower.startsWith('mobile')) {
      return LocalInterface.cellular;
    }

    // Ethernet
    if (lower.startsWith('eth') ||
        lower.startsWith('enp') ||
        lower.startsWith('ens') ||
        lower.startsWith('ethernet')) {
      return LocalInterface.ethernet;
    }
    // macOS: en1+ are typically Ethernet (en0 is WiFi, handled above)
    if ((Platform.isMacOS || Platform.isIOS) &&
        lower.startsWith('en') &&
        lower.length >= 3) {
      return LocalInterface.ethernet;
    }

    return LocalInterface.other;
  }

  /// Tunnel IPv6 address classification — these addresses are not useful
  /// for multi-interface binding (Teredo, 6to4, documentation, IPv4-mapped).
  static bool _isTunnelIpv6(String ip) {
    if (!ip.contains(':')) return false;
    final lower = ip.toLowerCase();
    final core = lower.split('%').first;
    if (core.startsWith('2001:0:') || core.startsWith('2001::')) return true;
    if (core.startsWith('2002:')) return true;
    if (core.startsWith('2001:db8:')) return true;
    if (core.startsWith('::ffff:')) return true;
    return false;
  }
}

/// Internal builder for grouping addresses by interface name.
class _InterfaceBuilder {
  final String name;
  final List<InternetAddress> ipv4 = [];
  final List<InternetAddress> ipv6 = [];
  _InterfaceBuilder(this.name);
}

/// Manages the lifecycle of per-interface sockets.
///
/// Created by [Transport] when [MultiInterfaceMode] is not [off].
/// Each active non-loopback interface gets its own UDP socket bound to
/// that interface's IPv4 address. The transport selects which socket(s) to
/// use for each send based on the mode and message priority.
class MultiInterfaceManager {
  final int port;
  final CLogger _log;
  MultiInterfaceMode _mode;
  final List<InterfaceSocket> _sockets = [];

  /// Callback for incoming datagrams on any interface socket.
  void Function(Datagram datagram, LocalInterface iface)? onDatagram;

  MultiInterfaceManager({
    required this.port,
    required MultiInterfaceMode mode,
    String? profileDir,
  })  : _mode = mode,
        _log = CLogger.get('multi-iface-mgr', profileDir: profileDir);

  MultiInterfaceMode get mode => _mode;

  set mode(MultiInterfaceMode m) {
    if (_mode == m) return;
    final old = _mode;
    _mode = m;
    _log.info('Multi-interface mode changed: ${old.name} -> ${m.name}');
    if (m == MultiInterfaceMode.off) {
      closeAll();
    }
  }

  /// Active interface sockets (read-only view).
  List<InterfaceSocket> get sockets => List.unmodifiable(_sockets);

  /// Whether multi-interface is actively sending (mode != off and sockets open).
  bool get isActive => _mode != MultiInterfaceMode.off && _sockets.isNotEmpty;

  /// Enumerate interfaces and bind sockets. Safe to call repeatedly
  /// (closes old sockets first). No-op when mode is [off].
  Future<void> refresh() async {
    closeAll();
    if (_mode == MultiInterfaceMode.off) return;

    final interfaces = await InterfaceEnumerator.enumerate();
    if (interfaces.length <= 1) {
      _log.info('Only ${interfaces.length} interface(s) — '
          'multi-interface not useful, staying single-socket');
      return;
    }

    for (final iface in interfaces) {
      final addr = iface.primaryIpv4;
      if (addr == null) continue;

      try {
        // Bind to the interface's specific IP with an OS-assigned port.
        // Cannot use `port` (the main transport port) because the main
        // socket on 0.0.0.0:port already claims all interfaces on that port.
        // Peers learn our per-interface address from packet source fields.
        final socket = await RawDatagramSocket.bind(addr, 0);
        socket.readEventsEnabled = true;
        final ifaceSocket = InterfaceSocket(
          interfaceInfo: iface,
          socket: socket,
          boundAddress: addr,
        );
        socket.listen(
          (event) {
            if (event != RawSocketEvent.read) return;
            for (;;) {
              final datagram = socket.receive();
              if (datagram == null) break;
              onDatagram?.call(datagram, iface.type);
            }
          },
          onError: (e) => _log.warn('Interface socket error (${iface.name}): $e'),
        );
        _sockets.add(ifaceSocket);
        _log.info('Bound interface socket: ${iface.name} '
            '(${iface.type.name}) on ${addr.address}:${socket.port}');
      } catch (e) {
        _log.info('Failed to bind on ${iface.name} (${addr.address}): $e');
      }
    }
    _log.info('Multi-interface: ${_sockets.length} sockets active');
  }

  /// Send data over a specific interface type. Returns bytes sent (>0 = ok).
  /// Returns 0 if no socket matches the requested interface.
  int sendVia(
    LocalInterface iface,
    Uint8List data,
    InternetAddress dest,
    int destPort,
  ) {
    for (final s in _sockets) {
      if (s.interfaceInfo.type == iface) {
        try {
          final sent = s.socket.send(data, dest, destPort);
          if (sent > 0) s.sendCount++;
          return sent;
        } catch (e) {
          _log.debug('sendVia(${iface.name}) error: $e');
          return 0;
        }
      }
    }
    return 0;
  }

  /// Send data over ALL active interface sockets (parallel send).
  /// Returns true if at least one socket succeeded.
  bool sendAll(Uint8List data, InternetAddress dest, int destPort) {
    var anySent = false;
    for (final s in _sockets) {
      try {
        final sent = s.socket.send(data, dest, destPort);
        if (sent > 0) {
          s.sendCount++;
          anySent = true;
        }
      } catch (e) {
        _log.debug('sendAll(${s.interfaceInfo.name}) error: $e');
      }
    }
    return anySent;
  }

  /// Send over the best (cheapest) interface: wifi > ethernet > other > cellular.
  /// Returns bytes sent, or 0 on failure.
  int sendBest(Uint8List data, InternetAddress dest, int destPort) {
    final sorted = List<InterfaceSocket>.from(_sockets)
      ..sort((a, b) => _interfaceCost(a.interfaceInfo.type)
          .compareTo(_interfaceCost(b.interfaceInfo.type)));
    for (final s in sorted) {
      try {
        final sent = s.socket.send(data, dest, destPort);
        if (sent > 0) {
          s.sendCount++;
          return sent;
        }
      } catch (e) {
        _log.debug('sendBest(${s.interfaceInfo.name}) error: $e');
      }
    }
    return 0;
  }

  /// Get the interface socket with the best ACK rate for a destination.
  /// Returns null if no sockets are active.
  InterfaceSocket? bestByAckRate() {
    if (_sockets.isEmpty) return null;
    InterfaceSocket? best;
    for (final s in _sockets) {
      if (best == null || s.ackRate > best.ackRate) best = s;
    }
    return best;
  }

  /// Close all interface sockets.
  void closeAll() {
    for (final s in _sockets) {
      s.close();
    }
    _sockets.clear();
  }

  /// Cost heuristic for interface selection.
  /// Lower = preferred: wifi(1), ethernet(2), other(5), cellular(10).
  static int _interfaceCost(LocalInterface type) {
    switch (type) {
      case LocalInterface.wifi:
        return 1;
      case LocalInterface.ethernet:
        return 2;
      case LocalInterface.other:
        return 5;
      case LocalInterface.cellular:
        return 10;
    }
  }

  /// JSON serialization of current mode (for profile persistence).
  static String modeToString(MultiInterfaceMode mode) => mode.name;

  static MultiInterfaceMode modeFromString(String? s) {
    if (s == null) return MultiInterfaceMode.off;
    return MultiInterfaceMode.values.firstWhere(
      (e) => e.name == s,
      orElse: () => MultiInterfaceMode.auto,
    );
  }
}
