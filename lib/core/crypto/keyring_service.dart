import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/platform/dpapi_ffi.dart';

/// OS Keyring abstraction (Architecture §3.7).
///
/// Protects master_seed and device_keys via platform-native credential storage:
/// Linux: libsecret (GNOME Keyring / KWallet) via secret-tool CLI
/// Windows: DPAPI (CryptProtectData / CryptUnprotectData)
/// Android/macOS/iOS: file-based fallback (platform backends TBD)
///
/// Falls back to file-based storage when no OS keyring is available (daemons
/// without desktop session, unsupported platforms).
///
/// All operations are synchronous — keyring access happens only at daemon
/// start/shutdown, not in hot paths.
abstract class KeyringService {
  // ── Singleton ──────────────────────────────────────────────────────────

  static KeyringService? _instance;

  /// Initialize the global KeyringService for [baseDir].
  /// Must be called once at daemon startup before any key access.
  /// The [probeAsync] step (secret-tool availability check) is the only
  /// async part — subsequent load/store calls are synchronous.
  static Future<KeyringService> init(String baseDir) async {
    if (_instance != null) return _instance!;
    final log = CLogger.get('keyring', profileDir: baseDir);

    if (Platform.isLinux) {
      final service = _LinuxSecretToolKeyring(log);
      if (await service._isAvailable()) {
        log.info('Using GNOME Keyring / KWallet via secret-tool');
        _instance = service;
        return _instance!;
      }
      log.warn('secret-tool not available — file-based key storage');
    } else if (Platform.isWindows) {
      final dpapi = _WindowsDpapiKeyring(baseDir, log);
      if (await dpapi._roundTripProbe()) {
        log.info('Using Windows DPAPI for key protection');
        _instance = dpapi;
        return _instance!;
      }
      log.warn('DPAPI round-trip probe failed or timed out — file-based key storage');
      dpapi.delete('_probe');
    } else if (Platform.isMacOS) {
      log.info('Using macOS Keychain via security CLI');
      _instance = _MacOsKeychainKeyring(log);
      return _instance!;
    } else if (Platform.isAndroid || Platform.isIOS) {
      // Android/iOS: registerInstance() from main.dart with MethodChannel
      // backend (EncryptedSharedPreferences / Keychain). If that failed,
      // _instance is still null and we fall through to file-based fallback.
      if (_instance != null) return _instance!;
      log.warn('Mobile keyring not registered — file-based fallback');
    }

    log.info('Using file-based key storage (${Platform.operatingSystem})');
    _instance = _FileKeyringFallback(baseDir, log);
    return _instance!;
  }

  /// Register a pre-built KeyringService instance. Used by platform-specific
  /// entry points (e.g. main.dart on Android) that set up MethodChannel-based
  /// backends before the generic init() runs.
  static void registerInstance(KeyringService service) {
    _instance = service;
  }

  /// Access the initialized KeyringService. Throws if [init] wasn't called.
  static KeyringService get instance {
    if (_instance == null) {
      throw StateError('KeyringService.init() not called yet');
    }
    return _instance!;
  }

  /// Whether a KeyringService has been initialized.
  static bool get isInitialized => _instance != null;

  /// Reset singleton (for testing only).
  static void resetForTest() => _instance = null;

  /// Test seam (S363): builds the file fallback directly, optionally as if
  /// the machine had a different name.
  ///
  /// Why this path exists: `_FileKeyringFallback` is the branch in which
  /// FOUR of the five platforms can land (see [init], l. 33-63) —
  /// but [init] only chooses it if `secret-tool`/DPAPI fails. On a machine
  /// on which a backend answers, it is unreachable from a test. But the
  /// statement the S363 guard checks lives only here: **a ciphertext that
  /// this machine cannot open must be read as ABSENT, not as its own
  /// ciphertext.**
  ///
  /// [hostname] reproduces the host name change exactly byte for byte:
  /// the fallback has as input only the blob and the key derived from it,
  /// and both are in this case the same as on a renamed machine. In
  /// production the parameter is never set.
  /// [saltOverride] replaces the content of `.keyring_salt` (32 B) — the
  /// lever with which the S363 guard, since the salt rework, produces a
  /// failing decryption. Before, that was the host name; it is out of the
  /// v3 derivation (see `_FileKeyringFallback._deriveKey`) and no longer
  /// suits that purpose.
  /// In production this parameter is never set either.
  static KeyringService fileFallbackForTest(String baseDir,
          {String? hostname, Uint8List? saltOverride}) =>
      _FileKeyringFallback(baseDir, CLogger.get('keyring', profileDir: baseDir),
          hostnameOverride: hostname, saltOverride: saltOverride);

  // ── Interface ──────────────────────────────────────────────────────────

  /// Store binary data under [name]. Returns true on success.
  bool store(String name, Uint8List data);

  /// Load binary data by [name]. Returns null if not found.
  Uint8List? load(String name);

  /// Delete stored data by [name]. Returns true if something was deleted.
  bool delete(String name);

  /// True if backed by a real OS keyring (vs file fallback).
  bool get isHardwareProtected;

  // ── S363, point 1: the gated side path ──────────────────────────
  //
  // Why the contract stands HERE and not in `keyring_mobile.dart`:
  // `IdentityManager` is used by the daemon, and the daemon import graph
  // must stay Flutter-free (preflight check "Daemon import graph
  // Flutter-free"). `keyring_mobile.dart` imports
  // `package:flutter/services.dart`. The caller therefore only talks to
  // this base class; the mobile version overrides.
  //
  // What is gated and what is not — measured, not chosen: the
  // keyring carries exactly TWO names (`master_seed`, `seed_phrase`),
  // and only the second has, as measured, NO second copy next to it. For
  // `master_seed`, `master_seed.json.enc` lies next to it under the raw
  // key file `db.key` (finding F-4 of the proposal
  // `docs/v4-redesign/S363-VORLAGE-android-sperre-und-salt.md`); a
  // lock in front of it would be ornament.

  /// Whether this version knows a gated side path at all.
  bool get hasGate => false;

  /// State of the lock, without reading or writing anything.
  Future<GateOutcome> gateStatus() async => GateOutcome.unavailable;

