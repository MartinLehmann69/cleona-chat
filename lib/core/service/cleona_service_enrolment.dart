// B-4b (D-39, D-40) — adding a further device over the 24 words, with the
// enrolment window in the recovery bundle and the approval in the Requests
// tab (V4.2 §13.0, §13.3.2, §13.3.4, §14.6.1, §14.6.2).
//
// ── THE EXISTING DEVICE ──────────────────────────────────────────────────
//
//   * [enrolmentWindowOpen] opens a 24-hour window for every identity this
//     device hosts and lays each bundle AT ONCE with the window's end
//     (§13.3.4). While open, the window asks `value_E` at the collection
//     edges and hears the enrolment call on the LAN (`enrol_window.dart`).
//   * A request becomes an entry of the Requests tab — name, platform,
//     DeviceID, time. NOTHING is handed over before the user accepts
//     (owner decision E-1 = A); there is no automatic approval.
//   * Accepting hands over the material of §14.6.2 — directly while both are
//     present, the rest in the post box — adds the device to the set,
//     announces it to the other own devices (Type 9) and shuts the window.
//     Rejecting shuts the window and tells the new device so.
//
// ── THE FRESH INSTALL ────────────────────────────────────────────────────
//
//   * From the words and without contacts it SEARCHES ONLY (D-40): the
//     identity is held (no own post collected, no search call answered),
//     the bundle is read, not deleted, and nothing is laid — an undecided
//     install never lays a bundle (it would lay an emptier, newer one over
//     the living device's).
//   * Bundle with an open window → the request (§14.6.1 step 2), then it
//     waits under its reply values. Without a window → the question whether
//     the previous device still exists (§13.0). Recovery begins only with
//     the user's choice ([enrolmentRecoverNow]) — "no bundle" is never
//     concluded automatically.
//   * The handover arrives → its files and key state are written, the
//     mailbox is opened anew from them, and it is an ordinary own device.
//
// ── THE LOCK (E7) ───────────────────────────────────────────────────────
//
// The routine KEM rotation across own devices (E7, D-40 second sentence) is
// not built in this tree. Until it is, two devices of one identity would
// drift apart at the first rotation — so the product path stays behind
// [EnrolmentGate]: the window cannot be opened, the interface says "not
// available yet". A test opens it on purpose.

part of 'cleona_service.dart';

/// The lock of the product path to two devices until E7 is merged.
class EnrolmentGate {
  /// Opened by a test, or by the environment of a lab daemon
  /// (`CLEONA_ENROLMENT_OPEN=1`); nothing else sets it.
  static bool open = Platform.environment['CLEONA_ENROLMENT_OPEN'] == '1';
}

/// §13.0 as a pure function: the phase an identity starts in. A fresh
/// install from the words without contacts searches (D-40); a phase chosen
/// or reached before a restart is kept while the case lasts; everything
/// else is an ordinary device.
EnrolmentPhase enrolmentStartPhase({
  required bool outPhrase,
  required bool hasContacts,
  EnrolmentPhase saved = EnrolmentPhase.none,
  bool settled = false,
}) {
  if (!outPhrase || hasContacts || settled) return EnrolmentPhase.none;
  return saved == EnrolmentPhase.none ? EnrolmentPhase.searching : saved;
}

/// §13.0: what a found bundle means. An open window → add; else ask.
///
/// After a rejection (§14.6.1 step 3) a window counts only from a bundle
/// laid AFTER the rejection ([bundleAtMs] > [rejectedAtMs]): closing lays
/// nothing (§13.3.4), so the bundle of the rejected window still names its
/// end for up to 24 hours (S398, lab B-4b finding B-2). Both times are on
/// the existing device's clock (`enrolRejectionBody`); a new window lays its
/// bundle at once and is therefore always younger.
EnrolmentPhase enrolmentAfterBundle(int? windowUntilMs, DateTime now,
    {int? bundleAtMs, int? rejectedAtMs}) {
  final open =
      windowUntilMs != null && windowUntilMs > now.millisecondsSinceEpoch;
  final afterRejection = rejectedAtMs == null ||
      (bundleAtMs != null && bundleAtMs > rejectedAtMs);
  return open && afterRejection
      ? EnrolmentPhase.waiting
      : EnrolmentPhase.noWindow;
}

/// The phases in which an identity is held: search only, no own post.
bool enrolmentHolds(EnrolmentPhase p) =>
    p == EnrolmentPhase.searching ||
    p == EnrolmentPhase.waiting ||
    p == EnrolmentPhase.noWindow ||
    p == EnrolmentPhase.rejected;

