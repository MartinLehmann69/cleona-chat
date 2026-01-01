// v4_2 §9.5, §20.2, D-48 — catching up after more than 7 days: THE PARTY
// ASKED. The returning device is in `cleona_service_catch_up.dart`.
//
// §9.5 "What is sent": "The party asked sends what it wrote itself, and only
// that: its messages in that scope written or changed since 14 days before
// the named moment (§9.3), newest first, in packets of at most 32 768 B
// including the seal, at most 4 packets per round, the next round on the
// requester's progress report (§20.2); the identifiers of its messages
// deleted in that time; and the identifiers of the requester's messages it
// holds from that time. … What the party has deleted, and what has expired
// there (§21.5.3), is not sent — deleted is deleted (§13.5.2). A file is
// named by its record and not sent again (§9.4)."
//
// The scope is that of §13.5.4: the conversation of the pair and every group
// both belong to — never another conversation. A group post goes only to a
// member it was sent to (`UiMessage.fanoutLegs`: "Members are fixed at the
// moment of sending", §16.2.3), under the identifier of that member's leg —
// the one the member holds it under (§16.2).
//
// §20.2: one answer per party and named moment; a repeated or backdated
// request is discarded and named; a moment in the future is refused. The
// state of an answer — the moment, how far it was sent — lies in the
// identity's store ([kCatchUpAnswersArea]), one entry per party. No clock:
// a round goes out when the request or a progress report arrives.

part of 'cleona_service.dart';

/// The answers this identity gave or is giving, one entry per party (§20.2
/// "catching up, answers a party gives: 1 per party and named moment").
const String kCatchUpAnswersArea = 'catch_up_answers';

/// §21.5.3 (owner decision 11, F5 = C): "When a copy on the sender's device
/// expires before the message was acknowledged, the device keeps for that
/// recipient and conversation a count of such messages and nothing of their
/// content; the count is handed over when the recipient catches up (§9.5)
/// and then dropped." One entry per recipient and conversation —
/// `<recipient>:<group>`, or `<recipient>:-` for the conversation of the
/// pair — holding `{'n': count}`. Bounded by the pairs and shared groups of
/// the identity (§20.2).
const String kCatchUpExpiredArea = 'catch_up_expired';

/// The conversation part of a [kCatchUpExpiredArea] key for the conversation
/// of the pair itself.
const String kCatchUpExpiredDirect = '-';

/// One own message in the scope of a pair, as the party asking holds it.
class _CatchUpOwn {
  /// The identifier the party holds it under: the message identifier 1:1,
  /// the identifier of the party's leg in a group.
  final String idHex;

  /// The group, or `null` for the conversation of the pair.
  final String? groupHex;
  final UiMessage msg;
  const _CatchUpOwn(this.idHex, this.groupHex, this.msg);

  int get ts => msg.timestamp.millisecondsSinceEpoch;

  /// Newest first; equal moments by identifier, so that a cursor names one
  /// place in the order.
  static int order(_CatchUpOwn a, _CatchUpOwn b) {
    final t = b.ts.compareTo(a.ts);
    return t != 0 ? t : b.idHex.compareTo(a.idHex);
  }
}

extension CleonaServiceCatchUpSource on CleonaService {
  /// The answer state for [partyHex], or `null`.
  Map<String, dynamic>? _catchUpAnswer(String partyHex) {
    try {
      return store.loadAreaPrefix(kCatchUpAnswersArea, partyHex)[partyHex];
    } catch (e) {
      _log.warn('catch-up: answer state for ${partyHex.substring(0, 8)} not '
          'readable: $e');
      return null;
    }
  }

  void _catchUpAnswerWrite(String partyHex, Map<String, dynamic> state) {
    try {
      store.putEntry(kCatchUpAnswersArea, partyHex, state);
    } catch (e) {
      _log.warn('catch-up: answer state for ${partyHex.substring(0, 8)} not '
          'written: $e');
    }
  }

