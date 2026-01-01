/// The own addresses of this node — which ones a packet names, and only of
/// the address families this node holds a socket for (§11.1, S394 V1/V2).
///
/// Two readers, two questions:
///
/// * [ownEntriesFor] — the own entries of an address list (§5.5 cover,
///   §11.8a board answer): ONE address per address family, and in the
///   family of the recipient the one under which the recipient SEES this
///   node. Only that one lets the recipient join the entries into one
///   neighbour (`neighbourhood_join.dart`: "from one of them").
/// * [cardOwnAddresses] — the own addresses of a card (§15.2): up to four,
///   in the issuer's order of preference, the confirmed public one first.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/card_address.dart';
import 'package:mycelium/node.dart';
import 'package:mycelium/node_helpers.dart' show interfaces, outTheSegment;
import 'package:mycelium/outside_address.dart' show fromOutsideReachable;
import 'package:mycelium/own_address.dart' show ownAddressesOrdered;

/// The own entries for a packet to [target]: per address family this node
/// speaks at most one address. In the family of [target]: the loopback for
/// a loopback target, an own address in the segment for a target in the
/// segment, otherwise the public one ([Node.publicAddress], confirmed from
/// outside) or one reachable from outside. In the other family only one
/// reachable from outside — a private address of another family would be
/// a guess the reader cannot check.
List<CardAddress> ownEntriesFor(Node k, InternetAddress target) => [
      for (final t in const [InternetAddressType.IPv4, InternetAddressType.IPv6])
        if (_family(k, t, target) case final a?) a
    ];

CardAddress? _family(Node k, InternetAddressType t, InternetAddress target) {
  final probe = t == InternetAddressType.IPv4
      ? InternetAddress.loopbackIPv4
      : InternetAddress.loopbackIPv6;
  if (!k.speaks(probe)) return null;
  CardAddress at(InternetAddress a) =>
      CardAddress(Uint8List.fromList(a.rawAddress), k.port);
  final same = target.type == t;
  if (same && target.isLoopback) return at(probe);
  final mine = [
    for (final s in interfaces)
      for (final a in s.addresses)
        if (a.type == t && !a.isLoopback) a
  ];
  if (same && outTheSegment(target)) {
    for (final a in mine) {
      if (outTheSegment(a)) return at(a);
    }
  }
  final p = k.publicAddress;
  if (p != null && p.kind.addressLength == probe.rawAddress.length) return p;
  for (final a in mine) {
    if (fromOutsideReachable(a)) return at(a);
  }
  return null;
}

/// The own addresses for a card (§15.2): the order of preference of
/// [ownAddressesOrdered], IN FRONT the one confirmed by the outside route
/// — the only one that knows a mapping through a NAT (the same reasoning
/// as `outsideAddresses`, §11.9) —, duplicates once, and only of an address
/// family this node holds a socket for (V1).
List<CardAddress> cardOwnAddresses(Node k) {
  final confirmed = k.publicAddress;
  return [
    if (confirmed != null) confirmed,
    ...ownAddressesOrdered(interfaces, k.port)
        .where((a) => confirmed == null || !a.equal(confirmed)),
  ]
      .where((a) => k.speaks(InternetAddress.fromRawAddress(a.address)))
      .take(kOwnAddressesAtMost)
      .toList();
}
