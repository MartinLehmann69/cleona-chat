// S398 P3b — lane 2 of §9.4 at the app: a 1:1 file from 256 KB up to `C`
// (25 MB, D-14) streamed through a volunteer (§17.6), lane 3 behind it.
//
// SENDER (§17.6 "Cascade and windows"). After the consent (§24.4.5):
//   (a) draw `K_T`, send the announcement with the flag "stream possible"
//       and no holder (`bulk_announce.dart`) — phase `negotiating`;
//   (b) wait for the recipient's request (`MT_MEDIA_STREAM_REQUEST`) for
//       [CleonaService.streamRequestWait];
//   (c) request there: ask `laneChoose` again with what was found — the
//       recipient is online, a candidate exists — and stream
//       (`MailboxStream.streamSend`); its `offer` goes to the recipient as an
//       ordinary message (`MT_MEDIA_STREAM_OFFER`) — phase `streaming n %`;
//   (d) no request, no candidate, or the stream reports `fallback`: place the
//       object under the SAME `K_T` with holders (`bulkPlaceFor`, D-30) and
//       send their list (`MT_MEDIA_HOLDERS`, the lane 3 announcement) —
//       phase `seeding n %` → `available`.
// Groups and objects above `C` never get here (`sendMediaMessage`: lane 3 at
// once, §17.6 last paragraph).
// Sent while no mailbox is attached (the first moments after the start),
// nothing of this happens yet: the file is `resting` (§9.1), its record
// carries the mark `unsent`, and (a) starts at the attach (S403).
//
// RECIPIENT. The announcement becomes the bubble of lane 3
// (`_bulkAnnounceReceived`); where auto-download applies (or on the click)
// `_bulkCollectStart` finds no holder and calls [_streamAsk]: one request to
// the sender, phase `negotiating`. The offer joins the stream
// (`MailboxStream.streamJoin`) — phase `collecting n %`; the object goes
// through `bulkObjectArrived`, which stores it and only THEN sends the held
// receipt of the announcement (Q1, D-29). A fallback waits for the holder
// list; the pieces already opened the delivery layer kept on this identity's
// disk BEFORE the give-up named the rest (no reneging, S407-N4,
// `stream_receive.dart`), and the collection takes them from there.
//
// WHAT THE SENDER CANNOT TELL (named, not guessed): whether the announcement
// reached the recipient directly (60 s) or through the post box (20 min).
// The ladder does not know it either: since S399 it keeps no "carrying" step
// (only the acknowledgement ends a sending, `ladder.dart`); the wait is the
// 60 s (see `S398-P3B-BERICHT.md`).
//
// No clock of its own besides the one wait of (b); nothing runs between
// transfers (§5.4).

part of 'cleona_service.dart';

/// At most this many lane 2 transfers wait for their request at once; one
/// more ends the wait of the oldest, which takes lane 3 (§20.2).
const int _kStreamOutAtMost = 16;

/// Holder lists that came before their announcement; the oldest goes.
const int _kStreamHoldersEarlyAtMost = 64;

/// A lane 2 transfer at the sender between the announcement and the request.
class _StreamOut {
  final String recipientHex;

  /// `true`: the recipient asked. `false`: displaced — take lane 3.
  final Completer<bool> request = Completer<bool>();
  _StreamOut(this.recipientHex);
}

extension CleonaServiceStream on CleonaService {
  // ── Sending ───────────────────────────────────────────────────────────

  /// The whole of lane 2 for [msg] (steps (a)–(d) in the file head). Runs
  /// detached from `sendMediaMessage`.
  Future<void> _streamSend({
    required UiMessage msg,
    required Uint8List object,
    required ContactInfo recipient,
    required proto.ContentMetadata metadata,
    required Uint8List? preview,
    required Uint8List messageIdBytes,
    Map<String, dynamic>? record,
  }) async {
    _transfersRunning.add(msg.id);
    try {
      await _streamRun(
          msg: msg,
          object: object,
          recipient: recipient,
          metadata: metadata,
          preview: preview,
          messageIdBytes: messageIdBytes,
          record: record);
    } finally {
      _transfersRunning.remove(msg.id);
    }
  }

