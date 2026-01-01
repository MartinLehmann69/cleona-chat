// AP-1c step 3 (docs/MIGRATION_V3_TO_V4_0_MYZEL.md §4c.6) — CLASS B.
//
// Message state care: expiry deadlines, catching up a status by message
// ID and the reception of the delivery receipt.
//
// CLASS B, and specifically the block that AP-4 touches: the target model
// has six states (§5.1b, decided 2026-08-17), `sent`/`queued`/`queuedOffline`
// go away without replacement. Whoever works here should first read the
// preliminary note of §5.1b — the mapping applies to the VALUE, never to
// the TRIGGER, and the larger part of AP-4 is deleting, not renaming.

part of 'cleona_service.dart';

extension MessageStateOps on CleonaService {

  // ─────────────────── DELIVERY STATUS (§9.1, §9.2) ───────────────────
  //
  // `MessageStatus` is the DISPLAY value; the delivery state behind it
  // lives in the mailbox of `package:mycelium` (`_myceliumOutbounds`,
  // `cleona_service_mycelium.dart`). Only a receipt whose sender is proven
  // (`SenderTrust.verified`, §9.2: "authenticated by the recipient's pair
  // tag") may flip a message to `delivered`; the mailbox notes that proof
  // in [_myceliumReceiptMark], and [_deliveryProven] asks it.
  //
  // Until S408-P23 a second register of the V4.1 delivery layer
  // (`V41DeliveryRegister`, `lib/core/tagline/delivery_state.dart`) stood
  // behind it. Its only filler was the V4.1 send branch of `sendToUser`,
  // which had no caller since S388 (`attachV41`); it fell with
  // `lib/core/tagline/`.
  //
  // If the mailbox does NOT know an identifier (long displaced), the
  // previous behaviour remains. A cap must not permanently nail a message
  // to "not delivered".

  void _noteReceipt(List<int> receiptPayload, {required bool verified}) {
    if (!verified) return;
    try {
      final receipt = proto.DeliveryReceipt.fromBuffer(
          Uint8List.fromList(receiptPayload));
      if (receipt.messageId.isEmpty) return;
      // S387: the receipt is already proven here (`verified`) — for a
      // message sent via mycelium this is noted in the mailbox index.
      _myceliumReceiptMark(receipt.messageId.hex);
      // An acknowledged message has no business in the parking compartment
      // any more (§9.2): the receiver demonstrably has it.
      if (localOutbox.remove(receipt.messageId.hex)) saveLocalOutbox();
    } catch (_) {
      // A malformed body carries no information (E-83). The handler below
      // catches the same case and logs it there.
    }
  }

