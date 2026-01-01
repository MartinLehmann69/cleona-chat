// §16.2.5 (S407 channel step 2) — groups and channels on the shared key:
// the state per group or channel, the capability notice, the construction
// (17 members on, back at 12 or fewer) and the keepers.
//
// The key deliveries are `cleona_service_shared_key_keys.dart`, a post going
// out `cleona_service_shared_key_post.dart`, an entry coming in (nudge or
// collection) `cleona_service_shared_key_take.dart`. The transport — keeper,
// deposit, collection, nudge — is mycelium (`channel_*.dart`).
//
// One group stays one group: roles, settings and posting rights are those of
// §16.2.2 in both constructions; the construction changes only how a post
// travels (§16.2.1).

part of 'cleona_service.dart';

extension CleonaServiceSharedKey on CleonaService {
  // ── State ─────────────────────────────────────────────────────────────

  void _skLoadAll() {
    if (_sharedKeysLoaded) return;
    _sharedKeysLoaded = true;
    try {
      for (final e in store.loadArea(kSharedKeyArea).entries) {
        _sharedKeys[e.key] = SharedKeyState.fromJson(e.value);
      }
      for (final e in store.loadArea(kCapabilityArea).entries) {
        _capabilities[e.key] =
            (e.value['caps'] as int? ?? 0, e.value['class'] as int? ?? 0);
      }
    } catch (e) {
      _log.warn('shared key: state unreadable ($e) — starts empty');
    }
  }

  /// The state of [gid], or `null` when this identity holds none.
  SharedKeyState? _sk(String gid) {
    _skLoadAll();
    return _sharedKeys[gid];
  }

  SharedKeyState _skOrNew(String gid) {
    _skLoadAll();
    return _sharedKeys[gid] ??= SharedKeyState(gid: gid);
  }

  void _skSave(SharedKeyState s) {
    s.prune(_skToday());
    try {
      store.putEntry(kSharedKeyArea, s.gid, s.toJson());
    } catch (e) {
      _log.warn('shared key ${_skShort(s.gid)}: not saved ($e)');
    }
  }

  void _skForget(String gid) {
    _skLoadAll();
    _sharedKeys.remove(gid);
    try {
      store.removeEntry(kSharedKeyArea, gid);
    } catch (_) {}
  }

  int _skToday() => chain.channelDay(sharedKeyClock());

  String _skShort(String h) => h.length > 8 ? h.substring(0, 8) : h;

  /// The state of [gid] — read by probes only.
  @visibleForTesting
  SharedKeyState? debugSharedKey(String gid) => _sk(gid);

  /// Whether [gid] runs on the shared key on this device.
  bool _skOn(String gid) => !sharedKeyOff && (_sk(gid)?.on ?? false);

  // ── The group or channel, read the same way for both ──────────────────

  bool _skIsChannel(String gid) => _channels.containsKey(gid);

  /// Member → role ('owner', 'admin', 'member' or 'subscriber') as this
  /// device holds the list (a subscriber holds owner, admins and itself).
  Map<String, String> _skRoles(String gid) {
    final c = _channels[gid];
    if (c != null) return {for (final m in c.members.values) m.nodeIdHex: m.role};
    final g = _groups[gid];
    if (g != null) return {for (final m in g.members.values) m.nodeIdHex: m.role};
    return const {};
  }

  bool _skRecords(String gid) {
    final r = _skRoles(gid)[identity.userIdHex];
    return r == 'owner' || r == 'admin';
  }

  bool _skOwnerHere(String gid) => _skRoles(gid)[identity.userIdHex] == 'owner';

  /// Whether [hex] may post (§16.2.5 "Authors"): in a channel and in a group
  /// in announcement mode the owner and the admins; in a group in discussion
  /// mode every member. A member that may not post gets no certificate, and
  /// its post is refused at the check.
  bool _skMayPost(String gid, String hex) {
    final r = _skRoles(gid)[hex];
    if (r == null) return false;
    return _skIsChannel(gid)
        ? (r == 'owner' || r == 'admin')
        : _groupMayPost(gid, hex);
  }

