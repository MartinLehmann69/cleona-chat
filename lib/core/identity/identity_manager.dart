import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/crypto/hd_wallet.dart';
import 'package:cleona/core/crypto/keyring_service.dart';
import 'package:cleona/core/crypto/pq_isolate.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/crypto/seed_phrase.dart';
import 'package:cleona/core/platform/app_paths.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/storage/atomic_json_writer.dart';

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
  String displayName;
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

  Identity({
    required this.id,
    required this.displayName,
    required this.profileDir,
    required this.port,
    required this.createdAt,
    this.nodeIdHex,
    this.hdIndex,
    this.skinId,
    this.isAdult = false,
    this.reviewEnabled = true,
  });

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
      );
}

/// Manages multiple identity profiles.
/// All identities share a single daemon/node/port.
/// Supports HD-Wallet key derivation from a master seed.
class IdentityManager {
  final String baseDir; // ~/.cleona
  int _maxHdIndex = -1;

  IdentityManager({String? baseDir})
      : baseDir = baseDir ?? AppPaths.dataDir;

  String get _identitiesFile => '$baseDir/identities.json';
  String get _crimsonDismissedFlagFile =>
      '$baseDir/crimson_migration_dismissed.flag';

  /// Returns true if any identity has a stored skinId of 'crimson' AND the
  /// user has not yet permanently dismissed the migration banner.
  /// Dismissal is persisted to disk (survives app restart).
  bool get crimsonMigrationShouldShow {
    if (File(_crimsonDismissedFlagFile).existsSync()) return false;
    final identities = loadIdentities();
    return identities.any((id) => id.skinId == 'crimson');
  }

  /// Called when user taps "Got it" on the migration banner.
  /// Writes a flag file so the banner stays dismissed across restarts.
  void dismissCrimsonBanner() {
    try {
      final f = File(_crimsonDismissedFlagFile);
      f.parent.createSync(recursive: true);
      f.writeAsStringSync('1');
    } catch (_) {
      // Non-fatal: if disk is read-only, banner re-shows next start.
    }
  }

  // ── Seed Phrase Management ──────────────────────────────────────

  /// Generate a new seed phrase and store the master seed encrypted.
  /// Returns the 24 words (user must back them up).
  List<String> generateSeedPhrase() {
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
    // Legacy fallback for pre-migration profiles
    final fileEnc = FileEncryption(baseDir: baseDir);
    final json = fileEnc.readJsonFile('$baseDir/master_seed.json');
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

  void _storeMasterSeed(Uint8List seed) {
    // S106 fix: dual-write — keyring (primary) AND file (ground-truth).
    // Prevents seed loss when keyring becomes unreadable (baseDir change,
    // hostname change, secret-tool daemon unavailable).
    if (KeyringService.isInitialized) {
      final stored = KeyringService.instance.store('master_seed', seed);
      if (!stored) {
        stderr.writeln('[IdentityManager] WARNING: keyring store failed for master_seed — file fallback only');
      }
    }
    final fileEnc = FileEncryption(baseDir: baseDir);
    fileEnc.writeJsonFile('$baseDir/master_seed.json', {
      'seed': _bytesToHex(seed),
      'version': 1,
    });
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
      if (stored) return;
    }
    // File fallback (keyring unavailable or store failed)
    final fileEnc = FileEncryption(baseDir: baseDir);
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
    // Legacy fallback
    final fileEnc = FileEncryption(baseDir: baseDir);
    final json = fileEnc.readJsonFile('$baseDir/seed_phrase.json');
    if (json == null) return null;
    final words = json['words'] as List<dynamic>?;
    if (words == null || words.length != 24) return null;
    return words.cast<String>();
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
    final canonicalExists = File(_identitiesFile).existsSync();
    final tmpExists = File('$_identitiesFile.tmp').existsSync();
    final oldExists = File('$_identitiesFile.old').existsSync();
    if (!canonicalExists && !tmpExists && !oldExists) {
      // Migration: check if last_profile.json exists (single-identity mode)
      return _migrateFromSingleProfile();
    }
    final json = AtomicJsonWriter.readJsonFile(_identitiesFile);
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
    return identities;
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
    AtomicJsonWriter.writeJsonFile(_identitiesFile, {
      'version': 2,
      'maxHdIndex': _maxHdIndex,
      'identities': identities.map((e) => e.toJson()).toList(),
    });
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
  Future<Identity> createIdentity(String displayName) async {
    final identities = loadIdentities();
    final nextNum = _nextIdentityNum(identities);
    final id = 'identity-$nextNum';
    final profileDir = '$baseDir/identities/$id';
    final port = 10000 + Random().nextInt(55000);

    Directory(profileDir).createSync(recursive: true);

    // Persist port
    File('$profileDir/port').writeAsStringSync('$port');

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
    );

    identities.add(identity);
    saveIdentities(identities);
    return identity;
  }

