/// The bulk lane — the second half of AP-7 (§9.3, §17.6, §21.2,
/// §26.6.1).
///
/// ── WHAT LIVES HERE ───────────────────────────────────────────────────
///
/// The fountain codec (`lib/core/fountain/`) turns an object into
/// equivalent blocks and back again. It knows no keys,
/// no tags, no holders and no hashes — deliberately (E-42, pure
/// Dart without crypto dependency). This directory is everything that is
/// missing in between:
///
/// | File | What it does |
/// |---|---|
/// | `bulk_params.dart` | the numbers from appendix A and §21.3.3, plus the MEASURED overhead curve |
/// | `bulk_keys.dart` | `K_T`, transfer tag, seal key, seed allocation |
/// | `bulk_block_seal.dart` | seal per block |
/// | `bulk_frames.dart` | the wire: placement, scanning, answer (type `0x05`) |
/// | `bulk_egress.dart` | the SECOND outflow at `R_bulk` |
/// | `bulk_cache.dart` | the holder's bulk quota: 1 GB, desktop only, `TTL_media`, scanning |
/// | `bulk_placement.dart` | round-robin over the responsible ones — EXACTLY one placement per block |
/// | `bulk_prefix.dart` | how many consecutive seeds REALLY suffice — counted, not estimated |
/// | `bulk_control.dart` | announce, request, refill, DECODED receipt |
/// | `bulk_lane.dart` | which lane (§17.6) and whether at all (Secure consent, §12) |
/// | `bulk_codec.dart` | which CODEC — rateless or Reed-Solomon stripes (§9.3, E-3 = D) |
/// | `bulk_sender.dart` | draw blocks, seal, assign; answer refill |
/// | `bulk_receiver.dart` | scan, deduplicate, **content binding** (§26.6.1 step 5) |
///
/// ── THE THREE PROMISES THIS LANE MUST GIVE ──────────────────────
///
/// 1. **Never silently wrong bytes.** Two gates: the seal per block at
///    the door, the full content hash at the exit. `BulkReceiver.take` returns
///    `null` outside of `BulkVerdict.verified`.
/// 2. **Exactly one placement per block.** Not `m x R` — that would cost around
///    a factor of 60 on the wire and buys nothing a rateless code
///    does not already deliver (§9.3). The redundancy is the overhead factor.
/// 3. **Mobile holds no bulk.** `BulkCache.forBudgetClass` gives a
///    harvester a disabled cache, not a small one (E-53).
///
/// ── WHAT HAS NO CALLER YET ─────────────────────────────────────
///
/// The egress. `R_bulk` (32 cells/s) is a property of the
/// send clock, not of these classes; likewise the placing itself, the
/// scanning over the onion and the connection to `routeFor`
/// (`service/v41_routing.dart:66` currently sends media on the
/// V3 two-step path). The report on AP-7 lists this as a
/// patch proposal.
library;

export 'bulk_block_seal.dart';
export 'bulk_cache.dart';
export 'bulk_codec.dart';
export 'bulk_control.dart';
export 'bulk_egress.dart';
export 'bulk_frames.dart';
export 'bulk_keys.dart';
export 'bulk_lane.dart';
export 'bulk_params.dart';
export 'bulk_placement.dart';
export 'bulk_prefix.dart';
export 'bulk_receiver.dart';
export 'bulk_sender.dart';
