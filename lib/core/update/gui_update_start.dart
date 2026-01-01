import 'dart:async';
import 'dart:io';

import 'package:cleona/core/platform/app_paths.dart';
import 'package:cleona/core/update/binary_update_manager.dart';

/// The window's part of the desktop safety net (v4_2 §26.5.4: "automatic
/// recovery if the app crashes within 30 s of an update"; owner decision
/// 19.10.2026: "the app" includes the window — S407-RUECKNAHME R-2).
///
/// Linux and Windows only: there the window and the daemon are two processes
/// of one bundle, and until S407 only the daemon reported the update healthy
/// — a window that crashed at its start was never rolled back. macOS, iOS and
/// Android have no desktop update marker (no in-network desktop update on
/// macOS/iOS, the system installer on Android) and are left alone.
///
/// The marker fields (all optional — a marker written by v4.2.3 has none):
///   `guiStartedAt`  the first window start of the new version recorded
///                   itself;
///   `guiHealthy`    that window ran 30 s;
///   `daemonHealthy` the daemon ran 30 s.
/// Marker and backup go when both are healthy, or when the daemon is healthy
/// and no window started ([BinaryUpdateManager.markDaemonHealthy]). A window
/// start that finds `guiStartedAt` without `guiHealthy` follows a window that
/// neither ran 30 s nor ended in order — it rolls back.
class GuiUpdateStart {
  /// Run once at the window's start, after its single-instance check.
  /// [command] is this window's command line (`[0]` = the program in the
  /// bundle); it is started again after a Linux rollback. Returns `true` when
  /// a rollback is under way and the caller must end the process.
  static Future<bool> atStart({
    required List<String> command,
    String? profileDir,
    void Function(String) log = _noLog,
    Duration healthyAfter = const Duration(seconds: 30),
  }) async {
    if (!(Platform.isLinux || Platform.isWindows)) return false;
    switch (BinaryUpdateManager.guiStartAfterUpdate(profileDir)) {
      case UpdateStart.none:
        return false;
      case UpdateStart.first:
        log('first window start after an update — healthy after '
            '${healthyAfter.inSeconds} s');
        Timer(healthyAfter, () => BinaryUpdateManager.markGuiHealthy(profileDir));
        return false;
      case UpdateStart.crashed:
        log('the previous window start after the update ended within 30 s '
            'without an orderly exit — rolling back (§26.5.4)');
        return rollBack(command: command, profileDir: profileDir, log: log);
    }
  }

  /// Restore the previous bundle and start it again.
  ///
  /// Windows: the helper script of the daemon's rollback
  /// ([BinaryUpdateManager.writeWindowsRollback]) — it ends daemon and window
  /// (running .exe files cannot be replaced), mirrors the backup back, removes
  /// backup and marker, and starts daemon and window. Linux: end the daemon of
  /// the new version (SIGTERM, then SIGKILL), mirror the backup back, start
  /// this window again from the restored bundle — it starts the daemon of the
  /// previous version as on every start. Without a backup or when the copy
  /// fails, the marker goes and the update stays: kept, every later window
  /// start would try again without end.
  static Future<bool> rollBack({
    required List<String> command,
    String? profileDir,
    void Function(String) log = _noLog,
  }) async {
    final program = command.first;
    if (Platform.isWindows) {
      final bat = BinaryUpdateManager.writeWindowsRollback(program, profileDir);
      if (bat == null) {
        log('no marker for the rollback — the update stays');
        return false;
      }
      final winPath = bat.replaceAll('/', '\\');
      log('spawning update-rollback.bat: $winPath — exiting');
      await Process.start('cmd.exe', ['/c', 'start', '/MIN', '', winPath],
          mode: ProcessStartMode.detached);
      return true;
    }
    if (!Platform.isLinux) return false;
    await stopDaemonLinux(profileDir, log);
    if (!BinaryUpdateManager.rollback(program, profileDir)) {
      log('rollback failed — the update stays');
      BinaryUpdateManager.dropMarker(profileDir);
      return false;
    }
    log('rolled back to the previous bundle — restarting the window');
    final quoted =
        command.map((p) => "'${p.replaceAll("'", r"'\''")}'").join(' ');
    await Process.start('/bin/bash', ['-c', 'sleep 3 && exec $quoted'],
        mode: ProcessStartMode.detached);
    return true;
  }

  /// Ends the daemon named in `cleona.pid` (Linux) and waits for it. Only a
  /// process whose name is the daemon's is touched: a stale PID file may name
  /// a recycled PID. The AOT daemon runs as `dart:cleona-dae` (the Dart
  /// runtime prefixes `comm`), a renamed copy as `cleona-daemon`.
  static Future<void> stopDaemonLinux(
      String? profileDir, void Function(String) log) async {
    final pidFile = File('${profileDir ?? AppPaths.dataDir}/cleona.pid');
    int? p;
    try {
      p = int.parse(pidFile.readAsStringSync().trim());
    } catch (_) {
      return;
    }
    String? comm() {
      final r = Process.runSync('ps', ['-p', '$p', '-o', 'comm=']);
      if (r.exitCode != 0) return null;
      final n = (r.stdout as String).trim();
      return n.isEmpty ? null : n;
    }

    final name = comm();
    if (name == null || !name.contains('cleona-dae')) return;
    log('ending daemon PID $p ($name) before the rollback');
    Process.killPid(p, ProcessSignal.sigterm);
    for (var i = 0; i < 150 && comm() != null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (comm() != null) {
      log('daemon PID $p did not end within 15 s — SIGKILL');
      Process.killPid(p, ProcessSignal.sigkill);
      for (var i = 0; i < 20 && comm() != null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  static void _noLog(String _) {}
}
