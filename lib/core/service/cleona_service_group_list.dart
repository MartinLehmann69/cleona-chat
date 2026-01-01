// The member list of a GROUP as changes (v4_2 §16.2.2 "Invites",
// "Membership consistency", §16.2 "Fan-out does not serialize", D-21;
// S407 group list, report `mycelium/berichte/S407-GRUPPENLISTE.md`).
//
// §16.2.2: "A membership change carries full entries only for members who
// are new and is a change, never the whole list again." Until S407 every
// joining, invitation, removal, leaving and change of role sent every member
// the whole list (`GroupInvite`, one compact entry per member with its
// three public keys, the full entry of the new member and the ML-DSA
// signature — about 32 KB per leg at 17 members, finding F-1 of
// `S407-KANALSCHRITT2.md`).
//
// WHAT HAPPENS NOW:
//  * A member that is new to the group gets the complete list, as before:
//    it knows every participant before joining.
//  * Every other member that has shown the capability of the member list
//    (`CapabilityNotice`, bit [kCapMemberList], §16.2.5) gets a
//    [proto.GroupMembersChange]: the members new to it or whose role
//    changed (a full entry only for those whose self-signed entry is new),
//    the members gone, its `s_AB` with every new member (§4.3) and the
//    canonical membership hash after the change. A different hash after
//    applying asks the owner for the state once (resync).
//  * A member that has not shown the capability — a v4.2.3 device (checked
//    on `398a6e40`: it discards the unknown kind 99 after the receipt,
//    `lib/core/service/cleona_service_receive.dart:118`) — gets the
//    `GroupInvite` update it reads, exactly as before.
//  * Every leg of one change leaves at once ([_groupUpdateLegsSend]); the
//    changes of one group stay in order (S406-CATCHUP).
//  * A resync request is answered to the one who asked, not to every member.

part of 'cleona_service.dart';

/// One leg of a group membership change: recipient, kind, payload.
typedef _GroupLeg = (String, proto.MessageType, Uint8List);

extension CleonaServiceGroupList on CleonaService {
  /// Whether [hex] reads a membership change (§16.2.2) — it showed the
  /// capability of the member list.
  bool _groupTakesChanges(String hex) {
    if (groupListAsChangesOff) return false;
    _skLoadAll();
    return (_capabilities[hex]?.$1 ?? 0) & kCapMemberList != 0;
  }

  /// The capability bits [hex] has shown — read by probes only.
  @visibleForTesting
  int debugCapabilityBits(String hex) {
    _skLoadAll();
    return _capabilities[hex]?.$1 ?? 0;
  }

  /// The change for [toHex]:[upserted] members (a full entry where
  /// [fullFor] names them and the entry is signed), [removed], the seeds of
  /// [toHex] with every member of [newMembers] (and with everyone when it is
  /// new itself — it never gets a change then), the hash after it.
  Uint8List _groupChangeBytes(GroupInfo g, String toHex,
      {required Iterable<String> upserted,
      required Set<String> fullFor,
      required Iterable<String> removed,
      required Set<String> newMembers,
      required Map<String, Uint8List> seeds}) {
    final ch = proto.GroupMembersChange()
      ..groupId = hexToBytes(g.groupIdHex)
      ..membershipEpoch = Int64(g.membershipEpoch)
      ..stateHash =
          _computeMembershipHash(g.membershipEpoch, g.groupIdHex, g.members);
    for (final id in upserted) {
      final m = g.members[id];
      if (m == null || id == toHex) continue;
      ch.upserted.add(_groupMemberWire(m, full: fullFor.contains(id)));
    }
    // The receiver's own role, where it changed.
    if (upserted.contains(toHex) && g.members[toHex] != null) {
      ch.upserted.add(_groupMemberWire(g.members[toHex]!, full: false));
    }
    for (final id in removed) {
      ch.removed.add(hexToBytes(id));
    }
    for (final x in newMembers) {
      if (x == toHex || x == identity.userIdHex || !g.members.containsKey(x)) {
        continue;
      }
      ch.pairSeeds.add(proto.GroupPairSeed()
        ..memberId = hexToBytes(x)
        ..seed = _groupSeedFor(seeds, toHex, x));
    }
    final step = _skStep(_sk(g.groupIdHex));
    if (step != null) ch.sharedKeyStep = step;
    return Uint8List.fromList(ch.writeToBuffer());
  }

