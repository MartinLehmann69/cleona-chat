/// Joining addresses into one neighbour, and sorting them by address
/// family — the two computations behind `Neighbourhood.ownAddresses` and
/// `Neighbourhood.socketsChanged` (S394 V1, V4).
///
/// Pure functions over a list of neighbours: they change nothing and send
/// nothing; `neighbourhood.dart` applies what they return. Separate
/// because the neighbourhood is at its line budget (mycelium/README.md
/// rule 2), and because what is computed here can be checked without a
/// neighbourhood around it.
library;

import 'dart:io';

import 'package:mycelium/card_address.dart';
import 'package:mycelium/neighbour.dart';

/// What a join replaces: [joined] leave the list, [whole] takes their place.
typedef Join = ({List<Neighbour> joined, Neighbour whole});

/// [from]:[port] named [own] as its own addresses (§5.5, §11.8a) — joins
/// into ONE neighbour every entry of [list] that holds [from]:[port] or one
/// of [own] (as address or name), plus [own] itself: an address of a family
/// this node [speaks] as an unconfirmed address, any other as a name. The
/// id and the fixed seat move over from the joined entries — the fixed one
/// first, then the one holding [from]:[port].
///
/// `null` if [from]:[port] is not among [own]: then nothing here is bound
/// (V4: "in a sealed packet that comes from one of them").
Join? joinOwn(List<Neighbour> list, InternetAddress from, int port,
    List<CardAddress> own, bool Function(InternetAddress a) speaks,
    bool Function(InternetAddress a, int port) possible) {
  final src = CardAddress(from.rawAddress, port);
  if (!speaks(from) || !own.any((o) => o.equal(src))) return null;
  final joined = [
    for (final n in list)
      if (n.has(from, port) || own.any(n.knows)) n
  ];
  final addresses = <NeighbourAddress>[
    for (final n in joined) ...n.addresses,
    for (final o in own)
      if (speaks(ip(o)) && possible(ip(o), o.port))
        NeighbourAddress(ip(o), o.port, kUnconfirmed),
  ];
  final names = <CardAddress>[];
  for (final c in [
    for (final n in joined) ...n.names,
    for (final o in own)
      if (!speaks(ip(o)) && o.port != 0) o,
  ]) {
    if (!names.any((x) => x.equal(c))) names.add(c);
  }
  final lead = [
    ...joined.where((n) => n.fixed),
    ...joined.where((n) => n.has(from, port)),
    ...joined,
  ];
  return (
    joined: joined,
    whole: Neighbour.of(addresses,
        names: names.length <= kAddressesPerNeighbour
            ? names
            : names.sublist(names.length - kAddressesPerNeighbour),
        fixed: joined.any((n) => n.fixed),
        contactSeat: joined.any((n) => n.fixed)
            ? 0 // the card's seat wins; the contact seat is refilled at the next edge
            : joined.map((n) => n.contactSeat).firstWhere((s) => s > 0, orElse: () => 0),
        id: lead.isEmpty ? null : lead.first.id),
  );
}

/// One neighbour after the wire gained or lost a socket (§11.1): [now] is
/// what stays (`null` = it leaves, no address is left), [lost] the
/// addresses that became names (`null` = none).
typedef Refamily = ({Neighbour old, Neighbour? now, Neighbour? lost});

/// For every neighbour of [list] whose addresses or names do not fit what
/// this node [speaks] any more: an address of a family no longer held
/// becomes a name, a name of a family held again an unconfirmed address.
List<Refamily> refamily(
    List<Neighbour> list, bool Function(InternetAddress a) speaks) {
  final out = <Refamily>[];
  for (final n in list) {
    final lost = [for (final a in n.addresses) if (!speaks(a.address)) a];
    final back = [for (final c in n.names) if (speaks(ip(c))) c];
    if (lost.isEmpty && back.isEmpty) continue;
    final addresses = [
      for (final a in n.addresses)
        if (speaks(a.address)) a,
      for (final c in back) NeighbourAddress(ip(c), c.port, kUnconfirmed),
    ];
    out.add((
      old: n,
      now: addresses.isEmpty
          ? null
          : n.copy(addresses: addresses, names: [
              for (final c in n.names)
                if (!speaks(ip(c))) c,
              for (final a in lost) a.asCardAddress,
            ]),
      lost: lost.isEmpty ? null : n.copy(addresses: lost),
    ));
  }
  return out;
}

/// The address of [c] as an [InternetAddress].
InternetAddress ip(CardAddress c) => InternetAddress.fromRawAddress(c.address);
