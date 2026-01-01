// The common ground of the two encrypted databases (S403, v4_2 §4.5.3
// forms 1 and 2, §21.4.1).
//
// There are two databases of ONE build: the store of an identity
// (`messages.db`, `message_store.dart`) and the device database
// (`device.db`, `device_store.dart`). What makes them "the same build" lives
// here and exists once: how the file is opened (key, journal, durability),
// the state table with its areas, and the compression rule of its values.
// What differs — the tables for messages and their full-text index — stays
// with the store of the identity; the device database has none of it and
// cannot be handed a message (§21.4.1: "No message, no conversation and no
// contact of the user is ever stored in it").
//
// This file was cut out of `message_store.dart`, not written beside it:
// the statements below ran there unchanged until S403.

import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:cleona/core/codec/compression.dart';
import 'package:cleona/core/log/clogger.dart';

/// Lower bound of the SQLite version. **Normative** (§21.4): CVE-2026-11822
/// and CVE-2026-11824 are memory errors in FTS5, fixed in
/// 3.53.2/3.53.3. Neither database opens on an older version
/// — otherwise the assurance from §21.4 carries nothing.
const String kMinSqliteVersion = '3.53.3';

/// HOW THE LIBRARY GETS INTO THE PROCESS. Not via `DynamicLibrary`
/// as with libsodium: `package:sqlite3` since 3.5 compiles the source
/// itself via a build hook, and `pubspec.yaml` points it to our
/// vendored amalgamation together with the switches that §4.5.3 and §21.4
/// assure (`SQLITE_TEMP_STORE=3`, `SQLITE_SECURE_DELETE`). Thus there is
/// exactly ONE place where the store library is described, and
/// it applies to all five platforms. `native/cleona_store/` keeps
/// its own CMake alongside — not for the app, but for the
/// gate with the reverse probe, which must be able to run without Dart.
abstract class EncryptedStore {
  @protected
  final Database db;

  @protected
  final CLogger log;

  EncryptedStore(this.db, this.log);

  /// Opens (or creates) the database file under [path] and returns the
  /// handle — keyed, in WAL mode, with `synchronous = FULL`. The schema is
  /// the caller's.
  ///
  /// [key] are the **raw 32 bytes** of a seed-derived key. It is passed
  /// as `PRAGMA hexkey`, not as `PRAGMA key`: `key` expects a
  /// passphrase and derives from it; our key is already
  /// seed-derived, a second derivation on top would bring nothing.
  ///
  /// [busyTimeoutMs] is how long a statement waits for a lock another
  /// connection holds before it fails with `SQLITE_BUSY`. `null` leaves
  /// SQLite's default (no waiting): right for a file that ONE process
  /// opens, wrong for one that two open (§21.4.1, `device_store.dart`).
  ///
  /// [fail] builds the exception of the calling store, so that a caller
  /// sees the type of the database it opened.
  @protected
  static Database openDatabase(
    String path,
    Uint8List key, {
    required Exception Function(String message) fail,
    int? busyTimeoutMs,
  }) {
    if (key.length != 32) {
      throw fail('key must be 32 bytes, got ${key.length}');
    }

    assertSqliteVersion(fail);

    final db = sqlite3.open(path);
    try {
      // Order is load-bearing: the key MUST come before every other
      // statement, otherwise SQLite creates the file unencrypted.
      db.execute("PRAGMA hexkey = '${_hex(key)}';");

      // Before the first statement that takes a lock: the query below and
      // the journal switch both can meet another connection's lock.
      if (busyTimeoutMs != null) {
        db.execute('PRAGMA busy_timeout = $busyTimeoutMs;');
      }

      // First real query — it fails if the key does not
      // match. Without it one would only find out on the first read.
      db.select('SELECT count(*) FROM sqlite_master;');

      db.execute('PRAGMA journal_mode = WAL;');
      db.execute('PRAGMA foreign_keys = ON;');
      db.execute('PRAGMA synchronous = FULL;');
      return db;
    } catch (e) {
      db.close();
      if (isNotADatabase(e)) throw fail(wrongKeyMessage);
      rethrow;
    }
  }

  /// What a store says when the file does not open under the key given.
  static const String wrongKeyMessage =
      'wrong key, or the file is not a Cleona store';

