/// The board (V4.2 §11.8a; build spec W5/W6, S391).
///
/// A node that is reachable under its own address hands out on
/// request the neighbours that it has confirmed under their address —
/// at most 32, each with the age of its last confirmation. A node
/// behind address translation asks from inside; the answer comes back through the
/// mapping that its question has just opened.
///
/// ── WIRE FORMAT (W5) ──────────────────────────────────────────────────────
/// ```
/// Question 0x43 | random 16 B                                      17 B
/// Answer   0x44 | random 16 B | address list (address_entries.dart)
///                                           at most 1 + 16 + 716 = 733 B
/// ```
/// The address list starts with the OWN addresses of the answering node
/// (S394 V3): the asker joins them into one neighbour, because the answer
/// comes from one of them (`neighbourhood_join.dart`). The neighbour
/// entries name ONE address per node, in the asker's family if the node
/// has one there.
/// Both travel like every packet through splitter and shell: on the wire
/// each of them is EXACTLY ONE packet of 1200 B (`shell.dart`). **The answer is
/// thus never larger than the question** — whoever replays a question with a foreign
/// sender address gets not one byte of amplification. So that it
/// stays that way, [Board] sends an answer only if it fits into ONE
/// part packet ([kAnswerAnswerAtMost]); it is measured on the wire
/// (`test/smoke_board.dart`).
///
/// ── WHO ANSWERS (W6) ────────────────────────────────────────────────────
/// Only a node that has PROVEN its reachability: by a mapping
/// that the router has granted, or by an unsolicited packet from the
/// open network (`board_proof.dart`). The address class alone is
/// no proof — a global IPv6 behind a stateful firewall
/// accepts nothing. Without proof: no answer, no packet.
///
/// ── WHEN IT IS ASKED ─────────────────────────────────────────────────────
/// Once per edge, after sources 1–3 and before the external entries
/// (§11.8a), to neighbours that are confirmed under their address. No clock:
/// the edge is set by the caller ([toTheEdge], `host_outside.dart`).
///
/// An entry is a hint (§6.1): it goes as a candidate to
/// [Board.onBoardAnswer] and is tried there, not believed.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:mycelium/address_entries.dart';
import 'package:mycelium/outside_address.dart' show fromOutsideReachable;
import 'package:mycelium/card_address.dart' show CardAddress, CardFormatError;
import 'package:mycelium/board_proof.dart';
import 'package:mycelium/neighbourhood.dart' show Neighbour;
import 'package:mycelium/shell_start.dart' show kPayloadAtMost;
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/split.dart' show kHeader;

/// Length of the random value that connects question and answer (§11.8a).
const int kAnswerRandom = 16;

/// Largest answer: kind + random + own count + 2 × 21 + count + 32 × 21,
/// an entry being 1 + 16 + 2 + 2 B.
const int kAnswerAnswerAtMost = 1 +
    kAnswerRandom +
    1 +
    kOwnEntriesAtMost * 21 +
    1 +
    kAddressEntriesAtMost * 21;

/// How long to wait for an answer. One round trip; whoever does not
/// answer keeps no board (W6) — that is not an error.
const Duration kBoardAnswerDeadline = Duration(seconds: 2);

/// How many neighbours are asked at most per edge, one after the
/// other, until one answers. §5.6 reckons with ONE exchange per edge
/// (≤ 0.7 KB); the limit caps the questions to neighbours without a board.
const int kAnswerAskPerEdge = 3;

/// §11.8: "An entry not confirmed for a day is stale" — stale entries never stand
/// in an answer, even if the callback should deliver them.
const Duration kConfirmedAtMost = Duration(days: 1);

typedef AnswerSend = void Function(
    Uint8List packet, InternetAddress target, int targetPort);

class _Open {
  final InternetAddress address;
  final int port;
  final Completer<AddressList> done = Completer();
  _Open(this.address, this.port);
}

class Board {
  final AnswerSend _send;
  final List<Neighbour> Function(DateTime now) _confirmed;
  final bool Function() _mappingProven;
  final List<CardAddress> Function(InternetAddress asker) _own;
  final ReachabilityProof? _passive;
  final Duration _deadline;
  final void Function(String)? _report;

  /// Learned addresses — own ones of [from] and candidates for the
  /// neighbourhood.
  void Function(AddressList l, InternetAddress from, int fromPort)?
      onBoardAnswer;

  final Map<String, _Open> _open = {};
  final Set<String> _asked = {};
  final Random _random = Random.secure();

  /// Counters for probes and network statistics (§25) — read only.
  int answered = 0;
  int withoutProofSilent = 0;
  int dropped = 0;
  int sentAsk = 0;

  Board({
    required AnswerSend send,
    required List<Neighbour> Function(DateTime now) confirmed,
    required bool Function() mappingProven,
    List<CardAddress> Function(InternetAddress asker)? own,
    ReachabilityProof? passive,
    this.onBoardAnswer,
    Duration deadline = kBoardAnswerDeadline,
    void Function(String)? report,
  })  : _send = send,
        _confirmed = confirmed,
        _mappingProven = mappingProven,
        _own = own ?? ((_) => const []),
        _passive = passive,
        _deadline = deadline,
        _report = report;

