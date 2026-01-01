/// The holder of lane 3 (§9.4 "Lane 3, holding"; D-30): keeps sealed
/// pieces for others in the bulk cache and hands them to whoever asks with
/// the identifier.
///
/// Active only with a budget above 0 — the app passes it (§21.3.3: desktop
/// 1 GB, phone 100 MB, D-32); a node without a budget answers every open
/// with `0x53` count 0. Every `0x53` states the holder's [BulkClass].
///
/// ## A holder holds only with evidenced reachability (§9.4, §11.8a, D-30)
/// "A holder is a node with evidenced reachability": a holder the
/// recipient cannot reach would take pieces nobody can collect. A phone
/// takes an open only when the address it was written to lies in a family
/// found open from outside — by the check of §8.1 or by a mapping or
/// pinhole the router granted ([_reachable]). A desktop takes it only when
/// its reachability is evidenced at all ([_proven]): a granted mapping or
/// pinhole, a passed open check, or the board's proof
/// (`Board.reachableProven`: mapping OR an unsolicited packet, §11.8a). An
/// address confirmed from outside is no such evidence — behind a
/// translator it answers only whom it asked. Without the evidence:
/// `0x53` count 0, and the sender moves on.
///
/// While the app reports data-saving mode on a metered connection
/// ([_serveAllowed] `false`) a phone refuses every open with count 0, takes
/// no piece and does not answer `0x54` at all — silence, not `0x55`: "nothing
/// here" would end the recipient's collection, silence leaves it to the next
/// edge of §8.2. A desktop ignores [_serveAllowed] (D-32).
///
/// ## Bounds (§20.2 — every buffer states its bound and its overflow)
/// | Buffer | Bound | On overflow |
/// |---|---|---|
/// | all pieces together | [budget] B | oldest identifier's oldest pieces evicted |
/// | pieces per identifier | the `count` of its open | the rest discarded |
/// | identifiers | [kIdentifiersAtMost] | oldest identifier evicted |
/// | answers to `0x54` running at once | [kAnswersAtMost] | the question ignored — it comes again at the asker's next edge |
/// | one open larger than the budget | refused with count 0 | — |
///
/// Evicting, never blocking: an attacker with one valid proof can fill the
/// budget, but what it pushes out ages out first — its own pieces are the
/// newest (§20.2). Lost pieces of others cost them at most four of eleven
/// per stripe before the transfer breaks (§9.4).
///
/// ## No clock, no deletion on request
/// Expiry after `TTL_media` is checked when a packet arrives and at start,
/// never on a timer (§5.4). The one timer here is the 300 ms quiet of an
/// intake (§11.3) — it runs only while pieces arrive. Nobody can delete: a
/// "done" packet would be a delete command anyone could send (§9.4).
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:mycelium/bulk_disk.dart';
import 'package:mycelium/bulk_piece.dart';
import 'package:mycelium/card.dart' show CardAddress;
import 'package:mycelium/kinds.dart' as kinds;

/// At most this many identifiers are held at once.
const int kIdentifiersAtMost = 4096;

/// At most this many `0x54` are answered at the same time.
const int kAnswersAtMost = 32;

class _Held {
  final Uint8List tag;
  final DateTime inserted;

  /// The sender's addresses. ONE node may be named under several addresses
  /// (LAN and public, the recipient's list and the own one), and the sender
  /// then places one share per address — each arrives from the address it
  /// was sent to.
  final List<CardAddress> from = [];

  /// The proofs taken for this identifier: each distinct valid open adds
  /// its count once; the same open again (a repeat) adds nothing.
  final Set<String> proofs = {};
  int allowed;
  int onDisk;
  final Map<int, Uint8List> fresh = {};
  Timer? quiet;

  _Held(this.tag, this.inserted, this.allowed, [this.onDisk = 0]);

  int get held => onDisk + fresh.length;
  HeldIndex get index =>
      (tag: tag, inserted: inserted, allowed: allowed, held: held);
}

class BulkHolder {
  /// The bulk cache in bytes of sealed pieces; 0 = no bulk.
  final int budget;

  /// Desktop or phone — stated in every `0x53`.
  final BulkClass cls;
  final bool Function(CardAddress own) _reachable;
  final bool Function() _proven;
  final bool Function() _serveAllowed;
  final BulkDisk? _disk;
  final BulkPace _pace;
  final void Function(Uint8List packet, CardAddress to) _send;
  final void Function(String)? report;

  /// The addresses under which this node knows itself (interfaces, the
  /// public address confirmed from outside or granted by the router). An
  /// open counts only with a proof bound to one of them (D-30: once per
  /// transfer AND holder) — a proof paid for another holder opens nothing
  /// here.
  final List<CardAddress> Function() _own;

  /// Oldest first — the order of eviction.
  final Map<String, _Held> _held = {};
  final Set<String> _answering = {};
  int _used = 0;

