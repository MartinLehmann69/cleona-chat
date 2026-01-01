import 'dart:async';
import 'dart:typed_data';

import 'package:cleona/core/crypto/per_message_kem.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:fixnum/fixnum.dart';
import 'package:cleona/core/erasure/reed_solomon.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/core/dht/mailbox_store.dart';
import 'package:cleona/core/node/cleona_node.dart';
import 'package:cleona/core/node/identity_context.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Message delivery status tracking.
enum MessageStatus {
  queued,
  sent,
  storedInNetwork,
  delivered,
  read,
  failed,
}

/// Tracks the delivery state of a single message.
class MessageDeliveryState {
  final String messageIdHex;
  final Uint8List recipientNodeId;
  MessageStatus status;
  int ackedFragments;
  final int totalFragments;
  DateTime lastUpdate;

  MessageDeliveryState({
    required this.messageIdHex,
    required this.recipientNodeId,
    this.status = MessageStatus.queued,
    this.ackedFragments = 0,
    this.totalFragments = ReedSolomon.defaultN,
  }) : lastUpdate = DateTime.now();
}

/// Contact manager interface for public key lookup.
/// Implemented by the application layer.
abstract class ContactKeyLookup {
  /// Look up a contact's ed25519 public key by node ID.
  Uint8List? getEd25519Pk(Uint8List nodeId);

  /// Look up a contact's x25519 public key by node ID.
  Uint8List? getX25519Pk(Uint8List nodeId);

  /// Look up a contact's ML-KEM public key by node ID.
  Uint8List? getMlKemPk(Uint8List nodeId);
}

/// Dual-delivery message sender: direct UDP push + erasure-coded DHT backup.
///
/// For every non-ephemeral message:
/// 1. Encrypt with Per-Message KEM (if applicable)
/// 2. Create signed envelope
/// 3. Direct-send via UDP to all known addresses of the recipient
/// 4. Erasure-code the envelope and distribute fragments to DHT peers
class MessageSender {
  final CleonaNode node;
  final IdentityContext identity;
  final ContactKeyLookup contactManager;
  final MailboxStore mailboxStore;
  final CLogger _log;
  final SodiumFFI _sodium = SodiumFFI();

  /// Status callback — fired on every status transition.
  void Function(String messageIdHex, MessageStatus status)? onStatusChanged;

  /// Active delivery states indexed by messageIdHex.
  final Map<String, MessageDeliveryState> _deliveryStates = {};

  /// Fragment TTL for DHT storage (7 days).
  static const Duration fragmentTtl = Duration(days: 7);

  /// Minimum required ACKs before considering fragments stored.
  static const int minAcksForStored = 5;

  MessageSender({
    required this.node,
    required this.identity,
    required this.contactManager,
    required this.mailboxStore,
  }) : _log = CLogger.get('msg-sender', profileDir: node.profileDir);

