// AP-1c step 3 (docs/MIGRATION_V3_TO_V4_0_MYZEL.md §4c.6) — CLASS B.
//
// In-network update: the orchestration of the signed update manifest —
// checking, triggering, progress, fragment GC — together with the two
// getters on the manager and the last-seen manifest.
//
// CLASS B means: the service keeps this task, the carrier changes. The
// in-network update is explicitly continued in V4 (ch. 19.6.1, fountain
// content layer, AP-7) — just no longer via DHT fragments and V3 frames.
// AP-3/AP-7 rewrite the content of this file, they do not delete it.
//
// Delimited against `cleona_service_v3_binary.dart`: that holds the V3
// binary transport (class A, dropped with the frame model). Here stands
// WHEN and WHY an update is triggered — the decision, not the transport
// path.

part of 'cleona_service.dart';

/// The version for which this service is currently collecting (Z1). Next
/// to the service instead of in it: the field would belong in
/// `cleona_service.dart`, and the seam is being built there in parallel (S387).
final Expando<String> _updateCollectTarget = Expando<String>('updateCollectTarget');

/// The update carrier of the delivery layer (S387). Next to the service,
/// for the same reason as [_updateCollectTarget].
final Expando<UpdateCarrier> _updateCarrierField =
    Expando<UpdateCarrier>('updateCarrier');

extension V3InNetworkUpdateOps on CleonaService {

  // ══ THE CARRIER IN THE DELIVERY LAYER (S387, M1+ AND P1) ═════════════
  //
  // v4_2 §26.5.4: the manifest lies in the post box and is asked for at
  // the moments start, network change, app open, new neighbour — never on
  // a clock. §26.6.1: missing pieces of an object are fetched from a
  // holder; always-on nodes hold what they have completely.
  // The implementation is `package:mycelium/update.dart`; it is attached
  // by the seam.
  //
  // ONE service per process gets the carrier (the seam sets it on the
  // first one). Every further one would ask the same compartment once more.

  UpdateCarrier? get updateCarrier => _updateCarrierField[this];

  /// Setting is the moment "start": the known manifest goes to the carrier
  /// (to be put back), the own complete objects are held, and the
  /// compartment is asked.
  set updateCarrier(UpdateCarrier? carrier) {
    _updateCarrierField[this] = carrier;
    if (carrier == null) return;
    carrier.onManifest =
        (json) => unawaited(_manifestsProcess(<Uint8List>[json]));
    try {
      final cache = File('${AppPaths.dataDir}${Platform.pathSeparator}'
          'update_manifest_cache.json');
      if (cache.existsSync()) carrier.manifestKnown(cache.readAsBytesSync());
    } catch (e) {
      _log.debug('[update] carrier: manifest cache unreadable: $e');
    }
    _ownObjectsHold(carrier);
    unawaited(carrier.manifestAsk());
  }

  /// A moment per M1+ — network change, app open, new neighbour. The seam
  /// calls it; this file has no timer for it.
  Future<void> updateManifestAsk() async =>
      _updateCarrierField[this]?.manifestAsk();

  /// Always-on nodes (desktop) hold every complete object of the current
  /// manifest for others (§26.6.1, §5.5 "What a node keeps"); mobile ones
  /// hold nothing for others.
  void _ownObjectsHold(UpdateCarrier carrier) {
    final manifest = _latestManifest;
    final store = _binaryFragmentStore;
    if (manifest == null || store == null) return;
    if (Platform.isAndroid || Platform.isIOS) return;
    for (final platform in kCoverFillPlatforms) {
      final hash = manifest.binaryHashes?[platform];
      if (hash == null || !store.hasCompleteSync(platform, manifest.version)) {
        continue;
      }
      carrier.objectHold(hexToBytes(hash),
          () => store.getComplete(platform, manifest.version));
      _log.info('[update] carrier: $platform v${manifest.version} is '
          'held for others');
    }
  }

  /// A collection run for [version] is outdated — a newer manifest has
  /// moved the target. Asked after every wait in [_startInNetworkUpdate].
  bool _updateSuperseded(String version) {
    final target = _updateCollectTarget[this];
    if (target == version) return false;
    _log.info('startInNetworkUpdate: run for v$version superseded '
        '(target now v$target) — ended');
    return true;
  }

  BinaryUpdateManager? get binaryUpdateManager => _binaryUpdateManager;

  /// The fragment store of this service.
  ///
  /// **Restored on 2026-09-01 (gap G-7).** Until the cut of 31.08. the
  /// getter stood as a one-liner in `cleona_service_v3_binary.dart` and
  /// fell with that file — although neither the field
  /// (`cleona_service.dart:548`) nor the class [BinaryFragmentStore] hangs
  /// on anything from the V3 network code. So what fell was the ACCESS,
  /// not the thing.
  ///
  /// **What was dead without it:** on Android `CleonaAppState.applyUpdate`
  /// needs the path of the completely assembled APK
  /// ([BinaryFragmentStore.completePath]) to hand it to the system
  /// installer. Without the getter the flow listed as MANDATORY "user
  /// clicks download -> auto-install" (§26.6.1 step 6, memo
  /// `project_android_update_flow_v145.md`) ended in the state `failed`.
  /// `test/smoke/smoke_update_mandatory_flow.dart` measures that now.
  BinaryFragmentStore? get binaryFragmentStore => _binaryFragmentStore;

  /// The embedded HTTP server of this service (§26.6.5).
  ///
  /// **Created on 2026-09-01, because G-20 needed an ACCESS.** The server
  /// binds no socket of its own — it is hung onto the four-byte switch of
  /// the TCP listener (`link_io/tcp_listener.dart`), and that happens in
  /// `attachV41`: there node (which holds the port) and service (which
  /// holds the server) are present at the same time. E-118 verbatim: "the
  /// node host inserts `BinaryHttpServer`".
  ///
  /// `null` as long as `startService()` has not run through the update branch.
  BinaryHttpServer? get binaryHttpServer => _binaryHttpServer;

  UpdateManifest? get latestManifest => _latestManifest;

  // ══ THE COVER FILL (§5.5) — REGISTER, PUSH, ACCEPT ══════════
  //
  // These three callbacks are the seam between the signed manifest (which
  // the SERVICE holds) and the slot plan (which belongs to the NODE).
  // `attachV41` attaches them — the only place where service and node are
  // present at the same time, the same construction as for level D and the
  // HTTP switch.
  //
  // ── WHAT CHANGED BETWEEN S365 AND S367 ────────────────────
  //
  // In S365 `binary_fountain.dart` and `cover_fill_blocks.dart` were built,
  // but had ZERO callers in `lib/` — the way to the root `K_T` was an open
  // owner decision (step C). It was made on 04.09.2026, and with that these
  // callers exist.
  //
  // ── AND WHAT CHANGED AGAIN IN S368 ─────────────────────
  //
  // Here it said "option B: `K_T = HKDF(binaryHash, "update/root")`". This
  // version derived the root solely from the content hash — a field of the
  // PUBLIC manifest. So anyone could compute it, even outside the closed
  // network, and trial-open every cover cell (B-29 lifted). On 05.09.2026
  // the owner switched to the derivation from the NETWORK SECRET:
  // `K_T = HKDF(netzgeheimnis, "update/root/" ‖ binaryHash)`.
  // Justification and reversal probe stand at [binaryTransferRoot].

