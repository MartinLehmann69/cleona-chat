import 'dart:convert';
import 'dart:typed_data';

import 'package:mycelium/address_class.dart' show routesToContact;
import 'package:mycelium/card_address.dart' show CardAddress, routesEmpty;
import 'package:mycelium/ladder.dart' show LadderStep, Shipment;
import 'package:mycelium/node_call.dart';
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/mailbox_group_pair.dart' show MailboxGroupPair;
import 'package:mycelium/message.dart' show Outbound, DeliveryState;
import 'package:mycelium/envelope.dart' show Address;
import 'package:mycelium/history.dart';
import 'package:mycelium/node_join.dart' show NodeJoin;

/// The outbound of the mailbox: send, leave resting, re-dispatch — always
/// AS the identity of this mailbox.
///
/// A separate file for the same reason as `mailbox_amendment.dart` — the
/// line budget of `mailbox.dart` knows no exception. The cut follows
/// the question of what happens to an own message until it is receipted;
/// over there stands who the peer is at all.
///
/// ── WHY A MESSAGE STAYS RESTING INSTEAD OF FAILING ─────────────
///
/// Until S384 `send` threw an error ("kein bekannter Weg") and did
/// not even create a history entry — a typed message was
/// thus gone without a trace. That is the wrong answer to the wrong question:
/// "I do not know this contact" and "I do not know right now how to
/// reach it" are not the same case.
///
///  * **Unknown identifier** NEVER changes by waiting. That stays an
///    error, and [Mailbox.contact] still throws it.
///  * **No known route** almost always changes, and the three edges
///    at which it flips all lie in ongoing operation: an
///    accepted contact request, a join, a neighbour found by the call.
///
/// The layer to be replaced made the same distinction in §21.2: what
/// does not change by waiting is not parked — "promising a
/// re-dispatch that would always have the same result".
///
/// NO TIMER. Re-dispatch happens at an EDGE, not after a
/// deadline expires. Working rule #5 (no polling) and the reasoning of the
/// V3 one-shot outbox apply unchanged: a message that goes out again every
/// minute costs network traffic and changes nothing.
///
/// ── HERE TEXT BECOMES BYTES, AND ONLY HERE ────────────────────────────
/// [send] takes bytes, because the delivery layer carries bytes and interprets
/// nothing (see `message.dart`). [sendText] is the one convenient
/// version over it: it does `utf8.encode` and NOTHING else. It is
/// no second delivery — it is an encoding, and it stands up here
/// so that there is exactly one place in the tree where text becomes
/// bytes.
extension MailboxOutbound on Mailbox {

  /// Sends [text] as UTF-8 to the contact with [contactIdentifier].
  ///
  /// The one convenient version over [send] — it encodes and calls on.
  /// Whoever already has bytes (the application with its protobuf frames) calls
  /// [send] directly.
  Outbound sendText(String contactIdentifier, String text) =>
      send(contactIdentifier, utf8.encode(text));

  /// Sends [content] to the contact with [contactIdentifier].
  ///
  /// [content] goes out unchanged — arbitrary bytes.
  ///
  /// Without a known address the message STILL goes onto the ladder, and
  /// that is the actual point: §8.2 attaches the post box to the
  /// OWN neighbours, not to an address of the recipient
  /// (`node.dart`: `inPostBox` gets only `target.identifier` and
  /// `depositNeighbours`). Until S390 this method returned without an address, and
  /// step 4 was thus unreachable exactly in the case for which §8.2
  /// provides it (`berichte/S390-EVAL-NACHRICHT.md`, finding B-2).
  ///
  /// **No readiness gate before it.** §22.7.2 allows EXACTLY ONE
  /// function gate (posting into the system channels), and §22.7.1 says
  /// for `searching` explicitly "ladder steps 1 and 2 may still carry;
  /// nothing can be left in a post box" — so the ladder is entered,
  /// and whether a deposit comes about is decided by the deposit itself.
  ///
  /// [DeliveryState.resting] thus keeps exactly the meaning from §9.1
  /// ("created, not yet sent") — and since V11 (S403) BEYOND the entry
  /// into the ladder: `in transit` begins only with the evidence, a way
  /// that demonstrably carried the packet ([dispatch]) or a post box that
  /// took it. Resting in a post box IS having gone out (§9.1: "`in
  /// transit` deliberately covers ‚lying in a post box'") — once the
  /// placing succeeded. An offline recipient is not an error.
  Outbound send(String contactIdentifier, Uint8List content) {
    final who = contact(contactIdentifier);
    final destination = routeTo(who);
    // Without a proven address the search call (call D, §7.2 "only when a send to
    // the contact has no way"). A find sets the route and re-dispatches.
    if (destination == null) node.search(who.address.identifier);
    final outbound = dispatch(who.address, content, destination,
        withoutRoute: routesEmpty(routesToContact(who)));
    historyFor(who.address).append(HistoryEntry(
      identifier: outbound.identifier,
      outgoing: true,
      content: content,
      instant: DateTime.now(),
      state: outbound.state,
    ));
    return outbound;
  }

