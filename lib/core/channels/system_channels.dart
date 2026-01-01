import 'dart:convert';
import 'dart:typed_data';

import '../crypto/sodium_ffi.dart';
import '../network/peer_info.dart' show bytesToHex;

/// Deterministic channel IDs and constants for the two system channels (§9.5).
class SystemChannels {
  SystemChannels._();

  // ── Channel IDs (deterministic, lazily computed on first access) ───

  static String? _bugLogId;
  static String get bugLogChannelIdHex =>
      _bugLogId ??= _sha256Hex('cleona-system-channel-bug-log');

  static String? _featureReqId;
  static String get featureReqChannelIdHex =>
      _featureReqId ??= _sha256Hex('cleona-system-channel-feature-requests');

  static bool isSystemChannel(String channelIdHex) =>
      channelIdHex == bugLogChannelIdHex ||
      channelIdHex == featureReqChannelIdHex;

  static bool isBugLogChannel(String channelIdHex) =>
      channelIdHex == bugLogChannelIdHex;

  static bool isFeatureReqChannel(String channelIdHex) =>
      channelIdHex == featureReqChannelIdHex;

  static String _sha256Hex(String input) =>
      bytesToHex(SodiumFFI().sha256(Uint8List.fromList(utf8.encode(input))));

  // ── Zero-owner sentinel ───────────────────────────────────────────

  static final String zeroOwnerHex = '00' * 32;

  // ── Storage limits ────────────────────────────────────────────────

  static const int maxChannelStorageBytes = 25 * 1024 * 1024;
  static const int maxAutoReportBytes = 256 * 1024;
  static const int maxManualPostBytes = 2 * 1024 * 1024;

  // ── Rate limits ───────────────────────────────────────────────────

  static const int maxReportsPerHour = 3;
  static const int maxReportsPerDay = 10;
  static const int maxFeaturePostsPerDay = 3;

  // ── Crash report field limits ─────────────────────────────────────

  static const int maxExceptionMsgChars = 500;
  static const int maxStackFrames = 20;
  static const int maxLogTailLines = 30;
  static const int fingerprintFrameCount = 5;
}

/// Structured crash report — collected locally, shown in the consent popup,
/// and serialized as a JSON channel post if the user approves.
class CrashReport {
  final String fingerprint;
  final String appVersion;
  final String platform;
  final String dartVersion;
  final int timestampMs;
  final String exceptionType;
  final String exceptionMsg;
  final String stackTrace;
  final String logTail;
  final int peerCount;
  final int uptimeSeconds;
  final int memoryBytes;

  const CrashReport({
    required this.fingerprint,
    required this.appVersion,
    required this.platform,
    required this.dartVersion,
    required this.timestampMs,
    required this.exceptionType,
    required this.exceptionMsg,
    required this.stackTrace,
    required this.logTail,
    required this.peerCount,
    required this.uptimeSeconds,
    required this.memoryBytes,
  });

  Map<String, dynamic> toJson() => {
        'type': 'crash_report',
        'fingerprint': fingerprint,
        'appVersion': appVersion,
        'platform': platform,
        'dartVersion': dartVersion,
        'timestampMs': timestampMs,
        'exceptionType': exceptionType,
        'exceptionMsg': exceptionMsg,
        'stackTrace': stackTrace,
        'logTail': logTail,
        'peerCount': peerCount,
        'uptimeSeconds': uptimeSeconds,
        'memoryBytes': memoryBytes,
      };

  static CrashReport? fromJson(Map<String, dynamic> json) {
    if (json['type'] != 'crash_report') return null;
    try {
      return CrashReport(
        fingerprint: json['fingerprint'] as String,
        appVersion: json['appVersion'] as String,
        platform: json['platform'] as String,
        dartVersion: json['dartVersion'] as String,
        timestampMs: json['timestampMs'] as int,
        exceptionType: json['exceptionType'] as String,
        exceptionMsg: json['exceptionMsg'] as String,
        stackTrace: json['stackTrace'] as String,
        logTail: json['logTail'] as String,
        peerCount: json['peerCount'] as int,
        uptimeSeconds: json['uptimeSeconds'] as int,
        memoryBytes: json['memoryBytes'] as int,
      );
    } catch (_) {
      return null;
    }
  }

