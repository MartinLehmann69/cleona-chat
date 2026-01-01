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

  // Monotonic counter bumped on every route change. Used by catch-up logic
  // to skip full-table sends when nothing changed since the last send.
  int routeEpoch = 0;

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

  // S-3: minimum cost of a single link (LAN same-subnet). Used as the lower
  // sanity bound on advertised route cost — a path of h hops cannot cost less
  // than h * minLinkCost.
  static const int minLinkCost = 1;

  // Callback: fired when a route changes (for propagation)
  void Function(String destHex, int cost)? onRouteChanged;

  // Advertisement filter: returns false for direct routes that should NOT be
  // advertised (e.g. stale — no inbound for >10min). Prevents propagating
  // routes to peers that switched networks without triggering Poison-Churn.
  bool Function(String destHex)? isDirectRouteAdvertisable;

  // D3 Phase 2: callback to query admission-PoW status of a neighbor.
  // Injected by CleonaNode after construction.
  bool Function(String nodeIdHex)? isAdmitted;

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
        if (r.isDirect) {
          existingDirect = r;
          break;
        }
      }
    }

    if (existingDirect != null) {
      // Any existing direct route (alive, stale, or dead) means we already
      // know this neighbor. Cost changes (LAN↔Public) or stale→alive
      // transitions update in-place, NOT new-neighbor events.
      // Without this, peers with multiple addresses trigger 820+ false
      // new-neighbor detections → Welcome-Push storm (107KB each) →
      // TLS timeouts → event-loop starvation → cascade failure.
      if (existingDirect.isAlive && existingDirect.cost <= cost) {
        return false;
      }
      // Revive dead/stale route or update cost — replace in routing table
      // but return false (not a new neighbor).
      final route = Route(
        destination: Uint8List.fromList(nodeId),
        nextHop: null,
        hopCount: 1,
        cost: cost,
        type: RouteType.direct,
        connType: connType,
      );
      _addOrUpdateRoute(hex, route);
      routeEpoch++;
      onRouteChanged?.call(hex, cost);
      updateDefaultGateway();
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
    routeEpoch++;
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

    if (toNotify.isNotEmpty) routeEpoch++;

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

      // S-3 cost sanity: reject impossible advertised costs (under-bidding).
      // cost is cumulative and every link costs >= minLinkCost, so a path of
      // h hops cannot cost less than h. Drops gross under-bids; a plausible
      // cost==hopCount claim still passes (see §4.4 threat model).
      if (entry.cost <= 0 || entry.cost < entry.hopCount * minLinkCost) {
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

    // V3.1.111: revalidation (un-staling) is NOT a topology change.
    // The stale penalty is a local selection bias — neighbors never saw
    // the inflated cost, so removing it restores the cost they already
    // know. No epoch bump, no update propagation needed.
    revalidateRoutesVia(fromHex);
    final updatedDests = <String>{};

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

      // S-3 cost sanity (see processRouteUpdate): drop impossible under-bids.
      if (entry.cost <= 0 || entry.cost < entry.hopCount * minLinkCost) {
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
    if (destList.isNotEmpty) routeEpoch++;
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
        // Bug 1 fix: suppress advertisement of stale direct routes
        if (best.isDirect && isDirectRouteAdvertisable != null &&
            !isDirectRouteAdvertisable!(destHex)) {
          return;
        }
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

  /// V3.1.111: Delta update — only the specified destinations (with Split Horizon).
  /// Used by _flushDvUpdates to send only changed routes instead of the full table.
  List<RouteEntry> buildDeltaFor(String neighborHex, Set<String> changedDests) {
    final result = <RouteEntry>[];
    final now = DateTime.now();

    for (final destHex in changedDests) {
      final routes = _routes[destHex];
      if (routes == null || routes.isEmpty) {
        // Destination was removed — send Poison Reverse so neighbor drops it
        result.add(RouteEntry(
          destinationHex: destHex,
          hopCount: 1,
          cost: Route.infinity,
          connType: ConnectionType.publicUdp,
        ));
        continue;
      }

      final best = routes.first;

      // Split Horizon
      if (best.nextHopHex == neighborHex) continue;

      if (best.isAlive) {
        // Bug 1 fix: suppress advertisement of stale direct routes
        if (best.isDirect && isDirectRouteAdvertisable != null &&
            !isDirectRouteAdvertisable!(destHex)) {
          continue;
        }
        result.add(RouteEntry(
          destinationHex: destHex,
          hopCount: best.hopCount,
          cost: best.cost,
          connType: best.connType,
        ));
      } else if (now.difference(best.lastConfirmed).inMinutes <= 5) {
        result.add(RouteEntry(
          destinationHex: destHex,
          hopCount: best.hopCount,
          cost: Route.infinity,
          connType: best.connType,
        ));
      }
    }

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
        // Bug 1 fix: suppress advertisement of stale direct routes
        if (best.isDirect && isDirectRouteAdvertisable != null &&
            !isDirectRouteAdvertisable!(destHex)) {
          return;
        }
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

    routeEpoch++;
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
  ///
  /// S-3: when [viaNextHopHex] is given (an E2E receipt that returned over a
  /// relay path), confirm the **specific** relay route we sent through —
  /// binding the route's preference to demonstrated delivery, not to the
  /// advertisement. Falls back to the direct/primary route when null.
  void confirmRoute(String destHex, {String? viaNextHopHex}) {
    final routes = _routes[destHex];
    if (routes == null || routes.isEmpty) return;
    final Route target;
    if (viaNextHopHex != null) {
      target = routes.firstWhere(
        (r) => r.nextHopHex == viaNextHopHex,
        orElse: () => routes.firstWhere(
          (r) => r.isDirect,
          orElse: () => routes.first,
        ),
      );
    } else {
      target = routes.firstWhere(
        (r) => r.isDirect,
        orElse: () => routes.first,
      );
    }
    target.consecutiveFailures = 0;
    target.lastConfirmed = DateTime.now();
    target.ackConfirmed = true;
    // ackConfirmed flip lifts the bias → re-sort so the proven route takes
    // its rightful primary slot.
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

  /// Add a low-priority relay route hint learned from an incoming relayed
  /// packet (Reverse-Relay-Path-Learning, §5.3). When we receive a packet
  /// from sender S relayed through neighbor R, we record "S is reachable
  /// via R" so the reply cascade can use R as relay for S.
  /// Does NOT override existing alive confirmed routes.
  bool addRelayRouteHint(String destHex, String relayHex, int cost) {
    if (destHex == _ownHex || destHex == relayHex) return false;
    if (!_neighbors.containsKey(relayHex)) return false;

    final existing = _routes[destHex];
    if (existing != null) {
      for (final r in existing) {
        if (r.nextHopHex == relayHex && r.isAlive) {
          r.lastConfirmed = DateTime.now();
          if (r.consecutiveFailures > 0) r.consecutiveFailures = 0;
          return false;
        }
      }
    }

    final route = Route(
      destination: hexToBytes(destHex),
      nextHop: hexToBytes(relayHex),
      hopCount: 2,
      cost: cost,
      type: RouteType.relay,
      connType: ConnectionType.relay,
    );
    _addOrUpdateRoute(destHex, route);
    return true;
  }

  /// All routes to a destination, sorted by cost.
  List<Route> routesTo(String destHex) {
    return List.unmodifiable(_routes[destHex] ?? []);
  }

  /// Whether at least one alive route to the destination exists.
  bool hasAliveRouteTo(String destHex) => bestRouteTo(destHex) != null;

  /// Like [hasAliveRouteTo] but also requires [lastConfirmed] within [maxAge].
  /// Relay-route-hints that were never used for actual traffic stay alive
  /// indefinitely (consecutiveFailures never increments) — this variant
  /// prevents them from inflating reachability counts.
  bool hasRecentAliveRouteTo(String destHex,
      {Duration maxAge = const Duration(minutes: 10)}) {
    final routes = _routes[destHex];
    if (routes == null) return false;
    final cutoff = DateTime.now().subtract(maxAge);
    for (final r in routes) {
      if (r.isAlive && r.lastConfirmed.isAfter(cutoff)) return true;
    }
    return false;
  }

  /// Remove relay-type routes whose [lastConfirmed] is older than [maxAge]
  /// and that were never ACK-confirmed. These are speculative hints from
  /// [addRelayRouteHint] that accumulated without ever carrying traffic.
  int pruneStaleRelayHints(Duration maxAge, {DateTime? now}) {
    final tNow = now ?? DateTime.now();
    var removed = 0;
    final emptiedDests = <String>[];
    _routes.forEach((destHex, routes) {
      final before = routes.length;
      routes.removeWhere((r) =>
          r.type == RouteType.relay &&
          !r.ackConfirmed &&
          tNow.difference(r.lastConfirmed) > maxAge);
      removed += before - routes.length;
      if (routes.isEmpty) emptiedDests.add(destHex);
    });
    for (final destHex in emptiedDests) {
      _routes.remove(destHex);
      onRouteChanged?.call(destHex, Route.infinity);
    }
    if (removed > 0) routeEpoch++;
    return removed;
  }

  /// All known destinations.
  Set<String> get allDestinations => _routes.keys.toSet();

  // ── Default-Gateway ───────────────────────────────────────────────────

  /// Selects the best default gateway (§4.4).
  /// Scoring: relay-confirmed → unique coverage → route count → avg cost → recency.
  /// "Unique coverage" counts destinations reachable ONLY through this neighbor —
  /// a neighbor that is the sole path to N destinations gets a bonus that outweighs
  /// raw route count. This prevents a high-route-count LAN peer from shadowing
  /// a Bootstrap that is the only relay to mobile/CGNAT devices.
  void updateDefaultGateway() {
    if (_neighbors.isEmpty) {
      _defaultGatewayHex = null;
      return;
    }

    // Pass 1: for each destination, collect which neighbors can reach it.
    final destToNeighbors = <String, List<String>>{};
    final neighborRouteCount = <String, int>{};
    final neighborTotalCost = <String, int>{};
    final neighborNewestConfirm = <String, DateTime>{};

    for (final neighborHex in _neighbors.keys) {
      neighborRouteCount[neighborHex] = 0;
      neighborTotalCost[neighborHex] = 0;
    }

    _routes.forEach((destHex, routes) {
      for (final r in routes) {
        if (!r.isAlive) continue;
        final via = r.isDirect ? r.destinationHex : r.nextHopHex;
        if (via == null || !_neighbors.containsKey(via)) continue;
        destToNeighbors.putIfAbsent(destHex, () => []);
        if (!destToNeighbors[destHex]!.contains(via)) {
          destToNeighbors[destHex]!.add(via);
        }
        neighborRouteCount[via] = (neighborRouteCount[via] ?? 0) + 1;
        neighborTotalCost[via] = (neighborTotalCost[via] ?? 0) + r.cost;
        final nc = neighborNewestConfirm[via];
        if (nc == null || r.lastConfirmed.isAfter(nc)) {
          neighborNewestConfirm[via] = r.lastConfirmed;
        }
        break; // best route per destination per neighbor
      }
    });

    // Pass 2: count unique destinations per neighbor (reachable ONLY via this one).
    final uniqueCoverage = <String, int>{};
    for (final neighborHex in _neighbors.keys) {
      uniqueCoverage[neighborHex] = 0;
    }
    for (final entry in destToNeighbors.entries) {
      if (entry.value.length == 1) {
        uniqueCoverage[entry.value.first] =
            (uniqueCoverage[entry.value.first] ?? 0) + 1;
      }
    }

    final scores = <String, _GatewayScore>{};
    for (final neighborHex in _neighbors.keys) {
      final rc = neighborRouteCount[neighborHex] ?? 0;
      scores[neighborHex] = _GatewayScore(
        routeCount: rc,
        uniqueCoverage: uniqueCoverage[neighborHex] ?? 0,
        avgCost: rc > 0 ? (neighborTotalCost[neighborHex] ?? 0) / rc : 999999,
        newestConfirm: neighborNewestConfirm[neighborHex] ?? DateTime(2000),
        relayConfirmed: _relayConfirmedNeighbors.contains(neighborHex),
        admitted: isAdmitted?.call(neighborHex) ?? false,
      );
    }

    // Sort: admitted → relay-confirmed → unique coverage → route count → cost → recency
    final sorted = scores.entries.toList()
      ..sort((a, b) {
        if (a.value.admitted != b.value.admitted) {
          return a.value.admitted ? -1 : 1;
        }
        if (a.value.relayConfirmed != b.value.relayConfirmed) {
          return a.value.relayConfirmed ? -1 : 1;
        }
        final ucCmp = b.value.uniqueCoverage.compareTo(a.value.uniqueCoverage);
        if (ucCmp != 0) return ucCmp;
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
    if (removed > 0) {
      routeEpoch++;
      updateDefaultGateway();
    }
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
      // S-3: proven beats unproven for ALL route classes. A route whose
      // end-to-end DELIVERY_RECEIPT has returned (ackConfirmed) outranks any
      // merely-advertised route, regardless of advertised cost — a blackhole
      // or under-bidder never earns the receipt, so it stays demoted. This is
      // a lexicographic partition, NOT an additive bias: within the same
      // confirmation class the existing DV-3 effective cost (incl. the
      // unconfirmed-direct bias) and hopCount decide, so the direct-vs-relay
      // balance for unproven routes is unchanged.
      final ca = a.ackConfirmed ? 0 : 1;
      final cb = b.ackConfirmed ? 0 : 1;
      if (ca != cb) return ca - cb;
      final c = _effectiveCost(a).compareTo(_effectiveCost(b));
      if (c != 0) return c;
      // Tiebreaker: fewer hops wins. Direct routes (hopCount=1) thus beat
      // relay routes (hopCount>=2) at equal effective cost.
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
  final int uniqueCoverage;
  final double avgCost;
  final DateTime newestConfirm;
  final bool relayConfirmed;
  final bool admitted;

  _GatewayScore({
    required this.routeCount,
    required this.uniqueCoverage,
    required this.avgCost,
    required this.newestConfirm,
    required this.relayConfirmed,
    required this.admitted,
  });
}