  /// Hands [content] for [to] to the node and notes the running sending:
  /// a new message under a fresh identifier, an entry of the history that
  /// is sent again under its own ([under]; §9.3 "under the same
  /// identifier"). The ONE place a message of this mailbox enters the
  /// ladder — and the place that learns how the placing of its step 4 ends
  /// ([_placingEnded]).
  Outbound dispatch(Address to, Uint8List content, CardAddress? destination,
      {Uint8List? under, bool withoutRoute = false}) {
    final outbound =
        node.send(content, to, destination, forField: identity, under: under);
    final id = outbound.identifier;
    marksInTransit(to, outbound, id, withoutRoute: withoutRoute);
    final shipment = node.shipmentOf(_hex(id));
    // §9.1 (V11, S403): a way that demonstrably carried the packet puts
    // the message `in transit` AT the dispatch. The shell reports a send
    // on step 1 or 3 as sent ([Shipment.started]); the post box step in
    // `started` alone is NOT the evidence — it says only that the
    // deposit began (§8.2), and it ends without one when no holder
    // acknowledges.
    final carried =
        shipment?.started.any((s) => s != LadderStep.postBox) ?? false;
    if (carried) _messageLeft(outbound, to);
    shipment?.onPlacingEnd =
        (placed) => _placingEnded(to, outbound, id, placed, running: shipment);
    return outbound;
  }

  /// §9.1 (V11, S403): THE EVIDENCE IS THERE — a way demonstrably carried
  /// the packet or a post box took it. From `resting` the message becomes
  /// `in transit`, on the [Outbound] and in the history; only from this
  /// moment may the application start the sender-side auto-delete
  /// deadline (§21.5.3, `cleona_service_mycelium.dart`, [onCarried]).
  ///
  /// The history write is GUARDED: [History.stateChange] rewrites blindly
  /// and would overwrite a closed entry — one that is `delivered` or
  /// `failed` keeps its state. An entry not yet written is skipped for
  /// the same reason: the FIRST send appends after the dispatch, with
  /// the state that applies by then.
  void _messageLeft(Outbound outbound, Address to) {
    if (outbound.state != DeliveryState.resting) return;
    outbound.state = DeliveryState.inTransit;
    final hex = _hex(outbound.identifier);
    final entry = historyFor(to)
        .openOutbounds
        .where((e) => _hex(e.identifier) == hex)
        .firstOrNull;
    if (entry != null) {
      historyFor(to).stateChange(outbound.identifier, DeliveryState.inTransit);
    }
    report?.call('$hex in transit — a way carried it or a post box took it '
        '(§9.1)');
    _carriedSinks[this]?.call(outbound);
  }

  /// The application learns that one of its messages has been carried
  /// (§9.1, V11): called once per message, at the moment `resting`
  /// becomes `in transit` — the display state and the start of the
  /// auto-delete deadline (§21.5.3) hang on it. `null` takes it away.
  set onCarried(void Function(Outbound)? sink) =>
      _carriedSinks[this] = sink;

  /// The placing of the message [id] to [to] has ended (§8.2 "placing
  /// ends").
  ///
  /// PLACED — the second `0x31`: the entry remembers the moment
  /// (`history.dart`, "PLACED IS REMEMBERED"). From here on it is not sent
  /// again at an edge and not closed as `failed` (§9.3).
  ///
  /// NOT PLACED: the message is still neither acknowledged nor placed, and
  /// the next edge sends it again. If an edge PASSED while this placing ran
  /// ([giveUpAgain] could not know yet how it would end and noted the
  /// entry), that edge's question is answered now, and the message leaves
  /// again here — once. No clock: the end of a placing is an event (§8.2),
  /// and without an edge in between nothing is sent.
  void _placingEnded(Address to, Outbound outbound, Uint8List id, bool placed,
      {required Shipment running}) {
    final hex = _hex(id);
    final history = historyFor(to);
    if (placed) {
      _edgePassed(this).remove(hex);
      // §9.1 (V11, S403): the post box took it — from this evidence the
      // message is `in transit` (and only from now it expires, §21.5.3).
      // BEFORE the placing is remembered below, so that whoever reads
      // in between sees state and placing together.
      _messageLeft(outbound, to);
      if (history.placedMark(id, DateTime.now())) {
        report?.call('$hex is placed — remembered, it is not sent again '
            '(§9.3)');
      }
      return;
    }
    // A sending that was superseded meanwhile answers nothing: the newer
    // one does. Neither does one that is acknowledged, nor a run the
    // stopping node ended.
    final now = node.shipmentOf(hex);
    if (now != null && !identical(now, running)) return;
    final passed = _edgePassed(this).remove(hex);
    if (now == null || !passed || node.postBoxDeposit.closed) return;
    final entry = history.openOutbounds
        .where((e) => _hex(e.identifier) == hex)
        .firstOrNull;
    if (entry != null) _atEdge(to, entry, DateTime.now());
  }

