// Secure mode — store instead of forward.
//
// THE DIFFERENCE FROM THE SPEED PATH is not the cryptography but the
// time axis. Speed forwards immediately; Secure stores the cell at the
// responsible relays and the receiver fetches it at ITS cadence —
// hidden in the cover stream. The latency thus hangs on the harvest cadence H,
// not on the network size (M2): ~1 h ceiling on reachable
// platforms, and that is the price that §8 openly states.
//
// THREE FAMILIES (m=3, D1). The same message is stored under THREE tags
// that come from the same pair root but different families.
// Because the tags yield independent points in the metric space,
// the three responsibility sets are practically disjoint too: whoever
// wants to suppress delivery must hit ALL THREE. That is the
// lever against censorship that S344 put in place of the dead PoW.
//
// DECOYS, AND WHY THEIR ORDER MATTERS. A harvest query carries
// `d` decoys per real tag (E-C′: d=3, uniform). If the real
// tags always stood in front, the masking would be worthless — the relay would read
// the answer off the position. The set is therefore mixed deterministically,
// from a device-local secret. Deterministic, so that
// the same epoch twice yields the same set in the same order:
// two queries with different mixing would reveal through the
// intersection which tags occur in both — and those would be the real ones.
//
// NO LIVENESS NEEDED. A pure Secure contact needs no
// liveness record (§6): storing happens on a tag, not on a
// living path. Exactly that makes the liveness cost depend on S
// and not on the total number of contacts (M5).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';

import 'harvest_memo.dart' show cellDigest;
import 'liveness.dart' show pairAnchor, kDecoyCount;
import 'package:cleona/core/bulk/responsibility.dart';
import 'secure_frames.dart'
    show
        kMaxHarvestTagsTotal,
        kRetentionManagement,
        kRetentionNormal,
        kRetentionSignal;

/// How many families a delivery carries (m=3, D1).
const int kFamilies = 3;

/// How many epochs backwards a harvest run SUBSCRIBES — §22.4.1:
/// „epoch subscription: **current + 2 previous**".
///
/// ── THIS NUMBER IS NOT THE RETENTION PERIOD (S363) ───────────────
///
/// Until S363 this said „How many epochs backwards the ORDINARY
/// period reaches (§22.4.1: current + 2) — at the same time `SecureStore.keepEpochs`".
/// Both in one sentence, and exactly therein lay the bug: **one number carried
/// two different quantities.** §22.4.1 names „current + 2" for the
/// SUBSCRIPTION depth of the harvest; retention stands in §21.1 („TTL
/// expiry (**14 d default**, 31 d for management types)",
/// `Cleona_Chat_Architecture_v4_1.md` §21.1, l. 7101 — re-measured
/// 03.09.2026 in the main tree `~/Cleona`, because v4_1 is not in the tree on `v4/knoten-host`;
/// line numbers are branch-dependent, the
/// paragraph number is not). Because `SecureStore.keepEpochs` defaulted to THIS
/// constant and `DeliveryNode` builds the store without the
/// parameter, an ordinary cell lay for **three** instead of fourteen
/// days — the number from the neighbouring column.
///
/// Retention has since been called [kNormalKeepEpochs] = 14.
/// [kHarvestEpochs] stays at 3 and now only means: how far the
/// SHALLOW rank of a harvest run asks back.
///
/// **And that is not a hole**, although 14 > 3: since S361
/// `ernteEpochenPlan` samples TWO ranks — the shallow `1 .. kHarvestEpochs - 1` and
/// the deep `kHarvestEpochs .. kManagementKeepEpochs - 1` = 3..30. The
/// backlogs 3..13, under which an ordinary cell can still lie since S363,
/// are thus covered by the deep rank; they cost no
/// additional frame, only the catch-up latency computed there (3.5 h
/// until the first coverage of a deep backlog, calculation at
/// [harvestEpochsPlan]). The edge on the other hand is `V41Node.nachholErnte`.
///
/// RAISING the depth here would be the same bug in the other
/// direction: every additional shallow epoch costs [kFamilies] tags per
/// counterpart, and at [kMaxRealHarvestTags] = 6 real tags per frame
/// already the fourth epoch means two frames instead of one — with a
/// cap of `kHarvestRequestsPerRun` = 3 thus one counterpart per run
/// instead of three. The full calculation is at [harvestEpochsPlan].
const int kHarvestEpochs = 3;

/// How many node epochs a cell of the ORDINARY class
/// ([kRetentionNormal]) lies at the responsible relay.
///
/// **14 epochs of [kEpochSeconds] = 86 400 s each, i.e. 14 days.**
///
/// ── DERIVATION ───────────────────────────────────────────────────────
///
/// §21.1 „Storage priorities", row 2 of the table: „TTL expiry (**14 d
/// default**, 31 d for management types) **or** eviction under
/// tag-line-budget overflow, **within the quota** (§20)".
/// Re-measured on 03.09.2026 in `Cleona_Chat_Architecture_v4_1.md`
/// **l. 7101** (heading §21.1 on l. 7094) — read in the main tree
/// `~/Cleona`, because the document is not in the tree on this branch.
/// The line number applies to that version; the paragraph number applies
/// everywhere.
///
/// Owner decision 03.09.2026, D2 from
/// `docs/v4-redesign/S363-VORLAGE-31-tage-konsolidiert.md` section 8:
/// **14 days** — the already decided value, i.e. WITHOUT
/// document change. The two alternatives and their price are there:
/// 3 d (~34 MB desktop delivery storage, contradicts §21.1) and 31 d
/// (~354 MB, four document places to change).
///
/// ── WHAT IT COSTS, RECALCULATED ────────────────────────────────────
///
/// §21.3.2 derives the mobile value from „~160 MB for **14 days** of full
/// retention, i.e. **~11.4 MB/day**" (l. 7187-7189 of the same
/// version). Thus the 14-day number is the one ALREADY budgeted in the document,
/// and the build of today with 3 epochs was at ~34 MB
/// **below** the budget, not above. The increase amounts to ~126 MB per
/// desktop node and is the price that §21.3.1 („Delivery-layer
/// storage, desktop, full TTL: **~160 MB**") lists as decided.
///
/// **On mobile nodes something VERY MUCH changes** — the proposal
/// says „no, there the cap binds", and recalculated that holds only
/// above an inflow rate that §21.3.2 explicitly does NOT expect of a mobile
/// node. The calculation (measured in
/// `smoke_v41_inhaltsfrist_14_tage.dart` section 8c):
///
///   * On mobile `SecureStore.maxTotalBytes` is set to
///     [kMobileSecureStoreCapBytes] = 32 MB (`v41_attach.dart`
///     -> `DeliveryNode(maxStoreBytes:)` -> here).
///   * The cap only binds above `32 MB / Frist`, i.e. above
///     **2.29 MB/day** at 14 d (before above 10.67 MB/day at 3 d).
///   * §21.3.2 on the mobile inflow: „a mobile node cannot receive the
///     11.4 MB/day of its subscription set at all — a pure background
///     node accumulates real **single-digit MB per 48 h**", i.e. about
///     0.5-4.5 MB/day.
///
/// Thus the WHOLE documented mobile range lay below the threshold before D2:
/// there the PERIOD bound, not the cap. After D2 the period
/// continues to bind at the lower end. The held volume of a
/// mobile background node grows from 1.5-13.5 MB to 7.0-32.0 MB.
///
/// **The 11.4 MB/day are a DESKTOP quantity** and must not be used for a
/// mobile node — exactly the mix-up that made
/// this constant necessary in the first place.
///
/// What binds first on mobile is anyway neither of the two storage values
/// but the traffic — §21.3.2: „the traffic quota binds before the
/// storage does".
///
/// **OPEN, and grown larger with D2:** §21.3.3 no. 1 lists for
/// mobile nodes a period of **48 h as normative**. Only
/// the cap is built (option C, owner 02.09.2026). Before D2 the build exceeded
/// the normative period by a factor of 1.5 (72 h against 48 h), now by a
/// factor of 7 (14 d against 48 h). That is no new non-conformity,
/// but a clearly larger one.
///
/// ── AND WHAT ELSE BINDS BEFORE ──────────────────────────────────────
///
/// On the desktop too the period is not the only gate. Per
/// tag line [SecureStore.maxCellsPerTag] = 32 cells applies (§20,
/// quota isolation); a tag line is `(Paar, Epoche, Familie,
/// Richtung)` and thus lives anew for only ONE epoch anyway. The
/// longer period therefore does not increase the cells PER tag line but
/// the number of simultaneously held tag lines — linearly, factor 14/3.
/// Eviction per §20 applies unchanged within the quota.
const int kNormalKeepEpochs = 14;