  /// A mycelium receipt (0x11) for which no shipment is open — the normal
  /// case after a restart of this device (S398-OP30; measured in the running
  /// process too, for an entry whose first shipment is no longer open): the
  /// shipment and its
  /// `Outbound` lived in memory, the message itself lives in the history of
  /// the peer (`history.dart`, in the store). mycelium hands it here
  /// (`Messages.onReceiptUnknown`) instead of discarding it.
  ///
  /// §9.2, row by row:
  ///  * [from] is proven: the receipt was unsealed and its signature checked
  ///    before mycelium called. It counts only for an own message in THE
  ///    HISTORY OF [from] whose frame names [from] as its recipient — a
  ///    receipt for another party's message is not found there and is
  ///    reported as discarded.
  ///  * an identifier the history does not know: discarded, no error.
  ///  * already `delivered`: a duplicate, ignored.
  ///  * already `failed`: the application closed it (§9.3, 14 days). A
  ///    closed entry keeps its identifier and no frame (`history.dart`,
  ///    §21.4.2), so there is no message of the app left to assign the
  ///    receipt to here: reported, nothing changes. The display follows the
  ///    application's DELIVERY_RECEIPT, which names the message itself.
  ///
  /// What it does: the history entry becomes `delivered` (the same entry the
  /// mailbox's `stateCheck` would have closed with the open shipment), so
  /// the next edge does not send an acknowledged message again; and the
  /// proof is noted for [_myceliumDeliveryProven]. The DISPLAY flips with
  /// the application's DELIVERY_RECEIPT as before
  /// ([_handleDeliveryReceipt]) — only it carries the recipient's
  /// disclosure bit (§16.2.3); flipping on the 0x11 alone would show what a
  /// withholding recipient chose to conceal. `true` if the entry was closed.
  bool _myceliumReceiptLate(Uint8List identifier, mycelium.Address from) {
    final p = myceliumMailbox;
    if (p == null) return false;
    final peer = mycelium.identifierFrom(from);
    final short = bytesToHex(identifier.sublist(0, 3));
    if (p.contactOrNull(peer) == null && p.groupPairOrNull(peer) == null) {
      _log.info('mycelium: receipt $short from ${peer.substring(0, 8)} — '
          'neither a contact nor a group pair. Discarded (§9.2).');
      return false;
    }
    final history = p.historyFor(from);
    final entry = history.entries
        .where((e) => e.outgoing && constantTimeEquals(e.identifier, identifier))
        .firstOrNull;
    if (entry == null) {
      _log.info('mycelium: receipt $short from ${peer.substring(0, 8)} — no '
          'own message to this party under this identifier. Discarded (§9.2).');
      return false;
    }
    if (entry.state == mycelium.DeliveryState.delivered) return false;
    if (!entry.open) {
      _log.info('mycelium: receipt $short from ${peer.substring(0, 8)} — its '
          'message was closed as ${entry.state?.name} before. Nothing '
          'changes (§9.2, §9.3).');
      return false;
    }
    if (entry.content.isEmpty) {
      // A PLACED message whose copy for sending again was dropped (§9.3:
      // "dropped at the next edge once the placing is more than 7 days
      // old"; `mycelium/lib/history.dart`). The entry stands in the history
      // WITH [from], so it went to that party; the frame that named the
      // app's message is gone with the copy. The entry is closed — an
      // acknowledged message is not open —, and the display follows the
      // application's DELIVERY_RECEIPT, which names the message itself.
      try {
        history.stateChange(identifier, mycelium.DeliveryState.delivered);
      } catch (e) {
        _log.warn('mycelium: receipt $short — history not closed: $e');
        return false;
      }
      _log.event('mycelium: receipt $short from ${peer.substring(0, 8)} for '
          'a placed message whose copy was dropped — delivered in the '
          'history (§9.2, §9.3)');
      return true;
    }
    final proto.ApplicationFrame frame;
    try {
      frame = proto.ApplicationFrame.fromBuffer(entry.content);
    } catch (_) {
      return false; // not an application frame: nothing of the app's
    }
    if (!constantTimeEquals(
        Uint8List.fromList(frame.recipientUserId), userIdFrom(from))) {
      _log.warn('mycelium: receipt $short from ${peer.substring(0, 8)} — the '
          'message names another recipient. Discarded (§9.2).');
      return false;
    }
    try {
      history.stateChange(identifier, mycelium.DeliveryState.delivered);
    } catch (e) {
      _log.warn('mycelium: receipt $short — history not closed: $e');
      return false;
    }
    final idHex = bytesToHex(Uint8List.fromList(frame.messageId));
    _myceliumAcknowledged.add(idHex);
    while (_myceliumAcknowledged.length > _kMyceliumOutboundsMax) {
      _myceliumAcknowledged.remove(_myceliumAcknowledged.first);
    }
    _log.event('mycelium: receipt $short from ${peer.substring(0, 8)} for '
        '${frame.messageType.name} ${idHex.substring(0, 8)} without an open '
        'shipment — delivered in the history (§9.2)');
    return true;
  }

  /// May the display for [messageIdHex] switch to `delivered`?
  ///
  /// `true` also when the mailbox does NOT know the identifier — see the
  /// block header: a displaced or never registered identifier is not a
  /// missing receipt. (Until S408-P23 a V4.1 register stood behind the
  /// mailbox; it was filled only by the V4.1 send path, which has had no
  /// caller since S388, and fell with `lib/core/tagline/`.)
  bool _deliveryProven(String messageIdHex) =>
      _myceliumDeliveryProven(messageIdHex) ?? true;

