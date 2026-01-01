/// Who holds the contact seats of the open set (V4.2 §5.2, proposal
/// "contacts as fixed neighbours", version 3, owner decision 24.09.2026:
/// D1 = up to three currently reachable contacts with replacement, D2 = a).
///
/// ── THE RULE ────────────────────────────────────────────────────────────
///
/// Up to [kContactSeats] seats go to devices of the node's OWN contacts
/// ([contact], set by the host: `host_contact_seats.dart`) that are
///
///  * reachable from the open network under the rule of the card's seat —
///    confirmed under a public address ([reachableNeighbour]), and
///  * have answered since the last start or network change ([answered],
///    `Readiness`, §22.7.1) — the one just confirmed counts ([justNow]),
///  * and are not excluded by the user ([never], §15.10 of the proposal),
///  * and could reach the node over IPv6 where the link is metered
///    ([v4Only], §8.1: on a metered link only one IPv4 path is kept open,
///    `keep_alive_fixed.dart`).
///
/// One such contact holds one seat, more hold up to three. The card's seat
/// (`neighbourhood_seat.dart`) is a separate place and never a contact
/// seat at the same time.
///
/// ── WHEN IT CHANGES — EDGES ONLY ────────────────────────────────────────
///
/// A seat is filled at a confirmation (a new answer) and after a removal
/// (§11.8: a failed use, never silence) — both are edges. A holder keeps
/// its seat while it is quiet, like the card's seat; it loses it only when
/// it is removed, takes the card's seat, stops being a contact, is
/// excluded by the user, or the link becomes metered while it could reach
/// the node only over IPv4. Nothing here sends a packet or runs on a clock.
///
/// Pure functions over the list; `neighbourhood.dart` applies them. A
/// separate file because the neighbourhood is at its line budget.
library;

import 'package:mycelium/neighbour.dart';
import 'package:mycelium/neighbourhood_seat.dart' show reachableNeighbour;

/// At most this many fixed seats go to devices of contacts (D1).
const int kContactSeats = 3;

/// The contact seats after an edge: neighbour id -> seat number (1..3).
/// Holders that still qualify keep their number; free numbers go to
/// qualifying neighbours in the order of [list] (the freshest stamp first).
Map<int, int> contactSeatsAfter(
  List<Neighbour> list, {
  int? justNow,
  required bool Function(Neighbour n) answered,
  required bool Function(Neighbour n) contact,
  required bool Function(Neighbour n) never,
  required bool Function(NeighbourAddress a) public,
  bool Function(Neighbour n)? v4Only,
}) {
  bool keeps(Neighbour n) =>
      !n.fixed && contact(n) && !never(n) && !(v4Only?.call(n) ?? false);
  final seats = <int, int>{
    for (final n in list)
      if (n.contactSeat > 0 && keeps(n)) n.id: n.contactSeat,
  };
  final free = [
    for (var s = 1; s <= kContactSeats; s++)
      if (!seats.containsValue(s)) s,
  ];
  for (final n in list) {
    if (free.isEmpty) break;
    if (seats.containsKey(n.id) || !keeps(n)) continue;
    if (!reachableNeighbour(n, public)) continue;
    if (n.id != justNow && !answered(n)) continue;
    seats[n.id] = free.removeAt(0);
  }
  return seats;
}

/// Applies [contactSeatsAfter] to [list] in place.
void seatContacts(
    List<Neighbour> list,
    int? justNow,
    bool Function(Neighbour n) answered,
    bool Function(Neighbour n) contact,
    bool Function(Neighbour n) never,
    bool Function(NeighbourAddress a) public,
    [bool Function(Neighbour n)? v4Only]) {
  final seats = contactSeatsAfter(list,
      justNow: justNow,
      answered: answered,
      contact: contact,
      never: never,
      public: public,
      v4Only: v4Only);
  for (var j = 0; j < list.length; j++) {
    final s = seats[list[j].id] ?? 0;
    if (list[j].contactSeat != s) list[j] = list[j].copy(contactSeat: s);
  }
}

/// The fixed neighbours of [list] — the contact seats by number, then the
/// card's seat (§8.1: each of them gets the codes).
List<Neighbour> fixedOrder(List<Neighbour> list) => [
      ...(list.where((n) => n.contactSeat > 0).toList()
        ..sort((a, b) => a.contactSeat.compareTo(b.contactSeat))),
      ...list.where((n) => n.fixed).take(1),
    ];

/// Sort key of a seat in the list: the card's seat first (§15.2: the card
/// names the FIRST), then the contact seats by number, then everybody else.
int seatOrder(Neighbour n) =>
    n.fixed ? 0 : (n.contactSeat > 0 ? n.contactSeat : kContactSeats + 1);
