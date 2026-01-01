// Under which addresses a partner can dial this node.
//
// ── WHY THIS STANDS HERE AND IS NOT FETCHED FROM V3 (S350) ────────────
//
// Until S350 `v41_attach.dart` pulled `Transport.getAllLocalIps()` from
// `lib/core/network/` for this. The guard `smoke_link_io_milestone` section 5
// reported that as a violation, and it is right — for two reasons that
// are both demonstrable in the code:
//
//  1. **Weight.** (Historical — `lib/core/network/` has had zero files since the CUT of
//     2026-08-31, measured 2026-09-03.)
//     `lib/core/network/transport.dart` pulled in, in its
//     first thirteen lines, `network_secret`, `clogger`,
//     `multi_interface`, three platform-dependent UDP senders,
//     `udp_fragmenter`, `binary_http_server` and the generated
//     V3 protobufs. A `static` helper function thus hangs the
//     ENTIRE V3 transport layer onto every process that starts a
//     V4.1 node. That is literally the error D-5, because of
//     which this guard exists: there it was a `static const int`,
//     here a `static` method.
//
//  2. **It is not even the same question.** V3 asks "which local IPs
//     do I have" and sorts them for ITS purpose ("WiFi/LAN interfaces
//     are preferred over mobile data"). V4.1 asks "under which address
//     can a partner DIAL me" — and already had to correct the V3 answer
//     before S350: `getAllLocalIps` counts `192.0.0.0/29`
//     (DS-Lite/464XLAT) and `100.64/10` (CGNAT) expressly among the
//     PRIVATE ones and thus sorts them to the FRONT, although under them
//     nobody arrives. On 28.08. in the field: the phone hung in the WLAN under
//     `192.168.178.34` and announced `192.0.0.4:31811` (B-26).
//
// The comment at the old place said "No second determiner, no
// second truth". The second truth already existed at that point —
// it stood as a post-filter directly below the call. Here it stands
// completely at ONE place, instead of half borrowed and half corrected.
//
// WHAT IS DELIBERATELY TAKEN OVER. The exclusions that V3 worked out
// and that apply to V4.1 just the same: loopback, `0.0.0.0`, IPv6
// link-local, and the Windows pseudo-interfaces from WIN-2 (Teredo, 6to4,
// documentation prefix, IPv4-mapped) — they flap as soon as the kernel
// creates them anew, and an announcement address that flaps is none.
//
// NO SORTING BY INTERFACE NAMES. `NetworkInterface.list` returns the
// order of the operating system, and on Android `rmnet` stands
// before `wlan0`. Whoever relies on that chooses the wrong one on every mobile device.
// Sorting is by PROPERTY of the address, not by origin.
library;

import 'dart:io';

import 'host_interfaces.dart';

/// Is nobody reachable under this address?
///
/// The three ranges that LOOK like a usable private address and
/// are not (B-26). They are no special case of mobile: `192.0.0.0/29`
/// is the IETF reservation from which 464XLAT takes its CLAT address,
/// `100.64/10` is CGNAT (RFC 6598), `169.254/16` is the
/// self-configuration without DHCP. From none of the three does a call come back.
bool isUndialableIpv4(String ip) {
  if (ip.startsWith('192.0.0.')) return true; // DS-Lite / 464XLAT
  if (ip.startsWith('169.254.')) return true; // link-local, no DHCP
  if (ip.startsWith('100.')) {
    final second = int.tryParse(ip.split('.')[1]) ?? 0;
    return second >= 64 && second <= 127; // CGNAT, RFC 6598
  }
  return false;
}

/// IPv4 from one of the private ranges (RFC 1918)?
///
/// Private first, because in the same segment the direct path is the only one
/// that carries without a NAT hole — and because a node only knows its public
/// address anyway if it happens to have one.
bool isPrivateIpv4(String ip) {
  if (ip.startsWith('192.168.')) return true;
  if (ip.startsWith('10.')) return true;
  if (ip.startsWith('172.')) {
    final second = int.tryParse(ip.split('.')[1]);
    return second != null && second >= 16 && second <= 31;
  }
  return false;
}

/// An IPv6 pseudo-interface that means no reachability (WIN-2).
bool isTunnelIpv6(String ip) {
  if (!ip.contains(':')) return false;
  final kern = ip.toLowerCase().split('%').first;
  if (kern.startsWith('2001:0:') || kern.startsWith('2001::')) return true;
  if (kern.startsWith('2002:')) return true;
  if (kern.startsWith('2001:db8:')) return true;
  if (kern.startsWith('::ffff:')) return true;
  return false;
}