  /// The Ed25519 identity key of member [hex], as the list carries it.
  Uint8List? _skMemberEdPk(String gid, String hex) =>
      _channels[gid]?.members[hex]?.ed25519Pk ??
      _groups[gid]?.members[hex]?.ed25519Pk ??
      _contacts[hex]?.ed25519Pk;

  // ── Capabilities (§16.2.5 "Mixed operation within 4.2") ──────────────

  int get _skOwnCaps =>
      sharedKeyOff ? kCapMemberList | kCapGroupProfile : kCapsBuilt;

  int get _skOwnClass =>
      sharedKeyDeviceClass ??
      (Platform.isAndroid || Platform.isIOS ? kClassPhone : kClassDesktop);

  /// Whether [hex] has shown the capability of §16.2.5.
  bool _skCapable(String hex) {
    if (hex == identity.userIdHex) return !sharedKeyOff;
    _skLoadAll();
    return (_capabilities[hex]?.$1 ?? 0) & kCapSharedKey != 0;
  }

  /// `MT_CAPABILITY_NOTICE`.
  void _capabilityNoticeReceived(HarvestEvent event) {
    if (sharedKeyOff) return; // a version without §16.2.5 does not read it
    final from = event.senderUserId.hex;
    final proto.CapabilityNotice n;
    try {
      n = proto.CapabilityNotice.fromBuffer(event.payload);
    } catch (e) {
      _log.warn('capability notice from ${_skShort(from)}: unreadable — dropped');
      return;
    }
    _skLoadAll();
    _capabilities[from] = (n.capabilities, n.deviceClass);
    try {
      store.putEntry(kCapabilityArea, from,
          {'caps': n.capabilities, 'class': n.deviceClass});
    } catch (_) {}
    // Channel step 1 kept the bit per channel member; it goes up here.
    for (final c in _channels.values) {
      final m = c.members[from];
      if (m != null && m.capabilities != n.capabilities) {
        m.capabilities = n.capabilities;
      }
    }
    _saveChannels();
    _log.info('capability notice from ${_skShort(from)}: '
        'bits ${n.capabilities}, class ${n.deviceClass}');
    // §16.2.2 (S407 group profile): a change of the profile made here that
    // did not reach it reaches it now.
    _profileOwedNotice(from);
    // A member that can now be served on the shared key gets its keys; the
    // owner's keeper list takes a desktop it did not know of yet (the next
    // post or key delivery carries the list).
    for (final s in _sharedKeys.values.toList()) {
      if (!s.on || !_skRoles(s.gid).containsKey(from)) continue;
      if (_skOwnerHere(s.gid) && s.keepers.length < kKeepersAtMost) {
        final list = _skKeeperList(s.gid);
        if (list.length > s.keepers.length) {
          s
            ..keepers = list
            ..keepersVersion = s.keepersVersion + 1;
          _skSave(s);
        }
      }
      if (_skRecords(s.gid)) unawaited(_skAdmit(s.gid, from));
    }
  }

  /// Sends the notice where it is owed (§16.2.5): to each owner and admin of
  /// every group and channel this identity belongs to, and to every contact
  /// whose fixed neighbour this node is — once per recipient and value
  /// (store area [kCapabilitySentArea]). Called at the attach, after an own
  /// acceptance and after a role change; costs nothing when all is sent.
  Future<void> _capabilityNoticesDue() async {
    final p = myceliumMailbox;
    // A version that does not build the notice sends none (probe stand-ins).
    if (p == null || channelReceiveAs423 || sharedKeyOff) return;
    final value = '$_skOwnCaps/$_skOwnClass';
    Map<String, Map<String, dynamic>> sent;
    try {
      sent = store.loadArea(kCapabilitySentArea);
    } catch (_) {
      sent = {};
    }
    final due = <String, String?>{}; // recipient → a group both belong to
    void owe(String gid) {
      _skRoles(gid).forEach((hex, role) {
        if (hex != identity.userIdHex &&
            (role == 'owner' || role == 'admin') &&
            sent[hex]?['v'] != value) {
          due.putIfAbsent(hex, () => gid);
        }
      });
    }

    for (final g in _groups.values) {
      if (g.joined) owe(g.groupIdHex);
    }
    for (final c in _channels.values) {
      if (!c.isPublic) owe(c.channelIdHex);
    }
    for (final hex in p.servedContacts()) {
      if (sent[hex]?['v'] != value && _contacts[hex]?.status == 'accepted') {
        due[hex] = null;
      }
    }
    if (due.isEmpty) return;
    final payload = Uint8List.fromList((proto.CapabilityNotice()
          ..capabilities = _skOwnCaps
          ..deviceClass = _skOwnClass)
        .writeToBuffer());
    await Future.wait([
      for (final e in due.entries)
        sendToUser(
          recipientUserId: hexToBytes(e.key),
          messageType: proto.MessageType.MT_CAPABILITY_NOTICE,
          payload: payload,
          groupId: e.value == null ? null : hexToBytes(e.value!),
        ).then((ok) {
          if (!ok) return;
          try {
            store.putEntry(kCapabilitySentArea, e.key, {'v': value});
          } catch (_) {}
        }),
    ]);
    _log.info('capability notice to ${due.length} owner(s), admin(s) or '
        'served contact(s): bits $_skOwnCaps, class $_skOwnClass');
  }

