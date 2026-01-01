import 'dart:async';
import 'dart:typed_data';

import 'package:cleona/core/erasure/reed_solomon.dart';
import 'package:cleona/core/dht/mailbox_store.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/core/node/cleona_node.dart';
import 'package:cleona/core/node/identity_context.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Tracks the partial assembly of a message from erasure-coded fragments.
class _FragmentAssembly {
  final String messageIdHex;
  final int totalFragments;
  final int requiredFragments;
  final int originalSize;
  final Map<int, Uint8List> fragments = {};
  final DateTime createdAt;
  bool reconstructed = false;

  _FragmentAssembly({
    required this.messageIdHex,
    required this.totalFragments,
    required this.requiredFragments,
    required this.originalSize,
  }) : createdAt = DateTime.now();

  bool get hasEnoughFragments => fragments.length >= requiredFragments;

  bool get isExpired =>
      DateTime.now().difference(createdAt) > MessageReceiver.fragmentAgingTimeout;
}

/// Receives and reassembles erasure-coded messages from DHT fragment storage.
///
/// Handles:
/// - Fragment collection and tracking of partial assemblies
/// - Reed-Solomon reconstruction when K=7 fragments arrive
/// - Mailbox polling to retrieve fragments from DHT peers
/// - Fragment aging: incomplete assemblies evicted after timeout
/// - Deduplication by messageIdHex
class MessageReceiver {
  final CleonaNode node;
  final IdentityContext identity;
  final MailboxStore mailboxStore;
  final CLogger _log;

  /// Callback fired when a message is fully reassembled from fragments.
  void Function(proto.MessageEnvelope envelope)? onMessageReassembled;

  /// Active fragment assemblies indexed by messageIdHex.
  final Map<String, _FragmentAssembly> _assemblies = {};

  /// Set of already-delivered message IDs for deduplication.
  final Set<String> _deliveredMessageIds = {};

  /// Maximum number of delivered message IDs to track (LRU eviction).
  static const int maxDeliveredIds = 10000;

  /// Fragment aging timeout: evict incomplete assemblies after this duration.
  static const Duration fragmentAgingTimeout = Duration(minutes: 10);

  /// Timer for periodic aging and cleanup.
  Timer? _agingTimer;

  MessageReceiver({
    required this.node,
    required this.identity,
    required this.mailboxStore,
  }) : _log = CLogger.get('msg-receiver', profileDir: node.profileDir);

  /// Start the receiver (begins periodic aging).
  void start() {
    _agingTimer = Timer.periodic(const Duration(seconds: 30), (_) => _evictStale());
    _log.info('MessageReceiver started');
  }

  /// Handle an incoming fragment (from FRAGMENT_STORE or mailbox poll).
  ///
  /// Returns true if this fragment triggered a successful reconstruction.
  bool handleFragment(StoredFragment fragment) {
    final messageIdHex = bytesToHex(fragment.messageId);

    // Deduplication: skip if already delivered
    if (_deliveredMessageIds.contains(messageIdHex)) {
      _log.debug('Skipping duplicate fragment for already-delivered ${messageIdHex.substring(0, 8)}');
      return false;
    }

    // Get or create assembly tracker
    var assembly = _assemblies[messageIdHex];
    if (assembly == null) {
      assembly = _FragmentAssembly(
        messageIdHex: messageIdHex,
        totalFragments: fragment.totalFragments,
        requiredFragments: fragment.requiredFragments,
        originalSize: fragment.originalSize,
      );
      _assemblies[messageIdHex] = assembly;
      _log.debug('New assembly for ${messageIdHex.substring(0, 8)}: '
          'need ${fragment.requiredFragments}/${fragment.totalFragments}');
    }

    // Skip if already reconstructed
    if (assembly.reconstructed) return false;

    // Skip duplicate fragment index
    if (assembly.fragments.containsKey(fragment.fragmentIndex)) {
      return false;
    }

    // Add fragment
    assembly.fragments[fragment.fragmentIndex] = Uint8List.fromList(fragment.data);
    _log.debug('Fragment ${fragment.fragmentIndex}/${assembly.totalFragments} '
        'for ${messageIdHex.substring(0, 8)} '
        '(${assembly.fragments.length}/${assembly.requiredFragments} collected)');

    // Try reconstruction if we have enough
    if (assembly.hasEnoughFragments) {
      return _tryReconstruct(messageIdHex);
    }

    return false;
  }

  /// Poll a mailbox for fragments from DHT peers.
  ///
  /// Sends FRAGMENT_RETRIEVE requests to peers closest to the mailbox ID.
  /// [mailboxId] — primary mailbox (PK-based).
  /// [fallbackMailboxId] — fallback mailbox (nodeId-based), polled if primary yields nothing.
  Future<int> pollMailbox(Uint8List mailboxId, {Uint8List? fallbackMailboxId}) async {
    var totalReceived = 0;

    totalReceived += await _pollSingleMailbox(mailboxId);

    if (totalReceived == 0 && fallbackMailboxId != null) {
      _log.debug('Primary mailbox empty, trying fallback');
      totalReceived += await _pollSingleMailbox(fallbackMailboxId);
    }

    return totalReceived;
  }

