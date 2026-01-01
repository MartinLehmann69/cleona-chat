// S387 — the app at the delivery layer V4.2 (`package:mycelium`).
//
// THE SEAM IS `sendToUser` (V4.2 §22.5). This part of the library holds
// the bodies that hang on it: sending to the mailbox, reception into the
// existing dispatcher (`handleApplicationFrame`), the mapping of the
// state onto `MessageStatus`, the invitation card (`cleona:1:…`, contract
// `mycelium/berichte/S387-API-KARTE.md`) and readiness. The process part
// — ONE host, N mailboxes — and the mapping UserID <-> mycelium address
// are in `mycelium_seam.dart`.
//
// WHAT DOES NOT STAND HERE, and why: no mode (V4.2 knows no
// secure/speed switch; `setSecureMode` is dropped, S384-NAHT-GEGEN-API),
// no own-device line (it has its own part since B-4, D-37:
// `cleona_service_own_line.dart`),
// no pair key (`Envelope.seal` seals per message against the address), no
// own resubmission (the mailbox history IS the ledger and resubmits by
// itself at the edges), no acceptance policy: the request waits until the
// user decides (§12.5, `takeMyceliumContactRequest`,
// `_myceliumRequestDecide`; overview in `mycelium_seam.dart` at
// `mailboxDetailsFor`).

part of 'cleona_service.dart';

/// Cap of the identifier index app `messageId` -> mycelium [mycelium.Outbound]. A
/// displaced entry only loses the display source, not the message:
/// `_v41StatusFor` then falls back to "unknown", the previous value
/// stays.
const int _kMyceliumOutboundsMax = 4096;

extension CleonaServiceMycelium on CleonaService {
  // ── Connection ────────────────────────────────────────────────────────

  /// Attaches the mailbox of this identity to the service. Called by
  /// `hostStart`/`serviceRegister` (`mycelium_seam.dart`).
  ///
  /// From here on the service's port is the host's — `ShareCleonaDialog`
  /// and the invitation card read `service.port` (S386 part A).
  ///
  /// From here on the node seam of the network change is
  /// `Host.networkChanged` (§11.8, §22.7.1). It only applies to callers
  /// that call `onNetworkChanged(triggerNodeReset: true)` INDIVIDUALLY
  /// ("Reconnect" in the connection sheet); the start paths run it themselves once per
  /// event and pass `false`.
  void myceliumAttach(mycelium.Mailbox p) {
    myceliumMailbox = p;
    port = p.port;
    v41OnNetworkChanged = () => p.host.networkChanged();
    _log.info('mycelium:mailbox ${p.ownIdentifier.substring(0, 8)} '
        'attached, port ${p.port}');
    // BEFORE the parked messages: a contact ended here must not be made
    // known to the fresh memory again by handing one over (W-a).
    _myceliumFormatResetApply(p);
    // AFTER the format reset: a contact ended there is `deleted` in the next
    // rescue bundle (§13.3, B-1; `cleona_service_recovery_bundle.dart`).
    _recoveryBundleAttach(p);
    // What was deleted while no mailbox was attached leaves its history now
    // (§21.5.2) — before anything is handed over or sent.
    _myceliumForgetOwed();
    _myceliumParkedHandedOver();
    _myceliumNeverFixedNeighbourHandedOver(p);
    _bulkResume(); // lane 3: announced objects of the last run (§9.4)
    _profileUpdateDue(); // a profile change the last run still owed (§15.8)
    // Q1 (§9.4, D-29): the receipt of a lane 3 announcement waits for the
    // decoded object (`cleona_service_bulk.dart`).
    p.identity.messages.receiptLater = _bulkReceiptLater;
    // OP-30 (§9.2): a receipt for a message of the last run (no shipment
    // open any more) is decided by the app (`cleona_service_msgstate.dart`).
    p.identity.messages.onReceiptUnknown = _myceliumReceiptLate;
    // V11 (§9.1, §21.5.3): the mailbox reports the CARRYING of a message
    // — the moment `resting` becomes `in transit`. The display state and
    // the start of the sender-side auto-delete deadline hang on it.
    p.onCarried = _myceliumMessageCarried;
    _myceliumOwnLineSync(); // the own device set (§14.7, D-37)
    // §15.3 "lives 60 s": the mailbox closed at its start what was due; a
    // face-to-face invitation shown shortly before a restart gets its rest.
    _faceToFaceArm();
    onStateChanged?.call();
  }

  /// Detaches the mailbox from the service and returns it (for
  /// `Host.deregister`).
  mycelium.Mailbox? myceliumDetach() {
    final p = myceliumMailbox;
    myceliumMailbox = null;
    v41OnNetworkChanged = null;
    p?.onCarried = null; // the callback belongs to this run of the app
    _faceToFaceClock?.cancel(); // its invitations belong to that mailbox
    _faceToFaceClock = null;
    recoveryBox?.detach(); // its edges belong to that mailbox's node
    recoveryBox = null;
    return p;
  }

  // ── A format change of the delivery layer's memory (W-a) ─────────────

  /// Owner decision W-a (S398): mycelium removed its memory or its
  /// first-contact store at this start because the file had a previous
  /// format version (`memory_enforcer.dart`) — and says so
  /// (`Mailbox.formatResetTake`, `mailbox_format_reset.dart`).
  ///
  /// THE FINDING (lab .201): with the memory went `s_AB` and the day keys of
  /// every contact, and neither arises again except at first contact. The
  /// app kept its contacts `accepted` and made them known to the mailbox
  /// again without them — `Post box step dropped: no daily pubkey`, forever,
  /// with a contact that looked fine. A silent half-state.
  ///
  /// W-a ends every AFFECTED contact with the EXISTING state `deleted`
  /// (§15.9; the identity-deletion pattern of §15.8: the record stays with
  /// its name, the conversation is kept read-only, `_deletedContacts` holds
  /// the mark) and writes the notice [kNoticeReconnectAfterUpdate] into its
  /// conversation. A later request from the same party is a question again
  /// (`takeMyceliumContactRequest`), and accepting it makes a fresh pair.
  /// Affected is, by what was removed — asked of the mailbox, not guessed:
  ///  * `accepted`: the memory (its `s_AB`, its day keys);
  ///  * `pending_outgoing`: its open join is gone (`_myceliumJoinRunsTo`);
  ///  * `pending`: its request no longer waits in the mailbox (the
  ///    invitations and their requests lay in the memory) — the question
  ///    could no longer be answered.
  /// No new state, no conversion of the old format (CLAUDE.md: an enforcer
  /// that deletes old stock is allowed, a migration is not).
  void _myceliumFormatResetApply(mycelium.Mailbox p) {
    final reset = p.formatResetTake();
    if (reset.isEmpty) return;
    final memory = reset.contains(FormatReset.memory);
    final waiting = [
      for (final a in mycelium.MailboxInvitation(p).contactRequests) a.who
    ];
    var ended = 0;
    for (final c in List.of(_contacts.values)) {
      final affected = switch (c.status) {
        'accepted' => memory,
        'pending_outgoing' => !_myceliumJoinRunsTo(c),
        'pending' => !waiting.any((w) => addressHeardTo(w, c)),
        _ => false,
      };
      if (!affected) continue;
      _myceliumContactEndAfterReset(c);
      ended++;
    }
    if (ended > 0) {
      _saveContacts();
      _saveConversations();
      onStateChanged?.call();
    }
    _log.event('mycelium: identity ${identity.userIdHex.substring(0, 8)} — '
        'the delivery layer removed ${reset.map((r) => r.name).join('+')} '
        '(format change): $ended contact(s) ended as deleted, each with the '
        'notice to connect again (W-a, §15.9)');
  }

  /// Ends [c] after a format reset: `deleted`, the notice in its
  /// conversation, nothing of it left in the mailbox, its parked messages
  /// failed (§9.1: no rung will carry them — the pair is gone).
  void _myceliumContactEndAfterReset(ContactInfo c) {
    final hex = bytesToHex(c.nodeId);
    final was = c.status;
    _myceliumContactForget(c);
    c.status = 'deleted';
    _deletedContacts.add(hex);
    // This runs at the mailbox attach, i.e. at start, when the conversation
    // carries only its youngest message (§21.4.1). Without the history a
    // parked message that is not that youngest one was not found below: it
    // left the compartment and stayed `resting` for good (S401).
    ensureLoaded(hex);
    var parked = 0;
    for (final e in v41Outbox.entries.toList()) {
      if (!constantTimeEquals(e.recipientUserId, c.nodeId)) continue;
      v41Outbox.remove(e.messageIdHex);
      parked++;
      final owner = _parkedOwner(e);
      if (owner != null) _seamRefused(owner, 'contact ended (format reset)');
    }
    if (parked > 0) saveV41Outbox();
    _addSystemMessage(hex, kNoticeReconnectAfterUpdate,
        type: UiMessageType.identityDeleted); // system message type
    _log.event('mycelium: contact ${hex.substring(0, 8)} ended after the '
        'format reset (was $was, $parked parked message(s) failed)');
  }

  /// What was sent before the attach (`startService` sends before the
  /// host is up) lies in the outbound compartment (§21.2, `sendToUser`
  /// no-carrier branch). It is handed over here ONCE to the mailbox and
  /// leaves the compartment: from then on the mailbox history is the
  /// ledger, and it resubmits at its own edges. Two ledgers for the same
  /// message would drift apart.
  ///
  /// S401: `sendToUser` answered `true` for a parked message ("taken over"),
  /// so its display state rests. Here the mailbox gives the answer the seam
  /// could not give before the attach. If it REFUSES a 1:1 message that has
  /// a display state ([_parkedOwner]), that is B-5 at the moment it is
  /// observed: the message is closed `failed (noRoute)` and leaves the
  /// compartment — a `failed` message must not go out at a later attach.
  /// Every other refused entry stays, as before, for the next attach.
  void _myceliumParkedHandedOver() {
    if (v41Outbox.length == 0) return;
    var handedOver = 0;
    var closed = 0;
    for (final e in v41Outbox.entries.toList()) {
      final contact = _contacts[e.recipientUserId.hex];
      final a = _myceliumFrameSend(
        recipientUserId: e.recipientUserId,
        contact: contact,
        frame: e.frame,
        messageIdHex: e.messageIdHex,
        typeName: e.messageType,
      );
      if (a == null) {
        final owner = _parkedOwner(e);
        if (owner == null) continue;
        v41Outbox.remove(e.messageIdHex);
        closed++;
        _seamRefused(owner, 'refused at the attach');
        continue;
      }
      v41Outbox.remove(e.messageIdHex);
      handedOver++;
    }
    if (handedOver > 0 || closed > 0) {
      saveV41Outbox();
      _log.event('mycelium:$handedOver parked message(s) handed over to the '
          'mailbox, $closed refused and closed as failed, ${v41Outbox.length} '
          'remain in the compartment');
    }
  }