  /// Reads [name] from the gated storage and asks for the device code if
  /// necessary. [title] and [description] are the text of the system
  /// dialog and come from the UI (i18n) — this layer has no language.
  Future<GatedRead> loadGated(String name,
          {String? title, String? description}) async =>
      const GatedRead(null, GateOutcome.unavailable);

  /// Moves the gated names from the ungated into the gated storage,
  /// provided that works WITHOUT a user dialog. Without a lock a no-op.
  ///
  /// Is called at start (`MobileKeyringService.init`) and after creating
  /// an identity (`IdentityManager._storeSeedPhrase`) — otherwise a freshly
  /// generated phrase would lie ungated until the next start.
  Future<void> promoteGatedNames() async {}
}

/// Outcome of an access to the gated storage.
enum GateOutcome {
  /// Read, or ready.
  ready,

  /// The lock holds, but nothing lies under this name.
  absent,

  /// The user cancelled the system dialog.
  cancelled,

  /// The device has no secure screen lock — an auth-bound key cannot
  /// even be generated there.
  noDeviceLock,

  /// Screen lock removed or changed: the key is permanently invalid, the
  /// content thus gone. Not an error of the construction but the price of
  /// device binding — and the reason why the 24 words belong written
  /// down.
  invalidated,

  /// This platform or this build knows no lock.
  unavailable,
}

/// Result of [KeyringService.loadGated].
class GatedRead {
  final Uint8List? value;
  final GateOutcome outcome;
  const GatedRead(this.value, this.outcome);
}

// ── Linux: secret-tool CLI (wraps libsecret) ────────────────────────────

class _LinuxSecretToolKeyring extends KeyringService {
  final CLogger _log;

  _LinuxSecretToolKeyring(this._log);

  @override
  bool get isHardwareProtected => true;

  /// Check if secret-tool is installed and a Secret Service daemon is reachable.
  Future<bool> _isAvailable() async {
    try {
      final which = await Process.run('which', ['secret-tool'])
          .timeout(const Duration(seconds: 2));
      if (which.exitCode != 0) return false;
      // Probe: lookup a key that won't exist. If the Secret Service daemon is
      // reachable, secret-tool returns quickly with exit 1 (not found). If no
      // daemon is running (no display session), it hangs or errors.
      final probe = await Process.run(
        'secret-tool', ['lookup', 'application', 'cleona', 'type', '_probe'],
      ).timeout(const Duration(seconds: 3));
      return probe.exitCode == 0 || probe.exitCode == 1;
    } catch (_) {
      return false;
    }
  }

  @override
  bool store(String name, Uint8List data) {
    try {
      final b64 = base64Encode(data);
      // secret-tool store reads the secret from stdin. Use Process.start
      // synchronously by writing stdin and waiting for exit.
      final result = Process.runSync(
        'bash', ['-c',
          'echo -n ${_shellEscape(b64)} | secret-tool store '
          '--label=${_shellEscape('Cleona: $name')} '
          'application cleona type ${_shellEscape(name)}'],
      );
      if (result.exitCode != 0) {
        _log.warn('secret-tool store failed for "$name" (exit ${result.exitCode})');
        return false;
      }
      return true;
    } catch (e) {
      _log.warn('secret-tool store error for "$name": $e');
      return false;
    }
  }

  @override
  Uint8List? load(String name) {
    try {
      final result = Process.runSync(
        'secret-tool',
        ['lookup', 'application', 'cleona', 'type', name],
        stdoutEncoding: utf8,
      );
      if (result.exitCode != 0) return null;
      final b64 = (result.stdout as String).trim();
      if (b64.isEmpty) return null;
      return base64Decode(b64);
    } catch (e) {
      _log.warn('secret-tool lookup error for "$name": $e');
      return null;
    }
  }

  @override
  bool delete(String name) {
    try {
      final result = Process.runSync(
        'secret-tool', ['clear', 'application', 'cleona', 'type', name],
      );
      return result.exitCode == 0;
    } catch (e) {
      _log.warn('secret-tool clear error for "$name": $e');
      return false;
    }
  }

  static String _shellEscape(String s) => "'${s.replaceAll("'", "'\\''")}'";
}

// ── Windows: DPAPI via PowerShell ───────────────────────────────────────

class _WindowsDpapiKeyring extends KeyringService {
  final String _baseDir;
  final CLogger _log;

  _WindowsDpapiKeyring(this._baseDir, this._log);

  @override
  bool get isHardwareProtected => true;

  String _pathFor(String name) => '$_baseDir/$name.dpapi';

  Future<bool> _roundTripProbe() async {
    try {
      final testData = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
      final encrypted = DpapiFfi.instance.protect(testData);
      if (encrypted == null) {
        _log.warn('DPAPI Protect probe failed');
        return false;
      }
      final decrypted = DpapiFfi.instance.unprotect(encrypted);
      if (decrypted == null) {
        _log.warn('DPAPI Unprotect probe failed');
        return false;
      }
      if (decrypted.length != 4) return false;
      for (var i = 0; i < 4; i++) {
        if (decrypted[i] != testData[i]) return false;
      }
      return true;
    } catch (e) {
      _log.warn('DPAPI round-trip probe exception: $e');
      return false;
    }
  }

  @override
  bool store(String name, Uint8List data) {
    try {
      final encrypted = DpapiFfi.instance.protect(data);
      if (encrypted == null) {
        _log.warn('DPAPI Protect failed for "$name"');
        return false;
      }
      final file = File(_pathFor(name));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(encrypted);
      return true;
    } catch (e) {
      _log.warn('DPAPI store error for "$name": $e');
      return false;
    }
  }