  /// Source and acceptance point of the cover fill, or `null` as long as no
  /// manifest has yielded a usable object.
  UpdateCoverFill? get updateCoverFill => _updateCoverFill;

  /// The platforms of in-network distribution.
  ///
  /// macOS and iOS are missing on purpose: §26.6.1 explicitly exempts them
  /// ("macOS and iOS are exempt from in-network distribution (DMG via
  /// GitHub Release, TestFlight); `shouldUseInNetworkUpdate()` returns
  /// `false` there").
  static const List<String> kCoverFillPlatforms = <String>[
    'android',
    'linux',
    'windows',
  ];

  /// Registers the objects of the last checked manifest with the cover
  /// fill (§5.5, §26.6.1).
  ///
  /// ── WHO REGISTERS WHAT, AND WHY ─────────────────────────────────────
  ///
  /// Three roles per object, and the assignment is not a preference:
  ///
  ///   * **Seeder** — this node holds the binary completely and
  ///     hash-checked. It encodes freshly, so it can supply arbitrarily many
  ///     different blocks. Precondition besides possession: it pushes at
  ///     all ([UpdateCoverFill.pushes]) and the object fits under
  ///     [kCoverFillMaxSeedBytes] — the encoder needs it whole in memory.
  ///   * **Collector** — the OWN platform, which this node does not have
  ///     yet. It assembles it; that is the purpose of the whole path.
  ///     Precondition: the object fits into its quota, otherwise it would
  ///     soak up bytes that never become a finished binary — and because
  ///     the quota counts over ALL objects, the others would starve along
  ///     with it.
  ///   * **Cache** — a FOREIGN platform. It does not decode it and never
  ///     assembles it; it holds a ring buffer and pushes on. §5.5
  ///     literally: "Blocks for other platforms are discarded or, on the
  ///     always-on tier, retained as cache."
  ///
  /// **The cache is the condition, not the extra.** Measured
  /// (`test/perf/perf_cover_fill_push_s365.dart`, 400 desktops): whoever
  /// throws away foreign blocks gets to 267-268 of 400 after over 90 days
  /// (cases A/C); whoever keeps them as cache, to 396 of 400 after 28 days
  /// (case E). The reason is the platform blindness from §5.4: without it
  /// propagation only runs via same-platform neighbours, and of those a
  /// node has 4/3 on average.
  ///
  /// ── THE MOBILE CLASS ─────────────────────────────────────────────────
  ///
  /// A mobile node ACCEPTS and does NOT PUSH (§9.3/E-53 "Mobile nodes hold
  /// no bulk" together with §5.5 "stores blocks within its platform tier's
  /// budget (§22.6) and discards the rest"; proposal
  /// `S365-VORLAGE-dritter-weg-und-wurzel.md` section 3, option a, chosen
  /// by the owner). It therefore only registers the own platform, gets
  /// [kCoverFillMobileBudgetBytes] and `pushes: false`.
  ///
  /// **The platform derivation stands HERE and not in `lib/core/update/`**
  /// — the same layer boundary as with `bulkCacheForPlatform`: the delivery
  /// layer and the update building blocks do not read `Platform.*`.
  Future<void> reportUpdateObjectsTo() async {
    final manifest = _latestManifest;
    final store = _binaryFragmentStore;
    if (manifest == null || store == null) return;

    final mobil = Platform.isAndroid || Platform.isIOS;
    final ownPlatform = Platform.operatingSystem;
    final platforms = mobil
        ? (kCoverFillPlatforms.contains(ownPlatform)
            ? <String>[ownPlatform]
            : const <String>[])
        : kCoverFillPlatforms;
    if (platforms.isEmpty) return;

    final fill = _updateCoverFill ??= UpdateCoverFill(
      // 32 random bytes per process. They do NOT have to stay secret and do
      // not have to hold across a restart — they are a scattering, not a
      // key (the header of `UpdateCoverFill` has the measurement: 0.0 %
      // duplicates versus 13.9 % if all seeders drew the same seed
      // sequence).
      seederSecret: SodiumFFI().randomBytes(32),
      pushes: !mobil,
      budgetBytes:
          mobil ? kCoverFillMobileBudgetBytes : kCoverFillBudgetBytes,
    );

    // Deregister objects of an outdated version BEFORE new ones join —
    // otherwise [kCoverFillMaxObjects] stands in the way, and the node would
    // keep collecting for a version nobody wants any more.
    for (final old in fill.objects.toList()) {
      if (old.version != manifest.version) {
        fill.unregister(old);
        _log.info('[update] cover fill: ${old.platform} v${old.version} '
            'deregistered (manifest is at v${manifest.version})');
      }
    }

    for (final platform in platforms) {
      final object = binaryFountainObjectFor(
        version: manifest.version,
        platform: platform,
        contentHashHex: manifest.binaryHashes?[platform],
        objectLength: manifest.binarySizes?[platform],
        // ── THE ROOT COMES FROM THE NETWORK SECRET (owner, 05.09.2026)
        //
        // NOT `NetworkSecret.outboundSecret`. During a rotation that
        // DELIBERATELY returns the OLD secret, so that outgoing packets get
        // through at neighbours not yet updated (`network_secret.dart:145`).
        // For the root that is the wrong way round: it is not a packet HMAC,
        // but the key under which BOTH sides collect the same object. During
        // a rotation the network would otherwise fall apart into two
        // collection sets that cannot open each other — see the finding on
        // rotation in the header of `binaryTransferRoot`.
        networkSecret: NetworkSecret.secret,
      );
      // No hash or no size in the manifest: the normal case for old
      // manifests and for platforms without in-network distribution.
      // Without a hash there is no root — it derives from network secret
      // AND content hash (decision B).
      if (object == null) continue;
      if (fill.objects.any((o) =>
          o.platform == object.platform && o.version == object.version)) {
        continue;
      }

      final own = platform == ownPlatform;

      // ── DOES THIS NODE ALREADY HAVE THE BINARY? ────────────────────────
      //
      // Existence is checked CHEAPLY and the file only read if it is also
      // needed. A `getComplete` without this switch would pull a 190 MB APK
      // into main memory on a phone, only to throw it away again at once.
      final restsBefore = store.hasCompleteSync(platform, object.version);
      final maySeed =
          fill.pushes && object.objectLength <= kCoverFillMaxSeedBytes;
      Uint8List? binary;
      if (restsBefore && maySeed) {
        // Reads AND checks the hash. If `null` comes back, the file does not
        // match the manifest — then the rest treats it as if it did not
        // exist, and the node collects anew.
        binary = await _completeBinary(store, object);
      }

      if (binary == null && restsBefore && !maySeed && own) {
        // It has its own binary and must not encode it (mobile, or larger
        // than [kCoverFillMaxSeedBytes]). There is nothing to collect and
        // nothing to push.
        _log.info('[update] cover fill: $platform v${manifest.version} '
            'is already complete — nothing to register');
        continue;
      }
      if (binary == null && !own && !fill.pushes) {
        // §5.5: "Blocks for other platforms are discarded or, ON THE
        // ALWAYS-ON TIER, retained as cache." A mobile node holds nothing
        // for strangers.
        continue;
      }

      final fits = plannedBlocksFor(object.objectLength) *
              kSealedBulkBlockBytes <=
          fill.budgetBytes;
      if (binary == null && own && !fits) {
        // ── WHY THIS IS AN EXCLUSION AND NOT A THROTTLING ────────
        //
        // The quota counts over ALL objects (`UpdateCoverFill.offer` checks
        // `acceptedBytes >= budgetBytes` before the assignment). Registering
        // an object that can never become complete would soak it empty and
        // let the others starve. Today this hits the full binaries above the
        // quota; as soon as the manifest carries deltas with hash and length
        // (§26.6.2), the case goes away.
        _log.info('[update] cover fill: $platform v${manifest.version} '
            '(${object.objectLength} B) does not fit into the quota '
            '${fill.budgetBytes} B — the harvest remains the path '
            '(§26.6.1)');
        continue;
      }

      final ok = fill.register(
        object,
        binary: binary,
        cache: binary == null && !own,
      );
      if (!ok) {
        _log.warn('[update] cover fill: $platform v${manifest.version} '
            'not registered — $kCoverFillMaxObjects objects occupied');
        continue;
      }
      _log.info('[update] cover fill: $platform v${manifest.version} '
          'registered as ${binary != null ? 'Seeder' : own ? 'Collector' : 'Cache'} '
          '(${object.objectLength} B, k=${object.sourceBlocks})');
    }
    _log.info('[update] cover fill: ${fill.objectCount} of '
        '$kCoverFillMaxObjects objects registered, quota '
        '${fill.budgetBytes} B, pushes: ${fill.pushes}');
  }

