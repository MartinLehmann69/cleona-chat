// The BUNDLE LINE of the rescue bundle (§13.3), step 1 — splitting,
// storing, renewal, harvest.
//
// ── WHY THIS FILE LIES IN THE DELIVERY LAYER ────────────────────
//
// Because it is a LINE, like `invite_line.dart` (§15.3.2) and
// `own_line.dart` (§14.7) — a place at which tags are computed, cells
// stored and cells harvested. In a first version it stood
// under `lib/core/recovery/` and accessed the node from there; the
// guard `smoke_seam_node_member_guard.dart` reported that red on the same day,
// and it was right: „the node is reached through
// V41Runtime.node, and only the layer that owns it (lib/core/tagline/)
// may do that." The answer was not the exception list but the
// move.
//
// Conversely, what is NOT a line stays outside: the derivations from the
// seed (`recovery/recovery_keys.dart`) and the CONTENT of the bundle
// (`recovery/recovery_bundle_content.dart`). This file sees 32 bytes of
// line key and n bytes of ciphertext; what is in it it does not know
// and should not know.
//
// ── WHY SPLITTING IS NEEDED ────────────────────────────────────────
//
// §13.3.2 calculates the bundle at „~32 KB with the identity's own current
// key state". A stored item carries [kMaxPlaceContentBytes] (measured 1042 B,
// `secure_frames.dart`). The document names the path itself: „Being
// > 10 KB, the bundle rides **Reed-Solomon erasure coding (N=10, K=7,
// 1.43x overhead, 3 peers may fail)** rather than fountain codes".
//
// ── THE TWO DEFINITIONS THAT §13.3 LEAVES OPEN ────────────────────
//
// §13.3.1 names `tag_R(i, e, j)` with „j = block index" and does not say how
// `j` is mapped onto (block, piece, family). Two values are fixed here
// ONCE and then frozen — like the salt in
// `recovery_keys.dart` they are **wire-relevant**:
//
//   1. The cell header [kBundleCellHeaderBytes]. It must exist because the
//      harvest answer carries ONLY (request identifier, cell) (`v41_node.dart`,
//      `_geerntet`) and one request bundles several tags: from the
//      answer alone it would otherwise be impossible to say which piece of which
//      block came back.
//   2. The mapping [recoveryBundleFragmentIndex]:
//        j = (block * kBundleFragmentsPerBlock + frag) * m + family.
//      It carries the m = 3 family redundancy (owner decision of
//      02.09.2026), for which `tag_R` itself has no parameter. THAT a
//      mapping is needed is measured and not a preference: the
//      responsibility set of a stored item follows from `targetFor(tag, epoche)`
//      (§9.1, `H(T ‖ e)`) — ONE tag has EXACTLY ONE set. Three families
//      therefore necessarily mean three different tags, otherwise all
//      three copies lie on the same relay set and m = 3 buys nothing.
//
// The HKDF underneath stays unchanged: [recoveryBundleTag] from
// `recovery_keys.dart` with its test vectors is not touched.
//
// ══════════════════════════════════════════════════════════════════
// THE LINE ITSELF — STORING, RENEWAL, HARVEST
// ══════════════════════════════════════════════════════════════════
//
// ── WHAT COMES TOGETHER HERE ───────────────────────────────────────────
//
// Three parts that are each right on their own and only do something
// together:
//
//   * `recovery/recovery_keys.dart` — the tags and the
//     bundle key from the seed (§13.3.1, §13.3.3). Built in S360
//     and until S362 with ZERO callers in `lib/` — eleven derivations that
//     only knew their own tests. This file is the first
//     call edge.
//   * the splitting in the upper part of this file — Reed-Solomon N=10/K=7
//     and the cell header.
//   * `v41_node.dart` — `placeUnderTag` / `storeUnderTag` /
//     `harvestUnderTags`: the tag-based storing without pair reference, which
//     was missing until S362 (S-2 in
//     `docs/v4-redesign/S360-recovery-entwurf.md`, section 5).
//
// ── THE RENEWAL CADENCE, AND WHY IT IS NOT A TIMER ──────────
//
// §13.3.4: „Cadence: renewal with every recovery-epoch change, i.e.,
// every 14 days. … and needs no timer of its own — **it hangs off a tick
// the node keeps anyway (§19: no polling)**."
//
// Exactly so it is built: [RecoveryBundleLine.slot] hangs via
// `V41Node.addSlotTick` on the cover slot that the node beats anyway.
// It is triggered at the EDGE — `recoveryEpochFor(jetzt)`
// against the last served epoch. No `Timer`, no lookup every
// second, no state that can grow without cause. A node
// that was off across an epoch change renews at the next
// start — the same edge, only seen later.
//
// ── AND WHY THE STORING IS TRICKLED, NOT POURED ────────────
//
// A renewal is, at m = 3 and `kResponsibleRelays` = 20, about
// **3 000** stored items (see [RecoveryBundleLine.plannedPlacements]). The
// control queue holds `kMaxControlBacklog` = 120 frames, and
// `CoverStream._pushControl` throws away the oldest whole
// group on overflow. Whoever enqueues 3 000 frames at once loses 96 % of them
// silently — AND takes the queue away from the running mail.
//
// Hence: **at most one frame per slot, and only into an EMPTY
// queue.** Thus the bundle is subordinate to every message, every harvest and
// every call signalling; it uses the slots in which
// padding would otherwise go. According to §5.1 invariant 1 („a real cell *replaces*
// an already-scheduled dummy slot") it thus costs **no additional
// bytes on the wire** — it costs sending capacity, and precisely the capacity that
// no one needs at the moment.
library;

