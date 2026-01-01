// The member list of a private channel (v4_2 §16.2.2 "Invites" and
// "Membership consistency", D-59, D-21; S407 channel step 1).
//
// In a private channel of any size a subscriber knows only the owner and
// the admins; the owner and the admins know everyone. A membership change
// is a change, never the whole list again, and it reaches only the members
// whose list it touches: a subscriber's joining, leaving or removal goes to
// the owner, the admins and that subscriber, a change of role to every
// member. Group pairs (§4.3) exist only between owner/admins and the
// others; subscribers do not pair with each other.
//
// Two epochs (§16.2.2): the membership epoch M, which owner and admins keep
// among themselves, and the role state — owner and admins with their roles
// — whose epoch R every member holds. R is the M of the last change of the
// role state, so it only grows and never overtakes M.
//
// MIXED OPERATION WITH 4.2.3 (D-21; checked on the code of `398a6e40`,
// report `mycelium/berichte/S407-KANALSCHRITT1.md`):
//  * A 4.2.3 subscriber takes the short list as the whole list (a new
//    channel is not hash-checked; an update is checked over the list as
//    sent). It keeps the invitation's epoch and checks every post against
//    the hash of the list it holds — so the legs to it carry the epoch of
//    the short list it was last given (`viewEpoch`) and the hash over
//    owner, admins and itself.
//  * It knows no change message and reads a role update for a member it
//    does not know as nothing: on every change of the role state it gets
//    the short list again, never a change message and never the leaving of
//    the owner (it would pick a new owner from a list that is not complete).
//  * Only a device that showed the capability in its acceptance
//    (`GroupJoin.capabilities`, bit [kChannelCapListAsChanges]) gets changes
//    and the role-state hash. Before its acceptance arrives a device counts
//    as 4.2.3.
//  * Where the owner or an admin has not shown the capability, the channel
//    stays as it was: the complete list to everyone, every update in full
//    ([CleonaService._broadcastChannelUpdate]) — that admin would send the
//    complete list itself.

part of 'cleona_service.dart';

/// §16.2.2: the member list of a private channel as owner and admins at a
/// subscriber, changes as changes (S407 channel step 1). Shown in
/// `GroupJoin.capabilities`.
const int kChannelCapListAsChanges = 1;

/// One leg of a membership change: recipient, kind, payload.
typedef _ChannelLeg = (String, proto.MessageType, Uint8List);

extension CleonaServiceChannelList on CleonaService {
  bool _channelIsRole(ChannelMemberInfo? m) =>
      m != null && (m.role == 'owner' || m.role == 'admin');

  bool _channelShows(ChannelMemberInfo m) =>
      m.nodeIdHex == identity.userIdHex ||
      m.capabilities & kChannelCapListAsChanges != 0;

  /// Whether [c] runs the short list: private, and the owner and every
  /// admin showed the capability (this device builds it).
  bool _channelShortList(ChannelInfo c) {
    if (c.isPublic || channelShortListOff) return false;
    for (final m in c.members.values) {
      if (_channelIsRole(m) && !_channelShows(m)) return false;
    }
    return true;
  }

  /// The role epoch of [c]; a channel from before it starts at its
  /// membership epoch.
  int _channelRoleEpoch(ChannelInfo c) {
    if (c.roleEpoch == 0) c.roleEpoch = c.membershipEpoch;
    return c.roleEpoch;
  }

  Map<String, ChannelMemberInfo> _channelRoleState(ChannelInfo c) => {
        for (final e in c.members.entries)
          if (_channelIsRole(e.value)) e.key: e.value,
      };

  /// The canonical hash of the role state at [epoch] (§16.2.2).
  Uint8List _channelRoleHash(int epoch, ChannelInfo c) =>
      _computeChannelMembershipHash(
          epoch, c.channelIdHex, _channelRoleState(c));

  /// The short list of subscriber [xHex]: owner, admins and itself.
  Map<String, ChannelMemberInfo> _channelViewOf(ChannelInfo c, String xHex) =>
      {
        ..._channelRoleState(c),
        if (c.members[xHex] != null) xHex: c.members[xHex]!,
      };

