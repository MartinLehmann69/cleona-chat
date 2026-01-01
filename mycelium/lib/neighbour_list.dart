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
/// 1 + 3 × 19 = 58 B. With [withKeys] (S407 a') the count byte carries
/// [kKeysFollow] and every address is followed by a flag and, with flag 1,
/// its node's record key (32 B, §11.9): at most 1 + 3 × 52 B. A 4.2.3 reader
/// rejects that count byte (`398a6e40` `neighbour_list.dart`: count 0..3),
/// so the keyed form goes only where it is read: the memory, and a contact
/// that showed it reads it (owner 09.10.2026, mixed operation "B";
/// `neighbour_keys.dart`) — the bit then stands even without a key, which is
/// how the contact learns the same of this side. Never the clear `0x22`,
/// never a group entry (every member reads it). This reader takes both.
library;

import 'dart:typed_data';

import 'package:mycelium/card_address.dart';
import 'package:mycelium/kinds.dart' as kinds;

/// At most this many fixed neighbours travel in a list (D1: up to three
/// contact seats).
const int kNeighbourListAtMost = 3;

/// Bit in the count byte: record keys follow the addresses (S407 a').
const int kKeysFollow = kinds.kBitNeighbourKeysFollow;

/// Writes [list] as count + addresses. [least] is the smallest count the
/// place allows (`0x22`: 1).
void neighbourListWrite(BytesBuilder b, List<CardAddress> list,
    {int least = 0, bool withKeys = false}) {
  if (list.length < least || list.length > kNeighbourListAtMost) {
    throw ArgumentError('${list.length} neighbour(s), allowed '
        '$least..$kNeighbourListAtMost');
  }
  final keys = withKeys;
  b.addByte(list.length | (keys ? kKeysFollow : 0));
  for (final a in list) {
    addressWrite(b, a);
    if (!keys) continue;
    final k = a.recordKey;
    b.addByte(k == null ? 0 : 1);
    if (k != null) b.add(k);
  }
}

/// Counterpart to [neighbourListWrite]; throws [CardFormatError] on a count
/// outside [least]..[kNeighbourListAtMost] or a broken address.
List<CardAddress> neighbourListRead(
    Uint8List Function(int length) read, String fieldName,
    {int least = 0, bool withKeys = false}) {
  final byte = read(1)[0];
  final keys = withKeys && byte & kKeysFollow != 0;
  final n = withKeys ? byte & ~kKeysFollow : byte;
  if (n < least || n > kNeighbourListAtMost) {
    throw CardFormatError('$fieldName: $n address(es), allowed '
        '$least..$kNeighbourListAtMost');
  }
  return [
    for (var i = 0; i < n; i++)
      () {
        final a = addressRead(read, fieldName);
        if (!keys) return a;
        final flag = read(1)[0];
        if (flag > 1) throw CardFormatError('$fieldName: key flag $flag');
        return flag == 1 ? a.withRecordKey(read(32)) : a;
      }(),
  ];
}

/// Whether the list starting with [countByte] carries the bit: its writer
/// reads keyed lists (S407).
bool neighbourListShowsKeys(int countByte) => countByte & kKeysFollow != 0;

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
