// The cover fill carries fountain blocks (§5.5) — source and acceptance.
//
// ── WHAT §5.5 REQUIRES, AND WHERE IT STANDS HERE ─────────────────────────
//
// "A dummy slot may carry a fountain block of the binary distribution
// (§26.6.1) instead of random bytes. This adds **no cell, no byte and no
// slot** — the cell was going out anyway." Four rules, and none of them
// is decided here — three arise structurally elsewhere, the fourth
// is an omission:
//
//   Rule 1 (never a slot of its own). Arises in `tagline/delivery_node.dart`:
//     the filler is only asked for AFTER control queue and
//     payload have had their slot and `takeSlot` has delivered a dummy.
//     This file does not know the slot plan and cannot touch it.
//   Rule 2 (the plan draws the partner). Likewise: [nextFillBlock] is told
//     no partner and delivers the same for each.
//   Rule 3 (no shared key on the wrapping). Arises in
//     `link/`: the cell is sealed pairwise under the link key
//     like any other. The block INSIDE it is public —
//     exactly the separation that §5.5 rule 3 requires.
//   Rule 4 (no return channel). This file sends nothing and requests
//     nothing. [offer] returns a finding, not a frame.
//
// ── THE CAP IS MANDATORY, NOT OPTIONAL ──────────────────────────────
//
// The proposal calls the memory-fill vector "the only real
// newcomer": today a cover cell dies at the AEAD without being read;
// in future a parser that holds blocks is entered after the MAC. Four
// gates, from the strictest to the softest:
//
//   1. **Only registered objects.** A block that matches no
//      [BinaryFountainObject] in this registration is discarded —
//      without cache, without counter per sender, without state. And
//      only what stems from a hybrid-signed manifest is registered
//      (§26.5.2). A stranger can thus not even influence the SET
//      of objects, let alone their number.
//   2. **A byte quota** over all objects
//      ([kCoverFillBudgetBytes]). It counts what was actually taken in,
//      not what was offered.
//   3. **An upper limit per object**: [kCoverFillAcceptFactor] times as
//      many blocks as a receiver needs at zero loss
//      (`plannedBlocksFor`). Whoever pushes beyond that pushes into the
//      void.
//   4. **A bolt against repeated poisoning**
//      ([kCoverFillMaxHashFailures]). After this many failed
//      final checks this object accepts no UNSOLICITED blocks
//      any more and falls back to the harvest (§26.6.1, the authoritative
//      path).
//
// **Why gate 4 is needed, and that belongs to the root question.**
// `bulk_block_seal.dart` carries the seal per block as a doorman: "a
// slipped-in block is rejected at the door … it would need
// `K_T`". For the binary `K_T` is computable for every MEMBER of the network
// — since 05.09.2026 it follows from the network secret and
// the public content hash (`binary_fountain.dart`,
// [binaryTransferRoot]). For the door that means: against an
// outsider it is closed, against a neighbour in the network not. The latter
// can build a block with a valid seal and spoiled payload,
// and only the final check (full SHA-256 against `binaryHashes`) catches
// the forgery. That is no code execution risk, but a
// discarding of the whole version state per poisoning. The bolt
// limits how often a neighbour can force that.
//
// **The root question is thus decided and no longer open.** Here
// stood until S368 "the conflict of aims behind it is stage C and lies as a
// proposal"; the owner decided on 05.09.2026. The proposal
// `docs/v4-redesign/S365-VORLAGE-dritter-weg-und-wurzel.md` stays as a
// record, but is no longer an open question.
//
// ── WHAT THIS FILE DOES NOT DO ───────────────────────────────────────
//
// NO I/O, NO NETWORK, NO CLOCK. It delivers bytes and takes bytes; who
// sends them is `DeliveryNode`, and when is decided by the slot plan.
//
// NO ORIGIN OF THE ROOT. See `binary_fountain.dart`.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:cleona/core/bulk/bulk_block_seal.dart';
import 'package:cleona/core/bulk/bulk_keys.dart';
import 'package:cleona/core/bulk/bulk_receiver.dart';
import 'package:cleona/core/bulk/bulk_sender.dart' show plannedBlocksFor;

