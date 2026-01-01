// CUT addendum, 31.08.2026 — what the file-granular cut tore along with it.
//
// The demolition of the V3 line deleted ten `cleona_service_v3_*.dart` as
// WHOLE FILES. That was the right size for the cut, but not for every
// single method in them: some bodies lay there because they stood in the
// source text between two V3 blocks — a filing place, not a boundary of
// fate. The same error class that §4c.2i already described once, only this
// time in the other direction.
//
// THE CHECK WAS NOT "WHERE DID IT LIE", BUT "WHAT DOES IT TOUCH". Every
// method here reads exclusively fields of `CleonaService`
// (`_contacts`, `_groups`, `_outbox`, `_suppressedReceiptMsgIds`) or the
// disk. Not a single one touches network, node, routing table or a
// V3 frame — they would have worked in V3 just as in V4.1, and their
// callers survived the cut.
//
// `_withholdsDeliveryStatusTo` is the most important case: §14.7.4
// (display lock per contact/group) is a promised product property, not a
// V3 remnant. Without it EVERY message would have disclosed its delivery
// status, regardless of what the user has set — and silently.
//
// The origin of each method stands at its body. The bodies are taken over
// literally (`git show 361af1df:lib/core/service/cleona_service_v3_*.dart`),
// unless explicitly noted otherwise.

part of 'cleona_service.dart';

// ── THE AREAS IN THE ENCRYPTED STORE (S366) ─────────────────
//
// Until S366 four separate `*.json.enc` files lay here in the profile. They
// are gone; the records now stand in `state(bereich, schluessel, …)` of the
// store — under THE SAME seed-derived key as before
// (`HdWallet.deriveFileEncKey`), i.e. without loss of protection, but with
// granularity: a change to an entry costs one row instead of the whole
// collection.
//
// THERE IS NO TAKEOVER STEP, and that is not an oversight: the
// justification stands above `MessageStore.putEntry` and rests on
// `FirstStartWipe.wipeProfileData` — at first start there is nothing left
// below the profile directory that would have to be taken over.

/// The V3 legacy outbox (formerly `outbox.json`).

/// Die V4.1-Outbox (vormals `v41_outbox.json`), §21.2/§21.8.
const String kLocalOutboxArea = 'v41_outbox';

/// The mailbox transition (formerly `mailbox_transition.json`), §5.6.
const String kMailboxTransitionArea = 'mailbox_transition';

/// The area of the app's former membership resend queue (S408 P19: gone;
/// its rows are removed at start, [_membershipResendRows]).
const String kMembershipResendArea = 'membership_resend';

/// The area of the former §14.4 transition windows of the V4.1 pair line
/// (S408-P23: gone with `lib/core/tagline/`; its rows — the old pair keys —
/// are removed at start, [_rotationWindowRows]).
const String kRotationWindowArea = 'rotation_windows';

/// The key of an area that carries EXACTLY ONE state.
///
/// A single state is not a collection: it gets a fixed key, so that a
/// second record cannot come about at all. If one chose something
/// content-related instead (an identifier, a timestamp), a slip would let
/// two rows stand side by side, and `loadArea(…).values.first` would then
/// have an opinion about which one applies.
const String kSingleStateKey = '_';

extension PureServiceOps on CleonaService {
  // ── §14.7.4 display lock (formerly cleona_service_v3_sf.dart:254) ───

  /// §14.7.4: does this node withhold its delivery status from [senderUserId]?
  ///
  /// A group message is governed by the group's own setting; everything else
  /// by the contact's. Channels are deliberately absent: `CHANNEL_POST` is not
  /// ack-worthy, so no receipt is ever emitted for one and there is nothing to
  /// withhold. Unknown group / unknown contact both fall back to `false`
  /// (disclose) — the behaviour that predates the flag.
  bool _withholdsDeliveryStatusTo(Uint8List senderUserId, List<int> groupId) {
    if (groupId.isNotEmpty) {
      final group = _groups[bytesToHex(Uint8List.fromList(groupId))];
      if (group != null) return group.withholdDeliveryStatus;
    }
    return _contacts[bytesToHex(senderUserId)]?.withholdDeliveryStatus ?? false;
  }

  /// §14.7.4 / §21.5.5 STO-4: does this node withhold its delivery status in
  /// the conversation [conversationId]? A group conversation follows the
  /// group's setting, a direct chat the contact's; anything else (channels,
  /// unknown) discloses — channels emit no receipt to withhold.
  bool _withholdsDeliveryStatusInConversation(String conversationId) {
    final group = _groups[conversationId];
    if (group != null) return group.withholdDeliveryStatus;
    return _contacts[conversationId]?.withholdDeliveryStatus ?? false;
  }

  // S388-BAU-KONTAKT: `_markReceiptSuppressed` stood here (finding 1 §8.1,
  // silent discarding of a CONTACT_REQUEST without receipt). Its only
  // caller was `_handleContactRequestV3`; dropped with it.