/// How many REAL tags fit into ONE harvest request.
///
/// [kMaxHarvestTagsTotal] (25, computed from the cell size) counts real
/// AND decoys. Every real one travels with [kDecoyCount] decoys (§6, E-C′) —
/// the integer division is thus the actual capacity:
/// `25 ~/ (1 + 3) = 6`.
///
/// **THIS NUMBER IS NOT 25, and the mix-up is expensive.** Whoever plans 25
/// real tags builds with 100 total tags a frame of
/// 3568 B and gets an ArgumentError from the send path. That is why
/// the division stands here and not in the caller's head.
///
/// SIX IS EXACTLY ENOUGH FOR ONE CONTACT WITH BOTH LINES:
/// `kFamilies` (3) message tags plus `kFamilies` (3) signal tags
/// (§17.2) = 6. That is no coincidence but the layout against which
/// `buendleErnte` caps.
const int kMaxRealHarvestTags = kMaxHarvestTagsTotal ~/ (1 + kDecoyCount);

Uint8List _hkdf(Uint8List key, String info) => SodiumFFI().hkdfSha256(key,
    salt: Uint8List.fromList(utf8.encode('cleona-secure')),
    info: Uint8List.fromList(utf8.encode(info)),
    length: 32);

/// The Secure tag of a pair in [epoch] for [family] and [direction].
///
/// Only computable with `K_AB` — the KEX gate, and the reason why a
/// remote non-contact cannot steer specifically at a victim
/// (§10.1).
///
/// ── THE DIRECTION IS NOT DECORATION (B-22, S349) ─────────────────────
///
/// §15.2 and §15.4 explicitly write the tag line with direction:
/// „under `tag(K_AB, B→A)`". Until S349 it was missing here, and the consequence was
/// not some vagueness but a dead channel:
///
///   * Both sides stored under THE SAME tag.
///   * Each side thus also harvested its OWN cells back — sealed against
///     the counterpart, so not openable for itself.
///   * The own cells filled the assembler and displaced
///     those of the counterpart before their last piece arrived.
///
/// Measured in the field on 28.08.: B harvested 18 times, continuously got
/// harvest answers and opened **nothing**. A's text lay the whole
/// time at the responsible relay.
///
/// [direction] is 0 or 1 and is determined equally by BOTH sides:
/// from the lexicographic order of the two identities (see
/// `PairRegistry.directionFor`). Whoever sends takes his outgoing direction;
/// whoever harvests, the other. Without such a canonical order both sides
/// would have to coordinate — and exactly that is what `K_AB` is meant to spare.
Uint8List secureTag(Uint8List kAb, int epoch, int family, int direction) {
  if (family < 0 || family >= kFamilies) {
    throw ArgumentError('Family must be 0..${kFamilies - 1}');
  }
  if (direction != 0 && direction != 1) {
    throw ArgumentError('Direction must be 0 or 1');
  }
  return _hkdf(kAb, 'secure/$epoch/$family/$direction');
}

/// The SIGNAL tag of a pair — the own line of call signalling.
///
/// ── WHY SIGNALLING GETS A LINE OF ITS OWN ───────────────
///    (owner decision 2026-08-31)
///
/// The owner: „Aren't we censorable during a call anyway?
/// Loss is not acceptable, just as little as a long
/// ringing time." With that the trade-off is decided, and it is a
/// DIFFERENT one than for a text:
///
///   * A text may cost eight minutes of egress (`m x R` = 3 x 20 = 60
///     stored items at `R_cover` = 1/8 s), because eight minutes later it is
///     still the same text.
///   * An INVITE that arrives eight minutes later is no longer a call.
///     §17.2 gives it 120 s, and in 120 s, at one cell
///     per 8 s, exactly **15** stored items flow out.
///
/// `m` (3) x `kSignalRelays` (5) = 15. The responsibility set of this
/// line is therefore smaller — that is the renunciation of censorship redundancy that
/// the owner explicitly traded for timeliness. The three
/// FAMILIES stay: they are the lever against censorship (D1), and
/// giving them up would have turned the trade from „somewhat less redundancy" into „no
/// redundancy".
///
/// ── THE DERIVATION FOLLOWS `secureTag` EXACTLY ────────────────────────────
///
/// Same root `K_AB`, same epoch, same family, same
/// DIRECTION — only a different `info` string. The direction is not
/// decoration here either: B-22 measured what its absence costs (both
/// sides store under the same tag and harvest their own cells
/// back), and B-31 what a derivation without pair binding costs.
///
/// An own info string also means: the signal line of a
/// pair is NOT computable from its message line, and
/// vice versa. A relay that holds one learns nothing about the
/// other.
Uint8List signalTag(Uint8List kAb, int epoch, int family, int direction) {
  if (family < 0 || family >= kFamilies) {
    throw ArgumentError('Family must be 0..${kFamilies - 1}');
  }
  if (direction != 0 && direction != 1) {
    throw ArgumentError('Direction must be 0 or 1');
  }
  return _hkdf(kAb, 'signal/$epoch/$family/$direction');
}

/// The epoch of this pair — the same clock as liveness (E-J, E-M),
/// via the same epoch-free anchor, so that there is no circle.
int secureEpoch(Uint8List kAb, DateTime utc) =>
    epochFor(pairAnchor(kAb), utc);

/// The three points in the metric space around which storing happens.
List<Uint8List> secureTargets(Uint8List kAb, int epoch, int direction) =>
    List.generate(
        kFamilies, (f) => targetFor(secureTag(kAb, epoch, f, direction), epoch));

/// The harvest query set: real tags plus decoys, mixed.
///
/// [deviceSecret] is device-local — the decoys must be stable over the epoch,
/// otherwise the intersection of two queries reveals the real tags.
List<Uint8List> harvestQuerySet({
  required Uint8List kAb,
  required Uint8List deviceSecret,
  required int currentEpoch,
  required int direction,
  int decoysPerTag = kDecoyCount,
  int epochs = kHarvestEpochs,
}) {
  final real = <Uint8List>[];
  for (var e = currentEpoch; e > currentEpoch - epochs; e--) {
    for (var f = 0; f < kFamilies; f++) {
      // The INPUT direction — what is harvested is what the counterpart
      // stored, not what one stored oneself (B-22).
      real.add(secureTag(kAb, e, f, direction));
    }
  }
  final decoys = <Uint8List>[];
  for (var i = 0; i < real.length * decoysPerTag; i++) {
    decoys.add(_hkdf(deviceSecret, 'decoy/$currentEpoch/$i'));
  }

  final all = <Uint8List>[...real, ...decoys];
  // Mix deterministically: the position must reveal nothing, and two
  // queries of the same epoch must yield the same order.
  final order = _hkdf(deviceSecret, 'order/$currentEpoch');
  all.sort((x, y) {
    final hx = SodiumFFI().sha256(Uint8List.fromList([...order, ...x]));
    final hy = SodiumFFI().sha256(Uint8List.fromList([...order, ...y]));
    for (var i = 0; i < hx.length; i++) {
      if (hx[i] != hy[i]) return hx[i] - hy[i];
    }
    return 0;
  });
  return all;
}

