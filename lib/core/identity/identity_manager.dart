import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/identity/identity_context.dart';
import 'package:cleona/core/storage/message_store.dart';
import 'package:cleona/core/crypto/hd_wallet.dart';
import 'package:cleona/core/crypto/keyring_service.dart';
import 'package:cleona/core/crypto/pq_isolate.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/crypto/seed_phrase.dart';
import 'package:cleona/core/platform/app_paths.dart';
import 'package:cleona/core/log/log_redaction.dart';
import 'package:cleona/core/platform/first_start_wipe.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/link/data_port.dart';

/// Thrown when identities.json is corrupt but identity directories exist on
/// disk — distinct from an empty-but-valid list (e.g. after last delete).
class IdentitiesFileCorruptException implements Exception {
  IdentitiesFileCorruptException(this.message);
  final String message;
  @override
  String toString() => 'IdentitiesFileCorruptException: $message';
}

/// Represents a single identity profile.
class Identity {
  final String id;

  /// The own display name. On 06.09.2026 it stood in plaintext at four
  /// log places (`service_daemon.dart:781`, `:1052`, `:1117`,
  /// `identity_context.dart:545`) and additionally in the ring buffer,
  /// which goes via the crash report (§9.5.8) into the bug log to THIRD
  /// parties. Registration in the constructor AND in the setter —
  /// otherwise it would be back after a rename.
  String _displayName;
  String get displayName => _displayName;
  set displayName(String v) {
    _displayName = v;
    LogRedaction.registerName(v);
  }

  String profileDir;
  int port;
  final DateTime createdAt;
  String? nodeIdHex;
  /// HD-Wallet derivation index (null for legacy random-key identities).
  int? hdIndex;
  /// Visual skin id (null = default 'teal').
  String? skinId;
  /// Self-declaration: user claims to be 18+ (default false).
  bool isAdult;
  /// Opt-in: participate in channel moderation jury (only visible if isAdult).
  bool reviewEnabled;
  /// §7.1.3 (P2): true iff this identity was created via seed-phrase restore
  /// AND the user told the restore screen they still have another device
  /// running with this identity ("additional device", not "device
  /// replacement"). Gates `IdentityPublisher._isPrimaryDevice` — while this
  /// is true, the device does not publish an AuthManifest (it would collide
  /// with the still-running original device under the single `SHA-256("auth"
  /// + userId)` DHT slot). Cleared implicitly once the device pairs and
  /// becomes `isLinkedDevice`; always false for freshly-created identities
  /// (never set outside the restore flow).
  bool restoreAwaitingPairing;

  /// §13 (S382): true iff this identity came into existence via the
  /// recovery path — on a fresh installation the user did NOT create a
  /// new user, but entered his 24-word phrase.
  ///
  /// ── WHY THIS MARKER MUST EXIST ───────────────────────────────
  ///
  /// Until S382 `beginRecoveryBundleHarvestIfLost` asked a
  /// PROXY: "this identity has no contacts". That is just as true for a
  /// freshly created second identity as for a recovered one — the log
  /// line said so itself ("kein Kontakt bekannt, Seed liegt vor").
  /// Consequence, measured in the lab on 12.09.2026: EVERY second identity
  /// (AllyCat, Charly, WindowsTwo) fired a §13.3 search on EVERY attach —
  /// up to 120 runs of three requests, about 16 minutes of pressure on the
  /// control queue, for something that never existed. And because
  /// `beginHarvest` resets the counter on every attach, this repeated on
  /// every restart.
  ///
  /// ── WHY A FIELD OF ITS OWN AND NOT [restoreAwaitingPairing] ──────
  ///
  /// The two answer DIFFERENT questions, and merging them would mean
  /// making the same error once more — a field with two meanings is the
  /// next proxy.
  ///
  ///   [restoreAwaitingPairing]  "there is ANOTHER device under this
  ///                             phrase" -> device set change (§14.4),
  ///                             NOT a recovery case
  ///   [restoredFromPhrase]      "this identity came from the phrase"
  ///
  /// The RECOVERY CASE is the combination: created from the phrase AND no
  /// other device. Exactly then — and only then — must the data from the
  /// chats with contacts, groups and channels be fetched back. If there
  /// is another device, they come from there (§14.4), and the search
  /// would be wasted traffic.
  ///
  /// IS DELETED as soon as it has fulfilled its purpose — see
  /// `beginRecoveryBundleHarvestIfLost`. A marker that stands forever
  /// fires anew on every restart and would again be the old error.
  bool restoredFromPhrase;

  Identity({
    required this.id,
    required String displayName,
    required this.profileDir,
    required this.port,
    required this.createdAt,
    this.nodeIdHex,
    this.hdIndex,
    this.skinId,
    this.isAdult = false,
    this.reviewEnabled = true,
    this.restoreAwaitingPairing = false,
    this.restoredFromPhrase = false,
  }) : _displayName = displayName {
    LogRedaction.registerName(displayName);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'profileDir': profileDir,
        'port': port,
        'createdAt': createdAt.toIso8601String(),
        'nodeIdHex': nodeIdHex,
        if (hdIndex != null) 'hdIndex': hdIndex,
        if (skinId != null) 'skinId': skinId,
        if (isAdult) 'isAdult': true,
        if (!reviewEnabled) 'reviewEnabled': false,
        if (restoreAwaitingPairing) 'restoreAwaitingPairing': true,
        if (restoredFromPhrase) 'restoredFromPhrase': true,
      };

  static Identity fromJson(Map<String, dynamic> json) => Identity(
        id: json['id'] as String,
        displayName: json['displayName'] as String? ?? json['display_name'] as String? ?? '',
        profileDir: json['profileDir'] as String? ?? json['profile_dir'] as String? ?? '',
        port: json['port'] as int,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? json['created_at'] as String? ?? '') ?? DateTime.now(),
        nodeIdHex: json['nodeIdHex'] as String? ?? json['node_id_hex'] as String?,
        hdIndex: json['hdIndex'] as int?,
        skinId: json['skinId'] as String?,
        isAdult: json['isAdult'] as bool? ?? false,
        reviewEnabled: json['reviewEnabled'] as bool? ?? true,
        restoreAwaitingPairing: json['restoreAwaitingPairing'] as bool? ?? false,
        restoredFromPhrase: json['restoredFromPhrase'] as bool? ?? false,
      );
}

/// Manages multiple identity profiles.
/// All identities share a single daemon/node/port.
/// Supports HD-Wallet key derivation from a master seed.
class IdentityManager {
  final String baseDir; // ~/.cleona
  int _maxHdIndex = -1;

  // NOTE (AP-3a stage 1): `drawDataPort` and `browserUnsafePort` moved to
  // `DataPort` in lib/core/link/data_port.dart — the port a node binds is a
  // link-layer property. Moved completely, no delegate: a forwarding shim
  // would be a second access path (the AP-1b anti-pattern).

  /// Every port a browser refuses to open, as the **union** of the two lists
  /// that matter. An invitation link has to work in the recipient's browser,
  /// whichever that is, so the stricter union applies — not either list alone.
  ///
  /// Sources (checked 2026-08-17, both lists read in full, not from memory —
  /// the single-value claim above stood unsourced in five places until then):
  ///  * Chromium `net/base/port_util.cc`, `kRestrictedPorts`
  ///    <https://chromium.googlesource.com/chromium/src/+/refs/heads/main/net/base/port_util.cc>
  ///  * Firefox `netwerk/base/nsIOService.cpp`, `gBadPortList`
  ///    <https://searchfox.org/mozilla-central/source/netwerk/base/nsIOService.cpp>
  ///
  /// The lists are **not identical**: Firefox additionally blocks 4190
  /// (ManageSieve) and 6679; Chromium additionally blocks 0. 10080 (the
  /// Amanda backup port, blocked by both since 2021) is the only member
  /// at or above 10000 and therefore the only one [drawDataPort] can hit.
  ///
  /// **Why the full set is needed even though the draw can only hit 10080:**
  /// the invitation link does not carry the drawn port. It carries
  /// `publicPort` (`nat_traversal.dart`), which is either a UPnP-mapped port
  /// the *router* chose or a STUN-observed port a translating NAT assigned.
  /// Either can be any value in 1–65535, so the draw-side exclusion does not
  /// reach it. Chromium and Firefox both allow local overrides
  /// (`--explicitly-allowed-ports`, `network.security.ports.banned.override`);
  /// those are the recipient's setting and cannot be relied on.
  static const Set<int> browserBlockedPorts = {
    0, 1, 7, 9, 11, 13, 15, 17, 19, 20, 21, 22, 23, 25, 37, 42, 43, 53, 69,
    77, 79, 87, 95, 101, 102, 103, 104, 109, 110, 111, 113, 115, 117, 119,
    123, 135, 137, 139, 143, 161, 179, 389, 427, 465, 512, 513, 514, 515,
    526, 530, 531, 532, 540, 548, 554, 556, 563, 587, 601, 636, 989, 990,
    993, 995, 1719, 1720, 1723, 2049, 3659, 4045, 4190, 5060, 5061, 6000,
    6566, 6665, 6666, 6667, 6668, 6669, 6679, 6697, 10080,
  };