  /// A request from [partyHex] (§9.5). [groupHex]: the group the request
  /// names — set where the party is a group pair, and carried on every
  /// packet back so that it passes as a group type (§16.2.2).
  void _catchUpRequestReceived(
      String partyHex, String? groupHex, proto.ReconcileFetch f) {
    final short = partyHex.substring(0, 8);
    if (f.fetchId.length != 16) return;
    if (_reducedMode) {
      _log.warn('catch-up: request from $short not answered — reduced mode');
      return;
    }
    final contact = _contacts[partyHex]?.status == 'accepted';
    if (!contact && _catchUpSharedGroups(partyHex).isEmpty) {
      _log.warn('catch-up: request from $short — neither a contact nor a '
          'member of a shared group. Discarded.');
      return;
    }
    final fetch = bytesToHex(Uint8List.fromList(f.fetchId));
    final since = f.sinceMs.toInt() < 0 ? 0 : f.sinceMs.toInt();
    final now = catchUpClock().millisecondsSinceEpoch;
    if (since > now) {
      _log.warn('catch-up: request from $short names a moment in the future '
          '— refused (§9.5 "Bounds")');
      return;
    }
    final before = _catchUpAnswer(partyHex);
    if (before != null) {
      final was = before['since'] as int? ?? 0;
      if (before['fetch'] == fetch) {
        _log.warn('catch-up: request from $short repeated — discarded '
            '(§20.2: one answer per party and named moment)');
        return;
      }
      if (since < was) {
        _log.warn('catch-up: request from $short backdated (names an '
            'earlier moment than the one answered) — discarded (§20.2)');
        return;
      }
      if (since == was && before['confirmed'] == true) {
        _log.warn('catch-up: request from $short for a moment that is '
            'answered — discarded (§20.2)');
        return;
      }
      // The same moment under a new request while the earlier answer was
      // never reported complete: that answer did not arrive, and the
      // requester kept its earlier moment (§20.2). It is answered anew.
    }
    final state = <String, dynamic>{
      'fetch': fetch,
      'since': since,
      'next': 0,
      'sent': false,
      'confirmed': false,
      if (!contact && groupHex != null) 'group': groupHex,
    };
    _catchUpAnswerRound(partyHex, state, first: true);
  }

  /// Sends ONE round of the answer to [partyHex] — at most
  /// [kReconcileWindow] packets — and writes how far it got.
  void _catchUpAnswerRound(String partyHex, Map<String, dynamic> state,
      {required bool first}) {
    final short = partyHex.substring(0, 8);
    final fetch = state['fetch'] as String;
    final since = state['since'] as int;
    final low = since - kCatchUpLookBack.inMilliseconds;
    final own = _catchUpOwnMessages(partyHex, low);
    final cursorTs = state['cursorTs'] as int?;
    final cursorId = state['cursorId'] as String?;
    final pending = cursorTs == null || cursorId == null
        ? own
        : [
            for (final o in own)
              if (o.ts < cursorTs ||
                  (o.ts == cursorTs && o.idHex.compareTo(cursorId) < 0))
                o
          ];
    final lists = first ? _catchUpLists(partyHex, low) : null;
    if (first &&
        pending.isEmpty &&
        lists!.held.isEmpty &&
        lists.deleted.isEmpty &&
        lists.expired.isEmpty) {
      // Nothing written, nothing held, nothing deleted: no packet. The
      // moment counts as answered all the same (§20.2).
      _catchUpAnswerWrite(
          partyHex, {...state, 'sent': true, 'confirmed': true});
      _log.event('catch-up: request from $short — nothing to send since '
          '14 days before its moment. No packet.');
      return;
    }
    final batch = pending.take(kCatchUpRoundRecordsAtMost).toList();
    final round = catchUpAnswerRound(
      fetchId: hexToBytes(fetch),
      firstSeq: state['next'] as int? ?? 0,
      records: [for (final o in batch) _catchUpRecord(o)],
      more: pending.length > batch.length,
      lists: lists,
    );
    final groupHex = state['group'] as String?;
    // The counts this answer hands over (§21.5.3) — dropped once the
    // requester reports the packet that carries them.
    final handed = <String, int>{
      for (final e in lists?.expired ?? const <proto.ReconcileExpired>[])
        '$partyHex:${e.convId.isEmpty ? kCatchUpExpiredDirect : bytesToHex(Uint8List.fromList(e.convId))}':
            e.count,
    };
    final payloads = [for (final frame in round.frames) reconcileEncode(frame)];
    for (final payload in payloads) {
      _detachedSend(
          'MTV3_CATCH_UP answer',
          sendToUser(
            recipientUserId: hexToBytes(partyHex),
            messageType: proto.MessageTypeV3.MTV3_CATCH_UP,
            payload: payload,
            groupId: groupHex == null ? null : hexToBytes(groupHex),
          ));
    }
    final last = round.consumed > 0 ? batch[round.consumed - 1] : null;
    _catchUpAnswerWrite(partyHex, {
      ...state,
      'next': (state['next'] as int? ?? 0) + round.frames.length,
      if (last != null) 'cursorTs': last.ts,
      if (last != null) 'cursorId': last.idHex,
      'sent': round.complete,
      'confirmed': false,
      if (handed.isNotEmpty) 'expired': handed,
    });
    if (round.skipped.isNotEmpty) {
      _log.warn('catch-up: ${round.skipped.length} message(s) to $short fit '
          'no packet — named to it, not sent (§20.2)');
    }
    if (round.heldLeftOut > 0) {
      _log.warn('catch-up: ${round.heldLeftOut} identifier(s) of messages '
          'held from $short left out — the list did not fit its packet');
    }
    _log.event('catch-up: answer to $short — ${round.frames.length} '
        'packet(s) of ${[for (final p in payloads) p.length]} B before the '
        'seal, with ${round.consumed - round.skipped.length} message(s)'
        '${first ? ', ${lists!.held.length} held, ${lists.deleted.length} deleted, ${lists.expired.length} count(s) of expired messages' : ''}'
        '${round.complete ? ' — complete' : ' — the next round waits for its progress report'}');
  }

