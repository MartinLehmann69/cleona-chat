// v4_2 §8.2 "After more than 7 days", §9.5, §20.2, D-48 (owner decision 11
// of 02.10.2026) — catching up after more than 7 days: THE RETURNING DEVICE.
//
// A message lies with holders for at most 7 days and is never placed a
// second time. A device whose last collection lies further back asks every
// party for what it missed — with the reconciliation of §14.6.3
// (`reconcile_wire.dart`: the same packets, the same bounds), carried
// between the two parties of a pair as the ordinary message `MTV3_CATCH_UP`.
//
// THIS FILE: the stored moment, the check, the requests, and what the
// requester does with an answer. The party asked is in
// `cleona_service_catch_up_source.dart`.
//
//  * The moment is the end of the last collection that at least one holder
//    answered (`NodeCollectAnswered`, mycelium); it lies in the identity's
//    store, area [kCatchUpArea]. The check runs where such a collection ends
//    and nowhere else — never on a clock (§5.4, D-9).
//  * ONE request per party — every contact and every group pair (§9.5 "Who
//    is asked"); it covers the conversation of the pair and every group both
//    belong to. One open request per party (§20.2): a new one replaces the
//    open one and keeps the earlier moment.
//  * An answer is taken only for the open request it names. A message is
//    taken only if none with its identifier is held; the sender of every
//    taken message is the answering party itself, whatever the record says
//    (§9.5 "what it wrote itself, and only that"; §16.2: the pairwise seal
//    is what authenticates a group post).
//
// NOT HERE (v4_2 Appendix C, not designed): large private channels with a
// shared key and public channels. A channel post is not caught up either:
// the author does not know the identifier under which a subscriber holds it
// (`sendChannelPost` passes none), so the subscriber could not tell a missed
// post from one it has.

part of 'cleona_service.dart';

/// The state area of the catching up in the identity's store.
const String kCatchUpArea = 'catch_up';

/// The entry of [kCatchUpArea] that holds the moment of the last answered
/// collection (`{'at': ms}`).
const String kCatchUpLastCollectionKey = 'last_collection';

/// The open requests of the returning device, one entry per party (§20.2
/// "catching up, open requests on the returning device: 1 per party").
const String kCatchUpOpenArea = 'catch_up_open';

/// §8.2: a collection that ends more than this long after the stored moment
/// has found an absence — the retention of the post box.
const Duration kCatchUpAfter = Duration(days: 7);

/// The kinds of message an answer carries: what a person wrote into a
/// conversation. A file is named by its record and not sent again (§9.4,
/// D-34).
const Set<UiMessageType> kCatchUpTypes = {
  UiMessageType.text,
  UiMessageType.image,
  UiMessageType.video,
  UiMessageType.gif,
  UiMessageType.voiceMessage,
  UiMessageType.file,
};

extension CleonaServiceCatchUp on CleonaService {
  /// The moment the last collection of this identity ended with an answer
  /// from at least one holder (§8.2) — `null`: none yet (a new profile), or
  /// the store is not readable.
  DateTime? get catchUpLastCollection {
    try {
      final at =
          store.loadArea(kCatchUpArea)[kCatchUpLastCollectionKey]?['at'];
      return at is int ? DateTime.fromMillisecondsSinceEpoch(at) : null;
    } catch (e) {
      _log.warn('catch-up: the moment of the last collection is not '
          'readable: $e');
      return null;
    }
  }

  /// Whether there is any open catch-up request on this device (§20.2).
  bool get catchUpHasOpenRequests {
    try {
      return store.loadArea(kCatchUpOpenArea).isNotEmpty;
    } catch (e) {
      _log.warn('catch-up: cannot read open requests: $e');
      return false;
    }
  }

