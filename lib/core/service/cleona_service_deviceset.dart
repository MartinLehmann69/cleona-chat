// §14.5 path 2 — THE PAIRWISE DEVICE-SET ANNOUNCEMENT.
//
// ── THE LOWERING THAT IS CLOSED HERE ────────────────────────────
//
// `_handleEmergencyKeyRotation` fed `verifyRotationCoAuth` with
//
//     const cachedDeviceSigKeys = <DeviceSigInfo>[];
//
// — a list empty at compile time. The `else` branch below it was dead
// code, `coAuthResult` was without exception `RotationCoAuthResult.legacy`,
// and EVERY incoming emergency rotation was applied unchecked.
//
// The `legacy` branch itself is NOT the error — v4_1 §14.5 lists it
// normatively: "A brand-new contact does not know `N`, a long-absent one has a
// stale state. Then: the case counts as a legacy case … and the new key is
// **applied anyway** — the **visibility principle**". The error is that
// it became the RULE: for every contact, permanently, without exception.
// §14.5 presupposes a second path for this, and it was missing completely:
//
//     "**The device set is announced pairwise.** Changes go out to contacts
//      as an ordinary delivery; the contact holds the state. The
//      announcement carries the previous device count and the
//      countersignatures of the remaining devices, so that a **shrinking of
//      the device set** requires proof. These very countersignatures are the
//      quorum from §14.4."
//
// Without this path the §7.5 protection against a seed thief is universally
// absent. Exactly that is "4.1 is less reliable than V3", and exactly that
// is what this file closes.
//
// ── WHY NO PUBLIC OBJECT ─────────────────────────────────────
//
// §14.5, explicitly: "A public durable object was explicitly rejected. It
// would be formally permissible (a self-declaration about one's own
// identity), but would make the device set of every identity enumerable
// network-wide and turn the identity itself into a discoverable object — a
// breach of the no-directory property at the person level."
//
// ── CHECK AGAINST §5.1 AND §23.6/RL-1 ──────────────────────────────────
//
// The announcement goes via [sendToUser], i.e. the ordinary delivery path.
// At egress it thus remains what §5.1 requires: cells of fixed size in
// constant cadence to partners DRAWN by the schedule — "the slot
// schedule draws the partner, not the sender" (§5.1 invariant 4). An
// additional message type changes neither `t`, `s`, `c` nor `d`; it
// fills a slot that is due anyway.
//
// The observable graph remains the sync graph, "decoupled from the social
// graph" (§23.6 row 1, RL-1). Only the CONTACT learns something — namely
// the device count and the device signing keys of a person with whom it
// maintains a contact relationship anyway. The social graph thereby
// becomes visible by no edge more than the contact relationship makes it
// anyway. That is the difference to the rejected public object, which
// would have made the device set of EVERY identity enumerable network-wide.
//
// ── WHAT THIS FILE DELIBERATELY CANNOT DO ──────────────────────────────────
//
// It only announces a device set that this node can prove COMPLETELY —
// i.e. only devices whose public signing keys it holds. `DeviceRecord`
// carries none (only `deviceNodeIdHex`), and there is no storage place
// for the keys of the sibling devices. Today that is exactly the
// single-device case.
//
// THAT IS FAIL-CLOSED AND NOT "AT LEAST SOMETHING": an announcement with
// an INCOMPLETE set would look like a shrinking at the receiver. It would
// cache a smaller set, and every later quorum check would run against this
// smaller denominator — the protection would not be extended but weakened.
// A contact had better keep its last, larger state.

part of 'cleona_service.dart';

/// How many devices an identity may keep (§14.8: "Cap: 5 devices per
/// identity"). At the receiver only observing — §14.8 says explicitly that
/// the limit is enforced "locally, on the enrolling device" and is merely
/// visible at the contact: "contacts see the device count in the
/// announcement, and a jump stands out".
const int kDeviceCapPerIdentity = 5;

extension DeviceSetAnnouncementOps on CleonaService {
  // ── SENDESEITE ────────────────────────────────────────────────────────

  /// The co-signing token of THIS device over [hash].
  ///
  /// Null as long as [IdentityContext.deviceKeys] is empty (before
  /// `initKeys`). The device signing keys are generated LOCALLY and are
  /// not seed-derived (`device_signature.dart`) — that is the whole
  /// structural basis of §7.5: whoever steals the seed cannot forge this token.
  RotationApprovalToken? _ownApprovalToken(Uint8List hash) {
    final bundle = identity.deviceKeys;
    if (bundle == null) {
      _log.warn('§7.5: no co-signature token — the device key '
          'bundle is not loaded (initKeys has not run yet).');
      return null;
    }
    return RotationApprovalToken(
      deviceNodeId: Uint8List.fromList(identity.deviceNodeId),
      rotationHash: hash,
      deviceEd25519Sig:
          SodiumFFI().signEd25519(hash, bundle.sig.ed25519PrivateKey),
      deviceMlDsaSig:
          OqsFFI().mlDsaSign(hash, bundle.sig.mlDsaPrivateKey),
    );
  }