/// The runtime state of one identity's enrolment.
class EnrolmentRuntime {
  mycelium.EnrolWindow? window;
  mycelium.EnrolWait? wait;
  EnrolmentPhase phase = EnrolmentPhase.none;
  DateTime? windowUntil;
  DateTime? windowFrom;

  /// Requests waiting in the Requests tab, by request id (hex).
  final Map<String, ({EnrolRequest q, DateTime at})> pending = {};

  /// New device: the request it laid and the reply key pairs.
  Uint8List? requestId;
  List<({Uint8List pk, Uint8List sk})> reply = const [];
  EnrolAnswerAssembly? assembly;

  /// New device: the newest bundle found (sealed) and when it was laid —
  /// kept for the question without a window and a later explicit recovery.
  Uint8List? found;
  DateTime? foundAt;

  /// New device: when the existing device rejected the last request, in ms
  /// on the EXISTING device's clock (the time its answer carries, at least
  /// the laying time of the bundle the request was laid on). Only a bundle
  /// laid after it carries a window this device asks at (S398, B-2).
  int? rejectedAtMs;

  /// Requests answered in this run — a repeat of the same call is dropped.
  final Set<String> answered = {};

  /// The case is settled — enrolled or recovered: never searching again,
  /// even for an identity without contacts.
  bool settled = false;
}

/// Area of the enrolment state in the store of the identity.
///
/// S401 (02.10.2026): until then it lay in a file of its own next to the
/// store (`enrolment.json.enc`, under the same key as the store). It is
/// state of ONE identity like the lock-out transitions and the rotation
/// windows, which have lain in the store since S366 — and it names the
/// devices that asked to be added (owner 02.10.2026: what does not belong
/// into a file goes into the store).
///
/// The head ([kEnrolmentHeadKey]) carries the window, the phase and, on a
/// new device, its request with the reply keys and the bundle it found.
/// **Each waiting request is a row of its own**, keyed by its request id in
/// hex, written when it arrives and removed when the user decides or the
/// window is cancelled.
const String kEnrolmentArea = 'enrolment';

/// The ONE row of [kEnrolmentArea] that is not a waiting request. A request
/// id in hex has 32 characters, so this key meets none.
const String kEnrolmentHeadKey = '_';

/// The name the state had as a file. No writer is left; the name is only
/// asked for by `_stateFileIntoStore`, which empties a file an earlier
/// build of this line left in the profile.
const String _kEnrolmentFile = 'enrolment.json';

/// At most this many requests wait at once (§14.8: 5 devices per identity).
const int _kEnrolPendingAtMost = 5;

/// What an existing device hands over from the storage (§14.6.2): the key
/// state, contacts with their deletion marks, groups, channels, profile,
/// the standing invitations and the device set. NOT: histories, local UI
/// settings, the bundle state (each device lays its own).
const List<String> _kHandoverAreas = [
  IdentityContext.areaKeys,
  IdentityContext.areaRotationChain,
  'contacts',
  'contacts_deleted',
  'groups',
  'channels',
  CleonaService._areaProfile,
  InviteStore.area,
  CleonaService._areaDevices,
];

/// What it hands over from the delivery layer's memory: own post box with
/// its previous generation and day-key seed, every contact's full record
/// (address with chain, `s_AB`, day keys, fixed neighbours, card addresses),
/// the invitations with their waiting requests, the group pairs.
const List<String> _kHandoverMemory = [
  kFileMailbox,
  kFileGroupPairs,
  kFileFirstContact,
];

extension CleonaServiceEnrolment on CleonaService {
  // ── What the interface shows ───────────────────────────────────────────

  EnrolmentView get enrolViewBuild => EnrolmentView(
        available: EnrolmentGate.open,
        phase: _enrol.phase,
        windowUntil: _enrol.window?.until,
        bundleAt: _enrol.foundAt,
        requests: [
          for (final e in _enrol.pending.entries)
            EnrolmentRequestView(
              requestIdHex: e.key,
              deviceName: e.value.q.deviceName,
              platform: e.value.q.platform,
              deviceIdHex: e.value.q.deviceIdHex,
              receivedAt: e.value.at,
            )
        ],
      );

  // ── At the mailbox ─────────────────────────────────────────────────────

