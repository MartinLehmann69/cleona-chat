import 'dart:typed_data';

import 'package:mycelium/group.dart';
import 'package:mycelium/node_post_box.dart';
import 'package:mycelium/node_helpers.dart';
import 'package:mycelium/mailbox.dart';

/// The multi-recipient side of the mailbox: create a group.
///
/// A separate file for the same reason as `mailbox_amendment.dart`: the
/// line budget of `mailbox.dart` knows no exception. The cut follows
/// the question TO WHOM something goes — here to more than one, over there
/// to exactly one contact.
///
/// It gets by with the public side of [Mailbox]:
/// [Mailbox.node], [Mailbox.identity], [Mailbox.groups] and [Mailbox.report].
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

  // `mediaSend` (raw, unsealed 0x50/0x51 to the contact) is gone since S398:
  // 0x51 is now the SEALED piece of lane 3, and a large object goes through
  // `mailbox_bulk.dart` (§9.4). It had no caller in the app.
}

String _short(Uint8List b) =>
    b.take(4).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
