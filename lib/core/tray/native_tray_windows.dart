// ignore_for_file: constant_identifier_names, camel_case_types
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:cleona/core/service/readiness_names.dart';
import 'package:cleona/core/tray/tray_status.dart';

// ── Win32 constants ─────────────────────────────────────────────────
const _NIM_ADD = 0x00000000;
const _NIM_MODIFY = 0x00000001;
const _NIM_DELETE = 0x00000002;
const _NIF_MESSAGE = 0x00000001;
const _NIF_ICON = 0x00000002;
const _NIF_TIP = 0x00000004;
const _WM_APP = 0x8000;
const _WM_TRAYICON = _WM_APP + 1;
const _WM_COMMAND = 0x0111;
const _WM_LBUTTONDBLCLK = 0x0203;
const _WM_RBUTTONUP = 0x0205;
const _WS_OVERLAPPEDWINDOW = 0x00CF0000;
const _IMAGE_ICON = 1;
const _LR_LOADFROMFILE = 0x0010;
const _LR_DEFAULTSIZE = 0x0040;
const _MF_STRING = 0x00000000;
const _MF_SEPARATOR = 0x00000800;
// For the state line: visible, but neither clickable nor highlighted.
const _MF_GRAYED = 0x00000001;
const _MF_DISABLED = 0x00000002;
const _TPM_BOTTOMALIGN = 0x0020;
const _TPM_LEFTALIGN = 0x0000;
const _IDI_APPLICATION = 32512;
// GetSystemMetrics: edge length of the SMALL icon. Exactly the size
// that the notification area displays.
const _SM_CXSMICON = 49;
const _SM_CYSMICON = 50;

// Menu item IDs
const _IDM_SHOW = 1001;
const _IDM_STOP = 1002;
const _IDM_START = 1003;
const _IDM_QUIT = 1004;

// ── Win32 type definitions ──────────────────────────────────────────

// Shell_NotifyIconW
typedef _Shell_NotifyIconWC = Int32 Function(Uint32, Pointer);
typedef _Shell_NotifyIconWDart = int Function(int, Pointer);

// CreateWindowExW
typedef _CreateWindowExWC = IntPtr Function(
    Uint32, Pointer<Utf16>, Pointer<Utf16>, Uint32,
    Int32, Int32, Int32, Int32,
    IntPtr, IntPtr, IntPtr, Pointer);
typedef _CreateWindowExWDart = int Function(
    int, Pointer<Utf16>, Pointer<Utf16>, int,
    int, int, int, int,
    int, int, int, Pointer);

// RegisterClassW
typedef _RegisterClassWC = Uint16 Function(Pointer);
typedef _RegisterClassWDart = int Function(Pointer);

// DefWindowProcW
typedef _DefWindowProcWC = IntPtr Function(IntPtr, Uint32, IntPtr, IntPtr);
typedef _DefWindowProcWDart = int Function(int, int, int, int);

// PeekMessageW
typedef _PeekMessageWC = Int32 Function(Pointer, IntPtr, Uint32, Uint32, Uint32);
typedef _PeekMessageWDart = int Function(Pointer, int, int, int, int);

// TranslateMessage / DispatchMessageW
typedef _TranslateMessageC = Int32 Function(Pointer);
typedef _TranslateMessageDart = int Function(Pointer);
typedef _DispatchMessageWC = IntPtr Function(Pointer);
typedef _DispatchMessageWDart = int Function(Pointer);

// LoadImageW
typedef _LoadImageWC = IntPtr Function(IntPtr, Pointer<Utf16>, Uint32, Int32, Int32, Uint32);
typedef _LoadImageWDart = int Function(int, Pointer<Utf16>, int, int, int, int);

// LoadIconW
typedef _LoadIconWC = IntPtr Function(IntPtr, IntPtr);
typedef _LoadIconWDart = int Function(int, int);

