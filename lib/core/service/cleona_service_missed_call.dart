// The missed-call message (v4_2 §17.2 "Missed call", D-45; S407-CALLNORM).
//
// "Whenever a call ends without having been answered — no `RING_ACK` within
// 10 s, the caller hanging up before an answer, or 60 s of ringing without an
// `ANSWER` — the caller sends the missed-call message. It is an ordinary
// message, not a call signal: steps 1, 3 and 4, acknowledged, shown and
// mirrored like any message (§7.1, §9, §14.2). It waits in the post box for a
// callee who is off … It carries the `callId` and whether the call was audio
// or video. The callee shows it with the time its own device received it
// (§22.5.3), never with a time the caller claims. A device that rang for this
// `callId` shows one entry, not two."
//
// Ordinary means: `sendToUser` with `MT_CALL_MISSED` — not in
// `_kCallSignalTypes`, so the seam gives it the full ladder with the post box
// and the edges (§9.3) like a text. Its message id is the `callId`: every copy
// of the one message — a second route, the mirror to an own device, the
// caller's own mirror — lands on the same entry.
//
// THE GROUP CALL (S408, S407-GAMUTE open point 1, owner variant B). §17.2
// names no exception, so a group call is no exception: the initiator sends
// the message to each member whose invitation ended unanswered
// (`GroupCallManager.onMissedCall`), as a group message — to a contact, or
// over the group pair to a co-member who is none (§4.3, §16.2.2) — and the
// member shows it in the group's conversation. Each leg carries a wire
// identifier of its own (a shared one would collide in the delivery register,
// as for a group post, `sendGroupTextMessage`); the entry is the `callId` on
// both sides. The initiator keeps ONE own entry per call in the group's
// conversation, with one leg per member that missed it — its state is that
// of the weakest leg (§16.2.3), as for a group post.

part of 'cleona_service.dart';

extension CleonaServiceMissedCall on CleonaService {
  /// The one shape of a missed-call entry — own ([outgoing], not sent yet:
  /// `resting`) or received (it arrived here: `delivered`, §9.1).
  UiMessage _missedCallEntry({
    required String idHex,
    required String conversationId,
    required String senderHex,
    required bool isVideo,
    required DateTime at,
    required bool outgoing,
  }) =>
      UiMessage(
        id: idHex,
        conversationId: conversationId,
        senderNodeIdHex: senderHex,
        text: missedCallKey(isVideo: isVideo),
        timestamp: at,
        type: UiMessageType.callMissed,
        status: outgoing ? MessageStatus.resting : MessageStatus.delivered,
        isOutgoing: outgoing,
      );

  /// The own entry as it goes to the other own devices (§14.7 Type 2
  /// `MESSAGE_SENT`). A newer own device shows it as a missed call; an older
  /// one reads `text` and shows the key.
  void _missedCallMirrorOwn(UiMessage msg) {
    _sendTwinSync(
        proto.TwinSyncType.MESSAGE_SENT,
        Uint8List.fromList(utf8.encode(jsonEncode({
          'conversationId': msg.conversationId,
          'text': msg.text,
          'messageId': msg.id,
          'timestamp': msg.timestamp.millisecondsSinceEpoch,
          'type': UiMessageType.callMissed.wireValue,
        }))));
  }

  /// The caller's side: [callId] to [peerHex] ended unanswered
  /// (`CallManager.onMissedCall`). Shown in the conversation as an own entry
  /// with its delivery state, sent like a text, mirrored to the own devices
  /// (§14.7 Type 2 `MESSAGE_SENT`).
  Future<void> _missedCallSend(
      String peerHex, Uint8List callId, bool isVideo) async {
    final contact = _contacts[peerHex];
    if (contact == null || contact.isDeleted) {
      _log.debug('missed call: ${CleonaService._hexShort(hexToBytes(peerHex))} '
          'is no contact — no message');
      return;
    }
    final idHex = bytesToHex(callId);
    final msg = _missedCallEntry(
      idHex: idHex,
      conversationId: peerHex,
      senderHex: identity.userIdHex,
      isVideo: isVideo,
      at: DateTime.now(),
      outgoing: true,
    );
    if (!_addMessageToConversation(peerHex, msg)) return;
    // Index entry BEFORE sending, as for a text (`sendTextMessage`, S393).
    _applyOutgoingLegStatus(msg, <String>[idHex]);
    final payload = (proto.CallMissed()
          ..callId = callId
          ..isVideo = isVideo)
        .writeToBuffer();
    bool handed;
    try {
      handed = await sendToUser(
        recipientUserId: contact.nodeId,
        messageType: proto.MessageType.MT_CALL_MISSED,
        payload: payload,
        messageId: callId,
      );
    } catch (e) {
      _log.warn('missed call: send threw: $e');
      handed = false;
    }
    if (!handed) _seamRefused(msg, 'missedCall');
    _applyOutgoingLegStatus(msg, <String>[idHex]);
    _saveConversations();
    onStateChanged?.call();
    _log.info('missed call ${idHex.substring(0, 8)} to '
        '${CleonaService._hexShort(contact.nodeId)} handed over: $handed '
        '(§17.2: an ordinary message)');
    _missedCallMirrorOwn(msg);
  }