import 'dart:typed_data';

import 'package:cleona/core/codec/reed_solomon.dart';
import 'package:cleona/core/recovery/recovery_keys.dart';

import 'package:cleona/core/sync/entry_record.dart';
import 'package:cleona/core/bulk/responsibility.dart' show kResponsibleRelays, targetFor;
// The two pure decisions of the harvest backlog (S374/S380).
// They exist as functions there so that they can be checked —
// and so that BOTH harvest paths use the same one instead of two copies.
import 'secure_mode.dart' show harvestRunDue, harvestCap;
import 'secure_frames.dart' show kMaxPlaceContentBytes, kRetentionManagement;
import 'v41_node.dart';
import 'package:cleona/core/sync/delivery_params.dart' show kDeliveryFamilies;

/// The encoder, built ONCE.
///
/// ── WHY NOT PER CALL (measured, not assumed) ────────────────
///
/// `ReedSolomon.withParams` is a factory and returns EVERY TIME a
/// new instance — including its own `CLogger` (`reed_solomon.dart`, field
/// `_log`) and a line „Reed-Solomon initialized" in the log. The
/// assembler calls `assemble()` after EVERY harvested cell; for
/// a 32-KB bundle that would be fifty new encoders and fifty
/// log lines for the same, unchangeable Cauchy matrix. A top-level `final`
/// is lazy in Dart: it is built at first use,
/// never again after that.
final ReedSolomon _bundleRs = ReedSolomon.withParams(kBundleN, kBundleK);

/// Version of the cell header. A receiver that sees a different one drops
/// the cell instead of misinterpreting it.
const int kBundleCellVersion = 1;

/// `ver(1) ‖ blocks(1) ‖ block(1) ‖ frag(1) ‖ sealedLen(4, big-endian)`.
///
/// Four of the eight bytes are redundant with the tag under which the
/// cell lies — and they are nevertheless necessary: see point 1 in the file header.
/// The other four (`sealedLen`) are, because the Reed-Solomon
/// decoding needs the original length (`reed_solomon.dart`,
/// `decode(fragments, originalSize)`), and that is nowhere else: the
/// bundle is sealed, so its length is only readable after
/// reassembly.
const int kBundleCellHeaderBytes = 8;

/// N from §13.3.2 verbatim: „Reed-Solomon erasure coding (N=10, K=7, 1.43x
/// overhead, 3 peers may fail)". It is at the same time `ReedSolomon.defaultN`,
/// so no second tailoring.
const int kBundleN = ReedSolomon.defaultN;

/// K from §13.3.2 — seven of ten pieces suffice.
const int kBundleK = ReedSolomon.defaultK;

/// How many pieces a block has. N, not K — the three parities are
/// the whole gain.
const int kBundleFragmentsPerBlock = kBundleN;

/// How much payload a piece carries.
///
/// MEASURED, NOT ESTIMATED: [kMaxPlaceContentBytes] = 1042
/// (`secure_frames.dart`, from `kControlBodyBytes` 1169 minus header,
/// class, tag and AEAD suffix). **Not** `kMaxOnionMessageBytes` = 1041
/// — that is the limit of the ONION path, and the bundle does not go through
/// the onion: it is sealed symmetrically under `bundle_key` (§13.3.3)
/// and addressed to no one.
///
/// `docs/v4-redesign/S360-recovery-entwurf.md` section 6.1 computes with
/// 1041 B. The difference does not change the number of pieces of a 32-KB bundle
/// — recalculated in `smoke_v41_recovery_bundle.dart`.
const int kBundleFragmentBytes =
    kMaxPlaceContentBytes - kBundleCellHeaderBytes;

/// How much bundle fits into ONE block: `K` pieces of
/// [kBundleFragmentBytes] each.
const int kBundleBlockBytes = kBundleK * kBundleFragmentBytes;

/// Maximum number of blocks — the header carries block and block count in one
/// byte each. 255 blocks are about 1.8 MB of bundle; §13.3.2 computes with 32 KB.
const int kBundleMaxBlocks = 255;

/// How many blocks a bundle of [sealedLength] bytes needs.
int recoveryBundleBlockCount(int sealedLength) {
  if (sealedLength <= 0) {
    throw ArgumentError('Bundle is empty');
  }
  final n = (sealedLength + kBundleBlockBytes - 1) ~/ kBundleBlockBytes;
  if (n > kBundleMaxBlocks) {
    throw ArgumentError('Bundle needs $n blocks, '
        'the header carries at most $kBundleMaxBlocks');
  }
  return n;
}

