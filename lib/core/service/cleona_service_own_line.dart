// B-4 (D-37) — the app on the own-device line of the delivery layer.
//
// V4.2 §22.5.2: twin sync to one's own devices runs as a `sendToUser` to
// one's own UserID; it deposits once per other own device under that
// device's value (§14.7, `mycelium/lib/mailbox_own_line.dart`). A single own
// device can be named (§22-O-1 = (b), own devices only). Twin-sync
// deliveries carry no acknowledgement; placed is their final observation
// (§9.2).
//
// The device set is the app's `_devices` (Types 9 and 16, §14.7); the
// delivery layer keeps no device list of its own and is told the set at
// attachment and at every change ([_myceliumOwnLineSync]).
//
// NOT here: the enrolment of a device (B-4b) — without enrolment no product
// path reaches two devices. The routine KEM rotation across own devices
// (E7, D-40, Type 19) stands in `cleona_service_kem_line.dart`.

part of 'cleona_service.dart';

/// The contact deliveries mirrored to the other own devices (§14.2, Type 18):
/// the conversation itself. Not mirrored (open, `S398-B4-BAU.md`): media and
/// voice (their objects travel lanes 2/3 with their own receipts, §9.4),
/// channel membership, contact requests, key rotation; group and channel
/// joins travel as Type 6 / Type 22 (§14.7). A change of a group's members is
/// mirrored (§14.7, D-91). The chat
/// configuration is mirrored (§21.5.4, D-72). A call signal
/// is mirrored too, but on steps 1 and 3 and not through the post box
/// (§17.2, D-46, `_kCallSignalTypes`, `cleona_service_own_ring.dart`).
const _kMirrored = <proto.MessageType>{
  proto.MessageType.MT_TEXT,
  proto.MessageType.MT_REPLY,
  proto.MessageType.MT_REACTION,
  // §16.2.4: the totals of a private channel are shown on every own device.
  proto.MessageType.MT_CHANNEL_REACTION_TOTALS,
  proto.MessageType.MT_EDIT,
  proto.MessageType.MT_DELETE,
  // §17.2: the missed-call message is "mirrored like any message".
  proto.MessageType.MT_CALL_MISSED,
  // §21.5.4, D-72 "per-chat values travel by mirroring the chat-configuration
  // message to the own devices": a contact's proposal, acceptance or
  // rejection, and an owner's or admin's group/channel settings — also from
  // a co-member who is no contact (group pair, `_handleDeliveryMirror`). The
  // own changes travel as Type 2 (`_ownChatConfigMirror`).
  proto.MessageType.MT_CHAT_CONFIG_UPDATE,
  // §14.7, D-91: "A change of a group's members that one device receives is
  // mirrored like any contact delivery (Type 18), whether or not the
  // identity has joined" — from a contact, or over a group pair
  // (`_handleDeliveryMirror`). The receiving device applies it as a direct
  // one (`_groupMembersChangeReceived`: authority gate, epoch rule, the
  // entry's signatures).
  proto.MessageType.MT_GROUP_MEMBERS_CHANGE,
};

extension CleonaServiceOwnLine on CleonaService {
  /// Tells the mailbox this device and the other own devices — at
  /// attachment and at every change of `_devices`. Only 16-B DeviceIDs
  /// (the device UUID, §14.1) take part; a record keyed by a device node id
  /// (the V3 pairing, `_addDeviceDelegation`) names no DeviceID.
  void _myceliumOwnLineSync() {
    final p = myceliumMailbox;
    if (p == null) return;
    Uint8List? me;
    final others = <Uint8List>[];
    for (final d in _devices.values) {
      final id = _ownLineDeviceId(d.deviceId);
      if (id == null) continue;
      if (d.isThisDevice) {
        me = id;
      } else {
        others.add(id);
      }
    }
    if (me == null) return; // no local device registered yet
    mycelium.MailboxOwnLine(p).ownLineSet(me, others);
    _ownWhereSync(); // where the others are, and the watch (§14.7, D-46)
  }

