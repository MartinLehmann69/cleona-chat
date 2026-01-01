import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:cleona/core/crypto/keyring_service.dart';
import 'package:cleona/core/log/clogger.dart';

/// §3.7 Mobile OS Keyring via MethodChannel (shared protocol).
///
/// Android: EncryptedSharedPreferences backed by AndroidKeyStore.
/// iOS: Keychain Services (kSecClassGenericPassword).
///
/// Preloads all stored keys into an in-memory cache during [init] (async).
/// Subsequent [load] calls return from cache (sync). [store]/[delete] update
/// the cache immediately and persist to the native side asynchronously.
///
/// ── S363: THE WRITE PATH IS MEASURED, NOT ASSUMED ────────────────
///
/// Until S363 [store] reported a **constant**: `return true`, without a
/// success being observed anywhere. The bridge's answer was logged in a
/// `catchError` and thrown away.
///
/// But the bridge does answer, on both platforms — re-measured in the
/// source code:
///   * Android `KeyringHandler.kt:59-60` — `p.edit().putString(...).commit()`
///     and then `result.success(true)`; if the keyring did not open at
///     all, `result.error("KEYRING_UNAVAILABLE", ...)` (`:46-50`).
///   * iOS `KeyringHandler.swift:35-36` — `result(ok)` with
///     `ok = (SecItemAdd(...) == errSecSuccess)` (`:81-85`), i.e. a real
///     `false` if the Keychain rejects the entry.
///
/// What the discarded answer cost: `IdentityManager._storeSeedPhrase`
/// (`identity_manager.dart:279-285`) writes the file ONLY if the keyring
/// reports `false` — so on mobile devices never. And
/// `KeyMigration` (`key_migration.dart:407` + `:473-477`) DELETES
/// `seed_phrase.json.enc` as soon as `store` says `true`. An invented
/// success report was thus a delete command for the 24 words.
///
/// The construction of the answer now follows the pattern Windows has
/// always done right (`_WindowsDpapiKeyring._roundTripProbe()`,
/// `keyring_service.dart`): first write-read-compare, then choose the
/// backend. After that every answer of the bridge carries the state on.
class MobileKeyringService extends KeyringService {
  static const _channel = MethodChannel('chat.cleona/keyring');

  /// S363, point 1 (option D): the channel via which the device code is
  /// confirmed. The counterpart is `MainActivity.kt`, KEYGUARD_CHANNEL —
  /// `KeyguardManager.createConfirmDeviceCredentialIntent` +
  /// `startActivityForResult`, without a new dependency and without a
  /// change of the activity base class.
  static const _gateChannel = MethodChannel('chat.cleona/keyguard');

  /// Names that belong behind the lock. MEASURED, not chosen: the
  /// keyring carries exactly two names, and before the rework
  /// `loadSeedPhrase()` had three callers, all display or export, NONE in
  /// the receive path (today: `settings_screen.dart:208`, `main.dart:3192`
  /// via `loadSeedPhraseGated`, `ipc_server.dart:2819` still synchronous —
  /// the daemon does not run on Android, `android/` names neither
  /// `service_daemon` nor `cleona-daemon`; plus since the reconciliation
  /// `identity_manager.dart:460`, which moves the file copy behind the
  /// lock). The foreground service thus loses nothing through the lock.
  /// For `master_seed` the opposite applies (`service_daemon.dart`,
  /// `ios_background_fetch.dart`), and it moreover has an unprotected
  /// second copy next to it — finding F-4.
  static const Set<String> gatedNames = {'seed_phrase'};

  /// Identifiers from `KeyringHandler.kt` (companion object). Whoever
  /// changes them there changes them here too.
  static const _gateReady = 'READY';
  static const _gateNoDeviceLock = 'NO_DEVICE_LOCK';
  static const _gateAuthRequired = 'AUTH_REQUIRED';
  static const _gateInvalidated = 'INVALIDATED';

  /// Name of the probe entry. Identical to `_probe` in the DPAPI branch
  /// (`keyring_service.dart:49`), so that both platforms carry the same
  /// name and a reader finds them together.
  static const _probeName = '_probe';