  // S368: here stood `_findSenderUserIdForKeyRotation` — an Ed25519 scan
  // over all contacts that looked for the matching sender for a
  // KeyRotationBroadcast WITHOUT `senderUserId`. Such a frame came about
  // ONLY on the InfrastructureFrame path (§7.4), and its receive site had
  // ZERO callers and has fallen with this commit. The function was
  // unreferenced afterwards — THE ANALYZER REPORTED IT, not I.
  //
  // The living path carries the sender along: `_handleKeyRotationBroadcast`
  // gets `senderUserId` passed and has nothing to guess.

  /// Single-source-of-truth log message for KEM version rejections (Sec H-5
  /// silent-drop contract). Use from [PerMessageKem.decrypt] catch sites.
  ///
  /// Formerly `cleona_service_v3_delivery.dart:608`. One log line.
  void _warnKemVersionRejected(String context, KemVersionRejectedException e) {
    _log.warn(
        'KEM version rejected for $context (version=${e.receivedVersion}, drop)');
  }

  // ── §5.1 CR edge (formerly cleona_service_v3_retry.dart:54) ──────────

  /// Shortens the running backoff waiting time of pending contact
  /// requests when a connectivity event occurs — `_lastCrRetryPerContact`
  /// is otherwise cleared nowhere edge-triggered.
  ///
  /// ONLY the timestamp is reset, not the counter in
  /// `_crRetryCountPerContact`: the backoff curve is preserved, only the
  /// currently running waiting time is shortened. Otherwise a frequently
  /// firing edge would have kept the backoff permanently at 10s.
  ///
  /// PURE, although the name sounds like network: the method reads
  /// `_contacts` and writes two timestamp maps. Whoever triggers the edge
  /// stands elsewhere.
  void shortenCrBackoffOnEdge(String trigger, {String? onlyUserHex}) {
    final now = DateTime.now();
    var shortened = 0;
    for (final entry in _contacts.entries) {
      if (entry.value.status != 'pending_outgoing') continue;
      if (onlyUserHex != null && entry.key != onlyUserHex) continue;
      // No attempt has run yet -> there is no waiting time to shorten.
      if (!_lastCrRetryPerContact.containsKey(entry.key)) continue;
      if (!CleonaService.crEdgeShortenAllowed(_crEdgeShortenAt[entry.key], now)) {
        continue;
      }
      _crEdgeShortenAt[entry.key] = now;
      _lastCrRetryPerContact.remove(entry.key);
      shortened++;
    }
    if (shortened > 0) {
      _log.info('§5.1 CR edge ($trigger): backoff for $shortened contact(s) '
          'shortened');
    }
  }

  // ── §27.9 NAT wizard: only the persistence ────────────────────────────
  //
  // Formerly `cleona_service_v3_retire.dart:82/95`. The TRIGGER
  // (`_initNatWizardTrigger`, `NatWizardTrigger`) has fallen along and
  // does NOT come back — it read `getNetworkStats()` and
  // `node.statsCollector.uptime`, both without a V4.1 counterpart. The
  // setting itself, however, still has readers: `dismissNatWizard`,
  // `requestNatWizard` and the two test hooks write it, and the user
  // expects a "never again" to survive a restart.

  /// The NAT wizard setting: "until when to no longer ask".
  ///
  /// S362, section 2.3: the file lay open in the profile. It carries a
  /// timestamp and thus the statement that this device sits behind a NAT
  /// that allows no direct connections — a property of the network
  /// environment, i.e. of the DEVICE.
  ///
  /// S366: from its own file into the encrypted store — the store of ONE
  /// identity, area `nat_wizard_settings`: with N identities N independent
  /// values of one device property.
  ///
  /// S403: one row of the DEVICE database (`DeviceStore.areaSettings`, key
  /// [kNatWizardSettingKey]; v4_2 §4.5.3 form 2: "device-wide settings").
  /// What the database of an identity still carries under the old area is
  /// removed at the start of its service, not read
  /// ([_removeSupersededDeviceSettings]). A loss is bearable: the wizard
  /// then asks again, which is annoying, but destroys nothing. A data-loss
  /// latch would therefore not be a protection here, just an additional
  /// source of errors.
  static const String kNatWizardSettingKey = 'nat_wizard';

  void _loadNatWizardSettings() {
    try {
      final j = identity.deviceStoreOrNull
          ?.entry(DeviceStore.areaSettings, kNatWizardSettingKey);
      if (j != null) {
        _natWizardDismissedUntilMs =
            (j['nat_wizard_dismissed_until'] as num?)?.toInt() ?? 0;
      }
    } catch (e) {
      _log.debug('Failed to load nat wizard settings: $e');
    }
  }

  void _saveNatWizardSettings() {
    try {
      final device = identity.deviceStoreForWrite();
      if (device == null) {
        _log.debug('NAT wizard setting not stored: no master seed, so no '
            'device database');
        return;
      }
      device.putEntry(DeviceStore.areaSettings, kNatWizardSettingKey,
          {'nat_wizard_dismissed_until': _natWizardDismissedUntilMs});
    } catch (e) {
      _log.debug('Failed to save nat wizard settings: $e');
    }
  }

