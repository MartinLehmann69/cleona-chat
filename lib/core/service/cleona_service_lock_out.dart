// V4.2 §14.4 "All identities on every own device" (S422, phase 5 of
// `S414-KOPPELN-BAUPLAN.md`, D-107, D-109, D-123) — Type 11 and what follows
// from it.
//
// ── ON THE LOCKED-OUT DEVICE ─────────────────────────────────────────────
//
// "A device that learns it has been locked out (Type 11 naming itself)
// deletes every identity on itself as a deletion from another own device does
// (§21.5.2), and the interface says why; a key change in which it stays in the
// set never makes it delete anything." It deletes ONLY on the proof Type 11
// carries: the countersignatures of the remaining devices over the change
// hash, checked against the device signing keys its own set names, counted
// over `M` (§14.8). Every own device holds the identity keys (§14.6.2) — a
// Type 11 without that proof could come from one stolen device, and one
// device alone must not make another delete itself.
//
// Its indices are NOT noted as deleted: the identities live on, on the other
// own devices, and a list naming them `active = false` would delete them there
// (§14.7 Type 23).
//
// ── ON THE REMAINING DEVICES ─────────────────────────────────────────────
//
// The locked-out device leaves the set and is noted device-wide (DeviceID and
// node identifier of the device), so that an identity list (Type 23) never
// enters it into a set again. An explicit enrolment is not affected: that is
// the user's decision (§14.6.1). They do not rotate on Type 11 — the device
// that started the lock-out changed the keys and placed their key packages
// (Type 16, §14.4 "Device side").

part of 'cleona_service.dart';

/// The Type 11 body (§14.7): the DeviceID of the locked-out device and the
/// proof of the quorum — the remaining per-identity device identifiers, the
/// announcement number and the countersignatures over the change hash.
Uint8List lockOutNoticeBody({
  required String deviceIdHex,
  required int changeSeq,
  required List<String> remainingNodeIdHexes,
  required List<RotationApprovalToken> changeTokens,
}) =>
    Uint8List.fromList(utf8.encode(jsonEncode({
      'v': 2,
      'd': deviceIdHex,
      'cs': changeSeq,
      'ids': remainingNodeIdHexes,
      'c': [
        for (final t in changeTokens) bytesToHex(t.toProto().writeToBuffer())
      ],
    })));

/// A Type 11 body read: the named DeviceID, and the proof when the body
/// carries one (a body of the form before S422 is the bare DeviceID).
typedef LockOutNotice = ({
  String deviceIdHex,
  int? changeSeq,
  List<String> remainingNodeIdHexes,
  List<RotationApprovalToken> changeTokens,
});

LockOutNotice? lockOutNoticeRead(List<int> payload) {
  final String text;
  try {
    text = utf8.decode(payload);
  } on Object {
    return null;
  }
  if (!text.startsWith('{')) {
    return (
      deviceIdHex: text,
      changeSeq: null,
      remainingNodeIdHexes: const [],
      changeTokens: const [],
    );
  }
  try {
    final j = jsonDecode(text) as Map<String, dynamic>;
    final d = j['d'];
    if (d is! String) return null;
    return (
      deviceIdHex: d,
      changeSeq: j['cs'] as int?,
      remainingNodeIdHexes: [for (final x in (j['ids'] as List? ?? const [])) '$x'],
      changeTokens: [
        for (final x in (j['c'] as List? ?? const []))
          RotationApprovalToken.fromProto(
              proto.RotationApprovalToken.fromBuffer(hexToBytes('$x')))
      ],
    );
  } on Object {
    return null;
  }
}

extension CleonaServiceLockOut on CleonaService {
  /// Type 11 (§14.7) from another own device.
  void _handleTwinDeviceRevoked(List<int> payload) {
    try {
      final notice = lockOutNoticeRead(payload);
      if (notice == null) {
        _log.warn('Twin DEVICE_REVOKED: body not readable — discarded');
        return;
      }
      final deviceIdHex = notice.deviceIdHex;
      if (deviceIdHex == _localDeviceId) {
        if (!_lockOutProofHolds(notice)) {
          _log.warn('§14.4 Type 11 names THIS device, but carries no proof '
              'of the remaining devices\' quorum that this device can check '
              '— nothing is deleted (one device alone cannot lock another '
              'out)');
          return;
        }
        _log.warn('§14.4 THIS DEVICE has been locked out by the other own '
            'devices (quorum proven) — every identity on it is deleted');
        unawaited(_lockedOutSelf());
        return;
      }
      final revoked = _devices.remove(deviceIdHex);
      _saveDevices();
      enrolApprovalEnd(revoked); // D-99: its enrolment approval ends
      unawaited(_applyDeviceSetRemoval(revoked, deviceIdHex));
      // S422: no rotation of its own here — the device that started the
      // lock-out changed the keys and placed this device's key package
      // (Type 16); a second rotation would compete with that one.
      if (revoked != null) _lockOutNoteDevice(revoked);
      _log.info('Twin device revoked: $deviceIdHex');
      _notifyDevicesChanged();
    } catch (e) {
      _log.warn('Twin DEVICE_REVOKED failed: $e');
    }
  }

