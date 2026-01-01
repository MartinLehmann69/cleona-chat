import 'dart:io';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/platform/app_paths.dart';

/// Where the running APK was installed from.
enum InstallSource {
  playStore,
  sideload,
  unknown, // non-Android platforms
}

/// Determines whether the running Android build was installed from the
/// Google Play Store or sideloaded (direct APK, F-Droid, file manager,
/// browser download, ...), for update routing (Architecture §19.6.4):
/// Play Store builds must never self-update via in-network binary
/// distribution (Play Store policy forbids self-updating apps), while
/// sideloaded builds are the primary target for censorship-resistant
/// update delivery.
///
/// Resolution order:
/// 1. Build-time override `--dart-define=INSTALL_SOURCE=playstore|sideload`
///    (used for CI builds where the distribution channel is known upfront).
/// 2. Cached result from a previous [detect] call, persisted to
///    `install_source.txt` in the app's data directory.
/// 3. Live query of the installer package name via `pm dump <package>` —
///    `com.android.vending` means Play Store, anything else (null,
///    sideload installer, file manager) means sideload.
///
/// Detection failures fail safe towards [InstallSource.playStore], i.e.
/// towards *disabling* self-update, rather than risking a Play Store policy
/// violation on a misdetected install.
class InstallSourceDetector {
  static const _kStorageKey = 'install_source_v2';

  static const _buildTimeOverride =
      String.fromEnvironment('INSTALL_SOURCE', defaultValue: 'auto');

  static InstallSource? _cached;

  static final CLogger _log = CLogger('InstallSourceDetector');

  /// Detect the install source. On non-Android platforms, always returns
  /// [InstallSource.unknown]. The result is determined once (build-time
  /// override, disk cache, or a live `pm` query) and then cached both in
  /// memory and on disk for subsequent calls/launches.
  static Future<InstallSource> detect() async {
    if (_cached != null) return _cached!;

    if (!Platform.isAndroid) {
      return _cached = InstallSource.unknown;
    }

    if (_buildTimeOverride != 'auto') {
      final source = _buildTimeOverride == 'sideload'
          ? InstallSource.sideload
          : InstallSource.playStore;
      _persist(source);
      return _cached = source;
    }

    final restored = _readCacheFile();
    if (restored != null) {
      return _cached = restored;
    }

    final detected = await _detectViaPackageManager();
    _persist(detected);
    return _cached = detected;
  }

  /// The cached install source (synchronous, for use in update checks).
  /// Returns null if [detect] hasn't been called yet in this process.
  static InstallSource? get cached => _cached;

  static File get _cacheFile =>
      File('${AppPaths.dataDir}/$_kStorageKey.txt');

  static InstallSource? _readCacheFile() {
    try {
      final file = _cacheFile;
      if (!file.existsSync()) return null;
      return _fromStorageString(file.readAsStringSync().trim());
    } catch (e) {
      _log.warn('Failed to read cached install source: $e');
      return null;
    }
  }

  /// Supplies Android's `installerPackageName`. Injected by the Flutter app
  /// layer (`main.dart`) — deliberately NOT implemented here.
  ///
  /// S299: this used to be a direct `MethodChannel` call, which pulled
  /// `package:flutter/services.dart` into `lib/core`. Because
  /// `cleona_service.dart` reaches this file, the whole Flutter tree — and
  /// with it `dart:ui` — landed in the dependency graph of the **daemon**,
  /// which is a pure-Dart AOT binary (`dart compile exe`). The consequence
  /// was not a degraded feature but a hard build failure: the daemon could
  /// not be compiled at all, and ten standalone smoke files died with
  /// "Dart library 'dart:ui' is not available on this platform".
  ///
  /// Keeping the platform call on the app side preserves the invariant that
  /// `lib/core` is Flutter-free. When the hook is unset — daemon, tests,
  /// every non-Android platform — detection falls back to `sideload`, which
  /// is the same answer the old `MissingPluginException` branch produced.
  static Future<String?> Function()? installerPackageNameProvider;

  static Future<InstallSource> _detectViaPackageManager() async {
    final provider = installerPackageNameProvider;
    if (provider == null) {
      _log.info('Install source: no platform provider registered '
          '(daemon mode), assuming sideload');
      return InstallSource.sideload;
    }
    try {
      final installer = await provider();
      _log.info('Install source: installerPackageName=$installer');
      if (installer == null || installer.isEmpty) return InstallSource.sideload;
      return installer == 'com.android.vending'
          ? InstallSource.playStore
          : InstallSource.sideload;
    } catch (e) {
      _log.warn('Install source detection failed: $e');
      return InstallSource.sideload;
    }
  }

  static void _persist(InstallSource source) {
    try {
      final file = _cacheFile;
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(_toStorageString(source));
    } catch (e) {
      _log.warn('Failed to persist install source: $e');
    }
  }

  static String _toStorageString(InstallSource source) => switch (source) {
        InstallSource.playStore => 'playstore',
        InstallSource.sideload => 'sideload',
        InstallSource.unknown => 'unknown',
      };

  static InstallSource? _fromStorageString(String s) => switch (s) {
        'playstore' => InstallSource.playStore,
        'sideload' => InstallSource.sideload,
        'unknown' => InstallSource.unknown,
        _ => null,
      };
}