  /// Only for the guards: the stored "do not ask until", read from the
  /// device database the way the next start reads it.
  @visibleForTesting
  int get natWizardDismissedUntilMsForTesting {
    _loadNatWizardSettings();
    return _natWizardDismissedUntilMs;
  }

  /// The areas under which the database of an identity carried settings of
  /// the DEVICE until S403. Their rows are removed at the start of the
  /// service and not read — the values lie in the device database, and a
  /// value of one identity is not taken over as the value of the device.
  static const List<String> supersededDeviceSettingAreas = [
    'nat_wizard_settings',
    'multi_interface_mode',
  ];

  void _removeSupersededDeviceSettings() {
    final s = storeOrNull;
    if (s == null) return;
    for (final area in supersededDeviceSettingAreas) {
      try {
        if (s.countArea(area) == 0) continue;
        s.replaceArea(area, const {});
        _log.info('Removed the area "$area" from the store of this identity '
            '— a setting of the device, which lies in the device database '
            'since S403');
      } catch (e) {
        _log.debug('Could not remove the area "$area": $e');
      }
    }
  }

  // ── §5.8 THE V3 OUTBOX IS GONE (S368) ────────────────────────────────
  //
  // Here stood `_loadOutbox`/`_saveOutbox` and with them the area `outbox`
  // of the store. Their justification was explicitly the old stock:
  // "The file `outbox.json` lies in existing profiles and carries messages
  // that the user sees as 'still in transit'."
  //
  // MEASURED before it fell — with five independent patterns, because a
  // zero from a single `grep` is not a zero:
  //   * `_outbox[` — EXACTLY ONE write access in the whole tree, and that
  //     stood in `_loadOutbox` itself. The ledger filled itself exclusively
  //     from itself.
  //   * `_OutboxEntry(` — only the constructor and `fromJson`. No producer.
  //   * `canonicalPacketB64` — in `lib/` only the field declaration.
  //   * `_outbox.` — exclusively reading, counting, removing and clearing.
  //   * `'outbox'` as area name — only the constant itself.
  // The comment said it already: "WHAT THIS OLD LEDGER LACKS: the FILLER
  // and the DRAIN." What remained was a ledger that was read, reported and
  // written back — and from which nothing ever went out.
  //
  // Owner, 05.09.2026: "There are no old profiles!!", "Nothing is
  // migrated!", "Neither data - nor in the network!". `FirstStartWipe` lets no
  // profile of the 3.2 line through to here; the entries this path was
  // meant to spare cannot exist.
  //
  // THE V4.1 OUTBOX NEXT TO IT IS UNAFFECTED BY THIS and carries everything
  // that really goes out ([loadLocalOutbox]/[saveLocalOutbox], drain
  // `flushV41Outbox`).

  // ── THE V4.1 OUTBOX (§21.2/§21.8, gap G-4) ────────────────────────
  //
  // Two ledgers, ONE area per ledger, and they must not be confused:
  // [kOutboxArea] carries serialised `NetworkPacket` bytes of an old
  // profile and is only read and written (see above); [kLocalOutboxArea]
  // carries PLAINTEXT `ApplicationFrame`, from which a resubmission
  // seals FRESHLY (§22.5.1 refinement 3).
  //
  // UNDER THE DB KEY, and that is normative: §21.8 lists "own,
  // not-yet-placed cells (outbox) | own messages including recipient |
  // **under the DB key**". The frame is plaintext and names recipient and
  // content.
  //
  // S366: THE CARRIER IS THE STORE, no longer `v41_outbox.json`.
  // Until then it said here that the frame went "exclusively through
  // `_fileEnc` (XSalsa20-Poly1305)". That was the file's path; the key has
  // stayed the same (`HdWallet.deriveFileEncKey`), the ciphertext is now
  // that of the store (ChaCha20-Poly1305 via SQLite Multiple Ciphers).
  // §21.8 requires "under the DB key", and that is exactly where the area
  // lies.
  //
  // Writing happens INDIVIDUALLY (`putEntry`/`removeEntry`) via the
  // journal in [LocalOutbox]: 2048 entries of up to 32 KiB each are not a
  // stock one rewrites entirely because of one receipt.