  /// The epoch and hash a leg of [c] to [toHex] carries, where it is not
  /// the complete state: `null` keeps the caller's (membership epoch and
  /// hash over the complete list). Only owner and admins send this way.
  (int, Uint8List)? _channelRosterFor(ChannelInfo c, String toHex) {
    if (c.isPublic || !_channelIsRole(c.members[identity.userIdHex])) {
      return null;
    }
    final x = c.members[toHex];
    if (x == null || _channelIsRole(x) || x.viewEpoch == 0) return null;
    if (_channelShows(x)) {
      final r = _channelRoleEpoch(c);
      return (r, _channelRoleHash(r, c));
    }
    return (
      x.viewEpoch,
      _computeChannelMembershipHash(
          x.viewEpoch, c.channelIdHex, _channelViewOf(c, toHex)),
    );
  }

  /// The check of a post's epoch and hash at a subscriber that holds the
  /// short list. `true`: split-view anomaly; `false`: matches, or a newer
  /// state was seen and a resync asked once per epoch.
  bool _channelRoleViewMismatch(
      ChannelInfo c, int wireEpoch, Uint8List wireHash, String senderHex) {
    final r = c.roleEpoch;
    final v = c.viewEpoch;
    if (wireEpoch == r && constantTimeEquals(wireHash, _channelRoleHash(r, c))) {
      return false;
    }
    if (wireEpoch == v &&
        constantTimeEquals(wireHash,
            _computeChannelMembershipHash(v, c.channelIdHex, c.members))) {
      return false;
    }
    final local = r > v ? r : v;
    if (wireEpoch > local) {
      final prev = _resyncRequestedAtEpoch[c.channelIdHex] ?? 0;
      if (wireEpoch > prev) {
        _resyncRequestedAtEpoch[c.channelIdHex] = wireEpoch;
        _sendChannelResyncRequest(c, localEpoch: r);
      }
      return false;
    }
    _log.warn('GM-4: CHANNEL SPLIT-VIEW in "${c.name}" (role state) — '
        'local role epoch=$r, short list epoch=$v, wire epoch=$wireEpoch '
        'from ${senderHex.substring(0, 8)}');
    return true;
  }

  /// [m] for a list that goes to owner and admins: with the capabilities and
  /// the short-list epoch of the member.
  proto.GroupMember _channelMemberWireAll(ChannelMemberInfo m,
      {required bool full}) {
    final w = _channelMemberWire(m, full: full);
    final caps = m.nodeIdHex == identity.userIdHex
        ? kChannelCapListAsChanges
        : m.capabilities;
    if (caps != 0) w.capabilities = caps;
    if (m.viewEpoch != 0) w.viewEpoch = Int64(m.viewEpoch);
    return w;
  }

  /// The short list for subscriber [toHex] (§16.2.2): owner, admins and
  /// itself, at the subscriber's [ChannelMemberInfo.viewEpoch], signed;
  /// full entries for [fullFor]; `s_AB` of [toHex] with every member of
  /// [seedWith] (§4.3).
  Uint8List _channelShortInviteBytes(ChannelInfo c, String toHex,
      {Set<String> fullFor = const {},
      Set<String> seedWith = const {},
      Map<String, Uint8List>? seeds}) {
    final x = c.members[toHex]!;
    final view = _channelViewOf(c, toHex);
    final invite = proto.ChannelInvite()
      ..channelId = hexToBytes(c.channelIdHex)
      ..channelName = c.name
      ..inviterId = identity.nodeId
      ..isPublic = false
      ..isAdult = c.isAdult
      ..language = c.language
      ..roleView = true
      ..roleEpoch = Int64(_channelRoleEpoch(c))
      ..membersEpoch = Int64(c.membershipEpoch);
    if (c.description != null) invite.channelDescription = c.description!;
    // §16.2.2: the image travels with the invitation (S407 group profile).
    final picture = channelReceiveAs423 ? null : _pictureBytes(c.pictureBase64);
    if (picture != null) invite.channelPicture = picture;
    for (final m in view.values) {
      invite.members
          .add(_channelMemberWire(m, full: fullFor.contains(m.nodeIdHex)));
    }
    if (seeds != null) {
      for (final y in seedWith) {
        if (y == toHex || y == identity.userIdHex || !view.containsKey(y)) {
          continue;
        }
        invite.pairSeeds.add(proto.GroupPairSeed()
          ..memberId = hexToBytes(y)
          ..seed = _groupSeedFor(seeds, toHex, y));
      }
    }
    invite.membershipEpoch = Int64(x.viewEpoch);
    final hash =
        _computeChannelMembershipHash(x.viewEpoch, c.channelIdHex, view);
    invite.membershipHash = hash;
    invite.membershipSigEd25519 =
        SodiumFFI().signEd25519(hash, identity.ed25519SecretKey);
    invite.membershipSigMlDsa =
        OqsFFI().mlDsaSign(hash, identity.mlDsaSecretKey);
    return Uint8List.fromList(invite.writeToBuffer());
  }

