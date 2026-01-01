/// The setting of the local CalDAV server (v4_2 §18.2): whether it runs,
/// on which port, and the token a calendar program must present.
///
/// ── WHOSE IT IS ─────────────────────────────────────────────────────────
///
/// The DEVICE's, not an identity's: the daemon starts ONE listener on
/// `127.0.0.1` and registers every identity's calendar on it
/// (`service_daemon.dart`, `_startLocalCalDAVServer`). One port and one
/// token serve all of them, so the setting cannot go into the store of one
/// identity (it would fall with that identity).
///
/// ── WHERE IT LIES (S403) ────────────────────────────────────────────────
///
/// In the device database (`device.db`, v4_2 §4.5.3 form 2, §21.4.1): one
/// row of the area `DeviceStore.areaSettings`, under the device-wide key —
/// the same key as the host (`hostKey`, `mycelium_seam.dart`), no second
/// one. The token is a password: whoever reads it reads every identity's
/// calendar through the loopback listener.
///
/// ── WHAT LAY THERE BEFORE, AND WHAT BECOMES OF IT ──────────────────────
///
/// Until S401 the daemon wrote a NAKED `caldav_server.json`; from S401 to
/// S403 the sealed file `caldav_server.json.enc`, and its reader sealed
/// what a naked file held. Neither is read any more: this line takes over
/// no earlier stock (CLAUDE.md "Linien"), and the start removes every form
/// of the name (`superseded_device_files.dart`) — the naked one included,
/// so that no start leaves the token readable. A device on which the
/// server was switched on with an earlier build finds it switched off, and
/// a calendar program that was given the old token must be given the new
/// one.
///
/// This file is the ONE reader and the ONE writer of the setting; the
/// daemon holds the loaded value and calls back here on every change.
library;

import 'dart:typed_data';

import 'package:cleona/core/storage/device_store.dart';

/// The key of the row in `DeviceStore.areaSettings`.
const String kCalDavServerSettingKey = 'caldav_server';

/// What the daemon keeps about its local CalDAV server.
class CalDavServerSetting {
  bool enabled;
  int port;
  String token;

  CalDavServerSetting({
    required this.enabled,
    required this.port,
    required this.token,
  });

  Map<String, dynamic> toJson() =>
      {'enabled': enabled, 'port': port, 'token': token};

  static CalDavServerSetting fromJson(
          Map<String, dynamic> json, int defaultPort) =>
      CalDavServerSetting(
        enabled: json['enabled'] as bool? ?? false,
        port: json['port'] as int? ?? defaultPort,
        token: json['token'] as String? ?? '',
      );
}

/// Reads the setting from the device database of [baseDir]. No database or
/// no row yields the default: off, [defaultPort], no token. [key] is
/// `hostKey(baseDir, masterSeed)`. [warn] receives what went wrong, if
/// anything did. The reader does not create the database.
///
/// A device database that is present but cannot be opened yields the
/// default as well; nothing is written here.
CalDavServerSetting calDavServerSettingLoad(
  String baseDir,
  Uint8List key, {
  required int defaultPort,
  void Function(String message)? warn,
}) {
  try {
    final row = DeviceStore.atIfPresent(baseDir, key)
        ?.entry(DeviceStore.areaSettings, kCalDavServerSettingKey);
    if (row != null) return CalDavServerSetting.fromJson(row, defaultPort);
  } catch (e) {
    warn?.call('The setting of the local CalDAV server could not be read '
        'from the device database of $baseDir ($e) — the server starts from '
        'its default (off, no token)');
  }
  return CalDavServerSetting(enabled: false, port: defaultPort, token: '');
}

/// Writes the setting. Only a user action calls it (switch, port, new
/// token) — and the start, when an enabled server has no token yet.
void calDavServerSettingStore(
    String baseDir, Uint8List key, CalDavServerSetting setting) {
  DeviceStore.at(baseDir, key).putEntry(
      DeviceStore.areaSettings, kCalDavServerSettingKey, setting.toJson());
}