  /// The device set this node CAN prove — or null if it cannot prove it
  /// completely.
  ///
  /// See header comment: an incomplete set would be indistinguishable from
  /// a shrinking for the receiver and would lower its quorum denominator.
  /// Better to announce nothing at all.
  List<DeviceSigInfo>? _announceableDeviceSet() {
    final bundle = identity.deviceKeys;
    if (bundle == null) return null;
    // Only the own device can be proven: `DeviceRecord` keeps no signing
    // keys, and a storage place for those of the sibling devices does not
    // exist (the same gap that also keeps the multi-device rotation
    // fail-closed).
    if (_devices.length > 1) return null;
    return [
      DeviceSigInfo(
        deviceNodeId: Uint8List.fromList(identity.deviceNodeId),
        deviceEd25519Pk: Uint8List.fromList(bundle.sig.ed25519PublicKey),
        deviceMlDsaPk: Uint8List.fromList(bundle.sig.mlDsaPublicKey),
        isPrimary: !identity.isLinkedDevice,
      ),
    ];
  }

  /// The next announcement counter, monotonic and across restarts.
  ///
  /// It lives in the device storage under a `_` key — `_loadDevices`
  /// already skips such keys (the same pattern as `_syncIdTs`), so no
  /// second file and no second load path is created. MONOTONIC IS
  /// SECURITY-RELEVANT HERE and not hygiene: the receiver rejects
  /// everything `<=` its highest state, and without that a recorded OLDER
  /// announcement — with the LARGER device set — could bring a locked-out
  /// device back as a valid co-signer.
  int _nextDeviceSetSeq() {
    final next = _deviceSetSeq + 1;
    _deviceSetSeq = next;
    _saveDevices();
    return next;
  }

  /// §14.5 path 2: announce the own device set pairwise to every accepted
  /// contact. [occasion] stands only in the log.
  ///
  /// Called on every change of the device set and after every rotation —
  /// §14.4: "The shared key is rerolled on **every change to the
  /// device set**", and the contact only holds the state if it gets it
  /// delivered (§14.5: "every contact holds the state locally and learns
  /// of changes to it because they are delivered to it").
  void _announceDeviceSetToContacts({required String occasion}) {
    final record = _announceableDeviceSet();
    if (record == null) {
      _log.warn('§14.5 path 2: NO device set announcement ($occasion) — '
          'this node cannot fully prove ${_devices.length} device(s) '
          '(it holds only its own '
          'signature keys). The contacts keep their last state; '
          'an incomplete set would LOWER their quorum denominator.');
      return;
    }

    final seq = _nextDeviceSetSeq();
    final changeHash = computeDeviceSetChangeHash(
      userId: Uint8List.fromList(identity.userId),
      newDeviceNodeIds: record.map((d) => d.deviceNodeId).toList(),
      newSeq: seq,
    );

    final ann = proto.DeviceSetAnnounceV3()
      ..seq = seq
      ..issuedAtMs = Int64(DateTime.now().millisecondsSinceEpoch)
      ..previousDeviceCount = _devices.length
      ..changeHash = changeHash;
    ann.deviceSigKeys.addAll(record.map((d) => d.toProto()));

    // §14.5: "the countersignatures of the remaining devices … These very
    // countersignatures are the quorum from §14.4." With M=1 that is, per
    // §14.8 ("M = 1 → 1"), exactly one — that of this device.
    final token = _ownApprovalToken(changeHash);
    if (token != null) {
      ann.approvals.add(token.toProto());
    }

    // The identity signature over fields 1-6. It proves that the
    // announcement comes from the contact; the receiver checks it against
    // its stored trust anchor.
    ann.userSignatureEd25519 =
        SodiumFFI().signEd25519(Uint8List.fromList(ann.writeToBuffer()),
            identity.ed25519SecretKey);

    final payload = Uint8List.fromList(ann.writeToBuffer());
    var sent = 0;
    for (final contact in _contacts.values) {
      if (contact.status != 'accepted') continue;
      if (contact.x25519Pk == null || contact.mlKemPk == null) continue;
      sent++;
      _detachedSend(
          'MTV3_DEVICE_SET_ANNOUNCE',
          sendToUser(
            recipientUserId: contact.nodeId,
            messageType: proto.MessageTypeV3.MTV3_DEVICE_SET_ANNOUNCE,
            payload: payload,
          ));
    }
    _log.info('§14.5 path 2: device set announcement ($occasion) seq=$seq, '
        '${record.length} device(s), ${ann.approvals.length} co-signature(s), '
        'pairwise to $sent contact(s).');
  }

