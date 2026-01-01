/// Runs [action] for every entry of [map], one after the other, awaiting each
/// — over a copy taken when the walk begins, skipping an entry that left the
/// map (or was replaced) while an earlier [action] was awaited.
///
/// WHY (S411, 03.11.2026): `_MultiServiceDaemon._updateManifestAsk` walked
/// `_services.values` directly and awaited inside the loop. A second identity
/// created at runtime (`addIdentity`) entered `_services` during that await;
/// the next step threw "Concurrent modification during iteration", the zone
/// handler judged it not survivable and ended the daemon with exit 99
/// (Windows VM, E2E gui-00c 0c.06, `mycelium/berichte/S411-E2E-ABBRUCH-2.md`).
///
/// An entry added during the walk is not visited in THIS walk; the next one
/// sees it. An entry removed during the walk is not visited any more — its
/// service is stopped and must not be asked.
Future<void> forEachStillPresent<K, V>(
    Map<K, V> map, Future<void> Function(V value) action) async {
  for (final entry in List.of(map.entries)) {
    if (!identical(map[entry.key], entry.value)) continue;
    await action(entry.value);
  }
}
