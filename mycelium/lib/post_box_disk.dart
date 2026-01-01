import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:mycelium/pair.dart' show kCodeLength;

/// The disk under the post box: what a holder holds FOR OTHERS,
/// across a restart.
///
/// Why at all: the deposit is the fourth and last ladder step and
/// thus the only route to an absent recipient. The retention period
/// is set to seven days — but if the holder kept its sendings only in
/// memory, a message to someone who was just off was
/// gone at the next start of any holder. Seven days of promise and
/// one process lifetime of reality.
///
/// This file stands next to `post_box_deposit.dart` because that one would otherwise
/// exceed the line budget. The budget has no exception mechanism:
/// if it does not fit, the design is wrong, not the limit. Here, however, it is
/// NOT an `extension` as in `node_amendment.dart`/`group_read.dart`
/// — an extension in a foreign file would not reach the internals of the
/// deposit (`_storage`, `_idToValue`) at all, Dart privacy
/// applies per file, not per class. The cut therefore runs along the
/// task: over there the five packets and the deadlines, here the
/// file format. This file knows no packet, no neighbour and no
/// kind; [DepositRecord.content] stays opaque to it throughout.
///
/// Encrypted and atomic writing is done by [FileEncryption] (`.enc.tmp` +
/// rename) — the same tool and the same handwriting as in
/// `memory.dart`, not a second way of doing the same. Folder and
/// key come from outside; no key is derived here.
///
/// ── FILE LAYOUT ───────────────────────────────────────────────────────
/// ```
/// version (1 B)
/// number of records (u32 big-endian)
/// per record:  id (8 B) | day value (16 B) | stored (u64 ms)
///              | content length (u32) | content
/// ```
/// No JSON: [DepositRecord.content] is foreign, sealed bytes, not
/// text — Base64 around it would be pure overhead without benefit.

/// A record on disk: exactly what a holder knows about a foreign
/// sending, and not a byte more.
typedef DepositRecord = ({
  Uint8List id,
  Uint8List value,
  Uint8List content,
  DateTime inserted,
});

/// The file is there, but unusable: wrong key, truncated,
/// unknown version, bent bytes. Thrown out of [PostBoxDisk.load]
/// BEFORE the return — there is never a half-filled deposit.
class DepositError implements Exception {
  final String reason;
  DepositError(this.reason);
  @override
  String toString() => 'AblageFehler: $reason';
}

/// Reads a byte bundle with a running pointer; throws [DepositError]
/// as soon as fewer bytes are there than needed. Word for word like the `_Leser` in
/// `memory.dart` except for the error kind — both are file-private,
/// a shared one would be a third module for forty lines.
class _Reader {
  final Uint8List _b;
  int _i = 0;
  _Reader(this._b);

  int get _rest => _b.length - _i;

  void _check(int n) {
    if (n < 0) throw DepositError('negative length $n');
    if (_rest < n) {
      throw DepositError('File too short: $n B needed, $_rest B present');
    }
  }

  int byte() {
    _check(1);
    return _b[_i++];
  }

  Uint8List bytes(int n) {
    _check(n);
    final r = Uint8List.fromList(_b.sublist(_i, _i + n));
    _i += n;
    return r;
  }

  int u32() {
    _check(4);
    final v = ByteData.sublistView(_b, _i, _i + 4).getUint32(0, Endian.big);
    _i += 4;
    return v;
  }

  int u64() {
    _check(8);
    final v = ByteData.sublistView(_b, _i, _i + 8).getUint64(0, Endian.big);
    _i += 8;
    return v;
  }

  void done() {
    if (_rest != 0) {
      throw DepositError('$_rest surplus bytes at the end');
    }
  }
}

/// [FileEncryption] appends `.enc` itself; on disk therefore lies
/// `briefkasten.enc` (briefly while writing: `.enc.tmp`).
const String _fileName = 'post_box';

/// Version 2 (S391, proposal M): records lie under the 16-B day value
/// instead of under the 32-B identifier. An OLDER version is discarded —
/// file deleted, result empty (4.2: no migration, the old stock
/// would lie under identifiers that no collector asks for any more). A NEWER one is
/// a [DepositError]: it would otherwise overwrite stock that this version
/// does not understand.
const int _version = 2;

/// Lengths that are fixed in the format. [kIdLength] must match the id length in
/// `post_box_deposit.dart`; [kValueLength] is the day value from
/// `pair.dart`.
const int kIdLength = 8;
const int kValueLength = kCodeLength;

