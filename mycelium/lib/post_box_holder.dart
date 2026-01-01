import 'dart:async';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/device_records.dart' show DeviceRecords;
import 'package:mycelium/post_box_hand_out.dart';
import 'package:mycelium/silence.dart' show Silence;
import 'package:mycelium/post_box_proof.dart';
import 'package:mycelium/post_box_proof_of_work.dart';
import 'package:mycelium/post_box_disk.dart';
import 'package:mycelium/post_box_holder_answers.dart';
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/update_manifest_compartment.dart' show isManifestValue, kManifestAtMost;

export 'package:mycelium/post_box_holder_answers.dart'
    show Neighbour, Send, kDepositHeader, kHereItIsHeader, kNodeIdentifierLength,
        receiptPacket;

/// The holder role of the post box: what I hold for others.
///
/// Split off from `post_box_deposit.dart` (S385); the cut follows WHO processes a packet:
/// | Role | Packets | File |
/// |---|---|---|
/// | holder | accept 0x30, 0x32 → 0x35, 0x36 → 0x33/0x34, delete receipt | here |
/// | sender | send 0x30, count deposited receipt (0x31) | `post_box_place.dart` |
/// | collector | send 0x32, 0x35 → 0x36, accept 0x33/0x34/0x37, send 0x31 | `post_box_collect.dart` |
///
/// **Handed out and deleted only against a proof** (S385, B1/B2):
/// whoever collects answers a task of this holder per value with the
/// secret day key whose day value he names (S391, proposal M).
/// Format and check are in `post_box_proof.dart`; here are the
/// open tasks and the proven collections.
///
/// **The holder sees no identifier** (§8.2): holding, counting and writing to
/// disk happens solely by the 16-B day value.
///
/// 0x31 carries two roles; the switch is in the deposit, which knows its own
/// running deposits — only the rest arrives here. [_Entry.content] stays opaque.

/// The cap per day value (§8.2: 100 packets).
const int kAtMostProValue = 100;
const Duration kAtMostAge = Duration(days: 7);

/// How long a task stays open and a proven collection stays entitled to
/// delete: room for a hand-out entry by entry and late delete receipts. A
/// hand-out that outlasts it has its later deletions refused: those entries
/// come again at the next collection.
const Duration kProofDeadline = Duration(seconds: 30);

/// At most this many open tasks — and separately this many proven
/// collections — a holder keeps (V4.2 R-2), ≈ 100 KB per table. On overflow
/// the oldest drops: a flood delays a collection, it captures nothing.
const int kAtMostOpen = 1024;

class _Entry {
  final Uint8List id;

  /// The day value of this entry — hex in the key of `_storage`, here the
  /// 16 bytes that go to disk.
  final Uint8List value;
  final Uint8List content;
  final DateTime inserted;
  _Entry(this.id, this.value, this.content, this.inserted);
}

/// An open task: to whom, for which values, until when — and the question it
/// was issued for: every packet sent back under it names that (§8.2).
typedef _Task = ({String source, Set<String> values, DateTime until, Uint8List request});
typedef _Proven = ({Uint8List pk, Uint8List random, DateTime until});

class PostBoxHolder {
  final Send send;
  final DateTime Function() now;

  /// Value (hex) -> entries, oldest first. Mirror of what lies on
  /// the [_disk] — if there is one.
  final Map<String, List<_Entry>> _storage = {};

  /// The disk, or `null` — then everything stays in memory.
  PostBoxDisk? _disk;

  /// id (hex) -> value (hex), for the delete receipt without list search.
  final Map<String, String> _idToValue = {};

  /// Open tasks: random (hex) -> to whom, for which values, until when.
  final Map<String, _Task> _tasks = {};

  /// Proven collections: `quelle|wert(hex)` -> day pubkey and random.
  final Map<String, _Proven> _proven = {};

  /// Hand-outs running right now (`quelle|wert`), and of those the ones a
  /// proof was repeated for meanwhile, with that proof's question: no second
  /// runs beside the first, the repetition is answered ONCE after it (§8.2).
  final Set<String> _running = {};
  final Map<String, Uint8List> _again = {};

  /// How many deposits this holder has accepted — pure
  /// diagnostics, so that the re-deposit loop from S384 is measurable.
  int deposits = 0;