  /// The legs of one membership change of [g], built here before any
  /// `await` (S406-CATCHUP): the complete list for a member new to the group
  /// and for one that reads no change, the change for everyone else.
  /// [extraTo]: members no longer in [g] that are owed the change as well
  /// (the removed member, §16.2.2).
  List<_GroupLeg> _groupUpdateLegs(GroupInfo g,
      {Set<String> fresh = const {},
      Set<String> newMembers = const {},
      Set<String> changed = const {},
      Set<String> removed = const {},
      Set<String> extraTo = const {}}) {
    final seeds = <String, Uint8List>{};
    final upserted = {...newMembers, ...fresh, ...changed};
    final isChange =
        upserted.isNotEmpty || removed.isNotEmpty;
    final legs = <_GroupLeg>[];
    for (final m in g.members.values.toList()) {
      final to = m.nodeIdHex;
      if (to == identity.userIdHex) continue;
      if (newMembers.contains(to) || !isChange || !_groupTakesChanges(to)) {
        legs.add((
          to,
          proto.MessageType.MT_GROUP_INVITE,
          _buildSignedGroupInviteBytes(g,
              recipientHex: to,
              fresh: fresh,
              newMembers: newMembers,
              seeds: seeds),
        ));
        continue;
      }
      legs.add((
        to,
        proto.MessageType.MT_GROUP_MEMBERS_CHANGE,
        _groupChangeBytes(g, to,
            upserted: upserted,
            fullFor: fresh,
            removed: removed,
            newMembers: newMembers,
            seeds: seeds),
      ));
    }
    for (final to in extraTo) {
      if (to == identity.userIdHex || g.members.containsKey(to)) continue;
      legs.add(_groupTakesChanges(to)
          ? (
              to,
              proto.MessageType.MT_GROUP_MEMBERS_CHANGE,
              _groupChangeBytes(g, to,
                  upserted: const [],
                  fullFor: const {},
                  removed: removed,
                  newMembers: const {},
                  seeds: seeds),
            )
          // The list without it is its removal (S403, V2) — built like a
          // membership resend, without seeds and without fresh entries.
          : (
              to,
              proto.MessageType.MT_GROUP_INVITE,
              _buildSignedGroupInviteBytes(g, recipientHex: to),
            ));
    }
    return legs;
  }

  /// Test hook: payload bytes of membership legs per recipient.
  void _groupListBytesNote(String to, int n) {
    final sink = groupListBytes;
    if (sink == null) return;
    sink[to] = (sink[to] ?? 0) + n;
  }