  /// The display status that the mailbox PROVES for [messageIdHex].
  ///
  /// `null` means "the mailbox does not know the identifier" — a long
  /// displaced entry. Then the previous value stays; a cap must not nail a
  /// message to a state.
  MessageStatus? _statusFor(String messageIdHex) =>
      _myceliumStatusFor(messageIdHex);

  /// Catches up the status of an OUTGOING message from the delivery
  /// register — the only source that v4_1 §22.5.1 permits for it.
  ///
  /// [legIdsHex] are the identifiers under which the legs of this message
  /// were sent: for a 1:1 message exactly one, for the group fan-out one
  /// per member (`UiMessage.fanoutLegs`).
  ///
  /// AGGREGATE OVER THE WEAKEST LEG (§16.2.3, §21.5.5 "Aggregation per
  /// leg"), `failed` the weakest (S410 finding 8, owner decision 30.10.2026
  /// variant A): one leg that no rung carried shows the message with the
  /// warning mark, and `delivered` comes only when every leg is receipted
  /// and none withholds (`UiMessage.isFullyDelivered`). Until S410 `failed`
  /// was a class of its own here (only when NO leg lay anywhere) while the
  /// receipt path counted the failed leg — the message stood on one tick
  /// for good. A receiver that is merely offline does not occur here as
  /// `failed` (§9.1: it stands on `inTransit`).
  /// Returns `true` if the display status ACTUALLY changed — since S376
  /// whether `onStateChanged` fires hangs on that.
  bool _applyOutgoingLegStatus(UiMessage msg, List<String> legIdsHex) {
    // ── THE INDEX IS KEPT HERE (S376, P5 finding 2) ─────────────
    //
    // At this place and only here, because both are present at once here:
    // the message and the wire identifiers of its legs. It thus fills up
    // on the same path by which a message gets into the delivery register
    // at all — there is no send path that does the one without the other.
    for (final id in legIdsHex) {
      _legIndex[id] = (convId: msg.conversationId, msgId: msg.id);
    }
    while (_legIndex.length > CleonaService._legIndexMax) {
      _legIndex.remove(_legIndex.keys.first);
    }
    // §16.2.3: a post on the shared key has the state of its placing with
    // the keepers (`cleona_service_shared_key_post.dart`); legs to members on
    // pairwise legs do not enter it.
    if (msg.sharedKey) return false;

    // S410 finding 8 (variant A): ONE rule for every path — the register
    // here, the receipts (`_applyFanoutReceipt`, `_catchUpMarkOwnDelivered`)
    // call this method too (`weakestLegState`, service_types.dart).
    final fanout = msg.fanoutLegs.isNotEmpty;
    final memberOf = <String, String>{
      for (final e in msg.fanoutLegs.entries) e.value: e.key,
    };
    final legs = <MessageStatus?>[];
    var legsChanged = false;
    for (final id in legIdsHex) {
      final member = memberOf[id];
      final receipted = member != null && msg.deliveredBy.contains(member);
      MessageStatus? register;
      // S398-W5: a leg waiting behind a file (§9.4) is not sent yet —
      // `resting` (§9.1), and the weakest leg counts (§16.2.3).
      if (!receipted) {
        register = _fileOrderWaiting.contains(id)
            ? MessageStatus.resting
            : _statusFor(id);
      }
      final leg = fanout
          ? legDisplayState(
              receipted: receipted,
              withheld: member != null && msg.withheldBy.contains(member),
              register: register)
          : register;
      legs.add(leg);
      // Which member's leg failed — what "retry" sends again (S410 "B").
      // Known legs only: a leg this run does not know keeps its entry.
      if (member != null && leg != null) {
        legsChanged |= leg == MessageStatus.failed
            ? msg.legFailedBy.add(member)
            : msg.legFailedBy.remove(member);
      }
    }
    final fresh = weakestLegState(legs,
        deliveredAllowed: !fanout || msg.isFullyDelivered);
    if (fresh == null || msg.status == fresh ||
        !msg.status.canTransitionTo(fresh)) {
      // §21.4.1: the failed legs changed without the display.
      if (legsChanged) persistMessage(msg.conversationId, msg);
      return false;
    }
    msg.status = fresh;
    // §12.2 "warning mark and its reason" (S398-W1): the delivery layer
    // gave up — no rung carried it.
    if (fresh == MessageStatus.failed) {
      msg.failureReason ??= FailureReason.noRoute;
    }
    // §21.4.1: every change to a message goes into the store.
    // `conversationId` stands at the object itself — the method does not
    // get it passed through, and pulling it from the caller would be a
    // second source for the same fact.
    persistMessage(msg.conversationId, msg);
    return true;
  }

