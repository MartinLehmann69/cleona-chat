import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/crypto/proof_of_work.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/dht/kbucket.dart';
import 'package:cleona/core/dht/dht_rpc.dart';
import 'package:cleona/core/network/ack_tracker.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/message_queue.dart';
import 'package:cleona/core/network/peer_message_store.dart';
import 'package:cleona/core/network/reachability_probe.dart';
import 'package:cleona/core/network/lan_discovery.dart';
import 'package:cleona/core/network/tls_fallback.dart';
import 'package:cleona/core/network/nat_traversal.dart';
import 'package:cleona/core/network/port_mapper.dart';
import 'package:cleona/core/network/compression.dart';
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/core/network/dv_routing.dart';
import 'package:cleona/core/network/transport.dart';
import 'package:cleona/core/network/relay_chunker.dart';
import 'package:cleona/core/network/udp_fragmenter.dart';
import 'package:cleona/core/network/rate_limiter.dart';
import 'package:cleona/core/network/peer_reputation.dart';
import 'package:cleona/core/node/identity_context.dart';
import 'package:cleona/core/node/relay_budget.dart';
import 'package:fixnum/fixnum.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Central network component. Handles transport, DHT, discovery, and message dispatch.
/// Shared by all identities — one node, one port, one network stack.
class CleonaNode {
  final String profileDir;
  int port;
  final String networkChannel;
  final CLogger _log;

  /// Primary identity used for DHT protocol messages (PING/PONG senderId).
  late IdentityContext primaryIdentity;

  /// TLS fallback manager: tracks per-peer consecutive failures, activates TLS when UDP is blocked.
  final TlsFallbackManager _tlsFallback = TlsFallbackManager();

  /// Relay budget: rate-limiting and dedup for relay traffic.
  final RelayBudget _relayBudget = RelayBudget();

  /// Per-node rate limiter (DoS Layer 2, Architecture Section 9.2).
  late final RateLimiter rateLimiter;

  /// Local peer reputation + banning (DoS Layers 3+5, Architecture Sections 9.3/9.5).
  late final ReputationManager reputationManager;

  /// Chunk reassembler for MEDIA_CHUNK messages (large envelopes split for relay).
  late final ChunkReassembler _chunkReassembler;

  /// Callback for relay stats tracking (wired by CleonaService).
  void Function(int bytes)? onRelayBytes;

  /// Callback for mutual peer computation (wired by CleonaService).
  /// Returns nodeIdHex set of peers likely known to the recipient
  /// (shared contacts + shared group members). Architecture Section 3.3.7.
  Set<String> Function(Uint8List recipientNodeId)? getMutualPeerIds;

  /// All registered identities: userIdHex → IdentityContext.
  /// Keyed by userId (stable identity), not deviceNodeId (per-device routing).
  final Map<String, IdentityContext> _identities = {};

  /// Reverse lookup: deviceNodeId hex → IdentityContext.
  /// Used for routing table operations that reference device-specific IDs.
  final Map<String, IdentityContext> _identitiesByDeviceId = {};

  // Components
  late Transport transport;
  late RoutingTable routingTable;
  late DhtRpc dhtRpc;
  late AckTracker ackTracker;
  late PeerMessageStore peerMessageStore;
  late MessageQueue messageQueue;
  late ReachabilityProbe reachabilityProbe;
  late LocalDiscovery localDiscovery;
  late MulticastDiscovery multicastDiscovery;
  late NatTraversal natTraversal;
  late DvRoutingTable dvRouting;
  late PortMapper portMapper;

  // Callback for application-layer messages routed to a specific identity.
  // If identity is null, recipientId didn't match any registered identity.
  void Function(proto.MessageEnvelope envelope, InternetAddress from, int port, IdentityContext? identity)? onMessageForIdentity;

  // State
  StreamSubscription<PortMapperEvent>? _portMapperSub;
  Timer? _maintenanceTimer;
  Timer? _peerExchangeTimer;
  Timer? _dvSafetyNetTimer;
  Timer? _dvPropagationDebounce;
  final Set<String> _dvPendingChanges = {};
  bool _running = false;
  late final DateTime _startedAt;
  DateTime? _lastNetworkChangeAt;
  String _localIp = '';
  List<String> _localIps = [];

  // Mass route-down detection: infer network change when ≥3 routes fail within 30s.
  final List<DateTime> _routeDownTimestamps = [];
  bool _networkChangeInProgress = false;

  /// Peers that have actually responded since this node started.
  /// Used to distinguish "loaded from disk" peers from truly reachable ones.
  final Set<String> _confirmedPeers = {};
  /// Live view: drops peers whose direct AND relay routes have died (3x ACK
  /// timeout) so the connection-status UI doesn't show "all good" after the
  /// network broke. Stays cheap because the set is small (handful of peers).
  Set<String> get confirmedPeerIds => _confirmedPeers.where((hex) {
        try {
          final peer = routingTable.getPeer(hexToBytes(hex));
          if (peer == null) return false;
          // Route DOWN if BOTH direct (3x consecutiveRouteFailures) AND relay
          // (3x consecutiveRelayFailures) have given up.
          final directDead = peer.consecutiveRouteFailures >= 3;
          final relayDead = peer.consecutiveRelayFailures >= 3 ||
                            peer.relayViaNodeId == null;
          return !(directDead && relayDead);
        } catch (_) {
          return false;
        }
      }).toSet();

  /// Last live UDP address per peer — for S&F push to mobile peers.
  final Map<String, (InternetAddress, int)> _lastLiveAddr = {};

  // Message-level dedup: skip duplicate application messages (same messageId).
  // Prevents double-processing when the same message arrives via multiple paths
  // (e.g. RELAY_FORWARD + S&F push, or multiple relay routes).
  final LinkedHashSet<String> _seenMessageIds = LinkedHashSet<String>();
  static const int _maxSeenMessages = 1000;

  // DV-Routing: track when we last sent a route update to each neighbor.
  // Used for catch-up: if >60s since last update, send full routes on next packet.
  final Map<String, DateTime> _lastRouteUpdateSentTo = {};

  /// Pending relay sends: relayIdHex → (recipientNodeId, relayPeerNodeId).
  /// Used by _handleRelayAck() to learn relay routes.
  final Map<String, ({Uint8List recipientNodeId, Uint8List relayPeerNodeId})> _pendingRelays = {};

  CleonaNode({
    required this.profileDir,
    required this.port,
    this.networkChannel = 'beta',
  }) : _log = CLogger.get('node', profileDir: profileDir),
       _chunkReassembler = ChunkReassembler(profileDir: profileDir) {
    rateLimiter = RateLimiter.production();
    reputationManager = ReputationManager.production(profileDir: profileDir);
  }

  /// Register an identity with the node.
  /// Can be called before or after start() — routing table registration is deferred if needed.
  void registerIdentity(IdentityContext ctx) {
    _identities[ctx.userIdHex] = ctx;
    _identitiesByDeviceId[ctx.nodeIdHex] = ctx;
    if (_running) {
      routingTable.addLocalNodeId(ctx.userId);       // identity (for message delivery)
      routingTable.addLocalNodeId(ctx.deviceNodeId);  // routing (for XOR exclusion)
    }
    _log.info('Identity registered: ${ctx.displayName} '
        '(user=${ctx.userIdHex.substring(0, 8)}, device=${ctx.nodeIdHex.substring(0, 8)})');
  }

  /// Unregister an identity from the node.
  /// Accepts either userIdHex or deviceNodeIdHex (backward compat).
  void unregisterIdentity(String idHex) {
    // Try userId first, then deviceNodeId
    var ctx = _identities.remove(idHex);
    if (ctx != null) {
      _identitiesByDeviceId.remove(ctx.nodeIdHex);
    } else {
      ctx = _identitiesByDeviceId.remove(idHex);
      if (ctx != null) {
        _identities.remove(ctx.userIdHex);
      }
    }
    if (ctx != null) {
      if (_running) {
        routingTable.removeLocalNodeId(ctx.userId);
        routingTable.removeLocalNodeId(ctx.deviceNodeId);
      }
      _log.info('Identity unregistered: ${ctx.displayName}');
    }
  }

  /// Get an identity by userIdHex (stable identity).
  IdentityContext? getIdentity(String userIdHex) => _identities[userIdHex];

  /// Get an identity by deviceNodeId hex (per-device routing).
  IdentityContext? getIdentityByDeviceId(String deviceNodeIdHex) =>
      _identitiesByDeviceId[deviceNodeIdHex];

  /// All registered identities.
  Iterable<IdentityContext> get identities => _identities.values;

  /// Start the node.
  /// Common init: transport, discovery, routing table — no bootstrap yet.
  Future<void> _startBase({List<String> bootstrapPeers = const []}) async {
    _log.info('Starting node on port $port...');

    // Init routing table BEFORE transport (transport callbacks need it)
    // Phase 2: ownNodeId = deviceNodeId (per-device XOR distance)
    routingTable = RoutingTable(primaryIdentity.deviceNodeId);
    // Register all identities as local (both userId for message delivery
    // and deviceNodeId for routing exclusion)
    for (final ctx in _identities.values) {
      routingTable.addLocalNodeId(ctx.userId);
      routingTable.addLocalNodeId(ctx.deviceNodeId);
    }
    _loadRoutingTable();
    // Set _startedAt AFTER loading routing table — _loadRoutingTable touches
    // all peers (lastSeen=now) to prevent maintenance prune. _startedAt must
    // be after that so _hasRecentlyReachablePeer() ignores disk-loaded peers.
    _startedAt = DateTime.now();

    // Init DHT RPC
    dhtRpc = DhtRpc(profileDir: profileDir);
    dhtRpc.sendFunction = _sendEnvelopeToPeer;

    // Init RUDP Light ACK tracker (uses shared RTT from DhtRpc)
    ackTracker = AckTracker(rttSource: dhtRpc, profileDir: profileDir);

    // RUDP Light retry: on ACK timeout, re-queue message for immediate re-send.
    // Architecture Section 2.4.3: "On timeout → try next route."
    // The re-queued message runs through sendEnvelope() again, which picks
    // the next cheapest route (failed route has incremented failure counter).
    ackTracker.onRetryNeeded = (messageIdHex, serializedEnvelope, recipientNodeId) {
      if (!messageQueue.contains(messageIdHex)) {
        messageQueue.enqueue(
          messageIdHex: messageIdHex,
          recipientNodeId: recipientNodeId,
          serializedEnvelope: serializedEnvelope,
        );
      }
      // Immediate drain — don't wait for the 30s periodic timer.
      final recipientHex = bytesToHex(recipientNodeId);
      messageQueue.drainForRecipient(recipientHex);
    };

    // Wire Route-Down: 3x ACK timeout → surgical DV markRouteDown → Poison Reverse
    // V3.1: Only the specific route (via nextHop) is marked down, not all routes.
    // V3.1.44: Mass route-down detection → infer network change → re-discover public IP.
    ackTracker.onRouteDown = (peerHex, {String? viaNextHopHex}) {
      final viaShort = viaNextHopHex != null ? viaNextHopHex.substring(0, 8) : 'direct';
      _log.info('Route DOWN via ACK: ${peerHex.substring(0, 8)} via $viaShort — surgical DV markRouteDown');
      dvRouting.markRouteDown(peerHex, viaNextHopHex: viaNextHopHex);

      // Mass route-down → infer network change (e.g. ISP IP reassignment, WiFi switch).
      // If ≥3 distinct peers go DOWN within 30s, trigger onNetworkChanged().
      _routeDownTimestamps.add(DateTime.now());
      _routeDownTimestamps.removeWhere((t) =>
          DateTime.now().difference(t).inSeconds > 30);
      if (_routeDownTimestamps.length >= 3 && !_networkChangeInProgress) {
        _log.info('Mass route-down detected (${_routeDownTimestamps.length} in 30s) '
            '— inferring network change');
        _routeDownTimestamps.clear();
        _networkChangeInProgress = true;
        onNetworkChanged(force: true).whenComplete(() => _networkChangeInProgress = false);
      }

      final peer = routingTable.getPeer(hexToBytes(peerHex));
      if (peer == null) return;

      if (viaNextHopHex != null) {
        // Relay route failure — only invalidate if this IS the learned relay route
        final relayHex = peer.relayViaNodeId != null ? bytesToHex(peer.relayViaNodeId!) : null;
        if (relayHex == viaNextHopHex) {
          peer.consecutiveRelayFailures = 3;
          _log.info('Relay route DOWN: ${peerHex.substring(0, 8)} via $viaShort — clearing learned relay');
          peer.clearRelayRoute();
        }
      } else {
        // Direct route failure — only mark peer as fully unreachable if NO DV alternatives
        final remaining = dvRouting.routesTo(peerHex).where((r) => r.isAlive).toList();
        if (remaining.isNotEmpty) {
          _log.info('Route DOWN: ${remaining.length} alternative route(s) remain for ${peerHex.substring(0, 8)}');
        } else {
          peer.consecutiveRouteFailures = 3;
        }
      }
    };

    // Init Store-and-Forward message store
    peerMessageStore = PeerMessageStore(profileDir: profileDir);
    await peerMessageStore.load();

    // Init message queue (holds messages when no route available)
    messageQueue = MessageQueue(profileDir: profileDir);
    await messageQueue.load();
    messageQueue.onRetrySend = (serializedEnvelope, recipientNodeId) {
      final env = proto.MessageEnvelope.fromBuffer(serializedEnvelope);
      return sendEnvelope(env, recipientNodeId);
    };

    // Load reputation data from disk
    await reputationManager.load(profileDir);

    // Init reachability probe (relay route discovery)
    reachabilityProbe = ReachabilityProbe(profileDir: profileDir);
    reachabilityProbe.sendFunction = (env, nodeId) => sendEnvelope(env, nodeId);
    reachabilityProbe.createEnvelopeFunction = (type, payload, {Uint8List? recipientId}) =>
        primaryIdentity.createSignedEnvelope(type, payload, recipientId: recipientId);
    reachabilityProbe.getCandidatesFunction = (targetNodeId) {
      final targetHex = bytesToHex(targetNodeId);
      return routingTable.allPeers
          .where((p) => _confirmedPeers.contains(p.nodeIdHex))
          .where((p) => p.nodeIdHex != targetHex)
          .where((p) => !routingTable.isLocalNode(p.nodeId))
          .toList();
    };
    reachabilityProbe.randomBytesFunction = (size) => SodiumFFI().randomBytes(size);

    // Init Distance-Vector routing table (V3)
    // Phase 2: ownNodeId = deviceNodeId (per-device routing)
    dvRouting = DvRoutingTable(ownNodeId: primaryIdentity.deviceNodeId);
    dvRouting.onRouteChanged = _onDvRouteChanged;

    // Init NAT traversal
    natTraversal = NatTraversal(profileDir: profileDir);
    natTraversal.ownNodeId = primaryIdentity.deviceNodeId;
    natTraversal.sendFunction = (env, nodeId) => sendEnvelope(env, nodeId);
    natTraversal.sendUdpRaw = (data, addr, port) => transport.sendUdpRaw(data, addr, port);
    natTraversal.createEnvelope = (type, payload, {Uint8List? recipientId}) =>
        primaryIdentity.createSignedEnvelope(type, payload, recipientId: recipientId);
    natTraversal.onHolePunchSuccess = _onHolePunchSuccess;

    // Get all local IPs BEFORE transport starts — isReachableFromCurrentNetwork
    // depends on this being set when incoming packets trigger outgoing sends.
    final allIps = await Transport.getAllLocalIps();
    _localIp = allIps.isNotEmpty ? allIps.first : '127.0.0.1';
    _localIps = allIps;
    PeerAddress.currentLocalIps = _localIps;
    _log.info('Local IPs: ${allIps.join(", ")} (primary: $_localIp)');

    // Init transport (starts receiving immediately — localIps must be set first)
    transport = Transport(port: port, profileDir: profileDir);
    transport.onEnvelope = _onEnvelopeReceived;
    transport.onDiscovery = _onDiscoveryReceived;
    transport.onPortProbe = _onPortProbeReceived;
    await transport.start();

    // Init LAN discovery — Phase 2: broadcast deviceNodeId (per-device routing)
    localDiscovery = LocalDiscovery(
      nodeId: primaryIdentity.deviceNodeId,
      nodePort: port,
      profileDir: profileDir,
    );
    localDiscovery.onDiscovered = _onPeerDiscovered;

    multicastDiscovery = MulticastDiscovery(
      nodeId: primaryIdentity.deviceNodeId,
      nodePort: port,
      profileDir: profileDir,
    );
    multicastDiscovery.onDiscovered = _onPeerDiscovered;

    await localDiscovery.start();
    await multicastDiscovery.start();

    // Port mapping (NAT-PMP/PCP + UPnP) — non-blocking, runs in background.
    // NatTraversal is injected so PortMapper can populate the NAT-Wizard
    // signals (§27.9.1): upnpStatus, pcpStatus, upnpRouterInfoJson.
    portMapper = PortMapper(
      internalPort: port,
      requestedExternalPort: port,
      profileDir: profileDir,
      natTraversal: natTraversal,
    );
    _portMapperSub = portMapper.events.listen(_onPortMapperEvent);
    // Fire-and-forget: don't block startup, results come via event stream
    portMapper.start();

    // Register self in routing table's peer manager
    _registerSelf();

    // No startup prune — peers may have stale lastSeen from previous session,
    // but are reachable right now. The regular maintenance timer (60s, 4h threshold)
    // handles cleanup AFTER peers have had a chance to respond to PINGs.

    // Bootstrap from known peers — send PING and wait for PONG
    if (bootstrapPeers.isNotEmpty) {
      for (final bp in bootstrapPeers) {
        _addBootstrapPeer(bp);
      }
    }
    _loadBootstrapSeeds();

    // Wait for PINGs to get PONGs back (populates routing table)
    if (bootstrapPeers.isNotEmpty || routingTable.peerCount == 0) {
      await Future.delayed(const Duration(seconds: 3));
    }
  }

  /// Full start (blocking bootstrap). Used by headless mode.
  Future<void> start({List<String> bootstrapPeers = const []}) async {
    await _startBase(bootstrapPeers: bootstrapPeers);

    // Start Kademlia bootstrap (FIND_NODE for own ID)
    await _kademliaBootstrap();

    _finishStart();
  }

  /// Quick start: transport + discovery immediately, bootstrap in background.
  Future<void> startQuick({List<String> bootstrapPeers = const []}) async {
    // Everything identical up to the bootstrap point
    await _startBase(bootstrapPeers: bootstrapPeers);

    // Bootstrap + Peer Exchange in background
    _kademliaBootstrap().then((_) => _finishStart());

    _running = true;
    _log.info('Node quick-started. Background bootstrap in progress...');
  }

  void _finishStart() {
    // Immediate peer exchange with all known peers
    if (routingTable.peerCount > 0) {
      _doPeerExchange();
      // Also broadcast our own PeerInfo (including PKs)
      _broadcastAddressUpdate();
    }

    // Cross-subnet discovery: scan other /24 subnets in the /16 range via
    // unicast on the discovery port. Runs when no peer is confirmed reachable
    // (not just when peerCount==0 — peers may exist but be unreachable due to
    // AP isolation or network change). Stops as soon as any peer responds.
    if (!_hasRecentlyReachablePeer()) {
      _log.info('No recently reachable peer at startup — starting subnet scan');
      localDiscovery.startSubnetScan(_localIps, () => _hasRecentlyReachablePeer());
    }

    // Start maintenance timer (60 seconds)
    _maintenanceTimer ??= Timer.periodic(const Duration(seconds: 60), (_) => _maintenance());

    // Start peer exchange timer (every 120 seconds)
    _peerExchangeTimer ??= Timer.periodic(const Duration(seconds: 120), (_) => _doPeerExchange());

    // Safety-Net: full route exchange every 1h (in case an update was missed)
    _dvSafetyNetTimer ??= Timer.periodic(const Duration(hours: 1), (_) => _dvSafetyNetExchange());

    _running = true;
    _log.info('Node started. Peers: ${routingTable.peerCount}');
  }

