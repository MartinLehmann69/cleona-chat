// S398-W1 — a file transfer survives interruptions, and one that fails is
// `failed` with its reason at both ends (v4_2 §9.3, §9.4 "The rest goes
// into the network", "Reasons", D-34).
//
// SENDER. Every lane 2/3 transfer has a RECORD in the store area
// [kMediaOutgoingArea] from its first step until its announcement (or holder
// list) is handed to the delivery layer: `K_T`, where the object lies in the
// media store (the file, or an encrypted copy when the object is not the
// file — a voice wrapper), its SHA-256, the lane, whether the announcement
// already went out, the holder of every share and how many pieces were sent
// (`BulkResume`). After a restart — and at every edge of §8.2 — [_transferResume]
// continues every record on lane 3 under the same `K_T`: an interrupted
// stream places the rest (§9.4 "The rest goes into the network"), an
// interrupted placement re-opens the same holders and sends every piece
// again — a holder keeps what it already has, and a piece the last run
// counted as sent may never have left the node (measured: 1216 counted,
// 887 held). The record goes when the announcement is handed over, or
// when the transfer failed. One record is NOT continued on lane 3: a lane 2
// file sent while no mailbox was attached (mark `unsent`, S403) — nothing of
// it has left, and it starts at the attach as it would have started
// (`_streamFromRecord`).
//
// IN THE NETWORK (D-34, for W5 "Nothing overtakes a file"): the moment a file
// is completely in the network — streamed to the end or placed with holders
// — is ONE call, [_mediaInNetwork]: it fires [CleonaService.onMediaInNetwork]
// and is queryable through [mediaInNetwork].
//
// FAILED WITH ITS REASON. [_mediaFail] is the one place that marks a file
// `failed` (sender: the delivery state, §9.1; recipient: the media state)
// and stores the [FailureReason]. When a transfer fails after the other end
// already knows of it, that end is told: `MTV3_MEDIA_ABORT` = tag 16 ‖
// reason u8 ‖ complete u32 ‖ stripes u32, both directions — the recipient
// whose collection failed for good, the sender that gave up after its
// announcement. Both ends show the same reason. A file is never sent again
// (§9.3).

part of 'cleona_service.dart';

/// Sender records of running lane 2/3 transfers, keyed by message id.
const String kMediaOutgoingArea = 'media_outgoing';

/// Sender: transfers whose announcement went out, keyed by hex tag — to
/// map an abort of the recipient to its message, and the "in the network"
/// state (D-34). Bounded; older than `TTL_media` falls at start.
const String kMediaSentArea = 'media_sent';
const int _kMediaSentAtMost = 1024;

/// `MTV3_MEDIA_ABORT`: tag ‖ reason ‖ complete ‖ stripes.
const int _kAbortLength = kTagLength + 1 + 4 + 4;

typedef _MediaTargets = ({
  List<ContactInfo> recipients,
  bool fanout,
  Uint8List? groupId,
  int? epoch,
  Uint8List? hash,
});

extension CleonaServiceTransfer on CleonaService {
  // ── Recipients of a media message ─────────────────────────────────────

