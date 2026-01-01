import 'dart:typed_data';
import 'package:cleona/core/network/peer_info.dart';

// Distance-Vector Routing Table (V3)
//
// Separate from Kademlia k-buckets. Kademlia = "who is close to key X in the DHT?"
// DV-Routing = "how do I reach peer X most cheaply?"
//
// Bellman-Ford + Split Horizon + Poison Reverse.

/// Result of processing a batch of route updates. Callers can inspect
/// [updatedDestinations] to decide which neighbors need propagation
/// instead of broadcasting to all.
class RouteUpdateResult {
  final bool changed;
  final List<String> updatedDestinations;

  const RouteUpdateResult({required this.changed, required this.updatedDestinations});
  const RouteUpdateResult.noChange() : changed = false, updatedDestinations = const [];
}

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

  // DV-3: Cost-Bias for direct routes that have not been ack-confirmed yet.
  // Initial cost-sort prefers indirect-via-relay over an unproven direct path
  // until the first DELIVERY_RECEIPT proves bidirectional UDP works. Once
  // confirmRoute fires, ackConfirmed flips true and the bias disappears.
  // Applied on-the-fly in _sortRoutes; the route's persisted `cost` is unchanged.
  static const int unconfirmedDirectBias = 10;

  // Callback: fired when a route changes (for propagation)
  void Function(String destHex, int cost)? onRouteChanged;

  DvRoutingTable({required this.ownNodeId})
      : _ownHex = bytesToHex(ownNodeId);

  String? get defaultGatewayHex => _defaultGatewayHex;
  Map<String, ConnectionType> get neighbors => Map.unmodifiable(_neighbors);
  int get routeCount => _routes.values.fold(0, (sum, list) => sum + list.length);
  int get destinationCount => _routes.length;

  /// All current neighbor IDs (hex). Used by maintenance to detect zombie
  /// neighbors that were evicted from the routing table but linger in the
  /// DV neighbor map (H-3).
  List<String> get neighborIds => _neighbors.keys.toList();
  bool isRelayConfirmed(String neighborHex) => _relayConfirmedNeighbors.contains(neighborHex);

  // ── Tier Registration ─────────────────────────────────────────────────

  /// Register a destination as a contact (NEVER evicted).
  void registerContact(String destHex) => _contactIds.add(destHex);

  /// Unregister a contact destination.
  void unregisterContact(String destHex) => _contactIds.remove(destHex);

  /// Atomically replace the full set of contact device-IDs.
  void replaceContactIds(Set<String> ids) {
    _contactIds.clear();
    _contactIds.addAll(ids);
  }

  /// Register a destination as a channel member.
  void registerChannelMember(String destHex) => _channelMemberIds.add(destHex);

  /// Unregister a channel member destination.
  void unregisterChannelMember(String destHex) => _channelMemberIds.remove(destHex);

  /// Atomically replace the full set of channel-member device-IDs.
  void replaceChannelMemberIds(Set<String> ids) {
    _channelMemberIds.clear();
    _channelMemberIds.addAll(ids);
  }

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
  ///
  /// DV-8: lookup is direct-route-specific, NOT via bestRouteTo. Under DV-3
  /// the unconfirmed-direct cost-bias may push a perfectly alive direct route
  /// behind an indirect alternative in the sort order — bestRouteTo would
  /// then return the indirect route, this function would (incorrectly) decide
  /// "no direct route exists yet", return true, and the caller would fire a
  /// Welcome-Update. Repeated for every inbound packet from the same neighbor
  /// this turns into a Welcome-Update-Storm (~30–50/s observed live).
  bool addDirectNeighbor(Uint8List nodeId, ConnectionType connType) {
    final hex = bytesToHex(nodeId);
    if (hex == _ownHex) return false; // No route to ourselves

    _neighbors[hex] = connType;

    final cost = connectionTypeCost(connType);
    Route? existingDirect;
    final routes = _routes[hex];
    if (routes != null) {
      for (final r in routes) {
        if (r.isDirect && r.isAlive) {
          existingDirect = r;
          break;
        }
      }
    }

    // If an equally good or better direct route already exists
    if (existingDirect != null && existingDirect.cost <= cost) {
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
    // H-5: Immediately consider the new neighbor as default gateway
    // candidate instead of waiting for the next maintenance tick.
    updateDefaultGateway();
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

    // Soft-reset revalidation (Architektur §2.7.2): a fresh DV-update from
    // this neighbor proves both the link and the routes learned through it
    // are still alive. Lift the stale flag + cost penalty before processing
    // the entries themselves.
    final revalidated = revalidateRoutesVia(fromHex);
    var changed = revalidated > 0;

    final linkCost = connectionTypeCost(neighborConnType);

    for (final entry in entries) {
      final destHex = entry.destinationHex;

      // No route to ourselves
      if (destHex == _ownHex) continue;

      // N-5: A neighbor advertising a route to itself is nonsensical
      // (it is always reachable directly) and wastes a route slot.
      if (destHex == fromHex) continue;

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

  /// Whether a route update for [destHex] would actually change our best
  /// route. Compares cost, nextHop, and alive status against the current
  /// best. Used by callers to gate propagation: standard Bellman-Ford only
  /// propagates when the local cost vector changes.
  bool hasRouteChanged(String destHex, {required int cost, String? nextHopHex}) {
    final best = bestRouteTo(destHex);
    if (best == null) return cost < Route.infinity;
    if (!best.isAlive && cost < Route.infinity) return true;
    if (best.isAlive && cost >= Route.infinity) return true;
    if (best.cost != cost) return true;
    if (best.nextHopHex != nextHopHex) return true;
    return false;
  }

  /// Like [processRouteUpdate] but returns a [RouteUpdateResult] with the
  /// list of destinations whose best route actually changed. Callers can
  /// use [updatedDestinations] to send targeted updates to neighbors
  /// instead of broadcasting.
  RouteUpdateResult processRouteUpdateDetailed(
      Uint8List fromNodeId, List<RouteEntry> entries) {
    final fromHex = bytesToHex(fromNodeId);
    final neighborConnType = _neighbors[fromHex];
    if (neighborConnType == null) return const RouteUpdateResult.noChange();

    final revalidated = revalidateRoutesVia(fromHex);
    final updatedDests = <String>{};
    if (revalidated > 0) {
      // Revalidation changed costs — snapshot which dests had their best
      // route affected would require a before/after diff. Conservative:
      // mark all revalidated destinations as changed.
      _routes.forEach((destHex, routes) {
        for (final r in routes) {
          final isMatch = r.nextHopHex == fromHex ||
              (r.isDirect && r.destinationHex == fromHex);
          if (isMatch) {
            updatedDests.add(destHex);
            break;
          }
        }
      });
    }

    final linkCost = connectionTypeCost(neighborConnType);

    for (final entry in entries) {
      final destHex = entry.destinationHex;
      if (destHex == _ownHex) continue;
      if (destHex == fromHex) continue;

      final bestBefore = bestRouteTo(destHex);
      final costBefore = bestBefore?.cost ?? Route.infinity;
      final aliveBefore = bestBefore?.isAlive ?? false;

      if (entry.cost >= Route.infinity) {
        final removed = _removeRoutesVia(destHex, fromHex);
        if (removed) {
          final best = bestRouteTo(destHex);
          final costAfter = best?.cost ?? Route.infinity;
          onRouteChanged?.call(destHex, costAfter);
          if (costAfter != costBefore || aliveBefore != (best?.isAlive ?? false)) {
            updatedDests.add(destHex);
          }
        }
        continue;
      }

      var newCost = linkCost + entry.cost;
      if (newCost >= Route.infinity) newCost = Route.infinity;
      final newHopCount = entry.hopCount + 1;

      final existingVia = _findRouteVia(destHex, fromHex);

      if (existingVia != null) {
        if (existingVia.cost != newCost || existingVia.hopCount != newHopCount) {
          existingVia.cost = newCost;
          existingVia.hopCount = newHopCount;
          existingVia.lastConfirmed = DateTime.now();
          _sortRoutes(destHex);
          final best = bestRouteTo(destHex);
          final costAfter = best?.cost ?? Route.infinity;
          onRouteChanged?.call(destHex, costAfter);
          if (costAfter != costBefore) {
            updatedDests.add(destHex);
          }
        }
      } else {
        final route = Route(
          destination: hexToBytes(destHex),
          nextHop: Uint8List.fromList(fromNodeId),
          hopCount: newHopCount,
          cost: newCost,
          type: RouteType.relay,
          connType: entry.connType,
        );
        _addOrUpdateRoute(destHex, route);
        final best = bestRouteTo(destHex);
        final costAfter = best?.cost ?? Route.infinity;
        onRouteChanged?.call(destHex, costAfter);
        if (costAfter != costBefore || !aliveBefore) {
          updatedDests.add(destHex);
        }
      }
    }

    final destList = updatedDests.toList();
    return RouteUpdateResult(
      changed: destList.isNotEmpty,
      updatedDestinations: destList,
    );
  }

  /// Evict routes whose [lastConfirmed] is older than [maxAge] AND that have
  /// [consecutiveFailures] >= 3. Unlike [pruneStaleRoutes] (which handles
  /// the soft-reset stale window), this removes genuinely dead routes that
  /// have not been refreshed for a long time.
  ///
  /// Called lazily during other operations, not on a timer.
  /// Returns the list of destination hex IDs that lost all routes.
  List<String> pruneExpiredRoutes(Duration maxAge, {DateTime? now}) {
    final tNow = now ?? DateTime.now();
    final evictedDests = <String>[];
    final emptiedDests = <String>[];

    _routes.forEach((destHex, routes) {
      final before = routes.length;
      routes.removeWhere((r) =>
          !r.isAlive &&
          tNow.difference(r.lastConfirmed) > maxAge);
      if (routes.length < before) {
        evictedDests.add(destHex);
      }
      if (routes.isEmpty) emptiedDests.add(destHex);
    });

    for (final destHex in emptiedDests) {
      _routes.remove(destHex);
      onRouteChanged?.call(destHex, Route.infinity);
    }

    if (evictedDests.isNotEmpty) updateDefaultGateway();
    return emptiedDests;
  }

  /// Check if any alive routes exist for [destHex] in the DV table.
  /// Used by kbucket eviction to avoid evicting peers with live routes.
  int aliveRouteCountFor(String destHex) {
    final routes = _routes[destHex];
    if (routes == null) return 0;
    return routes.where((r) => r.isAlive).length;
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

  /// Confirms a route after a DELIVERY_RECEIPT.
  ///
  /// This is called from §3.4's centralized ACK→DV bridge ONLY when the
  /// receipt arrived directly from the recipient (`wasDirect=true`),
  /// proving bidirectional UDP works. The caller therefore wants to
  /// flip ackConfirmed=true on the **direct** route — not on whatever
  /// route happens to be primary, which under DV-3's unconfirmed-direct
  /// bias is often an indirect-via-relay entry.
  ///
  /// If no direct route exists, falls back to the primary route to keep
  /// pre-DV-3 behavior for callers that may target relay-only paths.
  void confirmRoute(String destHex) {
    final routes = _routes[destHex];
    if (routes == null || routes.isEmpty) return;
    final target = routes.firstWhere(
      (r) => r.isDirect,
      orElse: () => routes.first,
    );
    target.consecutiveFailures = 0;
    target.lastConfirmed = DateTime.now();
    target.ackConfirmed = true;
    // ackConfirmed flip lifts the DV-3 bias → re-sort so the direct
    // route can take its rightful primary slot.
    _sortRoutes(destHex);
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
        avgCost: routeCount > 0 ? totalCost / routeCount : 999999,
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

  // ── Persistence (Architektur §2.7.3) ────────────────────────────────

  /// Serialize the DV-table for `dv_routing.json` persistence.
  ///
  /// Persisted fields cover what makes the post-reboot topology *useful*:
  /// `_routes` (the learned next-hops), `_neighbors` (direct adjacencies
  /// learned from authenticated V3 receives), `_defaultGatewayHex` (the
  /// chosen gateway for unknown destinations) and `_relayConfirmedNeighbors`
  /// (peers proven to actually deliver via observed RELAY_DELIVERY/ACK).
  ///
  /// Tier registries (`_contactIds`, `_channelMemberIds`) are intentionally
  /// **not** persisted here — they are re-populated at service start from
  /// `contacts.json.enc` / channel registry via `dv.registerContact` /
  /// `dv.registerChannelMember` (cleona_service.dart:5818+), and a stale
  /// duplicate written here would only invite drift between the two sources.
  Map<String, dynamic> toJson() => {
        'neighbors': _neighbors.map((hex, ct) => MapEntry(hex, ct.name)),
        'routes': _routes.map((destHex, list) =>
            MapEntry(destHex, list.map((r) => r.toJson()).toList())),
        if (_defaultGatewayHex != null) 'defaultGatewayHex': _defaultGatewayHex,
        'relayConfirmedNeighbors': _relayConfirmedNeighbors.toList(),
      };

  /// Restore the DV-table from its persisted JSON form. Every loaded route
  /// is immediately marked **stale** (Architektur §2.7.2 stale semantics):
  /// the +5 cost penalty makes any freshly-revalidated post-boot route
  /// preferred, and `cleona_node.onNetworkChanged` already wires the 30 s
  /// `pruneStaleRoutes` sweep that drops routes whose `lastConfirmed`
  /// did not refresh within the deadline.
  ///
  /// Net effect: a restarted node has an *immediately useful* topology
  /// hypothesis (no `cascade exhausted` storm in the first second after
  /// boot), but the hypothesis self-corrects within 30 s — exactly the
  /// soft-reset behaviour, just sourced from disk instead of the previous
  /// in-memory state.
  ///
  /// Corrupted entries are skipped silently; a malformed file may yield a
  /// partially-loaded table but never a crash on boot.
  void loadFromJson(Map<String, dynamic> json) {
    final neighborsJson = json['neighbors'] as Map<String, dynamic>?;
    if (neighborsJson != null) {
      neighborsJson.forEach((hex, ctName) {
        final ct = ConnectionType.values.firstWhere(
          (e) => e.name == ctName,
          orElse: () => ConnectionType.publicUdp,
        );
        _neighbors[hex] = ct;
      });
    }

    final routesJson = json['routes'] as Map<String, dynamic>?;
    if (routesJson != null) {
      routesJson.forEach((destHex, listJson) {
        if (destHex == _ownHex) return; // never a route to ourselves
        final list = <Route>[];
        for (final entry in (listJson as List<dynamic>)) {
          try {
            list.add(Route.fromJson(entry as Map<String, dynamic>));
          } catch (_) {
            // Skip individual corrupt entries; keep the rest.
          }
        }
        if (list.isNotEmpty) _routes[destHex] = list;
      });
    }

    final rcn = json['relayConfirmedNeighbors'] as List<dynamic>?;
    if (rcn != null) {
      for (final hex in rcn) {
        if (hex is String) _relayConfirmedNeighbors.add(hex);
      }
    }

    // Mark every loaded route as stale (cost +5, 30 s revalidation deadline).
    // The caller is expected to schedule `pruneStaleRoutes(30s)` — typically
    // by piggy-backing on the existing soft-reset machinery.
    markAllRoutesStale();

    // Re-elect default-GW from loaded routes instead of blindly restoring
    // the persisted value — a stale GW pointing to a dead node would
    // black-hole ALL traffic until the 30 s prune fires.
    updateDefaultGateway();
  }

  // ── Soft-Reset (Architektur §2.7.2 / §7.6) ──────────────────────────

  /// Mark all routes as stale on a network change. Each route gets a +5 cost
  /// penalty and a `staleSince` timestamp; routes remain queryable so the
  /// cascade can keep using them while fresh routes (via PING / DV-update)
  /// are revalidated. Use [pruneStaleRoutes] after the revalidation deadline
  /// to drop routes that did not re-confirm.
  ///
  /// Returns the number of routes marked stale.
  int markAllRoutesStale({DateTime? now}) {
    final tNow = now ?? DateTime.now();
    var count = 0;
    _routes.forEach((destHex, routes) {
      for (final r in routes) {
        if (!r.isStale) {
          r.markStale(now: tNow);
          count++;
        }
      }
      _sortRoutes(destHex);
    });
    return count;
  }

  /// Revalidate every route whose `nextHop` is the given neighbor (or, for
  /// direct routes, whose destination IS the neighbor itself). Called on
  /// PONG receipt or incoming DV-update — the live signal proves both the
  /// neighbor link and the topology learned through it are still good.
  ///
  /// Returns the number of routes revalidated.
  int revalidateRoutesVia(String neighborHex, {DateTime? now}) {
    final tNow = now ?? DateTime.now();
    var count = 0;
    _routes.forEach((destHex, routes) {
      var anyChanged = false;
      for (final r in routes) {
        if (!r.isStale) continue;
        final isMatch = r.nextHopHex == neighborHex ||
            (r.isDirect && r.destinationHex == neighborHex);
        if (isMatch) {
          r.revalidate(now: tNow);
          count++;
          anyChanged = true;
        }
      }
      if (anyChanged) _sortRoutes(destHex);
    });
    return count;
  }

  /// Drop routes that have been stale for longer than [maxAge]. Called by
  /// `CleonaNode.onNetworkChanged` from a delayed timer (default 30 s after
  /// the soft-reset). Routes that re-confirmed via [revalidateRoutesVia] in
  /// the meantime are skipped.
  ///
  /// Returns the number of routes removed.
  int pruneStaleRoutes(Duration maxAge, {DateTime? now}) {
    final tNow = now ?? DateTime.now();
    var removed = 0;
    final emptiedDests = <String>[];
    _routes.forEach((destHex, routes) {
      final before = routes.length;
      routes.removeWhere((r) =>
          r.isStale &&
          r.staleSince != null &&
          tNow.difference(r.staleSince!) > maxAge);
      removed += before - routes.length;
      if (routes.isEmpty) emptiedDests.add(destHex);
    });
    for (final destHex in emptiedDests) {
      _routes.remove(destHex);
      onRouteChanged?.call(destHex, Route.infinity);
    }
    if (removed > 0) updateDefaultGateway();
    return removed;
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
    routes.sort((a, b) {
      final c = _effectiveCost(a).compareTo(_effectiveCost(b));
      if (c != 0) return c;
      // Tiebreaker: fewer hops wins. Direct routes (hopCount=1) thus beat
      // relay routes (hopCount>=2) at equal effective cost — important when
      // ackConfirmed direct ties with indirect on raw cost.
      return a.hopCount.compareTo(b.hopCount);
    });
  }

  /// Sort-time cost including the DV-3 unconfirmed-direct bias.
  /// The persisted `Route.cost` is NOT modified — Bellman-Ford propagation
  /// uses the raw cost so neighbors see a consistent topology view.
  int _effectiveCost(Route r) {
    if (r.isDirect && !r.ackConfirmed) {
      final biased = r.cost + unconfirmedDirectBias;
      return biased > Route.infinity ? Route.infinity : biased;
    }
    return r.cost;
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
