// AP-1c path (b), addendum (docs/MIGRATION_V3_TO_V4_0_MYZEL.md §4c.2i) — CLASS B.
//
// Recovery of identities: the search for the own identities and the
// restore index probing. Both remain the service's task — V4 §3.5.1
// explicitly continues the probing (3-M-12) —, only the carrier changes:
// instead of the DHT registry the field supplies the records. AP-3 does
// NOT delete this file.
//
// Until 2026-08-14 they lay in `cleona_service_v3_delivery.dart`, whose
// header said "dropped in V4 without replacement" (§4c.2i).

part of 'cleona_service.dart';

extension V3IdentityRecoveryOps on CleonaService {

  /// §6.4.3: Recover multi-identity list from DHT after seed-phrase restore.
  /// Polls DHT for the erasure-coded registry, then creates identities for
  /// each active HD index that doesn't already exist locally.
  /// Returns the list of newly created identities (empty if none found or
  /// all already existed). The caller (daemon or in-process) is responsible
  /// for starting services for the returned identities.
  Future<List<Identity>> recoverIdentitiesFromRegistry() async {
    final masterSeed = identity.masterSeed;
    if (masterSeed == null) {
      _log.debug('Registry recovery skipped: no master seed');
      return [];
    }

    final result = await pollRegistryFromDht(masterSeed);

    if (result == null) {
      // §6.4.3 step 5: no registry found — fall back to AuthManifest probing
      // to detect pre-fix off-by-one (ID-01).
      return _probeRestoreIndex(masterSeed);
    }

    final mgr = IdentityManager();
    final existing = mgr.loadIdentities();
    final existingIndices = existing
        .where((i) => i.hdIndex != null)
        .map((i) => i.hdIndex!)
        .toSet();

    final created = <Identity>[];
    for (final entry in result.identities) {
      final idx = entry['index'] as int;
      if (existingIndices.contains(idx)) continue;
      final name = entry['name'] as String? ?? 'Identity ${idx + 1}';
      try {
        // §7.1.3 (P2): every identity recovered in this run describes the
        // same physical device the user just answered the restore question
        // for — forward the same "additional device vs. lost device" choice
        // so a secondary identity doesn't race its own original device for
        // the auth-key slot while the primary identity correctly waits.
        // §13 (S382): `restoredFromPhrase` travels along, for the same
        // reason as `restoreAwaitingPairing` one line below — every identity
        // recovered in this run describes THE SAME device and the same
        // process. Without passing it on, the second identity of a real
        // recovery case would have no marker and would never get its data.
        final id = await mgr.createIdentityAtIndex(idx, name,
            restoreAwaitingPairing: identity.restoreAwaitingPairing,
            restoredFromPhrase: identity.restoredFromPhrase);
        created.add(id);
        _log.info('Registry recovery: created identity "$name" at hdIndex=$idx');
      } catch (e) {
        _log.warn('Registry recovery: failed to create identity at hdIndex=$idx: $e');
      }
    }

    if (created.isNotEmpty) {
      _log.info('Registry recovery: ${created.length} identities restored from DHT');
    }
    return created;
  }

  /// §6.4.3 restore index probing (ID-01) — FALLEN (CUT, 31.08.2026).
  ///
  /// The body asked the 2D DHT for an AuthManifest under the UserID of HD
  /// index 1 (`node.identityResolver.resolve`), in order to detect the old
  /// off-by-one: users who had created their first identity before the
  /// `_maxHdIndex` fix have it on index 1 instead of 0.
  ///
  /// §4.3 is replaced in V4.1; there is no place where a stranger could
  /// look up whether someone exists under a UserID — that is not missing
  /// wiring, but a design decision (no pollable third-party knowledge).
  ///
  /// **Gap G-19**, small and named: a recovery no longer finds such an old
  /// identity by itself. It creates the primary identity on index 0
  /// instead. Only profiles from the time before the fix are affected, and
  /// the user can create the second identity by hand.
  ///
  /// The place returns `[]` — the same as the formerly most frequent
  /// outcome ("no AuthManifest on index 1") —, but reports the reason in
  /// the log, so that the empty return value is not read as a measurement
  /// result.
  Future<List<Identity>> _probeRestoreIndex(Uint8List masterSeed) async {
    final mgr = IdentityManager();
    final existing = mgr.loadIdentities();
    if (existing.length != 1 || existing.first.hdIndex != 0) return [];
    _log.warn('Restore index probing: not feasible — V4.1 has no '
        'AuthManifest that could be queried for a foreign UserID '
        '(gap G-19). An identity at HD index 1 from the '
        'time before the _maxHdIndex fix stays undiscovered.');
    return [];
  }
}