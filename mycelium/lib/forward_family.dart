/// Where the inner packet of a `0x22` goes — the address family rule of
/// the forwarder (V4.2 §8.1 rule 1, §11.1; S394 V5).
///
/// Measured 24.09.2026 in the lab: the phone named its fixed neighbour by
/// IPv6 in the way back of a bundle request; the forwarder on the other
/// side has no IPv6 socket and knew the same node only by IPv4 —
/// `wire: not sent … no IPv6 socket (errno 97)`, the bundle was lost. The
/// rule: "hand the inner packet to the next address. If this node has no
/// socket for that address's family, it uses another address of the same
/// neighbour (§11.8); if it knows none, it hands the `0x22` on, hop count
/// minus one, to one open neighbour (§5.2) that has an address in that
/// family — at most once, the hop count bounds it."
///
/// Separate from `forward.dart`, which knows no network and no neighbours,
/// and from `node_codes.dart`, which is at its line budget.
library;

import 'dart:io';

import 'package:mycelium/card_address.dart';
import 'package:mycelium/forward.dart' show NextStep;
import 'package:mycelium/node.dart';
import 'package:mycelium/node_helpers.dart' show interfaces;

/// The next step for a `0x22` to [next] that came from [from]:[fromPort].
/// `null`: no address of the target's family and no open neighbour that
/// has one — the packet goes nowhere, and the caller says so.
NextStep? familyStep(
    Node k, CardAddress next, InternetAddress from, int fromPort) {
  final a = InternetAddress.fromRawAddress(next.address);
  if (k.speaks(a)) return (target: (address: a, port: next.port), detour: false);
  // Another address of the same neighbour — it named `next` as its own
  // (a name, `neighbour.dart`); its addresses are of an own address family.
  final same = k.neighbourhood.recognise(next);
  if (same != null) {
    return (target: (address: same.address, port: same.port), detour: false);
  }
  // One open neighbour that has an address in that family — never the one
  // the `0x22` came from.
  for (final o in k.neighbourhood.openSet()) {
    if (o.has(from, fromPort) || !o.inFamily(a.type)) continue;
    return (target: (address: o.address, port: o.port), detour: true);
  }
  return null;
}

/// Is [a]:[port] this node itself? Loopback or an own interface, own port.
bool isSelf(Node k, InternetAddress a, int port) =>
    port == k.port &&
    (a.isLoopback ||
        interfaces.any((s) => s.addresses.any((x) => x.address == a.address)));