  /// The requester's progress report (§9.5, §20.2): the messages it names
  /// become `delivered`; if it has every packet sent so far, the next round
  /// goes out — or the answer is confirmed complete.
  void _catchUpProgressReceived(String partyHex, proto.ReconcileProgress p) {
    final short = partyHex.substring(0, 8);
    final state = _catchUpAnswer(partyHex);
    if (state == null ||
        state['fetch'] != bytesToHex(Uint8List.fromList(p.fetchId))) {
      _log.warn('catch-up: progress report from $short for an answer this '
          'device is not giving — discarded');
      return;
    }
    _catchUpMarkOwnDelivered(partyHex, [
      for (final id in p.delivered.take(kReconcileFetchIdsAtMost))
        if (id.length == 16) bytesToHex(Uint8List.fromList(id))
    ]);
    final next = state['next'] as int? ?? 0;
    if (p.received == 0 || p.received != next) return; // not the last round's
    if (state['confirmed'] == true) return;
    // The first packet is among those reported: the counts of expired
    // messages it carried are handed over — dropped here (§21.5.3).
    final settled = _catchUpExpiredDrop(state);
    if (settled['sent'] == true) {
      _catchUpAnswerWrite(partyHex, {...settled, 'confirmed': true});
      _log.event('catch-up: $short reports the answer complete');
      return;
    }
    if (_reducedMode) {
      _catchUpAnswerWrite(partyHex, settled);
      return;
    }
    _catchUpAnswerRound(partyHex, settled, first: false);
  }

  // ── Expired before it was acknowledged (§21.5.3, F5 = C) ──────────────

  /// The own copy of [msg] in [conv] expires now. For every recipient that
  /// has not acknowledged it, the count of such messages for that recipient
  /// and conversation goes up by one — the number, nothing of the content.
  /// 1:1 the contact; in a group every member a leg went to that is not
  /// among `deliveredBy`. Channels carry no acknowledgement and no count.
  ///
  /// Called from the expiry sweep (`_checkMessageExpiry`) and nowhere else:
  /// a message the user deletes is named as deleted, not counted.
  void _catchUpExpiredCount(Conversation conv, UiMessage msg) {
    if (!msg.isOutgoing || !kCatchUpTypes.contains(msg.type)) return;
    final recipients = <String>[];
    final String part;
    if (_groups.containsKey(conv.id)) {
      part = conv.id;
      recipients.addAll([
        for (final member in msg.fanoutLegs.keys)
          if (!msg.deliveredBy.contains(member)) member
      ]);
    } else if (_contacts.containsKey(conv.id)) {
      part = kCatchUpExpiredDirect;
      if (msg.status != MessageStatus.delivered) recipients.add(conv.id);
    } else {
      return;
    }
    for (final recipient in recipients) {
      final key = '$recipient:$part';
      try {
        final n =
            store.loadAreaPrefix(kCatchUpExpiredArea, key)[key]?['n'] as int?;
        store.putEntry(kCatchUpExpiredArea, key, {'n': (n ?? 0) + 1});
      } catch (e) {
        _log.warn('catch-up: count of expired messages for '
            '${recipient.substring(0, 8)} not written: $e');
      }
    }
  }

