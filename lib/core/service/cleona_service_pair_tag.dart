// S407-UMSCHLAG (v4_2 §4.4.3, §1.2 principle 8, §16.2.2): the pair tag for
// group pairs whose members joined before this release.
//
// A group pair seals with the pair tag once the co-member's own entry says
// it reads it (`reads_pair_tag`, set at the join — `_groupOwnEntrySign`).
// An entry signed before this release carries no mark, and neither side of
// such a pair ever starts with the tag: the group would stay signed for
// good. Two things at the attach of the mailbox close that:
//
//  * the marks held in the member state of groups and private channels go
//    back into the mailbox — they live in memory only there
//    (`mailbox_envelope_tag.dart`); no packet;
//  * ONCE per group whose own entry carries no mark, only the mark goes to
//    the owner or admin who passes entries on (a `GROUP_JOIN` without an
//    entry, [_groupEntryMarkOnly]); that member passes it on as a
//    [proto.GroupMembersChange] at the HELD epoch to the members that carry
//    the mark themselves and read changes ([_pairTagMarkPass]) — no member
//    list, no epoch step, nothing to a device of an earlier 4.2 version.
//
// Only to an owner or admin that showed this release ([NeighbourKeysContact
// .readsKeysOf]): an older 4.2 device would not read the mark and pass on
// nothing — the renewal waits for its update, checked
// again at the next start (an edge, never a timer). No retry here: the
// delivery layer carries the one `GROUP_JOIN` (§11.3a); the own mark is set
// only once it was handed over, so it goes at most once per group.

part of 'cleona_service.dart';

extension CleonaServicePairTag on CleonaService {
  /// At the attach of [p]: marks back into the mailbox, renewals due.
  void _pairTagAttach(mycelium.Mailbox p) {
    for (final g in _groups.values) {
      if (!g.joined) continue;
      for (final m in g.members.values) {
        if (m.nodeIdHex != identity.userIdHex &&
            m.readsPairTag &&
            p.groupPairOrNull(m.nodeIdHex) != null) {
          p.groupPairReadsTag(m.nodeIdHex);
        }
      }
      unawaited(_groupOwnEntryRenew(p, g));
    }
    // Channel pairs exist only from this release on: a co-subscriber with a
    // signed channel entry reads the tag (`_channelPairsSync`).
    for (final c in _channels.values) {
      if (!(c.members[identity.userIdHex]?.hasSignedEntry ?? false)) continue;
      for (final m in c.members.values) {
        if (m.nodeIdHex != identity.userIdHex &&
            m.hasSignedEntry &&
            p.groupPairOrNull(m.nodeIdHex) != null) {
          p.groupPairReadsTag(m.nodeIdHex);
        }
      }
    }
  }

  /// The one-time renewal of the own entry of [g] (see the head).
  Future<void> _groupOwnEntryRenew(mycelium.Mailbox p, GroupInfo g) async {
    final me = g.members[identity.userIdHex];
    if (me == null || !me.hasSignedEntry || me.readsPairTag) return;
    if (_hasGroupPermission(g, 'invite')) {
      // This identity passes entries on itself.
      me.readsPairTag = true;
      _saveGroups();
      _log.info('pair tag: own entry of ${g.groupIdHex.substring(0, 8)} '
          'renewed — mark to the members that read changes');
      _pairTagMarkPass(g, me.nodeIdHex);
      return;
    }
    final to = _pairTagPasserOf(g);
    final k = to == null ? null : p.contactOrNull(to);
    if (to == null || k == null || !p.readsKeysOf(k.address)) return;
    // Only the mark: the passer holds the signed entry already, and the leg
    // itself names the sender (pairwise seal) — ≈ 76 B instead of ≈ 8 KB.
    final join = proto.GroupJoin()
      ..groupId = hexToBytes(g.groupIdHex)
      ..member = (proto.GroupMember()
        ..nodeId = hexToBytes(me.nodeIdHex)
        ..readsPairTag = true);
    final sent = await sendToUser(
      recipientUserId: hexToBytes(to),
      messageType: proto.MessageType.MT_GROUP_JOIN,
      payload: Uint8List.fromList(join.writeToBuffer()),
      groupId: hexToBytes(g.groupIdHex),
    );
    if (!sent) return;
    me.readsPairTag = true;
    _saveGroups();
    _log.info('pair tag: own entry of ${g.groupIdHex.substring(0, 8)} '
        'renewed at ${to.substring(0, 8)}');
  }

