/// The remembered contact and its section in the file layout of the memory.
///
/// ── WHY THIS FILE EXISTS ─────────────────────────────────────────
///
/// Proposal M (S391) gives the contact three more fields — `s_AB`, the
/// day keys of the contact and the point in time of the last own
/// shipment of them —, and `memory.dart` stood at 392 lines. The
/// cut is the same as with `memory_invitation.dart`: over there
/// stands WHAT is remembered and how it is handled, here ONE section
/// of the file layout including the type it carries. `memory.dart` re-exports
/// this file.
///
/// ── FILE LAYOUT PER CONTACT (version 16) ───────────────────────────────
/// ```
/// name: u16 length + UTF-8 | address (Address.length) | since (u64 ms)
/// | lastSeen (flag + address)                — version 12
/// | card addresses (count byte + addresses)  — version 13
/// | neighbours (count byte 0..3 + addresses) — version 16 (was one, v11)
/// | s_AB: flag (1 B) + 32 B                  — version 14
/// | day keys: count (1 B), per day (u32) + key 32 B
/// | own day keys last sent (u64 ms, 0 = never)
/// | never a fixed neighbour (1 B, 0x00/0x01) — version 16
/// ```
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mycelium/memory_invitation.dart' show MemoryError, Reader;
import 'package:mycelium/card_address.dart';
import 'package:mycelium/pair.dart' show kPairRandomLength;
import 'package:mycelium/envelope.dart';

/// At most this many day keys of a contact lie at the contact:
/// the 31 of the last shipment and one each as tolerance for the clock of both
/// sides at both ends (proposal M §5.4: "the next 31 days").
const int kDayKeyAtMost = 31 + 2;

/// At most this many fixed neighbours of a contact are kept — as many as
/// a device holds contact seats (§5.2, proposal "contacts as fixed
/// neighbours", D1).
const int kContactNeighboursAtMost = 3;

/// A remembered contact: [Address], display name, point in time of
/// coming about, the most recently OBSERVED address including port, the
/// addresses of its card, its fixed neighbours and — since proposal M —
/// the pair data.
///
/// ── TWO ORIGINS, AND THE DIFFERENCE IS NORMATIVE (§6.2) ──────────
///
/// §6.2 lists what a node knows about another, and separates
/// the sources in doing so: "the card", "received packets" and "own attempts".
/// §6.3 lists them as separate fields — `lastSeenAddress` next to
/// `cardAddresses`.
///
///  * [lastSeen] is **evidence**: a packet came from there.
///  * [cardsAddresses] and [neighbours] are the **claim** of the
///    peer. A card address never overrides an observed route.
///
/// Until S390 a contact had only the field pair of the observed address
/// (finding B-1, `berichte/S390-EVAL-NACHRICHT.md`); since version 12 the
/// evidence is typed like the claim, since version 13 the card carries
/// no roles any more (classification on every access, `address_class.dart`).
class Contact {
  final Address address;
  final String displayName;
  final DateTime since;

  /// The last OBSERVED address (§6.2 „received packets").
  final CardAddress? lastSeen;

  /// The addresses that the peer has named for itself in its card
  /// — in ITS order of preference, at most four (§15.2),
  /// without classification.
  final List<CardAddress> cardsAddresses;

  /// The peer's fixed neighbours — step 3 (§8.1), at most
  /// [kContactNeighboursAtMost], in the peer's order. They belong to third
  /// parties. Origin: the card (joiner), the request (inviter, proposal M
  /// §5.7), a `0x23` or a notice of the contact about a change ("only
  /// contacts get the new address", §8.1). ONE list for all of them — the
  /// most recent statement replaces the whole list.
  final List<CardAddress> neighbours;

  /// The user excluded this contact from the fixed seats (§5.2; proposal
  /// "contacts as fixed neighbours", D2 = a): its devices never take one.
  /// Local, travels nowhere.
  final bool neverFixedNeighbour;

  /// `s_AB` (proposal M §5.2) — 32 B, or `null` without a pair.
  final Uint8List? pairRandom;

  /// The public day keys of the contact (§8.2 of the proposal),
  /// UTC day → 32 B.
  final Map<int, Uint8List> dayKey;

  /// When THIS identity last sent the contact its own
  /// day keys — `null`: never.
  final DateTime? dayKeySent;

