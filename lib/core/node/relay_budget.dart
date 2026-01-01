/// Rate-limiting and deduplication for relay traffic.
///
/// Prevents abuse by capping total relay volume, per-source volume,
/// message count, and payload size. Also provides relay_id dedup cache
/// and TTL enforcement.
library;

import 'dart:collection';
import 'dart:typed_data';

import 'package:cleona/core/network/peer_info.dart' show bytesToHex;

class RelayBudget {
  /// Max total relay bytes per minute (all sources combined).
  static const int maxTotalBytesPerMinute = 4 * 1024 * 1024; // 4 MB

  /// Max relay bytes per source node per minute.
  /// High limit: small networks relay through few nodes, each sending
  /// many queued messages after reconnect. Real abuse protection is
  /// via maxPayloadSize (64KB per message) and dedup cache.
  static const int maxSourceBytesPerMinute = 10 * 1024 * 1024; // 10 MB

  /// Max relay messages per minute (all sources).
  /// High limit: per-source byte limits (1MB/source/min) and payload
  /// size limits (64KB) are the real abuse protection. The message
  /// count limit only catches extreme flooding scenarios.
  static const int maxMessagesPerMinute = 2000;

  /// Max single relay payload size.
  /// V3.1.7: Raised from 64 KB to 300 KB — inline images (< 256 KB) must
  /// pass through relay for contacts behind AP-isolation/NAT.
  static const int maxPayloadSize = 300 * 1024; // 300 KB

  /// Max relay TTL — drop messages older than this.
  static const Duration maxRelayAge = Duration(minutes: 5);

  /// Max hops for any relay chain.
  static const int maxHops = 3;

  /// Max dedup cache entries.
  static const int maxDedupEntries = 10000;

  // ── Sliding-window counters ─────────────────────────────────────────

  int _totalBytes = 0;
  int _totalMessages = 0;
  DateTime _windowStart = DateTime.now();
  final Map<String, int> _sourceBytes = {};

  // ── Dedup cache (LRU) ──────────────────────────────────────────────

  final LinkedHashSet<String> _dedupCache = LinkedHashSet<String>();

  // ── Public API ─────────────────────────────────────────────────────

  /// Check whether a relay request should be accepted.
  ///
  /// Returns null if OK, or a rejection reason string.
  String? checkRelay({
    required Uint8List relayId,
    required Uint8List originNodeId,
    required int payloadSize,
    required int hopCount,
    required int maxHopsField,
    required int createdAtMs,
  }) {
    // 1. Payload size
    if (payloadSize > maxPayloadSize) {
      return 'payload too large: $payloadSize > $maxPayloadSize';
    }

    // 2. Hop limit
    if (hopCount >= maxHopsField || hopCount >= maxHops) {
      return 'hop limit reached: $hopCount >= ${maxHopsField.clamp(1, maxHops)}';
    }

    // 3. TTL
    final age = DateTime.now().millisecondsSinceEpoch - createdAtMs;
    if (age > maxRelayAge.inMilliseconds) {
      return 'relay too old: ${age ~/ 1000}s > ${maxRelayAge.inSeconds}s';
    }
    if (age < -60000) {
      return 'relay from future: ${-age ~/ 1000}s ahead';
    }

    // 4. Dedup
    final relayIdHex = bytesToHex(relayId);
    if (_dedupCache.contains(relayIdHex)) {
      return 'duplicate relay_id';
    }

    // 5. Rate limits
    _resetWindowIfNeeded();

    if (_totalMessages >= maxMessagesPerMinute) {
      return 'message rate limit: $_totalMessages >= $maxMessagesPerMinute/min';
    }

    if (_totalBytes + payloadSize > maxTotalBytesPerMinute) {
      return 'total byte limit: ${_totalBytes + payloadSize} > $maxTotalBytesPerMinute/min';
    }

    // 6. Per-source rate limit
    final sourceHex = bytesToHex(originNodeId);
    final sourceTotal = (_sourceBytes[sourceHex] ?? 0) + payloadSize;
    if (sourceTotal > maxSourceBytesPerMinute) {
      return 'per-source byte limit: $sourceTotal > $maxSourceBytesPerMinute/min';
    }

    return null; // OK
  }

  /// Record a relay that was accepted and processed.
  void recordRelay({
    required Uint8List relayId,
    required Uint8List originNodeId,
    required int payloadSize,
  }) {
    _resetWindowIfNeeded();

    _totalBytes += payloadSize;
    _totalMessages++;

    final sourceHex = bytesToHex(originNodeId);
    _sourceBytes[sourceHex] = (_sourceBytes[sourceHex] ?? 0) + payloadSize;

    // Add to dedup cache (LRU eviction)
    final relayIdHex = bytesToHex(relayId);
    _dedupCache.add(relayIdHex);
    while (_dedupCache.length > maxDedupEntries) {
      _dedupCache.remove(_dedupCache.first);
    }
  }

  /// Check if a relay_id was already seen (dedup only, no budget check).
  bool isDuplicate(Uint8List relayId) {
    return _dedupCache.contains(bytesToHex(relayId));
  }

  /// Check if own nodeId is in visited_nodes list (loop detection).
  bool isLoop(List<List<int>> visitedNodes, Uint8List ownNodeId) {
    final ownHex = bytesToHex(ownNodeId);
    for (final visited in visitedNodes) {
      if (bytesToHex(Uint8List.fromList(visited)) == ownHex) return true;
    }
    return false;
  }

  void _resetWindowIfNeeded() {
    final now = DateTime.now();
    if (now.difference(_windowStart).inSeconds >= 60) {
      _totalBytes = 0;
      _totalMessages = 0;
      _sourceBytes.clear();
      _windowStart = now;
    }
  }
}
