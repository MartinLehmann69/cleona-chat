import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/post_box_proof.dart';
import 'package:mycelium/post_box_holder.dart';
import 'package:mycelium/post_box_runs.dart';
import 'package:mycelium/post_box_proof_of_work.dart';
import 'package:mycelium/post_box_disk.dart';
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/update_manifest_compartment.dart' show isManifestValue;

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
/// holds something sends it per value as 0x33 (one per entry), otherwise 0x34. Bob acknowledges every piece INDIVIDUALLY — for that
/// 0x31 is reused in the opposite direction, no sixth code
/// needed. Deletion happens only AFTER this receipt, otherwise an
/// entry would be gone without replacement if the receipt packet were lost.
///
/// No point in time for [PostBoxDeposit.collect] in this file — that
/// is intentional: a permanent clock was the error of the old layer (plan +
/// clock, 49,000 lines, 12 minutes/message). [collect] is ONE request;
/// the caller decides WHEN. No timer here, no idle traffic.
///
/// Every neighbour is at the same time deposit site, sender and collector — one
/// instance covers all three roles. The HOLDER ROLE is in
/// `post_box_holder.dart` (S385, step 0: the line budget); here
/// remain sender and collector and the allocation of the packets. [content]
/// stays opaque throughout for both files.
///
/// What a holder holds for others survives a restart: with
/// `directory` + `key` in the constructor [PostBoxDisk] writes it
/// encrypted and atomically to disk, and at start it comes back from
/// there — minus whatever has exceeded the retention period of
/// [kAtMostAge]. WITHOUT `directory` the deposit works
/// as before purely in memory and touches no file.
/// The file format is in `post_box_disk.dart`.

const Duration kDepositDeadline = Duration(milliseconds: 800);
const Duration kCollectDeadline = Duration(seconds: 2);
/// One length, two users: here for the packets, in
/// `post_box_disk.dart` for the file format. Therefore taken from there,
/// not written down here once more.
const int _kIdLength = kIdLength;

class PostBoxDeposit {
  final Send send;
  final DateTime Function() now;
  final Random _random;

  /// An own request is completed, and these asked holders
  /// did NOT answer (V4.2 §22.7.1, downward edge of
  /// readiness). Reported only at the end of the deadline that is running
  /// anyway — or immediately if all have answered, then with nobody.
  /// No timer of its own, no packet.
  final void Function(List<Neighbour> withoutAnswer)? onMute;

  /// An asked holder has answered with its node identifier (hex)
  /// (`0x31` to an own deposit, `0x35` to an own query) — the
  /// readiness thus counts it per node (B1). No packet.
  final void Function(InternetAddress from, int port, String node)? onNode;

  /// What I hold for others — see `post_box_holder.dart`.
  late final PostBoxHolder _holder;

  /// Own running [deposit] requests, by id (hex).
  final Map<String, DepositRun> _deposits = {};

  /// At most one own [collect] request at a time; the node
  /// asks its identities one after the other (`node_post_box.dart`).
  CollectionRun? _collection;

  /// How many deposits this holder has accepted — pure
  /// diagnostics, so that the re-deposit loop from S384 is measurable.
  int get deposits => _holder.deposits;

  /// Whether a [collect] request is currently running. Lives here because the
  /// caller could otherwise only learn it via the thrown [StateError]
  /// — an exception for flow control is not information.
  /// Measured 14.09.2026: the edge „new neighbour" fires per neighbour, the
  /// second throw went through an `unawaited` and took the daemon down with it.
  bool get collectRuns => _collection != null;

  /// Without [directory] everything stays in memory — so it was until now, and
  /// so it stays for every caller that passes nothing. With [directory]
  /// [key] is mandatory; details and [DepositError] at
  /// [PostBoxHolder].
  PostBoxDeposit({
    required this.send,
    this.now = DateTime.now,
    Random? random,
    Directory? directory,
    Uint8List? key,
    this.onMute,
    this.onNode,
    /// The node identifier that this holder names in its answers — the
    /// node gives that of its call. Without it one is rolled.
    Uint8List? nodeIdentifier,
  }) : _random = random ?? Random.secure() {
    _holder = PostBoxHolder(
        send: send,
        now: now,
        directory: directory,
        key: key,
        nodeIdentifier: nodeIdentifier ??
            Uint8List.fromList(List<int>.generate(
                kNodeIdentifierLength, (_) => _random.nextInt(256))));
  }

