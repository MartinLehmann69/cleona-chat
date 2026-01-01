/// §9.5.7 SystemChannelRecord store — admission, anti-entropy state,
/// FR-vote tally, RETRACT tombstones (S119 D1/D2/D3, V3.1.117).
///
/// System channels are ownerless and carry no subscriber registry. Every
/// record is a self-contained, hybrid-self-signed blob (inline pubkeys) so
/// a receiver that has never seen the author can verify it stand-alone —
/// the KEX-Gate context-proof (§8.2/§9.5.6). Distribution is gossip-based
/// (SYSCHAN_DIGEST/SUMMARY/WANT/PUSH, BOOT-path InfrastructureFrames);
/// this module owns the local record set the gossip converges on.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cleona/core/channels/system_channels.dart';
import 'package:cleona/core/crypto/hd_wallet.dart';
import 'package:cleona/core/crypto/network_secret.dart';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart' show bytesToHex, hexToBytes;
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;
import 'package:fixnum/fixnum.dart';

/// Protobuf `bytes` getters are `List<int>` — wrap for [bytesToHex].
String _hex(List<int> bytes) => bytesToHex(Uint8List.fromList(bytes));

/// Record kinds (proto `SystemChannelRecord.kind`).
class SysChanKind {
  static const int post = 0;
  static const int vote = 1;
  static const int retract = 2;
}

/// FR vote options (§9.5.3): 0 = Ja, 1 = Nein, 2 = Egal.
class SysChanVote {
  static const int ja = 0;
  static const int nein = 1;
  static const int egal = 2;
}

/// Admission outcome for [SystemChannelRecordStore.tryAdmit].
enum SysChanAdmission {
  /// Fingerprint already known (stored, evicted, or tombstoned) — no-op.
  duplicate,

  /// Failed verification / unknown channel / rate limit — silently dropped.
  rejected,

  /// New POST admitted and stored.
  postAdmitted,

  /// New VOTE admitted (FR tally changed).
  voteAdmitted,

  /// New RETRACT admitted (target content removed, tombstone kept).
  retractAdmitted,
}

class StoredSysChanRecord {
  final proto.SystemChannelRecord record;
  final Uint8List bytes;
  final String fingerprintHex;

  StoredSysChanRecord({
    required this.record,
    required this.bytes,
    required this.fingerprintHex,
  });
}

/// FR tally for one target record (latest vote per author, LWW).
class FrTally {
  final int ja;
  final int nein;
  final int egal;
  const FrTally(this.ja, this.nein, this.egal);
  int get net => ja - nein;
}

class SystemChannelRecordStore {
  final CLogger _log;

  /// Optional fallback for rotated authors: returns true when the inline
  /// Ed25519 pubkey is authorized for [authorUserId] via the cached
  /// AuthManifest rotation chain (§4.3). Without it, only the founding
  /// binding (computeUserId(inlinePk) == authorUserId) admits.
  bool Function(Uint8List authorUserId, Uint8List inlineEd25519Pk)?
      chainVerifier;

  /// channelIdHex → fingerprintHex → record
  final Map<String, Map<String, StoredSysChanRecord>> _records = {};

  /// Fingerprints we have seen but no longer store (evicted, or POST
  /// content GC'd after RETRACT). Anti-resurrection: WANT never asks for
  /// these, PUSH of them is treated as duplicate.
  final Map<String, Set<String>> _knownGone = {};

  /// channelIdHex → retracted target recordIdHex → author userIdHex who
  /// signed the retract (must match the target's author).
  final Map<String, Map<String, String>> _retractedTargets = {};

  SystemChannelRecordStore({String? profileDir})
      : _log = CLogger.get('syschan', profileDir: profileDir);

  // ── Fingerprint / set hash ─────────────────────────────────────────

  static String fingerprintHexOf(Uint8List recordBytes) {
    final hash = SodiumFFI().sha256(recordBytes);
    return bytesToHex(Uint8List.sublistView(hash, 0, 16));
  }