  /// Poll a single mailbox ID from DHT peers.
  Future<int> _pollSingleMailbox(Uint8List mailboxId) async {
    final closestPeers = node.routingTable.findClosestPeers(mailboxId, count: 10);
    if (closestPeers.isEmpty) {
      _log.debug('No peers for mailbox poll ${bytesToHex(mailboxId).substring(0, 8)}');
      return 0;
    }

    var received = 0;

    for (final peer in closestPeers) {
      try {
        final retrieveMsg = proto.FragmentRetrieve()
          ..mailboxId = mailboxId;

        final envelope = identity.createSignedEnvelope(
          proto.MessageType.FRAGMENT_RETRIEVE,
          Uint8List.fromList(retrieveMsg.writeToBuffer()),
          recipientId: peer.nodeId,
        );

        final response = await node.dhtRpc.sendAndWait(
          envelope,
          peer,
          timeout: const Duration(seconds: 5),
        );

        if (response == null) continue;

        // Parse response — expect FRAGMENT_STORE messages with fragment data
        if (response.messageType == proto.MessageType.FRAGMENT_STORE) {
          try {
            final fragData = proto.FragmentStore.fromBuffer(response.encryptedPayload);
            final fragment = StoredFragment(
              mailboxId: Uint8List.fromList(fragData.mailboxId),
              messageId: Uint8List.fromList(fragData.messageId),
              fragmentIndex: fragData.fragmentIndex,
              totalFragments: fragData.totalFragments,
              requiredFragments: fragData.requiredFragments,
              data: Uint8List.fromList(fragData.fragmentData),
              originalSize: fragData.originalSize,
            );
            if (handleFragment(fragment)) {
              received++;
            }
          } catch (e) {
            _log.debug('Failed to parse fragment from ${peer.nodeIdHex.substring(0, 8)}: $e');
          }
        }
      } catch (e) {
        _log.debug('Mailbox poll error from ${peer.nodeIdHex.substring(0, 8)}: $e');
      }
    }

    if (received > 0) {
      _log.info('Mailbox poll: $received new fragments from '
          '${bytesToHex(mailboxId).substring(0, 8)}');
    }

    return received;
  }

  /// Try to reconstruct a message from collected fragments.
  bool _tryReconstruct(String messageIdHex) {
    final assembly = _assemblies[messageIdHex];
    if (assembly == null || assembly.reconstructed) return false;

    if (!assembly.hasEnoughFragments) {
      _log.debug('Not enough fragments for ${messageIdHex.substring(0, 8)}: '
          '${assembly.fragments.length}/${assembly.requiredFragments}');
      return false;
    }

    try {
      final rs = ReedSolomon();
      final reconstructedBytes = assembly.originalSize > ReedSolomon.streamingThreshold
          ? rs.decodeStreaming(assembly.fragments, assembly.originalSize)
          : rs.decode(assembly.fragments, assembly.originalSize);

      // Parse reconstructed bytes as MessageEnvelope
      final envelope = proto.MessageEnvelope.fromBuffer(reconstructedBytes);
      assembly.reconstructed = true;

      // Mark as delivered for deduplication
      _markDelivered(messageIdHex);

      _log.info('Reconstructed message ${messageIdHex.substring(0, 8)} '
          'from ${assembly.fragments.length} fragments '
          '(${assembly.originalSize} bytes)');

      // Fire callback
      onMessageReassembled?.call(envelope);

      return true;
    } catch (e) {
      _log.warn('Reconstruction failed for ${messageIdHex.substring(0, 8)}: $e');
      return false;
    }
  }

  /// Mark a message ID as delivered (deduplication).
  void _markDelivered(String messageIdHex) {
    _deliveredMessageIds.add(messageIdHex);

    // LRU eviction: remove oldest entries if over limit
    if (_deliveredMessageIds.length > maxDeliveredIds) {
      final excess = _deliveredMessageIds.length - maxDeliveredIds;
      final toRemove = _deliveredMessageIds.take(excess).toList();
      for (final id in toRemove) {
        _deliveredMessageIds.remove(id);
      }
    }
  }

  /// Also mark direct-delivered messages for deduplication.
  /// Call this when a message is received via direct UDP push.
  void markDirectDelivered(String messageIdHex) {
    _markDelivered(messageIdHex);
    // Clean up any partial assembly for this message
    _assemblies.remove(messageIdHex);
  }

  /// Evict incomplete fragment assemblies older than the aging timeout.
  void _evictStale() {
    final staleIds = <String>[];
    for (final entry in _assemblies.entries) {
      if (entry.value.isExpired && !entry.value.reconstructed) {
        staleIds.add(entry.key);
      }
    }

    for (final id in staleIds) {
      final assembly = _assemblies.remove(id);
      if (assembly != null) {
        _log.debug('Evicted stale assembly ${id.substring(0, 8)}: '
            '${assembly.fragments.length}/${assembly.requiredFragments} fragments');
      }
    }
  }

  /// Get the number of active (incomplete) assemblies.
  int get activeAssemblyCount =>
      _assemblies.values.where((a) => !a.reconstructed).length;

  /// Get the number of tracked delivered message IDs.
  int get deliveredCount => _deliveredMessageIds.length;

  /// Stop the receiver and clean up.
  void dispose() {
    _agingTimer?.cancel();
    _assemblies.clear();
    _log.info('MessageReceiver stopped');
  }
}
