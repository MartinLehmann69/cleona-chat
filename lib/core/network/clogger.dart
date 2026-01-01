import 'dart:async';
import 'dart:io';

import 'package:cleona/core/crypto/network_secret.dart';

/// Log levels, ordered by increasing severity.
///
/// [trace] sits below [debug] and exists for one purpose: per-destination
/// send-path decisions whose content is constant for a whole round (default-
/// gateway skip, fire-and-forget cut-off, relay cooldown). A node with a few
/// hundred peers emits these hundreds of times in milliseconds. They stay in
/// the log file — where they are genuinely useful for field RCA — but are
/// kept out of the crash-reporter ring, which holds only 500 lines and feeds
/// the 200-line tail of every bug report (§9.5.8). Without the split, a
/// single DHT round fills the whole report window and the actual incident
/// scrolls out. Same rationale as the module-based transport filter in
/// [getReportLines], but resolved per call site instead of per module.
enum LogLevel { trace, debug, info, warn, error }

/// Per-directory sink state for segment rotation (S120 log retention).
class _LogSinkState {
  String date;
  int segment;
  int bytesInSegment;
  DateTime lastCleanup;
  _LogSinkState(this.date, this.segment, this.bytesInSegment, this.lastCleanup);
}

class CLogger {
  static final Map<String, CLogger> _instances = {};
  static final Map<String, StringBuffer> _buffers = {};
  static Timer? _flushTimer;

  // -- Log retention (S120) --------------------------------------------------
  // Two-dimensional retention: age cap AND total-size budget per logs/ dir.
  // Guarantee: files of today and yesterday are exempt from the BUDGET rule
  // (>=24h coverage), but a runaway day is bounded by the per-day segment cap
  // (oldest segments of that day are dropped first, the newest edge — the
  // most valuable evidence — survives). Segment 0 keeps the legacy name
  // cleona_DATE.log; further segments are cleona_DATE.N.log.
  // Values are channel-specific: beta keeps a week of DEBUG logs for field
  // RCA, live keeps a lean 3 days. Static and overridable for tests.
  static int retentionDays =
      NetworkSecret.channel == NetworkChannel.live ? 3 : 7;
  static int totalBudgetBytes = NetworkSecret.channel == NetworkChannel.live
      ? 50 * 1024 * 1024
      : 200 * 1024 * 1024;
  static int segmentBytes = NetworkSecret.channel == NetworkChannel.live
      ? 16 * 1024 * 1024
      : 64 * 1024 * 1024;
  static int maxSegmentsPerDay =
      NetworkSecret.channel == NetworkChannel.live ? 3 : 4;

  static const Duration _cleanupInterval = Duration(hours: 6);
  static final Map<String, _LogSinkState> _sinkStates = {};
  static final RegExp _logFileRe =
      RegExp(r'^cleona_(\d{4}-\d{2}-\d{2})(?:\.(\d+))?\.log$');

  /// Whether console sinks (stdout/stderr) may still be written to.
  ///
  /// A daemon started WITHOUT a console — Windows autostart, the E2E VBS
  /// wrapper (`WScript.Shell.Run(exe, 0, False)`), any service manager — has
  /// no valid stdout/stderr handle. Dart's stdout/stderr are ASYNCHRONOUSLY
  /// buffered, so the write fails later during flush inside
  /// `_StdConsumer.addStream`, i.e. OUTSIDE the try/catch guarding the call.
  /// The resulting unhandled zone error is reported via the zone handler,
  /// which logs at ERROR level — which writes to stderr again, producing the
  /// next failure. That feedback loop, not a single write, is what kills the
  /// daemon (measured 2026-08-05: dead within 151s, no cleona.port; with
  /// redirected handles the same build runs indefinitely).
  ///
  /// Once a console write fails, all console output is switched off process-
  /// wide. File buffers and the ring buffer are unaffected — nothing that is
  /// diagnostically relevant is lost, because without a console the lines had
  /// nowhere to go anyway.
  static bool consoleEnabled = true;

  /// Disable console output permanently after a failed write.
  /// Deliberately silent: reporting this problem through the logger is exactly
  /// the recursion this guard exists to break.
  static void disableConsole(String sink) {
    consoleEnabled = false;
    _ring.add('${DateTime.now().toIso8601String()} [WARN ] [clogger] console '
        'sink "$sink" failed — console output disabled process-wide '
        '(no valid stdout/stderr handle). File logging continues.');
  }

  static bool _sinkWatchRegistered = false;

