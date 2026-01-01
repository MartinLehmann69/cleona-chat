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
/// **The card names no contact** (§5.2 "This place never goes to a
/// contact's device", D-26): a contact's device ([contact], set by the host)
/// never holds the card's seat. One that held it — it answered first, or
/// it became a contact later — hands it over at that edge to a neighbour
/// that is no contact and answered (a reachable one first, else a private
/// one), and where there is none the seat stays EMPTY: two devices that know
/// only each other have no card's seat (S407-EINST; until then the contact
/// kept it until a reachable non-contact answered — BAU-KN-P1 deviation 4,
/// S407-RBSEAT finding 2). Only a standing invitation that names the holder
/// keeps it there (its readers hold cards with that address). Whatever is
/// left is closed where strangers read it (`neighbourhood_card.dart`).
///
/// "Public" comes from the confirmed address alone — no board (§11.8a), no
/// cover (§3.1): [openNetwork] is `fromOutsideReachable`
/// (`outside_address.dart`), the one address classification of the tree.
///
/// Pure functions over the list; `neighbourhood.dart` applies them. A
/// separate file because the neighbourhood is at its line budget.
library;

import 'dart:io';

import 'package:mycelium/neighbour.dart';

/// Whether [n] is reachable from the open network: one of its addresses is
/// confirmed and [public] — and, with [evidence] (what its `0x25` said,
/// `neighbour_evidence.dart`), it did not say "not evidenced" (§5.2, D-114:
/// the rule of D-113 for the card's seat too). Nothing said (`null`, an
/// earlier 4.2 version): the address decides alone.
bool reachableNeighbour(Neighbour n, bool Function(NeighbourAddress a) public,
        [bool? Function(Neighbour n)? evidence]) =>
    evidence?.call(n) != false &&
    n.addresses.any((a) => a.confirmedEver && public(a));

/// The seat a removal empties (W7 "the next CONFIRMED one"): the first of
/// [list] that [answered] in this run — a reachable one before a private
/// one (V6), never a [contact] device (§5.2, D-26). `null`: no non-contact
/// answered, the seat stays empty.
Neighbour? seatAfterRemoval(List<Neighbour> list,
    bool Function(Neighbour n) answered, bool Function(NeighbourAddress a) public,
    [bool Function(Neighbour n) contact = _none,
    bool? Function(Neighbour n)? evidence]) {
  Neighbour? private;
  for (final n in list) {
    if (contact(n) || !answered(n)) continue;
    if (reachableNeighbour(n, public, evidence)) return n;
    private ??= n;
  }
  return private;
}

/// The edge "a confirmation" (V6): the seat moves from a private [fixed] to
/// a reachable neighbour that is no contact device and answered in this run
/// ([justNow] has, by the confirmation itself); from a [contact] device to
/// such a one too, and failing that to a private non-contact that answered
/// (§5.2, D-26). `null`: no move — the fixed one is reachable and no
/// contact, a standing invitation [named] it, or there is nobody to take it
/// (for a contact holder [cardSeatHandOver] then empties the seat).
/// [once]: the limit of D-115 ([NotEvidencedHandOver]); without it, none.
Neighbour? seatAfterConfirm(
  List<Neighbour> list,
  Neighbour fixed,
  int justNow, {
  required bool Function(Neighbour n) answered,
  required bool Function(Neighbour n) named,
  required bool Function(NeighbourAddress a) public,
  bool Function(Neighbour n) contact = _none,
  bool? Function(Neighbour n)? evidence,
  NotEvidencedHandOver? once,
}) {
  final leave = contact(fixed);
  if ((reachableNeighbour(fixed, public, evidence) && !leave) || named(fixed)) {
    return null;
  }
  Neighbour? to, private;
  for (final n in list) {
    if (n.id == fixed.id || n.contactSeat > 0) continue; // keeps its own seat
    if (contact(n) || (n.id != justNow && !answered(n))) continue;
    if (reachableNeighbour(n, public, evidence)) {
      to = n;
      break;
    }
    if (leave) private ??= n;
  }
  to ??= private;
  // D-115 (§5.2): limited is only the hand-over whose reason is the holder's
  // "not evidenced" — by its address alone it would stay. A contact's device
  // that must go ([leave]) and a private holder (V6) are not limited.
  if (to != null && once != null && !leave && reachableNeighbour(fixed, public) &&
      !once.take(fixed, to)) {
    return null;
  }
  return to;
}

