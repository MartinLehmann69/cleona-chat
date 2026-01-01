import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/crypto/device_keys_store.dart';
import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/crypto/hd_wallet.dart';
import 'package:cleona/core/crypto/network_secret.dart';
import 'package:cleona/core/crypto/pq_isolate.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/core/platform/app_paths.dart';

/// Holds all cryptographic keys and identity for one user profile.
/// Multiple IdentityContexts can share a single CleonaNode.
class IdentityContext {
  final String profileDir;
  final String networkChannel;
  final String displayName;
  final CLogger _log;

  // Identity keys (permanent)
  late Uint8List ed25519PublicKey;
  late Uint8List ed25519SecretKey;
  late Uint8List mlDsaPublicKey;
  late Uint8List mlDsaSecretKey;

  // KEM keys (rotatable)
  late Uint8List x25519PublicKey;
  late Uint8List x25519SecretKey;
  late Uint8List mlKemPublicKey;
  late Uint8List mlKemSecretKey;

  // Previous KEM keys (kept 7 days after rotation for transit messages)
  Uint8List? previousX25519Sk;
  Uint8List? previousMlKemSk;
  DateTime? keyRotatedAt;
  DateTime? keysCreatedAt;

  /// User-ID: stable identity across all devices = SHA-256(network_secret + ed25519_pk).
  /// Used for contact lookup, sender_id in envelopes, S&F storage key.
  late Uint8List userId;

  /// Device-Node-ID: daemon-global routing identifier.
  /// device_id = SHA-256(network_secret + ed25519_device_pubkey)
  /// Derived from the daemon-global Device-Sig keypair (§3.5/§3.7) — all
  /// hosted UserIDs share the same DeviceID. See Architecture §3.1.
  late Uint8List deviceNodeId;

  // ── 2D-DHT Identity Resolution: persistierte seq-Counter ──────────
  // Plan: docs/superpowers/plans/2026-04-26-2d-dht-identity-resolution.md (Task 4)
  // Persistiert in `<profileDir>/identity_resolution.json[.enc]`.
  // Auth-Seq und Liveness-Seq sind bewusst getrennt (verschiedene TTLs / Update-Frequenzen).
  int _authManifestSeq = 0;
  int _livenessSeq = 0;
  int _deviceKemSeq = 0;
  Uint8List? _lastAuthManifestContentHash;

  int get authManifestSeq => _authManifestSeq;
  int get livenessSeq => _livenessSeq;
  int get deviceKemSeq => _deviceKemSeq;
  Uint8List? get lastAuthManifestContentHash => _lastAuthManifestContentHash;

  int bumpAuthManifestSeq() => ++_authManifestSeq;
  int bumpLivenessSeq() => ++_livenessSeq;
  int bumpDeviceKemSeq() => ++_deviceKemSeq;

  void setLastAuthManifestContentHash(Uint8List hash) {
    _lastAuthManifestContentHash = hash;
  }

  /// Disk-Corruption-Recovery: wenn persistedSeq=0 (z.B. nach Datei-Verlust)
  /// und ein Network-Probe einen hoeheren Wert findet, springen wir auf
  /// max(persisted, probed) + 100. Safety-Margin verhindert dass alte
  /// stored Records den frischen Owner-Publish blockieren
  /// ("incoming.seq <= stored.seq -> drop"). Persistierung fire-and-forget.
  /// Plan: Task 12 Step 12.3.
  int recoverAuthSeq(int probedSeq) {
    _authManifestSeq =
        (probedSeq > _authManifestSeq ? probedSeq : _authManifestSeq) + 100;
    // fire-and-forget — Fehler beim Schreiben sind tolerierbar (naechster
    // bump+persist-Zyklus deckt das ab); waere blocking ungewollt waehrend
    // einer Network-Resolution.
    persistIdentityResolutionState();
    return _authManifestSeq;
  }

