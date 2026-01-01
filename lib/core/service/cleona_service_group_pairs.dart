// B-3 (S398, owner decision G2) — group legs to co-members who are not
// contacts: the GROUP PAIR (v4_2 §4.3 "`s_AB` for co-members who are not
// contacts", §8.2, §15.7, §16.2.2, §18.1.2, §22.5.1, Appendix D D-36).
//
// WHAT HAPPENS WHERE:
//  * The inviter (owner/admin) draws `s_XY` for every new pair of members X–Y
//    and carries it, per leg, in the membership update (`GROUP_INVITE`,
//    `pair_seeds`) — [CleonaService._buildSignedGroupInviteBytes].
//  * Each member entry carries the member's address as the MEMBER signed it
//    on joining (E3, mycelium `group_member.dart`); full entries travel only
//    for members new to the receiver (E2 = a + c).
//  * Joining is explicit (E4): [_groupJoin] signs the own entry and sends it
//    to the inviter (`GROUP_JOIN`), who passes it on in the next update.
//  * Only a joined member forms group pairs ([_groupPairsSync]), in its own
//    mycelium store (E5 = b, `mailbox_group_pair.dart`) — never a contact.
//  * A group pair carries only the group types of §16.2.2 naming a group both
//    belong to ([kGroupPairTypes], [_groupPairAdmits]; §15.7).
//  * A leg with no way — neither a contact nor a group pair — is `failed` and
//    named once in the group (stage 0, [_groupLegWithoutWay]).
//
// Private channels (§4.3 names them too) form their pairs the same way —
// `cleona_service_channel_pairs.dart`.

part of 'cleona_service.dart';

/// The group types a group pair may send (§16.2.2): group post, reaction,
/// edit, deletion, read mark, poll and vote, calendar entry of a group event,
/// membership update (owner/admin, checked by its handler against the OLD
/// member state), leave, and the acknowledgement. The day-key notice of the
/// pair is a mycelium kind and never reaches this set.
const Set<proto.MessageType> kGroupPairTypes = {
  proto.MessageType.MT_TEXT,
  proto.MessageType.MT_REPLY,
  proto.MessageType.MT_MEDIA_INLINE,
  proto.MessageType.MT_MEDIA_ANNOUNCE,
  proto.MessageType.MT_MEDIA_HOLDERS,
  // The failure of a group file, both ways (§9.4 "Reasons"): part of the
  // group post it ends — without it a member who is no contact would show
  // another reason than the sender (OP-30).
  proto.MessageType.MT_MEDIA_ABORT,
  proto.MessageType.MT_VOICE_MESSAGE,
  proto.MessageType.MT_REACTION,
  proto.MessageType.MT_EDIT,
  proto.MessageType.MT_DELETE,
  proto.MessageType.MT_READ_RECEIPT,
  proto.MessageType.MT_POLL_CREATE,
  proto.MessageType.MT_POLL_VOTE,
  proto.MessageType.MT_POLL_VOTE_ANONYMOUS,
  proto.MessageType.MT_POLL_UPDATE,
  proto.MessageType.MT_POLL_SNAPSHOT,
  proto.MessageType.MT_POLL_REVOKE,
  proto.MessageType.MT_CALENDAR_INVITE,
  proto.MessageType.MT_CALENDAR_UPDATE,
  proto.MessageType.MT_CALENDAR_DELETE,
  proto.MessageType.MT_CALENDAR_RSVP,
  proto.MessageType.MT_GROUP_INVITE,
  proto.MessageType.MT_CHANNEL_ROLE_UPDATE,
  proto.MessageType.MT_GROUP_LEAVE,
  proto.MessageType.MT_DELIVERY_RECEIPT,
  // §17.2 "Missed call" (S408): the message the initiator of a group call
  // sends a member whose invitation ended unanswered — an ordinary message,
  // over the group pair as the INVITE it follows (§16.2.2: "the signals of a
  // call in their group go over the group pair").
  proto.MessageType.MT_CALL_MISSED,
  // §9.5 "Who is asked: every contact and every group pair": the request,
  // the answer and the progress report of catching up, each naming a group
  // both belong to. (§16.2.2 does not list it among the group types yet.)
  proto.MessageType.MT_CATCH_UP,
  // A private channel (§4.3 "of a group or private channel"): its post, its
  // membership update and leaving, and the reactions of §16.2.4.
  proto.MessageType.MT_CHANNEL_POST,
  proto.MessageType.MT_CHANNEL_INVITE,
  proto.MessageType.MT_CHANNEL_LEAVE,
  proto.MessageType.MT_CHANNEL_REACTION_TOTALS,
  proto.MessageType.MT_CHANNEL_REACTION_HANDOVER,
  // §16.2.2: a membership change as a change (owner/admin, checked by its
  // handler against the OLD member state).
  proto.MessageType.MT_CHANNEL_MEMBERS_CHANGE,
  proto.MessageType.MT_GROUP_MEMBERS_CHANGE,
  // §16.2.2 "Settings (name, description, image, posting policy, message
  // expiry) are changed by the owner or admin" — and reach every member,
  // also one that is no contact of that owner or admin (owner/admin only,
  // checked by its handler; S407 group list, norm proposal in the report).
  proto.MessageType.MT_CHAT_CONFIG_UPDATE,
  // §16.2.2/§16.2.5: the capability notice and the key deliveries of the
  // shared key (`cleona_service_shared_key*.dart`), each naming a group or
  // channel both belong to. The nudge is a mycelium kind (`0x68`).
  proto.MessageType.MT_CAPABILITY_NOTICE,
  proto.MessageType.MT_SHARED_KEY,
  proto.MessageType.MT_SHARED_KEY_AUTHOR,
  // §16.2.2 "the signals of a call in that group (§17.2)", §17.2 "To a
  // fellow member who is not a contact, the signals of a call in their group
  // go over the group pair … on the same two steps; every member may start a
  // call in its group" (D-69). Exactly the signals the group call sends
  // (`GroupCallManager._signal`, `_sendReject`); they never carry Plane D
  // material to a member that is no contact with call consent (§17.3,
  // `GroupCallManager._callPairAdmissible`). The seam sends them as call
  // signals, steps 1 and 3 only ([_groupPairFrameSend]). CALL_MEDIA_STATE
  // and CALL_KEYFRAME_REQUEST are not sent in the group path and are not
  // here. RING_ACK is, since S407-GAMUTE (H-1): the ringing member tells the
  // initiator, which may be no contact (§17.2).
  proto.MessageType.MT_CALL_RING_ACK,
  proto.MessageType.MT_CALL_INVITE,
  proto.MessageType.MT_CALL_ANSWER,
  proto.MessageType.MT_CALL_REJECT,
  proto.MessageType.MT_CALL_HANGUP,
  proto.MessageType.MT_CALL_CANCEL_OTHERS,
  proto.MessageType.MT_CALL_GROUP_LEAVE,
  proto.MessageType.MT_CALL_REJOIN,
  proto.MessageType.MT_CALL_GROUP_SENDER_KEY,
};

