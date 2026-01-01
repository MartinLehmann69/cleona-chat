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
const String kV41OutboxArea = 'v41_outbox';

/// The mailbox transition (formerly `mailbox_transition.json`), §5.6.
const String kMailboxTransitionArea = 'mailbox_transition';

/// Ausstehende Mitgliedschafts-Nachsendungen (vormals
/// `membership_resend.json`), §5.8.
const String kMembershipResendArea = 'membership_resend';

/// Pending two-stage media sends (formerly
/// `pending_media_sends.json`), §5.5/§5.6.
///
/// Unlike the four named above, this file did NOT lie encrypted in the
/// profile, but naked: `writeAsStringSync(jsonEncode(...))`, neither via
/// `FileEncryption` nor atomically. It named in plaintext the storage
/// location and the file name of every pending attachment.
const String kPendingMediaSendsArea = 'pending_media_sends';

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

  /// Area of the store for the NAT wizard setting (§21.4.1).
  ///
  /// S362, section 2.3: the file lay open in the profile. It carries a
  /// timestamp ("until when to no longer ask") and thus the statement that
  /// this device sits behind a NAT that allows no direct connections — a
  /// property of the network environment.
  ///
  /// S366: it no longer lies in its own file, but in the encrypted store.
  /// A state with ONE field — hence one entry under `_` and `replaceArea`,
  /// as with the other settings. A loss is bearable: the wizard then asks
  /// again, which is annoying, but destroys nothing. A data-loss latch
  /// would therefore not be a protection here, just an additional source
  /// of errors.
  static const String _areaNatWizard = 'nat_wizard_settings';

  void _loadNatWizardSettings() {
    try {
      final j = store.loadArea(_areaNatWizard)['_'];
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
      store.replaceArea(_areaNatWizard, {
        '_': {'nat_wizard_dismissed_until': _natWizardDismissedUntilMs},
      });
    } catch (e) {
      _log.debug('Failed to save nat wizard settings: $e');
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
  // that really goes out ([loadV41Outbox]/[saveV41Outbox], drain
  // `flushV41Outbox`).

  // ── THE V4.1 OUTBOX (§21.2/§21.8, gap G-4) ────────────────────────
  //
  // Two ledgers, ONE area per ledger, and they must not be confused:
  // [kOutboxArea] carries serialised `NetworkPacketV3` bytes of an old
  // profile and is only read and written (see above); [kV41OutboxArea]
  // carries PLAINTEXT `ApplicationFrameV3`, from which a resubmission
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
  // journal in [V41Outbox]: 2048 entries of up to 32 KiB each are not a
  // stock one rewrites entirely because of one receipt.

  /// Reads the ledger from the profile.
  ///
  /// PUBLIC, unlike `_loadOutbox` next to it, and for a reason: this is the
  /// seam between profile and outbox, and it is the ONLY place at which it
  /// can be checked whether a restart keeps the parked messages. A guard
  /// cannot call `startService()` (sockets, partners, clock) and would then
  /// have had to rebuild the proof — a rebuilt proof checks the rebuild.
  /// `test/smoke/smoke_v41_outbox.dart` therefore calls it directly.
  void loadV41Outbox() {
    try {
      final skipped = v41Outbox.loadJson(store.loadArea(kV41OutboxArea));
      // NO `markSaved()` HERE. What `loadJson` notes are exclusively
      // deletions — broken records and what the cap displaced. Discarding
      // them now would leave the store standing above the memory state;
      // the next [saveV41Outbox] cleans them up.
      if (v41Outbox.length > 0 || skipped > 0) {
        _log.info('V4.1-Outbox: ${v41Outbox.length} entries loaded '
            '(${v41Outbox.bytes} B'
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
  void saveV41Outbox() {
    if (!v41Outbox.dirty) return;
    try {
      // FIRST DELETE, THEN WRITE. The two sets in the journal are mutually
      // exclusive (`_vormerkenChanged`/`…Removed`), so the order cannot hit
      // a row just written — it is nevertheless fixed here so that it is
      // not accidental.
      for (final k in v41Outbox.removedKeys.toList()) {
        store.removeEntry(kV41OutboxArea, k);
      }
      for (final k in v41Outbox.changedKeys.toList()) {
        final e = v41Outbox.lookup(k);
        if (e == null) continue;
        store.putEntry(kV41OutboxArea, k, e.toJson());
      }
      // ONLY AFTER successful writing. A failure leaves the journal
      // standing and the next call catches up — the same order as with
      // `host.markPrekeyStateSaved`.
      v41Outbox.markSaved();
    } catch (e) {
      _log.warn('V4.1 outbox: saving failed ($e)');
    }
  }

  /// §5.1 F3': proven inbound from [senderUserHex] — the THIRD edge of the
  /// outbox drain (§21.2).
  ///
  /// ── WHAT THIS EDGE PROVES, BUT THE OTHER TWO DO NOT ────────
  ///
  /// The frame is completely checked, so the counterpart is demonstrably
  /// reachable. Restart and readiness change say something about THIS
  /// node; only this edge says something about the RECEIVER — the case
  /// that no sender-side edge can see.
  ///
  /// THROTTLED via [CleonaService._outboxInboundFlushGate] (60 s per
  /// sender): a chatty sender must not re-trigger a still failing drain on
  /// every frame. **This is not a timer in the sense of §21.2** — the
  /// throttle TRIGGERS NOTHING, it only suppresses; without an inbound
  /// frame nothing ever happens.
  ///
  /// S368: next to it here stood a report about the V3 outbox ("its
  /// entries stay behind"). The V3 outbox has fallen — it had no filler,
  /// so nothing to report either.
  void _maybeFlushOutboxForSender(String senderUserHex) {
    final v41Parked = v41Outbox.entries
        .any((e) => e.recipientUserId.hex == senderUserHex);
    if (!v41Parked) return;
    final last = _outboxInboundFlushAt[senderUserHex];
    if (last != null &&
        DateTime.now().difference(last) <
            CleonaService._outboxInboundFlushGate) {
      return;
    }
    _outboxInboundFlushAt[senderUserHex] = DateTime.now();
    if (v41Parked) {
      // NOT filtered by sender, and that is intentional: the drain orders
      // by age and keeps the egress cap. A sender-filtered selection would
      // let a chatty contact drain its messages before all others — with a
      // cap of two resubmissions per edge that would be a preference for
      // which there is no reason.
      flushV41Outbox(
          reason: 'Inbound from ${senderUserHex.substring(0, 8)}');
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

  // ── §5.8 Pending membership resends ──────────────────
  //
  // Formerly `cleona_service_v3_retry.dart:277/295/473`. PURE: the three
  // bodies read `_groups`/`_channels`, write a JSON file and send via
  // [sendToUser] — i.e. via the V4.1 switch, not via V3. They lay in the
  // retry file because the EDGE lay there, not the content.

  // S366: area `membership_resend` instead of a file. **One row per
  // entity**, written via [_persistMembershipResend] — this collection has
  // NO cap (neither on the number of groups/channels nor on the recipients
  // per entry), and a stock without a cap should not be rewritten entirely
  // on every change.
  //
  // THE FORM IS `{'recipients': [...]}` AND NOT THE BARE LIST: an entry of
  // the store is an object (`Map<String, dynamic>`), not an array. An
  // enclosing name costs nothing and later allows a second field without
  // every old row becoming unreadable.

  void _loadPendingMembershipResends() {
    try {
      for (final entry in store.loadArea(kMembershipResendArea).entries) {
        final list = entry.value['recipients'] as List<dynamic>?;
        if (list == null) {
          _log.warn('Membership resend: entry ${entry.key} without '
              'recipient list, skipped');
          continue;
        }
        _pendingMembershipResends[entry.key] =
            list.map((e) => e as String).toSet();
      }
      _membershipResendsLoaded = true;
      if (_pendingMembershipResends.isNotEmpty) {
        _log.info('Membership resend: loaded ${_pendingMembershipResends.length} entities');
      }
    } catch (e) {
      // Do NOT mark as loaded: see latch below.
      _log.warn('Membership resend: load failed: $e');
    }
  }

  /// Writes EXACTLY ONE entity — or removes it if nothing is pending for
  /// it in memory any more.
  void _persistMembershipResend(String entityId) {
    // DATA-LOSS LATCH (S366) — NEWLY BUILT, there was none here.
    //
    // With single writes no foreign entry can get lost; but THIS one can,
    // if the memory state is not valid at all: after a failed load
    // `_pendingMembershipResends[entityId]` is `null`, and that would mean
    // "delete" here — although the store could hold recipients who have
    // never received an invitation.
    if (!_membershipResendsLoaded) {
      _log.warn('Membership resend: REFUSED to persist $entityId — loading '
          'failed, the stored state is not authoritative');
      return;
    }
    try {
      final recipient = _pendingMembershipResends[entityId];
      if (recipient == null || recipient.isEmpty) {
        store.removeEntry(kMembershipResendArea, entityId);
      } else {
        store.putEntry(kMembershipResendArea, entityId,
            {'recipients': recipient.toList()});
      }
    } catch (e) {
      _log.warn('Membership resend: persist $entityId failed: $e');
    }
  }

  // THERE IS NO FULL WRITING ANY MORE. Here stood
  // `_savePendingMembershipResends`, and after the switch-over it had no
  // caller any more: all three writing paths (two broadcasts, the drain)
  // change EXACTLY ONE entity and call [_persistMembershipResend]. Leaving
  // a method standing that can replace the whole stock would not be a
  // spare part here, but the only remaining place at which an empty set
  // could delete everything.

  Future<void> _flushPendingMembershipResends() async {
    if (_pendingMembershipResends.isEmpty) return;
    _log.info('Membership resend flush: ${_pendingMembershipResends.length} entities');
    final toRemoveEntities = <String>[];
    for (final entry in _pendingMembershipResends.entries.toList()) {
      final entityId = entry.key;
      final recipients = entry.value;
      final group = _groups[entityId];
      final channel = _channels[entityId];
      if (group == null && channel == null) {
        toRemoveEntities.add(entityId);
        continue;
      }
      final succeeded = <String>{};
      final stale = <String>{};
      final Uint8List inviteBytes;
      final proto.MessageTypeV3 msgType;
      final bool Function(String) isMember;
      final Uint8List? Function(String) memberX25519;
      final Uint8List? Function(String) memberMlKem;
      final Uint8List? Function(String) memberEd25519;
      if (group != null) {
        inviteBytes = _buildSignedGroupInviteBytes(group);
        msgType = proto.MessageTypeV3.MTV3_GROUP_INVITE;
        isMember = group.members.containsKey;
        memberX25519 = (h) => group.members[h]?.x25519Pk;
        memberMlKem = (h) => group.members[h]?.mlKemPk;
        memberEd25519 = (h) => group.members[h]?.ed25519Pk;
      } else {
        inviteBytes = _buildSignedChannelInviteBytes(channel!);
        msgType = proto.MessageTypeV3.MTV3_CHANNEL_INVITE;
        isMember = channel.members.containsKey;
        memberX25519 = (h) => channel.members[h]?.x25519Pk;
        memberMlKem = (h) => channel.members[h]?.mlKemPk;
        memberEd25519 = (h) => channel.members[h]?.ed25519Pk;
      }
      final entityIdBytes = hexToBytes(entityId);
      for (final recipientHex in recipients) {
        if (!isMember(recipientHex)) {
          stale.add(recipientHex);
          continue;
        }
        final (x25519Pk, mlKemPk, ed25519Pk) = _resolveMemberKeys(recipientHex,
            memberX25519Pk: memberX25519(recipientHex),
            memberMlKemPk: memberMlKem(recipientHex),
            memberEd25519Pk: memberEd25519(recipientHex));
        if (x25519Pk == null || mlKemPk == null) continue;
        try {
          final ok = await sendToUser(
            recipientUserId: hexToBytes(recipientHex),
            messageType: msgType,
            payload: inviteBytes,
            groupId: entityIdBytes,
            recipientX25519PkOverride: x25519Pk,
            recipientMlKemPkOverride: mlKemPk,
            recipientEd25519PkOverride: ed25519Pk,
          );
          if (ok) {
            succeeded.add(recipientHex);
            _log.info('Membership resend: sent to ${recipientHex.substring(0, 8)}');
          }
        } catch (e) {
          _log.warn('Membership resend: error for ${recipientHex.substring(0, 8)}: $e');
        }
      }
      recipients.removeAll(succeeded);
      recipients.removeAll(stale);
      if (recipients.isEmpty) {
        toRemoveEntities.add(entityId);
      } else if (succeeded.isNotEmpty || stale.isNotEmpty) {
        // PARTIAL SUCCESS IS NOW RECORDED TOO. Until S366 this loop only
        // wrote when an entity became ENTIRELY empty — whoever reached
        // nineteen of twenty recipients was presented with all twenty
        // again at the next start. With one row per entity recording costs
        // nothing any more.
        _persistMembershipResend(entityId);
      }
    }
    for (final id in toRemoveEntities) {
      _pendingMembershipResends.remove(id);
      _persistMembershipResend(id);
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


  // ── §26.6.2 package C: resubmission of the key rotation ───────────
  //
  // Formerly `cleona_service_v3_retry.dart:377/459`. The BOOKKEEPING is
  // pure (`KeyRotationRetryManager`, an IPC event) and stays; the SEND
  // PATH has fallen and does not come back.
  //
  // GAP G-3. `_retryKeyRotationToContact` resolved the contact into
  // devices via `node.identityResolver` and sent an `InfrastructureFrameV3`
  // per device. Neither exists any more. The obvious substitute — simply
  // taking [sendToUser] — would be WRONG and not merely unfinished: §7.4
  // makes the path the distinguishing feature
  // (`isEmergencyKeyRotationBody`), the receiver CHECKS it, and an
  // emergency rotation via the application path would be rejected there.
  // Changing the path is an architecture decision, not wiring.
  //
  // What happens instead: the attempt is COUNTED (`markAttempt`), so that
  // the entry expires after the promised 90 days / 3 attempts and the UI
  // reports the contact as "not reached" instead of showing "pending"
  // forever. One line per tick, not per contact.
  void _retryPendingKeyRotations() {
    if (!_keyRotationRetry.hasActiveRotation) {
      // Still drain notifications — contacts may have expired on a prior tick
      // before the UI had a chance to listen.
      _emitKeyRotationRetryEvents();
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final due = _keyRotationRetry.duePending(now: now);
    if (due.contacts.isNotEmpty) {
      _log.error('KEY_ROTATION_BROADCAST: ${due.contacts.length} contact(s) '
          'due, but V4.1 has no carrier for the §7.4 infra path '
          '(gap G-3). Attempt is counted so that the entries '
          'expire instead of staying pending forever.');
    }
    for (final hex in due.contacts) {
      _keyRotationRetry.markAttempt(hex, now: now);
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

  // ── §9.5.7 system channel records: what lives on WITHOUT gossip ──────────
  //
  // Formerly `cleona_service_v3_syschan.dart`. The file contained two
  // things, and only ONE of them was network:
  //
  //   * THE GOSSIP (DIGEST/SUMMARY/WANT/PUSH, `sendSysChanDigests`,
  //     `_sysChanPickReachablePeers`, `_sysChanPushTo`) — fallen, and there
  //     is a MEASUREMENT for it: this loop produced **3.17 GB/day with a
  //     useful share of zero**, because it did not converge (S356/S357).
  //     It does not come back. **Gap G-2**: the two system channels
  //     (bug log, feature requests) thus no longer have any propagation;
  //     V4.1 solves the same via the anti-entropy of the durable object
  //     class, and that is not built.
  //
  //   * THE LOCAL KEEPING — storing, making a record visible as a
  //     conversation message, applying a revocation. That is disk access
  //     and `conversations`, not network. It stays, because otherwise a
  //     locally written error report would not even appear in the own UI.

  // `_saveSysChanRecords()` stood here — a full writer of the whole
  // collection with a 2-second batching in front of it. BOTH ARE GONE
  // (S366), and the batching is not needed:
  //
  //   * It existed ONLY because a 1.8 MB file was rewritten completely on
  //     every change. The `SystemChannelRecordStore` now writes one row per
  //     change into the area `syschan_records` (or `syschan_gone`) — there
  //     is no write storm any more that would need damping.
  //   * It was moreover a data-loss window: `stop()` cancelled the timer
  //     (`_sysChanSaveDebounce?.cancel()`), so a record that was less than
  //     two seconds old got lost.
  //
  // The call has been dropped without replacement at both places
  // (`_evictSystemChannels`, `_publishSystemChannelRecord`).
  /// Materializes an admitted POST record as a conversation message so the
  /// existing channel UI (SystemChannelPost cards, eviction, dedup scans)
  /// keeps working. Idempotent per record id.
  ///
  /// F5-R3: For Bug Log crash_report posts, deduplicates at the storage
  /// layer — if a post with the same crash fingerprint already exists, the
  /// incoming record is stored as a crash_duplicate instead of a second
  /// full report (gossip divergence no longer floods the channel).
  UiMessage? _bridgeSysChanPost(StoredSysChanRecord stored) {
    final channelIdHex = stored.record.channelId.hex;
    final conv = conversations[channelIdHex];
    if (conv == null) return null;
    final recordIdHex = stored.record.recordId.hex;
    ensureLoaded(channelIdHex);
    for (final m in conv.messages) {
      if (m.id == recordIdHex) return m;
    }

    var text = stored.record.text;

    if (SystemChannels.isBugLogChannel(channelIdHex)) {
      text = _sysChanDedupCrashReport(text, conv);
    }

    final authorHex = stored.record.authorUserId.hex;
    final isOwn = authorHex == identity.userIdHex;
    final msg = UiMessage(
      id: recordIdHex,
      conversationId: channelIdHex,
      senderNodeIdHex: authorHex,
      text: text,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
          stored.record.timestampMs.toInt()),
      type: UiMessageType.channelPost,
      // AP-4: `sent` has been dropped. The own post is `placing` until the
      // placement confirmation; a foreign one lies on the own disk and is
      // thus observed, not claimed.
      status: isOwn ? MessageStatus.resting : MessageStatus.delivered,
      isOutgoing: isOwn,
    );
    _addMessageToConversation(channelIdHex, msg, isChannel: true);
    return msg;
  }
  /// If [text] is a crash_report whose crash fingerprint already exists in
  /// [conv], demote it to a lightweight crash_duplicate record.
  String _sysChanDedupCrashReport(String text, Conversation conv) {
    if (!text.contains('"crash_report"')) return text;
    try {
      final json = jsonDecode(text) as Map<String, dynamic>;
      if (json['type'] != 'crash_report') return text;
      final fp = json['fingerprint'] as String?;
      if (fp == null) return text;
      ensureLoaded(conv.id);
      for (final m in conv.messages) {
        final mText = m.text;
        if (mText.isEmpty || m.isDeleted) continue;
        if (!mText.contains(fp)) continue;
        try {
          final mj = jsonDecode(mText) as Map<String, dynamic>;
          if (mj['type'] == 'crash_report' && mj['fingerprint'] == fp) {
            final dupe = CrashDuplicateReply(
              fingerprint: fp,
              appVersion: json['appVersion'] as String? ?? '',
              platform: json['platform'] as String? ?? '',
              timestampMs: json['timestampMs'] as int? ?? 0,
            );
            return dupe.toPostText();
          }
        } catch (_) {}
      }
    } catch (_) {}
    return text;
  }
  /// D2: marks the bridged conversation message of a retracted record as
  /// deleted (tombstone effect in the UI).
  void _applySysChanRetract(String channelIdHex, String targetRecordIdHex) {
    final conv = conversations[channelIdHex];
    if (conv == null) return;
    ensureLoaded(channelIdHex);
    for (final m in conv.messages) {
      if (m.id == targetRecordIdHex && !m.isDeleted) {
        m.text = '';
        m.isDeleted = true;
        persistMessage(channelIdHex, m);
        _saveConversations();
        break;
      }
    }
  }

  /// §9.5.7 immediate propagation of a new record — SWITCHED OFF.
  ///
  /// See the block above: 3.17 GB/day without useful share. The body stays
  /// as a NAMED refusal instead of a deleted call, so that it is visible
  /// at the call sites that something is MISSING here and not that nothing
  /// was ever here.
  void _sysChanEagerPush(
      String channelIdHex, List<StoredSysChanRecord> records,
      {required int ttl}) {
    if (records.isEmpty) return;
    _log.warn('§9.5.7: ${records.length} record(s) in '
        '${channelIdHex.substring(0, 8)} stay local — V4.1 has no '
        'distribution for system channels (gap G-2).');
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
      if (isNew || storeRes == FragmentStoreResult.stored) {
        // FORMERLY: `_pushManifestToPeers(data)` — the fragment push to all
        // confirmed peers, so that an update spreads virally instead of
        // every node polling. It ran via `node.routingTable.allPeers` +
        // `node.sendInfraTo` (`FRAGMENT_STORE`) and fell with
        // `lib/core/network/`.
        //
        // **Gap G-18.** The manifest lies locally and is checked locally;
        // OTHER nodes no longer learn of it. The in-network update path
        // (§19.6) is thus one-sided: this node can still offer what it has,
        // but it distributes no manifests.
        _log.warn('[update] Manifest v${manifest.version} stays local — '
            'V4.1 has no fragment push (gap G-18).');
      }
    } catch (e) {
      _log.debug('[update] Self-publish manifest failed: $e');
    }
  }

  // ── §19.6 binary distribution: the local halves ────────────────────
  //
  // Formerly `cleona_service_v3_binary.dart`. Both bodies read and write
  // exclusively the local `BinaryFragmentStore`, or compute Reed-Solomon
  // fragments from the running binary. The only network reference was the
  // line `node.binaryHasContentToShare = true` — a node-wide flag that now
  // hangs as a field on the service (see there).
  /// Builds the current [BinaryAvailabilityRecord] for this device (§19.6.5)
  /// — a snapshot of what this node currently holds in its
  /// [BinaryFragmentStore] for the running platform/version. `addresses` and
  /// `seq` are placeholders overwritten by [BinaryRendezvousManager.publish].
  /// Synchronous because [RendezvousManager]-style record providers are
  /// invoked from debounce/periodic timers, not awaited call sites.
  List<BinaryAvailabilityRecord> _buildBinaryAvailabilityRecords() {
    final store = _binaryFragmentStore;
    if (store == null) return const [];
    final version = currentAppVersion;
    final records = <BinaryAvailabilityRecord>[];
    for (final platform in ['android', 'linux', 'windows', 'macos', 'ios']) {
      // §19.6.4: a binary fetched on demand for one visitor is transient — it
      // is capped at one, TTL-evicted after 24h and excluded from the
      // bootstrap storage budget. Advertising it network-wide would contradict
      // all of that and turn the node into a public mirror for a platform it
      // does not run, for a day, without the user ever asking. It stays
      // retrievable for the visitor who triggered it; it is just not promoted.
      if (_foreignBinaryAcquirer?.isOnDemand(platform, version) ?? false) {
        continue;
      }
      final fragments = store.availableFragmentsSync(platform, version);
      final hasComplete = store.hasCompleteSync(platform, version);
      if (fragments.isEmpty && !hasComplete) continue;
      records.add(BinaryAvailabilityRecord(
        deviceId: identity.deviceNodeId,
        platform: platform,
        version: version,
        addresses: const [],
        binaryHash: _latestManifest?.binaryHashes?[platform] ?? '',
        hasFullBinary: hasComplete,
        fragmentIndices: fragments,
        seq: _latestManifest?.minMonotoneSeq ?? 0,
      ));
    }
    return records;
  }

  /// Self-seed: encode the currently-running binary into Reed-Solomon
  /// fragments so this node becomes a distribution source for its own
  /// platform/version immediately at startup, without waiting for an
  /// update download (§19.6.2). Only meaningful for sideloaded installs —
  /// Play Store builds never self-update, so seeding their own binary
  /// serves no purpose.
  Future<void> _selfSeedCurrentBinary() async {
    final platform = Platform.operatingSystem;
    final version = CleonaService.kCurrentAppVersion;
    final existing = _binaryFragmentStore!.storedVersionsSync(platform);
    if (existing.contains(version)) {
      final frags = _binaryFragmentStore!.availableFragmentsSync(platform, version);
      if (frags.isNotEmpty) {
        _log.debug('[update] Already seeded $platform/$version (${frags.length} fragments)');
        return;
      }
      _log.info('[update] $platform/$version directory exists but 0 fragments — re-seeding');
    }
    try {
      final binaryPath = await _resolveCurrentBinaryPath();
      if (binaryPath == null) return;
      if (!File(binaryPath).existsSync()) {
        _log.debug('[update] Binary not found at $binaryPath — skip self-seed');
        return;
      }
      final expectedHash = _latestManifest?.binaryHashes?[platform];
      final profileDir = _binaryFragmentStore!.profileDir;
      final maxFragments = Platform.isAndroid ? 2 : 8;
      final count = await CleonaService._runSeedIsolate(
          binaryPath, profileDir, platform, version, maxFragments,
          expectedHash: expectedHash);
      if (count > 0) {
        _log.info('[update] Self-seeded $count fragments for $platform/$version');
        binaryHasContentToShare = true;
        _binaryRendezvousManager?.startPeriodicRefresh(_buildBinaryAvailabilityRecords);
        _binaryRendezvousManager?.publishAll(_buildBinaryAvailabilityRecords());
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
  /// the fragments in the `BinaryFragmentStore` of the profile directory.
  /// No wire, no frame, no routing table. The header of THIS file already
  /// says so literally for the neighbouring methods: "Both bodies read and
  /// write exclusively the local `BinaryFragmentStore` … The only network
  /// reference was the line `node.binaryHasContentToShare = true`."
  /// Exactly this one line is the difference to the original: today it
  /// hangs as a field on the service (`cleona_service.dart:391`), not on
  /// the node.
  ///
  /// And the way out is NOT dead on this branch: the announcement runs via
  /// `BinaryRendezvousManager` (`cleona_service_update.dart:562`) and thus
  /// via Nostr — the explicit exception of the CUT decision.
  /// `_selfSeedCurrentBinary` directly above uses the same apparatus at
  /// start; this entry does nothing the node does not do at every start
  /// anyway, only with a file named by the caller instead of its own.
  ///
  /// ── DEVIATIONS FROM THE RESTORED ORIGINAL ───────────────────
  ///
  /// (1) The answer additionally carries `platform` and `version`. The
  /// original only returned `{fragmentCount, hash}` — which is why
  /// `test/e2e/tests/binary-update.spec.ts:33-34` **could never pass even
  /// back then**, when the command still existed: test and body come from
  /// the same commit (`11c8c9df`), and the two fields were expected there
  /// but never delivered. An answer that names its own input values is
  /// the right side of this contradiction.
  ///
  /// (2) The file is read ONCE, not twice. The original computed the hash
  /// with a second `readAsBytesSync` after the isolate run; with a ~90 MB
  /// binary that is an avoidable complete second pass. The hash computed
  /// here is at the same time passed to the isolate as `expectedHash` and
  /// is thus in addition a probe that the file has not changed between
  /// measurement and encoding.
  ///
  /// (3) [maxFragments] can be overridden instead of being hard-wired. The
  /// wire command already carries the field — `IpcClient.seedBinary` has
  /// always sent it along (`ipc_client.dart`) —, and the original did not
  /// accept it: it would silently have had no effect. A parameter that the
  /// one side sends and the other throws away is a promise that is not
  /// kept.
  ///
  /// The default 50 is taken from the original and NOT newly chosen.
  /// §19.6.2 grades "mobile=1-2, desktop=6-8, bootstrap=all"; 50 fully
  /// covers the largest parametrisation (`linux`/`windows`: N=50),
  /// `android` (N=30) anyway. For this command that is the right default:
  /// it is the path triggered by the operator
  /// (`scripts/publish-in-network-update.sh:191` runs on the bootstrap),
  /// not the self-run of an end device.
  Future<Map<String, dynamic>> seedBinaryFromFile(
      String platform, String version, String filePath,
      {int maxFragments = 50}) async {
    final store = _binaryFragmentStore;
    if (store == null) return {'error': 'fragment store not initialized'};
    final file = File(filePath);
    // Wording "file not found" deliberately kept: it is the distinguishable
    // case compared with "could not encode" — the isolate returns only 0
    // for both.
    if (!file.existsSync()) return {'error': 'file not found: $filePath'};
    try {
      final binary = await file.readAsBytes();
      final hash = bytesToHex(SodiumFFI().sha256(binary));
      final count = await CleonaService._runSeedIsolate(
          filePath, store.profileDir, platform, version, maxFragments,
          expectedHash: hash);
      if (count == 0) {
        return {'error': 'seeding produced no fragments for $platform/$version'};
      }
      binaryHasContentToShare = true;
      _binaryRendezvousManager?.startPeriodicRefresh(_buildBinaryAvailabilityRecords);
      _binaryRendezvousManager?.publishAll(_buildBinaryAvailabilityRecords());
      return {
        'fragmentCount': count,
        'hash': hash,
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
