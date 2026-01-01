import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/crypto/per_message_kem.dart';
import 'package:cleona/core/crypto/shamir_sss.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart' show bytesToHex, hexToBytes;
import 'package:cleona/core/node/cleona_node.dart';
import 'package:cleona/core/node/identity_context.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;
import 'package:cleona/core/platform/app_paths.dart';

/// Manages Shamir Secret Sharing Guardian Recovery.
///
/// Flow A: Setup — split seed into 5 shares, send to guardians
/// Flow B: Trigger — guardian triggers restore, shows QR, notifies others
/// Flow C: Confirm — other guardians confirm and send shares
/// Flow D: Recover — user collects 3/5 shares → reconstruct seed
class GuardianService {
  final IdentityContext identity;
  final CleonaNode node;
  final String profileDir;
  final CLogger _log;
  final ShamirSSS _sss = ShamirSSS();
  final SodiumFFI _sodium = SodiumFFI();

  // Stored shares (as guardian for others)
  // Map: ownerNodeIdHex → share data (Uint8List)
  final Map<String, Uint8List> _storedShares = {};

  // Our own guardian list (node IDs of our 5 guardians)
  List<String>? _guardianNodeIds;

  // Recovery state: collected shares during restore
  final List<Uint8List> _collectedShares = [];

  // Callbacks
  void Function(String ownerName, String triggeringGuardianName, String ownerNodeIdHex, String recoveryMailboxIdHex)?
      onGuardianRestoreRequest;
  void Function(int sharesCollected, int sharesNeeded)? onRecoveryProgress;
  void Function(Uint8List masterSeed)? onRecoveryComplete;

  GuardianService({
    required this.identity,
    required this.node,
    required this.profileDir,
  }) : _log = CLogger.get('guardian', profileDir: profileDir) {
    _loadStoredShares();
    _loadGuardianList();
  }

  // ── Flow A: Setup Guardians ───────────────────────────────────────

  /// Split the master seed into 5 shares and send to guardians.
  /// [masterSeed] is the 32-byte seed to protect.
  /// [guardians] is a list of 5 accepted contacts.
  Future<bool> setupGuardians(Uint8List masterSeed, List<ContactInfo> guardians) async {
    if (guardians.length != 5) {
      _log.error('Need exactly 5 guardians, got ${guardians.length}');
      return false;
    }

    // Split seed into 5 shares (threshold 3)
    final shares = _sss.split(masterSeed, n: 5, k: 3);

    var sent = 0;
    for (var i = 0; i < 5; i++) {
      final guardian = guardians[i];
      if (guardian.x25519Pk == null || guardian.mlKemPk == null) continue;

      final msg = proto.GuardianShareStore()
        ..shareData = shares[i]
        ..ownerNodeId = identity.nodeId
        ..ownerDisplayName = identity.displayName;

      final payload = msg.writeToBuffer();
      final (kemHeader, ciphertext) = PerMessageKem.encrypt(
        plaintext: Uint8List.fromList(payload),
        recipientX25519Pk: guardian.x25519Pk!,
        recipientMlKemPk: guardian.mlKemPk!,
      );

      final envelope = identity.createSignedEnvelope(
        proto.MessageType.GUARDIAN_SHARE_STORE,
        ciphertext,
        recipientId: guardian.nodeId,
        compress: false,
      );
      envelope.kemHeader = kemHeader;

      node.sendEnvelope(envelope, guardian.nodeId);
      sent++;
    }

    // Save guardian list
    _guardianNodeIds = guardians.map((g) => g.nodeIdHex).toList();
    _saveGuardianList();

    _log.info('Guardian setup: $sent/5 shares sent');
    return sent == 5;
  }

  /// Get the list of guardian node IDs (null if not set up).
  List<String>? get guardianNodeIds => _guardianNodeIds;

  /// Whether social recovery is configured.
  bool get isSetUp => _guardianNodeIds != null && _guardianNodeIds!.length == 5;

  // ── Flow B: Handle incoming share (as guardian) ───────────────────

  /// Handle GUARDIAN_SHARE_STORE: store the share locally.
  void handleShareStore(proto.MessageEnvelope envelope, Uint8List decryptedPayload) {
    try {
      final msg = proto.GuardianShareStore.fromBuffer(decryptedPayload);
      final ownerHex = bytesToHex(Uint8List.fromList(msg.ownerNodeId));

      _storedShares[ownerHex] = Uint8List.fromList(msg.shareData);
      _saveStoredShares();

      _log.info('Stored guardian share for ${msg.ownerDisplayName} (${ownerHex.substring(0, 8)})');
    } catch (e) {
      _log.error('GUARDIAN_SHARE_STORE failed: $e');
    }
  }

  // ── Flow B: Trigger restore (guardian side) ───────────────────────

