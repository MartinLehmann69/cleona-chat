/// Whom the IPv6 keep-alive holds open, and which contact seat does not
/// count on a metered link (V4.2 §8.1; proposal "contacts as fixed
/// neighbours", version 3, section 6.3, owner decision 24.09.2026: D5 = a).
///
/// ── IPv6: EACH FIXED CONTACT NEIGHBOUR ─────────────────────────────────
///
/// A fixed neighbour of the recipient forwards to it (§8.1 step 3) — it
/// must be able to reach the node unsolicited. Behind a stateful firewall
/// that holds only while the node sends to it. So the IPv6 keep-alive goes
/// to every contact seat (`neighbourhood_contacts.dart`) that is an IPv6
/// neighbour, and to the card's seat only while a standing invitation
/// names it (its readers come through it, §5.2). Where there is none of
/// them, it goes to ONE neighbour as before: the card's seat if it has
/// IPv6, otherwise the most recently confirmed IPv6 neighbour.
///
/// All of them leave in the SAME look (`KeepAlive.tick`): one radio wake
/// per interval, however many fixed neighbours there are — as the two
/// address families already go together. None is sent on one found open
/// (`open_check.dart`) or mapped; none to a path cover refreshed within the
/// interval. IPv4 stays at one neighbour (`KeepAlive`, unchanged).
///
/// ── METERED: A CONTACT REACHABLE ONLY OVER IPv4 DOES NOT COUNT ─────────
///
/// On a metered link IPv4 is kept open towards ONE neighbour; a translator
/// that filters by address lets through only that one (RFC 4787 REQ-8:
/// endpoint-independent filtering is recommended for transparency,
/// address-dependent filtering where stringent filtering matters — a
/// carrier may do either, and none documents which). A contact that could reach the node only over IPv4 —
/// because it has no public IPv6 address or the node itself has no IPv6 —
/// would therefore not reach it: it takes no contact seat there and gives
/// up the one it holds; another contact takes it ([v4OnlyOnMetered],
/// applied by `neighbourhood_contacts.dart` at the edges, the metered flag
/// being one of them: `HostNetwork`).
///
/// Pure functions over the neighbourhood; no clock, no packet.
library;

import 'dart:io';

import 'package:mycelium/neighbourhood.dart';

/// The IPv6 keep-alive targets at [now], in the order of
/// [Neighbourhood.fixedNeighbours] (contact seats by number, then the card's
/// seat); empty: none of them is an IPv6 neighbour, the caller keeps one.
List<NeighbourAddress> fixedV6Targets(Neighbourhood hood, DateTime now) {
  final notBefore = now.subtract(Neighbourhood.staleAfter);
  return [
    for (final n in hood.fixedNeighbours)
      if (n.contactSeat > 0 || (n.fixed && hood.namedByCards(n)))
        if (n.confirmedIn(InternetAddressType.IPv6, notBefore) case final a?) a
  ];
}

/// Whether [n] could reach the node only over IPv4 on a [metered] link —
/// then it does not count as a fixed contact neighbour (§8.1, 6.3).
/// [ownV6]: the node has an IPv6 socket and a global IPv6 address.
bool v4OnlyOnMetered(Neighbour n,
        {required bool metered,
        required bool ownV6,
        required bool Function(InternetAddress a) public}) =>
    metered &&
    !(ownV6 &&
        n.addresses.any((a) =>
            a.address.type == InternetAddressType.IPv6 &&
            a.confirmedEver &&
            public(a.address)));