  /// The body of `sendToUser` to one's own UserID (§22.5.2). `true` when at
  /// least one deposit was placed (§8.2) — the observation, not a delivery
  /// claim. Only twin sync travels this line.
  Future<bool> _myceliumOwnSend({
    required proto.MessageType messageType,
    required Uint8List payload,
    Uint8List? messageId,
    Uint8List? targetDeviceId,
  }) async {
    final p = myceliumMailbox;
    if (p == null) return false;
    if (messageType != proto.MessageType.MT_TWIN_SYNC) {
      _log.warn('mycelium: self-send ${messageType.name} — only twin sync '
          'travels the own line (§14.7). Not sent.');
      return false;
    }
    List<Uint8List>? to;
    if (targetDeviceId != null && targetDeviceId.isNotEmpty) {
      final d = _ownLineTarget(targetDeviceId);
      if (d == null) {
        _log.warn('mycelium: twin sync to device '
            '${CleonaService._hexShort(targetDeviceId)} — not in the own '
            'device set. Not sent.');
        return false;
      }
      to = [d];
    }
    final id = (messageId != null && messageId.isNotEmpty)
        ? messageId
        : SodiumFFI().randomBytes(16);
    final frame = _innerFrame(
      recipientUserId: identity.userId,
      senderUserId: identity.userId,
      messageId: id,
      messageType: messageType,
      payload: payload,
    );
    final placed = await mycelium.MailboxOwnLine(p).ownSend(
        Uint8List.fromList(frame.writeToBuffer()),
        toDevices: to,
        withWhom: myceliumOwnLineHolders);
    _log.info('mycelium: twin sync placed for $placed own device(s)'
        '${to == null ? '' : ' (one named device)'}');
    return placed > 0;
  }

  /// A frame whose sender is the own UserID (§14.7): taken only as twin
  /// sync and only when the envelope carries exactly the own signing keys —
  /// a foreign identity naming this UserID, or the same identifier under
  /// other keys, is discarded. The device comes from the twin-sync envelope
  /// and only when it is in the own device set (§22.5.3 `senderDeviceId`).
  Future<void> _myceliumOwnInbound(
      mycelium.Inbound e, proto.ApplicationFrame frame) async {
    final ownKeys = e.from.sameIdentity(e.to) &&
        constantTimeEquals(e.from.ed25519Pk, identity.ed25519PublicKey) &&
        constantTimeEquals(e.from.mlDsaPk, identity.mlDsaPublicKey);
    if (!ownKeys) {
      _log.warn('mycelium drop: frame names the own UserID, the envelope is '
          'signed by other keys. Discarded.');
      return;
    }
    if (frame.messageType != proto.MessageType.MT_TWIN_SYNC) {
      _log.warn('mycelium drop: ${frame.messageType.name} from the own '
          'identity — only twin sync travels the own line. Discarded.');
      return;
    }
    Uint8List? device;
    try {
      final envelope = proto.TwinSyncEnvelope.fromBuffer(frame.payload);
      final d = Uint8List.fromList(envelope.deviceId);
      if (_devices.containsKey(bytesToHex(d))) {
        device = d;
        // §14.7 (D-46): every own-line deposit names where its device is.
        _ownWhereFrom(d, envelope);
      }
    } catch (_) {
      // Unreadable envelope: the twin handler logs and drops it.
    }
    _log.event('mycelium RECEIVE own line MT_TWIN_SYNC '
        '(${e.content.length} B, device '
        '${device == null ? 'unknown' : CleonaService._hexShort(device)})');
    await handleApplicationFrame(
      event: HarvestEvent.fromApplicationFrame(
        frame: frame,
        senderDeviceId: device,
        // An own-line delivery is a received delivery too (§20.2); the
        // layer below does not keep its identifier (the own identity is no
        // contact and no group pair), so the receive path does.
        deliveryId: e.identifier,
        snapshot: SenderIdentitySnapshot(
          senderDeviceId: device,
          senderUserId: identity.userId,
          outerSigStatus: OuterSigStatus.verified,
          verifiedDeviceEd25519Pk: null,
          verifiedDeviceMlDsaPk: null,
          newKeyDetectedForSenderUser: false,
          receivedAt: e.at,
        ),
      ),
      wasDirect: false,
    );
  }

