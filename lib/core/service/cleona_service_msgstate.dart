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

extension V3MessageStateOps on CleonaService {

  // ─────────────────── V4.1 DELIVERY STATUS (§9.2, D2) ───────────────────
  //
  // WHAT WAS MISSING HERE, and why it is not a formality. `DeliveryState`,
  // `DeliveryRecord` and the receipt check had stood since S346 in
  // `lib/core/tagline/delivery_state.dart` and had NO caller in all of
  // `lib/` — recounted on 2026-08-30: outside their own file the symbols
  // only occurred in `test/smoke/`, and the guard
  // `smoke_tagline_lab_only_guard.dart` listed them explicitly as a known
  // gap ("der Zustellstatus der Anwendung haengt noch am V3-Pfad").
  //
  // The delivery status thus ran entirely via `_handleDeliveryReceiptV3`
  // further down — and that flipped the display to `delivered` as soon as
  // a receipt frame with a matching message identifier arrived, WITHOUT
  // looking at the verdict about the sender. Recounted: `senderTrust` does
  // not occur in the whole handler. Exactly that is ruled out by D2:
  // "Only the recipient, holding `K_AB`, can produce a receipt that flips
  // the sender's 'delivered' state. … This closes silent deletion."
  //
  // The case is reachable and not theoretical: `acceptV41Frame` DISCARDS
  // only what is demonstrably forged (`V41SenderVerdict.forged`). If `K_AB`
  // cannot be formed at all on reception — no contact record, e.g. a group
  // member without its own entry —, the verdict is `unverifiable`, the
  // frame goes on and carries `SenderTrust.unknownKey`. Up to here it
  // flipped the display nonetheless.
  //
  // HOW THE TWO SOURCES COME TOGETHER without staying two: `MessageStatus`
  // stays the DISPLAY value — it carries `sending`/`sent`/`read`/`expired`,
  // i.e. states that the delivery layer does not know at all. The register
  // alone decides the ONE question for which §9.2 has a rule: may the
  // transition to `delivered` take place? The answer then stands in ONE
  // place — in the record — and not once per receive path.
  //
  // BOTH PATHS FEED THE SAME REGISTER, and that is not carelessness towards
  // §9.2 but its condition. A receipt coming back via V4.1 proves `K_AB`
  // through the frame MAC (§4.4.3); one coming back via V3 proves the same
  // sender through KEM and user signature against the contact registry —
  // and whoever can sign with that can derive `K_AB` from the founding keys
  // (§15.2). Both are a cryptographic attribution to the PAIR PARTNER, and
  // only that is required by D2; the relay against which the paragraph is
  // written has neither the one nor the other. Accepting only the V4.1
  // path would have nailed a message acknowledged via V3 permanently to
  // `sent` — a stuck status is no security gain.
  //
  // If the register does NOT know an identifier (V3 send path, or long
  // displaced), the previous behaviour remains. A cap must not permanently
  // nail a message to "not delivered".

  /// Notes what became of a V4.1 send attempt.
  ///
  /// ACCEPTED MEANS `placing`, not `placed`. `SendOutcome.legs` counts, for
  /// secure, the families that `V41Node.placeSecure` QUEUED
  /// (`egress.stream.enqueueControl`) — not those whose deposit a relay
  /// has confirmed. The difference is the same that the send site records
  /// with "'Queued' is not 'placed'". Mapping `legs` to `notePlaced` here
  /// would mean claiming a placement confirmation that nobody gave.
  ///
  /// REJECTED MEANS `failed`, and only that. Each of the three rejections
  /// from [SendRefusal] says that NOTHING went out: no pair key
  /// (`noPairKey`), too large for splitting (`tooLarge`), no confirmed
  /// relay (`notReady`). That is exactly the condition that
  /// `DeliveryRecord.markFailed` demands — "NOT for offline recipients". A
  /// recipient that does not harvest does not occur here at all: for them
  /// the cell lies in the network, and the record stays at `placing` until
  /// the receipt flips it.
  void _v41NoteSend(Uint8List messageId, SendOutcome outcome) {
    final record = v41Deliveries.open(messageId.hex, messageId);
    if (!outcome.accepted) {
      record.markFailed();
      return;
    }
    // THE RECORD MUST KNOW INTO HOW MANY PIECES THIS SEALING BROKE — else
    // it can say nothing about the MESSAGE, only about individual pieces.
    // And it must know WHICH attempt it was: a resubmission (§5.1) seals
    // freshly, and proofs of different attempts do not combine at the
    // receiver.
    record.noteAttempt(outcome.transferId, outcome.pieces);
  }

