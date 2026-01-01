import 'dart:io';
import 'dart:math' as math;

import 'package:mycelium/wire_target.dart';
import 'package:mycelium/card_address.dart';
import 'package:mycelium/neighbour.dart';
import 'package:mycelium/neighbourhood_contacts.dart';
import 'package:mycelium/neighbourhood_join.dart';
import 'package:mycelium/neighbourhood_open.dart';
import 'package:mycelium/neighbourhood_seat.dart';
import 'package:mycelium/outside_address.dart' show fromOutsideReachable;

export 'package:mycelium/neighbour.dart';

/// The neighbours that this node knows — cap, stamp, memory (V4.2 §11.8).
/// A neighbour is a NODE with its addresses (`neighbour.dart`, S394 V4);
/// 32 counts nodes. Each address carries its stamp, set only by [confirm]
/// (an ANSWER under this address, W8); a hint is [unconfirmed].
///
/// **Silence never removes** (§11.8.5): only a failed USE removes an address
/// ([useFailed], via `Readiness.mute` with a counter proof, E2), the
/// neighbour goes with its last — an edge: [onUnderTarget], at most once per
/// [refillInterval], a round inside it DROPPED (§5.4; S392 finding 3). A
/// lost family removes nothing, it [waiting]s (C-7). Used is only an address
/// with a socket for it ([speaks], §11.1 V1); seats: `neighbourhood_seat.dart`.
class Neighbourhood {
  /// The optimum (§11.8) and at the same time the cap — in NODES.
  static const int atMost = 32;

  /// After this long without a stamp an address is stale (§11.8).
  static const Duration staleAfter = Duration(days: 1);

  /// The stamp of an address that has never been confirmed.
  static final DateTime unconfirmed = kUnconfirmed;

  final Duration refillInterval; // [kRefillInterval], shorter in probes

  final List<Neighbour> _list = [];
  final Waiting _waiting = Waiting(atMost);
  final OpenSet _open;

  /// Neighbour id -> when it came into the list (memory only, for [_rank]).
  final Map<int, DateTime> _learned = {};

  Neighbourhood({
    this.refillInterval = kRefillInterval,
    math.Random? random,
  }) : _open = OpenSet(random ?? math.Random.secure());

  /// A socket for the address family of [a]? (§11.1, V1; set by the node.)
  bool Function(InternetAddress a) speaks = (_) => true;

  /// V6/V7: whether [a] is reachable from the open network — the ONE address
  /// classification (`fromOutsideReachable`); probes on 127.0.0.1 let the
  /// loopback play a public address. [namedByCards]: a standing invitation
  /// names this neighbour (set by the host, `node_invitation.dart`).
  bool Function(InternetAddress a) openNetwork = fromOutsideReachable;
  bool Function(Neighbour n) namedByCards = (_) => false;

  /// Device of an own contact / excluded by the user (§15.10); by the host.
  bool Function(Neighbour n) isContactDevice = (_) => false;
  bool Function(Neighbour n) neverFixedNeighbour = (_) => false;
  /// Reachable only over IPv4 on a metered link (§8.1); by the host network.
  bool Function(Neighbour n) v4OnlyOnMetered = (_) => false;

  /// Edge below [atMost]: the caller starts what a cold start starts (§11.8).
  void Function()? onUnderTarget;

  /// Who LEAVES the list — the part that left (see [observe]).
  void Function(Neighbour gone)? onRemoved;

  final List<void Function(Neighbour)> _removedListener = [];
  final List<void Function(Neighbour)> _confirmedListener = [];
  final List<void Function()> _joinedListener = [];

  DateTime? _lastRound; // the only state the ceiling needs (§5.4)

  /// For `readiness.dart`, synchronously: every removal and confirmation —
  /// the PART concerned, with id and seat — and every join into one node.
  void observe({
    required void Function(Neighbour gone) removed,
    required void Function(Neighbour n) onConfirmed,
    void Function()? joined,
  }) {
    _removedListener.add(removed);
    _confirmedListener.add(onConfirmed);
    if (joined != null) _joinedListener.add(joined);
  }

  /// All neighbours: the fixed one first (W7), then by [_rank]. Read only.
  List<Neighbour> get all => List.unmodifiable(_list);

