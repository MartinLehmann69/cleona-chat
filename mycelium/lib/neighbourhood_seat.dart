/// Who holds the fixed seat of the open set (V4.2 §5.2, W7; S394 V6).
///
/// The fixed seat is the neighbour the own cards name (§15.2) — only via it
/// is a node behind NAT reachable for the reader of its card. Measured
/// 24.09.2026: Charly's fixed neighbour was Node1 under a PRIVATE IPv4,
/// although Node2 had the bootstrap under a public IPv4 in its list — the
/// seat simply went to the first confirmed one. The rule (V6): the seat
/// goes to a neighbour reachable from the open network — confirmed under a
/// PUBLIC address ([openNetwork]) — as soon as the node has one. A neighbour
/// known only privately holds it only as long as there is no other, and
/// hands it over at the next edge (a confirmation) to a reachable one,
/// UNLESS a standing invitation still names it (its readers hold cards
/// with that address). Otherwise nothing changes: between reachable ones
/// the seat moves only on removal.
///
/// **The card names no contact** (proposal "contacts as fixed neighbours",
/// 6.5): a contact's device ([contact], set by the host) takes the card's
/// seat only while no other neighbour answered, and hands it over at the
/// next edge to one that is not a contact. Whatever is left is closed where
/// strangers read it (`neighbourhood_card.dart`).
///
/// "Public" comes from the confirmed address alone — no board (§11.8a), no
/// cover (§3.1): [openNetwork] is `fromOutsideReachable`
/// (`outside_address.dart`), the one address classification of the tree.
///
/// Pure functions over the list; `neighbourhood.dart` applies them. A
/// separate file because the neighbourhood is at its line budget.
library;

import 'package:mycelium/neighbour.dart';

/// Whether [n] is reachable from the open network: one of its addresses is
/// confirmed and [public].
bool reachableNeighbour(Neighbour n, bool Function(NeighbourAddress a) public) =>
    n.addresses.any((a) => a.confirmedEver && public(a));

/// The seat a removal empties (W7 "the next CONFIRMED one"): the first of
/// [list] that [answered] in this run — a reachable one before a private
/// one (V6), a neighbour that is no [contact] device before one that is,
/// and one without a contact seat before one with (the card names no
/// contact where it can avoid it). `null`: nobody answered.
Neighbour? seatAfterRemoval(List<Neighbour> list,
    bool Function(Neighbour n) answered, bool Function(NeighbourAddress a) public,
    [bool Function(Neighbour n) contact = _none]) {
  Neighbour? private;
  for (final n in [
    ...list.where((n) => !contact(n)),
    ...list.where((n) => contact(n) && n.contactSeat == 0),
    ...list.where((n) => contact(n) && n.contactSeat > 0),
  ]) {
    if (!answered(n)) continue;
    if (reachableNeighbour(n, public)) return n;
    private ??= n;
  }
  return private;
}

/// The edge "a confirmation" (V6): the seat moves from a private [fixed] —
/// or from a [contact] device — to a reachable neighbour that is no contact
/// device and answered in this run ([justNow] has, by the confirmation
/// itself). `null`: the seat stays — the fixed one is reachable and no
/// contact, a standing invitation [named] it, or there is nobody better.
Neighbour? seatAfterConfirm(
  List<Neighbour> list,
  Neighbour fixed,
  int justNow, {
  required bool Function(Neighbour n) answered,
  required bool Function(Neighbour n) named,
  required bool Function(NeighbourAddress a) public,
  bool Function(Neighbour n) contact = _none,
}) {
  final leave = contact(fixed);
  if ((reachableNeighbour(fixed, public) && !leave) || named(fixed)) return null;
  for (final n in list) {
    if (n.id == fixed.id || n.contactSeat > 0) continue; // keeps its own seat
    if (contact(n) || !reachableNeighbour(n, public)) continue;
    if (n.id == justNow || answered(n)) return n;
  }
  return null;
}

bool _none(Neighbour _) => false;

/// The neighbours of the last run as they come back at start: addresses
/// this node can use ([usable]) only, a neighbour without one stays out;
/// a file with two card seats — or two holders of one contact seat — keeps
/// the first.
List<Neighbour> seatsFromMemory(
    Iterable<Neighbour> remembered, bool Function(NeighbourAddress a) usable) {
  var fixedSeen = false;
  final seats = <int>{0};
  return [
    for (final n in remembered)
      if (n.addresses.where(usable).toList() case final a when a.isNotEmpty)
        n.copy(
            addresses: a,
            fixed: n.fixed && !fixedSeen && (fixedSeen = true),
            contactSeat: seats.add(n.contactSeat) ? n.contactSeat : 0),
  ];
}
