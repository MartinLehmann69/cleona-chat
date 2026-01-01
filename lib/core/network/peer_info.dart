import 'dart:io' show InternetAddress;
import 'dart:math' show exp;
import 'dart:typed_data';
import 'package:fixnum/fixnum.dart';
import 'package:cleona/core/network/multi_interface.dart' show LocalInterface;
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;
import 'package:cleona/core/crypto/sodium_ffi.dart';

/// Long-term address stability classification for cold-start prioritisation.
enum StabilityTier { anchor, stable, normal, volatile_ }

class PeerAddress {
  String ip;
  int port;
  PeerAddressType type;
  double score;
  DateTime? lastSuccess;
  DateTime? lastAttempt;
  int successCount;
  int failCount;
  /// Consecutive failures since last success (for exponential backoff).
  int consecutiveFailures;

  /// 23.2 Multi-Interface Send: which local interface was used to reach
  /// this address. Null = unknown / single-socket mode (default).
  /// Set when a packet is successfully delivered via a specific interface;
  /// used by per-interface ACK tracking to attribute delivery success.
  LocalInterface? localInterface;

  /// Set when an inbound packet is received FROM this ip:port. Proves
  /// bidirectional reachability — the NAT mapping is live in both directions.
  /// Distinct from [lastSuccess] which is also set by outbound UDP send
  /// (OS-level accept, not delivery proof). Used by [allConnectionTargets]
  /// to prefer addresses confirmed by received traffic over STUN-discovered
  /// addresses that may map to a different CGNAT port (symmetric NAT).
  DateTime? lastReceivedAt;

  /// First successful contact under this exact ip:port. Set once by
  /// [recordSuccess] and never overwritten — survives daemon restarts via
  /// JSON persistence. Drives the [StabilityTier] classification.
  DateTime? stableSince;

  PeerAddress({
    required this.ip,
    required this.port,
    this.type = PeerAddressType.ipv4Public,
    this.score = 0.5,
    this.lastSuccess,
    this.lastAttempt,
    this.successCount = 0,
    this.failCount = 0,
    this.consecutiveFailures = 0,
    this.lastReceivedAt,
    this.stableSince,
    this.localInterface,
  });

  /// Base delay for exponential backoff (doubles each failure).
  /// Architecture §4.6: "5s → 30s → 5min" progression.
  static const _baseBackoffMs = 5000; // 5s (spec first tier)
  static const _maxBackoffMs = 300000; // 5 min cap (spec third tier)

  /// Grace period after network change: recordFailure() is a no-op until
  /// this timestamp, giving the socket time to stabilize on the new
  /// interface (WiFi→Mobilfunk transition).
  static DateTime? networkChangeGraceUntil;

  void recordSuccess() {
    successCount++;
    consecutiveFailures = 0;
    lastSuccess = DateTime.now();
    lastAttempt = lastSuccess;
    stableSince ??= lastSuccess;
    score = successCount / (successCount + failCount);
  }

  /// Record that an inbound packet was received FROM this address.
  /// Stronger signal than [recordSuccess] (which also fires on outbound
  /// OS-level send accept). Proves the NAT mapping is live bidirectionally.
  void recordReceived() {
    lastReceivedAt = DateTime.now();
    recordSuccess();
  }

  void recordFailure() {
    final grace = networkChangeGraceUntil;
    if (grace != null && DateTime.now().isBefore(grace)) return;
    failCount++;
    consecutiveFailures++;
    lastAttempt = DateTime.now();
    score = successCount / (successCount + failCount);
  }

  /// Whether this address should be skipped due to backoff.
  bool get isInBackoff {
    if (consecutiveFailures < 1) return false;
    final last = lastAttempt;
    if (last == null) return false;
    final elapsed = DateTime.now().difference(last).inMilliseconds;
    return elapsed < currentBackoffMs;
  }

  /// Current backoff delay in ms (exponential: 5s, 10s, 20s, 40s, 80s, 160s, 300s cap).
  /// Architecture §4.6: "on failure, exponential backoff (5s → 30s → 5min)."
  int get currentBackoffMs {
    if (consecutiveFailures < 1) return 0;
    final delay = _baseBackoffMs * (1 << (consecutiveFailures - 1).clamp(0, 6));
    return delay.clamp(0, _maxBackoffMs);
  }

  proto.PeerAddressProto toProto() {
    // Bug 4: success_count/fail_count/score/last_success/last_attempt are
    // strictly LOCAL epistemics — they describe what THIS node has
    // observed about address X working. They have no meaning for any
    // other node, whose network position, NAT context, and IPv6
    // reachability differ. Sharing them via PEER_LIST_PUSH gossip lets
    // a peer with polluted counters (e.g. an old build that bumped
    // recordSuccess() on every kernel-accept) overwrite the receiver's
    // legitimate local observations on KBucket.addPeer merge. The proto
    // fields stay on the wire for backwards compatibility but are
    // explicitly zeroed; receivers ignore them — see fromProto.
    return proto.PeerAddressProto()
      ..ip = ip
      ..port = port
      ..addressType = typeToProto(type);
  }

  static PeerAddress? fromProto(proto.PeerAddressProto p) {
    final ip = p.ip.trim();
    if (ip.isEmpty || ip == '0.0.0.0' || ip == '::' || p.port <= 0) return null;
    // Migration on load: older peers (and even older code in this peer)
    // sent every IPv6 address as IPV6_GLOBAL. Re-classify against actual
    // textual prefix so that ULA/LinkLocal/SiteLocal records that were
    // mislabelled on the wire get healed transparently.
    var type = _typeFromProto(p.addressType);
    final classified = classifyIp(ip);
    if (type == PeerAddressType.ipv6Global &&
        classified != PeerAddressType.ipv6Global) {
      type = classified;
    }
    // Bug 4: never trust the wire's success/fail/score numbers. They
    // are local-only facts that the sending peer has no authority to
    // claim about us. New address entry → counters start at zero;
    // KBucket.addPeer preserves existing local counters when the same
    // ip:port is re-advertised so merges don't blow away local state.
    return PeerAddress(
      ip: ip,
      port: p.port,
      type: type,
    );
  }

  static proto.AddressType typeToProto(PeerAddressType t) {
    switch (t) {
      case PeerAddressType.ipv4Public:
        return proto.AddressType.IPV4_PUBLIC;
      case PeerAddressType.ipv4Private:
        return proto.AddressType.IPV4_PRIVATE;
      case PeerAddressType.ipv6Global:
        return proto.AddressType.IPV6_GLOBAL;
      case PeerAddressType.ipv6Ula:
        return proto.AddressType.IPV6_ULA;
      case PeerAddressType.ipv6LinkLocal:
        return proto.AddressType.IPV6_LINK_LOCAL;
      case PeerAddressType.ipv6SiteLocal:
        return proto.AddressType.IPV6_SITE_LOCAL;
    }
  }

  static PeerAddressType _typeFromProto(proto.AddressType t) {
    switch (t) {
      case proto.AddressType.IPV4_PUBLIC:
        return PeerAddressType.ipv4Public;
      case proto.AddressType.IPV4_PRIVATE:
        return PeerAddressType.ipv4Private;
      case proto.AddressType.IPV6_GLOBAL:
        return PeerAddressType.ipv6Global;
      case proto.AddressType.IPV6_ULA:
        return PeerAddressType.ipv6Ula;
      case proto.AddressType.IPV6_LINK_LOCAL:
        return PeerAddressType.ipv6LinkLocal;
      case proto.AddressType.IPV6_SITE_LOCAL:
        return PeerAddressType.ipv6SiteLocal;
      default:
        return PeerAddressType.ipv4Public;
    }
  }

