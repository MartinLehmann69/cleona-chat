import 'dart:typed_data';
import 'package:cleona/core/network/peer_info.dart';

// Distance-Vector Routing Table (V3)
//
// Separate from Kademlia k-buckets. Kademlia = "who is close to key X in the DHT?"
// DV-Routing = "how do I reach peer X most cheaply?"
//
// Bellman-Ford + Split Horizon + Poison Reverse.

/// Routing tier classification (Architecture 2.2.3).
enum RouteTier { contact, transit, channel }

class DvRoutingTable {
  final Uint8List ownNodeId;
  final String _ownHex;

  // destHex → [Route] sorted by cost (cheapest first)
  final Map<String, List<Route>> _routes = {};

  // Direct neighbors: neighborHex → ConnectionType
  final Map<String, ConnectionType> _neighbors = {};

  // Default gateway (neighbor with the broadest network knowledge)
  String? _defaultGatewayHex;

  // Relay-confirmed neighbors: neighbors through which we have actually
  // received messages (DELIVERY_RECEIPT, Relay-Delivery).
  // Only these are reliable relay partners — pure Discovery/PONG neighbors
  // could be behind AP isolation (unicast doesn't pass through).
  final Set<String> _relayConfirmedNeighbors = {};

  // Three-tier capacity classification (Architecture 2.2.3)
  final Set<String> _contactIds = {};
  final Set<String> _channelMemberIds = {};

  // Tier capacity limits
  static const int maxContactDestinations = 1000;
  static const int maxTransitDestinations = 640;
  static const int maxChannelDestinations = 500;

  // Callback: fired when a route changes (for propagation)
  void Function(String destHex, int cost)? onRouteChanged;

  DvRoutingTable({required this.ownNodeId})
      : _ownHex = bytesToHex(ownNodeId);

  String? get defaultGatewayHex => _defaultGatewayHex;
  Map<String, ConnectionType> get neighbors => Map.unmodifiable(_neighbors);
  int get routeCount => _routes.values.fold(0, (sum, list) => sum + list.length);
  int get destinationCount => _routes.length;
  bool isRelayConfirmed(String neighborHex) => _relayConfirmedNeighbors.contains(neighborHex);

  // ── Tier Registration ─────────────────────────────────────────────────

  /// Register a destination as a contact (NEVER evicted).
  void registerContact(String destHex) => _contactIds.add(destHex);

  /// Unregister a contact destination.
  void unregisterContact(String destHex) => _contactIds.remove(destHex);

  /// Register a destination as a channel member.
  void registerChannelMember(String destHex) => _channelMemberIds.add(destHex);

  /// Unregister a channel member destination.
  void unregisterChannelMember(String destHex) => _channelMemberIds.remove(destHex);

  /// Classify a destination into its routing tier.
  RouteTier tierOf(String destHex) {
    if (_contactIds.contains(destHex)) return RouteTier.contact;
    if (_channelMemberIds.contains(destHex)) return RouteTier.channel;
    return RouteTier.transit;
  }

  /// Count destinations per tier.
  Map<RouteTier, int> get tierCounts {
    int contact = 0, channel = 0, transit = 0;
    for (final destHex in _routes.keys) {
      switch (tierOf(destHex)) {
        case RouteTier.contact: contact++;
        case RouteTier.channel: channel++;
        case RouteTier.transit: transit++;
      }
    }
    return {RouteTier.contact: contact, RouteTier.channel: channel, RouteTier.transit: transit};
  }

  /// Marks a neighbor as relay-confirmed: we have actually received a
  /// message through this neighbor (Relay-Delivery, ACK).
  /// Such neighbors are preferred in default gateway selection.
  void confirmRelayNeighbor(String neighborHex) {
    _relayConfirmedNeighbors.add(neighborHex);
  }

  // ── Direct Neighbors ──────────────────────────────────────────────────

