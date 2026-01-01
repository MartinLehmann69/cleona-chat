// S398 P2b — lane 3 of §9.4 at the app: a file of 256 KB or more.
//
// SENDING. After the consent (§9.4 "Consent", §24.4.5) the object is
// striped, sealed under a fresh `K_T` and placed ONCE with always-on holders
// (mycelium `bulk_place.dart`, D-30). Only then goes the announcement —
// `K_T`, length, SHA-256, the holders, a micro preview
// (`bulk_announce.dart`) — to every recipient as an ordinary sealed message
// (`MTV3_MEDIA_ANNOUNCE`, §4.3), one leg per member in a group (§16.2). The
// message is `resting` while the pieces are placed and takes its state from
// the announcement like text (§9.1). Nothing accepted: `failed` (§22.5.1
// "no volunteer and no holder accepted anything").
//
// RECEIVING. The announcement becomes a bubble `announced` with the preview;
// the recipient collects from exactly the named holders (§9.4 "Lane 3,
// collection"), mycelium checks the SHA-256, the object goes encrypted into
// the media store. The entry of the store area [kBulkIncomingArea] of this
// identity is the ONE record of an announced object and of its collection
// (S401): `K_T`, length, SHA-256 and holders (the announcement), the
// message it belongs to, and whether collecting has begun. The delivery
// layer keeps no second list: after a restart [_bulkResume] hands every
// begun collection over again, with its callbacks, to the collector of this
// identity's mailbox; the stripes already complete lie in this identity's
// folder under its key (`mycelium/lib/bulk_disk.dart`).
//
// Q1 (§9.4, D-29). The acknowledgement of the announcement is what sets
// `delivered` at the sender, and it goes only once the object decoded: the
// mycelium receipt (0x11) is held back ([_bulkReceiptLater], asked by
// `message.dart` for every copy) and sent with the app's DELIVERY_RECEIPT
// from [bulkObjectArrived]. The identifier it needs stands in the store entry,
// so a held receipt survives a restart; a copy arriving after the object
// was stored is receipted at once — the second chance for a lost receipt.
//
// PROGRESS (§22.5.1 `TransferPhase`): `seeding` / `available` at the
// sender, `collecting` at the recipient — beside the delivery state, never
// folded into it. At most one event per whole percent.
//
// INTERRUPTIONS AND FAILURE (S398-W1, D-34): the sender's record, the resume
// after a restart, "in the network", the reasons and the abort both ways
// live in `cleona_service_transfer.dart`. A collection that fails for good
// (every holder "nothing here", `TTL_media`, rounds without a new stripe) is
// `failed` with its reason here and at the sender.
//
// Lane 2 (a volunteer, §17.6, S398 P3b) lives in `cleona_service_stream.dart`
// and shares the recipient's half with this file: its announcement is the
// same `MTV3_MEDIA_ANNOUNCE` with the flag "stream possible" and no holder
// yet; a stream that falls back sends the holders afterwards under the SAME
// `K_T` (`MTV3_MEDIA_HOLDERS`), so the tag, the entry and the held receipt
// stay those of the announcement.

part of 'cleona_service.dart';

/// Store area: announced lane 3 objects of THIS identity, keyed by the hex
/// transfer tag. An entry lives from the announcement until the object is
/// stored, or until the collection failed for good (S398-W1, D-34: the file
/// is then `failed` with its reason); older than `TTL_media` no holder has
/// the pieces (§9.4).
const String kBulkIncomingArea = 'bulk_incoming';

/// At most this many announced objects are remembered; the oldest gives
/// way (§20.2). Far above the 32 open collections of mycelium, because an
/// announcement without auto-download waits for the user's click.
const int _kBulkIncomingAtMost = 1024;

/// At most this many progress entries (one per running transfer).
const int _kTransferProgressAtMost = 256;

extension CleonaServiceBulk on CleonaService {
  // ── Progress ──────────────────────────────────────────────────────────