  /// Called by `_recoveryBundleAttach` with the fresh [box]. Decides the
  /// phase (§13.0, D-40) and hangs the window on the node.
  void _enrolmentAttach(mycelium.Mailbox p, mycelium.BundleBox box,
      Uint8List recoveryKeyI) {
    _enrol.window?.detach();
    _enrol.wait?.detach();
    _enrol.wait = null;
    _enrolmentLoad();
    _enrol.phase = enrolmentStartPhase(
        outPhrase: identity.restoredFromPhrase,
        hasContacts: _contacts.isNotEmpty || _deletedContacts.isNotEmpty,
        saved: _enrol.phase,
        settled: _enrol.settled);
    final w = mycelium.EnrolWindow(p.node,
        keyFor: (d) => enrolBoxKey(recoveryKeyI, d),
        now: () => recoveryBundleClock(),
        report: _log.info,
        onRequests: _enrolRequestsIn)
      ..attach();
    final until = _enrol.windowUntil;
    if (until != null && until.isAfter(recoveryBundleClock())) {
      w.open(until, from: _enrol.windowFrom);
    } else {
      _enrol.windowUntil = null;
    }
    _enrol.window = w;
    _enrolmentApply(p, box);
    _log.info('Enrolment (§13.0): phase ${_enrol.phase.name}'
        '${w.isOpen ? ", window open until ${w.until!.toUtc().toIso8601String()}" : ""}');
  }

  /// Puts the phase into effect at the node and the bundle box.
  void _enrolmentApply(mycelium.Mailbox p, mycelium.BundleBox box) {
    final held = enrolmentHolds(_enrol.phase);
    p.node.postHold(p.identity, held);
    box.readOnly = held;
    box.seeking = _enrol.phase == EnrolmentPhase.searching ||
        _enrol.phase == EnrolmentPhase.noWindow ||
        _enrol.phase == EnrolmentPhase.rejected ||
        _enrol.phase == EnrolmentPhase.recovering;
    if (_enrol.phase == EnrolmentPhase.waiting && _enrol.wait == null) {
      _enrolWaitAttach(p);
    }
  }

  // ── The existing device ────────────────────────────────────────────────

  /// Opens the enrolment window for every identity this device hosts
  /// (§14.6.1 step 1, D-19). `false` while the lock is shut (E7) or without
  /// a mailbox. Every bundle is laid at once with the window's end.
  Future<bool> enrolOpenAll() async {
    if (!EnrolmentGate.open) {
      _log.info('Enrolment: window NOT opened — not available until the '
          'routine KEM rotation across own devices (E7) is built');
      return false;
    }
    final p = myceliumMailbox;
    if (p == null) return false;
    var opened = 0;
    for (final s in servicesOnHost(p.host, this)) {
      if (s._enrolWindowOpenHere()) opened++;
    }
    return opened > 0;
  }

  bool _enrolWindowOpenHere() {
    final w = _enrol.window;
    if (w == null || enrolmentHolds(_enrol.phase)) return false;
    final now = recoveryBundleClock();
    final until = now.add(kEnrolWindow);
    w.open(until, from: now);
    _enrol.windowUntil = until;
    _enrol.windowFrom = now;
    _enrolmentSave();
    // §13.3.4: opening places the bundle at once, outside the cadence.
    final box = recoveryBox;
    if (box != null) unawaited(box.depositSoon());
    onStateChanged?.call();
    return true;
  }

  /// Shuts the window of every hosted identity. Nothing is laid: the end
  /// time is in the bundle, the next routine renewal omits the field.
  Future<bool> enrolCancelAll() async {
    final p = myceliumMailbox;
    if (p == null) return false;
    for (final s in servicesOnHost(p.host, this)) {
      s._enrolWindowShut(dropRequests: true);
    }
    return true;
  }

  void _enrolWindowShut({bool dropRequests = false}) {
    _enrol.window?.close();
    _enrol.windowUntil = null;
    _enrol.windowFrom = null;
    if (dropRequests) {
      final dropped = _enrol.pending.keys.toList();
      _enrol.pending.clear();
      for (final id in dropped) {
        _enrolPendingSave(id);
      }
    }
    _enrolmentSave();
    onStateChanged?.call();
  }

  /// What the window brought: requests are opened and become entries of
  /// the Requests tab — nothing else happens without the user.
  void _enrolRequestsIn(List<Uint8List> sealed, CardAddress? from) {
    final rk = _enrolRecoveryKey();
    if (rk == null) return;
    var fresh = 0;
    for (final s in sealed) {
      final q = openEnrolRequest(rk, s);
      if (q == null) {
        _log.warn('Enrolment: a piece under value_E does not open as a '
            'request of these words — dropped');
        continue;
      }
      final id = q.requestIdHex;
      if (q.deviceIdHex == _localDeviceId ||
          _enrol.pending.containsKey(id) ||
          _enrol.answered.contains(id) ||
          _enrol.pending.length >= _kEnrolPendingAtMost) {
        continue;
      }
      _enrol.pending[id] = (q: q, at: DateTime.now());
      _enrolPendingSave(id);
      fresh++;
      _log.event('Enrolment: request of "${q.deviceName}" (${q.platform}, '
          'device ${q.deviceIdHex.substring(0, 8)}) waits in the Requests tab'
          '${from == null ? "" : " (LAN call)"}');
    }
    // Each fresh request wrote its own row above; the head did not change.
    if (fresh > 0) onStateChanged?.call();
  }

