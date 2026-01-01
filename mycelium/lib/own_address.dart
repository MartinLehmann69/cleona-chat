/// Which own address a node writes into its card.
///
/// A file of its own and not `node_helpers.dart`, for two reasons.
/// First, it is a DECISION with a price (see
/// [rankTheAddress]), not a convenience like `hexFrom` or `wuerfeln`.
/// Second, `node_helpers.dart` with this code stood at exactly 400
/// lines — the line budget from `mycelium/README.md` rule 2 —, and a
/// file at the limit is the invitation to put the next piece elsewhere,
/// where it does not belong.
///
/// The counterpart is in `wire_target.dart`: there, which FOREIGN address
/// is impossible as a target; here, which OWN address is of any use
/// as a hint. Both are knowledge about addresses, neither needs a socket.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/card_address.dart'
    show CardAddress, kOwnAddressesAtMost;
import 'package:mycelium/node_helpers.dart' show isPrivate;

/// How usable an own address is as a hint in the card —
/// larger is better, `-1` means unusable.
///
/// | Rank | What | Why there |
/// |---|---|---|
/// | 3 | global IPv6 | reachable everywhere, without address translation (§11.1) |
/// | 2 | global IPv4 | reachable everywhere |
/// | 1 | IPv6 ULA `fc00::/7` | reachable in the segment, needs no zone identifier |
/// | 0 | private IPv4 (RFC 1918) | reachable in the segment |
/// | -1 | everything else | see below |
///
/// **Unusable and therefore `-1`:** the loopback (the recipient
/// would land at himself), link-local `169.254/16` and `fe80::/10` (without
/// zone identifier a throw there goes nowhere, and the zone identifier of the
/// OTHER machine is meaningless), group and broadcast addresses, the
/// unspecified address, `100.64/10` (RFC 6598, CGNAT).
///
/// The order „global first, IPv6 before IPv4" has a PRICE: the
/// card has exactly ONE LAN field (§15.2). A counterpart without
/// IPv6 socket (§11.1 explicitly allows that) cannot use an
/// IPv6 hint and falls back to steps 2 to 4.
int rankTheAddress(InternetAddress a) {
  if (a.isLoopback) return -1;
  final b = a.rawAddress;
  if (b.every((x) => x == 0)) return -1;
  if (b.length == 16) {
    if (b[0] == 0xFF) return -1; // ff00::/8
    if (b[0] == 0xFE && (b[1] & 0xC0) == 0x80) return -1; // fe80::/10
    if ((b[0] & 0xFE) == 0xFC) return 1; // fc00::/7
    return 3;
  }
  if (b.length != 4) return -1;
  if (b[0] == 0 || b[0] >= 224) return -1;
  if (b[0] == 169 && b[1] == 254) return -1; // RFC 3927
  if (b[0] == 100 && b[1] >= 64 && b[1] <= 127) return -1; // RFC 6598
  return isPrivate(a) ? 0 : 2;
}

/// The best own address for the LAN field of the card — or `null`
/// if this machine has no usable one.
///
/// Until S390 this place took the FIRST address that is not the
/// loopback, without any check — and otherwise returned `127.0.0.1`.
/// Both were wrong: with several interfaces the first address is
/// arbitrary (host network, bridge, virtual network), and `127.0.0.1` in a
/// card is not a hint at the issuer but one at the
/// recipient himself — it costs the counterpart a whole ladder step and
/// never finds anyone (the same reasoning as with `cardFor`).
///
/// `null` means „I have none that is of use to another". The
/// caller should be able to SAY that instead of inventing an address.
Uint8List? ownLanAddress(List<NetworkInterface> interfaces) {
  Uint8List? best;
  var bestRank = -1;
  var bestLink = 0;
  for (final s in interfaces) {
    final link = linkKindFrom(s.name).priority;
    for (final a in s.addresses) {
      final r = rankTheAddress(a);
      if (r < 0) continue;
      // FIRST the link (§10, §23.1: „cellular as the last choice"),
      // only then the address range. The other way round, on a phone
      // with WLAN AND cellular, the global IPv6 of cellular would win against the
      // private IPv4 of the WLAN — and the card would take the expensive route while
      // the neighbour in the same network sits one hop away.
      if (best == null ||
          link > bestLink ||
          (link == bestLink && r > bestRank)) {
        bestRank = r;
        bestLink = link;
        best = Uint8List.fromList(a.rawAddress);
      }
    }
  }
  return best;
}

