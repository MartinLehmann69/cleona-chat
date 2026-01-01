/// Per-node rate limiting for incoming traffic (DoS Layer 2).
///
/// Tracks packet count and byte volume per source Node-ID within a sliding
/// time window. Excessive traffic is silently dropped — the sender receives
/// no error response (information leakage prevention).
///
/// Architecture reference: Section 9.2 — "Each node tracks traffic volume
/// per source Node-ID and enforces configurable limits."
library;

import 'dart:typed_data';

import 'package:cleona/core/network/peer_info.dart' show bytesToHex;

/// Per-source traffic counters within the current window.
class _SourceBucket {
  int packets = 0;
  int bytes = 0;
  DateTime windowStart;

  _SourceBucket() : windowStart = DateTime.now();

  void reset() {
    packets = 0;
    bytes = 0;
    windowStart = DateTime.now();
  }

  bool isExpired(Duration windowSize) =>
      DateTime.now().difference(windowStart) >= windowSize;
}

class RateLimiter {
  // ── Configurable limits ────────────────────────────────────────────

  /// Time window for rate tracking.
  final Duration window;

  /// Max packets per source per window.
  final int maxPacketsPerSource;

  /// Max bytes per source per window.
  final int maxBytesPerSource;

  /// Max total packets from ALL sources per window.
  final int maxTotalPackets;

  /// Max total bytes from ALL sources per window.
  final int maxTotalBytes;

  /// Max tracked sources (LRU eviction beyond this).
  final int maxTrackedSources;

  /// D5 (§13.1.3 Collective quota): fraction of the GLOBAL budgets that all
  /// non-introduced (anonymous/unknown) sources share collectively. Generous
  /// by design — binds only under attack, never during cold-start (a peer's
  /// first packet is typically the self-broadcast that lifts it out of the
  /// pool via firstParty PK / admission PoW).
  final double poolFraction;

  // ── Internal state ─────────────────────────────────────────────────

  final Map<String, _SourceBucket> _sources = {};
  int _totalPackets = 0;
  int _totalBytes = 0;
  // D5: collective counters for pooled (non-introduced) sources. Reset on
  // the same window as the global counters.
  int _poolPackets = 0;
  int _poolBytes = 0;
  DateTime _totalWindowStart = DateTime.now();

  // Stats for monitoring
  int _droppedPackets = 0;
  int get droppedPackets => _droppedPackets;

  /// D5: packets dropped because the collective pool slice was exhausted
  /// (subset of [droppedPackets]). Exposed as `poolDropsRate` in network
  /// stats.
  int _poolDroppedPackets = 0;
  int get poolDroppedPackets => _poolDroppedPackets;

  RateLimiter({
    this.window = const Duration(seconds: 10),
    this.maxPacketsPerSource = 200,
    this.maxBytesPerSource = 2 * 1024 * 1024, // 2 MB
    this.maxTotalPackets = 2000,
    this.maxTotalBytes = 20 * 1024 * 1024, // 20 MB
    this.maxTrackedSources = 500,
    this.poolFraction = 0.5,
  });

  /// Production defaults — generous limits that only catch real abuse.
  factory RateLimiter.production() => RateLimiter();

  /// Test defaults — tighter limits for automated testing.
  factory RateLimiter.test() => RateLimiter(
        window: const Duration(seconds: 5),
        maxPacketsPerSource: 50,
        maxBytesPerSource: 512 * 1024,
        maxTotalPackets: 500,
        maxTotalBytes: 5 * 1024 * 1024,
      );

  /// Check whether a packet from [senderNodeId] with [packetSize] bytes
  /// should be accepted.
  ///
  /// Returns `true` if the packet is allowed, `false` if it should be
  /// silently dropped.
  bool allowPacket(Uint8List senderNodeId, int packetSize) {
    _resetTotalIfExpired();

    // Global limits
    if (_totalPackets >= maxTotalPackets) {
      _droppedPackets++;
      return false;
    }
    if (_totalBytes + packetSize > maxTotalBytes) {
      _droppedPackets++;
      return false;
    }

    // Per-source limits
    final hex = bytesToHex(senderNodeId);
    var bucket = _sources[hex];
    if (bucket == null) {
      _evictIfNeeded();
      bucket = _SourceBucket();
      _sources[hex] = bucket;
    }

    if (bucket.isExpired(window)) {
      bucket.reset();
    }

    if (bucket.packets >= maxPacketsPerSource) {
      _droppedPackets++;
      return false;
    }
    if (bucket.bytes + packetSize > maxBytesPerSource) {
      _droppedPackets++;
      return false;
    }

    // Accept — record counters
    bucket.packets++;
    bucket.bytes += packetSize;
    _totalPackets++;
    _totalBytes += packetSize;

    return true;
  }