  /// Persistiert die seq-Counter + last-content-hash verschluesselt nach
  /// `<profileDir>/identity_resolution.json` (FileEncryption nutzt den
  /// daemon-weiten `<_baseDir>/db.key`).
  Future<void> persistIdentityResolutionState() async {
    final fileEnc = FileEncryption(baseDir: _baseDir);
    Directory(profileDir).createSync(recursive: true);
    fileEnc.writeJsonFile('$profileDir/identity_resolution.json', {
      'authManifestSeq': _authManifestSeq,
      'livenessSeq': _livenessSeq,
      'deviceKemSeq': _deviceKemSeq,
      'lastAuthManifestContentHash': _lastAuthManifestContentHash != null
          ? bytesToHex(_lastAuthManifestContentHash!)
          : null,
    });
  }

  /// Laedt die persistierten seq-Counter beim Identity-Init. Erstes Run:
  /// Datei fehlt -> Defaults bleiben 0.
  Future<void> _loadIdentityResolutionState() async {
    final fileEnc = FileEncryption(baseDir: _baseDir);
    final data = fileEnc.readJsonFile('$profileDir/identity_resolution.json');
    if (data == null) return;
    _authManifestSeq = (data['authManifestSeq'] as int?) ?? 0;
    _livenessSeq = (data['livenessSeq'] as int?) ?? 0;
    _deviceKemSeq = (data['deviceKemSeq'] as int?) ?? 0;
    final hashHex = data['lastAuthManifestContentHash'] as String?;
    _lastAuthManifestContentHash =
        hashHex != null ? hexToBytes(hashHex) : null;
  }

  /// Legacy alias: returns userId (backward compat for identity comparisons).
  /// 50+ places in the codebase compare identity.nodeId with contact IDs,
  /// group member IDs, etc. — all of these are identity operations, not routing.
  Uint8List get nodeId => userId;

  /// Base directory for shared resources (db.key).
  /// Defaults to ~/.cleona (2 levels up from identities/identity-N/).
  final String _baseDir;

  /// HD-Wallet derivation index (null = legacy random keys).
  final int? hdIndex;

  /// Master seed for HD-Wallet derivation (null = legacy).
  final Uint8List? masterSeed;

  /// When this identity was created (from IdentityManager).
  final DateTime createdAt;

  /// Self-declaration: user claims to be 18+ (from IdentityManager).
  bool isAdult;

  IdentityContext({
    required this.profileDir,
    required this.displayName,
    this.networkChannel = 'beta',
    String? baseDir,
    this.hdIndex,
    this.masterSeed,
    DateTime? createdAt,
    this.isAdult = false,
  })  : _baseDir = baseDir ?? _resolveBaseDir(profileDir),
        createdAt = createdAt ?? DateTime.now(),
        _log = CLogger.get('identity', profileDir: profileDir);

  static String _resolveBaseDir(String profileDir) {
    // profileDir is e.g. ~/.cleona/identities/identity-1 or ~/.cleona/Alice
    // baseDir is ~/.cleona
    final home = AppPaths.home;
    return '$home/.cleona';
  }

  /// nodeIdHex returns the per-device routing ID (used by transport layer).
  /// For service-level identification (contacts, groups, channels), use userIdHex.
  String get nodeIdHex => bytesToHex(deviceNodeId);
  String get userIdHex => bytesToHex(userId);
  String get deviceNodeIdHex => bytesToHex(deviceNodeId);