  /// Send a message to a recipient.
  ///
  /// [recipientNodeId] — 32-byte node ID of the recipient.
  /// [messageType] — protobuf message type enum.
  /// [payload] — plaintext payload bytes.
  /// [encrypt] — whether to apply Per-Message KEM encryption (default true).
  ///
  /// Returns the hex-encoded message ID on success, null on failure.
  Future<String?> sendMessage(
    Uint8List recipientNodeId,
    proto.MessageType messageType,
    Uint8List payload, {
    bool encrypt = true,
  }) async {
    final shouldDoEncrypt = encrypt && PerMessageKem.shouldEncrypt(messageType);
    final isEphemeral = PerMessageKem.isEphemeral(messageType);

    Uint8List effectivePayload = payload;
    proto.PerMessageKem? kemHeader;

    // ── Step 1: Encrypt if needed ──────────────────────────────────────
    if (shouldDoEncrypt) {
      final x25519Pk = _lookupX25519Pk(recipientNodeId);
      final mlKemPk = _lookupMlKemPk(recipientNodeId);

      if (x25519Pk == null || mlKemPk == null) {
        _log.warn('Cannot encrypt: missing PK for ${bytesToHex(recipientNodeId).substring(0, 8)}');
        return null;
      }

      final (header, ciphertext) = PerMessageKem.encrypt(
        plaintext: payload,
        recipientX25519Pk: x25519Pk,
        recipientMlKemPk: mlKemPk,
      );
      kemHeader = header;
      effectivePayload = ciphertext;
    }

    // ── Step 2: Create signed envelope ─────────────────────────────────
    final envelope = identity.createSignedEnvelope(
      messageType,
      effectivePayload,
      recipientId: recipientNodeId,
    );
    if (kemHeader != null) {
      envelope.kemHeader = kemHeader;
    }

    final messageId = Uint8List.fromList(envelope.messageId);
    final messageIdHex = bytesToHex(messageId);
    _log.info('Sending ${messageType.name} to ${bytesToHex(recipientNodeId).substring(0, 8)}.. '
        'msgId=${messageIdHex.substring(0, 8)}.. encrypt=$shouldDoEncrypt ephemeral=$isEphemeral');

    // ── Step 3: Track delivery state ───────────────────────────────────
    final state = MessageDeliveryState(
      messageIdHex: messageIdHex,
      recipientNodeId: recipientNodeId,
    );
    _deliveryStates[messageIdHex] = state;
    _updateStatus(state, MessageStatus.queued);

    // ── Step 4: Direct send via UDP (V3: no TCP in the normal path) ──
    final directSuccess = await node.sendEnvelope(envelope, recipientNodeId);
    if (directSuccess) {
      _updateStatus(state, MessageStatus.sent);
      _log.debug('Direct send OK: ${messageIdHex.substring(0, 8)}');
    } else {
      _log.debug('Direct send failed (peer offline?): ${messageIdHex.substring(0, 8)}');
    }

    // ── Step 5: Erasure-coded backup (non-ephemeral only) ──────────────
    if (!isEphemeral) {
      try {
        final mailboxId = _computeMailboxId(recipientNodeId);
        final envelopeBytes = Uint8List.fromList(envelope.writeToBuffer());
        final rs = ReedSolomon();
        final fragments = envelopeBytes.length > ReedSolomon.streamingThreshold
            ? rs.encodeStreaming(envelopeBytes)
            : rs.encode(envelopeBytes);

        _log.debug('Erasure-coded ${envelopeBytes.length} bytes into '
            '${fragments.length} fragments for mailbox ${bytesToHex(mailboxId).substring(0, 8)}');

        // Store fragments in DHT (fire-and-forget, ACKs tracked async)
        unawaited(_storeFragments(mailboxId, messageId, fragments, envelopeBytes.length));
      } catch (e) {
        _log.warn('Erasure coding failed for ${messageIdHex.substring(0, 8)}: $e');
      }
    }

    return messageIdHex;
  }

  /// Compute the mailbox ID for a recipient.
  ///
  /// Primary: SHA-256("mailbox" + ed25519Pk) — stable, PK-based.
  /// Fallback: SHA-256("mailbox-nid" + nodeId) — if PK unknown.
  Uint8List _computeMailboxId(Uint8List recipientNodeId) {
    // Try PK lookup chain: routing table -> contactManager -> fallback
    Uint8List? ed25519Pk;

    // 1. Check routing table
    final peer = node.routingTable.getPeer(recipientNodeId);
    if (peer?.ed25519PublicKey != null && peer!.ed25519PublicKey!.isNotEmpty) {
      ed25519Pk = peer.ed25519PublicKey!;
    }

    // 2. Check contactManager
    ed25519Pk ??= contactManager.getEd25519Pk(recipientNodeId);

    if (ed25519Pk != null) {
      // Primary: SHA-256("mailbox" + ed25519Pk)
      final prefix = Uint8List.fromList('mailbox'.codeUnits);
      final combined = Uint8List(prefix.length + ed25519Pk.length);
      combined.setRange(0, prefix.length, prefix);
      combined.setRange(prefix.length, combined.length, ed25519Pk);
      return _sodium.sha256(combined);
    }

    // Fallback: SHA-256("mailbox-nid" + nodeId)
    _log.debug('Using nodeId-based mailbox for ${bytesToHex(recipientNodeId).substring(0, 8)}');
    final prefix = Uint8List.fromList('mailbox-nid'.codeUnits);
    final combined = Uint8List(prefix.length + recipientNodeId.length);
    combined.setRange(0, prefix.length, prefix);
    combined.setRange(prefix.length, combined.length, recipientNodeId);
    return _sodium.sha256(combined);
  }

