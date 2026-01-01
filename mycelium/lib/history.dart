/// The history — what the delivery layer remembers of the conversation with
/// ONE peer, restart-proof. [memory.dart] remembers the own post box and the
/// contacts; what was still to be sent, and what had already come, was gone
/// after a restart. This file supplies that.
///
/// ── WHAT AN ENTRY KEEPS ────────────────────────────────────────────────
/// The CONTENT of a message lives in the application's message store and
/// nowhere else (V4.2 §21.4.2: "Message text and conversation metadata
/// always live in the message store; there is no setting that puts them
/// anywhere else"; §4.5.3 point 1). The history is not a second place for
/// it. It keeps the content of an OWN entry exactly while the entry is
/// OPEN and can still be sent again — the delivery layer sends it again
/// from here at an edge (§9.3) — and never that of a RECEIVED one. With
/// `delivered` or `failed` the content goes; identifier, time and state
/// stay.
///
/// Of a RECEIVED delivery this file keeps NOTHING any more (S403): its
/// identifier lives in the identity's received memory
/// ([HistoryStore.incomingKeep], §20.2, owner decision 02.10.2026, V-1 =
/// B) — not per peer, not with an arrival time, and not falling with the
/// contact. Until S403 it stood here as an entry with its peer, and a
/// deleted contact took the memory of its deliveries with it; the
/// guards of that statement are `mycelium/test/smoke_received_ids.dart`.
///
/// [History] enforces this itself, at every place an entry is written
/// ([History.append], [History.stateChange], [History.contentChange]), so
/// that no caller keeps content by omission — and at the load: a record
/// that is not open and still carries content loses it there
/// ([History.load]).
///
/// ── PLACED IS REMEMBERED ───────────────────────────────────────────────
/// An open own entry also keeps WHEN its deposit was placed — two holders
/// acknowledged it, the second `0x31` (§8.2) — because "placed (§8.2) is
/// final for the delivery layer: a placed message is not sent again at an
/// edge, not placed a second time and not closed as `failed`" (§9.3, D-44,
/// D-48). It is a moment on the record, not a fifth state: the entry stays
/// `in transit` (§9.1 "an implementation must not extend it"). Until S403
/// the result of a deposit was thrown away, and after a restart every open
/// entry went out and was placed once more. The copy kept for sending
/// again goes once the placing is older than [kPlacedCopyKept] — the
/// holders have dropped the message by then, and it reaches its recipient
/// through the recipient's request, from the application's store (§9.5);
/// the entry itself stays open until its acknowledgement. Who marks and who
/// drops: `mailbox_outbound.dart`.
///
/// ── WHERE IT IS KEPT: IN THE IDENTITY'S STORE ──────────────────────────
/// Until S401 every history was a file of its own in the mailbox's
/// directory. The norm has no such file: "Messages, conversations and their
/// indices live in an encrypted SQLite database, one per identity" (V4.2
/// §4.5.3 form 1), the own outbox lies "under the DB key" (§4.5.3), and for
/// the mailbox's directory §4.5.2 names contacts' delivery state, group
/// pairs, first contact and parked cells. So the records go where the
/// caller's store is: through a port ([HistoryStore], `history_store.dart`)
/// that the application serves with its message store. This file decides
/// WHICH records stand there and when one is written; it knows no file, no
/// key and no database.
///
/// ── ONE RECORD PER ENTRY ───────────────────────────────────────────────
/// A new message is ONE record written. A state change (a receipt arrived)
/// rewrites that ONE record — as a file it rewrote the whole history with
/// that peer, because a record in the middle of a file cannot be appended.
/// A deletion removes one record. A record is written whole or not at all
/// (the store's business); as a file, a record torn while appending made
/// the whole history with that peer unreadable.
///
/// ── THE ORDER ──────────────────────────────────────────────────────────
/// While the process runs, the entries stand in the order they were
/// appended. Loaded, they stand in the order of their TIME (for the same
/// millisecond: of their name in the store) — the store keeps records, not
/// a sequence. The time of an own entry is the moment it was written, so
/// both orders are the same one except within a millisecond. (A received
/// delivery keeps no entry here any more — file header — and therefore
/// no time either: V-4, no arrival time is stored anywhere.)
///
/// ── THE FILES OF THE BUILDS BEFORE S401 ────────────────────────────────
/// are taken over once and removed: `history_takeover.dart`.
library;

import 'dart:typed_data';

import 'package:mycelium/history_store.dart';
import 'package:mycelium/message.dart' show DeliveryState, kIdentifierLength;

/// The history cannot do what was asked: an identifier it does not know,
/// or — while an old file is read (`history_takeover.dart`) — a file that
/// is truncated, of another version, or sealed under another key.
class HistoryError implements Exception {
  final String reason;
  HistoryError(this.reason);
  @override
  String toString() => 'HistoryError: $reason';
}

/// A single message as it stands in the history with a peer.
class HistoryEntry {
  final Uint8List identifier;
  final bool outgoing;

