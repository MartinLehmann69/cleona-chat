import 'dart:async';
import 'dart:typed_data';

import 'package:mycelium/card_address.dart' show CardAddress;
import 'package:mycelium/post_box_deposit.dart'
    show Neighbour, ownAsk, compartmentQuestion;
import 'package:mycelium/post_box_holders.dart';
import 'package:mycelium/forward_family.dart' show isSelf;
import 'package:mycelium/neighbourhood.dart' show Neighbourhood;
import 'package:mycelium/post_box_disk.dart' show kValueLength;
import 'package:mycelium/node.dart';
import 'package:mycelium/pair.dart' show dayValue, utcDay;
import 'package:mycelium/envelope.dart' show Address, PostBox;

/// The day pubkey (32 B) of [contact] on UTC day [day], or `null`
/// if none is known. Supplied by the mailbox (M1: contacts get
/// the public day keys sealed, proposal M 5.4).
typedef DayPkFrom = Uint8List? Function(Address contact, int day);

/// The contact for a 32-B identifier, or `null`. Needed because step 4
/// of the ladder only names the identifier (`ladder.dart`, `AblageSenden`), but the
/// day pubkey hangs on the contact.
typedef ContactFrom = Address? Function(Uint8List identifier);

/// The fixed neighbours [contact] last told this node (§9.2), or empty.
typedef NeighboursFrom = List<CardAddress> Function(Address contact);

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
/// Its own file for the same reason as `node_invitation.dart` — the
/// line budget of `node.dart` knows no exception. The cut follows
/// the question who currently HOLDS the message: here a neighbour, over there
/// the own machine.
///
/// It gets by with the public side of [Node]:
/// [Node.postBoxDeposit], [Node.depositNeighbours],
/// [Node.identities], [Node.feed] and [Node.report].
///
/// ── NO CLOCK ────────────────────────────────────────────────────────
///
/// [collect] is ONE request, not a service. Whoever calls it decides
/// when — at start, on a new neighbour, when the user opens the app.
/// A permanent clock was the error of the old layer, and
/// `post_box_deposit.dart` says the same in its header.
extension NodePostBox on Node {
  /// The holders with whom depositing and collecting happens: the three last
  /// heard NODES (ch8.2: three addressed, two suffice; B1, S388).
  /// Lives here and not in `node.dart`: it is the holder list of the
  /// deposit, and over there the line budget breaks.
  List<Neighbour> get depositNeighbours =>
      readiness.different(foundNeighbours, 3);

