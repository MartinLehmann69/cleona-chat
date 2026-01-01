// V4.2 §14.4 "Device side", §14.7 Type 16 DEVICE_SET_CHANGED (S414 phase 2,
// S400 §9 E-c step 2) — placing and taking the key packages.
//
// THE ROTATING DEVICE places, BEFORE it applies the new keys, one package per
// remaining own device under that device's value in the OLD line (the own-line
// values derive from `K_own`, which follows the signing key, §14.7), sealed
// against that device's KEM keys as THIS identity's device set names them
// (§14.9.1; D-101 changes only where those keys come from). The deposits are
// awaited: a package placed after the switch would be signed with the new
// keys, and the sibling — still on the old ones — discards it
// (`_myceliumOwnInbound`).
//
// THE RECEIVING DEVICE opens the package with its own device KEM secret keys,
// checks that the chain continues ITS keys (hybrid, `RotationChain.holds`),
// takes the keys over and hands them to the running mailbox without sending
// the day keys again (the rotating device did, §8.2). It announces nothing to
// contacts: that is the rotating device's announcement (§14.4 "Contact
// side"). Devices the package does not name any more leave the set.

part of 'cleona_service.dart';

extension CleonaServiceKeyPackage on CleonaService {
  /// Places [pkg] for every other device of the set it names as remaining.
  /// Returns `(placed, missing)` — a device whose KEM keys the set does not
  /// name gets nothing and is counted as missing (named in the log).
  Future<(int, int)> _keyPackagesPlace(DeviceKeyPackage pkg) async {
    var placed = 0, missing = 0;
    for (final r in _devices.values.toList()) {
      if (r.isThisDevice || !pkg.remaining.contains(r.deviceId)) continue;
      final to = _ownLineDeviceId(r.deviceId);
      final x = r.deviceKemHex, kem = r.deviceMlKemHex;
      if (to == null || x == null || kem == null) {
        missing++;
        _log.error('Type 16: no key package for ${r.deviceId.substring(0, 8)} '
            '— the device set names no KEM keys for it (§14.9.1); it loses '
            'the identity at this rotation and must be enrolled again');
        continue;
      }
      final sealed = sealDeviceKeyPackage(pkg,
          x25519Pk: hexToBytes(x), mlKemPk: hexToBytes(kem));
      final envelope = buildTwinSyncEnvelope(
        syncId: SodiumFFI().randomBytes(16),
        deviceId: hexToBytes(_localDeviceId),
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        syncType: proto.TwinSyncType.DEVICE_SET_CHANGED,
        payload: sealed,
        where: _ownWhereWires(),
      );
      final ok = await _myceliumOwnSend(
          messageType: proto.MessageType.MT_TWIN_SYNC,
          payload: envelope,
          targetDeviceId: to);
      if (ok) placed++;
      _log.info('Type 16: key package for ${r.deviceId.substring(0, 8)} '
          '(${sealed.length} B sealed, envelope ${envelope.length} B) '
          '${ok ? "placed" : "NOT placed"} in the old line (§14.4)');
    }
    return (placed, missing);
  }

  /// Type 16 received: open, check, take over. Does not throw.
  void _handleTwinKeyPackage(List<int> payload) {
    final kem = identity.deviceKeys?.kem;
    if (kem == null) {
      _log.warn('Type 16: no device KEM keys loaded — package not opened');
      return;
    }
    final pkg = openDeviceKeyPackage(Uint8List.fromList(payload),
        x25519Sk: kem.x25519PrivateKey, mlKemSk: kem.mlKemPrivateKey);
    if (pkg == null) {
      _log.warn('Type 16: the package does not open with this device\'s '
          'keys — not for this device (§14.7)');
      return;
    }
    if (constantTimeEquals(pkg.ed25519Pk, identity.ed25519PublicKey)) {
      _log.debug('Type 16: the keys are already this device\'s');
      return;
    }
    try {
      if (!RotationChain.fromStored(pkg.chain)
          .holds(identity.userId, ChainKeys(pkg.ed25519Pk, pkg.mlDsaPk))) {
        _log.warn('Type 16: the chain does not lead from this UserID to the '
            'package\'s keys (§4.5.4) — NOT taken');
        return;
      }
      // D-109 B-3 (S422): siblings that have not taken their package yet
      // still sign with the previous keys — accepted for 7 days.
      _ownPreviousNote();
      identity.adoptSiblingRotation(
        chain: pkg.chain,
        ed25519Pk: pkg.ed25519Pk,
        ed25519Sk: pkg.ed25519Sk,
        mlDsaPk: pkg.mlDsaPk,
        mlDsaSk: pkg.mlDsaSk,
        x25519Pk: pkg.x25519Pk,
        x25519Sk: pkg.x25519Sk,
        mlKemPk: pkg.mlKemPk,
        mlKemSk: pkg.mlKemSk,
      );
    } on Object catch (e) {
      _log.warn('Type 16: keys NOT taken — $e');
      return;
    }
    final p = myceliumMailbox;
    if (p != null) {
      try {
        mycelium.MailboxRotation(p)
            .identityRotate(postBoxFrom(identity), fromSibling: true);
      } catch (e) {
        _log.error('Type 16: the running mailbox did not take the keys over '
            '($e) — it takes them at the next start');
      }
    }
    // D-107: the keys caught up — the bundle renews again from its next edge,
    // and "offline too long" (§14.6.3) no longer holds.
    recoveryBox?.release();
    recoveryOfflineTooLong = false;
    final gone = [
      for (final r in _devices.values)
        if (!r.isThisDevice && !pkg.remaining.contains(r.deviceId)) r.deviceId
    ];
    for (final id in gone) {
      _devices.remove(id);
    }
    _saveDevices();
    _myceliumOwnLineSync();
    _notifyDevicesChanged();
    _log.event('Type 16: keys of the ${pkg.reason.name} rotation taken over '
        '(§14.4) — chain ${identity.rotationChain.length} link(s)'
        '${gone.isEmpty ? "" : ", ${gone.length} device(s) left the set"}');
    onStateChanged?.call();
  }

  /// A package for [deviceId] sealed against the keys this set names, opened
  /// with THIS device's KEM secret keys — `true` would mean a device opens a
  /// package that is not its own. For the probe door of the class.
  bool _keyPackageOpensWithOwnKeys(String deviceId) {
    final r = _devices[deviceId]!;
    final pkg = DeviceKeyPackage(
      reason: KeyPackageReason.emergency,
      chain: [identity.rotationLinkTo(identity.ed25519PublicKey, identity.mlDsaPublicKey)],
      ed25519Sk: identity.ed25519SecretKey,
      mlDsaSk: identity.mlDsaSecretKey,
      x25519Pk: identity.x25519PublicKey,
      x25519Sk: identity.x25519SecretKey,
      mlKemPk: identity.mlKemPublicKey,
      mlKemSk: identity.mlKemSecretKey,
      remaining: [deviceId],
      atMs: 0,
    );
    final sealed = sealDeviceKeyPackage(pkg,
        x25519Pk: hexToBytes(r.deviceKemHex!),
        mlKemPk: hexToBytes(r.deviceMlKemHex!));
    final kem = identity.deviceKeys!.kem;
    return openDeviceKeyPackage(sealed,
            x25519Sk: kem.x25519PrivateKey, mlKemSk: kem.mlKemPrivateKey) !=
        null;
  }
}