  /// Watches this process's console sinks and disables console output as soon
  /// as one of them dies.
  ///
  /// A failed stdout/stderr flush NEVER surfaces at the call site: Dart flushes
  /// asynchronously in `_StdConsumer`, so the try/catch around `print`/
  /// `stderr.writeln` in [_log] cannot see it. That is precisely why W-1 killed
  /// the Windows daemon despite those guards — the error escaped to the zone,
  /// the zone handler logged it, and the log wrote to the same dead sink.
  ///
  /// The `done` future is where the error does surface, and it does so in every
  /// process type. Measured 2026-08-05 against a sink whose reader is gone:
  /// bare Dart VM and a compiled Flutter release binary both deliver
  /// `FileSystemException` here — and in the Flutter case
  /// `PlatformDispatcher.onError` is never reached, so the §16.2 invariant
  /// (single global error sink) stays untouched rather than being duplicated
  /// into every entry point (daemon, GUI, foreground service, iOS).
  ///
  /// MUST run before the first console write. Measured: if the flush error
  /// happens first, the future is already completed with an unhandled error and
  /// a `catchError` attached afterwards never fires.
  static void _watchConsoleSinks() {
    if (_sinkWatchRegistered) return;
    _sinkWatchRegistered = true;
    stdout.done.catchError((e) { disableConsole('stdout-done'); return null; });
    stderr.done.catchError((e) { disableConsole('stderr-done'); return null; });
  }

  /// Ring buffer of the most recent log lines (across all modules).
  /// Used by the crash reporter (§9.5) to attach log context to reports.
  static const int _ringCapacity = 500;
  static final List<String> _ring = [];

  /// Separate ring buffer for application-level events (CR, contact state,
  /// KEX, delivery, identity). These are rare but diagnostic-critical and
  /// must not be displaced by high-frequency transport noise.
  static const int _eventCapacity = 200;
  static final List<String> _events = [];

  /// Modules whose DEBUG lines are pure transport noise and should be
  /// excluded from bug reports (but still written to the log file).
  static const _transportModules = {'transport', 'udp-keepalive', 'lan-mcast', 'local-disc'};

  static List<String> getRecentLines([int count = 30]) {
    if (count >= _ring.length) return List.unmodifiable(_ring);
    return List.unmodifiable(_ring.sublist(_ring.length - count));
  }

  /// Returns lines for bug reports: ALL events + filtered log lines
  /// (no DEBUG from transport modules). Much more diagnostic value than
  /// raw tail of the ring buffer.
  static List<String> getReportLines(int maxLines) {
    final filtered = <String>[];
    for (final line in _ring) {
      if (line.contains('[DEBUG]') && _isTransportNoise(line)) continue;
      filtered.add(line);
    }
    if (filtered.length > maxLines) {
      return List.unmodifiable(filtered.sublist(filtered.length - maxLines));
    }
    return List.unmodifiable(filtered);
  }

  static bool _isTransportNoise(String line) {
    for (final m in _transportModules) {
      if (line.contains('[$m]')) return true;
    }
    return false;
  }

  static List<String> getRecentEvents([int count = 200]) {
    if (count >= _events.length) return List.unmodifiable(_events);
    return List.unmodifiable(_events.sublist(_events.length - count));
  }

  /// B1 (2026-07-27): Modulnamen, fuer die der "kein Log-Buffer"-Selbstalarm
  /// bereits ausgegeben wurde (einmal pro Modul, kein Flooding).
  static final Set<String> _blindModulesWarned = {};

  /// iOS: mirror log output to this path (Documents/, AFC-accessible).
  /// Set from main.dart via path_provider before any CLogger is created.
  static String? iosMirrorPath;
  static StringBuffer? _iosMirrorBuffer;

  final String module;
  final String? profileDir;

  CLogger(this.module, {this.profileDir}) {
    if (profileDir != null && !_buffers.containsKey(profileDir)) {
      _buffers[profileDir!] = StringBuffer();
    }
    _ensureFlushTimer();
  }

  factory CLogger.get(String module, {String? profileDir}) {
    final key = '$module:$profileDir';
    return _instances.putIfAbsent(key, () => CLogger(module, profileDir: profileDir));
  }

  /// File-only logging for high-frequency, low-information send-path lines.
  /// See [LogLevel.trace] for why these must not reach the report ring.
  void trace(String msg) => _log(LogLevel.trace, msg);
  void debug(String msg) => _log(LogLevel.debug, msg);
  void info(String msg) => _log(LogLevel.info, msg);
  void warn(String msg) => _log(LogLevel.warn, msg);
  void error(String msg) => _log(LogLevel.error, msg);

