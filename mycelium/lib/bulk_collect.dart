/// The recipient of lane 3 (§9.4 "Lane 3, collection"): asks the holders
/// the announcement names, opens what comes back and assembles the object.
///
/// `0x54` goes to each named holder when [BulkCollector.collect] is called
/// and at the edges of §8.2 — start, network change, a new neighbour, the
/// application opened. Those edges reach this file through
/// `node_collect_edge.dart`; there is no timer here (§5.4, D-9).
///
/// ROUNDS (S398-W1, §11.3 pattern). A holder ends every pass with a `0x55`
/// that carries its count ("end of pass", `bulk_piece.dart`). When EVERY
/// named holder has ended the round (end of pass or "nothing here") and
/// the object is still open, the collector asks again at once, naming the
/// first open stripe (`0x54` "from stripe"). A round that completes no new
/// stripe counts; after [kCollectRoundsAtMost] such rounds the collection
/// fails "incomplete (x of y stripes)". A holder that sends no end mark at
/// all leaves the round open — then the next edge asks again. The events
/// are packets, never a clock.
///
/// A piece opens under `HKDF(K_T, "bulk/seal")` or is discarded. With
/// seven pieces in every stripe the object is assembled and checked against
/// the SHA-256 of the announcement.
///
/// ONE COLLECTOR PER IDENTITY (S401; §4.5.3, §21.4.1). A transfer belongs
/// to one identity: its callbacks, and its opened blocks in THAT identity's
/// folder under its key. Two identities of a device in one group collect
/// the same `K_T` each for itself; the holder answers one address once.
///
/// RESTART (S398-W1, S401): complete stripes survive — encrypted chunks
/// ([BulkDisk.openedAppend]), at least [kOpenedChunkStripes] stripes or
/// 1/32 of the object, and at every end of a pass. WHICH collections are
/// open does NOT stand here: the layer above keeps them in the store of
/// the identity — the one source — and hands each over again with
/// [collect]; only then is it open here, takes what its chunks hold and
/// asks from the first open stripe. [stash] keeps pieces of a fallen-back
/// stream (§17.6) before the collection exists.
///
/// BOUNDS (§20.2): [kCollectionsAtMost] open collections per identity (one
/// more evicts the oldest, "displaced"); older than `TTL_media` fails at
/// the next edge; every named holder "nothing here" fails at once; opened
/// blocks on disk at most [kOpenedOnDiskAtMost] (256 MiB) over all
/// collections of all identities of the device — beyond that stripes stay
/// in memory and are asked again after a restart.
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/bulk_collection.dart';
import 'package:mycelium/bulk_disk.dart';
import 'package:mycelium/bulk_piece.dart';
import 'package:mycelium/card.dart' show CardAddress;
import 'package:mycelium/media.dart'
    show kBlock, kPiecesPerStripe, kStripeWidth, objectFromPieces;

/// The callback types stand with the collection (`bulk_collection.dart`);
/// every existing caller still imports only this file.
export 'package:mycelium/bulk_collection.dart'
    show OnBulkObject, OnBulkFailure, OnBulkProgress;

/// At most this many collections are open at once.
const int kCollectionsAtMost = 32;

/// Rounds without a new complete stripe before "incomplete".
const int kCollectRoundsAtMost = 3;

/// Opened blocks on disk over all collections (256 MiB).
const int kOpenedOnDiskAtMost = 256 << 20;

/// Complete stripes per chunk on disk, at least.
const int kOpenedChunkStripes = 64;

class BulkCollector {
  final void Function(Uint8List packet, CardAddress to) _send;
  final BulkDisk? _disk;
  final void Function(String)? report;

  /// Opened blocks the other identities of this device have on disk — the
  /// bound [kOpenedOnDiskAtMost] holds for the device.
  final int Function()? _others;

  /// Pieces that arrived over the wire, all collections (statistics).
  int piecesReceived = 0;

  final Map<String, BulkCollection> _open = {};
  int _onDisk = 0;