  /// A change for [toHex] (§16.2.2): [upserted] (full entries for
  /// [fullFor]), [removed], `s_AB` of [toHex] with [seedWith], and the hash
  /// of the state [toHex] holds after it.
  Uint8List _channelChangeBytes(ChannelInfo c, String toHex,
      {Iterable<ChannelMemberInfo> upserted = const [],
      Set<String> fullFor = const {},
      Iterable<String> removed = const [],
      Set<String> seedWith = const {},
      Map<String, Uint8List>? seeds}) {
    final toRole = _channelIsRole(c.members[toHex]);
    final r = _channelRoleEpoch(c);
    final ch = proto.ChannelMembersChange()
      ..channelId = hexToBytes(c.channelIdHex)
      ..membersEpoch = Int64(c.membershipEpoch)
      ..roleEpoch = Int64(r)
      ..stateHash = toRole
          ? _computeChannelMembershipHash(
              c.membershipEpoch, c.channelIdHex, c.members)
          : _channelRoleHash(r, c);
    for (final m in upserted) {
      final full = fullFor.contains(m.nodeIdHex);
      ch.upserted.add(toRole
          ? _channelMemberWireAll(m, full: full)
          : _channelMemberWire(m, full: full));
    }
    for (final id in removed) {
      ch.removed.add(hexToBytes(id));
    }
    if (seeds != null) {
      for (final y in seedWith) {
        if (y == toHex || y == identity.userIdHex) continue;
        ch.pairSeeds.add(proto.GroupPairSeed()
          ..memberId = hexToBytes(y)
          ..seed = _groupSeedFor(seeds, toHex, y));
      }
    }
    // §16.2.5 "Joining": the change to owner and admins carries the step.
    final step = toRole ? _skStep(_sk(c.channelIdHex)) : null;
    if (step != null) ch.sharedKeyStep = step;
    return Uint8List.fromList(ch.writeToBuffer());
  }

  /// Every leg at once (§16.2 "Fan-out does not serialize"); a leg that
  /// was not taken over at all is failed (§22.5.1).
  Future<void> _channelLegsSend(ChannelInfo c, List<_ChannelLeg> legs) async {
    if (legs.isEmpty) return;
    final cid = hexToBytes(c.channelIdHex);
    // The changes of one channel are handed over one after the other (the
    // rule of [CleonaService._broadcastChannelUpdate], S406); the legs of
    // one change at once.
    final before = _groupUpdateSending[c.channelIdHex];
    final turn = Completer<void>();
    _groupUpdateSending[c.channelIdHex] = turn.future;
    final List<bool> results;
    try {
      if (before != null) await before;
      results = await Future.wait([
      for (final (to, kind, bytes) in legs)
        () {
          _channelListBytesNote(to, bytes.length);
          return sendToUser(
              recipientUserId: hexToBytes(to),
              messageType: kind,
              payload: bytes,
              groupId: cid);
        }(),
      ]);
    } finally {
      turn.complete();
      if (identical(_groupUpdateSending[c.channelIdHex], turn.future)) {
        _groupUpdateSending.remove(c.channelIdHex);
      }
    }
    // A leg not taken over never will be (§22.5.1) — failed; nothing here
    // sends it again (S408-LEBENSLAUF P19, §9.3, D-47).
    for (var i = 0; i < legs.length; i++) {
      if (results[i]) continue;
      _log.debug('Channel list: ${legs[i].$1.substring(0, 8)} not taken over '
          '— failed');
    }
  }

  /// Test hook: payload bytes of membership legs per recipient.
  void _channelListBytesNote(String to, int n) {
    final sink = channelListBytes;
    if (sink == null) return;
    sink[to] = (sink[to] ?? 0) + n;
  }

