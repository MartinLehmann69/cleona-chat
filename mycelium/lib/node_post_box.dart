import 'dart:async';
import 'dart:typed_data';

import 'package:mycelium/post_box_deposit.dart'
    show Neighbour, Question, ownAsk;
import 'package:mycelium/post_box_proof.dart' show previousAsk;
import 'package:mycelium/post_box_holders.dart';
import 'package:mycelium/post_box_log.dart' show holdersNamed;
import 'package:mycelium/post_box_runs.dart'
    show holdersAnswered, neighbourKey;
import 'package:mycelium/node.dart';
import 'package:mycelium/node_collect_answered.dart';
import 'package:mycelium/node_collect_edge.dart';
import 'package:mycelium/node_collect_queue.dart';
import 'package:mycelium/node_enrolment.dart' show NodeEnrolment;
export 'package:mycelium/node_collect_queue.dart' show NodeCompartment;
export 'package:mycelium/node_deposit.dart';
import 'package:mycelium/node_first_contact_box.dart';
import 'package:mycelium/node_receipt.dart' show NodeReceipt;
import 'package:mycelium/own_line.dart' show ownLineAsk; // D-37, §14.7
import 'package:mycelium/identity.dart' show Identity;
import 'package:mycelium/parked.dart'; // D-40

/// The post box side of the node: collect what lies there for oneself —
/// since S391 (proposal M, §8.2) under day values instead of identifiers.
/// The sender side (step 4 of the ladder) stands in `node_deposit.dart`
/// (line budget, S407-VB20), exported from here.
///
/// Collector side: [collect] asks per identity under its own
/// day keys of today and the six days before (`ownAsk`,
/// `deriveDayKey(postBox, day)` from `pair.dart`).
///
/// Its own file for the line budget of `node.dart`; it gets by with the
/// public side of [Node].
///
/// ── NO CLOCK ────────────────────────────────────────────────────────
///
/// [collect] is ONE round of questions, not a service. Whoever calls it
/// decides when — at start, when the network changes, when the user opens
/// the app (§8.2); [collectFrom] is the edge "a new neighbour".
extension NodePostBox on Node {
  /// Whom a collection asks: the own fixed neighbours first — a sender leaves
  /// post there first (§8.2, `post_box_holders.dart`) — then
  /// [NodeCollectQueue.lastHeard].
  /// Behind the fixed neighbours: what an owner registered with
  /// [collectAlso] (§13.2.1: the former fixed neighbours after a recovery).
  List<Neighbour> get collectNeighbours => holdersJoin(
      holdersJoin([
        for (final f in neighbourhood.fixedNeighbours) (f.address, f.port)
      ], [
        for (final f in (_collectAlso[this] ?? const {}).values) ...f()
      ]),
      lastHeard);

  /// Registers [also] for [owner] (`null` removes it); the owner decides
  /// when it is empty — no clock here.
  void collectAlso(Object owner, List<Neighbour> Function()? also) {
    final m = _collectAlso[this] ??= {};
    also == null ? m.remove(owner) : m[owner] = also;
  }

  /// An edge of §8.2 (start, network change, the application opened, an
  /// enrolment handover): asks the own neighbours for everything that lies
  /// for oneself under the own day values, and feeds in every piece as if
  /// it had just arrived.
  ///
  /// Every conversation ends by itself (§8.2: after one request for what is
  /// missing at the latest); at a holder where one of an earlier round still
  /// stands, only values not standing there yet are put, behind it.
  ///
  /// [von] is the HOLDER here, not the sender — that is not
  /// carelessness but the truth: where the piece came from is the
  /// neighbour. Whoever needs the sender unseals; it stands in the seal.
  ///
  /// Returns how many pieces were collected, once every holder asked is
  /// done — answered, unreachable, or silent after one request for what is
  /// missing. That future waits alone: every piece is fed when it
  /// arrives. `0` is not an error — usually nothing is lying there.
  /// [withWhom] asks EXACTLY these holders instead of the found neighbours.
  /// Needed from two sides: by a caller who has remembered a holder,
  /// and by a probe that must not depend on
  /// whom the call has just found in the network of the test machine.
  ///
  /// PER IDENTITY under ITS day values. Until S385 the node asked only under
  /// the identifier of the first, and what lay for identity 2..N nobody ever
  /// collected (S385-WIDERLEGUNG W1.a.1). The questions to one holder
  /// follow one another (`post_box_collect.dart`).
  Future<int> collect({List<Neighbour>? withWhom}) =>
      _round(withWhom ?? collectNeighbours, edge: true);