/// Which epoch this harvest run queries for which family (§22.4.1),
/// over two ranks: the shallow one up to [epochs] and the deep one up to
/// [depth].
///
/// ── THE FINDING (S361) ────────────────────────────────────────────────
///
/// §22.4.1 writes for `lib/core/tagline/` „epoch subscription:
/// **current + 2 previous**" (the same number in the decision register:
/// „acceptance tolerance ±1 epoch, subscription current + 2 previous").
/// [harvestQuerySet] computes exactly that — and had NO caller in `lib/`.
/// The harvest run in `v41_node.dart` queried for both lines
/// exclusively the CURRENT epoch.
///
/// The consequence was not vagueness but a loss with a time of day: an
/// epoch is [kEpochSeconds] = 86 400 s, and the ordinary
/// retention was back then `SecureStore.keepEpochs` = 3 node epochs.
/// Whoever was away longer than until the next epoch boundary queried from
/// then on only tags under which nothing ever lay — while his
/// cells still lay at the responsible relay for up to three days. The
/// promised 72 h offline tolerance was a measured 24 h.
///
/// **Since S363 the store holds [kNormalKeepEpochs] = 14 epochs**
/// (D2, 03.09.2026); `keepEpochs` no longer hangs on [kHarvestEpochs].
/// The gap between period and shallow rank has thus become larger
/// — it is covered by the DEEP rank further below, which reaches up to
/// [kManagementKeepEpochs] - 1 = 30 and includes the backlogs 3..13.
///
/// ── WHY NOT SIMPLY THREE TIMES AS MANY TAGS ──────────────────────
///
/// Because that would triple the control channel, and it is already
/// overbooked. Calculated:
///
///   * A frame carries [kMaxRealHarvestTags] = 6 REAL tags (25
///     tags per cell, of which per real tag [kDecoyCount] = 3 decoys).
///   * A counterpart today costs exactly these 6: `kFamilies` = 3
///     message tags plus 3 signal tags — ONE frame, as long as a
///     shared relay exists.
///   * Three epochs on the message line would be 3 x 3 + 3 = 12
///     tags, i.e. AT LEAST two frames per counterpart.
///   * The run is capped at `kHarvestRequestsPerRun` = 3 frames
///     (derived from the outflow: `harvestEverySlots` = 4 slots of 8 s).
///     At 2 frames per counterpart a run would cover only ONE counterpart
///     instead of three — the round time at N contacts would rise from
///     `ceil(N/3) x 32 s` to `N x 32 s`, at N = 20 from 224 s to 640 s.
///
/// That is the price this function does NOT pay.
///
/// ── INSTEAD: SAMPLE, AS THE SPEC ALREADY DOES ─────────────────
///
/// §6 describes the procedure for relay selection in exactly these
/// words: „the harvest **samples** the responsible set (one relay per
/// family per run, §9.2), and that sampling is only sound because the
/// placement **covers** it." The same division of tasks carries the
/// epoch axis: storing covers (it stores in the current epoch under
/// ALL `m` families, §9.2), the harvest samples.
///
/// Per run therefore EXACTLY ONE family carries a previous epoch, the
/// others stay on the current one. The tags stay at six, the
/// frame stays one, the egress stays byte for byte the same.
///
/// The cycle runs over `familien x (epochen - 1)` = 6 runs and
/// takes the previous epochs INSIDE: run 0 asks `N-1`, run 1 `N-2`, run 2
/// again `N-1` (next family) and so on. Both previous epochs are
/// thus asked at least once after TWO runs (64 s), and after
/// six runs (192 s) every combination of family and previous epoch
/// has been asked exactly once. Against a retention of three DAYS that is
/// no relevant delay.
///
/// WHAT IT COSTS, openly: the current epoch is asked per run with
/// `familien - 1` = 2 instead of 3 families. That is no loss of
/// coverage — storing puts the same content under all three
/// family tags, one found family suffices —, but one
/// chance fewer per run in case storing reached only part of the
/// responsibility set. The pointer moves, so the
/// omitted family is included again in the next run; the cost is
/// at most one run = 32 s against the Secure ceiling of ~1 h (§8).
///
/// [run] is the counter that grows by one per counterpart with every harvest run
/// (`V41Node._ernteVersatz`) — the same one that lets the relay selection
/// move, and for the same reason separate per counterpart.
///
/// Returns: a list of length [families], entry `f` is the
/// epoch under which family `f` is to be asked in this run.
///
/// ── AND BEYOND THE ORDINARY PERIOD: THE MANAGEMENT CLASS ──────
///
/// Until S361 the rotation above sampled EXACTLY the three epochs that
/// [kHarvestEpochs] names (the SHALLOW rank). Thus the third
/// retention class
/// was unreachable: [kManagementKeepEpochs] = 31 epochs are the period that
/// §21.1 („31 d for management types") and the owner's promise („survive at least 31
/// days offline") demand — **28 of these 31 days no one ever
/// asked.** The relay held, the receiver did not ask; a
/// silent loss of exactly the class that was built not to
/// have one (emergency rotation, `cleona_service.dart` `rotateIdentityKeys`,
/// `management: true`).
///
/// The reach therefore grows to [depth] = [kManagementKeepEpochs].
/// Reachable are thus the backlogs `1 .. tiefe - 1` = 1..30 — 31
/// is the backlog at which `SecureStore.expire` has already thrown the cell
/// away (`c.epoch <= currentEpoch - kManagementKeepEpochs`).
///
/// ── THAT THIS GOES BEYOND §22.4.1 IS STATED HERE AND REPORTED ──
///
/// §22.4.1 says verbatim „epoch subscription: **current + 2 previous**"
/// — the number that [kHarvestEpochs] carries, and since S363 ONLY
/// that. §21.1 says in the same document „TTL expiry (**14 d default**,
/// **31 d for management types**)" — those are [kNormalKeepEpochs] and
/// [kManagementKeepEpochs], two retention periods, not
/// subscription depths. Both
/// sentences are normative, and together they yield a cell that lies for 31 days
/// and is no longer asked after 3. That is no room for
/// interpretation but a contradiction IN the document; it is resolved
/// here in favour of §21.1 and the owner's promise („survive at least 31 days
/// offline") — on explicit approval of the owner
/// (2026-09-02, „follow the recommendation (B+C)").
///
/// **The architecture document is NOT changed in the process** (work rule
/// 4). Adjusting the number in §22.4.1 is an editorial task
/// of the owner and stands open as such.
///
/// ── TWO RANKS, BECAUSE ONE POINTER PUNISHES THE FREQUENT CASE ─────────
///
/// Both conceivable constructions cost **zero** on the wire: it stays at one
/// family per run on a previous epoch, i.e. at [kMaxRealHarvestTags] = 6
/// real tags and one frame per counterpart. The decision was made by
/// LATENCY, calculated with [kFamilies] = 3, [kHarvestEpochs] = 3,
/// [kManagementKeepEpochs] = 31:
///
///   * **One pointer, period 31.** Positions `familien x (tiefe - 1)`
///     = 3 x 30 = **90 visits** per counterpart for a full cycle.
///     The two backlogs under which an ORDINARY
///     cell can lie at all (1 and 2 — further back `expire` has deleted it at
///     `keepEpochs` = 3) are 2 of 90 positions in it instead of
///     2 of 6 so far. The frequent case — a node that missed an
///     epoch boundary — thus waits **15 times longer**,
///     so that the rare one is served at all. 28 of the 30 positions
///     query epochs in which an ordinary cell provably no longer
///     lies.
///   * **Two ranks, interleaved** (built). Even runs sample
///     SHALLOW (backlogs `1 .. epochen-1`, `familien x (epochen-1)` = 6
///     positions), odd ones DEEP (backlogs `epochen .. tiefe-1`,
///     `familien x (tiefe - epochen)` = 3 x 28 = 84 positions). The
///     shallow cycle is through after **12 visits** instead of 6, the
///     deep one after 168 — but DEEP ordered EPOCH-MAJOR, so that every
///     deep backlog is asked at least once (on
///     one family) after **56 visits**. Since storing puts the same content under
///     ALL `m` family tags (§9.2), one suffices.
///
/// Measured in seconds, with one visit per counterpart every
/// `ceil(N / 3) x 32 s` (three frames per run, [kMaxRealHarvestTags]
/// covers one counterpart): at N = 20 contacts a visit is every 224 s.
/// Shallow cycle 12 x 224 s = **45 min**, deep epoch coverage
/// 56 x 224 s = **3.5 h**, all 84 combinations 168 x 224 s = 10.5 h.
/// The one pointer with period 31 would have set the shallow case to
/// 90 x 224 s = 5.6 h.
///
/// **The 3.5 h are the reason why the rotation alone is not enough.**
/// The edge against them is the catch-up harvest in `V41Node.nachholErnte`
/// (variant C): it only happens at an away-return event
/// (network change, return to foreground) and only after measured
/// absence, and it asks one family PER BACKLOG — six
/// backlogs in one frame instead of two.
///
/// [epochs] = 1 switches off BOTH ranks (all families on
/// [currentEpoch]) — the version before S361. [depth] <= [epochs] switches
/// off only the deep rank — the version between S361 and this
/// change. Both are reverse tests of the guard
/// (`smoke_v41_harvest_epoch_depth.dart`).
List<int> harvestEpochsPlan({
  required int currentEpoch,
  required int run,
  int families = kFamilies,
  int epochs = kHarvestEpochs,
  int depth = kManagementKeepEpochs,
}) {
  if (families <= 0) return const <int>[];
  final plan = List<int>.filled(families, currentEpoch);
  if (epochs <= 1) return plan;
  final flat = epochs - 1;
  final deep = depth > epochs ? depth - epochs : 0;
  // Negative counters cannot exist, but a `%` on such a one
  // yields non-negative in Dart anyway — it stands here so that the index
  // does not fall out of the list with a future caller either.
  final n = run.abs();
  if (deep == 0) {
    final i = n.remainder(families * flat);
    plan[i ~/ flat] = currentEpoch - (1 + (i % flat));
    return plan;
  }
  if (n.isEven) {
    // SHALLOW RANK — family-major, so that both near backlogs come up
    // early (run 0 -> backlog 1, run 2 -> backlog 2).
    final i = (n ~/ 2).remainder(families * flat);
    plan[i ~/ flat] = currentEpoch - (1 + (i % flat));
    return plan;
  }
  // DEEP RANK — EPOCH-MAJOR, and that is the decision that separates the
  // 3.5 h above from 10.5 h: first every backlog once (on
  // family 0), then the same pass on family 1 and 2. Family-major
  // would have asked the same epoch on changing families for 28 visits
  // — redundancy that storing already carries anyway.
  final i = (n ~/ 2).remainder(families * deep);
  plan[i ~/ deep] = currentEpoch - (epochs + (i % deep));
  return plan;
}

