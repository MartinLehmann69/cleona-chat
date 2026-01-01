import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart';

/// Shows/raises the application window.
/// - Linux: GTK3 FFI (gtk_window_present).
/// - macOS: MethodChannel to Swift (NSApp.activate).
/// - Windows: no-op (Windows variant uses native_tray_windows to restore).
class WindowShow {
  static bool _initialized = false;
  static late void Function(Pointer, int) _gtkWindowPresent;
  static late Pointer Function() _gtkWindowListToplevels;
  static late void Function(Pointer) _gtkWidgetShowAll;

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
    } catch (_) {
      // Silently fail — window show will be a no-op
    }
  }

  /// Show/raise the main application window.
  static void show() {
    if (Platform.isMacOS) {
      // Fire-and-forget — platform side handles NSApp.activate + window orderFront.
      _macChannel.invokeMethod('show').catchError((_) => null);
      return;
    }
    if (!Platform.isLinux) return;
    _init();
    if (!_initialized) return;

    try {
      final toplevels = _gtkWindowListToplevels();
      if (toplevels == nullptr) return;

      // GList struct: { void *data, GList *next, GList *prev }
      var node = toplevels;
      while (node != nullptr) {
        final data = node.cast<Pointer>().value;
        if (data != nullptr) {
          _gtkWidgetShowAll(data);
          _gtkWindowPresent(data, 0);
          break;
        }
        // Move to next: offset 1 pointer-width
        final nextPtr = Pointer<Pointer>.fromAddress(
            node.address + sizeOf<Pointer>());
        node = nextPtr.value;
      }
    } catch (_) {
      // Ignore errors — best effort
    }
  }
}
