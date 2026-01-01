import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:mycelium/device_records.dart' show DeviceRecords;
import 'package:mycelium/post_box_proof.dart';
import 'package:mycelium/post_box_holder.dart';
import 'package:mycelium/post_box_collect.dart';
import 'package:mycelium/post_box_place.dart';
import 'package:mycelium/post_box_runs.dart';
import 'package:mycelium/post_box_log.dart';
import 'package:mycelium/post_box_disk.dart';
import 'package:mycelium/silence.dart';
import 'package:mycelium/split_flow.dart' show SendEnd;
import 'package:mycelium/kinds.dart' as kinds;

export 'package:mycelium/post_box_proof.dart'
    show Question, DayPair, ownAsk, compartmentQuestion, kAtMostValues;
export 'package:mycelium/post_box_holder.dart'
    show
        Neighbour,
        Send,
        kAtMostProValue,
        kAtMostAge,
        kDepositHeader,
        kHereItIsHeader;

/// P6 — the post box for the absent recipient.
///
/// Bob is off. Alice deposits with three neighbours (0x30); each stores the
/// bytes under Bob's today's day value (S391, proposal M: 16 B from Bob's
/// day pubkey, `pair.dart`) and acknowledges immediately (0x31). TWO of three
/// suffice — one may fail. When Bob comes back, he asks the same
/// neighbours under the day values of the last seven days (0x32); whoever
/// holds something sends it per value as 0x33 (one per entry, each naming
/// how many it hands out), otherwise 0x34. Bob acknowledges every piece
/// INDIVIDUALLY — for that 0x31 is reused in the opposite direction, no
/// sixth code needed. Deletion happens only AFTER this receipt, otherwise an
/// entry would be gone without replacement if the receipt packet were lost.
///
/// **Events, not clocks** (§8.2, D-44; S399 step 4). Placing ends at the
/// second `0x31`, or not placed when the transmission to every holder has
/// ended without it — never on a deadline, never repeated. The collection
/// (`post_box_collect.dart`) is a conversation per holder: a holder is done
/// when it has handed out what it announced or its link ended unanswered,
/// and no holder waits for another.
///
/// No point in time for [PostBoxDeposit.collect] in this file — that
/// is intentional: a permanent clock was the error of the old layer (plan +
/// clock, 49,000 lines, 12 minutes/message). [collect] is ONE request;
/// the caller decides WHEN. No timer here, no idle traffic.
///
/// Every neighbour is deposit site, sender and collector — one instance covers
/// all three roles: the holder in `post_box_holder.dart`, the collector in
/// `post_box_collect.dart`, the sender in `post_box_place.dart`; this class
/// holds them and dispatches the packets. [content] stays opaque.
///
/// What a holder holds for others survives a restart: with `records` in
/// the constructor (in the app the device database) [PostBoxDisk] writes
/// it there as a whole, and at start it comes back from there — minus
/// whatever has exceeded the retention period of [kAtMostAge]. WITHOUT
/// `records` the deposit works purely in memory.

class PostBoxDeposit {
  final Send send;
  final DateTime Function() now;
  final Random _random;

  /// Where a request that expects an answer is sent, repeated and given up
  /// (V4.2 §11.3a): the deposit's `0x30` and the collector's questions. It
  /// declares a failed address to the readiness; nothing here counts.
  /// Without one (probes) nothing is declared failed.
  final Silence silence;

  /// An asked holder has answered with its node identifier (hex)
  /// (`0x31` to an own deposit, `0x35` to an own query) — the
  /// readiness thus counts it per node (B1). No packet.
  final void Function(InternetAddress from, int port, String node)? onNode;

  /// The log (O2, `post_box_log.dart`) — decides nothing.
  final void Function(String)? report;

  /// What I hold for others — see `post_box_holder.dart`.
  late final PostBoxHolder _holder;

  /// What I collect for myself — see `post_box_collect.dart`.
  late final PostBoxCollector _collector;

  /// Names packets discarded for their length — see [LengthLog].
  late final LengthLog _lengths = LengthLog(report);

  /// The bound of the own running deposits — [kDepositsAtMost]; a probe
  /// sets a smaller one.
  final int depositsAtMost;

  /// What I place for myself — see `post_box_place.dart`.
  late final PostBoxPlacing _placing;

  /// How many own deposits are running — diagnostics.
  int get depositRuns => _placing.runs;

  /// Whether [close] has run. A run it ended did not end by the events of
  /// §8.2 — the node stopped: nothing is sent again on its account
  /// (`mailbox_outbound.dart`).
  bool get closed => _closed;
  bool _closed = false;

  /// The node stops: every own run ends with what it has, without counting
  /// a use; the collector ends its conversations ([PostBoxCollector.close]).
  void close() {
    _closed = true;
    _placing.close();
    _collector.close();
  }

  /// An edge of §8.2 begins — see [PostBoxCollector.edge].
  void collectEdge() => _collector.edge();

  /// How many deposits this holder has accepted — pure
  /// diagnostics, so that the re-deposit loop from S384 is measurable.
  int get deposits => _holder.deposits;

  /// Packets this node holds right now — the network statistics (§25.6).
  int get held => _holder.held;

  /// The manifest in the own post box (§26.5.4) — see [PostBoxHolder.holdOwn].
  bool holdOwn(Uint8List value, Uint8List content) =>
      _holder.holdOwn(value, content);

  /// Whether a [collect] question is open at any holder.
  bool get collectRuns => _collector.runs;