  /// The user's decision in the Requests tab (§14.6.1 step 3, E-1 = A).
  /// `false` for an unknown request.
  Future<bool> enrolDecide(String requestIdHex, bool accept) async {
    final e = _enrol.pending.remove(requestIdHex);
    if (e == null) return false;
    _enrolPendingSave(requestIdHex);
    _enrol.answered.add(requestIdHex);
    final q = e.q;
    if (!accept) {
      // The rejection carries its time on this device's clock — the clock
      // of the bundles (S398, B-2).
      await _enrolAnswer(q, EnrolAnswerType.rejected,
          enrolRejectionBody(recoveryBundleClock().millisecondsSinceEpoch));
      _enrolWindowShut();
      _log.event('Enrolment: request of "${q.deviceName}" REJECTED — the '
          'window is shut, the new device is told');
      return true;
    }
    // The new device joins the set BEFORE the handover is built: the
    // device list it receives already names it.
    final now = DateTime.now();
    _devices[q.deviceIdHex] = DeviceRecord(
      deviceId: q.deviceIdHex,
      deviceName: q.deviceName,
      platform: q.platform,
      firstSeen: now,
      lastSeen: now,
    );
    _saveDevices();
    final body = enrolBodyOf(_enrolHandoverBuild());
    final placed = await _enrolAnswer(q, EnrolAnswerType.handover, body);
    _enrolAnnounce(q);
    _notifyDevicesChanged();
    // §14.6.1 step 5, §14.5 path 2: the grown set to the contacts. The
    // announcement proves only a set whose device signing keys this node
    // holds; it names itself in the log when it stays silent.
    _announceDeviceSetToContacts(occasion: 'Device enrolled');
    _enrolWindowShut();
    _log.event('Enrolment: "${q.deviceName}" ACCEPTED — ${body.length} B '
        'handed over ($placed), Type 9 to the other own devices');
    return true;
  }

  /// §14.6.2 — what the seed does not give. The histories stay (§14.6.3:
  /// a full reconciliation is the user's decision).
  Map<String, dynamic> _enrolHandoverBuild() {
    final areas = <String, dynamic>{};
    for (final a in _kHandoverAreas) {
      areas[a] = store.loadArea(a);
    }
    final memory = <String, String>{};
    final d = mailboxDetailsFor(this);
    final enc = FileEncryption(baseDir: d.directory.path, key: d.key);
    for (final name in _kHandoverMemory) {
      final bytes = enc.readBinaryFile('${d.directory.path}/$name');
      if (bytes != null) memory[name] = base64Encode(bytes);
    }
    return {'v': 1, 'areas': areas, 'memory': memory};
  }

  /// Sends the answer to the new device: directly to its addresses while
  /// both are present, the unacknowledged rest in the post box under its
  /// reply value of today, named first at the holders it asks (§8.2).
  /// Returns a line for the log.
  Future<String> _enrolAnswer(
      EnrolRequest q, EnrolAnswerType type, Uint8List body) async {
    final p = myceliumMailbox;
    if (p == null) return 'no mailbox';
    final pieces = sealEnrolAnswer(
        requestId: q.requestId,
        type: type,
        body: body,
        x25519Pk: q.deviceX25519Pk,
        mlKemPk: q.deviceMlKemPk);
    final age = utcDay(recoveryBundleClock()) -
        utcDay(DateTime.fromMillisecondsSinceEpoch(q.atMs, isUtc: true));
    final i = age < 0 ? 0 : (age >= q.replyPks.length ? q.replyPks.length - 1 : age);
    final value = dayValue(q.replyPks[i]);
    var rest = pieces;
    for (final a in q.addresses) {
      if (rest.isEmpty) break;
      rest = await p.node.enrolDirect(CardAddress(a.ip, a.port), value, rest);
    }
    final named = [for (final h in q.holders) CardAddress(h.ip, h.port)];
    var boxed = 0;
    for (final piece in rest) {
      final (done, _) = await p.node.depositNamed(piece, value, named);
      if (done) boxed++;
    }
    return '${pieces.length - rest.length} of ${pieces.length} piece(s) '
        'directly, $boxed in the post box';
  }

