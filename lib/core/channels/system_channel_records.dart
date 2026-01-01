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
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/identity/identity_context.dart'
    show StoredRotationLink;
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/storage/message_store.dart';
import 'package:cleona/core/util/hex.dart' show bytesToHex, hexToBytes;
import 'package:cleona/generated/proto/app_payloads.pb.dart' as proto;
import 'package:fixnum/fixnum.dart';

/// Protobuf `bytes` getters are `List<int>` — wrap for [bytesToHex].
String _hex(List<int> bytes) => bytesToHex(Uint8List.fromList(bytes));

/// Record kinds (proto `SystemChannelRecord.kind`).
class SysChanKind {
  static const int post = 0;
  static const int vote = 1;
  static const int retract = 2;
}

/// FR vote options (§9.5.3): 0 = "Ja" (yes), 1 = "Nein" (no), 2 = "Egal" (don't care).
class SysChanVote {
  static const int yes = 0;
  static const int no = 1;
  static const int irrelevant = 2;
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
  final int yes;
  final int no;
  final int irrelevant;
  const FrTally(this.yes, this.no, this.irrelevant);
  int get net => yes - no;
}

class SystemChannelRecordStore {
  final CLogger _log;

  /// Upper limit for the length of the rotation chain travelling along (S392).
  ///
  /// It is a **DoS gate, not the spec** — v4_2 names no number.
  /// Without it, a self-signed record with N invented links costs the
  /// recipient N ML-DSA checks, while the attacker signs only once.
  /// At 32 that is in the worst case ~32 checks and a record of about
  /// 235 KB.
  ///
  /// The number is deliberately chosen far above any plausible number of
  /// emergency rotations of an identity, because a reached limit would
  /// lock the author out — exactly what §14.5 ("a rotation is never
  /// blocked, only shown") forbids. Whoever lowers it lowers it against
  /// this sentence.
  static const int maxRotationChainLinks = 32;

  /// channelIdHex → fingerprintHex → record
  final Map<String, Map<String, StoredSysChanRecord>> _records = {};

  /// Fingerprints we have seen but no longer store (evicted, or POST
  /// content GC'd after RETRACT). Anti-resurrection: WANT never asks for
  /// these, PUSH of them is treated as duplicate.
  final Map<String, Set<String>> _knownGone = {};

  /// channelIdHex → retracted target recordIdHex → author userIdHex who
  /// signed the retract (must match the target's author).
  final Map<String, Map<String, String>> _retractedTargets = {};

  /// Encrypted storage (S366). `null` = no write-back — that is the path
  /// for pure computation checks and for every caller that needs the
  /// holdings only in memory.
  final MessageStore? _store;

  /// Area for the records themselves: key `<channel>:<fingerprint>`,
  /// value `{'b': base64(bytes)}`.
  static const String kAreaRecords = 'syschan_records';

  /// Area for the tombstones (`_knownGone`): the same key cut, empty
  /// value. A SEPARATE area and not a special key in the record area
  /// — the tombstones grow WITHOUT A CAP, while the records are capped
  /// at 25 MB per channel (§9.5.5). Two laws of growth do not belong in
  /// one area, and `countArea` thus quantifies both separately.
  static const String kAreaGone = 'syschan_gone';

  SystemChannelRecordStore({String? profileDir, this._store})
      : _log = CLogger.get('syschan', profileDir: profileDir);

  static String _key(String channelIdHex, String fpHex) =>
      '$channelIdHex:$fpHex';

  /// Writes ONE record. Formerly every change rewrote the whole
  /// collection — in the field profile 1 838 533 B, the second-largest
  /// file of all. Exactly for that reason a 2-second batching hung on it;
  /// with this granularity it is moot and has been dropped.
  void _persistRecord(String channelIdHex, StoredSysChanRecord stored) {
    final s = _store;
    if (s == null) return;
    try {
      s.putEntry(kAreaRecords, _key(channelIdHex, stored.fingerprintHex),
          {'b': base64Encode(stored.bytes)});
    } catch (e) {
      _log.warn('syschan: persist record failed: $e');
    }
  }

  void _forgetRecord(String channelIdHex, String fpHex) {
    final s = _store;
    if (s == null) return;
    try {
      s.removeEntry(kAreaRecords, _key(channelIdHex, fpHex));
    } catch (e) {
      _log.warn('syschan: remove record failed: $e');
    }
  }