  /// Log a diagnostic event that survives transport noise in bug reports.
  /// Use for: CR sent/received/accepted, contact state changes, KEX
  /// decisions, delivery receipts, identity events, QR scans.
  void event(String msg) {
    final now = DateTime.now();
    final ts = now.toIso8601String();
    final line = '$ts [EVENT] [$module] $msg';
    _events.add(line);
    if (_events.length > _eventCapacity) _events.removeAt(0);
    _log(LogLevel.info, msg);
  }

  void _log(LogLevel level, String msg) {
    final now = DateTime.now();
    final ts = now.toIso8601String();
    final levelStr = level.name.toUpperCase().padRight(5);
    final line = '$ts [$levelStr] [$module] $msg';

    // TRACE and DEBUG only go to the file buffer — console output is INFO+.
    // On Android this avoids main-thread I/O flooding; on Windows it
    // prevents the console window from scrolling endlessly with packet-
    // level noise that makes the machine look like "die Hölle ist los".
    // Register the sink watch BEFORE the first console write — see
    // [_watchConsoleSinks]: attaching it after the first failed flush is too
    // late, the future has already completed with an unhandled error.
    if (!_sinkWatchRegistered) _watchConsoleSinks();

    if (consoleEnabled && level != LogLevel.debug && level != LogLevel.trace) {
      try {
        // ignore: avoid_print
        print(line);
      } catch (_) {
        disableConsole('print');
      }
    }

    // ERROR-level: also write to stderr directly (synchronous, no buffer).
    // Survives logger/buffer failure modes; lands in the wrapper's stderr-capture
    // so a stack trace is visible even when the process dies before the 2s
    // periodic flush runs. See C-3 (B-4 daemon crash without trace).
    if (consoleEnabled && level == LogLevel.error) {
      try { stderr.writeln(line); } catch (_) {
        disableConsole('stderr');
      }
    }

    // Ring buffer for crash reporter. TRACE is deliberately excluded: the
    // ring holds 500 lines and feeds the 200-line report tail (§9.5.8), so
    // a few hundred per-destination send-path lines would evict everything
    // diagnostically useful within milliseconds. Field evidence (bug report
    // 2026-07-27): 155 of 199 report lines were two such messages and the
    // report covered only 3.5 s. The lines remain in the file buffer below.
    if (level != LogLevel.trace) {
      _ring.add(line);
      if (_ring.length > _ringCapacity) _ring.removeAt(0);
    }

    // Buffer for file write
    final buffer = profileDir != null ? _buffers[profileDir] : null;
    if (buffer != null) {
      buffer.writeln(line);
    } else if (consoleEnabled && _blindModulesWarned.add(module)) {
      // B1 (2026-07-27) Selbst-Alarm: ein Modul ohne profileDir loggt ins
      // Nichts — die Zeile geht nur in Konsole + Ring-Buffer, NIE in
      // logs/cleona_*.log. Genau so verschwanden alle [resolver]-Zeilen
      // (D1 Trust-Anchor) aus beiden Logfiles. Einmal pro Modulname, damit
      // der Alarm selbst kein Flooding wird; stderr, weil er auch dann
      // sichtbar sein muss, wenn die Datei-Pipeline nicht greift.
      try {
        stderr.writeln('$ts [WARN ] [clogger] Modul "$module" hat keinen '
            'Log-Buffer (profileDir=$profileDir) — seine Zeilen landen in '
            'KEINEM Logfile, nur in Konsole + Ring-Buffer. '
            'CLogger.get("$module", profileDir: ...) durchreichen.');
      } catch (_) {}
    }

    // iOS mirror: duplicate ALL log lines to the AFC-accessible Documents path
    if (iosMirrorPath != null) {
      (_iosMirrorBuffer ??= StringBuffer()).writeln(line);
    }
  }

  static void _ensureFlushTimer() {
    _flushTimer ??= Timer.periodic(const Duration(seconds: 2), (_) => flushAll());
  }

  static Future<void> flushAll() async {
    for (final entry in Map.of(_buffers).entries) {
      final dir = entry.key;
      final buffer = entry.value;
      if (buffer.isEmpty) continue;

      final content = buffer.toString();
      buffer.clear();

      try {
        await _appendToSink(dir, content);
      } catch (_) {
        // Non-fatal: logging should never crash the app
      }
    }

    // iOS mirror flush — writes to Documents/logs/ (AFC-accessible)
    if (iosMirrorPath != null && _iosMirrorBuffer != null && _iosMirrorBuffer!.isNotEmpty) {
      final content = _iosMirrorBuffer!.toString();
      _iosMirrorBuffer!.clear();
      try {
        await _appendToSink(iosMirrorPath!, content);
      } catch (_) {}
    }
  }

