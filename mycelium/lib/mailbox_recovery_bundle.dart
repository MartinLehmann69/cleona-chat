/// The recovery bundle in the post box (V4.2 §13.3; finding B-1, owner
/// approval S398: E1-b, E2-a, E3-a, E5-a, E6-a).
///
/// mycelium carries the bytes and knows neither the seed nor what they say:
/// the application seals the bundle (`bundle_key`, §13.3.3) and supplies the
/// box key per UTC day (`recovery_key(i)`, E3-a). Here stands WHERE it lies,
/// WHEN it is renewed and HOW it is looked for:
///
///  * **Where (E1-b).** One deposit (E6-a) — split on the wire like any
///    packet (§11.2), no lane of its own — with three holders: the own fixed
///    neighbours first (contacts' devices, §5.2: the ones a recovering device
///    reaches by reading such a contact's card again), then the own
///    neighbours by rank (§8.2, `post_box_holders.dart`).
///  * **When (E2-a).** At a collection edge (§8.2, `node_collect_edge.dart`),
///    if the last deposit is [kBundleRenewAfter] old or older. No timer
///    (§5.4): a device that meets no edge for [kBundleLife] lets it lapse,
///    and [BundleBox.lastDeposit] is what the interface shows (§13.3.4).
///  * **How it is found.** ONE question with the values of today and the six
///    days before (the retention of §8.2, [bundleAsk]) — at every collection
///    edge while the application says this is the recovery case
///    ([BundleBox.seeking]), and with the addresses of any card read
///    ([BundleBox.seek] with `withWhom`). A holder hands it out only against
///    the proof with that day's box key and deletes it on the collector's
///    receipt (E5-a); the device lays a fresh one once it has taken it over.
///
/// While [BundleBox.seeking] nothing is laid: a device that has not found its
/// bundle yet would lay an emptier, newer one over it (§13.3.2 "time of
/// deposit — the newest of several copies wins").
///
/// **Before a renewal (§13.3.4 "A retired device removes the identity",
/// D-103).** The box first reads the values of the days since its own last
/// deposit, from the day after it ([renewAsk]), and leaves what it finds with
/// its holders; the application decides ([BundleBox.retiredBy]) whether a
/// bundle among them continues this device's keys along the rotation chain.
/// Then the box is retired: it lays nothing and asks nothing any more. One
/// question per renewal, no packet of its own; a holder without anything
/// answers `0x34` (§13.7). A device with siblings is never retired by a key
/// change one of them made (D-107): the application says `behind`, the box
/// lays nothing, asks again once its own collection round has ended (which
/// brings the key package, §14.7 Type 16), and is held until released.
///
/// **For 7 days after a takeover (§13.3.4 "At a rotation").** The recovering
/// device names the former fixed neighbours of the taken-over bundle first
/// among the holders of its own deposits ([BundleBox.alsoNamed]) — there the
/// previous device asks before its renewal.
///
/// Idle: nothing. A [BundleBox] sends only from an edge or a call.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:mycelium/card_address.dart' show CardAddress;
import 'package:mycelium/node.dart';
import 'package:mycelium/node_collect_edge.dart';
import 'package:mycelium/node_first_contact_box.dart';
import 'package:mycelium/node_post_box.dart';
import 'package:mycelium/pair.dart' show dayValue, utcDay;
import 'package:mycelium/post_box_deposit.dart' show Neighbour;
import 'package:mycelium/recovery_bundle_ask.dart';

export 'package:mycelium/recovery_bundle_ask.dart';

/// The recovery bundle of ONE identity, at the node of its mailbox
/// (`Mailbox.node`).
class BundleBox {
  final Node node;
  final BoxKeyFor keyFor;

  /// The log — decides nothing.
  final void Function(String)? report;

  /// The sealed bundle as of now, or `null`: nothing to lay.
  final Uint8List? Function() sealed;

  /// The clock — the UTC day of a value and the age of the last deposit.
  final DateTime Function() now;

  /// A deposit that at least one holder acknowledged: when, and with how many.
  final void Function(DateTime at, int holders)? onDeposited;

  /// What a search brought — sealed bundles, opened by the application.
  final void Function(List<Uint8List> found)? onFound;

  /// Before a renewal: what the question of [renewAsk] found, sealed, and
  /// whether the own collection round of that edge has ended. `retired`: the
  /// box lays nothing any more (§13.3.4). `behind` (D-107): asked again once
  /// that round has ended; still `behind` then, the box is [held]. `null`: no
  /// check (the box renews as before D-103).
  final BundleFinding Function(List<Uint8List> found, bool afterRound)?
      retiredBy;