  /// [disk]: the folder of THIS identity under its key. Nothing is open
  /// after construction — see RESTART in the header.
  BulkCollector({
    required void Function(Uint8List packet, CardAddress to) send,
    BulkDisk? disk,
    int Function()? othersOnDisk,
    this.report,
  })  : _send = send,
        _disk = disk,
        _others = othersOnDisk {
    _disk?.openedOrphansDrop(const [], kTtlMedia);
    _onDisk = _disk?.openedBytes() ?? 0;
  }

  int get openCollections => _open.length;

  /// Bytes of opened blocks this identity has on disk.
  int get openedOnDisk => _onDisk;

  bool _full(int stripes) =>
      (_others?.call() ?? 0) + _onDisk + stripes * kPiecesPerStripe * (kBlock + 1) >
      kOpenedOnDiskAtMost;

  /// The layer above names every transfer its store still knows ([tags]);
  /// opened blocks of any other go NOW. The store is the one source for
  /// what is open (S401): a block without an entry there belongs to nothing.
  void keepOnly(Iterable<Uint8List> tags) {
    _disk?.openedOrphansDrop(
        [...tags, for (final c in _open.values) c.tag], Duration.zero);
    _onDisk = _disk?.openedBytes() ?? 0;
  }

  /// The identity left the host (deregistered): nothing is asked, taken or
  /// reported for it any more. Its chunks stay where they are — they go
  /// with its folder, or serve it when it registers again.
  void close() => _open.clear();

  /// Starts collecting the object of [transferKey] from [holders] (at most
  /// eleven) and asks every holder NOW; again for the same transfer it
  /// replaces the callbacks and asks again. Returns the identifier.
  /// [seed]: blocks a fallen-back lane 2 attempt opened (§17.6), taken with
  /// what [stash] kept on disk; complete — assembled after this returned.
  /// [started]: when the announcement came — `TTL_media` runs from there,
  /// also across a restart (default: now).
  Uint8List collect({
    required Uint8List transferKey,
    required int length,
    required Uint8List sha256,
    required List<CardAddress> holders,
    OnBulkObject? onObject,
    OnBulkFailure? onFailure,
    OnBulkProgress? progress,
    Map<int, Map<int, Uint8List>>? seed,
    DateTime? started,
  }) {
    if (transferKey.length != kTransferKeyLength || sha256.length != 32 ||
        length <= 0 || holders.isEmpty) {
      throw ArgumentError('collect: K_T 32 B, SHA-256 32 B, length > 0, '
          'at least one holder');
    }
    final tag = bulkTag(transferKey);
    final k = tagHex(tag);
    final fresh = !_open.containsKey(k);
    final c = _open[k] ??
        BulkCollection(
          transferKey: transferKey,
          length: length,
          sha256: Uint8List.fromList(sha256),
          started: started ?? DateTime.now(),
          holders: holders.take(kHoldersAtMost).toList(),
        );
    c
      ..onObject = onObject ?? c.onObject
      ..onFailure = onFailure ?? c.onFailure
      ..progress = progress ?? c.progress;
    if (fresh) {
      if (_open.length >= kCollectionsAtMost) {
        _fail(_open.values.first, 'displaced — more than $kCollectionsAtMost '
            'open collections (§20.2)');
      }
      _open[k] = c;
      final kept = _disk?.openedLoad(tag);
      if (kept != null) _take(c, kept, save: false);
      if (c.complete > 0) {
        report?.call('Bulk: collection ${c.short} resumed from disk with '
            '${c.complete} of ${c.stripes} stripes');
      }
    }
    if (seed != null) _take(c, seed, save: true);
    _persist(c, force: true);
    if (c.complete == c.stripes) {
      scheduleMicrotask(() => _open[k] == c ? _finish(c) : null);
      return tag;
    }
    _ask(c);
    return tag;
  }

