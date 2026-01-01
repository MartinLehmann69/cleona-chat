import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/crypto/hd_wallet.dart';
import 'package:cleona/core/crypto/keyring_service.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/platform/app_paths.dart';

/// THE TAKEOVER OF A LEGACY PROFILE IS GONE (S368). What remains here is
/// the device-wide envelope change — and the inventory lists against which
/// the guards measure which file lies under which key.
///
/// ── WHAT WAS REMOVED, AND WHY ──────────────────────────────────
///
/// Here stood `migrateIfNeeded` / `_performMigration` (takeover of a
/// profile from the time before the keyring) and `repairIfNeeded`
/// (after-repair of a takeover from versions before v3.1.109). Both were
/// removed on 05.09.2026, for two reasons, each of which suffices on
/// its own:
///
/// **1. The invariant.** "V4.1 is not backward compatible", "There are
/// no legacy profiles", "Profiles are wiped" (owner, literally on three
/// days). Code that READS an old format is thus dead; code that DELETES
/// it lives. Both functions read.
///
/// **2. They could no longer hit their target at all — measured.** Since
/// the first-start deletion path (S363, option A), `FirstStartWipe
/// .runFirstStartWipe` is the FIRST line of `IdentityContext.initCrypto`
/// and `migrateIfNeeded` stood after it. A profile without the V4.1 marker
/// is already completely deleted at this point; a profile WITH the marker
/// stems from a V4.1 state and was never a legacy profile. The set to
/// which `migrateIfNeeded` could ever apply was empty after S363.
///
/// **3. It asked the question of a proxy.** `migrateIfNeeded`
/// decided "new or old profile?" by the mere EXISTENCE of
/// `db.key` — a file that the application back then created ITSELF:
/// `IdentityManager._storeMasterSeed` built a `FileEncryption` without a
/// key, and its keyless branch created it anew.
///
/// **RE-MEASURED ON 08.09.2026 (S376): this branch no longer
/// exists.** `FileEncryption` without a key THROWS since S368
/// (`_loadLegacyKeyOrThrow`: "refusing to mint a random db.key"), and
/// `IdentityManager._storeMasterSeed` throws as well, instead of falling
/// back to `master_seed.json.enc` under the raw `db.key`. The sentence
/// stood here in the present tense until today and named a line location
/// (`file_encryption.dart:66-68`) where `hasLegacyKey` stands today —
/// the gate `check-code-line-refs.sh` checks THAT a reference resolves,
/// not TO WHAT. It is thus past, and that now stands there. On the UI's
/// order (seed -> identity -> daemon) the takeover therefore started on a
/// profile that was not a second old, and at the end renamed `db.key` to
/// `.db.key.migrated` — a raw 32-byte key that would not have come into
/// existence at all without this misdiagnosis and afterwards lay
/// permanently in the profile. `LegacyKeyPurge`
/// (`legacy_key_purge.dart`) cleans it up retroactively.
///
/// **Not removed: [migrateDeviceScopedFiles].** It asks THE SAME
/// question not of the file name but of the matter itself: it checks per
/// file whether the derived key already opens it, and changes only the
/// envelope of what still lies under the old one. It is repeatable,
/// resumable after an abort, and replaces the old format instead of
/// continuing to write it.
class KeyMigration {
  // `_log` is static and is loaded before any `baseDir` argument is known
  // (every migration method only gets it as a parameter) ->
  // no per-identity profileDir reachable at construction time.
  static final _log = CLogger.get('key-migration', profileDir: AppPaths.dataDir);

