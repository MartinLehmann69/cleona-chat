// V4.2 §14.4 "Who is allowed to do what", §14.5, §14.8, §14.7 Types 12/13 —
// the co-signing round of an Emergency Key Rotation and of a lock-out
// (S422, phases 3 and 4 of `S414-KOPPELN-BAUPLAN.md`, D-123).
//
// ── THE STARTING DEVICE ──────────────────────────────────────────────────
//
// It forms the new keys ONCE (the countersignature covers their public
// halves), keeps them in the identity's store with the round, and asks every
// other remaining own device for its countersignature (Type 12, naming the
// reason in `approval_kind`, §14.8). Its own approval counts. The keys change
// only when the quorum is reached — counted in DISTINCT devices of the set,
// each token checked against the device signing keys this identity's set
// names for that device (§14.9.1). Without the quorum nothing rotates; the
// round stays visible until the quorum, a rejection that makes it
// unreachable, or the user's cancel. THERE IS NO CLOCK (S400 §9 E-a): the
// 5-minute window and the 2-minute grace of the approver are gone.
//
// A lock-out is a device-set change and a key change at once: the remaining
// devices sign the rotation hash (for the contacts' check, §14.4 (ii)) and
// the change hash over the remaining set and a reserved announcement number
// (the shrink proof, §14.5 path 2). The quorum counts the REMAINING devices
// `M` (§14.8: M = 1 → 1, M ≥ 2 → max(2, ⌈M/2⌉)).
//
// ── THE APPROVING DEVICE ─────────────────────────────────────────────────
//
// It recomputes both hashes from what the request names before it parks it,
// keeps the request in its store (it survives a restart), and signs only on
// the user's explicit decision. One decision answers every request of the
// same round — the requests of all identities of the starting device (§14.4
// "one approval per device counts for all identities"); each identity signs
// with its own device keys (D-106).
//
// ── A CANCELLED ROUND (§14.8, D-124 point 5) ─────────────────────────────
//
// The starting device sends the same request marked `withdrawn` to every
// remaining device that has not answered. Such a device drops the parked
// request, keeps the withdrawal, and shows it no more; an approval of it is
// no longer given there and, arriving late, counts nowhere here.

part of 'cleona_service.dart';

/// The new keys of an Emergency Key Rotation (§4.5.4), formed before the
/// co-signing round and kept in the identity's store until it ends.
class EmergencyKeys {
  final Uint8List ed25519Pk, ed25519Sk, mlDsaPk, mlDsaSk;
  final Uint8List x25519Pk, x25519Sk, mlKemPk, mlKemSk;

  const EmergencyKeys({
    required this.ed25519Pk,
    required this.ed25519Sk,
    required this.mlDsaPk,
    required this.mlDsaSk,
    required this.x25519Pk,
    required this.x25519Sk,
    required this.mlKemPk,
    required this.mlKemSk,
  });

  Map<String, dynamic> toJson() => {
        'ep': bytesToHex(ed25519Pk),
        'es': bytesToHex(ed25519Sk),
        'dp': bytesToHex(mlDsaPk),
        'ds': bytesToHex(mlDsaSk),
        'xp': bytesToHex(x25519Pk),
        'xs': bytesToHex(x25519Sk),
        'kp': bytesToHex(mlKemPk),
        'ks': bytesToHex(mlKemSk),
      };

  static EmergencyKeys? fromJson(Object? j) {
    if (j is! Map) return null;
    Uint8List? b(String k) {
      final v = j[k];
      return v is String && v.isNotEmpty ? hexToBytes(v) : null;
    }

    final ep = b('ep'), es = b('es'), dp = b('dp'), ds = b('ds');
    final xp = b('xp'), xs = b('xs'), kp = b('kp'), ks = b('ks');
    if ([ep, es, dp, ds, xp, xs, kp, ks].any((x) => x == null)) return null;
    return EmergencyKeys(
        ed25519Pk: ep!,
        ed25519Sk: es!,
        mlDsaPk: dp!,
        mlDsaSk: ds!,
        x25519Pk: xp!,
        x25519Sk: xs!,
        mlKemPk: kp!,
        mlKemSk: ks!);
  }
}

