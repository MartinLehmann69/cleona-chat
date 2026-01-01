/// The setting "fewer empty cover packets on W/LAN" (V4.2 §12.7, §5.1,
/// D-7; S398-W4).
///
/// Default OFF (§12.7). On: on UNMETERED W/LAN the cover stream carries
/// only content — update pieces and address entries keep flowing, the empty
/// filling is skipped (`CoverStream.emptyReduce`, `mycelium/lib/
/// cover_stream.dart`). On metered mobile data the switch never applies
/// (`CoverStream.reduced`); there the rate is lowered instead (§5.3).
///
/// ── WHY HERE AND NOT IN THE HOST'S MEMORY ─────────────────────────────
///
/// The same reasoning and the same place as `port_mapping_setting.dart`: a
/// DEVICE value (one host, one cover stream, §4.5.1). The host's own
/// memory (`host_memory.dart`) has a fixed binary layout that this package
/// does not change.
///
/// ── WHERE IT LIES (S403) ──────────────────────────────────────────────
///
/// In the device database (`device.db`, v4_2 §4.5.3 form 2, §21.4.1): one
/// row of the area `DeviceStore.areaSettings`. Until S403 it was the file
/// `<baseDir>/cover_reduce.enc`; nothing reads that file any more, and the
/// start removes it (`superseded_device_files.dart`).
///
/// ── WHAT IT REPLACES ─────────────────────────────────────────────────
///
/// The S373 consent PER SEGMENT of the replaced V4.1 layer
/// (`v41Delivery.grantLanShaping`). Its only writer was `attachV41`, which
/// has no caller: the settings tile always said "no own network", the
/// grant always failed, and the 4.2 cover stream never saw the wish
/// (report `S398-LUECKEN-GUI.md`, B7). §12.7 asks for a plain switch.
library;

import 'dart:typed_data';

import 'package:cleona/core/storage/device_store.dart';

/// The key of the row in `DeviceStore.areaSettings`.
const String kCoverReduceSettingKey = 'cover_reduce';
const String _field = 'on';

/// Reads the setting. No device database, no row, or a database that does
/// not open: the default applies — OFF (§12.7). Concealment is never given
/// up by accident. The reader does not create the database.
bool coverReduceConfigured(String baseDir, Uint8List key) {
  try {
    final row = DeviceStore.atIfPresent(baseDir, key)
        ?.entry(DeviceStore.areaSettings, kCoverReduceSettingKey);
    if (row == null) return false;
    return row[_field] as bool? ?? false;
  } on Object {
    return false;
  }
}

/// Writes the setting. Only a user action calls it.
void coverReduceConfigure(String baseDir, Uint8List key, bool to) {
  DeviceStore.at(baseDir, key).putEntry(
      DeviceStore.areaSettings, kCoverReduceSettingKey, {_field: to});
}
