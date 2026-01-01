import 'entry_record.dart';

/// When two relays count as INDEPENDENT.
///
/// THE PROBLEM that is closed here. The design demands in several
/// places confirmations "from independent relays in **different
/// partitions**" — §22.5.1 for the state `placed`, §13.4.2 for the
/// proof against backdating (E-35), §16.0 for durable objects.
/// At the same time §9.1 says explicitly: *"V4.1 has no such partition — a relay
/// stores what it is handed."* The word survived the replacement of V4.0,
/// the concept did not — and so `placed` had a condition
/// that did not exist.
///
/// THE RESOLUTION. What was meant was never the storage partition from V4.0 (a
/// prefix of length l that "belonged" to nodes). What was meant was
/// independence: two confirmations should not be able to come from the same hand.
/// V4.1 has a quantity for that which V4.0 did not have —
/// the ADDRESS, and since the entry record several per node.
///
/// A partition is therefore the NETWORK BLOCK: `/24` for IPv4, `/48` for
/// IPv6.
///
/// WHY NOT THE METRIC NEIGHBOURHOOD. It would be obvious to count two relays
/// as independent if their positions lie far
/// apart. That does not hold: the position is the hash of the node keys,
/// and keys can be generated until the position lands in the desired
/// range. Metric distance can be ground, an address block cannot —
/// whoever wants two confirmations from different `/24` needs addresses
/// in two `/24`.
///
/// WHAT THIS DEFINITION DOES NOT ACHIEVE, and that belongs to it: an operator
/// with addresses at several providers satisfies it. It makes
/// mass production more expensive, it does not prevent it — exactly the role that
/// §13.4.2 ascribes to the concept anyway ("makes mass production more
/// expensive").
abstract final class Partition {
  /// Prefix length for IPv4.
  static const int v4Prefix = 24;

  /// Prefix length for IPv6.
  static const int v6Prefix = 48;

  /// The partition of an address, or `null` if it cannot be
  /// interpreted.
  ///
  /// Unreadable content gets NO partition — and thus also does not count as
  /// independent. An address one does not understand is no proof.
  static String? of(String host) {
    if (host.contains(':')) return _v6(host);
    return _v4(host);
  }

  static String? _v4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return null;
    for (final t in parts) {
      final n = int.tryParse(t);
      if (n == null || n < 0 || n > 255) return null;
    }
    // /24: the first three octets.
    return 'v4:${parts[0]}.${parts[1]}.${parts[2]}';
  }

  static String? _v6(String host) {
    // Interpret only as far as necessary: the first three groups are /48.
    final withoutZone = host.split('%').first;
    if (!withoutZone.contains(':')) return null;
    final full = _expand(withoutZone);
    if (full == null) return null;
    return 'v6:${full[0]}:${full[1]}:${full[2]}';
  }

  /// Writes out an IPv6 address to eight groups. `null` on nonsense.
  static List<String>? _expand(String host) {
    final halves = host.split('::');
    if (halves.length > 2) return null;
    List<String> chunk(String s) =>
        s.isEmpty ? <String>[] : s.split(':').where((e) => e.isNotEmpty).toList();
    final links = chunk(halves[0]);
    final right = halves.length == 2 ? chunk(halves[1]) : <String>[];
    if (halves.length == 1) {
      if (links.length != 8) return null;
      return links.map(_norm).toList();
    }
    final missing = 8 - links.length - right.length;
    if (missing < 0) return null;
    return [
      ...links.map(_norm),
      ...List.filled(missing, '0'),
      ...right.map(_norm),
    ];
  }

  static String _norm(String g) {
    final n = int.tryParse(g, radix: 16);
    return n == null ? g.toLowerCase() : n.toRadixString(16);
  }

  /// All partitions in which this node sits.
  static Set<String> ofRecord(EntryRecord r) {
    final out = <String>{};
    for (final a in r.addresses) {
      final p = of(a.host);
      if (p != null) out.add(p);
    }
    return out;
  }

  /// Are the two in DIFFERENT partitions?
  ///
  /// If they overlap in even one, they count as dependent —
  /// the stricter reading, because one shared block suffices to provide both
  /// from one hand.
  /// How many of the passed relays are INDEPENDENT.
  ///
  /// Greedy: keep a relay whose network blocks overlap with none already
  /// kept. For a handful of relays that is cheap
  /// and exact enough.
  ///
  /// ── ONE IMPLEMENTATION, NOT TWO ───────────────────────────────────
  ///
  /// The same calculation is needed by readiness (`ReadinessTracker
  /// .verifiedRelaysAt`) and by the delivery state (`DeliveryRecord`, §22.5.1
  /// "≥ 2 … from independent relays in different partitions"). Two
  /// copies would be two places where the concept
  /// "independent" can develop apart — and the concept is
  /// exactly what is defended here.
  ///
  /// **A relay WITHOUT an interpretable address counts as ONE, but lends
  /// independence to no other.** Otherwise a node whose
  /// entry record is missing would never be a proof — and at the same time it must
  /// not count as a second hand, because an address one does not
  /// understand is no proof (see [of]).
  static int independentCount(Iterable<Set<String>> proRelay) {
    final proven = <String>{};
    var n = 0;
    for (final p in proRelay) {
      if (p.isEmpty) {
        n++;
        continue;
      }
      if (p.intersection(proven).isNotEmpty) continue;
      proven.addAll(p);
      n++;
    }
    return n;
  }

  static bool independent(EntryRecord a, EntryRecord b) {
    final pa = ofRecord(a);
    final pb = ofRecord(b);
    if (pa.isEmpty || pb.isEmpty) return false;
    return pa.intersection(pb).isEmpty;
  }
}
