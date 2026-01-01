// Encrypted local store for messages and conversations (S366).
//
// The carrier is SQLite3 Multiple Ciphers via `native/cleona_store/`
// (SQLite 3.53.4, ChaCha20-Poly1305). Architecture: §4.5.3 form 1, §21.4
// "The message store".
//
// WHY THIS LAYER EXISTS — measured, not assumed (S366):
// the previous store rewrote the whole conversation file on EVERY change
// and held every message in memory at start.
// At 150 000 messages that was 3 497 ms load time, 1 005 MB
// memory peak and 2 520 ms for a search over everything as soon as
// memory no longer sufficed. Here: no full load, 1.6 ms search,
// ~1 ms per insertion.
//
// WHAT IS COMPRESSED HERE, AND WHAT NOT. §4.5.3 demands compression
// except where it brings nothing, and puts the decision on a
// MEASUREMENT instead of a type list: below 10 % gain it is stored
// uncompressed. For this store that means:
//   * `text` stays a plaintext column. Message text is 86 B on average;
//     compressed individually it becomes LARGER (measured: a 13 B message
//     yields 26 B), and the full-text index needs it in plaintext anyway.
//   * `extra` (the rarer fields as JSON — media header, reactions,
//     quote, link preview) is compressed if the probe yields at least
//     10 %. That is where the large values lie.
// That is the same rule as in `FileEncryption`, only at column level.

import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/storage/encrypted_store.dart';

// The lower bound of the SQLite version lived in this file until S403 and
// is imported from here in many places.
export 'package:cleona/core/storage/encrypted_store.dart'
    show kMinSqliteVersion;

/// Schema version. Kept in `PRAGMA user_version`; an upgrade is
/// a deliberate action, not a side effect.
///
/// 1 — conversations, messages, full-text index (S366).
/// 2 — the state table `state` for everything that was previously written as a separate
///     JSON file per collection (S366, second part).
/// 3 — the same state table with English column names (`area`,
///     `entry_key`, `data`, `data_zstd`; S393, CLAUDE.md rule 11). A store
///     of schema 2 is rejected, not converted: 4.2 has no conversion
///     path, the profile is created anew.
/// 4 — `received_ids`: the identifiers of the deliveries this identity
///     has received, one slim row per 8-byte identifier — no sender, no
///     arrival time, no cap, kept for as long as the identity exists
///     (§20.2; owner decision 02.10.2026, V-1 = B, V-2 = b, V-3 = a,
///     V-4). The received rows of the delivery history of an earlier
///     build are taken over into it once, idempotently, by
///     `DeliveryHistoryStore`.
const int kMessageStoreSchemaVersion = 4;

class MessageStoreException implements Exception {
  final String message;
  const MessageStoreException(this.message);
  @override
  String toString() => 'MessageStoreException: $message';
}

/// An encrypted store. **One per identity** (§21.4): a
/// shared one would have to lie under the device-wide key and would thus give
/// up the separation that `deriveFileEncKey` establishes.
///
/// How the file is opened, the state table and the compression of its
/// values are shared with the device database and live in
/// [EncryptedStore] (S403); the tables for messages and conversations and
/// their full-text index exist only here.
class MessageStore extends EncryptedStore {
  MessageStore._(super.db, super.log);

  /// Opens (or creates) the store under [path].
  ///
  /// [key] are the **raw 32 bytes** from
  /// `HdWallet.deriveFileEncKey(masterSeed, hdIndex)`
  /// ([EncryptedStore.openDatabase]).
  static MessageStore open(String path, Uint8List key, {CLogger? logger}) {
    // `profileDir` is mandatory, not decoration: without it `CLogger` keeps the
    // lines only in the ring and writes to NO file — a store whose
    // open errors are recorded nowhere cannot be investigated in the field.
    // The directory of the store IS the profile directory.
    final log = logger ??
        CLogger.get('MessageStore',
            profileDir: File(path).parent.path);

    final db = EncryptedStore.openDatabase(path, key,
        fail: MessageStoreException.new);
    try {
      final store = MessageStore._(db, log);
      store._migrate();
      return store;
    } catch (e) {
      db.close();
      rethrow;
    }
  }