  /// Keeps [pieces] of a fallen-back stream (§17.6): into the open
  /// collection, or on disk for the one to come (survives a restart).
  void stash(Uint8List tag, Map<int, Map<int, Uint8List>> pieces) {
    final c = _open[tagHex(tag)];
    if (c != null) {
      if (_take(c, pieces, save: true)) {
        scheduleMicrotask(() => _open[tagHex(tag)] == c ? _finish(c) : null);
      }
      _persist(c, force: true);
      return;
    }
    final disk = _disk;
    if (disk == null || pieces.isEmpty) return;
    if (_full(pieces.length)) {
      return report?.call('Bulk: stash ${tagHex(tag).substring(0, 8)} not '
          'kept — opened blocks on disk at the bound');
    }
    _onDisk += disk.openedAppend(tag, pieces);
  }

  /// Takes [seed] into [c]; `true` if every stripe is then complete.
  bool _take(BulkCollection c, Map<int, Map<int, Uint8List>> seed,
      {required bool save}) {
    final before = c.complete;
    for (final e in seed.entries) {
      if (e.key < 0 || e.key >= c.stripes) continue;
      final there = c.per[e.key] ??= {};
      if (there.length >= kStripeWidth) continue;
      for (final b in e.value.entries) {
        if (there.length >= kStripeWidth) break;
        if (b.key < 0 || b.key >= kPiecesPerStripe || b.value.length != kBlock) {
          continue;
        }
        there[b.key] ??= Uint8List.fromList(b.value);
      }
      if (there.length == kStripeWidth) {
        c.complete++;
        if (save) c.unsaved.add(e.key);
      }
    }
    if (c.complete > before) c.progress?.call(c.tag, c.complete, c.stripes);
    return c.complete == c.stripes;
  }

  /// Complete stripes, all stripes, pieces opened, pieces over the wire in
  /// this run; `null` if not open.
  ({int complete, int stripes, int pieces, int received})? status(
      Uint8List tag) {
    final c = _open[tagHex(tag)];
    if (c == null) return null;
    return (
      complete: c.complete,
      stripes: c.stripes,
      pieces: c.per.values.fold(0, (a, m) => a + m.length),
      received: c.received,
    );
  }

  /// Gives a collection up (user, or the layer above: the sender gave up).
  /// Local only; ends with [onFailure], naming what was missing.
  void abandon(Uint8List tag) {
    final c = _open[tagHex(tag)];
    if (c == null) {
      // Not open, but a stash or the chunks of the last run may lie there.
      _disk?.openedDrop(tag);
      _onDisk = _disk?.openedBytes() ?? 0;
      return;
    }
    _fail(c, 'abandoned — ${c.stripes - c.complete} of ${c.stripes} stripes '
        'below $kStripeWidth pieces');
  }

  /// The edge (§8.2): every open collection asks its holders once.
  void ask() {
    final limit = DateTime.now().subtract(kTtlMedia);
    for (final c in _open.values.toList()) {
      if (c.started.isBefore(limit)) {
        _fail(c, 'expired — older than TTL_media');
      } else {
        c.rounds = 0; // an edge is a fresh start of the rounds
        _ask(c);
      }
    }
  }

  /// A round: every named holder, from the first open stripe on.
  void _ask(BulkCollection c) {
    c
      ..nothing.clear()
      ..ended.clear()
      ..roundStart = c.complete;
    var from = 0;
    while (from < c.stripes && (c.per[from]?.length ?? 0) >= kStripeWidth) {
      from++;
    }
    report?.call('Bulk: collection ${c.short} asks ${c.holders.length} '
        'holder(s) from stripe $from (${c.complete} of ${c.stripes} complete, '
        'round ${c.rounds + 1})');
    for (final h in c.holders) {
      _send(collectPacket(c.tag, from), h);
    }
  }