  /// Reads the ledger from the profile.
  ///
  /// PUBLIC, unlike `_loadOutbox` next to it, and for a reason: this is the
  /// seam between profile and outbox, and it is the ONLY place at which it
  /// can be checked whether a restart keeps the parked messages. A guard
  /// cannot call `startService()` (sockets, partners, clock) and would then
  /// have had to rebuild the proof — a rebuilt proof checks the rebuild.
  /// `test/smoke/smoke_local_outbox.dart` therefore calls it directly.
  void loadLocalOutbox() {
    try {
      final skipped = localOutbox.loadJson(store.loadArea(kLocalOutboxArea));
      // NO `markSaved()` HERE. What `loadJson` notes are exclusively
      // deletions — broken records and what the cap displaced. Discarding
      // them now would leave the store standing above the memory state;
      // the next [saveLocalOutbox] cleans them up.
      if (localOutbox.length > 0 || skipped > 0) {
        _log.info('V4.1-Outbox: ${localOutbox.length} entries loaded '
            '(${localOutbox.bytes} B'
            '${skipped > 0 ? ", $skipped kaputte uebersprungen" : ""}). '
            'They go out again at the next readiness edge '
            '(§21.2).');
      }
    } catch (e) {
      // NO START ERROR, but no silent overwriting either: if the file stays
      // unreadable, that stands in the log, and the next write recreates
      // it. A throw here would have prevented the whole service from
      // starting — for a ledger whose loss costs messages, but no identity.
      _log.warn('V4.1 outbox: loading failed ($e) — the parked '
          'messages of this profile are lost');
    }
  }

  /// Writes the ledger if it has changed.
  ///
  /// SYNCHRONOUSLY AND IMMEDIATELY, not via a clock. The outbox is the only
  /// place where an own message not yet proven stands; a crash between
  /// sending and the next tick would cost exactly the message it exists
  /// for. The file is small (a text measures ~250-400 B, measured), and
  /// `writeJsonFile` writes via side files — there is no half-written
  /// ledger.
  void saveLocalOutbox() {
    if (!localOutbox.dirty) return;
    try {
      // FIRST DELETE, THEN WRITE. The two sets in the journal are mutually
      // exclusive (`_vormerkenChanged`/`…Removed`), so the order cannot hit
      // a row just written — it is nevertheless fixed here so that it is
      // not accidental.
      for (final k in localOutbox.removedKeys.toList()) {
        store.removeEntry(kLocalOutboxArea, k);
      }
      for (final k in localOutbox.changedKeys.toList()) {
        final e = localOutbox.lookup(k);
        if (e == null) continue;
        store.putEntry(kLocalOutboxArea, k, e.toJson());
      }
      // ONLY AFTER successful writing. A failure leaves the journal
      // standing and the next call catches up — the same order as with
      // `host.markPrekeyStateSaved`.
      localOutbox.markSaved();
    } catch (e) {
      _log.warn('V4.1 outbox: saving failed ($e)');
    }
  }

  // ── §5.6 mailbox transition: only the persistence now ─────────────────
  //
  // `_primaryMailboxId()` and `_activeMailboxIds()` are NOT brought back:
  // their only purpose was under which identifiers fragments and S&F
  // messages are to be collected, and both collection paths have fallen.
  // Their last caller outside of that was `rotateIdentityKeys`, and that
  // aborts today before the first step.
  //
  // What REMAINS is the transition state itself: `cleona_service_lockout`
  // writes it (§14.4 lock-out transition), and it must survive a restart.

  void _loadMailboxTransition() {
    try {
      // S366: ONE entry under [kEinzelzustandKey] in the area
      // `mailbox_transition` instead of the file of the same name.
      final json =
          store.loadArea(kMailboxTransitionArea)[kSingleStateKey];
      _mailboxTransitionLoaded = true;
      if (json == null) return;
      final hexId = json['previousMailboxPrimary'] as String?;
      final setAtMs = json['setAtMs'] as int?;
      if (hexId != null && setAtMs != null) {
        final setAt = DateTime.fromMillisecondsSinceEpoch(setAtMs);
        if (DateTime.now().difference(setAt).inDays <
            CleonaService._mailboxTransitionDays) {
          _previousMailboxPrimary = hexToBytes(hexId);
          _previousMailboxPrimarySetAt = setAt;
          _log.info('Mailbox transition: loaded previous primary '
              '(age: ${DateTime.now().difference(setAt)})');
        } else {
          store.removeEntry(
              kMailboxTransitionArea, kSingleStateKey);
        }
      }
    } catch (e) {
      // Do NOT mark as loaded — otherwise the latch in
      // [_saveMailboxTransition] wrongly considers the memory state
      // authoritative.
      _log.debug('Mailbox transition: load failed: $e');
    }
  }