  /// Distribute erasure-coded fragments to the closest peers for the mailbox ID.
  /// Uses cascading retry: if the preferred peer doesn't ACK, tries the next
  /// closest peer. Ensures fragments are stored even when some peers are unreachable.
  Future<void> _storeFragments(
    Uint8List mailboxId,
    Uint8List messageId,
    List<Uint8List> fragments,
    int originalSize,
  ) async {
    final messageIdHex = bytesToHex(messageId);
    final state = _deliveryStates[messageIdHex];

    // Find peers closest to the mailbox ID in the DHT
    final closestPeers = node.routingTable.findClosestPeers(mailboxId, count: 20);
    if (closestPeers.isEmpty) {
      _log.warn('No peers to store fragments for ${messageIdHex.substring(0, 8)}');
      return;
    }

    _log.debug('Distributing ${fragments.length} fragments to '
        '${closestPeers.length} candidates for ${messageIdHex.substring(0, 8)}');

    var ackedCount = 0;

    for (var i = 0; i < fragments.length; i++) {
      final fragStore = proto.FragmentStore()
        ..mailboxId = mailboxId
        ..messageId = messageId
        ..fragmentIndex = i
        ..totalFragments = fragments.length
        ..requiredFragments = ReedSolomon.defaultK
        ..fragmentData = fragments[i]
        ..originalSize = originalSize
        ..ttlMs = Int64(fragmentTtl.inMilliseconds);
      final fragBytes = Uint8List.fromList(fragStore.writeToBuffer());

      // Cascading retry: try peers in order until one ACKs
      var stored = false;
      // Start with the preferred peer (round-robin), then try others
      final preferredIdx = i % closestPeers.length;
      for (var attempt = 0; attempt < closestPeers.length && !stored; attempt++) {
        final peerIdx = (preferredIdx + attempt) % closestPeers.length;
        final targetPeer = closestPeers[peerIdx];

        final envelope = identity.createSignedEnvelope(
          proto.MessageType.FRAGMENT_STORE,
          fragBytes,
          recipientId: targetPeer.nodeId,
        );

        final ackResponse = await node.dhtRpc.sendAndWait(
          envelope,
          targetPeer,
          timeout: const Duration(seconds: 3),
        );

        if (ackResponse != null) {
          stored = true;
          ackedCount++;
          if (state != null) {
            state.ackedFragments = ackedCount;
          }
          _log.debug('Fragment $i/${fragments.length} ACKed by '
              '${targetPeer.nodeIdHex.substring(0, 8)}'
              '${attempt > 0 ? " (retry #$attempt)" : ""}');
        }
      }

      if (!stored) {
        _log.debug('Fragment $i/${fragments.length} NOT stored (all peers failed)');
      }
    }

    // Update delivery status based on ACK count
    if (state != null && ackedCount >= minAcksForStored) {
      _updateStatus(state, MessageStatus.storedInNetwork);
    }

    _log.info('Fragment distribution done for ${messageIdHex.substring(0, 8)}: '
        '$ackedCount/${fragments.length} ACKed');
  }

  /// Look up x25519 public key: routing table -> contactManager.
  Uint8List? _lookupX25519Pk(Uint8List recipientNodeId) {
    final peer = node.routingTable.getPeer(recipientNodeId);
    if (peer?.x25519PublicKey != null && peer!.x25519PublicKey!.isNotEmpty) {
      return peer.x25519PublicKey!;
    }
    return contactManager.getX25519Pk(recipientNodeId);
  }

  /// Look up ML-KEM public key: routing table -> contactManager.
  Uint8List? _lookupMlKemPk(Uint8List recipientNodeId) {
    final peer = node.routingTable.getPeer(recipientNodeId);
    if (peer?.mlKemPublicKey != null && peer!.mlKemPublicKey!.isNotEmpty) {
      return peer.mlKemPublicKey!;
    }
    return contactManager.getMlKemPk(recipientNodeId);
  }

  /// Update delivery status and fire callback.
  void _updateStatus(MessageDeliveryState state, MessageStatus newStatus) {
    state.status = newStatus;
    state.lastUpdate = DateTime.now();
    onStatusChanged?.call(state.messageIdHex, newStatus);
  }

  /// Mark a message as delivered (called when DELIVERY_RECEIPT received).
  void markDelivered(String messageIdHex) {
    final state = _deliveryStates[messageIdHex];
    if (state != null) {
      _updateStatus(state, MessageStatus.delivered);
    }
  }

  /// Mark a message as read (called when READ_RECEIPT received).
  void markRead(String messageIdHex) {
    final state = _deliveryStates[messageIdHex];
    if (state != null) {
      _updateStatus(state, MessageStatus.read);
    }
  }

  /// Get delivery state for a message.
  MessageDeliveryState? getDeliveryState(String messageIdHex) {
    return _deliveryStates[messageIdHex];
  }

  /// Clean up old delivery states (older than 24 hours).
  void pruneDeliveryStates() {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    _deliveryStates.removeWhere((_, state) => state.lastUpdate.isBefore(cutoff));
  }
}