/// Old name and old contract, so that `node_invitation.dart` keeps running
/// unchanged: never `null`, if need be `127.0.0.1`.
///
/// **The name has no longer been correct since S390** — on a host with global
/// IPv6, 16 bytes come out here, and the card carries them (§11.1: „A
/// node with a global IPv6 address advertises it in its card"; §15.2: every
/// address has its own type byte). The fallback to `127.0.0.1` is the
/// remainder of the old error and only stays because the caller lies in another
/// tree. New code takes [ownLanAddress] and checks for `null`.
Uint8List ownIpv4(List<NetworkInterface> interfaces) =>
    ownLanAddress(interfaces) ?? Uint8List.fromList([127, 0, 0, 1]);

/// Whether this host has an IPv6 address under which anyone can reach it
/// at all — the question that is asked BEFORE binding the second socket
/// (§11.1).
///
/// ── WHY THIS IS ASKED AND NOT TRIED ────────────────────────
///
/// Until S390 `Wire.open` bound the IPv6 socket unconditionally and caught
/// the error. That is the wrong way round: a bind on `::` does
/// succeed on a host entirely without IPv6 — the socket then
/// stands, [Wire.hasIpv6] says `true`, and only the first throw fails
/// (errno 101, asynchronous, and it ends the socket). The error
/// thus does not become visible where it arises, but one layer and
/// some seconds later. A node should know its network environment
/// instead of exploring it by failing.
///
/// ── WHERE THE LIMIT LIES ──────────────────────────────────────────────
///
/// Asked for is [rankTheAddress] >= 1, i.e. global IPv6 or ULA
/// `fc00::/7`. Deliberately NOT link-local `fe80::/10`: an fe80 address
/// without zone identifier is not a target another can use, and it never
/// goes into a card (owner decision 16.09.2026: "link-local
/// as public makes no sense! Do not publish"). A host
/// that has ONLY fe80 has nothing it could offer — for it
/// the second socket is a socket without purpose.
bool usableIpv6Present(List<NetworkInterface> interfaces) {
  for (final s in interfaces) {
    for (final a in s.addresses) {
      if (a.rawAddress.length == 16 && rankTheAddress(a) >= 1) return true;
    }
  }
  return false;
}

/// What an interface hangs on — the question that §10, §22.6 and §23.1
/// have long answered normatively and that nobody asked until S390.
///
/// > §10: „reachable at all → link type (**wired/WLAN before cellular**) →
/// > power source → measured usable upload → RTT as a tie-break"
/// > §23.1: „**cellular as the last choice when selecting an interface**"
///
/// ── WHY HERE AND NOT IN `uplink_state.dart` ──────────────────────
///
/// The app keeps in `lib/core/util/uplink_state.dart` a class
/// `Netzart`, and it answers a DIFFERENT question: „does the route
/// out cost money?", node-wide, one value. Exactly that is of no use here. A
/// phone with WLAN AND cellular has two links at the same time, and the
/// question is which of the two ADDRESSES is the better one — that is a
/// property per interface, not of the node. §22.4.1 also assigns the
/// precedence rule to `lib/core/sync/`; that layer is superseded,
/// and the delivery layer that needs it today is `mycelium/`.
///
/// ── WHAT THIS DETECTION IS AND WHAT IT IS NOT ────────────────────────────
///
/// It reads the NAME of the interface. That is a heuristic, and it
/// is named as such here instead of being passed off as knowledge: `dart:io`
/// gives via `NetworkInterface` nothing but name, index and addresses,
/// and a platform channel per system would be a high price for an ORDER.
/// The names come from the systems themselves — `wlan0`/`wlp*`
/// (Linux, Android), `en*` (macOS/iOS, there also WLAN), `rmnet*`,
/// `ccmni*`, `pdp_ip*` (Android cellular), `pdp*`/`rmnet*` (iOS).
///
/// **The error is deliberately placed in one direction:** whatever is not
/// recognised is [LinkKind.unknown] and stands BEFORE cellular,
/// not behind it. Wrongly deferring an unknown interface
/// costs the better route; wrongly taking it for cellular
/// costs it too — but the more frequent case is an
/// unknown name on a desktop, and that is never cellular.
enum LinkKind {
  cable(3),
  wlan(2),
  vpn(1),
  unknown(0),
  cellular(-1);

