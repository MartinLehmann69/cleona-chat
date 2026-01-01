// S398-W5 — nothing overtakes a file (v4_2 §9.4 "Nothing overtakes a file",
// §9.1, §16.2, §22.5.1, D-34).
//
// SENDER. Every leg — conversation plus recipient; in a group one per member
// (§16.2) — has a waiting LINE, persisted in the store area [kFileOrderArea]
// so that it survives a restart. A lane 2/3 file takes a slot in the line of
// each of its legs when it is sent. Every user message written to that leg
// afterwards (text, lane 1 media, a further file, a reaction … —
// [CleonaService.kFileOrderKinds]) waits behind it, `resting` (§9.1, pending
// mark §12.2), and goes out in writing order once the file is completely in
// the network — streamed to the end, or placed with holders AND its
// announcement handed over — or once it is `failed`. The waiting message
// carries the file's identifier (8 B: the first 8 bytes of the file's
// message identifier on this leg, `ApplicationFrameV3.after_file`). Lane 1
// is one ordinary message and is in the network at once; it takes no slot.
//
// ONE PLACE HOLDS: `sendToUser` hands every user message kind to
// [_fileOrderHold] before anything else, so no send path can forget it.
//
// A 1:1 file behind a file does not start its transfer (lane 2 needs its
// announcement answered within its window, §17.6; one transfer at a time):
// its sender record (`cleona_service_transfer.dart`) is written with the mark
// `waiting`, and its transfer — lane 2 or 3, as chosen — starts when its turn
// comes. A group file is placed at once, because its ONE placement serves
// every member (§9.4 "encode once, place once") and legs to different
// members must not wait on each other (§16.2); only its announcement to a
// member whose line is not at it yet is held in its slot.
//
// RECIPIENT. A message carrying a file identifier whose file is still
// incomplete makes the recipient collect from the holders at once (the
// collection of W1, rounds included); if the file cannot be assembled it
// ends `failed` with its reason and the sender is told (`MTV3_MEDIA_ABORT`,
// `bulkCollectionFailed`). The message itself is accepted and stored, and
// shown AFTER the file: [_fileOrderPlace] moves it behind the file, also
// when the file arrives only later.
//
// No clock: a line moves on the file's own events ("in the network",
// `failed`), at the attach and at the edges of §8.2 (`bulkEdge`).

part of 'cleona_service.dart';

/// Store area: the waiting lines, keyed by "conversation:recipient".
const String kFileOrderArea = 'file_order';

/// Files this run already asked for because a message after them came.
const int _kFileOrderAskedAtMost = 256;

extension CleonaServiceFileOrder on CleonaService {
  static String _key(String conversationId, String recipientHex) =>
      '$conversationId:$recipientHex';

  // ── The lines ─────────────────────────────────────────────────────────

  void _fileOrderEnsureLoaded() {
    if (_fileOrderLoaded) return;
    try {
      for (final e in store.loadArea(kFileOrderArea).entries) {
        final q = [
          for (final s in (e.value['q'] as List?) ?? const [])
            Map<String, dynamic>.from(s as Map)
        ];
        if (q.isEmpty) continue;
        _fileOrder[e.key] = q;
        for (final s in q) {
          if (s['frame'] != null) _fileOrderWaiting.add(s['wire'] as String);
        }
      }
      _fileOrderLoaded = true;
    } catch (x) {
      _log.warn('file order: lines not loaded — $x');
    }
  }

  void _fileOrderSave(String key) {
    final line = _fileOrder[key];
    try {
      if (line == null || line.isEmpty) {
        _fileOrder.remove(key);
        store.removeEntry(kFileOrderArea, key);
      } else {
        store.putEntry(kFileOrderArea, key, {'q': line});
      }
    } catch (x) {
      _log.warn('file order: line ${key.substring(0, 8)} not stored — $x');
    }
  }

  /// The file identifier the last slot of [line] stands behind.
  static String? _lastFile(List<Map<String, dynamic>> line) {
    for (final s in line.reversed) {
      final f = s['k'] == 'file' ? s['fid'] as String? : s['after'] as String?;
      if (f != null) return f;
    }
    return null;
  }

  /// How many messages of [conversationId] wait in a line, files included.
  @visibleForTesting
  int fileOrderWaiting(String conversationId) {
    _fileOrderEnsureLoaded();
    var n = 0;
    for (final e in _fileOrder.entries) {
      if (e.key.startsWith('$conversationId:')) n += e.value.length;
    }
    return n;
  }

  // ── Holding (called by `sendToUser`) ──────────────────────────────────

