// What this node ALREADY HAD of a tagline.
//
// ── THE FINDING THAT MAKES THIS FILE NECESSARY (B-32, S350) ─────────────
//
// Measured in the field on 28.08. (two nodes, one segment): ONE sent
// text appeared at the recipient **21 times** as `V4.1 EMPFANG MTV3_TEXT`.
// The user saw it once — the application's `messageId` dedup applies —,
// it was paid for twenty-one times: twenty-one times over the wire,
// twenty-one times through reassembler, seal and signature check.
//
// The 21 are no random value, they can be computed: `placeSecure` places
// every piece under **three** family tags (m=3, D1) — with the same
// content. In the lab the same node was responsible for all three tags,
// so one harvest fetched three identical copies, and the reassembler
// got the two pieces of the message complete three times in a row.
// Three deliveries per harvest run, seven runs in a good
// three and a half minutes: 3 x 7 = 21.
//
// That violates work rule 5 ("No unnecessary network traffic.
// Every message counts.") — and it does not stop by itself:
// `SecureStore.expire()` had NO caller in `lib/`, so the cell
// rested with the relay until the process ended and was delivered again every 32 s.
//
// ── WHY DELETING ON HARVEST IS NO SOLUTION ──────────────────────────────
//
// §14.2 ("One delivery serves all devices"): all devices of an identity
// share the `inbox_key` and harvest **the same tagline**; they share the
// user KEM key and open **the same cell**. A relay that deletes after
// the first fetch takes the cell away from the second device — and
// unnoticed, because the delivery has long been confirmed for the sender.
// The cell MUST stay until its deadline expires.
//
// ── WHAT HAPPENS INSTEAD ───────────────────────────────────────────────
//
// The HARVESTER keeps a book and tells the relay in the request what it
// already has ("have-list", `secure_frames.dart`). The relay then only sends
// what is missing.
//
// Three properties that distinguish this solution from a relay-side
// receipt:
//
//   1. **No state at the relay.** The have-list applies to EXACTLY THIS
//      request. The relay remembers nothing, consumes nothing and
//      forgets nothing — it has nothing to forget either.
//   2. **No recognisable fetcher.** A receipt ("this one already has
//      it") would need an identifier of the fetcher that is stable across rounds.
//      Exactly that does not exist here and is not supposed to: the answer
//      finds home via `requestId` and the remembered return path, and no
//      node knows more than its two neighbours (§11.2).
//   3. **§14.2 stays.** A second device keeps its own book, has
//      nothing, declares nothing and gets everything.
//
// ── WHAT THE HAVE-LIST REVEALS, without glossing over ──────────────────
//
// A tag is `SHA-256("cleona-harvest-have/v1" ‖ cell)`, truncated to 8 B.
// The responsible relay holds the cell itself and can compute the
// tag at any time — towards it the tag is no secret. A
// relay that holds NOTHING under the queried tags (the decoy case)
// would without further ado see the NUMBER of cells this neighbour
// already has. Therefore the list is **always the same length**
// ([kHarvestHaveSlots]) and padded with filler tags that come from the
// device-local secret — the same reasoning from which the
// decoy tags are already derived and not rolled
// (`liveness.dart`): rolled filler tags would differ between two
// queries of the same epoch, and the intersection of both lists
// would be exactly the set of the real ones.
//
// Sorting is by the value of the tag, not by origin. The position
// in the list thus carries no information — real and filler tags lie
// uniformly distributed among each other, without a mixing function being needed
// that would rearrange the whole list when a real tag is added.
//
// ── TWO STAGES, BECAUSE ONE DOES NOT SUFFICE ───────────────────────────
//
// A tag only goes into the book when the transfer to which it
// belongs is COMPLETELY reassembled. If the first piece were already
// noted, a transfer whose buffer was displaced by
// [PayloadReassembler.maxOpenTransfers] could never be
// fetched again: the first piece would no longer come, the second would find
// no start, and the message would be silently lost.
//
// Within a still open transfer the repetition is
// nevertheless rejected, and that is not only thrift: a second
// time the same first piece would hit the reassembler at `off !=
// t.filled` and THROW AWAY THE WHOLE OPEN TRANSFER
// (`frame_split.dart`). The m=3 redundancy delivers exactly such
// repetitions — without this stage it would be a delivery obstacle instead of
// a censorship protection.
//
// NO CLOCK, NO I/O. The epoch comes in, as everywhere in this
// layer.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';