  // ── THE RE-KEYING SET (re-measured in S366) ─────────────────────
  //
  // WHAT THESE LISTS ARE: the complete set of files that lie sealed in the
  // profile under a DERIVED key. Whatever is missing here stays under the
  // OLD key on a key change and can no longer be decrypted afterwards.
  //
  // ── THE BASIC QUESTION: IS THIS LIST STILL NEEDED AT ALL? ────────
  //
  // For the largest part of the holdings: NO, no longer. Until S366 every
  // collection lay in its own `*.json.enc` file, and every single one had
  // to stand here. Since S366 about thirty collections lie in the
  // STORAGE — `messages.db`, ONE file under ONE key
  // (`HdWallet.deriveFileEncKey`, `message_store.dart`). A key change is
  // ONE operation there and needs no entry per collection; the next moved
  // collection therefore no longer falls out here either. Exactly for
  // that reason the list shrank on re-measuring from eighteen names to
  // ten: THIRTEEN of them no longer had a writer in `lib/`
  // (`conversations.json`, `contacts.json`,
  // `groups.json`, `channels.json`, `outbox.json`,
  // `mailbox_transition.json`, `membership_resend.json`,
  // `moderation.json`, `channel_index.json`, `media_settings.json`,
  // `link_preview_settings.json`, `multi_interface_mode.json`,
  // `nat_wizard_settings.json`), nor did the six that were listed
  // individually further below (`polls.json`, the four `calendar_*` and
  // `key_rotation_retry.json`). They were not "forgotten" — they moved
  // into the storage.
  //
  // What REMAINS lying next to it stands here, and it is measured instead
  // of enumerated: `smoke_key_rotation_list.dart` holds these lists
  // against the actual callers of `FileEncryption.writeJsonFile`/
  // `writeBinaryFile` and `PlaintextSweep.sweepOne` in `lib/` — in BOTH
  // directions. A new writer without an entry is red, an entry without a
  // writer as well.
  //
  // WHY THE FOUR SWEEPER NAMES STAY IN, although their collections have
  // long been in the storage: `PlaintextSweep` still WRITES them — it
  // encrypts a plaintext remnant found in a legacy profile under exactly
  // this key (`cleona_service.dart:_sweepPlaintextUserContent`). An entry
  // missing here would be a remnant that can no longer be opened at all
  // after the key change.