  /// Type 9 (§14.7): the new device to every OTHER own device — the new one
  /// learns the set from the handover.
  void _enrolAnnounce(EnrolRequest q) {
    final record = proto.DeviceRecord()
      ..deviceId = q.deviceId
      ..deviceName = q.deviceName
      ..platform = CleonaService._platformToProto(q.platform)
      ..firstSeen = Int64(DateTime.now().millisecondsSinceEpoch)
      ..lastSeen = Int64(DateTime.now().millisecondsSinceEpoch);
    for (final other in _devices.values) {
      if (other.isThisDevice || other.deviceId == q.deviceIdHex) continue;
      final to = hexToBytes(other.deviceId);
      if (to.length != 16) continue; // a DeviceID (§14.1)
      _sendTwinSync(proto.TwinSyncType.DEVICE_ANNOUNCE,
          Uint8List.fromList(record.writeToBuffer()),
          targetDeviceId: to);
    }
  }

  // ── The fresh install ──────────────────────────────────────────────────

  /// A bundle was found while this install searches (§13.0): with an open
  /// window it asks to be added; without, the user is asked. Nothing from
  /// the bundle is taken into use — only the window's end and the fixed
  /// neighbours to lay the request at. The holders answer one after the
  /// other: an older copy never replaces a newer one already found
  /// (§13.3.2 "the newest of several copies wins").
  void _enrolBundleFound(RecoveryBundleContent best, Uint8List sealed) {
    final p = myceliumMailbox;
    if (p == null) return;
    final at = _enrol.foundAt;
    if (_enrol.found != null &&
        at != null &&
        best.depositedAtMs < at.millisecondsSinceEpoch) {
      return;
    }
    _enrol.found = sealed;
    _enrol.foundAt = DateTime.fromMillisecondsSinceEpoch(best.depositedAtMs);
    final now = recoveryBundleClock();
    final next = enrolmentAfterBundle(best.enrolmentOpenUntilMs, now,
        bundleAtMs: best.depositedAtMs, rejectedAtMs: _enrol.rejectedAtMs);
    // The bundle names a running window, but it was laid before the
    // rejection: that window ended with it (S398, B-2).
    final endedByRejection = next != EnrolmentPhase.waiting &&
        enrolmentAfterBundle(best.enrolmentOpenUntilMs, now) ==
            EnrolmentPhase.waiting;
    if (next == EnrolmentPhase.waiting) {
      _enrolRequestLay(p, best);
    } else if (_enrol.phase != EnrolmentPhase.rejected) {
      _enrol.phase = EnrolmentPhase.noWindow;
    }
    final box = recoveryBox;
    if (box != null) _enrolmentApply(p, box);
    _enrolmentSave();
    final String what;
    if (next == EnrolmentPhase.waiting) {
      what = 'window open: request laid, waiting for the approval';
    } else if (endedByRejection) {
      what = 'its window ended with the rejection of '
          '${DateTime.fromMillisecondsSinceEpoch(_enrol.rejectedAtMs!).toUtc().toIso8601String()} '
          '(existing device\'s clock) — no new request';
    } else {
      what = 'no window: the user is asked whether the previous device '
          'still exists';
    }
    _log.event('Enrolment (§13.0): bundle of '
        '${_enrol.foundAt!.toUtc().toIso8601String()} found — $what');
    onStateChanged?.call();
  }

  void _enrolRequestLay(mycelium.Mailbox p, RecoveryBundleContent best) {
    final rk = _enrolRecoveryKey();
    final kem = identity.deviceKeys?.kem;
    if (rk == null || kem == null) {
      _log.error('Enrolment: no request — ${rk == null ? "no recovery key" : "no device KEM keys"}');
      return;
    }
    final na = SodiumFFI();
    final now = recoveryBundleClock();
    _enrol.requestId = na.randomBytes(16);
    _enrol.reply = [
      for (var i = 0; i < kEnrolReplyKeys; i++)
        (() {
          final k = na.generateEd25519KeyPair();
          return (pk: k.publicKey, sk: k.secretKey);
        })()
    ];
    _enrol.assembly = null;
    BundleNeighbour held(CardAddress c) => (ip: c.address, port: c.port);
    final q = EnrolRequest(
      requestId: _enrol.requestId!,
      deviceId: hexToBytes(_localDeviceId),
      deviceName: _devices[_localDeviceId]?.deviceName ??
          localDeviceName(CleonaService._detectPlatform()),
      platform: CleonaService._detectPlatform(),
      deviceX25519Pk: kem.x25519PublicKey,
      deviceMlKemPk: kem.mlKemPublicKey,
      replyPks: [for (final r in _enrol.reply) r.pk],
      addresses: [for (final c in cardOwnAddresses(p.node).take(4)) held(c)],
      holders: [
        for (final n in p.node.collectNeighbours.take(3))
          (ip: Uint8List.fromList(n.$1.rawAddress), port: n.$2)
      ],
      atMs: now.millisecondsSinceEpoch,
    );
    final sealed = sealEnrolRequest(rk, q);
    final value = dayValue(enrolBoxKey(rk, utcDay(now)).pk);
    _enrol.phase = EnrolmentPhase.waiting;
    _enrolWaitAttach(p);
    final named = [
      for (final n in best.ownNeighbours) CardAddress(n.ip, n.port)
    ];
    unawaited(_enrol.wait!.request(sealed, value, named: named));
  }