  /// W6: mapping granted OR reached unsolicited.
  bool get reachableProven =>
      _mappingProven() || (_passive?.proven ?? false);

  /// A new edge: every neighbour may be asked once again.
  void edgeStarts() => _asked.clear();

  /// Network change: the passive proof applied to the old address.
  void networkChanged() {
    _passive?.forget();
    edgeStarts();
  }

  /// Asks [to] — at most once per edge. `true` if a valid
  /// answer came; its entries have then gone to [onBoardAnswer].
  Future<bool> ask(Neighbour to) async {
    if (!_asked.add(_who(to.address, to.port))) return false;
    final random = Uint8List(kAnswerRandom);
    for (var i = 0; i < random.length; i++) {
      random[i] = _random.nextInt(256);
    }
    final key = _hex(random);
    final open = _Open(to.address, to.port);
    _open[key] = open;
    final question = Uint8List(1 + kAnswerRandom)
      ..[0] = kinds.kAnswerQuestion
      ..setRange(1, 1 + kAnswerRandom, random);
    sentAsk++;
    _send(question, to.address, to.port);
    try {
      final entries = await open.done.future.timeout(_deadline);
      _report?.call('Board from ${to.address.address}:${to.port}: '
          '${entries.own.length} own, ${entries.neighbours.length} '
          'entry/entries');
      onBoardAnswer?.call(entries, to.address, to.port);
      return true;
    } on TimeoutException {
      return false;
    } finally {
      _open.remove(key);
    }
  }

  /// The edge (§11.8a): asks the confirmed neighbours one after another until
  /// one answers — at most [kAnswerAskPerEdge]. Those reachable from outside
  /// first: only they can keep a board. Returns the
  /// number of questions sent. Does not throw.
  Future<int> toTheEdge() async {
    edgeStarts();
    final now = DateTime.now();
    final fresh = _confirmed(now).where((n) => _fresh(n, now));
    final row = [
      ...fresh.where((n) => fromOutsideReachable(n.address)),
      ...fresh.where((n) => !fromOutsideReachable(n.address)),
    ];
    var asked = 0;
    for (final n in row) {
      if (asked >= kAnswerAskPerEdge) break;
      asked++;
      try {
        if (await ask(n)) break;
      } on Object catch (e) {
        _report?.call('Board: question aborted: $e');
      }
    }
    return asked;
  }

  /// A packet of kinds 0x43/0x44 — from the kind dispatch.
  void receive(Uint8List packet, InternetAddress from, int fromPort) {
    if (packet.isEmpty) return;
    if (packet[0] == kinds.kAnswerQuestion) {
      _onQuestion(packet, from, fromPort);
    } else if (packet[0] == kinds.kAnswerAnswer) {
      _onAnswer(packet, from, fromPort);
    }
  }

  void _onQuestion(Uint8List packet, InternetAddress from, int fromPort) {
    if (packet.length != 1 + kAnswerRandom) {
      dropped++;
      return;
    }
    if (!reachableProven) {
      withoutProofSilent++; // W6: no proof, no packet
      return;
    }
    final now = DateTime.now();
    final entries = <AddressEntry>[];
    for (final n in _confirmed(now)) {
      if (entries.length >= kAddressEntriesAtMost) break;
      if (!_fresh(n, now)) continue;
      // The asker does not need itself.
      if (n.has(from, fromPort)) continue;
      entries.add(AddressEntry.fromNeighbour(n, now, from));
    }
    final b = BytesBuilder()
      ..addByte(kinds.kAnswerAnswer)
      ..add(packet.sublist(1));
    addressListWrite(
        b,
        AddressList(
            own: [for (final a in _own(from)) AddressEntry(a, 0)],
            neighbours: entries));
    final answer = b.toBytes();
    // ONE part packet, like the question — otherwise the answer would be larger.
    if (answer.length > kAnswerAnswerAtMost ||
        answer.length + kHeader > kPayloadAtMost) {
      dropped++;
      return;
    }
    _send(answer, from, fromPort);
    answered++;
  }

  void _onAnswer(Uint8List packet, InternetAddress from, int fromPort) {
    if (packet.length < 1 + kAnswerRandom + 1) {
      dropped++;
      return;
    }
    final open = _open[_hex(packet.sublist(1, 1 + kAnswerRandom))];
    if (open == null ||
        open.address.address != from.address ||
        open.port != fromPort ||
        open.done.isCompleted) {
      dropped++; // never asked, wrong sender or already answered
      return;
    }
    var spot = 1 + kAnswerRandom;
    Uint8List read(int n) {
      if (spot + n > packet.length) {
        throw CardFormatError('Answer too short');
      }
      return Uint8List.sublistView(packet, spot, spot += n);
    }

    try {
      final entries = addressListRead(read);
      if (spot != packet.length) {
        throw CardFormatError('${packet.length - spot} B zu viel');
      }
      open.done.complete(entries);
    } on CardFormatError catch (e) {
      dropped++;
      _report?.call('Board answer discarded: $e');
    }
  }

  static bool _fresh(Neighbour n, DateTime now) =>
      now.difference(n.last) < kConfirmedAtMost;

  static String _who(InternetAddress a, int port) => '${a.address}|$port';

  static String _hex(Uint8List b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
}