  /// Trigger a guardian restore for a contact.
  /// Returns QR data (share + peer addresses + own node ID) or null on failure.
  /// Also sends GUARDIAN_RESTORE_REQUEST to the other guardians.
  Map<String, dynamic>? triggerGuardianRestore(
    String ownerNodeIdHex,
    String ownerDisplayName,
    List<ContactInfo> allContacts,
  ) {
    final share = _storedShares[ownerNodeIdHex];
    if (share == null) {
      _log.warn('No stored share for $ownerNodeIdHex');
      return null;
    }

    // Build recovery mailbox ID (deterministic from owner's node ID)
    final recoveryMailboxId = _sodium.sha256(Uint8List.fromList([
      ...'guardian-recovery'.codeUnits,
      ...hexToBytes(ownerNodeIdHex),
    ]));

    // Build QR data
    final peers = node.routingTable.allPeers.take(3).toList();
    final qrData = {
      'type': 'guardian_restore',
      'share': base64Encode(share),
      'guardian_node_id': identity.userIdHex,
      'recovery_mailbox_id': bytesToHex(recoveryMailboxId),
      'peers': peers.map((p) => '${p.publicIp}:${p.publicPort}').toList(),
    };

    // Send GUARDIAN_RESTORE_REQUEST to other guardians who have shares
    // (We don't know who the other guardians are, but we can send to all contacts
    // who might be guardians — they'll ignore the request if they don't have a share)
    final request = proto.GuardianRestoreRequest()
      ..ownerNodeId = hexToBytes(ownerNodeIdHex)
      ..ownerDisplayName = ownerDisplayName
      ..triggeringGuardianNodeId = identity.nodeId
      ..triggeringGuardianName = identity.displayName
      ..recoveryMailboxId = recoveryMailboxId;

    final requestBytes = request.writeToBuffer();
    var notified = 0;
    for (final contact in allContacts) {
      if (contact.status != 'accepted') continue;
      if (contact.nodeIdHex == ownerNodeIdHex) continue; // Skip the owner
      if (contact.nodeIdHex == identity.userIdHex) continue; // Skip self
      if (contact.x25519Pk == null || contact.mlKemPk == null) continue;

      final (kemHeader, ciphertext) = PerMessageKem.encrypt(
        plaintext: Uint8List.fromList(requestBytes),
        recipientX25519Pk: contact.x25519Pk!,
        recipientMlKemPk: contact.mlKemPk!,
      );

      final envelope = identity.createSignedEnvelope(
        proto.MessageType.GUARDIAN_RESTORE_REQUEST,
        ciphertext,
        recipientId: contact.nodeId,
        compress: false,
      );
      envelope.kemHeader = kemHeader;

      node.sendEnvelope(envelope, contact.nodeId);
      notified++;
    }

    _log.info('Guardian restore triggered for $ownerDisplayName: QR ready, $notified contacts notified');
    return qrData;
  }

  // ── Flow C: Handle restore request (other guardian side) ──────────

  /// Handle GUARDIAN_RESTORE_REQUEST: show pop-up to user.
  void handleRestoreRequest(proto.MessageEnvelope envelope, Uint8List decryptedPayload) {
    try {
      final msg = proto.GuardianRestoreRequest.fromBuffer(decryptedPayload);
      final ownerHex = bytesToHex(Uint8List.fromList(msg.ownerNodeId));

      // Only process if we have a share for this owner
      if (!_storedShares.containsKey(ownerHex)) {
        _log.debug('GUARDIAN_RESTORE_REQUEST for unknown owner ${ownerHex.substring(0, 8)}, ignoring');
        return;
      }

      final recoveryMailboxHex = bytesToHex(Uint8List.fromList(msg.recoveryMailboxId));

      _log.info('Guardian restore request for ${msg.ownerDisplayName} from ${msg.triggeringGuardianName}');

      // Trigger callback → GUI shows pop-up
      onGuardianRestoreRequest?.call(
        msg.ownerDisplayName,
        msg.triggeringGuardianName,
        ownerHex,
        recoveryMailboxHex,
      );
    } catch (e) {
      _log.error('GUARDIAN_RESTORE_REQUEST failed: $e');
    }
  }

  /// Confirm a guardian restore request: send our share to the recovery mailbox.
  Future<bool> confirmRestore(String ownerNodeIdHex, String recoveryMailboxIdHex) async {
    final share = _storedShares[ownerNodeIdHex];
    if (share == null) return false;

    final response = proto.GuardianRestoreResponse()
      ..shareData = share
      ..ownerNodeId = hexToBytes(ownerNodeIdHex);

    // Send to recovery mailbox via erasure coding (same as offline delivery)
    final envelope = identity.createSignedEnvelope(
      proto.MessageType.GUARDIAN_RESTORE_RESPONSE,
      response.writeToBuffer(),
      recipientId: hexToBytes(ownerNodeIdHex),
    );

    // Store in DHT near the recovery mailbox
    final recoveryMailboxId = hexToBytes(recoveryMailboxIdHex);
    final peers = node.routingTable.findClosestPeers(recoveryMailboxId, count: 10);

    final fragStore = proto.FragmentStore()
      ..mailboxId = recoveryMailboxId
      ..messageId = Uint8List.fromList(envelope.messageId)
      ..fragmentIndex = 0
      ..totalFragments = 1
      ..requiredFragments = 1
      ..fragmentData = envelope.writeToBuffer()
      ..originalSize = envelope.writeToBuffer().length;

    var sent = 0;
    for (final peer in peers) {
      final fragEnv = identity.createSignedEnvelope(
        proto.MessageType.FRAGMENT_STORE,
        fragStore.writeToBuffer(),
        recipientId: peer.nodeId,
      );
      node.transport.sendUdp(fragEnv, InternetAddress(peer.publicIp), peer.publicPort);
      sent++;
    }

    _log.info('Guardian restore confirmed for ${ownerNodeIdHex.substring(0, 8)}: share sent to $sent peers');
    return sent > 0;
  }

