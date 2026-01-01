/// The local system-channel records of 4.2.3 and earlier, signed anew under
/// the report pseudonym (v4_2 §16.7, D-57). S407 SK-2.
///
/// ── WHY RE-SIGNING IS ALLOWED HERE ────────────────────────────────────────
///
/// Up to 4.2.3 a record was signed with the identity's own keys and carried
/// its UserID (`SystemChannelRecordStore.buildSigned`). None of them ever
/// left the device: the propagation was switched off (`_sysChanEagerPush`
/// in `cleona_service_pure.dart`, gap G-2 — "stay local"). So no holder,
/// no reader and no state root knows them, and the identity link they carry
/// has never been published. Signing their content anew under the report
/// pseudonym changes nothing anyone has seen; publishing the old form would
/// publish the link §16.7 forbids.
///
/// What is converted: the OWN records of the identity (author = own UserID)
/// that are still standing —
///
///   * a post becomes a report; a `crash_report` keeps its fingerprint
///     (§16.7 "Dedup and +1"); a `crash_duplicate` (the old +1) becomes a
///     +1 entry;
///   * the latest own vote on an own Feature Request becomes a vote on the
///     converted request;
///   * a post the identity retracted is dropped together with its
///     retraction — neither ever left the device.
///
/// Records of other authors cannot exist (nothing was ever received), and
/// a vote on a request that is not converted has no target; both are
/// skipped. The caller (SK-4) offers the results to `SystemObjectStore.
/// addOwn`, deposits them, and removes the old rows.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/channels/system_channels.dart';
import 'package:cleona/core/channels/system_object.dart';
import 'package:cleona/core/storage/encrypted_store.dart';
import 'package:cleona/core/util/hex.dart' show bytesToHex, hexToBytes;
import 'package:cleona/generated/proto/app_payloads.pb.dart' as proto;
import 'package:mycelium/durable_id.dart';

/// The area of the retired record store in the identity's database
/// (`SystemChannelRecordStore.kAreaRecords`, S366). Named here so that the
/// old store can go without this conversion losing its source.
const String kLegacyRecordArea = 'syschan_records';

/// The area of the old store's expiry marks (`kAreaGone`) — removed with
/// the records once they are re-signed.
const String kLegacyGoneArea = 'syschan_gone';

/// Old record kinds (`SysChanKind`).
const int _post = 0, _vote = 1, _retract = 2;

/// One converted record.
class LegacyResigned {
  /// The record id of the old record (hex).
  final String oldRecordIdHex;

  /// The new object, signed under the report pseudonym.
  final Uint8List object;

  const LegacyResigned(this.oldRecordIdHex, this.object);
}

/// Reads the old records from the identity's database; damaged rows are
/// skipped.
List<proto.SystemChannelRecord> readLegacyRecords(EncryptedStore store) {
  final out = <proto.SystemChannelRecord>[];
  for (final row in store.loadArea(kLegacyRecordArea).values) {
    try {
      out.add(proto.SystemChannelRecord.fromBuffer(
          base64Decode(row['b'] as String)));
    } catch (_) {/* skip a damaged row */}
  }
  return out;
}

/// Converts the own, standing records of [ownUserId] (see the library
/// comment). The result is ordered as the records were written, requests
/// before the votes on them.
List<LegacyResigned> resignLegacyRecords(
  Iterable<proto.SystemChannelRecord> records, {
  required Uint8List ownUserId,
  required SystemObjectAuthor author,
}) {
  final own = bytesToHex(ownUserId);
  final mine = records
      .where((r) => bytesToHex(Uint8List.fromList(r.authorUserId)) == own)
      .toList()
    ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));

  String idOf(List<int> b) => bytesToHex(Uint8List.fromList(b));
  final retracted = {
    for (final r in mine)
      if (r.kind == _retract && r.targetRecordId.isNotEmpty)
        idOf(r.targetRecordId)
  };

  final out = <LegacyResigned>[];
  final newHash = <String, Uint8List>{};
  for (final r in mine.where((r) => r.kind == _post)) {
    final id = idOf(r.recordId);
    if (retracted.contains(id)) continue;
    final channel = _channelOf(idOf(r.channelId));
    if (channel == null) continue;
    final at = DateTime.fromMillisecondsSinceEpoch(r.timestampMs.toInt(),
        isUtc: true);
    final fp = _fingerprintOf(r.text, type: 'crash_report');
    final dup = _fingerprintOf(r.text, type: 'crash_duplicate');
    final Uint8List bytes;
    if (channel == kChannelBugLog && dup != null) {
      bytes = author.plusOne(dup, at: at);
    } else {
      bytes = author.report(channel, r.text,
          fingerprint: channel == kChannelBugLog ? fp : null, at: at);
    }
    newHash[id] = objectHash(bytes);
    out.add(LegacyResigned(id, bytes));
  }

  final latestVote = <String, proto.SystemChannelRecord>{};
  for (final r in mine.where((r) => r.kind == _vote)) {
    final t = idOf(r.targetRecordId);
    if (!newHash.containsKey(t) || retracted.contains(t)) continue;
    latestVote[t] = r; // sorted by time: the last one stands
  }
  for (final e in latestVote.entries) {
    final r = e.value;
    if (r.voteOption < SystemVote.yes || r.voteOption > SystemVote.dontCare) {
      continue;
    }
    out.add(LegacyResigned(
        idOf(r.recordId),
        author.vote(newHash[e.key]!, r.voteOption,
            at: DateTime.fromMillisecondsSinceEpoch(r.timestampMs.toInt(),
                isUtc: true))));
  }
  return out;
}

int? _channelOf(String channelIdHex) {
  if (SystemChannels.isBugLogChannel(channelIdHex)) return kChannelBugLog;
  if (SystemChannels.isFeatureReqChannel(channelIdHex)) {
    return kChannelFeatureRequests;
  }
  return null;
}

/// The 32 B fingerprint of a report text of [type], or `null`.
Uint8List? _fingerprintOf(String text, {required String type}) {
  if (!text.contains('"$type"')) return null;
  try {
    final j = jsonDecode(text);
    if (j is! Map || j['type'] != type) return null;
    final fp = j['fingerprint'];
    if (fp is! String || fp.length != 64) return null;
    return hexToBytes(fp);
  } catch (_) {
    return null;
  }
}