  /// Initialize keys: load from disk or generate new ones.
  /// Keys are stored encrypted via FileEncryption.
  Future<void> initKeys() async {
    final fileEnc = FileEncryption(baseDir: _baseDir);
    final json = fileEnc.readJsonFile('$profileDir/keys.json');

    if (json != null) {
      ed25519PublicKey = hexToBytes(json['ed25519_pk'] as String);
      ed25519SecretKey = hexToBytes(json['ed25519_sk'] as String);
      mlDsaPublicKey = hexToBytes(json['ml_dsa_pk'] as String);
      mlDsaSecretKey = hexToBytes(json['ml_dsa_sk'] as String);
      x25519PublicKey = hexToBytes(json['x25519_pk'] as String);
      x25519SecretKey = hexToBytes(json['x25519_sk'] as String);
      mlKemPublicKey = hexToBytes(json['ml_kem_pk'] as String);
      mlKemSecretKey = hexToBytes(json['ml_kem_sk'] as String);
      // Load previous keys if present (rotation fallback)
      if (json['prev_x25519_sk'] != null) {
        previousX25519Sk = hexToBytes(json['prev_x25519_sk'] as String);
      }
      if (json['prev_ml_kem_sk'] != null) {
        previousMlKemSk = hexToBytes(json['prev_ml_kem_sk'] as String);
      }
      if (json['key_rotated_at'] != null) {
        keyRotatedAt = DateTime.fromMillisecondsSinceEpoch(json['key_rotated_at'] as int);
      }
      if (json['keys_created_at'] != null) {
        keysCreatedAt = DateTime.fromMillisecondsSinceEpoch(json['keys_created_at'] as int);
      } else {
        // Migrate legacy keys: set creation time to now, rotation starts in 7 days
        keysCreatedAt = DateTime.now();
        _saveKeys(fileEnc);
      }
      _log.info('Keys loaded from disk');
    } else {
      await _generateKeysAsync();
      keysCreatedAt = DateTime.now();
      _saveKeys(fileEnc);
      _log.info('New keys generated');
    }

    // Compute User-ID: SHA-256(network_secret + ed25519PublicKey) — stable identity
    userId = HdWallet.computeUserId(ed25519PublicKey, NetworkSecret.secret);

    // Compute Device-Node-ID from the daemon-global Device-Sig keypair
    // (§3.1, §3.5). Multi-Identity sharing: all IdentityContexts in this
    // daemon load the SAME DeviceKeysStore (single file in baseDir) and
    // therefore derive the SAME deviceNodeId.
    final deviceBundle = DeviceKeysStore.loadOrCreate(baseDir: _baseDir, fileEnc: fileEnc);
    deviceNodeId = HdWallet.computeDeviceNodeId(
        deviceBundle.sig.ed25519PublicKey, NetworkSecret.secret);

    _log.info('Identity "$displayName" User-ID: ${userIdHex.substring(0, 16)}... '
        'Device-Node-ID: ${deviceNodeIdHex.substring(0, 16)}...');

    // 2D-DHT Identity Resolution: persistierte seq-Counter wiederherstellen
    // (Datei fehlt beim ersten Start -> Defaults bleiben 0).
    await _loadIdentityResolutionState();
  }

  Future<void> _generateKeysAsync() async {
    final sodium = SodiumFFI();

    // Ed25519 + X25519: deterministic from seed if HD-Wallet, random otherwise
    if (masterSeed != null && hdIndex != null) {
      final edKeys = HdWallet.deriveEd25519(masterSeed!, hdIndex!);
      ed25519PublicKey = edKeys.publicKey;
      ed25519SecretKey = edKeys.secretKey;
      _log.info('Ed25519 keys derived from HD-Wallet index $hdIndex');
    } else {
      final edKeys = sodium.generateEd25519KeyPair();
      ed25519PublicKey = edKeys.publicKey;
      ed25519SecretKey = edKeys.secretKey;
    }

    x25519PublicKey = sodium.ed25519PkToX25519(ed25519PublicKey);
    x25519SecretKey = sodium.ed25519SkToX25519(ed25519SecretKey);

    // PQ keys: generated in background isolate to avoid ANR on Android.
    // ML-DSA-65 + ML-KEM-768 keygen takes 15-30s on slow devices.
    final pqKeys = await generatePqKeysIsolated();
    mlDsaPublicKey = pqKeys.mlDsaPk;
    mlDsaSecretKey = pqKeys.mlDsaSk;
    mlKemPublicKey = pqKeys.mlKemPk;
    mlKemSecretKey = pqKeys.mlKemSk;
  }

  void _saveKeys(FileEncryption fileEnc) {
    Directory(profileDir).createSync(recursive: true);
    final data = <String, dynamic>{
      'ed25519_pk': bytesToHex(ed25519PublicKey),
      'ed25519_sk': bytesToHex(ed25519SecretKey),
      'ml_dsa_pk': bytesToHex(mlDsaPublicKey),
      'ml_dsa_sk': bytesToHex(mlDsaSecretKey),
      'x25519_pk': bytesToHex(x25519PublicKey),
      'x25519_sk': bytesToHex(x25519SecretKey),
      'ml_kem_pk': bytesToHex(mlKemPublicKey),
      'ml_kem_sk': bytesToHex(mlKemSecretKey),
    };
    if (previousX25519Sk != null) data['prev_x25519_sk'] = bytesToHex(previousX25519Sk!);
    if (previousMlKemSk != null) data['prev_ml_kem_sk'] = bytesToHex(previousMlKemSk!);
    if (keyRotatedAt != null) data['key_rotated_at'] = keyRotatedAt!.millisecondsSinceEpoch;
    if (keysCreatedAt != null) data['keys_created_at'] = keysCreatedAt!.millisecondsSinceEpoch;
    fileEnc.writeJsonFile('$profileDir/keys.json', data);
  }

