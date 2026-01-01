import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../crypto/sodium_ffi.dart';
import '../network/clogger.dart';
import '../network/peer_info.dart' show bytesToHex;
import '../service/cleona_service.dart';
import 'system_channels.dart';

class ContactIssueReporter {
  final CleonaService _service;
  final CLogger _log = CLogger.get('ContactIssueReporter');

  ContactIssueReporter(this._service);

  ContactIssueReport buildReport(ContactInfo contact) {
    final fingerprint = _computeFingerprint(contact.nodeIdHex);

    final stats = _service.getNetworkStats();

    final seedAge = _estimateSeedAge(contact);

    final peerSeenInDht = _service.node.routingTable
            .getPeerByUserId(contact.nodeId) !=
        null;

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
      natType: stats.natType,
      peerCount: stats.activePeerCount,
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

  bool get canPostToBugLog => _service.peerCount > 0;

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
