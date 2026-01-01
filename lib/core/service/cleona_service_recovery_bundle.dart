// The rescue bundle (§13.3), application side: WHAT goes into it.
//
// ── THE DIVISION OF LABOUR, AND WHY IT IS CUT THIS WAY ─────────────
//
//   * `recovery_keys.dart`   — the derivations from the seed (§13.3.1/.3).
//   * `tagline/recovery_line.dart` — splitting, deposit, cadence, harvest
//     on the bundle line.
//   * THIS file              — the CONTENT, and only that.
//
// The content is the only part that needs the contact list, the identity
// and the master seed. Exactly for that reason it lives here and not in
// the delivery layer: that knows no contacts and shall know none.
//
// ── WHAT §13.3.2 REQUIRES AND WHAT OF IT WORKS ──────────────────────────
//
// The line-by-line acceptance is in the header of
// `recovery_bundle_content.dart`. Two of the eleven lines are NOT built,
// both with a reason and both reported: the "Shared Key" including
// `inbox_key` per contact (there is no mailbox line in V4.1; §21.2
// explicitly denies it) and the prekey pool identifier from §13.4.4
// (does not exist in the tree).

part of 'cleona_service.dart';

/// §13.0 — IS THIS THE RECOVERY CASE?
///
/// The decision stands next to it as a pure function, so that it can be
/// checked and is not only commented — the same pattern as
/// `harvestRunDue`/`harvestCap` in `tagline/secure_mode.dart`, and for the
/// same reason: until S382 a STAND-IN stood at this place, and nobody
/// noticed, because nothing checked it.
///
/// The rule, literally from §13.0 (owner decision 12.09.2026):
///
///     Fresh installation, NO new user created, but the
///     passphrase entered:
///       -> Are there further devices under this phrase?
///          YES:  the data comes from there (§14.4). Not a case.
///          NO:   THAT is the recovery case.
///
/// [outPhrase]      the identity came about via the 24-word phrase
///                  (`Identity.restoredFromPhrase`). A freshly created one
///                  is NOT — not even when it looks like a recovered one
///                  (seed there, no contacts).
/// [otherDevice]  another device is still running under the same phrase
///                  (`Identity.restoreAwaitingPairing`).
/// [hasContacts]    something is already there, so nothing more to fetch.
bool isRecoveryCase({
  required bool outPhrase,
  required bool otherDevice,
  required bool hasContacts,
}) =>
    outPhrase && !otherDevice && !hasContacts;