  /// Who receives a media message in [conversationId], with the group
  /// fields of GM-1 (§9.1.4). `null` for an unknown conversation or a
  /// channel without post permission.
  _MediaTargets? _mediaTargets(String conversationId) {
    // A throwaway image for ONE sending that names the recipient. The keys
    // are the member entry's; the seam finds contact or group pair by the
    // UserID itself (B-3, §22.5.1 "There are no key overrides") — a member
    // without a way gets a `failed` leg there (stage 0).
    ContactInfo member(String hex, String name, Uint8List? x, Uint8List? k,
        Uint8List? e) {
      final c = _contacts[hex];
      return ContactInfo(
        nodeId: hexToBytes(hex),
        displayName: name,
        x25519Pk: c?.x25519Pk ?? x,
        mlKemPk: c?.mlKemPk ?? k,
        ed25519Pk: c?.ed25519Pk ?? e,
        status: 'accepted',
        // §15.2: the anchor comes from the real contact record, not from
        // this throwaway image (same group leg as the 1:1 path).
        peerFoundingEd25519Pk: v41PeerFoundingPk(_contacts[hex]),
      );
    }

    final group = _groups[conversationId];
    if (group != null) {
      return (
        recipients: [
          for (final m in group.members.values)
            if (m.nodeIdHex != identity.userIdHex)
              member(m.nodeIdHex, m.displayName, m.x25519Pk, m.mlKemPk,
                  m.ed25519Pk)
        ].where((c) => c.x25519Pk != null && c.mlKemPk != null).toList(),
        fanout: true,
        groupId: hexToBytes(conversationId),
        epoch: group.membershipEpoch,
        hash: _computeMembershipHash(
            group.membershipEpoch, conversationId, group.members),
      );
    }
    final channel = _channels[conversationId];
    if (channel != null) {
      if (!_hasChannelPermission(channel, 'post')) return null;
      return (
        recipients: [
          for (final m in channel.members.values)
            if (m.nodeIdHex != identity.userIdHex)
              member(m.nodeIdHex, m.displayName, m.x25519Pk, m.mlKemPk,
                  m.ed25519Pk)
        ].where((c) => c.x25519Pk != null && c.mlKemPk != null).toList(),
        fanout: true,
        groupId: hexToBytes(conversationId),
        epoch: channel.membershipEpoch,
        hash: _computeChannelMembershipHash(
            channel.membershipEpoch, conversationId, channel.members),
      );
    }
    final contact = _contacts[conversationId];
    if (contact == null || contact.status != 'accepted') return null;
    return (
      recipients: [contact],
      fanout: false,
      groupId: null,
      epoch: null,
      hash: null,
    );
  }

  // ── Failed, with its reason ───────────────────────────────────────────

  /// The ONE place that marks a file failed (§9.3, §9.4 "Reasons").
  /// Outgoing: the delivery state goes to `failed` — unless a receipt
  /// already proved delivery (§9.2). Incoming: the media state.
  void _mediaFail(UiMessage msg, FailureReason reason, String why,
      {String? detail}) {
    _log.warn('[E2E media-failed] msgId=${msg.id.substring(0, 8)} '
        '${msg.isOutgoing ? 'out' : 'in'} reason=${reason.wireName}'
        '${detail == null ? '' : ' ($detail)'} — $why');
    if (msg.isOutgoing) {
      if (!msg.status.canTransitionTo(MessageStatus.failed)) {
        return _fileOrderRelease(msg);
      }
      msg.status = MessageStatus.failed;
    } else {
      msg.mediaState = MediaDownloadState.failed;
    }
    msg
      ..failureReason = reason
      ..failureDetail = detail;
    _transferProgressEnd(msg.id);
    persistMessage(msg.conversationId, msg);
    _saveConversations();
    onStateChanged?.call();
    // S398-W5: what waited behind the file goes now (§9.4).
    _fileOrderRelease(msg);
  }

  // ── Records ───────────────────────────────────────────────────────────

  /// A new sender record for [msg] (lane `mass` or `stream`), stored at once.
  Map<String, dynamic> _transferRecordNew(UiMessage msg, Uint8List object,
      {required String lane,
      required Uint8List transferKey,
      required proto.ContentMetadata metadata,
      Uint8List? preview}) {
    // The object is the file unless it was wrapped (voice): then a copy,
    // encrypted like every attachment (S362), goes next to it.
    var path = msg.filePath;
    var own = false;
    if (path == null || object.length != msg.fileSize) {
      path = '$profileDir/media/.transfer_${msg.id}';
      MediaStore.instance.writeBytes(path, object);
      own = true;
    }
    final r = <String, dynamic>{
      'conv': msg.conversationId,
      'msg': msg.id,
      'lane': lane,
      'kt': bytesToHex(transferKey),
      'object': path,
      'own': own,
      'sha': bytesToHex(SodiumFFI().sha256(object)),
      'announced': false,
      'meta': base64Encode(metadata.writeToBuffer()),
      if (preview != null) 'preview': bytesToHex(preview),
      'at': DateTime.now().millisecondsSinceEpoch,
    };
    _transferRecordPut(r);
    return r;
  }

  void _transferRecordPut(Map<String, dynamic> r) {
    try {
      store.putEntry(kMediaOutgoingArea, r['msg'] as String, r);
    } catch (x) {
      _log.warn('transfer: record ${(r['msg'] as String).substring(0, 8)} not '
          'stored — $x');
    }
  }

