// The numbers of the bulk lane — one file, so that they do not wander.
//
// Every constant here stands like this in the architecture document (appendix A) or in
// §9.3/§21.3.3. Where it is "proposed" and not "decided", this is stated
// alongside — whoever measures it later thus finds the place where the
// measurement belongs.
//
// NO STATE, NO I/O.
library;

/// Cap of the bulk quota, in bytes (§21.3.3 no. 3, E-53).
///
/// "**1 GB default**, user-overridable in tiers analogous to the media
/// budget (§21.6 pattern), no automatic growth with disk size."
///
/// Decimal GB, not GiB — the same reading as
/// `sync/budget_class.dart:transitPoolCapacityBytes`, where the rationale
/// is.
const int kBulkCacheCapacityBytes = 1000000000;

/// `TTL_media` (Appendix A, §9.3): **7 d**.
///
/// „An offline recipient is not a failure: blocks wait in the bulk cache
/// for `TTL_media` (default 7 d, cleared 24 h after the receipt)."
const int kTtlMediaSeconds = 7 * 24 * 3600;

/// How long a tag is still held after the DECODED receipt
/// (§9.3: "cleared 24 h after the receipt").
///
/// Not immediately, because the receipt may come from one of several devices of the same
/// identity (§14.2: all devices harvest the same line) —
/// the second would otherwise have nothing left to fetch.
const int kBulkClearAfterReceiptSeconds = 24 * 3600;

/// `R_bulk` (appendix A, §9.3): **32 cells/s**, uniform, one
/// transfer at a time. Status in the document: *proposed*, to be measured.
const int kBulkRateCellsPerSecond = 32;

/// Relay size cap `C` (appendix A, §17.6/§9.3, D-1): **25 MB
/// payload**. Above it a transfer no longer asks a volunteer
/// and takes the bulk lane, regardless of whether both sides are online.
const int kRelaySizeCapBytes = 25 * 1000 * 1000;

/// Size of the responsibility set the bulk lane is designed
/// against — `R` from §9.1.
///
/// **THIS FILE STAYS IMPORT-FREE** (see [_log]); `kResponsibleRelays`
/// from `tagline/responsibility.dart` would pull in `sodium_ffi` and thus the
/// loading of a library. The number therefore stands here a second
/// time — and precisely for that reason a GUARD stands behind it that does not compare the
/// two numbers but checks the STATEMENT from which they both
/// derive: `test/smoke/smoke_bulk_f_auslegung.dart` places blocks
/// over a real `BulkPlacementPlan` and counts over how many
/// different holders the round-robin really runs.
const int kNominalBulkHolders = 20;

/// **`p` — THE ONE NUMBER THAT IS TO BE SET HERE.**
///
/// Share of the `R` responsible relays that do NOT accept a placement. The
/// usual case behind it is in §9.3: "Mobile nodes hold no bulk (E-53)" —
/// a mobile node in the responsibility set is a holder whose
/// blocks lie nowhere.
///
/// ── IT IS NOT AVAILABLE, AND THAT IS MEASURED (S363, 03.09.2026) ────────
///
/// On 02.09. the owner decided: **no platform byte in the
/// `EntryRecord`** (variant A rejected — a permanent, signed,
/// network-wide retrievable partition of the population is the (c) axis that
/// §5.4 is precisely closing for `R` and `d`), and the number is
/// estimated **off-network** from the platform shares of the installations
/// (variant D).
///
/// This estimate is **not possible** today. Measured on the
/// release pipeline (`repos/MartinLehmann69/cleona-chat`, all releases,
/// `gh api .../releases`, 03.09.2026): **65 downloads across all
/// releases together** — 46 APK, 16 Windows, 1 each Linux, iOS
/// and macOS —, the repository has 1 star and 0 forks, and there is
/// no store release (only TestFlight internal tests). Those are
/// the developer's devices and the test VMs, not a population. There
/// is also no counter in the program that could replace it: no
/// telemetry path, no installation counter, and the only place where
/// a platform appears on the wire at all is the
/// binary pull (`binary_http_server.dart:85-97`) — it measures "who fetches
/// a binary", not "who is in a responsibility set".
///
/// ── WHY 0.20 NEVERTHELESS AND NOT 0 ──────────────────────────────────
///
/// **0.20 is the value that the program ALREADY uses TODAY** — it just
/// was not written down. Until S363 `F` was a fixed floor of 1.300. Measured
/// (`test/perf/perf_f_auslegung_s363.dart deckung`), this floor covers
/// at 200 MB exactly `d = 4` of `R = 20`: needed 251 400 blocks,
/// planned 253 907. The derivation below reproduces it: at `p` = 0.20
/// it computes 251 933. The 1.300 thus WERE "cover 4 of 20", only
/// exclusively for large objects — for small ones the same
/// expression covered NOTHING, because it was a `max` and not a factor (see
/// [bulkOvershoot]).
///
/// A smaller `p` would thus be **not a neutral default, but a
/// silent withdrawal** of the coverage that large transfers have today.
/// A larger one cannot be justified without a number. The
/// computed price of every choice is in
/// `docs/v4-redesign/S363-VORLAGE-f-auslegung.md`; what is to be changed is
/// **this one line**.
///
/// And it is an UPPER BOUND as soon as the installation numbers come:
/// mobile nodes are online less often and therefore underrepresented in a
/// responsibility set — the installation share overestimates `p`.
/// For a COVERAGE that is the safe direction.
const double kAssumedHolderLossShare = 0.20;

