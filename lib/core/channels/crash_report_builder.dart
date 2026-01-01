import 'dart:convert';
import 'dart:io';

import '../log/clogger.dart';
import '../log/log_redaction.dart';
import '../service/app_version.dart';
import 'system_channels.dart';

/// Builds the crash report of §16.7 for a process that may not hold a
/// `CleonaService` of its own.
///
/// S417 W-1: on Linux, Windows and macOS with a daemon the window is an IPC
/// client; the only `CrashReporter` lived on the in-process service, so a
/// crash of the window never reached the opt-in popup. The report is built
/// here from what the calling process knows; `CrashReporter.buildReport`
/// passes the values of its service.
///
/// Nothing is posted here — the report goes to the opt-in popup with its
/// preview (`showCrashReportDialog`), and only the user's choice there
/// deposits it.
CrashReport buildCrashReport(
  Object error,
  StackTrace stackTrace, {
  required DateTime startedAt,
  required int peerCount,
}) {
  final exType = error.runtimeType.toString();
  final exMsg = error.toString();
  final rawStack = stackTrace.toString();

  final fingerprint = computeCrashFingerprint(exType, rawStack);

  final truncatedStack = rawStack
      .split('\n')
      .take(SystemChannels.maxStackFrames)
      .map(normalizeCrashPath)
      .join('\n');

  int memBytes = 0;
  try {
    memBytes = ProcessInfo.currentRss;
  } catch (_) {}

  return CrashReport(
    fingerprint: fingerprint,
    appVersion: kAppVersion,
    platform: crashPlatformString(),
    dartVersion: Platform.version.split(' ').first,
    timestampMs: DateTime.now().millisecondsSinceEpoch,
    exceptionType: exType,
    exceptionMsg: _truncateMsg(exMsg),
    stackTrace: truncatedStack,
    logTail: CLogger.getReportLines(SystemChannels.maxLogTailLines).join('\n'),
    peerCount: peerCount,
    uptimeSeconds: DateTime.now().difference(startedAt).inSeconds,
    memoryBytes: memBytes,
  );
}

String _truncateMsg(String msg) => msg.length > SystemChannels.maxExceptionMsgChars
    ? msg.substring(0, SystemChannels.maxExceptionMsgChars)
    : msg;

/// `<os>-<arch>` of this process, as every crash and log report names it.
String crashPlatformString() {
  final os = Platform.operatingSystem;
  String arch = 'unknown';
  try {
    final info = Platform.version;
    if (info.contains('x64') || info.contains('x86_64')) {
      arch = 'x86_64';
    } else if (info.contains('arm64') || info.contains('aarch64')) {
      arch = 'arm64';
    } else if (info.contains('arm')) {
      arch = 'arm';
    }
  } catch (_) {}
  return '$os-$arch';
}

/// Cuts the installation path in front of `lib/` from a stack frame.
String normalizeCrashPath(String frame) {
  return frame
      .replaceAll(RegExp(r'/home/[^ ]*/lib/'), 'lib/')
      .replaceAll(RegExp(r'C:\\[^ ]*\\lib\\'), 'lib/')
      .replaceAll(RegExp(r'/data/[^ ]*/lib/'), 'lib/');
}

/// A daemon that vanished under the window without an orderly stop
/// (S417 W-1, §16.7 "Crash reports only after an opt-in popup").
///
/// The window notices the daemon's end (`IpcClient.onDaemonDied`), writes
/// `crash-daemon.log` and ends itself. A crash of the daemon cannot be caught
/// in the daemon (a native abort such as 0xc0000409 ends the process at
/// once), so the report is built from what the window holds at that moment:
/// the exit status line and the tail of the daemon's stderr
/// (`logs/daemon-stdio.log`), both through [LogRedaction] — the same text
/// `crash-daemon.log` keeps. The record lies beside that log until the
/// window, at its next start with a running daemon, shows it in the opt-in
/// popup; it is removed when the popup is shown, so each crash is offered
/// at most once. A newer crash before that replaces the record.
class DaemonExitRecord {
  /// The file in the profile directory, beside `crash-daemon.log`.
  static const String fileName = 'crash-daemon-pending.json';

  /// The exception type the report carries: a daemon end has no Dart
  /// exception the window could name.
  static const String exceptionType = 'DaemonExit';

  final int detectedAtMs;

  /// The line of `crash-daemon.log`, e.g. "Exit status: killed by signal 6".
  final String exitStatus;

  /// The tail of `daemon-stdio.log` as `crash-daemon.log` holds it.
  final String stdioTail;

