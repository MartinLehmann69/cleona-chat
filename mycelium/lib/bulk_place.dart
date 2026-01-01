/// The sender of lane 3 (§9.4, D-30): stripes an
/// object, seals every piece under a fresh `K_T` and places each piece
/// ONCE with an always-on holder.
///
/// ## Who gets what
/// With `h` holders (at most eleven, in the caller's order), piece `i` goes
/// to share `i mod h`. With eleven, piece `n` of every stripe goes to
/// holder `n` — the eleven of a stripe lie with eleven distinct holders,
/// and losing four holders loses at most four pieces of any stripe. With
/// fewer, one holder carries several pieces of a stripe and that bound no
/// longer holds (B-30); [BulkPlaced.decodable] says whether the accepted
/// shares still reach seven per stripe.
///
/// ## The sequence per holder
/// Proof of work for its count, `0x52` open, wait up to [kOpenWait] for
/// the `0x53`. Count 0 (a mobile node, a full or absent cache) or no answer:
/// the share moves to the next unused candidate of the list; without one
/// it goes to a holder that already accepted another share (B-30, a proof
/// of its own), and only if none takes it does it stay unplaced — the
/// result says so. Then the pieces, share
/// by share, at `R_bulk` — grouped per holder so that each holder sees ONE
/// quiet after its last piece and reports ONE final count.
///
/// ## Holder classes (§9.4, D-30)
/// Every `0x53` states desktop or phone; the class per holder address
/// ([classOf], memory only, [kClassesAtMost], oldest forgotten) lets the
/// next transfer ask desktops before phones of equal rank.
///
/// ## Bounds (§20.2)
/// One transfer at a time per node (§9.4); [kPlaceWaitingAtMost] wait, one
/// more evicts the OLDEST waiting ("displaced"). Every wait ends by a
/// deadline; nothing runs in idle.
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/bulk_piece.dart';
import 'package:mycelium/card.dart' show CardAddress;
import 'package:mycelium/media.dart'
    show kAtMostObject, kPiecesPerStripe, kStripeWidth, stripeForm, stripeNumber;

/// How long a holder has to answer an open. Not the 800 ms of the post
/// box: the holder checks a proof and may write its index first.
const Duration kOpenWait = Duration(seconds: 5);

/// How long the sender waits for the final counts after its last piece.
const Duration kFinalWait = Duration(seconds: 3);

/// Calls waiting behind the running transfer.
const int kPlaceWaitingAtMost = 8;

/// Holder addresses whose class is remembered.
const int kClassesAtMost = 1024;

typedef BulkHolderShare = ({CardAddress address, int assigned, int confirmed});

/// An interrupted run of placing (S398-W1, §9.4 "The rest goes into the
/// network"): the holder per share (`null` = none), kept by the layer above
/// across a restart. Resuming re-opens the same holders under the same
/// `K_T` — the pieces they already hold stay, the number of shares too.
typedef BulkResume = ({List<CardAddress?> assigned});

/// What placing an object did — everything the announcement needs, and the
/// numbers to judge it.
class BulkPlaced {
  /// `K_T` — goes into the announcement, never anywhere else (§9.4).
  final Uint8List transferKey;
  final Uint8List tag;
  final int length;
  final Uint8List sha256;

  /// The holders that accepted, in the order of the caller's list. The
  /// announcement names exactly these.
  final List<BulkHolderShare> holders;
  final int pieces;

  /// Pieces that found no holder.
  final int unplaced;

  /// Whether every stripe has at least seven pieces with an accepting holder.
  final bool decodable;

  /// Packets and payload bytes sent (opens and pieces).
  final int packets;
  final int bytes;
  final Duration took;

  /// Why nothing (or not all) was placed; `null` when all shares found a holder.
  final String? reason;

  BulkPlaced(this.transferKey, this.tag, this.length, this.sha256, this.holders,
      this.pieces, this.unplaced, this.decodable, this.packets, this.bytes,
      this.took, this.reason);