  /// Single source of truth for IP → PeerAddressType classification.
  ///
  /// IPv4: public vs private (RFC 1918 / loopback / CGNAT).
  /// IPv6 textual prefixes:
  ///   ::1                                 → ipv6LinkLocal (loopback, never published)
  ///   fe80::/10  (fe80..febf)             → ipv6LinkLocal
  ///   fc00::/7   (fc..  / fd..)           → ipv6Ula      (RFC 4193 unique-local)
  ///   fec0::/10  (fec0..feff)             → ipv6SiteLocal (RFC 3879 deprecated)
  ///   ff00::/8   (ff..)                   → ipv6LinkLocal sentinel (multicast — never publish)
  ///   else                                → ipv6Global
  ///
  /// Used by both Liveness-Builder (filter ULA/LL/SL out) and `fromProto`
  /// migration (heal mislabelled IPV6_GLOBAL records).
  static PeerAddressType classifyIp(String ip) {
    final s = ip.trim();
    if (s.isEmpty) return PeerAddressType.ipv4Public;
    if (!s.contains(':')) {
      // IPv4
      return _isPrivateIp(s) ? PeerAddressType.ipv4Private : PeerAddressType.ipv4Public;
    }
    // IPv6 — strip zone suffix (fe80::1%eth0) and brackets if any.
    var v6 = s;
    if (v6.startsWith('[')) {
      final close = v6.indexOf(']');
      if (close > 0) v6 = v6.substring(1, close);
    }
    final pct = v6.indexOf('%');
    if (pct >= 0) v6 = v6.substring(0, pct);
    final lower = v6.toLowerCase();
    if (lower == '::1') return PeerAddressType.ipv6LinkLocal;
    if (lower.startsWith('fe80')) return PeerAddressType.ipv6LinkLocal;
    // fc00::/7 → first byte 0xfc or 0xfd → "fc" or "fd" prefix.
    if (lower.startsWith('fc') || lower.startsWith('fd')) {
      return PeerAddressType.ipv6Ula;
    }
    // fec0::/10 deprecated site-local. fec0..feff (excluding fe80..febf which
    // is link-local handled above).
    if (lower.startsWith('fec') || lower.startsWith('fed') ||
        lower.startsWith('fee') || lower.startsWith('fef')) {
      return PeerAddressType.ipv6SiteLocal;
    }
    // ff00::/8 multicast — caller should never publish; we mark it as
    // link-local sentinel so reachability filters drop it.
    if (lower.startsWith('ff')) return PeerAddressType.ipv6LinkLocal;
    return PeerAddressType.ipv6Global;
  }

  /// Current local IPs — set by CleonaNode on start and network change.
  /// Used for address priority calculation (same subnet = highest priority).
  static List<String> currentLocalIps = [];

  // ── Score-Decay (Bug B) ────────────────────────────────────────────
  // Raw `score` = succ / (succ+fail) is sticky for life: an address with
  // 4 successes from two weeks ago stays at 1.0 forever and dominates the
  // route-selection sort. Effective score applies an exponential decay
  // anchored on the last confirmed activity timestamp.
  //
  //   effectiveScore = score * exp(-(ageHours / halfLifeHours) * ln2)
  //
  //   halfLife = 24h when we've ever seen a `lastSuccess`
  //            =  6h when we've only attempted (no success ever)
  //            = no decay if both timestamps are null (cold record)
  static const double _ln2 = 0.693147180559945;

  /// Time-decayed score for sorting / route selection.
  /// Falls back to raw `score` when no activity timestamp is available.
  double get effectiveScore {
    final anchor = lastSuccess ?? lastAttempt;
    if (anchor == null) return score;
    final halfLifeHours = (lastSuccess != null) ? 24.0 : 6.0;
    final ageHours =
        DateTime.now().difference(anchor).inMilliseconds / 3600000.0;
    if (ageHours <= 0) return score;
    final decay = exp(-(ageHours / halfLifeHours) * _ln2);
    return score * decay;
  }

  /// Address priority (IPv6-First, §4.6):
  ///   1 = same-subnet IPv4 / link-local IPv6 (LAN direct)
  ///   2 = global IPv6 (no NAT, end-to-end routable)
  ///   3 = public IPv4 / ULA IPv6 / other-private IPv4
  ///   4 = CGNAT/DS-Lite IPv4
  int get priority {
    // IPv6
    if (ip.contains(':')) {
      if (ip.toLowerCase().startsWith('fe80:')) return 1; // Link-local = LAN
      final t = classifyIp(ip);
      if (t == PeerAddressType.ipv6Ula || t == PeerAddressType.ipv6SiteLocal) {
        return 3; // ULA/site-local = other-subnet private
      }
      return 2; // Global IPv6 — no NAT, end-to-end routable
    }
    // IPv4
    if (_isCgnat(ip)) return 4;
    if (!_isPrivateIp(ip)) return 3;
    for (final localIp in currentLocalIps) {
      if (_sameSubnet(ip, localIp)) return 1;
    }
    return 3; // Other private subnet
  }

  /// Check if IP is in CGNAT range (100.64.0.0/10) or carrier NAT (192.0.0.0/24).
  static bool _isCgnat(String ip) {
    if (ip.startsWith('100.')) {
      final parts = ip.split('.');
      if (parts.length >= 2) {
        final second = int.tryParse(parts[1]) ?? 0;
        return second >= 64 && second <= 127;
      }
    }
    return ip.startsWith('192.0.0.');
  }

  /// WIN-4: Public alias for `_isCgnat`. Used by `RoutingTable.auditAddresses`
  /// to prune carrier-NAT IPs from the persistent cache at startup. Carrier
  /// NAT addresses (100.64.0.0/10 RFC 6598, plus the legacy 192.0.0.0/24
  /// well-known prefix) are NEVER routable from outside the carrier and
  /// belong only to the carrier-side temporary client side of mobile DS-Lite.
  static bool isCarrierNAT(String ip) => _isCgnat(ip);

  /// WIN-4: Whether `ip` is in a /24 of any of `localIps` (IPv4 only).
  /// Used by audit-pass to decide whether a private address is reachable
  /// from the current host. Returns true for IPs that DO share a /24 with
  /// at least one local interface; false for unreachable private IPs (e.g.
  /// 10.0.2.x emulator-NAT addresses on a 192.168.10.x host).
  static bool isInLocalSubnet(String ip, Iterable<String> localIps) {
    if (ip.contains(':')) return false; // IPv6 handled separately
    for (final localIp in localIps) {
      if (_sameSubnet(ip, localIp)) return true;
    }
    return false;
  }

  /// Check if two IPs are in the same /24 subnet (IPv4 only).
  static bool _sameSubnet(String ip1, String ip2) {
    if (ip1.contains(':') || ip2.contains(':')) return false; // IPv6: no /24 concept
    final p1 = ip1.split('.');
    final p2 = ip2.split('.');
    if (p1.length != 4 || p2.length != 4) return false;
    return p1[0] == p2[0] && p1[1] == p2[1] && p1[2] == p2[2];
  }

  /// Whether this address is reachable from the device's current network.
  /// IPv4: private IPs reachable iff we also have a private IP (cross-class OK
  /// since 6acbdef Bug C — different RFC1918 classes within one routed network
  /// are common). CGNAT IPs (100.64.x.x) are treated like public.
  /// IPv6 (Bug A/C):
  ///   - IPV6_GLOBAL:     reachable iff we have a global IPv6 ourselves
  ///   - IPV6_ULA:        reachable iff we have any ULA ourselves
  ///   - IPV6_SITE_LOCAL: same as ULA (deprecated but treat conservatively)
  ///   - IPV6_LINK_LOCAL: never reachable across DHT routing (return false).
  ///                     Includes the multicast sentinel (`ff..`).
  bool get isReachableFromCurrentNetwork {
    // IPv6 dispatch first — IPv4 helpers below assume dot-notation.
    if (ip.contains(':')) {
      if (ip == '::1') return true; // loopback to self always reachable
      switch (type) {
        case PeerAddressType.ipv6Global:
          return _hasGlobalIpv6();
        case PeerAddressType.ipv6Ula:
        case PeerAddressType.ipv6SiteLocal:
          return _hasAnyUlaAddress();
        case PeerAddressType.ipv6LinkLocal:
          return false;
        default:
          // IPv4 enum value but colon in IP string — defensive: classify on
          // the fly and recurse. Avoid infinite loop by inlining the result.
          final t = classifyIp(ip);
          if (t == PeerAddressType.ipv6LinkLocal) return false;
          if (t == PeerAddressType.ipv6Global) return _hasGlobalIpv6();
          if (t == PeerAddressType.ipv6Ula || t == PeerAddressType.ipv6SiteLocal) {
            return _hasAnyUlaAddress();
          }
          return false;
      }
    }
    // IPv4 path
    if (!_isPrivateIp(ip)) return true;
    // Loopback is always reachable from the same machine
    if (ip.startsWith('127.')) return true;
    // Target is private — are WE also on a private network?
    // §4.7: CGNAT (100.64/10) has zero routing relationship to RFC 1918.
    // A CGNAT local must NOT try to reach 192.168.x targets and vice versa.
    // Cross-class RFC 1918 routing (e.g. 192.168.x ↔ 10.x behind the same
    // gateway) is common in home/lab networks and remains permitted.
    final targetIsCgnat = _isCgnat(ip);
    for (final localIp in currentLocalIps) {
      if (!_isPrivateIp(localIp)) continue;
      final localIsCgnat = _isCgnat(localIp);
      // Both CGNAT or both RFC 1918: potentially same network
      if (localIsCgnat == targetIsCgnat) return true;
    }
    return false;
  }