import 'binary_fountain.dart';

/// How many objects may be registered at the same time.
///
/// Three platforms of the in-network distribution (android, linux, windows —
/// macOS/iOS are excluded, §26.6.1) times full binary and delta.
const int kCoverFillMaxObjects = 6;

/// Byte quota of the cover fill on the always-on tier.
///
/// CALCULATED, NOT SET — and the first calculation here was wrong,
/// that is why it stands written out:
///
///   a 5 MB delta (§26.6.2 "a few MB"; the path carries deltas, not
///   full binaries — the proposal calculates 45 days for a 189.6 MB APK)
///   plans `plannedBlocksFor(5e6)` = **7068** blocks.
///   Times [kCoverFillAcceptFactor] that is 14 136 blocks, and a
///   sealed block measures 1069 B:
///
///     per object   14 136 x 1069 B = 15.11 MB
///     3 objects (one delta per platform)          45.3 MB
///     6 objects (full binary and delta per p.)    90.7 MB
///
/// Here stood "6 objects at 5 MB times 2 = 60 MB" — that computed with the
/// OBJECT SIZE instead of with the taken-in blocks and was too small by a factor of 3.
///
/// **64 MB covers the regular case with room to spare and does not bind in the
/// extreme.** That is intentional and not a leftover: with six objects collected
/// at the same time this quota takes effect BEFORE the limit per object.
/// Two gates of which the outer one holds first are exactly the
/// intended order — the inner one is directed against a single neighbour,
/// the outer one against the sum.
///
/// NOT COUNTED is the ring buffer for pushing on: it
/// costs [kCoverFillForwardPoolBlocks] x 1069 B = 1.09 MB per object,
/// i.e. at most 6.6 MB, and is hard-limited per object.
///
/// **It is an item of its own, not part of the bulk quota.**
/// `kBulkCacheCapacityBytes` (1 GB) belongs to the HOLDER SERVICE for foreign
/// transmissions (§9.3); what lies here the node collects for ITSELF.
/// A shared pot would mean that an update displaces the holder service
/// or vice versa.
const int kCoverFillBudgetBytes = 64 * 1024 * 1024;

/// Byte quota of the cover fill on the RESERVE-LIMITED tier
/// (§22.6: Android/iOS).
///
/// CALCULATED, NOT SET (04.09.2026, S367). A mobile node
/// registers according to §5.5 only the OWN platform and pushes nothing
/// on ([UpdateCoverFill.pushes] = `false`) — it thus collects exactly
/// one object and needs no quota for foreign ones.
///
///   a 5 MB delta (§26.6.2 "Full binaries are expensive over cellular")
///   plans `plannedBlocksFor(5e6)` = 7068 blocks at 1069 B = **7.56 MB**
///   at ZERO loss. Times [kCoverFillAcceptFactor] that is 15.11 MB.
///
/// **16 MB, so that the limit PER OBJECT holds first.** That is the same
/// order as on the always-on tier, only justified the other way round: there
/// six objects are in the pot and the outer gate takes effect first,
/// here ONE object is in it and the inner one is to take effect. A smaller
/// quota would have cut off the collection in the middle of the object —
/// the most expensive of all variants, because the taken-in bytes are then
/// of no use.
///
/// For comparison, measured: the delivery store of a mobile node
/// stands at `kMobileSecureStoreCapBytes` = 32 MB.
const int kCoverFillMobileBudgetBytes = 16 * 1024 * 1024;