/// The dialable addresses of this node, in announcement order.
///
/// Order: private IPv4, then public IPv4, then global IPv6.
/// Empty is an admissible result — a node without a dialable address
/// is reachable as soon as it dials itself, and the caller says so in the
/// log instead of announcing a loopback address.
///
/// DOES NOT THROW. The enumeration can fail during an interface change
/// (regularly on iOS); that is no start error, but a
/// later attempt.
/// **THE FILTER HAS STOOD IN `lib/core/util/host_interfaces.dart` SINCE S376.**
/// It arose here (S374, B-4) and was also only used here; six
/// further loops in the tree ask the same question and lay below or
/// next to `tagline/`, so could not call it. Moved completely,
/// no forwarding left behind (AP-1b).

Future<List<String>> dialableLocalAddresses() async {
  final all = <NetworkInterface>[];
  try {
    all.addAll(await NetworkInterface.list(type: InternetAddressType.IPv4));
  } catch (_) {
    // Enumeration during an interface change — silent (E-83).
  }
  try {
    all.addAll(await NetworkInterface.list(type: InternetAddressType.IPv6));
  } catch (_) {
    // IPv6 not available — no error.
  }
  return dialableFrom(all);
}

/// The same answer from interfaces read elsewhere — the delivery layer's
/// list, read at its edges start and network change (S408-LEBENSLAUF P16,
/// finding A-5: one source, no second enumeration beside the host). Private
/// IPv4 first, then public IPv4, then IPv6 — the NAT assistant's forwarding
/// target is the first.
List<String> dialableFrom(Iterable<NetworkInterface> interfaces) {
  final private = <String>[];
  final public = <String>[];
  final v6 = <String>[];
  for (final iface in interfaces) {
    if (!interfaceLeadsAfterOutside(iface.name)) continue;
    for (final addr in iface.addresses) {
      final ip = addr.address;
      if (addr.type == InternetAddressType.IPv4) {
        if (addr.isLoopback || ip == '0.0.0.0') continue;
        if (isUndialableIpv4(ip)) continue;
        (isPrivateIpv4(ip) ? private : public).add(ip);
      } else {
        if (addr.isLoopback || addr.isLinkLocal) continue;
        if (isTunnelIpv6(ip)) continue;
        v6.add(ip);
      }
    }
  }
  return <String>[...private, ...public, ...v6];
}

/// An IPv6 address from `fc00::/7` — Unique Local Address (RFC 4193).
///
/// It looks like a global IPv6 (no `fe80:` prefix, no
/// special form) and is nonetheless reachable nowhere in the internet: it is the
/// IPv6 counterpart to RFC 1918. Fritzbox and OpenWrt assign it
/// by default NEXT TO the global address, so a node often has both.
///
/// PROVEN, not assumed: on the public entry board of the channel
/// `cleona-beta` on 06.09.2026 among 17 records lay two
/// `fdb2:` addresses. Until then nobody queried them: `dialableLocalAddresses`
/// filters IPv6 only against loopback, link-local and [isTunnelIpv6] — in none
/// of the three checks does `fc00::/7` stand.
bool isUlaIpv6(String ip) {
  if (!ip.contains(':')) return false;
  final kern = ip.toLowerCase().split('%').first;
  return kern.startsWith('fc') || kern.startsWith('fd');
}

