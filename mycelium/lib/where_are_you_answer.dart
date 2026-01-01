/// The answer to a `0x23` ("where are you", V4.2 §8.1):
///
/// > The recipient answers on the ordinary way; its acknowledgement carries
/// > its current fixed neighbours (§9.2).
///
/// Until S407-OLAPPW the recipient only adopted the sender's fixed neighbours
/// and registered its codes anew (S398 N-1c, `node_codes.dart`). That heals
/// a lost registration at an UNCHANGED fixed neighbour; a sender whose `0x23`
/// was started because the recipient's fixed neighbour had moved or died
/// never learned the new one (`berichte/S407-RCA-OLAPP9.md` W-1).
///
/// The answer is one acknowledgement `0x11` (§9.2) — the packet whose content
/// is exactly "an identifier and the current fixed neighbours" — sealed to
/// the sender like every acknowledgement. A `0x23` carries no message, so
/// there is no identifier to acknowledge: the identifier is eight zero
/// bytes, which names no message. The sender reads the list before it looks
/// the identifier up (`message.dart` `_cut`), keeps it (§9.2 "a contact
/// keeps the latest list it heard") and discards the rest as an
/// acknowledgement for an unknown identifier ("discarded, not raised as an
/// error"). A v4.2.3 sender does the same (`398a6e40:mycelium/lib/
/// message.dart:302–353`).
///
/// The way is the ordinary one of an acknowledgement whose message way is
/// unknown (`node_receipt.dart`): steps 1 and 3 — step 3 to the fixed
/// neighbours the `0x23` just named — never the post box.
///
/// THE SEARCHER, when the answer arrives (D-76, owner 26.10.2026): §8.1
/// "…its acknowledgement carries its current fixed neighbours (§9.2), and
/// what rests for it goes again (§9.3)" — as in the case "placing ended
/// unplaced → look up → the message goes again". The list is adopted first
/// (`message.dart` `_cut`), then [WhereAreYouAnswer.whereAreYouAnswered]
/// takes the one way of an edge for that peer (`mailbox_edge.dart`). Bound:
/// the `0x23` itself — one re-dispatch per own `0x23` sent within the hour
/// ([CodeRoute.searched]); an answer to no own `0x23`, or a second answer to
/// the same one, sends nothing.
///
/// ONE answer per sender and [kSuchInterval]: the sender sends at most one
/// `0x23` per contact per hour (§8.1), but the same `0x23` can arrive once
/// from each forwarder that holds this device's code. A bound, not a clock:
/// nothing is sent or forgotten when it runs out.
library;

import 'dart:typed_data';

import 'package:mycelium/envelope.dart' show Address;
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/mailbox_edge.dart' show MailboxEdge;
import 'package:mycelium/mailbox_pair.dart' show MailboxPair;
import 'package:mycelium/message.dart' show kIdentifierLength;
import 'package:mycelium/node_codes.dart' show kSuchInterval;

final Expando<Map<String, DateTime>> _answered = Expando('0x23 answered');
final Expando<Map<String, DateTime>> _taken = Expando('0x23 answer taken');

extension WhereAreYouAnswer on Mailbox {
  /// Answers the `0x23` that [to] sent and whose seal opened here.
  /// `true` if the acknowledgement went out.
  bool whereAreYouAnswer(Address to) {
    final who = identifierFrom(to);
    final now = node.codeRoute.now();
    final last = (_answered[this] ??= {})[who];
    if (last != null && now.difference(last) < kSuchInterval) {
      report?.call('0x23 from ${who.substring(0, 8)}: already answered '
          'within the hour — not again');
      return false;
    }
    _answered[this]![who] = now;
    identity.messages.receiptSend(Uint8List(kIdentifierLength), to);
    report?.call('0x23 from ${who.substring(0, 8)} answered: acknowledgement '
        'with ${ownNeighbours.length} fixed neighbour(s) on the ordinary way');
    return true;
  }

  /// The answer to an own `0x23` to [from] arrived (D-76, see the head):
  /// what rests for [from] goes again, once per `0x23` sent.
  void whereAreYouAnswered(Address from) {
    final who = identifierFrom(from);
    final asked = node.codeRoute.searched[who];
    final taken = _taken[this] ??= {};
    if (asked == null ||
        node.codeRoute.now().difference(asked) >= kSuchInterval ||
        taken[who] == asked) {
      report?.call('0x23 answer from ${who.substring(0, 8)}: no own 0x23 '
          'open — nothing goes again');
      return;
    }
    taken[who] = asked;
    report?.call('0x23 answered by ${who.substring(0, 8)}: what rests for it '
        'goes again (§8.1, D-76)');
    atEdge(only: from);
  }
}