  void _saveMailboxTransition() {
    // DATA-LOSS LATCH (S366) — NEWLY BUILT, there was none here.
    //
    // THE FINDING: `_previousMailboxPrimary == null` meant "delete", and
    // exactly this state was also left behind by a FAILED load. An
    // unreadable memory state and an expired transition could not be
    // distinguished — the first call after a read error would have deleted
    // the transition, and with it §5.6: inbound messages under the old
    // line then count as foreign. The latch fails closed if the store is
    // not readable.
    if (!_mailboxTransitionLoaded && _previousMailboxPrimary == null) {
      var present = false;
      try {
        present = store.countArea(kMailboxTransitionArea) > 0;
      } catch (e) {
        _log.warn(
            'Mailbox transition: REFUSED to save — store not readable: $e');
        return;
      }
      if (present) {
        _log.warn('Mailbox transition: REFUSED to clear — loading failed, '
            'but the store holds a transition. Would cause data loss!');
        return;
      }
    }
    try {
      if (_previousMailboxPrimary == null) {
        store.removeEntry(kMailboxTransitionArea, kSingleStateKey);
        return;
      }
      // One object, one entry — `replaceArea` thus keeps the area at
      // exactly one row and clears old stock away too.
      store.replaceArea(kMailboxTransitionArea, {
        kSingleStateKey: {
          'previousMailboxPrimary': bytesToHex(_previousMailboxPrimary!),
          'setAtMs': _previousMailboxPrimarySetAt!.millisecondsSinceEpoch,
        }
      });
    } catch (e) {
      _log.warn('Mailbox transition: save failed: $e');
    }
  }

  // ── Anonymous poll votes: FALLEN ──────────────────────────────
  //
  // `handleIncomingPollAnonSubmit` / `…Ack` were one-liners on `_polls`.
  // They are (T), but not because of their body: `PollService` lost the
  // two counterparts with the CUT, because the whole procedure hung on the
  // V3 re-broadcaster (§4b.1: "removed without replacement"). A delegate
  // to a method that does not exist would not be preservation, but a
  // compile error.

  // ── Identity registry in the network ────────────────────────────────────
  //
  // Formerly `cleona_service_v3_delivery.dart:443/525` (`pollRegistryFromDht`
  // / `storeRegistryInDht`), removed in the V3 demolition.
  //
  // GAP G-5, NOT (T). What is missing is the STORAGE PLACE — the V3 DHT in
  // which the erasure-coded fragments lay. §7 (multi-identity) keeps the
  // registry as a subject, but V4.1 has no pollable third party (the
  // paragraph bridge in CLAUDE.md says explicitly about §4.3 "replaced,
  // not renumbered").
  //
  // ADDENDUM 08.09.2026 (S376): here it said that `IdentityDhtRegistry` and
  // the Reed-Solomon codec lived on "unchanged". The class has been
  // DELETED (owner decision V-11 = A) — it had zero callers in `lib/` and
  // produced fragments for a network that does not exist. The Reed-Solomon
  // codec stays, it has other consumers. Gap G-5 is thus NOT closed, only
  // separated from its component: the replacement per v4_1 §13.7
  // (derivation instead of directory) is outstanding.
  //
  // Both places therefore fail LOUDLY and with a reason, instead of
  // returning `null` or `false` like an empty network. The difference is
  // load-bearing: `null` would have told the recovery "no registry found"
  // and let the user create a second identity that the HD counter would
  // then have assigned twice.

  /// Poll the network for identity registry fragments after seed recovery.
  ///
  /// Gap G-5 — no storage place in V4.1.
  Future<({List<Map<String, dynamic>> identities, int nextIndex})?>
      pollRegistryFromDht(Uint8List masterSeed) async {
    _log.error('Identity registry: collecting not possible — V4.1 has '
        'no storage location for the erasure-coded fragments (gap '
        'G-5). The replacement per v4_1 §13.7 — derivation instead of directory '
        '— is not built; `IdentityDhtRegistry` was deleted on 08.09.2026 '
        'because it built for a network that does not exist.');
    throw UnsupportedError(
        'pollRegistryFromDht: V4.1 has no registry storage location (G-5). '
        'A silent `null` would be dangerous here — the restore '
        'reads it as "no further identities" and assigns HD indices '
        'twice.');
  }

  /// Store the current identity registry in the network.
  ///
  /// Gap G-5 — no storage place in V4.1.
  Future<bool> storeRegistryInDht(Uint8List masterSeed,
      List<({int? hdIndex, String name})> identities, int nextIndex) async {
    _log.error('Identity registry: storing not possible — V4.1 has '
        'no storage location (gap G-5). ${identities.length} identity(ies), '
        'nextIndex=$nextIndex NOT published.');
    return false;
  }

  /// Fire-and-forget: publish identity registry after a rename.
  ///
  /// Stays as ONE place at which gap G-5 shows up in the log, instead of
  /// vanishing at three call sites.
  void _publishIdentityRegistryIfPossible() {
    if (identity.masterSeed == null) return;
    final mgr = IdentityManager();
    final identities = mgr.loadIdentities();
    final entries = identities
        .map((i) => (hdIndex: i.hdIndex, name: i.displayName))
        .toList();
    unawaited(storeRegistryInDht(
        identity.masterSeed!, entries, mgr.nextHdIndex()));
  }