  /// Type 0 CONTACT_ADDED (§14.7, D-28): everything another own device needs
  /// to reach [contact] — keys, founding anchor, and from the delivery layer
  /// the pair secret `s_AB`, the peer's day keys and its fixed neighbours.
  /// It travels only sealed to the own identity (the own line).
  void _sendTwinContactAdded(ContactInfo contact) {
    final hex = contact.nodeIdHex;
    final k = myceliumMailbox?.contactOrNull(hex);
    _sendTwinSync(proto.TwinSyncType.CONTACT_ADDED,
        Uint8List.fromList(utf8.encode(jsonEncode({
      'nodeId': hex,
      'displayName': contact.displayName,
      if (contact.ed25519Pk != null) 'ed25519Pk': bytesToHex(contact.ed25519Pk!),
      if (contact.x25519Pk != null) 'x25519Pk': bytesToHex(contact.x25519Pk!),
      if (contact.mlKemPk != null) 'mlKemPk': bytesToHex(contact.mlKemPk!),
      if (contact.mlDsaPk != null) 'mlDsaPk': bytesToHex(contact.mlDsaPk!),
      // §15.2: the founding anchor MUST travel along — the twin would
      // otherwise compute a different `K_AB` for the same human.
      if (contact.peerFoundingEd25519Pk != null)
        'peerFoundingEd25519Pk': bytesToHex(contact.peerFoundingEd25519Pk!),
      if (contact.deviceNodeIds.isNotEmpty)
        'deviceNodeIds': contact.deviceNodeIds.toList(),
      if (k?.pairRandom != null) 'sAB': bytesToHex(k!.pairRandom!),
      if (k != null && k.dayKey.isNotEmpty)
        'dayKeys': {
          for (final e in k.dayKey.entries) '${e.key}': bytesToHex(e.value)
        },
      if (k != null && k.neighbours.isNotEmpty)
        'neighbours': [
          for (final n in k.neighbours)
            {'a': bytesToHex(n.address), 'p': n.port}
        ],
    }))));
  }

  /// The delivery-layer half of a received CONTACT_ADDED: `s_AB`, day keys
  /// and fixed neighbours go into the mailbox, and the own incoming codes are
  /// recomputed (§8.1 edge "new contact"). Without `s_AB` the contact stays
  /// what it was — reachable only after a first contact of this device.
  void _ownLineContactTake(Map<String, dynamic> json, ContactInfo contact) {
    final p = myceliumMailbox;
    final sAB = json['sAB'];
    if (p == null || sAB is! String) return;
    try {
      final days = json['dayKeys'];
      final near = json['neighbours'];
      p.contactRemember(
        addressFrom(contact),
        pairRandom: hexToBytes(sAB),
        dayKey: days is Map
            ? {
                for (final e in days.entries)
                  int.parse(e.key as String): hexToBytes(e.value as String)
              }
            : null,
        neighbours: near is List
            ? [
                for (final n in near.cast<Map<String, dynamic>>())
                  CardAddress(
                      hexToBytes(n['a'] as String), n['p'] as int)
              ]
            : null,
        displayName: contact.displayName,
      );
      p.node.codeRoute.codesChanged();
      _log.info('mycelium: contact ${contact.nodeIdHex.substring(0, 8)} '
          'taken over from the own line (s_AB, day keys, fixed neighbours)');
    } catch (e) {
      _log.warn('mycelium: CONTACT_ADDED for '
          '${contact.nodeIdHex.substring(0, 8)} not taken into the mailbox: $e');
    }
  }

  /// Type 6 GROUP_CREATED (§14.7): a group this device created or joined, as
  /// it stands here — the members with their signed entries, the epoch and
  /// `joined` — and, per group pair of this group (D-36), what Type 0
  /// carries per contact: `sAB`, the co-member's `dayKeys` and its fixed
  /// `neighbours`, so that every own device reaches every member.
  void _sendTwinGroupCreated(GroupInfo group) {
    final p = myceliumMailbox;
    final pairs = <String, dynamic>{};
    for (final m in group.members.keys) {
      final k = p?.groupPairOrNull(m);
      final s = k?.groupSeeds[group.groupIdHex];
      if (k == null || s == null) continue;
      pairs[m] = {
        'sAB': bytesToHex(s),
        if (k.dayKey.isNotEmpty)
          'dayKeys': {
            for (final e in k.dayKey.entries) '${e.key}': bytesToHex(e.value)
          },
        if (k.neighbours.isNotEmpty)
          'neighbours': [
            for (final n in k.neighbours)
              {'a': bytesToHex(n.address), 'p': n.port}
          ],
      };
    }
    final sk = _skTwinState(group.groupIdHex);
    _sendTwinSync(proto.TwinSyncType.GROUP_CREATED,
        Uint8List.fromList(utf8.encode(jsonEncode({
      ...group.toJson(),
      if (pairs.isNotEmpty) 'groupPairs': pairs,
      // §14.7 Type 6, §16.2.5: the key state this device holds.
      'sharedKey': ?sk,
    }))));
  }

