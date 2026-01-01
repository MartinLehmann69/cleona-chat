import 'dart:io';

import '../log/clogger.dart';
import '../service/cleona_service.dart';
import 'system_channels.dart';

/// Builds crash and log reports (§16.7).
///
/// The crash reporter does NOT post anything — it builds a [CrashReport] or
/// [LogReport]; the user decides in the preview, and the deposit, the
/// duplicate question and the own limits run through `SystemChannelApi`
/// (`system_channel_service.dart`).
class CrashReporter {
  final CleonaService _service;

  CrashReporter(this._service);

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
        CLogger.getReportLines(SystemChannels.maxLogTailLines).join('\n');

    final uptime = DateTime.now().difference(_service.serviceStartedAt).inSeconds;

    int peerCount = 0;
    try {
      peerCount = _service.peerCount;
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

  // ── Manual log report ──────────────────────────────────────────────

  LogReport buildLogReport() {
    final logLines = CLogger.getReportLines(SystemChannels.maxLogTailLines)
        .map(_normalizePath)
        .toList();

    final uptime = DateTime.now().difference(_service.serviceStartedAt).inSeconds;

    int peerCount = 0;
    bool hasPortMapping = false;
    // ── TWO DIAGNOSTIC VALUES STAY UNFILLED ON 2026-08-31 (CUT) ──────
    //
    // `routeCount` came from `node.dvRouting.routeCount`, `natType` from
    // `node.natTraversal.natType.name` — both via the pass-throughs in
    // `cleona_service_v3_retire.dart:73,76`, which were deleted with the
    // V3 cut. The quantities themselves are V3: the number of entries
    // in the distance-vector table and the STUN classification of the
    // own NAT. V4.1 has neither a DV table nor a NAT type detection —
    // there is nothing that could answer these two questions.
    //
    // THEY ARE THEREFORE NOT ESTIMATED BUT LEFT EMPTY:
    // `routeCount = 0` and `natType = 'unknown'` are exactly the values
    // the presetting already provided for when access failed. An error
    // report carrying an invented route count is worse than one that
    // leaves the question open — it sends it to everyone who reads the
    // report.
    //
    // `LogReport` requires both fields (`system_channels.dart:319,321`);
    // whether the cut of the report is switched to V4.1 quantities
    // (readiness, independent sync partners) is a question for
    // `system_channels.dart` and is reported, not decided here.
    const int routeCount = 0;
    const String natType = 'unknown';
    try {
      peerCount = _service.peerCount;
      hasPortMapping = _service.hasPortMapping;
    } catch (_) {}

    int memBytes = 0;
    try {
      memBytes = ProcessInfo.currentRss;
    } catch (_) {}

    // Contact state summary for diagnostic context
    String contactSummary = '';
    try {
      final contacts = _service.contacts;
      if (contacts.isNotEmpty) {
        final byStatus = <String, int>{};
        for (final c in contacts.values) {
          byStatus[c.status] = (byStatus[c.status] ?? 0) + 1;
        }
        contactSummary = byStatus.entries
            .map((e) => '${e.value}x ${e.key}')
            .join(', ');
      }
    } catch (_) {}

    // Recent events (CR, contact changes, KEX, delivery)
    final events = CLogger.getRecentEvents()
        .map(_normalizePath)
        .toList();

    return LogReport(
      appVersion: CleonaService.kCurrentAppVersion,
      platform: _platformString(),
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      logTail: logLines.join('\n'),
      peerCount: peerCount,
      uptimeSeconds: uptime,
      memoryBytes: memBytes,
      natType: natType,
      hasPortMapping: hasPortMapping,
      routeCount: routeCount,
      contactSummary: contactSummary,
      eventTail: events.isEmpty ? null : events.join('\n'),
    );
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
}