/// A co-signing round started on this device (§14.5, §14.8). Kept in the
/// identity's store ([CleonaService._areaCoSign]) until the quorum, a
/// rejection that makes it unreachable, or the user's cancel.
class CoSignRound {
  /// One per user action; the same in every identity of this device.
  final String roundId;

  /// The DeviceID being locked out — `null` for a key rotation alone.
  final String? lockOutDeviceId;

  /// DeviceIDs that remain, this device included.
  final List<String> remaining;

  /// The per-identity device identifiers that remain (lock-out only).
  final List<String> remainingNodeIds;

  /// Distinct devices needed, this device included (§14.8).
  final int required;
  final String rotationHashHex;
  final String? changeHashHex;
  final int? changeSeq;
  final EmergencyKeys keys;
  final String reason;
  final bool askPreviousDayValues;
  final int startedAtMs;

  /// Per device identifier (hex): the token over the rotation hash (`t`)
  /// and, at a lock-out, over the change hash (`c`), each the proto in hex.
  final Map<String, Map<String, String>> approvals;

  /// DeviceIDs that answered with a rejection.
  final Set<String> rejectedBy;

  CoSignRound({
    required this.roundId,
    required this.lockOutDeviceId,
    required this.remaining,
    required this.remainingNodeIds,
    required this.required,
    required this.rotationHashHex,
    required this.changeHashHex,
    required this.changeSeq,
    required this.keys,
    required this.reason,
    required this.askPreviousDayValues,
    required this.startedAtMs,
    Map<String, Map<String, String>>? approvals,
    Set<String>? rejectedBy,
  })  : approvals = approvals ?? {},
        rejectedBy = rejectedBy ?? {};

  bool get lockOut => lockOutDeviceId != null;

  /// The quorum can no longer be reached: the devices that did not reject
  /// are fewer than [required].
  bool get unreachable =>
      remaining.length - rejectedBy.length < required;

  bool get quorumMet => approvals.length >= required;

  List<RotationApprovalToken> tokens(String which) => [
        for (final a in approvals.values)
          if (a[which] != null)
            RotationApprovalToken.fromProto(
                proto.RotationApprovalToken.fromBuffer(hexToBytes(a[which]!)))
      ];

  Map<String, dynamic> toJson() => {
        'id': roundId,
        if (lockOutDeviceId != null) 'out': lockOutDeviceId,
        'rem': remaining,
        'remN': remainingNodeIds,
        'req': required,
        'rh': rotationHashHex,
        if (changeHashHex != null) 'ch': changeHashHex,
        if (changeSeq != null) 'cs': changeSeq,
        'k': keys.toJson(),
        'why': reason,
        'prev': askPreviousDayValues,
        'at': startedAtMs,
        'ok': approvals,
        'no': rejectedBy.toList(),
      };

  static CoSignRound? fromJson(Map<String, dynamic> j) {
    final keys = EmergencyKeys.fromJson(j['k']);
    final id = j['id'], rh = j['rh'], req = j['req'];
    if (keys == null || id is! String || rh is! String || req is! int) {
      return null;
    }
    final ok = <String, Map<String, String>>{};
    final raw = j['ok'];
    if (raw is Map) {
      for (final e in raw.entries) {
        if (e.value is Map) {
          ok['${e.key}'] = (e.value as Map)
              .map((k, v) => MapEntry('$k', '$v'));
        }
      }
    }
    return CoSignRound(
      roundId: id,
      lockOutDeviceId: j['out'] as String?,
      remaining: [for (final x in (j['rem'] as List? ?? const [])) '$x'],
      remainingNodeIds: [for (final x in (j['remN'] as List? ?? const [])) '$x'],
      required: req,
      rotationHashHex: rh,
      changeHashHex: j['ch'] as String?,
      changeSeq: j['cs'] as int?,
      keys: keys,
      reason: j['why'] as String? ?? KeyPackageReason.emergency.name,
      askPreviousDayValues: j['prev'] != false,
      startedAtMs: j['at'] as int? ?? 0,
      approvals: ok,
      rejectedBy: {for (final x in (j['no'] as List? ?? const [])) '$x'},
    );
  }
}

