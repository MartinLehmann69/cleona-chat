/// The running shipments of ONE mailbox — noted when they leave, entered
/// into the history when the message layer has settled them.
///
/// A separate file for the line budget of `mailbox.dart` (S406); the cut is
/// the question WHAT IS RUNNING: [Mailbox.inTransit] holds the shipments,
/// this extension notes, asks and settles them. Re-exported by
/// `mailbox.dart`, so every caller of the mailbox reaches it unchanged.
library;

import 'dart:typed_data';

import 'package:mycelium/envelope.dart' show Address;
import 'package:mycelium/history.dart' show HistoryError;
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/message.dart' show Outbound, DeliveryState;

extension MailboxInTransit on Mailbox {
  /// No callback for receipt/give-up — [Outbound] is the same mutable
  /// instance the message layer changes; this check enters it into the
  /// history. What rests keeps its note (V11, §9.1) until it is carried.
  void stateCheck() {
    final settled = <String>[];
    for (final e in inTransit.entries) {
      final u = e.value;
      if (u.outbound.state == DeliveryState.resting ||
          u.outbound.state == DeliveryState.inTransit) { continue; }
      try {
        historyFor(u.to).stateChange(u.identifierInHistory, u.outbound.state);
      } on HistoryError catch (err) {
        report?.call('State change discarded: $err');
      }
      settled.add(e.key);
    }
    settled.forEach(inTransit.remove);
  }

  /// Notes a running shipment, so that [stateCheck] enters its state
  /// into the history afterwards. [identifierInHistory] is the identifier of the
  /// ENTRY — for a re-dispatch a different one than that of the shipment;
  /// a re-dispatch therefore REPLACES the previous note of the same
  /// entry. [withoutRoute]: started without any address, see [runsWithoutRoute].
  void marksInTransit(Address to, Outbound outbound,
          Uint8List identifierInHistory, {bool withoutRoute = false}) =>
      inTransit
        ..removeWhere(
            (_, u) => _hex(u.identifierInHistory) == _hex(identifierInHistory))
        ..[_hex(outbound.identifier)] = (to: to, outbound: outbound,
            identifierInHistory: identifierInHistory, withoutRoute: withoutRoute);

  /// Whether a shipment is currently running for [identifierInHistory]. The re-dispatch
  /// asks this before it dispatches something again — otherwise the same
  /// message would go out twice.
  bool runsCurrently(Uint8List identifierInHistory) => inTransit.values
      .any((u) => _hex(u.identifierInHistory) == _hex(identifierInHistory));

  /// Whether the running shipment for [identifierInHistory] started WITHOUT any address.
  /// Such a one no longer learns an address added later
  /// — the ladder sets up its steps at start —, so it is replaced at the
  /// edge (§9.3).
  bool runsWithoutRoute(Uint8List identifierInHistory) => inTransit.values.any((u) =>
      _hex(u.identifierInHistory) == _hex(identifierInHistory) && u.withoutRoute);
}

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