  /// The state [toHex] should hold of [c], for a resend or a resync: the
  /// short list for a subscriber that holds it, the complete list (every
  /// entry full) for everyone else.
  Uint8List _channelStateBytesFor(ChannelInfo c, String toHex) {
    final x = c.members[toHex];
    if (x != null &&
        !_channelIsRole(x) &&
        x.viewEpoch != 0 &&
        _channelShortList(c)) {
      return _channelShortInviteBytes(c, toHex);
    }
    return _buildSignedChannelInviteBytes(c,
        recipientHex: toHex, newMembers: {toHex});
  }

  /// A change of the role state (§16.2.2: "a change of role to every
  /// member") at the membership epoch [c] holds now: the role epoch and
  /// every subscriber's short list move to it. Returns the subscribers
  /// that held the short list before.
  Set<String> _channelRoleStateMoved(ChannelInfo c) {
    c.roleEpoch = c.membershipEpoch;
    final held = <String>{};
    for (final m in c.members.values) {
      if (_channelIsRole(m)) continue;
      if (m.viewEpoch != 0) held.add(m.nodeIdHex);
      m.viewEpoch = c.membershipEpoch;
    }
    return held;
  }

  /// The legs of a role-state change to the subscribers of [c] (all but
  /// [except]): [change] where the subscriber showed the capability and
  /// held the short list before ([heldShort]), the short list again
  /// otherwise. [newcomer] is a member new to the subscribers (full entry
  /// and `s_AB`).
  List<_ChannelLeg> _channelRoleLegsToSubscribers(ChannelInfo c,
      {required Set<String> heldShort,
      required Uint8List Function(ChannelMemberInfo s, Set<String> fresh)
          change,
      required proto.MessageType changeKind,
      String? newcomer,
      Set<String> except = const {},
      required Map<String, Uint8List> seeds}) {
    final legs = <_ChannelLeg>[];
    final fresh = {?newcomer};
    for (final s in c.members.values.toList()) {
      if (_channelIsRole(s) ||
          s.nodeIdHex == identity.userIdHex ||
          except.contains(s.nodeIdHex)) {
        continue;
      }
      if (_channelShows(s) && heldShort.contains(s.nodeIdHex)) {
        legs.add((s.nodeIdHex, changeKind, change(s, fresh)));
        continue;
      }
      s.viewEpoch = c.membershipEpoch;
      legs.add((
        s.nodeIdHex,
        proto.MessageType.MT_CHANNEL_INVITE,
        _channelShortInviteBytes(c, s.nodeIdHex,
            fullFor: fresh, seedWith: fresh, seeds: seeds),
      ));
    }
    return legs;
  }

  /// The legs of a change to the other owner/admins of [c].
  List<_ChannelLeg> _channelLegsToRoles(ChannelInfo c,
      {Iterable<ChannelMemberInfo> upserted = const [],
      Set<String> fullFor = const {},
      Iterable<String> removed = const [],
      Set<String> seedWith = const {},
      Set<String> except = const {},
      Map<String, Uint8List>? seeds}) {
    return [
      for (final y in _channelRoleState(c).values)
        if (y.nodeIdHex != identity.userIdHex && !except.contains(y.nodeIdHex))
          (
            y.nodeIdHex,
            proto.MessageType.MT_CHANNEL_MEMBERS_CHANGE,
            _channelChangeBytes(c, y.nodeIdHex,
                upserted: upserted,
                fullFor: fullFor,
                removed: removed,
                seedWith: seedWith,
                seeds: seeds),
          ),
    ];
  }

  /// The own entry of [c] signed, where it is not yet.
  void _channelOwnEntryEnsure(ChannelInfo c) {
    final me = c.members[identity.userIdHex];
    if (me != null && !me.hasSignedEntry && _channelOwnEntrySign(c)) {
      _saveChannels();
    }
  }

  // ── Recording a change (owner or admin) ──────────────────────────────

  /// A new channel: every subscriber gets the short list — the owner and
  /// itself (§16.2.2). One leg each, at once.
  Future<void> _channelShortCreate(ChannelInfo c) async {
    _channelOwnEntryEnsure(c);
    final legs = <_ChannelLeg>[];
    for (final s in c.members.values.toList()) {
      if (s.nodeIdHex == identity.userIdHex) continue;
      s.viewEpoch = c.membershipEpoch;
      legs.add((
        s.nodeIdHex,
        proto.MessageType.MT_CHANNEL_INVITE,
        _channelShortInviteBytes(c, s.nodeIdHex,
            fullFor: {identity.userIdHex}),
      ));
    }
    _saveChannels();
    await _channelLegsSend(c, legs);
    _log.info('Channel "${c.name}" to ${legs.length} subscribers — each the '
        'short list (§16.2.2)');
    _sendTwinChannelJoined(c);
  }

