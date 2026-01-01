// The device database (S403; v4_2 §4.5.2, §4.5.3 form 2, §21.4.1, Appendix D
// D-51).
//
// "State of the device rather than of one identity lives in a second
// database of the same build, the device database, under
// `deriveSharedFileEncKey(master_seed)`" (§4.5.3). ONE file per profile,
// `<baseDir>/device.db`, built like the store of an identity
// ([EncryptedStore]): SQLite3 Multiple Ciphers, the key as `PRAGMA hexkey`,
// WAL, `synchronous = FULL`.
//
// ── WHAT LIES IN IT ────────────────────────────────────────────────────
//
// Only the state table. Its areas are named below, each with its bound
// (§20.2). There is no table for messages or conversations and no method
// that takes one: "No message, no conversation and no contact of the user
// is ever stored in it" (§21.4.1) holds by the form of this class.
//
// ── TWO PROGRAMS, ONE FILE ─────────────────────────────────────────────
//
// "On the desktop the daemon and the GUI both open it; a writer that finds
// it busy waits rather than fails" (§21.4.1). WAL lets a reader and a writer
// work at the same time; two writers take turns, and the one that comes
// second waits for [kDeviceStoreBusyTimeoutMs]. A change that reads first
// and then writes runs in [transaction], which takes the write lock at its
// start (the reason stands there).
//
// ── ONE HANDLE PER PROCESS AND PROFILE ─────────────────────────────────
//
// [at] and [atIfPresent] hand out the same handle for the same directory
// for as long as the file is there. Opening is not free (the cipher
// derives its page key at every open; measured in
// `smoke_device_store.dart`), and the readers of this database are called
// often, some from a widget's build.
//
// ── A READER DOES NOT CREATE THE FILE ──────────────────────────────────
//
// [atIfPresent] returns `null` where no file lies. A profile directory
// that was only LOOKED at stays without `device.db` — which matters because
// the file is evidence of a profile (`FirstStartWipe.baseEvidenceFiles`)
// and the installer's mark for "a profile is set up"
// (`scripts/install-desktop.sh`).
//
// ── A FILE THAT WENT AWAY UNDER AN OPEN HANDLE ─────────────────────────
//
// A wipe (`FirstStartWipe.wipeProfileData`) releases the handle of its own
// process before it deletes. For a deletion from outside, both entry
// points look whether the file is still there and drop a handle whose file
// is gone — otherwise the process would go on reading and writing a file
// no path leads to any more. NOT caught: a file that another process
// deleted AND created anew between two calls of this process; this process
// then still holds the deleted one. Dart offers no way to ask a path and an
// open file whether they are the same file. The daemon's watchdog closes
// this for the daemon (`service_daemon.dart`, `_checkProfileIntegrity`);
// a window that ran through such a replacement reads the old content until
// its next start.

import 'dart:convert';
import 'dart:io';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/storage/encrypted_store.dart';

/// Name of the device database in the profile directory (§4.5.2).
const String kDeviceStoreFileName = 'device.db';

/// Schema version, kept in `PRAGMA user_version`.
///
/// 1 — the state table, and the secret of the daemon–GUI connection drawn
///     with it (S403).
const int kDeviceStoreSchemaVersion = 1;

/// How long a statement waits for a lock another connection holds
/// (`PRAGMA busy_timeout`), in milliseconds.
///
/// The value is derived from what it has to cover and what it must not
/// exceed (measured 02.10.2026 with `smoke_device_store_two_processes` on
/// ext4/NVMe; report `mycelium/berichte/S403-GERAETE-DATENBANK-SCHRITT-1.md`):
///
///  * Lower end — how long a writer can be kept waiting. A write here is
///    one row or a handful (an identity, a setting, the device keys),
///    committed with one `fsync` of the journal: 3 ms per commit on
///    average (600 commits in 1 815 ms). The longest wait of a single
///    write was 933 ms — against a second program that committed 300 times
///    without a pause, which no caller of this database does; SQLite's
///    waiting polls with growing pauses and can lose several rounds in a
///    row. Against a program that held the lock for 1 500 ms on purpose,
///    the wait was 1 538 ms and the write succeeded.
///  * Upper end — a wait runs on the caller's thread; in the GUI that is
///    the thread that draws. A wait is worth having only while it is
///    shorter than what a user takes for a hang.
///
/// 5 000 ms is five times the longest wait measured under artificial load
/// and three times the deliberately held lock. When the time runs out the
/// statement fails with `SQLITE_BUSY`, as it would at once without the
/// setting (measured: after 5 ms); the caller sees the exception.
const int kDeviceStoreBusyTimeoutMs = 5000;

