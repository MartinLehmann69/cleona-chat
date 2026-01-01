// Group pairs in private channels (v4_2 §4.3 "`s_AB` for co-members who are
// not contacts … of a group or private channel (§16.2)", §16.2.2, D-36).
//
// The same mechanism as for groups (`cleona_service_group_pairs.dart`), with
// the channel identifier as the group identifier of the pair:
//  * the invitation leg to each subscriber carries `s_AB` for every pair the
//    invitation makes co-members (`ChannelInvite.pair_seeds`), and every
//    member's address as the member itself signed it for this channel;
//  * a subscriber signs its own entry when the first invitation arrives (a
//    channel has no separate join step) and sends it to the inviter as
//    `GROUP_JOIN`; the inviter passes it on in the next update;
//  * with a co-subscriber's checked entry and the waiting seed the mailbox
//    forms the pair. Where two members share several groups or channels the
//    mailbox takes the seed of the smallest identifier (`GroupPair.pairRandom`)
//    — one rule across both, because a channel identifier is just another
//    group identifier there.
//
// 4.2.3 (D-21): `pair_seeds` is a new field — an older device keeps it as an
// unknown field and ignores it; the entry fields of `GroupMember` are read
// by its group path only. A `GROUP_JOIN` naming a channel finds no group
// there and is discarded after its receipt.

part of 'cleona_service.dart';

extension CleonaServiceChannelPairs on CleonaService {
  /// [m] on the wire; with its signed entry only when [full].
  proto.GroupMember _channelMemberWire(ChannelMemberInfo m,
      {required bool full}) {
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
    return w;
  }

  /// Signs the own entry of [c] with the current keys of this identity's
  /// post box. `false`: no mailbox, or not a member.
  bool _channelOwnEntrySign(ChannelInfo c) {
    final p = myceliumMailbox;
    final me = c.members[identity.userIdHex];
    if (p == null || me == null) return false;
    final e = groupMemberSign(p.identity.postBox, hexToBytes(c.channelIdHex));
    me
      ..address = e.address
      ..addressSigEd25519 = e.ed
      ..addressSigMlDsa = e.dsa
      ..neighbours = groupMemberNeighboursWire(p.ownNeighbours);
    return true;
  }

  /// The checked entry of [m] for [channelIdHex] into [into]; `false` if it
  /// does not prove itself (the member's own signature over this channel,
  /// its identifier the member's UserID).
  bool _channelEntryTake(
      String channelIdHex, proto.GroupMember m, ChannelMemberInfo into) {
    final a = groupMemberCheck(hexToBytes(channelIdHex),
        Uint8List.fromList(m.address), Uint8List.fromList(m.addressSigEd25519),
        Uint8List.fromList(m.addressSigMlDsa));
    if (a == null || bytesToHex(a.identifier) != into.nodeIdHex) return false;
    into
      ..address = Uint8List.fromList(m.address)
      ..addressSigEd25519 = Uint8List.fromList(m.addressSigEd25519)
      ..addressSigMlDsa = Uint8List.fromList(m.addressSigMlDsa)
      ..neighbours = m.neighbours.isEmpty
          ? into.neighbours
          : Uint8List.fromList(m.neighbours);
    return true;
  }

  /// The entries of an arriving invitation into [members] — a full one only
  /// if it proves itself, a compact one keeps what [old] held.
  void _channelEntriesTake(proto.ChannelInvite invite,
      Map<String, ChannelMemberInfo> members, ChannelInfo? old) {
    final cid = invite.channelId.hex;
    for (final w in invite.members) {
      final info = members[w.nodeId.hex];
      if (info == null) continue;
      final prev = old?.members[info.nodeIdHex];
      if (w.address.isNotEmpty && _channelEntryTake(cid, w, info)) continue;
      if (prev != null && prev.hasSignedEntry) {
        info
          ..address = prev.address
          ..addressSigEd25519 = prev.addressSigEd25519
          ..addressSigMlDsa = prev.addressSigMlDsa
          ..neighbours = prev.neighbours;
      }
    }
  }

  /// A LATE invitation (epoch not above [c]'s) decides nothing, but a
  /// self-signed entry it carries for a member [c] holds without one is
  /// taken — as for a group (§16.2.2). Returns how many were taken.
  int _channelLateEntriesTake(proto.ChannelInvite invite, ChannelInfo c) {
    var taken = 0;
    for (final w in invite.members) {
      final held = c.members[w.nodeId.hex];
      if (w.address.isEmpty || held == null || held.hasSignedEntry) continue;
      if (_channelEntryTake(c.channelIdHex, w, held)) taken++;
    }
    return taken;
  }

  /// The seeds of an invitation for THIS identity wait in the mailbox until
  /// the pair can be formed.
  void _channelPairSeedsTake(proto.ChannelInvite invite, ChannelInfo c) {
    final p = myceliumMailbox;
    if (p == null) return;
    final cid = Uint8List.fromList(invite.channelId);
    for (final s in invite.pairSeeds) {
      final mid = s.memberId.hex;
      if (mid == identity.userIdHex || !c.members.containsKey(mid)) continue;
      p.groupPairSeed(
          cid, Uint8List.fromList(s.memberId), Uint8List.fromList(s.seed));
    }
  }