  /// Deposits [content] (bytes opaque for the recipient) with [withWhom]
  /// under the 16-B value [underValue] — the day value of the recipient
  /// (`dayValue(tagesPk)`, `pair.dart`) or the manifest compartment. Done
  /// as soon as TWO different nodes have acknowledged — the return value
  /// names the actual number of NODES. Throws [ArgumentError] on
  /// wrong value length.
  Future<(bool done, int acknowledged)> deposit({
    required Uint8List content,
    required Uint8List underValue,
    required List<Neighbour> withWhom,
    Duration deadline = kDepositDeadline,
  }) {
    if (underValue.length != kValueLength) {
      throw ArgumentError(
          'Value must be $kValueLength B, was ${underValue.length}');
    }
    final id = _randomId();
    final idHex = asHex(id);
    final h = DepositRun();
    _deposits[idHex] = h;
    if (withWhom.isEmpty) {
      _depositComplete(idHex); // nobody there: nothing to compute
      return h.result.future;
    }
    // First compute (F3), then send, then the deadline: the deadline measures the
    // answer time of the holders, not the own computing time. If something fails,
    // the deposit ends with (false, 0) instead of with an error that
    // nobody catches in the `unawaited` of the ladder (node.dart, post box step).
    unawaited(() async {
      try {
        final proofOfWork = await depositProofOfWork(id, underValue, content);
        final packet = (BytesBuilder()
              ..addByte(kinds.kDeposit)
              ..add(id)
              ..add(underValue)
              ..add(proofOfWork)
              ..add(content))
            .toBytes();
        // The run state stands BEFORE dispatch: a receipt that arrives while still in
        // the send loop would otherwise find an empty list of the
        // asked and close the run without deadline and without mute ones.
        h
          ..packet = packet
          ..deadlineDuration = deadline
          ..asked = List.of(withWhom);
        h.deadline = Timer(deadline, () => _depositComplete(idHex));
        for (final n in withWhom) {
          send(packet, n);
        }
      } on Object {
        _depositComplete(idHex);
      }
    }());
    return h.result.future;
  }

  /// [isFinal] = the deadline is over (or there was nobody to ask). Otherwise
  /// two have acknowledged: the result stands, but the third holder has
  /// time until the end of the deadline — whoever already calls him „mute" now tips
  /// readiness briefly down with every deposit and right back up again.
  void _depositComplete(String idHex, {bool isFinal = true}) {
    final h = _deposits[idHex];
    if (h == null) return;
    if (!h.result.isCompleted) {
      h.result.complete((h.node >= 2, h.node));
    }
    if (!isFinal && h.acknowledged.length < h.asked.length) return;
    h.deadline?.cancel();
    final mute = [
      for (final n in h.asked)
        if (!h.acknowledged.containsKey(neighbourKey(n))) n
    ];
    // §11.8 (E2): failed only after the SECOND sending. The result
    // already stands (above); the repetition only decides about „mute".
    if (isFinal && mute.isNotEmpty && _repeat(h, mute)) {
      h.deadline = Timer(h.deadlineDuration, () => _depositComplete(idHex));
      return;
    }
    _deposits.remove(idHex);
    if (mute.isNotEmpty) onMute?.call(mute);
  }

  /// Asks [withWhom] for everything under the values of [ask] (1–7; for
  /// an identity [ownAsk], for the manifest compartment [compartmentQuestion]),
  /// proves itself per value against the task of each holder (0x35 → 0x36) and
  /// acknowledges every piece individually, signed with the day key
  /// (prerequisite for deleting). Waits at most [deadline], but closes
  /// immediately as soon as all have answered for all values.
  Future<List<Uint8List>> collect({
    required List<Question> ask,
    required List<Neighbour> withWhom,
    Duration deadline = kCollectDeadline,
  }) {
    if (_collection != null) throw StateError('collect() is already running');
    final packet = collectPacket(ask, SodiumFFI().randomBytes(kCollectLength));
    final a = CollectionRun(List.of(withWhom), ask);
    _collection = a;
    // Arm the deadline BEFORE dispatch: a very fast answer
    // could otherwise already pass as "complete" during the send loop,
    // before the remaining packets have even been sent.
    a.deadline = Timer(deadline, () => _collectComplete(a));
    a
      ..packet = packet
      ..deadlineDuration = deadline;
    for (final n in withWhom) {
      send(packet, n);
    }
    _collectComplete(a); // covers withWhom.isEmpty immediately
    return a.result.future;
  }

  void _collectComplete(CollectionRun a) {
    final deadlineRunsStill = a.deadline != null && a.deadline!.isActive;
    if (!a.complete && deadlineRunsStill) return;
    // Whoever's task (0x35) came has answered — the first answer of each
    // holder to 0x32 (`post_box_holder.dart` beiAbholen).
    final mute = [
      for (final n in a.holder)
        if (!a.random.containsKey(neighbourKey(n))) n
    ];
    // §11.8 (E2): whoever has not answered gets the request ONE
    // second time; the collection waits at most one deadline more for it.
    if (!a.complete && mute.isNotEmpty && _repeat(a, mute)) {
      a.deadline = Timer(a.deadlineDuration, () => _collectComplete(a));
      return;
    }
    if (identical(_collection, a)) _collection = null;
    a.deadline?.cancel();
    if (a.result.isCompleted) return;
    a.result.complete(a.found);
    if (mute.isNotEmpty) onMute?.call(mute);
  }

