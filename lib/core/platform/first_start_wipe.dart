import 'dart:convert';
import 'dart:io';

import 'package:cleona/core/crypto/keyring_service.dart';
import 'package:cleona/core/service/app_version.dart' show kAppLine;

/// FIRST START WITHOUT V4.1 MARK: THE PROFILE IS DELETED, NOT READ.
///
/// ── THE DECISION THIS FILE CARRIES ────────────────────────────
///
/// Owner decision of 03.09.2026, verbatim: "On 3 A, because a version
/// of 3.2.2 exists on GitHub. For the umpteenth time: 3.x has no place
/// in V4.1!" — that is **option A** from
/// `docs/v4-redesign/S363-VORLAGE-erststart-loeschpfad.md` section 9:
/// the first start without a V4.1 mark deletes the profile content
/// **completely** and creates an empty profile. Not the named
/// subset (option B), not the confirmation question (option C).
///
/// The decision expressly revokes the decision of 17.08.2026, by
/// which the V4.1 line deliberately continued to read V3 profiles
/// (`docs/MIGRATION_V3_TO_V4_0_MYZEL.md:5190-5194`, carrier
/// `lib/core/service/service_types.dart:195-253`). This takeover code
/// remains — it becomes moot through A, not wrong, and its
/// removal is not the subject of this decision.
///
/// ── THE SPEC ─────────────────────────────────────────────────────────
///
/// v4_1 §21.4 "Encryption of local data": "The first start creates a fresh
/// profile. Profile data found in the data directory that does not match
/// the format is deleted rather than read." And v4_1 §13.5.2 "Wipe before
/// recovery": "Before the seed is entered, any existing profile data is
/// deleted completely (first-start deletion rule, §21)."
///
/// **These are TWO call sites of the same building block, not one.**
/// [runFirstStartWipe] decides itself (mark check, once,
/// without the user's involvement). [wipeBeforeRecovery] does not decide — it
/// deletes because the user expressly triggered it, without
/// mark check and without once-only. Merging them into one function
/// is the path by which a user action becomes a
/// silent start operation.
///
/// ── TWO MARKS, NOT ONE ABSENCE ────────────────────────────
///
/// A marker that speaks only through ABSENCE is the trap from
/// section 4.3 of the proposal: a profile created by a V4.1 state BEFORE
/// introduction of the marker would not have it — and would be deleted as a
/// foreign format on the next update. The path would then fire
/// from V4.1 to V4.1, with complete data loss.
///
/// That is why there are two POSITIVE marks, and one suffices:
///   1. [markerFilename] — the explicit marker of this file.
///   2. [nodeKeysFilename] — `node_keys.enc`, written by
///      `lib/core/link/node_keys.dart` on the first start of every V4.1
///      state. No V3 state ever wrote this file.
///
/// The second mark carries the states that existed before the marker; the
/// first carries the states in which the node never started (then
/// `node_keys.enc` is missing). Checking both costs two `existsSync()`.
///
/// ── CORRECTION (S368, 05.09.2026) ──────────────────────────────────
///
/// Until today this said the first mark carries "the states in which
/// only the UI ran". **On the daemon platforms that was never
/// true.** Until S368 the marker was written exclusively by
/// [runFirstStartWipe] and [wipeBeforeRecovery] themselves, and the only
/// path to the first of the two is `IdentityContext.initCrypto`
/// (`identity_context.dart:341`) — which on Linux and Windows runs ONLY in the
/// daemon; the UI expressly skips it
/// (`main.dart:157-170`, "daemon owns keyring"). A state in which only
/// the UI ran thus had precisely NO marker. Exactly on that
/// the first start died: the UI created seed and identity, the
/// daemon found at the first `initCrypto` neither marker nor `node_keys.enc`,
/// but did find `identities.json` and `master_seed.json.enc` — and deleted
/// the just created identity together with the 24 words just displayed,
/// under the message "Profile from version 3.x removed".
///
/// The sentence has been true since S368, because the stamp has moved to where
/// it belongs: to the FIRST V4.1 WRITER of the profile directory.
/// `IdentityManager.generateSeedPhrase`, `createIdentity`,
/// `createIdentityAtIndex` and `restoreFromPhrase` call [writeMarker]
/// (justification there, `identity_manager.dart` `_stampV41Profile`).
/// Expressly NOT `saveIdentities` — that would also run on `setSkinId`
/// and would undermine the deletion path on a genuine 3.x profile.
///
/// **The time window is unique.** Measured on 03.09.2026: last
/// shipped state is `v3.2.2-beta`, no V4.1 build has ever been
/// shipped. Introducing the marker is free today; after
/// the first V4.1 release a set of markerless
/// V4.1 profiles already exists and the trap above is real.
///
/// ── WHAT IS EXPRESSLY NOT DELETED ───────────────────────────
///
/// `~/.cleona-daemon.lock` lies as a SIBLING of the profile directory,
/// not in it (`lib/service_daemon.dart:200-206`, v4_1 §22.1): the
/// machine-wide uniqueness lock must survive a wipe, otherwise
/// two daemons run. This file deletes exclusively ENTRIES
/// BELOW `baseDir` and never `baseDir` itself — the
/// sibling file is thus out of reach by construction, and
/// [wipeProfileData] additionally checks that (see [_assertPlausibleBaseDir]).
///
/// ── THE KEYRING (RB-4, S370) ──────────────────────────────────
///
/// **Until S370 the opposite stood here.** The header recorded that the
/// operating system's keyring lies outside the
/// profile directory and "survives the wipe" — and that was not
/// incidental, but a hole in exactly the separation this file
/// enforces. Measured on 06.09.2026 in a throwaway profile, with a
/// keyring outside `baseDir`:
///
///   BEFORE the wipe: hasMasterSeed()=true,
///                  loadMasterSeed()=a0a1…bebf (the V3 seed)
///   AFTER  the wipe: hasMasterSeed()=true,
///                  loadMasterSeed()=a0a1…bebf — BYTE-IDENTICAL the same
///
/// The V3 seed thus survived the deletion path completely, because
/// `identity_manager.dart:198-201`/`:210-213` reads the keyring FIRST. A
/// surviving V3 seed is a compatibility path; the decisions
/// (repeated six times, most recently 03.09.2026 on option A) know none.
///
/// **Where the keyring lies — measured, not assumed:**
///
///   INSIDE `baseDir` (the wipe always took them along):
///     `.<name>.keyring` + `.keyring_salt`  (file fallback,
///        `keyring_service.dart:438`/`:461`) — that is the path on every
///        Linux installation WITHOUT `secret-tool`
///     `<name>.dpapi`                       (Windows, `:296`)
///   OUTSIDE `baseDir` (stayed behind):
///     GNOME Keyring/KWallet via `secret-tool` (`:202-281`)
///     macOS Keychain via `security` (`:970-1037`)
///     Android EncryptedSharedPreferences / iOS Keychain
///        (`keyring_mobile.dart`)
///
/// That is why since S370 the first-start wipe has TWO halves, not one:
/// [wipeProfileData] clears the disk, [wipeKeyringSecrets] clears the
/// keyring. The second half cannot stand in [runFirstStartWipe]: the
/// deletion path runs BEFORE `KeyringService.init`, and deliberately so
/// (`identity_context.dart`, D3 in the guard) — at this time there is
/// no backend yet that one could have delete. It hangs one line
/// later, immediately after the keyring initialisation and BEFORE
/// `KeyMigration.migrateIfNeeded`.
///
/// **It fires ONLY if something was really deleted** — i.e. only if
/// [runFirstStartWipe] returned a report. A freshly created
/// profile and a profile with a V4.1 mark keep their seed; a wipe
/// that always cleared the keyring would be worse than the finding it
/// closes (on Windows exactly this error was measured: the
/// daemon deleted the fresh identity 24 s after creation).
class FirstStartWipe {
  FirstStartWipe._();

