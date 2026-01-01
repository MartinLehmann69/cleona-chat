// §16.2.5 (S407 channel step 2) — an entry coming in on the shared key, by
// nudge or by collection, and the collection itself.
//
// Collection runs at start, on a network change and when the user opens the
// group or channel — never on a clock (§5.4): the member asks the first
// keeper on its newest list that answers for the channel values of the days
// it still lacks (today's and those of the last 7 days not yet closed).
//
// Check (step 5): decrypt, check the signature against the author's key and
// the author's right to post (§16.2.2), take the post once by its
// identifier. An entry that fails is refused, enters the state root and is
// never fetched again.

part of 'cleona_service.dart';

extension CleonaServiceSharedKeyTake on CleonaService {
  /// The attach of the mailbox: the nudge sink of this identity, and the
  /// start edge.
  void _skAttach(mycelium.Mailbox p) {
    HostChannel.of(p.host.node).onNudge[p] = _skNudge;
    unawaited(_skEdge(reason: 'start'));
    unawaited(_capabilityNoticesDue());
  }

  /// An edge (start, network change): what is not placed goes out again,
  /// and every group or channel on the shared key is collected.
  Future<void> _skEdge({required String reason}) async {
    if (sharedKeyOff) return;
    _skLoadAll();
    await _skOutResume();
    await Future.wait([
      for (final s in _sharedKeys.values.toList())
        if (s.generations.isNotEmpty) _skCollect(s.gid, reason: reason)
    ]);
  }

  void _skNudge(String fromHex, Uint8List entry) {
    if (sharedKeyOff) return;
    final head = centry.EntryHead.of(entry);
    if (head == null) return;
    _skLoadAll();
    for (final s in _sharedKeys.values) {
      final g = s.byHead(head.generation, head.generationId);
      if (g == null) continue;
      unawaited(_skTake(s, g, entry));
      return;
    }
    _log.info('shared key nudge from ${_skShort(fromHex)}: a generation this '
        'device does not hold — it collects when it has the keys');
  }

  /// Collects [gid] from its keepers (§16.2.5 step 4). One run at a time:
  /// asked for while a run of [gid] goes on — whose list may predate what
  /// this request is for (an object the nudge just named) —, it is not
  /// dropped but marked, and ONE more run starts when the running one ends,
  /// with every object asked for meanwhile. The returned future completes
  /// when the run that serves this request has ended.
  Future<void> _skCollect(String gid,
      {required String reason, String? object, Set<String>? objects}) {
    final s = _sk(gid);
    final p = myceliumMailbox;
    if (s == null || p == null || sharedKeyOff) return Future.value();
    final asked = {...?objects, ?object};
    if (!_skCollecting.add(gid)) {
      final mark = _skCollectAgain[gid];
      if (mark != null) {
        mark.objects.addAll(asked);
        return mark.done.future;
      }
      final again = (reason: reason, objects: asked, done: Completer<void>());
      _skCollectAgain[gid] = again;
      _log.info('shared key ${_skShort(gid)}: collection ($reason) waits for '
          'the running one — one more run after it');
      return again.done.future;
    }
    return _skCollectRun(s, p, reason, asked).whenComplete(() {
      _skCollecting.remove(gid);
      final again = _skCollectAgain.remove(gid);
      if (again != null) {
        unawaited(_skCollect(gid,
                reason: '${again.reason}, after the running one',
                objects: again.objects)
            .whenComplete(again.done.complete));
      }
    });
  }

  Future<void> _skCollectRun(SharedKeyState s, mycelium.Mailbox p,
      String reason, Set<String> objects) async {
    final gid = s.gid;
    try {
      final keepers = _skKeepers(s);
      if (keepers.isEmpty) return;
      final today = _skToday();
      final c = HostChannel.of(p.host.node).collector;
      for (final g in s.generations.values.toList()) {
        final values = <({Uint8List value, Uint8List collectPk, Uint8List collectSk})>[];
        for (var d = today - chain.kKeepDays; d <= today; d++) {
          if (g.dayKey(d) == null && !g.stepFloor.containsKey(d)) continue;
          final v = g.value(d);
          final vh = chain.hexOf(v);
          if (s.closed.contains(vh) && objects.isEmpty) continue;
          s.valueDay[vh] = d;
          final pair = g.collect(d);
          values.add((value: v, collectPk: pair.publicKey, collectSk: pair.secretKey));
        }
        if (values.isEmpty) continue;
        final heldOrRefused = <String>{
          for (final v in values) ...?s.held[chain.hexOf(v.value)]
        };
        final end = await c.collect((
          generationPk: g.generationPk,
          values: values,
          heldOrRefused: heldOrRefused,
          wanted: (hash, kind) => kind != centry.kEntryObject ||
              objects.contains(hash) ||
              _skObjectWanted(s, hash),
        ), keepers, (value, entry) => unawaited(_skTake(s, g, entry)));
        // A day is closed once a question after its end was answered "same".
        if (end.same) {
          for (final v in values) {
            final d = s.valueDay[chain.hexOf(v.value)] ?? today;
            if (d < today) s.closed.add(chain.hexOf(v.value));
          }
        }
        _log.info('shared key ${_skShort(gid)}: collected ($reason) — '
            '${end.keeper == null ? 'no keeper answered' : end.same ? 'same' : '${end.got} entr(ies)'}');
      }
      await sharedKeyCollectHeld?.call(gid);
      _skSave(s);
    } catch (e) {
      _log.warn('shared key ${_skShort(gid)}: collection failed ($e)');
    }
  }