  int get count => _list.length; // NODES; [waiting] does not count
  List<Neighbour> get waiting => _waiting.all; // no family: §11.8.1, C-7
  List<Neighbour> get toRemember => forMemory(_list, _waiting.all, atMost);

  /// One address per neighbour — its [Neighbour.first], a family of this
  /// node — in the order of [all].
  List<({InternetAddress address, int port})> get asEntries =>
      List.unmodifiable(
          [for (final n in _list) (address: n.address, port: n.port)]);

  /// Whether [address]:[port] CAN be a neighbour at all: a length the card
  /// knows (4 or 16 B), a target safe for the wire (`wire_target.dart`).
  static bool possible(InternetAddress address, int port) =>
      CardAddressType.fromLength(address.rawAddress.length) != null &&
      impossibleTarget(address, port, 0) == null;

  /// Answered in THIS run (§22.7.1)? Set by `Readiness`.
  bool Function(Neighbour n)? respondingNow;

  /// The card's seat of the open set (W7, V6): the neighbour the own cards
  /// name; survives the restart. Rules: `neighbourhood_seat.dart`.
  Neighbour? get fixedNeighbour => _list.where((n) => n.fixed).firstOrNull;
  Neighbour? get cardNeighbour => fixedNeighbour;

  /// All fixed neighbours (§5.2, §8.1): the contact seats first, then the card's.
  List<Neighbour> get fixedNeighbours => fixedOrder(_list);

  /// The neighbour that [a]:[port] belongs to — as an address, not a name.
  Neighbour? holding(InternetAddress a, int port) {
    final i = _spot(a, port);
    return i < 0 ? null : _list[i];
  }

  /// The neighbour that [c] belongs to — as an address OR a name (§8.1, V5).
  Neighbour? recognise(CardAddress c) =>
      _list.where((n) => n.knows(c)).firstOrNull;

  /// Admits a HINT (card, foreign call, external entry), [unconfirmed]; a
  /// known address stays — a hint confirms nothing. `true` only if a NEW
  /// neighbour arose and stays (the caller's edge). No socket, no entry (V1).
  bool remember(InternetAddress address, int port) {
    if (!possible(address, port) || !speaks(address)) return false;
    if (_spot(address, port) >= 0) return false;
    return _admit(Neighbour(address, port, unconfirmed));
  }

  /// Stamps [address]:[port] with [now], creates the neighbour if unknown; only for an
  /// ANSWER (W8). Fixed places move only at their edge ([seatEdgeAt], §11.8.8, C-14).
  void confirm(InternetAddress address, int port, DateTime now) {
    if (!possible(address, port) || !speaks(address)) return;
    final i = _spot(address, port);
    final Neighbour n;
    final edge = i < 0 || seatEdgeAt(_list[i], address, port, respondingNow, _public);
    if (i >= 0) {
      final old = _list[i];
      n = old.copy(
          addresses: [
            NeighbourAddress(address, port, now),
            ...old.addresses.where((x) => !x.isAt(address, port)),
          ],
          fixed: old.fixed || (edge && fixedNeighbour == null));
      _list[i] = n;
      _sort();
    } else {
      n = Neighbour(address, port, now, fixed: fixedNeighbour == null);
      if (!_admit(n)) return; // immediately fell over the cap
    }
    final f = edge ? fixedNeighbour : null; // V6: the seat moves at its edge
    final to = f == null
        ? null
        : seatAfterConfirm(_list, f, n.id,
            answered: respondingNow ?? (_) => false,
            named: namedByCards,
            public: _public,
            contact: isContactDevice); // 6.5: the card names no contact
    if (to != null) _seat(to.id);
    if (edge) contactSeatsCheck(n.id); // ... and the contact seats too
    // The listeners get the part that was confirmed: this one address.
    final part = holding(address, port)!
        .copy(addresses: [NeighbourAddress(address, port, now)]);
    for (final h in List.of(_confirmedListener)) {
      h(part);
    }
  }