  @override
  Uint8List? load(String name) {
    try {
      final file = File(_pathFor(name));
      if (!file.existsSync()) return null;
      final raw = file.readAsBytesSync();
      if (raw.isEmpty) return null;

      // Migration: old PowerShell-based code wrote base64-encoded DPAPI
      // ciphertext as text. Detect by checking if content is valid ASCII
      // base64 (only printable chars + whitespace). Raw DPAPI ciphertext
      // contains non-ASCII bytes, so the heuristic is reliable.
      Uint8List encrypted;
      if (_looksLikeBase64Text(raw)) {
        var text = String.fromCharCodes(raw).trim();
        text = text.replaceAll(RegExp(r'\s+'), '');
        if (!RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(text)) {
          _log.warn('DPAPI file for "$name" contains invalid characters');
          return null;
        }
        encrypted = base64Decode(text);
      } else {
        encrypted = raw;
      }

      final decrypted = DpapiFfi.instance.unprotect(encrypted);
      if (decrypted == null) {
        _log.warn('DPAPI Unprotect failed for "$name"');
        return null;
      }

      // Re-write as raw binary so future loads skip the base64 path.
      if (_looksLikeBase64Text(raw)) {
        try {
          file.writeAsBytesSync(encrypted);
        } catch (_) {}
      }

      return decrypted;
    } catch (e) {
      _log.warn('DPAPI load error for "$name": $e');
      return null;
    }
  }

  static bool _looksLikeBase64Text(Uint8List data) {
    for (final b in data) {
      if (b > 0x7E) return false;
      if (b < 0x09) return false;
    }
    return true;
  }

  @override
  bool delete(String name) {
    try {
      final file = File(_pathFor(name));
      if (file.existsSync()) {
        file.deleteSync();
        return true;
      }
      return false;
    } catch (e) {
      _log.warn('DPAPI delete error for "$name": $e');
      return false;
    }
  }
}

// ── File-based fallback (all platforms) ──────────────────────────────────

class _FileKeyringFallback extends KeyringService {
  final String _baseDir;
  final CLogger _log;

  /// Set only from [KeyringService.fileFallbackForTest]. In production
  /// `null` — then `Platform.localHostname` applies. Since S363 the host
  /// name goes ONLY into the legacy keys v1/v2, no longer into v3.
  final String? _hostnameOverride;

  /// Set only from [KeyringService.fileFallbackForTest] (32 B). In
  /// production `null` — then the content of `.keyring_salt` applies.
  final Uint8List? _saltOverride;

  Uint8List? _encKey;

  _FileKeyringFallback(this._baseDir, this._log,
      {String? hostnameOverride, Uint8List? saltOverride})
      // ignore: prefer_initializing_formals
      : _hostnameOverride = hostnameOverride,
        // ignore: prefer_initializing_formals
        _saltOverride = saltOverride;

  String get _hostname => _hostnameOverride ?? Platform.localHostname;

  @override
  bool get isHardwareProtected => false;

  String _pathFor(String name) => '$_baseDir/.$name.keyring';

  // ── S363: the salt ───────────────────────────────────────────────────
  //
  // Until S363 the key of this fallback was
  // `SHA-256('$hostname:cleona-file-keyring-v2')` — two PUBLIC values,
  // one of them a string in the source code. On Android
  // `Platform.localHostname` is, as measured, `localhost`
  // (`docs/v4-redesign/S363-messung-android-hostname.md`), the key thus
  // the same in EVERY installation: a single precomputed value opened
  // every affected device.
  //
  // v3 instead derives from 32 random bytes per installation, and the
  // host name drops out of the derivation ENTIRELY. It contributed no
  // entropy (it stands in every backup, in every log), but an error case:
  // a renamed computer lost its profile. That error case is thus gone —
  // checked in `smoke_keyring_fallback_guard.dart`, A7.
  //
  // What the salt does NOT achieve, explicitly: it lies next to the
  // ciphertext. Whoever has the disk has it too. The gain is the removal
  // of the key's UNIVERSALITY ("one value opens all" -> "one targeted
  // attack per device"), not the strength of the fallback.
  static const int _saltLength = 32;
  static const String _saltFileName = '.keyring_salt';

  /// Extension of the side file. The process stands in front of it:
  /// `.master_seed.keyring.4711.tmp` — see [_writeVerified].
  static const String _tmpSuffix = '.tmp';

  /// Identifier at the start of every v3 container: `C K 3 \0`.
  ///
  /// Why an identifier is needed and not just a key chain: without it a
  /// v3 container cannot be distinguished from a v2 container (both are
  /// nonce+ciphertext). If the salt is then missing, the construction
  /// could not decide whether a new salt is safe (the file was v2 and is
  /// re-keyed anyway) or whether it makes the only copy unreadable (the
  /// file was v3). Exactly this distinction is required by section 3.4
  /// of the proposal.
  ///
  /// `\0` is not printable, so it does not collide with
  /// [_looksLikeLegacyPlaintext].
  static const List<int> _v3Magic = [0x43, 0x4b, 0x33, 0x00];

  String get _saltPath => '$_baseDir/$_saltFileName';

  Uint8List? _saltCache;

  /// Reads the salt without ever creating one. `null` = no usable salt.
  Uint8List? _readSalt() {
    if (_saltOverride != null) return _saltOverride;
    if (_saltCache != null) return _saltCache;
    final f = File(_saltPath);
    if (!f.existsSync()) return null;
    final bytes = f.readAsBytesSync();
    if (bytes.length != _saltLength) {
      _log.warn('File keyring: $_saltFileName has ${bytes.length} B '
          '(expected $_saltLength) — treating it as ABSENT. Nothing is '
          'overwritten; see _saltForWrite().');
      return null;
    }
    _saltCache = Uint8List.fromList(bytes);
    return _saltCache;
  }

  /// Are there containers in the profile that open ONLY with a salt?
  ///
  /// That is the condition under which a new salt would be data loss.
  bool _hasV3Blobs() {
    final dir = Directory(_baseDir);
    if (!dir.existsSync()) return false;
    for (final e in dir.listSync(followLinks: false).whereType<File>()) {
      final n = e.uri.pathSegments.last;
      // The side files too: after a crash between writing and renaming,
      // the only copy may lie in the process's own
      // `.master_seed.keyring.<pid>.tmp` (S368), and on LEGACY holdings
      // additionally in `.master_seed.keyring.old` — the remnant of the
      // Windows three-step run until S370. This build no longer produces
      // `.old` ([_ersetzeWithRetry]), but a profile from an older version
      // may carry one, and whoever overlooks it here permits a new salt
      // and makes it unreadable.
      if (!n.startsWith('.') || !_isContainerName(n)) continue;
      try {
        final raf = e.openSync();
        try {
          final head = raf.readSync(_v3Magic.length);
          if (_startsWithMagic(head)) return true;
        } finally {
          raf.closeSync();
        }
      } catch (_) {
        // Unreadable file: do not count as v3, but not as a free pass
        // either — the caller additionally checks for profile data.
      }
    }
    return false;
  }

