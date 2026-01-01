/// The run states of an own deposit and an own collection.
///
/// Stood until S391 as private classes in `post_box_deposit.dart`; moved
/// out for the line budget. Only data — sending and deciding happen in the
/// deposit (`post_box_deposit.dart`) and the collector
/// (`post_box_collect.dart`).
///
/// Both run on events, never on a clock (§8.2, D-44): a deposit ends when
/// every holder has acknowledged or its transmission has ended; a
/// collection is a conversation per holder, and a holder is done when it
/// has handed out what it announced, its link has ended unanswered, or one
/// request for what is missing has brought nothing (the quiet period of
/// §11.3 — no timer runs while answers are arriving).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:mycelium/post_box_proof.dart' show Question;
import 'package:mycelium/post_box_holder.dart' show Neighbour;

class DepositRun {
  /// Who was addressed — only set AFTER dispatch: if already the
  /// computation fails, nobody was asked, and nobody is mute.
  List<Neighbour> asked = const [];

  /// `adresse:port` -> node identifier of the receipt. Placed is by
  /// NODES, not by addresses (B1, S388): a holder under two addresses
  /// is ONE copy.
  final Map<String, String> acknowledged = {};
  int get node => acknowledged.values.toSet().length;

  /// `adresse:port` of the holders whose transmission of the `0x30` has
  /// ended (`delivered`, `unconfirmed`, `refused`, `unreachable` — §11.3,
  /// §11.6). A holder acknowledges before its end mark leaves
  /// (`split.dart`), so a holder that ended without a receipt gives none.
  final Set<String> ended = {};

  /// One per holder whose `0x30` left as a single part: it has no end mark,
  /// so its transmission has ended 1.1 s after it (§11.3). Cancelled when
  /// the run ends.
  final List<Timer> waits = [];

  /// The run leaves: no timer stays behind.
  void release() {
    for (final w in waits) {
      w.cancel();
    }
    waits.clear();
  }

  /// Every addressed holder has acknowledged or its transmission has ended:
  /// nothing more can come (§8.2 "placing ends").
  bool get finished => asked.every((n) {
        final k = neighbourKey(n);
        return acknowledged.containsKey(k) || ended.contains(k);
      });

  /// For the log only (`post_box_log.dart`): when the packet went out, after
  /// how many ms each holder's receipt came, and which came after the run
  /// was already placed.
  DateTime? sentAt;
  String valueShort = '';
  final Map<String, int> ackMs = {};
  final Set<String> afterPlaced = {};
  final Completer<(bool done, int acknowledged)> result = Completer();

  /// The result, fixed ONCE by [complete] and read by everyone after it —
  /// the result future and the final log line alike (S398, OP-22): `null`
  /// while open, `true` as soon as two nodes have acknowledged (§8.2),
  /// `false` only once every transmission has ended short of two.
  bool? placed;

  /// Fixes [placed] from the nodes acknowledged so far; later calls change
  /// nothing.
  void complete() {
    if (placed != null) return;
    final p = node >= 2;
    placed = p;
    result.complete((p, node));
  }
}

/// One question — up to seven values — put to several holders. Every holder
/// answers it in a conversation of its own ([Conversation]); no holder waits
/// for another (§8.2 "collection ends").
class CollectionRun {
  /// The asked holders, each once, in the order they were named.
  final List<Neighbour> holder;

  /// What is asked, by value (hex) — every question carries the
  /// day key that signs its proof and its delete receipts.
  final Map<String, Question> ask;

  /// Read, do not delete: no delete receipt goes out — a fresh install
  /// that only searches must not take a living device's bundle (D-40).
  final bool keep;

  /// Where every piece goes the moment it arrives (§8.2 "taken over and
  /// acknowledged for deletion when it arrives") — see [PieceTaken].
  final PieceTaken? onPiece;

  /// Per asked holder (`adresse:port`): its conversation. Only their
  /// answers count — until S385 every sender counted, and three foreign
  /// 0x34 ended a collection before a holder had answered (proposal
  /// holder, B6).
  final Map<String, Conversation> talks = {};

  /// What was taken over, each piece once.
  final List<Uint8List> found = [];
  final Set<String> seen = {};

  /// Per value (hex): the ids taken over in this run — a holder whose task
  /// comes after a takeover gets their deletion behind its proofs (§8.2
  /// "to every holder it asked", M-2).
  final Map<String, List<Uint8List>> taken = {};

  /// Completes with [found] once every asked holder is done. It waits
  /// alone: nothing else of the collector depends on it.
  final Completer<List<Uint8List>> result = Completer();

  CollectionRun(List<Neighbour> holders, List<Question> askedValues,
      {this.keep = false, this.onPiece})
      : holder = [],
        ask = {for (final f in askedValues) asHex(f.value): f} {
    for (final n in holders) {
      final k = neighbourKey(n);
      if (talks.containsKey(k)) continue;
      holder.add(n);
      talks[k] = Conversation(this, n);
    }
    _runOf[found] = this;
  }