extension V41RecoveryBundleOps on CleonaService {
  /// Builds the rescue bundle of this identity — unsealed.
  ///
  /// Returns `null` if this identity CANNOT have one: without a master
  /// seed and without an HD index there is neither `recovery_key(i)` nor
  /// `bundle_key`, and a bundle that nobody can find again would be the
  /// dummy that §13 precisely does not need.
  RecoveryBundleContent? buildRecoveryBundle() {
    if (identity.masterSeed == null) return null;
    final index = identity.hdIndex;
    if (index == null) return null;

    // ── WHICH CONTACTS, AND WHY THE DELETED ONES TOO ───────────────
    //
    // §13.3.2 lists the deletion marker as its own line with the
    // justification "prevents deleted contacts from resurrecting via
    // recovery (§15.9)". That only works if the deletion TRAVELS ALONG — a
    // bundle that simply omits deleted contacts lets them resurrect at the
    // counterpart's next broadcast, and the user would have to delete them
    // a second time.
    //
    // The tree keeps the own deletion in `_deletedContacts` and in the
    // process removes the record from `_contacts` (`cleona_service.dart`).
    // From an identifier without a record no `foundingEd25519Pk` can be
    // formed any more — such identifiers therefore go into the bundle as a
    // tombstone: 32 B UserID, empty anchor, `deleted = true`. That suffices
    // for the purpose (not letting them resurrect) and costs nothing further.
    final contacts = <BundleContact>[];
    for (final c in _contacts.values) {
      final anchor = v41PeerFoundingPk(c);
      if (anchor == null) {
        // WITHOUT AN ANCHOR THE CONTACT IS NOT RECOVERABLE, and skipping it
        // silently would be exactly the kind of gap this session closes. It
        // comes along as a tombstone, so that the recovery can SHOW it
        // instead of losing it.
        contacts.add(BundleContact(
          userId: c.nodeId,
          foundingEd25519Pk: Uint8List(0),
          displayName: c.displayName,
          verificationLevel: c.verificationLevel,
          deleted: c.isDeleted,
          blocked: c.status == 'blocked',
        ));
        continue;
      }
      contacts.add(BundleContact(
        userId: c.nodeId,
        foundingEd25519Pk: anchor,
        displayName: c.displayName,
        verificationLevel: c.verificationLevel,
        deleted: c.isDeleted,
        blocked: c.status == 'blocked',
      ));
    }
    for (final hex in _deletedContacts) {
      if (_contacts.containsKey(hex)) continue;
      final id = hexToBytes(hex);
      if (id.length != 32) continue;
      contacts.add(BundleContact(
        userId: id,
        foundingEd25519Pk: Uint8List(0),
        displayName: '',
        verificationLevel: kVerificationLevels[0],
        deleted: true,
        blocked: false,
      ));
    }

    final groups = <BundleGroup>[
      for (final g in _groups.values)
        BundleGroup(
          groupId: hexToBytes(g.groupIdHex),
          name: g.name,
          channel: false,
          members: <BundleGroupMember>[
            for (final m in g.members.values)
              BundleGroupMember(
                  userId: hexToBytes(m.nodeIdHex), role: m.role)
          ],
        ),
    ];

    // THE INVITATION LINE (§13.3.3 "closes K-7", §15.3.3). `g_inv` and
    // highwater together say which invitation indices HAVE BEEN assigned —
    // without them a recovered identity would assign indices a second
    // time, and the counterparts of the first assignment would have a line
    // that belongs to someone else.
    final book = inviteLedger;

    return RecoveryBundleContent(
      identityIndex: index,
      displayName: identity.displayName,
      active: true,
      ed25519SecretKey: identity.ed25519SecretKey,
      mlDsaSecretKey: identity.mlDsaSecretKey,
      x25519SecretKey: identity.x25519SecretKey,
      mlKemSecretKey: identity.mlKemSecretKey,
      rotationChain: <BundleRotationLink>[
        for (final l in identity.rotationChain)
          BundleRotationLink(
            oldEd25519Pk: l.oldEd25519Pk,
            oldMlDsaPk: l.oldMlDsaPk,
            newEd25519Pk: l.newEd25519Pk,
            newMlDsaPk: l.newMlDsaPk,
            oldSignatureEd25519: l.oldSignatureEd25519,
            oldSignatureMlDsa: l.oldSignatureMlDsa,
          )
      ],
      inviteGeneration: book.generation,
      inviteHighwater: book.highwater,
      // NOT the pool identifier from §13.4.4 — that does not exist.
      // What stands here is the assignment counter of the index space, and
      // it stands under its own name (see `prekeysIssued`).
      prekeysIssued: v41Host?.prekeyIndicesIssued ?? 0,
      contacts: contacts,
      groups: groups,
    );
  }

  /// The material for the bundle line: line key and sealed bundle
  /// (§13.3.1, §13.3.3).
  ///
  /// `null` means "not now" and is not an error — the line asks again in
  /// an hour.
  RecoveryBundleMaterial? recoveryBundleMaterial(int recoveryEpoch) {
    final seed = identity.masterSeed;
    final index = identity.hdIndex;
    if (seed == null || index == null) return null;
    final content = buildRecoveryBundle();
    if (content == null) return null;
    final clear = content.encode();
    // ── THE NONCE, AND WHY IT IS RANDOMISED ────────────────────
    //
    // `sealBundle` requires it from the caller and says why: "the mark
    // `recoveryBundleTag` is NOT suitable as a nonce (it repeats when the
    // same epoch is renewed twice)". Randomness is the right choice here —
    // with 12 B and one renewal every 14 days a repetition under the same
    // key is not to be expected, and a counter would need a persistent
    // state that would be lost after exactly the event the bundle protects
    // against.
    final isSealed = sealBundle(
        bundleKey(seed), SodiumFFI().randomBytes(kBundleNonceBytes), clear);
    _log.info('Recovery bundle (§13.3): epoch $recoveryEpoch, '
        '${content.contacts.length} contact(s), ${content.groups.length} '
        'group(s), ${clear.length} B content, ${isSealed.length} B '
        'sealed');
    return RecoveryBundleMaterial(
      recoveryKey: recoveryKey(seed, index),
      sealed: isSealed,
    );
  }