  /// Append to the current segment of `$baseDir/logs`, rotating segments and
  /// running retention cleanup (at startup, day roll and every 6h).
  static Future<void> _appendToSink(String baseDir, String content) async {
    final logDir = Directory('$baseDir/logs');
    if (!logDir.existsSync()) {
      logDir.createSync(recursive: true);
    }
    final now = DateTime.now();
    final date = now.toIso8601String().substring(0, 10);

    var state = _sinkStates[baseDir];
    if (state == null || state.date != date) {
      state = _initSinkState(logDir, date, now);
      _sinkStates[baseDir] = state;
      _cleanup(logDir, now);
    }

    final file = File(_segmentPath(logDir, date, state.segment));
    await file.writeAsString(content, mode: FileMode.append);
    state.bytesInSegment += content.length;

    if (state.bytesInSegment >= segmentBytes) {
      state.segment++;
      state.bytesInSegment = 0;
      _enforceDayCap(logDir, date, state.segment);
    }

    if (now.difference(state.lastCleanup) > _cleanupInterval) {
      state.lastCleanup = now;
      _cleanup(logDir, now);
    }
  }

  static String _segmentPath(Directory logDir, String date, int segment) =>
      segment == 0
          ? '${logDir.path}/cleona_$date.log'
          : '${logDir.path}/cleona_$date.$segment.log';

  /// Resume at the highest existing segment of [date] (restart-safe: appends
  /// continue where the previous process stopped instead of resetting to 0).
  static _LogSinkState _initSinkState(
      Directory logDir, String date, DateTime now) {
    var segment = 0;
    var bytes = 0;
    try {
      for (final f in logDir.listSync().whereType<File>()) {
        final m = _logFileRe.firstMatch(f.uri.pathSegments.last);
        if (m == null || m.group(1) != date) continue;
        final seg = int.parse(m.group(2) ?? '0');
        if (seg >= segment) {
          segment = seg;
          bytes = f.lengthSync();
        }
      }
    } catch (_) {}
    return _LogSinkState(date, segment, bytes, now);
  }

  /// Per-day cap: after opening segment [newSegment], drop the oldest
  /// segments of the same day beyond [maxSegmentsPerDay].
  static void _enforceDayCap(Directory logDir, String date, int newSegment) {
    try {
      for (var seg = 0; seg <= newSegment - maxSegmentsPerDay; seg++) {
        final f = File(_segmentPath(logDir, date, seg));
        if (f.existsSync()) f.deleteSync();
      }
    } catch (_) {}
  }

  /// Age + budget cleanup. Oldest files go first; files of today and
  /// yesterday are exempt from the budget rule (>=24h guarantee).
  static void _cleanup(Directory logDir, DateTime now) {
    try {
      final today = now.toIso8601String().substring(0, 10);
      final yesterday = now
          .subtract(const Duration(days: 1))
          .toIso8601String()
          .substring(0, 10);
      final cutoff = now
          .subtract(Duration(days: retentionDays - 1))
          .toIso8601String()
          .substring(0, 10);

      final entries = <({String date, int seg, File file, int size})>[];
      for (final f in logDir.listSync().whereType<File>()) {
        final m = _logFileRe.firstMatch(f.uri.pathSegments.last);
        if (m == null) continue;
        entries.add((
          date: m.group(1)!,
          seg: int.parse(m.group(2) ?? '0'),
          file: f,
          size: f.lengthSync(),
        ));
      }

      // ISO dates compare lexicographically.
      var total = 0;
      final kept = <({String date, int seg, File file, int size})>[];
      for (final e in entries) {
        if (e.date.compareTo(cutoff) < 0) {
          e.file.deleteSync();
        } else {
          kept.add(e);
          total += e.size;
        }
      }
      if (total <= totalBudgetBytes) return;

      kept.sort((a, b) {
        final d = a.date.compareTo(b.date);
        return d != 0 ? d : a.seg.compareTo(b.seg);
      });
      for (final e in kept) {
        if (total <= totalBudgetBytes) break;
        if (e.date == today || e.date == yesterday) continue;
        e.file.deleteSync();
        total -= e.size;
      }
    } catch (_) {
      // Non-fatal: retention must never take down logging.
    }
  }

  static void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
    flushAll();
  }
}