  /// A collection of this identity ended, and at least one holder answered
  /// it — called by the seam (`mycelium_seam.dart`) from the node's report.
  ///
  /// §8.2: "When a collection ends and that moment lies more than 7 days
  /// back, post left for it in between may have expired uncollected, and the
  /// device asks for what it missed (§9.5)." Without a stored moment nobody
  /// is asked: a new profile has missed nothing, and a restored identity has
  /// its own way back (§13).
  ///
  /// The new moment is written AFTER the asking: a process that ends in
  /// between finds the absence again at its next collection.
  void collectionAnswered() {
    if (_disposed) return;
    final now = catchUpClock();
    final last = catchUpLastCollection;
    if (last != null && now.difference(last) > kCatchUpAfter) {
      catchUpAskedSince = last;
      final asked = _catchUpAskAll(last);
      _log.event('catch-up: the last collection lies '
          '${now.difference(last).inDays} days back — $asked '
          'part${asked == 1 ? 'y' : 'ies'} asked for what was missed since '
          'then (§9.5)');
    }
    try {
      store.putEntry(kCatchUpArea, kCatchUpLastCollectionKey,
          {'at': now.millisecondsSinceEpoch});
    } catch (e) {
      _log.warn('catch-up: the moment of this collection is not stored: $e');
    }
  }

  // ── Who is asked (§9.5) ───────────────────────────────────────────────

  /// Every party of this identity: UserID hex → the group a request to it
  /// names (`null` for a contact). "Every contact and every group pair,
  /// once": a co-member who is a contact is asked as a contact; one who is
  /// not is reached as a group pair, with a group the pair carries (§4.3,
  /// §16.2.2).
  Map<String, String?> _catchUpParties() {
    final out = <String, String?>{};
    for (final c in _contacts.values) {
      if (c.status == 'accepted') out[bytesToHex(c.nodeId)] = null;
    }
    final p = myceliumMailbox;
    if (p == null) return out;
    for (final g in _groups.values) {
      if (!g.joined || !g.members.containsKey(identity.userIdHex)) continue;
      for (final m in g.members.keys) {
        if (m == identity.userIdHex || out.containsKey(m)) continue;
        if (p.groupPairOrNull(m)?.groups.contains(g.groupIdHex) ?? false) {
          out[m] = g.groupIdHex;
        }
      }
    }
    return out;
  }

  /// Asks every party for what was missed since [since]. Returns how many
  /// requests were handed to the delivery layer.
  int _catchUpAskAll(DateTime since) {
    var asked = 0;
    for (final e in _catchUpParties().entries) {
      if (_catchUpAsk(e.key, since.millisecondsSinceEpoch, e.value)) asked++;
    }
    return asked;
  }

  /// The open request to [partyHex], or `null`.
  Map<String, dynamic>? _catchUpOpen(String partyHex) {
    try {
      return store.loadAreaPrefix(kCatchUpOpenArea, partyHex)[partyHex];
    } catch (e) {
      _log.warn('catch-up: open request to ${partyHex.substring(0, 8)} not '
          'readable: $e');
      return null;
    }
  }

  /// ONE request to [partyHex] (§9.5): an ordinary message that names the
  /// moment and nothing else. An open request to the same party is replaced
  /// and its EARLIER moment kept (§20.2).
  bool _catchUpAsk(String partyHex, int sinceMs, String? groupHex) {
    final open = _catchUpOpen(partyHex);
    final earlier = open?['since'];
    final since = earlier is int && earlier < sinceMs ? earlier : sinceMs;
    final fetchId = SodiumFFI().randomBytes(16);
    try {
      store.putEntry(kCatchUpOpenArea, partyHex, {
        'fetch': bytesToHex(fetchId),
        'since': since,
        'group': ?groupHex,
        'from': 0,
        'got': <int>[],
        'delivered': <String>[],
        'n': 0,
      });
    } catch (e) {
      _log.warn('catch-up: request to ${partyHex.substring(0, 8)} not '
          'stored, not sent: $e');
      return false;
    }
    _catchUpRequestSend(partyHex, fetchId, since, groupHex);
    return true;
  }

  void _catchUpRequestSend(
      String partyHex, Uint8List fetchId, int sinceMs, String? groupHex) {
    _detachedSend(
        'MTV3_CATCH_UP request',
        sendToUser(
          recipientUserId: hexToBytes(partyHex),
          messageType: proto.MessageTypeV3.MTV3_CATCH_UP,
          payload: reconcileEncode(
              catchUpRequestFrame(fetchId: fetchId, sinceMs: sinceMs)),
          // The request's own identifier: its acknowledgement (§9.2) says
          // whether it reached the party ([_catchUpAskAgain]).
          messageId: fetchId,
          groupId: groupHex == null ? null : hexToBytes(groupHex),
        ));
  }

