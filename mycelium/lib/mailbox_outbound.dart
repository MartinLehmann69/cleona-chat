import 'dart:convert';
import 'dart:typed_data';

import 'package:mycelium/address_class.dart' show routesToContact;
import 'package:mycelium/card_address.dart' show routesEmpty;
import 'package:mycelium/node_call.dart';
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/message.dart' show Outbound, DeliveryState;
import 'package:mycelium/envelope.dart' show Address;
import 'package:mycelium/history.dart';

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
  /// ("created, not yet sent"): the moment between creating the
  /// [Outbound] and the ladder. Whoever has entered the ladder is
  /// `in transit` — resting in a post box IS having
  /// gone out (§9.1: "`in transit` deliberately covers ‚lying in
  /// a post box'"), and an offline recipient is not an error.
  Outbound send(String contactIdentifier, Uint8List content) {
    final who = contact(contactIdentifier);
    final destination = routeTo(who);
    // Without a proven address the search call (call D, §7.2 "only when a send to
    // the contact has no way"). A find sets the route and re-dispatches.
    if (destination == null) node.search(who.address.identifier);
    final outbound =
        node.send(content, who.address, destination, forField: identity);
    historyFor(who.address).append(HistoryEntry(
      identifier: outbound.identifier,
      outgoing: true,
      content: content,
      instant: DateTime.now(),
      state: outbound.state,
    ));
    marksInTransit(who.address, outbound, outbound.identifier,
        withoutRoute: routesEmpty(routesToContact(who)));
    return outbound;
  }

  /// Puts every open message onto the ladder again — at start for
  /// all contacts, at an edge only for [only].
  ///
  /// What has been open longer than [kOutboundDeadline] is set to
  /// [DeliveryState.failed] instead of being re-dispatched. That is a
  /// purely local time check, it creates no network traffic — and
  /// it takes effect when someone looks, not at a point in time: setting a
  /// timer for it would mean that a device wakes up to declare a
  /// message dead.
  void giveUpAgain({Address? only}) {
    final now = DateTime.now();
    for (final who in contacts) {
      if (only != null && identifierFrom(who.address) != identifierFrom(only)) continue;
      final history = historyFor(who.address);
      for (final entry in history.openOutbounds.toList()) {
        // THE DEADLINE FIRST, only then the question whether something is running.
        // The other way round it never fired: `_inTransit` keeps an entry
        // as long as its state is `in transit`, and exactly that is the case
        // for which the deadline is made. `runsCurrently` would be permanently
        // true, the jump below always taken, and a never
        // receipted message would stay `in transit` forever in the running process.
        // Found on 14.09.2026 in a check of the
        // receipt path, not in operation.
        if (now.difference(entry.instant) > kOutboundDeadline) {
          try {
            history.stateChange(entry.identifier, DeliveryState.failed);
            report?.call('${_hex(entry.identifier)} has been resting for more than '
                '${kOutboundDeadline.inDays} days — given up');
          } on HistoryError catch (err) {
            report?.call('Giving up discarded: $err');
          }
          continue;
        }
        final destination = routeTo(who);
        // §8.2 applies here too: without an address the post box carries. Until
        // S390 the re-dispatch skipped ahead at this place, and a
        // message without an address stayed resting at EVERY edge (finding B-2).
        if (destination == null) node.search(who.address.identifier);
        // Already running: do not touch. Without this question the same
        // message would go out once more at every edge — with three
        // edges shortly after one another thus three times.
        //
        // EXCEPTION, and it is the purpose of the edge: a shipment that started without
        // any address can no longer learn the one just added.
        // It is replaced (§9.3), and `marksInTransit`
        // clears away the previous note of the same entry in doing so.
        final replace =
            !routesEmpty(routesToContact(who)) && runsWithoutRoute(entry.identifier);
        if (runsCurrently(entry.identifier) && !replace) continue;
        final outbound = node.send(entry.content, who.address, destination,
            forField: identity);
        marksInTransit(who.address, outbound, entry.identifier,
            withoutRoute: routesEmpty(routesToContact(who)));
        report?.call('${_hex(entry.identifier)} put back on the ladder '
            '(${_hex(outbound.identifier)})');
      }
    }
  }
}

/// How long an own message may rest before it is given up.
///
/// **Fourteen days, owner decision of 14.09.2026.** Deliberately NOT the
/// seven days of the post box deposit: there one occupies the storage of a
/// FOREIGN device, here one's own. Two different loads may have
/// two different deadlines; the same number would only be
/// seemingly simpler here.
const Duration kOutboundDeadline = Duration(days: 14);

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
