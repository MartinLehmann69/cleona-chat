/// The fixed neighbours as a list on the wire (proposal "contacts as fixed
/// neighbours", version 3, 6.2 and 6.9; V4.2 §8.1, §9.2).
///
/// ONE codec for the three places the list travels:
///
///  * **sealed, in every message and every acknowledgement** a node sends
///    to a contact (`message.dart`) — count 0..3; a contact learns its
///    peer's fixed neighbours only this way, so a change costs no packet of
///    its own (rule 5 of the proposal; the former notice `0x17` is gone);
///  * **sealed, in a `0x23`** where are you (`mailbox_pair.dart`) — the
///    same list, under `K_AB`;
///  * **in the clear, in a `0x22`** (`forward.dart`) — the next addresses,
///    count 1..3.
///
/// Layout: count (1 B) + per address type (1) + address (4/16) + port (2),
/// the address codec of the card (`card_address.dart`). At most
/// 1 + 3 × 19 = 58 B.
library;

import 'dart:typed_data';

import 'package:mycelium/card_address.dart';

/// At most this many fixed neighbours travel in a list (D1: up to three
/// contact seats).
const int kNeighbourListAtMost = 3;

/// Writes [list] as count + addresses. [least] is the smallest count the
/// place allows (`0x22`: 1).
void neighbourListWrite(BytesBuilder b, List<CardAddress> list,
    {int least = 0}) {
  if (list.length < least || list.length > kNeighbourListAtMost) {
    throw ArgumentError('${list.length} neighbour(s), allowed '
        '$least..$kNeighbourListAtMost');
  }
  b.addByte(list.length);
  for (final a in list) {
    addressWrite(b, a);
  }
}

/// Counterpart to [neighbourListWrite]; throws [CardFormatError] on a count
/// outside [least]..[kNeighbourListAtMost] or a broken address.
List<CardAddress> neighbourListRead(
    Uint8List Function(int length) read, String fieldName,
    {int least = 0}) {
  final n = read(1)[0];
  if (n < least || n > kNeighbourListAtMost) {
    throw CardFormatError('$fieldName: $n address(es), allowed '
        '$least..$kNeighbourListAtMost');
  }
  return [for (var i = 0; i < n; i++) addressRead(read, fieldName)];
}

/// [list] without duplicates, in its order, at most [kNeighbourListAtMost].
List<CardAddress> neighbourListClean(Iterable<CardAddress> list) {
  final out = <CardAddress>[];
  for (final a in list) {
    if (out.length == kNeighbourListAtMost) break;
    if (!out.any((x) => x.equal(a))) out.add(a);
  }
  return out;
}

/// Whether [a] and [b] name the same addresses in the same order.
bool neighbourListEqual(List<CardAddress> a, List<CardAddress> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!a[i].equal(b[i])) return false;
  }
  return true;
}