  void _enrolWaitAttach(mycelium.Mailbox p) {
    if (_enrol.reply.isEmpty) {
      // A restart lost nothing but the running wait: the pairs are in the
      // head of the stored state. Without them the request cannot be
      // answered — search on.
      _enrol.phase = EnrolmentPhase.searching;
      return;
    }
    _enrol.wait?.detach();
    _enrol.wait = mycelium.EnrolWait(p.node,
        pairs: _enrol.reply,
        now: () => recoveryBundleClock(),
        report: _log.info,
        onPieces: _enrolPiecesIn)
      ..attach();
  }

  /// Pieces under the reply values: opened with the device KEM keys and put
  /// together; a complete answer is taken.
  void _enrolPiecesIn(List<Uint8List> pieces) {
    final kem = identity.deviceKeys?.kem;
    final id = _enrol.requestId;
    if (kem == null || id == null || _enrol.phase != EnrolmentPhase.waiting) {
      return;
    }
    final a = _enrol.assembly ??= EnrolAnswerAssembly(id);
    for (final piece in pieces) {
      final opened =
          openEnrolAnswer(piece, kem.x25519PrivateKey, kem.mlKemPrivateKey);
      if (opened == null) continue;
      final done = a.add(opened);
      if (done == null) continue;
      if (done.type == EnrolAnswerType.rejected) {
        _enrolRejected(done.body);
      } else {
        _enrolTakeOver(done.body);
      }
      return;
    }
    _log.info('Enrolment: answer ${a.have} of ${a.count ?? "?"} piece(s)');
  }

  void _enrolRejected(Uint8List body) {
    _enrol.wait?.detach();
    _enrol.wait = null;
    _enrol.phase = EnrolmentPhase.rejected;
    _enrol.assembly = null;
    // S398, B-2: from now on only a bundle laid after the rejection carries
    // a window. Both candidates are on the existing device's clock: the time
    // the answer carries, and — as the floor — when the bundle this request
    // was laid on was laid (a rejection is never older than that).
    var at = enrolRejectionAt(body);
    final laidOn = _enrol.foundAt?.millisecondsSinceEpoch;
    if (laidOn != null && (at == null || laidOn > at)) at = laidOn;
    final before = _enrol.rejectedAtMs;
    if (at != null && (before == null || at > before)) _enrol.rejectedAtMs = at;
    final p = myceliumMailbox;
    final box = recoveryBox;
    if (p != null && box != null) _enrolmentApply(p, box);
    _enrolmentSave();
    _log.event('Enrolment: the existing device REJECTED the request — '
        'searching on for a new window');
    onStateChanged?.call();
  }

  /// §14.6.2: the handover is taken over — key state, storage areas and
  /// the delivery layer's memory written, then read back; the mailbox is
  /// opened anew from its files. Refused (named) when it does not continue
  /// this identity.
  void _enrolTakeOver(Uint8List body) {
    final j = enrolBodyRead(body);
    final p = myceliumMailbox;
    if (j == null || j['v'] != 1 || p == null) {
      _log.error('Enrolment: handover unreadable — not taken over');
      return;
    }
    final areas = (j['areas'] as Map).cast<String, dynamic>();
    Map<String, Map<String, dynamic>> area(String n) => {
          for (final e in ((areas[n] as Map?) ?? const {}).entries)
            e.key as String: (e.value as Map).cast<String, dynamic>()
        };
    final keys = area(IdentityContext.areaKeys)[IdentityContext.keyKeys];
    if (keys == null || !_enrolContinues(keys, area(IdentityContext.areaRotationChain))) {
      _log.error('Enrolment: the handed-over keys do not continue this '
          'identity (§4.5.4) — NOT taken over');
      return;
    }
    // 1. the delivery layer's memory, under THIS device's mailbox key.
    final d = mailboxDetailsFor(this);
    final enc = FileEncryption(baseDir: d.directory.path, key: d.key);
    final memory = (j['memory'] as Map).cast<String, dynamic>();
    for (final e in memory.entries) {
      if (!_kHandoverMemory.contains(e.key)) continue;
      enc.writeBinaryFile(
          '${d.directory.path}/${e.key}', base64Decode(e.value as String));
    }
    // 2. the storage areas; this device stays this device in the set.
    for (final n in _kHandoverAreas) {
      if (n == IdentityContext.areaKeys ||
          n == IdentityContext.areaRotationChain) {
        continue;
      }
      final rows = area(n);
      if (n == CleonaService._areaDevices) {
        for (final r in rows.values) {
          r['isThisDevice'] = r['deviceId'] == _localDeviceId;
        }
      }
      store.replaceArea(n, rows);
    }
    identity.keysTakeOver(keys, area(IdentityContext.areaRotationChain));
    // 3. read back what the service keeps in memory.
    _contacts.clear();
    _deletedContacts.clear();
    _loadContacts();
    _groups.clear();
    _loadGroups();
    _channels.clear();
    _loadChannels();
    _loadProfilePicture();
    _loadProfileDescription();
    _loadProfileUpdateState();
    _devices.clear();
    _loadDevices();
    _inviteLedgerCached = null;
    // 4. an ordinary own device from here on.
    _enrol.wait?.detach();
    _enrol.wait = null;
    _enrol.phase = EnrolmentPhase.none;
    _enrol.found = null;
    _enrol.rejectedAtMs = null;
    _enrol.requestId = null;
    _enrol.reply = const [];
    _enrol.settled = true;
    identity.restoredFromPhrase = false;
    _enrolmentSave();
    final host = p.host;
    myceliumDetach();
    final fresh = host.reopen(p, mailboxDetailsFor(this));
    myceliumAttach(fresh);
    _sendTwinAnnounce();
    _log.event('Enrolment: handover taken over (§14.6.2) — '
        '${_contacts.length} contact(s), ${_groups.length} group(s), '
        '${_devices.length} own device(s); an ordinary own device now');
    onStateChanged?.call();
  }