  /// The bytes of a complete binary from the fragment store —
  /// **only if their SHA-256 matches the object.**
  ///
  /// The check is not caution but duty: [BinaryFountainSeeder] throws on a
  /// deviation, and a seeder with the wrong content would distribute blocks
  /// that topple the whole version state at EVERY receiver (§26.6.1
  /// self-healing). The fragment store does not itself hold its
  /// `complete.bin` against the manifest — `_selfSeedInIsolate` only checks
  /// if an `expectedHash` came along.
  Future<Uint8List?> _completeBinary(
      BinaryFragmentStore store, BinaryFountainObject object) async {
    try {
      final bytes = await store.getComplete(object.platform, object.version);
      if (bytes == null) return null;
      if (bytes.length != object.objectLength) return null;
      if (!bytesEqualConstantTime(
          bulkContentHash(bytes), object.contentHash)) {
        _log.warn('[update] cover fill: complete.bin for '
            '${object.platform} v${object.version} does not match the '
            'manifest hash — NOT seeded');
        return null;
      }
      return bytes;
    } catch (e) {
      _log.debug('[update] cover fill: complete.bin not readable: $e');
      return null;
    }
  }

  /// The block for a cover slot that is due anyway — or `null` if nothing
  /// is pending. Then the cell stays random, as before.
  ///
  /// **No parameters, and that is rule 2** ("the schedule draws the
  /// partner, not the block"): the slot plan has long drawn the partner
  /// when this line runs, and it does not learn it.
  ///
  /// It stands HERE and not as `() => _updateCoverFill?.nextFillBlock()` in
  /// `attachV41`: there `lib/core/update/` is not imported, and the guard
  /// `smoke_delivery_layer_unwalked_guard` only counts a mention in a file
  /// that also imports the declaring one — otherwise `nextFillBlock` would
  /// still have counted as unentered, although the call is there.
  Uint8List? nextCoverFillBlock() =>
      _updateCoverFill?.nextFillBlock();

  /// Accepts an UNSOLICITED block from a cover slot (§5.5 rule 4 — nothing
  /// is sent back).
  ///
  /// The block ENDS HERE. It is not forwarded: that would be a cell of its
  /// own and thus rule 1 ("never a slot of its own"). That is why
  /// `BulkOp.publicBlock` does not stand in `kForwardableBulkOps` either,
  /// and `decrementBulkHops` returns `null` for it.
  void takeCoverFillBlock(Uint8List sealed) {
    final fill = _updateCoverFill;
    if (fill == null) return;
    final finding = fill.offer(sealed);
    if (finding != CoverFillVerdict.accepted) return;
    for (final object in fill.objects.toList()) {
      if (fill.progressOf(object) < 1.0) continue;
      final bytes = fill.tryAssemble(object);
      if (bytes != null) {
        unawaited(_adoptCoverFillBinary(object, bytes));
        continue;
      }
      // ── THE SELF-HEALING WAS MUTE (§26.6.1) ──────────────────────
      //
      // Collected completely and failed on the full SHA-256: per §26.6.1
      // "the entire version state … discarded and re-fetched". Without
      // this line that happens silently, and a node that a neighbour
      // poisons looks like one that simply gets nothing.
      //
      // UNTIL S368 THIS SAID "since the root is public (option B)". That no
      // longer holds as such: since 05.09.2026 the root derives from the
      // NETWORK SECRET, and an outsider cannot compute it
      // (`binaryTransferRoot`). The attack path nevertheless stays open, only
      // the circle is smaller: **every MEMBER of the network** has the
      // secret and the public manifest, computes the root from it and can
      // build a block with a valid seal and a corrupted payload. The seal
      // per block thus still does not reject a smuggler from within the
      // network — only one from outside.
      final error = fill.hashFailuresFor(object);
      _log.warn('[update] cover fill: ${object.platform} '
          'v${object.version} was complete, but the hash does '
          'not match — collection round discarded (§26.6.1). '
          '${fill.acceptedFor(object)} blocks taken, '
          '$error of $kCoverFillMaxHashFailures failures'
          '${error >= kCoverFillMaxHashFailures ? ' — this object '
              'accepts no more unsolicited blocks, the harvest '
              'remains the way' : ''}');
    }
  }

  /// Puts a binary assembled via the cover fill where the click path reads
  /// it.
  ///
  /// ── ONLY THE OWN PLATFORM, AND THAT IS MEASURED ──────────────────
  ///
  /// Storing a FOREIGN binary here would have a silent side effect:
  /// `_runBinaryFragmentGc` switches the fragment store to
  /// `BinaryFragmentStore.kBootstrapBudgetBytes` (unlimited) as soon as it
  /// finds a foreign platform that is not marked "on demand". The storage
  /// would thus be unlimited without anyone having decided that. Foreign
  /// platforms therefore stay in the cover fill's cache (ring buffer, hard
  /// limited) and are not assembled in the first place — see
  /// [reportUpdateObjectsTo].
  ///
  /// For the own platform, by contrast, the path is exactly the existing
  /// one: `complete.bin` is what `_startInNetworkUpdate` recognises as
  /// "already cached locally" and what `CleonaAppState.applyUpdate` hands
  /// to the system installer on Android (§26.6.1 step 6, memo
  /// `project_android_update_flow_v145.md`).
  Future<void> _adoptCoverFillBinary(
      BinaryFountainObject object, Uint8List bytes) async {
    _log.info('[update] cover fill: ${object.platform} v${object.version} '
        'fully assembled (${bytes.length} B, hash checked)');
    if (object.platform != Platform.operatingSystem) return;
    final store = _binaryFragmentStore;
    if (store == null) return;
    try {
      await store.storeComplete(object.platform, object.version, bytes);
      binaryHasContentToShare = true;
      _log.info('[update] cover fill: v${object.version} is now stored as '
          'complete.bin — the click path finds it (§26.6.1 step 6)');
    } catch (e) {
      _log.warn('[update] cover fill: complete.bin not writable: $e');
    }
  }


  // ── Update Checking (Architecture Section 17.5.5) ──────────────────

  bool _loadInNetworkFlag() {
    try {
      final f = File(
          '${AppPaths.dataDir}${Platform.pathSeparator}update_in_network.flag');
      return f.existsSync();
    } catch (_) {
      return false;
    }
  }