  /// Books a confirmed deposit in the delivery register.
  ///
  /// ── THE PRODUCER OF `placed` (§22.5.1) ───────────────────────────
  ///
  /// Until S357 `DeliveryRecord.notePlaced` had no caller, and the state
  /// was unreachable: the placement receipt only carried the tag, and that
  /// is the same for all messages of the same pair in the same epoch — an
  /// assignment would have been guessed. It now carries an identifier per
  /// leg and a MAC that only the storing relay can form; the delivery
  /// layer passes back message, attempt, piece, family, relay and its
  /// network blocks.
  ///
  /// NOTHING IS CALCULATED HERE. The rule — every piece, independent
  /// relays, one attempt — stands in the record itself; this place is only
  /// the seam. Whoever rebuilt it here as a secondary would have two
  /// verdicts about the same state.
  ///
  /// An unknown identifier is NOT an error: the register is capped
  /// (`maxRecords`), and a displaced record takes its receipts with it.
  void noteV41Placement(PlacementAck ack) {
    final record = v41Deliveries.lookup(ack.messageId.hex);
    if (record == null) return;
    record.notePlaced(
      transferId: ack.transferId,
      piece: ack.piece,
      family: ack.family,
      relay: ack.relay,
      partitions: ack.partitions,
    );
    // ── AND INTO THE DISPLAY (§21.5.5, S376) ───────────────────────────
    //
    // THIS STEP WAS MISSING HERE. The record moved to `placed`, the outbox
    // let go of the entry — and the `UiMessage` stayed on `placing`,
    // because it was only touched at the send edge. `placed` was thus a
    // state that §21.5.5 lists and that no user ever saw.
    //
    // BEFORE the outbox release and not after: both read the same
    // `record.state`, but the release logs and writes: if it died, the
    // display would already be right. The reverse order would leave a
    // message with an empty ledger standing on `placing` — the state that
    // nobody can move any more.
    _v41ReflectStatus(ack.messageId.hex);
    // ── AND WITH THAT IT LEAVES THE OUTBOX (§21.2) ────────────────────
    //
    // "The cell remains in the local outbox until >= 2 placement
    // acknowledgments from independent relays are in hand." EXACTLY THAT
    // is the condition, and it is not recalculated here, but READ OFF the
    // record: `DeliveryRecord.state` keeps the three rules (independent
    // relays per §9.1 network block, EVERY piece, ONE attempt) in ONE
    // place. A second calculation here would be the double bookkeeping the
    // header of this file warns against — and it could drift in exactly
    // the direction that lets `placed` be claimed without a proof behind it.
    //
    // `redundant` is the tightening of `placed`, `delivered` lies beyond
    // it — all three are "proven enough to leave the ledger".
    switch (record.state) {
      case DeliveryState.placed:
      case DeliveryState.redundant:
      case DeliveryState.delivered:
        if (v41Outbox.remove(ack.messageId.hex)) {
          saveV41Outbox();
          _log.debug('V4.1-Outbox: ${ack.messageId.hex.substring(0, 8)} is '
              'proven (${record.independentRelays} independent relays) and '
              'leaves the book');
        }
      case DeliveryState.placing:
      case DeliveryState.failed:
        break;
    }
  }

