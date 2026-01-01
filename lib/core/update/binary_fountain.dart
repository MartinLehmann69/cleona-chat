// An update binary as a fountain object (§26.6.1, AP-7).
//
// ── THE GAP THIS FILE CLOSES ────────────────────────────
//
// §26.6.1 specifies: "The binary is **encoded per platform into fountain
// blocks** (block size = one cell payload, ~1.1 KB) and placed into the
// delivery layer." That was not built. Re-measured on 04.09.2026 over
// the whole of `lib/`:
//
//   * `BulkTransferKeys.fromRoot`/`.fresh` — TWO producers, both in
//     `service/media_bulk_lane.dart` (l. 340, 546);
//   * `FountainEncoder(` — ONE producer, `bulk/bulk_sender.dart:78`;
//   * `lib/core/update/` — unchanged the V3 line: Reed-Solomon
//     (`binary_update_manager.dart:8`, `binary_seeder.dart:4`,
//     `delta_update_manager.dart:3`) with indexed `fragment-NNN.bin`.
//
// So not a single fountain block of a binary existed. This
// file is the way there — and it builds **no second mechanism**:
// it uses `BulkSender` and `BulkReceiver` unchanged. What stands here
// is solely what differs in the binary case from the media case:
//
//   1. **The root is not drawn but passed in.** With media
//      the sender draws `K_T` fresh (`BulkTransferKeys.fresh`) and
//      sends it along in the offer. With the binary there is no offer and
//      no sender — many desktops seed the same object and
//      must agree on THE SAME root (§26.6.1, quoted in
//      `bulk_keys.dart:151-154`).
//   2. **Where this root comes from has stood here since 05.09.2026.**
//      The owner derived it from the NETWORK SECRET
//      (`K_T = HKDF(netzgeheimnis, "update/root/" ‖ binaryHash)`) — no
//      manifest field, no pipeline change, no
//      compatibility rule, no existing manifest becomes invalid.
//      See [binaryTransferRoot], which also states why the two
//      other paths are rejected.
//
//      **Until S368 here stood "`K_T = HKDF(binaryHash, "update/root")`".**
//      That was the S367 version and it was too weak: `binaryHashes`
//      stands in the PUBLIC manifest, so any observer
//      outside the closed network could compute the root and open every
//      cover cell on trial — B-29 cancelled. Measured in
//      `smoke_update_cover_fill` section 9 ("the outsider with the
//      PUBLIC manifest"); with the old formula exactly these
//      three checks are red.
//
//      Until S365 it stood here that the origin was open and that there was therefore
//      no caller that PROCURES a root; since S367 there is one
//      (`cleona_service_update.dart`, `meldeUpdateObjekteAn`).
//   3. **The content hash is already public.** `UpdateManifest`
//      has carried `binaryHashes` per platform since §19.6.2 — the SHA-256 of the
//      binary — and `binarySignatures` over it. The fountain codec
//      needs exactly this hash (`objectId` = its first 8 B,
//      `bulk_keys.dart:119`), but does not compute it itself (E-42).
//
// ── WHAT IS NOT IN HERE ─────────────────────────────────────────
//
// NO I/O. No file access, no network, no clock. The caller reads
// the binary and passes the bytes in; he takes the blocks and
// hands them out. The reason is the same as with `BulkSender`: `R_bulk`
// and the slot tick belong to the egress, and two ticks in the program are
// an error.
//
// NO REPLACEMENT OF THE V3 LINE. `binary_update_manager.dart` and
// `binary_fragment_store.dart` stay untouched. Switching them off
// presupposes the root decision (without it nobody can open a binary
// that came via this path) — and a path that arrives at the user
// must not be switched off before its successor carries
// (`project_android_update_flow_v145.md`: the click path is mandatory).
library;

import 'dart:typed_data';

import 'package:cleona/core/bulk/bulk_control.dart';
import 'package:cleona/core/bulk/bulk_keys.dart';
import 'package:cleona/core/bulk/bulk_receiver.dart';
import 'package:cleona/core/bulk/bulk_sender.dart';
import 'package:cleona/core/fountain/fountain_block.dart';