extension CleonaServiceCoSign on CleonaService {
  /// The round this identity started and that has not ended — at most one
  /// (D-109: one lock-out at a time; a second action waits for the first).
  CoSignRound? get coSignRound {
    try {
      final j = store.loadArea(CleonaService._areaCoSign)['round'];
      return j == null ? null : CoSignRound.fromJson(j);
    } on Object catch (e) {
      _log.warn('§14.5 co-signing: round not readable — $e');
      return null;
    }
  }

  void _coSignPut(CoSignRound? r) {
    if (r == null) {
      store.removeEntry(CleonaService._areaCoSign, 'round');
    } else {
      store.putEntry(CleonaService._areaCoSign, 'round', r.toJson());
    }
  }

  /// Whether a lock-out of ANY identity of this device waits for its quorum
  /// — then the device set does not grow (§14.4, D-109).
  bool get coSignLockOutPendingOnHost {
    final p = myceliumMailbox;
    final all = p == null ? [this] : servicesOnHost(p.host, this);
    for (final s in all) {
      if (s.coSignRound?.lockOut == true) return true;
    }
    return false;
  }

  /// The per-identity identifier of [r] (§4.1, D-106) — `H(Ed25519)` of the
  /// device signing key this identity's set names for it; `null` while the
  /// set names none.
  Uint8List? _coSignNodeIdOf(DeviceRecord r) {
    if (r.isThisDevice) return Uint8List.fromList(identity.deviceNodeId);
    final ed = r.deviceSigEd25519Hex;
    return ed == null ? null : HdWallet.computeDeviceNodeId(hexToBytes(ed));
  }