  /// Does [name] carry a container — canonical, `.old` or the process's
  /// own `.<pid>.tmp`?
  ///
  /// **`.old` DELIBERATELY stays here** (S370). This build no longer
  /// creates `.old` — the Windows three-step that produced it is deleted.
  /// But a profile from an older version may carry one, and if it is the
  /// only copy, [_hasV3Blobs] must not overlook it. Deleting it here would
  /// be the kind of cleanup that silently costs data.
  ///
  /// Deliberately NOT `contains('.keyring')`: the profile holds
  /// `.keyring_salt`, `.keyring_migrated` and `.keyring_repair_v2`, and
  /// those are not containers. What is required is the segment `.keyring`
  /// at the end or before a dot.
  static bool _isContainerName(String n) {
    const seg = '.keyring';
    final i = n.lastIndexOf(seg);
    if (i < 0) return false;
    final rest = n.substring(i + seg.length);
    return rest.isEmpty ||
        rest == '.old' ||
        RegExp(r'^\.\d+\.tmp$').hasMatch(rest);
  }

  /// Salt for WRITING. Creates one if there is nothing to lose —
  /// and throws if there is.
  ///
  /// The model is `FileEncryption._loadOrCreateLegacyKey`
  /// (`file_encryption.dart:51-60`): no silent regeneration when profile
  /// data lie there. A salt that disappears and is silently replaced makes
  /// every v3 container permanently unreadable — on a taken-over Linux
  /// profile without `secret-tool` that is the master seed in its only
  /// copy (finding F-2 of the proposal).
  Uint8List _saltForWrite() {
    final existing = _readSalt();
    // `_readSalt()` returns `_saltOverride` unchanged if set
    // — down here it is therefore always `null` (test path already done).
    if (existing != null) return existing;

    final saltFileExists = File(_saltPath).existsSync();
    final hasV3 = _hasV3Blobs();
    final hasProfileData = Directory('$_baseDir/identities').existsSync();

    if (hasV3 || (saltFileExists && hasProfileData)) {
      throw StateError(
          'keyring salt ($_saltFileName) is missing or has the wrong length '
          'while v3 keyring containers (hasV3=$hasV3) or profile data '
          '(hasProfileData=$hasProfileData) exist — refusing to generate a '
          'new salt (would make the existing containers unreadable forever)');
    }

    // ── ONE SALT PER PROFILE, EVEN WITH TWO PROCESSES (S368) ───────────
    //
    // **Why the latch stands HERE and not at the caller.** Until S368 the
    // code explicitly stated "on Linux/Windows the daemon owns the
    // keyring — the GUI connects via IPC and never accesses keys
    // directly". That sentence fell with `main.dart:176-198`: since S368
    // the UI starts up the keyring itself, because
    // `setup_screen.dart:143` generates the master seed in ITS process.
    // Thus TWO processes access the same file, and the guarantee "only one
    // writes" now holds only via the call order — exactly the class of
    // guarantee that has caught up with this project several times
    // already.
    //
    // The old way was check-then-act: `existsSync()` above, then
    // `writeAsBytesSync()` here. Two processes that both stand in the
    // window in between BOTH generate a salt; the last writer wins the
    // disk, the first keeps its own in `_saltCache` and `_encKey`.
    // Measured on 05.09.2026 with two processes at a wall-clock barrier:
    // 20 of 20 runs two salts, 13 of them left behind a profile from which
    // NO process could fetch the master seed any more. The worst outcome
    // was the silent one: a process got `store()==true` AND read its seed
    // back verbatim (the probe in `_writeVerified` checks against the key
    // IN MEMORY, not against the disk) — and nevertheless the container
    // was unreadable for every later start.
    //
    // `createSync(exclusive: true)` is `O_EXCL`: exactly one process
    // creates the file, every other gets an exception and then reads the
    // winner's salt. The latch thus sits at the place where writing
    // happens, and holds regardless of who calls.
    Directory(_baseDir).createSync(recursive: true);
    final f = File(_saltPath);
    try {
      f.createSync(exclusive: true);
    } on FileSystemException {
      // ONLY "already exists" means "another one was there first". Every
      // other reason (no write permission, disk full) must come through
      // — otherwise this branch waits two seconds and then reports a
      // cause that is not true. Measured: `smoke_keyring_fallback_
      // guard` A10a makes the directory unwritable, and the first
      // version of this latch turned that into an "another process
      // created it and did not finish writing".
      if (!File(_saltPath).existsSync()) rethrow;
      // Its salt applies — not ours. It may still be empty (created,
      // but the 32 B not yet written), hence the waiting.
      final foreign = _awaitForeignSalt();
      if (foreign == null) {
        throw StateError(
            '$_saltFileName exists but did not reach $_saltLength B within '
            '${_saltWaitMs}ms — another process created it and did not '
            'finish. Refusing to write a second salt (it would make that '
            "process's containers unreadable forever).");
      }
      _log.info('File keyring: another process created $_saltFileName first '
          '— adopting its salt instead of generating a second one');
      _saltCache = foreign;
      return foreign;
    }

    final salt = SodiumFFI().randomBytes(_saltLength);
    f.writeAsBytesSync(salt, flush: true);
    if (Platform.isLinux || Platform.isMacOS) {
      Process.runSync('chmod', ['600', f.path]);
    }
    _saltCache = salt;
    _log.info('File keyring: generated a fresh per-installation salt '
        '($_saltLength B, $_saltFileName)');
    return salt;
  }

  /// How long to wait for another process's salt.
  ///
  /// The window between `createSync(exclusive: true)` and
  /// `writeAsBytesSync` is one random call and one write —
  /// microseconds. Two seconds are generous and still finite; waiting
  /// longer would mean covering for a crashed neighbour forever.
  static const int _saltWaitMs = 2000;