/// How large an object may be at most for this node to encode it
/// FRESHLY instead of only passing it on.
///
/// ── WHY THIS LIMIT MUST EXIST ────────────────────────────────
///
/// [BinaryFountainSeeder] hangs on `FountainEncoder`, and that needs the
/// WHOLE object in memory (`fountain_encoder.dart:26-31`). Without a limit
/// a number from a manifest — `binarySizes` — would decide how much
/// working memory this node permanently holds.
///
/// **64 MB, and what that excludes is measured (04.09.2026):**
///
///   `build/cleona-daemon`  15 673 584 B  — four times headroom, is seeded
///   APK (proposal §26.6)  189.6 MB       — above it, is NOT seeded
///
/// The consequence for Android is explicit and no side effect: a
/// full APK does not travel via the cover fill. §26.6.2 carries exactly
/// for that the deltas ("a few MB"), and as soon as the manifest carries a
/// delta hash, this object falls below the limit. Until then
/// the harvest remains the path for Android (§26.6.1, the authoritative one
/// anyway).
const int kCoverFillMaxSeedBytes = 64 * 1024 * 1024;

/// How much more than necessary an object takes in at most.
///
/// `plannedBlocksFor` is already the need WITH coverage and margin
/// (`bulk_sender.dart`). The factor 2 on top allows duplicates and the
/// platform blindness, without a neighbour being able to top up
/// indefinitely.
const int kCoverFillAcceptFactor = 2;

/// After this many failed final checks an object accepts no
/// unsolicited blocks any more.
const int kCoverFillMaxHashFailures = 3;

/// How many sealed blocks per object are kept for the VERBATIM
/// pushing on.
///
/// ── WHY THIS SUPPLY EXISTS, MEASURED ───────────────────────────
///
/// A node that does not yet have the binary completely cannot
/// re-encode (`fountain_decoder.dart` has no re-encoding, and
/// `FountainEncoder` needs the whole object). It can only pass on
/// what it has received. Whether it SHOULD do that is measured
/// (`test/perf/perf_cover_fill_push_s365.dart`, 400 desktops, 5 MB delta,
/// 04.09.2026) — and the answer is clear:
///
///   only complete ones push      268 of 400 after 90 days
///   incomplete ones as well      400 of 400 after **13** days
///
/// The price is duplicates; the gain is that the spread reaches
/// the whole graph at all. Without pushing on it only runs
/// via neighbours of THE SAME platform, and of those a node has on average
/// 4/3 — too few for an epidemic.
///
/// The supply costs [kCoverFillForwardPoolBlocks] x 1069 B per object.
const int kCoverFillForwardPoolBlocks = 1024;

/// What offering an unsolicited block has yielded.
enum CoverFillVerdict {
  /// Taken in and effective in the decoder.
  accepted,

  /// Taken in, but contributed nothing (rateless normal) or was a
  /// duplicate.
  redundant,

  /// Taken in, but ONLY for pushing on (§5.5: "Blocks for
  /// other platforms are discarded or, on the always-on tier, retained as
  /// cache"). No decoder, no byte against the total quota — only the
  /// per-object hard ring buffer.
  cached,

  /// Belonging to no registered object — gate 1.
  unknown,

  /// Object is already complete.
  complete,

  /// One of the gates 2, 3 or 4 has taken effect.
  refused,
}

/// A registered object with its collection state.
final class _Slot {
  final BinaryFountainObject object;

  /// Set when this node has the binary COMPLETELY — then it can
  /// compute fresh blocks instead of only passing on.
  BinaryFountainSeeder? seeder;

  /// Set as long as collecting goes on.
  ///
  /// **If [seeder] AND [collector] are `null`, the place is a pure
  /// CACHE** — the node accepts blocks of this object in order to
  /// push them on, and does not assemble it itself. That is the
  /// case "foreign platform on the always-on tier" from §5.5, and it is
  /// the condition, not an option: the measurement
  /// (`test/perf/perf_cover_fill_push_s365.dart`, case A/C against E) shows
  /// 267-268 of 400 after over 90 days if foreign blocks
  /// are thrown away, against 396 of 400 after 28 days if they stay as
  /// cache.
  BinaryFountainCollector? collector;

  /// True if this place only pushes on.
  bool get isOnlyCache => seeder == null && collector == null;

