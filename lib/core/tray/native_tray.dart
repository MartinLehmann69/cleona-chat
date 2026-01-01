import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:cleona/core/config/network_channel.dart';
import 'package:cleona/core/service/readiness_names.dart';
import 'package:cleona/core/tray/native_tray_windows.dart';
import 'package:cleona/core/tray/tray_status.dart';

// ── GTK type aliases ─────────────────────────────────────────────────

typedef _GtkInitCheckC = Int32 Function(Pointer<Int32>, Pointer<Pointer<Pointer<Utf8>>>);
typedef _GtkInitCheckDart = int Function(Pointer<Int32>, Pointer<Pointer<Pointer<Utf8>>>);

typedef _GtkMenuNewC = Pointer Function();
typedef _GtkMenuNewDart = Pointer Function();

typedef _GtkMenuItemNewC = Pointer Function(Pointer<Utf8>);
typedef _GtkMenuItemNewDart = Pointer Function(Pointer<Utf8>);

typedef _GtkSeparatorMenuItemNewC = Pointer Function();
typedef _GtkSeparatorMenuItemNewDart = Pointer Function();

typedef _GtkMenuShellAppendC = Void Function(Pointer, Pointer);
typedef _GtkMenuShellAppendDart = void Function(Pointer, Pointer);

typedef _GtkWidgetShowAllC = Void Function(Pointer);
typedef _GtkWidgetShowAllDart = void Function(Pointer);

// For the state line in the menu: it is a menu item, but not a
// button. `gtk_widget_set_sensitive(item, FALSE)` greys it out and takes
// its click away — otherwise the line would look like a command that does nothing.
typedef _GtkWidgetSetSensitiveC = Void Function(Pointer, Int32);
typedef _GtkWidgetSetSensitiveDart = void Function(Pointer, int);

typedef _GMainContextIterationC = Int32 Function(Pointer, Int32);
typedef _GMainContextIterationDart = int Function(Pointer, int);

typedef _GSignalConnectC = Uint64 Function(
    Pointer, Pointer<Utf8>, Pointer, Pointer);
typedef _GSignalConnectDart = int Function(
    Pointer, Pointer<Utf8>, Pointer, Pointer);

typedef _AppIndicatorNewC = Pointer Function(Pointer<Utf8>, Pointer<Utf8>, Int32);
typedef _AppIndicatorNewDart = Pointer Function(Pointer<Utf8>, Pointer<Utf8>, int);

typedef _AppIndicatorSetStatusC = Void Function(Pointer, Int32);
typedef _AppIndicatorSetStatusDart = void Function(Pointer, int);

typedef _AppIndicatorSetMenuC = Void Function(Pointer, Pointer);
typedef _AppIndicatorSetMenuDart = void Function(Pointer, Pointer);

typedef _AppIndicatorSetIconFullC = Void Function(Pointer, Pointer<Utf8>, Pointer<Utf8>);
typedef _AppIndicatorSetIconFullDart = void Function(Pointer, Pointer<Utf8>, Pointer<Utf8>);

typedef _AppIndicatorSetIconThemePathC = Void Function(Pointer, Pointer<Utf8>);
typedef _AppIndicatorSetIconThemePathDart = void Function(Pointer, Pointer<Utf8>);

typedef _AppIndicatorSetTitleC = Void Function(Pointer, Pointer<Utf8>);
typedef _AppIndicatorSetTitleDart = void Function(Pointer, Pointer<Utf8>);

// ── Static signal callbacks (Pointer.fromFunction compatible) ────────
// Each sets a flag that processEvents() picks up on the Dart event loop.

bool _pendingShow = false;
bool _pendingStop = false;
bool _pendingStart = false;
bool _pendingQuit = false;

void _onShowActivated(Pointer widget, Pointer data) { _pendingShow = true; }
void _onStopActivated(Pointer widget, Pointer data) { _pendingStop = true; }
void _onStartActivated(Pointer widget, Pointer data) { _pendingStart = true; }
void _onQuitActivated(Pointer widget, Pointer data) { _pendingQuit = true; }

/// The state line is greyed out and therefore never gets an
/// `activate` — the callback only exists because `g_signal_connect_data`
/// accepts no null pointer.
void _onNoop(Pointer widget, Pointer data) {}

/// Native system tray icon for the daemon process.
/// Linux: GTK3 + libappindicator3 via FFI.
/// Windows: Win32 Shell_NotifyIcon via FFI.
class NativeTray {
  Pointer? _indicator;
  Pointer? _currentMenu;
  Timer? _gtkPumpTimer;
  bool _initialized = false;
  Directory? _tmpIconDir;