  /// True if [port] is one a browser refuses to open, so any HTTP link built
  /// on it is dead before a single packet leaves the recipient's machine.
  static bool isBrowserBlockedPort(int port) =>
      browserBlockedPorts.contains(port);

  IdentityManager({String? baseDir})
      : baseDir = baseDir ?? AppPaths.dataDir;

  /// The LOGICAL path. On disk lies `identities.json.enc` —
  /// [FileEncryption] appends the suffix itself, as everywhere else.
  String get _identitiesFile => '$baseDir/identities.json';
  // S368: here stood `_crimsonDismissedFlagFile`,
  // `crimsonMigrationShouldShow` and `dismissCrimsonBanner`. They found
  // identities with `skinId == 'crimson'` — an appearance that no longer
  // exists in `Skins.all` (measured: teal, ocean, sunset, forest,
  // amethyst, fire, storm, slate, gold, contrast) — and showed the user a
  // banner "is now Fire". An identity with this value can only stem from
  // a profile before the renaming; such profiles do not reach this
  // version. With the three members the marker
  // `crimson_migration_dismissed.flag` falls as well.

  // -- WHY THIS FILE NO LONGER LIES IN PLAINTEXT (S368) ----------
  //
  // Measured on a freshly created profile on 05.09.2026
  // (`/tmp/s368-frisch`, 284 B after one daemon run):
  //
  //     {"version":2,"maxHdIndex":0,"identities":[{"id":"identity-1",
  //      "displayName":"Alice",
  //      "profileDir":"/tmp/s368-frisch/identities/identity-1",
  //      "port":34260,"createdAt":"2026-09-05T19:14:01.819484",
  //      "nodeIdHex":"851ce1b88f5c89d4afed36fb1b77769adff0698575a70f0f0b
  //      ae2347eb8b1187","hdIndex":0}]}
  //
  // The name entered by the user stands next to `nodeIdHex` - the
  // identifier under which this device appears in the network (byte for
  // byte the same one that the creation run outputs as "Identity
  // User-ID"). Plus the data port, the creation time, the absolute
  // profile path (i.e. the login name), the number of identities held and
  // via `maxHdIndex` the number ever held. From a disk image alone this
  // pins the wire identifier onto a human.
  //
  // -- 4.5.3 JUSTIFIES THE PLACE, NOT THE PLAINTEXT ----------------
  //
  // The leading architecture document (`Cleona_Chat_Architecture_v4_1.md`;
  // read on 05.09.2026 on branch `v4/knoten-host`, l. 908-925 - the file
  // does not lie in THIS working tree) lists `identities.json` among the
  // files that "cannot move into a database because they hold what one
  // needs to open one". That is right and answers a DIFFERENT question:
  // the file carries the `hdIndex`, and `deriveFileEncKey(masterSeed,
  // hdIndex)` opens `messages.db`. So it could not lie IN the storage -
  // that would be a ring.
  //
  // WHAT THE SAME SECTION EXPLICITLY REQUIRES, and what the state found
  // VIOLATED: form 2 there reads "Structured
  // configuration state stays in **individually encrypted** JSON files
  // per identity (`FileEncryption`)" - and `identities.json` is one of
  // them. The plaintext was thus not a documented state but a violation
  // of the leading document. A change to it is therefore NOT necessary
  // for this work.
  //
  // But a ring exists only against the IDENTITY-BOUND key. The
  // device-wide `deriveSharedFileEncKey(masterSeed)` takes exactly one
  // argument, and that is the seed (`hd_wallet.dart:231-237`) - no
  // `hdIndex`, so no identity, so no list. And `loadMasterSeed()`
  // (`:209-247`) reads exclusively the keyring or a legacy storage;
  // `identities.json` does not occur in its body. The unlock chain is
  // thus straight, not circular:
  //
  //     keyring -> masterSeed -> deriveSharedFileEncKey
  //       -> identities.json.enc -> hdIndex
  //       -> deriveFileEncKey(seed, hdIndex) -> messages.db
  //
  // The same class as `device_keys.bin.enc`, `node_keys.enc` and the
  // entry stock, which all already lie under this key.
  //
  // NO MIGRATION. `FirstStartWipe` deletes a profile without the V4.1
  // marker at start; no plaintext is READ here in order to continue
  // writing it. That `FileEncryption.readJsonFile` has a generic
  // plaintext branch is behaviour of this class for ALL files and is not
  // specifically exploited here.

  /// The envelope for `identities.json` — device-wide (K2), derived from
  /// the master seed.
  ///
  /// `null` means: this profile has no master seed (yet). That is **not an
  /// operating case with identities**: `generateSeedPhrase()` or
  /// `restoreFromPhrase()` store the seed BEFORE `createIdentity` writes
  /// the file for the first time (`setup_screen.dart`,
  /// `scripts/init_profile.dart`, `guiOrder` in the guard). Before the
  /// seed the file does not exist, and then nothing is needed here.
  FileEncryption? _identitiesEnvelopeOrNull() {
    final seed = loadMasterSeed();
    if (seed == null) return null;
    return FileEncryption(
        baseDir: baseDir, key: HdWallet.deriveSharedFileEncKey(seed));
  }

  /// Does any version of the file lie on disk? Checked are the ciphertext
  /// and its two sidecars (aborted atomic write) as well as a plaintext
  /// version — that no longer arises in this state, but may still lie in
  /// a developer profile.
  bool get _identitiesFilePresent =>
      File('$_identitiesFile.enc').existsSync() ||
      File('$_identitiesFile.enc.tmp').existsSync() ||
      File('$_identitiesFile.enc.old').existsSync() ||
      File(_identitiesFile).existsSync();

  // ── THE STAMP BELONGS TO THE WRITER (S368) ─────────────────
  //
  // **The finding that forces this call.** Until 05.09.2026 the first
  // start deleted the identity it had JUST CREATED — on a machine that
  // never had a 3.x profile, with the message
  // "Profil aus Version 3.x entfernt" and 24 words just displayed, which
  // were thereby worthless. The sequence, deterministic, no race:
  //
  //   1. `setup_screen.dart:136-163` — the UI generates seed and
  //      identity. On Linux and Windows it runs WITHOUT
  //      `IdentityContext.initCrypto` (`main.dart:157-170`, "daemon owns
  //      keyring"), i.e. without the only call that until then could set
  //      the marker `.v41_profile`.
  //   2. `_ensureDaemonRunning()` starts the daemon.
  //   3. `service_daemon.dart:507` calls `initCrypto`, and its first
  //      line is `FirstStartWipe.runFirstStartWipe(baseDir)`.
  //   4. There lies neither the marker nor `node_keys.enc` — that is only
  //      written by `_startAllInner` (`service_daemon.dart:676`), i.e.
  //      AFTER the check. What is found instead are `identities.json`,
  //      `master_seed.json.enc`, `seed_phrase.json.enc` and `db.key`:
  //      four pieces of evidence from [FirstStartWipe.baseEvidenceFiles].
  //      The deletion path fires.
  //
  //   Measured 05.09.2026 against the REAL daemon:
  //   `[FirstStartWipe] firstStart: 9 entries deleted, 0 failed,
  //    54543 bytes, evidence=identities.json,last_profile.json,
  //    master_seed.json.enc,seed_phrase.json.enc,db.key`
  //   followed by `Keine Identitäten gefunden — warte auf GUI-Setup`.
  //
  // **Why the stamp stands HERE and not in `setup_screen`.** A call there
  // would be at the symptom: there is at least a second creation place
  // (`main.dart:3582`, `createAndSwitchIdentity`) and every future one.
  // The cause is that the FIRST V4.1 writer of the profile directory did
  // not stamp it. These four methods ARE this writer: they create
  // `master_seed.json(.enc)`, `seed_phrase.json(.enc)`, `db.key` and
  // `identities.json` — exactly the evidence by which the deletion path
  // recognises legacy holdings.
  //
  // **Explicitly NOT in [saveIdentities].** That method also runs on
  // `setSkinId`, `setActiveIdentity` and on port self-healing. On a REAL
  // 3.x profile it would set the marker before the daemon ever reaches
  // `initCrypto` — and thereby undermine the deletion path decided by the
  // owner on 03.09.2026. The deletion path stays unchanged; it is
  // intended.
  //
  // Idempotent: [FirstStartWipe.writeMarker] is a no-op as soon as the
  // marker stands, and carries the time of its FIRST write.
  void _stampV41Profile() => FirstStartWipe.writeMarker(baseDir);

