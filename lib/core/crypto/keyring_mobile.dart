import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:cleona/core/crypto/keyring_service.dart';
import 'package:cleona/core/network/clogger.dart';

/// §3.7 Mobile OS Keyring via MethodChannel (shared protocol).
///
/// Android: EncryptedSharedPreferences backed by AndroidKeyStore.
/// iOS: Keychain Services (kSecClassGenericPassword).
///
/// Preloads all stored keys into an in-memory cache during [init] (async).
/// Subsequent [load] calls return from cache (sync). [store]/[delete] update
/// the cache immediately and persist to the native side asynchronously.
class MobileKeyringService extends KeyringService {
  static const _channel = MethodChannel('chat.cleona/keyring');
  final Map<String, Uint8List> _cache = {};
  final CLogger _log;
  final String _platformName;

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
      log.info('$platform keyring: preloaded ${service._cache.length} keys');
      KeyringService.registerInstance(service);
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

  @override
  bool get isHardwareProtected => true;

  @override
  bool store(String name, Uint8List data) {
    _cache[name] = Uint8List.fromList(data);
    _channel.invokeMethod('store', {
      'name': name,
      'data': base64Encode(data),
    }).catchError((e) {
      _log.warn('$_platformName keyring persist failed for "$name": $e');
      return null;
    });
    return true;
  }

  @override
  Uint8List? load(String name) => _cache[name];

  @override
  bool delete(String name) {
    final existed = _cache.containsKey(name);
    _cache.remove(name);
    _channel.invokeMethod('delete', {'name': name}).catchError((e) {
      _log.warn('$_platformName keyring delete failed for "$name": $e');
      return null;
    });
    return existed;
  }
}