  void _registerSelf() {
    // We don't add ourselves to the routing table, but we store our info
    // for PeerExchange to include our PK.
  }

  void _onEnvelopeReceived(proto.MessageEnvelope envelope, InternetAddress from, int fromPort, {bool isUdp = false, bool skipRateLimit = false}) {
    final type = envelope.messageType;

    // Network channel filter (defense-in-depth — HMAC already filters at transport layer)
    if (envelope.networkTag.isNotEmpty && envelope.networkTag != networkChannel) return;

    // --- DoS Layer 3+5: Ban check (Architecture Section 9.3/9.5) ---
    // Banned peers are silently dropped before any processing.
    if (envelope.senderId.isNotEmpty) {
      final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
      if (reputationManager.isBanned(senderHex)) return;

      // --- DoS Layer 2: Rate limiting (Architecture Section 9.2) ---
      // Excessive traffic from a single source is silently dropped.
      // skipRateLimit: relay-unwrapped inner envelopes were already counted
      // against the relay node's budget — counting them again would double-
      // charge the original sender.
      if (!skipRateLimit) {
        final packetSize = envelope.writeToBuffer().length;
        if (!rateLimiter.allowPacketHex(senderHex, packetSize)) {
          reputationManager.recordBad(senderHex, 'rate_limit_exceeded');
          return;
        }
      }

      // DoS Layer 3: Every accepted packet counts as positive reputation.
      // Infrastructure messages (DHT, DV, PeerList, Relay) return in the
      // switch-case below and never reach the application-level recordGood().
      // Without this, new peers doing normal bootstrap traffic can never
      // build goodActions → score stays 0.0 after first violation → score-
      // gate (Section 9.3) is ineffective.
      reputationManager.recordGood(senderHex);
    }

    // Decompress encryptedPayload if needed — node-level handlers (relay, S&F,
    // reachability) read encryptedPayload directly and need decompressed data.
    // V3.1.7 FIX: Skip decompression for KEM-encrypted messages. Their
    // compression field describes the PLAINTEXT (pre-encryption), not the
    // ciphertext. Decompressing ciphertext corrupts it → decrypt fails.
    // The service layer handles post-decryption decompression.
    final isKemEncrypted = envelope.hasKemHeader() &&
        envelope.kemHeader.ephemeralX25519Pk.isNotEmpty;
    if (envelope.compression == proto.CompressionType.ZSTD && isKemEncrypted) {
      _log.debug('Skip node-level decompress for KEM-encrypted ${envelope.messageType} '
          '(${envelope.encryptedPayload.length}B payload)');
    }
    if (!isKemEncrypted &&
        envelope.compression == proto.CompressionType.ZSTD &&
        envelope.encryptedPayload.isNotEmpty) {
      try {
        envelope.encryptedPayload = ZstdCompression.instance.decompress(
            Uint8List.fromList(envelope.encryptedPayload));
        envelope.compression = proto.CompressionType.NONE;
      } catch (_) {
        // Decompression failed — leave payload as-is for service layer to handle
      }
    }

    // Update routing table with sender info
    // DHT protocol messages are authoritative (direct from the peer)
    if (envelope.senderId.isNotEmpty) {
      final senderUserId = Uint8List.fromList(envelope.senderId);
      final senderUserHex = bytesToHex(senderUserId);
      // Phase 2: routing operations use deviceNodeId (per-device),
      // identity operations use userId (stable across devices).
      final routingId = _routingIdFromEnvelope(envelope);
      final routingHex = bytesToHex(routingId);
      _confirmedPeers.add(routingHex); // Mark device as actually reachable

      // DV-Routing: register neighbors (direct connection)
      if (from.address != '0.0.0.0') {
        final addr = PeerAddress(ip: from.address, port: fromPort);
        final ct = connectionTypeFromPriority(addr.priority);
        final isNewNeighbor = dvRouting.addDirectNeighbor(routingId, ct);

        if (isNewNeighbor) {
          _log.info('DV: New neighbor ${routingHex.substring(0, 8)} from ${from.address}:$fromPort (${ct.name})');
          // Prevent catch-up from firing on subsequent packets before welcome timer
          _lastRouteUpdateSentTo[routingHex] = DateTime.now();
          // Schedule welcome route update (after _touchPeer adds peer to routing table)
          Timer(const Duration(milliseconds: 500), () => _sendWelcomeRouteUpdate(routingHex));
        } else {
          // Catch-up: if we haven't sent a route update to this neighbor recently,
          // send one now — covers returning peers whose route never went DOWN.
          _maybeSendCatchUpRouteUpdate(routingHex);
        }

        // V3.1 Fix: Reset failure counters — direct packet proves reachability.
        final senderPeer = routingTable.getPeer(routingId);
        if (senderPeer != null) {
          if (senderPeer.consecutiveRouteFailures > 0) {
            _log.debug('Reset consecutiveRouteFailures for ${routingHex.substring(0, 8)} '
                '(direct packet received from ${from.address})');
            senderPeer.consecutiveRouteFailures = 0;
          }
          if (senderPeer.consecutiveRelayFailures > 0) {
            senderPeer.consecutiveRelayFailures = 0;
          }
        }

        // Public-IP-Trigger: if a peer with a public IP appears as neighbor
        // and we don't have a port mapping yet, start acquiring one.
        // UPnP discovers the IGD (Fritzbox) via SSDP unicast + tracepath
        // and queries it for the external IP — no external service needed.
        if (!PeerAddress.isPrivateIp(from.address) &&
            !natTraversal.hasPortMapping &&
            portMapper.state != PortMapperState.acquiring &&
            portMapper.state != PortMapperState.mapped) {
          _log.info('Public-IP peer detected (${from.address}) — starting port mapping');
          portMapper.start();
        }
      }

      // Track live UDP address for S&F push (keyed by userId — S&F is identity-level).
      final senderId = Uint8List.fromList(envelope.senderId);
      if (isUdp && from.address != '0.0.0.0' && fromPort > 0) {
        _lastLiveAddr[senderUserHex] = (from, fromPort);
      }

      // Push-based S&F: if we have stored messages for this peer, push them now
      // via the LIVE address we just received from (not routing table — may be stale).
      // Wrap in RELAY_FORWARD so receiver processes with from=0.0.0.0 and does NOT
      // register the original sender as a direct neighbor at our IP (V3.1.7 fix).
      //
      // Architecture (3.3.7): Messages persist until confirmed delivery (PEER_RETRIEVE)
      // or TTL expiry (7 days). peekMessages() reads without removing and rate-limits
      // pushes to once per 30 seconds per message to avoid flooding.
      if (from.address != '0.0.0.0' && fromPort > 0 && peerMessageStore.hasMessagesFor(senderId)) {
        final toPush = peerMessageStore.peekMessages(senderId);
        for (final envBytes in toPush) {
          try {
            final storedEnv = proto.MessageEnvelope.fromBuffer(envBytes);
            // Phase 2: prefer senderDeviceNodeId for relay origin (per-device routing)
            final originId = storedEnv.senderDeviceNodeId.isNotEmpty
                ? Uint8List.fromList(storedEnv.senderDeviceNodeId)
                : (storedEnv.senderId.isNotEmpty
                    ? Uint8List.fromList(storedEnv.senderId)
                    : primaryIdentity.deviceNodeId);
            final relay = proto.RelayForward()
              ..relayId = SodiumFFI().randomBytes(16)
              ..finalRecipientId = senderId
              ..wrappedEnvelope = envBytes
              ..hopCount = 1
              ..maxHops = 3
              ..ttl = 63
              ..originNodeId = originId
              ..createdAtMs = Int64(DateTime.now().millisecondsSinceEpoch);
            relay.visitedNodes.add(primaryIdentity.deviceNodeId);
            final relayEnv = primaryIdentity.createSignedEnvelope(
              proto.MessageType.RELAY_FORWARD,
              relay.writeToBuffer(),
            );
            transport.sendUdp(relayEnv, from, fromPort);
          } catch (_) {}
        }
        if (toPush.isNotEmpty) {
          _log.info('S&F push: sent ${toPush.length} stored messages (RELAY_FORWARD) to ${senderUserHex.substring(0, 8)} at ${from.address}:$fromPort');
        }
      }

      final isDhtDirect = type == proto.MessageType.DHT_PING ||
          type == proto.MessageType.DHT_PONG ||
          type == proto.MessageType.DHT_FIND_NODE ||
          type == proto.MessageType.DHT_FIND_NODE_RESPONSE;
      // Phase 2: _touchPeer uses routingId (deviceNodeId) so the routing table
      // entry is per-device, with userId attached for identity lookups.
      _touchPeer(routingId, from.address, fromPort,
          isAuthoritative: isDhtDirect, userId: senderUserId);
    }

    // Handle DHT protocol messages internally
    switch (type) {
      case proto.MessageType.DHT_PING:
        _handlePing(envelope, from, fromPort);
        return;
      case proto.MessageType.DHT_PONG:
        _handlePong(envelope, from, fromPort);
        return;
      case proto.MessageType.DHT_FIND_NODE:
        _handleFindNode(envelope, from, fromPort);
        return;
      case proto.MessageType.DHT_FIND_NODE_RESPONSE:
      case proto.MessageType.DHT_STORE_RESPONSE:
      case proto.MessageType.DHT_FIND_VALUE_RESPONSE:
      case proto.MessageType.FRAGMENT_STORE_ACK:
        dhtRpc.handleResponse(envelope, from.address, fromPort);
        return;
      case proto.MessageType.PEER_LIST_SUMMARY:
        _handlePeerListSummary(envelope, from, fromPort);
        return;
      case proto.MessageType.PEER_LIST_WANT:
        _handlePeerListWant(envelope, from, fromPort);
        return;
      case proto.MessageType.PEER_LIST_PUSH:
        _handlePeerListPush(envelope, from, fromPort);
        return;
      case proto.MessageType.RELAY_FORWARD:
        _handleRelayForward(envelope, from, fromPort);
        return;
      case proto.MessageType.RELAY_ACK:
        _handleRelayAck(envelope);
        return;
      case proto.MessageType.REACHABILITY_QUERY:
        _handleReachabilityQuery(envelope, from, fromPort);
        return;
      case proto.MessageType.REACHABILITY_RESPONSE:
        reachabilityProbe.handleResponse(envelope);
        return;
      case proto.MessageType.PEER_STORE:
        _handlePeerStore(envelope, from, fromPort);
        return;
      case proto.MessageType.PEER_STORE_ACK:
        _log.debug('PEER_STORE_ACK received from ${from.address}');
        return;
      case proto.MessageType.PEER_RETRIEVE:
        _handlePeerRetrieve(envelope, from, fromPort);
        return;
      case proto.MessageType.PEER_RETRIEVE_RESPONSE:
        _handlePeerRetrieveResponse(envelope);
        return;
      case proto.MessageType.ROUTE_UPDATE:
        _handleRouteUpdate(envelope);
        return;
      case proto.MessageType.HOLE_PUNCH_REQUEST:
        natTraversal.handleHolePunchRequest(envelope);
        return;
      case proto.MessageType.HOLE_PUNCH_NOTIFY:
        natTraversal.handleHolePunchNotify(envelope);
        return;
      case proto.MessageType.HOLE_PUNCH_PING:
        natTraversal.handleHolePunchPing(envelope, from, fromPort);
        return;
      case proto.MessageType.HOLE_PUNCH_PONG:
        natTraversal.handleHolePunchPong(envelope, from, fromPort);
        return;
      case proto.MessageType.MEDIA_CHUNK:
        _handleMediaChunk(envelope, from, fromPort);
        return;
      default:
        break;
    }

    // Verify Proof of Work on application messages (mandatory for chat messages)
    // Infrastructure, group/channel management, and LAN peers are exempt —
    // authenticated via per-message KEM + Ed25519 signature.
    final powExempt = type == proto.MessageType.FRAGMENT_STORE ||
        type == proto.MessageType.FRAGMENT_RETRIEVE ||
        type == proto.MessageType.FRAGMENT_DELETE ||
        type == proto.MessageType.CONTACT_REQUEST ||
        type == proto.MessageType.CONTACT_REQUEST_RESPONSE ||
        type == proto.MessageType.TYPING_INDICATOR ||
        type == proto.MessageType.READ_RECEIPT ||
        type == proto.MessageType.DELIVERY_RECEIPT ||
        type == proto.MessageType.GROUP_INVITE ||
        type == proto.MessageType.GROUP_LEAVE ||
        type == proto.MessageType.CHANNEL_INVITE ||
        type == proto.MessageType.CHANNEL_LEAVE ||
        type == proto.MessageType.CHANNEL_ROLE_UPDATE ||
        type == proto.MessageType.CHAT_CONFIG_UPDATE ||
        type == proto.MessageType.KEY_ROTATION_BROADCAST ||
        type == proto.MessageType.PROFILE_UPDATE ||
        type == proto.MessageType.RESTORE_BROADCAST ||
        type == proto.MessageType.CHANNEL_JOIN_REQUEST ||
        type == proto.MessageType.CHANNEL_INDEX_EXCHANGE ||
        type == proto.MessageType.CHANNEL_REPORT ||
        type == proto.MessageType.JURY_REQUEST ||
        type == proto.MessageType.JURY_VOTE_MSG ||
        type == proto.MessageType.JURY_RESULT ||
        type == proto.MessageType.RELAY_FORWARD ||
        type == proto.MessageType.RELAY_ACK ||
        type == proto.MessageType.REACHABILITY_QUERY ||
        type == proto.MessageType.REACHABILITY_RESPONSE ||
        type == proto.MessageType.PEER_STORE ||
        type == proto.MessageType.PEER_STORE_ACK ||
        type == proto.MessageType.PEER_RETRIEVE ||
        type == proto.MessageType.PEER_RETRIEVE_RESPONSE ||
        type == proto.MessageType.ROUTE_UPDATE ||
        type == proto.MessageType.HOLE_PUNCH_REQUEST ||
        type == proto.MessageType.HOLE_PUNCH_NOTIFY ||
        type == proto.MessageType.HOLE_PUNCH_PING ||
        type == proto.MessageType.HOLE_PUNCH_PONG ||
        type == proto.MessageType.MEDIA_CHUNK || // Relay chunking transport
        type == proto.MessageType.CALL_AUDIO || // Real-time audio frames
        type == proto.MessageType.CALL_VIDEO || // Real-time video frames
        type == proto.MessageType.CALL_KEYFRAME_REQUEST || // Video keyframe request
        type == proto.MessageType.CALL_GROUP_AUDIO || // Real-time group audio
        type == proto.MessageType.CALL_GROUP_VIDEO || // Real-time group video
        type == proto.MessageType.CALL_GROUP_LEAVE ||
        type == proto.MessageType.CALL_GROUP_KEY_ROTATE ||
        type == proto.MessageType.CALL_RTT_PING ||
        type == proto.MessageType.CALL_RTT_PONG ||
        type == proto.MessageType.CALL_TREE_UPDATE ||
        type == proto.MessageType.CALL_REJOIN ||
        _isPrivateIp(from.address) || // LAN peers exempt
        from.address == '0.0.0.0'; // Relay-delivered (already validated by RelayBudget)
    if (!powExempt) {
      final powSenderHex = envelope.senderId.isNotEmpty
          ? bytesToHex(Uint8List.fromList(envelope.senderId))
          : '';
      if (!envelope.hasPow() || envelope.pow.difficulty < ProofOfWork.minAcceptedDifficulty) {
        _log.info('Rejected message without valid PoW from ${from.address}:$fromPort (type: $type)');
        if (powSenderHex.isNotEmpty) {
          reputationManager.recordBad(powSenderHex, 'missing_or_insufficient_pow');
        }
        return;
      }
      final stripped = envelope.clone()..clearPow();
      final signedData = stripped.writeToBuffer();
      if (!ProofOfWork.verify(signedData, envelope.pow)) {
        _log.info('PoW verification failed from ${from.address}:$fromPort');
        if (powSenderHex.isNotEmpty) {
          reputationManager.recordBad(powSenderHex, 'invalid_pow');
        }
        return;
      }
    }

    // Message-level dedup: skip if we've already processed this messageId.
    // Infrastructure messages (DHT, RELAY, etc.) are handled above and never reach here.
    final msgIdHex = envelope.messageId.isNotEmpty
        ? bytesToHex(Uint8List.fromList(envelope.messageId))
        : '';
    if (msgIdHex.isNotEmpty) {
      if (_seenMessageIds.contains(msgIdHex)) {
        _log.debug('Dedup: skipping duplicate messageId ${msgIdHex.substring(0, 8)} type=$type');
        return;
      }
      _seenMessageIds.add(msgIdHex);
      if (_seenMessageIds.length > _maxSeenMessages) {
        _seenMessageIds.remove(_seenMessageIds.first);
      }
    }
    _log.info('→ Service: type=$type msgId=${msgIdHex.isNotEmpty ? msgIdHex.substring(0, 8) : "empty"} from=${from.address}');

    // Route to the correct identity based on recipientId
    IdentityContext? targetIdentity;
    if (envelope.recipientId.isNotEmpty) {
      final recipientHex = bytesToHex(Uint8List.fromList(envelope.recipientId));
      // Phase 2: try userId first, then deviceNodeId fallback
      targetIdentity = _identities[recipientHex] ??
          _identitiesByDeviceId[recipientHex];
    }

    // RUDP Light: intercept DELIVERY_RECEIPT as ACK at node level.
    // Still forwarded to service layer for UI status update.
    if (type == proto.MessageType.DELIVERY_RECEIPT) {
      try {
        final receipt = proto.DeliveryReceipt.fromBuffer(envelope.encryptedPayload);
        final msgIdHex = bytesToHex(Uint8List.fromList(receipt.messageId));
        // Phase 2: ackTracker keys must match _trackAck (which uses peer.nodeIdHex = deviceNodeId)
        final ackRoutingId = _routingIdFromEnvelope(envelope);
        final ackRoutingHex = bytesToHex(ackRoutingId);
        ackTracker.handleAck(msgIdHex, ackRoutingHex);
        // Remove from send queue if present (message delivered)
        messageQueue.remove(msgIdHex);
        // Confirm DV route — only for DIRECT-delivered receipts.
        // Relay-delivered (from=0.0.0.0) proves end-to-end reachability but NOT
        // that the direct UDP path works. Confirming relay-delivered receipts
        // causes sendEnvelope to skip the relay cascade (directProven=true),
        // sending to a stale NAT address that drops packets silently.
        if (from.address != '0.0.0.0') {
          dvRouting.confirmRoute(ackRoutingHex);
        }
        // Confirm relay neighbor: we received an ACK,
        // so the direct sender is a reliable relay partner.
        if (from.address != '0.0.0.0' && !_isLocalIdentity(ackRoutingHex)) {
          dvRouting.confirmRelayNeighbor(ackRoutingHex);
        }
        // V3.1 Fix: Reset failure counters for sender —
        // DELIVERY_RECEIPT proves end-to-end reachability (at least via relay).
        final ackPeer = routingTable.getPeer(ackRoutingId);
        if (ackPeer != null) {
          if (ackPeer.consecutiveRouteFailures > 0) {
            _log.debug('Reset consecutiveRouteFailures for ${ackRoutingHex.substring(0, 8)} '
                '(DELIVERY_RECEIPT received)');
            ackPeer.consecutiveRouteFailures = 0;
          }
          if (ackPeer.consecutiveRelayFailures > 0) {
            ackPeer.consecutiveRelayFailures = 0;
          }
        }
      } catch (_) {}
    }

    // Forward to application layer with identity context
    if (type == proto.MessageType.CONTACT_REQUEST || type == proto.MessageType.CONTACT_REQUEST_RESPONSE) {
      final sHex = bytesToHex(Uint8List.fromList(envelope.senderId));
      final rHex = envelope.recipientId.isNotEmpty ? bytesToHex(Uint8List.fromList(envelope.recipientId)) : 'empty';
      _log.info('Forwarding $type from ${sHex.substring(0, 8)} to service '
          '(recipientId=${rHex.substring(0, 8)}, identity=${targetIdentity?.nodeIdHex.substring(0, 8) ?? "null"})');
    }
    onMessageForIdentity?.call(envelope, from, fromPort, targetIdentity);
  }