  /// Per IDENTITY, sealed with `HdWallet.deriveFileEncKey(seed, hdIndex)`.
  ///
  /// Measured completely against the writers in `lib/` (05.09.2026):
  ///
  ///   keys.json                 identity_context.dart, identity_manager.dart
  ///   v41_prekeys.json          v41_attach.dart
  ///   v41_daily_secrets.json    v41_attach.dart
  ///   voice_transcriptions.json cleona_service.dart (PlaintextSweep)
  ///   profile_picture.b64       cleona_service.dart (PlaintextSweep)
  ///   profile_description.txt   cleona_service.dart (PlaintextSweep)
  ///   reputation.json           cleona_service.dart (PlaintextSweep)
  ///
  /// ── THREE NAMES ARE OUT OF HERE (S368) ───────────────────────────────
  ///
  /// `identity_resolution.json`, `processed_msg_ids.json` and
  /// `linked_device_keys.json` stood in the list until now and had
  /// NEITHER writer NOR reader in `lib/` and `bin/`. Re-measured on
  /// 05.09.2026 with seven independent search patterns (full file name,
  /// stem without extension, camelCase variants, concatenation pattern,
  /// `lib/core/ipc/` for name strings, `proto/` including generated code,
  /// and `git grep` as a second indexer): not a single hit is a
  /// `File(...)`, `writeJsonFile`, `readJsonFile` or `AtomicJsonWriter`
  /// on one of these names — only comments, docs and this list entry
  /// itself.
  ///
  /// They moved into `messages.db` with `31328094` ("identity collections
  /// into the storage", S366). Their carriers today are AREAS of the table
  /// `state`: `LinkedDeviceKeysStore.area = 'linked_device_keys'`
  /// (`linked_device_keys_store.dart:45`),
  /// `CleonaService.areaProcessedIds = 'processed_msg_ids'`
  /// (`cleona_service.dart:7564`); the counters behind
  /// `identity_resolution.json` have been dropped entirely with the 2D DHT
  /// resolution (`identity_context.dart:202-226`).
  ///
  /// ── AND IS THIS CONTENT TAKEN ALONG ON A KEY CHANGE? ──────
  ///
  /// The question is the right one — a name that falls out of the work
  /// list without the new carrier being covered would be silent data loss
  /// at the next emergency rotation. Re-measured, and the answer is:
  /// **today there is no key change at this place at all**, neither for
  /// the files nor for the storage.
  ///
  ///  * [reencryptIdentityFiles] is the ONLY executor of this list
  ///    and has ZERO callers in `lib/` and `bin/` (only the guard
  ///    `smoke_key_rotation_list.dart` runs it).
  ///  * The emergency rotation (§7.5/§14.4,
  ///    `cleona_service.dart:_performEmergencyKeyRotation`) does form a
  ///    `newMasterSeed`, but uses it only as a derivation function for the
  ///    new signature/KEM keys and throws it away. What is applied is
  ///    `identity.rotateIdentityFull(...)`, and the method assigns NEITHER
  ///    `masterSeed` NOR `hdIndex` (re-measured over all assignments in
  ///    `identity_context.dart`).
  ///  * `deriveFileEncKey(masterSeed, hdIndex)` depends on exactly these
  ///    two values. They do not change, so the key of `messages.db` does
  ///    not change, so there is nothing to re-key.
  ///
  /// **Nothing is lost by the deletion**: the three files do not exist,
  /// and the list they fall out of is run by nobody. **What REMAINS open
  /// and is named here instead of kept silent:** should a real change of
  /// the storage key ever grow in, `messages.db` is covered by NO list
  /// (`smoke_key_rotation_list.dart` part D records that explicitly)
  /// — then a re-keyer for the STORAGE is needed, and this file list would
  /// not have helped with that anyway.
  /// ── TWO MORE NAMES ARE OUT (S372, 06.09.2026) ────────────────
  ///
  /// `v41_prekeys.json` and `v41_daily_secrets.json` moved into
  /// `messages.db` with this session's storage switch (areas
  /// `v41_prekeys` and `v41_daily_secrets`, `v41_attach.dart`). After that
  /// they no longer had a writer in `lib/` — the guard
  /// `smoke_key_rotation_list.dart` reported exactly that
  /// ("OHNE SCHREIBER: je Identitaet: v41_prekeys.json"), and it thereby
  /// did what it was built for: a list that carries a name without a
  /// carrier is a list that can no longer be believed.
  ///
  /// The question from the section above applies here unchanged and with
  /// the same answer: nothing can be lost, because there is no key change
  /// at this place — [reencryptIdentityFiles] still has zero callers, and
  /// the emergency rotation leaves `masterSeed` and `hdIndex`, on which
  /// `deriveFileEncKey` depends, untouched. The open point stays the same
  /// and only grows by two areas: should a real change of the STORAGE key
  /// ever come, `messages.db` is covered by no list.
  ///
  /// The legacy holdings are taken care of: `v41_attach.dart` takes over a
  /// found file into the storage on first access and deletes it only after
  /// the content demonstrably lies there.
  static const List<String> perIdentityFiles = [
    'keys.json',
    'voice_transcriptions.json',
    'profile_picture.b64',
    'profile_description.txt',
    'reputation.json',
  ];

  /// At the profile ROOT DIRECTORY, under a FOUND `db.key` and not under a
  /// derived key — the 24 words ARE the seed, and a key derived from them
  /// could not seal them (`identity_manager.dart:_storeSeedPhrase`).
  ///
  /// They stand here so that the guard
  /// `smoke_key_rotation_list.dart` recognises them as DECIDED and does
  /// not report them as a gap.
  ///
  /// ── `master_seed.json` STOOD HERE AND IS GONE (S368) ──────────────
  ///
  /// Until S368 this list carried the master seed along, and the reasoning
  /// above named finding F-4 from
  /// `docs/v4-redesign/S363-VORLAGE-android-sperre-und-salt.md` as an
  /// "open decision of the owner". Both are corrected: the owner has
  /// clarified that the target state was already built under 3.2.2 —
  /// `maintenance/3.2:key_migration.dart:251-252`:
  ///
  ///     // master_seed is in keyring — remove .enc file
  ///     _deleteEncFile('$baseDir/master_seed.json');
  ///
  /// `IdentityManager._storeMasterSeed` has since then stored the seed
  /// exclusively in the keyring, checks it back verbatim and then removes
  /// any `master_seed.json.enc`. There is thus NO writer of this name in
  /// `lib/` any more — an entry here would be a dead one, and exactly that
  /// is what the guard's staleness test checks.
  ///
  /// **Why `seed_phrase.json` stays.** Owner decision D3
  /// (03.09.2026): if the keyring rejects the WORDS, keeping them is
  /// better than losing them. But the branch now only writes via
  /// `FileEncryption.legacyOrNull` — it can no longer create a `db.key`,
  /// only use a found one. On a profile without a legacy key the words
  /// stay in the keyring or nowhere.
  static const List<String> deliberatelyUnderDbKey = [
    'seed_phrase.json',
  ];