  // GTK cleanup functions (loaded lazily during init)
  void Function(Pointer)? _gObjectUnref;
  void Function(Pointer)? _gtkWidgetDestroy;
  NativeTrayWindows? _windowsTray;

  // Callbacks
  void Function()? onShowWindow;
  void Function()? onStop;
  void Function()? onStart;
  void Function()? onQuit;

  // GTK function pointers (stored for menu rebuilds)
  late _GtkMenuNewDart _gtkMenuNew;
  late _GtkMenuItemNewDart _gtkMenuItemNew;
  late _GtkSeparatorMenuItemNewDart _gtkSeparatorNew;
  late _GtkMenuShellAppendDart _gtkMenuShellAppend;
  late _GtkWidgetShowAllDart _gtkWidgetShowAll;
  late _GMainContextIterationDart _gMainContextIteration;
  late _GSignalConnectDart _gSignalConnect;
  late _AppIndicatorSetMenuDart _appIndicatorSetMenu;
  late _AppIndicatorSetTitleDart _appIndicatorSetTitle;
  late _GtkWidgetSetSensitiveDart _gtkWidgetSetSensitive;
  _AppIndicatorSetIconFullDart? _appIndicatorSetIconFull;

  /// Last passed state — THE observable seam (§22.9).
  ///
  /// It is set in [updateStatus] BEFORE `_initialized` is
  /// checked. Reason: "what the tray should display" is a true statement
  /// even when there is no notification area at all (headless
  /// run, missing libappindicator, Windows service account) — and only thus
  /// can it be checked WITHOUT GTK that a readiness change reaches the
  /// tray. A guard that instead only measures the existence of the
  /// method measures a proxy.
  TrayStatus? lastState;

  /// Language of the tray texts. Default: that of the operating system.
  /// Overridable, so that the guard can check all 34 locales.
  String localeCode = trayLocaleCode();

  /// The GUI has reported its language (owner decision V-10-a = b,
  /// 09.09.2026).
  ///
  /// ── WHY THE TRAY CANNOT LOOK IT UP ITSELF ───────────────────────
  ///
  /// `AppLocale` stores the chosen language in `SharedPreferences`
  /// (`app_locale.dart:_prefsKey`) — a Flutter plugin that does not exist in the
  /// daemon. What the daemon has by itself is
  /// `Platform.localeName`, i.e. the language of the OPERATING SYSTEM. Whoever
  /// switched in the GUI kept reading the tray in English until S377.
  ///
  /// Opening the plugin storage location in the daemon would be a workaround
  /// (working rule 1): platform-dependent path, implementation detail
  /// of a package. Instead the GUI reports the language via a field
  /// on the existing IPC traffic; here it arrives.
  ///
  /// ── THE ACCEPTED LIMIT, and it belongs here ──────────────────
  ///
  /// Until the first GUI start the tray stays on the system language — on
  /// a server without GUI permanently. That is the price of the variant and
  /// no gap that still needs closing: a daemon without GUI has
  /// nobody who would have chosen a language.
  void setLocale(String code) {
    if (code == localeCode) return;
    // The value comes via IPC from another process. What the tray
    // does not know, it does not set — otherwise the state text would show the
    // key name (`trayTranslate` falls back to it at the end).
    if (!isTrayLanguage(code)) return;
    localeCode = code;
    // The icon carries the state description along as text; without this
    // reset it would stay in the old language, because
    // [_symbolSetzen] aborts on the same name.
    _setSymbol = null;
    final state = lastState;
    if (state == null || !_initialized) return;
    if (_windowsTray != null) {
      _windowsTray!.updateStatus(state, _basisName, localeCode);
      return;
    }
    _rebuildMenu(state);
  }

  /// Icon name per readiness state, provided the image was found in the
  /// bundle. Empty means: it stays with the base icon (fail-safe,
  /// see [_stateSymbolsPrepare]).
  final Map<String, String> _stateSymbols = {};
  String? _basisSymbolName;
  String? _setSymbol;

  /// The display name without counter and without state.
  String _basisName = 'Cleona Chat';