  /// The explicit marker. Starts with a dot, so that it stands next to
  /// `.keyring_migrated` and `.db_migrated` — the same construction that
  /// `KeyMigration` has kept proven since S106.
  static const String markerFilename = '.v41_profile';

  /// The second, older marker — `node_keys.enc` in the profile root
  /// directory (`lib/core/link/node_keys.dart`, `filenameStem`).
  static const String nodeKeysFilename = 'node_keys.enc';

  /// The note for the UI. It arises AFTER the wipe (it lies
  /// itself in `baseDir`) and is read by the UI and afterwards
  /// thrown away.
  static const String noticeFilename = '.v41_wipe_notice.json';

  /// Format identifier in the marker: the LINE that wrote the marker.
  /// Deliberately a string and not a number — a later state can
  /// read and distinguish it.
  ///
  /// S368 — HERE `'4.1'` STOOD AS A LITERAL, and `app_version.dart` claimed
  /// in the same tree that this marker is DERIVED from `kAppLine`. Two
  /// statements about the same thing, and the documentation was the wrong one. On 4.2
  /// the marker would have continued to write `4.1` — the same construction as
  /// "(Architecture v3.0)" in the settings screen, only with a number that
  /// happens to be right today.
  ///
  /// Now derived, and that is behaviour-neutral: `writeMarker` is a
  /// no-op as soon as the file stands, so no existing marker is
  /// rewritten; and `hasMarker` checks solely the EXISTENCE of the file,
  /// not its content. No reader in `lib/` evaluates the field — it is
  /// a provenance statement for a later state, and as such the
  /// writing line is exactly the right information.
  static final String markerFormat = kAppLine;