  void _onDiscoveryReceived(Uint8List peerId, int peerPort, InternetAddress from, int fromPort) {
    _log.debug('Discovery: ${bytesToHex(peerId).substring(0, 8)}.. at ${from.address}:$peerPort');
    // V3.1 Fix: LAN discovery proves direct reachability — reset failure counters.
    final discoveredPeer = routingTable.getPeer(peerId);
    if (discoveredPeer != null) {
      if (discoveredPeer.consecutiveRouteFailures > 0) {
        _log.debug('Reset consecutiveRouteFailures for ${bytesToHex(peerId).substring(0, 8)} '
            '(LAN discovery from ${from.address})');
        discoveredPeer.consecutiveRouteFailures = 0;
      }
      if (discoveredPeer.consecutiveRelayFailures > 0) {
        discoveredPeer.consecutiveRelayFailures = 0;
      }
    }
    _touchPeer(peerId, from.address, peerPort, isAuthoritative: true);

    // Send PING to discovered peer
    _sendPing(from.address, peerPort);
  }

  void _onPeerDiscovered(Uint8List peerId, int peerPort, InternetAddress from, int fromPort) {
    _onDiscoveryReceived(peerId, peerPort, from, fromPort);
  }

  /// Update or create a peer entry in the routing table.
  /// [peerId] is the deviceNodeId (per-device routing key).
  /// [userId] is the stable identity (optional, attached to PeerInfo for lookups).
  void _touchPeer(Uint8List peerId, String ip, int port,
      {bool isAuthoritative = false, Uint8List? userId}) {
    final existing = routingTable.getPeer(peerId);
    if (existing != null) {
      existing.lastSeen = DateTime.now();
      // Phase 2: update userId if newly learned. Go through the routing
      // table so the secondary userId→peers index stays consistent —
      // otherwise the freshly-learned userId is invisible to O(1) lookups.
      if (userId != null && existing.userId == null) {
        routingTable.setPeerUserId(existing, userId);
      }
      if (ip.isNotEmpty && ip != '0.0.0.0' && ip != '::' && isAuthoritative) {
        // Legacy fields: only for IPv4 (publicIp/localIp are IPv4 NAT concepts)
        if (!ip.contains(':')) {
          if (_isPrivateIp(ip)) {
            existing.localIp = ip;
            existing.localPort = port;
          } else {
            existing.publicIp = ip;
            existing.publicPort = port;
          }
        }
        // Accumulate in multi-address list (all address types incl. IPv6).
        // Dedup by ip:port — add if new, reset backoff if known.
        final addrKey = '$ip:$port';
        final known = existing.addresses.any((a) => '${a.ip}:${a.port}' == addrKey);
        if (!known) {
          existing.addresses.add(PeerAddress(
            ip: ip,
            port: port,
            type: _classifyAddressType(ip),
          ));
        } else {
          for (final addr in existing.addresses) {
            if (addr.ip == ip && addr.port == port && addr.consecutiveFailures > 0) {
              addr.consecutiveFailures = 0;
            }
          }
        }
      }
      routingTable.addPeer(existing);
    } else {
      final peer = PeerInfo(
        nodeId: peerId,
        userId: userId,
        networkChannel: networkChannel,
      );
      // Same guard as UPDATE branch — relay-delivered messages have
      // from=0.0.0.0 / :: which must NOT be stored as an address.
      if (ip.isNotEmpty && ip != '0.0.0.0' && ip != '::') {
        // Legacy fields: only for IPv4
        if (!ip.contains(':')) {
          if (_isPrivateIp(ip)) {
            peer.localIp = ip;
            peer.localPort = port;
          } else {
            peer.publicIp = ip;
            peer.publicPort = port;
          }
        }
        peer.addresses.add(PeerAddress(
          ip: ip,
          port: port,
          type: _classifyAddressType(ip),
        ));
      }
      routingTable.addPeer(peer);
    }
  }

  // ── DHT Protocol Handlers ──────────────────────────────────────────

  void _handlePing(proto.MessageEnvelope envelope, InternetAddress from, int fromPort) {
    // Respond with PONG including observed address + all secondary identities
    final pong = _createEnvelope(proto.MessageType.DHT_PONG);
    final pongData = proto.DhtPong()
      ..senderId = primaryIdentity.nodeId
      ..timestamp = Int64(DateTime.now().millisecondsSinceEpoch)
      ..observedIp = from.address
      ..observedPort = fromPort;
    // Announce secondary identities so peers can route to them.
    // Phase 2: send deviceNodeId (per-device routing key for DV neighbor registration)
    for (final ctx in _identities.values) {
      if (ctx.nodeIdHex != primaryIdentity.nodeIdHex) {
        pongData.additionalNodeIds.add(ctx.deviceNodeId);
      }
    }
    pong.encryptedPayload = pongData.writeToBuffer();
    pong.recipientId = envelope.senderId;
    if (from.address != '0.0.0.0') {
      transport.sendUdp(pong, from, fromPort);
    } else {
      sendEnvelope(pong, Uint8List.fromList(envelope.senderId));
    }
  }

  void _handlePong(proto.MessageEnvelope envelope, InternetAddress from, int fromPort) {
    try {
      final pongData = proto.DhtPong.fromBuffer(envelope.encryptedPayload);
      // Use observed address for NAT traversal
      if (pongData.observedIp.isNotEmpty) {
        final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
        natTraversal.addObservation(senderHex, pongData.observedIp, pongData.observedPort);
      }
      // Register secondary identities at the same address as the primary
      // They share the same transport, so they need DV neighbor status too —
      // otherwise messages to secondary identities have no DV route.
      for (final additionalId in pongData.additionalNodeIds) {
        final addId = Uint8List.fromList(additionalId);
        final addHex = bytesToHex(addId);
        _touchPeer(addId, from.address, fromPort, isAuthoritative: true);
        _confirmedPeers.add(addHex);
        if (from.address != '0.0.0.0') {
          final addr = PeerAddress(ip: from.address, port: fromPort);
          final ct = connectionTypeFromPriority(addr.priority);
          final isNew = dvRouting.addDirectNeighbor(addId, ct);
          if (isNew) {
            _log.info('DV: New neighbor (secondary) ${addHex.substring(0, 8)} from ${from.address}:$fromPort (${ct.name})');
            _lastRouteUpdateSentTo[addHex] = DateTime.now();
            Timer(const Duration(milliseconds: 500), () => _sendWelcomeRouteUpdate(addHex));
          }
        }
      }

      // CGNAT gateway keepalive: when we're behind carrier NAT and receive
      // a PONG from a public-IP peer, register it for NAT-Timeout-Probing.
      // This keeps the carrier NAT pinhole alive without a coordinated Hole Punch.
      if (_isBehindCgnat() && !_isPrivateIp(from.address)) {
        final senderNodeId = Uint8List.fromList(envelope.senderId);
        natTraversal.registerGatewayConnection(senderNodeId, from.address, fromPort);
      }

      // Match to pending RPC
      dhtRpc.handleResponse(envelope, from.address, fromPort);
    } catch (e) {
      _log.debug('PONG parse error: $e');
    }
  }

  /// Detect CGNAT: 100.64.0.0/10 or 192.0.0.0/29 (DS-Lite).
  bool _isBehindCgnat() {
    return _localIps.any((ip) =>
        (ip.startsWith('100.') && _isCgnatRange(ip)) ||
        ip.startsWith('192.0.0.'));
  }

  bool _isCgnatRange(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final b1 = int.tryParse(parts[0]) ?? 0;
    final b2 = int.tryParse(parts[1]) ?? 0;
    return b1 == 100 && b2 >= 64 && b2 <= 127;
  }

  void _handleFindNode(proto.MessageEnvelope envelope, InternetAddress from, int fromPort) {
    try {
      final findData = proto.DhtFindNode.fromBuffer(envelope.encryptedPayload);
      final targetId = Uint8List.fromList(findData.targetId);
      final closest = routingTable.findClosestPeers(targetId, count: kBucketSize);

      final response = _createEnvelope(proto.MessageType.DHT_FIND_NODE_RESPONSE);
      final respData = proto.DhtFindNodeResponse();
      for (final peer in closest) {
        respData.closestPeers.add(peer.toProto());
      }
      response.encryptedPayload = respData.writeToBuffer();
      response.recipientId = envelope.senderId;
      if (from.address != '0.0.0.0') {
        transport.sendUdp(response, from, fromPort);
      } else {
        sendEnvelope(response, Uint8List.fromList(envelope.senderId));
      }
    } catch (e) {
      _log.debug('FIND_NODE error: $e');
    }
  }

  // ── Peer List Exchange (3-step delta) ──────────────────────────────

  void _handlePeerListSummary(proto.MessageEnvelope envelope, InternetAddress from, int fromPort) {
    try {
      final summary = proto.PeerListSummary.fromBuffer(envelope.encryptedPayload);
      final theirEntries = <String, int>{};
      for (final entry in summary.entries) {
        theirEntries[bytesToHex(Uint8List.fromList(entry.nodeId))] = entry.lastSeen.toInt();
      }

      // Find peers we have that they need (newer or missing)
      final wantedByThem = <Uint8List>[];
      for (final peer in routingTable.allPeers) {
        final hex = peer.nodeIdHex;
        final theirTs = theirEntries[hex];
        if (theirTs == null || peer.lastSeen.millisecondsSinceEpoch > theirTs) {
          wantedByThem.add(peer.nodeId);
        }
      }

      // Find peers they have that we want
      final wanted = <Uint8List>[];
      final ourPeerIds = routingTable.allPeers.map((p) => p.nodeIdHex).toSet();
      for (final entry in summary.entries) {
        final hex = bytesToHex(Uint8List.fromList(entry.nodeId));
        if (!ourPeerIds.contains(hex)) {
          wanted.add(Uint8List.fromList(entry.nodeId));
        }
      }

      // Send WANT for peers we need
      if (wanted.isNotEmpty) {
        final wantMsg = _createEnvelope(proto.MessageType.PEER_LIST_WANT);
        final wantData = proto.PeerListWant();
        for (final id in wanted) {
          wantData.wantedNodeIds.add(id);
        }
        wantMsg.encryptedPayload = wantData.writeToBuffer();
        wantMsg.recipientId = envelope.senderId;
        if (from.address != '0.0.0.0') {
          transport.sendUdp(wantMsg, from, fromPort);
        } else {
          sendEnvelope(wantMsg, Uint8List.fromList(envelope.senderId));
        }
      }

      // Push peers they need
      if (wantedByThem.isNotEmpty) {
        final pushMsg = _createEnvelope(proto.MessageType.PEER_LIST_PUSH);
        final pushData = proto.PeerListPush();
        for (final id in wantedByThem.take(50)) { // Limit to 50
          final peer = routingTable.getPeer(id);
          if (peer != null) {
            pushData.peers.add(peer.toProto());
          }
        }
        pushMsg.encryptedPayload = pushData.writeToBuffer();
        pushMsg.recipientId = envelope.senderId;
        if (from.address != '0.0.0.0') {
          transport.sendUdp(pushMsg, from, fromPort);
        } else {
          sendEnvelope(pushMsg, Uint8List.fromList(envelope.senderId));
        }
      }
    } catch (e) {
      _log.debug('PeerListSummary error: $e');
    }
  }

  void _handlePeerListWant(proto.MessageEnvelope envelope, InternetAddress from, int fromPort) {
    try {
      final want = proto.PeerListWant.fromBuffer(envelope.encryptedPayload);
      final pushMsg = _createEnvelope(proto.MessageType.PEER_LIST_PUSH);
      final pushData = proto.PeerListPush();

      for (final wantedId in want.wantedNodeIds) {
        final peer = routingTable.getPeer(Uint8List.fromList(wantedId));
        if (peer != null) {
          pushData.peers.add(peer.toProto());
        }
      }

      pushMsg.encryptedPayload = pushData.writeToBuffer();
      pushMsg.recipientId = envelope.senderId;
      if (from.address != '0.0.0.0') {
        transport.sendUdp(pushMsg, from, fromPort);
      } else {
        sendEnvelope(pushMsg, Uint8List.fromList(envelope.senderId));
      }
    } catch (e) {
      _log.debug('PeerListWant error: $e');
    }
  }

  void _handlePeerListPush(proto.MessageEnvelope envelope, InternetAddress from, int fromPort) {
    try {
      final push = proto.PeerListPush.fromBuffer(envelope.encryptedPayload);
      for (final peerProto in push.peers) {
        final peer = PeerInfo.fromProto(peerProto);
        if (peer.networkChannel.isNotEmpty && peer.networkChannel != networkChannel) continue;
        routingTable.addPeer(peer);
      }
      _log.debug('PeerListPush: received ${push.peers.length} peers from ${from.address}');
      onPeersChanged?.call();
    } catch (e) {
      _log.debug('PeerListPush error: $e');
    }
  }

  // ── Kademlia Bootstrap ─────────────────────────────────────────────

  Future<void> _kademliaBootstrap() async {
    _log.info('Starting Kademlia bootstrap...');
    final peers = routingTable.allPeers;
    if (peers.isEmpty) {
      _log.info('No peers for bootstrap');
      return;
    }

    // Send FIND_NODE for our own ID to all known peers
    for (final peer in peers.take(10)) {
      try {
        await _sendFindNode(peer, primaryIdentity.deviceNodeId);
      } catch (_) {}
    }

    _log.info('Kademlia bootstrap done. Peers: ${routingTable.peerCount}');
  }

  Future<List<PeerInfo>> _sendFindNode(PeerInfo peer, Uint8List targetId) async {
    final envelope = _createEnvelope(proto.MessageType.DHT_FIND_NODE);
    final findData = proto.DhtFindNode()
      ..targetId = targetId
      ..senderId = primaryIdentity.nodeId;
    envelope.encryptedPayload = findData.writeToBuffer();
    envelope.recipientId = peer.nodeId;

    final response = await dhtRpc.sendAndWait(envelope, peer);
    if (response == null) return [];

    try {
      final respData = proto.DhtFindNodeResponse.fromBuffer(response.encryptedPayload);
      final result = <PeerInfo>[];
      for (final p in respData.closestPeers) {
        final info = PeerInfo.fromProto(p);
        if (info.networkChannel.isNotEmpty && info.networkChannel != networkChannel) continue;
        routingTable.addPeer(info);
        result.add(info);
        // Probe newly learned peers (standard Kademlia behavior).
        // Without this, peers learned via FIND_NODE_RESPONSE never get confirmed
        // because no bidirectional communication is established.
        for (final addr in info.allConnectionTargets().take(2)) {
          _sendPing(addr.ip, addr.port);
        }
      }
      return result;
    } catch (e) {
      return [];
    }
  }

  /// Public ping — used by service layer (e.g. QR seed peer bootstrap).
  void sendPing(String ip, int port) => _sendPing(ip, port);

  Future<void> _sendPing(String ip, int port) async {
    final envelope = _createEnvelope(proto.MessageType.DHT_PING);
    final pingData = proto.DhtPing()
      ..senderId = primaryIdentity.nodeId
      ..timestamp = Int64(DateTime.now().millisecondsSinceEpoch);
    envelope.encryptedPayload = pingData.writeToBuffer();

    try {
      final addr = InternetAddress(ip);
      await transport.sendUdp(envelope, addr, port);
    } catch (_) {}
  }

  // ── Envelope Creation ──────────────────────────────────────────────

  proto.MessageEnvelope _createEnvelope(proto.MessageType type) {
    return proto.MessageEnvelope()
      ..version = 1
      ..senderId = primaryIdentity.nodeId          // userId (stable identity)
      ..senderDeviceNodeId = primaryIdentity.deviceNodeId  // Phase 2: per-device routing
      ..timestamp = Int64(DateTime.now().millisecondsSinceEpoch)
      ..messageType = type
      ..networkTag = networkChannel;
  }

  /// Extract the device-specific routing ID from an envelope.
  /// Phase 2: uses senderDeviceNodeId if available, falls back to senderId
  /// for backward compatibility with pre-Phase-2 peers.
  Uint8List _routingIdFromEnvelope(proto.MessageEnvelope envelope) {
    if (envelope.senderDeviceNodeId.isNotEmpty) {
      return Uint8List.fromList(envelope.senderDeviceNodeId);
    }
    return Uint8List.fromList(envelope.senderId);
  }

  /// Check if a hex ID belongs to any registered local identity
  /// (checks both userId and deviceNodeId).
  bool _isLocalIdentity(String hex) {
    return _identities.containsKey(hex) || _identitiesByDeviceId.containsKey(hex);
  }

  /// Filter targets by NAT context: private IPs are only meaningful when our
  /// public IP matches the peer's public IP (same NAT). Without this check,
  /// 192.168.15.15 behind NAT-A gets sent to a device behind NAT-B — wasted traffic.
  List<PeerAddress> _filterNatContext(List<PeerAddress> targets, PeerInfo peer) {
    final myPublicIp = natTraversal.publicIpForNatContext;
    // If our "public" IP is actually a private IP (NAT module misdetection),
    // treat as unknown — don't block private targets based on bad data.
    final effectivePublicIp = (myPublicIp != null && _isPrivateIp(myPublicIp)) ? null : myPublicIp;
    return targets.where((addr) {
      // IPv6 global: no NAT context needed — always routable
      if (addr.ip.contains(':') && !addr.ip.toLowerCase().startsWith('fe80:')) return true;
      if (!_isPrivateIp(addr.ip)) return true;
      // Private IP: only try if same NAT (matching public IP) or unknown
      return effectivePublicIp == null || effectivePublicIp == peer.publicIp || peer.publicIp.isEmpty;
    }).toList();
  }

