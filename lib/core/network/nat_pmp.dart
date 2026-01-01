// NAT-PMP (RFC 6886) + PCP (RFC 6887) client implementation.
//
// Provides port mapping requests to the gateway router for public
// reachability without keepalive traffic. Uses its own ephemeral
// UDP socket (NOT the Transport socket).
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/network/clogger.dart';

// ── Data Classes ────────────────────────────────────────────────────

/// Result of a successful port mapping request.
class PortMappingResult {
  final String externalIp;
  final int externalPort;
  final int lifetimeSeconds;
  final DateTime acquiredAt;

  PortMappingResult({
    required this.externalIp,
    required this.externalPort,
    required this.lifetimeSeconds,
    DateTime? acquiredAt,
  }) : acquiredAt = acquiredAt ?? DateTime.now();

  /// When the lease should be renewed (lifetime / 2).
  DateTime get renewAt => acquiredAt.add(Duration(
      seconds: lifetimeSeconds > 0 ? lifetimeSeconds ~/ 2 : 1800));

  /// Whether the lease has expired.
  bool get isExpired => lifetimeSeconds > 0 &&
      DateTime.now().isAfter(
          acquiredAt.add(Duration(seconds: lifetimeSeconds)));

  @override
  String toString() =>
      'PortMapping($externalIp:$externalPort, lifetime=${lifetimeSeconds}s)';
}

// ── NAT-PMP Protocol Constants ──────────────────────────────────────

/// NAT-PMP version byte.
const int natPmpVersion = 0;

/// NAT-PMP opcodes.
const int natPmpOpExternalAddress = 0;
const int natPmpOpMapUdp = 1;
const int natPmpOpMapTcp = 2;

/// NAT-PMP result codes.
const int natPmpResultSuccess = 0;
const int natPmpResultUnsupported = 1;
const int natPmpResultNotAuthorized = 2;
const int natPmpResultNetworkFailure = 3;
const int natPmpResultOutOfResources = 4;
const int natPmpResultUnsupportedOpcode = 5;

/// NAT-PMP/PCP port on the gateway.
const int natPmpPort = 5351;

/// Initial retry delay for NAT-PMP (RFC 6886 section 3.1).
const Duration natPmpInitialDelay = Duration(milliseconds: 250);

/// Maximum retries (250ms * 2^8 = 64s total).
const int natPmpMaxRetries = 9;

// ── PCP Protocol Constants ──────────────────────────────────────────

/// PCP version byte.
const int pcpVersion = 2;

/// PCP opcodes.
const int pcpOpMap = 1;
const int pcpOpPeer = 2;
const int pcpOpAnnounce = 3;

/// PCP result codes.
const int pcpResultSuccess = 0;

// ── Gateway Detection ───────────────────────────────────────────────

/// Parse the default gateway IP from /proc/net/route (Linux).
/// Returns null if not found.
String? parseGatewayFromProcRoute(String contents) {
  final lines = contents.split('\n');
  for (final line in lines.skip(1)) {
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 3) continue;
    final destination = parts[1];
    final gateway = parts[2];
    // Default route: destination == 00000000
    if (destination == '00000000' && gateway != '00000000') {
      return parseHexIp(gateway);
    }
  }
  return null;
}

/// Parse a hex-encoded IPv4 address from /proc/net/route.
/// Format is little-endian: "0101A8C0" → 192.168.1.1
String? parseHexIp(String hex) {
  if (hex.length != 8) return null;
  try {
    final value = int.parse(hex, radix: 16);
    // Little-endian byte order
    final b0 = value & 0xFF;
    final b1 = (value >> 8) & 0xFF;
    final b2 = (value >> 16) & 0xFF;
    final b3 = (value >> 24) & 0xFF;
    return '$b0.$b1.$b2.$b3';
  } catch (_) {
    return null;
  }
}

