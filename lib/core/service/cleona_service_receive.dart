// AP-1c path (b), addendum (docs/MIGRATION_V3_TO_V4_0_MYZEL.md §4c.2i) — CLASS B.
//
// THE RECEIVE PATH OF THE APPLICATION. AP-3 does NOT delete this file, but
// rewrites it: V4 §15.5.3 hands the application a `HarvestEvent`, and
// `handleApplicationFrame` already accepts it.
//
// Why the file exists at all: until 2026-08-14 these five members lay in
// `cleona_service_v3_sf.dart`, whose header said "is deleted as a block
// in AP-3". They had landed there because they stood in the source text
// between two S&F blocks — a filing place, not a boundary of fate
// (§4c.2i, the same error class as §4c.2a).
//
// Callers of the entry: service_daemon.dart, main.dart,
// core/platform/ios_background_fetch.dart.

part of 'cleona_service.dart';

extension ReceivePathOps on CleonaService {

  // ── THE V3 RECEIVE ENTRY HAS FALLEN (CUT, 31.08.2026) ──────────
  //
  // Here stood `handleIncomingApplicationPacket(...)` and its fast path
  // `_tryLiveMediaFastPath(...)`. Both accepted a `proto.NetworkPacket`
  // — the RAW V3 frame from the wire — and did three things: inner KEM
  // decapsulation against the user KEM keys of this identity, user
  // signature check against the contact registration, and handover to
  // [handleApplicationFrame].
  //
  // WHY (T) AND NOT (G): there is no PRODUCER any more. The three callers
  // were `service_daemon.dart`, `main.dart` and
  // `ios_background_fetch.dart`, and all three called them from
  // `CleonaNode.onApplicationFramePayload` — the callback of the deleted
  // node. Re-measured on 31.08.2026: there is no further caller in `lib/`.
  //
  // THE 4.2 RECEIVE SIDE IS A DIFFERENT ONE AND IT STANDS: the mailbox of
  // `package:mycelium` opens the envelope, proves the sender and hands the
  // frame through `cleona_service_mycelium.dart` as a `HarvestEvent` into
  // [handleApplicationFrame]. The DISPATCHER below is thus unchanged in
  // operation; only this one entry is gone. (The V4.1 receive side,
  // `acceptV41Frame`, fell with `lib/core/tagline/`, S408-P23.)
  //
  // TWO THINGS WERE LOST WITH THE V3 ENTRY, named instead of concealed:
  //
  //   * `identity.previousX25519Sk`/`previousMlKemSk` — the fallback to
  //     the PREVIOUS KEM keys after a rotation. It lived only in this body.
  //     In 4.2 the post box opens with the current and the previous KEM
  //     generation (`mycelium/lib/post_box.dart`, `kemOpeners`, §4.5.4).
  //
  //   * THE LIVE MEDIA FAST PATH (§10.3 / appendix B.2). Call frames carry
  //     a PLAINTEXT inner without per-recipient KEM, because the payload
  //     is already AES-GCM-authenticated under the `call_key`. It belongs
  //     on level D (§17).
  //
  //     UNTIL S361 THIS SAID "coincides with **gap G-13**: `CallTransport`
  //     has had no implementation since the CUT" — the same error that had
  //     already been corrected in `cleona_service.dart` (`sendToUser`), but
  //     remained standing here as a duplicate. Measured false: there is an
  //     implementation, `calls/plane_d_call_transport.dart:83`
  //     `class PlaneDCallTransport implements CallTransport`, constructed in
  //     `service/call_service.dart:192`. And this fast path here is not its
  //     caller anyway: live call frames never run through the receive
  //     dispatcher of this file, but arrive directly at the `DSocket`
  //     (`call_service.dart:915` on the sending side). What remains open at
  //     level D is the §17.3 punch window (`call_service.dart:435`), listed
  //     in the gap book under G-13 (`docs/v4-redesign/S361-lueckenbuch.md`).