  void _transferRecordDrop(Map<String, dynamic> r) {
    try {
      store.removeEntry(kMediaOutgoingArea, r['msg'] as String);
    } catch (x) {
      _log.warn('transfer: record not removed — $x');
    }
    if (r['own'] == true) MediaStore.instance.delete(r['object'] as String);
  }

  /// The object of [r], checked against its SHA-256; `null` if it is gone
  /// or changed (the user deleted the message, a damaged store).
  Uint8List? _transferObjectLoad(Map<String, dynamic> r) {
    final bytes = MediaStore.instance.readAll(r['object'] as String);
    if (bytes == null) return null;
    return bytesToHex(SodiumFFI().sha256(bytes)) == r['sha'] ? bytes : null;
  }

  // ── In the network (D-34) ─────────────────────────────────────────────

  void _mediaSentPut(String tag, Map<String, dynamic> e) {
    _mediaSent[tag] = e;
    while (_mediaSent.length > _kMediaSentAtMost) {
      final old = _mediaSent.keys.first;
      _mediaSent.remove(old);
      try {
        store.removeEntry(kMediaSentArea, old);
      } catch (_) {}
    }
    try {
      store.putEntry(kMediaSentArea, tag, e);
    } catch (x) {
      _log.warn('transfer: sent entry ${tag.substring(0, 8)} not stored — $x');
    }
  }

  void _mediaSentLoad() {
    try {
      final limit =
          DateTime.now().subtract(kTtlMedia).millisecondsSinceEpoch;
      _mediaSent.clear();
      for (final e in store.loadArea(kMediaSentArea).entries) {
        if (((e.value['at'] as int?) ?? 0) < limit) {
          store.removeEntry(kMediaSentArea, e.key);
        } else {
          _mediaSent[e.key] = e.value;
        }
      }
    } catch (x) {
      _log.warn('transfer: sent entries not loaded — $x');
    }
  }

  /// The file of [msg] is completely in the network — streamed to the end
  /// or placed with holders (D-34). The ONE place that says so.
  void _mediaInNetwork(UiMessage msg, String tag) {
    final e = _mediaSent[tag];
    if (e != null) {
      e['net'] = true;
      _mediaSentPut(tag, e);
    }
    _log.info('[E2E media-in-network] msgId=${msg.id.substring(0, 8)} '
        'tag ${tag.substring(0, 8)}');
    try {
      onMediaInNetwork?.call(msg.conversationId, msg.id);
    } catch (x) {
      _log.warn('onMediaInNetwork listener threw: $x');
    }
  }

  /// Whether the file of [messageId] is completely in the network (D-34):
  /// `true`/`false` for a lane 2/3 transfer this identity sent, `null` for
  /// anything else (lane 1, text, unknown).
  bool? mediaInNetwork(String messageId) {
    for (final e in _mediaSent.values) {
      if (e['msg'] == messageId) return e['net'] == true;
    }
    return null;
  }

  // ── Lane 3 for one message: fresh, after lane 2, or resumed ───────────

