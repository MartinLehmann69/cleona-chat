/// Joining addresses into one neighbour, and sorting them by address
/// family — the two computations behind `Neighbourhood.ownAddresses` and
/// `Neighbourhood.socketsChanged` (S394 V1, V4).
///
/// Pure functions over a list of neighbours: they change nothing and send
/// nothing; `neighbourhood.dart` applies what they return. Separate
/// because the neighbourhood is at its line budget (mycelium/README.md
/// rule 2), and because what is computed here can be checked without a
/// neighbourhood around it.
library;

import 'dart:io';

import 'package:mycelium/card_address.dart';
import 'package:mycelium/neighbour.dart';

/// What a join replaces: [joined] leave the list, [whole] takes their place.
typedef Join = ({List<Neighbour> joined, Neighbour whole});

/// [from]:[port] named [own] as its own addresses (§5.5, §11.8a) — joins
/// into ONE neighbour every entry of [list] that holds [from]:[port] or one
/// of [own] (as address or name), plus [own] itself: an address of a family
/// this node [speaks] as an unconfirmed address, any other as a name. The
/// id and the fixed seat move over from the joined entries — the fixed one
/// first, then the one holding [from]:[port].
///
/// The same join serves the third rule of §11.8: addresses that named the
/// same node identifier in answers within one run (`Readiness.nodeLearn`
/// passes them as [own], S407-N2).
///
/// `null` if [from]:[port] is not among [own]: then nothing here is bound
/// (V4: "in a sealed packet that comes from one of them").
Join? joinOwn(List<Neighbour> list, InternetAddress from, int port,
    List<CardAddress> own, bool Function(InternetAddress a) speaks,
    bool Function(InternetAddress a, int port) possible) {
  final src = CardAddress(from.rawAddress, port);
  if (!speaks(from) || !own.any((o) => o.equal(src))) return null;
  final joined = [
    for (final n in list)
      if (n.has(from, port) || own.any(n.knows)) n
  ];
  final addresses = <NeighbourAddress>[
    for (final n in joined) ...n.addresses,
    for (final o in own)
      if (speaks(ip(o)) && possible(ip(o), o.port))
        NeighbourAddress(ip(o), o.port, kUnconfirmed),
  ];
  // The joined names first: a name that waits with its stamp keeps it.
  final names = <NeighbourAddress>[
    for (final n in joined) ...n.names,
    for (final o in own)
      if (!speaks(ip(o)) && o.port != 0)
        NeighbourAddress(ip(o), o.port, kUnconfirmed),
  ];
  final lead = [
    ...joined.where((n) => n.fixed),
    ...joined.where((n) => n.has(from, port)),
    ...joined,
  ];
  return (
    joined: joined,
    whole: Neighbour.of(addresses,
        names: names,
        fixed: joined.any((n) => n.fixed),
        contactSeat: joined.any((n) => n.fixed)
            ? 0 // the card's seat wins; the contact seat is refilled at the next edge
            : joined.map((n) => n.contactSeat).firstWhere((s) => s > 0, orElse: () => 0),
        id: lead.isEmpty ? null : lead.first.id),
  );
}

/// One neighbour after the wire gained or lost a socket (§11.1): [now] is
/// what stays in use (`null` = no usable address is left: it waits, see
/// [asleep]), [lost] the addresses that became names (`null` = none).
typedef Refamily = ({Neighbour old, Neighbour? now, Neighbour? lost});

/// For every neighbour of [list] whose addresses or names do not fit what
/// this node [speaks] any more: an address of a family no longer held
/// becomes a name, a name of a family held again an address — each with
/// its stamp. Nothing is removed: an address under a lost family waits
/// for the family to return (§11.8.5; S407-LB-P6, C-7).
List<Refamily> refamily(
    List<Neighbour> list, bool Function(InternetAddress a) speaks) {
  final out = <Refamily>[];
  for (final n in list) {
    final lost = [for (final a in n.addresses) if (!speaks(a.address)) a];
    final back = [for (final c in n.names) if (speaks(c.address)) c];
    if (lost.isEmpty && back.isEmpty) continue;
    out.add((
      old: n,
      now: awake(n, speaks),
      lost: lost.isEmpty ? null : n.copy(addresses: lost),
    ));
  }
  return out;
}

/// [n] sorted by what this node [speaks]: its usable addresses — names of a
/// family held again among them — as addresses, the rest as names, each
/// with its stamp; `null` while none is usable.
Neighbour? awake(Neighbour n, bool Function(InternetAddress a) speaks) {
  final all = [...n.addresses, ...n.names];
  final use = [for (final a in all) if (speaks(a.address)) a];
  if (use.isEmpty) return null;
  return n.copy(
      addresses: use, names: [for (final a in all) if (!speaks(a.address)) a]);
}