  /// Whether a handed-over key row continues THIS identity: without a
  /// rotation the words' own signing key, after one a chain from this
  /// UserID to the row's keys (§4.5.4, D-33).
  bool _enrolContinues(
      Map<String, dynamic> keys, Map<String, Map<String, dynamic>> chain) {
    try {
      final ed = hexToBytes(keys['ed25519_pk'] as String);
      final dsa = hexToBytes(keys['ml_dsa_pk'] as String);
      if (chain.isEmpty) {
        return constantTimeEquals(ed, identity.ed25519PublicKey) &&
            constantTimeEquals(dsa, identity.mlDsaPublicKey);
      }
      final links = [
        for (final i in (chain.keys.map(int.parse).toList()..sort()))
          StoredRotationLink.fromJson(chain['$i']!)
      ];
      return RotationChain.fromStored(links)
          .holds(identity.userId, ChainKeys(ed, dsa));
    } on Object catch (e) {
      _log.warn('Enrolment: key row not checkable — $e');
      return false;
    }
  }

  /// The user chose recovery explicitly (§13.0, D-40): the one way into the
  /// recovery case. A bundle already found is taken over at once;
  /// otherwise the search goes on, now collecting the own post.
  Future<bool> enrolRecover() async {
    if (!enrolmentHolds(_enrol.phase)) return false;
    final p = myceliumMailbox;
    final box = recoveryBox;
    if (p == null || box == null) return false;
    _enrol.wait?.detach();
    _enrol.wait = null;
    _enrol.phase = EnrolmentPhase.recovering;
    _enrolmentApply(p, box);
    _enrolmentSave();
    _log.event('Enrolment: the user chose RECOVERY (§13.0) — own post is '
        'collected from now on');
    final found = _enrol.found;
    if (found != null) {
      _recoveryBundleFound([found]);
    } else {
      unawaited(p.node.collect());
    }
    onStateChanged?.call();
    return true;
  }

  /// The recovery case ended with a bundle taken over (§13.3, E7): the
  /// identity is released and the case is settled.
  void _enrolRecoverySettled() {
    if (_enrol.phase == EnrolmentPhase.none && _enrol.settled) return;
    _enrol.phase = EnrolmentPhase.none;
    _enrol.settled = true;
    _enrol.found = null;
    final p = myceliumMailbox;
    if (p != null) p.node.postHold(p.identity, false);
    recoveryBox?.readOnly = false;
    _enrolmentSave();
  }

  // ── The state in the store ─────────────────────────────────────────────

  Uint8List? _enrolRecoveryKey() {
    final seed = identity.masterSeed;
    final index = identity.hdIndex;
    return seed == null || index == null ? null : recoveryKey(seed, index);
  }

