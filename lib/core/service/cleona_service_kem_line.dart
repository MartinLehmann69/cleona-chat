// E7 (D-40, §4.5.4, §14.7 Type 19) — the routine KEM rotation with more than
// one device.
//
// Every device that found the rotation due would otherwise draw its own random
// generation; contacts take the one with the higher state and the other device
// collects post it cannot open. So, with more than one device:
//
//  * only the device with the smallest DeviceID rotates — or any device once
//    the current generation is [kKemRotationTakeover] (14 days) old, so a
//    silent responsible device does not stop the rotation;
//  * the rotating device places Type 19 `KEM_ROTATED` (the new generation's
//    secret keys and its time) to each other own device BEFORE it announces
//    to contacts;
//  * the receiving device takes it as its current generation; its former
//    current one becomes the ONE previous one.
//
// With ONE device nothing here sends anything or holds anything back: the
// rotation runs exactly as before (no Type 19, no own-line deposit).
//
// No clock of its own (working rule 5): the decision hangs on the points in
// time at which `_performKeyRotation` already runs.

part of 'cleona_service.dart';

extension CleonaServiceKemLine on CleonaService {
  /// The DeviceIDs (hex) of the own device set that take part in the own
  /// line — 16-B UUIDs only, as in [_myceliumOwnLineSync].
  List<String> _kemLineDevices() => [
        for (final d in _devices.values)
          if (_ownLineDeviceId(d.deviceId) != null) d.deviceId,
      ];

  /// D-40: whether THIS device performs the due routine rotation. `true`
  /// with one device; with more, only for the smallest DeviceID or once the
  /// current generation is [kKemRotationTakeover] old.
  bool _kemRotationIsMine() {
    final ids = _kemLineDevices();
    if (ids.length <= 1 || !ids.contains(_localDeviceId)) return true;
    ids.sort();
    if (ids.first == _localDeviceId) return true;
    final since = identity.kemGenerationSince;
    if (since != null &&
        DateTime.now().difference(since) >= kKemRotationTakeover) {
      _log.info('KEM rotation: the device with the smallest DeviceID '
          '(${ids.first.substring(0, 8)}) has not rotated for '
          '${kKemRotationTakeover.inDays} days — this device takes over '
          '(D-40)');
      return true;
    }
    _log.debug('KEM rotation due, left to the device with the smallest '
        'DeviceID (${ids.first.substring(0, 8)}, D-40)');
    return false;
  }

  /// Type 19 to each other own device (§14.7): the generation the identity
  /// has just rotated to. Called AFTER `identity.rotateKemKeys()` and BEFORE
  /// the mailbox takes the new keys: the own-line packet is sealed to the
  /// identity's address as the running mailbox holds it, i.e. under the
  /// generation the other devices still hold — sealed under the new one,
  /// they could not open the very message that brings it to them.
  ///
  /// Awaited by the caller: the announcement to contacts goes out only after
  /// this deposit was attempted (D-40). Returns how many devices it was
  /// placed for; `0` with one device (nothing is sent).
  Future<int> _kemRotatedToOwnDevices() async {
    final others = [
      for (final d in _kemLineDevices())
        if (d != _localDeviceId) d,
    ];
    if (others.isEmpty) return 0;
    final at = identity.keyRotatedAt ?? DateTime.now();
    final syncId = SodiumFFI().randomBytes(16);
    _processedSyncIds[bytesToHex(syncId)] = DateTime.now().millisecondsSinceEpoch;
    final envelope = buildTwinSyncEnvelope(
      syncId: syncId,
      deviceId: hexToBytes(_localDeviceId),
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      syncType: proto.TwinSyncType.KEM_ROTATED,
      payload: Uint8List.fromList(utf8.encode(jsonEncode({
        'x25519Pk': bytesToHex(identity.x25519PublicKey),
        'x25519Sk': bytesToHex(identity.x25519SecretKey),
        'mlKemPk': bytesToHex(identity.mlKemPublicKey),
        'mlKemSk': bytesToHex(identity.mlKemSecretKey),
        'at': at.millisecondsSinceEpoch,
      }))),
    );
    final placed = await _myceliumOwnSend(
        messageType: proto.MessageTypeV3.MTV3_TWIN_SYNC, payload: envelope);
    if (placed) {
      _log.info('KEM rotation: Type 19 placed for ${others.length} other own '
          'device(s) — now the announcement to contacts (D-40)');
    } else {
      // The announcement still goes out: withheld, the contacts would keep
      // sealing to the previous generation, which this device drops after
      // 7 days. The other devices then park what they cannot open (D-40)
      // and count it if it expires.
      _log.warn('KEM rotation: Type 19 NOT placed for the other own '
          'device(s) — they cannot open post under the new generation until '
          'it reaches them');
    }
    return placed ? others.length : 0;
  }

  /// A Type 19 from another own device (§14.7, D-40): take the generation,
  /// the current one becomes the ONE previous one, and the mailbox swaps the
  /// keys (and opens what it parked). An older or the same generation is
  /// skipped — two devices that rotated at once converge on the later one.
  void _handleKemRotated(List<int> payload) {
    final Map<String, dynamic> j;
    final Uint8List xPk, xSk, kPk, kSk;
    final DateTime at;
    try {
      j = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      xPk = hexToBytes(j['x25519Pk'] as String);
      xSk = hexToBytes(j['x25519Sk'] as String);
      kPk = hexToBytes(j['mlKemPk'] as String);
      kSk = hexToBytes(j['mlKemSk'] as String);
      at = DateTime.fromMillisecondsSinceEpoch(j['at'] as int);
    } catch (e) {
      _log.warn('Twin KEM_ROTATED: unreadable payload — discarded ($e)');
      return;
    }
    if (xPk.length != 32 ||
        xSk.length != 32 ||
        kPk.length != OqsFFI.mlKemPublicKeyLength ||
        kSk.length != OqsFFI.mlKemSecretKeyLength) {
      _log.warn('Twin KEM_ROTATED: key lengths do not fit — discarded');
      return;
    }
    if (constantTimeEquals(xPk, identity.x25519PublicKey)) return;
    final since = identity.kemGenerationSince;
    if (since != null && !at.isAfter(since)) {
      _log.info('Twin KEM_ROTATED: generation of $at is not newer than the '
          'current one ($since) — skipped');
      return;
    }
    identity.adoptKemGeneration(
        x25519Pk: xPk, x25519Sk: xSk, mlKemPk: kPk, mlKemSk: kSk, at: at);
    // The mailbox swaps the keys like the rotating device's did and opens
    // the cells it parked for want of this generation (D-40, c); each opened
    // one is acknowledged and mirrored like any collected delivery.
    final p = myceliumMailbox;
    final opened = p == null
        ? 0
        : mycelium.MailboxParked(p).kemTake((
            x25519Pk: xPk,
            x25519Sk: xSk,
            mlKemPk: kPk,
            mlKemSk: kSk,
          ), now: at);
    _log.info('Twin KEM_ROTATED: generation of $at taken over (D-40), '
        '$opened parked cell(s) opened');
  }
}
