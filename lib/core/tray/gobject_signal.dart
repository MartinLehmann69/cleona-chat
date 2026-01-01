// The binding of `g_signal_connect_data` — one place, used by the tray and
// measured by `test/smoke/smoke_tray_signal_connect_abi.dart`.
//
// ── WHY ITS OWN FILE (S409) ──────────────────────────────────────────
//
// Until S409 the tray bound the function with FOUR parameters. The C
// function has SIX (`/usr/include/glib-2.0/gobject/gsignal.h`):
//
//     gulong g_signal_connect_data (gpointer       instance,
//                                   const gchar   *detailed_signal,
//                                   GCallback      c_handler,
//                                   gpointer       data,
//                                   GClosureNotify destroy_data,
//                                   GConnectFlags  connect_flags);
//
// GLib therefore read `destroy_data` and `connect_flags` from whatever the
// registers r8/r9 held. When the tray replaced its menu, libdbusmenu freed
// the old items and `g_closure_unref` CALLED that garbage `destroy_data` —
// a lab daemon died with SIGSEGV one second after its start (S409, report
// S409-TRAY-ABSTURZ.md); with other register contents it would have run
// arbitrary code. A binding in a file of its own lets the smoke measure the
// very function the tray calls, not a copy of it.
import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef _GSignalConnectDataC = UnsignedLong Function(
    Pointer, Pointer<Utf8>, Pointer, Pointer, Pointer, Int32);
typedef _GSignalConnectDataDart = int Function(
    Pointer, Pointer<Utf8>, Pointer, Pointer, Pointer, int);

/// `g_signal_connect_data` with its full signature.
class GObjectSignal {
  GObjectSignal(DynamicLibrary gobject)
      : _connect =
            gobject.lookupFunction<_GSignalConnectDataC, _GSignalConnectDataDart>(
                'g_signal_connect_data');

  final _GSignalConnectDataDart _connect;

  /// Connects [callback] to [signal] of [instance]; returns the handler id.
  ///
  /// [data] is handed to the callback and to [destroyData] (a
  /// `GClosureNotify`, called once when the handler is disconnected or the
  /// instance finalised); both default to "none". [flags] are the
  /// `GConnectFlags` (0 = run after the default handler, no swap).
  int connect(Pointer instance, Pointer<Utf8> signal, Pointer callback,
      {Pointer? data, Pointer? destroyData, int flags = 0}) {
    return _connect(instance, signal, callback, data ?? nullptr,
        destroyData ?? nullptr, flags);
  }
}
