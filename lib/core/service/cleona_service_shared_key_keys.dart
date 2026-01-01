// §16.2.5 (S407 channel step 2) — the keys of a group or channel on the
// shared key, each in an ordinary 1:1 delivery over a pairwise leg (§4.3):
//
// * a new generation (the switch at 17, a leaving, a removal, a transfer of
//   ownership): the day key, A_g, the generation public key, to owner and
//   admins W_g, the keeper list and, to every author, a certificate for its
//   next author key — one delivery per remaining member; the departed member
//   receives none;
// * a joining: the step advanced by one, S_g(d, j) and D_g(d+1) — one
//   delivery; the membership update to owner and admins carries the new j;
// * the return to pairwise legs at 12 members or fewer;
// * an author that holds no certificate for the generation in force names
//   its author key, and owner or admin certify it.
//
// The daily change costs no packet: every device derives the next day key.

part of 'cleona_service.dart';

extension CleonaServiceSharedKeyKeys on CleonaService {
  int _skEpoch(String gid) =>
      _channels[gid]?.membershipEpoch ?? _groups[gid]?.membershipEpoch ?? 0;

  /// Draws the next generation here (owner, or the admin who recorded the
  /// change) and gives it to every member served on the shared key.
  Future<void> _skNewGeneration(String gid) async {
    final s = _skOrNew(gid);
    final today = _skToday();
    final g = chain.newGeneration();
    final w = chain.generationKey(g.root);
    final gen = SharedGeneration(
      number: (s.current?.number ?? 0) + 1,
      id: g.id,
      root: g.root,
      keeperKey: chain.keeperKey(g.root),
      generationPk: chain.generationPair(w).publicKey,
      generationSeed: w,
      dayKeys: {today: chain.dayKeyFirst(g.root)},
      day: today,
    );
    _skSelfCertify(s, gen);
    // Served: who showed the capability here, and who was served before — a
    // new owner after a transfer knows the capabilities from the previous
    // owner's deliveries before the members' notices reach it.
    final roles = _skRoles(gid);
    final keepers = _skKeeperList(gid);
    for (final k in s.keepers) {
      if (keepers.length >= kKeepersAtMost) break;
      if (!keepers.any((x) => x.join(',') == k.join(','))) keepers.add(k);
    }
    s
      ..adopt(gen)
      ..on = true
      ..keepers = keepers
      ..keepersVersion = s.keepersVersion + 1
      ..served = {
        for (final hex in roles.keys)
          if (hex != identity.userIdHex &&
              (_skCapable(hex) || s.served.contains(hex)))
            hex
      };
    _skSave(s);
    _log.info('shared key ${_skShort(gid)}: generation ${gen.number} drawn — '
        '${s.served.length} member(s) served, ${s.keepers.length} keeper(s)');
    await Future.wait([for (final hex in s.served.toList()) _skGive(s, gen, hex)]);
    _skSave(s);
    _skTwinSend(gid);
  }

  /// An owner or admin that holds `W_g` certifies an own author key for it.
  void _skSelfCertify(SharedKeyState s, SharedGeneration gen) {
    final w = gen.generationSeed;
    if (w == null || gen.certificate != null || !_skMayPost(s.gid, identity.userIdHex)) {
      return;
    }
    final a = chain.newAuthorPair();
    gen
      ..authorPk = a.publicKey
      ..authorSk = a.secretKey
      ..certificate = chain.certify(
          chain.generationPair(w).secretKey, gen.number, gen.id, a.publicKey);
  }