  /// Every asked holder is done.
  bool get complete => talks.values.every((t) => t.end != null);

  /// How many asked holders answered the question to the end: handed out
  /// what they announced, or said "nothing here" ([TalkEnd.answered]).
  int get answered =>
      talks.values.where((t) => t.end == TalkEnd.answered).length;
}

/// The run a collection's result list came from. The collector completes a
/// run with its [CollectionRun.found]; whoever holds that list can ask how
/// the run ended without the collector's signature carrying it.
final Expando<CollectionRun> _runOf = Expando<CollectionRun>('collectionRun');

/// Of the collection that returned [pieces]: how many asked holders answered
/// it to the end ([CollectionRun.answered]) — `0` for a list that is no
/// collection's result. v4_2 §8.2 "After more than 7 days": only a collection
/// that ended with an answer from at least one holder counts as the device's
/// last one (`node_post_box.dart`).
int holdersAnswered(List<Uint8List> pieces) => _runOf[pieces]?.answered ?? 0;

/// At most this many questions stand in one holder's row — the open one and
/// those waiting behind it (R-2). Set, not measured: a round puts up to four
/// kinds of questions per identity; a row empties as its questions end.
const int kRowAtMost = 64;

/// At most this many conversations that ended [TalkEnd.quiet] are kept for
/// a late answer; beyond it the oldest drops (§20.2). Set, not measured: a
/// round asks a handful of holders, and only those that fell silent stand
/// here.
const int kLateAtMost = 8;

/// At most this many own deposits run at once; beyond it the oldest ends
/// with the receipts it has, without counting a use (§20.2). Set, not
/// measured: the size of the holder's tables (`kAtMostOpen`).
const int kDepositsAtMost = 1024;

/// The consumer of a collected piece: `true` — it took the piece over, and
/// only then the collector acknowledges it for deletion; `false` — the piece
/// stays with its holder (§8.2).
typedef PieceTaken = bool Function(Uint8List content, Neighbour holder);

/// How a conversation ended (§8.2 "collection ends").
enum TalkEnd {
  /// The holder handed out the number it announced for every value
  /// (`0x34`: none, `0x37`: refused).
  answered,

  /// Its link ended unanswered (§11.6): a send to it ended `unreachable`.
  unreachable,

  /// One request for what was missing brought nothing within a quiet period
  /// (§8.2): the holder is done for this edge with what it handed out for
  /// this question; the next in its row goes out.
  quiet,

  /// Not answered and not counted: it waited behind a question whose holder
  /// was unreachable (§20.2), the holder's row was full ([kRowAtMost]), or
  /// the node stopped.
  dropped,
}

/// The conversation with ONE holder about the question of [of]: request
/// `0x32`, task `0x35`, proofs `0x36`, pieces `0x33` up to the announced
/// number (or `0x34`, `0x37`).
class Conversation {
  final CollectionRun of;
  final Neighbour holder;
  Conversation(this.of, this.holder);

  /// The request identifiers (hex) sent to the holder for this question:
  /// the request and, after a quiet period without a task, the one further.
  final Set<String> ids = {};

  /// The holder's task. ONE per conversation is answered: a request forged
  /// onto this source could otherwise make the collector send 3.3 KB to
  /// the holder arbitrarily often.
  Uint8List? random;

  /// Per value (hex): the number announced, and the ids handed out since
  /// its proof last went out — a copy of an entry counts once.
  final Map<String, int> expected = {};
  final Map<String, Set<String>> handed = {};
  int received(String value) => handed[value]?.length ?? 0;

  /// [value] is answered: the announced number is handed out (`0x34`: none).
  bool done(String value) {
    final e = expected[value];
    return e != null && received(value) >= e;
  }

  /// The proof of [value] goes out once more: its answer counts from zero —
  /// the holder announces what it still holds.
  void restart(String value) {
    expected.remove(value);
    handed.remove(value);
  }

  /// Whether the holder has answered a request of this conversation at all.
  bool answered = false;

  /// The quiet period (§8.2, as §11.3) — only while this conversation is
  /// open. [progress] counts the holder's answers; [progressAtRequest] is
  /// its value when the one request for what is missing last went out.
  Timer? quiet;
  int progress = 0;
  int? progressAtRequest;

  /// `null`: waiting in the holder's row, or open.
  TalkEnd? end;

  /// The holder has answered for EVERY value.
  bool get handedOut => random != null && of.ask.keys.every(done);

  /// What this holder handed out that the run had not taken yet.
  int pieces = 0;
}

/// `adresse:port` — the key of a neighbour in the run states.
String neighbourKey(Neighbour n) => '${n.$1.address}:${n.$2}';

String asHex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