  /// Send an envelope to a peer (used by DhtRpc and relay forwarding).
  /// V3.1.7: Large payloads (>1200 bytes) use TLS (TCP, reliable, no fragmentation).
  /// Small payloads use UDP (fast, single packet).
  Future<bool> _sendEnvelopeToPeer(proto.MessageEnvelope envelope, PeerInfo peer) async {
    final targets = peer.allConnectionTargets();
    if (targets.isEmpty) return false;

    // Check for punched connection — prefer it over regular addresses
    final peerHex = peer.nodeIdHex;
    final punched = natTraversal.getPunchedConnection(peerHex);
    if (punched != null) {
      try {
        final ok = await transport.sendUdp(
          envelope,
          InternetAddress(punched.peerIp),
          punched.peerPort,
        );
        if (ok) return true;
      } catch (_) {}
    }

    // Filter unreachable private IPs + NAT context (V3.1.32).
    // Private IPs only meaningful if we share the same NAT (public IP match).
    final natFiltered = _filterNatContext(targets, peer);
    var reachable = natFiltered.where((addr) => addr.isReachableFromCurrentNetwork).toList();
    if (reachable.isEmpty) {
      // All targets heuristically unreachable — try NAT-filtered targets anyway
      // (DNAT/port-forwarding can make private IPs reachable from same NAT).
      reachable = natFiltered;
    }
    if (reachable.isEmpty) {
      _log.debug('_sendEnvelopeToPeer: no reachable targets for ${peerHex.substring(0, 8)} '
          '(${targets.length} total, all filtered by NAT context or reachability)');
      return false;
    }

    // V3.1.7: Protocol escalation — lightest first, escalate on failure.
    // UDP (with NACK-retry for fragments) → TLS (TCP, last resort).
    // TlsFallbackManager tracks per-peer: 15 UDP failures → TLS mode.
    final dataSize = envelope.writeToBuffer().length;
    final isLargePayload = dataSize > maxFragmentPacketSize;

    // If in TLS mode for this peer, skip UDP and go straight to TLS
    if (isLargePayload && _tlsFallback.isInTlsMode(peerHex)) {
      for (final addr in reachable) {
        try {
          final ok = await transport.sendTls(envelope, InternetAddress(addr.ip), addr.port);
          if (ok) {
            _log.debug('_sendEnvelopeToPeer: TLS sent ${dataSize}B to ${peerHex.substring(0, 8)} at ${addr.ip}:${addr.port}');
            _tlsFallback.recordTlsSuccess(peerHex);
            return true;
          }
        } catch (_) {}
      }
      return false;
    }

    // V3: Prioritized delivery — best address first, escalate on failure.
    // Architecture Section 2.4.3: "V3 replaces shotgun to all addresses
    // with route-based prioritized delivery."
    // Addresses are already sorted by priority (LAN > private > public).
    for (final addr in reachable) {
      try {
        final ok = await transport.sendUdp(envelope, InternetAddress(addr.ip), addr.port);
        if (ok) return true;
      } catch (_) {}
    }

    // UDP failed on all addresses — escalate to TLS for large payloads
    if (isLargePayload) {
      for (final addr in reachable) {
        try {
          final ok = await transport.sendTls(envelope, InternetAddress(addr.ip), addr.port);
          if (ok) {
            _log.debug('_sendEnvelopeToPeer: UDP→TLS escalation ${dataSize}B to '
                '${peerHex.substring(0, 8)} at ${addr.ip}:${addr.port}');
            return true;
          }
        } catch (_) {}
      }
    }

    _log.debug('_sendEnvelopeToPeer: all sends failed for '
        '${peerHex.substring(0, 8)} (targets: ${reachable.map((a) => "${a.ip}:${a.port}").join(", ")})');
    return false;
  }

  /// V3.1: Public relay send — for "reply via same path" (DELIVERY_RECEIPT via relay).
  Future<bool> sendViaRelay(proto.MessageEnvelope envelope, Uint8List recipientNodeId) =>
      _sendViaRelay(envelope, recipientNodeId);

  /// V3.1: Public DV next-hop send — for "reply via same path".
  Future<bool> sendViaNextHopPublic(proto.MessageEnvelope envelope, Uint8List recipientNodeId, PeerInfo nextHopPeer) =>
      _sendViaNextHop(envelope, recipientNodeId, nextHopPeer);

  /// Send an envelope to a specific peer by node ID.
  /// V3: Route-based — DV Cheapest Route → Fallback → Default-Gateway → Legacy Relay → S&F
  /// Route-based, UDP only. Direct → Relay → S&F cascade.
  Future<bool> sendEnvelope(proto.MessageEnvelope envelope, Uint8List recipientNodeId) async {
    // Phase 2: try deviceNodeId first, then userId fallback (callers may pass either)
    final peer = routingTable.getPeer(recipientNodeId) ??
        routingTable.getPeerByUserId(recipientNodeId);
    if (peer == null) {
      // Peer not in Kademlia routing table. Don't give up — try relay via
      // DV routing (default gateway or next-hop) which may know this peer.
      final recipientHex = bytesToHex(recipientNodeId);
      _log.debug('Peer ${recipientHex.substring(0, 8)} not in k-table, trying DV relay');

      final type = envelope.messageType;
      final isRelayable = type != proto.MessageType.RELAY_FORWARD &&
          type != proto.MessageType.RELAY_ACK &&
          type != proto.MessageType.TYPING_INDICATOR &&
          type != proto.MessageType.READ_RECEIPT;

      if (isRelayable) {
        // Try default gateway
        final gwHex = dvRouting.defaultGatewayHex;
        if (gwHex != null && gwHex != recipientHex && !_isLocalIdentity(gwHex)) {
          final gwPeer = routingTable.getPeer(hexToBytes(gwHex));
          if (gwPeer != null) {
            _log.debug('Sending via default-GW ${gwHex.substring(0, 8)} for unreachable ${recipientHex.substring(0, 8)}');
            return _sendViaNextHop(envelope, recipientNodeId, gwPeer);
          }
        }
      }

      _log.debug('Cannot send: peer ${recipientHex.substring(0, 8)} not in routing table or DV');
      // Queue ack-worthy messages for later delivery when route appears
      if (AckTracker.isAckWorthy(type) && envelope.messageId.isNotEmpty) {
        final msgIdHex = bytesToHex(Uint8List.fromList(envelope.messageId));
        messageQueue.enqueue(
          messageIdHex: msgIdHex,
          recipientNodeId: recipientNodeId,
          serializedEnvelope: envelope.writeToBuffer(),
        );
      }
      return false;
    }

    final peerHex = peer.nodeIdHex;
    final targets = peer.allConnectionTargets();

    // Compute PoW only for non-infrastructure messages to non-LAN peers.
    final type = envelope.messageType;
    final isInfrastructure = type == proto.MessageType.FRAGMENT_STORE ||
        type == proto.MessageType.FRAGMENT_RETRIEVE ||
        type == proto.MessageType.FRAGMENT_DELETE ||
        type == proto.MessageType.CONTACT_REQUEST ||
        type == proto.MessageType.CONTACT_REQUEST_RESPONSE ||
        type == proto.MessageType.TYPING_INDICATOR ||
        type == proto.MessageType.READ_RECEIPT ||
        type == proto.MessageType.DELIVERY_RECEIPT ||
        type == proto.MessageType.GROUP_INVITE ||
        type == proto.MessageType.GROUP_LEAVE ||
        type == proto.MessageType.CHANNEL_INVITE ||
        type == proto.MessageType.CHANNEL_LEAVE ||
        type == proto.MessageType.CHANNEL_ROLE_UPDATE ||
        type == proto.MessageType.CHAT_CONFIG_UPDATE ||
        type == proto.MessageType.KEY_ROTATION_BROADCAST ||
        type == proto.MessageType.PROFILE_UPDATE ||
        type == proto.MessageType.RESTORE_BROADCAST ||
        type == proto.MessageType.RELAY_FORWARD ||
        type == proto.MessageType.RELAY_ACK ||
        type == proto.MessageType.REACHABILITY_QUERY ||
        type == proto.MessageType.REACHABILITY_RESPONSE ||
        type == proto.MessageType.PEER_STORE ||
        type == proto.MessageType.PEER_STORE_ACK ||
        type == proto.MessageType.PEER_RETRIEVE ||
        type == proto.MessageType.PEER_RETRIEVE_RESPONSE ||
        type == proto.MessageType.HOLE_PUNCH_REQUEST ||
        type == proto.MessageType.HOLE_PUNCH_NOTIFY ||
        type == proto.MessageType.HOLE_PUNCH_PING ||
        type == proto.MessageType.HOLE_PUNCH_PONG ||
        type == proto.MessageType.MEDIA_CHUNK ||
        type == proto.MessageType.CALL_GROUP_AUDIO ||
        type == proto.MessageType.CALL_GROUP_VIDEO ||
        type == proto.MessageType.CALL_GROUP_LEAVE ||
        type == proto.MessageType.CALL_GROUP_KEY_ROTATE ||
        type == proto.MessageType.CALL_RTT_PING ||
        type == proto.MessageType.CALL_RTT_PONG ||
        type == proto.MessageType.CALL_TREE_UPDATE ||
        type == proto.MessageType.CALL_REJOIN;
    // A peer is LAN if it has at least one same-subnet address (priority 1).
    // Previous check (targets.every(isPrivateIp)) falsely classified LAN peers
    // as non-LAN when they also had a public IP (via UPnP), forcing unnecessary
    // PoW computation that blocked image delivery (fire-and-forget race condition).
    final isLanPeer = targets.any((addr) => addr.priority == 1);
    // V3.1.7: Skip PoW when message will travel via relay — receiver exempts
    // relay-delivered messages (from=0.0.0.0) from PoW verification anyway.
    // Saves 500ms-2s on mobile devices.
    // Multi-device: directBlocked is per-address (via backoff), not per-node.
    // A second device may have a fresh address while the first is in backoff.
    // The node-level consecutiveRouteFailures is kept for diagnostics/logging
    // but no longer gates the send decision.
    final activeTargets = targets.where((addr) =>
        !addr.isInBackoff && addr.isReachableFromCurrentNetwork).toList();
    final directBlocked = activeTargets.isEmpty;
    final willRelay = directBlocked;
    if (!isInfrastructure && !isLanPeer && !willRelay && !envelope.hasPow()) {
      final signedData = envelope.writeToBuffer();
      try {
        envelope.pow = await ProofOfWork.computeAsync(signedData, difficulty: ProofOfWork.defaultDifficulty);
      } catch (e) {
        _log.error('PoW computation failed: $e — using sync fallback');
        envelope.pow = ProofOfWork.compute(signedData, difficulty: ProofOfWork.defaultDifficulty);
      }
    }

    final ackWorthy = AckTracker.isAckWorthy(type);
    final isRelayable = type != proto.MessageType.RELAY_FORWARD &&
        type != proto.MessageType.RELAY_ACK &&
        type != proto.MessageType.TYPING_INDICATOR &&
        type != proto.MessageType.READ_RECEIPT;

    // ── V3.1 Route-based sending ──────────────────────────────
    // RUDP Light principle: OS-level UDP "success" ≠ delivery.
    // Only DELIVERY_RECEIPT confirms actual delivery.
    //
    // Cascade logic:
    // 1. Direct to recipient (ACK tracker monitors)
    // 2. Relay via confirmed-working neighbor (Gateway/DV)
    // 3. Fallback relays (learned, generic)
    // 4. S&F as offline safety net
    //
    // Direct send to recipient starts ACK tracker but does NOT
    // end the cascade — the confirmed-working relay is always
    // also tried (because direct can fail due to AP isolation).
    bool anySent = false;

    // ── Step 1: Direct to recipient ────────────────────────────
    // Attempts direct delivery. With AP isolation the ACK fails
    // after 8s → Route DOWN. Cascade continues regardless.
    // V3.1.7: Skip direct for large payloads when route is not ackConfirmed.
    // Large unconfirmed direct sends flood the OS send buffer with dead
    // fragments (AP isolation drops them), blocking subsequent relay sends.
    // (directBlocked computed above for PoW exemption, reused here)
    final directRoute = dvRouting.bestRouteTo(peerHex);
    final directProven = directRoute != null && directRoute.isDirect && directRoute.ackConfirmed;
    // Skip large direct sends only if peer is truly unconfirmed (never heard from).
    // Confirmed peers (received PONG/message) have a working path — no AP isolation.
    final peerConfirmed = _confirmedPeers.contains(peerHex);
    final skipDirectLarge = !directProven && !peerConfirmed &&
        envelope.writeToBuffer().length > maxFragmentPacketSize;
    if (!directBlocked && !skipDirectLarge && targets.isNotEmpty) {
      final success = await _sendDirectToPeer(envelope, peer, ackWorthy);
      if (success) {
        if (directProven) {
          return true;
        }
        // Cross-subnet private peers (priority 2): trust direct send only if
        // we also have a private IP in the SAME /8 range (same physical network).
        // 10.0.2.x (emulator NAT) is NOT reachable from 192.168.x.x even though
        // both are "private" — different network classes behind different NATs.
        final bestTarget = targets.firstOrNull;
        if (bestTarget != null && bestTarget.priority == 2 && _isPrivateIp(_localIp) &&
            _samePrivateNetwork(bestTarget.ip, _localIp)) {
          return true;
        }
        // Priority 1 (same subnet): only trust if directProven (handled above).
        // confirmedPeers is NOT sufficient — peer may be confirmed via relay
        // (from=0.0.0.0) while AP isolation blocks direct UDP.
        // Fall through to relay cascade for all non-proven same-subnet peers.
        // Untrusted direct (priority 1 without ACK, never heard from):
        // packet was sent but may be AP-isolated. Do NOT set anySent —
        // relay fallback (Steps 2c/4) must still run as safety net.
      }
    }

    // ── Step 2: Relay via confirmed-working neighbor ──────────
    // Priority: learned relay route (proven return path from incoming
    // RELAY_FORWARD) > DV relay routes > default gateway.
    _log.debug('Cascade for ${peerHex.substring(0, 8)}: anySent=$anySent, '
        'directBlocked=$directBlocked, isRelayable=$isRelayable, '
        'hasRelay=${peer.hasValidRelayRoute}, '
        'gwHex=${dvRouting.defaultGatewayHex?.substring(0, 8)}, '
        'dvRoutes=${dvRouting.routesTo(peerHex).length}, '
        'neighbors=${dvRouting.neighbors.length}');
    if (isRelayable) {
      // 2a: Learned relay route — most specific, proven path for THIS peer.
      // Must be tried BEFORE default gateway, because the gateway may not
      // be able to reach the target (e.g. AP isolation: Alice as gateway
      // can't reach phone, but Bootstrap as learned relay can).
      // V3.1.35: Validate relay node is actually reachable — stale relay
      // routes from disk-loaded routing tables cause unnecessary timeouts.
      if (peer.hasValidRelayRoute) {
        final relayViaHex = bytesToHex(peer.relayViaNodeId!);
        if (relayViaHex != peerHex && !_isLocalIdentity(relayViaHex)) {
          final relayPeer = routingTable.getPeer(peer.relayViaNodeId!);
          final relayAlive = relayPeer != null && _confirmedPeers.contains(relayViaHex);
          if (relayPeer != null && relayAlive) {
            _log.debug('Learned relay for ${peerHex.substring(0, 8)} via ${relayViaHex.substring(0, 8)}');
            final success = await _sendViaSpecificRelay(envelope, recipientNodeId, relayPeer);
            if (success) return true; // Learned relay is proven path — no need for DV/GW duplicates
          } else {
            peer.clearRelayRoute();
          }
        } else {
          peer.clearRelayRoute();
        }
      }

      final dvRoutes = dvRouting.routesTo(peerHex);

      // 2b: DV relay routes — confirmed nextHops first
      for (final route in dvRoutes) {
        if (!route.isAlive || route.isDirect) continue;
        if (route.nextHop == null) continue;
        final nhHex = bytesToHex(route.nextHop!);
        if (!dvRouting.isRelayConfirmed(nhHex)) continue; // Only confirmed
        final nextHopPeer = routingTable.getPeer(route.nextHop!);
        if (nextHopPeer != null) {
          final success = await _sendViaNextHop(envelope, recipientNodeId, nextHopPeer);
          if (success) return true; // Confirmed → end cascade
        }
      }

      // 2c: Default gateway
      if (!anySent) {
        final gwHex = dvRouting.defaultGatewayHex;
        if (gwHex != null && gwHex != peerHex && !_isLocalIdentity(gwHex)) {
          final gwPeer = routingTable.getPeer(hexToBytes(gwHex));
          if (gwPeer != null) {
            _log.debug('Default-Gateway ${gwHex.substring(0, 8)} for ${peerHex.substring(0, 8)}');
            final success = await _sendViaNextHop(envelope, recipientNodeId, gwPeer);
            if (success) return true;
          } else {
            _log.debug('Default-Gateway ${gwHex.substring(0, 8)} skipped for ${peerHex.substring(0, 8)}: gwPeer not in routing table');
          }
        } else if (gwHex != null) {
          final skipReason = gwHex == peerHex
              ? 'gwHex == peerHex (handled by alt-relay below)'
              : '_isLocalIdentity(${gwHex.substring(0, 8)})';
          _log.debug('Default-Gateway skipped for ${peerHex.substring(0, 8)}: $skipReason');
        }
        // V3.1.52: Target IS the default gateway — direct send failed or
        // unconfirmed, relay through any OTHER confirmed neighbor instead.
        // Without this, messages to the gateway node have no relay fallback
        // (gwHex == peerHex skips the normal GW path, and all DV routes to
        // a neighbor are isDirect → Steps 2b/2d skip them too).
        if (gwHex != null && gwHex == peerHex) {
          for (final neighborHex in dvRouting.neighbors.keys) {
            if (neighborHex == peerHex) continue;
            if (_isLocalIdentity(neighborHex)) continue;
            if (!_confirmedPeers.contains(neighborHex)) continue;
            final neighborPeer = routingTable.getPeer(hexToBytes(neighborHex));
            if (neighborPeer != null) {
              _log.debug('Alt-relay via ${neighborHex.substring(0, 8)} for gateway-target ${peerHex.substring(0, 8)}');
              final success = await _sendViaNextHop(envelope, recipientNodeId, neighborPeer);
              if (success) return true;
            }
          }
        }
      }

      // 2d: DV relay routes — unconfirmed nextHops (fallback)
      for (final route in dvRoutes) {
        if (!route.isAlive || route.isDirect) continue;
        if (route.nextHop == null) continue;
        final nhHex = bytesToHex(route.nextHop!);
        if (dvRouting.isRelayConfirmed(nhHex)) continue; // Already tried in 2b
        final nextHopPeer = routingTable.getPeer(route.nextHop!);
        if (nextHopPeer != null) {
          final success = await _sendViaNextHop(envelope, recipientNodeId, nextHopPeer);
          if (success) { anySent = true; break; } // Unconfirmed → continue
        }
      }
    }

    // ── Step 4: Generic relay search ──────────────────────────
    if (!anySent && isRelayable) {
      final relayed = await _sendViaRelay(envelope, recipientNodeId);
      if (relayed) return true;
    }

    if (anySent) return true; // Direct or unconfirmed relay has sent

    // Observability: if we reach here with no send path, the cascade
    // exhausted all options silently. This is the signal for debugging
    // "message never arrives" incidents.
    _log.warn('Cascade fell through for ${peerHex.substring(0, 8)}: '
        'no direct, no relay, no gateway, no S&F path — '
        'type=${envelope.messageType.name} size=${envelope.encryptedPayload.length}B '
        'dvRoutes=${dvRouting.routesTo(peerHex).length} '
        'neighbors=${dvRouting.neighbors.length} '
        'hasRelay=${peer.hasValidRelayRoute} '
        'gwHex=${dvRouting.defaultGatewayHex?.substring(0, 8)} '
        'ackWorthy=$ackWorthy');

    // ── Step 5: Store-and-Forward (offline safety net) ─────────
    if (ackWorthy) {
      await _storeOnPeers(envelope, recipientNodeId);
    }

    _tlsFallback.recordFailure(peerHex);

    // Queue for retry when route becomes available
    if (ackWorthy && envelope.messageId.isNotEmpty) {
      final msgIdHex = bytesToHex(Uint8List.fromList(envelope.messageId));
      messageQueue.enqueue(
        messageIdHex: msgIdHex,
        recipientNodeId: recipientNodeId,
        serializedEnvelope: envelope.writeToBuffer(),
      );
    }

    return false;
  }