  /// Order-independent XOR over all stored record fingerprints (16B).
  Uint8List setHash(String channelIdHex) {
    final out = Uint8List(16);
    for (final fp in (_records[channelIdHex] ?? const {}).keys) {
      final bytes = hexToBytes(fp);
      for (var i = 0; i < 16; i++) {
        out[i] ^= bytes[i];
      }
    }
    return out;
  }

  int recordCount(String channelIdHex) => _records[channelIdHex]?.length ?? 0;

  /// Fingerprints we can supply to a peer (stored records only).
  List<String> storedFingerprints(String channelIdHex) =>
      (_records[channelIdHex] ?? const {}).keys.toList();

  /// Fingerprints from [theirs] that we neither store nor know as gone.
  List<Uint8List> missingFingerprints(
      String channelIdHex, List<Uint8List> theirs) {
    final stored = _records[channelIdHex] ?? const {};
    final gone = _knownGone[channelIdHex] ?? const {};
    return theirs.where((fp) {
      final hex = bytesToHex(fp);
      return !stored.containsKey(hex) && !gone.contains(hex);
    }).toList();
  }

  /// Records we store that are absent from [theirs].
  List<StoredSysChanRecord> extraRecords(
      String channelIdHex, List<Uint8List> theirs) {
    final theirSet = theirs.map(bytesToHex).toSet();
    return (_records[channelIdHex] ?? const {})
        .values
        .where((r) => !theirSet.contains(r.fingerprintHex))
        .toList();
  }

  List<StoredSysChanRecord> recordsForFingerprints(
      String channelIdHex, List<Uint8List> fps) {
    final stored = _records[channelIdHex] ?? const {};
    final out = <StoredSysChanRecord>[];
    for (final fp in fps) {
      final r = stored[bytesToHex(fp)];
      if (r != null) out.add(r);
    }
    return out;
  }

  Iterable<StoredSysChanRecord> allRecords(String channelIdHex) =>
      (_records[channelIdHex] ?? const {}).values;

  StoredSysChanRecord? recordById(String channelIdHex, String recordIdHex) {
    for (final r in allRecords(channelIdHex)) {
      if (_hex(r.record.recordId) == recordIdHex) return r;
    }
    return null;
  }

  bool isRetracted(String channelIdHex, String recordIdHex) =>
      _retractedTargets[channelIdHex]?.containsKey(recordIdHex) ?? false;

  // ── Signing / building (author side) ───────────────────────────────