  /// Holders named FIRST at a deposit, before the own fixed neighbours —
  /// the former fixed neighbours for 7 days after a takeover (§13.3.4).
  final List<CardAddress> Function()? alsoNamed;

  /// Set once [retiredBy] said so: nothing is laid or asked any more.
  bool retired = false;

  /// Set when [retiredBy] said `behind` after the own round (D-107): nothing
  /// is laid or asked until [release] — the application releases the box
  /// once the device's keys caught up.
  bool held = false;

  /// The device's keys caught up with its sibling's (§14.7 Type 16): the box
  /// renews again from its next edge.
  void release() => held = false;

  /// When the last deposit was acknowledged, `null`: none known.
  DateTime? lastDeposit;

  /// How many holders acknowledged it.
  int lastHolders;

  /// The recovery case (§13.0): look for the bundle at every edge, lay none.
  bool seeking = false;

  /// While seeking: read the bundle, do not delete it at its holder — a
  /// fresh install that has not decided yet may find a LIVING device's
  /// bundle (§13.0, D-40). `false` in the recovery case (E5-a: deleted on
  /// the receipt, a fresh one is laid after the takeover).
  bool readOnly = false;

  /// Diagnostics: deposits and searches this box started.
  int deposits = 0;
  int seeks = 0;

  bool _attached = false;
  bool _depositRuns = false;

  BundleBox(
    this.node, {
    required this.keyFor,
    required this.sealed,
    this.report,
    this.now = DateTime.now,
    this.onDeposited,
    this.onFound,
    this.retiredBy,
    this.alsoNamed,
    this.lastDeposit,
    this.lastHolders = 0,
  });

  Node get _node => node;

  /// From now on at every collection edge of the node. Once.
  void attach() {
    if (_attached) return;
    _attached = true;
    _node.addCollectEdge(_edge);
  }

  /// The edge stays registered at the node (no removal there); it does
  /// nothing any more. A deposit still running ends, but no longer reports
  /// to [onDeposited]: its owner detached the box because the identity left
  /// the process or stopped (S406).
  void detach() {
    _attached = false;
    _detaches++;
  }

  int _detaches = 0;

  /// Until when the last deposit lies with its holders, or `null`.
  DateTime? get validUntil => lastDeposit?.add(kBundleLife);

  void _edge(List<Neighbour>? only, Future<int>? round) {
    if (!_attached || retired || held) return;
    if (seeking) {
      unawaited(seek(withWhom: only));
    } else if (bundleRenewDue(lastDeposit, now())) {
      unawaited(_renew(round));
    }
  }

  bool _renewRuns = false;

  /// A renewal at an edge: first the question of [renewAsk], then the
  /// deposit — unless the device is retired by what came.
  Future<void> _renew(Future<int>? round) async {
    if (_renewRuns) return;
    _renewRuns = true;
    try {
      if (!await _mayLay(round)) return;
    } finally {
      _renewRuns = false;
    }
    if (!_attached || seeking) return;
    unawaited(deposit());
    // The post of this edge is fed after that bundle was built: once the
    // round has ended and brought pieces, one more is laid with them.
    unawaited(round?.then((pieces) {
      if (_attached && !seeking && !retired && pieces > 0) {
        unawaited(depositSoon());
      }
    }));
  }

  /// Reads the values since the own last deposit (they stay with their
  /// holders) and asks [retiredBy] — a second time after the own [round]
  /// when it says `behind` (D-107). `false`: retired, held, or detached
  /// meanwhile — nothing is laid. Does not throw.
  Future<bool> _mayLay(Future<int>? round) async {
    final check = retiredBy;
    final last = lastDeposit;
    if (check == null || last == null) return true;
    final ask = renewAsk(keyFor, last, now());
    if (ask.isEmpty) return true;
    final found = await _node.compartmentCollect(ask,
        withWhom: _node.collectNeighbours, keep: true);
    if (!_attached) return false;
    _say('recovery bundle: before the renewal ${ask.length} day value(s) '
        'read — ${found == null ? "not asked" : "${found.length} piece(s)"}');
    if (found == null || found.isEmpty) return true;
    var finding = _judged(check, found, false);
    if (finding == BundleFinding.behind) {
      // The pieces of the own round are fed synchronously; one turn of the
      // event loop lets what they started finish (a key package taken over).
      if (round == null) return false;
      await round;
      await Future<void>.delayed(Duration.zero);
      if (!_attached) return false;
      finding = _judged(check, found, true);
      if (finding == BundleFinding.behind) {
        held = true;
        _say('recovery bundle: a newer bundle continues these keys and the '
            'own round brought none of them — held, nothing laid (D-107)');
        return false;
      }
    }
    if (finding == BundleFinding.none) return true;
    retired = true;
    _say('recovery bundle: a newer bundle continues these keys — this device '
        'is retired, nothing laid (§13.3.4)');
    return false;
  }

