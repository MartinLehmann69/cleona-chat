/// The one-time warning for the file variant of the keyring (V18).
///
/// Owner decision V18 (02.10.2026): where the system has a keyring, the
/// keyring is binding. Where it has none — or logs in automatically, so
/// the keyring stays LOCKED — the master seed and the 24 words lie in the
/// file-variant containers (`.master_seed.keyring`, `.seed_phrase.keyring`,
/// sealed under the per-installation `.keyring_salt`), and that is a WEAKER
/// state: whoever can read the disk can open them. The app therefore shows
/// the warning exactly ONCE at the start on the file variant, naming the
/// attack and the remedy (set up a keyring, or disable automatic login).
///
/// ── WHY A SHOWN-ONCE FLAG AND NOT EVERY START ─────────────────────────
///
/// The state is a property of the MACHINE, not of a message: it changes
/// only when the system changes. Showing it on every start would train the
/// click away; showing it never would hide a real, named risk. "Once" is
/// the owner's wording, and this file is only its memory.
///
/// ── WHERE IT LIES ─────────────────────────────────────────────────────
///
/// In the device database (`device.db`, v4_2 §4.5.3 form 2, §21.4.1): one
/// row of the area `DeviceStore.areaSettings`, the same place as the port
/// mapping setting (`port_mapping_setting.dart`). It is device-wide, not
/// per identity: the keyring decision is made before any identity is
/// loaded, and the warning would otherwise re-appear once per identity.
///
/// [key] is the device database key — `HdWallet.deriveSharedFileEncKey(
/// masterSeed)`, no second key (see `hostKey`, `mycelium_seam.dart`). The
/// reader does not create the database; a machine that never acknowledged
/// has no row and gets the default.
library;

import 'dart:typed_data';

import 'package:cleona/core/storage/device_store.dart';

/// The key of the row in `DeviceStore.areaSettings`.
const String kKeyringFileWarningShownKey = 'keyring_file_warning_shown';
const String _field = 'shown';

/// Whether the warning has already been acknowledged. No device database,
/// no row, or a database that does not open: `false` — the default is
/// "not shown yet", never "shown" (fail open on the warning side means the
/// user sees it again, not never).
bool keyringFileWarningShown(String baseDir, Uint8List key) {
  try {
    final row = DeviceStore.atIfPresent(baseDir, key)
        ?.entry(DeviceStore.areaSettings, kKeyringFileWarningShownKey);
    if (row == null) return false;
    return row[_field] as bool? ?? false;
  } on Object {
    return false;
  }
}

/// Marks the warning as acknowledged — called by the acknowledge button of
/// the warning screen, and by nothing else.
void markKeyringFileWarningShown(String baseDir, Uint8List key) {
  DeviceStore.at(baseDir, key).putEntry(
      DeviceStore.areaSettings, kKeyringFileWarningShownKey, {_field: true});
}