  /// Places the object of [msg] under the `K_T` of [r] and hands its
  /// announcement over — the full announcement, or the holder list when
  /// lane 2 already announced (`MTV3_MEDIA_HOLDERS`, same tag). [resumed]:
  /// after a restart or at an edge; then "no holder known yet" keeps the
  /// record for the next edge instead of failing.
  Future<void> _laneThree(
      UiMessage msg, Uint8List object, Map<String, dynamic> r,
      {bool resumed = false}) async {
    final conversationId = msg.conversationId;
    final short = msg.id.substring(0, 8);
    final p = myceliumMailbox;
    if (p == null) return; // the record stays; the attach resumes it
    final announced = r['announced'] == true;
    final kT = hexToBytes(r['kt'] as String);
    final tag = tagHex(bulkTag(kT));
    final t = _mediaTargets(conversationId);
    if (t == null || t.recipients.isEmpty) {
      _transferRecordDrop(r);
      return _mediaFail(msg, FailureReason.noRoute, 'no recipient with keys');
    }
    final sends = <(ContactInfo, Uint8List)>[];
    for (final c in t.recipients) {
      if (!t.fanout) {
        sends.add((c, hexToBytes(msg.id)));
        continue;
      }
      final hex = bytesToHex(c.nodeId);
      final leg = msg.fanoutLegs[hex] ??=
          bytesToHex(SodiumFFI().randomBytes(16));
      sends.add((c, hexToBytes(leg)));
    }
    void giveUp(FailureReason reason, String why) {
      _transferRecordDrop(r);
      if (announced) {
        for (final (c, _) in sends) {
          _mediaAbortSend(bytesToHex(c.nodeId), tag, reason,
              groupHex: t.groupId == null ? null : conversationId);
        }
      }
      _mediaFail(msg, reason, why);
    }

    _mediaSentPut(tag, {
      'conv': conversationId,
      'msg': msg.id,
      'to': [for (final (c, _) in sends) bytesToHex(c.nodeId)],
      'at': DateTime.now().millisecondsSinceEpoch,
      'net': false,
    });
    _transferProgress(conversationId, msg.id, TransferPhase.seeding, 0);
    final kept = r['assigned'] as List?;
    var saved = (r['sent'] as int?) ?? 0;
    final BulkPlaced placed;
    try {
      placed = await p.bulkPlaceFor(
          [for (final (c, _) in sends) bytesToHex(c.nodeId)], object,
          transferKey: kT,
          // The same holders again; every piece goes again and a holder
          // keeps what it has (`BulkResume`). `sent` is only the progress
          // seen, for the log.
          resume: kept == null
              ? null
              : (assigned: [for (final a in kept) _addressRead(a as String)]),
          onAssigned: (a) {
            r['assigned'] = [for (final x in a) _addressWrite(x)];
            _transferRecordPut(r);
          },
          progress: (sent, total) {
            _transferProgress(conversationId, msg.id, TransferPhase.seeding,
                total == 0 ? 0 : sent * 100 ~/ total);
            if (sent - saved >= (total ~/ 100 > 64 ? total ~/ 100 : 64)) {
              saved = sent;
              r['sent'] = sent;
              _transferRecordPut(r);
            }
          });
    } on ArgumentError catch (e) {
      return giveUp(FailureReason.tooLarge, '$e');
    } catch (e) {
      // The host stopped under the placement (the process ends): the record
      // stays, the next start resumes it.
      _log.warn('[E2E media-send-path] lane mass msgId=$short interrupted — $e');
      return;
    }
    if (_disposed) return;
    if (placed.failed) {
      if (resumed && placed.reason == 'no holder known') {
        _log.info('[E2E media-send-path] lane mass msgId=$short: no holder '
            'known yet — resumes at the next edge');
        return;
      }
      return giveUp(FailureReason.noHolder, placed.reason ?? 'no holder accepted');
    }
    r['sent'] = placed.pieces;
    _transferRecordPut(r);
    _transferProgress(conversationId, msg.id, TransferPhase.available, 100);
    _mediaInNetwork(msg, tag);
    if (!placed.decodable) {
      // Announced anyway: what lies there is the sender's whole statement;
      // the recipient's collection ends with "incomplete" and says so.
      _log.warn('[E2E media-send-path] lane mass msgId=$short: placed but not '
          'decodable — ${placed.reason}');
    }

    final legs = t.fanout ? msg.fanoutLegs.values.toList() : <String>[msg.id];
    _v41ApplyOutgoingStatus(msg, legs); // index BEFORE sending (sendTextMessage)
    var handed = 0;
    final Uint8List payload;
    if (announced) {
      payload = p.bulkAnnouncement(placed);
    } else {
      final preview = r['preview'] as String?;
      payload = p.bulkAnnouncement(placed,
          preview: preview == null ? null : hexToBytes(preview));
    }
    final meta = proto.ContentMetadata.fromBuffer(
        base64Decode(r['meta'] as String));
    for (final (c, wireId) in sends) {
      final ok = await sendToUser(
        recipientUserId: c.nodeId,
        messageType: announced
            ? proto.MessageTypeV3.MTV3_MEDIA_HOLDERS
            : proto.MessageTypeV3.MTV3_MEDIA_ANNOUNCE,
        payload: payload,
        contentMetadata: announced ? null : meta,
        messageId: announced ? null : wireId,
        // The holder list names the group too (B-3, D-36): a member who is
        // no contact is reached only over the group pair.
        groupId: t.groupId,
        groupMembershipEpoch: t.epoch,
        groupMembershipHash: t.hash,
        // §16.2: the announcement is the group post; the holder list of an
        // earlier announcement is not one.
        postId: announced || msg.postId == null
            ? null
            : hexToBytes(msg.postId!),
      );
      if (ok) {
        handed++;
        statsCollector.addMessageSent();
      }
    }
    _v41ApplyOutgoingStatus(msg, legs);
    _transferRecordDrop(r);
    _transferProgressEnd(msg.id);
    if (handed == 0) {
      return _mediaFail(msg, FailureReason.noRoute,
          'the ${announced ? 'holder list' : 'announcement'} was not handed '
          'to the delivery layer');
    }
    persistMessage(conversationId, msg);
    _saveConversations();
    onStateChanged?.call();
    // S398-W5: in the network AND announced — only now may what waited
    // behind it go; before the announcement it would overtake it (§9.4).
    _fileOrderRelease(msg);
    _log.info('[E2E media-send-done] msgId=$short filename=${msg.filename} '
        'size=${msg.fileSize} recipient=${conversationId.substring(0, 8)} '
        'lane=mass${announced ? ' (after lane 2)' : ''}${resumed ? ' resumed' : ''} '
        'holders=${placed.holders.length} pieces=${placed.pieces} '
        'unplaced=${placed.unplaced} took=${placed.took.inMilliseconds} ms '
        'handed=$handed of ${sends.length}');
  }