  /// Waits until the file created by the neighbouring process carries its
  /// 32 B. `null` = it did not get them within the deadline.
  Uint8List? _awaitForeignSalt() {
    final f = File(_saltPath);
    final end = DateTime.now().add(const Duration(milliseconds: _saltWaitMs));
    while (DateTime.now().isBefore(end)) {
      try {
        final b = f.readAsBytesSync();
        if (b.length == _saltLength) return Uint8List.fromList(b);
      } catch (_) {
        // The neighbour may be holding the file right now — keep waiting.
      }
      sleep(const Duration(milliseconds: 5));
    }
    return null;
  }

  Uint8List _deriveKeyFromSalt(Uint8List salt) {
    final tag = utf8.encode(':cleona-file-keyring-v3');
    final material = Uint8List(salt.length + tag.length)
      ..setRange(0, salt.length, salt)
      ..setRange(salt.length, salt.length + tag.length, tag);
    return SodiumFFI().sha256(material);
  }

  /// v3 key for READING. `null` if there is no salt.
  Uint8List? _deriveKeyForRead() {
    if (_encKey != null) return _encKey;
    final salt = _readSalt();
    if (salt == null) return null;
    _encKey = _deriveKeyFromSalt(salt);
    return _encKey;
  }

  /// v3 key for WRITING. Creates a salt if needed (or throws).
  Uint8List _deriveKeyForWrite() {
    if (_encKey != null) return _encKey!;
    _encKey = _deriveKeyFromSalt(_saltForWrite());
    return _encKey!;
  }

  Uint8List? _v2Key;
  Uint8List? _v1Key;

  /// v2 (until S363): host name + fixed string. **Only for READING any
  /// more** — every hit is rewritten to v3.
  Uint8List _deriveKeyV2() {
    if (_v2Key != null) return _v2Key!;
    // S106 fix: key derivation no longer depends on baseDir. A path
    // change (profileDir vs baseDir, deploy to different location) used
    // to silently break all stored secrets.
    final material = utf8.encode('$_hostname:cleona-file-keyring-v2');
    _v2Key = SodiumFFI().sha256(Uint8List.fromList(material));
    return _v2Key!;
  }

  /// v1 (pre-S106): host name + baseDir. **Only for READING any more.**
  /// The host name MUST stay here — the legacy files are encrypted with
  /// it (finding F-3 (6) of the proposal).
  Uint8List _deriveKeyV1() {
    if (_v1Key != null) return _v1Key!;
    final material = utf8.encode('$_hostname:$_baseDir:cleona-file-keyring-v1');
    _v1Key = SodiumFFI().sha256(Uint8List.fromList(material));
    return _v1Key!;
  }

  static bool _startsWithMagic(List<int> blob) {
    if (blob.length < _v3Magic.length) return false;
    for (var i = 0; i < _v3Magic.length; i++) {
      if (blob[i] != _v3Magic[i]) return false;
    }
    return true;
  }

  @override
  bool store(String name, Uint8List data) {
    try {
      final key = _deriveKeyForWrite();
      return _writeVerified(name, data, key);
    } catch (e) {
      _log.warn('File keyring store error for "$name": $e');
      return false;
    }
  }