  /// Do we currently have any global-scope IPv6 address bound locally?
  /// Conservative — only `ipv6Global` per `classifyIp` counts.
  static bool _hasGlobalIpv6() {
    for (final ip in currentLocalIps) {
      if (!ip.contains(':')) continue;
      if (classifyIp(ip) == PeerAddressType.ipv6Global) return true;
    }
    return false;
  }

  /// Do we have any ULA (or site-local) IPv6 address bound locally?
  /// Used to decide whether a peer's ULA is potentially reachable. Conservative:
  /// "any ULA" rather than "ULA in the same /48 prefix" — good enough for now,
  /// avoids dropping records on home networks where the prefix is stable.
  static bool _hasAnyUlaAddress() {
    for (final ip in currentLocalIps) {
      if (!ip.contains(':')) continue;
      final t = classifyIp(ip);
      if (t == PeerAddressType.ipv6Ula || t == PeerAddressType.ipv6SiteLocal) {
        return true;
      }
    }
    return false;
  }

  /// Public access to private-IP check (needed by cleona_node for relay logic).
  static bool isPrivateIp(String ip) => _isPrivateIp(ip);

  /// §4.7 Public accessor: true iff the local device currently has at least
  /// one globally-routable IPv6 address bound. Used by [CleonaNode] to detect
  /// the IPv4-only-sender cross-family relay scenario.
  static bool hasGlobalIpv6() => _hasGlobalIpv6();

  /// True if the two IPs belong to the same RFC1918 class
  /// (10/8, 172.16-31/12, or 192.168/16). Returns false for IPv6 or
  /// non-private inputs. Used by NAT-egress detection: an observed-IP
  /// that's private AND in the same class as ours is most likely an echo
  /// of our own LAN address, not a legit cross-NAT egress.
  static bool samePrivateClass(String ip1, String ip2) {
    if (ip1.contains(':') || ip2.contains(':')) return false;
    if (ip1.startsWith('10.') && ip2.startsWith('10.')) return true;
    if (ip1.startsWith('192.168.') && ip2.startsWith('192.168.')) return true;
    final p1 = ip1.split('.');
    final p2 = ip2.split('.');
    if (p1.length >= 2 && p2.length >= 2 && p1[0] == '172' && p2[0] == '172') {
      final s1 = int.tryParse(p1[1]) ?? 0;
      final s2 = int.tryParse(p2[1]) ?? 0;
      if (s1 >= 16 && s1 <= 31 && s2 >= 16 && s2 <= 31) return true;
    }
    return false;
  }

  @override
  String toString() => '$ip:$port (${type.name}, pri=$priority, score=${score.toStringAsFixed(2)})';
}

enum PeerAddressType {
  ipv4Public,
  ipv4Private,
  ipv6Global,
  ipv6Ula,
  ipv6LinkLocal,
  ipv6SiteLocal,
}

/// Capability bitmask flags for PeerInfo.capabilities (§27 IPv6 Transport).
class PeerCapabilities {
  static const int ipv4 = 1 << 0;     // Supports IPv4 transport
  static const int ipv6 = 1 << 1;     // Supports IPv6 transport
  static const int dualStack = ipv4 | ipv6; // Can bridge IPv4↔IPv6
}

// ── Distance-Vector Routing (V3) ──────────────────────────────────────

enum RouteType { direct, relay }

enum ConnectionType {
  lanSameSubnet,    // Cost 1
  lanOtherSubnet,   // Cost 2
  wifiDirect,       // Cost 3
  publicUdp,        // Cost 5
  holePunch,        // Cost 5
  relay,            // Cost 10
  mobile,           // Cost 20
  mobileRelay,      // Cost 30
}

int connectionTypeCost(ConnectionType ct) {
  switch (ct) {
    case ConnectionType.lanSameSubnet:  return 1;
    case ConnectionType.lanOtherSubnet: return 2;
    case ConnectionType.wifiDirect:     return 3;
    case ConnectionType.publicUdp:      return 5;
    case ConnectionType.holePunch:      return 5;
    case ConnectionType.relay:          return 10;
    case ConnectionType.mobile:         return 20;
    case ConnectionType.mobileRelay:    return 30;
  }
}

ConnectionType connectionTypeFromPriority(int priority) {
  switch (priority) {
    case 1:  return ConnectionType.lanSameSubnet;
    case 2:  return ConnectionType.lanOtherSubnet;
    case 3:  return ConnectionType.publicUdp;
    case 4:  return ConnectionType.mobile;
    default: return ConnectionType.publicUdp;
  }
}

class Route {
  final Uint8List destination;      // Ziel-NodeId (32 bytes)
  final Uint8List? nextHop;         // Naechster Sprung, null = direkt
  int hopCount;
  int cost;
  final RouteType type;
  DateTime lastConfirmed;
  final ConnectionType connType;
  int consecutiveFailures;

  /// True when delivery via this route has been confirmed by a DELIVERY_RECEIPT.
  /// OS-level UDP send success does NOT set this — only actual end-to-end ACK.
  /// Used by sendEnvelope cascade: if direct route is ackConfirmed, skip relay.
  bool ackConfirmed;

  /// True while this route is in the soft-reset "stale" window after a network
  /// change (Architektur §2.7.2 / §7.6). Stale routes still appear in lookups
  /// but at +5 cost, so freshly revalidated routes are preferred. Routes that
  /// fail to revalidate within the deadline are dropped by `pruneStaleRoutes`.
  bool isStale = false;

  /// When the route entered the `stale` state (null when not stale).
  DateTime? staleSince;

  /// Cost penalty applied to [cost] while the route is stale. Always 0 or
  /// [stalenessPenalty]; persisted so [revalidate] can restore the original
  /// cost without floating-point drift if multiple stale cycles occur.
  int _stalenessPenalty = 0;

  /// Soft-reset cost penalty for stale routes (Architektur §2.7.2).
  static const int stalenessPenalty = 5;

  static const int infinity = 65535;

  Route({
    required this.destination,
    this.nextHop,
    required this.hopCount,
    required this.cost,
    required this.type,
    DateTime? lastConfirmed,
    required this.connType,
    this.consecutiveFailures = 0,
    this.ackConfirmed = false,
  }) : lastConfirmed = lastConfirmed ?? DateTime.now();

  /// Mark this route as stale (idempotent). Adds [stalenessPenalty] to [cost]
  /// the first time it is called on a fresh route.
  void markStale({DateTime? now}) {
    if (isStale) return;
    isStale = true;
    staleSince = now ?? DateTime.now();
    cost = (cost + stalenessPenalty).clamp(0, infinity);
    _stalenessPenalty = stalenessPenalty;
  }