  /// Drains the local outbox (§21.2) — at an EDGE, never on a clock.
  ///
  /// ── WHY NO TIMER (§5.1 invariant 1) ──────────────────────
  ///
  /// §21.2 says "no timer retry", and §5.1 says why: "A real cell
  /// *replaces* an already-scheduled dummy slot; it does not add a
  /// cell." An own rhythm for the resubmission would be recognisable as
  /// such on the wire and would break egress indistinguishability.
  /// This method therefore produces NO traffic beyond the cover clock: it
  /// queues into the same control queue from which the slot clock draws
  /// exactly one cell per `kSlotInterval` = 8 s anyway.
  ///
  /// ── THE THREE EDGES, AND WHY EACH PROVES THAT NOTHING LIES ────
  ///
  ///   * **Restart.** Control queue (`CoverStream._control`) and delivery
  ///     register (`V41DeliveryRegister._records`) are both bare maps in
  ///     memory; an entry loaded from `v41_outbox.json` has no proof by
  ///     construction.
  ///   * **Readiness change.** The previous attempt ended with
  ///     `SendRefusal.notReady` — `placeSecure` returned 0, NOTHING went
  ///     out. Exactly that changes when a relay confirms. This is the V4.1
  ///     counterpart of the V3 edge `onNetworkChanged`.
  ///   * **Proven inbound from the counterpart** (§5.1 F3'): the
  ///     counterpart is demonstrably reachable.
  ///
  /// ── HOLDING IS NOT SENDING ───────────────────────────────────────
  ///
  /// ONLY what has `independentRelays == 0` is resubmitted. With ONE
  /// receipt present, resubmission would be strictly worse than holding:
  /// `DeliveryRecord.noteAttempt` DELETES the proofs of the previous
  /// attempt (§22.5.1 refinement 3 — "acknowledgments from different
  /// sealing attempts do not combine"), so the resubmission would cost 60
  /// cells AND destroy the one proof one had. The cell meanwhile lies at
  /// the acknowledging relay and waits for the harvest — case (j) from §9.2.
  ///
  /// Returns how many entries actually went out again.
  int flushV41Outbox({required String reason}) {
    final v41 = v41Delivery;
    final host = v41Host;
    if (v41 == null || host == null) return 0;
    if (v41Outbox.length == 0) return 0;

    // THE EGRESS CAP. Without information from the node NOTHING is
    // guessed: then nothing drains. An assumed free slot that does not
    // exist makes `CoverStream` discard the oldest group — and that could
    // be a message that is in transit regularly right now.
    final deep = v41PendingControl?.call();
    final cap = v41ControlBacklogLimit?.call();
    if (deep == null || cap == null) return 0;
    final free = cap - deep;
    if (free < CleonaService._v41SecureFramesPerOffer) {
      _log.debug('V4.1-Outbox ($reason): control queue $deep/$cap — '
          'no room for a resubmission '
          '(${CleonaService._v41SecureFramesPerOffer} frames)');
      return 0;
    }

    final due = v41Outbox.due(
      // THE VERDICT STANDS IN THE RECORD, NOT HERE. `DeliveryRecord` keeps
      // the three rules of §22.5.1 in ONE place; a second calculation would
      // be the double bookkeeping the header of this file warns against.
      //
      // IF THE REGISTER DOES NOT KNOW THE IDENTIFIER, "no proof" applies —
      // exactly the case after a restart, and that is the main case of
      // this method.
      hasProof: (idHex) =>
          (v41Deliveries.lookup(idHex)?.independentRelays ?? 0) > 0,
      freeFrame: free,
      frameProTemplate: CleonaService._v41SecureFramesPerOffer,
    );
    if (due.isEmpty) return 0;

    var out = 0;
    for (final e in due) {
      try {
        if (_v41Resubmit(e, v41, host)) out++;
      } catch (ex, st) {
        // A SINGLE ENTRY MUST NOT STOP THE DRAIN.
        // `v41PairKeyFor` and `v41OutDirectionFor` THROW when the founding
        // keys are missing (deleted contact, rotated identity). Without
        // this latch such an entry would tear every further resubmission
        // down with it — and the throw would run out of an edge callback
        // into the daemon's zone handler, which does not classify it as
        // survivable (`exit(99)`).
        _log.error('V4.1-Outbox: ${e.messageIdHex.substring(0, 8)} '
            '(${e.messageType}) cannot be resubmitted: $ex\n$st');
      }
    }
    if (out > 0) {
      saveV41Outbox();
      _log.event('V4.1-Outbox ($reason): $out of ${v41Outbox.length} '
          'entries resubmitted, queue $deep/$cap');
    }
    return out;
  }

