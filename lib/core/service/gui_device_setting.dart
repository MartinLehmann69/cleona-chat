/// The GUI's device-wide choices: appearance (light/dark/system), language,
/// and until when the donation banner stays dismissed (S407, owner
/// 08.10.2026: configuration lives in the databases, not in files).
///
/// ── WHERE IT LIES ────────────────────────────────────────────────────────
///
/// In the device database (`device.db`, v4_2 §4.5.2 "device-wide settings",
/// §4.5.3 form 2): one row of the area `DeviceStore.areaSettings`. Until S407
/// these three values lay in the platform's `SharedPreferences` file; the GUI
/// start removes those keys (`legacyGuiPrefsSweep` in `lib/main.dart`) and
/// nothing reads them any more.
///
/// ── BEFORE THERE IS A DEVICE DATABASE ────────────────────────────────────
///
/// The device database needs the master seed (§4.5.2); during the first setup
/// there is none yet. A choice made then stays in the GUI's memory and is
/// written here as soon as a service can store it (`CleonaAppState`); until a
/// stored value is read, the GUI starts in the system's language and theme.
library;

import 'package:cleona/core/storage/device_store.dart';

/// The key of the row in `DeviceStore.areaSettings`.
const String kGuiDeviceSettingKey = 'gui';

/// Field: `ThemeMode.index` (0 system, 1 light, 2 dark).
const String kGuiFieldTheme = 'theme';

/// Field: the language code (`AppLocale.supportedLocales`).
const String kGuiFieldLocale = 'locale';

/// Field: milliseconds since the epoch until which the donation banner stays
/// hidden; absent = shown.
const String kGuiFieldDonationBannerUntil = 'donationBannerUntil';

/// The fields a writer may set — anything else is refused, so the row never
/// becomes a general-purpose store.
const Set<String> kGuiFields = {
  kGuiFieldTheme,
  kGuiFieldLocale,
  kGuiFieldDonationBannerUntil,
};

/// Reads the row; an absent database or row gives an empty map.
Map<String, dynamic> guiDeviceSettingsRead(DeviceStore? store) {
  try {
    final row = store?.entry(DeviceStore.areaSettings, kGuiDeviceSettingKey);
    return row == null ? <String, dynamic>{} : Map<String, dynamic>.from(row);
  } on Object {
    return <String, dynamic>{};
  }
}

/// Sets one field ([value] `null` removes it). Returns false when [field] is
/// not one of [kGuiFields] or there is no database to write to.
bool guiDeviceSettingWrite(DeviceStore? store, String field, Object? value) {
  if (store == null || !kGuiFields.contains(field)) return false;
  final row = guiDeviceSettingsRead(store);
  if (value == null) {
    row.remove(field);
  } else {
    row[field] = value;
  }
  store.putEntry(DeviceStore.areaSettings, kGuiDeviceSettingKey, row);
  return true;
}