  /// Sealed blocks for verbatim pushing on. Ring buffer.
  final List<Uint8List> forwardPool = <Uint8List>[];
  int _ring = 0;

  int acceptedBlocks = 0;
  int refusedBlocks = 0;

  _Slot(this.object);

  int get maxBlocks =>
      plannedBlocksFor(object.objectLength) * kCoverFillAcceptFactor;

  void remember(Uint8List sealed) {
    if (forwardPool.length < kCoverFillForwardPoolBlocks) {
      forwardPool.add(sealed);
      return;
    }
    // Ring buffer and not "nothing more from now on": a fixed supply from
    // the early phase would be exactly the set that the neighbours already
    // have. Overwriting keeps it fresh.
    forwardPool[_ring] = sealed;
    _ring = (_ring + 1) % forwardPool.length;
  }
}

/// Source and acceptance point of the cover fill.
final class UpdateCoverFill {
  /// Whether this node pushes at all.
  ///
  /// **`false` on mobile nodes.** §9.3 (E-53): "Mobile nodes hold no
  /// bulk"; §5.5: the receiver "stores blocks within its platform tier's
  /// budget (§22.6) and discards the rest". A phone thus accepts for ITSELF
  /// and pushes nothing on. **That does not stand like this in the document** — it
  /// is the obvious reading of both sentences together, and it lies as
  /// point 3 of the proposal
  /// `docs/v4-redesign/S365-VORLAGE-dritter-weg-und-wurzel.md` with the
  /// owner. Until then it is a parameter and not a silent assumption.
  final bool pushes;

  /// Total quota of the acceptance.
  final int budgetBytes;

  /// The NODE-LOCAL seeder secret.
  ///
  /// ── WHY THERE MUST BE ONE, MEASURED ──────────────────────────────
  ///
  /// `KeyedSeeds` derives the seeds from a secret; two seeders with
  /// different secrets produce practically disjoint block sets.
  /// If one takes the ROOT for that, nothing is gained — it is the same for all
  /// seeders (that is its purpose, §26.6.1), so each would draw
  /// the same sequence. Measured, the difference is clear: 0.0 % duplicates
  /// against 13.9 %, and without pushing on 396 of 400 finished nodes
  /// against 267 (`test/perf/perf_cover_fill_push_s365.dart`).
  ///
  /// 32 random bytes of the node suffice. They need NOT stay
  /// secret — they are no key, but a scattering; their
  /// only purpose is that two nodes do not draw the same blocks.
  final Uint8List seederSecret;

  final Map<String, _Slot> _slots = <String, _Slot>{};
  final Random _rng;

  /// How many blocks arrived without a matching object (gate 1).
  int unknownBlocks = 0;

  /// How many blocks failed on the quota (gates 2/3/4).
  int refusedBlocks = 0;

  UpdateCoverFill({
    required this.seederSecret,
    this.pushes = true,
    this.budgetBytes = kCoverFillBudgetBytes,
    Random? rng,
  }) : _rng = rng ?? Random() {
    if (seederSecret.length != 32) {
      throw ArgumentError(
        'Seeder secret must be 32 B, is '
        '${seederSecret.length}',
      );
    }
  }

  /// Taken-in bytes over all objects.
  ///
  /// What is counted is the RAW block (1041 B), not the sealed one: the
  /// decoder holds the payload, not the seal. The ring buffer for
  /// pushing on comes on top separately and is hard-limited by
  /// [kCoverFillForwardPoolBlocks] per object.
  int get acceptedBytes {
    var n = 0;
    for (final s in _slots.values) {
      n += s.acceptedBlocks * kSealedBulkBlockBytes;
    }
    return n;
  }

  int get objectCount => _slots.length;

  Iterable<BinaryFountainObject> get objects =>
      _slots.values.map((s) => s.object);