  // ── Merkmalspruefung ────────────────────────────────────────────────

  static bool hasMarker(String baseDir) =>
      File('$baseDir${Platform.pathSeparator}$markerFilename').existsSync();

  static bool hasNodeKeys(String baseDir) =>
      File('$baseDir${Platform.pathSeparator}$nodeKeysFilename').existsSync();

  /// Does the directory carry a V4.1 marker? One suffices (see header).
  static bool isV41Profile(String baseDir) =>
      hasMarker(baseDir) || hasNodeKeys(baseDir);

  /// Files at the profile root directory whose mere existence proves an
  /// EXISTING profile.
  ///
  /// **Why a positive list is admissible here, although section 3.6
  /// of the proposal warns against name lists.** There it was about the DELETION SET
  /// (`_wipeLocalIdentityData:154`): what is missing from the list stays
  /// behind — the list ages in the harmful direction. Here
  /// the list only decides WHETHER deletion happens; the deletion set itself
  /// is "everything below baseDir" and needs no names. What is missing from
  /// this list leads to "not deleted" — the harmless
  /// direction. Data loss cannot arise from it.
  static const List<String> baseEvidenceFiles = <String>[
    // Identity management. BOTH versions stand here: the plaintext
    // names prove a profile from the time before S368, the `.enc` names the
    // current one. The list only decides WHETHER deletion happens — a
    // missing name leads to "not deleted", i.e. in the harmless
    // direction (see the paragraph above this list). Exactly that is why
    // it must GROW ALONG on the switch to a ciphertext: otherwise an
    // existing V4.1 profile that only carries `identities.json.enc`
    // would no longer be recognised as "existing".
    'identities.json',
    'identities.json.enc',
    'last_profile.json',
    'last_profile.json.enc',
    // Seed and phrase, all four storage paths
    'master_seed.json',
    'master_seed.json.enc',
    'seed_phrase.json',
    'seed_phrase.json.enc',
    '.master_seed.keyring',
    '.seed_phrase.keyring',
    'master_seed.dpapi',
    'seed_phrase.dpapi',
    // Schluesselmaterial
    'db.key',
    '.db.key.migrated',
    'device_keys.bin.enc',
    'keys.json.enc',
    // V3 orphaned holdings in the root directory (proposal 3.2)
    'confirmed_peers.json',
    'dv_routing.json',
    'peer_messages.json',
    'routing_table.json',
    'peer_history.json',
    'prekeys.json',
    'sessions.json',
    'cleona.db',
    'guardian_shares.json',
    'guardian_shares.json.enc',
    'guardian_list.json',
    'guardian_list.json.enc',
  ];