  BundleFinding _judged(
      BundleFinding Function(List<Uint8List>, bool) check,
      List<Uint8List> found,
      bool afterRound) {
    try {
      return check(List.of(found), afterRound);
    } on Object catch (e) {
      _say('recovery bundle: the check before the renewal failed — $e');
      return BundleFinding.none;
    }
  }

  /// Lays the bundle under today's value (E1-b, E6-a). Returns how many
  /// holders acknowledged it; `0` also when nothing was laid (a deposit is
  /// running, the recovery case, retired, nothing to lay). Does not throw.
  Future<int> deposit() {
    if (_depositRuns || seeking || retired) return Future.value(0);
    final f = _deposit();
    _running = f.whenComplete(() => _running = null);
    return f;
  }

  Future<int> _deposit() async {
    final Uint8List? s;
    try {
      s = sealed();
    } on Object catch (e) {
      _say('recovery bundle: not built — $e');
      return 0;
    }
    if (s == null) return 0;
    _depositRuns = true;
    final detachesAtStart = _detaches;
    try {
      final at = now();
      final p = keyFor(utcDay(at));
      deposits++;
      final first = alsoNamed?.call() ?? const <CardAddress>[];
      final named = <CardAddress>[...first];
      for (final f in _node.neighbourhood.fixedNeighbours) {
        final c = f.asCardAddress;
        if (!named.any((n) => n.port == c.port && _sameIp(n.address, c.address))) {
          named.add(c);
        }
      }
      final r = await _node.depositNamed(s, dayValue(p.pk), named);
      _say('recovery bundle: ${s.length} B, ${named.length - first.length} '
          'own fixed neighbour(s)'
          '${first.isEmpty ? "" : " after ${first.length} former one(s)"} '
          'named — ${r.$1 ? "placed" : "NOT placed"}, '
          '${r.$2} holder(s) acknowledged');
      if (r.$2 > 0) {
        lastDeposit = at;
        lastHolders = r.$2;
        if (_detaches == detachesAtStart) onDeposited?.call(at, r.$2);
      }
      return r.$2;
    } finally {
      _depositRuns = false;
    }
  }

  /// A deposit NOW, outside the cadence — opening an enrolment window
  /// (§13.3.4, §14.6.1). If one is running, it may have been built before
  /// the change: exactly one more follows it, built then. Returns the
  /// receipts of the deposit that carries the change. Does not throw.
  Future<int> depositSoon() async {
    final running = _running;
    if (running == null) return deposit();
    _again ??= running.then((_) {
      _again = null;
      return deposit();
    });
    return _again!;
  }

  Future<int>? _running;
  Future<int>? _again;

  /// Asks for the bundle — [withWhom] (the holders a card names), else the
  /// holders a collection asks (own fixed neighbours first). Once every
  /// asked holder is done (§8.2: each is, after two quiet periods at the
  /// latest) everything found goes to [onFound] as ONE list — the newest of
  /// several copies wins over ALL holders (§13.3.2). Returns how many came;
  /// "none" concludes nothing (D-40). Does not throw.
  Future<int> seek({List<Neighbour>? withWhom}) async {
    seeks++;
    final to = withWhom ?? _node.collectNeighbours;
    // What a holder hands out after it was done for the edge (§8.2) comes
    // alone. A search of the recovery case whose case is settled meanwhile
    // ([seeking] went off: a bundle was taken over) takes none any more:
    // such a piece is not acknowledged and stays with its holder.
    var ended = false;
    final recovery = seeking;
    final found = await _node.compartmentCollect(bundleAsk(keyFor, now()),
        withWhom: to, keep: readOnly, onPiece: (p) {
      if (!ended) return true;
      if (recovery && !seeking) return false;
      onFound?.call([p]);
      return true;
    });
    ended = true;
    if (found != null && found.isNotEmpty) onFound?.call(List.of(found));
    _say('recovery bundle: looked for at ${to.length} holder(s) — '
        '${found == null ? "not asked" : "${found.length} piece(s)"}');
    return found?.length ?? 0;
  }

  void _say(String s) => report?.call(s);
}

bool _sameIp(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