import 'frame_split.dart';
// The deadline of the book hangs on the LONGEST retention class of the
// relay — it stands where the classes stand. The back reference is
// intended: a copy of the number would be exactly the drift that S363 closed in the
// delivery layer.
import 'secure_mode.dart' show kManagementKeepEpochs, kNormalKeepEpochs;

/// Length of a cell tag in bytes.
///
/// 8 B = 64 bits. The tag only has to distinguish within the cells of ONE pair in
/// ONE epoch — that is at most `maxCellsPerTag` (32)
/// pieces. The probability of a collision is thus
/// `32^2 / 2^65 ~ 3 * 10^-17`; its consequence would be a single
/// piece not delivered again, no loss of security. 32 B per tag would have
/// brought the have-list from 256 to 1024 B and pushed the request
/// over the cell limit.
const int kCellDigestBytes = 8;

/// How many tags a have-list carries — ALWAYS exactly this many.
///
/// Equal to the tag quota of a relay (`SecureStore.maxCellsPerTag` = 32):
/// under ONE tag a relay can hold at most 32 cells. The list
/// can thus cover the stock of a relay completely — no
/// cell falls through because there was no room left.
///
/// ── WHY 32 SUFFICES EVEN AFTER BUNDLING (S358) ─────────────────────────
///
/// Since S358 a request carries up to `kMaxRealHarvestTags` = 6 real
/// tags instead of one, and one might think the list would have to
/// grow accordingly. It need not, and the reason is the cut
/// of the bundling: **a bundle carries only tags of ONE counterpart**
/// (`bundleHarvest` — more would not be possible without turning the sender into a guess).
/// The list comes from the book of EXACTLY THIS counterpart, and
/// a tag is CONTENT-based:
///
///   * The m = 3 family tags carry identical content (that is the
///     reason why `cellDigest` is content-based at all). Six
///     tags thus do not point to six times as many different
///     cells, but to the same ones.
///   * What is added is the signal line — and its cells live
///     at most `kSignalKeepBuckets x kRetentionBucketSeconds` = 240 s
///     (§17.2). They never stay in the book long enough to bind places.
///
/// What matters is thus the number of DIFFERENT cells of a pair, not
/// the number of queried tags. It is unchanged.
const int kHarvestHaveSlots = 32;

/// The tag of a cell.
Uint8List cellDigest(Uint8List cell) {
  final buf = Uint8List(_prefix.length + cell.length)
    ..setRange(0, _prefix.length, _prefix)
    ..setRange(_prefix.length, _prefix.length + cell.length, cell);
  return Uint8List.sublistView(SodiumFFI().sha256(buf), 0, kCellDigestBytes);
}

final Uint8List _prefix =
    Uint8List.fromList(utf8.encode('cleona-harvest-have/v1'));

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

/// How a harvested cell is to be classified.
enum CellVerdict {
  /// New — it goes into the reassembler.
  fresh,

  /// Already had completely once, or already seen in this transfer.
  /// It is dropped BEFORE it costs crypto.
  duplicate,
}

/// The book of a counterpart: what of its tagline was already there.
final class HarvestMemo {
  /// How many node epochs a tag is valid.
  ///
  /// Must be at least as long as a relay holds the cell
  /// (`SecureStore.keepEpochs`) — a tag that forgets earlier than the
  /// relay lets the same cell through again afterwards.
  ///
  /// ── UPDATED S363 (D2), AND IT HAD A REAL CONSEQUENCE ─────────────
  ///
  /// The default stood there as a bare `3` — the same number that
  /// `SecureStore.keepEpochs` had back then, but without a connection to it.
  /// With D2 (03.09.2026) the relay holds an ordinary cell
  /// [kNormalKeepEpochs] = 14 epochs; a book with 3 would have BROKEN the condition
  /// above and let the same cell through again after three days
  /// — visible as a doubly delivered message. Exactly
  /// the error against which `smoke_v41_harvest_repeat.dart` stands.
  ///
  /// It is bound to [kManagementKeepEpochs] = 31 and not to the 14:
  /// "as long as a relay holds the cell" means the LONGEST
  /// retention class, and that is the management class. With 14
  /// the condition would remain broken for management cells — a
  /// hole that already existed before D2 (3 against 31) and is closed here
  /// too.
  ///
  /// The price is capped, not the deadline: [capacity] = 128 tags
  /// per counterpart limits the memory independently of the deadline, and
  /// what is displaced is the OLDEST — i.e. the tag of the cell that
  /// expires first at the relay.
  final int keepEpochs;

