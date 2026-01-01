import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/crypto/file_sha256.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/util/hex.dart' show bytesToHex, hexToBytes;
import 'package:cleona/core/platform/app_paths.dart';
import 'package:cleona/core/storage/atomic_replace.dart';
import 'package:cleona/core/storage/device_state_legacy.dart';
import 'package:cleona/core/storage/device_store.dart';
import 'package:cleona/core/update/update_binary_store.dart';
import 'package:cleona/core/update/install_source.dart';
import 'package:cleona/core/update/update_manifest.dart';
import 'package:mycelium/update_trace.dart';

/// §26.6.1 — the state machine of an in-network update: checks a verified
/// [UpdateManifest] against the per-platform binary marker, verifies the
/// collected binary, and hands a ready-to-install path back to the caller.
/// No network transport of its own: the object is collected by the update
/// carrier of the delivery layer (`cleona_service_update.dart`).
enum BinaryUpdateState {
  idle,
  checking,
  downloading,
  assembling,
  verifying,
  ready,
  failed,
}

/// What [BinaryUpdateManager.startAfterUpdate] found at a process start.
enum UpdateStart {
  /// No desktop update is pending.
  none,

  /// The first start of a freshly applied version.
  first,

  /// The previous start of that version neither reached 30 s nor shut down
  /// in order — it crashed (§26.5).
  crashed,
}

class BinaryUpdateManager {
  final UpdateBinaryStore _store;
  final UpdateChecker _checker;
  final CLogger _log;

  BinaryUpdateState _state = BinaryUpdateState.idle;
  String? _targetVersion;
  String? _targetPlatform;
  double _progress = 0.0;
  String? _errorMessage;
  bool _cancelled = false;
  String? _windowsUpdateBatPath;

  int _highestSeenMonotoneSeq = 0;

  /// Where the downgrade bound lives (§26.5): the device database
  /// (`DeviceStore.keyUpdateMonotoneSeq`, §4.5.3). `null` (no master seed
  /// yet, or a probe) — then the bound lives in memory for this run only.
  final DeviceStore? Function()? _deviceStore;

  void Function(BinaryUpdateState state, double progress)? onStateChanged;
  void Function(String version, String binaryPath)? onUpdateReady;

  BinaryUpdateManager({
    required this._store,
    required this._checker,
    String? profileDir,
    this._deviceStore,
  })  : _log = CLogger.get('bin-update', profileDir: profileDir) {
    _highestSeenMonotoneSeq = _loadMonotoneSeq();
  }

  /// The downgrade bound as it stands — for probes and the network
  /// statistics.
  int get highestSeenMonotoneSeq => _highestSeenMonotoneSeq;

  BinaryUpdateState get state => _state;
  double get progress => _progress;
  String? get errorMessage => _errorMessage;
  String? get targetVersion => _targetVersion;
  String? get windowsUpdateBatPath => _windowsUpdateBatPath;

  /// Check for an available in-network update from a verified manifest.
  /// Returns true if [manifest] describes a newer version reachable via
  /// the in-network binary distribution path for [platform].
  Future<bool> checkForUpdate(
    UpdateManifest manifest,
    String currentVersion,
    String platform,
  ) async {
    // ── ONE CHECK, NO STATE (S387) ────────────────────────────
    //
    // Here ran `_setState(checking)` and afterwards `_setState(idle)`. Since
    // the banner only appears on `ready` (owner decision
    // 14.09.2026), that was an error with consequences: every FURTHER identity
    // of a daemon checks the same manifest, its `idle` went via IPC to
    // the same GUI and deleted the banner of the service that had finished
    // collecting. This method only decides "is there a target";
    // the state is set by whoever collects.
    //
    // And a NEWER manifest during a run is no "already
    // in transit": it is checked like any other and becomes the new
    // target (Z1, §26.6.1). The service ends the superseded collection
    // (`_updateTargetSet`, S406-UPDPKG).
    final runs = _state == BinaryUpdateState.downloading ||
        _state == BinaryUpdateState.assembling ||
        _state == BinaryUpdateState.verifying ||
        _state == BinaryUpdateState.ready;
    if (runs && manifest.version == _targetVersion) {
      return _checker.isNewer(manifest.version, currentVersion);
    }
    try {
      if (!shouldUseInNetworkUpdate()) {
        // Name the ACTUAL reason. This used to say "(Play Store install)"
        // unconditionally — but InstallSourceDetector fails safe *towards*
        // playStore (install_source.dart: "Detection failures fail safe towards
        // InstallSource.playStore, i.e. towards disabling self-update"), so a
        // detection failure produced a log line asserting a Play Store install
        // that never happened. Field case S297/F9: a sideloaded build on
        // Samsung never offered an update across 3.1.157/.158/.159, and this
        // line would have sent the reader looking in the wrong place.
        // WARN, not INFO: this silently disables the entire update path.
        final why = (Platform.isIOS || Platform.isMacOS)
            ? 'platform uses the store update path'
            : 'install source = ${InstallSourceDetector.cached?.name ?? "not yet detected"} '
                '(note: detection failures report playStore by design)';
        _log.warn('In-network updates disabled — $why');
        return false;
      }

      if (_checker.isDowngradeAttempt(manifest, _highestSeenMonotoneSeq)) {
        _log.warn('Rejecting manifest: monotoneSeq=${manifest.minMonotoneSeq} '
            '<= highestSeen=$_highestSeenMonotoneSeq');
        return false;
      }

      // Presence marker, not a lookup key — the value is
      // deliberately not read (reasoning at `UpdateManifest.binaryTag`).
      final tag = manifest.binaryTag?[platform];
      final hash = manifest.binaryHashes?[platform];
      if (tag == null && hash == null) {
        // INFO, not DEBUG: a manifest that carries no artefact for this
        // platform is an anomaly on the publishing side, not a routine
        // outcome — unlike the "not newer" case below, which is the normal
        // steady state and stays at DEBUG so the 6h check does not spam.
        _log.info('In-network update unavailable: manifest v${manifest.version} '
            'has neither binaryTag nor binaryHash for platform=$platform');
        return false;
      }

      if (!_checker.isNewer(manifest.version, currentVersion)) {
        _log.debug('Manifest v${manifest.version} not newer than $currentVersion');
        return false;
      }

      if (manifest.minMonotoneSeq != null &&
          manifest.minMonotoneSeq! > _highestSeenMonotoneSeq) {
        _highestSeenMonotoneSeq = manifest.minMonotoneSeq!;
        _saveMonotoneSeq();
      }

      _targetVersion = manifest.version;
      _targetPlatform = platform;
      _log.info('In-network update available: v${manifest.version} for $platform');
      return true;
    } catch (e) {
      // No `_fail`: a `failed` from here would go as a state to the GUI
      // (see header of the method), although nothing was collected.
      _errorMessage = 'checkForUpdate failed: $e';
      _log.error(_errorMessage!);
      return false;
    }
  }

