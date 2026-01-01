// §16.2.5 (S407 channel step 2) — a post going out on the shared key.
//
// 1. The author builds the post — the application frame a pairwise leg would
//    carry (post identifier, epoch and hash of §16.2.2, content), the keeper
//    list — signs it with its identity key (§4.4.3) and encrypts it ONCE
//    under the step key of `(g, d, j)`. An object below 256 KB is its own
//    entry that the post names.
// 2. Deposit with the first three keepers that answer; placed at the second
//    acknowledgement (mycelium `channel_deposit.dart`).
// 3. Nudge: the same entry, without its objects, to every member served on
//    the shared key — wrapped per pair, steps 1 and 3, never acknowledged,
//    never sent again (mycelium `mailbox_channel.dart`).
//
// Members that have not shown the capability get pairwise legs with the
// same post identifier: [_skServe] returns them to the caller, which sends
// its legs as before. The state of the post is that of its placing (§16.2.3).
//
// A post with a link (S410 follow-up, owner 29.10.2026 "A"): it is sealed
// and kept at once as it would go without a preview, and holds the POST
// LINE of its group while the sender fetches the preview; the posts written
// after it are sealed and kept, and go after it. Once fetched it is sealed
// again with the preview and the kept copy is dropped ([_skGo],
// [_skLinkReplace], [_skLineMove]).

part of 'cleona_service.dart';

final Uint8List _kSkPostDomain = Uint8List.fromList(utf8.encode('cleona-channel-post/v1'));

/// A sealed post in the post line of a group or channel (S410 follow-up):
/// [go] nudges and deposits it; [link] names the message of a link post,
/// which holds the line until it is [ready]; [value] and [hashes] are what
/// its seal entered as held (dropped with a kept copy that is replaced).
class _SkWaiting {
  final String key;
  final void Function() go;
  final String value;
  final List<String> hashes;
  final String? link;
  bool ready = false;
  _SkWaiting({
    required this.key,
    required this.go,
    required this.value,
    required this.hashes,
    this.link,
  });
}