  /// AN EDGE (§8.2, §9.3): "the node sends again, under the same identifier,
  /// what is neither acknowledged nor placed" — at start for all contacts
  /// and group pairs, at an edge of one peer only for [only].
  ///
  /// What is PLACED is not sent again, not placed a second time and not
  /// closed as `failed` (§9.3, D-44, D-48); the copy kept for sending again
  /// goes here once the placing is more than [kPlacedCopyKept] old.
  ///
  /// What was NEVER placed and has been open longer than [kOutboundDeadline]
  /// is set to [DeliveryState.failed] instead of being re-dispatched (D-47).
  /// That is a purely local time check, it creates no network traffic — and
  /// it takes effect when someone looks, not at a point in time: setting a
  /// timer for it would mean that a device wakes up to declare a
  /// message dead. Closed, the entry keeps its identifier and loses its
  /// content (`history.dart`): nothing is sent from it any more.
  ///
  /// [reseal]: also what is RUNNING or PLACED goes out newly sealed — after
  /// a change of signing keys on either side (§4.5.4 "their unacknowledged
  /// messages are sent again"): a running envelope under the sender's old
  /// keys is superseded at the recipient and never acknowledged, one under
  /// the recipient's old KEM keys opens only 7 d.
  ///
  /// GROUP PAIRS (§4.3, `mailbox_group_pair.dart`) are re-dispatched the same
  /// way, without a route and without a search call: their legs go by code
  /// and post box only.
  void giveUpAgain({Address? only, bool reseal = false}) {
    // What the receipts of the last moments closed is written first: an
    // acknowledged message is not open any more, whatever the checker's
    // turn (`Mailbox.stateCheck`).
    stateCheck();
    // S405 F-1 (D-44): an out-of-band request no post box took yet goes too.
    if (only == null) node.joinsSendAgain(identity);
    final now = DateTime.now();
    final seen = <String>{};
    for (final address in [
      for (final k in contacts) k.address,
      for (final p in groupPairs) p.address,
    ]) {
      if (!seen.add(identifierFrom(address))) continue;
      if (only != null && identifierFrom(address) != identifierFrom(only)) continue;
      for (final entry in historyFor(address).openOutbounds.toList()) {
        _atEdge(address, entry, now, reseal: reseal);
      }
    }
  }

  /// The open own [entry] of the history with [address], at an edge.
  void _atEdge(Address address, HistoryEntry entry, DateTime now,
      {bool reseal = false}) {
    final history = historyFor(address);
    final id = entry.identifier, hex = _hex(id);
    if (entry.placedAt case final placedAt?) {
      // PLACED IS FINAL (§9.3). The holders keep it 7 days (§8.2); after
      // that it reaches its recipient through the recipient's request, from
      // the application's store (§9.5) — the copy here has no reader left.
      final dropped = now.difference(placedAt) > kPlacedCopyKept &&
          history.copyDrop(id);
      if (dropped) {
        report?.call('$hex was placed more than ${kPlacedCopyKept.inDays} '
            'days ago — the copy kept for sending again is dropped; it stays '
            'in transit (§9.1, §9.3)');
      }
      if (!reseal || dropped || entry.content.isEmpty) return;
      // SEALED AGAIN (§4.5.4): the placing was that of the envelope under
      // the replaced keys. It counts no longer — were it kept and the new
      // deposit not placed, no edge would ever send the message again.
      history.placedClear(id);
    } else if (now.difference(entry.instant) > kOutboundDeadline) {
      // THE DEADLINE FIRST, only then the question whether something is
      // running — a running sending stays `in transit` for good otherwise
      // (found on 14.09.2026 in a check of the receipt path).
      try {
        history.stateChange(id, DeliveryState.failed);
        report?.call('$hex has been resting for more than '
            '${kOutboundDeadline.inDays} days — given up');
      } on HistoryError catch (err) {
        report?.call('Giving up discarded: $err');
      }
      return;
    }
    final who = contactOrNull(identifierFrom(address));
    final destination = who == null ? null : routeTo(who);
    final withoutRoute = who == null || routesEmpty(routesToContact(who));
    // §8.2 applies here too: without an address the post box carries. Until
    // S390 the re-dispatch skipped ahead at this place, and a
    // message without an address stayed resting at EVERY edge (finding B-2).
    if (who != null && destination == null) node.search(address.identifier);
    // ITS PLACING STILL RUNS: whether it is "neither acknowledged nor
    // placed" is not known yet. It is not sent a second time beside its own
    // deposit — with three edges shortly after one another it would go out
    // three times —; the edge is noted and answered when the placing ends
    // ([_placingEnded]).
    //
    // EXCEPTION, and it is the purpose of the edge: a shipment that started
    // without any address can no longer learn the one just added, and one
    // sealed under replaced keys is never acknowledged. It is replaced
    // (§9.3).
    final replace = reseal || !withoutRoute && runsWithoutRoute(id);
    final running = node.shipmentOf(hex);
    if (running != null && running.placed == null && !replace) {
      _edgePassed(this).add(hex);
      return;
    }
    // The sending before this one is superseded: a deposit of it that has
    // not left yet is dropped (§7.1).
    node.shipmentEnd(hex);
    final outbound = dispatch(address, entry.content, destination,
        under: id, withoutRoute: withoutRoute);
    report?.call('$hex put back on the ladder (${_hex(outbound.identifier)})');
  }

