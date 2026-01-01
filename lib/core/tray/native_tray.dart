import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:cleona/core/crypto/network_secret.dart';
import 'package:cleona/core/tray/native_tray_windows.dart';

// ── GTK type aliases ─────────────────────────────────────────────────

typedef _GtkInitC = Void Function(Pointer<Int32>, Pointer<Pointer<Pointer<Utf8>>>);
typedef _GtkInitDart = void Function(Pointer<Int32>, Pointer<Pointer<Pointer<Utf8>>>);

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

  bool init({required String iconPath, String tooltip = 'Cleona Chat'}) {
    if (_initialized) return true;

    // Windows: delegate to Win32 implementation
    if (Platform.isWindows) {
      _windowsTray = NativeTrayWindows();
      _windowsTray!.onShowWindow = () => onShowWindow?.call();
      _windowsTray!.onStop = () => onStop?.call();
      _windowsTray!.onStart = () => onStart?.call();
      _windowsTray!.onQuit = () => onQuit?.call();
      _initialized = _windowsTray!.init(iconPath: iconPath, tooltip: tooltip);
      return _initialized;
    }

    // macOS: no daemon-side tray in v1. The daemon is a plain Dart command-
    // line binary without a FlutterEngine, so MethodChannel to Cocoa isn't
    // available. An NSStatusItem via direct objc_msgSend FFI is feasible but
    // ~500 LoC of bridging code and not needed for the first macOS ship.
    // updateMenu()/dispose() below check _initialized and become no-ops.
    if (Platform.isMacOS) {
      return false;
    }

    try {
      final gtk = DynamicLibrary.open('libgtk-3.so.0');
      final glib = DynamicLibrary.open('libglib-2.0.so.0');
      final gobject = DynamicLibrary.open('libgobject-2.0.so.0');

      DynamicLibrary appindicatorLib;
      try {
        appindicatorLib = DynamicLibrary.open('libayatana-appindicator3.so.1');
      } catch (_) {
        appindicatorLib = DynamicLibrary.open('libappindicator3.so.1');
      }

      final gtkInit = gtk.lookupFunction<_GtkInitC, _GtkInitDart>('gtk_init');
      _gtkMenuNew = gtk.lookupFunction<_GtkMenuNewC, _GtkMenuNewDart>('gtk_menu_new');
      _gtkMenuItemNew = gtk.lookupFunction<_GtkMenuItemNewC, _GtkMenuItemNewDart>(
          'gtk_menu_item_new_with_label');
      _gtkSeparatorNew = gtk.lookupFunction<_GtkSeparatorMenuItemNewC, _GtkSeparatorMenuItemNewDart>(
          'gtk_separator_menu_item_new');
      _gtkMenuShellAppend = gtk.lookupFunction<_GtkMenuShellAppendC, _GtkMenuShellAppendDart>(
          'gtk_menu_shell_append');
      _gtkWidgetShowAll = gtk.lookupFunction<_GtkWidgetShowAllC, _GtkWidgetShowAllDart>(
          'gtk_widget_show_all');
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
      final appIndicatorSetIconThemePath =
          appindicatorLib.lookupFunction<_AppIndicatorSetIconThemePathC, _AppIndicatorSetIconThemePathDart>(
              'app_indicator_set_icon_theme_path');
      _appIndicatorSetTitle =
          appindicatorLib.lookupFunction<_AppIndicatorSetTitleC, _AppIndicatorSetTitleDart>(
              'app_indicator_set_title');

      gtkInit(nullptr, nullptr);

      // AppIndicator expects icon theme name, not absolute path.
      // Copy icon to temp dir with PID-unique name to bust GNOME Shell's icon cache.
      final uniqueName = 'cleona_tray_$pid';
      final tmpDir = Directory.systemTemp.createTempSync('cleona_tray_');
      _tmpIconDir = tmpDir;
      File(iconPath).copySync('${tmpDir.path}/$uniqueName.png');
      final iconDir = tmpDir.path;
      final iconName = uniqueName;

      final id = 'cleona-daemon'.toNativeUtf8();
      final iconNameNative = iconName.toNativeUtf8();
      _indicator = appIndicatorNew(id, iconNameNative, 1); // CATEGORY_COMMUNICATIONS
      calloc.free(id);
      calloc.free(iconNameNative);

      if (_indicator == null || _indicator == nullptr) return false;

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

      _rebuildMenu(serviceRunning: true);

      _gtkPumpTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        while (_gMainContextIteration(nullptr, 0) != 0) {}
        processEvents();
      });

      _initialized = true;
      return true;
    } catch (e) {
      try { stderr.writeln('NativeTray init failed: $e'); } catch (_) {}
      return false;
    }
  }

  void updateMenu({required bool serviceRunning, int unreadCount = 0}) {
    if (!_initialized) return;
    if (_windowsTray != null) {
      _windowsTray!.updateMenu(serviceRunning: serviceRunning);
      return;
    }
    _rebuildMenu(serviceRunning: serviceRunning, unreadCount: unreadCount);
  }

  void _rebuildMenu({required bool serviceRunning, int unreadCount = 0}) {
    // Update tray title with unread count
    final baseName = NetworkSecret.channel == NetworkChannel.beta ? 'Cleona Beta' : 'Cleona Chat';
    final title = unreadCount > 0 ? '$baseName ($unreadCount)' : baseName;
    final titleNative = title.toNativeUtf8();
    _appIndicatorSetTitle(_indicator!, titleNative);
    calloc.free(titleNative);

    final menu = _gtkMenuNew();
    final sig = 'activate'.toNativeUtf8();

    // Anzeigen
    _addItem(menu, 'Anzeigen', sig,
        Pointer.fromFunction<Void Function(Pointer, Pointer)>(_onShowActivated));

    _gtkMenuShellAppend(menu, _gtkSeparatorNew());

    if (serviceRunning) {
      _addItem(menu, 'Dienst stoppen', sig,
          Pointer.fromFunction<Void Function(Pointer, Pointer)>(_onStopActivated));
    } else {
      _addItem(menu, 'Dienst starten', sig,
          Pointer.fromFunction<Void Function(Pointer, Pointer)>(_onStartActivated));
    }

    _gtkMenuShellAppend(menu, _gtkSeparatorNew());

    _addItem(menu, 'Beenden', sig,
        Pointer.fromFunction<Void Function(Pointer, Pointer)>(_onQuitActivated));

    calloc.free(sig);
    _gtkWidgetShowAll(menu);
    _appIndicatorSetMenu(_indicator!, menu);
    _currentMenu = menu;
  }

  void _addItem(Pointer menu, String label, Pointer<Utf8> signal, Pointer callback) {
    final lbl = label.toNativeUtf8();
    final item = _gtkMenuItemNew(lbl);
    calloc.free(lbl);
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
