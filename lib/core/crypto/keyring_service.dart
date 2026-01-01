import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/network/clogger.dart';

/// OS Keyring abstraction (Architecture §3.7).
///
/// Protects master_seed and device_keys via platform-native credential storage:
/// Linux: libsecret (GNOME Keyring / KWallet) via secret-tool CLI
/// Windows: DPAPI (CryptProtectData / CryptUnprotectData)
/// Android/macOS/iOS: file-based fallback (platform backends TBD)
///
/// Falls back to file-based storage when no OS keyring is available (headless
/// daemons, unsupported platforms).
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
      log.info('Using Windows DPAPI for key protection');
      _instance = _WindowsDpapiKeyring(baseDir, log);
      return _instance!;
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

  // ── Interface ──────────────────────────────────────────────────────────

  /// Store binary data under [name]. Returns true on success.
  bool store(String name, Uint8List data);

  /// Load binary data by [name]. Returns null if not found.
  Uint8List? load(String name);

  /// Delete stored data by [name]. Returns true if something was deleted.
  bool delete(String name);

  /// True if backed by a real OS keyring (vs file fallback).
  bool get isHardwareProtected;
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
      // daemon is running (headless), it hangs or errors.
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

  @override
  bool store(String name, Uint8List data) {
    try {
      final b64Input = base64Encode(data);
      // PowerShell DPAPI: encrypts data bound to the current Windows user.
      final result = Process.runSync('powershell', [
        '-NoProfile', '-NonInteractive', '-Command',
        'Add-Type -AssemblyName System.Security; '
            '[Convert]::ToBase64String('
            '[System.Security.Cryptography.ProtectedData]::Protect('
            '[Convert]::FromBase64String("$b64Input"), '
            '\$null, '
            '[System.Security.Cryptography.DataProtectionScope]::CurrentUser'
            '))',
      ]);
      if (result.exitCode != 0) {
        _log.warn('DPAPI Protect failed for "$name": ${result.stderr}');
        return false;
      }
      final encrypted = (result.stdout as String).trim();
      final file = File(_pathFor(name));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(encrypted);
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
      var encrypted = file.readAsStringSync().trim();
      if (encrypted.isEmpty) return null;
      // Strip whitespace first: PowerShell's ToBase64String may line-wrap
      // at 76 chars, inserting \r\n into the DPAPI ciphertext file.
      // Without stripping, the regex below would reject valid DPAPI output,
      // causing post-migration identity loss (seed gone, legacy deleted).
      encrypted = encrypted.replaceAll(RegExp(r'\s+'), '');
      // Validate strict base64 to prevent PowerShell injection via tampered
      // .dpapi files (the string is interpolated into a -Command argument).
      if (!RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(encrypted)) {
        _log.warn('DPAPI file for "$name" contains invalid characters — '
            'possible tampering, refusing to load');
        return null;
      }
      final result = Process.runSync('powershell', [
        '-NoProfile', '-NonInteractive', '-Command',
        'Add-Type -AssemblyName System.Security; '
            '[Convert]::ToBase64String('
            '[System.Security.Cryptography.ProtectedData]::Unprotect('
            '[Convert]::FromBase64String("$encrypted"), '
            '\$null, '
            '[System.Security.Cryptography.DataProtectionScope]::CurrentUser'
            '))',
      ]);
      if (result.exitCode != 0) {
        _log.warn('DPAPI Unprotect failed for "$name": ${result.stderr}');
        return null;
      }
      final b64 = (result.stdout as String).trim();
      if (b64.isEmpty) return null;
      return base64Decode(b64);
    } catch (e) {
      _log.warn('DPAPI load error for "$name": $e');
      return null;
    }
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
  Uint8List? _encKey;

  _FileKeyringFallback(this._baseDir, this._log);

  @override
  bool get isHardwareProtected => false;

  String _pathFor(String name) => '$_baseDir/.$name.keyring';

  Uint8List? _v1Key;

  Uint8List _deriveKey() {
    if (_encKey != null) return _encKey!;
    // S106 fix: key derivation no longer depends on baseDir. A path
    // change (profileDir vs baseDir, deploy to different location) used
    // to silently break all stored secrets.
    final material = utf8.encode('${Platform.localHostname}:cleona-file-keyring-v2');
    _encKey = SodiumFFI().sha256(Uint8List.fromList(material));
    return _encKey!;
  }

  Uint8List _deriveKeyV1() {
    if (_v1Key != null) return _v1Key!;
    final material = utf8.encode('${Platform.localHostname}:$_baseDir:cleona-file-keyring-v1');
    _v1Key = SodiumFFI().sha256(Uint8List.fromList(material));
    return _v1Key!;
  }

  @override
  bool store(String name, Uint8List data) {
    try {
      final sodium = SodiumFFI();
      final key = _deriveKey();
      final nonce = sodium.randomBytes(24);
      final ciphertext = sodium.secretBoxEncrypt(data, key, nonce);
      final blob = Uint8List(24 + ciphertext.length);
      blob.setRange(0, 24, nonce);
      blob.setRange(24, blob.length, ciphertext);

      final file = File(_pathFor(name));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(blob);
      if (Platform.isLinux || Platform.isMacOS) {
        Process.runSync('chmod', ['600', file.path]);
      }
      return true;
    } catch (e) {
      _log.warn('File keyring store error for "$name": $e');
      return false;
    }
  }

  @override
  Uint8List? load(String name) {
    try {
      final file = File(_pathFor(name));
      if (!file.existsSync()) return null;
      final blob = file.readAsBytesSync();
      if (blob.isEmpty) return null;

      if (blob.length < 40) return Uint8List.fromList(blob);
      final sodium = SodiumFFI();
      final nonce = Uint8List.fromList(blob.sublist(0, 24));
      final ciphertext = Uint8List.fromList(blob.sublist(24));
      // Try v2 key first (baseDir-independent)
      try {
        return sodium.secretBoxDecrypt(ciphertext, _deriveKey(), nonce);
      } catch (_) {}
      // Fallback: v1 key (baseDir-dependent, pre-S106)
      try {
        final plaintext = sodium.secretBoxDecrypt(ciphertext, _deriveKeyV1(), nonce);
        _log.info('File keyring "$name": migrating from v1 to v2 key');
        store(name, plaintext);
        return plaintext;
      } catch (_) {
        _log.info('File keyring "$name": migrating plaintext to encrypted');
        return Uint8List.fromList(blob);
      }
    } catch (e) {
      _log.warn('File keyring load error for "$name": $e');
      return null;
    }
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