  /// Is [e] SQLite's answer to a first page it cannot read under the key
  /// of this connection?
  @protected
  static bool isNotADatabase(Object e) =>
      e.toString().contains('file is not a database');

  /// §21.4 normative: FTS5 below 3.53.3 carries two known
  /// memory errors. The store does not open there.
  @protected
  static void assertSqliteVersion(Exception Function(String message) fail) {
    final v = sqlite3.version.libVersion;
    if (_compareVersions(v, kMinSqliteVersion) < 0) {
      throw fail('SQLite $v is below the required $kMinSqliteVersion '
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

  // ── The state table ───────────────────────────────────────────────
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

  /// Creates the state table. Called by the schema step of the store that
  /// owns the file, inside its transaction.
  @protected
  static void createStateTable(Database db) {
    db.execute('''
      CREATE TABLE state(
        area        TEXT NOT NULL,
        entry_key   TEXT NOT NULL,
        data        BLOB NOT NULL,
        data_zstd   INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(area, entry_key)
      ) WITHOUT ROWID;
    ''');
  }

  // ── Compression of a JSON value ───────────────────────────────────
  //
  // The rule from §4.5.3: measure instead of guess. If zstd brings less than
  // 10 %, the plaintext is stored and the flag stays 0.

  static const int _minCompressionGain = 10; // percent

  @protected
  (Uint8List?, int) packJson(Map<String, dynamic>? value) {
    if (value == null || value.isEmpty) return (null, 0);
    final raw = Uint8List.fromList(utf8.encode(jsonEncode(value)));
    if (raw.length < 128) return (raw, 0); // pointless below the frame size
    final packed = ZstdCompression.instance.compress(raw, level: 3);
    final gain = 100 - (packed.length * 100 ~/ raw.length);
    if (gain < _minCompressionGain) return (raw, 0);
    return (packed, 1);
  }

  @protected
  Map<String, dynamic>? unpackJson(Object? blob, int flag) {
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

  // ── Transactions ──────────────────────────────────────────────────

  int _transactionDepth = 0;

  /// Runs [body] as ONE transaction: all of it or none of it.
  ///
  /// `BEGIN IMMEDIATE`, not `BEGIN`: the write lock is taken at the start.
  /// A transaction that begins by READING and then writes cannot be made to
  /// wait for another connection's commit — SQLite fails it at once, the
  /// wait time does not apply to it — and what it read may be stale by the
  /// time it writes. Taken at the start, the lock waits like every other
  /// (`busy_timeout`), and what [body] reads is what it then changes.
  ///
  /// A call inside [body] joins the running transaction.
  T transaction<T>(T Function() body) {
    if (_transactionDepth > 0) return body();
    db.execute('BEGIN IMMEDIATE;');
    _transactionDepth++;
    try {
      final result = body();
      db.execute('COMMIT;');
      return result;
    } catch (e) {
      // SQLite has already ended the transaction itself after some errors
      // (disk full, I/O error); a second failure here must not hide the
      // first one.
      try {
        db.execute('ROLLBACK;');
      } catch (_) {}
      rethrow;
    } finally {
      _transactionDepth--;
    }
  }

  // ── State: what used to be a file of its own per collection ───────

  /// Writes ONE entry. That is the path that brings the granularity:
  /// a change to a contact costs one row, not the whole
  /// collection.
  void putEntry(String area, String key, Map<String, dynamic> data) {
    final (blob, flag) = packJson(data);
    db.execute('''
      INSERT INTO state(area, entry_key, data, data_zstd)
      VALUES(?,?,?,?)
      ON CONFLICT(area, entry_key) DO UPDATE SET
        data=excluded.data, data_zstd=excluded.data_zstd;
    ''', [area, key, blob ?? Uint8List(0), flag]);
  }

  void removeEntry(String area, String key) {
    db.execute('DELETE FROM state WHERE area = ? AND entry_key = ?;',
        [area, key]);
  }

  /// The keys of an area, without reading (and unpacking) its values.
  List<String> areaKeys(String area) => [
        for (final r in db
            .select('SELECT entry_key FROM state WHERE area = ?;', [area]))
          r['entry_key'] as String,
      ];

  /// ONE entry, or `null` if it is not there.
  Map<String, dynamic>? entry(String area, String key) {
    final rows = db.select(
        'SELECT data, data_zstd FROM state WHERE area = ? AND entry_key = ?;',
        [area, key]);
    if (rows.isEmpty) return null;
    return unpackJson(rows.first['data'], rows.first['data_zstd'] as int);
  }

  /// All entries of an area.
  Map<String, Map<String, dynamic>> loadArea(String area) {
    final rows = db.select(
        'SELECT entry_key, data, data_zstd FROM state WHERE area = ?;',
        [area]);
    final out = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      final d = unpackJson(r['data'], r['data_zstd'] as int);
      if (d != null) out[r['entry_key'] as String] = d;
    }
    return out;
  }

  /// The entries of an area whose key begins with [prefix] — a range read
  /// on the primary key `(area, entry_key)`, so its cost follows the number
  /// of entries FOUND, not the size of the area. For an area keyed by a
  /// compound name (`<owner>:<item>`): the items of one owner without
  /// reading every other owner's.
  Map<String, Map<String, dynamic>> loadAreaPrefix(String area, String prefix) {
    final rows = db.select(
        'SELECT entry_key, data, data_zstd FROM state '
        'WHERE area = ? AND entry_key >= ? AND entry_key < ?;',
        [area, prefix, _afterPrefix(prefix)]);
    final out = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      final d = unpackJson(r['data'], r['data_zstd'] as int);
      if (d != null) out[r['entry_key'] as String] = d;
    }
    return out;
  }

  /// Removes every entry of an area whose key begins with [prefix], in ONE
  /// statement. Returns how many went.
  int removeAreaPrefix(String area, String prefix) {
    db.execute(
        'DELETE FROM state '
        'WHERE area = ? AND entry_key >= ? AND entry_key < ?;',
        [area, prefix, _afterPrefix(prefix)]);
    return db.updatedRows;
  }

  /// The smallest key that is greater than every key beginning with
  /// [prefix]: the prefix with its last code unit raised by one. The keys
  /// compare bytewise (`BINARY`, the column's default collation), and a
  /// prefix ends in an ASCII separator here — raising it stays one byte.
  static String _afterPrefix(String prefix) {
    if (prefix.isEmpty) {
      throw ArgumentError('an empty prefix names the whole area');
    }
    final last = prefix.codeUnitAt(prefix.length - 1);
    if (last >= 0x7f) {
      throw ArgumentError('the prefix must end in an ASCII character');
    }
    return prefix.substring(0, prefix.length - 1) +
        String.fromCharCode(last + 1);
  }

  /// Replaces a whole area in ONE transaction.
  ///
  /// For collections whose callers today call "save everything" and
  /// for which the switch to individual writes is not worth it (a
  /// few dozen entries). Whoever writes a GROWING collection this way
  /// brings back the full write against which the table was built
  /// — that is where [putEntry] belongs.
  void replaceArea(String area, Map<String, Map<String, dynamic>> all) {
    transaction(() {
      db.execute('DELETE FROM state WHERE area = ?;', [area]);
      for (final e in all.entries) {
        putEntry(area, e.key, e.value);
      }
    });
  }

  int countArea(String area) => db.select(
      'SELECT count(*) c FROM state WHERE area = ?;',
      [area]).first['c'] as int;

  /// Only for the guards: the raw handle, for statements about the
  /// SCHEMA itself (`PRAGMA user_version`, the shape of a table, a
  /// constraint's own refusal). A test that goes through a method of
  /// the store measures that method, not the table under it — the same
  /// reasoning as [debugTableNames], only for statements the named
  /// methods do not carry.
  @visibleForTesting
  Database get debugDb => db;

  /// Only for the guards: the names of the tables this file carries. The
  /// statement "the device database has no table for messages" is checked
  /// on the schema itself, not on the absence of a method.
  @visibleForTesting
  List<String> debugTableNames() => [
        for (final r in db.select(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            'ORDER BY name;'))
          r['name'] as String,
      ];

  /// Only for the guards: SQLite's own verdict on the file
  /// (`PRAGMA integrity_check`), `ok` for an undamaged one.
  @visibleForTesting
  String debugIntegrityCheck() => db
      .select('PRAGMA integrity_check;')
      .map((r) => r.values.first.toString())
      .join('; ');

  void close() => db.close();
}