  /// The 1:1 message whose display state belongs to the parked entry [e], or
  /// `null`: only a text and a lane 1 file carry their OWN identifier (an
  /// edit, a deletion or a reaction carries the identifier of the message it
  /// refers to — that message is not theirs to close), and a group leg is
  /// aggregated over all legs (`_v41ApplyOutgoingStatus`), not closed alone.
  UiMessage? _parkedOwner(V41OutboxEntry e) {
    if (e.groupIdHex != null) return null;
    if (e.messageType != proto.MessageTypeV3.MTV3_TEXT.name &&
        e.messageType != proto.MessageTypeV3.MTV3_MEDIA_INLINE.name) {
      return null;
    }
    final owner = _fileOrderOwner(e.recipientUserId.hex, e.messageIdHex);
    return (owner == null || owner.id != e.messageIdHex) ? null : owner;
  }

  /// THE ONE PLACE that closes a 1:1 message of which the seam took NOTHING
  /// over (B-5, S398-W1): `failed` with the reason `noRoute` (§9.1 "no rung
  /// carried it at all", §12.2 "warning mark and its reason", §22.5.1).
  ///
  /// The observation it carries is the seam's own answer — `sendToUser`
  /// returned `false`, or the mailbox refused a parked message at the attach
  /// ([_myceliumParkedHandedOver]), or the contact was ended with the
  /// message still parked ([_myceliumContactEndAfterReset]). Never "no
  /// mailbox attached yet": that is parked and `resting` (S401).
  ///
  /// A file goes through [_mediaFail], the one place that marks a file
  /// failed (§9.3: it is never sent again).
  void _seamRefused(UiMessage msg, String where) {
    if (msg.isMedia) {
      return _mediaFail(msg, FailureReason.noRoute,
          '$where: nothing taken over by the delivery layer');
    }
    if (!msg.status.canTransitionTo(MessageStatus.failed)) return;
    msg
      ..status = MessageStatus.failed
      ..failureReason = FailureReason.noRoute;
    persistMessage(msg.conversationId, msg);
    onStateChanged?.call();
    _log.warn('$where: ${msg.id.substring(0, 8)} not taken over by the '
        'delivery layer — failed (noRoute)');
  }

  // ── Sending ───────────────────────────────────────────────────────────

  /// The body of [CleonaService.sendToUser] as soon as a mailbox is
  /// attached.
  ///
  /// RETURN: `true` if the message was handed to the mailbox — also when
  /// it is RESTING for lack of a way (V4.2 §22.5.1: `resting`/`inTransit`
  /// are not an error). `false` if nothing was handed over; the reason is
  /// in the log.
  Future<bool> _myceliumSendToUser({
    required Uint8List recipientUserId,
    required bool isSelfSend,
    required ContactInfo? contact,
    required proto.MessageTypeV3 messageType,
    required Uint8List payload,
    Uint8List? groupId,
    Uint8List? messageId,
    proto.ContentMetadata? contentMetadata,
    proto.EditMetadata? editMetadata,
    proto.ExpiryMetadata? expiryMetadata,
    int? groupMembershipEpoch,
    Uint8List? groupMembershipHash,
    Uint8List? postId,
  }) async {
    if (isSelfSend) {
      // `sendToUser` hands the own UserID to the own line
      // (`cleona_service_own_line.dart`, D-37) before this body.
      return _myceliumOwnSend(
          messageType: messageType, payload: payload, messageId: messageId);
    }
    if (kV3InfraTypes.contains(messageType)) {
      _log.error('mycelium: ${messageType.name} is V3 infrastructure and has no '
          'subject in V4.2. Not sent.');
      return false;
    }
    final id = (messageId != null && messageId.isNotEmpty)
        ? messageId
        : SodiumFFI().randomBytes(16);
    final inner = _v41InnerFrame(
      recipientUserId: recipientUserId,
      senderUserId: identity.userId,
      messageId: id,
      messageType: messageType,
      payload: payload,
      groupId: groupId,
      contentMetadata: contentMetadata,
      editMetadata: editMetadata,
      expiryMetadata: expiryMetadata,
      groupMembershipEpoch: groupMembershipEpoch,
      groupMembershipHash: groupMembershipHash,
      postId: postId,
    );
    final a = _myceliumFrameSend(
      recipientUserId: recipientUserId,
      contact: contact,
      frame: Uint8List.fromList(inner.writeToBuffer()),
      messageIdHex: id.hex,
      typeName: messageType.name,
      ephemeral: CleonaService.kV41Ephemeral.contains(messageType),
      messageType: messageType,
      groupId: groupId,
    );
    return a != null;
  }

  /// Hands ONE serialised application frame to the mailbox.
  /// `null` if nothing was handed over.
  mycelium.Outbound? _myceliumFrameSend({
    required Uint8List recipientUserId,
    required ContactInfo? contact,
    required Uint8List frame,
    required String messageIdHex,
    required String typeName,
    bool ephemeral = false,
    proto.MessageTypeV3? messageType,
    Uint8List? groupId,
  }) {
    final p = myceliumMailbox;
    if (p == null) return null;
    final short = CleonaService._hexShort(recipientUserId);
    if (contact == null) {
      // B-3 (§4.3, §16.2.2): a co-member who is not a contact is reached as
      // a GROUP PAIR — only with a group type naming a group the pair
      // carries (`cleona_service_group_pairs.dart`). Otherwise the leg has
      // no way: `failed`, named once in the group (stage 0, §22.5.1).
      final a = _groupPairFrameSend(p,
          recipientHex: bytesToHex(recipientUserId),
          frame: frame,
          messageType: messageType,
          groupId: groupId);
      if (a == null) {
        _groupLegWithoutWay(messageIdHex, bytesToHex(recipientUserId),
            groupId: groupId, messageType: messageType);
        _log.warn('mycelium: $typeName to $short — neither a contact nor a '
            'group pair for this group. Not sent (failed).');
        return null;
      }
      return _myceliumOutboundNote(a, messageIdHex, typeName, short, frame,
          groupPair: true);
    }
    if (contact.isDeleted) {
      // §15.9: a deleted contact is no contact in the delivery layer. A send
      // would make it known to the mailbox again below (`contactRemember`),
      // without `s_AB` — exactly the half-state W-a ends.
      _log.warn('mycelium: $typeName to $short — contact deleted. Not sent.');
      return null;
    }
    // FIRST: does the mailbox already know the contact (first contact,
    // request)? It is searched by the ANCHOR (`addressHeardTo`). The app's
    // contact record then needs no state: a contact still standing
    // `pending` (without `acceptedAt`) is reachable this way, and that is
    // the path of every receipt to a contact request. Measured
    // (smoke_mycelium_app_seam, 3b): without this search it never went
    // out — `SeamError … stand: false`.
    var address = _myceliumKnownAddress(p, contact);
    if (address == null) {
      try {
        address = addressFrom(contact);
      } on SeamError catch (e) {
        _log.warn('mycelium:$typeName to $short — $e. Not sent.');
        return null;
      }
      // The app knows the contact, the mailbox does not (say a contact
      // whose first contact did not run via this mailbox). What is
      // remembered is the ADDRESS, not a way — `contactRemember` without
      // ip/port teaches no fourth route source (`mailbox.dart`, "exactly three
      // sources"). The message then rests and the search call begins.
      p.contactRemember(address);
      _log.info('mycelium: contact $short made known to the mailbox (without route)');
    }
    final identifier = mycelium.identifierFrom(address);
    // Since S390 no way means: NONE of the three addresses from §7.1 is
    // there. An ephemeral indicator does not take the post box either —
    // hours later it would claim someone is typing right now.
    if (ephemeral && mycelium.routesEmpty(p.routesToAddress(address))) {
      // A typing indicator that rests and goes out later claims someone is
      // typing right now (`kV41Ephemeral`). Without a way: do not send.
      _log.debug('mycelium:$typeName to $short without a path — ephemeral, not '
          'sent');
      return null;
    }
    final mycelium.Outbound a;
    try {
      a = mycelium.MailboxOutbound(p).send(identifier, frame);
    } on mycelium.MailboxError catch (e) {
      _log.warn('mycelium:$typeName to $short — $e. Not sent.');
      return null;
    }
    return _myceliumOutboundNote(a, messageIdHex, typeName, short, frame);
  }

  /// Notes the outbound [a] of the message [messageIdHex] for the display.
  mycelium.Outbound _myceliumOutboundNote(mycelium.Outbound a,
      String messageIdHex, String typeName, String short, Uint8List frame,
      {bool groupPair = false}) {
    _myceliumOutbounds[messageIdHex] = a;
    _myceliumOutboundIds[a] = messageIdHex;
    while (_myceliumOutbounds.length > _kMyceliumOutboundsMax) {
      _myceliumOutbounds.remove(_myceliumOutbounds.keys.first);
    }
    // The state the mailbox set just now (`inTransit` once a way carried it
    // or a post box took it, `resting` until then — V11, §9.1) goes into
    // the display at once — not only when the caller of `sendToUser` gets
    // control back (§12.2: the ONE tick must be visible).
    _v41ReflectStatus(messageIdHex);
    // VISIBLE like "V4.1 SENDEN": without the counterpart to reception it
    // is impossible to tell in the field whether nothing went out at all.
    _log.event('mycelium SEND$typeName to $short (${frame.length} B'
        '${groupPair ? ', group pair' : ''}) — ${a.state.name}');
    return a;
  }