/// The kinds whose leg without a way is NAMED in the group (stage 0) — what
/// the user posted. A receipt or a read mark without a way is only `failed`.
const Set<proto.MessageType> _kGroupPostTypes = {
  proto.MessageType.MT_TEXT,
  proto.MessageType.MT_REPLY,
  proto.MessageType.MT_MEDIA_INLINE,
  proto.MessageType.MT_MEDIA_ANNOUNCE,
  proto.MessageType.MT_VOICE_MESSAGE,
  proto.MessageType.MT_POLL_CREATE,
  proto.MessageType.MT_CALENDAR_INVITE,
};

extension CleonaServiceGroupPairs on CleonaService {
  // ── The gate (§15.7) ──────────────────────────────────────────────────

  /// Whether [frame] from [senderHex] — no contact — passes as from a group
  /// pair: a group type naming a group both belong to in the CURRENT member
  /// state, which this identity joined and which carries the pair.
  bool _groupPairAdmits(proto.ApplicationFrame frame, String senderHex) {
    final p = myceliumMailbox;
    if (p == null ||
        !kGroupPairTypes.contains(frame.messageType) ||
        frame.groupId.isEmpty) {
      return false;
    }
    final gid = bytesToHex(Uint8List.fromList(frame.groupId));
    final c = _channels[gid];
    if (c != null) {
      // A private channel both belong to (§4.3, §16.2).
      if (c.isPublic ||
          !c.members.containsKey(senderHex) ||
          !c.members.containsKey(identity.userIdHex)) {
        return false;
      }
      return p.groupPairOrNull(senderHex)?.groups.contains(gid) ?? false;
    }
    final g = _groups[gid];
    if (g == null ||
        !g.joined ||
        !g.members.containsKey(senderHex) ||
        !g.members.containsKey(identity.userIdHex)) {
      return false;
    }
    return p.groupPairOrNull(senderHex)?.groups.contains(gid) ?? false;
  }