  /// Files that identify a directory as a PROFILE DIRECTORY — for
  /// the named layout (`~/.cleona/Bootstrap/`) and for the entries
  /// under `identities/` (proposal 3.1, all three layouts).
  static const List<String> profileDirEvidenceFiles = <String>[
    'keys.json',
    'keys.json.enc',
    'contacts.json',
    'contacts.json.enc',
    'conversations.json',
    'conversations.json.enc',
    'prekeys.json',
    'cleona.db',
    'cleona.db.enc',
    'sessions.json',
    'peer_history.json',
    'routing_table.json',
  ];

  /// Entries the wipe leaves standing, because they are NOT profile data
  /// but the guard files of the process that is currently running.
  ///
  /// ── THE FINDING (S368, 05.09.2026) ───────────────────────────────────
  ///
  /// The wipe runs in the DAEMON (`service_daemon.dart:507` →
  /// [runFirstStartWipe]) — and at this time the same
  /// process already holds both files: `cleona.lock` since
  /// `service_daemon.dart:151` (guard 1, `flock` LOCK_EX), `cleona.pid`
  /// since `:244` (guard 0). Both arise BEFORE `startAll()`, the wipe
  /// thus caught them too.
  ///
  /// The consequence is not cosmetic, it costs the SECOND attempt:
  /// the UI reads `cleona.lock`/`cleona.pid` (`main.dart:1460`,
  /// `:1477`), finds nothing, considers the daemon dead and starts a
  /// second one — which fails at the machine-wide lock
  /// `~/.cleona-daemon.lock` (which survives the wipe, see header) and
  /// ends with exit 1. Only the third attempt runs.
  ///
  /// Weightier is the uniqueness guarantee itself: `service_daemon
  /// .dart:148` expressly warns "never delete cleona.lock externally
  /// — the flock is inode-based; deleting the file lets a second process
  /// create a new inode and acquire its own lock, defeating the guard."
  /// Exactly that is what this building block did.
  ///
  /// **This does not only hit the first start.** On the genuine transition
  /// 3.x → 4.1 the wipe rightfully deletes a legacy profile — and until today
  /// took the guard files of the running daemon along. Every
  /// existing user was affected, not only the first start.
  ///
  /// ── WHY A NAME LIST IS DEFENSIBLE HERE ──────────────────────
  ///
  /// It ages in the HARMFUL direction: what is missing from it is
  /// deleted; what becomes outdated on it protects a name that no longer
  /// exists, and thereby claims a protection nobody
  /// needs any more. That is why an **outdatedness test** hangs on it
  /// (`test/smoke/smoke_first_start_gui_reihenfolge.dart`, part V): every
  /// name here must have a WRITER in the daemon and a READER in the UI.
  /// If either of the two falls away, the test turns red,
  /// instead of the entry silently remaining.
  ///
  /// ── WHAT IS EXPRESSLY NOT ON IT ──────────────────────────────
  ///
  /// `cleona.sock` (Linux/macOS) and `cleona.port` (Windows) do NOT exist
  /// at the time of the first-start wipe: the daemon clears them away in
  /// `run()` as legacy stock (`service_daemon.dart:249-287`) and only creates
  /// them in `_startAllInner` (`:847`), i.e. after `initCrypto`.
  /// Measured 05.09.2026 against the real daemon: the deletion report of the
  /// first start lists `cleona.pid` and `cleona.lock`, neither of the other
  /// two. For the recovery path the
  /// 30-second guard `_socketWatchdog` (`:978-989`) additionally covers an externally
  /// deleted socket.
  static const List<String> preservedEntries = <String>[
    'cleona.lock',
    'cleona.pid',
  ];

  /// Directories that are NEVER a profile directory — they carry
  /// caches, not identity. Without this exception a
  /// freshly installed state that has only created `logs/` would have counted as
  /// "profile present".
  static const List<String> nonProfileDirs = <String>[
    'logs',
    'models',
    'update',
    'binary-updates',
    'media',
    'mailbox',
  ];