  /// V11 (§9.1, §21.5.3): the mailbox has carried [a] — a way demonstrably
  /// transported the packet or a post box took it, and the message flips
  /// from `resting` to `in transit` only NOW. The display state and the
  /// start of the sender-side auto-delete deadline (§21.5.3: "when sent")
  /// hang on this flip, so it must not wait for the next receipt that may
  /// never come: `_v41ReflectStatus` carries the state into the `UiMessage`
  /// at once, and `UiMessage.set status` sets `sentAt`.
  ///
  /// A message whose app run ended while it rested has no note here any
  /// more: its display keeps `resting` until the receipt, and its
  /// deadline starts at the latest then. The 14-day rule of §9.3
  /// continues to bound the entry in the history regardless.
  void _myceliumMessageCarried(mycelium.Outbound a) {
    final messageIdHex = _myceliumOutboundIds[a];
    if (messageIdHex == null) return;
    _v41ReflectStatus(messageIdHex);
  }

  // ── Deletion (§21.5.2 level 1, §9.3) ──────────────────────────────────

  /// A deletion reaches the delivery layer: the messages sent under
  /// [wireIdsHex] leave the mailbox's history, and the sending of every one
  /// of them that is still open stops (`MailboxOutbound.forget`).
  ///
  /// WHY: the history keeps, per peer, the frame of every own message that
  /// is still OPEN — a row of its own in this identity's store, area
  /// `delivery_history` (`mycelium_history_store.dart`) — and re-dispatches
  /// it at each edge of §8.2. Until S401 the deletion removed the message
  /// row only — the text stayed readable in the history, and a deleted
  /// message that had not been acknowledged yet left the device again at
  /// the next start (S401, NB-11). What is acknowledged, given up or
  /// received carries no frame there (§21.4.2, `mycelium/lib/history.dart`)
  /// and is not asked.
  ///
  /// WHAT IS FORGOTTEN: every frame that carries one of the identifiers as
  /// its own — the message and its edits (`editMessage` sends under the
  /// identifier of its target) — and every reaction that names one. NOT the
  /// deletion request (MTV3_DELETE, the same identifier): it is the own
  /// message that tells the other side, and it must stay open until it is
  /// acknowledged (§21.5.2 level 2). Receipts name the identifier in their
  /// payload and carry no content; they stay.
  ///
  /// WHERE: in the histories with [peersHex] — the parties the message, its
  /// edits and the reactions to it went to or came from
  /// ([_myceliumPeersOf]). A contact the mailbox no longer keeps (§15.9) has
  /// no history any more — it left the store with the contact
  /// (`Mailbox.contactForget`); asking for it finds nothing. Without
  /// [peersHex] (the attach, which knows identifiers only) every history of
  /// the mailbox. The cost is one parse per OPEN own entry of each history
  /// asked — and loading a history that was not loaded yet —, which is why
  /// the parties are named where they are known.
  ///
  /// [keepOpenOwn]: an own entry that is still open stays, with its content,
  /// and goes on being sent — a conversation left a group or channel
  /// (`_conversationLeavesProfile`): leaving does not withdraw a post that
  /// is still on its way (§9.3).
  ///
  /// `false` only if no mailbox is attached: then nothing was told, and the
  /// caller keeps it owed (`DeletionMark.owed`).
  bool _myceliumForget(Iterable<String> wireIdsHex,
      {Iterable<String>? peersHex, bool keepOpenOwn = false}) {
    final p = myceliumMailbox;
    if (p == null) return false;
    final ids = wireIdsHex.toSet();
    final peers = <mycelium.Address>[];
    if (peersHex == null) {
      peers
        ..addAll(p.contacts.map((k) => k.address))
        ..addAll(p.groupPairs.map((g) => g.address));
    } else {
      for (final hex in peersHex.toSet()) {
        final known = p.contactOrNull(hex)?.address ??
            p.groupPairOrNull(hex)?.address;
        if (known != null) {
          peers.add(known);
          continue;
        }
        final contact = _contacts[hex];
        if (contact == null) continue; // own identifier, a channel, a stranger
        try {
          peers.add(addressFrom(contact));
        } on SeamError {
          // No complete address: there was no first contact, so no history.
        }
      }
    }
    var forgotten = 0;
    for (final peer in peers) {
      try {
        forgotten += mycelium.MailboxOutbound(p).forget(peer, (e) {
          if (keepOpenOwn && e.outgoing && e.open) return false;
          // Without a frame there is nothing to forget and nothing to
          // read: only an open own entry carries one.
          if (e.content.isEmpty) return false;
          final proto.ApplicationFrameV3 frame;
          try {
            frame = proto.ApplicationFrameV3.fromBuffer(e.content);
            switch (frame.messageType) {
              case proto.MessageTypeV3.MTV3_DELETE:
                return false;
              case proto.MessageTypeV3.MTV3_REACTION:
                return ids.contains(bytesToHex(Uint8List.fromList(
                    proto.EmojiReaction.fromBuffer(frame.payload).messageId)));
              default:
                return ids.contains(
                    bytesToHex(Uint8List.fromList(frame.messageId)));
            }
          } catch (_) {
            return false; // not an application frame: nothing of the app's
          }
        });
      } catch (e) {
        // A history the store does not hand out or take (the store's own
        // error). Reported, not retried: the mailbox cannot read it for
        // sending again either.
        _log.warn('mycelium: history with '
            '${mycelium.identifierFrom(peer).substring(0, 8)} not reached '
            'by the deletion: $e');
      }
    }
    if (forgotten > 0) {
      _log.event('mycelium: deletion — $forgotten entr'
          '${forgotten == 1 ? 'y' : 'ies'} forgotten in the history of the '
          'delivery layer (§21.5.2)');
    }
    return true;
  }

  /// The parties in whose histories [msg] of [conversationId] can stand:
  /// the conversation itself (1:1 — the contact), its sender (a received
  /// message, and the edits to it), every member a leg went to, and the
  /// present members of the group or channel (own edits and reactions go to
  /// all of them). Identifiers that are no party of the mailbox — the own
  /// one, a system channel — are sorted out by [_myceliumForget].
  Set<String> _myceliumPeersOf(String conversationId, UiMessage msg) => {
        conversationId,
        if (msg.senderNodeIdHex.isNotEmpty) msg.senderNodeIdHex,
        ...msg.fanoutLegs.keys,
        ...?_groups[conversationId]?.members.keys,
        ...?_channels[conversationId]?.members.keys,
      };

  // ── Fixed neighbours from contacts (§5.2, §15.10, D2 = a) ─────────────

  /// Hands the mark "never use as a fixed neighbour" of [c] to the mailbox
  /// and, if it changed there, triggers the seat edge at the host
  /// (`HostContactSeats.contactNeverFixedNeighbourSet`). Without a mailbox
  /// nothing happens here — [myceliumAttach] hands the marks over.
  ///
  /// Only an ACCEPTED contact is handed over when the mailbox does not
  /// know it yet: remembering it creates a contact there (with the mark,
  /// without a route), and a request the user has not accepted must not
  /// become one (§12.5).
  void myceliumNeverFixedNeighbourApply(ContactInfo c) {
    final p = myceliumMailbox;
    if (p == null) return;
    var address = _myceliumKnownAddress(p, c);
    if (address == null) {
      if (!c.neverFixedNeighbour || c.status != 'accepted') return;
      try {
        address = addressFrom(c);
      } on SeamError catch (e) {
        _log.warn('mycelium: never-fixed-neighbour mark for '
            '${CleonaService._hexShort(c.nodeId)} not handed over — $e');
        return;
      }
    }
    if (p.host.contactNeverFixedNeighbourSet(p, address, c.neverFixedNeighbour)) {
      _log.info('mycelium: contact ${CleonaService._hexShort(c.nodeId)} '
          '${c.neverFixedNeighbour ? 'excluded from' : 'allowed as'} '
          'fixed neighbour — seats checked');
    }
  }

  /// At the attach: the app's contact record is where the user set the
  /// mark, so the mailbox follows it — for every contact the mailbox
  /// knows, and for every marked one (a mailbox laid down anew, say after
  /// a storage version change, would otherwise lose it silently).
  void _myceliumNeverFixedNeighbourHandedOver(mycelium.Mailbox p) {
    for (final c in _contacts.values) {
      myceliumNeverFixedNeighbourApply(c);
    }
  }

  /// The address under which [p] keeps the contact [c], or `null`.
  mycelium.Address? _myceliumKnownAddress(mycelium.Mailbox p, ContactInfo c) {
    for (final k in p.contacts) {
      if (addressHeardTo(k.address, c)) return k.address;
    }
    return null;
  }

  // ── State ─────────────────────────────────────────────────────────────

