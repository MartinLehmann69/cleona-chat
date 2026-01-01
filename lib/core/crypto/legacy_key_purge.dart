import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/crypto/key_migration.dart';
import 'package:cleona/core/crypto/keyring_service.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:path/path.dart' as p;

/// CLEANS UP THE RAW KEY THAT THE REMOVED TAKEOVER LEFT
/// BEHIND — `.db.key.migrated`.
///
/// ── WHAT IT AROSE FROM ────────────────────────────────────────────────
///
/// `KeyMigration.migrateIfNeeded` (removed in S368) decided "new or old
/// profile?" by the mere existence of `db.key`. On the UI's order,
/// however, the application creates this file ITSELF before the daemon
/// ever starts: `IdentityManager._storeMasterSeed` builds a
/// `FileEncryption` without a key, and `file_encryption.dart:66-68`
/// generates `db.key` in exactly this branch. The takeover therefore
/// started on a profile seconds old and at the end renamed `db.key` to
/// `.db.key.migrated`.
///
/// Measured on 05.09.2026, GUI order, fresh profile, real
/// `initCrypto` run:
///
///     [key-migration] Migrating profile to keyring-based key derivation...
///     [key-migration] Master seed stored in keyring
///     [key-migration] Old db.key renamed to .db.key.migrated
///     ...
///     "--- Zustand NACH initCrypto ---"
///       /.db.key.migrated  (32 B)
///
/// 32 raw key bytes, in plaintext, permanently. They would never have
/// come into existence without the misdiagnosis.
///
/// ── WHY THIS IS NOT "HARMLESS, BECAUSE EMPTY" ─────────────────────────
///
/// On a profile created this way the file opens nothing any more at the
/// same moment (the takeover had deleted `master_seed.json.enc` and
/// `seed_phrase.json.enc`).
///
/// ── THE REASONING WAS OUTDATED (re-measured 08.09.2026, S376) ─────
///
/// Here stood: "`_storeMasterSeed` rewrites `master_seed.json.enc` on
/// EVERY recovery. The next such write thus seals the master seed again
/// under a key that lies openly next to it. The file is not a corpse, it
/// is a loaded weapon."
///
/// **This write no longer exists.**
/// `IdentityManager._storeMasterSeed` (`identity_manager.dart:415-439`)
/// THROWS without a keyring instead of falling back to the file, and
/// `FileEncryption` without a key throws as well ("refusing to mint a
/// random db.key"). The loading that kept the weapon loaded has been
/// dropped with S368 — the place cited here, `file_encryption.dart:41-49`,
/// today carries `legacyOrNull`, which explicitly returns `null` instead
/// of silently inventing a key.
///
/// ── WHY IT IS CLEANED UP NEVERTHELESS ──────────────────────────────
///
/// Because 32 raw key bytes in plaintext have no business in the profile
/// even when nothing hangs on them any more: `legacyKeyBytes` still reads
/// them (and MUST, otherwise legacy holdings would stay unreadable), they
/// lie in every image and in every backup, and a later path that uses
/// them again would be a silent fallback. A cleaner needs no acute weapon
/// as justification — a plaintext key suffices.
///
/// ── IT DELETES, IT DOES NOT MIGRATE ──────────────────────────────────
///
/// That is the reason why this building block may live under the owner
/// invariant while the takeover had to die: it reads no old format in
/// order to continue writing it — it establishes that nothing hangs on it
/// any more and removes it. Where something does still hang on it, it
/// touches NOTHING and says so loudly. A cleaner that deletes when in
/// doubt would be data loss.
///
/// ── F-4 IS NOT AN OPEN QUESTION BUT A REGRESSION ──────────────
///
/// Until S368 here stood that `db.key` itself stays untouched, because
/// finding F-4 (`docs/v4-redesign/S363-VORLAGE-android-sperre-und-salt.md`)
/// was listed as an open decision of the owner. **That was wrong.** The
/// owner has clarified: the target state was already built under 3.2.2
/// — `maintenance/3.2:key_migration.dart:251-252`:
///
///     // master_seed is in keyring — remove .enc file
///     _deleteEncFile('$baseDir/master_seed.json');
///
/// The seed lies in the keyring, and the file next to it goes as soon as
/// it lies there. A post-quantum-secure messenger does not store a key
/// in plaintext. This class therefore cleans up BOTH names —
/// `.db.key.migrated` AND `db.key` —, each only when demonstrably nothing
/// hangs on it any more.
///
/// The irony, and it is the actual danger: the mechanism that deleted the
/// file sat IN `KeyMigration` — exactly what S368 removed. A removal
/// without this replacement would have left the chain
/// `db.key -> master_seed.json.enc -> storage key` permanently open.
class LegacyKeyPurge {
  LegacyKeyPurge._();