  /// Whether [n] proves that the remaining own devices locked THIS device out
  /// with their quorum (§14.4, §14.8): the remaining identifiers do not name
  /// this device, and the countersignatures over the change hash come from
  /// at least `quorum(M)` distinct devices this identity's set names.
  bool _lockOutProofHolds(LockOutNotice n) {
    final seq = n.changeSeq;
    if (seq == null || n.remainingNodeIdHexes.isEmpty) return false;
    final own = bytesToHex(identity.deviceNodeId);
    if (n.remainingNodeIdHexes.contains(own)) return false;
    final change = computeDeviceSetChangeHash(
        userId: identity.userId,
        newDeviceNodeIds: [for (final h in n.remainingNodeIdHexes) hexToBytes(h)],
        newSeq: seq);
    final known = <String, DeviceRecord>{};
    for (final r in _devices.values) {
      if (r.isThisDevice) continue;
      final id = _coSignNodeIdOf(r);
      if (id != null) known[bytesToHex(id)] = r;
    }
    final named = n.remainingNodeIdHexes.toSet();
    final required = deviceSetChangeQuorum(named.length);
    final approvers = <String>{};
    for (final t in n.changeTokens) {
      final key = bytesToHex(t.deviceNodeId);
      final r = known[key];
      if (r == null || !named.contains(key) || approvers.contains(key)) continue;
      if (bytesToHex(t.rotationHash) != bytesToHex(change)) continue;
      if (t.verify(hexToBytes(r.deviceSigEd25519Hex!),
          hexToBytes(r.deviceSigMlDsaHex!))) {
        approvers.add(key);
      }
    }
    _log.info('§14.4 Type 11 proof: ${approvers.length} of $required '
        'countersignature(s) of the remaining ${named.length} device(s)');
    return required > 0 && approvers.length >= required;
  }

  /// This device was locked out: every identity on it is deleted as Type 17
  /// deletes one (§21.5.2) — post held first, the note for the interface
  /// written (indices NOT noted as deleted, see the file head), then the
  /// local data cleared and the host removes the identity.
  Future<void> _lockedOutSelf() async {
    final services = _identitySetServices;
    try {
      _identityMgr.lockedOutSelfNote([
        for (final s in services)
          if (s.identity.hdIndex != null)
            (index: s.identity.hdIndex!, name: s.identity.displayName)
      ], DateTime.now());
    } on Object catch (e) {
      _log.warn('§14.4 lock-out: the note for the interface was not written '
          '($e) — the identities are deleted all the same');
    }
    for (final s in services) {
      final p = s.myceliumMailbox;
      if (p != null) p.node.postHold(p.identity, true);
      s._log.warn('§14.4: this device was locked out — the local copy of this '
          'identity is being cleared away');
      s._wipeLocalIdentityData();
      s.onIdentityDeletedRemotely?.call(s.identity.userIdHex);
    }
  }

  /// D-109 B-3 (§14.4 "The transition"): the identity's signing keys before
  /// the change it is about to make, with the time — kept in the store.
  void _ownPreviousNote() {
    try {
      store.putEntry(CleonaService._areaCoSign, 'previous', {
        'ed': bytesToHex(identity.ed25519PublicKey),
        'dsa': bytesToHex(identity.mlDsaPublicKey),
        'at': DateTime.now().millisecondsSinceEpoch,
      });
    } on Object catch (e) {
      _log.warn('B-3: the previous signing keys were not noted — $e');
    }
  }

  /// D-109 B-3: "during the 7-day transition the own line also accepts
  /// envelopes under the previous own signing keys, only from devices still
  /// in the set after the change". [ed]/[dsa]: the keys the envelope is
  /// signed with; [device]: the DeviceID it names, `null` when none of the
  /// set.
  bool _ownPreviousAccepts(Uint8List ed, Uint8List dsa, Uint8List? device) {
    if (device == null) return false;
    final r = _devices[bytesToHex(device)];
    if (r == null || r.isThisDevice) return false;
    final Map<String, dynamic>? p;
    try {
      p = store.loadArea(CleonaService._areaCoSign)['previous'];
    } on Object {
      return false;
    }
    if (p == null || p['at'] is! int) return false;
    final age = DateTime.now().millisecondsSinceEpoch - (p['at'] as int);
    if (age < 0 || age > const Duration(days: 7).inMilliseconds) return false;
    return bytesToHex(ed) == p['ed'] && bytesToHex(dsa) == p['dsa'];
  }

  /// Notes [r]'s device device-wide as locked out (D-109, phase 5).
  void _lockOutNoteDevice(DeviceRecord r) {
    try {
      _identityMgr.lockedOutDevicesNote(deviceRecordKeys(r)..remove('this'));
    } on Object catch (e) {
      _log.warn('§14.4 lock-out: the device-wide note was not written — $e');
    }
  }

  /// Whether [r] names a device that was locked out of this user's devices.
  bool _lockOutMarked(DeviceRecord r) {
    try {
      final marked = _identityMgr.lockedOutDevices();
      return deviceRecordKeys(r).any(marked.contains);
    } on Object {
      return false;
    }
  }
}
