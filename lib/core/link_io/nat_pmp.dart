/// NAT-PMP (RFC 6886) + PCP (RFC 6887) — the port mapping at the gateway.
///
/// ── WHERE THIS FILE COMES FROM AND WHY IT IS BACK (S373) ──────
///
/// Until the CUT of 31.08.2026 it stood as `lib/core/network/nat_pmp.dart`
/// in the V3 tree and fell with it. The owner expressly approved bringing it back on
/// 07.09.2026 — it is the reversal of part
/// of the CUT decision, not an overlooked remnant. The protocol part is
/// taken over unchanged; changed are only the connection to the
/// log sink (bare `void Function(String)` instead of `CLogger`, as in the whole
/// directory) and the removal of the V3 class `NatTraversal` — the
/// status signals of the NAT assistant (§27.9.1) are now handled by `PortMapper`.
///
/// WHAT IT DOES, and why V4.1 needs it: without port mapping a
/// node behind a NAT is only reachable from outside as long as its
/// own outgoing traffic keeps a hole open. A confirmed
/// mapping on the other hand yields an `externalIp:externalPort` that belongs in the
/// own entry record (§11) and that a stranger can dial
/// without this node having sent anything beforehand. Exactly that is
/// the prerequisite for incoming sync partners (§25.4).
///
/// ── WHAT IT IS NOT ───────────────────────────────────────────────
///
/// It is NOT a step of the escalation axis from §4.8. It does not know
/// `TransportStage`, it chooses no transport, and the numbers it
/// advances select nothing — it talks to the GATEWAY, not
/// to a peer. The retries below are the
/// RFC 6886 backoff of a single gateway dialogue and not a ladder.
///
/// ── OWN, SHORT-LIVED SOCKET ─────────────────────────────────────
///
/// Not the socket of the connection layer (`UdpSocketSet`). The responses
/// of the gateway are not link frames; sending them through the demux
/// would mean teaching it a second format that has nothing to do
/// with the network. The socket is bound per dialogue and closed afterwards.
///
/// ── PACKET COUNT (working rule #5) ─────────────────────────────────────
///
/// A run that nobody answers costs AT MOST 1 + 4 x 9 = 37
/// datagrams to up to three gateway addresses, spread over around
/// eight and a half minutes (backoff 250 ms, doubled, abort as soon as the
/// wait exceeds 64 s). If the gateway answers, it is two.
/// The renewal costs ONE datagram per half lifetime (default
/// 7200 s, i.e. one packet per hour). There is no polling.
///
/// ── THE SECOND MAPPING FOR TCP (S376, P2-1) ──────────────────────
///
/// The node binds UDP and TCP on THE SAME port number (§2.1a/E-60:
/// the entry record knows exactly one port for both;
/// `v41_node.dart` passes the same `port` to the `TcpLinkListener`). Until
/// 08.09.2026 the port mapping only opened the UDP half of it:
/// `encodeMappingRequest` hard-wrote `natPmpOpMapUdp`, the
/// PCP MAP body hard protocol 17, and the UPnP SOAP hard `'UDP'`.
/// `natPmpOpMapTcp` had stood there as a constant since the retrieval and was
/// only read in the PARSER. In a network that blocks UDP (RL-15), the
/// TCP fallback is the only way in — and exactly that was never
/// reachable behind NAT.
///
/// ── WHAT THIS COSTS IN PACKETS, AND WHY WORKING RULE 5 BEARS IT ───
///
/// The TCP mapping is ONLY attempted if the UDP mapping on
/// the same gateway and with the same protocol has just SUCCEEDED,
/// and then with exactly ONE datagram without a backoff loop
/// ([kTcpBestEffortTimeout]). Justification: the gateway has just proven
/// that it answers on this address in milliseconds. If it does not do so on
/// the TCP opcode, it cannot do TCP mappings — a
/// retry learns nothing new.
///
/// The balance above thus changes as follows:
///
///   nobody answers       37 datagrams  ->  37   (unchanged; without
///                                                UDP success no
///                                                TCP attempt)
///   gateway answers       2 datagrams  ->   3
///   renewal               1 per half lifetime -> 2, and only as long as
///                                                the TCP half stands
///   teardown              1 -> 2, likewise only then
///
/// One additional datagram in the success case, none in the failure case. That
/// is the price for the TCP fallback behind NAT existing
/// at all.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../util/host_interfaces.dart';

// ── Data Classes ────────────────────────────────────────────────────

/// Result of a successful port mapping request.
class PortMappingResult {
  final String externalIp;
  final int externalPort;
  final int lifetimeSeconds;
  final DateTime acquiredAt;

  /// Is the TCP mapping open IN ADDITION to the UDP mapping? (S376)
  ///
  /// **It does not change the ANNOUNCEMENT.** The entry record knows exactly
  /// one port for both protocols (§2.1a/E-60); there is no
  /// field in it that would say "TCP too", and there should not be one. The
  /// field says something to two things: the teardown (do I delete one or two
  /// mappings?) and the renewal (do I renew one or two?).
  /// A reader who turned it into an announcement decision would rebuild the
  /// second fixed point that B-24a closed.
  final bool tcpMapped;