/// How many stored items a renewal costs: pieces x families x
/// responsible ones.
///
/// As a function and not as a constant, because [relaysPerTag] must be measured and
/// not guessed: in the field `kResponsibleRelays` = 20, in the
/// three-node lab 3 (the set is bounded by the number of KNOWN relays,
/// `v41_node.dart`, `responsibleRelays`).
int recoveryBundlePlacements(int sealedLength, {required int relaysPerTag}) =>
    recoveryBundleBlockCount(sealedLength) *
    kBundleFragmentsPerBlock *
    kDeliveryFamilies *
    relaysPerTag;

/// The sequence number `j` of a piece in a family.
///
/// The mapping is FROZEN (see file header, point 2). Whoever
/// changes it makes every stored bundle unfindable — not broken,
/// but unfindable, and nothing reports an error.
int recoveryBundleFragmentIndex({
  required int block,
  required int fragment,
  required int family,
}) {
  if (block < 0 || block >= kBundleMaxBlocks) {
    throw ArgumentError('block $block outside 0..${kBundleMaxBlocks - 1}');
  }
  if (fragment < 0 || fragment >= kBundleFragmentsPerBlock) {
    throw ArgumentError(
        'piece $fragment outside 0..${kBundleFragmentsPerBlock - 1}');
  }
  if (family < 0 || family >= kDeliveryFamilies) {
    throw ArgumentError(
        'family $family outside 0..${kDeliveryFamilies - 1}');
  }
  return (block * kBundleFragmentsPerBlock + fragment) * kDeliveryFamilies +
      family;
}

/// The tag under which a piece lies — `tag_R(i, e, j)` from §13.3.1.
Uint8List recoveryBundleCellTag(
  Uint8List recoveryKeyI,
  int epoch, {
  required int block,
  required int fragment,
  required int family,
}) =>
    recoveryBundleTag(
        recoveryKeyI,
        epoch,
        recoveryBundleFragmentIndex(
            block: block, fragment: fragment, family: family));

/// A piece of the bundle, ready for storing.
final class RecoveryBundleCell {
  const RecoveryBundleCell({
    required this.block,
    required this.fragment,
    required this.content,
  });

  final int block;
  final int fragment;

  /// Header and payload — exactly what goes into the stored item.
  final Uint8List content;
}

/// Splits a sealed bundle into [kBundleFragmentsPerBlock] pieces
/// per block.
///
/// ── WHY THE WHOLE BUNDLE IS PADDED, NOT ONLY THE LAST BLOCK
///
/// `ReedSolomon.encode` computes the piece size from the length of its
/// input. A shorter last block would yield shorter pieces — and
/// thus a cell recognisable by its length as „the last one".
/// On the wire all cells are padded to `kCellBytes` anyway;
/// in the MEMORY of the relay they are not, and a relay sees its
/// stored items in their true length. Equally long pieces cost at most
/// one block remainder of padding (< 7.3 KB) and are the only form in which
/// the splitting reveals nothing.
List<RecoveryBundleCell> splitRecoveryBundle(Uint8List sealed) {
  final blocks = recoveryBundleBlockCount(sealed.length);
  final filled = Uint8List(blocks * kBundleBlockBytes)
    ..setRange(0, sealed.length, sealed);
  final rs = _bundleRs;
  final out = <RecoveryBundleCell>[];
  for (var b = 0; b < blocks; b++) {
    final raw = Uint8List.fromList(Uint8List.sublistView(
        filled, b * kBundleBlockBytes, (b + 1) * kBundleBlockBytes));
    final pieces = rs.encode(raw);
    for (var f = 0; f < pieces.length; f++) {
      final cell = Uint8List(kBundleCellHeaderBytes + pieces[f].length);
      cell[0] = kBundleCellVersion;
      cell[1] = blocks;
      cell[2] = b;
      cell[3] = f;
      cell[4] = (sealed.length >> 24) & 0xff;
      cell[5] = (sealed.length >> 16) & 0xff;
      cell[6] = (sealed.length >> 8) & 0xff;
      cell[7] = sealed.length & 0xff;
      cell.setRange(kBundleCellHeaderBytes, cell.length, pieces[f]);
      out.add(RecoveryBundleCell(block: b, fragment: f, content: cell));
    }
  }
  return out;
}

/// What a cell header says.
final class RecoveryBundleCellHeader {
  const RecoveryBundleCellHeader({
    required this.blocks,
    required this.block,
    required this.fragment,
    required this.sealedLength,
  });

  final int blocks;
  final int block;
  final int fragment;
  final int sealedLength;
}

/// Reads the header of a harvested cell. `null` if it is none.
///
/// SILENT, NOT THROWING (E-83): a harvest answer can carry any cell
/// that happened to lie under one of the queried tags — including padding
/// and foreign items. A throw here would tear the harvest run.
RecoveryBundleCellHeader? readRecoveryBundleCellHeader(Uint8List cell) {
  if (cell.length <= kBundleCellHeaderBytes) return null;
  if (cell[0] != kBundleCellVersion) return null;
  final blocks = cell[1];
  final block = cell[2];
  final fragment = cell[3];
  if (blocks < 1 || block >= blocks) return null;
  if (fragment >= kBundleFragmentsPerBlock) return null;
  final len = (cell[4] << 24) | (cell[5] << 16) | (cell[6] << 8) | cell[7];
  // The length must FIT the block count, not merely fit in: a
  // bundle of 8 KB cannot have 5 blocks. Without the lower bound
  // a forged header would be able to pin the collector to a
  // block count that never becomes complete.
  if (len < 1 || len > blocks * kBundleBlockBytes) return null;
  if (len <= (blocks - 1) * kBundleBlockBytes) return null;
  return RecoveryBundleCellHeader(
      blocks: blocks, block: block, fragment: fragment, sealedLength: len);
}

