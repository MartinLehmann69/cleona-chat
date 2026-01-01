import 'dart:collection';
import 'dart:math';
import 'package:cleona/core/calls/rtt_measurement.dart';

/// A node in the overlay multicast tree.
class TreeNode {
  final String nodeIdHex;
  String? parentHex;
  final List<String> childrenHex;
  bool isLanClusterHead;
  final List<String> lanMemberHex; // Peers in same LAN (receive via multicast)

  TreeNode({
    required this.nodeIdHex,
    this.parentHex,
    List<String>? childrenHex,
    this.isLanClusterHead = false,
    List<String>? lanMemberHex,
  })  : childrenHex = childrenHex ?? [],
        lanMemberHex = lanMemberHex ?? [];

  bool get isRoot => parentHex == null;
  bool get isLeaf => childrenHex.isEmpty;
  int get degree => childrenHex.length;

  @override
  String toString() => 'TreeNode($nodeIdHex, parent=$parentHex, '
      'children=${childrenHex.length}, lan=${lanMemberHex.length})';
}

/// Edge weight between two participants for MST construction.
class _Edge implements Comparable<_Edge> {
  final String nodeA;
  final String nodeB;
  final int cost;

  _Edge(this.nodeA, this.nodeB, this.cost);

  @override
  int compareTo(_Edge other) => cost.compareTo(other.cost);
}

/// Overlay Multicast Tree for group calls.
///
/// Constructs a degree-constrained minimum spanning tree over call
/// participants using DV route costs as edge weights.
/// Each node relays to at most [maxFanOut] children.
///
/// LAN optimization: Participants on the same subnet are grouped
/// into clusters. The cluster head represents the group in the tree
/// and multicasts to local members (zero extra upload).
class OverlayTree {
  /// Maximum children per node in the tree.
  final int maxFanOut;

  /// Max cumulative latency before triggering rebalance (ms).
  static const int maxCumulativeLatencyMs = 200;

  /// Crash detection timeout (ms) — no frames for this long = dead.
  static const int crashTimeoutMs = 3000;

  /// Tree version — monotonically increasing on each rebuild/rebalance.
  int version = 0;

  /// The call initiator (tree root).
  String? rootHex;

  /// All nodes in the tree: nodeIdHex → TreeNode.
  final Map<String, TreeNode> _nodes = {};

  OverlayTree({this.maxFanOut = 3});

  /// All tree nodes.
  Map<String, TreeNode> get nodes => Map.unmodifiable(_nodes);

  /// Get a specific node.
  TreeNode? nodeFor(String hex) => _nodes[hex];

  /// Number of participants in the tree.
  int get participantCount => _nodes.length;

  /// Tree depth from root.
  int get depth => _computeDepth(rootHex, 0);

  int _computeDepth(String? hex, int d) {
    if (hex == null) return d;
    final node = _nodes[hex];
    if (node == null || node.childrenHex.isEmpty) return d;
    int maxD = d;
    for (final child in node.childrenHex) {
      final cd = _computeDepth(child, d + 1);
      if (cd > maxD) maxD = cd;
    }
    return maxD;
  }

  /// Children of a node in the tree.
  List<String> childrenOf(String hex) => _nodes[hex]?.childrenHex ?? [];

  /// Parent of a node in the tree.
  String? parentOf(String hex) => _nodes[hex]?.parentHex;

  // ── Tree Construction ───────────────────────────────────────────────