  /// Resubmits ONE entry. `true` if it was accepted.
  ///
  /// It is the same call that `sendToUser` makes — with stored values
  /// instead of freshly resolved ones. NO second send path: whoever called
  /// `seal()` or `delivery.send` directly here would skip the prekey draw
  /// and the splitting, and both have been expensive once already.
  bool _v41Resubmit(V41OutboxEntry e, V41Delivery v41, V41Host host) {
    final contactHex = e.recipientUserId.hex;
    final contact = _contacts[contactHex];
    final peer = _v41PeerKey(e.recipientUserId);
    v41.rememberPeer(peer, v41PairKeyFor(e.recipientUserId, contact),
        outDirection: v41OutDirectionFor(e.recipientUserId, contact));

    // THE KEYS: first the stored overrides (the group member without a
    // contact record), then the contact record. The same order as in
    // `sendToUser`, and it must be the same — otherwise the resubmission
    // seals against different keys than the first attempt.
    final x = e.x25519Pk ?? contact?.x25519Pk;
    final m = e.mlKemPk ?? contact?.mlKemPk;
    if (x == null || m == null) {
      _log.warn('V4.1-Outbox: ${e.messageIdHex.substring(0, 8)} has no '
          'KEM keys any more (contact deleted?) — stays until the '
          'deadline');
      return false;
    }
    host.rememberPeerKeys(peer, x25519: x, mlKem: m);

    // ── THE MODE IS READ AGAIN, NOT REPEATED ─────────────────
    //
    // It never stood in the ledger, and that is intentional (see
    // `v41_outbox.dart`). A chat set to secure in the meantime must not
    // execute a stored speed decision — that would be the silent mode
    // switch that the invariant (owner, 30.08.) forbids. The opposite
    // direction would be just as wrong: a stored secure decision would cost
    // 60 cells for a chat that has long been on speed.
    //
    // `skipL3` and `ephemeral` are both `false`: ephemeral kinds do not
    // get into the ledger at all, and a signalling that needs a
    // resubmission no longer is one.
    // NO MODE INPUT ANY MORE (S389, §3.3/§12.1). Here
    // `Contact.secureMode`/`Group.secureMode` was read again; the switch
    // is gone. The constant is `true` for the same reason as in the send
    // path (`cleona_service.dart`, `secureDesired`): of the two possible
    // constants the hard rule only allows the protecting direction.
    const secureDesired = true;
    final mode = sendMode(
      secureDesired: secureDesired,
      skipL3: false,
      ephemeral: false,
    );
    if (mode == null) return false;
    v41.setChatMode(peer, secure: secureDesired);

    final outcome = host.sendFrame(
      peer: peer,
      // EXACTLY THE BYTES OF THE FIRST ATTEMPT. Sealing happens FRESHLY
      // (new ephemeral key, new one-time prekey, new splitting) — `sendFrame`
      // does that by itself. What MUST stay the same is the plaintext frame:
      // it carries the message identifier under which the other side
      // acknowledges.
      frame: e.frame,
      mode: mode,
      now: DateTime.now().toUtc(),
      messageId: e.messageId,
      // THE CLASS COMES FROM THE LEDGER, NOT FROM THE TYPE. Unlike the mode
      // it is NOT decided again: it belongs to the message, not to the
      // state of the chat. And it cannot be derived —
      // `MTV3_KEY_ROTATION_BROADCAST` carries routine as well as emergency
      // rotation (v41_outbox.dart, [V41OutboxEntry.management]).
      management: e.management,
    );
    // THE RECORD IS RESET, and that is the truth, not a loss:
    // `noteAttempt` discards the proofs of the previous attempt, because
    // its cells carry a different seal and cannot be combined with those
    // of this attempt (§22.5.1 ref. 3).
    _v41NoteSend(e.messageId, outcome);
    if (!outcome.accepted) {
      _log.debug('V4.1-Outbox: ${e.messageIdHex.substring(0, 8)} rejected '
          'again ($outcome) — stays in the book');
      return false;
    }
    // ONLY COUNT NOW. If the counter were increased before sending, a
    // rejection would also use up an attempt, and the cap would run empty
    // without anything ever going out.
    v41Outbox.markOffered(e.messageIdHex);
    // ── AND INTO THE DISPLAY (S376) ────────────────────────────────────
    //
    // `_v41NoteSend` further up has reset the record to `placing`
    // (`noteAttempt` discards the proofs of the previous attempt). Without
    // this line the display stayed on the old value — for a message that
    // was `failed` before, the user never saw the second attempt, although
    // §12 explicitly offers them a "Resend" for it.
    _v41ReflectStatus(e.messageIdHex);
    _log.event('V4.1-Outbox: ${e.messageType} to ${shortPairLabel(peer)} '
        'resubmitted (${e.frame.length} B, ${mode.name}, attempt '
        '${e.offers}/$kMaxOutboxOffers) — $outcome');
    return true;
  }

