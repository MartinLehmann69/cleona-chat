import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

/// Shows/raises the application window.
/// - Linux: GTK3 FFI (gtk_window_present).
/// - macOS: MethodChannel to Swift (NSApp.activate).
/// - Windows: Win32 FFI (FindWindowW + ShowWindow + SetForegroundWindow).
class WindowShow {
  static bool _initialized = false;
  static late void Function(Pointer, int) _gtkWindowPresent;
  static late Pointer Function() _gtkWindowListToplevels;
  static late void Function(Pointer) _gtkWidgetShowAll;

  // Windows
  static bool _winInitialized = false;
  static late int Function(int, int) _showWindow;
  static late int Function(int) _setForegroundWindow;
  static late int Function(Pointer<Utf16>, Pointer<Utf16>) _findWindowW;
  static late int Function(int) _isIconic;

  static const MethodChannel _macChannel =
      MethodChannel('chat.cleona.cleona/window');

  static void _init() {
    if (_initialized || !Platform.isLinux) return;

    try {
      final gtk = DynamicLibrary.open('libgtk-3.so.0');

      _gtkWindowPresent = gtk.lookupFunction<
          Void Function(Pointer, Uint32),
          void Function(Pointer, int)>('gtk_window_present_with_time');

      _gtkWindowListToplevels = gtk.lookupFunction<
          Pointer Function(),
          Pointer Function()>('gtk_window_list_toplevels');

      _gtkWidgetShowAll = gtk.lookupFunction<
          Void Function(Pointer),
          void Function(Pointer)>('gtk_widget_show_all');

      _initialized = true;
    } catch (_) {}
  }

  static void _initWindows() {
    if (_winInitialized) return;

    try {
      final user32 = DynamicLibrary.open('user32.dll');

      _showWindow = user32.lookupFunction<
          Int32 Function(IntPtr, Int32),
          int Function(int, int)>('ShowWindow');

      _setForegroundWindow = user32.lookupFunction<
          Int32 Function(IntPtr),
          int Function(int)>('SetForegroundWindow');

      _findWindowW = user32.lookupFunction<
          IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
          int Function(Pointer<Utf16>, Pointer<Utf16>)>('FindWindowW');

      _isIconic = user32.lookupFunction<
          Int32 Function(IntPtr),
          int Function(int)>('IsIconic');

      _winInitialized = true;
    } catch (_) {}
  }

  /// Show/raise the main application window.
  static void show() {
    if (Platform.isMacOS) {
      _macChannel.invokeMethod('show').catchError((_) => null);
      return;
    }
    if (Platform.isWindows) {
      _showWindows();
      return;
    }
    if (!Platform.isLinux) return;
    _init();
    if (!_initialized) return;

    try {
      final toplevels = _gtkWindowListToplevels();
      if (toplevels == nullptr) return;

      var node = toplevels;
      while (node != nullptr) {
        final data = node.cast<Pointer>().value;
        if (data != nullptr) {
          _gtkWidgetShowAll(data);
          _gtkWindowPresent(data, 0);
          break;
        }
        final nextPtr = Pointer<Pointer>.fromAddress(
            node.address + sizeOf<Pointer>());
        node = nextPtr.value;
      }
    } catch (_) {}
  }

  static void _showWindows() {
    _initWindows();
    if (!_winInitialized) return;

    try {
      final className = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
      final hwnd = _findWindowW(className, nullptr.cast());
      calloc.free(className);

      if (hwnd != 0) {
        if (_isIconic(hwnd) != 0) {
          _showWindow(hwnd, 9); // SW_RESTORE
        } else {
          _showWindow(hwnd, 5); // SW_SHOW
        }
        _setForegroundWindow(hwnd);
      }
    } catch (_) {}
  }
}