  // ── Seed Phrase Management ──────────────────────────────────────

  /// Generate a new seed phrase and store the master seed encrypted.
  /// Returns the 24 words (user must back them up).
  List<String> generateSeedPhrase() {
    // First writer of the profile directory — see [_stampV41Profile].
    // Stands BEFORE the first write, so that the marker also lies there
    // if storing the seed fails: a half-written directory is not a 3.x
    // profile.
    _stampV41Profile();
    final words = SeedPhrase.generate();
    final entropy = SeedPhrase.wordsToEntropy(words);
    final masterSeed = SeedPhrase.entropyToSeed(entropy);
    _storeMasterSeed(masterSeed);
    _storeSeedPhrase(words);
    return words;
  }

  /// Restore from a 24-word phrase. Stores the derived master seed.
  /// Returns the master seed for key derivation.
  Uint8List restoreFromPhrase(List<String> words) {
    // First writer of the profile directory — see [_stampV41Profile].
    // On the recovery path [FirstStartWipe.wipeBeforeRecovery] has
    // already set the marker immediately before
    // (`setup_screen.dart:596`); the call is a no-op there. It stands
    // here for EVERY other caller of this method.
    _stampV41Profile();
    final entropy = SeedPhrase.wordsToEntropy(words); // validates checksum
    final masterSeed = SeedPhrase.entropyToSeed(entropy);
    _storeMasterSeed(masterSeed);
    _storeSeedPhrase(words);
    return masterSeed;
  }

  /// Check if a master seed exists (keyring or legacy file).
  bool hasMasterSeed() {
    if (KeyringService.isInitialized) {
      final seed = KeyringService.instance.load('master_seed');
      if (seed != null) return true;
    }
    // Legacy fallback: check for db.key-encrypted file
    return File('$baseDir/master_seed.json.enc').existsSync() ||
           File('$baseDir/master_seed.json').existsSync();
  }

  /// Load the master seed. Tries keyring first, falls back to legacy db.key.
  Uint8List? loadMasterSeed() {
    // §3.7: keyring is the primary source
    if (KeyringService.isInitialized) {
      final seed = KeyringService.instance.load('master_seed');
      if (seed != null) return seed;
    }
    // ── THE LEGACY HOLDINGS ARE ONLY READ ANY MORE (S368) ──────────────────
    //
    // Until S368 here stood "INTENT, NOT AN OVERSIGHT: `db.key` stays here"
    // with the reasoning that the seed cannot seal itself with a key
    // derived from it. The first half-sentence is right, the conclusion
    // was wrong: the place for the seed is not a file under a key that
    // lies openly next to it, but the KEYRING. That is how it was already
    // built under 3.2.2 (`maintenance/3.2:key_migration.dart:251-252`:
    // "master_seed is in keyring — remove .enc file"), and that is how it
    // is restored here.
    //
    // This line stays as a PURE READ PATH for legacy holdings that still
    // carry the file: `LegacyKeyPurge` removes it on the next start as
    // soon as the keyring holds the same seed verbatim. It can no longer
    // create a `db.key` — `FileEncryption.legacyOrNull` returns `null`
    // if there is none.
    final fileEnc = FileEncryption.legacyOrNull(baseDir);
    final json = fileEnc?.readJsonFile('$baseDir/master_seed.json');
    if (json != null) {
      final hex = json['seed'] as String?;
      if (hex != null) return _hexToBytes(hex);
    }
    // If a .dpapi file exists but keyring load returned null, the DPAPI
    // decryption failed (user-switch, session issue). Returning null here
    // would silently trigger new random key generation → identity loss.
    if (Platform.isWindows && File('$baseDir/master_seed.dpapi').existsSync()) {
      stderr.writeln('[IdentityManager] FATAL: master_seed.dpapi exists but '
          'DPAPI decryption failed and no file fallback available — '
          'refusing to continue with null seed (would cause identity loss)');
      throw StateError('master_seed.dpapi unreadable — identity would be lost');
    }
    return null;
  }

  /// THE SEED GOES INTO THE KEYRING — AND ONLY THERE (S368).
  ///
  /// Here stood the S106 double write: keyring AND file. The file lay
  /// under the random `db.key`, which lies openly in the same directory;
  /// thus the master seed — and via `deriveFileEncKey(seed, hdIndex)` the
  /// entire message storage — could be opened from a disk image alone.
  /// The target state had been built since 3.2.2
  /// (`maintenance/3.2:key_migration.dart:251-252`) and is restored here.
  ///
  /// **It is checked, not believed.** After storing, the keyring must
  /// return the seed VERBATIM; only then does any legacy file go. If it
  /// does not return it, it THROWS instead of falling back to a
  /// plaintext-sealed file — a lost seed is visible, a silently exposed
  /// one is not.
  void _storeMasterSeed(Uint8List seed) {
    if (!KeyringService.isInitialized) {
      throw StateError(
          'No keyring available — the master seed has no '
          'permitted storage location. Formerly this place fell back to '
          '"$baseDir/master_seed.json.enc" under the raw "db.key"; '
          'that has been forbidden since S368. Callers must '
          'run KeyringService.init(baseDir) first '
          '(main.dart / service_daemon.dart do that).');
    }
    final ring = KeyringService.instance;
    if (!ring.store('master_seed', seed)) {
      throw StateError('The keyring rejected the master seed — '
          'there is NO fallback to a file under "db.key" (S368).');
    }
    final back = ring.load('master_seed');
    if (back == null || !_equal(back, seed)) {
      throw StateError('The keyring does not return the master seed '
          'identically — storing aborted, so that no state '
          'arises in which the seed is stored nowhere.');
    }
    // Legacy holdings may still carry the file. It goes as soon as the
    // keyring demonstrably holds the seed — exactly the order from 3.2.2.
    _removeLegacyStore('master_seed.json');
  }

