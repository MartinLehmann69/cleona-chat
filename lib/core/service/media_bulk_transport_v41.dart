// The holder side of the bulk lane, bound to the V4.1 node (§9.3).
//
// ── WHAT THIS FILE CLOSES ────────────────────────────────────────
//
// Until 02.09.2026 `MediaBulkLane.transport` was `null` in `lib/`, and a
// large media send was therefore REJECTED. The header of
// `media_bulk_transport.dart` and `smoke_bulk_holder_side_guard.dart` have
// measured the gap fourfold: no wire (frame type `0x05` was discarded on
// assignment), no holder (`BulkCache` had no constructor), the wrong
// storage class (`SecureStore.maxCellsPerTag` = 32 versus 47 blocks of the
// smallest transfer) and a blocked send path (1069 B block versus 1042 B
// PLACE content).
//
// All four are closed. This file is the link between them:
//
//   `bulk_frames.dart`      the wire (frame type 0x05, three actions)
//   `bulk_egress.dart`      the SECOND drain on `R_bulk`
//   `DeliveryNode._handleBulk` + `DeliveryNode.bulk`   the holder role
//   THIS FILE               the sender role: whom to ask, where to deposit
//
// ── THREE GATES THAT MUST NOT SOFTEN HERE ────────────────
//
// 1. **EXACTLY one deposit per block.** Not `m x R`. `BulkPlacementPlan
//    .forBlocks` returns exactly as many deposits as there are blocks, and
//    this file does not add a second round. §9.3: "redundancy is
//    the rateless overshoot factor `F`, **not** the `m × R` of §9.2 —
//    per-block `m × R` would cost a factor of **60** on the wire".
// 2. **Bulk NEVER goes via the control queue.** It holds
//    `kMaxControlBacklog` = 120 frames and releases one every 8 s; a
//    5 MB photo is 6348 blocks. Measured, that would be 98.1 % silent
//    loss. This file calls `egress.stream.enqueueControl` nowhere.
// 3. **The cover stream stays untouched** (§9.3: "the cover stream …
//    runs on unchanged beside an active transfer"). The second drain has
//    its own queue, its own timer and touches neither of the two random
//    streams of the cover stream.
//    `smoke_bulk_lane_effect.dart` measures this: same seed, once with and
//    once without a transfer, identical slot sequence and identical cell
//    bytes.
//
// ── WHAT THE SENDER ADDRESSES ────────────────────────────────────────
//
// Not the mark, but its EPOCH LINE `H(mark ‖ e)` — the same quantity that
// §9.1 forms for responsibility anyway. The justification is in the header
// of `bulk_frames.dart`; in short: it costs no additional bytes, it is a
// one-way image of the mark, and sender, holder and receiver compute it
// from the same function.
//
// ── A REPORTED REMAINDER ──────────────────────────────────────────────
//
// §9.3 deposits blocks at **always-on** relays (§22.6, E-53: "Mobile
// nodes hold no bulk"). `EntryRecord` carries no such feature — there is
// no information on the wire today from which a depositor could read the
// budget class of a relay. `BulkPlacementPlan` has the filter
// (`BulkHolder.alwaysOn`), but here it can only be fed with `true`.
// Consequence: if a mobile relay falls into the responsibility set, its
// `BulkCache` (switched off, E-53) does not accept the blocks, and the
// deposits to it are lost. The overshoot factor `F` covers that, but it is
// traffic without value.
// Reported and NOT secretly healed here — the healing would be a field in
// the entry record, i.e. a wire change with anonymity consequences (it
// would say which nodes are desktops), and that belongs before the owner,
// not built on the side.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/bulk/bulk_cache.dart' show BulkCache;
import 'package:cleona/core/bulk/bulk_egress.dart';
import 'package:cleona/core/bulk/bulk_frames.dart';
import 'package:cleona/core/bulk/bulk_placement.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/link/frame.dart' show LinkFrameType;
import 'package:cleona/core/service/media_bulk_lane.dart'
    show BulkPlacementCapacity, BulkScanExhaustion;
import 'package:cleona/core/service/media_bulk_transport.dart';
import 'package:cleona/core/bulk/responsibility.dart'
    show epochFor, kResponsibleRelays, targetFor;