  /// Opens a harvested bundle (§13.3.3).
  ///
  /// Returns `null` if the AEAD does not hold or the bytes are not a
  /// bundle. **`null` does NOT mean "no bundle found"** — §13.2.3 requires
  /// that an unsuccessful search is not an error; the distinction "nothing
  /// found" versus "found, but unusable" belongs in the caller.
  RecoveryBundleContent? openRecoveryBundle(Uint8List sealed) {
    final seed = identity.masterSeed;
    if (seed == null) return null;
    final clear = openBundle(bundleKey(seed), sealed);
    if (clear == null) return null;
    // S388 (K-4): opened means "mine" — if the content is still not
    // readable, the reason is named instead of silently returning `null`.
    final read = RecoveryBundleContent.read(clear);
    final error = read.error;
    if (error != null) {
      _log.warn('Rescue bundle (§13.3.3): opened, but discarded — '
          '${error.name} (version expected $kBundleFormatVersion)');
    }
    return read.content;
  }

  /// The state of the rescue bundle in one line (§13.3.4).
  ///
  /// ── WHY THIS LINE MUST EXIST ──────────────────────────────
  ///
  /// §13.3.4 "Visibility" is normative: "The bundle state belongs in the
  /// UI, following the pattern from §14.4: `Backup valid until <date>` or
  /// ,Backup expires in N days.` **An expired bundle must not lapse
  /// silently.**"
  ///
  /// The UI for it is NOT built — that is a separate, reported item. What
  /// stands here is the measurement underneath: the same information in
  /// the log, so that the question "does it renew at all?" is a
  /// measurement and not a guess. Without it a missing bundle would be
  /// noticed after 31 days at the earliest — when it is gone.
  String get recoveryBundleStatus {
    final l = v41RecoveryBundle;
    if (l == null) return 'Rescue bundle: no line (no V4.1 node)';
    if (l.harvesting) {
      return 'Rescue bundle: SEARCH running (${l.harvestRuns} runs, '
          'cap $kRecoveryHarvestMaxRuns)';
    }
    if (l.exhausted) {
      return 'Rescue bundle: search ended without a find — not an error '
          '(§13.2.3), but §13.2.2';
    }
    final found = l.foundEpoch;
    if (found != null) {
      return 'Rescue bundle: adopted from epoch $found';
    }
    return 'Rescue bundle: ${l.attached ? "on the tick" : "DETACHED"}, '
        '${l.renewals} renewal(s), ${l.placements} placements made, '
        '${l.pendingTags} tag(s) open '
        '(${l.plannedPlacements} placements in the plan), TTL '
        '${kRecoveryBundleTtl.inDays} d, cadence '
        '${kRecoveryRenewalInterval.inDays} d';
  }

  // ═══════════════════════════════════════════════════════════════════
  // THE SEARCH FOR THE OWN BUNDLE (§13.2.1, §13.3.1)
  // ═══════════════════════════════════════════════════════════════════

