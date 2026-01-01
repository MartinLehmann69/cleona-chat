/// Byte <-> hex conversion helpers.
///
/// These have no transport semantics and deliberately live outside
/// `lib/core/network/`: they were previously defined in
/// `network/peer_info.dart` and imported by 38 files across modules that the
/// V4 migration leaves untouched (`ipc/`, `identity/`, `moderation/`,
/// `services/`, `storage/`) as well as by modules carried over with deltas
/// (`calls/`, `channels/`, `update/`).
///
/// **HISTORICAL from 2026-08-31 (CUT).** `lib/core/network/` no longer
/// exists — zero files, re-measured on 2026-09-03. The paragraph above
/// justifies WHY these helpers survived the demolition; it describes
/// no present-day neighbour. Whoever looks for the path only finds it in the
/// history.
///
/// Moving them here is part of AP-1a (docs/MIGRATION_V3_TO_V4_0_MYZEL.md §9.15.5):
/// replacing the network layer must not take the project's hex helpers with
/// it. See also V4 architecture §15.4.5.
library;

import 'dart:typed_data';

/// Lowercase, zero-padded hex encoding of [bytes]. Two characters per byte,
/// no separators, no prefix.
String bytesToHex(Uint8List bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

/// Inverse of [bytesToHex]. Expects an even-length string of hex digits;
/// a trailing odd character is ignored, matching the previous behaviour.
Uint8List hexToBytes(String hex) {
  final result = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < result.length; i++) {
    result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return result;
}

/// Convenience getter for `bytesToHex(Uint8List.fromList(this))`.
extension HexOnListInt on List<int> {
  String get hex => bytesToHex(Uint8List.fromList(this));
}

/// Truncates a hex identifier to a 16-character diagnostic prefix.
///
/// 16 hex chars (~64 bits) are unique within a single run — that is all a
/// diagnostic label needs. The full identifier in cleartext gains nothing
/// over the prefix but ends up in every log file and every crash report.
/// Same reasoning and threshold as `identity_context.dart`'s
/// `userIdHex.substring(0, 16)` info-log lines and
/// `caldav_server.dart`'s `CalDAVServerIdentity.shortId`.
///
/// A [full] value of 16 chars or fewer (e.g. a short id used by a test
/// double) passes through unchanged instead of throwing.
String shortHex(String full) => full.length <= 16 ? full : full.substring(0, 16);
