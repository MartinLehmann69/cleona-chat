import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/post_box_proof.dart';
import 'package:mycelium/post_box_proof_of_work.dart';
import 'package:mycelium/post_box_disk.dart';
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/update_manifest_compartment.dart'
    show isManifestValue, manifestVerifier;

/// The holder role of the post box: what I hold for others.
///
/// Split off from `post_box_deposit.dart` (S385, proposal holder, step
/// 0), because both roles together stood at the line budget (399/400) and
/// every safeguard of the holder would have blown it. The cut follows the
/// question WHO processes a packet:
///
/// | Role | Packets | File |
/// |---|---|---|
/// | holder | accept 0x30, 0x32 → 0x35, 0x36 → 0x33/0x34, delete receipt | here |
/// | sender | send 0x30, count deposited receipt (0x31) | `post_box_deposit.dart` |
/// | collector | send 0x32, 0x35 → 0x36, accept 0x33/0x34, send 0x31 | `post_box_deposit.dart` |
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
/// 0x31 carries two roles; the switch is in the deposit, because only it
/// knows the own running deposits. Only what was none of
/// them arrives here. [_Entry.content] stays opaque.

/// A neighbour: only its network address — the neighbour sees only day values
/// and opaque bytes, the caller does not need more here either.
typedef Neighbour = (InternetAddress address, int port);

typedef Send = void Function(Uint8List packet, Neighbour target);

/// The cap per day value (§8.2: 100 packets).
const int kAtMostProValue = 100;
const Duration kAtMostAge = Duration(days: 7);

/// Header of a 0x30 before the content: kind 1 + id 8 + day value 16 +
/// proof of computation 16 = 41 B. The one place where that is written.
const int kDepositHeader = 1 + kIdLength + kValueLength + kProofOfWorkLength;

/// Header of a 0x33 before the content: kind 1 + day value 16 + id 8 + count 1.
const int kHereItIsHeader = 1 + kValueLength + kIdLength + 1;

/// How long a task stays open and a proven collection stays entitled to delete.
/// A collection takes at most `kAbholenFrist` (2 s); 30 s
/// leave room for a slow cellular round trip and late delete receipts,
/// without an overheard receipt being worth anything for long.
const Duration kProofDeadline = Duration(seconds: 30);

/// At most this many open tasks — and separately this many proven
/// collections — a holder keeps (V4.2 R-2). Roughly 100 B per entry, so
/// at most roughly 100 KB per table. On overflow the oldest drops:
/// an attacker who floods the table delays a collection until the
/// next edge, he captures and deletes nothing.
const int kAtMostOpen = 1024;

class _Entry {
  final Uint8List id;

  /// The day value under which this entry lies — in the map key of
  /// `_storage` it stands as hex text, here as the 16 bytes that go to
  /// disk.
  final Uint8List value;
  final Uint8List content;
  final DateTime inserted;
  _Entry(this.id, this.value, this.content, this.inserted);
}