  /// MT_GROUP_MEMBERS_CHANGE (§16.2.2): a membership change of a group as
  /// a change, from an owner or admin of the OLD state (authority gate; the
  /// sender of a leg is fixed by the pairwise seal, no inner signature).
  ///
  /// [mirrored]: another own device collected the change and mirrored it
  /// (§14.7 Type 18, D-91). It is applied as here; only the owner's duty
  /// after a departure (the next shared-key generation, §16.2.5) stays with
  /// the collecting device — two devices of one owner must not draw two.
  void _groupMembersChangeReceived(HarvestEvent event,
      {bool mirrored = false}) {
    final senderHex = event.senderUserId.hex;
    final proto.GroupMembersChange ch;
    try {
      ch = proto.GroupMembersChange.fromBuffer(event.payload);
    } catch (e) {
      _log.warn('GROUP_MEMBERS_CHANGE parse failed: $e');
      return;
    }
    final gid = ch.groupId.hex;
    final g = _groups[gid];
    if (g == null) {
      _log.info('GROUP_MEMBERS_CHANGE for a group this device does not hold '
          '— nothing to change');
      return;
    }
    final sender = g.members[senderHex];
    if (sender == null || (sender.role != 'owner' && sender.role != 'admin')) {
      _log.warn('GM-1: GROUP_MEMBERS_CHANGE from non-admin '
          '${senderHex.substring(0, 8)} for "${g.name}" — rejected');
      return;
    }
    final meHex = identity.userIdHex;
    final epoch = ch.membershipEpoch.toInt();
    if (ch.removed.any((r) => r.hex == meHex)) {
      if (epoch > g.membershipEpoch) _groupRemovedFrom(gid, epoch);
      return;
    }
    final gidBytes = Uint8List.fromList(ch.groupId);
    if (epoch <= g.membershipEpoch) {
      // §16.2.2: a late change decides nothing; a self-signed entry it
      // carries for a member held without one is taken.
      var taken = 0;
      for (final w in ch.upserted) {
        final held = g.members[w.nodeId.hex];
        // §4.4.3 (S407-UMSCHLAG): the pair-tag mark of a renewed entry
        // travels as such a change at the held epoch — it changes no member,
        // only adds a mark (never removes one).
        if (held != null && w.readsPairTag && !held.readsPairTag &&
            held.hasSignedEntry && w.nodeId.hex != meHex) {
          held.readsPairTag = true;
          taken++;
        }
        if (w.address.isEmpty || held == null || held.hasSignedEntry) continue;
        if (_groupEntryTake(gidBytes, w, held)) taken++;
      }
      if (taken > 0) {
        _saveGroups();
        final before = _groupPairCount(gid);
        _groupPairsSync(g);
        if (g.joined && _groupPairCount(gid) > before) _sendTwinGroupCreated(g);
        onStateChanged?.call();
      }
      _log.info('GROUP_MEMBERS_CHANGE at epoch $epoch for "${g.name}" — not '
          'newer than ${g.membershipEpoch}, $taken entries taken');
      return;
    }
    final unconfirmed = <String>{};
    final oldOwner = g.ownerNodeIdHex;
    // A change of role is shown as the owner shows it (`setMemberRole`) —
    // the membership update is the only carrier of the role now (F-1b).
    void roleShown(GroupMemberInfo m, String from) {
      if (from == m.role || from.isEmpty) return;
      _addSystemMessage(gid, '${m.displayName}: $from → ${m.role}',
          type: UiMessageType.channelRoleUpdate, isGroup: true);
    }

    for (final w in ch.upserted) {
      final id = w.nodeId.hex;
      if (id == meHex) {
        // Only the own role is taken; the own entry is this device's.
        final me = g.members[meHex];
        if (me != null && w.role.isNotEmpty) {
          final from = me.role;
          me.role = w.role;
          roleShown(me, from);
        }
        continue;
      }
      final held = g.members[id]?.role ?? '';
      Uint8List? opt(List<int> b) => b.isEmpty ? null : Uint8List.fromList(b);
      final m = g.members[id] ??= GroupMemberInfo(
        nodeIdHex: id,
        displayName: w.displayName,
        role: w.role,
        ed25519Pk: opt(w.ed25519PublicKey),
        x25519Pk: opt(w.x25519PublicKey),
        mlKemPk: opt(w.mlKemPublicKey),
      );
      if (w.role.isNotEmpty) m.role = w.role;
      if (w.displayName.isNotEmpty) m.displayName = w.displayName;
      if (w.readsPairTag) m.readsPairTag = true; // §4.4.3 (S407-UMSCHLAG)
      roleShown(m, held);
      if (w.address.isNotEmpty && !_groupEntryTake(gidBytes, w, m)) {
        unconfirmed.add(id);
      }
    }
    for (final r in ch.removed) {
      g.members.remove(r.hex);
    }
    for (final m in g.members.values) {
      if (m.role == 'owner') g.ownerNodeIdHex = m.nodeIdHex;
    }
    g.membershipEpoch = epoch;
    _saveGroups();
    final p = myceliumMailbox;
    if (p != null) {
      for (final s in ch.pairSeeds) {
        if (!g.members.containsKey(s.memberId.hex)) continue;
        p.groupPairSeed(gidBytes, Uint8List.fromList(s.memberId),
            Uint8List.fromList(s.seed));
      }
    }
    final before = _groupPairCount(gid);
    _groupPairsSync(g, unconfirmed: unconfirmed);
    if (g.joined && _groupPairCount(gid) > before) _sendTwinGroupCreated(g);
    if (ch.hasSharedKeyStep()) _skStepHeard(gid, ch.sharedKeyStep);
    // An owner or admin new to this device is owed the notice.
    unawaited(_capabilityNoticesDue());
    // §16.2.5 "Leaving and removal": the owner left and passed the role to
    // this device — it draws the next generation, as after a GROUP_LEAVE.
    if (!mirrored &&
        oldOwner != meHex &&
        g.ownerNodeIdHex == meHex &&
        !g.members.containsKey(oldOwner)) {
      unawaited(_skDeparted(gid));
    }
    final expect = _computeMembershipHash(epoch, gid, g.members);
    if (ch.stateHash.isNotEmpty &&
        !constantTimeEquals(Uint8List.fromList(ch.stateHash), expect)) {
      _log.warn('GROUP_MEMBERS_CHANGE for "${g.name}": the state after it '
          'differs from the sender\'s — resync asked (§16.2.2)');
      _sendResyncRequest(g, localEpoch: 0);
    }
    _log.info('GROUP_MEMBERS_CHANGE for "${g.name}" from '
        '${senderHex.substring(0, 8)}: +${ch.upserted.length} '
        '-${ch.removed.length}, epoch $epoch');
    onStateChanged?.call();
  }

  /// Takes the self-signed entry in [w] into [m] if it proves itself.
  bool _groupEntryTake(Uint8List gid, proto.GroupMember w, GroupMemberInfo m) {
    final a = groupMemberCheck(gid, Uint8List.fromList(w.address),
        Uint8List.fromList(w.addressSigEd25519),
        Uint8List.fromList(w.addressSigMlDsa));
    if (a == null || bytesToHex(a.identifier) != m.nodeIdHex) return false;
    m
      ..address = Uint8List.fromList(w.address)
      ..addressSigEd25519 = Uint8List.fromList(w.addressSigEd25519)
      ..addressSigMlDsa = Uint8List.fromList(w.addressSigMlDsa)
      ..neighbours = w.neighbours.isEmpty
          ? m.neighbours
          : Uint8List.fromList(w.neighbours);
    return true;
  }
}
