// E-7 — The lock-out transition: a device lock only takes effect once
// the contacts know, and the old mark line closes.
//
// ── THE FINDING, MEASURED ────────────────────────────────────────────────
//
// `revokeDevice` (`cleona_service.dart`) sent `MTV3_DEVICE_REVOCATION`
// to every accepted contact via `_detachedSend(...)`. Its body SWALLOWS
// the future completely — a `catchError` with log, nothing else. The
// transition thus existed only as a beginning:
//
//     $ grep -rn "revocationPending\|revokePending\|_revocationAck\|
//                 lockoutPending\|announcementAck\|contactsInformed" lib/
//     (no hit)
//
// ── WHAT THE ARCHITECTURE REQUIRES ────────────────────────────────────────
//
// v4_1 §14.4 ("End of the transition", normative): "The old line is closed
// **as soon as all contacts have acknowledged the announcement, but at the
// latest after the delivery window** (one recovery-epoch lifetime, 14
// days). In the normal case, everyone is through after one to two days;
// the deadline only kicks in for contacts who never come back — otherwise
// a single orphaned contact would hold the old line open forever, and with
// it the locked-out device in play."
//
// §14.4 ("Visibility", normative) and §24.4.3 additionally require the
// parametrised display with TWO counters: "Device locked — fully
// effective once all contacts are informed (3 of 47 still open)".
//
// ── VIA THE EXISTING DELIVERY REGISTER, NOT VIA NEW MACHINERY ──
//
// The owner's decision (E-7 = A). Since AP-4 the application keeps one
// record per message in the `V41DeliveryRegister`
// (`lib/core/tagline/delivery_state.dart`), and `_v41ApplyOutgoingStatus`
// reads it. The announcement is therefore QUEUED there: every fan-out leg
// gets its own message identifier, under which `sendToUser` creates the
// record, and a contact counts as informed when for ITS leg there is a
// delivery receipt authenticated under `K_AB` (§9.2 D2 — only the
// receiver can produce it).
//
// ── WHY THE PENDING SET LIVES ON DISK NONETHELESS ────────────
//
// The register lives ONLY IN MEMORY and is capped at 2048 records
// (`V41DeliveryRegister.maxRecords`). The transition runs up to 14 days;
// a daemon restart falls into this window with certainty. If the set
// stood only in the register, a restart would see "0 of 0 open" and would
// have reported the lock as completed without a single contact knowing
// about it. That is why the ACKNOWLEDGED state is persisted, rather than
// the counter derived.
//
// ── WHAT "CLOSING THE OLD MARK LINE" CONCRETELY IS HERE ──────────────
//
// `K_AB` derives from the FOUNDING keys (`v41PairKeyFor`, §15.2) and
// survives every rotation — so the pair line does not close. What the
// locked-out device can keep reading is the inbound line derived from the
// IDENTITY key: `_previousMailboxPrimary`
// (SHA-256("mailbox" ‖ old Ed25519 PK), §5.6). The rotation that
// `revokeDevice` triggers sets it; until today it expired after a
// BLIND 7-day timer, without any reference to whether the contacts have
// the announcement.
//
// What changes as a result, honestly in both directions:
//   * The normal case becomes SHORTER. Once all contacts are through —
//     per §14.4 "one to two days" —, the line closes at once instead of
//     after 7 days.
//   * The worst case becomes LONGER: 14 instead of 7 days if a contact
//     never comes back. That is the number §14.4 names, and it has a
//     reason: if the line closes before a contact has harvested the
//     announcement, THEIR messages are silently lost.
//     §14.4: "If the old line were closed immediately, their messages
//     would be **silently lost**."
part of 'cleona_service.dart';

/// A running lock-out transition (§14.4).
///
/// One record per locked device. It lives from the revocation until the
/// closing of the old line and survives restarts.
final class LockoutTransition {
  /// The locked-out device (UUID hex, key in `_devices`).
  final String deviceId;

  /// Its name at the time of the lock — for the display, because the
  /// device record is gone afterwards.
  final String deviceName;