  /// No holder accepted anything.
  bool get failed => holders.isEmpty;

  /// The holder addresses for the announcement, at most eleven.
  List<CardAddress> get holderAddresses => [for (final h in holders) h.address];
}

class _Job {
  final Uint8List object;
  final List<CardAddress> holders;
  final void Function(int sent, int total)? progress;
  final Uint8List? transferKey;
  final BulkResume? resume;
  final void Function(List<CardAddress?> assigned)? onAssigned;
  final done = Completer<BulkPlaced>();
  _Job(this.object, this.holders, this.progress, this.transferKey, this.resume,
      this.onAssigned);
}

class _Final {
  final int assigned;
  int latest = 0;
  final done = Completer<void>();
  _Final(this.assigned);
}

class BulkPlacer {
  final void Function(Uint8List packet, CardAddress to) _send;
  final BulkPace _pace;
  final void Function(String)? report;
  final List<_Job> _waiting = [];
  final Map<String, (int, Completer<int>)> _opens = {};
  final Map<String, _Final> _finals = {};

  /// Oldest first — the order of forgetting.
  final Map<String, BulkClass> _classes = {};
  bool _running = false;

  BulkPlacer({
    required void Function(Uint8List packet, CardAddress to) send,
    BulkPace? pace,
    this.report,
  })  : _send = send,
        _pace = pace ?? BulkPace();

  /// Places [object] with the holders of [holdersInOrder] (deduplicated;
  /// the first eleven that accept). [progress] counts pieces sent.
  ///
  /// [transferKey]: the `K_T` to seal under — a lane 2 attempt that falls
  /// back places under the `K_T` its announcement already carried (§17.6
  /// "falls to the bulk lane for the remainder"; pieces are lane-neutral,
  /// §9.4), so identifier and pieces stay those of the announcement.
  /// Without it a fresh `K_T` is drawn.
  ///
  /// [resume] continues an interrupted run of placing under the same
  /// [transferKey] (required with it); [onAssigned] reports the holder of
  /// every share once they are negotiated — what [resume] needs later.
  Future<BulkPlaced> place(Uint8List object, List<CardAddress> holdersInOrder,
      {void Function(int sent, int total)? progress,
      Uint8List? transferKey,
      BulkResume? resume,
      void Function(List<CardAddress?> assigned)? onAssigned}) {
    if (object.isEmpty || object.length > kAtMostObject) {
      throw ArgumentError('object of ${object.length} B — 1 to $kAtMostObject');
    }
    if (transferKey != null && transferKey.length != kTransferKeyLength) {
      throw ArgumentError('K_T of ${transferKey.length} B');
    }
    if (resume != null && transferKey == null) {
      throw ArgumentError('resuming needs the K_T');
    }
    final job = _Job(
        object, holdersInOrder, progress, transferKey, resume, onAssigned);
    if (_waiting.length >= kPlaceWaitingAtMost) {
      final old = _waiting.removeAt(0);
      old.done.complete(_nothing(old.object, 'displaced — more than '
          '$kPlaceWaitingAtMost transfers waiting (§20.2)'));
    }
    _waiting.add(job);
    _next();
    return job.done.future;
  }

  void _next() {
    if (_running || _waiting.isEmpty) return;
    _running = true;
    final job = _waiting.removeAt(0);
    _run(job).then(job.done.complete, onError: job.done.completeError)
        .whenComplete(() {
      _running = false;
      _next();
    });
  }

  /// The class [holder] last stated in a `0x53`; unknown if it never did
  /// (or was forgotten, [kClassesAtMost]).
  BulkClass classOf(CardAddress holder) =>
      _classes['$holder'] ?? BulkClass.unknown;

