// Pure IP address classification: string in, judgement out.
//
// EXTRACTED ON 2026-08-31 (CUT, step 0) from
// `lib/core/network/peer_info.dart`.
//
// WHY. `peer_info.dart` is a V3 wire model (1681 lines, protobuf
// conversions, address scoring, routes). In it lay a collection of functions
// that know nothing of that: they take an address as a string and
// return a `bool` or a string. No socket, no
// state, no packet format.
//
// Four files outside the V3 tree imported `peer_info.dart`
// EXCLUSIVELY for that — measured on 2026-08-31:
//
//   lib/core/update/physical_transfer_helper.dart:173  — only `isPrivateIp`
//   lib/core/update/invite_link_service.dart:78        — only `isPrivateIp`
//   lib/core/rendezvous/binary_rendezvous_manager.dart:192 — only `isPrivateIp`
//   lib/core/rendezvous/infra_rendezvous_manager.dart:96   — only `isPrivateIp`
//
// Four import edges of the application layer onto `lib/core/network/` for an
// `if` cascade over prefixes. They now read from here.
//
// WHAT DELIBERATELY STAYED IN `peer_info.dart` — and why that is no
// half-hearted cut but a measured boundary:
//
//   `PeerAddress.classifyIp` returns a `PeerAddressType`. This enum is
//   a V3 WIRE VALUE (it stands so in the protobuf address record) and occurs at
//   156 places in 10 files. Taking it along here would mean either
//   letting `lib/core/util/` import `lib/core/network/` — a
//   NEW edge in exactly the direction the CUT dismantles — or rewriting 156 places.
//   `classifyIp` moreover has ZERO callers outside the
//   V3 tree (`dht/kbucket.dart`, `node/identity_context.dart`,
//   `node/cleona_node.dart`, one smoke), so it costs no edge. It stays.
//
//   `PeerAddress.hasGlobalIpv6` and `hasAnyUlaAddress` are not pure
//   functions: they read `PeerAddress.currentLocalIps`, a MUTABLE
//   static field that `CleonaNode` sets anew at every interface change
//   (`lib/core/node/cleona_node.dart:1412` and `:6759`). That is
//   environment state of the V3 transport, no classifier. They too have
//   no caller outside the V3 tree.
//
// ADDENDUM 2026-09-03: EVERYTHING FROM HERE ON IS HISTORY. `lib/core/network/`,
// `lib/core/node/` and `lib/core/dht/` each have ZERO files (measured on
// 2026-09-03); `peer_info.dart` no longer exists, and with it the
// forwardings described below and the thirteen callers have fallen —
// just as the paragraph itself predicted. The text stays,
// because it carries the REASONING of this file, not as a signpost.
//
// FORWARDINGS IN `peer_info.dart`. Unlike with `DataPort` (AP-3a
// stage 1) and with `MultiInterfaceMode` (the same step) the
// `PeerAddress.*` names stayed as one-line forwardings to this file.
// That is a deviation from the principle "one access", and it is
// time-limited: the thirteen remaining callers ALL lie in the V3 tree
// (`network/nat_traversal.dart`, `network/udp_keepalive.dart`,
// `network/rendezvous/*`, `dht/kbucket.dart`, `node/cleona_node.dart`) and
// die with it. Switching them over now would carry the cut into files
// that the CUT removes as a whole anyway — work that is thrown away
// twice. Switched over are exactly the callers whose edge thereby
// disappears.

import 'dart:io' show InternetAddress, InternetAddressType;

/// Classifiers over IP addresses in text form. All members are pure:
/// same input, same output, no state.
abstract final class IpAddressClass {
  /// Whether [ip] is non-routable from the public internet.
  ///
  /// IPv6: link-local (`fe80:`), ULA (`fc`/`fd`), loopback (`::1`). Global
  /// IPv6 counts as public — there is no NAT in front of it.
  /// IPv4: RFC 1918 (10/8, 172.16/12, 192.168/16), loopback 127/8, CGNAT
  /// 100.64/10 (RFC 6598) and the DS-Lite well-known prefix 192.0.0.0/24.
  ///
  /// Taken over verbatim from `peer_info.dart::_isPrivateIp` (declared there at file level
  /// until 2026-08-31, now a forwarding to here).
  static bool isPrivate(String ip) {
    // IPv6 classification
    if (ip.contains(':')) {
      final lower = ip.toLowerCase();
      if (lower.startsWith('fe80:')) return true;   // Link-local
      if (lower.startsWith('fc') || lower.startsWith('fd')) return true; // ULA
      if (lower == '::1') return true;              // Loopback
      return false; // Global IPv6 = public (no NAT)
    }
    // IPv4
    if (ip.startsWith('10.')) return true;
    if (ip.startsWith('172.')) {
      final second = int.tryParse(ip.split('.')[1]);
      if (second != null && second >= 16 && second <= 31) return true;
    }
    if (ip.startsWith('192.168.')) return true;
    if (ip.startsWith('127.')) return true;
    // CGNAT ranges — not routable from the internet
    if (ip.startsWith('100.')) {
      final second = int.tryParse(ip.split('.')[1]) ?? 0;
      if (second >= 64 && second <= 127) return true; // 100.64.0.0/10
    }
    if (ip.startsWith('192.0.0.')) return true; // IETF reserved / DS-Lite
    return false;
  }