  /// A tombstone. It carries the anti-resurrection (§9.5.7) and must
  /// therefore NEVER disappear together with the record.
  void _persistGone(String channelIdHex, String fpHex) {
    final s = _store;
    if (s == null) return;
    try {
      s.putEntry(
          kAreaGone, _key(channelIdHex, fpHex), const <String, dynamic>{});
    } catch (e) {
      _log.warn('syschan: persist tombstone failed: $e');
    }
  }

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
    List<proto.SysChanRotationLink> rotationChain =
        const <proto.SysChanRotationLink>[],
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
    // The chain belongs in the canonical bytes BEFORE signing —
    // otherwise it could be swapped in transit (S392).
    if (rotationChain.isNotEmpty) record.rotationChain.addAll(rotationChain);

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
      // author admission.
      // S388 ("identifier = A", v4.2 §4.1): the UserID derives from BOTH
      // signing keys, and the record carries both inline. An ML-DSA key
      // of wrong length throws in `computeUserId` and ends below in the
      // `catch` as a rejection.
      if (record.rotationChain.isEmpty) {
        final derived = HdWallet.computeUserId(
            Uint8List.fromList(record.authorEd25519Pk),
            Uint8List.fromList(record.authorMlDsaPk));
        return _hex(derived) == _hex(record.authorUserId);
      }
      // Rotated author: the chain IS the proof (§4.1, §4.5.4, §14.5).
      return _verifyRotationChain(record);
    } catch (_) {
      return false;
    }
  }

  /// Checks the chain travelling along, founding → current keys (S392).
  ///
  /// It replaces the direct binding as soon as it is present: a
  /// non-empty chain MUST hold, it is never an additional offer.
  /// Otherwise a never-rotated record could append a junk chain and
  /// still get through — and nobody would check anything any more.
  ///
  /// The order is intentional: first the four cheap structure and
  /// binding checks (byte comparisons, one SHA-256), only then the
  /// expensive signature checks. An attacker must not be able to
  /// trigger N ML-DSA checks with a forged record.
  bool _verifyRotationChain(proto.SystemChannelRecord record) {
    final chain = record.rotationChain;
    if (chain.length > maxRotationChainLinks) return false;

    // (1) Founding anchor: the first link holds the keys from which the
    //     UserID derives. If it does not match them, the chain belongs to
    //     another identity.
    final founding = HdWallet.computeUserId(
        Uint8List.fromList(chain.first.oldEd25519Pk),
        Uint8List.fromList(chain.first.oldMlDsaPk));
    if (_hex(founding) != _hex(record.authorUserId)) return false;

    // (2) The chain must be a chain: the old pair of every link is the
    //     new pair of its predecessor.
    for (var i = 1; i < chain.length; i++) {
      if (_hex(chain[i].oldEd25519Pk) != _hex(chain[i - 1].newEd25519Pk)) {
        return false;
      }
      if (_hex(chain[i].oldMlDsaPk) != _hex(chain[i - 1].newMlDsaPk)) {
        return false;
      }
    }

    // (3) The last link must arrive at the keys with which the record is
    //     signed — otherwise the chain proves a foreign path.
    if (_hex(chain.last.newEd25519Pk) != _hex(record.authorEd25519Pk)) {
      return false;
    }
    if (_hex(chain.last.newMlDsaPk) != _hex(record.authorMlDsaPk)) {
      return false;
    }

    // (4) Every link is hybrid-signed by the OLD pair (§4.5.4). First
    //     Ed25519 (cheap), then ML-DSA — and both are mandatory: a link
    //     with an empty signature (LD-8 with outdated user sig SK,
    //     `identity_context.dart rotateDelegation`) fails here.
    for (final link in chain) {
      if (link.oldEd25519Pk.length != 32) return false;
      final content = StoredRotationLink.linkContentOf(
          Uint8List.fromList(link.newEd25519Pk),
          Uint8List.fromList(link.newMlDsaPk));
      if (!SodiumFFI().verifyEd25519(
          content,
          Uint8List.fromList(link.sigEd25519),
          Uint8List.fromList(link.oldEd25519Pk))) {
        return false;
      }
      if (!OqsFFI().mlDsaVerify(
          content,
          Uint8List.fromList(link.sigMlDsa),
          Uint8List.fromList(link.oldMlDsaPk))) {
        return false;
      }
    }
    return true;
  }

  /// Maps the persisted chain of an identity onto the wire form.
  /// ONE place, so that producer (`_publishSystemChannelRecord`) and
  /// checker see the same shape.
  static List<proto.SysChanRotationLink> wireChainOf(
          Iterable<StoredRotationLink> chain) =>
      <proto.SysChanRotationLink>[
        for (final l in chain)
          proto.SysChanRotationLink()
            ..oldEd25519Pk = l.oldEd25519Pk
            ..oldMlDsaPk = l.oldMlDsaPk
            ..newEd25519Pk = l.newEd25519Pk
            ..newMlDsaPk = l.newMlDsaPk
            ..sigEd25519 = l.oldSignatureEd25519
            ..sigMlDsa = l.oldSignatureMlDsa
      ];

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
            _persistGone(channelIdHex, fpHex);
            return SysChanAdmission.duplicate;
          }
          // Tombstone author does not match the real post author — the
          // retract was invalid; drop the bogus tombstone and admit.
          _retractedTargets[channelIdHex]!.remove(recordIdHex);
        }
        (_records[channelIdHex] ??= {})[fpHex] = stored;
        _persistRecord(channelIdHex, stored);
        return SysChanAdmission.postAdmitted;

      case SysChanKind.vote:
        if (!SystemChannels.isFeatureReqChannel(channelIdHex)) {
          return SysChanAdmission.rejected;
        }
        if (record.targetRecordId.isEmpty) return SysChanAdmission.rejected;
        (_records[channelIdHex] ??= {})[fpHex] = stored;
        _persistRecord(channelIdHex, stored);
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
        _persistRecord(channelIdHex, stored);
        (_retractedTargets[channelIdHex] ??= {})[targetIdHex] = authorHex;
        // GC rule: drop the target's content but keep its fingerprint so
        // anti-entropy never re-fetches it and the +1 dedup metadata
        // survives (§9.5.7).
        if (target != null) {
          _records[channelIdHex]!.remove(target.fingerprintHex);
          (_knownGone[channelIdHex] ??= {}).add(target.fingerprintHex);
          _forgetRecord(channelIdHex, target.fingerprintHex);
          _persistGone(channelIdHex, target.fingerprintHex);
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
    var yes = 0, no = 0, irrelevant = 0;
    for (final v in latest.values) {
      switch (v.voteOption) {
        case SysChanVote.yes:
          yes++;
        case SysChanVote.no:
          no++;
        case SysChanVote.irrelevant:
          irrelevant++;
      }
    }
    return FrTally(yes, no, irrelevant);
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
      _forgetRecord(channelIdHex, post.fingerprintHex);
      _persistGone(channelIdHex, post.fingerprintHex);
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
        _forgetRecord(channelIdHex, fp);
        _persistGone(channelIdHex, fp);
      }
    }
    if (evicted > 0) {
      _log.info('syschan: evicted $evicted post(s) from '
          '${channelIdHex.substring(0, 8)} (cap ${maxBytes ~/ (1024 * 1024)}MB)');
    }
    return evicted;
  }

  // ── Persistence (S366: encrypted storage instead of file) ─────────
  //
  // WHAT HAS CHANGED AND WHY. Until S366 the whole holdings lay in
  // `syschan_records.json` and were rewritten completely on EVERY
  // change — in the field profile 1 838 533 B. Against that stood a
  // 2-second batching in the service, which damped the write storm and
  // opened a window in doing so: whoever stopped within these two
  // seconds lost the record just published (`stop()` cancelled the
  // timer). Both are gone. Every change now writes EXACTLY THE ROW that
  // changed, immediately.
  //
  // NO DATA-LOSS LATCH NEEDED, and that is a statement, not an
  // omission: there is no full-write path here any more that a failed
  // load could overwrite with empty holdings. `putEntry`/`removeEntry`
  // touch only what the caller is holding in hand right now, and
  // `evictToLimit` returns immediately on empty holdings.

  /// Loads records and tombstones from the storage.
  void loadFromStore() {
    final s = _store;
    if (s == null) return;
    try {
      for (final key in s.loadArea(kAreaGone).keys) {
        final sep = key.indexOf(':');
        if (sep <= 0) continue;
        final ch = key.substring(0, sep);
        if (!SystemChannels.isSystemChannel(ch)) continue;
        (_knownGone[ch] ??= <String>{}).add(key.substring(sep + 1));
      }
      for (final entry in s.loadArea(kAreaRecords).entries) {
        final sep = entry.key.indexOf(':');
        if (sep <= 0) continue;
        final ch = entry.key.substring(0, sep);
        if (!SystemChannels.isSystemChannel(ch)) continue;
        try {
          final bytes = base64Decode(entry.value['b'] as String);
          final record = proto.SystemChannelRecord.fromBuffer(bytes);
          // The fingerprint is RECOMPUTED and not taken over from the
          // key: it is the record's ID card, and a key that does not match
          // its content must not bring it back under a false name.
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
    } catch (e) {
      _log.warn('syschan: load failed: $e');
    }
  }

  /// Number of stored records or tombstones — for guards and for
  /// callers that must know before a write path whether the storage
  /// holds anything.
  int storedRecordCount() => _store?.countArea(kAreaRecords) ?? 0;
  int storedGoneCount() => _store?.countArea(kAreaGone) ?? 0;
}