  /// Reads the state from the store. THE ONE READER: the view of the
  /// interface ([enrolViewBuild]), the phase at start and the waiting
  /// requests all come from here. No place asks for a file.
  void _enrolmentLoad() {
    _stateFileIntoStore(
        '$profileDir/$_kEnrolmentFile', kEnrolmentArea, _enrolRowsOfFile);
    final Map<String, Map<String, dynamic>> rows;
    try {
      rows = store.loadArea(kEnrolmentArea);
    } catch (e) {
      _log.warn('Enrolment: state not readable ($e) — starts empty');
      return;
    }
    final j = rows.remove(kEnrolmentHeadKey);
    final rk = _enrolRecoveryKey();
    _enrol.pending.clear();
    for (final e in rows.entries) {
      try {
        final q = rk == null
            ? null
            : EnrolRequest.read(base64Decode(e.value['q'] as String));
        if (q == null) continue;
        _enrol.pending[q.requestIdHex] = (
          q: q,
          at: DateTime.fromMillisecondsSinceEpoch(e.value['at'] as int)
        );
      } catch (err) {
        _log.warn('Enrolment: waiting request ${e.key} not readable '
            '($err) — skipped');
      }
    }
    if (j == null) return;
    _enrol.settled = j['settled'] as bool? ?? false;
    _enrol.phase = EnrolmentPhase.values.firstWhere(
        (x) => x.name == j['phase'], orElse: () => EnrolmentPhase.none);
    final u = j['windowUntil'] as int?;
    _enrol.windowUntil = u == null ? null : DateTime.fromMillisecondsSinceEpoch(u);
    final f = j['windowFrom'] as int?;
    _enrol.windowFrom = f == null ? null : DateTime.fromMillisecondsSinceEpoch(f);
    final rid = j['requestId'] as String?;
    _enrol.requestId = rid == null ? null : base64Decode(rid);
    _enrol.reply = [
      for (final s in (j['reply'] as List? ?? const []))
        (() {
          final sk = base64Decode(s as String);
          return (pk: Uint8List.fromList(sk.sublist(32)), sk: sk);
        })()
    ];
    final found = j['found'] as String?;
    _enrol.found = found == null ? null : base64Decode(found);
    final at = j['foundAt'] as int?;
    _enrol.foundAt = at == null ? null : DateTime.fromMillisecondsSinceEpoch(at);
    _enrol.rejectedAtMs = j['rejectedAtMs'] as int?;
  }

  /// Writes the head: window, phase, and on a new device its request with
  /// the reply keys and the bundle it found. The waiting requests are NOT
  /// in it — each has its own row ([_enrolPendingSave]).
  void _enrolmentSave() {
    try {
      store.putEntry(kEnrolmentArea, kEnrolmentHeadKey, {
        'phase': _enrol.phase.name,
        'settled': _enrol.settled,
        'windowUntil': _enrol.windowUntil?.millisecondsSinceEpoch,
        'windowFrom': _enrol.windowFrom?.millisecondsSinceEpoch,
        if (_enrol.requestId != null) 'requestId': base64Encode(_enrol.requestId!),
        'reply': [for (final r in _enrol.reply) base64Encode(r.sk)],
        if (_enrol.found != null) 'found': base64Encode(_enrol.found!),
        'foundAt': _enrol.foundAt?.millisecondsSinceEpoch,
        'rejectedAtMs': _enrol.rejectedAtMs,
      });
    } catch (e) {
      _log.warn('Enrolment: state not written ($e)');
    }
  }

  /// Writes EXACTLY ONE waiting request — or removes its row if it no
  /// longer waits. Nothing here writes the whole set from memory, so a
  /// failed load can never empty the area.
  void _enrolPendingSave(String requestIdHex) {
    try {
      final e = _enrol.pending[requestIdHex];
      if (e == null) {
        store.removeEntry(kEnrolmentArea, requestIdHex);
      } else {
        store.putEntry(kEnrolmentArea, requestIdHex, {
          'q': base64Encode(e.q.encode()),
          'at': e.at.millisecondsSinceEpoch,
        });
      }
    } catch (err) {
      _log.warn('Enrolment: waiting request $requestIdHex not written '
          '($err)');
    }
  }

  /// The rows of the area from the content of the former state file (the
  /// head's fields plus `pending: [{q, at}, …]`).
  Map<String, Map<String, dynamic>> _enrolRowsOfFile(Map<String, dynamic> j) {
    final head = Map<String, dynamic>.of(j)..remove('pending');
    final rows = <String, Map<String, dynamic>>{kEnrolmentHeadKey: head};
    for (final e in (j['pending'] as List? ?? const [])) {
      try {
        final q = EnrolRequest.read(base64Decode(e['q'] as String));
        if (q == null) continue;
        rows[q.requestIdHex] = {'q': e['q'] as String, 'at': e['at'] as int};
      } catch (err) {
        _log.warn('Enrolment: a waiting request of the left-over file is '
            'not readable ($err) — skipped');
      }
    }
    return rows;
  }
}