// CreatePopupMenu / AppendMenuW / TrackPopupMenu / DestroyMenu
typedef _CreatePopupMenuC = IntPtr Function();
typedef _CreatePopupMenuDart = int Function();
typedef _AppendMenuWC = Int32 Function(IntPtr, Uint32, IntPtr, Pointer<Utf16>);
typedef _AppendMenuWDart = int Function(int, int, int, Pointer<Utf16>);
typedef _TrackPopupMenuC = Int32 Function(IntPtr, Uint32, Int32, Int32, Int32, IntPtr, Pointer);
typedef _TrackPopupMenuDart = int Function(int, int, int, int, int, int, Pointer);
typedef _DestroyMenuC = Int32 Function(IntPtr);
typedef _DestroyMenuDart = int Function(int);

// GetCursorPos
typedef _GetCursorPosC = Int32 Function(Pointer);
typedef _GetCursorPosDart = int Function(Pointer);

// SetForegroundWindow / PostMessageW
typedef _SetForegroundWindowC = Int32 Function(IntPtr);
typedef _SetForegroundWindowDart = int Function(int);
typedef _PostMessageWC = Int32 Function(IntPtr, Uint32, IntPtr, IntPtr);
typedef _PostMessageWDart = int Function(int, int, int, int);

// GetModuleHandleW
typedef _GetModuleHandleWC = IntPtr Function(Pointer<Utf16>);
typedef _GetModuleHandleWDart = int Function(Pointer<Utf16>);

// DestroyIcon / GetSystemMetrics — for the five tier icons (§22.9).
typedef _DestroyIconC = Int32 Function(IntPtr);
typedef _DestroyIconDart = int Function(int);
typedef _GetSystemMetricsC = Int32 Function(Int32);
typedef _GetSystemMetricsDart = int Function(int);

// ── NOTIFYICONDATAW struct (simplified, 64-bit) ─────────────────────
// We use a raw byte buffer since Dart FFI structs can't easily handle
// the complex NOTIFYICONDATAW with its embedded arrays.
const _NOTIFYICONDATAW_SIZE = 976; // sizeof(NOTIFYICONDATAW) on 64-bit

/// Pending actions from the tray menu, polled by the daemon.
bool pendingShow = false;
bool pendingStop = false;
bool pendingStart = false;
bool pendingQuit = false;

/// Global state for the window procedure callback.
int _trayHwnd = 0;
int _trayHicon = 0;
bool _serviceRunning = true;

/// The state line for the context menu (§22.9, owner decision
/// V-10 = A: icon AND text).
///
/// GLOBAL, because `_showContextMenu` is called from the window procedure —
/// a `Pointer.fromFunction` callback that cannot carry an instance
/// with it. The same design as `_serviceRunning` next to it, for
/// the same reason.
String _statusLine = '';

/// Language of the menu items. Until S376 four German
/// strings stood here in the code — the only surface of the product that
/// knew none of the 34 languages.
String _menuLocale = 'en';

/// The individual lines of the identities for the context menu (V-10-c = b,
/// 09.09.2026). GLOBAL for the same reason as [_statusLine]:
/// `_showContextMenu` runs in a `Pointer.fromFunction` callback
/// without instance reference. Empty with a single identity.
List<String> _identityLines = const [];

// Win32 function pointers (global for callback access)
late _Shell_NotifyIconWDart _shellNotifyIcon;
late _CreatePopupMenuDart _createPopupMenu;
late _AppendMenuWDart _appendMenuW;
late _TrackPopupMenuDart _trackPopupMenu;
late _DestroyMenuDart _destroyMenu;
late _GetCursorPosDart _getCursorPos;
late _SetForegroundWindowDart _setForegroundWindow;
late _PostMessageWDart _postMessage;
late _DefWindowProcWDart _defWindowProc;

