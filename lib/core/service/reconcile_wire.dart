// V4.2 §14.6.3, §14.7 Type 20, §13.5.2, §20.2 (D-42) — the wire of the
// initial reconciliation of own devices. Pure functions: no network, no
// store, no clock. The one place that packs and reads Type 20.
//
// Every packet stays within 32 768 B INCLUDING the hybrid seal (§20.2):
// the seal of an own-line packet was measured constant at 7 779 B
// (`test/smoke/smoke_reconcile_budget.dart`), the twin-sync and application
// frames around the payload take less than [kReconcileFramingReserve].
// Content is compressed before the seal (§1.3) where zstd-3 gains at least
// 10 % (the rule of §4.5.3).

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/codec/compression.dart';
import 'package:cleona/generated/proto/app_payloads.pb.dart' as app;
import 'package:fixnum/fixnum.dart';

/// A reconciliation packet on the line, seal included (§20.2).
const int kReconcilePacketAtMost = 32768;

/// The hybrid seal of one own-line packet — measured constant
/// (`smoke_reconcile_budget` 2a: 7 779 B at 0, 1 000 and 24 000 B content).
const int kReconcileSealOverhead = 7779;

/// Room for ApplicationFrameV3 → TwinSyncEnvelope → ReconcilePacket around
/// the body (measured together with the seal by `smoke_reconcile_wire` 2a).
const int kReconcileFramingReserve = 512;

/// The encoded [app.ReconcilePacket] at most — what [reconcileEncode] yields.
const int kReconcileBodyAtMost =
    kReconcilePacketAtMost - kReconcileSealOverhead - kReconcileFramingReserve;

/// The norm's bound: packets of the source under one device value (§20.2,
/// §14.6.3).
const int kReconcileSourceAtMost = 80;

/// The OPERATING window: packets the source places per round before it
/// waits for the recipient's progress report. Owner 29.09.2026 (build form
/// B, finding M-1 of `S398-ERSTABGLEICH-BAU.md`): a collection pass brought
/// 4 packets of 32 KB on loopback; the number is measured again after the
/// flow control OP-33 B. It never exceeds [kReconcileSourceAtMost].
const int kReconcileWindow = 4;

/// Newest messages per conversation that follow the handover automatically
/// (§14.6.3, D-42: E-1 b).
const int kReconcileNewest = 10;

/// Manifest entries per packet (§13.5.2: ~570 at ~42 B).
const int kReconcileManifestAtMost = 570;

/// Identifiers one fetch names — 16 B each plus framing, within one packet.
const int kReconcileFetchIdsAtMost = 1300;

/// A packet's body carries at least this multiple of the records' raw
/// size hints: zstd-3 measured 2.6x (300 B text) to 7x (13 B text) on
/// random text, which compresses worse than chat text
/// (`smoke_reconcile_budget` 1). Used only to size a fetch.
const int kReconcileHintPerBody = 2;

/// A decompressed frame at most — an own-line frame is our own identity's,
/// the bound only keeps a broken frame from taking memory.
const int _kDecompressedAtMost = 4 * 1024 * 1024;

const int _kCompressFrom = 128;
const int _kMinCompressionGain = 10; // percent, §4.5.3

/// The Type-20 payload of [frame]: compressed where it gains ≥ 10 %.
Uint8List reconcileEncode(app.ReconcileFrame frame) {
  final raw = frame.writeToBuffer();
  var codec = 0;
  var body = raw;
  if (raw.length >= _kCompressFrom) {
    final packed = ZstdCompression.instance.compress(raw, level: 3);
    if (100 - packed.length * 100 ~/ raw.length >= _kMinCompressionGain) {
      codec = 1;
      body = packed;
    }
  }
  return (app.ReconcilePacket()
        ..codec = codec
        ..body = body)
      .writeToBuffer();
}

/// The frame of a Type-20 payload, or `null` when it is not one.
app.ReconcileFrame? reconcileDecode(Uint8List payload) {
  try {
    final p = app.ReconcilePacket.fromBuffer(payload);
    if (p.codec > 1) return null;
    final body = Uint8List.fromList(p.body);
    final raw = p.codec == 1 ? ZstdCompression.instance.decompress(body) : body;
    if (raw.length > _kDecompressedAtMost) return null;
    final f = app.ReconcileFrame.fromBuffer(raw);
    if (f.reconcileId.length != 16 ||
        f.whichKind() == app.ReconcileFrame_Kind.notSet) {
      return null;
    }
    return f;
  } on Object {
    return null;
  }
}

bool _fits(app.ReconcileFrame f) =>
    reconcileEncode(f).length <= kReconcileBodyAtMost;

