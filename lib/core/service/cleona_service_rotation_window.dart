// THE TRANSITION WINDOW OF A ROTATION (§14.4, owner decision 01.09.2026)
//
// ── WHAT THE OLD MARK LINE IN V4.1 ACTUALLY IS ─────────────────────
//
// Until today a V3 term stood here: `_previousMailboxPrimary`, the mailbox
// derived from the identity pubkey. v4_1 §21.2 explicitly denies it
// ("There is no mailbox derivable from a pubkey … no XOR metric"),
// `_primaryMailboxId()` fell with the CUT — and the field remained as a
// corpse, no longer SET by anyone.
//
// The V4.1 answer stands in `pair_registry.dart` and is measured, not
// presumed:
//
//     K_AB = X25519-DH(own ed25519 SECRET KEY,
//                      founding pubkey of the counterpart)
//     (`deriveDeliveryPairKeyFromFounding`, pair_registry.dart:211-222,
//      called from `v41PairKeyFor`, cleona_service_receive.dart:929-948)
//
// The own side of this DH is the CURRENT secret key — and that is replaced
// by `rotateIdentityFull`. So:
//
//     `K_AB_alt` = DH(old own sk, founding pk of the contact)
//     `K_AB_neu` = DH(new own sk, founding pk of the contact)
//
// A contact that has not yet applied the rotation keeps computing against
// my OLD pubkey and thus deposits on `K_AB_alt`. One that has applied it
// computes against the new one. THAT is the old and the new mark line in
// V4.1 — not a mailbox, but the pair line itself.
//
// `v41PairKeyFor` already says so at its own place, as a warning without
// action: "diese Identitaet hat rotiert … der Paarschluessel weicht ab
// (§15.2). Zustellung an alte Kontakte schlaegt fehl."
//
// The DIRECTION (`v41OutDirectionFor`) hangs on the FOUNDING pubkeys of
// both sides and survives the rotation unchanged — the old line is thus
// harvested under the same direction as the new one.
//
// ── THE OWNER'S DECISION, LITERALLY (01.09.2026) ──────────────────
//
//     "On device locking: until the contact has the new keys."
//     "But at most 14 days. After that the loss of contact is acceptable."
//
// So ended PER CONTACT as soon as it has switched over; 14 days are the
// CAP, not the rule. Not a flat 14 days for everyone — that would be the
// expensive variant (every old line costs the harvest a slot, see "price"
// below) and would moreover carry a correlation feature towards the relays
// for longer than necessary.
//
// ── WHAT COUNTS AS "THE CONTACT HAS THE NEW KEYS" ───────────────
//
// `MTV3_KEY_ROTATION_ACK`. Derived, not chosen:
//
//  1. It comes about ONLY where the contact has applied the rotation:
//     `_handleEmergencyKeyRotation` sends it as the last step, after BOTH
//     signatures have been checked and the new keys written into the
//     contact record (`cleona_service.dart`, branch
//     "Send KEY_ROTATION_ACK back to the rotator"). Before that it does not
//     exist.
//
//  2. It is NOT FORGEABLE, by construction rather than by an additional
//     check: it comes in as a V4.1 frame, and `acceptV41Frame` checks the
//     sender MAC under `K_AB` (`verifyV41Sender`,
//     cleona_service_receive.dart:752-772; verdict `forged` is discarded).
//     For an ACCEPTED contact `K_AB` can always be formed, so the verdict
//     is `verified` or `forged` — never `unverifiable`.
//
//     The point is the key under which the MAC stands: the contact can only
//     authenticate the ACK under `K_AB_NEU` once it has adopted my new
//     pubkey. The ACK on the new line thus IS the proof we are looking for
//     — it is not a signal about the switch-over, it is the switch-over.
//     Whoever wanted to forge it would need `K_AB_neu`, i.e. my new secret
//     key or the contact's.
//
//  3. The seam is already there: `_handleKeyRotationAckV3` already calls
//     `_keyRotationRetry.markAcked(senderHex)` at exactly this place.
//
// Rejected: "an inbound message opened under the new keys". It proves the
// same, but only comes when the contact writes of its own accord — a
// silent contact would stay open until the cap, although it switched over
// long ago. The ACK comes unprompted.
//
// ── THE PRICE, CALCULATED ────────────────────────────────────────────────
//
// For the harvest an old line is an additional counterpart in the pair
// register. It thus costs:
//
//   * 6 real marks (`kDeliveryFamilies` = 3 message marks plus 3 signal
//     marks, `harvestTick`, v41_node.dart:2704-2706) — exactly
//     `kMaxRealHarvestTags` = 6, i.e. ONE full harvest request per old line
//     in the small network.
//   * The cap per run is `kHarvestRequestsPerRun` = 3, a run falls every
//     `harvestEverySlots` = 4 slots of 8 s = 32 s.
//
// AVERAGE: per §14.4 a contact is through "after one to two days", in
// practice after its next harvest run. Open old lines are thus 0 to a few
// in normal operation, and the round-robin pointer (`harvestRank`)
// distributes them in the same fair order as all others.
//
// WORST CASE, and it is a FINDING: if all N contacts are offline and the
// cap runs out fully, the set doubles to 2N counterparts. A full pass then
// needs `ceil(2N/3)` runs instead of `ceil(N/3)`. At N = 10: 7 runs = 224 s
// instead of 4 runs = 128 s, until a particular contact is queried again —
// for up to 14 days.
//
// THE HARVEST CAP DOES NOT BREAK IN THE PROCESS, and that has been checked
// rather than hoped: `harvestTick` aborts at `placed >= maxRequests` and
// takes the rest in the next run (`_harvestPointer`/`_coldPointer` move
// on). So nothing fails, it takes longer. `kMaxRealHarvestTags` is not
// broken either, because every old line is an OWN counterpart and
// `bundleHarvest` bundles per counterpart — 6 marks, not 12.
//
// The doubling of the harvest latency for up to 14 days is the price of
// the decision. It stands here so that it is not first noticed in the field.