  /// The display status of a message sent via mycelium, or `null` for an
  /// identifier this path does not know.
  ///
  /// MAPPING — ONE TO ONE, because both sides keep the same four states
  /// of §9.1 (`mycelium/lib/message.dart`, until the renaming under
  /// German names):
  ///
  ///   `resting`     -> `resting`     waiting mark (§12.2)
  ///   `inTransit`   -> `inTransit`   ONE tick     (§12.2)
  ///   `delivered`   -> `delivered`   TWO ticks    (§12.2)
  ///   `failed`      -> `failed`      warning mark (§12.2)
  ///
  /// **UNTIL S390 THIS MAPPING THREW TWO ONTO ONE** — `resting` AND
  /// `inTransit` both went to `placing`, with the justification that
  /// `placed` had no producer in mycelium. That was the right observation
  /// with the wrong consequence: the ONE tick of §12.2 does not belong to
  /// a placement confirmation, but to "gone out, no receipt yet" (§9.1).
  /// As long as it hung on `placed`, `in transit` could not be displayed
  /// in the UI at all — a user saw the waiting mark until the two ticks
  /// came (finding B-4).
  MessageStatus? _myceliumStatusFor(String messageIdHex) {
    // B-3 stage 0: a leg that had no way at all (§9.1 `failed`).
    if (_myceliumLegsWithoutWay.contains(messageIdHex)) {
      return MessageStatus.failed;
    }
    final a = _myceliumOutbounds[messageIdHex];
    if (a == null) return null;
    if (_myceliumAcknowledged.contains(messageIdHex)) return MessageStatus.delivered;
    return switch (a.state) {
      mycelium.DeliveryState.resting => MessageStatus.resting,
      mycelium.DeliveryState.inTransit => MessageStatus.inTransit,
      mycelium.DeliveryState.delivered => MessageStatus.delivered,
      mycelium.DeliveryState.failed => MessageStatus.failed,
    };
  }

  /// Whether the delivery of a message sent via mycelium is proven —
  /// `null` for a foreign identifier. Proven means: the mycelium receipt
  /// came (`delivered`) OR a delivery receipt of the application whose
  /// sender mycelium has proven ([_myceliumReceiptMark]).
  bool? _myceliumDeliveryProven(String messageIdHex) {
    final a = _myceliumOutbounds[messageIdHex];
    if (a == null) return null;
    return _myceliumAcknowledged.contains(messageIdHex) ||
        a.state == mycelium.DeliveryState.delivered;
  }

  /// Notes a proven delivery receipt of the application for a message
  /// sent via mycelium. Only for known identifiers — otherwise the set
  /// grows with foreign receipts.
  void _myceliumReceiptMark(String messageIdHex) {
    if (!_myceliumOutbounds.containsKey(messageIdHex)) return;
    _myceliumAcknowledged.add(messageIdHex);
    while (_myceliumAcknowledged.length > _kMyceliumOutboundsMax) {
      _myceliumAcknowledged.remove(_myceliumAcknowledged.first);
    }
  }

  /// §22.7.1 — the host's readiness state, live. `null` without a mailbox
  /// (then the V4.1 remainder answers with `searching`).
  String? get _myceliumReadiness => myceliumMailbox?.host.readiness.name;

  // ── Reception ─────────────────────────────────────────────────────────

  /// THE ONE PLACE that overwrites a contact's signing keys with a rotation
  /// chain (V4.2 §4.5.4 "Five deliveries can overwrite a stored public key …
  /// every path … must trigger the check", D-33).
  ///
  /// [from] is an address mycelium accepted: its keys are the ones mycelium
  /// holds for the identifier or a chain connects them. The app checks the
  /// SAME chain against the keys IT holds — [RotationChain.holds] from the
  /// contact's UserID to [from]'s keys, passing through the held ones. The
  /// chain is the one the envelope carried, or — when it no longer rides
  /// (acknowledged) — the one mycelium kept with the contact
  /// (`memory_contact.dart`). A chain that does not pass through the held
  /// keys is a FORK: shown (E-A9), nothing adopted.
  ///
  /// Adoption (§4.5.4, §14.4): all four keys in place — contact, groups,
  /// channels; the level falls back provisionally
  /// ([_levelBeforeRotation] keeps what it was until the announcement brings
  /// the quorum); the key-change warning is shown (SR-1). `true` if the
  /// contact now holds [from]'s keys.
  bool _adoptChainedKeys(ContactInfo contact, mycelium.Address from) {
    final hex = bytesToHex(contact.nodeId);
    final short = hex.substring(0, 8);
    final heldEd = contact.ed25519Pk, heldDsa = contact.mlDsaPk;
    if (heldEd == null || heldDsa == null) return false;
    var chain = from.chain;
    if (chain.isEmpty) {
      final kept = myceliumMailbox?.contactOrNull(hex)?.address;
      if (kept != null && kept.sameKeys(from)) chain = kept.chain;
    }
    final ChainKeys held;
    try {
      held = ChainKeys(heldEd, heldDsa);
    } on RotationChainError {
      return false;
    }
    if (!chain.holds(contact.nodeId, from.signingKeys)) {
      _log.warn('mycelium drop: sender $short — other keys than the contact '
          'holds, and no rotation chain from its UserID to them (§4.5.4). '
          'Discarded.');
      return false;
    }
    if (chain.superseded(from.signingKeys) || !chain.passesThrough(held)) {
      _log.warn('mycelium drop: sender $short — FORK: a rotation chain that '
          'does not pass through the keys held for the contact (§4.5.4). '
          'Discarded, shown.');
      takeMyceliumFork(hex);
      return false;
    }
    if (!_setContactTrustAnchor(contact, hex, from.ed25519Pk, from.mlDsaPk,
        source: 'rotation chain')) {
      _log.warn('§8.3: rotation chain from $short — anchor write REFUSED, '
          'keys unchanged');
      return false;
    }
    contact.x25519Pk = from.x25519Pk;
    contact.mlKemPk = from.mlKemPk;
    contact.kemRotationAt = DateTime.fromMillisecondsSinceEpoch(from.state);
    final before = contact.verificationLevel;
    final change =
        onIdentityRotation(before, quorumMet: false, oldSignatureValid: true);
    contact.applyKeyChange(change);
    _levelBeforeRotation[hex] = _levelBeforeRotation[hex] ?? before;
    for (final group in _groups.values) {
      final member = group.members[hex];
      if (member != null) {
        member.ed25519Pk = from.ed25519Pk;
        member.x25519Pk = from.x25519Pk;
        member.mlKemPk = from.mlKemPk;
      }
    }
    _saveGroups();
    for (final channel in _channels.values) {
      final member = channel.members[hex];
      if (member != null) {
        member.ed25519Pk = from.ed25519Pk;
        member.x25519Pk = from.x25519Pk;
        member.mlKemPk = from.mlKemPk;
      }
    }
    _saveChannels();
    _saveContacts();
    _log.info('rotation chain of $short adopted (${chain.length} link(s)): '
        'keys replaced in place, UserID unchanged; level $before→'
        '${contact.verificationLevel} until the announcement decides (§14.4)');
    try {
      onContactIdentityRotated?.call(hex, contact.displayName, change.wasVerified);
    } catch (e) {
      _log.warn('onContactIdentityRotated listener threw: $e');
    }
    return true;
  }

  /// The adoption site without an envelope — for probes that measure what
  /// an adopted rotation does to the contact and the interface.
  @visibleForTesting
  bool testAdoptChainedKeys(ContactInfo contact, mycelium.Address from) =>
      _adoptChainedKeys(contact, from);

  /// A FORK for the contact [contactHex] (§4.5.4, E-A9): two successors of
  /// one key — the old keys are in other hands. Shown to the user; nothing
  /// is adopted. Also the callback `MailboxDetails.onFork`.
  void takeMyceliumFork(String contactHex) {
    final c = _contacts[contactHex];
    if (c == null) return;
    try {
      onContactKeyFork?.call(contactHex, c.displayName);
    } catch (e) {
      _log.warn('onContactKeyFork listener threw: $e');
    }
  }

  /// Callback `MailboxDetails.onMessage`: an inbound for THIS identity.
  /// Started without `await`, like `acceptV41Frame` — a throw runs into
  /// the process's zone and is classified there.
  void takeMyceliumInbound(mycelium.Inbound e) {
    unawaited(_myceliumInboundAccept(e));
  }

