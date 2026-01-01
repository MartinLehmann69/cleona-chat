// V4.2 §14.6.3, §14.7 Type 20 RECONCILE (D-42, D-123 (3), S422 phase 6) —
// the initial reconciliation of own devices.
//
// ── THE SOURCE ───────────────────────────────────────────────────────────
//
// After a handover (§14.6.1 step 6, §14.7 Type 23) the device that handed
// over sends the header — the conversation list with its configuration and,
// per conversation, the count and size of the history it holds before the
// cut. It serves only a device of its own set (Types 9/16), answers fetches
// with manifest and deliver packets, and holds at most
// [kReconcileSourceAtMost] packets under one device value: it places a round
// of at most the window the recipient named and fills again only on the
// recipient's progress report. No clock, no repetition.
//
// ── THE NEW DEVICE ───────────────────────────────────────────────────────
//
// Automatically: the header and the newest [kReconcileNewest] messages of
// each conversation (fetch NEWEST). The full history of a conversation is a
// deliberate user decision: it is offered with its size and way
// ([reconcileOffers]) and fetched only on [reconcileFetchHistory] (manifest,
// then the missing records). A record never overwrites what arrived
// meanwhile (`insertMessageIfAbsent`). While a fetch is open the interface
// shows "reconciling state" ([reconcileRunning]).
//
// The packets travel on the own line through the post box. The direct LAN
// carrier of §14.6.3 is not built here (named in the report); the offer
// therefore names the post box as the way.

part of 'cleona_service.dart';

/// The source's state for one recipient device. Kept in the store (area
/// [kReconcileServeArea]) without its queue: the header packets, the fetches
/// in order and the counts — after a restart the queue is built again from
/// the fetches and what was placed is skipped (§13.5.2 "resumable").
class _ReconcileServe {
  _ReconcileServe(this.reconcileId);
  final Uint8List reconcileId;
  int cutMs = 0;
  final List<proto.ReconcileFrame> queue = [];
  final List<Uint8List> headerFrames = [];
  final List<Uint8List> fetches = [];
  ReconcileWindow window = ReconcileWindow(size: kReconcileSourceAtMost);

  /// Per fetch (hex; `''` = the header): packets placed, and the highest
  /// count the recipient reported received. Progress reports name the
  /// CUMULATIVE count of their fetch, so a report that arrives late or twice
  /// (the own line keeps no order) changes nothing it should not.
  final Map<String, int> placedBy = {};
  final Map<String, int> reportedBy = {};

  /// How the packets went: directly on the LAN, or through the post box.
  int direct = 0;
  int viaPostBox = 0;

  /// Attachment pieces that did not arrive on the LAN (not placed elsewhere),
  /// and the attachment fetches ended for that reason.
  int attachmentsLost = 0;
  final Set<String> attachmentsEnded = {};

  /// Attachment fetches whose lane 3 placing was started (S422).
  final Set<String> laneThreeStarted = {};

  /// Packets placed and not yet reported received — never more than the
  /// window (§14.6.3: at most 80 under one device value).
  int get outstanding {
    var n = 0;
    for (final e in placedBy.entries) {
      final r = reportedBy[e.key] ?? 0;
      if (e.value > r) n += e.value - r;
    }
    return n;
  }
}

/// The fetch a frame belongs to (hex; `''` for the header).
String _reconcileFetchOf(proto.ReconcileFrame f) => f.hasDeliver()
    ? _hexR(f.deliver.fetchId)
    : f.hasManifest()
        ? _hexR(f.manifest.fetchId)
        : f.hasAttachment()
            ? _hexR(f.attachment.fetchId)
            : '';

/// Raw bytes of one attachment piece: the packet body less room for the
/// frame around it (§20.2, `reconcile_wire.dart`).
const int kReconcileAttachmentPiece = kReconcileBodyAtMost - 1024;