  /// Takes an arrived delivery receipt into the register.
  ///
  /// [verified] is the verdict about THIS frame, and depending on the path
  /// a different proof of the same statement "the frame comes from the
  /// pair partner": via V4.1 the frame MAC under `K_AB` (`verifyV41Sender`
  /// -> `V41SenderVerdict.verified`), via V3 the user signature
  /// (`SenderTrust.verified`). If it is `false`, the receipt is none per
  /// §9.2, and the record stays where it is. It is therefore not logged
  /// either: a receipt without proof is not an event about which anything
  /// could be said.
  ///
  /// THE IDENTIFIER STANDS IN THE BODY OF THE RECEIPT, not in the frame:
  /// the frame's `messageId` is the identifier of THIS receipt,
  /// `DeliveryReceipt.messageId` that of the acknowledged message. The
  /// body is unpacked here a second time (the handler below does it
  /// anyway) — that is cheaper and more honest than passing the verdict
  /// across `handleApplicationFrame` in a field that only this one type
  /// needs.
  /// Does THIS delivery receipt prove that the counterpart possesses our
  /// day capsule?
  ///
  /// Only if it refers to a message that WE sent sealed via V4.1. Whoever
  /// could open one of our V4.1 frames had the day secret — either the
  /// capsule rode along, or they knew it already. Both are possession, and
  /// only possession may switch off the capsule.
  ///
  /// ── WHAT THE OLD CONCLUSION COST (30.08. in the field) ──────────────
  ///
  /// Up to here ANY delivery receipt sufficed. But a receipt proves
  /// delivery, not the opening of a seal — and it also comes for messages
  /// that were delivered via the V3 path. Measured: Alice received a
  /// receipt from the phone at 11:41:53, her FIRST V4.1 send of this run
  /// was at 11:47:10, i.e. six minutes later. The receipt could not
  /// possibly be for a V4.1 frame. It switched off the capsule anyway;
  /// Alice's frames were then 642 B instead of 1152+, the capsule branch
  /// in the opener (`message_seal.dart`) never took hold, and because
  /// `MessageOpener._secrets` only lives in memory and the phone had been
  /// reinstalled 20 minutes before, EVERY secure message in this direction
  /// was unopenable — visible as `V4.1 UNGEOEFFNET … Selektor passte, AEAD
  /// fiel`. Until UTC midnight, because the confirmation key carries the
  /// day.
  ///
  /// [verified] belongs to it and did not stand in front of it before: a
  /// receipt without proof is none per §9.2, and it may all the less
  /// switch off the capsule — that would be a way to take delivery away
  /// from a pair for the rest of the day.
  ///
  /// Falls back to "not proven" when in doubt: sending the capsule along
  /// further costs 1088 B, switching it off too early costs the day.
  bool _v41ReceiptProvesCapsule(List<int> receiptPayload,
      {required bool verified}) {
    if (!verified) return false;
    try {
      final receipt = proto.DeliveryReceipt.fromBuffer(
          Uint8List.fromList(receiptPayload));
      if (receipt.messageId.isEmpty) return false;
      return v41Deliveries.lookup(receipt.messageId.hex) != null;
    } catch (_) {
      return false;
    }
  }

