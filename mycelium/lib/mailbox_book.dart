/// The book of a mailbox — its remembered contacts, as the prior state of
/// every acceptance (`anchor_book.dart`, V4.2 §4.5.4, D-33).
///
/// A separate file for the line budget of `mailbox.dart`, and because the
/// book is a view onto the mailbox, not a second store: what it holds is
/// [Mailbox.contacts], what it adopts goes through [Mailbox.contactRemember]
/// — the ONE path that writes an address, with its adoption rule, its edge
/// for the groups and its re-dispatch of what rests for that contact
/// ("every open own message to that party is sealed again against the new
/// address", §4.5.4).
library;

import 'dart:typed_data';

import 'package:mycelium/envelope.dart';
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/mailbox_start.dart' show MailboxDetails;
import 'package:mycelium/mailbox_outbound.dart' show MailboxOutbound;
import 'package:mycelium/memory_contact.dart'
    show Contact, contactWithChainState;

/// Gives [m]'s post box its book. Once, when the mailbox is created.
void mailboxBookAttach(Mailbox m, MailboxDetails a) =>
    m.identity.postBox.book = _MailboxBook(m, a.onFork);

class _MailboxBook implements AnchorBook {
  final Mailbox _m;
  final void Function(Address held, Address claimed)? _onFork;

  _MailboxBook(this._m, this._onFork);

  Contact? _contact(Uint8List identifier) =>
      _m.contactOrNull(_hex(identifier));

  @override
  Address? held(Uint8List identifier) => _contact(identifier)?.address;

  @override
  void adopt(Address fresh) {
    _m.report?.call('keys of ${identifierFrom(fresh).substring(0, 8)} '
        'adopted by their rotation chain (${fresh.chain.length} link(s))');
    _m.contactRemember(fresh);
    // §4.5.4: "every open own message to that party is sealed again against
    // the new address" — also those still running under the old one.
    _m.giveUpAgain(only: fresh, reseal: true);
  }

  @override
  void chainArrived(Address from) {
    final k = _contact(from.identifier);
    if (k == null || k.chainAcked) return;
    _m.contactPut(contactWithChainState(k, acked: true));
    _m.report?.call('${identifierFrom(from).substring(0, 8)} acknowledged '
        'the own rotation chain — it stays out of envelopes to it now');
  }

  @override
  void fork(Address held, Address claimed) {
    _m.report?.call('FORK for ${identifierFrom(held).substring(0, 8)}: a '
        'chain that does not pass through the held keys — discarded, '
        'reported (§4.5.4)');
    _onFork?.call(held, claimed);
  }

  @override
  bool chainAcked(Uint8List identifier) =>
      _contact(identifier)?.chainAcked ?? false;
}

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
