// ignore_for_file: constant_identifier_names, camel_case_types
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// ── Win32 constants ─────────────────────────────────────────────────
const _NIM_ADD = 0x00000000;
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
const _TPM_BOTTOMALIGN = 0x0020;
const _TPM_LEFTALIGN = 0x0000;
const _IDI_APPLICATION = 32512;

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

  final show = 'Anzeigen'.toNativeUtf16();
  _appendMenuW(menu, _MF_STRING, _IDM_SHOW, show);
  calloc.free(show);

  _appendMenuW(menu, _MF_SEPARATOR, 0, nullptr);

  if (_serviceRunning) {
    final stop = 'Dienst stoppen'.toNativeUtf16();
    _appendMenuW(menu, _MF_STRING, _IDM_STOP, stop);
    calloc.free(stop);
  } else {
    final start = 'Dienst starten'.toNativeUtf16();
    _appendMenuW(menu, _MF_STRING, _IDM_START, start);
    calloc.free(start);
  }

  _appendMenuW(menu, _MF_SEPARATOR, 0, nullptr);

  final quit = 'Beenden'.toNativeUtf16();
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

/// Windows system tray implementation using Win32 Shell_NotifyIcon.
class NativeTrayWindows {
  Timer? _pumpTimer;
  bool _initialized = false;
  final _nid = calloc<Uint8>(_NOTIFYICONDATAW_SIZE);

  // Callbacks
  void Function()? onShowWindow;
  void Function()? onStop;
  void Function()? onStart;
  void Function()? onQuit;

  bool init({required String iconPath, String tooltip = 'Cleona Chat'}) {
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

      // Fill NOTIFYICONDATAW
      final nidView = _nid.cast<Uint32>();
      nidView[0] = _NOTIFYICONDATAW_SIZE; // cbSize
      _nid.cast<IntPtr>()[1] = _trayHwnd; // hWnd (offset 8 on 64-bit)
      nidView[4] = 1; // uID (offset 16)
      nidView[5] = _NIF_MESSAGE | _NIF_ICON | _NIF_TIP; // uFlags (offset 20)
      nidView[6] = _WM_TRAYICON; // uCallbackMessage (offset 24)
      _nid.cast<IntPtr>()[4] = _trayHicon; // hIcon (offset 32 on 64-bit)

      // szTip: UTF-16 string at offset 40, max 128 chars
      final tipPtr = (_nid + 40).cast<Uint16>();
      final tipUnits = tooltip.codeUnits;
      for (var i = 0; i < tipUnits.length && i < 127; i++) {
        tipPtr[i] = tipUnits[i];
      }
      tipPtr[tipUnits.length.clamp(0, 127)] = 0;

      _shellNotifyIcon(_NIM_ADD, _nid);

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
      try { stderr.writeln('NativeTrayWindows init failed: $e'); } catch (_) {}
      return false;
    }
  }

  void updateMenu({required bool serviceRunning}) {
    _serviceRunning = serviceRunning;
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
    calloc.free(_nid);
    _initialized = false;
  }
}