  /// Whom a collection asks: the own fixed neighbours first — a sender
  /// leaves post there first (§8.2, `post_box_holders.dart`) — then
  /// [depositNeighbours].
  List<Neighbour> get collectNeighbours => holdersJoin(
      [for (final f in neighbourhood.fixedNeighbours) (f.address, f.port)],
      depositNeighbours);

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
      Address recipient, Uint8List content) {
    final value = depositValueFor(recipient);
    if (value == null) {
      report('Post box step dropped: no daily pubkey for '
          '${_short(recipient.identifier)}');
      return null;
    }
    // §8.2 (proposal 6.4): first the recipient's fixed neighbours, then ours.
    final named = _neighboursFrom[this]?.call(recipient) ?? const [];
    return deposit(content, value,
        withWhom: depositHolders(named, depositNeighbours,
            (a) =>
                speaks(a.$1) &&
                Neighbourhood.possible(a.$1, a.$2) &&
                !isSelf(this, a.$1, a.$2)));
  }

  /// [depositFor] for step 4 of the ladder, which names only the identifier.
  void stepFourForIdentifier(Uint8List identifier, Uint8List content) {
    final to = _contactFrom[this]?.call(identifier);
    if (to == null) {
      report('Post box step dropped: no contact for ${_short(identifier)}');
      return;
    }
    final f = depositFor(to, content);
    if (f != null) unawaited(f);
  }

  /// Deposits [content] under the 16-B value [underValue] (day value or
  /// manifest compartment) with the own neighbours. Does not throw: a value of another
  /// length ends with `(false, 0)` and a report.
  Future<(bool done, int acknowledged)> deposit(
      Uint8List content, Uint8List underValue, {List<Neighbour>? withWhom}) {
    if (underValue.length != kValueLength) {
      report('deposit: ${underValue.length} B is not a daily value '
          '($kValueLength B) — not deposited');
      return Future.value((false, 0));
    }
    // S394 diagnosis: the deposit had no line of its own — whether it was
    // placed, and with how many receipts, could not be read.
    final to = withWhom ?? depositNeighbours;
    report('deposit: ${content.length} B under ${_short(underValue)} '
        'to ${to.length} neighbour(s)');
    return postBoxDeposit
        .deposit(content: content, underValue: underValue, withWhom: to)
        .then((r) {
      report('deposit under ${_short(underValue)}: '
          '${r.$1 ? "placed" : "NOT placed"}, ${r.$2} receipt(s)');
      return r;
    });
  }

  /// Asks the own neighbours for everything that lies for oneself under the own
  /// day values, and feeds in every piece as if it had just
  /// arrived.
  ///
  /// [von] is the HOLDER here, not the sender — that is not
  /// carelessness but the truth: where the piece came from is the
  /// neighbour. Whoever needs the sender unseals; it stands in the seal.
  ///
  /// Returns how many pieces were collected. `0` is not an error —
  /// usually nothing is lying there.
  /// [withWhom] asks EXACTLY these holders instead of the found neighbours.
  /// Needed from two sides: by a caller who has remembered a holder,
  /// and by a probe that must not depend on
  /// whom the call has just found in the network of the test machine.
  ///
  /// PER IDENTITY under ITS day values, one after the other — the deposit handles
  /// one collection at a time. Until S385 the node asked only under the
  /// identifier of the first, and what lay for identity 2..N nobody ever
  /// collected (S385-WIDERLEGUNG W1.a.1). It remains ONE request per edge,
  /// only it carries N packets per holder.
  Future<int> collect({List<Neighbour>? withWhom}) async {
    // The edge „new neighbour" fires PER NEIGHBOUR. With the second one,
    // otherwise, a second request would run into a running first one — the deposit then
    // throws, and the throw would come out of an `unawaited`, i.e. from
    // a place where nobody catches it. Measured on 14.09.2026:
    // exactly so the test run died. The second request would be
    // superfluous anyway; the first already asks all known neighbours.
    // The flag applies to the whole pass over all identities:
    // between two identifiers the deposit is briefly free.
    if (_fetchesCurrently[this] == true) {
      // If the own pass is still waiting in the queue (behind the
      // manifest compartment), it TAKES OVER the holders remembered here at its
      // start, united with its own ([_pass]) — no second request
      // (work rule 5), but also no lost holder. Until the
      // S388-INTEGRATION the request returned here without remembering; a
      // [withWhom] that was not among the found neighbours stayed
      // unasked (`smoke_update_manifest_compartment` (9c) red).
      //
      // G4 (S387): the swallowed request is made up ONCE at the COMPLETION of the running
      // one, no matter how many were swallowed. Otherwise a
      // neighbour that joined during the 2 s of a running query remained without
      // question and thus without evidence (§22.7.1). The edge is the completion,
      // not a timer.
      //
      // Made up at the holders that the SWALLOWED request meant
      // — its [withWhom], otherwise the found neighbours AT THE MOMENT OF
      // SWALLOWING —, not at those last heard at completion. Until
      // S388 the second reading: since ES-3 every answer of the running
      // query refreshes its holders; they were thus younger than the new
      // neighbour, and the make-up asked them again. The new one stayed
      // unasked, and every further swallowed request chained on the same
      // round (smoke_host (b) red, `S388-BAU-FUND` "regression").
      final pending = _again[this] ??= [];
      for (final n in withWhom ?? collectNeighbours) {
        if (!pending.any((x) => x.$1.address == n.$1.address && x.$2 == n.$2)) {
          pending.add(n);
        }
      }
      report('collect: already running, will be repeated once after completion');
      return 0;
    }
    if ((withWhom ?? collectNeighbours).isEmpty) {
      report('collect: no neighbour known where something could be resting');
      return 0;
    }
    // S388 (§5.6 of the merge): a FOREIGN collection — the
    // manifest compartment ([fachAbholen]) — occupies the same deposit. Until S388 here came
    // `briefkastenAblage.abholenLaeuft` → „will be made up" → `return`,
    // and NOTHING was made up: `_again` applied only to the own
    // pass. Measured (`smoke_update_manifest_compartment` (9a)): the
    // group packet never arrived. Now the request waits in the queue.
    _fetchesCurrently[this] = true;
    return _sequential(() => _pass(withWhom));
  }

  Future<int> _pass(List<Neighbour>? withWhom) async {
    final neighbours = [...withWhom ?? collectNeighbours];
    // What was swallowed WHILE this pass waited in the queue,
    // it asks along — the own ones first ([_abholenFuer] names the first as
    // origin). While it runs, [_again] collects anew for the
    // make-up in the `finally`.
    final remembered = _again[this];
    _again[this] = null;
    for (final n in remembered ?? const <Neighbour>[]) {
      if (!neighbours.any((x) => x.$1.address == n.$1.address && x.$2 == n.$2)) {
        neighbours.add(n);
      }
    }
    var number = 0;
    var completed = neighbours.isNotEmpty;
    // S394 diagnosis: a pass that waits on silent holders keeps every later
    // edge queued ("already running") — its duration must be readable.
    final started = DateTime.now();
    report('collect: pass starts with ${neighbours.length} neighbour(s)');
    try {
      // A copy: an identity that is deregistered meanwhile
      // must not throw the loop out of step.
      for (final i in neighbours.isEmpty ? const [] : List.of(identities)) {
        final n = await _collectFor(i.postBox, neighbours);
        if (n == null) completed = false;
        number += n ?? 0;
      }
    } finally {
      _fetchesCurrently[this] = null;
      final pending = _again[this];
      if (pending != null) {
        _again[this] = null;
        unawaited(collect(withWhom: pending));
      }
    }
    if (number > 0) report('collect: $number piece(s) from the post box');
    report('collect: pass ended after '
        '${DateTime.now().difference(started).inMilliseconds} ms — $number '
        'piece(s)${completed ? "" : ", not every holder answered"}');
    // The pieces are already fed in here (`feed` is synchronous):
    // whatever announcements were lying there are read. Only NOW may the own
    // rotation announce.
    final callback = _onFirst[this];
    if (completed && callback != null) {
      _onFirst[this] = null;
      callback();
    }
    return number;
  }

  /// Cold-start callback — the mycelium replacement for the report „first
  /// collection pass" to the rotation gate of the app (`cleona_service.dart`),
  /// whose only reporter drops away with the old seam. Fires ONCE, after the
  /// first COMPLETED collection attempt with at least one neighbour
  /// (0 pieces, „nothing there" and deadline expiry count). NOT on „no
  /// neighbour" — for that the app has its fallback hour, and otherwise the
  /// gate would open at cold start almost always after milliseconds, without anyone
  /// having been asked (S385-E1-WIDERLEGUNG 6). Not on a skipped
  /// and not on a failed request.
  set onFirstCollection(void Function()? f) => _onFirst[this] = f;

  /// Does not throw. `null` means: the request failed, not finished.
  /// [me] instead of a value: the holder only hands out against evidence
  /// signed by the day key of the identity (S391).
  Future<int?> _collectFor(PostBox me, List<Neighbour> neighbours) async {
    // DOES NOT THROW. This method is called from edges whose result
    // nobody awaits (`unawaited`); a throw from here would be an
    // unhandled asynchronous error and would end the process. The
    // promise therefore belongs here and not in every caller — a
    // protective coat that everyone has to put on themselves will at some point be
    // forgotten. Nothing is swallowed: the reason goes into the report.
    List<Uint8List> pieces;
    try {
      pieces = await postBoxDeposit.collect(
        ask: ownAsk(me, postBoxDeposit.now()),
        withWhom: neighbours,
      );
    } on Object catch (e) {
      report('collect failed: $e');
      return null;
    }
    for (final s in pieces) {
      // Deliberately via the same entrance as a packet from the wire: a
      // collected piece IS a packet, it just took a detour.
      // Two entrances for the same thing would be two places where
      // a new kind can be forgotten.
      feed(s, neighbours.first.$1, neighbours.first.$2,
          withoutReturnRoute: true);
    }
    return pieces.length;
  }
}