  /// Check if KEM keys need rotation (> 7 days old).
  bool needsRotation() {
    final now = DateTime.now();
    // If rotated before, check time since last rotation
    if (keyRotatedAt != null) return now.difference(keyRotatedAt!).inDays >= 7;
    // Never rotated: check time since key creation
    if (keysCreatedAt != null) return now.difference(keysCreatedAt!).inDays >= 7;
    return false;
  }

  /// Rotate x25519 + ML-KEM keys. Moves current to previous, generates new.
  /// ML-KEM keygen runs in background isolate to avoid ANR on Android.
  Future<void> rotateKemKeys() async {
    final fileEnc = FileEncryption(baseDir: _baseDir);
    final sodium = SodiumFFI();

    // Move current to previous
    previousX25519Sk = x25519SecretKey;
    previousMlKemSk = mlKemSecretKey;

    // Generate new x25519 (independent, not derived from ed25519)
    final newX25519 = sodium.generateX25519KeyPair();
    x25519PublicKey = newX25519.publicKey;
    x25519SecretKey = newX25519.secretKey;

    // Generate new ML-KEM in background isolate (avoids ANR)
    final newKem = await generateMlKemIsolated();
    mlKemPublicKey = newKem.publicKey;
    mlKemSecretKey = newKem.secretKey;

    keyRotatedAt = DateTime.now();
    _saveKeys(fileEnc);
    _log.info('KEM keys rotated. Previous keys kept for 7 days.');
  }

  /// Emergency full identity rotation (§26.6.2).
  /// Replaces ALL keys (Ed25519, ML-DSA, X25519, ML-KEM), recomputes Node-ID,
  /// keeps old KEM secret keys as previous for 7-day transit-message grace period.
  void rotateIdentityFull({
    required Uint8List newEd25519Pk,
    required Uint8List newEd25519Sk,
    required Uint8List newMlDsaPk,
    required Uint8List newMlDsaSk,
    required Uint8List newX25519Pk,
    required Uint8List newX25519Sk,
    required Uint8List newMlKemPk,
    required Uint8List newMlKemSk,
  }) {
    final fileEnc = FileEncryption(baseDir: _baseDir);

    // Keep old KEM secret keys for transit messages (7-day retention)
    previousX25519Sk = x25519SecretKey;
    previousMlKemSk = mlKemSecretKey;

    // Replace all keys
    ed25519PublicKey = newEd25519Pk;
    ed25519SecretKey = newEd25519Sk;
    mlDsaPublicKey = newMlDsaPk;
    mlDsaSecretKey = newMlDsaSk;
    x25519PublicKey = newX25519Pk;
    x25519SecretKey = newX25519Sk;
    mlKemPublicKey = newMlKemPk;
    mlKemSecretKey = newMlKemSk;

    keyRotatedAt = DateTime.now();

    // Recompute User-ID with new Ed25519 public key.
    // DeviceID is unchanged: it's derived from the daemon-global Device-Sig
    // keypair (§3.1, §3.5), which is independent of any User-keypair rotation.
    userId = HdWallet.computeUserId(ed25519PublicKey, NetworkSecret.secret);

    _saveKeys(fileEnc);
    _log.info('Full identity rotation complete. New User-ID: ${userIdHex.substring(0, 16)}...');
  }

  /// Discard previous keys if retention period (7 days) has passed.
  void discardPreviousKeysIfExpired() {
    if (keyRotatedAt == null || previousX25519Sk == null) return;
    if (DateTime.now().difference(keyRotatedAt!).inDays >= 7) {
      previousX25519Sk = null;
      previousMlKemSk = null;
      final fileEnc = FileEncryption(baseDir: _baseDir);
      _saveKeys(fileEnc);
      _log.info('Previous KEM keys discarded (retention expired)');
    }
  }