  /// §9.5: "A request that expired in the post box of a party that was
  /// itself away is sent again when a request from that party arrives, never
  /// on a clock." Called when a request from [partyHex] arrived: the own
  /// open request to it goes out once more — unless an answer to it has
  /// begun to arrive or its acknowledgement is here (then it did not expire).
  void _catchUpAskAgain(String partyHex) {
    final open = _catchUpOpen(partyHex);
    if (open == null) return;
    final fetch = open['fetch'], since = open['since'];
    if (fetch is! String || since is! int) return;
    if ((open['got'] as List?)?.isNotEmpty ?? false) return;
    if ((open['from'] as int? ?? 0) > 0) return;
    if (_myceliumDeliveryProven(fetch) ?? false) return;
    _log.event('catch-up: a request from ${partyHex.substring(0, 8)} '
        'arrived — the own request to it, not acknowledged so far, is sent '
        'again (§9.5)');
    _catchUpRequestSend(
        partyHex, hexToBytes(fetch), since, open['group'] as String?);
  }

  // ── Reception (both roles) ────────────────────────────────────────────

  /// `MTV3_CATCH_UP` from a party: a request, a packet of an answer, or a
  /// progress report. Only from a PROVEN sender — an accepted contact, or a
  /// group pair for a group both belong to (`_myceliumInboundAccept` lets
  /// nobody else through; the trust is checked here once more).
  void _catchUpReceived(HarvestEvent event) {
    final partyHex = event.senderUserId.hex;
    if (event.senderTrust != SenderTrust.verified) {
      _log.warn('catch-up: packet from ${partyHex.substring(0, 8)} without '
          'a proven sender — discarded');
      return;
    }
    final frame = reconcileDecode(Uint8List.fromList(event.payload));
    if (frame == null) {
      _log.warn('catch-up: unreadable packet from '
          '${partyHex.substring(0, 8)} — discarded');
      return;
    }
    final groupHex = event.groupId?.hex;
    switch (frame.whichKind()) {
      case proto.ReconcileFrame_Kind.fetch:
        if (frame.fetch.kind != proto.ReconcileFetch_Kind.SINCE) {
          _log.warn('catch-up: a fetch of the kind ${frame.fetch.kind.name} '
              'from ${partyHex.substring(0, 8)} — only own devices may ask '
              'for that (§14.6.3). Discarded.');
          return;
        }
        _catchUpRequestReceived(partyHex, groupHex, frame.fetch);
        // AFTER the own answer is under way: the party is back.
        _catchUpAskAgain(partyHex);
      case proto.ReconcileFrame_Kind.deliver:
        _catchUpDeliverReceived(partyHex, frame.deliver, event.harvestedAt);
      case proto.ReconcileFrame_Kind.progress:
        _catchUpProgressReceived(partyHex, frame.progress);
      default:
        _log.warn('catch-up: a ${frame.whichKind().name} packet from '
            '${partyHex.substring(0, 8)} — not part of §9.5. Discarded.');
    }
  }

  /// The conversation a record or a list entry of [partyHex] names, or
  /// `null` if it lies outside the scope of the pair (§13.5.4: "only what
  /// the pair shares"): the pair's own conversation (empty identifier, only
  /// for a contact), or a group both belong to.
  String? _catchUpScope(String partyHex, List<int> convId) {
    if (convId.isEmpty) {
      return _contacts[partyHex]?.status == 'accepted' ? partyHex : null;
    }
    final gid = bytesToHex(Uint8List.fromList(convId));
    final g = _groups[gid];
    if (g == null ||
        !g.joined ||
        !g.members.containsKey(partyHex) ||
        !g.members.containsKey(identity.userIdHex)) {
      return null;
    }
    return gid;
  }

  /// The groups this identity shares with [partyHex].
  List<GroupInfo> _catchUpSharedGroups(String partyHex) => [
        for (final g in _groups.values)
          if (g.joined &&
              g.members.containsKey(partyHex) &&
              g.members.containsKey(identity.userIdHex))
            g,
      ];

  // ── The requester: an answer arrives (§9.5 "What the requester does") ──