String _hexR(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

/// The new device's state for one source device.
class _ReconcileTake {
  _ReconcileTake(this.reconcileId, this.fromHex);
  final Uint8List reconcileId;
  final String fromHex;
  int cutMs = 0;
  final Map<int, proto.ReconcileHeader> parts = {};
  int partsTotal = 0;
  final Map<String, proto.ReconcileChat> chats = {};

  /// Open fetch: id hex → kind.
  final Map<String, proto.ReconcileFetch_Kind> open = {};

  /// Per fetch (hex; `''` = the header): packets received, the count last
  /// reported (cumulative), and the packets the fetch has in all — known from
  /// its `complete` packet (`seq + 1`), which may arrive before the others.
  final Map<String, int> gotBy = {};
  final Map<String, int> reportedBy = {};
  final Map<String, int> totalBy = {};

  /// Deliver packets received per fetch, by number — a packet that comes
  /// twice (after a restart of the source) counts once.
  final Map<String, Set<int>> gotSeqs = {};

  /// Manifest fetches: the conversations asked (hex), and which of them
  /// sent their flagged last packet (`fetch/conv`).
  final Map<String, List<String>> manifestConvs = {};
  final Set<String> manifestFlagged = {};
  final Map<String, List<Uint8List>> manifestIds = {};
  final Map<String, int> tooLarge = {};
  final List<List<Uint8List>> pendingBatches = [];

  /// Packets this device takes per round (named in every fetch).
  int window = kReconcileWindow;

  /// Attachment fetches: the conversation asked; pieces of a file being put
  /// together (held here and kept in [kReconcilePieceArea], so a restart
  /// does not cut a file); conversations whose attachments the source did
  /// not carry.
  final Map<String, String> attachmentConvs = {};

  /// Lane 3 bundles announced and still being collected (tags, S422).
  final Set<String> bundlesPending = {};
  final Map<String, Map<int, Uint8List>> filePieces = {};
  final Set<String> attachmentsNotCarried = {};
}

/// Store areas of the reconciliation (§13.5.2 "resumable"), keyed by the
/// other device's DeviceID.
const String kReconcileServeArea = 'reconcile_serve';
const String kReconcileTakeArea = 'reconcile_take';

/// Attachment pieces received and not yet put together (`msg/part`), so a
/// file survives a restart in the middle of its transfer (S422).
const String kReconcilePieceArea = 'reconcile_pieces';

Map<String, dynamic> _reconcileServeJson(_ReconcileServe s) => {
      'rid': _hexR(s.reconcileId),
      'cut': s.cutMs,
      'h': [for (final b in s.headerFrames) _hexR(b)],
      'f': [for (final b in s.fetches) _hexR(b)],
      'p': s.placedBy,
      'r': s.reportedBy,
    };

Map<String, dynamic> _reconcileTakeJson(_ReconcileTake t) => {
      'rid': _hexR(t.reconcileId),
      'from': t.fromHex,
      'cut': t.cutMs,
      'pt': t.partsTotal,
      'parts': [for (final e in t.parts.entries) [e.key, _hexR(e.value.writeToBuffer())]],
      'open': {for (final e in t.open.entries) e.key: e.value.value},
      'got': t.gotBy,
      'seq': {for (final e in t.gotSeqs.entries) e.key: e.value.toList()},
      'rep': t.reportedBy,
      'tot': t.totalBy,
      'mc': t.manifestConvs,
      'mf': t.manifestFlagged.toList(),
      'mi': {
        for (final e in t.manifestIds.entries)
          e.key: [for (final i in e.value) _hexR(i)]
      },
      'tl': t.tooLarge,
      'pb': [
        for (final b in t.pendingBatches) [for (final i in b) _hexR(i)]
      ],
      'w': t.window,
      'ac': t.attachmentConvs,
      'nc': t.attachmentsNotCarried.toList(),
    };

Uint8List _bytesR(String h) => Uint8List.fromList(
    [for (var i = 0; i + 1 < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)]);

Map<String, int> _intMap(Object? m) => {
      if (m is Map)
        for (final e in m.entries)
          if (e.value is int) '${e.key}': e.value as int
    };

_ReconcileTake? _reconcileTakeFrom(Map<String, dynamic> j) {
  final rid = j['rid'], from = j['from'];
  if (rid is! String || from is! String) return null;
  final t = _ReconcileTake(_bytesR(rid), from)
    ..cutMs = j['cut'] as int? ?? 0
    ..partsTotal = j['pt'] as int? ?? 0
    ..window = j['w'] as int? ?? kReconcileWindow;
  for (final p in (j['parts'] as List? ?? const [])) {
    if (p is List && p.length == 2 && p[0] is int && p[1] is String) {
      final h = proto.ReconcileHeader.fromBuffer(_bytesR(p[1] as String));
      t.parts[p[0] as int] = h;
      for (final c in h.chats) {
        t.chats[_hexR(c.convId)] = c;
      }
    }
  }
  final open = j['open'];
  if (open is Map) {
    for (final e in open.entries) {
      final k = proto.ReconcileFetch_Kind.valueOf(e.value as int? ?? -1);
      if (k != null) t.open['${e.key}'] = k;
    }
  }
  t.gotBy.addAll(_intMap(j['got']));
  t.reportedBy.addAll(_intMap(j['rep']));
  t.totalBy.addAll(_intMap(j['tot']));
  t.tooLarge.addAll(_intMap(j['tl']));
  final seq = j['seq'];
  if (seq is Map) {
    for (final e in seq.entries) {
      t.gotSeqs['${e.key}'] = {for (final x in (e.value as List)) x as int};
    }
  }
  final mc = j['mc'];
  if (mc is Map) {
    for (final e in mc.entries) {
      t.manifestConvs['${e.key}'] = [for (final x in (e.value as List)) '$x'];
    }
  }
  t.manifestFlagged.addAll([for (final x in (j['mf'] as List? ?? const [])) '$x']);
  final mi = j['mi'];
  if (mi is Map) {
    for (final e in mi.entries) {
      t.manifestIds['${e.key}'] = [for (final x in (e.value as List)) _bytesR('$x')];
    }
  }
  for (final b in (j['pb'] as List? ?? const [])) {
    t.pendingBatches.add([for (final x in (b as List)) _bytesR('$x')]);
  }
  final ac = j['ac'];
  if (ac is Map) {
    for (final e in ac.entries) {
      t.attachmentConvs['${e.key}'] = '${e.value}';
    }
  }
  t.attachmentsNotCarried
      .addAll([for (final x in (j['nc'] as List? ?? const [])) '$x']);
  return t;
}

final Expando<Map<String, _ReconcileServe>> _reconcileServes =
    Expando('reconcile-serve');
final Expando<Map<String, _ReconcileTake>> _reconcileTakes =
    Expando('reconcile-take');

extension CleonaServiceReconcile on CleonaService {
  Map<String, _ReconcileServe> get _serves =>
      _reconcileServes[this] ??= <String, _ReconcileServe>{};
  Map<String, _ReconcileTake> get _takes =>
      _reconcileTakes[this] ??= <String, _ReconcileTake>{};

  // ── Source ─────────────────────────────────────────────────────────────

  /// After a handover to the own device [toHex] (its DeviceID in this
  /// identity's set): the header of the initial reconciliation (§14.6.3).
  void reconcileBegin(String toHex) {
    if (!_devices.containsKey(toHex) || toHex == _localDeviceId) return;
    final id = SodiumFFI().randomBytes(16);
    final cut = DateTime.now().millisecondsSinceEpoch;
    final chats = <proto.ReconcileChat>[];
    for (final e in conversations.entries) {
      final c = e.value;
      final convId = hexToBytes(e.key);
      final h = store.historyBefore(convId, beforeTs: cut);
      chats.add(proto.ReconcileChat()
        ..convId = convId
        ..displayName = c.displayName
        ..lastActivityMs = Int64(c.lastActivity.millisecondsSinceEpoch)
        ..isGroup = c.isGroup
        ..isChannel = c.isChannel
        ..isFavorite = c.isFavorite
        ..unreadCount = c.unreadCount
        ..configJson = utf8.encode(jsonEncode({'config': c.config.toJson()}))
        ..count = Int64(h.count)
        ..oldestMs = Int64(h.oldestTs)
        ..bytes = Int64(h.bytes)
        ..files = _reconcileFilesOf(e.key).length
        ..fileBytes = Int64(_reconcileFilesOf(e.key)
            .fold<int>(0, (n, f) => n + f.size)));
    }
    final serve = _ReconcileServe(id)..cutMs = cut;
    _serves[toHex] = serve;
    final header =
        reconcileHeaderFrames(reconcileId: id, cutMs: cut, chats: chats);
    serve.headerFrames
        .addAll([for (final h in header) Uint8List.fromList(h.writeToBuffer())]);
    serve.queue.addAll(header);
    _log.info('Type 20 (§14.6.3): header of ${chats.length} conversation(s) '
        'for device ${toHex.substring(0, 8)} (${serve.queue.length} packet(s))');
    _reconcilePump(toHex);
  }

  /// Places what the window of [toHex] still takes (§14.6.3: at most
  /// [kReconcileSourceAtMost] under one device value until progress).
  void _reconcilePump(String toHex) {
    final s = _serves[toHex];
    if (s == null) return;
    var placed = 0;
    while (s.queue.isNotEmpty && s.outstanding < s.window.size) {
      s.window.take();
      final f = s.queue.removeAt(0);
      final key = _reconcileFetchOf(f);
      // §14.6.3: numbered per fetch, so the recipient knows when a fetch is
      // whole whatever order the post box hands the packets out in.
      if (f.hasDeliver()) f.deliver.seq = s.placedBy[key] ?? 0;
      if (f.hasAttachment()) {
        f.attachment
          ..seq = s.placedBy[key] ?? 0
          ..complete = !s.queue.any((g) => _reconcileFetchOf(g) == key);
      }
      s.placedBy[key] = (s.placedBy[key] ?? 0) + 1;
      if (f.hasDeliver()) {
        f.deliver.roundEnd =
            s.queue.isEmpty || s.outstanding >= s.window.size;
        // The last packet OF THIS FETCH — packets of a later fetch may wait
        // behind it.
        f.deliver.complete =
            !s.queue.any((g) => _reconcileFetchOf(g) == key);
      }
      // Only a piece WITH file data is kept out of the post box; the empty
      // closing piece ("nothing carried") must reach the device either way.
      _reconcilePlace(toHex, reconcileEncode(f), s,
          attachment: f.hasAttachment() && f.attachment.data.isNotEmpty,
          fetchKey: key);
      placed++;
    }
    if (placed > 0) {
      _log.info('Type 20: $placed packet(s) to ${toHex.substring(0, 8)}, '
          '${s.outstanding} of ${s.window.size} outstanding, '
          '${s.queue.length} waiting for the progress report');
    }
    _reconcileServeSave(toHex);
  }

  void _reconcileServeSave(String toHex) {
    final s = _serves[toHex];
    try {
      if (s == null) {
        store.removeEntry(kReconcileServeArea, toHex);
      } else {
        store.putEntry(kReconcileServeArea, toHex, _reconcileServeJson(s));
      }
    } on Object catch (e) {
      _log.warn('Type 20: serving state not written — $e');
    }
  }

  void _reconcileTakeSave(_ReconcileTake t) {
    try {
      store.putEntry(kReconcileTakeArea, t.fromHex, _reconcileTakeJson(t));
    } on Object catch (e) {
      _log.warn('Type 20: reconciliation state not written — $e');
    }
  }

  /// After a start (§13.5.2 "resumable after an interruption"): the
  /// reconciliations this device serves and takes are read back. A served
  /// one rebuilds its queue from the header and the fetches — skipping what
  /// it had placed — and places what the window takes; no clock, nothing is
  /// sent again that was placed.
  void reconcileResume() {
    if (_serves.isNotEmpty || _takes.isNotEmpty) return;
    try {
      for (final e in store.loadArea(kReconcileTakeArea).entries) {
        final t = _reconcileTakeFrom(e.value);
        if (t != null) _takes[e.key] = t;
      }
      for (final e in store.loadArea(kReconcileServeArea).entries) {
        final j = e.value;
        final rid = j['rid'];
        if (rid is! String) continue;
        final s = _ReconcileServe(_bytesR(rid))..cutMs = j['cut'] as int? ?? 0;
        s.headerFrames.addAll(
            [for (final x in (j['h'] as List? ?? const [])) _bytesR('$x')]);
        s.fetches.addAll(
            [for (final x in (j['f'] as List? ?? const [])) _bytesR('$x')]);
        s.placedBy.addAll(_intMap(j['p']));
        s.reportedBy.addAll(_intMap(j['r']));
        final header = [
          for (final b in s.headerFrames) proto.ReconcileFrame.fromBuffer(b)
        ];
        s.queue.addAll(header.skip(s.placedBy[''] ?? 0));
        for (final b in s.fetches) {
          final q = proto.ReconcileFetch.fromBuffer(b);
          if (q.window != 0) s.window = ReconcileWindow(size: q.window);
          final frames = _reconcileFramesFor(e.key, s, q) ?? const [];
          s.queue.addAll(frames.skip(s.placedBy[_hexR(q.fetchId)] ?? 0));
        }
        _serves[e.key] = s;
      }
    } on Object catch (e) {
      _log.warn('Type 20: state not readable after the start — $e');
      return;
    }
    if (_serves.isEmpty && _takes.isEmpty) return;
    _log.info('Type 20: resumed — serving ${_serves.length}, taking '
        '${_takes.length} reconciliation(s)');
    for (final k in _serves.keys.toList()) {
      _reconcilePump(k);
    }
    onStateChanged?.call();
  }

  /// Test door: forget the reconciliation state held in memory — as a
  /// restart of the process does; the store keeps it.
  @visibleForTesting
  void reconcileForgetForTesting() {
    _serves.clear();
    _takes.clear();
  }

  /// One packet of the source to [toHex] (§14.6.3, §14.7 "Type 20 on the LAN
  /// while both devices are present"): directly on step 1 when this device
  /// knows a segment address of [toHex] it can speak to, and only on the
  /// recipient's end mark counted as arrived; otherwise — no address, or no
  /// answer on step 1 — the same envelope (same `sync_id`, the recipient
  /// takes it once) goes to the post box.
  void _reconcilePlace(String toHex, Uint8List payload, _ReconcileServe s,
      {bool attachment = false, String? fetchKey}) {
    final syncId = SodiumFFI().randomBytes(16);
    _processedSyncIds[bytesToHex(syncId)] = DateTime.now().millisecondsSinceEpoch;
    final envelope = buildTwinSyncEnvelope(
      syncId: syncId,
      deviceId: hexToBytes(_localDeviceId),
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      syncType: proto.TwinSyncType.RECONCILE,
      payload: payload,
      where: _ownWhereWires(),
    );
    final to = hexToBytes(toHex);
    unawaited(() async {
      final p = myceliumMailbox;
      var direct = false;
      if (p != null) {
        final frame = _innerFrame(
          recipientUserId: identity.userId,
          senderUserId: identity.userId,
          messageId: SodiumFFI().randomBytes(16),
          messageType: proto.MessageType.MT_TWIN_SYNC,
          payload: envelope,
        );
        try {
          direct = await mycelium.MailboxOwnSignal(p)
              .ownDirect(Uint8List.fromList(frame.writeToBuffer()), to);
        } on Object catch (e) {
          _log.warn('Type 20: direct step failed ($e) — the post box carries it');
        }
      }
      if (direct) {
        s.direct++;
        return;
      }
      if (attachment) {
        // §14.6.3: an attachment travels directly or on lane 3 — never as
        // post-box packets (each would lie with three holders for 7 days).
        // Lane 3 between own devices is not built (report S422 §9). The rest
        // of this fetch is dropped, and ONE empty closing piece tells the
        // device that nothing more is carried.
        s.attachmentsLost++;
        _log.warn('Type 20: an attachment piece did not arrive on the LAN — '
            'not placed in the post box; lane 3 between own devices is not '
            'built');
        if (fetchKey != null && s.attachmentsEnded.add(fetchKey)) {
          // §9.4 "The rest goes into the network": the rest of this fetch
          // goes on lane 3 as one bundle (the device takes a file it already
          // holds only once).
          s.queue.removeWhere((g) => _reconcileFetchOf(g) == fetchKey);
          final q = s.fetches
              .map(proto.ReconcileFetch.fromBuffer)
              .where((x) => _hexR(x.fetchId) == fetchKey)
              .firstOrNull;
          if (q != null && s.laneThreeStarted.add(fetchKey)) {
            unawaited(_reconcileLaneThree(toHex, s, q.fetchId,
                [for (final c in q.convIds) Uint8List.fromList(c)]));
          }
        }
        return;
      }
      s.viaPostBox++;
      await _myceliumOwnSend(
          messageType: proto.MessageType.MT_TWIN_SYNC,
          payload: envelope,
          targetDeviceId: to);
    }());
  }

  /// Test door: packets to [toHex] that arrived directly on the LAN, and
  /// those the post box carried.
  @visibleForTesting
  ({int direct, int postBox}) reconcileWaysForTesting(String toHex) => (
        direct: _serves[toHex]?.direct ?? 0,
        postBox: _serves[toHex]?.viaPostBox ?? 0,
      );

  /// Test door: packets the source placed in the current round for [toHex].
  @visibleForTesting
  int reconcilePlacedForTesting(String toHex) =>
      _serves[toHex]?.outstanding ?? 0;

  /// Test door: packets waiting for [toHex]'s progress report.
  @visibleForTesting
  int reconcileWaitingForTesting(String toHex) =>
      _serves[toHex]?.queue.length ?? 0;

  proto.ReconcileMessage _reconcileRecord(Map<String, Object?> r) {
    final m = proto.ReconcileMessage()
      ..id = r['id'] as Uint8List
      ..convId = r['convId'] as Uint8List
      ..tsMs = Int64(r['ts'] as int)
      ..type = r['type'] as int
      ..outgoing = r['isOutgoing'] == true
      ..status = (r['status'] as String?) ?? ''
      ..text = (r['text'] as String?) ?? '';
    if (r['sender'] != null) m.sender = r['sender'] as Uint8List;
    final extra = r['extra'];
    if (extra is Map && extra.isNotEmpty) {
      // Where THIS device keeps a file and how far it got with it is local
      // (§14.6.2 "NOT: … individual per device"): the new device gets the
      // attachment with its own consent (ATTACHMENTS fetch) and names its own
      // path then.
      final copy = Map<String, dynamic>.from(extra)
        ..remove('filePath')
        ..remove('mediaState')
        ..remove('failureReason');
      if (copy.isNotEmpty) m.extraJson = utf8.encode(jsonEncode(copy));
    }
    return m;
  }

  void _reconcileFetchIn(String fromHex, proto.ReconcileFrame f) {
    final s = _serves[fromHex];
    if (s == null || !_sameBytesR(s.reconcileId, f.reconcileId)) {
      _log.warn('Type 20: fetch of ${fromHex.substring(0, 8)} names no '
          'reconciliation of this device — ignored');
      return;
    }
    final q = f.fetch;
    final key = _hexR(q.fetchId);
    if (s.fetches.any((b) =>
        _hexR(proto.ReconcileFetch.fromBuffer(b).fetchId) == key)) {
      _log.info('Type 20: fetch ${key.substring(0, 8)} known already — '
          'nothing queued again');
      return;
    }
    final window = q.window == 0 ? kReconcileWindow : q.window;
    s.window = ReconcileWindow(size: window);
    // A new fetch: what the earlier one left outstanding stays counted.
    final frames = _reconcileFramesFor(fromHex, s, q);
    if (frames == null) return;
    s.fetches.add(Uint8List.fromList(q.writeToBuffer()));
    s.queue.addAll(frames);
    _log.info('Type 20: fetch ${q.kind.name} of ${fromHex.substring(0, 8)} '
        '(window $window) — ${s.queue.length} packet(s) queued');
    _reconcilePump(fromHex);
  }

  /// The packets that answer [q] — built from the store, the same again
  /// after a restart (the fetch names its conversations or identifiers and
  /// the cut). `null` for a kind own devices do not ask.
  /// The attachments of [convHex] this device holds: per file message its
  /// identifier, media path and size, by time (the same order after a
  /// restart).
  List<({String id, String path, int size})> _reconcileFilesOf(String convHex) {
    final c = conversations[convHex];
    if (c == null) return const [];
    ensureLoaded(convHex);
    final out = <({String id, String path, int size, int ts})>[];
    for (final m in c.messages) {
      final p = m.filePath;
      if (p == null || p.isEmpty) continue;
      if (!MediaStore.instance.existsEitherWay(p)) continue;
      final n = MediaStore.instance.plainLength(p) ?? m.fileSize ?? 0;
      out.add((id: m.id, path: p, size: n, ts: m.timestamp.millisecondsSinceEpoch));
    }
    out.sort((a, b) => a.ts != b.ts ? a.ts.compareTo(b.ts) : a.id.compareTo(b.id));
    return [for (final f in out) (id: f.id, path: f.path, size: f.size)];
  }

  /// The pieces of the attachments of [convs] (§14.6.3 "one transfer") — only
  /// when [toHex] is reachable directly on the LAN; the other way the norm
  /// names, lane 3 with its consent, is not built for own devices (report
  /// S422 §9): then one empty, closing piece says so.
  List<proto.ReconcileFrame> _reconcileAttachmentFrames(String toHex,
      _ReconcileServe s, List<int> fetchId, List<Uint8List> convs) {
    final out = <proto.ReconcileFrame>[];
    if (!_reconcileWayDirect(toHex)) {
      // §14.6.3 "… or on lane 3 with its consent" (S422): one bulk object
      // for the conversation's attachments; its announcement follows as one
      // piece once it is placed. Started once per fetch (also after a
      // restart, when nothing of it had gone out yet).
      final key = _hexR(fetchId);
      if ((s.placedBy[key] ?? 0) == 0 && s.laneThreeStarted.add(key)) {
        unawaited(_reconcileLaneThree(toHex, s, fetchId, convs));
      }
      return out;
    }
    for (final c in convs) {
      for (final f in _reconcileFilesOf(_hexR(c))) {
        final data = MediaStore.instance.readAll(f.path);
        if (data == null) continue;
        final parts = data.isEmpty
            ? 1
            : (data.length + kReconcileAttachmentPiece - 1) ~/
                kReconcileAttachmentPiece;
        for (var k = 0; k < parts; k++) {
          final end = (k + 1) * kReconcileAttachmentPiece;
          out.add(proto.ReconcileFrame()
            ..reconcileId = s.reconcileId
            ..attachment = (proto.ReconcileAttachment()
              ..fetchId = fetchId
              ..messageId = hexToBytes(f.id)
              ..convId = c
              ..part = k
              ..parts = parts
              ..size = Int64(data.length)
              ..data = data.sublist(k * kReconcileAttachmentPiece,
                  end > data.length ? data.length : end)));
        }
      }
    }
    if (out.isEmpty) {
      out.add(proto.ReconcileFrame()
        ..reconcileId = s.reconcileId
        ..attachment = (proto.ReconcileAttachment()..fetchId = fetchId));
    }
    return out;
  }

  /// Lane 3 for an own device (§9.4, §14.6.3): the attachments of [convs] as
  /// ONE object — `u32 index length ‖ index JSON [{id, n}] ‖ the files` —
  /// placed with the holders lane 3 takes (`bulkPlaceFor`, no contact named:
  /// this device's fixed neighbours, then other reachable nodes), under a
  /// fresh `K_T`; the announcement goes as one Type 20 piece on the own line
  /// (sealed like every own-line deposit). Nothing placed: an empty closing
  /// piece says "not carried".
  Future<void> _reconcileLaneThree(String toHex, _ReconcileServe s,
      List<int> fetchId, List<Uint8List> convs) async {
    final p = myceliumMailbox;
    final index = <Map<String, dynamic>>[];
    final body = BytesBuilder(copy: false);
    for (final c in convs) {
      for (final f in _reconcileFilesOf(_hexR(c))) {
        final data = MediaStore.instance.readAll(f.path);
        if (data == null) continue;
        index.add({'id': f.id, 'c': _hexR(c), 'n': data.length});
        body.add(data);
      }
    }
    final head = utf8.encode(jsonEncode(index));
    final object = (BytesBuilder(copy: false)
          ..add(Uint8List(4)..buffer.asByteData().setUint32(0, head.length))
          ..add(head)
          ..add(body.takeBytes()))
        .takeBytes();
    proto.ReconcileAttachment piece = proto.ReconcileAttachment()
      ..fetchId = fetchId;
    if (p != null && index.isNotEmpty) {
      try {
        final placed = await p.bulkPlaceForOwnDevice(hexToBytes(toHex), object,
            transferKey: transferKeyDraw());
        if (!placed.failed) {
          piece = piece
            ..bulkAnnouncement = p.bulkAnnouncement(placed)
            ..convId = convs.first
            ..size = Int64(object.length);
          _log.info('Type 20: attachments of ${convs.length} conversation(s) '
              '(${index.length} file(s), ${object.length} B) placed on lane 3 '
              'with ${placed.holders.length} holder(s) for '
              '${toHex.substring(0, 8)}');
        } else {
          _log.warn('Type 20: lane 3 placing failed (${placed.reason}) — '
              'attachments not carried');
        }
      } on Object catch (e) {
        _log.warn('Type 20: lane 3 placing failed ($e) — attachments not '
            'carried');
      }
    }
    s.queue.add(proto.ReconcileFrame()
      ..reconcileId = s.reconcileId
      ..attachment = piece);
    _reconcilePump(toHex);
  }

  List<proto.ReconcileFrame>? _reconcileFramesFor(
      String toHex, _ReconcileServe s, proto.ReconcileFetch q) {
    final out = <proto.ReconcileFrame>[];
    final convs = q.convIds.isEmpty
        ? ([for (final k in conversations.keys) k]..sort())
            .map(hexToBytes)
            .toList()
        : [for (final c in q.convIds) Uint8List.fromList(c)];
    final before = q.beforeMs == 0
        ? (s.cutMs == 0 ? DateTime.now().millisecondsSinceEpoch + 1 : s.cutMs)
        : q.beforeMs.toInt();
    switch (q.kind) {
      case proto.ReconcileFetch_Kind.NEWEST:
        final ids = <Uint8List>[];
        for (final c in convs) {
          ids.addAll(store
              .manifestPage(c,
                  beforeTs: before,
                  limit: q.newest == 0 ? kReconcileNewest : q.newest)
              .map((e) => e.id));
        }
        out.addAll(_reconcileDeliverFrames(s, q.fetchId, ids));
      case proto.ReconcileFetch_Kind.MANIFEST:
        final listed = <ReconcileListed>[];
        for (final c in convs) {
          for (final e in store.manifestPage(c,
              beforeTs: before, limit: 1 << 30)) {
            final entry = proto.ReconcileEntry()
              ..id = e.id
              ..tsMs = Int64(e.ts)
              ..type = e.type
              ..size = e.size;
            if (e.sender != null) entry.sender = e.sender!;
            listed.add((conv: c, entry: entry));
          }
        }
        out.addAll(reconcileManifestFrames(
            reconcileId: s.reconcileId, fetchId: q.fetchId, entries: listed));
      case proto.ReconcileFetch_Kind.MESSAGES:
        out.addAll(_reconcileDeliverFrames(
            s, q.fetchId, [for (final i in q.ids) Uint8List.fromList(i)]));
      case proto.ReconcileFetch_Kind.ATTACHMENTS:
        out.addAll(_reconcileAttachmentFrames(toHex, s, q.fetchId, convs));
      default:
        _log.warn('Type 20: fetch kind ${q.kind} is not one of own devices '
            '— ignored');
        return null;
    }
    return out;
  }

  List<proto.ReconcileFrame> _reconcileDeliverFrames(
      _ReconcileServe s, List<int> fetchId, List<Uint8List> ids) {
    final rows = store.messagesByIds(ids);
    final built = reconcileDeliverFrames(
        reconcileId: s.reconcileId,
        fetchId: fetchId,
        messages: [for (final r in rows) _reconcileRecord(r)]);
    if (built.frames.isEmpty) {
      // An empty answer still closes the fetch.
      return [
        proto.ReconcileFrame()
          ..reconcileId = s.reconcileId
          ..deliver = (proto.ReconcileDeliver()..fetchId = fetchId)
      ];
    }
    return built.frames;
  }

  // ── New device ─────────────────────────────────────────────────────────

  /// Type 20 from the own device [from] (its DeviceID).
  void _handleTwinReconcile(List<int> payload, Uint8List? from) {
    if (from == null) {
      _log.warn('Type 20: sender is no device of this set — discarded '
          '(the source serves only its own set, §14.6.3)');
      return;
    }
    final fromHex = bytesToHex(from);
    final f = reconcileDecode(Uint8List.fromList(payload));
    if (f == null) {
      _log.warn('Type 20 from ${fromHex.substring(0, 8)}: not readable');
      return;
    }
    if (f.hasFetch()) return _reconcileFetchIn(fromHex, f);
    if (f.hasProgress()) {
      final s = _serves[fromHex];
      if (s == null) return;
      final key = _hexR(f.progress.fetchId);
      final got = f.progress.received;
      if (got > (s.reportedBy[key] ?? 0)) s.reportedBy[key] = got;
      s.window.progress();
      _reconcilePump(fromHex);
      return;
    }
    if (f.hasCancel()) {
      _serves.remove(fromHex);
      _reconcileServeSave(fromHex);
      _log.info('Type 20: ${fromHex.substring(0, 8)} cancelled');
      return;
    }
    if (f.hasHeader()) return _reconcileHeaderIn(fromHex, f);
    if (f.hasManifest()) return _reconcileManifestIn(fromHex, f);
    if (f.hasDeliver()) return _reconcileDeliverIn(fromHex, f);
    if (f.hasAttachment()) return _reconcileAttachmentIn(fromHex, f);
  }

  /// A piece of an attachment (§14.6.3): put together per message; a whole
  /// file goes into the media store (encrypted, S362) and its message names
  /// it. Counted and reported like deliver packets.
  void _reconcileAttachmentIn(String fromHex, proto.ReconcileFrame f) {
    final t = _takes[fromHex];
    if (t == null || !_sameBytesR(t.reconcileId, f.reconcileId)) return;
    final a = f.attachment;
    final fetchHex = _hexR(a.fetchId);
    if (!t.open.containsKey(fetchHex)) {
      _log.warn('Type 20: attachment piece seq=${a.seq} of a fetch not open '
          'here (${fetchHex.substring(0, 8)}) — not taken');
      return;
    }
    final seqs = t.gotSeqs.putIfAbsent(fetchHex, () => <int>{});
    seqs.add(a.seq);
    t.gotBy[fetchHex] = seqs.length;
    if (a.complete) t.totalBy[fetchHex] = a.seq + 1;
    if (a.messageId.isNotEmpty && a.parts > 0) {
      final msgHex = _hexR(a.messageId);
      // The pieces are kept in the store as they come (S422): a file cut by a
      // restart is put together from what arrived before it and after it —
      // the source places after a restart only what it had not placed.
      final pieces = t.filePieces[msgHex] ??= _reconcilePiecesLoad(msgHex);
      final data = Uint8List.fromList(a.data);
      if (!pieces.containsKey(a.part)) {
        pieces[a.part] = data;
        _reconcilePiecePut(msgHex, a.part, data);
      }
      if (pieces.length == a.parts) {
        t.filePieces.remove(msgHex);
        final all = BytesBuilder(copy: false);
        for (var k = 0; k < a.parts; k++) {
          all.add(pieces[k]!);
        }
        _reconcileFileTake(_hexR(a.convId), msgHex, all.takeBytes());
        _reconcilePiecesDrop(msgHex);
      }
    }
    // Lane 3 (S422, §14.6.3): the announcement of the bundle — collected from
    // the holders it names through the ordinary lane 3 collection; it is
    // taken apart when it arrives ([reconcileBundleArrived]).
    final bundle = a.bulkAnnouncement.isNotEmpty;
    if (bundle) {
      final ann = bulkAnnounceUnpack(Uint8List.fromList(a.bulkAnnouncement));
      if (ann != null) {
        final tag = tagHex(bulkTag(ann.transferKey));
        t.bundlesPending.add(tag);
        _bulkIncomingPut(tag, {
          'conv': _hexR(a.convId),
          'msg': fetchHex,
          'from': fromHex,
          'announce': _hexR(a.bulkAnnouncement),
          'mime': '',
          'at': DateTime.now().millisecondsSinceEpoch,
          'reconcile': true,
        });
        _log.info('Type 20: attachment bundle announced on lane 3 '
            '(${ann.length} B, ${ann.holders.length} holder(s)) — collecting');
        _bulkCollectStart(tag);
      }
    }
    // An empty closing piece: the source carried nothing (more) of this
    // fetch. The fetch ends here; a file it cut stays incomplete.
    final ended = !bundle && a.complete && a.messageId.isEmpty;
    if (ended) {
      final c = t.attachmentConvs[fetchHex];
      // "Not carried": fewer files here than the header announced.
      if (c != null &&
          _reconcileFilesOf(c).length < (t.chats[c]?.files ?? 0)) {
        t.attachmentsNotCarried.add(c);
      }
    }
    final got = t.gotBy[fetchHex]!;
    final total = t.totalBy[fetchHex];
    // A lane 3 announcement carries the whole rest of the fetch: pieces
    // numbered before it that did not arrive on the LAN went into the bundle
    // (finding P6-L3c, S422) — the fetch ends with it.
    final whole = ended || bundle || (total != null && got >= total);
    if (got - (t.reportedBy[fetchHex] ?? 0) >= _reconcileRound(t) || whole) {
      _reconcileProgress(t, fetchHex);
    }
    if (whole) t.open.remove(fetchHex);
    _reconcileTakeSave(t);
    onStateChanged?.call();
  }

  /// The pieces of [msgHex]'s attachment kept so far (`msg/part` keys in
  /// [kReconcilePieceArea]).
  Map<int, Uint8List> _reconcilePiecesLoad(String msgHex) {
    final out = <int, Uint8List>{};
    try {
      for (final e
          in store.loadAreaPrefix(kReconcilePieceArea, '$msgHex/').entries) {
        final part = int.tryParse(e.key.substring(msgHex.length + 1));
        final d = e.value['d'];
        if (part != null && d is String) out[part] = base64Decode(d);
      }
    } on Object catch (e) {
      _log.warn('Type 20: kept pieces of ${msgHex.substring(0, 8)} not '
          'readable — $e');
    }
    return out;
  }

  void _reconcilePiecePut(String msgHex, int part, Uint8List data) {
    try {
      store.putEntry(
          kReconcilePieceArea, '$msgHex/$part', {'d': base64Encode(data)});
    } on Object catch (e) {
      _log.warn('Type 20: piece $part of ${msgHex.substring(0, 8)} not '
          'kept — $e');
    }
  }

  void _reconcilePiecesDrop(String msgHex) {
    try {
      store.removeAreaPrefix(kReconcilePieceArea, '$msgHex/');
    } on Object catch (e) {
      _log.warn('Type 20: kept pieces of ${msgHex.substring(0, 8)} not '
          'removed — $e');
    }
  }

  /// A whole attachment of message [msgHex] in [convHex]: into the media
  /// store, and the message names it.
  void _reconcileFileTake(String convHex, String msgHex, Uint8List data) {
    final c = conversations[convHex];
    if (c == null) return;
    ensureLoaded(convHex);
    final msg = c.messages.where((m) => m.id == msgHex).firstOrNull;
    if (msg == null) {
      _log.warn('Type 20: attachment of ${msgHex.substring(0, 8)} — the '
          'message is not held here, file not kept');
      return;
    }
    final held = msg.filePath;
    if (held != null &&
        held.startsWith(profileDir) &&
        MediaStore.instance.existsEitherWay(held)) {
      return; // came already (directly on the LAN before the rest)
    }
    final mediaDir = Directory('$profileDir/media');
    if (!mediaDir.existsSync()) mediaDir.createSync(recursive: true);
    final name = (msg.filename?.isNotEmpty ?? false)
        ? msg.filename!
        : 'file_$msgHex';
    final path = CleonaService._uniqueMediaPath(mediaDir.path, name);
    MediaStore.instance.writeBytes(path, data); // encrypted (S362)
    msg
      ..filePath = path
      ..fileSize = data.length
      ..mediaState = MediaDownloadState.completed
      ..failureReason = null;
    persistMessage(convHex, msg);
    _log.info('Type 20: attachment of ${msgHex.substring(0, 8)} '
        '(${data.length} B) taken over');
  }

  /// The user's consent (§14.6.3, §24.4.5: "attachments per conversation as
  /// one transfer with one consent"): fetch the attachments of
  /// [conversationId]. `false` when no source announced it.
  ///
  /// OPEN (S422): the consent dialog before this call — its text (number of
  /// files and size, §24.4.5) waits for the translation; see the report
  /// `S422-BAU-G3-1-3-KOPPELN.md` §8a/§9.
  bool reconcileFetchAttachments(String conversationId) {
    for (final t in _takes.values) {
      if (!t.chats.containsKey(conversationId)) continue;
      final q = proto.ReconcileFetch()
        ..kind = proto.ReconcileFetch_Kind.ATTACHMENTS
        ..convIds.add(hexToBytes(conversationId));
      _reconcileFetch(t, q);
      t.attachmentConvs[_hexR(q.fetchId)] = conversationId;
      _reconcileTakeSave(t);
      _log.info('Type 20: attachments of ${conversationId.substring(0, 8)} '
          'asked of ${t.fromHex.substring(0, 8)} (user consent)');
      onStateChanged?.call();
      return true;
    }
    return false;
  }

  void _reconcileHeaderIn(String fromHex, proto.ReconcileFrame f) {
    var t = _takes[fromHex];
    if (t == null || !_sameBytesR(t.reconcileId, f.reconcileId)) {
      t = _ReconcileTake(Uint8List.fromList(f.reconcileId), fromHex);
      _takes[fromHex] = t;
    }
    final h = f.header;
    t.cutMs = h.cutMs.toInt();
    t.partsTotal = h.parts;
    if (t.parts.containsKey(h.part)) return; // a repeat changes nothing
    t.parts[h.part] = h;
    t.gotBy[''] = (t.gotBy[''] ?? 0) + 1;
    for (final c in h.chats) {
      final convHex = bytesToHex(Uint8List.fromList(c.convId));
      t.chats[convHex] = c;
      if (!conversations.containsKey(convHex)) {
        conversations[convHex] = Conversation(
          id: convHex,
          displayName: c.displayName,
          lastActivity:
              DateTime.fromMillisecondsSinceEpoch(c.lastActivityMs.toInt()),
          isGroup: c.isGroup,
          isChannel: c.isChannel,
          isFavorite: c.isFavorite,
          unreadCount: c.unreadCount,
        )..messagesLoaded = true;
        _upsertConversationRow(convHex, conversations[convHex]!);
      }
    }
    _reconcileTakeSave(t);
    if (t.parts.length < t.partsTotal) return;
    _log.info('Type 20 (§14.6.3): header of ${t.chats.length} conversation(s) '
        'from ${fromHex.substring(0, 8)} — the newest $kReconcileNewest of '
        'each follow');
    _reconcileProgress(t, '');
    _reconcileFetch(t, proto.ReconcileFetch()
      ..kind = proto.ReconcileFetch_Kind.NEWEST
      ..newest = kReconcileNewest
      ..beforeMs = Int64(t.cutMs));
    onStateChanged?.call();
  }

  void _reconcileFetch(_ReconcileTake t, proto.ReconcileFetch q) {
    q
      ..fetchId = SodiumFFI().randomBytes(16)
      ..window = t.window;
    final key = bytesToHex(Uint8List.fromList(q.fetchId));
    t.open[key] = q.kind;
    if (q.kind == proto.ReconcileFetch_Kind.MANIFEST) {
      t.manifestConvs[key] = [
        for (final c in q.convIds) bytesToHex(Uint8List.fromList(c))
      ];
    }
    _reconcileTakeSave(t);
    _sendTwinSync(
        proto.TwinSyncType.RECONCILE,
        reconcileEncode(proto.ReconcileFrame()
          ..reconcileId = t.reconcileId
          ..fetch = q),
        targetDeviceId: hexToBytes(t.fromHex));
  }

  /// The progress report for fetch [key] (hex, `''` = header): the
  /// CUMULATIVE count received — a late or repeated report is harmless.
  void _reconcileProgress(_ReconcileTake t, String key) {
    final got = t.gotBy[key] ?? 0;
    t.reportedBy[key] = got;
    _reconcileTakeSave(t);
    _sendTwinSync(
        proto.TwinSyncType.RECONCILE,
        reconcileEncode(proto.ReconcileFrame()
          ..reconcileId = t.reconcileId
          ..progress = (proto.ReconcileProgress()
            ..fetchId = key.isEmpty ? Uint8List(0) : hexToBytes(key)
            ..received = got)),
        targetDeviceId: hexToBytes(t.fromHex));
  }

  /// The packets the source holds at most per round, whatever was asked.
  int _reconcileRound(_ReconcileTake t) =>
      t.window < kReconcileSourceAtMost ? t.window : kReconcileSourceAtMost;

  void _reconcileDeliverIn(String fromHex, proto.ReconcileFrame f) {
    final t = _takes[fromHex];
    if (t == null || !_sameBytesR(t.reconcileId, f.reconcileId)) return;
    final d = f.deliver;
    final fetchHex = bytesToHex(Uint8List.fromList(d.fetchId));
    if (!t.open.containsKey(fetchHex)) {
      // Never silent (S422, finding P6-1): a packet of a fetch this device
      // does not (or no longer) wait for.
      _log.warn('Type 20: deliver packet seq=${d.seq} of a fetch not open '
          'here (${fetchHex.substring(0, 8)}) — ${d.messages.length} '
          'record(s) not taken');
      return;
    }
    // Counted by number: a packet that comes twice counts once.
    final seqs = t.gotSeqs.putIfAbsent(fetchHex, () => <int>{});
    seqs.add(d.seq);
    t.gotBy[fetchHex] = seqs.length;
    if (d.complete) t.totalBy[fetchHex] = d.seq + 1;
    var added = 0;
    for (final m in d.messages) {
      if (_reconcileTake(m)) added++;
    }
    for (final id in d.tooLarge) {
      final conv = d.messages.isEmpty
          ? ''
          : bytesToHex(Uint8List.fromList(d.messages.first.convId));
      t.tooLarge[conv] = (t.tooLarge[conv] ?? 0) + 1;
      _log.warn('Type 20: record ${bytesToHex(Uint8List.fromList(id)).substring(0, 8)} '
          'too large for the reconciliation — named, not taken');
    }
    _log.info('Type 20: ${d.messages.length} record(s), $added new');
    // Reported after a full window of new packets or when the fetch is whole
    // — counted, not at a mark: the post box keeps no order, the `complete`
    // or `round_end` packet can arrive before the rest (finding P6-1).
    final got = t.gotBy[fetchHex]!;
    final total = t.totalBy[fetchHex];
    final whole = total != null && got >= total;
    if (got - (t.reportedBy[fetchHex] ?? 0) >= _reconcileRound(t) || whole) {
      _reconcileProgress(t, fetchHex);
    }
    if (whole) {
      t.open.remove(fetchHex);
      if (t.pendingBatches.isNotEmpty) {
        _reconcileFetch(t, proto.ReconcileFetch()
          ..kind = proto.ReconcileFetch_Kind.MESSAGES
          ..ids.addAll(t.pendingBatches.removeAt(0)));
      }
    }
    _reconcileTakeSave(t);
    onStateChanged?.call();
  }

  /// One record into the store and, where the conversation is in memory,
  /// into it — never over what arrived meanwhile. Returns whether it was new.
  bool _reconcileTake(proto.ReconcileMessage m) {
    Map<String, dynamic>? extra;
    if (m.extraJson.isNotEmpty) {
      try {
        final j = jsonDecode(utf8.decode(m.extraJson));
        if (j is Map<String, dynamic>) extra = j;
      } catch (_) {
        // Unreadable rarer fields: the record is taken without them.
      }
    }
    final id = Uint8List.fromList(m.id);
    final conv = Uint8List.fromList(m.convId);
    final inserted = store.insertMessageIfAbsent(
      id: id,
      convId: conv,
      sender: m.sender.isEmpty ? null : Uint8List.fromList(m.sender),
      ts: m.tsMs.toInt(),
      type: m.type,
      status: m.status,
      isOutgoing: m.outgoing,
      text: m.text,
      extra: extra,
    );
    if (!inserted) return false;
    final convHex = bytesToHex(conv);
    final c = conversations[convHex];
    if (c == null) return true;
    // §21.4.1: load before reading the history. A conversation that holds
    // only its window (`messagesLoaded == false`, e.g. after a restart in
    // the middle of the reconciliation) skipped the record here and its
    // `totalMessages` stayed short (S422-RCA-E2E-LAUF-4.2.8 R-6). The record
    // is in the store already, so loading brings it along; a conversation
    // that was loaded takes it below.
    ensureLoaded(convHex);
    if (!c.messagesLoaded) return true; // load failed — ensureLoaded logged it
    final row = store.messagesByIds([id]);
    if (row.isNotEmpty) {
      final msg = CleonaService.messageFromStoreRow(row.first);
      if (!msg.isDeleted && !c.messages.any((x) => x.id == msg.id)) {
        c.messages
          ..add(msg)
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        c.totalMessages = c.messages.length;
      }
    }
    return true;
  }

  void _reconcileManifestIn(String fromHex, proto.ReconcileFrame f) {
    final t = _takes[fromHex];
    if (t == null || !_sameBytesR(t.reconcileId, f.reconcileId)) return;
    final man = f.manifest;
    final fetchHex = bytesToHex(Uint8List.fromList(man.fetchId));
    if (!t.open.containsKey(fetchHex)) {
      _log.warn('Type 20: manifest packet of a fetch not open here '
          '(${fetchHex.substring(0, 8)}) — not taken');
      return;
    }
    t.gotBy[fetchHex] = (t.gotBy[fetchHex] ?? 0) + 1;
    final ids = t.manifestIds.putIfAbsent(fetchHex, () => []);
    for (final c in man.chats) {
      ids.addAll(c.entries.map((e) => Uint8List.fromList(e.id)));
      if (c.complete) {
        t.manifestFlagged
            .add('$fetchHex/${bytesToHex(Uint8List.fromList(c.convId))}');
      }
    }
    // Whole when every asked conversation's last packet came AND as many
    // entries as the header announced — the post box keeps no order, so the
    // flagged packet can come before the others (finding P6-1).
    final asked = t.manifestConvs[fetchHex] ?? const <String>[];
    final expected = asked.fold<int>(
        0, (n, c) => n + (t.chats[c]?.count.toInt() ?? 0));
    final whole = asked.isNotEmpty &&
        asked.every((c) => t.manifestFlagged.contains('$fetchHex/$c')) &&
        ids.length >= expected;
    if (t.gotBy[fetchHex]! - (t.reportedBy[fetchHex] ?? 0) >=
            _reconcileRound(t) ||
        whole) {
      _reconcileProgress(t, fetchHex);
    }
    _reconcileTakeSave(t);
    if (!whole) return;
    // The manifest is whole: fetch what this device does not hold.
    t.open.remove(fetchHex);
    final all = t.manifestIds.remove(fetchHex)!;
    final held = {
      for (final r in store.messagesByIds(all)) bytesToHex(r['id'] as Uint8List)
    };
    final missing = [
      for (final id in all)
        if (!held.contains(bytesToHex(id))) (id: id, size: 0)
    ];
    final batches = reconcileFetchBatches(missing);
    _log.info('Type 20: manifest of ${all.length} message(s), '
        '${missing.length} missing here, ${batches.length} fetch(es)');
    if (batches.isEmpty) {
      onStateChanged?.call();
      return;
    }
    t.pendingBatches.addAll(batches.skip(1));
    _reconcileFetch(t, proto.ReconcileFetch()
      ..kind = proto.ReconcileFetch_Kind.MESSAGES
      ..ids.addAll(batches.first));
  }

  /// §14.6.3: "reconciling state" — a fetch of the initial reconciliation
  /// is open on this device.
  bool get reconcileRunning => _takes.values.any((t) =>
      t.open.isNotEmpty ||
      t.pendingBatches.isNotEmpty ||
      t.bundlesPending.isNotEmpty);

  /// Lane 3 (S422): the attachment bundle [tagKey] arrived whole (mycelium
  /// checked its SHA-256) — taken apart into the media store. No receipt to
  /// a contact: it is an own device's transfer (twin sync carries none,
  /// §9.2). Returns whether it was one of the reconciliation's.
  bool reconcileBundleArrived(String tagKey, Map<String, dynamic> e,
      Uint8List object) {
    if (e['reconcile'] != true) return false;
    try {
      final n = object.buffer.asByteData(object.offsetInBytes).getUint32(0);
      final index = jsonDecode(utf8.decode(object.sublist(4, 4 + n))) as List;
      var at = 4 + n;
      for (final x in index) {
        final m = x as Map;
        final len = m['n'] as int;
        _reconcileFileTake(m['c'] as String, m['id'] as String,
            Uint8List.fromList(object.sublist(at, at + len)));
        at += len;
      }
      _log.info('Type 20: attachment bundle from lane 3 taken apart — '
          '${index.length} file(s)');
    } on Object catch (err) {
      _log.warn('Type 20: attachment bundle not readable — $err');
    }
    for (final t in _takes.values) {
      if (t.bundlesPending.remove(tagKey)) _reconcileTakeSave(t);
    }
    _bulkIncomingRemove(tagKey);
    onStateChanged?.call();
    return true;
  }

  /// Lane 3 (S422): collecting the bundle [tagKey] failed for good — its
  /// conversation's attachments are "not carried".
  bool reconcileBundleFailed(String tagKey, Map<String, dynamic> e) {
    if (e['reconcile'] != true) return false;
    for (final t in _takes.values) {
      if (t.bundlesPending.remove(tagKey)) {
        t.attachmentsNotCarried.add(e['conv'] as String);
        _reconcileTakeSave(t);
      }
    }
    _bulkIncomingRemove(tagKey);
    onStateChanged?.call();
    return true;
  }

  /// The offer of the full history (§14.6.3 "offered with its size and
  /// way, not taken"): per conversation whose source holds more than this
  /// device — the source device's name, the count and size it announced,
  /// what this device holds, the way (`postBox`: the own line through the
  /// post box; the direct LAN carrier is not built), and how many records
  /// were too large.
  List<Map<String, dynamic>> get reconcileOffers {
    final out = <Map<String, dynamic>>[];
    for (final t in _takes.values) {
      for (final e in t.chats.entries) {
        final c = e.value;
        int held;
        try {
          held = store.historyBefore(hexToBytes(e.key), beforeTs: t.cutMs).count;
        } on Object {
          held = 0;
        }
        final filesHeld = _reconcileFilesOf(e.key).length;
        if (c.count.toInt() <= held &&
            (t.tooLarge[e.key] ?? 0) == 0 &&
            c.files <= filesHeld) {
          continue;
        }
        final direct = _reconcileWayDirect(t.fromHex);
        out.add({
          'conversationId': e.key,
          'device': _devices[t.fromHex]?.deviceName ?? t.fromHex.substring(0, 8),
          'count': c.count.toInt(),
          'bytes': c.bytes.toInt(),
          'held': held,
          'way': direct ? 'direct' : 'postBox',
          'tooLarge': t.tooLarge[e.key] ?? 0,
          // §14.6.3: the attachments as one transfer — directly on the LAN
          // (lane 3 between own devices is not built: `none` otherwise).
          'files': c.files,
          'fileBytes': c.fileBytes.toInt(),
          'filesHeld': filesHeld,
          'filesWay': direct ? 'direct' : 'none',
          'filesNotCarried': t.attachmentsNotCarried.contains(e.key),
        });
      }
    }
    return out;
  }

  /// Whether the source [fromHex] is reachable directly on the LAN: this
  /// device knows a segment address of it that its ladder can speak to
  /// (§14.7, from the source's own-line deposits).
  bool _reconcileWayDirect(String fromHex) {
    final p = myceliumMailbox;
    if (p == null) return false;
    final where = mycelium.ownWhereOf(p.identity)[fromHex];
    return where != null && where.segment.any(p.node.ladder.speaks);
  }

  /// The user's decision (§14.6.3): fetch the full history of
  /// [conversationId] from the device that announced it. `false` when no
  /// source announced it.
  bool reconcileFetchHistory(String conversationId) {
    for (final t in _takes.values) {
      if (!t.chats.containsKey(conversationId)) continue;
      _reconcileFetch(t, proto.ReconcileFetch()
        ..kind = proto.ReconcileFetch_Kind.MANIFEST
        ..convIds.add(hexToBytes(conversationId))
        ..beforeMs = Int64(t.cutMs));
      _log.info('Type 20: full history of ${conversationId.substring(0, 8)} '
          'asked of ${t.fromHex.substring(0, 8)} (user decision)');
      onStateChanged?.call();
      return true;
    }
    return false;
  }

  /// Test door: [reconcileFetchHistory] naming [window] packets per round —
  /// to measure that the source never holds more than
  /// [kReconcileSourceAtMost] under one device value.
  @visibleForTesting
  bool reconcileFetchHistoryForTesting(String conversationId, int window) {
    for (final t in _takes.values) {
      t.window = window;
    }
    return reconcileFetchHistory(conversationId);
  }

  static bool _sameBytesR(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