  bool init({
    required String iconPath,
    String tooltip = 'Cleona Chat',
    void Function(String level, String msg)? logger,
  }) {
    void logI(String m) => (logger ?? (_, _) {})('info', 'Tray: $m');
    void logW(String m) => (logger ?? (_, _) {})('warn', 'Tray: $m');
    if (_initialized) return true;

    // Windows: delegate to Win32 implementation
    if (Platform.isWindows) {
      _windowsTray = NativeTrayWindows();
      _windowsTray!.onShowWindow = () => onShowWindow?.call();
      _windowsTray!.onStop = () => onStop?.call();
      _windowsTray!.onStart = () => onStart?.call();
      _windowsTray!.onQuit = () => onQuit?.call();
      // Pass `logger` through (S370): without it the reason
      // of a failed `Shell_NotifyIcon` disappeared — the only place at which
      // "no icon" can be explained at all.
      _basisName = tooltip;
      _initialized = _windowsTray!
          .init(iconPath: iconPath, tooltip: tooltip, logger: logger);
      if (_initialized) {
        // The start state, so that the tooltip does not stay empty until the first
        // state report.
        updateStatus(kTrayStartState);
      }
      if (!_initialized) {
        logW('Windows notification area did not accept the icon — '
            'the daemon runs without tray.');
      }
      return _initialized;
    }

    // macOS: no daemon-side tray in v1. See original comment.
    if (Platform.isMacOS) {
      return false;
    }

    // Linux: log display context up-front — StatusNotifierItem on GNOME/KDE
    // needs GTK to bind to a DISPLAY or WAYLAND_DISPLAY. If neither is set
    // (no-display/tty session) gtk_init_check returns 0 and app_indicator_new
    // still produces a non-null handle but never registers on DBus → tray
    // invisible while daemon log claims "OK". See gui-46.02.
    final dispX = Platform.environment['DISPLAY'] ?? '';
    final dispW = Platform.environment['WAYLAND_DISPLAY'] ?? '';
    final xdgBus = Platform.environment['DBUS_SESSION_BUS_ADDRESS'] ?? '';
    logI('env DISPLAY="$dispX" WAYLAND_DISPLAY="$dispW" '
        'DBUS_SESSION_BUS_ADDRESS=${xdgBus.isEmpty ? "MISSING" : "set"}');
    if (dispX.isEmpty && dispW.isEmpty) {
      logW('no DISPLAY/WAYLAND_DISPLAY — GTK cannot bind a backend, '
          'StatusNotifierItem will NOT register. Start daemon from a graphical '
          'session or export DISPLAY=:0 before launch.');
    }

    try {
      final gtk = DynamicLibrary.open('libgtk-3.so.0');
      final glib = DynamicLibrary.open('libglib-2.0.so.0');
      final gobject = DynamicLibrary.open('libgobject-2.0.so.0');

      // Fallback chain: Ayatana (Ubuntu/Debian modern) → legacy SONAME-1 →
      // legacy unversioned. On Fedora/Arch the older name can still show up.
      DynamicLibrary? appindicatorLib;
      String? loadedLibName;
      for (final name in const [
        'libayatana-appindicator3.so.1',
        'libappindicator3.so.1',
        'libappindicator3.so',
      ]) {
        try {
          appindicatorLib = DynamicLibrary.open(name);
          loadedLibName = name;
          break;
        } catch (e) {
          logI('DynamicLibrary.open("$name") failed: $e');
        }
      }
      if (appindicatorLib == null) {
        logW('no appindicator library found — install libayatana-appindicator3-1 '
            '(or gnome-shell-extension-appindicator on GNOME)');
        return false;
      }
      logI('loaded $loadedLibName');

      final gtkInitCheck = gtk.lookupFunction<_GtkInitCheckC, _GtkInitCheckDart>('gtk_init_check');
      _gtkMenuNew = gtk.lookupFunction<_GtkMenuNewC, _GtkMenuNewDart>('gtk_menu_new');
      _gtkMenuItemNew = gtk.lookupFunction<_GtkMenuItemNewC, _GtkMenuItemNewDart>(
          'gtk_menu_item_new_with_label');
      _gtkSeparatorNew = gtk.lookupFunction<_GtkSeparatorMenuItemNewC, _GtkSeparatorMenuItemNewDart>(
          'gtk_separator_menu_item_new');
      _gtkMenuShellAppend = gtk.lookupFunction<_GtkMenuShellAppendC, _GtkMenuShellAppendDart>(
          'gtk_menu_shell_append');
      _gtkWidgetShowAll = gtk.lookupFunction<_GtkWidgetShowAllC, _GtkWidgetShowAllDart>(
          'gtk_widget_show_all');
      _gtkWidgetSetSensitive =
          gtk.lookupFunction<_GtkWidgetSetSensitiveC, _GtkWidgetSetSensitiveDart>(
              'gtk_widget_set_sensitive');
      _gMainContextIteration = glib.lookupFunction<_GMainContextIterationC, _GMainContextIterationDart>(
          'g_main_context_iteration');
      _gSignalConnect = gobject.lookupFunction<_GSignalConnectC, _GSignalConnectDart>(
          'g_signal_connect_data');
      _gObjectUnref = gobject.lookupFunction<Void Function(Pointer), void Function(Pointer)>(
          'g_object_unref');
      _gtkWidgetDestroy = gtk.lookupFunction<Void Function(Pointer), void Function(Pointer)>(
          'gtk_widget_destroy');

      final appIndicatorNew = appindicatorLib.lookupFunction<_AppIndicatorNewC, _AppIndicatorNewDart>(
          'app_indicator_new');
      final appIndicatorSetStatus =
          appindicatorLib.lookupFunction<_AppIndicatorSetStatusC, _AppIndicatorSetStatusDart>(
              'app_indicator_set_status');
      _appIndicatorSetMenu =
          appindicatorLib.lookupFunction<_AppIndicatorSetMenuC, _AppIndicatorSetMenuDart>(
              'app_indicator_set_menu');
      final appIndicatorSetIconFull =
          appindicatorLib.lookupFunction<_AppIndicatorSetIconFullC, _AppIndicatorSetIconFullDart>(
              'app_indicator_set_icon_full');
      // Remembered, because the icon changes at EVERY state change and
      // is not only set once at start (§22.9).
      _appIndicatorSetIconFull = appIndicatorSetIconFull;
      final appIndicatorSetIconThemePath =
          appindicatorLib.lookupFunction<_AppIndicatorSetIconThemePathC, _AppIndicatorSetIconThemePathDart>(
              'app_indicator_set_icon_theme_path');
      _appIndicatorSetTitle =
          appindicatorLib.lookupFunction<_AppIndicatorSetTitleC, _AppIndicatorSetTitleDart>(
              'app_indicator_set_title');

      final gtkOk = gtkInitCheck(nullptr, nullptr);
      logI('gtk_init_check → ${gtkOk != 0 ? "OK" : "FAILED (no display backend)"}');
      if (gtkOk == 0) {
        // Without GTK, app_indicator_new would still return non-null but never
        // bind to DBus — bail out so the daemon logs a truthful "FAILED".
        return false;
      }

      // AppIndicator expects icon theme name, not absolute path.
      // Copy icon to temp dir with PID-unique name to bust GNOME Shell's icon cache.
      final uniqueName = 'cleona_tray_$pid';
      final tmpDir = Directory.systemTemp.createTempSync('cleona_tray_');
      _tmpIconDir = tmpDir;
      File(iconPath).copySync('${tmpDir.path}/$uniqueName.png');
      final iconDir = tmpDir.path;
      final iconName = uniqueName;
      _basisSymbolName = uniqueName;
      _basisName = tooltip;
      _stateSymbolsPrepare(iconPath, tmpDir, logI, logW);

      final id = 'cleona-daemon'.toNativeUtf8();
      final iconNameNative = iconName.toNativeUtf8();
      _indicator = appIndicatorNew(id, iconNameNative, 1); // CATEGORY_COMMUNICATIONS
      calloc.free(id);
      calloc.free(iconNameNative);

      if (_indicator == null || _indicator == nullptr) {
        logW('app_indicator_new returned null — cannot create tray');
        return false;
      }
      logI('app_indicator_new OK (id=cleona-daemon, icon=$iconName)');

      // Set icon search directory
      final iconDirNative = iconDir.toNativeUtf8();
      appIndicatorSetIconThemePath(_indicator!, iconDirNative);
      calloc.free(iconDirNative);

      appIndicatorSetStatus(_indicator!, 1); // STATUS_ACTIVE

      final titleNative = tooltip.toNativeUtf8();
      _appIndicatorSetTitle(_indicator!, titleNative);
      calloc.free(titleNative);

      final iconDesc = 'Cleona Chat'.toNativeUtf8();
      final iconNameForFull = iconName.toNativeUtf8();
      appIndicatorSetIconFull(_indicator!, iconNameForFull, iconDesc);
      calloc.free(iconDesc);
      calloc.free(iconNameForFull);

      _rebuildMenu(kTrayStartState);

      _gtkPumpTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        while (_gMainContextIteration(nullptr, 0) != 0) {}
        processEvents();
      });

