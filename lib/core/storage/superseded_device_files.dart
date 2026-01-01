// Enforcer (S403): the device-wide files the device database superseded.
//
// Until S403 the state of the device lay in files of its own in the
// profile directory, each sealed with `FileEncryption` under the
// device-wide key. That state lies in the device database now
// (`device_store.dart`, v4_2 §4.5.3 form 2, §21.4.1). A profile an earlier
// build of this line created still carries the files.
//
// ── THEY ARE REMOVED, NOT TAKEN OVER ───────────────────────────────────
//
// This line has no conversion of earlier stock and no old profiles
// (CLAUDE.md "Linien"; `scripts/check-no-v3-touch.sh`). Nothing below reads
// a file: neither its content nor the key it lies under is of interest.
// What the removal means for a device that ran the released build — it
// then has no list of identities and no device keys — is a question the
// owner decides, named in
// `mycelium/berichte/S403-GERAETE-DATENBANK-SCHRITT-1.md`.
//
// ── WHY THEY MUST GO AT ALL ────────────────────────────────────────────
//
// A file nothing reads and nothing writes is the file nobody comes past
// again. These carry the display name next to the network identifier, the
// device's secret keys and the token of the calendar listener; left lying,
// they would keep that content on disk for as long as the profile exists —
// under a key that opens them. The statement of this function is "under
// these names nothing lies in this profile", and it has no other keeper.
//
// The run is cheap and repeats at every start (`IdentityContext
// .initCrypto`): if nothing lies there, it costs four `existsSync` per
// name. It is bound to no marker — a marker would skip the run that could
// not delete last time.

import 'package:cleona/core/crypto/plaintext_sweep.dart';
import 'package:cleona/core/log/clogger.dart';

/// The names, relative to the profile directory and without `.enc`, as the
/// writers of the earlier build named them. Every form of each goes
/// (`PlaintextSweep.forms`): the name itself, the sealed file and the two
/// side pieces of an interrupted write.
const List<String> kSupersededDeviceFiles = <String>[
  // The list of identities and the identity shown last — now the areas
  // `identities` and `device` of the device database.
  'identities.json',
  'last_profile.json',
  // The device keys — now the area `device_keys`. A device that carried
  // this file gets NEW device keys at its next start; the old ones are not
  // read.
  'device_keys.bin',
  // Three device-wide settings — now rows of the area `settings`. A
  // setting made with an earlier build is back at its default.
  // `caldav_server.json` also lay UNENCRYPTED in the profile wherever the
  // released build had the local calendar server switched on; the name
  // itself is the first of the forms that go.
  'port_mapping',
  'cover_reduce',
  'caldav_server.json',
  // The node's own state (S403 step 3) — now rows of the area `node`
  // (`DeviceStore.areaNode`): the host's memory, the post box, the key of
  // the own address record. A device that carried them draws a new fixed
  // port at its next start (§11.1: cards handed out before point to the
  // old one), forgets its remembered neighbours and what it held for
  // others, and publishes its address record under a new key.
  'mycelium/host',
  'mycelium/post_box',
  'mycelium/outside',
];

/// Removes every form of every name in [kSupersededDeviceFiles] from
/// [baseDir]. Returns the base names of the files actually removed.
List<String> removeSupersededDeviceFiles(String baseDir, {CLogger? log}) {
  final removed = <String>[];
  for (final name in kSupersededDeviceFiles) {
    // With [log]: a form that cannot be deleted is reported there, stays,
    // and is tried again at the next start.
    removed.addAll(PlaintextSweep.removeAllForms('$baseDir/$name', log: log));
  }
  if (removed.isNotEmpty) {
    log?.info('Device files of an earlier build removed: '
        '${removed.join(', ')} — their state lies in the device database, '
        'and they are not read (S403).');
  }
  return removed;
}