  String toPostText() => jsonEncode(toJson());

  /// Human-readable summary for the consent popup.
  String toPreviewText() {
    final stackLines = stackTrace.split('\n');
    final buf = StringBuffer()
      ..writeln('Version: $appVersion')
      ..writeln('Plattform: $platform')
      ..writeln('Fehler: $exceptionType — $exceptionMsg')
      ..writeln('Stack:');
    for (final line in stackLines.take(5)) {
      buf.writeln('  $line');
    }
    if (stackLines.length > 5) {
      buf.writeln('  ... (${stackLines.length - 5} weitere)');
    }
    buf.writeln('Logs: [letzte ${logTail.split('\n').length} Zeilen]');
    return buf.toString();
  }
}

/// Lightweight "+1" reply for known crashes.
class CrashDuplicateReply {
  final String fingerprint;
  final String appVersion;
  final String platform;
  final int timestampMs;

  const CrashDuplicateReply({
    required this.fingerprint,
    required this.appVersion,
    required this.platform,
    required this.timestampMs,
  });

  Map<String, dynamic> toJson() => {
        'type': 'crash_duplicate',
        'fingerprint': fingerprint,
        'appVersion': appVersion,
        'platform': platform,
        'timestampMs': timestampMs,
      };

  static CrashDuplicateReply? fromJson(Map<String, dynamic> json) {
    if (json['type'] != 'crash_duplicate') return null;
    try {
      return CrashDuplicateReply(
        fingerprint: json['fingerprint'] as String,
        appVersion: json['appVersion'] as String,
        platform: json['platform'] as String,
        timestampMs: json['timestampMs'] as int,
      );
    } catch (_) {
      return null;
    }
  }

  String toPostText() => jsonEncode(toJson());
}

/// Manual contact-issue report — collected when a pending_outgoing contact
/// doesn't respond and the user taps "Problem melden" in the 3-dot menu.
class ContactIssueReport {
  final String fingerprint;
  final String appVersion;
  final String platform;
  final int timestampMs;
  final String contactIdShort;
  final String contactName;
  final int seedAgeSeconds;
  final String natType;
  final int peerCount;
  final int confirmedPeerCount;
  final bool hasPortMapping;
  final bool peerSeenInDht;
  final String logTail;
  final int uptimeSeconds;

  const ContactIssueReport({
    required this.fingerprint,
    required this.appVersion,
    required this.platform,
    required this.timestampMs,
    required this.contactIdShort,
    required this.contactName,
    required this.seedAgeSeconds,
    required this.natType,
    required this.peerCount,
    required this.confirmedPeerCount,
    required this.hasPortMapping,
    required this.peerSeenInDht,
    required this.logTail,
    required this.uptimeSeconds,
  });

  Map<String, dynamic> toJson() => {
        'type': 'contact_issue',
        'fingerprint': fingerprint,
        'appVersion': appVersion,
        'platform': platform,
        'timestampMs': timestampMs,
        'contactIdShort': contactIdShort,
        'contactName': contactName,
        'seedAgeSeconds': seedAgeSeconds,
        'natType': natType,
        'peerCount': peerCount,
        'confirmedPeerCount': confirmedPeerCount,
        'hasPortMapping': hasPortMapping,
        'peerSeenInDht': peerSeenInDht,
        'logTail': logTail,
        'uptimeSeconds': uptimeSeconds,
      };