  void _v41NoteReceipt(List<int> receiptPayload, {required bool verified}) {
    if (!verified) return;
    try {
      final receipt = proto.DeliveryReceipt.fromBuffer(
          Uint8List.fromList(receiptPayload));
      if (receipt.messageId.isEmpty) return;
      // S387: the receipt is already proven here (`verified`) — for a
      // message sent via mycelium this is noted in the mailbox index.
      _myceliumReceiptMark(receipt.messageId.hex);
      v41Deliveries
          .lookup(receipt.messageId.hex)
          ?.noteReceiptAuthenticatedByFrame();
      // DELIVERED INCLUDES PROVEN (§21.5.5: "`placed` -> `delivered`
      // only on a harvested delivery-receipt cell"). Whoever acknowledges
      // has harvested, so the cell lay there — the entry has no business
      // in the ledger any more, even if two placement receipts never
      // arrived.
      //
      // THIS IS NO CONTRADICTION TO "receipts have no influence on this"
      // (§21.5.5, line 7419). What it says there is that the receipt does
      // not produce the STATE `placed` — it does not replace the placement
      // proof. HOLDING a message that the receiver has demonstrably read
      // would, by contrast, be pointless: the resubmission would cost 60
      // cells for something that has arrived.
      if (v41Outbox.remove(receipt.messageId.hex)) saveV41Outbox();
    } catch (_) {
      // A malformed body carries no information (E-83). The handler below
      // catches the same case and logs it there.
    }
  }

  /// May the display for [messageIdHex] switch to `delivered`?
  ///
  /// `true` also when the register does NOT know the identifier — see the
  /// block header: that is the V3 path and the displaced record, not a
  /// missing receipt.
  bool _v41DeliveryProven(String messageIdHex) {
    final viaMycelium = _myceliumDeliveryProven(messageIdHex);
    if (viaMycelium != null) return viaMycelium;
    final record = v41Deliveries.lookup(messageIdHex);
    return record == null || record.state == DeliveryState.delivered;
  }

  /// The display status that the delivery register PROVES for
  /// [messageIdHex].
  ///
  /// `null` means "the register does not know the identifier" — the V3
  /// send path (`kBulkTypes`, first-contact types) or a long displaced
  /// record. Then the previous value stays; a cap must not nail a message
  /// to a state.
  MessageStatus? _v41StatusFor(String messageIdHex) {
    // S387: a message sent via mycelium keeps its state in the mailbox, not
    // in the V4.1 register (`cleona_service_mycelium.dart`).
    final viaMycelium = _myceliumStatusFor(messageIdHex);
    if (viaMycelium != null) return viaMycelium;
    final record = v41Deliveries.lookup(messageIdHex);
    if (record == null) return null;
    // THREE REGISTER STATES ONTO ONE DISPLAY STATE, and that is the spec
    // and not an imprecision: §9.1 says "`in transit` deliberately
    // covers 'lying in a post box'. A sender does not learn, and does not
    // need to learn, which rung of the ladder carried the packet."
    // `placing` (out, nothing lies), `placed` (two independent deposits)
    // and `redundant` (all families) are three strengths of THE SAME
    // statement "in transit, no receipt from the receiver yet". The number
    // of families stays in the record and is not lost.
    switch (record.state) {
      case DeliveryState.placing:
      case DeliveryState.placed:
      case DeliveryState.redundant:
        return MessageStatus.inTransit;
      case DeliveryState.delivered:
        return MessageStatus.delivered;
      case DeliveryState.failed:
        return MessageStatus.failed;
    }
  }