  /// Deletes a `.enc` storage including its sidecars, without creating a
  /// `db.key`. `FileEncryption.deleteFile` would need an instance and
  /// thus a key; here only the file name is asked for.
  void _removeLegacyStore(String name) {
    for (final suffix in ['.enc', '.enc.tmp', '.enc.old']) {
      final f = File('$baseDir/$name$suffix');
      if (!f.existsSync()) continue;
      try {
        f.deleteSync();
        stderr.writeln('[IdentityManager] INFO: $name$suffix removed — the '
            'keyring holds the content (S368, target state since 3.2.2)');
      } catch (e) {
        stderr.writeln('[IdentityManager] WARNING: $name$suffix could not '
            'be removed: $e');
      }
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

  /// Store the seed phrase words (for backup display in Settings).
  void _storeSeedPhrase(List<String> words) {
    if (KeyringService.isInitialized) {
      final phraseBytes = Uint8List.fromList(words.join(' ').codeUnits);
      final stored = KeyringService.instance.store('seed_phrase', phraseBytes);
      if (!stored) {
        stderr.writeln('[IdentityManager] WARNING: keyring store failed '
            'for seed_phrase — using file fallback');
      }
      if (stored) {
        // S363: move freshly generated words behind the lock immediately,
        // provided that works without a dialog. Without a lock a no-op.
        // Deliberately not awaited — `_storeSeedPhrase` is synchronous,
        // and the success of storing does not depend on it.
        unawaited(KeyringService.instance.promoteGatedNames());
        // Legacy holdings may still carry the file. It goes as soon as
        // the keyring holds the words (target state since 3.2.2).
        _removeLegacyStore('seed_phrase.json');
        return;
      }
    }
    // ── THE ONE REMAINING FILE FALLBACK, and it is decided ──
    //
    // Owner decision D3 (03.09.2026): KEEPING the 24 words is better than
    // losing them if the keyring answers the storing attempt with
    // `false`. Unlike with the seed above, there is therefore no throwing
    // here.
    //
    // The branch is reachable only in a narrow case: the keyring accepted
    // the SEED (otherwise `_storeMasterSeed` would have thrown before) and
    // then rejects the WORDS. And it can only write if the profile already
    // carries a legacy key anyway — `FileEncryption.legacyOrNull` creates
    // none. If there is none, the words stay where they are: in the
    // keyring or nowhere.
    final fileEnc = FileEncryption.legacyOrNull(baseDir);
    if (fileEnc == null) {
      stderr.writeln('[IdentityManager] WARNING: keyring refused the seed '
          'phrase and this profile has no legacy key — the 24 words are NOT '  // V3-TOUCH-OK: legacy key fallback, normative in v4_1 §4.5.3 (db.key is one of the six files that never move into the database)
          'written to disk (S368: no plaintext key is created for them).');
      return;
    }
    fileEnc.writeJsonFile('$baseDir/seed_phrase.json', {
      'words': words,
      'version': 1,
    });
  }

  /// Load stored seed phrase words (for displaying in Settings).
  List<String>? loadSeedPhrase() {
    if (KeyringService.isInitialized) {
      final bytes = KeyringService.instance.load('seed_phrase');
      if (bytes != null) {
        final words = String.fromCharCodes(bytes).split(' ');
        if (words.length == 24) return words;
      }
    }
    // Pure READ PATH for legacy holdings (S368). Counterpart to
    // `_storeSeedPhrase`; no longer creates a `db.key`.
    final fileEnc = FileEncryption.legacyOrNull(baseDir);
    final json = fileEnc?.readJsonFile('$baseDir/seed_phrase.json');
    if (json == null) return null;
    final words = json['words'] as List<dynamic>?;
    if (words == null || words.length != 24) return null;
    return words.cast<String>();
  }

  /// Whether this build knows a device code lock at all (Android).
  /// The UI needs this in order to explain "nothing stored" correctly:
  /// on a device WITH a lock that is almost always the reinstallation (the
  /// keyring is app-bound), on one without it is simply a profile without
  /// a stored phrase.
  bool get hasDeviceGate =>
      KeyringService.isInitialized && KeyringService.instance.hasGate;

  /// Whether the keyring of this build is bound to the APP INSTALLATION.
  /// Only then is "nothing lies here" almost always the reinstallation.
  ///
  /// Separate from [hasDeviceGate], because the two statements diverge:
  /// the device code lock exists only on Android
  /// (`MobileKeyringService.hasGate`), but BOTH mobile platforms are
  /// app-bound — Android `EncryptedSharedPreferences` lies in the app
  /// directory, and the iOS Keychain has been cleared along on uninstall
  /// since iOS 10.3. On the desktop it does not apply: `secret-tool` and
  /// DPAPI survive a reinstallation.
  bool get hasAppBoundKeyring => Platform.isAndroid || Platform.isIOS;

  /// The 24 words, if necessary behind the device code lock (S363,
  /// point 1, option D).
  ///
  /// **Why this second path exists next to [loadSeedPhrase] instead of
  /// rebuilding that one.** [loadSeedPhrase] is synchronous, and the header
  /// comment of `KeyringService` says why: keyring accesses lie at start
  /// and at shutdown, not in hot paths. A presence query is unavoidably
  /// asynchronous. Instead of rebuilding the interface, an asynchronous
  /// sibling call stands here; [loadSeedPhrase] stays what it was — and
  /// returns `null` on a device with a filled lock, because the ungated
  /// twin there was removed after the first proven read. Exactly that
  /// makes the lock effective.
  ///
  /// **What does NOT happen here.** There is no silent fallback to a
  /// weaker path: if the lock cannot be served, the result says WHY, and
  /// the UI tells the user. A cancelled dialog yields `cancelled`, not
  /// `null`.
  Future<SeedPhraseAccess> loadSeedPhraseGated(
      {String? title, String? description}) async {
    if (KeyringService.isInitialized) {
      final ring = KeyringService.instance;
      if (ring.hasGate) {
        final status = await ring.gateStatus();
        if (status == GateOutcome.ready) {
          final read = await ring.loadGated('seed_phrase',
              title: title, description: description);
          if (read.outcome == GateOutcome.ready && read.value != null) {
            final words = String.fromCharCodes(read.value!).split(' ');
            if (words.length == 24) {
              return SeedPhraseAccess(words, GateOutcome.ready, gated: true);
            }
          }
          if (read.outcome == GateOutcome.cancelled ||
              read.outcome == GateOutcome.invalidated) {
            return SeedPhraseAccess(null, read.outcome, gated: true);
          }
          // `absent`: nothing lies behind the lock (yet) — the ungated
          // path below is then the truth.
        } else if (status == GateOutcome.invalidated) {
          return SeedPhraseAccess(null, GateOutcome.invalidated, gated: true);
        }
        // noDeviceLock / unavailable: the ungated path still applies. That
        // is NO deterioration compared to the state before S363 — it is
        // exactly this state —, but it is named instead of kept silent.
        final words = loadSeedPhrase();
        return SeedPhraseAccess(
            words, words == null ? GateOutcome.absent : status,
            gated: false);
      }
    }
    final words = loadSeedPhrase();
    return SeedPhraseAccess(
        words, words == null ? GateOutcome.absent : GateOutcome.unavailable,
        gated: false);
  }

  /// MAKES SURE THAT THE KEYRING REALLY HOLDS THE SEED —
  /// and that it holds it BEFORE the lock next door judges it.
  ///
  /// ── WHY THIS IS NEEDED (S368, measured) ────────────────────────────
  ///
  /// [_storeMasterSeed] stores the seed in the keyring and THROWS if there
  /// is none (S368 — the file fallback under the raw `db.key` has been
  /// dropped; §4.5.3 of the leading architecture document:
  /// "never persisted directly"). Thus everything depends on the keyring
  /// standing at the moment the seed comes into existence. On the UI's
  /// order it did NOT stand until S368:
  ///
  ///   1. `main.dart:176-198` explicitly skips `initCrypto` on Linux and
  ///      Windows and until S368 did not start up the keyring there
  ///      either ("daemon owns keyring"),
  ///   2. `setup_screen.dart` nevertheless generates seed and identity in
  ///      THIS process — i.e. without a keyring,
  ///   3. the daemon starts afterwards and executes `initCrypto`.
  ///
  /// Until S368 step 3 caught up on the seed — but only as a SIDE EFFECT
  /// of a misdiagnosis: `KeyMigration.migrateIfNeeded` considered the
  /// one-second-old profile a legacy profile and in doing so put the seed
  /// into the keyring. With the removal of this takeover the side effect
  /// fell away, and the seed afterwards lay ONLY as `master_seed.json.enc`
  /// under the raw `db.key` — re-measured on 05.09.2026 on a fresh
  /// profile: after `initCrypto` there was no `.master_seed.keyring` and
  /// no keyring entry any more.
  ///
  /// This function catches up on that, and it is **not a migration**: it
  /// reads no old format, but exactly the file that the running build
  /// writes itself, and reconciles the two CURRENT storage places. It is
  /// repeatable and a no-op on a profile whose keyring already holds.
  ///
  /// **It does not delete the files itself — but it is the precondition
  /// for their being allowed to go.** F-4 from
  /// `docs/v4-redesign/S363-VORLAGE-android-sperre-und-salt.md` stood
  /// here until S368 as an "open decision of the owner". That was wrong:
  /// the owner has clarified that the target state was already built
  /// under 3.2.2 (`maintenance/3.2:key_migration.dart:
  /// 251-252` — "master_seed is in keyring — remove .enc file"). Deletion
  /// happens at the two places that have the evidence for it:
  /// [_storeMasterSeed] directly after the compared read-back step, and
  /// `LegacyKeyPurge.purge` for holdings this run did not write itself.
  /// This function delivers exactly the precondition on which both hang:
  /// that the keyring really holds the value.
  void reconcileKeyringDeposit() {
    if (!KeyringService.isInitialized) return;
    final ring = KeyringService.instance;
    final log = CLogger.get('identity', profileDir: baseDir);

    if (ring.load('master_seed') == null) {
      // `loadMasterSeed` falls back to the file when the keyring is empty
      // — exactly the value that belongs here.
      final seed = loadMasterSeed();
      if (seed != null && seed.isNotEmpty) {
        if (ring.store('master_seed', seed)) {
          log.info('Keyring reconciliation: the master seed existed only as a '
              'file and is now also in the keyring');
        } else {
          log.warn('Keyring reconciliation: the keyring did not accept the '
              'master seed — staying with the file path');
        }
      }
    }

    if (ring.load('seed_phrase') == null) {
      final words = loadSeedPhrase();
      if (words != null && words.length == 24) {
        if (ring.store(
            'seed_phrase', Uint8List.fromList(words.join(' ').codeUnits))) {
          log.info('Keyring reconciliation: the 24 words existed only as a '
              'file and are now also in the keyring');
        } else {
          log.warn('Keyring reconciliation: the keyring did not accept the 24 '
              'words — staying with the file path');
        }
      }
    }
  }

  /// Moves a leftover FILE copy of the 24 words behind the device code
  /// lock — and deletes it only when that is proven.
  ///
  /// ── THE FINDING THAT MAKES THIS NECESSARY (S363, measurement question 1) ───────────
  ///
  /// The lock from point 1 acts on the keyring. But next to it may lie
  /// `seed_phrase.json.enc`, which [FileEncryption] opens under the RAW
  /// key file `db.key` in the same directory — exactly the construction
  /// by which finding F-4 of the proposal exposed a lock on `master_seed`
  /// as ornament. [loadSeedPhrase] explicitly reads this file as a
  /// fallback; it thus leads past the lock, and the guard
  /// `smoke_seed_phrase_gate_guard` proves in the counter-check to B8
  /// that the words open there with `db.key` alone — without any keyring.
  ///
  /// It can arise on ONE proven path:
  ///   * [_storeSeedPhrase] writes it if the keyring answers the storing
  ///     attempt with `false` (decision D3: keeping the words is better
  ///     than losing them).
  ///
  /// The second path was dropped with S368: `KeyMigration` left it
  /// standing if its own `store` failed — the takeover of a legacy
  /// profile is removed (header of `key_migration.dart`).
  /// [reconcileKeyringDeposit] for its part NEVER writes the file; it
  /// only reads and stores in the keyring.
  ///
  /// If the keyring heals later — app update, fixed platform bug, or
  /// simply a user who has now set up a screen lock —, NOTHING moves it
  /// over: `promoteGatedNames` only knows the ungated twin IN the keyring,
  /// not the file. Without this reconciliation the words would stay
  /// permanently outside the lock, and nobody would see it.
  ///
  /// ── WHY THE ORDER IS THIS WAY ───────────────────────────────────
  ///
  /// First put into the ungated twin, then let the existing, verified
  /// takeover run (write, READ BACK, compare, and only then remove the
  /// twin), and delete the file only when the twin is ACTUALLY gone. The
  /// disappearance of the twin is the only proof this layer has that the
  /// gated storage really holds the words:
  /// `MobileKeyringService._dropUngated` runs exclusively after a compared
  /// read-back step.
  ///
  /// The intermediate step via the ungated twin is NO deterioration: it
  /// is app-bound and AndroidKeyStore-encrypted, while the file lies under
  /// a key that stands next to it in the same directory. If the takeover
  /// fails, both stay and the next start tries again.
  ///
  /// ── WHAT DOES NOT HAPPEN HERE ────────────────────────────────────────
  ///
  /// There is NEVER a prompt. If the time window of the auth-bound key is
  /// not open, everything stays as it is. And without a lock — i.e. on
  /// every non-Android platform — this is a no-op: the file is the only
  /// fallback there and stays where it is.
  Future<void> reconcileSeedPhraseGate() async {
    if (!hasDeviceGate) return;
    final log = CLogger.get('identity', profileDir: baseDir);
    final ring = KeyringService.instance;
    if (await ring.gateStatus() != GateOutcome.ready) return;

    final legacy = File('$baseDir/seed_phrase.json.enc');
    var fileCopyPending = legacy.existsSync();
    if (fileCopyPending) {
      final words = loadSeedPhrase();
      if (words == null || words.length != 24) {
        // Unreadable (no `db.key`, damaged): touch nothing. A file that
        // nobody can open is no bypass — but deleting it would be no gain
        // either, only a loss, in case it can be opened after all later.
        fileCopyPending = false;
      } else if (!ring.store(
          'seed_phrase', Uint8List.fromList(words.join(' ').codeUnits))) {
        log.warn('seed phrase gate: the keyring refused the store — the '
            'db.key file copy stays where it is');
        fileCopyPending = false;
      }
    }

    // Covers two cases in one: the twin just placed, and a twin that
    // `KeyMigration` fetched from the file in THIS run
    // (`MobileKeyringService.init` runs in `main.dart` BEFORE
    // `IdentityContext.initCrypto` and thus before the migration).
    await ring.promoteGatedNames();

    if (!fileCopyPending) return;
    if (ring.load('seed_phrase') != null) {
      log.warn('seed phrase gate: the ungated twin is still there — the '
          'promotion is NOT proven, so the file copy stays');
      return;
    }
    try {
      legacy.deleteSync();
      log.info('seed phrase gate: the db.key file copy of the 24 words was '
          'moved behind the device gate and removed');
    } catch (e) {
      log.warn('seed phrase gate: could not remove the file copy: $e');
    }
  }

  /// Get the next HD index for a new identity.
  /// Uses _maxHdIndex (persisted high-water-mark) to survive identity deletions.
  int nextHdIndex() {
    final identities = loadIdentities();
    var maxFromList = -1;
    for (final id in identities) {
      if (id.hdIndex != null && id.hdIndex! > maxFromList) {
        maxFromList = id.hdIndex!;
      }
    }
    final effective = _maxHdIndex > maxFromList ? _maxHdIndex : maxFromList;
    return effective + 1;
  }

  /// Monotonically increasing identity number — survives deletions.
  /// Parses 'identity-N' ids to find max N, then returns N+1.
  static int _nextIdentityNum(List<Identity> identities) {
    var maxNum = 0;
    for (final id in identities) {
      final match = RegExp(r'^identity-(\d+)$').firstMatch(id.id);
      if (match != null) {
        final n = int.parse(match.group(1)!);
        if (n > maxNum) maxNum = n;
      }
    }
    return maxNum + 1;
  }

  static String _bytesToHex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static Uint8List _hexToBytes(String hex) {
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  /// Load all identities. Recovers from .tmp/.old sidecars if canonical
  /// is missing or corrupt.
  List<Identity> loadIdentities() {
    if (!_identitiesFilePresent) {
      // -- HERE STOOD `_migrateFromSingleProfile()` (S368) --------------
      //
      // The single-profile path from V3: if `identities.json` was missing,
      // an identity was reconstructed from `last_profile.json` +
      // `<profileDir>/keys.json` (PLAINTEXT JSON, both) and written away.
      // That is a takeover of a legacy profile, and V4.1 has none
      // (owner invariant, repeated six times). It was not reachable any
      // more anyway: `FirstStartWipe` deletes a profile without the V4.1
      // marker as the FIRST line of `initCrypto`, and a profile WITH the
      // marker no longer has a V3 single-profile layout.
      //
      // No replacement, no dummy: no profile, no identities.
      //
      // NO `const []`: `createIdentity` appends to exactly this list
      // (`identities.add(identity)`, `:979`). An unmodifiable list made
      // the creation of the FIRST identity fail with "Cannot add to an
      // unmodifiable list" — measured on 05.09.2026, before there ever was
      // a profile.
      return <Identity>[];
    }
    final envelope = _identitiesEnvelopeOrNull();
    if (envelope == null) {
      // The file is there, the seed is not. Here it must NOT silently
      // continue: `[]` would mean "no identities", and the first-start
      // path would lay a new profile over an existing one.
      // The same answer as for a damaged ciphertext - the recovery path,
      // visibly.
      throw IdentitiesFileCorruptException(
          'identities.json.enc lies in $baseDir, but there is no '
          'master seed that opens the device-wide envelope '
          '(keyring empty and no old store) — use seed phrase '
          'to restore');
    }
    final json = envelope.readJsonFile(_identitiesFile);
    if (json == null) {
      final idDir = Directory('$baseDir/identities');
      if (idDir.existsSync() &&
          idDir.listSync().whereType<Directory>().any(
              (d) => d.path.contains('identity-'))) {
        throw IdentitiesFileCorruptException(
            'identities.json corrupt but identity directories exist '
            'on disk — use seed phrase to restore');
      }
      return [];
    }
    // The device port, if already drawn (S374). If it is missing,
    // [deviceDataPort] draws it on first access — there is no takeover
    // from `identity.port`, because there are no legacy profiles (owner
    // 07.09.2026).
    final gp = json['dataPort'] as int?;
    if (gp != null && gp > 0) _deviceDataPort = gp;
    final list = json['identities'] as List<dynamic>? ?? [];
    final identities = list.map((e) => Identity.fromJson(e as Map<String, dynamic>)).toList();
    // Restore high-water-mark: v2+ stores it explicitly, v1 computes from list
    final storedMax = json['maxHdIndex'] as int?;
    if (storedMax != null) {
      _maxHdIndex = storedMax;
    } else {
      var computed = -1;
      for (final id in identities) {
        if (id.hdIndex != null && id.hdIndex! > computed) {
          computed = id.hdIndex!;
        }
      }
      _maxHdIndex = computed;
    }
    _healDiscoveryPortCollisions(identities);
    return identities;
  }

  /// §4.5.2 self-heal: an identity created before the discovery-port
  /// exclusion existed (or set manually via an older build) may carry
  /// `port == discoveryPort`. Such a node binds the transport socket on the
  /// same port as its own LAN-discovery sockets; the bind succeeds silently
  /// because all of them use `SO_REUSEADDR`, and the kernel then splits
  /// inbound datagrams between them so that a share of all traffic is
  /// dropped without any error surfacing. Sender-side fixes cannot repair an
  /// already-persisted port, so it is re-drawn here on load.
  ///
  /// **S376: BOTH fixed LAN ports are healed** via
  /// `DataPort.isReservedLanPort`. Until then this loop only saw 41338
  /// — the V3 port that nobody binds any more on this line — and left
  /// 41340 standing, the port the V4.1 call sequence really binds.
  ///
  /// The port change propagates like any other one: peers relearn the node
  /// through discovery and the address broadcast. Doing this at load time
  /// (rather than at bind time) keeps `identities.json` and the per-profile
  /// `port` file consistent before anything reads them.
  void _healDiscoveryPortCollisions(List<Identity> identities) {
    var healed = false;
    for (final identity in identities) {
      if (!DataPort.isReservedLanPort(identity.port)) continue;
      final oldPort = identity.port;
      // Heal DEVICE-WIDE (S374): the port belongs to the device, so the
      // §4.5.2 self-healing must not set a single identity to a different
      // value than the others. Draw once, give to all.
      if (_deviceDataPort == null ||
          DataPort.isReservedLanPort(_deviceDataPort!)) {
        _deviceDataPort = DataPort.drawDataPort();
      }
      identity.port = _deviceDataPort!;
      healed = true;
      // The new port is written down by `saveIdentities` at the end of
      // this method — the file `<profileDir>/port` that used to be
      // additionally maintained here no longer exists (see [createIdentity]).
      CLogger.get('identity', profileDir: identity.profileDir).warn(
          'Port self-heal: identity ${identity.id} used the reserved LAN '
          'port $oldPort as its data port (§4.5.2 invariant violated) — '
          're-drawn to ${identity.port}');
    }
    if (healed) saveIdentities(identities);
  }

  /// Atomically save identities list (tmp+rename, sidecar-recovery on read).
  void saveIdentities(List<Identity> identities) {
    Directory(baseDir).createSync(recursive: true);
    // Update high-water-mark from current identity list
    for (final id in identities) {
      if (id.hdIndex != null && id.hdIndex! > _maxHdIndex) {
        _maxHdIndex = id.hdIndex!;
      }
    }
    final envelope = _identitiesEnvelopeOrNull();
    if (envelope == null) {
      // There is NO falling back to a plaintext write - exactly that way
      // out WAS the finding. Whoever lands here has violated the order
      // (first store seed, then create identity).
      throw StateError(
          'No master seed in $baseDir — "identities.json" could only '
          'have been written in plaintext, and that has been forbidden since '
          'S368. First generateSeedPhrase()/restoreFromPhrase(), '
          'then createIdentity().');
    }
    envelope.writeJsonFile(_identitiesFile, {
      'version': 2,
      'maxHdIndex': _maxHdIndex,
      // ── THE DATA PORT LIES AT THE TOP LEVEL (S374) ───────────
      //
      // Because it belongs to the DEVICE and not to an identity — §11,
      // "The drawn port is stable per device". It deliberately stands NEXT
      // TO the list and not in its entries.
      'dataPort': _deviceDataPort,
      'identities': identities.map((e) => e.toJson()).toList(),
    });
  }

  /// The data port of this DEVICE (§11, "stable per device").
  ///
  /// ── WHY NOT IN THE IDENTITY, WHERE IT STOOD UNTIL S374 ────────────
  ///
  /// V4.1 holds ONE node per device, and that opens ONE socket. On its
  /// port number hang the firewall permission (under Windows a visible
  /// permission granted once), the NAT mapping and every published entry
  /// hint. That is a property of the device, not of the identity.
  ///
  /// As long as the field hung on the list entries, the code had to make
  /// do, and the makeshift was the same everywhere: `identities.first
  /// .port` — at four places in three start paths (`service_daemon`,
  /// `main`, `ios_background_fetch`). Thus a LIST POSITION decided the
  /// bound port. Whoever deleted the first identity silently changed the
  /// port of the whole device; whoever created a second produced a port
  /// value that nobody bound.
  ///
  /// ── WHY NOT INTO THE ENCRYPTED STORAGE ──────────────────────
  ///
  /// Obvious, because since S366 almost everything lies there — and
  /// nevertheless wrong: `MessageStore` is explicitly ONE STORAGE PER
  /// IDENTITY (§21.4), and its own header justifies why there is no shared
  /// one ("a shared one would have to lie under the device-wide key and
  /// would thus give up the separation that `deriveFileEncKey`
  /// establishes"). A device-wide value cannot lie there without either
  /// being duplicated — i.e. today's problem — or giving up that
  /// separation.
  ///
  /// `identities.json`, by contrast, is already device-wide, already
  /// encrypted and already an object with a top level
  /// (`version`, `maxHdIndex`). The port goes there — no new file, no new
  /// format, no new key.
  ///
  /// NO TAKEOVER FROM LEGACY PROFILES (owner, 07.09.2026): V4.1 has no
  /// working predecessor version, the profiles are created anew before the
  /// next test anyway. If the field is missing, it is drawn.
  int? _deviceDataPort;

  /// The port of this device — drawn at initial setup, unchanged
  /// afterwards.
  ///
  /// Reads the persisted number; if there is none, it is drawn ONCE and
  /// written along at the next `saveIdentities`.
  int get deviceDataPort {
    var p = _deviceDataPort;
    if (p == null || p <= 0) {
      p = DataPort.drawDataPort();
      _deviceDataPort = p;
    }
    return p;
  }

  /// In-flight PQ keygen started by [preWarmPqKeys]. Picked up by
  /// [_preGenerateKeys] so the keygen can overlap with the seed-phrase dialog
  /// instead of running in the critical path.
  Future<({Uint8List mlDsaPk, Uint8List mlDsaSk, Uint8List mlKemPk, Uint8List mlKemSk})>? _pqKeygenPrewarm;

  /// HD index corresponding to [_pqKeygenPrewarm] when it was started via
  /// [preWarmPqKeysDeterministic]. Consumed by [_preGenerateKeys].
  int? _pqPrewarmHdIndex;

  /// Kick off ML-DSA-65 + ML-KEM-768 keygen in an isolate without blocking.
  /// The caller is expected to invoke [createIdentity] afterwards; the pending
  /// keys are consumed there. Safe to call multiple times (first call wins).
  /// Call this right after the user hits "Start" in the setup screen so the
  /// 15-30s keygen on slow hardware overlaps with the seed-phrase dialog
  /// instead of appearing as post-confirm latency.
  Future<({Uint8List mlDsaPk, Uint8List mlDsaSk, Uint8List mlKemPk, Uint8List mlKemSk})> preWarmPqKeys() {
    return _pqKeygenPrewarm ??= generatePqKeysIsolated();
  }

  /// Like [preWarmPqKeys] but starts **deterministic** PQ keygen from the
  /// master seed + HD index. This way the prewarmed keys are the exact keys
  /// that [createIdentity] will need — no discard/re-generate.
  /// If a previous prewarm was started for a different index (or as random
  /// via [preWarmPqKeys]), the stale Future is discarded and a fresh keygen
  /// is started for [hdIndex].
  Future<({Uint8List mlDsaPk, Uint8List mlDsaSk, Uint8List mlKemPk, Uint8List mlKemSk})> preWarmPqKeysDeterministic(Uint8List masterSeed, int hdIndex) {
    if (_pqKeygenPrewarm != null && _pqPrewarmHdIndex != hdIndex) {
      _pqKeygenPrewarm!.ignore();
      _pqKeygenPrewarm = null;
    }
    _pqPrewarmHdIndex = hdIndex;
    return _pqKeygenPrewarm ??= generatePqKeysDeterministicIsolated(masterSeed, hdIndex);
  }

  /// Create a new identity. Uses HD-Wallet index if master seed exists.
  /// Async because PQ keygen runs in a background isolate (ANR prevention).
  ///
  /// [restoreAwaitingPairing] (§7.1.3, P2): pass `true` only from the
  /// seed-phrase restore flow when the user said they still have another
  /// device running with this identity. Defaults to `false` — fresh
  /// installs and manually-added identities are always Primary from the
  /// start, this parameter must never flip for those paths.
  Future<Identity> createIdentity(String displayName,
      {bool restoreAwaitingPairing = false,
      bool restoredFromPhrase = false}) async {
    // First writer of the profile directory — see [_stampV41Profile].
    // Without this line the daemon would delete, at the next
    // `initCrypto`, the identity that comes into existence here.
    _stampV41Profile();
    final identities = loadIdentities();
    final nextNum = _nextIdentityNum(identities);
    final id = 'identity-$nextNum';
    final profileDir = '$baseDir/identities/$id';
    // THE PORT IS NO LONGER DRAWN PER IDENTITY (S374). It belongs to the
    // device (§11); [deviceDataPort] draws it ONCE at initial setup and
    // returns the same one afterwards. The identity only carries it along
    // so that the remaining readers stay unchanged — authoritative is the
    // value at the top level of `identities.json`.
    final port = deviceDataPort;

    Directory(profileDir).createSync(recursive: true);

  // ── `<profileDir>/port` IS GONE (S366) ──────────────────────────────
  //
  // Here stood `File('$profileDir/port').writeAsStringSync('$port')`.
  // Re-measured on 04.09.2026 against this branch, over `lib/`, `bin/`,
  // `test/`, `scripts/`, `docs/`, `android/`, `.github/` and in all
  // languages: the file had FIVE writers and ZERO readers. The port is
  // held in `identities.json` (`saveIdentities` writes it,
  // `loadIdentities` reads it back) — and from there `_startAllInner`
  // also fetches it (`service_daemon.dart:534`, `identities.first.port`).
  // The file was a maintained duplicate that was never consulted.
  //
  // NOT TO BE CONFUSED with `<baseDir>/cleona.port` — that is the IPC
  // port under Windows, and it has readers (`ipc_client.dart:170`,
  // `:235`, `main.dart:1467`, `ipc_server.dart:110`).
  //
  // Legacy holdings: no entry in `FirstStartWipe` needed.
  // `wipeProfileData` (`first_start_wipe.dart:332-346`) deletes EVERY
  // entry below `baseDir` via `listSync` + `deleteSync(recursive: true)`,
  // without a name list — the file falls along; the name lists there only
  // decide WHETHER deletion happens.

    // Assign HD-Wallet index if master seed exists
    int? hdIndex;
    if (hasMasterSeed()) {
      hdIndex = nextHdIndex();
      _maxHdIndex = hdIndex;
    }

    // Pre-generate ALL keys (Ed25519 + X25519 + ML-DSA-65 + ML-KEM-768).
    // PQ keygen runs in background isolate to avoid ANR on Android.
    await _preGenerateKeys(profileDir, hdIndex);

    final identity = Identity(
      id: id,
      displayName: displayName,
      profileDir: profileDir,
      port: port,
      createdAt: DateTime.now(),
      hdIndex: hdIndex,
      restoreAwaitingPairing: restoreAwaitingPairing,
      restoredFromPhrase: restoredFromPhrase,
    );

    identities.add(identity);
    saveIdentities(identities);
    return identity;
  }

  /// Create an identity at a specific HD-Wallet index (§6.4.3 registry recovery).
  /// Unlike [createIdentity], this targets an exact [hdIndex] instead of auto-incrementing.
  ///
  /// [restoreAwaitingPairing] (§7.1.3, P2): the caller (registry recovery /
  /// restore-index-probing, both only ever reached from the seed-phrase
  /// restore flow) forwards the same choice the user made for the primary
  /// identity — every identity recovered in the same restore run describes
  /// the same physical device and the same "additional device vs. lost
  /// device" fact.
  Future<Identity> createIdentityAtIndex(int hdIndex, String displayName,
      {bool restoreAwaitingPairing = false,
      bool restoredFromPhrase = false}) async {
    // First writer of the profile directory — see [_stampV41Profile].
    _stampV41Profile();
    final identities = loadIdentities();
    if (identities.any((i) => i.hdIndex == hdIndex)) {
      throw StateError('Identity with hdIndex=$hdIndex already exists');
    }
    final nextNum = _nextIdentityNum(identities);
    final id = 'identity-$nextNum';
    final profileDir = '$baseDir/identities/$id';
    // As in [createIdentity]: the port belongs to the device, not to the
    // identity (S374, §11).
    final port = deviceDataPort;

    Directory(profileDir).createSync(recursive: true);
    // `<profileDir>/port` is dropped — reasoning at [createIdentity].

    if (hdIndex > _maxHdIndex) _maxHdIndex = hdIndex;
    await _preGenerateKeys(profileDir, hdIndex);

    final identity = Identity(
      id: id,
      displayName: displayName,
      profileDir: profileDir,
      port: port,
      createdAt: DateTime.now(),
      hdIndex: hdIndex,
      restoreAwaitingPairing: restoreAwaitingPairing,
      restoredFromPhrase: restoredFromPhrase,
    );

    identities.add(identity);
    saveIdentities(identities);
    return identity;
  }

  /// Generates the key material in advance and stores it in the encrypted
  /// storage (S366, area `IdentityContext.areaKeys`).
  /// `IdentityContext.initKeys()` finds it there and does not have to
  /// repeat the expensive PQ generation.
  /// PQ keygen (ML-DSA + ML-KEM) runs in background isolate (ANR fix).
  ///
  /// THIS PLACE IS THE SECOND WRITER OF THE SAME AREA. It creates it,
  /// `IdentityContext._saveKeys` maintains it afterwards — the field names
  /// must therefore stay the same here and there.
  Future<void> _preGenerateKeys(String profileDir, int? hdIndex) async {
    final sodium = SodiumFFI();
    // §3.7 step 5: derive per-identity FileEncryption key from seed
    final masterSeed = loadMasterSeed();
    // §3.6 invariant: hdIndex implies deterministic keys from seed.
    // Random keys with hdIndex would appear recoverable but aren't.
    if (hdIndex != null && masterSeed == null) {
      throw StateError(
          'hdIndex=$hdIndex requested but master seed unreadable — '
          'refusing random keys (identity would be unrecoverable '
          'from seed phrase). Re-enter recovery phrase to fix.');
    }
    final Uint8List? fileEncKey = (masterSeed != null && hdIndex != null)
        ? HdWallet.deriveFileEncKey(masterSeed, hdIndex)
        : null;

    // Ed25519: deterministic from HD-Wallet seed, or random
    Uint8List ed25519Pk, ed25519Sk;
    if (masterSeed != null && hdIndex != null) {
      final edKeys = HdWallet.deriveEd25519(masterSeed, hdIndex);
      ed25519Pk = edKeys.publicKey;
      ed25519Sk = edKeys.secretKey;
    } else {
      final edKeys = sodium.generateEd25519KeyPair();
      ed25519Pk = edKeys.publicKey;
      ed25519Sk = edKeys.secretKey;
    }

    // X25519: derived from Ed25519
    final x25519Pk = sodium.ed25519PkToX25519(ed25519Pk);
    final x25519Sk = sodium.ed25519SkToX25519(ed25519Sk);

    // PQ keys: deterministic from master seed (seed recovery), or random.
    // Background isolate avoids ANR on Android (15-30s on slow devices).
    final pqStart = Stopwatch()..start();
    final Future<({Uint8List mlDsaPk, Uint8List mlDsaSk, Uint8List mlKemPk, Uint8List mlKemSk})> pqFuture;
    final bool pqPrewarmed;
    if (_pqKeygenPrewarm != null && masterSeed != null && hdIndex != null && _pqPrewarmHdIndex == hdIndex) {
      // Deterministic prewarm matches — reuse the already-running keygen.
      pqFuture = _pqKeygenPrewarm!;
      pqPrewarmed = true;
    } else if (masterSeed != null && hdIndex != null) {
      pqFuture = generatePqKeysDeterministicIsolated(masterSeed, hdIndex);
      pqPrewarmed = false;
    } else {
      pqFuture = _pqKeygenPrewarm ?? generatePqKeysIsolated();
      pqPrewarmed = _pqKeygenPrewarm != null;
    }
    _pqKeygenPrewarm = null;
    _pqPrewarmHdIndex = null;
    final pqKeys = await pqFuture;
    // Only via CLogger any more. The `print` next to it output THE SAME
    // line a second time on stdout — past `smoke_log_no_user_content_guard`,
    // which only reads `_log.(info|warn|error|event)`. No caller depended
    // on it (checked: `[setup-timing]` otherwise only comes from
    // `setup_screen.dart` and from the E2E spec itself).
    CLogger.get('setup-timing', profileDir: profileDir).info(
        'PQ keygen await: ${pqStart.elapsedMilliseconds}ms prewarmed=$pqPrewarmed');

    // Into the storage — the same format as IdentityContext._saveKeys().
    final data = <String, dynamic>{
      'ed25519_pk': _bytesToHex(ed25519Pk),
      'ed25519_sk': _bytesToHex(ed25519Sk),
      'x25519_pk': _bytesToHex(x25519Pk),
      'x25519_sk': _bytesToHex(x25519Sk),
      'ml_dsa_pk': _bytesToHex(pqKeys.mlDsaPk),
      'ml_dsa_sk': _bytesToHex(pqKeys.mlDsaSk),
      'ml_kem_pk': _bytesToHex(pqKeys.mlKemPk),
      'ml_kem_sk': _bytesToHex(pqKeys.mlKemSk),
      'keys_created_at': DateTime.now().millisecondsSinceEpoch,
    };
    if (fileEncKey == null) {
      // ── WITHOUT A SEED NOTHING IS CREATED (S366) ──────────────────────
      //
      // Here would be the obvious place for a fallback to
      // `FileEncryption(baseDir: baseDir)` — i.e. to the random `db.key`
      // NEXT TO the ciphertext. It would be wrong, and measurably so:
      // since the collections lie in the storage,
      // `IdentityContext.storeOrNull` opens them ONLY with
      // `deriveFileEncKey(masterSeed, hdIndex)`. An identity without seed
      // would thus get keys, but neither contacts nor conversations nor
      // groups — it would be unusable from the first second, and its
      // secret keys would in return lie under a key that lies openly next
      // to it.
      //
      // MEASURED that no operating path arrives here (04.09.2026):
      // every caller of `createIdentity` creates the seed beforehand or
      // already has it — `setup_screen.dart:142-156` (first start),
      // `:608-610` (recovery), `scripts/init_profile.dart:60-65`,
      // and `service_daemon.dart:1076` / `main.dart:3536`/`:3582` add a
      // second identity to an existing installation.
      // `createIdentityAtIndex` carries `hdIndex` in its signature; there
      // the check above has already thrown.
      throw StateError(
          'Identity creation without master seed: NO keys are '
          'stored. The encrypted storage of this identity could '
          'not be opened without a seed-derived key (§21.4.1) '
          '— the identity would have keys, but no contacts, '
          'conversations or groups. Create or restore the seed phrase '
          'first.');
    }
    final deposit =
        MessageStore.open('$profileDir/messages.db', fileEncKey);
    try {
      deposit.putEntry(IdentityContext.areaKeys,
          IdentityContext.keyKeys, data);
    } finally {
      // CLOSED, AND HERE: the daemon opens the same file right afterwards
      // via `IdentityContext.storeOrNull`. A handle left open here would
      // be a second one on the same storage.
      deposit.close();
    }
  }

  /// Delete an identity and its profile directory.
  void deleteIdentity(String id) {
    final identities = loadIdentities();
    final identity = identities.cast<Identity?>().firstWhere(
      (i) => i!.id == id,
      orElse: () => null,
    );
    identities.removeWhere((i) => i.id == id);
    saveIdentities(identities);

    // Remove profile directory
    if (identity != null) {
      final dir = Directory(identity.profileDir);
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    }
  }

  /// Rename an identity.
  void renameIdentity(String id, String newName) {
    final identities = loadIdentities();
    for (final identity in identities) {
      if (identity.id == id) {
        identity.displayName = newName;
        break;
      }
    }
    saveIdentities(identities);
  }

  /// Set the skin for an identity.
  void setSkinId(String id, String? skinId) {
    final identities = loadIdentities();
    for (final identity in identities) {
      if (identity.id == id) {
        identity.skinId = skinId;
        break;
      }
    }
    saveIdentities(identities);
  }

  /// Set the isAdult flag for an identity.
  void setIsAdult(String id, bool isAdult) {
    final identities = loadIdentities();
    for (final identity in identities) {
      if (identity.id == id) {
        identity.isAdult = isAdult;
        break;
      }
    }
    saveIdentities(identities);
  }

  /// Update the port for ALL identities (shared single port).
  void updatePort(int newPort) {
    // §4.5.2 invariant: never persist a reserved LAN port as a data port.
    // The IPC handler rejects this before calling us; this is the last line
    // of defence so no future caller can write the collision to disk, where
    // it would survive restarts and be re-advertised in every discovery
    // frame. S376: both fixed LAN ports, not only the V3 41338.
    if (DataPort.isReservedLanPort(newPort)) {
      // Process log: this warns BEFORE the identities are loaded and
      // applies to all at once (shared port) — it belongs to no single one.
      CLogger.get('identity', profileDir: AppPaths.dataDir).warn(
          'updatePort: refusing to persist the reserved LAN port $newPort '
          'as data port (§4.5.2 invariant)');
      return;
    }
    final identities = loadIdentities();
    // FIRST the device value — since S374 it is the authoritative one
    // (§11). The entries are pulled along so that no reader sees a
    // deviating number; but they are no longer the source.
    _deviceDataPort = newPort;
    for (final identity in identities) {
      identity.port = newPort;
    }
    saveIdentities(identities);
  }

  /// Set the reviewEnabled flag for an identity.
  void setReviewEnabled(String id, bool enabled) {
    final identities = loadIdentities();
    for (final identity in identities) {
      if (identity.id == id) {
        identity.reviewEnabled = enabled;
        break;
      }
    }
    saveIdentities(identities);
  }

  /// Reset all identities to the default skin.
  void resetAllSkins({String? defaultSkinId}) {
    final identities = loadIdentities();
    for (final identity in identities) {
      identity.skinId = defaultSkinId;
    }
    saveIdentities(identities);
  }

  /// Get active identity (from `last_profile.json.enc`).
  Identity? getActiveIdentity() {
    try {
      final envelope = _identitiesEnvelopeOrNull();
      if (envelope == null) return null;
      final json = envelope.readJsonFile(_lastProfileFile);
      if (json == null) return null;
      final profileDir = json['profileDir'] as String?;
      final nodeIdHex = json['nodeIdHex'] as String?;
      final identities = loadIdentities();

      // Match by nodeIdHex first (new format), then profileDir (legacy)
      if (nodeIdHex != null) {
        final match = identities.cast<Identity?>().firstWhere(
          (i) => i!.nodeIdHex == nodeIdHex,
          orElse: () => null,
        );
        if (match != null) return match;
      }
      if (profileDir != null) {
        return identities.cast<Identity?>().firstWhere(
          (i) => i!.profileDir == profileDir,
          orElse: () => null,
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// The LOGICAL path of the memo file for the most recently chosen
  /// identity. On disk: `last_profile.json.enc`.
  String get _lastProfileFile => '$baseDir/last_profile.json';

  /// Set active identity.
  ///
  /// -- WHY THIS FILE IS SEALED AS WELL (S368) -------------------
  ///
  /// It carries EXACTLY THE SAME link as `identities.json`, only for the
  /// active identity: `displayName` next to `nodeIdHex`, plus `port` and
  /// the absolute profile path. Sealing `identities.json` and leaving this
  /// one open would not have closed the finding, only shifted it from one
  /// file name to the other — the guard searches for the BYTES of the
  /// display name, not for names, and would have found it.
  ///
  /// The same device-wide key (K2): it is not identity-bound — after all,
  /// it is only what says WHICH identity is meant.
  void setActiveIdentity(Identity identity) {
    Directory(baseDir).createSync(recursive: true);
    final envelope = _identitiesEnvelopeOrNull();
    if (envelope == null) {
      throw StateError(
          'No master seed in $baseDir — "last_profile.json" could only '
          'have been written in plaintext (S368 forbidden). '
          'There is no active identity without a seed.');
    }
    envelope.writeJsonFile(_lastProfileFile, {
      'profileDir': identity.profileDir,
      'displayName': identity.displayName,
      'port': identity.port,
      if (identity.nodeIdHex != null) 'nodeIdHex': identity.nodeIdHex,
    });
  }

}

/// Result of [IdentityManager.loadSeedPhraseGated].
///
/// Carries the REASON next to the words, so that the UI can replace an
/// empty screen with a sentence. The three cases a user could not
/// otherwise place:
///   * [GateOutcome.cancelled]    — he cancelled the system dialog.
///   * [GateOutcome.invalidated]  — he removed or changed the screen lock;
///     the device-bound key is thus permanently invalid and the content
///     gone. His written-down 24 words remain valid — the identity is not
///     lost, only the display.
///   * [GateOutcome.absent] on Android — e.g. after a reinstallation:
///     the keyring is app-bound, an uninstall clears away ciphertext AND
///     key (measured in
///     `docs/v4-redesign/S363-messung-schluesselbund.md`, 5.1).
class SeedPhraseAccess {
  final List<String>? words;
  final GateOutcome outcome;

  /// Whether the words actually lay behind the device code lock.
  /// `false` means: this build or this device has no lock — the words
  /// came via the path that already existed before S363.
  final bool gated;

  const SeedPhraseAccess(this.words, this.outcome, {required this.gated});
}