  /// Records and reports the progress of [messageId]. Only a change of the
  /// whole percent or of the phase goes out.
  void _transferProgress(
      String conversationId, String messageId, TransferPhase phase, int percent) {
    final p = percent.clamp(0, 100);
    final last = _transferProgressMap[messageId];
    if (last != null && last.phase == phase && last.percent == p) return;
    _transferProgressMap[messageId] = (phase: phase, percent: p);
    while (_transferProgressMap.length > _kTransferProgressAtMost) {
      _transferProgressMap.remove(_transferProgressMap.keys.first);
    }
    onMediaTransferProgress?.call(conversationId, messageId, phase, p);
  }

  void _transferProgressEnd(String messageId) =>
      _transferProgressMap.remove(messageId);

  // ── Sending ───────────────────────────────────────────────────────────

  /// Lane 3 for [msg]: place [object], then announce. Runs detached from
  /// `sendMediaMessage` — placing 1 MB takes about 50 s at `R_bulk`
  /// (§9.4), and neither the GUI nor the IPC call may wait for it.
  ///
  /// S398-W1: a record under a fresh `K_T` is stored first; the placement
  /// and the announcement are `_laneThree` (`cleona_service_transfer.dart`),
  /// which a restart resumes from the same record.
  Future<void> _bulkSend({
    required UiMessage msg,
    required Uint8List object,
    required proto.ContentMetadata metadata,
    required Uint8List? preview,
  }) async {
    final r = _transferRecordNew(msg, object,
        lane: 'mass',
        transferKey: transferKeyDraw(),
        metadata: metadata,
        preview: preview);
    _transfersRunning.add(msg.id);
    try {
      await _laneThree(msg, object, r);
    } finally {
      _transfersRunning.remove(msg.id);
    }
  }

  // ── Receiving ─────────────────────────────────────────────────────────