  // ── Flow D: Collect shares (recovering user side) ─────────────────

  /// Parse a QR code scanned from a guardian.
  /// Returns parsed data or null.
  static Map<String, dynamic>? parseQrData(String qrContent) {
    try {
      final data = jsonDecode(qrContent) as Map<String, dynamic>;
      if (data['type'] != 'guardian_restore') return null;
      return data;
    } catch (_) {
      return null;
    }
  }

  /// Add a share from QR scan or network delivery.
  /// Returns true if we now have enough shares (3/5) to reconstruct.
  bool addShare(Uint8List shareData) {
    // Check for duplicate (same index)
    final index = shareData[0];
    if (_collectedShares.any((s) => s[0] == index)) {
      _log.debug('Duplicate share with index $index, ignoring');
      return _collectedShares.length >= 3;
    }

    _collectedShares.add(shareData);
    _log.info('Share collected: ${_collectedShares.length}/3 needed');

    onRecoveryProgress?.call(_collectedShares.length, 3);

    if (_collectedShares.length >= 3) {
      _tryReconstruct();
      return true;
    }
    return false;
  }

  /// Handle GUARDIAN_RESTORE_RESPONSE received via mailbox.
  void handleRestoreResponse(proto.MessageEnvelope envelope) {
    try {
      final msg = proto.GuardianRestoreResponse.fromBuffer(envelope.encryptedPayload);
      addShare(Uint8List.fromList(msg.shareData));
    } catch (e) {
      _log.error('GUARDIAN_RESTORE_RESPONSE failed: $e');
    }
  }

  /// Try to reconstruct the master seed from collected shares.
  void _tryReconstruct() {
    if (_collectedShares.length < 3) return;

    try {
      final seed = _sss.reconstruct(_collectedShares.take(3).toList());
      _log.info('Master seed reconstructed from ${_collectedShares.length} shares!');
      onRecoveryComplete?.call(seed);
    } catch (e) {
      _log.error('Seed reconstruction failed: $e');
      // Try with more shares if available
      if (_collectedShares.length > 3) {
        try {
          final seed = _sss.reconstruct(_collectedShares);
          _log.info('Reconstructed with ${_collectedShares.length} shares');
          onRecoveryComplete?.call(seed);
        } catch (e2) {
          _log.error('Reconstruction failed with all shares: $e2');
        }
      }
    }
  }

  /// Number of shares collected so far.
  int get collectedShareCount => _collectedShares.length;

  /// Reset recovery state.
  void resetRecovery() {
    _collectedShares.clear();
  }

  // ── Persistence ───────────────────────────────────────────────────

  FileEncryption get _fileEnc {
    return FileEncryption(baseDir: '${AppPaths.home}/.cleona');
  }

  void _loadStoredShares() {
    try {
      final json = _fileEnc.readJsonFile('$profileDir/guardian_shares.json');
      if (json == null) return;
      for (final entry in json.entries) {
        if (entry.key.startsWith('_')) continue;
        _storedShares[entry.key] = base64Decode(entry.value as String);
      }
      _log.info('Loaded ${_storedShares.length} guardian shares');
    } catch (e) {
      _log.debug('No guardian shares to load: $e');
    }
  }

  void _saveStoredShares() {
    try {
      final json = <String, dynamic>{};
      for (final entry in _storedShares.entries) {
        json[entry.key] = base64Encode(entry.value);
      }
      _fileEnc.writeJsonFile('$profileDir/guardian_shares.json', json);
    } catch (e) {
      _log.warn('Failed to save guardian shares: $e');
    }
  }

  void _loadGuardianList() {
    try {
      final json = _fileEnc.readJsonFile('$profileDir/guardian_list.json');
      if (json == null) return;
      final list = json['guardians'] as List<dynamic>?;
      if (list != null && list.length == 5) {
        _guardianNodeIds = list.cast<String>();
      }
    } catch (_) {}
  }

  void _saveGuardianList() {
    try {
      _fileEnc.writeJsonFile('$profileDir/guardian_list.json', {
        'guardians': _guardianNodeIds,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      _log.warn('Failed to save guardian list: $e');
    }
  }
}
