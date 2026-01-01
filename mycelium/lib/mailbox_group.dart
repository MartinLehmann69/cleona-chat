import 'dart:typed_data';

import 'package:mycelium/group.dart';
import 'package:mycelium/node_post_box.dart';
import 'package:mycelium/node_helpers.dart';
import 'package:mycelium/media.dart';
import 'package:mycelium/mailbox.dart';

/// The multi-recipient side of the mailbox: create a group, send a large
/// payload.
///
/// A separate file for the same reason as `mailbox_amendment.dart`: the
/// line budget of `mailbox.dart` knows no exception. The cut follows
/// the question TO WHOM something goes — here to more than one or something
/// large, over there to exactly one contact.
///
/// It gets by with the public side of [Mailbox]:
/// [Mailbox.node], [Mailbox.identity], [Mailbox.groups],
/// [Mailbox.media] and [Mailbox.report].
extension MailboxGroup on Mailbox {

  /// Creates a group, with THIS identity as member. Until S385
  /// every group sealed with the node's first identity
  /// (`knoten.ich`), no matter which service created it (W1.b).
  ///
  /// One becomes a member exclusively via admission — whoever stood in a list at
  /// creation would never have got a key.
  Group groupCreate(String name) {
    final g = Group(
      me: identity.postBox,
      name: name,
      create: true,
      send: (packet, destination) => node.rawSend(packet, destination),
      deposit: (content, underIdentifier) =>
          node.deposit(content, underIdentifier),
      onInbound: (e) => report?.call('Gruppennachricht von '
          '${_short(e.from.toBytes())}: ${e.text}'),
      report: report,
    );
    groups[hexFrom(g.identifier)] = g;
    return g;
  }

  /// Sends [object] as a large payload to the contact with
  /// [contactIdentifier]. Under 256 KB streamed, otherwise into bulk — the
  /// lane is chosen by [MediaSender] by size.
  ///
  /// THE RECIPIENT STANDS IN FRONT, and that is the fix of S384: until then
  /// this method took only the bytes and called `medien.sende(objekt)` without a
  /// route. The default route of the `MedienSender` is a mere report — it
  /// thus sent NOTHING and reported success.
  ///
  /// Throws [MailboxError] if no route is known — unlike with
  /// a text message, NOTHING is parked here. A media object can be
  /// arbitrarily large; holding it in the outbox for 14 days is a different
  /// promise than for a few hundred bytes of text, and that one has not
  /// been made.
  Dispatch mediaSend(String contactIdentifier, Uint8List object) {
    final (_, destination) = reachable(contactIdentifier);
    return media.send(object,
        out: (lane, packet) => node.rawSend(packet, destination));
  }
}

String _short(Uint8List b) =>
    b.take(4).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