  /// Registers an object. [binary] only if this node has it
  /// COMPLETELY — then it seeds freshly instead of passing on.
  ///
  /// [cache] `true` registers it ONLY for pushing on: no decoder,
  /// no assembly, no byte against the total quota. That is the place
  /// for a FOREIGN platform on the always-on tier (§5.5). [binary]
  /// and [cache] exclude each other — whoever has the object encodes
  /// freshly and needs no supply.
  ///
  /// Returns `false` if [kCoverFillMaxObjects] is reached.
  bool register(
    BinaryFountainObject object, {
    Uint8List? binary,
    bool cache = false,
  }) {
    if (binary != null && cache) {
      throw ArgumentError('binary and cache exclude each other');
    }
    final id = _hex(object.objectId);
    if (_slots.containsKey(id)) return true;
    if (_slots.length >= kCoverFillMaxObjects) return false;
    final s = _Slot(object);
    if (binary != null) {
      s.seeder = BinaryFountainSeeder(
        object: object,
        binary: binary,
        seeds: _seedsFor(object),
      );
    } else if (!cache) {
      s.collector = BinaryFountainCollector(object);
    }
    _slots[id] = s;
    return true;
  }

  void unregister(BinaryFountainObject object) =>
      _slots.remove(_hex(object.objectId));

  /// The block for a due cover slot — or `null` if nothing
  /// is pending. Then the cell stays random, as before.
  ///
  /// ── WHY THE OBJECT IS DRAWN AND NOT CHOSEN ────────────────
  ///
  /// The obvious thing would be to push the OWN platform — one has it
  /// anyway. Exactly that is excluded: §5.4 excludes the
  /// platform becoming readable from the stream, and a partner that knows the roots
  /// from the public manifest reads it off every pushed
  /// block. That is why the draw is uniform over ALL registered
  /// objects.
  ///
  /// The price is calculated: two thirds of the pushed cells are
  /// the wrong platform for the receiver. The counter-run without this
  /// rule stands in the measurement as case D — and it is not even
  /// faster, but **slower** (98 of 400 instead of 396 of 400),
  /// because the spread then shrinks down to same-platform neighbours.
  Uint8List? nextFillBlock() {
    if (!pushes || _slots.isEmpty) return null;
    final ids = _slots.keys.toList()..sort();
    final start = _rng.nextInt(ids.length);
    for (var i = 0; i < ids.length; i++) {
      final s = _slots[ids[(start + i) % ids.length]]!;
      final seeder = s.seeder;
      if (seeder != null) {
        final b = seeder.nextSealedBlocks(1);
        if (b.isNotEmpty) return b.first;
        continue;
      }
      if (s.forwardPool.isNotEmpty) {
        return s.forwardPool[_rng.nextInt(s.forwardPool.length)];
      }
    }
    return null;
  }

