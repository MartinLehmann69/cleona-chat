/// Address entries — ONE codec for two paths (S391, V2/V4, suggestion W4/W5).
///
/// A reachable node hands out on request the neighbours that it has
/// confirmed under their address (§11.8a), and every node lets
/// the same kind of list travel along in the cover stream (§5.5). Both are the same
/// statement — "these devices answer under this address, last so
/// many minutes ago" — and therefore have ONE format. Two codecs for one
/// statement would be the next place where a field lies differently here than
/// there (cf. `host_memory.dart`, version 5: "ONE codec, not two").
///
/// ── LAYOUT (S394, V2/V3) ──────────────────────────────────────────────
/// ```
/// own count (1 B, at most 2) | own entries      — the SENDER's addresses
/// count (1 B, at most 32)    | neighbour entries
/// per entry: type (1) | address (4/16) | port (u16 LE) | age in minutes (u16 LE)
/// ```
/// The own entries come first: one per address family the sender holds a
/// socket for, each of another family, age 0. They are the only statement
/// in here that is not a hint — the reader joins them into ONE neighbour
/// when the packet came from one of them (§11.8, `neighbourhood_join.dart`).
/// Address including type byte and port are written and read by [addressWrite] /
/// [addressRead] — the same codec as in the card (§15.2). The age is
/// capped at 65535 minutes (~45 days); anything older does not stand in
/// a list of confirmed neighbours anyway (§11.8: stale after one day).
///
/// Largest case: 1 + 2 × 21 + 1 + 32 × 21 = 716 B — fits into the 1170 B
/// payload of a packet on the data port, with room for the content byte in
/// front.
///
/// An entry is a HINT (§6.1, §11.9): whoever reads it tries the
/// address and discards it if it does not answer. Nothing here is
/// believed.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mycelium/card_address.dart'
    show CardAddress, CardFormatError, addressRead, addressWrite;
import 'package:mycelium/neighbourhood.dart' show Neighbour;

/// Maximum number of entries per list — the same number as the neighbourhood
/// (§11.8), a node cannot have confirmed more.
const int kAddressEntriesAtMost = 32;

/// At most this many own entries — one per address family (IPv4, IPv6).
const int kOwnEntriesAtMost = 2;

/// Maximum value of the age field (u16).
const int kAgeAtMostMinutes = 0xFFFF;

class AddressEntry {
  final CardAddress address;

  /// Minutes since the last confirmation, capped at
  /// [kAgeAtMostMinutes].
  final int ageMinutes;

  AddressEntry(this.address, int ageMinutes)
      : ageMinutes = math.max(0, math.min(ageMinutes, kAgeAtMostMinutes));

  /// From a confirmed neighbour: ONE entry per node — its address in the
  /// address family of [family] confirmed within a day, if it has one (the
  /// reader demonstrably speaks that family), otherwise its most recently
  /// confirmed one.
  factory AddressEntry.fromNeighbour(Neighbour n, DateTime now,
      [InternetAddress? family]) {
    final a = (family == null
            ? null
            : n.confirmedIn(family.type, now.subtract(const Duration(days: 1)))) ??
        n.first;
    return AddressEntry(a.asCardAddress, now.difference(a.last).inMinutes);
  }
}

/// What one packet carries: the sender's own addresses and its neighbours.
class AddressList {
  final List<AddressEntry> own;
  final List<AddressEntry> neighbours;
  const AddressList({this.own = const [], this.neighbours = const []});

  bool get isEmpty => own.isEmpty && neighbours.isEmpty;
}

/// Writes [l]: own entries first (V2), then the neighbour entries. More
/// than [kOwnEntriesAtMost] own entries, two of one address family or an
/// own entry with an age are programming errors of the caller.
void addressListWrite(BytesBuilder b, AddressList l) {
  _ownCheck(l.own, (m) => ArgumentError(m));
  b.addByte(l.own.length);
  for (final e in l.own) {
    addressWrite(b, e.address);
    b
      ..addByte(0)
      ..addByte(0);
  }
  addressEntriesWrite(b, l.neighbours);
}

/// Reads what [addressListWrite] wrote; throws [CardFormatError].
AddressList addressListRead(Uint8List Function(int length) read) {
  final count = read(1)[0];
  if (count > kOwnEntriesAtMost) {
    throw CardFormatError('$count own entries, at most $kOwnEntriesAtMost');
  }
  final own = <AddressEntry>[];
  for (var i = 0; i < count; i++) {
    final a = addressRead(read, 'own entry ${i + 1}');
    final age = read(2);
    own.add(AddressEntry(a, age[0] | (age[1] << 8)));
  }
  _ownCheck(own, (m) => CardFormatError(m));
  return AddressList(own: own, neighbours: addressEntriesRead(read));
}

/// The size of [l] in bytes.
int addressListLength(AddressList l) =>
    addressEntriesLength(l.own) + addressEntriesLength(l.neighbours);

void _ownCheck(List<AddressEntry> own, Object Function(String) error) {
  if (own.length > kOwnEntriesAtMost) {
    throw error('${own.length} own entries, at most $kOwnEntriesAtMost');
  }
  if (own.length == 2 && own[0].address.kind == own[1].address.kind) {
    throw error('two own entries of one address family');
  }
  if (own.any((e) => e.ageMinutes != 0)) {
    throw error('an own entry carries age 0');
  }
}

/// Writes [entries]; more than [kAddressEntriesAtMost] is a
/// programming error of the caller, not silent truncation.
void addressEntriesWrite(BytesBuilder b, List<AddressEntry> entries) {
  if (entries.length > kAddressEntriesAtMost) {
    throw ArgumentError('${entries.length} address entries, at most '
        '$kAddressEntriesAtMost are provided');
  }
  b.addByte(entries.length);
  for (final e in entries) {
    addressWrite(b, e.address);
    b
      ..addByte(e.ageMinutes & 0xFF)
      ..addByte((e.ageMinutes >> 8) & 0xFF);
  }
}

/// Reads a list; throws [CardFormatError] on too high a count, an
/// unknown type byte or too few bytes (that is reported by [read] itself).
List<AddressEntry> addressEntriesRead(Uint8List Function(int length) read) {
  final count = read(1)[0];
  if (count > kAddressEntriesAtMost) {
    throw CardFormatError('$count address entries, at most '
        '$kAddressEntriesAtMost are provided');
  }
  final result = <AddressEntry>[];
  for (var i = 0; i < count; i++) {
    final a = addressRead(read, 'address entry ${i + 1}');
    final age = read(2);
    result.add(AddressEntry(a, age[0] | (age[1] << 8)));
  }
  return result;
}

/// The size of a list in bytes — for the caller's space check.
int addressEntriesLength(List<AddressEntry> entries) =>
    1 + entries.fold<int>(0, (s, e) => s + 1 + e.address.address.length + 2 + 2);