  Contact({
    required this.address,
    required this.displayName,
    required this.since,
    this.lastSeen,
    List<CardAddress> cardsAddresses = const [],
    List<CardAddress> neighbours = const [],
    this.neverFixedNeighbour = false,
    this.pairRandom,
    Map<int, Uint8List> dayKey = const {},
    this.dayKeySent,
  })  : cardsAddresses = List.unmodifiable(cardsAddresses),
        neighbours = List.unmodifiable(neighbours),
        dayKey = Map.unmodifiable(dayKey) {
    if (neighbours.length > kContactNeighboursAtMost) {
      throw ArgumentError('at most $kContactNeighboursAtMost neighbours, '
          'were ${neighbours.length}');
    }
    final s = pairRandom;
    if (s != null && s.length != kPairRandomLength) {
      throw ArgumentError('s_AB must have $kPairRandomLength B');
    }
    if (dayKey.length > kDayKeyAtMost ||
        dayKey.values.any((pk) => pk.length != 32)) {
      throw ArgumentError('Day keys: at most '
          '$kDayKeyAtMost, 32 B each');
    }
  }

  /// The same contact with a different [Address] — everything else stays.
  Contact withAddress(Address a) => Contact(
      address: a,
      displayName: displayName,
      since: since,
      lastSeen: lastSeen,
      cardsAddresses: cardsAddresses,
      neighbours: neighbours,
      neverFixedNeighbour: neverFixedNeighbour,
      pairRandom: pairRandom,
      dayKey: dayKey,
      dayKeySent: dayKeySent);
}

/// Writes [k] in the layout from the header of this file.
void contactWrite(BytesBuilder b, Contact k) {
  final name = utf8.encode(k.displayName);
  b.add(_u16(name.length));
  b.add(name);
  b.add(k.address.toBytes());
  b.add(_u64(k.since.millisecondsSinceEpoch));
  optionalAddressWrite(b, k.lastSeen);
  addressesWrite(b, k.cardsAddresses);
  addressesWrite(b, k.neighbours);
  final s = k.pairRandom;
  b.addByte(s == null ? 0 : 1);
  if (s != null) b.add(s);
  final days = k.dayKey.keys.toList()..sort();
  b.addByte(days.length);
  for (final t in days) {
    b.add(_u32(t));
    b.add(k.dayKey[t]!);
  }
  b.add(_u64(k.dayKeySent?.millisecondsSinceEpoch ?? 0));
  b.addByte(k.neverFixedNeighbour ? 1 : 0);
}

/// Reads a contact. Throws [MemoryError] (via [Reader]) or
/// a format exception that the caller reports as damaged.
Contact contactRead(Reader l) {
  final name = utf8.decode(l.bytes(l.u16()));
  final address = Address.outBytes(l.bytes(Address.length));
  final since = DateTime.fromMillisecondsSinceEpoch(l.u64());
  final seen = optionalAddressRead(l.bytes, 'zuletztGesehen');
  final card = addressesRead(l.bytes);
  final many = l.byte();
  if (many > kContactNeighboursAtMost) {
    throw MemoryError('$many neighbours, at most $kContactNeighboursAtMost');
  }
  final neighbours = [
    for (var i = 1; i <= many; i++) addressRead(l.bytes, 'neighbour $i')
  ];
  final Uint8List? s = switch (l.byte()) {
    0 => null,
    1 => l.bytes(kPairRandomLength),
    final f => throw MemoryError('invalid s_AB flag $f'),
  };
  final count = l.byte();
  if (count > kDayKeyAtMost) {
    throw MemoryError('$count day keys, at most '
        '$kDayKeyAtMost');
  }
  final days = <int, Uint8List>{};
  for (var i = 0; i < count; i++) {
    days[l.u32()] = l.bytes(32);
  }
  final sent = l.u64();
  final never = switch (l.byte()) {
    0 => false,
    1 => true,
    final f => throw MemoryError('invalid never-fixed flag $f'),
  };
  return Contact(
    address: address,
    displayName: name,
    since: since,
    lastSeen: seen,
    cardsAddresses: card,
    neighbours: neighbours,
    neverFixedNeighbour: never,
    pairRandom: s,
    dayKey: days,
    dayKeySent:
        sent == 0 ? null : DateTime.fromMillisecondsSinceEpoch(sent),
  );
}

Uint8List _u16(int v) =>
    (ByteData(2)..setUint16(0, v, Endian.big)).buffer.asUint8List();
Uint8List _u32(int v) =>
    (ByteData(4)..setUint32(0, v, Endian.big)).buffer.asUint8List();
Uint8List _u64(int v) =>
    (ByteData(8)..setUint64(0, v, Endian.big)).buffer.asUint8List();