/// Reassembles harvested pieces into a sealed bundle.
///
/// It holds at most [kBundleK] pieces per block — decoding needs no more,
/// and a collector without a cap would, in the
/// recovery case, be the only memory item that grows with the number of
/// answers.
final class RecoveryBundleAssembler {
  final Map<int, Map<int, Uint8List>> _pieces = <int, Map<int, Uint8List>>{};
  int? _blocks;
  int? _sealedLength;

  /// How many blocks the bundle has, as soon as the first cell was there.
  int? get blocks => _blocks;

  /// How many blocks already have enough pieces.
  int get readyBlocks =>
      _pieces.values.where((m) => m.length >= kBundleK).length;

  /// For which blocks pieces are still missing — the harvest asks only for these.
  ///
  /// Before the first cell the block count is unknown; then the list is
  /// empty, and the caller asks for block 0 (see `harvestRecoveryTick`).
  List<int> get missingBlocks {
    final n = _blocks;
    if (n == null) return const <int>[];
    return [
      for (var b = 0; b < n; b++)
        if ((_pieces[b]?.length ?? 0) < kBundleK) b
    ];
  }

  /// Takes a harvested cell. Returns the sealed bundle
  /// as soon as every block has [kBundleK] pieces — otherwise `null`.
  ///
  /// `null` does NOT mean „this cell was unusable": §13.2.3 demands
  /// that an unsuccessful search is not an error. The normal case is that
  /// something is still missing.
  Uint8List? offer(Uint8List cell) {
    final header = readRecoveryBundleCellHeader(cell);
    if (header == null) return null;
    // ── A CHANGING HEADER IS A DIFFERENT BUNDLE ─────────────────
    //
    // The three epochs a recovery queries (§13.3.1)
    // can carry bundles of DIFFERENT size: between two
    // renewals contacts are added. Mixing pieces of two renewals
    // would yield bytes that fail the AEAD — with `null` as the
    // only signal, i.e. undecidable. The collector therefore sticks to the
    // FIRST seen layout and leaves foreign items lying; whoever wants to harvest the
    // older renewal takes a new collector.
    if (_blocks == null) {
      _blocks = header.blocks;
      _sealedLength = header.sealedLength;
    } else if (_blocks != header.blocks || _sealedLength != header.sealedLength) {
      return null;
    }
    final use = Uint8List.sublistView(cell, kBundleCellHeaderBytes);
    if (use.length != kBundleFragmentBytes) return null;
    final block = _pieces.putIfAbsent(header.block, () => <int, Uint8List>{});
    if (block.length < kBundleK || block.containsKey(header.fragment)) {
      block[header.fragment] = Uint8List.fromList(use);
    }
    return assemble();
  }

  /// Tries to reassemble the bundle. `null` as long as a block has
  /// fewer than [kBundleK] pieces.
  Uint8List? assemble() {
    final n = _blocks;
    final len = _sealedLength;
    if (n == null || len == null) return null;
    for (var b = 0; b < n; b++) {
      if ((_pieces[b]?.length ?? 0) < kBundleK) return null;
    }
    final rs = _bundleRs;
    final out = Uint8List(n * kBundleBlockBytes);
    for (var b = 0; b < n; b++) {
      final Uint8List block;
      try {
        block = rs.decode(_pieces[b]!, kBundleBlockBytes);
      } catch (_) {
        // A block that cannot be decoded is no reason to tear the
        // run — the next cell can heal it.
        return null;
      }
      out.setRange(b * kBundleBlockBytes, (b + 1) * kBundleBlockBytes, block);
    }
    return Uint8List.fromList(Uint8List.sublistView(out, 0, len));
  }
}

/// What the application contributes: the line key and the fully
/// sealed bundle.
///
/// BOTH COME FROM ABOVE, because both need the SEED — and that does
/// not belong in the delivery layer. This file sees 32 bytes of line key
/// and n bytes of ciphertext and does not know what is in it; whoever fills it
/// is `service/cleona_service_recovery_bundle.dart`.
final class RecoveryBundleMaterial {
  const RecoveryBundleMaterial({
    required this.recoveryKey,
    required this.sealed,
  });

  /// `recovery_key(i) = HKDF(seed, "recovery" ‖ i)` (§13.3.1).
  final Uint8List recoveryKey;

  /// The result of `sealBundle(bundle_key, nonce, content)` (§13.3.3).
  final Uint8List sealed;
}

/// Where the bundle comes from. `null` means „not now" — for instance because the
/// identity has not yet loaded a master seed. That is NOT an error
/// and is not treated as one; at the next attempt it is asked
/// again.
typedef RecoveryBundleSource = RecoveryBundleMaterial? Function(
    int recoveryEpoch);