/// A harvest frame after bundling: ONE relay, the tags for it.
///
/// [relay] and [marks] are INDICES into the lists the caller
/// handed in — this file knows neither nodes nor tags, only
/// their admissibility relation. That is the same layout as with
/// `closestTo` in `responsibility.dart`, and for the same reason: that way
/// the rule can be checked without building a network.
typedef HarvestBundle = ({int relay, List<int> marks});

/// Puts all tags that THE SAME relay can serve into ONE frame.
///
/// ── THE FINDING THAT MAKES THIS NECESSARY (S358) ──────────────────────────
///
/// Until S358 the harvest built a separate request per family with ONE
/// real tag. A contact thus cost `kFamilies` = 3 frames, and
/// the run is capped at `kHarvestRequestsPerRun` = 3 frames (the
/// cap is derived from the outflow: `harvestEverySlots` = 4 slots
/// of 8 s let 4 frames flow out). **A run therefore covered exactly
/// ONE contact**, a run happens every 32 s — with N contacts
/// a specific one waited up to `32 x N` seconds for its query.
/// `v41_node.dart` has noted this itself since S355: „if a
/// COLD contact writes for the first time, it waits further up to 32*N seconds.
/// Only putting several tags into ONE control frame helps against that."
///
/// ── WHY THIS WORKS WITHOUT A WIRE CHANGE ───────────────────────────────
///
/// `buildHarvestRequest` has always accepted `1..255` tags (the limit is
/// the cell size, [kMaxRealHarvestTags] = 6 real ones), and the
/// RELAY SIDE answers them too: `DeliveryNode` calls
/// `store.harvest(anfrage.tags, …)` over ALL tags and sends back per
/// hit a separate `harvestResponse` with the same identifier.
/// The return path withstands that — `PendingRequests.peekRoute` does NOT CONSUME
/// the identifier (in contrast to `takeRoute` for the
/// storing receipt), it is explicitly „only look … for
/// multi-part answers". So only the
/// ASKING SIDE had to be built.
///
/// ── WHAT IS DELIBERATELY NOT BUNDLED: SEVERAL CONTACTS ──────────────
///
/// A request carries ONE identifier, and the answer carries only this
/// identifier — not the tag under which the hit lay. `V41Node._geerntet`
/// looks up the counterpart from it in `_anfragePeer` and passes it on as
/// SENDER (`_geerntetVon` -> `_anbieten` -> `acceptSealed(peer:
/// …)`). Exactly this information is path A (S352): the sender is fixed
/// BECAUSE the tag cannot be computed without `K_AB` — it has replaced the
/// sender signature (B-20).
///
/// If one bundled the tags of TWO contacts into one request, the
/// proof would become a guess: the returning cell belongs to ONE
/// of the two, and which one is stated nowhere. That is not an inaccuracy
/// in the display but a wrongly attributed sender identity.
/// It would only work if the ANSWER carried the tag along — a change to the
/// answer format that is presented to the owner and not built on the
/// side.
///
/// What is bundled is therefore the lines of ONE contact: `kFamilies`
/// message tags and `kFamilies` signal tags. That is 6 and thus
/// exactly [kMaxRealHarvestTags].
///
/// ── THE ROTATION IS PRESERVED ─────────────────────────────────────
///
/// S353 put the harvest on ONE relay per family and let the selection
/// move round-robin ([offset]), so that over `|Menge|` runs every
/// responsible relay is asked once. This property would have been destroyed by a
/// greedy „take the relay that covers the most": it would
/// always choose the same node. That is why the pointer here moves over
/// the CANDIDATE LIST, and in every round the relay at the position
/// of the pointer is taken — what it can serve goes into its frame,
/// the rest goes into the next round.
///
/// [relayForMark] gives per tag the indices of the relays that are
/// responsible for it. Tags for which no candidate is responsible occur
/// in no bundle — the caller sees that from the sum.
List<HarvestBundle> bundleHarvest({
  required List<List<int>> relayForMark,
  required int relayCount,
  required int offset,
  int maxMarksProFrame = kMaxRealHarvestTags,
}) {
  final out = <HarvestBundle>[];
  if (relayCount <= 0 || maxMarksProFrame <= 0) return out;
  final open = <int>{
    for (var i = 0; i < relayForMark.length; i++) i,
  };
  final from = offset % relayCount;
  // SEVERAL ROUNDS, BECAUSE ONE NEED NOT SUFFICE. The cap
  // [maxMarkenProRahmen] can force more frames than there are candidates
  // — six tags with five relays and one tag per frame
  // would need six. A single rotation would have SILENTLY dropped the sixth;
  // in regular operation that is not noticeable (6 tags fit
  // into one frame), but a silent loss is exactly the class of
  // defect that has cost this layer weeks twice.
  //
  // Aborting happens as soon as a whole round assigns NOTHING any more — then
  // the remaining tags have no responsible relay among the
  // candidates, and further rounds change nothing about that.
  while (open.isNotEmpty) {
    var assigned = 0;
    for (var s = 0; s < relayCount && open.isNotEmpty; s++) {
      final r = (from + s) % relayCount;
      final matching = <int>[];
      for (final m in open) {
        if (matching.length >= maxMarksProFrame) break;
        if (relayForMark[m].contains(r)) matching.add(m);
      }
      if (matching.isEmpty) continue;
      open.removeAll(matching);
      out.add((relay: r, marks: matching));
      assigned += matching.length;
    }
    if (assigned == 0) break;
  }
  return out;
}