  /// `MTV3_MEDIA_ANNOUNCE`: the announcement of lane 3. The two-stage path
  /// of V3 and the V4.1 offer (`BulkAnnounce`, marker 0xB1) are gone — 4.2
  /// has no compatibility branch (D-21): a payload that is not a lane 3
  /// announcement makes no bubble.
  void _bulkAnnounceReceived(HarvestEvent event) {
    final senderHex = event.senderUserId.hex;
    final msgId = event.messageId.hex;
    final a = bulkAnnounceUnpack(Uint8List.fromList(event.payload));
    if (a == null) {
      _log.warn('[E2E media-announce-mass-recv] from=${senderHex.substring(0, 8)} '
          'msgId=${msgId.substring(0, 8)} dropped: not a lane 3 announcement '
          '(${event.payload.length} B)');
      return;
    }
    final mismatch = _checkGroupPostMembership(event, senderHex);
    if (mismatch == null) return;
    final conversationId =
        event.groupId != null ? event.groupId!.hex : senderHex;
    final tag = tagHex(bulkTag(a.transferKey));
    final known = _bulkIncoming[tag];
    if (known != null) {
      // A second copy (§7.1) — or the full announcement of a sender that
      // restarted before its "stream possible" went out for sure
      // (`_transferResume`): it names the holders the first one did not.
      final was = bulkAnnounceUnpack(hexToBytes(known['announce'] as String));
      if (was != null && was.holders.isEmpty && a.holders.isNotEmpty &&
          known['from'] == senderHex && was.length == a.length &&
          tagHex(was.sha256) == tagHex(a.sha256)) {
        known['announce'] = bytesToHex(Uint8List.fromList(event.payload));
        _bulkIncomingPut(tag, known);
        if (known['started'] == true) _bulkCollectStart(tag);
      }
      return;
    }
    final metadata = event.contentMetadata ?? proto.ContentMetadata();
    final size =
        metadata.fileSize.toInt() > 0 ? metadata.fileSize.toInt() : a.length;
    final msg = UiMessage(
      id: msgId,
      conversationId: conversationId,
      senderNodeIdHex: senderHex,
      text: metadata.filename,
      // §22.5.3: display and sorting rely on the local arrival time only.
      timestamp: event.harvestedAt,
      type: _msgTypeFromMime(metadata.mimeType),
      status: MessageStatus.delivered,
      isOutgoing: false,
      mimeType: metadata.mimeType,
      fileSize: size,
      filename: metadata.filename,
      thumbnailBase64: a.preview.isNotEmpty ? base64Encode(a.preview) : null,
      mediaState: MediaDownloadState.announced,
      membershipMismatch: mismatch,
      postId: event.postIdHex,
      transcriptText:
          metadata.transcriptText.isNotEmpty ? metadata.transcriptText : null,
      transcriptLanguage:
          metadata.transcriptText.isNotEmpty ? metadata.transcriptLanguage : null,
      transcriptConfidence: metadata.transcriptText.isNotEmpty
          ? metadata.transcriptConfidence.toDouble()
          : null,
    );
    final isGroup = _groups.containsKey(conversationId);
    final isNew = _addMessageToConversation(conversationId, msg, isGroup: isGroup);
    // Lane 2: the holder list of a fallen-back stream may have overtaken
    // its announcement (both from the post box in one run).
    final early = a.stream ? _streamHoldersEarly.remove(tag) : null;
    _bulkIncomingPut(tag, {
      'conv': conversationId,
      'msg': msgId,
      'from': senderHex,
      if (event.groupId != null) 'group': event.groupId!.hex,
      'announce': bytesToHex(early ?? Uint8List.fromList(event.payload)),
      'mime': metadata.mimeType,
      'at': DateTime.now().millisecondsSinceEpoch,
      'receipt': ?_bulkReceiptsHeld.remove(msgId),
    });
    // Without the file name: it is the text of the notification posted
    // below, and that "is not written to a log" (§22.8).
    _log.info('[E2E media-announce-mass-recv] from=${senderHex.substring(0, 8)} '
        'msgId=${msgId.substring(0, 8)} '
        'size=${a.length} holders=${a.holders.length} stream=${a.stream} '
        'preview=${a.preview.length} B');
    if (isNew &&
        !_shouldSuppressNotification(
            conversationId, _claimedSendTimeMs(event))) {
      notificationSound.playMessageSound(
          soundName: conversations[conversationId]?.notificationSoundName);
      final senderName =
          _contacts[senderHex]?.displayName ?? senderHex.substring(0, 8);
      _postAndroidNotification(senderName, '📎 ${metadata.filename}', conversationId);
      _lastNotifiedAt[conversationId] = DateTime.now();
    }
    // Auto-download as for every file (§3.4.3 policy, per chat and global).
    final allowed = conversations[conversationId]?.config.allowDownloads ?? true;
    if (allowed && _mediaSettings.shouldAutoDownload(metadata.mimeType, size)) {
      _bulkCollectStart(tag);
    }
  }

  /// Starts (or restarts) collecting the object of [tag] from the holders
  /// its announcement names. `false` without an entry or a mailbox.
  ///
  /// A lane 2 announcement names no holder yet: then the recipient asks
  /// the sender for the stream (§17.6, `_streamAsk`) — unless [ask] is
  /// false (a restart: the sender's window has passed, the holder list
  /// comes by itself) — and the collection starts when the holders do.
  bool _bulkCollectStart(String tag, {bool ask = true}) {
    final e = _bulkIncoming[tag];
    final p = myceliumMailbox;
    if (e == null || p == null) return false;
    final a = bulkAnnounceUnpack(hexToBytes(e['announce'] as String));
    if (a == null) return false;
    final conversationId = e['conv'] as String;
    final msgId = e['msg'] as String;
    if (a.holders.isEmpty) return _streamAsk(tag, e, ask: ask);
    final msg = _bulkMessage(conversationId, msgId);
    if (msg != null && msg.mediaState != MediaDownloadState.downloading) {
      msg.mediaState = MediaDownloadState.downloading;
      persistMessage(conversationId, msg);
      onStateChanged?.call();
    }
    e['started'] = true;
    _bulkIncomingPut(tag, e);
    _transferProgress(conversationId, msgId, TransferPhase.collecting, 0);
    final seed = _streamSeeds.remove(tag);
    p.bulkCollect(
      transferKey: a.transferKey,
      length: a.length,
      sha256: a.sha256,
      holders: a.holders,
      onObject: (t, o) => bulkObjectArrived(t, o),
      onFailure: (t, why) => bulkCollectionFailed(t, why),
      progress: (t, complete, stripes) => _transferProgress(conversationId,
          msgId, TransferPhase.collecting, complete * 100 ~/ stripes),
      // Lane 2 fell back: what the stream already opened (§17.6).
      seed: seed,
      // `TTL_media` runs from the announcement, also across a restart — the
      // collector keeps no time of its own (S401).
      started: DateTime.fromMillisecondsSinceEpoch(
          (e['at'] as int?) ?? DateTime.now().millisecondsSinceEpoch),
    );
    _log.info('[E2E media-mass-collect] msgId=${msgId.substring(0, 8)} '
        'holders=${a.holders.length} length=${a.length} '
        'seed=${seed?.values.fold<int>(0, (n, m) => n + m.length) ?? 0} piece(s)');
    return true;
  }