  // DROPPED ON 09.09.2026 (S378): no caller in lib/ or test/.
  // It was the SECOND truth about non-dialable addresses:
  // `tagline/local_addresses.dart::isUndialableIpv4` answers the same
  // question more broadly (CGNAT, DS-Lite/464XLAT AND link-local) and carries there
  // the sentence "No second determiner, no second truth". The consumer "WIN-4"
  // named in the docs did not exist in lib/.

  /// Whether two IPv4 addresses share a /24. False for any IPv6 input —
  /// IPv6 has no /24 concept and is handled by scope classification instead.
  ///
  /// Taken over from `peer_info.dart::PeerAddress._sameSubnet`.
  static bool sameSubnet24(String ip1, String ip2) {
    if (ip1.contains(':') || ip2.contains(':')) return false;
    final p1 = ip1.split('.');
    final p2 = ip2.split('.');
    if (p1.length != 4 || p2.length != 4) return false;
    return p1[0] == p2[0] && p1[1] == p2[1] && p1[2] == p2[2];
  }

  /// Whether [ip] shares a /24 with at least one of [localIps] (IPv4 only).
  ///
  /// Used by the routing-table audit pass to decide whether a private address
  /// is reachable from the current host: 10.0.2.x emulator-NAT addresses on a
  /// 192.168.10.x host are not.
  ///
  /// Taken over from `peer_info.dart::PeerAddress.isInLocalSubnet`.
  static bool isInLocalSubnet(String ip, Iterable<String> localIps) {
    if (ip.contains(':')) return false; // IPv6 handled separately
    for (final localIp in localIps) {
      if (sameSubnet24(ip, localIp)) return true;
    }
    return false;
  }

  /// Whether both IPs sit in the SAME RFC 1918 block (10/8, 172.16-31/12 or
  /// 192.168/16). False for IPv6 and for non-private inputs.
  ///
  /// Used by NAT-egress detection: an observed IP that is private AND in the
  /// same class as ours is most likely an echo of our own LAN address, not a
  /// legitimate cross-NAT egress.
  ///
  /// Taken over from `peer_info.dart::PeerAddress.samePrivateClass`.
  static bool samePrivateClass(String ip1, String ip2) {
    if (ip1.contains(':') || ip2.contains(':')) return false;
    if (ip1.startsWith('10.') && ip2.startsWith('10.')) return true;
    if (ip1.startsWith('192.168.') && ip2.startsWith('192.168.')) return true;
    final p1 = ip1.split('.');
    final p2 = ip2.split('.');
    if (p1.length >= 2 && p2.length >= 2 && p1[0] == '172' && p2[0] == '172') {
      final s1 = int.tryParse(p1[1]) ?? 0;
      final s2 = int.tryParse(p2[1]) ?? 0;
      if (s1 >= 16 && s1 <= 31 && s2 >= 16 && s2 <= 31) return true;
    }
    return false;
  }

  /// Collapse an IPv4-mapped IPv6 textual address (`::ffff:a.b.c.d`,
  /// RFC 4291 §2.5.5.2) to its plain dotted IPv4 form. Everything else is
  /// returned unchanged.
  ///
  /// Field evidence 2026-07: dual-stack sockets (`anyIPv6` without
  /// `IPV6_V6ONLY`) report IPv4 senders in the mapped form. Stored verbatim,
  /// the string contains ':' and therefore walks every IPv6 code path, so the
  /// same physical endpoint exists twice — once dead, once alive
  /// (`::ffff:192.0.2.15` score 0.5 / 0 successes next to `192.0.2.15` score
  /// 0.988 / 11890 successes in a real routing-table snapshot).
  ///
  /// The rare hex-tail form (`::ffff:c0a8:aca`) is left untouched: Dart's
  /// `InternetAddress` always renders mapped addresses with a dotted tail, so
  /// hex tails cannot originate from our own stack.
  ///
  /// Taken over from `peer_info.dart::PeerAddress.normalizeIp`.
  static String normalizeIp(String ip) {
    final lower = ip.trim().toLowerCase();
    if (!lower.startsWith('::ffff:')) return ip;
    final tail = lower.substring(7);
    if (!tail.contains('.')) return ip;
    // Defensive: only accept a tail that actually parses as IPv4 —
    // '::ffff:garbage.x' must not become a bogus dotted "address".
    final parsed = InternetAddress.tryParse(tail);
    if (parsed == null || parsed.type != InternetAddressType.IPv4) return ip;
    return tail;
  }
}