  /// [xHex] was invited as a subscriber (membership epoch already
  /// advanced): it gets the short list with the owner's and the admins'
  /// entries and its `s_AB` with each of them; the other owner/admins get
  /// the change with the same `s_AB`. Nobody else hears of it.
  Future<void> _channelShortInvite(ChannelInfo c, String xHex) async {
    _channelOwnEntryEnsure(c);
    final x = c.members[xHex]!..viewEpoch = c.membershipEpoch;
    _saveChannels();
    final seeds = <String, Uint8List>{};
    final roles = _channelRoleState(c).keys.toSet();
    final legs = <_ChannelLeg>[
      (
        xHex,
        proto.MessageType.MT_CHANNEL_INVITE,
        _channelShortInviteBytes(c, xHex,
            fullFor: roles, seedWith: roles, seeds: seeds),
      ),
      ..._channelLegsToRoles(c,
          upserted: [x], seedWith: {xHex}, seeds: seeds, except: {xHex}),
    ];
    await _channelLegsSend(c, legs);
    _log.info('Channel "${c.name}": ${xHex.substring(0, 8)} invited — '
        '${legs.length} legs (§16.2.2)');
    _sendTwinChannelJoined(c);
  }

  /// The signed entry of [x] arrived with its acceptance (membership epoch
  /// already advanced): it goes to the other owner/admins only.
  Future<void> _channelShortJoined(ChannelInfo c, ChannelMemberInfo x) async {
    final legs = _channelLegsToRoles(c,
        upserted: [x], fullFor: {x.nodeIdHex}, except: {x.nodeIdHex});
    await _channelLegsSend(c, legs);
    _sendTwinChannelJoined(c);
  }

  /// [x] was removed (already out of [c], membership epoch advanced): the
  /// other owner/admins get the change, [x] the notice of its own removal
  /// where it showed the capability; an owner or admin removed is a change
  /// of the role state, which every subscriber gets.
  Future<void> _channelShortRemove(ChannelInfo c, ChannelMemberInfo x) async {
    final xHex = x.nodeIdHex;
    final wasRole = _channelIsRole(x);
    final held = wasRole ? _channelRoleStateMoved(c) : const <String>{};
    _saveChannels();
    final seeds = <String, Uint8List>{};
    final legs = <_ChannelLeg>[
      ..._channelLegsToRoles(c, removed: [xHex]),
      if (_channelShows(x))
        (
          xHex,
          proto.MessageType.MT_CHANNEL_MEMBERS_CHANGE,
          _channelChangeBytes(c, xHex, removed: [xHex]),
        ),
      if (wasRole)
        ..._channelRoleLegsToSubscribers(c,
            heldShort: held,
            changeKind: proto.MessageType.MT_CHANNEL_MEMBERS_CHANGE,
            change: (s, _) =>
                _channelChangeBytes(c, s.nodeIdHex, removed: [xHex]),
            seeds: seeds),
    ];
    // The notice travels over the pair with [x]; it ends after it.
    await _channelLegsSend(c, legs);
    _channelPairsSync(c);
    _sendTwinChannelJoined(c);
  }

