// The node's own state in the device database (S403 step 3; v4_2 §4.5.2,
// §4.5.3 form 2, D-51; owner decision G-1 = A).
//
// The delivery layer writes three records of the device — the host's
// memory, its post box, the key of its address record — through the
// interface `DeviceRecords` (`mycelium/lib/device_records.dart`), and leaves
// it to whoever starts the host where they lie. The app puts them here: the
// area `node` of the device database, one row per record, the bytes as
// base64 (the same carriage as the history of the delivery layer in the
// identity's store, `mycelium_history_store.dart`; the compression of the
// state table takes back what it can).
//
// ── WHY THE HANDLE IS ASKED FOR AT EVERY CALL ──────────────────────────
//
// `DeviceStore.at` hands out the handle this process holds and drops one
// whose file went away (`device_store.dart`, "A FILE THAT WENT AWAY UNDER AN
// OPEN HANDLE"); the daemon's watchdog may create the database anew. A
// handle kept here would write into a file no path leads to any more.
// Asking costs a map lookup and one `existsSync`.
//
// ── WHAT "CANNOT BE READ" MEANS HERE ───────────────────────────────────
//
// The database is encrypted page by page; a row that is there opens with
// the database or not at all (then `DeviceStore.at` throws, and the host
// does not start — the same as an unreadable file before). A row whose
// value is not base64 is named as unreadable ([read] → `null`, [holds] →
// `true`); what that means is each store's decision, as with files.

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/storage/device_store.dart';
import 'package:mycelium/device_records.dart';

class MyceliumDeviceRecords implements DeviceRecords {
  /// The profile directory and the key of its device database —
  /// `hostKey(baseDir, masterSeed)`, which is
  /// `HdWallet.deriveSharedFileEncKey(masterSeed)` (§4.5.3).
  final String baseDir;
  final Uint8List _key;

  MyceliumDeviceRecords(this.baseDir, Uint8List key)
      : _key = Uint8List.fromList(key);

  DeviceStore get _store => DeviceStore.at(baseDir, _key);

  static const String _field = 'b';

  @override
  bool holds(String name) =>
      _store.entry(DeviceStore.areaNode, name) != null;

  @override
  Uint8List? read(String name) {
    final row = _store.entry(DeviceStore.areaNode, name);
    final text = row?[_field];
    if (text is! String) return null;
    try {
      return base64Decode(text);
    } on FormatException {
      return null;
    }
  }

  /// ONE row, replaced in one statement — the old bytes or the new ones.
  @override
  void write(String name, Uint8List bytes) => _store.putEntry(
      DeviceStore.areaNode, name, {_field: base64Encode(bytes)});

  @override
  void remove(String name) => _store.removeEntry(DeviceStore.areaNode, name);

  @override
  String where(String name) =>
      '${DeviceStore.pathIn(baseDir)} (${DeviceStore.areaNode}/$name)';
}