/// After how many slots it is asked again whether a renewal is due.
///
/// CALCULATED, NOT CHOSEN: the cadence is 14 days (§13.3.4), i.e.
/// 151 200 slots of `kSlotInterval` = 8 s. Asking every slot would mean
/// letting the application serialise a contact list 151 200 times per renewal
/// — the question itself is the expensive part, not
/// the answer. 450 slots are one hour: 336 questions per cadence, and the
/// renewal happens at most one hour after the epoch change.
/// Against a TTL of 31 days at a 14-day cadence (§13.3.4: „14 + 14 <
/// 31") one hour is of no significance.
const int kRecoveryBundleCheckSlots = 450;

/// How many stored items the line enqueues at most per slot.
///
/// ONE. The slot cycle hands out exactly one cell per slot
/// (`DeliveryNode.tick` calls `takeControl()` once); enqueuing more
/// would only let the queue grow.
const int kRecoveryBundleFramesPerSlot = 1;

/// Every how many slots a SEARCH run happens.
///
/// Four, like `V41Node.harvestEverySlots` — the same number for the same
/// reason: the control channel lets out exactly one frame per slot, and a
/// run enqueues at most three. Asking more often would only let the
/// queue grow.
const int kRecoveryBundleHarvestSlots = 4;

/// How many SEARCH runs a recovery makes at most.
///
/// ── WHY A CAP IS NEEDED ───────────────────────────────────
///
/// §13.2.3 is normative: „**an unsuccessful search is not an error and
/// must not invent one.**" From that it does NOT follow, however, that asking may
/// go on forever — work rule 5 and §19 („no polling") forbid exactly
/// that. A search without a cap would be a standing cycle: three requests every four
/// slots, unlimited, for a bundle that does not exist.
///
/// CALCULATED: the tag set is finite. For the first block it is
/// `3 Epochen x 10 Stuecke x 3 Familien` = 90 tags; a run covers
/// at most `maxRequests x kMaxRealHarvestTags` = 3 x 6 = 18, i.e.
/// five runs per full pass. 120 runs are thus 24 full
/// passes — and in that time (120 x 4 slots of 8 s = **64 min**)
/// even a routing table still empty at cold start is long filled.
/// Whoever has found nothing by then finds nothing at the 121st run either:
/// the same tags, the same relays.
const int kRecoveryHarvestMaxRuns = 120;

/// The bundle line of an identity.
final class RecoveryBundleLine {
  RecoveryBundleLine({
    required this.node,
    required this.source,
    void Function(String)? log,
  }) : _log = log ?? ((_) {});

  final V41Node node;
  final RecoveryBundleSource source;
  final void Function(String) _log;

  // ── DEPOSIT ───────────────────────────────────────────────────────

  /// The recovery epoch for which a plan was last built
  /// — at the same time the epoch against which the targets of the plan are
  /// computed.
  ///
  /// **THE RECOVERY EPOCH, NOT THE NODE EPOCH**, and that
  /// is no trifle: `targetFor(tag, e)` mixes `e` into the
  /// search point (§9.1, `H(T ‖ e)`), so it determines WHICH relays
  /// are responsible. The node epoch moves daily
  /// (`kEpochSeconds` = 86 400); a bundle stored according to it
  /// would after a week lie with relays no one asks any more,
  /// while the TTL of 31 days is still running. The
  /// recovery epoch stands still for 14 days — exactly as long as
  /// a renewal is valid.
  int? _planEpoch;

  /// What is still to be enqueued: per entry a tag and its cell.
  final List<({Uint8List tag, Uint8List cell, int family})> _plan =
      <({Uint8List tag, Uint8List cell, int family})>[];

  /// The responsibility set of the first plan entry, computed once.
  List<EntryRecord> _set = const <EntryRecord>[];
  int _setIndex = 0;
  bool _selfPlaced = false;

  /// How many renewals this line has started.
  int renewals = 0;

  /// How many cells it has enqueued in total.
  int placements = 0;

  /// How many tags the running plan still has to work through.
  int get pendingTags => _plan.length;

  /// How many stored items the running plan costs in total — the number from
  /// §13.3.2/§9.2, calculated on TODAY's table and not on the
  /// field assumption.
  int get plannedPlacements => _plan.length * kResponsibleRelays;

  /// The connection to the slot cycle of the node.
  ///
  /// APPENDS, does not overwrite (`V41Node.addSlotTick`). With
  /// multi-identity that is the difference between „runs" and „silently
  /// no longer runs": `attachV41` runs once per identity against
  /// THE SAME node, and §13.3.1 demands „**One bundle per
  /// identity**".
  ///
  /// IDEMPOTENT: called twice, the line hangs only once.
  void attach() {
    if (_appended) return;
    node.addSlotTick(slot);
    _appended = true;
  }

  /// Takes the line off the cycle again.
  void detach() {
    if (!_appended) return;
    node.removeSlotTick(slot);
    _appended = false;
  }

  bool _appended = false;

  /// Whether the line hangs on the tick.
  bool get attached => _appended;