/// A neighbour with no usable address as it waits (§11.8.1 acquaintance
/// "held under a family this node has no socket for"): every address it is
/// known under, with its stamp, no seat — the seat went on to an answering
/// neighbour (§11.8.8 W7); [awake] takes it back into the list.
Neighbour asleep(Neighbour n) =>
    Neighbour.of([...n.addresses, ...n.names], id: n.id);

/// The acquaintances under a family this node has no socket for (§11.8.1,
/// §11.8.5): not in the list, not counted, never used — held as [asleep]
/// until [wake] finds a usable address. At most [atMost]; above it the one
/// whose newest stamp is oldest gives way (§11.8.10).
class Waiting {
  final int atMost;
  final List<Neighbour> _l = [];
  Waiting(this.atMost);

  List<Neighbour> get all => List.unmodifiable(_l);

  void clear() => _l.clear();

  void add(Neighbour n) {
    _l
      ..removeWhere((w) => w.id == n.id)
      ..add(asleep(n))
      ..sort((a, b) => b.last.compareTo(a.last));
    if (_l.length > atMost) _l.removeRange(atMost, _l.length);
  }

  /// Those with a usable address again, taken out, sorted by [awake].
  List<Neighbour> wake(bool Function(InternetAddress a) speaks) {
    final out = <Neighbour>[];
    for (final w in List.of(_l)) {
      if (awake(w, speaks) case final a?) {
        _l.remove(w);
        out.add(a);
      }
    }
    return out;
  }
}

/// [a] back into [list]: into the entry that knows one of its addresses (it
/// named them as its own meanwhile; of two copies of one address the newer
/// stamp stays), else as an entry of its own — then `true`.
bool rejoin(List<Neighbour> list, Neighbour a) {
  final i = list.indexWhere((n) => knowsAny(n, a));
  if (i < 0) {
    list.add(a);
    return true;
  }
  List<NeighbourAddress> m(List<NeighbourAddress> x, List<NeighbourAddress> y) =>
      [...x, ...y]..sort((p, q) => q.last.compareTo(p.last));
  final e = list[i];
  list[i] = e.copy(
      addresses: m(e.addresses, a.addresses), names: m(e.names, a.names));
  return false;
}

/// Whether [n] knows one of the addresses [w] is known under.
bool knowsAny(Neighbour n, Neighbour w) =>
    [...w.addresses, ...w.names].any((a) => n.knows(a.asCardAddress));

/// What memory keeps (§11.8.3 source 1): the neighbours of [list] and those
/// of [waiting] that no entry of [list] knows, each with every address it
/// is known under, names included. Above [atMost] the one whose newest
/// stamp is oldest gives way, a seat never (§11.8.10) — the format stays
/// that of 4.2.3 (≤ 32 nodes, ≤ 4 addresses each, `host_memory.dart`).
List<Neighbour> forMemory(
    List<Neighbour> list, List<Neighbour> waiting, int atMost) {
  final out = [
    for (final n in list)
      n.copy(addresses: [...n.addresses, ...n.names], names: const []),
    for (final w in waiting)
      if (!list.any((n) => knowsAny(n, w))) w,
  ];
  while (out.length > atMost) {
    var i = -1;
    for (var j = 0; j < out.length; j++) {
      if (out[j].seated) continue;
      if (i < 0 || !out[j].last.isAfter(out[i].last)) i = j;
    }
    if (i < 0) break; // at most four seated
    out.removeAt(i);
  }
  return out;
}

/// The remembered neighbours as the start takes them (§11.8.3 source 1):
/// each with its [possible] addresses, names included, sorted by [awake] —
/// into [use] for the list, or into [wait] if none is usable here; one
/// without a possible address at all is no neighbour.
({List<Neighbour> use, List<Neighbour> wait}) fromMemory(
    Iterable<Neighbour> remembered,
    bool Function(InternetAddress a, int port) possible,
    bool Function(InternetAddress a) speaks) {
  final use = <Neighbour>[], wait = <Neighbour>[];
  for (final r in remembered) {
    final ok = [
      for (final a in [...r.addresses, ...r.names])
        if (possible(a.address, a.port)) a
    ];
    if (ok.isEmpty) continue;
    final m =
        Neighbour.of(ok, fixed: r.fixed, contactSeat: r.contactSeat, id: r.id);
    final a = awake(m, speaks);
    a == null ? wait.add(m) : use.add(a);
  }
  return (use: use, wait: wait);
}

/// The address of [c] as an [InternetAddress].
InternetAddress ip(CardAddress c) => InternetAddress.fromRawAddress(c.address);