  /// Catches up the status of an OUTGOING message from the delivery
  /// register — the only source that v4_1 §22.5.1 permits for it.
  ///
  /// [legIdsHex] are the identifiers under which the legs of this message
  /// were sent: for a 1:1 message exactly one, for the group fan-out one
  /// per member (`UiMessage.fanoutLegs`).
  ///
  /// AGGREGATE OVER THE WEAKEST LEG (§21.5.5 "Aggregation per leg").
  /// `failed` is NOT the weakest here, but a class of its own: it only
  /// applies if NO known leg lay anywhere. A single unplaceable leg next
  /// to a placed one does not turn the message into an error — and a
  /// receiver that does not harvest does not occur here at all (it stands
  /// on `placing`, not on `failed`).
  /// Returns `true` if the display status ACTUALLY changed — since S376
  /// whether `onStateChanged` fires hangs on that.
  bool _v41ApplyOutgoingStatus(UiMessage msg, List<String> legIdsHex) {
    // ── THE INDEX IS KEPT HERE (S376, P5 finding 2) ─────────────
    //
    // At this place and only here, because both are present at once here:
    // the message and the wire identifiers of its legs. It thus fills up
    // on the same path by which a message gets into the delivery register
    // at all — there is no send path that does the one without the other.
    for (final id in legIdsHex) {
      _v41LegIndex[id] = (convId: msg.conversationId, msgId: msg.id);
    }
    while (_v41LegIndex.length > CleonaService._v41LegIndexMax) {
      _v41LegIndex.remove(_v41LegIndex.keys.first);
    }

    final known = <MessageStatus>[];
    for (final id in legIdsHex) {
      final s = _v41StatusFor(id);
      if (s != null) known.add(s);
    }
    if (known.isEmpty) return false;
    final placed =
        known.where((s) => s != MessageStatus.failed).toList();
    final fresh = placed.isEmpty
        ? MessageStatus.failed
        : placed.reduce((a, b) => _statusRank(a) <= _statusRank(b) ? a : b);
    if (msg.status == fresh) return false;
    if (msg.status.canTransitionTo(fresh)) {
      msg.status = fresh;
      // §21.4.1: every change to a message goes into the store.
      // `conversationId` stands at the object itself — the method does not
      // get it passed through, and pulling it from the caller would be a
      // second source for the same fact.
      persistMessage(msg.conversationId, msg);
      return true;
    }
    return false;
  }