/// Groups [items] in order into the largest runs whose frame fits one
/// packet (at most [atMost] items each). An item that fits no frame alone
/// goes to [tooLarge]. Doubling, then halving: ~2·log2(n) encodings a packet.
List<List<T>> _pack<T>(List<T> items, app.ReconcileFrame Function(List<T>) build,
    {int atMost = 1 << 30, void Function(T)? tooLarge}) {
  final out = <List<T>>[];
  var i = 0;
  while (i < items.length) {
    final left = items.length - i < atMost ? items.length - i : atMost;
    if (!_fits(build(items.sublist(i, i + 1)))) {
      tooLarge?.call(items[i]);
      i++;
      continue;
    }
    var good = 1;
    var bad = left + 1;
    var step = 2;
    while (step <= left && _fits(build(items.sublist(i, i + step)))) {
      good = step;
      step *= 2;
    }
    if (step <= left) bad = step;
    if (good == left) bad = left + 1;
    while (bad - good > 1) {
      final mid = (good + bad) ~/ 2;
      if (_fits(build(items.sublist(i, i + mid)))) {
        good = mid;
      } else {
        bad = mid;
      }
    }
    out.add(items.sublist(i, i + good));
    i += good;
  }
  return out;
}

/// The header (§14.6.3): the chats by last activity, newest first, in
/// numbered parts.
List<app.ReconcileFrame> reconcileHeaderFrames({
  required List<int> reconcileId,
  required int cutMs,
  required List<app.ReconcileChat> chats,
}) {
  final sorted = List.of(chats)
    ..sort((a, b) => b.lastActivityMs.compareTo(a.lastActivityMs));
  app.ReconcileFrame build(List<app.ReconcileChat> run, int part, int parts) =>
      app.ReconcileFrame()
        ..reconcileId = reconcileId
        ..header = (app.ReconcileHeader()
          ..cutMs = Int64(cutMs)
          ..part = part
          ..parts = parts
          ..chats.addAll(run));
  // Sized with the largest part numbers the header could carry.
  final runs = _pack(sorted, (r) => build(r, 0xFFFF, 0xFFFF));
  if (runs.isEmpty) return [build(const [], 0, 1)];
  return [
    for (var k = 0; k < runs.length; k++) build(runs[k], k, runs.length)
  ];
}

/// One manifest entry with its conversation.
typedef ReconcileListed = ({List<int> conv, app.ReconcileEntry entry});

/// The manifest (§13.5.2 phase 2): entries newest first, at most
/// [kReconcileManifestAtMost] a packet, grouped per chat inside a packet; a
/// chat is `complete` in the packet that carries its last entry.
List<app.ReconcileFrame> reconcileManifestFrames({
  required List<int> reconcileId,
  required List<int> fetchId,
  required List<ReconcileListed> entries,
}) {
  final sorted = List.of(entries)
    ..sort((a, b) => b.entry.tsMs.compareTo(a.entry.tsMs));
  final last = <String, int>{};
  for (var k = 0; k < sorted.length; k++) {
    last[_key(sorted[k].conv)] = k;
  }
  final index = {for (var k = 0; k < sorted.length; k++) sorted[k]: k};
  app.ReconcileFrame build(List<ReconcileListed> run) {
    final m = app.ReconcileManifest()..fetchId = fetchId;
    final byChat = <String, app.ReconcileManifestChat>{};
    for (final e in run) {
      final k = _key(e.conv);
      final c = byChat.putIfAbsent(k, () {
        final c = app.ReconcileManifestChat()..convId = e.conv;
        m.chats.add(c);
        return c;
      });
      c.entries.add(e.entry);
      if (last[k] == index[e]) c.complete = true;
    }
    return app.ReconcileFrame()
      ..reconcileId = reconcileId
      ..manifest = m;
  }

  return [
    for (final run in _pack(sorted, build, atMost: kReconcileManifestAtMost))
      build(run)
  ];
}

/// The keys of `extra` a record loses first when it fits no packet: the
/// pictures, which the conversation can do without.
const List<String> _kDroppable = [
  'linkPreviewThumbnailBase64',
  'thumbnailBase64',
];

/// The deliver frames (§13.5.2 phase 3), newest first. A record that fits
/// no packet loses its pictures; one that still does not fit is named in
/// [skipped] and in the first frame's `too_large` — never dropped silently.
({List<app.ReconcileFrame> frames, List<Uint8List> skipped})
    reconcileDeliverFrames({
  required List<int> reconcileId,
  required List<int> fetchId,
  required List<app.ReconcileMessage> messages,
}) {
  final sorted = List.of(messages)..sort((a, b) => b.tsMs.compareTo(a.tsMs));
  app.ReconcileFrame build(List<app.ReconcileMessage> run) =>
      app.ReconcileFrame()
        ..reconcileId = reconcileId
        ..deliver = (app.ReconcileDeliver()
          ..fetchId = fetchId
          ..messages.addAll(run));
  final fitted = [
    for (final m in sorted) _fits(build([m])) ? m : _withoutPictures(m)
  ];
  final skipped = <Uint8List>[];
  final runs = _pack(fitted, build,
      tooLarge: (m) => skipped.add(Uint8List.fromList(m.id)));
  final frames = [for (final r in runs) build(r)];
  if (skipped.isNotEmpty) {
    if (frames.isEmpty) frames.add(build(const []));
    frames.first.deliver.tooLarge.addAll(skipped);
  }
  return (frames: frames, skipped: skipped);
}