  void _catchUpDeliverReceived(
      String partyHex, proto.ReconcileDeliver d, DateTime arrived) {
    final open = _catchUpOpen(partyHex);
    final fetch = bytesToHex(Uint8List.fromList(d.fetchId));
    if (open == null || open['fetch'] != fetch) {
      // §13.5.4: "An answer that no own broadcast asked for is discarded".
      _log.warn('catch-up: an answer from ${partyHex.substring(0, 8)} that '
          'no open request of this device asked for — discarded');
      return;
    }
    final from = open['from'] as int? ?? 0;
    final got = [...(open['got'] as List? ?? const []).cast<int>()];
    if (d.seq < from || got.contains(d.seq)) {
      _log.debug('catch-up: packet ${d.seq} of the answer from '
          '${partyHex.substring(0, 8)} is here already — dropped');
      return;
    }
    // The answer is placed at the moment its FIRST packet arrived (§22.5.3:
    // the local arrival time, observed), and its messages in the order the
    // author gave them: a later packet of the same answer carries older
    // messages and must not be shown behind the newer ones.
    final anchor = open['arrived'] as int? ?? arrived.millisecondsSinceEpoch;
    var rank = open['n'] as int? ?? 0;
    final delivered = [...(open['delivered'] as List? ?? const []).cast<String>()];
    final party = hexToBytes(partyHex);

    if (d.held.isNotEmpty) {
      _catchUpMarkOwnDelivered(partyHex, [
        for (final id in d.held.take(kCatchUpHeldAtMost))
          bytesToHex(Uint8List.fromList(id))
      ]);
    }
    for (final id in d.deleted.take(kCatchUpDeletedAtMost)) {
      _catchUpDeletedByParty(partyHex, bytesToHex(Uint8List.fromList(id)));
    }
    _catchUpExpiredShow(partyHex, d.expired);
    if (d.tooLarge.isNotEmpty) {
      _log.warn('catch-up: ${d.tooLarge.length} message(s) of '
          '${partyHex.substring(0, 8)} fit no packet and were not sent');
    }

    var taken = 0;
    final rang = <String, UiMessage>{};
    for (final m in d.messages) {
      final convId = _catchUpScope(partyHex, m.convId);
      if (convId == null || m.id.length != 16) {
        _log.warn('catch-up: a record of ${partyHex.substring(0, 8)} outside '
            'the scope of the pair — not taken');
        continue;
      }
      final idHex = bytesToHex(Uint8List.fromList(m.id));
      final isGroup = convId != partyHex;
      // §16.2.3: the report follows the same choice as a delivery receipt.
      final discloses = !_withholdsDeliveryStatusTo(
          party, isGroup ? hexToBytes(convId) : const <int>[]);
      if (_catchUpHolds(convId, idHex)) {
        if (discloses) delivered.add(idHex);
        continue;
      }
      final msg = _catchUpMessageFrom(m, idHex, convId, partyHex,
          DateTime.fromMillisecondsSinceEpoch(anchor - rank));
      rank++;
      if (msg == null) continue;
      if (!_addMessageToConversation(convId, msg, isGroup: isGroup)) {
        continue; // a deletion mark holds it back (§21.5.2)
      }
      taken++;
      if (discloses) delivered.add(idHex);
      rang.putIfAbsent(convId, () => msg);
    }
    catchUpTaken += taken;
    // One sound per conversation and packet, as for a message that arrives.
    for (final e in rang.entries) {
      if (_shouldSuppressNotification(e.key, 0)) continue;
      notificationSound.playMessageSound(
          soundName: conversations[e.key]?.notificationSoundName);
      notificationSound.vibrate(VibrationType.message);
      _postAndroidNotification(
          _contacts[partyHex]?.displayName ?? partyHex.substring(0, 8),
          e.value.text.length > 100
              ? '${e.value.text.substring(0, 100)}...'
              : e.value.text,
          e.key);
      _lastNotifiedAt[e.key] = DateTime.now();
    }

    got.add(d.seq);
    var end = open['end'] as int?;
    var complete = open['complete'] == true;
    if (d.roundEnd) {
      end = d.seq;
      complete = d.complete;
    }
    _log.event('catch-up: packet ${d.seq} of the answer from '
        '${partyHex.substring(0, 8)}: $taken message(s) taken, '
        '${d.messages.length - taken} held already or not taken, '
        '${d.held.length} own named as held, ${d.deleted.length} deleted'
        '${d.roundEnd ? (d.complete ? ' — last packet' : ' — end of a round') : ''}');

    // The round is here when every packet up to its end is: only then the
    // report goes out, and with it the next round may come (§20.2).
    final roundHere =
        end != null && [for (var s = from; s <= end; s++) s].every(got.contains);
    if (!roundHere) {
      _catchUpOpenWrite(partyHex, open, {
        'got': got,
        'delivered': delivered,
        'n': rank,
        'arrived': anchor,
        'end': ?end,
        'complete': complete,
      });
      return;
    }
    _catchUpProgressSend(partyHex, fetch, end + 1, delivered,
        open['group'] as String?);
    if (complete) {
      try {
        store.removeEntry(kCatchUpOpenArea, partyHex);
      } catch (e) {
        _log.warn('catch-up: closed request not removed: $e');
      }
      _log.event('catch-up: the answer from ${partyHex.substring(0, 8)} is '
          'complete — $rank message(s) taken in all');
    } else {
      _catchUpOpenWrite(partyHex, open, {
        'from': end + 1,
        'got': <int>[],
        'delivered': <String>[],
        'n': rank,
        'arrived': anchor,
        'end': null,
        'complete': false,
      });
    }
  }