  // ── Sending (§22.5.1: found by the UserID, no key overrides) ─────────

  /// Hands [frame] to the group pair [recipientHex] — only for a group type
  /// naming a group the pair carries. `null`: no such pair.
  ///
  /// A call signal ([_kCallSignalTypes]) goes as a signal: steps 1 and 3,
  /// no post box, no history entry (§17.2, D-45) — the same send as to a
  /// contact ([_myceliumSignalSend]). Through `groupPairSend` it would take
  /// the full ladder with the post box and be sent again at every edge.
  mycelium.Outbound? _groupPairFrameSend(mycelium.Mailbox p,
      {required String recipientHex,
      required Uint8List frame,
      required String messageIdHex,
      proto.MessageType? messageType,
      Uint8List? groupId}) {
    if (messageType == null ||
        !kGroupPairTypes.contains(messageType) ||
        groupId == null ||
        groupId.isEmpty) {
      return null;
    }
    final pair = p.groupPairOrNull(recipientHex);
    if (pair == null || !pair.groups.contains(bytesToHex(groupId))) {
      return null;
    }
    if (_kCallSignalTypes.contains(messageType)) {
      return _myceliumSignalSend(p, recipientHex, frame,
          messageIdHex: messageIdHex,
          type: messageType,
          short: recipientHex.substring(0, 8),
          groupPair: true);
    }
    try {
      return p.groupPairSend(recipientHex, frame);
    } on mycelium.MailboxError catch (e) {
      _log.warn('group pair ${recipientHex.substring(0, 8)}: $e');
      return null;
    }
  }

  /// Stage 0 (§22.5.1 `failed`, proposal B-3): the leg [messageIdHex] to
  /// [recipientHex] had no way. Its state is `failed`; for a post the group
  /// names the member ONCE (not per message) — instead of dropping it
  /// silently, as the seam did until S398.
  void _groupLegWithoutWay(String messageIdHex, String recipientHex,
      {Uint8List? groupId, proto.MessageType? messageType}) {
    _myceliumLegsWithoutWay.add(messageIdHex);
    while (_myceliumLegsWithoutWay.length > _kMyceliumOutboundsMax) {
      _myceliumLegsWithoutWay.remove(_myceliumLegsWithoutWay.first);
    }
    if (groupId == null || groupId.isEmpty) return;
    final g = _groups[bytesToHex(groupId)];
    if (g == null || !_kGroupPostTypes.contains(messageType)) return;
    _groupNotice(g, recipientHex, kNoticeGroupMemberUnreachable, 'unreachable');
  }

  /// Writes the notice [key] about [memberHex] into the group — once per
  /// member, group and [kind] in this run.
  void _groupNotice(GroupInfo g, String memberHex, String key, String kind) {
    if (!_groupNoticesShown.add('${g.groupIdHex}:$memberHex:$kind')) return;
    final name = g.members[memberHex]?.displayName ??
        _contacts[memberHex]?.displayName ??
        memberHex.substring(0, 8);
    _addSystemMessage(g.groupIdHex, noticeWithName(key, name),
        type: UiMessageType.groupInvite, isGroup: true);
    onStateChanged?.call();
  }

  // ── Member entries (§16.2.2, E2 = a + c, E3) ─────────────────────────

  /// [m] on the wire; with its signed entry only when [full].
  proto.GroupMember _groupMemberWire(GroupMemberInfo m, {required bool full}) {
    final w = proto.GroupMember()
      ..nodeId = hexToBytes(m.nodeIdHex)
      ..displayName = m.displayName
      ..role = m.role
      ..ed25519PublicKey = m.ed25519Pk ?? Uint8List(0)
      ..x25519PublicKey = m.x25519Pk ?? Uint8List(0)
      ..mlKemPublicKey = m.mlKemPk ?? Uint8List(0);
    if (full && m.hasSignedEntry) {
      w
        ..address = m.address!
        ..addressSigEd25519 = m.addressSigEd25519!
        ..addressSigMlDsa = m.addressSigMlDsa!;
      if (m.neighbours != null) w.neighbours = m.neighbours!;
    }
    // §4.4.3 (S407-UMSCHLAG): the mark rides in the compact entry too (2 B),
    // so a renewed one reaches co-members without the 6.7 KB entry.
    if (m.hasSignedEntry && m.readsPairTag) w.readsPairTag = true;
    return w;
  }