  /// Pieces pushed out because the cache was full (§21.3.3 item 4: eviction
  /// under budget pressure is shown in the network statistics, §25).
  /// Expiry after `kTtlMedia` is not counted.
  int evicted = 0;

  BulkHolder({
    required this.budget,
    required void Function(Uint8List packet, CardAddress to) send,
    required List<CardAddress> Function() own,
    this.cls = BulkClass.desktop,
    bool Function(CardAddress own)? reachable,
    bool Function()? proven,
    bool Function()? serveAllowed,
    BulkDisk? disk,
    BulkPace? pace,
    this.report,
  })  : _send = send,
        _own = own,
        _reachable = reachable ?? ((_) => false),
        _proven = proven ?? (() => false),
        _serveAllowed = serveAllowed ?? (() => true),
        _disk = budget > 0 ? disk : null,
        _pace = pace ?? BulkPace() {
    _load();
  }

  /// Bytes of sealed pieces held — for the statistics (§21.3.3 item 4).
  int get usedBytes => _used;

  /// Pieces held under [tag].
  int heldFor(Uint8List tag) => _held[tagHex(tag)]?.held ?? 0;

  bool get _phone => cls == BulkClass.phone;

  /// A phone under data-saving mode on a metered connection (D-32).
  bool get _resting => _phone && !_serveAllowed();

  void receive(Uint8List p, CardAddress from) {
    _expire();
    if (p.isEmpty) return;
    if (p[0] == kinds.kBulkCollect) {
      final c = readCollect(p);
      if (c != null && !_resting) unawaited(_answer(c.tag, from, c.from));
      return;
    }
    final open = readOpen(p);
    if (open != null) return _open(open, from);
    final piece = readHoldPiece(p);
    if (piece != null) _piece(piece, from);
  }

  void _open(BulkOpen o, CardAddress from) {
    final size = o.count * kSealedLength;
    if (budget <= 0 || o.count == 0 || size > budget || _resting) {
      _send(heldPacket(o.tag, 0, cls), from);
      return;
    }
    // Without a valid proof for one of the own addresses: silently nothing,
    // like the post box (§8.2).
    final to = _own()
        .where((a) => holdProofCarries(o.tag, o.count, a, o.proof))
        .firstOrNull;
    if (to == null) return;
    // Without evidenced reachability (§9.4, §11.8a): a phone needs the
    // family of THIS address open from outside ("a phone whose address the
    // check of §8.1 found open"), a desktop evidence at all.
    if (_phone ? !_reachable(to) : !_proven()) {
      _send(heldPacket(o.tag, 0, cls), from);
      return;
    }
    final k = tagHex(o.tag);
    var h = _held[k];
    if (h == null) {
      if (_held.length >= kIdentifiersAtMost) _evict(_held.keys.first);
      h = _held[k] = _Held(o.tag, DateTime.now(), 0);
    }
    // One paid proof per share (D-30): a second share for this node under
    // another of its addresses adds its count; a repeated open does not.
    if (h.proofs.add(tagHex(o.proof))) h.allowed += o.count;
    if (!h.from.any((x) => x.equal(from))) h.from.add(from);
    _room(size, k);
    _indexSave();
    _send(heldPacket(o.tag, o.count, cls), from);
  }

  void _piece(BulkPiece x, CardAddress from) {
    final h = _held[tagHex(x.tag)];
    if (h == null || !h.from.any((x) => x.equal(from)) || _resting) return;
    final key = x.stripe << 8 | x.no;
    if (x.no >= kHoldersAtMost || h.fresh.containsKey(key)) return;
    if (h.held >= h.allowed) return; // more than announced: discarded
    if (_used + kSealedLength > budget) _room(kSealedLength, tagHex(x.tag));
    if (_used + kSealedLength > budget) return;
    h.fresh[key] = x.sealed;
    _used += kSealedLength;
    h.quiet?.cancel();
    h.quiet = Timer(kHeldQuiet, () => _rest(h));
  }

  /// The intake has come to rest: to disk, and tell the sender what is
  /// really held (the second `0x53`).
  void _rest(_Held h) {
    h.quiet = null;
    if (!identical(_held[tagHex(h.tag)], h)) return; // evicted meanwhile
    _flush(h);
    _indexSave();
    report?.call('Bulk: holder took ${tagHex(h.tag).substring(0, 8)}: '
        '${h.held} of ${h.allowed} piece(s) held, from ${h.from.join(', ')}');
    for (final to in h.from) {
      _send(heldPacket(h.tag, min(h.held, 0xFFFF), cls), to);
    }
  }