  /// `true`: the message waits in its line and goes later. `false`: it goes
  /// now — its line is empty, or it is the announcement of the file at the
  /// head of the line (then with the identifier that file waited behind).
  bool _fileOrderHold({
    required Uint8List recipientUserId,
    required proto.MessageTypeV3 messageType,
    required Uint8List payload,
    required Uint8List messageId,
    Uint8List? groupId,
    proto.ContentMetadata? contentMetadata,
    proto.EditMetadata? editMetadata,
    proto.ExpiryMetadata? expiryMetadata,
    int? groupMembershipEpoch,
    Uint8List? groupMembershipHash,
    bool management = false,
    Uint8List? postId,
  }) {
    _fileOrderEnsureLoaded();
    final to = bytesToHex(recipientUserId);
    final conv =
        (groupId != null && groupId.isNotEmpty) ? bytesToHex(groupId) : to;
    final key = _key(conv, to);
    final line = _fileOrder[key];
    if (line == null || line.isEmpty) return false;
    final wire = bytesToHex(messageId);
    final at = line.indexWhere((s) => s['wire'] == wire);
    if (at == 0) {
      // The file at the head announces itself — it is its turn.
      final after = line.first['after'] as String?;
      if (after != null) _fileOrderAfterFile[wire] = hexToBytes(after);
      return false;
    }
    final frame = <String, dynamic>{
      'to': to,
      'type': messageType.value,
      'payload': base64Encode(payload),
      'id': wire,
      if (groupId != null && groupId.isNotEmpty) 'group': bytesToHex(groupId),
      if (contentMetadata != null)
        'meta': base64Encode(contentMetadata.writeToBuffer()),
      if (editMetadata != null) 'edit': base64Encode(editMetadata.writeToBuffer()),
      if (expiryMetadata != null)
        'expiry': base64Encode(expiryMetadata.writeToBuffer()),
      'epoch': ?groupMembershipEpoch,
      if (groupMembershipHash != null) 'hash': bytesToHex(groupMembershipHash),
      if (management) 'mgmt': true,
      // §16.2: the post identifier of a group post waits with its leg.
      if (postId != null && postId.isNotEmpty) 'post': bytesToHex(postId),
    };
    if (at > 0) {
      // The announcement of a group file whose slot is not at the head
      // yet: it waits in its own place, not at the end.
      line[at]['frame'] = frame;
    } else {
      line.add({
        'k': 'frame',
        'conv': conv,
        'wire': wire,
        'after': _lastFile(line),
        'frame': frame,
      });
    }
    _fileOrderWaiting.add(wire);
    _fileOrderSave(key);
    _log.info('[E2E file-order-wait] ${messageType.name} '
        'msgId=${wire.substring(0, 8)} to ${to.substring(0, 8)} waits '
        '(place ${at > 0 ? at + 1 : line.length} of ${line.length}) behind '
        'file ${(line.first['fid'] as String?)?.substring(0, 8) ?? '-'}');
    return true;
  }

  // ── A file takes its place ────────────────────────────────────────────

  /// A lane 2/3 file [msg] to [legs] (recipient hex, wire identifier) takes
  /// a slot in each leg's line. `true` if the line of a 1:1 file was not
  /// empty — then its transfer must not start now ([fanout] is `false`).
  bool _fileOrderFile(UiMessage msg, List<(String, String)> legs,
      {required bool fanout}) {
    _fileOrderEnsureLoaded();
    var waits = false;
    for (final (to, wire) in legs) {
      final key = _key(msg.conversationId, to);
      final line = _fileOrder.putIfAbsent(key, () => []);
      final first = line.isEmpty;
      if (!first) waits = true;
      line.add({
        'k': 'file',
        'conv': msg.conversationId,
        'msg': msg.id,
        'wire': wire,
        'fid': wire.substring(0, kAfterFileLength * 2),
        'after': _lastFile(line),
        // A group file is placed at once (one placement for every member);
        // a 1:1 file starts when it is at the head.
        'started': first || fanout,
        'done': false,
      });
      _fileOrderSave(key);
    }
    if (waits) {
      _log.info('[E2E file-order-wait] file msgId=${msg.id.substring(0, 8)} '
          'waits behind an earlier file on ${fanout ? 'some legs' : 'its leg'}');
    }
    return waits && !fanout;
  }

  // ── Release: in the network, or failed ────────────────────────────────