class DeviceStoreException implements Exception {
  final String message;
  const DeviceStoreException(this.message);
  @override
  String toString() => 'DeviceStoreException: $message';
}

/// The device database of ONE profile directory.
class DeviceStore extends EncryptedStore {
  /// The profile directory this database belongs to.
  final String baseDir;

  final Uint8List _key;

  DeviceStore._(super.db, super.log, this.baseDir, this._key);

  // ── The areas, and what bounds each (§20.2) ─────────────────────────
  //
  // None of them is a queue: nothing is appended here by traffic, and
  // nothing waits here to be drained. Every area holds a fixed number of
  // rows, except [areaIdentities], which holds one row per identity the
  // user has on this device.

  /// One row per identity of this device, keyed by its id (`identity-N`):
  /// display name, HD index, profile directory, creation time and the
  /// identity's switches (`Identity.toJson`). Grows only when the user
  /// creates or restores an identity, shrinks when one is deleted.
  static const String areaIdentities = 'identities';

  /// Single values of the device, one row each — the keys below.
  static const String areaDevice = 'device';

  /// [areaDevice]: the highest HD index ever assigned (`{'v': n}`). It
  /// survives the deletion of an identity, so that an index is never
  /// assigned twice.
  static const String keyMaxHdIndex = 'max_hd_index';

  /// [areaDevice]: the data port of this device (`{'v': port}`, §11.1).
  static const String keyDataPort = 'data_port';

  /// [areaDevice]: the identity the GUI showed last.
  static const String keyActiveIdentity = 'active_identity';

  /// The device keys (§4.4.2): ONE row, key [keySingle], the container of
  /// `DeviceKeysStore` as base64.
  static const String areaDeviceKeys = 'device_keys';

  /// The secret of the daemon–GUI connection (§22.1): ONE row, key
  /// [keySingle]. Written once, in the transaction that creates the
  /// database, and never again.
  static const String areaConnection = 'connection';

  /// Device-wide settings, one row per setting — a fixed set of keys, named
  /// by their owners (`port_mapping_setting.dart`,
  /// `cover_reduce_setting.dart`, `caldav_server_setting.dart`,
  /// `CleonaService`).
  static const String areaSettings = 'settings';

  /// The node's own state (§4.5.3 form 2, §11.1, §8.2, §11.9): at most
  /// THREE rows, keyed by the record names of the delivery layer
  /// (`mycelium/lib/device_records.dart`) — `host` (fixed port, device code,
  /// remembered neighbours, relays from cards), `post_box` (what this node
  /// holds for others; bounded there by `kDepositsAtMost` and the seven-day
  /// period) and `outside` (the key of the own address record). Each row
  /// is `{'b': <the record's bytes as base64>}`, written as a whole
  /// (`MyceliumDeviceRecords`, `mycelium_device_records.dart`).
  static const String areaNode = 'node';

  /// The key of the one row of an area that holds a single record.
  static const String keySingle = '_';

  static const int _connectionSecretLength = 32;

  // ── The handles of this process ─────────────────────────────────────

  static final Map<String, DeviceStore> _open = {};

  /// The name a directory has in the table above: absolute and without
  /// `.`/`..` and a trailing separator, so that two spellings of one
  /// directory get one handle. Symbolic links are not resolved.
  static String _place(String baseDir) {
    final path =
        Directory(baseDir).absolute.uri.normalizePath().toFilePath();
    final sep = Platform.pathSeparator;
    return path.length > 1 && path.endsWith(sep)
        ? path.substring(0, path.length - 1)
        : path;
  }