  /// The counts for [partyHex] an answer hands over: per conversation of the
  /// pair's scope the number of own messages that expired here before the
  /// party acknowledged them. A count for a conversation the pair no longer
  /// shares is not named.
  List<proto.ReconcileExpired> _catchUpExpiredFor(String partyHex) {
    final out = <proto.ReconcileExpired>[];
    final Map<String, Map<String, dynamic>> counts;
    try {
      counts = store.loadAreaPrefix(kCatchUpExpiredArea, '$partyHex:');
    } catch (e) {
      _log.warn('catch-up: counts of expired messages not readable: $e');
      return out;
    }
    for (final e in counts.entries) {
      final n = e.value['n'];
      if (n is! int || n <= 0) continue;
      final part = e.key.substring(partyHex.length + 1);
      final direct = part == kCatchUpExpiredDirect;
      final convId = direct ? const <int>[] : hexToBytes(part);
      if (_catchUpScope(partyHex, convId) == null) continue;
      final entry = proto.ReconcileExpired()..count = n;
      if (!direct) entry.convId = convId;
      out.add(entry);
      if (out.length >= kCatchUpExpiredAtMost) break;
    }
    return out;
  }

  /// The counts [state] handed over are subtracted — a message that expired
  /// since the answer left stays counted for the next one. Returns [state]
  /// without them.
  Map<String, dynamic> _catchUpExpiredDrop(Map<String, dynamic> state) {
    final handed = state['expired'];
    if (handed is! Map) return state;
    for (final e in handed.entries) {
      final key = e.key as String;
      try {
        final n =
            store.loadAreaPrefix(kCatchUpExpiredArea, key)[key]?['n'] as int?;
        final left = (n ?? 0) - (e.value as int);
        if (left > 0) {
          store.putEntry(kCatchUpExpiredArea, key, {'n': left});
        } else {
          store.removeEntry(kCatchUpExpiredArea, key);
        }
      } catch (err) {
        _log.warn('catch-up: handed-over count not dropped: $err');
      }
    }
    return {...state}..remove('expired');
  }

  /// The own messages in the scope of the pair with [partyHex], written or
  /// changed since [lowMs], newest first — and nothing from before the pair
  /// or the membership existed (§9.5 "Bounds").
  List<_CatchUpOwn> _catchUpOwnMessages(String partyHex, int lowMs) {
    final out = <_CatchUpOwn>[];
    bool since(UiMessage m, int low) =>
        m.timestamp.millisecondsSinceEpoch >= low ||
        (m.editedAt?.millisecondsSinceEpoch ?? 0) >= low;
    final contact = _contacts[partyHex];
    final direct = conversations[partyHex];
    if (contact != null && contact.status == 'accepted' && direct != null) {
      final from = contact.acceptedAt?.millisecondsSinceEpoch ?? 0;
      final low = from > lowMs ? from : lowMs;
      ensureLoaded(partyHex);
      for (final m in direct.messages) {
        if (m.isOutgoing && kCatchUpTypes.contains(m.type) && since(m, low)) {
          out.add(_CatchUpOwn(m.id, null, m));
        }
      }
    }
    for (final g in _catchUpSharedGroups(partyHex)) {
      final conv = conversations[g.groupIdHex];
      if (conv == null) continue;
      ensureLoaded(g.groupIdHex);
      for (final m in conv.messages) {
        // Without a leg the party was no member when the post was sent.
        final leg = m.fanoutLegs[partyHex];
        if (m.isOutgoing &&
            leg != null &&
            kCatchUpTypes.contains(m.type) &&
            since(m, lowMs)) {
          out.add(_CatchUpOwn(leg, g.groupIdHex, m));
        }
      }
    }
    return out..sort(_CatchUpOwn.order);
  }