part of 'cleona_service.dart';

/// A running transition window (§14.4) for EXACTLY ONE contact.
final class RotationWindow {
  /// The contact (UserID hex).
  final String contactHex;

  /// `K_AB_alt` — the pair line under which this contact deposits as long
  /// as it has not applied the rotation. 32 B, hex.
  final String kAbOldHex;

  /// The outbound direction of the pair. It hangs on the founding pubkeys
  /// and does NOT change through the rotation — carried along so that the
  /// restart does not have to re-derive it (the contact record could have
  /// been deleted in the meantime).
  final int outDirection;

  final int startedAtMs;

  /// Set as soon as the window is closed.
  int? closedAtMs;

  /// `contactHasNewKeys` (the ACK came) or `deadline` (14 days over).
  String? closeReason;

  RotationWindow({
    required this.contactHex,
    required this.kAbOldHex,
    required this.outDirection,
    required this.startedAtMs,
    this.closedAtMs,
    this.closeReason,
  });

  bool get closed => closedAtMs != null;

  /// §14.4/owner: „But at most 14 days."
  int get deadlineMs =>
      startedAtMs + CleonaService._rotationWindowDays * 86400 * 1000;

  Map<String, dynamic> toJson() => {
        'contactHex': contactHex,
        'kAbOldHex': kAbOldHex,
        'outDirection': outDirection,
        'startedAtMs': startedAtMs,
        if (closedAtMs != null) 'closedAtMs': closedAtMs,
        if (closeReason != null) 'closeReason': closeReason,
      };

