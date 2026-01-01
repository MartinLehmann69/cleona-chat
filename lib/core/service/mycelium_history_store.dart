/// The history of the delivery layer in the identity's message store
/// (v4_2 §4.5.3 form 1, §21.4.2; S401).
///
/// `package:mycelium` keeps, per peer, the frame of every own message that
/// is still OPEN — it sends it again from there at the edges of §8.2 (§9.3)
/// — and the identifier of everything else, the memory against the second
/// copy (§7.1). Until S401 that was a file per peer beside the store. The
/// norm knows no such file: "Messages, conversations and their indices live
/// in an encrypted SQLite database, one per identity" (§4.5.3), "own
/// outbox … under the DB key" (§4.5.3, the relay paragraph), and §4.5.2
/// names for the mailbox's directory contacts' delivery state, group pairs,
/// first contact and parked cells.
///
/// The delivery layer names what it keeps through a port
/// (`mycelium/lib/history_store.dart`); this file serves that port with the
/// store of the identity. The store's module sits above the seam (§22.4.5),
/// the delivery layer below it (§22.4.1) — so the store is handed down, the
/// layer does not reach up for it.
///
/// ── THE FORM ───────────────────────────────────────────────────────────
/// The state table, area [kDeliveryHistoryArea], ONE row per entry:
///
/// ```
/// entry_key  <peer identifier, 64 hex>:<o|i>:<message identifier, 16 hex>
/// data       {"t": <ms>, "s": <state 0..3, own entries only>,
///             "c": "<frame, base64 — only while the own entry is open>",
///             "p": <ms — only on an open own entry that is placed>}
/// ```
///
/// `p` (S403, step 5 of the delivery path): the moment two holders had
/// acknowledged the deposit of this message (§8.2 "placed at the second
/// `0x31`"). A placed message is not sent again at an edge and not closed
/// as `failed` (§9.3, D-44, D-48); its copy `c` goes at the first edge more
/// than 7 days after `p`, the row stays until the acknowledgement. The
/// field is optional and the store's schema number is unchanged: a row
/// without it is a message that is not placed.
///
/// A new message is one row, a state change rewrites that one row — not,
/// as the file did, the whole history with that peer. The rows of one peer
/// are read by a range on the primary key (`loadAreaPrefix`).
///
/// No schema change: the state table takes JSON, so the frame travels as
/// base64 (4/3); the store's own compression (zstd from 128 B, kept when it
/// gains 10 %) takes most of that back for a large frame. Only open own
/// entries carry one, and those are few: a message keeps its frame until
/// its receipt — at most 14 days if it was never placed, and until the
/// first edge more than 7 days after its placing if it was (§9.3).
///
/// ── THE MEMORY OF RECEIVED IDENTIFIERS (§20.2) ──────────────────────────
/// Not in this area any more (S403): the identifiers of received
/// deliveries live in the store's own table `received_ids` (schema 4),
/// one row per 8-byte identifier — no peer, no arrival time, no cap,
/// kept for as long as the identity exists
/// ([MessageStore.receivedIdKnown]/[MessageStore.receivedIdKeep]; owner
/// decision 02.10.2026, V-1 = B, V-2 = b, V-4). This file serves the
/// port's [incomingKnown]/[incomingKeep] with it.
///
/// The `i:` rows the builds before S403 wrote into this area are taken
/// over into that table ONCE, at the construction of this store,
/// idempotently: a row is read, its identifier inserted, the row removed
/// — a later start finds no `i:` row any more. An `o:` row is left
/// alone. (A `load` still tolerates an `i:` row it should ever see —
/// `History.load` routes it into the received memory — but the import
/// runs before any load, at the registration of the mailbox.)
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/storage/message_store.dart';
import 'package:mycelium/history.dart' show HistoryEntry;
import 'package:mycelium/history_store.dart';
import 'package:mycelium/message.dart' show DeliveryState, kIdentifierLength;

/// The area of the identity's store that holds the delivery layer's history.
const String kDeliveryHistoryArea = 'delivery_history';

/// [HistoryStore] over the message store of ONE identity.
class DeliveryHistoryStore implements HistoryStore {
  final MessageStore Function() _store;

  /// The identity's logger, with its profile directory (`mailboxDetailsFor`
  /// hands it in).
  final CLogger log;

  /// [store] returns the identity's store — a function, because the handle
  /// can be closed and opened anew while the mailbox lives (an enrolment
  /// handover, `closeStore`). It is asked ONCE here: a mailbox must not be
  /// registered for an identity whose store cannot be opened, and there is
  /// no falling back to memory — the function throws, as the store's own
  /// getter does without a seed (§21.4.1).
  DeliveryHistoryStore(this._store, {required this.log}) {
    _store();
    _receivedIdsTakeOver();
  }

  /// The `i:` rows of the builds before S403: `<peer>:i:<identifier>` —
  /// a peer identifier is 64 hex, a delivery identifier 16.
  static final RegExp _legacyIncomingRow =
      RegExp('^([0-9a-f]{64}):i:([0-9a-f]{16})\$');