/// How long a retention bucket is.
///
/// ── BUCKET, NOT A SECONDS STAMP (owner decision 2026-08-31) ────────
///
/// The epoch stays at 24 h (E-J) — it is the clock of the tag line and
/// is not touched by this period. For a 120-s period it is
/// however unusably coarse, and a second-precise stamp would be the other
/// extreme: §23.7 explicitly records that „a stored cell dates to
/// one day, not finer" — a cell that carries its storing second is
/// a fingerprint towards the holding relay.
///
/// A bucket of 120 s is as coarse as the period itself and therefore reveals
/// nothing the period would not reveal anyway.
///
/// **THE BUCKET IS STAMPED BY THE RELAY, not by the sender.** Otherwise
/// it would be choosable: a sender could claim a bucket in the future
/// and let its signal cell lie on foreign relays for an arbitrarily long
/// time — the same class of lever for which `SecureStore.place`
/// already does not take the epoch from the one storing.
const int kRetentionBucketSeconds = 120;

/// Over how many buckets a signal cell is held.
///
/// ── TWO, AND WHY NOT ONE ──────────────────────────────────────
///
/// One bucket sounds right and is wrong. The cell arrives at an
/// arbitrary point WITHIN a bucket; if it falls at its end, it
/// hardly lives any more. Calculated (uniformly distributed arrival in the bucket,
/// `x ∈ [0, 120)`, expiry at `Eimer + 1`):
///
///   lifetime = 120 − x   ->   min → 0 s, mean 60 s, max 120 s
///
/// §17.2 however demands the opposite of an upper bound: „the 120 s
/// TTL **must exceed** the recipient's harvest interval". The harvest cycle
/// is 32 s (`harvestEverySlots` = 4 slots of 8 s), and
/// `P(Lebensdauer < 32 s) = 32/120 = 26,7 %` — every fourth INVITE would have
/// expired before the next harvest of the receiver. The owner
/// said on this: „Loss is not acceptable."
///
/// With TWO buckets (expiry at `Eimer + 2`):
///
///   lifetime = 240 − x   ->   min > 120 s, mean 180 s, max 240 s
///
/// The 120 s from §17.2 are thus a LOWER bound, as the text
/// demands, and the price of the coarseness is capped: at most 240 s
/// instead of 120 s, against the [kNormalKeepEpochs] = 14 days of the
/// ordinary class (until S363: 3 days — the comparison stood back then
/// against those 3). That is the same construction as every epoch period: it
/// guarantees `n - 1` full units and costs up to `n`.
///
/// **RE-MEASURED**, not calculated (`smoke_v41_signal_line.dart`,
/// section 6, 2026-08-31): distributed over 120 arrival seconds —
///
///   min 121 s, mean 180,5 s, max 240 s
///
/// — against 259 200 s (3 days) before S358.
const int kSignalKeepBuckets = 2;

/// How many node epochs a cell of the management class lies.
///
/// **31 epochs of [kEpochSeconds] = 86 400 s each, i.e. 31 days** —
/// owner decision of 01.09.2026: „the recovery phrase must survive at least 31
/// days offline …", and §21.1 lists the same number as „31 d
/// for management types". The complete reasoning including the limit
/// that this constant can NOT heal (mobile relays, §21.3.3, 48 h)
/// is at [kRetentionManagement].
///
/// FROM ARRIVAL, not from the creation of the phrase — the owner's
/// addition, „not from creation, that would be pointless anyway". The epoch
/// is stamped by the holding relay, as with every other class
/// too; a sender cannot extend its period.
const int kManagementKeepEpochs = 31;

/// The bucket into which a point in time falls.
int retentionBucket(DateTime utc) =>
    (utc.toUtc().millisecondsSinceEpoch ~/ 1000) ~/ kRetentionBucketSeconds;

/// What a relay holds under a tag.
final class StoredCell {
  final Uint8List tag;
  final Uint8List cell;
  final int epoch;

  /// Arrival number in the store — the FINE clock next to the coarse one.
  ///
  /// The epoch measures 24 h (E-J). If one evicted by it alone, a
  /// tag line that an attacker filled this morning would find
  /// no victim in the afternoon: everything is equally old, and the real message
  /// would stay out. Within an epoch therefore whoever was there
  /// first decides.
  final int seq;

  /// The retention class from the seal of the stored item
  /// ([kRetentionNormal]/[kRetentionSignal]).
  final int retention;

  /// The bucket of ARRIVAL ([retentionBucket]), stamped by the holding relay.
  /// It only has an effect with [kRetentionSignal].
  final int bucket;

  StoredCell(this.tag, this.cell, this.epoch,
      [this.seq = 0, this.retention = kRetentionNormal, this.bucket = 0]);
}

/// Total byte cap of the delivery storage on mobile nodes (§21.3.1/
/// §21.3.3, owner decision 02.09.2026: option C from
/// `docs/v4-redesign/S361-VORLAGE-mobilfrist-21-3-3.md`).
///
/// §21.3.3 point 1 demands verbatim ONE double rule — 48 h period AND
/// 32 MB cap, whichever binds first. Option C builds only the second half:
/// the 48-h period stays unbuilt (recalculated in the proposal,
/// section 3.1: under today's constants `R_cover`/`m`/`R` it can
/// never bind at 48 h anyway, while the cap under load BY ITSELF
/// produces an effective period of ~2.4 d — the cheaper half
/// of the same rule). All three periods ([kNormalKeepEpochs],
/// [kSignalKeepBuckets]/[kRetentionBucketSeconds], [kManagementKeepEpochs])
/// are platform-independent — the cap joins them, it does not take their
/// place.
///
/// **S363, D2:** the first of these three stood here until then as
/// [kHarvestEpochs] = 3 and is now [kNormalKeepEpochs] = 14. That
/// „on mobile nodes the cap binds and the period therefore does not matter"
/// does **not** hold — this cap only binds above 2.29 MB/day
/// inflow, and §21.3.2 expects of a mobile background node only
/// „single-digit MB per 48 h". The full calculation is at
/// [kNormalKeepEpochs], measured in
/// `smoke_v41_inhaltsfrist_14_tage.dart` section 8c.
const int kMobileSecureStoreCapBytes = 32 * 1024 * 1024;

/// Approximate storage price of a held entry in bytes:
/// frame + tag, plus the same ~24-B bookkeeping flat rate (epoch, seq,
/// class) with which [BlindStore] already computes its entry price (see
/// the calculation at [kBlindHoldTotal]). The proposal arrives above that at
/// ~1225 B/entry — here real from `cell`/`tag` instead of assumed.
int _entryBytes(StoredCell c) => c.cell.length + c.tag.length + 24;

/// The store of a responsible relay.
///
/// Deliberately plain: tags on cells, expiry by epochs. The
/// eviction is quota-based (§22.4.1) and explicitly WITHOUT a
/// PoW price curve — that was dropped with the field model.
final class SecureStore {
  final int keepEpochs;
  final int maxCellsPerTag;