  /// Type 21 GROUP_LEFT (§14.7, S403 owner decision 03.10.2026 V1 = A): the
  /// identity left the group [gid] (or the channel of that identifier,
  /// §16.2.2 "The same mark is kept for a channel the device left"),
  /// holding the membership [epochAtLeaving]. The receiving device removes
  /// the conversation and sets the same mark — a post the leaving device
  /// discarded is not forwarded to it, so it must not show the group as
  /// held either. The mark is the same one the leaving device sets
  /// (`cleona_service_group_gate.dart`).
  void _sendTwinGroupLeft(String gid, int epochAtLeaving) {
    _sendTwinSync(proto.TwinSyncType.GROUP_LEFT,
        Uint8List.fromList(utf8.encode(jsonEncode({
      'group': gid,
      'epoch': epochAtLeaving,
    }))));
  }

  /// Type 22 CHANNEL_JOINED (§14.7, S407 owner decision 08.10.2026 E17 = A):
  /// the identity created, joined or changed [channel] on this device — its
  /// state as it stands here, so that every own device holds the channel
  /// the way it holds a group after Type 6. Sent only while the identity is
  /// a member: the state a leaving device sends to the remaining members no
  /// longer names it, and its leaving travels as Type 21 GROUP_LEFT.
  void _sendTwinChannelJoined(ChannelInfo channel) {
    if (!channel.members.containsKey(identity.userIdHex)) return;
    final sk = _skTwinState(channel.channelIdHex);
    // §14.7 Type 22 "name and settings" (S407-EINSTELLUNGEN A-5): the
    // settings in force here (§21.5.4) — they live at the conversation, not
    // at the channel object.
    final settings = conversations[channel.channelIdHex]?.config.toJson();
    _sendTwinSync(proto.TwinSyncType.CHANNEL_JOINED,
        Uint8List.fromList(utf8.encode(jsonEncode({
      ...channel.toJson(),
      // §14.7 Type 22, §16.2.5: the key state this device holds.
      'sharedKey': ?sk,
      'chatConfig': ?settings,
    }))));
  }

  /// The delivery-layer half of a received GROUP_CREATED: the seeds wait in
  /// the mailbox, the pairs of [g] form from them ([_groupPairsSync]), and
  /// each formed pair takes the co-member's day keys and fixed neighbours.
  void _ownLineGroupPairsTake(Map<String, dynamic> json, GroupInfo g) {
    final p = myceliumMailbox;
    final pairs = json['groupPairs'];
    if (p == null || pairs is! Map) {
      _groupPairsSync(g);
      return;
    }
    final gid = hexToBytes(g.groupIdHex);
    try {
      for (final e in pairs.entries) {
        final m = e.key as String;
        if (!g.members.containsKey(m)) continue;
        p.groupPairSeed(
            gid, hexToBytes(m), hexToBytes((e.value as Map)['sAB'] as String));
      }
      _groupPairsSync(g);
      final today = utcDay(DateTime.now());
      for (final e in pairs.entries) {
        final days = (e.value as Map)['dayKeys'];
        final near = (e.value as Map)['neighbours'];
        p.groupPairTakeOver(
          e.key as String,
          today,
          dayKey: days is Map
              ? {
                  for (final d in days.entries)
                    int.parse(d.key as String): hexToBytes(d.value as String)
                }
              : null,
          neighbours: near is List
              ? [
                  for (final n in near.cast<Map<String, dynamic>>())
                    CardAddress(hexToBytes(n['a'] as String), n['p'] as int)
                ]
              : null,
        );
      }
    } catch (e) {
      _log.warn('mycelium: GROUP_CREATED for ${g.groupIdHex.substring(0, 8)} '
          '— group pairs not taken into the mailbox: $e');
    }
  }

  /// How many group pairs of this identity carry [groupIdHex].
  int _groupPairCount(String groupIdHex) =>
      myceliumMailbox?.groupPairs
          .where((k) => k.groupSeeds.containsKey(groupIdHex))
          .length ??
      0;

