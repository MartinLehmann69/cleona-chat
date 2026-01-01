/// Where the histories of a mailbox are kept — the port to the identity's
/// store (V4.2 §4.5.3 form 1: "Messages, conversations and their indices
/// live in an encrypted SQLite database, one per identity"; §21.4.2).
///
/// ── WHY A PORT AND NOT THE DATABASE ITSELF ─────────────────────────────
/// The database belongs to the application: it opens it, once per identity
/// (§21.4.1), and its module sits above the seam (§22.4.5 lists
/// `lib/core/storage/` there). This layer sits below it (§22.4.1). So the
/// delivery layer names WHAT it keeps — one record per entry, by peer —
/// and the caller that registers a mailbox says WHERE: the application
/// hands in its store ([historyStoreGive]); a lab tool or a probe that has
/// none gets [HistoryStoreMemory].
///
/// ── ONE RECORD PER ENTRY ───────────────────────────────────────────────
/// A record is named by its peer, its direction and its identifier
/// ([historyRecordKey]): sender and recipient draw their identifiers
/// independently, so the direction is part of the name. A new message is
/// one [HistoryStore.put], a state change is one [HistoryStore.put] of the
/// same record, a deletion one [HistoryStore.remove]. Until S401 the
/// history was a file per peer and every state change rewrote all of it.
///
/// ── THE MEMORY OF RECEIVED IDENTIFIERS (§20.2) ─────────────────────────
/// Besides the per-peer records the port carries ONE memory of the
/// identifiers of received deliveries — [HistoryStore.incomingKnown] and
/// [HistoryStore.incomingKeep]. It is the IDENTITY's, not a peer's: no
/// sender beside the identifier, no arrival time, no cap, no eviction,
/// and it survives the end of a contact (owner decision 02.10.2026,
/// V-2 = b, V-3 = a, V-4 — `berichte/S403-ENTSCHEIDE-02-10-ABEND.md`
/// §11). The received records it replaces stood per peer and fell with
/// the contact; the application serves it from the `received_ids` table
/// of the identity's store (schema 4). Two separate calls on purpose:
/// the check at the inbound, the keep where the sender is admitted —
/// what lies between them may still refuse the delivery.
///
/// What a record carries is decided by [History] (`history.dart`, "WHAT AN
/// ENTRY KEEPS"), not here: this file only keeps what it is handed.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/history.dart' show HistoryEntry;
import 'package:mycelium/mailbox_start.dart' show MailboxDetails;

/// The records of the histories of ONE identity. [peer] is always the
/// peer's identifier, hex-encoded (`identifierFrom`).
abstract interface class HistoryStore {
  /// Every record kept for [peer], in no particular order.
  List<HistoryEntry> load(String peer);

  /// Writes ONE record: adds it, or replaces the one of the same direction
  /// and identifier.
  void put(String peer, HistoryEntry entry);

  /// Removes ONE record. Nothing happens if it is not there.
  void remove(String peer, HistoryEntry entry);

  /// Removes every record of [peer] — the peer is no contact and no group
  /// pair any more. The records of [peer] only; the identifiers it once
  /// delivered remain in the identity's received memory
  /// ([incomingKnown]/[incomingKeep]).
  void drop(String peer);

  /// The peers records are kept for.
  Set<String> peers();

  /// Whether this identity has already received a delivery with this
  /// identifier (8 B) — the memory against the second copy (§7.1, §20.2).
  /// Identity-wide: no peer, and no arrival time to run out — a late
  /// copy of a DELETED contact is refused just the same (V-3 = a).
  bool incomingKnown(Uint8List identifier);

  /// Remembers that this identity has received a delivery with this
  /// identifier (8 B) — idempotent, no sender, no time, no cap, kept
  /// for as long as the identity exists (§20.2; V-2 = b, V-4). The
  /// counterpart of [incomingKnown]; both are separate calls on
  /// purpose, so that a delivery can be checked at the gate and kept
  /// only where its sender is admitted.
  void incomingKeep(Uint8List identifier);
}

/// The name of the record of [e] within its peer: direction and identifier.
String historyRecordKey(HistoryEntry e) =>
    '${e.outgoing ? 'o' : 'i'}:${_hex(e.identifier)}';

/// The records in memory — for a caller without a store: the lab daemon
/// (`bin/myceliumd.dart`), the probes, the smokes of this package.
///
/// It does NOT survive the process. Within one process it survives the
/// mailbox: [at] returns the same store for the same directory, so a probe
/// that stops a host and starts it again on the same directory — a
/// restart, as far as this layer can tell — finds its records again.
class HistoryStoreMemory implements HistoryStore {
  final Map<String, Map<String, HistoryEntry>> _byPeer = {};

  /// The identity's received identifiers, hex-encoded — the §20.2 memory.
  /// In this store it lives in the process like the records do; the
  /// durable one is the application's [DeliveryHistoryStore].
  final Set<String> _incoming = {};

  HistoryStoreMemory();

  static final Map<String, HistoryStoreMemory> _perDirectory = {};

  /// The store of the mailbox whose files lie in [directory] — one per
  /// directory and process.
  static HistoryStoreMemory at(Directory directory) =>
      _perDirectory.putIfAbsent(
          directory.absolute.path, HistoryStoreMemory.new);

  @override
  List<HistoryEntry> load(String peer) => [...?_byPeer[peer]?.values];

  @override
  void put(String peer, HistoryEntry entry) =>
      (_byPeer[peer] ??= {})[historyRecordKey(entry)] = entry;

  @override
  void remove(String peer, HistoryEntry entry) {
    final records = _byPeer[peer];
    if (records == null) return;
    records.remove(historyRecordKey(entry));
    if (records.isEmpty) _byPeer.remove(peer);
  }

  @override
  void drop(String peer) => _byPeer.remove(peer);

  @override
  Set<String> peers() => _byPeer.keys.toSet();

  @override
  bool incomingKnown(Uint8List identifier) =>
      _incoming.contains(_hex(identifier));

  @override
  void incomingKeep(Uint8List identifier) => _incoming.add(_hex(identifier));
}

/// Per registration ([MailboxDetails]) — given before the mailbox exists,
/// like the note of a format reset (`mailbox_format_reset.dart`).
final Expando<HistoryStore> _given = Expando('historyStoreGiven');

/// Hands the store of the identity that registers with [a] to its mailbox.
/// The application calls this with its message store behind [store]
/// (`mailboxDetailsFor`); it returns [a] so that it can stand in the
/// expression that builds the registration.
MailboxDetails historyStoreGive(MailboxDetails a, HistoryStore store) {
  _given[a] = store;
  return a;
}

/// The store the caller gave for [a], or `null`.
HistoryStore? historyStoreGiven(MailboxDetails a) => _given[a];

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
