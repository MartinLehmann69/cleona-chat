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