  /// Asks [holders] without an edge: nothing open is dropped, the questions
  /// wait their turn behind it. The edge "a new neighbour" asks that
  /// neighbour alone this way (§8.2, §11.8; G4: a neighbour that joined
  /// while a query ran must not remain without question, §22.7.1), and a
  /// newly registered identity asks the holders of a collection.
  /// [only]: the questions of this identity alone (the newly registered one).
  Future<int> collectFrom(List<Neighbour> holders, {Identity? only}) =>
      _round(holders, edge: false, only: only);

  Future<int> _round(List<Neighbour> neighbours,
      {required bool edge, Identity? only}) {
    if (neighbours.isEmpty) {
      report('collect: no neighbour known where something could be resting');
      return Future.value(0);
    }
    if (edge) {
      postBoxDeposit.collectEdge(); // §11.8: one use per holder and edge
      receiptEdge(); // §9.2: a copy from now on is answered again
    }
    // A copy: an identity that is deregistered meanwhile must not throw
    // the loop out of step. D-40: a held identity searches only, no own post.
    final asking = [
      for (final i in List.of(identities))
        if (!postHeld(i) && (only == null || identical(i, only))) i
    ];
    // §8.2 "follow one another": a holder at which a question of an earlier
    // round still stands (it ends after two quiet periods without an answer;
    // no timer runs while a transmission of that holder is arriving) gets
    // only the values not standing there yet, behind that question.
    final standing = edge
        ? [
            for (final n in holdersJoin(neighbours, [
              for (final i in asking) ...invitationHolders(i, const []),
            ]))
              if (postBoxDeposit.collectBusy(n)) n
          ]
        : const <Neighbour>[];
    final stays = {for (final n in standing) neighbourKey(n)};
    final started = DateTime.now();
    final questions = <Future<int?>>[];
    // §8.2 "After more than 7 days": the identities whose question under
    // their OWN day values a holder answered in this round.
    final answered = <Identity>{};
    var behind = 0;
    for (final i in asking) {
      parkedOf(i)?.sweep(); // D-40: expired parked cells are counted here
      final own = ownAsk(i.postBox, postBoxDeposit.now());
      // Proposal E: the invitation post boxes under their own questions.
      for (final (ask, from) in [
        (own, neighbours),
        if (previousAsk(i.postBox, postBoxDeposit.now()) case final q
            when q.isNotEmpty) (q, neighbours), // E-A6, §8.2
        for (final q in invitationQuestions(i))
          (q, edge ? invitationHolders(i, neighbours) : neighbours),
        for (final q in ownLineAsk(i, postBoxDeposit.now())) (q, neighbours),
      ]) {
        final mark = identical(ask, own) ? answered : null;
        final free = [
          for (final n in from)
            if (!stays.contains(neighbourKey(n))) n
        ];
        if (free.isNotEmpty) questions.add(_collectFor(ask, free, i, mark));
        // What this holder was not asked yet waits its turn behind the open
        // question; the same values are not put a second time.
        for (final n in from) {
          if (!stays.contains(neighbourKey(n))) continue;
          final fresh = postBoxDeposit.collectUnasked(n, ask);
          if (fresh.isEmpty) continue;
          behind += fresh.length;
          questions.add(_collectFor(fresh, [n], i, mark));
        }
      }
    }
    if (behind > 0) {
      report('collect: $behind new value(s) wait behind the open question at '
          '${holdersNamed(standing)}');
    }
    if (questions.isEmpty && stays.isNotEmpty) {
      report('collect: every holder still has these values open — '
          'none is asked a second time');
      fireCollectEdge(); // the edge itself happened; there is no round
      return Future.value(0);
    }
    final own = neighbours.where((n) => !stays.contains(neighbourKey(n)));
    report('collect: round asks ${own.length} neighbour(s): '
        '${holdersNamed(own.toList())}');
    final round = Future.wait(questions).then((counts) {
      final number = counts.fold(0, (s, n) => s + (n ?? 0));
      final completed = !counts.contains(null);
      report('collect: round ended after '
          '${DateTime.now().difference(started).inMilliseconds} ms — $number '
          'piece(s)${completed ? "" : ", a question failed"}');
      // Every holder asked in this round is done — answered, unreachable or
      // silent after one request — and every piece is fed (`feed` is
      // synchronous): whatever announcements were lying there are read.
      // Only NOW may the own rotation announce — at the first round that
      // ENDS, whichever began first.
      final callback = _onFirst[this];
      if (completed && callback != null) {
        _onFirst[this] = null;
        callback();
      }
      // §8.2: the collection of these identities ended with an answer from
      // at least one holder (`node_collect_answered.dart`).
      answered.forEach(fireCollectionAnswered);
      return number;
    });
    // Whoever else asks at this moment (§9.4 lane 3, the bundle search, the
    // enrolment) does so now, behind the own questions at each holder — it
    // does not wait for a holder to answer them. What must follow the post
    // of this edge gets the round's end handed along.
    fireCollectEdge(edge ? null : neighbours, round);
    return round;
  }