  /// Write, READ BACK, COMPARE — and only then replace.
  ///
  /// Why this effort (proposal 3.3, finding F-2): on a profile without
  /// `secret-tool` the master seed can exist EXACTLY ONCE, namely in
  /// `.master_seed.keyring`. Until S368 the takeover produced that
  /// (`KeyMigration` deleted the file copy after successful storing);
  /// that takeover is removed, today the case is produced by
  /// `LegacyKeyPurge` — it removes `master_seed.json.enc` when the
  /// keyring holds the same seed verbatim. The situation has thus stayed
  /// the same, only the producer is a different one. The old version
  /// wrote in place (`writeAsBytesSync` on the canonical file); an abort
  /// between start and end of the write would have destroyed this one
  /// copy — and exactly that is the operation the salt rework triggers on
  /// EVERY existing profile.
  ///
  /// The construction is tmp+rename, extended by the read-back probe from
  /// `MobileKeyringService._roundTripProbe` (`keyring_mobile.dart`).
  ///
  /// **The model was `AtomicJsonWriter.writeJsonFile`, and its Windows
  /// branch has NOT been replicated here since S370** — see
  /// [_replaceWithRetry]. `atomic_json_writer.dart:33-47` and
  /// `file_encryption.dart:296-310`/`:363-377` still carry the same
  /// three-step; that is an open finding at those places, not a reason to
  /// build it back in here.
  bool _writeVerified(String name, Uint8List data, Uint8List key) {
    final sodium = SodiumFFI();
    final nonce = sodium.randomBytes(24);
    final ciphertext = sodium.secretBoxEncrypt(data, key, nonce);
    final blob = Uint8List(_v3Magic.length + 24 + ciphertext.length);
    blob.setRange(0, _v3Magic.length, _v3Magic);
    blob.setRange(_v3Magic.length, _v3Magic.length + 24, nonce);
    blob.setRange(_v3Magic.length + 24, blob.length, ciphertext);

    final canonical = File(_pathFor(name));
    // ── THE SIDE FILE BELONGS TO ONE PROCESS (S368) ────────────────
    //
    // Here stood `'${canonical.path}.tmp'` — ONE name for all. As long as
    // the daemon owned the keyring alone, that was right. Since
    // `main.dart:176-198` the UI starts it up as well, and both write the
    // same name `master_seed`: the UI in
    // `IdentityManager._storeMasterSeed`, the daemon every 30 s in
    // `_checkProfileIntegrity` (`service_daemon.dart:989` ->
    // `:1202`, Timer.periodic 30 s) as well as in
    // `IdentityManager.reconcileKeyringDeposit`.
    //
    // Measured on 05.09.2026, two processes at a wall-clock barrier:
    // both wrote into the same `.tmp`, and then
    //   * "PathNotFoundException: Cannot rename file to
    //     '.master_seed.keyring', path = '.master_seed.keyring.tmp'" —
    //     the other one had already renamed it away,
    //   * "Cannot open file, path = '.master_seed.keyring.tmp'" — on
    //     reading back it was gone,
    //   * "read back as 76 B, expected 76 B — refusing to replace" — the
    //     lengths are EQUAL, it is the content that is compared: what was
    //     read was the other process's container.
    // The third case is the dangerous one: if the read-back probe were
    // not byte-wise, this process would have promoted the other one's
    // container to the canonical name.
    //
    // One name per process solves all three: each writes and checks its
    // own piece, and the final `rename` is atomic on POSIX — the last one
    // wins, but what wins is always a complete, checked container.
    final tmp = File('${canonical.path}.$pid$_tmpSuffix');
    canonical.parent.createSync(recursive: true);

    try {
      tmp.writeAsBytesSync(blob, flush: true);
      if (Platform.isLinux || Platform.isMacOS) {
        Process.runSync('chmod', ['600', tmp.path]);
      }

      // ── The probe: read back and compare byte-wise ──────────
      final readBack = tmp.readAsBytesSync();
      if (!_bytesEqual(readBack, blob)) {
        throw StateError('keyring container for "$name" read back as '
            '${readBack.length} B, expected ${blob.length} B — refusing to '
            'replace the existing file');
      }
      final roundTrip = sodium.secretBoxDecrypt(
          Uint8List.fromList(
              readBack.sublist(_v3Magic.length + 24)),
          key,
          Uint8List.fromList(
              readBack.sublist(_v3Magic.length, _v3Magic.length + 24)));
      if (!_bytesEqual(roundTrip, data)) {
        throw StateError('keyring container for "$name" decrypts to '
            '${roundTrip.length} B, expected ${data.length} B — refusing to '
            'replace the existing file');
      }

      // ── Only now replace — in ONE step, on every platform ──
      _replaceWithRetry(tmp, canonical);
      if (Platform.isLinux || Platform.isMacOS) {
        Process.runSync('chmod', ['600', canonical.path]);
      }
      return true;
    } catch (e) {
      if (tmp.existsSync()) {
        try {
          tmp.deleteSync();
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// How often the final renaming is repeated, and how long to wait in
  /// between.
  ///
  /// Five attempts over 12 ms. The case they catch is a READER that holds
  /// the canonical file open at the moment of replacing (Windows:
  /// `ERROR_SHARING_VIOLATION`) — that lasts the length of a
  /// `readAsBytesSync`, no longer. Whoever waits long here covers for a
  /// hanging neighbour instead of bridging a race.
  static const int _replaceAttempts = 5;
  static const int _replacePauseMs = 3;

  /// Renames [tmp] to [canonical] — ONE step, with retry.
  ///
  /// ── A WINDOWS THREE-STEP STOOD HERE, AND IT WAS HARMFUL ─────
  ///
  /// Until S370 a three-step ran under `Platform.isWindows`:
  /// `canonical -> .old`, `tmp -> canonical`, delete `.old`. The
  /// reasoning for it stood in `atomic_json_writer.dart`: "Windows:
  /// `renameSync` cannot overwrite". **That is not true.** Dart maps
  /// `File.rename` there onto `MoveFileExW` with `MOVEFILE_REPLACE_EXISTING`;
  /// re-measured directly on the machine on 05.09.2026: the renaming
  /// REPLACES an existing file on NTFS.
  ///
  /// The three-step was thus not only superfluous, it tore a hole:
  /// between step one and two the canonical name does NOT exist. And
  /// `.old` — unlike the side file since S368 — carried no process
  /// number, so it was the same name for all processes, on which
  /// check-then-act then ran (`if (old.existsSync())
  /// old.deleteSync(); canonical.renameSync(old.path); ...`).
  ///
  /// Measured on Windows, two processes with 300 renames each, a third
  /// reads along on the side:
  ///
  ///     path                       errors per proc.  name MISSING  torn
  ///     one step                    98 / 99             0        0/4808
  ///     three steps                 54 / 68          1808        0/3847
  ///     one step + retry             3 /  2             0        0/4987
  ///
  /// 1808 looks out of about 3847 saw the canonical name missing — about
  /// a third. The rescue path [_recoverFromSidecar] was a band-aid on
  /// exactly this self-made hole.
  ///
  /// ── WHY THE RETRY IS NOT A CONVENIENCE ──────────────────────
  ///
  /// A lost race yields a `false` from [store], and
  /// `IdentityManager._storeMasterSeed` **throws** in response — the
  /// identity creation aborts. The last row of the table is therefore the
  /// actual yield: 98/99 errors become 3/2, and those are errors nobody
  /// sees any more, because the next attempt takes effect. The retry
  /// closes a data-loss window.
  ///
  /// **Only [FileSystemException].** Every other error comes through
  /// immediately: a `StateError` from the read-back probe is not a race,
  /// and repeating it five times would obscure a cause.
  void _replaceWithRetry(File tmp, File canonical) {
    for (var attempt = 1;; attempt++) {
      try {
        tmp.renameSync(canonical.path);
        return;
      } on FileSystemException catch (e) {
        if (attempt >= _replaceAttempts) rethrow;
        _log.warn('File keyring: renaming ${tmp.path} onto '
            '${canonical.path} failed on attempt $attempt/'
            '$_replaceAttempts ($e) — retrying in ${_replacePauseMs}ms');
        sleep(const Duration(milliseconds: _replacePauseMs));
      }
    }
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Decrypts [blob] with v3, v2 or v1 — WITHOUT side effect.
  ///
  /// Counterpart to [load], which takes the same path and migrates while
  /// doing so. Here it is only read, because the caller
  /// ([_recoverFromSidecar]) must first decide whether it found anything
  /// at all.
  Uint8List? _decodeAny(List<int> blob) {
    final sodium = SodiumFFI();
    if (_startsWithMagic(blob)) {
      final key = _deriveKeyForRead();
      if (key == null) return null;
      try {
        return sodium.secretBoxDecrypt(
            Uint8List.fromList(blob.sublist(_v3Magic.length + 24)),
            key,
            Uint8List.fromList(
                blob.sublist(_v3Magic.length, _v3Magic.length + 24)));
      } catch (_) {
        return null;
      }
    }
    if (blob.length < 40) return null;
    final nonce = Uint8List.fromList(blob.sublist(0, 24));
    final ct = Uint8List.fromList(blob.sublist(24));
    for (final key in [_deriveKeyV2(), _deriveKeyV1()]) {
      try {
        return sodium.secretBoxDecrypt(ct, key, nonce);
      } catch (_) {}
    }
    return null;
  }

  /// Fetches the secret back from a leftover side file.
  ///
  /// **Why this exists, and why precisely on Windows.** [_writeVerified]
  /// replaces the canonical file via `tmp`+`rename`. On POSIX
  /// `rename(2)` is atomic: either old or new, never nothing. Windows
  /// cannot rename over an existing file, which is why the path there
  /// takes THREE steps (canonical -> `.old`, `.tmp` -> canonical, `.old`
  /// gone) — and between step one and two the canonical file does NOT
  /// exist. If the operation dies exactly there (crash, power failure,
  /// virus scanner briefly holding the file), the only copy of the master
  /// seed would lie in a file nobody looks at any more.
  ///
  /// `AtomicJsonWriter.readJsonFile` does exactly that (`.tmp`, then
  /// `.old`), and without this twin the Windows branch of [_writeVerified]
  /// would have been a NEW loss possibility — introduced by the same
  /// change that is meant to prevent the loss. The order `.tmp` before
  /// `.old` is the right one: `.tmp` carries the already CHECKED new
  /// content, `.old` the previous one.
  /// The side files for [name], in the order in which they are
  /// consulted: first every `.<pid>.tmp` (there stands the already
  /// CHECKED new content), then `.old` (the previous one).
  ///
  /// Since S368 the `.tmp` names carry the process number, so there can be
  /// more than one — that is why the directory is read instead of trying
  /// two fixed names.
  ///
  /// `.old` is still tried, although this build has not created any since
  /// S370: on legacy holdings it may be the only copy.
  /// It is thus an HEIRLOOM, not part of the write path.
  List<File> _sidecarsOf(String name) {
    final canonical = _pathFor(name);
    final stem = canonical.split(Platform.pathSeparator).last;
    final out = <File>[];
    try {
      final dir = File(canonical).parent;
      if (dir.existsSync()) {
        final pattern = RegExp('^${RegExp.escape(stem)}\\.\\d+\\.tmp\$');
        for (final e in dir.listSync(followLinks: false).whereType<File>()) {
          if (pattern.hasMatch(e.uri.pathSegments.last)) out.add(e);
        }
      }
    } catch (_) {
      // Unreadable directory: `.old` below remains the way back.
    }
    out.sort((a, b) => a.path.compareTo(b.path));
    out.add(File('$canonical.old'));
    return out;
  }

  Uint8List? _recoverFromSidecar(String name) {
    for (final f in _sidecarsOf(name)) {
      final suffix = f.path.substring(_pathFor(name).length);
      if (!f.existsSync()) continue;
      try {
        final plain = _decodeAny(f.readAsBytesSync());
        if (plain == null) continue;
        _log.warn('File keyring "$name": the canonical file is missing but '
            '$suffix opened — recovering an interrupted write. Promoting it '
            'back to the canonical name. (A ".old" sidecar can only come '
            'from a profile written before S370; this build never creates '
            'one — see _ersetzeMitWiederholung.)');
        try {
          if (_writeVerified(name, plain, _deriveKeyForWrite())) f.deleteSync();
        } catch (e) {
          _log.warn('File keyring "$name": recovered from $suffix but could '
              'not promote it ($e) — the sidecar stays where it is.');
        }
        return plain;
      } catch (e) {
        _log.warn('File keyring "$name": $suffix unreadable: $e');
      }
    }
    return null;
  }

  @override
  Uint8List? load(String name) {
    try {
      final file = File(_pathFor(name));
      if (!file.existsSync()) return _recoverFromSidecar(name);
      final blob = file.readAsBytesSync();
      if (blob.isEmpty) return null;

      // ── v3: identifier in front, key from the salt ──────────────────
      if (_startsWithMagic(blob)) {
        final key = _deriveKeyForRead();
        if (key == null) {
          _log.warn('File keyring "$name": container is v3 (salted) but '
              '$_saltFileName is missing or has the wrong length. Reporting '
              'ABSENT — NOT generating a new salt, which would make this '
              'container unreadable forever. Restore $_saltFileName from a '
              'backup, or fall back to the file ground-truth (S106 '
              'dual-write).');
          return null;
        }
        try {
          return SodiumFFI().secretBoxDecrypt(
              Uint8List.fromList(blob.sublist(_v3Magic.length + 24)),
              key,
              Uint8List.fromList(
                  blob.sublist(_v3Magic.length, _v3Magic.length + 24)));
        } catch (_) {
          _log.warn('File keyring "$name": ${blob.length} B v3 container '
              'undecryptable — the salt in $_saltFileName does not belong to '
              'this container (restored from a foreign backup, or replaced). '
              'Reporting ABSENT so the file ground-truth (S106 dual-write) '
              'takes over instead of a bogus secret.');
          return null;
        }
      }

      // Shorter than nonce(24)+MAC(16): cannot be our container at all,
      // so it is a plaintext file from the time before `ea756876`
      // (2026-06-20) — until then store() wrote the raw bytes.
      if (blob.length < 40) return _adoptLegacyPlaintext(name, blob);

      final sodium = SodiumFFI();
      final nonce = Uint8List.fromList(blob.sublist(0, 24));
      final ciphertext = Uint8List.fromList(blob.sublist(24));
      // v2 (Rechnername, S106..S363)
      try {
        final plaintext = sodium.secretBoxDecrypt(ciphertext, _deriveKeyV2(), nonce);
        _migrateToV3(name, plaintext, 'v2');
        return plaintext;
      } catch (_) {}
      // v1 (Rechnername + baseDir, pre-S106)
      try {
        final plaintext = sodium.secretBoxDecrypt(ciphertext, _deriveKeyV1(), nonce);
        _migrateToV3(name, plaintext, 'v1');
        return plaintext;
      } catch (_) {}

      // ── S363: HERE STOOD `return Uint8List.fromList(blob)` ──────────────
      //
      // Since `ea756876` (2026-06-20) the branch was the migration path for
      // plaintext files from the time before. But it never checked the
      // statement, only a PROXY: "decryption failed" was read as "this is
      // plaintext". Exactly the same output, however, is produced by the
      // second case — ciphertext that THIS installation cannot open.
      //
      // Measured (S363 measurement, section 3.3) on the real file of this
      // workstation:
      //     host=delllin      v2=OPEN  v1=FAIL  -> plaintext(32B)
      //     host=delllin-neu  v2=FAIL  v1=FAIL  -> RAW BLOB 72B as seed
      //
      // The 72 B of ciphertext were passed on as the master seed. Because
      // `IdentityManager.loadMasterSeed()` passes through every non-null
      // value, `master_seed.json` — the ground truth of the S106 double
      // write — was NEVER reached, and `HdWallet.deriveFileEncKey`
      // (HKDF, takes any length) turned it into a well-formed,
      // deterministically wrong file key. The break was silent.
      //
      // Now the statement is checked, not the proxy: only what LOOKS like a
      // plaintext file is taken over as such; everything else counts as
      // ABSENT, so that the fallback it was built for takes effect.
      if (_looksLikeLegacyPlaintext(blob)) {
        return _adoptLegacyPlaintext(name, blob);
      }
      _log.warn('File keyring "$name": ${blob.length} B undecryptable with '
          'the v2/v1 legacy keys under hostname "$_hostname" and carrying no '
          'v3 marker. Reporting ABSENT so the file ground-truth '
          '(S106 dual-write) takes over instead of a bogus secret.');
      return null;
    } catch (e) {
      _log.warn('File keyring load error for "$name": $e');
      return null;
    }
  }

  /// Rewrites a successfully read legacy container to v3.
  ///
  /// If that fails (no salt creatable, probe failed), the OLD file stays
  /// and the reader still gets its plaintext — a failing migration must
  /// not cost the only copy.
  void _migrateToV3(String name, Uint8List plaintext, String from) {
    try {
      final key = _deriveKeyForWrite();
      if (_writeVerified(name, plaintext, key)) {
        _log.info('File keyring "$name": migrated $from -> v3 (salted, '
            'hostname no longer part of the derivation)');
      }
    } catch (e) {
      _log.warn('File keyring "$name": $from container read fine but the '
          'migration to v3 failed ($e) — leaving the $from file in place. '
          'The secret is NOT lost.');
    }
  }

  /// Does [blob] look like a plaintext file from the time before `ea756876`?
  ///
  /// MEASURED, not guessed: the file fallback carries exactly TWO
  /// entries, and that is the entire inventory in the tree (`grep` over
  /// `lib/` for `keyring.*\.(load|store)\(`):
  ///   * `master_seed`  — 32 raw bytes, falls under the 40-B limit
  ///     above and does not arrive here at all;
  ///   * `seed_phrase`  — `words.join(' ').codeUnits`, i.e. 24 BIP-39 words
  ///     and 23 spaces: exclusively printable ASCII.
  ///
  /// Ciphertext is XSalsa20 output, thus uniformly distributed. That 40 or
  /// more such bytes all fall into the 95-character-wide printable window
  /// has probability (95/256)^40 < 2^-57. That is not a heuristic on
  /// suspicion but a format distinction with a computed error rate.
  static bool _looksLikeLegacyPlaintext(List<int> blob) {
    for (final b in blob) {
      if (b < 0x20 || b > 0x7e) return false;
    }
    return true;
  }

  /// Takes over a recognised plaintext file and ENCRYPTS it in doing so.
  ///
  /// The old branch only returned and left the migration to the next
  /// `store()` — but that only comes when a new seed is created, i.e.
  /// practically never. The plaintext file thus stayed. The v1->v2 branch
  /// above has done it right since S106; here it follows suit.
  Uint8List _adoptLegacyPlaintext(String name, List<int> blob) {
    final plaintext = Uint8List.fromList(blob);
    _log.info('File keyring "$name": legacy plaintext (${blob.length} B) '
        '— re-encrypting in place');
    _migrateToV3(name, plaintext, 'plaintext');
    return plaintext;
  }

  @override
  bool delete(String name) {
    try {
      final file = File(_pathFor(name));
      if (file.existsSync()) {
        file.deleteSync();
        return true;
      }
      return false;
    } catch (e) {
      _log.warn('File keyring delete error for "$name": $e');
      return false;
    }
  }
}


// ── macOS: Keychain via security CLI ────────────────────────────────────

class _MacOsKeychainKeyring extends KeyringService {
  final CLogger _log;

  _MacOsKeychainKeyring(this._log);

  @override
  bool get isHardwareProtected => true;

  String _service(String name) => 'cleona_$name';

  @override
  bool store(String name, Uint8List data) {
    try {
      final b64 = base64Encode(data);
      // Delete existing entry first (add-generic-password fails on duplicates).
      Process.runSync('security', [
        'delete-generic-password', '-a', 'cleona', '-s', _service(name),
      ]);
      final result = Process.runSync('security', [
        'add-generic-password',
        '-a', 'cleona',
        '-s', _service(name),
        '-w', b64,
        '-T', '', // no ACL — app access only
      ]);
      if (result.exitCode != 0) {
        _log.warn('Keychain store failed for "$name" (exit ${result.exitCode})');
        return false;
      }
      return true;
    } catch (e) {
      _log.warn('Keychain store error for "$name": $e');
      return false;
    }
  }

  @override
  Uint8List? load(String name) {
    try {
      final result = Process.runSync('security', [
        'find-generic-password', '-a', 'cleona', '-s', _service(name), '-w',
      ]);
      if (result.exitCode != 0) return null;
      final b64 = (result.stdout as String).trim();
      if (b64.isEmpty) return null;
      return base64Decode(b64);
    } catch (e) {
      _log.warn('Keychain load error for "$name": $e');
      return null;
    }
  }

  @override
  bool delete(String name) {
    try {
      final result = Process.runSync('security', [
        'delete-generic-password', '-a', 'cleona', '-s', _service(name),
      ]);
      return result.exitCode == 0;
    } catch (e) {
      _log.warn('Keychain delete error for "$name": $e');
      return false;
    }
  }
}
