// The local outbox (§21.2) — the book of own, not yet proven
// messages.
//
// ── WHAT §21.2 DEMANDS, LITERALLY ───────────────────────────────────
//
//   "A node's own cells stay local until their placement is
//    substantiated: **the cell remains in the local outbox until >= 2
//    placement acknowledgments from independent relays are in hand
//    (§9).** No timer retry, no route state, no persistent send queue."
//
// And §21.8 lists it as an item ON DISK: "Own, not-yet-placed
// cells (outbox) | own messages including recipient | under the DB key".
//
// THAT IS NO CONTRADICTION, but two different things. What falls is the
// V3 `SendQueue` — a queue with route state, timer and
// retry counter per address. What stays is a book without its own
// clock: it holds, it does not send by itself.
//
// ── HOLDING IS NOT SENDING ──────────────────────────────────────────
//
// The sentence says the cell STAYS until two receipts — not that
// it repeatedly goes out until then. The difference carries the whole
// design:
//
//   HOLD     always, until `placed` / `delivered` / `expired`.
//   OFFER    only if the previous attempt DEMONSTRABLY left
//            nothing behind (`independentRelays == 0`).
//
// With ONE receipt present, re-offering is strictly worse than
// holding: `DeliveryRecord.noteAttempt` deletes the proofs of the previous
// attempt (§22.5.1 refinement 3 — "acknowledgments from different
// sealing attempts do not combine"), so the re-offer costs
// `m x R` = 60 cells AND destroys the one proof one had.
// Meanwhile the cell rests with the acknowledging relay and waits for the
// harvest — case (j) from §9.2, "an offline recipient is not an error".
//
// ── THE PLAINTEXT FRAME, NOT THE CELL ───────────────────────────────
//
// What is stored is what `sendToUser` hands to `V41Host.sendFrame`:
// the serialised `ApplicationFrameV3`. NOT the sealed cells.
// §22.5.1: the re-offer "seals afresh" — new ephemeral
// key, new one-time prekey, new split. Whoever
// stored the cells could only send them out again unchanged, and
// the same seal twice on the wire is a recognition feature.
//
// The frame is plaintext and therefore goes exclusively through
// `FileEncryption` under the identity-derived key — §21.8
// demands exactly that.
//
// ── THE MODE IS NOT STORED ──────────────────────────────────────────
//
// It is re-read on re-offer. A chat switched to
// Secure in the meantime must not execute a stored Speed decision
// — that would be the silent mode switch that the invariant
// (owner, 30.08.) forbids. The reverse direction would be equally
// wrong: a stored Secure decision would cost 60 cells for
// a chat that has long been on Speed.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/util/hex.dart';

/// How often an unproven message is re-offered at most.
///
/// ── WHY A CAP IS NEEDED AT ALL ─────────────────────────────────────
///
/// There are network situations in which `independentRelays` stays 0 permanently,
/// ALTHOUGH the cell rests: `PlacementAck.partitions` is empty if no
/// interpretable entry record exists for the storing relay
/// (`delivery_api.dart`), and `Partition.independentCount` does not count empty
/// sets as independence. Without a cap the re-offer would
/// then run again on every readiness change — 60 cells and 8 minutes
/// egress per run, without anything ever changing.
///
/// THREE covers the three situations in which really nothing rests: a
/// restart and two network changes. The worst-case price is in
/// `docs/v4-redesign/S360-outbox-entwurf.md` §6 question 1 and was put to the
/// owner there: up to 180 cells / 211 KiB / 24 min egress per
/// message.
const int kMaxOutboxOffers = 3;

/// At most how many entries the outbox holds.
const int kMaxOutboxEntries = 2048;

/// And how many bytes of frames. **Whatever applies first, applies** —
/// the same double rule that §21.3.3 point 1 sets for the mobile
/// delivery store.
///
/// The counter is necessary because a frame lies between ~250 B (text) and
/// `kMaxSplitPayloadBytes` = 32 KiB. 2048 entries at the
/// upper bound would be 64 MB; with the byte cap it is 8 MB, i.e. 256
/// entries in the worst case. Owner question 2.
const int kMaxOutboxBytes = 8 * 1024 * 1024;

/// An entry: an own message whose placement is not proven.
final class V41OutboxEntry {
  /// The identifier under which acknowledgement happens — the same one that
  /// `V41Host.sendFrame` passes down and that comes back in the placement receipt.
  final Uint8List messageId;