  /// Looks for a signed update manifest and authenticates it.
  ///
  /// Until S372 this said "Check the DHT … Uses FRAGMENT_RETRIEVE on the
  /// update manifest's DHT key". Neither exists any more: what is read is
  /// the LOCAL compartment [UpdateManifest.manifestStoreTag] in the
  /// `MailboxStore`. The signature check is unchanged.
  void _checkForUpdates() {
    final checker = UpdateChecker(log: _log);
    final depositCompartment = UpdateManifest.manifestStoreTag();

    // ── THE PEER POLL HAS FALLEN (CUT, 31.08.2026) ─────────────────
    //
    // Here a `FRAGMENT_RETRIEVE` on the manifest's storage compartment was
    // sent to EVERY known peer. Routing table and fragment request are
    // both gone.
    //
    // **Gap G-18.** What follows below still reads the LOCAL fragment
    // store — and that is filled by [_selfPublishManifest] from the
    // manifest file on disk. An update is thus still recognised if the
    // manifest is present locally (shipped along, from the cache, imported
    // via file); it is NO LONGER fetched from the network. The signature
    // check is unchanged — what arrives here must still be signed by the
    // maintainer.
    if (_updateCarrierField[this] == null) {
      _log.warn('[update] no update carrier set — only the '
          'local storage is read (gap G-18; the carrier closes it, '
          'S387)');
    }

    // Check collected fragments after a delay
    Timer(const Duration(seconds: 8), () {
      final localFrags = mailboxStore.retrieveFragments(depositCompartment);
      unawaited(_manifestsProcess(
          localFrags.map((f) => f.data).toList(), checker: checker));
    });
  }

  /// Checks manifest candidates (JSON bytes) — from the local compartment
  /// or from the update carrier (S387) — and reports a newer one via
  /// [onUpdateAvailable]. Until S387 the body stood in the timer of
  /// [_checkForUpdates]; it is unchanged, only the source is now a
  /// parameter.
  Future<void> _manifestsProcess(List<Uint8List> candidates,
      {UpdateChecker? checker}) async {
    checker ??= UpdateChecker(log: _log);
    {
      if (candidates.isEmpty) {
        _log.debug('[update] Poll returned 0 manifest fragments');
        return;
      }

      try {
        UpdateManifest? best;
        String? bestJson;
        for (final data in candidates) {
          try {
            final json = utf8.decode(data);
            final m = checker.verifyManifest(json);
            if (m == null) continue;
            if (best == null || checker.isNewer(m.version, best.version) ||
                (checker.isSameVersion(m.version, best.version) &&
                    (m.minMonotoneSeq ?? 0) > (best.minMonotoneSeq ?? 0))) {
              best = m;
              bestJson = json;
            }
          } catch (_) {}
        }
        if (best == null || bestJson == null) return;

        _log.info('[update] Poll: best manifest v${best.version} '
            '(from ${candidates.length} fragments)');

        final prev = _latestManifest;
        if (prev != null && !checker.isNewer(best.version, prev.version)) {
          if (checker.isNewer(prev.version, best.version)) {
            _log.debug('[update] Poll manifest v${best.version} older than cached v${prev.version}');
            // `_pushManifestToPeers(...)` stood here — the correction to the
            // peers that offered an older manifest (gap G-18).
            return;
          }
          final bestSeq = best.minMonotoneSeq ?? 0;
          final prevSeq = prev.minMonotoneSeq ?? 0;
          if (bestSeq <= prevSeq) {
            _log.debug('[update] No update available '
                '(manifest: v${best.version} seq=$bestSeq, '
                'cached: v${prev.version} seq=$prevSeq)');
            return;
          }
          _log.info('[update] Poll: same version v${best.version} '
              'but higher seq ($bestSeq > $prevSeq) — accepting');
        }

        _latestManifest = best;
        // S387: the carrier puts the newest manifest back into the compartment.
        final carrier = _updateCarrierField[this];
        if (carrier != null) {
          carrier.manifestKnown(Uint8List.fromList(utf8.encode(bestJson)));
          _ownObjectsHold(carrier);
        }
        // §5.5 — register the objects of the new version. No network
        // traffic: the registration at most reads `complete.bin` from the
        // own disk. From here on a cover slot that is due anyway carries a
        // block instead of filler bytes.
        unawaited(reportUpdateObjectsTo());
        try {
          final cacheFile = File('${AppPaths.dataDir}${Platform.pathSeparator}update_manifest_cache.json');
          cacheFile.parent.createSync(recursive: true);
          cacheFile.writeAsStringSync(bestJson, flush: true);
        } catch (e) {
          _log.debug('Failed to cache update manifest: $e');
        }
        final isNewer = checker.isNewer(best.version, currentAppVersion);

        if (isNewer) {
          _log.info('[update] Update available: v${best.version} '
              '(current: v$currentAppVersion)');

          final isHardBlock = checker.isHardBlocked(best, currentAppVersion);
          final hasBinTag = best.binaryTag
                  ?.containsKey(Platform.operatingSystem) ??
              false;
          final hasBinHash = best.binaryHashes
                  ?.containsKey(Platform.operatingSystem) ??
              false;
          if (!isHardBlock && !hasBinTag && !hasBinHash) {
            _log.debug('[update] Suppressing soft-update notification: '
                'no binary for ${Platform.operatingSystem}');
          } else {
            var inNetworkAvailable = false;
            if ((hasBinTag || hasBinHash) && _binaryUpdateManager != null) {
              try {
                inNetworkAvailable = await _binaryUpdateManager!
                    .checkForUpdate(best, currentAppVersion, Platform.operatingSystem);
                if (inNetworkAvailable) {
                  _log.info('[update] In-network update available for '
                      '${Platform.operatingSystem}: v${best.version}');
                  _saveInNetworkFlag(true);
                }
              } catch (e) {
                _log.debug('[update] In-network update check failed: $e');
              }
            }

            onUpdateAvailable?.call(best, inNetworkAvailable);
          }
        } else {
          _log.debug('[update] No update available '
              '(manifest: v${best.version}, current: v$currentAppVersion)');
        }

        // `_pushManifestToPeers(bestData)` stood here (gap G-18) — since
        // S387 the carrier puts it back (`manifestKnown` above).
      } catch (e) {
        _log.debug('[update] Update manifest check failed: $e');
      }
    }
  }


  /// §19.6.2 fragment-store housekeeping: drops fragments/complete binaries
  /// for versions superseded by [CleonaService.kCurrentAppVersion] and enforces a
  /// platform-dependent storage budget on what's left. Invoked once at
  /// startup and then hourly via [_binaryGcTimer].
  Future<void> _runBinaryFragmentGc() async {
    final updater = _binaryUpdateManager;
    final store = _binaryFragmentStore;
    if (updater == null || store == null) return;

    final currentPlatform = Platform.operatingSystem;

    // §19.6.4: drop on-demand foreign binaries past their TTL first, so the
    // budget decision below sees the post-eviction state.
    final acquirer = _foreignBinaryAcquirer;
    try {
      final n = await (acquirer?.evictExpired() ?? Future.value(0));
      if (n > 0) _log.info('[update] evicted $n expired on-demand binary/-ies');
    } catch (e) {
      _log.debug('[update] on-demand eviction failed: $e');
    }

    // Cross-platform content switches the store to the unlimited bootstrap
    // budget — but ONLY when the node deliberately seeds other platforms.
    // An on-demand acquisition is transient and must not disable the budget
    // for the whole store, otherwise one visitor permanently unbounds it.
    final hasCrossPlatform = ['android', 'linux', 'windows', 'macos', 'ios']
        .where((p) => p != currentPlatform)
        .any((p) => store.storedVersionsSync(p)
            .any((v) => acquirer == null || !acquirer.isOnDemand(p, v)));
    final budgetBytes = hasCrossPlatform
        ? BinaryFragmentStore.kBootstrapBudgetBytes
        : (Platform.isAndroid || Platform.isIOS)
            ? BinaryFragmentStore.kMobileBudgetBytes
            : BinaryFragmentStore.kDesktopBudgetBytes;

    try {
      updater.gc(CleonaService.kCurrentAppVersion, budgetBytes);
    } catch (e) {
      _log.debug('[update] Fragment GC failed: $e');
    }
  }