  Future<void> _myceliumInboundAccept(mycelium.Inbound e) async {
    if (_disposed) return;
    final proto.ApplicationFrameV3 frame;
    try {
      frame = proto.ApplicationFrameV3.fromBuffer(e.content);
    } catch (_) {
      // Silent (E-83): an unreadable frame carries no information.
      _log.debug('mycelium:inbound without a readable application frame '
          '(${e.content.length} B) — discarded');
      return;
    }

    // Addressed to US? The seal has answered that (`Inbound.to`); the
    // frame names a UserID, and both must say the same.
    final recipient = Uint8List.fromList(frame.recipientUserId);
    if (!constantTimeEquals(recipient, identity.userId)) {
      _log.warn('mycelium drop:frame names recipient '
          '${CleonaService._hexShort(recipient)}, opened by '
          '${identity.userIdHex.substring(0, 8)}');
      return;
    }

    // ── THE SENDER (§22.5.3 "Trust belongs in the type") ────────────
    //
    // mycelium PROVES `e.from`: the envelope is signed with Ed25519 AND
    // ML-DSA, and the signed data carry sender and receiver
    // (`envelope.dart`). The frame NAMES a UserID. The two are held
    // together via the ONE mapping in `mycelium_seam.dart`:
    //   * contact with anchor: `addressHeardTo` -> `verified`; otherwise
    //     discarded.
    //   * without anchor (first contact): the UserID must be
    //     `userIdFrom(e.from)` -> `skippedBootstrap`, i.e. no silent key
    //     adoption; otherwise discarded.
    final sender = Uint8List.fromList(frame.senderUserId);
    // The own UserID: twin sync from another own device (§14.7, D-37) — its
    // own gate, it is no contact (`cleona_service_own_line.dart`).
    if (constantTimeEquals(sender, identity.userId)) {
      return _myceliumOwnInbound(e, frame);
    }
    final senderHex = bytesToHex(sender);
    // Did the layer below already keep THIS delivery's identifier in the
    // identity's received memory (§20.2, S403 decision 1)? `inboundAccept`
    // keeps it for a sender it knows — contact, group pair — and the two
    // `inboundMark` sites below keep it for a sender the application has
    // just decided. What NOBODY has kept reaches the receive path as a
    // delivery identifier, and there the path keeps it when it processes
    // the frame; a stranger that §15.7 discards below keeps nothing (no
    // fill, §15.7).
    final p = myceliumMailbox;
    var identifierKept = p != null &&
        (p.contactOrNull(mycelium.identifierFrom(e.from)) != null ||
            p.groupPairOrNull(mycelium.identifierFrom(e.from)) != null);
    final contact = _contacts[senderHex];
    var trust = OuterSigStatus.skippedBootstrap;
    final anchorEd = contact?.ed25519Pk;
    final anchorDsa = contact?.mlDsaPk;
    final hasAnchor = anchorEd != null &&
        anchorEd.isNotEmpty &&
        anchorDsa != null &&
        anchorDsa.isNotEmpty;
    if (hasAnchor) {
      if (!addressHeardTo(e.from, contact!)) {
        _log.warn('mycelium drop: sender ${senderHex.substring(0, 8)} — '
            'the envelope is signed by a different identity than the '
            'contact. Discarded, not downgraded.');
        return;
      }
      // Same identifier, other keys: an Emergency Key Rotation (§4.5.4).
      // mycelium accepted the envelope only because its chain passes
      // through the keys mycelium holds; the app checks the same chain
      // against the keys IT holds and adopts them — the ONE place that
      // overwrites a contact's signing keys (§4.5.4 "every envelope carrying
      // a rotation chain"). Until S398 this was a drop.
      if (!addressKeysOf(e.from, contact) &&
          !_adoptChainedKeys(contact, e.from)) {
        return;
      }
      trust = OuterSigStatus.verified;
    } else if (!constantTimeEquals(userIdFrom(e.from), sender)) {
      _log.warn('mycelium drop: frame names sender '
          '${senderHex.substring(0, 8)}, the envelope is signed by a '
          'different identity. Discarded.');
      return;
    } else if (contact != null && _recoveryAnchor(contact, e.from)) {
      // A contact restored from the rescue bundle, proven by its first
      // envelope (§13.3, B-1 E7-b): from now on it has its anchor.
      trust = OuterSigStatus.verified;
      if (p != null) {
        mycelium.MailboxInbound(p).inboundMark(e);
        // `inboundMark` keeps the delivery identifier in the received
        // memory too (§20.2) — the receive path keeps nothing for it.
        identifierKept = true;
      }
    }

    // The answer CARRIES keys in the body, and the handler stores them as
    // anchor. They must be those of the envelope — otherwise a proven
    // identity could submit foreign keys as its own.
    if (!_myceliumBodyKeysMatch(frame, e.from)) {
      _log.warn('mycelium drop:${frame.messageType.name} from '
          '${senderHex.substring(0, 8)} carries other keys than '
          'the envelope. Discarded.');
      return;
    }

    // ── DECIDED? (§12.5, §15.7 — S388-BAU-KONTAKT, B-2) ──────────
    //
    // Only a contact about which a decision has been made reaches the
    // application: `accepted`, or `pending_outgoing` (we have joined them —
    // our own decision). A `pending` counterpart is an open question, an
    // unknown one a stranger; both are discarded ("anything else —
    // nothing"). Only exception: the answer to an own, still running join
    // with mutual requests (§15.5).
    final state = contact?.status;
    final decided = state == 'accepted' ||
        state == 'pending_outgoing' ||
        (state == 'pending' &&
            frame.messageType ==
                proto.MessageTypeV3.MTV3_CONTACT_REQUEST_RESPONSE &&
            _myceliumJoinRunsTo(contact!));
    // §15.7 (B-3, D-36): a GROUP PAIR is not an unknown party for a group
    // type naming a group both belong to in the current member state.
    final viaGroupPair =
        !decided && contact == null && _groupPairAdmits(frame, senderHex);
    if (!decided && !viaGroupPair) {
      final pair = myceliumMailbox?.groupPairOrNull(senderHex) != null;
      _log.warn('mycelium drop: ${frame.messageType.name} from '
          '${senderHex.substring(0, 8)} — '
          '${pair ? 'group pair, but not a group type naming a shared group' : 'no decided contact (${state ?? 'unknown'})'}'
          '. Discarded (§15.7).');
      return;
    }
    // A group pair's sender IS proven: the frame's UserID is the envelope's
    // identifier (checked above), and that identifier is the one of the
    // self-signed address the pair was formed with (§16.2.2, E3) — so its
    // receipt proves a leg like a contact's does (§9.2).
    if (viaGroupPair) trust = OuterSigStatus.verified;
    // The mailbox remembers the sender only HERE, with the app's decision
    // behind it (`MailboxInbound.inboundAccept` no longer does it for
    // strangers) — and only proven (anchor).
    if (p != null &&
        hasAnchor &&
        p.contactOrNull(mycelium.identifierFrom(e.from)) == null) {
      mycelium.MailboxInbound(p).inboundMark(e);
      // `inboundMark` keeps the delivery identifier in the received
      // memory too (§20.2) — the receive path keeps nothing for it.
      identifierKept = true;
    }

    _log.event('mycelium RECEIVE${frame.messageType.name} from '
        '${senderHex.substring(0, 8)} (${e.content.length} B, '
        '${viaGroupPair ? 'group pair' : trust.name})');

    final verdict = await handleApplicationFrame(
      event: HarvestEvent.fromV3Frame(
        frame: frame,
        // The delivery layer addresses identities, not devices.
        senderDeviceId: null,
        // The delivery identifier — unless the layer below or an
        // `inboundMark` above has already kept it in the received memory
        // (§20.2): then `null`, and the receive path checks and keeps
        // nothing, per the null contract of `HarvestEvent.deliveryId`.
        deliveryId: identifierKept ? null : e.identifier,
        snapshot: SenderIdentitySnapshot(
          senderDeviceId: null,
          senderUserId: sender,
          outerSigStatus: trust,
          verifiedDeviceEd25519Pk: null,
          verifiedDeviceMlDsaPk: null,
          newKeyDetectedForSenderUser: false,
          // §22.5.3: the LOCAL arrival time, observed by mycelium.
          receivedAt: e.at,
        ),
      ),
      wasDirect: false,
    );
    // §14.2: this device collected it — the other own devices get a mirror.
    // §14.7 Type 21 GROUP_LEFT (S403): a post this device DISCARDED for a
    // group the identity left is not forwarded to the other own devices —
    // they read the leaving over the own line and discard the post there
    // as well; a mirror would undo the leaving on them.
    if (verdict != GroupGateVerdict.discarded) {
      _myceliumMirror(frame, e.content, e.identifier);
    }
  }

  /// For CONTACT_REQUEST_RESPONSE: the keys in the body must be those of
  /// the envelope. Every other kind: `true`.
  bool _myceliumBodyKeysMatch(
      proto.ApplicationFrameV3 frame, mycelium.Address from) {
    final List<int> ed, dsa, x, kem;
    switch (frame.messageType) {
      case proto.MessageTypeV3.MTV3_CONTACT_REQUEST_RESPONSE:
        final r = proto.ContactRequestResponse.fromBuffer(frame.payload);
        if (!r.accepted) return true;
        (ed, dsa, x, kem) = (r.ed25519PublicKey, r.mlDsaPublicKey,
            r.x25519PublicKey, r.mlKemPublicKey);
      default:
        return true;
    }
    bool equal(List<int> a, Uint8List b) =>
        constantTimeEquals(Uint8List.fromList(a), b);
    return equal(ed, from.ed25519Pk) &&
        equal(dsa, from.mlDsaPk) &&
        equal(x, from.x25519Pk) &&
        equal(kem, from.mlKemPk);
  }

  // ── Invitation card (contract S387-API-KARTE.md) ──────────────────────

  /// The channel in which THIS build runs — the card is read in it
  /// (contract §6.1, V4.2 §15.2/§15.3).
  int get _ownCardChannel => invitationChannelByte(
      isBeta: activeNetworkChannel == NetworkChannel.beta);

  /// A local, opaque identifier of an invitation (contract §6.5):
  /// NOT the code (that belongs in no list over IPC), but the first 16 hex
  /// digits of its SHA-256.
  String _invitationId(Uint8List code) =>
      bytesToHex(SodiumFFI().sha256(code)).substring(0, 16);

  /// `issueInvitationCard` — §15.2/§15.3.
  ///
  /// [faceToFace] (§15.5): the invitation carries the marker `persoenlich`
  /// at the issuer, and the card comes back WITHOUT a text line — a line
  /// could be passed on and would obtain acceptance without a question.
  /// Only for the single-use kind (§15.3 "issued as the single kind too").
  InvitationIssueResult _cardIssue({
    required InvitationKind kind,
    InvitationValidity? validity,
    String label = '',
    bool faceToFace = false,
  }) {
    final p = myceliumMailbox;
    if (p == null) {
      return const InvitationIssueResult.refused(
          InvitationIssueRefusal.notConnected);
    }
    if (faceToFace && kind != InvitationKind.single) {
      return const InvitationIssueResult.refused(
          InvitationIssueRefusal.failed,
          'personal handover only for one person (§15.3, §15.5)');
    }
    // §15.3 (contract §6.4): ONE identity per node with a standing
    // invitation — the anonymous bundle request cannot be attributed to
    // any (S385-SCHNITT-F §4.1). Not silently the card of the wrong identity.
    for (final other in p.host.mailboxes) {
      if (identical(other, p)) continue;
      if (other.identity.invitations.standing().isNotEmpty) {
        return const InvitationIssueResult.refused(
            InvitationIssueRefusal.otherIdentityStanding);
      }
    }
    // §15.3 "Selectable 7 d / 30 d / 90 d / unlimited". Until S390 this
    // place rejected every choice except the default, because `Node.invite`
    // did not pass the validity on — the UI offered all four values and
    // three of them could only fail. Now it travels through:
    // `null` -> the default of the kind, `unlimited` -> `0xFFFFFFFF`.
    final chosen = validity ?? InvitationValidity.defaultFor(kind);
    // §15.3 "Attribution": the label stays with the issuer. A value that
    // is too long is rejected BY NAME instead of silently truncated —
    // truncated, a different invitation than the intended one would stand
    // in the list.
    if (utf8.encode(label).length > mycelium.kLabelAtMostBytes) {
      return InvitationIssueResult.refused(
          InvitationIssueRefusal.failed,
          'Beschriftung laenger als '
          '${mycelium.kLabelAtMostBytes} B');
    }
    if (p.identity.invitations.standing().length >=
        mycelium.kAtMostStanding) {
      return const InvitationIssueResult.refused(
          InvitationIssueRefusal.capReached);
    }
    final ({mycelium.Card card, String text}) out;
    try {
      out = mycelium.MailboxInvitation(p).invitationIssue(
          open: kind == InvitationKind.open,
          inPerson: faceToFace,
          days: chosen.days,
          unlimited: chosen.days == null,
          label: label);
    } on StateError catch (e) {
      // `Invitations.admit` throws exactly at the cap.
      return InvitationIssueResult.refused(
          InvitationIssueRefusal.capReached, '$e');
    }
    _log.event('mycelium CARD issued (${kind.name}, ${chosen.name}'
        '${faceToFace ? ', in person' : ''}, '
        '${_invitationId(out.card.code)})');
    // §12.4: shown at once only with a way in from the open network.
    final wayIn = mycelium.invitationWayIn(p, out.card) != null;
    // §15.3 "lives 60 s": with a way in the front end shows the card as it
    // arrives — its clock starts now, here in the service.
    if (faceToFace && wayIn) _faceToFaceShown(out.card.code);
    return InvitationIssueResult.issued(InvitationCard(
      // The same identifier as StandingInvitation.id (line 582) — otherwise
      // the card just issued could not be revoked.
      id: _invitationId(out.card.code),
      text: faceToFace ? '' : out.text,
      packed: out.card.pack(),
      kind: kind,
      expiryUnixSeconds: out.card.expiryUnixSeconds,
      faceToFace: faceToFace,
      wayIn: wayIn,
    ));
  }