  // ── NO DOWNLOAD, NO ASSEMBLY HERE (S406-UPDPKG, P4) ───────────────
  //
  // `startDownload` (HTTP: full binary or Reed-Solomon parts from the
  // Nostr rendezvous and the entry cascade) and `assemble` (Reed-Solomon
  // decode into `complete.bin`) stood here. An update arrives only through
  // the fetch path of the delivery layer and cover fill (v4_2 §26.6.1,
  // §26.6.7 stages 5/6); §26.6.4 "This design uses no external rendezvous
  // channel such as Nostr here", and §26.6.8 gives HTTP to "first
  // installation and foreign-platform fetch" only. That source asked by
  // version, not by object, and on 07.10.2026 20:39 assembled a binary that
  // was neither the old nor the new one (S406-UPD2 finding B-5; owner
  // decision E-2 A, 07.10.2026). The HTTP server and the browser assembler
  // stay for first installation and the foreign platform (§26.6.5).

  /// Checks the binary at [path] for [version] on [platform]: SHA-256
  /// (streamed — the file is never held in memory, S406-UPD2 finding B-8)
  /// against [expectedHash] (hex), and the maintainer's Ed25519 signature
  /// over that hash. `true` leaves the state at `verifying`: the caller
  /// stores the file and then calls [markReady]; `false` sets `failed`.
  Future<bool> verifyFile(
    String path, {
    required String platform,
    required String version,
    required String expectedHash,
    required Uint8List maintainerSignature,
  }) async {
    _targetPlatform = platform;
    _targetVersion = version;
    _cancelled = false;
    _setState(BinaryUpdateState.verifying, 0.0);
    try {
      final size = await File(path).length();
      final hash = await sha256OfFile(path);
      final hashHex = bytesToHex(hash);
      final hashOk = hashHex.toLowerCase() == expectedHash.toLowerCase();
      final key = hexToBytes(UpdateChecker.maintainerPublicKeyHex);
      final signed =
          hashOk && SodiumFFI().verifyEd25519(hash, maintainerSignature, key);
      updateTrace('verify',
          version: version,
          object: expectedHash,
          platform: platform,
          reason: '$size B, SHA-256 expected '
              '${updateObjectShort(expectedHash)} got '
              '${updateObjectShort(hashHex)} '
              '${hashOk ? 'MATCHES' : 'DOES NOT MATCH'}, signature '
              '${!hashOk ? 'not checked' : signed ? 'valid' : 'NOT valid'}');
      if (!hashOk) {
        _fail('Hash mismatch: expected=$expectedHash got=$hashHex');
        return false;
      }
      if (!signed) {
        _fail('Signature verification failed');
        return false;
      }
      return true;
    } catch (e) {
      _fail('verify failed: $e');
      return false;
    }
  }

  /// The checked binary lies in the store: `ready` — the banner may show
  /// (v4_2 §26.6.1 step 5).
  void markReady() {
    _setState(BinaryUpdateState.ready, 1.0);
    final target = _targetVersion;
    if (target != null && !Platform.isAndroid) {
      getVerifiedBinaryPath(_targetPlatform ?? '', target).then((path) {
        if (path != null) onUpdateReady?.call(target, path);
      });
    }
  }

  /// Path to the verified binary once assembled, for installation.
  Future<String?> getVerifiedBinaryPath(String platform, String version) async {
    final srcFile = File(_store.completePath(platform, version));
    if (!srcFile.existsSync()) return null;

    final dir = Directory('$_updateDir/verified');
    final ext = platform == 'android' ? 'apk' : 'bin';
    final destPath = '${dir.path}/cleona-$platform-$version.$ext';
    final destFile = File(destPath);

    if (destFile.existsSync()) {
      final expectedHash = await _store.getBinaryHash(platform, version);
      final destHash = bytesToHex(SodiumFFI().sha256(destFile.readAsBytesSync()));
      if (expectedHash != null && expectedHash.isNotEmpty) {
        if (destHash.toLowerCase() == expectedHash.toLowerCase()) {
          return destPath;
        }
        _log.warn('Cached binary hash mismatch: expected=$expectedHash '
            'got=$destHash — re-copying');
      } else {
        final srcHash = bytesToHex(SodiumFFI().sha256(srcFile.readAsBytesSync()));
        if (destHash.toLowerCase() == srcHash.toLowerCase()) {
          return destPath;
        }
        _log.warn('Cached binary hash differs from source — re-copying');
      }
      destFile.deleteSync();
    }

    try {
      if (!dir.existsSync()) dir.createSync(recursive: true);
      if (destFile.existsSync()) destFile.deleteSync();
      await srcFile.copy(destPath);
      return destPath;
    } catch (e) {
      _log.warn('getVerifiedBinaryPath failed: $e');
      return null;
    }
  }

  String get _updateDir => '${AppPaths.dataDir}/update';

  /// Whether to use in-network updates or redirect to Play Store.
  bool shouldUseInNetworkUpdate() {
    if (Platform.isIOS || Platform.isMacOS) return false;
    final source = InstallSourceDetector.cached;
    if (source == InstallSource.playStore) return false;
    return true;
  }

