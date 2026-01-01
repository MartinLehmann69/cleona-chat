import 'dart:io';

import 'package:cleona/core/log/log_redaction.dart';

/// The only way product code writes a line straight to stdout/stderr.
///
/// ── WHY THIS FILE EXISTS (S403) ─────────────────────────────────
///
/// The GUI starts the daemon with stdout and stderr redirected into
/// `logs/daemon-stdio.log` (`lib/main.dart`, `_prepareDaemonStdioLog`), and
/// the Windows launcher does the same with stderr. §4.5.3 leaves log files
/// unencrypted on the condition that the logger redacts display names, the
/// host name, private IP addresses and the home directory path. That held
/// for every line that went through `CLogger` — and for none of the lines
/// that code wrote with a bare `stderr.writeln(...)`: the identity manager,
/// the first-start wipe, file encryption, the atomic writers, the daemon's
/// start-up refusals. They named files, paths and identity names in that
/// file in plaintext.
///
/// The redaction is process-wide state ([LogRedaction] registers names and
/// paths statically, and discovers the home directory and host name by
/// itself), so a line sent through here is redacted exactly as a `CLogger`
/// line of the same process would be. What it cannot know is a name that has
/// not been registered yet when the line is written — a line written before
/// any identity is loaded still has the home directory, foreign home
/// directories, the host name and IP addresses redacted, but no display name.
///
/// What this does NOT cover: whatever the Dart runtime itself writes to
/// stderr (an unhandled exception that escapes every zone, a VM crash
/// message). That text never passes through Dart code that could redact it.
///
/// The guard `test/smoke/smoke_stderr_goes_through_redaction.dart` turns red
/// for every direct `stderr`/`stdout` write in `lib/` and `bin/` outside this
/// file and its short, reasoned exception list.
abstract final class RedactedConsole {
  /// Writes [line] to stderr after redaction. Same sink, same synchronous
  /// semantics as the `stderr.writeln` it replaces.
  static void err(String line) => stderr.writeln(LogRedaction.apply(line));

  /// Writes [line] to stdout after redaction.
  static void out(String line) => stdout.writeln(LogRedaction.apply(line));
}