  /// The file [msg] is completely in the network with its announcement
  /// handed over, or `failed` (D-34): the lines behind it move on.
  void _fileOrderRelease(UiMessage msg) {
    if (!msg.isOutgoing) return;
    _fileOrderEnsureLoaded();
    final touched = <String>[];
    for (final e in _fileOrder.entries) {
      var hit = false;
      for (final s in e.value) {
        if (s['k'] == 'file' && s['msg'] == msg.id && s['done'] != true) {
          s['done'] = true;
          hit = true;
        }
      }
      if (hit) touched.add(e.key);
    }
    for (final key in touched) {
      _fileOrderSave(key);
      _log.info('[E2E file-order-release] file msgId=${msg.id.substring(0, 8)} '
          '${msg.status == MessageStatus.failed ? 'failed' : 'in the network'} '
          '— line ${key.substring(key.indexOf(':') + 1, key.indexOf(':') + 9)} '
          'moves on');
      unawaited(_fileOrderDrain(key));
    }
  }

  /// At the attach and at every edge of §8.2: a started file whose sender
  /// record is gone (handed over or dropped while the process ended) is
  /// done; a waiting record whose slot is gone starts; every line moves on.
  void _fileOrderResume() {
    if (_disposed) return;
    _fileOrderEnsureLoaded();
    Map<String, Map<String, dynamic>> records;
    try {
      records = store.loadArea(kMediaOutgoingArea);
    } catch (x) {
      _log.warn('file order: sender records not loaded — $x');
      return;
    }
    final inLine = <String>{};
    for (final e in _fileOrder.entries) {
      var changed = false;
      for (final s in e.value) {
        if (s['k'] != 'file') continue;
        final id = s['msg'] as String;
        inLine.add(id);
        if (s['started'] == true &&
            s['done'] != true &&
            !records.containsKey(id) &&
            !_transfersRunning.contains(id)) {
          s['done'] = true;
          changed = true;
        }
      }
      if (changed) _fileOrderSave(e.key);
    }
    var orphans = 0;
    for (final r in records.values) {
      if (r['waiting'] == true && !inLine.contains(r['msg'])) {
        r.remove('waiting');
        r['at'] = DateTime.now().millisecondsSinceEpoch;
        _transferRecordPut(r);
        orphans++;
      }
    }
    if (orphans > 0) {
      _log.warn('file order: $orphans waiting record(s) without a line — '
          'they start now');
      _transferResume();
    }
    for (final key in _fileOrder.keys.toList()) {
      unawaited(_fileOrderDrain(key));
    }
  }

  // ── Moving a line on ──────────────────────────────────────────────────

  /// Hands on what is due at the head of line [key], in order, until a file
  /// that is not yet in the network stands at the head.
  Future<void> _fileOrderDrain(String key) async {
    if (_disposed) return;
    if (!_fileOrderDraining.add(key)) {
      _fileOrderAgain.add(key);
      return;
    }
    try {
      do {
        _fileOrderAgain.remove(key);
        while (!_disposed) {
          final line = _fileOrder[key];
          if (line == null || line.isEmpty) break;
          final head = line.first;
          final frame = head['frame'] as Map<String, dynamic>?;
          if (head['k'] == 'file') {
            final msg =
                _bulkMessage(head['conv'] as String, head['msg'] as String);
            final gone = msg == null || msg.status == MessageStatus.failed;
            if (gone || head['done'] == true) {
              if (frame != null && !gone) {
                await _fileOrderSend(head, frame);
              } else if (frame != null) {
                _fileOrderWaiting.remove(head['wire']);
              }
              line.remove(head);
              _fileOrderSave(key);
              continue;
            }
            if (head['started'] != true) {
              head['started'] = true;
              _fileOrderSave(key);
              _fileOrderStart(head, msg);
            }
            break;
          }
          if (frame != null) await _fileOrderSend(head, frame);
          line.remove(head);
          _fileOrderSave(key);
        }
      } while (_fileOrderAgain.contains(key) && !_disposed);
    } finally {
      _fileOrderDraining.remove(key);
    }
  }

  /// A 1:1 file whose turn came: its transfer starts from its sender record,
  /// on the lane chosen when it was sent.
  void _fileOrderStart(Map<String, dynamic> slot, UiMessage msg) {
    Map<String, dynamic>? r;
    try {
      r = store.loadArea(kMediaOutgoingArea)[msg.id];
    } catch (x) {
      _log.warn('file order: record of ${msg.id.substring(0, 8)} not loaded — $x');
    }
    if (r == null) {
      return _mediaFail(msg, FailureReason.senderGaveUp,
          'the record of the waiting file is gone');
    }
    final object = _transferObjectLoad(r);
    if (object == null) {
      _transferRecordDrop(r);
      return _mediaFail(msg, FailureReason.senderGaveUp,
          'the waiting file is gone');
    }
    r
      ..remove('waiting')
      ..['at'] = DateTime.now().millisecondsSinceEpoch;
    _transferRecordPut(r);
    _log.info('[E2E file-order-start] file msgId=${msg.id.substring(0, 8)} '
        'lane=${r['lane']} — its turn came');
    final record = r;
    if (record['lane'] == 'stream') return _streamFromRecord(msg, object, record);
    _transfersRunning.add(msg.id);
    unawaited(_laneThree(msg, object, record)
        .whenComplete(() => _transfersRunning.remove(msg.id)));
  }