  /// Collects, assembles and checks the update for [manifest] (v4_2
  /// §26.6.1 steps 4-5).
  ///
  /// **Since S387 without user action** (owner decision 14.09.2026): the
  /// caller is `UpdateOffer.onManifest` in the daemon or in
  /// `CleonaAppState`, triggered by [onUpdateAvailable]. Here it said "once
  /// … the user has consented to installing … the UI calls this" — that was
  /// the download click, which no longer exists. NOTHING is installed here:
  /// the run ends in `BinaryUpdateState.ready`, and only the click on
  /// "Installieren" (`UpdateOffer.consent`) installs.
  Future<void> startInNetworkUpdate(UpdateManifest manifest) =>
      _startInNetworkUpdate(manifest);


  /// Orchestrates the full in-network update flow (§19.6.2): resolve
  /// binary sources via [BinaryRendezvousManager], download erasure-coded
  /// fragments (or the full binary in one shot when a peer has it) from
  /// those sources, assemble + verify the result against the
  /// maintainer-signed hash carried in [manifest], and seed the verified
  /// binary back into this node's fragment store so it becomes a
  /// distribution source for other nodes too.
  Future<void> _startInNetworkUpdate(UpdateManifest manifest) async {
    // S287: the UI may hold a stale cached manifest (e.g. v3.1.158) while
    // the poll has already promoted _latestManifest to a newer version
    // (e.g. v3.1.159). Using the stale manifest causes a binSize mismatch
    // because expectedSize comes from the manifest's binarySizes map.
    final latest = _latestManifest;
    if (latest != null) {
      final checker = UpdateChecker(log: _log);
      if (checker.isNewer(latest.version, manifest.version)) {
        _log.info('startInNetworkUpdate: upgrading stale UI manifest '
            'v${manifest.version} → v${latest.version}');
        manifest = latest;
      }
    }

    final platform = Platform.operatingSystem;
    final store = _binaryFragmentStore;
    final updater = _binaryUpdateManager;
    final fetchClient = _binaryFetchClient;
    final seeder = _binarySeeder;
    if (store == null || updater == null || fetchClient == null || seeder == null) {
      _log.warn('startInNetworkUpdate: binary-update subsystem not initialized');
      return;
    }

    // ── Z1: A NEWER MANIFEST MOVES THE TARGET IMMEDIATELY (§26.6.1) ─────
    //
    // "The node switches to the newest target at once; pieces that do not
    // serve it are discarded. An outdated version is never offered." The
    // outdated run ends at [_updateSuperseded] after every wait; what it has
    // stored for the old version is discarded here — even an already fully
    // checked one that had not been installed yet.
    final soFar = _updateCollectTarget[this];
    _updateCollectTarget[this] = manifest.version;
    if (soFar != null &&
        soFar != manifest.version &&
        soFar != currentAppVersion) {
      _log.info('startInNetworkUpdate: target v$soFar -> v${manifest.version} '
          '— pieces of the old version are discarded (Z1)');
      _updateCarrierField[this]?.fetchAbort();
      unawaited(store.deleteVersion(platform, soFar));
    }
    onUpdateStateChanged?.call(BinaryUpdateState.checking, 0.0);

    // The manifest's per-platform hash/signature/size is the trust anchor —
    // without it there is nothing to verify the downloaded binary against,
    // so refuse rather than install an unverified download.
    final expectedHash = manifest.binaryHashes?[platform];
    final signatureB64 = manifest.binarySignatures?[platform];
    final originalSize = manifest.binarySizes?[platform];
    if (expectedHash == null || signatureB64 == null || originalSize == null) {
      _log.warn('startInNetworkUpdate: manifest v${manifest.version} has no '
          'binaryHash/signature/size for platform=$platform — cannot verify, aborting');
      onUpdateStateChanged?.call(BinaryUpdateState.idle, 0.0);
      return;
    }
    final Uint8List signatureBytes;
    try {
      signatureBytes = base64Decode(signatureB64);
    } catch (e) {
      _log.warn('startInNetworkUpdate: malformed binarySignature for platform=$platform: $e');
      onUpdateStateChanged?.call(BinaryUpdateState.idle, 0.0);
      return;
    }

    // 3. Reed-Solomon parameters for this platform (§19.6.2).
    final params = BinarySeeder.paramsFor(platform);

    // ── SOURCE 0: THE FETCH PATH OF THE DELIVERY LAYER (S387, P1) ────────────
    //
    // §26.6.1 "The fetch path": pieces of ONE object from a holder,
    // independent of the cover stream. If it delivers, the check happens
    // BEFORE storing (S388, `PhysicalTransferHelper.importAndVerifyBytes`:
    // SHA-256 + maintainer signature) — `complete.bin` has readers that do
    // not wait for step 8 (HTTP delivery `binaryProvider`, the fast path
    // after a restart). Step 8 checks once more afterwards and sets
    // `ready`. If it does not deliver, the previous sources remain.
    //
    // What is fetched is the FULL binary: a delta (§26.6.2, D1) would
    // presuppose bspatch, and `DeltaUpdateManager.applyDelta` has none
    // (report S387).
    final carrier = _updateCarrierField[this];
    if (carrier != null &&
        !File(store.completePath(platform, manifest.version)).existsSync()) {
      onUpdateStateChanged?.call(BinaryUpdateState.downloading, 0.0);
      Uint8List? fetched;
      try {
        fetched = await carrier.piecesFetch(
            contentHash: hexToBytes(expectedHash), length: originalSize);
      } catch (e) {
        _log.warn('startInNetworkUpdate: fetch path failed: $e');
      }
      if (_updateSuperseded(manifest.version)) return;
      if (fetched != null && fetched.length == originalSize) {
        final helper = _physicalTransferHelper;
        final checked = helper != null &&
            await helper.importAndVerifyBytes(
              data: fetched,
              platform: platform,
              version: manifest.version,
              expectedHash: expectedHash,
              maintainerSignature: signatureBytes,
            );
        if (_updateSuperseded(manifest.version)) return;
        if (checked) {
          _log.info('startInNetworkUpdate: v${manifest.version} fetched via the '
              'fetch path of the delivery layer and checked '
              '(${fetched.length} B)');
        } else {
          _log.warn('startInNetworkUpdate: v${manifest.version} from the fetch path '
              'did not pass the check — not stored'
              '${helper == null ? ' (no check helper)' : ''}');
        }
      } else {
        _log.info('startInNetworkUpdate: the fetch path did not deliver v'
            '${manifest.version} — the remaining sources');
      }
    }

    // Fast path: if the complete binary is already in the local fragment
    // store (e.g. from a previous download or self-seeding), skip the
    // network download and go straight to assemble+verify.
    final localComplete = File(store.completePath(platform, manifest.version));
    if (localComplete.existsSync() && localComplete.lengthSync() == originalSize) {
      _log.info('startInNetworkUpdate: complete binary already cached locally '
          '(${localComplete.lengthSync()}B) — skipping download');
    } else {
      // ── TWO SOURCE CLASSES, IN THIS ORDER (§26.6.4, S372) ──
      //
      // Class 1: the Nostr rendezvous. Its records name the version, they
      // are therefore filtered and stand at the FRONT.
      //
      // Class 2: the entry cascade (§11). §26.6.4 verbatim: "A publishing
      // node that holds a complete binary set is reachable through the same
      // entry cascade the inviter's `s=` ContactSeed encodes". Until S372
      // this class did not exist — the fetch only knew Nostr and aborted
      // without relays, although the node's pool held reachable neighbours
      // whose data port serves exactly the delivery server after
      // `attachV41`.
      //
      // WHY BEHIND AND NOT BEFORE. An entry record names no version; a Nostr
      // record names it and is thus the more precise source. The less
      // precise one costs nothing, because it only gets its turn when the
      // precise one yielded nothing — and because a neighbour with the
      // wrong version fails at the Content-Length check of
      // `BinaryFetchClient.fetch` BEFORE the first payload byte (expected
      // size = `binarySizes` from the SIGNED manifest). Whatever got through
      // after that is caught by step 8 (SHA-256 + Ed25519).
      //
      // WHAT THIS PLACE DOES NOT DECIDE. §26.6.4 withdraws the external
      // carrier completely, §26.7 continues it ("the Nostr publishing key of
      // the binary distribution"). The contradiction lies with the owner
      // (finding at `BinaryRendezvousManager.publish`). Here the cascade
      // steps NEXT TO Nostr, not in its place — both answers stay buildable.
      final resolvedAll =
          await _binaryRendezvousManager?.resolve(platform) ??
              const <ResolvedBinaryEndpoint>[];
      // Filter: only sources advertising the target version (V3.1.149 hardening).
      // Prevents downloading stale binaries from nodes that haven't seeded yet.
      final resolved = resolvedAll
          .where((ep) => ep.version == manifest.version)
          .toList();
      if (resolved.isEmpty && resolvedAll.isNotEmpty) {
        _log.info('startInNetworkUpdate: ${resolvedAll.length} rendezvous '
            'source(s) found but none advertise v${manifest.version} '
            '(versions seen: '
            '${resolvedAll.map((e) => e.version).toSet().join(', ')}) — '
            'the entry cascade remains (§26.6.4)');
      }

      // 2. Convert ResolvedBinaryEndpoint -> FragmentSource.
      // Enrich with routing-table addresses: the Rendezvous record only
      // carries public IPs, but LAN peers are reachable via their private
      // addresses in the routing table. Append those as extra targets so
      // the download layer can reach them even without public IPv4/IPv6.
      // Interleave addresses across devices (round-robin) so the download
      // layer quickly tries one address per device instead of exhausting all
      // addresses of device A before ever contacting device B.
      final perDevice = resolved.map((ep) {
        final allAddrs = <EndpointAddress>[...ep.addresses];
        // FORMERLY the peer's LAN addresses from the routing table were
        // mixed in here: the rendezvous record only names public addresses,
        // but a neighbour in the same network is reachable via its private
        // one. Without a routing table it stays with what the record names —
        // a download in the LAN behind the same NAT may thus not find the
        // other side (part of gap G-11).
        return allAddrs
            .map((addr) => FragmentSource(
                  address: addr,
                  fragmentIndices: ep.fragmentIndices,
                  hasFullBinary: ep.hasFullBinary,
                ))
            .toList();
      }).toList();
      final fragmentSources = <FragmentSource>[];
      var idx = 0;
      bool added;
      do {
        added = false;
        for (final addrs in perDevice) {
          if (idx < addrs.length) {
            fragmentSources.add(addrs[idx]);
            added = true;
          }
        }
        idx++;
      } while (added);

      // 3. The entry cascade behind it (§26.6.4). The pool belongs to the
      // node; `attachV41` passes it in as [binarySourcesOutEntry]. Without a
      // running V4.1 node the callback is `null`, and the list stays empty —
      // then this place behaves as before S372.
      //
      // `hasFullBinary: true` and no fragment indices: a neighbour's
      // delivery server always serves `/cleona/binary/<plattform>`, this
      // node does not know its fragment set. A neighbour without a matching
      // file answers with 404, and `fetch` returns `null` — the loop in
      // `BinaryUpdateManager.startDownload` goes to the next source.
      final outEntry =
          binarySourcesOutEntry?.call() ?? const <EndpointAddress>[];
      var outCascade = 0;
      for (final addr in outEntry) {
        if (fragmentSources.any((s) =>
            s.address.ip == addr.ip && s.address.port == addr.port)) {
          continue;
        }
        fragmentSources.add(FragmentSource(
          address: addr,
          fragmentIndices: const <int>[],
          hasFullBinary: true,
        ));
        outCascade++;
      }

      if (fragmentSources.isEmpty) {
        _log.warn('startInNetworkUpdate: no binary source for '
            'platform=$platform — rendezvous delivered ${resolvedAll.length} '
            'record(s) (of which ${resolved.length} in the right '
            'version), the entry cascade ${outEntry.length} address(es)');
        onUpdateStateChanged?.call(BinaryUpdateState.idle, 0.0);
        return;
      }
      _log.info('startInNetworkUpdate: ${fragmentSources.length} source(s) '
          'for $platform v${manifest.version} — ${resolved.length} from the '
          'rendezvous, $outCascade from the entry cascade (§26.6.4)');

      // 4./5. Delta path (§19.6.3): findDeltaPath() is a free, side-effect-free
      // check — only logged here. Actually applying a delta requires
      // libcleona_bsdiff, which DeltaUpdateManager.applyDelta() documents as
      // not yet implemented (always returns null), and the manifest carries no
      // delta-hash trust anchor yet either. So this stays a guarded no-op
      // until both land — full-binary download below is the functioning path.
      final deltaFromVersion = _deltaUpdateManager?.findDeltaPath(
        manifest: manifest,
        currentVersion: currentAppVersion,
        platform: platform,
      );
      if (deltaFromVersion != null) {
        _log.debug('startInNetworkUpdate: delta path $deltaFromVersion -> '
            '${manifest.version} advertised, but bsdiff is not yet wired — '
            'falling back to full binary');
      }

      // 6. Download (full binary in one shot if a source has it, else
      // K-of-N fragments assembled below).
      await updater.startDownload(
        platform: platform,
        version: manifest.version,
        n: params.n,
        k: params.k,
        expectedHash: expectedHash,
        sources: fragmentSources,
        fetchFragment: (addr, plat, idx) => fetchClient.fetch(addr, plat, idx),
        fetchWithSize: fetchClient.fetch,
        expectedSize: originalSize,
      );
      if (_updateSuperseded(manifest.version)) return;
      if (updater.state == BinaryUpdateState.failed) {
        _log.warn('startInNetworkUpdate: download failed: ${updater.errorMessage}');
        return;
      }
    }

    // 7. Assemble the binary from downloaded fragments (or reuse the
    // complete binary if a full-binary fetch already stored it).
    if (_updateSuperseded(manifest.version)) return;
    final binary = await updater.assemble(
        platform, manifest.version, params.n, params.k, originalSize);
    if (_updateSuperseded(manifest.version)) return;
    if (binary == null) {
      _log.warn('startInNetworkUpdate: assemble failed: ${updater.errorMessage}');
      // RS decode exception = corrupt fragments → purge cache to allow fresh download
      // "Cannot assemble: have/only N fragments" = transient → preserve partial download
      if (updater.errorMessage != null && updater.errorMessage!.contains('assemble failed:')) {
        _log.warn('startInNetworkUpdate: corrupt fragment cache detected, purging v${manifest.version} ($platform)');
        await store.deleteVersion(platform, manifest.version);
      }
      return;
    }

    // 8. Verify SHA-256 hash + Ed25519 maintainer signature over that hash.
    // On success this also fires BinaryUpdateManager.onUpdateReady, which
    // republishes this node's binary-availability record.
    final verified = await updater.verify(binary, expectedHash, signatureBytes);
    if (_updateSuperseded(manifest.version)) return;
    if (!verified) {
      _log.error('startInNetworkUpdate: verification FAILED for v${manifest.version} '
          '($platform) — refusing to seed or offer for install, purging all fragments');
      await store.deleteVersion(platform, manifest.version);
      return;
    }

    binaryHasContentToShare = true;
    _log.info('startInNetworkUpdate: v${manifest.version} verified and ready '
        '(${binary.length}B)');
    // S387: checked and complete — an always-on node now holds it for
    // others (§26.6.1).
    final carrierAfter = _updateCarrierField[this];
    if (carrierAfter != null) _ownObjectsHold(carrierAfter);

    // 9. Seed — encode into RS fragments so this node also becomes a
    // fragment-serving distribution source, not just a full-binary source.
    // Fire-and-forget: RS encoding is CPU-intensive (synchronous FFI) and
    // must not block the auto-install flow on Android.
    final maxFragments = Platform.isAndroid || Platform.isIOS ? 2 : 8;
    unawaited(Future(() async {
      final seededCount = await seeder.seed(
        binary: binary,
        platform: platform,
        version: manifest.version,
        maxFragments: maxFragments,
      );
      _log.info('startInNetworkUpdate: seeded $seededCount fragment(s) for '
          'v${manifest.version}');
    }));
  }