  /// The logger of THIS run — at `baseDir`, not at `AppPaths.dataDir`.
  ///
  /// Until S370 here stood `static final _log = CLogger.get('legacy-key-purge',
  /// profileDir: AppPaths.dataDir)`. That wrote the reasoning for a verdict
  /// about `baseDir` into the log directory of a DIFFERENT profile —
  /// measured on 06.09.2026 with `smoke_legacy_purge_foreign_profile_guard`
  /// (F4/F4b): the lines stood under `AppPaths.dataDir/logs`, under
  /// `BASIS/logs` there was none. A cleaner whose reasoning lies elsewhere
  /// cannot be traced in case of error.
  static CLogger _logFor(String baseDir) =>
      CLogger.get('legacy-key-purge', profileDir: baseDir);  // V3-TOUCH-OK: legacy key fallback, normative in v4_1 §4.5.3 (db.key is one of the six files that never move into the database)

  /// The name that the removed takeover left behind.
  static const String legacyKeyFilename = '.db.key.migrated';  // V3-TOUCH-OK: legacy key fallback, normative in v4_1 §4.5.3 (db.key is one of the six files that never move into the database)

  /// The plaintext key itself. Until S368 `FileEncryption` generated it
  /// anew on every keyless construction; it no longer does, and legacy
  /// holdings are removed here.
  static const String dbKeyFilename = 'db.key';

  /// Both names, in the order in which they are checked.
  static const List<String> allLegacyNames = <String>[
    legacyKeyFilename,
    dbKeyFilename,
  ];

  /// Result of a run — deliberately three-valued, so that the guard can
  /// measure the statement and not just "did something".
  ///
  /// * [nothingToDo]   — the file does not exist (the normal case after S368).
  /// * [removed]      — it lay there, hangs on nothing any more, is now gone.
  /// * [stillUsed] — it still opens content; NOTHING was deleted.
  static const int nothingToDo = 0;
  static const int removed = 1;
  static const int stillUsed = 2;

  /// Cleans up BOTH plaintext key files — `.db.key.migrated` and
  /// `db.key` —, each only when demonstrably nothing hangs on it any more.
  ///
  /// Return: [removed] as soon as at least one fell; [stillUsed] if at
  /// least one had to stay and none fell; otherwise [nothingToDo]. If one
  /// falls and the other stays, the result is [stillUsed] — the state
  /// "plaintext still lies there" is the statement that matters.
  ///
  /// MUST RUN AFTER `KeyMigration.migrateDeviceScopedFiles`: that first
  /// takes the device-wide files off these keys. If the cleaner ran
  /// before, it would find them still hanging on it and would
  /// (rightly) leave everything — the key would stay forever.
  ///
  /// **Order within the run:** first `.db.key.migrated`, then `db.key`.
  /// The other way round, the first pass could clean away
  /// `master_seed.json.enc` under `db.key` and the second would then
  /// consider `.db.key.migrated` as "hangs on nothing", although it was
  /// never checked.
  static int purge(String baseDir) {
    var somethingFell = false;
    var somethingStayed = false;
    for (final name in allLegacyNames) {
      switch (_purgeOne(baseDir, name)) {
        case removed:
          somethingFell = true;
        case stillUsed:
          somethingStayed = true;
        default:
          break;
      }
    }
    if (somethingStayed) return stillUsed;
    return somethingFell ? removed : nothingToDo;
  }

