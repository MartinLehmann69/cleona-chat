import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/crypto/hd_wallet.dart';
import 'package:cleona/core/crypto/pq_isolate.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/crypto/seed_phrase.dart';
import 'package:cleona/core/platform/app_paths.dart';

/// Represents a single identity profile.
class Identity {
  final String id;
  String displayName;
  final String profileDir;
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

  IdentityManager({String? baseDir})
      : baseDir = baseDir ?? AppPaths.dataDir;

  String get _identitiesFile => '$baseDir/identities.json';

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

  /// Check if a master seed exists.
  bool hasMasterSeed() {
    // FileEncryption stores as .json.enc
    return File('$baseDir/master_seed.json.enc').existsSync() ||
           File('$baseDir/master_seed.json').existsSync();
  }

  /// Load the master seed (encrypted on disk).
  Uint8List? loadMasterSeed() {
    final fileEnc = FileEncryption(baseDir: baseDir);
    final json = fileEnc.readJsonFile('$baseDir/master_seed.json');
    if (json == null) return null;
    final hex = json['seed'] as String?;
    if (hex == null) return null;
    return _hexToBytes(hex);
  }

  void _storeMasterSeed(Uint8List seed) {
    final fileEnc = FileEncryption(baseDir: baseDir);
    fileEnc.writeJsonFile('$baseDir/master_seed.json', {
      'seed': _bytesToHex(seed),
      'version': 1,
    });
  }

  /// Store the seed phrase words encrypted (for backup display in Settings).
  void _storeSeedPhrase(List<String> words) {
    final fileEnc = FileEncryption(baseDir: baseDir);
    fileEnc.writeJsonFile('$baseDir/seed_phrase.json', {
      'words': words,
      'version': 1,
    });
  }

  /// Load stored seed phrase words (for displaying in Settings).
  List<String>? loadSeedPhrase() {
    final fileEnc = FileEncryption(baseDir: baseDir);
    final json = fileEnc.readJsonFile('$baseDir/seed_phrase.json');
    if (json == null) return null;
    final words = json['words'] as List<dynamic>?;
    if (words == null || words.length != 24) return null;
    return words.cast<String>();
  }

  /// Get the next HD index for a new identity.
  int nextHdIndex() {
    final identities = loadIdentities();
    var maxIndex = -1;
    for (final id in identities) {
      if (id.hdIndex != null && id.hdIndex! > maxIndex) {
        maxIndex = id.hdIndex!;
      }
    }
    return maxIndex + 1;
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

  /// Load all identities.
  List<Identity> loadIdentities() {
    final file = File(_identitiesFile);
    if (!file.existsSync()) {
      // Migration: check if last_profile.json exists (single-identity mode)
      return _migrateFromSingleProfile();
    }

    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final list = json['identities'] as List<dynamic>? ?? [];
      return list.map((e) => Identity.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Save identities list.
  void saveIdentities(List<Identity> identities) {
    Directory(baseDir).createSync(recursive: true);
    File(_identitiesFile).writeAsStringSync(jsonEncode({
      'version': 1,
      'identities': identities.map((e) => e.toJson()).toList(),
    }));
  }

  /// In-flight PQ keygen started by [preWarmPqKeys]. Picked up by
  /// [_preGenerateKeys] so the keygen can overlap with the seed-phrase dialog
  /// instead of running in the critical path.
  Future<({Uint8List mlDsaPk, Uint8List mlDsaSk, Uint8List mlKemPk, Uint8List mlKemSk})>? _pqKeygenPrewarm;

  /// Kick off ML-DSA-65 + ML-KEM-768 keygen in an isolate without blocking.
  /// The caller is expected to invoke [createIdentity] afterwards; the pending
  /// keys are consumed there. Safe to call multiple times (first call wins).
  /// Call this right after the user hits "Start" in the setup screen so the
  /// 15-30s keygen on slow hardware overlaps with the seed-phrase dialog
  /// instead of appearing as post-confirm latency.
  void preWarmPqKeys() {
    _pqKeygenPrewarm ??= generatePqKeysIsolated();
  }

  /// Create a new identity. Uses HD-Wallet index if master seed exists.
  /// Async because PQ keygen runs in a background isolate (ANR prevention).
  Future<Identity> createIdentity(String displayName) async {
    final identities = loadIdentities();
    final nextNum = identities.length + 1;
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

  /// Pre-generate cryptographic keys and persist as encrypted keys.json.
  /// The daemon's IdentityContext.initKeys() will find keys.json and load
  /// them instantly instead of running expensive PQ keygen.
  /// PQ keygen (ML-DSA + ML-KEM) runs in background isolate (ANR fix).
  Future<void> _preGenerateKeys(String profileDir, int? hdIndex) async {
    final sodium = SodiumFFI();
    final fileEnc = FileEncryption(baseDir: baseDir);

    // Ed25519: deterministic from HD-Wallet seed, or random
    Uint8List ed25519Pk, ed25519Sk;
    final masterSeed = loadMasterSeed();
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

    // PQ keys in background isolate (ML-DSA + ML-KEM: 15-30s on slow devices).
    // Reuse a prewarmed future if preWarmPqKeys() was called during the seed
    // phrase dialog — that overlaps keygen with user reading time.
    final pqPrewarmed = _pqKeygenPrewarm != null;
    final pqStart = Stopwatch()..start();
    final pqFuture = _pqKeygenPrewarm ?? generatePqKeysIsolated();
    _pqKeygenPrewarm = null;
    final pqKeys = await pqFuture;
    // print() (stdout) is captured in /tmp/cleona-gui.log by the GUI launcher;
    // stderr is not. No flutter/foundation import here because this file also
    // runs in the pure-Dart AOT daemon build.
    // ignore: avoid_print
    print('[setup-timing] PQ keygen await: ${pqStart.elapsedMilliseconds}ms '
        '(prewarmed=$pqPrewarmed)');

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
    File('$baseDir/last_profile.json').writeAsStringSync(jsonEncode({
      'profileDir': identity.profileDir,
      'displayName': identity.displayName,
      'port': identity.port,
      if (identity.nodeIdHex != null) 'nodeIdHex': identity.nodeIdHex,
    }));
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

      // Read nodeIdHex if keys exist
      final keysFile = File('${identity.profileDir}/keys.json');
      if (keysFile.existsSync()) {
        try {
          final keys = jsonDecode(keysFile.readAsStringSync()) as Map<String, dynamic>;
          identity.nodeIdHex = keys['nodeIdHex'] as String?;
        } catch (_) {}
      }

      saveIdentities([identity]);
      return [identity];
    } catch (_) {
      return [];
    }
  }
}
