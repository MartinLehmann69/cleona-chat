import 'dart:async';
import 'dart:io';

enum LogLevel { debug, info, warn, error }

class CLogger {
  static final Map<String, CLogger> _instances = {};
  static final Map<String, StringBuffer> _buffers = {};
  static Timer? _flushTimer;

  /// Ring buffer of the most recent log lines (across all modules).
  /// Used by the crash reporter (§9.5) to attach log context to reports.
  static const int _ringCapacity = 500;
  static final List<String> _ring = [];

  static List<String> getRecentLines([int count = 30]) {
    if (count >= _ring.length) return List.unmodifiable(_ring);
    return List.unmodifiable(_ring.sublist(_ring.length - count));
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
        final logDir = Directory('$dir/logs');
        if (!logDir.existsSync()) {
          logDir.createSync(recursive: true);
        }
        final date = DateTime.now().toIso8601String().substring(0, 10);
        final file = File('${logDir.path}/cleona_$date.log');
        await file.writeAsString(content, mode: FileMode.append);
      } catch (_) {
        // Non-fatal: logging should never crash the app
      }
    }

    // iOS mirror flush — writes to Documents/logs/ (AFC-accessible)
    if (iosMirrorPath != null && _iosMirrorBuffer != null && _iosMirrorBuffer!.isNotEmpty) {
      final content = _iosMirrorBuffer!.toString();
      _iosMirrorBuffer!.clear();
      try {
        final logDir = Directory('$iosMirrorPath/logs');
        if (!logDir.existsSync()) logDir.createSync(recursive: true);
        final date = DateTime.now().toIso8601String().substring(0, 10);
        final file = File('${logDir.path}/cleona_$date.log');
        await file.writeAsString(content, mode: FileMode.append);
      } catch (_) {}
    }
  }

  static void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
    flushAll();
  }
}
