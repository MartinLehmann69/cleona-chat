import 'dart:typed_data';
import 'package:cleona/core/moderation/moderation_config.dart';
import 'package:cleona/core/network/clogger.dart';

/// Bloom filter for Social Graph Reachability checks.
///
/// Used in Anti-Sybil validation: random validators check if a reporter
/// is reachable within [maxHops] hops through the social graph.
/// Privacy: nodes only see a Bloom filter, never the full path.
class ReachabilityBloomFilter {
  /// Filter size in bits (4096 = 512 bytes — compact enough for DHT messages).
  static const int filterBits = 4096;
  static const int filterBytes = filterBits ~/ 8;
  static const int hashCount = 7;

  final Uint8List _bits;

  ReachabilityBloomFilter() : _bits = Uint8List(filterBytes);
  ReachabilityBloomFilter.fromBytes(Uint8List bytes) : _bits = Uint8List.fromList(bytes);

  Uint8List get bytes => Uint8List.fromList(_bits);

  /// Add a node ID to the filter.
  void add(Uint8List nodeId) {
    for (var i = 0; i < hashCount; i++) {
      final bit = _hash(nodeId, i) % filterBits;
      _bits[bit ~/ 8] |= 1 << (bit % 8);
    }
  }

  /// Check if a node ID might be in the filter (false positives possible).
  bool mightContain(Uint8List nodeId) {
    for (var i = 0; i < hashCount; i++) {
      final bit = _hash(nodeId, i) % filterBits;
      if (_bits[bit ~/ 8] & (1 << (bit % 8)) == 0) return false;
    }
    return true;
  }

  /// Simple hash: FNV-1a variant with seed.
  int _hash(Uint8List data, int seed) {
    var hash = 0x811c9dc5 ^ seed;
    for (final b in data) {
      hash ^= b;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }
}

/// Result of a reachability validation for a reporter.
class ReachabilityResult {
  final String reporterNodeIdHex;
  final int validatorsReached;
  final int validatorsTotal;
  final bool accepted;

  ReachabilityResult({
    required this.reporterNodeIdHex,
    required this.validatorsReached,
    required this.validatorsTotal,
    required this.accepted,
  });

  double get reachabilityScore =>
      validatorsTotal > 0 ? validatorsReached / validatorsTotal : 0.0;

  @override
  String toString() =>
      'ReachabilityResult($reporterNodeIdHex: $validatorsReached/$validatorsTotal = '
      '${(reachabilityScore * 100).toStringAsFixed(0)}% '
      '${accepted ? "ACCEPTED" : "REJECTED"})';
}

/// Validator logic for Social Graph Reachability checks.
///
/// In production, this runs on network nodes (not app-side).
/// Each validator performs a random walk through its local social graph
/// to check if the target node is reachable within N hops.
class ReachabilityValidator {
  final ModerationConfig config;
  final CLogger _log;

  ReachabilityValidator({required this.config, CLogger? log})
      : _log = log ?? CLogger('Reachability');

  /// Check if a reporter is sufficiently connected to the network.
  ///
  /// [contactsOfReporter] — node IDs of the reporter's direct contacts.
  /// [validatorContactGraphs] — each validator's local neighborhood (nodeIdHex -> set of contact nodeIdHexes).
  ///
  /// Returns the reachability result.
  ReachabilityResult validate({
    required String reporterNodeIdHex,
    required Set<String> contactsOfReporter,
    required Map<String, Set<String>> validatorContactGraphs,
  }) {
    if (!config.reachabilityEnabled) {
      return ReachabilityResult(
        reporterNodeIdHex: reporterNodeIdHex,
        validatorsReached: 1,
        validatorsTotal: 1,
        accepted: true,
      );
    }

    var reached = 0;
    final total = validatorContactGraphs.length;

    for (final entry in validatorContactGraphs.entries) {
      final validatorId = entry.key;
      final validatorGraph = entry.value;

      // BFS from validator, check if reporter is reachable in maxHops
      final canReach = _bfsReachable(
        startNodeContacts: validatorGraph,
        targetNodeIdHex: reporterNodeIdHex,
        maxHops: config.reachabilityMaxHops,
        allGraphs: validatorContactGraphs,
      );

      if (canReach) reached++;
      _log.info('Validator $validatorId -> reporter: ${canReach ? "REACHABLE" : "NOT REACHABLE"}');
    }

    final score = total > 0 ? reached / total : 0.0;
    final accepted = score >= config.reachabilityThreshold;

    final result = ReachabilityResult(
      reporterNodeIdHex: reporterNodeIdHex,
      validatorsReached: reached,
      validatorsTotal: total,
      accepted: accepted,
    );

    _log.info('Reachability check: $result');
    return result;
  }

  /// BFS reachability check within maxHops.
  bool _bfsReachable({
    required Set<String> startNodeContacts,
    required String targetNodeIdHex,
    required int maxHops,
    required Map<String, Set<String>> allGraphs,
  }) {
    if (startNodeContacts.contains(targetNodeIdHex)) return true;

    var frontier = startNodeContacts.toSet();
    final visited = <String>{};

    for (var hop = 1; hop <= maxHops; hop++) {
      final nextFrontier = <String>{};
      for (final nodeId in frontier) {
        if (visited.contains(nodeId)) continue;
        visited.add(nodeId);

        final contacts = allGraphs[nodeId];
        if (contacts == null) continue;

        if (contacts.contains(targetNodeIdHex)) return true;
        nextFrontier.addAll(contacts.difference(visited));
      }
      if (nextFrontier.isEmpty) break;
      frontier = nextFrontier;
    }

    return false;
  }
}
