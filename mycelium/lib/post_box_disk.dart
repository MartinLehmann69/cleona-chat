import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/file_encryption.dart' show FileEncryption;
import 'package:mycelium/device_records.dart';
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
/// WHERE the bytes lie is handed in ([DeviceRecords], S403): in the app a
/// row of the device database (V4.2 §4.5.3 form 2), in probes the encrypted
/// file of [FileEncryption]. No key is derived here.
///
/// ── LAYOUT: ONE ROW PER HELD PACKET (v4_2 §4.5.3, owner 15.10.2026) ──
/// ```
/// name:  post_box/<id as 16 hex digits>
/// bytes: version (1 B) | id (8 B) | day value (16 B) | stored (u64 ms)
///        | content
/// ```
/// A deposit writes its row, a delete receipt or an expiry removes its row;
/// the stock is never written or read as one value. Until S407 it was ONE
/// record `post_box` (version 2: count, then every record) rewritten as a
/// whole at every change — 11.3 MB of others' packets on the bootstrap,
/// +68 MB peak and 11 MB written per deposit, the start reading it twice
/// (S407-BOOTSTRAPSPEICHER). Such a block is converted into rows once, at
/// the next load, and then removed.

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
    final r = _b.sublist(_i, _i + n); // a copy of its own already
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

/// The block format until S407: version 2, records under the 16-B day value
/// (S391, proposal M). An OLDER block is discarded; a NEWER one is a
/// [DepositError]. Read only to convert it into rows.
const int _blockVersion = 2;

/// The version of one row. Another one is a [DepositError]: it would
/// otherwise be overwritten by a build that does not understand it.
const int _rowVersion = 1;

/// Lengths that are fixed in the format. [kIdLength] must match the id length in
/// `post_box_deposit.dart`; [kValueLength] is the day value from
/// `pair.dart`.
const int kIdLength = 8;
const int kValueLength = kCodeLength;

/// The names of the rows begin with this.
const String kPostBoxRowPrefix = '$kRecordPostBox/';

/// The storage of a holder: one row per held packet under
/// [kPostBoxRowPrefix] — in the app rows of the device database (v4_2
/// §4.5.3, `device_records.dart`).
class PostBoxDisk {
  final DeviceRecords _records;

  /// Reads nothing yet.
  PostBoxDisk.on(this._records);

  /// [PostBoxDisk.on] encrypted files `post_box/<id>.enc` in [directory];
  /// [key] is passed through unchanged to [FileEncryption].
  static PostBoxDisk open(Directory directory, Uint8List key) =>
      PostBoxDisk.on(FileDeviceRecords(directory, key));

  /// Removes the whole stock of [records] — rows and an unconverted block.
  static void clear(DeviceRecords records) {
    records.remove(kRecordPostBox);
    records.removePrefix(kPostBoxRowPrefix);
  }

  /// Where the rows lie — for reports and probes.
  String get path => _records.where(kPostBoxRowPrefix);

  static String _name(Uint8List id) => '$kPostBoxRowPrefix${_hex(id)}';

  /// Reads the records back, oldest first, and in doing so removes
  /// everything that was stored BEFORE [limit] — the retention period
  /// applies at LOADING, so a record does not become immortal because the
  /// holder restarts often. A block of the earlier layout is converted into
  /// rows first and then removed.
  ///
  /// No stock is the normal case. A row that cannot be read throws
  /// [DepositError] instead of continuing with half the stock.
  List<DepositRecord> load({required DateTime limit}) {
    _convertBlock(limit);
    final records = <DepositRecord>[];
    final expired = <String>[];
    for (final (name, bytes) in _records.readPrefix(kPostBoxRowPrefix)) {
      if (bytes == null) {
        throw DepositError('${_records.where(name)} exists, but cannot be '
            'read — wrong key or damaged record');
      }
      final r = _rowDecode(bytes);
      if (r.inserted.isBefore(limit)) {
        expired.add(name);
      } else {
        records.add(r);
      }
    }
    expired.forEach(_records.remove);
    records.sort((a, b) => a.inserted.compareTo(b.inserted));
    return records;
  }

  /// Writes the row of [r] — one row, whatever the stock holds.
  void put(DepositRecord r) => _records.write(_name(r.id), _rowEncode(r));

  /// Removes the row of [id].
  void drop(Uint8List id) => _records.remove(_name(id));

  void _convertBlock(DateTime limit) {
    if (!_records.holds(kRecordPostBox)) return;
    final bytes = _records.read(kRecordPostBox);
    if (bytes == null) {
      throw DepositError('${_records.where(kRecordPostBox)} exists, but '
          'cannot be read — wrong key or damaged record');
    }
    // Rows first, the block last: a crash in between converts again and
    // writes the same rows under the same names.
    _blockDecode(bytes, limit).forEach(put);
    _records.remove(kRecordPostBox);
  }

  static Uint8List _rowEncode(DepositRecord s) {
    if (s.id.length != kIdLength) {
      throw ArgumentError('id must be $kIdLength B, was ${s.id.length}');
    }
    if (s.value.length != kValueLength) {
      throw ArgumentError('Value must be $kValueLength B, was ${s.value.length}');
    }
    const head = 1 + kIdLength + kValueLength + 8;
    final out = Uint8List(head + s.content.length);
    out[0] = _rowVersion;
    out.setAll(1, s.id);
    out.setAll(1 + kIdLength, s.value);
    ByteData.sublistView(out).setUint64(
        1 + kIdLength + kValueLength, s.inserted.millisecondsSinceEpoch, Endian.big);
    out.setAll(head, s.content);
    return out;
  }

  static DepositRecord _rowDecode(Uint8List bytes) {
    try {
      final l = _Reader(bytes);
      final version = l.byte();
      if (version != _rowVersion) throw DepositError('unknown row version $version');
      final id = l.bytes(kIdLength);
      final value = l.bytes(kValueLength);
      final inserted = DateTime.fromMillisecondsSinceEpoch(l.u64());
      final content = l.bytes(bytes.length - (1 + kIdLength + kValueLength + 8));
      l.done();
      return (id: id, value: value, content: content, inserted: inserted);
    } on DepositError {
      rethrow;
    } catch (e) {
      throw DepositError('Row damaged: $e');
    }
  }

  List<DepositRecord> _blockDecode(Uint8List bytes, DateTime limit) {
    try {
      final l = _Reader(bytes);
      final version = l.byte();
      if (version < _blockVersion) return const <DepositRecord>[];
      if (version != _blockVersion) {
        throw DepositError('unknown version $version');
      }
      final count = l.u32();
      final records = <DepositRecord>[];
      for (var i = 0; i < count; i++) {
        final id = l.bytes(kIdLength);
        final value = l.bytes(kValueLength);
        final inserted = DateTime.fromMillisecondsSinceEpoch(l.u64());
        final content = l.bytes(l.u32());
        // The deadline applies AFTER the complete reading of the record:
        // the pointer must still stand exactly behind it.
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
}

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