/// Window procedure callback for the hidden tray window.
int _wndProc(int hwnd, int msg, int wParam, int lParam) {
  if (msg == _WM_TRAYICON) {
    final event = lParam & 0xFFFF;
    if (event == _WM_LBUTTONDBLCLK) {
      pendingShow = true;
    } else if (event == _WM_RBUTTONUP) {
      _showContextMenu(hwnd);
    }
    return 0;
  }
  if (msg == _WM_COMMAND) {
    final id = wParam & 0xFFFF;
    switch (id) {
      case _IDM_SHOW:
        pendingShow = true;
        break;
      case _IDM_STOP:
        pendingStop = true;
        break;
      case _IDM_START:
        pendingStart = true;
        break;
      case _IDM_QUIT:
        pendingQuit = true;
        break;
    }
    return 0;
  }
  return _defWindowProc(hwnd, msg, wParam, lParam);
}

void _showContextMenu(int hwnd) {
  final menu = _createPopupMenu();

  // ── STATE LINE AT THE VERY TOP, GREYED OUT (§22.9) ────────────────────
  //
  // `MF_GRAYED | MF_DISABLED`: information, not a command. The identifier
  // is 0, so that an accidental click in `_wndProc` falls into none of the
  // four `case` branches.
  if (_statusLine.isNotEmpty) {
    final st = _statusLine.toNativeUtf16();
    _appendMenuW(menu, _MF_STRING | _MF_GRAYED | _MF_DISABLED, 0, st);
    calloc.free(st);
    // Each identity individually (V-10-c = b) — the same structure as in the
    // GTK menu, so that both platforms say the same.
    for (final line in _identityLines) {
      final z = '    $line'.toNativeUtf16();
      _appendMenuW(menu, _MF_STRING | _MF_GRAYED | _MF_DISABLED, 0, z);
      calloc.free(z);
    }
    _appendMenuW(menu, _MF_SEPARATOR, 0, nullptr);
  }

  final show = trayTranslate('tray_menu_show', _menuLocale).toNativeUtf16();
  _appendMenuW(menu, _MF_STRING, _IDM_SHOW, show);
  calloc.free(show);

  _appendMenuW(menu, _MF_SEPARATOR, 0, nullptr);

  if (_serviceRunning) {
    final stop = trayTranslate('tray_menu_stop', _menuLocale).toNativeUtf16();
    _appendMenuW(menu, _MF_STRING, _IDM_STOP, stop);
    calloc.free(stop);
  } else {
    final start = trayTranslate('tray_menu_start', _menuLocale).toNativeUtf16();
    _appendMenuW(menu, _MF_STRING, _IDM_START, start);
    calloc.free(start);
  }

  _appendMenuW(menu, _MF_SEPARATOR, 0, nullptr);

  final quit = trayTranslate('tray_menu_quit', _menuLocale).toNativeUtf16();
  _appendMenuW(menu, _MF_STRING, _IDM_QUIT, quit);
  calloc.free(quit);

  // Get cursor position
  final pt = calloc<Int32>(2);
  _getCursorPos(pt);
  final x = pt[0];
  final y = pt[1];
  calloc.free(pt);

  _setForegroundWindow(hwnd);
  _trackPopupMenu(menu, _TPM_LEFTALIGN | _TPM_BOTTOMALIGN, x, y, 0, hwnd, nullptr);
  _postMessage(hwnd, _WM_COMMAND, 0, 0); // dismiss
  _destroyMenu(menu);
}

/// Has the notification area accepted the icon?
///
/// `Shell_NotifyIconW` returns BOOL: non-zero means "accepted",
/// zero means "rejected". This function is the one place at which a
/// statement is made from this return value, so that it can be checked without Windows
/// (`test/smoke/smoke_tray_windows_meldung_guard.dart`).
///
/// ── WHY IT EXISTS (finding 4, S370, 06.09.2026) ───────────────────
///
/// Until S370 [NativeTrayWindows.init] simply contained
///
///     _shellNotifyIcon(_NIM_ADD, _nid);
///
/// — the return value was discarded, `init` reported `true` as soon as
/// `CreateWindowExW` had succeeded, and `service_daemon.dart` thereupon printed
/// "Tray icon: OK". Measured on 06.09.2026 on the
/// Windows build VM 192.168.10.74:
///
///   12:09:13.901399 [INFO ] [daemon] Tray icon: OK (icon: …app_icon_beta.ico)
///   PS> Get-Process cleona-daemon | Select Id,SessionId -> 5156, session 0
///   PS> Get-Process explorer     | Select Id,SessionId -> 2264, session 3
///
/// The daemon ran in session 0, the shell in session 3. There
/// `Shell_NotifyIcon` cannot create an icon — there is no notification area.
/// `CreateWindowExW` however succeeds even without a shell, and exactly on that
/// the success report relied. The Linux branch of the same class warns
/// expressly when DISPLAY is missing; the Windows branch claimed
/// success instead.
bool trayIconAccepted(int shellNotifyIconResult) => shellNotifyIconResult != 0;