app.ReconcileMessage _withoutPictures(app.ReconcileMessage m) {
  try {
    final extra = jsonDecode(utf8.decode(m.extraJson));
    if (extra is! Map<String, dynamic>) return m;
    if (!_kDroppable.any(extra.containsKey)) return m;
    for (final k in _kDroppable) {
      extra.remove(k);
    }
    return app.ReconcileMessage.fromBuffer(m.writeToBuffer())
      ..extraJson = utf8.encode(jsonEncode(extra));
  } on Object {
    return m;
  }
}

/// The identifiers of one fetch each (§13.5.2 phase 3), in the given order
/// (the caller gives them newest first): at most [kReconcileFetchIdsAtMost]
/// and at most what [window] packets carry by the records' size hints.
List<List<Uint8List>> reconcileFetchBatches(
    List<({Uint8List id, int size})> missing,
    {int window = kReconcileWindow}) {
  final budget = window * kReconcileBodyAtMost * kReconcileHintPerBody;
  final out = <List<Uint8List>>[];
  var run = <Uint8List>[];
  var sum = 0;
  for (final m in missing) {
    if (run.isNotEmpty &&
        (run.length >= kReconcileFetchIdsAtMost || sum + m.size > budget)) {
      out.add(run);
      run = <Uint8List>[];
      sum = 0;
    }
    run.add(m.id);
    sum += m.size;
  }
  if (run.isNotEmpty) out.add(run);
  return out;
}

// ── §9.5 catching up after more than 7 days (D-48) ──────────────────────
//
// "It does so with the reconciliation of §14.6.3 — the same packets, the
// same bounds, the same store operations — carried between the two parties
// of a pair (§4.3) instead of over the own-device line. There is no second
// mechanism." The request is a fetch of the kind SINCE, the answer deliver
// packets, the report a progress packet; the carrier is the ordinary
// message `MTV3_CATCH_UP` instead of twin-sync Type 20.

/// §9.5: "written or changed since 14 days before the named moment (§9.3)"
/// — so long a message may have rested with its sender before it left.
const Duration kCatchUpLookBack = Duration(days: 14);

/// Identifiers of the requester's messages an answer names as held, at most
/// (§9.5, §20.2). Beyond it the oldest are left out: those messages stay
/// `in transit` at the requester although they arrived.
const int kCatchUpHeldAtMost = 900;

/// Identifiers of deleted messages an answer names at most (§9.5, §20.2).
/// Beyond it the oldest deletions are left out and named in the log.
const int kCatchUpDeletedAtMost = 200;

/// Conversations an answer names a count of expired messages for, at most
/// (§21.5.3, §20.2).
const int kCatchUpExpiredAtMost = 64;

/// Records the answering party looks at for ONE round: more than four
/// packets carry even of the shortest messages (642 of 13 B text a packet,
/// `smoke_reconcile_budget`), so a round never packs the whole history.
const int kCatchUpRoundRecordsAtMost = 2800;

/// The request (§9.5 "Who is asked"): it names the moment of the device's
/// last collection and nothing else about the device.
app.ReconcileFrame catchUpRequestFrame({
  required List<int> fetchId,
  required int sinceMs,
}) =>
    app.ReconcileFrame()
      ..reconcileId = fetchId
      ..fetch = (app.ReconcileFetch()
        ..fetchId = fetchId
        ..kind = app.ReconcileFetch_Kind.SINCE
        ..sinceMs = Int64(sinceMs)
        ..window = kReconcileWindow);

/// The requester's progress report (§9.5 "reports the messages as
/// delivered", §20.2): [received] packets of the answer are here, numbered
/// from 0 without a gap; [delivered] are the answering party's messages the
/// requester holds now.
app.ReconcileFrame catchUpProgressFrame({
  required List<int> fetchId,
  required int received,
  required List<List<int>> delivered,
}) =>
    app.ReconcileFrame()
      ..reconcileId = fetchId
      ..progress = (app.ReconcileProgress()
        ..fetchId = fetchId
        ..received = received
        ..delivered.addAll(delivered));