  /// Signs the own entry of [g] with the current keys of this identity's
  /// post box, and names its own fixed neighbours next to it.
  void _groupOwnEntrySign(GroupInfo g) {
    final p = myceliumMailbox;
    final me = g.members[identity.userIdHex];
    if (p == null || me == null) return;
    final e = groupMemberSign(p.identity.postBox, hexToBytes(g.groupIdHex));
    me
      ..address = e.address
      ..addressSigEd25519 = e.ed
      ..addressSigMlDsa = e.dsa
      ..neighbours = groupMemberNeighboursWire(p.ownNeighbours)
      ..readsPairTag = true; // this build reads the tagged envelope (§4.4.3)
  }

  /// The seed of the pair [x]–[y] in [seeds] — drawn once per update, so
  /// both legs carry the same one.
  Uint8List _groupSeedFor(Map<String, Uint8List> seeds, String x, String y) =>
      seeds.putIfAbsent(x.compareTo(y) < 0 ? '$x:$y' : '$y:$x',
          () => SodiumFFI().randomBytes(32));

  /// The members of an arriving update. A full entry is kept only if it
  /// proves itself (the member's own signature over this group, its
  /// identifier the member's UserID); one that does not goes into
  /// [unconfirmed]. A compact entry keeps what [old] held.
  Map<String, GroupMemberInfo> _groupMembersFromInvite(
      proto.GroupInvite invite, GroupInfo? old, Set<String> unconfirmed) {
    final gid = Uint8List.fromList(invite.groupId);
    final members = <String, GroupMemberInfo>{};
    for (final m in invite.members) {
      final nid = m.nodeId.hex;
      Uint8List? opt(List<int> b) => b.isEmpty ? null : Uint8List.fromList(b);
      final info = GroupMemberInfo(
        nodeIdHex: nid,
        displayName: m.displayName,
        role: m.role,
        ed25519Pk: opt(m.ed25519PublicKey),
        x25519Pk: opt(m.x25519PublicKey),
        mlKemPk: opt(m.mlKemPublicKey),
      );
      final prev = old?.members[nid];
      if (m.address.isNotEmpty) {
        final a = groupMemberCheck(gid, Uint8List.fromList(m.address),
            Uint8List.fromList(m.addressSigEd25519),
            Uint8List.fromList(m.addressSigMlDsa));
        if (a != null && bytesToHex(a.identifier) == nid) {
          info
            ..address = Uint8List.fromList(m.address)
            ..addressSigEd25519 = Uint8List.fromList(m.addressSigEd25519)
            ..addressSigMlDsa = Uint8List.fromList(m.addressSigMlDsa)
            ..neighbours = opt(m.neighbours) ?? prev?.neighbours
            ..readsPairTag = m.readsPairTag;
        } else {
          unconfirmed.add(nid);
        }
      } else if (prev != null && prev.hasSignedEntry) {
        info
          ..address = prev.address
          ..addressSigEd25519 = prev.addressSigEd25519
          ..addressSigMlDsa = prev.addressSigMlDsa
          ..neighbours = prev.neighbours
          ..readsPairTag = prev.readsPairTag || m.readsPairTag;
      }
      members[nid] = info;
    }
    return members;
  }

  /// A LATE update (§16.2.2, owner decision 08.10.2026, V1 = A): an update
  /// whose epoch is not above [g]'s decides nothing — members, roles, name
  /// and epoch stay those of the newer state — but a self-signed entry it
  /// carries for a member [g] holds WITHOUT one is taken. The entry proves
  /// itself (`groupMemberCheck`), and an update E that a later E+1 overtook
  /// in transport is otherwise the only copy of the entry of the member who
  /// joined with E (S406-CATCHUP, open point 2). Returns how many were taken.
  int _groupLateEntriesTake(proto.GroupInvite invite, GroupInfo g) {
    final gid = Uint8List.fromList(invite.groupId);
    var taken = 0;
    for (final m in invite.members) {
      final held = g.members[m.nodeId.hex];
      if (m.address.isEmpty || held == null || held.hasSignedEntry) continue;
      final a = groupMemberCheck(gid, Uint8List.fromList(m.address),
          Uint8List.fromList(m.addressSigEd25519),
          Uint8List.fromList(m.addressSigMlDsa));
      if (a == null || bytesToHex(a.identifier) != held.nodeIdHex) continue;
      held
        ..address = Uint8List.fromList(m.address)
        ..addressSigEd25519 = Uint8List.fromList(m.addressSigEd25519)
        ..addressSigMlDsa = Uint8List.fromList(m.addressSigMlDsa)
        ..readsPairTag = m.readsPairTag
        ..neighbours ??= m.neighbours.isEmpty
            ? null
            : Uint8List.fromList(m.neighbours);
      taken++;
    }
    return taken;
  }