  /// Direct send to peer's addresses (priority-sorted, UDP primary, TLS as anti-censorship fallback).
  Future<bool> _sendDirectToPeer(
    proto.MessageEnvelope envelope,
    PeerInfo peer,
    bool ackWorthy,
  ) async {
    final peerHex = peer.nodeIdHex;
    final targets = peer.allConnectionTargets(); // Sorted by priority ASC, score DESC

    // Filter: NAT context (V3.1.32) + backoff + reachability heuristic.
    final natFiltered = _filterNatContext(targets, peer);
    var activeTargets = natFiltered
        .where((addr) => !addr.isInBackoff && addr.isReachableFromCurrentNetwork)
        .toList();
    if (activeTargets.isEmpty) {
      // All targets heuristically unreachable — try non-backoff NAT-filtered targets
      activeTargets = natFiltered.where((addr) => !addr.isInBackoff).toList();
      if (activeTargets.isEmpty) return false;
    }

    // TLS mode (anti-censorship fallback): periodic UDP probe + TLS send
    if (_tlsFallback.isInTlsMode(peerHex)) {
      if (_tlsFallback.shouldProbeUdp(peerHex)) {
        _tlsFallback.resetProbeTimer(peerHex);
        for (final addr in activeTargets) {
          try {
            final udpOk = await transport.sendUdp(envelope, InternetAddress(addr.ip), addr.port);
            if (udpOk) {
              _tlsFallback.recordSuccess(peerHex);
              addr.recordSuccess();
              if (ackWorthy && envelope.messageId.isNotEmpty) {
                _trackAck(envelope, peerHex, peer.nodeId, [addr]);
              }
              return true;
            }
          } catch (_) {}
        }
      }
      for (final addr in activeTargets) {
        try {
          final tlsOk = await transport.sendTls(envelope, InternetAddress(addr.ip), addr.port);
          if (tlsOk) {
            _tlsFallback.recordTlsSuccess(peerHex);
            addr.recordSuccess();
            if (ackWorthy && envelope.messageId.isNotEmpty) {
              _trackAck(envelope, peerHex, peer.nodeId, [addr]);
            }
            return true;
          }
        } catch (_) {}
      }
      return false;
    }

    // UDP primary — single port, all traffic
    final udpFutures = <Future<bool>>[];
    for (final addr in activeTargets) {
      try {
        udpFutures.add(transport.sendUdp(envelope, InternetAddress(addr.ip), addr.port));
      } catch (_) {}
    }

    if (udpFutures.isEmpty) return false;

    final results = await Future.wait(udpFutures).timeout(
      const Duration(milliseconds: 1500),
      onTimeout: () => udpFutures.map((_) => false).toList(),
    );

    // Score tracking: for ackWorthy messages, let AckTracker handle BOTH
    // success and failure exclusively — prevents double-counting failures
    // (once here + once in AckTracker timeout → premature backoff).
    for (var i = 0; i < activeTargets.length && i < results.length; i++) {
      if (results[i]) {
        if (!ackWorthy) activeTargets[i].recordSuccess();
      } else {
        if (!ackWorthy) activeTargets[i].recordFailure();
      }
    }

    final anySuccess = results.any((r) => r);

    if (anySuccess) {
      _tlsFallback.recordSuccess(peerHex);
      if (ackWorthy && envelope.messageId.isNotEmpty) {
        _trackAck(envelope, peerHex, peer.nodeId, activeTargets);
      }
      return true;
    }

    return false;
  }

  /// Register ACK tracking for RUDP Light (non-blocking).
  /// V3.1: Supports relay context for per-route failure tracking and relay-aware timeouts.
  void _trackAck(
    proto.MessageEnvelope envelope, String peerHex, Uint8List peerNodeId, List<PeerAddress> addrs, {
    String? viaNextHopHex,
    int estimatedHops = 1,
  }) {
    final msgIdHex = bytesToHex(Uint8List.fromList(envelope.messageId));
    final rtt = dhtRpc.getRtt(peerNodeId);
    final timeout = AckTracker.computeTimeout(rtt, hopCount: estimatedHops);
    ackTracker.trackSend(msgIdHex, peerHex, List.of(addrs), timeout,
        viaNextHopHex: viaNextHopHex, estimatedHops: estimatedHops,
        serializedEnvelope: envelope.writeToBuffer(),
        recipientNodeId: peerNodeId);
  }

  /// §26 Phase 3: Send envelope to ALL known devices of a user (call fan-out).
  /// Falls back to single sendEnvelope if no per-device entries exist.
  Future<bool> sendToAllDevices(proto.MessageEnvelope envelope, Uint8List userId) async {
    final peers = routingTable.getAllPeersForUserId(userId);
    if (peers.isEmpty) {
      // No device-specific entries — try normal send (may use userId fallback)
      return sendEnvelope(envelope, userId);
    }
    var anySent = false;
    for (final peer in peers) {
      // Clone envelope for each device (PoW/ack tracking are per-send)
      final copy = proto.MessageEnvelope.fromBuffer(envelope.writeToBuffer());
      final sent = await sendEnvelope(copy, peer.nodeId);
      if (sent) anySent = true;
    }
    return anySent;
  }

  /// Send via DV routing next-hop (wraps in RELAY_FORWARD with TTL=64).
  Future<bool> _sendViaNextHop(
    proto.MessageEnvelope envelope,
    Uint8List recipientNodeId,
    PeerInfo nextHopPeer,
  ) async {
    // V3.1.12: Chunk large envelopes that would exceed relay budget
    if (_needsChunking(envelope)) {
      return _sendChunkedViaRelay(envelope, recipientNodeId, nextHopPeer, isNextHop: true);
    }

    final sodium = SodiumFFI();
    final relayId = sodium.randomBytes(16);

    final relay = proto.RelayForward()
      ..relayId = relayId
      ..finalRecipientId = recipientNodeId
      ..wrappedEnvelope = envelope.writeToBuffer()
      ..hopCount = 1
      ..maxHops = RelayBudget.maxHops
      ..ttl = 64
      ..originNodeId = primaryIdentity.deviceNodeId
      ..createdAtMs = Int64(DateTime.now().millisecondsSinceEpoch);
    relay.visitedNodes.add(primaryIdentity.deviceNodeId);

    final relayEnvelope = primaryIdentity.createSignedEnvelope(
      proto.MessageType.RELAY_FORWARD,
      relay.writeToBuffer(),
      recipientId: nextHopPeer.nodeId,
    );

    final ok = await _sendEnvelopeToPeer(relayEnvelope, nextHopPeer);
    if (ok) {
      final relayIdHex = bytesToHex(relayId);
      _pendingRelays[relayIdHex] = (
        recipientNodeId: recipientNodeId,
        relayPeerNodeId: Uint8List.fromList(nextHopPeer.nodeId),
      );
      Timer(const Duration(minutes: 5), () => _pendingRelays.remove(relayIdHex));

      // V3.1: Track ACK against FINAL RECIPIENT with relay-aware timeout.
      final innerType = envelope.messageType;
      if (AckTracker.isAckWorthy(innerType) && envelope.messageId.isNotEmpty) {
        final recipientHex = bytesToHex(recipientNodeId);
        final route = dvRouting.bestRouteTo(recipientHex);
        final hops = route?.hopCount ?? 2;
        _trackAck(envelope, recipientHex, recipientNodeId,
            nextHopPeer.allConnectionTargets(),
            viaNextHopHex: nextHopPeer.nodeIdHex, estimatedHops: hops);
      }

      _log.info('DV relay: via ${nextHopPeer.nodeIdHex.substring(0, 8)} '
          'for ${bytesToHex(recipientNodeId).substring(0, 8)}');
      return true;
    }
    return false;
  }

  /// Returns true if any peer has been confirmed reachable since this node
  /// started. Uses PeerInfo.lastSeen (set on PONG / actual message receipt)
  /// rather than PeerAddress.lastSuccess (set on OS-level send, which can
  /// succeed even when the peer is unreachable due to AP isolation).
  /// Ignores lastSeen values loaded from disk (previous sessions).
  bool _hasRecentlyReachablePeer() {
    for (final peer in routingTable.allPeers) {
      if (peer.lastSeen.isAfter(_startedAt)) return true;
    }
    return false;
  }

  // ── Maintenance ────────────────────────────────────────────────────

  void _maintenance() {
    // Prune peers older than 4 hours — synchronize DV neighbors
    final peersBefore = routingTable.allPeers.map((p) => p.nodeIdHex).toSet();
    // Debug: log peer ages before prune
    for (final peer in routingTable.allPeers) {
      final age = DateTime.now().difference(peer.lastSeen);
      if (age.inHours >= 4) {
        _log.info('Maintenance: peer ${peer.nodeIdHex.substring(0, 8)} age=${age.inSeconds}s will be pruned');
      }
    }
    final pruned = routingTable.prune(const Duration(hours: 4));
    if (pruned > 0) {
      _log.info('Maintenance: pruned $pruned stale peers');
      final peersAfter = routingTable.allPeers.map((p) => p.nodeIdHex).toSet();
      final removed = peersBefore.difference(peersAfter);
      for (final hex in removed) {
        _log.info('Maintenance: removed ${hex.substring(0, 8)} from routing table');
        dvRouting.removeNeighbor(hexToBytes(hex));
      }
    }
    // Deep GC: protected seeds survive the 4h prune for Doze-resilience
    // but should NOT pile up forever (retired devices from old QR scans).
    // Gated to at most once per hour inside the routing table itself.
    final staleSeeds = routingTable.pruneStaleSeeds(const Duration(days: 30));
    if (staleSeeds > 0) {
      _log.info('Maintenance: pruned $staleSeeds stale seed peers (>30d)');
    }
    // Prune stale addresses (>14 days without lastSuccess)
    var staleAddrs = 0;
    for (final peer in routingTable.allPeers) {
      staleAddrs += peer.pruneStaleAddresses();
    }
    if (staleAddrs > 0) {
      _log.info('Maintenance: removed $staleAddrs stale addresses');
    }

    dvRouting.updateDefaultGateway();
    peerMessageStore.pruneExpired();
    messageQueue.pruneExpired();
    _saveRoutingTable();
  }

  void _doPeerExchange() {
    final peers = routingTable.allPeers;
    if (peers.isEmpty) return;

    // Pick a random subset of peers for exchange
    final shuffled = List<PeerInfo>.from(peers)..shuffle();
    for (final peer in shuffled.take(3)) {
      _sendPeerListSummary(peer);
    }
  }

  void _sendPeerListSummary(PeerInfo peer) {
    final summary = proto.PeerListSummary();
    for (final p in routingTable.allPeers) {
      summary.entries.add(proto.PeerSummaryEntry()
        ..nodeId = p.nodeId
        ..lastSeen = Int64(p.lastSeen.millisecondsSinceEpoch));
    }

    final envelope = _createEnvelope(proto.MessageType.PEER_LIST_SUMMARY);
    envelope.encryptedPayload = summary.writeToBuffer();
    envelope.recipientId = peer.nodeId;
    _sendEnvelopeToPeer(envelope, peer);
  }

  // ── Network Change ─────────────────────────────────────────────────

  Future<void> onNetworkChanged({bool force = false}) async {
    // Check if IPs actually changed — Android's connectivity_plus fires
    // spurious events (ConnectivityResult.mobile → mobile) without real change.
    // Clearing DV routes on false alarms kills all relay paths.
    // force=true: mass route-down detected — public IP may have changed even
    // though local IPs are the same (DS-Lite/CGNAT ISP reassignment).
    final updatedIps = await Transport.getAllLocalIps();
    final ipsChanged = updatedIps.join(',') != _localIps.join(',');
    if (!force && !ipsChanged && _localIps.isNotEmpty) {
      _log.debug('Network change event ignored — IPs unchanged: ${updatedIps.join(", ")}');
      return;
    }

    _log.info('Network change detected${force ? " (mass route-down)" : ""} — '
        'IPs: ${_localIps.join(",")} → ${updatedIps.join(",")}');

    _lastNetworkChangeAt = DateTime.now();

    // Notify daemon/headless to re-query public IP
    onNetworkChangeDetected?.call();

    // 0. Deactivate mobile fallback (new network = fresh start via WiFi)
    transport.stopMobileFallback();

    // 1. Reset NAT + port mapping
    natTraversal.reset();
    await portMapper.reset();
    // Re-acquire port mapping in background
    portMapper.start();

    // 2. Fast discovery burst
    localDiscovery.triggerFastDiscovery();
    multicastDiscovery.triggerFastDiscovery();

    // 3. Update local IPs (all interfaces)
    _localIp = updatedIps.isNotEmpty ? updatedIps.first : '127.0.0.1';
    _localIps = updatedIps;
    PeerAddress.currentLocalIps = _localIps;
    _log.info('Network recovery: IPs ${updatedIps.join(", ")}');

    // 3b. Clear all relay routes and failure counters (network topology may have changed).
    // Failure counters from the old network are meaningless — a peer unreachable via
    // WiFi/LAN may be perfectly reachable via mobile (public IP) and vice versa.
    // Without this reset, directBlocked stays true and _sendDirectToPeer is never called.
    for (final peer in routingTable.allPeers) {
      peer.clearRelayRoute();
      peer.consecutiveRouteFailures = 0;
      peer.consecutiveRelayFailures = 0;
      // Reset per-address backoff (exponential backoff from old network is stale)
      for (final addr in peer.addresses) {
        addr.consecutiveFailures = 0;
      }
    }
    _pendingRelays.clear();

    // 3b2. Reset TLS fallback (peer stuck in TLS mode from old network would skip UDP)
    _tlsFallback.reset();

    // 3c. DV-Routing: clear all routes (topology may have changed)
    dvRouting.clearAllRoutes();
    _lastRouteUpdateSentTo.clear();

    // 4. Ping all known peers with network-aware address selection.
    // Private IPs are only meaningful within their NAT context. A peer's
    // privateIp is only reachable if we share the same publicIp (same NAT).
    // After network change we may not have our publicIp yet, so:
    //   - Always try peer's public addresses
    //   - Try peer's private addresses only if our publicIp matches theirs
    //     (same NAT) or if we have no publicIp yet (try everything, Ed25519
    //     PONG signature prevents connecting to wrong peers)
    for (final peer in routingTable.allPeers) {
      for (final addr in _filterNatContext(peer.allConnectionTargets(), peer)) {
        _sendPing(addr.ip, addr.port);
      }
    }

    // 5. Re-bootstrap
    await _kademliaBootstrap();

    // 6. Broadcast address update
    _broadcastAddressUpdate();

    // 7. Subnet scan fallback: if no peer responded within 5s after network
    // change, scan /16 range. Covers the case where known peers are in a
    // different subnet or unreachable (AP isolation) but other nodes (e.g.
    // Bootstrap) are reachable cross-subnet.
    Future.delayed(const Duration(seconds: 5), () {
      if (!_running) return;
      if (!_hasRecentlyReachablePeer()) {
        _log.info('No peer responded after network change — starting subnet scan');
        localDiscovery.startSubnetScan(
            _localIps, () => _hasRecentlyReachablePeer());
      }
    });

    // 8. Mobile fallback probe: if still 0 peers after 15s AND we have
    // multiple local IPs (WiFi + Mobile), the WiFi path is likely dead
    // (captive portal, firewall). Try binding a socket to each non-primary
    // IP and sending PINGs. If mobile works → activate mobile fallback socket.
    Future.delayed(const Duration(seconds: 15), () {
      if (!_running) return;
      if (_confirmedPeers.isNotEmpty) return; // Peers found via WiFi — no fallback needed
      if (transport.isMobileFallbackActive) return; // Already active
      _tryMobileFallback();
    });

    // 9. Proactive rendezvous: after 8s, ask any reachable peer about peers
    // that didn't re-confirm since the network change. Establishes relay
    // routes before the user sends a message → Layer-2 cascade picks them up.
    // Reduces dependency on Bootstrap as sole rendezvous point.
    Future.delayed(const Duration(seconds: 8), () {
      if (!_running) return;
      _tryProactiveRendezvous();
    });
  }

  /// Ask any confirmed peer about peers/contacts not reconfirmed since the
  /// last network change. Establishes relay routes from the responses.
  Future<void> _tryProactiveRendezvous() async {
    if (_confirmedPeers.isEmpty) return;
    final changeAt = _lastNetworkChangeAt;
    if (changeAt == null) return;

    final stale = routingTable.allPeers.where((p) {
      if (_isLocalIdentity(p.nodeIdHex)) return false;
      if (_confirmedPeers.contains(p.nodeIdHex)) return false;
      if (p.hasValidRelayRoute) return false;
      return p.lastSeen.isBefore(changeAt);
    }).take(5).toList();

    if (stale.isEmpty) return;

    _log.info('Proactive rendezvous: querying ${stale.length} unreachable peer(s)');
    for (final peer in stale) {
      reachabilityProbe.queryPeersAbout(peer.nodeId).then((relayNodeId) {
        if (relayNodeId == null) return;
        final relayHex = bytesToHex(relayNodeId);
        if (relayHex == peer.nodeIdHex) return;
        if (_isLocalIdentity(relayHex)) return;
        peer.relayViaNodeId = relayNodeId;
        peer.relaySetAt = DateTime.now();
        peer.consecutiveRelayFailures = 0;
        _log.info('Proactive rendezvous: relay learned ${peer.nodeIdHex.substring(0, 8)} '
            'via ${relayHex.substring(0, 8)}');
      });
    }
  }

  /// Probe non-primary local interfaces to find a working mobile path.
  /// Called when WiFi appears connected but 0 peers are reachable.
  Future<void> _tryMobileFallback() async {
    final allIps = await Transport.getAllLocalIps();
    if (allIps.length < 2) {
      _log.debug('Mobile fallback: only ${allIps.length} local IP(s) — no alternative interface');
      return;
    }

    final primaryIp = allIps.first; // WiFi/LAN IP (highest priority)
    final alternativeIps = allIps.where((ip) => ip != primaryIp && !ip.contains(':')).toList();
    if (alternativeIps.isEmpty) {
      _log.debug('Mobile fallback: no alternative IPv4 interfaces');
      return;
    }

    // Find peers with public/internet addresses to probe through
    final probePeers = routingTable.allPeers
        .where((p) => p.publicIp.isNotEmpty && !_isPrivateIp(p.publicIp) && p.publicPort > 0)
        .take(3)
        .toList();
    if (probePeers.isEmpty) {
      _log.debug('Mobile fallback: no peers with public addresses to probe');
      return;
    }

    _log.info('Mobile fallback: probing ${alternativeIps.length} alternative interface(s)');

    // Build a PING envelope for probing
    final pingData = _buildPingPacket();

    for (final altIp in alternativeIps) {
      for (final peer in probePeers) {
        try {
          final sent = await transport.probeViaInterface(
            altIp,
            InternetAddress(peer.publicIp),
            peer.publicPort,
            pingData,
          );
          if (sent) {
            _log.info('Mobile fallback: probe sent via $altIp to ${peer.publicIp}:${peer.publicPort}');
            // Activate mobile fallback socket on this interface
            final activated = await transport.startMobileFallback(altIp);
            if (activated) {
              _log.info('Mobile fallback: socket active on $altIp — re-pinging all peers');
              // Re-send PINGs to all known peers through mobile socket
              for (final p in routingTable.allPeers) {
                for (final addr in p.allConnectionTargets()) {
                  if (!_isPrivateIp(addr.ip)) {
                    _sendPing(addr.ip, addr.port);
                  }
                }
              }
              return; // First working interface is enough
            }
          }
        } catch (e) {
          _log.debug('Mobile fallback: probe via $altIp failed: $e');
        }
      }
    }
    _log.info('Mobile fallback: no alternative interface worked');
  }

