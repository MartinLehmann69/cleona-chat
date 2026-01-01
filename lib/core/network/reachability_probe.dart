import 'dart:async';
import 'dart:typed_data';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Pending reachability query.
class _PendingQuery {
  final String queryIdHex;
  final Uint8List targetNodeId;
  final Completer<Uint8List?> completer; // Resolves with relay peer nodeId or null
  final Timer timer;
  int responsesReceived = 0;

  _PendingQuery({
    required this.queryIdHex,
    required this.targetNodeId,
    required this.completer,
    required this.timer,
  });
}

/// Probes online peers to discover relay routes for unreachable targets.
///
/// When a peer is unreachable (ACK timeout, no relay route), the probe
/// asks 3 random online peers: "Can you reach peer X?"
/// The first positive response establishes a relay route.
class ReachabilityProbe {
  final Map<String, _PendingQuery> _pending = {};
  final CLogger _log;

  /// Callback to send an envelope (injected by CleonaNode).
  Future<bool> Function(proto.MessageEnvelope envelope, Uint8List recipientNodeId)? sendFunction;

  /// Callback to create a signed envelope (injected by CleonaNode).
  proto.MessageEnvelope Function(proto.MessageType type, Uint8List payload, {Uint8List? recipientId})? createEnvelopeFunction;

  /// Callback to get confirmed online peers (injected by CleonaNode).
  List<PeerInfo> Function(Uint8List targetNodeId)? getCandidatesFunction;

  /// Callback to generate random bytes (injected by CleonaNode).
  Uint8List Function(int size)? randomBytesFunction;

  ReachabilityProbe({String? profileDir})
      : _log = CLogger.get('reach-probe', profileDir: profileDir);

  /// Query online peers about a target's reachability.
  ///
  /// Returns the nodeId of a peer that can reach the target, or null if
  /// no peer can reach it (within 3s timeout).
  Future<Uint8List?> queryPeersAbout(Uint8List targetNodeId) async {
    if (sendFunction == null || createEnvelopeFunction == null ||
        getCandidatesFunction == null || randomBytesFunction == null) {
      return null;
    }

    final candidates = getCandidatesFunction!(targetNodeId);
    if (candidates.isEmpty) {
      _log.debug('No candidates to query about ${bytesToHex(targetNodeId).substring(0, 8)}');
      return null;
    }

    final queryId = randomBytesFunction!(16);
    final queryIdHex = bytesToHex(queryId);
    final completer = Completer<Uint8List?>();

    final timer = Timer(const Duration(seconds: 3), () {
      final entry = _pending.remove(queryIdHex);
      if (entry != null && !entry.completer.isCompleted) {
        entry.completer.complete(null);
        _log.debug('Reachability query timeout for ${bytesToHex(targetNodeId).substring(0, 8)} '
            '(${entry.responsesReceived} responses, none positive)');
      }
    });

    _pending[queryIdHex] = _PendingQuery(
      queryIdHex: queryIdHex,
      targetNodeId: targetNodeId,
      completer: completer,
      timer: timer,
    );

    // Send query to up to 3 candidates
    final query = proto.PeerReachabilityQuery()
      ..targetNodeId = targetNodeId
      ..queryId = queryId;

    for (final candidate in candidates.take(3)) {
      final env = createEnvelopeFunction!(
        proto.MessageType.REACHABILITY_QUERY,
        query.writeToBuffer(),
        recipientId: candidate.nodeId,
      );
      sendFunction!(env, candidate.nodeId);
    }

    _log.debug('Queried ${candidates.take(3).length} peers about '
        '${bytesToHex(targetNodeId).substring(0, 8)}');

    return completer.future;
  }

  /// Handle a REACHABILITY_RESPONSE from a peer.
  ///
  /// Called by CleonaNode when a response arrives.
  void handleResponse(proto.MessageEnvelope envelope) {
    try {
      final response = proto.PeerReachabilityResponse.fromBuffer(envelope.encryptedPayload);
      final queryIdHex = bytesToHex(Uint8List.fromList(response.queryId));
      final senderNodeId = Uint8List.fromList(envelope.senderId);

      final entry = _pending[queryIdHex];
      if (entry == null) return; // Unknown or expired query

      entry.responsesReceived++;

      if (response.canReach && !entry.completer.isCompleted) {
        // First positive response — resolve with this peer as relay
        _pending.remove(queryIdHex);
        entry.timer.cancel();
        entry.completer.complete(senderNodeId);
        _log.info('Reachability: ${bytesToHex(senderNodeId).substring(0, 8)} '
            'can reach ${bytesToHex(entry.targetNodeId).substring(0, 8)} '
            '(last seen ${response.lastSeenMs}ms ago)');
      }
    } catch (e) {
      _log.debug('Reachability response parse error: $e');
    }
  }

  /// Number of pending queries (for diagnostics).
  int get pendingCount => _pending.length;

  void dispose() {
    for (final entry in _pending.values) {
      entry.timer.cancel();
      if (!entry.completer.isCompleted) {
        entry.completer.complete(null);
      }
    }
    _pending.clear();
  }
}