  // ── The construction (§16.2.1) ────────────────────────────────────────

  /// The owner checks the size after every membership change: to the shared
  /// key at 17 members, back to pairwise legs at 12 or fewer; none at
  /// 13–16. Only the owner switches.
  Future<void> _skSizeCheck(String gid) async {
    if (sharedKeyOff || !_skOwnerHere(gid)) return;
    final c = _channels[gid];
    if (c != null && c.isPublic) return;
    final n = _skRoles(gid).length;
    final s = _sk(gid);
    final on = s?.on ?? false;
    if (!on && n >= kSharedKeyFrom) {
      _log.info('shared key ${_skShort(gid)}: $n members — to the shared key');
      await _skNewGeneration(gid);
    } else if (on && n <= kPairwiseAtMost) {
      _log.info('shared key ${_skShort(gid)}: $n members — back to pairwise legs');
      await _skReturnPairwise(gid);
    }
  }

  /// A leaving or removal was recorded here (§16.2.5 "Leaving and
  /// removal"): the owner — or the admin who removed — draws the next
  /// generation for every remaining member. Then the size is checked.
  Future<void> _skDeparted(String gid, {bool removedHere = false}) async {
    if (sharedKeyOff) return;
    // A leaving can pass the ownership on: the new owner is owed the notice.
    unawaited(_capabilityNoticesDue());
    final s = _sk(gid);
    if (s != null && s.on && (_skOwnerHere(gid) || (removedHere && _skRecords(gid)))) {
      s.served.removeWhere((h) => !_skRoles(gid).containsKey(h));
      await _skNewGeneration(gid);
    }
    await _skSizeCheck(gid);
  }

  /// The keeper list (§16.2.5 "Keepers"), drawn by the owner: desktops of the
  /// owner and the admins, then desktops of the other members, then the
  /// owner's fixed neighbours — each one that showed the capability, at an
  /// address this device holds; up to five, without [without].
  List<Uint8List> _skKeeperList(String gid, {Set<String> without = const {}}) {
    final p = myceliumMailbox;
    if (p == null) return const [];
    final out = <CardAddress>[];
    void add(CardAddress? a) {
      if (a == null || out.length >= kKeepersAtMost) return;
      if (without.contains(_skPack(a).join(','))) return;
      if (out.any((x) => x.equal(a))) return;
      out.add(a);
    }

    bool desktop(String hex) =>
        _skCapable(hex) && (_capabilities[hex]?.$2 ?? 0) == kClassDesktop;
    final roles = _skRoles(gid);
    final node = p.host.node;
    // The own desktop first, when it keeps (evidenced reachability).
    if (_skOwnClass == kClassDesktop && HostChannel.of(node).keeps()) {
      add(node.publicAddress);
    }
    for (final pass in [true, false]) {
      roles.forEach((hex, role) {
        final lead = role == 'owner' || role == 'admin';
        if (hex == identity.userIdHex || lead != pass || !desktop(hex)) return;
        add(p.contactOrNull(hex)?.lastSeen);
      });
    }
    for (final n in node.neighbourhood.fixedNeighbours) {
      for (final k in p.contacts) {
        final hex = mycelium.identifierFrom(k.address);
        if (desktop(hex) && deviceOfContact(k, n)) add(n.asCardAddress);
      }
    }
    return [for (final a in out) _skPack(a)];
  }