  static int _purgeOne(String baseDir, String legacyKeyFilename) {
    final sep = Platform.pathSeparator;
    final log = _logFor(baseDir);
    final file = File('$baseDir$sep$legacyKeyFilename');
    if (!file.existsSync()) return nothingToDo;

    List<int> rawBytes;
    try {
      rawBytes = file.readAsBytesSync();
    } catch (e) {
      log.warn('$legacyKeyFilename is not readable ($e) — nothing done');
      return stillUsed;
    }
    if (rawBytes.length != 32) {
      // No usable key file: by construction it opens nothing, and
      // `_loadOrCreateLegacyKey` rejects it as well
      // (`file_encryption.dart:44`). Away with it.
      log.info('$legacyKeyFilename has ${rawBytes.length} B instead of 32 — '
          'not a usable key, is being removed');
      return _delete(file, log) ? removed : stillUsed;
    }

    final old = FileEncryption(
        baseDir: '$baseDir${sep}__nie__', key: Uint8List.fromList(rawBytes));

    // ── 1. Do the seed or the phrase still hang on it? ────────────────
    //
    // If so, the file may only go if the same value demonstrably ALSO
    // lies in the keyring. What is compared is the CONTENT, not the mere
    // presence of an entry — a keyring with a DIFFERENT seed would be the
    // worst case a cleaner could silently seal.
    final hanging = <String>[];

    final seedJson = old.readJsonFile('$baseDir${sep}master_seed.json');
    if (seedJson != null) {
      if (_seedStandsInKeyring(seedJson)) {
        old.deleteFile('$baseDir${sep}master_seed.json');
        log.info('master_seed.json.enc was under the legacy key and '  // V3-TOUCH-OK: legacy key fallback, normative in v4_1 §4.5.3 (db.key is one of the six files that never move into the database)
            'is identical in the keyring — the file is removed');
      } else {
        hanging.add('master_seed.json');
      }
    }

    final phraseJson = old.readJsonFile('$baseDir${sep}seed_phrase.json');
    if (phraseJson != null) {
      if (_phraseStandsInKeyring(phraseJson)) {
        old.deleteFile('$baseDir${sep}seed_phrase.json');
        log.info('seed_phrase.json.enc was under the legacy key and '  // V3-TOUCH-OK: legacy key fallback, normative in v4_1 §4.5.3 (db.key is one of the six files that never move into the database)
            'is identical in the keyring — the file is removed');
      } else {
        hanging.add('seed_phrase.json');
      }
    }

    // ── 2. Does a device-wide file still hang on it? ─────────────────
    for (final n in KeyMigration.deviceScopedJsonFiles) {
      if (old.readJsonFile('$baseDir$sep$n') != null) hanging.add(n);
    }
    for (final n in KeyMigration.deviceScopedBinaryFiles) {
      if (old.readBinaryFile('$baseDir$sep$n') != null) hanging.add(n);
    }

    // ── 3. Does an identity file still hang on it? ───────────────────
    for (final id in _profileDirectories(baseDir)) {
      for (final n in KeyMigration.perIdentityFiles) {
        if (old.readJsonFile('$id$sep$n') != null) {
          hanging.add('${id.split(sep).last}$sep$n');
        }
      }
    }

    if (hanging.isNotEmpty) {
      log.error('$legacyKeyFilename still opens ${hanging.length} '
          'file(s) — NOTHING deleted: ${hanging.join(", ")}');
      return stillUsed;
    }

    log.info('$legacyKeyFilename opens nothing any more — being removed');
    return _delete(file, log) ? removed : stillUsed;
  }

  /// Overwrites the 32 bytes before the directory entry goes.
  ///
  /// **This is NOT a deletion guarantee** and is not presented as one
  /// here: on a journaling or copy-on-write file system (btrfs, ZFS, APFS,
  /// every SSD FTL) the old block may physically remain. It costs one
  /// write and covers the cheapest case — a file that was not overwritten,
  /// only unlinked, and whose content a `grep` over the raw device
  /// finds.
  static bool _delete(File file, CLogger log) {
    try {
      file.writeAsBytesSync(Uint8List(32), flush: true);
    } catch (e) {
      log.warn('Overwriting ${file.path} failed: $e — '
          'it is deleted anyway');
    }
    try {
      file.deleteSync();
      return true;
    } catch (e) {
      log.error('${file.path} could not be deleted: $e');
      return false;
    }
  }

  static bool _seedStandsInKeyring(Map<String, dynamic> json) {
    if (!KeyringService.isInitialized) return false;
    final outFile = _hexToBytes(json['seed'] as String?);
    if (outFile == null) return false;
    final outBundle = KeyringService.instance.load('master_seed');
    if (outBundle == null) return false;
    return _equal(outFile, outBundle);
  }

  static bool _phraseStandsInKeyring(Map<String, dynamic> json) {
    if (!KeyringService.isInitialized) return false;
    final words = (json['words'] as List<dynamic>?)?.cast<String>();
    if (words == null || words.isEmpty) return false;
    final outBundle = KeyringService.instance.load('seed_phrase');
    if (outBundle == null) return false;
    return String.fromCharCodes(outBundle) == words.join(' ');
  }