  /// Registers a direct neighbor (hop 1).
  /// Creates a direct route with cost = connectionTypeCost(connType).
  /// Returns true if the route is new or better.
  bool addDirectNeighbor(Uint8List nodeId, ConnectionType connType) {
    final hex = bytesToHex(nodeId);
    if (hex == _ownHex) return false; // No route to ourselves

    _neighbors[hex] = connType;

    final cost = connectionTypeCost(connType);
    final existing = bestRouteTo(hex);

    // If an equally good or better direct route already exists
    if (existing != null && existing.isDirect && existing.cost <= cost && existing.isAlive) {
      return false;
    }

    // Create/update direct route
    final route = Route(
      destination: Uint8List.fromList(nodeId),
      nextHop: null, // direct
      hopCount: 1,
      cost: cost,
      type: RouteType.direct,
      connType: connType,
    );

    _addOrUpdateRoute(hex, route);
    onRouteChanged?.call(hex, cost);
    return true;
  }

  /// Removes a neighbor and all routes that go through it.
  void removeNeighbor(Uint8List nodeId) {
    final hex = bytesToHex(nodeId);
    _neighbors.remove(hex);

    // Remove all routes that have this neighbor as nextHop
    final toNotify = <String, int>{};
    _routes.forEach((destHex, routes) {
      routes.removeWhere((r) {
        if (r.nextHopHex == hex || (r.isDirect && r.destinationHex == hex)) {
          return true;
        }
        return false;
      });
      if (routes.isEmpty) {
        toNotify[destHex] = Route.infinity;
      }
    });

    // Remove empty entries
    _routes.removeWhere((_, routes) => routes.isEmpty);

    // Poison Reverse for removed destinations
    for (final entry in toNotify.entries) {
      onRouteChanged?.call(entry.key, entry.value);
    }

    // Update default gateway if needed
    if (_defaultGatewayHex == hex) {
      updateDefaultGateway();
    }
  }

  // ── Bellman-Ford ──────────────────────────────────────────────────────

  /// Processes a ROUTE_UPDATE from a neighbor.
  /// Bellman-Ford: newCost = costToNeighbor + advertisedCost
  /// If cost >= infinity = Poison Reverse (remove route).
  /// Returns true if at least one route changed.
  bool processRouteUpdate(Uint8List fromNodeId, List<RouteEntry> entries) {
    final fromHex = bytesToHex(fromNodeId);

    // Only accept updates from known neighbors
    final neighborConnType = _neighbors[fromHex];
    if (neighborConnType == null) return false;

    final linkCost = connectionTypeCost(neighborConnType);
    var changed = false;

    for (final entry in entries) {
      final destHex = entry.destinationHex;

      // No route to ourselves
      if (destHex == _ownHex) continue;

      // Poison Reverse: neighbor reports route as dead
      if (entry.cost >= Route.infinity) {
        final removed = _removeRoutesVia(destHex, fromHex);
        if (removed) {
          changed = true;
          final best = bestRouteTo(destHex);
          onRouteChanged?.call(destHex, best?.cost ?? Route.infinity);
        }
        continue;
      }

      // Bellman-Ford: calculate new cost
      var newCost = linkCost + entry.cost;
      if (newCost >= Route.infinity) newCost = Route.infinity;
      final newHopCount = entry.hopCount + 1;

      // Existing route via this neighbor?
      final existingVia = _findRouteVia(destHex, fromHex);

      if (existingVia != null) {
        // Route via same neighbor: always update (can get better or worse)
        if (existingVia.cost != newCost || existingVia.hopCount != newHopCount) {
          existingVia.cost = newCost;
          existingVia.hopCount = newHopCount;
          existingVia.lastConfirmed = DateTime.now();
          _sortRoutes(destHex);
          changed = true;
          onRouteChanged?.call(destHex, bestRouteTo(destHex)?.cost ?? Route.infinity);
        }
      } else {
        // New route via this neighbor — ALWAYS add (as fallback).
        // _addOrUpdateRoute limits to max 5 routes per destination.
        final route = Route(
          destination: hexToBytes(destHex),
          nextHop: Uint8List.fromList(fromNodeId),
          hopCount: newHopCount,
          cost: newCost,
          type: RouteType.relay,
          connType: entry.connType,
        );
        _addOrUpdateRoute(destHex, route);
        changed = true;
        final bestCost = bestRouteTo(destHex)?.cost ?? Route.infinity;
        onRouteChanged?.call(destHex, bestCost);
      }
    }

    return changed;
  }

