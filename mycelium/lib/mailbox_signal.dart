/// The call signal of this mailbox's identity (V4.2 §17.2, D-45): sealed and
/// sent like a message, with one difference — it takes ladder steps 1 and 3,
/// both at once, and nothing else.
///
/// ```
/// message   steps 1, 3, 4   history entry, sent again at every edge (§9.3)
/// signal    steps 1, 3      no history entry, never sent again at an edge
/// ```
///
/// What keeps it off step 4 is a property of its shipment, [Target.signal]
/// (`ladder_target.dart`): the ladder is the same one. Without step 4 there
/// is no proof of work and no holder (§8.2), and a call that cannot ring now
/// does not ring for nobody when the callee returns. The one difference left
/// to this file is the edge: a signal is never written into the history the
/// edges of §8.2 send again from (`mailbox_outbound.dart`), so it ends with
/// its acknowledgement (§9.2) or with its call ([signalEnd]), whichever comes
/// first. Its step 1 is repeated while it waits, as §11.3a says for every
/// packet that expects an answer — that is the transport's, not a clock here.
///
/// A missed call is NOT a signal: it is an ordinary message and goes through
/// [MailboxOutbound.send] (steps 1, 3 and 4, §17.2 "Missed call").
library;

import 'dart:typed_data';

import 'package:mycelium/mailbox.dart';
import 'package:mycelium/mailbox_group_pair.dart' show MailboxGroupPair;
import 'package:mycelium/message.dart' show Outbound;
import 'package:mycelium/node_helpers.dart' show hexFrom;

extension MailboxSignal on Mailbox {
  /// Sends the call signal [content] to the contact — or the group pair
  /// (§4.3) — with [identifier]: steps 1 and 3 only. Throws [MailboxError]
  /// when this identity knows neither.
  ///
  /// No search call of its own: the ladder sends one only when the
  /// recipient holds no address at all (§7.2), and a find would re-dispatch
  /// nothing — a signal has no history entry to re-dispatch from.
  Outbound signal(String identifier, Uint8List content) {
    final who = contactOrNull(identifier);
    final address = who?.address ??
        groupPairOrNull(identifier)?.address ??
        (throw MailboxError('neither a contact nor a group pair: $identifier'));
    return node.send(content, address, who == null ? null : routeTo(who),
        forField: identity, signal: true);
  }

  /// The call of [sent] has ended (§17.2: a signal "ends with its
  /// acknowledgement or with its call, whichever comes first"): its sending
  /// stops — step 1 is not asked again — and its open outbound closes. An
  /// acknowledged one is left as it is.
  void signalEnd(Outbound sent) {
    node.shipmentEnd(hexFrom(sent.identifier));
    identity.messages.giveUp(sent.identifier);
  }
}
