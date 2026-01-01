import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/crypto/hd_wallet.dart';
import 'package:cleona/core/crypto/keyring_service.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/network/clogger.dart';

/// Migrates pre-keyring profiles to the §3.7 key cascade:
///   OS Keyring → Master-Seed → derived FileEncryption keys
///
/// Migration runs once per profile. The old db.key is renamed to
/// .db.key.migrated (rollback safety) and a .keyring_migrated marker
/// prevents re-runs.
class KeyMigration {
  static final _log = CLogger.get('key-migration');

  static const _serviceFiles = [
    'conversations.json',
    'contacts.json',
    'groups.json',
    'channels.json',
    'outbox.json',
    'mailbox_transition.json',
    'membership_resend.json',
    'processed_msg_ids.json',
  ];

  /// Repair profiles where migration completed but service-level .enc files
  /// were not re-encrypted (bug in versions before v3.1.109).
  /// Uses the backup `.db.key.migrated` to decrypt, then re-encrypts with
  /// the correct seed-derived key.
  static bool repairIfNeeded(String baseDir) {
    final marker = File('$baseDir/.keyring_migrated');
    if (!marker.existsSync()) return false; // not yet migrated

    final repairMarker = File('$baseDir/.keyring_repair_v2');
    if (repairMarker.existsSync()) return false; // already repaired

    final oldKeyFile = File('$baseDir/.db.key.migrated');
    if (!oldKeyFile.existsSync()) {
      repairMarker.writeAsStringSync(DateTime.now().toIso8601String());
      return false; // no old key — nothing to repair
    }

    final oldKeyBytes = oldKeyFile.readAsBytesSync();
    if (oldKeyBytes.length != 32) {
      _log.warn('Repair: .db.key.migrated has unexpected length '
          '${oldKeyBytes.length} — skipping');
      repairMarker.writeAsStringSync('skip:bad-key-length');
      return false;
    }

    final keyring = KeyringService.instance;
    final seedBytes = keyring.load('master_seed');
    if (seedBytes == null) {
      _log.warn('Repair: master_seed not in keyring — skipping');
      repairMarker.writeAsStringSync('skip:no-seed');
      return false;
    }

    _log.info('Repairing service-level files missed by initial migration...');
    final oldFileEnc = FileEncryption(
      baseDir: baseDir, key: Uint8List.fromList(oldKeyBytes));

    final identityMgr = IdentityManager(baseDir: baseDir);
    final identities = identityMgr.loadIdentities();
    var repaired = 0;

    for (final identity in identities) {
      final hdIndex = identity.hdIndex;
      if (hdIndex == null) continue;

      final fileEncKey = HdWallet.deriveFileEncKey(seedBytes, hdIndex);
      final newFileEnc = FileEncryption(baseDir: baseDir, key: fileEncKey);

      // iOS container UUIDs change between app updates — rebase profileDir
      var profileDir = identity.profileDir;
      if (!Directory(profileDir).existsSync() &&
          profileDir.contains('/.cleona/')) {
        final relative = profileDir.split('/.cleona/').last;
        final rebased = '$baseDir/$relative';
        if (Directory(rebased).existsSync()) {
          _log.info('Repair: rebased profileDir to $rebased');
          profileDir = rebased;
        }
      }

      for (final name in _serviceFiles) {
        final path = '$profileDir/$name';
        final encFile = File('$path.enc');
        if (!encFile.existsSync()) continue;

        // Try new key first — if it works, file is already correct
        final alreadyOk = newFileEnc.readJsonFile(path);
        if (alreadyOk != null) continue;

        // Try old key
        final recovered = oldFileEnc.readJsonFile(path);
        if (recovered == null) {
          _log.warn('Repair: $name unreadable with both keys');
          continue;
        }

        // Re-encrypt with the correct derived key
        newFileEnc.writeJsonFile(path, recovered);
        _log.info('Repair: $name re-encrypted for '
            '"${identity.displayName}"');
        repaired++;
      }
    }

    repairMarker.writeAsStringSync(DateTime.now().toIso8601String());
    if (repaired > 0) {
      _log.info('Repair complete: $repaired files re-encrypted');
    } else {
      _log.info('Repair complete: no files needed re-encryption');
    }
    return repaired > 0;
  }