  // ── §5.8 THE APP'S MEMBERSHIP RESEND QUEUE IS GONE (S408 P19) ───────
  //
  // Here stood a queue of its own: a group or channel update that
  // `sendToUser` did not take over was parked per (entity, recipient),
  // persisted in the area `membership_resend`, sent again at every network
  // change and closed after 14 days (D-47, S407-STILLE F-9). It repeated
  // above the transport what the delivery layer does itself: a message
  // without a way RESTS in the sender's history and leaves again at the
  // edges of §8.2, closed after 14 days (§9.3, D-47; `mailbox_outbound.dart`
  // `kOutboundDeadline`) — and `sendToUser` answers `false` only when
  // nothing was taken over and nothing ever will be (§22.5.1). §11.3a: the
  // layers above "do not repeat, count or time anything themselves".

  /// The rows the queue left in a profile of an earlier 4.2 version: read
  /// by nobody any more, so they go (an older 4.2 that reads the area again
  /// finds it empty — the state it starts from anyway).
  void _membershipResendRows() {
    try {
      for (final k in store.loadArea(kMembershipResendArea).keys.toList()) {
        store.removeEntry(kMembershipResendArea, k);
      }
    } catch (e) {
      _log.warn('Membership resend rows: not removed: $e');
    }
  }

  /// Removes what a previous 4.2 left in [kRotationWindowArea]: per contact
  /// an old V4.1 pair key and a deadline, read by nothing since S408-P23. A
  /// key without a reader does not stay on the disk. An older 4.2 that finds
  /// the area empty starts without a window — its state before any rotation.
  void _rotationWindowRows() {
    try {
      for (final k in store.loadArea(kRotationWindowArea).keys.toList()) {
        store.removeEntry(kRotationWindowArea, k);
      }
    } catch (e) {
      _log.warn('Rotation window rows: not removed: $e');
    }
  }

  // ── S368: THE ONE-TIME MIGRATION deviceNodeId -> userIdHex IS GONE ────
  //
  // Here stood `_migrateDeviceNodeIdToUserId`, `_findOurOldMemberKey` and
  // `_isOurOldKey` — together around 130 lines that ran at EVERY start over
  // all groups, channels and conversations and rewrote the own row from an
  // old key (`deviceNodeId`) to the new one (`userIdHex`). The header
  // comment named the reason itself: "old profiles with the wrong key
  // still lie on disk, so it must keep running at start."
  //
  // Exactly those no longer exist. The error arose in V3.1.44; a profile
  // from that time does not reach V4.1 (`FirstStartWipe`), and the owner
  // ruled it out six times literally on 05.09.2026 ("There are no
  // old profiles!!", "Nothing is migrated!").
  //
  // The price, named: if, against expectation, such a profile were present
  // after all, the user would stand in their own groups under the old key.
  // That is not a step back from the target state, but its consequence —
  // such a profile must not reach this version at all.


  // ── §26.6.2 package C: who has the key rotation ─────────────────────
  //
  // The broadcast is an ordinary sending of the delivery layer (§4.5.4,
  // §14.4): without a way it rests and leaves again at every edge, placed it
  // waits for the contact's collection, and the delivery layer alone closes
  // it as failed — after 14 days without a way (§9.3, D-47). Until
  // S408-LEBENSLAUF P20 a 24-hour timer here counted "attempts" per contact
  // without sending anything (the V4.1 carrier had fallen, gap G-3) and
  // declared a contact not reached after three of them or 90 days — a clock
  // and a count above the transport (§11.3a, working rule 5). Now the state
  // follows the delivery state: read at the edges start and network change
  // (and when the state is asked for), a broadcast the delivery layer closed
  // as failed makes its contact `expired`; the `KEY_ROTATION_ACK` makes it
  // `acked` ([_handleKeyRotationAck]).
  void _keyRotationFromDelivery() {
    final p = myceliumMailbox;
    if (p != null && _keyRotationRetry.hasActiveRotation) {
      for (final MapEntry(key: hex, value: sending)
          in _keyRotationRetry.pendingSendings.entries) {
        final c = _contacts[hex];
        final address = c == null ? null : _myceliumKnownAddress(p, c);
        if (address == null) continue;
        final failed = p.historyFor(address).entries.any((e) =>
            e.state == mycelium.DeliveryState.failed &&
            bytesToHex(e.identifier) == sending);
        if (failed) _keyRotationRetry.markFailed(hex);
      }
    }
    _emitKeyRotationRetryEvents();
  }

  /// Drain new `expired` transitions into IPC events. Idempotent — if there
  /// is nothing to report this is a no-op.
  void _emitKeyRotationRetryEvents() {
    final newlyExpired = _keyRotationRetry.drainNewlyExpired();
    if (newlyExpired.isEmpty) return;
    final listener = onKeyRotationPendingExpired;
    if (listener == null) return;
    for (final hex in newlyExpired) {
      try {
        listener(hex, _keyRotationRetry.pendingCount);
      } catch (e) {
        _log.warn('onKeyRotationPendingExpired listener threw: $e');
      }
    }
  }