/// Detect the default gateway IP.
/// Linux: parse /proc/net/route. Android/other: heuristic (.1 suffix).
Future<String?> detectGatewayIp() async {
  // Try /proc/net/route first (Linux, Android)
  try {
    final file = File('/proc/net/route');
    if (await file.exists()) {
      final contents = await file.readAsString();
      final gw = parseGatewayFromProcRoute(contents);
      if (gw != null) return gw;
    }
  } catch (_) {}

  // Fallback: heuristic — assume gateway is .1 on the first private IP's subnet
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    for (final iface in interfaces) {
      if (iface.name == 'lo') continue;
      for (final addr in iface.addresses) {
        final ip = addr.address;
        if (ip.startsWith('10.') ||
            ip.startsWith('192.168.') ||
            _isClass172Private(ip)) {
          // Replace last octet with .1
          final parts = ip.split('.');
          parts[3] = '1';
          return parts.join('.');
        }
      }
    }
  } catch (_) {}

  return null;
}

bool _isClass172Private(String ip) {
  if (!ip.startsWith('172.')) return false;
  final parts = ip.split('.');
  if (parts.length != 4) return false;
  final second = int.tryParse(parts[1]);
  return second != null && second >= 16 && second <= 31;
}

// ── IPv4-mapped-IPv6 Helpers ────────────────────────────────────────

/// Encode an IPv4 address as IPv4-mapped-IPv6 (16 bytes).
/// Format: 10 bytes 0x00 + 2 bytes 0xFF + 4 bytes IPv4.
Uint8List ipv4ToMappedIpv6(String ipv4) {
  final parts = ipv4.split('.');
  if (parts.length != 4) {
    throw ArgumentError('Invalid IPv4: $ipv4');
  }
  final bytes = Uint8List(16);
  // First 10 bytes: 0x00 (already initialized)
  bytes[10] = 0xFF;
  bytes[11] = 0xFF;
  for (var i = 0; i < 4; i++) {
    bytes[12 + i] = int.parse(parts[i]);
  }
  return bytes;
}

/// Decode an IPv4 address from IPv4-mapped-IPv6 (16 bytes).
/// Returns null if not a valid IPv4-mapped-IPv6 address.
String? mappedIpv6ToIpv4(Uint8List bytes) {
  if (bytes.length != 16) return null;
  // Check prefix: 10 bytes 0x00 + 2 bytes 0xFF
  for (var i = 0; i < 10; i++) {
    if (bytes[i] != 0) return null;
  }
  if (bytes[10] != 0xFF || bytes[11] != 0xFF) return null;
  return '${bytes[12]}.${bytes[13]}.${bytes[14]}.${bytes[15]}';
}

/// Encode an IPv4 address as 4 bytes.
Uint8List ipv4ToBytes(String ipv4) {
  final parts = ipv4.split('.');
  if (parts.length != 4) {
    throw ArgumentError('Invalid IPv4: $ipv4');
  }
  final bytes = Uint8List(4);
  for (var i = 0; i < 4; i++) {
    bytes[i] = int.parse(parts[i]);
  }
  return bytes;
}

/// Decode an IPv4 address from 4 bytes.
String ipv4FromBytes(Uint8List bytes, [int offset = 0]) {
  return '${bytes[offset]}.${bytes[offset + 1]}.${bytes[offset + 2]}.${bytes[offset + 3]}';
}

// ── NAT-PMP Packet Encoding/Decoding ────────────────────────────────

/// Encode a NAT-PMP external address request (2 bytes).
Uint8List encodeExternalAddressRequest() {
  return Uint8List.fromList([natPmpVersion, natPmpOpExternalAddress]);
}

/// Encode a NAT-PMP UDP mapping request (12 bytes).
///
/// [internalPort] - the local port to map.
/// [externalPort] - suggested external port (0 = let router choose).
/// [lifetime] - requested lifetime in seconds (0 = delete mapping).
Uint8List encodeMappingRequest(int internalPort, int externalPort, int lifetime) {
  final data = ByteData(12);
  data.setUint8(0, natPmpVersion);
  data.setUint8(1, natPmpOpMapUdp);
  data.setUint16(2, 0); // reserved
  data.setUint16(4, internalPort);
  data.setUint16(6, externalPort);
  data.setUint32(8, lifetime);
  return data.buffer.asUint8List();
}