  void receive(Uint8List p, CardAddress from) {
    if (p.isEmpty) return;
    final n = readNothingHere(p);
    if (n != null) return _nothingOrEnd(n, from);
    final x = readPiece(p);
    final c = x == null ? null : _open[tagHex(x.tag)];
    if (x == null || c == null) return;
    if (x.stripe >= c.stripes || x.no >= kPiecesPerStripe) return;
    c.received++;
    piecesReceived++;
    final there = c.per[x.stripe] ??= {};
    if (there.length >= kStripeWidth || there.containsKey(x.no)) return;
    final block = pieceOpen(c.seal, c.tag, x.stripe, x.no, x.sealed);
    if (block == null) {
      report?.call('Bulk: piece ${x.stripe}/${x.no} of ${c.short} '
          'does not open — discarded');
      return;
    }
    there[x.no] = block;
    c.fromHolder['$from'] = (c.fromHolder['$from'] ?? 0) + 1;
    if (there.length < kStripeWidth) return;
    c.complete++;
    c.unsaved.add(x.stripe);
    _persist(c);
    c.progress?.call(c.tag, c.complete, c.stripes);
    final d = c.complete * 10 ~/ c.stripes;
    if (d > c.decile && c.complete < c.stripes) {
      c.decile = d;
      report?.call('Bulk: collection ${c.short}: ${c.complete} of ${c.stripes} '
          'stripes, pieces per holder ${c.fromHolder}');
    }
    if (c.complete == c.stripes) _finish(c);
  }

  void _nothingOrEnd(({Uint8List tag, bool ended, int sent}) n, CardAddress from) {
    final c = _open[tagHex(n.tag)];
    if (c == null) return;
    c.ended.add('$from'); // this round: done (end of pass or nothing here)
    if (!n.ended) {
      c.nothing.add('$from');
      if (c.holders.every((h) => c.nothing.contains('$h'))) {
        return _fail(c, 'none of the ${c.holders.length} named '
            'holders holds anything');
      }
    } else {
      report?.call('Bulk: collection ${c.short}: $from ended its pass with '
          '${n.sent} piece(s); ${c.complete} of ${c.stripes} stripes');
      _persist(c, force: true);
    }
    if (!c.holders.every((h) => c.ended.contains('$h'))) return;
    // Every named holder has ended this round, and stripes are still open.
    c.rounds = c.complete > c.roundStart ? 0 : c.rounds + 1;
    if (c.rounds >= kCollectRoundsAtMost) {
      return _fail(c, 'incomplete (${c.complete} of ${c.stripes} stripes) — '
          '${c.rounds} rounds without a new stripe');
    }
    _ask(c);
  }

  /// Complete stripes to disk: in chunks, or everything with [force].
  void _persist(BulkCollection c, {bool force = false}) {
    final disk = _disk;
    if (disk == null || c.unsaved.isEmpty) return;
    if (!force && c.unsaved.length < max(kOpenedChunkStripes, c.stripes ~/ 32)) {
      return;
    }
    if (_full(c.unsaved.length)) {
      report?.call('Bulk: collection ${c.short}: ${c.unsaved.length} stripe(s) '
          'stay in memory — opened blocks on disk at the bound');
      c.unsaved.clear();
      return;
    }
    _onDisk += disk.openedAppend(c.tag, {for (final s in c.unsaved) s: c.per[s]!});
    c.unsaved.clear();
  }

  void _finish(BulkCollection c) {
    _remove(c);
    final Uint8List object;
    try {
      object = objectFromPieces(c.per, c.length);
    } on Object catch (e) {
      return c.onFailure?.call(c.tag, 'assembly failed: $e');
    }
    final sum = SodiumFFI().sha256(object);
    for (var i = 0; i < 32; i++) {
      if (sum[i] != c.sha256[i]) {
        return c.onFailure
            ?.call(c.tag, 'SHA-256 does not match the announcement');
      }
    }
    report?.call('Bulk: collected ${c.short}: ${c.stripes} stripes, '
        '${c.received} piece(s) over the wire in this run, per holder '
        '${c.fromHolder}, ${DateTime.now().difference(c.began).inMilliseconds} ms');
    c.onObject?.call(c.tag, object);
  }

  void _fail(BulkCollection c, String why) {
    _remove(c);
    report?.call('Bulk: collection ${c.short} failed — $why');
    c.onFailure?.call(c.tag, why);
  }

  void _remove(BulkCollection c) {
    if (_open.remove(tagHex(c.tag)) == null) return;
    _disk?.openedDrop(c.tag);
    _onDisk = _disk?.openedBytes() ?? 0;
  }
}
