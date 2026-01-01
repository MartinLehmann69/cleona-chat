/// Local peer reputation system (DoS Layer 3) + network-level banning (DoS Layer 5).
///
/// Each node independently evaluates its peers based on observed behavior.
/// There is no global reputation score — all decisions are strictly local.
///
/// Architecture reference:
///   Section 9.3 — "Nodes build reputation over time based on observed behavior."
///   Section 9.5 — "Nodes can temporarily or permanently ban other nodes."
library;

import 'dart:convert';
import 'dart:io';

import 'package:cleona/core/network/clogger.dart';

/// Reputation score entry for a single peer.
class PeerReputation {
  /// Positive events: successful message delivery, valid PoW, legitimate relay.
  int goodActions = 0;

  /// Negative events: invalid PoW, rate limit violations, spam, invalid signatures.
  int badActions = 0;

  /// Timestamp of first interaction.
  DateTime firstSeen;

  /// Timestamp of last interaction.
  DateTime lastSeen;

  /// Whether the peer is temporarily banned.
  bool isTempBanned = false;

  /// When the temp ban expires (null = not banned or permanent).
  DateTime? tempBanExpiry;

  /// Whether the peer is permanently banned.
  bool isPermBanned = false;

  /// Reason for the most recent ban (for diagnostics).
  String? banReason;

  PeerReputation()
      : firstSeen = DateTime.now(),
        lastSeen = DateTime.now();

  /// Reputation score: ratio of good to total actions, weighted by age.
  /// New peers start at 0.5 (neutral). Range: 0.0 (worst) to 1.0 (best).
  double get score {
    final total = goodActions + badActions;
    if (total == 0) return 0.5; // New peer — neutral
    return goodActions / total;
  }

  /// Whether the peer is currently banned (temp or permanent).
  bool get isBanned {
    if (isPermBanned) return true;
    if (isTempBanned) {
      if (tempBanExpiry != null && DateTime.now().isAfter(tempBanExpiry!)) {
        // Temp ban expired — auto-clear + decay badActions (Fix B).
        // Without decay, a single new violation immediately re-triggers the ban
        // (badActions still >= threshold), making temp bans de-facto permanent.
        isTempBanned = false;
        tempBanExpiry = null;
        banReason = null;
        badActions = (badActions * 0.5).round();
        return false;
      }
      return true;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
        'goodActions': goodActions,
        'badActions': badActions,
        'firstSeen': firstSeen.millisecondsSinceEpoch,
        'lastSeen': lastSeen.millisecondsSinceEpoch,
        'isTempBanned': isTempBanned,
        'tempBanExpiry': tempBanExpiry?.millisecondsSinceEpoch,
        'isPermBanned': isPermBanned,
        'banReason': banReason,
      };

  static PeerReputation fromJson(Map<String, dynamic> json) {
    final rep = PeerReputation()
      ..goodActions = json['goodActions'] as int? ?? 0
      ..badActions = json['badActions'] as int? ?? 0
      ..firstSeen = DateTime.fromMillisecondsSinceEpoch(json['firstSeen'] as int? ?? 0)
      ..lastSeen = DateTime.fromMillisecondsSinceEpoch(json['lastSeen'] as int? ?? 0)
      ..isTempBanned = json['isTempBanned'] as bool? ?? false
      ..isPermBanned = json['isPermBanned'] as bool? ?? false
      ..banReason = json['banReason'] as String?;
    if (json['tempBanExpiry'] != null) {
      rep.tempBanExpiry = DateTime.fromMillisecondsSinceEpoch(json['tempBanExpiry'] as int);
    }
    return rep;
  }
}

/// Manages peer reputation and banning decisions for a single node.
class ReputationManager {
  final Map<String, PeerReputation> _peers = {};
  final CLogger _log;

  // ── Configurable thresholds ──────────────────────────────────────

  /// Bad action count that triggers a temporary ban.
  final int tempBanThreshold;

  /// Duration of a temporary ban.
  final Duration tempBanDuration;

  /// Bad action count that triggers a permanent ban (cumulative, across bans).
  final int permBanThreshold;

  /// Max tracked peers (LRU eviction for ancient entries).
  final int maxTrackedPeers;

  ReputationManager({
    required String profileDir,
    this.tempBanThreshold = 20,
    this.tempBanDuration = const Duration(hours: 1),
    this.permBanThreshold = 100,
    this.maxTrackedPeers = 2000,
  }) : _log = CLogger.get('reputation', profileDir: profileDir);

  /// Production defaults.
  factory ReputationManager.production({required String profileDir}) =>
      ReputationManager(profileDir: profileDir);

  /// Test defaults — lower thresholds for faster testing.
  factory ReputationManager.test({required String profileDir}) =>
      ReputationManager(
        profileDir: profileDir,
        tempBanThreshold: 5,
        tempBanDuration: const Duration(seconds: 30),
        permBanThreshold: 15,
      );

  // ── Query ────────────────────────────────────────────────────────

  /// Check if a peer is currently banned.
  bool isBanned(String nodeIdHex) {
    final rep = _peers[nodeIdHex];
    if (rep == null) return false;
    return rep.isBanned;
  }

  /// Get a peer's current reputation score (0.0–1.0).
  double getScore(String nodeIdHex) {
    return _peers[nodeIdHex]?.score ?? 0.5;
  }