  /// Clear the stale flag and remove the cost penalty. Idempotent.
  void revalidate({DateTime? now}) {
    if (!isStale) return;
    isStale = false;
    staleSince = null;
    cost = (cost - _stalenessPenalty).clamp(0, infinity);
    _stalenessPenalty = 0;
    lastConfirmed = now ?? DateTime.now();
  }

  bool get isAlive => cost < infinity && consecutiveFailures < 3;
  bool get isDirect => nextHop == null;

  String get destinationHex => _bytesToHex(destination);
  String? get nextHopHex => nextHop != null ? _bytesToHex(nextHop!) : null;

  @override
  String toString() =>
      'Route(${destinationHex.substring(0, 8)}.. '
      'via ${nextHopHex?.substring(0, 8) ?? "direct"}, '
      'cost=$cost, hops=$hopCount, ${connType.name})';

  /// Serialize for `dv_routing.json` persistence (Architecture §2.7.3).
  /// `cost` is stored *without* the stale-penalty so a daemon restart does
  /// not pile penalty on penalty across multiple stale cycles. The `isStale`
  /// / `staleSince` / `_stalenessPenalty` fields are intentionally NOT
  /// persisted — `DvRoutingTable.loadFromJson` re-marks every loaded route
  /// stale via `markAllRoutesStale`, mirroring the soft-reset semantics in
  /// `cleona_node.dart:onNetworkChanged` (§2.7.2).
  Map<String, dynamic> toJson() => {
        'destination': _bytesToHex(destination),
        if (nextHop != null) 'nextHop': _bytesToHex(nextHop!),
        'hopCount': hopCount,
        'cost': (cost - _stalenessPenalty).clamp(0, infinity),
        'type': type.name,
        'lastConfirmed': lastConfirmed.millisecondsSinceEpoch,
        'connType': connType.name,
        'consecutiveFailures': consecutiveFailures,
        'ackConfirmed': ackConfirmed,
      };

  /// Reconstruct a Route from its persisted JSON form. Unknown enum values
  /// fall back to safe defaults (relay / publicUdp) rather than throwing —
  /// a corrupted persisted file should at worst yield slightly off cost
  /// estimates that the next live `processRouteUpdate` corrects, never a
  /// crash on daemon start.
  static Route fromJson(Map<String, dynamic> json) {
    return Route(
      destination: _hexToBytes(json['destination'] as String),
      nextHop: json['nextHop'] != null
          ? _hexToBytes(json['nextHop'] as String)
          : null,
      hopCount: json['hopCount'] as int,
      cost: json['cost'] as int,
      type: RouteType.values.firstWhere(
        (e) => e.name == (json['type'] as String? ?? 'relay'),
        orElse: () => RouteType.relay,
      ),
      lastConfirmed: DateTime.fromMillisecondsSinceEpoch(
          json['lastConfirmed'] as int? ?? 0),
      connType: ConnectionType.values.firstWhere(
        (e) => e.name == (json['connType'] as String? ?? 'publicUdp'),
        orElse: () => ConnectionType.publicUdp,
      ),
      consecutiveFailures: json['consecutiveFailures'] as int? ?? 0,
      ackConfirmed: json['ackConfirmed'] as bool? ?? false,
    );
  }
}

/// Provenance of a cached PubKey in `PeerInfo` — drives `verifyOuterEnvelope`
/// behavior on signature mismatch (Architecture §17.3).
///
/// - [none]: no PK cached.
/// - [thirdParty]: learned via foreign PEER_LIST_PUSH (a node telling us about
///   another node). Mismatch → clear + accept (lenient — tolerates pollution).
/// - [firstParty]: learned via authenticated direct exchange with the peer
///   itself (self-broadcast PEER_LIST_PUSH where pushed deviceNodeId matches
///   envelope.senderDeviceNodeId; CONTACT_REQUEST/RESPONSE; signed
///   KEY_ROTATION_BROADCAST). Mismatch → drop + preserve (presumed adversarial).
enum PkSource { none, thirdParty, firstParty }

/// Represents a known peer in the network.
/// After Phase 2 (§26 Multi-Device), nodeId = deviceNodeId (per-device routing).
/// userId = stable identity (same across all devices of one user).
class PeerInfo {
  Uint8List nodeId; // 32 bytes — deviceNodeId (per-device routing key)
  /// Stable user identity (same across all devices). Null for legacy peers.
  Uint8List? userId;
  String publicIp;
  int publicPort;
  String localIp;
  int localPort;
  List<PeerAddress> addresses;
  String networkChannel;
  DateTime lastSeen;
  NatClassification natType;
  int capabilities;
  /// **User-Sig** PK (Ed25519). Identity-wide — derived from the User's seed,
  /// identical across all of the User's devices. Used for: contact-resolution,
  /// mailbox-ID derivation (§3.2 `mailboxId = SHA-256("mailbox" || ed25519_pk)`),
  /// CR/CRR signature verification.
  ///
  /// **Not** used for outer NetworkPacketV3 device-sig verification — that
  /// reaches for [deviceEd25519PublicKey] (Welle 3, §17.3).
  Uint8List? ed25519PublicKey;

  /// **User-Sig** PK (ML-DSA-65) — PQ companion to [ed25519PublicKey].
  Uint8List? mlDsaPublicKey;

  Uint8List? x25519PublicKey;
  Uint8List? mlKemPublicKey;

  /// **Device-Sig** PK (Ed25519). Per-device, persisted server-side in
  /// `device_keys.json`. Distinct from [ed25519PublicKey] (User-Sig). The
  /// outer `NetworkPacketV3.device_sig` is signed with the Device-Sig
  /// keypair — `verifyOuterDeviceSig` MUST consult these fields, not the
  /// User-Sig PKs above. `null` means we have not yet learned this peer's
  /// Device-Sig PK from a self-broadcast / KEY_ROTATION; the receiver then
  /// falls back to the lenient-bootstrap path (§2.4.0).
  Uint8List? deviceEd25519PublicKey;

  /// **Device-Sig** PK (ML-DSA-65) — PQ companion to [deviceEd25519PublicKey].
  Uint8List? deviceMlDsaPublicKey;

  /// Provenance of the cached signing keys (Ed25519 + ML-DSA), used by
  /// `CleonaNode.verifyOuterEnvelope` to choose the mismatch policy.
  /// See `PkSource` for semantics; default `none`. The two PK types share a
  /// single source flag because both are populated from the same authenticated
  /// channels (CONTACT_REQUEST, self-broadcast PEER_LIST_PUSH, KEY_ROTATION).
  PkSource pkSource = PkSource.none;

  /// §5.10 Send-Cascade Recovery — Stale-PK flag (orthogonal to [pkSource]).
  ///
  /// Set when the cached signing PK is suspected stale (Stage 2: incoming
  /// `device_sig_invalid` from a peer with a firstParty PK we cached, treated
  /// as likely key rotation rather than malice; Stage 5: blanket mark on
  /// re-discovery so the next firstParty Self-Broadcast can refresh every
  /// peer's PK after a wider mesh-state loss).
  ///
  /// Contract (§5.10.5): while `pkStale == true` AND `pkSource ==
  /// PkSource.firstParty`, [setSigningKeys] allows an incoming firstParty PK
  /// to overwrite the cached one — bypassing the "firstParty cannot be
  /// overwritten" pollution-prevention rule. The overwrite clears `pkStale`.
  /// Receiver-side reputation hits for `device_sig_invalid` are suppressed
  /// while the flag is set (the cascade is owning the recovery).
  bool pkStale = false;
  Uint8List? ed25519Signature;
  Uint8List? mlDsaSignature;

  /// SHA-256 fingerprint over all 6 PK fields (ed25519 + ml_dsa + x25519 +
  /// ml_kem + device_ed25519 + device_ml_dsa). Carried in slim PEER_LIST_PUSH
  /// so the receiver can detect key changes without the full PQ keys.
  Uint8List? keyFingerprint;

  /// D3 Admission-PoW (§13.1.2): 8-byte nonce certifying
  /// [deviceEd25519PublicKey]. Travels in PEER_LIST_PUSH (also slim) and
  /// PEER_KEY_RESPONSE; persisted with the routing table.
  Uint8List? deviceIdPowNonce;