  /// Run housekeeping on the fragment store (called periodically by owner).
  ///
  /// Passes this manager's own [_targetPlatform]/[_targetVersion] through to
  /// [UpdateBinaryStore.enforceBudget] as the protected install target —
  /// this manager is the only object that knows which (platform, version) is
  /// currently being downloaded/assembled/verified for local installation
  /// (`main.dart:applyUpdate()` reads `_targetVersion` for exactly that
  /// decision on Android and desktop alike), so the exemption is set here,
  /// not guessed at inside the store.
  ///
  /// [manifestVersion]: the version of the newest manifest the node knows —
  /// everything older is superseded (§26.6.1); without one, the running
  /// [currentVersion] is the measure (S407-BOOTSTRAPSPEICHER).
  ///
  /// [manifestHashes]: the per-platform SHA-256 of that manifest; against
  /// it the complete objects of [manifestVersion] are checked before the
  /// fragment files an earlier version left next to them are removed
  /// ([UpdateBinaryStore.dropFragmentFiles], S407-UPDATEFRAGMENTE).
  ///
  /// [hold]: objects that are never evicted beside the install target —
  /// what a desktop holds for others (`heldForOthers`).
  ///
  /// [phonePlatform]: set on a phone (its own platform). A phone holds no
  /// object (§26.6.1 step 3); the copy of its running binary an earlier
  /// version stored at start goes at once, whatever the budget — it hands
  /// its binary out from the installed file (`installed_binary.dart`,
  /// S407-UPDATEFRAGMENTE W9). The install target is never touched.
  Future<void> gc(String currentVersion, int budgetBytes,
      {String? manifestVersion,
      Map<String, String>? manifestHashes,
      bool Function(String platform, String version)? hold,
      String? phonePlatform}) async {
    try {
      if (phonePlatform != null &&
          !(phonePlatform == _targetPlatform &&
              currentVersion == _targetVersion) &&
          await _store.hasComplete(phonePlatform, currentVersion)) {
        await _store.deleteVersion(phonePlatform, currentVersion);
        _log.info('gc: phone — copy of the running $phonePlatform/'
            '$currentVersion released (a phone holds none, §26.6.1)');
      }
      await _store.garbageCollect(manifestVersion ?? currentVersion,
          keep: (platform, version) =>
              platform == _targetPlatform && version == _targetVersion);
      await _store.dropFragmentFiles(
          expectedHash: (platform, version) =>
              version == manifestVersion ? (manifestHashes?[platform]) : null);
      await _store.enforceBudget(budgetBytes,
          protectPlatform: _targetPlatform,
          protectVersion: _targetVersion,
          protect: hold);
    } catch (e) {
      _log.warn('gc failed: $e');
    }
  }

  void cancel() {
    _cancelled = true;
    _setState(BinaryUpdateState.idle, 0.0);
  }

  void dispose() {
    _cancelled = true;
    onStateChanged = null;
    onUpdateReady = null;
  }

  void _setState(BinaryUpdateState state, double progress) {
    if (_cancelled && state != BinaryUpdateState.idle) return;
    _state = state;
    _progress = progress;
    try {
      onStateChanged?.call(state, progress);
    } catch (_) {}
  }

  void _fail(String message) {
    _errorMessage = message;
    _log.error(message);
    _setState(BinaryUpdateState.failed, _progress);
  }

  // ---------------------------------------------------------------------------
  // Desktop binary apply + rollback
  // ---------------------------------------------------------------------------

  /// Desktop (Linux/Windows/macOS): back up the current binary and replace it
  /// with the verified update. Writes an `update-pending.json` marker so that
  /// the next startup can detect a fresh update and run [markUpdateHealthy]
  /// after a grace period, or [rollback] if the app crashes immediately.
  /// Root of the bundle that [applyDesktopUpdate] and [rollback]
  /// replace — derived from the passed program path.
  ///
  /// CRITICAL SINCE S367, and the reason is a data loss that was almost
  /// built in: both procedures below mirror a whole
  /// bundle with `rsync --delete` or `robocopy` into this directory.
  /// Until here `File(currentBinaryPath).parent.path` stood there. The
  /// daemon lies in `<bundleDir>/bin/` since S367 — with the old
  /// calculation the entire bundle would have been mirrored into `bin/`
  /// and `--delete` would have removed the rest of the installation. Computed via
  /// [AppPaths.bundleDirOf] it hits the same, right root for GUI (root) and
  /// daemon (`bin/`).
  static String _bundleRootOf(String currentBinaryPath) =>
      AppPaths.bundleDirOf(currentBinaryPath);

  /// rsync arguments that make the bundle [to] an exact copy of [from] —
  /// for applying an update, for restoring after a failed apply, and for
  /// the rollback (Linux).
  ///
  /// `--checksum`, because rsync's quick check compares only size and
  /// modification time: a file of the new version with the same size and
  /// time as the old one would be skipped, and the bundle would mix both
  /// versions (S407, seen in smoke_update_crash_rollback). Costs one read
  /// of both bundles per update — once per release.
  static List<String> mirrorArgs(String from, String to) =>
      ['-a', '--delete', '--checksum', '$from/', '$to/'];