  /// Accepts an UNSOLICITED block.
  ///
  /// Tries the registered objects in turn. Why that works instead of
  /// an identifier on the wire is stated at `BulkOp.publicBlock`:
  /// an identifier would be a version-state leak, and the price of
  /// trying is negligible with at most [kCoverFillMaxObjects] objects and
  /// at most one cell per slot.
  ///
  /// **Sends nothing** — §5.5 rule 4.
  CoverFillVerdict offer(Uint8List sealedBlock) {
    if (sealedBlock.length != kSealedBulkBlockBytes) {
      unknownBlocks++;
      return CoverFillVerdict.unknown;
    }
    if (acceptedBytes >= budgetBytes) {
      refusedBlocks++;
      return CoverFillVerdict.refused;
    }
    // ── FIRST ASSIGN, THEN CAP, ONLY THEN FEED ─────────────
    //
    // The first version of this loop GAVE the block to the collector
    // and checked the cap afterwards. That was a cap on the
    // counter and none on the memory: the decoder had then
    // already taken in the block. The assignment needs no collector —
    // `openBulkBlock` against the keys of the object suffices, costs
    // one AES-GCM open over 1069 B and at the same time says whether the block
    // is genuine at all.
    for (final s in _slots.values) {
      final c = s.collector;
      // A place WITH a seeder is finished — there is nothing to take in.
      // A place WITHOUT either is a pure cache: it checks the
      // membership and puts the block into the ring buffer, without
      // decoding it and without burdening the total quota.
      if (c == null && s.seeder != null) continue;
      if (openBulkBlock(sealedBlock, s.object.keys) == null) {
        continue; // does not belong to this object (or is forged)
      }
      if (c == null) {
        s.remember(Uint8List.fromList(sealedBlock));
        return CoverFillVerdict.cached;
      }
      // From here on it is certain: the block belongs to THIS object.
      if (c.hashFailures >= kCoverFillMaxHashFailures) {
        s.refusedBlocks++;
        refusedBlocks++;
        return CoverFillVerdict.refused;
      }
      if (s.acceptedBlocks >= s.maxBlocks) {
        s.refusedBlocks++;
        refusedBlocks++;
        return CoverFillVerdict.refused;
      }
      final r = c.offerSealed(sealedBlock);
      if (r == BulkOffer.complete) return CoverFillVerdict.complete;
      if (r == BulkOffer.quarantined || r == BulkOffer.duplicate) {
        return CoverFillVerdict.redundant;
      }
      if (r == BulkOffer.foreign) {
        // Opened, but a different object of the same root — can only
        // be a length or identifier error. Is not taken in.
        return CoverFillVerdict.unknown;
      }
      s.acceptedBlocks++;
      s.remember(Uint8List.fromList(sealedBlock));
      return r == BulkOffer.redundant
          ? CoverFillVerdict.redundant
          : CoverFillVerdict.accepted;
    }
    unknownBlocks++;
    return CoverFillVerdict.unknown;
  }

  /// Attempts the assembly of an object. Returns the bytes ONLY on a
  /// passed hash check (`BulkReceiver.take`).
  ///
  /// After success the collector is replaced by a seeder: the
  /// node can now re-encode the object instead of only passing it on.
  /// Exactly this transition is in the measurement the difference between
  /// "268 of 400 after 90 days" and "396 of 400 after 28".
  Uint8List? tryAssemble(BinaryFountainObject object) {
    final s = _slots[_hex(object.objectId)];
    final c = s?.collector;
    if (s == null || c == null) return null;
    final t = c.take();
    if (t.verdict != BulkVerdict.verified) return null;
    final bytes = t.object!;
    s.collector = null;
    s.seeder = BinaryFountainSeeder(
      object: object,
      binary: bytes,
      seeds: _seedsFor(object),
    );
    s.forwardPool.clear();
    return bytes;
  }

  /// Progress of an object, `[0,1]`. `1.0` when it is completely there.
  double progressOf(BinaryFountainObject object) {
    final s = _slots[_hex(object.objectId)];
    if (s == null) return 0;
    if (s.seeder != null) return 1;
    return s.collector?.progress ?? 0;
  }

  /// How many blocks were taken in for [object].
  int acceptedFor(BinaryFountainObject object) =>
      _slots[_hex(object.objectId)]?.acceptedBlocks ?? 0;

  /// How often the assembly of [object] has failed at the full SHA-256
  /// — the counter against which [kCoverFillMaxHashFailures] checks.
  ///
  /// **Passed to the outside, because otherwise it cannot be measured WHICH cap
  /// took effect.** [offer] returns for cap 3 (limit per object) and
  /// cap 4 (poisoning bolt) the same finding
  /// [CoverFillVerdict.refused]; a test that only checks for that measures
  /// a proxy. An object that this node already has
  /// completely reports 0 — it no longer collects.
  int hashFailuresFor(BinaryFountainObject object) =>
      _slots[_hex(object.objectId)]?.collector?.hashFailures ?? 0;

  BulkSeedSource _seedsFor(BinaryFountainObject object) =>
      KeyedSeeds(seederSecret: seederSecret, objectId: object.objectId);

  static String _hex(Uint8List b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
}
