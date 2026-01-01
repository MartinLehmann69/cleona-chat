import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/crypto/file_sha256.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/util/hex.dart' show bytesToHex, hexToBytes;
import 'package:cleona/core/platform/app_paths.dart';
import 'package:cleona/core/rendezvous/rendezvous_provider.dart'
    show EndpointAddress;
import 'package:cleona/core/update/binary_fragment_store.dart';
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

/// Describes which Reed-Solomon parts a node can serve over HTTP.
///
/// Since S406-UPDPKG (P4) only [DeltaUpdateManager]'s HTTP download uses it;
/// that path is the delta order's to replace (E-1 B, §26.6.2: "A delta is
/// simply a smaller object on the same path as the full binary").
class FragmentSource {
  final EndpointAddress address;
  final List<int> fragmentIndices;
  final bool hasFullBinary;

  const FragmentSource({
    required this.address,
    required this.fragmentIndices,
    required this.hasFullBinary,
  });
}

class BinaryUpdateManager {
  final BinaryFragmentStore _store;
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

  void Function(BinaryUpdateState state, double progress)? onStateChanged;
  void Function(String version, String binaryPath)? onUpdateReady;

  BinaryUpdateManager({
    required this._store,
    required this._checker,
    String? profileDir,
  })  : _log = CLogger.get('bin-update', profileDir: profileDir) {
    _highestSeenMonotoneSeq = _loadMonotoneSeq();
  }

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
  /// [BinaryFragmentStore.enforceBudget] as the protected install target —
  /// this manager is the only object that knows which (platform, version) is
  /// currently being downloaded/assembled/verified for local installation
  /// (`main.dart:applyUpdate()` reads `_targetVersion` for exactly that
  /// decision on Android and desktop alike), so the exemption is set here,
  /// not guessed at inside the store.
  Future<void> gc(String currentVersion, int budgetBytes) async {
    try {
      await _store.garbageCollect(currentVersion);
      await _store.enforceBudget(budgetBytes,
          protectPlatform: _targetPlatform, protectVersion: _targetVersion);
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

  Future<bool> applyDesktopUpdate(String currentBinaryPath) async {
    final verifiedPath = _verifiedBinaryPathSync();
    if (verifiedPath == null) {
      _fail('applyDesktopUpdate: no verified binary available');
      return false;
    }
    try {
      final currentFile = File(currentBinaryPath);
      final bakPath = '$currentBinaryPath.bak';
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
        final zipSrc = verifiedPath.replaceAll('/', '\\');
        final tmpZip = '$zipSrc.zip';
        final zipDest = File('$verifiedPath.zip');
        if (zipDest.existsSync()) zipDest.deleteSync();
        File(verifiedPath).copySync(zipDest.path);

        final batPath = '$_updateDir/update-apply.bat'.replaceAll('/', '\\');
        final batLog = '$_updateDir/update-apply.log'.replaceAll('/', '\\');
        final home = Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Cleona';
        final pidFile = '$home\\.cleona\\cleona.pid';
        File(batPath).writeAsStringSync(
          '@echo off\r\n'
          'echo [%date% %time%] update-apply.bat started > "$batLog"\r\n'
          'echo [%date% %time%] Waiting 5s for processes to exit... >> "$batLog"\r\n'
          'ping -n 6 127.0.0.1 >nul\r\n'
          'echo [%date% %time%] Force-killing remaining processes... >> "$batLog"\r\n'
          'for /F "usebackq" %%P in ("$pidFile") do (\r\n'
          '  echo [%date% %time%] Killing daemon PID %%P >> "$batLog"\r\n'
          '  taskkill /F /PID %%P >nul 2>&1\r\n'
          ')\r\n'
          'wmic process where "name=\'cleona.exe\'" call terminate >nul 2>&1\r\n'
          'wmic process where "name=\'cleona-daemon.exe\'" call terminate >nul 2>&1\r\n'
          'ping -n 3 127.0.0.1 >nul\r\n'
          'del "$pidFile" >nul 2>&1\r\n'
          'echo [%date% %time%] Backing up... >> "$batLog"\r\n'
          'if exist "$bakDir" rmdir /S /Q "$bakDir"\r\n'
          'robocopy "$appDir" "$bakDir" /E /NFL /NDL /NJH /NJS >> "$batLog" 2>&1\r\n'
          'if %ERRORLEVEL% geq 8 (\r\n'
          '  echo [%date% %time%] Backup FAILED — aborting update >> "$batLog"\r\n'
          '  goto start_app\r\n'
          ')\r\n'
          'echo [%date% %time%] Cleaning app dir before extraction... >> "$batLog"\r\n'
          'powershell -NoProfile -WindowStyle Hidden -Command "Remove-Item -Path \'$appDir\\*\' -Recurse -Force -ErrorAction SilentlyContinue" >> "$batLog" 2>&1\r\n'
          'echo [%date% %time%] Extracting update... >> "$batLog"\r\n'
          'powershell -NoProfile -WindowStyle Hidden -Command "Expand-Archive -Path \'$tmpZip\' -DestinationPath \'$appDir\' -Force" >> "$batLog" 2>&1\r\n'
          'if %ERRORLEVEL% neq 0 (\r\n'
          '  echo [%date% %time%] Extraction FAILED, restoring backup... >> "$batLog"\r\n'
          '  robocopy "$bakDir" "$appDir" /MIR /NFL /NDL /NJH /NJS >> "$batLog" 2>&1\r\n'
          '  goto cleanup\r\n'
          ')\r\n'
          'echo [%date% %time%] Extraction successful. >> "$batLog"\r\n'
          ':cleanup\r\n'
          'if exist "$tmpZip" del /Q "$tmpZip"\r\n'
          ':start_app\r\n'
          'echo [%date% %time%] Starting daemon... >> "$batLog"\r\n'
          // `bin\\` first (S367): there `dart build cli` puts the
          // binary, and only from there does its embedded
          // path `..\\lib\\sqlite3.dll` resolve. The root stays as
          // fallback, so that a bundle in the old layout
          // keeps starting.
          'if exist "$appDir\\bin\\cleona-daemon.exe" (\r\n'
          '  start "" "$appDir\\bin\\cleona-daemon.exe"\r\n'
          ') else (\r\n'
          '  start "" "$appDir\\cleona-daemon.exe"\r\n'
          ')\r\n'
          'echo [%date% %time%] Waiting for daemon... >> "$batLog"\r\n'
          'ping -n 5 127.0.0.1 >nul\r\n'
          'echo [%date% %time%] Starting GUI... >> "$batLog"\r\n'
          'start "" "$appDir\\cleona.exe"\r\n'
          'echo [%date% %time%] DONE >> "$batLog"\r\n',
        );
        _windowsUpdateBatPath = batPath;
        _log.info('Wrote update-apply.bat: $batPath');
      } else if (isGzip && Platform.isLinux) {
        // Linux tar.gz: full bundle replacement (daemon + GUI + libs + data).
        final appDir = _bundleRootOf(currentBinaryPath);
        final bakDir = '$appDir.update-bak';

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
          final rsyncResult = await Process.run('rsync', [
            '-a', '--delete', '$sourceDir/', '$appDir/',
          ]);
          if (rsyncResult.exitCode != 0) {
            await Process.run('rsync', ['-a', '--delete', '$bakDir/', '$appDir/']);
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
      marker.writeAsStringSync(jsonEncode({
        'version': _targetVersion,
        'appliedAt': DateTime.now().toIso8601String(),
        'previousBinary': bakPath,
      }));
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
  /// `update-pending.json` marker and deletes the `.bak` backup.
  static void markUpdateHealthy(String? profileDir) {
    final updateDir = '${profileDir ?? AppPaths.dataDir}/update';
    final markerFile = File('$updateDir/update-pending.json');
    if (!markerFile.existsSync()) return;
    try {
      final data = jsonDecode(markerFile.readAsStringSync()) as Map<String, dynamic>;
      final bakPath = data['previousBinary'] as String?;
      markerFile.deleteSync();
      if (bakPath != null) {
        final bak = File(bakPath);
        if (bak.existsSync()) bak.deleteSync();
        final appDir = File(bakPath).parent.path;
        final bakDir = Directory('$appDir.update-bak');
        if (bakDir.existsSync()) {
          try { bakDir.deleteSync(recursive: true); } catch (_) {}
        }
      }
    } catch (_) {}
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
    if (markerFile.existsSync()) {
      try {
        final data = jsonDecode(markerFile.readAsStringSync()) as Map<String, dynamic>;
        bakPath = data['previousBinary'] as String?;
      } catch (_) {}
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

  int _loadMonotoneSeq() {
    try {
      final file = File('$_updateDir/monotone_seq.txt');
      if (file.existsSync()) return int.parse(file.readAsStringSync().trim());
    } catch (_) {}
    return 0;
  }

  void _saveMonotoneSeq() {
    try {
      final dir = Directory(_updateDir);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      File('$_updateDir/monotone_seq.txt')
          .writeAsStringSync('$_highestSeenMonotoneSeq');
    } catch (_) {}
  }
}