  Future<bool> applyDesktopUpdate(String currentBinaryPath) async {
    final verifiedPath = _verifiedBinaryPathSync();
    if (verifiedPath == null) {
      _fail('applyDesktopUpdate: no verified binary available');
      return false;
    }
    try {
      final currentFile = File(currentBinaryPath);
      final bakPath = '$currentBinaryPath.bak';
      // The whole-bundle backup of the archive paths below — what a
      // rollback restores and what markUpdateHealthy deletes (S392-11).
      String? bundleBackup;
      final bakFile = File(bakPath);
      if (bakFile.existsSync()) {
        try { bakFile.deleteSync(); } catch (_) {}
      }

      final raf = File(verifiedPath).openSync();
      final header = raf.readSync(4);
      raf.closeSync();
      final isZip = header.length >= 4 &&
          header[0] == 0x50 && header[1] == 0x4B &&
          header[2] == 0x03 && header[3] == 0x04;
      final isGzip = header.length >= 2 &&
          header[0] == 0x1F && header[1] == 0x8B;

      if (isZip && Platform.isWindows) {
        // Windows: can't overwrite running .exe files. Write a .bat script
        // that waits for daemon+GUI to exit, then extracts the ZIP, then
        // restarts the daemon. The caller spawns this script and exits.
        final appDir =
            _bundleRootOf(currentBinaryPath).replaceAll('/', '\\');
        final bakDir = '$appDir.update-bak'.replaceAll('/', '\\');
        bundleBackup = bakDir;
        final zipSrc = verifiedPath.replaceAll('/', '\\');
        final tmpZip = '$zipSrc.zip';
        final zipDest = File('$verifiedPath.zip');
        if (zipDest.existsSync()) zipDest.deleteSync();
        File(verifiedPath).copySync(zipDest.path);

        final batPath = '$_updateDir/update-apply.bat'.replaceAll('/', '\\');
        final home = Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Cleona';
        File(batPath).writeAsStringSync(windowsApplyScript(
          appDir: appDir,
          bakDir: bakDir,
          zipPath: tmpZip,
          markerPath: '$_updateDir/update-pending.json',
          pidFile: '$home\\.cleona\\cleona.pid',
          logPath: '$_updateDir/update-apply.log',
        ));
        _windowsUpdateBatPath = batPath;
        _log.info('Wrote update-apply.bat: $batPath');
      } else if (isGzip && Platform.isLinux) {
        // Linux tar.gz: full bundle replacement (daemon + GUI + libs + data).
        final appDir = _bundleRootOf(currentBinaryPath);
        final bakDir = '$appDir.update-bak';
        bundleBackup = bakDir;

        try { Directory(bakDir).deleteSync(recursive: true); } catch (_) {}

        final cpBak = await Process.run('cp', ['-a', appDir, bakDir]);
        if (cpBak.exitCode != 0) {
          _fail('Directory backup failed: ${cpBak.stderr}');
          return false;
        }
        _log.info('Backed up app directory to $bakDir');

        final tmpDir = Directory('$_updateDir/extract-tmp');
        if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
        tmpDir.createSync(recursive: true);
        try {
          final tarResult = await Process.run(
            'tar', ['-xzf', verifiedPath, '-C', tmpDir.path],
          );
          if (tarResult.exitCode != 0) {
            _fail('tar extraction failed (exit ${tarResult.exitCode}): ${tarResult.stderr}');
            tmpDir.deleteSync(recursive: true);
            return false;
          }

          // tar.gz may have a top-level directory (e.g. "cleona-chat/")
          final topEntries = tmpDir.listSync();
          final sourceDir = topEntries.length == 1 && topEntries.first is Directory
              ? (topEntries.first as Directory).path
              : tmpDir.path;

          // rsync extracted bundle into app directory
          final rsyncResult =
              await Process.run('rsync', mirrorArgs(sourceDir, appDir));
          if (rsyncResult.exitCode != 0) {
            await Process.run('rsync', mirrorArgs(bakDir, appDir));
            _log.info('Restored app directory from backup after rsync failure');
            try { Directory(bakDir).deleteSync(recursive: true); } catch (_) {}
            _fail('rsync to app dir failed: ${rsyncResult.stderr}');
            return false;
          }

          // Ensure binaries are executable.
          // `bin/cleona-daemon` is the canonical place of the daemon since S367;
          // the root entries stay for bundles in the
          // old layout. A `chmod` on a non-existent
          // file is no error, but skipped.
          for (final rel in ['bin/cleona-daemon', 'cleona-daemon', 'cleona']) {
            final bin = File('$appDir/$rel');
            if (bin.existsSync()) {
              Process.runSync('chmod', ['+x', bin.path]);
            }
          }
          _log.info('Extracted full Linux bundle to $appDir');
        } finally {
          if (tmpDir.existsSync()) {
            try { tmpDir.deleteSync(recursive: true); } catch (_) {}
          }
        }
      } else if (isGzip || isZip) {
        _fail('applyDesktopUpdate: archive format (${isGzip ? "gzip" : "zip"}) '
            'not supported on ${Platform.operatingSystem}');
        return false;
      } else {
        // Raw binary (direct ELF/Mach-O) — simple copy
        if (currentFile.existsSync()) {
          currentFile.renameSync(bakPath);
          _log.info('Backed up current binary to $bakPath');
        }
        File(verifiedPath).copySync(currentBinaryPath);
        if (!Platform.isWindows) {
          Process.runSync('chmod', ['+x', currentBinaryPath]);
        }
      }

      final marker = File('$_updateDir/update-pending.json');
      if (!marker.parent.existsSync()) marker.parent.createSync(recursive: true);
      _dropCleanExitNote(_updateDir);
      _writeMarkerFile(marker, {
        'version': _targetVersion,
        'appliedAt': DateTime.now().toIso8601String(),
        'previousBinary': bakPath,
        'bundleBackup': bundleBackup,
      });
      _log.info('Applied update v$_targetVersion — restart required');
      return true;
    } catch (e) {
      _fail('applyDesktopUpdate failed: $e');
      return false;
    }
  }

  String? _verifiedBinaryPathSync() {
    if (_targetPlatform == null || _targetVersion == null) return null;
    final path = '$_updateDir/verified/cleona-$_targetPlatform-$_targetVersion.bin';
    return File(path).existsSync() ? path : null;
  }

  /// Called ~30s after startup if the app is running stably. Removes the
  /// `update-pending.json` marker and deletes the backup — the `.bak` file
  /// of a raw binary and the whole-bundle backup of an archive update.
  ///
  /// Until S407 the bundle backup was looked for beside the binary's
  /// directory (`<bundle>/bin.update-bak`), while it lies beside the bundle
  /// (`<bundle>.update-bak`): every desktop update left a full copy of the
  /// old bundle behind (S392-11 (d)).
  ///
  /// Unconditional — used where one process is the whole app (in-process
  /// mode). On Linux and Windows the daemon and the window each report with
  /// [markDaemonHealthy] / [markGuiHealthy].
  static void markUpdateHealthy(String? profileDir) {
    _editMarker(profileDir, (data) {
      _finalize(data);
      return null;
    });
  }