  /// An inline object is fetched now when its image may load (§9.4), or when
  /// it is not an image a post waits for.
  bool _skObjectWanted(SharedKeyState s, String hash) {
    final msgId = s.objects[hash];
    final load = _skLoadImages(s.gid);
    if (msgId == null) return load; // its post is not here yet
    return load || msgId.startsWith('!');
  }

  /// One entry: refused, or taken once.
  Future<void> _skTake(SharedKeyState s, SharedGeneration g, Uint8List entry) async {
    final head = centry.EntryHead.of(entry);
    if (head == null) return;
    final value = chain.hexOf(g.value(head.day));
    final hash = chain.hexOf(chain.entryHash(entry));
    if (s.held[value]?.contains(hash) ?? false) return; // taken once
    _skHeld(s, value, head.day, hash);
    final step = g.stepKey(head.day, head.step);
    final body = step == null ? null : centry.entryOpen(entry, step);
    if (body == null) {
      _skSave(s);
      _log.info('shared key ${_skShort(s.gid)}: entry ${hash.substring(0, 8)} '
          'does not open (before the joining, or altered) — refused');
      return;
    }
    if (head.kind == centry.kEntryObject) {
      _skSave(s);
      await _skObjectArrived(s, hash, body);
      return;
    }
    final proto.SharedKeyPost post;
    final proto.ApplicationFrame frame;
    try {
      post = proto.SharedKeyPost.fromBuffer(body);
      frame = proto.ApplicationFrame.fromBuffer(post.frame);
    } catch (_) {
      _skSave(s);
      return;
    }
    final author = bytesToHex(Uint8List.fromList(frame.senderUserId));
    final pk = _skMemberEdPk(s.gid, author);
    final signed = Uint8List.fromList(
        [..._kSkPostDomain, ...head.toBytes(), ...post.frame]);
    if (pk == null ||
        !chain.verifies(signed, Uint8List.fromList(post.signature), pk) ||
        !_skMayPost(s.gid, author) ||
        bytesToHex(Uint8List.fromList(frame.groupId)) != s.gid) {
      _skSave(s);
      _log.warn('shared key ${_skShort(s.gid)}: entry ${hash.substring(0, 8)} '
          'from ${_skShort(author)} — signature or right to post does not hold, '
          'refused');
      return;
    }
    g.seen(head.day, head.step);
    if (post.keepers.isNotEmpty && post.keepersVersion > s.keepersVersion) {
      s
        ..keepers = [for (final k in post.keepers) Uint8List.fromList(k)]
        ..keepersVersion = post.keepersVersion;
    }
    if (post.nextAuthorPk.length == 32 && _skRecords(s.gid)) {
      s.named[author] = bytesToHex(Uint8List.fromList(post.nextAuthorPk));
    }
    _skSave(s);
    if (author == identity.userIdHex) return; // the own post, collected back
    if (post.objects.isNotEmpty) {
      await _skPostWithObject(s, frame, chain.hexOf(post.objects.first));
      return;
    }
    await _skDispatch(s, frame);
  }

  /// Hands the frame to the receive path as a pairwise leg would arrive —
  /// without a delivery identifier (this file keeps it once) and without a
  /// receipt (§16.2.3: no `delivered` per member, no read marks).
  Future<void> _skDispatch(SharedKeyState s, proto.ApplicationFrame frame) async {
    final ch = _channels[s.gid];
    if (ch != null && !ch.roleView) {
      // A post names the role state every member holds; owner and admins
      // keep the complete list and check nothing against it.
      frame
        ..clearGroupMembershipEpoch()
        ..clearGroupMembershipHash();
    }
    await handleApplicationFrame(
      event: HarvestEvent.fromApplicationFrame(
        frame: frame,
        senderDeviceId: null,
        snapshot: SenderIdentitySnapshot(
          senderDeviceId: null,
          senderUserId: Uint8List.fromList(frame.senderUserId),
          outerSigStatus: OuterSigStatus.verified,
          verifiedDeviceEd25519Pk: null,
          verifiedDeviceMlDsaPk: null,
          newKeyDetectedForSenderUser: false,
          receivedAt: sharedKeyClock(),
        ),
      ),
      wasDirect: false,
    );
  }