/// The root `K_T` of an update binary — **derived, not passed in**.
///
/// ── THE DECISION (owner, 05.09.2026): FROM THE NETWORK SECRET ───
///
/// All seeders of the same object must have the same root, otherwise
/// they produce different blocks and the cache no longer deduplicates
/// (§26.6.1; calculated in `bulk_keys.dart`: with 1000 seeders of a
/// 190 MB binary ~190 GB instead of ~190 MB). An offer from which they could
/// read it does not exist for the binary — the receiver has no
/// key exchange with the sender.
///
/// Three paths were available for choice
/// (`docs/v4-redesign/S365-VORLAGE-dritter-weg-und-wurzel.md`), the third
/// was chosen:
///
///   A  root as a new field in the signed manifest.
///   B' root deterministically from `binaryHashes` (the S365 version
///      of THIS function).
///   B  root from the **network secret**, bound to the content hash.
///
/// **A and B' are security-equivalent, and both are too weak.**
/// `binaryHashes` stands in the signed manifest, and the manifest is
/// public (GitHub release, §26.6). Whoever has it computes with B' the
/// root — and thus the tag and the epoch line `H(T ‖ e)` — without
/// ever having been in the network. That cancels **B-29**: an observer
/// OUTSIDE the closed network can open every cover cell
/// on trial and gets "opens = filler, does not open =
/// real traffic" — exactly the sieve against which §5.1 and §5.5 rule 3
/// are built.
///
/// **B draws the line at the closed network.** The network secret lies
/// only in official builds (`network_secret.dart`, Closed Network
/// Model); an outsider does not have it, and the publicity of the
/// manifest no longer helps him. Within the network everything stays
/// that §26.6.1 requires: all seeders compute the same root, their
/// blocks are byte-identical, the content-addressed cache keeps them
/// once.
///
/// **The content hash stays in the info part** and carries on two properties
/// that B' had and that must not be lost: the root
/// is bound to the CONTENT (a seeder cannot seed with a root
/// that does not belong to its binary), and two versions
/// never have the same root (old and new blocks can lie in the same
/// tag line, §26.6.1).
///
/// ── WHY NOT `deriveBinaryKey`, MEASURED ─────────────────────────
///
/// `rendezvous_secret.dart:157` already carries
/// `deriveBinaryKey(networkSecret, epochString)` and returns 32 B — the
/// length that [BulkTransferKeys.fromRoot] requires. It is nonetheless
/// **not** used here, and the reason is a number:
/// `kRendezvousEpochHours = 6` (`rendezvous_secret.dart:39`). An
/// epoch-bound root changes four times a day. The measured
/// spread via the cover fill needs **28 days**
/// (`test/perf/perf_cover_fill_push_s365.dart`, case E) — with a
/// 6-hour root all held blocks would be unreadable after every change,
/// every collector would start from the beginning, and the cache could
/// no longer deduplicate, because the same blocks would have different
/// bytes in every epoch. The distribution would never arrive. Hence here: **no
/// epoch**, the root stands as long as the version.
///
/// ── WHAT THAT COSTS, AND WHERE THE CAP AGAINST IT SITS ─────────────────
///
/// `bulk_block_seal.dart` carries the seal per block as a doorman: "a
/// slipped-in block is rejected at the door … it would need
/// `K_T`". **Against a MEMBER of the network that does not hold here either.**
/// Whoever has the network secret and the manifest — i.e. every participant —
/// computes the root and can build a block with a valid header,
/// canonical nonce and spoiled payload; `openBulkBlock`
/// lets it through, and only the full SHA-256 at the exit catches it —
/// then according to §26.6.1 ("discarded and re-fetched") the whole
/// collection round falls. Against an OUTSIDER the door is closed again with B,
/// and that is the gain over B'.
///
/// The cap against it is `kCoverFillMaxHashFailures = 3`
/// (`cover_fill_blocks.dart`): after that the object accepts no
/// UNSOLICITED blocks any more and falls back to the harvest.
///
/// **No code execution risk.** Installation still hangs unchanged
/// on `binarySignatures` (Ed25519 of the maintainer over the binary hash).
///
/// [networkSecret] is `NetworkSecret.secret` — as a parameter and not
/// as an import, so that this file stays parameter-pure (the same reason as
/// with [binaryFountainObjectFor]) and so that a probe can run two different
/// secrets against each other.
Uint8List binaryTransferRoot(Uint8List contentHash, Uint8List networkSecret) {
  if (contentHash.length != kBulkContentHashBytes) {
    throw ArgumentError(
      'Content hash must be $kBulkContentHashBytes B, is '
      '${contentHash.length}',
    );
  }
  if (networkSecret.isEmpty) {
    throw ArgumentError('Network secret is empty — without it there is no '
        'root (owner decision B, 05.09.2026)');
  }
  return bulkHkdf(networkSecret, 'update/root/${_hexRoot(contentHash)}');
}

