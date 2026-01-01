import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'package:cleona/core/platform/app_paths.dart';

// The binding to `cleona_tray.dll` (windows/cleona_tray/cleona_tray.c):
// the native thread that owns the hidden tray window, the icon handles, the
// `Shell_NotifyIconW` calls and the context menu of the Windows tray.
//
// ── WHY IT EXISTS (S423 B-5, report S423-RCA-WINDOWS.md) ──────
//
// Until S423 `NativeTrayWindows.init` created the window from Dart. Dart
// code after an `await` runs on a worker of the VM thread pool (Dart SDK
// runtime/vm/dart_api_impl.cc, `Dart_RunLoop`), an idle worker ends after
// 5 s (runtime/vm/thread_pool.cc, `worker_timeout_millis` = 5000), and
// "Any resources owned by the thread, such as windows and hooks, are freed"
// (Microsoft Learn, "Terminating a Thread",
// https://learn.microsoft.com/en-us/windows/win32/procthread/terminating-a-thread).
// The lab measured exactly that on 14.11.2026: `NIM_MODIFY` rejected with
// `window alive=false` from 7 s after `NIM_ADD`, the icon gone from the
// notification area. An isolate is bound to no OS thread, so the window
// lives on a thread Dart does not manage, and this file is the only way to
// it. Every call blocks until the tray thread has handled it (at most 5 s,
// `TRAY_SEND_TIMEOUT_MS` in the C file).

/// Event codes the tray thread reports (besides the menu identifiers it
/// passes through unchanged). Must match `TRAY_EVENT_*` in cleona_tray.c.
const int kTrayEventShow = 1001;
const int kTrayEventReadded = 2001;
const int kTrayEventReaddFailed = 2002;

/// Measurement (S424 R-3, M-1): the tray window received `WM_CLOSE`.
const int kTrayEventCloseReceived = 2003;

/// Measurement (S424 R-3, M-1): the tray window received `WM_DESTROY`.
const int kTrayEventDestroyed = 2004;

/// Measurement (S424 R-3, M-1): the tray thread's message loop ended on
/// `WM_QUIT` (`GetMessageW` = 0) and the thread returns exit code 0.
const int kTrayEventThreadEnded = 2005;

/// Measurement (S424 R-3, M-1): the tray thread's message loop ended because
/// `GetMessageW` returned -1 (error) and the thread returns exit code 0.
const int kTrayEventThreadEndedLoopError = 2006;

typedef TrayEventCallback = Void Function(Int32);

typedef _StartC = IntPtr Function(Pointer<NativeFunction<TrayEventCallback>>);
typedef _StartDart = int Function(Pointer<NativeFunction<TrayEventCallback>>);
typedef _NotifyC = Int32 Function(
    Uint32, Pointer<Uint8>, Pointer<Uint32>, Pointer<Int32>);
typedef _NotifyDart = int Function(
    int, Pointer<Uint8>, Pointer<Uint32>, Pointer<Int32>);
typedef _SetMenuC = Int32 Function(Pointer<Utf16>);
typedef _SetMenuDart = int Function(Pointer<Utf16>);
typedef _LoadIconC = IntPtr Function(Pointer<Utf16>, Int32, Int32, Uint32);
typedef _LoadIconDart = int Function(Pointer<Utf16>, int, int, int);
typedef _StopC = Int32 Function();
typedef _StopDart = int Function();

/// Outcome of one `Shell_NotifyIconW` call on the tray thread.
class TrayNotifyResult {
  /// The BOOL of `Shell_NotifyIconW` (0 = rejected). Read through
  /// `trayIconAccepted` (native_tray_windows.dart).
  final int result;

  /// `GetLastError()` on the tray thread right after the call — or the
  /// error of the hand-over itself (1460 ERROR_TIMEOUT: the thread did not
  /// answer within 5 s; 1400 ERROR_INVALID_WINDOW_HANDLE: no window).
  final int lastError;

  /// `IsWindow` of the tray window right after the call.
  final bool windowAlive;