  static String _addressWrite(CardAddress? a) =>
      a == null ? '' : '${bytesToHex(a.address)}:${a.port}';

  static CardAddress? _addressRead(String s) {
    final i = s.lastIndexOf(':');
    if (i <= 0) return null;
    try {
      return CardAddress(hexToBytes(s.substring(0, i)), int.parse(s.substring(i + 1)));
    } catch (_) {
      return null;
    }
  }

  // ── Resume (§9.4 "The rest goes into the network") ────────────────────

  /// Continues every sender record not running in this process: at the
  /// attach (start) and at every edge of §8.2 ([bulkEdge]). No clock.
  void _transferResume() {
    if (_disposed || myceliumMailbox == null) return;
    final Map<String, Map<String, dynamic>> all;
    try {
      all = store.loadArea(kMediaOutgoingArea);
    } catch (e) {
      _log.warn('transfer: records not loaded — $e');
      return;
    }
    final limit = DateTime.now().subtract(kTtlMedia).millisecondsSinceEpoch;
    for (final e in all.entries) {
      final r = e.value;
      if (_transfersRunning.contains(e.key)) continue;
      // S398-W5: a file waiting behind a file starts when its turn comes
      // (`_fileOrderStart`), not here.
      if (r['waiting'] == true) continue;
      final msg = _bulkMessage(r['conv'] as String, e.key);
      if (msg == null ||
          msg.status == MessageStatus.delivered ||
          msg.status == MessageStatus.failed) {
        _transferRecordDrop(r);
        continue;
      }
      final object = _transferObjectLoad(r);
      if (r['unsent'] == true && object != null) {
        // S403 (owner decision 12): sent while no mailbox was attached —
        // nothing of it has left, so there is nothing to continue on lane 3
        // and no `TTL_media` to have run out. It starts now, the way it
        // would have started with a mailbox: lane 2 is tried, lane 3 behind
        // it (`_streamRun`).
        _log.info('[E2E media-send-resume] msgId=${e.key.substring(0, 8)} '
            'lane=${r['lane']} unsent — starts at the attach');
        _streamFromRecord(msg, object, r);
        continue;
      }
      final tag = tagHex(bulkTag(hexToBytes(r['kt'] as String)));
      FailureReason? end;
      if (((r['at'] as int?) ?? 0) < limit) end = FailureReason.noHolder;
      if (object == null) end = FailureReason.senderGaveUp;
      if (end != null) {
        _transferRecordDrop(r);
        if (r['announced'] == true) {
          for (final to in (_mediaSent[tag]?['to'] as List?) ?? const []) {
            _mediaAbortSend(to as String, tag, end,
                groupHex: r['conv'] as String);
          }
        }
        _mediaFail(msg, end, object == null
            ? 'the file to resume is gone'
            : 'no holder within TTL_media');
        continue;
      }
      _log.info('[E2E media-send-resume] msgId=${e.key.substring(0, 8)} '
          'lane=${r['lane']} announced=${r['announced']} '
          'sent=${r['sent'] ?? 0}');
      _transfersRunning.add(e.key);
      unawaited(_laneThree(msg, object!, r, resumed: true)
          .whenComplete(() => _transfersRunning.remove(e.key)));
    }
  }