  /// The object of [tag] is assembled and matches the SHA-256 of the
  /// announcement (mycelium checked it). `false` if this identity does not
  /// know [tag] (any more) — the entry went while the collection ran.
  bool bulkObjectArrived(Uint8List tag, Uint8List object) {
    final key = tagHex(tag);
    final e = _bulkIncoming[key];
    if (e == null || _disposed) return false;
    final conversationId = e['conv'] as String;
    final msgId = e['msg'] as String;
    final msg = _bulkMessage(conversationId, msgId);
    final mime = (e['mime'] as String?) ?? '';

    // Voice: the object is the VoicePayload wrapper, as on lane 1.
    var data = object;
    if (mime.startsWith('audio/')) {
      try {
        final voice = proto.VoicePayload.fromBuffer(object);
        if (voice.audioData.isNotEmpty) {
          data = Uint8List.fromList(voice.audioData);
          if (msg != null &&
              msg.transcriptText == null &&
              voice.transcriptText.isNotEmpty) {
            msg.transcriptText = voice.transcriptText;
            msg.transcriptLanguage = voice.transcriptLanguage;
            msg.transcriptConfidence = voice.transcriptConfidence.toDouble();
          }
        }
      } catch (_) {/* raw audio bytes */}
    }
    final mediaDir = Directory('$profileDir/media');
    if (!mediaDir.existsSync()) mediaDir.createSync(recursive: true);
    final filename = (msg?.filename?.isNotEmpty ?? false)
        ? msg!.filename!
        : 'file_$msgId';
    final savePath = CleonaService._uniqueMediaPath(mediaDir.path, filename);
    MediaStore.instance.writeBytes(savePath, data); // encrypted (S362)
    if (msg != null) {
      msg.filePath = savePath;
      msg.fileSize = data.length;
      msg.mediaState = MediaDownloadState.completed;
      if (mime.startsWith('image/') &&
          msg.thumbnailBase64 == null &&
          data.length <= 100 * 1024) {
        msg.thumbnailBase64 = base64Encode(data);
      }
      persistMessage(conversationId, msg);
      _saveConversations();
      if (mime.startsWith('audio/') &&
          (msg.transcriptText == null || msg.transcriptText!.isEmpty)) {
        _voiceTranscription?.enqueueTranscription(
            messageId: msgId, audioFilePath: savePath);
      }
    }
    _transferProgress(conversationId, msgId, TransferPhase.collecting, 100);
    _transferProgressEnd(msgId);
    _bulkReceiptsSend(e);
    _bulkIncomingRemove(key);
    _streamSeeds.remove(key);
    onStateChanged?.call();
    _log.info('[E2E media-mass-recv-done] msgId=${msgId.substring(0, 8)} '
        'bytes=${data.length} path=$savePath');
    return true;
  }