  const LinkKind(this.priority);

  /// Larger is better. Cellular is the only negative value — it is
  /// „the last choice" (§23.1), not merely a worse one.
  final int priority;
}

/// The link kind from the name of an interface. See
/// [LinkKind] — heuristic, named as such.
LinkKind linkKindFrom(String name) {
  final n = name.toLowerCase();
  // Cellular first: `rmnet_data0` would otherwise be caught by nobody, and `pdp_ip0`
  // contains no abbreviation of the other classes.
  for (final m in const ['rmnet', 'ccmni', 'pdp_ip', 'pdp', 'wwan', 'ppp']) {
    if (n.startsWith(m)) return LinkKind.cellular;
  }
  for (final w in const ['wlan', 'wlp', 'wl', 'wifi', 'ap']) {
    if (n.startsWith(w)) return LinkKind.wlan;
  }
  for (final v in const ['tun', 'tap', 'utun', 'wg', 'ipsec']) {
    if (n.startsWith(v)) return LinkKind.vpn;
  }
  for (final k in const ['eth', 'enp', 'eno', 'ens', 'en', 'em', 'rndis']) {
    if (n.startsWith(k)) return LinkKind.cable;
  }
  return LinkKind.unknown;
}


/// The addresses that go into the own card — ordered, deduplicated and
/// capped (§15.2).
///
/// **The order IS the statement** („in the issuer's order of
/// preference"), and it has two levels, in this sequence:
///
///  1. the LINK ([linkKindFrom]) — cable, WLAN and VPN before
///     cellular (§10, §23.1);
///  2. within a link the address range ([rankTheAddress]).
///
/// The other way round, a phone with WLAN and cellular would take the global IPv6 of
/// cellular first, while the neighbour in the same WLAN sits one hop
/// away.
///
/// Unusable addresses ([rankTheAddress] < 0) drop out — the
/// loopback, link-local, CGNAT. A device in cellular behind CGNAT
/// therefore gets an EMPTY list, and that is the right answer: it
/// has nothing that is of use to another (§15.2, count byte `0`). Until S390
/// this place lied `127.0.0.1` into the card at this point.
List<CardAddress> ownAddressesOrdered(
    List<NetworkInterface> interfaces, int port) {
  final candidates = <({int link, int rank, Uint8List raw})>[];
  for (final s in interfaces) {
    final link = linkKindFrom(s.name).priority;
    for (final a in s.addresses) {
      final rank = rankTheAddress(a);
      if (rank < 0) continue;
      candidates.add((
        link: link,
        rank: rank,
        raw: Uint8List.fromList(a.rawAddress)
      ));
    }
  }
  candidates.sort((x, y) => x.link != y.link
      ? y.link.compareTo(x.link)
      : y.rank.compareTo(x.rank));
  final seen = <String>{};
  final out = <CardAddress>[];
  for (final k in candidates) {
    if (out.length >= kOwnAddressesAtMost) break;
    if (!seen.add(k.raw.join('.'))) continue;
    out.add(CardAddress(k.raw, port));
  }
  return out;
}