  /// One key delivery to [hex]. [joining]: the step key of the joining and
  /// the next day key; otherwise the day key of the generation's first day.
  Future<bool> _skGive(SharedKeyState s, SharedGeneration gen, String hex,
      {bool joining = false}) {
    final role = _skRoles(s.gid)[hex];
    final d = proto.SharedKeyDelivery()
      ..groupId = hexToBytes(s.gid)
      ..generation = gen.number
      ..generationId = gen.id
      ..keeperKey = gen.keeperKey
      ..generationPk = gen.generationPk
      ..keepers.addAll(s.keepers)
      ..keepersVersion = s.keepersVersion
      ..served.addAll([for (final h in {...s.served, identity.userIdHex}) hexToBytes(h)])
      ..membershipEpoch = Int64(_skEpoch(s.gid));
    if (joining) {
      d
        ..day = gen.day
        ..step = gen.step
        ..stepKey = gen.stepKey(gen.day, gen.step)!
        ..dayKey = gen.dayKey(gen.day + 1)!;
    } else {
      final today = _skToday();
      d
        ..day = today
        ..step = 0
        ..dayKey = gen.dayKey(today)!;
    }
    final w = gen.generationSeed;
    if (w != null && (role == 'owner' || role == 'admin')) d.generationSeed = w;
    final named = s.named[hex];
    if (w != null && named != null && _skMayPost(s.gid, hex)) {
      final apk = hexToBytes(named);
      d
        ..authorPk = apk
        ..certificate = chain.certify(
            chain.generationPair(w).secretKey, gen.number, gen.id, apk);
    }
    s.given[hex] = gen.key;
    final payload = Uint8List.fromList(d.writeToBuffer());
    sharedKeyBytes?['keys'] = (sharedKeyBytes?['keys'] ?? 0) + payload.length;
    return sendToUser(
      recipientUserId: hexToBytes(hex),
      messageType: proto.MessageType.MT_SHARED_KEY,
      payload: payload,
      groupId: hexToBytes(s.gid),
    );
  }

  /// [hex] joined, or showed the capability while a member (§16.2.5
  /// "Joining"): the owner or admin who admits it advances `j` by one and
  /// gives it the keys from there on — one delivery. Returns the step the
  /// membership update reports, or `null`.
  ///
  /// A member already served on the shared key is not admitted again: it
  /// holds the generation in force, and a later step would only move its
  /// reading point past posts it has to read. This device learns who is
  /// served from its own deliveries ([SharedKeyState.given]) and from the
  /// list every key delivery carries ([SharedKeyState.served]) — an admin
  /// named after the subscribers joined gave them nothing itself. [again]:
  /// the catch-up of §16.2.5 "Catching up and restoring", which gives the
  /// keys anew as at a joining.
  Future<proto.SharedKeyStep?> _skAdmit(String gid, String hex,
      {bool again = false}) async {
    final s = _sk(gid);
    final gen = s?.current;
    if (s == null || gen == null || !s.on || sharedKeyOff) return null;
    if (!_skRecords(gid) || !_skCapable(hex) || hex == identity.userIdHex) return null;
    if (!again && (s.given[hex] == gen.key || s.served.contains(hex))) return null;
    if (!_skJoined(gid, hex)) return null;
    final today = _skToday();
    if (gen.day < today) {
      gen
        ..day = today
        ..step = 0;
    }
    if (gen.dayKey(today + 1) == null || gen.stepKey(today, gen.step + 1) == null) {
      _log.warn('shared key ${_skShort(gid)}: this device holds no key from '
          'which to admit ${_skShort(hex)} — the owner does');
      return null;
    }
    gen.step++;
    s.served.add(hex);
    _skSave(s);
    await _skGive(s, gen, hex, joining: true);
    _skSave(s);
    _log.info('shared key ${_skShort(gid)}: ${_skShort(hex)} admitted at step '
        '${gen.step} of day ${gen.day} — reads from here on');
    return _skStep(s);
  }

  /// [hex] became admin or owner: it holds `W_g` from now on (§16.2.5 —
  /// owner and admins receive it; at a transfer the previous owner hands it
  /// over). The notices owed to the new role follow.
  Future<void> _skRoleChanged(String gid, String hex) async {
    unawaited(_capabilityNoticesDue());
    final s = _sk(gid);
    final gen = s?.current;
    final role = _skRoles(gid)[hex];
    if (s == null || gen == null || !s.on || gen.generationSeed == null) return;
    if ((role != 'owner' && role != 'admin') || !_skCapable(hex)) return;
    await _skGive(s, gen, hex);
    _skSave(s);
  }

  /// §16.2.5 "Catching up and restoring": a member that was off for more
  /// than 7 days — or restored — asked as §9.5 provides; the owner gives it
  /// the current keys as at a joining.
  Future<void> _skCatchUp(String partyHex) async {
    _skLoadAll();
    for (final s in _sharedKeys.values.toList()) {
      if (!s.on || !_skOwnerHere(s.gid) || !_skRoles(s.gid).containsKey(partyHex)) {
        continue;
      }
      await _skAdmit(s.gid, partyHex, again: true);
    }
  }

  bool _skJoined(String gid, String hex) {
    final c = _channels[gid]?.members[hex];
    if (c != null) return c.hasSignedEntry;
    final g = _groups[gid]?.members[hex];
    return g != null && g.hasSignedEntry;
  }

