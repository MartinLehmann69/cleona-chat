/// The setting "port mapping" (task D, point 5, W9).
///
/// Default ON: as long as nobody explicitly switches it off, the node asks
/// its router (V4.2 §7.3). This file only PROVIDES the setting: it reads it
/// for `portMappingToEdge` (`mycelium_seam.dart`), and [portMappingConfigure]
/// writes it for the settings tile (`portMappingSet`, §12.7).
///
/// ── WHY DEVICE-WIDE, NOT PER IDENTITY ───────────────────────────────
///
/// The router it asks belongs to the DEVICE (one host, one port, V4.2
/// §4.5.1) — like `HostMemory` on the mycelium side.
///
/// ── WHERE IT LIES (S403) ────────────────────────────────────────────
///
/// In the device database (`device.db`, v4_2 §4.5.3 form 2, §21.4.1): one
/// row of the area `DeviceStore.areaSettings`. Until S403 it was the file
/// `<baseDir>/port_mapping.enc`; nothing reads that file any more, and the
/// start removes it (`superseded_device_files.dart`). The key the callers
/// hand in is unchanged — `hostKey(baseDir, masterSeed)`, which IS the key
/// of the device database.
library;

import 'dart:typed_data';

import 'package:cleona/core/storage/device_store.dart';

/// The key of the row in `DeviceStore.areaSettings`.
const String kPortMappingSettingKey = 'port_mapping';
const String _field = 'active';

/// Reads the setting. No device database, no row, or a database that does
/// not open (no error case a router cares about): the default applies —
/// ON. [key] is the same as `hostKey(baseDir, masterSeed)` — no second key.
/// The reader does not create the database.
bool portMappingConfigured(String baseDir, Uint8List key) {
  try {
    final row = DeviceStore.atIfPresent(baseDir, key)
        ?.entry(DeviceStore.areaSettings, kPortMappingSettingKey);
    if (row == null) return true;
    return row[_field] as bool? ?? true;
  } on Object {
    return true;
  }
}

/// Writes the setting. Only a user action calls it — since S398-W4 through
/// `portMappingSet` (`mycelium_seam.dart`), from the settings tile (§12.7).
void portMappingConfigure(String baseDir, Uint8List key, bool to) {
  DeviceStore.at(baseDir, key).putEntry(
      DeviceStore.areaSettings, kPortMappingSettingKey, {_field: to});
}