  PortMappingResult({
    required this.externalIp,
    required this.externalPort,
    required this.lifetimeSeconds,
    this.tcpMapped = false,
    DateTime? acquiredAt,
  }) : acquiredAt = acquiredAt ?? DateTime.now();

  /// When the lease should be renewed (lifetime / 2).
  DateTime get renewAt => acquiredAt.add(Duration(
      seconds: lifetimeSeconds > 0 ? lifetimeSeconds ~/ 2 : 1800));

  /// Whether the lease has expired.
  bool get isExpired =>
      lifetimeSeconds > 0 &&
      DateTime.now()
          .isAfter(acquiredAt.add(Duration(seconds: lifetimeSeconds)));

  @override
  String toString() => 'PortMapping($externalIp:$externalPort, '
      'lifetime=${lifetimeSeconds}s, tcp=$tcpMapped)';
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

/// How long to wait for the response to the SECOND (TCP) mapping.
///
/// No backoff, no second attempt — see file header: the gateway has
/// answered on the same address immediately before. Two seconds
/// are eight times the first backoff stage (250 ms) and thus
/// generous for a device in the own segment.
const Duration kTcpBestEffortTimeout = Duration(seconds: 2);

// ── PCP Protocol Constants ──────────────────────────────────────────

/// PCP version byte.
const int pcpVersion = 2;

/// The protocol number in the PCP MAP body (byte 36), IANA.
///
/// It stands here as a constant since there are two of them (S376): a
/// literal `17` in the body and a literal `6` next to it would be two places
/// for the same rule.
const int pcpProtocolTcp = 6;
const int pcpProtocolUdp = 17;

/// PCP opcodes.
const int pcpOpMap = 1;
const int pcpOpPeer = 2;
const int pcpOpAnnounce = 3;

/// PCP result codes — RFC 6887 §7.4 ("Result Codes"). Only 0 is success;
/// all other values are errors. The names stand here so that a log
/// names the reason for a refusal instead of a bare number (S391/E4).
const int pcpResultSuccess = 0;
const int pcpResultUnsuppVersion = 1;
const int pcpResultNotAuthorized = 2;
const int pcpResultMalformedRequest = 3;
const int pcpResultUnsuppOpcode = 4;
const int pcpResultUnsuppOption = 5;
const int pcpResultMalformedOption = 6;
const int pcpResultNetworkFailure = 7;
const int pcpResultNoResources = 8;
const int pcpResultUnsuppProtocol = 9;
const int pcpResultUserExQuota = 10;
const int pcpResultCannotProvideExternal = 11;
const int pcpResultAddressMismatch = 12;
const int pcpResultExcessiveRemotePeers = 13;

/// The name of a PCP result code (RFC 6887 §7.4), for the log.
String pcpResultName(int code) => switch (code) {
      pcpResultSuccess => 'SUCCESS',
      pcpResultUnsuppVersion => 'UNSUPP_VERSION',
      pcpResultNotAuthorized => 'NOT_AUTHORIZED',
      pcpResultMalformedRequest => 'MALFORMED_REQUEST',
      pcpResultUnsuppOpcode => 'UNSUPP_OPCODE',
      pcpResultUnsuppOption => 'UNSUPP_OPTION',
      pcpResultMalformedOption => 'MALFORMED_OPTION',
      pcpResultNetworkFailure => 'NETWORK_FAILURE',
      pcpResultNoResources => 'NO_RESOURCES',
      pcpResultUnsuppProtocol => 'UNSUPP_PROTOCOL',
      pcpResultUserExQuota => 'USER_EX_QUOTA',
      pcpResultCannotProvideExternal => 'CANNOT_PROVIDE_EXTERNAL',
      pcpResultAddressMismatch => 'ADDRESS_MISMATCH',
      pcpResultExcessiveRemotePeers => 'EXCESSIVE_REMOTE_PEERS',
      _ => 'unknown($code)',
    };

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
///
/// Linux and Android: `/proc/net/route`. Windows, macOS and iOS do not have the
/// file — there the heuristic below applies (`.1` in the first
/// private subnet). NO subprocess: `Process.run` is not
/// allowed on iOS and not reliable on Android, and a gateway detection
/// that throws on two of five platforms would be worse than a
/// heuristic that delivers something on all five.
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
      // S376 (P2-4): `name != 'lo'` was not enough. On a machine with
      // libvirt, `virbr0` with `192.168.122.1` stands in the same
      // enumeration, and this heuristic then output `192.168.122.1` as
      // default gateway — the host's own bridge. The
      // NAT-PMP/PCP dialogue then ran against a device that knows no
      // port mapping, and used up its nine rounds there.
      if (!interfaceLeadsAfterOutside(iface.name)) continue;
      for (final addr in iface.addresses) {
        final ip = addr.address;
        if (ip.startsWith('10.') ||
            ip.startsWith('192.168.') ||
            isClass172Private(ip)) {
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

// ── IPv6 default router (S391, task E4) ──────────────────────────
//
// THE SAME WAY AS FOR IPv4: the kernel's routing table as a file, no
// subprocess (justification at [detectGatewayIp]). For IPv6 the
// file is called `/proc/net/ipv6_route`. RFC 6887 §8.1 step 2 names exactly this
// router as PCP server for IPv6 mappings: "an IPv6 PCP server (its
// IPv6 default router) for its IPv6 mappings".
//
// The IPv6 default router is practically always a LINK-LOCAL address
// (`fe80::/10`). Without a zone identifier it is not a destination — that is why the
// name of the interface belongs to the result, and the address is formed WITH
// `%<interface>` (`dart:io` accepts this form, measured on
// 17.09.2026 with Dart 3.12.2: `InternetAddress.tryParse('fe80::1%lo')`
// yields an IPv6 address, `send` to it succeeds).

/// Route flags of the Linux kernel — `include/uapi/linux/route.h`
/// (`RTF_UP 0x0001`, `RTF_GATEWAY 0x0002`, `RTF_REJECT 0x0200`); the
/// column "flags" in `/proc/net/ipv6_route` carries them in hexadecimal.
const int _rtfUp = 0x0001;
const int _rtfGateway = 0x0002;
const int _rtfReject = 0x0200;

/// The IPv6 default router from the content of `/proc/net/ipv6_route`, or
/// `null`.
///
/// Line format (Linux kernel, `net/ipv6/route.c`,
/// `ipv6_route_native_seq_show`): destination (32 hex) · destination prefix length (2 hex)
/// · source (32 hex) · source prefix length (2 hex) · next hop
/// (32 hex) · metric (8 hex) · references · use · flags (8 hex) ·
/// interface. The default route has destination `::` with length 0, a
/// next hop unequal to `::` and the flags UP+GATEWAY; a
/// REJECT route (the kernel creates it on `lo` if there is none) does
/// not count. With several, the smallest metric wins.
({String router, String networkInterface})? parseIpv6GatewayFromProcRoute(
    String contents) {
  ({String router, String networkInterface})? best;
  var bestMetric = -1;
  for (final line in contents.split('\n')) {
    final t = line.trim().split(RegExp(r'\s+'));
    if (t.length < 10) continue;
    final target = t[0], targetLength = t[1], hop = t[4];
    if (target.length != 32 || hop.length != 32) continue;
    if (int.tryParse(targetLength, radix: 16) != 0) continue;
    if (target != '0' * 32 || hop == '0' * 32) continue;
    final flags = int.tryParse(t[8], radix: 16) ?? 0;
    if (flags & _rtfUp == 0 || flags & _rtfGateway == 0) continue;
    if (flags & _rtfReject != 0) continue;
    final metric = int.tryParse(t[5], radix: 16) ?? 0xFFFFFFFF;
    final bytes = Uint8List(16);
    var valid = true;
    for (var i = 0; i < 16; i++) {
      final b = int.tryParse(hop.substring(2 * i, 2 * i + 2), radix: 16);
      if (b == null) {
        valid = false;
        break;
      }
      bytes[i] = b;
    }
    if (!valid) continue;
    // `fromRawAddress` yields the short text form (`fe80::1`); a
    // `tryParse` of the written-out groups would keep the long one.
    final router = InternetAddress.fromRawAddress(bytes,
            type: InternetAddressType.IPv6)
        .address;
    if (best == null || metric < bestMetric) {
      best = (router: router, networkInterface: t[9]);
      bestMetric = metric;
    }
  }
  return best;
}

/// The IPv6 default router of this device including interface, or `null`.
///
/// Only where `/proc/net/ipv6_route` is readable (Linux, Android — there
/// depending on the SELinux policy of the version). Windows, macOS and iOS
/// deliver `null`: for IPv6 there is NO heuristic like the `.1` for
/// IPv4, because the link-local address of a router cannot be derived from anything.
/// Without a router the PCP path for the pinhole is dropped; the UPnP path
/// remains (see `ipv6_pinhole.dart`).
Future<({String router, String networkInterface})?> detectIpv6Gateway() async {
  try {
    final file = File('/proc/net/ipv6_route');
    if (await file.exists()) {
      return parseIpv6GatewayFromProcRoute(await file.readAsString());
    }
  } catch (_) {}
  return null;
}

/// `172.16.0.0/12` — the part of the private space that a prefix comparison
/// alone does not hit.
bool isClass172Private(String ip) {
  if (!ip.startsWith('172.')) return false;
  final parts = ip.split('.');
  if (parts.length != 4) return false;
  final second = int.tryParse(parts[1]);
  return second != null && second >= 16 && second <= 31;
}

/// The first private IPv4 address of this device, or `null`.
///
/// Shared by PCP (`clientIp` in the MAP request) and UPnP
/// (`NewInternalClient` in the SOAP body). Two copies of the same loop
/// would be two places where the same question could be answered
/// differently — and the mapping would then point to a different device
/// than the record.
///
/// S376 (P2-4): exactly this sentence held until then only WITHIN this
/// file. Compared with `dialableLocalAddresses` — the source of the addresses
/// the node announces — the answer had been a different one since S374: that
/// loop left out virtual host bridges, this one did not. The
/// port mapping thus reported `192.168.122.x` to the gateway as its own
/// connection, while the record carried a different address. Both
/// now ask the same predicate.
Future<String?> detectOwnPrivateIpv4() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    for (final iface in interfaces) {
      if (!interfaceLeadsAfterOutside(iface.name)) continue;
      for (final addr in iface.addresses) {
        final ip = addr.address;
        if (ip.startsWith('10.') ||
            ip.startsWith('192.168.') ||
            isClass172Private(ip)) {
          return ip;
        }
      }
    }
  } catch (_) {}
  return null;
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
  return '${bytes[offset]}.${bytes[offset + 1]}.'
      '${bytes[offset + 2]}.${bytes[offset + 3]}';
}

// ── NAT-PMP Packet Encoding/Decoding ────────────────────────────────

/// Encode a NAT-PMP external address request (2 bytes).
Uint8List encodeExternalAddressRequest() {
  return Uint8List.fromList([natPmpVersion, natPmpOpExternalAddress]);
}

/// Encode a NAT-PMP mapping request (12 bytes).
///
/// [internalPort] - the local port to map.
/// [externalPort] - suggested external port (0 = let router choose).
/// [lifetime] - requested lifetime in seconds (0 = delete mapping).
/// [opcode] - [natPmpOpMapUdp] (default) or [natPmpOpMapTcp].
///
/// **The opcode was hard-wired until S376.** `natPmpOpMapTcp` had stood
/// there as a constant since the retrieval and was only read in the parser
/// — the TCP half of the one port stayed closed behind NAT.
Uint8List encodeMappingRequest(
    int internalPort, int externalPort, int lifetime,
    {int opcode = natPmpOpMapUdp}) {
  final data = ByteData(12);
  data.setUint8(0, natPmpVersion);
  data.setUint8(1, opcode);
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
({String ip, int resultCode, int secondsSinceEpoch})?
    parseExternalAddressResponse(Uint8List data) {
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
({
  int resultCode,
  int secondsSinceEpoch,
  int internalPort,
  int externalPort,
  int lifetime
})? parseMappingResponse(Uint8List data) {
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
///
/// ── IPv6 (S391, task E4) ─────────────────────────────────────────
///
/// [clientIp] may be an IPv6 address (recognised by the `:`; a
/// zone identifier `%…` is cut off). Then its 16 bytes stand raw in the
/// header — RFC 6887 §7.1: "PCP Client's IP Address: The source IPv4 or IPv6
/// address in the IP header"; only IPv4 is encoded as IPv4-mapped (§5).
/// That is the pinhole: the same MAP request, made from the own
/// global IPv6 to the IPv6 default router (§8.1 step 2).
///
/// [suggestedExternalIp] (default: all zero) is there for the RENEWAL —
/// RFC 6887 §11.2.1: "SHOULD also include the currently assigned external
/// IP address and port in the Suggested External IP Address and Suggested
/// External Port fields". On deletion (lifetime 0) the field must be zero
/// (§15.1); the caller then omits it.
Uint8List encodePcpMapRequest({
  required String clientIp,
  required int internalPort,
  int externalPort = 0,
  int lifetime = 7200,
  int protocol = pcpProtocolUdp,
  Uint8List? nonce,
  String? suggestedExternalIp,
}) {
  final data = Uint8List(60);
  final view = ByteData.sublistView(data);

  // Header
  data[0] = pcpVersion;
  data[1] = pcpOpMap; // R=0 (request), opcode=1
  // bytes 2-3 reserved (0)
  view.setUint32(4, lifetime);
  // Client IP: IPv4-mapped-IPv6, or raw for IPv6 (RFC 6887 §5, §7.1)
  data.setRange(8, 24, pcpAddress16(clientIp));

  // MAP payload
  // Nonce (12 bytes) — random or provided
  if (nonce != null && nonce.length >= 12) {
    data.setRange(24, 36, nonce.sublist(0, 12));
  }
  // Protokollnummer (IANA): 17 = UDP, 6 = TCP. Bis S376 fest 17.
  data[36] = protocol;
  // bytes 37-39 reserved (0)
  view.setUint16(40, internalPort);
  view.setUint16(42, externalPort);
  // Suggested external IP: default all-zeros (= any), bytes 44-59 stay 0
  if (suggestedExternalIp != null) {
    data.setRange(44, 60, pcpAddress16(suggestedExternalIp));
  }

  return data;
}

/// An address as a 16-byte field of a PCP packet (RFC 6887 §5): IPv6 raw,
/// IPv4 as IPv4-mapped-IPv6. A zone identifier (`fe80::1%eth0`) is
/// cut off — it is a property of the sender, not of the
/// address.
Uint8List pcpAddress16(String ip) {
  if (!ip.contains(':')) return ipv4ToMappedIpv6(ip);
  final raw = InternetAddress.tryParse(ip.split('%').first);
  if (raw == null || raw.rawAddress.length != 16) {
    throw ArgumentError('Invalid IPv6: $ip');
  }
  return Uint8List.fromList(raw.rawAddress);
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
  String? assignedAddress,
  int protocol,
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
  // S391/E4: the same address independent of family. [externalIp] stays
  // as it was (IPv4 only, otherwise `null`) — its readers in the IPv4 path
  // use it to distinguish "no address" from "an address".
  // `assignedAddress` is for the pinhole: RFC 6887 §11.1 "Assigned
  // External IP Address … An IPv4 address is encoded using IPv4-mapped IPv6
  // address", everything else is an IPv6 address.
  final assignedAddress = externalIp ??
      InternetAddress.fromRawAddress(externalIpBytes,
              type: InternetAddressType.IPv6)
          .address;

  return (
    resultCode: resultCode,
    lifetime: lifetime,
    epochTime: epochTime,
    internalPort: internalPort,
    externalPort: externalPort,
    externalIp: externalIp,
    assignedAddress: assignedAddress,
    protocol: data[36],
    nonce: nonce,
  );
}

// ── NAT-PMP Client ──────────────────────────────────────────────────

/// NAT-PMP / PCP client.
///
/// Tries NAT-PMP first (RFC 6886), falls back to PCP (RFC 6887)
/// if NAT-PMP returns unsupported opcode or times out.
class NatPmpClient {
  /// A bare sink, not a `CLogger`. Justification in the file header:
  /// `lib/core/link_io/` routes its logs via `void Function(String)`,
  /// so that every module of this directory stays testable without a profile directory and
  /// without a file system.
  final void Function(String)? log;

  /// The currently open dialogue sockets.
  ///
  /// ── WHY NO SINGLE FIELD ANY MORE (S376, P2-2) ───────────────────────
  ///
  /// Until 08.09.2026 this said `RawDatagramSocket? _socket`, and
  /// `_bindSocket()` first closed the old one before binding the new one.
  /// As long as only one dialogue ran, that was right. But two runs
  /// side by side do exist: `PortMapper.reset()` does not abort the
  /// running detection run, and the network change immediately starts
  /// a second one (`port_map_wiring.dart:onNetworkChanged`). The
  /// second run then closed the socket of the first — in the middle of its
  /// receive loop. The first then sent on a closed
  /// socket, which silently does nothing or throws, and evaluated that as
  /// "gateway does not answer".
  ///
  /// Every dialogue now holds its socket LOCALLY and closes it in
  /// a `finally`. The set here serves solely [dispose]: on
  /// shutdown the sockets whose dialogue is still in
  /// its backoff must fall too.
  final Set<RawDatagramSocket> _openSockets = <RawDatagramSocket>{};

  /// The gateway the last [requestMapping] run talked to.
  ///
  /// USED BY THE FAILURE BRANCH (S377, W-2). If the mapping fails,
  /// `PortMapper` still asks here for the OUTER ADDRESS ([queryExternalIp]).
  /// Without this handle this second dialogue would have to determine the gateway a
  /// second time — the same heuristic, the same file
  /// (`/proc/net/route`), read once more, and in the worst case with
  /// a DIFFERENT result than the run whose failure triggers it.
  ///
  /// `null` means: no [requestMapping] ran, or no
  /// gateway was detected. Both lead in [queryExternalIp] to the same path
  /// as before (determine it itself, and without a gateway return immediately) — the
  /// handle is a shortcut, not a prerequisite.
  String? _lastGatewayIp;
  String? get lastGatewayIp => _lastGatewayIp;

  NatPmpClient({this.log});

  /// Request a UDP port mapping from the gateway.
  ///
  /// [gatewayIp] - gateway IP address (auto-detected if null).
  /// [internalPort] - local UDP port.
  /// [externalPort] - suggested external port (0 = router chooses).
  /// [lifetime] - requested lease time in seconds (default 7200 = 2h).
  /// [clientIp] - own IP for PCP (auto-detected if null).
  /// [tryTcp] - whether after the UDP mapping the TCP half of the same
  ///   port should be opened as well (S376). Default `true`; the RENEWAL
  ///   passes `false` through if the TCP half was refused on creation
  ///   — otherwise a gateway without TCP mappings would cost one
  ///   useless datagram per hour, permanently (working rule 5).
  ///
  /// [abort] - is asked BEFORE every stage and before every retry.
  ///   If it returns `true`, the run aborts and returns
  ///   `null`.
  ///
  ///   ── WHY (S380, 10.09.2026) ────────────────────────────────────
  ///
  ///   This call runs in the worst case (nothing answers) around
  ///   eight and a half minutes and 37 datagrams: four stages (NAT-PMP at the
  ///   gateway, PCP at the gateway, PCP at two CGNAT addresses) with nine
  ///   retries each in the RFC 6886 backoff. The coordinator runs it
  ///   ALONGSIDE the UPnP path and takes the first result. If UPnP
  ///   has a mapping after three seconds, the remaining
  ///   eight and a half minutes are datagrams without any value
  ///   (working rule 5) — and until S380 they ran anyway.
  ///
  ///   NO genuine abort: a running `await` on a datagram
  ///   cannot be aborted in Dart. The question therefore stands at
  ///   the seams where the next traffic would arise;
  ///   the running wait (at most 64 s) still runs out.
  ///
  /// Returns a [PortMappingResult] on success, null on failure.
  /// Tries NAT-PMP first, then PCP as fallback.
  Future<PortMappingResult?> requestMapping({
    String? gatewayIp,
    required int internalPort,
    int externalPort = 0,
    int lifetime = 7200,
    String? clientIp,
    bool tryTcp = true,
    bool Function()? abort,
  }) async {
    // Detect gateway if not provided
    final gw = gatewayIp ?? await detectGatewayIp();
    if (gw == null) {
      log?.call('No gateway detected — NAT-PMP/PCP is skipped');
      return null;
    }
    // Remember for the failure branch of the coordinator (S377, W-2) — see
    // [lastGatewayIp]. Stands BEFORE the attempts: the value is needed
    // precisely when none of them yields anything.
    _lastGatewayIp = gw;

    // Try NAT-PMP first (home router)
    if (abort?.call() ?? false) return null;
    final natPmpResult = await _tryNatPmp(
        gw, internalPort, externalPort, lifetime, tryTcp, abort);
    if (natPmpResult != null) return natPmpResult;

    // Fallback to PCP on local gateway (home router)
    if (abort?.call() ?? false) return null;
    log?.call('NAT-PMP without success, PCP on gateway $gw...');
    final pcpResult = await _tryPcp(
        gw, internalPort, externalPort, lifetime, clientIp, tryTcp, abort);
    if (pcpResult != null) return pcpResult;

    // §27 CGNAT bypass: try PCP on known CGNAT/AFTR addresses.
    // DS-Lite AFTR uses 192.0.0.1 (RFC 6333), some carriers use other
    // addresses. PCP to the CGNAT gateway can open a public port mapping
    // even when the home router doesn't support PCP.
    for (final cgnatGw in _cgnatGateways) {
      if (cgnatGw == gw) continue; // Already tried
      if (abort?.call() ?? false) return null;
      log?.call('PCP on CGNAT gateway $cgnatGw...');
      final cgnatResult = await _tryPcp(cgnatGw, internalPort, externalPort,
          lifetime, clientIp, tryTcp, abort);
      if (cgnatResult != null) {
        log?.call('PCP on CGNAT gateway $cgnatGw succeeded');
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

    RawDatagramSocket? socket;
    try {
      socket = await _bindSocket();
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
            return parsed.ip;
          }
          // Non-retryable error
          if (parsed != null && parsed.resultCode != natPmpResultSuccess) {
            return null;
          }
        }
        delay *= 2;
      }
      return null;
    } catch (e) {
      log?.call('queryExternalIp: $e');
      return null;
    } finally {
      _closeSocket(socket);
    }
  }

  /// Delete a port mapping.
  ///
  /// [tcp] ADDITIONALLY tears down the TCP mapping (S376). The caller
  /// knows from `PortMappingResult.tcpMapped` whether there is one; an
  /// unconditional second datagram would be one for a mapping
  /// that mostly does not exist.
  ///
  /// The return value refers to the UDP mapping — it is the one
  /// reachability hangs on. A failed TCP teardown
  /// stands in the log and otherwise runs out with its lifetime.
  Future<bool> deleteMapping({
    String? gatewayIp,
    required int internalPort,
    bool tcp = false,
  }) async {
    final gw = gatewayIp ?? await detectGatewayIp();
    if (gw == null) return false;

    RawDatagramSocket? socket;
    try {
      socket = await _bindSocket();
      if (socket == null) return false;
      final gwAddr = InternetAddress(gw);

      // Send mapping request with lifetime=0 (delete)
      final request = encodeMappingRequest(internalPort, 0, 0);
      socket.send(request, gwAddr, natPmpPort);

      final response =
          await _receiveWithTimeout(socket, const Duration(seconds: 3));

      if (tcp) {
        socket.send(
            encodeMappingRequest(internalPort, 0, 0,
                opcode: natPmpOpMapTcp),
            gwAddr,
            natPmpPort);
        final tcpAnswer =
            await _receiveWithTimeout(socket, kTcpBestEffortTimeout);
        if (tcpAnswer == null) {
          log?.call('NAT-PMP: no answer to the TCP teardown — the '
              'mapping runs out with its lifetime');
        }
      }

      if (response != null) {
        final parsed = parseMappingResponse(response);
        return parsed != null && parsed.resultCode == natPmpResultSuccess;
      }
      return false;
    } catch (e) {
      log?.call('deleteMapping: $e');
      return false;
    } finally {
      _closeSocket(socket);
    }
  }

  /// Dispose the client and close any open socket.
  ///
  /// Closes ALL still open dialogue sockets, not only the last one.
  void dispose() {
    for (final s in _openSockets.toList()) {
      try {
        s.close();
      } catch (_) {}
    }
    _openSockets.clear();
  }

  // ── Internal: NAT-PMP ─────────────────────────────────────────────

  Future<PortMappingResult?> _tryNatPmp(String gatewayIp, int internalPort,
      int externalPort, int lifetime, bool tryTcp,
      [bool Function()? abort]) async {
    RawDatagramSocket? socket;
    try {
      socket = await _bindSocket();
      if (socket == null) return null;

      final request =
          encodeMappingRequest(internalPort, externalPort, lifetime);
      final gwAddr = InternetAddress(gatewayIp);

      // First, query external IP
      String? externalIp;
      socket.send(encodeExternalAddressRequest(), gwAddr, natPmpPort);
      final ipResp =
          await _receiveWithTimeout(socket, const Duration(seconds: 2));
      if (ipResp != null) {
        final parsed = parseExternalAddressResponse(ipResp);
        if (parsed != null && parsed.resultCode == natPmpResultSuccess) {
          externalIp = parsed.ip;
        }
      }

      // Send mapping request with exponential backoff (RFC 6886 section 3.1)
      var delay = natPmpInitialDelay;
      for (var attempt = 0; attempt < natPmpMaxRetries; attempt++) {
        // Before every NEW datagram, not only before the stage: the
        // backoff doubles up to 64 s, an abort only at the
        // end of the stage would come too late (S380).
        if (abort?.call() ?? false) return null;
        socket.send(request, gwAddr, natPmpPort);

        final response = await _receiveWithTimeout(socket, delay);
        if (response != null) {
          final parsed = parseMappingResponse(response);
          if (parsed != null) {
            if (parsed.resultCode == natPmpResultSuccess) {
              log?.call('NAT-PMP mapping: port ${parsed.externalPort}, '
                  'lifetime ${parsed.lifetime}s');
              // ── THE SECOND HALF OF THE SAME PORT (S376) ────────
              // Only now, and only once: justification in the file header
              // ("What this costs in packets").
              final tcp = tryTcp &&
                  await _tcpExtraNatPmp(socket, gwAddr, internalPort,
                      parsed.externalPort, lifetime);
              return PortMappingResult(
                externalIp: externalIp ?? '0.0.0.0',
                externalPort: parsed.externalPort,
                lifetimeSeconds: parsed.lifetime,
                tcpMapped: tcp,
              );
            }
            // Non-retryable error
            log?.call('NAT-PMP error: result=${parsed.resultCode}');
            return null;
          }
        }
        delay *= 2;
        // Cap delay at 64 seconds
        if (delay.inSeconds > 64) break;
      }

      return null;
    } catch (e) {
      log?.call('NAT-PMP: $e');
      return null;
    } finally {
      _closeSocket(socket);
    }
  }

  // ── Internal: PCP ─────────────────────────────────────────────────

  Future<PortMappingResult?> _tryPcp(String gatewayIp, int internalPort,
      int externalPort, int lifetime, String? clientIp, bool tryTcp,
      [bool Function()? abort]) async {
    RawDatagramSocket? socket;
    try {
      // Detect client IP if not provided
      final myIp = clientIp ?? await detectOwnPrivateIpv4();
      if (myIp == null) {
        log?.call('PCP: own address cannot be determined');
        return null;
      }

      socket = await _bindSocket();
      if (socket == null) return null;

      final request = encodePcpMapRequest(
        clientIp: myIp,
        internalPort: internalPort,
        externalPort: externalPort,
        lifetime: lifetime,
        protocol: pcpProtocolUdp,
      );

      final gwAddr = InternetAddress(gatewayIp);

      // PCP uses same retry strategy as NAT-PMP
      var delay = natPmpInitialDelay;
      for (var attempt = 0; attempt < natPmpMaxRetries; attempt++) {
        // Before every NEW datagram, not only before the stage: the
        // backoff doubles up to 64 s, an abort only at the
        // end of the stage would come too late (S380).
        if (abort?.call() ?? false) return null;
        socket.send(request, gwAddr, natPmpPort);

        final response = await _receiveWithTimeout(socket, delay);
        if (response != null) {
          final parsed = parsePcpMapResponse(response);
          if (parsed != null) {
            if (parsed.resultCode == pcpResultSuccess) {
              log?.call('PCP mapping: port ${parsed.externalPort}, '
                  'lifetime ${parsed.lifetime}s, IP=${parsed.externalIp}');
              final tcp = tryTcp &&
                  await _tcpExtraPcp(socket, gwAddr, myIp, internalPort,
                      parsed.externalPort, lifetime);
              return PortMappingResult(
                externalIp: parsed.externalIp ?? '0.0.0.0',
                externalPort: parsed.externalPort,
                lifetimeSeconds: parsed.lifetime,
                tcpMapped: tcp,
              );
            }
            log?.call('PCP error: result=${parsed.resultCode}');
            return null;
          }
        }
        delay *= 2;
        if (delay.inSeconds > 64) break;
      }

      return null;
    } catch (e) {
      log?.call('PCP: $e');
      return null;
    } finally {
      _closeSocket(socket);
    }
  }

  // ── The second mapping: TCP, best effort (S376, P2-1) ───────────
  //
  // COMMON RULES OF BOTH FUNCTIONS:
  //
  //   * They are ONLY called after a successful UDP mapping, on
  //     THE SAME socket and THE SAME gateway.
  //   * ONE datagram, ONE wait ([kTcpBestEffortTimeout]), no
  //     backoff. Justification in the file header.
  //   * They do not throw and report `false` instead of an error. A
  //     node with UDP mapping and without TCP mapping is reachable;
  //     the failure must not take the successful half along.
  //   * They take the OUTER port that the gateway assigned for UDP
  //     — not the desired one. §2.1a/E-60 gives the
  //     entry record one port for both protocols; a
  //     deviating TCP number would not be representable in the record and
  //     thus worthless.

  /// NAT-PMP: the same body, opcode 2 instead of 1.
  Future<bool> _tcpExtraNatPmp(RawDatagramSocket socket,
      InternetAddress gwAddr, int internalPort, int externalPort,
      int lifetime) async {
    try {
      socket.send(
          encodeMappingRequest(internalPort, externalPort, lifetime,
              opcode: natPmpOpMapTcp),
          gwAddr,
          natPmpPort);
      final response =
          await _receiveWithTimeout(socket, kTcpBestEffortTimeout);
      if (response == null) {
        log?.call('NAT-PMP: no answer to the TCP mapping — the '
            'TCP fallback stays closed behind NAT (UDP stands)');
        return false;
      }
      final parsed = parseMappingResponse(response);
      if (parsed == null || parsed.resultCode != natPmpResultSuccess) {
        log?.call('NAT-PMP: TCP mapping refused '
            '(result=${parsed?.resultCode})');
        return false;
      }
      if (parsed.externalPort != externalPort) {
        // A different outer number is unusable for the record
        // (one port for both protocols). It is not kept and
        // not torn down again — it runs out with its lifetime.
        log?.call('NAT-PMP: TCP mapping on a different port '
            '${parsed.externalPort} instead of $externalPort — discarded');
        return false;
      }
      log?.call('NAT-PMP: TCP mapping also open on $externalPort');
      return true;
    } catch (e) {
      log?.call('NAT-PMP TCP mapping: $e');
      return false;
    }
  }

  /// PCP: the same body, protocol 6 instead of 17.
  Future<bool> _tcpExtraPcp(RawDatagramSocket socket, InternetAddress gwAddr,
      String myIp, int internalPort, int externalPort, int lifetime) async {
    try {
      socket.send(
          encodePcpMapRequest(
            clientIp: myIp,
            internalPort: internalPort,
            externalPort: externalPort,
            lifetime: lifetime,
            protocol: pcpProtocolTcp,
          ),
          gwAddr,
          natPmpPort);
      final response =
          await _receiveWithTimeout(socket, kTcpBestEffortTimeout);
      if (response == null) {
        log?.call('PCP: no answer to the TCP mapping — the '
            'TCP fallback stays closed behind NAT (UDP stands)');
        return false;
      }
      final parsed = parsePcpMapResponse(response);
      if (parsed == null || parsed.resultCode != pcpResultSuccess) {
        log?.call('PCP: TCP mapping refused (result=${parsed?.resultCode})');
        return false;
      }
      if (parsed.externalPort != externalPort) {
        log?.call('PCP: TCP mapping on a different port '
            '${parsed.externalPort} instead of $externalPort — discarded');
        return false;
      }
      log?.call('PCP: TCP mapping also open on $externalPort');
      return true;
    } catch (e) {
      log?.call('PCP TCP mapping: $e');
      return false;
    }
  }

  // ── Socket Helpers ────────────────────────────────────────────────

  /// Binds an OWN socket for exactly one dialogue.
  ///
  /// Expressly closes no other — see [_openSockets].
  Future<RawDatagramSocket?> _bindSocket() async {
    try {
      final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _openSockets.add(s);
      return s;
    } catch (e) {
      log?.call('NAT-PMP socket not bound: $e');
      return null;
    }
  }

  /// Releases the socket of ONE dialogue. Belongs in a `finally`.
  void _closeSocket(RawDatagramSocket? s) {
    if (s == null) return;
    _openSockets.remove(s);
    try {
      s.close();
    } catch (_) {}
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
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return null;
  }
}
