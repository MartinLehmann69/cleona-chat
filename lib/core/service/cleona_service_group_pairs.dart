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
// NOT HERE: private channels (§4.3 names them too). Their legs still reach
// only contacts; a subscriber without one gets `failed` + the same notice.

part of 'cleona_service.dart';

/// The group types a group pair may send (§16.2.2): group post, reaction,
/// edit, deletion, read mark, poll and vote, calendar entry of a group event,
/// membership update (owner/admin, checked by its handler against the OLD
/// member state), leave, and the acknowledgement. The day-key notice of the
/// pair is a mycelium kind and never reaches this set.
const Set<proto.MessageTypeV3> kGroupPairTypes = {
  proto.MessageTypeV3.MTV3_TEXT,
  proto.MessageTypeV3.MTV3_REPLY,
  proto.MessageTypeV3.MTV3_MEDIA_INLINE,
  proto.MessageTypeV3.MTV3_MEDIA_ANNOUNCE,
  proto.MessageTypeV3.MTV3_MEDIA_HOLDERS,
  // The failure of a group file, both ways (§9.4 "Reasons"): part of the
  // group post it ends — without it a member who is no contact would show
  // another reason than the sender (OP-30).
  proto.MessageTypeV3.MTV3_MEDIA_ABORT,
  proto.MessageTypeV3.MTV3_VOICE_MESSAGE,
  proto.MessageTypeV3.MTV3_REACTION,
  proto.MessageTypeV3.MTV3_EDIT,
  proto.MessageTypeV3.MTV3_DELETE,
  proto.MessageTypeV3.MTV3_READ_RECEIPT,
  proto.MessageTypeV3.MTV3_POLL_CREATE,
  proto.MessageTypeV3.MTV3_POLL_VOTE,
  proto.MessageTypeV3.MTV3_POLL_VOTE_ANONYMOUS,
  proto.MessageTypeV3.MTV3_POLL_UPDATE,
  proto.MessageTypeV3.MTV3_POLL_SNAPSHOT,
  proto.MessageTypeV3.MTV3_POLL_REVOKE,
  proto.MessageTypeV3.MTV3_CALENDAR_INVITE,
  proto.MessageTypeV3.MTV3_CALENDAR_UPDATE,
  proto.MessageTypeV3.MTV3_CALENDAR_DELETE,
  proto.MessageTypeV3.MTV3_CALENDAR_RSVP,
  proto.MessageTypeV3.MTV3_GROUP_INVITE,
  proto.MessageTypeV3.MTV3_CHANNEL_ROLE_UPDATE,
  proto.MessageTypeV3.MTV3_GROUP_LEAVE,
  proto.MessageTypeV3.MTV3_DELIVERY_RECEIPT,
  // §9.5 "Who is asked: every contact and every group pair": the request,
  // the answer and the progress report of catching up, each naming a group
  // both belong to. (§16.2.2 does not list it among the group types yet.)
  proto.MessageTypeV3.MTV3_CATCH_UP,
};

/// The kinds whose leg without a way is NAMED in the group (stage 0) — what
/// the user posted. A receipt or a read mark without a way is only `failed`.
const Set<proto.MessageTypeV3> _kGroupPostTypes = {
  proto.MessageTypeV3.MTV3_TEXT,
  proto.MessageTypeV3.MTV3_REPLY,
  proto.MessageTypeV3.MTV3_MEDIA_INLINE,
  proto.MessageTypeV3.MTV3_MEDIA_ANNOUNCE,
  proto.MessageTypeV3.MTV3_VOICE_MESSAGE,
  proto.MessageTypeV3.MTV3_POLL_CREATE,
  proto.MessageTypeV3.MTV3_CALENDAR_INVITE,
};

extension CleonaServiceGroupPairs on CleonaService {
  // ── The gate (§15.7) ──────────────────────────────────────────────────

  /// Whether [frame] from [senderHex] — no contact — passes as from a group
  /// pair: a group type naming a group both belong to in the CURRENT member
  /// state, which this identity joined and which carries the pair.
  bool _groupPairAdmits(proto.ApplicationFrameV3 frame, String senderHex) {
    final p = myceliumMailbox;
    if (p == null ||
        !kGroupPairTypes.contains(frame.messageType) ||
        frame.groupId.isEmpty) {
      return false;
    }
    final gid = bytesToHex(Uint8List.fromList(frame.groupId));
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
  mycelium.Outbound? _groupPairFrameSend(mycelium.Mailbox p,
      {required String recipientHex,
      required Uint8List frame,
      proto.MessageTypeV3? messageType,
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
      {Uint8List? groupId, proto.MessageTypeV3? messageType}) {
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
  proto.GroupMemberV3 _groupMemberWire(GroupMemberInfo m, {required bool full}) {
    final w = proto.GroupMemberV3()
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
      ..neighbours = groupMemberNeighboursWire(p.ownNeighbours);
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
      proto.GroupInviteV3 invite, GroupInfo? old, Set<String> unconfirmed) {
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
            ..neighbours = opt(m.neighbours) ?? prev?.neighbours;
        } else {
          unconfirmed.add(nid);
        }
      } else if (prev != null && prev.hasSignedEntry) {
        info
          ..address = prev.address
          ..addressSigEd25519 = prev.addressSigEd25519
          ..addressSigMlDsa = prev.addressSigMlDsa
          ..neighbours = prev.neighbours;
      }
      members[nid] = info;
    }
    return members;
  }

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
  void _groupPairSeedsTake(proto.GroupInviteV3 invite, GroupInfo g) {
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
          neighboursWire: m.neighbours);
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
    final to = g.inviterNodeIdHex ?? g.ownerNodeIdHex;
    final join = proto.GroupJoin()
      ..groupId = hexToBytes(groupIdHex)
      ..member = _groupMemberWire(me, full: true);
    final sent = await sendToUser(
      recipientUserId: hexToBytes(to),
      messageType: proto.MessageTypeV3.MTV3_GROUP_JOIN,
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
  void _handleGroupJoinV3(HarvestEvent event) {
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
    final member = g?.members[senderHex];
    if (g == null || member == null || !_hasGroupPermission(g, 'invite')) {
      _log.warn('GROUP_JOIN from ${senderHex.substring(0, 8)}: no such member '
          'or no owner/admin here — discarded');
      return;
    }
    final w = join.member;
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
      ..neighbours = known.isNotEmpty
          ? groupMemberNeighboursWire(known)
          : (w.neighbours.isEmpty ? null : Uint8List.fromList(w.neighbours));
    g.membershipEpoch++;
    _saveGroups();
    _log.info('GROUP_JOIN: ${senderHex.substring(0, 8)} joined '
        '${gid.substring(0, 8)} — entry passed on');
    unawaited(_broadcastGroupUpdate(g, fresh: {senderHex}));
    onStateChanged?.call();
  }
}
