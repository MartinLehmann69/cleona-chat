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

extension V3ReceivePathOps on CleonaService {

  // ── THE V3 RECEIVE ENTRY HAS FALLEN (CUT, 31.08.2026) ──────────
  //
  // Here stood `handleIncomingApplicationPacket(...)` and its fast path
  // `_tryLiveMediaFastPath(...)`. Both accepted a `proto.NetworkPacketV3`
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
  // THE V4.1 RECEIVE SIDE IS A DIFFERENT ONE AND IT STANDS: `V41Host.accept`
  // -> `MessageSealer.open` -> `Aggregate.unpack` ->
  // [acceptV41Frame] (further down in this file) -> the V4.1 cells come
  // as `HarvestEvent` into [handleApplicationFrame]. The DISPATCHER below
  // is thus unchanged in operation; only this one entry is gone.
  //
  // TWO THINGS ARE LOST IN THE PROCESS, named instead of concealed:
  //
  //   * `identity.previousX25519Sk`/`previousMlKemSk` — the fallback to
  //     the PREVIOUS KEM keys after a rotation. It lived only in this body.
  //
  //     ADDED ON 02.09.2026 (S362), AND TWO THINGS HERE WERE WRONG.
  //     First the deadline: it no longer stands at 7 days, but at 32
  //     (`IdentityContext.previousKeyRetention`, the bracket from §4.5.4
  //     for the 31-day class). Second the sentence
  //     "`MessageSealer.open` decapsulates against the pair key": that is
  //     not true. `MessageOpener.open` decapsulates against
  //     `ownMlKemSecret()`, i.e. very much against the user KEM keys; the
  //     pair key `K_AB` carries the MARK, not the seal. The fallback was
  //     therefore very much needed — since S362 it is built in
  //     `tagline/message_seal.dart`
  //     (`previousX25519Secret`/`previousMlKemSecret`, wired in
  //     `tagline/v41_attach.dart`). As long as it was missing, a
  //     management cell was openable for 3.5 instead of 31 days on
  //     average, and the loss was silent.
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
  //     implementation, `calls/call_transport_v41.dart:83`
  //     `class CallTransportV41 implements CallTransport`, constructed in
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
  Future<void> handleApplicationFrame({
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
  }) async {

    // Receive-side dedup (Architecture §5.8 RUDP-Light): suppress the PAYLOAD
    // of duplicate frames. The same logical message can arrive via Direct +
    // Reed-Solomon reassembly + S&F mutual peer; without dedup the user sees
    // the message thrice.
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
    // Inner.messageId is set by `sendToUser` (16-byte UUID v4); empty
    // messageIds fall through (transitional path until all senders are
    // wired — receipt-emit just won't happen for those).
    if (event.messageId.isNotEmpty) {
      final msgIdHex = event.messageId.hex;
      if (_processedMessageIds.contains(msgIdHex)) {
        _log.debug('handleApplicationFrame: duplicate ${event.type.name} '
            'msgId=${msgIdHex.substring(0, 8)} — re-acking, payload dropped');
        // Finding 1 (§8.1): a messageId whose receipt was suppressed on first
        // sight must stay unacknowledged on every replay. Without this check
        // the re-ack above silently undoes the silent-CR-drop suppression,
        // because the L1 retry carries the identical inner messageId.
        if (_suppressedReceiptMsgIds.contains(msgIdHex)) {
          _log.debug('handleApplicationFrame: duplicate of a receipt-suppressed '
              'frame msgId=${msgIdHex.substring(0, 8)} — NOT re-acking');
          return;
        }
        if (isAckWorthyV3(event.type) &&
            event.senderUserId.isNotEmpty) {
          final senderUserId = Uint8List.fromList(event.senderUserId);
          if (!constantTimeEquals(senderUserId, identity.userId)) {
            _sendDeliveryReceiptV3(
              recipientUserId: senderUserId,
              messageId: Uint8List.fromList(event.messageId),
              senderDeviceId: event.senderDeviceId,
              groupId: event.groupId ?? const <int>[],
            );
          }
        }
        return;
      }
      _processedMessageIds.add(msgIdHex);
      while (_processedMessageIds.length > CleonaService._processedMessageIdsCap) {
        _processedMessageIds.remove(_processedMessageIds.first);
      }
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

    // §5.1 F3′ (fourth outbox edge): this frame is fully verified, so the
    // sender is provably back online. If we hold parked outbox entries FOR
    // this user, flush them user-scoped now — the recipient reappearing is
    // the one case the sender-side edges (network-change, first-peer,
    // endpoint-confirmed) cannot see.
    _maybeFlushOutboxForSender(senderUserHex);
    // §5.1 F3' — the same edge for the First-CR, but called SEPARATELY:
    // _maybeFlushOutboxForSender exits early if no outbox entries are
    // parked for this sender (:7595) — and for a First-CR there are none by
    // construction. A hook inside the function would therefore be
    // unreachable in exactly the relevant case.
    shortenCrBackoffOnEdge('verified-inbound', onlyUserHex: senderUserHex);

    // A5: any verified ApplicationFrame proves contact liveness
    if (senderContact != null && senderContact.status == 'accepted') {
      senderContact.lastAckedAt = DateTime.now();
      _staleWarningWrittenFor.remove(senderUserHex);
      if (senderContact.autoRepairAttempted) {
        senderContact.autoRepairAttempted = false;
      }
    }

    switch (event.type) {
      // Messaging — Cluster C2
      case proto.MessageTypeV3.MTV3_TEXT:
        _handleTextV3(event);
        break;
      case proto.MessageTypeV3.MTV3_MEDIA_INLINE:
        _handleMediaInlineV3(event);
        break;
      case proto.MessageTypeV3.MTV3_MEDIA_ANNOUNCE:
        _handleMediaAnnounceV3(event);
        break;
      case proto.MessageTypeV3.MTV3_MEDIA_REQUEST:
        // Fire-and-forget: chunk-stream may take a while; the dispatch loop
        // mustn't block on it.
        unawaited(_handleMediaRequestV3(event));
        break;
      case proto.MessageTypeV3.MTV3_MEDIA_CHUNK:
        _handleMediaChunkV3(event);
        break;
      case proto.MessageTypeV3.MTV3_MEDIA_COMPLETE:
        _handleMediaCompleteV3(event);
        break;
      case proto.MessageTypeV3.MTV3_MEDIA_REJECT:
        _handleMediaRejectV3(event);
        break;
      case proto.MessageTypeV3.MTV3_REACTION:
        _handleReactionV3(event);
        break;
      case proto.MessageTypeV3.MTV3_REPLY:
        _handleReplyV3(event);
        break;
      case proto.MessageTypeV3.MTV3_EDIT:
        _handleEditV3(event);
        break;
      case proto.MessageTypeV3.MTV3_DELETE:
        _handleDeleteV3(event);
        break;
      case proto.MessageTypeV3.MTV3_VOICE_MESSAGE:
        _handleVoiceMessageV3(event);
        break;

      // Layer-Replies (ephemeral, ACK) — Cluster C1
      case proto.MessageTypeV3.MTV3_TYPING_INDICATOR:
        _handleTypingIndicatorV3(event);
        break;
      case proto.MessageTypeV3.MTV3_READ_RECEIPT:
        _handleReadReceiptV3(event);
        break;
      case proto.MessageTypeV3.MTV3_DELIVERY_RECEIPT:
        _handleDeliveryReceiptV3(event, wasDirect: wasDirect);
        break;

      // Recovery / Identity / Profile — Cluster C4
      case proto.MessageTypeV3.MTV3_RESTORE_BROADCAST:
        _handleRestoreBroadcastV3(event);
        break;
      case proto.MessageTypeV3.MTV3_RESTORE_RESPONSE:
        _handleRestoreResponseV3(event);
        break;
      case proto.MessageTypeV3.MTV3_IDENTITY_DELETED:
        _handleIdentityDeletedV3(event);
        break;
      case proto.MessageTypeV3.MTV3_PROFILE_UPDATE:
        _handleProfileUpdateV3(event);
        break;
      case proto.MessageTypeV3.MTV3_KEY_ROTATION_BROADCAST:
        _handleKeyRotationBroadcastV3(event);
        break;
      case proto.MessageTypeV3.MTV3_KEY_ROTATION_ACK:
        _handleKeyRotationAckV3(event);
        break;
      case proto.MessageTypeV3.MTV3_ROTATION_REJECTION_ALERT:
        _handleRotationRejectionAlertV3(event);
        break;
      // §14.5 path 2 — the carrier without which `verifyRotationCoAuth` has
      // no denominator (`cleona_service_deviceset.dart`).
      case proto.MessageTypeV3.MTV3_DEVICE_SET_ANNOUNCE:
        _handleDeviceSetAnnounceV3(event);
        break;

      // Contact request — cluster C4. MTV3_CONTACT_REQUEST no longer has a
      // handler (S388-BAU-KONTAKT): the request is package (2) of first
      // contact in mycelium (§15.5), and such a frame falls into `default`
      // (§15.7 — no third path for strangers).
      case proto.MessageTypeV3.MTV3_CONTACT_REQUEST_RESPONSE:
        _handleContactRequestResponseV3(event);
        break;

      // Groups — Cluster C4
      case proto.MessageTypeV3.MTV3_GROUP_CREATE:
        _handleGroupCreateV3(event);
        break;
      case proto.MessageTypeV3.MTV3_GROUP_INVITE:
        _handleGroupInviteV3(event);
        break;
      case proto.MessageTypeV3.MTV3_GROUP_LEAVE:
        _handleGroupLeaveV3(event);
        break;
      case proto.MessageTypeV3.MTV3_GROUP_KEY_UPDATE:
        _handleGroupKeyUpdateV3(event);
        break;
      case proto.MessageTypeV3.MTV3_GROUP_MEMBERSHIP_RESYNC_REQUEST:
        _handleGroupMembershipResyncRequest(event);
        break;

      // Channels — Cluster C4
      case proto.MessageTypeV3.MTV3_CHANNEL_CREATE:
        _handleChannelCreateV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CHANNEL_POST:
        _handleChannelPostV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CHANNEL_INVITE:
        _handleChannelInviteV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CHANNEL_LEAVE:
        _handleChannelLeaveV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CHANNEL_ROLE_UPDATE:
        _handleChannelRoleUpdateV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CHANNEL_BAD_BADGE_REPORT:
        _moderation.handleChannelBadBadgeReportV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CHANNEL_JURY_VOTE:
        _moderation.handleChannelJuryVoteV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CHANNEL_MOD_DECISION:
        _moderation.handleChannelModDecisionV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CHANNEL_SUBSCRIBE_PROBE:
        _moderation.handleChannelSubscribeProbeV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CHANNEL_JOIN_REQUEST:
        _moderation.handleChannelJoinRequestV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CHANNEL_REPORT:
        _moderation.handleChannelReportV3(event);
        break;

      // Calls — Cluster C3 (delegated to CallService)
      case proto.MessageTypeV3.MTV3_CALL_INVITE:
        _calls.handleCallInviteV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CALL_ANSWER:
        _calls.handleCallAnswerV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CALL_REJECT:
        _calls.handleCallRejectV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CALL_RING_ACK:
        // §17.2: only with this may the caller hear a ringback tone.
        _calls.handleCallRingAckV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CALL_CANCEL_OTHERS:
        // §17.2 multi-device arbitration. Own type instead of a rider on
        // MTV3_CALL_REJECT — justification in `calls/call_arbitration.dart`.
        _calls.handleCallCancelOthersV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CALL_HANGUP:
        _calls.handleCallHangupV3(event);
        break;
      case proto.MessageTypeV3.MTV3_ICE_CANDIDATE:
        _calls.handleIceCandidateV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CALL_REJOIN:
        _calls.handleCallRejoinV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CALL_AUDIO:
        _calls.handleCallAudioV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CALL_VIDEO:
        _calls.handleCallVideoV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CALL_KEYFRAME_REQUEST:
        _calls.onKeyframeRequested?.call();
        break;
      // §10.6 / V1.12 — handled here, not in CallService: the state is a
      // protocol fact about the peer, and CallService (V2.1) is not touched
      // during wave 1 of the audio/video rebuild.
      case proto.MessageTypeV3.MTV3_CALL_MEDIA_STATE:
        handleCallMediaStateV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CALL_GROUP_AUDIO:
        _calls.handleCallGroupAudioV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CALL_GROUP_VIDEO:
        _calls.handleCallGroupVideoV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CALL_GROUP_LEAVE:
        _calls.handleCallGroupLeaveV3(event);
        break;
      // S368: MTV3_CALL_GROUP_KEY_ROTATE (81) has been removed — the handler
      // was a wire-compat no-op. The number is reserved in the proto; a
      // frame with it now falls into the `default` branch and is discarded.
      case proto.MessageTypeV3.MTV3_CALL_GROUP_SENDER_KEY:
        _calls.groupCallManager.handleGroupCallSenderKeyV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CALL_RTT_PING:
        _calls.handleCallRttPingV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CALL_RTT_PONG:
        _calls.handleCallRttPongV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CALL_TREE_UPDATE:
        _calls.handleCallTreeUpdateV3(event);
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
      case proto.MessageTypeV3.MTV3_CHAT_CONFIG_UPDATE:
        _handleChatConfigUpdateV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CHAT_CONFIG_RESPONSE:
        _handleChatConfigResponseV3(event);
        break;

      // (ROUTE_UPDATE, REACHABILITY_*, RELAY_*, HOLE_PUNCH_* — see comment
      //  on Wave 2B.3 above; all dispatched in cleona_node.dart.)

      // Identity resolution (V3 §4.3, 2D DHT): the six kinds
      // IDENTITY_AUTH_*/IDENTITY_LIVE_* had empty handlers here and no
      // sender in `lib/`, `bin/`, `test/`, `integration_test/`, `scripts/`
      // (measured S388-BAU-KONTAKT). V4.2 has no pollable third-party
      // knowledge; such a frame falls into `default`.

      // Multi-Device — Cluster C4
      case proto.MessageTypeV3.MTV3_TWIN_SYNC:
        _handleTwinSyncV3(event);
        break;
      case proto.MessageTypeV3.MTV3_DEVICE_PAIR_REQUEST:
        _handleDevicePairRequestV3(event);
        break;
      case proto.MessageTypeV3.MTV3_DEVICE_PAIR_APPROVE:
        _handleDevicePairApproveV3(event);
        break;
      case proto.MessageTypeV3.MTV3_DEVICE_REVOCATION:
        _handleDeviceRevocationV3(event);
        break;

      // Calendar — Cluster C4
      case proto.MessageTypeV3.MTV3_CALENDAR_INVITE:
        _calendarProto.handleCalendarInviteV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CALENDAR_RSVP:
        _calendarProto.handleCalendarRsvpV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CALENDAR_UPDATE:
        _calendarProto.handleCalendarUpdateV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CALENDAR_DELETE:
        _calendarProto.handleCalendarDeleteV3(event);
        break;
      case proto.MessageTypeV3.MTV3_FREE_BUSY_REQUEST:
        _calendarProto.handleFreeBusyRequestV3(event);
        break;
      case proto.MessageTypeV3.MTV3_FREE_BUSY_RESPONSE:
        _calendarProto.handleFreeBusyResponseV3(event);
        break;

      // Polls — Cluster C4
      case proto.MessageTypeV3.MTV3_POLL_CREATE:
        _polls.handlePollCreateV3(event);
        break;
      case proto.MessageTypeV3.MTV3_POLL_VOTE:
        _polls.handlePollVoteV3(event);
        break;
      case proto.MessageTypeV3.MTV3_POLL_VOTE_ANONYMOUS:
        _polls.handlePollVoteAnonymousV3(event);
        break;
      case proto.MessageTypeV3.MTV3_POLL_UPDATE:
        _polls.handlePollUpdateV3(event);
        break;
      case proto.MessageTypeV3.MTV3_POLL_SNAPSHOT:
        _polls.handlePollSnapshotV3(event);
        break;
      case proto.MessageTypeV3.MTV3_POLL_REVOKE:
        _polls.handlePollRevokeV3(event);
        break;

      // In-Call Collaboration (§25, planned) — cluster C3 (delegated to CallService)
      case proto.MessageTypeV3.MTV3_WHITEBOARD_STROKE:
        _calls.handleWhiteboardStrokeV3(event);
        break;
      case proto.MessageTypeV3.MTV3_WHITEBOARD_PAGE:
        _calls.handleWhiteboardPageV3(event);
        break;
      case proto.MessageTypeV3.MTV3_FILE_EXCHANGE:
        _calls.handleFileExchangeV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CLIPBOARD_EXCHANGE:
        _calls.handleClipboardExchangeV3(event);
        break;
      case proto.MessageTypeV3.MTV3_SCREEN_SHARE_FRAME:
        _calls.handleScreenShareFrameV3(event);
        break;
      case proto.MessageTypeV3.MTV3_CALL_CHAT:
        _calls.handleCallChatV3(event);
        break;
      case proto.MessageTypeV3.MTV3_REMOTE_CONTROL_INPUT:
        _calls.handleRemoteControlInputV3(event);
        break;

      default:
        _log.warn('handleApplicationFrame: unhandled type ${event.type}');
    }

    if (CleonaService._isUserMessage(event.type)) {
      statsCollector.addMessageReceived();
    }

    // Auto-DELIVERY_RECEIPT (Architecture §5.8 RUDP-Light): for ack-worthy
    // ApplicationFrame types, emit a receipt back to the sender's UserID
    // with the inner messageId. The sender's `_handleDeliveryReceiptV3`
    // upgrades the matching outgoing UiMessage from `sent` to `delivered`.
    // Skipped when:
    //   - messageId empty (sender hasn't been migrated to set inner.messageId),
    //   - senderUserId empty,
    //   - sender is ourselves (loopback / self-send won't have a contact).
    if (isAckWorthyV3(event.type) &&
        event.messageId.isNotEmpty &&
        event.senderUserId.isNotEmpty) {
      final senderUserId = Uint8List.fromList(event.senderUserId);
      if (!constantTimeEquals(senderUserId, identity.userId)) {
        _sendDeliveryReceiptV3(
          recipientUserId: senderUserId,
          messageId: Uint8List.fromList(event.messageId),
          senderDeviceId: event.senderDeviceId,
          groupId: event.groupId ?? const <int>[],
        );
      }
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
        if (!_v41DeliveryProven(legIdHex)) return;
        msg.deliveredBy.add(memberUserHex);
        if (withheld) {
          msg.withheldBy.add(memberUserHex);
        } else {
          msg.withheldBy.remove(memberUserHex);
        }
        if (msg.isFullyDelivered &&
            msg.status.canTransitionTo(MessageStatus.delivered)) {
          msg.status = MessageStatus.delivered;
        }
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

  void _sendDeliveryReceiptV3({
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
      messageType: proto.MessageTypeV3.MTV3_DELIVERY_RECEIPT,
      payload: receipt.writeToBuffer(),
      targetDeviceId:
          (senderDeviceId != null && senderDeviceId.isNotEmpty)
              ? senderDeviceId
              : null,
    );
  }
}

/// The receive path of the V4.1 delivery layer (S349).
///
/// WHY THIS EXTENSION EXISTS. Until S349 V4.1 ended one step before the
/// application: `V41Host.accept()`, `MessageOpener` and
/// `Aggregate.unpack` together had ZERO callers in `lib/`, and a cell
/// delivered to this node was counted in `DeliveryNode` as
/// `CellRole.mine` and dropped. The send path was wired, the receive path
/// not — the same error class that this migration has already hit eight
/// times (built in the lab, never entered in the application).
///
/// WHAT DOES NOT HAPPEN HERE, and that should be said openly: the V4.1
/// cell carries no device identity. §7 (multi-device) hangs in V3 on a
/// `senderDeviceId` from the outer packet; that does not exist here,
/// because the delivery layer addresses identities and not devices.
///
/// UNTIL S349 THE USERID STOOD HERE — as "the only identifier there is".
/// That was wrong, and measurably so: `senderDeviceId` wanders in the
/// contact request path into `ContactInfo.deviceNodeIds`, and this set is
/// not a note but a ROUTING TARGET — `cleona_service_v3_legacy
/// .dart:149` calls `node.sendToDeviceTracked` for every entry. Every
/// request received via V4.1 thus polluted the contact's device list with
/// its identity identifier, and the V3 send path afterwards routed to an
/// identifier that no node keeps.
///
/// Now `null` stands there, and the type system forces every reader to
/// handle the case. That is the honest information: this path knows no
/// device (§14.1 "subject, not a signpost"; §14.2 "the delivery path has
/// no device level"). What a device NEEDS — §7.1 pairing, §7.5
/// co-authorization — keeps running only via V3 frames until §7 is
/// brought over, and on this path is discarded with a named reason,
/// instead of working on an invented identifier.
extension V41ReceivePathOps on CleonaService {
  /// Accepts an unsealed, reassembled V4.1 frame.
  ///
  /// ── TWO SENDER STATEMENTS, NO SIGNATURE (§4.4.3, S352) ─────────
  ///
  /// [mac] is the sender MAC over [frameBytes] under the pair key `K_AB`
  /// (`v41SenderMac`). It is the LOAD-BEARING proof of whom the frame
  /// comes from: the sealing only proves that someone sealed against the
  /// public keys of THIS identity, and those are public. Without the check
  /// every V4.1 frame would be an identity spoof (B-20).
  ///
  /// [peer] is the pair identifier from the TAGLINE — in the secure path
  /// `<own64>/<foreign64>`, in the speed path empty, because there is no
  /// field tag there (§4.3: "in Speed-Mode there is **no field tag** — the
  /// cell is addressed by the onion path"). Where it is present, it is an
  /// INDEPENDENT second statement: the cell lay under
  /// `secureTag(K_AB, …)`, and this tag cannot be computed without `K_AB`.
  /// Both must say the same.
  ///
  /// **Why no signature any more.** §4.4.3 lists "1:1 message" and
  /// "Group leg (pairwise)" with **none** and justifies it: "the tag
  /// `HKDF(K_AB, …)` authenticates the sender symmetrically … —
  /// non-repudiation is deliberately given up (deniability)". Until S352
  /// an Ed25519 check stood here, and the receiver thus held a proof,
  /// passable to third parties, of who said what — exactly what the
  /// protocol does not want to issue.
  /// On the invitation path [peer] is empty, because the mark derives from
  /// `K_inv(i)` and proves no person (`v41_attach.dart`). The ASSIGNMENT to
  /// the invitation (`inviteLine`) travelled along until S388; its only
  /// consumer was `_handleContactRequestV3` (S388-BAU-KONTAKT).
  Future<void> acceptV41Frame({
    required String peer,
    required Uint8List mac,
    required Uint8List frameBytes,
  }) async {
    final proto.ApplicationFrameV3 frame;
    try {
      frame = proto.ApplicationFrameV3.fromBuffer(frameBytes);
    } catch (_) {
      // Silent (E-83): a malformed frame carries no information.
      return;
    }

    // Addressed to US? The sealing has already answered that — but held
    // twice, as in the V3 path: a frame naming a different recipient
    // identifier is either an error or an attempt.
    final recipient = Uint8List.fromList(frame.recipientUserId);
    if (!constantTimeEquals(recipient, identity.userId)) {
      _log.warn('V4.1 drop: frame names recipient '
          '${bytesToHex(recipient).substring(0, 8)}, opened by '
          '${identity.userIdHex.substring(0, 8)}');
      return;
    }

    final sender = Uint8List.fromList(frame.senderUserId);
    final senderHex = bytesToHex(sender);

    // ── THE SENDER CHECK (§4.4.3) ────────────────────────────────
    //
    // The rule itself stands in `verifyV41Sender` (`v41_host.dart`) — in
    // ONE place, and it also says there why it evaluates two independent
    // statements. Here only what it needs is obtained, and what follows
    // from its verdict is decided.
    //
    // `K_AB` comes from the same derivation that the sending side uses too
    // (`v41PairKeyFor`, §15.2 founding keys). It throws when no founding
    // key is available — that is the situation at FIRST CONTACT and not an
    // error, hence caught here and not logged.
    final contact = _contacts[senderHex];
    Uint8List? kAb;
    // The identifier of the own device line — needed as MAC root AND as
    // check value in `verifyV41Sender`. It is formed once, so that the two
    // uses cannot drift apart.
    String? ownDeviceLine;
    if (isDevicePeer(peer)) {
      // ── THE DEVICE LINE (§14.1, §14.7) ────────────────────────────
      //
      // Here lies what differs PER DEVICE: the key package (kind 16), the
      // initial sync (§14.6.3) and the delivery of delegated keys. The MAC
      // key is the root of THIS line, not `K_own` and not `K_AB`.
      //
      // DERIVED FOR THE OWN DEVICE, not for the one named in the
      // identifier. Both would be computable here — all own devices have
      // `K_own`, and every device root follows from it. Precisely for that
      // reason the derivation must be bound to THIS device: only then does
      // a frame that lay on a sibling's line fail in `verifyV41Sender`,
      // instead of being silently opened here with the matching key.
      try {
        final kOwn = deriveKOwn(
          userX25519Secret: identity.x25519SecretKey,
          userMlKemSecret: identity.mlKemSecretKey,
        );
        ownDeviceLine =
            deviceLineKey(identity.userId, identity.deviceNodeId);
        kAb = deriveKDevice(
            kOwn: kOwn, deviceNodeId: identity.deviceNodeId);
      } catch (e) {
        _log.warn('V4.1: frame on the device line, but no '
            'device root can be built ($e)');
        kAb = null;
      }
    } else if (isOwnPeer(peer)) {
      // ── THE TWIN SYNC (§14.7, G-14) ──────────────────────
      //
      // On the own line the MAC key is `K_own`, not `K_AB`: there is no
      // counterpart, and `v41PairKeyFor` would need two founding keys.
      // `verifyV41Sender` additionally checks that the frame really names
      // the own identifier as sender — a frame on this line with a foreign
      // name fails there.
      //
      // DERIVED, NOT READ FROM THE REGISTRY. The registry belongs to the
      // node and carries the lines of ALL identities of the process; here
      // the receiver's is needed, and the receiver is fixed by the check
      // above. Looking it up via the identifier would be the same value on
      // a longer path — and a path on which a second identity of the same
      // process could be inserted.
      try {
        kAb = deriveKOwn(
          userX25519Secret: identity.x25519SecretKey,
          userMlKemSecret: identity.mlKemSecretKey,
        );
      } catch (e) {
        _log.warn('V4.1: twin frame, but no K_own can be built ($e)');
        kAb = null;
      }
    } else {
      try {
        kAb = v41PairKeyFor(sender, contact);
      } on StateError {
        kAb = null;
      }
    }

    final verdict = verifyV41Sender(
      peer: peer,
      ownUserIdHex: identity.userIdHex,
      senderUserIdHex: senderHex,
      kAb: kAb,
      mac: mac,
      frame: frameBytes,
      ownDeviceLine: ownDeviceLine,
    );
    // `skippedBootstrap` is the precise term and not a makeshift: the MAC
    // was not checked because we cannot form the sender's pair key yet.
    // `_trustFromV3` maps this correctly to `SenderTrust.unknownKey`, and
    // the handlers decide whether they may do something with it.
    var trust = OuterSigStatus.skippedBootstrap;
    switch (verdict) {
      case V41SenderVerdict.forged:
        _log.warn('V4.1 drop: sender ${senderHex.substring(0, 8)} '
            'not proven '
            '${peer.isEmpty ? '(MAC)' : '(MAC/Taglinie ${shortPairLabel(peer)})'}'
            ' — discarded, not downgraded');
        return;
      case V41SenderVerdict.verified:
        trust = OuterSigStatus.verified;
      case V41SenderVerdict.unverifiable:
        break;
    }

    // THE PROOF FOR THE DAY CAPSULE. A delivery confirmation is the proof
    // that the counterpart REALLY opened one of our messages — i.e.
    // possesses our day capsule. Until this proof is present, every message
    // carries it along again (1088 B), so that its loss does not make the
    // rest of the day unopenable.
    if (frame.messageType == proto.MessageTypeV3.MTV3_DELIVERY_RECEIPT) {
      // THE SAME IDENTIFIER UNDER WHICH THE SENDING SIDE ASKS.
      // `carriesCapsule` looks up `_v41PeerKey` — `<own64>/<foreign64>`, 129
      // characters —, until S351 the bare sender identifier with 64
      // characters stood here. The two strings can never meet, so the proof
      // NEVER took hold and every message kept carrying the capsule
      // (1088 B): 6 instead of 3 cells, permanently, regardless of the
      // delivery situation.
      //
      // The reason is the same as with B-31 (S349): the pair registry sits
      // node-wide, which is why the identifier had to include the own
      // identity. This one caller was not pulled along at the time.
      // ONLY IF THE RECEIPT MEANS ONE OF OUR V4.1 FRAMES (30.08.).
      // Here the call stood unconditionally — and a receipt proves delivery,
      // not the opening of a seal: it also comes for messages that were
      // delivered via the V3 path. Measured in the field: a receipt at
      // 11:41:53 switched off the capsule, although our first V4.1 send of
      // the run only went out at 11:47:10. After that every secure message
      // in this direction was unopenable until UTC midnight. The
      // justification with proof stands at `_v41ReceiptProvesCapsule`.
      if (_v41ReceiptProvesCapsule(frame.payload,
          verified: verdict == V41SenderVerdict.verified)) {
        v41Host?.sealer
            .confirmCapsuleReceived(_v41PeerKey(sender), DateTime.now());
      }

      // AND THE DELIVERY STATUS (§9.2, D2) — HERE, NOT IN THE HANDLER.
      //
      // The verdict about `K_AB` exists only at this place. It stands in
      // `verdict` (above, from `verifyV41Sender`), and the way from here to
      // the handler leads through `HarvestEvent` — a structure whose field
      // list is explicitly "measured, not designed" and which has no
      // carrier for "came via V4.1, MAC under `K_AB` checked".
      // `outerSigStatus` does NOT suffice as a substitute: the V3 path sets
      // `verified` there too, but means the device signature and not the
      // pair key. And taking `senderDeviceId == null` as a distinguishing
      // feature would be a guess about the transport path at a place where
      // a security decision is made.
      //
      // That is why the verdict is booked where it is proven. The handler
      // afterwards only reads the record.
      _v41NoteReceipt(frame.payload,
          verified: verdict == V41SenderVerdict.verified);
    }

    // ── WHOEVER WRITES GETS AN ANSWER — SO A ROUTE IS NEEDED ───
    //
    // The second trigger for §6/E-E, and in the field the more important
    // one. Every accepted frame is followed by an answer of this layer: the
    // delivery receipt ALWAYS goes out (§21.5.4 — even with display lock,
    // it is a transport primitive), read confirmation and typing indicator
    // come on top.
    //
    // Without a speed route each of these receipts cost `m x R` cells.
    // Measured on 29.08. what comes of that: the V3 layer repeated a
    // message sixteen times, the receiver acknowledged every duplicate, and
    // every receipt booked 30 control frames against a retry clock that
    // runs in seconds — queue permanently at ~110/120, 441 discarded
    // frames, among them real deposits. With a route the same receipt costs
    // one cell.
    //
    // HERE, NOT IN THE SEND PATH OF THE RECEIPT: the request itself needs a
    // slot and its answer another one. Whoever only asks when the receipt
    // is already finished will certainly not have the route yet when they
    // need it. Asked at reception, it runs while the application
    // processes the frame.
    //
    // APPLIES TO GROUPS TOO: `sender` is the member who wrote, and the
    // answer goes pairwise to exactly this one (§16.2).
    try {
      v41Delivery?.prepareSpeed(_v41PeerKey(sender));
    } catch (e) {
      _log.debug('prepareSpeed after receive failed: $e');
    }

    _log.event('V4.1 RECEIVE ${frame.messageType.name} from '
        '${senderHex.substring(0, 8)} '
        '(${frameBytes.length} B, '
        '${kAb == null ? 'MAC not checkable' : 'MAC checked'}'
        '${peer.isEmpty ? ', speed' : ', tagline confirmed'})');

    await handleApplicationFrame(
      event: HarvestEvent.fromV3Frame(
        frame: frame,
        // See class header: the delivery layer addresses identities, not
        // devices. `null` is the information here, not the gap.
        senderDeviceId: null,
        snapshot: SenderIdentitySnapshot(
          // `SenderIdentitySnapshot.senderDeviceId` is explicitly the
          // "wire-level senderDeviceId from `NetworkPacketV3`" — a V3
          // packet field that does not exist on this path. Outside this
          // construction it has NO reader (recounted over `lib/`: the class
          // sets it, nobody reads it).
          //
          // Since S351 `null` stands here instead of `Uint8List(0)`: the
          // field is now optional. An empty field looks like a value; `null`
          // says what is meant — no packet, no device (§14.2). This place
          // thus carries the same statement as the `senderDeviceId: null`
          // one line above, instead of formally contradicting it.
          senderDeviceId: null,
          senderUserId: sender,
          outerSigStatus: trust,
          verifiedDeviceEd25519Pk: null,
          verifiedDeviceMlDsaPk: null,
          newKeyDetectedForSenderUser: false,
          receivedAt: DateTime.now(),
        ),
      ),
      // NEVER `wasDirect`. A V4.1 cell has come via at least two relays
      // (speed) or was harvested from a deposit (secure) — in both cases
      // there is no direct route that a reception confirmation could
      // confirm.
      wasDirect: false,
    );
  }
}

/// The ONE place at which `K_AB` is formed (§15.2).
extension V41PairKeyOps on CleonaService {
  /// `K_AB` for a counterpart — from the founding keys.
  ///
  /// §15.2: "`K_AB` has exactly one source: the founding keys of both
  /// sides." That is not a question of style. Derived from the CURRENT
  /// keys, `K_AB` diverges on every rotation and delivery fails silently —
  /// and at FIRST CONTACT it cannot be formed at all, because the requester
  /// does not have the counterpart's user X25519 yet (only its device KEM
  /// from the ContactSeed). Measured in the field on 28.08.: B deposited
  /// the contact answer, A never harvested, because A could not form a
  /// pair key.
  ///
  /// **WHERE THE COUNTERPART'S FOUNDING KEY COMES FROM:** from
  /// [ContactInfo.peerFoundingEd25519Pk], the anchor recorded once. See
  /// [v41PeerFoundingPk] — it also says there why the preference list that
  /// used to stand here (`ep`, otherwise `ed25519Pk`) broke both times.
  ///
  /// **THE OPEN LIMIT, named instead of hidden (path A, S361):** the own
  /// founding secret is recomputed from the HD wallet
  /// ([IdentityContext.foundingEd25519SecretKey]) instead of stored. For an
  /// identity WITHOUT an HD wallet (created legacy; linked device without
  /// seed, §7.1.1) this recomputation does not exist — it stays on the
  /// current key and thus on the old behaviour. That is no deterioration,
  /// but no improvement either, and it is logged instead of silently
  /// accepted.
  Uint8List v41PairKeyFor(Uint8List recipientUserId, ContactInfo? contact) {
    final peerFounding = v41PeerFoundingPk(contact);
    if (peerFounding != null) {
      return deriveDeliveryPairKeyFromFounding(
        // §15.2 LITERALLY: "the founding keys of BOTH sides". Until S361
        // `identity.ed25519SecretKey` stood here — the CURRENT one. After an
        // own rotation the own side of the derivation thus changed, while
        // the counterpart kept computing against the founding pubkey: two
        // different marks, no delivery, and after the 14-day cap of the
        // transition window (§14.4) permanently. The warning that stood here
        // even said so — and let the wrong derivation run anyway.
        //
        // [IdentityContext.foundingEd25519SecretKey] recomputes the founding
        // secret from the HD wallet and CHECKS that it belongs to the
        // founding pubkey; without an HD wallet it falls back to the current
        // key and says so in the log.
        ownEd25519Secret: identity.foundingEd25519SecretKey,
        peerEd25519Public: peerFounding,
      );
    }
    // No founding key available: that must not silently lead to a
    // DIFFERENT key, otherwise both sides talk under different marks and
    // nobody sees why.
    throw StateError('K_AB cannot be built for '
        '${bytesToHex(recipientUserId).substring(0, 8)} — neither ContactSeed ep '
        'nor Ed25519 of the contact is present (§15.2)');
  }

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
  /// ([ContactInfo.toJson]). It is deliberately NOT saved here: this
  /// function itself hangs on the save path via [primeV41Pairs], a save
  /// from here would run in a circle.
  ///
  /// OWN FUNCTION, BECAUSE TWO THINGS HANG ON IT. `K_AB` and the outbound
  /// direction must come from THE SAME anchor (§15.2). Two resolutions
  /// side by side could deviate, and the deviation would be silent: the
  /// mark would match, the direction would not, and both sides would only
  /// see "harvested: 0".
  Uint8List? v41PeerFoundingPk(ContactInfo? contact) {
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

  /// Under which direction this node DEPOSITS to [recipientUserId].
  ///
  /// ── WHY NO LONGER VIA THE USER IDS (S353) ──────────────────────
  ///
  /// Until S353 `outboundDirection` compared `identity.userId` with the
  /// counterpart's stored identifier. Both are UserIDs, and V4.1 has
  /// re-minted every UserID (§4.1: the derivation reads the public domain
  /// constant instead of a network secret). On 29.08. in the field:
  /// `0d1c821d` -> `10b3cc3f`, `2708863c` -> `f64b2c3b`, `K_AB` unchanged
  /// both times. After a re-minting each side compares its NEW identifier
  /// with the counterpart's OLD, stored one — two different pairs, and the
  /// invariant "exactly one side deposits under direction 0" only holds by
  /// chance.
  ///
  /// The founding key survives every re-minting and every rotation (§4.1)
  /// and is the same anchor from which `K_AB` follows.
  ///
  /// THROWS LIKE `v41PairKeyFor`, and for the same reason: a silent
  /// substitute direction would let both sides talk under different marks.
  int v41OutDirectionFor(Uint8List recipientUserId, ContactInfo? contact) {
    final peerFounding = v41PeerFoundingPk(contact);
    if (peerFounding == null) {
      throw StateError('Direction cannot be built for '
          '${bytesToHex(recipientUserId).substring(0, 8)} — neither '
          'ContactSeed ep nor Ed25519 of the contact is present (§15.2)');
    }
    return outboundDirection(
      ownFoundingEd25519Pk: identity.foundingEd25519Pk,
      peerFoundingEd25519Pk: peerFounding,
    );
  }
}

/// The harvest needs all pair keys, not only those of the ones sent to.
extension V41PrimeOps on CleonaService {
  /// Registers the pair key for EVERY known contact.
  ///
  /// ── WHY THIS HAS TO BE (B-23, S349) ────────────────────────────────
  ///
  /// `harvestTick` runs over `pairs.peers`. Until S349 this set was filled
  /// at exactly two places — in the body of `sendToUser` and when sending
  /// a contact request. Both presuppose that this node ITSELF sends
  /// something. It followed that:
  ///
  ///   * A node that only receives never harvests. It is reachable,
  ///     connected, ready — and still collects nothing.
  ///   * After every restart reception is dead until the user writes of
  ///     their own accord. `pairs` lives only in memory; a restart deletes
  ///     every pair key.
  ///
  /// Measured in the field on 28.08.: A sent a text ("V4.1 SENDEN
  /// MTV3_TEXT … angenommen (6 Beine)"), B harvested 19 times in the same
  /// time and opened nothing — after its restart B no longer had a pair
  /// key for A and therefore asked for marks that nobody deposited.
  ///
  /// The restoration is possible because `K_AB` comes from the FOUNDING
  /// KEYS (§15.2): they stand in the contact record and survive the
  /// restart. From the volatile current keys it would not be.
  ///
  /// Returns how many pairs were registered.
  int primeV41Pairs() {
    final v41 = v41Delivery;
    if (v41 == null) return 0;
    // ── THE OWN LINE FIRST (§14.7, gap G-14) ─────────────────
    //
    // It hangs on no contact and must therefore stand before the loop: an
    // identity without a single contact still has twins. And it must run
    // on EVERY call, not only the first — `K_own` derives from the user KEM
    // secrets, and those rotate when a device is locked out (§14.4).
    v41ArmOwnLine?.call();
    var n = 0;
    var withoutAnchor = 0;
    for (final entry in _contacts.entries) {
      final c = entry.value;
      // INCREMENTAL, so that the call stays cheap on every contact save.
      // `_saveContacts()` has 43 callers; computing over all contacts would,
      // with 200 contacts, be one key derivation per contact and save. A
      // pair already registered does not change — `K_AB` hangs on the
      // FOUNDING keys (§15.2), not on the current key state.
      if (_v41Primed.contains(entry.key)) continue;
      // `pending_outgoing` too: there the ANSWER to a contact request is
      // waiting, and it lies on a tagline that nobody harvests without a
      // pair key (§15.2 step 1).
      if (c.status == 'blocked') continue;
      try {
        // THE SAME identifier as in the send path — otherwise the one path
        // registers the pair key under "identity/peer" and the other under
        // "peer", and the harvest asks past the deposit (B-31).
        v41.rememberPeer(_v41PeerKey(c.nodeId), v41PairKeyFor(c.nodeId, c),
            outDirection: v41OutDirectionFor(c.nodeId, c));
        _v41Primed.add(entry.key);
        n++;
      } catch (_) {
        // No founding key available — this contact can NOT harvest. Do NOT
        // enter into `_v41Primed`: if the contact gets its anchor later
        // (contact request, AuthManifest, rotation), the next call from
        // `_saveContacts()` takes hold.
        withoutAnchor++;
      }
    }
    if (n > 0) {
      _log.info('V4.1: $n pair keys registered — the harvest runs '
          'from now on for all contacts, not only for those to whom this '
          'node itself has written');
    }
    // ── THE SILENCE THAT MADE AN IDENTITY DEAF ON 30.08. ─────────
    //
    // Here stood only `catch (_) {}` with the justification that
    // complaining about all contacts would be noise. That is true per
    // contact — but not for the case that NOT A SINGLE contact has an
    // anchor: then this identity harvests for nobody, and the harvest loop
    // skips it silently as well (`v41_node.dart`, `kAb == null`).
    //
    // In the field: the second identity of a node ("AllyCat") reported no
    // pair keys at all on attach, while the first reported two.
    // `Ernte fuer` stood at 0 for it all day, against 499 for the first. It
    // only became reachable when it sent ITSELF — `sendToUser` registers the
    // pair along the way. Exactly that is what this call was meant to
    // prevent (B-23).
    if (n == 0 && withoutAnchor > 0) {
      _log.warn('V4.1: NO pair key registered — $withoutAnchor '
          'contact(s) without founding anchor (§15.2). This identity cannot '
          'harvest for them and stays deaf to incoming messages '
          'until the anchor is present.');
    } else if (withoutAnchor > 0) {
      _log.info('V4.1: $withoutAnchor contact(s) without founding anchor '
          'skipped — no harvesting for them');
    }
    return n;
  }

  /// Arms the INVITATION LINES of this identity (§15.3.2).
  ///
  /// ── WHAT IS MISSING WITHOUT THIS CALL ────────────────────────────────────
  ///
  /// The other side of the first request (until S388: `sendContactRequest`;
  /// on V4.2 it comes about when redeeming an invitation card, §15.5, and
  /// goes out via `sendToUser`, §22.5). The requester deposits its request
  /// under `σ(i,e)` — a mark that follows solely from `K_inv(i)`. The
  /// issuer only finds it if it queries the same mark, and the harvest
  /// runs (like everything in this layer) via `pairs.peers`. Without this
  /// call the invitation is a promise that nobody redeems: the requester
  /// deposits correctly, the issuer never harvests, and **both sides see
  /// only silence** — the same error class as B-23 one method further up.
  ///
  /// ── THREE THINGS THAT MUST BE EXACTLY LIKE THIS HERE ──────────────────────
  ///
  /// **1. The direction is the ISSUER's.** It registers itself with
  /// [kInviteIssuerDirection] = 1, so that `inDirectionFor` makes 0 of it
  /// — the direction under which the requester deposits. Registered with
  /// 0, it would harvest its own, empty opposite direction; that is B-22 in
  /// pure form.
  ///
  /// **2. `secure: true`, otherwise the invitation is a presence oracle.**
  /// The node publishes a liveness for every pair under
  /// `livenessTag(kAb, …)`, unless it is set to secure
  /// (`v41_node.dart`, `_secureOnly`). `kAb` here is `K_inv(i)`, and that is
  /// public for the class "published" (§15.3.1). Every holder of a posting
  /// could otherwise query when this node was last alive. §15.4 forbids
  /// exactly that.
  ///
  /// **3. The standing seal secret must go into the opener.** The contact
  /// request carries no day capsule — its `ss_pq` is derived from
  /// `K_inv(i)` (§15.4). `MessageOpener` only finds it via
  /// [MessageOpener.rememberStandingSecret]; without that the cell would
  /// arrive, reassemble and die in the seal.
  ///
  /// ── WHICH INVITATIONS, AND WHY NOT THE OPEN ONES ─────────────────
  ///
  /// `InviteLedger.harvestedAt`, not `openAt`. §15.3.3 separates the two:
  /// a revoked or expired invitation is no longer HANDED OUT, but its
  /// harvest window is still running — otherwise the request deposited
  /// shortly before the revocation would be lost. Whoever took `openAt`
  /// here would throw away exactly these requests.
  int armV41InviteLines() {
    final v41 = v41Delivery;
    final opener = v41Host?.opener;
    if (v41 == null || opener == null) return 0;

    final InviteLedger book;
    try {
      book = inviteLedger;
    } catch (e) {
      // `inviteLedger` throws if the ledger is there and unreadable (see
      // there). That must not kill the start, but it is a finding: this
      // identity accepts no first contacts.
      _log.error('§15.3: invitation book not readable ($e) — NO '
          'invitation line is armed, incoming contact requests are '
          'not harvested.');
      return 0;
    }

    final now = DateTime.now();
    var withoutKey = 0;
    final desired = <String, Uint8List>{};
    for (final rec in book.harvestedAt(now)) {
      final kInv = inviteKeyFor(rec);
      if (kInv == null) {
        // Old profile without HD derivation: `inviteKeyFor` already says so
        // with a line of its own. Only counted here, not repeated.
        withoutKey++;
        continue;
      }
      desired[invitePeerLabel(kInv)] = kInv;
    }

    // ── FIRST COMPARE, THEN TOUCH ──────────────────────────────
    //
    // BECAUSE OTHERWISE THE CLOCK MAKES IT DEAF. This method is called
    // periodically (§15.3.3: an expired invitation must LOSE its line,
    // otherwise it stays a write right into the inbox until the next
    // restart). `forgetPeer` also deletes `_harvestMemo` in the process —
    // the have-list with which the node distinguishes what it has already
    // harvested (B-32). Applied unconditionally, every tick would fetch
    // anew from storage everything it already had, and m=3 times.
    //
    // The comparison via the IDENTIFIERS suffices, because the identifier
    // is a function of the key (`invitePeerLabel`): the same set of
    // identifiers means the same set of keys.
    final unchanged = desired.length == _v41InviteLines.length &&
        _v41InviteLines.every(desired.containsKey);
    if (unchanged) return _v41InviteLines.length;

    for (final old in _v41InviteLines) {
      v41.forgetPeer(old);
    }
    _v41InviteLines.clear();
    opener.clearStandingSecrets();

    var n = 0;
    for (final e in desired.entries) {
      v41.rememberPeer(e.key, e.value, outDirection: kInviteIssuerDirection);
      v41.setChatMode(e.key, secure: true);
      opener.rememberStandingSecret(inviteSealSecret(e.value));
      _v41InviteLines.add(e.key);
      n++;
    }
    if (n > 0) {
      _log.info('§15.3.2: $n invitation line(s) armed — incoming '
          'contact requests are harvested from now on '
          '(${opener.standingSecrets} standing seal secrets)');
    }
    if (withoutKey > 0) {
      _log.warn('§15.3.1: $withoutKey invitation(s) without `K_inv(i)` — '
          'no request can arrive on them');
    }
    if (opener.standingRefused > 0) {
      _log.warn('§15.3.2: ${opener.standingRefused} invitation secret(s) '
          'rejected (cap ${MessageOpener.maxStandingSecrets}) — that '
          'many invitations are NOT harvestable. §15.3.2 caps the '
          'simultaneously open ones at 10; more stand in the harvest window here.');
    }
    return n;
  }

  /// The invitation behind an invitation identifier (§15.3.3).
  ///
  /// ── WHY RECALCULATED AND NOT LOOKED UP ────────────────────
  ///
  /// `_v41InviteLines` keeps the same identifiers, so it could carry a
  /// table identifier -> record along. It would be a SECOND truth about
  /// the same thing and would have to be maintained at every edge at which
  /// [armV41InviteLines] resets the set — exactly the construction at which
  /// `_harvestMemo` and `Highwater` have already drifted apart in this
  /// migration. Here instead the same calculation is repeated that armed
  /// the line in the first place: `invitePeerLabel(K_inv(i))`. The cap from
  /// §15.3.2 is ten invitations open at the same time, so the loop runs
  /// over a single-digit set and computes one SHA-256 per entry.
  ///
  /// **Via `harvestedAt`, not `openAt`** — for the same reason as in
  /// [armV41InviteLines]: a request may still arrive when the invitation
  /// has long expired for the scanner (§15.3.3, the three decoupled
  /// deadlines). Whoever took `openAt` here would lose the assignment
  /// precisely for the requests whose grace window is the point of the
  /// matter.
  ///
  /// Returns `null` if the identifier is not an invitation line, the ledger
  /// is not readable or no harvested invitation matches. `null` is not an
  /// error here: the line may have expired or been revoked between harvest
  /// and assignment.
  //
  // S388-BAU-KONTAKT: `inviteRecordForLine` stood here. Its only consumer
  // was `_handleContactRequestV3`; dropped with it.
}