  /// Starts a co-signing round (§14.4, §14.8): an Emergency Key Rotation
  /// ([lockOutDeviceId] `null`) or a lock-out of [lockOutDeviceId] (the
  /// DeviceID in this identity's set). Returns `true` when the keys changed
  /// right away (the own approval was the quorum: one remaining device), and
  /// `false` when the round waits for the other devices or did not start
  /// (named in the log). [roundId]: shared by every identity of this device
  /// for one user action.
  Future<bool> coSignStart(
      {required String? lockOutDeviceId,
      KeyPackageReason reason = KeyPackageReason.emergency,
      bool askPreviousDayValues = true,
      Uint8List? roundId}) async {
    final open = coSignRound;
    if (open != null) {
      _log.warn('§14.5 co-signing: a round (${open.roundId.substring(0, 8)}, '
          '${open.lockOut ? "lock-out" : "key rotation"}) is still open — '
          'a second one starts only after it ended (D-109). Nothing started.');
      return false;
    }
    final remaining = [
      for (final r in _devices.values)
        if (r.deviceId != lockOutDeviceId) r
    ];
    if (lockOutDeviceId != null && remaining.length == _devices.length) {
      _log.warn('§14.4 lock-out: ${lockOutDeviceId.substring(0, 8)} is not in '
          'this identity\'s set — nothing started.');
      return false;
    }
    final required = coSignRequired(
        lockOut: lockOutDeviceId != null, remaining: remaining.length);
    final keys = await _emergencyKeysNew();
    if (keys == null) return false;
    final rotHash = _emergencyRotationHash(keys);

    final nodeIds = <Uint8List>[];
    Uint8List? changeHash;
    int? seq;
    if (lockOutDeviceId != null) {
      for (final r in remaining) {
        final id = _coSignNodeIdOf(r);
        if (id == null) {
          _log.error('§14.4 lock-out: the set names no device signing key for '
              'the remaining device ${r.deviceId.substring(0, 8)} (§14.9.1) — '
              'its countersignature could not be checked and the shrink proof '
              'not built. Nothing started, nothing rotated.');
          return false;
        }
        nodeIds.add(id);
      }
      seq = _nextDeviceSetSeq();
      changeHash = computeDeviceSetChangeHash(
          userId: Uint8List.fromList(identity.userId),
          newDeviceNodeIds: nodeIds,
          newSeq: seq);
    }

    final id = roundId ?? SodiumFFI().randomBytes(16);
    final round = CoSignRound(
      roundId: bytesToHex(id),
      lockOutDeviceId: lockOutDeviceId,
      remaining: [for (final r in remaining) r.deviceId],
      remainingNodeIds: [for (final n in nodeIds) bytesToHex(n)],
      required: required,
      rotationHashHex: bytesToHex(rotHash),
      changeHashHex: changeHash == null ? null : bytesToHex(changeHash),
      changeSeq: seq,
      keys: keys,
      reason: reason.name,
      askPreviousDayValues: askPreviousDayValues,
      startedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    final own = _ownApprovalToken(rotHash);
    final ownChange = changeHash == null ? null : _ownApprovalToken(changeHash);
    if (own != null) {
      round.approvals[bytesToHex(own.deviceNodeId)] = {
        't': bytesToHex(own.toProto().writeToBuffer()),
        if (ownChange != null)
          'c': bytesToHex(ownChange.toProto().writeToBuffer()),
      };
    }
    _coSignPut(round);
    _log.info('§14.5 co-signing: round ${round.roundId.substring(0, 8)} '
        '(${round.lockOut ? "lock-out of ${lockOutDeviceId!.substring(0, 8)}" : "key rotation"}) '
        '— ${round.approvals.length} of $required approval(s), '
        '${remaining.length} remaining device(s) (§14.8)');
    if (round.quorumMet) return _coSignFinish(round);

    final body = _coSignRequestBody(round);
    var asked = 0;
    for (final r in remaining) {
      if (r.isThisDevice || r.deviceId.length != 32) continue;
      _sendTwinSync(proto.TwinSyncType.ROTATION_APPROVAL_REQUEST, body,
          targetDeviceId: hexToBytes(r.deviceId));
      asked++;
    }
    _log.info('§14.5 co-signing: Type 12 (${body.length} B) to $asked own '
        'device(s) — nothing rotates before the quorum (no clock)');
    onStateChanged?.call();
    return false;
  }

  /// The Type 12 of [round] — the request the other own devices are asked,
  /// or, with [withdrawn], the same request marked withdrawn (§14.8).
  Uint8List _coSignRequestBody(CoSignRound round, {bool withdrawn = false}) {
    final keys = round.keys;
    final request = proto.RotationApprovalRequestPayload()
      ..rotationHash = hexToBytes(round.rotationHashHex)
      ..newEd25519Pk = keys.ed25519Pk
      ..newMlDsaPk = keys.mlDsaPk
      ..newX25519Pk = keys.x25519Pk
      ..newMlKemPk = keys.mlKemPk
      ..approvalKind = round.lockOut
          ? proto.ApprovalKind.APPROVAL_KIND_DEVICE_SET_CHANGE
          : proto.ApprovalKind.APPROVAL_KIND_KEY_ROTATION
      ..roundId = hexToBytes(round.roundId);
    if (round.changeHashHex != null) {
      request
        ..changeHash = hexToBytes(round.changeHashHex!)
        ..changeSeq = round.changeSeq!
        ..lockedOutDeviceId = hexToBytes(round.lockOutDeviceId!);
      request.newDeviceNodeIds
          .addAll([for (final h in round.remainingNodeIds) hexToBytes(h)]);
    }
    if (withdrawn) request.withdrawn = true;
    return Uint8List.fromList(request.writeToBuffer());
  }

  /// §14.8 "A round the initiating device cancels is withdrawn": the same
  /// request, marked withdrawn, to every other remaining device that has not
  /// answered yet — those still hold it parked and show it. A device that
  /// approved or rejected holds nothing; its answer, should it arrive late,
  /// finds no open round here and counts nowhere ([_coSignResponseIn]).
  /// Sent once, on the user's cancel: no clock, nothing standing.
  void _coSignWithdraw(CoSignRound round) {
    final body = _coSignRequestBody(round, withdrawn: true);
    var told = 0;
    for (final id in round.remaining) {
      final rec = _devices[id];
      if (rec == null || rec.isThisDevice || id.length != 32) continue;
      if (round.rejectedBy.contains(id)) continue;
      final n = _coSignNodeIdOf(rec);
      if (n != null && round.approvals.containsKey(bytesToHex(n))) continue;
      _sendTwinSync(proto.TwinSyncType.ROTATION_APPROVAL_REQUEST, body,
          targetDeviceId: hexToBytes(id));
      told++;
    }
    _log.info('§14.8 co-signing: round ${round.roundId.substring(0, 8)} '
        'withdrawn — Type 12 marked withdrawn (${body.length} B) to $told '
        'own device(s) that had not answered');
  }

  /// The open round for the interface (§14.9.2 "Quorum: Confirmation from 2
  /// devices needed — 1 of 2 given"), `null` without one: `lockOut`, the
  /// locked-out `deviceIdHex`/`deviceName`, `have`/`need` (distinct devices),
  /// the names of the devices not yet heard from (`missing`), the ones that
  /// rejected (`rejected`), and whether the quorum is out of reach.
  Map<String, dynamic>? get coSignRoundState {
    final r = coSignRound;
    if (r == null) return null;
    String name(String id) => _devices[id]?.deviceName ?? id.substring(0, 8);
    final heard = <String>{...r.rejectedBy};
    for (final id in r.remaining) {
      final rec = _devices[id];
      final n = rec == null ? null : _coSignNodeIdOf(rec);
      if (n != null && r.approvals.containsKey(bytesToHex(n))) heard.add(id);
    }
    return {
      'roundId': r.roundId,
      'lockOut': r.lockOut,
      if (r.lockOut) 'deviceIdHex': r.lockOutDeviceId,
      if (r.lockOut) 'deviceName': name(r.lockOutDeviceId!),
      'have': r.approvals.length,
      'need': r.required,
      'missing': [
        for (final id in r.remaining)
          if (!heard.contains(id)) name(id)
      ],
      'rejected': [for (final id in r.rejectedBy) name(id)],
      'unreachable': r.unreachable,
      'startedAtMs': r.startedAtMs,
    };
  }

  /// The user cancels the round of every identity of this device (one user
  /// action started them together). Returns how many were open.
  int coSignCancelAll() {
    final p = myceliumMailbox;
    final all = p == null ? [this] : servicesOnHost(p.host, this);
    var n = 0;
    for (final s in all) {
      if (s.coSignCancel()) n++;
    }
    return n;
  }

  /// The user cancels the round this identity started: nothing rotates, the
  /// new keys are dropped, and the request is withdrawn on the other own
  /// devices (§14.8). Returns whether a round was open.
  bool coSignCancel() {
    final r = coSignRound;
    if (r == null) return false;
    _coSignPut(null);
    _log.warn('§14.5 co-signing: round ${r.roundId.substring(0, 8)} cancelled '
        'by the user — ${r.approvals.length} of ${r.required} approval(s); '
        'nothing rotated, the new keys are dropped');
    _coSignWithdraw(r);
    onStateChanged?.call();
    return true;
  }

  /// Type 13 from the own device [from] (its DeviceID): a countersignature
  /// or a rejection of the open round.
  void _coSignResponseIn(List<int> payload, Uint8List from) {
    final round = coSignRound;
    final fromHex = bytesToHex(from);
    final proto.RotationApprovalResponsePayload resp;
    try {
      resp = proto.RotationApprovalResponsePayload.fromBuffer(payload);
    } on Object catch (e) {
      _log.warn('§14.5 Type 13 from ${fromHex.substring(0, 8)}: not readable '
          '— $e');
      return;
    }
    final hash = resp.rotationHash.isNotEmpty
        ? bytesToHex(Uint8List.fromList(resp.rotationHash))
        : (resp.hasToken()
            ? bytesToHex(Uint8List.fromList(resp.token.rotationHash))
            : '');
    if (round == null || hash != round.rotationHashHex) {
      _log.info('§14.5 Type 13 from ${fromHex.substring(0, 8)}: no open round '
          'for it here (ended or cancelled) — ignored');
      return;
    }
    final rec = _devices[fromHex];
    if (rec == null || rec.isThisDevice || !round.remaining.contains(fromHex)) {
      _log.warn('§14.5 Type 13 from ${fromHex.substring(0, 8)}: not a remaining '
          'device of the round — ignored');
      return;
    }
    if (resp.rejected) {
      round.rejectedBy.add(fromHex);
      _coSignPut(round);
      _log.warn('§14.5 co-signing: device ${fromHex.substring(0, 8)} REJECTED '
          'round ${round.roundId.substring(0, 8)} — '
          '${round.unreachable ? "the quorum can no longer be reached, nothing rotates" : "the round stays open"}');
      onStateChanged?.call();
      return;
    }
    final nodeId = _coSignNodeIdOf(rec);
    final ed = rec.deviceSigEd25519Hex, dsa = rec.deviceSigMlDsaHex;
    if (nodeId == null || ed == null || dsa == null || !resp.hasToken()) {
      _log.warn('§14.5 Type 13 from ${fromHex.substring(0, 8)}: no token, or '
          'the set names no device signing key for it — not counted');
      return;
    }
    bool good(proto.RotationApprovalToken p, String hashHex) {
      final t = RotationApprovalToken.fromProto(p);
      return bytesToHex(t.deviceNodeId) == bytesToHex(nodeId) &&
          bytesToHex(t.rotationHash) == hashHex &&
          t.verify(hexToBytes(ed), hexToBytes(dsa));
    }

    if (!good(resp.token, round.rotationHashHex) ||
        (round.lockOut &&
            (!resp.hasChangeToken() ||
                !good(resp.changeToken, round.changeHashHex!)))) {
      _log.warn('§14.5 Type 13 from ${fromHex.substring(0, 8)}: a token does '
          'not verify against the device signing keys of the set — not '
          'counted');
      return;
    }
    final key = bytesToHex(nodeId);
    if (round.approvals.containsKey(key)) {
      _log.info('§14.5 Type 13 from ${fromHex.substring(0, 8)}: this device '
          'approved already — counted once (§14.8)');
      return;
    }
    round.approvals[key] = {
      't': bytesToHex(resp.token.writeToBuffer()),
      if (round.lockOut) 'c': bytesToHex(resp.changeToken.writeToBuffer()),
    };
    _coSignPut(round);
    _log.info('§14.5 co-signing: approval of ${fromHex.substring(0, 8)} — '
        '${round.approvals.length} of ${round.required} (round '
        '${round.roundId.substring(0, 8)})');
    onStateChanged?.call();
    if (round.quorumMet) unawaited(_coSignFinish(round));
  }

  /// The quorum is reached: the lock-out takes effect and the keys change
  /// with every countersignature collected (§14.4, §14.5).
  Future<bool> _coSignFinish(CoSignRound round) async {
    _coSignPut(null);
    final reason = KeyPackageReason.values
            .where((r) => r.name == round.reason)
            .firstOrNull ??
        KeyPackageReason.emergency;
    _log.info('§14.5 co-signing: quorum reached in round '
        '${round.roundId.substring(0, 8)} (${round.approvals.length} of '
        '${round.required}) — ${round.lockOut ? "the lock-out takes effect" : "the keys change"}');
    if (!round.lockOut) {
      return _emergencyApply(round.keys,
          askPreviousDayValues: round.askPreviousDayValues,
          reason: reason,
          tokens: round.tokens('t'),
          packagesOnlyTo: round.remaining);
    }
    final out = round.lockOutDeviceId!;
    final device = _devices[out];
    if (device != null) await _lockOutTakeEffect(device, round);
    final ok = await _emergencyApply(round.keys,
        askPreviousDayValues: round.askPreviousDayValues,
        reason: KeyPackageReason.lockout,
        tokens: round.tokens('t'),
        remainingNodeIds: [for (final h in round.remainingNodeIds) hexToBytes(h)],
        packagesOnlyTo: round.remaining,
        announceSet: false);
    _announceDeviceSetToContacts(
        occasion: 'device lock-out',
        seq: round.changeSeq,
        approvals: round.tokens('c'));
    return ok;
  }

  // ── The approving device ───────────────────────────────────────────────

  /// Loads the parked requests of this identity (they survive a restart).
  void _coSignWaitLoad() {
    try {
      for (final e in store.loadArea(CleonaService._areaCoSignWait).entries) {
        final p = _PendingRotationApproval.fromJson(e.value);
        if (p != null) _pendingRotationApprovals[e.key] = p;
      }
    } on Object catch (e) {
      _log.warn('§14.5 co-signing: parked requests not readable — $e');
    }
    _coSignWithdrawnPrune();
  }

  void _coSignWaitPut(String hashHex, _PendingRotationApproval? p) {
    try {
      if (p == null) {
        store.removeEntry(CleonaService._areaCoSignWait, hashHex);
      } else {
        store.putEntry(CleonaService._areaCoSignWait, hashHex, p.toJson());
      }
    } on Object catch (e) {
      _log.warn('§14.5 co-signing: parked request not written — $e');
    }
  }

  /// §14.8: the device [from] withdraws the request [hashHex] — checked like
  /// the request itself (own line, own signing keys, a device of the own
  /// set, both hashes recomputed). Only the device that asked may withdraw
  /// it: a withdrawal of another device's parked request changes nothing.
  /// The parked request is dropped from the store, the withdrawal is kept
  /// (a request arriving after it, or after a restart, is not shown), and an
  /// approval of it can no longer be given ([approveRotation] finds nothing).
  void _coSignWithdrawnIn(String hashHex, Uint8List from) {
    final fromHex = bytesToHex(from);
    final parked = _pendingRotationApprovals[hashHex];
    if (parked != null && bytesToHex(parked.requestingDeviceId) != fromHex) {
      _log.warn('§14.8 withdrawal of ${hashHex.substring(0, 8)} from device '
          '${fromHex.substring(0, 8)}, but device '
          '${CleonaService._hexShort(parked.requestingDeviceId)} asked it — '
          'only the initiating device withdraws a round. Ignored.');
      return;
    }
    try {
      _coSignWithdrawnPrune();
      store.putEntry(CleonaService._areaCoSignWithdrawn, hashHex, {
        'from': fromHex,
        if (parked?.roundId != null) 'round': parked!.roundId,
        'at': DateTime.now().millisecondsSinceEpoch,
      });
    } on Object catch (e) {
      _log.warn('§14.8 co-signing: withdrawal not written — $e');
    }
    if (parked != null) {
      _pendingRotationApprovals.remove(hashHex);
      _coSignWaitPut(hashHex, null);
    }
    _log.info('§14.8 co-signing: request ${hashHex.substring(0, 8)} withdrawn '
        'by device ${fromHex.substring(0, 8)} — '
        '${parked != null ? "dropped, no longer shown" : "nothing parked here; kept so it is not shown later"}');
    onStateChanged?.call();
  }

  /// Drops withdrawals older than the dedup window (S422, report
  /// `S422-RCA-CO-SIGN-WITHDRAWN-AUFRAEUMEN.md`): a request goes out once,
  /// only to the post box, and holders keep it 7 days (§8.2) — after that it
  /// cannot arrive any more, so its withdrawal has nothing left to hold back.
  /// No clock of its own (§5.4): run at load and before every new withdrawal,
  /// with the window of `_pruneSyncDedup`. A row without `at` (written before
  /// this field) gets one now and goes 7 days later.
  void _coSignWithdrawnPrune() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - CleonaService._syncDedupTtlMs;
    try {
      for (final e
          in store.loadArea(CleonaService._areaCoSignWithdrawn).entries) {
        final at = e.value['at'];
        if (at is! int) {
          store.putEntry(CleonaService._areaCoSignWithdrawn, e.key,
              {...e.value, 'at': now});
        } else if (at < cutoff) {
          store.removeEntry(CleonaService._areaCoSignWithdrawn, e.key);
        }
      }
    } on Object catch (e) {
      _log.warn('§14.8 co-signing: withdrawals not pruned — $e');
    }
  }