  /// Entries pushed out by the per-value cap [kAtMostProValue] — eviction
  /// under budget pressure, which §21.3.3 item 4 requires to be visible in
  /// the network statistics (§25). Expiry by age is not counted.
  int evicted = 0;

  /// Packets held right now, over every value (§25.6 "post-box packets held").
  int get held => _storage.values.fold(0, (a, l) => a + l.length);

  /// The same, summed over every holder of this process: the app reads it
  /// (one host per device, §4.5.1), because the holder instance sits behind
  /// the node's deposit and has no outside reader.
  static int evictedInProcess = 0;

  /// What this holder did not take, counted and named ([HolderLog]).
  final HolderLog log;

  /// Without [records] everything stays in memory. With them (in the app
  /// the device database, `device_records.dart`) the constructor READS and
  /// throws [DepositError] instead of a half-filled holder.
  PostBoxHolder({
    required this.send,
    required this.now,
    required this.nodeIdentifier,
    DeviceRecords? records,
    void Function(String)? report,
    Silence? silence,
  })  : log = HolderLog(report),
        _silent = HandOutSilence(silence ?? Silence()) {
    if (records == null) return;
    final p = PostBoxDisk.on(records);
    // The deadline applies HERE too: a holder that restarts keeps nothing forever.
    for (final s in p.load(limit: now().subtract(kAtMostAge))) {
      final valueHex = _hex(s.value);
      _storage
          .putIfAbsent(valueHex, () => [])
          .add(_Entry(s.id, s.value, s.content, s.inserted));
      _idToValue[_hex(s.id)] = valueHex;
    }
    _disk = p; // only now: an error while loading must not overwrite anything
  }

  /// The node identifier ([kNodeIdentifierLength] B) in every answer (`0x31`, `0x35`), B1.
  final Uint8List nodeIdentifier;
  final HandOutSilence _silent; // §11.3a for the hand-out

  /// One row per held packet (v4_2 §4.5.3): a change touches only its own
  /// row, never the stock (S407-BOOTSTRAPSPEICHER); without disk a no-op. A
  /// slow write is noted ([HolderLog.saved]).
  void _put(_Entry e) {
    final p = _disk;
    if (p == null) return;
    final watch = Stopwatch()..start();
    p.put((id: e.id, value: e.value, content: e.content, inserted: e.inserted));
    log.saved(watch.elapsedMilliseconds, 1);
  }

  void _drop(_Entry e) => _disk?.drop(e.id);

  /// 0x30: `Sorte | id | Tageswert | Nachweis 16 | Inhalt`. Silent only
  /// without a valid proof (§8.2); every other deposit not taken is refused
  /// with `0x37` naming its id (`post_box_holder_answers.dart`).
  void onDeposit(Uint8List packet, Neighbour from) {
    if (packet.length < kDepositHeader) return log.discarded(DepositDiscard.length, from);
    var i = 1;
    final id = packet.sublist(i, i += kIdLength);
    final value = packet.sublist(i, i += kValueLength);
    final proofOfWork = packet.sublist(i, i += kProofOfWorkLength);
    final content = packet.sublist(i);
    // FIRST: without a valid proof no receipt, no space, not even
    // information on whether the id is already known (F3/B4) — silently.
    if (!depositProofOfWorkCarries(id, value, content, proofOfWork)) {
      return log.discarded(DepositDiscard.proofOfWork, from,
          detail: () => depositProofOfWorkWindow(id, value, content, proofOfWork));
    }
    final valueHex = _hex(value);
    // A known id is never bent (proposal B1, second consequence): under
    // another value the real entry would afterwards no longer be
    // deletable by receipt. The same value: a duplicate, only acknowledge.
    final known = _idToValue[_hex(id)];
    if (known != null) {
      if (known != valueHex) return _refuseDeposit(DepositDiscard.idElsewhere, id, value, from);
      send(receiptPacket(id, nodeIdentifier), from);
      return;
    }
    // The public manifest compartment: checked, only the newest (decision 20,
    // B-2); §8.2 "cannot read the content" is for private post — the manifest
    // is public. The held sequence is acknowledged: this holder holds it.
    if (isManifestValue(value)) {
      switch (_manifestAdmits(valueHex, content)) {
        case Admit.same:
          log.sameHeld(from);
          send(receiptPacket(id, nodeIdentifier), from);
          return;
        case Admit.older:
          return _refuseDeposit(DepositDiscard.manifestOlder, id, value, from);
        case Admit.invalid:
          return _refuseDeposit(DepositDiscard.manifestInvalid, id, value, from);
        case Admit.yes:
      }
    }
    deposits++;
    final list = _storage.putIfAbsent(valueHex, () => []);
    _purge(list);
    final entry = _Entry(id, value, content, now());
    list.add(entry);
    _idToValue[_hex(id)] = valueHex;
    while (list.length > kAtMostProValue) {
      final old = list.removeAt(0); // oldest in first, out first
      _drop(old);
      _idToValue.remove(_hex(old.id));
      evicted++;
      evictedInProcess++;
    }
    // Written BEFORE the receipt: the receipt is the promise that I hold
    // the piece.
    _put(entry);
    send(receiptPacket(id, nodeIdentifier), from);
  }

