import 'dart:io';

/// Central path resolution for Cleona data directory.
/// On Linux/macOS: $HOME/.cleona
/// On Windows: %APPDATA%\.cleona
/// On Android: /data/data/`packageName`/files/.cleona (app-private)
///
/// macOS uses $HOME/.cleona (not Application Support) for consistency with
/// the many direct `$home/.cleona` references across main.dart / headless.dart /
/// service_daemon.dart. A later refactor could adopt the Apple convention if
/// all call sites are migrated to AppPaths.dataDir.
class AppPaths {
  static String? _cachedHome;
  static String? _cachedDataDir;
  static String? _androidPackage;

  /// Resolve the Android package name from /proc/self/cmdline.
  static String get packageName {
    if (_androidPackage != null) return _androidPackage!;
    try {
      final cmdline = File('/proc/self/cmdline').readAsBytesSync();
      // cmdline is null-terminated; package name is the first segment
      final end = cmdline.indexOf(0);
      _androidPackage = String.fromCharCodes(
        end > 0 ? cmdline.sublist(0, end) : cmdline,
      );
    } catch (_) {
      _androidPackage = 'chat.cleona.cleona';
    }
    return _androidPackage!;
  }

  /// Get the home directory equivalent for the current platform.
  /// On Android, returns the app's internal files directory.
  static String get home {
    if (_cachedHome != null) return _cachedHome!;

    if (Platform.isAndroid) {
      _cachedHome = '/data/data/$packageName/files';
    } else if (Platform.isWindows) {
      _cachedHome = Platform.environment['APPDATA'] ??
          Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Public';
    } else {
      _cachedHome = Platform.environment['HOME'] ?? '/tmp';
    }
    return _cachedHome!;
  }

  /// Override the home directory (useful for tests or when path_provider is available).
  static void setHome(String path) {
    _cachedHome = path;
    _cachedDataDir = null;
  }

  /// Override the data dir directly (e.g. when path_provider resolves
  /// Application Support on macOS/iOS).
  static void setDataDir(String path) {
    _cachedDataDir = path;
  }

  /// The .cleona data directory.
  static String get dataDir =>
      _cachedDataDir ?? '$home${Platform.pathSeparator}.cleona';

  /// Temp directory (platform-aware).
  static String get tempDir {
    if (Platform.isAndroid) {
      return '/data/data/$packageName/cache';
    }
    if (Platform.isWindows) {
      return Platform.environment['TEMP'] ?? Directory.systemTemp.path;
    }
    if (Platform.isMacOS) {
      return Platform.environment['TMPDIR'] ?? Directory.systemTemp.path;
    }
    return '/tmp';
  }
}