  // ── Schema ────────────────────────────────────────────────────────
  //
  // Identifiers are stored as BLOB, not as hex text. Measured (S366): that
  // alone is 27 % of the database size — more than the entire
  // text compression yields (12-17 %), because the surcharge acts
  // threefold: in the row, in the primary key and in the index.

  void _migrate() {
    final current = db.select('PRAGMA user_version;').first.values.first as int;
    if (current == kMessageStoreSchemaVersion) return;
    if (current > kMessageStoreSchemaVersion) {
      throw MessageStoreException(
          'store schema is $current, this build knows only '
          '$kMessageStoreSchemaVersion — refusing to open rather than '
          'writing a shape a newer build would not recognise');
    }
    if (current == 2) {
      throw MessageStoreException(
          'store schema 2 names the state table in German; this build '
          'reads schema $kMessageStoreSchemaVersion only and converts '
          'nothing — create the profile anew');
    }

    db.execute('BEGIN;');
    try {
      if (current < 1) {
        // `extra` carries the fields that are neither searched nor
        // sorted by (`config`, the pending proposal, the
        // notification choice) — the same construction as for `messages`.
        // Five individual columns for it would be five schema changes for
        // every new field; here it is none.
        db.execute('''
          CREATE TABLE conversations(
            id             BLOB PRIMARY KEY,
            display_name   TEXT NOT NULL DEFAULT '',
            last_activity  INTEGER NOT NULL DEFAULT 0,
            is_group       INTEGER NOT NULL DEFAULT 0,
            is_channel     INTEGER NOT NULL DEFAULT 0,
            is_favorite    INTEGER NOT NULL DEFAULT 0,
            unread_count   INTEGER NOT NULL DEFAULT 0,
            profile_picture BLOB,
            extra          BLOB,
            extra_zstd     INTEGER NOT NULL DEFAULT 0
          );
        ''');
        db.execute('''
          CREATE TABLE messages(
            id           BLOB PRIMARY KEY,
            conv_id      BLOB NOT NULL
                         REFERENCES conversations(id) ON DELETE CASCADE,
            sender       BLOB,
            ts           INTEGER NOT NULL,
            type         INTEGER NOT NULL DEFAULT 0,
            status       TEXT NOT NULL DEFAULT '',
            is_outgoing  INTEGER NOT NULL DEFAULT 0,
            text         TEXT NOT NULL DEFAULT '',
            extra        BLOB,
            extra_zstd   INTEGER NOT NULL DEFAULT 0
          );
        ''');
        // The one query every chat build makes: the last N
        // of a conversation. Measured 0.08 ms at 150 000 messages.
        db.execute(
            'CREATE INDEX ix_msg_conv_ts ON messages(conv_id, ts DESC);');
        // Full-text index with external content: the index holds only the
        // tokens, the text stays in `messages`. No second text stock.
        db.execute('''
          CREATE VIRTUAL TABLE messages_fts USING fts5(
            text, content='messages', content_rowid='rowid'
          );
        ''');
        // The three triggers keep the index congruent. Without them
        // the search would find deleted messages and miss new ones —
        // an index that silently diverges is worse than none.
        db.execute('''
          CREATE TRIGGER messages_fts_ai AFTER INSERT ON messages BEGIN
            INSERT INTO messages_fts(rowid, text) VALUES (new.rowid, new.text);
          END;
        ''');
        db.execute('''
          CREATE TRIGGER messages_fts_ad AFTER DELETE ON messages BEGIN
            INSERT INTO messages_fts(messages_fts, rowid, text)
              VALUES ('delete', old.rowid, old.text);
          END;
        ''');
        db.execute('''
          CREATE TRIGGER messages_fts_au AFTER UPDATE ON messages BEGIN
            INSERT INTO messages_fts(messages_fts, rowid, text)
              VALUES ('delete', old.rowid, old.text);
            INSERT INTO messages_fts(rowid, text) VALUES (new.rowid, new.text);
          END;
        ''');
      }
      if (current < 2) {
        // The state table — what it is and why it is ONE table stands at
        // [EncryptedStore.createStateTable].
        EncryptedStore.createStateTable(db);
      }
      if (current < 4) {
        // The identifiers of received deliveries (§20.2, S403 decision 1):
        // one slim row per 8-byte delivery identifier — the identifier
        // mycelium draws per message, NOT the 16-byte app message id. No
        // sender, no arrival time: the owner accepted the collision
        // chance of the 8 bytes (V-2 = b) and wants no eviction (V-4) —
        // the memory's span is "as long as the identity exists", not a
        // number. `WITHOUT ROWID`: the table is its primary key, every
        // read is one page hit, no second index exists to drift.
        // The CHECK makes the 8 bytes a property of the schema, not of a
        // caller's care (the guard of `smoke_received_ids_store.dart`
        // probes exactly this).
        db.execute('''
          CREATE TABLE received_ids(
            id BLOB NOT NULL PRIMARY KEY CHECK (length(id) = 8)
          ) WITHOUT ROWID;
        ''');
      }
      db.execute('PRAGMA user_version = $kMessageStoreSchemaVersion;');
      db.execute('COMMIT;');
      log.info('message store schema at $kMessageStoreSchemaVersion');
    } catch (e) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  // ── The memory of received deliveries (§20.2) ────────────────────
  //
  // THE STATEMENT, not an implementation detail: §20.2 keeps, per
  // identity, the identifiers of received deliveries "against a second
  // copy", with "none — kept as long as the identity exists" as their
  // span and "nothing is evicted" as the explicit answer to every
  // deadline. This table IS that memory — the capped ring of the
  // process (`_processedMessageIds`, 4 096 entries) it replaces fell
  // short of both: it forgot after 4 096 deliveries and lived only as
  // long as the process wrote it out.
  //
  // The 8-byte identifier is the DELIVERY identifier mycelium draws per
  // message (`mycelium/lib/message.dart`, `kIdentifierLength`); retries
  // carry the same one. It is NOT the 16-byte app message id: an edit or
  // a deletion travels under the identifier of its TARGET, and the
  // memory keyed on the target would refuse the second edit. The
  // collision chance of 8 bytes at one million kept identifiers is
  // about 2.7 in a hundred million — accepted by the owner (V-2 = b):
  // the worst case is one message shown twice, never one lost.

  /// The length a row of `received_ids` must have — the delivery
  /// identifier of the layer below (`mycelium/lib/message.dart`,
  /// `kIdentifierLength`). Kept here as the schema's own number so the
  /// CHECK and this guard cannot drift apart; the layer below enforces
  /// the same length at its entries.
  static const int kReceivedIdLength = 8;

  /// Whether a delivery with this identifier was already received by
  /// THIS identity (§20.2) — the memory against the second copy, for
  /// the whole delivery layer AND the application: both ask the same
  /// table through [DeliveryHistoryStore] and `HarvestEvent.deliveryId`.
  bool receivedIdKnown(Uint8List id) {
    _assertReceivedIdLength(id);
    return db
        .select('SELECT 1 FROM received_ids WHERE id = ?;', [id])
        .isNotEmpty;
  }

  /// Remembers a received delivery identifier — idempotent: a second
  /// keep of the same identifier is one row, not two. Nothing here ever
  /// deletes a row; the span is the identity's, not a peer's (V-3 = a:
  /// the identifiers of a deleted contact stay).
  void receivedIdKeep(Uint8List id) {
    _assertReceivedIdLength(id);
    db.execute('INSERT OR IGNORE INTO received_ids(id) VALUES (?);', [id]);
  }

  void _assertReceivedIdLength(Uint8List id) {
    if (id.length != kReceivedIdLength) {
      throw ArgumentError.value(id.length, 'id.length',
          'a delivery identifier is $kReceivedIdLength bytes');
    }
  }

  // The compression of the `extra` column is [packJson]/[unpackJson] of
  // [EncryptedStore] — the same rule as for a value of the state table
  // (§4.5.3: measure instead of guess; below 10 % gain the value is stored
  // uncompressed and `extra_zstd` stays 0).

  // ── Writing ───────────────────────────────────────────────────────

  void upsertConversation({
    required Uint8List id,
    required String displayName,
    required int lastActivity,
    bool isGroup = false,
    bool isChannel = false,
    bool isFavorite = false,
    int unreadCount = 0,
    Uint8List? profilePicture,
    Map<String, dynamic>? extra,
  }) {
    final (blob, flag) = packJson(extra);
    db.execute('''
      INSERT INTO conversations(id, display_name, last_activity, is_group,
                                is_channel, is_favorite, unread_count,
                                profile_picture, extra, extra_zstd)
      VALUES(?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET
        display_name=excluded.display_name,
        last_activity=excluded.last_activity,
        is_group=excluded.is_group,
        is_channel=excluded.is_channel,
        is_favorite=excluded.is_favorite,
        unread_count=excluded.unread_count,
        profile_picture=excluded.profile_picture,
        extra=excluded.extra,
        extra_zstd=excluded.extra_zstd;
    ''', [
      id, displayName, lastActivity,
      isGroup ? 1 : 0, isChannel ? 1 : 0, isFavorite ? 1 : 0,
      unreadCount, profilePicture, blob, flag,
    ]);
  }

  /// All conversations, newest first. Without their messages — those come
  /// via [recentMessages], and exactly therein lies the gain: the start
  /// no longer depends on the number of messages.
  List<Map<String, Object?>> allConversations() {
    final rows = db.select(
        'SELECT * FROM conversations ORDER BY last_activity DESC;');
    return rows
        .map((r) => {
              'id': r['id'],
              'displayName': r['display_name'],
              'lastActivity': r['last_activity'],
              'isGroup': (r['is_group'] as int) == 1,
              'isChannel': (r['is_channel'] as int) == 1,
              'isFavorite': (r['is_favorite'] as int) == 1,
              'unreadCount': r['unread_count'],
              'profilePicture': r['profile_picture'],
              'extra': unpackJson(r['extra'], r['extra_zstd'] as int),
            })
        .toList();
  }

  void upsertMessage({
    required Uint8List id,
    required Uint8List convId,
    Uint8List? sender,
    required int ts,
    int type = 0,
    String status = '',
    bool isOutgoing = false,
    String text = '',
    Map<String, dynamic>? extra,
  }) {
    final (blob, flag) = packJson(extra);
    db.execute('''
      INSERT INTO messages(id, conv_id, sender, ts, type, status,
                           is_outgoing, text, extra, extra_zstd)
      VALUES(?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET
        conv_id=excluded.conv_id, sender=excluded.sender, ts=excluded.ts,
        type=excluded.type, status=excluded.status,
        is_outgoing=excluded.is_outgoing, text=excluded.text,
        extra=excluded.extra, extra_zstd=excluded.extra_zstd;
    ''', [
      id, convId, sender, ts, type, status,
      isOutgoing ? 1 : 0, text, blob, flag,
    ]);
  }

  /// Deletes a message. `SQLITE_SECURE_DELETE` is compiled in
  /// (§21.4) — the pages are overwritten, not only freed.
  void deleteMessage(Uint8List id) {
    db.execute('DELETE FROM messages WHERE id = ?;', [id]);
  }

  /// Deletes a conversation with every message of it: `ON DELETE CASCADE`
  /// on `messages.conv_id` (`foreign_keys = ON`, see [open]), and the delete
  /// trigger takes each message's words out of the full-text index.
  void deleteConversation(Uint8List id) {
    db.execute('DELETE FROM conversations WHERE id = ?;', [id]);
  }

  // ── Reading ───────────────────────────────────────────────────────

  /// The last [limit] messages of a conversation, oldest first.
  /// That is the query that builds the chat — measured 0.08 ms at
  /// 150 000 messages, independent of the total stock.
  List<Map<String, Object?>> recentMessages(Uint8List convId,
      {int limit = 50, int? beforeTs}) {
    final rows = db.select('''
      SELECT * FROM messages
       WHERE conv_id = ? ${beforeTs != null ? 'AND ts < ?' : ''}
       ORDER BY ts DESC LIMIT ?;
    ''', [convId, ?beforeTs, limit]);
    return rows.map(_row).toList().reversed.toList();
  }

  /// ALL messages of a conversation, oldest first.
  ///
  /// **Transitional.** Stage A still keeps the stock completely
  /// in memory so that service and UI can work with it unchanged;
  /// only stage B lets both fetch page by page and makes
  /// this method superfluous. Whoever still calls it after that brings back the
  /// memory peak that the whole rebuild is meant to remove.
  List<Map<String, Object?>> messagesOf(Uint8List convId) {
    final rows = db.select(
        'SELECT * FROM messages WHERE conv_id = ? ORDER BY ts ASC;', [convId]);
    return rows.map(_row).toList();
  }

  /// Full-text search over **all** conversations. Measured 1.6 ms at
  /// 150 000 messages; the previous store needed 2 520 ms for it
  /// as soon as it no longer lay completely in memory.
  List<Map<String, Object?>> search(String query, {int limit = 100}) {
    if (query.trim().isEmpty) return const [];
    final rows = db.select('''
      SELECT m.* FROM messages_fts f
        JOIN messages m ON m.rowid = f.rowid
       WHERE messages_fts MATCH ?
       ORDER BY m.ts DESC LIMIT ?;
    ''', [_escapeFts(query), limit]);
    return rows.map(_row).toList();
  }

  /// FTS5 reads special characters as query syntax. User input is no
  /// syntax: it is passed as a string in quotation marks,
  /// embedded quotation marks doubled.
  static String _escapeFts(String q) => '"${q.replaceAll('"', '""')}"';

  Map<String, Object?> _row(Row r) => {
        'id': r['id'],
        'convId': r['conv_id'],
        'sender': r['sender'],
        'ts': r['ts'],
        'type': r['type'],
        'status': r['status'],
        'isOutgoing': (r['is_outgoing'] as int) == 1,
        'text': r['text'],
        'extra': unpackJson(r['extra'], r['extra_zstd'] as int),
      };

  /// Only for the guard: which row holds its `extra` compressed,
  /// by timestamp. Without this view a test could only check
  /// that the values come back — and they would do that even if the
  /// compression rule did not apply at all (proxy instead of statement).
  Map<int, int> debugExtraFlags() {
    final rows = db.select('SELECT ts, extra_zstd FROM messages;');
    return {
      for (final r in rows) r['ts'] as int: r['extra_zstd'] as int,
    };
  }

  /// The youngest message of a conversation, or `null`. It is all
  /// the conversation list needs for display — the start does not have to
  /// load the whole history for it.
  Map<String, Object?>? lastMessageOf(Uint8List convId) {
    final rows = db.select(
        'SELECT * FROM messages WHERE conv_id = ? ORDER BY ts DESC LIMIT 1;',
        [convId]);
    return rows.isEmpty ? null : _row(rows.first);
  }

  /// A single message by its identifier — regardless of whether
  /// its conversation is currently in memory.
  Map<String, Object?>? messageById(Uint8List id) {
    final rows = db.select('SELECT * FROM messages WHERE id = ?;', [id]);
    return rows.isEmpty ? null : _row(rows.first);
  }

  /// Number of messages of a conversation, without loading them.
  int countMessagesOf(Uint8List convId) => db.select(
      'SELECT count(*) c FROM messages WHERE conv_id = ?;',
      [convId]).first['c'] as int;

  // ── The initial reconciliation (§14.6.3, §13.5.2) ─────────────────
  //
  // A deleted message keeps its row with an empty text and `isDeleted` in
  // `extra` (`deleteMessage` of the service). "Deleted is deleted"
  // (§13.5.2): such a row is announced to nobody. Only rows with an empty
  // text are opened to tell — media rows are the others among them.

  /// Fixed part of a record's size hint besides text and `extra`: the
  /// identifiers, timestamp and flags as the wire carries them.
  static const int _kRecordFixed = 64;

  bool _isDeletedRow(Row r) {
    if ((r['text'] as String).isNotEmpty || r['extra'] == null) return false;
    final e = unpackJson(r['extra'], r['extra_zstd'] as int);
    return e?['isDeleted'] == true;
  }

  /// The manifest of [convId] (§13.5.2 phase 2): one entry per message
  /// strictly before the key ([beforeTs], [beforeId]) — `ts` DESC, `id`
  /// DESC, so that equal timestamps page without loss — at most [limit],
  /// deleted messages omitted. The next page starts at the last entry.
  List<({Uint8List id, int ts, Uint8List? sender, int type, int size})>
      manifestPage(Uint8List convId,
          {required int beforeTs, Uint8List? beforeId, int limit = 570}) {
    final out =
        <({Uint8List id, int ts, Uint8List? sender, int type, int size})>[];
    var ts = beforeTs;
    var id = beforeId;
    while (out.length < limit) {
      final rows = db.select('''
        SELECT id, ts, sender, type, text, extra, extra_zstd,
               length(CAST(text AS BLOB)) + ifnull(length(extra), 0) AS size
          FROM messages
         WHERE conv_id = ? AND ${id == null ? 'ts < ?' : '(ts < ? OR (ts = ? AND id < ?))'}
         ORDER BY ts DESC, id DESC LIMIT ?;
      ''', [convId, ts, if (id != null) ...[ts, id], limit - out.length]);
      if (rows.isEmpty) break;
      for (final r in rows) {
        if (_isDeletedRow(r)) continue;
        out.add((
          id: r['id'] as Uint8List,
          ts: r['ts'] as int,
          sender: r['sender'] as Uint8List?,
          type: r['type'] as int,
          size: (r['size'] as int) + _kRecordFixed,
        ));
      }
      ts = rows.last['ts'] as int;
      id = rows.last['id'] as Uint8List;
    }
    return out;
  }

  /// The rows of [ids] that are present, in no particular order (§13.5.2
  /// phase 3). Queried in slices below SQLite's variable limit.
  List<Map<String, Object?>> messagesByIds(List<Uint8List> ids) {
    const slice = 500;
    final out = <Map<String, Object?>>[];
    for (var i = 0; i < ids.length; i += slice) {
      final part = ids.sublist(i, i + slice < ids.length ? i + slice : ids.length);
      final rows = db.select(
          'SELECT * FROM messages WHERE id IN '
          '(${List.filled(part.length, '?').join(',')});',
          part);
      out.addAll(rows.map(_row));
    }
    return out;
  }

  /// Inserts a record only when its identifier is not present — a pulled
  /// record never overwrites what arrived meanwhile by mirroring (an edit,
  /// a deletion, a read mark). `true` when it inserted.
  bool insertMessageIfAbsent({
    required Uint8List id,
    required Uint8List convId,
    Uint8List? sender,
    required int ts,
    int type = 0,
    String status = '',
    bool isOutgoing = false,
    String text = '',
    Map<String, dynamic>? extra,
  }) {
    final (blob, flag) = packJson(extra);
    db.execute('''
      INSERT INTO messages(id, conv_id, sender, ts, type, status,
                           is_outgoing, text, extra, extra_zstd)
      VALUES(?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(id) DO NOTHING;
    ''', [
      id, convId, sender, ts, type, status,
      isOutgoing ? 1 : 0, text, blob, flag,
    ]);
    return db.updatedRows == 1;
  }

  /// What the reconciliation header announces for [convId] (§14.6.3): the
  /// messages before [beforeTs], their oldest timestamp and a size hint —
  /// deleted messages not counted.
  ({int count, int oldestTs, int bytes}) historyBefore(Uint8List convId,
      {required int beforeTs}) {
    final all = db.select('''
      SELECT count(*) c, ifnull(min(ts), 0) oldest,
             ifnull(sum(length(CAST(text AS BLOB)) + ifnull(length(extra), 0)), 0) b
        FROM messages WHERE conv_id = ? AND ts < ?;
    ''', [convId, beforeTs]).first;
    var count = all['c'] as int;
    var bytes = (all['b'] as int) + count * _kRecordFixed;
    var oldest = all['oldest'] as int;
    final empty = db.select('''
      SELECT id, ts, text, extra, extra_zstd FROM messages
       WHERE conv_id = ? AND ts < ? AND text = '' AND extra IS NOT NULL;
    ''', [convId, beforeTs]);
    final deletedTs = <int>[];
    for (final r in empty) {
      if (!_isDeletedRow(r)) continue;
      count--;
      bytes -= _kRecordFixed;
      deletedTs.add(r['ts'] as int);
    }
    if (deletedTs.contains(oldest)) {
      // The oldest row is deleted: the oldest one that is not.
      oldest = 0;
      for (var offset = 0; oldest == 0; offset += 100) {
        final rows = db.select('''
          SELECT ts, text, extra, extra_zstd FROM messages
           WHERE conv_id = ? AND ts < ? ORDER BY ts ASC LIMIT 100 OFFSET ?;
        ''', [convId, beforeTs, offset]);
        if (rows.isEmpty) break;
        for (final r in rows) {
          if (!_isDeletedRow(r)) {
            oldest = r['ts'] as int;
            break;
          }
        }
      }
    }
    return (count: count, oldestTs: oldest, bytes: bytes);
  }

  // ── State: what used to be a file of its own per collection ───────
  //
  // THERE ARE NO OLD PROFILES, and therefore no takeover step.
  //
  // Three agents independently reported "a transfer of the old stock
  // from `*.json.enc` is missing" as an open point. It is
  // none. The owner explicitly confirmed it on 04.09.2026, and
  // it is measured in the code: `FirstStartWipe.wipeProfileData`
  // (`lib/core/platform/first_start_wipe.dart`) deletes on first start
  // EVERY entry below the profile directory — `dir.listSync()`
  // plus `deleteSync(recursive: true)`, without a name list. That is
  // owner decision 3 of 03.09. ("Option A, delete everything"), and the
  // migration plan explicitly excludes profile migration code
  // (`docs/MIGRATION_V3_TO_V4_0_MYZEL.md:10315-10318`).
  //
  // Whoever in future adds a read path for old `.json.enc` files here
  // builds against a decision, not against a gap.

  // The entries themselves — `putEntry`, `removeEntry`, `areaKeys`,
  // `loadArea`, `loadAreaPrefix`, `removeAreaPrefix`, `replaceArea`,
  // `countArea` — are [EncryptedStore]'s: the device database keeps its
  // state in the same table by the same statements (S403).

  int get messageCount =>
      db.select('SELECT count(*) c FROM messages;').first['c'] as int;

  int get conversationCount =>
      db.select('SELECT count(*) c FROM conversations;').first['c'] as int;
}