  // ── §19.6 update manifest: the local half ───────────────────────
  //
  // Formerly `cleona_service_v3_binary.dart:129`. The body reads the
  // manifest from disk, CHECKS THE maintainer's SIGNATURE and stores it in
  // the local fragment store. None of it is network — and without it
  // `_latestManifest` would stay empty, whereby the invitation link
  // (binary hashes, version) and the update display would vanish.
  //
  // The PUSH to other nodes has fallen (gap G-18, named in the body).
  void _selfPublishManifest() {
    try {
      var manifestPath = '${AppPaths.dataDir}${Platform.pathSeparator}update_manifest.json';
      var file = File(manifestPath);
      if (!file.existsSync()) {
        manifestPath = '${AppPaths.dataDir}${Platform.pathSeparator}update_manifest_cache.json';
        file = File(manifestPath);
        if (!file.existsSync()) return;
      }
      final jsonData = file.readAsStringSync();
      final checker = UpdateChecker(log: _log);
      final manifest = checker.verifyManifest(jsonData);
      if (manifest == null) {
        _log.warn('[update] update_manifest.json has invalid signature — ignoring');
        return;
      }
      final depositCompartment = UpdateManifest.manifestStoreTag();
      final data = Uint8List.fromList(utf8.encode(jsonData));
      final messageId = SodiumFFI().sha256(data);
      final storeRes = mailboxStore.storeFragment(StoredFragment(
        mailboxId: depositCompartment,
        messageId: messageId,
        fragmentIndex: 0,
        totalFragments: 1,
        requiredFragments: 1,
        data: data,
        originalSize: data.length,
        expiresAt: DateTime.now().add(const Duration(days: 30)),
      ));
      final isNew = _latestManifest == null ||
          checker.isNewer(manifest.version, _latestManifest!.version);
      if (isNew) _latestManifest = manifest;
      if (storeRes == FragmentStoreResult.stored) {
        _log.info('[update] Manifest v${manifest.version} stored locally');
      }
      // S406-UPD, finding U-3: the carrier gets the manifest at once, so
      // the next moment of §26.5.4 places it in the post box. Without a
      // carrier (start, before the host runs) the setter reads the file.
      final carrier = _updateCarrierField[this];
      if (carrier != null) {
        carrier.manifestKnown(data);
        _ownObjectsHold(carrier);
        _log.info('[update] Manifest v${manifest.version} handed to the '
            'update carrier');
        return;
      }
      // FORMERLY `_pushManifestToPeers(data)` (gap G-18, fell with
      // `lib/core/network/`). Since S387 the update carrier places the
      // manifest in the post box (§26.5.4); since S406 it gets it from here
      // (above) or, at start, from the file (`ownManifestsToCarrier`).
      _log.info('[update] Manifest v${manifest.version} stored locally; '
          'the update carrier takes it over when the host starts');
    } catch (e) {
      _log.debug('[update] Self-publish manifest failed: $e');
    }
  }

  // ── §19.6 binary distribution: the local halves ────────────────────
  //
  // Formerly `cleona_service_v3_binary.dart`. Both bodies read and write
  // exclusively the local `UpdateBinaryStore` (until S407 they also
  // computed Reed-Solomon fragments from the binary; since
  // S407-UPDATEFRAGMENTE only the complete object is stored). The only
  // network reference was the
  // line `node.binaryHasContentToShare = true` — a node-wide flag that now
  // hangs as a field on the service (see there).
  // `_buildBinaryAvailabilityRecords` stood here: the snapshot of what this
  // node holds, announced on Nostr relays every 4 hours by
  // `BinaryRendezvousManager`. Both fell with V9 A1 (owner decision
  // 08.10.2026; v4_2 §26.6.4 "no external rendezvous channel"). A node holds
  // its objects for others through the update carrier instead
  // (`_ownObjectsHold`), and an on-demand foreign binary is not held.

  /// Self-seed: store the currently-running binary as the complete object
  /// so this node becomes a source for its own platform/version immediately
  /// at startup, without waiting for an update download (§26.6.1, §26.6.5).
  /// Only meaningful for sideloaded installs — Play Store builds never
  /// self-update, so seeding their own binary serves no purpose.
  ///
  /// Until S407 the measure for "already seeded" was the presence of
  /// Reed-Solomon fragments: a directory with `complete.bin` and no
  /// fragments was seeded again on every start. The measure is the
  /// complete object (S407-UPDATEFRAGMENTE).
  Future<void> _selfSeedCurrentBinary() async {
    final platform = Platform.operatingSystem;
    final version = CleonaService.kCurrentAppVersion;
    if (_updateBinaryStore!.hasCompleteSync(platform, version)) {
      _log.debug('[update] Already seeded $platform/$version (complete object)');
      return;
    }
    try {
      final binaryPath = await _resolveCurrentBinaryPath();
      if (binaryPath == null) return;
      if (!File(binaryPath).existsSync()) {
        _log.debug('[update] Binary not found at $binaryPath — skip self-seed');
        return;
      }
      final expectedHash = _latestManifest?.binaryHashes?[platform];
      final profileDir = _updateBinaryStore!.profileDir;
      final result = await CleonaService._runSeedIsolate(
          binaryPath, profileDir, platform, version,
          expectedHash: expectedHash);
      if (result != null) {
        _log.info('[update] Self-seeded $platform/$version as the complete '
            'object (${result.bytes} bytes)');
        binaryHasContentToShare = true;
      }
    } catch (e) {
      _log.warn('[update] Self-seed failed: $e');
    }
  }