  /// The generation and step a membership update reports (§16.2.5).
  proto.SharedKeyStep? _skStep(SharedKeyState? s) {
    final g = s?.current;
    if (s == null || g == null || !s.on) return null;
    return proto.SharedKeyStep()
      ..generation = g.number
      ..generationId = g.id
      ..day = g.day
      ..step = g.step;
  }

  /// A membership update carried the step after a joining.
  void _skStepHeard(String gid, proto.SharedKeyStep st) {
    final s = _sk(gid);
    final g = s?.byHead(st.generation, Uint8List.fromList(st.generationId));
    if (s == null || g == null) return;
    g.seen(st.day, st.step);
    _skSave(s);
  }

  /// Back to pairwise legs at 12 members or fewer (§16.2.5 "Size changes"):
  /// one delivery to every member served; the keys are deleted when their
  /// 7 days have passed.
  Future<void> _skReturnPairwise(String gid) async {
    final s = _sk(gid);
    if (s == null) return;
    final served = s.served.toList();
    s
      ..on = false
      ..served = {};
    _skSave(s);
    final payload = Uint8List.fromList((proto.SharedKeyDelivery()
          ..groupId = hexToBytes(gid)
          ..pairwise = true
          ..membershipEpoch = Int64(_skEpoch(gid)))
        .writeToBuffer());
    await Future.wait([
      for (final hex in served)
        if (_skRoles(gid).containsKey(hex))
          sendToUser(
            recipientUserId: hexToBytes(hex),
            messageType: proto.MessageType.MT_SHARED_KEY,
            payload: payload,
            groupId: hexToBytes(gid),
          ),
    ]);
  }

  /// `MT_SHARED_KEY` — from the owner or an admin only, checked against
  /// the member state this device holds (the authority gate of §16.2.2).
  void _skDeliveryReceived(HarvestEvent event) {
    if (sharedKeyOff) return;
    final from = event.senderUserId.hex;
    final proto.SharedKeyDelivery d;
    try {
      d = proto.SharedKeyDelivery.fromBuffer(event.payload);
    } catch (_) {
      _log.warn('shared key delivery from ${_skShort(from)}: unreadable');
      return;
    }
    final gid = bytesToHex(Uint8List.fromList(d.groupId));
    final role = _skRoles(gid)[from];
    if (role != 'owner' && role != 'admin') {
      _log.warn('shared key delivery for ${_skShort(gid)} from '
          '${_skShort(from)}, who is no owner or admin here — discarded');
      return;
    }
    final s = _skOrNew(gid);
    if (d.pairwise) {
      s
        ..on = false
        ..served = {};
      _skSave(s);
      _log.info('shared key ${_skShort(gid)}: back to pairwise legs');
      return;
    }
    final gid8 = Uint8List.fromList(d.generationId);
    var gen = s.byHead(d.generation, gid8);
    if (d.keeperKey.isNotEmpty) {
      gen ??= SharedGeneration(
          number: d.generation,
          id: gid8,
          keeperKey: Uint8List.fromList(d.keeperKey),
          generationPk: Uint8List.fromList(d.generationPk),
          day: d.day,
          step: d.step);
      if (d.stepKey.isNotEmpty) {
        // A joining delivery to a device that already derives this step
        // (it holds the day key, or an earlier step of the day) changes
        // nothing: a later floor would hide the steps before it, and the
        // device derives forward and never backward (§16.2.5).
        if (gen.stepKey(d.day, d.step) == null) {
          gen.stepFloor[d.day] = (d.step, Uint8List.fromList(d.stepKey));
        }
        if (gen.dayKey(d.day + 1) == null) {
          gen.dayKeys[d.day + 1] = Uint8List.fromList(d.dayKey);
        }
      } else {
        gen.dayKeys[d.day] = Uint8List.fromList(d.dayKey);
      }
      gen.seen(d.day, d.step);
      if (d.generationSeed.isNotEmpty) {
        gen.generationSeed = Uint8List.fromList(d.generationSeed);
      }
      if (d.keepersVersion >= s.keepersVersion || s.keepers.isEmpty) {
        s
          ..keepers = [for (final k in d.keepers) Uint8List.fromList(k)]
          ..keepersVersion = d.keepersVersion;
      }
      s
        ..served = {
          for (final h in d.served)
            if (bytesToHex(Uint8List.fromList(h)) != identity.userIdHex)
              bytesToHex(Uint8List.fromList(h))
        }
        ..on = true;
      s.adopt(gen);
    }
    if (gen == null) {
      _log.warn('shared key ${_skShort(gid)}: certificate for a generation '
          'this device does not hold — dropped');
      return;
    }
    _skCertificateTake(s, gen, d.authorPk, d.certificate);
    _skSelfCertify(s, gen);
    _skSave(s);
    _log.info('shared key ${_skShort(gid)}: generation ${gen.number} from '
        '${_skShort(from)} (${d.stepKey.isNotEmpty ? 'joining at step ${d.step}' : 'day ${d.day}'}'
        '${gen.certificate != null ? ', certified' : ''})');
    unawaited(_skOutResume(gid));
    _skTwinSend(gid);
    if (_skMayPost(gid, identity.userIdHex) && gen.certificate == null &&
        identical(s.current, gen)) {
      unawaited(_skAuthorAsk(gid));
    }
  }