  /// Type 7 PROFILE_CHANGED (§14.7): the fields of the own profile that
  /// changed on this device — `displayName`, `profilePicture` (base64 JPEG),
  /// `profileDescription`; a `null` value removes the field on the other
  /// devices. Only the changed field travels, so two changes collected out of
  /// order do not undo each other.
  void _sendTwinProfileChanged(Map<String, String?> changed) {
    _sendTwinSync(proto.TwinSyncType.PROFILE_CHANGED,
        Uint8List.fromList(utf8.encode(jsonEncode(changed))));
  }

  /// Sets the transcription language of this identity (§21.7 "language
  /// setting per identity") and tells the other own devices (§14.7 Type 8
  /// SETTINGS_CHANGED, field `transcriptionLanguage`, with the time of the
  /// change — `cleona_service_shared_settings.dart`).
  void setTranscriptionLanguage(String language) {
    _transcriptionLanguageStore(language);
    _sharedLanguageSend(language);
  }

  /// Stores [language] next to this device's own retention and model size
  /// (those two stay per device) and hands it to the running service.
  void _transcriptionLanguageStore(String language) {
    final held = VoiceTranscriptionSettings.readFrom(store) ??
        const VoiceTranscriptionSettings();
    VoiceTranscriptionSettings(
      defaultLanguage: language,
      audioRetentionDays: held.audioRetentionDays,
      modelSize: held.modelSize,
    ).writeTo(store);
    _voiceTranscription?.defaultLanguage = language;
  }

  /// §14.2/§14.7 Type 18 (E5): a delivery from a contact that THIS device
  /// collected goes to the other own devices as it arrived. Only the
  /// conversation types ([_kMirrored]); `_sendTwinSync` sends nothing while
  /// this is the only device.
  ///
  /// [identifier] is the delivery identifier of the CONTACT delivery this
  /// device collected (§20.2, S403 decision 1 — a deviation from the draft's
  /// variant B, which kept the mirror free of it): the mirror carries it, so
  /// the twin keeps it in the SAME received memory as the collecting device
  /// — whichever of the devices meets a second copy of that delivery, the
  /// identifier is known everywhere and the copy is refused everywhere.
  void _myceliumMirror(
      proto.ApplicationFrame frame, Uint8List content, Uint8List identifier) {
    // §17.2, D-46: a call signal goes to the other own devices at once, on
    // steps 1 and 3 only — never through the post box, which would ring
    // for nobody (`cleona_service_own_ring.dart`).
    if (_kCallSignalTypes.contains(frame.messageType)) {
      _ownCallMirror(content, identifier);
      return;
    }
    if (!_kMirrored.contains(frame.messageType)) return;
    _sendTwinSync(proto.TwinSyncType.DELIVERY_MIRROR, content,
        deliveryId: identifier);
  }