  /// IPC entry: take a binary file from disk into the local fragment store
  /// and thus make this device a source (§19.6.2).
  ///
  /// ── RESTORED ON 02.09.2026, AND WHY THAT IS NOT A STEP BACK
  ///
  /// The body lay in `cleona_service_v3_binary.dart` and fell with the CUT
  /// as a whole file (`7f1b19b9`), the associated IPC case one commit
  /// later (`91b566dd`). The comment that remained there justifies this
  /// with "the successor is named and unbuilt" and refers to the fountain
  /// content layer (AP-7).
  ///
  /// **This justification does not apply to the body**, measured on the
  /// same tree: what it touches is exclusively local. It reads a file,
  /// has it Reed-Solomon-encoded in an isolate
  /// (`CleonaService._runSeedIsolate` -> `_selfSeedInIsolate`) and stores
  /// the fragments in the `UpdateBinaryStore` of the profile directory.
  /// No wire, no frame, no routing table. The header of THIS file already
  /// says so literally for the neighbouring methods: "Both bodies read and
  /// write exclusively the local `UpdateBinaryStore` … The only network
  /// reference was the line `node.binaryHasContentToShare = true`."
  /// Exactly this one line is the difference to the original: today it
  /// hangs as a field on the service (`cleona_service.dart:391`), not on
  /// the node.
  ///
  /// The announcement over Nostr that followed the seed until 08.10.2026
  /// (`BinaryRendezvousManager`) fell with V9 A1 (§26.6.4).
  /// `_selfSeedCurrentBinary` directly above does the same at start; this
  /// entry does nothing the node does not do at every start anyway, only
  /// with a file named by the caller instead of its own.
  ///
  /// ── DEVIATIONS FROM THE RESTORED ORIGINAL ───────────────────
  ///
  /// (1) The answer additionally carries `platform` and `version`. The
  /// original only returned `{fragmentCount, hash}` — which is why
  /// `test/e2e/tests/binary-update.spec.ts:33-34` **could never pass even
  /// back then**, when the command still existed: test and body come from
  /// the same commit (`11c8c9df`), and the two fields were expected there
  /// but never delivered. An answer that names its own input values is
  /// the right side of this contradiction. Since S407-UPDATEFRAGMENTE the
  /// answer names the stored object's size (`bytes`) instead of a
  /// fragment count.
  ///
  /// (2) The file is read ZERO times in the caller (S404). Until S404 this
  /// method did a `readAsBytes` only to compute the SHA-256 — with a ~200 MB
  /// APK that was the first of three full copies in memory and contributed
  /// to the OOM kill of the bootstrap daemon (515.7 MB peak, 03.10.2026).
  /// Today the isolate streams the file (see [seedBinaryFileToStore]) and
  /// returns the hash of the file that was actually stored — no
  /// measurement before, no copy after, no gap between the two.
  ///
  /// (3) Until S407 the command took `maxFragments` (how many Reed-Solomon
  /// fragments to store, default 50 = "bootstrap=all" of §19.6.2 in the
  /// 3.x line). Fragments are no longer stored (S407-UPDATEFRAGMENTE).
  Future<Map<String, dynamic>> seedBinaryFromFile(
      String platform, String version, String filePath) async {
    final store = _updateBinaryStore;
    if (store == null) return {'error': 'update store not initialized'};
    final file = File(filePath);
    // Wording "file not found" deliberately kept: it is the distinguishable
    // case compared with "could not encode" — the isolate returns only
    // null (missing file / hash mismatch) or a result for both others.
    if (!file.existsSync()) return {'error': 'file not found: $filePath'};
    try {
      final result = await CleonaService._runSeedIsolate(
          filePath, store.profileDir, platform, version);
      if (result == null) {
        return {'error': 'seeding stored nothing for $platform/$version'};
      }
      binaryHasContentToShare = true;
      // Housekeeping at once: an operator seeding over a directory of the
      // 3.x layout does not wait up to an hour for its fragments to go.
      unawaited(_runBinaryFragmentGc());
      return {
        'bytes': result.bytes,
        'hash': result.binaryHash,
        'platform': platform,
        'version': version,
      };
    } catch (e) {
      return {'error': '$e'};
    }
  }

  Future<String?> _resolveCurrentBinaryPath() async {
    if (Platform.isAndroid) {
      final resolver = CleonaService.apkPathResolver;
      if (resolver == null) return null;
      try {
        return await resolver();
      } catch (e) {
        _log.debug('[update] Failed to resolve APK path: $e');
        return null;
      }
    }
    return Platform.resolvedExecutable;
  }
}