  /// The recipient. From it the re-offer forms the pair designator
  /// and `K_AB` anew — the key is NOT stored, it is in
  /// the pair registry and would only lie here a second time.
  final Uint8List recipientUserId;

  /// The serialised `ApplicationFrameV3` — PLAINTEXT, see file header.
  final Uint8List frame;

  /// The group, if it is one. The re-offer needs it to read the
  /// mode (§12) at the same place as `sendToUser`:
  /// group choice from `_groups`, DM choice from `_contacts`.
  final String? groupIdHex;

  /// The KEM overrides for group and channel members that are not
  /// a contact at all (their keys came via `GROUP_INVITE`).
  ///
  /// Without them the re-offer could not seal for exactly these recipients
  /// — `sendToUser` resolves them on the first attempt from the
  /// caller, and the caller is long gone by then.
  final Uint8List? x25519Pk;
  final Uint8List? mlKemPk;

  /// The name of the message kind — only for log and diagnosis. The
  /// re-offer does not read it: it passes the finished frame through.
  final String messageType;

  /// When the first send attempt was. Carries the deadline (§21.5.5).
  final int createdAtMs;

  /// How often it has already been re-offered. Cap: [kMaxOutboxOffers].
  int offers;

  /// The 31-day retention class (§21.1, `kRetentionManagement`).
  ///
  /// ── WHY IT IS HERE, WHERE THE MODE IS NOT ──────────────────────────
  ///
  /// The mode is re-read on re-offer (file header); the
  /// class is not, and both for the same reason: the mode is an
  /// ongoing choice of the user, the class a fixed property of THIS
  /// message.
  ///
  /// It cannot be reconstructed. The entry keeps only the NAME of the
  /// message kind, and `MTV3_KEY_ROTATION_BROADCAST` carries both the
  /// routine rotation (§4.5.4, "an ordinary delivery") and the
  /// emergency rotation (management class). Without this field a
  /// re-offered emergency rotation would silently rest 3 instead of 31 days.
  final bool management;

  V41OutboxEntry({
    required this.messageId,
    required this.recipientUserId,
    required this.frame,
    required this.messageType,
    required this.createdAtMs,
    this.groupIdHex,
    this.x25519Pk,
    this.mlKemPk,
    this.offers = 0,
    this.management = false,
  });

  String get messageIdHex => messageId.hex;

  /// What this entry weighs in the memory cap. Only the frame counts —
  /// the other fields together are under 1.3 KB and do not fluctuate.
  int get weightBytes => frame.length;

  Map<String, dynamic> toJson() => {
        'messageId': base64.encode(messageId),
        'recipientUserId': base64.encode(recipientUserId),
        'frame': base64.encode(frame),
        'messageType': messageType,
        'createdAtMs': createdAtMs,
        'offers': offers,
        if (groupIdHex != null) 'groupIdHex': groupIdHex,
        if (x25519Pk != null) 'x25519Pk': base64.encode(x25519Pk!),
        if (mlKemPk != null) 'mlKemPk': base64.encode(mlKemPk!),
        // ONLY IF SET, so that an existing stock stays byte-identical and
        // the file is not rewritten on every start.
        if (management) 'management': true,
      };

  /// Reads an entry. Throws on a broken record — the caller
  /// then skips it individually instead of losing the whole file
  /// (the same treatment as in `_loadOutbox` for the V3 version).
  static V41OutboxEntry fromJson(Map<String, dynamic> j) {
    Uint8List b(String k) => base64.decode(j[k] as String);
    Uint8List? bo(String k) =>
        j[k] == null ? null : base64.decode(j[k] as String);
    final f = b('frame');
    if (f.isEmpty) throw const FormatException('empty frame');
    final id = b('messageId');
    if (id.isEmpty) throw const FormatException('empty identifier');
    return V41OutboxEntry(
      messageId: id,
      recipientUserId: b('recipientUserId'),
      frame: f,
      messageType: j['messageType'] as String? ?? 'UNBEKANNT',
      createdAtMs: j['createdAtMs'] as int? ?? 0,
      offers: j['offers'] as int? ?? 0,
      groupIdHex: j['groupIdHex'] as String?,
      x25519Pk: bo('x25519Pk'),
      mlKemPk: bo('mlKemPk'),
      // AN OLD ENTRY WITHOUT THE FIELD IS ORDINARY, not management. The
      // fallback thus goes to the SHORT deadline — the direction in which
      // an error may run here: an ordinary cell falls
      // earlier, instead of an uninvolved message resting 31 days with
      // twenty foreign relays.
      management: j['management'] as bool? ?? false,
    );
  }
}