      _initialized = true;
      return true;
    } catch (e, st) {
      logW('init threw: $e\n$st');
      try { stderr.writeln('NativeTray init failed: $e'); } catch (_) {}
      return false;
    }
  }

  /// The readiness state to the notification area (§22.9).
  ///
  /// Replaces the earlier `updateMenu({serviceRunning, unreadCount})`.
  /// That was seam no. 6 of the S375 network audit: the tray knew a
  /// boolean and a number, and §22.9 requires the
  /// readiness state. The two old quantities now sit in
  /// [TrayStatus] — nothing is lost, something is added. Since
  /// S388 (E3 = A) [TrayStatus] carries no connection tier and no
  /// reachability mark any more.
  void updateStatus(TrayStatus status) {
    // BEFORE `_initialized`: see [letzterZustand].
    lastState = status;
    if (!_initialized) return;
    if (_windowsTray != null) {
      _windowsTray!.updateStatus(status, _basisName, localeCode);
      return;
    }
    _rebuildMenu(status);
  }

  /// Looks for the three state icons next to the base icon and puts them into
  /// the same theme directory.
  ///
  /// ── WHY FAIL-SAFE AND NOT MANDATORY ───────────────────────────────
  ///
  /// `app_indicator_set_icon_full` with a name for which no file lies in the
  /// theme directory makes the icon
  /// DISAPPEAR — without an error value, without a log. A tray that becomes invisible
  /// at a state change would be worse than one that does not show the
  /// state in the icon. Finding therefore happens in advance, and only
  /// what was actually copied is set later; the rest stays
  /// with the base icon and tells its state via title and menu.
  void _stateSymbolsPrepare(String iconPath, Directory tmpDir,
      void Function(String) logI, void Function(String) logW) {
    var found = 0;
    for (final state in kReadinessNames) {
      // The same search rule as the Windows branch, only with a different extension
      // (`native_tray_windows.dart:init`) — for that reason it stands in
      // `tray_status.dart` and not twice here.
      final path =
          readinessIconSiblingPath(iconPath, state, extension: 'png');
      if (path == null) return;
      final source = File(path);
      if (!source.existsSync()) continue;
      final target = 'cleona_tray_${pid}_$state';
      try {
        source.copySync('${tmpDir.path}/$target.png');
        _stateSymbols[state] = target;
        found++;
      } catch (e) {
        logW('State icon $path not copyable: $e');
      }
    }
    if (found == 0) {
      logW('none of the three state icons (conn_*.png) lies next to '
          '"$iconPath" — the tray stays at the base icon and shows the '
          'state only as text (§22.9).');
    } else {
      logI('State icons: $found of ${kReadinessNames.length}');
    }
  }

  void _symbolSet(String readiness) {
    final assign = _appIndicatorSetIconFull;
    if (assign == null || _indicator == null) return;
    final name = _stateSymbols[readiness] ?? _basisSymbolName;
    if (name == null || name == _setSymbol) return;
    _setSymbol = name;
    final n = name.toNativeUtf8();
    final description =
        trayTranslate(readinessKey(readiness), localeCode).toNativeUtf8();
    assign(_indicator!, n, description);
    calloc.free(n);
    calloc.free(description);
  }

  void _rebuildMenu(TrayStatus status) {
    lastState = status;

    // ── SYMBOL (three states, §22.9 / E3 = A) ─────────────────────────
    _symbolSet(status.readiness);

    // ── TITLE: name, counter, state ───────────────────────────────────
    final baseName = _basisName.isNotEmpty
        ? _basisName
        : (activeNetworkChannel == NetworkChannel.beta
            ? 'Cleona Beta'
            : 'Cleona Chat');
    final title = trayTitleText(baseName, status, localeCode);
    final titleNative = title.toNativeUtf8();
    _appIndicatorSetTitle(_indicator!, titleNative);
    calloc.free(titleNative);

    final menu = _gtkMenuNew();
    final sig = 'activate'.toNativeUtf8();

    // ── TEXT (owner decision V-10 = A, 08.09.2026) ───────────────
    //
    // "Icon AND text, not only a coloured icon." The line stands
    // AT THE VERY TOP and is the only reason for which this menu could have helped in S373
    // and S374: it says whether the node can deliver.
    // It is greyed out — information, not a command.
    _addItem(menu, trayStatusText(status, localeCode), sig,
        Pointer.fromFunction<Void Function(Pointer, Pointer)>(_onNoop),
        enabled: false);

    // ── EACH IDENTITY INDIVIDUALLY (V-10-c = b, 09.09.2026) ──────────────
    //
    // The line above says "Bereit 2/3". Without these lines that would be
    // a number nobody can act on: the user would see THAT
    // an identity is hanging, but not WHICH. They only stand with more
    // than one identity (`aggregateTrayStatus` then returns the list
    // empty), likewise greyed out — information, not a command.
    for (final line in status.identities) {
      _addItem(menu, '    ${trayIdentityLineText(line, localeCode)}', sig,
          Pointer.fromFunction<Void Function(Pointer, Pointer)>(_onNoop),
          enabled: false);
    }

    _gtkMenuShellAppend(menu, _gtkSeparatorNew());

    _addItem(menu, trayTranslate('tray_menu_show', localeCode), sig,
        Pointer.fromFunction<Void Function(Pointer, Pointer)>(_onShowActivated));

    _gtkMenuShellAppend(menu, _gtkSeparatorNew());

    if (status.serviceRunning) {
      _addItem(menu, trayTranslate('tray_menu_stop', localeCode), sig,
          Pointer.fromFunction<Void Function(Pointer, Pointer)>(_onStopActivated));
    } else {
      _addItem(menu, trayTranslate('tray_menu_start', localeCode), sig,
          Pointer.fromFunction<Void Function(Pointer, Pointer)>(_onStartActivated));
    }

    _gtkMenuShellAppend(menu, _gtkSeparatorNew());

    _addItem(menu, trayTranslate('tray_menu_quit', localeCode), sig,
        Pointer.fromFunction<Void Function(Pointer, Pointer)>(_onQuitActivated));

    calloc.free(sig);
    _gtkWidgetShowAll(menu);
    // The PREVIOUS menu is released by the indicator itself: measured on
    // 24.09.2026 (S394) against libayatana-appindicator3 0.5.93 / GTK
    // 3.24.41 on node1 — right after `app_indicator_set_menu(new)` the old
    // menu is no valid GObject any more ("invalid unclassed pointer in cast
    // to 'GObject'"). The `gtk_widget_destroy(previous)` that stood here
    // since a76c70b6 therefore touched freed memory: mostly a Gtk-CRITICAL
    // on stderr, sometimes a native crash of the daemon without any Dart
    // trace (Alice, 24.09.2026 12:00:20, on an incoming message).
    _appIndicatorSetMenu(_indicator!, menu);
    _currentMenu = menu;
  }

  void _addItem(Pointer menu, String label, Pointer<Utf8> signal, Pointer callback,
      {bool enabled = true}) {
    final lbl = label.toNativeUtf8();
    final item = _gtkMenuItemNew(lbl);
    calloc.free(lbl);
    if (!enabled) _gtkWidgetSetSensitive(item, 0);
    _gtkMenuShellAppend(menu, item);
    _gSignalConnect(item, signal, callback, nullptr);
  }

  void processEvents() {
    if (_pendingShow) {
      _pendingShow = false;
      onShowWindow?.call();
    }
    if (_pendingStop) {
      _pendingStop = false;
      onStop?.call();
    }
    if (_pendingStart) {
      _pendingStart = false;
      onStart?.call();
    }
    if (_pendingQuit) {
      _pendingQuit = false;
      onQuit?.call();
    }
  }

  void dispose() {
    if (_windowsTray != null) {
      _windowsTray!.dispose();
      _windowsTray = null;
      _initialized = false;
      return;
    }
    _gtkPumpTimer?.cancel();
    _gtkPumpTimer = null;

    // Properly release GTK/AppIndicator resources to prevent zombie X11 windows.
    // Without this, SIGTERM → exit(0) leaves orphaned X11 windows that the
    // X server never cleans up (GTK internal helper windows + menu windows).
    try {
      if (_currentMenu != null && _gtkWidgetDestroy != null) {
        _gtkWidgetDestroy!(_currentMenu!);
        _currentMenu = null;
      }
      if (_indicator != null && _gObjectUnref != null) {
        _gObjectUnref!(_indicator!);
        _indicator = null;
      }
    } catch (_) {
      // Best-effort cleanup — crash during dispose is worse than leaked windows
    }

    _initialized = false;
    try { _tmpIconDir?.deleteSync(recursive: true); } catch (_) {}
  }
}