String _hexRoot(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

/// Builds the object from the three manifest entries of a platform.
///
/// `null` if one of them is missing or unusable — a manifest without
/// `binaryHashes`/`binarySizes` for this platform is the normal case
/// (old manifest, or a platform without in-network distribution), not an
/// error.
///
/// **DOES NOT TAKE AN `UpdateManifest`, and that is intentional.** This
/// file keeps itself free of I/O; `update_manifest.dart` brings along
/// `app_paths.dart` and thus `dart:io`. The mapping
/// manifest field -> entry is done by the service, which holds the manifest
/// anyway.
///
/// **ALSO DOES NOT TAKE `NetworkSecret`**, for the same reason and
/// with a second one besides: [networkSecret] is a parameter so that a
/// probe can run two different secrets against each other. Exactly
/// that is measured by the reverse probe of decision B — a node with a
/// different network secret must not be able to open a block. If
/// the secret were imported here instead of passed in, the statement could
/// not be checked at all.
BinaryFountainObject? binaryFountainObjectFor({
  required String version,
  required String platform,
  required String? contentHashHex,
  required int? objectLength,
  required Uint8List networkSecret,
}) {
  if (contentHashHex == null || objectLength == null) return null;
  if (objectLength < 1) return null;
  final hash = hexToBytesOrNull(contentHashHex);
  if (hash == null || hash.length != kBulkContentHashBytes) return null;
  // A build without network key material (`NetworkSecret.hasKeyMaterial`
  // == false, architecture §4.10) derives a null secret. It cannot
  // join the network anyway; here it silently falls through instead of
  // computing a root that no other node shares.
  if (networkSecret.isEmpty || networkSecret.every((b) => b == 0)) return null;
  return BinaryFountainObject(
    version: version,
    platform: platform,
    contentHash: hash,
    objectLength: objectLength,
    transferRoot: binaryTransferRoot(hash, networkSecret),
  );
}

/// Hex characters -> bytes, `null` for everything that is not one.
///
/// Our own and not from `util/hex.dart`: the reader there throws on
/// nonsense. Here the string comes from a manifest, i.e. from
/// outside — a throw at this place would be a crash surface that a
/// stranger triggers.
Uint8List? hexToBytesOrNull(String s) {
  if (s.isEmpty || s.length.isOdd) return null;
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    final b = int.tryParse(s.substring(i * 2, i * 2 + 2), radix: 16);
    if (b == null) return null;
    out[i] = b;
  }
  return out;
}

/// The identifier of an update object: one binary of one version for one
/// platform.
///
/// **Everything about it is already public** — version and platform stand
/// in the manifest, the content hash as well (`UpdateManifest.binaryHashes`).
/// That is no oversight, but the prerequisite for several
/// seeders producing byte-identical blocks.
final class BinaryFountainObject {
  /// Version of the manifest to which this binary belongs.
  final String version;

  /// `linux`, `windows`, `android` — the same keys as
  /// `UpdateManifest.binaryTag`.
  final String platform;

  /// SHA-256 of the unmodified binary (32 B). From the manifest.
  final Uint8List contentHash;

  /// Length of the unmodified binary.
  final int objectLength;

  /// The keys of this transmission, from the PASSED-IN root.
  final BulkTransferKeys keys;

  BinaryFountainObject({
    required this.version,
    required this.platform,
    required this.contentHash,
    required this.objectLength,
    required Uint8List transferRoot,
  }) : keys = BulkTransferKeys.fromRoot(transferRoot) {
    if (contentHash.length != kBulkContentHashBytes) {
      throw ArgumentError(
        'Content hash must be $kBulkContentHashBytes B, '
        'is ${contentHash.length}',
      );
    }
    if (objectLength < 1) {
      throw ArgumentError.value(objectLength, 'objectLength', 'must be >= 1');
    }
  }

  /// The 8 B by which the decoder assigns a block to this object.
  Uint8List get objectId => objectIdFromContentHash(contentHash);

  /// `k` — the number of source blocks.
  int get sourceBlocks => FountainBlock.sourceBlockCount(objectLength);

  @override
  String toString() =>
      'BinaryFountainObject($platform $version, $objectLength B, '
      'k=$sourceBlocks)';
}

/// The SEED SIDE: blocks are made from a binary.
///
/// ── WHY [KeyedSeeds] AND NOT THE DEFAULT ────────────────────────
///
/// `BulkSender` uses [SequentialSeeds] by default — justified in
/// `bulk_keys.dart` by the fact that the only consumer so far (the
/// media lane) has EXACTLY ONE seeder. With the binary many nodes seed
/// the same object, and the difference is measured
/// (`test/perf/perf_cover_fill_push_s365.dart`, 400 desktops, 5 MB delta,
/// 04.09.2026):
///
///   keyed      duplicates  0.0 % of arrivals
///   sequential duplicates  6.2 % of arrivals
///
/// The reason is immediate: with sequential seeds ALL
/// neighbours of a receiver push the same sequence 0, 1, 2, … — every block that
/// the second neighbour delivers has already come from the first.
///
/// **That holds for the PUSH, not automatically for the placement.** For the
/// placement at the responsible ones (§9.3) the counter-calculation from
/// `bulk_keys.dart` speaks: there with sequential seeds the cache keeps every
/// block exactly once, however many seed (~190 MB against ~190 GB with
/// 1000 seeders). This file does NOT decide the placement side — it
/// takes the seed source as a parameter, so that both paths can choose their
/// own.
final class BinaryFountainSeeder {
  final BinaryFountainObject object;
  final BulkSender _sender;

