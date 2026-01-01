/// The keeper of groups and channels on the shared key (V4.2 §16.2.5
/// "Keepers", §21.3.1): it holds entries under channel values for 7 days and
/// hands them to members that prove they collect under a value.
///
/// It reads nothing: an entry is sealed under a key the keeper does not hold
/// unless it is itself a member. What it checks is public — the value
/// matches the two public keys, the author key carries a certificate of the
/// generation key, the author signed the entry and THIS keeper's address,
/// and the first deposit under a value carries its proof of work.
///
/// Bounds: 100 entries per author key, 1,000 per value, [kKeeperBytesAtMost]
/// in all (inside the delivery-layer storage of §21.3.1). Nothing is deleted
/// on collection; an entry leaves when its 7 days have passed — checked at
/// every packet, never on a clock (§1.2).
///
/// Who keeps: an always-on desktop installation with evidenced reachability
/// ([allowed], set by `host_channel.dart`); every other node answers a hold
/// with [HeldVerdict.noKeeper] and a question with "nothing here".
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:mycelium/card_address.dart';
import 'package:mycelium/channel_chain.dart';
import 'package:mycelium/channel_entry.dart';
import 'package:mycelium/channel_keeper_disk.dart';
import 'package:mycelium/channel_proof.dart';
import 'package:mycelium/channel_wire.dart' as w;
import 'package:mycelium/device_records.dart';
import 'package:mycelium/split.dart' show kMaxPayload;
import 'package:mycelium/split_flow.dart' show SendEnd;

const int kPerAuthorAtMost = 100;
const int kPerValueAtMost = 1000;
const int kKeeperBytesAtMost = 64 * 1024 * 1024;

/// Open passes a keeper remembers between a question and its fetch (§20.2).
const int kPassesAtMost = 64;

typedef ChannelSend = FutureOr<Object?> Function(Uint8List packet, CardAddress to);

class ChannelKeeper {
  final ChannelSend send;
  final bool Function() allowed;
  final List<CardAddress> Function() ownAddresses;
  final DateTime Function() now;
  final void Function(String)? report;
  final KeeperDisk _disk;

  /// value hex → entries, oldest first.
  final Map<String, List<KeptEntry>> _values = {};

  /// request hex → the values a question proved, for its fetch.
  final Map<String, Set<String>> _passes = {};

  /// Counters for probes and the network statistics (§25).
  int taken = 0, refused = 0, handedOut = 0;

  ChannelKeeper({
    required this.send,
    required this.allowed,
    required this.ownAddresses,
    DeviceRecords? records,
    this.now = DateTime.now,
    this.report,
  }) : _disk = KeeperDisk(records) {
    for (final e in _disk.load()) {
      (_values[hexOf(e.value)] ??= []).add(e);
    }
    _expire();
  }

  int get entries => _values.values.fold(0, (s, l) => s + l.length);
  int get bytes =>
      _values.values.fold(0, (s, l) => s + l.fold(0, (t, e) => t + e.entry.length));

  /// Whether this keeper holds an entry with [hash] under [value].
  bool holds(Uint8List value, Uint8List hash) =>
      (_values[hexOf(value)] ?? const []).any((e) => _eq(e.hash, hash));

  void _expire() {
    final limit = now().subtract(const Duration(days: kKeepDays));
    var gone = 0;
    _values.removeWhere((_, l) {
      final before = l.length;
      l.removeWhere((e) => e.at.isBefore(limit));
      gone += before - l.length;
      return l.isEmpty;
    });
    if (gone > 0) _disk.save(_all());
  }

  Iterable<KeptEntry> _all() => _values.values.expand((l) => l);

  /// The own address the signature names, or `null`.
  bool _forMe(bool Function(CardAddress) signedFor) =>
      ownAddresses().any(signedFor);

