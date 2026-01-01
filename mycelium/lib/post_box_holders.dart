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
import 'package:mycelium/post_box_deposit.dart' show Neighbour;

/// The holders addressed on a deposit (§8.2).
const int kDepositHolders = 3;

/// The recipient's [named] fixed neighbours that are [usable], then [own],
/// without duplicates, at most [kDepositHolders].
List<Neighbour> depositHolders(List<CardAddress> named, List<Neighbour> own,
    bool Function(Neighbour a) usable) {
  final first = [
    for (final c in named)
      if ((InternetAddress.fromRawAddress(Uint8List.fromList(c.address)), c.port)
          case final Neighbour a when usable(a))
        a,
  ];
  return holdersJoin(first, own).take(kDepositHolders).toList();
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
