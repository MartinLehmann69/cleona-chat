import 'dart:typed_data';

/// Pairwise RTT measurement between call participants.
///
/// Each participant sends CALL_RTT_PING to every other participant,
/// receives CALL_RTT_PONG, and computes the round-trip time.
/// The RTT matrix is used by the overlay tree construction algorithm.
class RttMeasurement {
  final Uint8List callId;
  final String ownNodeIdHex;

  // nodeIdHex → smoothed RTT in milliseconds (EMA, alpha=0.3)
  final Map<String, int> _rttMs = {};

  // nodeIdHex → timestamp (microseconds) of last ping sent
  final Map<String, int> _pendingPings = {};

  // Pairwise RTT reports from other participants:
  // "$nodeA:$nodeB" → RTT ms (collected via tree update gossip)
  final Map<String, int> _pairwiseRtt = {};

  static const double _emaAlpha = 0.3;

  RttMeasurement({required this.callId, required this.ownNodeIdHex});

  /// Smoothed RTT to a peer in ms, or null if not measured yet.
  int? rttTo(String nodeIdHex) => _rttMs[nodeIdHex];

  /// All measured RTTs from this node.
  Map<String, int> get allRtts => Map.unmodifiable(_rttMs);

  /// Pairwise RTT between any two nodes (from gossip).
  int? pairwiseRtt(String nodeA, String nodeB) {
    return _pairwiseRtt['$nodeA:$nodeB'] ?? _pairwiseRtt['$nodeB:$nodeA'];
  }

  /// Record a pairwise RTT report from another participant.
  void recordPairwiseRtt(String nodeA, String nodeB, int rttMs) {
    _pairwiseRtt['$nodeA:$nodeB'] = rttMs;
  }

  /// Get effective cost between two nodes for tree construction.
  /// Uses: own measurement > pairwise gossip > DV route cost.
  int? effectiveRtt(String nodeA, String nodeB) {
    if (nodeA == ownNodeIdHex) return _rttMs[nodeB];
    if (nodeB == ownNodeIdHex) return _rttMs[nodeA];
    return pairwiseRtt(nodeA, nodeB);
  }

  /// Create a ping timestamp for a target. Returns the microsecond timestamp
  /// that should be put into CALL_RTT_PING.timestamp_us.
  int createPing(String targetNodeIdHex) {
    final now = DateTime.now().microsecondsSinceEpoch;
    _pendingPings[targetNodeIdHex] = now;
    return now;
  }

  /// Handle incoming ping — returns the echo timestamp for the pong.
  int handlePing(int pingTimestampUs) => pingTimestampUs;

  /// Handle incoming pong — calculate and record RTT.
  /// Returns the measured RTT in ms, or null if no matching ping.
  int? handlePong(String senderNodeIdHex, int echoTimestampUs) {
    final sentAt = _pendingPings.remove(senderNodeIdHex);
    if (sentAt == null) return null;

    // echoTimestampUs should match what we sent
    if (sentAt != echoTimestampUs) return null;

    final now = DateTime.now().microsecondsSinceEpoch;
    final rttUs = now - sentAt;
    final rttMs = (rttUs / 1000).round().clamp(0, 60000); // Cap at 60s

    // EMA smoothing
    final prev = _rttMs[senderNodeIdHex];
    if (prev != null) {
      _rttMs[senderNodeIdHex] =
          (_emaAlpha * rttMs + (1 - _emaAlpha) * prev).round();
    } else {
      _rttMs[senderNodeIdHex] = rttMs;
    }

    // Record in pairwise matrix
    _pairwiseRtt['$ownNodeIdHex:$senderNodeIdHex'] =
        _rttMs[senderNodeIdHex]!;

    return _rttMs[senderNodeIdHex];
  }

  /// Number of participants with measured RTT.
  int get measuredCount => _rttMs.length;

  /// Check if we have a pending ping for a peer.
  bool hasPendingPing(String nodeIdHex) =>
      _pendingPings.containsKey(nodeIdHex);

  /// Clear all state (for call end).
  void clear() {
    _rttMs.clear();
    _pendingPings.clear();
    _pairwiseRtt.clear();
  }
}