/// Parse a NAT-PMP external address response.
/// Returns the external IP or null on error.
///
/// Response format (12 bytes):
///   0: version (0)
///   1: opcode (128 + 0 = 128)
///   2-3: result code
///   4-7: seconds since epoch
///   8-11: external IP address
({String ip, int resultCode, int secondsSinceEpoch})? parseExternalAddressResponse(
    Uint8List data) {
  if (data.length < 12) return null;
  final view = ByteData.sublistView(data);
  final opcode = view.getUint8(1);
  if (opcode != 128 + natPmpOpExternalAddress) return null;
  final resultCode = view.getUint16(2);
  final ssse = view.getUint32(4);
  final ip = ipv4FromBytes(data, 8);
  return (ip: ip, resultCode: resultCode, secondsSinceEpoch: ssse);
}

/// Parse a NAT-PMP mapping response.
///
/// Response format (16 bytes):
///   0: version (0)
///   1: opcode (128 + original opcode)
///   2-3: result code
///   4-7: seconds since epoch
///   8-9: internal port
///   10-11: mapped external port
///   12-15: mapping lifetime (seconds)
({int resultCode, int secondsSinceEpoch, int internalPort, int externalPort, int lifetime})?
    parseMappingResponse(Uint8List data) {
  if (data.length < 16) return null;
  final view = ByteData.sublistView(data);
  final opcode = view.getUint8(1);
  if (opcode != 128 + natPmpOpMapUdp && opcode != 128 + natPmpOpMapTcp) {
    return null;
  }
  return (
    resultCode: view.getUint16(2),
    secondsSinceEpoch: view.getUint32(4),
    internalPort: view.getUint16(8),
    externalPort: view.getUint16(10),
    lifetime: view.getUint32(12),
  );
}

// ── PCP Packet Encoding/Decoding ────────────────────────────────────

/// Encode a PCP MAP request.
///
/// PCP header (24 bytes):
///   0: version (2)
///   1: opcode (R=0 | opcode 1)
///   2-3: reserved
///   4-7: requested lifetime
///   8-23: client IP (IPv4-mapped-IPv6)
///
/// MAP opcode payload (36 bytes):
///   0-11: mapping nonce (12 bytes)
///   12: protocol (17 = UDP)
///   13-15: reserved
///   16-17: internal port
///   18-19: suggested external port
///   20-35: suggested external IP (IPv4-mapped-IPv6, all-zeros = any)
///
/// Total: 60 bytes.
Uint8List encodePcpMapRequest({
  required String clientIp,
  required int internalPort,
  int externalPort = 0,
  int lifetime = 7200,
  Uint8List? nonce,
}) {
  final data = Uint8List(60);
  final view = ByteData.sublistView(data);

  // Header
  data[0] = pcpVersion;
  data[1] = pcpOpMap; // R=0 (request), opcode=1
  // bytes 2-3 reserved (0)
  view.setUint32(4, lifetime);
  // Client IP (IPv4-mapped-IPv6)
  final clientIpBytes = ipv4ToMappedIpv6(clientIp);
  data.setRange(8, 24, clientIpBytes);

  // MAP payload
  // Nonce (12 bytes) — random or provided
  if (nonce != null && nonce.length >= 12) {
    data.setRange(24, 36, nonce.sublist(0, 12));
  }
  // Protocol: 17 = UDP
  data[36] = 17;
  // bytes 37-39 reserved (0)
  view.setUint16(40, internalPort);
  view.setUint16(42, externalPort);
  // Suggested external IP: all-zeros (= any), bytes 44-59 stay 0

  return data;
}