  /// Deletes the backups a marker points to — the `.bak` file of a raw
  /// binary and the whole-bundle backup of an archive update.
  static void _finalize(Map<String, dynamic> data) {
    try {
      final bakPath = data['previousBinary'] as String?;
      final bundleBackup = bundleBackupOf(data);
      if (bakPath != null) {
        final bak = File(bakPath);
        if (bak.existsSync()) bak.deleteSync();
      }
      if (bundleBackup != null) {
        final bakDir = Directory(bundleBackup);
        if (bakDir.existsSync()) {
          try { bakDir.deleteSync(recursive: true); } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// Read-modify-write of the marker under an exclusive lock.
  ///
  /// Two processes write it — the daemon and the window (S407-RUECKNAHME
  /// R-2) — so every change runs under a lock on `update-pending.lock` beside
  /// it (`flock` on Linux, `LockFileEx` on Windows, both via
  /// [RandomAccessFile.lockSync]) and becomes visible with one rename
  /// ([atomicReplace]): a reader sees the old marker or the new one, never a
  /// torn one, and neither writer overwrites the other's field. [edit] gets
  /// the marker and returns it changed (written), `null` (deleted — the
  /// window's clean-exit note goes with it), or the same content unchanged
  /// (nothing written). Without a marker [edit] does not run.
  static void _editMarker(String? profileDir,
      Map<String, dynamic>? Function(Map<String, dynamic> data) edit) {
    final updateDir = '${profileDir ?? AppPaths.dataDir}/update';
    final markerFile = File('$updateDir/update-pending.json');
    if (!markerFile.existsSync()) return;
    RandomAccessFile? lock;
    try {
      lock = File('$updateDir/update-pending.lock').openSync(mode: FileMode.write);
      lock.lockSync(FileLock.blockingExclusive);
      if (!markerFile.existsSync()) return;
      final data =
          jsonDecode(markerFile.readAsStringSync()) as Map<String, dynamic>;
      final before = jsonEncode(data);
      final after = edit(data);
      if (after == null) {
        markerFile.deleteSync();
        _dropCleanExitNote(updateDir);
      } else if (jsonEncode(after) != before) {
        _writeMarkerFile(markerFile, after);
      }
    } catch (_) {
      // An unreadable marker is treated like none (as before S407).
    } finally {
      try { lock?.unlockSync(); } catch (_) {}
      try { lock?.closeSync(); } catch (_) {}
    }
  }

  static void _writeMarkerFile(File markerFile, Map<String, dynamic> data) {
    final tmp = File('${markerFile.path}.tmp');
    tmp.writeAsStringSync(jsonEncode(data), flush: true);
    atomicReplace(tmp, markerFile);
  }

  /// The daemon ran 30 s after an update (§26.5.4). The safety net ends —
  /// marker and backup go — when no window started (no window, autostart,
  /// a lab node) or the window is healthy too; otherwise the window ends it
  /// with [markGuiHealthy], or rolls back at its next start
  /// ([guiStartAfterUpdate]) — owner decision 19.10.2026 (R-2).
  static void markDaemonHealthy(String? profileDir) {
    _editMarker(profileDir, (data) {
      data['daemonHealthy'] = DateTime.now().toIso8601String();
      if (data['guiStartedAt'] == null || data['guiHealthy'] != null) {
        _finalize(data);
        return null;
      }
      return data;
    });
  }

  /// The window ran 30 s after an update. Ends the safety net when the daemon
  /// is healthy already; otherwise the daemon ends it at its 30 s.
  static void markGuiHealthy(String? profileDir) {
    _editMarker(profileDir, (data) {
      data['guiHealthy'] = DateTime.now().toIso8601String();
      if (data['daemonHealthy'] != null) {
        _finalize(data);
        return null;
      }
      return data;
    });
  }

  /// The window's start after an update (Linux, Windows): like
  /// [startAfterUpdate] for the daemon, with its own fields. A start that
  /// finds `guiStartedAt` without `guiHealthy` follows a window that neither
  /// ran 30 s nor ended in order ([markGuiStopped]): [UpdateStart.crashed].
  /// Only the window judges the window — the daemon cannot tell a dead window
  /// from one that is still in its first 30 s (the window starts the daemon).
  ///
  /// Windows: a window closed by the user ends its process right after the
  /// message loop — no Dart code runs then. The runner leaves the note
  /// `gui-clean-exit` beside the marker instead (`windows/runner/main.cpp`);
  /// a note newer than `guiStartedAt` means the previous window ended in
  /// order, and this start counts as the first again. An older note belongs
  /// to an earlier window and proves nothing about this one.
  static UpdateStart guiStartAfterUpdate(String? profileDir) {
    final updateDir = '${profileDir ?? AppPaths.dataDir}/update';
    var result = UpdateStart.none;
    _editMarker(profileDir, (data) {
      final note = File('$updateDir/$_cleanExitNote');
      DateTime? noteAt;
      try {
        if (note.existsSync()) noteAt = note.lastModifiedSync();
      } catch (_) {}
      _dropCleanExitNote(updateDir);
      if (data['guiHealthy'] != null) return data;
      final startedAt = data['guiStartedAt'] as String?;
      if (startedAt != null) {
        final started = DateTime.tryParse(startedAt);
        final closedInOrder =
            noteAt != null && started != null && noteAt.isAfter(started);
        if (!closedInOrder) {
          result = UpdateStart.crashed;
          return data;
        }
      }
      data['guiStartedAt'] = DateTime.now().toIso8601String();
      result = UpdateStart.first;
      return data;
    });
    return result;
  }

  /// The note the Windows runner leaves when its message loop ends in order
  /// (see [guiStartAfterUpdate]).
  static const String _cleanExitNote = 'gui-clean-exit';

  static void _dropCleanExitNote(String updateDir) {
    try {
      final f = File('$updateDir/$_cleanExitNote');
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  /// An orderly window exit within its 30 s is no crash (the window's own
  /// deliberate exits; a closed window on Windows: [guiStartAfterUpdate]).
  static void markGuiStopped(String? profileDir) {
    _editMarker(profileDir, (data) {
      if (data['guiHealthy'] == null) data.remove('guiStartedAt');
      return data;
    });
  }

  /// Removes the marker — after a rollback that could not run, so that the
  /// next start does not try again without end; the update stays.
  static void dropMarker(String? profileDir) {
    _editMarker(profileDir, (_) => null);
  }

  /// The whole-bundle backup a marker points to.
  ///
  /// The marker is written by the binary that APPLIES the update — on the
  /// first update after this change that is still the installed old release.
  /// v4.2.3 (`398a6e40`) writes `version`, `appliedAt` and `previousBinary`
  /// only; its archive paths back the bundle up to `<bundle>.update-bak`
  /// all the same. Without this fallback a crashed first start after an
  /// update FROM v4.2.3 is not rolled back on Linux (the rollback finds no
  /// backup and returns false), and the healthy path leaves a full copy of
  /// the old bundle behind (S407-RUECKNAHME, R-1). `previousBinary` is
  /// `<program>.bak`, so the bundle root follows from the program path the
  /// same way as when the update was applied ([_bundleRootOf]).
  ///
  /// A marker of this tree always carries the key — `null` there means "no
  /// bundle backup" (raw binary), and stays `null`.
  static String? bundleBackupOf(Map<String, dynamic> marker) {
    if (marker.containsKey('bundleBackup')) {
      return marker['bundleBackup'] as String?;
    }
    final prev = marker['previousBinary'] as String?;
    if (prev == null || !prev.endsWith('.bak')) return null;
    final program = prev.substring(0, prev.length - '.bak'.length);
    return '${_bundleRootOf(program)}.update-bak';
  }

  /// The start of a process after a desktop update (v4_2 §26.5: "automatic
  /// recovery if the app crashes within 30 s of an update").
  ///
  /// The marker of [applyDesktopUpdate] alone cannot tell the first start of
  /// the new version from a start after it crashed — both find it. So the
  /// first start writes `startedAt` into it; [markDaemonHealthy] records the
  /// daemon healthy 30 s later and [markUpdateStopped] takes `startedAt` back on an
  /// orderly shutdown. A start that finds `startedAt` therefore follows a
  /// start of the new version that neither reached 30 s nor shut down in
  /// order: [UpdateStart.crashed].
  ///
  /// A daemon that was healthy once (`daemonHealthy`, the marker now waits
  /// only for the window) is past its 30 s: a later start is no first start.
  static UpdateStart startAfterUpdate(String? profileDir) {
    var result = UpdateStart.none;
    _editMarker(profileDir, (data) {
      if (data['daemonHealthy'] != null) return data;
      if (data['startedAt'] != null) {
        result = UpdateStart.crashed;
        return data;
      }
      data['startedAt'] = DateTime.now().toIso8601String();
      result = UpdateStart.first;
      return data;
    });
    return result;
  }

  /// An orderly shutdown within the 30 s is no crash: `startedAt` goes, and
  /// the next start counts as the first again (S392-11).
  static void markUpdateStopped(String? profileDir) {
    _editMarker(profileDir, (data) {
      data.remove('startedAt');
      return data;
    });
  }

  /// Called at startup to check if a pending update crashed. If the marker
  /// file exists and the app is restarting (i.e. it crashed after update),
  /// returns the marker data so the caller can trigger [rollback].
  static Map<String, dynamic>? checkUpdatePending(String? profileDir) {
    final updateDir = '${profileDir ?? AppPaths.dataDir}/update';
    final markerFile = File('$updateDir/update-pending.json');
    if (!markerFile.existsSync()) return null;
    try {
      return jsonDecode(markerFile.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// The helper script that applies a Windows update (`update-apply.bat`):
  /// wait, end daemon and window, back the bundle up, empty it, extract the
  /// ZIP, start daemon (`bin\` first, S367) and window again.
  ///
  /// S407, two findings fixed here:
  ///  * robocopy ran without `/R` and `/W` — on a locked file its default is
  ///    a million retries of 30 s each: the update hung practically forever.
  ///    Now `/R:2 /W:1`, as in [windowsRollbackScript]; a locked file ends
  ///    the step within seconds with an exit code of 8 or more.
  ///  * The window was ended with `wmic`, which newer Windows no longer ships
  ///    (not found on the lab VM, Windows 10.0.26200) — the line did
  ///    nothing. Now `taskkill /IM`.
  /// And a clean exit when a step fails: a failed backup removes the partial
  /// backup and the marker (nothing was replaced — a later rollback must not
  /// restore a half backup); a failed extraction restores the backup, and
  /// once that worked removes backup and marker too. Daemon and window are
  /// started again in every case.
  static String windowsApplyScript({
    required String appDir,
    required String bakDir,
    required String zipPath,
    required String markerPath,
    required String pidFile,
    required String logPath,
    String daemonExe = 'cleona-daemon.exe',
    String guiExe = 'cleona.exe',
  }) {
    String w(String p) => p.replaceAll('/', '\\');
    final app = w(appDir), bak = w(bakDir), zip = w(zipPath);
    final log = w(logPath), marker = w(markerPath), pid = w(pidFile);
    return '@echo off\r\n'
        'echo [%date% %time%] update-apply.bat started > "$log"\r\n'
        'echo [%date% %time%] Waiting 5s for processes to exit... >> "$log"\r\n'
        'ping -n 6 127.0.0.1 >nul\r\n'
        'echo [%date% %time%] Ending remaining processes... >> "$log"\r\n'
        'if exist "$pid" for /F "usebackq" %%P in ("$pid") do (\r\n'
        '  echo [%date% %time%] Killing daemon PID %%P >> "$log"\r\n'
        '  taskkill /F /PID %%P >nul 2>&1\r\n'
        ')\r\n'
        'taskkill /F /IM "$guiExe" >nul 2>&1\r\n'
        'taskkill /F /IM "$daemonExe" >nul 2>&1\r\n'
        'ping -n 3 127.0.0.1 >nul\r\n'
        'del "$pid" >nul 2>&1\r\n'
        'echo [%date% %time%] Backing up... >> "$log"\r\n'
        'if exist "$bak" rmdir /S /Q "$bak"\r\n'
        'robocopy "$app" "$bak" /E /R:2 /W:1 /NFL /NDL /NJH /NJS >> "$log" 2>&1\r\n'
        'if %ERRORLEVEL% geq 8 (\r\n'
        '  echo [%date% %time%] Backup FAILED, update not applied >> "$log"\r\n'
        '  if exist "$bak" rmdir /S /Q "$bak"\r\n'
        '  del "$marker" >nul 2>&1\r\n'
        '  goto cleanup\r\n'
        ')\r\n'
        'echo [%date% %time%] Cleaning app dir before extraction... >> "$log"\r\n'
        'powershell -NoProfile -WindowStyle Hidden -Command "Remove-Item -Path \'$app\\*\' -Recurse -Force -ErrorAction SilentlyContinue" >> "$log" 2>&1\r\n'
        'echo [%date% %time%] Extracting update... >> "$log"\r\n'
        'powershell -NoProfile -WindowStyle Hidden -Command "Expand-Archive -Path \'$zip\' -DestinationPath \'$app\' -Force" >> "$log" 2>&1\r\n'
        'if %ERRORLEVEL% neq 0 (\r\n'
        '  echo [%date% %time%] Extraction FAILED, restoring backup... >> "$log"\r\n'
        '  robocopy "$bak" "$app" /MIR /R:2 /W:1 /NFL /NDL /NJH /NJS >> "$log" 2>&1\r\n'
        '  if not errorlevel 8 (\r\n'
        '    rmdir /S /Q "$bak"\r\n'
        '    del "$marker" >nul 2>&1\r\n'
        '    echo [%date% %time%] Backup restored, update not applied >> "$log"\r\n'
        '  )\r\n'
        '  goto cleanup\r\n'
        ')\r\n'
        'echo [%date% %time%] Extraction successful. >> "$log"\r\n'
        ':cleanup\r\n'
        'if exist "$zip" del /Q "$zip"\r\n'
        'echo [%date% %time%] Starting daemon... >> "$log"\r\n'
        'if exist "$app\\bin\\$daemonExe" (\r\n'
        '  start "" "$app\\bin\\$daemonExe"\r\n'
        ') else (\r\n'
        '  start "" "$app\\$daemonExe"\r\n'
        ')\r\n'
        'echo [%date% %time%] Waiting for daemon... >> "$log"\r\n'
        'ping -n 5 127.0.0.1 >nul\r\n'
        'echo [%date% %time%] Starting GUI... >> "$log"\r\n'
        'start "" "$app\\$guiExe"\r\n'
        'echo [%date% %time%] DONE >> "$log"\r\n';
  }

  /// The helper script of a Windows rollback (§26.5, S407). A running .exe
  /// cannot be overwritten in place, so — as for the update itself
  /// (`update-apply.bat`) — the daemon writes this script, starts it
  /// detached and exits. The script waits, ends what still runs, mirrors the
  /// bundle backup back over the bundle, removes backup and marker only
  /// after the copy succeeded, and starts daemon and window again.
  ///
  /// Pure text, so the smoke checks it on any platform and a probe runs it
  /// on Windows in a throw-away folder with harmless program names.
  /// `robocopy /MIR` is the counterpart of `rsync --delete` (files of the
  /// new version only go too); `/R:2 /W:1` bounds the retries — robocopy's
  /// default is a million retries of 30 s each on a locked file. Exit codes
  /// below 8 are success. Without a backup, or when the copy fails, the
  /// marker goes as well: the update then stays (as before S407) — kept, the
  /// restarted daemon would find `startedAt` again and start this script
  /// again, without end.
  static String windowsRollbackScript({
    required String appDir,
    required String bakDir,
    required String markerPath,
    required String pidFile,
    required String logPath,
    String daemonExe = 'cleona-daemon.exe',
    String guiExe = 'cleona.exe',
  }) {
    String w(String p) => p.replaceAll('/', '\\');
    final app = w(appDir), bak = w(bakDir), log = w(logPath);
    return '@echo off\r\n'
        'echo [%date% %time%] update-rollback.bat started > "$log"\r\n'
        'ping -n 6 127.0.0.1 >nul\r\n'
        'if exist "${w(pidFile)}" for /F "usebackq" %%P in ("${w(pidFile)}") do (\r\n'
        '  taskkill /F /PID %%P >nul 2>&1\r\n'
        ')\r\n'
        'taskkill /F /IM "$guiExe" >nul 2>&1\r\n'
        'taskkill /F /IM "$daemonExe" >nul 2>&1\r\n'
        'ping -n 3 127.0.0.1 >nul\r\n'
        'if not exist "$bak" (\r\n'
        '  echo [%date% %time%] no backup, nothing restored >> "$log"\r\n'
        '  del "${w(markerPath)}" >nul 2>&1\r\n'
        '  goto start_app\r\n'
        ')\r\n'
        'robocopy "$bak" "$app" /MIR /R:2 /W:1 /NFL /NDL /NJH /NJS >> "$log" 2>&1\r\n'
        'if %ERRORLEVEL% geq 8 (\r\n'
        '  echo [%date% %time%] restore FAILED, update stays >> "$log"\r\n'
        '  del "${w(markerPath)}" >nul 2>&1\r\n'
        '  goto start_app\r\n'
        ')\r\n'
        'rmdir /S /Q "$bak"\r\n'
        'del "${w(markerPath)}" >nul 2>&1\r\n'
        'echo [%date% %time%] restored the previous bundle >> "$log"\r\n'
        ':start_app\r\n'
        'if exist "$app\\bin\\$daemonExe" (\r\n'
        '  start "" "$app\\bin\\$daemonExe"\r\n'
        ') else (\r\n'
        '  start "" "$app\\$daemonExe"\r\n'
        ')\r\n'
        'ping -n 5 127.0.0.1 >nul\r\n'
        'start "" "$app\\$guiExe"\r\n'
        'echo [%date% %time%] DONE >> "$log"\r\n';
  }

  /// Writes [windowsRollbackScript] for this installation into the update
  /// directory and returns its path, or `null` without a marker.
  static String? writeWindowsRollback(String currentBinaryPath, String? profileDir) {
    final updateDir = '${profileDir ?? AppPaths.dataDir}/update';
    final markerFile = File('$updateDir/update-pending.json');
    if (!markerFile.existsSync()) return null;
    String? bundleBackup;
    try {
      final data = jsonDecode(markerFile.readAsStringSync()) as Map<String, dynamic>;
      bundleBackup = bundleBackupOf(data);
    } catch (_) {}
    final appDir = _bundleRootOf(currentBinaryPath);
    final script = windowsRollbackScript(
      appDir: appDir,
      bakDir: bundleBackup ?? '$appDir.update-bak',
      markerPath: markerFile.path,
      pidFile: '${profileDir ?? AppPaths.dataDir}/cleona.pid',
      logPath: '$updateDir/update-rollback.log',
    );
    final path = '$updateDir/update-rollback.bat';
    File(path).writeAsStringSync(script);
    return path;
  }

  /// Restore the `.bak` backup over the current binary. Called when a crash
  /// is detected after an update, or manually by the user.
  static bool rollback(String currentBinaryPath, String? profileDir) {
    final updateDir = '${profileDir ?? AppPaths.dataDir}/update';
    final markerFile = File('$updateDir/update-pending.json');

    if (Platform.isWindows) {
      // The same root as when applying (S367) — otherwise
      // `robocopy` would mirror the backup bundle into `bin\`.
      final appDir = _bundleRootOf(currentBinaryPath);
      final bakDir = '$appDir.update-bak';
      if (Directory(bakDir).existsSync()) {
        try {
          final result = Process.runSync('robocopy', [
            bakDir.replaceAll('/', '\\'),
            appDir.replaceAll('/', '\\'),
            '/E', '/NFL', '/NDL', '/NJH', '/NJS',
          ]);
          if (result.exitCode <= 7) {
            try { Directory(bakDir).deleteSync(recursive: true); } catch (_) {}
            if (markerFile.existsSync()) markerFile.deleteSync();
            return true;
          }
        } catch (_) {}
      }
    }

    String? bakPath;
    String? bundleBackup;
    if (markerFile.existsSync()) {
      try {
        final data = jsonDecode(markerFile.readAsStringSync()) as Map<String, dynamic>;
        bakPath = data['previousBinary'] as String?;
        bundleBackup = bundleBackupOf(data);
      } catch (_) {}
    }

    // Linux archive update: the backup is the whole bundle beside the
    // bundle, not `<daemon>.bak` — until S407 the rollback looked only for
    // the file and returned false (S392-11 (c)). Restored the way the update
    // put the new one in: rsync over the bundle root. A running binary may
    // be replaced on Linux; the caller restarts into the restored one.
    // [mirrorArgs] (with `--checksum`, see there).
    if (Platform.isLinux && bundleBackup != null &&
        Directory(bundleBackup).existsSync()) {
      final appDir = _bundleRootOf(currentBinaryPath);
      try {
        final r = Process.runSync('rsync', mirrorArgs(bundleBackup, appDir));
        if (r.exitCode != 0) return false;
        try { Directory(bundleBackup).deleteSync(recursive: true); } catch (_) {}
        if (markerFile.existsSync()) markerFile.deleteSync();
        return true;
      } catch (_) {
        return false;
      }
    }

    bakPath ??= '$currentBinaryPath.bak';
    final bakFile = File(bakPath);
    if (!bakFile.existsSync()) return false;
    try {
      bakFile.copySync(currentBinaryPath);
      if (!Platform.isWindows) {
        Process.runSync('chmod', ['+x', currentBinaryPath]);
      }
      if (markerFile.existsSync()) markerFile.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Remove old verified binaries (not the current target version).
  void cleanupOldVerifiedBinaries() {
    try {
      final dir = Directory('$_updateDir/verified');
      if (!dir.existsSync()) return;
      for (final file in dir.listSync().whereType<File>()) {
        final name = file.path.split('/').last;
        if (_targetVersion != null && name.contains(_targetVersion!)) continue;
        file.deleteSync();
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Monotone sequence number persistence (downgrade protection)
  // ---------------------------------------------------------------------------

  /// The bound as the device database holds it, raised to the value of a
  /// file of an earlier build if that is higher (S407, B3). The file is
  /// removed only once the database holds a value at least as high — at no
  /// moment is the bound lower than before the move.
  int _loadMonotoneSeq() {
    final store = _deviceStoreOrNull();
    var fromDb = 0;
    if (store != null) {
      try {
        final row =
            store.entry(DeviceStore.areaDevice, DeviceStore.keyUpdateMonotoneSeq);
        fromDb = (row?['v'] as num?)?.toInt() ?? 0;
      } catch (e) {
        _log.warn('Monotone sequence unreadable in the device database: $e');
      }
    }
    final fromFile = legacyMonotoneSeqRead(_updateDir);
    if (fromFile == null) return fromDb;
    final highest = fromFile > fromDb ? fromFile : fromDb;
    if (store == null) {
      // No database to carry the bound: keep the file, use its value.
      return highest;
    }
    if (_putMonotoneSeq(store, highest)) {
      legacyDeviceStateDrop(_updateDir, kLegacyMonotoneSeqFile);
      _log.info('Monotone sequence $highest now in the device database; '
          'the file of an earlier build is removed');
    }
    return highest;
  }

  void _saveMonotoneSeq() {
    final store = _deviceStoreOrNull();
    if (store == null) {
      _log.warn('Monotone sequence $_highestSeenMonotoneSeq held in memory '
          'only — no device database');
      return;
    }
    _putMonotoneSeq(store, _highestSeenMonotoneSeq);
  }

  /// Writes [seq] unless the database already holds a higher value — the
  /// bound is only ever raised. Returns whether the database holds at least
  /// [seq] afterwards.
  bool _putMonotoneSeq(DeviceStore store, int seq) {
    try {
      final row =
          store.entry(DeviceStore.areaDevice, DeviceStore.keyUpdateMonotoneSeq);
      final held = (row?['v'] as num?)?.toInt() ?? 0;
      if (held >= seq) return true;
      store.putEntry(
          DeviceStore.areaDevice, DeviceStore.keyUpdateMonotoneSeq, {'v': seq});
      return true;
    } catch (e) {
      _log.warn('Monotone sequence $seq not stored: $e');
      return false;
    }
  }

  DeviceStore? _deviceStoreOrNull() {
    try {
      return _deviceStore?.call();
    } catch (_) {
      return null;
    }
  }
}
