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

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'package:cleona/core/codec/compression.dart';
import 'package:cleona/core/log/clogger.dart';

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
const int kMessageStoreSchemaVersion = 3;

/// Lower bound of the SQLite version. **Normative** (§21.4): CVE-2026-11822
/// and CVE-2026-11824 are memory errors in FTS5, fixed in
/// 3.53.2/3.53.3. The store refuses to open on an older version
/// — otherwise the assurance from §21.4 carries nothing.
const String kMinSqliteVersion = '3.53.3';

class MessageStoreException implements Exception {
  final String message;
  const MessageStoreException(this.message);
  @override
  String toString() => 'MessageStoreException: $message';
}

/// HOW THE LIBRARY GETS INTO THE PROCESS. Not via `DynamicLibrary`
/// as with libsodium: `package:sqlite3` since 3.5 compiles the source
/// itself via a build hook, and `pubspec.yaml` points it to our
/// vendored amalgamation together with the switches that §4.5.3 and §21.4
/// assure (`SQLITE_TEMP_STORE=3`, `SQLITE_SECURE_DELETE`). Thus there is
/// exactly ONE place where the store library is described, and
/// it applies to all five platforms. `native/cleona_store/` keeps
/// its own CMake alongside — not for the app, but for the
/// gate with the reverse probe, which must be able to run without Dart.

/// An encrypted store. **One per identity** (§21.4): a
/// shared one would have to lie under the device-wide key and would thus give
/// up the separation that `deriveFileEncKey` establishes.
class MessageStore {
  final Database _db;
  final CLogger _log;

  MessageStore._(this._db, this._log);

  /// Opens (or creates) the store under [path].
  ///
  /// [key] are the **raw 32 bytes** from
  /// `HdWallet.deriveFileEncKey(masterSeed, hdIndex)`. It is passed
  /// as `PRAGMA hexkey`, not as `PRAGMA key`: `key` expects a
  /// passphrase and derives from it; our key is already
  /// seed-derived, a second derivation on top would bring nothing.
  static MessageStore open(String path, Uint8List key, {CLogger? logger}) {
    // `profileDir` is mandatory, not decoration: without it `CLogger` keeps the
    // lines only in the ring and writes to NO file — a store whose
    // open errors are recorded nowhere cannot be investigated in the field.
    // The directory of the store IS the profile directory.
    final log = logger ??
        CLogger.get('MessageStore',
            profileDir: File(path).parent.path);

    if (key.length != 32) {
      throw MessageStoreException(
          'key must be 32 bytes, got ${key.length}');
    }

    _assertSqliteVersion();

    final db = sqlite3.open(path);
    try {
      // Order is load-bearing: the key MUST come before every other
      // statement, otherwise SQLite creates the file unencrypted.
      db.execute("PRAGMA hexkey = '${_hex(key)}';");

      // First real query — it fails if the key does not
      // match. Without it one would only find out on the first read.
      db.select('SELECT count(*) FROM sqlite_master;');

      db.execute('PRAGMA journal_mode = WAL;');
      db.execute('PRAGMA foreign_keys = ON;');
      db.execute('PRAGMA synchronous = FULL;');

      final store = MessageStore._(db, log);
      store._migrate();
      return store;
    } catch (e) {
      db.close();
      if (e.toString().contains('file is not a database')) {
        throw const MessageStoreException(
            'wrong key, or the file is not a Cleona store');
      }
      rethrow;
    }
  }

  /// §21.4 normative: FTS5 below 3.53.3 carries two known
  /// memory errors. The store does not open there.
  static void _assertSqliteVersion() {
    final v = sqlite3.version.libVersion;
    if (_compareVersions(v, kMinSqliteVersion) < 0) {
      throw MessageStoreException(
          'SQLite $v is below the required $kMinSqliteVersion '
          '(CVE-2026-11822 / CVE-2026-11824 in FTS5)');
    }
  }