  /// Device-wide under `HdWallet.deriveSharedFileEncKey(seed)` — but
  /// EXPLICITLY NOT in [deviceScopedJsonFiles], i.e. not part of the
  /// takeover that [migrateDeviceScopedFiles] runs on every start.
  ///
  /// **Why a list of its own and not the one next to it.** The two files
  /// lay in PLAINTEXT until S368, not under `db.key`. So there can be no
  /// profile that carries them under the legacy key — and entered in
  /// [deviceScopedJsonFiles], [migrateDeviceScopedFiles] would try on a
  /// profile with a found `db.key` to open with the WRONG key a ciphertext
  /// that already lies under the right one. Building a takeover for
  /// holdings that do not exist would be exactly the compatibility path
  /// that V4.1 does not have.
  ///
  /// The list is purely EXPLANATORY, like [deliberatelyUnderDbKey]: it says to
  /// which key class the files belong, so that the guard
  /// `smoke_key_rotation_list.dart` finds no writer without
  /// classification. It is run by nobody.
  ///
  /// `identities.json` carries the display name next to `nodeIdHex`,
  /// `last_profile.json` the same link for the active identity
  /// (S368, reasoning at `IdentityManager._identitiesFile`).
  static const List<String> deviceWideWithoutTakeover = [
    'identities.json',
    'last_profile.json',
  ];

  // ── S362: the device-wide storages at the profile ROOT DIRECTORY ──────
  //
  // The removed takeover (`_performMigration`, removed in S368) took two
  // classes along: the identity files (`deriveFileEncKey`) and
  // `device_keys.bin` (`deriveSharedFileEncKey`). A third class did not
  // yet exist in its time — the device-wide files of the V4.1 line, which
  // since S349/S354 lie next to the identity directories:
  //
  //     node_keys.enc        L_node/E_node/N_* — the entry key set
  //     v41_entries.json.enc the entry stock: WHOM this node knows
  //     v41_ages.json.enc    the peer age (§10.3, first condition)
  //
  // Until S362 they were sealed with the **legacy random key** `db.key`
  // — a file that lies in the SAME directory as the ciphertext. Against a
  // second local user that holds (`0600`); against a stolen device, a disk
  // image or a backup it holds nothing, because the key travels along.
  // Exactly for that the seed-derived derivation is built.
  //
  // WHY THIS IS A SEPARATE, SELF-HEALING FUNCTION and was not another step
  // of the removed takeover: that procedure ran **once** and then set
  // `.keyring_migrated`; a step there reached no already marked profile.
  // This function instead checks on EVERY start per file whether it
  // already lies under the derived key, and is thus repeatable and
  // resumable after an abort. **Exactly therein also lies the reason why
  // it survived the removal:** it decides by the MATTER (does the derived
  // key open this file?), not by a file name that happens to lie next to
  // it.
  //
  // ABORT SAFETY, step by step. Reading is done with the old key, writing
  // with the new one via `writeJsonFile`/`writeBinaryFile` — both are
  // tmp+rename, thus crash-atomic. Afterwards it is READ BACK and the
  // content compared; only this comparison decides. If it fails, the old
  // state is written back with the old key. A crash can hit the run only
  // at three places: before the `rename` (old file untouched, next start
  // repeats), after the `rename` (new file complete and readable, next
  // start skips it) or between two files (the rest move on the next
  // start). In no case is there a state in which the file is readable
  // under NEITHER of the two keys.
  //
  // The old key is **never generated**, only read: `db.key` or
  // `.db.key.migrated`, via `FileEncryption.legacyKeyBytes`.
  //
  // S376: here stood that a `FileEncryption(baseDir: …)` without a key
  // WOULD create the file on a new installation. That has not been so
  // since S368 — the keyless constructor throws. The sentence thus no
  // longer described the danger this place guards against; the caution
  // itself stays right and cheap.
  /// Device-wide, sealed with `HdWallet.deriveSharedFileEncKey(seed)`.
  ///
  /// S366 ADDED: `v41_rendezvous_ablage.json` (`v41_attach.dart:747`)
  /// was missing. It is the only LIVING re-keying path —
  /// [migrateDeviceScopedFiles] runs on every start and checks per
  /// file. A node that once ran without master seed
  /// (linked device, §7.6.2) has the tag lying under `db.key`; without
  /// this entry it stayed there and the node stored once too often on
  /// every start.
  ///
  /// `device_keys.bin` is also new here. Until S366 it was taken along ONLY
  /// by the meanwhile removed takeover — a path that ran exactly once per
  /// profile and after the first-start deletion path (§21.4) found no more
  /// holdings. Here it is covered repeatably.
  static const List<String> deviceScopedJsonFiles = [
    'v41_entries.json',
    'v41_ages.json',
    'v41_rendezvous_deposit.json',
  ];
  static const List<String> deviceScopedBinaryFiles = [
    'node_keys',
    'device_keys.bin',
  ];