/// The encrypted storage file of a holder.
class PostBoxDisk {
  final FileEncryption _enc;
  final String _path;

  PostBoxDisk._(this._enc, this._path);

  /// Sets up the disk in [directory]; [key] is passed through unchanged to
  /// [FileEncryption]. Creates the folder, reads nothing yet.
  static PostBoxDisk open(Directory directory, Uint8List key) {
    directory.createSync(recursive: true);
    return PostBoxDisk._(
      FileEncryption(baseDir: directory.path, key: key),
      '${directory.path}/$_fileName',
    );
  }

  /// The path without `.enc` — for reports and probes.
  String get path => _path;

  /// Reads the records back, oldest first, and in doing so leaves out everything
  /// that was stored BEFORE [limit].
  ///
  /// The retention period thus already applies at LOADING and not only at the
  /// next touch: a record must not become immortal because
  /// the holder restarts often.
  ///
  /// If no file is there, the result is empty — a holder without
  /// history is the normal case, not an error. If one is there that
  /// cannot be read, this method throws [DepositError] instead of
  /// silently continuing with half the stock.
  List<DepositRecord> load({required DateTime limit}) {
    // The side files count too: [FileEncryption.readBinaryFile] recovers
    // from them what a crash in the middle of writing left lying around.
    final there = File('$_path.enc').existsSync() ||
        File('$_path.enc.tmp').existsSync() ||
        File('$_path.enc.old').existsSync();
    if (!there) return <DepositRecord>[];
    final bytes = _enc.readBinaryFile(_path);
    if (bytes == null) {
      throw DepositError('$_path.enc exists, but cannot be read '
          '— wrong key or damaged file');
    }
    return _decode(bytes, limit);
  }

  /// Writes [records] encrypted and atomically (`FileEncryption.
  /// writeBinaryFile`: first `.enc.tmp`, then renamed). A crash
  /// between both steps leaves the previous `briefkasten.enc`
  /// intact — there is never an intermediate version under the canonical
  /// name.
  void save(Iterable<DepositRecord> records) =>
      _enc.writeBinaryFile(_path, _encode(records));

  Uint8List _encode(Iterable<DepositRecord> records) {
    final list = records.toList();
    final b = BytesBuilder();
    b.addByte(_version);
    b.add(_u32(list.length));
    for (final s in list) {
      if (s.id.length != kIdLength) {
        throw ArgumentError('id must be $kIdLength B, was ${s.id.length}');
      }
      if (s.value.length != kValueLength) {
        throw ArgumentError(
            'Value must be $kValueLength B, was ${s.value.length}');
      }
      b.add(s.id);
      b.add(s.value);
      b.add(_u64(s.inserted.millisecondsSinceEpoch));
      b.add(_u32(s.content.length));
      b.add(s.content);
    }
    return b.toBytes();
  }

  List<DepositRecord> _decode(Uint8List bytes, DateTime limit) {
    try {
      final l = _Reader(bytes);
      final version = l.byte();
      if (version < _version) return _drop();
      if (version != _version) {
        throw DepositError('unknown version $version');
      }
      final count = l.u32();
      final records = <DepositRecord>[];
      for (var i = 0; i < count; i++) {
        final id = l.bytes(kIdLength);
        final value = l.bytes(kValueLength);
        final inserted = DateTime.fromMillisecondsSinceEpoch(l.u64());
        final content = l.bytes(l.u32());
        // The deadline applies AFTER the complete reading of the record: an
        // expired record is passed over, not skipped — the
        // pointer must still stand exactly behind it, otherwise the
        // next record falls apart.
        if (inserted.isBefore(limit)) continue;
        records.add(
            (id: id, value: value, content: content, inserted: inserted));
      }
      l.done();
      return records;
    } on DepositError {
      rethrow;
    } catch (e) {
      throw DepositError('Content damaged: $e');
    }
  }

  /// Old stock of an earlier version: gone, together with side files.
  List<DepositRecord> _drop() {
    for (final ending in const ['.enc', '.enc.tmp', '.enc.old']) {
      final f = File('$_path$ending');
      if (f.existsSync()) f.deleteSync();
    }
    return <DepositRecord>[];
  }
}

Uint8List _u32(int v) =>
    (ByteData(4)..setUint32(0, v, Endian.big)).buffer.asUint8List();
Uint8List _u64(int v) =>
    (ByteData(8)..setUint64(0, v, Endian.big)).buffer.asUint8List();