  /// A deposit with a valid proof that this holder does not take: answered,
  /// never silent (§11.3a) — `0x37` with the deposit's id as request.
  void _refuseDeposit(DepositDiscard why, Uint8List id, Uint8List value, Neighbour from) {
    log.discarded(why, from);
    send(refusalPacket(value, id), from);
  }

  /// The manifest check ([manifestAgainst], decision 20); clears what it
  /// displaces when it admits.
  Admit _manifestAdmits(String valueHex, Uint8List content, {bool orSame = false}) {
    final held = _storage[valueHex];
    final r = manifestAgainst(content, held?.lastOrNull?.content, orSame: orSame);
    if (r == Admit.yes && held != null) {
      for (final e in held) {
        _idToValue.remove(_hex(e.id));
        _drop(e);
      }
      held.clear();
    }
    return r;
  }

  /// §26.5.4 (owner 07.10.2026): a node holding a verified manifest keeps it
  /// in its OWN post box under the public value — no packet, no proof of
  /// computation, the check of [onDeposit]. The same sequence renews the
  /// entry: the retention of §8.2 runs from the last time the node knew it.
  bool holdOwn(Uint8List value, Uint8List content) {
    if (!isManifestValue(value) || content.length > kManifestAtMost) return false;
    final valueHex = _hex(value);
    if (_manifestAdmits(valueHex, content, orSame: true) != Admit.yes) return false;
    final id = SodiumFFI().sha256(content).sublist(0, kIdLength);
    final entry = _Entry(
        id, Uint8List.fromList(value), Uint8List.fromList(content), now());
    _storage.putIfAbsent(valueHex, () => []).add(entry);
    _idToValue[_hex(id)] = valueHex;
    _put(entry);
    return true;
  }

  /// 0x32 `Sorte | Anzahl | 7 × Wert | Anfragekennung`: NO handing out, only ONE
  /// task (41 B) for all asked values, naming this question. Whether something
  /// lies there is learned only by whoever has proven himself per value.
  void onCollect(Uint8List packet, Neighbour from) {
    final values = collectValuesRead(packet);
    if (values == null) return;
    final random = SodiumFFI().randomBytes(kRandomLength);
    final request = collectRequestId(packet);
    final t = now();
    _tasks.removeWhere((_, a) => !a.until.isAfter(t));
    _tasks[_hex(random)] = (
      source: _source(from),
      values: {for (final w in values) _hex(w)},
      until: t.add(kProofDeadline),
      request: request,
    );
    while (_tasks.length > kAtMostOpen) {
      _tasks.remove(_tasks.keys.first);
    }
    send(taskPacket(random, nodeIdentifier, request), from);
  }

  /// 0x36: the proof for ONE value of a task. If it holds, the
  /// holder hands out what lies under this value; otherwise it refuses the
  /// value explicitly (`0x37`, 25 B, smaller than the proof) — a holder never
  /// stays silent to a request (owner, 30.09.2026). Only an unparseable
  /// packet stays unanswered (§11.6).
  void onProof(Uint8List packet, Neighbour from) {
    final b = proofRead(packet);
    if (b == null) return;
    final randomHex = _hex(b.random);
    final a = _tasks[randomHex];
    final source = _source(from);
    final valueHex = _hex(b.value);
    // A task this holder does not know — or one of another source — names no
    // question: refused with the identifier left zero (§8.2).
    if (a == null || a.source != source) {
      return _refuse(b.value, from, Uint8List(kRequestIdLength));
    }
    // The task belongs to one question of one collector and lives until its
    // deadline; a proof repeated under it is answered as the first was (§8.2).
    if (!a.values.contains(valueHex) || !a.until.isAfter(now()) || !proofCarries(b)) {
      return _refuse(b.value, from, a.request);
    }
    final key = '$source|$valueHex';
    // Under the manifest compartment nothing is ever deleted (§26.5.4): no proof to remember.
    if (!isManifestValue(b.value)) {
      final t = now();
      _proven.removeWhere((_, x) => !x.until.isAfter(t));
      _proven.remove(key);
      _proven[key] =
          (pk: b.pk, random: b.random, until: t.add(kProofDeadline));
      while (_proven.length > kAtMostOpen) {
        _proven.remove(_proven.keys.first);
      }
    }
    _running.contains(key) ? _again[key] = a.request : _answer(b.value, key, from, a.request);
  }