  /// Q1: holds back the mycelium receipt of a lane 3 announcement until
  /// its object decodes. Synchronous and before the app sees the inbound
  /// (`Messages.receiptLater`); `false` for everything else.
  bool _bulkReceiptLater(mycelium.Inbound e) {
    if (e.kind != null) return false;
    final proto.ApplicationFrameV3 f;
    try {
      f = proto.ApplicationFrameV3.fromBuffer(e.content);
    } catch (_) {
      return false;
    }
    if (f.messageType != proto.MessageTypeV3.MTV3_MEDIA_ANNOUNCE) return false;
    final msgId = bytesToHex(Uint8List.fromList(f.messageId));
    final conversationId = f.groupId.isNotEmpty
        ? bytesToHex(Uint8List.fromList(f.groupId))
        : bytesToHex(Uint8List.fromList(f.senderUserId));
    // Already decoded: this copy is the second chance for a lost receipt.
    if (_bulkMessage(conversationId, msgId)?.mediaState ==
        MediaDownloadState.completed) {
      return false;
    }
    final receipt = bytesToHex(e.identifier);
    for (final x in _bulkIncoming.entries) {
      if (x.value['msg'] != msgId) continue;
      x.value['receipt'] = receipt;
      _bulkIncomingPut(x.key, x.value);
      return true;
    }
    _bulkReceiptsHeld[msgId] = receipt; // taken over by the announcement
    while (_bulkReceiptsHeld.length > _kTransferProgressAtMost) {
      _bulkReceiptsHeld.remove(_bulkReceiptsHeld.keys.first);
    }
    return true;
  }

  /// Sends the receipts held back for entry [e]: the mycelium 0x11 (§9.2)
  /// and the app's DELIVERY_RECEIPT — both only now, after decoding.
  void _bulkReceiptsSend(Map<String, dynamic> e) {
    final from = e['from'] as String;
    final msgId = e['msg'] as String;
    final group = e['group'] as String?;
    final receipt = e['receipt'] as String?;
    final p = myceliumMailbox;
    final contact = _contacts[from];
    // A co-member who is no contact is a group pair (D-36): its 0x11 goes to
    // the pair's address, like every other packet of the pair.
    final pair = contact == null ? p?.groupPairOrNull(from)?.address : null;
    if (receipt != null && p != null && (contact != null || pair != null)) {
      try {
        final address = pair ??
            _myceliumKnownAddress(p, contact!) ??
            addressFrom(contact!);
        p.identity.messages.receiptSend(hexToBytes(receipt), address);
        _log.info('[E2E media-mass-receipt] msgId=${msgId.substring(0, 8)} '
            'receipt ${receipt.substring(0, 6)} sent after decoding (§9.4)');
      } on SeamError catch (x) {
        _log.warn('bulk: receipt for ${msgId.substring(0, 8)} not sent — $x');
      }
    } else {
      _log.warn('bulk: no held receipt for ${msgId.substring(0, 8)} '
          '(receipt ${receipt != null}, mailbox ${p != null}, contact '
          '${contact != null}, group pair ${pair != null})');
    }
    _sendDeliveryReceiptV3(
      recipientUserId: hexToBytes(from),
      messageId: hexToBytes(msgId),
      groupId: group == null ? const <int>[] : hexToBytes(group),
    );
  }

  /// The collection of [tag] ended without an object — for good (D-34):
  /// every holder had nothing, `TTL_media` passed, it was displaced, or the
  /// rounds of `bulk_collect.dart` brought no new stripe. The file is
  /// `failed` with its reason here, and the sender is told
  /// (`MTV3_MEDIA_ABORT`), so both ends show the same reason (§9.4
  /// "Reasons"). `false` if this identity does not know [tag].
  bool bulkCollectionFailed(Uint8List tag, String why) {
    final key = tagHex(tag);
    final e = _bulkIncoming[key];
    if (e == null || _disposed) return false;
    final conversationId = e['conv'] as String;
    final msgId = e['msg'] as String;
    final (reason, complete, stripes) = _collectionFailureReason(why);
    _log.warn('[E2E media-mass-recv-failed] msgId=${msgId.substring(0, 8)} — $why');
    _bulkIncomingRemove(key);
    _streamSeeds.remove(key);
    final msg = _bulkMessage(conversationId, msgId);
    if (msg != null) {
      _mediaFail(msg, reason, why,
          detail: stripes > 0 ? '$complete/$stripes' : null);
    }
    _mediaAbortSend(e['from'] as String, key, reason,
        complete: complete, stripes: stripes, groupHex: e['group'] as String?);
    return true;
  }