  /// An edge of §8.2 at the host (`HostMedia.onEdge`, set by the seam):
  /// resume what waits.
  void bulkEdge() {
    _transferResume();
    _fileOrderResume(); // S398-W5: the waiting lines
  }

  // ── Abort (both directions) ───────────────────────────────────────────

  /// [groupHex]: the conversation of the transfer when it is a group — the
  /// abort then names it, so it reaches a member who is no contact over the
  /// group pair (B-3, D-36), like the announcement did.
  void _mediaAbortSend(String toHex, String tag, FailureReason reason,
      {int complete = 0, int stripes = 0, String? groupHex}) {
    final c = _contacts[toHex];
    final group =
        groupHex != null && _groups.containsKey(groupHex) ? groupHex : null;
    if (c == null && group == null) {
      _log.warn('[E2E media-abort] to ${toHex.substring(0, 8)}: no contact');
      return;
    }
    final payload = Uint8List(_kAbortLength)
      ..setRange(0, kTagLength, hexToBytes(tag))
      ..[kTagLength] = reason.code;
    ByteData.sublistView(payload)
      ..setUint32(kTagLength + 1, complete, Endian.big)
      ..setUint32(kTagLength + 5, stripes, Endian.big);
    unawaited(sendToUser(
      recipientUserId: c?.nodeId ?? hexToBytes(toHex),
      messageType: proto.MessageTypeV3.MTV3_MEDIA_ABORT,
      payload: payload,
      groupId: group == null ? null : hexToBytes(group),
    ).then((ok) => _log.info('[E2E media-abort] to ${toHex.substring(0, 8)} '
        'tag ${tag.substring(0, 8)} reason=${reason.wireName} sent=$ok')));
  }

  /// `MTV3_MEDIA_ABORT`: the other end gave up this transfer for good.
  void _mediaAbortReceived(HarvestEvent event) {
    final from = event.senderUserId.hex;
    final b = Uint8List.fromList(event.payload);
    if (b.length != _kAbortLength) {
      _log.warn('[E2E media-abort] from ${from.substring(0, 8)} dropped: '
          '${b.length} B');
      return;
    }
    final tag = bytesToHex(Uint8List.sublistView(b, 0, kTagLength));
    final reason =
        FailureReason.fromCode(b[kTagLength]) ?? FailureReason.senderGaveUp;
    final d = ByteData.sublistView(b);
    final complete = d.getUint32(kTagLength + 1, Endian.big);
    final stripes = d.getUint32(kTagLength + 5, Endian.big);
    final detail = stripes > 0 ? '$complete/$stripes' : null;
    // As recipient: the sender of an announced object gave up.
    final e = _bulkIncoming[tag];
    if (e != null && e['from'] == from) {
      _bulkIncomingRemove(tag);
      _streamSeeds.remove(tag);
      myceliumMailbox?.bulkCollector.abandon(hexToBytes(tag));
      final msg = _bulkMessage(e['conv'] as String, e['msg'] as String);
      if (msg != null) {
        _mediaFail(msg, reason, 'the sender gave up', detail: detail);
      }
      return;
    }
    // As sender: a recipient of ours could not assemble the file.
    final s = _mediaSent[tag];
    final to = (s?['to'] as List?)?.cast<String>() ?? const <String>[];
    if (s == null || !to.contains(from)) {
      _log.info('[E2E media-abort] from ${from.substring(0, 8)} tag '
          '${tag.substring(0, 8)}: no transfer of this party');
      return;
    }
    final failedBy = {...?(s['failedBy'] as List?)?.cast<String>(), from};
    s['failedBy'] = failedBy.toList();
    _mediaSentPut(tag, s);
    final msg = _bulkMessage(s['conv'] as String, s['msg'] as String);
    if (msg == null) return;
    // A group message fails only when no member could assemble it; a
    // member that did is its leg's receipt (§9.5 aggregate).
    if (failedBy.length < to.length) {
      _log.info('[E2E media-abort] msgId=${msg.id.substring(0, 8)}: '
          '${failedBy.length} of ${to.length} member(s) report ${reason.wireName}');
      return;
    }
    _mediaFail(msg, reason, 'the recipient could not assemble it',
        detail: detail);
  }
}