/// The text of the tooltip (szTip) for an unread state.
///
/// The same rule the Linux branch uses for the tray TITLE
/// (`native_tray.dart:_rebuildMenu`: `unreadCount > 0 ? '$baseName
/// ($unreadCount)' : baseName`) — the two platforms are to say the same,
/// only via different carriers.
///
/// ── WHY IT EXISTS (finding 5, S370, 06.09.2026) ───────────────────
///
/// `service_daemon.dart:1602` computes the unread sum over all
/// identities and calls `tray.updateMenu(serviceRunning:,
/// unreadCount:)`. `native_tray.dart:268-275` passed of that ONLY
/// `serviceRunning` on to the Windows tray, and
/// `NativeTrayWindows.updateMenu` had no parameter at all for `unreadCount`.
/// `_NIM_MODIFY` was not even defined as a constant in the file:
/// after `NIM_ADD` the notification area was never touched again.
/// The producer existed, the receiver did not.
///
/// [statusLine] was added with S376 (§22.9): the tooltip is under
/// Windows the only surface that shows the state WITHOUT a click. szTip
/// holds 127 characters; if the line is longer, it drops instead of
/// displacing the counter — the counter is the older promise.
String trayTooltipText(String basis, int unreadCount, [String statusLine = '']) {
  final header = unreadCount > 0 ? '$basis ($unreadCount)' : basis;
  if (statusLine.isEmpty) return header;
  final full = '$header\n$statusLine';
  return full.length <= 127 ? full : header;
}

/// Writes [text] as a null-terminated UTF-16 string into the szTip field
/// of a NOTIFYICONDATAW structure.
///
/// On a 64-bit Windows szTip lies at BYTE OFFSET 40 and holds 128
/// WCHAR. Recalculated (S370): cbSize 4 + 4 padding bytes = 8, hWnd 8 = 16,
/// uID 4 = 20, uFlags 4 = 24, uCallbackMessage 4 + 4 padding bytes = 32,
/// hIcon 8 = 40. Thus 127 characters plus terminating null are usable.
///
/// Extracted, because this pointer arithmetic is the only place with a
/// real risk of error and can be checked WITHOUT Windows — a
/// `calloc` buffer behaves the same under Linux
/// (`smoke_tray_windows_ungelesen_guard.dart`).
void writeSzTip(Pointer<Uint8> nid, String text) {
  final tipPtr = (nid + 40).cast<Uint16>();
  final units = text.codeUnits;
  final n = units.length < 127 ? units.length : 127;
  for (var i = 0; i < n; i++) {
    tipPtr[i] = units[i];
  }
  tipPtr[n] = 0;
}

/// Windows system tray implementation using Win32 Shell_NotifyIcon.
class NativeTrayWindows {
  Timer? _pumpTimer;
  bool _initialized = false;
  final _nid = calloc<Uint8>(_NOTIFYICONDATAW_SIZE);

  /// Log channel of the caller (`NativeTray.init`'s `logger`). Without it
  /// a failed `Shell_NotifyIcon` stayed mute even when the
  /// daemon keeps a log.
  void Function(String level, String msg)? _logger;

  /// The tooltip without counter, as [init] got it. Basis for
  /// [trayTooltipText] at every [updateMenu].
  String _tooltipBasis = 'Cleona Chat';