  /// A packet of one of the five kinds of this file; everything else is ignored.
  void receive(Uint8List packet, InternetAddress from, int fromPort) {
    if (packet.isEmpty) return;
    final n = (from, fromPort);
    switch (packet[0]) {
      case kinds.kDeposit:
        _holder.onDeposit(packet, n);
      case kinds.kDeposited:
        _onAcknowledged(packet, n);
      case kinds.kCollect:
        _holder.onCollect(packet, n);
      case kinds.kHereItIs:
        _onHereItIs(packet, n);
      case kinds.kNothingThere:
        _onNothingThere(packet, n);
      case kinds.kCollectTask:
        _onTask(packet, n);
      case kinds.kCollectProof:
        _holder.onProof(packet, n);
    }
  }

  /// 0x35: the task of an asked holder — answered with one
  /// proof for each asked value.
  void _onTask(Uint8List packet, Neighbour from) {
    if (packet.length != 1 + kRandomLength + kNodeIdentifierLength) return;
    final a = _collection;
    if (a == null) return;
    final s = neighbourKey(from);
    if (!a.asked.contains(s) || a.random.containsKey(s)) return;
    final random = packet.sublist(1, 1 + kRandomLength);
    a.random[s] = random;
    onNode?.call(from.$1, from.$2, asHex(packet.sublist(1 + kRandomLength)));
    for (final f in a.ask.values) {
      send(proofPacket(f, random), from);
    }
  }

  void _onAcknowledged(Uint8List packet, Neighbour from) {
    if (packet.length < 1 + _kIdLength) return;
    final idHex = asHex(packet.sublist(1, 1 + _kIdLength));
    final h = _deposits[idHex];
    if (h != null) {
      if (packet.length != 1 + _kIdLength + kNodeIdentifierLength) return;
      final node = asHex(packet.sublist(1 + _kIdLength));
      h.acknowledged[neighbourKey(from)] = node;
      onNode?.call(from.$1, from.$2, node);
      if (h.node >= 2) {
        _depositComplete(idHex, isFinal: false);
      }
      return;
    }
    // No running deposit with this id: then it is the
    // delete receipt of a collector for an own entry (0x31
    // carries both roles, distinguished only by the id).
    _holder.onDeleteReceipt(packet, from);
  }

  /// 0x33 `Sorte | Wert | id | Anzahl | Inhalt`.
  void _onHereItIs(Uint8List packet, Neighbour from) {
    if (packet.length < kHereItIsHeader) return;
    var i = 1;
    final value = packet.sublist(i, i += kValueLength);
    final id = packet.sublist(i, i += _kIdLength);
    final count = packet[i++];
    final content = packet.sublist(i);
    // Only what is TAKEN OVER is acknowledged (proposal holder, B3). Until
    // S385 the receipt went out before this check: a sending that
    // arrived after the end of the collection was acknowledged, deleted by the holder
    // and discarded here — a loss without an attacker. Without
    // receipt the holder keeps the piece, the next collection brings it.
    final a = _collection;
    if (a == null) return;
    final key = neighbourKey(from);
    if (!a.asked.contains(key)) return; // B6: not asked
    // Only from a holder whose task is answered: otherwise there would be
    // no random value to which the delete receipt can be bound.
    final random = a.random[key];
    if (random == null) return;
    final question = a.ask[asHex(value)];
    if (question == null) return; // not asked
    final per = '$key|${asHex(value)}';
    // "received" counts deliveries of THIS neighbour under this value, independent of the
    // global duplicate check: all three neighbours of a deposit
    // carry the same id (replica) — otherwise a known-id neighbour would count
    // as "never answered", and [collect] would always wait the full deadline.
    a.received[per] = (a.received[per] ?? 0) + 1;
    a.expected[per] = count;
    if (a.seen.add(asHex(id))) a.found.add(content);
    // Now it lies in [found] (or already lay there): taken over. Under
    // the manifest compartment no delete receipt — it is never deleted (§8.2).
    final pair = question.pair;
    if (pair != null && !isManifestValue(value)) {
      send(deletePacket(pair, value, random, id), from);
    }
    _collectComplete(a);
  }

  /// 0x34 `Sorte | Wert`.
  void _onNothingThere(Uint8List packet, Neighbour from) {
    if (packet.length != 1 + kValueLength) return;
    final a = _collection;
    if (a == null) return;
    final key = neighbourKey(from);
    if (!a.asked.contains(key)) return; // B6: not asked
    if (!a.random.containsKey(key)) return; // before the proof: not from the holder
    final valueHex = asHex(packet.sublist(1));
    if (!a.ask.containsKey(valueHex)) return;
    a.expected['$key|$valueHex'] = 0;
    _collectComplete(a);
  }

  /// The one repetition to [mute]; `false` if it already happened.
  bool _repeat(Repeatable run, List<Neighbour> mute) {
    final packet = run.packet;
    if (run.repeated || packet == null) return false;
    run.repeated = true;
    for (final n in mute) {
      send(packet, n);
    }
    return true;
  }

  Uint8List _randomId() => Uint8List.fromList(
      List<int>.generate(_kIdLength, (_) => _random.nextInt(256)));
}