  /// V3 receive-side dispatcher (Architecture v3.0 §2.6, receiver step 13).
  /// Called by the node after the outer Device-Sig has been verified, the
  /// inner KEM has been decrypted, and the User-Sig has been verified. The
  /// frame is trusted at this point — this method only routes to subsystem-
  /// specific handlers.
  ///
  /// Each handler dispatches to the subsystem-specific business logic.
  ///
  /// Returns what the group gate decided (§16.2.2): the collecting device
  /// does not mirror a frame it discarded for a group this device left
  /// (§14.7 Type 21 GROUP_LEFT, `cleona_service_mycelium.dart`). A frame
  /// that returns before the gate — an unknown type, a duplicate — reads as
  /// [GroupGateVerdict.pass]: none of them is a post of a group, and the
  /// mirror only carries the post kinds anyway.
  Future<GroupGateVerdict> handleApplicationFrame({
    required HarvestEvent event,
    // `sourceAddr`/`sourcePort` have been dropped here without replacement:
    // they were read ZERO times in the body and only passed through. That
    // proves V4 §15.5.3 ("no sender address and no port") from the code.
    // The only consumer was the `wasDirect` derivation at the seam entry.
    // Finding 14: true only when the OUTER packet arrived with hopCount==0
    // from a real UDP source address (computed at packet level in
    // handleIncomingApplicationPacket). Callers without packet context
    // (First-CR infra path, S&F/erasure re-injection) keep the safe
    // default false — a receipt then never confirms a direct route.
    bool wasDirect = false,
    // §14.7 Type 18 (D-37): the frame is a contact's delivery mirrored by
    // another own device. It is shown like a received one and NOT
    // acknowledged again — the collecting device already did.
    bool mirrored = false,
  }) async {
    // A TYPE THIS BUILD DOES NOT KNOW IS DISCARDED — before dedup, receipt
    // and dispatch (S398, finding R-1). protobuf leaves an unknown enum value
    // in `unknownFields`, and `event.type` then reads `MT_TEXT`: a frame of
    // a reserved type (30/31 restore, 35-37 guardian) or of a future one
    // would be shown as a text message made of its payload and acknowledged
    // as text. Measured before this line: all three appeared in the chat
    // (`test/smoke/smoke_restore_response_scope.dart`, point 4). No receipt:
    // an application receipt confirms a message the application took.
    if (event.unknownType != null) {
      _log.warn('handleApplicationFrame: frame of unknown type '
          '${event.unknownType} from ${event.senderUserId.hex.length >= 8 ? event.senderUserId.hex.substring(0, 8) : event.senderUserId.hex} '
          '— discarded (reserved or newer than this build)');
      return GroupGateVerdict.pass;
    }

    // Receive-side dedup — the identity's memory of received DELIVERY
    // identifiers (§20.2, S403 decision 1): one slim table in the store
    // (`received_ids`, schema 4), one row per 8-byte identifier, kept
    // for as long as the identity exists — no cap, no eviction, no
    // arrival time. It replaces the capped ring this process held until
    // S403 (`_processedMessageIds`, 4 096 entries, forgotten with the
    // process): a copy of a delivery from 5 000 deliveries ago, or after
    // a restart, stays refused.
    //
    // THE DELIVERY IDENTIFIER, NOT THE app message id: mycelium draws
    // the 8 bytes per message, retries carry the same one (D-44) — the
    // duplicate IS the retry or the second route. The 16-byte
    // messageId names the MESSAGE: an edit and a deletion travel under
    // the identifier of their TARGET, and keyed on it the SECOND edit of
    // the same message would be dropped as a duplicate of the first
    // (the ring needed `delete:`/`edit:` special keys for exactly that
    // reason; the delivery identifier needs none — every delivery has
    // one of its own). `test/smoke/smoke_received_ids_app.dart` holds
    // both halves apart.
    //
    // The DELIVERY_RECEIPT is NOT suppressed. The architecture's canonical
    // receiver pipeline (§ "service.handleApplicationFrame", step [b]) reads:
    //
    //     ├─ [b] Dedup: messageId already seen?
    //     │      → if yes: send DELIVERY_RECEIPT (idempotent), then drop
    //
    // Returning early here — as this code did until 2026-07-28 — skipped the
    // receipt in step [d] and made every RUDP-Light retry structurally
    // unacknowledgeable: a lost receipt causes a retry, the retry is seen as a
    // duplicate, the duplicate is dropped without a receipt, and the sender
    // escalates to 3x timeout → Route DOWN → exponential address backoff up to
    // 5 minutes on addresses that were working the whole time. Measured on
    // node202: 346 ACK timeouts, all for a single peer, while direct UDP
    // between the two flowed in the same second.
    //
    // A duplicate is the strongest available proof that the message arrived,
    // so re-acking is both correct and cheaper than what it replaces: one
    // ~200-byte receipt instead of an unbounded retry cycle (working rule 5).
    // Deliberately NOT rate-limited — a time window would leave retries inside
    // it unacknowledged and would recreate exactly this bug.
    //
    // `deliveryId == null`: the layer below the seam has ALREADY kept this
    // identifier — mycelium marks every inbound of a sender it knows in the
    // same memory before the callback — or the caller has no delivery
    // context at all (a direct call, a replay in a guard). Nothing is
    // checked and nothing kept here then; the per-messageId dedup of
    // `_addMessageToConversation` still hides a double dispatch of one
    // message at the bubble level.
    final deliveryId = event.deliveryId;
    if (deliveryId != null) {
      final msgIdHex = event.messageId.hex;
      final msgIdShort = msgIdHex.length >= 8 ? msgIdHex.substring(0, 8) : msgIdHex;
      if (store.receivedIdKnown(deliveryId)) {
        _log.debug('handleApplicationFrame: duplicate delivery '
            '(${event.type.name}) msgId=$msgIdShort — re-acking, '
            'payload dropped');
        // Finding 1 (§8.1): a messageId whose receipt was suppressed on first
        // sight must stay unacknowledged on every replay. Without this check
        // the re-ack above silently undoes the silent-CR-drop suppression,
        // because the L1 retry carries the identical inner messageId.
        if (_suppressedReceiptMsgIds.contains(msgIdHex)) {
          _log.debug('handleApplicationFrame: duplicate of a receipt-suppressed '
              'frame msgId=$msgIdShort — NOT re-acking');
          return GroupGateVerdict.pass;
        }
        if (!mirrored &&
            isAckWorthy(event.type) &&
            event.senderUserId.isNotEmpty) {
          final senderUserId = Uint8List.fromList(event.senderUserId);
          if (!constantTimeEquals(senderUserId, identity.userId)) {
            _sendDeliveryReceipt(
              recipientUserId: senderUserId,
              messageId: Uint8List.fromList(event.messageId),
              senderDeviceId: event.senderDeviceId,
              groupId: event.groupId ?? const <int>[],
            );
          }
        }
        return GroupGateVerdict.pass;
      }
      store.receivedIdKeep(deliveryId);
    }

    // §3.1 A-2: refresh sender's known deviceNodeId on every incoming
    // ApplicationFrame so sendToUser's contact.deviceNodeIds fallback
    // stays warm without relying on DHT resolution.
    //
    // Only if the frame names a device at all (§14.1/§14.2, S349).
    // This line is the second half of the finding next to the contact
    // request path: it runs on EVERY incoming frame, so a message received
    // via V4.1 would have filled the device list of every already existing
    // contact with its own UserID — and `cleona_service_v3_legacy.dart:149`
    // would then have sent packets to this identifier. One can only "keep
    // warm" what exists.
    final senderUserHex = event.senderUserId.hex;
    final senderContact = _contacts[senderUserHex];
    final senderDevice = event.senderDeviceId;
    if (senderContact != null && senderDevice != null) {
      final senderDeviceHex = bytesToHex(senderDevice);
      if (!senderContact.deviceNodeIds.contains(senderDeviceHex)) {
        senderContact.deviceNodeIds.add(senderDeviceHex);
        _saveContacts();
      }
    }

    // §5.1 F3' — a fully verified frame proves the sender is back online.
    // (The V4.1 outbox drain on this edge, `_maybeFlushOutboxForSender`,
    // fell with `lib/core/tagline/`, S408-P23: in 4.2 the mailbox resends
    // at its own edges, §8.2.)
    shortenCrBackoffOnEdge('verified-inbound', onlyUserHex: senderUserHex);

    // A5: any verified ApplicationFrame proves contact liveness
    if (senderContact != null && senderContact.status == 'accepted') {
      senderContact.lastAckedAt = DateTime.now();
      if (senderContact.autoRepairAttempted) {
        senderContact.autoRepairAttempted = false;
      }
      // A-4: this device opened the frame with the contact's keys → `seen`.
      // Not for a copy another own device mirrored (§14.7 Type 18): that
      // device opened it, not this one.
      if (!mirrored) _markKeyMaterialUsed(senderContact);
    }

    // §16.2.2: a frame for a group this device left is discarded, one for a
    // group it does not hold yet waits for the invitation
    // (`cleona_service_group_gate.dart`). Neither reaches a handler now.
    final gate = _groupGate(event);
    // §16.2.2: in a group in announcement mode a member's post is discarded
    // (`cleona_service_group_announcement.dart`); the receipt stays as for
    // any frame the delivery layer has acknowledged.
    if (gate == GroupGateVerdict.pass && !_groupAnnouncementRefuses(event)) {
      _applicationEventDispatch(event,
          wasDirect: wasDirect, mirrored: mirrored);

      // §9.4 "Nothing overtakes a file" (S398-W5): a file arrived, or a
      // message that waited behind one — order and collection
      // (`cleona_service_file_order.dart`).
      _fileOrderReceived(event);
    }

    if (gate != GroupGateVerdict.discarded &&
        CleonaService._isUserMessage(event.type)) {
      statsCollector.addMessageReceived();
    }

    // Auto-DELIVERY_RECEIPT (Architecture §5.8 RUDP-Light): for ack-worthy
    // ApplicationFrame types, emit a receipt back to the sender's UserID
    // with the inner messageId. The sender's `_handleDeliveryReceipt`
    // upgrades the matching outgoing UiMessage from `sent` to `delivered`.
    // Skipped when:
    //   - messageId empty (sender hasn't been migrated to set inner.messageId),
    //   - senderUserId empty,
    //   - sender is ourselves (loopback / self-send won't have a contact).
    //
    // UNCHANGED FOR A FRAME THE GATE HELD BACK. The delivery layer has
    // acknowledged it by now (§9.2: "Every non-ephemeral message is
    // acknowledged by exactly one packet from the recipient" — sent by
    // mycelium for every frame it opens, before the application decides
    // anything), and this receipt says the same thing; withholding it here
    // would make the two disagree.
    if (!mirrored &&
        isAckWorthy(event.type) &&
        event.messageId.isNotEmpty &&
        event.senderUserId.isNotEmpty) {
      final senderUserId = Uint8List.fromList(event.senderUserId);
      if (!constantTimeEquals(senderUserId, identity.userId)) {
        _sendDeliveryReceipt(
          recipientUserId: senderUserId,
          messageId: Uint8List.fromList(event.messageId),
          senderDeviceId: event.senderDeviceId,
          groupId: event.groupId ?? const <int>[],
        );
      }
    }
    return gate;
  }