  /// The payload, unchanged. This file does not interpret it — see
  /// file header and `message.dart`. EMPTY for every entry of a [History]
  /// that is not [open]: received, acknowledged or given up.
  final Uint8List content;
  final DateTime instant;

  /// Set only for [outgoing] — one of the four values from
  /// `message.dart`.
  final DeliveryState? state;

  /// Set only for an [open] entry that is PLACED: the moment two holders
  /// had acknowledged its deposit (file header, "PLACED IS REMEMBERED").
  final DateTime? placedAt;

  HistoryEntry({
    required this.identifier,
    required this.outgoing,
    required this.content,
    required this.instant,
    this.state,
    this.placedAt,
  }) {
    if (identifier.length != kIdentifierLength) {
      throw ArgumentError(
          'identifier must be $kIdentifierLength B, was ${identifier.length}');
    }
    if (outgoing && state == null) {
      throw ArgumentError('an outgoing entry needs a state');
    }
    if (!outgoing && state != null) {
      throw ArgumentError('an incoming entry carries no state');
    }
    if (!outgoing && placedAt != null) {
      throw ArgumentError('an incoming entry is not placed by this device');
    }
  }

  /// Not yet receipted and not yet given up — the caller must
  /// deliver this entry again after loading.
  bool get open =>
      outgoing &&
      state != DeliveryState.delivered &&
      state != DeliveryState.failed;

  /// The same entry with another state, another content or a placing.
  HistoryEntry _with(
          {DeliveryState? state, Uint8List? content, DateTime? placedAt}) =>
      HistoryEntry(
        identifier: identifier,
        outgoing: outgoing,
        content: content ?? this.content,
        instant: instant,
        state: state ?? this.state,
        placedAt: placedAt ?? this.placedAt,
      );

  /// The same entry as a CLOSED or received one keeps it: identifier, time
  /// and state — no content and no placing.
  HistoryEntry _bare() => HistoryEntry(
      identifier: identifier,
      outgoing: outgoing,
      content: Uint8List(0),
      instant: instant,
      state: state);
}

/// How long the copy of a PLACED message is kept for sending again: the
/// retention of the post box (§8.2 "retention 7 days"; §9.3 "dropped at the
/// next edge once the placing is more than 7 days old").
const Duration kPlacedCopyKept = Duration(days: 7);

/// The state byte of a RECEIVED record in the FILE of the builds before
/// S401 — such a record carries no state (layout: `history_takeover.dart`,
/// which reads those files). It stands here and not beside the layout
/// because this file is where the gate against numbers assigned outside
/// `kinds.dart` (`scripts/check-mycelium-rules.sh`, rule 4) allows the one
/// number that is a file format and not a packet kind.
const int kHistoryNoState = 0xFF;

/// The history with exactly ONE peer. One object per peer; its records lie
/// in the [HistoryStore] it was loaded from, under the peer's identifier.
class History {
  final HistoryStore _store;
  final String _peer;
  final List<HistoryEntry> _entries = [];

  History._(this._store, this._peer);

  /// Loads the history with [peer] (its identifier, hex) from [store] — an
  /// empty one if the store holds no record for it.
  ///
  /// THE LOAD IS THE ENFORCER (file header): a record that is not open and
  /// still carries content loses it here, and that record is rewritten at
  /// once. A history that already keeps the rule is not written.
  ///
  /// A record of a RECEIVED delivery (a row the builds before S403 wrote;
  /// the application's import removes them at its start): only its
  /// identifier is taken over — into the identity's received memory
  /// ([HistoryStore.incomingKeep], §20.2). It keeps no entry here (file
  /// header), so nothing is shown of it and nothing rewritten.
  static History load(HistoryStore store, String peer) {
    final v = History._(store, peer);
    final read = [...store.load(peer)]..sort((a, b) {
        final byTime = a.instant.compareTo(b.instant);
        return byTime != 0
            ? byTime
            : historyRecordKey(a).compareTo(historyRecordKey(b));
      });
    for (final r in read) {
      if (!r.outgoing) {
        store.incomingKeep(r.identifier);
        continue;
      }
      final e = kept(r);
      if (!identical(e, r)) store.put(peer, e);
      v._entries.add(e);
    }
    return v;
  }

  /// [e] as the history keeps it: an entry that is not open carries no
  /// content and no placing (file header).
  static HistoryEntry kept(HistoryEntry e) =>
      e.open || (e.content.isEmpty && e.placedAt == null) ? e : e._bare();

  /// All entries, in the order of arrival/sending (file header, "THE
  /// ORDER").
  List<HistoryEntry> get entries => List.unmodifiable(_entries);

  /// Outgoing entries that are not yet receipted and not given up
  /// — the caller must deliver them again.
  Iterable<HistoryEntry> get openOutbounds =>
      _entries.where((e) => e.open);