/// `d` — how many of the [holders] responsible relays the design withstands.
///
/// Rounded up: half a failed holder is none.
int coveredHolderFailures({int holders = kNominalBulkHolders}) {
  if (holders < 2) return 0;
  var d = (kAssumedHolderLossShare * holders).ceil();
  if (d < 0) d = 0;
  // More than `holders - 1` would no longer be a coverage factor but a
  // division by zero or negative.
  if (d > holders - 1) d = holders - 1;
  return d;
}

/// The coverage factor `R / (R - d)`.
///
/// ── WHY EXACTLY THIS EXPRESSION ──────────────────────────────────────
///
/// `BulkPlacementPlan.forBlocks` places ROUND-ROBIN: block `i` goes to holder
/// `i mod R` (`bulk_placement.dart:113-127`). If a holder fails,
/// the receiver is not missing a random share, but **exactly the
/// residue class** `i mod R == j` — `d` failed holders take away exactly
/// `d/R` of the blocks sent. So that `n` blocks ARRIVE,
/// `n * R/(R-d)` must be SENT. That is not a
/// probability calculation but a set calculation.
double holderLossCover(int failures, {int holders = kNominalBulkHolders}) {
  if (failures <= 0) return 1.0;
  if (failures >= holders) {
    throw ArgumentError.value(failures, 'failures', 'must be < $holders');
  }
  return holders / (holders - failures);
}