  /// Extracted from [startService] (S331, §4c.2f) — pure move,
  /// body verbatim unchanged. Block boundaries: docs/analysis/start_service_blocks.tsv.
  Future<void> _initInNetworkUpdate() async {
    // §19.6 Censorship-Resistant Distribution: in-network binary updates.
    // Node-wide subsystem (fragment store on disk, one embedded HTTP server
    // on the shared transport, one Nostr rendezvous manager) — only the
    // first identity's service on this daemon wires it up, mirroring the
    // node.rendezvousManager ??= _rendezvousManager first-wins pattern above.
    // FORMERLY the guard was `node.binaryRendezvousManager == null` — the
    // "first identity wins" pattern for a NODE-WIDE subsystem. Without a
    // shared node every service builds its own; the fragment store lies in
    // the profile directory anyway and was thus per identity even before.
    if (_binaryRendezvousManager == null) {
      await InstallSourceDetector.detect();

      _binaryFragmentStore = BinaryFragmentStore(profileDir);
      await _binaryFragmentStore!.init();

      _binaryUpdateManager = BinaryUpdateManager(
        store: _binaryFragmentStore!,
        checker: UpdateChecker(log: _log),
        profileDir: profileDir,
      );
      _deltaUpdateManager = DeltaUpdateManager(
        store: _binaryFragmentStore!,
        log: _log,
      );
      _inviteLinkService = InviteLinkService(profileDir: profileDir);
      _physicalTransferHelper = PhysicalTransferHelper(
        store: _binaryFragmentStore!,
        profileDir: profileDir,
      );
      _binarySeeder = BinarySeeder(store: _binaryFragmentStore!, profileDir: profileDir);
      _binaryFetchClient = BinaryFetchClient(profileDir: profileDir);
      // Once a download is verified and ready, this device becomes a
      // legitimate distribution source — (re)publish availability so
      // other cold-starting nodes can find it.
      _binaryUpdateManager!.onUpdateReady = (version, path) {
        binaryHasContentToShare = true;
        _binaryRendezvousManager?.startPeriodicRefresh(_buildBinaryAvailabilityRecords);
        _binaryRendezvousManager?.publishAll(_buildBinaryAvailabilityRecords());
      };
      _binaryUpdateManager!.onStateChanged = (state, progress) {
        onUpdateStateChanged?.call(state, progress);
      };

      _binaryHttpServer = BinaryHttpServer(profileDir: profileDir);
      _binaryHttpServer!.bootstrapWebApp = Uint8List.fromList(
          utf8.encode(BootstrapWebApp.html(
              maintainerPublicKeyHex: UpdateChecker.maintainerPublicKeyHex)));
      _binaryHttpServer!.binaryProvider = (platform) {
        final versions = _binaryFragmentStore!.storedVersionsSync(platform);
        if (versions.isEmpty) return null;
        return _binaryFragmentStore!.getCompletePath(platform, versions.last);
      };
      _binaryHttpServer!.fragmentProvider = (platform, index) {
        final versions = _binaryFragmentStore!.storedVersionsSync(platform);
        if (versions.isEmpty) return null;
        return _binaryFragmentStore!.getFragmentSync(platform, versions.last, index);
      };
      // ── GAP G-20 IS CLOSED (S361) — WHERE, AND WHY NOT HERE ──
      //
      // `node.transport.httpServer = _binaryHttpServer` stood here. The V3
      // transport also accepted HTTP on ITS TCP port and pushed the request
      // on to here — §26.6.5 names exactly that as the reason (the same
      // port for link handshake and delivery, "it keeps automatic scanners
      // away").
      //
      // The successor stands in `attachV41` (`lib/core/tagline/
      // v41_attach.dart`), and the place is not arbitrary: the V4.1 node
      // holds the port and stands BEFORE the services in both composition
      // points — it supplies them with the port. Here, in the service, the
      // listener does not exist yet at all. `attachV41` is the only place
      // where node and service are present at the same time; the same
      // justification already carries level D and the network statistics
      // there. E-118 verbatim: "the node host inserts `BinaryHttpServer`".
      //
      // WHAT STOOD HERE UNTIL S361 was wrong twice and right once.
      // Wrong: "V4.1 has a TCP listener, but no switch in it" — the switch
      // was complete (`tcp_listener.dart`: `typedef LinkHttpSink`, the
      // field `httpSink`, `_handOverHttp` including the E-83 null case).
      // Wrong too the conclusion "the in-network update path is dead": per
      // §26.6.1 the update itself travels via the fountain layer, not via
      // HTTP. Right was the core: **no production code constructed a
      // `TcpLinkListener`** — and on that hung not only the delivery
      // (§26.6.4/§26.6.5, step 3 of the distribution ladder §26.6.7), but
      // EVERY incoming TCP link handshake.
      //
      // The access to the server is the getter [binaryHttpServer] above.

      _binaryRendezvousManager = BinaryRendezvousManager(profileDir: profileDir);
      _binaryRendezvousManager!.init(
        networkSecret: NetworkSecret.secret,
        previousNetworkSecret: NetworkSecret.previousSecret,
        deviceId: identity.deviceNodeId,
        // FORMERLY `node.currentSelfAddresses()` — the addresses the V3
        // transport knew of itself (local, UPnP-mapped, STUN-observed).
        // V4.1 knows only the local ones (§4.5, `localIps`) and no public
        // one (gap G-12); the port is that of the service.
        addressProvider: () =>
            localIps.map((ip) => RendezvousAddress(ip, port)).toList(),
      );
      // `node.binaryRendezvousManager` and `node.binaryRecordProvider`
      // stood here: with them the node answered infrastructure requests for
      // binary records. No node, no infra requests (T).

      // §19.6.4: serve platforms this node does not run, on demand. Always
      // active and hard-bounded inside the acquirer — one acquisition at a
      // time, one foreign binary stored, 24h TTL eviction.
      _foreignBinaryAcquirer = ForeignBinaryAcquirer(
        store: _binaryFragmentStore!,
        fetchClient: _binaryFetchClient!,
        rendezvous: () => _binaryRendezvousManager,
        profileDir: profileDir,
      );
      _binaryHttpServer!.onForeignBinaryRequested = (platform) {
        if (platform == Platform.operatingSystem) return;
        _foreignBinaryAcquirer!.requestAcquire(platform, _latestManifest);
      };
      _binaryHttpServer!.foreignStatusProvider = (platform) =>
          _foreignBinaryAcquirer!.statusFor(platform).toJson();

      // Working rule #5 (no unnecessary network traffic): only start the
      // periodic Nostr republish if this device already holds binary/
      // fragment data worth advertising. Devices with an empty store stay
      // silent until BinaryUpdateManager.onUpdateReady flips the flag above.
      binaryHasContentToShare = ['android', 'linux', 'windows', 'macos', 'ios']
              .any((p) => _binaryFragmentStore!.storedVersionsSync(p).isNotEmpty);
      if (binaryHasContentToShare) {
        _binaryRendezvousManager!.startPeriodicRefresh(_buildBinaryAvailabilityRecords);
        _binaryRendezvousManager!.publishAll(_buildBinaryAvailabilityRecords());
      }

      // Self-seed: encode the running binary into RS fragments so this node
      // can serve updates (§19.6.2). Fire-and-forget: the Isolate-based
      // RS encoding of the ~90 MB binary must not block conversation loading
      // and node bootstrap. The seed sets binaryHasContentToShare + starts
      // rendezvous publishing on completion (line 10606-10608).
      if (InstallSourceDetector.cached != InstallSource.playStore) {
        unawaited(_selfSeedCurrentBinary());
      }

      _selfPublishManifest();
      // The delayed follow-up push at T+90 s (F2) stood here: the first
      // `_selfPublishManifest` ran before UDP was listening, i.e. with zero
      // peers. Without a push path the second attempt has no subject
      // (gap G-18).

      // §19.6 fragment GC — prune old/excess fragment data once per hour,
      // and once immediately at startup to clean up stale data from
      // previous runs.
      _runBinaryFragmentGc();
      _binaryGcTimer = Timer.periodic(const Duration(hours: 1), (_) {
        _runBinaryFragmentGc();
      });
    }
  }