  static RotationWindow fromJson(Map<String, dynamic> j) => RotationWindow(
        contactHex: j['contactHex'] as String,
        kAbOldHex: j['kAbOldHex'] as String,
        outDirection: (j['outDirection'] as num?)?.toInt() ?? 0,
        startedAtMs: (j['startedAtMs'] as num).toInt(),
        closedAtMs: (j['closedAtMs'] as num?)?.toInt(),
        closeReason: j['closeReason'] as String?,
      );
}

/// Area of the transition windows in the store (formerly
/// `rotation_windows.json`), §14.4.
///
/// ── WHAT STANDS IN HERE, AND WHY THAT IS FINE ──────────────────
///
/// `RotationWindow.kAbOldHex` is the OLD pair key `K_AB_alt` — i.e. key
/// material, not mere state. It nevertheless lies correctly here: the
/// store stands under the same seed-derived key
/// (`HdWallet.deriveFileEncKey`) under which the file stood before, so the
/// protection level does not change. What changes is the granularity —
/// and because `K_AB_alt` can no longer be formed from any existing key
/// after the rotation (`rotateIdentityFull` overwrites the own side of the
/// DH), it MUST travel along completely: if it gets lost, every cell that
/// a not-yet-switched contact deposits on the old line is unreadable.
const String kRotationWindowArea = 'rotation_windows';

extension RotationWindowOps on CleonaService {
  // ── Storage ────────────────────────────────────────────────────────────
  //
  // S366: area `rotation_windows` instead of a file. What is written is the
  // AREA, not the single row — unlike the lock-out transitions next door:
  // the three writing paths (`_beginRotationWindows`,
  // `_closeRotationWindow`, the cleaner) each change the overall state of
  // a rotation, and the cleaner also removes in the process. A stock the
  // size of the contact list, touched only at rotation events, does not
  // justify a second way of writing.

  void _ensureRotationWindowsLoaded() {
    if (_rotationWindowsLoaded) return;
    try {
      for (final e in store.loadArea(kRotationWindowArea).entries) {
        try {
          _rotationWindows[e.key] = RotationWindow.fromJson(e.value);
        } catch (err) {
          _log.warn('Transition window ${e.key} unreadable, skipped: $err');
        }
      }
      // ONLY HERE, NOT IN THE FIRST LINE — see latch below.
      _rotationWindowsLoaded = true;
      if (_rotationWindows.isNotEmpty) {
        _log.info('Transition windows loaded: ${_rotationWindows.length} '
            '(${_rotationWindows.values.where((w) => !w.closed).length} open)');
      }
    } catch (e) {
      _log.warn('Transition windows: loading failed: $e');
    }
  }

  void _saveRotationWindows() {
    // DATA-LOSS LATCH (S366) — NEWLY BUILT, there was none here.
    //
    // THE FINDING: `_rotationWindows.isEmpty` meant "delete file", and the
    // same state was left behind by a failed load; the load flag moreover
    // stood at `true` BEFORE reading, so the difference was visible
    // nowhere any more. The loss here would be the most severe of the
    // seven areas: with the window `K_AB_alt` is lost, and that cannot be
    // restored after the rotation — every cell of a contact not yet
    // switched over would stay unreadable. The latch fails closed.
    if (!_rotationWindowsLoaded && _rotationWindows.isEmpty) {
      var present = false;
      try {
        present = store.countArea(kRotationWindowArea) > 0;
      } catch (e) {
        _log.warn(
            'Transition window: REFUSED to save — store not readable: $e');
        return;
      }
      if (present) {
        _log.warn('Transition window: REFUSED to save empty set — loading '
            'failed, but the storage holds windows (and thus K_AB_alt). '
            'Would cause data loss!');
        return;
      }
    }
    try {
      store.replaceArea(kRotationWindowArea,
          {for (final e in _rotationWindows.entries) e.key: e.value.toJson()});
    } catch (e) {
      _log.warn('Transition windows: saving failed: $e');
    }
  }

