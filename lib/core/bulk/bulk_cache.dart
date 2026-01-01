// The bulk quota — the fourth storage class (§21.2, §21.3.3 no. 3).
//
// THE SPEC, verbatim (§21.3.3 no. 3):
//
//   "**Bulk as its own, fourth capped class.** Desktop installations only;
//    mobile nodes carry no bulk. **1 GB default** … **Lowest priority:**
//    under disk pressure, bulk is trimmed first (ahead of the delivery
//    layer), with eviction within the class by the §20 rule."
//
// and §21.2:
//
//   "Bulk blocks are uniform cells on the wire (entry type 0x05) but they
//    are **not** delivery-layer cells: they live in their own budget class
//    (E-53), are evicted first under pressure, and their placement is
//    addressed per holder (§9.3), not replicated `m × R`."
//
// WHAT THIS CLASS THEREFORE IS NOT: a second `SecureStore`. Four
// differences, all four from the spec:
//
// 1. **The cap is class-wide in bytes**, not per tag line in cells.
//    `SecureStore` evicts "only within the quota" of a tag line
//    (§20), because there every line has its own quota. Bulk has ONE
//    quota for the whole class (1 GB) — so it evicts class-wide,
//    oldest first.
// 2. **There is a clock, no epochs.** `TTL_media` is 7 d, the epoch
//    24 h; an epoch calculation would be a rounding without benefit here.
// 3. **On mobile the class does not exist at all.** A harvester node
//    (Android, iOS) holds no bulk — not "little", but none.
// 4. **Lowest priority.** [trim] is the handle that the layer
//    above pulls FIRST under disk pressure, before the delivery layer.
//
// WHAT IT SHARES WITH `SecureStore` and what is taken over: the
// eviction order ("oldest/near-expiry first"), the self-victim latch
// (whoever would itself be the oldest is rejected instead of throwing out a younger
// one) and the `evicted` counter that §21.3.3 no. 4 explicitly
// requires: "a node that evicts under budget pressure shows this visibly
// in the network statistics (§25)."
library;

import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/sync/budget_class.dart';

import 'bulk_block_seal.dart';
import 'bulk_params.dart';

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

/// The tag of a held block: SHA-256 over the sealed
/// bytes.
///
/// Content-based, not carried along — just like `cellDigest` in the
/// delivery layer. Here it carries two loads: the deduplication in the cache
/// and the have-list of the scanner (`scan(exclude:)`), so that a second
/// pass does not pull the same bytes over the wire once more.
Uint8List bulkBlockDigest(Uint8List sealed) => SodiumFFI().sha256(sealed);

/// Ein gehaltener Block.
final class BulkEntry {
  final Uint8List tag;
  final Uint8List sealed;
  final Uint8List digest;

  /// Unix seconds of the placement, by the clock of the HOLDER.
  ///
  /// Not by that of the placer: otherwise the placer would choose its
  /// own expiry date and could immunise itself against any eviction with a date in the
  /// future.
  final int placedAt;

  /// Arrival number — the fine clock next to the coarse one, for the case of
  /// the same second. The same rationale as for `StoredCell.seq`.
  final int seq;

  BulkEntry(this.tag, this.sealed, this.digest, this.placedAt, this.seq);

  int get bytes => sealed.length;
}

/// The bulk cache of a holder.
final class BulkCache {
  /// Does this node hold bulk at all? Carrier (desktop) only.
  final bool enabled;

  /// Cap of the class in bytes.
  final int capacityBytes;

  /// `TTL_media` in seconds.
  final int ttlSeconds;

  /// How long it is still held after the DECODED receipt.
  final int clearAfterReceiptSeconds;

  final Map<String, List<BulkEntry>> _byTag = <String, List<BulkEntry>>{};

  /// Tags of all held blocks — the deduplication, class-wide.
  ///
  /// Class-wide and not per tag line, because the same block comes from several
  /// seeders with `BulkSeedPolicy.sequential` and §26.6.1
  /// builds on exactly that: "the cache holds it once instead of twice".
  ///
  /// THAT THIS MAY BE CLASS-WIDE depends on an invariant from
  /// `bulk_keys.dart` and not on convenience: tag and
  /// seal key BOTH derive from the same root `K_T`. Same
  /// sealed bytes thus mean same seal key, same
  /// seal key means same root, and same root means
  /// same tag. A block thus cannot appear under two tag lines at all
  /// — otherwise the class deduplication would lose it for the
  /// second line.
  final Map<String, BulkEntry> _byDigest = <String, BulkEntry>{};

  /// Tag lines for which a DECODED receipt was seen, with the
  /// time: `tagHex -> unixSeconds`.
  final Map<String, int> _decodedAt = <String, int>{};

  int _seq = 0;
  int _bytes = 0;

  /// How often eviction happened under quota pressure (§21.3.3 no. 4).
  int evicted = 0;

  /// How often a placement was rejected — mobile, too large, or the
  /// own next victim.
  int rejected = 0;

  /// How often a placement was recognised as a duplicate (not an error).
  int deduplicated = 0;

  /// How many blocks expiry has removed.
  int expiredBlocks = 0;