  // ── Split Horizon ─────────────────────────────────────────────────────

  /// Builds a ROUTE_UPDATE for a specific neighbor.
  /// Split Horizon: routes learned via this neighbor are NOT
  /// advertised back to it.
  /// Recently dead routes (5-min grace) are advertised with cost=infinity
  /// (Poison Reverse) so neighbors remove the route.
  List<RouteEntry> buildUpdateFor(String neighborHex) {
    final result = <RouteEntry>[];
    final now = DateTime.now();

    _routes.forEach((destHex, routes) {
      if (routes.isEmpty) return;
      final best = routes.first; // cheapest route

      // Split Horizon: don't advertise back to the neighbor we learned from
      if (best.nextHopHex == neighborHex) return;

      if (best.isAlive) {
        result.add(RouteEntry(
          destinationHex: destHex,
          hopCount: best.hopCount,
          cost: best.cost,
          connType: best.connType,
        ));
      } else if (now.difference(best.lastConfirmed).inMinutes <= 5) {
        // Recently dead route: Poison Reverse with cost=infinity
        // so neighbors remove the route (prevents routing black holes)
        result.add(RouteEntry(
          destinationHex: destHex,
          hopCount: best.hopCount,
          cost: Route.infinity,
          connType: best.connType,
        ));
      }
    });

    return result;
  }

  /// Builds a full ROUTE_UPDATE (for 1h safety net).
  /// Without Split Horizon — all best routes.
  /// Recently dead routes (5-min grace) are advertised with cost=infinity.
  List<RouteEntry> buildFullUpdate() {
    final result = <RouteEntry>[];
    final now = DateTime.now();

    _routes.forEach((destHex, routes) {
      if (routes.isEmpty) return;
      final best = routes.first;

      if (best.isAlive) {
        result.add(RouteEntry(
          destinationHex: destHex,
          hopCount: best.hopCount,
          cost: best.cost,
          connType: best.connType,
        ));
      } else if (now.difference(best.lastConfirmed).inMinutes <= 5) {
        // Recently dead route: Poison Reverse with cost=infinity
        result.add(RouteEntry(
          destinationHex: destHex,
          hopCount: best.hopCount,
          cost: Route.infinity,
          connType: best.connType,
        ));
      }
    });

    return result;
  }

  // ── Route-Down / Poison Reverse ───────────────────────────────────────

  /// Marks a route as DOWN (cost = infinity).
  /// Fires onRouteChanged with infinity for Poison Reverse propagation.
  void markRouteDown(String destHex, {String? viaNextHopHex}) {
    final routes = _routes[destHex];
    if (routes == null) return;

    if (viaNextHopHex != null) {
      // Only mark the route via the specific neighbor as DOWN
      for (final r in routes) {
        if (r.nextHopHex == viaNextHopHex || (r.isDirect && r.destinationHex == destHex && viaNextHopHex == destHex)) {
          r.cost = Route.infinity;
          r.consecutiveFailures = 3;
          r.ackConfirmed = false;
        }
      }
    } else {
      // All routes to this destination as DOWN
      for (final r in routes) {
        r.cost = Route.infinity;
        r.consecutiveFailures = 3;
        r.ackConfirmed = false;
      }
    }

    _sortRoutes(destHex);

    // Dead routes: 5-min grace period for recovery via neighbor updates.
    // Only remove routes that have been dead for >5 min.
    final now = DateTime.now();
    routes.removeWhere((r) =>
        !r.isAlive && now.difference(r.lastConfirmed).inMinutes > 5);
    if (routes.isEmpty) _routes.remove(destHex);

    final best = bestRouteTo(destHex);
    onRouteChanged?.call(destHex, best?.cost ?? Route.infinity);
  }