/// The book itself.
///
/// It has NO clock and NO timer. Whoever lets it drain
/// does so at an edge (§4.2 of the design): restart,
/// readiness change, proven input from the other side. The class
/// itself knows no clock except the deadline that the caller
/// passes in.
final class V41Outbox {
  final int maxEntries;
  final int maxBytes;
  final int maxOffers;

  /// Insertion-ordered (Dart map literals are), so that the cap
  /// displaces the OLDEST entry first.
  final Map<String, V41OutboxEntry> _entries = <String, V41OutboxEntry>{};

  // ── THE WRITE JOURNAL (S366) ─────────────────────────────────────
  //
  // Until S366 the mark was a mere `bool dirty`, and the caller
  // then rewrote the WHOLE book (`toJson()` into a file).
  // Since the outbox lives in the store, that is the wrong granularity:
  // 2048 entries are the cap, a frame measures up to 32 KiB, and
  // a single acknowledged message would otherwise cost up to 8 MB of
  // rewriting.
  //
  // MORE IMPORTANT THAN THE COST IS WHAT THE JOURNAL PREVENTS. With
  // full writes a silent data destruction was built in: if
  // `loadV41Outbox` failed, the book stayed empty, the next own
  // message set `dirty`, and the write replaced the
  // entire parked stock with this ONE entry. There was no latch
  // against it. With the journal it can no longer need one:
  // only what this session touched is written —
  // foreign rows are unreachable, even if loading failed.
  final Set<String> _changed = <String>{};
  final Set<String> _removed = <String>{};

  /// Whether there is anything to write at all.
  bool get dirty => _changed.isNotEmpty || _removed.isNotEmpty;

  /// The identifiers whose row is to be rewritten.
  Iterable<String> get changedKeys => _changed;

  /// The identifiers whose row is to be deleted.
  Iterable<String> get removedKeys => _removed;

  /// To be called by the caller AFTER a successful write. A failure
  /// leaves the journal in place and the next attempt catches up —
  /// the same order as with `V41Host.markPrekeyStateSaved`.
  void markSaved() {
    _changed.clear();
    _removed.clear();
  }

  /// Both sets are mutually exclusive: what happened last
  /// applies. Otherwise an identifier would be pending both for writing and for
  /// deletion, and the order in the caller would decide the content.
  void _markChanged(String k) {
    _removed.remove(k);
    _changed.add(k);
  }

  void _markRemoved(String k) {
    _changed.remove(k);
    _removed.add(k);
  }

  /// How many entries the cap has already displaced. > 0 is a
  /// finding, not operational noise: it means an own message has
  /// fallen out of the book before its placement was proven.
  int evicted = 0;

  /// How many entries have reached the attempt cap and are only
  /// held.
  int exhausted = 0;

  V41Outbox({
    this.maxEntries = kMaxOutboxEntries,
    this.maxBytes = kMaxOutboxBytes,
    this.maxOffers = kMaxOutboxOffers,
  });

  int get length => _entries.length;

  int get bytes =>
      _entries.values.fold<int>(0, (a, e) => a + e.weightBytes);

  Iterable<V41OutboxEntry> get entries => _entries.values;

  V41OutboxEntry? lookup(String messageIdHex) => _entries[messageIdHex];

  /// Takes a message into the book.
  ///
  /// IDEMPOTENT over the identifier: the re-offer submits the same
  /// message again, and a second entry would reset the counter
  /// [V41OutboxEntry.offers] — the cap would then be none.
  void add(V41OutboxEntry e) {
    final present = _entries[e.messageIdHex];
    if (present != null) return;
    _entries[e.messageIdHex] = e;
    _markChanged(e.messageIdHex);
    _trim();
  }

  /// Takes a message out. `true` if it was in.
  bool remove(String messageIdHex) {
    final route = _entries.remove(messageIdHex) != null;
    if (route) _markRemoved(messageIdHex);
    return route;
  }

