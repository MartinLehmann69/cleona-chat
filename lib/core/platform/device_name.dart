// The name this device carries in the device set, in an enrolment request
// (§14.6.1 step 2: "carrying its name, platform, …") and in the Requests tab
// of the existing device (step 3: "with the new device's name, platform and
// DeviceID").
//
// S398, lab B-4b finding B-3: until S398 the name was `Platform.localHostname`
// everywhere. On Android that is `localhost` (measured in the lab:
// `Local device registered: 55cc457b… (localhost)`, and in S363,
// `docs/v4-redesign/S363-messung-android-hostname.md`), so the user deciding
// in the Requests tab saw "localhost" and could not tell whether he had set
// the device up himself. On Android and iOS the name comes from the platform
// (the app asks it over `chat.cleona/storage`, method `getDeviceName`, and
// hands it in via [PlatformDeviceName.reported] before the first service
// starts); desktops keep the host name.
//
// Pure Dart: the daemon has no Flutter, so this file never calls a channel.

import 'dart:io';

/// What the platform reported about this device, set by the app (main.dart)
/// on Android and iOS before the first service starts. `null` on desktops,
/// in the daemon and in tests that do not set it.
class PlatformDeviceName {
  static ({String? name, String? manufacturer, String? model})? reported;
}

/// Whether [s] names a device. `localhost` (and `localhost.<domain>`) names
/// none: it is what `Platform.localHostname` gives on Android.
bool deviceNameUsable(String? s) {
  if (s == null) return false;
  final t = s.trim();
  if (t.isEmpty) return false;
  final l = t.toLowerCase();
  return l != 'localhost' && !l.startsWith('localhost.');
}

/// The platform as a name — the last fallback, never empty.
String devicePlatformLabel(String platform) => switch (platform) {
      'android' => 'Android',
      'ios' => 'iOS',
      'linux' => 'Linux',
      'windows' => 'Windows',
      'macos' => 'macOS',
      _ => 'Device',
    };

/// Chooses this device's name — a pure function, so that "localhost" can be
/// ruled out by a test.
///
/// * Android / iOS: the name the platform reports ([name]: Android
///   `Settings.Global.DEVICE_NAME`, iOS `UIDevice.current.name`), else
///   manufacturer + model ("Google Pixel 6"; a model that already starts with
///   the manufacturer is not doubled), else the platform label. The host
///   name is never used there.
/// * Desktop: the host name, else the platform label.
///
/// Never returns an empty string and never `localhost`.
String deviceNameChoose({
  required String platform,
  required String hostname,
  String? name,
  String? manufacturer,
  String? model,
}) {
  final mobile = platform == 'android' || platform == 'ios';
  if (!mobile) {
    return deviceNameUsable(hostname)
        ? hostname.trim()
        : devicePlatformLabel(platform);
  }
  if (deviceNameUsable(name)) return name!.trim();
  final m = deviceNameUsable(model) ? model!.trim() : null;
  final f = deviceNameUsable(manufacturer) ? manufacturer!.trim() : null;
  if (m != null) {
    if (f == null || m.toLowerCase().startsWith(f.toLowerCase())) return m;
    return '${_capitalised(f)} $m';
  }
  if (f != null) return _capitalised(f);
  return devicePlatformLabel(platform);
}

String _capitalised(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// This device's name now: [deviceNameChoose] with the host name and what
/// the platform reported.
String localDeviceName(String platform) {
  final r = PlatformDeviceName.reported;
  String host;
  try {
    host = Platform.localHostname;
  } on Object {
    host = '';
  }
  return deviceNameChoose(
    platform: platform,
    hostname: host,
    name: r?.name,
    manufacturer: r?.manufacturer,
    model: r?.model,
  );
}