  // ── Inline objects (§9.4 "Loading images in a group or channel") ──────

  /// A post naming an inline object. An image shows as not loaded until it
  /// is collected — at once while "always load images" is on, by a tap
  /// otherwise; any other object is collected at once and the post waits.
  Future<void> _skPostWithObject(
      SharedKeyState s, proto.ApplicationFrame frame, String objectHash) async {
    final kept = _skObjectBytes.remove(objectHash);
    if (kept != null) {
      frame.payload = kept;
      await _skDispatch(s, frame);
      return;
    }
    final meta = frame.hasContentMetadata() ? frame.contentMetadata : null;
    final image = meta?.mimeType.startsWith('image/') ?? false;
    final msgId = bytesToHex(Uint8List.fromList(frame.messageId));
    if (image) {
      final author = bytesToHex(Uint8List.fromList(frame.senderUserId));
      final msg = UiMessage(
        id: msgId,
        conversationId: s.gid,
        senderNodeIdHex: author,
        text: meta!.filename,
        timestamp: sharedKeyClock(),
        type: UiMessageType.image,
        status: MessageStatus.delivered,
        isOutgoing: false,
        mimeType: meta.mimeType,
        fileSize: meta.fileSize.toInt(),
        filename: meta.filename,
        thumbnailBase64: meta.thumbnail.isEmpty ? null : base64Encode(meta.thumbnail),
        mediaState: _skLoadImages(s.gid)
            ? MediaDownloadState.downloading
            : MediaDownloadState.announced,
        postId: frame.postId.isEmpty ? null : bytesToHex(Uint8List.fromList(frame.postId)),
      );
      _addMessageToConversation(s.gid, msg,
          isGroup: _groups.containsKey(s.gid), isChannel: _skIsChannel(s.gid));
      s.objects[objectHash] = msgId;
    } else {
      // '!' marks a post that waits for its object whatever the setting.
      s.objects[objectHash] = '!${bytesToHex(Uint8List.fromList(frame.writeToBuffer()))}';
    }
    _skSave(s);
    if (_skLoadImages(s.gid) || !image) {
      unawaited(_skCollect(s.gid, reason: 'inline object', object: objectHash));
    }
  }

  Future<void> _skObjectArrived(SharedKeyState s, String hash, Uint8List object) async {
    final waiting = s.objects.remove(hash);
    if (waiting == null) {
      // Its post is not here yet: kept in memory until it comes.
      _skObjectBytes[hash] = object;
      while (_skObjectBytes.length > 16) {
        _skObjectBytes.remove(_skObjectBytes.keys.first);
      }
      return;
    }
    _skSave(s);
    if (waiting.startsWith('!')) {
      final frame = proto.ApplicationFrame.fromBuffer(hexToBytes(waiting.substring(1)))
        ..payload = object;
      await _skDispatch(s, frame);
      return;
    }
    _skImageComplete(s.gid, waiting, object);
  }

  /// The image of a post shown as not loaded has arrived.
  void _skImageComplete(String gid, String msgId, Uint8List container) {
    ensureLoaded(gid);
    final msg = conversations[gid]?.messages.where((m) => m.id == msgId).firstOrNull;
    if (msg == null) return;
    final Uint8List bytes;
    try {
      bytes = mycelium.inlineObject(container);
    } catch (e) {
      _log.warn('shared key ${_skShort(gid)}: image ${_skShort(msgId)} broken ($e)');
      return;
    }
    final dir = Directory('$profileDir/media');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final path = CleonaService._uniqueMediaPath(
        dir.path, msg.filename?.isNotEmpty == true ? msg.filename! : 'file_$msgId');
    MediaStore.instance.writeBytes(path, bytes);
    msg
      ..filePath = path
      ..fileSize = bytes.length
      ..mediaState = MediaDownloadState.completed;
    msg.thumbnailBase64 ??= bytes.length <= 100 * 1024 ? base64Encode(bytes) : null;
    persistMessage(gid, msg);
    onStateChanged?.call();
  }

  /// A tap on an image shown as not loaded (§9.4): that one image is
  /// collected. `null` when [messageId] is no such image.
  Future<bool>? _skAcceptDownload(String conversationId, String messageId) {
    final s = _sk(conversationId);
    if (s == null) return null;
    final hash = s.objects.entries
        .where((e) => e.value == messageId)
        .map((e) => e.key)
        .firstOrNull;
    if (hash == null) return null;
    ensureLoaded(conversationId);
    final msg = conversations[conversationId]
        ?.messages
        .where((m) => m.id == messageId)
        .firstOrNull;
    if (msg != null) {
      msg.mediaState = MediaDownloadState.downloading;
      persistMessage(conversationId, msg);
      onStateChanged?.call();
    }
    return _skCollect(conversationId, reason: 'tap on an image', object: hash)
        .then((_) => !s.objects.containsKey(hash));
  }
}