  /// Starts lane 2 for [msg] from its sender [record] — a file whose turn
  /// came in its line (`_fileOrderStart`), or one that was sent while no
  /// mailbox was attached (`_transferResume`, mark `unsent`).
  void _streamFromRecord(
      UiMessage msg, Uint8List object, Map<String, dynamic> record) {
    final contact = _contacts[msg.conversationId];
    if (contact == null) {
      _transferRecordDrop(record);
      return _mediaFail(msg, FailureReason.noRoute, 'recipient is no contact');
    }
    final preview = record['preview'] as String?;
    unawaited(_streamSend(
      msg: msg,
      object: object,
      recipient: contact,
      metadata: proto.ContentMetadata.fromBuffer(
          base64Decode(record['meta'] as String)),
      preview: preview == null ? null : hexToBytes(preview),
      messageIdBytes: hexToBytes(msg.id),
      record: record,
    ));
  }

  Future<void> _streamRun({
    required UiMessage msg,
    required Uint8List object,
    required ContactInfo recipient,
    required proto.ContentMetadata metadata,
    required Uint8List? preview,
    required Uint8List messageIdBytes,
    // The record of a file that waited — behind a file (S398-W5) or for the
    // mailbox (S403): its `K_T` is used, no new record is drawn.
    Map<String, dynamic>? record,
  }) async {
    final conversationId = msg.conversationId;
    final short = msg.id.substring(0, 8);
    void settle() {
      persistMessage(conversationId, msg);
      _saveConversations();
      onStateChanged?.call();
    }

    if (recipient.x25519Pk == null || recipient.mlKemPk == null) {
      return _mediaFail(msg, FailureReason.noRoute, 'recipient without keys');
    }
    final p = myceliumMailbox;
    if (p == null) {
      // NO MAILBOX ATTACHED YET (S403, owner decision 12 of 02.10.2026): the
      // file is created, not yet sent — `resting` (§9.1) —, not `failed`.
      // Whether a lane is viable (§9.4 "first by size, then by viability")
      // cannot be told before the attach, and a file closed here could never
      // be sent again (D-34). Its record waits with the mark `unsent`; the
      // attach starts it from there (`_transferResume`), and lane 2 is then
      // tried as always. No clock: the wait ends at the attach.
      final r = record ??
          _transferRecordNew(msg, object,
              lane: 'stream',
              transferKey: transferKeyDraw(),
              metadata: metadata,
              preview: preview);
      r['unsent'] = true;
      _transferRecordPut(r);
      _log.info('[E2E media-send-path] lane streamed msgId=$short waits — no '
          'mailbox attached yet, nothing sent (§9.1 resting)');
      return;
    }
    final recipientHex = bytesToHex(recipient.nodeId);
    Future<bool> send(proto.MessageType type, Uint8List payload,
            {Uint8List? messageId, proto.ContentMetadata? meta}) =>
        sendToUser(
          recipientUserId: recipient.nodeId,
          messageType: type,
          payload: payload,
          messageId: messageId,
          contentMetadata: meta,
        );

    // (a) K_T and the announcement "stream possible".
    final kT = record == null
        ? transferKeyDraw()
        : hexToBytes(record['kt'] as String);
    final tagBytes = bulkTag(kT);
    final tag = tagHex(tagBytes);
    final Uint8List announce;
    try {
      announce = bulkAnnouncePack(
          transferKey: kT,
          length: object.length,
          sha256: SodiumFFI().sha256(object),
          holders: const [],
          preview: preview,
          stream: true);
    } on ArgumentError catch (e) {
      return _mediaFail(msg, FailureReason.tooLarge, '$e');
    }
    // S398-W1: the record first — a restart from here on continues on
    // lane 3 under this K_T (`_transferResume`).
    final r = record ??
        _transferRecordNew(msg, object,
            lane: 'stream', transferKey: kT, metadata: metadata, preview: preview);
    if (r.remove('unsent') != null) {
      // S403: it leaves now. From here on a restart continues on lane 3 like
      // every started transfer, and `TTL_media` counts from this moment —
      // nothing of it lay anywhere before.
      r['at'] = DateTime.now().millisecondsSinceEpoch;
      _transferRecordPut(r);
    }
    final wait = _StreamOut(recipientHex);
    _streamOut[tag] = wait;
    while (_streamOut.length > _kStreamOutAtMost) {
      final old = _streamOut.remove(_streamOut.keys.first);
      if (old != null && !old.request.isCompleted) old.request.complete(false);
    }
    _transferProgress(conversationId, msg.id, TransferPhase.negotiating, 0);
    final legs = <String>[msg.id];
    // Index BEFORE sending, for the reason given in `sendTextMessage`.
    _applyOutgoingLegStatus(msg, legs);
    final announced = await send(proto.MessageType.MT_MEDIA_ANNOUNCE,
        announce,
        messageId: messageIdBytes, meta: metadata);
    _applyOutgoingLegStatus(msg, legs);
    if (!announced) {
      // B-8: nothing handed over — no stream, no lane 3 for an object the
      // recipient never hears of.
      if (identical(_streamOut[tag], wait)) _streamOut.remove(tag);
      _transferRecordDrop(r);
      return _mediaFail(msg, FailureReason.noRoute,
          'the announcement was not handed to the delivery layer');
    }
    statsCollector.addMessageSent();
    r['announced'] = true;
    _transferRecordPut(r);
    _mediaSentPut(tag, {
      'conv': conversationId,
      'msg': msg.id,
      'to': [recipientHex],
      'at': DateTime.now().millisecondsSinceEpoch,
      'net': false,
    });
    settle();

    // (b) The recipient's request — the evidence that it is online (§17.6).
    //     The window follows the rung that carried the announcement (§17.6
    //     "Cascade and windows"): 60 s when it reached the recipient
    //     directly, 20 min when it went via the post box — the recipient
    //     reads it at its next collection. The delivery layer says which:
    //     a placed announcement (its history entry carries `placedAt`). Until
    //     S408-LEBENSLAUF P21 the sender always waited 60 s and sent a placed
    //     announcement's object to lane 3 before the recipient could ask.
    bool requested;
    try {
      requested = await wait.request.future.timeout(streamRequestWait);
    } on TimeoutException {
      requested = false;
    }
    if (!requested && _announcePlaced(bytesToHex(messageIdBytes))) {
      _log.info('[E2E media-stream-send] msgId=$short announcement placed — '
          'the request window is ${streamRequestWaitPlaced.inMinutes} min');
      try {
        requested = await wait.request.future
            .timeout(streamRequestWaitPlaced - streamRequestWait);
      } on TimeoutException {
        requested = false;
      }
    }
    if (identical(_streamOut[tag], wait)) _streamOut.remove(tag);
    if (_disposed) return;

    // (c) Lane 2 — the choice asked again with what the cascade found.
    final candidates = requested
        ? (streamCandidatesForTesting?.call() ?? p.streamCandidates())
        : const <CardAddress>[];
    final lane = mycelium.laneChoose(
        length: object.length,
        bothOnline: requested,
        volunteerThere: candidates.isNotEmpty);
    String why;
    List<int>? lastMissing; // what the recipient named, S407 M-2
    if (lane == mycelium.Lane.streamed) {
      _log.info('[E2E media-stream-send] msgId=$short request came, '
          '${candidates.length} candidate(s)');
      final s = await _streamOneAtATime(() => p.streamSend(object, kT,
          candidates: candidates,
          offer: (o) async {
            final payload = Uint8List(kTagLength + o.length)
              ..setRange(0, kTagLength, tagBytes)
              ..setRange(kTagLength, kTagLength + o.length, o);
            if (!await send(proto.MessageType.MT_MEDIA_STREAM_OFFER, payload)) {
              _log.warn('[E2E media-stream-send] msgId=$short offer not handed '
                  'to the delivery layer');
            }
          },
          progress: (sent, total) => _transferProgress(conversationId, msg.id,
              TransferPhase.streaming,
              total == 0 ? 0 : (sent * 100 ~/ total).clamp(0, 99))));
      if (s.recipientGaveUp) lastMissing = s.missingStripes;
      if (_disposed) return;
      if (s.done) {
        _transferProgress(conversationId, msg.id, TransferPhase.available, 100);
        _transferProgressEnd(msg.id);
        _transferRecordDrop(r);
        _mediaInNetwork(msg, tag); // streamed to the end (D-34)
        // S398-W5: what waited behind it goes now.
        _fileOrderRelease(msg, fileFailed: false);
        _log.info('[E2E media-send-done] msgId=$short filename=${msg.filename} '
            'size=${msg.fileSize} recipient=${conversationId.substring(0, 8)} '
            'lane=streamed frames=${s.frames} sessions=${s.sessions} '
            'rate=${s.rate}/s took=${s.took.inMilliseconds} ms');
        return;
      }
      why = 'the stream fell back — ${s.reason}';
    } else {
      why = requested
          ? 'no volunteer candidate'
          : 'no request within its window (§17.6)';
    }

    // (d) Lane 3 for the remainder, under the SAME K_T (§17.6 "falls to the
    // bulk lane for the remainder"): the tag of the announcement stays.
    // S407 M-2: when the recipient gave up, it named what it cannot decode
    // and kept the rest it opened on its disk (S407-N4: what it cannot keep
    // it names too): only those stripes go. Otherwise (volunteer lost, nothing named) the
    // recipient may still be collecting from the stream — the whole object.
    final missing = lastMissing;
    final total = mycelium.stripeNumber(object.length);
    if (missing != null && missing.isNotEmpty && missing.length < total) {
      r['only'] = missing;
      _transferRecordPut(r);
    }
    _log.info('[E2E media-send-path] lane mass msgId=$short after lane 2 — $why'
        '${r['only'] == null ? '' : ' — ${missing!.length} of $total stripes'}');
    await _laneThree(msg, object, r);
  }