  /// The owner changed the role of [x] from [oldRole] (membership epoch
  /// advanced, roles applied): a change of the role state to every member.
  /// A subscriber made owner or admin gets the complete list with its
  /// `s_AB` with everyone; an owner or admin made subscriber gets the short
  /// list.
  Future<void> _channelShortRole(
      ChannelInfo c, ChannelMemberInfo x, String oldRole) async {
    final xHex = x.nodeIdHex;
    final wasRole = oldRole == 'owner' || oldRole == 'admin';
    final isRole = _channelIsRole(x);
    final me = c.members[identity.userIdHex];
    final transfer = x.role == 'owner';
    final held = _channelRoleStateMoved(c);
    final seeds = <String, Uint8List>{};
    final upserted = [x, if (transfer && me != null) me];
    final legs = <_ChannelLeg>[];
    if (isRole && !wasRole) {
      x.viewEpoch = 0;
      legs.add((
        xHex,
        proto.MessageType.MT_CHANNEL_INVITE,
        _buildSignedChannelInviteBytes(c,
            recipientHex: xHex, newMembers: {xHex}, seeds: seeds),
      ));
    } else if (!isRole && wasRole) {
      legs.add((
        xHex,
        proto.MessageType.MT_CHANNEL_INVITE,
        _channelShortInviteBytes(c, xHex),
      ));
    }
    legs.addAll(_channelLegsToRoles(c,
        upserted: upserted, except: {if (!wasRole || !isRole) xHex}));
    final newcomer = isRole && !wasRole ? xHex : null;
    legs.addAll(_channelRoleLegsToSubscribers(c,
        heldShort: held,
        except: {xHex},
        newcomer: newcomer,
        changeKind: proto.MessageType.MT_CHANNEL_MEMBERS_CHANGE,
        change: (s, fresh) => _channelChangeBytes(c, s.nodeIdHex,
            upserted: upserted, fullFor: fresh, seedWith: fresh, seeds: seeds),
        seeds: seeds));
    _saveChannels();
    await _channelLegsSend(c, legs);
    _channelPairsSync(c);
  }

  /// This device, owner or admin of [c], leaves (§16.2.2). A change of the
  /// role state to every member; an owner passes its role first — to the
  /// first admin, else the first member — and names the new owner in the
  /// leaving itself, so that no subscriber has to pick one from a list it
  /// does not hold. Returns the new owner, if any.
  Future<String?> _channelShortLeave(ChannelInfo c) async {
    final meHex = identity.userIdHex;
    ChannelMemberInfo? n;
    var nWasRole = false;
    if (c.ownerNodeIdHex == meHex && c.members.length > 1) {
      final others = c.members.values.where((m) => m.nodeIdHex != meHex);
      n = others.where((m) => m.role == 'admin').firstOrNull ?? others.first;
      nWasRole = _channelIsRole(n);
      n.role = 'owner';
      c.ownerNodeIdHex = n.nodeIdHex;
      // §16.2.4: the reactions go with the role, before the conversation.
      _channelReactionHandoverSend(c, n.nodeIdHex, keepConversation: false);
    }
    c.members.remove(meHex);
    c.membershipEpoch++;
    final held = _channelRoleStateMoved(c);
    final seeds = <String, Uint8List>{};
    Uint8List leave(String toHex, {bool full = false}) {
      final l = proto.ChannelLeave()
        ..channelId = hexToBytes(c.channelIdHex)
        ..roleEpoch = Int64(c.roleEpoch)
        ..membersEpoch = Int64(c.membershipEpoch);
      if (n != null) {
        l.newOwner = _channelIsRole(c.members[toHex])
            ? _channelMemberWireAll(n, full: full)
            : _channelMemberWire(n, full: full);
        if (full) {
          l.pairSeed = proto.GroupPairSeed()
            ..memberId = hexToBytes(n.nodeIdHex)
            ..seed = _groupSeedFor(seeds, toHex, n.nodeIdHex);
        }
      }
      return Uint8List.fromList(l.writeToBuffer());
    }

    final legs = <_ChannelLeg>[];
    final nHex = n?.nodeIdHex;
    if (n != null && !nWasRole) {
      n.viewEpoch = 0;
      legs.add((
        n.nodeIdHex,
        proto.MessageType.MT_CHANNEL_INVITE,
        _buildSignedChannelInviteBytes(c,
            recipientHex: n.nodeIdHex, newMembers: {n.nodeIdHex}, seeds: seeds),
      ));
    }
    for (final y in _channelRoleState(c).values) {
      if (n != null && !nWasRole && y.nodeIdHex == nHex) continue;
      legs.add((
        y.nodeIdHex,
        proto.MessageType.MT_CHANNEL_LEAVE,
        leave(y.nodeIdHex),
      ));
    }
    legs.addAll(_channelRoleLegsToSubscribers(c,
        heldShort: held,
        except: {?nHex},
        newcomer: n != null && !nWasRole ? nHex : null,
        changeKind: proto.MessageType.MT_CHANNEL_LEAVE,
        change: (s, fresh) => leave(s.nodeIdHex, full: fresh.isNotEmpty),
        seeds: seeds));
    await _channelLegsSend(c, legs);
    _log.info('Left channel "${c.name}" as owner/admin — ${legs.length} legs, '
        'new owner ${nHex?.substring(0, 8) ?? '-'} (§16.2.2)');
    return nHex;
  }