  // ── §15.3 "A face-to-face invitation lives 60 s" ──────────────────────
  //
  // The service — not the screen — closes a face-to-face invitation (QR shown
  // person to person, NFC) that nobody redeemed 60 s after it was shown
  // (owner decision 07.10.2026). The rule and the moment shown live in the
  // mailbox (`invitation_face_to_face.dart`, on disk with the invitation);
  // here is only the one local clock and where the moment comes from:
  //   * with a way in at issue, the front end shows the card at once
  //     ([_cardIssue]);
  //   * after the wait of §12.4, as the way in arrives ([_cardWayIn]);
  //   * "show anyway – same W/LAN only": only the front end knows that
  //     moment and reports it ([_cardShown], `reportInvitationShown`).

  /// Stamps the face-to-face invitation with [code] as shown now and arms
  /// the clock. `false` if it no longer stands.
  bool _faceToFaceShown(Uint8List code) {
    final p = myceliumMailbox;
    final e = p?.identity.invitations.toCode(code);
    if (p == null || e == null) return false;
    final standing = mycelium.MailboxFaceToFace(p).faceToFaceShown(e);
    _faceToFaceArm();
    return standing;
  }

  /// `reportInvitationShown` — the front end shows the invitation [id] now
  /// ("show anyway", §12.4). `false`: it no longer stands — closed, revoked
  /// or spent — and must not be shown.
  bool _cardShown(String id) {
    final p = myceliumMailbox;
    if (p == null) return false;
    final e = p.identity.invitations.all
        .where((e) => _invitationId(e.code) == id)
        .firstOrNull;
    if (e == null) return false;
    final standing = _faceToFaceShown(e.code);
    _log.event('mycelium CARD $id shown (anyway)'
        '${standing ? '' : ' — no longer standing'}');
    return standing;
  }

  /// The one local clock of §15.3 "lives 60 s": runs until the next shown,
  /// unredeemed face-to-face invitation is due, closes what is due, and arms
  /// itself for the next. None running — no timer (working rule 5).
  void _faceToFaceArm() {
    _faceToFaceClock?.cancel();
    _faceToFaceClock = null;
    final p = myceliumMailbox;
    if (p == null || _disposed) return;
    final wait = mycelium.MailboxFaceToFace(p).faceToFaceNext();
    if (wait == null) return;
    _faceToFaceClock = Timer(wait, () {
      _faceToFaceClock = null;
      if (_disposed || !identical(myceliumMailbox, p)) return;
      final n = mycelium.MailboxFaceToFace(p).faceToFaceClose();
      if (n > 0) {
        _log.event('mycelium CARDS closed: $n face-to-face, not redeemed '
            '${mycelium.faceToFaceLife.inSeconds} s after shown (§15.3)');
        onStateChanged?.call();
      }
      _faceToFaceArm();
    });
  }

  /// `awaitInvitationWayIn` — §12.4. The invitation must still stand; a
  /// revoked or unknown one is refused by name, not waited for.
  Future<InvitationIssueResult> _cardWayIn(String id) async {
    final p = myceliumMailbox;
    if (p == null) {
      return const InvitationIssueResult.refused(
          InvitationIssueRefusal.notConnected);
    }
    final e = p.identity.invitations.all
        .where((e) => !e.revoke && _invitationId(e.code) == id)
        .firstOrNull;
    if (e == null) {
      return const InvitationIssueResult.refused(
          InvitationIssueRefusal.failed, 'invitation not standing');
    }
    final r = await mycelium.MailboxWayIn(p).invitationWayInAwait(e);
    _log.event('mycelium CARD $id: ${r.way == null ? 'no way in within '
        '${kInvitationWayInWait.inSeconds} s' : 'way in ${r.way!.name}'}');
    // §15.3 "lives 60 s": the front end shows the card as its way in arrives.
    if (e.inPerson && r.way != null) _faceToFaceShown(e.code);
    return InvitationIssueResult.issued(InvitationCard(
      id: id,
      text: e.inPerson ? '' : r.text,
      packed: r.card.pack(),
      kind: e.kind == mycelium.Kind.open
          ? InvitationKind.open
          : InvitationKind.single,
      expiryUnixSeconds: r.card.expiryUnixSeconds,
      faceToFace: e.inPerson,
      wayIn: r.way != null,
    ));
  }

  /// `redeemInvitationText` / `redeemInvitationCardBytes` — after reading
  /// (contract §6.1/§6.2: read error, foreign channel, expiry BEFORE any
  /// packet).
  Future<InvitationRedeemResult> _cardRedeem(
      InvitationReading reading) async {
    if (myceliumMailbox == null) {
      return const InvitationRedeemResult(InvitationRedeemOutcome.notConnected);
    }
    if (!reading.ok) {
      return InvitationRedeemResult(InvitationRedeemOutcome.readError,
          readError: reading.error, cardChannel: reading.cardChannel);
    }
    // §13.3.1 (B-1 E1-b): in the recovery case the card's addresses are
    // asked for the rescue bundle first. Did it bring this very contact
    // back, no request is sent — its first envelope anchors it (E7-b).
    await _recoverySeekAtCard(reading.card!);
    // D-40, §14.6.1: undecided, the install searches only — no request goes
    // out in the identity's name.
    if (enrolmentHolds(_enrol.phase)) {
      return const InvitationRedeemResult(InvitationRedeemOutcome.searchedOnly);
    }
    if (_recoveryAnchors.containsKey(bytesToHex(reading.card!.fingerprint))) {
      return const InvitationRedeemResult(
          InvitationRedeemOutcome.alreadyContact);
    }
    return _myceliumJoin(reading.card!,
        pkInv: reading.pkInv,
        keyBundle: reading.keyBundle,
        lineSignature: reading.lineSignature,
        lineChain: reading.lineChain);
  }