  /// A `0x53` from a holder: the answer to an open, or a final count.
  void receive(Uint8List p, CardAddress from) {
    final x = readHeld(p);
    if (x == null) return;
    final key = '${tagHex(x.tag)}@$from';
    // Only an answer this placer waits for: a stray 0x53 teaches nothing.
    if (_opens.containsKey(key) || _finals.containsKey(key)) {
      _classes.remove('$from');
      _classes['$from'] = x.cls; // to the end: the newest is forgotten last
      if (_classes.length > kClassesAtMost) {
        _classes.remove(_classes.keys.first);
      }
    }
    // An open is answered with its count or 0; a count in between is the
    // final count of an EARLIER intake (a resumed run, S398-W1) — not it.
    final open = _opens[key];
    if (open != null && (x.count == 0 || x.count >= open.$1)) {
      _opens.remove(key);
      return open.$2.complete(x.count);
    }
    final f = _finals[key];
    if (f == null) return;
    f.latest = x.count;
    if (x.count >= f.assigned && !f.done.isCompleted) f.done.complete();
  }

  BulkPlaced _nothing(Uint8List object, String why) => BulkPlaced(
      Uint8List(kTransferKeyLength), Uint8List(kTagLength), object.length,
      SodiumFFI().sha256(object), const [], 0, 0, false, 0, 0, Duration.zero, why);

