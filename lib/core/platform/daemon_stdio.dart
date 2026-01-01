/// How the GUI starts the daemon on Linux so that its output survives the GUI
/// (S395, S407-KLEIN3).
///
/// The daemon runs behind `setsid` in a session of its own; a pipe to the GUI
/// would break with the GUI, a file does not. The shell between `setsid` and
/// the daemon redirects the daemon's own descriptors and then `exec`s it, so
/// the process tree is unchanged and the exit status the GUI reaps is the
/// daemon's own.
///
/// ONLY stderr goes into `daemon-stdio.log`. stderr is what nothing else
/// records: the Dart VM's crash report on a segmentation fault (S394-4), the
/// messages written before the logger exists (`RedactedConsole.err`), and
/// every ERROR line a second time, written synchronously (`CLogger._write`).
/// stdout carries nothing but the console copy of every INFO+ log line
/// (`CLogger._write`, the one `print` in `lib/`), which the logger already
/// writes into `logs/cleona_*.log` (and the identity's own log) — sending it
/// into the file as well put the whole daemon log there twice (S395-2: 327 KB
/// next to a 342 KB day log after 20 min on node1), and the file is only cut
/// at the next start, so it grew for as long as the daemon ran. Windows does
/// the same since S397: `2>>log >NUL`.
///
/// What this gives up, measured on node1 (09.10.2026, S407-KLEIN3): the
/// INFO/WARN lines of the last moments before a HARD end (SIGKILL, VM crash)
/// that the 2 s file flush of `CLogger` no longer wrote — there the stdout
/// copy was their only record (`SIGTERM received` … `Plane D: deregistered`,
/// 12:01:45, absent from the day log that ends at 12:01:42). ERROR lines and
/// the VM's own crash report still arrive, they go through stderr.
library;

import 'dart:io';

/// The argument list for `Process.start('setsid', …)`: `sh -c` appends the
/// daemon's stderr to [stdioLog], discards its stdout, and execs
/// [daemonBinary] with [args]. The log path and the binary are passed as
/// positional parameters, never spliced into the script text.
List<String> linuxDaemonLaunchArgs(
        String stdioLog, String daemonBinary, List<String> args) =>
    [
      'sh', '-c', r'log=$1; shift; exec "$@" >/dev/null 2>>"$log"',
      'sh', stdioLog, daemonBinary, ...args,
    ];

// ── Windows (S397, S418 W-1-D) ─────────────────────────────────────────
//
// The Windows daemon is a GUI-subsystem program without a console: whatever
// starts it without a redirection loses its stderr — and with it the reason
// of a Dart VM abort (0xc0000409, W-1). Until S418 only the GUI redirected;
// the autostart entry of the installer, `update-apply.bat`,
// `update-rollback.bat` and the lab's scheduled tasks started the .exe
// directly. A redirection in each of those would need a `cmd.exe` in the
// autostart entry, which shows a console window at every login. Instead the
// daemon itself starts once more through the same launcher as the GUI when
// nobody redirected it ([windowsDaemonNeedsRelaunch]); every start path is
// covered by one mechanism.

/// Set by the launcher; its presence means "stderr goes into the file".
const String kDaemonStderrEnv = 'CLEONA_DAEMON_STDERR';

/// `<baseDir>/logs/daemon-stdio.log`, created if missing and cut to its last
/// 512 KB above 1 MB (the file is only appended to). Returns the path; a
/// failure to prepare it is returned as [error], the path stays usable.
({String path, Object? error}) prepareDaemonStdioLog(String baseDir) {
  final path = '$baseDir/logs/daemon-stdio.log';
  try {
    Directory('$baseDir/logs').createSync(recursive: true);
    final f = File(path);
    if (f.existsSync() && f.lengthSync() > 1024 * 1024) {
      final bytes = f.readAsBytesSync();
      f.writeAsBytesSync(bytes.sublist(bytes.length - 512 * 1024), flush: true);
    }
    return (path: path, error: null);
  } catch (e) {
    return (path: path, error: e);
  }
}

/// The text of `daemon-start.cmd`: marks the start as redirected, then runs
/// [daemonBinary] with [args], stderr appended to [stdioLog], stdout to NUL.
/// A launcher file and not an inline `cmd /c` line: Dart quotes arguments
/// with backslash escapes, which cmd.exe does not understand.
String windowsDaemonLauncherScript(
    String stdioLog, String daemonBinary, List<String> args) {
  final line = [daemonBinary, ...args].map((a) => '"$a"').join(' ');
  return '@set "$kDaemonStderrEnv=1"\r\n'
      '@$line 2>>"${stdioLog.replaceAll('/', r'\')}" >NUL\r\n';
}

/// Writes `<baseDir>/daemon-start.cmd` and starts it detached — no console
/// window (S407): `cmd.exe` starts detached, the daemon is a GUI-subsystem
/// program, and the redirection still reaches it.
Future<void> startWindowsDaemonWithStdioLog(
    String baseDir, String daemonBinary, List<String> args) async {
  final stdioLog = prepareDaemonStdioLog(baseDir).path;
  final launcher = File('$baseDir/daemon-start.cmd'); // not a log
  launcher.writeAsStringSync(
      windowsDaemonLauncherScript(stdioLog, daemonBinary, args));
  await Process.start(
      'cmd.exe', ['/d', '/c', launcher.path.replaceAll('/', r'\')],
      mode: ProcessStartMode.detached);
}

/// Whether a Windows daemon must start itself again through the launcher:
/// nobody marked its start as redirected, and its stderr is no console a
/// person reads (a developer's terminal keeps the output where it is).
bool windowsDaemonNeedsRelaunch(
        {required bool isWindows,
        required Map<String, String> environment,
        required bool stderrIsTerminal}) =>
    isWindows && !environment.containsKey(kDaemonStderrEnv) && !stderrIsTerminal;