  /// Carries the register state for ONE leg over into the display.
  ///
  /// ══════════════════════════════════════════════════════════════════
  /// WHY THIS METHOD EXISTS (S376, P5 finding 2)
  /// ══════════════════════════════════════════════════════════════════
  ///
  /// Until S376 [_applyOutgoingLegStatus] ran at EXACTLY TWO places, and
  /// both lie on the SEND EDGE: `cleona_service.dart` immediately after
  /// `sendToUser` (1:1) and after the fan-out loop (group). At this point
  /// no relay has acknowledged yet — the record stands on `placing`, and
  /// exactly that is what the method writes into the display.
  ///
  /// After that nothing happened any more. `noteV41Placement` booked the
  /// receipt in the register and took the entry out of the outbox, but did
  /// not touch the `UiMessage`; `_v41Resubmit` likewise. The consequence,
  /// at both ends:
  ///
  ///   * **`placed` was unreachable.** §21.5.5 lists it as its own display
  ///     state ("2+ independent relays hold the cell"), and the user never
  ///     saw it — the message stayed on `placing` until a delivery receipt
  ///     came. For an offline receiver one thus waits for days in front of
  ///     a state that says "going out right now", although the cell has
  ///     long been lying safely in the network.
  ///     `cleona_service_msgstate.dart` said so itself elsewhere:
  ///     "`placed` is unreachable today".
  ///   * **`failed` → `placing` was invisible.** A resubmission (§5.1)
  ///     resets the record and sends freshly; the display stayed on the
  ///     old value.
  ///
  /// ── OVER ALL LEGS, NOT OVER THE ONE ────────────────────────
  ///
  /// The caller knows ONE leg; the display of a group message, however,
  /// is the aggregate over ALL (§21.5.5 "Aggregation per leg", the weakest
  /// counts). This method therefore looks up the message via the index and
  /// passes it with ALL its legs to [_applyOutgoingLegStatus] — the same
  /// calculation as at the send edge, no second verdict.
  ///
  /// ── A NOTIFICATION ONLY ON A REAL CHANGE ───────────────────────────
  ///
  /// Up to `m x R` = 60 receipts per message (§9.2); one `onStateChanged`
  /// per receipt would be 60 redraws of the list for at most two visible
  /// transitions. `_applyOutgoingLegStatus` therefore reports whether
  /// something has changed, and only then does the notification go out.
  void _reflectLegStatus(String legIdHex) {
    final place = _legIndex[legIdHex];
    if (place == null) return;
    final conv = conversations[place.convId];
    if (conv == null) return;
    // ONLY THIS ONE CONVERSATION. `ensureAllLoaded()` — which
    // `_applyFanoutReceipt` next to it does — loads EVERY conversation from
    // the store; with up to 60 receipts per message (§9.2) that would be
    // the most expensive way to information the index has already given.
    ensureLoaded(place.convId);
    UiMessage? msg;
    for (final m in conv.messages) {
      if (m.id == place.msgId) {
        msg = m;
        break;
      }
    }
    if (msg == null) {
      // The message has been deleted (§21.5.1, unlimited deletion) or has
      // expired. The index entry points into nothing and goes along.
      _legIndex.remove(legIdHex);
      return;
    }
    // ALL LEGS: for 1:1 the display identifier is at the same time the
    // wire identifier, for the fan-out it stands in `fanoutLegs`.
    final legs = msg.fanoutLegs.isEmpty
        ? <String>[msg.id]
        : msg.fanoutLegs.values.toList();
    if (_applyOutgoingLegStatus(msg, legs)) {
      onStateChanged?.call();
    }
  }


