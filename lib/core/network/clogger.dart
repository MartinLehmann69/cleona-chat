import 'dart:async';
import 'dart:io';

import 'package:cleona/core/crypto/network_secret.dart';

enum LogLevel { debug, info, warn, error }

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

    // DEBUG only goes to the file buffer — console output is INFO+.
    // On Android this avoids main-thread I/O flooding; on Windows it
    // prevents the console window from scrolling endlessly with packet-
    // level noise that makes the machine look like "die Hölle ist los".
    if (level != LogLevel.debug) {
      try {
        // ignore: avoid_print
        print(line);
      } catch (_) {}
    }

    // ERROR-level: also write to stderr directly (synchronous, no buffer).
    // Survives logger/buffer failure modes; lands in the wrapper's stderr-capture
    // so a stack trace is visible even when the process dies before the 2s
    // periodic flush runs. See C-3 (B-4 daemon crash without trace).
    if (level == LogLevel.error) {
      try { stderr.writeln(line); } catch (_) {}
    }

    // Ring buffer for crash reporter
    _ring.add(line);
    if (_ring.length > _ringCapacity) _ring.removeAt(0);

    // Buffer for file write
    if (profileDir != null) {
      _buffers[profileDir]?.writeln(line);
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