  void _flush(_Held h) {
    final disk = _disk;
    if (disk == null || h.fresh.isEmpty) return;
    final stored = disk.piecesLoad(h.tag);
    final have = {for (final s in stored) s.stripe << 8 | s.no};
    for (final e in h.fresh.entries) {
      if (have.add(e.key)) {
        stored.add((stripe: e.key >> 8, no: e.key & 0xFF, sealed: e.value));
      } else {
        _used -= kSealedLength; // a repeat of a piece already on disk
      }
    }
    h.fresh.clear();
    h.onDisk = stored.length;
    disk.piecesSave(h.tag, stored);
  }

  /// Frees [need] bytes by evicting the oldest pieces, never those of
  /// [except]. At least 1/16 of the budget goes at once, so that a full
  /// cache does not rewrite a file for every arriving piece.
  void _room(int need, String except) {
    var over = _used + need - budget;
    if (over <= 0) return;
    over = max(over, budget ~/ 16);
    for (final k in _held.keys.toList()) {
      if (over <= 0) break;
      if (k == except) continue;
      final h = _held[k]!;
      final n = (over + kSealedLength - 1) ~/ kSealedLength;
      if (n >= h.held) {
        over -= h.held * kSealedLength;
        evicted += h.held;
        _evict(k);
      } else {
        _shorten(h, n);
        evicted += n;
        over -= n * kSealedLength;
      }
    }
    _indexSave();
    report?.call('Bulk: cache full — oldest pieces evicted (§20.2)');
  }

  void _shorten(_Held h, int n) {
    _flush(h);
    final stored = _disk?.piecesLoad(h.tag) ?? [];
    final rest = stored.sublist(min(n, stored.length));
    _used -= (stored.length - rest.length) * kSealedLength;
    h.onDisk = rest.length;
    _disk?.piecesSave(h.tag, rest);
  }

  void _evict(String k) {
    final h = _held.remove(k);
    if (h == null) return;
    h.quiet?.cancel();
    _used -= h.held * kSealedLength;
    _disk?.piecesDrop(h.tag);
  }

  /// One pass for [to]: every piece held under [tag] from stripe [from] on,
  /// then the end of the pass (`0x55` with the count, `bulk_piece.dart`) —
  /// the recipient's event to ask again for what is still open (S398-W1).
  Future<void> _answer(Uint8List tag, CardAddress to, int from) async {
    final k = tagHex(tag);
    final h = _held[k];
    if (h == null || h.held == 0) {
      _send(tagPacket(kinds.kBulkNothingHere, tag), to);
      return;
    }
    final running = '$k@$to';
    if (_answering.length >= kAnswersAtMost || !_answering.add(running)) return;
    final began = DateTime.now();
    final short = k.substring(0, 8);
    var sent = 0;
    try {
      final all = <StoredPiece>[
        ...?_disk?.piecesLoad(tag),
        for (final e in h.fresh.entries)
          (stripe: e.key >> 8, no: e.key & 0xFF, sealed: e.value),
      ];
      if (all.isEmpty) {
        _send(tagPacket(kinds.kBulkNothingHere, tag), to);
        return;
      }
      final pass = [for (final s in all) if (s.stripe >= from) s];
      report?.call('Bulk: holder answers $short to $to from stripe $from: '
          '${pass.length} of ${all.length} piece(s)');
      final step = max(1, pass.length ~/ 10);
      for (final s in pass) {
        await _pace.turn();
        _send(piecePacket((tag: tag, stripe: s.stripe, no: s.no, sealed: s.sealed)),
            to);
        if (++sent % step == 0 && sent < pass.length) {
          report?.call('Bulk: holder $short to $to: $sent of ${pass.length} '
              'piece(s) sent');
        }
      }
      _send(passEndPacket(tag, sent), to);
      report?.call('Bulk: holder answered $short to $to: $sent piece(s) in '
          '${DateTime.now().difference(began).inMilliseconds} ms, end of pass '
          'sent');
    } finally {
      _answering.remove(running);
    }
  }

  void _expire() {
    final limit = DateTime.now().subtract(kTtlMedia);
    final old = [
      for (final e in _held.entries)
        if (e.value.inserted.isBefore(limit)) e.key
    ];
    if (old.isEmpty) return;
    old.forEach(_evict);
    _indexSave();
  }

  void _load() {
    final disk = _disk;
    if (disk == null) return;
    final all = disk.indexLoad()
      ..sort((a, b) => a.inserted.compareTo(b.inserted));
    for (final x in all) {
      if (x.held == 0) continue;
      _held[tagHex(x.tag)] = _Held(x.tag, x.inserted, x.allowed, x.held);
      _used += x.held * kSealedLength;
    }
    disk.orphansDrop(_held.values.map((h) => h.tag));
    _expire();
    if (_used > budget) _room(0, '');
  }

  void _indexSave() => _disk?.indexSave(_held.values.map((h) => h.index));

  /// Everything still in memory to disk — at stop. A transfer in intake
  /// keeps what arrived; its sender learns the count at its next attempt.
  void stop() {
    for (final h in _held.values) {
      h.quiet?.cancel();
      _flush(h);
    }
    _indexSave();
  }
}