  /// THE ONE ROUTE on which a message leaves this profile (§21.5.2, level 1:
  /// "The message disappears from the user's own profile. Immediately and
  /// completely.") — the own deletion, the author's deletion at the
  /// recipient, the mirror from an own device, a retracted system-channel
  /// post and the per-chat expiry all end here.
  ///
  /// Gone are the row in the store (`forgetMessage`: `SECURE_DELETE`
  /// overwrites the pages, §21.4), text, preview image, transcript, quote,
  /// link preview, reactions, file name and the attachment file itself —
  /// and the message, its edits and the reactions to it in the history of
  /// the delivery layer, which keeps the content of every message sent and
  /// received and re-dispatches an open own one at every edge
  /// (`_myceliumForget`; §9.3 "it stops the sending").
  ///
  /// Nothing of the message stays in the conversation — no row "message
  /// deleted" either (owner decision 01.10.2026). What keeps a second copy
  /// of the same message (post box, mirror of an own device) from being
  /// shown again is a mark outside the conversation: identifier and delete
  /// time, kept as long as the identity exists
  /// (`cleona_service_deletion_marks.dart`, §21.5.2, §20.2).
  ///
  /// [byAuthor]: the user deleted an own message — the mark keeps, for a
  /// party that catches up later (§9.5), who held it
  /// ([DeletionMarkOps._markDeletedAndForget]).
  void _eraseMessageLocally(String conversationId, UiMessage msg,
      {bool byAuthor = false}) {
    final path = msg.filePath;
    final conv = conversations[conversationId];
    if (conv != null) {
      // Every caller has loaded the history to find [msg]; the second call
      // is free, and the removal below must never meet a history that
      // holds only its youngest row.
      ensureLoaded(conversationId);
      final before = conv.messages.length;
      conv.messages.removeWhere((m) => m.id == msg.id);
      if (conv.messages.length < before) {
        if (conv.totalMessages > 0) conv.totalMessages--;
        // Counted as unread when it came (`_addMessageToConversation`) and
        // not read since: the count must not point at a message that is no
        // longer there.
        if (!msg.isOutgoing &&
            msg.readAt == null &&
            conv.unreadCount > 0 &&
            !SystemChannels.isSystemChannel(conversationId)) {
          conv.unreadCount--;
          _updateBadgeCount();
        }
      }
    }
    forgetMessage(msg.id);
    _markDeletedAndForget(conversationId, msg, byAuthor: byAuthor);
    _voiceTranscription?.forget(msg.id);
    // The archive row, the sender record of the media lanes and the entry
    // of an object still in collection (`cleona_service_conversation_end
    // .dart`): "completely" names them too.
    _eraseStateOfMessage(msg.id);
    if (path != null) _eraseAttachmentUnlessHeld(path);
  }

  /// Removes an attachment file — unless another message still points to it.
  /// One rule for one file and for the files of a whole conversation:
  /// [ConversationEndOps._eraseAttachmentsUnlessHeld].
  void _eraseAttachmentUnlessHeld(String path) =>
      _eraseAttachmentsUnlessHeld([path]);

  /// The user has read [conv] at [at]: every incoming message not yet read
  /// starts its expiry deadline now (§21.5.3). Independent of whether read
  /// receipts are sent — the deadline is local.
  bool _stampIncomingRead(Conversation conv, DateTime at) {
    ensureLoaded(conv.id);
    var stamped = false;
    for (final msg in conv.messages) {
      if (msg.isOutgoing || msg.readAt != null) continue;
      msg.readAt = at;
      persistMessage(conv.id, msg);
      stamped = true;
    }
    return stamped;
  }

