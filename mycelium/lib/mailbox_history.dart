/// The histories of ONE mailbox — which store they are kept in, and what
/// leaves that store when a peer ends.
///
/// A separate file for the line budget of `mailbox.dart`; the cut is the
/// question WHERE the histories lie. What an entry keeps stands in
/// `history.dart`, the port in `history_store.dart`.
///
/// ── A PEER THAT ENDS TAKES ITS RECORDS WITH IT ─────────────────────────
/// A contact that is deleted or blocked (§15.9) and a group pair whose
/// last shared group is gone (§4.3) leave the mailbox — and their history
/// leaves the store with them ([MailboxHistories.drop]). Until S401 the
/// file of such a peer stayed for good and came back to life when the same
/// party became a contact again: its open entries were sent once more
/// (NB-12, U-11).
///
/// The IDENTIFIERS it once delivered are NOT records of its history and
/// do not go with it (S403, V-3 = a): they live in the identity's
/// received memory ([HistoryStore.incomingKeep], §20.2), which has no
/// peer and is kept for as long as the identity exists — a late copy of
/// a deleted contact stays refused, exactly as a copy of a contact that
/// is still there. Since S403 that memory is all the history keeps of a
/// RECEIVED delivery; only the OWN entries stand as records.
///
/// The same holds at the START ([MailboxHistory.historiesSettle]): records
/// of a peer the mailbox does not keep have no reader any more — nothing
/// is sent from them (the re-dispatch walks contacts and group pairs), and
/// no deletion would reach them. They go, reported. That is the case after
/// the enforcer removed a memory of a foreign version
/// (`mailbox_format_reset.dart`: every contact is gone, the application
/// ends them) or when the group-pair store could not be read.
library;

import 'dart:typed_data';

import 'package:mycelium/envelope.dart' show Address;
import 'package:mycelium/history.dart';
import 'package:mycelium/history_store.dart';
import 'package:mycelium/history_takeover.dart';
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/mailbox_group_pair.dart' show MailboxGroupPair;
import 'package:mycelium/mailbox_start.dart' show MailboxDetails;

/// The histories of a mailbox, by peer, over ONE [store].
class MailboxHistories {
  final HistoryStore store;
  final Map<String, History> _loaded = {};

  MailboxHistories(this.store);

  /// The histories for the mailbox that registers with [a]: over the store
  /// its caller gave ([historyStoreGive]) — the application's message store.
  /// A caller that gave none is a lab tool or a probe; its histories are
  /// kept in memory, and that is SAID, not done silently: they do not
  /// survive the process.
  factory MailboxHistories.forRegistration(
      MailboxDetails a, void Function(String)? report) {
    final given = historyStoreGiven(a);
    if (given == null) {
      report?.call('history kept in memory only — the caller gave no store '
          '(lab tool or probe); it does not survive this process');
    }
    return MailboxHistories(given ?? HistoryStoreMemory.at(a.directory));
  }

  /// The history with [peer] — read from the store at its first use in
  /// this process, from then on the same object.
  History of(Address peer) {
    final id = _hex(peer.identifier);
    return _loaded.putIfAbsent(id, () => History.load(store, id));
  }

  /// The peer with the identifier [peer] (hex) has ended: every record of
  /// its history leaves the store.
  void drop(String peer) {
    _loaded.remove(peer);
    store.drop(peer);
  }
}

extension MailboxHistory on Mailbox {
  /// Once, when the mailbox is created and its contacts and group pairs
  /// are loaded: the history files of the builds before S401 are taken
  /// over and removed (`history_takeover.dart`), and records of a peer this
  /// mailbox does not keep leave the store (file header).
  void historiesSettle(MailboxDetails a) {
    bool known(String peer) =>
        contactOrNull(peer) != null || groupPairOrNull(peer) != null;
    historyFilesTakeOver(
        directory: a.directory,
        key: a.key,
        store: histories.store,
        known: known,
        report: report);
    for (final peer in histories.store.peers()) {
      if (known(peer)) continue;
      histories.drop(peer);
      report?.call('history with ${peer.substring(0, 8)} removed from the '
          'store — no contact and no group pair any more');
    }
  }
}

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