  final Map<String, Uint8List> _cache = {};
  final CLogger _log;
  final String _platformName;

  /// Whether the native storage has worked as MEASURED. Initial value
  /// `false` — it is proven in [_roundTripProbe] during [init], and it
  /// falls back to `false` permanently as soon as the bridge reports a
  /// failure. There is no way to set it to `true` without a measurement.
  bool _bridgeHealthy = false;

  /// Names whose plaintext now lies only in [_cache] — i.e. in the
  /// memory of THIS process and nowhere else. Diagnostic information for
  /// callers and logs; every entry here is gone on the next start.
  final Set<String> _unpersisted = <String>{};

  MobileKeyringService._(this._log, this._platformName);

  /// Create and preload a mobile keyring instance. Registers itself as the
  /// global KeyringService singleton — call BEFORE KeyringService.init().
  /// Returns null if the native backend is unavailable (KeyringService
  /// falls through to file-based fallback in that case).
  static Future<MobileKeyringService?> init(String baseDir) async {
    final log = CLogger.get('keyring', profileDir: baseDir);
    final platform = _detectPlatform();
    final service = MobileKeyringService._(log, platform);
    try {
      final all = await _channel.invokeMethod<Map>('loadAll');
      if (all != null) {
        for (final entry in all.entries) {
          try {
            service._cache[entry.key as String] =
                base64Decode(entry.value as String);
          } catch (_) {}
        }
      }
      // A leftover probe entry from an aborted run is no secret and does
      // not belong in the cache.
      service._cache.remove(_probeName);

      // `loadAll` only proves that READING is possible. Whether writing
      // is possible is a second question — and exactly the one whose
      // answer was invented until S363.
      if (!await service._roundTripProbe()) {
        log.warn('$platform keyring: write probe failed — the native side '
            'cannot persist. Falling through to the file-based fallback '
            'rather than registering a keyring that silently forgets.');
        return null;
      }
      service._bridgeHealthy = true;

      log.info('$platform keyring: preloaded ${service._cache.length} keys, '
          'write probe OK');
      KeyringService.registerInstance(service);
      // S363: move the 24 words behind the device code lock, provided
      // that works without a dialog. Deliberately NOT awaited — the
      // program start does not hang on the lock, and if it fails, the
      // next start tries again.
      unawaited(service.promoteGatedNames());
      return service;
    } catch (e) {
      log.warn('$platform keyring unavailable: $e — will use file fallback');
      return null;
    }
  }

  static String _detectPlatform() {
    try {
      // dart:io Platform not available in all contexts; this is safe in Flutter
      return const bool.fromEnvironment('dart.library.io')
          ? 'Mobile' : 'Mobile';
    } catch (_) {
      return 'Mobile';
    }
  }

  /// Write, read back, compare, clean up. The same construction as
  /// `_WindowsDpapiKeyring._roundTripProbe()`.
  ///
  /// The probe value is freshly random, so that a hit cannot stem from an
  /// old entry of the same name — otherwise the probe would measure
  /// "something lies there" instead of "my write has arrived".
  Future<bool> _roundTripProbe() async {
    final rnd = Random.secure();
    final marker =
        base64Encode(List<int>.generate(16, (_) => rnd.nextInt(256)));
    try {
      final stored = await _channel
          .invokeMethod<bool>('store', {'name': _probeName, 'data': marker});
      if (stored != true) {
        _log.warn('$_platformName keyring: write probe — native side '
            'answered "$stored" instead of true');
        return false;
      }
      final read =
          await _channel.invokeMethod<String>('load', {'name': _probeName});
      if (read != marker) {
        _log.warn('$_platformName keyring: write probe — read back a '
            'different value than was written (${read == null ? "null" : "${read.length} chars"})');
        return false;
      }
      return true;
    } catch (e) {
      _log.warn('$_platformName keyring: write probe failed: $e');
      return false;
    } finally {
      try {
        await _channel.invokeMethod('delete', {'name': _probeName});
      } catch (_) {}
      _cache.remove(_probeName);
    }
  }