  /// Check for expired messages and delete them.
  ///
  /// [at] is the moment the sweep takes as "now"; only the guard
  /// (`debugCheckMessageExpiry`) passes one.
  void _checkMessageExpiry({DateTime? at}) {
    final now = (at ?? DateTime.now()).millisecondsSinceEpoch;
    var changed = false;

    // The marks of deleted messages are not swept here, nor anywhere: they
    // stay as long as the identity exists (§21.5.2, §20.2).

    // ── THE DEADLINE OF THE OUTBOX (§21.2/§21.5.5) ─────────────────────────
    //
    // ON THIS CLOCK AND NO OWN ONE, and it touches NO display state — since
    // S390 that is the whole difference.
    //
    // What happens here is memory hygiene: a ledger entry whose `UiMessage`
    // has long been deleted (§21.5.1 unlimited deletion, per-chat expiry
    // §21.5.3) has nobody left who takes it out, and would run along up to
    // the memory cap.
    //
    // What NO LONGER happens here is giving up. `_checkAndMarkExpired`
    // stood next to it and set `MessageStatus.expired`; §9.3 forbids that
    // ("There is no timer that expires messages"), and the method has
    // fallen. If an entry drops out here, `_statusFor` returns `null`
    // for its identifier, and `null` means explicitly "the cap nails no
    // message to a state": the display keeps its last value.
    final expired = localOutbox.sweep(
        nowMs: now, ttlMs: CleonaService._placementTtlMs);
    if (expired > 0) {
      saveLocalOutbox();
      _log.info('V4.1-Outbox: $expired entries beyond the '
          '14-day deadline taken out (storage cap, no '
          'state change — §9.3)');
    }

    // ── PER-CHAT EXPIRY (§21.5.3) ─────────────────────────────────────────
    //
    // Every message carries the deadline that applied when it entered the
    // conversation (`UiMessage.expiryMs`), and the deadline runs PER COPY:
    // a received message from the moment it was READ here
    // (`UiMessage.readAt`), an own one from the moment it was SENT
    // (`UiMessage.sentAt`) — whatever the recipient reports or withholds.
    // Without its anchor a message does not expire: unread, or not left
    // ("A message that has not left does not expire" — `resting`, and
    // `failed` without ever having left). The conversation's current
    // deadline decides nothing for an existing message — except for a row
    // written before the deadline was kept per message: it has none
    // recorded, and takes the conversation's the first time it is seen
    // here.
    for (final conv in conversations.values) {
      final current = conv.config.expiryDurationMs;
      final hasCurrent = current != null && current > 0;
      if (!hasCurrent && !conv.expiryPending) continue;

      ensureLoaded(conv.id);
      var stillPending = false;
      for (final msg in List<UiMessage>.of(conv.messages)) {
        if (msg.expiryMs == null) {
          msg.expiryMs = hasCurrent ? current : 0;
          persistMessage(conv.id, msg);
        }
        final deadline = msg.expiryMs!;
        if (deadline <= 0) continue;
        final anchor = msg.isOutgoing ? msg.sentAt : msg.readAt;
        if (anchor == null) {
          stillPending = true;
          continue;
        }
        final elapsed = now - anchor.millisecondsSinceEpoch;
        if (elapsed >= deadline) {
          // §21.5.3: an own copy that expires before the message was
          // acknowledged leaves a count for its recipient — the number,
          // nothing of the content (`cleona_service_catch_up_source.dart`).
          _catchUpExpiredCount(conv, msg);
          _eraseMessageLocally(conv.id, msg);
          changed = true;
          _log.debug('Message ${msg.id.substring(0, 8)} expired after ${elapsed}ms');
        } else {
          stillPending = true;
        }
      }
      if (conv.expiryPending != stillPending) {
        conv.expiryPending = stillPending;
        changed = true;
      }
    }

    if (changed) {
      _saveConversations();
      onStateChanged?.call();
    }

    // Prune service-level cooldown maps to prevent unbounded growth.
    final nowDt = DateTime.now();
    _lastNotifiedAt.removeWhere((_, ts) => nowDt.difference(ts).inHours > 1);
    _lastCrRetryPerContact.removeWhere((_, ts) => nowDt.difference(ts).inHours > 2);
    _crEdgeShortenAt.removeWhere((_, ts) => nowDt.difference(ts).inHours > 2);
    _peerStoreRateLog.removeWhere((_, log) => log.isEmpty ||
        log.every((ts) => nowDt.difference(ts).inHours > 1));
    _resyncRequestedAtEpoch.removeWhere((_, epoch) => epoch > 0 &&
        nowDt.millisecondsSinceEpoch ~/ 1000 - epoch > 86400);
  }