  /// D3: true once [deviceIdPowNonce] verified against the pubkey AND the
  /// deviceId binding (`SHA-256(secret || pk) == nodeId`, checked in
  /// cleona_node). Phase 1 observe-only — feeds network stats, gates nothing.
  bool idPowVerified = false;

  Uint8List? get computedKeyFingerprint {
    if (ed25519PublicKey == null) return null;
    final buf = <int>[
      ...ed25519PublicKey!,
      ...?mlDsaPublicKey,
      ...?x25519PublicKey,
      ...?mlKemPublicKey,
      ...?deviceEd25519PublicKey,
      ...?deviceMlDsaPublicKey,
    ];
    return SodiumFFI().sha256(Uint8List.fromList(buf));
  }

  /// Relay route: nodeId of the relay peer that can reach this peer.
  /// Transient — not persisted.
  Uint8List? relayViaNodeId;

  /// When was this relay route set (for logging/diagnostics).
  DateTime? relaySetAt;

  /// Consecutive ACK failures on DIRECT route to this peer.
  /// 3x timeout → directBlocked, but does NOT affect relay route validity.
  int consecutiveRouteFailures = 0;

  /// Consecutive ACK failures on the RELAY route specifically.
  /// Tracked separately from direct failures so that direct-send failures
  /// don't invalidate a working relay path (NAT peer bug fix).
  int consecutiveRelayFailures = 0;

  /// Whether a valid relay route exists.
  /// Uses its own failure counter — direct-send failures don't kill the relay.
  bool get hasValidRelayRoute =>
      relayViaNodeId != null &&
      consecutiveRelayFailures < 3;

  /// True while the learned relay route is in the soft-reset "stale" window
  /// (Architektur §2.7.2 / §7.6). The route is still consulted by the cascade,
  /// but `bestRouteTo` adds a cost penalty so a freshly revalidated direct
  /// route is preferred. Cleared on incoming PONG / DELIVERY_RECEIPT through
  /// the relay; pruned to `clearRelayRoute()` if not revalidated within the
  /// 30 s deadline by `pruneRelayIfStale`.
  bool relayStale = false;

  /// Timestamp when the relay route entered the `stale` state (null when not).
  DateTime? relayStaleSince;

  /// Mark the learned relay route as stale (idempotent, no-op if no relay).
  void markRelayStale({DateTime? now}) {
    if (relayViaNodeId == null) return;
    if (relayStale) return;
    relayStale = true;
    relayStaleSince = now ?? DateTime.now();
  }

  /// Clear the stale flag (called when a frame is delivered through the relay
  /// or the relay sends us a fresh DV-update). Idempotent.
  void confirmRelay({DateTime? now}) {
    if (!relayStale) return;
    relayStale = false;
    relayStaleSince = null;
    relaySetAt = now ?? DateTime.now();
  }

  /// Drop the relay route entirely if it has been stale for longer than
  /// [maxAge]. Returns true if the route was pruned.
  bool pruneRelayIfStale(Duration maxAge, {DateTime? now}) {
    if (!relayStale || relayStaleSince == null) return false;
    final tNow = now ?? DateTime.now();
    if (tNow.difference(relayStaleSince!) <= maxAge) return false;
    clearRelayRoute();
    relayStale = false;
    relayStaleSince = null;
    return true;
  }

  /// Clear the relay route (on network change, or relay peer gone).
  void clearRelayRoute() {
    relayViaNodeId = null;
    relaySetAt = null;
    consecutiveRelayFailures = 0;
    relayStale = false;
    relayStaleSince = null;
  }

  /// Per-relay-route cooldown (Task #30): relayHex → expiresAt.
  ///
  /// When a learned relay route accumulates 3 consecutive ACK timeouts, we
  /// stamp the relay's nodeId here. While the timestamp is in the future,
  /// re-learning of the SAME relay (via incoming RELAY_FORWARD or RELAY_ACK)
  /// is suppressed and Cascade Step 2a skips it.
  ///
  /// Why: asymmetric reachability is real on the internet. b4344987 may be
  /// able to deliver to us (incoming relay traffic arrives) while being
  /// unable to deliver from us to a third party (outgoing relay drops).
  /// Without this cooldown, peer.relayViaNodeId is overwritten every time
  /// a stale relay sends us a packet, re-arming the broken path.
  ///
  /// Transient — not persisted across daemon restarts (defensive: a fresh
  /// daemon should explore paths from scratch rather than honor a stale
  /// blacklist that may no longer apply).
  final Map<String, DateTime> _relayCooldownUntil = {};

  /// Default cooldown: long enough to survive several incoming relay packets
  /// (a peer's CHANNEL_INDEX_EXCHANGE arrives every 5-15min) but short enough
  /// that genuine path repair (NAT mapping refresh) recovers within minutes.
  static const Duration relayFailureCooldown = Duration(minutes: 5);

  /// Mark a relay route as recently failed. Suppresses re-learning of the
  /// same relay for the cooldown window.
  void markRelayFailed(String relayHex, {Duration? cooldown}) {
    _relayCooldownUntil[relayHex] =
        DateTime.now().add(cooldown ?? relayFailureCooldown);
  }

