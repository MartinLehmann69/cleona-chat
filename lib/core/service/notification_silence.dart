/// Quiet hours and the master mute (§22.8 "quiet hours (per identity, plus a
/// master mute)", owner decision 08.10.2026).
///
/// ── WHAT IS SILENCED ──────────────────────────────────────────────────────
///
/// Message notifications: the sound, the vibration and the system
/// notification of an incoming message — the same three things the layers
/// L1–L5 of §22.8 decide about. The message itself, its unread count and
/// every badge stay as they are. Calls and calendar reminders are not
/// messages and are not silenced here: §22.8 names its layers for incoming
/// messages, and it says nothing about calls during quiet hours.
///
/// ── WHERE IT LIES ─────────────────────────────────────────────────────────
///
/// Quiet hours belong to an identity: fields of its `NotificationSettings`
/// in its own database (`messages.db`, area `notification_settings`). The
/// master mute belongs to the device: one row of `DeviceStore.areaSettings`
/// in `device.db` (§4.5.2 "device-wide settings"), the same for every
/// identity of the device.
///
/// ── NO CLOCK ──────────────────────────────────────────────────────────────
///
/// Both are checked at the moment a notification would be given. Nothing
/// runs on a timer, nothing is sent (§5.4).
library;

import 'package:cleona/core/service/notification_sound_service.dart';
import 'package:cleona/core/storage/device_store.dart';

/// The key of the master-mute row in `DeviceStore.areaSettings`.
const String kMasterMuteSettingKey = 'master_mute';

/// Reads the master mute; no database or no row means off.
bool masterMuteRead(DeviceStore? store) {
  try {
    final row = store?.entry(DeviceStore.areaSettings, kMasterMuteSettingKey);
    return row?['on'] == true;
  } on Object {
    return false;
  }
}

/// Stores the master mute. Returns false when there is no database to write
/// to (no master seed yet).
bool masterMuteWrite(DeviceStore? store, bool on) {
  if (store == null) return false;
  store.putEntry(DeviceStore.areaSettings, kMasterMuteSettingKey, {'on': on});
  return true;
}

/// Whether a message notification is silenced at [now] (local time): by the
/// device's master mute or by the identity's quiet hours.
bool notificationSilenced({
  required bool masterMute,
  required NotificationSettings settings,
  required DateTime now,
}) =>
    masterMute || settings.quietAt(now);