/// The measured surcharge above the set calculation.
///
/// ── WHAT IT IS FOR ───────────────────────────────────────────────────
///
/// [holderLossCover] assumes that a seed sequence thinned out by `d/R`
/// behaves like a prefix of the same length. For large
/// objects that is almost exactly right; for small ones not, because the graph is then
/// so sparse that it matters WHICH residue class is missing.
///
/// ── THE SUPPORT POINTS ARE MEASURED, NOT ESTIMATED ────────────────
///
/// `test/perf/perf_f_design_s363.dart band <d> 4096`, 03.09.2026, on
/// the shipped graph (`DegreeDistribution.neighbours` is
/// wire format). For `d = 1` COMPLETE — all 20 possible positions
/// of a failed holder, no sample —, for `d = 4` 30
/// drawn positions per `k`; 738 values of `k`. Given is
/// `Bedarf / ceil(Plan * R/(R-d))`:
///
/// ```
/// k band          d=1 median  d=1 p90   d=4 median  d=4 p90   MAX
/// 32..255            1.032     1.195      1.095      1.333    1.824
/// 256..1023          0.971     1.074      1.000      1.138    1.380
/// 1024..4096         0.866     0.921      0.878      0.939    1.121
/// ```
///
/// Plus the six field sizes (`… deckung 60 alle`, `Bedarf/Formel`,  (german-ok)
/// largest value over `d` = 1..4): 5 MB 1.062; 50 MB 0.997;
/// 200 MB 1.008.
///
/// ── IT IS THE p90 AND NOT THE MAXIMUM, AND THAT IS A CHOICE ──────
///
/// The maximum over the band is **1.824** (k = 58). Covering it
/// would cost +82 % on EVERY small transfer — for the last ten
/// percent of object sizes. Exactly for these ten percent §9.3 provides
/// the refill path (`refill`), and the measurement of S363
/// (task 1, recommendation A) recommends building it: it costs 60 cells
/// / 8 min in the Secure chat, and only when a harvest really hangs.
/// An overshoot covers the usual case, the return channel the rest — designing the
/// usual case for the maximum would mean replacing the return channel with
/// permanent costs.
///
/// **CORRECTED ON 2026-09-03.** Here it said: "As long as `refill` has no
/// caller in `lib/` (S363 1.1: zero), these ~10 % of the
/// sizes stay incomplete with `d` failed holders." The path has been
/// built AND walked since `7266736b`. Measured on 2026-09-03 over
/// `lib/`, separately for `refill(`, `refillRequestFor`, `refillsRequested`
/// and `.refill`:
///
///   * receive branch: `BulkReceiver.refill()` (`bulk/bulk_receiver.dart:290`)
///     is called from `service/media_bulk_lane.dart:571`
///     (`refillRequestFor`) and `:606` (`maybeRequestRefill`).
///   * trigger without a clock: `service/media_bulk_transport_v41.dart:267-281`
///     reports the empty round, wired in `media_bulk_lane.dart:302-307`.
///   * send branch: `MediaBulkLane.refill` (`media_bulk_lane.dart:494`)
///     is called from `service/cleona_service_media.dart:427`; below it
///     `BulkSender.refill` (`bulk/bulk_sender.dart:196`).
///   * cap per transfer: `kBulkRefillMaxRequests`
///     (`media_bulk_lane.dart:605`).
///
/// What REMAINS: the ~10 % above the p90 thus cost a return path
/// instead of permanent costs — exactly the design this paragraph justifies.
double measuredPlanningMargin(int objectBytes) {
  // Kept in BYTES and not in `k`, so that this file stays import-free
  // (`FountainBlock.sourceBlockCount` would otherwise be needed here). The
  // support points are the band limits from the measurement run, in bytes:
  // k = 255 -> 261 120 B, k = 1023 -> 1 047 552 B.
  const points = <(int, double)>[
    (261120, 1.34), // k <= 255   (p90 d=4: 1,333)
    (1047552, 1.14), // k <= 1023 (p90 d=4: 1,138)
    (5000000, 1.07), // 5 MB      (largest value over d: 1,062)
    (50000000, 1.01), // 50 MB    (largest value over d: 0,997)
  ];
  if (objectBytes <= points.first.$1) return points.first.$2;
  if (objectBytes >= points.last.$1) return points.last.$2;
  for (var i = 0; i < points.length - 1; i++) {
    final (x0, y0) = points[i];
    final (x1, y1) = points[i + 1];
    if (objectBytes <= x1) {
      final t = (_log(objectBytes) - _log(x0)) / (_log(x1) - _log(x0));
      return y0 + (y1 - y0) * t;
    }
  }
  return points.last.$2;
}

/// Size of the micro-preview in the announce (appendix A): **<= 979 B**, so that
/// the announce fits into ONE cell.
const int kAnnouncePreviewMaxBytes = 979;

/// Below this size an object enters no media lane at all.
///
/// ── SINCE S372 IT IS THE LOWER BOUND OF THE REED-SOLOMON LANE ──────────
///
/// Until 06.09.2026 it was the lower bound of the BULK lane, and that was
/// the contradiction that decision E-3 = D resolves: §9.3 names ~256 KB
/// as the NORMATIVE lower bound of the rateless lanes and justifies it with
/// its own measurement (1.367 at 64 KiB with maximum 2.750; at 16 KiB
/// two of 4 000 runs without reconstruction even at 3k), while
/// this line sent the band 32..256 KB — the NORMAL CASE PHOTO — exactly onto that
/// lane.
///
/// It was resolved not by moving one of the two numbers,
/// but by a third lane in between: 32 KB up to
/// [kFountainLowerBoundBytes] is carried by Reed-Solomon
/// (`lib/core/codec/erasure_stripes.dart`). This constant thus keeps
/// name and value and changes its meaning — it now separates the cell path
/// from the media lane, no longer the cell path from the bulk lane.
///
/// ── WHY 32 KB AND NOT LESS ────────────────────────────────────
///
/// The cell path splits up to `kMaxSplitPayloadBytes` = 32 768 B
/// (`tagline/frame_split.dart`, deliberate memory cap per remote side).
/// The two limits meet; there is no size for which
/// neither the cell path nor a lane would be responsible. And below that a
/// transfer with tag, placements and its own clock for an object of
/// 5 KB would be effort without benefit.
const int kFountainWorthwhileBytes = 32 * 1024;