  /// [o] as a record of the answer: the columns of the message and its rarer
  /// fields — nothing of this device's view of it (state, read marks, legs,
  /// the path of a file).
  proto.ReconcileMessage _catchUpRecord(_CatchUpOwn o) {
    final m = o.msg;
    final quoted = m.replyToMessageId;
    final extra = <String, dynamic>{
      if (m.editedAt != null) 'editedAt': m.editedAt!.millisecondsSinceEpoch,
      if (m.forwardedFrom != null) 'forwardedFrom': m.forwardedFrom,
      if (o.groupHex != null && m.postId != null) 'postId': m.postId,
      if (quoted != null && quoted.isNotEmpty)
        // §16.2: the identifier a quote names on the wire.
        'replyToMessageId':
            _referenceIdOf(o.groupHex ?? m.conversationId, quoted),
      if (m.replyToText != null) 'replyToText': m.replyToText,
      if (m.linkPreviewUrl != null) 'linkPreviewUrl': m.linkPreviewUrl,
      if (m.linkPreviewTitle != null) 'linkPreviewTitle': m.linkPreviewTitle,
      if (m.linkPreviewDescription != null)
        'linkPreviewDescription': m.linkPreviewDescription,
      if (m.linkPreviewSiteName != null)
        'linkPreviewSiteName': m.linkPreviewSiteName,
      if (m.linkPreviewThumbnailBase64 != null)
        'linkPreviewThumbnailBase64': m.linkPreviewThumbnailBase64,
      if (m.transcriptText != null) 'transcriptText': m.transcriptText,
      if (m.transcriptLanguage != null)
        'transcriptLanguage': m.transcriptLanguage,
      // §9.4, D-34: the record of a file — name, kind, size — never the file.
      if (m.mimeType != null) 'mimeType': m.mimeType,
      if (m.filename != null) 'filename': m.filename,
      if (m.fileSize != null) 'fileSize': m.fileSize,
    };
    final r = proto.ReconcileMessage()
      ..id = hexToBytes(o.idHex)
      ..tsMs = Int64(o.ts)
      ..type = m.type.wireValue
      ..text = m.text;
    if (o.groupHex != null) r.convId = hexToBytes(o.groupHex!);
    if (extra.isNotEmpty) r.extraJson = utf8.encode(jsonEncode(extra));
    return r;
  }

  /// The lists of the answer's first packet (§9.5): the identifiers of the
  /// requester's messages this device holds from that time — only where it
  /// discloses its delivery state (§16.2.3) — and the identifiers of own
  /// messages the user deleted in that time, as the requester holds them.
  proto.ReconcileDeliver _catchUpLists(String partyHex, int lowMs) {
    final party = hexToBytes(partyHex);
    final held = <({int ts, String id})>[];
    void from(String convId, List<int> groupId) {
      final conv = conversations[convId];
      if (conv == null || _withholdsDeliveryStatusTo(party, groupId)) return;
      ensureLoaded(convId);
      for (final m in conv.messages) {
        final ts = m.timestamp.millisecondsSinceEpoch;
        if (!m.isOutgoing &&
            m.senderNodeIdHex == partyHex &&
            kCatchUpTypes.contains(m.type) &&
            ts >= lowMs) {
          held.add((ts: ts, id: m.id));
        }
      }
    }

    if (_contacts[partyHex]?.status == 'accepted') from(partyHex, const []);
    for (final g in _catchUpSharedGroups(partyHex)) {
      from(g.groupIdHex, hexToBytes(g.groupIdHex));
    }
    held.sort((a, b) => b.ts.compareTo(a.ts));
    if (held.length > kCatchUpHeldAtMost) {
      _log.warn('catch-up: ${held.length - kCatchUpHeldAtMost} of '
          '${held.length} messages held from ${partyHex.substring(0, 8)} are '
          'not named — more than $kCatchUpHeldAtMost (§20.2)');
    }
    _ensureDeletionMarksLoaded();
    final deleted = <({int at, String id})>[
      for (final mark in _deletionMarks.values)
        if (mark.atMs >= lowMs && mark.held?[partyHex] != null)
          (at: mark.atMs, id: mark.held![partyHex]!),
    ]..sort((a, b) => b.at.compareTo(a.at));
    if (deleted.length > kCatchUpDeletedAtMost) {
      _log.warn('catch-up: ${deleted.length - kCatchUpDeletedAtMost} of '
          '${deleted.length} deletions are not named to '
          '${partyHex.substring(0, 8)} — more than $kCatchUpDeletedAtMost '
          '(§20.2)');
    }
    return proto.ReconcileDeliver()
      ..held.addAll(
          [for (final h in held.take(kCatchUpHeldAtMost)) hexToBytes(h.id)])
      ..deleted.addAll([
        for (final d in deleted.take(kCatchUpDeletedAtMost)) hexToBytes(d.id)
      ])
      ..expired.addAll(_catchUpExpiredFor(partyHex));
  }
}
