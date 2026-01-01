import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../crypto/sodium_ffi.dart';
import '../log/clogger.dart';
import '../util/hex.dart' show bytesToHex;
import '../service/cleona_service.dart';
import '../service/service_interface.dart' show ReadinessGate;
import 'system_channels.dart';

class ContactIssueReporter {
  final CleonaService _service;
  final CLogger _log;

  // _service.profileDir is the per-identity profile directory of the
  // daemon that constructs this reporter (analogous to CrashReporter).
  ContactIssueReporter(this._service)
      : _log = CLogger.get('ContactIssueReporter', profileDir: _service.profileDir);

  ContactIssueReport buildReport(ContactInfo contact) {
    final fingerprint = _computeFingerprint(contact.nodeIdHex);

    final stats = _service.getNetworkStats();

    final seedAge = _estimateSeedAge(contact);

    final peerSeenInDht = _service.isPeerKnownByUserId(contact.nodeId);

    final logLines =
        CLogger.getRecentLines(SystemChannels.maxLogTailLines).join('\n');

    final uptime = stats.uptime.inSeconds;

    return ContactIssueReport(
      fingerprint: fingerprint,
      appVersion: CleonaService.kCurrentAppVersion,
      platform: _platformString(),
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      contactIdShort: contact.nodeIdHex.substring(0, 16),
      contactName: contact.displayName,
      seedAgeSeconds: seedAge,
      // ── TWO FIELDS OF THE REPORT FORMAT, NEWLY SUPPLIED (S360) ──────
      //
      // Here stood `stats.natType` and `stats.activePeerCount`. Both
      // fields of the network statistics fell on 01.09.2026: V4.1 has
      // no NAT type detection and no global peer set.
      //
      // THE REPORT FORMAT ITSELF STAYS UNCHANGED, and that is a
      // deliberate decision, not convenience. `ContactIssueReport`
      // is PUBLISHED as a post in the bug log channel and read there
      // by foreign devices with foreign app versions;
      // `system_channels.dart` reads `natType` without a default value
      // (`json['natType'] as String`). A dropped field would make every
      // older app fail on a report of this version.
      //
      // `'unknown'` is therefore exactly the right value: it was already
      // the default value on a failed access before, and it CLAIMS
      // nothing. `crash_reporter.dart` made and justified the same choice
      // on 31.08. for `LogReport`.
      //
      // Whether the report itself is recut to V4.1 quantities
      // (readiness instead of NAT type, independent sync partners instead
      // of peer count) is a format question with external effect and
      // belongs to the owner — it is reported, not decided here.
      natType: 'unknown',
      // `peerCount`, by contrast, gets a REAL V4.1 number: the session
      // partners of the tagline (`cleona_service.dart`,
      // `_v41SessionPartner`). It answers the same question as
      // `activePeerCount` did before — "with how many nodes is this
      // device talking right now" — and, unlike that one, has a writer.
      peerCount: _service.peerCount,
      confirmedPeerCount: _service.confirmedPeerCount,
      hasPortMapping: _service.hasPortMapping,
      peerSeenInDht: peerSeenInDht,
      logTail: logLines,
      uptimeSeconds: uptime,
    );
  }

  String? findExistingReport(String fingerprint) {
    final channelId = SystemChannels.bugLogChannelIdHex;
    final conv = _service.conversations[channelId];
    _service.ensureLoaded(channelId);
    if (conv == null) return null;

    for (final msg in conv.messages) {
      final parsed = _parsePostJson(msg.text);
      if (parsed == null) continue;
      if (parsed['type'] == 'contact_issue' &&
          parsed['fingerprint'] == fingerprint) {
        return msg.id;
      }
    }
    return null;
  }

  Future<bool> publishReport(ContactIssueReport report) async {
    final postText = report.toPostText();
    if (postText.length > SystemChannels.maxManualPostBytes) {
      _log.warn('Contact issue report exceeds size limit');
      return false;
    }

    final result = await _service.sendChannelPost(
      SystemChannels.bugLogChannelIdHex,
      postText,
    );
    if (result != null) {
      _log.info('Contact issue report published (fp: ${report.fingerprint.substring(0, 16)})');
      return true;
    }
    return false;
  }

  Future<String?> exportToFile(ContactIssueReport report, String savePath) async {
    try {
      final file = File(savePath);
      await file.writeAsString(report.toExportText());
      _log.info('Contact issue report exported to $savePath');
      return savePath;
    } catch (e) {
      _log.warn('Failed to export contact issue report: $e');
      return null;
    }
  }

  /// §22.7.2 — posting into the system channels is possible from `ready`.
  ///
  /// Until AP-5, `_service.peerCount > 0` stood here, and the same
  /// condition stood a second time in `contact_issue_dialog.dart:23`.
  /// §22.7.2 forbids both: the acquaintance count as predicate ("gates hang
  /// off the readiness state `ready`, never off a raw acquaintance count")
  /// and the second, independent copy of the same gate. Both places now
  /// ask the same getter — [ICleonaService.isReady].
  bool get canPostToBugLog => _service.isReady;

  int _estimateSeedAge(ContactInfo contact) {
    if (contact.acceptedAt != null) {
      return DateTime.now().difference(contact.acceptedAt!).inSeconds;
    }
    return _service.getNetworkStats().uptime.inSeconds;
  }

  String _computeFingerprint(String targetUserIdHex) {
    final input = 'contact-issue\n$targetUserIdHex';
    return bytesToHex(
        SodiumFFI().sha256(Uint8List.fromList(utf8.encode(input))));
  }

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

  static Map<String, dynamic>? _parsePostJson(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }
}
