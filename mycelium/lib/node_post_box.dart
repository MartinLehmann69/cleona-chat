import 'dart:async';
import 'dart:typed_data';

import 'package:mycelium/card_address.dart' show CardAddress;
import 'package:mycelium/post_box_deposit.dart'
    show Neighbour, Question, ownAsk;
import 'package:mycelium/post_box_proof.dart' show previousAsk;
import 'package:mycelium/post_box_holders.dart';
import 'package:mycelium/post_box_log.dart' show holdersNamed;
import 'package:mycelium/post_box_disk.dart' show kValueLength;
import 'package:mycelium/post_box_runs.dart'
    show holdersAnswered, neighbourKey;
import 'package:mycelium/node.dart';
import 'package:mycelium/node_collect_answered.dart';
import 'package:mycelium/node_collect_edge.dart';
import 'package:mycelium/node_collect_queue.dart';
import 'package:mycelium/node_enrolment.dart' show NodeEnrolment;
export 'package:mycelium/node_collect_queue.dart' show NodeCompartment;
import 'package:mycelium/node_first_contact_box.dart';
import 'package:mycelium/own_line.dart' show ownLineAsk; // D-37, §14.7
import 'package:mycelium/identity.dart' show Identity;
import 'package:mycelium/parked.dart'; // D-40
import 'package:mycelium/pair.dart' show dayValue, utcDay;
import 'package:mycelium/envelope.dart' show Address;

/// The day pubkey (32 B) of [contact] on UTC day [day], or `null`
/// if none is known. Supplied by the mailbox (M1: contacts get
/// the public day keys sealed, proposal M 5.4).
typedef DayPkFrom = Uint8List? Function(Address contact, int day);

/// The contact for a 32-B identifier, or `null`. Needed because step 4
/// of the ladder only names the identifier (`ladder.dart`, `AblageSenden`), but the
/// day pubkey hangs on the contact.
typedef ContactFrom = Address? Function(Uint8List identifier);

/// `named`: the fixed neighbours [contact] last told this node (§9.2); `at`:
/// its own addresses, only to leave them out as holders (OP-19 part B).
typedef NeighboursFrom = ({List<CardAddress> named, List<CardAddress> at})
    Function(Address contact);