  /// One slot. Three things, in this order and no other:
  ///
  ///   1. the edge of the recovery epoch (§13.3.4),
  ///   2. the SEARCH, if one is currently running,
  ///   3. otherwise the trickling of the storing.
  ///
  /// **Search and storing exclude each other**, and that is not a
  /// matter of economy: whoever searches has just lost everything and has nothing
  /// to store — §13.1.3 („The recovering user can **harvest not a
  /// single message**"). Doing both at the same time would mean building a bundle
  /// from a state that has not yet been restored.
  void slot(int slotNumber) {
    if (slotNumber % kRecoveryBundleCheckSlots == 0) renewIfDue();
    if (harvesting) {
      if (slotNumber % kRecoveryBundleHarvestSlots == 0) harvestTick();
      return;
    }
    feed();
  }

  /// Builds a new storing plan if the recovery epoch
  /// has moved.
  ///
  /// Returns how many tags the new plan has (0 if there was nothing
  /// to do).
  int renewIfDue({DateTime? now}) {
    final current = now ?? DateTime.now().toUtc();
    final epoch = recoveryEpochFor(current);
    if (_planEpoch == epoch) return 0;
    final material = source(epoch);
    if (material == null) {
      // NO ERROR, NO NOTE OF THE EPOCH. If the epoch were noted here,
      // an identity that had not yet loaded a seed at the first attempt
      // would remain fourteen days without a bundle — and
      // nothing would say so.
      return 0;
    }
    renew(
        recoveryKey: material.recoveryKey,
        sealed: material.sealed,
        now: current);
    return _plan.length;
  }

