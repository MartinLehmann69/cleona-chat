import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:mycelium/device_records.dart' show DeviceRecords;
import 'package:mycelium/post_box_proof.dart';
import 'package:mycelium/post_box_holder.dart';
import 'package:mycelium/post_box_collect.dart';
import 'package:mycelium/post_box_runs.dart';
import 'package:mycelium/post_box_log.dart';
import 'package:mycelium/post_box_proof_of_work.dart';
import 'package:mycelium/post_box_disk.dart';
import 'package:mycelium/split.dart' show endedAfter, kRestPeriod;
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
/// `post_box_collect.dart`, the sender here. [content] stays opaque.
///
/// What a holder holds for others survives a restart: with `records` in
/// the constructor (in the app the device database) [PostBoxDisk] writes
/// it there as a whole, and at start it comes back from there — minus
/// whatever has exceeded the retention period of [kAtMostAge]. WITHOUT
/// `records` the deposit works purely in memory.

/// One length, two users: here for the packets, in
/// `post_box_disk.dart` for the file format. Therefore taken from there,
/// not written down here once more.
const int _kIdLength = kIdLength;

class PostBoxDeposit {
  final Send send;
  final DateTime Function() now;
  final Random _random;

  /// These asked holders did NOT answer an own request (V4.2 §22.7.1,
  /// downward edge of readiness; §11.8 a failed use). A deposit reports
  /// once, when its run has ended; a collection per holder, when its link
  /// ended unanswered or one request for what is missing brought no answer
  /// at all. No timer of its own, no packet.
  final void Function(List<Neighbour> withoutAnswer)? onMute;

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

  /// Own running [deposit] requests, by id (hex), oldest first. At most
  /// [depositsAtMost] (§20.2): beyond it the oldest ends with the receipts
  /// it has, without counting a use. A run leaves when every holder has
  /// acknowledged or its transmission has ended; only a [send] without flow
  /// (probes) gives no end, and such a run stays until its receipts or the
  /// cap.
  final Map<String, DepositRun> _deposits = {};

  /// How many own deposits are running — diagnostics.
  int get depositRuns => _deposits.length;

  /// Whether [close] has run. A run it ended did not end by the events of
  /// §8.2 — the node stopped: nothing is sent again on its account
  /// (`mailbox_outbound.dart`).
  bool get closed => _closed;
  bool _closed = false;

  /// The node stops: every own run ends with what it has, without counting
  /// a use; the collector ends its conversations ([PostBoxCollector.close]).
  void close() {
    _closed = true;
    for (final h in _deposits.values) {
      h
        ..release()
        ..complete();
    }
    _deposits.clear();
    _collector.close();
  }

  /// An edge of §8.2 begins — see [PostBoxCollector.edge].
  void collectEdge() => _collector.edge();