extension CleonaServiceSharedKeyPost on CleonaService {
  /// Serves a post of [gid] on the shared key. Returns the members still to
  /// be served on pairwise legs, or `null` when [gid] runs on pairwise legs
  /// here (then every member gets its leg, as before).
  ///
  /// [object]: an inline object (< 256 KB) deposited as its own entry; the
  /// frame then carries an empty payload and the post names the entry.
  ///
  /// [linkWaits] (a post [msg] with a link whose preview is being fetched,
  /// S410 follow-up): the post is sealed and kept as it would go without a
  /// preview, and holds the post line of [gid] — nothing written after it
  /// is nudged or deposited before it. [linkResealed]: the same post sealed
  /// again with its preview; it takes the place of the kept copy, which is
  /// dropped, and the line moves on ([_skLinkReady] when sealing fails).
  Future<Set<String>?> _skServe(
    String gid, {
    required proto.MessageType type,
    required Uint8List payload,
    required Uint8List messageId,
    Uint8List? postId,
    proto.ContentMetadata? contentMetadata,
    proto.EditMetadata? editMetadata,
    proto.ExpiryMetadata? expiryMetadata,
    int? epoch,
    Uint8List? hash,
    UiMessage? msg,
    Uint8List? object,
    bool linkWaits = false,
    bool linkResealed = false,
  }) async {
    if (!_skOn(gid)) return null;
    final s = _sk(gid)!;
    final gen = s.current;
    if (gen == null || !_skMayPost(gid, identity.userIdHex)) return null;
    final today = _skToday();
    if (gen.day < today) {
      gen
        ..day = today
        ..step = 0;
    }
    final step = gen.stepKey(gen.day, gen.step);
    if (step == null) {
      _log.warn('shared key ${_skShort(gid)}: no step key for '
          '(${gen.number}, ${gen.day}, ${gen.step}) — pairwise legs this time');
      return null;
    }
    final served = _skServed(s);
    final pairwise = {
      for (final hex in _skRoles(gid).keys)
        if (hex != identity.userIdHex && !served.contains(hex)) hex
    };
    // In a channel every member holds the role state; a post names it.
    var e = epoch, h = hash;
    final ch = _channels[gid];
    if (ch != null && _channelShortList(ch)) {
      e = _channelRoleEpoch(ch);
      h = _channelRoleHash(e, ch);
    }
    final frame = _innerFrame(
      recipientUserId: hexToBytes(gid),
      senderUserId: identity.userId,
      messageId: messageId,
      messageType: type,
      payload: object != null ? Uint8List(0) : payload,
      groupId: hexToBytes(gid),
      contentMetadata: contentMetadata,
      editMetadata: editMetadata,
      expiryMetadata: expiryMetadata,
      groupMembershipEpoch: e,
      groupMembershipHash: h,
      postId: postId,
    );
    centry.EntryHead head(int kind) => centry.EntryHead(
        kind: kind,
        generation: gen.number,
        generationId: gen.id,
        day: gen.day,
        step: gen.step,
        id: SodiumFFI().randomBytes(chain.kEntryIdLength));
    final entries = <Uint8List>[];
    final objects = <Uint8List>[];
    if (object != null) {
      final o = centry.entrySeal(head(centry.kEntryObject), step, object);
      entries.add(o);
      objects.add(chain.entryHash(o));
    }
    final ph = head(centry.kEntryPost);
    final frameBytes = Uint8List.fromList(frame.writeToBuffer());
    final post = proto.SharedKeyPost()
      ..frame = frameBytes
      ..signature = SodiumFFI().signEd25519(
          Uint8List.fromList([..._kSkPostDomain, ...ph.toBytes(), ...frameBytes]),
          identity.signingEd25519Sk)
      ..objects.addAll(objects)
      ..keepers.addAll(s.keepers)
      ..keepersVersion = s.keepersVersion;
    if (!_skIsChannel(gid)) post.nextAuthorPk = _skNameAuthorKey(s);
    final entry = centry.entrySeal(ph, step, Uint8List.fromList(post.writeToBuffer()));
    entries.add(entry);
    final value = chain.hexOf(gen.value(gen.day));
    for (final x in entries) {
      _skHeld(s, value, gen.day, chain.hexOf(chain.entryHash(x)));
    }
    if (msg != null) {
      msg.sharedKey = true;
      persistMessage(msg.conversationId, msg);
    }
    _skSave(s);
    final outKey = chain.hexOf(chain.entryHash(entry));
    _skOutPut(outKey, {
      'gid': gid,
      'gen': gen.key,
      'day': gen.day,
      'entries': [for (final x in entries) chain.hexOf(x)],
      if (msg != null) 'msg': msg.id,
    });
    sharedKeyBytes?['entry'] = entry.length;
    // The nudge: the post without its objects, every served member, once,
    // with this first sending (§16.2.5 step 3). A member that may load
    // images collects the object the moment the nudge names it (§9.4) —
    // so a post with an object nudges only after the object's deposit
    // (step 2) has ended; before it, the keepers do not hold the object
    // and that collection finds nothing (report S407-M7).
    void nudge() {
      final p = myceliumMailbox;
      var nudged = 0;
      if (p != null) {
        for (final hex in served) {
          if (p.nudgeSend(hex, entry)) nudged++;
        }
      }
      _log.info('shared key ${_skShort(gid)}: post ${type.name} '
          '(${entry.length} B${object != null ? ' + object ${entries.first.length} B' : ''}) '
          '— nudged $nudged, ${pairwise.length} on pairwise legs');
    }

    void go() {
      if (object == null) {
        nudge();
        unawaited(_skDeposit(outKey));
      } else {
        unawaited(_skDeposit(outKey, afterObjects: nudge));
      }
    }

    final waiting = _SkWaiting(
      key: outKey,
      go: go,
      value: value,
      hashes: [for (final x in entries) chain.hexOf(chain.entryHash(x))],
      link: (linkWaits || linkResealed) ? msg?.id : null,
    );
    if (linkResealed) {
      _skLinkReplace(gid, waiting);
    } else {
      _skGo(gid, waiting);
    }
    return pairwise;
  }