  void _answer(Uint8List value, String key, Neighbour from, Uint8List request) {
    _running.add(key);
    unawaited(_handOut(value, _hex(value), from, request).whenComplete(() {
      _running.remove(key);
      if (_again.remove(key) case final again?) _answer(value, key, from, again);
    }));
  }

  /// Entry by entry, under the flow of §11.3, never as a burst (§8.2): each
  /// 0x33 waits until the one before it has ended (S398 OP-33 R9: a burst
  /// brought 5/100 and 14/100). [request]: the question of the proof's task.
  Future<void> _handOut(
      Uint8List value, String valueHex, Neighbour from, Uint8List request) async {
    final list = _storage[valueHex];
    if (list != null) _purge(list);
    if (list == null || list.isEmpty) {
      send((BytesBuilder()..addByte(kinds.kNothingThere)..add(value)..add(request))
          .toBytes(), from);
      return;
    }
    // Copy: a 0x31 mutates the list. Gone is not handed out (S411); announced: came + left.
    final copy = List.of(list);
    bool held(_Entry x) => _idToValue.containsKey(_hex(x.id));
    var came = 0;
    for (final e in copy.where(held)) {
      final p = BytesBuilder()
        ..addByte(kinds.kHereItIs)
        ..add(value)
        ..add(e.id)
        ..addByte(came++ + copy.skipWhile((x) => !identical(x, e)).where(held).length)
        ..add(request)
        ..add(e.content);
      final sending = send(p.toBytes(), from);
      if (sending is! Future) continue; // a send without flow (probes)
      // Unreachable, the bound for others, or the collector silent (§11.3a,
      // `post_box_hand_out.dart`): stop — no `0x37` (owner 30.09.2026).
      if (!_silent.ended(from, await sending)) return;
    }
  }

  /// 0x31 `Sorte | id | Zeichnung` as delete receipt. Deleted only
  /// if THIS source has proven itself for the value of the entry and the
  /// signature with the proven day pubkey is over exactly this id.
  void onDeleteReceipt(Uint8List packet, Neighbour from) {
    if (packet.length != kDeleteReceiptLength) return;
    final idHex = _hex(packet.sublist(1, 1 + kIdLength));
    final valueHex = _idToValue[idHex];
    if (valueHex == null) return;
    final list = _storage[valueHex];
    final i = list?.indexWhere((e) => _hex(e.id) == idHex) ?? -1;
    if (i < 0) return;
    // §8.2: the public manifest compartment is read, never deleted — not even
    // on a valid signature.
    if (isManifestValue(list![i].value)) return;
    final s = _proven['${_source(from)}|$valueHex'];
    if (s == null || !s.until.isAfter(now())) return;
    if (!deleteReceiptCarries(packet, list[i].value, s.random, s.pk)) return;
    _drop(list.removeAt(i));
    _idToValue.remove(idHex);
  }

  /// `0x37 | value | request`: this value is not handed out now.
  void _refuse(Uint8List value, Neighbour to, Uint8List request) =>
      send(refusalPacket(value, request), to);

  /// Throws away what is older than [kAtMostAge], each with its row.
  void _purge(List<_Entry> list) {
    final limit = now().subtract(kAtMostAge);
    list.removeWhere((e) {
      final expired = e.inserted.isBefore(limit);
      if (expired) {
        _idToValue.remove(_hex(e.id));
        _drop(e);
      }
      return expired;
    });
  }
}

String _source(Neighbour n) => '${n.$1.address}:${n.$2}';

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