  /// The join itself — the part of `redeem*` AFTER the card reader.
  ///
  /// 1. Own card? (a mailbox of this host keeps the code) -> `ownCard`.
  /// 2. `Mailbox.join` step 1 — bundle checked, request (2) with the own
  ///    introduction out (`onSent`). No bundle within the deadline
  ///    -> `noAnswer`. Step 2 (the inviter's decision, §12.5) is NOT
  ///    waited for — it can take hours.
  /// 3. The app's contact record is created as `pending_outgoing`, with
  ///    the keys FROM THE BUNDLE -> `requestSent` ("request out", not
  ///    "contact stands", contract §6.3).
  /// 4. [_myceliumJoinTrack] attaches itself to the decision.
  ///
  /// With a `cleona:2:` line ([pkInv], [keyBundle], proposal E) step 1 has no
  /// bundle round trip: the request goes out at once — into the issuer's
  /// invitation post box too, if it is off — and there is no 5-s wait and no
  /// `noAnswer`; the pending contact carries the keys from the line.
  Future<InvitationRedeemResult> _myceliumJoin(mycelium.Card card,
      {Uint8List? pkInv,
      Uint8List? keyBundle,
      Uint8List? lineSignature,
      Uint8List? lineChain}) async {
    final p = myceliumMailbox!;
    final codeHex = mycelium.hexFrom(card.code);
    for (final own in p.host.mailboxes) {
      if (own.identity.open.containsKey(codeHex)) {
        return const InvitationRedeemResult(InvitationRedeemOutcome.ownCard);
      }
    }
    // S405 F-1: `true` = in transit (a way carried it or the post box took
    // it, §9.1), `false` = out-of-band request saved, resting (§12.2).
    final sent = Completer<(mycelium.Address, bool)>();
    final decided = mycelium.MailboxInvitation(p).join(
      pkInv != null && keyBundle != null && lineSignature != null
          ? mycelium.asInvitationLine(card, pkInv, keyBundle, lineSignature,
              chain: lineChain)
          : mycelium.asInvitationText(card),
      introduction: _myceliumIntroduction(),
      onSent: (g) {
        if (!sent.isCompleted) sent.complete((g, true));
      },
      onResting: (g) {
        if (!sent.isCompleted) sent.complete((g, false));
      },
    );
    final mycelium.Address addr;
    final bool inTransit;
    try {
      // Whatever comes first: the end of step 1, or an error before it. The
      // error of a LATER rejection falls into `_myceliumJoinVerfolgen`.
      (addr, inTransit) = await Future.any(
          [sent.future, decided.then((k) => (k.address, true))]);
    } on mycelium.MailboxError catch (e) {
      _log.warn('mycelium: join did not come about — $e');
      return InvitationRedeemResult(InvitationRedeemOutcome.noAnswer,
          detail: '$e');
    } on mycelium.CardTextError catch (e) {
      _log.warn('mycelium: card for the join unreadable — $e');
      return InvitationRedeemResult(InvitationRedeemOutcome.failed,
          detail: '$e');
    }
    final userId = userIdFrom(addr);
    final hex = bytesToHex(userId);
    if (constantTimeEquals(userId, identity.userId)) {
      return const InvitationRedeemResult(InvitationRedeemOutcome.ownCard);
    }
    final soFar = _contacts[hex];
    if (soFar != null && soFar.status == 'accepted') {
      _log.info('mycelium: join to ${hex.substring(0, 8)} — already a contact');
      return const InvitationRedeemResult(
          InvitationRedeemOutcome.alreadyContact);
    }
    // A DELETED record (§15.9, e.g. ended by a format reset, W-a) is no
    // contact: joining its card is the user's own explicit act and lifts the
    // mark, as accepting its request does. Until W-a the record stayed, and
    // the acceptance (3) found it `deleted` and set nothing.
    if (soFar == null || soFar.isDeleted) {
      _deletedContacts.remove(hex);
      final c = ContactInfo(
        nodeId: userId,
        displayName: kPendingContactName,
        status: 'pending_outgoing',
        ed25519Pk: addr.ed25519Pk,
        mlDsaPk: addr.mlDsaPk,
        x25519Pk: addr.x25519Pk,
        mlKemPk: addr.mlKemPk,
        requestedAt: DateTime.now(),
      )..kemRotationAt = DateTime.fromMillisecondsSinceEpoch(addr.state);
      // §15.2: the anchor right at creation — the same step as in
      // [takeMyceliumContactRequest], because here too the constructor
      // bypasses the setter.
      c.rememberFoundingAnchor(addr.ed25519Pk);
      _contacts[hex] = c;
      _saveContacts();
    }
    // ── NO CONTACT_REQUEST OF THE APP (S388-BAU-KONTAKT, B-1 = A) ────
    //
    // Name and greeting for the question are carried by the introduction
    // of request (2), acceptance follows from answer (3)
    // ([_myceliumJoinAccepted]), the profile picture from PROFILE_UPDATE
    // (§15.8). Until S388 a CONTACT_REQUEST of the app followed after that;
    // the inviter answered it a second time (measured: two
    // CONTACT_REQUEST_RESPONSE per acceptance).
    _myceliumJoinTrack(decided, hex);
    return InvitationRedeemResult(inTransit
        ? InvitationRedeemOutcome.requestSent
        : InvitationRedeemOutcome.requestResting);
  }

  /// Attaches itself to the inviter's decision (step 2 of the join,
  /// without a deadline).
  void _myceliumJoinTrack(Future<mycelium.Contact> decided, String hex) {
    final short = hex.substring(0, 8);
    unawaited(decided.then((k) {
      _log.event('mycelium:joining $short accepted');
      // S394-11: the name from the introduction in answer (3), unless
      // mycelium still only has its placeholder.
      final name = k.displayName == mycelium.contactPlaceholderName(hex)
          ? null
          : k.displayName;
      if (!_disposed) _myceliumJoinAccepted(hex, k.address, name: name);
    }, onError: (Object e) {
      _log.event('mycelium:joining $short not accepted — $e');
    }));
  }

  /// Callback `MailboxDetails.onJoinCompleted` (proposal E): a join that
  /// mycelium restored after a restart has been accepted — the future
  /// [_myceliumJoinTrack] waited for died with the old process. The same
  /// consequences as there.
  void takeMyceliumJoinCompleted(mycelium.Contact k) {
    if (_disposed) return;
    final hex = mycelium.identifierFrom(k.address);
    _log.event('mycelium:joining ${hex.substring(0, 8)} accepted after a restart');
    final name =
        k.displayName == mycelium.contactPlaceholderName(hex) ? null : k.displayName;
    _myceliumJoinAccepted(hex, k.address, name: name);
  }

  /// The inviter's answer (3) has accepted — it IS the acceptance
  /// (§15.5 "After that, both sides hold the other's verified key bundle").
  /// The app's CONTACT_REQUEST_RESPONSE can come before or after; it then
  /// only refreshes name and picture (`wasAlreadyAccepted`).
  ///
  /// Three consequences, each once:
  ///  1. the contact stands (`accepted`) — from `pending_outgoing`, or from
  ///     `pending` if the counterpart has at the same time requested us;
  ///  2. their waiting request is thereby answered (§15.5, mutual
  ///     requests) — [_myceliumOwnQuestionAnswer];
  ///  3. the own profile goes out as PROFILE_UPDATE if there is a picture
  ///     or description (the introduction only carries the name).
  void _myceliumJoinAccepted(String hex, mycelium.Address addr,
      {String? name}) {
    final c = _contacts[hex];
    if (c == null || !addressHeardTo(addr, c)) {
      _log.warn('mycelium: join to ${hex.substring(0, 8)} accepted, but '
          'no matching contact record (${c?.status}) — nothing set');
      return;
    }
    if (name != null && name.isNotEmpty && c.displayName == kPendingContactName) {
      c.displayName = name;
    }
    if (c.status == 'pending_outgoing' || c.status == 'pending') {
      final now = DateTime.now();
      c.status = 'accepted';
      c.acceptedAt ??= now;
      c.lastAckedAt = now;
      // The signed answer carries the issuer's current KEM generation; a
      // `cleona:2:` line carries none (state 1, `bundle.dart`) — the newer
      // one is adopted, as `Address.adopt` does in mycelium.
      final soFar = c.kemRotationAt?.millisecondsSinceEpoch ?? 0;
      if (addr.state > soFar) {
        c.x25519Pk = addr.x25519Pk;
        c.mlKemPk = addr.mlKemPk;
        c.kemRotationAt = DateTime.fromMillisecondsSinceEpoch(addr.state);
      }
      _saveContacts();
      _addSystemMessage(hex, noticeWithName(kNoticeContactAccepted, c.displayName),
          type: UiMessageType.identityDeleted); // system message type
      _saveConversations();
      onContactAccepted?.call(hex);
      onStateChanged?.call();
      _log.event('mycelium:contact ${hex.substring(0, 8)} accepted (answer 3)');
      // §14.7 Type 0: the requester that received the answer tells its
      // other own devices (D-28).
      _sendTwinContactAdded(c);
    }
    if (c.status != 'accepted') return;
    _myceliumOwnQuestionAnswer(c);
    if (_profilePictureBase64 != null || _profileDescription != null) {
      final profile = proto.ProfileData()
        ..updatedAtMs = Int64(DateTime.now().millisecondsSinceEpoch)
        ..displayName = displayName;
      if (_profilePictureBase64 != null) {
        profile.profilePicture = base64Decode(_profilePictureBase64!);
      }
      if (_profileDescription != null) {
        profile.description = _profileDescription!;
      }
      _detachedSend(
          'MTV3_PROFILE_UPDATE',
          sendToUser(
            recipientUserId: c.nodeId,
            messageType: proto.MessageTypeV3.MTV3_PROFILE_UPDATE,
            payload: Uint8List.fromList(profile.writeToBuffer()),
          ));
    }
  }

  /// Name in the request (§15.5). A display name over the limit of the
  /// introduction (64 B) is OMITTED, not truncated. §15.5 gives the
  /// reason: "Over-long fields are rejected on receipt, not truncated — a
  /// truncated greeting would be attributed to its sender." (Until S388
  /// the same rule stood in the profile picture branch of
  /// `sendContactRequest`; the path no longer exists, the rule does.)
  mycelium.Introduction? _myceliumIntroduction() {
    try {
      final v = mycelium.Introduction(name: displayName);
      return v.empty ? null : v;
    } on mycelium.IntroductionError catch (e) {
      _log.info('mycelium: display name does not fit into the introduction ($e) — '
          'the request goes out without a name');
      return null;
    }
  }