  /// Total byte cap over ALL tag lines. `< 0` = unlimited (desktop,
  /// today's behaviour — default value, so that no existing caller
  /// changes). Mobile nodes pass [kMobileSecureStoreCapBytes]
  /// through (`V41Node.start` -> `DeliveryNode` -> here).
  final int maxTotalBytes;

  final Map<String, List<StoredCell>> _byTag = <String, List<StoredCell>>{};

  /// [keepEpochs] is the period of the ORDINARY class and therefore defaults to
  /// [kNormalKeepEpochs] = 14, not to [kHarvestEpochs] = 3.
  /// Until S363 [kHarvestEpochs] stood here — the subscription depth from
  /// §22.4.1 —, and because `DeliveryNode` builds the store without this
  /// parameter (`delivery_node.dart`), the retention in
  /// operation was three instead of fourteen days. The two quantities have since been
  /// separated; the derivation of the 14 is at [kNormalKeepEpochs].
  SecureStore(
      {this.keepEpochs = kNormalKeepEpochs,
      this.maxCellsPerTag = 32,
      this.maxTotalBytes = -1});

  String _k(Uint8List tag) =>
      tag.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Arrival counter over all tag lines. It only needs to be MONOTONIC, not
  /// dense — comparisons always happen within one list.
  int _seq = 0;

  /// How often this store has evicted under quota pressure.
  ///
  /// §21.3.3 no. 4: „a node that evicts under budget pressure shows this
  /// visibly in the network statistics (§25). A silently shrinking
  /// delivery layer is the storage variant of the failure mode §1.2 rules
  /// out for delivery." The number is the carrier for that; who displays it
  /// is decided by the level above.
  int evicted = 0;

  /// Stores a cell. `false` if it was not taken in.
  ///
  /// ── EVICT INSTEAD OF REJECT (§20) ─────────────────────────────────
  ///
  /// The spec is unambiguous: „What bounds a tag line is its **own** quota:
  /// eviction happens **only within** the quota, never across it […]
  /// Within the quota, the oldest/near-expiry cells go first."
  ///
  /// Until S351 this said `if (list.length >= maxCellsPerTag) return false`
  /// — that is the reverse order: the YOUNGEST went first,
  /// and the oldest stayed until its expiry. The consequence was
  /// saturation: whoever fills a computable tag line with `maxCellsPerTag`
  /// cells and refills before expiry keeps every real
  /// message out permanently. One filling per epoch sufficed.
  ///
  /// WHY THIS OPENS NO NEW ATTACK SURFACE. Evicting means that
  /// someone storing can make foreign cells of THE SAME tag line get lost.
  /// §20 weighs exactly that and calls it „the R-11 eviction
  /// surface": a computable tag line is an affordable target, and
  /// the answer to that is quota isolation, not rejection. A
  /// Secure tag cannot be computed without `K_AB` (§10.1, KEX gate) —
  /// whoever has it is the conversation partner. And eviction never
  /// reaches beyond the tag line: the list is per tag.
  ///
  /// THE EXCEPTION. If the incoming cell were itself the oldest, it
  /// would be its own next victim. Taking it in first and throwing
  /// a younger one for it costs a foreign cell without any
  /// gain — then it is rejected. In operation that is not a normal case:
  /// `DeliveryNode` stamps `epochNow()`, so the epoch is not choosable by the
  /// one storing. The check is the safeguard against
  /// a later caller making it choosable.
  /// [retention] and [bucket] carry the second period (§17.2, S358).
  /// [bucket] is the bucket of ARRIVAL and is stamped by the holding relay
  /// ([retentionBucket]) — never by the one storing, for the same
  /// reason for which the epoch is not choosable here either.
  bool place(Uint8List tag, Uint8List cell, int epoch,
      {int retention = kRetentionNormal, int bucket = 0}) {
    final list = _byTag.putIfAbsent(_k(tag), () => <StoredCell>[]);
    if (list.length >= maxCellsPerTag) {
      var victim = 0;
      for (var i = 1; i < list.length; i++) {
        if (_olderAs(list[i], list[victim])) victim = i;
      }
      if (epoch < list[victim].epoch) return false;
      list.removeAt(victim);
      evicted++;
    }
    final fresh = StoredCell(tag, cell, epoch, _seq++, retention, bucket);
    // ── THE TOTAL CAP (§21.3.3, option C) ─────────────────────────
    //
    // Only acts if [maxTotalBytes] is set (mobile). Eviction happens
    // ACROSS ALL tag lines, but CLASS-PRIORITISED: first
    // [kRetentionNormal] (oldest first), then [kRetentionSignal],
    // [kRetentionManagement] last — [_niedrigererRang] exploits for this
    // that the three constants are already numbered in exactly this
    // order. A pure oldest-first eviction over all
    // classes would hit the management cells first — they are by
    // construction the oldest (31 d period) —, and the 31-day promise
    // would be silently dead through the back door of the cap. Exactly that is what
    // this order is meant to prevent.
    if (maxTotalBytes >= 0) {
      final newBytes = _entryBytes(fresh);
      while (totalBytes + newBytes > maxTotalBytes) {
        final victim = _capVictim();
        if (victim == null) break; // storage empty, cap < one entry
        _byTag[victim.$1]!.removeAt(victim.$2);
        evicted++;
      }
    }
    list.add(fresh);
    return true;
  }

  /// The next eviction candidate under the total cap: lowest
  /// [StoredCell.retention] first, on a tie [_olderAs]. `null`
  /// if nothing is held. Empty lists stay — they are
  /// cleared in the next [expire] — instead of removing them here, which
  /// would orphan the `list` reference in [place] for the tag currently
  /// being processed.
  (String, int)? _capVictim() {
    String? bestTag;
    int bestIndex = -1;
    StoredCell? best;
    for (final entry in _byTag.entries) {
      for (var i = 0; i < entry.value.length; i++) {
        final c = entry.value[i];
        if (best == null || _lowerRank(c, best)) {
          best = c;
          bestTag = entry.key;
          bestIndex = i;
        }
      }
    }
    return best == null ? null : (bestTag!, bestIndex);
  }

  /// `true` if [a] should be evicted before [b]: lower
  /// [StoredCell.retention] first (normal 0 < signal 1 < management 2 —
  /// exactly the demanded class order), on a tie [_olderAs].
  static bool _lowerRank(StoredCell a, StoredCell b) =>
      a.retention != b.retention
          ? a.retention < b.retention
          : _olderAs(a, b);

  /// Held bytes over all tag lines — a pure read value like
  /// [cellCount], only in bytes instead of cells.
  int get totalBytes => _byTag.values
      .fold<int>(0, (a, l) => a + l.fold(0, (b, c) => b + _entryBytes(c)));

  /// Who goes first: the older epoch, on a tie the earlier
  /// arrival. „oldest/near-expiry first" (§20) — expiry hangs on the
  /// epoch, so it is the first criterion.
  static bool _olderAs(StoredCell a, StoredCell b) =>
      a.epoch != b.epoch ? a.epoch < b.epoch : a.seq < b.seq;