  /// The dispatcher: hands [event] to the handler of its kind. Called for a
  /// frame that arrives ([handleApplicationFrame]) and for one that waited
  /// for the invitation into its group (`_groupWaitingApply`, §16.2.2).
  void _applicationEventDispatch(HarvestEvent event,
      {required bool wasDirect, bool mirrored = false}) {
    switch (event.type) {
      // Messaging — Cluster C2
      case proto.MessageType.MT_TEXT:
        _handleText(event);
        break;
      case proto.MessageType.MT_MEDIA_INLINE:
        _handleMediaInline(event);
        break;
      case proto.MessageType.MT_MEDIA_ANNOUNCE:
        _handleMediaAnnounce(event);
        break;
      // Lane 2 (§17.6, S398 P3b) — `cleona_service_stream.dart`.
      case proto.MessageType.MT_MEDIA_STREAM_REQUEST:
        _streamRequestReceived(event);
        break;
      case proto.MessageType.MT_MEDIA_STREAM_OFFER:
        _streamOfferReceived(event);
        break;
      case proto.MessageType.MT_MEDIA_HOLDERS:
        _streamHoldersReceived(event);
        break;
      // §9.4 "Reasons", D-34 (S398-W1) — `cleona_service_transfer.dart`.
      case proto.MessageType.MT_MEDIA_ABORT:
        _mediaAbortReceived(event);
        break;
      // D-34's one exception (S407 A2): an image whose recipient lost the
      // pieces it kept asks once for the missing stripes —
      // `cleona_service_image_again.dart`. Any other file is refused there.
      case proto.MessageType.MT_MEDIA_REQUEST:
        _imageAgainReceived(event);
        break;
      // MT_MEDIA_CHUNK / _COMPLETE / _REJECT have no handler (S399 P2-7):
      // §9.4 knows no fetch on request, and a file is never sent again
      // (§9.3, D-34). They fall to `default` and are logged.
      case proto.MessageType.MT_REACTION:
        _handleReaction(event, mirrored: mirrored);
        break;
      // §16.2.4 — `cleona_service_channel_reactions.dart`.
      case proto.MessageType.MT_CHANNEL_REACTION_TOTALS:
        _channelReactionTotalsReceived(event);
        break;
      case proto.MessageType.MT_CHANNEL_REACTION_HANDOVER:
        _channelReactionHandoverReceived(event, mirrored);
        break;
      case proto.MessageType.MT_REPLY:
        _handleReply(event);
        break;
      case proto.MessageType.MT_EDIT:
        _handleEdit(event);
        break;
      case proto.MessageType.MT_DELETE:
        _handleDelete(event);
        break;
      case proto.MessageType.MT_VOICE_MESSAGE:
        _handleVoiceMessage(event);
        break;

      // Layer-Replies (ephemeral, ACK) — Cluster C1
      case proto.MessageType.MT_TYPING_INDICATOR:
        _handleTypingIndicator(event);
        break;
      case proto.MessageType.MT_READ_RECEIPT:
        _handleReadReceipt(event);
        break;
      case proto.MessageType.MT_DELIVERY_RECEIPT:
        _handleDeliveryReceipt(event, wasDirect: wasDirect);
        break;

      // §9.5 (D-48): catching up after more than 7 days — request, answer
      // packet or progress report of a party (`cleona_service_catch_up.dart`).
      case proto.MessageType.MT_CATCH_UP:
        _catchUpReceived(event);
        break;

      // Identity / Profile — Cluster C4. Types 30/31 (V3 restore) are
      // reserved; a frame carrying them is discarded above as an unknown
      // type (S398, finding R-1).
      case proto.MessageType.MT_IDENTITY_DELETED:
        _handleIdentityDeleted(event);
        break;
      case proto.MessageType.MT_PROFILE_UPDATE:
        _handleProfileUpdate(event);
        break;
      case proto.MessageType.MT_KEY_ROTATION_BROADCAST:
        _handleKeyRotationBroadcastEvent(event);
        break;
      case proto.MessageType.MT_KEY_ROTATION_ACK:
        _handleKeyRotationAck(event);
        break;
      case proto.MessageType.MT_ROTATION_REJECTION_ALERT:
        _handleRotationRejectionAlert(event);
        break;
      // §14.5 path 2 — the carrier without which `verifyRotationCoAuth` has
      // no denominator (`cleona_service_deviceset.dart`).
      case proto.MessageType.MT_DEVICE_SET_ANNOUNCE:
        _handleDeviceSetAnnounce(event);
        break;

      // Contact request — cluster C4. MT_CONTACT_REQUEST no longer has a
      // handler (S388-BAU-KONTAKT): the request is package (2) of first
      // contact in mycelium (§15.5), and such a frame falls into `default`
      // (§15.7 — no third path for strangers).
      case proto.MessageType.MT_CONTACT_REQUEST_RESPONSE:
        _handleContactRequestResponse(event);
        break;

      // Groups — Cluster C4
      case proto.MessageType.MT_GROUP_CREATE:
        _handleGroupCreate(event);
        break;
      case proto.MessageType.MT_GROUP_INVITE:
        _handleGroupInvite(event);
        break;
      case proto.MessageType.MT_GROUP_LEAVE:
        _handleGroupLeave(event);
        break;
      case proto.MessageType.MT_GROUP_KEY_UPDATE:
        _handleGroupKeyUpdate(event);
        break;
      case proto.MessageType.MT_GROUP_MEMBERSHIP_RESYNC_REQUEST:
        _handleGroupMembershipResyncRequest(event);
        break;
      case proto.MessageType.MT_GROUP_JOIN: // B-3, §16.2.2
        _handleGroupJoin(event);
        break;

      // Channels — Cluster C4
      case proto.MessageType.MT_CHANNEL_CREATE:
        _handleChannelCreate(event);
        break;
      case proto.MessageType.MT_CHANNEL_POST:
        _handleChannelPost(event);
        break;
      case proto.MessageType.MT_CHANNEL_INVITE:
        _handleChannelInvite(event);
        break;
      case proto.MessageType.MT_CHANNEL_LEAVE:
        _handleChannelLeave(event);
        break;
      case proto.MessageType.MT_CHANNEL_ROLE_UPDATE:
        _handleChannelRoleUpdate(event);
        break;
      // §16.2.2 — `cleona_service_channel_list.dart`.
      case proto.MessageType.MT_CHANNEL_MEMBERS_CHANGE:
        // A 4.2.3 device does not know the kind (stand-in of a probe).
        if (!channelReceiveAs423) _channelMembersChangeReceived(event);
        break;
      // §16.2.2 — `cleona_service_group_list.dart`.
      case proto.MessageType.MT_GROUP_MEMBERS_CHANGE:
        // A 4.2.3 device does not know the kind (stand-in of a probe).
        if (!channelReceiveAs423) _groupMembersChangeReceived(event);
        break;
      // §16.2.5 — `cleona_service_shared_key*.dart`. A 4.2.3 device does not
      // know the kinds (stand-ins of a probe: `channelReceiveAs423`,
      // `sharedKeyOff`).
      case proto.MessageType.MT_CAPABILITY_NOTICE:
        if (!channelReceiveAs423) _capabilityNoticeReceived(event);
        break;
      case proto.MessageType.MT_SHARED_KEY:
        if (!channelReceiveAs423) _skDeliveryReceived(event);
        break;
      case proto.MessageType.MT_SHARED_KEY_AUTHOR:
        if (!channelReceiveAs423) _skAuthorReceived(event);
        break;
      case proto.MessageType.MT_CHANNEL_BAD_BADGE_REPORT:
        _moderation.handleChannelBadBadgeReport(event);
        break;
      case proto.MessageType.MT_CHANNEL_JURY_VOTE:
        _moderation.handleChannelJuryVote(event);
        break;
      case proto.MessageType.MT_CHANNEL_MOD_DECISION:
        _moderation.handleChannelModDecision(event);
        break;
      case proto.MessageType.MT_CHANNEL_SUBSCRIBE_PROBE:
        _moderation.handleChannelSubscribeProbe(event);
        break;
      case proto.MessageType.MT_CHANNEL_JOIN_REQUEST:
        _moderation.handleChannelJoinRequestEvent(event);
        break;
      case proto.MessageType.MT_CHANNEL_REPORT:
        _moderation.handleChannelReport(event);
        break;

      // Calls — Cluster C3 (delegated to CallService)
      case proto.MessageType.MT_CALL_INVITE:
        _calls.handleCallInvite(event);
        break;
      case proto.MessageType.MT_CALL_ANSWER:
        _calls.handleCallAnswer(event);
        break;
      case proto.MessageType.MT_CALL_REJECT:
        _calls.handleCallReject(event);
        break;
      case proto.MessageType.MT_CALL_RING_ACK:
        // §17.2: only with this may the caller hear a ringback tone.
        _calls.handleCallRingAck(event);
        break;
      case proto.MessageType.MT_CALL_CANCEL_OTHERS:
        // §17.2 multi-device arbitration. Own type instead of a rider on
        // MT_CALL_REJECT — justification in `calls/call_arbitration.dart`.
        _calls.handleCallCancelOthers(event);
        break;
      case proto.MessageType.MT_CALL_HANGUP:
        _calls.handleCallHangup(event);
        break;
      case proto.MessageType.MT_CALL_MISSED:
        // §17.2: an ordinary message, not a call signal
        // (`cleona_service_missed_call.dart`).
        _missedCallReceived(event);
        break;
      case proto.MessageType.MT_ICE_CANDIDATE:
        _calls.handleIceCandidate(event);
        break;
      case proto.MessageType.MT_CALL_REJOIN:
        _calls.handleCallRejoin(event);
        break;
      case proto.MessageType.MT_CALL_AUDIO:
        _calls.handleCallAudio(event);
        break;
      case proto.MessageType.MT_CALL_VIDEO:
        _calls.handleCallVideo(event);
        break;
      case proto.MessageType.MT_CALL_KEYFRAME_REQUEST:
        _calls.onKeyframeRequested?.call();
        break;
      // §17.5 — handled here, not in CallService: the state is a report
      // about the peer that the UI reads (`peerCallMediaState`); CallService
      // decides only when OUR state changes (`onOwnVideoStateChanged`, S399).
      case proto.MessageType.MT_CALL_MEDIA_STATE:
        handleCallMediaState(event);
        break;
      case proto.MessageType.MT_CALL_GROUP_AUDIO:
        _calls.handleCallGroupAudio(event);
        break;
      case proto.MessageType.MT_CALL_GROUP_VIDEO:
        _calls.handleCallGroupVideo(event);
        break;
      case proto.MessageType.MT_CALL_GROUP_LEAVE:
        _calls.handleCallGroupLeave(event);
        break;
      // S368: MT_CALL_GROUP_KEY_ROTATE (81) has been removed — the handler
      // was a wire-compat no-op. The number is reserved in the proto; a
      // frame with it now falls into the `default` branch and is discarded.
      case proto.MessageType.MT_CALL_GROUP_SENDER_KEY:
        _calls.groupCallManager.handleGroupCallSenderKey(event);
        break;
      case proto.MessageType.MT_CALL_RTT_PING:
        _calls.handleCallRttPing(event);
        break;
      case proto.MessageType.MT_CALL_RTT_PONG:
        _calls.handleCallRttPong(event);
        break;
      case proto.MessageType.MT_CALL_TREE_UPDATE:
        _calls.handleCallTreeUpdate(event);
        break;

      // Wave 2B.3: PEER_LIST_*, DHT_*, ROUTE_UPDATE, REACHABILITY_*, HOLE_PUNCH_*
      // are §2.3.5 InfrastructureFrames handled in cleona_node.dart's
      // `_dispatchInfrastructureFrameLocal`. They never arrive as
      // ApplicationFrames on the wire — the V3 hard-cut routes them as
      // InfrastructureFrames — so cases here would be unreachable.
      //
      // FRAGMENT_* and PEER_STORE_* carry encrypted user-content and are
      // handled by service-layer Infra-hooks in service_daemon.dart
      // (handleIncomingFragmentStoreInfra etc.). They are not dispatched
      // through this ApplicationFrame switch either.

      // Chat-Config — Cluster C4
      case proto.MessageType.MT_CHAT_CONFIG_UPDATE:
        _handleChatConfigUpdate(event);
        break;
      case proto.MessageType.MT_CHAT_CONFIG_RESPONSE:
        _handleChatConfigResponse(event);
        break;

      // (ROUTE_UPDATE, REACHABILITY_*, RELAY_*, HOLE_PUNCH_* — see comment
      //  on Wave 2B.3 above; all dispatched in cleona_node.dart.)

      // Identity resolution (V3 §4.3, 2D DHT): the six kinds
      // IDENTITY_AUTH_*/IDENTITY_LIVE_* had empty handlers here and no
      // sender in `lib/`, `bin/`, `test/`, `integration_test/`, `scripts/`
      // (measured S388-BAU-KONTAKT). V4.2 has no pollable third-party
      // knowledge; such a frame falls into `default`.

      // Multi-Device — Cluster C4
      case proto.MessageType.MT_TWIN_SYNC:
        _handleTwinSync(event);
        break;
      // B-4b: the V3 pairing frames (DEVICE_PAIR_REQUEST/_APPROVE) have no
      // handler any more — a further device is enrolled over the words
      // (§14.6.1, `cleona_service_enrolment.dart`); such a frame falls into
      // `default` and is dropped.
      case proto.MessageType.MT_DEVICE_REVOCATION:
        _handleDeviceRevocation(event);
        break;

      // Calendar — Cluster C4
      case proto.MessageType.MT_CALENDAR_INVITE:
        _calendarProto.handleCalendarInvite(event);
        break;
      case proto.MessageType.MT_CALENDAR_RSVP:
        _calendarProto.handleCalendarRsvp(event);
        break;
      case proto.MessageType.MT_CALENDAR_UPDATE:
        _calendarProto.handleCalendarUpdate(event);
        break;
      case proto.MessageType.MT_CALENDAR_DELETE:
        _calendarProto.handleCalendarDelete(event);
        break;
      case proto.MessageType.MT_FREE_BUSY_REQUEST:
        _calendarProto.handleFreeBusyRequest(event);
        break;
      case proto.MessageType.MT_FREE_BUSY_RESPONSE:
        _calendarProto.handleFreeBusyResponse(event);
        break;

      // Polls — Cluster C4
      case proto.MessageType.MT_POLL_CREATE:
        _polls.handlePollCreate(event);
        break;
      case proto.MessageType.MT_POLL_VOTE:
        _polls.handlePollVote(event);
        break;
      case proto.MessageType.MT_POLL_VOTE_ANONYMOUS:
        _polls.handlePollVoteAnonymous(event);
        break;
      case proto.MessageType.MT_POLL_UPDATE:
        _polls.handlePollUpdate(event);
        break;
      case proto.MessageType.MT_POLL_SNAPSHOT:
        _polls.handlePollSnapshot(event);
        break;
      case proto.MessageType.MT_POLL_REVOKE:
        _polls.handlePollRevoke(event);
        break;

      // In-Call Collaboration (§25, planned) — cluster C3 (delegated to CallService)
      case proto.MessageType.MT_WHITEBOARD_STROKE:
        _calls.handleWhiteboardStroke(event);
        break;
      case proto.MessageType.MT_WHITEBOARD_PAGE:
        _calls.handleWhiteboardPage(event);
        break;
      case proto.MessageType.MT_FILE_EXCHANGE:
        _calls.handleFileExchange(event);
        break;
      case proto.MessageType.MT_CLIPBOARD_EXCHANGE:
        _calls.handleClipboardExchange(event);
        break;
      case proto.MessageType.MT_SCREEN_SHARE_FRAME:
        _calls.handleScreenShareFrame(event);
        break;
      case proto.MessageType.MT_CALL_CHAT:
        _calls.handleCallChat(event);
        break;
      case proto.MessageType.MT_REMOTE_CONTROL_INPUT:
        _calls.handleRemoteControlInput(event);
        break;

      default:
        _log.warn('handleApplicationFrame: unhandled type ${event.type}');
    }
  }

