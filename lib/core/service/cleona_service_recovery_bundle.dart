// The rescue bundle (§13.3) on mycelium, application side: WHAT goes into
// it, what is done with it when found, and its state (finding B-1, owner
// approval S398: stage 0, E1-b … E7-a+b).
//
// ── THE DIVISION OF LABOUR ────────────────────────────────────────────
//
//   * `recovery/recovery_keys.dart`   — the derivations from the seed:
//     `recovery_key(i)`, the box key per UTC day (E3-a), `bundle_key`.
//   * `mycelium/lib/mailbox_recovery_bundle.dart` — WHERE it lies (own
//     fixed neighbours first, E1-b), WHEN it is renewed (at a collection
//     edge from 3 d on, E2-a), HOW it is looked for (seven day values in one
//     question). No timer, nothing idle.
//   * THIS file — the CONTENT (§13.3.2, format 4), the seal (§13.3.3), the
//     recovery case (§13.0), taking a found bundle over (E7-a: own keys and
//     chain; E7-b: contacts held until their first envelope proves them), the
//     state in the store of the identity (area `recovery_bundle`) and the
//     one status line (§13.3.4).
//
// The content needs the contact list, the identity and the master seed —
// exactly for that reason it lives here and not in the delivery layer,
// which knows no contacts and shall know none.
//
// Until S398 the bundle line hung on `attachV41` (V4.1, no caller since the
// mycelium rebuild): on mycelium the bundle was neither laid nor looked for,
// and the status line said "no line (no V4.1 node)" — B-1.

part of 'cleona_service.dart';

// §13.0 — IS THIS THE RECOVERY CASE? Since B-4b (D-39, D-40) the fresh
// install decides it from the bundle and the user's choice, not from a
// question asked up front: `enrolmentStartPhase` and `enrolmentAfterBundle`
// (`cleona_service_enrolment.dart`) are the pure functions that replace
// `isRecoveryCase`.

/// Area of the bundle state in the store of the identity.
///
/// S401 (02.10.2026): until then the state lay in a file of its own next to
/// the store (`recovery_bundle.json.enc`, under the same key as the store).
/// It names the contacts restored from a bundle — WHO this identity is in
/// contact with — together with each pair's `s_AB`: conversation metadata,
/// which lives in the store and nowhere else (v4_2 §21.4.2; owner
/// 02.10.2026).
///
/// **One row per waiting contact**, keyed by its UserID in hex and written
/// when it is restored ([RecoveryBundleOps.applyRecoveryBundle]) and
/// removed when its first envelope anchors it
/// ([RecoveryBundleOps._recoveryAnchor]). The file was rewritten as a whole
/// on every deposit and every anchoring; a restore of 200 contacts followed
/// by their first envelopes rewrote 200 entries 200 times.
const String kRecoveryBundleArea = 'recovery_bundle';

/// The ONE row of [kRecoveryBundleArea] that is not a waiting contact: when
/// the bundle was last laid and with how many holders. A UserID in hex has
/// 64 characters, so this key meets none.
const String kRecoveryBundleHeadKey = '_';

/// The name the state had as a file. No writer is left; the name is only
/// asked for by [RecoveryBundleOps._stateFileIntoStore], which empties a
/// file an earlier build of this line left in the profile.
const String _kRecoveryStateFile = 'recovery_bundle.json';

/// One waiting contact as a row: `s_AB` and the fixed neighbours the bundle
/// named for it.
Map<String, dynamic> _recoveryAnchorRow(
        ({Uint8List? pairRandom, List<BundleNeighbour> neighbours}) a) =>
    {
      's': a.pairRandom == null ? null : base64Encode(a.pairRandom!),
      'n': [
        for (final n in a.neighbours) [base64Encode(n.ip), n.port]
      ],
    };

/// Reads [_recoveryAnchorRow] back. Throws on a row of another shape.
({Uint8List? pairRandom, List<BundleNeighbour> neighbours})
    _recoveryAnchorOf(Map<dynamic, dynamic> row) {
  final s = row['s'] as String?;
  return (
    pairRandom: s == null ? null : base64Decode(s),
    neighbours: <BundleNeighbour>[
      for (final n in (row['n'] as List? ?? const []))
        (ip: base64Decode(n[0] as String), port: n[1] as int)
    ],
  );
}