  /// The reason of §9.4 for a failure text of `bulk_collect.dart`, with the
  /// stripe counts where the text names them ("x of y stripes").
  (FailureReason, int, int) _collectionFailureReason(String why) {
    if (why.startsWith('none of the') || why.startsWith('expired')) {
      return (FailureReason.holdersGone, 0, 0);
    }
    final m = RegExp(r'(\d+) of (\d+) stripes').firstMatch(why);
    if (m == null) return (FailureReason.incomplete, 0, 0);
    final x = int.parse(m.group(1)!), y = int.parse(m.group(2)!);
    // "abandoned — m of y stripes below 7 pieces" names the MISSING ones.
    return (FailureReason.incomplete, why.startsWith('abandoned') ? y - x : x, y);
  }

  /// The user asks for an announced lane 3 object (click on the bubble).
  /// `null` if [messageId] is no lane 3 announcement of this identity.
  bool? _bulkAcceptDownload(String messageId) {
    for (final e in _bulkIncoming.entries) {
      if (e.value['msg'] == messageId) return _bulkCollectStart(e.key);
    }
    return null;
  }

  /// An incoming file that still waits (`announced`, `downloading`) but has
  /// no lane 2/3 entry any more — the area was damaged, or the entry was
  /// displaced by the bound [_kBulkIncomingAtMost] — can never be collected:
  /// `K_T` and the holders lived only in that entry. It is `failed` with its
  /// reason (§9.3, §9.4 "Reasons", D-34), never offered for a fetch on
  /// request (S399 P2-7). Runs once per attach, after [_bulkResume].
  void _bulkOrphansFail() {
    final waiting = <String>{
      for (final e in _bulkIncoming.values) e['msg'] as String,
    };
    ensureAllLoaded();
    var failed = 0;
    for (final conv in conversations.values) {
      for (final msg in conv.messages.toList()) {
        if (msg.isOutgoing || waiting.contains(msg.id)) continue;
        if (msg.mediaState != MediaDownloadState.announced &&
            msg.mediaState != MediaDownloadState.downloading) {
          continue;
        }
        _mediaFail(msg, FailureReason.holdersGone,
            'no lane 2/3 entry any more — the file cannot be collected');
        failed++;
      }
    }
    if (failed > 0) {
      _log.info('bulk: $failed waiting file(s) without an entry are failed');
    }
  }

  /// At the attach of the mailbox: the announced objects of the last run
  /// come back; every collection that was running is handed to the
  /// delivery layer again — it remembers none itself (S401), and asking now
  /// is the start edge of §8.2. Older than `TTL_media`: gone at every
  /// holder, the entry goes. Opened blocks of a transfer this store no
  /// longer knows go too: the store is the one source for what is open.
  void _bulkResume() {
    final Map<String, Map<String, dynamic>> all;
    try {
      all = store.loadArea(kBulkIncomingArea);
    } catch (e) {
      _log.warn('bulk: announced objects not loaded — $e');
      return;
    }
    final limit = DateTime.now()
        .subtract(kTtlMedia)
        .millisecondsSinceEpoch;
    final entries = all.entries.toList()
      ..sort((x, y) =>
          ((x.value['at'] as int?) ?? 0).compareTo((y.value['at'] as int?) ?? 0));
    _bulkIncoming.clear();
    for (final e in entries) {
      if (((e.value['at'] as int?) ?? 0) < limit) {
        // Gone at every holder (§9.4): failed, not silently forgotten.
        _bulkIncomingRemove(e.key);
        final msg =
            _bulkMessage(e.value['conv'] as String, e.value['msg'] as String);
        if (msg != null && msg.mediaState != MediaDownloadState.completed) {
          _mediaFail(msg, FailureReason.holdersGone, 'older than TTL_media');
        }
        continue;
      }
      _bulkIncoming[e.key] = e.value;
    }
    myceliumMailbox?.bulkCollector.keepOnly(_bulkIncoming.keys.map(hexToBytes));
    var resumed = 0;
    for (final e in _bulkIncoming.entries.toList()) {
      if (e.value['started'] == true && _bulkCollectStart(e.key, ask: false)) {
        resumed++;
      }
    }
    if (_bulkIncoming.isNotEmpty) {
      _log.info('bulk: ${_bulkIncoming.length} announced object(s), '
          '$resumed collection(s) resumed');
    }
    _bulkOrphansFail();
    // The sender's half (S398-W1): what this identity was placing or
    // announcing when the last run ended goes on (§9.4 "The rest goes into
    // the network").
    _mediaSentLoad();
    _transferResume();
    // S398-W5: the waiting lines of the last run move on (§9.4 "Nothing
    // overtakes a file").
    _fileOrderResume();
  }