  /// Whether the device [from] withdrew the request [hashHex] (§14.8).
  bool _coSignWithdrawnBy(String hashHex, Uint8List from) {
    try {
      final w = store.entry(CleonaService._areaCoSignWithdrawn, hashHex);
      return w != null && w['from'] == bytesToHex(from);
    } on Object catch (e) {
      _log.warn('§14.8 co-signing: withdrawals not readable — $e');
      return false;
    }
  }

  /// Answers the parked request [p] of this identity (Type 13 to the device
  /// that asked): with the countersignatures of this identity's device keys,
  /// or with a rejection.
  bool _coSignAnswer(_PendingRotationApproval p, {required bool approve}) {
    final hashHex = bytesToHex(p.rotationHash);
    _pendingRotationApprovals.remove(hashHex);
    _coSignWaitPut(hashHex, null);
    final resp = proto.RotationApprovalResponsePayload()
      ..rotationHash = p.rotationHash;
    if (approve) {
      final t = _ownApprovalToken(p.rotationHash);
      final c = p.changeHash == null ? null : _ownApprovalToken(p.changeHash!);
      if (t == null || (p.changeHash != null && c == null)) {
        _log.error('§14.5 co-signing: no device signing key here — the '
            'approval of ${hashHex.substring(0, 8)} cannot be given');
        return false;
      }
      resp.token = t.toProto();
      if (c != null) resp.changeToken = c.toProto();
    } else {
      resp.rejected = true;
    }
    _sendTwinSync(proto.TwinSyncType.ROTATION_APPROVAL_RESPONSE,
        Uint8List.fromList(resp.writeToBuffer()),
        targetDeviceId: p.requestingDeviceId);
    _log.info('§14.5 Type 13 (${approve ? "approved" : "REJECTED"} by the '
        'user) for ${hashHex.substring(0, 8)} to device '
        '${CleonaService._hexShort(p.requestingDeviceId)}');
    onStateChanged?.call();
    return true;
  }

  /// One user decision for [hashHex] answers every parked request of the
  /// same round in every identity of this device (§14.4 "one approval per
  /// device counts for all identities"). Returns how many were answered.
  int _coSignDecide(String hashHex, {required bool approve}) {
    final first = _pendingRotationApprovals[hashHex];
    if (first == null) return 0;
    final round = first.roundId;
    final p = myceliumMailbox;
    final all = p == null ? [this] : servicesOnHost(p.host, this);
    var n = 0;
    for (final s in all) {
      for (final q in s._pendingRotationApprovals.values.toList()) {
        final same = identical(q, first) ||
            (round != null && round.isNotEmpty && q.roundId == round);
        if (same && s._coSignAnswer(q, approve: approve)) n++;
      }
    }
    return n;
  }
}
