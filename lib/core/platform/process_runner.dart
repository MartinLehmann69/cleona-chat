// Shared child-process runner with a hard, enforced deadline.
//
// Extracted from `ClipboardHelper._runWithTimeout` so that every code path
// which shells out to an external tool (clipboard helpers, archive transports)
// gets the same guarantee: no unbounded wait for the caller AND no orphaned
// child process left behind.

import 'dart:async';
import 'dart:io';

/// Runs external processes with a deadline that also terminates the child.
class ProcessRunner {
  /// Run an external process with a hard timeout.
  ///
  /// [Process.run] has no timeout parameter, and many network/IPC tools block
  /// indefinitely when their peer accepts a connection and then stops
  /// answering (a frozen SMB server, a spun-down NAS, a firewall that starts
  /// DROPping after the session is up, an X selection owner that never
  /// replies). Wrapping [Process.run] in `.timeout()` only unblocks the
  /// caller — the child is *leaked*, because `Process.run` never hands out a
  /// [Process] handle to kill. This helper keeps the handle and SIGKILLs the
  /// child when the deadline fires.
  ///
  /// Returns `null` on timeout or when the process cannot be started at all;
  /// callers MUST treat that exactly like a non-zero exit code.
  ///
  /// [environment] is merged into the inherited environment (same semantics as
  /// `Process.run(..., includeParentEnvironment: true)`).
  /// With [binaryStdout] the stdout bytes are returned unchanged (no character
  /// decoding), matching `Process.run(..., stdoutEncoding: null)`.
  static Future<ProcessResult?> run(
    String executable,
    List<String> args, {
    required Duration timeout,
    Map<String, String>? environment,
    bool binaryStdout = false,
  }) async {
    final Process proc;
    try {
      proc = await Process.start(executable, args, environment: environment);
    } catch (_) {
      return null;
    }
    final stdoutBytes = <int>[];
    final stderrBytes = <int>[];
    // Drain both pipes concurrently — an undrained pipe buffer would block the
    // child even without a hanging peer.
    final stdoutDone = proc.stdout.listen(stdoutBytes.addAll).asFuture<void>();
    final stderrDone = proc.stderr.listen(stderrBytes.addAll).asFuture<void>();
    var exitCode = -1;
    try {
      await Future.wait<void>([
        proc.exitCode.then<void>((c) => exitCode = c),
        stdoutDone,
        stderrDone,
      ]).timeout(timeout);
    } on TimeoutException {
      proc.kill(ProcessSignal.sigkill);
      return null;
    } catch (_) {
      proc.kill(ProcessSignal.sigkill);
      return null;
    }
    return ProcessResult(
      proc.pid,
      exitCode,
      binaryStdout ? stdoutBytes : decodeBytes(stdoutBytes),
      decodeBytes(stderrBytes),
    );
  }

  /// Decode process output with the system encoding, falling back to a raw
  /// code-unit interpretation when the bytes are not valid in that encoding.
  static String decodeBytes(List<int> bytes) {
    try {
      return systemEncoding.decode(bytes);
    } catch (_) {
      return String.fromCharCodes(bytes);
    }
  }
}