  /// A Type 18 mirror from another own device: the contact's frame, shown as
  /// if received here and not acknowledged again (§14.7). Taken only from a
  /// decided contact, addressed to this identity, of a mirrored type — the
  /// own line vouches for the collecting device, not for arbitrary content.
  ///
  /// [deliveryId] is the delivery identifier the collecting device's mirror
  /// carries (see [_myceliumMirror]): handed into the receive path, so this
  /// device keeps it in the same received memory (§20.2). `null` from an
  /// older sender that mirrors without it — then nothing is checked or
  /// kept, per the null contract of [HarvestEvent.deliveryId].
  Future<void> _handleDeliveryMirror(
      List<int> payload, Uint8List? deliveryId) async {
    final proto.ApplicationFrame frame;
    try {
      frame = proto.ApplicationFrame.fromBuffer(payload);
    } catch (_) {
      _log.warn('Twin DELIVERY_MIRROR: unreadable frame — discarded');
      return;
    }
    final sender = Uint8List.fromList(frame.senderUserId);
    final contact = _contacts[bytesToHex(sender)];
    final isContact =
        contact != null && !contact.isDeleted && contact.status == 'accepted';
    // §17.2, D-46: the mirror of a call signal — from a contact, or over a
    // group pair for a group both belong to (§4.3, §16.2.2), as the
    // collecting device admitted it.
    final callSignal = _kCallSignalTypes.contains(frame.messageType) &&
        (isContact || _groupPairAdmits(frame, bytesToHex(sender)));
    // §21.5.4: a group's or channel's settings from an owner or admin who
    // is no contact came over a group pair (§4.3) — admitted the same way.
    // For a group or channel this device does not hold yet the pair cannot
    // be checked here: the settings go to the group gate and wait for the
    // group (§21.5.4 "settings for it … are buffered", N-1a); the sender's
    // role is checked when they are applied (`_handleChatConfigUpdate`).
    final gid = frame.groupId.isEmpty
        ? null
        : bytesToHex(Uint8List.fromList(frame.groupId));
    final groupNotHeld = gid != null &&
        !_groups.containsKey(gid) &&
        !_channels.containsKey(gid) &&
        !SystemChannels.isSystemChannel(gid);
    final configOverPair =
        frame.messageType == proto.MessageType.MT_CHAT_CONFIG_UPDATE &&
            !isContact &&
            (groupNotHeld || _groupPairAdmits(frame, bytesToHex(sender)));
    // §17.2 "mirrored like any message" (S408): the missed-call message of a
    // group call from a co-member who is no contact came over the group pair,
    // as the INVITE it follows did — admitted the same way as that INVITE's
    // mirror above, so that every own device that rang shows the entry.
    final missedOverPair =
        frame.messageType == proto.MessageType.MT_CALL_MISSED &&
            !isContact &&
            _groupPairAdmits(frame, bytesToHex(sender));
    // D-91: a membership change from an owner or admin who is no contact
    // came over the group pair of a joined group — admitted the same way.
    // A group this device does not hold has nothing to change.
    final membersOverPair =
        frame.messageType == proto.MessageType.MT_GROUP_MEMBERS_CHANGE &&
            !isContact &&
            _groupPairAdmits(frame, bytesToHex(sender));
    if (!(callSignal ||
            _kMirrored.contains(frame.messageType) &&
                (isContact ||
                    configOverPair ||
                    missedOverPair ||
                    membersOverPair)) ||
        !constantTimeEquals(
            Uint8List.fromList(frame.recipientUserId), identity.userId)) {
      _log.warn('Twin DELIVERY_MIRROR: ${frame.messageType.name} from '
          '${CleonaService._hexShort(sender)} — not a mirrored delivery of '
          'a contact. Discarded.');
      return;
    }
    await handleApplicationFrame(
      event: HarvestEvent.fromApplicationFrame(
        frame: frame,
        senderDeviceId: null,
        deliveryId: deliveryId,
        snapshot: SenderIdentitySnapshot(
          senderDeviceId: null,
          senderUserId: sender,
          outerSigStatus: OuterSigStatus.verified,
          verifiedDeviceEd25519Pk: null,
          verifiedDeviceMlDsaPk: null,
          newKeyDetectedForSenderUser: false,
          // This device's own arrival: a mirrored INVITE counts its 10 s
          // from here (§17.2 "counts from its own arrival time").
          receivedAt: DateTime.now(),
        ),
      ),
      mirrored: true,
    );
  }

  /// §14.2 "what any device sends … reaches the others as `MESSAGE_SENT`",
  /// D-72: a chat configuration this device sent — a 1:1 proposal,
  /// acceptance or rejection, or a group's or channel's settings — goes to
  /// the other own devices as Type 2 carrying the `ChatConfigUpdate` as
  /// sent. A v4.2.3 device finds no `text` in it and drops it with a
  /// warning (`398a6e40:lib/core/service/cleona_service.dart:9680-9686`).
  ///
  /// [group]: the settings of a group or channel — so that a device that
  /// does not hold it yet keeps them for it (§21.5.4 "settings for it",
  /// N-1a) instead of taking the identifier for an unknown contact.
  void _ownChatConfigMirror(String conversationId, Uint8List configBytes,
      {bool group = false}) {
    _sendTwinSync(proto.TwinSyncType.MESSAGE_SENT,
        Uint8List.fromList(utf8.encode(jsonEncode({
      'conversationId': conversationId,
      'chatConfigUpdate': base64Encode(configBytes),
      if (group) 'group': true,
    }))));
  }