  void _catchUpOpenWrite(String partyHex, Map<String, dynamic> open,
      Map<String, dynamic> changes) {
    try {
      store.putEntry(kCatchUpOpenArea, partyHex, {...open, ...changes});
    } catch (e) {
      _log.warn('catch-up: open request to ${partyHex.substring(0, 8)} not '
          'written: $e');
    }
  }

  /// The progress report (§9.5 "reports the messages as delivered", §20.2):
  /// [received] packets are here without a gap. The identifiers go in
  /// packets of their own where they do not fit one; only the last carries
  /// [received].
  void _catchUpProgressSend(String partyHex, String fetch, int received,
      List<String> delivered, String? groupHex) {
    final ids = [for (final h in delivered) hexToBytes(h)];
    final parts = <List<Uint8List>>[];
    for (var i = 0; i < ids.length; i += kReconcileFetchIdsAtMost) {
      parts.add(ids.sublist(
          i,
          i + kReconcileFetchIdsAtMost < ids.length
              ? i + kReconcileFetchIdsAtMost
              : ids.length));
    }
    if (parts.isEmpty) parts.add(const []);
    for (var k = 0; k < parts.length; k++) {
      _detachedSend(
          'MTV3_CATCH_UP progress',
          sendToUser(
            recipientUserId: hexToBytes(partyHex),
            messageType: proto.MessageTypeV3.MTV3_CATCH_UP,
            payload: reconcileEncode(catchUpProgressFrame(
                fetchId: hexToBytes(fetch),
                received: k == parts.length - 1 ? received : 0,
                delivered: parts[k])),
            groupId: groupHex == null ? null : hexToBytes(groupHex),
          ));
    }
  }

  /// Whether this device holds a message [idHex] in [convId].
  bool _catchUpHolds(String convId, String idHex) {
    final conv = conversations[convId];
    if (conv == null) return false;
    ensureLoaded(convId);
    return conv.messages.any((m) => m.id == idHex);
  }