  /// Create an identity at a specific HD-Wallet index (§6.4.3 registry recovery).
  /// Unlike [createIdentity], this targets an exact [hdIndex] instead of auto-incrementing.
  Future<Identity> createIdentityAtIndex(int hdIndex, String displayName) async {
    final identities = loadIdentities();
    if (identities.any((i) => i.hdIndex == hdIndex)) {
      throw StateError('Identity with hdIndex=$hdIndex already exists');
    }
    final nextNum = _nextIdentityNum(identities);
    final id = 'identity-$nextNum';
    final profileDir = '$baseDir/identities/$id';
    final port = 10000 + Random().nextInt(55000);

    Directory(profileDir).createSync(recursive: true);
    File('$profileDir/port').writeAsStringSync('$port');

    if (hdIndex > _maxHdIndex) _maxHdIndex = hdIndex;
    await _preGenerateKeys(profileDir, hdIndex);

    final identity = Identity(
      id: id,
      displayName: displayName,
      profileDir: profileDir,
      port: port,
      createdAt: DateTime.now(),
      hdIndex: hdIndex,
    );

    identities.add(identity);
    saveIdentities(identities);
    return identity;
  }

  /// Pre-generate cryptographic keys and persist as encrypted keys.json.
  /// The daemon's IdentityContext.initKeys() will find keys.json and load
  /// them instantly instead of running expensive PQ keygen.
  /// PQ keygen (ML-DSA + ML-KEM) runs in background isolate (ANR fix).
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
    final fileEnc = FileEncryption(baseDir: baseDir, key: fileEncKey);

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
    // Log PQ keygen timing both to stdout (print) and to the per-profile CLogger
    // so it appears in $profileDir/logs/cleona_YYYY-MM-DD.log for E2E diagnosis.
    // ignore: avoid_print
    print('[setup-timing] PQ keygen await: ${pqStart.elapsedMilliseconds}ms '
        '(prewarmed=$pqPrewarmed)');
    CLogger.get('setup-timing', profileDir: profileDir).info(
        'PQ keygen await: ${pqStart.elapsedMilliseconds}ms prewarmed=$pqPrewarmed');

    // Save encrypted keys.json — same format as IdentityContext._saveKeys()
    fileEnc.writeJsonFile('$profileDir/keys.json', {
      'ed25519_pk': _bytesToHex(ed25519Pk),
      'ed25519_sk': _bytesToHex(ed25519Sk),
      'x25519_pk': _bytesToHex(x25519Pk),
      'x25519_sk': _bytesToHex(x25519Sk),
      'ml_dsa_pk': _bytesToHex(pqKeys.mlDsaPk),
      'ml_dsa_sk': _bytesToHex(pqKeys.mlDsaSk),
      'ml_kem_pk': _bytesToHex(pqKeys.mlKemPk),
      'ml_kem_sk': _bytesToHex(pqKeys.mlKemSk),
      'keys_created_at': DateTime.now().millisecondsSinceEpoch,
    });
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
    final identities = loadIdentities();
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

  /// Get active identity (from last_profile.json).
  Identity? getActiveIdentity() {
    final file = File('$baseDir/last_profile.json');
    if (!file.existsSync()) return null;

    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
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

  /// Set active identity.
  void setActiveIdentity(Identity identity) {
    Directory(baseDir).createSync(recursive: true);
    AtomicJsonWriter.writeJsonFile('$baseDir/last_profile.json', {
      'profileDir': identity.profileDir,
      'displayName': identity.displayName,
      'port': identity.port,
      if (identity.nodeIdHex != null) 'nodeIdHex': identity.nodeIdHex,
    });
  }

  /// Migrate from single-profile mode (last_profile.json only).
  List<Identity> _migrateFromSingleProfile() {
    final lastProfile = File('$baseDir/last_profile.json');
    if (!lastProfile.existsSync()) return [];

    try {
      final json = jsonDecode(lastProfile.readAsStringSync()) as Map<String, dynamic>;
      final identity = Identity(
        id: 'identity-1',
        displayName: json['displayName'] as String,
        profileDir: json['profileDir'] as String,
        port: json['port'] as int,
        createdAt: DateTime.now(),
      );

      final keysFile = File('${identity.profileDir}/keys.json');
      if (!keysFile.existsSync()) return [];
      final Map<String, dynamic> keys;
      try {
        keys = jsonDecode(keysFile.readAsStringSync()) as Map<String, dynamic>;
      } catch (_) {
        return [];
      }
      identity.nodeIdHex = keys['nodeIdHex'] as String?;

      saveIdentities([identity]);
      return [identity];
    } catch (_) {
      return [];
    }
  }
}