  /// The identity profile directories of **this** profile.
  ///
  /// `identities.json` is read via [IdentityManager] — the same source
  /// from which the rest of the start obtains them. If that fails, it
  /// falls back to `identities/*`: a cleaner that does NOT find the
  /// directories would otherwise report "hangs on nothing", although it
  /// only did not look.
  ///
  /// ── WHY FILTERING HAPPENS HERE (S370, finding W-4) ──────────────────
  ///
  /// `profileDir` stands in `identities.json` **absolute**
  /// (`identity_manager.dart:71`). On a taken-over, copied or moved
  /// profile this path points elsewhere; on the Windows machine, measured
  /// on 05.09.2026, there stood
  ///
  ///     "profileDir":"C:\\Users\\Cleona\\.cleona/identities/identity-1"
  ///
  /// while `purge` ran with a different `baseDir`. The cleaner then read a
  /// file OUTSIDE its subject, found it readable under the legacy key and
  /// reported "still hangs on it".
  ///
  /// The tipping point was measured: `purge(BASIS)` returned `stillUsed`
  /// as long as the foreign file existed, and `removed` after ONLY it had
  /// been deleted — in `BASIS` not a byte had changed. A verdict that
  /// hangs on a file outside its subject is none. That is why every path
  /// that after normalisation does not lie under [baseDir] drops out here,
  /// and it drops out LOUDLY.
  ///
  /// **Side effect, explicitly:** a profile whose identity directories
  /// deliberately lie outside `baseDir` is no longer checked — the cleaner
  /// could delete a key still in use there. This layout produces nothing
  /// in the tree: the only producers of `profileDir` build
  /// `'$baseDir/identities/<id>'` (`identity_manager.dart:823`, `:892`),
  /// and the only later writer explicitly puts it back AGAIN under the
  /// current base path (`main.dart:2104-2117`, "Rebasing
  /// profileDir"). It only comes from outside from foreign holdings —
  /// and exactly that is the finding.
  static List<String> _profileDirectories(String baseDir) {
    final sep = Platform.pathSeparator;
    final log = _logFor(baseDir);
    final out = <String>{};
    try {
      for (final i in IdentityManager(baseDir: baseDir).loadIdentities()) {
        if (!_restsUnder(i.profileDir, baseDir)) {
          log.warn('identities.json lists "${i.profileDir}" — this path '
              'is NOT under "$baseDir" and is NOT checked. The '
              'entry comes from a foreign or relocated store; '
              'a verdict on this cleanup run must not depend on a '
              'file outside its profile (S370, W-4).');
          continue;
        }
        out.add(i.profileDir);
      }
    } catch (e) {
      log.warn('identities.json not readable ($e) — looking via the '
          'directory instead');
    }
    final under = Directory('$baseDir${sep}identities');
    if (under.existsSync()) {
      try {
        for (final e in under.listSync(followLinks: false)) {
          if (e is Directory) out.add(e.path);
        }
      } catch (_) {/* unreadable: the path above has already tried it */}
    }
    return out.toList();
  }

  /// Comparison form of a path: absolute, without `.`/`..` detours, and
  /// on Windows case- and separator-neutral.
  ///
  /// Windows needs both: NTFS is case-INsensitive, `String.==` is not, and
  /// in the tree both separators stand side by side — the line measured on
  /// the machine carried `\\` and `/` mixed in ONE path. On POSIX the
  /// spelling stays untouched: there `A` and `a` are different
  /// directories, and equating them would itself be an error.
  static String _comparisonForm(String path) {
    var n = p.normalize(p.absolute(path));
    if (Platform.isWindows) n = n.replaceAll('\\', '/').toLowerCase();
    return n;
  }

  /// Does [kind] really lie below [parents]?
  ///
  /// `baseDir` itself does NOT count as an identity directory — otherwise
  /// the cleaner would check the files at the profile root a second time
  /// under a false name.
  static bool _restsUnder(String kind, String parents) {
    if (kind.isEmpty) return false;
    final k = _comparisonForm(kind);
    final e = _comparisonForm(parents);
    if (k == e) return false;
    final sep = Platform.isWindows ? '/' : Platform.pathSeparator;
    final prefix = e.endsWith(sep) ? e : '$e$sep';
    return k.startsWith(prefix);
  }

  static Uint8List? _hexToBytes(String? hex) {
    if (hex == null || hex.isEmpty || hex.length.isOdd) return null;
    try {
      final b = Uint8List(hex.length ~/ 2);
      for (var i = 0; i < b.length; i++) {
        b[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      }
      return b;
    } catch (_) {
      return null;
    }
  }

  static bool _equal(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a[i] ^ b[i];
    }
    return d == 0;
  }
}