/// From this size on the RATELESS lanes carry (stream §17.6, bulk
/// §9.3); below it, down to [kFountainWorthwhileBytes], Reed-Solomon
/// carries.
///
/// ── TAKEN OVER, NOT CHOSEN ──────────────────────────────────────
///
/// The number is the row "Fountain lower bound | **~256 KB** — below it
/// the bulk lane is not used" from appendix A of the leading document,
/// unchanged. CHOOSING it a second time here would have been the
/// neighbouring column; it was taken so that the three ranges
/// meet without gaps and without overlap:
///
/// ```
///   < 32 KB                       cell path (frame_split)
///   32 KB .. < 256 KB             Reed-Solomon (erasure_stripes)
///   >= 256 KB                     stream (§17.6) or bulk (§9.3)
/// ```
///
/// ── AND IT IS CHECKED AGAINST THE MEASUREMENT, NOT JUST COPIED ──
///
/// Computed from the support points of appendix A (S372, 06.09.2026,
/// `test/perf/perf_medienspur_s372.dart`), the two crossings
/// at which Reed-Solomon becomes more expensive than the rateless coding lie at
///
///   * **40 681 B**, if one puts the MEAN curve
///     [measuredFountainOverhead] against 10/7, and
///   * **2 529 898 B**, if one puts the upper spread (the maxima of the same
///     support points) against it.
///
/// Appendix A itself says that the design is "chosen on the **upper
/// tail**, not the mean" — the 256 KB lie between the two and
/// thus safely in the range in which Reed-Solomon is measurably cheaper.
/// Against the BUILT planner ([plannedBlocksFor], which includes coverage and margin)
/// the stripe coding even only crosses at
/// **2 151 424 B** — the same size that appendix A independently names as
/// "k ≈ 2048 (~2 MB)". That between 256 KB and 2 MB there is still
/// 25.7 % traffic is measured and lies with the owner as a separate
/// proposal; it is a separate decision with its own number and
/// not an appendage to this one.
///
/// `smoke_erasure_lane.dart` pins the check down: the computed
/// crossing against the built planner must lie ABOVE this limit.
const int kFountainLowerBoundBytes = 256 * 1024;

/// The measured overhead figure as a function of the object size.
///
/// Support points from the measurement run of AP-7 (`test/perf/perf_fountain.dart`,
/// 2026-08-30): 16 KiB -> 1,546; 64 KiB -> 1,367; 5 MiB -> 1,079;
/// 200 MiB -> 1,021. In between it is interpolated logarithmically, beyond
/// that clamped.
///
/// WHY INTERPOLATED AND NOT ROUNDED. A single factor would be too expensive for
/// large objects (1.3 instead of 1.021 on 200 MB is 56 MB of
/// superfluous traffic) and too cheap for small ones (1.3 instead of 1.546 on
/// 16 KiB means: the receiver does not finish). Both errors are
/// large enough not to make them.
double measuredFountainOverhead(int objectBytes) {
  const points = <(int, double)>[
    (16 * 1024, 1.546),
    (64 * 1024, 1.367),
    (5 * 1024 * 1024, 1.079),
    (200 * 1024 * 1024, 1.021),
  ];
  if (objectBytes <= points.first.$1) return points.first.$2;
  if (objectBytes >= points.last.$1) return points.last.$2;
  for (var i = 0; i < points.length - 1; i++) {
    final (x0, y0) = points[i];
    final (x1, y1) = points[i + 1];
    if (objectBytes <= x1) {
      // Logarithmic in x: the support points are apart by factors,
      // not by summands.
      final t = (_log(objectBytes) - _log(x0)) / (_log(x1) - _log(x0));
      return y0 + (y1 - y0) * t;
    }
  }
  return points.last.$2;
}