  /// Get the full reputation entry (for stats/diagnostics).
  PeerReputation? getReputation(String nodeIdHex) => _peers[nodeIdHex];

  /// Number of currently banned peers.
  int get bannedCount => _peers.values.where((r) => r.isBanned).length;

  /// Number of tracked peers.
  int get trackedCount => _peers.length;

  // ── Record events ────────────────────────────────────────────────

  /// Record a positive interaction (successful delivery, valid protocol message).
  void recordGood(String nodeIdHex) {
    final rep = _getOrCreate(nodeIdHex);
    rep.goodActions++;
    rep.lastSeen = DateTime.now();
  }

  /// Record a negative interaction and check ban thresholds.
  ///
  /// [reason] describes the violation (logged, stored in ban record).
  void recordBad(String nodeIdHex, String reason) {
    final rep = _getOrCreate(nodeIdHex);
    rep.badActions++;
    rep.lastSeen = DateTime.now();

    // Check permanent ban first (Fix A: score-gated, same as temp ban).
    if (!rep.isPermBanned && rep.badActions >= permBanThreshold && rep.score < 0.3) {
      rep.isPermBanned = true;
      rep.banReason = reason;
      _log.info('PERM BAN: ${nodeIdHex.substring(0, nodeIdHex.length.clamp(0, 8))} '
          '(${rep.badActions} bad actions, score=${rep.score.toStringAsFixed(2)}, last: $reason)');
      return;
    }

    // Check temporary ban (Fix A: score-gated).
    // A peer with good reputation (score >= 0.5, i.e. more good than bad actions)
    // is NOT banned — transient rate-limit bursts from legitimate neighbors
    // (e.g. S&F pushes, DV update storms) should not ban proven peers.
    // Architecture Section 9.3: "Reputation built through legitimate participation."
    if (!rep.isBanned && rep.badActions >= tempBanThreshold && rep.score < 0.5) {
      rep.isTempBanned = true;
      rep.tempBanExpiry = DateTime.now().add(tempBanDuration);
      rep.banReason = reason;
      _log.info('TEMP BAN: ${nodeIdHex.substring(0, nodeIdHex.length.clamp(0, 8))} for '
          '${tempBanDuration.inMinutes}min '
          '(${rep.badActions} bad actions, score=${rep.score.toStringAsFixed(2)}, last: $reason)');
    }
  }

  /// Manually ban a peer (e.g., user-initiated block).
  void banPermanently(String nodeIdHex, String reason) {
    final rep = _getOrCreate(nodeIdHex);
    rep.isPermBanned = true;
    rep.banReason = reason;
    _log.info('Manual PERM BAN: ${nodeIdHex.substring(0, nodeIdHex.length.clamp(0, 8))} ($reason)');
  }

  /// Manually ban a peer temporarily.
  void banTemporarily(String nodeIdHex, Duration duration, String reason) {
    final rep = _getOrCreate(nodeIdHex);
    rep.isTempBanned = true;
    rep.tempBanExpiry = DateTime.now().add(duration);
    rep.banReason = reason;
    _log.info('Manual TEMP BAN: ${nodeIdHex.substring(0, nodeIdHex.length.clamp(0, 8))} '
        'for ${duration.inMinutes}min ($reason)');
  }

  /// Unban a peer (clears both temp and perm bans).
  void unban(String nodeIdHex) {
    final rep = _peers[nodeIdHex];
    if (rep == null) return;
    rep.isTempBanned = false;
    rep.isPermBanned = false;
    rep.tempBanExpiry = null;
    rep.banReason = null;
    _log.info('UNBAN: ${nodeIdHex.substring(0, nodeIdHex.length.clamp(0, 8))}');
  }

  // ── Persistence ──────────────────────────────────────────────────

  Future<void> save(String profileDir) async {
    final file = File('$profileDir/reputation.json');
    await file.parent.create(recursive: true);
    final data = <String, dynamic>{};
    for (final entry in _peers.entries) {
      data[entry.key] = entry.value.toJson();
    }
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
    );
  }

  Future<void> load(String profileDir) async {
    final file = File('$profileDir/reputation.json');
    if (!await file.exists()) return;
    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      _peers.clear();
      for (final entry in json.entries) {
        _peers[entry.key] =
            PeerReputation.fromJson(entry.value as Map<String, dynamic>);
      }
    } on FormatException {
      // Corrupted file — start fresh
    }
  }

  // ── Internal ─────────────────────────────────────────────────────

  PeerReputation _getOrCreate(String nodeIdHex) {
    var rep = _peers[nodeIdHex];
    if (rep == null) {
      _evictIfNeeded();
      rep = PeerReputation();
      _peers[nodeIdHex] = rep;
    }
    return rep;
  }

  void _evictIfNeeded() {
    if (_peers.length >= maxTrackedPeers) {
      // Evict oldest non-banned peer
      String? oldest;
      DateTime? oldestTime;
      for (final entry in _peers.entries) {
        if (entry.value.isBanned) continue; // Never evict banned peers
        if (oldestTime == null || entry.value.lastSeen.isBefore(oldestTime)) {
          oldest = entry.key;
          oldestTime = entry.value.lastSeen;
        }
      }
      if (oldest != null) _peers.remove(oldest);
    }
  }
}