  final int startedAtMs;

  /// Contact hex -> identifier of the leg under which the announcement
  /// went to it. EXACTLY the identifier under which `sendToUser` created
  /// the record in the delivery register.
  final Map<String, String> pendingLegs;

  /// Contacts whose leg carried an authenticated delivery receipt.
  final Set<String> informed;

  /// Contacts whose leg demonstrably did not go out at all (`sendToUser`
  /// reported `false`). They stay PENDING — not informed is not
  /// informed —, but are kept separately, so that the display
  /// "3 of 47 open" is not confused with "3 of 47 failed".
  final Set<String> notSent;

  bool closed;
  int? closedAtMs;

  /// `allInformed` or `deadline` — which of the two branches of §14.4
  /// took hold. Stands in the display and in the log.
  String? closeReason;

  LockoutTransition({
    required this.deviceId,
    required this.deviceName,
    required this.startedAtMs,
    required this.pendingLegs,
    Set<String>? informed,
    Set<String>? notSent,
    this.closed = false,
    this.closedAtMs,
    this.closeReason,
  })  : informed = informed ?? <String>{},
        notSent = notSent ?? <String>{};

  /// The deadline from §14.4: "at the latest after the delivery window (one
  /// recovery-epoch lifetime, 14 days)".
  int get deadlineMs =>
      startedAtMs + CleonaService._lockoutDeadlineDays * 86400 * 1000;

  /// The second counter from §24.4.3 — how many contacts do not know it
  /// yet.
  int get stillOpen => pendingLegs.length - informed.length;

  /// The first counter from §24.4.3 — how many it is about in total.
  int get total => pendingLegs.length;

  bool get allInformed => stillOpen <= 0;

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'startedAtMs': startedAtMs,
        'pendingLegs': pendingLegs,
        'informed': informed.toList(),
        'notSent': notSent.toList(),
        'closed': closed,
        if (closedAtMs != null) 'closedAtMs': closedAtMs,
        if (closeReason != null) 'closeReason': closeReason,
      };

  static LockoutTransition fromJson(Map<String, dynamic> j) =>
      LockoutTransition(
        deviceId: j['deviceId'] as String,
        deviceName: j['deviceName'] as String? ?? '',
        startedAtMs: j['startedAtMs'] as int,
        pendingLegs: (j['pendingLegs'] as Map).map(
            (k, v) => MapEntry(k as String, v as String)),
        informed: ((j['informed'] as List?) ?? const [])
            .map((e) => e as String)
            .toSet(),
        notSent: ((j['notSent'] as List?) ?? const [])
            .map((e) => e as String)
            .toSet(),
        closed: j['closed'] as bool? ?? false,
        closedAtMs: j['closedAtMs'] as int?,
        closeReason: j['closeReason'] as String?,
      );
}

/// How long after the start of a transition a newly set old mark line
/// still counts AS ITS OWN. Justification: [
/// DeviceLockoutOps._lockoutHoldsLine].
const Duration _lineOwnershipWindow = Duration(minutes: 5);

/// Area of the lock-out transitions in the store (formerly
/// `device_lockouts.json`), §14.4.
const String kDeviceLockoutArea = 'device_lockouts';

extension DeviceLockoutOps on CleonaService {
  // ── Persistence ────────────────────────────────────────────────────────
  //
  // S366: area `device_lockouts` in the encrypted store instead of
  // `device_lockouts.json`. **One row per device**, written via
  // [_persistLockout]: the collection grows with the contact count, and a
  // single arriving leg (`notSent` one entry smaller) rewrote the whole
  // stock — with 47 contacts that was the case that `_noteLockoutLeg`
  // below already once described as too expensive.