  // ── The post line (S410 follow-up) ────────────────────────────────────

  /// A sealed post goes now — unless a post with a link that waits for its
  /// preview stands in the line of [gid], or it is that post itself: then
  /// it waits in writing order.
  void _skGo(String gid, _SkWaiting w) {
    final line = _skLine[gid];
    if ((line == null || line.isEmpty) && w.link == null) return w.go();
    (_skLine[gid] ??= []).add(w);
    if (line != null && line.isNotEmpty) {
      _log.info('shared key ${_skShort(gid)}: post ${w.key.substring(0, 8)} '
          'waits behind the link post ${line.first.link?.substring(0, 8)} '
          '(place ${line.length} of ${line.length})');
    }
  }

  /// `true` while the kept post [key] waits in a post line — it is not
  /// deposited at an edge before its turn ([_skDeposit]).
  bool _skWaits(String key) {
    for (final line in _skLine.values) {
      for (final w in line) {
        if (w.key == key) return true;
      }
    }
    return false;
  }

  /// The link post [w.link] is sealed again with its preview: the new seal
  /// takes the place of the kept copy, the copy is dropped (its row and the
  /// hashes it entered as held — no keeper ever got it).
  void _skLinkReplace(String gid, _SkWaiting w) {
    final line = _skLine[gid];
    final at = line?.indexWhere((x) => x.link == w.link) ?? -1;
    if (line == null || at < 0) {
      // The line is gone (the conversation ended meanwhile): it goes now.
      return w.go();
    }
    final old = line[at];
    line[at] = w..ready = true;
    _skDropKept(gid, old);
    _skLineMove(gid);
  }

  /// The fetch of the link post [msgId] ended without a new seal: the
  /// kept copy goes as it was sealed.
  void _skLinkReady(String gid, String msgId) {
    final line = _skLine[gid];
    if (line == null) return;
    for (final w in line) {
      if (w.link == msgId) w.ready = true;
    }
    _skLineMove(gid);
  }

  /// The conversation of the link post [msgId] ended while its preview was
  /// fetched: the post does not go; what waited behind it moves on (and is
  /// dropped by [_skDeposit] if the group is gone).
  void _skLinkDrop(String gid, String msgId) {
    final line = _skLine[gid];
    if (line == null) return;
    final at = line.indexWhere((w) => w.link == msgId);
    if (at < 0) return;
    _skDropKept(gid, line.removeAt(at));
    _skLineMove(gid);
  }

  void _skDropKept(String gid, _SkWaiting w) {
    try {
      store.removeEntry(kSharedKeyOutArea, w.key);
    } catch (e) {
      _log.warn('shared key ${_skShort(gid)}: kept post not removed ($e)');
    }
    final s = _sk(gid);
    if (s == null) return;
    for (final h in w.hashes) {
      s.held[w.value]?.remove(h);
    }
    _skSave(s);
  }

  /// Hands on, in writing order, what is due at the head of the post line
  /// of [gid], until a link post that still waits for its preview.
  void _skLineMove(String gid) {
    final line = _skLine[gid];
    while (line != null && line.isNotEmpty) {
      final head = line.first;
      if (head.link != null && !head.ready) return;
      line.removeAt(0);
      head.go();
    }
    _skLine.remove(gid);
  }

  void _skHeld(SharedKeyState s, String value, int day, String hash) {
    (s.held[value] ??= {}).add(hash);
    s.valueDay[value] = day;
  }

  void _skOutPut(String key, Map<String, dynamic> row) {
    try {
      store.putEntry(kSharedKeyOutArea, key, row);
    } catch (e) {
      _log.warn('shared key: post not kept for its placing ($e)');
    }
  }