  /// Carries the register state for ONE leg over into the display.
  ///
  /// ══════════════════════════════════════════════════════════════════
  /// WHY THIS METHOD EXISTS (S376, P5 finding 2)
  /// ══════════════════════════════════════════════════════════════════
  ///
  /// Until S376 [_v41ApplyOutgoingStatus] ran at EXACTLY TWO places, and
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
  /// passes it with ALL its legs to [_v41ApplyOutgoingStatus] — the same
  /// calculation as at the send edge, no second verdict.
  ///
  /// ── A NOTIFICATION ONLY ON A REAL CHANGE ───────────────────────────
  ///
  /// Up to `m x R` = 60 receipts per message (§9.2); one `onStateChanged`
  /// per receipt would be 60 redraws of the list for at most two visible
  /// transitions. `_v41ApplyOutgoingStatus` therefore reports whether
  /// something has changed, and only then does the notification go out.
  void _v41ReflectStatus(String legIdHex) {
    final place = _v41LegIndex[legIdHex];
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
      _v41LegIndex.remove(legIdHex);
      return;
    }
    // ALL LEGS: for 1:1 the display identifier is at the same time the
    // wire identifier, for the fan-out it stands in `fanoutLegs`.
    final legs = msg.fanoutLegs.isEmpty
        ? <String>[msg.id]
        : msg.fanoutLegs.values.toList();
    if (_v41ApplyOutgoingStatus(msg, legs)) {
      onStateChanged?.call();
    }
  }


  /// Check for expired messages and delete them.
  void _checkMessageExpiry() {
    final now = DateTime.now().millisecondsSinceEpoch;
    var changed = false;

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
    // fallen. If an entry drops out here, `_v41StatusFor` returns `null`
    // for its identifier, and `null` means explicitly "the cap nails no
    // message to a state": the display keeps its last value.
    final expired = v41Outbox.sweep(
        nowMs: now, ttlMs: CleonaService._placementTtlMs);
    if (expired > 0) {
      saveV41Outbox();
      _log.info('V4.1-Outbox: $expired entries beyond the '
          '14-day deadline taken out (storage cap, no '
          'state change — §9.3)');
    }

    for (final conv in conversations.values) {
      final expiryMs = conv.config.expiryDurationMs;
      if (expiryMs == null || expiryMs <= 0) continue;

      ensureAllLoaded();
      for (final msg in conv.messages) {
        if (msg.isDeleted) continue;
        if (msg.readAt == null) continue;
        final elapsed = now - msg.readAt!.millisecondsSinceEpoch;
        if (elapsed >= expiryMs) {
          msg.text = '';
          msg.isDeleted = true;
          changed = true;
          persistMessage(conv.id, msg);
          _log.debug('Message ${msg.id.substring(0, 8)} expired after ${elapsed}ms');
        }
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
  // The cleanup of the outbox (`v41Outbox.sweep` in `_checkMessageExpiry`)
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
  void _handleDeliveryReceiptV3(HarvestEvent event, {bool wasDirect = false}) {
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
      // delivery status of the message flips directly to `delivered` here,
      // and the V4.1 placement confirmation
      // (`PlacementAck` -> `V41Delivery.bindPlacementAcked`) flips it to
      // `placed` before. The difference to V3 is that there is NO timer any
      // more that notices a missing reception: V4.1 knows no deadline on
      // the delivery path (§22.5.1), because the cell stays with the
      // responsible relays until it is harvested. A receiver that stayed
      // offline is not an error.
      //
      // Nothing in route selection hangs on this place any more — there
      // are no routes, no address rating and no resubmission any more that
      // could learn from it.

      // A5: DELIVERY_RECEIPT proves end-to-end contact liveness
      final senderUserHex = event.senderUserId.hex;
      final senderContact = _contacts[senderUserHex];
      if (senderContact != null) {
        senderContact.lastAckedAt = DateTime.now();
        _staleWarningWrittenFor.remove(senderUserHex);
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
      // THE ONE QUESTION THAT THE DELIVERY REGISTER DECIDES (§9.2, D2).
      // See the block header of this file: for a message sent via V4.1 the
      // display only flips if the receipt frame was authenticated under
      // `K_AB`. For everything else the answer is `true`, and the following
      // line is then exactly the one from before.
      //
      // NO STEP BACK FOR MIXED NETWORKS, and that is recalculated: only
      // what `routeFor` sent to `DeliveryRoute.v41` is registered. Whoever
      // could open such a message at all possesses `K_AB` and answers via
      // the same path — `MTV3_DELIVERY_RECEIPT` stands neither in
      // `kBootstrapTypes` nor in `kBulkTypes` (see
      // `_receiptReturnsOverV41`). A counterpart without `K_AB` could never
      // have read the message and has nothing to acknowledge.
      // ── THE DELIVERY REGISTER, ENTERED AND THEN ASKED (§9.2, D2) ──
      //
      // What is entered here is the V3 proof: `SenderTrust.verified` means
      // that KEM unpacking and user signature held against the contact
      // registry — the frame comes from the pair partner. The stronger V4.1
      // proof (frame MAC under `K_AB`) is already entered at this point;
      // `acceptV41Frame` does it before handing over here; a second entry
      // of the same verdict changes nothing.
      //
      // WHY NOT SIMPLY QUERY `event.senderTrust` HERE and omit the record:
      // then the rule would stand in two places — here and in the fan-out
      // branch in `cleona_service_receive.dart` —, and the one could change
      // without the other following. The record is the one place.
      _v41NoteReceipt(event.payload,
          verified: event.senderTrust == SenderTrust.verified);
      final deliveryProven = _v41DeliveryProven(msgIdHex);

      // ── AND: WAS THIS A LEG OF A LOCK-OUT ANNOUNCEMENT? (E-7) ────
      //
      // AFTER `_v41NoteReceipt`, not before: there the record in the
      // register is flipped, here what it says is read. The question "is
      // this receipt proven?" is thus answered at exactly ONE place (§9.2,
      // D2) and not a second time in the lock-out path. If the register
      // does not know the leg, the contact stays pending — the justified
      // strictness stands at `_v41DeliveryProvenForLockout`.
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

/// Ranking of the display states for the leg aggregate (§9.5: "groups
/// show the weakest state over all members").
///
/// Only the three steps that an OUTGOING leg can take on its way forward.
/// `failed` is not a step of this ladder, but a class of its own (§9.1:
/// "no way carried it") and is sorted out by the caller beforehand — a
/// single uncarried leg next to a carried one does not turn the message
/// into an error.
int _statusRank(MessageStatus s) => switch (s) {
      MessageStatus.resting => 0,
      MessageStatus.inTransit => 1,
      MessageStatus.delivered => 2,
      MessageStatus.failed => -1,
    };