  /// The membership update [_broadcastGroupUpdate] builds from [g] for
  /// [recipientHex] — for probes that hand a device updates in an order of
  /// their choosing (`smoke_group_update_late_run.dart`).
  @visibleForTesting
  Uint8List groupUpdateForTesting(GroupInfo g, String recipientHex,
          {Set<String> fresh = const {}}) =>
      _buildSignedGroupInviteBytes(g, recipientHex: recipientHex, fresh: fresh);

  /// The ML-DSA key of [m] from its signed entry — for a membership update
  /// of an admin who is not a contact (build step 9 of the proposal).
  Uint8List? _groupMemberMlDsa(GroupMemberInfo? m) {
    final a = m?.address;
    if (a == null || a.length < 64 + OqsFFI.mlDsaPublicKeyLength) return null;
    return Uint8List.fromList(
        Uint8List.sublistView(a, 64, 64 + OqsFFI.mlDsaPublicKeyLength));
  }

  // ── Pairs ─────────────────────────────────────────────────────────────

  /// The seeds of an update for THIS identity wait in the mailbox until the
  /// pair can be formed (only after the explicit join, §16.2.2).
  void _groupPairSeedsTake(proto.GroupInvite invite, GroupInfo g) {
    final p = myceliumMailbox;
    if (p == null) return;
    final gid = Uint8List.fromList(invite.groupId);
    for (final s in invite.pairSeeds) {
      final mid = s.memberId.hex;
      if (mid == identity.userIdHex || !g.members.containsKey(mid)) continue;
      p.groupPairSeed(
          gid, Uint8List.fromList(s.memberId), Uint8List.fromList(s.seed));
    }
  }

  /// Brings the group pairs of [g] in line with its member state: removed
  /// members end their pair for this group (the last group ends the pair,
  /// §4.3); a joined identity forms a pair with every co-member that is not
  /// a contact and has a checked entry and a seed.
  void _groupPairsSync(GroupInfo g, {Set<String> unconfirmed = const {}}) {
    final p = myceliumMailbox;
    if (p == null) return;
    final gid = hexToBytes(g.groupIdHex);
    if (!g.members.containsKey(identity.userIdHex)) {
      p.groupPairLeave(gid);
      return;
    }
    final ended = p.groupPairLeave(gid, keep: g.members.keys.toSet());
    if (ended > 0) _log.info('group pairs: $ended ended with the member state');
    for (final m in g.members.values) {
      if (m.nodeIdHex == identity.userIdHex) continue;
      final contact = _contacts[m.nodeIdHex]?.status == 'accepted' ||
          p.contactOrNull(m.nodeIdHex) != null;
      if (contact) continue;
      if (unconfirmed.contains(m.nodeIdHex)) {
        _groupNotice(g, m.nodeIdHex, kNoticeGroupMemberUnconfirmed,
            'unconfirmed');
      }
      if (!g.joined || !m.hasSignedEntry) continue;
      final r = p.groupPairFromEntry(
          gid, m.address!, m.addressSigEd25519!, m.addressSigMlDsa!,
          neighboursWire: m.neighbours, readsTag: m.readsPairTag);
      if (r.address == null) {
        _groupNotice(g, m.nodeIdHex, kNoticeGroupMemberUnconfirmed,
            'unconfirmed');
      }
    }
  }

  // ── The explicit join (§16.2.2, E4) ──────────────────────────────────

  /// The user joins [groupIdHex]: the own entry is signed, goes to the
  /// inviter, and the group pairs are formed.
  Future<bool> _groupJoin(String groupIdHex) async {
    final g = _groups[groupIdHex];
    final p = myceliumMailbox;
    if (g == null || p == null) return false;
    if (g.joined) return true;
    final me = g.members[identity.userIdHex];
    if (me == null) return false;
    _groupOwnEntrySign(g);
    g.joined = true;
    _saveGroups();
    // §16.2.5: the capability notice goes with the acceptance — ahead of
    // it, so that the owner can admit this device on the shared key.
    await _capabilityNoticesDue();
    final to = g.inviterNodeIdHex ?? g.ownerNodeIdHex;
    final join = proto.GroupJoin()
      ..groupId = hexToBytes(groupIdHex)
      ..member = _groupMemberWire(me, full: true);
    if (!sharedKeyOff) {
      // §16.2.5 "Joining": the author key it names in its acceptance.
      final s = _skOrNew(groupIdHex);
      join.authorPk = _skNameAuthorKey(s);
      _skSave(s);
    }
    final sent = await sendToUser(
      recipientUserId: hexToBytes(to),
      messageType: proto.MessageType.MT_GROUP_JOIN,
      payload: Uint8List.fromList(join.writeToBuffer()),
      groupId: hexToBytes(groupIdHex),
    );
    _groupPairsSync(g);
    _sendTwinGroupCreated(g);
    onStateChanged?.call();
    _log.info('Joined group ${groupIdHex.substring(0, 8)} — own entry to '
        '${to.substring(0, 8)} (${sent ? 'handed over' : 'not sent'})');
    return true;
  }

