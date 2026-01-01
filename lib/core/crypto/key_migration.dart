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

  static void _performMigration(String baseDir, File dbKeyFile) {
    final keyring = KeyringService.instance;
    final oldFileEnc = FileEncryption(baseDir: baseDir); // uses db.key

    // ── 1. Migrate master_seed to keyring ────────────────────────────────

    final seedJson = oldFileEnc.readJsonFile('$baseDir/master_seed.json');
    if (seedJson == null) {
      _log.warn('No master_seed.json found — skipping migration');
      return;
    }
    final seedHex = seedJson['seed'] as String?;
    if (seedHex == null) {
      _log.warn('master_seed.json has no seed field — skipping');
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
        keyring.store('seed_phrase', phraseBytes);
        _log.info('Seed phrase stored in keyring');
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

      _log.info('Identity "${identity.displayName}" (index $hdIndex) re-encrypted');
    }

    // ── 4. Remove old encryption artefacts ─────────────────────────────

    // master_seed and seed_phrase are now in the keyring — remove .enc files
    _deleteEncFile('$baseDir/master_seed.json');
    _deleteEncFile('$baseDir/seed_phrase.json');

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

  static Uint8List _hexToBytes(String hex) {
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}