  BulkCache({
    this.enabled = true,
    this.capacityBytes = kBulkCacheCapacityBytes,
    this.ttlSeconds = kTtlMediaSeconds,
    this.clearAfterReceiptSeconds = kBulkClearAfterReceiptSeconds,
  });

  /// The cache the platform class allows (§21.3.3 no. 3, E-53).
  ///
  /// Harvesters (Android, iOS) get a DISABLED cache, not a
  /// small one: "mobile nodes carry no bulk". A small one would be worse
  /// than none — it would attract placements that it immediately evicts again,
  /// and would cost mobile data volume for nothing.
  factory BulkCache.forBudgetClass(FieldBudgetClass cls,
      {int capacityBytes = kBulkCacheCapacityBytes}) {
    return switch (cls) {
      FieldBudgetClass.carrier =>
        BulkCache(enabled: true, capacityBytes: capacityBytes),
      FieldBudgetClass.harvester => BulkCache(enabled: false, capacityBytes: 0),
    };
  }

  int get bytesHeld => _bytes;

  int get blockCount => _byDigest.length;

  int get tagLineCount => _byTag.length;

  /// Accepts a sealed block under [tag].
  ///
  /// `false` means: not accepted. Five reasons, and each has its
  /// own counter, so that they can be told apart in operation.
  bool place(Uint8List tag, Uint8List sealed, DateTime nowUtc) {
    if (!enabled) {
      rejected++;
      return false;
    }
    if (sealed.length != kSealedBulkBlockBytes) {
      rejected++;
      return false;
    }
    if (sealed.length > capacityBytes) {
      rejected++;
      return false;
    }
    final now = nowUtc.toUtc().millisecondsSinceEpoch ~/ 1000;
    final digest = bulkBlockDigest(sealed);
    final dHex = _hex(digest);
    if (_byDigest.containsKey(dHex)) {
      // THE SAME BLOCK, already there. That is the normal case with several
      // seeders with consecutive seeds and the reason why the nonce
      // is derived and not drawn (`bulk_keys.dart`).
      deduplicated++;
      return true;
    }

    // Make room: oldest first, class-wide (§20 rule within
    // the class).
    while (_bytes + sealed.length > capacityBytes) {
      final victim = _oldest();
      if (victim == null) {
        rejected++;
        return false;
      }
      // THE SELF-VICTIM LATCH. If the newcomer itself were the
      // next victim, accepting it would cost a foreign block without
      // any gain. In operation this cannot happen — the holder
      // stamps `now`, so the newcomer is always the youngest —,
      // but the check guards against a later caller that
      // makes the timestamp selectable.
      if (now < victim.placedAt) {
        rejected++;
        return false;
      }
      _remove(victim);
      evicted++;
    }

    final e = BulkEntry(Uint8List.fromList(tag), sealed, digest, now, _seq++);
    (_byTag.putIfAbsent(_hex(tag), () => <BulkEntry>[])).add(e);
    _byDigest[dHex] = e;
    _bytes += e.bytes;
    return true;
  }

  /// **Scan, don't query** (§26.6.1: "the cache is not queried but
  /// scanned").
  ///
  /// The asker names a tag line and gets what lies under it — they
  /// NEVER name a single block. That is not convenience,
  /// but the property that §26.6.2 claims for the delta updates:
  /// "A delta fetch reveals nothing about the fetcher's
  /// starting version, because the cache is not queried but scanned." A
  /// query per block would be exactly the bookkeeping that a rateless
  /// code abolishes (§9: "no block is special, no index is allocated").
  ///
  /// [have] is the asker's have-list: tags they already have.
  /// They are not sent to them again, but NOT deleted —
  /// §14.2 lets all devices of an identity harvest the same line, and
  /// the second declares nothing and needs everything. The holder does not
  /// remember the list: it applies to exactly this request, no
  /// state per fetcher arises and thus no recognisable identifier.
  ///
  /// [limit] caps the answer. A tag line can hold tens of thousands of blocks;
  /// sending them in one go would be a traffic burst that
  /// `R_bulk` is precisely meant to limit.
  ///
  /// [offset] skips the first so many ENTRIES of the line
  /// before the have-list is applied.
  ///
  /// ── WHY IT NEEDS BOTH AND NOT JUST THE HAVE-LIST ─────────
  ///
  /// Because the have-list must fit into ONE frame and holds 33 tags there
  /// (`bulk_frames.dart`, `kBulkScanHaveSlots`). An asker with
  /// 6348 blocks can thus, from the third round on, only declare a
  /// fraction of what they have — and gets the same entries from here
  /// again and again. Recomputed in
  /// `buildBulkScan`: +1 new block per round with 31 discarded.
  ///
  /// [offset] is the POSITION, the have-list is the CONTENT. The
  /// position alone does not suffice, because eviction ([evicted]) and
  /// expiry shorten the line and thus shift everything behind;
  /// the content alone does not suffice, because it does not fit into the frame.
  /// Together they are exact, without either side having to hold state per
  /// fetcher — the holder still remembers NOTHING
  /// (§26.6.1: "no state per fetcher").
  List<BulkEntry> scan(Uint8List tag,
          {Iterable<Uint8List> have = const <Uint8List>[],
          int? limit,
          int offset = 0}) =>
      scanFrom(tag, have: have, limit: limit, offset: offset).entries;