/// An open task: to whom, for which values not yet proven, until when.
typedef _Task = ({String source, Set<String> values, DateTime until});
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

  /// How many deposits this holder has accepted — pure
  /// diagnostics, so that the re-deposit loop from S384 is measurable.
  int deposits = 0;

  /// Without [directory] everything stays in memory. With [directory]
  /// [key] is mandatory (32 B, as `FileEncryption` takes it); the
  /// constructor then READS and throws [DepositError] instead of a half-
  /// filled holder.
  PostBoxHolder({
    required this.send,
    required this.now,
    required this.nodeIdentifier,
    Directory? directory,
    Uint8List? key,
  }) {
    if (directory == null) {
      if (key != null) {
        throw ArgumentError('key without folder: there is nothing to '
            'encrypt, the stock would stay in memory');
      }
      return;
    }
    if (key == null) {
      throw ArgumentError('folder without key: this class derives '
          'no key, it comes from outside');
    }
    final p = PostBoxDisk.open(directory, key);
    // The deadline already applies HERE: otherwise an entry would become
    // immortal because the holder restarts often.
    for (final s in p.load(limit: now().subtract(kAtMostAge))) {
      final valueHex = _hex(s.value);
      _storage
          .putIfAbsent(valueHex, () => [])
          .add(_Entry(s.id, s.value, s.content, s.inserted));
      _idToValue[_hex(s.id)] = valueHex;
    }
    _disk = p; // only now: an error while loading must not overwrite anything
  }

  /// The node identifier of this holder ([kNodeIdentifierLength] B) — stands in
  /// every answer to a question (`0x31`, `0x35`), B1.
  final Uint8List nodeIdentifier;

  /// Writes away the WHOLE held stock; without disk a no-op.
  void _save() {
    final p = _disk;
    if (p == null) return;
    p.save([
      for (final list in _storage.values)
        for (final e in list)
          (
            id: e.id,
            value: e.value,
            content: e.content,
            inserted: e.inserted
          ),
    ]);
  }

  /// 0x30: `Sorte | id | Tageswert | Nachweis 16 | Inhalt`.
  void onDeposit(Uint8List packet, Neighbour from) {
    if (packet.length < kDepositHeader) return;
    var i = 1;
    final id = packet.sublist(i, i += kIdLength);
    final value = packet.sublist(i, i += kValueLength);
    final proofOfWork = packet.sublist(i, i += kProofOfWorkLength);
    final content = packet.sublist(i);
    // FIRST: without a valid proof no receipt, no space, not even
    // information on whether the id is already known (F3/B4). Silently, as with
    // first contact — an answer would itself already be a signal.
    if (!depositProofOfWorkCarries(id, value, content, proofOfWork)) return;
    final valueHex = _hex(value);
    // A known id is never bent (proposal B1, second consequence): under
    // another value the real entry would afterwards no longer be
    // deletable by receipt. The same value: a duplicate, only acknowledge.
    final known = _idToValue[_hex(id)];
    if (known != null) {
      if (known == valueHex) send(receiptPacket(id, nodeIdentifier), from);
      return;
    }
    // ── THE PUBLIC MANIFEST COMPARTMENT: CHECKED, AND ONLY THE NEWEST ──
    //
    // Decision 20 (owner, 15.09.2026) on finding B-2 (S388): until then
    // the holder accepted under this value everything that carried a
    // proof of computation, and passed it on to every asker — a stranger
    // could fill the compartment with forgeries and old versions (measured:
    // five 0x33 instead of one, `smoke_update_manifest_compartment` (11.5)).
    //
    // The holder may check this without violating §8.2 „The holder cannot read the
    // content": the manifest is public, its value is
    // computed by every node, and every asker checks against the maintainer key
    // anyway. Private post stays untouched — under every
    // other value the holder still sees only opaque bytes.
    //
    // REJECTION IS SILENT, as with a missing proof of computation (above):
    // an answer to an unchecked sender address would be an oracle
    // („your forgery was detected") and an amplifier. The sender
    // learns it from the missing receipt — `deposit` returns to him
    // (false, 0). A rejection via the ladder is NOT buildable here:
    // a 0x30 carries the value of the RECIPIENT compartment, never an identifier of the
    // sender, and `Knoten.antwortUeberLeiter` needs exactly that
    // (S389 report, section "Ablehnung").
    if (isManifestValue(value)) {
      final sequence = manifestVerifier(content);
      if (sequence == null) return;
      final held = _storage[valueHex];
      if (held != null && held.isNotEmpty) {
        // At most one entry — the sequence is recomputed from what is held
        // instead of remembered: a remembered value survives neither
        // the restart (disk) nor a key change, and the
        // recomputation costs one check per incoming 0x30.
        final old = manifestVerifier(held.last.content);
        if (old != null && sequence <= old) return;
        for (final e in held) {
          _idToValue.remove(_hex(e.id));
        }
        held.clear();
      }
    }
    deposits++;
    final list = _storage.putIfAbsent(valueHex, () => []);
    _purge(list);
    list.add(_Entry(id, value, content, now()));
    _idToValue[_hex(id)] = valueHex;
    while (list.length > kAtMostProValue) {
      final old = list.removeAt(0); // oldest in first, out first
      _idToValue.remove(_hex(old.id));
    }
    // Save BEFORE the receipt: the receipt is the promise that I hold the
    // piece.
    _save();
    send(receiptPacket(id, nodeIdentifier), from);
  }

  /// 0x32 `Sorte | Anzahl | 7 × Wert`: NO handing out, only ONE task
  /// (33 B) for all asked values. Whether something lies there is learned only by whoever
  /// has proven himself per value.
  void onCollect(Uint8List packet, Neighbour from) {
    final values = collectValuesRead(packet);
    if (values == null) return;
    final random = SodiumFFI().randomBytes(kRandomLength);
    final t = now();
    _tasks.removeWhere((_, a) => !a.until.isAfter(t));
    _tasks[_hex(random)] = (
      source: _source(from),
      values: {for (final w in values) _hex(w)},
      until: t.add(kProofDeadline),
    );
    while (_tasks.length > kAtMostOpen) {
      _tasks.remove(_tasks.keys.first);
    }
    send(taskPacket(random, nodeIdentifier), from);
  }

  /// 0x36: the proof for ONE value of a task. If it holds, the
  /// holder hands out what lies under this value.
  void onProof(Uint8List packet, Neighbour from) {
    final b = proofRead(packet);
    if (b == null) return;
    final randomHex = _hex(b.random);
    final a = _tasks[randomHex];
    final source = _source(from);
    if (a == null || a.source != source) return;
    final valueHex = _hex(b.value);
    // Once per value — even if the proof does not hold.
    if (!a.values.remove(valueHex)) return;
    if (a.values.isEmpty) _tasks.remove(randomHex);
    if (!a.until.isAfter(now())) return;
    if (!proofCarries(b)) return;
    // Under the manifest compartment nothing is ever deleted (§26.5.4): no proof to remember.
    if (!isManifestValue(b.value)) {
      final t = now();
      _proven.removeWhere((_, x) => !x.until.isAfter(t));
      final key = '$source|$valueHex';
      _proven.remove(key);
      _proven[key] =
          (pk: b.pk, random: b.random, until: t.add(kProofDeadline));
      while (_proven.length > kAtMostOpen) {
        _proven.remove(_proven.keys.first);
      }
    }
    _handOut(b.value, valueHex, from);
  }

  void _handOut(Uint8List value, String valueHex, Neighbour from) {
    final list = _storage[valueHex];
    if (list != null && _purge(list)) _save();
    if (list == null || list.isEmpty) {
      send(
          (BytesBuilder()
                ..addByte(kinds.kNothingThere)
                ..add(value))
              .toBytes(),
          from);
      return;
    }
    final count = list.length; // <= kAtMostProValue (100), fits in 1 B
    // Copy: a sent 0x33 can trigger a delete receipt (0x31)
    // that mutates EXACTLY THIS list in the meantime.
    for (final e in List.of(list)) {
      final p = BytesBuilder()
        ..addByte(kinds.kHereItIs)
        ..add(value)
        ..add(e.id)
        ..addByte(count)
        ..add(e.content);
      send(p.toBytes(), from);
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
    list.removeAt(i);
    _idToValue.remove(idHex);
    _save();
  }

  /// Throws away what is older than [kAtMostAge]. Reports back whether
  /// something dropped out in the process — only then does the disk have to be
  /// touched.
  bool _purge(List<_Entry> list) {
    final limit = now().subtract(kAtMostAge);
    final before = list.length;
    list.removeWhere((e) {
      final expired = e.inserted.isBefore(limit);
      if (expired) _idToValue.remove(_hex(e.id));
      return expired;
    });
    return list.length != before;
  }
}

/// 0x31 `Sorte | id | Knotenkennung 16` — the deposited receipt of the
/// holder to the sender. The node identifier (B1, S388) lets the sender
/// count two receipts of THE SAME node under two addresses as one.
Uint8List receiptPacket(Uint8List id, Uint8List node) =>
    (BytesBuilder()
          ..addByte(kinds.kDeposited)
          ..add(id)
          ..add(node))
        .toBytes();

/// Length of the node identifier in `0x31` and `0x35` (as in the neighbour call, there
/// as text).
const int kNodeIdentifierLength = 16;

String _source(Neighbour n) => '${n.$1.address}:${n.$2}';

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