  /// Build a raw PING packet for interface probing.
  Uint8List _buildPingPacket() {
    final ping = proto.MessageEnvelope()
      ..version = 1
      ..messageType = proto.MessageType.DHT_PING
      ..timestamp = Int64(DateTime.now().millisecondsSinceEpoch)
      ..senderId = primaryIdentity.userId;
    return Uint8List.fromList(ping.writeToBuffer());
  }

  /// Change the listening port at runtime. Rebinds UDP+TLS, updates all peers.
  /// Throws SocketException if new port is unavailable.
  Future<void> changePort(int newPort) async {
    if (newPort == port) return;
    await transport.rebind(newPort);
    port = newPort;
    _log.info('Port changed to $newPort, broadcasting to peers');
    _broadcastAddressUpdate();
  }

  /// Broadcast our current address info to all peers.
  /// Called internally on network changes and externally by headless public IP polling.
  void broadcastAddressUpdate() => _broadcastAddressUpdate();

  /// Initiate a port probe for an external IP (public API for daemon/headless ipify fallback).
  void probePublicPort(String externalIp) => _initiatePortProbe(externalIp);

  void _broadcastAddressUpdate() {
    // Broadcast PeerInfo for ALL registered identities
    for (final ctx in _identities.values) {
      final pushMsg = _createEnvelope(proto.MessageType.PEER_LIST_PUSH);
      final pushData = proto.PeerListPush();
      pushData.peers.add(ctx.ownPeerInfo(
        localIp: _localIp,
        localPort: port,
        publicIp: natTraversal.publicIp,
        publicPort: natTraversal.publicPort,
        allLocalIps: _localIps,
      ).toProto());
      pushMsg.encryptedPayload = pushData.writeToBuffer();

      for (final peer in routingTable.allPeers) {
        pushMsg.recipientId = peer.nodeId;
        _sendEnvelopeToPeer(pushMsg, peer);
      }
    }
    // Notify services so IPC clients refresh peerSummaries
    onPeersChanged?.call();
  }

  /// Called when peer list or addresses change (e.g. new public IP discovered).
  /// Used by daemon to push state_changed events to GUI.
  void Function()? onPeersChanged;

  /// Called when a network change is detected (ip monitor, mass route-down, etc.).
  /// Used by daemon/headless to re-query public IP via ipify.
  void Function()? onNetworkChangeDetected;

  PeerInfo _ownPeerInfo() {
    return primaryIdentity.ownPeerInfo(
      localIp: _localIp,
      localPort: port,
      publicIp: natTraversal.publicIp,
      publicPort: natTraversal.publicPort,
      allLocalIps: _localIps,
    );
  }

  // ── Persistence ────────────────────────────────────────────────────

  void _loadRoutingTable() {
    final file = File('$profileDir/routing_table.json');
    if (file.existsSync()) {
      try {
        final json = jsonDecode(file.readAsStringSync()) as List<dynamic>;
        routingTable.loadFromJson(json);
        // Touch all loaded peers so maintenance prune (4h) doesn't remove them
        // before they have a chance to respond to discovery/PINGs.
        final now = DateTime.now();
        for (final peer in routingTable.allPeers) {
          peer.lastSeen = now;
        }
        _log.info('Loaded ${routingTable.peerCount} peers from routing table');
      } catch (e) {
        _log.warn('Failed to load routing table: $e');
      }
    }
  }

