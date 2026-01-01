// E-9 — The deletion of an identity reaches the OWN devices.
//
// ── THE FINDING, MEASURED ────────────────────────────────────────────────
//
// `broadcastIdentityDeleted` (`cleona_service.dart`) iterated
// `_contacts.values` and touched `_devices` with not a single line. The
// `TwinSyncType` enum in `proto/app_payloads.proto` listed 14 types
// (0..13) and NONE for an identity deletion. A linked device kept
// contacts, keys and history indefinitely and never learned that a
// deletion had happened.
//
// ── WHY THIS IS NOT §21.5.2/B-9 ─────────────────────────────────────
//
// §21.5.2 honestly explains that deletion on the delivery layer is
// local: "The original cell stays put until its TTL clears it." What stays
// there is CIPHERTEXT at a foreign relay — without a key. On the second
// phone of the same user lies PLAINTEXT, because this device has the key.
// The difference is the whole point.
//
// ── WHAT THE DELETION ACHIEVES HERE AND WHAT NOT ───────────────────────
//
// ACHIEVED: every own device that harvests within the delivery deadline
// (§21.8: 14 days default TTL). It then clears away its copy — contacts,
// conversations, groups, channels, device list, outbox, and the encrypted
// stores in the profile directory including `keys.json.enc`.
//
// NOT ACHIEVED: a device that stays off longer than the deadline. The cell
// expires, the device never finds it and keeps its copy. That is
// DECLARED, not hidden (the same honesty rule as §21.5.2 for the relay
// ciphertext) — the i18n key for it is in the report of this session.
part of 'cleona_service.dart';