  /// Confirms a route (DELIVERY_RECEIPT received).
  /// Sets ackConfirmed=true so sendEnvelope knows direct delivery works
  /// and can skip redundant relay sends.
  void confirmRoute(String destHex) {
    final routes = _routes[destHex];
    if (routes == null || routes.isEmpty) return;
    // Confirmation applies to the primary (cheapest) route
    routes.first.consecutiveFailures = 0;
    routes.first.lastConfirmed = DateTime.now();
    routes.first.ackConfirmed = true;
  }

  /// Records a failure on the primary route.
  void recordRouteFailure(String destHex) {
    final routes = _routes[destHex];
    if (routes == null || routes.isEmpty) return;
    routes.first.consecutiveFailures++;
  }

  // ── Queries ──────────────────────────────────────────────────────────

  /// Cheapest alive route to the destination, or null.
  Route? bestRouteTo(String destHex) {
    final routes = _routes[destHex];
    if (routes == null) return null;
    for (final r in routes) {
      if (r.isAlive) return r;
    }
    return null;
  }

  /// All routes to a destination, sorted by cost.
  List<Route> routesTo(String destHex) {
    return List.unmodifiable(_routes[destHex] ?? []);
  }

  /// Whether at least one alive route to the destination exists.
  bool hasAliveRouteTo(String destHex) => bestRouteTo(destHex) != null;

  /// All known destinations.
  Set<String> get allDestinations => _routes.keys.toSet();

  // ── Default-Gateway ───────────────────────────────────────────────────

  /// Selects the best default gateway:
  /// Chooses the best neighbor as default gateway.
  /// Primary criterion: relay-confirmed (DELIVERY_RECEIPT/Relay-Delivery
  /// received) beats pure Discovery/PONG neighbors.
  /// Secondary: most routes → lowest avg cost → most recent confirmation.
  void updateDefaultGateway() {
    if (_neighbors.isEmpty) {
      _defaultGatewayHex = null;
      return;
    }

    // For each neighbor, count: how many destinations are reachable through it?
    final scores = <String, _GatewayScore>{};

    for (final neighborHex in _neighbors.keys) {
      var routeCount = 0;
      var totalCost = 0;
      DateTime? newestConfirm;

      _routes.forEach((_, routes) {
        for (final r in routes) {
          if (r.isAlive && (r.nextHopHex == neighborHex || (r.isDirect && r.destinationHex == neighborHex))) {
            routeCount++;
            totalCost += r.cost;
            if (newestConfirm == null || r.lastConfirmed.isAfter(newestConfirm!)) {
              newestConfirm = r.lastConfirmed;
            }
            break; // Only count the best route per destination
          }
        }
      });

      scores[neighborHex] = _GatewayScore(
        routeCount: routeCount,
        avgCost: routeCount > 0 ? totalCost / routeCount : double.infinity,
        newestConfirm: newestConfirm ?? DateTime(2000),
        relayConfirmed: _relayConfirmedNeighbors.contains(neighborHex),
      );
    }

    // Sort: relay-confirmed first, then most routes → cost → recency
    final sorted = scores.entries.toList()
      ..sort((a, b) {
        // Relay-confirmed neighbors ALWAYS before unconfirmed ones
        if (a.value.relayConfirmed != b.value.relayConfirmed) {
          return a.value.relayConfirmed ? -1 : 1;
        }
        final routeCmp = b.value.routeCount.compareTo(a.value.routeCount);
        if (routeCmp != 0) return routeCmp;
        final costCmp = a.value.avgCost.compareTo(b.value.avgCost);
        if (costCmp != 0) return costCmp;
        return b.value.newestConfirm.compareTo(a.value.newestConfirm);
      });

    _defaultGatewayHex = sorted.isNotEmpty ? sorted.first.key : null;
  }

  // ── Reset ─────────────────────────────────────────────────────────────

  /// Clear all routes (e.g. on network change).
  /// Neighbors are preserved — must be re-registered manually.
  void clearAllRoutes() {
    _routes.clear();
    _defaultGatewayHex = null;
  }

