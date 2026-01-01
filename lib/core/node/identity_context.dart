import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/crypto/hd_wallet.dart';
import 'package:cleona/core/crypto/network_secret.dart';
import 'package:cleona/core/crypto/pq_isolate.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/compression.dart';
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/core/platform/app_paths.dart';
import 'package:fixnum/fixnum.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

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

  /// Device-Node-ID: unique per device = SHA-256(network_secret + ed25519_pk + device_uuid).
  /// Used for network routing, DHT registration, routing table entries.
  late Uint8List deviceNodeId;

  /// Device UUID (16 bytes, generated once per device, persisted).
  late Uint8List deviceUuid;

  // ── 2D-DHT Identity Resolution: persistierte seq-Counter ──────────
  // Plan: docs/superpowers/plans/2026-04-26-2d-dht-identity-resolution.md (Task 4)
  // Persistiert in `<profileDir>/identity_resolution.json[.enc]`.
  // Auth-Seq und Liveness-Seq sind bewusst getrennt (verschiedene TTLs / Update-Frequenzen).
  int _authManifestSeq = 0;
  int _livenessSeq = 0;
  Uint8List? _lastAuthManifestContentHash;

  int get authManifestSeq => _authManifestSeq;
  int get livenessSeq => _livenessSeq;
  Uint8List? get lastAuthManifestContentHash => _lastAuthManifestContentHash;

  int bumpAuthManifestSeq() => ++_authManifestSeq;
  int bumpLivenessSeq() => ++_livenessSeq;

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

    // Load or generate Device UUID (persisted per device)
    deviceUuid = _loadOrCreateDeviceUuid(fileEnc);

    // Compute Device-Node-ID: SHA-256(network_secret + ed25519_pk + device_uuid) — routing
    deviceNodeId = HdWallet.computeDeviceNodeId(ed25519PublicKey, NetworkSecret.secret, deviceUuid);

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

  /// Load device UUID from disk, or generate a new one.
  /// Stored alongside keys but NOT rotated — it's the device's permanent identity.
  Uint8List _loadOrCreateDeviceUuid(FileEncryption fileEnc) {
    final uuidFile = File('$profileDir/device_uuid');
    if (uuidFile.existsSync()) {
      final hex = uuidFile.readAsStringSync().trim();
      if (hex.length == 32) return hexToBytes(hex);
    }
    // Generate new UUID (16 bytes)
    final uuid = SodiumFFI().randomBytes(16);
    uuidFile.parent.createSync(recursive: true);
    uuidFile.writeAsStringSync(bytesToHex(uuid));
    _log.info('New device UUID generated: ${bytesToHex(uuid).substring(0, 8)}...');
    return uuid;
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

    // Recompute User-ID and Device-Node-ID with new Ed25519 public key
    userId = HdWallet.computeUserId(ed25519PublicKey, NetworkSecret.secret);
    deviceNodeId = HdWallet.computeDeviceNodeId(ed25519PublicKey, NetworkSecret.secret, deviceUuid);

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

  /// Create and sign a message envelope.
  /// Payloads >= 64 bytes are zstd-compressed automatically.
  ///
  /// [senderIdOverride]: when set, used in place of the current `userId` as
  /// `envelope.senderId`. Needed by §26.6.2 Paket C so the emergency
  /// key-rotation retry keeps the receiver's pre-rotation contact-lookup hex
  /// after the local `userId` has already flipped to the new one.
  /// The envelope is still signed with the *current* Ed25519 key — the inner
  /// dual-signature is what authenticates the rotation itself.
  proto.MessageEnvelope createSignedEnvelope(
    proto.MessageType type,
    Uint8List payload, {
    Uint8List? recipientId,
    bool compress = true,
    Uint8List? senderIdOverride,
  }) {
    // Compress payload if beneficial (>= 64 bytes)
    Uint8List effectivePayload = payload;
    var compression = proto.CompressionType.NONE;
    if (compress && payload.length >= 64 && !_isEphemeralMediaType(type)) {
      try {
        final compressed = ZstdCompression.instance.compress(payload);
        if (compressed.length < payload.length) {
          effectivePayload = compressed;
          compression = proto.CompressionType.ZSTD;
        }
      } catch (_) {
        // Compression failed, send uncompressed
      }
    }

    final envelope = proto.MessageEnvelope()
      ..version = 1
      ..senderId = senderIdOverride ?? userId  // Stable identity (contact lookup)
      ..senderDeviceNodeId = deviceNodeId  // For routing replies/receipts back
      ..timestamp = Int64(DateTime.now().millisecondsSinceEpoch)
      ..messageType = type
      ..networkTag = networkChannel
      ..compression = compression
      ..encryptedPayload = effectivePayload;
    if (recipientId != null) envelope.recipientId = recipientId;

    // Generate message ID
    final sodium = SodiumFFI();
    envelope.messageId = sodium.randomBytes(16);

    // Sign with Ed25519
    final dataToSign = envelope.writeToBuffer();
    envelope.signatureEd25519 = sodium.signEd25519(dataToSign, ed25519SecretKey);

    // Sign with ML-DSA (skip for infrastructure messages — inner payload already has dual signatures)
    // Also skip for ephemeral media frames (CALL_AUDIO/CALL_VIDEO) — see _isEphemeralMediaType.
    if (!_isInfrastructureType(type) && !_isEphemeralMediaType(type)) {
      final oqs = OqsFFI();
      envelope.signatureMlDsa = oqs.mlDsaSign(dataToSign, mlDsaSecretKey);
    }

    return envelope;
  }

  /// Infrastructure message types that only need Ed25519 (not ML-DSA).
  /// These are routing/relay messages where the inner payload already has
  /// full dual signatures. Skipping ML-DSA saves ~3.3KB per hop, critical
  /// for mobile delivery where UDP fragments get lost.
  static bool _isInfrastructureType(proto.MessageType type) {
    switch (type) {
      case proto.MessageType.RELAY_FORWARD:
      case proto.MessageType.RELAY_ACK:
      case proto.MessageType.DHT_PING:
      case proto.MessageType.DHT_PONG:
      case proto.MessageType.DHT_FIND_NODE:
      case proto.MessageType.DHT_FIND_NODE_RESPONSE:
      case proto.MessageType.DHT_STORE:
      case proto.MessageType.DHT_STORE_RESPONSE:
      case proto.MessageType.DHT_FIND_VALUE:
      case proto.MessageType.DHT_FIND_VALUE_RESPONSE:
      case proto.MessageType.ROUTE_UPDATE:
      case proto.MessageType.PEER_LIST_PUSH:
      case proto.MessageType.PEER_STORE:
      case proto.MessageType.PEER_STORE_ACK:
      case proto.MessageType.PEER_RETRIEVE:
      case proto.MessageType.PEER_RETRIEVE_RESPONSE:
      case proto.MessageType.REACHABILITY_QUERY:
      case proto.MessageType.REACHABILITY_RESPONSE:
      case proto.MessageType.HOLE_PUNCH_REQUEST:
      case proto.MessageType.HOLE_PUNCH_NOTIFY:
      case proto.MessageType.HOLE_PUNCH_PING:
      case proto.MessageType.HOLE_PUNCH_PONG:
        return true;
      default:
        return false;
    }
  }

  /// Ephemeral media types — Live-Stream-Frames (Audio/Video) im aktiven Call.
  /// Authentifizierung läuft über den Call-Setup-Handshake (CALL_INVITE/ANSWER
  /// mit voller Hybrid-Signatur + KEM-Etablierung von callKey). Pro-Frame
  /// AES-GCM mit callKey + Ed25519-Signatur reichen für Authentizität +
  /// Identitätsbeweis. ML-DSA pro Frame ist redundant: callKey ist bereits
  /// post-quantum sicher etabliert, jeder Frame mit callKey damit auch.
  /// Skip spart 500 µs CPU + 3.3 KB Wire-Bytes pro Frame, kritisch für
  /// Mobilfunk-Delivery wo UDP-Fragmente verloren gehen.
  ///
  /// Audit (2026-04-25): Receiver-Side `mlDsaVerify` wird heute nirgendwo
  /// aufgerufen (siehe grep "mlDsaVerify" in lib/) — dieser Skip ist also
  /// auch ohne symmetrischen Receiver-Update sicher.
  static bool _isEphemeralMediaType(proto.MessageType type) {
    switch (type) {
      case proto.MessageType.CALL_AUDIO:
      case proto.MessageType.CALL_VIDEO:
        return true;
      default:
        return false;
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
  }) {
    // Build multi-address list from all available IPs
    final addresses = <PeerAddress>[];
    for (final ip in allLocalIps) {
      addresses.add(PeerAddress(
        ip: ip,
        port: localPort,
        type: ip.contains(':') ? PeerAddressType.ipv6Global
            : _isPrivateIpAddr(ip) ? PeerAddressType.ipv4Private : PeerAddressType.ipv4Public,
      ));
    }
    if (publicIp != null && publicIp.isNotEmpty) {
      final pubPort = publicPort ?? localPort;
      final alreadyListed = addresses.any((a) => a.ip == publicIp && a.port == pubPort);
      if (!alreadyListed) {
        addresses.add(PeerAddress(
          ip: publicIp,
          port: pubPort,
          type: PeerAddressType.ipv4Public,
        ));
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
      x25519PublicKey: x25519PublicKey,
      mlKemPublicKey: mlKemPublicKey,
    );
  }

  static bool _isPrivateIpAddr(String ip) {
    if (ip.contains(':')) {
      final lower = ip.toLowerCase();
      return lower.startsWith('fe80:') || lower.startsWith('fc') ||
             lower.startsWith('fd') || lower == '::1';
    }
    if (ip.startsWith('192.168.')) return true;
    if (ip.startsWith('10.')) return true;
    if (ip.startsWith('172.')) {
      final second = int.tryParse(ip.split('.')[1]);
      if (second != null && second >= 16 && second <= 31) return true;
    }
    if (ip.startsWith('100.')) {
      final second = int.tryParse(ip.split('.')[1]) ?? 0;
      if (second >= 64 && second <= 127) return true;
    }
    if (ip.startsWith('192.0.0.')) return true;
    return false;
  }
}