  /// Callback `MailboxDetails.onContactRequest` (§12.5): a request on a
  /// card of THIS identity is waiting. Here the `pending` contact for the
  /// inbox is created, and the user is asked. Decisions are made
  /// exclusively in [_myceliumRequestDecide].
  ///
  /// `kemRotationAt` stays DELIBERATELY empty: without a state the contact
  /// has no address (`addressFrom`), so the seam cannot send anything to
  /// it before the decision — a send would have remembered it in the
  /// mailbox (`_myceliumFrameSend` -> `contactRemember`), a contact without
  /// acceptance. The state is set by the acceptance.
  ///
  /// BY THE STATE OF THE PREVIOUS CONTACT RECORD (S388-BAU-KONTAKT):
  ///  * `blocked` -> nothing: no question, no answer (§15.9). The request
  ///    stays in the buffer and counts against it (§15.4 point 3).
  ///  * `accepted`, same keys -> answer without question and without
  ///    consumption (§15.5 re-contact). Different keys -> warning, level
  ///    back, NOTHING adopted (§15.8); the request waits without question.
  ///  * `pending_outgoing` (we have at the same time joined the
  ///    counterpart) -> an ordinary question (§15.5 "No special path for
  ///    simultaneous mutual requests"); the own join runs on.
  ///  * otherwise -> `pending`, question to the user.
  /// A card handed over in person (§15.5, [mycelium.ContactRequest.inPerson])
  /// is accepted without a second question — decided in THE
  /// app, via the same path as a tap on "Annehmen".
  void takeMyceliumContactRequest(mycelium.ContactRequest a) {
    if (_disposed) return;
    final who = a.who;
    final userId = userIdFrom(who);
    final hex = bytesToHex(userId);
    final short = hex.substring(0, 8);
    if (constantTimeEquals(userId, identity.userId)) {
      _log.warn('mycelium:contact request from the own identity — ignored');
      return;
    }
    final soFar = _contacts[hex];
    switch (soFar?.status) {
      case 'blocked':
        _log.event('mycelium CONTACT REQUEST from $short — blocked: no question, '
            'no answer (§15.9)');
        return;
      case 'accepted':
        // §4.5.4: a request is one of the five deliveries that can overwrite
        // a stored key — with a chain from the held keys it is a rotation,
        // adopted like any envelope carrying one (then a re-contact).
        if (!addressKeysOf(who, soFar!) && who.rotated) {
          _adoptChainedKeys(soFar, who);
        }
        if (_myceliumSameKeys(soFar, who)) {
          final ok = _myceliumRequestDecide(soFar,
              accept: true, recontact: true);
          _log.event('mycelium CONTACT REQUEST from $short — already a contact, same '
              'keys: answer without question (§15.5) -> $ok');
          return;
        }
        _myceliumKeyWarning(soFar, hex);
        return;
      case 'pending_outgoing':
        if (!addressKeysOf(who, soFar!)) {
          _log.warn('mycelium CONTACT REQUEST from $short — different keys than '
              'the card we joined: not adopted (§15.8)');
          return;
        }
    }
    final name = a.introduction?.name ?? '';
    final greeting = a.introduction?.greeting ?? '';
    _deletedContacts.remove(hex);
    final ContactInfo c;
    if (soFar != null && soFar.status == 'pending_outgoing') {
      c = soFar
        ..status = 'pending'
        ..message = greeting.isEmpty ? soFar.message : greeting;
      if (name.isNotEmpty && c.displayName == kPendingContactName) c.displayName = name;
    } else {
      c = ContactInfo(
        nodeId: userId,
        displayName: name.isEmpty ? kPendingContactName : name,
        status: 'pending',
        ed25519Pk: who.ed25519Pk,
        mlDsaPk: who.mlDsaPk,
        x25519Pk: who.x25519Pk,
        mlKemPk: who.mlKemPk,
        message: greeting.isEmpty ? null : greeting,
      );
      c.rememberFoundingAnchor(who.ed25519Pk);
      _contacts[hex] = c;
    }
    _saveContacts();
    if (a.inPerson) {
      _log.event('mycelium CONTACT REQUEST from $short on a personally '
          'handed-over card -> accepted without a second question (§15.5)');
      unawaited(acceptContactRequest(hex));
      return;
    }
    _log.event('mycelium CONTACT REQUESTfrom $short -> pending, waiting for the '
        'decision (§12.5)');
    onContactRequestReceived?.call(hex, c.displayName);
    onStateChanged?.call();
  }

  /// Does [who] carry exactly the four keys that [c] keeps?
  bool _myceliumSameKeys(ContactInfo c, mycelium.Address who) {
    bool equal(Uint8List? stored, Uint8List fresh) =>
        stored != null && constantTimeEquals(stored, fresh);
    return equal(c.ed25519Pk, who.ed25519Pk) &&
        equal(c.mlDsaPk, who.mlDsaPk) &&
        equal(c.x25519Pk, who.x25519Pk) &&
        equal(c.mlKemPk, who.mlKemPk);
  }

  /// §15.8: a request under the UserID of an accepted contact, but with a
  /// different key set. "Never adopted silently: it is shown as a
  /// warning, the contact's verification level is reset to `unverified`,
  /// and adoption requires an explicit act by the user." Nothing is
  /// adopted here; the request waits in mycelium.
  void _myceliumKeyWarning(ContactInfo c, String hex) {
    final before = c.verificationLevel;
    final change = onIdentityRotation(before);
    c.applyKeyChange(change);
    _saveContacts();
    _log.warn('§15.8: contact request from ${hex.substring(0, 8)} carries different '
        'keys than the accepted contact — NOT adopted, level '
        '$before -> ${change.newLevel}');
    try {
      onContactIdentityRotated?.call(hex, c.displayName, change.wasVerified);
    } catch (e) {
      _log.warn('onContactIdentityRotated listener threw: $e');
    }
    onStateChanged?.call();
  }

  /// The ONE decision in mycelium about the waiting request that belongs
  /// to [contact] (by the anchor, `addressHeardTo`). `null`: none is
  /// waiting (no mailbox, restart, already decided). `false`: mycelium
  /// could not decide (single-use invitation used up).
  /// [recontact]: [contact] is already accepted, with the same keys
  /// (§15.5 re-contact) — answer without consuming the invitation.
  bool? _myceliumRequestDecide(ContactInfo contact,
      {required bool accept, bool recontact = false}) {
    final p = myceliumMailbox;
    if (p == null) return null;
    for (final a in mycelium.MailboxInvitation(p).contactRequests) {
      if (!addressHeardTo(a.who, contact)) continue;
      final ok = mycelium.MailboxInvitation(p).contactRequestDecide(
          mycelium.identifierFrom(a.who),
          accept: accept,
          recontact: recontact,
          // S394-11: the own name into answer (3) — never on a rejection.
          self: accept ? _myceliumIntroduction() : null);
      if (ok && accept) {
        contact.kemRotationAt = DateTime.fromMillisecondsSinceEpoch(a.who.state);
      }
      _log.event('mycelium CONTACT REQUEST ${bytesToHex(contact.nodeId).substring(0, 8)} '
          '${accept ? 'accept' : 'reject'} -> '
          '${ok ? 'decided' : 'NOT decided'}');
      return ok;
    }
    return null;
  }

  /// `standingInvitations` — §15.3.
  StandingInvitationsResult _cardStanding() {
    final p = myceliumMailbox;
    if (p == null) {
      return const StandingInvitationsResult.unavailable(notConnected: true);
    }
    final closed = mycelium.MailboxFaceToFace(p).faceToFaceClosed;
    return StandingInvitationsResult([
      for (final e in p.identity.invitations.standing())
        StandingInvitation(
          id: _invitationId(e.code),
          kind: e.kind == mycelium.Kind.open
              ? InvitationKind.open
              : InvitationKind.single,
          expiryUnixSeconds: e.expiryUnixSeconds,
          accepted: e.accepted,
          maxAcceptances: e.atMost,
          // §15.3 "Attribution" — kept and saved since S390.
          label: e.label,
          // ES-9 (§15.4 point 2): the waiting invitation for this code
          // knows its buffer; without it (never on the wire) it is empty.
          atBufferLimit:
              p.identity.open[mycelium.hexFrom(e.code)]?.atBufferThreshold ??
                  false,
        ),
    ],
        // §15.3 "lives 60 s" (S406-QR2 2A): which face-to-face invitations
        // the service closed in this run — the view says why a code it
        // shows disappeared.
        closedFaceToFace: [
          for (final e in p.identity.invitations.all)
            if (closed.contains(mycelium.hexFrom(e.code)))
              _invitationId(e.code),
        ]);
  }

  /// `revokeInvitationCard` — §15.3.
  ///
  /// ONE step in mycelium (`MailboxInvitation.invitationRevoke`, S388):
  /// the waiting first-contact invitation reads the revocation itself
  /// (B2), a later request is silently rejected, and the revocation is
  /// saved — it survives the restart (B3). Until S388 the app additionally
  /// removed the invitation from `offene` here; that only held until the
  /// next start.
  InvitationRevokeOutcome _cardRevoke(String invitationId) {
    final p = myceliumMailbox;
    if (p == null) return InvitationRevokeOutcome.notConnected;
    for (final e in p.identity.invitations.all) {
      if (e.revoke || _invitationId(e.code) != invitationId) continue;
      mycelium.MailboxInvitation(p).invitationRevoke(e.code);
      _log.event('mycelium CARD revoked ($invitationId)');
      return InvitationRevokeOutcome.revoked;
    }
    return InvitationRevokeOutcome.unknown;
  }

  /// `revokeAllInvitationCards` — §15.3 „Bulk revocation".
  InvitationRevokeAllResult _cardAllRevoke() {
    final p = myceliumMailbox;
    if (p == null) return const InvitationRevokeAllResult.notConnected();
    final n = mycelium.MailboxInvitation(p).allInvitationsRevoke();
    _log.event('mycelium CARDS all revoked ($n)');
    return InvitationRevokeAllResult(n);
  }

  /// §15.9: the contact [c] has been deleted — the mailbox forgets it too.
  /// Without that mycelium would answer its next request as a re-contact
  /// without question (`Mailbox.requestCheck`).
  void _myceliumContactForget(ContactInfo c) {
    final p = myceliumMailbox;
    if (p == null) return;
    for (final k in List.of(p.contacts)) {
      if (!addressHeardTo(k.address, c)) continue;
      p.contactForget(k.address);
      _log.event('mycelium: contact ${bytesToHex(c.nodeId).substring(0, 8)} '
          'also forgotten in the mailbox (§15.9)');
    }
  }

  /// Is an own join to [c] running whose answer is still pending? The
  /// counter-check for a CONTACT_REQUEST_RESPONSE to a `pending` contact
  /// (mutual requests, §15.5).
  bool _myceliumJoinRunsTo(ContactInfo c) {
    final p = myceliumMailbox;
    if (p == null) return false;
    return p.identity.joins.any((b) {
      final g = b.counterpart;
      return g != null && !b.declined && addressHeardTo(g, c);
    });
  }

  /// §15.5: [c] has just become a contact (answer to the own join). If a
  /// request from them on an OWN card is waiting at the same time (mutual
  /// requests), it is thereby answered — it gets the answer instead of
  /// remaining as a second question. The invitation is consumed in the
  /// process: the one it was issued for has been accepted.
  void _myceliumOwnQuestionAnswer(ContactInfo c) {
    final ok = _myceliumRequestDecide(c, accept: true);
    if (ok == null) return;
    _log.event('mycelium: waiting request from '
        '${bytesToHex(c.nodeId).substring(0, 8)} answered with the acceptance '
        '(mutual, §15.5) -> ${ok ? 'decided' : 'NOT decided'}');
  }
}