  const TrayNotifyResult(this.result, this.lastError, this.windowAlive);
}

/// The five entry points of `cleona_tray.dll`.
class TrayThreadLibrary {
  final _StartDart _start;
  final _NotifyDart _notify;
  final _SetMenuDart _setMenu;
  final _LoadIconDart _loadIcon;
  final _StopDart _stop;

  TrayThreadLibrary._(DynamicLibrary lib)
      : _start = lib.lookupFunction<_StartC, _StartDart>('cleona_tray_start'),
        _notify =
            lib.lookupFunction<_NotifyC, _NotifyDart>('cleona_tray_notify'),
        _setMenu = lib
            .lookupFunction<_SetMenuC, _SetMenuDart>('cleona_tray_set_menu'),
        _loadIcon = lib.lookupFunction<_LoadIconC, _LoadIconDart>(
            'cleona_tray_load_icon'),
        _stop = lib.lookupFunction<_StopC, _StopDart>('cleona_tray_stop');

  /// Opens `cleona_tray.dll`: the bare name first (directory of the
  /// executable), then the bundle root, where windows/runner/CMakeLists.txt
  /// puts it — for the daemon in `bin\` the bundle root is the place that
  /// counts. The same candidate list as `NativeSendPath._openLibrary` uses
  /// for its own library. (No other library is named in this file on
  /// purpose: smoke_native_libraries_inventory takes a file that names a
  /// library and calls `DynamicLibrary.open` as that library's loader.)
  /// Throws a [StateError] naming every candidate when none opens (on Linux
  /// and macOS always: there is no such library).
  static TrayThreadLibrary open() {
    final candidates = <String>['cleona_tray.dll'];
    try {
      candidates.add('${AppPaths.bundleDir}\\cleona_tray.dll');
    } catch (_) {
      // `Platform.resolvedExecutable` can throw in unusual embeddings; then
      // the bare name remains.
    }
    Object? lastError;
    for (final c in candidates) {
      try {
        return TrayThreadLibrary._(DynamicLibrary.open(c));
      } catch (e) {
        lastError = e;
      }
    }
    throw StateError('cleona_tray.dll not loadable. Tried: '
        '${candidates.join(", ")} — last: $lastError');
  }

  /// Starts the tray thread; returns the HWND of its window, 0 on failure.
  /// [onEvent] must stay open until [stop] returned true.
  int start(Pointer<NativeFunction<TrayEventCallback>> onEvent) =>
      _start(onEvent);

  /// `Shell_NotifyIconW(message, nid)` on the tray thread. The thread sets
  /// `hWnd` and `uCallbackMessage` itself and keeps a copy of the record
  /// (to add the icon again after a taskbar restart).
  TrayNotifyResult notify(int message, Pointer<Uint8> nid) {
    final err = calloc<Uint32>();
    final alive = calloc<Int32>();
    try {
      final r = _notify(message, nid, err, alive);
      return TrayNotifyResult(r, err.value, alive.value != 0);
    } finally {
      calloc.free(err);
      calloc.free(alive);
    }
  }

  /// Hands the context menu over (format: [trayMenuSpec]).
  bool setMenu(String spec) {
    final p = spec.toNativeUtf16();
    try {
      return _setMenu(p) != 0;
    } finally {
      calloc.free(p);
    }
  }

  /// `LoadImageW(NULL, path, IMAGE_ICON, cx, cy, flags)` on the tray thread;
  /// the thread destroys these icons when it ends. A null [path] returns
  /// the shared system application icon. 0 = not loaded.
  int loadIcon(String? path, int cx, int cy, int flags) {
    if (path == null) return _loadIcon(nullptr, cx, cy, flags);
    final p = path.toNativeUtf16();
    try {
      return _loadIcon(p, cx, cy, flags);
    } finally {
      calloc.free(p);
    }
  }

  /// Ends the thread (the icon is removed, the window destroyed). True when
  /// the thread has ended within 5 s — only then may the callback given to
  /// [start] be closed.
  bool stop() => _stop() != 0;
}
