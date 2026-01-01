import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Windows sessions: can a process show an icon in the notification area of THIS
/// user?
///
/// ── THE FINDING THAT TRIGGERED THIS FILE (finding 4, S370) ───────
///
/// `main.dart`'s `_daemonHasDisplay()` returned `true` unconditionally on Windows.
/// The GUI thus never replaced a daemon without a notification area —
/// while `NativeTrayWindows.init` at the same time reported "Tray icon: OK",
/// because it discarded the return value of `Shell_NotifyIcon`. Both halves
/// together produced a tray contract that nothing checks on Windows.
///
/// Measured on 06.09.2026 on the Windows build VM 192.168.10.74:
///
///   PS> Get-Process cleona-daemon | Select Id,SessionId  ->  5156, session 0
///   PS> Get-Process explorer      | Select Id,SessionId  ->  2264, session 3
///
/// A process in session 0 has no shell and thus no notification area.
/// `Shell_NotifyIcon` fails there, `CreateWindowExW` does not — that is why
/// the daemon saw itself as successful.

/// Pure decision: can a daemon in [daemonSession] show an icon in the
/// notification area of the GUI in [guiSession]?
///
/// The order of the cases is the whole content of this function, and
/// every case has a reason:
///
///  1. **Unknown (`null`) → `true`.** The only consumer of this
///     statement KILLS the daemon if it is `false`
///     (`main.dart:_ensureDaemonRunning` → `_killExistingDaemon`). A
///     failed measurement must therefore never mean "no": that would be
///     a kill loop on every GUI start. In doubt it stays with the
///     behaviour from before S370.
///  2. **The GUI itself sits in session 0 → `true`.** Then there is
///     no interactive session at all into which the daemon could be
///     replaced; a restart changes nothing and only costs
///     the running delivery.
///  3. **The daemon sits in session 0 → `false`.** That is the measured
///     case: no notification area, no icon, and a replacement in the session
///     of the GUI fixes it.
///  4. **Same session → `true`, otherwise `false`.** A daemon in a
///     DIFFERENT interactive session (second logged-on user) shows
///     its icon there — not where this user is looking. For the
///     statement "the user sees an icon" that is a no.
bool windowsDaemonCanShowTray({
  required int? daemonSession,
  required int? guiSession,
}) {
  if (daemonSession == null || guiSession == null) return true;
  if (guiSession == 0) return true;
  if (daemonSession == 0) return false;
  return daemonSession == guiSession;
}

/// Windows session identifier of a process, or `null` if it cannot be
/// determined (different operating system, process gone, missing permission).
///
/// `null` is expressly a valid result and means "not
/// measured", not "session 0" — [windowsDaemonCanShowTray] treats it
/// accordingly.
int? windowsSessionIdOf(int processId) {
  if (!Platform.isWindows) return null;
  if (processId <= 0) return null;
  Pointer<Uint32>? out;
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final processIdToSessionId = kernel32.lookupFunction<
        Int32 Function(Uint32, Pointer<Uint32>),
        int Function(int, Pointer<Uint32>)>('ProcessIdToSessionId');
    out = calloc<Uint32>();
    // BOOL: null means failure. Then the session is UNKNOWN.
    if (processIdToSessionId(processId, out) == 0) return null;
    return out.value;
  } catch (_) {
    return null;
  } finally {
    if (out != null) calloc.free(out);
  }
}