  /// A use of [address]:[port] has failed — a request that expected an
  /// answer stayed without one. Removes THIS address and reports it; the
  /// neighbour goes with its last address, and only that is an edge for
  /// the refill. `true` if an address was removed.
  bool useFailed(InternetAddress address, int port) {
    final i = _spot(address, port);
    if (i < 0) return false;
    final n = _list[i];
    final gone = n.copy(
        addresses: [for (final a in n.addresses) if (a.isAt(address, port)) a]);
    final rest = [for (final a in n.addresses) if (!a.isAt(address, port)) a];
    if (rest.isNotEmpty) {
      _list[i] = n.copy(addresses: rest);
      _sort();
      _report(gone);
      return true;
    }
    _list.removeAt(i);
    if (fixedNeighbour == null) _moveUp();
    contactSeatsCheck(); // a removal is the edge for the replacement
    _report(gone);
    _open.draw(_list, DateTime.now());
    _refill();
    return true;
  }

  /// §5.5/§11.8a, V2–V4: [from]:[port] named [own] as its own (sealed packet,
  /// or one identifier in answers, `Readiness.nodeLearn`) — ONE neighbour. `bound: false`:
  /// not sent from one of them, the caller takes them as hints. `fresh`: a
  /// new neighbour arose — below the optimum only, a hint never displaces.
  ({bool bound, bool fresh}) ownAddresses(
      InternetAddress from, int port, List<CardAddress> own) {
    final j = joinOwn(_list, from, port, own, speaks, possible);
    if (j == null) return (bound: false, fresh: false);
    if (j.joined.isEmpty && count >= atMost) return (bound: true, fresh: false);
    _list.removeWhere((n) => j.joined.any((x) => x.id == n.id));
    _list.add(j.whole);
    _learned.putIfAbsent(j.whole.id, DateTime.now);
    _sort();
    _open.draw(_list, DateTime.now());
    for (final h in List.of(_joinedListener)) {
      h();
    }
    return (bound: true, fresh: j.joined.isEmpty);
  }

  /// Edge: the wire gained or lost a socket (§11.1), see [refamily]. Nothing
  /// is removed (§11.8.5, C-7): without a usable address a neighbour
  /// [waiting]s; the lost part is reported (it answers no more). No refill.
  void socketsChanged() {
    for (final r in refamily(_list, speaks)) {
      final i = _list.indexWhere((x) => x.id == r.old.id);
      if (r.now case final now?) {
        _list[i] = now;
      } else {
        _waiting.add(_list.removeAt(i));
      }
      if (r.lost case final lost?) _report(lost);
    }
    for (final a in _waiting.wake(speaks)) {
      if (rejoin(_list, a)) _learned[a.id] = DateTime.now();
    }
    _sort();
    _cap();
    if (fixedNeighbour == null) _moveUp();
    contactSeatsCheck();
    _open.draw(_list, DateTime.now());
  }


  /// W7 "the next CONFIRMED one" (a reachable one first, V6): the emptied
  /// seat goes HERE, ahead of [_report], so the edge
  /// `HostNetwork.fixedCheck` carries it (`berichte/S392-FIX-FESTER-PLATZ.md`).
  void _moveUp() {
    final answered = respondingNow;
    final to = answered == null
        ? null : seatAfterRemoval(_list, answered, _public, isContactDevice);
    if (to != null) _seat(to.id);
  }

  /// The fixed seat to the neighbour with [id], and only to it.
  void _seat(int id) {
    for (var j = 0; j < _list.length; j++) {
      if (_list[j].fixed != (_list[j].id == id)) {
        _list[j] = _list[j].copy(fixed: _list[j].id == id);
      }
    }
    _sort();
  }

  /// EDGE for the contact seats and, after them, the card's seat (S405 V1) — also by the host.
  void contactSeatsCheck([int? justNow]) {
    seatAll(_list, justNow, respondingNow ?? (_) => false, namedByCards, isContactDevice,
        neverFixedNeighbour, _public, v4OnlyOnMetered); // `neighbourhood_contacts.dart`, D-26
    _sort();
  }

  bool _public(NeighbourAddress a) => openNetwork(a.address);

  /// Neighbours whose newest stamp is younger than [staleAfter], newest first.
  List<Neighbour> confirmed(DateTime now) => [
        for (final n in _afterStamp())
          if (now.difference(n.last) < staleAfter) n
      ];