  /// Which entries may be re-offered NOW.
  ///
  /// [hasProof] answers for an identifier "does something rest anywhere?" —
  /// in the service that is `DeliveryRecord.independentRelays > 0`. The
  /// outbox does NOT recompute that itself: the verdict on a
  /// delivery record is in the record, and two verdicts on the same state
  /// would be the double bookkeeping that `delivery_state.dart` just
  /// avoids.
  ///
  /// [freeFrame] is the space in the control queue
  /// (`kMaxControlBacklog - pendingControl`), [frameProTemplate] what a
  /// re-offer costs (`m x R` = 60 with Secure). Both together are
  /// the egress cap: WITHOUT IT THE DRAIN IS A DEFECT — three
  /// messages at once queue 180 frames into a queue of 120,
  /// and `CoverStream` then discards the OLDEST whole group, i.e.
  /// possibly a message that was regularly in transit.
  ///
  /// The counter [V41OutboxEntry.offers] is NOT incremented here — that
  /// is done by [markOffered] after the send was really accepted.
  /// Were it here, a rejected attempt would count too, and the
  /// cap would run empty without anything ever going out.
  List<V41OutboxEntry> due({
    required bool Function(String messageIdHex) hasProof,
    required int freeFrame,
    required int frameProTemplate,
  }) {
    if (frameProTemplate <= 0) return const <V41OutboxEntry>[];
    final out = <V41OutboxEntry>[];
    var budget = freeFrame;
    for (final e in _entries.values) {
      if (budget < frameProTemplate) break;
      if (e.offers >= maxOffers) continue;
      // THE ONE CONDITION (§21.2 read as "hold, don't send"):
      // only what DEMONSTRABLY rests nowhere. See file header.
      if (hasProof(e.messageIdHex)) continue;
      out.add(e);
      budget -= frameProTemplate;
    }
    return out;
  }

  /// Books an actually accepted re-offer.
  void markOffered(String messageIdHex) {
    final e = _entries[messageIdHex];
    if (e == null) return;
    e.offers++;
    if (e.offers >= maxOffers) exhausted++;
    _markChanged(messageIdHex);
  }

  /// Throws away everything older than [ttl]. The caller says when
  /// now is — this class holds no clock.
  ///
  /// The caller is `_checkMessageExpiry`, the same clock that sets the
  /// display to `expired`. Two deadlines would be two places at
  /// which the same message has a different age.
  int sweep({required int nowMs, required int ttlMs}) {
    final route = <String>[];
    for (final e in _entries.entries) {
      if (nowMs - e.value.createdAtMs > ttlMs) route.add(e.key);
    }
    for (final k in route) {
      _entries.remove(k);
      _markRemoved(k);
    }
    return route.length;
  }

  /// Holds both caps. Displacement is in INSERTION ORDER, i.e. the
  /// oldest entry first — the same rule as in the delivery register.
  void _trim() {
    var b = bytes;
    while (_entries.length > maxEntries || b > maxBytes) {
      if (_entries.isEmpty) break;
      final k = _entries.keys.first;
      final e = _entries.remove(k);
      if (e == null) break;
      _markRemoved(k);
      b -= e.weightBytes;
      evicted++;
    }
  }

  Map<String, dynamic> toJson() =>
      {for (final e in _entries.entries) e.key: e.value.toJson()};

  /// Loads a book. A broken record is SKIPPED, not thrown:
  /// a file that can no longer be opened would be the
  /// total loss of all parked messages.
  ///
  /// Returns how many records were skipped.
  int loadJson(Map<String, dynamic> j) {
    var skipped = 0;
    for (final e in j.entries) {
      try {
        final entry = V41OutboxEntry.fromJson(
            (e.value as Map).cast<String, dynamic>());
        _entries[entry.messageIdHex] = entry;
      } catch (_) {
        skipped++;
        // A BROKEN RECORD IS MARKED FOR DELETION, not only
        // skipped. With full writes it vanished by itself on the next
        // save; with individual writes it would otherwise stay
        // forever and be an error in the log again on every start,
        // without anything ever clearing it.
        _markRemoved(e.key);
      }
    }
    // What the cap displaces here is likewise marked (`_trim`)
    // — the read book and the store must not diverge.
    _trim();
    return skipped;
  }

  /// Only for tests and diagnosis.
  void clear() {
    for (final k in _entries.keys) {
      _markRemoved(k);
    }
    _entries.clear();
  }
}
