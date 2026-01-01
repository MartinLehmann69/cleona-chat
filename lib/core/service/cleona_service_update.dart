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

/// The target this service collects for (S406-UPDPKG P1): an object and
/// the sequence number that names it — `updateTargetFor`. Until S406 this
/// was the version string (`_updateCollectTarget`, finding B-3). Next to the
/// service instead of in it, as since S387.
final Expando<UpdateTarget> _updateTargetField =
    Expando<UpdateTarget>('updateTarget');

/// The update carrier of the delivery layer (S387). Next to the service,
/// for the same reason as [_updateTargetField].
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
    // The target completed by cover fill, outside a fetch (P3).
    carrier.onObjectComplete = (hash, path) {
      final t = _updateTargetField[this];
      if (t == null || !_sameHash(t.object, hash)) return;
      // A delta that falls back moves the target to the full binary; the
      // next moment fetches it (no fetch outside a moment, §26.5.4).
      unawaited(_objectComplete(t.manifest, t, path).catchError((Object e) {
        _log.warn('[update] completing $t by cover fill failed: $e');
        return false;
      }));
    };
    // Both own manifest files, not only the cache (S406-UPD, finding U-3):
    // the bootstrap knows its manifest from `update_manifest.json` alone.
    final handed =
        ownManifestsToCarrier(AppPaths.dataDir, carrier, report: _log.debug);
    _log.info('[update] carrier: $handed own manifest file(s) handed over');
    _ownObjectsHold(carrier);
    updateTrace('ask', reason: 'moment start (update carrier set)');
    unawaited(carrier.manifestAsk());
  }

  /// A moment per M1+ — network change, app open, new neighbour. The seam
  /// calls it; this file has no timer for it.
  ///
  /// [moment] names the moment for the diagnosis line only (S406-UPD2).
  Future<void> updateManifestAsk({String moment = 'unnamed'}) async {
    final carrier = _updateCarrierField[this];
    if (carrier == null) return;
    updateTrace('ask', reason: 'moment $moment');
    await carrier.manifestAsk();
  }

  /// Always-on nodes (desktop) hold every complete object of the current
  /// manifest for others (§26.6.1, §5.5 "What a node keeps"); mobile ones
  /// hold nothing for others.
  void _ownObjectsHold(UpdateCarrier carrier) {
    final manifest = _latestManifest;
    final store = _binaryFragmentStore;
    if (manifest == null || store == null) return;
    if (Platform.isAndroid || Platform.isIOS) return;
    for (final platform in kInNetworkPlatforms) {
      final hash = manifest.binaryHashes?[platform];
      if (hash == null || !store.hasCompleteSync(platform, manifest.version)) {
        continue;
      }
      // From the file, never into memory (S406-OOM): the android object
      // is ~200 MB, and the holder used to load it whole on the first
      // cover packet.
      carrier.objectHoldFile(
          hexToBytes(hash), store.completePath(platform, manifest.version));
      _log.info('[update] carrier: $platform v${manifest.version} is '
          'held for others');
    }
    // The android deltas of the current manifest (§26.6.2 "a delta is simply
    // a smaller object on the same path as the full binary"), placed by the
    // release pipeline in <data dir>/update-deltas/ (S406-DELTA).
    for (final (hash, path) in deltaObjectsHeld(manifest, AppPaths.dataDir)) {
      carrier.objectHoldFile(hexToBytes(hash), path);
      _log.info('[update] carrier: delta ${hash.substring(0, 16)} is held for '
          'others');
    }
  }

  /// A collection for [target] is outdated — a newer manifest has moved
  /// the target. Asked after every wait in [_startInNetworkUpdate].
  bool _updateSuperseded(UpdateTarget target) {
    if (identical(_updateTargetField[this], target)) return false;
    _log.info('startInNetworkUpdate: run for $target superseded '
        '(target now ${_updateTargetField[this]}) — ended');
    return true;
  }

  static bool _sameHash(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Sets the target of [manifest] (P1, §26.6.1 "The node switches to the
  /// newest target at once; pieces that do not serve it are discarded"):
  /// a former target with another object ends its fetch, its stored
  /// version is deleted, and the carrier expects the new object — which
  /// deletes every other partial state. The same object again changes
  /// nothing. `null`: the manifest names no object for this platform.
  UpdateTarget? _updateTargetSet(UpdateManifest manifest) {
    final platform = Platform.operatingSystem;
    final fresh = updateTargetFor(manifest, currentAppVersion, platform);
    if (fresh == null) return null;
    final old = _updateTargetField[this];
    if (old != null && old.sameAs(fresh)) return old;
    _updateTargetField[this] = fresh;
    final carrier = _updateCarrierField[this];
    if (old != null && !_sameHash(old.object, fresh.object)) {
      updateTrace('discard',
          seq: old.seq,
          version: old.version,
          object: old.object,
          platform: platform,
          reason: 'target moved to seq ${fresh.seq} '
              '${updateObjectShort(fresh.object)} (Z1) — its fetch ends');
      carrier?.fetchAbort();
      if (old.version != currentAppVersion) { // V3-TOUCH-OK: the running version, not a peer's — its store holds the self-seeded binary
        unawaited(_binaryFragmentStore?.deleteVersion(platform, old.version));
      }
    }
    updateTrace('target',
        seq: fresh.seq,
        version: fresh.version,
        object: fresh.object,
        platform: platform,
        reason: '$fresh, before: ${old ?? 'none'}');
    if (!File(_binaryFragmentStore?.completePath(platform, fresh.version) ?? '')
        .existsSync()) {
      _updateExpect(fresh);
    }
    return fresh;
  }

  /// The carrier expects [t]'s object. Without a writable profile there is
  /// no partial state; the next moment tries again.
  void _updateExpect(UpdateTarget t) {
    try {
      _updateCarrierField[this]?.objectExpect(t.object, t.length);
    } on FileSystemException catch (e) {
      _log.warn('[update] partial state of $t not openable: $e');
    }
  }

  /// The offer knows the target but fetching is locked (data-saving mode,
  /// §24.4.2): the object is expected all the same, so cover fill is kept;
  /// a binary already stored is checked and offered — no packet (P3).
  void updateTargetExpect(UpdateManifest manifest) {
    final t = _updateTargetSet(manifest);
    if (t == null) return;
    final complete =
        _binaryFragmentStore?.completePath(t.platform, t.version) ?? '';
    if (File(complete).existsSync()) {
      unawaited(_storedCheck(manifest, t, complete).catchError((Object e) {
        _log.warn('[update] check of the stored $t failed: $e');
      }));
    }
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

  // The V4.1 cover fill (`UpdateCoverFill`, fountain blocks in dummy cover
  // slots: `reportUpdateObjectsTo`, `nextCoverFillBlock`,
  // `takeCoverFillBlock`, `_adoptCoverFillBinary`) fell with S399 P2. Its
  // blocks were handed out and taken only by `attachV41`, which has no
  // caller in 4.2. Update pieces ride the cover stream through
  // `mycelium/lib/update_cover_route.dart` (§5.5, §26.6.1); a node holds
  // the complete objects for others through [_ownObjectsHold].

  /// The platforms of in-network distribution.
  ///
  /// macOS and iOS are missing on purpose: §26.6.1 explicitly exempts them
  /// ("macOS and iOS are exempt from in-network distribution (DMG via
  /// GitHub Release, TestFlight); `shouldUseInNetworkUpdate()` returns
  /// `false` there").
  static const List<String> kInNetworkPlatforms = <String>[
    'android',
    'linux',
    'windows',
  ];


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
        updateTrace('manifest-decision', reason: 'no candidate');
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
        if (best == null || bestJson == null) {
          updateTrace('manifest-decision',
              reason: '${candidates.length} candidate(s), none validly signed');
          return;
        }

        _log.info('[update] Poll: best manifest v${best.version} '
            '(from ${candidates.length} fragments)');

        final prev = _latestManifest;
        if (prev != null && !checker.isNewer(best.version, prev.version)) {
          if (checker.isNewer(prev.version, best.version)) {
            updateTrace('manifest-decision',
                seq: best.minMonotoneSeq,
                version: best.version,
                object: best.binaryHashes?[Platform.operatingSystem],
                platform: Platform.operatingSystem,
                reason: 'OLDER than known v${prev.version} — ignored');
            _log.debug('[update] Poll manifest v${best.version} older than cached v${prev.version}');
            // `_pushManifestToPeers(...)` stood here — the correction to the
            // peers that offered an older manifest (gap G-18).
            return;
          }
          final bestSeq = best.minMonotoneSeq ?? 0;
          final prevSeq = prev.minMonotoneSeq ?? 0;
          if (bestSeq <= prevSeq) {
            updateTrace('manifest-decision',
                seq: bestSeq,
                version: best.version,
                object: best.binaryHashes?[Platform.operatingSystem],
                platform: Platform.operatingSystem,
                reason: 'SAME as known (seq $prevSeq) — nothing reported');
            _log.debug('[update] No update available '
                '(manifest: v${best.version} seq=$bestSeq, '
                'cached: v${prev.version} seq=$prevSeq)');
            return;
          }
          _log.info('[update] Poll: same version v${best.version} '
              'but higher seq ($bestSeq > $prevSeq) — accepting');
        }

        updateTrace('manifest-decision',
            seq: best.minMonotoneSeq,
            version: best.version,
            object: best.binaryHashes?[Platform.operatingSystem],
            platform: Platform.operatingSystem,
            reason: prev == null
                ? 'first known manifest'
                : checker.isNewer(best.version, prev.version)
                    ? 'NEWER version than known v${prev.version}'
                    : 'same version, HIGHER seq than known '
                        '${prev.minMonotoneSeq ?? 0}');
        _latestManifest = best;
        // S387: the carrier puts the newest manifest back into the compartment.
        final carrier = _updateCarrierField[this];
        if (carrier != null) {
          carrier.manifestKnown(Uint8List.fromList(utf8.encode(bestJson)));
          _ownObjectsHold(carrier);
        }
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
            updateTrace('manifest-decision',
                seq: best.minMonotoneSeq,
                version: best.version,
                platform: Platform.operatingSystem,
                reason: 'no binary for this platform — not reported');
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

            updateTrace('manifest-decision',
                seq: best.minMonotoneSeq,
                version: best.version,
                object: best.binaryHashes?[Platform.operatingSystem],
                platform: Platform.operatingSystem,
                reason: 'update available (current v$currentAppVersion), '
                    'in-network ${inNetworkAvailable ? 'yes' : 'NO'} — '
                    'reported to the offer');
            onUpdateAvailable?.call(best, inNetworkAvailable);
          }
        } else {
          updateTrace('manifest-decision',
              seq: best.minMonotoneSeq,
              version: best.version,
              platform: Platform.operatingSystem,
              reason: 'not newer than the running v$currentAppVersion');
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


  /// Collects, checks and stores the update for [manifest] (v4_2 §26.6.1
  /// steps 4-5).
  ///
  /// **Without user action** (owner decision 14.09.2026): the caller is
  /// `UpdateOffer.onManifest` in the daemon or in `CleonaAppState`. NOTHING
  /// is installed here: the run ends in `BinaryUpdateState.ready`, and only
  /// the click on "Installieren" (`UpdateOffer.consent`) installs.
  Future<void> startInNetworkUpdate(UpdateManifest manifest) async {
    try {
      await _startInNetworkUpdate(manifest);
    } finally {
      updateTrace('collect-end',
          seq: manifest.minMonotoneSeq,
          version: manifest.version,
          object: manifest.binaryHashes?[Platform.operatingSystem],
          platform: Platform.operatingSystem,
          reason: 'state ${_binaryUpdateManager?.state.name ?? 'no manager'}'
              '${_binaryUpdateManager?.errorMessage == null ? '' : ', last error: ${_binaryUpdateManager!.errorMessage}'}');
    }
  }

  /// ONE source: the target's object from the fetch path of the delivery
  /// layer, into its partial state on disk (S406-UPDPKG). Then the check,
  /// then `complete.bin`, then `ready`.
  ///
  /// ── WHAT FELL HERE (P4, owner decision E-2 A, 07.10.2026) ──────────
  ///
  /// Behind the fetch path stood two more source classes: the Nostr
  /// rendezvous and the entry cascade, each fetching the full binary or
  /// Reed-Solomon parts over HTTP and assembling them. §26.6.4: "This design
  /// uses no external rendezvous channel such as Nostr here"; §26.6.7 gives
  /// updates stages 5 and 6 (bulk cache, delta) and HTTP to first
  /// installation (stage 3); §26.6.8 "HTTP path for first installation and
  /// foreign-platform fetch". The source asked by version, not by object:
  /// on 07.10.2026 20:39 it assembled parts of the new APK to the size of
  /// the old one (S406-UPD2 finding B-5). The seeding of Reed-Solomon parts
  /// after a check fell with it — it held the whole binary in memory; the
  /// running binary is seeded from its file at the next start
  /// (`_selfSeedCurrentBinary`).
  ///
  /// When the fetch path does not deliver, the partial state stays and the
  /// next moment of §26.5.4 resumes it (`UpdateOffer.againTry`) — never a
  /// timer.
  Future<void> _startInNetworkUpdate(UpdateManifest manifest) async {
    // S287: the UI may hold a stale cached manifest while the poll has
    // already promoted _latestManifest to a newer version.
    final latest = _latestManifest;
    if (latest != null) {
      final checker = UpdateChecker(log: _log);
      if (checker.isNewer(latest.version, manifest.version)) {
        updateTrace('collect-start',
            seq: latest.minMonotoneSeq,
            version: latest.version,
            reason: 'stale manifest v${manifest.version} from the caller '
                'replaced by the known one');
        manifest = latest;
      }
    }

    final platform = Platform.operatingSystem;
    final store = _binaryFragmentStore;
    final updater = _binaryUpdateManager;
    if (store == null || updater == null) {
      updateTrace('collect-start',
          seq: manifest.minMonotoneSeq,
          version: manifest.version,
          platform: platform,
          reason: 'NOT started — binary-update subsystem not initialized');
      _log.warn('startInNetworkUpdate: binary-update subsystem not initialized');
      return;
    }
    final target = _updateTargetSet(manifest);
    final complete = store.completePath(platform, manifest.version);
    final carrier = _updateCarrierField[this];
    updateTrace('collect-start',
        seq: manifest.minMonotoneSeq,
        version: manifest.version,
        object: target?.object,
        platform: platform,
        reason: '${target ?? 'NO object for this platform'}, carrier '
            '${carrier == null ? 'NONE' : 'set'}, complete.bin '
            '${File(complete).existsSync() ? 'present' : 'absent'}');
    if (target == null) {
      onUpdateStateChanged?.call(BinaryUpdateState.idle, 0.0);
      return;
    }
    onUpdateStateChanged?.call(BinaryUpdateState.checking, 0.0);
    if (File(complete).existsSync()) {
      await _storedCheck(manifest, target, complete);
      if (_updateSuperseded(target) || File(complete).existsSync()) return;
    }
    if (carrier == null) {
      _log.warn('startInNetworkUpdate: no update carrier — nothing to fetch from');
      onUpdateStateChanged?.call(BinaryUpdateState.idle, 0.0);
      return;
    }
    onUpdateStateChanged?.call(BinaryUpdateState.downloading, 0.0);
    String? path;
    try {
      path = await carrier.objectFetch(
          contentHash: target.object, length: target.length);
    } catch (e) {
      _log.warn('startInNetworkUpdate: fetch path failed: $e');
    }
    if (_updateSuperseded(target)) return;
    if (path == null) {
      _log.info('startInNetworkUpdate: the fetch path did not deliver '
          '$target — the partial state stays for the next moment');
      onUpdateStateChanged?.call(BinaryUpdateState.idle, 0.0);
      return;
    }
    if (await _objectComplete(manifest, target, path)) {
      // The delta did not become the binary — the full binary is the target
      // now (§26.6.2 "fallback to the full binary"); this run fetches it.
      await _startInNetworkUpdate(manifest);
    }
  }

  /// A `complete.bin` already stored for [target] (a restart before the
  /// click, or a former object under the same version): checked again —
  /// passes → `ready`; fails → deleted, and the object is expected afresh.
  Future<void> _storedCheck(
      UpdateManifest manifest, UpdateTarget target, String complete) async {
    final updater = _binaryUpdateManager;
    final signature = _binarySignatureOf(manifest, target.platform);
    final hash = manifest.binaryHashes?[target.platform];
    if (updater == null || signature == null || hash == null) return;
    final ok = await updater.verifyFile(complete,
        platform: target.platform,
        version: target.version,
        expectedHash: hash,
        maintainerSignature: signature);
    if (_updateSuperseded(target)) return;
    if (ok) {
      _updateReady(target);
      return;
    }
    updateTrace('discard',
        seq: target.seq,
        version: target.version,
        object: target.object,
        platform: target.platform,
        reason: 'stored complete.bin failed its check — deleted, fetched anew');
    await _binaryFragmentStore?.deleteVersion(target.platform, target.version);
    _updateExpect(target);
  }

  /// The object of [target] is complete at [objectPath] (fetch path or
  /// cover fill): made into the binary (`updateBinaryFromObject`), checked
  /// (SHA-256 + maintainer signature) BEFORE it becomes `complete.bin` —
  /// `complete.bin` has readers that do not wait for `ready` (the HTTP
  /// delivery server). A failed check deletes the whole state; the next
  /// moment fetches anew (§26.6.1 self-healing).
  ///
  /// A delta (S406-DELTA, §26.6.2) that does not become a binary passing
  /// that check is marked failed ([updateDeltaFailed]) and the full binary
  /// becomes the target at once. Returns `true` then: the fetch path fetches
  /// it in the same run; after cover fill the next moment does.
  Future<bool> _objectComplete(
      UpdateManifest manifest, UpdateTarget target, String objectPath) async {
    final updater = _binaryUpdateManager;
    final store = _binaryFragmentStore;
    final carrier = _updateCarrierField[this];
    final signature = _binarySignatureOf(manifest, target.platform);
    final hash = manifest.binaryHashes?[target.platform];
    if (updater == null || store == null || signature == null || hash == null) {
      _log.warn('startInNetworkUpdate: $target has no binary hash/signature '
          'for ${target.platform} — cannot verify');
      onUpdateStateChanged?.call(BinaryUpdateState.idle, 0.0);
      return false;
    }
    final binary = await updateBinaryFromObject(target, objectPath,
        basePath: target.kind == UpdateObjectKind.delta
            ? await deltaBasePath(
                platform: target.platform,
                apkPath: CleonaService.apkPathResolver)
            : null);
    if (target.kind == UpdateObjectKind.delta) {
      updateTrace('fetch-check',
          seq: target.seq,
          version: target.version,
          object: target.object,
          platform: target.platform,
          reason: 'delta v${target.fromVersion} -> v${target.version}: '
              '${binary == null ? 'bspatch did NOT build the binary (installed file missing or not the delta\'s base)' : 'bspatch built the binary — its check follows'}');
    }
    final ok = binary != null &&
        await updater.verifyFile(binary,
            platform: target.platform,
            version: target.version,
            expectedHash: hash,
            maintainerSignature: signature);
    if (_updateSuperseded(target)) return false;
    if (!ok) {
      _log.error('startInNetworkUpdate: verification FAILED for $target — '
          'the whole state is deleted, the next moment fetches anew');
      updateTrace('discard',
          seq: target.seq,
          version: target.version,
          object: target.object,
          platform: target.platform,
          reason: 'verification failed — the whole state is deleted');
      if (binary != null && binary != objectPath) _deleteQuietly(binary);
      carrier?.objectDiscard(target.object);
      await store.deleteVersion(target.platform, target.version);
      if (target.kind == UpdateObjectKind.delta) {
        // §26.6.2 "fallback to the full binary": this delta is not chosen
        // again, and the full binary becomes the target now.
        updateDeltaFailed(target);
        final full = _updateTargetSet(manifest);
        updateTrace('discard',
            seq: target.seq,
            version: target.version,
            object: target.object,
            platform: target.platform,
            reason: 'delta v${target.fromVersion} not usable — the target is '
                'now ${full ?? 'none'} (fallback to the full binary)');
        return full != null && full.kind == UpdateObjectKind.full;
      }
      return false;
    }
    final complete = store.completePath(target.platform, target.version);
    try {
      File(complete).parent.createSync(recursive: true);
      File(binary).renameSync(complete);
    } on FileSystemException {
      // Another file system: copy, then remove the source.
      File(binary).copySync(complete);
      _deleteQuietly(binary);
    }
    carrier?.objectTaken(target.object);
    _updateReady(target);
    return false;
  }

  /// Checked and stored: `ready`, and an always-on node holds it for others.
  void _updateReady(UpdateTarget target) {
    _binaryUpdateManager?.markReady();
    binaryHasContentToShare = true;
    _log.info('startInNetworkUpdate: $target verified and ready');
    final carrier = _updateCarrierField[this];
    if (carrier != null) _ownObjectsHold(carrier);
  }

  static Uint8List? _binarySignatureOf(UpdateManifest m, String platform) {
    final b64 = m.binarySignatures?[platform];
    if (b64 == null) return null;
    try {
      return base64Decode(b64);
    } on FormatException {
      return null;
    }
  }

  static void _deleteQuietly(String path) {
    try {
      File(path).deleteSync();
    } on FileSystemException {
      // already gone
    }
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
    // ONE read of the local compartment at the moment "start" (S406-UPD,
    // finding U-2). The five-minute retry ("F3: one retry for mobile") and
    // the six-hour `Timer.periodic` stood here — remnants of the V3 DHT
    // poll. Since the cut they read only the local store, which nothing
    // fills between two starts, and logged "Poll returned 0 manifest
    // fragments" every six hours to the second. §26.5.4: "Never on a
    // timer"; D-9: nothing periodic in idle. The manifest arrives through
    // the update carrier at the moments of §26.5.4 (`updateManifestAsk`).
    Timer(const Duration(seconds: 30), _checkForUpdates);
  }
}