  /// Build a PeerInfo representing this identity.
  /// [allLocalIps] — all local IPv4 addresses (WiFi, LAN, mobile).
  /// Each is added as a PeerAddress for multi-homed connectivity.
  PeerInfo ownPeerInfo({
    required String localIp,
    required int localPort,
    String? publicIp,
    int? publicPort,
    List<String> allLocalIps = const [],
    // Welle 3 (§17.3): outer NetworkPacketV3 device_sig is signed with the
    // Device-Sig keypair, distinct from the User-Sig keypair on this
    // IdentityContext. The receiver caches these PKs and verifies subsequent
    // outer-sigs with them, so the sender MUST advertise them in its
    // self-broadcast PEER_LIST_PUSH or every receive after the first
    // lenient-bootstrap pass dies in §5.10.2 stale-PK recovery.
    Uint8List? deviceEd25519PublicKey,
    Uint8List? deviceMlDsaPublicKey,
  }) {
    // Build multi-address list from all available IPs.
    //
    // Bug C — Liveness pre-filter:
    // We previously published *every* local IP including IPv6 ULA (fc/fd…),
    // link-local (fe80::), site-local (fec0:: deprecated), and multicast
    // (ff..) — and tagged them all as IPV6_GLOBAL on the wire. That polluted
    // every other node's routing table: the bootstrap then treated a
    // home-router-assigned ULA as the highest-scored "global" address and
    // burned ACK timeouts trying to reach it.
    //
    // Single source of truth: PeerAddress.classifyIp(ip).
    // Allowed in liveness:  ipv4Public, ipv4Private, ipv6Global.
    // Skipped in liveness:  ipv6Ula, ipv6LinkLocal, ipv6SiteLocal.
    //   - ULA: meaningful only inside the issuing /48; we have no way to
    //     prove the receiver shares that prefix, so don't advertise.
    //   - Link-Local: per definition not routable beyond the segment.
    //   - Site-Local: deprecated by RFC 3879; treat like ULA.
    final addresses = <PeerAddress>[];
    for (final ip in allLocalIps) {
      final t = PeerAddress.classifyIp(ip);
      if (t == PeerAddressType.ipv6Ula ||
          t == PeerAddressType.ipv6LinkLocal ||
          t == PeerAddressType.ipv6SiteLocal) {
        continue;
      }
      addresses.add(PeerAddress(
        ip: ip,
        port: localPort,
        type: t,
      ));
    }
    if (publicIp != null && publicIp.isNotEmpty) {
      final pubPort = publicPort ?? localPort;
      final alreadyListed = addresses.any((a) => a.ip == publicIp && a.port == pubPort);
      if (!alreadyListed) {
        // Public IP is by definition routable; classify so IPv6 publics
        // get IPV6_GLOBAL not IPV4_PUBLIC.
        final t = PeerAddress.classifyIp(publicIp);
        // Defensive: if a misconfigured upstream hands us a private/ULA as
        // "public", honour the filter anyway.
        if (t != PeerAddressType.ipv6Ula &&
            t != PeerAddressType.ipv6LinkLocal &&
            t != PeerAddressType.ipv6SiteLocal) {
          addresses.add(PeerAddress(
            ip: publicIp,
            port: pubPort,
            type: t == PeerAddressType.ipv4Private
                ? PeerAddressType.ipv4Public  // upstream said public, trust the role
                : t,
          ));
        }
      }
    }

    return PeerInfo(
      nodeId: deviceNodeId,  // Phase 2: routing key = per-device ID
      userId: userId,         // Phase 2: stable identity across devices
      publicIp: publicIp ?? '',
      publicPort: publicPort ?? localPort,
      localIp: localIp,
      localPort: localPort,
      addresses: addresses,
      networkChannel: networkChannel,
      ed25519PublicKey: ed25519PublicKey,
      mlDsaPublicKey: mlDsaPublicKey,
      x25519PublicKey: x25519PublicKey,
      mlKemPublicKey: mlKemPublicKey,
      deviceEd25519PublicKey: deviceEd25519PublicKey,
      deviceMlDsaPublicKey: deviceMlDsaPublicKey,
    );
  }
}