  /// The path of the database file of [baseDir].
  static String pathIn(String baseDir) =>
      '$baseDir${Platform.pathSeparator}$kDeviceStoreFileName';

  /// Does a device database lie in [baseDir]? Nothing is opened.
  static bool present(String baseDir) => File(pathIn(baseDir)).existsSync();

  /// The device database of [baseDir] — opened, and CREATED if it is not
  /// there. For a caller that writes. [key] is
  /// `HdWallet.deriveSharedFileEncKey(masterSeed)`.
  static DeviceStore at(String baseDir, Uint8List key, {CLogger? logger}) {
    final held = _held(baseDir, key);
    if (held != null) return held;
    Directory(baseDir).createSync(recursive: true);
    return _openAt(baseDir, key, logger);
  }

  /// The device database of [baseDir], or `null` if none lies there. For a
  /// caller that only reads: it does not create the file.
  static DeviceStore? atIfPresent(String baseDir, Uint8List key,
      {CLogger? logger}) {
    final held = _held(baseDir, key);
    if (held != null) return held;
    if (!present(baseDir)) return null;
    return _openAt(baseDir, key, logger);
  }

  /// The handle this process already holds for [baseDir], if its file is
  /// still there.
  static DeviceStore? _held(String baseDir, Uint8List key) {
    final place = _place(baseDir);
    final held = _open[place];
    if (held == null) return null;
    if (!present(baseDir)) {
      // The file went away under the open handle (header of this file).
      _open.remove(place);
      held._closeQuietly();
      return null;
    }
    if (!_sameKey(held._key, key)) {
      throw DeviceStoreException(
          'the device database of $baseDir is open in this process under '
          'another key');
    }
    return held;
  }

  /// How often the opening of a NEW file is repeated when it fails on the
  /// key ([_openAt]).
  static const int _creationAttempts = 5;

  /// Opens the file and brings it to the schema.
  ///
  /// ── TWO PROGRAMS THAT CREATE THE FILE AT THE SAME MOMENT ─────────────
  ///
  /// The cipher keeps a random salt in the first 16 bytes of the file and
  /// derives the page key from the key handed over AND that salt
  /// (`sqlite3mc_amalgamation.c`, `GenerateKeyChaCha20Cipher`). A
  /// connection reads the salt when it is keyed; on a file that is still
  /// EMPTY there is none to read, and the connection draws its own. Two
  /// programs that key the same empty file therefore hold two different
  /// page keys. Only one of them writes the first page (SQLite's file lock
  /// decides); the other one then reads a first page it cannot open and
  /// fails — with the right key in its hand.
  ///
  /// Measured before this loop existed (`smoke_device_store_two_processes`,
  /// part A, 02.10.2026): 8 of 8 simultaneous creations ended with "wrong
  /// key" in one of the two programs.
  ///
  /// The failed connection wrote nothing, and its failure says nothing
  /// about the key: it is closed and the file is opened ANEW — the salt is
  /// there now. This applies only to a file that was missing or empty when
  /// the attempt began; a file with content that does not open under [key]
  /// is the wrong key or a damaged file and is reported at once.
  static DeviceStore _openAt(String baseDir, Uint8List key, CLogger? logger) {
    final log = logger ?? CLogger.get('DeviceStore', profileDir: baseDir);
    final file = File(pathIn(baseDir));
    for (var attempt = 1;; attempt++) {
      final wasNew = !file.existsSync() || file.lengthSync() == 0;
      try {
        final store = _openOnce(baseDir, key, log);
        if (attempt > 1) {
          log.info('device database opened at attempt $attempt — another '
              'program created the file at the same moment');
        }
        return store;
      } catch (e) {
        final onKey = EncryptedStore.isNotADatabase(e) ||
            (e is DeviceStoreException &&
                e.message == EncryptedStore.wrongKeyMessage);
        if (!onKey) rethrow;
        if (!wasNew || attempt >= _creationAttempts) {
          throw const DeviceStoreException(EncryptedStore.wrongKeyMessage);
        }
        sleep(Duration(milliseconds: 20 * attempt));
      }
    }
  }