  /// Adds [given] — ONE record written, for an OWN entry: the same entry of
  /// the same direction and identifier that already stands here is
  /// replaced, in its place (a record has one name, `history_store.dart`).
  ///
  /// A RECEIVED entry keeps no record and no entry here any more (file
  /// header, S403): its identifier goes into the identity's received
  /// memory — one row, without peer and without time (§20.2). The check
  /// against it runs at the inbound, BEFORE anything is admitted
  /// (`mailbox_inbound.dart`); that this branch still exists is the file's
  /// own rule that it enforces itself at every place an entry is written.
  void append(HistoryEntry given) {
    if (!given.outgoing) {
      _store.incomingKeep(given.identifier);
      return;
    }
    final entry = kept(given);
    _store.put(_peer, entry);
    final at = _entries.indexWhere((e) =>
        e.outgoing == entry.outgoing && _equal(e.identifier, entry.identifier));
    at == -1 ? _entries.add(entry) : _entries[at] = entry;
  }

  /// Changes the state of the outgoing entry with this identifier — ONE
  /// record rewritten. With `delivered` or `failed` the entry is closed and
  /// its content goes with the same write — whoever closes it, for whatever
  /// reason: the receipt, the application's 14-day limit (§9.3), a receipt
  /// of the last run.
  void stateChange(Uint8List identifier, DeliveryState fresh) {
    final idx = _entries
        .indexWhere((e) => e.outgoing && _equal(e.identifier, identifier));
    if (idx == -1) {
      throw HistoryError(
          'no outgoing entry with this identifier in the history');
    }
    final changed = kept(_entries[idx]._with(state: fresh));
    _store.put(_peer, changed);
    _entries[idx] = changed;
  }

  /// The deposit of the open own entry [identifier] is PLACED — two holders
  /// acknowledged it at [at] (§8.2). ONE record rewritten. `false`, and
  /// nothing written, if the entry is gone or closed meanwhile: the
  /// acknowledgement came first, or the application deleted the message.
  bool placedMark(Uint8List identifier, DateTime at) {
    final idx = _entries
        .indexWhere((e) => e.open && _equal(e.identifier, identifier));
    if (idx == -1) return false;
    final changed = _entries[idx]._with(placedAt: at);
    _store.put(_peer, changed);
    _entries[idx] = changed;
    return true;
  }

  /// The placing of the open entry [identifier] counts no longer: the
  /// message is sealed again under other keys (§4.5.4), and what the
  /// holders keep is the envelope before that. Until the new deposit is
  /// placed the entry is again "neither acknowledged nor placed" (§9.3).
  void placedClear(Uint8List identifier) {
    final idx = _entries.indexWhere((e) =>
        e.open && e.placedAt != null && _equal(e.identifier, identifier));
    if (idx == -1) return;
    final e = _entries[idx];
    final changed = HistoryEntry(
        identifier: e.identifier,
        outgoing: true,
        content: e.content,
        instant: e.instant,
        state: e.state);
    _store.put(_peer, changed);
    _entries[idx] = changed;
  }

  /// Drops the copy kept for sending again of the PLACED open entry
  /// [identifier] (§9.3; the caller decides when: [kPlacedCopyKept]). The
  /// entry stays open — `in transit` (§9.1) — with identifier, time and
  /// placing. `false`, and nothing written, if there is no such copy.
  bool copyDrop(Uint8List identifier) {
    final idx = _entries.indexWhere((e) =>
        e.open && e.placedAt != null && _equal(e.identifier, identifier));
    if (idx == -1 || _entries[idx].content.isEmpty) return false;
    final changed = _entries[idx]._with(content: Uint8List(0));
    _store.put(_peer, changed);
    _entries[idx] = changed;
    return true;
  }

  /// Changes the content of an OPEN entry — the point in time stays that of
  /// the ORIGINAL. An edit is not a new message; if it
  /// slid forward, the reply to it would suddenly stand before it.
  ///
  /// An entry that is received or closed keeps no content (file header), so
  /// an edit of it changes nothing here and nothing is written: the edit
  /// itself has gone to the peer, and the wording lives in the application.
  void contentChange(Uint8List identifier, Uint8List newContent) {
    final idx = _entries.indexWhere((e) => _equal(e.identifier, identifier));
    if (idx == -1) {
      throw HistoryError('no entry with this identifier in the history');
    }
    final e = _entries[idx];
    // A placed entry whose copy was dropped ([copyDrop]) gets none back.
    if (!e.open || (e.placedAt != null && e.content.isEmpty)) return;
    final changed = e._with(content: newContent);
    _store.put(_peer, changed);
    _entries[idx] = changed;
  }

  /// Forgets every entry [which] names. An entry leaves the history — its
  /// record is removed from the store — only when it is OUTGOING: of a
  /// received delivery nothing stands here any more (file header, S403),
  /// so [which] cannot name one; the identifier of a received delivery
  /// is not touched by a forgetting either way — it lives in the
  /// identity's received memory (§20.2), and a late copy stays refused.
  /// Returns what was named, as it stood; the store is written
  /// only if an entry leaves it.
  List<HistoryEntry> forget(bool Function(HistoryEntry) which) {
    final named = _entries.where(which).toList();
    final gone = named.where((e) => e.outgoing).toList();
    for (final e in gone) {
      _store.remove(_peer, e);
    }
    _entries.removeWhere(gone.contains);
    return named;
  }
}

bool _equal(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