  /// `GROUP_JOIN` at the inviter: the joiner's self-signed entry is checked,
  /// kept with the fixed neighbours this identity knows of it, and goes to
  /// every member in the next update (a full entry only for it, E2 = c).
  void _handleGroupJoin(HarvestEvent event) {
    final senderHex = event.senderUserId.hex;
    final proto.GroupJoin join;
    try {
      join = proto.GroupJoin.fromBuffer(event.payload);
    } catch (e) {
      _log.error('GROUP_JOIN parse failed: $e');
      return;
    }
    final gid = join.groupId.hex;
    final g = _groups[gid];
    // §4.3, §16.2.2: a subscriber's entry for a private channel.
    if (g == null && _channels.containsKey(gid)) {
      _channelJoinReceived(senderHex, join);
      return;
    }
    final member = g?.members[senderHex];
    if (g == null || member == null || !_hasGroupPermission(g, 'invite')) {
      _log.warn('GROUP_JOIN from ${senderHex.substring(0, 8)}: no such member '
          'or no owner/admin here — discarded');
      return;
    }
    final w = join.member;
    // §4.4.3 (S407-UMSCHLAG): only the mark, no entry — the one-time renewal
    // of a member that joined before (`cleona_service_pair_tag.dart`).
    if (_groupEntryMarkOnly(g, senderHex, member, w, join)) return;
    final a = w.nodeId.hex == senderHex
        ? groupMemberCheck(hexToBytes(gid), Uint8List.fromList(w.address),
            Uint8List.fromList(w.addressSigEd25519),
            Uint8List.fromList(w.addressSigMlDsa))
        : null;
    if (a == null || bytesToHex(a.identifier) != senderHex) {
      _log.warn('GROUP_JOIN from ${senderHex.substring(0, 8)}: the entry does '
          'not prove itself — discarded (E3)');
      _groupNotice(g, senderHex, kNoticeGroupMemberUnconfirmed, 'unconfirmed');
      return;
    }
    final known = myceliumMailbox?.contactOrNull(senderHex)?.neighbours ??
        const <CardAddress>[];
    member
      ..address = Uint8List.fromList(w.address)
      ..addressSigEd25519 = Uint8List.fromList(w.addressSigEd25519)
      ..addressSigMlDsa = Uint8List.fromList(w.addressSigMlDsa)
      ..readsPairTag = w.readsPairTag
      ..neighbours = known.isNotEmpty
          ? groupMemberNeighboursWire(known)
          : (w.neighbours.isEmpty ? null : Uint8List.fromList(w.neighbours));
    g.membershipEpoch++;
    _saveGroups();
    if (join.authorPk.length == 32) {
      final s = _skOrNew(gid);
      s.named[senderHex] = bytesToHex(Uint8List.fromList(join.authorPk));
      _skSave(s);
    }
    _log.info('GROUP_JOIN: ${senderHex.substring(0, 8)} joined '
        '${gid.substring(0, 8)} — entry passed on');
    // §16.2.5 "Joining": the keys first — `_skAdmit` advances the step before
    // its first `await` —, so that the membership update, built before its
    // own first `await` from THIS state, carries the step; then the size.
    // No `await` between them: a second joining must not overtake the
    // update of the first (`smoke_group_join_concurrent_run`).
    unawaited(_skAdmit(gid, senderHex));
    unawaited(_broadcastGroupUpdate(g, fresh: {senderHex}));
    unawaited(_skSizeCheck(gid));
    // §16.2.2, §21.5.4: a member who joins is told the settings in force —
    // one 1:1 delivery, none on the defaults.
    _settingsToNewcomer(gid, senderHex);
    onStateChanged?.call();
  }
}
