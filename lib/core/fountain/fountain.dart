/// Fountain codec — rateless erasure coding for **large objects**
/// (work package AP-7, §9, §26.6.1).
///
/// ── TWO CONSUMERS, ONE BLOCK FORMAT ────────────────────────────────
///
/// 1. **Media bulk lane** — files and media beyond message size
///    (§9, "offline large payloads").
/// 2. **Binary distribution** — in-network updates: the binary per
///    platform travels as fountain blocks via the fountain erasure cache
///    of the always-on tier, the manifest is harvested, not queried
///    (E-40, §26.6.1).
///
/// Both use **the same** block format (`fountain_block.dart`), because
/// they share the same cache and the same cells. A block carries no
/// origin; it carries an object identifier.
///
/// ── WHAT THE CODEC IS NOT ──────────────────────────────────────────
///
/// It is **not** the delivery path for messages. Messages and recovery
/// bundles ride Reed-Solomon (N=10, K=7,
/// `lib/core/codec/reed_solomon.dart`; until the CUT of 2026-08-31 the
/// file lay in `lib/core/erasure/`) — the fountain coding of messages was
/// a V4.0 idea and has been withdrawn (§13.0 "Delivery re-pointing
/// note", §9).
///
/// It computes **no** hashes and **no** signatures. The object identifier
/// comes from the caller; checking the reconstructed object against the
/// full content hash and the hybrid manifest signature is step 5 in
/// §26.6.1 and lies with the caller.
///
/// It uses **no FFI and no third-party library** (E-42, 2026-08-08:
/// LT codes in pure Dart; RaptorQ rejected, because a native library on
/// five platforms and an unclear legal situation would be the price that
/// this decision explicitly does not pay).
///
/// ── THE OVERHEAD FIGURE ────────────────────────────────────────────
///
/// How many blocks beyond `k` the recipient needs is the open measurement
/// requirement §27-O-3. It is measured by `test/perf/perf_fountain.dart`,
/// secured by `test/smoke/smoke_fountain.dart`. The defaults in
/// `DegreeDistribution` stem from this measurement.
///
/// ── THE CONNECTION LIES IN `lib/core/bulk/` ──────────────────────────
///
/// This codec is the first, self-contained half of AP-7. The second —
/// keys, tags, holders, hashes — lies in `lib/core/bulk/` (`bulk.dart`
/// lists it). Done with that are:
///
/// 1. **Cell type `0x05`.** `LinkFrameType.fountain` has stood in
///    `LinkFrameType.known` since 30.08. (`lib/core/link/frame.dart`). A
///    sealed block (1069 B) plus frame header (3 B) occupies 1072 B in a
///    cell with 1172 B of interior — no fragmentation.
/// 2. **Object identifier and final check.** `bulk_keys.dart` carries the
///    content hash (8 B into it as `objectId`), `BulkReceiver.take` checks
///    the full hash against the reconstructed object and hands out **no
///    bytes** outside of `BulkVerdict.verified` (§26.6.1 step 5). The
///    hybrid manifest signature for updates stays with the update
///    consumer.
/// 3. **The cache.** `BulkCache`: own quota (E-53: 1 GB, desktop only,
///    lowest priority), `TTL_media`, scanning instead of querying,
///    deduplication by block tag.
/// 4. **Seed assignment.** `BulkSeedPolicy` with both paths and the price
///    of both; default `sequential`, because today's consumer has exactly
///    one seeder.
///
/// Still open:
///
/// 5. **File-backed encoding.** [FountainEncoder] holds the whole object
///    in memory. For a 200 MB binary on a phone that is not a viable
///    path.
/// 6. **Resumability.** The decoder state lives only in memory.
///    §26.6.1 requires that a partial state survives an abort
///    ("transient errors delete nothing").
/// 7. **Offloading into an isolate.** Named as planned in §27.4.2,
///    not built.
library;

export 'block_xor.dart';
export 'degree_distribution.dart';
export 'fountain_block.dart';
export 'fountain_decoder.dart';
export 'fountain_encoder.dart';