  /// Whether the given relay nodeId is currently in cooldown.
  bool isRelayInCooldown(String relayHex) {
    final until = _relayCooldownUntil[relayHex];
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _relayCooldownUntil.remove(relayHex);
      return false;
    }
    return true;
  }

  /// Protected seed peers survive maintenance pruning (§27 Doze resilience).
  /// Set when a peer is added from a QR/NFC/URI seed — ensures the phone can
  /// re-bootstrap after Android Doze instead of losing all peers.
  bool isProtectedSeed = false;

  /// How often this peer's public address set has changed (dynamic IP
  /// reconnects). Incremented by KBucket address-merge on firstParty
  /// updates when a public ip:port disappears and a new one appears.
  int addressChangeCount = 0;

  /// Longest [stableSince] across all current addresses.
  DateTime? get _oldestStableSince {
    DateTime? best;
    for (final a in addresses) {
      final ss = a.stableSince;
      if (ss != null && (best == null || ss.isBefore(best))) best = ss;
    }
    return best;
  }

  /// Cold-start stability classification based on long-term address
  /// persistence. Anchor peers are contacted first after prolonged offline.
  StabilityTier get stabilityTier {
    final oldest = _oldestStableSince;
    if (oldest == null) return StabilityTier.normal;
    final stableDays = DateTime.now().difference(oldest).inDays;
    if (stableDays >= 30 && addressChangeCount == 0) return StabilityTier.anchor;
    if (stableDays >= 7 && addressChangeCount <= 2) return StabilityTier.stable;
    if (addressChangeCount > 10) return StabilityTier.volatile_;
    return StabilityTier.normal;
  }

  PeerInfo({
    required this.nodeId,
    this.userId,
    this.publicIp = '',
    this.publicPort = 0,
    this.localIp = '',
    this.localPort = 0,
    List<PeerAddress>? addresses,
    this.networkChannel = 'beta',
    DateTime? lastSeen,
    this.natType = NatClassification.unknown,
    this.capabilities = 0,
    this.ed25519PublicKey,
    this.mlDsaPublicKey,
    this.x25519PublicKey,
    this.mlKemPublicKey,
    this.deviceEd25519PublicKey,
    this.deviceMlDsaPublicKey,
    this.ed25519Signature,
    this.mlDsaSignature,
    this.keyFingerprint,
    this.deviceIdPowNonce,
    this.pkSource = PkSource.none,
  })  : addresses = addresses ?? [],
        lastSeen = lastSeen ?? DateTime.now();

  /// Set or upgrade the cached signing PKs.
  ///
  /// Provenance precedence: a `firstParty` PK is **never** overwritten by a
  /// `thirdParty` claim — that closes the cache-pollution vector identified
  /// in V3.1.74 (Architecture §17.3 "Stale key handling"). Setting the same
  /// or higher provenance is allowed; the same provenance with new bytes
  /// overwrites (legitimate key rotation flows go through dedicated paths
  /// that pass `firstParty`).
  ///
  /// Returns `true` if the PK fields were updated, `false` if the call was
  /// suppressed by the precedence rule.
  bool setSigningKeys({
    Uint8List? ed25519,
    Uint8List? mlDsa,
    Uint8List? deviceEd25519,
    Uint8List? deviceMlDsa,
    required PkSource source,
  }) {
    if (source == PkSource.none) return false;
    if (pkSource == PkSource.firstParty && source == PkSource.thirdParty) {
      return false; // Don't downgrade.
    }
    if (ed25519 != null && ed25519.isNotEmpty) ed25519PublicKey = ed25519;
    if (mlDsa != null && mlDsa.isNotEmpty) mlDsaPublicKey = mlDsa;
    // Welle 3 (§17.3): Device-Sig PKs are populated from the same authenticated
    // channels (self-broadcast PEER_LIST_PUSH, KEY_ROTATION) and share the
    // provenance flag. The outer NetworkPacketV3 device_sig verifier reaches
    // for these explicitly — keeping them in sync with the User-Sig PKs is
    // mandatory or `verifyOuterDeviceSig` will silently fall through.
    if (deviceEd25519 != null && deviceEd25519.isNotEmpty) {
      deviceEd25519PublicKey = deviceEd25519;
    }
    if (deviceMlDsa != null && deviceMlDsa.isNotEmpty) {
      deviceMlDsaPublicKey = deviceMlDsa;
    }
    pkSource = source;
    // §5.10.5 — once a fresh firstParty PK has landed, the Stage-2/Stage-5
    // recovery is over for this peer. Clear the stale flag so subsequent
    // packets verify normally and the reputation-hit suppression in
    // `_onPacketV3Received` (§5.10.2) lifts.
    if (source == PkSource.firstParty) pkStale = false;
    return true;
  }

  /// Clear the cached signing PKs (e.g. on signature mismatch with
  /// `thirdParty` provenance — the lenient policy from §17.3).
  void clearSigningKeys() {
    ed25519PublicKey = null;
    mlDsaPublicKey = null;
    deviceEd25519PublicKey = null;
    deviceMlDsaPublicKey = null;
    pkSource = PkSource.none;
  }

  String get nodeIdHex => _bytesToHex(nodeId);

  /// Cached hex-encoded userId. Invalidates automatically when `userId` is
  /// reassigned to a different Uint8List (identity check — reassignment of
  /// the same reference keeps the cache). Read O(1) after first access.
  String? _userIdHexCache;
  Uint8List? _userIdHexCachedFor;
  String? get userIdHex {
    final u = userId;
    if (u == null) return null;
    if (identical(u, _userIdHexCachedFor)) return _userIdHexCache;
    _userIdHexCachedFor = u;
    return _userIdHexCache = _bytesToHex(u);
  }

  /// Remove addresses that haven't had a successful connection in [maxAge].
  /// Returns the number of removed addresses.
  int pruneStaleAddresses({Duration maxAge = const Duration(days: 14)}) {
    final cutoff = DateTime.now().subtract(maxAge);
    final before = addresses.length;
    addresses.removeWhere((addr) {
      final ls = addr.lastSuccess;
      // Never succeeded and older than maxAge based on lastAttempt
      if (ls == null) {
        final la = addr.lastAttempt;
        return la != null && la.isBefore(cutoff);
      }
      return ls.isBefore(cutoff);
    });
    return before - addresses.length;
  }

  /// Returns all connection targets, deduplicated, sorted by reliability score (best first).
  List<PeerAddress> allConnectionTargets() {
    final targets = <String, PeerAddress>{};

    // Add multi-address entries
    for (final addr in addresses) {
      final key = '${addr.ip}:${addr.port}';
      targets[key] = addr;
    }

    // Add legacy fields (guard against 0.0.0.0 — last defense if sanitization missed)
    if (publicIp.isNotEmpty && publicIp != '0.0.0.0' && publicPort > 0) {
      final key = '$publicIp:$publicPort';
      targets.putIfAbsent(key, () => PeerAddress(
        ip: publicIp,
        port: publicPort,
        type: _isPrivateIp(publicIp) ? PeerAddressType.ipv4Private : PeerAddressType.ipv4Public,
      ));
    }
    if (localIp.isNotEmpty && localIp != '0.0.0.0' && localPort > 0) {
      final key = '$localIp:$localPort';
      targets.putIfAbsent(key, () => PeerAddress(
        ip: localIp,
        port: localPort,
        type: PeerAddressType.ipv4Private,
      ));
    }

    final result = targets.values.toList();
    // Sort: priority ASC → receive-confirmed first → effectiveScore DESC.
    // Receive-confirmed (lastReceivedAt != null) addresses have proven
    // bidirectional NAT reachability — critical for symmetric NAT / CGNAT
    // where STUN-discovered ports differ per destination.
    result.sort((a, b) {
      final priCmp = a.priority.compareTo(b.priority);
      if (priCmp != 0) return priCmp;
      final aRecv = a.lastReceivedAt != null ? 0 : 1;
      final bRecv = b.lastReceivedAt != null ? 0 : 1;
      if (aRecv != bRecv) return aRecv.compareTo(bRecv);
      return b.effectiveScore.compareTo(a.effectiveScore);
    });
    return result;
  }

  /// Most recent `lastReceivedAt` across all addresses. `null` if no address
  /// has ever confirmed inbound traffic.
  DateTime? get freshestInboundAt {
    DateTime? best;
    for (final addr in addresses) {
      final lr = addr.lastReceivedAt;
      if (lr != null && (best == null || lr.isAfter(best))) best = lr;
    }
    return best;
  }

  /// D4 (§4.3 Replicator & lookup diversity): coarse IP-group key for the
  /// subnet-diversity selection in `RoutingTable.findClosestPeers`.
  ///
  /// Granularity (eclipse cost binding, §13.1.8):
  ///   IPv4 public  → /16   ("v4:a.b")
  ///   IPv6 global  → /32   ("v6:xxxxxxxx", first 4 raw bytes hex)
  ///   IPv4 private → /24   ("lan4:a.b.c")
  ///   IPv6 ULA/LL/SL → /64 ("lan6:…", first 8 raw bytes hex)
  ///   address-less → shared single "none" group (an attacker must not be
  ///   able to dodge the cap by stripping addresses)
  ///
  /// Picks the peer's most distinctive address (public IPv4 > global IPv6 >
  /// private IPv4 > other IPv6); falls back to the legacy publicIp/localIp
  /// fields when the multi-address list is empty.
  String get ipDiversityGroup {
    PeerAddress? pick;
    var pickRank = 99;
    for (final a in addresses) {
      final r = _diversityRank(a.type);
      if (r < pickRank) {
        pick = a;
        pickRank = r;
      }
    }
    if (pick != null) return _ipGroupKey(pick.ip, pick.type);
    if (publicIp.isNotEmpty && publicIp != '0.0.0.0') {
      return _ipGroupKey(publicIp, PeerAddress.classifyIp(publicIp));
    }
    if (localIp.isNotEmpty && localIp != '0.0.0.0') {
      return _ipGroupKey(localIp, PeerAddress.classifyIp(localIp));
    }
    return 'none';
  }

  static int _diversityRank(PeerAddressType t) {
    switch (t) {
      case PeerAddressType.ipv4Public:
        return 0;
      case PeerAddressType.ipv6Global:
        return 1;
      case PeerAddressType.ipv4Private:
        return 2;
      case PeerAddressType.ipv6Ula:
      case PeerAddressType.ipv6SiteLocal:
      case PeerAddressType.ipv6LinkLocal:
        return 3;
    }
  }

  static String _ipGroupKey(String ip, PeerAddressType type) {
    switch (type) {
      case PeerAddressType.ipv4Public:
        final parts = ip.split('.');
        if (parts.length == 4) return 'v4:${parts[0]}.${parts[1]}';
        return 'v4:$ip';
      case PeerAddressType.ipv4Private:
        final parts = ip.split('.');
        if (parts.length == 4) return 'lan4:${parts[0]}.${parts[1]}.${parts[2]}';
        return 'lan4:$ip';
      case PeerAddressType.ipv6Global:
        final raw = _rawV6(ip);
        if (raw != null) return 'v6:${_bytesToHex(raw.sublist(0, 4))}';
        return 'v6:$ip';
      case PeerAddressType.ipv6Ula:
      case PeerAddressType.ipv6SiteLocal:
      case PeerAddressType.ipv6LinkLocal:
        final raw = _rawV6(ip);
        if (raw != null) return 'lan6:${_bytesToHex(raw.sublist(0, 8))}';
        return 'lan6:$ip';
    }
  }

  /// Parse an IPv6 textual address to its 16 raw bytes. Strips brackets and
  /// zone suffix (`fe80::1%eth0`). Returns null on parse failure — the
  /// caller then groups by the literal string (still deterministic).
  static Uint8List? _rawV6(String ip) {
    var v6 = ip.trim();
    if (v6.startsWith('[')) {
      final close = v6.indexOf(']');
      if (close > 0) v6 = v6.substring(1, close);
    }
    final pct = v6.indexOf('%');
    if (pct >= 0) v6 = v6.substring(0, pct);
    final parsed = InternetAddress.tryParse(v6);
    if (parsed == null || parsed.rawAddress.length != 16) return null;
    return Uint8List.fromList(parsed.rawAddress);
  }

  static proto.NatType _natToProto(NatClassification nat) {
    switch (nat) {
      case NatClassification.unknown:
        return proto.NatType.NAT_UNKNOWN;
      case NatClassification.public_:
        return proto.NatType.NAT_PUBLIC;
      case NatClassification.fullCone:
        return proto.NatType.NAT_FULL_CONE;
      case NatClassification.symmetric:
        return proto.NatType.NAT_SYMMETRIC;
    }
  }

  static NatClassification _natFromProto(proto.NatType nat) {
    switch (nat) {
      case proto.NatType.NAT_PUBLIC:
        return NatClassification.public_;
      case proto.NatType.NAT_FULL_CONE:
        return NatClassification.fullCone;
      case proto.NatType.NAT_SYMMETRIC:
        return NatClassification.symmetric;
      default:
        return NatClassification.unknown;
    }
  }

  /// Serialize to protobuf.
  ///
  /// [slim]: omit PQ key material (ml_dsa_pk, ml_kem_pk, x25519_pk,
  /// device_ml_dsa_pk) and ML-DSA signature. Includes key_fingerprint so the
  /// receiver can detect key changes. ~450B instead of ~8,800B.
  ///
  /// [gossipFilter]: only addresses with at least one local success are
  /// included — prevents propagating unverified NAT-mapped addresses.
  proto.PeerInfoProto toProto({bool slim = false, bool gossipFilter = false}) {
    final p = proto.PeerInfoProto()
      ..nodeId = nodeId
      ..publicIp = publicIp
      ..publicPort = publicPort
      ..localIp = localIp
      ..localPort = localPort
      ..networkTag = networkChannel
      ..lastSeen = Int64(_msFromDateTime(lastSeen))
      ..natType = PeerInfo._natToProto(natType)
      ..capabilities = capabilities;
    for (final addr in addresses) {
      if (gossipFilter && addr.lastSuccess == null && addr.successCount == 0 &&
          addr.lastReceivedAt == null) {
        continue;
      }
      p.addresses.add(addr.toProto());
    }
    if (ed25519PublicKey != null) p.ed25519PublicKey = ed25519PublicKey!;
    if (deviceEd25519PublicKey != null) {
      p.deviceEd25519PublicKey = deviceEd25519PublicKey!;
    }
    // D3: Admission-Nonce reist mit dem Device-PK — auch im slim-Set (8 B).
    if (deviceIdPowNonce != null && deviceIdPowNonce!.isNotEmpty) {
      p.deviceIdPowNonce = deviceIdPowNonce!;
    }
    if (ed25519Signature != null) p.ed25519Signature = ed25519Signature!;
    if (slim) {
      final fp = computedKeyFingerprint;
      if (fp != null) p.keyFingerprint = fp;
    } else {
      if (mlDsaPublicKey != null) p.mlDsaPublicKey = mlDsaPublicKey!;
      if (x25519PublicKey != null) p.x25519PublicKey = x25519PublicKey!;
      if (mlKemPublicKey != null) p.mlKemPublicKey = mlKemPublicKey!;
      if (deviceMlDsaPublicKey != null) {
        p.deviceMlDsaPublicKey = deviceMlDsaPublicKey!;
      }
      if (mlDsaSignature != null) p.mlDsaSignature = mlDsaSignature!;
    }
    if (userId != null && userId!.isNotEmpty) p.userId = userId!;
    return p;
  }

  static PeerInfo fromProto(proto.PeerInfoProto p) {
    return PeerInfo(
      nodeId: Uint8List.fromList(p.nodeId),
      userId: p.userId.isEmpty ? null : Uint8List.fromList(p.userId),
      publicIp: _sanitizeIp(p.publicIp),
      publicPort: p.publicPort,
      localIp: _sanitizeIp(p.localIp),
      localPort: p.localPort,
      addresses: p.addresses.map(PeerAddress.fromProto).whereType<PeerAddress>().toList(),
      networkChannel: p.networkTag,
      lastSeen: _dateFromMs(p.lastSeen.toInt()) ?? DateTime.now(),
      natType: PeerInfo._natFromProto(p.natType),
      capabilities: p.capabilities,
      ed25519PublicKey: p.ed25519PublicKey.isEmpty ? null : Uint8List.fromList(p.ed25519PublicKey),
      mlDsaPublicKey: p.mlDsaPublicKey.isEmpty ? null : Uint8List.fromList(p.mlDsaPublicKey),
      x25519PublicKey: p.x25519PublicKey.isEmpty ? null : Uint8List.fromList(p.x25519PublicKey),
      mlKemPublicKey: p.mlKemPublicKey.isEmpty ? null : Uint8List.fromList(p.mlKemPublicKey),
      deviceEd25519PublicKey: p.deviceEd25519PublicKey.isEmpty
          ? null
          : Uint8List.fromList(p.deviceEd25519PublicKey),
      deviceMlDsaPublicKey: p.deviceMlDsaPublicKey.isEmpty
          ? null
          : Uint8List.fromList(p.deviceMlDsaPublicKey),
      ed25519Signature: p.ed25519Signature.isEmpty ? null : Uint8List.fromList(p.ed25519Signature),
      mlDsaSignature: p.mlDsaSignature.isEmpty ? null : Uint8List.fromList(p.mlDsaSignature),
      keyFingerprint: p.keyFingerprint.isEmpty ? null : Uint8List.fromList(p.keyFingerprint),
      deviceIdPowNonce: p.deviceIdPowNonce.isEmpty
          ? null
          : Uint8List.fromList(p.deviceIdPowNonce),
    );
  }

  /// Strips port suffixes, spaces, garbage, and invalid addresses from IP strings.
  static String _sanitizeIp(String ip) {
    if (ip.isEmpty) return ip;
    // Strip everything after a space
    final spaceIdx = ip.indexOf(' ');
    if (spaceIdx >= 0) ip = ip.substring(0, spaceIdx);
    // Strip port suffix from IPv4
    if (!ip.contains('[') && ip.contains(':')) {
      final parts = ip.split(':');
      if (parts.length == 2) {
        // Could be ip:port
        final portPart = int.tryParse(parts[1]);
        if (portPart != null && portPart > 0 && portPart <= 65535) {
          ip = parts[0];
        }
      }
    }
    ip = ip.trim();
    // Reject addresses that are never valid send targets.
    // 0.0.0.0 as destination causes SocketException(EINVAL) which kills
    // the entire Dart UDP socket — no further sends possible.
    if (ip == '0.0.0.0') return '';
    return ip;
  }

  Map<String, dynamic> toJson() {
    return {
      'nodeId': _bytesToHex(nodeId),
      if (userId != null) 'userId': _bytesToHex(userId!),
      'publicIp': publicIp,
      'publicPort': publicPort,
      'localIp': localIp,
      'localPort': localPort,
      'networkTag': networkChannel,
      'lastSeen': lastSeen.millisecondsSinceEpoch,
      'natType': natType.name,
      'ed25519PublicKey': ed25519PublicKey != null ? _bytesToHex(ed25519PublicKey!) : null,
      'mlDsaPublicKey': mlDsaPublicKey != null ? _bytesToHex(mlDsaPublicKey!) : null,
      'x25519PublicKey': x25519PublicKey != null ? _bytesToHex(x25519PublicKey!) : null,
      'mlKemPublicKey': mlKemPublicKey != null ? _bytesToHex(mlKemPublicKey!) : null,
      // Welle 3 (§17.3): persist Device-Sig PKs so a daemon restart re-uses
      // the cached device pubkey instead of falling back to lenient bootstrap.
      'deviceEd25519PublicKey': deviceEd25519PublicKey != null
          ? _bytesToHex(deviceEd25519PublicKey!)
          : null,
      'deviceMlDsaPublicKey': deviceMlDsaPublicKey != null
          ? _bytesToHex(deviceMlDsaPublicKey!)
          : null,
      // Persist provenance so a daemon restart preserves the firstParty
      // protection (Architecture §17.3). Without this, every restart would
      // reset to thirdParty and re-open the pollution window.
      if (pkSource != PkSource.none) 'pkSource': pkSource.name,
      // D3 (§13.1.2): Admission-Nonce + Verifikationsergebnis ueberleben
      // den Daemon-Restart (sonst wuerde jeder Restart neu verifizieren).
      if (deviceIdPowNonce != null)
        'deviceIdPowNonce': _bytesToHex(deviceIdPowNonce!),
      if (idPowVerified) 'idPowVerified': true,
      'addresses': addresses.map((a) => {
        'ip': a.ip,
        'port': a.port,
        'type': a.type.name,
        'score': a.score,
        'successCount': a.successCount,
        'failCount': a.failCount,
        if (a.lastReceivedAt != null)
          'lastReceivedAt': a.lastReceivedAt!.millisecondsSinceEpoch,
        if (a.stableSince != null)
          'stableSince': a.stableSince!.millisecondsSinceEpoch,
      }).toList(),
      if (isProtectedSeed) 'isProtectedSeed': true,
      if (addressChangeCount > 0) 'addressChangeCount': addressChangeCount,
    };
  }

  static PeerInfo fromJson(Map<String, dynamic> json) {
    return PeerInfo(
      nodeId: _hexToBytes(json['nodeId'] as String),
      userId: json['userId'] != null ? _hexToBytes(json['userId'] as String) : null,
      publicIp: _sanitizeIp(json['publicIp'] as String? ?? ''),
      publicPort: json['publicPort'] as int? ?? 0,
      localIp: _sanitizeIp(json['localIp'] as String? ?? ''),
      localPort: json['localPort'] as int? ?? 0,
      networkChannel: json['networkTag'] as String? ?? 'beta',
      lastSeen: DateTime.fromMillisecondsSinceEpoch(json['lastSeen'] as int? ?? 0),
      natType: NatClassification.values.firstWhere(
        (e) => e.name == (json['natType'] as String? ?? 'unknown'),
        orElse: () => NatClassification.unknown,
      ),
      ed25519PublicKey: json['ed25519PublicKey'] != null ? _hexToBytes(json['ed25519PublicKey'] as String) : null,
      mlDsaPublicKey: json['mlDsaPublicKey'] != null ? _hexToBytes(json['mlDsaPublicKey'] as String) : null,
      x25519PublicKey: json['x25519PublicKey'] != null ? _hexToBytes(json['x25519PublicKey'] as String) : null,
      mlKemPublicKey: json['mlKemPublicKey'] != null ? _hexToBytes(json['mlKemPublicKey'] as String) : null,
      deviceEd25519PublicKey: json['deviceEd25519PublicKey'] != null
          ? _hexToBytes(json['deviceEd25519PublicKey'] as String)
          : null,
      deviceMlDsaPublicKey: json['deviceMlDsaPublicKey'] != null
          ? _hexToBytes(json['deviceMlDsaPublicKey'] as String)
          : null,
      pkSource: PkSource.values.firstWhere(
        (e) => e.name == (json['pkSource'] as String? ?? 'none'),
        orElse: () => PkSource.none,
      ),
      addresses: (json['addresses'] as List<dynamic>?)?.map((a) {
        final m = a as Map<String, dynamic>;
        final ip = (m['ip'] as String).trim();
        final port = m['port'] as int;
        if (ip.isEmpty || ip == '0.0.0.0' || port <= 0) return null;
        final lrMs = m['lastReceivedAt'] as int?;
        final ssMs = m['stableSince'] as int?;
        return PeerAddress(
          ip: ip,
          port: port,
          type: PeerAddressType.values.firstWhere(
            (e) => e.name == (m['type'] as String? ?? 'ipv4Public'),
            orElse: () => PeerAddressType.ipv4Public,
          ),
          score: (m['score'] as num?)?.toDouble() ?? 0.5,
          successCount: m['successCount'] as int? ?? 0,
          failCount: m['failCount'] as int? ?? 0,
          lastReceivedAt: lrMs != null
              ? DateTime.fromMillisecondsSinceEpoch(lrMs)
              : null,
          stableSince: ssMs != null
              ? DateTime.fromMillisecondsSinceEpoch(ssMs)
              : null,
        );
      }).whereType<PeerAddress>().toList() ?? [],
      deviceIdPowNonce: json['deviceIdPowNonce'] != null
          ? _hexToBytes(json['deviceIdPowNonce'] as String)
          : null,
    )
      ..isProtectedSeed = json['isProtectedSeed'] as bool? ?? false
      ..idPowVerified = json['idPowVerified'] as bool? ?? false
      ..addressChangeCount = json['addressChangeCount'] as int? ?? 0;
  }

  @override
  String toString() => 'Peer(${nodeIdHex.substring(0, 8)}.. $publicIp:$publicPort)';
}