  static ContactIssueReport? fromJson(Map<String, dynamic> json) {
    if (json['type'] != 'contact_issue') return null;
    try {
      return ContactIssueReport(
        fingerprint: json['fingerprint'] as String,
        appVersion: json['appVersion'] as String,
        platform: json['platform'] as String,
        timestampMs: json['timestampMs'] as int,
        contactIdShort: json['contactIdShort'] as String,
        contactName: json['contactName'] as String,
        seedAgeSeconds: json['seedAgeSeconds'] as int,
        natType: json['natType'] as String,
        peerCount: json['peerCount'] as int,
        confirmedPeerCount: json['confirmedPeerCount'] as int,
        hasPortMapping: json['hasPortMapping'] as bool,
        peerSeenInDht: json['peerSeenInDht'] as bool,
        logTail: json['logTail'] as String,
        uptimeSeconds: json['uptimeSeconds'] as int,
      );
    } catch (_) {
      return null;
    }
  }

  String toPostText() => jsonEncode(toJson());

  String toPreviewText() {
    final buf = StringBuffer()
      ..writeln('Version: $appVersion')
      ..writeln('Plattform: $platform')
      ..writeln('Kontakt: $contactName ($contactIdShort)')
      ..writeln('Seed-Alter: ${formatDuration(seedAgeSeconds)}')
      ..writeln('NAT-Typ: $natType')
      ..writeln('Peers: $peerCount ($confirmedPeerCount bestätigt)')
      ..writeln('Port-Mapping: ${hasPortMapping ? "ja" : "nein"}')
      ..writeln('Peer im DHT: ${peerSeenInDht ? "ja" : "nein"}')
      ..writeln('Uptime: ${formatDuration(uptimeSeconds)}')
      ..writeln('Logs: [letzte ${logTail.split('\n').length} Zeilen]');
    return buf.toString();
  }

  String toExportText() {
    final buf = StringBuffer()
      ..writeln('=== Cleona Kontaktproblem-Bericht ===')
      ..writeln('Erstellt: ${DateTime.fromMillisecondsSinceEpoch(timestampMs).toIso8601String()}')
      ..writeln('')
      ..writeln('Version: $appVersion')
      ..writeln('Plattform: $platform')
      ..writeln('Kontakt: $contactName ($contactIdShort)')
      ..writeln('Seed-Alter: ${formatDuration(seedAgeSeconds)}')
      ..writeln('NAT-Typ: $natType')
      ..writeln('Peers: $peerCount ($confirmedPeerCount bestätigt)')
      ..writeln('Port-Mapping: ${hasPortMapping ? "ja" : "nein"}')
      ..writeln('Peer im DHT: ${peerSeenInDht ? "ja" : "nein"}')
      ..writeln('Uptime: ${formatDuration(uptimeSeconds)}')
      ..writeln('')
      ..writeln('--- Letzte Log-Einträge ---')
      ..writeln(logTail);
    return buf.toString();
  }

  static String formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}min';
    if (seconds < 86400) return '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}min';
    return '${seconds ~/ 86400}d ${(seconds % 86400) ~/ 3600}h';
  }
}

/// Compute a crash fingerprint from exception type and stack frames.
/// Strips line numbers and normalizes paths so the same bug on different
/// versions produces the same fingerprint.
String computeCrashFingerprint(String exceptionType, String rawStackTrace) {
  final lines = rawStackTrace.split('\n');
  final normalized = <String>[];
  for (final line in lines) {
    if (normalized.length >= SystemChannels.fingerprintFrameCount) break;
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final noLineCol = trimmed
        .replaceAll(RegExp(r':\d+:\d+'), '')
        .replaceAll(RegExp(r'\(line \d+\)'), '')
        .replaceAll(RegExp(r'/[^ ]*lib/'), 'lib/');
    normalized.add(noLineCol);
  }
  final input = '$exceptionType\n${normalized.join('\n')}';
  return bytesToHex(
      SodiumFFI().sha256(Uint8List.fromList(utf8.encode(input))));
}