  /// A configuration change another own device sent ([_ownChatConfigMirror]):
  /// applied as there — a group's or channel's settings where the identity
  /// is owner or admin, in 1:1 the identity's own proposal (shown as open),
  /// its acceptance (applied, proposal closed) or its rejection (proposal
  /// closed).
  ///
  /// [forGroup]: the sender marked it as a group's or channel's settings
  /// ([_ownChatConfigMirror]). For one this device does not hold yet they
  /// wait in the identity's store like the settings of a member that arrive
  /// before the invitation (§21.5.4 "settings for it … are buffered", N-1a)
  /// and are applied with the group (`_groupWaitingApply`), where the own
  /// role is checked as for every settings change.
  void _ownChatConfigApply(String conversationId, Uint8List bytes,
      {bool forGroup = false}) {
    final proto.ChatConfigUpdate m;
    try {
      m = proto.ChatConfigUpdate.fromBuffer(bytes);
    } catch (_) {
      _log.warn('Twin MESSAGE_SENT: unreadable configuration — discarded');
      return;
    }
    final config = _chatConfigOf(m);
    final me = identity.userIdHex;
    final group = _groups[conversationId];
    final channel = group == null ? _channels[conversationId] : null;
    final short = conversationId.length >= 8
        ? conversationId.substring(0, 8)
        : conversationId;
    if (group != null || channel != null) {
      final role = group?.members[me]?.role ?? channel?.members[me]?.role;
      final conv = conversations[conversationId];
      if ((role != 'owner' && role != 'admin') || conv == null) {
        _log.warn('Twin configuration for $short: not owner/admin here or '
            'no conversation — discarded');
        return;
      }
      if (group != null) {
        config.announcementOnly = m.hasAnnouncementOnly()
            ? m.announcementOnly
            : conv.config.announcementOnly;
      }
      final modeChanged =
          group != null && config.announcementOnly != conv.config.announcementOnly;
      conv.config = config;
      _saveConversations();
      if (modeChanged) _groupAnnouncementChanged(conversationId);
      onStateChanged?.call();
      _log.info('Twin-synced ${group != null ? 'group' : 'channel'} '
          'configuration for $short');
      return;
    }
    if (forGroup) {
      final verdict = _groupGate(HarvestEvent(
        senderUserId: identity.userId,
        senderDeviceId: null,
        type: proto.MessageType.MT_CHAT_CONFIG_UPDATE,
        payload: bytes,
        messageId: SodiumFFI().randomBytes(16),
        harvestedAt: DateTime.now(),
        claimedSentAt: null,
        groupId: hexToBytes(conversationId),
        rosterVersion: null,
        contentMetadata: null,
        senderTrust: SenderTrust.verified,
      ));
      if (verdict != GroupGateVerdict.waits) {
        _log.info('Twin configuration for the group $short not held here — '
            '${verdict.name}');
      }
      return;
    }
    final contact = _contacts[conversationId];
    if (contact == null) {
      _log.info('Twin configuration for the unknown $short — dropped');
      return;
    }
    final conv = conversations.putIfAbsent(conversationId,
        () => Conversation(id: conversationId, displayName: contact.displayName));
    // O-1: the partner's acceptance this device kept because the proposal
    // had not arrived yet. The identity's own proposal of exactly its values
    // completes the consent (§21.5.4) — applied now; an own proposal of
    // other values or an own answer drops it.
    final kept = conv.parkedConfigAcceptance;
    conv.parkedConfigAcceptance = null;
    var keptApplied = false;
    if (m.isRequest) {
      if (kept != null && _sameDmConfig(kept, config)) {
        conv.config = config;
        conv.pendingConfigProposal = null;
        conv.pendingConfigProposer = null;
        keptApplied = true;
      } else {
        conv.pendingConfigProposal = config;
        conv.pendingConfigProposer = me;
      }
    } else {
      if (m.accepted) conv.config = config;
      conv.pendingConfigProposal = null;
      conv.pendingConfigProposer = null;
    }
    _saveConversations();
    onStateChanged?.call();
    _log.info('Twin-synced 1:1 configuration for $short '
        '(${keptApplied ? 'proposal, applied with the acceptance kept here' : m.isRequest ? 'proposal' : m.accepted ? 'accepted' : 'rejected'}'
        '${kept != null && !keptApplied ? '; kept acceptance dropped' : ''})');
  }

  /// The DeviceID of the own device [target] names — its UUID key or its
  /// device node id (the V3 pairing used the latter as target).
  Uint8List? _ownLineTarget(Uint8List target) {
    final hex = bytesToHex(target);
    for (final d in _devices.values) {
      if (d.isThisDevice) continue;
      if (d.deviceId == hex || d.deviceNodeIdHex == hex) {
        return _ownLineDeviceId(d.deviceId);
      }
    }
    return null;
  }

  /// A DeviceID (16 B, 32 hex digits) or `null`.
  Uint8List? _ownLineDeviceId(String hex) =>
      hex.length == 32 && RegExp(r'^[0-9a-f]+$').hasMatch(hex)
          ? hexToBytes(hex)
          : null;
}
