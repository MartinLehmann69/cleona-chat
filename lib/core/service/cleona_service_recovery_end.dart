// The end of a recovery (V4.2 §13.6, §13.3.4; D-102, D-103): no second,
// unpaired install from the same words runs on.
//
//   * THE NEW DEVICE completes a recovery from a bundle with an Emergency
//     Key Rotation (§4.5.4) — when the user taps "finish and renew keys"
//     ([RecoveryEndOps.enrolRecoveryFinish]), or by itself once every
//     contact restored from the bundle is back (F-1 = A). Until then the
//     interface shows how many are back and reminds at the opening of the
//     app after [kRecoveryRemindAfter]. Without a bundle the rotation took
//     place at the choice (§13.2.2, `enrolRecover`).
//   * THE PREVIOUS DEVICE reads, before it renews its bundle, the values of
//     the days since its own last placement (`BundleBox.retiredBy`). A
//     bundle whose keys continue its own along the rotation chain means: a
//     recovery retired it. It holds its post, notes the identity's name and
//     the time for the interface, and removes the identity as a deletion
//     from another own device does (§21.5.2, F-2 = B) — without noting the
//     index as deleted: the identity lives on, on the recovering device. A
//     bundle whose chain forks from its own keys is only shown. A device
//     with siblings is never retired this way (D-107): the newer keys are a
//     sibling's key change, whose key package (Type 16) it collects; without
//     one it says it was offline too long (§14.6.3) and deletes nothing.
//
// No timer, no packet of its own (rule 5): the completion happens at an
// anchoring or a tap, the check at the renewal that is due anyway.

part of 'cleona_service.dart';

/// After how long a running recovery reminds the user at the opening of the
/// app (§13.6 "a reminder after a few days"). A choice of this build: three
/// days, the renewal cadence of the bundle (§13.3.4) — by then the restored
/// contacts that write at all have usually written.
const Duration kRecoveryRemindAfter = Duration(days: 3);

/// How long after a takeover the former fixed neighbours are named among the
/// holders of the own deposits (§13.3.4 "At a rotation": 7 days — the
/// retention of a post-box entry, §8.2).
const Duration kRecoveryFormerNamedFor = kAtMostAge;

/// Per service: [RecoveryEndOps.recoveryOfflineTooLong] (memory only — after
/// a restart the next renewal finds the same and says it again).
final Expando<bool> _recoveryOfflineTooLongOf = Expando('offline-too-long');

extension RecoveryEndOps on CleonaService {
  // ── The new device: the running recovery (§13.6) ────────────────────────

  /// Called at the takeover of a bundle (`_recoveryBundleFound`): the
  /// recovery runs from now on. [restored]: the contacts restored from the
  /// bundle; [former]: the fixed neighbours the bundle named. With nothing
  /// to wait for it completes at once.
  void _recoveryOpenStart(int restored, List<BundleNeighbour> former) {
    _enrol.recoveryOpen = true;
    _enrol.recoveryTotal = restored;
    _enrol.recoveryTakenAt = recoveryBundleClock();
    _enrol.recoveryFormer = List.of(former);
    _enrolmentSave();
    _log.info('Recovery (§13.6): running — $restored restored contact(s) to '
        'come back; old devices can read along until it is completed');
    _recoveryCompleteIfAllBack();
  }

  /// How many restored contacts are back: anchored by their first envelope.
  int get _recoveryBack {
    final back = _enrol.recoveryTotal - _recoveryAnchors.length;
    return back < 0 ? 0 : back;
  }

  /// F-1 = A: once every restored contact is back, the recovery completes by
  /// itself. Called at the takeover and at every anchoring.
  void _recoveryCompleteIfAllBack() {
    if (!_enrol.recoveryOpen || _recoveryAnchors.isNotEmpty) return;
    unawaited(_recoveryComplete(byUser: false));
  }

  /// The user dismissed the notice of the identities this device removed
  /// because a recovery elsewhere retired them (§13.3.4) — marked as read
  /// in the device database, nothing sent. `false`: not writable.
  bool enrolRetiredSeen() {
    try {
      _identityMgr.retiredIdentitiesSeen();
    } on Object catch (e) {
      _log.warn('Recovery (§13.3.4): notice not marked as read — $e');
      return false;
    }
    onStateChanged?.call();
    return true;
  }

  /// The user's "finish and renew keys" (§13.6). `false`: no recovery runs,
  /// or the rotation did not take place (named in the log) — then it keeps
  /// running.
  Future<bool> enrolRecoveryFinish() => _recoveryComplete(byUser: true);

  Future<bool> _recoveryComplete({required bool byUser}) async {
    if (!_enrol.recoveryOpen) return false;
    final running = _recoveryCompleting;
    if (running != null) return running;
    final f = _recoveryCompleteRun(byUser);
    _recoveryCompleting = f;
    try {
      return await f;
    } finally {
      _recoveryCompleting = null;
    }
  }

  Future<bool> _recoveryCompleteRun(bool byUser) async {
    final back = _recoveryBack;
    final total = _enrol.recoveryTotal;
    if (!await emergencyKeyRotation()) {
      _log.warn('Recovery (§13.6): NOT completed — the Emergency Key Rotation '
          'did not take place; the recovery keeps running');
      onStateChanged?.call();
      return false;
    }
    _enrol.recoveryOpen = false;
    _enrolmentSave();
    _log.event('Recovery (§13.6): completed ${byUser ? "by the user" : "by itself, every restored contact is back"} '
        '— $back of $total contact(s) back, keys renewed; every previous '
        'device is retired');
    onStateChanged?.call();
    return true;
  }