  /// `0x60`.
  void onHold(Uint8List p, CardAddress from) {
    final h = w.holdRead(p);
    if (h == null) return; // unparseable: no answer (§11.6)
    void answer(w.HeldVerdict v) {
      if (v == w.HeldVerdict.held) {
        taken++;
      } else {
        refused++;
      }
      send(w.held(h.request, v), from);
    }

    if (!allowed()) return answer(w.HeldVerdict.noKeeper);
    _expire();
    final head = EntryHead.of(h.entry);
    if (head == null ||
        !_eq(channelValue(h.collectPk, h.generationPk), h.value) ||
        !certificateHolds(h.generationPk, head.generation, head.generationId,
            h.authorPk, h.certificate) ||
        !_forMe((a) =>
            verifies(w.holdSigned(h.value, h.entry, a), h.signature, h.authorPk))) {
      return answer(w.HeldVerdict.invalid);
    }
    final key = hexOf(h.value);
    final list = _values[key];
    final hash = entryHash(h.entry);
    if (list != null && list.any((e) => _eq(e.hash, hash))) {
      return answer(w.HeldVerdict.held); // kept already (§8.2: acknowledged)
    }
    if (list == null) {
      if (h.proof == null) return answer(w.HeldVerdict.proofWanted);
      if (!channelProofHolds(h.value, h.proof!)) {
        return answer(w.HeldVerdict.invalid);
      }
    }
    final author = hexOf(h.authorPk);
    final byAuthor =
        _all().where((e) => hexOf(e.authorPk) == author).length;
    if ((list?.length ?? 0) >= kPerValueAtMost ||
        byAuthor >= kPerAuthorAtMost) {
      report?.call('channel keeper: ${key.substring(0, 8)} full '
          '(${list?.length ?? 0} under the value, $byAuthor of the author)');
      return answer(w.HeldVerdict.full);
    }
    if (bytes + h.entry.length > kKeeperBytesAtMost) {
      return answer(w.HeldVerdict.noKeeper);
    }
    (_values[key] ??= []).add(KeptEntry(
        value: h.value, authorPk: h.authorPk, entry: h.entry, at: now()));
    _disk.save(_all());
    answer(w.HeldVerdict.held);
  }

  /// `0x62`: "same", the list of hashes, or "nothing here".
  void onQuestion(Uint8List p, CardAddress from) {
    final q = w.questionRead(p);
    if (q == null) return;
    _expire();
    final proven = <String>{};
    for (final it in q.items) {
      if (!_eq(channelValue(it.collectPk, q.generationPk), it.value)) continue;
      if (!_forMe((a) => verifies(
          w.questionSigned(q.request, q.root, it.value, a),
          it.signature,
          it.collectPk))) {
        continue;
      }
      proven.add(hexOf(it.value));
    }
    final held = [for (final v in proven) ...?_values[v]];
    final hashes = [for (final e in held) e.hash];
    if (!allowed() || proven.isEmpty || hashes.isEmpty) {
      send(w.end(q.request, 0, nothingHere: true), from);
      return;
    }
    if (_eq(stateRoot(hashes), q.root)) {
      send(w.same(q.request), from);
      return;
    }
    _passes[hexOf(q.request)] = proven;
    while (_passes.length > kPassesAtMost) {
      _passes.remove(_passes.keys.first);
    }
    const per = w.kListedPerPacket;
    final parts = (held.length + per - 1) ~/ per;
    for (var i = 0; i < parts; i++) {
      final chunk = held.sublist(i * per, ((i + 1) * per).clamp(0, held.length));
      send(
          w.listPacket(q.request, i, parts,
              [for (final e in chunk) (hash: e.hash, kind: e.entry[0])]),
          from);
    }
  }

  /// `0x65`: hands out each asked entry (`0x66`) under the flow of §11.3 —
  /// an entry of several parts waits for the end of the one before it,
  /// single parts do not wait — and closes with the number (`0x67`).
  Future<void> onFetch(Uint8List p, CardAddress from) async {
    final f = w.fetchRead(p);
    if (f == null) return;
    final values = _passes[hexOf(f.request)];
    if (values == null || !allowed()) {
      send(w.end(f.request, 0, nothingHere: true), from);
      return;
    }
    var n = 0;
    for (final hash in f.hashes) {
      KeptEntry? e;
      for (final v in values) {
        e ??= _values[v]?.where((x) => _eq(x.hash, hash)).firstOrNull;
      }
      if (e == null) continue;
      final packet = w.entryPacket(f.request, e.value, e.entry);
      final out = send(packet, from);
      n++;
      handedOut++;
      if (packet.length > kMaxPayload && out is Future) {
        final end = await out;
        if (end == SendEnd.unreachable || end == SendEnd.refused) break;
      }
    }
    send(w.end(f.request, n), from);
  }
}

bool _eq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    d |= a[i] ^ b[i];
  }
  return d == 0;
}
