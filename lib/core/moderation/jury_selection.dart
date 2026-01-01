/// Deterministic juror selection for decentralized moderation (§9.3.1a).
///
/// Selection point H = SHA-256("jury-select" || channelId || categoryIndex || epochDay || juryRound).
/// Jury = jurySize XOR-closest JurorAvailabilityRecords to H.
/// Every node can recompute the selection independently.
library;

import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/network/peer_info.dart' show bytesToHex;

/// Computes the jury selection point H.
///
/// `H = SHA-256("jury-select" || channelId || categoryIndex || epochDay || juryRound)`
/// None of the inputs is freely grindable by a reporter — reportId is
/// deliberately excluded.
Uint8List computeSelectionPoint({
  required Uint8List channelId,
  required int categoryIndex,
  required int epochDay,
  required int juryRound,
  required SodiumFFI sodium,
}) {
  final prefix = Uint8List.fromList('jury-select'.codeUnits);
  final buf = BytesBuilder(copy: false);
  buf.add(prefix);
  buf.add(channelId);
  buf.add(_uint32Bytes(categoryIndex));
  buf.add(_uint32Bytes(epochDay));
  buf.add(_uint32Bytes(juryRound));
  return sodium.sha256(buf.toBytes());
}

/// Computes the juror record ID from a user's public key.
///
/// `juror_record_id = SHA-256("juror" || userPubKey)`
Uint8List computeJurorRecordId(Uint8List userPubKeyEd25519, SodiumFFI sodium) {
  final prefix = Uint8List.fromList('juror'.codeUnits);
  final buf = BytesBuilder(copy: false);
  buf.add(prefix);
  buf.add(userPubKeyEd25519);
  return sodium.sha256(buf.toBytes());
}

/// Selects jurors deterministically: the [jurySize] records whose
/// [JurorRecord.recordId] is XOR-closest to [selectionPoint].
///
/// Returns the selected records sorted by XOR distance (closest first).
/// If fewer than [jurySize] records are available, returns all of them.
List<JurorRecord> selectJurors({
  required Uint8List selectionPoint,
  required List<JurorRecord> registeredJurors,
  required int jurySize,
}) {
  if (registeredJurors.isEmpty) return [];

  final scored = registeredJurors.map((j) {
    final dist = _xorDistance(selectionPoint, j.recordId);
    return _ScoredJuror(j, dist);
  }).toList();

  scored.sort((a, b) => _compareDistance(a.distance, b.distance));

  final take = jurySize < scored.length ? jurySize : scored.length;
  return scored.sublist(0, take).map((s) => s.juror).toList();
}

/// Tolerance check (§9.3.1a): a verdict signer is accepted if its
/// record ID lies within the top `toleranceFactor × jurySize` records
/// closest to H from the verifier's own lookup.
bool isWithinToleranceSet({
  required Uint8List jurorRecordId,
  required Uint8List selectionPoint,
  required List<JurorRecord> registeredJurors,
  required int toleranceFactor,
  required int jurySize,
}) {
  final toleranceSize = toleranceFactor * jurySize;
  final topN = selectJurors(
    selectionPoint: selectionPoint,
    registeredJurors: registeredJurors,
    jurySize: toleranceSize,
  );
  return topN.any((j) => _bytesEqual(j.recordId, jurorRecordId));
}

/// Computes the canonical verdict core hash that jurors sign.
///
/// `SHA-256(juryId || channelId || reportId || vote || consequence || epochDay || juryRound)`
Uint8List computeVerdictCoreHash({
  required Uint8List juryId,
  required Uint8List channelId,
  required Uint8List reportId,
  required int vote,
  required int consequence,
  required int epochDay,
  required int juryRound,
  required SodiumFFI sodium,
}) {
  final buf = BytesBuilder(copy: false);
  buf.add(juryId);
  buf.add(channelId);
  buf.add(reportId);
  buf.add(_uint32Bytes(vote));
  buf.add(_uint32Bytes(consequence));
  buf.add(_uint32Bytes(epochDay));
  buf.add(_uint32Bytes(juryRound));
  return sodium.sha256(buf.toBytes());
}

/// Computes the eligibility snapshot hash — audit trail of which
/// candidate record IDs the initiator observed at selection time.
Uint8List computeEligibilitySnapshotHash(
    List<Uint8List> candidateRecordIds, SodiumFFI sodium) {
  final sorted = List<Uint8List>.from(candidateRecordIds)
    ..sort(_compareBytes);
  final buf = BytesBuilder(copy: false);
  for (final id in sorted) {
    buf.add(id);
  }
  return sodium.sha256(buf.toBytes());
}

/// Computes the moderation proof hash for gossip entries.
///
/// `SHA-256(ModerationProofRecord serialized bytes)`
Uint8List computeModerationProofHash(
    Uint8List proofRecordBytes, SodiumFFI sodium) {
  return sodium.sha256(proofRecordBytes);
}

/// Computes the DHT key for storing a moderation proof.
///
/// `SHA-256("modproof" || channelId)`
Uint8List computeModerationProofDhtKey(
    Uint8List channelId, SodiumFFI sodium) {
  final prefix = Uint8List.fromList('modproof'.codeUnits);
  final buf = BytesBuilder(copy: false);
  buf.add(prefix);
  buf.add(channelId);
  return sodium.sha256(buf.toBytes());
}

/// UTC epoch day (days since Unix epoch).
int utcEpochDay(DateTime utc) =>
    utc.toUtc().millisecondsSinceEpoch ~/ (24 * 60 * 60 * 1000);

/// A registered juror's DHT record (in-memory representation).
class JurorRecord {
  final Uint8List recordId;
  final Uint8List userPubKeyEd25519;
  final Uint8List userPubKeyMlDsa;
  final int creationEpochMs;
  final Uint8List selfSigEd25519;
  final Uint8List selfSigMlDsa;

  JurorRecord({
    required this.recordId,
    required this.userPubKeyEd25519,
    required this.userPubKeyMlDsa,
    required this.creationEpochMs,
    required this.selfSigEd25519,
    required this.selfSigMlDsa,
  });

  String get recordIdHex => bytesToHex(recordId);
  String get userIdHex => bytesToHex(userPubKeyEd25519);
}

// ── Internal helpers ──────────────────────────────────────────────────

Uint8List _uint32Bytes(int value) {
  final b = ByteData(4);
  b.setUint32(0, value, Endian.big);
  return b.buffer.asUint8List();
}

Uint8List _xorDistance(Uint8List a, Uint8List b) {
  final len = a.length < b.length ? a.length : b.length;
  final result = Uint8List(len);
  for (var i = 0; i < len; i++) {
    result[i] = a[i] ^ b[i];
  }
  return result;
}

int _compareDistance(Uint8List a, Uint8List b) {
  final len = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < len; i++) {
    if (a[i] != b[i]) return a[i] < b[i] ? -1 : 1;
  }
  return a.length - b.length;
}

int _compareBytes(Uint8List a, Uint8List b) => _compareDistance(a, b);

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class _ScoredJuror {
  final JurorRecord juror;
  final Uint8List distance;
  _ScoredJuror(this.juror, this.distance);
}
