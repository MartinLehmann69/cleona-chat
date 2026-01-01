import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/erasure/erasure_placement.dart';
import 'package:cleona/core/crypto/hd_wallet.dart';
import 'package:cleona/core/crypto/shamir_sss.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/dht/kbucket.dart' show RoutingTable;
import 'package:cleona/core/network/peer_info.dart' show PeerInfo, bytesToHex, hexToBytes;
import 'package:cleona/core/network/clogger.dart';
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

  /// Injected by CleonaService: sends FRAGMENT_STORE and waits for ACK.
  /// Returns true if ACK received within timeout, false on timeout.
  Future<bool> Function(Uint8List fragStoreBytes, Uint8List messageId,
      int fragmentIndex, Uint8List recipientDeviceId)? sendFragmentStoreWithAck;

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
      final msg = proto.GuardianShareStore()
        ..shareData = shares[i]
        ..ownerNodeId = identity.nodeId
        ..ownerDisplayName = identity.displayName;
      final payload = Uint8List.fromList(msg.writeToBuffer());

      // §3.1: guardian may have multiple devices — send to all known ones.
      var deviceIds = guardian.deviceNodeIds.map(hexToBytes).toList();
      if (deviceIds.isEmpty) {
        deviceIds = await node.resolveUserToDevices(guardian.nodeId);
      }
      if (deviceIds.isEmpty) {
        _log.warn('setupGuardians: ${guardian.displayName} has no known devices');
        continue;
      }
      var guardianSent = false;
      for (final deviceId in deviceIds) {
        final ok = await node.sendInfraTo(
          messageType: proto.MessageTypeV3.MTV3_GUARDIAN_SHARE_STORE,
          innerPayload: payload,
          recipientDeviceId: deviceId,
        );
        if (ok) guardianSent = true;
      }
      if (guardianSent) sent++;
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
  ///
  /// V3-direct: [payload] is the plain `GuardianShareStore` proto bytes
  /// from an `InfrastructureFrameV3` whose Device-KEM encap was already
  /// verified by the V3 receive pipeline (§6.2 + §2.3.5). The frame has
  /// no inner KEM wrap — the frame-level encap is the only confidentiality
  /// layer.
  void handleShareStore(Uint8List payload) {
    try {
      final msg = proto.GuardianShareStore.fromBuffer(payload);
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

      // §3.1: contact may have multiple devices — best-effort to all.
      final deviceIds = contact.deviceNodeIds.map(hexToBytes).toList();
      if (deviceIds.isEmpty) {
        _log.debug('triggerGuardianRestore: ${contact.displayName} has no '
            'known deviceNodeIds, skipping');
        continue;
      }
      for (final deviceId in deviceIds) {
        // ignore: unawaited_futures
        node.sendInfraTo(
          messageType: proto.MessageTypeV3.MTV3_GUARDIAN_RESTORE_REQUEST,
          innerPayload: Uint8List.fromList(requestBytes),
          recipientDeviceId: deviceId,
        );
      }
      notified++;
    }

    _log.info('Guardian restore triggered for $ownerDisplayName: QR ready, $notified contacts notified');
    return qrData;
  }

  // ── Flow C: Handle restore request (other guardian side) ──────────

  /// Handle GUARDIAN_RESTORE_REQUEST: show pop-up to user.
  ///
  /// V3-direct: [payload] is the plain `GuardianRestoreRequest` proto bytes
  /// from an `InfrastructureFrameV3` whose Device-KEM encap was already
  /// verified by the V3 receive pipeline (§6.2 + §2.3.5). Recipients that
  /// do not hold a stored share for the named owner silently drop below.
  void handleRestoreRequest(Uint8List payload) {
    try {
      final msg = proto.GuardianRestoreRequest.fromBuffer(payload);
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
    final responseBytes = response.writeToBuffer();

    // Store in DHT near the recovery mailbox so the recovering owner —
    // who is offline and has only the recovery-mailbox-id (derived from
    // their own old node-id) plus a few bootstrap peer addresses from
    // the QR code — can later FRAGMENT_RETRIEVE the share.
    //
    // Outer transport is MTV3_FRAGMENT_STORE on InfrastructureFrame.
    // Inner fragmentData holds the raw GuardianRestoreResponse bytes;
    // on retrieval the recovering side parses fragmentData directly via
    // GuardianRestoreResponse.fromBuffer (see `handleRestoreResponse`
    // — TODO when the recovering side wires the V3 retrieve path it
    // must adapt to the un-wrapped payload shape).
    final recoveryMailboxId = hexToBytes(recoveryMailboxIdHex);
    // D4 (§4.3): subnet-diverse replicator selection.
    final peers = node.routingTable.findClosestPeers(recoveryMailboxId,
        count: 10, maxPerIpGroup: RoutingTable.diversityMaxPerIpGroup);

    // Synthesize a deterministic messageId for the FragmentStore so the
    // recovering side can de-dup across peers (hashed from
    // recipient + responseBytes).
    final messageId = _sodium.sha256(Uint8List.fromList([
      ...recoveryMailboxId,
      ...responseBytes,
    ])).sublist(0, 16);

    final fragStore = proto.FragmentStore()
      ..mailboxId = recoveryMailboxId
      ..messageId = messageId
      ..fragmentIndex = 0
      ..totalFragments = 1
      ..requiredFragments = 1
      ..fragmentData = responseBytes
      ..originalSize = responseBytes.length;
    final fragStoreBytes = Uint8List.fromList(fragStore.writeToBuffer());

    final ackSender = sendFragmentStoreWithAck;
    if (ackSender == null) {
      // Fallback: fire-and-forget (legacy path, should not happen after wiring)
      var sent = 0;
      for (final peer in peers) {
        final ok = await node.sendInfraTo(
          messageType: proto.MessageTypeV3.MTV3_FRAGMENT_STORE,
          innerPayload: fragStoreBytes,
          recipientDeviceId: Uint8List.fromList(peer.nodeId),
        );
        if (ok) sent++;
      }
      _log.warn('Guardian restore for ${ownerNodeIdHex.substring(0, 8)}: fire-and-forget ($sent sends, no ACK)');
      return sent > 0;
    }

    final coordinator = ErasurePlacementCoordinator<PeerInfo>(
      totalFragments: 1,
      requiredFragments: 1,
      peerId: (p) => bytesToHex(Uint8List.fromList(p.nodeId)),
      initialReplicaCount: 3,
      maxRetryWaves: 2,
    );
    final result = await coordinator.run(
      initialPool: peers,
      deeperPool: () => node.routingTable.findClosestPeers(recoveryMailboxId,
          count: 30, maxPerIpGroup: RoutingTable.diversityMaxPerIpGroup),
      sendAndWait: (fragmentIndex, peer) =>
          ackSender(fragStoreBytes, messageId, fragmentIndex, Uint8List.fromList(peer.nodeId)),
    );

    if (result.success) {
      _log.info('Guardian restore confirmed for ${ownerNodeIdHex.substring(0, 8)}: ACK-verified');
    } else {
      _log.warn('Guardian restore for ${ownerNodeIdHex.substring(0, 8)}: placement FAILED');
    }
    return result.success;
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
  ///
  /// V3-direct: [payload] is the plain `GuardianRestoreResponse` proto
  /// bytes. Two arrival paths converge here:
  ///   1. DHT FRAGMENT_RETRIEVE — `FragmentStore.fragmentData` carries the
  ///      response bytes verbatim (see `confirmRestore` above).
  ///   2. Direct InfraFrame (future) — `InfrastructureFrameV3.payload`
  ///      whose Device-KEM encap was verified upstream.
  void handleRestoreResponse(Uint8List payload) {
    try {
      final msg = proto.GuardianRestoreResponse.fromBuffer(payload);
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
    final baseDir = '${AppPaths.home}/.cleona';
    final seed = identity.masterSeed;
    final idx = identity.hdIndex;
    final Uint8List? key = (seed != null && idx != null)
        ? HdWallet.deriveFileEncKey(seed, idx)
        : null;
    return FileEncryption(baseDir: baseDir, key: key);
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