  /// Emit a V3 DELIVERY_RECEIPT (Architecture §5.8 RUDP-Light) for a
  /// successfully received ApplicationFrame. Fire-and-forget — receipt
  /// loss is tolerable (sender's AckTracker times out and triggers its
  /// own retry / route-down logic).
  ///
  /// [senderDeviceId] is the concrete device that sent the frame being
  /// acknowledged (from `handleApplicationFrame`'s outer packet). On a
  /// multi-device account, `sendToUser`'s user-level fan-out may otherwise
  /// pick a *different*, stale cached device of the same user — the receipt
  /// would then never reach the device whose AckTracker is actually waiting.
  /// Targeting the exact device closes that gap without any extra traffic
  /// (still exactly one receipt).
  ///
  /// `null` (or empty) means: the receive path knows no device — then the
  /// confirmation goes out identity-addressed, i.e. exactly the path that
  /// §14.2 provides anyway ("one delivery serves all devices").
  /// NO identifier is invented to fill the `targetDeviceId` field: an
  /// invented identifier would not be a faster path, but a path into the
  /// void.
  /// §14.7.4 fan-out receipt attribution: credit one member's leg of a group
  /// message and re-evaluate the aggregate status.
  ///
  /// A group message reaches a visible `delivered` only when EVERY leg is
  /// confirmed AND every member discloses. A member who withholds keeps the
  /// message at `sent` — counting their leg would leak exactly what they
  /// chose to withhold, which is why `withheldBy` blocks the aggregate rather
  /// than merely being skipped.
  void _applyFanoutReceipt(String memberUserHex, String legIdHex,
      {required bool withheld}) {
    for (final conv in conversations.values) {
      ensureAllLoaded();
      for (final msg in conv.messages) {
        if (!msg.isOutgoing) continue;
        if (msg.fanoutLegs[memberUserHex] != legIdHex) continue;
        // §9.2/D2 APPLIES PER LEG. A group fan-out sends each member its own
        // message with its own identifier (`legIdHex`) and its own `K_AB` —
        // the register therefore keeps one record per leg, and here the
        // same one is asked as in the 1:1 branch.
        //
        // NOT CREDITED AT ALL, instead of merely blocking the aggregate:
        // `deliveredBy` is itself a delivery claim — the UI shows it as
        // "delivered to N of M". Entering a leg without proof there and only
        // holding back the tick would mean treating the same unproven
        // statement differently in two places.
        //
        // NO DEAD END: if a proven receipt for the same leg comes later,
        // this path runs again and then enters it. Nor is `withheldBy`
        // maintained from an unproven frame — the lock bit of a receipt is
        // no more trustworthy than the receipt itself.
        //
        // If the register does not know the leg (V3 send path, or long
        // displaced), the previous behaviour applies as everywhere; the
        // justification is in the block header of
        // `cleona_service_msgstate.dart`.
        if (!_deliveryProven(legIdHex)) return;
        msg.deliveredBy.add(memberUserHex);
        if (withheld) {
          msg.withheldBy.add(memberUserHex);
        } else {
          msg.withheldBy.remove(memberUserHex);
        }
        // §16.2.3, §21.5.5: the display over ALL legs, by the one rule
        // (S410 finding 8) — `delivered` once every leg is receipted and none
        // withholds; otherwise the weakest leg, `failed` included. A post on
        // the shared key has the state of its placing; the method leaves it.
        _applyOutgoingLegStatus(msg, msg.fanoutLegs.values.toList());
        // §21.4.1. This place is the reason why the store is NOT supplied
        // via a `dirty` flag in `UiMessage`: `deliveredBy` and `withheldBy`
        // are changed as a COLLECTION, the field itself is never assigned.
        // A setter would see nothing here.
        persistMessage(msg.conversationId, msg);
        _saveConversations();
        onStateChanged?.call();
        return;
      }
    }
  }