  /// Who passes entries of [g] on: the inviter while it is owner or admin,
  /// otherwise the owner.
  String? _pairTagPasserOf(GroupInfo g) {
    final inviter = g.inviterNodeIdHex;
    final role = inviter == null ? null : g.members[inviter]?.role;
    if (role == 'owner' || role == 'admin') return inviter;
    final owner = g.ownerNodeIdHex;
    return owner == identity.userIdHex ? null : owner;
  }

  /// At the member that passes entries on: a `GROUP_JOIN` from [senderHex]
  /// that carries no entry, only the mark, for a member whose signed entry
  /// is held. It is no joining (no author key, admission, settings, epoch).
  /// `true`: handled.
  bool _groupEntryMarkOnly(GroupInfo g, String senderHex,
      GroupMemberInfo member, proto.GroupMember w, proto.GroupJoin join) {
    if (w.address.isNotEmpty ||
        !w.readsPairTag ||
        w.nodeId.hex != senderHex ||
        join.authorPk.isNotEmpty ||
        !member.hasSignedEntry) {
      return false;
    }
    if (member.readsPairTag) return true; // nothing new, nothing sent
    member.readsPairTag = true;
    _saveGroups();
    _log.info('pair tag: ${senderHex.substring(0, 8)} reads it in '
        '${g.groupIdHex.substring(0, 8)}');
    _pairTagMarkPass(g, senderHex);
    return true;
  }

  /// The mark of [xHex] to every other member of [g] that carries the mark
  /// and reads membership changes (§16.2.2, bit [kCapMemberList]): a
  /// [proto.GroupMembersChange] at
  /// the HELD epoch — it changes no member, so no epoch, no hash change, and
  /// a member of an earlier 4.2 version (which neither reads the mark nor
  /// forms pairs that could use it with this one) gets nothing and keeps a
  /// consistent epoch. Receivers take it as a late change
  /// (`_groupMembersChangeReceived`). ≈ 110 B payload per leg.
  void _pairTagMarkPass(GroupInfo g, String xHex) {
    final ch = proto.GroupMembersChange()
      ..groupId = hexToBytes(g.groupIdHex)
      ..membershipEpoch = Int64(g.membershipEpoch)
      ..stateHash =
          _computeMembershipHash(g.membershipEpoch, g.groupIdHex, g.members)
      ..upserted.add(proto.GroupMember()
        ..nodeId = hexToBytes(xHex)
        ..readsPairTag = true);
    final payload = Uint8List.fromList(ch.writeToBuffer());
    var n = 0;
    for (final e in g.members.entries) {
      final to = e.key;
      // Only to a member that carries the mark itself: of each pair the one
      // that renews second carries it to the first, and the first learns
      // the other's from its first tagged leg (`tagShown`) — one leg per
      // pair, not two.
      if (to == identity.userIdHex ||
          to == xHex ||
          !e.value.readsPairTag ||
          !_groupTakesChanges(to)) {
        continue;
      }
      n++;
      _groupListBytesNote(to, payload.length);
      unawaited(sendToUser(
        recipientUserId: hexToBytes(to),
        messageType: proto.MessageType.MT_GROUP_MEMBERS_CHANGE,
        payload: payload,
        groupId: hexToBytes(g.groupIdHex),
      ));
    }
    _log.info('pair tag: mark of ${xHex.substring(0, 8)} to $n member(s), '
        '${payload.length} B each');
  }
}