  // `_updateMessageStatusById` stood here. AP-4 deleted it, not renamed
  // it: its two callers (§5.1c K3, flush process and S&F) derived the
  // delivery status from a successful L3 placement, and this trigger has
  // no successor in V4.1. Without callers the method would be a tool for
  // exactly the move that §22.5.1 forbids.

  // ── `_checkAndMarkExpired` HAS FALLEN (S390, finding B-4) ──────────
  //
  // Here stood a clock: every outgoing message that stood for 14 days
  // without a receipt was set to `MessageStatus.expired` and taken out of
  // the ledger. §9.3 forbids exactly that, and literally:
  //
  //   "The delivery layer never decides on its own that a message has
  //    failed. It reports what each step did; the application decides
  //    when to stop. There is no timer that expires messages and no
  //    background retry loop."
  //
  // `expired` was moreover a FIFTH state next to the four of §9.1 and
  // terminal besides (`canTransitionTo`): a receipt arriving after 14
  // days — exactly the case §8.2 provides for with seven days of post box
  // deadline and §9.2 with "a retry crossing a late answer" —, could no
  // longer move the display.
  //
  // WHAT TAKES ITS PLACE: nothing. A message stays `inTransit` until a
  // receipt comes (§9.1: "A recipient who is offline is not an error") or
  // until the user gives up and presses "retry"; the renewed attempt gets
  // a new identifier (§9.3), the old entry becomes `failed`. Otherwise
  // `failed` is set by the ladder alone, and only if no rung has carried.
  //
  // The cleanup of the outbox (`localOutbox.sweep` in `_checkMessageExpiry`)
  // is separate from that and stays: it takes LEDGER ENTRIES above the
  // memory cap out and touches no display state.

  // ──────────────────────────── V3 Handler Stubs ────────────────────────────
  // Planned/deferred message types with empty handlers (silent no-op).
  // Categories: §10.5 (in-call collaboration), moderation Phase 2,
  // infra-dispatched types (switch exhaustiveness only), dead proto types.

  // C1 — Layer-Replies (V3 migration of _handleDeliveryReceipt /
  // _handleReadReceipt / _handleEphemeral-typing). The V3 frame has no
  // groupId field — group fan-out for these ephemeral types lands with
  // C4-Groups; here the conversation lookup is DM-style on
  // bytesToHex(senderUserId), with the TypingIndicator carrying a
  // conversationId field for forward-compat.
  //
  // The V3-Neuerung: senderDeviceId is now available for per-device ACK
  // bookkeeping. The C1 cluster does not yet track per-device ACKs
  // (AckTracker is keyed by recipient nodeId / route, not by device); the
  // parameter is accepted and logged for traceability so future Welle-3
  // wiring is a one-line edit.