  Uint8List _skPack(CardAddress a) =>
      Uint8List.fromList([a.kind.index, ...a.address, a.port >> 8, a.port & 0xFF]);

  CardAddress? _skUnpack(Uint8List b) {
    try {
      final len = b.length - 3;
      if (len != 4 && len != 16) return null;
      return CardAddress(Uint8List.sublistView(b, 1, 1 + len),
          (b[1 + len] << 8) | b[2 + len]);
    } catch (_) {
      return null;
    }
  }

  List<CardAddress> _skKeepers(SharedKeyState s) =>
      [for (final k in s.keepers) ?_skUnpack(k)];

  /// The members this device serves on the shared key: those that showed
  /// the capability (owner and admins know it from the notices, every other
  /// member from the last key delivery).
  Set<String> _skServed(SharedKeyState s) {
    final roles = _skRoles(s.gid);
    return {
      for (final hex in roles.keys)
        if (hex != identity.userIdHex &&
            (s.served.contains(hex) || (_skRecords(s.gid) && _skCapable(hex))))
          hex,
    };
  }

  // ── Own other devices (§14.7 Type 6 / Type 22) ───────────────────────

  /// The key state a twin record carries — without `r_g`, which never
  /// leaves the device that drew it (§16.2.5). `null`: none held.
  Map<String, dynamic>? _skTwinState(String gid) {
    final s = _sk(gid);
    if (s == null || s.generations.isEmpty) return null;
    final j = s.toJson();
    for (final g in (j['gens'] as Map).values) {
      (g as Map).remove('r');
    }
    // What this device collected or refused is its own; the twin collects.
    j
      ..remove('held')
      ..remove('vday')
      ..remove('closed')
      ..remove('objects');
    return j;
  }

  /// The key state changed here: the own other devices get it with the
  /// record of the group or channel (§16.2.5 "Catching up and restoring").
  void _skTwinSend(String gid) {
    final g = _groups[gid];
    if (g != null && g.joined) _sendTwinGroupCreated(g);
    final c = _channels[gid];
    if (c != null) _sendTwinChannelJoined(c);
  }

  /// Takes the key state of another own device: generations this device
  /// does not hold, the keys of days it lacks, the construction, the newest
  /// keeper list.
  void _skTwinTake(String gid, Object? json) {
    if (json is! Map || sharedKeyOff) return;
    final SharedKeyState other;
    try {
      other = SharedKeyState.fromJson(Map<String, dynamic>.from(json));
    } catch (e) {
      _log.warn('shared key twin state for ${_skShort(gid)} unreadable ($e)');
      return;
    }
    final s = _skOrNew(gid);
    for (final g in other.generations.values) {
      final mine = s.generations[g.key];
      if (mine == null) {
        s.adopt(g);
        continue;
      }
      g.dayKeys.forEach((d, k) => mine.dayKeys.putIfAbsent(d, () => k));
      g.stepFloor.forEach((d, f) => mine.stepFloor.putIfAbsent(d, () => f));
      mine.generationSeed ??= g.generationSeed;
      if (mine.certificate == null && g.certificate != null) {
        mine
          ..authorPk = g.authorPk
          ..authorSk = g.authorSk
          ..certificate = g.certificate;
      }
      mine.seen(g.day, g.step);
    }
    if (other.keepersVersion >= s.keepersVersion && other.keepers.isNotEmpty) {
      s
        ..keepers = other.keepers
        ..keepersVersion = other.keepersVersion;
    }
    s
      ..on = other.on
      ..served = {...s.served, ...other.served}
      ..authorKeys.addAll(other.authorKeys);
    _skSave(s);
  }

  /// "Always load images" (§9.4) of a group or channel — on by default; the
  /// setting lives with the group or channel (`setAlwaysLoadImages`).
  bool _skLoadImages(String gid) =>
      _groups[gid]?.alwaysLoadImages ?? _channels[gid]?.alwaysLoadImages ?? true;
}