/// Does someone from OUTSIDE the own network arrive under [ip]?
///
/// ── WHAT FOR THIS SECOND QUESTION NEXT TO [dialableLocalAddresses] ──────────
///
/// [dialableLocalAddresses] answers "under which address can a
/// partner dial me" — and the answer expressly INCLUDES the private IPv4,
/// because in the own segment exactly they are the only path without a
/// NAT hole (see [isPrivateIpv4]). This function answers the
/// other half: whether one of these addresses also means something for a stranger in the
/// internet.
///
/// Both answers are needed, at different places. The LAN call
/// (step 2 of the entry cascade) LIVES on the private addresses; the
/// global entry board (step 5, §11.3) chokes on them. Whoever builds this
/// filter in further down — in [dialableLocalAddresses], in
/// `setzeAnsageadressen` or in `V41Node.ownEntry` — destroys the
/// LAN entry, i.e. exactly the step that carries in the home network.
///
/// ── THE FINDING (06.09.2026) ────────────────────────────────────────
///
/// A `resolve` on the public board of the channel `cleona-beta`
/// delivered 17 records with 30 private IPv4, ZERO public IPv4,
/// 3 global IPv6 and 2 ULA. **15 of the 17 records carried not a single
/// address dialable from outside.** Whoever reads the board for a cold start
/// dials into the void fifteen times.
///
/// ── IT ASKS THE ADDRESS, NOT ITS ORIGIN ─────────────────────
///
/// That is intentional and not incidental: an external address obtained via port mapping
/// (owner decision 07.09.2026, built in
/// another package) comes through here without a special case as soon as it stands in the
/// announcement addresses. A function that instead asked about the source
/// would have to be updated at every new path — and would be forgotten at the
/// next one.
///
/// ── WHY NOT `IpAddressClass.isPrivate` ─────────────────────────
///
/// The classifier in `lib/core/util/ip_address_class.dart` does NOT know
/// `169.254/16` (IPv4 link-local, DHCP failure), and none of the
/// four IPv6 pseudo-forms from WIN-2 (Teredo `2001:0:`, 6to4 `2002:`,
/// documentation prefix `2001:db8:`, IPv4-mapped `::ffff:`). It is the
/// V3 heir and serves the rendezvous managers; here it would have left a GAP.
/// This function instead builds ON the predicates
/// that this file carries anyway. No second truth arises from that:
/// it is the conjunction of the first.
///
/// OWN ADDRESS, NOT FOREIGN. `::ffff:a.b.c.d` counts here as NOT
/// reachable, because on the OWN interface it is a Windows
/// pseudo-interface (WIN-2). As the SOURCE ADDRESS of an incoming session
/// the same form is on the other hand a valid IPv4 partner — whoever
/// uses it that way converts it beforehand (`IpAddressClass.normalizeIp`, as
/// the inbound proof in `v41_attach.dart` does).
bool isExternallyReachable(String ip) {
  final k = ip.trim().toLowerCase();
  if (k.isEmpty) return false;
  if (k.contains(':')) {
    final kern = k.split('%').first; // Zonenindex (`%eth0`) weg
    if (kern == '::' || kern == '::1') return false;
    if (kern.startsWith('fe80:')) return false; // link-local
    if (isUlaIpv6(kern)) return false; // fc00::/7
    if (isTunnelIpv6(kern)) return false; // WIN-2
    return true;
  }
  if (k == '0.0.0.0' || k.startsWith('127.')) return false;
  if (isUndialableIpv4(k)) return false; // DS-Lite, CGNAT, 169.254
  if (isPrivateIpv4(k)) return false; // RFC 1918
  return true;
}

/// Two private IPv4 in the same RFC1918 class? (V3: `samePrivateClass`)
///
/// ── WHAT FOR, AND WHY HERE (S379) ────────────────────────────────────
///
/// Two questions need the same probe. `beobachteteAnsageadressen`
/// (`v41_attach.dart`) uses it to distinguish the ECHO of the own LAN from
/// a real exit; dialling (`dialAddressOrder`) uses it to decide
/// whether a private address from a foreign record comes into question at all for
/// THIS node. The probe stood as a private
/// function in `v41_attach.dart` and has moved here, where the
/// remaining address predicates lie — no forwarding
/// left behind (AP-1b).
///
/// **Limit, expressly:** it works on the CLASS (10/8,
/// 172.16/12, 192.168/16), not on the subnet. `192.168.10.5` and
/// `192.168.178.20` count as belonging to the same class — in a
/// routed intranet that is right, it is exactly the case this
/// probe is meant to hit; two home networks behind different connections
/// thereby hit each other with at most one failed attempt.
bool samePrivateClass(String a, String b) {
  if (a.startsWith('10.') && b.startsWith('10.')) return true;
  if (a.startsWith('192.168.') && b.startsWith('192.168.')) return true;
  final pa = a.split('.');
  final pb = b.split('.');
  return pa.length >= 2 && pb.length >= 2 && pa[0] == '172' && pb[0] == '172';
}

// ── "IS AN ADDRESS EVENT ALSO AN ADDRESS CHANGE?" (S380 → S407-LB-P14) ──
//
// `isRealNetworkChange` stood here from S380: daemon and app compared the
// dialable addresses before and after an event, so a router advertisement
// that only renews lifetimes (measured on the bootstrap on 10.09.2026: six
// in 40 minutes, each tearing down all sessions) is no change —
// [dialableLocalAddresses] returns addresses, not lifetimes. It also said
// "the first run counts as a change": every caller started with an EMPTY
// list, so the first report after a start ran the whole edge for nothing
// (finding A-1). The decision moved with S407-LB-P14 into the delivery
// layer (`mycelium/lib/network_watch.dart`), which reads the own addresses
// at the start; [dialableLocalAddresses] stays here as the one list it
// compares. What it does not see is unchanged: a change that leaves the
// dialable addresses alone (another gateway, only the EXTERNAL address) —
// the latter is covered by §17.3 via `onAgreedChanged`.
