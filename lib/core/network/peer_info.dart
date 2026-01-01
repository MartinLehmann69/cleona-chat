import 'dart:typed_data';
import 'package:fixnum/fixnum.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

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
  });

  /// Base delay for exponential backoff (doubles each failure).
  static const _baseBackoffMs = 2000; // 2s
  static const _maxBackoffMs = 120000; // 2 min cap

  void recordSuccess() {
    successCount++;
    consecutiveFailures = 0;
    lastSuccess = DateTime.now();
    lastAttempt = lastSuccess;
    score = successCount / (successCount + failCount);
  }

  void recordFailure() {
    failCount++;
    consecutiveFailures++;
    lastAttempt = DateTime.now();
    score = successCount / (successCount + failCount);
  }

  /// Whether this address should be skipped due to backoff.
  bool get isInBackoff {
    if (consecutiveFailures < 2) return false;
    final last = lastAttempt;
    if (last == null) return false;
    final elapsed = DateTime.now().difference(last).inMilliseconds;
    return elapsed < currentBackoffMs;
  }

  /// Current backoff delay in ms (exponential: 2s, 4s, 8s, ... capped at 2min).
  int get currentBackoffMs {
    if (consecutiveFailures < 2) return 0;
    final delay = _baseBackoffMs * (1 << (consecutiveFailures - 2).clamp(0, 6));
    return delay.clamp(0, _maxBackoffMs);
  }

  proto.PeerAddressProto toProto() {
    return proto.PeerAddressProto()
      ..ip = ip
      ..port = port
      ..addressType = _typeToProto(type)
      ..score = score
      ..lastSuccess = Int64(lastSuccess?.millisecondsSinceEpoch ?? 0)
      ..lastAttempt = Int64(lastAttempt?.millisecondsSinceEpoch ?? 0)
      ..successCount = successCount
      ..failCount = failCount;
  }

  static PeerAddress? fromProto(proto.PeerAddressProto p) {
    final ip = p.ip.trim();
    if (ip.isEmpty || ip == '0.0.0.0' || ip == '::' || p.port <= 0) return null;
    return PeerAddress(
      ip: ip,
      port: p.port,
      type: _typeFromProto(p.addressType),
      score: p.score,
      lastSuccess: _dateFromMs(p.lastSuccess.toInt()),
      lastAttempt: _dateFromMs(p.lastAttempt.toInt()),
      successCount: p.successCount,
      failCount: p.failCount,
    );
  }

  static proto.AddressType _typeToProto(PeerAddressType t) {
    switch (t) {
      case PeerAddressType.ipv4Public:
        return proto.AddressType.IPV4_PUBLIC;
      case PeerAddressType.ipv4Private:
        return proto.AddressType.IPV4_PRIVATE;
      case PeerAddressType.ipv6Global:
        return proto.AddressType.IPV6_GLOBAL;
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
      default:
        return PeerAddressType.ipv4Public;
    }
  }

  /// Current local IPs — set by CleonaNode on start and network change.
  /// Used for address priority calculation (same subnet = highest priority).
  static List<String> currentLocalIps = [];

  /// Address priority: 1=same-subnet/link-local, 2=IPv6 global/other-private,
  /// 3=public IPv4, 4=CGNAT/mobile.
  int get priority {
    // IPv6
    if (ip.contains(':')) {
      if (ip.toLowerCase().startsWith('fe80:')) return 1; // Link-local = LAN
      return 2; // Global IPv6 — better than public IPv4 (no NAT!)
    }
    // IPv4
    if (_isCgnat(ip)) return 4;
    if (!_isPrivateIp(ip)) return 3;
    for (final localIp in currentLocalIps) {
      if (_sameSubnet(ip, localIp)) return 1;
    }
    return 2; // Other private subnet
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

  /// Check if two IPs are in the same /24 subnet (IPv4 only).
  static bool _sameSubnet(String ip1, String ip2) {
    if (ip1.contains(':') || ip2.contains(':')) return false; // IPv6: no /24 concept
    final p1 = ip1.split('.');
    final p2 = ip2.split('.');
    if (p1.length != 4 || p2.length != 4) return false;
    return p1[0] == p2[0] && p1[1] == p2[1] && p1[2] == p2[2];
  }

  /// Whether this address is reachable from the device's current network.
  /// Global IPv6 reachable iff WE have a global IPv6 — site-local (fec0:),
  /// ULA (fc00:/fd00:), link-local (fe80:) on the device do not provide global
  /// egress (e.g. QEMU user-mode NAT routes ::/0 via fe80::2 but drops the
  /// packet silently; OS-level send returns ok and the score-pinning prevents
  /// IPv4 fallback from ever being tried).
  /// Private IPs reachable iff WE have any private IP — different RFC1918
  /// classes within one routed network are common (192.168.10.x ↔ 192.0.2.x
  /// across VLANs, 10.0.2.x QEMU-NAT egressing onto a 192.168.x host LAN).
  /// CGNAT IPs (100.64.x.x) are treated like public (mobile carrier NAT outbound works).
  bool get isReachableFromCurrentNetwork {
    if (ip.contains(':') && !ip.toLowerCase().startsWith('fe80:')) {
      if (ip == '::1') return true; // loopback to self always reachable
      return _hasGlobalIpv6();
    }
    if (!_isPrivateIp(ip)) return true;
    // Loopback is always reachable from the same machine
    if (ip.startsWith('127.')) return true;
    // Target is private — are WE also on a private network?
    // Cross-class private routing is common in test labs and home networks,
    // so any private local IP qualifies. If a target is genuinely on an
    // isolated subnet, the UDP send simply fails and the cascade falls back
    // to relay; better than blanket-suppressing valid local addresses.
    for (final localIp in currentLocalIps) {
      if (_isPrivateIp(localIp)) return true;
    }
    return false;
  }

  /// True if the device has at least one routable (global) IPv6 address.
  /// Excludes link-local (fe80:), site-local-deprecated (fec0:),
  /// ULA (fc00:/fd00:), loopback (::1), multicast (ff..).
  static bool _hasGlobalIpv6() {
    for (final localIp in currentLocalIps) {
      if (!localIp.contains(':')) continue;
      final lower = localIp.toLowerCase();
      if (lower == '::1') continue;
      if (lower.startsWith('fe80:')) continue;
      if (lower.startsWith('fec0:')) continue;
      if (lower.startsWith('ff')) continue;
      if (lower.startsWith('fc') || lower.startsWith('fd')) continue;
      return true;
    }
    return false;
  }

  /// Public access to private-IP check (needed by cleona_node for relay logic).
  static bool isPrivateIp(String ip) => _isPrivateIp(ip);

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

enum PeerAddressType { ipv4Public, ipv4Private, ipv6Global }

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

  bool get isAlive => cost < infinity && consecutiveFailures < 3;
  bool get isDirect => nextHop == null;

  String get destinationHex => _bytesToHex(destination);
  String? get nextHopHex => nextHop != null ? _bytesToHex(nextHop!) : null;

  @override
  String toString() =>
      'Route(${destinationHex.substring(0, 8)}.. '
      'via ${nextHopHex?.substring(0, 8) ?? "direct"}, '
      'cost=$cost, hops=$hopCount, ${connType.name})';
}

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
  Uint8List? ed25519PublicKey;
  Uint8List? mlDsaPublicKey;
  Uint8List? x25519PublicKey;
  Uint8List? mlKemPublicKey;
  Uint8List? ed25519Signature;
  Uint8List? mlDsaSignature;

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

  /// Clear the relay route (on network change, or relay peer gone).
  void clearRelayRoute() {
    relayViaNodeId = null;
    relaySetAt = null;
    consecutiveRelayFailures = 0;
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
  /// (Bob's CHANNEL_INDEX_EXCHANGE arrives every 5-15min) but short enough
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
    this.ed25519Signature,
    this.mlDsaSignature,
  })  : addresses = addresses ?? [],
        lastSeen = lastSeen ?? DateTime.now();

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
    // Sort by priority ASC (lower = better), then by score DESC (higher = better)
    result.sort((a, b) {
      final priCmp = a.priority.compareTo(b.priority);
      if (priCmp != 0) return priCmp;
      return b.score.compareTo(a.score);
    });
    return result;
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

  proto.PeerInfoProto toProto() {
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
      p.addresses.add(addr.toProto());
    }
    if (ed25519PublicKey != null) p.ed25519PublicKey = ed25519PublicKey!;
    if (mlDsaPublicKey != null) p.mlDsaPublicKey = mlDsaPublicKey!;
    if (x25519PublicKey != null) p.x25519PublicKey = x25519PublicKey!;
    if (mlKemPublicKey != null) p.mlKemPublicKey = mlKemPublicKey!;
    if (ed25519Signature != null) p.ed25519Signature = ed25519Signature!;
    if (mlDsaSignature != null) p.mlDsaSignature = mlDsaSignature!;
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
      ed25519Signature: p.ed25519Signature.isEmpty ? null : Uint8List.fromList(p.ed25519Signature),
      mlDsaSignature: p.mlDsaSignature.isEmpty ? null : Uint8List.fromList(p.mlDsaSignature),
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
      'x25519PublicKey': x25519PublicKey != null ? _bytesToHex(x25519PublicKey!) : null,
      'mlKemPublicKey': mlKemPublicKey != null ? _bytesToHex(mlKemPublicKey!) : null,
      'addresses': addresses.map((a) => {
        'ip': a.ip,
        'port': a.port,
        'type': a.type.name,
        'score': a.score,
        'successCount': a.successCount,
        'failCount': a.failCount,
      }).toList(),
      if (isProtectedSeed) 'isProtectedSeed': true,
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
      x25519PublicKey: json['x25519PublicKey'] != null ? _hexToBytes(json['x25519PublicKey'] as String) : null,
      mlKemPublicKey: json['mlKemPublicKey'] != null ? _hexToBytes(json['mlKemPublicKey'] as String) : null,
      addresses: (json['addresses'] as List<dynamic>?)?.map((a) {
        final m = a as Map<String, dynamic>;
        final ip = (m['ip'] as String).trim();
        final port = m['port'] as int;
        if (ip.isEmpty || ip == '0.0.0.0' || port <= 0) return null;
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
        );
      }).whereType<PeerAddress>().toList() ?? [],
    )..isProtectedSeed = json['isProtectedSeed'] as bool? ?? false;
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