  /// Loads the transitions on FIRST access.
  ///
  /// Deliberately no call from `startService()`: then there would be two
  /// paths (the started service and everything else), and the test would
  /// use a different one than production. This way there is exactly one.
  void _ensureLockoutsLoaded() {
    if (_lockoutsLoaded) return;
    try {
      for (final e in store.loadArea(kDeviceLockoutArea).entries) {
        try {
          _lockouts[e.key] = LockoutTransition.fromJson(e.value);
        } catch (err) {
          _log.warn('Lockout transition ${e.key} unreadable, skipped: $err');
        }
      }
      // ONLY HERE, NOT IN THE FIRST LINE. Until S366
      // `_lockoutsLoaded = true` stood BEFORE the read — a failed run thus
      // counted as loaded stock, and the latch below would never have seen
      // it. Now the marker means what it says, and a read error is retried
      // on the next access.
      _lockoutsLoaded = true;
      if (_lockouts.isNotEmpty) {
        _log.info('Lockout transitions loaded: ${_lockouts.length} '
            '(${_lockouts.values.where((t) => !t.closed).length} open)');
      }
    } catch (e) {
      _log.warn('Lockout transitions: loading failed: $e');
    }
  }

  /// Writes EXACTLY ONE transition — or removes it if it no longer stands
  /// in memory.
  void _persistLockout(String deviceId) {
    if (!_lockoutsLoaded) {
      _log.warn('Lockout transitions: REFUSED to persist '
          '${deviceId.substring(0, 8)} — loading failed, the '
          'stored state is not authoritative');
      return;
    }
    try {
      final t = _lockouts[deviceId];
      if (t == null) {
        store.removeEntry(kDeviceLockoutArea, deviceId);
      } else {
        store.putEntry(kDeviceLockoutArea, deviceId, t.toJson());
      }
    } catch (e) {
      _log.warn('Lock-out transitions: saving '
          '${deviceId.substring(0, 8)} failed: $e');
    }
  }

  /// Writes the ENTIRE stock. Only for the paths that change SEVERAL
  /// transitions at once — the receipt round and the cleaner, which also
  /// removes closed transitions. Whoever changes exactly ONE calls
  /// [_persistLockout].
  void _saveLockouts() {
    // DATA-LOSS LATCH (S366) — NEWLY BUILT, there was none here.
    //
    // THE FINDING: `_lockouts.isEmpty` meant "delete file", and exactly
    // this state was also left behind by a failed load. Because
    // `_ensureLockoutsLoaded` moreover set its marker BEFORE reading,
    // there was no place at all where the difference would still have
    // been visible. A lost transition means, per §14.4: the old mark line
    // is never closed, and the locked-out device stays in play.
    if (!_lockoutsLoaded && _lockouts.isEmpty) {
      var present = false;
      try {
        present = store.countArea(kDeviceLockoutArea) > 0;
      } catch (e) {
        _log.warn('Lockout transitions: REFUSED to save — store not '
            'readable: $e');
        return;
      }
      if (present) {
        _log.warn('Lock-out transitions: REFUSED to save empty set — '
            'loading failed, but the store holds transitions. '
            'Would cause data loss!');
        return;
      }
    }
    try {
      store.replaceArea(kDeviceLockoutArea,
          {for (final e in _lockouts.entries) e.key: e.value.toJson()});
    } catch (e) {
      _log.warn('Lockout transitions: saving failed: $e');
    }
  }

  // ── Start ─────────────────────────────────────────────────────────────

  /// Opens the transition for [deviceId] and returns the identifier under
  /// which the announcement to [contactHex] is to be sent.
  ///
  /// The caller (`revokeDevice`) passes this identifier on as `messageId`
  /// to `sendToUser` — so the send site creates the record in the delivery
  /// register under exactly this identifier, and the contact's receipt
  /// finds it again.
  LockoutTransition _beginLockout(String deviceId, String deviceName) {
    _ensureLockoutsLoaded();
    final present = _lockouts[deviceId];
    if (present != null && !present.closed) return present;
    final t = LockoutTransition(
      deviceId: deviceId,
      deviceName: deviceName,
      startedAtMs: DateTime.now().millisecondsSinceEpoch,
      pendingLegs: <String, String>{},
    );
    _lockouts[deviceId] = t;
    return t;
  }