  BinaryFountainSeeder._(this.object, this._sender);

  /// [binary] are the bytes of the binary, [seeds] the seed source.
  ///
  /// Throws if [binary] does not match [object] — the hash is checked HERE
  /// and not left to the caller. A seeder that
  /// encodes a different binary than the manifest names distributes blocks
  /// that tip over the whole version state at every receiver
  /// (§26.6.1 self-healing) — the most expensive silent error of this path.
  /// [seeds] is the seed source and deliberately has **no default**.
  ///
  /// ── WHY NONE (04.09.2026, own finding) ────────────────────────
  ///
  /// The first version inserted here
  /// `KeyedSeeds(seederSecret: object.keys.root, …)` when the
  /// caller specified nothing. That is the worst possible value: the
  /// root is THE SAME for ALL seeders (that is its purpose, §26.6.1),
  /// so all nodes would draw the same seed sequence — exactly the case
  /// `SequentialSeeds` that the measurement shows to be expensive (13.9 % duplicates
  /// against 0.0 %). A default that silently takes back the measured
  /// decision is worse than none.
  factory BinaryFountainSeeder({
    required BinaryFountainObject object,
    required Uint8List binary,
    required BulkSeedSource seeds,
  }) {
    if (binary.length != object.objectLength) {
      throw ArgumentError(
        'Binary is ${binary.length} B, the object names '
        '${object.objectLength} B',
      );
    }
    final hash = bulkContentHash(binary);
    if (!bytesEqualConstantTime(hash, object.contentHash)) {
      throw ArgumentError('Binary does not match the content hash of the object');
    }
    return BinaryFountainSeeder._(
      object,
      BulkSender(object: binary, keys: object.keys, seeds: seeds),
    );
  }

  int get sourceBlocks => _sender.sourceBlocks;
  int get blocksEmitted => _sender.blocksEmitted;

  /// How many blocks a receiver needs at ZERO loss.
  int get plannedBlocks => _sender.plannedBlocks;

  /// Draws [count] further sealed blocks.
  List<Uint8List> nextSealedBlocks(int count) => <Uint8List>[
    for (final (bytes, _) in _sender.nextBlocks(count)) bytes,
  ];
}

/// The COLLECTION SIDE: blocks become the binary again.
///
/// Thin wrapper around [BulkReceiver] — the two gates (seal at the
/// door, full SHA-256 at the exit) are built there and are not
/// rebuilt here. What this class adds is the path from the manifest:
/// `BulkReceiver.fromAnnounce` presupposes a `BulkAnnounce`, and with the
/// binary there is none.
final class BinaryFountainCollector {
  final BinaryFountainObject object;
  final BulkReceiver _receiver;

  BinaryFountainCollector._(this.object, this._receiver);

  factory BinaryFountainCollector(BinaryFountainObject object) {
    // The offer that does not exist for the binary is FORMED here from the
    // manifest — the same three quantities, a different origin.
    // Via this path `BulkReceiver` stays the only place that
    // takes in and checks blocks.
    final announce = BulkAnnounce(
      contentHash: object.contentHash,
      objectLength: object.objectLength,
      transferRoot: object.keys.root,
    );
    return BinaryFountainCollector._(
      object,
      BulkReceiver.fromAnnounce(announce, object.keys),
    );
  }

  int get sourceBlocks => _receiver.sourceBlocks;
  int get resolvedSourceBlocks => _receiver.resolvedSourceBlocks;
  double get progress => _receiver.progress;
  bool get isComplete => _receiver.isComplete;
  int get hashFailures => _receiver.hashFailures;
  int get foreignBlocks => _receiver.foreignBlocks;

  /// Offers a sealed block.
  BulkOffer offerSealed(Uint8List sealed) => _receiver.offerSealed(sealed);

  /// The assembly — the only place at which bytes come out, and
  /// only with a passed hash check.
  BulkTake take() => _receiver.take();

  /// How many blocks are still missing (for the harvest, §26.6.1).
  BulkRefillRequest refill() => _receiver.refill();
}