import 'package:cleona/core/tagline/v41_node.dart' show V41Node;

/// The seam between [MediaBulkLane] and the V4.1 node.
final class V41MediaBulkTransport
    implements
        MediaBulkTransport,
        BulkPlacementCapacity,
        BulkScanExhaustion,
        BulkDirectedPlacement {
  final V41Node node;

  /// The second drain. **Not** the cover stream.
  final BulkEgress egress;

  late final BulkDrain drain;

  /// Where scanned blocks are reported.
  void Function(Uint8List tag, List<Uint8List> sealed)? _sink;

  /// Where it is reported that the drain has space again.
  void Function()? _place;

  /// Where it is reported that a scan round came up empty.
  void Function(Uint8List tag)? _empty;

  @override
  set onScanExhausted(void Function(Uint8List tag) sink) => _empty = sink;

  /// How many blocks [placeOnce] accepts NOW without discarding one
  /// (§9.3, [BulkPlacementCapacity]).
  ///
  /// It is the space in the SECOND DRAIN, and that is shared: the scan
  /// requests of the receiving side queue into the same queue. Precisely
  /// for that reason the number is queried here and not computed in the
  /// lane — only this class sees both inflows.
  ///
  /// ── AND THAT IS WHY IT IS SMALLER BY THE RESERVE ─────────────────
  ///
  /// [kBulkEgressScanReserve] stays reserved for scanning; the
  /// justification stands where the cap stands. In short: [scan] queues
  /// into THE SAME queue and checks nothing, and since the pull model the
  /// sending side keeps it full for hours.
  @override
  int get placementCapacity {
    final free = egress.freeSlots - kBulkEgressScanReserve;
    return free < 0 ? 0 : free;
  }

  @override
  set onPlacementCapacity(void Function() sink) => _place = sink;

  /// Which mark belongs to an issued scan identifier.
  ///
  /// **The answer carries the LINE, not the mark** — the holder does not
  /// know the mark, after all. The way back to the mark therefore leads via
  /// this ledger, and that is at the same time the latch: an answer to an
  /// identifier this node never issued finds no mark and is discarded.
  /// Without it a partner could push arbitrary blocks into a foreign
  /// harvest (the seal latch in `BulkReceiver` would catch them, but only
  /// after one decryption per block).
  final Map<String, Uint8List> _scanTags = <String, Uint8List>{};

  /// How often a mark has already been scanned — the offset in the
  /// round-robin over the responsible ones.
  final Map<String, int> _scanRounds = <String, int>{};

  /// From which holder an issued identifier expects an answer.
  ///
  /// The value is `base64(holderposition)|base64(line)` — the key under
  /// which [_scanHop] is kept.
  final Map<String, String> _scanFrom = <String, String>{};

  /// How many entries a holder has already offered under a line — the
  /// `skip` of the next request to IT.
  ///
  /// **Per holder, not per mark.** §9.3 distributes the blocks round-robin
  /// over the responsible ones, so each holds its own subset; a shared
  /// counter would skip the wrong thing at all the others.
  final Map<String, int> _scanHop = <String, int>{};

  /// Which [_scanHop] keys belong to a mark.
  ///
  /// Without this ledger [forgetTag] could not get rid of them again: the
  /// key contains the EPOCH LINE, and a transfer that crosses an epoch
  /// boundary has more than one. From the mark alone they could not be
  /// recomputed without guessing how many epochs it lasted.
  final Map<String, Set<String>> _hopFromMark = <String, Set<String>>{};

  /// How many requests of a mark are still waiting for their round end.
  final Map<String, int> _open = <String, int>{};

  /// How many blocks the running round of a mark has brought.
  final Map<String, int> _yield = <String, int>{};

  /// Has anything come back for this mark at all since the last [scan]
  /// request? The latch against a permanently blocked harvest — see [scan].
  final Map<String, bool> _stir = <String, bool>{};

  /// How many scan rounds this node has started (diagnostics).
  int scanRounds = 0;

  /// How many resubmissions were damped because a round was still running.
  /// A number well above [scanRounds] is the normal case: up to 128 blocks
  /// come back per round, and each one triggers a resubmission.
  int scanSuppressed = 0;

  /// How many deposits this node has held itself because it was
  /// responsible for the line (B-34: costs no cell on the wire).
  int selfHeld = 0;

  /// How many deposits could not be queued at all because no responsible
  /// relay was known.
  int noHolder = 0;

  V41MediaBulkTransport(this.node, {BulkEgress? bulkEgress, void Function(String)? log})
      : egress = bulkEgress ?? BulkEgress() {
    // THE BUILD-TIME PROMISE, REDEEMED HERE. `kBulkFrameFitsCell` says that
    // all three bulk frames fit into ONE cell; without a consumer that
    // would be a constant nobody reads — and exactly this class ("built,
    // never entered") is what `smoke_delivery_layer_unwalked_guard.dart`
    // looks for. The latch stands at the place where the frames come
    // about: whoever changes the block size or a frame header gets the
    // throw here and not only a silently fragmented wire.
    if (!kBulkFrameFitsCell) {
      throw StateError('Bulk frames no longer fit into a cell — '
          'see bulk_frames.dart (block size or frame header changed)');
    }
    // THE PULL (S363): the timer fetches the supply, instead of the sender
    // pushing it in. Without `onRoom` nothing was left of a 200 MB video
    // after the first full drain — `BulkEgress.enqueue` silently discarded
    // 98.4 % (B-1).
    drain = BulkDrain(
        egress: egress, send: _send, log: log, onRoom: () => _place?.call());
  }

  @override
  set onScanned(void Function(Uint8List tag, List<Uint8List> sealed) sink) =>
      _sink = sink;

  /// Accepts an answer that `DeliveryNode` has recognised as "our own".
  ///
  /// Is attached to `DeliveryNode.onBulkScanned` in `attachV41BulkLane`.
  void acceptScanned(Uint8List requestId, Uint8List line, Uint8List sealed) {
    final id = base64.encode(requestId);
    final mark = _scanTags[id];
    // NO MARK, NO BLOCK. See [_scanTags]: an answer to a question never
    // asked is not a find, but an injection.
    if (mark == null) return;
    final markHex = base64.encode(mark);
    _yield[markHex] = (_yield[markHex] ?? 0) + 1;
    _stir[markHex] = true;
    _sink?.call(mark, <Uint8List>[sealed]);
  }

  /// A holder has completed its answer to [requestId].
  ///
  /// ── HERE, AND ONLY HERE, HANGS THE RESUBMISSION ─────────────────
  ///
  /// Not at the block inbound: with [kBulkScanRelaysPerRound] holders of
  /// [kBulkScanResponseLimit] blocks each, that is 128 arrivals per round,
  /// and each would trigger a new round. At the round end it is four
  /// events, and only the last one triggers.
  ///
  /// [count] is how many entries THIS holder has handed out — it moves onto
  /// its `skip`. Without it the next round would get the same entries once
  /// more (`buildBulkScan`, calculation there).
  ///
  /// **The trigger is an empty report to the sink, not a direct call of
  /// [scan].** Only the lane knows the have-list, not this transport; the
  /// lane passes it in at the next [scan]. A round that brought NOTHING
  /// triggers nothing at all — there the chain ends, without clock and
  /// without polling.
  void acceptScanEnd(Uint8List requestId, Uint8List line, int count) {
    final id = base64.encode(requestId);
    final mark = _scanTags[id];
    if (mark == null) return;
    final from = _scanFrom.remove(id);
    if (from != null && count > 0) {
      _scanHop[from] = (_scanHop[from] ?? 0) + count;
    }
    final markHex = base64.encode(mark);
    _stir[markHex] = true;
    final rest = (_open[markHex] ?? 1) - 1;
    _open[markHex] = rest < 0 ? 0 : rest;
    if (rest > 0) return;
    final yieldAmount = _yield.remove(markHex) ?? 0;
    if (yieldAmount == 0) {
      // ── HERE THE HARVEST HANGS (§9.3 "refill", S363) ────────────────
      //
      // A round over [kBulkScanRelaysPerRound] responsible ones has brought
      // not a single block. The chain ends here — without clock, without
      // polling —, and exactly that is the ONLY occasion to request a
      // refill from the sender. Until S363 it ended here SILENTLY: the
      // receiver had no way of telling anyone, and
      // `MediaBulkLane.refillRequestFor` had no caller in `lib/`.
      //
      // Whether a refill request really comes of it is decided by the lane
      // (`MediaBulkLane._harvestHangs`): it knows the progress of the
      // harvest and the cap per transfer. This transport only reports the
      // fact.
      _empty?.call(mark);
      return;
    }
    _sink?.call(mark, const <Uint8List>[]);
  }

  /// Forgets all state for a mark — abort or completion.
  ///
  /// Without this move one entry per holder would remain in [_scanHop]
  /// per completed transfer. For a user who receives a lot, that is a
  /// slow leak.
  void forgetTag(Uint8List tag) {
    final markHex = base64.encode(tag);
    _open.remove(markHex);
    _yield.remove(markHex);
    _stir.remove(markHex);
    _scanRounds.remove(markHex);
    for (final k in _hopFromMark.remove(markHex) ?? const <String>{}) {
      _scanHop.remove(k);
    }
    _scanTags.removeWhere((k, v) {
      if (base64.encode(v) != markHex) return false;
      _scanFrom.remove(k);
      return true;
    });
  }

  /// How many counters this transport currently keeps (diagnostics).
  ///
  /// It stands here because a leak at this place is SLOW: per received
  /// file otherwise as many entries remain as it had holders. A number
  /// that only grows in operation is the finding.
  int get trackedCounters =>
      _scanHop.length + _scanTags.length + _scanFrom.length;

  /// One line for the node's status line.
  String statusLine() => 'Bulk send side: placed self $selfHeld, '
      'without holder $noHolder, rounds $scanRounds '
      '(damped $scanSuppressed), counters $trackedCounters, '
      // TOP-UPS AND DISCARDED ONES BELONG SIDE BY SIDE (S363): the counter
      // on the left says how often the lane has topped up, the one on the
      // right whether something fell anyway. A number > 0 on the right
      // means that someone queues past this queue — the lane itself has
      // asked beforehand since the pull model (`BulkPlacementCapacity`).
      'top-ups ${drain.refills}, discarded ${egress.dropped}';

  @override
  int placeOnce(Uint8List tag, List<Uint8List> sealedBlocks) {
    if (sealedBlocks.isEmpty) return 0;
    final now = DateTime.now().toUtc();
    final epoch = epochFor(tag, now);
    final line = targetFor(tag, epoch);

    final holder = _holderFor(tag, line, now);
    if (holder.isEmpty) {
      noHolder += sealedBlocks.length;
      return 0;
    }

    // EXACTLY ONE DEPOSIT PER BLOCK — the length of the return is the
    // length of the input, and `BulkPlacementPlan.forBlocks` fixes that.
    final plan = BulkPlacementPlan(
        tag: tag, candidates: holder, nowUtc: now, count: kResponsibleRelays);
    if (plan.isEmpty) {
      noHolder += sealedBlocks.length;
      return 0;
    }
    final deposits = plan.forBlocks(
        <(Uint8List, int)>[for (final b in sealedBlocks) (b, 0)]);

    var accepted = 0;
    for (final a in deposits) {
      if (_depositOn(a.holder, line, a.sealedBlock, now)) accepted++;
    }
    drain.kick();
    return accepted;
  }

  /// A single deposit at a named holder.
  ///
  /// Pulled out of [placeOnce] (S372), because [placeAt] does the same —
  /// only with a holder that the caller has determined. Two versions of the
  /// same move would be two behaviours; especially the self-responsibility
  /// branch below must not stand in only one of them.
  bool _depositOn(
      BulkHolder holder, Uint8List line, Uint8List block, DateTime now) {
    if (holder.id == _selfId) {
      // SELF-RESPONSIBILITY (B-34). The routing table never contains this
      // node, but the responsibility set from §9.1 knows no exception for
      // the sender. Without this branch a block for which this node itself
      // is the next holder would lie nowhere. Costs no cell on the wire.
      if (!node.delivery.bulk.place(line, block, now)) return false;
      selfHeld++;
      return true;
    }
    final partner = node.delivery.nextHopToward?.call(holder.position);
    if (partner == null) return false;
    return egress
        .enqueue(BulkOutgoing(partner, buildBulkPlace(holder.position, line, block)));
  }

  /// The responsible ones of the mark — the same set and the same order
  /// from which [placeOnce] builds its round-robin (`BulkDirectedPlacement`).
  @override
  List<BulkHolder> holdersFor(Uint8List tag) {
    final now = DateTime.now().toUtc();
    final epoch = epochFor(tag, now);
    final line = targetFor(tag, epoch);
    final plan = BulkPlacementPlan(
        tag: tag,
        candidates: _holderFor(tag, line, now),
        nowUtc: now,
        count: kResponsibleRelays);
    return plan.holders;
  }

  /// Deposits ONE block at EXACTLY THIS holder
  /// (`BulkDirectedPlacement`).
  ///
  /// `true` means **handed over**, not **stored** — the justification
  /// stands at [BulkDirectedPlacement], and it is a measurement: `BulkOp`
  /// knows no placement receipt.
  @override
  bool placeAt(Uint8List tag, BulkHolder holder, Uint8List sealedBlock) {
    final now = DateTime.now().toUtc();
    final line = targetFor(tag, epochFor(tag, now));
    final ok = _depositOn(holder, line, sealedBlock, now);
    if (!ok) noHolder++;
    drain.kick();
    return ok;
  }

  @override
  void scan(Uint8List tag, List<Uint8List> have) {
    final markHex0 = base64.encode(tag);

    // ── THE DAMPER ─────────────────────────────────────────────────
    //
    // `MediaBulkLane` calls again here on EVERY arrived block as long as
    // the harvest is incomplete. That is right — the lane does not know
    // what a "round" is, and shall not know. Damping therefore happens
    // HERE, at the place that keeps the rounds: as long as a round is
    // running, no second one is started.
    //
    // ── AND WHY THE DAMPER HAS A BACK DOOR ──────────────────
    //
    // If a round end got lost — a holder fails in the middle of the answer
    // —, [_open] would stand above zero forever and the harvest would be
    // DEAD, even for the user's move ("herunterladen",
    // `cleona_service.dart`). A guard over a clock would be a second
    // rhythm; instead [_stir] counts: if NOTHING came back since the last
    // attempt, the round counts as lost and a new one starts. The user
    // thus always gets through, and in operation it never applies, because
    // something keeps arriving during a living round.
    if ((_open[markHex0] ?? 0) > 0) {
      if (_stir[markHex0] ?? false) {
        _stir[markHex0] = false;
        scanSuppressed++;
        return;
      }
      // No stir since the last attempt: the round is lost.
      _open[markHex0] = 0;
      _yield.remove(markHex0);
    }

    final now = DateTime.now().toUtc();
    final epoch = epochFor(tag, now);
    final line = targetFor(tag, epoch);
    final holder = _holderFor(tag, line, now)
        .where((h) => h.id != _selfId)
        .toList();

    // THE OWN POOL FIRST, AND WITHOUT A SINGLE CELL. A node that is itself
    // responsible holds blocks of the line — and asking for them over the
    // wire would be traffic to itself.
    //
    // WITHOUT `limit`, unlike with a foreign holder: the cap there limits
    // TRAFFIC (a line can hold 256 000 blocks), and no traffic arises here.
    // Setting it anyway would have a measurable side effect: the
    // resubmission in `MediaBulkLane._sampled` hangs on progress, so every
    // capped run would synchronously call the next — a recursion as deep as
    // blocks divided by cap.
    final own = node.delivery.bulk.scan(line, have: have);
    if (own.isNotEmpty) {
      _sink?.call(tag, <Uint8List>[for (final e in own) e.sealed]);
    }
    if (holder.isEmpty) return;

    final markHex = base64.encode(tag);
    final round = _scanRounds.update(markHex, (v) => v + 1, ifAbsent: () => 0);
    final offset = (round * kBulkScanRelaysPerRound) % holder.length;
    final lineHex = base64.encode(line);
    var placed = 0;

    for (var i = 0; i < kBulkScanRelaysPerRound && i < holder.length; i++) {
      final h = holder[(offset + i) % holder.length];
      final partner = node.delivery.nextHopToward?.call(h.position);
      if (partner == null) continue;
      final id = SodiumFFI().randomBytes(kBulkRequestIdBytes);
      final from = '${h.id}|$lineHex';
      _scanFrom[base64.encode(id)] = from;
      (_hopFromMark[markHex] ??= <String>{}).add(from);
      _scanTags[base64.encode(id)] = Uint8List.fromList(tag);
      // FIFO cap like `V41Node._ownRequests`: without it the ledger grows
      // with every request and becomes a memory leak. 256 open identifiers
      // are, at four per run, 64 runs of memory — more than an answer ever
      // needs.
      while (_scanTags.length > 256) {
        final route = _scanTags.keys.first;
        _scanTags.remove(route);
        _scanFrom.remove(route);
      }
      if (egress.enqueue(BulkOutgoing(
          partner,
          buildBulkScan(h.position, id, line,
              have: have, skip: _scanHop[from] ?? 0)))) {
        placed++;
      }
    }
    // ONLY NOW — after queueing, not before. A round from which not a
    // single request went out (no way to a holder, drain full) must not
    // close the damper; otherwise it would block the next one without a
    // round end ever coming.
    if (placed > 0) {
      _open[markHex] = placed;
      _yield[markHex] = 0;
      _stir[markHex] = false;
      scanRounds++;
    }
    drain.kick();
  }

  /// The responsible ones of a line, including this node itself.
  ///
  /// **This node stands in the set too, and `closestTo` decides whether it
  /// stays in.** Leaving it out would be B-34 (the own position never
  /// stands in the own routing table, but responsibility per §9.1 knows no
  /// exception); including it unchecked would be a second responsibility
  /// rule next to §9.1.
  ///
  /// **`alwaysOn: true` for all** — see the file header: the entry record
  /// does not carry the budget class, so this filter cannot be served here.
  /// The own node is the exception: it knows its class.
  List<BulkHolder> _holderFor(Uint8List tag, Uint8List line, DateTime now) {
    final relay = node.responsibleRelays(line, now: now);
    final out = <BulkHolder>[
      for (final r in relay) BulkHolder(base64.encode(r.lNode), r.lNode),
      BulkHolder(_selfId, node.keys.lNode,
          alwaysOn: node.delivery.bulk.enabled),
    ];
    return out;
  }

  /// How a due frame goes out.
  ///
  /// Via `emitFrame(0x05, …)` and thus PAST the control queue — that is the
  /// whole purpose of the second drain. The clock sits in [BulkDrain], not
  /// here.
  ///
  /// `false` means: the partner index has become empty in the meantime
  /// (connection gone). The frame is NOT resubmitted — the overshoot factor
  /// `F` covers exactly that (§9.3), and a resubmission per block would be
  /// a second bookkeeping over 256 000 entries.
  bool _send(BulkOutgoing item) {
    final partner = node.delivery.partners;
    if (item.partner < 0 || item.partner >= partner.length) return false;
    partner[item.partner].emitFrame(LinkFrameType.fountain, item.body);
    // NO FORWARDING — this is the OWN drain of this node: the blocks come
    // from the own `MediaBulkLane`, from a transfer that this node itself
    // triggered. Foreign bulk frames take another path
    // (`DeliveryNode._forwardBulk`), and that one books.
    //
    // This send site lay OUTSIDE of what `smoke_network_stats` looked at at
    // all until S363 — the guard read exactly one file. It now checks all
    // of `lib/`.
    return true;
  }

  static const String _selfId = '@self';
}

/// A bulk quota as it suits this platform.
///
/// A thin detour so that `startV41Node` can read `Platform.*` without
/// `lib/core/bulk/` doing so (the same layer boundary for which
/// `maxStoreBytes` is formed at `startV41Node` and not in the
/// `SecureStore`).
BulkCache bulkCacheForPlatform({required bool mobile}) =>
    mobile ? BulkCache(enabled: false) : BulkCache();