  /// Notes a leg of the announcement and attaches itself to ITS outcome.
  ///
  /// HERE STOOD `_detachedSend`, and that was the finding: it threw the
  /// future away. The latch against the dying daemon stays (every throw is
  /// caught), but the RESULT is now read — a leg that demonstrably went
  /// out nowhere belongs in `notSent` and not in the same cloud as one
  /// that is in transit.
  void _noteLockoutLeg(LockoutTransition t, String contactHex, String legIdHex,
      Future<bool> dispatch) {
    t.pendingLegs[contactHex] = legIdHex;
    // ONLY WRITE IF SOMETHING HAS CHANGED. The normal case is that all
    // legs go out — then `notSent` stays empty and this feedback costs
    // nothing. An unconditional `_saveLockouts()` per leg would, with 47
    // contacts (the number from the example of §24.4.3), be 47 encrypted
    // file writes in a row, for zero new information.
    dispatch.then((ok) {
      if (ok ? t.notSent.remove(contactHex) : t.notSent.add(contactHex)) {
        _persistLockout(t.deviceId);
      }
    }).catchError((Object e, StackTrace s) {
      if (t.notSent.add(contactHex)) _persistLockout(t.deviceId);
      _log.error('Lockout announcement to '
          '${contactHex.substring(0, 8)} threw: $e\n$s');
    });
  }

  // ── Fortschritt ───────────────────────────────────────────────────────

  /// An authenticated delivery receipt has arrived — does it concern a
  /// leg of a lock-out announcement?
  ///
  /// Called from `_handleDeliveryReceiptV3`, AFTER `_v41NoteReceipt`:
  /// there the record in the delivery register is flipped, here what it
  /// says is read. The question about the proof is thus not answered a
  /// second time — it is asked at the one place that already answers it
  /// (§9.2, D2).
  void _noteLockoutAck(String legIdHex) {
    _ensureLockoutsLoaded();
    if (_lockouts.isEmpty) return;
    var changed = false;
    for (final t in _lockouts.values) {
      if (t.closed) continue;
      for (final e in t.pendingLegs.entries) {
        if (e.value != legIdHex) continue;
        if (!_v41DeliveryProvenForLockout(legIdHex)) continue;
        if (t.informed.add(e.key)) {
          t.notSent.remove(e.key);
          changed = true;
          _log.info('Lock-out transition ${t.deviceId.substring(0, 8)}: '
              'contact ${e.key.substring(0, 8)} informed '
              '(${t.stillOpen} of ${t.total} open)');
        }
      }
    }
    if (changed) {
      _saveLockouts();
      _sweepLockouts();
      onStateChanged?.call();
    }
  }

  /// Does the delivery register prove the delivery of this leg?
  ///
  /// STRICTER THAN `_v41DeliveryProven`, and that is intentional. There
  /// "don't know it" means `true`, because a cap must not permanently nail
  /// a message to "not delivered". Here the same leniency would be wrong
  /// the other way round: "don't know it" would count a contact as
  /// informed whom nobody informed, and report the lock as effective when
  /// it is not. An unknown leg therefore stays PENDING and in the worst
  /// case runs into the 14-day deadline — the branch §14.4 provides for
  /// exactly this case.
  bool _v41DeliveryProvenForLockout(String legIdHex) =>
      v41Deliveries.lookup(legIdHex)?.state == DeliveryState.delivered;

  // ── Close ─────────────────────────────────────────────────────────────

