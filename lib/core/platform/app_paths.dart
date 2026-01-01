import 'dart:io';

/// Central path resolution for Cleona data directory.
/// On Linux/macOS: $HOME/.cleona
/// On Windows: %USERPROFILE%\.cleona
/// On Android: /data/data/`packageName`/files/.cleona (app-private)
///
/// macOS uses $HOME/.cleona (not Application Support) for consistency with
/// the many direct `$home/.cleona` references across main.dart / service_daemon.dart /
/// service_daemon.dart. A later refactor could adopt the Apple convention if
/// all call sites are migrated to AppPaths.dataDir.
/// Resolves the home directory under Windows — or fails loudly.
///
/// ── THE FINDING THAT CHANGED THIS (13b, S370, 06.09.2026) ─────────
///
/// Here stood
///
///     _cachedHome = Platform.environment['USERPROFILE'] ??
///         Platform.environment['APPDATA'] ?? 'C:\\Users\\Public';
///
/// If both variables were not set, the ENTIRE profile landed in
/// `C:\Users\Public` — `db.key`, `master_seed.dpapi`,
/// `master_seed.json.enc`, `seed_phrase.json.enc`, `node_keys.enc` and the
/// `cleona.port` with the IPC token. Measured on 06.09.2026 on the build VM:
///
///   > icacls C:\Users\Public
///     `NT-AUTORITAET\INTERAKTIV:(OI)(CI)(IO)(M,DC)`
///     `NT-AUTORITAET\DIENST:(OI)(CI)(IO)(M,DC)`
///     `NT-AUTORITAET\BATCH:(OI)(CI)(IO)(M,DC)`
///
/// "(OI)(CI)" means: inherited by files and subfolders. Every interactively
/// logged-on user of this machine could have read AND changed the key files.
///
/// The case is unlikely — but a SILENT fallback to a
/// commonly writable directory is the wrong direction: it
/// trades a loud, immediately visible start error for an
/// invisible key leak. That is why it now fails closed.
///
/// [appData] remains as second choice (existing behaviour, so that
/// existing profiles do not move); only the third stage is gone.
String resolveWindowsHome({String? userProfile, String? appData}) {
  final chosen = (userProfile != null && userProfile.isNotEmpty)
      ? userProfile
      : (appData != null && appData.isNotEmpty)
          ? appData
          : null;
  if (chosen == null) {
    throw StateError(
        'Neither USERPROFILE nor APPDATA is set — the home directory '
        'cannot be determined. Cleona aborts here instead of putting profile and '
        'keys into a commonly writable directory '
        '(until S370 that was C:\\Users\\Public, on which every interactively '
        'logged-in user has modify rights).');
  }
  return chosen;
}

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
  /// On iOS, HOME is not set — resolve via the executable path.
  static String get home {
    if (_cachedHome != null) return _cachedHome!;

    if (Platform.isAndroid) {
      _cachedHome = '/data/data/$packageName/files';
    } else if (Platform.isIOS) {
      final env = Platform.environment['HOME'];
      if (env != null && env != '/tmp') {
        _cachedHome = env;
      } else {
        // HOME not set on iOS. Derive container root from executable path:
        // /private/var/.../Runner.app/Runner → /private/var/.../
        final exe = Platform.resolvedExecutable;
        final appIdx = exe.lastIndexOf('.app/');
        if (appIdx > 0) {
          final bundlePath = exe.substring(0, appIdx);
          final slash = bundlePath.lastIndexOf('/');
          _cachedHome = slash > 0 ? bundlePath.substring(0, slash) : bundlePath;
        } else {
          _cachedHome = '/tmp';
        }
      }
    } else if (Platform.isWindows) {
      _cachedHome = resolveWindowsHome(
        userProfile: Platform.environment['USERPROFILE'],
        appData: Platform.environment['APPDATA'],
      );
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

  // ══════════════════════════════════════════════════════════════════
  // BUNDLE LAYOUT — the ONLY place that knows it (S367)
  // ══════════════════════════════════════════════════════════════════
  //
  // WHY THIS SECTION EXISTS.
  //
  // Since the storage (§21.4.1) hangs on a code asset, the daemon is
  // built with `dart build cli`. This tool embeds the path to the
  // library as `../lib/libsqlite3.so` into the binary, namely
  // **relative to the executable** — not to the
  // working directory. Measured on 05.09.2026 with `strings` on the
  // binary and in a run attempt:
  //
  //     Failed to load dynamic library '../lib/libsqlite3.so' relative
  //     to '/tmp/clprobe/layoutB/cleona-daemon': … /tmp/clprobe/lib/
  //     libsqlite3.so: cannot open shared object file
  //
  // `LD_LIBRARY_PATH`, the working directory and an `RPATH $ORIGIN/`
  // are all ineffective against this. In return the tool assures a
  // layout: `bundle/bin/<exe>` next to `bundle/lib/<libs>`. Whoever takes the
  // binary out of `bin/` and puts it into the bundle root
  // makes `../lib/` point one level too high — and the daemon
  // **then terminates with exit 0** (`service_daemon.dart` catches the
  // start error, logs it and calls `shutdownAll()`). For the
  // GUI that is indistinguishable from "running, just does not open a
  // socket".
  //
  // THE DECISION: the tool's layout is adopted, not
  // fought. The daemon stays in `bin/`. Thus the same form applies on all
  // desktop platforms:
  //
  //     <bundleDir>/            <- GUI binary (cleona[.exe])
  //     <bundleDir>/bin/        <- daemon binary (cleona-daemon[.exe])
  //     <bundleDir>/lib/        <- native libraries of both
  //
  // [bundleDir] is thus on EVERY platform the directory of the
  // GUI binary — exactly what the `File(Platform.resolvedExecutable).parent.path`
  // formerly written out at ~20 places already was
  // for the GUI. For the GUI nothing changes; for the
  // daemon it points one level higher than its own directory, and
  // exactly that was the error.

  /// Root of the shipped bundle, derived from the running
  /// executable.
  ///
  /// Not cached: `Platform.resolvedExecutable` is constant during a
  /// process lifetime, and a cache would only be one more
  /// place that would have to be reset in tests.
  static String get bundleDir => bundleDirOf(Platform.resolvedExecutable);

  /// Pure form of [bundleDir] for an arbitrary program path.
  ///
  /// Separate, because two callers bring a FOREIGN path along —
  /// `BinaryUpdateManager.applyDesktopUpdate` and `.rollback` get
  /// it as a parameter — and because a pure function is testable
  /// without building a daemon.
  ///
  /// Rule: if the file lies in a directory named `bin`, the
  /// bundle root is its parent directory; otherwise the directory
  /// itself. `bin` is not a guessed name — it is the one that
  /// `dart build cli` produces.
  static String bundleDirOf(String exePath) {
    // Allow both separators: under Windows mixed paths occur
    // (Dart delivers `\`, our scripts write `/` in places).
    final norm = exePath.replaceAll('\\', '/');
    final lastSlash = norm.lastIndexOf('/');
    if (lastSlash < 0) return '.';
    if (lastSlash == 0) return _denorm('/');
    final dir = norm.substring(0, lastSlash);
    final prevSlash = dir.lastIndexOf('/');
    final dirName = prevSlash >= 0 ? dir.substring(prevSlash + 1) : dir;
    if (dirName != 'bin') return _denorm(dir);
    // `/bin/x` and `C:/bin/x` must not shrink to '' or 'C:' —
    // an empty or bare drive specifier would not be a directory.
    if (prevSlash <= 0) return _denorm(dir);
    final parent = dir.substring(0, prevSlash);
    if (parent.isEmpty || RegExp(r'^[A-Za-z]:$').hasMatch(parent)) {
      return _denorm(dir);
    }
    return _denorm(parent);
  }

  static String _denorm(String p) =>
      Platform.isWindows ? p.replaceAll('/', '\\') : p;

  /// Directory of the native libraries in the bundle: `<bundleDir>/lib`.
  static String get bundleLibDir =>
      '$bundleDir${Platform.pathSeparator}lib';

  /// macOS: `Contents/Frameworks` of the running `.app`.
  ///
  /// Replaces `@executable_path/../Frameworks`. The difference is exactly
  /// the daemon: `@executable_path` is ITS directory, and that has been
  /// `Contents/MacOS/bin` since S367 — `../Frameworks` pointed from there to
  /// `Contents/MacOS/Frameworks`, which does not exist. Computed via [bundleDir]
  /// the path is right for GUI and daemon alike.
  static String get macFrameworksDir {
    final sep = Platform.pathSeparator;
    return '$bundleDir$sep..${sep}Frameworks';
  }

  /// File name of the daemon binary on this platform.
  static String get daemonBinaryName =>
      Platform.isWindows ? 'cleona-daemon.exe' : 'cleona-daemon';

  /// File name of the GUI binary on this platform.
  static String get guiBinaryName =>
      Platform.isWindows ? 'cleona.exe' : 'cleona';

  /// Canonical location of the daemon in the bundle: `<bundleDir>/bin/cleona-daemon`.
  static String daemonPathIn(String bundleRoot) {
    final sep = Platform.pathSeparator;
    return '$bundleRoot${sep}bin$sep$daemonBinaryName';
  }
}