  /// §13.3.4: the former fixed neighbours, named first at a deposit for
  /// [kRecoveryFormerNamedFor] after the takeover — decided at the deposit,
  /// no clock.
  List<CardAddress> _recoveryAlsoNamed() {
    final at = _enrol.recoveryTakenAt;
    if (at == null || _enrol.recoveryFormer.isEmpty) return const [];
    if (recoveryBundleClock().difference(at) >= kRecoveryFormerNamedFor) {
      return const [];
    }
    return [for (final n in _enrol.recoveryFormer) CardAddress(n.ip, n.port)];
  }

  /// §13.3.2, §13.3.4: copies whose chains fork were seen — kept for the
  /// interface, nothing taken or deleted.
  void _recoveryForkSeen(String where) {
    _enrol.forkSeenAt = recoveryBundleClock();
    _enrolmentSave();
    _log.warn('Rescue bundle (§13.3.2): copies whose rotation chains FORK — '
        '$where; none is taken, nothing is deleted; another install of '
        'these words runs with other keys (§4.5.4)');
    onStateChanged?.call();
  }

  // ── The previous device: retired by a recovery (§13.3.4) ────────────────

  /// The key path of this identity: founding key to current key.
  List<Uint8List> get _ownKeyPath => keyPathOf(identity.ed25519PublicKey, [
        for (final l in identity.rotationChain)
          (oldPk: l.oldEd25519Pk, newPk: l.newEd25519Pk)
      ]);

  /// What the question before a renewal found (`BundleBox.retiredBy`).
  ///
  /// A bundle of this identity that continues its keys along the rotation
  /// chain means, for a device that is the only one of its set: a recovery
  /// retired it — the identity is removed here ([_recoveryRetire], D-103).
  ///
  /// For a device whose set names other own devices it means a key change one
  /// of them made, and that device's key package (§14.7 Type 16) lies under
  /// this device's value: D-107 — a device regards itself as retired only
  /// when it is explicitly locked out, never at a key change in which it
  /// stays in the set. It is `behind`: it lays no bundle of its old keys over
  /// the newer one and deletes nothing. Still behind once its own collection
  /// round has ended ([afterRound]), it did not find its package — §14.6.3:
  /// it was off too long and must be enrolled again; the interface says so
  /// ([recoveryOfflineTooLong]), and still nothing is deleted.
  mycelium.BundleFinding _recoveryRetiredBy(
      List<Uint8List> found, bool afterRound) {
    final own = _ownKeyPath;
    final index = identity.hdIndex;
    RecoveryBundleContent? newer;
    var fork = false;
    for (final s in found) {
      final c = openRecoveryBundle(s);
      if (c == null || !c.active || c.identityIndex != index) continue;
      switch (keyPathOrder(own, bundleKeyPath(c))) {
        case KeyPathOrder.ahead:
          if (newer == null || c.depositedAtMs > newer.depositedAtMs) {
            newer = c;
          }
        case KeyPathOrder.fork:
          fork = true;
        case KeyPathOrder.same:
        case KeyPathOrder.behind:
        case KeyPathOrder.unknown:
          break;
      }
    }
    if (newer == null) {
      if (fork) _recoveryForkSeen('a bundle forks from the own keys');
      return mycelium.BundleFinding.none;
    }
    if (_devices.values.any((d) => !d.isThisDevice)) {
      if (!afterRound) {
        _log.info('Recovery (§13.3.4): a bundle of '
            '${DateTime.fromMillisecondsSinceEpoch(newer.depositedAtMs).toUtc().toIso8601String()} '
            'continues these keys (${newer.rotationChain.length} link(s)) — '
            'another own device changed them; its key package (§14.7 '
            'Type 16) comes with this edge\'s collection. Nothing is laid, '
            'nothing deleted (D-107)');
      } else if (!recoveryOfflineTooLong) {
        recoveryOfflineTooLong = true;
        _log.warn('Recovery (§14.6.3): the keys of this identity were changed '
            'on another own device and this device found no key package for '
            'it — it was offline too long and must be enrolled again. '
            'Nothing is deleted (D-107)');
        onStateChanged?.call();
      }
      return mycelium.BundleFinding.behind;
    }
    unawaited(Future(() => _recoveryRetire(newer!)));
    return mycelium.BundleFinding.retired;
  }

  /// §14.6.3 (D-107): another own device changed this identity's keys and
  /// this device found no key package for it — it was offline too long and
  /// must be enrolled again. Cleared when a key package is taken over.
  bool get recoveryOfflineTooLong => _recoveryOfflineTooLongOf[this] ?? false;
  set recoveryOfflineTooLong(bool v) => _recoveryOfflineTooLongOf[this] = v;

  /// F-2 = B: the identity is removed on this device as a deletion from
  /// another own device removes it (§21.5.2) — first the post is held, the
  /// name and time are noted (the index is not noted as deleted), then the
  /// local data is cleared and the host removes the identity.
  Future<void> _recoveryRetire(RecoveryBundleContent newer) async {
    final p = myceliumMailbox;
    if (p != null) p.node.postHold(p.identity, true);
    final at = recoveryBundleClock();
    final index = identity.hdIndex;
    _log.warn('Recovery (§13.3.4): this identity was recovered on another '
        'device (bundle of '
        '${DateTime.fromMillisecondsSinceEpoch(newer.depositedAtMs).toUtc().toIso8601String()}, '
        '${newer.rotationChain.length} link(s)) — this device is retired, '
        'the identity is removed here');
    if (index != null) {
      try {
        _identityMgr.retiredIdentityNote(index, identity.displayName, at);
      } on Object catch (e) {
        _log.warn('Recovery (§13.3.4): the note for the interface was not '
            'written ($e) — the identity is removed all the same');
      }
    }
    _wipeLocalIdentityData();
    onIdentityDeletedRemotely?.call(identity.userIdHex);
  }
}