/// The post box side of the node: deposit with neighbours, and
/// collect what lies there for oneself — since S391 (proposal M, §8.2)
/// under day values instead of identifiers.
///
/// ── INTERFACE (M3) ───────────────────────────────────────────────
///
/// Sender side, called by step 4 of the ladder:
/// ```
/// Future<(bool done, int acknowledged)>? depositFor(Address recipient, Uint8List content)
/// void stepFourForIdentifier(Uint8List identifier, Uint8List content)
/// ```
/// Deposited under `dayValue(dayPkFrom(recipient, utcDay(now)))`.
/// Without a known day pubkey step 4 is dropped for this sending —
/// `null` or no deposit, and [Node.report] says so.
/// Wired are [dayPkFrom] and [contactFrom] (integrator/M1).
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
  /// The own holders of a deposit: [n] NODES (§8.2: three addressed, two
  /// suffice; B1) in the order of `ownHoldersRanked` (OP-19 part A, S398),
  /// none on the node of an address in [not] — the recipient's (part B).
  List<Neighbour> ownHolders({Iterable<Neighbour> not = const [], int n = 3}) =>
      readiness.different([
        for (final x in ownHoldersRanked(neighbourhood.all,
            live: linkLive, answered: readiness.answeredRecently)) // S398 L2-1
          (address: x.address, port: x.port)
      ], n, not: not);
  List<Neighbour> get depositNeighbours => ownHolders();

  /// Whom a collection asks: the own fixed neighbours first — a sender leaves
  /// post there first (§8.2, `post_box_holders.dart`) — then
  /// [NodeCollectQueue.lastHeard].
  List<Neighbour> get collectNeighbours => holdersJoin(
      [for (final f in neighbourhood.fixedNeighbours) (f.address, f.port)],
      lastHeard);

  /// Where the fixed neighbours of a contact come from — see [NeighboursFrom].
  set neighboursFrom(NeighboursFrom? f) => _neighboursFrom[this] = f;

  /// Where the day pubkey of a contact comes from — see [DayPkFrom].
  set dayPkFrom(DayPkFrom? f) => _dayPkFrom[this] = f;

  /// Where the contact for an identifier comes from — see [ContactFrom].
  set contactFrom(ContactFrom? f) => _contactFrom[this] = f;

  /// The value under which deposits for [recipient] are made TODAY (UTC), or
  /// `null` without a known day pubkey.
  Uint8List? depositValueFor(Address recipient) {
    final pk = _dayPkFrom[this]
        ?.call(recipient, utcDay(postBoxDeposit.now()));
    return pk == null ? null : dayValue(pk);
  }

  /// Step 4 for [recipient]: deposits [content] under his today's
  /// day value with the own neighbours (three addressed, two
  /// receipts suffice). `null`: no day pubkey known — step 4
  /// is dropped for this sending, reported. Does not throw.
  Future<(bool done, int acknowledged)>? depositFor(
      Address recipient, Uint8List content, {bool Function()? ended}) {
    final value = depositValueFor(recipient);
    if (value == null) {
      report('Post box step dropped: no daily pubkey for '
          '${_short(recipient.identifier)}');
      return null;
    }
    // §8.2 (proposal 6.4): first the recipient's fixed neighbours, then ours
    // — never the recipient's own device (OP-19 part B).
    final f = _neighboursFrom[this]?.call(recipient);
    return depositNamed(content, value, f?.named ?? const [],
        at: f?.at ?? const [], ended: ended);
  }

  /// [depositFor] for step 4 of the ladder by the identifier. A line join's
  /// request never comes here: it carries its invitation value
  /// (`node_step_four.dart`, OP-20). Returns whether the deposit was placed
  /// (§8.2: the second `0x31`) — the sender remembers it per message
  /// (`mailbox_outbound.dart`, §9.3); `null` if nothing was left.
  Future<bool>? stepFourForIdentifier(Uint8List identifier, Uint8List content,
      {bool Function()? ended}) {
    final to = _contactFrom[this]?.call(identifier);
    if (to == null) {
      report('Post box step dropped: no contact for ${_short(identifier)}');
      return null;
    }
    return depositFor(to, content, ended: ended)?.then((r) => r.$1);
  }

  /// Deposits [content] under the 16-B value [underValue] (day value, manifest
  /// compartment, recovery bundle) with the own neighbours; it ends on
  /// events (§8.2). Does not throw: another length ends `(false, 0)`,
  /// reported. [ended]: see [PostBoxDeposit.deposit].
  Future<(bool done, int acknowledged)> deposit(Uint8List content,
      Uint8List underValue,
      {List<Neighbour>? withWhom, bool Function()? ended}) {
    if (underValue.length != kValueLength) {
      report('deposit: ${underValue.length} B is not a daily value '
          '($kValueLength B) — not deposited');
      return Future.value((false, 0));
    }
    // S394 diagnosis: the deposit had no line of its own — whether it was
    // placed, and with how many receipts, could not be read.
    final to = withWhom ?? depositNeighbours;
    report('deposit: ${content.length} B under ${_short(underValue)} '
        'to ${to.length} neighbour(s): ${holdersNamed(to)}'); // O2
    return postBoxDeposit
        .deposit(
            content: content, underValue: underValue, withWhom: to, ended: ended)
        .then((r) {
      report('deposit under ${_short(underValue)}: '
          '${r.$1 ? "placed" : "NOT placed"}, ${r.$2} receipt(s)');
      return r;
    });
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
    if (edge) postBoxDeposit.collectEdge(); // §11.8: one use per holder and edge
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
    report('collect: round asks ${own.length} neighbour(s)');
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

/// The callbacks of the sender side per node — see
/// [NodePostBox.dayPkFrom] and [NodePostBox.contactFrom].
final Expando<DayPkFrom> _dayPkFrom = Expando<DayPkFrom>('dayPkOf');
final Expando<ContactFrom> _contactFrom = Expando<ContactFrom>('contactOf');
final Expando<NeighboursFrom> _neighboursFrom =
    Expando<NeighboursFrom>('neighboursOf');

String _short(Uint8List b) => b
    .sublist(0, 4)
    .map((x) => x.toRadixString(16).padLeft(2, '0'))
    .join();