  /// Cold-start callback — the mycelium replacement for the report „first
  /// collection pass" to the rotation gate of the app (`cleona_service.dart`),
  /// whose only reporter drops away with the old seam. Fires ONCE, at the
  /// first round with at least one neighbour that ENDS: every holder it
  /// asked is done — answered (0 pieces and „nothing there" count),
  /// unreachable, or silent after one request for what is missing (§8.2 —
  /// every round ends). An earlier round still running does not keep the
  /// gate shut for a later one that ends first. It
  /// waits alone and holds nothing up. NOT on „no neighbour" — for that the
  /// app has its fallback hour, and otherwise the gate would open at cold
  /// start almost always after milliseconds, without anyone having been
  /// asked (S385-E1-WIDERLEGUNG 6). Not on a failed request.
  set onFirstCollection(void Function()? f) => _onFirst[this] = f;

  /// Does not throw. `null` means: the request failed, not finished.
  /// [ask] carries the pairs: the holder only hands out against evidence
  /// signed by the day key (S391) or the invitation key (proposal E).
  /// [answered]: [i] is added once a holder answered this question to the end.
  Future<int?> _collectFor(List<Question> ask, List<Neighbour> neighbours,
      Identity i, [Set<Identity>? answered]) async {
    // DOES NOT THROW. This method is called from edges whose result
    // nobody awaits (`unawaited`); a throw from here would be an
    // unhandled asynchronous error and would end the process. The
    // promise therefore belongs here and not in every caller — a
    // protective coat that everyone has to put on themselves will at some point be
    // forgotten. Nothing is swallowed: the reason goes into the report.
    try {
      // Deliberately via the same entrance as a packet from the wire: a
      // collected piece IS a packet, it just took a detour — flagged as
      // collected (proposal E), and fed the moment it arrives (§8.2).
      final pieces = await postBoxDeposit.collect(
          ask: ask,
          withWhom: neighbours,
          onPiece: (piece, holder) => _fedFor(i, piece, holder));
      if (answered != null && holdersAnswered(pieces) > 0) answered.add(i);
      return pieces.length;
    } on Object catch (e) {
      report('collect failed: $e');
      return null;
    }
  }

  /// The piece answered [i]'s question: what none of the identities opens
  /// may be parked for [i] (D-40, `parked.dart`). Does not throw: it runs
  /// inside the collector's takeover, which acknowledges the piece next —
  /// `false` (it could not be fed) leaves it with its holder.
  bool _fedFor(Identity i, Uint8List piece, Neighbour holder) {
    collectingFor = i;
    try {
      feedCollected([piece], holder);
      return true;
    } on Object catch (e) {
      report('collect: a collected piece could not be fed: $e');
      return false;
    } finally {
      collectingFor = null;
    }
  }
}

// [NodeCompartment] and [NodeCollectQueue.lastHeard] stand in
// `node_collect_queue.dart` (line budget, S398).

/// The not yet fired cold-start callback per node — see
/// [NodePostBox.onFirstCollection]. Next to the node instead of in it:
/// `node.dart` is at the line budget.
final Expando<void Function()> _onFirst =
    Expando<void Function()>('onFirstFetch');

/// What an owner registered with [NodePostBox.collectAlso], per node.
final _collectAlso = Expando<Map<Object, List<Neighbour> Function()>>();