  // ── EMPFANGSSEITE ─────────────────────────────────────────────────────

  /// §14.5 path 2 on the receiving side.
  ///
  /// The order of the checks is intentional: first "do I know the sender"
  /// (KEX gate), then "does it really come from them" (identity signature),
  /// then "is it fresh" (seq), then "does the hash match" (computed
  /// ourselves), and only last the expensive quorum check. None of it may
  /// be skipped, because every later check takes the earlier ones as
  /// given.
  void _handleDeviceSetAnnounceV3(HarvestEvent event) {
    final senderHex = event.senderUserId.hex;
    final contact = _contacts[senderHex];
    if (contact == null || contact.status != 'accepted') {
      _log.warn('DEVICE_SET_ANNOUNCE from unknown/not accepted '
          'sender ${_short(senderHex)} — discarded (KEX gate).');
      return;
    }

    proto.DeviceSetAnnounceV3 ann;
    try {
      ann = proto.DeviceSetAnnounceV3.fromBuffer(event.payload);
    } catch (e) {
      _log.warn('DEVICE_SET_ANNOUNCE from ${_short(senderHex)}: '
          'not readable ($e) — discarded.');
      return;
    }

    // 1. Identity signature over fields 1-6.
    final anchor = contact.ed25519Pk;
    if (anchor == null || contact.trustAnchorQuarantined) {
      _log.warn('DEVICE_SET_ANNOUNCE from ${_short(senderHex)}: no '
          'usable trust anchor (quarantine='
          '${contact.trustAnchorQuarantined}) — discarded.');
      return;
    }
    // Rebuild the signed bytes — fields 1-6 in the same order in which the
    // sender wrote them (`writeToBuffer` writes by field number, so the
    // order is not intent but a property). NO `deepCopy()` followed by
    // `clear…`: that is marked as deprecated in this protobuf version.
    final withoutSig = proto.DeviceSetAnnounceV3()
      ..seq = ann.seq
      ..issuedAtMs = ann.issuedAtMs
      ..previousDeviceCount = ann.previousDeviceCount
      ..changeHash = ann.changeHash;
    withoutSig.deviceSigKeys.addAll(ann.deviceSigKeys);
    withoutSig.approvals.addAll(ann.approvals);
    if (!SodiumFFI().verifyEd25519(
      Uint8List.fromList(withoutSig.writeToBuffer()),
      Uint8List.fromList(ann.userSignatureEd25519),
      anchor,
    )) {
      _log.warn('DEVICE_SET_ANNOUNCE from ${_short(senderHex)}: '
          'identity signature INVALID — discarded.');
      return;
    }

    // 2. Replay. `<=`, not `<`: the same seq twice is either a duplicate
    //    or a recording, and in both cases there is nothing new to adopt.
    if (ann.seq <= contact.deviceSetSeq) {
      _log.warn('DEVICE_SET_ANNOUNCE from ${_short(senderHex)}: seq='
          '${ann.seq} <= stored ${contact.deviceSetSeq} — discarded '
          '(replay).');
      return;
    }

    // 3. Compute the change hash OURSELVES. The one from the frame is the
    //    claim of the party that is under suspicion right now.
    final newIds = ann.deviceSigKeys
        .map((d) => Uint8List.fromList(d.deviceNodeId))
        .toList();
    final expected = computeDeviceSetChangeHash(
      userId: Uint8List.fromList(event.senderUserId),
      newDeviceNodeIds: newIds,
      newSeq: ann.seq,
    );
    if (!_bytesSame(expected, Uint8List.fromList(ann.changeHash))) {
      _log.warn('DEVICE_SET_ANNOUNCE from ${_short(senderHex)}: '
          'changeHash does not match the content — discarded.');
      return;
    }
    if (newIds.isEmpty) {
      _log.warn('DEVICE_SET_ANNOUNCE from ${_short(senderHex)}: empty '
          'device set — discarded. An identity without a device can announce '
          'nothing, and an empty set would have set the quorum denominator '
          'to 0.');
      return;
    }

    // 4. §14.8 cap: only make visible, do not enforce — §14.8 says
    //    explicitly that the limit is enforced at the enrolling device and
    //    is "noticeable" at the contact. A larger set makes the quorum
    //    HARDER anyway, not easier; rejecting it would lock out an honest
    //    user without protecting anything.
    if (newIds.length > kDeviceCapPerIdentity) {
      _log.warn('§14.8: ${_short(senderHex)} announces ${newIds.length} '
          'devices — more than the cap of $kDeviceCapPerIdentity. '
          'Taken over and noted here (the limit applies locally on the '
          'admitting device).');
    }

    // 5. SHRINKING REQUIRES PROOF (§14.5). Growth does not: §14.4 "Any
    //    device may add alone. The rotation due in this case wraps for all
    //    already-enrolled devices too; no one loses anything, and a thief
    //    gains nothing they did not already have."
    //
    //    It is checked against the CACHED set, never against the one sent
    //    along — otherwise whoever can write an announcement could also
    //    name its co-signers (`verifyRotationCoAuth` justifies this at its
    //    own place).
    final cached = contact.deviceSigKeys
        .map((d) => d.toSigInfo())
        .whereType<DeviceSigInfo>()
        .toList();
    if (cached.isNotEmpty &&
        newIds.length < cached.length) {
      final result = verifyRotationCoAuth(
        tokens:
            ann.approvals.map(RotationApprovalToken.fromProto).toList(),
        cachedDeviceSigKeys: cached,
        rotationHash: expected,
        occasion: CoAuthOccasion.deviceSetChange,
        remainingDeviceCount: newIds.length,
      );
      if (result != RotationCoAuthResult.quorumMet &&
          result != RotationCoAuthResult.singleDevice) {
        // REJECTED — and that does NOT contradict the visibility principle
        // from §14.5. The principle applies to ROTATION ("a rotation is
        // never blocked, only shown"); here no rotation is blocked, but the
        // claim "these devices are gone" is rejected, for which §14.5
        // literally demands proof: "so that a **shrinking of the device
        // set** requires proof". The contact keeps its previous, LARGER set
        // — the stricter state.
        _log.warn('§14.5: ${_short(senderHex)} shrinks the device set '
            'from ${cached.length} to ${newIds.length}, but '
            'the quorum is NOT proven ($result, '
            '${ann.approvals.length} tokens, required '
            '${deviceSetChangeQuorum(newIds.length)}) — REJECTED, the '
            'previous set stays.');
        try {
          onRotationCoAuthWarning?.call(
              senderHex,
              contact.displayName,
              ann.approvals.length,
              deviceSetChangeQuorum(newIds.length));
        } catch (e) {
          _log.warn('onRotationCoAuthWarning listener threw: $e');
        }
        return;
      }
    }

    // 6. Adopt.
    final before = contact.deviceSigKeys.length;
    contact.deviceSigKeys = ann.deviceSigKeys
        .map((d) => ContactDeviceSigKey(
              deviceNodeIdHex: bytesToHex(Uint8List.fromList(d.deviceNodeId)),
              ed25519PkHex: bytesToHex(Uint8List.fromList(d.deviceEd25519Pk)),
              mlDsaPkHex: bytesToHex(Uint8List.fromList(d.deviceMlDsaPk)),
              isPrimary: d.isPrimary,
            ))
        .toList();
    contact.deviceSetSeq = ann.seq;
    _saveContacts();
    _log.info('§14.5 path 2: device set of ${_short(senderHex)} '
        'adopted — seq=${ann.seq}, $before -> '
        '${contact.deviceSigKeys.length} device(s). The quorum check '
        'of a future rotation thus has a denominator.');
    onStateChanged?.call();
  }

  String _short(String hex) =>
      hex.length >= 8 ? hex.substring(0, 8) : hex;

  bool _bytesSame(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// Bridge from the storage form (hex JSON) into the crypto layer.
extension ContactDeviceSigKeyBridge on ContactDeviceSigKey {
  /// Null if a field is unusable — a half-read record must not wander into
  /// the quorum denominator as a valid co-signer.
  DeviceSigInfo? toSigInfo() {
    try {
      final id = hexToBytes(deviceNodeIdHex);
      final ed = hexToBytes(ed25519PkHex);
      final dsa = hexToBytes(mlDsaPkHex);
      if (id.isEmpty || ed.isEmpty || dsa.isEmpty) return null;
      return DeviceSigInfo(
        deviceNodeId: id,
        deviceEd25519Pk: ed,
        deviceMlDsaPk: dsa,
        isPrimary: isPrimary,
      );
    } catch (_) {
      return null;
    }
  }
}
