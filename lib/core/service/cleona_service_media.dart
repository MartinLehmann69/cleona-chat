// AP-1c step 3 (docs/MIGRATION_V3_TO_V4_0_MYZEL.md §4c.6) — CLASS B.
//
// Media reception: announcement, chunks, completion — plus the MIME
// detection and the restart of half-sent media after a restart.
//
// CLASS B: the two-stage transfer survives (V4 §5.5/§5.6, fountain), the
// carrier does not. What is domain logic here — which type is this, is it
// a voice message, where did the half upload lie — is rewired.
// AP-3/AP-7 rewrite the content, they do not delete the file.

part of 'cleona_service.dart';

extension V3MediaReceiveOps on CleonaService {


  String _guessMimeType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg': case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'gif': return 'image/gif';
      case 'webp': return 'image/webp';
      case 'mp4': return 'video/mp4';
      case 'webm': return 'video/webm';
      case 'mov': return 'video/quicktime';
      case 'mkv': return 'video/x-matroska';
      case 'mpeg': case 'mpg': return 'video/mpeg';
      case 'mp3': return 'audio/mpeg';
      case 'ogg': case 'oga': return 'audio/ogg';
      case 'wav': return 'audio/wav';
      case 'm4a': case 'aac': return 'audio/aac';
      case 'flac': return 'audio/flac';
      case 'opus': return 'audio/opus';
      case 'pdf': return 'application/pdf';
      case 'txt': return 'text/plain';
      case 'zip': return 'application/zip';
      default: return 'application/octet-stream';
    }
  }


  /// True iff [mimeType] denotes a voice/audio recording (audio/*).
  /// V3 send-paths use this for transcription/voice-payload branching.
  bool _isVoiceFromMime(String mimeType) => mimeType.startsWith('audio/');


  String? _recoverPendingMediaPath(String messageId) {
    for (final conv in conversations.values) {
      ensureAllLoaded();
      for (final msg in conv.messages) {
        // S362: `existsEitherWay` — the attachment lies under `<path>.cmenc`.
        if (msg.id == messageId &&
            msg.filePath != null &&
            MediaStore.instance.existsEitherWay(msg.filePath!)) {
          return msg.filePath;
        }
      }
    }
    return null;
  }


  /// Writes the pending two-stage sends into the store.
  ///
  /// `replaceArea` with ONE record and not `putEntry` per message: the
  /// collection is not a growing but a shrinking one — every entry
  /// disappears as soon as the receiver has collected the blocks
  /// (`_pendingMediaSends.remove`), and open at the same time are at most
  /// the transfers currently running. A full-state writer thus costs
  /// nothing here.
  ///
  /// NO DATA-LOSS LATCH, and that is measured, not presumed: if the map
  /// gets lost, BOTH sides stay intact. The attachment lies unchanged as
  /// `.cmenc` on the sender's disk, the message stands in the store, and on
  /// the receiver side `_recoverStuckMedia` resets the state to `announced`
  /// at the next start — the attachment is then clickable again. What is
  /// lost is only the AUTOMATIC resumption of a half-run transfer. A latch
  /// that blocked the write path for that would be more expensive than the
  /// damage it prevented.
  void _savePendingMediaSends() {
    try {
      if (_pendingMediaSends.isEmpty) {
        store.replaceArea(kPendingMediaSendsArea, const {});
        return;
      }
      store.replaceArea(kPendingMediaSendsArea, {
        kSingleStateKey:
            Map<String, dynamic>.from(_pendingMediaSends),
      });
    } catch (e) {
      _log.warn('Failed to save pending media sends: $e');
    }
  }


  /// V3 MEDIA_ANNOUNCE: Stage-1 announcement of >256KB media. Receiver
  /// either auto-accepts (size+mime policy) or shows a placeholder for
  /// manual click. payload is empty (metadata lives in frame.contentMetadata).
  void _handleMediaAnnounceV3(HarvestEvent event) {
    try {
      // ── STEP 1 OF THE CUT: IS THIS A BULK OFFER? (§9.3) ─────────
      //
      // On the bulk lane MEDIA_ANNOUNCE carries a `BulkAnnounce` in the
      // PAYLOAD (full content hash, object length, possibly the drawn
      // root, micro preview <= 979 B). The V3 two-stage path sent an EMPTY
      // payload here and everything in `contentMetadata`.
      //
      // The distinction is not guessed: `BulkAnnounce.decode` requires the
      // marker byte `0xB1`, the format version and a minimum length of
      // 41 B. An empty V3 payload necessarily fails on that.
      final offer = event.payload.isNotEmpty
          ? BulkAnnounce.decode(Uint8List.fromList(event.payload))
          : null;
      if (offer != null) {
        _handleBulkAnnounce(event, offer);
        return;
      }
      final senderHex = event.senderUserId.hex;
      final mismatchResult = _checkGroupPostMembership(event, senderHex);
      if (mismatchResult == null) return;
      final isMembershipMismatch = mismatchResult;
      final msgId = event.messageId.hex;
      final conversationId = event.groupId != null
          ? event.groupId!.hex
          : senderHex;
      final metadata = event.contentMetadata ?? proto.ContentMetadata();

      final thumbnailB64 = metadata.thumbnail.isNotEmpty
          ? base64Encode(metadata.thumbnail)
          : null;

      final msg = UiMessage(
        id: msgId,
        conversationId: conversationId,
        senderNodeIdHex: senderHex,
        text: metadata.filename,
        timestamp:
            (event.claimedSentAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
        type: _msgTypeFromMime(metadata.mimeType),
        status: MessageStatus.delivered,
        isOutgoing: false,
        mimeType: metadata.mimeType,
        fileSize: metadata.fileSize.toInt(),
        filename: metadata.filename,
        thumbnailBase64: thumbnailB64,
        mediaState: MediaDownloadState.announced,
        membershipMismatch: isMembershipMismatch,
        // Source-side transcript travels along in the metadata — visible
        // before the audio has even been downloaded.
        transcriptText:
            metadata.transcriptText.isNotEmpty ? metadata.transcriptText : null,
        transcriptLanguage: metadata.transcriptText.isNotEmpty
            ? metadata.transcriptLanguage
            : null,
        transcriptConfidence: metadata.transcriptText.isNotEmpty
            ? metadata.transcriptConfidence.toDouble()
            : null,
      );

      final isGroup = _groups.containsKey(conversationId);
      _addMessageToConversation(conversationId, msg, isGroup: isGroup);
      _log.info(
          '[E2E media-announce-v3-recv] from=${senderHex.substring(0, 8)} '
          'device=${CleonaService._hexShort(event.senderDeviceId)} msgId=${msgId.substring(0, 8)} '
          'filename=${metadata.filename} size=${metadata.fileSize} '
          'mime=${metadata.mimeType}');

      // Auto-accept policy per Architecture §3.4.3. Fires the same V3
      // MEDIA_REQUEST path the manual UI click uses.
      final autoOk = _mediaSettings.shouldAutoDownload(
          metadata.mimeType, metadata.fileSize.toInt());
      if (autoOk) {
        _log.info(
            'media-announce-v3 auto-accept: triggering MEDIA_REQUEST for '
            'msgId=${msgId.substring(0, 8)}');
        unawaited(acceptMediaDownload(conversationId, msgId));
      }
    } catch (e) {
      _logHandlerErrorEvent('handleMediaAnnounceV3', e, event, messageType: 'failed');
    }
  }


  // ══ DIE BULK-SPUR, EMPFANGSSEITE (§9.3) ══════════════════════════════

  /// A bulk offer has arrived.
  ///
  /// THE RECEIVER SCANS, IT DOES NOT ASK. §9.3: "The recipient
  /// **scans** the holding relays (§26.6.1: the cache is not queried but
  /// scanned), deduplicates by block id, and asks for refills as an
  /// ordinary message." There is therefore no MEDIA_REQUEST any more that
  /// the sender would have to answer, and no `_pendingMediaSends` on the
  /// other side: the blocks lie in the network.
  void _handleBulkAnnounce(HarvestEvent event, BulkAnnounce offer) {
    final senderHex = event.senderUserId.hex;
    final mismatchResult = _checkGroupPostMembership(event, senderHex);
    if (mismatchResult == null) return;
    final isMembershipMismatch = mismatchResult;
    final msgId = event.messageId.hex;
    final conversationId =
        event.groupId != null ? event.groupId!.hex : senderHex;
    final metadata = event.contentMetadata ?? proto.ContentMetadata();

    // ── THE MARK (§9.3) ───────────────────────────────────────────────
    //
    // It derives from the root IN THE OFFER, and in every case — since
    // 31.08.2026 the 1:1 offer carries it along too (`bulk_keys.dart`: the
    // pairwise branch from `K_AB` is struck, because `K_AB` is pure
    // X25519). Until then a lookup of `K_AB` stood here, which could fail
    // with a still incomplete contact record; it is gone without
    // replacement. Whoever could open the offer has the root — and only
    // the KEX-gated cell path under X25519 + ML-KEM-768 could open it.

    // THE SINK IS BOUND HERE, not at a construction site. It is a property
    // of this receive path, and a binding at exactly the place where the
    // path begins cannot be forgotten — the same pattern by which
    // `V41Host.sendFrame` draws the prekey supply when sending rather than
    // on a clock.
    mediaBulkLane.onDecoded = _bulkDecoded;
    // AT THE SAME PLACE, for the same reason: a callback that is bound
    // where the path BEGINS cannot be forgotten. Without it a hanging
    // harvest ended silently — §9.3 names "refill" in the control flow,
    // and until S363 there was neither a send nor a receive branch for it
    // (finding 3.3).
    mediaBulkLane.onHarvestStalled = _bulkHarvestHangs;

    final ticket = mediaBulkLane.beginReceive(
      conversationId: conversationId,
      messageId: msgId,
      announce: offer,
      // NOT `conversationId`: in a group that is the group identifier, and
      // the DECODED receipt is a statement about ONE leg (§9.3, D2).
      announcerHex: senderHex,
    );

    final preview = offer.preview.isNotEmpty
        ? base64Encode(offer.preview)
        : (metadata.thumbnail.isNotEmpty
            ? base64Encode(metadata.thumbnail)
            : null);

    final msg = UiMessage(
      id: msgId,
      conversationId: conversationId,
      senderNodeIdHex: senderHex,
      text: metadata.filename,
      timestamp:
          (event.claimedSentAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
      type: _msgTypeFromMime(metadata.mimeType),
      status: MessageStatus.delivered,
      isOutgoing: false,
      mimeType: metadata.mimeType,
      // FROM THE OFFER, not from the metadata: the object length stands in
      // the `BulkAnnounce` and is the number from which `k` follows. The
      // metadata is a claim of the sender next to it.
      fileSize: offer.objectLength,
      filename: metadata.filename,
      thumbnailBase64: preview,
      mediaState: MediaDownloadState.announced,
      membershipMismatch: isMembershipMismatch,
      transcriptText:
          metadata.transcriptText.isNotEmpty ? metadata.transcriptText : null,
      transcriptLanguage: metadata.transcriptText.isNotEmpty
          ? metadata.transcriptLanguage
          : null,
      transcriptConfidence: metadata.transcriptText.isNotEmpty
          ? metadata.transcriptConfidence.toDouble()
          : null,
    );
    final isGroup = _groups.containsKey(conversationId);
    _addMessageToConversation(conversationId, msg, isGroup: isGroup);
    _log.info('[E2E media-announce-bulk-recv] '
        'from=${senderHex.substring(0, 8)} msgId=${msgId.substring(0, 8)} '
        'filename=${metadata.filename} size=${offer.objectLength} '
        'k=${ticket?.receiver.sourceBlocks} '
        'preview=${offer.preview.length} B');

    if (ticket == null) return;
    final autoOk = _mediaSettings.shouldAutoDownload(
        metadata.mimeType, offer.objectLength);
    if (!autoOk) return;
    if (!mediaBulkLane.scan(ticket)) {
      _log.warn('Bulk offer ${msgId.substring(0, 8)}: no transport, it '
          'cannot be scanned (§9.3). No fallback to V3.');
    }
  }

  /// An object is complete AND checked against its content hash.
  ///
  /// That it is checked is not decided by this method: `BulkReceiver`
  /// hands out no bytes outside of `BulkVerdict.verified`
  /// (§26.6.1 step 5), and the receipt only comes about together with the
  /// bytes.
  void _bulkDecoded(
      BulkReceiveTicket ticket, Uint8List object, BulkDecodedReceipt receipt) {
    final conv = conversations[ticket.conversationId];
    UiMessage? msg;
    if (conv != null) {
      ensureLoaded(ticket.conversationId);
      final idx = conv.messages.indexWhere((m) => m.id == ticket.messageId);
      if (idx >= 0) msg = conv.messages[idx];
    }
    final filename = msg?.filename ?? 'file_${ticket.messageId}';
    final mediaDir = Directory('$profileDir/media');
    if (!mediaDir.existsSync()) mediaDir.createSync(recursive: true);
    final savePath = CleonaService._uniqueMediaPath(mediaDir.path, filename);
    // S362: encrypted. Up to here the received bulk object lay in plaintext
    // next to the encrypted message it belongs to.
    MediaStore.instance.writeBytes(savePath, object);
    if (msg != null) {
      msg.filePath = savePath;
      msg.fileSize = object.length;
      msg.mediaState = MediaDownloadState.completed;
      if (msg.mimeType?.startsWith('image/') == true &&
          object.length <= 100 * 1024) {
        msg.thumbnailBase64 = base64Encode(object);
      }
      onStateChanged?.call();
      persistMessage(msg.conversationId, msg);
      _saveConversations();
    }
    mediaBulkLane.endReceive(ticket);
    _log.event('V4.1 BULK RECEIVED ${object.length} B, checked — '
        'DECODED receipt goes back (§9.3, D2)');

    // THE RECEIPT IS AN ORDINARY MESSAGE (§9.3, "rides the delivery layer
    // in the chat's mode"). It goes to the SENDER of the offer, not to the
    // group: `delivered` is a statement about a leg.
    final recipient = _contacts[ticket.announcerHex];
    unawaited(sendToUser(
      recipientUserId: recipient?.nodeId ?? hexToBytes(ticket.announcerHex),
      messageType: proto.MessageTypeV3.MTV3_MEDIA_COMPLETE,
      payload: receipt.encode(),
      messageId: hexToBytes(ticket.messageId),
    ));
  }

  /// A send has deposited all planned blocks — or has finally failed to
  /// (§9.3, B-1).
  ///
  /// ── WHY THIS CANNOT STAND IN `_sendOnBulkLane` ─────────────
  ///
  /// Because there is nothing more to learn there. Since S363 the drain
  /// pulls the blocks instead of having them pushed; `emit` returns as
  /// soon as the queue is full — at 200 MB after 4096 of 253 907 blocks.
  /// The rest runs on for hours, and nobody can wait for that: the OFFER
  /// must go out at once, otherwise the receiver has nothing to scan
  /// (§9.3, "harvested by the recipient on its own cadence").
  ///
  /// ── AND WHY NO `failed` IS SET HERE NONETHELESS ────────────
  ///
  /// §9.3 reserves `failed` for "no volunteer and no holder accepted
  /// anything". A shortfall is something else: the blocks that went out
  /// lie there and are harvested — only the set may not suffice, and then
  /// the receiver requests a refill. This place therefore SAYS it, instead
  /// of flipping a status that §9.3 assigns differently.
  ///
  /// ── ON THE NAME, AND IT IS NOT A WHIM ─────────────────────────────
  ///
  /// Until the first corpus probe it was called `_bulkAblageFertig`, and
  /// `smoke_bulk_pq_guard.dart` turned red on it: its pattern for the
  /// forbidden key origin was the bare character sequence `kAb`, and that
  /// sits right in the middle of `bulkAblageFertig`. The pattern has since
  /// been set to word boundaries, the name nevertheless stays the present
  /// one — it is the more precise: what is reported is not "the deposit",
  /// but that THIS SEND has been completely deposited.
  void _bulkShipmentDonePlaced(BulkSendTicket ticket) {
    if (ticket.placementLossless) {
      _log.event('V4.1 BULK STORE DONE ${ticket.messageId.substring(0, 8)}: '
          '${ticket.placementsAccepted} of ${ticket.blocksPlanned} blocks, '
          'without shortfall (§9.3)');
      return;
    }
    _log.warn('V4.1 BULK PARTIAL LOSS ${ticket.messageId.substring(0, 8)}: '
        'planned ${ticket.blocksPlanned}, deposited ${ticket.placementsAccepted}, '
        'without holder/path ${ticket.placementsRefused}, not drawn '
        '${ticket.blocksUndrawn} — the surplus `F` covers part of it, the '
        'receiver requests the rest (§9.3 „refill")');
  }

  /// The harvest hangs — request a refill from the sender (§9.3 "refill").
  ///
  /// ── VIA THE CELL PATH, NOT VIA THE BULK LANE ─────────────────
  ///
  /// §9.3 puts the whole control flow on the delivery layer:
  /// "announce with a one-cell micro-preview, request, refill, DECODED
  /// receipt — rides the delivery layer in the chat's mode". A refill
  /// request on frame type `0x05` would be a fifth opcode with its own
  /// format and without sender binding — it was explicitly NOT proposed
  /// (S363, section 1.7).
  ///
  /// It therefore travels like the DECODED receipt a hand's width further
  /// down: as an ordinary message to the ANNOUNCER, not to the group. In a
  /// group the distinction is essential — the blocks belong to a leg, and
  /// only the announcer can draw fresh seeds.
  ///
  /// ── THE PRICE, MEASURED ───────────────────────────────────────────
  ///
  /// The message is 14 B payload; with `ApplicationFrameV3` (111 B) and
  /// seal (64 B) it is 175 B sealed, i.e. ONE piece, i.e. in secure mode
  /// `m x R` = 3 x 20 = **60 cells** = 8.0 min egress at
  /// `kSlotInterval` = 8 s. If the day capsule is due, it is 120 cells /
  /// 16 min; in speed one cell / 8 s. The sender's answer costs 2 to 1271
  /// bulk cells (0.1 to 40 s at `R_bulk`).
  ///
  /// The RUNNING price is zero: there is no clock that triggers this. The
  /// occasion is a scan round that came up empty, and the number of refill
  /// requests per harvest is capped at [kBulkRefillMaxRequests].
  void _bulkHarvestHangs(BulkReceiveTicket ticket, BulkRefillRequest req) {
    final recipient = _contacts[ticket.announcerHex];
    _log.event('V4.1 BULK REFILL REQUEST ${ticket.messageId.substring(0, 8)}: '
        '${req.wantedBlocks} blocks from '
        '${ticket.announcerHex.substring(0, 8)} '
        '(attempt ${ticket.refillsRequested}/$kBulkRefillMaxRequests, '
        '${ticket.receiver.resolvedSourceBlocks} of '
        '${ticket.receiver.sourceBlocks} source blocks resolved) — via the '
        'cell path, §9.3');
    unawaited(sendToUser(
      recipientUserId: recipient?.nodeId ?? hexToBytes(ticket.announcerHex),
      messageType: proto.MessageTypeV3.MTV3_MEDIA_REQUEST,
      payload: req.encode(),
      messageId: hexToBytes(ticket.messageId),
    ));
  }

  /// A refill request has arrived — answer with FRESH seeds.
  ///
  /// `MediaBulkLane.refill` looks up the running send via the object
  /// identifier; if the request belongs to none, nothing happens. That is
  /// the same latch as with the DECODED receipt: a message that fits no
  /// held object is a claim without proof.
  ///
  /// **The answer goes via the BULK LANE, not via the cell path.** It
  /// consists of blocks, and blocks are cells of entry type `0x05` (§9.3).
  /// Only the QUESTION travels via the delivery layer.
  void _handleBulkRefill(HarvestEvent event, BulkRefillRequest req) {
    final deposited = mediaBulkLane.refill(req);
    if (deposited == 0) {
      _log.warn('Bulk refill request from '
          '${event.senderUserId.hex.substring(0, 8)} for '
          '${req.wantedBlocks} blocks matches no running transfer '
          '(or the drain took nothing) — nothing added');
      return;
    }
    _log.event('V4.1 BULK ADDED $deposited of ${req.wantedBlocks} '
        'blocks for ${event.senderUserId.hex.substring(0, 8)} — fresh '
        'seeds, §9.3');
  }

  /// A DECODED receipt has come back (§9.3, D2).
  void _handleBulkReceipt(HarvestEvent event, BulkDecodedReceipt receipt) {
    final ticket = mediaBulkLane.acceptReceipt(receipt);
    if (ticket == null) {
      // NO `delivered`. A receipt that fits no running send is a claim
      // without proof — exactly the case that flipped the status on the
      // cell path in S354.
      _log.warn('Bulk receipt from ${event.senderUserId.hex.substring(0, 8)} '
          'matches no running transfer — nothing flipped');
      return;
    }
    final conv = conversations[ticket.conversationId];
    if (conv != null) {
      ensureLoaded(ticket.conversationId);
      final idx = conv.messages.indexWhere((m) => m.id == ticket.messageId);
      if (idx >= 0) {
        conv.messages[idx].status = MessageStatus.delivered;
        onStateChanged?.call();
        persistMessage(ticket.conversationId, conv.messages[idx]);
        _saveConversations();
      }
    }
    mediaBulkLane.endSend(ticket);
    _log.event('V4.1 BULK DELIVERED ${ticket.messageId.substring(0, 8)} — '
        'the DECODED receipt is the only proof (§9.3, D2)');
  }

  /// V3 MEDIA_CHUNK: receiver buffers the chunk in `_mediaChunkBuffers`
  /// keyed by mediaIdHex. Reassembly + file-write happens in the matching
  /// MEDIA_COMPLETE handler.
  void _handleMediaChunkV3(HarvestEvent event) {
    try {
      final chunk = proto.MediaChunkV3.fromBuffer(event.payload);
      final mediaIdHex = chunk.mediaId.hex;
      final senderHex = event.senderUserId.hex;

      final buf = _mediaChunkBuffers.putIfAbsent(
          mediaIdHex, () => _MediaChunkBuffer(chunk.totalChunks));
      if (buf.totalChunks != chunk.totalChunks) {
        _log.warn(
            'media-chunk-v3: totalChunks mismatch for $mediaIdHex '
            '(buf=${buf.totalChunks} chunk=${chunk.totalChunks}) — '
            'dropping chunk');
        return;
      }
      if (chunk.chunkIndex >= buf.totalChunks) {
        _log.warn(
            'media-chunk-v3: out-of-bounds index ${chunk.chunkIndex}/${buf.totalChunks} '
            'for $mediaIdHex — drop');
        return;
      }
      buf.chunks[chunk.chunkIndex] = Uint8List.fromList(chunk.data);
      _log.debug(
          '[E2E media-chunk-v3-recv] from=${senderHex.substring(0, 8)} '
          'device=${CleonaService._hexShort(event.senderDeviceId)} mediaId=${mediaIdHex.substring(0, 8)} '
          'idx=${chunk.chunkIndex}/${buf.totalChunks} bytes=${chunk.data.length}');
    } catch (e) {
      _logHandlerErrorEvent('handleMediaChunkV3', e, event);
    }
  }


  /// V3 MEDIA_COMPLETE: assemble buffered chunks, hash-check, write file,
  /// bump the matching UiMessage to MediaDownloadState.completed.
  void _handleMediaCompleteV3(HarvestEvent event) {
    try {
      // ── THE DECODED RECEIPT OF THE BULK LANE (§9.3, D2) ───────────────
      //
      // IT IS THE ONLY THING THAT MAY FLIP `delivered`. §9.3: "Per-batch
      // placement acknowledgments and relay signals are transport
      // diagnostics and flip nothing (§9.2). … `delivered` flips
      // exclusively on the recipient's DECODED receipt under `K_AB`."
      // Exactly this defect — an unproven receipt flipped `delivered` —
      // stood on the cell path in S354; it is not rebuilt here:
      // `BulkSender.acceptsReceipt` compares the FULL content hash in
      // constant time, and if it fits no running send, nothing happens.
      final receipt =
          BulkDecodedReceipt.decode(Uint8List.fromList(event.payload));
      if (receipt != null) {
        _handleBulkReceipt(event, receipt);
        return;
      }
      final complete = proto.MediaCompleteV3.fromBuffer(event.payload);
      final mediaIdHex = complete.mediaId.hex;
      final senderHex = event.senderUserId.hex;
      final conversationId = event.groupId != null
          ? event.groupId!.hex
          : senderHex;

      final buf = _mediaChunkBuffers.remove(mediaIdHex);
      if (buf == null) {
        _log.warn(
            'media-complete-v3: no chunk-buffer for ${mediaIdHex.substring(0, 8)} — drop');
        return;
      }
      if (!buf.isComplete) {
        final missing = <int>[];
        for (var i = 0; i < buf.chunks.length; i++) {
          if (buf.chunks[i] == null) missing.add(i);
        }
        _log.warn(
            'media-complete-v3: incomplete buffer for ${mediaIdHex.substring(0, 8)} '
            '— missing=${missing.length}/${buf.totalChunks}');
        return;
      }
      final assembled = buf.assemble();
      if (complete.totalSize.toInt() != 0 &&
          complete.totalSize.toInt() != assembled.length) {
        _log.warn(
            'media-complete-v3: size mismatch for ${mediaIdHex.substring(0, 8)} '
            '(expected=${complete.totalSize} got=${assembled.length})');
        return;
      }
      final localHash = SodiumFFI().sha256(assembled);
      final wantHash = Uint8List.fromList(complete.contentHash);
      if (wantHash.isNotEmpty && !constantTimeEquals(localHash, wantHash)) {
        _log.warn(
            'media-complete-v3: hash mismatch for ${mediaIdHex.substring(0, 8)}'
            ' — drop reassembled bytes');
        return;
      }

      // Locate the announced UiMessage so we can read filename/mime and bump
      // the mediaState. The MEDIA_ANNOUNCE handler stored the bubble keyed
      // by msgId (= mediaId) in the same conversation.
      final conv = conversations[conversationId];
      UiMessage? msg;
      if (conv != null) {
        ensureLoaded(conversationId);
        final idx = conv.messages.indexWhere((m) => m.id == mediaIdHex);
        if (idx >= 0) msg = conv.messages[idx];
      }
      final filename =
          msg?.filename ?? 'file_$mediaIdHex';
      final mediaDir = Directory('$profileDir/media');
      if (!mediaDir.existsSync()) mediaDir.createSync(recursive: true);
      final savePath = CleonaService._uniqueMediaPath(mediaDir.path, filename);
      // S362: encrypted — see `_bulkDecoded`, same class.
      MediaStore.instance.writeBytes(savePath, assembled);

      if (msg != null) {
        msg.filePath = savePath;
        msg.fileSize = assembled.length;
        msg.mediaState = MediaDownloadState.completed;
        if (msg.mimeType?.startsWith('image/') == true &&
            msg.thumbnailBase64 == null &&
            assembled.length <= 100 * 1024) {
          msg.thumbnailBase64 = base64Encode(assembled);
        }
        onStateChanged?.call();
        persistMessage(msg.conversationId, msg);
        _saveConversations();

        // Local transcription fallback for voice without sender transcript —
        // counterpart to _handleMediaInlineV3. Applies when the sender runs
        // an older version (metadata without transcript fields) or no
        // Whisper model was present on the sender side.
        if (msg.mimeType?.startsWith('audio/') == true &&
            (msg.transcriptText == null || msg.transcriptText!.isEmpty)) {
          _voiceTranscription?.enqueueTranscription(
            messageId: mediaIdHex,
            audioFilePath: savePath,
          );
        }
      }

      _log.info(
          '[E2E media-stage2-recv-done-v3] from=${senderHex.substring(0, 8)} '
          'device=${CleonaService._hexShort(event.senderDeviceId)} mediaId=${mediaIdHex.substring(0, 8)} '
          'bytes=${assembled.length} path=$savePath');
    } catch (e, st) {
      _log.warn('handleMediaCompleteV3: failed: $e\n$st '
          '(sender=${CleonaService._hexShort(Uint8List.fromList(event.senderUserId))})');
    }
  }
}