  /// Brings the group pairs of [c] in line with its member state: members
  /// gone end their pair for this channel; with the own signed entry a pair
  /// is formed with every co-member that is not a contact and has a checked
  /// entry and a seed.
  void _channelPairsSync(ChannelInfo c) {
    final p = myceliumMailbox;
    if (p == null) return;
    final cid = hexToBytes(c.channelIdHex);
    final me = c.members[identity.userIdHex];
    if (me == null) {
      p.groupPairLeave(cid);
      return;
    }
    final ended = p.groupPairLeave(cid, keep: c.members.keys.toSet());
    if (ended > 0) {
      _log.info('channel pairs: $ended ended with the member state');
    }
    if (!me.hasSignedEntry) return;
    for (final m in c.members.values) {
      if (m.nodeIdHex == identity.userIdHex || !m.hasSignedEntry) continue;
      if (_contacts[m.nodeIdHex]?.status == 'accepted' ||
          p.contactOrNull(m.nodeIdHex) != null) {
        continue;
      }
      // §4.4.3 (S407-UMSCHLAG): channel entries exist only from this release
      // on (channel pairs, S407), so a co-subscriber that signed one has
      // itself shown it reads the pair tag.
      p.groupPairFromEntry(
          cid, m.address!, m.addressSigEd25519!, m.addressSigMlDsa!,
          neighboursWire: m.neighbours, readsTag: true);
    }
  }

  /// The first invitation into [c] arrived: the own entry is signed and goes
  /// to the inviter [toHex], who passes it on (§16.2.2).
  Future<void> _channelJoin(ChannelInfo c, String toHex) async {
    if (!_channelOwnEntrySign(c)) return;
    _saveChannels();
    // §16.2.2, §16.2.5, D-21: what this build takes — the short list and
    // changes, the shared key — goes in the capability notice, ahead of the
    // acceptance (the bit of channel step 1 went up in it).
    await _capabilityNoticesDue();
    final join = proto.GroupJoin()
      ..groupId = hexToBytes(c.channelIdHex)
      ..member = _channelMemberWire(c.members[identity.userIdHex]!, full: true);
    final sent = await sendToUser(
      recipientUserId: hexToBytes(toHex),
      messageType: proto.MessageType.MT_GROUP_JOIN,
      payload: Uint8List.fromList(join.writeToBuffer()),
      groupId: hexToBytes(c.channelIdHex),
    );
    _channelPairsSync(c);
    _log.info('Joined channel ${c.channelIdHex.substring(0, 8)} — own entry to '
        '${toHex.substring(0, 8)} (${sent ? 'handed over' : 'not sent'})');
  }

  /// `GROUP_JOIN` naming a channel, at the inviter: the subscriber's
  /// self-signed entry is checked, kept, and goes to every member in the
  /// next update.
  void _channelJoinReceived(String senderHex, proto.GroupJoin join) {
    final cid = join.groupId.hex;
    final c = _channels[cid];
    final member = c?.members[senderHex];
    if (c == null || member == null || !_hasChannelPermission(c, 'invite')) {
      _log.warn('GROUP_JOIN (channel) from ${senderHex.substring(0, 8)}: no '
          'such member or no owner/admin here — discarded');
      return;
    }
    if (join.member.nodeId.hex != senderHex ||
        !_channelEntryTake(cid, join.member, member)) {
      _log.warn('GROUP_JOIN (channel) from ${senderHex.substring(0, 8)}: the '
          'entry does not prove itself — discarded (E3)');
      return;
    }
    final known = myceliumMailbox?.contactOrNull(senderHex)?.neighbours ??
        const <CardAddress>[];
    if (known.isNotEmpty) member.neighbours = groupMemberNeighboursWire(known);
    // §16.2.2, D-21: what the subscriber's version builds — from its
    // capability notice (§16.2.5), which goes ahead of the acceptance.
    member.capabilities = _capabilities[senderHex]?.$1 ?? member.capabilities;
    c.membershipEpoch++;
    _saveChannels();
    _log.info('GROUP_JOIN: ${senderHex.substring(0, 8)} joined channel '
        '${cid.substring(0, 8)} — entry passed on '
        '(capabilities ${member.capabilities})');
    // §16.2.5 "Joining": the keys first — `_skAdmit` advances the step before
    // its first `await` —, so that the change, built from THIS state, carries
    // it; then the size. No `await` in between (order of the updates).
    unawaited(_skAdmit(cid, senderHex));
    if (_channelShortList(c)) {
      // A subscriber's joining goes to the owner and the admins only.
      unawaited(_channelShortJoined(c, member));
    } else {
      unawaited(_broadcastChannelUpdate(c, fresh: {senderHex}));
    }
    unawaited(_skSizeCheck(cid));
    _channelPairsSync(c);
    // §16.2.2, §21.5.4: the settings in force — one 1:1 delivery, none on
    // the defaults.
    _settingsToNewcomer(cid, senderHex);
  }
}
