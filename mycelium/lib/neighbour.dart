/// A neighbour is a NODE, kept as the set of its addresses (V4.2 §11.8,
/// proposal S394 V4).
///
/// ── WHY A NODE AND NOT AN ADDRESS ──────────────────────────────────────
///
/// Until S394 a neighbour WAS its address (call D, S385): `address:port`
/// was the key, and two addresses of the same node were two entries that
/// knew nothing of each other. Measured 24.09.2026 in the lab: the phone
/// named its neighbour by IPv6, the forwarder of the other side knew the
/// same node only by IPv4 and could do nothing with the IPv6 address
/// (`wire: not sent … no IPv6 socket`); and a failed IPv6 use removed the
/// whole entry although the node answered under IPv4 all the time.
///
/// Two addresses belong to the same neighbour when it names them as its
/// OWN in a sealed packet that comes from one of them (§5.5, §11.8a — the
/// own entries of `address_entries.dart`). No node identifier: that one is
/// drawn anew per start (`node_call.dart`) and would join nothing across a
/// restart.
///
/// ── WHAT IS KEPT PER ADDRESS ──────────────────────────────────────────
///
/// Each address carries its own stamp ([NeighbourAddress.last]) — it is
/// confirmed on its own, and a failed use removes only it. The neighbour
/// leaves with its last address.
///
/// Only addresses of an address family this node holds a socket for are
/// [addresses] (§11.1, V1). What the neighbour names in another family is
/// kept in [names]: never tried, never sent to, never written to a card or
/// to memory — it only lets the forwarder recognise the node when a `0x22`
/// names it that way (§8.1, V5).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/card_address.dart';
import 'package:mycelium/outside_address.dart' show fromOutsideReachable;

/// At most this many addresses per neighbour — as many as a card names of
/// its issuer (§15.2). A node names one per address family of its own
/// (§5.5); more arise only from address changes, and then the oldest
/// stamp gives way.
const int kAddressesPerNeighbour = 4;

/// The stamp of an address that has never been confirmed. In local time
/// like every stamp read from memory — otherwise it would no longer be
/// `==` to itself after the restart.
final DateTime kUnconfirmed = DateTime.fromMillisecondsSinceEpoch(0);

/// One address of a neighbour with its own confirmation stamp.
class NeighbourAddress {
  final InternetAddress address;
  final int port;

  /// The confirmation stamp (`Neighbourhood.confirm`), or [kUnconfirmed].
  final DateTime last;

  NeighbourAddress(this.address, this.port, this.last) {
    if (port < 1 || port > 0xFFFF) {
      throw ArgumentError('Port must be between 1 and 65535, was $port — '
          'port 0 means "not bound" and is not an address');
    }
    if (CardAddressType.fromLength(address.rawAddress.length) == null) {
      throw ArgumentError('an address has 4 (IPv4) or 16 (IPv6) bytes, '
          'was ${address.rawAddress.length} B');
    }
  }

  /// `address:port`.
  String get key => '${address.address}:$port';

  bool get confirmedEver => !last.isAtSameMomentAs(kUnconfirmed);

  /// With type byte, thus also IPv6 (S390: ONE codec).
  CardAddress get asCardAddress =>
      CardAddress(Uint8List.fromList(address.rawAddress), port);

  bool isAt(InternetAddress a, int p) => p == port && a.address == address.address;
}

/// A neighbour: one node, the addresses under which this node reaches it,
/// and the seat it holds in the open set: the card's seat (W7) or one of
/// up to three contact seats (§5.2, contacts as fixed neighbours).
class Neighbour {
  static int _next = 0;

  /// Local, per run, never on the wire or on disk. It survives a merge and
  /// a new stamp — the open set and the rank keep the node by it, not by
  /// an address that can change.
  final int id;

  /// Newest stamp first; never empty.
  final List<NeighbourAddress> addresses;

  /// Addresses the neighbour named as its own in an address family this
  /// node has no socket for — only for recognition (§8.1, V5).
  final List<CardAddress> names;

  /// The card's seat — the neighbour the own cards name (W7).
  final bool fixed;

  /// 0: no contact seat; 1–3: which of the contact seats this device of an
  /// own contact holds (`neighbourhood_contacts.dart`). Never together with
  /// [fixed].
  final int contactSeat;

  /// Holds any fixed seat — the card's or a contact's.
  bool get seated => fixed || contactSeat > 0;

  /// One address — the form of a hint, of a confirmation and of the
  /// probes.
  Neighbour(InternetAddress address, int port, DateTime last,
      {bool fixed = false, int contactSeat = 0})
      : this.of([NeighbourAddress(address, port, last)],
            fixed: fixed, contactSeat: contactSeat);