  /// The initiator's side of a group call: [memberHex]'s invitation to
  /// [callId] in [groupIdHex] ended unanswered (`GroupCallManager
  /// .onMissedCall`). One leg to the member, as a group message; the own
  /// entry in the group's conversation gathers the legs of this call.
  ///
  /// A group call is audio (its INVITE carries no `is_video`).
  Future<void> _missedGroupCallSend(
      String memberHex, String groupIdHex, Uint8List callId) async {
    final group = _groups[groupIdHex];
    if (group == null || !group.members.containsKey(memberHex)) {
      _log.debug('missed group call: ${memberHex.substring(0, 8)} is no '
          'member of the group — no message');
      return;
    }
    final idHex = bytesToHex(callId);
    ensureLoaded(groupIdHex);
    var msg = conversations[groupIdHex]
        ?.messages
        .where((m) => m.id == idHex && m.isOutgoing)
        .firstOrNull;
    final first = msg == null;
    if (msg == null) {
      msg = _missedCallEntry(
        idHex: idHex,
        conversationId: groupIdHex,
        senderHex: identity.userIdHex,
        isVideo: false,
        at: DateTime.now(),
        outgoing: true,
      );
      if (!_addMessageToConversation(groupIdHex, msg, isGroup: true)) return;
    }
    if (msg.fanoutLegs.containsKey(memberHex)) return;
    final legId = SodiumFFI().randomBytes(16);
    msg.fanoutLegs[memberHex] = bytesToHex(legId);
    // Index entry BEFORE sending, as for a group post.
    _applyOutgoingLegStatus(msg, msg.fanoutLegs.values.toList());
    final payload = (proto.CallMissed()
          ..callId = callId
          ..isVideo = false)
        .writeToBuffer();
    bool handed;
    try {
      handed = await sendToUser(
        recipientUserId: hexToBytes(memberHex),
        messageType: proto.MessageType.MT_CALL_MISSED,
        payload: payload,
        messageId: legId,
        groupId: hexToBytes(groupIdHex),
      );
    } catch (e) {
      _log.warn('missed group call: send threw: $e');
      handed = false;
    }
    // A leg nothing took over stays out of the aggregate, as for a group
    // post: the weakest of the legs that went is the entry's state.
    _applyOutgoingLegStatus(msg, msg.fanoutLegs.values.toList());
    persistMessage(groupIdHex, msg);
    _saveConversations();
    onStateChanged?.call();
    _log.info('missed group call ${idHex.substring(0, 8)} to '
        '${memberHex.substring(0, 8)} handed over: $handed '
        '(§17.2: an ordinary group message)');
    if (first) _missedCallMirrorOwn(msg);
  }

  /// The callee's side: `MT_CALL_MISSED` from a contact (or its mirror
  /// from an own device, §14.7 Type 18), or — naming a group — from a member
  /// of that group, contact or group pair. Shown with THIS device's arrival
  /// time (§22.5.3), once per `callId`, in the conversation of the contact or
  /// of the group.
  void _missedCallReceived(HarvestEvent event) {
    final proto.CallMissed m;
    try {
      m = proto.CallMissed.fromBuffer(event.payload);
    } catch (_) {
      _log.warn('missed call: unreadable payload — dropped');
      return;
    }
    final senderHex = event.senderUserId.hex;
    final groupHex = event.groupId?.hex;
    final group = groupHex == null ? null : _groups[groupHex];
    final admitted = groupHex == null
        ? _contacts[senderHex] != null
        : group != null &&
            group.members.containsKey(senderHex) &&
            group.members.containsKey(identity.userIdHex);
    if (!admitted) {
      _log.warn('missed call from ${senderHex.length >= 8 ? senderHex.substring(0, 8) : senderHex}: '
          '${groupHex == null ? 'not a 1:1 message of a contact' : 'not from a member of a group held here'}'
          ' — dropped');
      return;
    }
    final conversationId = groupHex ?? senderHex;
    final idHex = m.callId.length == 16
        ? bytesToHex(Uint8List.fromList(m.callId))
        : event.messageId.hex;
    final msg = _missedCallEntry(
      idHex: idHex,
      conversationId: conversationId,
      senderHex: senderHex,
      isVideo: m.isVideo,
      // §17.2: "with the time its own device received it (§22.5.3), never
      // with a time the caller claims".
      at: event.harvestedAt,
      outgoing: false,
    );
    final isNew = _addMessageToConversation(conversationId, msg,
        isGroup: group != null);
    _log.info('missed call ${idHex.substring(0, 8)} from '
        '${senderHex.substring(0, 8)}${group != null ? ' in a group' : ''}'
        '${isNew ? '' : ' (already shown)'}');
    if (!isNew ||
        _shouldSuppressNotification(
            conversationId, _claimedSendTimeMs(event))) {
      return;
    }
    notificationSound.playMessageSound(
        soundName: conversations[conversationId]?.notificationSoundName);
    notificationSound.vibrate(VibrationType.message);
    final words = notificationWords ??
        (String key) => trayTranslate(key, trayLocaleCode());
    final senderName =
        _contacts[senderHex]?.displayName ??
            group?.members[senderHex]?.displayName ??
            senderHex.substring(0, 8);
    _postAndroidNotification(
        group == null ? senderName : '$senderName · ${group.name}',
        words(msg.text),
        conversationId);
    _lastNotifiedAt[conversationId] = DateTime.now();
  }
}
