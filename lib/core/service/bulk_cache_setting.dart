/// The size of the bulk cache — what this device holds of lane 3 for
/// others (V4.2 §9.4, §21.2, §21.3.1, §21.3.3 item 3; D-32).
///
/// Default desktop 1 GB, phone 100 MB (D-32), "user-overridable in tiers
/// following the §21.6 pattern", "no automatic growth with disk size"
/// (§21.3.3 item 3). The tiers span the range §21.3.1 gives the media
/// budget of §21.6 — 100 MB (mobile) to 2 GB (desktop) — and are the same
/// on every platform; only the default differs. There is no tier 0: every
/// desktop installation keeps a bulk cache (§9.4 "Lane 3, placement").
///
/// ── WHERE IT LIES ────────────────────────────────────────────────────
///
/// A DEVICE value (one host, one bulk cache, §4.5.1), so the same place as
/// `cover_reduce_setting.dart` and `port_mapping_setting.dart`: one row of
/// the area `DeviceStore.areaSettings` in the device database (`device.db`,
/// §4.5.3 form 2). No row — every installation before this setting — means
/// the platform default. A row this build cannot read (a value that is no
/// tier, a field of another type) also means the default: a smaller cache
/// than wished is the safe direction, it holds less for others and never
/// touches own data (§21.1).
library;

import 'dart:typed_data';

import 'package:cleona/core/storage/device_store.dart';

/// The key of the row in `DeviceStore.areaSettings`.
const String kBulkCacheSettingKey = 'bulk_cache';
const String _field = 'mb';

/// The tiers in MB, smallest first.
const List<int> kBulkCacheTiersMb = [100, 250, 500, 1024, 2048];

/// The default of D-32: desktop 1 GB, phone 100 MB.
int bulkCacheDefaultMb({required bool mobile}) => mobile ? 100 : 1024;

/// The user's tier, or `null` when none is stored or the row is not one
/// this build reads (then the default applies). The reader does not create
/// the database.
int? bulkCacheConfiguredMb(String baseDir, Uint8List key) {
  try {
    final row = DeviceStore.atIfPresent(baseDir, key)
        ?.entry(DeviceStore.areaSettings, kBulkCacheSettingKey);
    final mb = row?[_field];
    return mb is int && kBulkCacheTiersMb.contains(mb) ? mb : null;
  } on Object {
    return null;
  }
}

/// Writes the user's tier. Only a user action calls it; a value that is no
/// tier is refused.
void bulkCacheConfigure(String baseDir, Uint8List key, int mb) {
  if (!kBulkCacheTiersMb.contains(mb)) {
    throw ArgumentError.value(mb, 'mb', 'not a bulk-cache tier');
  }
  DeviceStore.at(baseDir, key)
      .putEntry(DeviceStore.areaSettings, kBulkCacheSettingKey, {_field: mb});
}