  /// Re-seals the daemon-wide, device-scoped files at the profile root with
  /// `HdWallet.deriveSharedFileEncKey(masterSeed)`. Idempotent, resumable,
  /// and a no-op on devices without a master seed (Linked Devices, §7.6.2)
  /// and on profiles that never had a `db.key`.
  ///
  /// Returns the number of files actually re-encrypted by THIS call.
  static int migrateDeviceScopedFiles(String baseDir) {
    // Nothing to migrate unless at least one of the files exists.
    final candidates = <String>[
      for (final n in deviceScopedJsonFiles) n,
      for (final n in deviceScopedBinaryFiles) n,
    ];
    final present = candidates
        .where((n) => File('$baseDir/$n.enc').existsSync())
        .toList();
    if (present.isEmpty) return 0;

    final masterSeed = _seedForDeviceScope(baseDir);
    if (masterSeed == null) {
      // No seed reachable: linked device (§7.6.2 "NOT: the seed") or
      // a keyring that does not open right now. In BOTH cases doing
      // nothing is right — the files stay readable under the old key.
      // Rewriting with a guessed key would be the data loss this
      // function is meant to prevent.
      return 0;
    }
    final newEnc = FileEncryption(
        baseDir: baseDir, key: HdWallet.deriveSharedFileEncKey(masterSeed));

    FileEncryption? oldEnc;
    FileEncryption? legacyEnc() {
      if (oldEnc != null) return oldEnc;
      final bytes = FileEncryption.legacyKeyBytes(baseDir);
      if (bytes == null) return null;
      return oldEnc = FileEncryption(baseDir: baseDir, key: bytes);
    }

    var migrated = 0;
    for (final name in deviceScopedJsonFiles) {
      final path = '$baseDir/$name';
      if (!File('$path.enc').existsSync()) continue;
      if (newEnc.readJsonFile(path) != null) continue; // already sealed
      final old = legacyEnc();
      if (old == null) {
        _log.warn('Device-scoped migration: $name is not readable with the '
            'derived key and no legacy db.key exists — left untouched');
        continue;
      }
      final data = old.readJsonFile(path);
      if (data == null) {
        _log.warn('Device-scoped migration: $name unreadable with both keys '
            '— left untouched');
        continue;
      }
      newEnc.writeJsonFile(path, data);
      final back = newEnc.readJsonFile(path);
      if (back == null || jsonEncode(back) != jsonEncode(data)) {
        _log.error('Device-scoped migration: $name did not verify after '
            're-encryption — restoring the previous envelope');
        old.writeJsonFile(path, data);
        continue;
      }
      migrated++;
      _log.info('Device-scoped migration: $name re-encrypted with the '
          'seed-derived shared key');
    }

    for (final name in deviceScopedBinaryFiles) {
      final path = '$baseDir/$name';
      if (!File('$path.enc').existsSync()) continue;
      if (newEnc.readBinaryFile(path) != null) continue; // already sealed
      final old = legacyEnc();
      if (old == null) {
        _log.warn('Device-scoped migration: $name is not readable with the '
            'derived key and no legacy db.key exists — left untouched');
        continue;
      }
      final data = old.readBinaryFile(path);
      if (data == null) {
        _log.warn('Device-scoped migration: $name unreadable with both keys '
            '— left untouched');
        continue;
      }
      newEnc.writeBinaryFile(path, data);
      final back = newEnc.readBinaryFile(path);
      if (back == null || !_bytesEqual(back, data)) {
        _log.error('Device-scoped migration: $name did not verify after '
            're-encryption — restoring the previous envelope');
        old.writeBinaryFile(path, data);
        continue;
      }
      migrated++;
      _log.info('Device-scoped migration: $name re-encrypted with the '
          'seed-derived shared key');
    }

    return migrated;
  }