  /// The message a record of [partyHex] becomes on this device — its sender
  /// is the answering party, its time the arrival of the answer. `null` for
  /// a record this build does not take.
  UiMessage? _catchUpMessageFrom(proto.ReconcileMessage m, String idHex,
      String convId, String partyHex, DateTime at) {
    final type = UiMessageType.fromInt(m.type);
    if (!kCatchUpTypes.contains(type) || type.wireValue != m.type) {
      _log.warn('catch-up: a record of the kind ${m.type} from '
          '${partyHex.substring(0, 8)} — not taken');
      return null;
    }
    Map<String, dynamic> extra = const {};
    if (m.extraJson.isNotEmpty) {
      try {
        final j = jsonDecode(utf8.decode(m.extraJson));
        if (j is Map<String, dynamic>) extra = j;
      } catch (_) {
        // Unreadable: the record is taken without its rarer fields.
      }
    }
    String? text(String k) => extra[k] is String ? extra[k] as String : null;
    final isFile = type != UiMessageType.text;
    final msg = UiMessage(
      id: idHex,
      conversationId: convId,
      senderNodeIdHex: partyHex,
      text: m.text,
      // §22.5.3: display and sorting rely on the local arrival time only.
      timestamp: at,
      type: type,
      status: MessageStatus.delivered,
      isOutgoing: false,
      editedAt: extra['editedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(extra['editedAt'] as int)
          : null,
      forwardedFrom: text('forwardedFrom'),
      postId: convId == partyHex ? null : text('postId'),
      linkPreviewUrl: text('linkPreviewUrl'),
      linkPreviewTitle: text('linkPreviewTitle'),
      linkPreviewDescription: text('linkPreviewDescription'),
      linkPreviewSiteName: text('linkPreviewSiteName'),
      linkPreviewThumbnailBase64: text('linkPreviewThumbnailBase64'),
      transcriptText: text('transcriptText'),
      transcriptLanguage: text('transcriptLanguage'),
      mimeType: isFile ? text('mimeType') : null,
      filename: isFile ? text('filename') : null,
      fileSize: isFile && extra['fileSize'] is int
          ? extra['fileSize'] as int
          : null,
      // §9.4, D-34: "A file is named by its record and not sent again" — the
      // record says what was sent, and that it can no longer be collected.
      mediaState: isFile ? MediaDownloadState.failed : MediaDownloadState.none,
      failureReason: isFile ? FailureReason.holdersGone : null,
    );
    final quoted = text('replyToMessageId');
    if (quoted != null &&
        CleonaService._isWireCapableMessageIdentifier(quoted)) {
      // §16.2: a quote names the post identifier in a group; the message
      // keeps the identifier the quoted one has HERE.
      final orig = _referredMessage(convId, quoted);
      msg
        ..replyToMessageId = orig?.id ?? quoted
        ..replyToText = text('replyToText') ??
            (orig == null
                ? null
                : (orig.text.length > 200
                    ? orig.text.substring(0, 200)
                    : orig.text))
        ..replyToSender = orig == null
            ? null
            : (_contacts[orig.senderNodeIdHex]?.displayName ??
                (orig.senderNodeIdHex.length >= 8
                    ? orig.senderNodeIdHex.substring(0, 8)
                    : null));
    }
    return msg;
  }

  /// §9.5, §21.5.3 (F5 = C): "For each conversation in that scope it also
  /// names the number of its messages from that time that expired there
  /// unacknowledged — the number, nothing of their content — and the
  /// requester shows it once in that conversation." One system line per
  /// conversation, translated by the interface
  /// ([kNoticeExpiredBeforeRead]). "Once": the packet that carries the
  /// counts is taken once ([_catchUpDeliverReceived] drops its copy).
  void _catchUpExpiredShow(
      String partyHex, List<proto.ReconcileExpired> expired) {
    for (final e in expired.take(kCatchUpExpiredAtMost)) {
      if (e.count <= 0) continue;
      final convId = _catchUpScope(partyHex, e.convId);
      if (convId == null) continue;
      final isGroup = convId != partyHex;
      _addSystemMessage(
          convId, noticeWithCount(kNoticeExpiredBeforeRead, e.count),
          // The types the other system lines of a conversation carry.
          type: isGroup ? UiMessageType.groupInvite : UiMessageType.identityDeleted,
          isGroup: isGroup);
      _log.event('catch-up: ${partyHex.substring(0, 8)} names ${e.count} '
          'message(s) that expired before they arrived here');
    }
  }

  /// §9.5: a message of [partyHex] it deleted while this device was away.
  /// Only the author deletes (§21.5.1): a held message of somebody else
  /// under that identifier stays; one not held gets the mark that keeps a
  /// late copy out, naming who asked.
  void _catchUpDeletedByParty(String partyHex, String idHex) {
    for (final convId in [
      if (_contacts[partyHex]?.status == 'accepted') partyHex,
      for (final g in _catchUpSharedGroups(partyHex)) g.groupIdHex,
    ]) {
      final conv = conversations[convId];
      if (conv == null) continue;
      ensureLoaded(convId);
      final held = conv.messages.where((m) => m.id == idHex).firstOrNull;
      if (held == null) continue;
      if (held.isOutgoing || held.senderNodeIdHex != partyHex) {
        _log.warn('catch-up: ${partyHex.substring(0, 8)} names a message as '
            'deleted that is not its own — it stays');
        return;
      }
      _eraseMessageLocally(convId, held);
      _saveConversations();
      onStateChanged?.call();
      return;
    }
    _markDeleted(idHex, byHex: partyHex);
  }

  /// Own messages to [partyHex] it holds become `delivered` (§9.5 "Its own
  /// messages the answer names as held become `delivered`"; on the answering
  /// side: the messages the requester reports). [idsHex] are the identifiers
  /// the party holds them under: the message identifier 1:1, the identifier
  /// of the party's leg in a group (§16.2).
  ///
  /// The party named them in a packet sealed to this identity (§4.3) — the
  /// same proof a delivery receipt carries (§9.2). A message closed as
  /// `failed` after 14 days without a way becomes `delivered` too (§9.3); one
  /// the user has sent again is no longer in the conversation and is not
  /// found.
  void _catchUpMarkOwnDelivered(String partyHex, List<String> idsHex) {
    if (idsHex.isEmpty) return;
    final ids = idsHex.toSet();
    var changed = 0;
    final closed = <String>{};
    final direct = conversations[partyHex];
    if (direct != null && _contacts[partyHex]?.status == 'accepted') {
      ensureLoaded(partyHex);
      for (final msg in direct.messages) {
        if (!msg.isOutgoing || !ids.contains(msg.id)) continue;
        closed.add(msg.id);
        if (!msg.status.canTransitionTo(MessageStatus.delivered)) continue;
        msg
          ..status = MessageStatus.delivered
          ..failureReason = null
          ..failureDetail = null;
        persistMessage(partyHex, msg);
        changed++;
      }
    }
    for (final g in _catchUpSharedGroups(partyHex)) {
      final conv = conversations[g.groupIdHex];
      if (conv == null) continue;
      ensureLoaded(g.groupIdHex);
      for (final msg in conv.messages) {
        final leg = msg.fanoutLegs[partyHex];
        if (!msg.isOutgoing || leg == null || !ids.contains(leg)) continue;
        closed.add(leg);
        if (!msg.deliveredBy.add(partyHex)) continue;
        msg.withheldBy.remove(partyHex);
        if (msg.isFullyDelivered &&
            msg.status.canTransitionTo(MessageStatus.delivered)) {
          msg
            ..status = MessageStatus.delivered
            ..failureReason = null
            ..failureDetail = null;
        }
        persistMessage(g.groupIdHex, msg);
        changed++;
      }
    }
    _catchUpHistoryClose(partyHex, closed);
    if (changed > 0) {
      _saveConversations();
      onStateChanged?.call();
    }
  }

  /// The delivery layer learns that [wireIdsHex] reached [partyHex]: the
  /// open entry of each in the history with that party becomes `delivered`,
  /// so that no edge sends it again (§9.3). Only the message itself — an
  /// edit or a deletion under the same identifier stays open until its own
  /// acknowledgement comes.
  void _catchUpHistoryClose(String partyHex, Set<String> wireIdsHex) {
    final p = myceliumMailbox;
    if (p == null || wireIdsHex.isEmpty) return;
    final address = p.contactOrNull(partyHex)?.address ??
        p.groupPairOrNull(partyHex)?.address;
    if (address == null) return;
    try {
      final history = p.historyFor(address);
      for (final e in history.entries.toList()) {
        if (!e.outgoing || !e.open || e.content.isEmpty) continue;
        final proto.ApplicationFrameV3 frame;
        try {
          frame = proto.ApplicationFrameV3.fromBuffer(e.content);
        } catch (_) {
          continue;
        }
        if (!_kCatchUpMessageKinds.contains(frame.messageType)) continue;
        final idHex = bytesToHex(Uint8List.fromList(frame.messageId));
        if (!wireIdsHex.contains(idHex)) continue;
        history.stateChange(e.identifier, mycelium.DeliveryState.delivered);
        _myceliumAcknowledged.add(idHex);
      }
      while (_myceliumAcknowledged.length > _kMyceliumOutboundsMax) {
        _myceliumAcknowledged.remove(_myceliumAcknowledged.first);
      }
    } catch (e) {
      _log.warn('catch-up: history with ${partyHex.substring(0, 8)} not '
          'closed: $e');
    }
  }
}

/// The kinds of frame that ARE a message of [kCatchUpTypes] — what an entry
/// of the delivery history must carry to be closed by a catching up.
const Set<proto.MessageTypeV3> _kCatchUpMessageKinds = {
  proto.MessageTypeV3.MTV3_TEXT,
  proto.MessageTypeV3.MTV3_REPLY,
  proto.MessageTypeV3.MTV3_MEDIA_INLINE,
  proto.MessageTypeV3.MTV3_MEDIA_ANNOUNCE,
  proto.MessageTypeV3.MTV3_VOICE_MESSAGE,
};