  /// Hands one waiting message on, carrying the identifier of the file it
  /// waited behind, and carries its state into the display.
  Future<void> _fileOrderSend(
      Map<String, dynamic> slot, Map<String, dynamic> f) async {
    final wire = f['id'] as String;
    final after = slot['after'] as String?;
    final type = proto.MessageTypeV3.valueOf(f['type'] as int) ??
        proto.MessageTypeV3.MTV3_TEXT;
    if (after != null) _fileOrderAfterFile[wire] = hexToBytes(after);
    Uint8List? hex(String k) =>
        f[k] == null ? null : hexToBytes(f[k] as String);
    final ok = await sendToUser(
      recipientUserId: hexToBytes(f['to'] as String),
      messageType: type,
      payload: base64Decode(f['payload'] as String),
      messageId: hexToBytes(wire),
      groupId: hex('group'),
      contentMetadata: f['meta'] == null
          ? null
          : proto.ContentMetadata.fromBuffer(base64Decode(f['meta'] as String)),
      editMetadata: f['edit'] == null
          ? null
          : proto.EditMetadata.fromBuffer(base64Decode(f['edit'] as String)),
      expiryMetadata: f['expiry'] == null
          ? null
          : proto.ExpiryMetadata.fromBuffer(
              base64Decode(f['expiry'] as String)),
      groupMembershipEpoch: f['epoch'] as int?,
      groupMembershipHash: hex('hash'),
      management: f['mgmt'] == true,
      postId: hex('post'),
      fileOrderChecked: true,
    );
    _fileOrderAfterFile.remove(wire);
    _fileOrderWaiting.remove(wire);
    _log.info('[E2E file-order-send] ${type.name} msgId=${wire.substring(0, 8)} '
        'to ${(f['to'] as String).substring(0, 8)} after file '
        '${after?.substring(0, 8) ?? '-'} handed=$ok');
    final owner = _fileOrderOwner(slot['conv'] as String, wire);
    if (owner == null) return;
    if (!ok &&
        owner.fanoutLegs.isEmpty &&
        (type == proto.MessageTypeV3.MTV3_TEXT ||
            type == proto.MessageTypeV3.MTV3_MEDIA_INLINE)) {
      // Nothing taken over: B-5 as in `sendTextMessage`, and B-6 as in
      // `sendMediaMessage` for a lane 1 file (S403, N-4) — the two kinds
      // that carry their OWN identifier (`_parkedOwner`). Without this the
      // file stayed `resting` with nothing that could ever carry it.
      _seamRefused(owner, 'file order');
    }
    final legs = owner.fanoutLegs.isEmpty
        ? <String>[owner.id]
        : owner.fanoutLegs.values.toList();
    _v41ApplyOutgoingStatus(owner, legs);
    persistMessage(owner.conversationId, owner);
    onStateChanged?.call();
  }

  /// The outgoing message whose leg is [wire] in [conversationId], or `null`
  /// (a reaction, an edit — nothing of its own in the conversation).
  UiMessage? _fileOrderOwner(String conversationId, String wire) {
    final conv = conversations[conversationId];
    if (conv == null) return null;
    ensureLoaded(conversationId);
    for (final m in conv.messages.reversed) {
      if (!m.isOutgoing) continue;
      if (m.id == wire || m.fanoutLegs.containsValue(wire)) return m;
    }
    return null;
  }

  // ── Recipient ─────────────────────────────────────────────────────────

