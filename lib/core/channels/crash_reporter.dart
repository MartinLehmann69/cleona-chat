import 'dart:convert';
import 'dart:io';

import 'package:mycelium/durable_packets.dart' show kDurableObjectAtMost;
import 'package:mycelium/node_helpers.dart' show interfaces;
import 'package:mycelium/own_address.dart' show linkKindFrom;

import '../log/clogger.dart';
import '../log/log_redaction.dart';
import '../service/cleona_service.dart';
import '../service/mycelium_seam.dart' show hostWireState;
import 'crash_report_builder.dart';
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

  /// The report body is built by [buildCrashReport], which the desktop
  /// window uses as well (it holds no `CleonaService`, S417 W-1).
  CrashReport buildReport(Object error, StackTrace stackTrace) {
    int peerCount = 0;
    try {
      peerCount = _service.independentSyncPartners; // §22.7.1, S411
    } catch (_) {}
    return buildCrashReport(error, stackTrace,
        startedAt: _service.serviceStartedAt, peerCount: peerCount);
  }

  // ── Manual log report ──────────────────────────────────────────────

  LogReport buildLogReport() {
    final head = _stateLines();
    final tail = CLogger.getReportLines(SystemChannels.maxLogTailLines)
        .map(normalizeCrashPath)
        .toList();
    var report = _logReport(head, tail);
    // A system object above `kDurableObjectAtMost` is read by no holder
    // (`durable_packets.dart`, S420 BL-5): the oldest tail lines go first,
    // never the head; 1024 B stay free for pseudonym, signature and the
    // object's own head (`system_object.dart`).
    while (tail.isNotEmpty &&
        utf8.encode(report.toPostText()).length > kDurableObjectAtMost - 1024) {
      tail.removeRange(0, tail.length < 10 ? tail.length : 10);
      report = _logReport(head, tail);
    }
    return report;
  }

  /// Fixed lines at the head of a log report (S422): the state a storm of
  /// equal lines pushes out of the tail, read from the node instead of the
  /// log. Every address goes through [LogRedaction.apply] — the same markers
  /// as in the tail; an interface is named by its kind and index, never by
  /// its name (on Windows the name is the user's own text). The node is read
  /// at the seam ([hostWireState], §22.4.6), never here.
  List<String> _stateLines() {
    try {
      final s = hostWireState(_service.myceliumMailbox?.host);
      if (s == null) return const ['== node: not running'];
      final ifs = [
        for (final i in interfaces)
          '${linkKindFrom(i.name).name}#${i.index} '
              '${i.addresses.map((a) => a.address).join(',')}',
      ].join('; ');
      final pub = s.publicAddress;
      final edge = s.lastEdge;
      String cap(String s) => s.length > 1024 ? '${s.substring(0, 1024)}…' : s;
      return [
        '== wire: port ${s.port}, IPv6 socket '
            '${s.ipv6Socket ? 'yes' : 'no'}; '
            'packets sent ${s.packetsSent}, received ${s.packetsReceived}; '
            'send failures IPv4 ${s.sendFailures4}, IPv6 ${s.sendFailures6}',
        cap('== interfaces at the last edge: ${LogRedaction.apply(ifs)}'),
        '== own public address: '
            '${pub == null ? 'none' : LogRedaction.apply(pub)}',
        edge == null
            ? '== last network change: none since start'
            : cap('== last network change ${edge.at.toIso8601String()} '
                '(${edge.reason}): ${LogRedaction.apply(
                    s.lastAddresses.join(','))}'),
      ];
    } catch (e) {
      return ['== node state not readable: ${e.runtimeType}'];
    }
  }

  LogReport _logReport(List<String> head, List<String> tail) {
    final logLines = [...head, ...tail];

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
      peerCount = _service.independentSyncPartners; // §22.7.1, S411
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
        .map(normalizeCrashPath)
        .toList();

    return LogReport(
      appVersion: CleonaService.kCurrentAppVersion,
      platform: crashPlatformString(),
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
}
