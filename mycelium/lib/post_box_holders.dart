/// With whom a sender leaves post, and whom a collector asks (V4.2 §8.2;
/// proposal "contacts as fixed neighbours", version 3, 6.4).
///
/// §8.2: "The holders are chosen so that the recipient will ask them. …
/// A post box at a holder the recipient never asks is not redundancy." So
/// both sides meet on the same nodes:
///
///  * the SENDER leaves post first with the recipient's fixed neighbours as
///    the recipient last told them (they ride sealed in its messages and
///    acknowledgements, §9.2), then with its own neighbours as before —
///    three addressed, two acknowledgements suffice;
///  * the COLLECTOR asks its own fixed neighbours first, then the
///    neighbours it asked before ([holdersJoin]).
///
/// Only at edges (§8.2 "never on a timer"); no packet more per deposit —
/// still three holders. A collection asks up to four fixed neighbours more
/// than before, once per edge.
///
/// Pure functions; `node_post_box.dart` applies them.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/card_address.dart';
import 'package:mycelium/neighbour.dart' as nb;
import 'package:mycelium/post_box_deposit.dart' show Neighbour;

/// The holders addressed on a deposit (§8.2).
const int kDepositHolders = 3;

/// The recipient's [named] fixed neighbours that are [usable], then [own],
/// without duplicates, at most [kDepositHolders]. [node]: the node an
/// address belongs to — one place per NODE (OP-19 part A, S398: two
/// addresses of one node took two of three places); by default the address.
List<Neighbour> depositHolders(List<CardAddress> named, List<Neighbour> own,
    bool Function(Neighbour a) usable, {String Function(Neighbour a)? node}) {
  final first = [
    for (final c in named)
      if ((InternetAddress.fromRawAddress(Uint8List.fromList(c.address)), c.port)
          case final Neighbour a when usable(a))
        a,
  ];
  final key = node ?? (Neighbour a) => '${a.$1.address}:${a.$2}';
  final seen = <String>{};
  return [
    for (final a in [...first, ...own])
      if (seen.length < kDepositHolders && seen.add(key(a))) a,
  ];
}

/// The own neighbours in the order a deposit takes them as holders (OP-19
/// part A, S398; lab E/O2 finding 1): 0 a live link ([live],
/// `Node.linkLive`), 1 answered in this run within the link silence
/// ([answered], `Readiness.answeredRecently`, §22.7.1; S398 lab run 2
/// finding 1: without the window it never aged), 2 confirmed earlier —
/// in an earlier run, or in this one but silent since — 3 never confirmed — a hint is no neighbour
/// yet (§11.8), so it holds only where nothing better is left. Within a
/// rank the list order stays. The collection keeps the list order.
List<nb.Neighbour> ownHoldersRanked(List<nb.Neighbour> all,
    {required bool Function(nb.Neighbour n) live,
    required bool Function(nb.Neighbour n) answered}) {
  int rank(nb.Neighbour n) => live(n)
      ? 0
      : answered(n)
          ? 1
          : n.addresses.any((a) => a.confirmedEver) ? 2 : 3;
  return [for (var r = 0; r < 4; r++) ...all.where((n) => rank(n) == r)];
}

/// [first], then [then], each address:port once.
List<Neighbour> holdersJoin(List<Neighbour> first, List<Neighbour> then) {
  final out = <Neighbour>[];
  for (final a in [...first, ...then]) {
    if (!out.any((x) => x.$1.address == a.$1.address && x.$2 == a.$2)) {
      out.add(a);
    }
  }
  return out;
}
