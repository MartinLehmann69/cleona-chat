import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/network/clogger.dart';

/// LAN IPv6 Multicast for group calls.
///
/// Uses multicast group ff02::c1e0:ca11 ("cleona call") on the
/// link-local scope to deliver media frames to all LAN participants
/// with a single packet — zero additional upload per local recipient.
///
/// Lifecycle:
/// 1. [joinGroup] when joining a call with LAN participants
/// 2. [send] media frames (received by all group members)
/// 3. [leaveGroup] when the call ends
///
/// Fallback: If multicast binding fails (unsupported OS, permissions),
/// the caller should use unicast to each LAN member instead.
class CallLanMulticast {
  /// Multicast group address for Cleona calls (link-local scope).
  /// ff02:: = link-local multicast, c1e0:ca11 = "cleona call" mnemonic.
  static const String multicastGroup = 'ff02::c1e0:ca11';

  /// Default port for call multicast traffic.
  static const int defaultPort = 41339; // Main port + 1

  final int port;
  final CLogger _log;

  RawDatagramSocket? _socket;
  bool _joined = false;

  // Callback: received multicast frame.
  void Function(Uint8List data, InternetAddress sender, int senderPort)?
      onFrame;

  // Stats
  int framesSent = 0;
  int framesReceived = 0;

  CallLanMulticast({
    int? port,
    required String profileDir,
  })  : port = port ?? defaultPort,
        _log = CLogger.get('lan-mcast', profileDir: profileDir);

  bool get isJoined => _joined;

  /// Join the multicast group and start listening.
  /// Returns true on success, false if multicast is not available.
  Future<bool> joinGroup() async {
    if (_joined) return true;

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv6,
        port,
        reuseAddress: true,
        reusePort: true,
      );

      _socket!.joinMulticast(InternetAddress(multicastGroup));
      _socket!.multicastHops = 1; // Link-local only

      _socket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = _socket!.receive();
          if (dg != null) {
            framesReceived++;
            onFrame?.call(dg.data, dg.address, dg.port);
          }
        }
      });

      _joined = true;
      _log.info('Joined multicast group $multicastGroup:$port');
      return true;
    } catch (e) {
      _log.warn('Multicast join failed: $e');
      _socket?.close();
      _socket = null;
      return false;
    }
  }

  /// Send a media frame to the multicast group.
  /// Returns true if sent, false if not joined or send failed.
  bool send(Uint8List data) {
    if (!_joined || _socket == null) return false;

    try {
      final sent = _socket!.send(
        data,
        InternetAddress(multicastGroup),
        port,
      );
      if (sent > 0) {
        framesSent++;
        return true;
      }
      return false;
    } catch (e) {
      _log.debug('Multicast send failed: $e');
      return false;
    }
  }

  /// Leave the multicast group and close the socket.
  void leaveGroup() {
    if (!_joined) return;

    try {
      _socket?.leaveMulticast(InternetAddress(multicastGroup));
    } catch (_) {}

    _socket?.close();
    _socket = null;
    _joined = false;
    _log.info('Left multicast group');
  }

  /// Check if IPv6 multicast is available on this system.
  static bool get isAvailable {
    try {
      // Check for IPv6 support by looking for a link-local address
      for (final iface in NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv6,
      ) as Iterable<NetworkInterface>) {
        for (final addr in iface.addresses) {
          if (addr.isLinkLocal) return true;
        }
      }
    } catch (_) {}
    return false;
  }
}

/// Detect if two IP addresses are on the same subnet.
///
/// For IPv4: compares /24 prefix (first 3 octets).
/// For IPv6: compares link-local prefix (same interface).
bool isSameSubnet(String ipA, String ipB) {
  try {
    final a = InternetAddress(ipA);
    final b = InternetAddress(ipB);

    if (a.type == InternetAddressType.IPv4 &&
        b.type == InternetAddressType.IPv4) {
      // Compare /24 prefix
      final partsA = ipA.split('.');
      final partsB = ipB.split('.');
      return partsA.length == 4 &&
          partsB.length == 4 &&
          partsA[0] == partsB[0] &&
          partsA[1] == partsB[1] &&
          partsA[2] == partsB[2];
    }

    if (a.isLinkLocal && b.isLinkLocal) {
      // Both IPv6 link-local → same LAN
      return true;
    }
  } catch (_) {}

  return false;
}