  /// Run migration if needed. Returns true if migration was performed.
  static bool migrateIfNeeded(String baseDir) {
    final marker = File('$baseDir/.keyring_migrated');
    if (marker.existsSync()) return false;

    final dbKeyFile = File('$baseDir/db.key');
    if (!dbKeyFile.existsSync()) {
      // Fresh install — no migration needed, mark as current
      marker.createSync(recursive: true);
      return false;
    }

    _log.info('Migrating profile to keyring-based key derivation...');

    try {
      _performMigration(baseDir, dbKeyFile);
      marker.writeAsStringSync(DateTime.now().toIso8601String());
      _log.info('Migration complete');
      return true;
    } catch (e, st) {
      _log.error('Migration failed (profile unchanged): $e\n$st');
      // Don't write marker — retry on next start
      return false;
    }
  }

  static bool _seedPhraseStored = false;

  static void _performMigration(String baseDir, File dbKeyFile) {
    _seedPhraseStored = false;
    final keyring = KeyringService.instance;
    final oldFileEnc = FileEncryption(baseDir: baseDir); // uses db.key

    // ── 1. Migrate master_seed to keyring ────────────────────────────────

    final seedJson = oldFileEnc.readJsonFile('$baseDir/master_seed.json');
    if (seedJson == null) {
      if (_anyIdentityHasHdIndex(baseDir)) {
        throw StateError('master_seed.json missing but HD-derived identities '
            'exist — seed file corrupted, cannot migrate');
      }
      _log.warn('No master_seed.json found — skipping migration (legacy pre-HD profile)');
      return;
    }
    final seedHex = seedJson['seed'] as String?;
    if (seedHex == null) {
      if (_anyIdentityHasHdIndex(baseDir)) {
        throw StateError('master_seed.json has no seed field but HD-derived '
            'identities exist — seed file corrupted, cannot migrate');
      }
      _log.warn('master_seed.json has no seed field — skipping (legacy pre-HD profile)');
      return;
    }
    final masterSeed = _hexToBytes(seedHex);

    if (!keyring.store('master_seed', masterSeed)) {
      throw StateError('Failed to store master_seed in keyring');
    }
    _log.info('Master seed stored in keyring');

    // Also migrate seed phrase if present
    final phraseJson = oldFileEnc.readJsonFile('$baseDir/seed_phrase.json');
    if (phraseJson != null) {
      final words = phraseJson['words'] as List<dynamic>?;
      if (words != null) {
        final phraseBytes = Uint8List.fromList(words.join(' ').codeUnits);
        _seedPhraseStored = keyring.store('seed_phrase', phraseBytes);
        if (!_seedPhraseStored) {
          _log.warn('Keyring store failed for seed_phrase — '
              'keeping legacy file as fallback');
        } else {
          _log.info('Seed phrase stored in keyring');
        }
      }
    }

    // ── 2. Re-encrypt device_keys with shared derived key ───────────────
    // DeviceKeysStore still reads device_keys.bin.enc for the admission nonce,
    // so we re-encrypt in place rather than moving to keyring-only.

    final sharedKey = HdWallet.deriveSharedFileEncKey(masterSeed);
    final sharedFileEnc = FileEncryption(baseDir: baseDir, key: sharedKey);

    final deviceKeysData = oldFileEnc.readBinaryFile('$baseDir/device_keys.bin');
    if (deviceKeysData != null) {
      sharedFileEnc.writeBinaryFile('$baseDir/device_keys.bin', deviceKeysData);
      _log.info('Device keys re-encrypted with derived key');
    }

    // ── 3. Re-encrypt per-identity files with derived keys ───────────────

    final identityMgr = IdentityManager(baseDir: baseDir);
    final identities = identityMgr.loadIdentities();

    for (final identity in identities) {
      final hdIndex = identity.hdIndex;
      if (hdIndex == null) {
        _log.warn('Identity "${identity.displayName}" has no hdIndex — '
            'cannot derive key, keeping old encryption');
        continue;
      }

      final fileEncKey = HdWallet.deriveFileEncKey(masterSeed, hdIndex);
      final newFileEnc = FileEncryption(baseDir: baseDir, key: fileEncKey);
      final profileDir = identity.profileDir;

      // Per-identity files (Identity layer)
      _reEncryptJsonFile(oldFileEnc, newFileEnc, '$profileDir/keys.json');
      _reEncryptJsonFile(oldFileEnc, newFileEnc, '$profileDir/identity_resolution.json');
      _reEncryptJsonFile(oldFileEnc, newFileEnc, '$profileDir/polls.json');
      _reEncryptJsonFile(oldFileEnc, newFileEnc, '$profileDir/calendar_events.json');
      _reEncryptJsonFile(oldFileEnc, newFileEnc, '$profileDir/calendar_settings.json');
      _reEncryptJsonFile(oldFileEnc, newFileEnc, '$profileDir/calendar_sync_config.json');
      _reEncryptJsonFile(oldFileEnc, newFileEnc, '$profileDir/calendar_sync_state.json');
      _reEncryptJsonFile(oldFileEnc, newFileEnc, '$profileDir/key_rotation_retry.json');
      _reEncryptJsonFile(oldFileEnc, newFileEnc, '$profileDir/guardian_shares.json');
      _reEncryptJsonFile(oldFileEnc, newFileEnc, '$profileDir/guardian_list.json');

      // CleonaService-level files (also per-identity, in same profileDir)
      for (final name in _serviceFiles) {
        _reEncryptJsonFile(oldFileEnc, newFileEnc, '$profileDir/$name');
      }

      _log.info('Identity "${identity.displayName}" (index $hdIndex) re-encrypted');
    }

    // ── 4. Remove old encryption artefacts ─────────────────────────────

    // master_seed is in keyring — remove .enc file
    _deleteEncFile('$baseDir/master_seed.json');
    // seed_phrase: only delete if keyring store succeeded
    if (_seedPhraseStored) {
      _deleteEncFile('$baseDir/seed_phrase.json');
    } else {
      _log.info('Keeping seed_phrase.json.enc — keyring store was '
          'skipped or failed');
    }

    // Rename db.key for rollback safety (not deleted)
    final backupPath = '$baseDir/.db.key.migrated';
    dbKeyFile.renameSync(backupPath);
    _log.info('Old db.key renamed to .db.key.migrated');
  }

  static void _reEncryptJsonFile(
    FileEncryption oldEnc, FileEncryption newEnc, String path,
  ) {
    final json = oldEnc.readJsonFile(path);
    if (json == null) return;
    newEnc.writeJsonFile(path, json);
  }

  static void _deleteEncFile(String basePath) {
    for (final suffix in ['.enc', '.enc.tmp', '.enc.old']) {
      final f = File('$basePath$suffix');
      if (f.existsSync()) f.deleteSync();
    }
  }

  /// Returns true if any identity in identities.json has hdIndex > 0,
  /// indicating a seed must have existed at some point.
  static bool _anyIdentityHasHdIndex(String baseDir) {
    try {
      final identitiesFile = File('$baseDir/identities.json');
      if (!identitiesFile.existsSync()) return false;
      final content = identitiesFile.readAsStringSync();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final list = json['identities'] as List<dynamic>? ?? [];
      for (final entry in list) {
        final map = entry as Map<String, dynamic>;
        final hdIndex = map['hdIndex'] as int?;
        if (hdIndex != null && hdIndex > 0) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Uint8List _hexToBytes(String hex) {
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}