/// Parse a PCP MAP response.
///
/// Response header (24 bytes):
///   0: version (2)
///   1: R=1 | opcode
///   2: reserved
///   3: result code
///   4-7: lifetime
///   8-11: epoch time
///   12-23: reserved
///
/// MAP payload (36 bytes):
///   0-11: nonce
///   12: protocol
///   13-15: reserved
///   16-17: internal port
///   18-19: assigned external port
///   20-35: assigned external IP (IPv4-mapped-IPv6)
({
  int resultCode,
  int lifetime,
  int epochTime,
  int internalPort,
  int externalPort,
  String? externalIp,
  Uint8List? nonce,
})? parsePcpMapResponse(Uint8List data) {
  if (data.length < 60) return null;
  final view = ByteData.sublistView(data);

  final version = data[0];
  if (version != pcpVersion) return null;

  final opcodeField = data[1];
  // Response bit (0x80) must be set, opcode must be MAP (1)
  if (opcodeField & 0x80 == 0) return null; // Not a response
  final opcode = opcodeField & 0x7F;
  if (opcode != pcpOpMap) return null;

  final resultCode = data[3];
  final lifetime = view.getUint32(4);
  final epochTime = view.getUint32(8);

  // MAP payload starts at offset 24
  final nonce = Uint8List.fromList(data.sublist(24, 36));
  final internalPort = view.getUint16(40);
  final externalPort = view.getUint16(42);
  final externalIpBytes = Uint8List.fromList(data.sublist(44, 60));
  final externalIp = mappedIpv6ToIpv4(externalIpBytes);

  return (
    resultCode: resultCode,
    lifetime: lifetime,
    epochTime: epochTime,
    internalPort: internalPort,
    externalPort: externalPort,
    externalIp: externalIp,
    nonce: nonce,
  );
}

// ── NAT-PMP Client ──────────────────────────────────────────────────

/// NAT-PMP / PCP client.
///
/// Tries NAT-PMP first (RFC 6886), falls back to PCP (RFC 6887)
/// if NAT-PMP returns unsupported opcode or times out.
class NatPmpClient {
  final CLogger _log;
  RawDatagramSocket? _socket;

  NatPmpClient({String? profileDir})
      : _log = CLogger.get('nat-pmp', profileDir: profileDir);

  /// Request a UDP port mapping from the gateway.
  ///
  /// [gatewayIp] - gateway IP address (auto-detected if null).
  /// [internalPort] - local UDP port.
  /// [externalPort] - suggested external port (0 = router chooses).
  /// [lifetime] - requested lease time in seconds (default 7200 = 2h).
  /// [clientIp] - own IP for PCP (auto-detected if null).
  ///
  /// Returns a [PortMappingResult] on success, null on failure.
  /// Tries NAT-PMP first, then PCP as fallback.
  Future<PortMappingResult?> requestMapping({
    String? gatewayIp,
    required int internalPort,
    int externalPort = 0,
    int lifetime = 7200,
    String? clientIp,
  }) async {
    // Detect gateway if not provided
    final gw = gatewayIp ?? await detectGatewayIp();
    if (gw == null) {
      _log.info('No gateway detected — skipping NAT-PMP/PCP');
      return null;
    }

    // Try NAT-PMP first (home router)
    final natPmpResult = await _tryNatPmp(gw, internalPort, externalPort, lifetime);
    if (natPmpResult != null) return natPmpResult;

    // Fallback to PCP on local gateway (home router)
    _log.debug('NAT-PMP failed, trying PCP on gateway $gw...');
    final pcpResult = await _tryPcp(gw, internalPort, externalPort, lifetime, clientIp);
    if (pcpResult != null) return pcpResult;

    // §27 CGNAT bypass: try PCP on known CGNAT/AFTR addresses.
    // DS-Lite AFTR uses 192.0.0.1 (RFC 6333), some carriers use other addresses.
    // PCP to the CGNAT gateway can open a public port mapping even when the
    // home router doesn't support PCP.
    for (final cgnatGw in _cgnatGateways) {
      if (cgnatGw == gw) continue; // Already tried
      _log.debug('Trying PCP on CGNAT gateway $cgnatGw...');
      final cgnatResult = await _tryPcp(cgnatGw, internalPort, externalPort, lifetime, clientIp);
      if (cgnatResult != null) {
        _log.info('PCP succeeded on CGNAT gateway $cgnatGw!');
        return cgnatResult;
      }
    }
    return null;
  }

