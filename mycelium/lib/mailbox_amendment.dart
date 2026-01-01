import 'dart:convert';
import 'dart:typed_data';

import 'package:mycelium/node_amendment.dart';
import 'package:mycelium/mailbox.dart';

/// The amendment side of the mailbox — reaction, edit, read mark,
/// each AS the identity of this mailbox.
///
/// A separate file for the same reason as `node_amendment.dart`: the
/// line budget of `mailbox.dart` knows no exception. The cut is
/// not arbitrary — here stands what one appends to a message AFTERWARDS,
/// over there how it comes about and goes away at all.
///
/// It gets by with the public side of [Mailbox]:
/// [Mailbox.node], [Mailbox.identity], [Mailbox.reachable] and
/// [Mailbox.historyFor].
///
/// All three are NOT delivery states. There are four of them, and that is how it
/// stays (owner decision 24a): a read mark that never comes is
/// not a delivery error.
extension MailboxAmendment on Mailbox {

  /// Reacts to a message in the history with [contactIdentifier].
  void react(String contactIdentifier, Uint8List messagesIdentifier,
      String chars,
      {bool isSet = true}) {
    final (contact, destination) = reachable(contactIdentifier);
    node.react(messagesIdentifier, chars, contact.address, destination,
        isSet: isSet, forField: identity);
  }

  /// Changes the content of an own message to [contactIdentifier] —
  /// [newText] as UTF-8. The one convenient version over [edit]:
  /// it encodes and calls on, nothing more.
  void editText(String contactIdentifier, Uint8List messagesIdentifier,
          String newText) =>
      edit(contactIdentifier, messagesIdentifier, utf8.encode(newText));

  /// Changes the content of an own message to [contactIdentifier].
  ///
  /// [newContent] goes out unchanged — arbitrary bytes, as when
  /// sending.
  void edit(String contactIdentifier, Uint8List messagesIdentifier,
      Uint8List newContent) {
    final (contact, destination) = reachable(contactIdentifier);
    node.edit(messagesIdentifier, newContent, contact.address, destination,
        forField: identity);
    // Locally the change applies immediately — the recipient checks its
    // deadline itself, and both sides can diverge if it
    // does not accept it. That is the price for the deadline lying with the
    // recipient; a sender that checks it alone has none.
    historyFor(contact.address)
        .contentChange(messagesIdentifier, newContent);
  }

  /// Notes to [contactIdentifier] that the message has been read.
  /// Voluntary — whoever does not want this does not call it.
  void readReport(String contactIdentifier, Uint8List messagesIdentifier) {
    final (contact, destination) = reachable(contactIdentifier);
    node.read(messagesIdentifier, contact.address, destination,
        forField: identity);
  }
}