  /// After a fresh frame was handled: a file that arrived takes the messages
  /// that waited for it behind it; a message that carries a file identifier
  /// is placed after that file and, if the file is still incomplete, makes
  /// this device collect it at once.
  void _fileOrderReceived(HarvestEvent event) {
    if (event.messageId.isEmpty) return;
    final conv = event.groupId != null
        ? bytesToHex(event.groupId!)
        : bytesToHex(event.senderUserId);
    final id = bytesToHex(event.messageId);
    if (event.type == proto.MessageTypeV3.MTV3_MEDIA_ANNOUNCE ||
        event.type == proto.MessageTypeV3.MTV3_MEDIA_INLINE ||
        event.type == proto.MessageTypeV3.MTV3_VOICE_MESSAGE) {
      final f = _bulkMessage(conv, id);
      if (f != null && !f.isOutgoing) _fileOrderPlace(conv, f);
    }
    final after = event.afterFile;
    if (after == null) return;
    final fid = bytesToHex(after);
    final m = _bulkMessage(conv, id);
    if (m != null && m.afterFile != fid) {
      m.afterFile = fid;
      persistMessage(conv, m);
    }
    UiMessage? file;
    // The file is searched in the whole history (§21.4.1). `_bulkMessage`
    // above has loaded it already; said here so that the search does not
    // depend on the line above staying where it is (the second call is free).
    ensureLoaded(conv);
    for (final x in conversations[conv]?.messages ?? const <UiMessage>[]) {
      if (!x.isOutgoing && x.id.startsWith(fid)) {
        file = x;
        break;
      }
    }
    if (file == null) {
      _log.info('[E2E file-order-recv] msgId=${id.substring(0, 8)} after file '
          '${fid.substring(0, 8)}, which is not here yet — placed when it comes');
      return;
    }
    _fileOrderPlace(conv, file);
    final state = file.mediaState;
    if (state == MediaDownloadState.completed ||
        state == MediaDownloadState.failed) {
      return;
    }
    // Incomplete: collect at once (§9.4) — the collection of W1, with its
    // rounds; "incomplete" ends it `failed` and tells the sender.
    String? tag;
    Map<String, dynamic>? entry;
    for (final e in _bulkIncoming.entries) {
      if (e.value['msg'] == file.id) {
        tag = e.key;
        entry = e.value;
        break;
      }
    }
    if (tag == null || entry == null) return;
    // Once per file and run: a burst of messages after one file asks once,
    // not once each; the rounds of W1 carry on from there.
    if (!_fileOrderAsked.add(tag)) return;
    while (_fileOrderAsked.length > _kFileOrderAskedAtMost) {
      _fileOrderAsked.remove(_fileOrderAsked.first);
    }
    final running =
        myceliumMailbox?.bulkCollector.status(hexToBytes(tag)) != null;
    // The user's download choice stands (§24.4.5): a file the policy does
    // not fetch by itself and the user did not ask for is not collected —
    // it stays announced, which is not incomplete.
    final allowed = running ||
        entry['started'] == true ||
        ((conversations[conv]?.config.allowDownloads ?? true) &&
            _mediaSettings.shouldAutoDownload(
                entry['mime'] as String?, file.fileSize ?? 0));
    if (!allowed) {
      _log.info('[E2E file-order-collect] msgId=${file.id.substring(0, 8)} '
          'not collected — the download is left to the user');
      return;
    }
    // A running collection asks its holders again NOW (a collection whose
    // holders sent no end mark would otherwise wait for the next edge of
    // §8.2); one not running starts.
    _log.info('[E2E file-order-collect] msgId=${file.id.substring(0, 8)} '
        'incomplete, a message after it came — '
        '${running ? 'asking the holders again now' : 'collecting now'}');
    _bulkCollectStart(tag);
  }

  /// Places every message of [conversationId] that waited behind [file]
  /// after it — by the least that takes (1 ms), keeping their order.
  void _fileOrderPlace(String conversationId, UiMessage file) {
    final conv = conversations[conversationId];
    if (conv == null || file.id.length < kAfterFileLength * 2) return;
    // The followers are searched in the whole history and re-inserted by
    // timestamp (§21.4.1). Every caller has loaded it today; the method does
    // not depend on that (the second call is free).
    ensureLoaded(conversationId);
    final fid = file.id.substring(0, kAfterFileLength * 2);
    final followers = [
      for (final m in conv.messages)
        if (m.afterFile == fid && !identical(m, file)) m
    ];
    var t = file.timestamp;
    final moved = <UiMessage>[];
    for (final m in followers) {
      if (!m.timestamp.isAfter(t)) {
        m.timestamp = t.add(const Duration(milliseconds: 1));
        moved.add(m);
      }
      t = m.timestamp;
    }
    if (moved.isEmpty) return;
    for (final m in moved) {
      conv.messages.remove(m);
      var at = conv.messages.length;
      while (at > 0 && conv.messages[at - 1].timestamp.isAfter(m.timestamp)) {
        at--;
      }
      conv.messages.insert(at, m);
      persistMessage(conversationId, m);
    }
    _log.info('[E2E file-order-place] ${moved.length} message(s) placed after '
        'file ${fid.substring(0, 8)}');
    _saveConversations();
    onStateChanged?.call();
    for (final m in moved) {
      if (m.fileSize != null) _fileOrderPlace(conversationId, m);
    }
  }
}