  void _skCertificateTake(SharedKeyState s, SharedGeneration gen,
      List<int> authorPk, List<int> certificate) {
    if (authorPk.isEmpty || certificate.isEmpty) return;
    final apk = Uint8List.fromList(authorPk);
    final cert = Uint8List.fromList(certificate);
    final sk = s.authorKeys[bytesToHex(apk)];
    if (sk == null ||
        !chain.certificateHolds(gen.generationPk, gen.number, gen.id, apk, cert)) {
      return;
    }
    gen
      ..authorPk = apk
      ..authorSk = hexToBytes(sk)
      ..certificate = cert;
  }

  /// A fresh author key this device names (acceptance, a post, or a request).
  Uint8List _skNameAuthorKey(SharedKeyState s) {
    final a = chain.newAuthorPair();
    s.authorKeys[bytesToHex(a.publicKey)] = bytesToHex(a.secretKey);
    while (s.authorKeys.length > 4) {
      s.authorKeys.remove(s.authorKeys.keys.first);
    }
    return a.publicKey;
  }

  /// This author holds no certificate for the generation in force: it names
  /// a key to the owner and the admins (§16.2.5 "Authors").
  Future<void> _skAuthorAsk(String gid) async {
    final s = _sk(gid);
    final gen = s?.current;
    if (s == null || gen == null) return;
    final pk = _skNameAuthorKey(s);
    _skSave(s);
    final payload = Uint8List.fromList((proto.SharedKeyAuthor()
          ..groupId = hexToBytes(gid)
          ..generation = gen.number
          ..generationId = gen.id
          ..authorPk = pk)
        .writeToBuffer());
    final to = [
      for (final e in _skRoles(gid).entries)
        if (e.key != identity.userIdHex && (e.value == 'owner' || e.value == 'admin'))
          e.key
    ];
    await Future.wait([
      for (final hex in to)
        sendToUser(
          recipientUserId: hexToBytes(hex),
          messageType: proto.MessageType.MT_SHARED_KEY_AUTHOR,
          payload: payload,
          groupId: hexToBytes(gid),
        )
    ]);
  }

  /// `MT_SHARED_KEY_AUTHOR` at the owner or an admin: certify the key of a
  /// member that may post.
  void _skAuthorReceived(HarvestEvent event) {
    if (sharedKeyOff) return;
    final from = event.senderUserId.hex;
    final proto.SharedKeyAuthor a;
    try {
      a = proto.SharedKeyAuthor.fromBuffer(event.payload);
    } catch (_) {
      return;
    }
    final gid = bytesToHex(Uint8List.fromList(a.groupId));
    final s = _sk(gid);
    final gen = s?.byHead(a.generation, Uint8List.fromList(a.generationId));
    if (s == null || gen == null || gen.generationSeed == null ||
        !_skRecords(gid) || !_skMayPost(gid, from) || a.authorPk.length != 32) {
      return;
    }
    s.named[from] = bytesToHex(Uint8List.fromList(a.authorPk));
    final d = proto.SharedKeyDelivery()
      ..groupId = a.groupId
      ..generation = gen.number
      ..generationId = gen.id
      ..authorPk = a.authorPk
      ..certificate = chain.certify(chain.generationPair(gen.generationSeed!).secretKey,
          gen.number, gen.id, Uint8List.fromList(a.authorPk));
    _skSave(s);
    unawaited(sendToUser(
      recipientUserId: hexToBytes(from),
      messageType: proto.MessageType.MT_SHARED_KEY,
      payload: Uint8List.fromList(d.writeToBuffer()),
      groupId: hexToBytes(gid),
    ));
  }
}
