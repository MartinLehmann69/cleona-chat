/// What a keeper holds survives a restart (V4.2 §16.2.5: "A keeper holds
/// each entry for 7 days"): the whole holding as one record of the device
/// database (`device_records.dart`, encrypted there), written when it
/// changes and read at start — the same way the post box keeps what it holds
/// for others (`post_box_disk.dart`).
///
/// ```
/// count u32 | count × (value 16 | author pk 32 | at ms u64 | length u32 | entry)
/// ```
///
/// Without records (probes) everything stays in memory.
library;

import 'dart:typed_data';

import 'package:mycelium/channel_chain.dart';
import 'package:mycelium/device_records.dart';

const String kRecordChannelKeeper = 'channel_keeper';

/// One held entry.
class KeptEntry {
  final Uint8List value;
  final Uint8List authorPk;
  final Uint8List entry;
  final DateTime at;
  final Uint8List hash;

  KeptEntry({
    required this.value,
    required this.authorPk,
    required this.entry,
    required this.at,
  }) : hash = entryHash(entry);
}

class KeeperDisk {
  final DeviceRecords? records;
  KeeperDisk(this.records);

  List<KeptEntry> load() {
    final b = records?.read(kRecordChannelKeeper);
    if (b == null || b.length < 4) return [];
    final out = <KeptEntry>[];
    try {
      final d = ByteData.sublistView(b);
      final n = d.getUint32(0);
      var i = 4;
      for (var k = 0; k < n; k++) {
        final value = Uint8List.fromList(b.sublist(i, i += kChannelValueLength));
        final author = Uint8List.fromList(b.sublist(i, i += kSignPkLength));
        final at = DateTime.fromMillisecondsSinceEpoch(d.getUint64(i));
        i += 8;
        final len = d.getUint32(i);
        i += 4;
        final entry = Uint8List.fromList(b.sublist(i, i += len));
        out.add(KeptEntry(value: value, authorPk: author, entry: entry, at: at));
      }
    } on Object {
      // A record that does not read is one that holds nothing — the members
      // collect from the other keepers of their list.
      return out;
    }
    return out;
  }

  void save(Iterable<KeptEntry> all) {
    final r = records;
    if (r == null) return;
    final list = all.toList();
    final b = BytesBuilder()..add(_u32(list.length));
    for (final e in list) {
      final at = ByteData(8)..setUint64(0, e.at.millisecondsSinceEpoch);
      b
        ..add(e.value)
        ..add(e.authorPk)
        ..add(at.buffer.asUint8List())
        ..add(_u32(e.entry.length))
        ..add(e.entry);
    }
    r.write(kRecordChannelKeeper, b.toBytes());
  }
}

Uint8List _u32(int v) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, v);
