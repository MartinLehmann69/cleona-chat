import 'dart:convert';
import 'dart:io';

import '../network/clogger.dart';
import '../service/cleona_service.dart';
import 'system_channels.dart';

/// Collects crash data and manages the opt-in reporting flow (§9.5.2).
///
/// The crash reporter does NOT post anything automatically — it builds a
/// [CrashReport], checks for duplicates in the local Bug Log channel, and
/// returns the result so the UI layer can show the appropriate popup.
class CrashReporter {
  final CleonaService _service;
  final DateTime _startTime = DateTime.now();
  final CLogger _log = CLogger.get('CrashReporter');

  /// Tracks reports-per-hour and reports-per-day for rate limiting.
  final List<DateTime> _reportTimestamps = [];

  CrashReporter(this._service);

  // ── Rate limiting ─────────────────────────────────────────────────

  bool get isRateLimited {
    final now = DateTime.now();
    _reportTimestamps.removeWhere(
        (t) => now.difference(t).inHours >= 24);

    final lastHour = _reportTimestamps
        .where((t) => now.difference(t).inMinutes < 60)
        .length;
    if (lastHour >= SystemChannels.maxReportsPerHour) return true;
    if (_reportTimestamps.length >= SystemChannels.maxReportsPerDay) return true;
    return false;
  }

  void _recordReport() => _reportTimestamps.add(DateTime.now());

  // ── Report building ───────────────────────────────────────────────

  CrashReport buildReport(Object error, StackTrace stackTrace) {
    final exType = error.runtimeType.toString();
    final exMsg = error.toString();
    final rawStack = stackTrace.toString();

    final fingerprint = computeCrashFingerprint(exType, rawStack);

    final truncatedMsg = exMsg.length > SystemChannels.maxExceptionMsgChars
        ? exMsg.substring(0, SystemChannels.maxExceptionMsgChars)
        : exMsg;

    final stackLines = rawStack.split('\n');
    final truncatedStack = stackLines
        .take(SystemChannels.maxStackFrames)
        .map(_normalizePath)
        .join('\n');

    final logLines =
        CLogger.getRecentLines(SystemChannels.maxLogTailLines).join('\n');

    final uptime = DateTime.now().difference(_startTime).inSeconds;

    int peerCount = 0;
    try {
      peerCount = _service.node.routingTable.allPeers.length;
    } catch (_) {}

    int memBytes = 0;
    try {
      memBytes = ProcessInfo.currentRss;
    } catch (_) {}

    return CrashReport(
      fingerprint: fingerprint,
      appVersion: CleonaService.kCurrentAppVersion,
      platform: _platformString(),
      dartVersion: Platform.version.split(' ').first,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      exceptionType: exType,
      exceptionMsg: truncatedMsg,
      stackTrace: truncatedStack,
      logTail: logLines,
      peerCount: peerCount,
      uptimeSeconds: uptime,
      memoryBytes: memBytes,
    );
  }

  // ── Duplicate detection ───────────────────────────────────────────

  /// Searches the local Bug Log channel for an existing post with the
  /// same fingerprint. Returns the post ID if found, null otherwise.
  String? findExistingReport(String fingerprint) {
    final channelId = SystemChannels.bugLogChannelIdHex;
    final conv = _service.conversations[channelId];
    if (conv == null) return null;
    final messages = conv.messages;

    for (final msg in messages) {
      final parsed = _parsePostJson(msg.text);
      if (parsed == null) continue;
      final type = parsed['type'] as String?;
      final fp = parsed['fingerprint'] as String?;
      if (type == 'crash_report' && fp == fingerprint) return msg.id;
    }
    return null;
  }

  /// Counts how many +1 replies exist for a given fingerprint.
  int countDuplicates(String fingerprint) {
    final channelId = SystemChannels.bugLogChannelIdHex;
    final conv = _service.conversations[channelId];
    if (conv == null) return 0;
    final messages = conv.messages;

    int count = 0;
    for (final msg in messages) {
      final parsed = _parsePostJson(msg.text);
      if (parsed == null) continue;
      if (parsed['type'] == 'crash_duplicate' &&
          parsed['fingerprint'] == fingerprint) {
        count++;
      }
    }
    return count;
  }

  // ── Posting ───────────────────────────────────────────────────────

  /// Posts a new crash report to the Bug Log channel.
  /// Call only after the user consented via the popup.
  Future<bool> publishReport(CrashReport report) async {
    if (isRateLimited) return false;

    final postText = report.toPostText();
    if (postText.length > SystemChannels.maxAutoReportBytes) {
      _log.warn('Crash report exceeds size limit, truncating');
      return false;
    }

    final result = await _service.sendChannelPost(
      SystemChannels.bugLogChannelIdHex,
      postText,
    );
    if (result != null) {
      _recordReport();
      _log.info('Crash report published (fp: ${report.fingerprint.substring(0, 16)})');
      return true;
    }
    return false;
  }

  /// Posts a lightweight "+1" duplicate reply.
  Future<bool> publishDuplicate(CrashReport report) async {
    if (isRateLimited) return false;

    final reply = CrashDuplicateReply(
      fingerprint: report.fingerprint,
      appVersion: report.appVersion,
      platform: report.platform,
      timestampMs: report.timestampMs,
    );

    final result = await _service.sendChannelPost(
      SystemChannels.bugLogChannelIdHex,
      reply.toPostText(),
    );
    if (result != null) {
      _recordReport();
      return true;
    }
    return false;
  }

  // ── Helpers ───────────────────────────────────────────────────────

  static String _platformString() {
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

  static String _normalizePath(String frame) {
    return frame
        .replaceAll(RegExp(r'/home/[^ ]*/lib/'), 'lib/')
        .replaceAll(RegExp(r'C:\\[^ ]*\\lib\\'), 'lib/')
        .replaceAll(RegExp(r'/data/[^ ]*/lib/'), 'lib/');
  }

  static Map<String, dynamic>? _parsePostJson(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }
}