  /// Per ADDRESS whose stamp is [staleAfter] old or older (also never
  /// confirmed), the newest first, one part per address — for the one-time
  /// attempt at the next edge; each address is confirmed on its own (V4).
  List<Neighbour> stale(DateTime now) => [
        for (final n in _afterStamp())
          for (final a in n.addresses)
            if (now.difference(a.last) >= staleAfter) n.copy(addresses: [a])
      ];

  /// At most four neighbours, the fixed one first (§5.2, W7).
  List<Neighbour> openSet() => _open.read(_list);

  /// Redraws the loose seats — at edges.
  void openSetNewDraw(math.Random random) =>
      _open.draw(_list, DateTime.now(), random);

  /// Sets the state from memory — exactly one call at start (edge: the open
  /// set is drawn). What has no socket here [waiting]s or is a name (C-7).
  void outMemory(Iterable<Neighbour> remembered) {
    final old = List.of(_list);
    final m = fromMemory(remembered, possible, speaks);
    _waiting.clear();
    m.wait.forEach(_waiting.add);
    _list
      ..clear()
      ..addAll(seatsFromMemory(m.use, (_) => true));
    final now = DateTime.now();
    _learned
      ..clear()
      ..addAll({for (final n in _list) n.id: now});
    _sort();
    _cap();
    for (final n in old) {
      if (!_list.any((x) => x.id == n.id)) _report(n);
    }
    _open.draw(_list, DateTime.now());
  }

  /// Network change or stop (`Readiness.reset`): the open set is redrawn.
  void runLimit() => _open.draw(_list, DateTime.now());

  void empty() { // only for probes: forget everything
    final old = List.of(_list);
    _list.clear();
    _waiting.clear();
    old.forEach(_report);
    runLimit();
  }

  bool _admit(Neighbour n) {
    _learned[n.id] = DateTime.now();
    _list.add(n);
    _sort();
    _cap();
    if (!_list.any((x) => x.id == n.id)) return false;
    _open.draw(_list, DateTime.now()); // edge: new neighbour
    return true;
  }

  /// §5.4 "never on a schedule": a round inside [refillInterval] is
  /// dropped; "under the target" is still true at the next edge.
  void _refill() {
    if (count >= atMost) return;
    final last = _lastRound;
    if (last != null && DateTime.now().difference(last) < refillInterval) {
      return;
    }
    _lastRound = DateTime.now();
    onUnderTarget?.call();
  }

  /// Above [atMost] the neighbour with the OLDEST newest stamp gives way (a
  /// new hint is not "fresher" than a confirmed one); among equal stamps the
  /// one listed longest; the fixed one never (W7). First remove, then
  /// report (S387: otherwise the loop ran forever).
  void _cap() {
    while (_list.length > atMost) {
      var i = -1;
      for (var j = 0; j < _list.length; j++) {
        if (_list[j].seated) continue;
        if (i < 0 || !_list[j].last.isAfter(_list[i].last)) i = j;
      }
      if (i < 0) return; // at most four seated — cannot occur at 33
      _report(_list.removeAt(i));
    }
  }

  void _report(Neighbour gone) {
    if (!_list.any((x) => x.id == gone.id)) _learned.remove(gone.id);
    for (final h in List.of(_removedListener)) {
      h(gone);
    }
    onRemoved?.call(gone);
  }

  int _spot(InternetAddress address, int port) =>
      _list.indexWhere((n) => n.has(address, port));

  List<Neighbour> _afterStamp() =>
      List.of(_list)..sort((a, b) => b.last.compareTo(a.last));

  /// The seats in front ([seatOrder]), then by [_rank] descending.
  void _sort() => _list.sort((a, b) => seatOrder(a) != seatOrder(b)
      ? seatOrder(a).compareTo(seatOrder(b))
      : _rank(b).compareTo(_rank(a)));

  /// The rank in [all]: a confirmed neighbour's newest stamp, a never
  /// confirmed hint's LEARNING moment — so a collection asks a fresh hint
  /// first and it sinks if unused (`smoke_readiness` B1, G4); a deposit
  /// ranks it last (`ownHoldersRanked`, OP-19).
  DateTime _rank(Neighbour n) => n.last.isAtSameMomentAs(unconfirmed)
      ? (_learned[n.id] ?? unconfirmed)
      : n.last;
}

/// Smallest interval between two refill rounds (§11.8: „at most one per minute").
const Duration kRefillInterval = Duration(minutes: 1);