  static DeviceStore _openOnce(String baseDir, Uint8List key, CLogger log) {
    final db = EncryptedStore.openDatabase(pathIn(baseDir), key,
        fail: DeviceStoreException.new,
        busyTimeoutMs: kDeviceStoreBusyTimeoutMs);
    try {
      final store =
          DeviceStore._(db, log, baseDir, Uint8List.fromList(key));
      store._migrate();
      return _open[_place(baseDir)] = store;
    } catch (e) {
      db.close();
      rethrow;
    }
  }

  /// Closes the handle this process holds for [baseDir]. The next [at] or
  /// [atIfPresent] opens anew. MUST run before the file is deleted by this
  /// process (`FirstStartWipe.wipeProfileData`).
  static void release(String baseDir) =>
      _open.remove(_place(baseDir))?._closeQuietly();

  /// Closes every handle of this process.
  static void releaseAll() {
    for (final store in List.of(_open.values)) {
      store._closeQuietly();
    }
    _open.clear();
  }

  void _closeQuietly() {
    try {
      db.close();
    } catch (_) {}
  }

  /// Closing goes through [release]: a handle closed behind the back of
  /// the table above would be handed out again, closed.
  @override
  void close() => release(baseDir);

  static bool _sameKey(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a[i] ^ b[i];
    }
    return d == 0;
  }

  // ── Schema ──────────────────────────────────────────────────────────

  /// Brings a new file to the schema — in ONE transaction that holds the
  /// write lock from its start, so that of two programs that open a new
  /// file at the same moment one creates the table and draws the secret
  /// and the other finds both.
  void _migrate() {
    int version() =>
        db.select('PRAGMA user_version;').first.values.first as int;
    if (version() == kDeviceStoreSchemaVersion) return;
    transaction(() {
      final current = version();
      if (current == kDeviceStoreSchemaVersion) return;
      if (current != 0) {
        throw DeviceStoreException(
            'device database schema is $current, this build knows only '
            '$kDeviceStoreSchemaVersion — refusing to open rather than '
            'writing a shape another build would not recognise');
      }
      EncryptedStore.createStateTable(db);
      // "Its secret — 32 random bytes — is drawn once, when the device
      // database is created, and lives there" (§22.1).
      final random = Random.secure();
      final secret = Uint8List.fromList(List<int>.generate(
          _connectionSecretLength, (_) => random.nextInt(256)));
      putEntry(areaConnection, keySingle, {'secret': base64Encode(secret)});
      db.execute('PRAGMA user_version = $kDeviceStoreSchemaVersion;');
      log.info('device database created, schema $kDeviceStoreSchemaVersion');
    });
  }

  /// Only for the guard `smoke_device_store_two_processes`: sets the wait
  /// time of THIS handle. The guard needs it for its counter-probe — the
  /// same two programs without a wait time must fail, or the guard would
  /// not show that the wait time is what keeps them from failing.
  @visibleForTesting
  void debugSetBusyTimeout(int milliseconds) =>
      db.execute('PRAGMA busy_timeout = $milliseconds;');

  // ── The secret of the daemon–GUI connection (§22.1) ─────────────────

  /// The 32 bytes both programs derive their connection keys from. They
  /// are in every device database from the moment it exists; a database
  /// without them is damaged and is named as such.
  Uint8List connectionSecret() {
    final row = entry(areaConnection, keySingle);
    final text = row?['secret'] as String?;
    final secret = text == null ? null : base64Decode(text);
    if (secret == null || secret.length != _connectionSecretLength) {
      throw DeviceStoreException(
          'the device database of $baseDir carries no connection secret of '
          '$_connectionSecretLength bytes');
    }
    return secret;
  }
}