/// The overshoot factor `F` for an object of [objectBytes] — a
/// DERIVATION, not an assumption.
///
/// ```
///   F(bytes) = codingNeed(bytes)    x  R/(R-d)  x  margin(bytes)
///              \_ measuredFountain  \_ holder   \_ measuredPlanning
///                 Overhead             LossCover    Margin
/// ```
///
/// ── WHAT STOOD HERE UNTIL S363 AND WHY IT WAS WRONG ──────────────────
///
/// Until 03.09.2026 this function read
/// `max(gemessen(bytes), 1,3)`, with the rationale that the 1.3 from appendix A
/// covers "fountain overhead plus churn refills". **A `max` covers no
/// churn.** It only takes effect where the coding need is BELOW 1.3 anyway
/// — i.e. for large objects; exactly where the coding need
/// is HIGH (small objects), the same expression delivered the pure coding need
/// and thus **zero** reserve for a failed holder.
///
/// Measured against what a failed holder really costs
/// (`test/perf/perf_f_auslegung_s363.dart deckung 60 alle`, 03.09.2026):
///
/// ```
/// object     k        old plan   withstands d = ...
/// 64 KiB        64          95   NO d, not even d=1
/// 200 KiB      200         260   NO d, not even d=1
/// 1 MB         977        1271   d=1
/// 5 MB        4883        6348   d=2
/// 50 MB      48829       63478   d=3
/// 200 MB    195313      253907   d=4
/// ```
///
/// And over the whole band (`… band 1 4096`): **361 of 738**
/// object sizes did not withstand even ONE failed holder, at
/// `d = 4` **738 of 738**. That matches the field measurement from
/// S363 1.3(b): a single non-holding node out of twenty brought
/// 68.5 % of the 64 KiB and 60.5 % of the 256 KB transfers to a halt.
///
/// ── WHY MULTIPLICATIVE AND NOT AS A FLOOR OR SUMMAND ─────────────
///
/// The loss is a SHARE of the blocks sent, not a surcharge
/// on their number: `d` of `R` holders take away `d/R`, no matter how many there
/// were (`holderLossCover` justifies the set calculation). A floor
/// cannot model that — it is constant, the need is not —,
/// and a summand cannot either, because it would give too
/// little for small objects and too much for large ones.
///
/// ── WHAT THE MEASURED CURVE IS AND WHAT IT IS NOT ────────────────
///
/// [measuredFountainOverhead] is the MEAN over random seeds.
/// The sender does not roll dice — it draws [SequentialSeeds], its block set
/// is a function of `k`. For it the right number is the EXACT
/// prefix, and `bulk_prefix.dart:exactSequentialPrefix` counts it;
/// [plannedBlocksFor] puts both side by side and takes the larger one
/// as the coding need, BEFORE coverage and margin are applied to it.
///
/// The path proposed here earlier, "measured MAXIMUM instead of mean",
/// stays settled, and the rationale stays valid: the maximum is
/// not a bound but a function of the number of runs (k = 64,
/// random seeds: 100 runs -> 2,219; 1 000 -> 2,875; 10 000 ->
/// 3,359; 100 000 -> 4,344; 400 000 -> 4,438). The "2.750" from §9.3 is
/// the largest of 3 000 throws, not a property of the codec.
///
/// [holders] and [failures] are arguments and not constants, so that
/// a caller with a SMALLER responsibility set (in a small network
/// `responsibleRelays` breaks off, `delivery_api.dart:481-482`) can compute
/// correctly: there a failed holder weighs more.
double bulkOvershoot(int objectBytes,
    {int holders = kNominalBulkHolders, int? failures}) {
  final d = failures ?? coveredHolderFailures(holders: holders);
  return measuredFountainOverhead(objectBytes) *
      holderLossCover(d, holders: holders) *
      measuredPlanningMargin(objectBytes);
}

double _log(int v) {
  // Without `dart:math` — this file is meant to stay import-free, so that it can be read in
  // any context. Natural logarithm via the
  // series for ln((1+z)/(1-z)) after splitting off the power of two.
  var x = v.toDouble();
  var e = 0;
  while (x >= 2.0) {
    x /= 2.0;
    e++;
  }
  final z = (x - 1) / (x + 1);
  final z2 = z * z;
  var term = z;
  var sum = 0.0;
  for (var n = 1; n <= 25; n += 2) {
    sum += term / n;
    term *= z2;
  }
  return 2 * sum + e * 0.6931471805599453;
}