  /// Last set tooltip — prevents one `NIM_MODIFY` per call
  /// when nothing has changed. `updateMenu` comes with every
  /// incoming message.
  String? _tooltipSet;

  /// Loaded state icons (HICON) per readiness state.
  ///
  /// ── WHY IT EXISTS (V-10-b, owner decision 09.09.2026) ──────
  ///
  /// Until S377 the Windows tray carried its display ONLY as text: tooltip
  /// and greyed-out first menu line. The reason was no code problem,
  /// but a missing image format — `Shell_NotifyIcon` takes an
  /// HICON resource, and the images were only available as PNG. They lie
  /// additionally as `.ico` next to them (`scripts/make_tray_icos.dart`), and
  /// with that the ICON carries the state here too, as §22.9 requires for
  /// both platforms. Since S388 (E3 = A) these are three images
  /// for the three readiness states instead of five tiers.
  ///
  /// FAIL-SAFE, for the same reason as under Linux: if a file is missing
  /// or `LoadImageW` fails, it stays with the base icon and the
  /// state keeps travelling via the text. A tray that loses its icon at a
  /// state change would be worse than one
  /// that does not show the state in the icon.
  final Map<String, int> _stateSymbols = {};

  /// The icon last written into the structure — prevents a
  /// `NIM_MODIFY` for a change that does not exist.
  int _setSymbol = 0;

  /// The path of the state icon that the tray SHOULD show — set even
  /// when there is no notification area at all.
  ///
  /// The same design and the same reason as [intendedTooltip]: only
  /// thus can "the state reaches the Windows icon" be checked without Windows.
  /// A guard that instead measures the existence of
  /// `_zustandsSymbole` measures a proxy.
  String? intendedStateIcon;

  /// Base icon from [init] — the fallback when a state image is missing.
  String _baseIconPath = '';

  /// The EXISTING state files next to the base icon.
  ///
  /// Determined once at start and not at every state report:
  /// `updateStatus` comes at every change of the service, and an
  /// `existsSync` per change would be a system call for an answer
  /// that no longer changes at runtime.
  final Map<String, String> _statePaths = {};

  _DestroyIconDart? _destroyIcon;

  // Callbacks
  void Function()? onShowWindow;
  void Function()? onStop;
  void Function()? onStart;
  void Function()? onQuit;