  /// Known CGNAT/AFTR gateway addresses to try PCP against.
  /// 192.0.0.1: DS-Lite AFTR (RFC 6333)
  /// 100.64.0.1: Common CGNAT gateway in the 100.64.0.0/10 range
  static const _cgnatGateways = ['192.0.0.1', '100.64.0.1'];

  /// Query the external IP address via NAT-PMP.
  Future<String?> queryExternalIp({String? gatewayIp}) async {
    final gw = gatewayIp ?? await detectGatewayIp();
    if (gw == null) return null;

    try {
      final socket = await _bindSocket();
      if (socket == null) return null;

      final request = encodeExternalAddressRequest();
      final gwAddr = InternetAddress(gw);

      // Send with exponential backoff (RFC 6886 section 3.1)
      var delay = natPmpInitialDelay;
      for (var attempt = 0; attempt < natPmpMaxRetries; attempt++) {
        socket.send(request, gwAddr, natPmpPort);

        final response = await _receiveWithTimeout(socket, delay);
        if (response != null) {
          final parsed = parseExternalAddressResponse(response);
          if (parsed != null && parsed.resultCode == natPmpResultSuccess) {
            _closeSocket();
            return parsed.ip;
          }
          // Non-retryable error
          if (parsed != null && parsed.resultCode != natPmpResultSuccess) {
            _closeSocket();
            return null;
          }
        }
        delay *= 2;
      }
      _closeSocket();
      return null;
    } catch (e) {
      _log.debug('queryExternalIp error: $e');
      _closeSocket();
      return null;
    }
  }

  /// Delete a port mapping.
  Future<bool> deleteMapping({
    String? gatewayIp,
    required int internalPort,
  }) async {
    final gw = gatewayIp ?? await detectGatewayIp();
    if (gw == null) return false;

    try {
      final socket = await _bindSocket();
      if (socket == null) return false;

      // Send mapping request with lifetime=0 (delete)
      final request = encodeMappingRequest(internalPort, 0, 0);
      socket.send(request, InternetAddress(gw), natPmpPort);

      final response = await _receiveWithTimeout(
          socket, const Duration(seconds: 3));
      _closeSocket();

      if (response != null) {
        final parsed = parseMappingResponse(response);
        return parsed != null && parsed.resultCode == natPmpResultSuccess;
      }
      return false;
    } catch (e) {
      _log.debug('deleteMapping error: $e');
      _closeSocket();
      return false;
    }
  }

  /// Dispose the client and close any open socket.
  void dispose() {
    _closeSocket();
  }

  // ── Internal: NAT-PMP ─────────────────────────────────────────────

  Future<PortMappingResult?> _tryNatPmp(
      String gatewayIp, int internalPort, int externalPort, int lifetime) async {
    try {
      final socket = await _bindSocket();
      if (socket == null) return null;

      final request = encodeMappingRequest(internalPort, externalPort, lifetime);
      final gwAddr = InternetAddress(gatewayIp);

      // First, query external IP
      String? externalIp;
      socket.send(encodeExternalAddressRequest(), gwAddr, natPmpPort);
      final ipResp = await _receiveWithTimeout(socket, const Duration(seconds: 2));
      if (ipResp != null) {
        final parsed = parseExternalAddressResponse(ipResp);
        if (parsed != null && parsed.resultCode == natPmpResultSuccess) {
          externalIp = parsed.ip;
        }
      }

      // Send mapping request with exponential backoff (RFC 6886 section 3.1)
      var delay = natPmpInitialDelay;
      for (var attempt = 0; attempt < natPmpMaxRetries; attempt++) {
        socket.send(request, gwAddr, natPmpPort);

        final response = await _receiveWithTimeout(socket, delay);
        if (response != null) {
          final parsed = parseMappingResponse(response);
          if (parsed != null) {
            if (parsed.resultCode == natPmpResultSuccess) {
              _log.info('NAT-PMP mapping: port ${parsed.externalPort}, '
                  'lifetime ${parsed.lifetime}s');
              _closeSocket();
              return PortMappingResult(
                externalIp: externalIp ?? '0.0.0.0',
                externalPort: parsed.externalPort,
                lifetimeSeconds: parsed.lifetime,
              );
            }
            // Non-retryable error
            _log.debug('NAT-PMP error: result=${parsed.resultCode}');
            _closeSocket();
            return null;
          }
        }
        delay *= 2;
        // Cap delay at 64 seconds
        if (delay.inSeconds > 64) break;
      }

      _closeSocket();
      return null;
    } catch (e) {
      _log.debug('NAT-PMP error: $e');
      _closeSocket();
      return null;
    }
  }