  /// Checks every open transition against the two branches of §14.4.
  ///
  /// Runs along in the 30-second clock of the existing expiry timer; an
  /// own timer would be a second clock for the same question
  /// (working rule #5).
  void _sweepLockouts() {
    _ensureLockoutsLoaded();
    if (_lockouts.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    var changed = false;

    for (final t in _lockouts.values) {
      if (t.closed) continue;

      // Catch up from the register: a receipt may have arrived while
      // `_noteLockoutAck` did not see it (group fan-out path, re-reading
      // after restart within the register lifetime).
      for (final e in t.pendingLegs.entries) {
        if (t.informed.contains(e.key)) continue;
        if (!_v41DeliveryProvenForLockout(e.value)) continue;
        t.informed.add(e.key);
        t.notSent.remove(e.key);
        changed = true;
      }

      if (t.allInformed) {
        _closeLockout(t, 'allInformed');
        changed = true;
      } else if (now >= t.deadlineMs) {
        _closeLockout(t, 'deadline');
        changed = true;
      }
    }

    // Closed transitions whose old line is long gone need not lie on disk
    // forever. They are kept until the end of the deadline, because until
    // then a receipt can still arrive whose assignment would otherwise
    // show up in the log as "unknown leg".
    final toDelete = _lockouts.values
        .where((t) => t.closed && now >= t.deadlineMs)
        .map((t) => t.deviceId)
        .toList();
    for (final id in toDelete) {
      _lockouts.remove(id);
      changed = true;
    }

    if (changed) {
      _saveLockouts();
      onStateChanged?.call();
    }
  }

  void _closeLockout(LockoutTransition t, String reason) {
    t.closed = true;
    t.closedAtMs = DateTime.now().millisecondsSinceEpoch;
    t.closeReason = reason;
    _log.warn('Lockout transition ${t.deviceId.substring(0, 8)} '
        '("${t.deviceName}") closed — reason: $reason, '
        '${t.informed.length} of ${t.total} contacts informed');
    _closeOldTagLine(t);
  }

  /// Does the currently held old mark line belong to [t]?
  ///
  /// ── WHY THIS QUESTION IS ASKED AT ALL ──────────────────────
  ///
  /// `_previousMailboxPrimary` is ONE field, not a record per rotation.
  /// Every further rotation — hygiene, a second revocation, the IPC path
  /// `rotate_identity_keys` — overwrites it. A transition that expires
  /// days later must therefore not blindly close what it finds there: that
  /// could be the line of a YOUNGER rotation whose own window has only
  /// just begun. Exactly this premature closing is the silent message loss
  /// that §14.4 wants to prevent ("their messages would be **silently
  /// lost**").
  ///
  /// ── HOW THE ASSIGNMENT WORKS WITHOUT AN ADDITIONAL FIELD ──────────────
  ///
  /// Via the point in time, and that is not an estimate: the rotation that
  /// sets the line runs OUT OF `revokeDevice` —
  /// `unawaited(rotateIdentityKeys())` stands there in the same call path
  /// as `_beginLockout`, and `_previousMailboxPrimary = _primaryMailboxId()`
  /// is the first line of its body, even before any `await`. Between the
  /// start of the transition and the setting of the line lie
  /// milliseconds. [_lineOwnershipWindow] is generous compared with this
  /// span and still much shorter than any later rotation.
  ///
  /// Cleaner would be to note the mark IN the transition when the rotation
  /// sets it. That requires one line in `rotateIdentityKeys`
  /// (`cleona_service.dart`) and stands as a proposal in the session report.
  bool _lockoutHoldsLine(LockoutTransition t, DateTime? setAt) {
    if (setAt == null) return true; // fail closed: without a timestamp it counts
    final ms = setAt.millisecondsSinceEpoch;
    return ms >= t.startedAtMs - 1000 &&
        ms <= t.startedAtMs + _lineOwnershipWindow.inMilliseconds;
  }

  /// Closes the old mark line that THIS transition has held open.
  /// Justification of the assignment: [_lockoutHoldsLine].
  void _closeOldTagLine(LockoutTransition t) {
    final held = _previousMailboxPrimary;
    if (held == null) return;
    final setAt = _previousMailboxPrimarySetAt;
    if (!_lockoutHoldsLine(t, setAt)) {
      _log.info('Old mark line stems from a different rotation '
          '(${setAt?.toIso8601String()}) — stays open');
      return;
    }
    _previousMailboxPrimary = null;
    _previousMailboxPrimarySetAt = null;
    _saveMailboxTransition();
    _log.warn('Old tag line closed (lockout transition '
        '${t.deviceId.substring(0, 8)}) — no more harvesting under the old '
        'inbound address');
  }

  /// How long the old inbound line may stay open.
  ///
  /// 7 days is the value §5.6 sets for an ordinary rotation. If an OPEN
  /// lock-out transition holds this line, the deadline of §14.4 applies:
  /// 14 days. The difference has a named reason — an announcement the
  /// contact has not harvested yet turns closing into a silent message
  /// loss on THEIR side.
  int _mailboxTransitionWindowDays() {
    _ensureLockoutsLoaded();
    final setAt = _previousMailboxPrimarySetAt;
    if (setAt == null) return CleonaService._mailboxTransitionDays;
    for (final t in _lockouts.values) {
      if (t.closed) continue;
      // THE SAME assignment as when closing (`_lockoutHoldsLine`), and that
      // is the condition for both fitting together: what a transition holds
      // open longer must also be what it then closes. Two different
      // criteria would either hold a line for 14 days and never close it,
      // or the other way round.
      if (_lockoutHoldsLine(t, setAt)) {
        return CleonaService._lockoutDeadlineDays;
      }
    }
    return CleonaService._mailboxTransitionDays;
  }

  // ── Display (§24.4.3) ─────────────────────────────────────────────────

  /// The numbers from which the UI builds "Geraet gesperrt — vollstaendig
  /// wirksam, sobald alle Kontakte informiert sind (3 von 47 offen)".
  ///
  /// NO UI IN THIS PACKAGE (the 34 locales are held by a parallel package);
  /// this here is the data side, on which the display is then small. The
  /// key list is in the session report.
  List<Map<String, dynamic>> deviceLockoutStates() {
    _ensureLockoutsLoaded();
    return _lockouts.values
        .map((t) => <String, dynamic>{
              'deviceId': t.deviceId,
              'deviceName': t.deviceName,
              'startedAtMs': t.startedAtMs,
              'deadlineMs': t.deadlineMs,
              'total': t.total,
              'stillOpen': t.stillOpen,
              'notSent': t.notSent.length,
              'closed': t.closed,
              if (t.closedAtMs != null) 'closedAtMs': t.closedAtMs,
              if (t.closeReason != null) 'closeReason': t.closeReason,
            })
        .toList();
  }

  // ── Testzugaenge ──────────────────────────────────────────────────────

  /// Checks the two branches of §14.4 immediately instead of in the
  /// 30-second clock. Calls THE SAME production path; no second mechanism.
  @visibleForTesting
  void sweepLockoutsForTest() => _sweepLockouts();

  /// Moves the start of a transition into the past, so that the 14-day
  /// deadline can expire in the test without faking the clock.
  @visibleForTesting
  bool backdateLockoutForTest(String deviceId, Duration at) {
    _ensureLockoutsLoaded();
    final old = _lockouts[deviceId];
    if (old == null) return false;
    _lockouts[deviceId] = LockoutTransition(
      deviceId: old.deviceId,
      deviceName: old.deviceName,
      startedAtMs: old.startedAtMs - at.inMilliseconds,
      pendingLegs: old.pendingLegs,
      informed: old.informed,
      notSent: old.notSent,
      closed: old.closed,
      closedAtMs: old.closedAtMs,
      closeReason: old.closeReason,
    );
    _persistLockout(deviceId);
    return true;
  }

  /// The leg identifiers of a transition — the test needs them to produce
  /// a receipt for EXACTLY the leg that production sent.
  @visibleForTesting
  Map<String, String> lockoutLegsForTest(String deviceId) {
    _ensureLockoutsLoaded();
    return Map<String, String>.from(
        _lockouts[deviceId]?.pendingLegs ?? const <String, String>{});
  }

  /// Reports an arrived, authenticated receipt for [legIdHex] —
  /// the same call that `_handleDeliveryReceiptV3` makes.
  @visibleForTesting
  void noteLockoutAckForTest(String legIdHex) => _noteLockoutAck(legIdHex);

  /// The window that the old entry line is currently holding open.
  @visibleForTesting
  int mailboxTransitionWindowDaysForTest() => _mailboxTransitionWindowDays();
}