  /// Answers a harvest query.
  ///
  /// The relay does not distinguish real tags from decoys — it cannot,
  /// and exactly on that the masking rests.
  ///
  /// [exclude] is the have list of the asker (B-32): tags of cells
  /// it already has completely. They are NOT deleted — §14.2
  /// lets all devices of an identity harvest the same tag line, and
  /// the second device declares nothing and gets everything. They are only
  /// not sent again to **this** asker.
  ///
  /// The relay remembers nothing in the process: the list applies to exactly this
  /// request. No state per collector arises and thus no
  /// identifier of a collector recognisable across rounds.
  List<StoredCell> harvest(List<Uint8List> tags,
      {Iterable<Uint8List> exclude = const <Uint8List>[]}) {
    // EACH TAG ONLY ONCE. A query set may contain the same tag twice
    // — the decoys are mixed in, and a decoy can
    // coincide by chance with a real tag. Without this
    // sorting out the relay answers the same cell several times: that
    // costs bandwidth and delivers duplicates to the asker, which its
    // assembler must discard as pieces in the wrong place.
    final seen = <String>{};
    final already = <String>{for (final m in exclude) _k(m)};
    final out = <StoredCell>[];
    for (final t in tags) {
      if (!seen.add(_k(t))) continue;
      for (final c in _byTag[_k(t)] ?? const <StoredCell>[]) {
        // THE TAG IS COMPUTED HERE, not carried along: a cell
        // arrives under m=3 family tags with IDENTICAL content, and
        // exactly for that reason the tag is content-based — otherwise
        // the same message would appear three times differently.
        if (already.contains(_k(cellDigest(c.cell)))) continue;
        out.add(c);
      }
    }
    return out;
  }

  /// Throws off what has exceeded its period.
  ///
  /// ── TWO CLASSES, TWO CLOCKS (§17.2, S358) ──────────────────────────
  ///
  /// [kRetentionNormal] falls after [keepEpochs] node epochs — 24 h per
  /// epoch (E-J), i.e. [kNormalKeepEpochs] = **14 days** (§21.1 „14 d
  /// default"; until S363 it was 3, because `keepEpochs` defaulted to the
  /// subscription depth [kHarvestEpochs]). Until S358 that was
  /// the period FOR EVERYTHING, and thus the sentence from §17.2 did not apply: „an
  /// INVITE cannot ring days later". It applies now.
  ///
  /// [kRetentionSignal] falls after [kSignalKeepBuckets] buckets of
  /// [kRetentionBucketSeconds] seconds each — guaranteed more than 120 s,
  /// at most 240 s. The calculation for it is at [kSignalKeepBuckets].
  ///
  /// [currentBucket] is MANDATORY and has no default: a default
  /// zero would have silently left signal cells with the LONG period in every caller that forgets it
  /// — the bug would have stayed invisible,
  /// because a cell lying too long behaves exactly like a
  /// correct one, only longer. When updating the callers, the
  /// compiler instead reports all of them.
  int expire(int currentEpoch, int currentBucket) {
    var removed = 0;
    for (final entry in _byTag.entries.toList()) {
      entry.value.removeWhere((c) {
        final old = switch (c.retention) {
          kRetentionSignal => c.bucket <= currentBucket - kSignalKeepBuckets,
          kRetentionManagement =>
            c.epoch <= currentEpoch - kManagementKeepEpochs,
          _ => c.epoch <= currentEpoch - keepEpochs,
        };
        if (old) removed++;
        return old;
      });
      if (entry.value.isEmpty) _byTag.remove(entry.key);
    }
    return removed;
  }

  int get cellCount =>
      _byTag.values.fold<int>(0, (a, l) => a + l.length);
}

// ─────────────────────────────────────────────────────────────────────────
// THE BLIND STORING AT THE LOCAL MINIMUM (§11.2, path a)
// ─────────────────────────────────────────────────────────────────────────
//
// THE SPEC. §11.2: „The path is greedy. A relay that is not the target
// hands the cell to the partner nearer the target than itself; a relay
// that knows no nearer partner is **the local minimum and stores rather
// than dropping** — a target nobody knows is better kept at its nearest
// neighbour than nowhere."
//
// WHY THIS RULE HAS NO LONGER BEEN EXECUTABLE SINCE IP-1. Since IP-1
// a stored item is sealed to the TARGET key (`buildPlace`): tag and
// content lie under `AEAD(HKDF(X25519(eph, ziel_pk), ziel))`. The
// local minimum is by precondition NOT the target — `openPlace`
// returns `null` to it, and with `null` there is neither tag nor cell under
// which something could be stored. The code therefore did exactly what the
// comment next to it excluded: it discarded.
//
// Measured on 2026-08-29 (three nodes, one process):
//   d(X,P) < d(A,P) = true      -> X is the local minimum
//   nextHopToward(P) at X = null
//   `openPlace(frame, X_sk)` = null
//   Action of X: "Ablage nicht zu oeffnen", X.store.cellCount = 0
//
// WHAT A LOCAL MINIMUM SEES AT ALL — and thus the upper limit
// of what a quota can measure here. `parseSecureFrame` hands out for
// `SecureOp.place` exactly three things: the remaining hops,
// the TARGET (32 B, plaintext in the header) and the unchanged frame. Not
// the tag, not the content, not the period, not the sender. A
// quota can thus only rely on the TARGET MARK, the DELIVERING PARTNER
// and the total number. Exactly these three are drawn on by [BlindStore].
//
// HOW THE CELL FINDS ITS WAY OUT AGAIN — and why that is NOT a harvest.
// The cell is sealed to the target. Neither the blind holder nor a
// harvesting receiver can open it; putting it on a harvest answer
// for an asker would give him bytes he must throw away. The
// blind storing is therefore not a mailbox but a RESUBMISSION: it
// lies separate from the tag store (that one is indexed by tags, this one
// by target marks — a blind cell cannot hit a harvest at all)
// and is forwarded again as soon as the node gets a partner
// that lies nearer to the target than itself. In the limiting case that is
// the target itself: then it opens the stored item, stores it under its tag,
// and the ordinary harvest finds it there. Until then it is
// "kept at its nearest neighbour" — exactly what the spec demands.
//
// THE PRICE, CALCULATED.
//   One entry: frame <= 1169 B (`kPlaceSealOffset` 78 + class 1 +
//   tag 32 + content <= `kMaxPlaceContentBytes` 1042 + AEAD 16)
//   + target mark 32 B +
//   three numbers ~ 24 B  =  ~1225 B, rounded 1.2 KB.
//   Total 64 entries  ->  ~78.4 KB.
//     = 0.23 % of the 32-MB cap of a mobile node (§21.3.1)
//     = 0.05 % of the ~160 MB of a desktop node
//   Per partner 16          ->  ~19.6 KB per session.
//   Per target mark 8       ->  ~9.8 KB.
//
// WHY THESE THREE NUMBERS.
//   * 64 total: a Secure message is split into cells of <= 1043 B
//     (§15.4) and stored m=3-fold; the 3315-B answer from S349 is four
//     cells, i.e. twelve stored items. 64 holds five such messages or
//     a whole `m x R = 60` storing batch (§9.2/§11.2) — and more buys
//     nothing, because the blind storing is a buffer against a routing pathology
//     and not a mailbox.
//   * 16 per partner: that is the BINDING limit against abuse. The
//     target mark stands in plaintext and can be freely invented — a quota per
//     target mark alone could be bypassed by varying the field. A
//     SESSION on the other hand costs a handshake. 16 >= 12 leaves a
//     neighbour one whole message, no more.
//   * 8 per target mark: fairness among honest, simultaneously unreachable
//     targets — one mark must not fill the total stock alone.
//
// WHAT HAPPENS UNDER PRESSURE. If the quota per partner or per target mark
// is exhausted, it is REJECTED — otherwise pushing more would be a lever with which
// someone delivering evicts his own older entries (or those of another).
// If only the TOTAL number is exhausted, eviction happens per §20:
// the oldest first. That is the same rule as in the tag store and for
// the same reason — otherwise a one-time rush would lock the stock until
// expiry.
//
// OWN CLASS, OWN CAP. §21.3.3 no. 2: „Delivery layer, durable
// objects, media archive, and bulk stand side by side; no class draws on
// another." The blind storing takes nothing from the tag store and the
// tag store nothing from it.