/// The X25519 base point (RFC 7748 §4.1: u = 9) — the public key of a secret
/// scalar is X25519(scalar, 9) (RFC 7748 §6.1).
final Uint8List _kX25519Base = Uint8List(32)..[0] = 9;

/// ML-KEM-768: the decapsulation key is `dk_PKE ‖ ek ‖ H(ek) ‖ z` (FIPS 203
/// §7.1, ML-KEM.KeyGen_internal), `dk_PKE` being 384·k = 1152 B for k = 3;
/// `ek` is the 1184-B public key. liboqs stores the secret key in exactly
/// this layout (2400 B).
const int _kMlKemEkOffset = 1152;

extension RecoveryBundleOps on CleonaService {
  // ── The content (§13.3.2, format 4) ────────────────────────────────────

  /// Builds the rescue bundle of this identity — unsealed.
  ///
  /// Returns `null` if this identity CANNOT have one: without a master
  /// seed and without an HD index there is neither `recovery_key(i)` nor
  /// `bundle_key`, and a bundle that nobody can find again would be the
  /// dummy that §13 precisely does not need.
  RecoveryBundleContent? buildRecoveryBundle({DateTime? at}) {
    if (identity.masterSeed == null) return null;
    final index = identity.hdIndex;
    if (index == null) return null;
    final p = myceliumMailbox;

    List<BundleNeighbour> held(List<CardAddress> l) =>
        [for (final c in l) (ip: c.address, port: c.port)];

    // ── WHICH CONTACTS, AND WHY THE DELETED ONES TOO ───────────────
    //
    // §13.3.2 lists the deletion marker as its own line — "prevents deleted
    // contacts from resurrecting via recovery (§15.9)". That only works if
    // the deletion TRAVELS ALONG. From an identifier without a record no
    // founding key can be formed any more — such identifiers go into the
    // bundle as a tombstone: 32 B UserID, empty anchor, `deleted = true`.
    //
    // `s_AB` and the contact's fixed neighbours come from the mailbox (the
    // pair lives there, D-5); for a contact restored from a bundle that has
    // not yet sent its first envelope (E7-b), from what that bundle brought.
    final contacts = <BundleContact>[];
    for (final c in _contacts.values) {
      final hex = bytesToHex(c.nodeId);
      final anchor = v41PeerFoundingPk(c);
      final waiting = _recoveryAnchors[hex];
      final k = p?.contactOrNull(hex);
      contacts.add(BundleContact(
        userId: c.nodeId,
        foundingEd25519Pk: anchor ?? Uint8List(0),
        displayName: c.displayName,
        verificationLevel: c.verificationLevel,
        deleted: c.isDeleted,
        blocked: c.status == 'blocked',
        pairRandom: k?.pairRandom ?? waiting?.pairRandom,
        neighbours: k != null ? held(k.neighbours) : waiting?.neighbours ?? const [],
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

    // THE INVITATION LINE (§13.3.3 "closes K-7", §15.3.3).
    final book = inviteLedger;
    final own = p == null
        ? const <BundleNeighbour>[]
        : held([
            for (final f in p.node.neighbourhood.fixedNeighbours)
              f.asCardAddress
          ]);

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
      depositedAtMs: (at ?? recoveryBundleClock()).millisecondsSinceEpoch,
      // §13.3.2 (D-39): present only while a window is open.
      enrolmentOpenUntilMs: _enrol.window?.until?.millisecondsSinceEpoch,
      ownNeighbours: own,
      contacts: contacts,
      groups: groups,
    );
  }

  /// The bundle as it is laid: built now and sealed (§13.3.3). `null`: this
  /// identity has none.
  Uint8List? recoveryBundleSealed() {
    final seed = identity.masterSeed;
    if (seed == null) return null;
    // D-40: an undecided install never lays a bundle — it would lay an
    // emptier, newer one over the living device's (the "newest wins" rule
    // of §13.3.2 would make the near-empty one the backup).
    if (enrolmentHolds(_enrol.phase)) return null;
    final content = buildRecoveryBundle();
    if (content == null) return null;
    final clear = content.encode();
    // THE NONCE IS RANDOM: `sealBundle` requires it from the caller; a
    // counter would need a state that is lost after exactly the event the
    // bundle protects against.
    final sealed = sealBundle(
        bundleKey(seed), SodiumFFI().randomBytes(kBundleNonceBytes), clear);
    _log.info('Recovery bundle (§13.3): ${content.contacts.length} '
        'contact(s), ${content.groups.length} group(s), '
        '${content.ownNeighbours.length} own fixed neighbour(s), '
        '${clear.length} B content, ${sealed.length} B sealed');
    return sealed;
  }

  /// Opens a found bundle (§13.3.3).
  ///
  /// Returns `null` if the AEAD does not hold or the bytes are not a
  /// bundle. **`null` does NOT mean "no bundle found"** (§13.2.3).
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
          '${error.name} (format $kBundleFormatVersion expected)');
    }
    return read.content;
  }

  // ── The state (§13.3.4) ─────────────────────────────────────────────────

  /// The state of the rescue bundle in one line (§13.3.4: "An expired bundle
  /// must not lapse silently"). The interface shows [CleonaService.
  /// recoveryBundleValidUntil]; this is the same in the log.
  String get recoveryBundleStatus {
    final box = recoveryBox;
    if (box == null) {
      return 'Rescue bundle: none — no mailbox attached, or an identity '
          'without seed/HD index (§13.3.1)';
    }
    if (box.seeking) {
      return 'Rescue bundle: SEARCH — recovery case (§13.0), asked at every '
          'collection edge and at every card read (${box.seeks} so far)';
    }
    final last = box.lastDeposit;
    final taken = _recoveryTaken;
    final head = taken == null
        ? ''
        : 'taken over at ${taken.toUtc().toIso8601String()}; ';
    if (last == null) {
      return 'Rescue bundle: ${head}not placed yet — laid at the next '
          'collection edge (§13.3.4)';
    }
    return 'Rescue bundle: ${head}placed ${last.toUtc().toIso8601String()} '
        'with ${box.lastHolders} holder(s), valid until '
        '${box.validUntil!.toUtc().toIso8601String()}, renewed at an edge '
        'from ${mycelium.kBundleRenewAfter.inDays} d on';
  }

  /// Reads the state from the store: last deposit, holders, and the
  /// contacts still waiting for their first envelope (E7-b). Nothing there:
  /// all empty.
  ///
  /// THE ONE READER. Everything that shows or uses the state gets it from
  /// here: the box's `lastDeposit` (status line, `recoveryBundleValidUntil`,
  /// the `recoveryBundleUntil` of the state snapshot the interface reads)
  /// and [CleonaService._recoveryAnchors]. No place asks for a file.
  ({DateTime? last, int holders}) _recoveryStateLoad() {
    _stateFileIntoStore('$profileDir/$_kRecoveryStateFile',
        kRecoveryBundleArea, _recoveryRowsOfFile);
    final Map<String, Map<String, dynamic>> rows;
    try {
      rows = store.loadArea(kRecoveryBundleArea);
    } catch (e) {
      _log.warn('Rescue bundle: state not readable ($e) — starts empty');
      return (last: null, holders: 0);
    }
    final head = rows.remove(kRecoveryBundleHeadKey);
    _recoveryAnchors.clear();
    for (final MapEntry(:key, :value) in rows.entries) {
      try {
        _recoveryAnchors[key] = _recoveryAnchorOf(value);
      } catch (e) {
        _log.warn('Rescue bundle: waiting contact ${_short8(key)} not '
            'readable ($e) — skipped');
      }
    }
    final ms = head?['last'] as int?;
    return (
      last: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
      holders: head?['holders'] as int? ?? 0,
    );
  }

  /// Writes the head: when the bundle was last laid, with how many holders.
  /// It changes at a deposit and at nothing else.
  void _recoveryHeadSave() {
    final box = recoveryBox;
    try {
      store.putEntry(kRecoveryBundleArea, kRecoveryBundleHeadKey, {
        'last': box?.lastDeposit?.millisecondsSinceEpoch,
        'holders': box?.lastHolders ?? 0,
      });
    } catch (e) {
      _log.warn('Rescue bundle: state not written ($e)');
    }
  }

  /// Writes EXACTLY ONE waiting contact — or removes its row if it no
  /// longer waits. Nothing here writes the whole set from memory, so a
  /// failed load can never empty the area.
  void _recoveryAnchorSave(String hex) {
    try {
      final waiting = _recoveryAnchors[hex];
      if (waiting == null) {
        store.removeEntry(kRecoveryBundleArea, hex);
      } else {
        store.putEntry(kRecoveryBundleArea, hex, _recoveryAnchorRow(waiting));
      }
    } catch (e) {
      _log.warn('Rescue bundle: waiting contact ${_short8(hex)} not '
          'written ($e)');
    }
  }

  String _short8(String s) => s.length > 8 ? s.substring(0, 8) : s;

  /// The rows of the area from the content of the former state file
  /// (`{last, holders, anchors: {<UserID hex>: {s, n}}}`).
  Map<String, Map<String, dynamic>> _recoveryRowsOfFile(
      Map<String, dynamic> j) {
    final rows = <String, Map<String, dynamic>>{};
    final last = j['last'] as int?;
    // Without a deposit the head says nothing; the reader treats a missing
    // head the same.
    if (last != null) {
      rows[kRecoveryBundleHeadKey] = {
        'last': last,
        'holders': j['holders'] as int? ?? 0,
      };
    }
    final anchors = j['anchors'];
    if (anchors is Map) {
      for (final MapEntry(:key, :value) in anchors.entries) {
        if (key is! String || value is! Map) continue;
        try {
          rows[key] = _recoveryAnchorRow(_recoveryAnchorOf(value));
        } catch (e) {
          _log.warn('Rescue bundle: waiting contact ${_short8(key)} of the '
              'left-over file not readable ($e) — skipped');
        }
      }
    }
    return rows;
  }

  /// Enforcer for a state file an earlier build of THIS line left in the
  /// profile: its content goes into [area] of the store, then every form
  /// of the file is removed.
  ///
  /// ── WHY IT TAKES OVER INSTEAD OF ONLY REMOVING ──────────────────────
  ///
  /// The two files it is called for (`recovery_bundle.json`,
  /// `enrolment.json`) were written by builds of this line between
  /// 29.09.2026 and S401, under this identity's own key — not foreign
  /// stock. No released build wrote them (v4.2.0-beta, `2a3d1947`, has
  /// neither writer), so only lab profiles carry them. What a loss would
  /// mean decided it:
  ///   * the head of the bundle state heals by itself (the bundle is laid
  ///     once more at the next edge);
  ///   * a contact restored from a bundle and still waiting for its first
  ///     envelope does NOT: without its row [_recoveryAnchor] refuses the
  ///     envelope that would anchor it, and `s_AB` is gone for good;
  ///   * a settled enrolment without contacts does NOT either: without
  ///     `settled` an install made from the words searches again and holds
  ///     its own post (D-40) until the user chooses recovery a second time.
  /// The takeover is one read and one transaction.
  ///
  /// ── THE RULES ───────────────────────────────────────────────────────
  ///
  ///   * Nothing of the name in the profile: nothing happens (four
  ///     `existsSync`).
  ///   * The area already carries rows: THE STORE LEADS. The file is the
  ///     older state (or one whose takeover completed and whose removal
  ///     did not) and is removed without being read into the area.
  ///   * The file does not open under this identity's key: nothing is
  ///     taken, it is removed and named in the log — a file nobody can
  ///     read has no reader to wait for.
  ///   * Otherwise: written in ONE transaction, READ BACK and compared;
  ///     only an identical read-back removes the file. If it differs, the
  ///     area is emptied again and the file stays for the next start.
  ///   * The store itself fails: the file stays, the next start repeats.
  void _stateFileIntoStore(String path, String area,
      Map<String, Map<String, dynamic>> Function(Map<String, dynamic>) rowsOf) {
    try {
      if (!PlaintextSweep.forms.any((s) => File('$path$s').existsSync())) {
        return;
      }
    } on FileSystemException {
      return;
    }
    final name = path.split(Platform.pathSeparator).last;
    try {
      if (store.countArea(area) > 0) {
        _log.info('State file $name found although the store already '
            'carries the area `$area` — the store leads, the file is removed');
      } else {
        Map<String, dynamic>? j;
        try {
          j = _fileEnc.readJsonFile(path);
        } catch (e) {
          _log.warn('State file $name: reading failed ($e)');
        }
        if (j == null) {
          _log.warn('State file $name does not open under the key of this '
              'identity — nothing taken over, the file is removed');
        } else {
          final rows = rowsOf(j);
          String canon(Map<String, Map<String, dynamic>> m) => jsonEncode(
              [for (final k in m.keys.toList()..sort()) [k, m[k]]]);
          store.replaceArea(area, rows);
          if (canon(store.loadArea(area)) != canon(rows)) {
            store.replaceArea(area, const {});
            _log.error('State file $name: the area `$area` does not read '
                'back what was written — the file STAYS, the next start '
                'tries again');
            return;
          }
          _log.info('State file $name taken over into the area `$area` '
              '(${rows.length} row(s)) — the file is removed');
        }
      }
    } catch (e) {
      _log.warn('State file $name: the store is not usable ($e) — the file '
          'stays, the next start tries again');
      return;
    }
    PlaintextSweep.removeAllForms(path, log: _log);
  }

  // ── At the mailbox (§13.3.1, E1-b/E2-a) ────────────────────────────────

  /// Hangs the bundle of this identity on the collection edges of [p]'s
  /// node. Called by `myceliumAttach` AFTER the format reset (W-a): a
  /// contact ended there stands as `deleted` in the next bundle.
  ///
  /// In the recovery case (§13.0) the box LOOKS instead of laying: at every
  /// collection edge, and at every card the user reads
  /// ([_recoverySeekAtCard]). Otherwise it lays at the first edge and renews
  /// at an edge from 3 d on. No timer, nothing idle (§5.4).
  void _recoveryBundleAttach(mycelium.Mailbox p) {
    recoveryBox?.detach();
    recoveryBox = null;
    final seed = identity.masterSeed;
    final index = identity.hdIndex;
    if (seed == null || index == null) {
      _log.warn('Rescue bundle: none — identity without seed or HD index, '
          'there is no recovery_key(i) (§13.3.1)');
      return;
    }
    final rk = recoveryKey(seed, index);
    final state = _recoveryStateLoad();
    final box = mycelium.BundleBox(p.node,
        keyFor: (d) => recoveryBoxKey(rk, d),
        sealed: recoveryBundleSealed,
        now: () => recoveryBundleClock(),
        report: _log.info,
        lastDeposit: state.last,
        lastHolders: state.holders,
        onDeposited: (_, _) {
          _recoveryHeadSave();
          onStateChanged?.call();
        },
        onFound: _recoveryBundleFound);
    // §13.0, D-40: the phase decides whether the box seeks, reads only, or
    // lays (`cleona_service_enrolment.dart`).
    recoveryBox = box;
    _enrolmentAttach(p, box, rk);
    box.attach();
    _log.info(recoveryBundleStatus);
  }

  /// A card was read (QR, NFC, text — §15.2) while this identity looks for
  /// its bundle: its addresses are asked at once (E1-b) — a contact's device
  /// that was a fixed neighbour holds the bundle. Outside the recovery case:
  /// nothing. Does not throw.
  ///
  /// Undecided (D-40) the search is not waited for: the redeem answers
  /// "searched only" whatever it brings, and a bundle is taken when it
  /// arrives. In the recovery case the future ends once every asked address
  /// is done (§8.2) — the redeem then knows whether the bundle brought this
  /// contact back.
  Future<void> _recoverySeekAtCard(mycelium.Card card) async {
    final box = recoveryBox;
    if (box == null || !box.seeking) return;
    final holders =
        mycelium.cardHolders(card.ownAddresses, card.neighbourAddress);
    if (holders.isEmpty) return;
    _log.info('Rescue bundle: card read in the recovery case — asking its '
        '${holders.length} address(es)');
    final search = box.seek(withWhom: holders);
    if (enrolmentHolds(_enrol.phase)) return unawaited(search);
    await search;
  }

  // ── Taking a found bundle over (E7) ────────────────────────────────────

  /// What a search brought: the newest bundle that opens is taken over; the
  /// search ends. Found, but none opens: named and ended too — a bundle that
  /// the own seed does not open now does not open later (§13.2.3: that is
  /// not an error, and §13.2.2 applies).
  void _recoveryBundleFound(List<Uint8List> pieces) {
    final box = recoveryBox;
    if (box == null || !box.seeking) return;
    RecoveryBundleContent? best;
    for (final s in pieces) {
      final c = openRecoveryBundle(s);
      if (c == null) continue;
      if (best == null || c.depositedAtMs > best.depositedAtMs) best = c;
    }
    if (best == null) {
      // While undecided (D-40) the search goes on: a bundle that does not
      // open is not the living device's (§13.2.3 — not an error).
      if (enrolmentHolds(_enrol.phase)) return;
      box.seeking = false;
      _log.warn('Rescue bundle (§13.3): ${pieces.length} piece(s) found, none '
          'opens with this seed — search ended (§13.2.2)');
      return;
    }
    // §13.0: undecided, the bundle decides between adding and the question;
    // it is taken over only in the recovery case the user chose.
    if (enrolmentHolds(_enrol.phase)) {
      if (_enrol.phase == EnrolmentPhase.waiting) return;
      final sealedBest = pieces.firstWhere(
          (s) => openRecoveryBundle(s)?.depositedAtMs == best!.depositedAtMs);
      _enrolBundleFound(best, sealedBest);
      return;
    }
    box.seeking = false;
    final n = applyRecoveryBundle(best);
    _enrolRecoverySettled();
    // THE CASE IS SETTLED, SO THE MARKER EXPIRES (S382) — only the runtime
    // mirror; across a restart the third probe (contacts present) carries.
    identity.restoredFromPhrase = false;
    _recoveryTaken = recoveryBundleClock();
    _log.info('Recovery bundle (§13.3): bundle of '
        '${DateTime.fromMillisecondsSinceEpoch(best.depositedAtMs).toUtc().toIso8601String()} '
        'taken over — $n contact(s) of ${best.contacts.length}');
    final p = myceliumMailbox;
    if (p != null) {
      // The post still waiting lies with the former fixed neighbours (§8.2)
      // — ask them at once, then the usual ones.
      final former = [
        for (final a in best.ownNeighbours)
          (InternetAddress.fromRawAddress(a.ip), a.port)
      ];
      unawaited(p.node.collect(
          withWhom: holdersJoin(former, p.node.collectNeighbours)));
    }
    // E5-a: the holder deleted it on our receipt — the device lays a fresh
    // one now, with everything it just took over.
    unawaited(box.deposit());
    onStateChanged?.call();
  }

  /// Takes an opened bundle content over (§13.3.2, E7).
  ///
  /// **Taken over:** the own keys and the rotation chain (E7-a, §4.5.4,
  /// D-33 — after an Emergency Key Rotation the words alone give the
  /// replaced keys); the contacts with founding anchor, name, level, the
  /// deletion and block marks; `s_AB` and each contact's fixed neighbours
  /// are HELD until the contact's first envelope proves its UserID (E7-b,
  /// [_recoveryAnchor]) — the bundle carries no full address (E4); and the
  /// invitation line (only upwards).
  ///
  /// **NOT taken over:** the groups — `GroupInfo` needs owner, creation time
  /// and membership epoch, two of which are not in the bundle (B-3).
  ///
  /// **ONLY SUPPLEMENTING, NEVER OVERWRITING.** An existing contact stays
  /// as it is. Returns how many contacts were newly created.
  int applyRecoveryBundle(RecoveryBundleContent content) {
    final keys = _recoveryKeysAdopt(content);
    var fresh = 0;
    var deleted = 0;
    for (final c in content.contacts) {
      final hex = bytesToHex(c.userId);
      if (c.deleted) {
        // §15.9: a deleted contact must NOT resurrect via the recovery.
        _deletedContacts.add(hex);
        deleted++;
        continue;
      }
      if (_contacts.containsKey(hex)) continue;
      if (c.foundingEd25519Pk.length != 32) {
        _log.warn('Rescue bundle: contact ${hex.substring(0, 8)} without '
            'founding anchor in the bundle — not created.');
        continue;
      }
      final info = ContactInfo(
        nodeId: c.userId,
        displayName: c.displayName,
        status: c.blocked ? 'blocked' : 'accepted',
        verificationLevel: c.verificationLevel,
        // THE ANCHOR BELONGS IN `seedEpB64` (`v41PeerFoundingPk` looks for
        // it there), URL-safe and without padding like every writer.
        seedEpB64: base64Url.encode(c.foundingEd25519Pk).replaceAll('=', ''),
      );
      info.rememberFoundingAnchor(c.foundingEd25519Pk);
      _contacts[hex] = info;
      _recoveryAnchors[hex] =
          (pairRandom: c.pairRandom, neighbours: c.neighbours);
      // The row BEFORE the contact list: a contact that is stored without
      // its waiting row could never be anchored ([_recoveryAnchor] refuses
      // it); a row without its contact is used by nobody.
      _recoveryAnchorSave(hex);
      fresh++;
    }
    if (fresh > 0 || deleted > 0) _saveContacts();

    // THE INVITATION LINE (§15.3.3, K-7). Only UPWARDS.
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
    if (bookChanged) inviteStore.persistHead(book);

    if (content.groups.isNotEmpty) {
      _log.info('Rescue bundle: ${content.groups.length} group(s) lie '
          'in the bundle and are NOT taken over — `GroupInfo` needs '
          'owner, creation time and membership epoch (B-3). Open.');
    }
    _log.info('Rescue bundle: taken over — own keys '
        '${keys ? "and chain (${content.rotationChain.length} link(s))" : "unchanged (the keys of the words)"}, '
        '$fresh contact(s) waiting for their first envelope, $deleted '
        'deletion mark(s)');
    return fresh;
  }

  /// E7-a: the own current keys and chain from the bundle, when they differ
  /// from the words' keys — an Emergency Key Rotation happened (§4.5.4,
  /// D-33). The chain must lead from this UserID to the bundle's signing
  /// keys (checked hybrid, `RotationChain.holds`); the running mailbox takes
  /// the keys over in the same step (`MailboxRotation.identityRotate`).
  /// `false`: nothing to adopt, or refused (named).
  bool _recoveryKeysAdopt(RecoveryBundleContent c) {
    if (c.rotationChain.isEmpty) return false;
    if (c.ed25519SecretKey.length != 64) return false;
    final ed = Uint8List.fromList(Uint8List.sublistView(c.ed25519SecretKey, 32));
    if (constantTimeEquals(ed, identity.ed25519PublicKey)) return false;
    if (identity.hasRotated) {
      _log.warn('Rescue bundle: this device already carries a rotation chain '
          '— the bundle\'s keys are NOT written over it');
      return false;
    }
    final chain = [
      for (final l in c.rotationChain)
        StoredRotationLink(
          oldEd25519Pk: l.oldEd25519Pk,
          oldMlDsaPk: l.oldMlDsaPk,
          newEd25519Pk: l.newEd25519Pk,
          newMlDsaPk: l.newMlDsaPk,
          oldSignatureEd25519: l.oldSignatureEd25519,
          oldSignatureMlDsa: l.oldSignatureMlDsa,
        )
    ];
    final dsa = c.rotationChain.last.newMlDsaPk;
    try {
      if (!RotationChain.fromStored(chain)
          .holds(identity.userId, ChainKeys(ed, dsa))) {
        _log.warn('Rescue bundle: the chain does not lead from this UserID to '
            'the bundle\'s keys (§4.5.4) — keys NOT adopted');
        return false;
      }
      if (c.mlKemSecretKey.length != OqsFFI.mlKemSecretKeyLength) {
        throw ArgumentError('ML-KEM secret key of ${c.mlKemSecretKey.length} B');
      }
      identity.adoptRecoveredKeys(
        chain: chain,
        ed25519Pk: ed,
        ed25519Sk: c.ed25519SecretKey,
        mlDsaPk: dsa,
        mlDsaSk: c.mlDsaSecretKey,
        x25519Pk: SodiumFFI().x25519ScalarMult(c.x25519SecretKey, _kX25519Base),
        x25519Sk: c.x25519SecretKey,
        mlKemPk: Uint8List.fromList(c.mlKemSecretKey.sublist(_kMlKemEkOffset,
            _kMlKemEkOffset + OqsFFI.mlKemPublicKeyLength)),
        mlKemSk: c.mlKemSecretKey,
      );
    } on Object catch (e) {
      _log.warn('Rescue bundle: keys NOT adopted — $e');
      return false;
    }
    final p = myceliumMailbox;
    if (p != null) {
      try {
        mycelium.MailboxRotation(p).identityRotate(postBoxFrom(identity));
      } catch (e) {
        _log.error('Rescue bundle: the running mailbox did not take the '
            'recovered keys over ($e) — it takes them at the next start');
      }
    }
    return true;
  }

  /// E7-b: the first envelope of a restored contact that proves its UserID
  /// (mycelium checked the signature and, for a rotated one, the chain). Its
  /// founding key must be the one the bundle named; then its address becomes
  /// the contact's, and the mailbox learns it with the `s_AB` and fixed
  /// neighbours from the bundle — `K_AB`, the codes and step 3 are back
  /// (§4.3, §8.1). `false`: not a waiting contact, or refused (named).
  bool _recoveryAnchor(ContactInfo c, mycelium.Address from) {
    final hex = bytesToHex(c.nodeId);
    final waiting = _recoveryAnchors[hex];
    if (waiting == null) return false;
    final founding = from.chain.founding?.ed25519Pk ?? from.ed25519Pk;
    final held = v41PeerFoundingPk(c);
    if (held == null || !constantTimeEquals(held, founding)) {
      _log.warn('Rescue bundle: envelope of ${hex.substring(0, 8)} does not '
          'carry the founding key the bundle named — not anchored');
      return false;
    }
    if (!_setContactTrustAnchor(c, hex, from.ed25519Pk, from.mlDsaPk,
        source: 'recovery bundle, first envelope')) {
      return false;
    }
    c.x25519Pk = from.x25519Pk;
    c.mlKemPk = from.mlKemPk;
    c.kemRotationAt = DateTime.fromMillisecondsSinceEpoch(from.state);
    c.acceptedAt ??= DateTime.now();
    _recoveryAnchors.remove(hex);
    final p = myceliumMailbox;
    if (p != null) {
      p.contactRemember(from,
          pairRandom: waiting.pairRandom,
          neighbours: [
            for (final n in waiting.neighbours) CardAddress(n.ip, n.port)
          ],
          displayName: c.displayName);
      p.node.codeRoute.codesChanged(); // EDGE (§8.1): the pair's codes
      p.host.contactSeatsEdge(); // §5.2: it may take a fixed seat again
    }
    // The contact first, then its row goes: a row left over after a crash
    // in between names a contact that is anchored already and is harmless.
    _saveContacts();
    _recoveryAnchorSave(hex);
    _log.event('Rescue bundle: contact ${hex.substring(0, 8)} anchored by its '
        'first envelope (E7-b) — s_AB ${waiting.pairRandom == null ? "none" : "from the bundle"}, '
        '${waiting.neighbours.length} fixed neighbour(s)');
    return true;
  }
}