  @override
  bool get isHardwareProtected => _bridgeHealthy;

  /// Names whose value lies only in memory. Empty as long as the
  /// bridge holds.
  Set<String> get unpersistedNames => Set.unmodifiable(_unpersisted);

  @override
  bool store(String name, Uint8List data) {
    _cache[name] = Uint8List.fromList(data);
    _unpersisted.add(name);
    if (!_bridgeHealthy) {
      // The failure is PASSED ON, not swallowed: the caller
      // (IdentityManager, KeyMigration) has a file path for exactly
      // this case and may now take it.
      _log.warn('$_platformName keyring: refusing to claim a store for '
          '"$name" — the native side is known not to persist. The value '
          'lives only in this process. Caller must use its file fallback.');
      return false;
    }
    unawaited(_persist(name, data));
    return true;
  }

  /// Store and report the success that the native side ACTUALLY
  /// delivered.
  ///
  /// [store] cannot do that: its signature is synchronous, the bridge is
  /// not. That is why [init] measures the write path in advance and
  /// [store] carries the result on — but a caller that wants to delete a
  /// file or switch off a fallback should be able to await the real value
  /// instead of relying on the advance measurement.
  Future<bool> storeAndConfirm(String name, Uint8List data) {
    _cache[name] = Uint8List.fromList(data);
    _unpersisted.add(name);
    if (!_bridgeHealthy) return Future.value(false);
    return _persist(name, data);
  }

  /// The only place where the bridge's answer is evaluated.
  ///
  /// `try`/`catch` lies INSIDE the `async` body — an `unawaited()`
  /// behind a synchronous `try` catches nothing in Dart (S351).
  Future<bool> _persist(String name, Uint8List data) async {
    try {
      final ok = await _channel.invokeMethod<bool>('store', {
        'name': name,
        'data': base64Encode(data),
      });
      if (ok == true) {
        _unpersisted.remove(name);
        return true;
      }
      _log.warn('$_platformName keyring: native side REJECTED the store for '
          '"$name" (answered "$ok") — value is not persisted');
    } catch (e) {
      _log.warn('$_platformName keyring persist failed for "$name": $e');
    }
    // Sticky: a bridge that once could not write must not claim success
    // again on the next call.
    _bridgeHealthy = false;
    return false;
  }

  @override
  Uint8List? load(String name) => _cache[name];

  /// **RB-4 (S370): deletes BOTH storages, not only the ungated one.**
  ///
  /// Until S370 `delete` addressed exclusively `getPrefs()`
  /// (`KeyringHandler.kt:308-315`). Exactly that was too little as soon as
  /// [promoteGatedNames] had run: the promotion puts `seed_phrase`
  /// into `getGatedPrefs()` and throws away the ungated twin
  /// ([_dropUngated]). After that a `delete('seed_phrase')` hit an empty
  /// cache and an empty ungated storage — and left the 24 words standing
  /// behind the lock. For the first-start wipe
  /// (`FirstStartWipe.wipeKeyringSecrets`) that means: the deletion would
  /// have run and the seed would still have been there, i.e. the same
  /// finding one level deeper.
  ///
  /// The return value stays what it was — "was it in the cache?". Whether
  /// something lay behind the lock cannot be learned synchronously; the
  /// delete order goes out nevertheless. The caller who wants to count
  /// therefore counts conservatively too few, never too many.
  @override
  bool delete(String name) {
    final existed = _cache.containsKey(name);
    _cache.remove(name);
    _unpersisted.remove(name);
    unawaited(_forget(name));
    if (gatedNames.contains(name)) unawaited(_forgetGated(name));
    return existed;
  }

