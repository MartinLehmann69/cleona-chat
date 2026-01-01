/// The run states of an own deposit and an own collection.
///
/// Stood until S391 as private classes in `post_box_deposit.dart`;
/// moved out for the line budget when the repetition from §11.8 (E2)
/// was added. Only data — sending and deciding happen in the deposit.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:mycelium/post_box_proof.dart' show Question;
import 'package:mycelium/post_box_holder.dart' show Neighbour;

class DepositRun with Repeatable {
  /// Who was addressed — only set AFTER dispatch: if already the
  /// computation fails, nobody was asked, and nobody is mute.
  List<Neighbour> asked = const [];

  /// `adresse:port` -> node identifier of the receipt. Placed is by
  /// NODES, not by addresses (B1, S388): a holder under two addresses
  /// is ONE copy.
  final Map<String, String> acknowledged = {};
  int get node => acknowledged.values.toSet().length;
  final Completer<(bool done, int acknowledged)> result = Completer();
  Timer? deadline;
}

class CollectionRun with Repeatable {
  /// The asked holders (`adresse:port`). Only their answers count —
  /// until S385 every sender counted, and three foreign 0x34 ended a
  /// collection before a holder had answered (proposal holder, B6).
  final Set<String> asked;
  final List<Neighbour> holder;
  int get requested => asked.length;

  /// What is asked, by value (hex) — every question carries the
  /// day key that signs its proof and its delete receipts.
  final Map<String, Question> ask;

  /// The task per asked holder. ONE per holder is answered:
  /// a request forged onto this source could otherwise make the collector
  /// send 3.3 KB to the holder arbitrarily often.
  final Map<String, Uint8List> random = {};
  final List<Uint8List> found = [];
  final Set<String> seen = {};

  /// Per `adresse:port|wert(hex)`: announced and received pieces.
  final Map<String, int> expected = {};
  final Map<String, int> received = {};
  final Completer<List<Uint8List>> result = Completer();
  Timer? deadline;
  CollectionRun(this.holder, List<Question> askedValues)
      : asked = {for (final n in holder) neighbourKey(n)},
        ask = {for (final f in askedValues) asHex(f.value): f};

  /// Complete: every asked holder has answered for EVERY value
  /// and delivered everything announced.
  bool get complete =>
      expected.length == requested * ask.length &&
      expected.entries.every((e) => (received[e.key] ?? 0) >= e.value);
}

/// What a run needs for the ONE repetition to the mute ones
/// (§11.8, E2): the sent packet and the deadline that runs once more
/// afterwards.
mixin Repeatable {
  Uint8List? packet;
  Duration deadlineDuration = Duration.zero;
  bool repeated = false;
}

/// `adresse:port` — the key of a neighbour in the run states.
String neighbourKey(Neighbour n) => '${n.$1.address}:${n.$2}';

String asHex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