  /// Build the overlay tree from scratch.
  ///
  /// [participants]: all participant node IDs (including initiator).
  /// [initiatorHex]: the call initiator (becomes root).
  /// [routeCost]: returns the DV route cost between two nodes, or null
  ///              if no route exists. Used as primary edge weight.
  /// [rtt]: optional RTT measurement for tie-breaking.
  /// [sameSubnet]: returns true if two nodes are on the same LAN subnet.
  void build({
    required List<String> participants,
    required String initiatorHex,
    required int? Function(String a, String b) routeCost,
    RttMeasurement? rtt,
    bool Function(String a, String b)? sameSubnet,
  }) {
    _nodes.clear();
    version++;
    rootHex = initiatorHex;

    if (participants.length <= 1) {
      if (participants.isNotEmpty) {
        _nodes[participants.first] = TreeNode(nodeIdHex: participants.first);
      }
      return;
    }

    // ── Step 1: Detect LAN clusters ─────────────────────────────────
    final clusters = _detectLanClusters(participants, sameSubnet);

    // Effective participants: one representative per cluster + singletons
    final effectiveParticipants = <String>[];
    final clusterMap = <String, List<String>>{}; // headHex → member list

    for (final cluster in clusters) {
      if (cluster.length == 1) {
        effectiveParticipants.add(cluster.first);
      } else {
        // Choose the initiator as head if present, otherwise first member
        final head = cluster.contains(initiatorHex)
            ? initiatorHex
            : cluster.first;
        effectiveParticipants.add(head);
        clusterMap[head] = cluster.where((n) => n != head).toList();
      }
    }

    // ── Step 2: Build edges with costs ──────────────────────────────
    final edges = <_Edge>[];
    for (var i = 0; i < effectiveParticipants.length; i++) {
      for (var j = i + 1; j < effectiveParticipants.length; j++) {
        final a = effectiveParticipants[i];
        final b = effectiveParticipants[j];

        var cost = routeCost(a, b);
        if (cost == null) {
          // No route — use RTT if available, otherwise high cost
          final r = rtt?.effectiveRtt(a, b);
          cost = r != null ? (r ~/ 10).clamp(1, 100) : 1000;
        }

        // RTT tie-breaking: if costs are equal, prefer lower RTT
        final r = rtt?.effectiveRtt(a, b);
        if (r != null) {
          // Add fractional RTT cost (0-9) for tie-breaking
          cost = cost * 10 + (r ~/ 50).clamp(0, 9);
        } else {
          cost = cost * 10;
        }

        edges.add(_Edge(a, b, cost));
      }
    }
    edges.sort();

    // ── Step 3: Degree-constrained MST (Kruskal-like) ──────────────
    // Union-Find for cycle detection
    final parent = <String, String>{};
    final rank = <String, int>{};
    final degree = <String, int>{};

    for (final p in effectiveParticipants) {
      parent[p] = p;
      rank[p] = 0;
      degree[p] = 0;
    }

    String find(String x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]!]!; // Path compression
        x = parent[x]!;
      }
      return x;
    }

    void union(String a, String b) {
      final ra = find(a), rb = find(b);
      if (ra == rb) return;
      if (rank[ra]! < rank[rb]!) {
        parent[ra] = rb;
      } else if (rank[ra]! > rank[rb]!) {
        parent[rb] = ra;
      } else {
        parent[rb] = ra;
        rank[ra] = rank[ra]! + 1;
      }
    }

    // Selected MST edges
    final mstEdges = <_Edge>[];

    for (final edge in edges) {
      if (mstEdges.length >= effectiveParticipants.length - 1) break;
      if (find(edge.nodeA) == find(edge.nodeB)) continue;
      if (degree[edge.nodeA]! >= maxFanOut &&
          degree[edge.nodeB]! >= maxFanOut) { continue; }

      mstEdges.add(edge);
      union(edge.nodeA, edge.nodeB);
      degree[edge.nodeA] = degree[edge.nodeA]! + 1;
      degree[edge.nodeB] = degree[edge.nodeB]! + 1;
    }

    // ── Step 4: Root the tree at initiator ──────────────────────────
    // Build adjacency list from MST edges
    final adj = <String, List<String>>{};
    for (final p in effectiveParticipants) {
      adj[p] = [];
    }
    for (final edge in mstEdges) {
      adj[edge.nodeA]!.add(edge.nodeB);
      adj[edge.nodeB]!.add(edge.nodeA);
    }

    // BFS from root to assign parent/children
    final visited = <String>{};
    final queue = Queue<String>();
    queue.add(initiatorHex);
    visited.add(initiatorHex);

    _nodes[initiatorHex] = TreeNode(
      nodeIdHex: initiatorHex,
      isLanClusterHead: clusterMap.containsKey(initiatorHex),
      lanMemberHex: clusterMap[initiatorHex],
    );

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      final neighbors = adj[current] ?? [];

      // Enforce fan-out limit: sort neighbors by cost to root
      final unvisited = neighbors.where((n) => !visited.contains(n)).toList();

      for (final neighbor in unvisited) {
        if (_nodes[current]!.childrenHex.length >= maxFanOut) {
          // Fan-out exceeded — find another parent in the tree
          final altParent = _findAvailableParent(visited, current);
          if (altParent != null) {
            visited.add(neighbor);
            _nodes[neighbor] = TreeNode(
              nodeIdHex: neighbor,
              parentHex: altParent,
              isLanClusterHead: clusterMap.containsKey(neighbor),
              lanMemberHex: clusterMap[neighbor],
            );
            _nodes[altParent]!.childrenHex.add(neighbor);
            queue.add(neighbor);
          }
          continue;
        }

        visited.add(neighbor);
        _nodes[neighbor] = TreeNode(
          nodeIdHex: neighbor,
          parentHex: current,
          isLanClusterHead: clusterMap.containsKey(neighbor),
          lanMemberHex: clusterMap[neighbor],
        );
        _nodes[current]!.childrenHex.add(neighbor);
        queue.add(neighbor);
      }
    }

    // Handle any participants not connected by MST (disconnected graph)
    for (final p in effectiveParticipants) {
      if (!_nodes.containsKey(p)) {
        final altParent = _findAvailableParent(_nodes.keys.toSet(), null);
        _nodes[p] = TreeNode(
          nodeIdHex: p,
          parentHex: altParent,
          isLanClusterHead: clusterMap.containsKey(p),
          lanMemberHex: clusterMap[p],
        );
        if (altParent != null) {
          _nodes[altParent]!.childrenHex.add(p);
        }
      }
    }

    // ── Step 5: Auto-rebalance if tree is too deep ──────────────────
    // MST on path-like cost graphs can produce deep chains.
    // Rebalance to fill fan-out breadth-first for bounded depth.
    final maxDepth = (log(participantCount) / log(maxFanOut)).ceil() + 1;
    if (depth > maxDepth && rootHex != null) {
      _rebalanceSubtree(rootHex!);
    }
  }

  /// Find a tree node with available capacity (degree < maxFanOut).
  String? _findAvailableParent(Set<String> placed, String? exclude) {
    for (final hex in placed) {
      if (hex == exclude) continue;
      final node = _nodes[hex];
      if (node != null && node.childrenHex.length < maxFanOut) {
        return hex;
      }
    }
    return null;
  }

  /// Detect LAN clusters among participants.
  List<List<String>> _detectLanClusters(
    List<String> participants,
    bool Function(String a, String b)? sameSubnet,
  ) {
    if (sameSubnet == null) {
      return participants.map((p) => [p]).toList();
    }

    // Union-Find clustering
    final parent = <String, String>{};
    for (final p in participants) {
      parent[p] = p;
    }

    String find(String x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]!]!;
        x = parent[x]!;
      }
      return x;
    }

    for (var i = 0; i < participants.length; i++) {
      for (var j = i + 1; j < participants.length; j++) {
        if (sameSubnet(participants[i], participants[j])) {
          final ra = find(participants[i]);
          final rb = find(participants[j]);
          if (ra != rb) parent[ra] = rb;
        }
      }
    }

    final clusters = <String, List<String>>{};
    for (final p in participants) {
      final root = find(p);
      clusters.putIfAbsent(root, () => []).add(p);
    }

    return clusters.values.toList();
  }

  // ── Rebalancing ─────────────────────────────────────────────────────

  /// Add a new participant to the tree.
  /// Attaches to the node with least depth and available capacity.
  void addParticipant(String nodeIdHex) {
    if (_nodes.containsKey(nodeIdHex)) return;
    if (_nodes.isEmpty) {
      rootHex = nodeIdHex;
      _nodes[nodeIdHex] = TreeNode(nodeIdHex: nodeIdHex);
      version++;
      return;
    }

    // Find the shallowest node with available fan-out
    final bestParent = _findShallowestAvailable();
    _nodes[nodeIdHex] = TreeNode(
      nodeIdHex: nodeIdHex,
      parentHex: bestParent,
    );
    if (bestParent != null) {
      _nodes[bestParent]!.childrenHex.add(nodeIdHex);
    }
    version++;

    // Check if rebalance needed: depth > log₃(N) + 1
    final maxDepth = (log(participantCount) / log(maxFanOut)).ceil() + 1;
    if (depth > maxDepth) {
      _rebalanceSubtree(rootHex!);
    }
  }

  /// Remove a participant (graceful leave).
  /// Reassigns orphaned children to the leaving node's parent.
  void removeParticipant(String nodeIdHex) {
    final node = _nodes.remove(nodeIdHex);
    if (node == null) return;
    version++;

    // Remove from parent's children
    if (node.parentHex != null) {
      _nodes[node.parentHex]?.childrenHex.remove(nodeIdHex);
    }

    // Reassign children to the leaving node's parent (or find alternatives)
    for (final childHex in node.childrenHex) {
      final child = _nodes[childHex];
      if (child == null) continue;

      if (node.parentHex != null &&
          _nodes[node.parentHex] != null &&
          _nodes[node.parentHex]!.childrenHex.length < maxFanOut) {
        // Attach to grandparent
        child.parentHex = node.parentHex;
        _nodes[node.parentHex]!.childrenHex.add(childHex);
      } else {
        // Find any node with capacity
        final altParent = _findAvailableParent(
            _nodes.keys.toSet(), childHex);
        child.parentHex = altParent;
        if (altParent != null) {
          _nodes[altParent]!.childrenHex.add(childHex);
        }
      }
    }

    // If root was removed, promote first child or pick another
    if (nodeIdHex == rootHex) {
      if (_nodes.isNotEmpty) {
        rootHex = _nodes.keys.first;
        _nodes[rootHex!]!.parentHex = null;
      } else {
        rootHex = null;
      }
    }
  }

  /// Handle a crashed participant (detected by timeout).
  /// Same as removeParticipant but can trigger subtree reattach.
  void handleCrash(String nodeIdHex) {
    removeParticipant(nodeIdHex);
  }

  /// Find the shallowest tree node with available fan-out capacity.
  String? _findShallowestAvailable() {
    if (rootHex == null) return null;

    // BFS from root — first node with capacity wins
    final queue = Queue<String>();
    queue.add(rootHex!);
    final visited = <String>{rootHex!};

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      final node = _nodes[current];
      if (node == null) continue;

      if (node.childrenHex.length < maxFanOut) return current;

      for (final child in node.childrenHex) {
        if (!visited.contains(child)) {
          visited.add(child);
          queue.add(child);
        }
      }
    }

    return null; // All nodes full — shouldn't happen with reasonable fan-out
  }

  /// Rebalance a subtree rooted at [subtreeRootHex].
  /// Collects all descendants, sorts by depth preference, re-attaches.
  void _rebalanceSubtree(String subtreeRootHex) {
    final descendants = _collectDescendants(subtreeRootHex);
    if (descendants.length <= 1) return;

    // Detach all descendants
    for (final hex in descendants) {
      if (hex == subtreeRootHex) continue;
      _nodes[hex]?.childrenHex.clear();
      _nodes[hex]?.parentHex = null;
    }
    _nodes[subtreeRootHex]?.childrenHex.clear();

    // Re-attach using BFS (breadth-first gives balanced tree)
    final queue = Queue<String>();
    queue.add(subtreeRootHex);
    final remaining = descendants.where((h) => h != subtreeRootHex).toList();
    var idx = 0;

    while (queue.isNotEmpty && idx < remaining.length) {
      final current = queue.removeFirst();
      final node = _nodes[current]!;

      while (node.childrenHex.length < maxFanOut && idx < remaining.length) {
        final childHex = remaining[idx++];
        node.childrenHex.add(childHex);
        _nodes[childHex]!.parentHex = current;
        queue.add(childHex);
      }
    }

    version++;
  }

  /// Collect all descendants of a node (BFS).
  List<String> _collectDescendants(String hex) {
    final result = <String>[];
    final queue = Queue<String>();
    queue.add(hex);

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      result.add(current);
      for (final child in _nodes[current]?.childrenHex ?? []) {
        queue.add(child);
      }
    }

    return result;
  }

  /// Check cumulative latency from root to a leaf.
  /// Returns the max cumulative RTT across all paths.
  int cumulativeLatency(RttMeasurement rtt) {
    if (rootHex == null) return 0;
    return _maxLatency(rootHex!, rtt, 0);
  }

  int _maxLatency(String hex, RttMeasurement rtt, int cumulative) {
    final node = _nodes[hex];
    if (node == null || node.childrenHex.isEmpty) return cumulative;

    int maxL = cumulative;
    for (final child in node.childrenHex) {
      final edgeRtt = rtt.effectiveRtt(hex, child) ?? 50; // 50ms default
      final childL = _maxLatency(child, rtt, cumulative + edgeRtt);
      if (childL > maxL) maxL = childL;
    }
    return maxL;
  }

  /// Check if rebalancing is needed based on cumulative latency.
  bool needsRebalance(RttMeasurement rtt) {
    return cumulativeLatency(rtt) > maxCumulativeLatencyMs;
  }

  /// Full rebalance of the entire tree.
  void rebalance() {
    if (rootHex != null) _rebalanceSubtree(rootHex!);
  }

  // ── Serialization ───────────────────────────────────────────────────

  /// Export tree as a list of node descriptions (for CALL_TREE_UPDATE).
  List<Map<String, dynamic>> toNodeList() {
    return _nodes.values.map((n) => {
          'nodeIdHex': n.nodeIdHex,
          'parentHex': n.parentHex,
          'childrenHex': n.childrenHex,
          'isLanClusterHead': n.isLanClusterHead,
          'lanMemberHex': n.lanMemberHex,
        }).toList();
  }

  /// Import tree from a node list (received via CALL_TREE_UPDATE).
  void fromNodeList(List<Map<String, dynamic>> nodeList, String rootNodeHex) {
    _nodes.clear();
    rootHex = rootNodeHex;

    for (final entry in nodeList) {
      final hex = entry['nodeIdHex'] as String;
      _nodes[hex] = TreeNode(
        nodeIdHex: hex,
        parentHex: entry['parentHex'] as String?,
        childrenHex: List<String>.from(entry['childrenHex'] as List),
        isLanClusterHead: entry['isLanClusterHead'] as bool? ?? false,
        lanMemberHex: List<String>.from(entry['lanMemberHex'] as List? ?? []),
      );
    }

    version++;
  }
}