  /// The identifier under which the OLD line stands in the pair register.
  ///
  /// An own identifier and not a second entry under the same one: the
  /// register holds EXACTLY ONE `K_AB` per counterpart (`pair_registry.dart`
  /// `_kAb` is a map). A second `remember` on the same identifier would
  /// overwrite the new line instead of placing the old one next to it —
  /// and the harvest would then run exclusively on the old one.
  String _v41OldLinePeerKey(Uint8List recipientUserId) =>
      '${_v41PeerKey(recipientUserId)}#alt';

  // ── Start ─────────────────────────────────────────────────────────────

  /// Opens the transition windows of a rotation.
  ///
  /// MUST RUN BEFORE `rotateIdentityFull`: `K_AB_alt` derives from the old
  /// secret key, and the rotation overwrites it. After that it could no
  /// longer be formed — [identity] does keep `previousX25519Sk` (since S362
  /// for `IdentityContext.previousKeyRetention` = 32 days, no longer 7),
  /// but exclusively for decrypting individual cells (`MessageOpener`), not
  /// as a pair line anchor.
  void _beginRotationWindows() {
    _ensureRotationWindowsLoaded();
    final now = DateTime.now().millisecondsSinceEpoch;
    var opened = 0;
    for (final contact in _contacts.values) {
      if (contact.status != 'accepted') continue;
      final hex = bytesToHex(contact.nodeId);
      try {
        final kAbOld = v41PairKeyFor(contact.nodeId, contact);
        final direction = v41OutDirectionFor(contact.nodeId, contact);
        _rotationWindows[hex] = RotationWindow(
          contactHex: hex,
          kAbOldHex: bytesToHex(kAbOld),
          outDirection: direction,
          startedAtMs: now,
        );
        opened++;
      } on StateError {
        // No founding key — this contact had no pair line BEFORE the
        // rotation either. There is nothing to keep open.
        continue;
      }
    }
    if (opened > 0) _saveRotationWindows();
    _log.info('§14.4: $opened transition window(s) opened — the old '
        'pair line is harvested per contact until it has the new '
        'keys, at most ${CleonaService._rotationWindowDays} days '
        '(owner decision 01.09.).');
  }

  /// Registers all open old lines in the pair register.
  ///
  /// To be called AFTER `rotateIdentityFull` and AFTER re-priming the new
  /// lines — otherwise both would stand under identifiers the harvest does
  /// not know yet.
  void _registerOldLines() {
    _ensureRotationWindowsLoaded();
    final v41 = v41Delivery;
    if (v41 == null) return;
    var n = 0;
    for (final w in _rotationWindows.values) {
      if (w.closed) continue;
      try {
        v41.rememberPeer(
          _v41OldLinePeerKey(hexToBytes(w.contactHex)),
          hexToBytes(w.kAbOldHex),
          outDirection: w.outDirection,
        );
        n++;
      } catch (e) {
        _log.warn('Transition window ${w.contactHex.substring(0, 8)}: '
            'old line cannot be registered ($e)');
      }
    }
    if (n > 0) {
      _log.info('§14.4: $n old pair line(s) in the harvest register — price: per '
          'line one harvest request per run (${'kMaxRealHarvestTags'} = 6 '
          'tags), cap 3 requests per run.');
    }
  }

  // ── End ───────────────────────────────────────────────────────────────

  /// The contact has the new keys — proven by a `KEY_ROTATION_ACK`
  /// authenticated under `K_AB_neu` (derivation in the header of this
  /// file). The old line falls IMMEDIATELY.
  void _noteContactHasNewKeys(String contactHex) {
    _ensureRotationWindowsLoaded();
    final w = _rotationWindows[contactHex];
    if (w == null || w.closed) return;
    _closeRotationWindow(w, 'contactHasNewKeys');
    _saveRotationWindows();
  }