  /// Deposits a post that is not placed yet — at once, and at the edges of
  /// §8.2 (§9.3) as a new sending.
  ///
  /// [afterObjects] (first sending of a post with inline objects only) runs
  /// once, when the deposit of the object entries has ended — whatever its
  /// outcome, and also when the deposit does not start — and before the
  /// post entry itself is deposited.
  Future<void> _skDeposit(String key, {void Function()? afterObjects}) async {
    var objectsDone = false;
    void objectsEnded() {
      if (objectsDone) return;
      objectsDone = true;
      afterObjects?.call();
    }

    // A kept post waiting behind a link post goes at its turn, not at an
    // edge before it (S410 follow-up).
    if (_skWaits(key) || !_skDepositing.add(key)) {
      objectsEnded();
      return;
    }
    try {
      final row = store.loadAreaPrefix(kSharedKeyOutArea, key)[key];
      final p = myceliumMailbox;
      if (row == null || p == null) return;
      final gid = row['gid'] as String;
      final s = _sk(gid);
      final gen = s?.generations[row['gen'] as String];
      if (s == null || gen == null) {
        store.removeEntry(kSharedKeyOutArea, key);
        return;
      }
      if (gen.certificate == null) {
        _log.info('shared key ${_skShort(gid)}: no certificate yet — the post '
            'rests until it comes');
        return;
      }
      final day = row['day'] as int;
      final collect = gen.collect(day);
      final keys = (
        value: gen.value(day),
        collectPk: collect.publicKey,
        generationPk: gen.generationPk,
        authorPk: gen.authorPk!,
        authorSk: gen.authorSk!,
        certificate: gen.certificate!,
      );
      final keepers = _skKeepers(s);
      final entries = [for (final x in row['entries'] as List) hexToBytes(x as String)];
      final channel = HostChannel.of(p.host.node);
      var placed = true;
      final failed = <CardAddress>[];
      for (var i = 0; i < entries.length; i++) {
        final last = i == entries.length - 1;
        // The post entry is the last one; its objects stand before it.
        if (last) objectsEnded();
        final end = await channel.depositor.deposit(entries[i], keys, keepers,
            onPlaced: last ? () => _skPlaced(gid, row['msg'] as String?) : null);
        placed = placed && end.placed;
        failed.addAll(end.failed);
      }
      if (placed) store.removeEntry(kSharedKeyOutArea, key);
      if (failed.isNotEmpty && _skOwnerHere(gid)) {
        // §16.2.5 "Keepers": the owner's next post carries a list without it.
        s
          ..keepers = _skKeeperList(gid,
              without: {for (final f in failed) _skPack(f).join(',')})
          ..keepersVersion = s.keepersVersion + 1;
        _skSave(s);
      }
    } catch (e) {
      _log.warn('shared key: deposit $key failed ($e)');
    } finally {
      _skDepositing.remove(key);
      objectsEnded();
    }
  }

  /// The post is placed (§16.2.3): `in transit`, and that is final.
  void _skPlaced(String gid, String? msgId) {
    if (msgId == null) return;
    ensureLoaded(gid);
    final msg = conversations[gid]?.messages.where((m) => m.id == msgId).firstOrNull;
    if (msg == null || !msg.status.canTransitionTo(MessageStatus.inTransit)) return;
    msg.status = MessageStatus.inTransit;
    persistMessage(gid, msg);
    onStateChanged?.call();
  }

  /// Every post of [gid] (or of every group) that is not placed yet goes out
  /// again — at an edge of §8.2, or when a certificate arrived.
  Future<void> _skOutResume([String? gid]) async {
    Map<String, Map<String, dynamic>> rows;
    try {
      rows = store.loadArea(kSharedKeyOutArea);
    } catch (_) {
      return;
    }
    await Future.wait([
      for (final e in rows.entries)
        if (gid == null || e.value['gid'] == gid) _skDeposit(e.key)
    ]);
  }
}