  // ── Receiving ─────────────────────────────────────────────────────────

  /// A member from the wire for [c]: kept where known (role, entry where a
  /// full one proves itself), new otherwise.
  ChannelMemberInfo? _channelMemberUpsert(
      ChannelInfo c, proto.GroupMember w) {
    final id = w.nodeId.hex;
    if (id.isEmpty) return null;
    Uint8List? opt(List<int> b) => b.isEmpty ? null : Uint8List.fromList(b);
    final m = c.members[id] ??
        ChannelMemberInfo(
          nodeIdHex: id,
          displayName: w.displayName,
          ed25519Pk: opt(w.ed25519PublicKey),
          x25519Pk: opt(w.x25519PublicKey),
          mlKemPk: opt(w.mlKemPublicKey),
        );
    if (w.displayName.isNotEmpty) m.displayName = w.displayName;
    if (w.role.isNotEmpty) m.role = w.role;
    if (w.address.isNotEmpty && !_channelEntryTake(c.channelIdHex, w, m)) {
      _log.warn('channel ${c.channelIdHex.substring(0, 8)}: the entry of '
          '${id.substring(0, 8)} does not prove itself — kept without it');
    }
    if (w.hasCapabilities()) m.capabilities = w.capabilities;
    if (w.hasViewEpoch()) m.viewEpoch = w.viewEpoch.toInt();
    c.members[id] = m;
    return m;
  }

  /// MT_CHANNEL_MEMBERS_CHANGE (§16.2.2): a membership change as a change,
  /// from the owner or an admin of the OLD state (authority gate; the
  /// sender of a leg is fixed by the pairwise seal).
  void _channelMembersChangeReceived(HarvestEvent event) {
    final senderHex = event.senderUserId.hex;
    final proto.ChannelMembersChange ch;
    try {
      ch = proto.ChannelMembersChange.fromBuffer(event.payload);
    } catch (e) {
      _log.warn('CHANNEL_MEMBERS_CHANGE parse failed: $e');
      return;
    }
    final cid = ch.channelId.hex;
    final c = _channels[cid];
    if (c == null) return;
    if (!_channelIsRole(c.members[senderHex])) {
      _log.warn('CHANNEL_MEMBERS_CHANGE from ${senderHex.substring(0, 8)}, '
          'no owner/admin of "${c.name}" — discarded');
      return;
    }
    final meHex = identity.userIdHex;
    if (ch.hasSharedKeyStep()) _skStepHeard(cid, ch.sharedKeyStep);
    // §16.2.5: a change can name a new admin, who is owed the notice — asked
    // once the change below is applied.
    unawaited(Future(_capabilityNoticesDue));
    if (ch.removed.any((r) => r.hex == meHex)) {
      _channelRemovedFrom(c, senderHex);
      return;
    }
    final members = ch.membersEpoch.toInt();
    final role = ch.roleEpoch.toInt();
    final iAmRole = _channelIsRole(c.members[meHex]);
    final late = iAmRole ? members <= c.membershipEpoch : role <= c.roleEpoch;
    if (late) {
      // §16.2.2: a late change decides nothing; a self-signed entry it
      // carries for a member held without one is taken.
      var taken = 0;
      for (final w in ch.upserted) {
        final held = c.members[w.nodeId.hex];
        if (w.address.isEmpty || held == null || held.hasSignedEntry) continue;
        if (_channelEntryTake(cid, w, held)) taken++;
      }
      if (taken > 0) {
        _saveChannels();
        _channelPairsSync(c);
      }
      _log.info('CHANNEL_MEMBERS_CHANGE at epoch $members/$role for '
          '"${c.name}" — not newer, $taken entries taken');
      return;
    }
    for (final w in ch.upserted) {
      if (w.nodeId.hex == meHex) {
        // Only the own role is taken from a change; the own entry is this
        // device's.
        final me = c.members[meHex];
        if (me != null && w.role.isNotEmpty) me.role = w.role;
        if (w.role == 'owner') c.ownerNodeIdHex = meHex;
        continue;
      }
      final m = _channelMemberUpsert(c, w);
      if (m == null) continue;
      if (m.role == 'owner') {
        c.ownerNodeIdHex = m.nodeIdHex;
      }
      // A subscriber holds the role state only (§16.2.2).
      if (c.roleView && !_channelIsRole(m)) c.members.remove(m.nodeIdHex);
    }
    for (final r in ch.removed) {
      c.members.remove(r.hex);
    }
    final roleMoved = role > c.roleEpoch;
    if (c.roleView) {
      c.roleEpoch = role;
      c.viewEpoch = members;
      c.membershipEpoch = members;
    } else {
      c.membershipEpoch = members;
      if (roleMoved) {
        c.roleEpoch = role;
        // The rule of [_channelRoleStateMoved], applied by every owner/admin
        // alike: every short list moves to the epoch of the change.
        for (final m in c.members.values) {
          if (!_channelIsRole(m)) m.viewEpoch = members;
        }
      }
    }
    final p = myceliumMailbox;
    if (p != null) {
      for (final s in ch.pairSeeds) {
        if (!c.members.containsKey(s.memberId.hex)) continue;
        p.groupPairSeed(Uint8List.fromList(ch.channelId),
            Uint8List.fromList(s.memberId), Uint8List.fromList(s.seed));
      }
    }
    _saveChannels();
    _channelPairsSync(c);
    final expect = c.roleView
        ? _channelRoleHash(c.roleEpoch, c)
        : _computeChannelMembershipHash(c.membershipEpoch, cid, c.members);
    if (ch.stateHash.isNotEmpty &&
        !constantTimeEquals(Uint8List.fromList(ch.stateHash), expect)) {
      _log.warn('CHANNEL_MEMBERS_CHANGE for "${c.name}": the state after it '
          'differs from the sender\'s — resync asked (§16.2.2)');
      _sendChannelResyncRequest(c,
          localEpoch: 0);
    }
    _log.info('CHANNEL_MEMBERS_CHANGE for "${c.name}" from '
        '${senderHex.substring(0, 8)}: +${ch.upserted.length} '
        '-${ch.removed.length}, epoch $members, role epoch $role');
    onStateChanged?.call();
  }