  /// How many deposits this holder has accepted — pure
  /// diagnostics, so that the re-deposit loop from S384 is measurable.
  int get deposits => _holder.deposits;

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
    this.onMute,
    this.onNode,
    this.report,
    this.depositsAtMost = kDepositsAtMost,
    /// The node identifier that this holder names in its answers — the
    /// node gives that of its call. Without it one is rolled.
    Uint8List? nodeIdentifier,
  }) : _random = random ?? Random.secure() {
    _holder = PostBoxHolder(
        send: answersLogged(send, report),
        now: now,
        records: records,
        nodeIdentifier: nodeIdentifier ??
            Uint8List.fromList(List<int>.generate(
                kNodeIdentifierLength, (_) => _random.nextInt(256))));
    _collector = PostBoxCollector(
        send: send, onMute: onMute, onNode: onNode, report: report);
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
  /// receipts.
  Future<(bool done, int acknowledged)> deposit({
    required Uint8List content,
    required Uint8List underValue,
    required List<Neighbour> withWhom,
    bool Function()? ended,
  }) {
    if (underValue.length != kValueLength) {
      throw ArgumentError(
          'Value must be $kValueLength B, was ${underValue.length}');
    }
    final id = _randomId();
    final idHex = asHex(id);
    final h = DepositRun();
    _deposits[idHex] = h;
    while (_deposits.length > depositsAtMost) {
      final old = _deposits.remove(_deposits.keys.first)!
        ..release()
        ..complete();
      report?.call('deposit under ${old.valueShort}: more than '
          '$depositsAtMost runs — the oldest ends with ${old.node} receipt(s)');
    }
    if (withWhom.isEmpty) {
      _depositEnd(idHex); // nobody there: nothing to compute
      return h.result.future;
    }
    // Compute (F3), then send. A failure ends (false, 0), never an error in
    // an `unawaited`.
    unawaited(() async {
      try {
        final proofOfWork = await depositProofOfWork(id, underValue, content);
        if (ended?.call() ?? false) {
          report?.call('deposit dropped — acknowledged before its proof of work (§7.1)');
          _depositEnd(idHex);
          return;
        }
        final packet = (BytesBuilder()
              ..addByte(kinds.kDeposit)
              ..add(id)
              ..add(underValue)
              ..add(proofOfWork)
              ..add(content))
            .toBytes();
        // The run state stands BEFORE dispatch: a receipt that arrives while
        // still in the send loop would otherwise find an empty list of the
        // asked and end the run.
        h
          ..asked = List.of(withWhom)
          ..sentAt = DateTime.now()
          ..valueShort = asHex(underValue).substring(0, 8);
        for (final n in withWhom) {
          final s = send(packet, n);
          if (s is Future) {
            unawaited(s.then((end) => _transmissionEnded(idHex, n, end),
                onError: (Object _) => _transmissionEnded(idHex, n, null)));
          }
        }
      } on Object {
        _depositEnd(idHex);
      }
    }());
    return h.result.future;
  }

  /// The transmission of the `0x30` to [n] ended. A single part (`sent`) has
  /// no end mark: it has ended [endedAfter] its leaving — 1.1 s, the rule of
  /// §11.3 for a sender without end mark or request; never repeated (§8.2).
  void _transmissionEnded(String idHex, Neighbour n, Object? end) {
    final h = _deposits[idHex];
    if (h == null) return;
    if (end == SendEnd.sent) {
      h.waits.add(Timer(endedAfter(kRestPeriod),
          () => _transmissionEnded(idHex, n, SendEnd.unconfirmed)));
      return;
    }
    h.ended.add(neighbourKey(n));
    if (h.finished) _depositEnd(idHex);
  }

  /// The run has ended: every holder acknowledged or its transmission
  /// ended (or there was nobody to ask, or nothing was sent).
  void _depositEnd(String idHex) {
    final h = _deposits.remove(idHex);
    if (h == null) return;
    h
      ..release()
      ..complete();
    if (h.sentAt != null) report?.call(depositOutcome(h, h.valueShort));
    final mute = [
      for (final n in h.asked)
        if (!h.acknowledged.containsKey(neighbourKey(n))) n
    ];
    if (mute.isNotEmpty) onMute?.call(mute);
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
        _onAcknowledged(packet, n);
      case kinds.kCollect:
        _holder.onCollect(packet, n);
      case kinds.kHereItIs:
        _collector.onHereItIs(packet, n);
      case kinds.kNothingThere:
        _collector.onNothingThere(packet, n);
      case kinds.kRefused:
        _collector.onNothingThere(packet, n, refused: true);
      case kinds.kCollectTask:
        _collector.onTask(packet, n);
      case kinds.kCollectProof:
        _holder.onProof(packet, n);
    }
  }

  void _onAcknowledged(Uint8List packet, Neighbour from) {
    if (packet.length < 1 + _kIdLength) return;
    final idHex = asHex(packet.sublist(1, 1 + _kIdLength));
    final h = _deposits[idHex];
    const at = 1 + _kIdLength + kNodeIdentifierLength;
    if (h != null) {
      if (packet.length != at + kRequestIdLength) return;
      final node = asHex(packet.sublist(1 + _kIdLength, at));
      final key = neighbourKey(from);
      ackNoted(h, key); // log only (O2)
      h.acknowledged[key] = node;
      onNode?.call(from.$1, from.$2, node);
      if (h.node >= 2) h.complete(); // placed at the second 0x31 (§8.2)
      if (h.finished) _depositEnd(idHex);
      return;
    }
    // No running deposit with this id: then it is the
    // delete receipt of a collector for an own entry (0x31
    // carries both roles, distinguished only by the id).
    _holder.onDeleteReceipt(packet, from);
  }

  Uint8List _randomId() => Uint8List.fromList(
      List<int>.generate(_kIdLength, (_) => _random.nextInt(256)));
}