  /// Like [scan], but additionally returns **by how many entries
  /// the line was traversed in the process**.
  ///
  /// ── WHY THE SECOND NUMBER IS NEEDED, EXACTLY ─────────────────────────
  ///
  /// The scanner adds the answer to its `offset` for the next
  /// pass (`bulk_frames.dart`, `skip`). If it takes the number of
  /// RETURNED entries for that, it counts too few as soon as the
  /// have-list has filtered something out — the skipped entries
  /// were traversed but not counted. Its `offset` would lag behind
  /// the true position, and the next pass would run once more
  /// over the same entries.
  ///
  /// The error is small — with `offset > 0` the have-list as a rule
  /// filters nothing, because every block is placed exactly ONCE according to §9.3
  /// and the scanner has never seen the entries behind it —,
  /// but it is unnecessary: the right number arises here anyway.
  ///
  /// [advanced] is NOT `entries.length`, and it is also not
  /// `line.length - offset`: it is exactly the distance that this
  /// pass covered, so `0` if nothing is left.
  ({List<BulkEntry> entries, int advanced}) scanFrom(Uint8List tag,
      {Iterable<Uint8List> have = const <Uint8List>[],
      int? limit,
      int offset = 0}) {
    const empty = (entries: <BulkEntry>[], advanced: 0);
    if (!enabled) return empty;
    final already = <String>{for (final h in have) _hex(h)};
    final line = _byTag[_hex(tag)];
    if (line == null) return empty;
    final from = offset < 0 ? 0 : offset;
    if (from >= line.length) return empty;
    final out = <BulkEntry>[];
    var i = from;
    for (; i < line.length; i++) {
      final e = line[i];
      if (already.contains(_hex(e.digest))) continue;
      out.add(e);
      if (limit != null && out.length >= limit) {
        i++;
        break;
      }
    }
    return (entries: out, advanced: i - from);
  }

  /// The recipient has acknowledged (§9.3: "cleared 24 h after the
  /// receipt").
  ///
  /// Not deleted immediately — see [kBulkClearAfterReceiptSeconds].
  void markDecoded(Uint8List tag, DateTime nowUtc) {
    if (!enabled) return;
    _decodedAt[_hex(tag)] =
        nowUtc.toUtc().millisecondsSinceEpoch ~/ 1000;
  }

  /// Expiry: `TTL_media`, and the 24 h grace period after the receipt.
  ///
  /// Returns the number of removed blocks.
  int expire(DateTime nowUtc) {
    if (!enabled) return 0;
    final now = nowUtc.toUtc().millisecondsSinceEpoch ~/ 1000;
    var removed = 0;
    for (final tagHex in _byTag.keys.toList()) {
      final decoded = _decodedAt[tagHex];
      final receiptExpired =
          decoded != null && now - decoded >= clearAfterReceiptSeconds;
      final line = _byTag[tagHex]!;
      for (final e in line.toList()) {
        if (receiptExpired || now - e.placedAt >= ttlSeconds) {
          _remove(e);
          removed++;
        }
      }
      if (receiptExpired) _decodedAt.remove(tagHex);
    }
    expiredBlocks += removed;
    return removed;
  }

  /// Disk pressure from outside: down to [targetBytes], oldest
  /// first.
  ///
  /// THE HANDLE THAT §21.3.3 NO. 3 MEANS: "under disk pressure, bulk is
  /// trimmed first (ahead of the delivery layer)". The order
  /// between the classes is decided by the layer above; this class
  /// only ensures that it CAN help itself here without
  /// touching the delivery layer.
  int trim(int targetBytes) {
    var removed = 0;
    while (_bytes > targetBytes) {
      final victim = _oldest();
      if (victim == null) break;
      _remove(victim);
      evicted++;
      removed++;
    }
    return removed;
  }

  /// Everything for one tag line gone — for aborting a transfer.
  int dropTag(Uint8List tag) {
    final line = _byTag[_hex(tag)];
    if (line == null) return 0;
    final n = line.length;
    for (final e in line.toList()) {
      _remove(e);
    }
    _decodedAt.remove(_hex(tag));
    return n;
  }

  BulkEntry? _oldest() {
    BulkEntry? best;
    for (final line in _byTag.values) {
      for (final e in line) {
        if (best == null || _olderAs(e, best)) best = e;
      }
    }
    return best;
  }

  /// Older placement time first; on a tie the earlier arrival.
  static bool _olderAs(BulkEntry a, BulkEntry b) =>
      a.placedAt != b.placedAt ? a.placedAt < b.placedAt : a.seq < b.seq;

  void _remove(BulkEntry e) {
    final tagHex = _hex(e.tag);
    final line = _byTag[tagHex];
    if (line != null) {
      line.remove(e);
      if (line.isEmpty) _byTag.remove(tagHex);
    }
    if (_byDigest.remove(_hex(e.digest)) != null) {
      _bytes -= e.bytes;
    }
  }
}
