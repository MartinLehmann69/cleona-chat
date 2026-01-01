import 'dart:io';

/// The files in which state of the device lay until S407 — now rows of the
/// device database (`device.db`, `DeviceStore.areaDevice`; v4_2 §4.5.2,
/// §4.5.3: "State of the device lives in the device database").
///
/// This file READS and DELETES them and never writes one: it is the only
/// place under lib/ that names them (gate `scripts/check-no-file-config.sh`).
/// Nothing is carried over from them — 4.2 knows no migration — with one
/// exception, the monotone sequence: it is a security bound (§26.5), and a
/// bound that fell back to 0 on the move would let an older manifest in.
/// So its value is read, the device database keeps the higher of the two,
/// and only then is the file removed ([legacyMonotoneSeqRead]).

/// `<dataDir>/update/monotone_seq.txt` — the highest manifest sequence seen.
const String kLegacyMonotoneSeqFile = 'monotone_seq.txt';

/// `<dataDir>/update_in_network.flag` — "an in-network update is available".
const String kLegacyInNetworkFlagFile = 'update_in_network.flag';

/// `<dataDir>/install_source_v2.txt` — the detected install source.
const String kLegacyInstallSourceFile = 'install_source_v2.txt';

/// `<baseDir>/firewall_rule_added` — Windows firewall rules were set.
const String kLegacyFirewallMarkerFile = 'firewall_rule_added';

/// The value of the legacy monotone-sequence file in [updateDir], or `null`
/// when there is none or it is unreadable. Does NOT delete it: the caller
/// deletes it ([legacyDeviceStateDrop]) only after the device database holds
/// a value at least as high.
int? legacyMonotoneSeqRead(String updateDir) {
  try {
    final f = File('$updateDir${Platform.pathSeparator}$kLegacyMonotoneSeqFile');
    if (!f.existsSync()) return null;
    return int.tryParse(f.readAsStringSync().trim());
  } catch (_) {
    return null;
  }
}

/// Whether the legacy file [name] lies in [dir].
bool legacyDeviceStatePresent(String dir, String name) {
  try {
    return File('$dir${Platform.pathSeparator}$name').existsSync();
  } catch (_) {
    return false;
  }
}

/// Removes the legacy file [name] from [dir]; silent when it is not there.
void legacyDeviceStateDrop(String dir, String name) {
  try {
    final f = File('$dir${Platform.pathSeparator}$name');
    if (f.existsSync()) f.deleteSync();
  } catch (_) {}
}