  /// Starts the search IF this node is in the recovery case.
  ///
  /// ── BY WHAT THE CASE IS RECOGNISED, AND WHY BY EXACTLY THAT ───────────
  ///
  /// §13.0 cuts the occasion narrowly: "replacing a device is not a
  /// recovery case … The real recovery case is exclusively: **all devices
  /// gone.**" And §13.1.3 describes what of that is visible in the process:
  /// "The recovering user possesses exclusively **self-referential** key
  /// material" — seed yes, counterpart no.
  ///
  /// Exactly that is the probe: a master seed is present, an HD index is
  /// present, and there is **not a single** contact — neither a living nor
  /// a deleted one. A device replacement does not fall in here: the new
  /// device gets its contacts via the admission (§14.6), not via the
  /// bundle.
  ///
  /// **NO EFFORT IF THE CASE DOES NOT APPLY.** The probe is a look at two
  /// counters; the search itself only runs if it applies. A normally used
  /// account never makes one of these requests.
  ///
  /// Returns `true` if a search was started.
  bool beginRecoveryBundleHarvestIfLost() {
    final line = v41RecoveryBundle;
    if (line == null) return false;
    if (line.harvesting || line.sealedFound != null) return false;
    final seed = identity.masterSeed;
    final index = identity.hdIndex;
    if (seed == null || index == null) return false;
    // ── THREE QUESTIONS, IN THIS ORDER (§13, S382) ────────────────
    //
    // Until S382 ONLY the third stood here — "does this identity have no
    // contacts". That is a STAND-IN, and it is just as true for a freshly
    // created second identity as for a recovered one. Measured on
    // 12.09.2026: every second identity in the lab (AllyCat, Charly,
    // WindowsTwo) fired a search over up to 120 runs at EVERY attach — for
    // something that never existed.
    //
    // The case distinction that belongs here (owner, 12.09.2026):
    //
    //   Fresh installation, NO new user created, but the
    //   passphrase entered:
    //     -> Are there further devices under this phrase?
    //        YES:  the data comes from there, via the same identity on the
    //              other device (§14.4). NOT a recovery case.
    //        NO:   THAT is the recovery case — the data from the chats with
    //              contacts, groups and channels is fetched back.
    //
    // The three questions stand in `isWiederherstellungsfall` above.
    if (!isRecoveryCase(
        outPhrase: identity.restoredFromPhrase,
        otherDevice: identity.restoreAwaitingPairing,
        hasContacts: _contacts.isNotEmpty || _deletedContacts.isNotEmpty)) {
      return false;
    }
    line.onFound = (isSealed, epoch) {
      final content = openRecoveryBundle(isSealed);
      if (content == null) {
        // FOUND, BUT UNUSABLE — and that is something other than "nothing
        // found" (§13.2.3). It is reported and the search ended: a bundle
        // that cannot be opened with the own seed will not open on the next
        // run either.
        _log.warn('Rescue bundle (§13.3): bundle from epoch $epoch '
            'found, but cannot be opened — the AEAD does not hold or '
            'the content is none. Search ended.');
        line.endHarvest();
        return;
      }
      final n = applyRecoveryBundle(content);
      _log.info('Recovery bundle (§13.3): bundle from epoch $epoch '
          'opened — $n contact(s) adopted of '
          '${content.contacts.length}.');
      // ── THE CASE IS SETTLED, SO THE MARKER EXPIRES (S382) ────
      //
      // Without this line `restoredFromPhrase` would stay set and the case
      // would be open again at every restart — exactly the permanent
      // trigger this change switches off, just one level higher. The third
      // probe in the gate (contacts present) would catch it as soon as the
      // bundle brought something; if it brought NOTHING, it would not catch
      // it, and then exactly this deletion is the difference.
      //
      // ONLY THE RUNTIME MIRROR. The identity record on disk belongs to the
      // `IdentityManager`, which the service layer does not hold; across
      // the restart the third probe carries. That is a deliberately small
      // solution and named as a limit, not overlooked.
      identity.restoredFromPhrase = false;
      line.endHarvest();
    };
    line.beginHarvest(recoveryKey(seed, index));
    _log.info('Rescue bundle (§13.3): no contact known, seed is '
        'present — search on the own bundle line started (epochs '
        '${recoveryHarvestEpochs(DateTime.now().toUtc()).join(", ")}).');
    return true;
  }