  bool init({
    required String iconPath,
    String tooltip = 'Cleona Chat',
    void Function(String level, String msg)? logger,
  }) {
    _logger = logger;
    _tooltipBasis = tooltip;
    _tooltipSet = tooltip;
    // BEFORE the `try` and before any Win32 binding, for the same reason as
    // [beabsichtigteKurzinfo]: "which state icon SHOULD the tray
    // show" is a true statement even when there is no Windows at all.
    // Only thus can it be checked without Windows — and it is pure
    // file system work that needs no Win32.
    _baseIconPath = iconPath;
    _statePaths.clear();
    for (final state in kReadinessNames) {
      final path =
          readinessIconSiblingPath(iconPath, state, extension: 'ico');
      if (path != null && File(path).existsSync()) {
        _statePaths[state] = path;
      }
    }
    if (_initialized) return true;

    try {
      final shell32 = DynamicLibrary.open('shell32.dll');
      final user32 = DynamicLibrary.open('user32.dll');
      final kernel32 = DynamicLibrary.open('kernel32.dll');

      _shellNotifyIcon = shell32.lookupFunction<_Shell_NotifyIconWC, _Shell_NotifyIconWDart>(
          'Shell_NotifyIconW');

      final createWindowExW = user32.lookupFunction<_CreateWindowExWC, _CreateWindowExWDart>(
          'CreateWindowExW');
      final registerClassW = user32.lookupFunction<_RegisterClassWC, _RegisterClassWDart>(
          'RegisterClassW');
      _defWindowProc = user32.lookupFunction<_DefWindowProcWC, _DefWindowProcWDart>(
          'DefWindowProcW');
      final peekMessageW = user32.lookupFunction<_PeekMessageWC, _PeekMessageWDart>(
          'PeekMessageW');
      final translateMessage = user32.lookupFunction<_TranslateMessageC, _TranslateMessageDart>(
          'TranslateMessage');
      final dispatchMessageW = user32.lookupFunction<_DispatchMessageWC, _DispatchMessageWDart>(
          'DispatchMessageW');
      final loadImageW = user32.lookupFunction<_LoadImageWC, _LoadImageWDart>(
          'LoadImageW');
      final loadIconW = user32.lookupFunction<_LoadIconWC, _LoadIconWDart>(
          'LoadIconW');
      _createPopupMenu = user32.lookupFunction<_CreatePopupMenuC, _CreatePopupMenuDart>(
          'CreatePopupMenu');
      _appendMenuW = user32.lookupFunction<_AppendMenuWC, _AppendMenuWDart>(
          'AppendMenuW');
      _trackPopupMenu = user32.lookupFunction<_TrackPopupMenuC, _TrackPopupMenuDart>(
          'TrackPopupMenu');
      _destroyMenu = user32.lookupFunction<_DestroyMenuC, _DestroyMenuDart>(
          'DestroyMenu');
      _getCursorPos = user32.lookupFunction<_GetCursorPosC, _GetCursorPosDart>(
          'GetCursorPos');
      _setForegroundWindow = user32.lookupFunction<_SetForegroundWindowC, _SetForegroundWindowDart>(
          'SetForegroundWindow');
      _postMessage = user32.lookupFunction<_PostMessageWC, _PostMessageWDart>(
          'PostMessageW');
      final getModuleHandle = kernel32.lookupFunction<_GetModuleHandleWC, _GetModuleHandleWDart>(
          'GetModuleHandleW');

      final hInstance = getModuleHandle(nullptr);

      // Register window class
      final className = 'CleonaTrayWindow'.toNativeUtf16();
      final wndProcPtr = Pointer.fromFunction<IntPtr Function(IntPtr, Uint32, IntPtr, IntPtr)>(
          _wndProc, 0);

      // WNDCLASSW struct (80 bytes on 64-bit)
      final wc = calloc<Uint8>(80);
      final wcView = wc.cast<IntPtr>();
      // style = 0
      wcView[0] = 0;
      // lpfnWndProc
      wcView[1] = wndProcPtr.address;
      // cbClsExtra, cbWndExtra = 0
      wc.cast<Int32>()[4] = 0;
      wc.cast<Int32>()[5] = 0;
      // hInstance
      wcView[3] = hInstance;
      // hIcon, hCursor, hbrBackground = 0
      wcView[4] = 0;
      wcView[5] = 0;
      wcView[6] = 0;
      // lpszMenuName = null
      wcView[7] = 0;
      // lpszClassName
      wcView[8] = className.address;

      registerClassW(wc);
      calloc.free(wc);

      // Create hidden window
      final windowName = 'Cleona Tray'.toNativeUtf16();
      _trayHwnd = createWindowExW(
        0, className, windowName, _WS_OVERLAPPEDWINDOW,
        0, 0, 0, 0,
        0, 0, hInstance, nullptr,
      );
      calloc.free(className);
      calloc.free(windowName);

      if (_trayHwnd == 0) return false;

      _destroyIcon =
          user32.lookupFunction<_DestroyIconC, _DestroyIconDart>('DestroyIcon');
      final getSystemMetrics =
          user32.lookupFunction<_GetSystemMetricsC, _GetSystemMetricsDart>(
              'GetSystemMetrics');

      // Load icon
      if (iconPath.endsWith('.ico') && File(iconPath).existsSync()) {
        final iconPathW = iconPath.toNativeUtf16();
        _trayHicon = loadImageW(0, iconPathW, _IMAGE_ICON, 0, 0,
            _LR_LOADFROMFILE | _LR_DEFAULTSIZE);
        calloc.free(iconPathW);
      }
      if (_trayHicon == 0) {
        // Fallback: default application icon
        _trayHicon = loadIconW(0, _IDI_APPLICATION);
      }
      _setSymbol = _trayHicon;

      // ── THE THREE STATE ICONS (§22.9, V-10-b, E3 = A) ─────────────
      //
      // In the EXACT size that the notification area shows. The base icon
      // above loads with `LR_DEFAULTSIZE`, i.e. 32 x 32
      // (`SM_CXICON`), and lets the shell scale down; for the
      // states the container holds a 16 version of its own, and that is
      // sharper than a scaled-down 32. If
      // `GetSystemMetrics` returns nothing (0), it falls back to `LR_DEFAULTSIZE`
      // instead of to an invented number.
      var kx = 0;
      var ky = 0;
      try {
        kx = getSystemMetrics(_SM_CXSMICON);
        ky = getSystemMetrics(_SM_CYSMICON);
      } catch (_) {}
      final flags = (kx > 0 && ky > 0)
          ? _LR_LOADFROMFILE
          : (_LR_LOADFROMFILE | _LR_DEFAULTSIZE);
      var found = 0;
      for (final entry in _statePaths.entries) {
        final state = entry.key;
        final path = entry.value;
        final pw = path.toNativeUtf16();
        final h = loadImageW(0, pw, _IMAGE_ICON, kx, ky, flags);
        calloc.free(pw);
        if (h == 0) {
          _logger?.call('warn',
              'State icon "$path" could not be loaded (LoadImageW = 0).');
          continue;
        }
        _stateSymbols[state] = h;
        found++;
      }
      if (found == 0) {
        _logger?.call(
            'warn',
            'none of the three state icons (conn_*.ico) lies next to '
            '"$iconPath" — the icon stays fixed, the state travels only '
            'as text (§22.9).');
      } else {
        _logger?.call('info',
            'State icons: $found of ${kReadinessNames.length} '
            '(${kx > 0 ? "${kx}x$ky" : "default size"})');
      }

      // Fill NOTIFYICONDATAW
      final nidView = _nid.cast<Uint32>();
      nidView[0] = _NOTIFYICONDATAW_SIZE; // cbSize
      _nid.cast<IntPtr>()[1] = _trayHwnd; // hWnd (offset 8 on 64-bit)
      nidView[4] = 1; // uID (offset 16)
      nidView[5] = _NIF_MESSAGE | _NIF_ICON | _NIF_TIP; // uFlags (offset 20)
      nidView[6] = _WM_TRAYICON; // uCallbackMessage (offset 24)
      _nid.cast<IntPtr>()[4] = _trayHicon; // hIcon (offset 32 on 64-bit)

      // szTip: UTF-16 string at offset 40, max 128 chars
      writeSzTip(_nid, tooltip);

      // The return value IS the statement — see [trayIconAccepted].
      // If the insertion fails, abort here, BEFORE the
      // pump timer stands: there is then nothing to withdraw, and
      // `service_daemon.dart` prints "Tray icon: FAILED" instead of "OK".
      if (!trayIconAccepted(_shellNotifyIcon(_NIM_ADD, _nid))) {
        _logger?.call(
            'warn',
            'Shell_NotifyIcon(NIM_ADD) rejected — in this session there is '
            'no notification area (session 0 / no shell / Explorer not '
            'started). NO icon will appear.');
        return false;
      }

      // Message pump timer
      final msg = calloc<Uint8>(48); // MSG struct
      _pumpTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        // Process Windows messages
        while (peekMessageW(msg, _trayHwnd, 0, 0, 1) != 0) {
          translateMessage(msg);
          dispatchMessageW(msg);
        }
        _processEvents();
      });