  static Uint8List _randomRecordId() {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(16, (_) => r.nextInt(256)));
  }

  /// Canonical bytes = record serialized with both sig fields empty.
  static Uint8List canonicalBytes(proto.SystemChannelRecord record) {
    final clone =
        proto.SystemChannelRecord.fromBuffer(record.writeToBuffer())
          ..sigEd25519 = Uint8List(0)
          ..sigMlDsa = Uint8List(0);
    return clone.writeToBuffer();
  }

  /// Builds and hybrid-signs a record (H-2 pattern: Ed25519 + ML-DSA-65
  /// over the canonical content, inline pubkeys for stand-alone verify).
  static proto.SystemChannelRecord buildSigned({
    required Uint8List channelId,
    required int kind,
    required Uint8List authorUserId,
    required Uint8List ed25519Pk,
    required Uint8List ed25519Sk,
    required Uint8List mlDsaPk,
    required Uint8List mlDsaSk,
    String text = '',
    Uint8List? targetRecordId,
    int voteOption = 0,
    Uint8List? recordId,
    int? timestampMs,
  }) {
    final record = proto.SystemChannelRecord()
      ..channelId = channelId
      ..recordId = recordId ?? _randomRecordId()
      ..kind = kind
      ..authorUserId = authorUserId
      ..authorEd25519Pk = ed25519Pk
      ..authorMlDsaPk = mlDsaPk
      ..timestampMs =
          Int64(timestampMs ?? DateTime.now().toUtc().millisecondsSinceEpoch)
      ..text = text
      ..voteOption = voteOption;
    if (targetRecordId != null) record.targetRecordId = targetRecordId;

    final canonical = canonicalBytes(record);
    record.sigEd25519 = SodiumFFI().signEd25519(canonical, ed25519Sk);
    record.sigMlDsa = OqsFFI().mlDsaSign(canonical, mlDsaSk);
    return record;
  }

  // ── Admission (receiver side, §8.2 context-proof) ──────────────────

  /// Verifies the hybrid self-signature + founding binding. Pure check,
  /// no state change.
  bool verifyRecord(proto.SystemChannelRecord record) {
    try {
      if (record.authorEd25519Pk.length != 32) return false;
      final canonical = canonicalBytes(record);
      if (!SodiumFFI().verifyEd25519(
          canonical,
          Uint8List.fromList(record.sigEd25519),
          Uint8List.fromList(record.authorEd25519Pk))) {
        return false;
      }
      if (!OqsFFI().mlDsaVerify(
          canonical,
          Uint8List.fromList(record.sigMlDsa),
          Uint8List.fromList(record.authorMlDsaPk))) {
        return false;
      }
      // UserID-Founding-Binding (§9.5.7): the trust anchor for unknown-
      // author admission. Rotated authors verify via the AuthManifest
      // rotation chain when a chainVerifier is wired.
      final derived = HdWallet.computeUserId(
          Uint8List.fromList(record.authorEd25519Pk), NetworkSecret.secret);
      if (_hex(derived) != _hex(record.authorUserId)) {
        final chain = chainVerifier;
        if (chain == null ||
            !chain(Uint8List.fromList(record.authorUserId),
                Uint8List.fromList(record.authorEd25519Pk))) {
          return false;
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Receiver-side daily rate limit per author (§9.5.3/§9.5.5): counts
  /// POSTs from this author stored in the last 24 h.
  bool _postRateLimitOk(String channelIdHex, String authorHex) {
    final limit = SystemChannels.isFeatureReqChannel(channelIdHex)
        ? SystemChannels.maxFeaturePostsPerDay
        : SystemChannels.maxReportsPerDay;
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 24))
        .millisecondsSinceEpoch;
    var count = 0;
    for (final r in allRecords(channelIdHex)) {
      if (r.record.kind != SysChanKind.post) continue;
      if (_hex(r.record.authorUserId) != authorHex) continue;
      if (r.record.timestampMs.toInt() < cutoff) continue;
      count++;
    }
    return count < limit;
  }

  /// Full admission pipeline for a wire record. Returns what happened so
  /// the service layer can bridge UI state (conversation message, tally
  /// refresh, tombstone application).
  SysChanAdmission tryAdmit(Uint8List recordBytes,
      {proto.SystemChannelRecord? parsed}) {
    proto.SystemChannelRecord record;
    try {
      record = parsed ?? proto.SystemChannelRecord.fromBuffer(recordBytes);
    } catch (_) {
      return SysChanAdmission.rejected;
    }

    final channelIdHex = _hex(record.channelId);
    if (!SystemChannels.isSystemChannel(channelIdHex)) {
      return SysChanAdmission.rejected;
    }

    final fpHex = fingerprintHexOf(recordBytes);
    if ((_records[channelIdHex]?.containsKey(fpHex) ?? false) ||
        (_knownGone[channelIdHex]?.contains(fpHex) ?? false)) {
      return SysChanAdmission.duplicate;
    }

    if (!verifyRecord(record)) {
      _log.debug('syschan: signature/binding verify failed for '
          '$fpHex in ${channelIdHex.substring(0, 8)}');
      return SysChanAdmission.rejected;
    }

    final authorHex = _hex(record.authorUserId);
    final recordIdHex = _hex(record.recordId);
    final stored = StoredSysChanRecord(
        record: record,
        bytes: recordBytes,
        fingerprintHex: fpHex);

    switch (record.kind) {
      case SysChanKind.post:
        if (!_postRateLimitOk(channelIdHex, authorHex)) {
          _log.info('syschan: POST rate limit for author '
              '${authorHex.substring(0, 8)} — dropped');
          return SysChanAdmission.rejected;
        }
        // Anti-resurrection: a tombstone for this record id (by the same
        // author) blocks admission of the original content.
        final retractedBy = _retractedTargets[channelIdHex]?[recordIdHex];
        if (retractedBy != null) {
          if (retractedBy == authorHex) {
            (_knownGone[channelIdHex] ??= {}).add(fpHex);
            return SysChanAdmission.duplicate;
          }
          // Tombstone author does not match the real post author — the
          // retract was invalid; drop the bogus tombstone and admit.
          _retractedTargets[channelIdHex]!.remove(recordIdHex);
        }
        (_records[channelIdHex] ??= {})[fpHex] = stored;
        return SysChanAdmission.postAdmitted;

      case SysChanKind.vote:
        if (!SystemChannels.isFeatureReqChannel(channelIdHex)) {
          return SysChanAdmission.rejected;
        }
        if (record.targetRecordId.isEmpty) return SysChanAdmission.rejected;
        (_records[channelIdHex] ??= {})[fpHex] = stored;
        return SysChanAdmission.voteAdmitted;

      case SysChanKind.retract:
        if (record.targetRecordId.isEmpty) return SysChanAdmission.rejected;
        final targetIdHex = _hex(record.targetRecordId);
        final target = recordById(channelIdHex, targetIdHex);
        if (target != null &&
            _hex(target.record.authorUserId) != authorHex) {
          // Author-only retraction (§9.5.7 D2).
          return SysChanAdmission.rejected;
        }
        (_records[channelIdHex] ??= {})[fpHex] = stored;
        (_retractedTargets[channelIdHex] ??= {})[targetIdHex] = authorHex;
        // GC rule: drop the target's content but keep its fingerprint so
        // anti-entropy never re-fetches it and the +1 dedup metadata
        // survives (§9.5.7).
        if (target != null) {
          _records[channelIdHex]!.remove(target.fingerprintHex);
          (_knownGone[channelIdHex] ??= {}).add(target.fingerprintHex);
        }
        return SysChanAdmission.retractAdmitted;

      default:
        return SysChanAdmission.rejected;
    }
  }

  /// Stores a locally-built (already signed) record without re-verifying.
  /// Same tombstone/GC side effects as [tryAdmit].
  StoredSysChanRecord storeLocal(proto.SystemChannelRecord record) {
    final bytes = record.writeToBuffer();
    final admission = tryAdmit(bytes, parsed: record);
    final fpHex = fingerprintHexOf(bytes);
    final channelIdHex = _hex(record.channelId);
    if (admission == SysChanAdmission.rejected) {
      _log.warn('syschan: local record rejected by own admission '
          '($fpHex, kind=${record.kind})');
    }
    return _records[channelIdHex]?[fpHex] ??
        StoredSysChanRecord(
            record: record, bytes: bytes, fingerprintHex: fpHex);
  }

  // ── FR tally (§9.5.3 — open vote records, tallied locally) ─────────

  /// Latest vote per author wins (LWW by record timestamp).
  FrTally tallyFor(String channelIdHex, String targetRecordIdHex) {
    final latest = <String, proto.SystemChannelRecord>{};
    for (final r in allRecords(channelIdHex)) {
      if (r.record.kind != SysChanKind.vote) continue;
      if (_hex(r.record.targetRecordId) != targetRecordIdHex) continue;
      final authorHex = _hex(r.record.authorUserId);
      final prev = latest[authorHex];
      if (prev == null ||
          r.record.timestampMs.toInt() > prev.timestampMs.toInt()) {
        latest[authorHex] = r.record;
      }
    }
    var ja = 0, nein = 0, egal = 0;
    for (final v in latest.values) {
      switch (v.voteOption) {
        case SysChanVote.ja:
          ja++;
        case SysChanVote.nein:
          nein++;
        case SysChanVote.egal:
          egal++;
      }
    }
    return FrTally(ja, nein, egal);
  }

  /// The caller's current vote on a target, or null.
  int? ownVote(
      String channelIdHex, String targetRecordIdHex, String ownUserIdHex) {
    proto.SystemChannelRecord? latest;
    for (final r in allRecords(channelIdHex)) {
      if (r.record.kind != SysChanKind.vote) continue;
      if (_hex(r.record.targetRecordId) != targetRecordIdHex) continue;
      if (_hex(r.record.authorUserId) != ownUserIdHex) continue;
      if (latest == null ||
          r.record.timestampMs.toInt() > latest.timestampMs.toInt()) {
        latest = r.record;
      }
    }
    return latest?.voteOption;
  }

  // ── Eviction (§9.5.5) ──────────────────────────────────────────────

  /// Enforces the per-channel storage cap. Bug Log: oldest POSTs first.
  /// Feature Requests: lowest `net_votes` first, ties oldest first. VOTE
  /// and RETRACT records are never evicted directly (small; retracts must
  /// survive to keep anti-resurrection); votes of an evicted FR post are
  /// evicted with it.
  int evictToLimit(String channelIdHex,
      {int maxBytes = SystemChannels.maxChannelStorageBytes}) {
    final records = _records[channelIdHex];
    if (records == null || records.isEmpty) return 0;

    int totalBytes() =>
        records.values.fold(0, (sum, r) => sum + r.bytes.length);
    if (totalBytes() <= maxBytes) return 0;

    final posts = records.values
        .where((r) => r.record.kind == SysChanKind.post)
        .toList();
    if (SystemChannels.isFeatureReqChannel(channelIdHex)) {
      posts.sort((a, b) {
        final netA =
            tallyFor(channelIdHex, _hex(a.record.recordId)).net;
        final netB =
            tallyFor(channelIdHex, _hex(b.record.recordId)).net;
        if (netA != netB) return netA.compareTo(netB);
        return a.record.timestampMs.compareTo(b.record.timestampMs);
      });
    } else {
      posts.sort(
          (a, b) => a.record.timestampMs.compareTo(b.record.timestampMs));
    }

    var evicted = 0;
    for (final post in posts) {
      if (totalBytes() <= maxBytes) break;
      final postIdHex = _hex(post.record.recordId);
      records.remove(post.fingerprintHex);
      (_knownGone[channelIdHex] ??= {}).add(post.fingerprintHex);
      evicted++;
      // Evict this post's votes with it.
      final voteFps = records.values
          .where((r) =>
              r.record.kind == SysChanKind.vote &&
              _hex(r.record.targetRecordId) == postIdHex)
          .map((r) => r.fingerprintHex)
          .toList();
      for (final fp in voteFps) {
        records.remove(fp);
        _knownGone[channelIdHex]!.add(fp);
      }
    }
    if (evicted > 0) {
      _log.info('syschan: evicted $evicted post(s) from '
          '${channelIdHex.substring(0, 8)} (cap ${maxBytes ~/ (1024 * 1024)}MB)');
    }
    return evicted;
  }

  // ── Persistence ────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'channels': _records.map((ch, records) => MapEntry(ch, {
              'records': records.values.map((r) => base64Encode(r.bytes)).toList(),
              'gone': (_knownGone[ch] ?? const <String>{}).toList(),
            })),
      };

  void loadFromJson(Map<String, dynamic> json) {
    try {
      final channels = json['channels'] as Map<String, dynamic>? ?? {};
      for (final entry in channels.entries) {
        final ch = entry.key;
        if (!SystemChannels.isSystemChannel(ch)) continue;
        final data = entry.value as Map<String, dynamic>;
        _knownGone[ch] = ((data['gone'] as List<dynamic>?) ?? const [])
            .map((e) => e as String)
            .toSet();
        for (final b64 in (data['records'] as List<dynamic>?) ?? const []) {
          try {
            final bytes = base64Decode(b64 as String);
            final record = proto.SystemChannelRecord.fromBuffer(bytes);
            final fpHex = fingerprintHexOf(bytes);
            (_records[ch] ??= {})[fpHex] = StoredSysChanRecord(
                record: record, bytes: bytes, fingerprintHex: fpHex);
            if (record.kind == SysChanKind.retract &&
                record.targetRecordId.isNotEmpty) {
              (_retractedTargets[ch] ??= {})[_hex(record.targetRecordId)] =
                  _hex(record.authorUserId);
            }
          } catch (_) {/* skip corrupt entry */}
        }
      }
    } catch (e) {
      _log.warn('syschan: load failed: $e');
    }
  }
}