enum NatClassification { unknown, public_, fullCone, symmetric }

// ── Helpers ────────────────────────────────────────────────────────────

bool _isPrivateIp(String ip) {
  // IPv6 classification
  if (ip.contains(':')) {
    final lower = ip.toLowerCase();
    if (lower.startsWith('fe80:')) return true;   // Link-local
    if (lower.startsWith('fc') || lower.startsWith('fd')) return true; // ULA
    if (lower == '::1') return true;              // Loopback
    return false; // Global IPv6 = public (no NAT)
  }
  // IPv4
  if (ip.startsWith('10.')) return true;
  if (ip.startsWith('172.')) {
    final second = int.tryParse(ip.split('.')[1]);
    if (second != null && second >= 16 && second <= 31) return true;
  }
  if (ip.startsWith('192.168.')) return true;
  if (ip.startsWith('127.')) return true;
  // CGNAT ranges — not routable from the internet
  if (ip.startsWith('100.')) {
    final second = int.tryParse(ip.split('.')[1]) ?? 0;
    if (second >= 64 && second <= 127) return true; // 100.64.0.0/10
  }
  if (ip.startsWith('192.0.0.')) return true; // IETF reserved / DS-Lite
  return false;
}

int _msFromDateTime(DateTime dt) => dt.millisecondsSinceEpoch;
DateTime? _dateFromMs(int ms) => ms == 0 ? null : DateTime.fromMillisecondsSinceEpoch(ms);
// ignore: non_constant_identifier_names
int Int64FromDateTime(DateTime? dt) => dt?.millisecondsSinceEpoch ?? 0;

String _bytesToHex(Uint8List bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

Uint8List _hexToBytes(String hex) {
  final result = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < result.length; i++) {
    result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return result;
}

/// Shared hex conversion utilities
String bytesToHex(Uint8List bytes) => _bytesToHex(bytes);
Uint8List hexToBytes(String hex) => _hexToBytes(hex);