/// The one hand-over away from a "not evidenced" holder of the card's seat
/// (§5.2, D-115). A node learns what a neighbour says only from its `0x25`,
/// i.e. once that neighbour holds the seat and has the codes (§8.1). Without
/// a limit a node whose neighbours are all behind routers handed the seat
/// through every one of them (S419: six hand-overs in
/// `smoke_mycelium_own_line_app`, each with a registration and one deposit
/// per other own device, `S419-RCA-D114-WECHSEL.md` W-1). So the seat moves
/// this way at most ONCE between two starts or network changes; if the new
/// holder says "not evidenced" too, it stays with it until the next one.
/// A start is a new [Neighbourhood] (memory only); a network change or stop
/// is `Readiness.reset`, which calls `Neighbourhood.runLimit`, which calls
/// [reopen] — the same tick as `Readiness.resets`, under which the
/// statements themselves expire (`neighbour_evidence.dart`). A removal
/// ([seatAfterRemoval]) is no such hand-over and is not limited.
class NotEvidencedHandOver {
  bool _used = false;

  /// Log only, set by the host: the hand-over from [holder] to [to] that the
  /// limit waived.
  void Function(Neighbour holder, Neighbour to)? onWaived;

  /// A start or network change: the next such hand-over may go again.
  void reopen() => _used = false;

  /// A hand-over from the "not evidenced" [holder] to [to] stands: `true`
  /// takes the one of this start or network change (the caller applies it),
  /// `false` — it went already — keeps the seat with [holder].
  bool take(Neighbour holder, Neighbour to) {
    if (!_used) return _used = true;
    onWaived?.call(holder, to);
    return false;
  }
}

bool _none(Neighbour _) => false;

/// Whether the confirmation of [address]:[port] of [old] (the entry BEFORE
/// the stamp) is an edge for the fixed places (§11.8.8, C-14, S408): the
/// neighbour answers for the first time in this run (§11.8.2), or for the
/// first time under an address reachable from the open network — the first
/// answer of the better qualified one. Any later answer stamps and moves no
/// place. Without a yardstick ([answered] `null`) every confirmation counts.
bool seatEdgeAt(Neighbour old, InternetAddress address, int port,
    bool Function(Neighbour n)? answered,
    bool Function(NeighbourAddress a) public) {
  if (answered == null || !answered(old)) return true;
  if (!public(NeighbourAddress(address, port, kUnconfirmed))) return false;
  final reach = [for (final a in old.addresses) if (public(a)) a];
  return reach.isEmpty || !answered(old.copy(addresses: reach));
}

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

/// The edge "the contact seats changed" (S405 V1, owner decision
/// 06.10.2026): the card's seat is handed over by the same rule as at a
/// confirmation ([seatAfterConfirm]) — away from a contact's device or a
/// private holder to a reachable neighbour that answered. Until S405 only a
/// confirmation asked it; a deleted contact left its former device holding
/// the card's seat until the next confirmations (field 06.10.2026: 20:15:32
/// deleted, 20:15:58 still "card neighbour NONE"). In place, like
/// `seatContacts`; `true` if the seat moved. A contact's device on the seat
/// with nobody to take it empties it (D-26); an empty seat is filled by the
/// rule of a removal ([seatAfterRemoval]) — never with a contact's device.
/// [once]: the limit of D-115, as at a confirmation.
bool cardSeatHandOver(List<Neighbour> list, bool Function(Neighbour n) answered,
    bool Function(Neighbour n) named, bool Function(NeighbourAddress a) public,
    bool Function(Neighbour n) contact, [bool? Function(Neighbour n)? evidence,
    NotEvidencedHandOver? once]) {
  final f = list.where((n) => n.fixed).firstOrNull;
  final Neighbour? to;
  if (f == null) {
    to = seatAfterRemoval(list, answered, public, contact, evidence);
    if (to == null) return false;
  } else {
    to = seatAfterConfirm(list, f, -1,
        answered: answered, named: named, public: public, contact: contact,
        evidence: evidence, once: once);
    if (to == null && (!contact(f) || named(f))) return false;
  }
  for (var j = 0; j < list.length; j++) {
    if (list[j].fixed != (list[j].id == to?.id)) {
      list[j] = list[j].copy(fixed: list[j].id == to?.id);
    }
  }
  return true;
}