  /// The master seed for the device-scoped envelope. Keyring first (§3.7);
  /// the legacy `master_seed.json` only when a legacy key file ALREADY
  /// exists — reading it must never be the thing that creates `db.key`.
  static Uint8List? _seedForDeviceScope(String baseDir) {
    if (KeyringService.isInitialized) {
      final seed = KeyringService.instance.load('master_seed');
      if (seed != null && seed.isNotEmpty) return seed;
    }
    final legacy = FileEncryption.legacyKeyBytes(baseDir);  // V3-TOUCH-OK: legacy key fallback, normative in v4_1 §4.5.3 (db.key is one of the six files that never move into the database)
    if (legacy == null) return null;
    final enc = FileEncryption(baseDir: baseDir, key: legacy);
    final json = enc.readJsonFile('$baseDir/master_seed.json');
    final hex = json?['seed'] as String?;
    if (hex == null || hex.isEmpty) return null;
    try {
      return _hexToBytes(hex);
    } catch (_) {
      return null;
    }
  }

  // ── `_legacyKeyBytes` — DROPPED ON 08.09.2026 (S376) ─────────────
  //
  // It read `db.key`, otherwise `.db.key.migrated`, and was byte for byte
  // the same loop as `FileEncryption.legacyKeyBytes` — only without its
  // warning on wrong length. Two copies of ONE name list are two places
  // where a name changed later arrives at only one; the third copy lay in
  // `link/node_keys.dart` and is gone as well. There is now exactly one
  // reader, and `smoke_legacy_key_reader_guard.dart` records that.

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
  /// Re-keys ALL files from [perIdentityFiles] in [profileDir] from
  /// [oldEnc] to [newEnc]. Whatever is not present is skipped.
  ///
  /// PUBLIC, because the guard must be able to run it: a test that only
  /// READS the list does not prove that it is also applied.
  /// `smoke_key_rotation_list.dart` creates one file per name under one
  /// key, calls this function and reads all back under the other.
  ///
  /// **EXPLICITLY NAMED (S368): since the removal it has NO caller in
  /// `lib/` any more.** Its only one was `_performMigration`. It stays
  /// nevertheless, because it is the APPLYING counterpart to
  /// [perIdentityFiles] and the guard would otherwise only read a list
  /// that nobody runs. A key change during operation does not exist
  /// today: `deriveFileEncKey(masterSeed, hdIndex)` depends on two values
  /// that an identity rotation (§7.5, `_performKeyRotation`) touches
  /// NEITHER of — re-measured over all callers of `deriveFileEncKey` in
  /// `lib/`. Should such a change ever grow in, this is its place; until
  /// then the state is named here instead of kept silent.
  static void reencryptIdentityFiles(
      String profileDir, FileEncryption oldEnc, FileEncryption newEnc) {
    for (final name in perIdentityFiles) {
      _reEncryptJsonFile(oldEnc, newEnc, '$profileDir/$name');
    }
  }

  static void _reEncryptJsonFile(
    FileEncryption oldEnc, FileEncryption newEnc, String path,
  ) {
    final json = oldEnc.readJsonFile(path);
    if (json == null) return;
    newEnc.writeJsonFile(path, json);
  }

  static Uint8List _hexToBytes(String hex) {
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}