  /// Takes an opened bundle content into the contact stock.
  ///
  /// ── WHAT IS TAKEN OVER AND WHAT EXPLICITLY NOT ──────────────
  ///
  /// **Taken over:** the contacts including founding anchor, display name
  /// and verification level, the deletion markers, and the state of the
  /// invitation line. Exactly that solves the chicken-and-egg problem from
  /// §13.1.3 ("The problem is not where the mail is, but **knowledge of the
  /// other parties**") — with the founding anchor `K_AB` follows, and with
  /// `K_AB` every tagline.
  ///
  /// **NOT taken over, and both with a reason:**
  ///
  ///   * **The own keys** (sig SKs, user KEM SK, rotation chain). They
  ///     TRAVEL along in the bundle — §13.3.2 requires them, and without
  ///     them a ROTATED identity is the one from day 1 after the recovery.
  ///     Importing them here, however, would mean overwriting the running
  ///     key state from something that came from the network; that belongs
  ///     to the takeover path from §13.6/§14.4 with its continuity check and
  ///     not here. Open and reported, not forgotten.
  ///   * **The groups.** They travel along too (§13.3.2, last line), but
  ///     `GroupInfo` needs `ownerNodeIdHex`, `createdAt` and
  ///     `membershipEpoch`, and two of them do NOT stand in the bundle.
  ///     A group with an invented membership epoch would be worse than none.
  ///
  /// **ONLY SUPPLEMENTING, NEVER OVERWRITING.** An existing contact stays
  /// as it is: the bundle is up to 31 days old, an existing record is
  /// never older.
  ///
  /// Returns how many contacts were newly created.
  int applyRecoveryBundle(RecoveryBundleContent content) {
    var fresh = 0;
    var deleted = 0;
    for (final c in content.contacts) {
      final hex = bytesToHex(c.userId);
      if (c.deleted) {
        // §15.9: a deleted contact must NOT resurrect via the recovery. The
        // marker comes back, the record does not.
        _deletedContacts.add(hex);
        deleted++;
        continue;
      }
      if (_contacts.containsKey(hex)) continue;
      if (c.foundingEd25519Pk.length != 32) {
        // WITHOUT AN ANCHOR NO `K_AB` AND NO LINE. Such an entry would be a
        // name without a delivery path; it is reported, not created.
        _log.warn('Rescue bundle: contact $hex without founding anchor in the '
            'bundle — not created.');
        continue;
      }
      _contacts[hex] = ContactInfo(
        nodeId: c.userId,
        displayName: c.displayName,
        // ── THE VERIFICATION LEVEL COMES ALONG, THE STATUS DOES NOT ───────────────
        //
        // §13.3.2 lists "display name + verification level" as a bundle
        // line with the justification "UI continuity, key-change detection
        // (§15.7)". The STATUS does not stand there — and it could not be
        // proven either: `blocked` travels as its own bit, everything else
        // is an accepted contact, otherwise it would not lie in the bundle.
        status: c.blocked ? 'blocked' : 'accepted',
        verificationLevel: c.verificationLevel,
        // THE ANCHOR BELONGS IN `seedEpB64`, because `v41PeerFoundingPk`
        // looks for it exactly there (and only afterwards falls back to
        // `ed25519Pk`). URL-safe and without padding — the same notation as
        // with all three other writers of the field, against exactly the
        // error that silently killed first contact in S360.
        seedEpB64: base64Url.encode(c.foundingEd25519Pk).replaceAll('=', ''),
      );
      fresh++;
    }
    if (fresh > 0 || deleted > 0) _saveContacts();

    // THE INVITATION LINE (§15.3.3, K-7). Only UPWARDS: if the local ledger
    // is further ahead than the bundle, it is right — the bundle is up to
    // 31 days old. Set backwards, indices would be assigned a second time,
    // and the counterparts of the first assignment would have a line that
    // belongs to someone else.
    final book = inviteLedger;
    var bookChanged = false;
    if (content.inviteGeneration > book.generation) {
      book.generation = content.inviteGeneration;
      bookChanged = true;
    }
    if (content.inviteHighwater > book.highwater) {
      book.highwater = content.inviteHighwater;
      bookChanged = true;
    }
    // S366: here EXCLUSIVELY the header changes — generation and highwater
    // move upwards, no record is created. So only the header is written.
    if (bookChanged) inviteStore.persistHead(book);

    if (content.groups.isNotEmpty) {
      _log.info('Rescue bundle: ${content.groups.length} group(s) lie '
          'in the bundle and are NOT taken over — `GroupInfo` needs '
          'owner, creation time and membership epoch, and two of them '
          'are not in the bundle (§13.3.2). Open, not forgotten.');
    }
    return fresh;
  }
}