      _initialized = true;
      return true;
    } catch (e) {
      _logger?.call('warn', 'NativeTrayWindows init failed: $e');
      try { stderr.writeln('NativeTrayWindows init failed: $e'); } catch (_) {}
      return false;
    }
  }

  /// What the tooltip SHOULD show — independent of whether the
  /// notification area has accepted the icon.
  ///
  /// Set BEFORE the `_initialized` check, for the same reason as
  /// `NativeTray.letzterZustand`: otherwise "the readiness reaches
  /// the Windows tray" would only be checkable on a Windows with a session, and
  /// the guard would have to make do with a text comparison of the source
  /// — i.e. with a proxy.
  String? intendedTooltip;

  /// The last passed state (counterpart to
  /// `NativeTray.letzterZustand` on the Windows branch).
  TrayStatus? lastState;

  /// Readiness state and counter to the notification area.
  ///
  /// Windows has no permanently visible menu like the
  /// StatusNotifierItem — the state therefore travels via the TOOLTIP
  /// (szTip, on hovering) and via the greyed-out first line of the
  /// context menu (on right-click).
  void updateStatus(TrayStatus status, String basisName, String localeCode) {
    _serviceRunning = status.serviceRunning;
    _menuLocale = localeCode;
    _statusLine = trayStatusText(status, localeCode);
    _identityLines = [
      for (final z in status.identities) trayIdentityLineText(z, localeCode)
    ];
    lastState = status;
    final basis = basisName.isEmpty ? _tooltipBasis : basisName;
    final text = trayTooltipText(basis, status.unreadCount, _statusLine);
    intendedTooltip = text;
    // The intended statement about the ICON — before the
    // `_initialized` check, for the same reason as the tooltip
    // above (see [beabsichtigtesZustandssymbol]).
    // The fallback is expressly represented here: if the
    // state file is missing, the base icon is the statement — not a path that
    // does not exist. Otherwise this seam would claim a change that the
    // notification area never sees.
    intendedStateIcon = _baseIconPath.isEmpty
        ? null
        : (_statePaths[status.readiness] ?? _baseIconPath);
    if (!_initialized) return;

    final symbol = _stateSymbols[status.readiness] ?? _trayHicon;
    final symbolNew = symbol != 0 && symbol != _setSymbol;
    final textNew = text != _tooltipSet;
    // A `NIM_MODIFY` without change is traffic without a statement — and
    // `updateStatus` comes with every state report of the service.
    if (!symbolNew && !textNew) return;

    if (textNew) {
      _tooltipSet = text;
      writeSzTip(_nid, text);
    }
    if (symbolNew) {
      _setSymbol = symbol;
      _nid.cast<IntPtr>()[4] = symbol; // hIcon (offset 32 on 64 bit)
    }
    // NIM_MODIFY with unchanged uFlags (MESSAGE|ICON|TIP): the
    // notification area takes over the whole record anew — now including
    // a changed icon.
    if (_shellNotifyIcon(_NIM_MODIFY, _nid) == 0) {
      _logger?.call('warn',
          'Shell_NotifyIcon(NIM_MODIFY) rejected — tooltip and icon '
          'stay at the old state.');
    }
  }

  void _processEvents() {
    if (pendingShow) {
      pendingShow = false;
      onShowWindow?.call();
    }
    if (pendingStop) {
      pendingStop = false;
      onStop?.call();
    }
    if (pendingStart) {
      pendingStart = false;
      onStart?.call();
    }
    if (pendingQuit) {
      pendingQuit = false;
      onQuit?.call();
    }
  }

  void dispose() {
    _pumpTimer?.cancel();
    if (_initialized) {
      _shellNotifyIcon(_NIM_DELETE, _nid);
    }
    // Only free the tier icons created by ourselves with `LoadImageW(..., LR_LOADFROMFILE)`.
    // The base icon stays untouched: it
    // can stem from `LoadIconW(0, IDI_APPLICATION)`, and a
    // shared system icon must not be destroyed.
    final destroy = _destroyIcon;
    if (destroy != null) {
      for (final h in _stateSymbols.values) {
        try { destroy(h); } catch (_) {}
      }
    }
    _stateSymbols.clear();
    calloc.free(_nid);
    _initialized = false;
  }
}