  UiMessage? _bulkMessage(String conversationId, String msgId) {
    final conv = conversations[conversationId];
    if (conv == null) return null;
    ensureLoaded(conversationId);
    for (final m in conv.messages) {
      if (m.id == msgId) return m;
    }
    return null;
  }

  void _bulkIncomingPut(String tag, Map<String, dynamic> e) {
    _bulkIncoming[tag] = e;
    try {
      store.putEntry(kBulkIncomingArea, tag, e);
    } catch (x) {
      _log.warn('bulk: entry ${tag.substring(0, 8)} not stored — $x');
    }
    while (_bulkIncoming.length > _kBulkIncomingAtMost) {
      final old = _bulkIncoming.keys.first;
      _bulkIncomingDisplaced(old, _bulkIncoming[old]!);
    }
  }

  /// S399 O-2: the bound of §20.2 displaced the entry of [tag] — the oldest.
  /// `K_T` and the holders lived only in [e], so the file can never be
  /// collected: it is `failed` with its reason now, not left `announced`
  /// until the next start, and the sender is told (`MTV3_MEDIA_ABORT`), so
  /// both ends show the same reason (§9.3, §9.4 "Reasons"). Nothing is sent
  /// again. The reason is `holdersGone` ("holders gone or expired"): of the
  /// seven of §9.4 it is the one the entry's end comes closest to — it
  /// expired here, displaced as the oldest — and the one the start gives the
  /// same file when it finds it without an entry ([_bulkOrphansFail]).
  void _bulkIncomingDisplaced(String tag, Map<String, dynamic> e) {
    final msgId = e['msg'] as String?;
    final conversationId = e['conv'] as String?;
    _log.warn('[E2E media-mass-displaced] msgId=${msgId?.substring(0, 8)} — '
        'displaced by the bound of $_kBulkIncomingAtMost waiting files');
    // Entry first: the collector's failure callback below finds nothing and
    // does not fail the file a second time.
    _bulkIncomingRemove(tag);
    _streamSeeds.remove(tag);
    myceliumMailbox?.bulkCollector.abandon(hexToBytes(tag));
    final msg = conversationId == null || msgId == null
        ? null
        : _bulkMessage(conversationId, msgId);
    if (msg != null &&
        msg.mediaState != MediaDownloadState.completed &&
        msg.mediaState != MediaDownloadState.failed) {
      _mediaFail(msg, FailureReason.holdersGone,
          'displaced by the bound of $_kBulkIncomingAtMost waiting files');
    }
    final from = e['from'] as String?;
    if (from != null) {
      _mediaAbortSend(from, tag, FailureReason.holdersGone,
          groupHex: e['group'] as String?);
    }
  }

  /// Probe access to the bound of [_kBulkIncomingAtMost] (S399 O-2): puts
  /// an entry through the same path an announcement takes.
  @visibleForTesting
  void bulkIncomingPutForTesting(String tag, Map<String, dynamic> e) =>
      _bulkIncomingPut(tag, e);

  @visibleForTesting
  int get bulkIncomingAtMostForTesting => _kBulkIncomingAtMost;

  void _bulkIncomingRemove(String tag) {
    _bulkIncoming.remove(tag);
    try {
      store.removeEntry(kBulkIncomingArea, tag);
    } catch (x) {
      _log.warn('bulk: entry ${tag.substring(0, 8)} not removed — $x');
    }
  }
}