  /// Extracted from [startService] (S331, §4c.2f) — pure move,
  /// body verbatim unchanged. Block boundaries: docs/analysis/start_service_blocks.tsv.
  void _initUpdateChecking() {
    // Update checking: bootstrap _latestManifest from cache so the version
    // guard in _checkForUpdates rejects stale stored fragments on the very first
    // poll (otherwise _latestManifest is null → any version passes).
    try {
      final cacheFile = File(
          '${AppPaths.dataDir}${Platform.pathSeparator}update_manifest_cache.json');
      if (cacheFile.existsSync()) {
        final cached = UpdateChecker(log: _log)
            .verifyManifest(cacheFile.readAsStringSync());
        if (cached != null) _latestManifest = cached;
      }
    } catch (_) {}
    // Startup scan: check mailbox store for manifest fragments that were
    // stored but never processed (e.g. handler failed after store, crash,
    // or duplicate-identical race). Process any that are newer than cache.
    try {
      final depositCompartment = UpdateManifest.manifestStoreTag();
      final storedFrags = mailboxStore.retrieveFragments(depositCompartment);
      if (storedFrags.isNotEmpty) {
        final checker = UpdateChecker(log: _log);
        for (final frag in storedFrags) {
          try {
            final json = utf8.decode(frag.data);
            final m = checker.verifyManifest(json);
            if (m == null) continue;
            if (_latestManifest == null ||
                checker.isNewer(m.version, _latestManifest!.version)) {
              _latestManifest = m;
              try {
                final cacheFile = File(
                    '${AppPaths.dataDir}${Platform.pathSeparator}update_manifest_cache.json');
                cacheFile.parent.createSync(recursive: true);
                cacheFile.writeAsStringSync(json, flush: true);
              } catch (_) {}
              _log.info('[update] Startup scan: found stored manifest '
                  'v${m.version} (promoted from mailbox store)');
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
    // If the cached manifest is already newer than the running version,
    // fire the notification directly after a short delay (UI is ready by
    // then). This bypasses checkForUpdate() intentionally — the monotoneSeq
    // anti-downgrade guard in checkForUpdate() correctly rejects the same
    // manifest on restart (§19.6.2: "lower than or equal to"), which is the
    // right behavior for first-time discovery but wrong for re-notification.
    // Instead, we read the persisted inNetworkAvailable flag that was saved
    // when the manifest was first successfully checked.
    // §5.5 — also at start, not only at the next harvest. The cached
    // manifest is already checked (`UpdateChecker.verifyManifest`), and
    // without this line a node would again fill only randomness into its
    // cover slots after every restart until the next query (30 s, then 6 h).
    unawaited(reportUpdateObjectsTo());
    if (_latestManifest != null) {
      final cachedManifest = _latestManifest!;
      final checker = UpdateChecker(log: _log);
      if (!checker.isNewer(cachedManifest.version, CleonaService.kCurrentAppVersion)) {
        _saveInNetworkFlag(false);
      } else {
        Timer(const Duration(seconds: 5), () {
          _log.info('[update] Cached manifest v${cachedManifest.version} '
              'is newer than running v${CleonaService.kCurrentAppVersion} — re-firing notification');
          final hasBinTag = cachedManifest.binaryTag
                  ?.containsKey(Platform.operatingSystem) ??
              false;
          final hasBinHash = cachedManifest.binaryHashes
                  ?.containsKey(Platform.operatingSystem) ??
              false;
          if (!hasBinTag && !hasBinHash) {
            _log.debug('[update] Suppressing cached-update notification: '
                'no binary for ${Platform.operatingSystem}');
          } else {
            var inNetworkAvailable = _loadInNetworkFlag();
            if (!inNetworkAvailable && (hasBinTag || hasBinHash)) {
              inNetworkAvailable =
                  _binaryUpdateManager?.shouldUseInNetworkUpdate() ?? false;
            }
            onUpdateAvailable?.call(cachedManifest, inNetworkAvailable);
          }
        });
      }
    }
    Timer(const Duration(seconds: 30), _checkForUpdates); // Initial check after 30s
    Timer(const Duration(minutes: 5), _checkForUpdates); // F3: one retry for mobile
    _updateCheckTimer = Timer.periodic(const Duration(hours: 6), (_) => _checkForUpdates());
  }
}