  Future<BulkPlaced> _run(_Job job) async {
    final start = DateTime.now();
    final blocks = stripeForm(job.object);
    final n = blocks.length;
    final kT = job.transferKey ?? transferKeyDraw();
    final tag = bulkTag(kT);
    final seal = bulkSealKey(kT);
    final r = job.resume != null && job.resume!.assigned.isNotEmpty &&
            job.resume!.assigned.length <= kHoldersAtMost
        ? job.resume
        : null;
    final old = r?.assigned ?? const <CardAddress?>[];
    final candidates = <CardAddress>[];
    for (final c in job.holders) {
      if (!candidates.any((x) => x.equal(c)) &&
          !old.any((x) => x != null && x.equal(c))) {
        candidates.add(c);
      }
    }
    // Resumed: the SAME number of shares, or piece i would change holder.
    final h = r != null ? old.length : min(kHoldersAtMost, candidates.length);
    if (h == 0) return _nothing(job.object, 'no holder known');
    final counts = [for (var j = 0; j < h; j++) n ~/ h + (j < n % h ? 1 : 0)];
    if (counts.first > 0xFFFF) {
      return _nothing(job.object, '${counts.first} pieces for one holder — '
          'more than an open can announce (u16)');
    }
    var packets = 0;
    var cursor = r != null ? 0 : h;
    final assigned = List<CardAddress?>.filled(h, null);
    Future<void> negotiate(int j) async {
      var c = r != null ? old[j] : candidates[j];
      if (c == null) {
        if (cursor >= candidates.length) return;
        c = candidates[cursor++];
      }
      for (;;) {
        packets++;
        if (await _openAt(c!, tag, counts[j], job.object.length)) {
          assigned[j] = c;
          return;
        }
        if (cursor >= candidates.length) return;
        c = candidates[cursor++];
      }
    }

    if (r != null) {
      // One after another: two shares of one holder would share the key of
      // the waiting open (`_opens`).
      for (var j = 0; j < h; j++) {
        await negotiate(j);
      }
    } else {
      await Future.wait([for (var j = 0; j < h; j++) negotiate(j)]);
    }
    // B-30: a share whose candidates all refused goes to a holder that
    // already accepted — with an open and a proof of its own (D-30); the
    // failure bound per holder no longer holds for those stripes, but the
    // pieces are placed instead of lost.
    final accepted = <CardAddress>[];
    for (final a in assigned) {
      if (a != null && !accepted.any((x) => x.equal(a))) accepted.add(a);
    }
    for (var j = 0; j < h && accepted.isNotEmpty; j++) {
      if (assigned[j] != null) continue;
      for (var k = 0; k < accepted.length; k++) {
        final c = accepted[(j + k) % accepted.length];
        packets++;
        if (await _openAt(c, tag, counts[j], job.object.length)) {
          assigned[j] = c;
          break;
        }
      }
    }
    final total = [for (var j = 0; j < h; j++) if (assigned[j] != null) counts[j]]
        .fold(0, (a, b) => a + b);
    // One final count per ADDRESS: a holder reports what it holds under the
    // tag, all its shares together.
    final perAddress = <String, (CardAddress, int)>{};
    for (var j = 0; j < h; j++) {
      final a = assigned[j];
      if (a == null) continue;
      final was = perAddress['$a'];
      perAddress['$a'] = (a, (was?.$2 ?? 0) + counts[j]);
    }
    final finals = <String, _Final>{
      for (final e in perAddress.entries)
        e.key: _finals['${tagHex(tag)}@${e.key}'] = _Final(e.value.$2),
    };
    job.onAssigned?.call(List.of(assigned));
    // Resumed: EVERY piece again. A piece the last run counted as sent may
    // never have left the node (measured, S398-W1: 1216 counted, 887 held);
    // the holder keeps each (stripe, number) once and drops repeats.
    var sent = 0;
    var wire = 0;
    final step = max(1, total ~/ 10);
    report?.call('Bulk: placing ${tagHex(tag).substring(0, 8)}: $n pieces, '
        '${perAddress.length} holder(s) ${perAddress.keys.join(', ')}'
        '${r != null ? ', resumed with the same holders' : ''}');
    for (var j = 0; j < h; j++) {
      final to = assigned[j];
      if (to == null) continue;
      for (var i = j; i < n; i += h) {
        final s = i ~/ kPiecesPerStripe, no = i % kPiecesPerStripe;
        await _pace.turn();
        _send(holdPiecePacket((tag: tag, stripe: s, no: no,
            sealed: pieceSeal(seal, tag, s, no, blocks[i]))), to);
        wire++;
        job.progress?.call(++sent, total);
        if (sent % step == 0 && sent < total) {
          report?.call('Bulk: placing ${tagHex(tag).substring(0, 8)}: $sent '
              'of $total pieces sent (holder $to)');
        }
      }
    }
    await Future.wait([for (final f in finals.values) f.done.future])
        .timeout(kFinalWait, onTimeout: () => const []);
    final shares = <BulkHolderShare>[
      for (final e in finals.entries)
        (
          address: perAddress[e.key]!.$1,
          assigned: e.value.assigned,
          confirmed: e.value.latest
        ),
    ];
    for (final k in finals.keys) {
      _finals.remove('${tagHex(tag)}@$k');
    }
    var decodable = true;
    for (var s = 0; s < stripeNumber(job.object.length); s++) {
      var there = 0;
      for (var no = 0; no < kPiecesPerStripe; no++) {
        if (assigned[(s * kPiecesPerStripe + no) % h] != null) there++;
      }
      if (there < kStripeWidth) decodable = false;
    }
    final unplaced = n - total;
    final opens = packets;
    packets += wire;
    report?.call('Bulk: placed $sent of $n pieces with ${shares.length} '
        'holders in ${DateTime.now().difference(start).inMilliseconds} ms '
        '(${[for (final s in shares) '${s.address} ${s.confirmed}/${s.assigned}'].join(', ')})');
    return BulkPlaced(kT, tag, job.object.length, SodiumFFI().sha256(job.object),
        shares, n, unplaced, decodable && shares.isNotEmpty, packets,
        opens * kOpenLength + wire * kHoldPieceLength,
        DateTime.now().difference(start),
        shares.isEmpty
            ? 'no holder accepted'
            : unplaced > 0 ? '$unplaced pieces without a holder' : null);
  }

  Future<bool> _openAt(
      CardAddress to, Uint8List tag, int count, int total) async {
    final proof = await holdProof(tag, count, to);
    final key = '${tagHex(tag)}@$to';
    final answer = Completer<int>();
    _opens[key] = (count, answer);
    _send(openPacket(tag, count, total, proof), to);
    final accepted =
        await answer.future.timeout(kOpenWait, onTimeout: () => 0);
    _opens.remove(key);
    return accepted >= count && accepted > 0;
  }
}