  /// Maximum number of finished tags per counterpart.
  ///
  /// The cap is memory protection, not behaviour: it only applies when
  /// a pair has exchanged more than [capacity] different pieces in one epoch.
  /// What is displaced is the OLDEST tag — it belongs
  /// to the cell that expires first at the relay.
  final int capacity;

  /// Maximum number of simultaneously open transfers whose tags
  /// are pre-noted. Mirrors [PayloadReassembler.maxOpenTransfers]: pre-noting
  /// more than the reassembler can keep open would bring nothing.
  final int maxOpenTransfers;

  /// Finished tags: tag -> node epoch in which it was entered.
  /// Insertion order = age (Dart maps keep it).
  final Map<String, int> _done = <String, int>{};

  /// Pre-noted tags per transfer, not yet in the book.
  final Map<int, List<String>> _open = <int, List<String>>{};

  /// How many repetitions were rejected — counter, not log (E-83).
  int duplicates = 0;

  HarvestMemo({
    this.keepEpochs = kManagementKeepEpochs,
    this.capacity = 128,
    this.maxOpenTransfers = 4,
  });

  int get length => _done.length;

  /// The real tags, youngest first.
  ///
  /// For the path via the OWN placement store: nobody watches there,
  /// so no filler tags are needed.
  List<Uint8List> knownDigests({int limit = kHarvestHaveSlots}) {
    final after = _done.entries.toList()
      ..sort((a, b) => b.value - a.value);
    return [
      for (final e in after.take(limit)) _unhex(e.key),
    ];
  }

  /// The have-list for a harvest request: exactly [slots] tags.
  ///
  /// Real ones selected first (youngest epoch first — the oldest
  /// expire next at the relay anyway), then padded with derived
  /// filler tags and sorted by value.
  List<Uint8List> declare({
    required Uint8List deviceSecret,
    required int epoch,
    int slots = kHarvestHaveSlots,
  }) {
    final out = knownDigests(limit: slots);
    for (var i = out.length; i < slots; i++) {
      out.add(Uint8List.sublistView(
          SodiumFFI().hkdfSha256(deviceSecret,
              salt: Uint8List.fromList(utf8.encode('cleona-harvest-have')),
              info: Uint8List.fromList(utf8.encode('filler/$epoch/$i')),
              length: 32),
          0,
          kCellDigestBytes));
    }
    out.sort(_compare);
    return out;
  }

  /// Was this cell already there completely once?
  bool knows(Uint8List cell) => _done.containsKey(_hex(cellDigest(cell)));

  /// Accepts a harvested cell for assessment.
  ///
  /// Notes the tag as PRE-NOTED — it only goes into the book with
  /// [completed].
  CellVerdict offer(Uint8List cell, int epoch) {
    final mark = _hex(cellDigest(cell));
    if (_done.containsKey(mark)) {
      duplicates++;
      return CellVerdict.duplicate;
    }
    final id = splitTransferId(cell);
    if (id == null) {
      // No readable header. The reassembler discards it right away itself;
      // nothing is pre-noted here that never belongs to a transfer.
      return CellVerdict.fresh;
    }
    final list = _open.putIfAbsent(id, () {
      while (_open.length >= maxOpenTransfers) {
        _open.remove(_open.keys.first);
      }
      return <String>[];
    });
    if (list.contains(mark)) {
      // The same piece a second time while the transfer is still
      // open — that is the m=3 copy. It must not reach the reassembler,
      // otherwise it throws away half the transfer.
      duplicates++;
      return CellVerdict.duplicate;
    }
    list.add(mark);
    return CellVerdict.fresh;
  }

  /// The transfer [transferId] is complete — its tags apply.
  void completed(int transferId, int epoch) {
    final list = _open.remove(transferId);
    if (list == null) return;
    for (final mark in list) {
      _done[mark] = epoch;
      while (_done.length > capacity) {
        _done.remove(_done.keys.first);
      }
    }
  }

  /// Throws away what is older than [keepEpochs].
  int expire(int currentEpoch) {
    var route = 0;
    for (final k in _done.keys.toList()) {
      if (_done[k]! <= currentEpoch - keepEpochs) {
        _done.remove(k);
        route++;
      }
    }
    return route;
  }

  static Uint8List _unhex(String s) => Uint8List.fromList(List<int>.generate(
      s.length ~/ 2,
      (i) => int.parse(s.substring(i * 2, i * 2 + 2), radix: 16)));

  static int _compare(Uint8List a, Uint8List b) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) return a[i] - b[i];
    }
    return a.length - b.length;
  }
}