  /// Is there any evidence of an EXISTING profile? Checks all
  /// three layouts from section 3.1 of the proposal:
  ///   1. the base directory itself,
  ///   2. named directories directly below it (`Bootstrap/`, `gui1/`),
  ///   3. `identities/<id>/`.
  static bool hasLegacyProfileEvidence(String baseDir) =>
      legacyProfileEvidence(baseDir).isNotEmpty;

  /// Like [hasLegacyProfileEvidence], but returns the evidence — the
  /// guard thus measures the STATEMENT and not only its result.
  static List<String> legacyProfileEvidence(String baseDir) {
    final sep = Platform.pathSeparator;
    final found = <String>[];
    final dir = Directory(baseDir);
    if (!dir.existsSync()) return found;

    for (final name in baseEvidenceFiles) {
      if (File('$baseDir$sep$name').existsSync()) found.add(name);
    }

    List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } catch (_) {
      return found;
    }
    for (final entry in entries) {
      if (entry is! Directory) continue;
      final name = entry.path.split(sep).last;
      if (nonProfileDirs.contains(name)) continue;
      if (name == 'identities') {
        // Layout 3: every subdirectory is a profile directory.
        try {
          for (final sub in entry.listSync(followLinks: false)) {
            if (sub is! Directory) continue;
            if (_looksLikeProfileDir(sub.path)) {
              found.add('identities$sep${sub.path.split(sep).last}');
            }
          }
        } catch (_) {/* an unreadable directory is no evidence */}
        continue;
      }
      // Layout 2: named profile directory directly below the base.
      if (_looksLikeProfileDir(entry.path)) found.add(name);
    }
    return found;
  }

  static bool _looksLikeProfileDir(String path) {
    final sep = Platform.pathSeparator;
    for (final name in profileDirEvidenceFiles) {
      if (File('$path$sep$name').existsSync()) return true;
    }
    return false;
  }

  // ── Call site 1: the first start (§21.4) ───────────────────────────

  /// Decides and deletes. Returns the report if something was deleted,
  /// otherwise `null`.
  ///
  /// The formula (proposal 4.3), written out:
  ///
  ///   V4.1 mark present           -> V4.1 on V4.1, nothing to do
  ///   no mark, no evidence        -> genuine fresh start, nothing to delete
  ///   no mark, but evidence       -> DELETION PATH
  ///
  /// In all three cases the marker stands at the end — even if nothing
  /// was deleted. Without that, the genuine fresh start would have no marker at the SECOND
  /// start and (then with profile content) would have triggered the deletion path.
  static WipeReport? runFirstStartWipe(String baseDir) {
    if (isV41Profile(baseDir)) {
      writeMarker(baseDir);
      return null;
    }
    final evidence = legacyProfileEvidence(baseDir);
    if (evidence.isEmpty) {
      writeMarker(baseDir);
      return null;
    }
    final report = wipeProfileData(baseDir, WipeReason.firstStart, evidence);
    writeMarker(baseDir);
    writeNotice(baseDir, report);
    return report;
  }

  // ── Call site 2: before recovery (§13.5.2) ─────────────

  /// Deletes because the user triggered it — without mark check,
  /// without once-only, without a note for the UI (the UI
  /// is with the user at this moment and tells him itself).
  ///
  /// v4_1 §13.5.2: "Before the seed is entered, any existing profile data
  /// is deleted completely (first-start deletion rule, §21)." The marker
  /// is set afterwards: what arises here is a V4.1 profile.
  static WipeReport wipeBeforeRecovery(String baseDir,
      {KeyringService? keyring}) {
    final report = wipeProfileData(
        baseDir, WipeReason.recovery, legacyProfileEvidence(baseDir));
    // §13.5.2 says "deleted completely". The keyring belongs to that — the
    // caller passes it in, because this layer must not build it
    // itself (in the first start it runs BEFORE its initialisation).
    //
    // `null` is a REGULAR case here and not an oversight: on Linux and
    // Windows the DAEMON owns the keyring, the UI runs without
    // `initCrypto` (`main.dart:157-172`), and `KeyringService.instance`
    // would throw there. On these two platforms the old entry is
    // overwritten instead: `restoreFromPhrase` stores the NEW seed,
    // and the next daemon start pulls it via
    // `KeyMigration.migrateIfNeeded` into the keyring (`.keyring_migrated`
    // fell with the wipe, so the migration runs again).
    if (keyring != null) wipeKeyringSecrets(keyring, baseDir, report: report);
    writeMarker(baseDir);
    return report;
  }

  // ── The second half of the wipe: the keyring ────────────────

  /// The names the keyring carries — measured, not chosen:
  /// `master_seed` and `seed_phrase` are the only `store()` calls
  /// in the whole tree (`identity_manager.dart:262`/`:280`,
  /// `key_migration.dart:396`/`:407`).
  static const List<String> keyringSecretNames = <String>[
    'master_seed',
    'seed_phrase',
  ];

  /// Deletes the entries of the keyring. Returns what is really
  /// gone.
  ///
  /// **Only to be called if something was actually deleted** — the caller
  /// checks that on the report from [runFirstStartWipe]. The third direction
  /// of the guard (a freshly created profile KEEPS its seed)
  /// hangs exactly on this condition.
  ///
  /// A `false` from [KeyringService.delete] is not an error: on the
  /// file fallback and on Windows the containers lay INSIDE
  /// `baseDir` and have already fallen by [wipeProfileData] at this point.
  /// That is why it is counted, not claimed.
  ///
  /// [report] is optional: if it is present, the note for the
  /// UI is rewritten, so that the message does not name less
  /// than has happened.
  static List<String> wipeKeyringSecrets(KeyringService keyring, String baseDir,
      {WipeReport? report}) {
    final removed = <String>[];
    for (final name in keyringSecretNames) {
      try {
        if (keyring.delete(name)) removed.add(name);
      } catch (e) {
        // A backend that throws on deletion must not abort the start
        // — but it must not stay silent either.
        stderr.writeln('[FirstStartWipe] keyring delete "$name" failed: $e');
      }
    }
    stderr.writeln('[FirstStartWipe] keyring: ${removed.length} of '
        '${keyringSecretNames.length} entries deleted '
        '(${removed.isEmpty ? "none" : removed.join(",")})');
    if (report != null && removed.isNotEmpty) {
      writeNotice(baseDir, report.withKeyringSecrets(removed));
    }
    return removed;
  }

  // ── Der Baustein ────────────────────────────────────────────────────

  /// Deletes EVERY entry below [baseDir]. `baseDir` itself
  /// stays (open descriptors of the running process, and the
  /// caller creates things in it right away).
  ///
  /// **Except the guard files of the running process** — see
  /// [preservedEntries]. They are not profile data.
  ///
  /// **Every entry has its own try/catch.** On Windows
  /// `deleteSync` fails on an open file (sharing violation). A
  /// propagating exception would abort the start; instead
  /// the entry stands in the report under [WipeReport.failed].
  ///
  /// S368: until today `cleona.lock` was the main case of this sentence — the
  /// daemon holds it open at the time of the wipe
  /// (`lib/service_daemon.dart:151-167`, acquired BEFORE `initCrypto`), so
  /// on Windows it stayed behind through the sharing violation and stood
  /// as [WipeReport.failed] in the report. That was not protection but a
  /// coincidence with two defects: it only applied on Windows (on Linux
  /// `unlink` also removes an open, `flock`ed file — measured
  /// 05.09.2026, `deleted: [cleona.pid, cleona.lock, …]`), and it did
  /// not apply to `cleona.pid`, which the daemon does NOT keep open. Since
  /// [preservedEntries] the result is the same on both platforms
  /// and stands as [WipeReport.preserved] in the report — "was not allowed"
  /// instead of "did not work".
  static WipeReport wipeProfileData(
      String baseDir, WipeReason reason, List<String> evidence) {
    _assertPlausibleBaseDir(baseDir);
    final dir = Directory(baseDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
      return WipeReport(
          reason: reason, deleted: const [], failed: const [], bytes: 0,
          evidence: evidence, when: DateTime.now());
    }

    final deleted = <String>[];
    final failed = <String>[];
    final preserved = <String>[];
    var bytes = 0;

    List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } catch (e) {
      stderr.writeln('[FirstStartWipe] cannot list $baseDir: $e');
      return WipeReport(
          reason: reason, deleted: const [], failed: const [], bytes: 0,
          evidence: evidence, when: DateTime.now());
    }

    for (final entry in entries) {
      final name = entry.path.split(Platform.pathSeparator).last;
      // Guard files of the running process — justification and
      // outdatedness test at [preservedEntries].
      if (preservedEntries.contains(name)) {
        preserved.add(name);
        continue;
      }
      final size = _sizeOf(entry);
      try {
        if (entry is Directory) {
          entry.deleteSync(recursive: true);
        } else {
          entry.deleteSync();
        }
        deleted.add(name);
        bytes += size;
      } catch (e) {
        failed.add(name);
        stderr.writeln('[FirstStartWipe] could not delete $name: $e');
      }
    }

    stderr.writeln('[FirstStartWipe] ${reason.name}: '
        '${deleted.length} entries deleted, ${failed.length} failed, '
        '${preserved.length} preserved (${preserved.join(",")}), '
        '$bytes bytes, evidence=${evidence.join(",")}');
    return WipeReport(
        reason: reason, deleted: deleted, failed: failed, bytes: bytes,
        preserved: preserved, evidence: evidence, when: DateTime.now());
  }

  /// Gate against the mistake that costs everything: a `baseDir` that is
  /// the user directory itself or a file system root.
  /// Throws instead of deleting.
  static void _assertPlausibleBaseDir(String baseDir) {
    final trimmed = baseDir.replaceAll(RegExp(r'[/\\]+$'), '');
    if (trimmed.isEmpty) {
      throw ArgumentError('FirstStartWipe: refusing to wipe an empty path');
    }
    final segments = trimmed
        .split(RegExp(r'[/\\]'))
        .where((s) => s.isNotEmpty && s != '.')
        .toList();
    if (segments.length < 2) {
      throw ArgumentError(
          'FirstStartWipe: refusing to wipe "$baseDir" — too close to the root');
    }
    if (segments.contains('..')) {
      throw ArgumentError(
          'FirstStartWipe: refusing to wipe "$baseDir" — path contains ".."');
    }
  }

  static int _sizeOf(FileSystemEntity entity) {
    try {
      if (entity is File) return entity.lengthSync();
      if (entity is Directory) {
        var total = 0;
        for (final e in entity.listSync(recursive: true, followLinks: false)) {
          if (e is File) {
            try {
              total += e.lengthSync();
            } catch (_) {/* disappeared while counting */}
          }
        }
        return total;
      }
    } catch (_) {/* size is incidental, never a reason to fail */}
    return 0;
  }

  // ── Marker ──────────────────────────────────────────────────────────

  /// Sets the marker if it is missing. Repeatable, a no-op as soon as it
  /// stands — it carries the time of its FIRST writing.
  static void writeMarker(String baseDir) {
    final file = File('$baseDir${Platform.pathSeparator}$markerFilename');
    if (file.existsSync()) return;
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(<String, Object>{
        'format': markerFormat,
        'createdAt': DateTime.now().toIso8601String(),
      }));
    } catch (e) {
      stderr.writeln('[FirstStartWipe] could not write marker: $e');
    }
  }

  // ── Note for the UI ─────────────────────────────────────

  /// On Linux and Windows the DAEMON deletes
  /// (`lib/service_daemon.dart:507`), the UI is a different
  /// process and runs without `initCrypto` (`lib/main.dart:176-198` — the
  /// UI there has brought up the keyring since S368, but
  /// expressly NOT the start sequence). The
  /// note is the bridge: a file in `baseDir` that both processes
  /// see.
  static void writeNotice(String baseDir, WipeReport report) {
    try {
      File('$baseDir${Platform.pathSeparator}$noticeFilename')
          .writeAsStringSync(jsonEncode(report.toJson()));
    } catch (e) {
      stderr.writeln('[FirstStartWipe] could not write notice: $e');
    }
  }

  static WipeReport? readNotice(String baseDir) {
    try {
      final file = File('$baseDir${Platform.pathSeparator}$noticeFilename');
      if (!file.existsSync()) return null;
      final json = jsonDecode(file.readAsStringSync());
      if (json is! Map<String, dynamic>) return null;
      return WipeReport.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  static void clearNotice(String baseDir) {
    try {
      final file = File('$baseDir${Platform.pathSeparator}$noticeFilename');
      if (file.existsSync()) file.deleteSync();
    } catch (_) {/* the note is incidental */}
  }
}

/// Why a wipe ran. The two values are the two call sites —
/// §21.4 (first start, the application decides) and §13.5.2
/// (recovery, the user decides).
enum WipeReason {
  firstStart,
  recovery;

  static WipeReason fromName(String? name) => WipeReason.values.firstWhere(
      (r) => r.name == name,
      orElse: () => WipeReason.firstStart);
}

/// What a wipe did. Carries the numbers for the message to the
/// user — the numbers need no translation, the text does.
class WipeReport {
  final WipeReason reason;

  /// Names of the deleted top-level entries.
  final List<String> deleted;

  /// Names that could NOT be deleted (Windows: open file).
  final List<String> failed;

  /// Sum of the file sizes below the deleted entries.
  final int bytes;

  /// Names that DELIBERATELY remained — the guard files of the
  /// running process ([FirstStartWipe.preservedEntries]). Kept separate
  /// from [failed]: "not deleted because it did not work" and
  /// "not deleted because it was not allowed" are two different
  /// statements, and only the first is a finding.
  final List<String> preserved;

  /// The evidence that triggered the deletion path.
  final List<String> evidence;

  /// Names deleted from the KEYRING (RB-4, S370) —
  /// the part of the wipe that takes place outside `baseDir` and
  /// therefore does not appear in [deleted].
  final List<String> keyringSecrets;

  final DateTime when;

  const WipeReport({
    required this.reason,
    required this.deleted,
    required this.failed,
    required this.bytes,
    required this.evidence,
    required this.when,
    this.preserved = const <String>[],
    this.keyringSecrets = const <String>[],
  });

  /// The same report with keyring entries added. The keyring falls
  /// one line later than the disk (it does not yet exist on the deletion path),
  /// and the note for the UI should nonetheless name both.
  WipeReport withKeyringSecrets(List<String> secrets) => WipeReport(
        reason: reason,
        deleted: deleted,
        failed: failed,
        bytes: bytes,
        evidence: evidence,
        when: when,
        keyringSecrets: secrets,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'reason': reason.name,
        'deleted': deleted,
        'failed': failed,
        'preserved': preserved,
        'bytes': bytes,
        'evidence': evidence,
        'keyringSecrets': keyringSecrets,
        'when': when.toIso8601String(),
      };

  static WipeReport fromJson(Map<String, dynamic> json) => WipeReport(
        reason: WipeReason.fromName(json['reason'] as String?),
        deleted: (json['deleted'] as List<dynamic>? ?? const [])
            .map((e) => '$e')
            .toList(),
        failed: (json['failed'] as List<dynamic>? ?? const [])
            .map((e) => '$e')
            .toList(),
        preserved: (json['preserved'] as List<dynamic>? ?? const [])
            .map((e) => '$e')
            .toList(),
        bytes: (json['bytes'] as num?)?.toInt() ?? 0,
        evidence: (json['evidence'] as List<dynamic>? ?? const [])
            .map((e) => '$e')
            .toList(),
        keyringSecrets: (json['keyringSecrets'] as List<dynamic>? ?? const [])
            .map((e) => '$e')
            .toList(),
        when: DateTime.tryParse('${json['when']}') ?? DateTime.now(),
      );

  /// A line without translation needs: numbers and units.
  String get technicalSummary {
    final mb = bytes / (1024 * 1024);
    final size = mb >= 1024
        ? '${(mb / 1024).toStringAsFixed(1)} GB'
        : mb >= 1
            ? '${mb.toStringAsFixed(1)} MB'
            : '$bytes B';
    final base = '${deleted.length} · $size';
    return failed.isEmpty ? base : '$base · ${failed.length} !';
  }
}