  void _saveRoutingTable() {
    try {
      final file = File('$profileDir/routing_table.json');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(routingTable.toJson()));
    } catch (e) {
      _log.warn('Failed to save routing table: $e');
    }
  }

  void _loadBootstrapSeeds() {
    if (routingTable.peerCount > 3) return; // Enough peers already

    final file = File('$profileDir/bootstrap_seeds.json');
    if (file.existsSync()) {
      try {
        final json = jsonDecode(file.readAsStringSync()) as List<dynamic>;
        for (final entry in json) {
          final ip = entry['ip'] as String;
          final port = entry['port'] as int;
          final peerId = entry['nodeId'] as String?;
          if (ip.isNotEmpty && port > 0) {
            if (peerId != null) {
              _touchPeer(hexToBytes(peerId), ip, port);
            }
            _sendPing(ip, port);
          }
        }
        _log.info('Loaded bootstrap seeds');
      } catch (e) {
        _log.warn('Failed to load bootstrap seeds: $e');
      }
    }
  }

  void _addBootstrapPeer(String addressStr) {
    // Format: ip:port (IPv4) or [ip]:port (IPv6)
    String ip;
    int? port;
    if (addressStr.startsWith('[')) {
      // IPv6: [2001:db8::1]:8081
      final closeBracket = addressStr.indexOf(']');
      if (closeBracket < 0) return;
      ip = addressStr.substring(1, closeBracket);
      if (closeBracket + 2 < addressStr.length && addressStr[closeBracket + 1] == ':') {
        port = int.tryParse(addressStr.substring(closeBracket + 2));
      }
    } else {
      final parts = addressStr.split(':');
      if (parts.length != 2) return;
      ip = parts[0];
      port = int.tryParse(parts[1]);
    }
    if (port == null) return;
    _sendPing(ip, port);
  }

  // ── Multi-Hop Relay ─────────────────────────────────────────────────

  /// Send an envelope via relay when direct delivery failed.
  /// Wraps the original envelope in RELAY_FORWARD and sends to relay candidates.
  Future<bool> _sendViaRelay(proto.MessageEnvelope envelope, Uint8List recipientNodeId) async {
    final candidates = findRelayCandidates(recipientNodeId);
    if (candidates.isEmpty) {
      _log.debug('Relay: no candidates for ${bytesToHex(recipientNodeId).substring(0, 8)}');
      return false;
    }

    // V3.1.12: Chunk large envelopes that would exceed relay budget
    if (_needsChunking(envelope)) {
      // Try each candidate until one works
      for (final candidate in candidates) {
        final ok = await _sendChunkedViaRelay(envelope, recipientNodeId, candidate);
        if (ok) return true;
      }
      return false;
    }

    final sodium = SodiumFFI();
    final relayId = sodium.randomBytes(16);

    final relay = proto.RelayForward()
      ..relayId = relayId
      ..finalRecipientId = recipientNodeId
      ..wrappedEnvelope = envelope.writeToBuffer()
      ..hopCount = 1
      ..maxHops = RelayBudget.maxHops
      ..ttl = 64  // V3: Hop limit (decremented per hop, dropped at 0)
      ..originNodeId = primaryIdentity.deviceNodeId
      ..createdAtMs = Int64(DateTime.now().millisecondsSinceEpoch);
    relay.visitedNodes.add(primaryIdentity.deviceNodeId);

    final relayEnvelope = primaryIdentity.createSignedEnvelope(
      proto.MessageType.RELAY_FORWARD,
      relay.writeToBuffer(),
    );

    // Register for relay route learning (auto-cleanup after 5 min)
    final relayIdHex = bytesToHex(relayId);

    // Try each candidate in order (sorted by score — best first).
    for (final candidate in candidates) {
      relayEnvelope.recipientId = candidate.nodeId;
      final ok = await _sendEnvelopeToPeer(relayEnvelope, candidate);
      if (ok) {
        _pendingRelays[relayIdHex] = (
          recipientNodeId: recipientNodeId,
          relayPeerNodeId: Uint8List.fromList(candidate.nodeId),
        );
        Timer(const Duration(minutes: 5), () => _pendingRelays.remove(relayIdHex));

        // V3.1: Track ACK against final recipient via relay
        if (AckTracker.isAckWorthy(envelope.messageType) && envelope.messageId.isNotEmpty) {
          final recipientHex = bytesToHex(recipientNodeId);
          _trackAck(envelope, recipientHex, recipientNodeId,
              candidate.allConnectionTargets(),
              viaNextHopHex: candidate.nodeIdHex, estimatedHops: 2);
        }

        _log.info('Relay: sent via ${candidate.nodeIdHex.substring(0, 8)} '
            'for ${bytesToHex(recipientNodeId).substring(0, 8)}');
        return true;
      }
    }

    _log.debug('Relay: all ${candidates.length} candidates failed');
    return false;
  }

  /// Send via a specific relay peer (used when a learned relay route exists).
  /// Falls back to generic relay search on failure.
  Future<bool> _sendViaSpecificRelay(
    proto.MessageEnvelope envelope,
    Uint8List recipientNodeId,
    PeerInfo relayPeer,
  ) async {
    // V3.1.12: Chunk large envelopes that would exceed relay budget
    if (_needsChunking(envelope)) {
      final ok = await _sendChunkedViaRelay(envelope, recipientNodeId, relayPeer);
      if (ok) return true;
      // Fall through to generic relay on failure
      final peer = routingTable.getPeer(recipientNodeId);
      peer?.clearRelayRoute();
      return _sendViaRelay(envelope, recipientNodeId);
    }

    final sodium = SodiumFFI();
    final relayId = sodium.randomBytes(16);

    final relay = proto.RelayForward()
      ..relayId = relayId
      ..finalRecipientId = recipientNodeId
      ..wrappedEnvelope = envelope.writeToBuffer()
      ..hopCount = 1
      ..maxHops = RelayBudget.maxHops
      ..ttl = 64  // V3: Hop Limit
      ..originNodeId = primaryIdentity.deviceNodeId
      ..createdAtMs = Int64(DateTime.now().millisecondsSinceEpoch);
    relay.visitedNodes.add(primaryIdentity.deviceNodeId);

    final relayEnvelope = primaryIdentity.createSignedEnvelope(
      proto.MessageType.RELAY_FORWARD,
      relay.writeToBuffer(),
      recipientId: relayPeer.nodeId,
    );

    final targets = _filterNatContext(relayPeer.allConnectionTargets(), relayPeer);
    for (final addr in targets) {
      try {
        final udpOk = await transport.sendUdp(relayEnvelope, InternetAddress(addr.ip), addr.port);
        if (udpOk) {
          final relayIdHex = bytesToHex(relayId);
          _pendingRelays[relayIdHex] = (
            recipientNodeId: recipientNodeId,
            relayPeerNodeId: Uint8List.fromList(relayPeer.nodeId),
          );
          Timer(const Duration(minutes: 5), () => _pendingRelays.remove(relayIdHex));

          // V3.1: Track ACK against final recipient via specific relay
          if (AckTracker.isAckWorthy(envelope.messageType) && envelope.messageId.isNotEmpty) {
            final recipientHex = bytesToHex(recipientNodeId);
            _trackAck(envelope, recipientHex, recipientNodeId,
                _filterNatContext(relayPeer.allConnectionTargets(), relayPeer),
                viaNextHopHex: relayPeer.nodeIdHex, estimatedHops: 2);
          }

          _log.info('Relay (learned route): sent via ${relayPeer.nodeIdHex.substring(0, 8)} '
              'for ${bytesToHex(recipientNodeId).substring(0, 8)}');
          return true;
        }
      } catch (_) {}
    }

    // Learned relay route failed — clear it and fall back to generic relay search
    _log.debug('Learned relay route to ${relayPeer.nodeIdHex.substring(0, 8)} failed — clearing');
    final peer = routingTable.getPeer(recipientNodeId);
    peer?.clearRelayRoute();
    return _sendViaRelay(envelope, recipientNodeId);
  }

  // ── App-Level Chunking for Relay (V3.1.12) ───────────────────────

  /// Handle incoming MEDIA_CHUNK: reassemble chunks into original envelope.
  void _handleMediaChunk(proto.MessageEnvelope envelope, InternetAddress from, int fromPort) {
    final chunk = proto.MediaChunk.fromBuffer(envelope.encryptedPayload);
    final transferIdHex = bytesToHex(Uint8List.fromList(chunk.transferId));

    final reassembled = _chunkReassembler.addChunk(
      transferIdHex: transferIdHex,
      chunkIndex: chunk.chunkIndex,
      totalChunks: chunk.totalChunks,
      chunkData: Uint8List.fromList(chunk.chunkData),
    );

    if (reassembled != null) {
      // Reassembly complete — deserialize original envelope and process
      try {
        final originalEnvelope = proto.MessageEnvelope.fromBuffer(reassembled);
        _log.info('Chunk reassembly complete: transfer=$transferIdHex '
            '(${reassembled.length}B, ${chunk.totalChunks} chunks)');
        _onEnvelopeReceived(originalEnvelope, from, fromPort, skipRateLimit: true);
      } catch (e) {
        _log.error('Chunk reassembly failed to parse envelope: $e');
      }
    }
  }

  /// Split a large envelope into MEDIA_CHUNK messages and send each via relay.
  /// Returns true if all chunks were sent successfully.
  Future<bool> _sendChunkedViaRelay(
    proto.MessageEnvelope envelope,
    Uint8List recipientNodeId,
    PeerInfo relayPeer, {
    bool isNextHop = false,
  }) async {
    final data = Uint8List.fromList(envelope.writeToBuffer());
    final chunks = chunkPayload(data);
    final sodium = SodiumFFI();
    final transferId = sodium.randomBytes(16);

    _log.info('Chunking ${data.length}B envelope into ${chunks.length} chunks '
        'for relay via ${relayPeer.nodeIdHex.substring(0, 8)}');

    for (var i = 0; i < chunks.length; i++) {
      final chunkMsg = proto.MediaChunk()
        ..transferId = transferId
        ..chunkIndex = i
        ..totalChunks = chunks.length
        ..chunkData = chunks[i]
        ..originalRecipientId = recipientNodeId;

      final chunkEnvelope = primaryIdentity.createSignedEnvelope(
        proto.MessageType.MEDIA_CHUNK,
        chunkMsg.writeToBuffer(),
        recipientId: recipientNodeId,
      );

      // Wrap each chunk in RELAY_FORWARD
      final relayId = sodium.randomBytes(16);
      final relay = proto.RelayForward()
        ..relayId = relayId
        ..finalRecipientId = recipientNodeId
        ..wrappedEnvelope = chunkEnvelope.writeToBuffer()
        ..hopCount = 1
        ..maxHops = RelayBudget.maxHops
        ..ttl = 64
        ..originNodeId = primaryIdentity.deviceNodeId
        ..createdAtMs = Int64(DateTime.now().millisecondsSinceEpoch);
      relay.visitedNodes.add(primaryIdentity.deviceNodeId);

      final relayEnvelope = primaryIdentity.createSignedEnvelope(
        proto.MessageType.RELAY_FORWARD,
        relay.writeToBuffer(),
        recipientId: relayPeer.nodeId,
      );

      final ok = await _sendEnvelopeToPeer(relayEnvelope, relayPeer);
      if (!ok) {
        _log.debug('Chunk $i/${chunks.length} relay send failed');
        return false;
      }
    }

    // Track ACK against final recipient for the original message
    if (AckTracker.isAckWorthy(envelope.messageType) && envelope.messageId.isNotEmpty) {
      final recipientHex = bytesToHex(recipientNodeId);
      _trackAck(envelope, recipientHex, recipientNodeId,
          relayPeer.allConnectionTargets(),
          viaNextHopHex: relayPeer.nodeIdHex, estimatedHops: 2);
    }

    _log.info('All ${chunks.length} chunks sent via ${relayPeer.nodeIdHex.substring(0, 8)}');
    return true;
  }

  /// Check if an envelope needs chunking for relay (exceeds relay budget).
  bool _needsChunking(proto.MessageEnvelope envelope) {
    // Estimate size without full serialization: check encryptedPayload + overhead
    final payloadSize = envelope.encryptedPayload.length;
    // Rough estimate: payload + ~200B envelope overhead + ~100B relay overhead
    return payloadSize > maxChunkDataSize - 300;
  }

  /// Handle an incoming RELAY_FORWARD message.
  void _handleRelayForward(proto.MessageEnvelope envelope, InternetAddress from, int fromPort) {
    final relay = proto.RelayForward.fromBuffer(envelope.encryptedPayload);
    final relayIdHex = bytesToHex(Uint8List.fromList(relay.relayId));

    // Dedup check (applies to local delivery AND forwarding)
    final relayIdBytes = Uint8List.fromList(relay.relayId);
    if (_relayBudget.isDuplicate(relayIdBytes)) {
      _log.debug('Relay rejected ($relayIdHex): duplicate relay_id');
      return;
    }

    // Loop check: our deviceNodeId in visited_nodes?
    for (final identity in _identities.values) {
      if (_relayBudget.isLoop(relay.visitedNodes, identity.deviceNodeId)) {
        _log.debug('Relay loop detected ($relayIdHex)');
        return;
      }
    }

    final targetId = Uint8List.fromList(relay.finalRecipientId);
    final targetHex = bytesToHex(targetId);

    // Local delivery FIRST — hop count must NOT block messages addressed to us.
    // A 3-hop path (Alice→Bob→Bootstrap→Handy) arrives with hopCount=3 which
    // equals maxHops=3. This is valid for delivery, only invalid for forwarding.
    // Phase 2: check both userId and deviceNodeId maps
    if (_identities.containsKey(targetHex) || _identitiesByDeviceId.containsKey(targetHex)) {
      // Record in budget
      _relayBudget.recordRelay(
        relayId: relayIdBytes,
        originNodeId: Uint8List.fromList(relay.originNodeId),
        payloadSize: relay.wrappedEnvelope.length,
      );
      _log.info('Relay: delivering to local identity ${targetHex.substring(0, 8)}');

      // Confirm relay neighbor: this neighbor successfully delivered
      // a relay message to us → reliable relay partner.
      // Phase 2: use routing ID (deviceNodeId) for the forwarding node
      final relayNeighborRoutingId = _routingIdFromEnvelope(envelope);
      final relayNeighborHex = bytesToHex(relayNeighborRoutingId);
      if (!_isLocalIdentity(relayNeighborHex)) {
        dvRouting.confirmRelayNeighbor(relayNeighborHex);
      }

      // Learn relay route back to the original sender.
      // The envelope.senderId is the relay node that forwarded this to us —
      // we can reach the origin through that relay.
      if (relay.originNodeId.isNotEmpty) {
        final originId = Uint8List.fromList(relay.originNodeId);
        final originHex = bytesToHex(originId);
        // Phase 2: relay route via the specific DEVICE that forwarded
        final relayNodeId = relayNeighborRoutingId;
        final relayHex = relayNeighborHex;

        // Guard: relay via origin itself = circular (sender forwarded directly)
        if (relayHex != originHex && !_isLocalIdentity(relayHex)) {
          var originPeer = routingTable.getPeer(originId) ??
              routingTable.getPeerByUserId(originId);
          if (originPeer == null) {
            originPeer = PeerInfo(nodeId: originId, networkChannel: networkChannel);
            routingTable.addPeer(originPeer);
          }
          originPeer.relayViaNodeId = relayNodeId;
          originPeer.relaySetAt = DateTime.now();
          _log.info('Relay route learned (delivery): ${originHex.substring(0, 8)} '
              'via ${relayHex.substring(0, 8)}');
        } else {
          _log.debug('Relay route skipped (circular): ${originHex.substring(0, 8)} '
              'via ${relayHex.substring(0, 8)}');
        }
      }

      // Process inner envelope with from=0.0.0.0 so _touchPeer does NOT
      // associate the sender's nodeId with the relay node's IP address.
      try {
        final inner = proto.MessageEnvelope.fromBuffer(relay.wrappedEnvelope);
        final innerType = inner.messageType;
        final innerSender = inner.senderId.isNotEmpty
            ? bytesToHex(Uint8List.fromList(inner.senderId)).substring(0, 8)
            : 'empty';
        final innerMsgId = inner.messageId.isNotEmpty
            ? bytesToHex(Uint8List.fromList(inner.messageId)).substring(0, 8)
            : 'empty';
        _log.info('Relay inner: type=$innerType sender=$innerSender msgId=$innerMsgId');
        _onEnvelopeReceived(inner, InternetAddress('0.0.0.0'), 0, skipRateLimit: true);
      } catch (e) {
        _log.warn('Relay: failed to parse inner envelope: $e');
      }
      _sendRelayAck(relay, delivered: true);
      onRelayBytes?.call(relay.wrappedEnvelope.length);
      return;
    }

    // Forward to target or next hop — full validation for forwarding
    // (hop limit, TTL, payload size, budget). Local delivery above skips these.
    final rejection = _relayBudget.checkRelay(
      relayId: relayIdBytes,
      originNodeId: Uint8List.fromList(relay.originNodeId),
      payloadSize: relay.wrappedEnvelope.length,
      hopCount: relay.hopCount,
      maxHopsField: relay.maxHops,
      createdAtMs: relay.createdAtMs.toInt(),
    );
    if (rejection != null) {
      _log.debug('Relay rejected ($relayIdHex): $rejection');
      return;
    }
    _relayBudget.recordRelay(
      relayId: relayIdBytes,
      originNodeId: Uint8List.fromList(relay.originNodeId),
      payloadSize: relay.wrappedEnvelope.length,
    );

    () async {
      try {
        // V3 TTL check: ttl>0 means V3 message, ttl=0 means pre-V3 (backwards compatible)
        if (relay.ttl > 0 && relay.ttl <= 1) {
          _log.debug('Relay: TTL expired ($relayIdHex), ttl=${relay.ttl}');
          return;
        }

        final nextRelay = proto.RelayForward()
          ..relayId = relay.relayId
          ..finalRecipientId = relay.finalRecipientId
          ..wrappedEnvelope = relay.wrappedEnvelope
          ..hopCount = relay.hopCount + 1
          ..maxHops = relay.maxHops
          ..ttl = relay.ttl > 0 ? relay.ttl - 1 : 0  // Decrement (0 = not set)
          ..originNodeId = relay.originNodeId
          ..createdAtMs = relay.createdAtMs;
        nextRelay.visitedNodes.addAll(relay.visitedNodes);
        // Phase 2: add deviceNodeId to visited (per-device loop prevention)
        for (final identity in _identities.values) {
          nextRelay.visitedNodes.add(identity.deviceNodeId);
        }

        final nextEnvelope = primaryIdentity.createSignedEnvelope(
          proto.MessageType.RELAY_FORWARD,
          nextRelay.writeToBuffer(),
        );

        // Compute visited set early — needed for relay route + candidate checks
        final visitedSet = nextRelay.visitedNodes
            .map((n) => bytesToHex(Uint8List.fromList(n)))
            .toSet();

        // Try delivery to the final recipient
        // Phase 2: try deviceNodeId first, then userId fallback
        final peer = routingTable.getPeer(targetId) ??
            routingTable.getPeerByUserId(targetId);
        if (peer != null) {
          // Direct DV neighbor: send directly, skip learned relay route.
          // Learned relay routes create unnecessary hops when the target is
          // a direct neighbor (e.g., Bootstrap→Bob→Alice instead of Bootstrap→Alice).
          // This also ensures correct relay-route learning on the recipient side.
          final targetDvRoute = dvRouting.bestRouteTo(targetHex);
          final isDirectNeighbor = targetDvRoute != null && targetDvRoute.isDirect;

          // Use learned relay route ONLY for non-direct peers.
          // For direct neighbors, always try direct first.
          if (!isDirectNeighbor && peer.hasValidRelayRoute) {
            final relayNode = routingTable.getPeer(peer.relayViaNodeId!);
            if (relayNode != null && !visitedSet.contains(relayNode.nodeIdHex)) {
              nextEnvelope.recipientId = relayNode.nodeId;
              final ok = await _sendEnvelopeToPeer(nextEnvelope, relayNode);
              if (ok) {
                _log.info('Relay: forwarded via learned relay '
                    '${relayNode.nodeIdHex.substring(0, 8)} for '
                    '${targetHex.substring(0, 8)} (hop ${nextRelay.hopCount})');
                final storeIdHex = bytesToHex(Uint8List.fromList(relay.relayId));
                peerMessageStore.storeMessage(
                  recipientNodeId: targetId,
                  wrappedEnvelope: Uint8List.fromList(relay.wrappedEnvelope),
                  storeIdHex: 'relay-bs-$storeIdHex',
                );
                _sendRelayAck(relay, delivered: false);
                onRelayBytes?.call(relay.wrappedEnvelope.length);
                return;
              }
            }
          }

          // Direct send — trust only for direct DV neighbors (same transport path).
          // For non-neighbors (public/CGNAT), UDP "success" ≠ delivery.
          nextEnvelope.recipientId = peer.nodeId;
          final ok = await _sendEnvelopeToPeer(nextEnvelope, peer);
          if (ok && isDirectNeighbor) {
            _log.info('Relay: forwarded to target ${targetHex.substring(0, 8)} (hop ${nextRelay.hopCount})');
            final storeIdHex = bytesToHex(Uint8List.fromList(relay.relayId));
            peerMessageStore.storeMessage(
              recipientNodeId: targetId,
              wrappedEnvelope: Uint8List.fromList(relay.wrappedEnvelope),
              storeIdHex: 'relay-bs-$storeIdHex',
            );
            _sendRelayAck(relay, delivered: false);
            onRelayBytes?.call(relay.wrappedEnvelope.length);
            return;
          }
          // Non-neighbor: direct send attempted but unconfirmed — fall through
          // to DV routing for reliable multi-hop delivery.
        }

        // Target not reachable directly — try DV routing next-hop
        final dvRoutes = dvRouting.routesTo(targetHex);
        for (final route in dvRoutes) {
          if (!route.isAlive || route.isDirect) continue;
          if (route.nextHop == null) continue;
          final nhHex = bytesToHex(route.nextHop!);
          if (visitedSet.contains(nhHex)) continue;
          final nextHopPeer = routingTable.getPeer(route.nextHop!);
          if (nextHopPeer != null) {
            nextEnvelope.recipientId = nextHopPeer.nodeId;
            final ok = await _sendEnvelopeToPeer(nextEnvelope, nextHopPeer);
            if (ok) {
              _log.info('Relay: forwarded via DV next-hop '
                  '${nhHex.substring(0, 8)} for ${targetHex.substring(0, 8)} '
                  '(hop ${nextRelay.hopCount})');
              final storeIdHex = bytesToHex(Uint8List.fromList(relay.relayId));
              peerMessageStore.storeMessage(
                recipientNodeId: targetId,
                wrappedEnvelope: Uint8List.fromList(relay.wrappedEnvelope),
                storeIdHex: 'relay-bs-$storeIdHex',
              );
              _sendRelayAck(relay, delivered: false);
              onRelayBytes?.call(relay.wrappedEnvelope.length);
              return;
            }
          }
        }

        // Fallback: forward to generic relay candidates
        final candidates = findRelayCandidates(targetId)
            .where((p) => !visitedSet.contains(p.nodeIdHex))
            .toList();

        if (candidates.isNotEmpty) {
          for (final candidate in candidates) {
            nextEnvelope.recipientId = candidate.nodeId;
            final ok = await _sendEnvelopeToPeer(nextEnvelope, candidate);
            if (ok) {
              _log.info('Relay: forwarded to ${candidate.nodeIdHex.substring(0, 8)} '
                  '(hop ${nextRelay.hopCount})');
              _sendRelayAck(relay, delivered: false);
              onRelayBytes?.call(relay.wrappedEnvelope.length);
              return;
            }
          }
        }

        // All delivery attempts failed — store locally for later PEER_RETRIEVE.
        // This is the key fix for large packets (e.g. CR-Response ~4KB with PQ keys)
        // that can't be delivered via UDP fragmentation to NAT'd mobile devices.
        final storeIdHex = bytesToHex(Uint8List.fromList(relay.relayId));
        final stored = peerMessageStore.storeMessage(
          recipientNodeId: targetId,
          wrappedEnvelope: Uint8List.fromList(relay.wrappedEnvelope),
          storeIdHex: 'relay-$storeIdHex',
        );
        if (stored) {
          _log.info('Relay: stored for later retrieval by ${targetHex.substring(0, 8)} ($relayIdHex)');
        } else {
          _log.debug('Relay: could not deliver, forward, or store ($relayIdHex)');
        }
      } catch (e) {
        _log.warn('Relay forward error: $e');
      }
    }();
  }

  /// Handle an incoming RELAY_ACK — learn relay route if delivered.
  void _handleRelayAck(proto.MessageEnvelope envelope) {
    try {
      final ack = proto.RelayAck.fromBuffer(envelope.encryptedPayload);
      final relayIdHex = bytesToHex(Uint8List.fromList(ack.relayId));

      final info = _pendingRelays.remove(relayIdHex);
      if (info == null) {
        _log.debug('Relay ACK: $relayIdHex (no pending entry)');
        return;
      }

      if (ack.delivered) {
        // Learn relay route: this relay peer can reach the target.
        // Guard against circular routes: relayedBy must NOT equal the target.
        // Phase 2: try deviceNodeId first, then userId fallback
        final peer = routingTable.getPeer(info.recipientNodeId) ??
            routingTable.getPeerByUserId(info.recipientNodeId);
        if (peer != null) {
          final relayVia = ack.relayedBy.isNotEmpty
              ? Uint8List.fromList(ack.relayedBy)
              : Uint8List.fromList(info.relayPeerNodeId);
          final relayViaHex = bytesToHex(relayVia);
          if (relayViaHex != peer.nodeIdHex) {
            peer.relayViaNodeId = relayVia;
            peer.relaySetAt = DateTime.now();
            _log.info('Relay route learned: ${peer.nodeIdHex.substring(0, 8)} '
                'via ${relayViaHex.substring(0, 8)}');
          } else {
            _log.debug('Relay ACK: ignoring circular route for ${peer.nodeIdHex.substring(0, 8)}');
          }
        }
      } else {
        _log.debug('Relay ACK: $relayIdHex not delivered');
      }
    } catch (e) {
      _log.debug('Relay ACK parse error: $e');
    }
  }

  /// Send a RELAY_ACK back towards the origin.
  /// Uses the origin's relay route if available (origin may only be reachable via relay).
  void _sendRelayAck(proto.RelayForward relay, {required bool delivered}) {
    final originId = Uint8List.fromList(relay.originNodeId);
    final peer = routingTable.getPeer(originId);
    if (peer == null) return;

    final ack = proto.RelayAck()
      ..relayId = relay.relayId
      ..delivered = delivered
      ..relayedBy = primaryIdentity.deviceNodeId;  // Phase 2: per-device relay identity

    final ackEnvelope = primaryIdentity.createSignedEnvelope(
      proto.MessageType.RELAY_ACK,
      ack.writeToBuffer(),
      recipientId: originId,
    );

    // RELAY_ACK must NEVER be wrapped in RELAY_FORWARD — that causes an
    // infinite loop (each side sends RELAY_ACK for received RELAY_FORWARD,
    // which triggers another RELAY_ACK on the other side).
    // Direct send only. If unreachable, the ACK is lost — that's OK because
    // DELIVERY_RECEIPT provides end-to-end confirmation via the normal cascade.
    _sendEnvelopeToPeer(ackEnvelope, peer);
  }

  /// Find relay candidates: recently reachable peers, sorted by RTT.
  /// Uses 10-minute window (not 2 min) — peers behind AP isolation may have
  /// infrequent but valid connections (e.g. relay-forwarded messages).
  List<PeerInfo> findRelayCandidates(Uint8List recipientNodeId, {int count = 5}) {
    final recipientHex = bytesToHex(recipientNodeId);
    final localIds = _identities.keys.toSet();

    final candidates = routingTable.allPeers
        .where((p) => p.nodeIdHex != recipientHex)
        .where((p) => !localIds.contains(p.nodeIdHex))
        .where((p) => p.allConnectionTargets().isNotEmpty)
        .toList();

    // Sort: prefer dual-stack (can bridge IPv4↔IPv6), then score, then RTT
    candidates.sort((a, b) {
      // Dual-stack nodes can bridge — prefer them as relays (§27)
      final dualA = (a.capabilities & PeerCapabilities.dualStack) == PeerCapabilities.dualStack ? 1 : 0;
      final dualB = (b.capabilities & PeerCapabilities.dualStack) == PeerCapabilities.dualStack ? 1 : 0;
      if (dualA != dualB) return dualB.compareTo(dualA);
      final scoreA = a.allConnectionTargets().fold(0.0, (s, addr) => s + addr.score);
      final scoreB = b.allConnectionTargets().fold(0.0, (s, addr) => s + addr.score);
      if (scoreA != scoreB) return scoreB.compareTo(scoreA);
      final rttA = dhtRpc.getRtt(a.nodeId).inMilliseconds;
      final rttB = dhtRpc.getRtt(b.nodeId).inMilliseconds;
      return rttA.compareTo(rttB);
    });

    return candidates.take(count).toList();
  }

  // ── Distance-Vector Routing (V3) ───────────────────────────────────

  void _handleRouteUpdate(proto.MessageEnvelope envelope) {
    if (envelope.senderId.isEmpty) return;
    try {
      final msg = proto.RouteUpdateMsg.fromBuffer(envelope.encryptedPayload);
      // Phase 2: route updates come from a specific DEVICE
      final fromNodeId = _routingIdFromEnvelope(envelope);
      final fromHex = bytesToHex(fromNodeId);

      final entries = msg.routes.map((r) => RouteEntry(
        destinationHex: bytesToHex(Uint8List.fromList(r.destination)),
        hopCount: r.hopCount,
        cost: r.cost,
        connType: _connTypeFromProto(r.connType),
      )).toList();

      final changed = dvRouting.processRouteUpdate(fromNodeId, entries);
      if (changed) {
        dvRouting.updateDefaultGateway();
      }
      _log.info('DV: Route update from ${fromHex.substring(0, 8)}: ${entries.length} entries, changed=$changed, '
          'gwHex=${dvRouting.defaultGatewayHex?.substring(0, 8)}, routes=${dvRouting.routeCount}, '
          'neighbors=${dvRouting.neighbors.length}');

      // Reciprocal welcome: if neighbor sent empty/minimal update (likely just
      // restarted), respond with our full table so they can rebuild routes.
      if (entries.isEmpty && dvRouting.neighbors.containsKey(fromHex)) {
        final ourRoutes = dvRouting.buildFullUpdate();
        if (ourRoutes.isNotEmpty) {
          final peer = routingTable.getPeer(fromNodeId);
          if (peer != null) {
            _sendRouteUpdate(peer, ourRoutes);
            _lastRouteUpdateSentTo[fromHex] = DateTime.now();
            _log.info('DV: Reciprocal welcome sent ${ourRoutes.length} routes to ${fromHex.substring(0, 8)} (peer restart detected)');
          }
        }
      }
    } catch (e) {
      _log.debug('DV: Failed to parse ROUTE_UPDATE: $e');
    }
  }

  /// Debounced route propagation: collects changes and sends after 2s.
  void _onDvRouteChanged(String destHex, int cost) {
    _dvPendingChanges.add(destHex);
    _dvPropagationDebounce?.cancel();
    _dvPropagationDebounce = Timer(const Duration(seconds: 2), _flushDvUpdates);
  }

  void _flushDvUpdates() {
    if (_dvPendingChanges.isEmpty) return;
    final changes = _dvPendingChanges.length;
    _dvPendingChanges.clear();

    // For each neighbor an individual update (Split Horizon)
    var sent = 0;
    final now = DateTime.now();
    for (final neighborHex in dvRouting.neighbors.keys) {
      final entries = dvRouting.buildUpdateFor(neighborHex);
      if (entries.isEmpty) continue;

      final peer = routingTable.getPeer(hexToBytes(neighborHex));
      if (peer == null) continue;

      _sendRouteUpdate(peer, entries);
      _lastRouteUpdateSentTo[neighborHex] = now;
      sent++;
    }
    if (sent > 0) {
      _log.debug('DV: Flush sent updates to $sent neighbors ($changes pending changes)');
    }

    // Drain queued messages for destinations that now have routes
    if (messageQueue.totalMessages > 0) {
      messageQueue.drainAll((recipientHex) {
        final routes = dvRouting.routesTo(recipientHex);
        return routes.any((r) => r.isAlive) ||
            routingTable.getPeer(hexToBytes(recipientHex)) != null;
      });
    }
  }

  void _sendRouteUpdate(PeerInfo peer, List<RouteEntry> entries) {
    final msg = proto.RouteUpdateMsg();
    for (final e in entries) {
      msg.routes.add(proto.RouteEntryProto()
        ..destination = hexToBytes(e.destinationHex)
        ..hopCount = e.hopCount
        ..cost = e.cost
        ..connType = _connTypeToProto(e.connType)
        ..lastConfirmedMs = Int64(DateTime.now().millisecondsSinceEpoch));
    }

    final envelope = _createEnvelope(proto.MessageType.ROUTE_UPDATE);
    envelope.encryptedPayload = msg.writeToBuffer();
    envelope.recipientId = peer.nodeId;
    _sendEnvelopeToPeer(envelope, peer);
  }

  /// Safety-Net: full route exchange with all neighbors every 1h.
  void _dvSafetyNetExchange() {
    final fullUpdate = dvRouting.buildFullUpdate();
    if (fullUpdate.isEmpty) return;

    for (final neighborHex in dvRouting.neighbors.keys) {
      final peer = routingTable.getPeer(hexToBytes(neighborHex));
      if (peer == null) continue;
      // For safety-net no Split Horizon — send all routes
      _sendRouteUpdate(peer, fullUpdate);
    }
    _log.debug('DV: Safety-net exchange sent ${fullUpdate.length} routes to ${dvRouting.neighbors.length} neighbors');
    // Update catch-up timestamps for all neighbors
    final now = DateTime.now();
    for (final neighborHex in dvRouting.neighbors.keys) {
      _lastRouteUpdateSentTo[neighborHex] = now;
    }
  }

  /// Welcome-Update: send full route table to a newly discovered neighbor.
  /// Called 500ms after addDirectNeighbor (to let _touchPeer populate routing table).
  /// Always sends, even if our table is empty — this acts as a "hello" signal
  /// that tells the peer we (re)started and need their routes.
  void _sendWelcomeRouteUpdate(String neighborHex) {
    final peer = routingTable.getPeer(hexToBytes(neighborHex));
    if (peer == null) {
      _log.debug('DV: Welcome skipped for ${neighborHex.substring(0, 8)} — not in routing table');
      return;
    }
    // Use buildFullUpdate (no Split Horizon) — new peer has no routes from us yet.
    // Send even if empty — recipient detects restart and responds with their table.
    final fullUpdate = dvRouting.buildFullUpdate();
    _sendRouteUpdate(peer, fullUpdate);
    _lastRouteUpdateSentTo[neighborHex] = DateTime.now();
    _log.info('DV: Welcome update sent ${fullUpdate.length} routes to ${neighborHex.substring(0, 8)}');
  }

  /// Catch-up: if we haven't sent a route update to this neighbor in >60s,
  /// send a full update now. Covers returning peers whose route never went DOWN.
  void _maybeSendCatchUpRouteUpdate(String neighborHex) {
    final lastSent = _lastRouteUpdateSentTo[neighborHex];
    if (lastSent != null && DateTime.now().difference(lastSent).inSeconds < 60) {
      return; // Recent update — no catch-up needed
    }
    final peer = routingTable.getPeer(hexToBytes(neighborHex));
    if (peer == null) return;
    final fullUpdate = dvRouting.buildFullUpdate();
    if (fullUpdate.isEmpty) return;
    _sendRouteUpdate(peer, fullUpdate);
    _lastRouteUpdateSentTo[neighborHex] = DateTime.now();
    _log.info('DV: Catch-up update sent ${fullUpdate.length} routes to ${neighborHex.substring(0, 8)}');
  }

  // ── Hole Punch Success Callback ────────────────────────────────────

  void _onHolePunchSuccess(Uint8List peerNodeId, String ip, int port) {
    final peerHex = bytesToHex(peerNodeId);
    _log.info('Hole punch succeeded: ${peerHex.substring(0, 8)} at $ip:$port');

    // Add/update punched address in peer's address list
    final peer = routingTable.getPeer(peerNodeId);
    if (peer != null) {
      // Add the punched public address
      final addr = PeerAddress(
        ip: ip,
        port: port,
        type: PeerAddressType.ipv4Public,
      );
      addr.recordSuccess();
      final key = '$ip:$port';
      peer.addresses.removeWhere((a) => '${a.ip}:${a.port}' == key);
      peer.addresses.insert(0, addr);

      // Register as DV neighbor with holePunch connection type
      dvRouting.addDirectNeighbor(peerNodeId, ConnectionType.holePunch);
    }
  }

  // ── Port Mapper Event Handler ─────────────────────────────────

  void _onPortMapperEvent(PortMapperEvent event) {
    switch (event.type) {
      case PortMapperEventType.mappingAcquired:
      case PortMapperEventType.mappingRenewed:
        if (event.mapping != null) {
          final m = event.mapping!;
          natTraversal.setPortMapping(m.externalIp, m.externalPort);
          _log.info('Port mapping ${event.type.name}: '
              '${m.externalIp}:${m.externalPort} via ${event.source}');
          // Broadcast updated address to peers
          _broadcastAddressUpdate();
        }
      case PortMapperEventType.mappingLost:
        natTraversal.clearPortMapping();
        _log.info('Port mapping lost — falling back to hole punch');
      case PortMapperEventType.externalIpDiscovered:
        if (event.externalIp != null && event.externalIp != '0.0.0.0') {
          // Store for NAT context only. Port reachability is verified
          // separately by mappingAcquired (UPnP AddPortMapping / NAT-PMP).
          // Without verified port mapping, advertising this IP would cause
          // peers to send to a closed port — silently dropped by the router.
          natTraversal.setExternalIpOnly(event.externalIp!);
          // V3.1.33: Active port probe — ask an Internet peer to verify
          // reachability by sending a CPRB packet to our public IP:port.
          // Detects manual DNAT, UPnP on a different router, etc.
          _initiatePortProbe(event.externalIp!);
        }
    }
  }

  // ── Port Probe (V3.1.33) ────────────────────────────────────────────
  // Verify public port reachability by asking a confirmed Internet peer
  // to send a CPRB probe packet to our claimed public IP:port.

  /// Pending probe: probeIdHex → externalIp
  final Map<String, String> _pendingPortProbes = {};
  Timer? _portProbeTimer;

  /// Initiate a port probe after discovering external IP without port mapping.
  void _initiatePortProbe(String externalIp) {
    // Find a confirmed peer with a public IP (Internet peer) to act as prober
    final candidates = routingTable.allPeers
        .where((p) => _confirmedPeers.contains(p.nodeIdHex))
        .where((p) => p.publicIp.isNotEmpty && !_isPrivateIp(p.publicIp))
        .toList();

    if (candidates.isEmpty) {
      // No Internet peer available — try any confirmed peer
      // (might work if they can route to our public IP)
      final fallback = routingTable.allPeers
          .where((p) => _confirmedPeers.contains(p.nodeIdHex))
          .where((p) => !_isLocalIdentity(p.nodeIdHex))
          .toList();
      if (fallback.isEmpty) {
        _log.debug('Port probe: no confirmed peer available');
        return;
      }
      candidates.addAll(fallback.take(2));
    }

    final probeId = SodiumFFI().randomBytes(16);
    final probeIdHex = bytesToHex(probeId);
    _pendingPortProbes[probeIdHex] = externalIp;

    // Send probe request to up to 2 candidates
    for (final prober in candidates.take(2)) {
      final query = proto.PeerReachabilityQuery(
        targetNodeId: primaryIdentity.deviceNodeId,
        queryId: probeId,
        probeIp: externalIp,
        probePort: port,
      );
      final envelope = primaryIdentity.createSignedEnvelope(
        proto.MessageType.REACHABILITY_QUERY,
        query.writeToBuffer(),
        recipientId: prober.nodeId,
      );
      sendEnvelope(envelope, prober.nodeId);
      _log.info('Port probe request sent to ${prober.nodeIdHex.substring(0, 8)} '
          'for $externalIp:$port');
    }

    // Timeout: 5 seconds
    _portProbeTimer?.cancel();
    _portProbeTimer = Timer(const Duration(seconds: 5), () {
      if (_pendingPortProbes.remove(probeIdHex) != null) {
        _log.info('Port probe TIMEOUT for $externalIp:$port '
            '— port not reachable from outside');
      }
    });
  }

  /// Handle incoming CPRB port probe packet.
  void _onPortProbeReceived(Uint8List probeId, InternetAddress from, int fromPort) {
    final probeIdHex = bytesToHex(probeId);
    final externalIp = _pendingPortProbes.remove(probeIdHex);
    if (externalIp == null) {
      _log.debug('Port probe received but no pending probe for ${probeIdHex.substring(0, 8)}');
      return;
    }
    _portProbeTimer?.cancel();

    _log.info('Port probe SUCCESS — $externalIp:$port is reachable from outside! '
        '(probe from ${from.address}:$fromPort)');
    natTraversal.confirmPublicAddress(externalIp, port);
    _broadcastAddressUpdate();
  }

  /// Try to initiate a hole punch for a public-IP peer.
  /// Called when we learn about a peer with a public IP but can't reach them directly.
  void tryHolePunch(Uint8List targetNodeId) {
    if (!natTraversal.hasPublicIp) return;
    if (natTraversal.isPunchInProgress(targetNodeId)) return;

    final targetHex = bytesToHex(targetNodeId);
    if (natTraversal.hasPunchedConnection(targetHex)) return;

    // Find a coordinator: a confirmed peer that knows both us and the target.
    // Default-Gateway is a good choice.
    final gwHex = dvRouting.defaultGatewayHex;
    if (gwHex == null) return;
    if (gwHex == targetHex) return; // Can't coordinate via the target itself

    final gwNodeId = hexToBytes(gwHex);
    natTraversal.initiateHolePunch(targetNodeId, gwNodeId);
  }

  static proto.ConnectionTypeProto _connTypeToProto(ConnectionType ct) {
    switch (ct) {
      case ConnectionType.lanSameSubnet:  return proto.ConnectionTypeProto.CT_LAN_SAME_SUBNET;
      case ConnectionType.lanOtherSubnet: return proto.ConnectionTypeProto.CT_LAN_OTHER_SUBNET;
      case ConnectionType.wifiDirect:     return proto.ConnectionTypeProto.CT_WIFI_DIRECT;
      case ConnectionType.publicUdp:      return proto.ConnectionTypeProto.CT_PUBLIC_UDP;
      case ConnectionType.holePunch:      return proto.ConnectionTypeProto.CT_HOLE_PUNCH;
      case ConnectionType.relay:          return proto.ConnectionTypeProto.CT_RELAY;
      case ConnectionType.mobile:         return proto.ConnectionTypeProto.CT_MOBILE;
      case ConnectionType.mobileRelay:    return proto.ConnectionTypeProto.CT_MOBILE_RELAY;
    }
  }

  static ConnectionType _connTypeFromProto(proto.ConnectionTypeProto ct) {
    switch (ct) {
      case proto.ConnectionTypeProto.CT_LAN_SAME_SUBNET:  return ConnectionType.lanSameSubnet;
      case proto.ConnectionTypeProto.CT_LAN_OTHER_SUBNET: return ConnectionType.lanOtherSubnet;
      case proto.ConnectionTypeProto.CT_WIFI_DIRECT:      return ConnectionType.wifiDirect;
      case proto.ConnectionTypeProto.CT_PUBLIC_UDP:        return ConnectionType.publicUdp;
      case proto.ConnectionTypeProto.CT_HOLE_PUNCH:       return ConnectionType.holePunch;
      case proto.ConnectionTypeProto.CT_RELAY:             return ConnectionType.relay;
      case proto.ConnectionTypeProto.CT_MOBILE:            return ConnectionType.mobile;
      case proto.ConnectionTypeProto.CT_MOBILE_RELAY:      return ConnectionType.mobileRelay;
      default:                                              return ConnectionType.publicUdp;
    }
  }

  // ── Getters ────────────────────────────────────────────────────────

  String get nodeIdHex => primaryIdentity.nodeIdHex;
  String get localIp => _localIp;
  List<String> get localIps => _localIps;
  bool get isRunning => _running;

  /// Get own PeerInfo for sharing (QR code, etc.).
  PeerInfo get ownPeerInfo => _ownPeerInfo();

  // ── Shutdown ───────────────────────────────────────────────────────

  Future<void> stop() async {
    _running = false;
    _maintenanceTimer?.cancel();
    _peerExchangeTimer?.cancel();
    _dvSafetyNetTimer?.cancel();
    _dvPropagationDebounce?.cancel();
    localDiscovery.stop();
    multicastDiscovery.stop();
    ackTracker.dispose();
    reachabilityProbe.dispose();
    natTraversal.dispose();
    _portMapperSub?.cancel();
    await portMapper.dispose();
    await peerMessageStore.dispose();
    await messageQueue.dispose();
    dhtRpc.dispose();
    _saveRoutingTable();
    await reputationManager.save(profileDir);
    await transport.stop();
    _log.info('Node stopped');
  }

  // ── Reachability Query Handler ──────────────────────────────────

  void _handleReachabilityQuery(proto.MessageEnvelope envelope, InternetAddress from, int fromPort) {
    try {
      final query = proto.PeerReachabilityQuery.fromBuffer(envelope.encryptedPayload);

      // V3.1.33: Port probe — send CPRB packet to sender's claimed public address
      if (query.probeIp.isNotEmpty && query.probePort > 0) {
        final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
        final senderDeviceHex = envelope.senderDeviceNodeId.isNotEmpty
            ? bytesToHex(Uint8List.fromList(envelope.senderDeviceNodeId))
            : senderHex;
        // Security: only probe for confirmed peers (check both userId and deviceNodeId)
        if (!_confirmedPeers.contains(senderHex) &&
            !_confirmedPeers.contains(senderDeviceHex)) {
          _log.debug('Port probe rejected: ${senderHex.substring(0, 8)} not confirmed');
          return;
        }
        if (_isPrivateIp(query.probeIp)) {
          _log.debug('Port probe rejected: ${query.probeIp} is private');
          return;
        }
        _log.info('Port probe: sending CPRB to ${query.probeIp}:${query.probePort} '
            'for ${senderHex.substring(0, 8)}');
        transport.sendPortProbe(
          Uint8List.fromList(query.queryId),
          InternetAddress(query.probeIp),
          query.probePort,
        );
        return;
      }

      // Normal reachability query (relay route discovery)
      final targetId = Uint8List.fromList(query.targetNodeId);
      final targetHex = bytesToHex(targetId);
      final peer = routingTable.getPeer(targetId);
      final confirmed = _confirmedPeers.contains(targetHex);

      final response = proto.PeerReachabilityResponse()
        ..targetNodeId = query.targetNodeId
        ..queryId = query.queryId
        ..canReach = (peer != null && confirmed)
        ..lastSeenMs = Int64(peer?.lastSeen.millisecondsSinceEpoch ?? 0);

      final respEnvelope = primaryIdentity.createSignedEnvelope(
        proto.MessageType.REACHABILITY_RESPONSE,
        response.writeToBuffer(),
        recipientId: Uint8List.fromList(envelope.senderId),
      );
      sendEnvelope(respEnvelope, Uint8List.fromList(envelope.senderId));
      _log.debug('Reachability query for ${targetHex.substring(0, 8)}: '
          'canReach=${peer != null && confirmed}');
    } catch (e) {
      _log.debug('REACHABILITY_QUERY parse error: $e');
    }
  }

  // ── Store-and-Forward Handlers ──────────────────────────────────

  void _handlePeerStore(proto.MessageEnvelope envelope, InternetAddress from, int fromPort) {
    try {
      final store = proto.PeerStore.fromBuffer(envelope.encryptedPayload);
      final storeIdHex = bytesToHex(Uint8List.fromList(store.storeId));
      final recipientId = Uint8List.fromList(store.recipientNodeId);

      final accepted = peerMessageStore.storeMessage(
        recipientNodeId: recipientId,
        wrappedEnvelope: Uint8List.fromList(store.wrappedEnvelope),
        storeIdHex: storeIdHex,
        ttlMs: store.ttlMs.toInt(),
      );

      // Send ACK
      final ack = proto.PeerStoreAck()
        ..storeId = store.storeId
        ..accepted = accepted;
      final ackEnv = primaryIdentity.createSignedEnvelope(
        proto.MessageType.PEER_STORE_ACK,
        ack.writeToBuffer(),
        recipientId: Uint8List.fromList(envelope.senderId),
      );
      sendEnvelope(ackEnv, Uint8List.fromList(envelope.senderId));
    } catch (e) {
      _log.debug('PEER_STORE parse error: $e');
    }
  }

  void _handlePeerRetrieve(proto.MessageEnvelope envelope, InternetAddress from, int fromPort) {
    try {
      final retrieve = proto.PeerRetrieve.fromBuffer(envelope.encryptedPayload);
      final requesterId = Uint8List.fromList(retrieve.requesterNodeId);

      final messages = peerMessageStore.retrieveMessages(requesterId);

      final response = proto.PeerRetrieveResponse()
        ..remaining = 0;
      for (final msg in messages) {
        response.storedEnvelopes.add(msg);
      }

      final respEnv = primaryIdentity.createSignedEnvelope(
        proto.MessageType.PEER_RETRIEVE_RESPONSE,
        response.writeToBuffer(),
        recipientId: Uint8List.fromList(envelope.senderId),
      );
      sendEnvelope(respEnv, Uint8List.fromList(envelope.senderId));
      _log.info('PEER_RETRIEVE: sent ${messages.length} stored messages to '
          '${bytesToHex(requesterId).substring(0, 8)}');
    } catch (e) {
      _log.debug('PEER_RETRIEVE parse error: $e');
    }
  }

  void _handlePeerRetrieveResponse(proto.MessageEnvelope envelope) {
    try {
      final response = proto.PeerRetrieveResponse.fromBuffer(envelope.encryptedPayload);
      _log.info('PEER_RETRIEVE_RESPONSE: ${response.storedEnvelopes.length} messages '
          '(remaining: ${response.remaining})');

      for (final envBytes in response.storedEnvelopes) {
        try {
          final storedEnvelope = proto.MessageEnvelope.fromBuffer(envBytes);
          // Process as if received directly — the envelope has its own sender/recipient/signatures.
          // Use 0.0.0.0 so _touchPeer does NOT store the storage peer's IP as the sender's address.
          _onEnvelopeReceived(storedEnvelope, InternetAddress('0.0.0.0'), 0, skipRateLimit: true);
        } catch (e) {
          _log.debug('Failed to process stored envelope: $e');
        }
      }
    } catch (e) {
      _log.debug('PEER_RETRIEVE_RESPONSE parse error: $e');
    }
  }

  /// Store a message on mutual peers when direct+relay delivery fails.
  /// Architecture Section 3.3.7: Mutual Peer Selection — prefer peers known
  /// to both sender and recipient (shared contacts, shared group members).
  /// Falls back to any confirmed peer if fewer than 3 mutual peers available.
  Future<void> _storeOnPeers(proto.MessageEnvelope envelope, Uint8List recipientNodeId) async {
    final recipientHex = bytesToHex(recipientNodeId);
    const maxStorePeers = 3;

    // All confirmed online peers (excluding self and recipient)
    final allCandidates = routingTable.allPeers
        .where((p) => _confirmedPeers.contains(p.nodeIdHex))
        .where((p) => !routingTable.isLocalNode(p.nodeId))
        .where((p) => p.nodeIdHex != recipientHex && p.userIdHex != recipientHex)
        .toList();

    if (allCandidates.isEmpty) {
      _log.debug('No online peers for Store-and-Forward');
      return;
    }

    // Compute mutual peer set (Architecture Section 3.3.7)
    final mutualIds = getMutualPeerIds?.call(recipientNodeId) ?? <String>{};

    // Partition: mutual peers first, then fallback peers
    final mutualPeers = <PeerInfo>[];
    final fallbackPeers = <PeerInfo>[];
    for (final p in allCandidates) {
      if (mutualIds.contains(p.nodeIdHex)) {
        mutualPeers.add(p);
      } else {
        fallbackPeers.add(p);
      }
    }

    // Select up to maxStorePeers: mutual first, then fallback
    final selected = <PeerInfo>[];
    selected.addAll(mutualPeers.take(maxStorePeers));
    if (selected.length < maxStorePeers) {
      selected.addAll(fallbackPeers.take(maxStorePeers - selected.length));
    }

    final mutualCount = selected.where((p) => mutualIds.contains(p.nodeIdHex)).length;
    _log.info('S&F peer selection for ${recipientHex.substring(0, 8)}: '
        '${mutualPeers.length} mutual, ${fallbackPeers.length} fallback → '
        'selected $mutualCount mutual + ${selected.length - mutualCount} fallback');

    final sodium = SodiumFFI();
    // §26.6.2: KEY_ROTATION_BROADCAST gets a 30-day S&F TTL so offline
    // contacts can still receive the new pubkey after vacation / device swap.
    // All other messages keep the default 7-day TTL.
    final ttlMs = envelope.messageType == proto.MessageType.KEY_ROTATION_BROADCAST
        ? Int64(30 * 24 * 60 * 60 * 1000)
        : Int64(7 * 24 * 60 * 60 * 1000);
    var successCount = 0;
    for (final peer in selected) {
      final storeMsg = proto.PeerStore()
        ..recipientNodeId = recipientNodeId
        ..wrappedEnvelope = envelope.writeToBuffer()
        ..storeId = sodium.randomBytes(16)
        ..ttlMs = ttlMs;

      final storeEnv = primaryIdentity.createSignedEnvelope(
        proto.MessageType.PEER_STORE,
        storeMsg.writeToBuffer(),
        recipientId: peer.nodeId,
      );
      final ok = await _sendEnvelopeToPeer(storeEnv, peer);
      if (ok) successCount++;
    }

    _log.info('Store-and-Forward: $successCount/${selected.length} stores sent '
        'for ${recipientHex.substring(0, 8)}');
  }
}

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

PeerAddressType _classifyAddressType(String ip) {
  if (ip.contains(':')) return PeerAddressType.ipv6Global;
  return _isPrivateIp(ip) ? PeerAddressType.ipv4Private : PeerAddressType.ipv4Public;
}

/// Check if two private IPs are in the same /8 network class.
/// 10.x.x.x and 192.168.x.x are different networks (emulator NAT vs LAN).
/// Same-class peers are likely router-connected; different-class peers are behind
/// separate NATs and cannot reach each other directly.
bool _samePrivateNetwork(String ip1, String ip2) {
  final a = ip1.split('.').firstOrNull;
  final b = ip2.split('.').firstOrNull;
  if (a == null || b == null) return false;
  return a == b;
}