  /// Builds the storing plan for a given bundle.
  ///
  /// ── THE ORDER, AND WHAT IT BUYS ──────────────────────────
  ///
  /// Per cell its `kDeliveryFamilies` = 3 tags stand one after another,
  /// and every tag is worked through over its whole responsibility set
  /// before the next one begins. Thus a cell is COMPLETELY redundantly stored after
  /// `m x R` = 60 slots (8 min), instead of
  /// sixty cells each lying singly after the same time.
  ///
  /// For the bundle that is the right direction — unlike with
  /// `placeSecure`, where storing goes round-robin across the families. The
  /// difference is the object: there it is about ONE message
  /// whose three families should stand at the same time. Here an
  /// interrupted renewal falls apart anyway — a bundle missing a BLOCK
  /// is unusable, however complete the others lie. And the
  /// previous renewal is still there (TTL 31 d against cadence 14 d, §13.3.4),
  /// so that an aborted renewal costs nothing except itself.
  void renew({
    required Uint8List recoveryKey,
    required Uint8List sealed,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now().toUtc();
    final epoch = recoveryEpochFor(current);
    final cells = splitRecoveryBundle(sealed);
    _plan
      ..clear()
      ..addAll(<({Uint8List tag, Uint8List cell, int family})>[
        for (final z in cells)
          for (var f = 0; f < kDeliveryFamilies; f++)
            (
              tag: recoveryBundleCellTag(recoveryKey, epoch,
                  block: z.block, fragment: z.fragment, family: f),
              cell: z.content,
              family: f,
            )
      ]);
    _set = const <EntryRecord>[];
    _setIndex = 0;
    _selfPlaced = false;
    _planEpoch = epoch;
    renewals++;
    _log('Recovery bundle (§13.3): renewal for epoch $epoch — '
        '${sealed.length} B sealed, '
        '${recoveryBundleBlockCount(sealed.length)} blocks, '
        '${cells.length} pieces, ${_plan.length} marks '
        '(m = $kDeliveryFamilies), '
        '${recoveryBundlePlacements(sealed.length, relaysPerTag: kResponsibleRelays)} '
        'deposits at R = $kResponsibleRelays');
  }

  /// Enqueues at most [kRecoveryBundleFramesPerSlot] stored items.
  ///
  /// Returns how many there were.
  int feed({DateTime? now}) {
    if (_plan.isEmpty) return 0;
    final epoch = _planEpoch;
    if (epoch == null) return 0;
    // ── ONLY INTO AN EMPTY QUEUE ─────────────────────────────────
    //
    // Not „below the limit" but EMPTY. Everything else in the
    // control channel has an addressee who is waiting: a message,
    // a harvest, a call signalling with a 120 s period. The bundle
    // has fourteen days.
    if (node.pendingControlFrames > 0) return 0;

    final current = now ?? DateTime.now().toUtc();
    var placed = 0;
    while (placed < kRecoveryBundleFramesPerSlot && _plan.isNotEmpty) {
      final entry = _plan.first;
      if (_set.isEmpty) {
        final target = targetFor(entry.tag, epoch);
        _set = node.responsibleRelays(target, count: kResponsibleRelays);
        _setIndex = 0;
        if (!_selfPlaced &&
            node.isSelfResponsible(target, _set, count: kResponsibleRelays)) {
          node.storeUnderTag(
              tag: entry.tag,
              cell: entry.cell,
              retention: kRetentionManagement,
              now: current);
          _selfPlaced = true;
        }
        if (_set.isEmpty) {
          // NO RELAY KNOWN. The plan stays; at the next
          // slot it is computed again. Discarding it here would mean letting a
          // bundle fail at a start moment in which the
          // routing table is still empty.
          return placed;
        }
      }
      node.placeUnderTag(
        relay: _set[_setIndex],
        tag: entry.tag,
        cell: entry.cell,
        retention: kRetentionManagement,
        family: entry.family,
        now: current,
      );
      placements++;
      placed++;
      _setIndex++;
      if (_setIndex >= _set.length) {
        _plan.removeAt(0);
        _set = const <EntryRecord>[];
        _setIndex = 0;
        _selfPlaced = false;
      }
    }
    return placed;
  }

  // ── HARVEST (§13.3.1, „Finding without a directory") ──────────────

  /// One collector per queried recovery epoch.
  ///
  /// THREE, because §13.3.1 demands three: „harvests the line for **current +
  /// 2 previous** epochs (42 d coverage), which fully covers the bundle's
  /// 31-day TTL". Separate, because two renewals may be of different
  /// size (see `RecoveryBundleAssembler.offer`).
  final Map<int, RecoveryBundleAssembler> _assembler =
      <int, RecoveryBundleAssembler>{};

  Uint8List? _harvestKey;
  int _harvestOffset = 0;

  /// How many search runs have paused because of a full control channel
  /// (S380). Counterpart of `V41Node._ernteAusgesetzt` — the same rule,
  /// the same counter, only for the second harvest path. Without it
  /// [harvestRunDue] would not know when „pausing yes, stopping no" makes the
  /// forced run due.
  int _harvestSuspended = 0;

  /// How many search runs this recovery has already made.
  int harvestRuns = 0;

  /// Whether the search has reached its cap without finding anything.
  ///
  /// **That is NOT an error** (§13.2.3: „an unsuccessful search is not an
  /// error and must not invent one") — it is the case from §13.2.2
  /// („Without a Bundle: New Inbox, Old Content Lost"). The caller
  /// shows „no answer yet", not „failed".
  bool exhausted = false;

  /// The found, still SEALED bundle — or `null`.
  ///
  /// Sealed, because opening needs the seed and that does not belong
  /// here. The caller calls `openBundle(bundleKey(seed), …)`.
  Uint8List? sealedFound;

  /// From which epoch the found bundle comes.
  int? foundEpoch;

  /// Called as soon as a bundle is completely reassembled.
  ///
  /// The callback gets the SEALED bytes: opening needs the
  /// seed, and that does not belong here. If it throws, the throw falls into the
  /// slot callback of the node and is caught there — the cycle does not
  /// tear.
  void Function(Uint8List sealed, int epoch)? onFound;

  /// Starts a search for the own bundle.
  ///
  /// [recoveryKey] is `recovery_key(i)`; it follows from the seed alone
  /// (§13.3.1) — that is the whole property on which §13 rests.
  void beginHarvest(Uint8List recoveryKey) {
    _harvestKey = Uint8List.fromList(recoveryKey);
    _assembler.clear();
    _harvestOffset = 0;
    harvestRuns = 0;
    exhausted = false;
    sealedFound = null;
    foundEpoch = null;
  }

  /// Aborts a running search.
  void endHarvest() {
    _harvestKey = null;
    _assembler.clear();
  }

  /// Whether a search is currently running.
  bool get harvesting =>
      _harvestKey != null && sealedFound == null && !exhausted;

  /// One harvest run. Returns how many requests were enqueued.
  ///
  /// ── WHAT IT ASKS, AND IN WHICH ORDER ────────────────────
  ///
  /// Before the first cell the block count is UNKNOWN — it stands in the
  /// cell header, and one only has that once a cell is there. That is why
  /// the first run per epoch asks for block 0, namely for all
  /// [kBundleFragmentsPerBlock] pieces in all
  /// [kDeliveryFamilies] families. As soon as a cell answers, its
  /// header says how many blocks follow, and the further runs only ask
  /// for what is missing.
  ///
  /// ── AND WHY IT MAY DO SO MUCH ───────────────────────────────────
  ///
  /// During a recovery this node has **zero**
  /// pair keys: there are no contacts for which harvesting
  /// could happen, and `harvestTick` falls straight through its loop over
  /// `pairs.harvestPeers`. The whole harvest cap is
  /// available to this search, and precisely when it is
  /// needed.
  int harvestTick({DateTime? now, int maxRequests = 3}) {
    final key = _harvestKey;
    if (key == null || sealedFound != null || exhausted) return 0;
    // -- THE SAME BRAKE AS THE TAG RUN (S380, 10.09.2026) -------
    //
    // S374 built `ernteLaufFaellig` + `ernteDeckel` against the standing
    // backlog - but only in the tag run
    // (`V41Node.harvestTick`). THIS run stayed unbraked, and it is
    // the larger inflow: it hangs per IDENTITY on the slot cycle
    // (`kRecoveryBundleHarvestSlots` = 4 slots = 32 s) and makes per run
    // up to `maxRequests` = 3 requests, for up to
    // `kRecoveryHarvestMaxRuns` = 120 runs.
    //
    // CALCULATED: 3 requests per 32 s and identity are 5.6/min; with two
    // identities 11.25/min. The outflow is ONE cell per
    // `kSlotInterval` = 8 s, i.e. 7.5/min. The channel is thus overbooked
    // by this path alone, and permanently.
    //
    // MEASURED IN THE FIELD on 10.09.2026 (.201 and .202, two
    // identities each): 123 harvest requests in 10 minutes = 12.3/min,
    // control queue 120/120 for hours, `droppedControl` 141 -> 345
    // and still rising. A contact request enqueued in this situation
    // waits 16 minutes (120 frames / 7.5 per minute) -
    // measured: it did not arrive within 13 minutes.
    //
    // WHAT IS NOT TOUCHED HERE: `m`, `R` and the cover rate. Those
    // are the three adjusting screws that `V41Node.kHarvestMaxSkips`
    // explicitly reserves for the owner, because they touch traffic or
    // anonymity. Here only the INFLOW is bound to the same rule
    // that the neighbouring path has had since S374 - "pausing yes,
    // stopping no".
    final waiting = node.egress.stream.pendingControl;
    if (!harvestRunDue(
        waitingFrame: waiting,
        limit: V41Node.kHarvestBacklogLimit,
        suspended: _harvestSuspended,
        atMostSkips: V41Node.kHarvestMaxSkips)) {
      _harvestSuspended++;
      return 0;
    }
    final cap = harvestCap(
      waitingFrame: waiting,
      limit: V41Node.kHarvestBacklogLimit,
      fullCap: maxRequests,
      forcedCap: V41Node.kHarvestForcedRequests,
    );
    if (_harvestSuspended > 0) {
      _log('Recovery bundle (§13.3): $_harvestSuspended run(s) '
          'suspended (control queue $waiting) - one goes anyway, '
          'capped at $cap instead of $maxRequests');
    }
    _harvestSuspended = 0;
    if (harvestRuns >= kRecoveryHarvestMaxRuns) {
      exhausted = true;
      _log('Recovery bundle (§13.3): $harvestRuns search runs without a find — '
          'search ended. This is NOT an error (§13.2.3), but the case '
          'from §13.2.2: new mailbox, old contents lost.');
      return 0;
    }
    harvestRuns++;
    final current = now ?? DateTime.now().toUtc();
    // ── AIM AT THE EPOCH THAT ANSWERED ──────────────────
    //
    // As long as nothing is found, all three epochs are queried
    // (§13.3.1: „current + 2 previous"). But as soon as ONE of them has
    // delivered a cell, a bundle lies there — and asking the two
    // others further for block 0 would cost two thirds of every
    // frame for tags under which there is nothing more to fetch.
    final allEpochs = recoveryHarvestEpochs(current);
    final answered = <int>[
      for (final e in allEpochs)
        if (_assembler[e]?.blocks != null) e
    ];
    final epochs = answered.isEmpty ? allEpochs : answered;

    final marks = <Uint8List>[];
    final marksEpoch = <int>[];
    final order = <({int epoch, int block, int fragment, int family})>[];
    for (final e in epochs) {
      final assembler = _assembler.putIfAbsent(e, RecoveryBundleAssembler.new);
      final blocks = assembler.blocks == null
          ? const <int>[0]
          : assembler.missingBlocks;
      for (final b in blocks) {
        for (var f = 0; f < kBundleFragmentsPerBlock; f++) {
          for (var fam = 0; fam < kDeliveryFamilies; fam++) {
            marks.add(recoveryBundleCellTag(key, e,
                block: b, fragment: f, family: fam));
            marksEpoch.add(e);
            order.add((epoch: e, block: b, fragment: f, family: fam));
          }
        }
      }
    }
    if (marks.isEmpty) return 0;

    // ── SAMPLED, NOT ALL AT ONCE ──────────────────────────
    //
    // Three epochs of 10 pieces of 3 families are 90 tags for
    // block 0 alone; a frame carries `kMaxRealHarvestTags` = 6. Enqueuing all at
    // once would fill the queue with fifteen frames and
    // make the node deaf to everything else for two minutes — that
    // is the same bug that cost S352 its delivery, only on
    // a different axis. The offset moves by one per run; over
    // enough runs every tag gets its turn.
    final n = marks.length;
    final from = _harvestOffset % n;
    final rotated = <Uint8List>[for (var i = 0; i < n; i++) marks[(from + i) % n]];
    final rotatedEpochs = <int>[
      for (var i = 0; i < n; i++) marksEpoch[(from + i) % n]
    ];
    _harvestOffset++;

    return node.harvestUnderTags(
      tags: rotated,
      epochs: rotatedEpochs,
      // CAPPED AS DECIDED ABOVE, not with the full wish: with a
      // standing backlog that is ONE request (S380).
      maxRequests: cap,
      offset: _harvestOffset,
      sink: _offered,
    );
  }

  void _offered(Uint8List cell) {
    if (sealedFound != null) return;
    // WHICH EPOCH? The cell header does NOT say — it carries block,
    // piece and length, not the epoch of the tag under which the cell
    // lay. Offering it to every collector is cheap (one header read per
    // collector) and right: a piece that does not fit a
    // collector's layout is left lying by it automatically.
    for (final e in _assembler.keys.toList(growable: false)) {
      final done = _assembler[e]!.offer(cell);
      if (done != null) {
        sealedFound = done;
        foundEpoch = e;
        _log('Recovery bundle (§13.3): bundle from epoch $e '
            'assembled (${done.length} B sealed)');
        onFound?.call(done, e);
        return;
      }
    }
  }
}