  /// The gated twin. Only built on Android — on iOS
  /// `KeyringHandler.swift` does not know `deleteGated` and answers with
  /// `MissingPluginException`; the `catch` catches that and leaves
  /// [_bridgeHealthy] explicitly untouched (there is no gated storage
  /// there, so nothing that would not have been deleted either).
  Future<void> _forgetGated(String name) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('deleteGated', {'name': name});
    } catch (e) {
      _log.warn('$_platformName gated keyring delete failed for "$name": $e');
    }
  }

  Future<void> _forget(String name) async {
    try {
      await _channel.invokeMethod('delete', {'name': name});
    } catch (e) {
      _log.warn('$_platformName keyring delete failed for "$name": $e');
      // The same reasoning as in [_persist]: if the bridge does not execute
      // a delete order, it does not execute a write order either, and the
      // next `store` must not claim success.
      _bridgeHealthy = false;
    }
  }

  // ── S363, point 1: the lock on the 24 words ────────────────────

  /// MEASURED, not assumed: the lock exists ONLY on Android.
  ///
  /// Its two carriers are
  /// `android/app/src/main/kotlin/chat/cleona/cleona/KeyringHandler.kt`
  /// (the second, auth-bound storage) and `MainActivity.kt` (the
  /// keyguard channel). On the Apple side there is no counterpart —
  /// `ios/Runner/KeyringHandler.swift` does not know `gateStatus`,
  /// `storeGated`, `loadGated` and `deleteGated`, and there is no channel
  /// `chat.cleona/keyguard` there either (re-measured
  /// 04.09.2026: zero occurrences in `ios/` and `macos/`).
  ///
  /// This class carries both platforms. A fixed `true` would therefore
  /// claim a lock on iOS that does not exist — with three consequences:
  /// `gateStatus()` ran into a `MissingPluginException` on every display
  /// (including a warning line), `IdentityManager
  /// .hasDeviceGate` reported `true`, and a hint text explaining the
  /// screen lock would have appeared on a device on which it has nothing
  /// to do with the storage.
  @override
  bool get hasGate => Platform.isAndroid;

  static GateOutcome _outcomeOf(String code) {
    switch (code) {
      case _gateReady:
      // IMPORTANT: `AUTH_REQUIRED` means "the lock stands and works, it
      // only wants a fresh confirmation" — NOT "there is no lock here".
      // Whoever maps that to `unavailable` makes
      // `IdentityManager.loadSeedPhraseGated` skip the lock and fetch the
      // words from the ungated twin: a silent mode change, and precisely
      // the one this package is meant to prevent.
      // `loadGated` fetches the confirmation itself.
      case _gateAuthRequired:
        return GateOutcome.ready;
      case _gateNoDeviceLock:
        return GateOutcome.noDeviceLock;
      case _gateInvalidated:
        return GateOutcome.invalidated;
      default:
        return GateOutcome.unavailable;
    }
  }

  @override
  Future<GateOutcome> gateStatus() async {
    try {
      // `gateStatus` on the Kotlin side checks `KeyguardManager
      // .isDeviceSecure` itself before it touches an auth-bound key — a
      // second query via the keyguard channel would be the same question
      // to the same place.
      final code = await _channel.invokeMethod<String>('gateStatus');
      return _outcomeOf(code ?? '');
    } catch (e) {
      _log.warn('$_platformName gate status failed: $e');
      return GateOutcome.unavailable;
    }
  }

  @override
  Future<GatedRead> loadGated(String name,
      {String? title, String? description}) async {
    // First attempt. If the time window of the auth-bound key is still
    // open (default 300 s since the last unlock), the value comes without
    // a dialog.
    var attempt = await _rawLoadGated(name);
    if (attempt.outcome != GateOutcome.cancelled) {
      if (attempt.outcome == GateOutcome.ready) _dropUngated(name);
      return attempt;
    }
    // `cancelled` stands here for AUTH_REQUIRED — the key demands a fresh
    // confirmation. Exactly for that the keyguard path exists.
    final confirmed = await _confirmDeviceCredential(title, description);
    if (!confirmed) return const GatedRead(null, GateOutcome.cancelled);
    attempt = await _rawLoadGated(name);
    if (attempt.outcome == GateOutcome.ready) _dropUngated(name);
    return attempt;
  }

  Future<GatedRead> _rawLoadGated(String name) async {
    try {
      final b64 = await _channel.invokeMethod<String>('loadGated', {'name': name});
      if (b64 == null) return const GatedRead(null, GateOutcome.absent);
      return GatedRead(base64Decode(b64), GateOutcome.ready);
    } on PlatformException catch (e) {
      if (e.code == _gateAuthRequired) {
        return const GatedRead(null, GateOutcome.cancelled);
      }
      _log.warn('$_platformName gated load "$name": ${e.code}');
      return GatedRead(null, _outcomeOf(e.code));
    } catch (e) {
      _log.warn('$_platformName gated load "$name" failed: $e');
      return const GatedRead(null, GateOutcome.unavailable);
    }
  }

  Future<bool> _confirmDeviceCredential(String? title, String? description) async {
    try {
      final ok = await _gateChannel.invokeMethod<bool>('confirmDeviceCredential', {
        'title': title,
        'description': description,
      });
      return ok == true;
    } catch (e) {
      _log.warn('$_platformName device-credential confirmation failed: $e');
      return false;
    }
  }

  /// The ungated twin of a gated name — in the cache AND on the native
  /// side. Is called ONLY after the gated entry has ACTUALLY been read;
  /// before that it would be throwing away the only copy.
  void _dropUngated(String name) {
    if (!_cache.containsKey(name)) return;
    _cache.remove(name);
    _unpersisted.remove(name);
    unawaited(_forget(name));
    _log.info('$_platformName keyring: "$name" now lives behind the device '
        'gate only — the ungated copy was removed after a verified read');
  }

  /// Moves the gated names from the ungated into the gated storage, if
  /// that works WITHOUT a user dialog.
  ///
  /// The order is that of stage 1 (proposal 3.3, finding F-2):
  /// write, READ BACK, compare, and ONLY THEN remove the old copy. The
  /// read-back step needs the same auth state as the write step and
  /// therefore falls into the same open time window; if it does not work
  /// out, the ungated entry stays and the next start tries again. There is
  /// NEVER a prompt here — a dialog at program start would be an
  /// imposition, and moreover one the user cannot place.
  @override
  Future<void> promoteGatedNames() async {
    // S372, channel 3: without this line `gateStatus()` unconditionally
    // calls `chat.cleona/keyring.gateStatus` — on iOS the method does not
    // exist on the native side (`KeyringHandler.swift` knows only store/
    // load/delete/loadAll), so every start throws a
    // MissingPluginException that is only logged and discarded here.
    // `hasGate` is already the established predicate for this in the
    // project (`identity_manager.dart:576` checks it before exactly the
    // same call).
    if (!hasGate) return;
    if (await gateStatus() != GateOutcome.ready) return;
    for (final name in gatedNames) {
      try {
        final existing = await _rawLoadGated(name);
        if (existing.outcome == GateOutcome.ready) {
          _dropUngated(name);
          continue;
        }
        if (existing.outcome != GateOutcome.absent) continue; // z.B. AUTH_REQUIRED
        final plain = _cache[name];
        if (plain == null) continue;
        if (!await _rawStoreGated(name, plain)) continue;
        final back = await _rawLoadGated(name);
        if (back.outcome != GateOutcome.ready || back.value == null) {
          _log.warn('$_platformName gate: wrote "$name" but could not read it '
              'back — keeping the ungated copy');
          continue;
        }
        if (!_sameBytes(back.value!, plain)) {
          _log.warn('$_platformName gate: "$name" read back as '
              '${back.value!.length} B instead of ${plain.length} B — '
              'keeping the ungated copy');
          continue;
        }
        _dropUngated(name);
      } catch (e) {
        _log.warn('$_platformName gate: promotion of "$name" failed: $e');
      }
    }
  }

  Future<bool> _rawStoreGated(String name, Uint8List data) async {
    try {
      final ok = await _channel.invokeMethod<bool>(
          'storeGated', {'name': name, 'data': base64Encode(data)});
      return ok == true;
    } on PlatformException catch (e) {
      _log.warn('$_platformName gated store "$name": ${e.code}');
      return false;
    } catch (e) {
      _log.warn('$_platformName gated store "$name" failed: $e');
      return false;
    }
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