  /// Without [records] everything stays in memory; details and
  /// [DepositError] at [PostBoxHolder].
  PostBoxDeposit({
    required this.send,
    this.now = DateTime.now,
    Random? random,
    DeviceRecords? records,
    Silence? silence,
    this.onNode,
    this.report,
    this.depositsAtMost = kDepositsAtMost,
    /// The node identifier that this holder names in its answers — the
    /// node gives that of its call. Without it one is rolled.
    Uint8List? nodeIdentifier,
  })  : _random = random ?? Random.secure(),
        silence = silence ?? Silence() {
    final node = nodeIdentifier ??
        Uint8List.fromList(List<int>.generate(
            kNodeIdentifierLength, (_) => _random.nextInt(256)));
    _holder = PostBoxHolder(
        send: answersLogged(send, report),
        now: now,
        report: report,
        records: records,
        silence: this.silence,
        nodeIdentifier: node);
    _collector = PostBoxCollector(
        send: send, silence: this.silence, onNode: onNode, report: report);
    _placing = PostBoxPlacing(
        send: send,
        silence: this.silence,
        atMost: depositsAtMost,
        ownNode: asHex(node),
        onNode: onNode,
        report: report);
  }

  /// Deposits [content] (bytes opaque for the recipient) with [withWhom]
  /// under the 16-B value [underValue] — the day value of the recipient
  /// (`dayValue(tagesPk)`, `pair.dart`) or the manifest compartment. Done
  /// as soon as TWO different nodes have acknowledged; NOT done once the
  /// transmission to every holder has ended short of two (§8.2) — the return
  /// value names the actual number of NODES. Throws [ArgumentError] on wrong
  /// value length. [ended]: asked once the proof of work is ready; `true`
  /// leaves nothing (§7.1).
  ///
  /// The end of a transmission is what [send] returns ([SendEnd]); a single
  /// part has ended 1.1 s after it left (§11.3). A send that returns nothing
  /// (a probe without flow) gives no end, and such a run ends only with the
  /// receipts. [reserve]: the candidates after [withWhom], in their order —
  /// a holder that ends without a receipt gives way to the next of them
  /// while the run is not placed (§8.2, `post_box_place.dart`). [sending]: a
  /// message's [sendingSeed]; its deposit id hangs on this, not on the bytes.
  Future<(bool done, int acknowledged)> deposit({
    required Uint8List content,
    required Uint8List underValue,
    required List<Neighbour> withWhom,
    List<Neighbour> reserve = const [],
    bool Function()? ended,
    Uint8List? sending,
  }) {
    if (underValue.length != kValueLength) {
      throw ArgumentError(
          'Value must be $kValueLength B, was ${underValue.length}');
    }
    return _placing.deposit(
        content: content,
        underValue: underValue,
        withWhom: withWhom,
        reserve: reserve,
        ended: ended,
        sending: sending);
  }

  /// Asks [withWhom] for everything under the values of [ask] (1–7; for
  /// an identity [ownAsk], for the manifest compartment [compartmentQuestion]),
  /// proves itself per value against the task of each holder (0x35 → 0x36) and
  /// acknowledges every piece, signed with the day key, to every holder
  /// asked (prerequisite for deleting). A conversation per holder — see
  /// `post_box_collect.dart`; the future completes once every holder is
  /// done. [keep]: read only, no delete receipt (D-40). [onPiece]: where
  /// every piece goes when it arrives.
  Future<List<Uint8List>> collect({
    required List<Question> ask,
    required List<Neighbour> withWhom,
    bool keep = false,
    PieceTaken? onPiece,
  }) =>
      _collector.collect(
          ask: ask, withWhom: withWhom, keep: keep, onPiece: onPiece);

  /// See [PostBoxCollector.beforeRequest] (§11.6 variant A).
  set beforeRequest(void Function(Neighbour holder)? f) =>
      _collector.beforeRequest = f;

  /// See [PostBoxCollector.arriving] (§8.2: no timer while answers arrive).
  set arriving(bool Function(Neighbour holder)? f) => _collector.arriving = f;

  /// Whether a question still stands at [holder], and of [ask] what it was
  /// not asked yet — see [PostBoxCollector.busy], [PostBoxCollector.unasked].
  bool collectBusy(Neighbour holder) => _collector.busy(holder);
  List<Question> collectUnasked(Neighbour holder, List<Question> ask) =>
      _collector.unasked(holder, ask);

  /// A packet of one of the eight kinds of this file; everything else is ignored.
  void receive(Uint8List packet, InternetAddress from, int fromPort) {
    if (packet.isEmpty) return;
    final n = (from, fromPort);
    _lengths.check(packet, n); // log only: a discard for length is named
    switch (packet[0]) {
      case kinds.kDeposit:
        _holder.onDeposit(packet, n);
      case kinds.kDeposited:
        // No running deposit with this id: then it is the delete receipt of
        // a collector for an own entry (0x31 carries both roles,
        // distinguished only by the id).
        if (!_placing.acknowledged(packet, n)) {
          _holder.onDeleteReceipt(packet, n);
        }
      case kinds.kCollect:
        _holder.onCollect(packet, n);
      case kinds.kHereItIs:
        _collector.onHereItIs(packet, n);
      case kinds.kNothingThere:
        _collector.onNothingThere(packet, n);
      case kinds.kRefused:
        if (!_placing.refused(packet, n)) {
          _collector.onNothingThere(packet, n, refused: true);
        }
      case kinds.kCollectTask:
        _collector.onTask(packet, n);
      case kinds.kCollectProof:
        _holder.onProof(packet, n);
    }
  }
}
