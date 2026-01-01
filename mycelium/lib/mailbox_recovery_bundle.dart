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
/// Idle: nothing. A [BundleBox] sends only from an edge or a call.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/card_address.dart' show CardAddress;
import 'package:mycelium/node.dart';
import 'package:mycelium/node_collect_edge.dart';
import 'package:mycelium/node_first_contact_box.dart';
import 'package:mycelium/node_post_box.dart';
import 'package:mycelium/pair.dart' show dayValue, utcDay;
import 'package:mycelium/post_box_deposit.dart'
    show DayPair, Neighbour, Question, kAtMostAge, kAtMostValues;

/// How long a bundle lies with its holders: the retention of every post-box
/// entry (§8.2, D-6) — nothing longer, a holder cannot tell a bundle apart.
const Duration kBundleLife = kAtMostAge;

/// Renewed at an edge from this age of the last deposit on (E2-a): a device
/// with an edge at least every four days keeps its bundle alive.
const Duration kBundleRenewAfter = Duration(days: 3);

/// The box key pair of UTC day `d` — from the application (E3-a).
typedef BoxKeyFor = DayPair Function(int day);

/// Is a renewal due at [now]? Never before a first deposit took place is it
/// NOT due; a clock set back (last after now) makes it not due.
bool bundleRenewDue(DateTime? last, DateTime now) =>
    last == null || now.difference(last) >= kBundleRenewAfter;

/// The ONE question of a search: the box values of today and the six days
/// before, each with its pair (a holder hands out only against the proof).
List<Question> bundleAsk(BoxKeyFor keyFor, DateTime now) {
  final today = utcDay(now);
  return [
    for (var d = 0; d < kAtMostValues; d++)
      if (keyFor(today - d) case final p) (value: dayValue(p.pk), pair: p),
  ];
}

/// The holders a card names: its own addresses and its neighbour.
List<Neighbour> cardHolders(List<CardAddress> own, CardAddress? neighbour) => [
      for (final c in [...own, if (neighbour != null) neighbour])
        (InternetAddress.fromRawAddress(Uint8List.fromList(c.address)), c.port),
    ];

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
    if (!_attached) return;
    if (seeking) {
      unawaited(seek(withWhom: only));
    } else if (bundleRenewDue(lastDeposit, now())) {
      unawaited(deposit());
      // The post of this edge is fed after that bundle was built: once the
      // round has ended and brought pieces, one more is laid with them.
      unawaited(round?.then((pieces) {
        if (_attached && !seeking && pieces > 0) unawaited(depositSoon());
      }));
    }
  }

  /// Lays the bundle under today's value (E1-b, E6-a). Returns how many
  /// holders acknowledged it; `0` also when nothing was laid (a deposit is
  /// running, the recovery case, nothing to lay). Does not throw.
  Future<int> deposit() {
    if (_depositRuns || seeking) return Future.value(0);
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
      final named = [
        for (final f in _node.neighbourhood.fixedNeighbours) f.asCardAddress
      ];
      final r = await _node.depositNamed(s, dayValue(p.pk), named);
      _say('recovery bundle: ${s.length} B, ${named.length} own fixed '
          'neighbour(s) named — ${r.$1 ? "placed" : "NOT placed"}, '
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