  /// V3 DELIVERY_RECEIPT: sender side marks the outgoing message as
  /// `delivered`. Conversation lookup is on senderUserId-hex (DM); group
  /// receipts are deferred to C4-Groups.
  void _handleDeliveryReceipt(HarvestEvent event, {bool wasDirect = false}) {
    try {
      final receipt = proto.DeliveryReceipt.fromBuffer(event.payload);
      if (receipt.messageId.isEmpty) return;
      final msgIdHex = receipt.messageId.hex;
      final conversationId =
          event.senderUserId.hex;

      // ── THE BRIDGE TO THE `AckTracker` HAS FALLEN (CUT) ─────────────
      //
      // Here the confirmation was reported back into the RUDP-light timer:
      // deadline off, error counter back, address rating up, and with three
      // consecutive deadline expiries tear down the route (poison reverse).
      // `AckTracker` lived in `lib/core/network/` and was deleted with it.
      //
      // WHAT TAKES ITS PLACE already stands in this file and below: the
      // delivery status of the message flips directly to `delivered` here.
      // There is NO timer that notices a missing reception: the message
      // rests in the post box until it is collected (§8.2, §9.1), and a
      // receiver that stayed offline is not an error.
      //
      // Nothing in route selection hangs on this place any more — there
      // are no routes, no address rating and no resubmission any more that
      // could learn from it.

      // A5: DELIVERY_RECEIPT proves end-to-end contact liveness
      final senderUserHex = event.senderUserId.hex;
      final senderContact = _contacts[senderUserHex];
      if (senderContact != null) {
        senderContact.lastAckedAt = DateTime.now();
        if (senderContact.autoRepairAttempted) {
          senderContact.autoRepairAttempted = false;
        }
        _saveContacts();
      }

      // §5.5b: cancel pending FIRST_CR_STORE timer for First-CRs
      _firstCrAckGates.remove(msgIdHex)?.cancel();

      // S368: here stood the cleanup of the V3 outbox ("§5.8 Crash-safety:
      // remove outbox entry for delivered message"). The V3 outbox has
      // fallen; the V4.1 outbox cleans up at its own receipt edge.

      // §14.7.4: the receipt above was consumed by the transport layer
      // unconditionally — route health and outbox cleanup must never depend
      // on the receiver's display preference. Only the UI upgrade below is
      // governed by it.
      final withheld = receipt.withholdDeliveryStatus;

      // 1:1 path — the sender reused the UiMessage id as the wire messageId.
      // THE ONE QUESTION §9.2 DECIDES: only a receipt whose sender is proven
      // (`SenderTrust.verified`) flips the display. `_noteReceipt` notes
      // the proof in the mailbox index, `_deliveryProven` reads it — the
      // rule stands in ONE place and not once per receive path.
      _noteReceipt(event.payload,
          verified: event.senderTrust == SenderTrust.verified);
      final deliveryProven = _deliveryProven(msgIdHex);

      // ── AND: WAS THIS A LEG OF A LOCK-OUT ANNOUNCEMENT? (E-7) ────
      //
      // AFTER `_noteReceipt`, not before: there the proof of the
      // receipt is noted in the mailbox, here what it says is read. The
      // question "is this receipt proven?" is thus answered at exactly ONE
      // place (§9.2, D2) and not a second time in the lock-out path. If the
      // mailbox does not know the leg, the contact stays pending — the
      // justified strictness stands at `_lockoutDeliveryProven`.
      //
      // The identifier is that of the ACKNOWLEDGED leg, not that of the
      // receipt frame: `msgIdHex` comes from `receipt.messageId`.
      _noteLockoutAck(msgIdHex);

      final conv = conversations[conversationId];
      if (conv != null) {
        ensureLoaded(conversationId);
        for (final msg in conv.messages) {
          if (msg.id == msgIdHex && msg.isOutgoing) {
            if (!withheld &&
                deliveryProven &&
                msg.status.canTransitionTo(MessageStatus.delivered)) {
              msg.status = MessageStatus.delivered;
              persistMessage(conversationId, msg);
              _saveConversations();
              onStateChanged?.call();
            }
            return;
          }
        }
      }

      // Fan-out path (groups) — the wire messageId is a per-member leg id, so
      // the lookup is by (recipient, leg) instead of by UiMessage id. This is
      // what "group receipts are deferred to C4-Groups" left open: without it
      // a group message could never leave `sent`.
      _applyFanoutReceipt(senderUserHex, msgIdHex, withheld: withheld);
    } catch (e) {
      _logHandlerErrorEvent('handleDeliveryReceiptV3', e, event);
    }
  }
}