  // ── Internal: PCP ─────────────────────────────────────────────────

  Future<PortMappingResult?> _tryPcp(String gatewayIp, int internalPort,
      int externalPort, int lifetime, String? clientIp) async {
    try {
      // Detect client IP if not provided
      final myIp = clientIp ?? await _detectOwnIp();
      if (myIp == null) {
        _log.debug('PCP: cannot determine own IP');
        return null;
      }

      final socket = await _bindSocket();
      if (socket == null) return null;

      final request = encodePcpMapRequest(
        clientIp: myIp,
        internalPort: internalPort,
        externalPort: externalPort,
        lifetime: lifetime,
      );

      final gwAddr = InternetAddress(gatewayIp);

      // PCP uses same retry strategy as NAT-PMP
      var delay = natPmpInitialDelay;
      for (var attempt = 0; attempt < natPmpMaxRetries; attempt++) {
        socket.send(request, gwAddr, natPmpPort);

        final response = await _receiveWithTimeout(socket, delay);
        if (response != null) {
          final parsed = parsePcpMapResponse(response);
          if (parsed != null) {
            if (parsed.resultCode == pcpResultSuccess) {
              _log.info('PCP mapping: port ${parsed.externalPort}, '
                  'lifetime ${parsed.lifetime}s, ip=${parsed.externalIp}');
              _closeSocket();
              return PortMappingResult(
                externalIp: parsed.externalIp ?? '0.0.0.0',
                externalPort: parsed.externalPort,
                lifetimeSeconds: parsed.lifetime,
              );
            }
            _log.debug('PCP error: result=${parsed.resultCode}');
            _closeSocket();
            return null;
          }
        }
        delay *= 2;
        if (delay.inSeconds > 64) break;
      }

      _closeSocket();
      return null;
    } catch (e) {
      _log.debug('PCP error: $e');
      _closeSocket();
      return null;
    }
  }

  // ── Socket Helpers ────────────────────────────────────────────────

  Future<RawDatagramSocket?> _bindSocket() async {
    try {
      _closeSocket();
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      return _socket;
    } catch (e) {
      _log.debug('Failed to bind NAT-PMP socket: $e');
      return null;
    }
  }

  void _closeSocket() {
    _socket?.close();
    _socket = null;
  }

  Future<Uint8List?> _receiveWithTimeout(
      RawDatagramSocket socket, Duration timeout) async {
    // Poll socket.receive() instead of stream.listen() — RawDatagramSocket
    // is a single-subscription stream, so .listen() crashes on retry loops.
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < timeout) {
      final datagram = socket.receive();
      if (datagram != null) {
        return Uint8List.fromList(datagram.data);
      }
      await Future.delayed(const Duration(milliseconds: 20));
    }
    return null;
  }

  Future<String?> _detectOwnIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        if (iface.name == 'lo') continue;
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('10.') ||
              ip.startsWith('192.168.') ||
              _isClass172Private(ip)) {
            return ip;
          }
        }
      }
    } catch (_) {}
    return null;
  }
}