/// Byte equality, fail-closed on emptiness or length difference.
bool _sameBytes(List<int> a, List<int> b) {
  if (a.isEmpty || b.isEmpty || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

extension IdentityDeletionOps on CleonaService {
  /// Accepts the message "this identity has been deleted" from an OWN
  /// device and clears up locally.
  ///
  /// FAILS CLOSED. A wrongly accepted frame deletes irretrievably;
  /// therefore deletion only happens if the message demonstrably means
  /// THIS identity. It is checked against the CURRENT and against the
  /// FOUNDING Ed25519 — both, because a rotation (§14.4) changes the
  /// current key, while the founding key survives every rotation (§4.1).
  /// A device that has not seen a rotation yet would otherwise discard
  /// exactly the deletion that concerns it.
  ///
  /// THE FRAME ITSELF IS ALREADY AUTHENTICATED: `_handleTwinSyncV3` only
  /// gets what the receive chain has checked against the user key of this
  /// identity (or that of an authorised delegate), and the dedup lock on
  /// `sync_id` keeps repetitions out. The check here is the second door,
  /// not the first.
  void _handleTwinIdentityDeleted(List<int> payload) {
    proto.IdentityDeletedNotification report;
    try {
      report = proto.IdentityDeletedNotification.fromBuffer(
          Uint8List.fromList(payload));
    } catch (e) {
      _log.error('TWIN_IDENTITY_DELETED: body not readable: $e');
      return;
    }

    final meant = report.identityEd25519Pk;
    final fits = _sameBytes(meant, identity.ed25519PublicKey) ||
        _sameBytes(meant, identity.foundingEd25519Pk);
    if (!fits) {
      _log.warn('TWIN_IDENTITY_DELETED names a DIFFERENT identity '
          '(${CleonaService._hexShort(Uint8List.fromList(meant))}) than the '
          'own one (${CleonaService._hexShort(identity.ed25519PublicKey)}) — '
          'not deleted');
      return;
    }

    _log.warn('TWIN_IDENTITY_DELETED: this identity was deleted on another '
        'own device — local copy is being cleared away');
    _wipeLocalIdentityData();
    onIdentityDeletedRemotely?.call(identity.userIdHex);
  }

  /// Clears away everything THIS service holds of the identity.
  ///
  /// TWO STEPS, AND BOTH ARE NECESSARY.
  ///
  /// 1. The collections in memory are cleared AND saved. Without saving,
  ///    the next arbitrary writer (an arriving frame, the 2-second batcher
  ///    of `_saveConversations`) would put the old state from memory back
  ///    on disk and undo the deletion.
  /// 2. The encrypted stores in the profile directory are removed.
  ///    A container written EMPTY is not a deletion — it is an empty
  ///    container. Affected are the STORE (`messages.db` including
  ///    `-wal`/`-shm`) and all `*.json.enc` of this profile, explicitly
  ///    including the key material: without it even a later restored
  ///    image opens nothing any more.
  ///
  /// ── THE STORE WAS MISSING HERE, MEASURED (S377) ────────────────────────
  ///
  /// Until S377 step 2 cleared ONLY `*.json.enc`. Until S366 that was
  /// complete; since then keys, contacts, conversations, groups, channels
  /// and devices live in `messages.db`
  /// (`identity_context.dart:605` — `MessageStore.open` on
  /// `<profileDir>/messages.db`, written via `store.replaceArea(...)` in
  /// `cleona_service.dart:7542` / `:8011`). A field profile therefore
  /// carries ZERO `*.json.enc` — the loop ran into nothing.
  ///
  /// Re-measured on 09.09.2026 on a profile WITH master seed
  /// (i.e. as the field has it), after exactly this message:
  ///
  ///     "[WARN] TWIN_IDENTITY_DELETED: diese Identitaet wurde auf einem
  ///            anderen eigenen Geraet geloescht — lokale Kopie wird
  ///            abgeraeumt"
  ///     [WARN] REFUSED to save empty contacts — load failed but the
  ///            store still holds entries. Would cause data loss!
  ///     "[WARN] TWIN_IDENTITY_DELETED: 0 verschluesselte Ablagen
  ///            entfernt, Speicher geleert"
  ///
  ///     area "keys":     1 row  BEFORE -> 1 row  AFTER
  ///     area "contacts": 1 row  BEFORE -> 1 row  AFTER
  ///     files: messages.db, messages.db-wal, messages.db-shm — all three
  ///
  /// The key material survived the deletion completely, and so did the
  /// contacts: step 1 cannot clear them, because the data-loss latch in
  /// `_saveContacts` (`cleona_service.dart:7518-7530`) strikes —
  /// `_contactsLoaded` is `false` on a service that has only received
  /// frames, the set in memory is empty, and the store still carries rows.
  /// The latch is RIGHT (it protects against accidental empty writing) —
  /// it is just not a deletion path. A deletion path removes the
  /// container.
  ///
  /// WHAT IS NOT YET DONE WITH THIS: the directory itself, the entry in
  /// `identities.json` and the attachments (`*.cmenc`). Those belong to the
  /// `IdentityManager` — see the paragraph at the end of this comment and
  /// [CleonaService.onIdentityDeletedRemotely], which to this day has no
  /// assigner in `lib/` (gap book P-12).
  ///
  /// The order is NOT arbitrary: first clear and save, then delete.
  /// The other way round, step 1 would recreate the files.
  ///
  /// WHAT DOES NOT HAPPEN HERE, and why: the identity's entry in
  /// `identities.json` and the directory itself belong to the
  /// `IdentityManager`, i.e. the level above this service
  /// (`service_daemon.dart::_deleteIdentityAtRuntime`,
  /// `IdentityManager.deleteIdentity`). The service reports the deletion
  /// upwards via [CleonaService.onIdentityDeletedRemotely], instead of
  /// reaching into a foreign layer.
  void _wipeLocalIdentityData() {
    // 1a. Clear memory.
    _contacts.clear();
    _deletedContacts.clear();
    conversations.clear();
    _groups.clear();
    _channels.clear();
    _processedSyncIds.clear();
    // THE OWN DEVICE ROW TOO. Do not spare `_localDeviceId`: it is
    // `late final` and only set by `_initLocalDevice()` — a frame that
    // reaches a service without this step would throw a
    // `LateInitializationError` here IN THE MIDDLE of the deletion and
    // leave it half executed.
    //
    // The consequence for the immediately following `_saveDevices()` is
    // intended: with an empty set and a still existing file its own gate
    // ("REFUSED to save empty devices") takes hold and writes NOTHING —
    // the file falls in step 2, its old content goes with it. That is
    // exactly right here; the gate protects against accidental empty
    // writing, not against a deletion.
    _devices.clear();

    // 1b. And save, so that no later writer brings the old state back.
    //     `_saveConversations` batches for two seconds — here the batcher
    //     is bypassed, because there is no "later" any more.
    _saveContacts();
    _saveConversationsNow();
    _saveGroups();
    _saveChannels();
    _saveDevices();

    // 2. Remove the stores themselves.
    var deleted = 0;

    // 2a. THE STORE (S377) — since S366 it carries everything the comment
    //     above lists. CLOSE FIRST: an open handle leaves `-wal`/`-shm`
    //     behind and on Windows holds the file itself locked.
    //     `closeStore()` closes both handles (that of the service and that
    //     of the identity).
    closeStore();
    for (final name in const [
      'messages.db',
      'messages.db-wal',
      'messages.db-shm',
    ]) {
      final file = File('$profileDir/$name');
      try {
        if (file.existsSync()) {
          file.deleteSync();
          deleted++;
        }
      } catch (e) {
        _log.warn('TWIN_IDENTITY_DELETED: $name was left behind: $e');
      }
    }

    // 2b. The old stock from the time before S366. On a field profile there
    //     is nothing left to do here; on a profile without HD wallet
    //     (guard, §21.4.1) it is the only way.
    try {
      final registry = Directory(profileDir);
      if (registry.existsSync()) {
        for (final entry in registry.listSync()) {
          if (entry is! File) continue;
          if (!entry.path.endsWith('.json.enc')) continue;
          try {
            entry.deleteSync();
            deleted++;
          } catch (e) {
            _log.warn('TWIN_IDENTITY_DELETED: ${entry.path} was left behind: $e');
          }
        }
      }
    } catch (e) {
      _log.error('TWIN_IDENTITY_DELETED: profile directory not readable: $e');
    }
    _log.warn('TWIN_IDENTITY_DELETED: $deleted encrypted stores '
        'removed, memory cleared');
    onStateChanged?.call();
  }
}