  /// The application has deleted messages (§21.5.2 level 1: "immediately
  /// and completely"; §9.3: "the application decides when to stop … it
  /// stops the sending"). For every entry of the history with [peer] that
  /// [which] names:
  ///
  ///  * an OWN one leaves the history, and if it is still open its sending
  ///    ends HERE: the shipment is given up, a deposit not yet sent is
  ///    dropped, and nothing of it leaves again at an edge. What already
  ///    lies in a post box stays there until it expires (§21.5.2 level 3).
  ///
  /// A RECEIVED delivery has not stood in a history since S403
  /// (`history.dart`, §20.2): its identifier lives in the identity's
  /// received memory, which this forgetting does not touch — a late copy
  /// of a deleted message stays refused, and a copy of a message whose
  /// contact was deleted just the same (V-3 = a). A [which] that decides
  /// by the content therefore names own entries only.
  ///
  /// Since S401 only an OPEN own entry carries content at all
  /// (`history.dart`, V4.2 §21.4.2): what is acknowledged or given up has
  /// none left to forget, and [which] finds nothing in it.
  /// [which] decides by the content, and only the application can read that
  /// (`message.dart`): this layer does not know which entries belong to one
  /// message of the application.
  ///
  /// Returns the number of entries forgotten.
  int forget(Address peer, bool Function(HistoryEntry) which) {
    final named = historyFor(peer).forget(which);
    final gone = named.where((e) => e.outgoing).toList();
    for (final e in gone) {
      final entry = _hex(e.identifier);
      _edgePassed(this).remove(entry);
      inTransit.removeWhere((shipment, u) {
        if (_hex(u.identifierInHistory) != entry) return false;
        node.shipmentEnd(shipment);
        identity.messages.giveUp(u.outbound.identifier);
        return true;
      });
    }
    if (named.isNotEmpty) {
      report?.call('${named.length} entr${named.length == 1 ? 'y' : 'ies'} '
          'forgotten in the history with '
          '${identifierFrom(peer).substring(0, 8)} (${gone.length} own)');
    }
    return named.length;
  }
}

/// How long an own message may rest before it is given up.
///
/// **Fourteen days, owner decision of 14.09.2026.** Deliberately NOT the
/// seven days of the post box deposit: there one occupies the storage of a
/// FOREIGN device, here one's own. Two different loads may have
/// two different deadlines; the same number would only be
/// seemingly simpler here.
///
/// **Only for a message that was never placed** (D-47 "a message without a
/// way"; §9.3 "a placed message is … not closed as `failed`", D-48).
const Duration kOutboundDeadline = Duration(days: 14);

/// Per mailbox: the open entries (identifier, hex) for which an edge passed
/// while the placing of their running sending had not ended — see
/// [MailboxOutbound._placingEnded]. In memory only: after a restart no
/// placing runs, and the start edge sends what is not placed.
final Expando<Set<String>> _edges = Expando('edgePassedWhilePlacing');
Set<String> _edgePassed(Mailbox m) => _edges[m] ??= {};

/// Per mailbox: the sink the application set for the carrying of its
/// messages — see [MailboxOutbound.onCarried]. In memory only: after a
/// restart no note of the application survives anyway.
final Expando<void Function(Outbound)> _carriedSinks =
    Expando('messageCarried');

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