  /// The version the daemon reported over IPC; empty when unknown.
  final String daemonVersion;

  /// The daemon's last reported count of independent sync partners.
  final int peerCount;

  DaemonExitRecord({
    required this.detectedAtMs,
    required String exitStatus,
    required String stdioTail,
    required this.daemonVersion,
    required this.peerCount,
  })  : exitStatus = LogRedaction.apply(exitStatus),
        stdioTail = LogRedaction.apply(stdioTail);

  Map<String, dynamic> toJson() => {
        'detectedAtMs': detectedAtMs,
        'exitStatus': exitStatus,
        'stdioTail': stdioTail,
        'daemonVersion': daemonVersion,
        'peerCount': peerCount,
      };

  static DaemonExitRecord? fromJson(Map<String, dynamic> json) {
    try {
      return DaemonExitRecord(
        detectedAtMs: json['detectedAtMs'] as int,
        exitStatus: json['exitStatus'] as String,
        stdioTail: json['stdioTail'] as String,
        daemonVersion: json['daemonVersion'] as String,
        peerCount: json['peerCount'] as int,
      );
    } catch (_) {
      return null;
    }
  }

  /// Did the daemon stop in order? Its orderly stop (`shutdownAll` ->
  /// `stopAll`, tray "Quit", SIGTERM) deletes `cleona.pid` and exits with 0;
  /// the window notices that end exactly like a crash. A pid file still
  /// present, or a known exit status other than 0, is no orderly stop.
  /// [exitCode] is null when the window does not hold the status (Windows,
  /// a daemon it did not start).
  static bool endedInOrder({required bool pidFileLeft, int? exitCode}) =>
      !pidFileLeft && (exitCode == null || exitCode == 0);

  static File _file(String baseDir) => File('$baseDir/$fileName');

  /// Writes the record into [baseDir], readable by the owner only (like
  /// `crash-daemon.log`, §23.10). Replaces an earlier record.
  void save(String baseDir) {
    final f = _file(baseDir);
    Directory(baseDir).createSync(recursive: true);
    f.writeAsStringSync(jsonEncode(toJson()), flush: true);
    if (Platform.isLinux || Platform.isMacOS) {
      try {
        Process.runSync('chmod', ['600', f.path]);
      } catch (_) {/* best-effort owner-only permission */}
    }
  }

  /// The record waiting in [baseDir], or null. An unreadable record is
  /// removed — there is nothing in it that could be offered.
  static DaemonExitRecord? load(String baseDir) {
    final f = _file(baseDir);
    try {
      if (!f.existsSync()) return null;
      final decoded = jsonDecode(f.readAsStringSync());
      final record = decoded is Map<String, dynamic> ? fromJson(decoded) : null;
      if (record == null) drop(baseDir);
      return record;
    } catch (_) {
      drop(baseDir);
      return null;
    }
  }

  /// Removes the record — called when the popup shows it.
  static void drop(String baseDir) {
    try {
      final f = _file(baseDir);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  /// The crash report of this daemon end. The last
  /// [SystemChannels.maxStackFrames] lines of the stderr tail stand in the
  /// place of the stack (the Dart runtime writes the reason of a fatal abort
  /// there, and the daemon's zone handler its unhandled error); the lines
  /// before them form the log tail, so the two together are exactly the
  /// tail `crash-daemon.log` keeps. The fingerprint is
  /// [computeCrashFingerprint] over type and that stack, like every crash
  /// report. Uptime and memory of the daemon are unknown to the window and
  /// stay 0 — not estimated.
  CrashReport toReport() {
    final lines = stdioTail.split('\n').map(normalizeCrashPath).toList();
    final split = lines.length > SystemChannels.maxStackFrames
        ? lines.length - SystemChannels.maxStackFrames
        : 0;
    final stack = lines.sublist(split).join('\n');
    var before = lines.sublist(0, split);
    if (before.length > SystemChannels.maxLogTailLines) {
      before = before.sublist(before.length - SystemChannels.maxLogTailLines);
    }
    return CrashReport(
      fingerprint: computeCrashFingerprint(exceptionType, stack),
      appVersion: daemonVersion.isEmpty ? kAppVersion : daemonVersion,
      platform: crashPlatformString(),
      dartVersion: Platform.version.split(' ').first,
      timestampMs: detectedAtMs,
      exceptionType: exceptionType,
      exceptionMsg: _truncateMsg(exitStatus),
      stackTrace: stack,
      logTail: before.join('\n'),
      peerCount: peerCount,
      uptimeSeconds: 0,
      memoryBytes: 0,
    );
  }
}