  void _sendDeliveryReceipt({
    required Uint8List recipientUserId,
    required Uint8List messageId,
    Uint8List? senderDeviceId,
    List<int> groupId = const <int>[],
  }) {
    final receipt = proto.DeliveryReceipt()
      ..messageId = messageId
      ..deliveredAt = Int64(DateTime.now().millisecondsSinceEpoch)
      // §14.7.4: the receipt is emitted unconditionally — it is a transport
      // primitive of RUDP Light (its absence tears the route down). Only the
      // sender's *display* is governed, via this bit.
      ..withholdDeliveryStatus =
          _withholdsDeliveryStatusTo(recipientUserId, groupId);
    sendToUser(
      recipientUserId: recipientUserId,
      messageType: proto.MessageType.MT_DELIVERY_RECEIPT,
      payload: receipt.writeToBuffer(),
      // B-3 (§16.2.2 "the acknowledgement … of the pair"): a receipt for a
      // group leg names the group, so it can go back over a group pair.
      groupId: groupId.isEmpty ? null : Uint8List.fromList(groupId),
      targetDeviceId:
          (senderDeviceId != null && senderDeviceId.isNotEmpty)
              ? senderDeviceId
              : null,
    );
  }
}

/// The founding anchor of a counterpart (§4.3, §15.2).
extension PairKeyOps on CleonaService {
  /// The counterpart's FOUNDING pubkey, or `null`.
  ///
  /// ── ONE SOURCE, AND IT NEVER CHANGES (path A, S361) ─────────────
  ///
  /// Exclusively [ContactInfo.peerFoundingEd25519Pk] is read — a field
  /// that is set ONCE and never touched again afterwards
  /// ([ContactInfo.rememberFoundingAnchor] lets no second value in).
  ///
  /// Until S361 a preference list stood here: `ep` from the ContactSeed,
  /// otherwise `contact.ed25519Pk`. BOTH branches violated §15.2 after a
  /// rotation, just in different directions:
  ///
  ///   * `contact.ed25519Pk` carries the counterpart's RESPECTIVELY CURRENT
  ///     key — `CleonaService._setContactTrustAnchor` rewrites it on every
  ///     accepted `KEY_ROTATION_BROADCAST`. From the counterpart's first
  ///     rotation on, the "founding anchor" was thus simply its last key,
  ///     and both sides computed under different marks.
  ///   * `ep` never changes, but is the key that was current at ISSUING
  ///     TIME. For an issuer that had already rotated BEFORE issuing, it is
  ///     not its founding key; for that the seed carries its own field
  ///     `fp` (`contact_seed.dart`, passed through since S361 into the first
  ///     request; the carrier of that time,
  ///     `CleonaService.sendContactRequest`, has been dropped since
  ///     S388-BAU-KONTAKT, on V4.2 the request comes from the invitation
  ///     card, §15.5).
  ///
  /// ── THE INITIAL FILLING, AND WHY IT MAY STAND HERE ──────────────
  ///
  /// Existing contacts do not have the field. For them it is filled ONCE
  /// from what is available locally — `ep`, otherwise `ed25519Pk` —, and
  /// from then on the recorded value applies. That is no deterioration: it
  /// IS the old behaviour, only once instead of on every call. There is no
  /// other way to obtain an anchor without a network query.
  ///
  /// The value goes to disk at the next `_saveContacts()`
  /// ([ContactInfo.toJson]). It is deliberately NOT saved here: the
  /// readers (recovery bundle, media transfer) sit on paths that save
  /// themselves.
  Uint8List? peerFoundingPk(ContactInfo? contact) {
    if (contact == null) return null;
    final alreadyThere = contact.peerFoundingEd25519Pk;
    if (alreadyThere != null) return alreadyThere;

    // ── `base64.normalize` AND NOT `base64Decode` RAW (S360) ────────
    //
    // Since S361 the decoding lives in [ContactInfo.seedEpBytes], so that
    // there is exactly ONE decoder for this field. What it catches: all
    // three writers store URL-safe base64 WITHOUT padding (43 characters
    // for 32 B), `base64Decode` requires a multiple of four and throws
    // `Invalid length, must be multiple of four`. A `catch (_) {}` swallowed
    // the throw until S360, and the fallback `ed25519Pk` is empty by
    // construction at FIRST CONTACT — the key only comes with the answer.
    // The result was the silent total failure of first contact.
    final epBytes = contact.seedEpBytes;
    final ep = contact.seedEpB64;
    if (ep != null && ep.isNotEmpty && epBytes == null) {
      // NOT SILENT. An unreadable anchor means: for this counterpart there
      // is no `K_AB`, so no deposit and no harvest. That is a finding and
      // not operational noise.
      _log.warn('§15.2: `ep` of the contact not decodable — without a '
          'founding anchor there is no pair key');
    }
    if (contact.rememberFoundingAnchor(epBytes ?? contact.ed25519Pk)) {
      _log.info('§15.2: founding anchor of an existing contact recorded '
          'once (${epBytes != null ? '`ep`' : 'ed25519Pk'}) — from '
          'now on it survives every rotation of the counterpart');
    }
    return contact.peerFoundingEd25519Pk;
  }
}