  /// Check by hex string (convenience for pre-computed sender hex).
  ///
  /// [checkPacketCount] — when false, the per-source and global packet-count
  /// limits are skipped.
  ///
  /// [checkSourceLimits] — when false, all per-source limits (packet count +
  /// byte budget) are skipped; only the global total-byte limit applies. Set to
  /// false for KEM-encrypted frames (PAYLOAD_INFRASTRUCTURE_FRAME and
  /// PAYLOAD_APPLICATION_FRAME): they are expensive to forge (KEM cost), so the
  /// natural rate limit is CPU-bound. PAYLOAD_BOOTSTRAP_INFRASTRUCTURE_FRAME is
  /// plaintext and cheap — it is the only type that should consume per-source
  /// quota.
  ///
  /// [pooled] — D5 (§13.1.3 Collective quota): true when the sender has NOT
  /// introduced itself (no verified admission PoW and no firstParty
  /// Device-Sig-PK). Pooled senders collectively share `poolFraction` of the
  /// global packet/byte budgets, so N minted IDs compete with each other
  /// instead of multiplying per-source budgets. Per-source limits apply
  /// unchanged on top. Pool drops generate no recordBad (§13.1.3).
  bool allowPacketHex(String senderHex, int packetSize, {
    bool checkPacketCount = true,
    bool checkSourceLimits = true,
    bool pooled = false,
  }) {
    _resetTotalIfExpired();

    if (checkPacketCount && _totalPackets >= maxTotalPackets) {
      _droppedPackets++;
      return false;
    }
    if (_totalBytes + packetSize > maxTotalBytes) {
      _droppedPackets++;
      return false;
    }

    // D5: collective pool slice for non-introduced sources.
    if (pooled) {
      if (checkPacketCount &&
          _poolPackets >= (maxTotalPackets * poolFraction).floor()) {
        _droppedPackets++;
        _poolDroppedPackets++;
        return false;
      }
      if (_poolBytes + packetSize > (maxTotalBytes * poolFraction).floor()) {
        _droppedPackets++;
        _poolDroppedPackets++;
        return false;
      }
    }

    if (checkSourceLimits) {
      var bucket = _sources[senderHex];
      if (bucket == null) {
        _evictIfNeeded();
        bucket = _SourceBucket();
        _sources[senderHex] = bucket;
      }

      if (bucket.isExpired(window)) bucket.reset();

      if (checkPacketCount && bucket.packets >= maxPacketsPerSource) {
        _droppedPackets++;
        return false;
      }
      if (bucket.bytes + packetSize > maxBytesPerSource) {
        _droppedPackets++;
        return false;
      }

      bucket.packets++;
      bucket.bytes += packetSize;
    }

    _totalPackets++;
    _totalBytes += packetSize;
    if (pooled) {
      _poolPackets++;
      _poolBytes += packetSize;
    }
    return true;
  }

  void _resetTotalIfExpired() {
    if (DateTime.now().difference(_totalWindowStart) >= window) {
      _totalPackets = 0;
      _totalBytes = 0;
      _poolPackets = 0;
      _poolBytes = 0;
      _totalWindowStart = DateTime.now();
    }
  }

  void _evictIfNeeded() {
    if (_sources.length >= maxTrackedSources) {
      // Evict oldest entry
      String? oldest;
      DateTime? oldestTime;
      for (final entry in _sources.entries) {
        if (oldestTime == null || entry.value.windowStart.isBefore(oldestTime)) {
          oldest = entry.key;
          oldestTime = entry.value.windowStart;
        }
      }
      if (oldest != null) _sources.remove(oldest);
    }
  }
}