  /// The fields of a leaving by an owner or admin of this build
  /// (`ChannelLeave.role_epoch` > 0, §16.2.2): the new owner it names, the
  /// `s_AB` with it, the epochs. [senderHex] is already out of [c].
  void _channelLeaveApply(ChannelInfo c, proto.ChannelLeave l) {
    if (l.hasNewOwner()) {
      final n = _channelMemberUpsert(c, l.newOwner);
      if (n != null) {
        n.role = 'owner';
        c.ownerNodeIdHex = n.nodeIdHex;
        if (n.nodeIdHex == identity.userIdHex) c.roleView = false;
      }
    }
    if (l.hasPairSeed()) {
      myceliumMailbox?.groupPairSeed(Uint8List.fromList(l.channelId),
          Uint8List.fromList(l.pairSeed.memberId),
          Uint8List.fromList(l.pairSeed.seed));
    }
    final members = l.membersEpoch.toInt();
    final role = l.roleEpoch.toInt();
    if (c.roleView) {
      if (role > c.roleEpoch) c.roleEpoch = role;
      if (members > c.viewEpoch) c.viewEpoch = members;
      if (members > c.membershipEpoch) c.membershipEpoch = members;
      return;
    }
    if (members > c.membershipEpoch) c.membershipEpoch = members;
    if (role > c.roleEpoch) {
      c.roleEpoch = role;
      for (final m in c.members.values) {
        if (!_channelIsRole(m)) m.viewEpoch = members;
      }
    }
  }

  /// This device was removed from [c] by [byHex] (§16.2.2): as for a group,
  /// the conversation stays readable, marked as removed, later posts are
  /// discarded, the pairs of the channel end.
  void _channelRemovedFrom(ChannelInfo c, String byHex) {
    final cid = c.channelIdHex;
    myceliumMailbox?.groupPairLeave(hexToBytes(cid));
    _channels.remove(cid);
    _skForget(cid); // §16.2.5: no keys of the next generation
    _saveChannels();
    _groupMarkLeft(cid, c.membershipEpoch, removed: true);
    _saveConversations();
    onStateChanged?.call();
    _log.info('Removed from the channel ${cid.substring(0, 8)} by '
        '${byHex.substring(0, 8)} — the conversation stays (§16.2.2)');
  }
}