  /// ONE stream at a time per node: `StreamSender` keeps a single run.
  Future<T> _streamOneAtATime<T>(Future<T> Function() f) {
    final run = _streamTurn.then((_) => f());
    _streamTurn = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  /// `MT_MEDIA_STREAM_REQUEST` at the sender: the recipient is there and
  /// wants the stream of the tag in the payload.
  /// Whether the announcement [messageIdHex] went via the post box: its
  /// history entry in the delivery layer is placed (two holders took it,
  /// §8.2) — the rung-4 case of §17.6's request window.
  bool _announcePlaced(String messageIdHex) {
    final p = myceliumMailbox;
    final a = _myceliumOutbounds[messageIdHex];
    if (p == null || a == null) return false;
    final id = bytesToHex(a.identifier);
    return p.historyFor(a.to).entries.any(
        (e) => e.placedAt != null && bytesToHex(e.identifier) == id);
  }

  void _streamRequestReceived(HarvestEvent event) {
    final from = event.senderUserId.hex;
    if (event.payload.length != kTagLength) {
      _log.warn('[E2E media-stream-request] from=${from.substring(0, 8)} '
          'dropped: ${event.payload.length} B, not a tag');
      return;
    }
    final tag = bytesToHex(Uint8List.fromList(event.payload));
    final w = _streamOut[tag];
    if (w == null || w.recipientHex != from) {
      // The window has passed (lane 3 runs), or not ours.
      _log.info('[E2E media-stream-request] from=${from.substring(0, 8)} '
          'tag ${tag.substring(0, 8)}: no transfer waits for it');
      return;
    }
    _log.info('[E2E media-stream-request] from=${from.substring(0, 8)} '
        'tag ${tag.substring(0, 8)}');
    if (!w.request.isCompleted) w.request.complete(true);
  }

  // ── Receiving ─────────────────────────────────────────────────────────

  /// The recipient's half of step (b): asks the sender for the stream of
  /// entry [e] (lane 2 announcement, no holder yet) — at most once per
  /// entry, and only when [ask]. Marks the entry started either way, so
  /// that the holder list, when it comes, starts the collection.
  bool _streamAsk(String tag, Map<String, dynamic> e, {required bool ask}) {
    final conversationId = e['conv'] as String;
    final msgId = e['msg'] as String;
    final msg = _bulkMessage(conversationId, msgId);
    if (msg != null && msg.mediaState != MediaDownloadState.downloading) {
      msg.mediaState = MediaDownloadState.downloading;
      persistMessage(conversationId, msg);
      onStateChanged?.call();
    }
    final first = e['requested'] != true;
    e['started'] = true;
    if (ask && first) e['requested'] = true;
    _bulkIncomingPut(tag, e);
    if (!ask || !first) return true;
    _transferProgress(conversationId, msgId, TransferPhase.negotiating, 0);
    final contact = _contacts[e['from'] as String];
    if (contact == null) {
      _log.warn('[E2E media-stream-ask] msgId=${msgId.substring(0, 8)}: sender '
          'is no contact — waiting for the holder list');
      return true;
    }
    unawaited(sendToUser(
      recipientUserId: contact.nodeId,
      messageType: proto.MessageType.MT_MEDIA_STREAM_REQUEST,
      payload: hexToBytes(tag),
    ).then((ok) => _log.info('[E2E media-stream-ask] '
        'msgId=${msgId.substring(0, 8)} request sent=$ok')));
    return true;
  }

  /// `MT_MEDIA_STREAM_OFFER` at the recipient: tag ‖ STREAM_OFFER. Joins
  /// the volunteer it names for the object of the announcement.
  void _streamOfferReceived(HarvestEvent event) {
    final from = event.senderUserId.hex;
    final payload = Uint8List.fromList(event.payload);
    final p = myceliumMailbox;
    if (payload.length <= kTagLength || p == null) return;
    final tag = bytesToHex(Uint8List.sublistView(payload, 0, kTagLength));
    final e = _bulkIncoming[tag];
    if (e == null || e['from'] != from) {
      _log.info('[E2E media-stream-offer] from=${from.substring(0, 8)} '
          'tag ${tag.substring(0, 8)}: no announcement of this sender');
      return;
    }
    final a = bulkAnnounceUnpack(hexToBytes(e['announce'] as String));
    if (a == null) return;
    final conversationId = e['conv'] as String;
    final msgId = e['msg'] as String;
    Uint8List? joined;
    try {
      joined = p.streamJoin(Uint8List.sublistView(payload, kTagLength),
          transferKey: a.transferKey,
          length: a.length,
          sha256: a.sha256,
          onObject: (t, o) => bulkObjectArrived(t, o),
          onFallback: _streamFellBack,
          progress: (t, complete, stripes) => _transferProgress(conversationId,
              msgId, TransferPhase.collecting, complete * 100 ~/ stripes));
    } on ArgumentError catch (x) {
      _log.warn('[E2E media-stream-offer] msgId=${msgId.substring(0, 8)}: $x');
    }
    if (joined == null) {
      _log.warn('[E2E media-stream-offer] msgId=${msgId.substring(0, 8)}: '
          'offer unreadable or no family in common — waiting for the holders');
      return;
    }
    _transferProgress(conversationId, msgId, TransferPhase.collecting, 0);
    _log.info('[E2E media-stream-join] msgId=${msgId.substring(0, 8)} '
        'length=${a.length}');
  }

  /// The stream of [f] cannot finish (§17.6): collect from the holders once
  /// their list is there. What it opened lies on this identity's disk
  /// already — the delivery layer kept it before the give-up named the rest
  /// (S407-N4); the collection takes it from there.
  void _streamFellBack(StreamFallback f) {
    final key = tagHex(f.tag);
    final e = _bulkIncoming[key];
    if (e == null || _disposed) return;
    // What it named is what the sender places (S407 M-2); the rest are the
    // stripes whose pieces it keeps — the ones it may ask for once more,
    // should they be lost (D-34 exception, `cleona_service_image_again.dart`).
    e[kStreamGaveUpKey] = [...f.missingStripes]..sort();
    _bulkIncomingPut(key, e);
    final msgId = e['msg'] as String;
    final a = bulkAnnounceUnpack(hexToBytes(e['announce'] as String));
    final running = myceliumMailbox?.bulkCollector.status(f.tag) != null;
    _log.info('[E2E media-stream-fallback] msgId=${msgId.substring(0, 8)} — '
        '${f.reason}; ${f.missingStripes.length} stripe(s) missing, '
        'holders ${a?.holders.length ?? 0}, collecting $running');
    if (a != null && a.holders.isNotEmpty && !running && e['started'] == true) {
      _bulkCollectStart(key);
    }
  }

  /// `MT_MEDIA_HOLDERS` at the recipient: the lane 3 announcement of a
  /// stream that fell back — same `K_T`, so the same tag and entry.
  void _streamHoldersReceived(HarvestEvent event) {
    final from = event.senderUserId.hex;
    final payload = Uint8List.fromList(event.payload);
    final a = bulkAnnounceUnpack(payload);
    if (a == null || a.stream || a.holders.isEmpty) {
      _log.warn('[E2E media-stream-holders] from=${from.substring(0, 8)} '
          'dropped: not a holder list (${payload.length} B)');
      return;
    }
    final key = tagHex(bulkTag(a.transferKey));
    final e = _bulkIncoming[key];
    if (e == null) {
      // The announcement is still to come (both in one post box run), or
      // the object is stored already; kept briefly either way.
      _streamHoldersEarly[key] = payload;
      while (_streamHoldersEarly.length > _kStreamHoldersEarlyAtMost) {
        _streamHoldersEarly.remove(_streamHoldersEarly.keys.first);
      }
      return;
    }
    final was = bulkAnnounceUnpack(hexToBytes(e['announce'] as String));
    if (e['from'] != from ||
        was == null ||
        was.length != a.length ||
        tagHex(was.sha256) != tagHex(a.sha256)) {
      _log.warn('[E2E media-stream-holders] from=${from.substring(0, 8)} '
          'dropped: another sender or another object');
      return;
    }
    // After the D-34 request the new list names only the holders of the
    // lost stripes; the earlier ones still hold the rest.
    e['announce'] = bytesToHex(
        e[kImageAgainKey] == true ? _imageHoldersMerged(was, a) : payload);
    _bulkIncomingPut(key, e);
    _log.info('[E2E media-stream-holders] msgId=${(e['msg'] as String).substring(0, 8)} '
        'holders=${a.holders.length} started=${e['started'] == true}');
    if (e['started'] == true) _bulkCollectStart(key);
  }
}
