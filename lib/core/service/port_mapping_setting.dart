/// The setting "port mapping" (task D, point 5, W9).
///
/// Default ON: as long as nobody explicitly switches it off, the node asks
/// its router (V4.2 §7.3). There is NO UI for it here —
/// that comes later, then with i18n in all 34 languages (work rule 7).
/// This file only PROVIDES the setting: it reads it for
/// `portMappingToEdge` (`mycelium_seam.dart`), and [portMappingConfigure]
/// stands ready for the later UI — today without a caller in
/// `lib/`.
///
/// ── WHY DEVICE-WIDE, NOT PER IDENTITY ───────────────────────────────
///
/// The router it asks belongs to the DEVICE (one host, one port, V4.2
/// §4.5.1) — like `HostMemory` on the mycelium side. It is therefore
/// stored under [baseDir], with the same key as the host
/// (`hostKey`, `mycelium_seam.dart`): form 2 of persistence (§4.5.3),
/// `FileEncryption`, atomic.
library;

import 'dart:typed_data';

import 'package:cleona/core/crypto/file_encryption.dart';

const String _fileName = 'port_mapping';
const String _field = 'aktiv';

/// Reads the setting from `<baseDir>/portabbildung.enc`. If the
/// file is missing or unreadable (no error case a router
/// cares about): the default applies — ON. [key] is the same as
/// `hostKey(baseDir, masterSeed)` — no second key.
bool portMappingConfigured(String baseDir, Uint8List key) {
  try {
    final enc = FileEncryption(baseDir: baseDir, key: key);
    final json = enc.readJsonFile('$baseDir/$_fileName');
    if (json == null) return true;
    return json[_field] as bool? ?? true;
  } on Object {
    return true;
  }
}

/// Writes the setting. Prepared for the later UI;
/// today without a caller in `lib/`.
void portMappingConfigure(String baseDir, Uint8List key, bool to) {
  FileEncryption(baseDir: baseDir, key: key)
      .writeJsonFile('$baseDir/$_fileName', {_field: to});
}