  Neighbour.of(List<NeighbourAddress> addresses,
      {this.fixed = false,
      this.contactSeat = 0,
      List<CardAddress> names = const [],
      int? id})
      : id = id ?? _next++,
        addresses = List.unmodifiable(_ordered(addresses)),
        names = List.unmodifiable(names) {
    if (this.addresses.isEmpty) {
      throw ArgumentError('a neighbour has at least one address');
    }
    if (contactSeat < 0 || contactSeat > 3 || (fixed && contactSeat > 0)) {
      throw ArgumentError('contact seat $contactSeat (fixed: $fixed)');
    }
  }

  /// Newest stamp first; equal stamps keep their order (insertion, not
  /// `List.sort`, whose order for equal elements is not promised). Above
  /// [kAddressesPerNeighbour] the oldest stamps give way.
  static List<NeighbourAddress> _ordered(List<NeighbourAddress> l) {
    final out = <NeighbourAddress>[];
    for (final a in l) {
      if (out.any((x) => x.key == a.key)) continue;
      var i = out.length;
      while (i > 0 && a.last.isAfter(out[i - 1].last)) {
        i--;
      }
      out.insert(i, a);
    }
    return out.take(kAddressesPerNeighbour).toList();
  }

  /// The address a use goes to: the most recently confirmed one.
  NeighbourAddress get first => addresses.first;
  InternetAddress get address => first.address;
  int get port => first.port;

  /// The newest stamp of all addresses — what cap, rank and staleness
  /// decide by.
  DateTime get last => first.last;

  /// The key of [first] — for reports and probes. The neighbour itself is
  /// kept by [id].
  String get key => first.key;

  /// [first] as a card address — where a packet to this neighbour goes.
  CardAddress get sendAddress => first.asCardAddress;

  /// The address that names this neighbour in a card (§15.2) and in a way
  /// back (§15.5): only a CONFIRMED one. The reader is usually outside the
  /// own segment, and it hands the address to ITS neighbour, which has an
  /// IPv4 socket in any case (§11.1). Hence: reachable from the open
  /// network first, IPv4 before IPv6; otherwise the most recently confirmed.
  /// [verified] narrows "confirmed" (e.g. "answered in this run"); without
  /// it any stamp counts. `null` if no address qualifies.
  CardAddress? cardAddress([bool Function(NeighbourAddress a)? verified]) {
    final pool = [
      for (final a in addresses)
        if (verified == null ? a.confirmedEver : verified(a)) a
    ];
    if (pool.isEmpty) return null;
    for (final t in const [InternetAddressType.IPv4, InternetAddressType.IPv6]) {
      for (final a in pool) {
        if (a.address.type == t && fromOutsideReachable(a.address)) {
          return a.asCardAddress;
        }
      }
    }
    return pool.first.asCardAddress;
  }

  /// [cardAddress] without narrowing; a never confirmed neighbour gives its
  /// [first] address, so that callers that only need SOME address keep one.
  CardAddress get asCardAddress => cardAddress() ?? sendAddress;

  /// Whether [a]:[port] is one of [addresses].
  bool has(InternetAddress a, int port) => addresses.any((x) => x.isAt(a, port));

  /// Whether [c] is one of [addresses] or [names] — the recognition of §8.1.
  bool knows(CardAddress c) =>
      addresses.any((x) => x.asCardAddress.equal(c)) ||
      names.any((x) => x.equal(c));

  /// Whether the neighbour has an address, or a name, of type [t].
  bool inFamily(InternetAddressType t) =>
      addresses.any((x) => x.address.type == t) ||
      names.any((x) => (x.kind == CardAddressType.ipv6) ==
          (t == InternetAddressType.IPv6));

  /// The most recently confirmed address of type [t], or `null`.
  NeighbourAddress? confirmedIn(InternetAddressType t, DateTime notBefore) {
    for (final a in addresses) {
      if (a.address.type == t && !a.last.isBefore(notBefore)) return a;
    }
    return null;
  }

  /// A copy with other parts; [id] stays.
  /// Taking the card's seat gives up a contact seat (never both).
  Neighbour copy(
      {List<NeighbourAddress>? addresses,
      List<CardAddress>? names,
      bool? fixed,
      int? contactSeat}) {
    final f = fixed ?? this.fixed;
    return Neighbour.of(addresses ?? this.addresses,
        fixed: f,
        contactSeat: f ? 0 : contactSeat ?? this.contactSeat,
        names: names ?? this.names,
        id: id);
  }
}
