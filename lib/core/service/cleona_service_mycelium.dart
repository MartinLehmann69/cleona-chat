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
// no device line (multi-device is not a subject of the rebuild, S383),
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
  /// (`importPeerBundle`); the start paths run it themselves once per
  /// event and pass `false`.
  void myceliumAttach(mycelium.Mailbox p) {
    myceliumMailbox = p;
    port = p.port;
    v41OnNetworkChanged = () => p.host.networkChanged();
    _log.info('mycelium:mailbox ${p.ownIdentifier.substring(0, 8)} '
        'attached, port ${p.port}');
    _myceliumParkedHandedOver();
    _myceliumNeverFixedNeighbourHandedOver(p);
    onStateChanged?.call();
  }

  /// Detaches the mailbox from the service and returns it (for
  /// `Host.deregister`).
  mycelium.Mailbox? myceliumDetach() {
    final p = myceliumMailbox;
    myceliumMailbox = null;
    v41OnNetworkChanged = null;
    return p;
  }

  /// What was sent before the attach (`startService` sends before the
  /// host is up) lies in the outbound compartment (§21.2, `sendToUser`
  /// no-carrier branch). It is handed over here ONCE to the mailbox and
  /// leaves the compartment: from then on the mailbox history is the
  /// ledger, and it resubmits at its own edges. Two ledgers for the same
  /// message would drift apart.
  void _myceliumParkedHandedOver() {
    if (v41Outbox.length == 0) return;
    var handedOver = 0;
    for (final e in v41Outbox.entries.toList()) {
      final contact = _contacts[e.recipientUserId.hex];
      final a = _myceliumFrameSend(
        recipientUserId: e.recipientUserId,
        contact: contact,
        frame: e.frame,
        messageIdHex: e.messageIdHex,
        typeName: e.messageType,
      );
      if (a == null) continue;
      v41Outbox.remove(e.messageIdHex);
      handedOver++;
    }
    if (handedOver > 0) {
      saveV41Outbox();
      _log.event('mycelium:$handedOver parked message(s) handed over to the '
          'mailbox, ${v41Outbox.length} remain in the compartment');
    }
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
  }) async {
    if (isSelfSend) {
      // §22.5.2 lists the twin sync as `sendToUser` to the own UserID.
      // mycelium has no own line — multi-device is not a subject of the
      // rebuild (S383). Named, not silent.
      _log.warn('mycelium: self-send ${messageType.name} — mycelium carries '
          'no own line (multi-device, S383). Not sent.');
      return false;
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
    );
    final a = _myceliumFrameSend(
      recipientUserId: recipientUserId,
      contact: contact,
      frame: Uint8List.fromList(inner.writeToBuffer()),
      messageIdHex: id.hex,
      typeName: messageType.name,
      ephemeral: CleonaService.kV41Ephemeral.contains(messageType),
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
  }) {
    final p = myceliumMailbox;
    if (p == null) return null;
    final short = CleonaService._hexShort(recipientUserId);
    if (contact == null) {
      // A group member without a contact record carries only KEM keys
      // (overrides from GROUP_INVITE). A mycelium address needs the signing
      // keys — without them it would be sealed against a receiver whose
      // identity nobody proves.
      _log.warn('mycelium: $typeName to $short — no contact record, so no '
          'address. Not sent.');
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
    _myceliumOutbounds[messageIdHex] = a;
    while (_myceliumOutbounds.length > _kMyceliumOutboundsMax) {
      _myceliumOutbounds.remove(_myceliumOutbounds.keys.first);
    }
    // The state the mailbox set just now (`inTransit`, or `resting` without
    // a way) goes into the display at once — not only when the caller of
    // `sendToUser` gets control back (§12.2: the ONE tick must be visible).
    _v41ReflectStatus(messageIdHex);
    // VISIBLE like "V4.1 SENDEN": without the counterpart to reception it
    // is impossible to tell in the field whether nothing went out at all.
    _log.event('mycelium SEND$typeName to $short (${frame.length} B) — '
        '${a.state.name}');
    return a;
  }

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
    final senderHex = bytesToHex(sender);
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
            'the envelope is not signed with the keys of the '
            'contact. Discarded, not downgraded.');
        return;
      }
      trust = OuterSigStatus.verified;
    } else if (!constantTimeEquals(userIdFrom(e.from), sender)) {
      _log.warn('mycelium drop: frame names sender '
          '${senderHex.substring(0, 8)}, the envelope is signed by a '
          'different identity. Discarded.');
      return;
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
    if (!decided) {
      _log.warn('mycelium drop: ${frame.messageType.name} from '
          '${senderHex.substring(0, 8)} — no decided contact '
          '(${state ?? 'unknown'}). Discarded (§15.7).');
      return;
    }
    // The mailbox remembers the sender only HERE, with the app's decision
    // behind it (`MailboxInbound.inboundAccept` no longer does it for
    // strangers) — and only proven (anchor).
    final p = myceliumMailbox;
    if (p != null &&
        hasAnchor &&
        p.contactOrNull(mycelium.identifierFrom(e.from)) == null) {
      mycelium.MailboxInbound(p).inboundMark(e);
    }

    _log.event('mycelium RECEIVE${frame.messageType.name} from '
        '${senderHex.substring(0, 8)} (${e.content.length} B, '
        '${trust.name})');

    await handleApplicationFrame(
      event: HarvestEvent.fromV3Frame(
        frame: frame,
        // The delivery layer addresses identities, not devices.
        senderDeviceId: null,
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
    return InvitationIssueResult.issued(InvitationCard(
      // The same identifier as StandingInvitation.id (line 582) — otherwise
      // the card just issued could not be revoked.
      id: _invitationId(out.card.code),
      text: faceToFace ? '' : out.text,
      packed: out.card.pack(),
      kind: kind,
      expiryUnixSeconds: out.card.expiryUnixSeconds,
      faceToFace: faceToFace,
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
    return _myceliumJoin(reading.card!);
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
  Future<InvitationRedeemResult> _myceliumJoin(mycelium.Card card) async {
    final p = myceliumMailbox!;
    final codeHex = mycelium.hexFrom(card.code);
    for (final own in p.host.mailboxes) {
      if (own.identity.open.containsKey(codeHex)) {
        return const InvitationRedeemResult(InvitationRedeemOutcome.ownCard);
      }
    }
    final sent = Completer<mycelium.Address>();
    final decided = mycelium.MailboxInvitation(p).join(
      mycelium.asInvitationText(card),
      introduction: _myceliumIntroduction(),
      onSent: (g) {
        if (!sent.isCompleted) sent.complete(g);
      },
    );
    final mycelium.Address addr;
    try {
      // Whatever comes first: the end of step 1, or an error before it. The
      // error of a LATER rejection falls into `_myceliumJoinVerfolgen`.
      addr = await Future.any(
          [sent.future, decided.then((k) => k.address)]);
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
    if (soFar == null) {
      _deletedContacts.remove(hex);
      final c = ContactInfo(
        nodeId: userId,
        displayName: kPendingContactName,
        status: 'pending_outgoing',
        ed25519Pk: addr.ed25519Pk,
        mlDsaPk: addr.mlDsaPk,
        x25519Pk: addr.x25519Pk,
        mlKemPk: addr.mlKemPk,
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
    return const InvitationRedeemResult(InvitationRedeemOutcome.requestSent);
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
      c.kemRotationAt ??= DateTime.fromMillisecondsSinceEpoch(addr.state);
      _saveContacts();
      _addSystemMessage(hex, '${c.displayName} accepted your contact request.',
          type: UiMessageType.identityDeleted); // system message type
      _saveConversations();
      onContactAccepted?.call(hex);
      onStateChanged?.call();
      _log.event('mycelium:contact ${hex.substring(0, 8)} accepted (answer 3)');
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
        if (_myceliumSameKeys(soFar!, who)) {
          final ok = _myceliumRequestDecide(soFar,
              accept: true, recontact: true);
          _log.event('mycelium CONTACT REQUEST from $short — already a contact, same '
              'keys: answer without question (§15.5) -> $ok');
          return;
        }
        _myceliumKeyWarning(soFar, hex);
        return;
      case 'pending_outgoing':
        if (!addressHeardTo(who, soFar!)) {
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
    c.verificationLevel = change.newLevel;
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