/// Is a harvest run due now, or is it paused? (§9.2, S355)
///
/// Pure, so that the rule is a GATE and not a note. Two quantities
/// stand against each other:
///
/// - **The queue.** A request that waits behind thirty stored items
///   gets its answer four minutes later — it costs more than it
///   yields. That is why the run pauses when more than [limit]
///   control frames are pending.
/// - **The dark time.** If it pauses INDEFINITELY for that reason, the
///   node stops receiving as long as it sends. Exactly that was measured in the field
///   on 30.08.: in fifteen minutes with twelve
///   messages one node made 3 requests, the other 0 — of
///   twelve messages 1 and 2 arrived.
///
/// After [atMostSkips] skipped runs one therefore goes
/// out without looking at the queue.
bool harvestRunDue({
  required int waitingFrame,
  required int limit,
  required int suspended,
  required int atMostSkips,
}) =>
    waitingFrame < limit || suspended >= atMostSkips;

/// How many requests this harvest run may make at most (S374).
///
/// It stands as a PURE FUNCTION next to [harvestRunDue], for the same
/// reason as that one: the decision should be checkable and not only
/// commented. The two belong together — `ernteLaufFaellig` says
/// WHETHER a run goes, this one says HOW LARGE it may then be.
///
/// ── THE CASE IT CATCHES (measured in the field on 07.09.2026) ─────────
///
/// `ernteLaufFaellig` lets a run through after `hoechstensAussetzen` pauses,
/// EVEN if the queue is still above the limit —
/// „pausing yes, stopping no". Against a TEMPORARY
/// backlog that is right. Against a STANDING one it reverses:
/// the run then went in with the full cap and pushed the queue
/// further up.
///
/// Measured on .201 (two identities): harvest rounds every ~31 s of
/// 6 requests each against 4 frames that flow out between two runs;
/// control queue 120/120, discarded 180 and rising. The full
/// cap `kHarvestRequestsPerRun` = 3 holds per CALL (3 < 4) — the
/// outflow however belongs to the NODE, and two identities are two
/// calls against the same cover stream.
///
/// The forced run is meant to PREVENT STARVATION, not to produce
/// throughput. For that [forcedCap] suffices.
int harvestCap({
  required int waitingFrame,
  required int limit,
  required int fullCap,
  required int forcedCap,
}) =>
    waitingFrame >= limit ? forcedCap : fullCap;

/// How many blindly held deposits a node keeps in total.
const int kBlindHoldTotal = 64;

/// How many of them may fall on the same target mark.
const int kBlindHoldPerTarget = 8;

/// How many of them may come from the same session.
const int kBlindHoldPerPartner = 16;

/// After how many node epochs a BLINDLY held entry falls.
///
/// **Three — and since S363 that is a number of its own, no longer that of the
/// tag store.** Until then [kHarvestEpochs] stood here, with the
/// reasoning „the same period as in the tag store". This reasoning
/// has become moot with the separation of subscription depth and retention:
/// the tag store now holds
/// [kNormalKeepEpochs] = 14, and the harvest depth is not a period.
/// Had it stayed at [kHarvestEpochs], the same number would carry two
/// quantities again — exactly the bug that S363 closed.
///
/// **Why 3 and not 14.** The blind storing is not a delivery path
/// but a resubmission at the local minimum (§11.2, path a): the
/// entry is FORWARDED as soon as a nearer neighbour becomes known,
/// and never harvested. What has not found a nearer
/// neighbour for three epochs will not find one any more — the period measures
/// here the prospect of a better neighbour, not the time
/// a receiver may be offline. [kNormalKeepEpochs] is only
/// the UPPER bound for that (an entry that lay longer than the cell at the
/// target costs storage for a delivery that no longer exists),
/// and 3 <= 14 respects it.
///
/// **Measured what the number can bind at all:** the blind storing
/// is capped at [kBlindHoldTotal] = 64 entries, with
/// [kBlindHoldPerTarget] = 8 and [kBlindHoldPerPartner] = 16 below that.
/// Under load the count binds, not the epoch; the period clears
/// idle time. Raising it to 14 would therefore buy nothing and would
/// only hold longer what is evicted anyway.
const int kBlindHoldKeepEpochs = 3;

/// A stored item that this relay holds without being able to open it.
final class BlindHeld {
  /// The target mark from the header — the ONLY thing by which ordering is
  /// possible here.
  final Uint8List target;

  /// The unchanged `place` frame. It is later forwarded with one hop
  /// fewer; nothing else is changed about it, because
  /// everything except the header is sealed.
  final Uint8List frame;

  /// Which session it came from — carrier of the partner quota.
  final int fromPartner;

  /// The node epoch of arrival (`epochNow()`), carrier of the period.
  final int epoch;

  /// Arrival number, as with [StoredCell]: the fine clock.
  final int seq;

  BlindHeld(this.target, this.frame, this.fromPartner, this.epoch, this.seq);
}

/// The stock of blindly held stored items of a local minimum.
///
/// Deliberately NO copy of [SecureStore]: that one indexes by tags and
/// answers harvests. Here there is no tag to index and nothing to
/// answer — there is a target mark and a resubmission.
final class BlindStore {
  final int maxTotal;
  final int maxPerTarget;
  final int maxPerPartner;

  /// After how many node epochs an entry falls —
  /// [kBlindHoldKeepEpochs], NOT [kNormalKeepEpochs].
  final int keepEpochs;

  BlindStore({
    this.maxTotal = kBlindHoldTotal,
    this.maxPerTarget = kBlindHoldPerTarget,
    this.maxPerPartner = kBlindHoldPerPartner,
    this.keepEpochs = kBlindHoldKeepEpochs,
  });

  /// In arrival order — the oldest in front. Appending preserves it,
  /// removing too; nothing is re-sorted anywhere.
  final List<BlindHeld> _held = <BlindHeld>[];
  int _seq = 0;

  /// How often a stored item was evicted under total pressure (§21.3.3 no. 4).
  int evicted = 0;

  /// How often a stored item was rejected at a partial quota.
  int refused = 0;

  int get count => _held.length;

  /// Snapshot in arrival order. A copy, so that the caller may call
  /// [release] during the pass.
  List<BlindHeld> get holdings => List<BlindHeld>.unmodifiable(_held);

  int countForTarget(Uint8List target) =>
      _held.where((h) => _same(h.target, target)).length;

  int countForPartner(int partner) =>
      _held.where((h) => h.fromPartner == partner).length;

  /// Takes a stored item that cannot be opened into custody.
  ///
  /// `false` if a partial quota rejects it — then it falls, as
  /// before, silently (E-83).
  bool hold(Uint8List target, Uint8List frame, int fromPartner, int epoch) {
    if (target.length != kNodePositionBytes) return false;
    if (countForTarget(target) >= maxPerTarget) {
      refused++;
      return false;
    }
    if (countForPartner(fromPartner) >= maxPerPartner) {
      refused++;
      return false;
    }
    if (_held.length >= maxTotal) {
      // Only TOTAL pressure evicts, and per §20 the oldest first.
      _held.removeAt(0);
      evicted++;
    }
    _held.add(BlindHeld(Uint8List.fromList(target),
        Uint8List.fromList(frame), fromPartner, epoch, _seq++));
    return true;
  }

  /// Takes an entry out — after forwarding or when it
  /// can no longer be forwarded.
  bool release(BlindHeld held) => _held.remove(held);

  /// Throws off what is older than [keepEpochs]. Returns how many.
  int expire(int currentEpoch) {
    final before = _held.length;
    _held.removeWhere((h) => h.epoch <= currentEpoch - keepEpochs);
    return before - _held.length;
  }

  /// Forgets everything from a session that no longer exists.
  ///
  /// An entry carries a PARTNER INDEX, and indices shift when
  /// a session falls. Whoever keeps the quota per partner must move the
  /// bookkeeping along with the sessions, otherwise after the
  /// first departure it computes against a foreign neighbour.
  int dropPartner(int partner) {
    final before = _held.length;
    _held.removeWhere((h) => h.fromPartner == partner);
    return before - _held.length;
  }

  static bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