/// The ONE queue of collections per node (S388): the deposit handles one
/// collection at a time, and both [NodePostBox.collect] and
/// [NodePostBox.compartmentCollect] queue up here. The end of the
/// previous one is the edge for the next — no timer.
final Expando<Future<void>> _row = Expando<Future<void>>('abholReihe');

extension _Row on Node {
  /// If the queue is free, [task] starts IMMEDIATELY (synchronously up to its
  /// first `await`) — as before S388: whoever calls `collect()` finds the
  /// deposit occupied afterwards. Measured when the queue always started first via
  /// `then`: `smoke_readiness` G4 „precondition: the hanging
  /// query really runs" failed.
  Future<T> _sequential<T>(Future<T> Function() task) {
    final before = _row[this];
    final done = Completer<void>();
    _row[this] = done.future;
    Future<T> run() => task().whenComplete(() {
          if (identical(_row[this], done.future)) _row[this] = null;
          done.complete();
        });
    return before == null ? run() : before.then((_) => run());
  }
}

/// The collection under a FOREIGN, public post box.
extension NodeCompartment on Node {
  /// Collects what lies under the value [compartment] (the manifest compartment, §26.5.4,
  /// without proof), in the same
  /// queue as [NodePostBox.collect] — if one is running there right now, it is
  /// asked afterwards instead of discarded. `null`: not asked (no neighbour)
  /// or failed; then nothing was deleted either. Does not throw.
  Future<List<Uint8List>?> compartmentCollect(Uint8List compartment) async {
    if (depositNeighbours.isEmpty) return null;
    return _sequential(() async {
      final neighbours = depositNeighbours;
      if (neighbours.isEmpty) return null;
      try {
        return await postBoxDeposit.collect(
            ask: [compartmentQuestion(compartment)], withWhom: neighbours);
      } on Object catch (e) {
        report('Compartment: collect failed: $e');
        return null;
      }
    });
  }
}

/// Whether a node is currently querying through its identities — see [collect].
/// Next to the node instead of in it: `node.dart` is at the line budget.
final Expando<bool> _fetchesCurrently = Expando<bool>('fetchingNow');

/// With whom the make-up happens if requests were swallowed during the running pass
/// — the union of their holders, see
/// [NodePostBox.collect] (G4). `null`: nothing swallowed.
final Expando<List<Neighbour>> _again = Expando<List<Neighbour>>('nochmal');

/// The not yet fired cold-start callback per node — see
/// [NodePostBox.onFirstCollection]. Next to the node, for the same
/// reason as [_fetchesCurrently].
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