/// ONE round of an answer (§9.5 "What is sent", §20.2): at most [window]
/// packets, numbered from [firstSeq], the last one marked `round_end` — and
/// `complete` when nothing is left to send.
///
/// [records] is what is still to send, newest first; [more] says that the
/// party holds further records behind them. [lists] is the first packet of
/// the answer — the identifiers held and deleted and the expired counts —
/// and counts as one packet of its round; its `held` list is shortened from
/// its end until the packet fits (`heldLeftOut`).
///
/// [consumed] is how many of [records] the round carried or named as too
/// large — the next round starts behind them. A record that fits no packet
/// loses its pictures first and is otherwise named in `too_large`, never
/// dropped silently.
({
  List<app.ReconcileFrame> frames,
  int consumed,
  List<Uint8List> skipped,
  int heldLeftOut,
  bool complete,
}) catchUpAnswerRound({
  required List<int> fetchId,
  required int firstSeq,
  required List<app.ReconcileMessage> records,
  required bool more,
  app.ReconcileDeliver? lists,
  int window = kReconcileWindow,
}) {
  final size = window > kReconcileSourceAtMost ? kReconcileSourceAtMost : window;
  app.ReconcileFrame frame(app.ReconcileDeliver d) => app.ReconcileFrame()
    ..reconcileId = fetchId
    ..deliver = (d..fetchId = fetchId);
  app.ReconcileFrame build(List<app.ReconcileMessage> run) =>
      frame(app.ReconcileDeliver()
        ..seq = 0xFFFF
        ..roundEnd = true
        ..complete = true
        ..messages.addAll(run));

  final frames = <app.ReconcileFrame>[];
  var heldLeftOut = 0;
  if (lists != null) {
    final first = app.ReconcileDeliver()
      ..seq = 0xFFFF
      ..roundEnd = true
      ..complete = true
      ..held.addAll(lists.held)
      ..deleted.addAll(lists.deleted)
      ..expired.addAll(lists.expired);
    while (!_fits(frame(first)) && first.held.isNotEmpty) {
      final cut = first.held.length < 100 ? first.held.length : 100;
      first.held.removeRange(first.held.length - cut, first.held.length);
      heldLeftOut += cut;
    }
    frames.add(frame(first));
  }

  final fitted = [
    for (final m in records) _fits(build([m])) ? m : _withoutPictures(m)
  ];
  // What fits no packet alone is known before packing, so that every packet
  // is sized with the room the `too_large` list may take in it.
  final tooLarge = Set<app.ReconcileMessage>.identity()
    ..addAll(fitted.where((m) => !_fits(build([m]))));
  final named = [for (final m in tooLarge) m.id];
  app.ReconcileFrame sized(List<app.ReconcileMessage> run) =>
      build(run)..deliver.tooLarge.addAll(named);
  final runs = _pack(
      [
        for (final m in fitted)
          if (!tooLarge.contains(m)) m
      ],
      sized,
      tooLarge: tooLarge.add);
  final skipped = <Uint8List>[];
  var at = 0;
  void skipTooLarge() {
    while (at < fitted.length && tooLarge.contains(fitted[at])) {
      skipped.add(Uint8List.fromList(fitted[at].id));
      at++;
    }
  }

  skipTooLarge();
  for (final run in runs) {
    if (frames.length >= size) break;
    frames.add(frame(app.ReconcileDeliver()..messages.addAll(run)));
    at += run.length;
    skipTooLarge();
  }
  final complete = at >= fitted.length && !more;
  if (frames.isEmpty && (skipped.isNotEmpty || complete)) {
    frames.add(frame(app.ReconcileDeliver()));
  }
  if (skipped.isNotEmpty) frames.last.deliver.tooLarge.addAll(skipped);
  for (var k = 0; k < frames.length; k++) {
    final last = k == frames.length - 1;
    frames[k].deliver
      ..seq = firstSeq + k
      ..roundEnd = last
      ..complete = last && complete;
  }
  return (
    frames: frames,
    consumed: at,
    skipped: skipped,
    heldLeftOut: heldLeftOut,
    complete: complete,
  );
}

/// The source's count of packets placed for one device since its last
/// progress report (§14.6.3: "fills again only on the recipient's progress
/// report"). [size] never exceeds the norm's [kReconcileSourceAtMost].
class ReconcileWindow {
  ReconcileWindow({int size = kReconcileWindow})
      : size = size > kReconcileSourceAtMost ? kReconcileSourceAtMost : size;

  final int size;
  int _placed = 0;

  int get placed => _placed;
  int get left => size - _placed;

  /// One packet more — `false` when the round is full.
  bool take() {
    if (_placed >= size) return false;
    _placed++;
    return true;
  }

  /// The recipient's progress report opens the next round.
  void progress() => _placed = 0;
}

String _key(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