  static int _compareVersions(String a, String b) {
    final pa = a.split('.').map(int.tryParse).toList();
    final pb = b.split('.').map(int.tryParse).toList();
    for (var i = 0; i < 3; i++) {
      final x = (i < pa.length ? pa[i] : 0) ?? 0;
      final y = (i < pb.length ? pb[i] : 0) ?? 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  static String _hex(Uint8List b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  // ── Schema ────────────────────────────────────────────────────────
  //
  // Identifiers are stored as BLOB, not as hex text. Measured (S366): that
  // alone is 27 % of the database size — more than the entire
  // text compression yields (12-17 %), because the surcharge acts
  // threefold: in the row, in the primary key and in the index.

  void _migrate() {
    final current = _db.select('PRAGMA user_version;').first.values.first as int;
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

    _db.execute('BEGIN;');
    try {
      if (current < 1) {
        // `extra` carries the fields that are neither searched nor
        // sorted by (`config`, the pending proposal, the
        // notification choice) — the same construction as for `messages`.
        // Five individual columns for it would be five schema changes for
        // every new field; here it is none.
        _db.execute('''
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
        _db.execute('''
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
        _db.execute(
            'CREATE INDEX ix_msg_conv_ts ON messages(conv_id, ts DESC);');
        // Full-text index with external content: the index holds only the
        // tokens, the text stays in `messages`. No second text stock.
        _db.execute('''
          CREATE VIRTUAL TABLE messages_fts USING fts5(
            text, content='messages', content_rowid='rowid'
          );
        ''');
        // The three triggers keep the index congruent. Without them
        // the search would find deleted messages and miss new ones —
        // an index that silently diverges is worse than none.
        _db.execute('''
          CREATE TRIGGER messages_fts_ai AFTER INSERT ON messages BEGIN
            INSERT INTO messages_fts(rowid, text) VALUES (new.rowid, new.text);
          END;
        ''');
        _db.execute('''
          CREATE TRIGGER messages_fts_ad AFTER DELETE ON messages BEGIN
            INSERT INTO messages_fts(messages_fts, rowid, text)
              VALUES ('delete', old.rowid, old.text);
          END;
        ''');
        _db.execute('''
          CREATE TRIGGER messages_fts_au AFTER UPDATE ON messages BEGIN
            INSERT INTO messages_fts(messages_fts, rowid, text)
              VALUES ('delete', old.rowid, old.text);
            INSERT INTO messages_fts(rowid, text) VALUES (new.rowid, new.text);
          END;
        ''');
      }
      if (current < 2) {
        // ── The state table ────────────────────────────────────────
        //
        // It replaces the individual JSON files per collection (contacts,
        // polls, calendar, …). The gain is NOT "everything in one
        // place", but the granularity: a change writes ONE row.
        // The files were rewritten completely on every change —
        // the same pattern that led to the quadratic curve for the messages,
        // only on a small scale and in thirteen copies.
        //
        // `area` is the name of the superseded file without extension
        // ('contacts', 'polls', …), `entry_key` the identifier within
        // the collection. An area without a natural identifier (a
        // single settings store) uses the key '_'.
        //
        // NO table of its own per collection: the collections differ
        // only in name, not in form, and thirteen tables
        // would be thirteen schema changes for every new collection.
        _db.execute('''
          CREATE TABLE state(
            area        TEXT NOT NULL,
            entry_key   TEXT NOT NULL,
            data        BLOB NOT NULL,
            data_zstd   INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY(area, entry_key)
          ) WITHOUT ROWID;
        ''');
      }
      _db.execute('PRAGMA user_version = $kMessageStoreSchemaVersion;');
      _db.execute('COMMIT;');
      _log.info('message store schema at $kMessageStoreSchemaVersion');
    } catch (e) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  // ── Compression of the `extra` column ─────────────────────────────
  //
  // The rule from §4.5.3: measure instead of guess. If zstd brings less than
  // 10 %, the plaintext is stored and `extra_zstd` stays 0.

  static const int _minCompressionGain = 10; // percent

  (Uint8List?, int) _packExtra(Map<String, dynamic>? extra) {
    if (extra == null || extra.isEmpty) return (null, 0);
    final raw = Uint8List.fromList(utf8.encode(jsonEncode(extra)));
    if (raw.length < 128) return (raw, 0); // pointless below the frame size
    final packed = ZstdCompression.instance.compress(raw, level: 3);
    final gain = 100 - (packed.length * 100 ~/ raw.length);
    if (gain < _minCompressionGain) return (raw, 0);
    return (packed, 1);
  }

  Map<String, dynamic>? _unpackExtra(Object? blob, int flag) {
    if (blob == null) return null;
    final bytes = blob is Uint8List ? blob : Uint8List.fromList(blob as List<int>);
    // AN EMPTY VALUE IS A VALUE. [putEntry] stores an empty map as a
    // blob of LENGTH 0 (`blob ?? Uint8List(0)`), not as NULL —
    // and `jsonDecode('')` threw a FormatException on it that flew OUT of
    // [loadArea]. Thus not the one entry was unreadable,
    // but the WHOLE AREA.
    //
    // Re-measured on 04.09.2026 at `80035a94`: two tombstones in
    // `contacts_deleted` (there it says `const <String, dynamic>{}`) ->
    // `countArea` = 2, `loadArea` throws. `_loadContacts` reads the
    // tombstones BEFORE the contacts, catches the error and leaves
    // `_contactsLoaded` at false — a profile with even ONE
    // deleted contact would have shown no contacts at all
    // after the restart.
    if (bytes.isEmpty) return const <String, dynamic>{};
    final raw =
        flag == 1 ? ZstdCompression.instance.decompress(bytes) : bytes;
    return jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
  }

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
    final (blob, flag) = _packExtra(extra);
    _db.execute('''
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
    final rows = _db.select(
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
              'extra': _unpackExtra(r['extra'], r['extra_zstd'] as int),
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
    final (blob, flag) = _packExtra(extra);
    _db.execute('''
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
    _db.execute('DELETE FROM messages WHERE id = ?;', [id]);
  }

  void deleteConversation(Uint8List id) {
    _db.execute('DELETE FROM conversations WHERE id = ?;', [id]);
  }

  // ── Reading ───────────────────────────────────────────────────────

  /// The last [limit] messages of a conversation, oldest first.
  /// That is the query that builds the chat — measured 0.08 ms at
  /// 150 000 messages, independent of the total stock.
  List<Map<String, Object?>> recentMessages(Uint8List convId,
      {int limit = 50, int? beforeTs}) {
    final rows = _db.select('''
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
    final rows = _db.select(
        'SELECT * FROM messages WHERE conv_id = ? ORDER BY ts ASC;', [convId]);
    return rows.map(_row).toList();
  }

  /// Full-text search over **all** conversations. Measured 1.6 ms at
  /// 150 000 messages; the previous store needed 2 520 ms for it
  /// as soon as it no longer lay completely in memory.
  List<Map<String, Object?>> search(String query, {int limit = 100}) {
    if (query.trim().isEmpty) return const [];
    final rows = _db.select('''
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
        'extra': _unpackExtra(r['extra'], r['extra_zstd'] as int),
      };

  /// Only for the guard: which row holds its `extra` compressed,
  /// by timestamp. Without this view a test could only check
  /// that the values come back — and they would do that even if the
  /// compression rule did not apply at all (proxy instead of statement).
  Map<int, int> debugExtraFlags() {
    final rows = _db.select('SELECT ts, extra_zstd FROM messages;');
    return {
      for (final r in rows) r['ts'] as int: r['extra_zstd'] as int,
    };
  }

  /// The youngest message of a conversation, or `null`. It is all
  /// the conversation list needs for display — the start does not have to
  /// load the whole history for it.
  Map<String, Object?>? lastMessageOf(Uint8List convId) {
    final rows = _db.select(
        'SELECT * FROM messages WHERE conv_id = ? ORDER BY ts DESC LIMIT 1;',
        [convId]);
    return rows.isEmpty ? null : _row(rows.first);
  }

  /// A single message by its identifier — regardless of whether
  /// its conversation is currently in memory.
  Map<String, Object?>? messageById(Uint8List id) {
    final rows = _db.select('SELECT * FROM messages WHERE id = ?;', [id]);
    return rows.isEmpty ? null : _row(rows.first);
  }

  /// Number of messages of a conversation, without loading them.
  int countMessagesOf(Uint8List convId) => _db.select(
      'SELECT count(*) c FROM messages WHERE conv_id = ?;',
      [convId]).first['c'] as int;

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

  /// Writes ONE entry. That is the path that brings the granularity:
  /// a change to a contact costs one row, not the whole
  /// collection.
  void putEntry(String area, String key, Map<String, dynamic> data) {
    final (blob, flag) = _packExtra(data);
    _db.execute('''
      INSERT INTO state(area, entry_key, data, data_zstd)
      VALUES(?,?,?,?)
      ON CONFLICT(area, entry_key) DO UPDATE SET
        data=excluded.data, data_zstd=excluded.data_zstd;
    ''', [area, key, blob ?? Uint8List(0), flag]);
  }

  void removeEntry(String area, String key) {
    _db.execute('DELETE FROM state WHERE area = ? AND entry_key = ?;',
        [area, key]);
  }

  /// All entries of an area.
  Map<String, Map<String, dynamic>> loadArea(String area) {
    final rows = _db.select(
        'SELECT entry_key, data, data_zstd FROM state WHERE area = ?;',
        [area]);
    final out = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      final d = _unpackExtra(r['data'], r['data_zstd'] as int);
      if (d != null) out[r['entry_key'] as String] = d;
    }
    return out;
  }

  /// Replaces a whole area in ONE transaction.
  ///
  /// For collections whose callers today call "save everything" and
  /// for which the switch to individual writes is not worth it (a
  /// few dozen entries). Whoever writes a GROWING collection this way
  /// brings back the full write against which the table was built
  /// — that is where [putEntry] belongs.
  void replaceArea(String area, Map<String, Map<String, dynamic>> all) {
    _db.execute('BEGIN;');
    try {
      _db.execute('DELETE FROM state WHERE area = ?;', [area]);
      for (final e in all.entries) {
        putEntry(area, e.key, e.value);
      }
      _db.execute('COMMIT;');
    } catch (e) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  int countArea(String area) => _db.select(
      'SELECT count(*) c FROM state WHERE area = ?;',
      [area]).first['c'] as int;

  int get messageCount =>
      _db.select('SELECT count(*) c FROM messages;').first['c'] as int;

  int get conversationCount =>
      _db.select('SELECT count(*) c FROM conversations;').first['c'] as int;

  void close() => _db.close();
}