  void _closeRotationWindow(RotationWindow w, String reason) {
    w.closedAtMs = DateTime.now().millisecondsSinceEpoch;
    w.closeReason = reason;
    try {
      v41Delivery?.forgetPeer(_v41OldLinePeerKey(hexToBytes(w.contactHex)));
    } catch (e) {
      _log.debug('forgetPeer (old line) ${w.contactHex}: $e');
    }
    final days =
        (w.closedAtMs! - w.startedAtMs) / (86400 * 1000.0);
    _log.info('§14.4: old pair line closed for '
        '${w.contactHex.substring(0, 8)} — reason "$reason", after '
        '${days.toStringAsFixed(2)} day(s). '
        '${reason == 'deadline' ? 'From here on the loss of the contact is explicitly accepted (owner decision).' : 'It has switched over.'}');
  }

  /// The hard cap. Rides along on the 30 s clock that runs anyway
  /// (working rule #5 — no second rhythm).
  ///
  /// WITHOUT EXCEPTION: if an ACK never comes, the line falls on day 14.
  /// That is the point at which the owner explicitly accepts the loss of
  /// contact — a line that stayed open longer would keep the locked-out
  /// device in play (§14.4: "otherwise a single orphaned contact would
  /// hold the old line open forever, and with it the locked-out device in
  /// play").
  void _sweepRotationWindows() {
    _ensureRotationWindowsLoaded();
    if (_rotationWindows.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    var changed = false;
    for (final w in _rotationWindows.values.toList()) {
      if (w.closed) {
        // Cleared away only beyond the deadline — before that a restart
        // should still BE ABLE to see that and why the window is closed.
        if (now >= w.deadlineMs) {
          _rotationWindows.remove(w.contactHex);
          changed = true;
        }
        continue;
      }
      if (now >= w.deadlineMs) {
        _closeRotationWindow(w, 'deadline');
        changed = true;
      }
    }
    if (changed) _saveRotationWindows();
  }

  // ── Display / test ────────────────────────────────────────────────────

  /// The open windows, for UI and guard.
  List<Map<String, dynamic>> rotationWindowStates() {
    _ensureRotationWindowsLoaded();
    return _rotationWindows.values
        .map((w) => <String, dynamic>{
              'contactHex': w.contactHex,
              'startedAtMs': w.startedAtMs,
              'deadlineMs': w.deadlineMs,
              'closed': w.closed,
              if (w.closeReason != null) 'closeReason': w.closeReason,
            })
        .toList();
  }

  /// The identifier under which this contact's old line stands in the
  /// pair register — the guard observes the EFFECT at the delivery layer
  /// (which `rememberPeer`/`forgetPeer` it sees), not the window record. A
  /// window that is set but never moves into the register harvests
  /// nothing; the intention is not the effect.
  ///
  /// Deliberately no access to `V41Node.pairs` from here: `V41Delivery` is
  /// the interface this service hangs on, and a test access that reaches
  /// past it measures something other than what production does.
  @visibleForTesting
  String oldLinePeerKeyForTest(String contactHex) =>
      _v41OldLinePeerKey(hexToBytes(contactHex));

  @visibleForTesting
  void sweepRotationWindowsForTest() => _sweepRotationWindows();

  @visibleForTesting
  void noteContactHasNewKeysForTest(String contactHex) =>
      _noteContactHasNewKeys(contactHex);

  /// Backdates a window, so that the deadline can expire in the test
  /// without faking the clock.
  @visibleForTesting
  bool backdateRotationWindowForTest(String contactHex, Duration at) {
    _ensureRotationWindowsLoaded();
    final w = _rotationWindows[contactHex];
    if (w == null) return false;
    _rotationWindows[contactHex] = RotationWindow(
      contactHex: w.contactHex,
      kAbOldHex: w.kAbOldHex,
      outDirection: w.outDirection,
      startedAtMs: w.startedAtMs - at.inMilliseconds,
      closedAtMs: w.closedAtMs,
      closeReason: w.closeReason,
    );
    _saveRotationWindows();
    return true;
  }
}