  /// Full reset (routes + neighbors).
  void reset() {
    _routes.clear();
    _neighbors.clear();
    _defaultGatewayHex = null;
  }

  // ── Internal Helper Methods ─────────────────────────────────────────────

  void _addOrUpdateRoute(String destHex, Route route) {
    final isNewDestination = !_routes.containsKey(destHex);
    final routes = _routes.putIfAbsent(destHex, () => []);

    // Replace existing route with the same nextHop
    final nhHex = route.nextHopHex;
    routes.removeWhere((r) =>
        r.nextHopHex == nhHex ||
        (route.isDirect && r.isDirect));

    routes.add(route);
    _sortRoutes(destHex);

    // Max 5 routes per destination
    if (routes.length > 5) {
      routes.removeRange(5, routes.length);
    }

    // Three-tier capacity enforcement (Architecture 2.2.3)
    if (isNewDestination) {
      _enforceTierCapacity(destHex);
    }
  }

  /// Enforce tier capacity limits. Evicts one destination from the same tier
  /// if over capacity. Contact tier is NEVER evicted.
  void _enforceTierCapacity(String newDestHex) {
    final tier = tierOf(newDestHex);
    final int limit;
    switch (tier) {
      case RouteTier.contact:
        // Contacts are never evicted — just cap at hard limit
        if (_contactIds.length > maxContactDestinations) return;
        return;
      case RouteTier.transit:
        limit = maxTransitDestinations;
      case RouteTier.channel:
        limit = maxChannelDestinations;
    }

    // Count destinations in this tier
    final tierDests = _routes.keys.where((d) => tierOf(d) == tier).toList();
    if (tierDests.length <= limit) return;

    // Evict: highest cost (best route) + oldest lastConfirmed
    // Never evict the just-added destination
    String? evictHex;
    int evictCost = -1;
    DateTime evictConfirmed = DateTime.now();

    for (final destHex in tierDests) {
      if (destHex == newDestHex) continue;
      final best = bestRouteTo(destHex);
      if (best == null) {
        // No alive route — prime eviction candidate
        evictHex = destHex;
        break;
      }
      // Prefer evicting: highest cost, then oldest confirmation
      if (best.cost > evictCost ||
          (best.cost == evictCost && best.lastConfirmed.isBefore(evictConfirmed))) {
        evictCost = best.cost;
        evictConfirmed = best.lastConfirmed;
        evictHex = destHex;
      }
    }

    if (evictHex != null) {
      _routes.remove(evictHex);
    }
  }

  void _sortRoutes(String destHex) {
    final routes = _routes[destHex];
    if (routes == null) return;
    routes.sort((a, b) => a.cost.compareTo(b.cost));
  }

  bool _removeRoutesVia(String destHex, String viaHex) {
    final routes = _routes[destHex];
    if (routes == null) return false;
    final before = routes.length;
    routes.removeWhere((r) => r.nextHopHex == viaHex);
    if (routes.isEmpty) _routes.remove(destHex);
    return routes.length < before || (before > 0 && routes.isEmpty);
  }

  Route? _findRouteVia(String destHex, String viaHex) {
    final routes = _routes[destHex];
    if (routes == null) return null;
    for (final r in routes) {
      if (r.nextHopHex == viaHex) return r;
    }
    return null;
  }
}

// ── Data Class for Route Updates ──────────────────────────────────────

class RouteEntry {
  final String destinationHex;
  final int hopCount;
  final int cost;
  final ConnectionType connType;

  RouteEntry({
    required this.destinationHex,
    required this.hopCount,
    required this.cost,
    required this.connType,
  });
}

// ── Internal Score Class for Default Gateway Selection ──────────────────

class _GatewayScore {
  final int routeCount;
  final double avgCost;
  final DateTime newestConfirm;
  final bool relayConfirmed;

  _GatewayScore({
    required this.routeCount,
    required this.avgCost,
    required this.newestConfirm,
    required this.relayConfirmed,
  });
}
