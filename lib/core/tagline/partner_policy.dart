import 'package:cleona/core/sync/entry_record.dart';

/// Which address family an endpoint has.
///
/// „Family" here means ADDRESS family (IPv4/IPv6), not tag family —
/// the two words stand next to each other in the draft and mean
/// different things. The diversity rule steers sync partners, explicitly
/// not onion hops (§7.3).
enum AddressFamily { v4, v6 }

/// Recognises the family by the address. A colon does not occur in an
/// IPv4 address.
AddressFamily familyOf(String host) =>
    host.contains(':') ? AddressFamily.v6 : AddressFamily.v4;

/// How many sync partners a node keeps, and why exactly that many.
///
/// THE NUMBER IS CALCULATED, not grabbed (2026-08-22).
///
/// **Upwards the NAT binding binds, not the bandwidth.** The
/// cover stream runs per NODE, not per partner: the slot plan draws
/// one partner per slot (`cover_stream.dart`, `drawPartner`). Outgoing
/// that is 12.96 MB/day, independent of the number of partners. What grows with the
/// number of partners is the interval between two cells ON ONE
/// connection: `8 s x P`. And that is the only traffic that keeps the
/// UDP binding alive. With a timeout of 30 s (carrier NAT)
/// P <= 3.8 holds, at 60 s P <= 7.5, at 120 s P <= 15.
///
/// **Downwards encirclement and hysteresis bind.** If all partners are in
/// one hand, that hand sees everything and can withhold everything; with
/// uniformly distributed drawing that is `f^P` — at f = 0.1 thus 1 % for
/// P = 2 and 0.01 % for P = 4. Added to that is §22.7: `ready` demands two
/// confirmed relays, and with P = 2 every connection drop throws the
/// node immediately back to `connecting`.
///
/// **And the family rule hits the same number from another direction.**
/// §25: if the share of the weaker address family falls below 25 %, the
/// node raises to two partners per family. Two families times two is
/// four.
///
/// **What the number does NOT achieve.** Partners are not the responsible
/// relays. A stored item goes via a partner as first hop on to
/// the R ~ 20 responsible ones (§22.5.2); the number of partners thus determines over
/// how many paths a node gets there, not how many responsible ones it
/// reaches.
final class PartnerPolicy {
  /// Zielzahl.
  final int target;

  /// Aimed for per address family, as soon as both occur (§25).
  final int perFamily;

  const PartnerPolicy({
    this.target = 4,
    this.perFamily = 2,
  });

  /// Does this node still accept a partner?
  ///
  /// [current] are the families of the existing partners.
  bool hasRoom(List<AddressFamily> current) => current.length < target;

  /// Should a partner of this family be admitted preferentially although
  /// the target number is already reached?
  ///
  /// Yes, if its family is under-represented AND there is a
  /// second family at all. A pure IPv4 network should not wait forever for an
  /// IPv6 counterpart that does not exist.
  bool wantsForDiversity(List<AddressFamily> current, AddressFamily candidate) {
    if (current.length < target) return true;
    final n = current.where((f) => f == candidate).length;
    return n < perFamily && current.any((f) => f != candidate);
  }

  /// Which existing partner yields when room is needed for diversity
  /// — the one from the over-represented family.
  ///
  /// Returns `null` if no one should yield.
  int? evictFor(List<AddressFamily> current, AddressFamily candidate) {
    if (current.length < target) return null;
    final equal = <int>[];
    for (var i = 0; i < current.length; i++) {
      if (current[i] != candidate) equal.add(i);
    }
    // Only evict from a family that holds more than its share.
    if (equal.length <= perFamily) return null;
    return equal.last;
  }

  /// The share of the weaker family. §25 pulls up the
  /// countermeasure at 25 %.
  double weakerShare(List<AddressFamily> current) {
    if (current.isEmpty) return 0;
    final v4 = current.where((f) => f == AddressFamily.v4).length;
    final v6 = current.length - v4;
    final weaker = v4 < v6 ? v4 : v6;
    return weaker / current.length;
  }

  /// Is the countermeasure from §25 running?
  bool diversityAlarm(List<AddressFamily> current) =>
      current.length >= 2 && weakerShare(current) < 0.25;
}

/// The family of an entry record — that of the first address.
AddressFamily familyOfRecord(EntryRecord r) => familyOf(r.host);

/// ALL families on which this node is reachable.
///
/// A dual-stack node covers both and is counted for diversity for
/// both. If only its first address counted, §25 would measure
/// which family it happened to name first, not which it has.
Set<AddressFamily> familiesOfRecord(EntryRecord r) =>
    {for (final a in r.addresses) a.isV6 ? AddressFamily.v6 : AddressFamily.v4};