  /// Takes the received identifiers of the `i:` rows this file no longer
  /// writes into the received memory (file header), and removes the
  /// rows. One row that does not parse goes too — it can never be read
  /// again either way, the same reasoning as at [load]. Idempotent: a
  /// second run finds no `i:` row.
  void _receivedIdsTakeOver() {
    final store = _store();
    var taken = 0;
    for (final key in store.areaKeys(kDeliveryHistoryArea)) {
      final hit = _legacyIncomingRow.firstMatch(key);
      if (hit == null) continue;
      final identifier = _fromHex(hit.group(2)!);
      if (identifier == null) {
        log.warn('delivery history: the received row ${key.substring(0, 8)}…'
            ' does not read — removed');
      } else {
        store.receivedIdKeep(identifier);
        taken++;
      }
      store.removeEntry(kDeliveryHistoryArea, key);
    }
    if (taken > 0) {
      log.info('delivery history: $taken received identifier(s) taken over '
          'into the received memory (§20.2)');
    }
  }

  static String _prefixOf(String peer) => '$peer:';

  static String _keyOf(String peer, HistoryEntry e) =>
      '${_prefixOf(peer)}${historyRecordKey(e)}';

  @override
  List<HistoryEntry> load(String peer) {
    final prefix = _prefixOf(peer);
    final out = <HistoryEntry>[];
    final rows = _store().loadAreaPrefix(kDeliveryHistoryArea, prefix);
    for (final row in rows.entries) {
      final entry = _read(row.key.substring(prefix.length), row.value);
      if (entry == null) {
        // ONE row that does not read must not take the history with this
        // peer down with it (until S401 one torn record made the whole file
        // unreadable). It can never be read again: it goes, and that is
        // said.
        log.warn('delivery history: the row ${row.key.substring(0, 8)}…'
            '${row.key.substring(prefix.length)} does not read — removed');
        _store().removeEntry(kDeliveryHistoryArea, row.key);
        continue;
      }
      out.add(entry);
    }
    return out;
  }

  @override
  void put(String peer, HistoryEntry entry) =>
      _store().putEntry(kDeliveryHistoryArea, _keyOf(peer, entry), {
        't': entry.instant.millisecondsSinceEpoch,
        if (entry.outgoing) 's': entry.state!.index,
        if (entry.content.isNotEmpty) 'c': base64Encode(entry.content),
        if (entry.placedAt case final p?) 'p': p.millisecondsSinceEpoch,
      });

  @override
  void remove(String peer, HistoryEntry entry) =>
      _store().removeEntry(kDeliveryHistoryArea, _keyOf(peer, entry));

  @override
  void drop(String peer) =>
      _store().removeAreaPrefix(kDeliveryHistoryArea, _prefixOf(peer));

  @override
  Set<String> peers() => {
        for (final key in _store().areaKeys(kDeliveryHistoryArea))
          if (key.contains(':')) key.substring(0, key.indexOf(':')),
      };

  // The identity's received memory (§20.2) — served from the store's own
  // `received_ids` table (schema 4), not from this area: identity-wide,
  // no peer, no arrival time, and kept for as long as the identity
  // exists. The guards of that statement are
  // `test/smoke/smoke_received_ids_store.dart` and
  // `mycelium/test/smoke_received_ids.dart`.

  @override
  bool incomingKnown(Uint8List identifier) =>
      _store().receivedIdKnown(identifier);

  @override
  void incomingKeep(Uint8List identifier) =>
      _store().receivedIdKeep(identifier);

  /// The entry behind the row named [name] (`<o|i>:<identifier hex>`), or
  /// `null` if the row is not one this file wrote.
  static HistoryEntry? _read(String name, Map<String, dynamic> data) {
    try {
      final outgoing = switch (name.substring(0, 2)) {
        'o:' => true,
        'i:' => false,
        _ => null,
      };
      final identifier = _fromHex(name.substring(2));
      final at = data['t'];
      final s = data['s'];
      final c = data['c'];
      final p = data['p'];
      // A placing stands only on an own row, as a moment.
      if (p != null && (p is! int || outgoing != true)) return null;
      if (outgoing == null ||
          identifier == null ||
          identifier.length != kIdentifierLength ||
          at is! int) {
        return null;
      }
      if (outgoing != (s is int) ||
          (s is int && (s < 0 || s >= DeliveryState.values.length))) {
        return null;
      }
      return HistoryEntry(
        identifier: identifier,
        outgoing: outgoing,
        content: c is String ? base64Decode(c) : Uint8List(0),
        instant: DateTime.fromMillisecondsSinceEpoch(at),
        state: s is int ? DeliveryState.values[s] : null,
        placedAt: p is int ? DateTime.fromMillisecondsSinceEpoch(p) : null,
      );
    } on Object {
      return null;
    }
  }

  static Uint8List? _fromHex(String s) {
    if (s.length.isOdd) return null;
    final out = Uint8List(s.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      final b = int.tryParse(s.substring(2 * i, 2 * i + 2), radix: 16);
      if (b == null) return null;
      out[i] = b;
    }
    return out;
  }
}
