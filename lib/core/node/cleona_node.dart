import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cleona/core/crypto/admission_pow.dart';
import 'package:cleona/core/crypto/device_signature.dart';
import 'package:cleona/core/crypto/device_kem.dart';
import 'package:cleona/core/crypto/device_keys_store.dart';
import 'package:cleona/core/crypto/hd_wallet.dart';
import 'package:cleona/core/crypto/network_secret.dart';
import 'package:cleona/core/crypto/proof_of_work.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/dht/kbucket.dart';
import 'package:cleona/core/dht/dht_rpc.dart';
import 'package:cleona/core/network/ack_tracker.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_message_store.dart';
import 'package:cleona/core/network/sender_identity_snapshot.dart';
import 'package:cleona/core/network/reachability_probe.dart';
import 'package:cleona/core/network/lan_discovery.dart';
import 'package:cleona/core/network/network_stats.dart';
import 'package:cleona/core/network/tls_fallback.dart';
import 'package:cleona/core/network/nat_traversal.dart';
import 'package:cleona/core/network/port_mapper.dart';
import 'package:cleona/core/network/udp_keepalive.dart';
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/core/network/dv_routing.dart';
import 'package:cleona/core/network/transport.dart';
import 'package:cleona/core/network/v3_frame_codec.dart';
import 'package:cleona/core/network/udp_fragmenter.dart';
import 'package:cleona/core/network/rate_limiter.dart';
import 'package:cleona/core/network/peer_reputation.dart';
import 'package:cleona/core/node/relay_budget.dart';
import 'package:cleona/core/node/identity_context.dart';
import 'package:cleona/core/identity_resolution/auth_manifest.dart';
import 'package:cleona/core/identity_resolution/device_kem_record.dart';
import 'package:cleona/core/identity_resolution/liveness_record.dart';
import 'package:cleona/core/identity_resolution/identity_dht_handler.dart';
import 'package:cleona/core/identity_resolution/identity_resolver.dart';
import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/network/rendezvous/infra_rendezvous_manager.dart';
import 'package:cleona/core/network/rendezvous/binary_rendezvous_manager.dart';
import 'package:cleona/core/network/rendezvous/rendezvous_manager.dart';
import 'package:fixnum/fixnum.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Atomic JSON write via tmp+rename (POSIX crash-safe).
void _atomicWriteJson(String path, Object json) {
  final file = File(path);
  final tmp = File('$path.tmp');
  file.parent.createSync(recursive: true);
  tmp.writeAsStringSync(jsonEncode(json), flush: true);
  if (Platform.isWindows && file.existsSync()) {
    file.deleteSync();
  }
  tmp.renameSync(path);
}

/// F2 (S123 UDP-dead RCA, 2026-07-03 Pixel field test): tracks the last time
/// an inbound packet PROVED our own sends are getting through (a reply to
/// something we sent: DHT_PONG / DELIVERY_RECEIPT / the generic infra-
/// response bridge). Extracted from [CleonaNode] as a standalone,
/// injectable-time class so the gate predicate is unit-testable
/// (`test/smoke/smoke_udp_dead_recovery.dart`) without spinning up a full
/// node.
///
/// Deliberately distinct from `_confirmedPeers`, which only proves the
/// RECEIVE path is alive (any inbound packet, including a receive-only
/// trickle from a peer whose replies to OUR sends never arrive). Field
/// forensics: a Bootstrap IPv6 trickle (~1.5 pkt/min) kept `_confirmedPeers`
/// fresh for 2h23min while the send path was black-holed by a WLAN-zombie
/// interface — every recovery gate built on `_confirmedPeers` alone stayed
/// permanently suppressed.
class OutboundLivenessTracker {
  OutboundLivenessTracker({Duration? window})
      : window = window ?? defaultWindow;

  /// Default window: 2 keepalive intervals (`UdpKeepalive.initialIntervalMs`,
  /// §7.6) so one full keepalive round-trip is covered even if the first
  /// ping in the window was lost, + 10s buffer for scheduling/RTT jitter.
  static const Duration defaultWindow = Duration(
    milliseconds: UdpKeepalive.initialIntervalMs * 2 + 10000,
  );

  final Duration window;
  DateTime? _lastConfirmedAt;

  /// Timestamp of the last outbound-confirming packet, if any.
  DateTime? get lastConfirmedAt => _lastConfirmedAt;

  /// Record an inbound packet that proves our own send reached the peer
  /// (and their reply reached us back).
  void noteConfirmed([DateTime? now]) {
    _lastConfirmedAt = now ?? DateTime.now();
  }

  /// Whether an outbound-confirming packet arrived within [window].
  bool recentlyConfirmed([DateTime? now]) {
    final ts = _lastConfirmedAt;
    if (ts == null) return false;
    final n = now ?? DateTime.now();
    return n.difference(ts) <= window;
  }
}

/// F1 (S123 UDP-dead RCA): tracks whether a dead-edge-triggered
/// `onNetworkChanged` rebind recently completed, so a SECOND dead-edge
/// shortly after can be recognized as "the rebind demonstrably did not
/// help" (rebind-on-anyIPv4/anyIPv6 stays on the same dead interface) and
/// escalate straight to the mobile-fallback probe. Extracted from
/// [CleonaNode] for the same unit-testability reason as
/// [OutboundLivenessTracker].
class DeadEdgeEscalationTracker {
  DeadEdgeEscalationTracker({this.window = const Duration(seconds: 60)});

  final Duration window;
  DateTime? _lastRebindCompletedAt;

  /// Record that a dead-edge-triggered rebind (`onNetworkChanged` from
  /// `onUdpSocketDead`) just finished.
  void noteRebindCompleted([DateTime? now]) {
    _lastRebindCompletedAt = now ?? DateTime.now();
  }

  /// Whether a NEW dead-edge arriving at [now] should escalate to mobile
  /// fallback — true if a rebind completed within [window].
  bool shouldEscalate([DateTime? now]) {
    final ts = _lastRebindCompletedAt;
    if (ts == null) return false;
    final n = now ?? DateTime.now();
    return n.difference(ts) < window;
  }
}

/// Central network component. Handles transport, DHT, discovery, and message dispatch.
/// Shared by all identities — one node, one port, one network stack.
class CleonaNode {
  /// Device-Sig-Keypair (Architecture v3.0 §3.5). One per daemon, shared by
  /// all hosted user identities — DeviceID is device-bound, not identity-bound.
  /// Loaded from `<baseDir>/device_keys.bin.enc` on start, lazy-created on
  /// first run via OS CSPRNG. Not seed-derived (per §3.6 #5).
  late final DeviceKeyBundle _deviceKeys;

  /// Read-only access for callers that build NetworkPacketV3 outers
  /// (cleona_service.sendToUser, relay-forward path).
  DeviceKeyPair get deviceKeyPair => _deviceKeys.sig;
  DeviceKemKeyPair get deviceKem => _deviceKeys.kem;

  final String profileDir;
  int port;
  final String networkChannel;
  final CLogger _log;

  /// Explicitly configured public IP (e.g. `--public-ip` on Bootstrap nodes
  /// with manual DNAT). Only used for peer advertisement when NAT traversal
  /// cannot port-verify automatically (no UPnP/STUN success).
  String? manualPublicIp;

  /// Primary identity used for DHT protocol messages (PING/PONG senderId).
  late IdentityContext primaryIdentity;

  /// TLS fallback manager: tracks per-peer consecutive failures, activates TLS when UDP is blocked.
  final TlsFallbackManager _tlsFallback = TlsFallbackManager();

  /// Per-node rate limiter (DoS Layer 2, Architecture Section 9.2).
  late final RateLimiter rateLimiter;

  /// Local peer reputation + banning (DoS Layers 3+5, Architecture Sections 9.3/9.5).
  late final ReputationManager reputationManager;

  /// Shared network-stats collector. The transport is owned by the node and
  /// fan-outs every UDP frame to a single counter pair — wiring it per-Service
  /// (the previous design) used `??=` and only the first identity to start
  /// won the receive callback, so all subsequent identities saw byte counters
  /// stuck at 0 (#U5). Single source of truth here, services read it via
  /// `node.statsCollector` in their getNetworkStats().
  final NetworkStatsCollector statsCollector = NetworkStatsCollector();

  /// Callback for mutual peer computation (wired by CleonaService).
  /// Returns nodeIdHex set of peers likely known to the recipient
  /// (shared contacts + shared group members). Architecture Section 3.3.7.
  Set<String> Function(Uint8List recipientUserId)? getMutualPeerIds;

  /// All registered identities: userIdHex → IdentityContext.
  /// Keyed by userId (stable identity), not deviceNodeId (per-device routing).
  final Map<String, IdentityContext> _identities = {};

  /// Reverse lookup: deviceNodeId hex → IdentityContext.
  /// Used for routing table operations that reference device-specific IDs.
  final Map<String, IdentityContext> _identitiesByDeviceId = {};

  /// Welle 5 (§2.6): public lookup by device-id for the daemon-level
  /// ApplicationFrame dispatcher — finds the local IdentityContext that
  /// owns [deviceId] (each identity has its own deviceNodeId, so the
  /// `nextHopDeviceId` of an incoming packet uniquely selects the
  /// recipient identity on a multi-identity daemon). Returns null when
  /// [deviceId] is not local (caller will drop the packet — receiver-side
  /// invariant of `sendToDevice`).
  IdentityContext? identityByDeviceId(Uint8List deviceId) {
    return _identitiesByDeviceId[bytesToHex(deviceId)];
  }

  /// All identities hosted on [deviceId] (may be >1 after C-1/§3.1 made
  /// deviceNodeId daemon-global — two identities share one device).
  /// Used by service-routed handlers that carry recipientUserId in the payload.
  Iterable<IdentityContext> identitiesForDevice(Uint8List deviceId) {
    final hex = bytesToHex(deviceId);
    return _identities.values.where((ctx) => ctx.nodeIdHex == hex);
  }

  // Components
  late Transport transport;
  late RoutingTable routingTable;
  late DhtRpc dhtRpc;
  late AckTracker ackTracker;
  late PeerMessageStore peerMessageStore;
  // V3.0: persistent MessageQueue removed (Cleona_Chat_Architecture_v3_0.md §5).
  // Offline-Delivery wird ausschließlich von Store-and-Forward + Reed-Solomon
  // Erasure Coding + Mailbox-Pull übernommen. Sender stoppt bei „alle Routen
  // erschöpft", kein lokales Re-Send-Park.
  late ReachabilityProbe reachabilityProbe;
  late LocalDiscovery localDiscovery;
  late MulticastDiscovery multicastDiscovery;
  late NatTraversal natTraversal;
  late DvRoutingTable dvRouting;
  late PortMapper portMapper;

  // 2D-DHT Identity Resolution (§2.2.4)
  late IdentityDhtHandler identityDhtHandler;
  late IdentityResolver identityResolver;

  /// Keepalive for public-IP peers without a coordinated hole punch
  /// (e.g. Bootstrap, peers learned via PEER_LIST_PUSH). Architecture
  /// §2.4.5 + §7.6 — the only periodic UDP traffic in the system besides
  /// hole-punch keepalive in [NatTraversal].
  late UdpKeepalive udpKeepalive;

  /// §4.11 External Rendezvous: cold-start address resolution via external
  /// networks (Nostr). Wired by CleonaService after identity init.
  RendezvousManager? rendezvousManager;

  /// §4.11.9 Infrastructure Rendezvous: network entry-point resolution.
  InfraRendezvousManager? infraRendezvousManager;

  /// §19.6.5 Binary Distribution Rendezvous: publish/resolve which nodes
  /// hold complete or partial application binaries, for in-network
  /// censorship-resistant updates. Wired by CleonaService after identity
  /// init (same pattern as [infraRendezvousManager]).
  BinaryRendezvousManager? binaryRendezvousManager;

  /// Supplies the current [BinaryAvailabilityRecord] for this device when
  /// [binaryRendezvousManager] needs to (re-)publish on network change. Set
  /// by CleonaService once its BinaryFragmentStore/BinaryUpdateManager are
  /// ready.
  List<BinaryAvailabilityRecord> Function()? binaryRecordProvider;

  /// True once this device holds at least one binary/fragment worth
  /// advertising via [binaryRendezvousManager] (§19.6.5). Gates the
  /// network-change republish so idle devices (nothing to serve) don't emit
  /// unnecessary Nostr traffic (Arbeitsregel #5 — kein unnötiger
  /// Netzwerkverkehr). Set by CleonaService.
  bool binaryHasContentToShare = false;

  bool get serveBinaryUpdates => true;

  // §4.11.11 Reactive Resolve Triggers (V3.1.117) — gating state.
  // Edge-triggered only (retry-exhausted, network-change+8s,
  // discovery-complete); no timers beyond the one-shot batch coalescer.
  static const Duration _rvContactCooldown = Duration(minutes: 15);
  static const Duration _rvBatchGate = Duration(seconds: 60);
  static const Duration _rvBatchCoalesce = Duration(seconds: 2);
  final Map<String, DateTime> _rvResolveCooldown = {}; // userIdHex → attempt
  final Set<String> _rvPendingResolve = {};
  DateTime? _rvLastBatchAt;
  Timer? _rvBatchTimer;

  /// deviceHex → contact userIdHex whose rendezvous-resolved addresses we
  /// PINGed; a PONG from that device fires [onContactEndpointConfirmed].
  final Map<String, String> _rvAwaitingConfirm = {};
  final Map<String, DateTime> _rvAwaitingConfirmAt = {};

  /// §5.1 third outbox edge (contact-endpoint-confirmed): fires when a
  /// rendezvous-resolved contact device answers with bidirectional UDP
  /// contact. Service layer chains this to its outbox flush.
  void Function(String contactUserIdHex)? onContactEndpointConfirmed;

  // Plan §D2: lightweight signal so application-layer code (e.g. CallManager's
  // per-CallSession route cache) can invalidate stale routes when DV-Routing
  // surgically drops a path. Fires from the existing `ackTracker.onRouteDown`
  // handler — see the wire-up in `_init()`. peerHex may be a deviceNodeId or
  // a userId (V3.1.65 multi-device routing); listeners should match either.
  void Function(String peerHex)? onRouteDownForCalls;


  /// Fires when [ackTracker] has exhausted its surgical retry budget for a
  /// (messageId, recipientDeviceId) pair — i.e. all DV routes returned ACK
  /// timeouts and the per-message retry counter passed `_computeMaxRetries`.
  ///
  /// Service-layer consumer: trigger the V3 offline cascade per
  /// `Cleona_Chat_Architecture_v3_0.md` §5 — Reed-Solomon erasure-coded S&F
  /// (§5.4 + §5.5) plus mailbox publication (§5.6). Sender stops touching
  /// the wire from here; receiver pulls offline messages on next online.
  ///
  /// `messageIdHex` identifies the message for de-dup with prior S&F-Backup
  /// attempts. `recipientUserId` is the userId the AckTracker tracked.
  /// `serializedPacket` carries the `NetworkPacketV3` wire-payload bytes
  /// the AckTracker stored on `trackSend`.
  /// Fire-and-forget; consumer must own its own error handling.
  void Function(
    String messageIdHex,
    Uint8List serializedPacket,
    Uint8List recipientUserId,
  )? onMessageRetryExhausted;

  /// §5.1 L1 direct retry on first AckTracker timeout. Fires BEFORE
  /// exhaustion: transient UDP loss in LAN is recoverable with a single
  /// re-send — going straight to L3 (erasure/S&F) wastes 9+ minutes on
  /// edge-triggered outbox flush. Same signature as onMessageRetryExhausted.
  void Function(
    String messageIdHex,
    Uint8List serializedPacket,
    Uint8List recipientUserId,
  )? onMessageRetryNeeded;

  /// Welle 5 (§2.4.1) infrastructure-receive hook. The V3 receive pipeline
  /// ([_onPacketV3Received]) decapsulates `PAYLOAD_INFRASTRUCTURE_FRAME`
  /// packets inline using the local Device-KEM private keys (§3.5b),
  /// validates `messageType ∈ §2.3.5 selector` and `recipientDeviceId ==
  /// myDeviceId`, then dispatches the typed [proto.InfrastructureFrameV3]
  /// to this callback. Consumers (CleonaService) route by `frame.messageType`
  /// — there is no second decap step.
  ///
  /// Drop conditions (parseFailed, kemDecapFailed, selectorMismatch,
  /// recipientMismatch) never reach the hook; they are silently absorbed at
  /// the codec boundary per §2.4.1 [10']/[14'].
  ///
  /// Welle 6 (§2.4.0): `snapshot` carries the outcome of step §2.4 [4]
  /// (Outer Device-Sig-Verify). InfrastructureFrame senderUserId is empty
  /// (no user-identity claim at this layer); inner-handlers that need a
  /// userId attach it after parsing the wrapped payload.
  void Function(
    proto.InfrastructureFrameV3 frame,
    Uint8List senderDeviceId,
    InternetAddress sourceAddr,
    int sourcePort,
    SenderIdentitySnapshot snapshot,
  )? onInfrastructureFramePayload;

  // State
  StreamSubscription<PortMapperEvent>? _portMapperSub;
  bool _portMapperPublicIpRetried = false;
  Timer? _maintenanceTimer;
  Timer? _peerExchangeTimer;
  Timer? _dvSafetyNetTimer;
  Timer? _dvPropagationDebounce;
  Timer? _networkStateSaveDebounce;

  // ── §4.5 Isolated-Node Re-Discovery (Architecture §4.5) ──────────────
  //
  // Self-terminating retry with exponential backoff for the `peerCount == 0`
  // pathological case. The normal "3-burst then silence" rule only applies
  // when ≥1 peer exists to flood. Without peers the node is stuck: it never
  // receives anything to trigger Stage-5 re-discovery, so we need an
  // independent timer.
  //
  // Backoff schedule (Architecture §4.5):
  //   step 0 → 1 min, step 1 → 5 min, step 2+ → 30 min, cap 60 min.
  // The timer disarms immediately on the first confirmed peer (first direct
  // hopCount==0 packet OR hole-punch success). It is NEVER armed while
  // peerCount > 0, so it generates O(1) traffic in any populated mesh.
  Timer? _isolatedNodeRetryTimer;
  int _isolatedNodeRetryStep = 0;

  /// Bootstrap addresses passed to [start]/[startQuick]. Stored so the
  /// isolated-node retry tick can re-ping them without requiring the caller
  /// to re-supply them. Cleared on [stop].
  final List<String> _isolatedNodeBootstrapAddrs = [];

  /// §4.5 Discovery Cascade: set to true when a PEER_LIST_PUSH with ≥1
  /// entry is received. Gates all burst-producing mechanisms (welcome route
  /// updates, DV flushes, Kademlia bootstrap, address broadcasts) so they
  /// only fire after the mesh state is known — not during the discovery phase.
  /// Reset on network-change events (§4.9) so the cascade re-runs.
  bool _discoveryComplete = false;
  Timer? _discoveryCascadeTimer;

  // §13.1.2 exemption #4: call-session-scoped live-media PoW allowlist.
  // Live-media frames (CALL_AUDIO/VIDEO, CALL_GROUP_AUDIO/VIDEO, RTT ping/
  // pong, tree updates) are built with `skipPoW: true` on the sender side
  // (Architecture §10.3 / Appendix B.2 — a ~20ms PoW grind per 20ms audio
  // frame is impossible at call framerates). The PoW gate cannot see the
  // inner messageType before KEM-decap, so the exemption is scoped by
  // sender device id instead: [CallManager]/[GroupCallManager] register the
  // peer device(s) of an active call session here for the session's
  // lifetime and unregister on every terminal call state. Hex-encoded
  // lowercase device ids (matches `bytesToHex` used elsewhere for device
  // ids). This does NOT weaken the outer device-sig, rate limiting or
  // reputation layers — only the PoW check is bypassed, only for
  // registered devices.
  final Set<String> _liveMediaPeerDevices = {};

  /// Register a peer device id as exempt from the ApplicationFrame PoW gate
  /// for the duration of an active call (§13.1.2 exemption #4). Idempotent —
  /// safe to call for a device id already registered (e.g. overlapping
  /// 1:1 + group call sessions with the same peer).
  void registerLiveMediaPeer(Uint8List deviceId) {
    _liveMediaPeerDevices.add(bytesToHex(deviceId));
  }

  /// Unregister a peer device id previously registered via
  /// [registerLiveMediaPeer]. Callers must unregister exactly the device ids
  /// their own session registered (not blindly clear the whole set) so
  /// overlapping sessions to the same peer don't clobber each other.
  void unregisterLiveMediaPeer(Uint8List deviceId) {
    _liveMediaPeerDevices.remove(bytesToHex(deviceId));
  }

  /// True if `deviceId` is currently exempt from the PoW gate as an active
  /// call peer.
  bool isLiveMediaPeer(Uint8List deviceId) {
    return _liveMediaPeerDevices.contains(bytesToHex(deviceId));
  }

  final Set<String> _dvPendingChanges = {};
  // §4.4: Per-neighbor hold-down — suppress DV updates to a neighbor for 10s
  // after the last flush to that neighbor.  Bounds worst-case traffic to
  // 6 updates/min/neighbor regardless of topology churn.
  final Map<String, DateTime> _dvHoldDownUntil = {};
  static const _dvHoldDownDuration = Duration(seconds: 10);
  final RelayDedupCache _relayDedup = RelayDedupCache();

  // D5 (§5.3 + §13.1.3): collective relay-forward slice for non-introduced
  // origins. Sliding 60s window. Origins that never introduced themselves
  // (no admission PoW, no firstParty PK) collectively get this much forward
  // amplification; introduced origins are unaffected. Generous: binds only
  // under attack.
  static const int relayPoolMaxBytesPerMinute = 2 * 1024 * 1024; // 2 MB
  static const int relayPoolMaxMessagesPerMinute = 1000;
  int _relayPoolBytes = 0;
  int _relayPoolMessages = 0;
  DateTime _relayPoolWindowStart = DateTime.now();
  int _relayPoolDrops = 0;

  /// D5: relay forwards dropped because the collective pool slice was
  /// exhausted. Exposed as `poolDropsRelay` in network stats.
  int get relayPoolDrops => _relayPoolDrops;

  /// D5: returns true (and accounts the forward) when the pooled relay
  /// slice still has room; false → the forward must be dropped. Only called
  /// for non-introduced origins.
  bool _relayPoolAllow(int payloadSize) {
    final now = DateTime.now();
    if (now.difference(_relayPoolWindowStart).inSeconds >= 60) {
      _relayPoolBytes = 0;
      _relayPoolMessages = 0;
      _relayPoolWindowStart = now;
    }
    if (_relayPoolMessages >= relayPoolMaxMessagesPerMinute ||
        _relayPoolBytes + payloadSize > relayPoolMaxBytesPerMinute) {
      _relayPoolDrops++;
      return false;
    }
    _relayPoolMessages++;
    _relayPoolBytes += payloadSize;
    return true;
  }

  /// §2.4 step [3b]: duplicate-frame cache (replay dedup). Keyed on the
  /// networkTag HMAC, which covers the full packet incl. timestampMs — a
  /// byte-identical replay maps to the identical tag, while relay re-wraps
  /// and sender-rebuilt retransmits produce fresh tags (no false positives).
  final FrameDedupCache _frameDedup = FrameDedupCache();
  DateTime? _lastBroadcastTime;
  bool _running = false;
  /// Count of authenticated packets received in this session.
  /// Used by [_hasRecentlyReachablePeer] to gate Stage-5 Re-Discovery
  /// (Architecture §5.10.5): if the daemon has not received a single
  /// HMAC-validated packet since startup, the mesh is presumed unreachable
  /// and the Re-Discovery procedure (3-burst + Subnet-Scan) must run.
  ///
  /// `PeerInfo.lastSeen` on persisted entries is NOT a valid signal here —
  /// it can be touched without a real receive (e.g. by `_loadRoutingTable`
  /// at startup, or via address-update paths). A stale entry from a dead
  /// peer could keep lastSeen ahead of any session marker and silently
  /// abort Stage-5, leaving the daemon isolated. Forensics 2026-05-15:
  /// a routing-table entry for a dead peer had lastSeen freshly updated
  /// each session, scan aborted `sent=0` 12× the same day, mesh isolation.
  int _authenticatedReceivesInSession = 0;

  DateTime? _lastNetworkChangeAt;
  String _localIp = '';
  List<String> _localIps = [];

  // Mass route-down detection: infer network change when ≥3 routes fail within 30s.
  final List<DateTime> _routeDownTimestamps = [];
  bool _networkChangeInProgress = false;
  bool _networkChangePending = false;
  bool _networkChangePendingForce = false;

  /// F1 (S123 UDP-dead RCA): when the LAST `onUdpSocketDead` edge finished
  /// its `onNetworkChanged(force:true)` rebind. If a SECOND dead-edge
  /// arrives soon after, the rebind demonstrably did not fix anything (same
  /// dead network — a rebind-on-anyIPv4/anyIPv6 stays on the same dead
  /// interface) and we escalate straight to `_tryMobileFallback()`,
  /// bypassing the `_confirmedPeers` gate that made the fallback
  /// unreachable in the field (WLAN-zombie: rebind ran 8× in ~20s, all
  /// equally ineffective). See [DeadEdgeEscalationTracker].
  final DeadEdgeEscalationTracker _deadEdgeEscalation =
      DeadEdgeEscalationTracker();

  /// Zero-peer recovery: periodic timer that re-bootstraps when isolated.
  Timer? _zeroPeerRecoveryTimer;

  /// Peers that have actually responded since this node started, with the
  /// timestamp of the last direct (hopCount==0) packet received. Used to
  /// distinguish "loaded from disk" peers from truly reachable ones. Peers
  /// that haven't sent a direct packet in [_confirmedPeerTtl] are no longer
  /// considered confirmed — UDP fire-and-forget to them returns false,
  /// enabling the relay/failure cascade.
  ///
  /// Persisted via [saveNetworkState] and reloaded on start as a warm-start
  /// hint (accelerates re-confirmation of known peers). Persisted entries
  /// do NOT satisfy [hasSessionConfirmedPeers] — that flag requires a fresh
  /// direct packet in the current session.
  final Map<String, DateTime> _confirmedPeers = {};
  static const Duration _confirmedPeerTtl = Duration(hours: 1);

  /// F2 (S123 UDP-dead RCA, 2026-07-03 Pixel field test): tracks the last
  /// INBOUND packet that proves our OWN sends are getting through — i.e. a
  /// reply to something we sent (DHT_PONG / DELIVERY_RECEIPT / the generic
  /// infra-response bridge covering FRAGMENT_STORE_ACK,
  /// DHT_FIND_NODE/FIND_VALUE/STORE_RESPONSE, IDENTITY_*_RESPONSE).
  ///
  /// This is deliberately DISTINCT from [_confirmedPeers]: that map only
  /// proves the RECEIVE path is alive (any inbound direct/BOOT packet, even
  /// a receive-only trickle from a peer whose replies to us never arrive).
  /// The field forensics (WLAN-zombie: uplink dead, interface kept its IPs
  /// for ~2.5min, only inbound was a Bootstrap IPv6 trickle) showed
  /// `_confirmedPeers` staying fresh via that trickle while our own sends
  /// were black-holed for 2h23min — the recovery gates below were built on
  /// `_confirmedPeers` and therefore never tripped. They must instead gate
  /// on send-path liveness. See [OutboundLivenessTracker].
  final OutboundLivenessTracker _outboundLiveness = OutboundLivenessTracker();

  /// True if an inbound packet proving our own sends reached a peer arrived
  /// recently. See [_outboundLiveness].
  bool get _outboundRecentlyConfirmed => _outboundLiveness.recentlyConfirmed();

  /// True once at least one peer has been confirmed by a direct packet
  /// (hopCount==0) in the CURRENT daemon session. The QR convergence gate
  /// (§8.1.1) uses this to distinguish "mesh converged" from "still warming
  /// up with stale data". Persisted confirmed-peers do not flip this flag.
  bool hasSessionConfirmedPeers = false;

  /// Timestamp of the node start — used by the QR convergence indicator
  /// to show progress relative to typical convergence time.
  DateTime? nodeStartedAt;
  bool isPeerConfirmed(String hex) {
    final ts = _confirmedPeers[hex];
    if (ts == null) return false;
    if (DateTime.now().difference(ts) > _confirmedPeerTtl) return false;
    return true;
  }

  /// Stricter liveness check for gossip responses (PeerListPush content).
  /// A peer is gossip-worthy only if:
  ///  1. confirmed (direct packet within TTL), AND
  ///  2. has an alive DV route, AND
  ///  3. fewer than 3 unacked packets (not in cascade-exhaustion state).
  /// Dead peers are excluded from gossip immediately — they pull updates
  /// themselves via Mesh-Refresh when they come back online.
  bool _isPeerAliveForGossip(String hex) {
    if (!isPeerConfirmed(hex)) return false;
    final route = dvRouting.bestRouteTo(hex);
    if (route == null || !route.isAlive) return false;
    if ((_unackedPacketsToPeer[hex] ?? 0) >= 3) return false;
    return true;
  }

  /// Authoritative set of currently confirmed peers (within TTL).
  /// Mirrors [isPeerConfirmed] so callers get a consistent view; any route-dead
  /// filtering must be performed explicitly by the consumer.
  Set<String> get confirmedPeerIds =>
      _confirmedPeers.keys.where(isPeerConfirmed).toSet();

  /// S119 B (Problem 2): authoritative "reachable" set for UI counters and
  /// peer lists — confirmed (bidirectional UDP within TTL) ∪ alive DV route.
  /// Deliberately NOT [DvRouting.allDestinations]: `_routes` retains dead
  /// and never-pruned routes for destinations without traffic, which
  /// inflated the connection sheet with unreachable peers.
  Set<String> get reachablePeerIds {
    final set = confirmedPeerIds;
    for (final destHex in dvRouting.allDestinations) {
      if (!set.contains(destHex) && dvRouting.hasAliveRouteTo(destHex)) {
        set.add(destHex);
      }
    }
    return set;
  }

  // DV-Routing: track when we last sent a route update to each neighbor.
  // Used for catch-up and welcome gate.
  final Map<String, DateTime> _lastRouteUpdateSentTo = {};

  // Epoch of dvRouting.routeEpoch at the time of the last update sent to
  // each neighbor. Catch-up is skipped when routeEpoch hasn't changed.
  final Map<String, int> _lastRouteEpochSentTo = {};

  // F5: Grace period after network change — suppress catch-up sends entirely
  // to prevent the self-amplifying full-table storm.
  DateTime? _networkChangeGraceUntil;

  // DV→K-bucket seeding: cooldown per destination to avoid repeated WANTs.
  final Map<String, DateTime> _dvSeedWantCooldown = {};

  // §5.10.4 Solicited-Reply-Adoption tracker.
  //
  // When we send a `MTV3_PEER_LIST_WANT` to a peer, we record the deviceId-hex
  // here with the send timestamp. An incoming `MTV3_PEER_LIST_PUSH` from that
  // peer within `_solicitedReplyWindow` is treated as a *solicited reply* —
  // the peer is adopted as a direct neighbor (idempotent
  // `dvRouting.addDirectNeighbor` call) before `processRouteUpdate` runs, so
  // the silent-drop in `dv_routing.dart:processRouteUpdate` (return false on
  // unknown sender) cannot eat the carried routes when the adoption hasn't
  // already happened via the V3-receive hook (cold-start / fresh peer cases).
  // Outer-Sig + HMAC + rate-limit + reputation-ban remain the trust gate;
  // this tracker only short-circuits the DV neighbor-membership precondition.
  // Entries are removed on first match or pruned by `_maintenance` after the
  // window expires; the tracker is in-memory only — an outstanding WANT from
  // a previous daemon lifetime carries no semantics.
  final Map<String, DateTime> _outstandingPeerListWants = {};
  static const Duration _solicitedReplyWindow = Duration(seconds: 30);

  /// Cooldown map for PEER_KEY_REQUEST: deviceIdHex → last request time.
  /// At most one request per peer per 60s to avoid request storms.
  final Map<String, DateTime> _peerKeyRequestCooldown = {};

  // ── §5.10 Send-Cascade Recovery & Self-Healing ───────────────────────
  //
  // Counter-driven (NOT timer-driven) self-healing for the V3 send cascade:
  //   Stage 1 Direct (≤3 packets, AckTracker)
  //   Stage 2 Stale-PK Recovery     ← see _triggerStalePkRecovery
  //   Stage 3 Alternative Route (≤3 packets, sendToDevice DV cascade)
  //   Stage 4 Mesh-State Refresh    ← see _triggerMeshRefresh
  //   Stage 5 Re-Discovery          ← see _triggerReDiscovery
  // Cascade falls through to §5.4 Erasure / §5.6 Mailbox layers normally.

  /// §5.10.4 — per-peer counter of in-flight, unACK'd packets to that device.
  /// Incremented on each `sendToDevice`; decremented on any positive signal
  /// from the same device (DELIVERY_RECEIPT via `ackTracker.onAckReceived`,
  /// DHT_PONG, PEER_LIST_PUSH). Stage 4 Mesh-Refresh triggers at ≥6.
  final Map<String, int> _unackedPacketsToPeer = {};

  /// §5.10.4 — Stage 4 trigger threshold (in unACK'd packets to one peer).
  static const int _stage4Threshold = 6;

  /// §5.10.2 — last Stale-PK probe per peer (deviceIdHex → DateTime). Throttle
  /// repeats from a flood of `device_sig_invalid` packets to a single probe
  /// per 30s window. Mirrors the feel of `_lastPeerListProbe` and friends.
  final Map<String, DateTime> _lastStalePkProbe = {};
  static const Duration _stalePkProbeThrottle = Duration(seconds: 30);

  /// §5.10.4 — last Mesh-Refresh per failed-peer (deviceIdHex → DateTime).
  /// 60 s cooldown so a single message-cascade collapse doesn't keep firing
  /// PEER_LIST_WANT bursts on every retry tick. Cooldown anchors on the
  /// failed device's hex (de-dup matches the spec's "by original messageId"
  /// intent — a single failed peer in this window only refreshes once).
  final Map<String, DateTime> _lastMeshRefresh = {};
  static const Duration _meshRefreshThrottle = Duration(seconds: 60);

  /// §5.10.5 — timestamp of last Re-Discovery trigger.
  ///
  /// Re-Discovery is a heavy operation: 3-burst multicast + LAN-broadcast
  /// + a subnet scan that can take 130-200s to complete on slow networks.
  /// Without a global cooldown, a daemon with no reachable peers ends up
  /// in a tight loop: send-cascade fails → Re-Discovery triggers → before
  /// the previous discovery finishes, the next message-send cascade also
  /// fails → another Re-Discovery → multicast/broadcast bursts pile up,
  /// the existing subnet scan is interrupted (`startSubnetScan` no-ops
  /// when already active so the *scan* is fine, but the redundant burst
  /// traffic floods the LAN and wastes per-peer rate-limit budget).
  /// 60 s mirrors `_meshRefreshThrottle` for symmetry; long enough that
  /// a typical subnet scan can make meaningful fill-phase progress before
  /// the next trigger, short enough that a peer that *does* come up
  /// gets noticed reasonably quickly.
  DateTime? _lastReDiscoveryTrigger;
  static const Duration _reDiscoveryCooldown = Duration(seconds: 60);

  /// §5.10.4 — global rate limit for Mesh Refresh (token bucket).
  /// Per-peer cooldown alone allows N distinct ghost peers to fire N bursts
  /// per minute. The global bucket caps total bursts to [_meshRefreshGlobalMax]
  /// per [_meshRefreshGlobalWindow], regardless of how many peers fail.
  final List<DateTime> _meshRefreshGlobalBucket = [];
  static const int _meshRefreshGlobalMax = 3;
  static const Duration _meshRefreshGlobalWindow = Duration(seconds: 60);

  /// §5.10.4 — timestamp of the most recent Stage-4 PEER_LIST_WANT burst,
  /// used by `_handlePeerListPushInfra` to detect "we received a reply
  /// inside the tail window" → set `_stage4ReplySeen = true`.
  DateTime? _lastStage4BurstAt;
  Duration _lastStage4TailWindow = Duration.zero;
  bool _stage4ReplySeen = false;
  String? _stage4FailedHex;

  /// §5.5b First-CR-Mailbox: stored CRs waiting for the target to come
  /// online. Keyed by recipientDeviceIdHex. Each entry holds the opaque
  /// encrypted blob, the sender's deviceId, and a timestamp. Max 50
  /// entries total, 7-day TTL, evicted on periodic tick.
  final Map<String, List<_FirstCrMailboxEntry>> _firstCrMailbox = {};
  static const int _firstCrMailboxMaxEntries = 50;
  static const Duration _firstCrMailboxTtl = Duration(days: 7);

  /// Callback for FIRST_CR_STORE_ACK — the service layer registers this
  /// so it can update contact status to storedForDelivery.
  void Function(Uint8List senderDeviceId, bool accepted)? onFirstCrStoreAck;

  CleonaNode({
    required this.profileDir,
    required this.port,
    this.networkChannel = 'beta',
  }) : _log = CLogger.get('node', profileDir: profileDir) {
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
    statsCollector.markStarted();

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

    // Init Distance-Vector routing table (V3) — must exist before loadDvRouting.
    // Phase 2: ownNodeId = deviceNodeId (per-device routing)
    dvRouting = DvRoutingTable(ownNodeId: primaryIdentity.deviceNodeId);
    dvRouting.onRouteChanged = _onDvRouteChanged;
    dvRouting.isAdmitted = (hex) {
      final peer = routingTable.getPeer(hexToBytes(hex));
      return peer?.idPowVerified ?? false;
    };

    // DV-table sits *next* to the routing table on disk (Architektur §2.7.3).
    // Order matters: routes/neighbors reference nodeIds that must already be
    // resolvable as PeerInfos in `routingTable`, so the routing table loads
    // first, the topology second.
    _loadDvRouting();
    _loadConfirmedPeers();
    _loadFirstCrMailbox();

    // Init DHT RPC. V3-direct contract: sendFunction takes
    // `(MTV3, body, peer)` and we plumb that into the §2.3.5 InfraFrame
    // pipeline directly via `_sendInfra`.
    dhtRpc = DhtRpc(profileDir: profileDir);
    dhtRpc.sendFunction = (proto.MessageTypeV3 type, Uint8List body,
            PeerInfo peer) =>
        _sendInfra(
          messageType: type,
          innerPayload: body,
          recipientDeviceId: Uint8List.fromList(peer.nodeId),
        );

    // Init RUDP Light ACK tracker (uses shared RTT from DhtRpc)
    ackTracker = AckTracker(rttSource: dhtRpc, profileDir: profileDir);

    // DV-6: Wire dynamic retry cap. The tracker queries this callback at
    // timeout time to compute how many retries the current message gets.
    // Single-route peers stay at the conservative base of 3; peers with
    // multiple alternatives get a deeper budget so one broken route
    // doesn't exhaust the whole recovery window.
    ackTracker.aliveRouteCount = (peerHex) {
      // peerHex from trackSend is userId. DV routes are indexed by deviceId.
      // Sum alive routes across all devices of this user.
      final peerBytes = hexToBytes(peerHex);
      final directRoutes = dvRouting.routesTo(peerHex).where((r) => r.isAlive).length;
      if (directRoutes > 0) return directRoutes;
      int total = 0;
      for (final p in routingTable.getAllPeersForUserId(peerBytes)) {
        total += dvRouting.routesTo(bytesToHex(p.nodeId)).where((r) => r.isAlive).length;
      }
      return total;
    };

    // §5.1 Layer 3 trigger: when ALL ACK retries are exhausted for a message,
    // forward to service layer for offline cascade (S&F + Erasure).
    // onRetryExhausted fires once after maxRetries consecutive timeouts.
    // onRetryNeeded (per-timeout) is intentionally unwired — V3 does not
    // re-send via alternative DV routes (the cascade handles offline delivery).
    ackTracker.onRetryExhausted =
        (messageIdHex, serializedPacket, recipientUserId) {
      // Fire-and-forget: service handler is async but errors are
      // handled internally (outbox fallback on L3 failure).
      onMessageRetryExhausted?.call(
          messageIdHex, serializedPacket, recipientUserId);
      // §4.11.11 trigger 1: the Layer-3 edge marks the contact unreachable
      // — batch a reactive rendezvous resolve for it.
      requestContactResolve(
          userIdHex: bytesToHex(recipientUserId), reason: 'retry-exhausted');
    };

    // §5.1 L1 direct retry: re-send via resolved devices on first timeout.
    // Transient LAN packet loss is recoverable — skipping straight to L3
    // (erasure/S&F) wastes minutes waiting for edge-triggered outbox flush.
    ackTracker.onRetryNeeded =
        (messageIdHex, serializedPacket, recipientUserId) {
      onMessageRetryNeeded?.call(
          messageIdHex, serializedPacket, recipientUserId);
    };

    // Wire Route-Down: 3x ACK timeout → surgical DV markRouteDown → Poison Reverse
    // V3.1: Only the specific route (via nextHop) is marked down, not all routes.
    // V3.1.44: Mass route-down detection → infer network change → re-discover public IP.
    ackTracker.onRouteDown = (peerHex, {String? viaNextHopHex}) {
      final viaShort = viaNextHopHex != null ? viaNextHopHex.substring(0, 8) : 'direct';
      _log.info('Route DOWN via ACK: ${peerHex.substring(0, 8)} via $viaShort');

      // peerHex from AckTracker timeout is userId (trackSend keyed by userId).
      // DV routes are indexed by deviceId. Resolve userId→device(s) so
      // markRouteDown and routesTo operate on the correct keys.
      final peerBytes = hexToBytes(peerHex);
      final peers = routingTable.getAllPeersForUserId(peerBytes);
      // Direct deviceId hit (legacy or if peerHex IS a deviceId).
      if (peers.isEmpty) {
        final directPeer = routingTable.getPeer(peerBytes);
        if (directPeer != null) {
          peers.add(directPeer);
        }
      }
      if (peers.isEmpty) return;

      // Mark DV routes down for every device of this user.
      for (final peer in peers) {
        final deviceHex = bytesToHex(peer.nodeId);
        dvRouting.markRouteDown(deviceHex, viaNextHopHex: viaNextHopHex);
        _log.debug('DV markRouteDown: device ${deviceHex.substring(0, 8)} '
            '(user ${peerHex.substring(0, 8)}) via $viaShort');
      }

      // Notify call layer (fire-and-forget).
      for (final peer in peers) {
        try {
          onRouteDownForCalls?.call(bytesToHex(peer.nodeId));
        } catch (_) {}
      }

      // Mass route-down → infer possible network change (e.g. ISP IP reassignment).
      // V3.1.111: removed force:true — let onNetworkChanged check IPs normally.
      // On bootstrap nodes, offline peers cause constant ACK timeouts that
      // trivially hit the 3-in-30s threshold with unchanged IPs, creating a
      // false-positive feedback loop (markAllRoutesStale → revalidation →
      // epoch bump → full-table catch-up → more ACK tracking → repeat).
      _routeDownTimestamps.add(DateTime.now());
      _routeDownTimestamps.removeWhere((t) =>
          DateTime.now().difference(t).inSeconds > 30);
      if (_routeDownTimestamps.length >= 3) {
        _log.info('Mass route-down detected (${_routeDownTimestamps.length} in 30s) '
            '— checking for network change');
        _routeDownTimestamps.clear();
        _scheduleNetworkChange();
      }

      // Per-device routing table bookkeeping.
      for (final peer in peers) {
        final deviceHex = bytesToHex(peer.nodeId);
        if (viaNextHopHex != null) {
          final relayHex = peer.relayViaNodeId != null ? bytesToHex(peer.relayViaNodeId!) : null;
          if (relayHex == viaNextHopHex) {
            peer.consecutiveRelayFailures = 3;
            _log.info('Relay route DOWN: ${deviceHex.substring(0, 8)} via $viaShort — clearing learned relay');
            peer.markRelayFailed(viaNextHopHex);
            peer.clearRelayRoute();
          }
        } else {
          final remaining = dvRouting.routesTo(deviceHex).where((r) => r.isAlive).toList();
          if (remaining.isNotEmpty) {
            _log.info('Route DOWN: ${remaining.length} alternative route(s) remain for ${deviceHex.substring(0, 8)}');
          } else {
            peer.consecutiveRouteFailures = 3;
          }
        }
      }
    };

    // §3.4: Single source of truth for ACK-Success → DV-Routing.
    // Mirror of onRouteDown (Failure-Seite). The DELIVERY_RECEIPT envelope
    // handler computes `wasDirect` from the source address and forwards it
    // through handleAck → here, instead of duplicating DV-state logic inline.
    // §3.1 B-1: peerHex is now the ACK sender's deviceId (not userId),
    // so dvRouting.confirmRoute and routingTable.getPeer work directly.
    ackTracker.onAckReceived = (msgIdHex, peerHex, wasDirect) {
      // F2 (S123 UDP-dead RCA): a DELIVERY_RECEIPT proves our own send
      // reached the peer AND their reply reached us back — the strongest
      // possible send-path liveness signal (RUDP-Light architectural
      // delivery proof). See [OutboundLivenessTracker].
      _outboundLiveness.noteConfirmed();
      if (wasDirect) {
        dvRouting.confirmRoute(peerHex);
        if (!_isLocalIdentity(peerHex)) {
          dvRouting.confirmRelayNeighbor(peerHex);
        }
      }

      final peerBytes = hexToBytes(peerHex);
      final peer = routingTable.getPeer(peerBytes);
      if (peer == null) {
        _log.debug('onAckReceived: peer ${peerHex.substring(0, 8)} not in '
            'routing table (stale or userId leak)');
        _decrementUnackedPacketsToPeer(peerHex);
        return;
      }
      if (peer.consecutiveRouteFailures > 0) {
        _log.debug('Reset consecutiveRouteFailures for ${peerHex.substring(0, 8)} '
            '(ACK ${wasDirect ? "direct" : "via relay"})');
        peer.consecutiveRouteFailures = 0;
      }
      if (peer.consecutiveRelayFailures > 0) {
        peer.consecutiveRelayFailures = 0;
      }
      _decrementUnackedPacketsToPeer(bytesToHex(peer.nodeId));
      if (peer.userId != null) {
        _decrementUnackedPacketsToPeer(bytesToHex(peer.userId!));
      }
    };

    // S-3: an E2E DELIVERY_RECEIPT that returned over a relay path proves the
    // relay route we sent through actually delivers → confirm that *specific*
    // route (binds preference to demonstrated delivery, not the advertisement).
    ackTracker.onRelayRouteConfirmed = (destHex, viaNextHopHex) {
      dvRouting.confirmRoute(destHex, viaNextHopHex: viaNextHopHex);
      if (!_isLocalIdentity(viaNextHopHex)) {
        dvRouting.confirmRelayNeighbor(viaNextHopHex);
      }
    };

    // 2D-DHT Identity Resolution (§2.2.4): Replicator-Side + Resolver
    // §3.7: derive shared FileEncryption key from master seed for daemon-level files.
    // Device keys are daemon-global → use baseDir (~/.cleona), NOT profileDir
    // (which may be a sub-directory like ~/.cleona/Bootstrap/).
    final deviceKeysDir = primaryIdentity.baseDir;
    final masterSeed = primaryIdentity.masterSeed;
    final Uint8List? sharedFileEncKey = masterSeed != null
        ? HdWallet.deriveSharedFileEncKey(masterSeed)
        : null;
    final identityFileEnc = FileEncryption(baseDir: deviceKeysDir, key: sharedFileEncKey);

    // V3.0 Device-Sig keypair (§3.5). Loaded once per daemon, shared across
    // all hosted identities. Lazy-created on first start.
    _deviceKeys = DeviceKeysStore.loadOrCreate(
      baseDir: deviceKeysDir,
      fileEnc: identityFileEnc,
    );
    // D3 Phase 2 (§13.1.2): Admission-PoW-Nonce MUSS vor dem ersten
    // Self-Broadcast bereitstehen — Phase 2 gates Relay/DV/DHT-Rollen auf
    // idPowVerified, d.h. ohne Nonce im Self-Broadcast werden wir von
    // anderen Nodes nicht als admitted erkannt.
    if (_deviceKeys.admissionNonce == null) {
      try {
        await DeviceKeysStore.ensureAdmissionNonce(
          bundle: _deviceKeys,
          baseDir: deviceKeysDir,
          fileEnc: identityFileEnc,
        );
        _log.info('D3: Admission-PoW-Nonce bereit '
            '(${AdmissionPow.difficultyBits} bits, Device-PK zertifiziert)');
      } catch (e) {
        _log.warn('D3: Admission-PoW-Grind fehlgeschlagen: $e');
      }
    }
    identityDhtHandler = IdentityDhtHandler(
      ownNodeId: primaryIdentity.deviceNodeId,
      fileEncryption: identityFileEnc,
      storagePath: '$profileDir/identity_dht_storage.json',
      // D1 (§4.3 Trust anchor): Store-Time-Verifikation eingehender
      // AuthManifests gegen Founding-Key-Hash/Rotationsketten-Anker.
      deriveUserId: (pk) => HdWallet.computeUserId(pk, NetworkSecret.secret),
    );
    await identityDhtHandler.start();
    identityResolver = IdentityResolver(
      routingTable: routingTable,
      dhtRpc: dhtRpc,
      dhtHandler: identityDhtHandler,
      // V3-direct: outer Device-Sig + KEM-AEAD inner are added by the
      // §2.3.5 InfraFrame pipeline (`_sendInfra` keyed by the sending
      // identity's device-keypair) when DhtRpc.sendFunction fires.
    );

    // Init Store-and-Forward message store
    peerMessageStore = PeerMessageStore(profileDir: profileDir);
    await peerMessageStore.load();

    // V3.0: keine MessageQueue-Initialisierung mehr. Offline-Delivery läuft
    // über S&F + Reed-Solomon + Mailbox-Pull (Architektur §5).

    // Load reputation data from disk
    await reputationManager.load(profileDir);

    // Init reachability probe (relay route discovery). ReachabilityProbe
    // hands us V3 InfraFrame triples `(MessageTypeV3, body, PeerInfo)`
    // directly. recipientDeviceId == peer.nodeId for the §2.3.5
    // InfraFrame path.
    reachabilityProbe = ReachabilityProbe(profileDir: profileDir);
    reachabilityProbe.sendFunction = (proto.MessageTypeV3 type,
            Uint8List body, PeerInfo peer) =>
        _sendInfra(
          messageType: type,
          innerPayload: body,
          recipientDeviceId: Uint8List.fromList(peer.nodeId),
        );
    reachabilityProbe.getCandidatesFunction = (targetNodeId) {
      final targetHex = bytesToHex(targetNodeId);
      return routingTable.allPeers
          .where((p) => isPeerConfirmed(p.nodeIdHex))
          .where((p) => p.nodeIdHex != targetHex)
          .where((p) => !routingTable.isLocalNode(p.nodeId))
          .toList();
    };
    reachabilityProbe.randomBytesFunction = (size) => SodiumFFI().randomBytes(size);

    // NatTraversal ships a V3-direct sender contract — `sendInfraFn` for
    // DV-cascade (HOLE_PUNCH_REQUEST → coordinator, HOLE_PUNCH_NOTIFY →
    // target) and `sendInfraDirectFn` for explicit-address sends
    // (HOLE_PUNCH_PING / PONG, NAT-timeout-probing keepalive).
    natTraversal = NatTraversal(profileDir: profileDir);
    natTraversal.ownNodeId = primaryIdentity.deviceNodeId;
    natTraversal.sendInfraFn = (type, body, deviceId) =>
        _sendInfra(messageType: type, innerPayload: body, recipientDeviceId: deviceId);
    natTraversal.sendInfraDirectFn = (type, body, deviceId, addr, port) =>
        sendInfraDirect(
          messageType: type,
          innerPayload: body,
          recipientDeviceId: deviceId,
          addr: addr,
          port: port,
        );
    natTraversal.onHolePunchSuccess = _onHolePunchSuccess;

    // Init UDP keepalive for public-IP peers (non-hole-punch path).
    // Architecture §2.4.5 / §7.6: keep carrier-NAT pinholes alive (~25s
    // interval, well below typical 30–60s carrier timeout). After 3
    // consecutive rounds where ALL registered peers fail to respond
    // (~75s) we infer a network change and run onNetworkChanged().
    udpKeepalive = UdpKeepalive(profileDir: profileDir);
    udpKeepalive.ownNodeId = primaryIdentity.deviceNodeId;
    // V3 hard-cut: keepalive PINGs use V3-direct InfraFrame send
    // (transport.dart:_processUdpDatagram only accepts NetworkPacketV3
    // since Welle 1; legacy raw-UDP pings were silently dropped on the
    // wire and carrier-NAT pinholes expired after ~30-60s).
    udpKeepalive.sendInfraFn = (type, body, deviceId, addr, port) =>
        sendInfraDirect(
          messageType: type,
          innerPayload: body,
          recipientDeviceId: deviceId,
          addr: addr,
          port: port,
        );
    udpKeepalive.onAllPeersFailed = () {
      // §4.6 IPv6-First / F2 (S123 UDP-dead RCA): only suppress the
      // network-change inference when our OWN sends are recently confirmed
      // as getting through (send-path liveness). `_confirmedPeers` alone is
      // NOT sufficient — it only proves the receive path is alive, and a
      // receive-only trickle (e.g. Bootstrap IPv6 keepalive replies to
      // someone else, or any inbound packet) kept it fresh for 2h23min in
      // the field while OUR sends were black-holed by a WLAN-zombie
      // interface, permanently suppressing this exact recovery path.
      if (_outboundRecentlyConfirmed) {
        _log.info('UdpKeepalive: all keepalive peers failed but outbound '
            'send-path recently confirmed (IPv6 path alive) — skipping '
            'network change');
        return;
      }
      _log.info('UdpKeepalive: all peers failed — inferring network change');
      _scheduleNetworkChange(force: true);
    };

    // Get all local IPs BEFORE transport starts — isReachableFromCurrentNetwork
    // depends on this being set when incoming packets trigger outgoing sends.
    var allIps = await Transport.getAllLocalIps();

    // §4.7 Mobile/SLAAC IPv6 startup race: the first snapshot may run before
    // the carrier has finished IPv6 address assignment. Retry briefly (local
    // only, no network traffic) until a global IPv6 appears or we give up.
    for (var retry = 0; retry < 3; retry++) {
      final hasGlobalV6 = allIps.any((ip) {
        final t = PeerAddress.classifyIp(ip);
        return t == PeerAddressType.ipv6Global;
      });
      if (hasGlobalV6) break;
      _log.info('Local IPs: no global IPv6 yet, retry ${retry + 1}/3 ...');
      await Future.delayed(const Duration(seconds: 2));
      allIps = await Transport.getAllLocalIps();
    }

    _localIp = allIps.isNotEmpty ? allIps.first : '127.0.0.1';
    _localIps = allIps;
    PeerAddress.currentLocalIps = _localIps;
    _log.info('Local IPs: ${allIps.join(", ")} (primary: $_localIp)');

    // Init transport (starts receiving immediately — localIps must be set first)
    transport = Transport(port: port, profileDir: profileDir);
    transport.onPacketV3 = _onPacketV3Received;
    transport.onDiscovery = _onDiscoveryReceived;
    transport.onPortProbe = _onPortProbeReceived;
    transport.onBytesSent = (b) => statsCollector.addBytesSent(b);
    transport.onBytesReceived = (b) => statsCollector.addBytesReceived(b);
    transport.onUdpSocketDead = () {
      // F1 (S123 UDP-dead RCA): a second dead-edge shortly after a
      // completed dead-edge-triggered rebind proves the rebind (anyIPv4/
      // anyIPv6 on the same interface) did not help — escalate straight to
      // the mobile-fallback probe instead of waiting for the
      // `_confirmedPeers`-gated 15s path in `onNetworkChanged`, which the
      // field trickle made unreachable. `_tryMobileFallback` verifies the
      // alternative interface itself (probe-and-check), so no additional
      // gate beyond "not already active" is needed here.
      if (_deadEdgeEscalation.shouldEscalate() &&
          !transport.isMobileFallbackActive) {
        _log.warn('UDP socket dead again <60s after rebind completed — '
            'rebind ineffective, escalating to mobile fallback');
        _tryMobileFallback();
      }
      _log.warn('UDP socket dead — triggering network change');
      _scheduleNetworkChange(
        force: true,
        onComplete: () => _deadEdgeEscalation.noteRebindCompleted(),
      );
    };
    transport.onEpochExpired = (minVersion) {
      _log.warn('EPOCH_EXPIRED: network requires secret version $minVersion — this build is outdated');
    };

    // Port mapping (NAT-PMP/PCP + UPnP) — must be initialized BEFORE
    // transport.start() because _onPacketV3Received accesses portMapper.state
    // and packets arrive immediately after the UDP socket opens.
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

    // Register self in routing table's peer manager
    _registerSelf();

    // No startup prune — peers may have stale lastSeen from previous session,
    // but are reachable right now. The regular maintenance timer (60s, 4h threshold)
    // handles cleanup AFTER peers have had a chance to respond to PINGs.

    // §4.5 Discovery Cascade: store bootstrap addresses for Tier 3.
    // Pings are deferred to `_startDiscoveryCascade()` — no immediate burst.
    if (bootstrapPeers.isNotEmpty) {
      _isolatedNodeBootstrapAddrs
        ..clear()
        ..addAll(bootstrapPeers);
    }

    // NOTE: no convergence delay here. _startBase() is shared by start() and
    // startQuick(); a blocking delay here delayed startQuick() → IpcServer.start()
    // → cleona.port on slow hosts (Windows first-run "Verbinde mit Dienst" hang).
    // The convergence wait now lives only in start() (headless), which blocks on
    // bootstrap by design.
  }

  /// Full start (blocking bootstrap). Used by headless mode.
  Future<void> start({List<String> bootstrapPeers = const []}) async {
    await _startBase(bootstrapPeers: bootstrapPeers);

    // §4.5 Discovery Cascade: probe stored peers → LAN → bootstrap → scan.
    // Blocks until discovery completes or all tiers exhausted.
    await _startDiscoveryCascade();

    _finishStart();
  }

  /// Quick start: transport + discovery immediately, bootstrap in background.
  Future<void> startQuick({List<String> bootstrapPeers = const []}) async {
    await _startBase(bootstrapPeers: bootstrapPeers);

    // §4.5 Discovery Cascade in background — does not block IPC readiness.
    _startDiscoveryCascade().then((_) => _finishStart());

    _running = true;
    _log.info('Node quick-started. Discovery cascade in background...');
  }

  void _finishStart() {
    // Cold-start jitter (0-3s): stagger startup bursts when many nodes boot
    // simultaneously (e.g. mod-lab cluster) to avoid O(N²) push cascade.
    final jitterMs = Random().nextInt(3000);
    if (jitterMs > 0) {
      Future.delayed(Duration(milliseconds: jitterMs), _finishStartDelayed);
      return;
    }
    _finishStartDelayed();
  }

  void _finishStartDelayed() {
    routingTable.defaultPeerFilter = null;

    // §5.11 — Maintenance timer (15 min, intern-only). Local prune of peers
    // older than 4 h, stale addresses, default-gateway recompute, persistence.
    _maintenanceTimer ??=
        Timer.periodic(const Duration(minutes: 15), (_) => _maintenance());

    // §5.12 cold-path — full DV exchange + firstParty self-broadcast every 1h.
    _dvSafetyNetTimer ??= Timer.periodic(const Duration(hours: 1), (_) => _dvSafetyNetExchange());

    // Startup mobile fallback: if after 30s no peer has been confirmed,
    // probe alternative interfaces (WiFi hairpin NAT, captive portal).
    Future.delayed(const Duration(seconds: 30), () {
      if (!_running) return;
      if (_confirmedPeers.values.any((ts) => DateTime.now().difference(ts) <= _confirmedPeerTtl)) return;
      if (transport.isMobileFallbackActive) return;
      _log.info('Startup: 0 confirmed peers after 30s — probing mobile fallback');
      _tryMobileFallback();
    });

    _running = true;
    nodeStartedAt = DateTime.now();
    _log.info('Node started. Peers: ${routingTable.peerCount}, '
        'discoveryComplete=$_discoveryComplete');
  }

  void _registerSelf() {
    // We don't add ourselves to the routing table, but we store our info
    // for PeerExchange to include our PK.
  }

  // ── §4.5 Discovery Cascade ──────────────────────────────────────────

  /// Sequential 4-tier discovery (Architecture §4.5). Each tier fires only
  /// if the previous tier failed to produce a confirmed peer with a fresh
  /// peer list. Returns when discovery completes or all tiers are exhausted.
  Future<void> _startDiscoveryCascade() async {
    _discoveryComplete = false;

    // Tier 1 — Stored peers: probe persisted routing table. Anchor/Stable
    // peers first (most likely to still have the same address after extended
    // offline), then by lastSeen recency. 1 PING per peer, 2 s timeout, max 5.
    final stored = routingTable.allPeers
        .where((p) => !_isLocalIdentity(p.nodeIdHex))
        .toList()
      ..sort((a, b) {
        final tierCmp = a.stabilityTier.index.compareTo(b.stabilityTier.index);
        if (tierCmp != 0) return tierCmp;
        return b.lastSeen.compareTo(a.lastSeen);
      });

    if (stored.isNotEmpty) {
      final probeCount = stored.length < 5 ? stored.length : 5;
      _log.info('§4.5 Cascade Tier 1: probing $probeCount stored peers (all reachable addresses)');
      for (final peer in stored.take(5)) {
        if (_discoveryComplete) return;
        for (final target in peer.allConnectionTargets()) {
          if (target.ip.isNotEmpty && target.port > 0 &&
              target.isReachableFromCurrentNetwork) {
            _sendPing(target.ip, target.port);
          }
        }
      }
      // PINGs produce PONGs but NOT PEER_LIST_PUSH. Send PEER_LIST_WANT
      // alongside to explicitly trigger a PUSH response → _onDiscoveryComplete.
      final wantData = proto.PeerListWant();
      for (final peer in stored.take(20)) {
        wantData.wantedNodeIds.add(peer.nodeId);
      }
      final wantBytes = wantData.writeToBuffer();
      for (final peer in stored.take(3)) {
        for (final addr in _filterNatContext(
            peer.allConnectionTargets(), peer)) {
          sendInfraDirect(
            messageType: proto.MessageTypeV3.MTV3_PEER_LIST_WANT,
            innerPayload: wantBytes,
            recipientDeviceId: peer.nodeId,
            addr: InternetAddress(addr.ip),
            port: addr.port,
          );
        }
        _outstandingPeerListWants[peer.nodeIdHex] = DateTime.now();
      }
      // Wait up to 5 s for PEER_LIST_PUSH response
      for (var i = 0; i < 10 && !_discoveryComplete; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
      if (_discoveryComplete) return;
      _log.info('§4.5 Cascade Tier 1 exhausted — no stored peer responded');
    }

    // Tier 2 — LAN Discovery: broadcast + multicast burst.
    _log.info('§4.5 Cascade Tier 2: LAN broadcast/multicast');
    localDiscovery.triggerFastDiscovery();
    multicastDiscovery.triggerFastDiscovery();
    for (var i = 0; i < 10 && !_discoveryComplete; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
    }
    if (_discoveryComplete) return;
    _log.info('§4.5 Cascade Tier 2 exhausted — no LAN peer found');

    // Tier 3 — Bootstrap: unicast probe to cached bootstrap addresses.
    // On Android/GUI, _isolatedNodeBootstrapAddrs is empty (no --bootstrap
    // CLI param). Derive bootstrap targets from stored peers' reachable
    // addresses (uses isReachableFromCurrentNetwork: includes same-subnet
    // private IPs on WiFi, excludes them on Mobilfunk/CGNAT).
    var tier3Addrs = _isolatedNodeBootstrapAddrs.toList();
    if (tier3Addrs.isEmpty) {
      final bsPort = NetworkSecret.channel.defaultBootstrapPort;
      for (final peer in stored) {
        for (final addr in peer.allConnectionTargets()) {
          if (addr.ip.isEmpty || addr.port <= 0) continue;
          if (!addr.isReachableFromCurrentNetwork) continue;
          final fmt = addr.ip.contains(':') ? '[${addr.ip}]' : addr.ip;
          final peerAddr = '$fmt:${addr.port}';
          if (!tier3Addrs.contains(peerAddr)) tier3Addrs.add(peerAddr);
          // §4.5 Tier 3: also probe channel-default bootstrap port (§17.5)
          if (addr.port != bsPort) {
            final bsAddr = '$fmt:$bsPort';
            if (!tier3Addrs.contains(bsAddr)) tier3Addrs.add(bsAddr);
          }
        }
      }
    }
    if (tier3Addrs.isNotEmpty) {
      _log.info('§4.5 Cascade Tier 3: bootstrap probe '
          '(${tier3Addrs.length} address(es)${_isolatedNodeBootstrapAddrs.isEmpty ? ", derived from stored peers" : ""})');
      for (final addr in tier3Addrs) {
        _addBootstrapPeer(addr);
      }
      for (var i = 0; i < 10 && !_discoveryComplete; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
      if (_discoveryComplete) return;
      _log.info('§4.5 Cascade Tier 3 exhausted — bootstrap unreachable');
    }

    // Tier 3b — External Rendezvous (§4.11 + §4.11.9): two parallel paths.
    // (A) Contact-Rendezvous: resolve contact devices via device-scoped tags.
    // (B) Infra-Rendezvous: resolve network entry-points via network-wide tag.
    // Run regardless of _discoveryComplete: rendezvous is not just a cold-start
    // fallback; it also refreshes entry-points and contact endpoints even after
    // bootstrap peers have been found.
    if (rendezvousManager != null ||
        infraRendezvousManager != null ||
        binaryRendezvousManager != null) {
      _log.info('§4.5 Cascade Tier 3b: external rendezvous resolve');
      try {
        final futures = <Future>[];

        // Path A: Contact-Rendezvous (§4.11.4) — shared helper, stamps the
        // §4.11.11 per-contact cooldown so a reactive resolve right after
        // the cascade does not double-query the providers.
        if (rendezvousManager != null) {
          futures.add(_resolveContactRendezvousFor(
              rendezvousManager!.contactsSnapshot,
              reason: 'tier3b'));
        }

        // Path B: Infrastructure-Rendezvous (§4.11.9)
        if (infraRendezvousManager != null) {
          futures.add(() async {
            final infraEps =
                await infraRendezvousManager!.resolve();
            for (final ep in infraEps) {
              for (final addr in ep.addresses) {
                _sendPing(addr.ip, addr.port);
              }
            }
            if (infraEps.isNotEmpty) {
              _log.info('§4.11.9 Infra-RV: resolved '
                  '${infraEps.length} entry-point(s)');
            }
          }());
        }

        // Path C: Binary-Distribution-Rendezvous (§19.6.5) — resolve nodes
        // serving this platform's binary/fragments, so in-network update
        // assembly has candidate sources without waiting for a full network
        // scan. Read-only (resolve), independent of whether this device
        // itself has anything to publish.
        if (binaryRendezvousManager != null) {
          futures.add(() async {
            final binEps =
                await binaryRendezvousManager!.resolve(Platform.operatingSystem);
            for (final ep in binEps) {
              for (final addr in ep.addresses) {
                _sendPing(addr.ip, addr.port);
              }
            }
            if (binEps.isNotEmpty) {
              _log.info('§19.6.5 Binary-RV: resolved ${binEps.length} '
                  'node(s) serving ${Platform.operatingSystem} binary');
            }
          }());
        }

        await Future.wait(futures);

        if (!_discoveryComplete) {
          for (var i = 0; i < 10 && !_discoveryComplete; i++) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
      } catch (e) {
        _log.debug('§4.11 Rendezvous resolve failed: $e');
      }
      if (_discoveryComplete) return;
    }

    // Tier 4 — Subnet Scan (last resort).
    _log.info('§4.5 Cascade Tier 4: subnet scan');
    localDiscovery.startSubnetScan(
        _localIps, () => _discoveryComplete);

    // Arm isolated-node timer if routing table is empty.
    if (routingTable.peerCount == 0) {
      _armIsolatedNodeTimer();
    }
  }

  /// Called once when the first PEER_LIST_PUSH with ≥1 entry arrives.
  /// Transitions from discovery to normal operation: fires deferred peer
  /// exchange, address broadcast, and Kademlia bootstrap.
  void _onDiscoveryComplete() {
    if (_discoveryComplete) return;
    _discoveryComplete = true;
    _discoveryCascadeTimer?.cancel();
    _discoveryCascadeTimer = null;
    _log.info('§4.5 Discovery complete — transitioning to normal operation');

    // Cold-start jitter (0–3 s) before the post-discovery burst (§4.5).
    final jitterMs = Random().nextInt(3000);
    Future.delayed(Duration(milliseconds: jitterMs), () {
      if (!_running) return;
      // Peer exchange + address broadcast — now safe, we have a live mesh.
      if (routingTable.peerCount > 0) {
        _doPeerExchange();
        _broadcastAddressUpdate(force: true);
      }
      // Kademlia bootstrap — populate DHT after we know the mesh.
      _kademliaBootstrap();
      // Retry port probes that failed at startup due to "no confirmed peer".
      // Now that we have a live peer, the probe can succeed.
      final extIp = natTraversal.publicIpForNatContext;
      if (!natTraversal.hasPublicIp && extIp != null) {
        _initiatePortProbe(extIp);
      }
      _probeIpv6Inbound();
      onDiscoveryComplete?.call();
      // §4.11.11 trigger 3: once per discovery cycle, re-resolve contacts
      // that are still unreachable after the cascade finished.
      requestContactResolve(reason: 'discovery-complete');
    });
  }

  // ── V3.0 Receive Pipeline (Architecture v3.0 §2.4 receiver steps 3-7) ──

  /// Callback for locally-delivered NetworkPacketV3. Called from
  /// [_onPacketV3Received] when nextHopDeviceId == myDeviceId. The receiver
  /// (cleona_service) is responsible for KEM-decap, ApplicationFrame parse,
  /// User-Sig verify (V3FrameCodec.decryptAndVerifyInner) and dispatch.
  ///
  /// Welle 6 (§2.4.0): `snapshot` carries the outcome of step §2.4 [4]
  /// (Outer Device-Sig-Verify) so type-specific handlers can gate trust-
  /// elevating actions (e.g. F4 Re-Contact-Auto-Overwrite, §8.1).
  void Function(proto.NetworkPacketV3 packet, InternetAddress from, int fromPort,
          SenderIdentitySnapshot snapshot)?
      onApplicationFramePayload;

  /// Receiver-side V3 pipeline (Architecture v3.0 §2.4 steps 3-7).
  ///
  /// `network_tag` (HMAC) was already verified by [Transport]; this method
  /// covers timestamp window, DoS gates, Device-Sig-Verify, PoW-Verify,
  /// DV-Routing neighbor learning, and the routing decision (forward vs
  /// local delivery). Local delivery hands the packet to
  /// [onApplicationFramePayload] for inner KEM-decap + User-Sig-Verify.
  void _onPacketV3Received(
    proto.NetworkPacketV3 packet,
    InternetAddress from,
    int fromPort, {
    bool isUdp = false,
  }) {
    // [3] Timestamp window: ±60s replay protection (Architecture §2.4 step 3).
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final tsDelta = (nowMs - packet.timestampMs.toInt()).abs();
    if (tsDelta > 60 * 1000) {
      _log.debug('V3 drop: timestamp window violation (${tsDelta}ms)');
      return;
    }

    // [3b] Duplicate-frame check (Architecture §2.4 step 3b): silently drop
    // byte-identical replays of HMAC-valid frames inside the 60s window
    // (BOOT-RPCs, HOLE_PUNCH_*, DHT_PING/PONG, DELIVERY_RECEIPT, call frames).
    if (packet.networkTag.isNotEmpty &&
        _frameDedup.isDuplicate(bytesToHex(Uint8List.fromList(packet.networkTag)))) {
      _log.debug('V3 drop: duplicate frame (replay dedup) type=${packet.payloadType.name}');
      return;
    }

    final senderDeviceId = Uint8List.fromList(packet.senderDeviceId);
    final senderHex = senderDeviceId.isNotEmpty ? bytesToHex(senderDeviceId) : '';

    // DoS Layer 3+5: Ban check — banned senders silently dropped.
    if (senderHex.isNotEmpty && reputationManager.isBanned(senderHex)) {
      _log.warn('V3 drop: banned sender ${senderHex.substring(0, 8)} type=${packet.payloadType.name}');
      return;
    }

    // D5 (§13.1.3 Collective quota): source classification. A sender is
    // "introduced" once its admission PoW verified (D3, Phase 2 hard
    // enforcement V3.1.90+). The firstParty exemption was removed — every
    // source must carry a verified admission proof to escape the collective
    // pool. This makes pool exemption CPU-bound per ID (22-bit PoW).
    final senderPeer = senderDeviceId.isNotEmpty
        ? routingTable.getPeer(senderDeviceId)
        : null;
    final introducedSource = senderPeer != null &&
        senderPeer.idPowVerified;

    // DoS Layer 2: Rate limiting per sender device.
    // PAYLOAD_BOOTSTRAP_INFRASTRUCTURE_FRAME is plaintext (cheap to forge) →
    // full per-source limits apply.  KEM-encrypted frames (INFRASTRUCTURE_FRAME
    // and APPLICATION_FRAME) are expensive to produce, so their natural
    // rate limit is CPU-bound; only the global total-byte limit applies.
    if (senderHex.isNotEmpty) {
      final pktSize = packet.writeToBuffer().length;
      final isBootInfra = packet.payloadType == proto.PayloadTypeV3.PAYLOAD_BOOTSTRAP_INFRASTRUCTURE_FRAME;
      if (!rateLimiter.allowPacketHex(senderHex, pktSize,
          checkPacketCount: isBootInfra, checkSourceLimits: isBootInfra,
          pooled: !introducedSource)) {
        _log.debug('V3 drop: rate-limited ${senderHex.substring(0, 8)} pkt=${pktSize}B type=${packet.payloadType.name}');
        return;
      }
      reputationManager.recordGood(senderHex);
    }
    _log.debug('V3 recv ok: type=${packet.payloadType.name} from ${senderHex.isEmpty ? "?" : senderHex.substring(0, 8)} isUdp=$isUdp');

    // Mark session as having received at least one valid peer packet
    // (HMAC + timestamp window + ban check + rate-limit all passed).
    // Read by _hasRecentlyReachablePeer() to gate Stage-5 Re-Discovery
    // per Architecture §5.10.5. See field doc.
    _authenticatedReceivesInSession++;

    // [4] Device-Sig-Verify (Architecture §2.4 step 4). Lookup the sender's
    // *Device*-Sig PK via routing table. Welle 3 (§17.3): the cached
    // `deviceEd25519PublicKey` / `deviceMlDsaPublicKey` are the per-device
    // signing keys (distinct from the User-Sig PKs that share the
    // `ed25519PublicKey` field). Bootstrap path: no Device-Sig PK on file →
    // lenient pass; the next self-broadcast PEER_LIST_PUSH installs the PK
    // and subsequent packets verify strictly.
    // (senderPeer was already looked up before the rate-limit step — D5.)
    final edPk = senderPeer?.deviceEd25519PublicKey;
    OuterSigStatus outerStatus;
    if (edPk != null) {
      final ok = V3FrameCodec.verifyOuterDeviceSig(
        packet: packet,
        senderDeviceEd25519Pk: edPk,
        senderDeviceMlDsaPk: senderPeer?.deviceMlDsaPublicKey,
      );
      if (!ok) {
        // §5.10.2 Stale-PK Recovery — if this senderId is a known peer for
        // which we have a *firstParty* PK on file, the most likely cause of
        // a fresh `device_sig_invalid` is a key rotation we haven't learned
        // about yet, not an adversary forging packets. Treat the failure as
        // a refresh signal: mark the cached PK stale and fire ONE BOOT-path
        // DHT_PING so the peer's reply (PONG + follow-up self-broadcast
        // PEER_LIST_PUSH) repopulates the cache with the rotated PK. The
        // `pkStale` flag (a) suppresses reputation hits while recovery is
        // in flight and (b) lets the next firstParty Self-Broadcast
        // overwrite the cached PK even though pkSource is already firstParty
        // (see `PeerInfo.setSigningKeys` §5.10.5 carve-out). Sender side does
        // NOT block on this — Stage 2 is fire-and-forget; Stages 1/3/4/5 of
        // the cascade run in parallel on their own counters.
        if (senderPeer != null &&
            senderPeer.pkSource != PkSource.none &&
            !senderPeer.pkStale) {
          // §5.10.2 key-rotation path: fire refresh probe, but do NOT drop.
          // HMAC already proves network membership; sig failure on a known
          // peer (firstParty OR thirdParty/gossip-sourced) almost always
          // means key rotation (e.g. profile wipe, device restart with
          // regenerated keys), not spoofing. The inner handler validates at
          // its own trust level using outerStatus=skippedBootstrap. Dropping
          // here would silently block the re-contact-request that carries
          // the new key.
          _triggerStalePkRecovery(senderPeer);
          outerStatus = OuterSigStatus.skippedBootstrap;
        } else if (senderPeer?.pkStale == true) {
          // Recovery already in flight — let through with the same lenient
          // status; the probe's ≥30s throttle prevents probe storms.
          outerStatus = OuterSigStatus.skippedBootstrap;
        } else {
          // No PK cache at all (pkSource==none) OR unknown sender using a
          // known device-id. Silent drop, NO reputation hit: a *failed*
          // device-sig means `senderDeviceId` is exactly the unproven
          // field — the HMAC proves only network membership. An insider
          // could otherwise forge a frame with a victim's deviceId + valid
          // HMAC + broken sig to frame the victim into a ban
          // (Ban-DoS-by-framing). See §13.1.4 attribution precondition.
          _log.debug('V3 drop: device-sig invalid from '
              '${senderHex.isNotEmpty ? senderHex.substring(0, 8) : "<unknown>"}');
          return;
        }
        // outerStatus already set to skippedBootstrap in the branches above.
      } else {
        outerStatus = OuterSigStatus.verified;
      }
      // Self-heal: if Ed25519 passed but ML-DSA device PK is missing (slim
      // gossip omits PQ keys), request the full key set so future packets
      // get full hybrid verification.
      if (senderPeer != null &&
          senderPeer.deviceMlDsaPublicKey == null &&
          senderDeviceId.isNotEmpty) {
        _sendPeerKeyRequest(senderDeviceId);
      }
    } else {
      // No PK on file → lenient pass (bootstrap, §2.4.0).
      outerStatus = OuterSigStatus.skippedBootstrap;
    }

    // §2.4.0 — build the snapshot once, thread it through both inner-frame
    // hooks. `senderUserId` is empty here; inner handlers fill it in after
    // parsing ApplicationFrame.senderUserId / the wrapped CR payload.
    final snapshot = SenderIdentitySnapshot(
      senderDeviceId: senderDeviceId,
      senderUserId: Uint8List(0),
      outerSigStatus: outerStatus,
      verifiedDeviceEd25519Pk: outerStatus == OuterSigStatus.verified ? edPk : null,
      verifiedDeviceMlDsaPk: outerStatus == OuterSigStatus.verified
          ? senderPeer?.deviceMlDsaPublicKey
          : null,
      newKeyDetectedForSenderUser: false,
      receivedAt: DateTime.now(),
    );

    // [5] PoW-Verify (Architecture §2.4 step 5). Skip for LAN peers — the
    // sender side mirrors this and omits PoW for same-subnet targets.
    final isLanPeer = !PeerAddress.isPrivateIp(from.address) ? false :
        _localIps.any((ip) => _samePrivateNetwork(from.address, ip));
    if (!isLanPeer && packet.hasPow()) {
      if (!ProofOfWork.verify(Uint8List.fromList(packet.payload), packet.pow)) {
        // §13.1.4 attribution precondition: PoW covers only the payload, not
        // `senderDeviceId`. Attribute the bad PoW only when the outer
        // device-sig verified for this packet — otherwise the sender is
        // unproven (bootstrap/stale-PK lenient pass) and a `recordBad` would
        // be framable. When verified, the senderDeviceId is proven and the
        // penalty is sound.
        if (senderHex.isNotEmpty && outerStatus == OuterSigStatus.verified) {
          reputationManager.recordBad(senderHex, 'pow_invalid');
        }
        _log.debug('V3 drop: PoW invalid from '
            '${senderHex.isNotEmpty ? senderHex.substring(0, 8) : "<unknown>"}');
        return;
      }
    }

    // DV-Routing: register sender as direct neighbor. Routing keys are
    // deviceNodeIds in V3 by construction.
    // Guard: only for direct packets (hopCount==0). Relayed packets carry
    // the originator's senderDeviceId but arrive from the relay node's IP.
    // Without this guard, _touchPeer maps the originator to the relay's
    // address → routing table pollution (B-28).
    if (senderDeviceId.isNotEmpty && from.address != '0.0.0.0' && packet.hopCount == 0) {
      final addr = PeerAddress(ip: from.address, port: fromPort);
      final ct = connectionTypeFromPriority(addr.priority);
      final isNewNeighbor = dvRouting.addDirectNeighbor(senderDeviceId, ct);
      _confirmedPeers[senderHex] = DateTime.now();
      _notifyEndpointConfirmed(senderHex);
      if (!hasSessionConfirmedPeers) {
        hasSessionConfirmedPeers = true;
        _log.info('First session-confirmed peer: ${senderHex.substring(0, 8)}');
      }
      // §4.5: first confirmed peer → disarm isolated-node retry.
      _disarmIsolatedNodeTimer();
      _zeroPeerRecoveryTimer?.cancel();
      _zeroPeerRecoveryTimer = null;

      // DV-3 bias fix: receiving a direct packet (hopCount=0) proves
      // bidirectional reachability — same as DELIVERY_RECEIPT. Without
      // this, infra-only peers (Bootstrap ↔ Node) never get ackConfirmed,
      // the +10 bias makes indirect routes win, and relay loops form.
      dvRouting.confirmRoute(senderHex);

      // Cross-subnet fix (2026-05-06): for same-subnet peers, LAN multicast
      // Discovery → `_onDiscoveryReceived` → `_touchPeer` populates
      // `routingTable` *before* the first DHT_PING arrives. For cross-subnet
      // peers (e.g. 192.168.10.x ↔ 192.0.2.x via DNAT), multicast does not
      // cross the router, so `_touchPeer` never fires and `routingTable`
      // remains empty for the new neighbor — even though `dvRouting` knows
      // about it. The result: `_sendV3ViaHop` (line ~1734) and
      // `_sendWelcomeRouteUpdate` (line ~2845) both look up the peer via
      // `routingTable.getPeer` and find nothing → "cascade exhausted
      // (routes=1)" / "Welcome skipped — not in routing table". Mirroring the
      // discovery-side behaviour here keeps the two tables in sync regardless
      // of the discovery channel that brought the peer in.
      _touchPeer(senderDeviceId, from.address, fromPort,
          isAuthoritative: true, isUdp: isUdp);

      _debouncedNetworkStateSave();

      if (isNewNeighbor) {
        _log.info('DV: New neighbor ${senderHex.substring(0, 8)} from '
            '${from.address}:$fromPort (${ct.name}) '
            '— routing table populated via _touchPeer');
        // §4.5: welcome route updates and self-broadcasts are deferred until
        // discovery completes. During discovery, the peer list from the first
        // responding peer provides routes — no need to flood the mesh.
        if (_discoveryComplete) {
          _lastRouteUpdateSentTo[senderHex] = DateTime.now();
          Timer(const Duration(milliseconds: 500), () {
            _sendWelcomeRouteUpdate(senderHex);
            // §4.5: push top-N known peers to the new neighbor so it
            // learns PeerInfo (addresses, userId) immediately — not just
            // DV routes which carry no addresses.
            _pushTopNPeersToNewNeighbor(senderDeviceId);
          });
          _pushSelfToNeighborsExcept(senderDeviceId);
          // §5.11: push our own Self-Broadcast BACK to the new neighbor.
          // Seed peers from ContactSeed (§8.1.1) carry no PK/nonce — the
          // new neighbor can only verify our admission PoW (D3, §13.1.2)
          // after receiving this push. Without it, admission verification
          // waits for the 1h cold-path, blocking relay for First-CRs.
          _pushSelfToPeer(senderDeviceId);
          _log.info('§5.11: new-neighbor self-push to '
              '${senderHex.substring(0, 8)}');
        } else {
          _log.debug('DV: Welcome/push deferred — discovery not complete');
        }
      } else if (_discoveryComplete) {
        _maybeSendCatchUpRouteUpdate(senderHex);
      }

      // Reset failure counters — direct packet proves reachability.
      if (senderPeer != null) {
        if (senderPeer.consecutiveRouteFailures > 0) {
          senderPeer.consecutiveRouteFailures = 0;
        }
        if (senderPeer.consecutiveRelayFailures > 0) {
          senderPeer.consecutiveRelayFailures = 0;
        }
      }

      // Public-IP-Trigger for port mapping (one-shot per startup/network-change
      // cycle: covers the edge case where the node starts offline and later
      // gains internet connectivity).
      if (!_portMapperPublicIpRetried &&
          !PeerAddress.isPrivateIp(from.address) &&
          !natTraversal.hasPortMapping &&
          portMapper.state != PortMapperState.acquiring &&
          portMapper.state != PortMapperState.mapped) {
        _portMapperPublicIpRetried = true;
        _log.info('Public-IP peer detected (${from.address}) — starting port mapping (one-shot)');
        portMapper.start();
      }
    }

    // [5b] Reverse-Relay-Path-Learning (§5.3): when we receive a relayed
    // packet (hopCount > 0) from originator S, learn "S is reachable via
    // the relay that forwarded this packet". This enables reply-path
    // symmetry for NAT-asymmetric scenarios (e.g. mobile sends via
    // Bootstrap, we can relay back via Bootstrap).
    if (senderDeviceId.isNotEmpty && packet.hopCount > 0 && from.address != '0.0.0.0') {
      final relayNeighborHex = _learnReverseRelayPath(senderHex, from.address, fromPort);
      if (relayNeighborHex != null) {
        dvRouting.confirmRoute(senderHex, viaNextHopHex: relayNeighborHex);
      }
    }

    // [6] Routing decision: am I the next hop?
    // Per §3.1 the DeviceID is daemon-global — all hosted identities share
    // the same deviceNodeId. Equality with primaryIdentity.deviceNodeId is
    // sufficient; no per-identity hostedDeviceIds set needed.
    final nextHop = Uint8List.fromList(packet.nextHopDeviceId);
    final myDeviceId = primaryIdentity.deviceNodeId;
    final isLocal = _bytesEqual(nextHop, myDeviceId);

    if (!isLocal) {
      // §3.7.3 Relay loop prevention — originator check: if we originated
      // this packet and it came back via relay, it has looped. Drop.
      if (_bytesEqual(senderDeviceId, myDeviceId)) {
        _log.debug('V3 relay drop: originator loop '
            '(dest=${bytesToHex(nextHop).substring(0, 8)})');
        return;
      }
      // §5.3 Visited-array loop prevention: if ANY of our local deviceIds
      // appears in visited_device_ids, the packet has looped through us.
      // Multi-identity-aware: checks all registered identities, not just primary.
      for (final visited in packet.visitedDeviceIds) {
        if (_identitiesByDeviceId.containsKey(bytesToHex(Uint8List.fromList(visited)))) {
          _log.debug('V3 relay drop: visited-array loop '
              '(dest=${bytesToHex(nextHop).substring(0, 8)})');
          return;
        }
      }
      // Forward as relay. Decrement TTL, increment hopCount.
      if (packet.ttl <= 0 || packet.hopCount >= RelayBudget.maxHops) {
        _log.debug('V3 relay drop: ${packet.ttl <= 0 ? "TTL exhausted" : "maxHops=${RelayBudget.maxHops}"} '
            'for ${bytesToHex(nextHop).substring(0, 8)} '
            '(ttl=${packet.ttl} hops=${packet.hopCount})');
        return;
      }
      // Relay dedup: same packet arriving via multiple paths must only
      // be forwarded once. Key = sender + timestamp + payload fingerprint.
      final dedupKey = '${senderHex.substring(0, 8)}:'
          '${packet.timestampMs}:${packet.payload.length}:'
          '${packet.payload.length > 16 ? bytesToHex(Uint8List.fromList(packet.payload.sublist(0, 16))) : bytesToHex(Uint8List.fromList(packet.payload))}';
      if (_relayDedup.isDuplicate(dedupKey)) {
        _log.debug('V3 relay drop: dedup '
            '${bytesToHex(nextHop).substring(0, 8)}');
        return;
      }
      // §4.6 (V3.1.72): relay-forward gates on REACHABILITY, not
      // direct-confirmed. A relay node almost never has direct-confirmed
      // status for a final destination it only forwards to (esp. CGNAT
      // targets — that is exactly why relay exists). Drop only if we have
      // no alive route (direct or onward-relay) to forward along.
      final nextHopHex = bytesToHex(nextHop);
      if (!dvRouting.hasAliveRouteTo(nextHopHex)) {
        _log.debug('V3 relay drop: dest ${nextHopHex.substring(0, 8)} no alive route');
        return;
      }
      // D5 (§5.3): collective forward slice for non-introduced origins.
      // `introducedSource` classifies packet.senderDeviceId — for a relayed
      // packet that IS the originator, exactly the identity whose forward
      // amplification the pool bounds. Introduced origins skip this entirely.
      if (!introducedSource && !_relayPoolAllow(packet.payload.length)) {
        _log.debug('V3 relay drop: pooled-origin slice exhausted '
            '(${senderHex.substring(0, 8)}, '
            '$_relayPoolMessages msgs/${_relayPoolBytes ~/ 1024}KB this window)');
        return;
      }
      // §3.7.3 Reverse-path loop prevention: resolve who sent this packet
      // to us (by IP) and exclude them as next-hop candidate so we don't
      // bounce the packet right back.
      final relaySenderHex = _resolveDeviceHexFromAddress(from.address);
      _log.info('V3 relay forward: ${packet.payloadType.name} '
          '${packet.payload.length}B ttl=${packet.ttl} '
          'from ${senderHex.substring(0, 8)} → ${nextHopHex.substring(0, 8)}'
          '${relaySenderHex != null ? " (excl ${relaySenderHex.substring(0, 8)})" : ""}');
      packet.ttl = packet.ttl - 1;
      packet.hopCount = packet.hopCount + 1;
      // §5.3 Append ALL local deviceIds to visited_device_ids so downstream
      // relays can detect multi-identity loops.
      for (final ctx in _identitiesByDeviceId.values) {
        packet.visitedDeviceIds.add(ctx.deviceNodeId);
      }
      // Fire-and-forget relay forward — exclude the relay sender from
      // route candidates to prevent 2-node bounce loops.
      // expectsReply: false — relay nodes never receive the E2E
      // DELIVERY_RECEIPT (that goes to the originator), so counting
      // relay-forwards as unACK'd would monotonically inflate the
      // counter and trigger spurious Stage-4 Mesh Refresh storms.
      sendToDevice(packet, nextHop,
              excludeNextHopHex: relaySenderHex, isRelay: true,
              expectsReply: false)
          .then((ok) {
        if (!ok) {
          _log.warn('V3 relay send FAILED to ${nextHopHex.substring(0, 8)} '
              '(routes=${dvRouting.routesTo(nextHopHex).length})');
        }
      });
      return;
    }

    // [7] Local delivery — see [_deliverLocalV3Packet]. Factored out so the
    // §5.4 erasure-coded reassembly path can re-use the local-delivery branch
    // without going through routing/timestamp/HMAC again.
    if (packet.payloadType == proto.PayloadTypeV3.PAYLOAD_INFRASTRUCTURE_FRAME) {
      _log.info('V3 local deliver: INFRA ${packet.payload.length}B '
          'from ${senderHex.isEmpty ? "?" : senderHex.substring(0, 8)}');
    }
    _deliverLocalV3Packet(packet, from, fromPort, snapshot);
  }

  /// Local-delivery branch of the V3 receive pipeline (Architecture §2.4
  /// receiver step 7+). Called from [_onPacketV3Received] after the routing
  /// decision concluded "next-hop is me", and from [dispatchReassembledPacket]
  /// after Reed-Solomon reassembly forces local delivery (§5.4).
  void _deliverLocalV3Packet(
    proto.NetworkPacketV3 packet,
    InternetAddress from,
    int fromPort,
    SenderIdentitySnapshot snapshot,
  ) {
    if (packet.payloadType ==
        proto.PayloadTypeV3.PAYLOAD_INFRASTRUCTURE_FRAME) {
      // Receiver pipeline (§2.4.1 [8'-14']) — inline KEM-decap with the
      // daemon-global Device-KEM private keys, validate selector + recipient,
      // then dispatch the typed InfrastructureFrameV3 to the consumer hook.
      // V3FrameCodec absorbs every drop case (parse / KEM / selector /
      // recipient mismatch) and returns a typed result.
      // Per §3.1 the DeviceID is daemon-global — recipient check is plain
      // equality with myDeviceId; the Welle-5 isLocalDeviceId callback is
      // obsolete (one deviceId per daemon, regardless of hosted identities).
      final result = V3FrameCodec.decryptAndVerifyInfrastructure(
        innerPayload: Uint8List.fromList(packet.payload),
        ourDeviceKemX25519Sk: _deviceKeys.kem.x25519PrivateKey,
        ourDeviceKemMlKemSk: _deviceKeys.kem.mlKemPrivateKey,
        myDeviceId: primaryIdentity.deviceNodeId,
      );
      final frame = result.frame;
      if (frame == null) {
        _log.debug(
            'V3 INFRA drop: ${result.error?.name ?? "unknown"} '
            '(sender=${bytesToHex(Uint8List.fromList(packet.senderDeviceId)).substring(0, 8)})');
        return;
      }
      final senderDeviceId = Uint8List.fromList(packet.senderDeviceId);
      // Node-local infrastructure dispatch — types whose handlers live in the
      // node layer (identityDhtHandler, etc.) are processed inline; everything
      // else falls through to the consumer hook so the service / future
      // node-local handlers can pick it up.
      if (_dispatchInfrastructureFrameLocal(
          frame, senderDeviceId, from, fromPort)) {
        return;
      }
      final hook = onInfrastructureFramePayload;
      if (hook == null) {
        _log.debug(
            'V3 INFRA drop: no onInfrastructureFramePayload hook wired '
            '(messageType=${frame.messageType.name})');
        return;
      }
      hook(frame, senderDeviceId, from, fromPort, snapshot);
      return;
    }

    if (packet.payloadType ==
        proto.PayloadTypeV3.PAYLOAD_BOOTSTRAP_INFRASTRUCTURE_FRAME) {
      // BOOT-path receiver: outer.payload is a serialized
      // InfrastructureFrameV3 *plaintext* (no KEM, no zstd). Closed-Network
      // HMAC + Outer Device-Sig were already validated at the caller; here
      // we parse the inner directly, enforce the strict BOOT-subset
      // selector (drops cross-layer abuse attempts that try to skip the
      // KEM wrapper for non-bootstrap types), and dispatch via the same
      // hooks as the KEM path. PUBLISH-RPCs (IDENTITY_AUTH/LIVE/KEM_PUBLISH)
      // re-verify the inner-record signature in their existing handler —
      // unchanged from the KEM path, since the inner record is identical.
      // Per §3.1 the DeviceID is daemon-global — recipient check is plain
      // equality (no isLocalDeviceId callback needed).
      final result = V3FrameCodec.decryptAndVerifyBootstrapInfrastructure(
        innerPayload: Uint8List.fromList(packet.payload),
        myDeviceId: primaryIdentity.deviceNodeId,
      );
      final frame = result.frame;
      if (frame == null) {
        _log.debug(
            'V3 BOOT drop: ${result.error?.name ?? "unknown"} '
            '(sender=${bytesToHex(Uint8List.fromList(packet.senderDeviceId)).substring(0, 8)})');
        return;
      }
      _log.info(
          'V3 BOOT recv: ${frame.messageType.name} '
          'from ${bytesToHex(Uint8List.fromList(packet.senderDeviceId)).substring(0, 8)}');
      final senderDeviceId = Uint8List.fromList(packet.senderDeviceId);
      if (_dispatchInfrastructureFrameLocal(
          frame, senderDeviceId, from, fromPort)) {
        return;
      }
      final hook = onInfrastructureFramePayload;
      if (hook == null) {
        _log.debug(
            'V3 BOOT drop: no onInfrastructureFramePayload hook wired '
            '(messageType=${frame.messageType.name})');
        return;
      }
      hook(frame, senderDeviceId, from, fromPort, snapshot);
      return;
    }

    if (packet.payloadType != proto.PayloadTypeV3.PAYLOAD_APPLICATION_FRAME) {
      _log.warn('V3 drop: unsupported payloadType ${packet.payloadType}');
      return;
    }

    // §13.1 PoW verification for ApplicationFrames.
    // Exempt: LAN peers (private IP), relay-delivered packets (0.0.0.0), and
    // §13.1.2 exemption #4 — devices registered as an active call's
    // live-media peer (sender used `skipPoW: true` for CALL_AUDIO/VIDEO
    // etc., see [registerLiveMediaPeer]).
    final isRelayDelivered = from.address == '0.0.0.0';
    final isLanSource = !isRelayDelivered && PeerAddress.isPrivateIp(from.address);
    final isLiveMediaSource = !isRelayDelivered &&
        !isLanSource &&
        packet.senderDeviceId.isNotEmpty &&
        isLiveMediaPeer(Uint8List.fromList(packet.senderDeviceId));
    if (!isRelayDelivered && !isLanSource && !isLiveMediaSource) {
      if (!packet.hasPow() ||
          !ProofOfWork.verify(
              Uint8List.fromList(packet.payload), packet.pow)) {
        _log.debug('V3 PoW drop: invalid/missing PoW from ${from.address}');
        return;
      }
    }
    // No per-frame log on the isLiveMediaSource skip path — fires at call
    // framerate (~50/s per direction); even debug-level logging here would
    // still pay for string formatting + ring-buffer writes on every frame.

    onApplicationFramePayload?.call(packet, from, fromPort, snapshot);
  }

  /// V3 reassembly entrypoint (Architecture §5.4 — Reed-Solomon offline
  /// delivery). Re-injects a complete `NetworkPacketV3` reconstructed from
  /// DHT-stored fragments into the local-delivery branch of the receive
  /// pipeline. Two principled deviations from the UDP path:
  /// (a) the timestamp window check is bypassed — fragments live up to
  ///     7 days in the DHT (§5.4 Lifetime), 60 s replay would drop every
  ///     reassembled packet;
  /// (b) the routing decision is forced local — by definition the
  ///     mailbox-ID pointed to *this* user, so the packet is for us; the
  ///     `nextHopDeviceId` of the canonical erasure-source may target a
  ///     sibling device of the same user (multi-device case), where naive
  ///     routing would attempt a relay forward.
  ///
  /// HMAC, Outer-Device-Sig, KEM-decap and Inner-Sig-verify run identically
  /// to the UDP path — the encoded blob is auth-bound by the original
  /// sender's keys, not by the DHT-replicator that delivered it. Drops
  /// (HMAC mismatch, parse fail, sig invalid) are silent + logged at debug.
  void dispatchReassembledPacket(Uint8List packetBytes) {
    final packet = transport.parseAndVerifyNetworkPacketV3(packetBytes);
    if (packet == null) {
      _log.debug('V3 reassembled drop: HMAC/parse invalid');
      return;
    }

    final senderDeviceId = Uint8List.fromList(packet.senderDeviceId);
    final senderHex = senderDeviceId.isNotEmpty ? bytesToHex(senderDeviceId) : '';

    // Outer-Device-Sig-Verify (§2.4 step 4). Mandatory for reassembled
    // packets — fragments could be injected into the DHT by an adversary
    // without HMAC compromise (HMAC alone proves network membership, not
    // sender authenticity). Lenient bootstrap (no PK yet) = same as UDP
    // path: accept and let the next first-party exchange teach us the PK.
    final senderPeer = senderDeviceId.isNotEmpty
        ? routingTable.getPeer(senderDeviceId)
        : null;
    // Welle 3 (§17.3): use Device-Sig PK, not User-Sig PK.
    final edPk = senderPeer?.deviceEd25519PublicKey;
    OuterSigStatus outerStatus;
    if (edPk != null) {
      final ok = V3FrameCodec.verifyOuterDeviceSig(
        packet: packet,
        senderDeviceEd25519Pk: edPk,
        senderDeviceMlDsaPk: senderPeer?.deviceMlDsaPublicKey,
      );
      if (!ok) {
        // §13.1.4 attribution precondition: a failed device-sig leaves
        // `senderDeviceId` unproven, so silent drop WITHOUT reputation hit —
        // otherwise an insider could frame a victim by injecting reassembled
        // fragments carrying the victim's deviceId + broken sig.
        _log.debug('V3 reassembled drop: device-sig invalid from '
            '${senderHex.isNotEmpty ? senderHex.substring(0, 8) : "<unknown>"}');
        return;
      }
      outerStatus = OuterSigStatus.verified;
    } else {
      outerStatus = OuterSigStatus.skippedBootstrap;
    }

    final snapshot = SenderIdentitySnapshot(
      senderDeviceId: senderDeviceId,
      senderUserId: Uint8List(0),
      outerSigStatus: outerStatus,
      verifiedDeviceEd25519Pk:
          outerStatus == OuterSigStatus.verified ? edPk : null,
      verifiedDeviceMlDsaPk: outerStatus == OuterSigStatus.verified
          ? senderPeer?.deviceMlDsaPublicKey
          : null,
      newKeyDetectedForSenderUser: false,
      receivedAt: DateTime.now(),
    );

    // Force local delivery — `from = loopback` because there is no real
    // network source for a reassembled packet; downstream code that uses
    // `from` for DV-neighbor registration is bypassed by skipping the
    // routing-decision branch entirely (we jump straight to local delivery).
    _deliverLocalV3Packet(
      packet,
      InternetAddress.loopbackIPv4,
      0,
      snapshot,
    );
  }

  /// Welle 5 (§4.3): Node-local dispatch for infrastructure frames whose
  /// handler is owned by a node-level subsystem ([identityDhtHandler] for
  /// the 2D-DHT identity-resolution records — `AuthManifest`,
  /// `LivenessRecord`, `DeviceKemRecord`). Returns `true` when the frame was
  /// consumed; `false` lets the caller fall through to the
  /// `onInfrastructureFramePayload` hook for service-side / not-yet-migrated
  /// types.
  ///
  /// Sig-Verification policy at the replicator boundary:
  ///
  /// * **AuthManifest / LivenessRecord** are signed against pubkeys we do
  ///   NOT generally have at replicator-time (the user's Master-Ed25519/
  ///   ML-DSA-65 for AuthManifest, the device-sig pubkey for LivenessRecord).
  ///   The handler explicitly delegates verification to the read-side
  ///   resolver (§4.3.4) which cross-checks via Contact-Registry /
  ///   AuthManifest chain. At this layer we trust the wire HMAC + Outer-
  ///   Device-Sig (§3.5) and forward the record into replication storage
  ///   so it survives until somebody asks for it.
  /// * **DeviceKemRecord** embeds its own `userEd25519Pk`, enabling a
  ///   self-consistency check (catches sig-corruption and parser-mismatches
  ///   on the wire boundary). Impersonation defence is the resolver's job
  ///   on read — same trust model as AUTH/LIVE.
  bool _dispatchInfrastructureFrameLocal(
      proto.InfrastructureFrameV3 frame,
      Uint8List senderDeviceId,
      InternetAddress from,
      int fromPort) {
    // §5.10.4 — any infrastructure frame from this device proves it's alive,
    // so the unACK'd-packets counter for it can come down. Especially for
    // DHT_PONG (Stage-2 reply) and PEER_LIST_PUSH (Stage-4 reply) where the
    // reply is the *signal* the cascade was waiting for. Cheap O(1) and
    // works for every messageType — fewer special cases.
    if (senderDeviceId.isNotEmpty) {
      final senderHexLocal = bytesToHex(senderDeviceId);
      _decrementUnackedPacketsToPeer(senderHexLocal);
      // Also clear under userId in case the counter was incremented under it.
      final senderPeerLocal = routingTable.getPeer(senderDeviceId);
      if (senderPeerLocal?.userId != null) {
        _decrementUnackedPacketsToPeer(bytesToHex(senderPeerLocal!.userId!));
      }
      // A BOOT-path response (e.g. DHT_PONG) proves bidirectional
      // reachability just like an ApplicationFrame with hopCount==0.
      // On Mobilfunk/CGNAT, BOOT is the ONLY inbound path — without this,
      // hasSessionConfirmedPeers stays false and the QR convergence gate
      // never opens.
      if (from.address != '0.0.0.0') {
        _confirmedPeers[senderHexLocal] = DateTime.now();
        _notifyEndpointConfirmed(senderHexLocal);
        if (!hasSessionConfirmedPeers) {
          hasSessionConfirmedPeers = true;
          _log.info('First session-confirmed peer (BOOT): '
              '${senderHexLocal.substring(0, 8)}');
        }
        _disarmIsolatedNodeTimer();
        // F3 (S123 UDP-dead RCA): a BOOT frame is receive-only proof — it
        // fires for inbound requests (e.g. DHT_PING) just as much as
        // replies, and on Mobilfunk/CGNAT a single chatty peer (observed:
        // Bootstrap IPv6 trickle, ~1.5 pkt/min) can keep this branch
        // running indefinitely while OUR sends are black-holed. Only
        // disarm the zero-peer recovery loop once send-path liveness is
        // ALSO confirmed — otherwise let it keep retrying.
        if (_outboundRecentlyConfirmed) {
          _zeroPeerRecoveryTimer?.cancel();
          _zeroPeerRecoveryTimer = null;
        }
      }
    }
    switch (frame.messageType) {
      case proto.MessageTypeV3.MTV3_IDENTITY_AUTH_PUBLISH:
        try {
          final p = proto.AuthManifestProto.fromBuffer(frame.payload);
          identityDhtHandler.handleAuthPublish(AuthManifest.fromProto(p));
        } catch (e) {
          _log.debug('AUTH_PUBLISH drop: parse error: $e');
        }
        return true;
      case proto.MessageTypeV3.MTV3_IDENTITY_LIVE_PUBLISH:
        try {
          final p = proto.LivenessRecordProto.fromBuffer(frame.payload);
          final live = LivenessRecord.fromProto(p);
          identityDhtHandler.handleLivePublish(live);
          // Welle 5 §4.3 (multi-identity routability): also seed the
          // routing-table with the announced device — Liveness carries
          // userId + deviceId + concrete addresses, which is exactly the
          // tuple `sendToDevice` / DV-routing needs to compute a path. In
          // a multi-identity-on-one-daemon setup (two identities on the same
          // physical node) the secondary identity never bonds via the V3
          // BOOT-cascade on its own (the daemon already V3-bonded with
          // its primary identity), so without this hop a sender that has
          // resolved the secondary identity's KEM record via 2D-DHT still
          // fails the actual `sendToDevice` because routes are absent.
          //
          // The PeerInfo carries the LivenessRecord's addresses; the
          // routing table will deduplicate against any existing entry for
          // the same deviceNodeId. We deliberately do NOT touch
          // confirmedPeer state here — that requires a wire round-trip,
          // and these addresses are still hearsay until the BOOT-cascade
          // verifies them.
          if (live.addresses.isNotEmpty) {
            final addrs = <PeerAddress>[];
            for (final pa in live.addresses) {
              final a = PeerAddress.fromProto(pa);
              if (a != null) addrs.add(a);
            }
            if (addrs.isNotEmpty) {
              final peer = PeerInfo(
                nodeId: live.deviceNodeId,
                userId: live.userId,
                addresses: addrs,
                lastSeen: DateTime.fromMillisecondsSinceEpoch(live.publishedAtMs),
              );
              routingTable.addPeer(peer);
              // K-3: Do NOT call dvRouting.addDirectNeighbor() here.
              // A Liveness Record from the DHT is hearsay — we never
              // exchanged a direct packet with this device.  Only
              // _touchPeer() (called from _onPacketV3Received when
              // hopCount == 0) should promote a peer to DV direct
              // neighbor.  The routingTable.addPeer() above is correct:
              // it populates the address cache for future sendToDevice
              // lookups so a direct PING can be attempted.
            }
          }
        } catch (e) {
          _log.debug('LIVE_PUBLISH drop: parse error: $e');
        }
        return true;
      case proto.MessageTypeV3.MTV3_IDENTITY_KEM_PUBLISH:
        try {
          final p = proto.DeviceKemRecordV3.fromBuffer(frame.payload);
          final r = DeviceKemRecord.fromProto(p);
          if (!r.verify(r.userEd25519Pk)) {
            _log.debug('KEM_PUBLISH drop: in-place sig verify failed '
                '(user=${bytesToHex(r.userId).substring(0, 8)} '
                'device=${bytesToHex(r.deviceId).substring(0, 8)})');
            return true;
          }
          identityDhtHandler.handleKemPublish(r);
        } catch (e) {
          _log.debug('KEM_PUBLISH drop: parse/verify error: $e');
        }
        return true;

      // ── 2D-DHT RETRIEVE: lookup-and-respond ──────────────────────────
      case proto.MessageTypeV3.MTV3_IDENTITY_AUTH_RETRIEVE:
        try {
          final req = proto.IdentityAuthRetrieveRequest.fromBuffer(frame.payload);
          final m = identityDhtHandler.getAuthManifest(Uint8List.fromList(req.userId));
          if (m == null) return true; // silent — sender's RPC will time out
          _sendInfra(
            messageType: proto.MessageTypeV3.MTV3_IDENTITY_AUTH_RESPONSE,
            innerPayload: Uint8List.fromList(m.toProto().writeToBuffer()),
            recipientDeviceId: senderDeviceId,
          );
        } catch (e) {
          _log.debug('AUTH_RETRIEVE drop: parse/lookup error: $e');
        }
        return true;
      case proto.MessageTypeV3.MTV3_IDENTITY_LIVE_RETRIEVE:
        try {
          final req = proto.IdentityLiveRetrieveRequest.fromBuffer(frame.payload);
          final r = identityDhtHandler.getLiveness(
              Uint8List.fromList(req.userId),
              Uint8List.fromList(req.deviceNodeId));
          if (r == null) return true;
          _sendInfra(
            messageType: proto.MessageTypeV3.MTV3_IDENTITY_LIVE_RESPONSE,
            innerPayload: Uint8List.fromList(r.toProto().writeToBuffer()),
            recipientDeviceId: senderDeviceId,
          );
        } catch (e) {
          _log.debug('LIVE_RETRIEVE drop: parse/lookup error: $e');
        }
        return true;
      case proto.MessageTypeV3.MTV3_IDENTITY_KEM_RETRIEVE:
        try {
          final req = proto.IdentityKemRetrieveRequest.fromBuffer(frame.payload);
          final r = identityDhtHandler.getKemRecord(
              Uint8List.fromList(req.userId),
              Uint8List.fromList(req.deviceId));
          if (r == null) return true;
          _sendInfra(
            messageType: proto.MessageTypeV3.MTV3_IDENTITY_KEM_RESPONSE,
            innerPayload: Uint8List.fromList(r.toProto().writeToBuffer()),
            recipientDeviceId: senderDeviceId,
          );
        } catch (e) {
          _log.debug('KEM_RETRIEVE drop: parse/lookup error: $e');
        }
        return true;

      // ── 2D-DHT RESPONSE: forward to DhtRpc V3-direct matcher ─────────
      // DhtRpc.handleResponse takes the V3 type + payload + senderDeviceId
      // + remote (addr, port). The IdentityResolver-side awaiter receives a
      // `(type, payload)` tuple it decodes with the typed proto's
      // `fromBuffer`.
      case proto.MessageTypeV3.MTV3_IDENTITY_AUTH_RESPONSE:
      case proto.MessageTypeV3.MTV3_IDENTITY_LIVE_RESPONSE:
      case proto.MessageTypeV3.MTV3_IDENTITY_KEM_RESPONSE:
      case proto.MessageTypeV3.MTV3_DHT_PONG:
      case proto.MessageTypeV3.MTV3_DHT_FIND_NODE_RESPONSE:
      case proto.MessageTypeV3.MTV3_DHT_FIND_VALUE_RESPONSE:
      case proto.MessageTypeV3.MTV3_DHT_STORE_RESPONSE:
        _bridgeInfraResponseToDhtRpc(frame.messageType, frame, from, fromPort);
        return true;

      // S123 Erasure-F1: FRAGMENT_STORE_ACK must reach the service-layer
      // placement tracker (CleonaService.handleIncomingFragmentStoreAckInfra)
      // so it can resolve the per-fragment-index Completer that
      // `_distributeErasureFragments` is awaiting and drive
      // `onProactivePushAcked` (proactive-push retry cancellation). No
      // `DhtRpc.sendAndWait` ever registers a pending request for this
      // type, so the bridge call below is a defensive no-op kept for
      // symmetry with the other DHT-response types — the frame must NOT be
      // swallowed here, so this returns false to fall through to
      // `onInfrastructureFramePayload`, mirroring MTV3_PEER_STORE_ACK which
      // was never listed in this switch at all.
      case proto.MessageTypeV3.MTV3_FRAGMENT_STORE_ACK:
        _bridgeInfraResponseToDhtRpc(frame.messageType, frame, from, fromPort);
        return false;

      // ── DHT request side (DHT_PING / DHT_FIND_NODE) ──────────────────
      // Wave 2B.3: ported from the dead-code V2-bridge stubs in
      // cleona_service.dart (`_handleDhtPingV3`, `_handleDhtFindNodeV3`)
      // which were unreachable — these messageTypes route as
      // InfrastructureFrames per §2.3.5 selector. Reply via _sendInfra.
      case proto.MessageTypeV3.MTV3_DHT_PING:
        _handleDhtPingInfra(frame, senderDeviceId, from, fromPort);
        return true;
      case proto.MessageTypeV3.MTV3_DHT_FIND_NODE:
        _handleDhtFindNodeInfra(frame, senderDeviceId);
        return true;

      // ── Peer-list gossip (PEER_LIST_PUSH/SUMMARY/WANT) ───────────────
      // Wave 2B.3: ported from cleona_service.dart V2-bridge stubs.
      // PUSH = absorb the pushed PeerInfos into the routing table.
      // SUMMARY = gossip-anti-entropy: pull missing peers, push wanted ones.
      // WANT = answer with PEER_LIST_PUSH for each requested peer we know.
      case proto.MessageTypeV3.MTV3_PEER_LIST_PUSH:
        _handlePeerListPushInfra(frame, senderDeviceId, from);
        return true;
      case proto.MessageTypeV3.MTV3_PEER_LIST_SUMMARY:
        _handlePeerListSummaryInfra(frame, senderDeviceId);
        return true;
      case proto.MessageTypeV3.MTV3_PEER_LIST_WANT:
        _handlePeerListWantInfra(frame, senderDeviceId);
        return true;
      case proto.MessageTypeV3.MTV3_PEER_KEY_REQUEST:
        _handlePeerKeyRequestInfra(senderDeviceId);
        return true;
      case proto.MessageTypeV3.MTV3_PEER_KEY_RESPONSE:
        _handlePeerKeyResponseInfra(frame, senderDeviceId);
        return true;

      // ── Distance-Vector routing (ROUTE_UPDATE) ───────────────────────
      // Wave 2B.3: ported from cleona_service.dart V2-bridge stub.
      // V3 simplifies vs V2 — `senderDeviceId` is already the routing key,
      // no need for the V2 `_routingIdFromEnvelope` extraction.
      case proto.MessageTypeV3.MTV3_ROUTE_UPDATE:
        _handleRouteUpdateInfra(frame, senderDeviceId);
        return true;

      // ── Reachability probe (relay route discovery + port probe) ──────
      // Wave 2B.3: ported from cleona_service.dart V2-bridge stubs.
      // QUERY = answer whether we can reach `targetNodeId` (or send a
      // CPRB port probe if `probeIp/Port` is set, V3.1.33 path).
      // RESPONSE = forward to ReachabilityProbe matcher (not on dhtRpc —
      // ReachabilityProbe owns its own pending-query table).
      case proto.MessageTypeV3.MTV3_REACHABILITY_QUERY:
        _handleReachabilityQueryInfra(frame, senderDeviceId);
        return true;
      case proto.MessageTypeV3.MTV3_REACHABILITY_RESPONSE:
        reachabilityProbe.handleResponse(
            Uint8List.fromList(frame.payload), senderDeviceId);
        return true;

      // ── NAT hole-punch (REQUEST/NOTIFY/PING/PONG) ────────────────────
      // Wave 2B.3: NatTraversal already has clean V3 handler methods
      // taking parsed proto bodies. Parse here, then dispatch.
      case proto.MessageTypeV3.MTV3_HOLE_PUNCH_REQUEST:
        _handleHolePunchRequestInfra(frame, senderDeviceId);
        return true;
      case proto.MessageTypeV3.MTV3_HOLE_PUNCH_NOTIFY:
        _handleHolePunchNotifyInfra(frame, senderDeviceId);
        return true;
      case proto.MessageTypeV3.MTV3_HOLE_PUNCH_PING:
        _handleHolePunchPingInfra(frame, from, fromPort);
        return true;
      case proto.MessageTypeV3.MTV3_HOLE_PUNCH_PONG:
        _handleHolePunchPongInfra(frame, senderDeviceId, from, fromPort);
        return true;

      // ── First-CR-Mailbox (§5.5b) ─────────────────────────────────────
      case proto.MessageTypeV3.MTV3_FIRST_CR_STORE:
        _handleFirstCrStore(frame, senderDeviceId, from, fromPort);
        return true;
      case proto.MessageTypeV3.MTV3_FIRST_CR_STORE_ACK:
        _handleFirstCrStoreAck(frame, senderDeviceId);
        return true;
      case proto.MessageTypeV3.MTV3_FIRST_CR_DELIVER:
        _handleFirstCrDeliver(frame, senderDeviceId);
        return true;

      default:
        return false;
    }
  }

  // ── Wave 2B.3 receive-side handlers (Architecture v3.0 §2.3.5) ──────
  // Ported from dead V2-bridge stubs in cleona_service.dart. All operate
  // on node-local state only (routingTable, dvRouting, reachabilityProbe,
  // natTraversal, peerManager) — no service-state access.

  void _handleDhtPingInfra(
      proto.InfrastructureFrameV3 frame, Uint8List senderDeviceId,
      InternetAddress from, int fromPort) {
    try {
      final pongPayload = (proto.DhtPong()
        ..senderId = primaryIdentity.deviceNodeId
        ..timestamp = Int64(DateTime.now().millisecondsSinceEpoch))
          .writeToBuffer();
      // Send PONG directly back to the sender's source address. This
      // bypasses the routing-table lookup in sendToDevice — critical when
      // the sender is a DV neighbor but not in the routing table (k-bucket
      // full). Without this, the PONG is lost and the sender never learns
      // our addresses (including IPv6).
      sendInfraDirect(
        messageType: proto.MessageTypeV3.MTV3_DHT_PONG,
        innerPayload: pongPayload,
        recipientDeviceId: senderDeviceId,
        addr: from,
        port: fromPort,
      );
      // Also send via routing-table path (if available) — covers cases
      // where the source address is a relay hop, not the originator.
      _sendInfra(
        messageType: proto.MessageTypeV3.MTV3_DHT_PONG,
        innerPayload: pongPayload,
        recipientDeviceId: senderDeviceId,
      );

      // §5.12 hot-path — if the ping is a Stale-PK recovery probe (§5.10.2),
      // also send back an unsolicited firstParty PEER_LIST_PUSH with our
      // current PeerInfo. This heals the prober's stale-PK cache in 1 RTT
      // instead of waiting for the cold-path DV-safety-net.
      try {
        final ping = proto.DhtPing.fromBuffer(frame.payload);
        if (ping.pkRecoveryHint) {
          _log.info('§5.12 hot-path: pk_recovery_hint received → answering '
              'with self-broadcast PEER_LIST_PUSH');
          _pushSelfToPeer(senderDeviceId);
        }
      } catch (_) {
        // Unparseable ping body — ignore the hint (the PONG above is enough).
      }
    } catch (e) {
      _log.debug('DHT_PING handler error: $e');
    }
  }

  void _handleDhtFindNodeInfra(
      proto.InfrastructureFrameV3 frame, Uint8List senderDeviceId) {
    try {
      final find = proto.DhtFindNode.fromBuffer(frame.payload);
      final targetId = Uint8List.fromList(find.targetId);
      final closest = routingTable.findClosestPeers(targetId, count: 20);
      final response = proto.DhtFindNodeResponse();
      for (final peer in closest) {
        response.closestPeers.add(peer.toProto(gossipFilter: true));
      }
      _sendInfra(
        messageType: proto.MessageTypeV3.MTV3_DHT_FIND_NODE_RESPONSE,
        innerPayload: response.writeToBuffer(),
        recipientDeviceId: senderDeviceId,
      );
    } catch (e) {
      _log.debug('DHT_FIND_NODE handler error: $e');
    }
  }

  void _handlePeerListPushInfra(proto.InfrastructureFrameV3 frame,
      Uint8List senderDeviceId, InternetAddress from) {
    // §5.10.4 — Stage-4 success signal: only count if this PUSH actually
    // contains the failed peer we asked about. A bystander PUSH (from
    // unrelated gossip) was previously resetting the ghost peer's counter,
    // creating a re-arm loop: bystander PUSH → counter cleared → 6 more
    // sends → threshold → mesh refresh → bystander PUSH → repeat forever.
    // Deferred to after parse so we can inspect the PUSH contents.
    try {
      final push = proto.PeerListPush.fromBuffer(frame.payload);
      if (_lastStage4BurstAt != null && _stage4FailedHex != null) {
        final age = DateTime.now().difference(_lastStage4BurstAt!);
        if (age <= _lastStage4TailWindow) {
          final failedBytes = hexToBytes(_stage4FailedHex!);
          for (final peerProto in push.peers) {
            if (_bytesEqual(Uint8List.fromList(peerProto.nodeId), failedBytes)) {
              _stage4ReplySeen = true;
              break;
            }
          }
        }
      }

      // §5.10.4 Solicited-Reply-Adoption (Architektur §5.10.4):
      //
      // If this PUSH is a direct reply to a recent PEER_LIST_WANT we sent to
      // this very peer, adopt the sender as a direct neighbor before
      // `processRouteUpdate` runs. Without this, a freshly-restarted node (no
      // `dv_routing.json` yet) or a never-seen peer that we just queried
      // would have no `_neighbors` entry for the sender, and
      // `dvRouting.processRouteUpdate` (`dv_routing.dart:196-197`) would
      // silently discard the carried routes — exactly the "asks for All,
      // gets All back, doesn't write it down" symptom observed in §5.10.4
      // mesh-refresh logs.
      //
      // Trust argument: outer-sig verify + closed-network HMAC ran upstream
      // in `_onPacketV3Received` and would have rejected a forged reply long
      // before this handler. Receiving a PUSH within 30 s of our WANT to the
      // same deviceId is therefore proof of liveness *and* authenticity —
      // sufficient to flip `_neighbors[sender] = ct`. The existing
      // `addDirectNeighbor` is idempotent (always sets the map entry; only
      // returns true when a *better* direct route gets installed) so calling
      // it a second time after the V3-receive hook already did is cheap and
      // semantically safe.
      final senderHex = bytesToHex(senderDeviceId);
      final wantSentAt = _outstandingPeerListWants[senderHex];
      final isSolicitedReply = wantSentAt != null &&
          DateTime.now().difference(wantSentAt) <= _solicitedReplyWindow;
      if (isSolicitedReply) {
        _outstandingPeerListWants.remove(senderHex);
        final addr = PeerAddress(ip: from.address, port: 0);
        final ct = connectionTypeFromPriority(addr.priority);
        final adopted = dvRouting.addDirectNeighbor(senderDeviceId, ct);
        _log.info(
            '§5.10.4: Solicited PEER_LIST_PUSH from ${senderHex.substring(0, 8)} '
            '— adopted as direct neighbor (${ct.name}, '
            '${adopted ? "new direct route" : "already known"})');
      }

      // Bellman-Ford-Sicht des Senders ist genau dann verwertbar, wenn beide
      // parallelen Listen vorhanden UND gleich lang wie `peers` sind. Sonst
      // (alter Sender / Längen-Mismatch) fallen wir auf den Backwards-Compat
      // "nur-Cache"-Pfad zurück.
      final hasDvView = push.hopsFromSender.length == push.peers.length &&
          push.costFromSender.length == push.peers.length;
      if (!hasDvView &&
          (push.hopsFromSender.isNotEmpty || push.costFromSender.isNotEmpty)) {
        _log.warn('PeerListPush: parallel-list length mismatch '
            '(peers=${push.peers.length}, hops=${push.hopsFromSender.length}, '
            'cost=${push.costFromSender.length}) — DV update skipped');
      }

      // Architecture §17.3 PK provenance: a self-broadcast PEER_LIST_PUSH —
      // where the pushed peerProto.nodeId equals the sender's deviceId — is
      // authoritative for that peer's signing keys (firstParty). All other
      // entries are thirdParty hearsay; their PKs populate empty caches but
      // never overwrite firstParty entries.
      final dvUpdates = <RouteEntry>[];
      for (var i = 0; i < push.peers.length; i++) {
        final peerProto = push.peers[i];
        final peer = PeerInfo.fromProto(peerProto);
        if (peer.networkChannel.isNotEmpty &&
            peer.networkChannel != networkChannel) {
          continue;
        }
        final isSelfBroadcast = peer.nodeId.length == senderDeviceId.length &&
            bytesToHex(peer.nodeId) == bytesToHex(senderDeviceId);
        peer.pkSource =
            isSelfBroadcast ? PkSource.firstParty : PkSource.thirdParty;
        routingTable.addPeer(peer);
        _verifyAdmissionPow(peer.nodeId);

        // Slim-push key-fetch: if PQ keys are missing or fingerprint changed,
        // send PEER_KEY_REQUEST to the sender (with 60s cooldown per peer).
        if (isSelfBroadcast) {
          final existing = routingTable.getPeer(peer.nodeId);
          final needKeys = existing != null &&
              (existing.mlKemPublicKey == null ||
               existing.mlDsaPublicKey == null ||
               existing.deviceMlDsaPublicKey == null ||
               (peer.keyFingerprint != null &&
                existing.computedKeyFingerprint != null &&
                bytesToHex(peer.keyFingerprint!) !=
                    bytesToHex(existing.computedKeyFingerprint!)));
          if (needKeys) {
            _sendPeerKeyRequest(senderDeviceId);
          }
        }

        // §4.6 IPv6-First: on Desktop, skip IPv4 keepalive if the peer has
        // a global IPv6 (no NAT pinhole needed). On Mobile (Android/iOS),
        // ALWAYS register — the keepalive doubles as dead-network detector.
        // Without it, onAllPeersFailed never fires after WiFi->Mobile and
        // the phone stays at 0 peers for hours.
        final hasGlobalIpv6 = peer.allConnectionTargets().any((a) =>
            a.ip.contains(':') && !a.ip.toLowerCase().startsWith('fe80:') &&
            !a.ip.toLowerCase().startsWith('fd'));
        if (!hasGlobalIpv6 || Platform.isAndroid || Platform.isIOS) {
          for (final addr in peer.allConnectionTargets()) {
            if (addr.ip.isEmpty || addr.port <= 0) continue;
            if (!_needsKeepalive(addr.ip)) continue;
            udpKeepalive.register(peer.nodeIdHex, addr.ip, addr.port, peer.nodeId);
            break;
          }
        }

        // Bellman-Ford-Update: wir haben die DV-Sicht des Senders bekommen
        // → schreibe gelernte Route in dvRouting via processRouteUpdate.
        // Self-Broadcast übersprungen, weil der Sender bereits via
        // _touchPeer + dvRouting.addDirectNeighbor (Receive-Pipeline §4.4)
        // als Direct-Neighbor registriert wurde.
        if (hasDvView &&
            !isSelfBroadcast &&
            !routingTable.isLocalNode(peer.nodeId)) {
          final senderHops = push.hopsFromSender[i];
          final senderCost = push.costFromSender[i];
          // ConnectionType-Hint für die synthetische Entry: wir kennen den
          // Connection-Type des Sender→peer-Hops nicht (die Pusher-Route
          // wurde nicht serialisiert). Wir nehmen `publicUdp` als neutralen
          // Default — die effektive Kostenrechnung in processRouteUpdate
          // verwendet ohnehin senderCost direkt (entry.cost), nur die
          // gespeicherte Route trägt diesen connType-Hint mit.
          dvUpdates.add(RouteEntry(
            destinationHex: bytesToHex(peer.nodeId),
            hopCount: senderHops,
            cost: senderCost,
            connType: ConnectionType.publicUdp,
          ));
        }
      }

      // Single processRouteUpdate-Call mit allen entries: addiert linkCost
      // (= Sender-zu-uns) + senderCost und schreibt die Route via Sender als
      // nextHop. Verwirft silent, falls senderDeviceId nicht in _neighbors
      // ist — das ist ok (ohne registrierte Neighbor-Beziehung wäre die
      // gelernte Route ohnehin nicht trustworthy).
      if (dvUpdates.isNotEmpty) {
        dvRouting.processRouteUpdate(senderDeviceId, dvUpdates);
      }

      // §5.10.4 — wenn die Antwort auf einen Stage-4-Burst leer war,
      // verdient das einen WARN: dann hat der Pusher entweder nichts in
      // seinem Cache, oder unsere WANT-Liste hat ihn nicht erreicht.
      final stage4Tail = _lastStage4BurstAt != null &&
          DateTime.now().difference(_lastStage4BurstAt!) <=
              _lastStage4TailWindow;
      if (push.peers.isEmpty && stage4Tail) {
        _log.warn('PeerListPush: empty reply during Stage-4 tail window '
            'from ${from.address}');
      } else {
        _log.debug('PeerListPush: received ${push.peers.length} peers from '
            '${from.address}');
      }
      // §4.5 Discovery-complete gate: first PUSH with entries → transition
      // from discovery to normal operation.
      if (!_discoveryComplete && push.peers.isNotEmpty) {
        _onDiscoveryComplete();
      }
      onPeersChanged?.call();
    } catch (e) {
      _log.debug('PeerListPush parse error: $e');
    }
  }

  void _sendPeerKeyRequest(Uint8List recipientDeviceId) {
    final hex = bytesToHex(recipientDeviceId);
    final last = _peerKeyRequestCooldown[hex];
    if (last != null && DateTime.now().difference(last).inSeconds < 60) return;
    _peerKeyRequestCooldown[hex] = DateTime.now();
    _log.info('Sending PEER_KEY_REQUEST to ${hex.substring(0, 8)}');
    _sendInfra(
      messageType: proto.MessageTypeV3.MTV3_PEER_KEY_REQUEST,
      innerPayload: proto.PeerKeyRequest().writeToBuffer(),
      recipientDeviceId: recipientDeviceId,
    );
  }

  void _handlePeerKeyRequestInfra(Uint8List senderDeviceId) {
    _log.info('PEER_KEY_REQUEST from ${bytesToHex(senderDeviceId).substring(0, 8)} '
        '— responding with full PeerInfo for ${_identities.length} identities');
    final response = proto.PeerKeyResponse();
    for (final ctx in _identities.values) {
      response.peers.add(ctx.ownPeerInfo(
        localIp: _localIp,
        localPort: port,
        publicIp: _advertisedPublicIp,
        publicPort: _advertisedPublicPort,
        allLocalIps: _localIps,
        deviceEd25519PublicKey: _deviceKeys.sig.ed25519PublicKey,
        deviceMlDsaPublicKey: _deviceKeys.sig.mlDsaPublicKey,
        deviceIdPowNonce: _deviceKeys.admissionNonce,
      ).toProto());
    }
    _sendInfra(
      messageType: proto.MessageTypeV3.MTV3_PEER_KEY_RESPONSE,
      innerPayload: response.writeToBuffer(),
      recipientDeviceId: senderDeviceId,
    );
  }

  void _handlePeerKeyResponseInfra(
      proto.InfrastructureFrameV3 frame, Uint8List senderDeviceId) {
    try {
      final response = proto.PeerKeyResponse.fromBuffer(frame.payload);
      _log.info('PEER_KEY_RESPONSE from ${bytesToHex(senderDeviceId).substring(0, 8)} '
          '— ${response.peers.length} full PeerInfos');
      for (final peerProto in response.peers) {
        final peer = PeerInfo.fromProto(peerProto);
        if (peer.networkChannel.isNotEmpty &&
            peer.networkChannel != networkChannel) {
          continue;
        }
        peer.pkSource = PkSource.firstParty;
        routingTable.addPeer(peer);
        _verifyAdmissionPow(peer.nodeId);
      }
    } catch (e) {
      _log.debug('PeerKeyResponse parse error: $e');
    }
  }

  /// D3 (§13.1.2, Phase 1 observe-only): verifiziere die Admission-PoW-Nonce
  /// eines Peers, sobald Device-PK + Nonce vorliegen. Zwei Checks: (1) der
  /// PK gehoert zur Wire-Identitaet (`SHA-256(secret || pk) == nodeId`),
  /// (2) der PoW-Hash erreicht die Schwierigkeit. Ergebnis wird im PeerInfo
  /// persistiert; nichts wird gegated.
  void _verifyAdmissionPow(Uint8List nodeId) {
    final peer = routingTable.getPeer(nodeId);
    if (peer == null || peer.idPowVerified) return;
    final pk = peer.deviceEd25519PublicKey;
    final nonce = peer.deviceIdPowNonce;
    if (pk == null || pk.isEmpty || nonce == null || nonce.isEmpty) return;
    final boundId = HdWallet.computeDeviceNodeId(pk, NetworkSecret.secret);
    if (bytesToHex(boundId) != bytesToHex(peer.nodeId)) {
      _log.warn('D3: Admission-Nonce fuer ${peer.nodeIdHex.substring(0, 8)} '
          'verworfen — Device-PK gehoert nicht zur Wire-Identitaet');
      return;
    }
    if (AdmissionPow.verify(pk, nonce)) {
      peer.idPowVerified = true;
      _log.info('D3: Peer ${peer.nodeIdHex.substring(0, 8)} admission-PoW '
          'verifiziert');
    } else {
      _log.warn('D3: Admission-Nonce fuer ${peer.nodeIdHex.substring(0, 8)} '
          'ungueltig (PoW-Schwierigkeit verfehlt)');
    }
  }

  void _handlePeerListSummaryInfra(
      proto.InfrastructureFrameV3 frame, Uint8List senderDeviceId) {
    try {
      final summary = proto.PeerListSummary.fromBuffer(frame.payload);
      final theirEntries = <String, int>{};
      for (final entry in summary.entries) {
        theirEntries[bytesToHex(Uint8List.fromList(entry.nodeId))] =
            entry.lastSeen.toInt();
      }

      // Find peers we have that they need (newer or missing).
      // §4.4 gossip gate: only include peers that are confirmed + alive +
      // not in cascade-exhaustion. Dead peers are not gossipped — they pull
      // updates themselves via Mesh-Refresh when they come back online.
      final wantedByThem = <Uint8List>[];
      for (final peer in routingTable.allPeers) {
        final hex = peer.nodeIdHex;
        if (!routingTable.isLocalNode(peer.nodeId) &&
            !_isPeerAliveForGossip(hex)) {
          continue;
        }
        final theirTs = theirEntries[hex];
        if (theirTs == null ||
            peer.lastSeen.millisecondsSinceEpoch > theirTs) {
          wantedByThem.add(peer.nodeId);
        }
      }

      // Find peers they have that we want.
      final wanted = <Uint8List>[];
      final ourPeerIds =
          routingTable.allPeers.map((p) => p.nodeIdHex).toSet();
      for (final entry in summary.entries) {
        final hex = bytesToHex(Uint8List.fromList(entry.nodeId));
        if (!ourPeerIds.contains(hex)) {
          wanted.add(Uint8List.fromList(entry.nodeId));
        }
      }

      // Send WANT for peers we need.
      if (wanted.isNotEmpty) {
        final wantData = proto.PeerListWant();
        for (final id in wanted) {
          wantData.wantedNodeIds.add(id);
        }
        _sendInfra(
          messageType: proto.MessageTypeV3.MTV3_PEER_LIST_WANT,
          innerPayload: wantData.writeToBuffer(),
          recipientDeviceId: senderDeviceId,
        );
        // §5.10.4 Solicited-Reply-Adoption: record the WANT so an incoming
        // PUSH from this peer within the window adopts it as a neighbor
        // even if `_neighbors` is currently empty for it (cold-start case).
        _outstandingPeerListWants[bytesToHex(senderDeviceId)] = DateTime.now();
      }

      // Push peers they need (cap at 50 to avoid fragmentation storm).
      if (wantedByThem.isNotEmpty) {
        final pushData = proto.PeerListPush();
        for (final id in wantedByThem.take(50)) {
          final peer = routingTable.getPeer(id);
          if (peer != null) {
            pushData.peers.add(peer.toProto(gossipFilter: true));
          }
        }
        _sendInfra(
          messageType: proto.MessageTypeV3.MTV3_PEER_LIST_PUSH,
          innerPayload: pushData.writeToBuffer(),
          recipientDeviceId: senderDeviceId,
        );
      }
    } catch (e) {
      _log.debug('PeerListSummary handler error: $e');
    }
  }

  void _handlePeerListWantInfra(
      proto.InfrastructureFrameV3 frame, Uint8List senderDeviceId) {
    try {
      final want = proto.PeerListWant.fromBuffer(frame.payload);
      final pushData = proto.PeerListPush();
      // Cap at 50 entries to avoid giant PUSH responses (defense-in-depth
      // against old nodes or malicious WANTs with 100+ entries).
      final wantedIds = want.wantedNodeIds.take(50);
      for (final wantedId in wantedIds) {
        final id = Uint8List.fromList(wantedId);
        final peer = routingTable.getPeer(id);
        if (peer == null) continue;

        // Eigene DV-Sicht zu diesem Peer beilegen, damit der Empfänger
        // Bellman-Ford-Update fahren kann statt nur den PeerInfo-Cache zu
        // füllen. Self-Broadcast: hops=0, cost=0. Sonst: cheapest alive
        // route aus dvRouting. Wenn keine alive route existiert, skip — wir
        // hätten einen logischen Bruch (Cache-Eintrag ohne Route), den der
        // Empfänger nicht sinnvoll als DV-Update verarbeiten kann.
        final isSelf = routingTable.isLocalNode(id);
        final peerHex = bytesToHex(id);
        Route? route;
        if (!isSelf) {
          // WANT is an explicit request — the requester already knows the
          // peer exists (from a DV ROUTE_UPDATE). Respond with whatever
          // PeerInfo we have. The gossip gate (isPeerConfirmed) is NOT
          // applied here — it belongs on proactive gossip (Summary handler)
          // only. Requiring confirmed would break DV→K-bucket seeding for
          // peers behind NAT whose mapping expired.
          route = dvRouting
              .routesTo(peerHex)
              .where((r) => r.isAlive)
              .firstOrNull;
          if (route == null) {
            _log.debug('PeerListWant: skip ${peerHex.substring(0, 8)} '
                '— have PeerInfo but no alive DV route');
            continue;
          }
        }

        pushData.peers.add(isSelf ? peer.toProto() : peer.toProto(gossipFilter: true));
        pushData.hopsFromSender.add(isSelf ? 0 : route!.hopCount);
        pushData.costFromSender.add(isSelf ? 0 : route!.cost);
      }
      _sendInfra(
        messageType: proto.MessageTypeV3.MTV3_PEER_LIST_PUSH,
        innerPayload: pushData.writeToBuffer(),
        recipientDeviceId: senderDeviceId,
      );
    } catch (e) {
      _log.debug('PeerListWant handler error: $e');
    }
  }

  // ── §5.10 Send-Cascade Recovery & Self-Healing helpers ──────────────

  /// §5.10.4 — Decrement the per-peer unACK'd-packets counter. Floors at 0
  /// and removes the entry when it reaches 0 to keep the map bounded.
  /// Idempotent: a no-op if the peer is not currently tracked.
  void _decrementUnackedPacketsToPeer(String peerHex) {
    final n = _unackedPacketsToPeer[peerHex];
    if (n == null) return;
    if (n <= 1) {
      _unackedPacketsToPeer.remove(peerHex);
    } else {
      _unackedPacketsToPeer[peerHex] = n - 1;
    }
  }

  /// §5.10.2 Stale-PK Recovery — Stage 2 of the send cascade.
  ///
  /// Triggered exclusively from [_onPacketV3Received] when an incoming
  /// `device_sig_invalid` arrives from a peer for whom we have a firstParty
  /// PK on file. We mark that PK stale (so the next firstParty Self-Broadcast
  /// can overwrite it via the §5.10.5 carve-out in `setSigningKeys`) and send
  /// ONE BOOT-path `MTV3_DHT_PING`. The reply path:
  ///
  ///   1. Peer replies with `MTV3_DHT_PONG` (BOOT, HMAC-only) — the response
  ///      arrives via UDP, gets HMAC-verified at the transport edge, and
  ///      bypasses Outer-Sig-Verify because the peer's NEW PK is not yet
  ///      cached. This re-touches the routing table.
  ///   2. The peer follows up with a self-broadcast `PEER_LIST_PUSH` carrying
  ///      its current PK pair — `_handlePeerListPushInfra` overwrites the
  ///      cached PK because `pkStale == true`, and `setSigningKeys` clears
  ///      the flag.
  ///   3. The next packet from this peer Outer-Sig-Verifies normally; the
  ///      cascade is healed.
  ///
  /// 30 s throttle per peer guards against `device_sig_invalid` floods (e.g.
  /// a burst of buffered packets queued before the rotation). Fire-and-forget
  /// — the caller is the receive pipeline and does NOT await this.
  void _triggerStalePkRecovery(PeerInfo peer) {
    final hex = peer.nodeIdHex;
    final last = _lastStalePkProbe[hex];
    if (last != null &&
        DateTime.now().difference(last) < _stalePkProbeThrottle) {
      return; // throttle — already probed recently
    }
    _lastStalePkProbe[hex] = DateTime.now();

    peer.pkStale = true;

    // Pick a usable address — `allConnectionTargets` is sorted priority-asc
    // / score-desc, so the first reachable entry is the best shot.
    PeerAddress? probe;
    for (final addr in peer.allConnectionTargets()) {
      if (addr.ip.isEmpty || addr.port <= 0) continue;
      if (!addr.isReachableFromCurrentNetwork) continue;
      if (addr.isInBackoff) continue;
      probe = addr;
      break;
    }

    final shortHex =
        hex.length >= 8 ? hex.substring(0, 8) : hex;
    if (probe == null) {
      _log.info('§5.10.2: Stale-PK recovery for $shortHex — '
          'no usable address (will rely on incoming traffic + Stage 4)');
      return;
    }

    _log.info('§5.10.2: Stale-PK recovery probe → $shortHex at '
        '${probe.ip}:${probe.port} (BOOT DHT_PING)');

    // BOOT-path DHT_PING — body needn't carry routing info; it just needs to
    // elicit a PONG. `_sendInfra` routes via DV cascade, which for a peer in
    // routingTable hits the same direct/relay path the cascade is rebuilding.
    // §5.12 hot-path — set pkRecoveryHint=true so the responder also sends
    // back an unsolicited firstParty PEER_LIST_PUSH; that heals our cached
    // stale signing PK in 1 RTT instead of waiting for the cold-path safety
    // net (1 h) or never (the periodic 120 s peer-exchange is gone).
    final ping = proto.DhtPing()
      ..senderId = primaryIdentity.deviceNodeId
      ..timestamp = Int64(DateTime.now().millisecondsSinceEpoch)
      ..pkRecoveryHint = true;
    _sendInfra(
      messageType: proto.MessageTypeV3.MTV3_DHT_PING,
      innerPayload: ping.writeToBuffer(),
      recipientDeviceId: peer.nodeId,
    );

    // Notify any UI watchers that peer state changed (pkStale flag).
    onPeersChanged?.call();
  }

  /// §5.10.4 Mesh-State Refresh — Stage 4 of the send cascade.
  ///
  /// Triggered when `_unackedPacketsToPeer[deviceHex] >= _stage4Threshold`
  /// (=6 packets sent without a reply). Iterates other peers in the routing
  /// table (excluding the failed peer) in cost order and sends one BOOT-path
  /// `MTV3_PEER_LIST_WANT` to each, spaced 50 ms apart. After the last WANT
  /// is dispatched we wait an additional 150 ms tail; if any peer responded
  /// with `MTV3_PEER_LIST_PUSH` inside that window (`_stage4ReplySeen` set
  /// by `_handlePeerListPushInfra`), we reset the unACK counter for the
  /// failed peer and let the next send-attempt naturally retry Stage 1 with
  /// potentially refreshed cache. If the tail elapses without any reply, we
  /// escalate to Stage 5 Re-Discovery.
  ///
  /// 60 s throttle per failed-peer key prevents a stuck cascade from firing
  /// WANTs every retry tick. Fire-and-forget — caller is `sendToDevice` and
  /// does NOT await this.
  void _triggerMeshRefresh(Uint8List failedDeviceId) {
    final failedHex = bytesToHex(failedDeviceId);
    final now = DateTime.now();
    final last = _lastMeshRefresh[failedHex];
    if (last != null && now.difference(last) < _meshRefreshThrottle) {
      return; // throttle — already refreshed recently for this peer
    }
    // Global token bucket: prune expired entries, then check capacity.
    // Checked BEFORE stamping per-peer cooldown so a peer that loses the
    // global race isn't penalized with a 60s per-peer wait for a refresh
    // that never fired.
    _meshRefreshGlobalBucket.removeWhere(
        (t) => now.difference(t) >= _meshRefreshGlobalWindow);
    if (_meshRefreshGlobalBucket.length >= _meshRefreshGlobalMax) {
      return; // global rate limit — too many refreshes across all peers
    }
    _meshRefreshGlobalBucket.add(now);
    _lastMeshRefresh[failedHex] = now;

    // Build the candidate list: every peer in the routing table EXCEPT the
    // failed one and our own identities. Cost-order via DV `bestRouteTo`
    // (lower cost = better — preferred for the WANT burst since they're
    // most likely to actually reach + reply quickly).
    final candidates = <_MeshRefreshCandidate>[];
    for (final peer in routingTable.allPeers) {
      final hex = peer.nodeIdHex;
      if (hex == failedHex) continue;
      if (_isLocalIdentity(hex)) continue;
      if (!isPeerConfirmed(hex)) continue;
      final route = dvRouting.bestRouteTo(hex);
      if (route == null || !route.isAlive) continue;
      candidates.add(_MeshRefreshCandidate(peer.nodeId, route.cost));
    }
    candidates.sort((a, b) => a.cost.compareTo(b.cost));

    final shortFailed =
        failedHex.length >= 8 ? failedHex.substring(0, 8) : failedHex;
    if (candidates.isEmpty) {
      // No other peers → cascade has fully collapsed; jump straight to
      // Stage 5 Re-Discovery.
      _log.info('§5.10.4: Mesh refresh for $shortFailed — '
          'zero candidate peers, escalating directly to Re-Discovery');
      _triggerReDiscovery();
      return;
    }

    _log.info('§5.10.4: Mesh refresh — failed=$shortFailed, '
        'sending PEER_LIST_WANT to ${candidates.length} peers (50 ms spacing)');

    // Inner WANT payload: empty `wantedNodeIds` = "send me your full peer
    // list". Receivers iterate `wantedNodeIds`; an empty list naturally
    // produces an empty `PeerListPush` — but receivers also gossip back
    // freshly-known peers via the SUMMARY/PUSH path on the next anti-entropy
    // tick. To force an immediate reply, we ask specifically for the failed
    // peer's nodeId. If anyone in the mesh has it, they push it back.
    final wantData = proto.PeerListWant();
    wantData.wantedNodeIds.add(failedDeviceId);
    final wantBytes = wantData.writeToBuffer();

    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      Future.delayed(Duration(milliseconds: 50 * i), () {
        if (!_running) return;
        _sendInfra(
          messageType: proto.MessageTypeV3.MTV3_PEER_LIST_WANT,
          innerPayload: wantBytes,
          recipientDeviceId: candidate.deviceId,
        );
        // §5.10.4 Solicited-Reply-Adoption: arm each candidate so a PUSH
        // back within the window adopts it as a neighbor. Stamping inside
        // the delayed callback (vs. up-front in the loop) means the window
        // starts when the WANT actually leaves, not 50ms × i earlier.
        _outstandingPeerListWants[bytesToHex(candidate.deviceId)] =
            DateTime.now();
      });
    }

    // Tail-window: total burst duration plus a 150 ms grace for replies to
    // arrive. The PEER_LIST_PUSH receive path flips `_stage4ReplySeen`.
    final tailTotal = Duration(
        milliseconds: 50 * (candidates.length - 1) + 150);
    _lastStage4BurstAt = DateTime.now();
    _lastStage4TailWindow = tailTotal;
    _stage4ReplySeen = false;
    _stage4FailedHex = failedHex;
    Future.delayed(tailTotal, () {
      if (!_running) return;
      if (_stage4ReplySeen) {
        _log.info('§5.10.4: Mesh refresh — at least one reply for '
            '$shortFailed, refreshing cache (counter reset)');
        _unackedPacketsToPeer.remove(failedHex);
      } else {
        _log.info('§5.10.5: Mesh refresh yielded zero replies for '
            '$shortFailed → Re-Discovery');
        _triggerReDiscovery();
      }
    });
  }

  /// §5.10.5 Re-Discovery — Stage 5 of the send cascade.
  ///
  /// Last-resort: re-execute the §2.7.1 startup discovery routine
  /// (multicast/broadcast 3-burst on both LAN channels, plus subnet-scan
  /// fallback). Single-shot per cascade-fail — if Stage 5 yields nothing,
  /// the message proceeds to §5.4 Erasure / §5.6 Mailbox layers via the
  /// existing fall-through. We also blanket-mark every peer's firstParty PK
  /// as stale so the next Self-Broadcast can overwrite it (covers the case
  /// where multiple peers rotated keys while we were partitioned).
  void _triggerReDiscovery() {
    if (!_running) return;

    // §5.10.5 cooldown: suppress repeated Re-Discovery triggers within 60 s.
    // Empirically (2026-05-09 bonding-loop investigation) the cascade
    // could fire 4 Re-Discoveries in 4 minutes when no peer was reachable —
    // each one re-emits multicast + broadcast 3-bursts on top of the
    // already-running subnet scan, flooding the LAN and never letting the
    // subnet scan complete. The cooldown lets the in-flight scan make
    // meaningful fill-phase progress (130-200 s typical) before the next
    // burst tries again.
    final now = DateTime.now();
    if (_lastReDiscoveryTrigger != null &&
        now.difference(_lastReDiscoveryTrigger!) < _reDiscoveryCooldown) {
      final ago = now.difference(_lastReDiscoveryTrigger!).inSeconds;
      _log.debug('§5.10.5: Re-Discovery suppressed (last trigger ${ago}s ago, '
          'cooldown ${_reDiscoveryCooldown.inSeconds}s)');
      return;
    }
    _lastReDiscoveryTrigger = now;

    // Mark every firstParty peer's PK as stale so a fresh Self-Broadcast
    // can overwrite via the §5.10.5 carve-out. Cheap O(N) walk over the
    // routing table; the flag does no harm if no rotation actually happened
    // (next packet still verifies cleanly under the cached PK if it's still
    // valid, and `setSigningKeys` only clears the flag on a firstParty
    // overwrite — but a passing verify is fine, the peer is alive).
    var marked = 0;
    for (final peer in routingTable.allPeers) {
      if (peer.pkSource == PkSource.firstParty && !peer.pkStale) {
        peer.pkStale = true;
        marked++;
      }
    }

    _log.info('§5.10.5: Re-Discovery triggered — '
        'multicast + LAN-broadcast 3-burst + subnet scan; '
        'marked $marked firstParty PKs stale for refresh');

    // Re-execute discovery — the existing fast-discovery + subnet-scan
    // primitives that `_finishStart` uses on cold-start. No new mechanism.
    try {
      localDiscovery.triggerFastDiscovery();
    } catch (e) {
      _log.debug('§5.10.5: localDiscovery.triggerFastDiscovery error: $e');
    }
    try {
      multicastDiscovery.triggerFastDiscovery();
    } catch (e) {
      _log.debug('§5.10.5: multicastDiscovery.triggerFastDiscovery error: $e');
    }
    try {
      localDiscovery.startSubnetScan(
          _localIps, () => _hasCrossSubnetPeer());
    } catch (e) {
      _log.debug('§5.10.5: subnet-scan error: $e');
    }

    onPeersChanged?.call();
  }

  void _handleRouteUpdateInfra(
      proto.InfrastructureFrameV3 frame, Uint8List senderDeviceId) {
    try {
      final msg = proto.RouteUpdateMsg.fromBuffer(frame.payload);
      final fromHex = bytesToHex(senderDeviceId);

      // D3 Phase 2 (§13.1.2): DV route acceptance requires admission PoW.
      // §13.1.2 exception: isProtectedSeed peers (ContactSeed §8.1.1)
      // are exempt — scanner needs routes from seed peers for First-CR.
      final senderPeer = routingTable.getPeer(senderDeviceId);
      if (senderPeer != null && !senderPeer.idPowVerified &&
          !senderPeer.isProtectedSeed) {
        _log.debug('D3: ROUTE_UPDATE from non-admitted '
            '${fromHex.substring(0, 8)} — dropped');
        return;
      }

      final entries = msg.routes
          .map((r) => RouteEntry(
                destinationHex:
                    bytesToHex(Uint8List.fromList(r.destination)),
                hopCount: r.hopCount,
                cost: r.cost,
                connType: _connTypeFromProto(r.connType),
              ))
          .toList();

      // Change-gated propagation: suppress the per-entry onRouteChanged
      // callback during batch processing — we populate _dvPendingChanges
      // manually from the result's updatedDestinations list, which only
      // includes destinations whose BEST route actually changed.
      final savedCallback = dvRouting.onRouteChanged;
      dvRouting.onRouteChanged = null;
      final result = dvRouting.processRouteUpdateDetailed(
          senderDeviceId, entries);
      dvRouting.onRouteChanged = savedCallback;
      if (result.changed) {
        for (final dest in result.updatedDestinations) {
          _dvPendingChanges.add(dest);
        }
        _dvPropagationDebounce?.cancel();
        _dvPropagationDebounce =
            Timer(const Duration(seconds: 2), _flushDvUpdates);
        dvRouting.updateDefaultGateway();
      }
      _log.info('DV: Route update from ${fromHex.substring(0, 8)}: '
          '${entries.length} entries, changed=${result.changed} '
          '(${result.updatedDestinations.length} dests), '
          'gwHex=${dvRouting.defaultGatewayHex?.substring(0, 8)}, '
          'routes=${dvRouting.routeCount}, '
          'neighbors=${dvRouting.neighbors.length}');

      // DV→K-bucket seeding: if the ROUTE_UPDATE advertises destinations
      // that we don't have in our K-bucket routing table, send a targeted
      // PEER_LIST_WANT to the neighbor so it pushes the peer metadata
      // (addresses, keys). Without this, DV-only destinations (e.g.
      // bootstrap on another subnet) never appear in peerSummaries and
      // cannot be included as seed peers in ContactSeed URIs.
      if (result.changed) {
        final candidates = <({Uint8List id, String hex, int cost})>[];
        final now = DateTime.now();
        for (final entry in entries) {
          if (entry.cost >= Route.infinity) continue;
          final destBytes = hexToBytes(entry.destinationHex);
          if (routingTable.getPeer(destBytes) != null) continue;
          final lastWant = _dvSeedWantCooldown[entry.destinationHex];
          if (lastWant != null && now.difference(lastWant).inSeconds < 120) continue;
          candidates.add((id: destBytes, hex: entry.destinationHex, cost: entry.cost));
        }
        // Cap at 10 per batch (cheapest first) to avoid giant PUSH
        // responses (109 entries → 107KB / 90 fragments). Remaining
        // destinations are eligible on the next ROUTE_UPDATE cycle.
        candidates.sort((a, b) => a.cost.compareTo(b.cost));
        final batch = candidates.take(10).toList();
        // Only stamp cooldown for destinations actually requested.
        for (final c in batch) {
          _dvSeedWantCooldown[c.hex] = now;
        }
        if (batch.isNotEmpty) {
          final wantData = proto.PeerListWant();
          for (final c in batch) {
            wantData.wantedNodeIds.add(c.id);
          }
          _sendInfra(
            messageType: proto.MessageTypeV3.MTV3_PEER_LIST_WANT,
            innerPayload: wantData.writeToBuffer(),
            recipientDeviceId: senderDeviceId,
          );
          _outstandingPeerListWants[fromHex] = now;
          _log.info('DV: Requested peer metadata for ${batch.length} '
              'DV-only destinations from ${fromHex.substring(0, 8)}'
              '${candidates.length > 10 ? " (${candidates.length - 10} deferred)" : ""}');
        }
      }

      // Reciprocal welcome: empty/minimal update from a known neighbor
      // signals a peer restart — respond with our full table.
      if (entries.isEmpty && dvRouting.neighbors.containsKey(fromHex)) {
        final ourRoutes = dvRouting.buildFullUpdate();
        if (ourRoutes.isNotEmpty) {
          final peer = routingTable.getPeer(senderDeviceId);
          if (peer != null) {
            _sendRouteUpdate(peer, ourRoutes);
            _lastRouteUpdateSentTo[fromHex] = DateTime.now();
            _lastRouteEpochSentTo[fromHex] = dvRouting.routeEpoch;
            _log.info('DV: Reciprocal welcome sent ${ourRoutes.length} '
                'routes to ${fromHex.substring(0, 8)} (peer restart)');
          }
        }
      }
    } catch (e) {
      _log.debug('DV: Failed to parse ROUTE_UPDATE: $e');
    }
  }

  void _handleReachabilityQueryInfra(
      proto.InfrastructureFrameV3 frame, Uint8List senderDeviceId) {
    try {
      final query = proto.PeerReachabilityQuery.fromBuffer(frame.payload);

      // V3.1.33 port probe: send CPRB packet to sender's claimed public address.
      if (query.probeIp.isNotEmpty && query.probePort > 0) {
        final senderHex = bytesToHex(senderDeviceId);
        // Security: only probe for confirmed peers.
        if (!isPeerConfirmed(senderHex)) {
          _log.debug('Port probe rejected: ${senderHex.substring(0, 8)} '
              'not confirmed');
          return;
        }
        if (_isPrivateIp(query.probeIp)) {
          _log.debug('Port probe rejected: ${query.probeIp} is private');
          return;
        }
        _log.info('Port probe: sending CPRB to ${query.probeIp}:'
            '${query.probePort} for ${senderHex.substring(0, 8)}');
        transport.sendPortProbe(
          Uint8List.fromList(query.queryId),
          InternetAddress(query.probeIp),
          query.probePort,
        );
        return;
      }

      // Normal reachability query: do we know a route to targetNodeId?
      final targetId = Uint8List.fromList(query.targetNodeId);
      final targetHex = bytesToHex(targetId);
      final peer = routingTable.getPeer(targetId);
      final confirmed = isPeerConfirmed(targetHex);

      final response = proto.PeerReachabilityResponse()
        ..targetNodeId = query.targetNodeId
        ..queryId = query.queryId
        ..canReach = (peer != null && confirmed)
        ..lastSeenMs = Int64(peer?.lastSeen.millisecondsSinceEpoch ?? 0);

      _sendInfra(
        messageType: proto.MessageTypeV3.MTV3_REACHABILITY_RESPONSE,
        innerPayload: response.writeToBuffer(),
        recipientDeviceId: senderDeviceId,
      );
      _log.debug('Reachability query for ${targetHex.substring(0, 8)}: '
          'canReach=${peer != null && confirmed}');
    } catch (e) {
      _log.debug('REACHABILITY_QUERY parse error: $e');
    }
  }

  void _handleHolePunchRequestInfra(
      proto.InfrastructureFrameV3 frame, Uint8List senderDeviceId) {
    try {
      final req = proto.HolePunchRequest.fromBuffer(frame.payload);
      natTraversal.handleHolePunchRequest(req, senderDeviceId);
    } catch (e) {
      _log.debug('HOLE_PUNCH_REQUEST parse error: $e');
    }
  }

  void _handleHolePunchNotifyInfra(
      proto.InfrastructureFrameV3 frame, Uint8List senderDeviceId) {
    try {
      final notify = proto.HolePunchNotify.fromBuffer(frame.payload);
      natTraversal.handleHolePunchNotify(notify, senderDeviceId);
    } catch (e) {
      _log.debug('HOLE_PUNCH_NOTIFY parse error: $e');
    }
  }

  void _handleHolePunchPingInfra(
      proto.InfrastructureFrameV3 frame, InternetAddress from, int fromPort) {
    try {
      final ping = proto.HolePunchPing.fromBuffer(frame.payload);
      natTraversal.handleHolePunchPing(ping, from, fromPort);
    } catch (e) {
      _log.debug('HOLE_PUNCH_PING parse error: $e');
    }
  }

  void _handleHolePunchPongInfra(proto.InfrastructureFrameV3 frame,
      Uint8List senderDeviceId, InternetAddress from, int fromPort) {
    try {
      final pong = proto.HolePunchPong.fromBuffer(frame.payload);
      natTraversal.handleHolePunchPong(pong, from, fromPort);
      // V2 parity: a HOLE_PUNCH_PONG also proves the peer's pinhole is
      // alive — reset UdpKeepalive's all-failure counter for this peer.
      udpKeepalive.onPongReceived(bytesToHex(senderDeviceId));
    } catch (e) {
      _log.debug('HOLE_PUNCH_PONG parse error: $e');
    }
  }

  // ── §5.5b First-CR-Mailbox receive handlers ─────────────────────────

  void _handleFirstCrStore(proto.InfrastructureFrameV3 frame,
      Uint8List senderDeviceId, InternetAddress from, int fromPort) {
    try {
      final store = proto.FirstCrStoreV3.fromBuffer(frame.payload);
      final recipHex = bytesToHex(Uint8List.fromList(store.recipientDeviceId));
      final senderHex = bytesToHex(Uint8List.fromList(store.senderDeviceId));
      final ttlMs = store.ttlMs.toInt();
      final ttl = ttlMs > 0 && ttlMs <= 604800000
          ? Duration(milliseconds: ttlMs)
          : _firstCrMailboxTtl;

      // Quota check — total across all recipients.
      var totalEntries = 0;
      for (final list in _firstCrMailbox.values) {
        totalEntries += list.length;
      }
      if (totalEntries >= _firstCrMailboxMaxEntries) {
        _log.info('FIRST_CR_STORE reject: quota ($totalEntries >= '
            '$_firstCrMailboxMaxEntries) from ${senderHex.substring(0, 8)}');
        _sendFirstCrStoreAck(senderDeviceId, from, fromPort, false,
            reason: 'quota_exceeded');
        return;
      }

      // Dedup — same sender→recipient pair replaces the old entry.
      final dedupKey = '$senderHex:$recipHex';
      final bucket = _firstCrMailbox.putIfAbsent(recipHex, () => []);
      bucket.removeWhere((e) => e.dedupKey == dedupKey);

      bucket.add(_FirstCrMailboxEntry(
        recipientDeviceId: Uint8List.fromList(store.recipientDeviceId),
        senderDeviceId: Uint8List.fromList(store.senderDeviceId),
        encryptedCrBlob: Uint8List.fromList(store.encryptedCrBlob),
        storedAt: DateTime.now(),
        ttl: ttl,
      ));

      _log.info('§5.5b FIRST_CR_STORE: stored CR from ${senderHex.substring(0, 8)} '
          'for ${recipHex.substring(0, 8)} (ttl=${ttl.inHours}h, total=$totalEntries)');
      _saveFirstCrMailbox();
      _sendFirstCrStoreAck(senderDeviceId, from, fromPort, true);
    } catch (e) {
      _log.debug('FIRST_CR_STORE parse error: $e');
    }
  }

  void _sendFirstCrStoreAck(Uint8List recipientDeviceId,
      InternetAddress addr, int port, bool accepted, {String reason = ''}) {
    final ack = proto.FirstCrStoreAckV3()
      ..accepted = accepted
      ..rejectReason = reason;
    sendInfraDirect(
      messageType: proto.MessageTypeV3.MTV3_FIRST_CR_STORE_ACK,
      innerPayload: Uint8List.fromList(ack.writeToBuffer()),
      recipientDeviceId: recipientDeviceId,
      addr: addr,
      port: port,
    );
  }

  void _handleFirstCrStoreAck(proto.InfrastructureFrameV3 frame,
      Uint8List senderDeviceId) {
    try {
      final ack = proto.FirstCrStoreAckV3.fromBuffer(frame.payload);
      _log.info('§5.5b FIRST_CR_STORE_ACK from '
          '${bytesToHex(senderDeviceId).substring(0, 8)}: '
          'accepted=${ack.accepted}'
          '${ack.rejectReason.isNotEmpty ? " reason=${ack.rejectReason}" : ""}');
      onFirstCrStoreAck?.call(senderDeviceId, ack.accepted);
    } catch (e) {
      _log.debug('FIRST_CR_STORE_ACK parse error: $e');
    }
  }

  /// §5.5b: Deliver stored CRs when the target device's first packet
  /// arrives (called from _touchPeer on hopCount==0 contact).
  void deliverFirstCrMailbox(Uint8List deviceId, InternetAddress addr, int port) {
    final hex = bytesToHex(deviceId);
    final bucket = _firstCrMailbox.remove(hex);
    if (bucket == null || bucket.isEmpty) return;

    var delivered = 0;
    for (final entry in bucket) {
      if (entry.isExpired) continue;
      final deliver = proto.FirstCrDeliverV3()
        ..encryptedCrBlob = entry.encryptedCrBlob
        ..senderDeviceId = entry.senderDeviceId
        ..storedAtMs = Int64(entry.storedAt.millisecondsSinceEpoch);
      sendInfraDirect(
        messageType: proto.MessageTypeV3.MTV3_FIRST_CR_DELIVER,
        innerPayload: Uint8List.fromList(deliver.writeToBuffer()),
        recipientDeviceId: deviceId,
        addr: addr,
        port: port,
      );
      delivered++;
    }
    if (delivered > 0) {
      _log.info('§5.5b FIRST_CR_DELIVER: pushed $delivered stored CRs '
          'to ${hex.substring(0, 8)} at ${addr.address}:$port');
      _saveFirstCrMailbox();
    }
  }

  /// Evict expired entries from the First-CR-Mailbox (called from periodic tick).
  void _evictExpiredFirstCrMailbox() {
    final before = _firstCrMailbox.length;
    _firstCrMailbox.removeWhere((_, bucket) {
      bucket.removeWhere((e) => e.isExpired);
      return bucket.isEmpty;
    });
    if (_firstCrMailbox.length != before) _saveFirstCrMailbox();
  }

  /// §5.5b: Handle FIRST_CR_DELIVER — a seed peer is forwarding a
  /// stored CR that was deposited while we were offline. Re-inject the
  /// opaque blob into the normal receive pipeline via
  /// `dispatchReassembledPacket` (same path as erasure-coded recovery).
  void _handleFirstCrDeliver(proto.InfrastructureFrameV3 frame,
      Uint8List senderDeviceId) {
    try {
      final deliver = proto.FirstCrDeliverV3.fromBuffer(frame.payload);
      if (deliver.encryptedCrBlob.isEmpty) {
        _log.debug('FIRST_CR_DELIVER drop: empty blob');
        return;
      }
      final origSenderHex = bytesToHex(Uint8List.fromList(deliver.senderDeviceId));
      _log.info('§5.5b FIRST_CR_DELIVER: received stored CR from '
          '${origSenderHex.substring(0, 8)} via seed '
          '${bytesToHex(senderDeviceId).substring(0, 8)} '
          '(storedAt=${deliver.storedAtMs})');
      dispatchReassembledPacket(Uint8List.fromList(deliver.encryptedCrBlob));
    } catch (e) {
      _log.debug('FIRST_CR_DELIVER parse error: $e');
    }
  }

  /// Receive-side bridge: hand the V3 InfraFrame response straight to
  /// [DhtRpc.handleResponse] so the awaiting `sendAndWait` completer fires.
  /// V3-direct contract: the DhtRpc pending-table is keyed by V3 type, and
  /// `_requestTypeFor` maps each `MTV3_*_RESPONSE` to its matching
  /// `MTV3_*_RETRIEVE` request.
  void _bridgeInfraResponseToDhtRpc(
      proto.MessageTypeV3 v3ResponseType,
      proto.InfrastructureFrameV3 frame,
      InternetAddress from,
      int fromPort) {
    // F2 (S123 UDP-dead RCA): every type bridged here (DHT_PONG,
    // DHT_FIND_NODE/FIND_VALUE/STORE_RESPONSE, FRAGMENT_STORE_ACK,
    // IDENTITY_*_RESPONSE) is a reply to something WE sent — proof our
    // send-path is alive, not just our receive-path. See
    // [OutboundLivenessTracker].
    _outboundLiveness.noteConfirmed();
    dhtRpc.handleResponse(
      v3ResponseType,
      Uint8List.fromList(frame.payload),
      Uint8List.fromList(frame.senderDeviceId),
      from.address,
      fromPort,
    );
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// §3.7.3 Reverse-path relay loop prevention: resolve a peer's IP address
  /// to its device-ID hex by scanning DV neighbors. O(N) but N ≤ ~100.
  String? _resolveDeviceHexFromAddress(String ip) {
    for (final nhHex in dvRouting.neighbors.keys) {
      final peer = routingTable.getPeer(hexToBytes(nhHex));
      if (peer != null && peer.addresses.any((a) => a.ip == ip)) {
        return nhHex;
      }
    }
    return null;
  }

  /// Welle 2 Teil 4 (C4-β): Routing-layer chatter that
  /// (a) carries no user-private payload, (b) is high-frequency enough to
  /// justify Ed25519-only Outer-Sigs (§3.5), and (c) — once the receive
  /// pipeline is wired — should be handled inside cleona_node.dart rather
  /// than the application service. PoW is also skipped for these types
  /// (Architecture §2.4 sender step 10).
  ///
  /// The mapping is deliberately conservative: identity-resolution
  /// (`MTV3_IDENTITY_*`) is included so the DHT replicator/resolver can
  /// run without a hop through cleona_service, but live-call media
  /// (`MTV3_CALL_AUDIO/VIDEO`) is **not** infrastructure — those are
  /// ephemeral application frames that already follow the
  /// `applicationFlavor=false` selector independently (cleona_service
  /// owns the call cluster, C3).
  /// §2.3.5 selector predicate. Mirror of the canonical implementation in
  /// `lib/core/network/v3_frame_codec.dart` (top-level
  /// `isInfrastructureMessageTypeV3`); both lists MUST stay in sync. The
  /// codec uses its own copy to avoid an upward dependency on `cleona_node`;
  /// `CleonaNode` keeps this static method as a stable surface for external
  /// callers (CleonaService, tests) that already import this class.
  static bool isInfrastructureMessageTypeV3(proto.MessageTypeV3 type) {
    switch (type) {
      // Peer-list / DHT chatter
      case proto.MessageTypeV3.MTV3_PEER_LIST_PUSH:
      case proto.MessageTypeV3.MTV3_PEER_LIST_SUMMARY:
      case proto.MessageTypeV3.MTV3_PEER_LIST_WANT:
      case proto.MessageTypeV3.MTV3_PEER_KEY_REQUEST:
      case proto.MessageTypeV3.MTV3_PEER_KEY_RESPONSE:
      case proto.MessageTypeV3.MTV3_DHT_PING:
      case proto.MessageTypeV3.MTV3_DHT_PONG:
      case proto.MessageTypeV3.MTV3_DHT_FIND_NODE:
      case proto.MessageTypeV3.MTV3_DHT_FIND_NODE_RESPONSE:
      case proto.MessageTypeV3.MTV3_DHT_STORE:
      case proto.MessageTypeV3.MTV3_DHT_STORE_RESPONSE:
      case proto.MessageTypeV3.MTV3_DHT_FIND_VALUE:
      case proto.MessageTypeV3.MTV3_DHT_FIND_VALUE_RESPONSE:
      // Reed-Solomon fragment storage / S&F mailbox primitives
      case proto.MessageTypeV3.MTV3_FRAGMENT_STORE:
      case proto.MessageTypeV3.MTV3_FRAGMENT_STORE_ACK:
      case proto.MessageTypeV3.MTV3_FRAGMENT_RETRIEVE:
      case proto.MessageTypeV3.MTV3_FRAGMENT_RETRIEVE_RESPONSE:
      case proto.MessageTypeV3.MTV3_FRAGMENT_DELETE:
      case proto.MessageTypeV3.MTV3_PEER_STORE:
      case proto.MessageTypeV3.MTV3_PEER_STORE_ACK:
      case proto.MessageTypeV3.MTV3_PEER_RETRIEVE:
      case proto.MessageTypeV3.MTV3_PEER_RETRIEVE_RESPONSE:
      // Routing / RUDP / NAT control-plane
      case proto.MessageTypeV3.MTV3_ROUTE_UPDATE:
      case proto.MessageTypeV3.MTV3_REACHABILITY_QUERY:
      case proto.MessageTypeV3.MTV3_REACHABILITY_RESPONSE:
      case proto.MessageTypeV3.MTV3_RELAY_FORWARD:
      case proto.MessageTypeV3.MTV3_RELAY_ACK:
      case proto.MessageTypeV3.MTV3_HOLE_PUNCH_REQUEST:
      case proto.MessageTypeV3.MTV3_HOLE_PUNCH_NOTIFY:
      case proto.MessageTypeV3.MTV3_HOLE_PUNCH_PING:
      case proto.MessageTypeV3.MTV3_HOLE_PUNCH_PONG:
      // 2D-DHT identity resolution (§4.3) — also infrastructure
      case proto.MessageTypeV3.MTV3_IDENTITY_AUTH_PUBLISH:
      case proto.MessageTypeV3.MTV3_IDENTITY_AUTH_RETRIEVE:
      case proto.MessageTypeV3.MTV3_IDENTITY_AUTH_RESPONSE:
      case proto.MessageTypeV3.MTV3_IDENTITY_LIVE_PUBLISH:
      case proto.MessageTypeV3.MTV3_IDENTITY_LIVE_RETRIEVE:
      case proto.MessageTypeV3.MTV3_IDENTITY_LIVE_RESPONSE:
      // Welle 5: Device-KEM-Record class — separate DHT key-space ("kem")
      // but same §2.3.5 selector membership as AUTH/LIVE.
      case proto.MessageTypeV3.MTV3_IDENTITY_KEM_PUBLISH:
      case proto.MessageTypeV3.MTV3_IDENTITY_KEM_RETRIEVE:
      case proto.MessageTypeV3.MTV3_IDENTITY_KEM_RESPONSE:
      // Welle 6 (§2.3.5 / §6.3 / §7.4): Identity-Layer Infrastructure.
      // Mirror of the codec list — see top-level
      // `isInfrastructureMessageTypeV3` in v3_frame_codec.dart for rationale.
      case proto.MessageTypeV3.MTV3_RESTORE_BROADCAST:
      case proto.MessageTypeV3.MTV3_KEY_ROTATION_BROADCAST:
      // Guardian / Shamir Social Recovery (§6.2) — mirror of the codec
      // selector list. Trust-bootstrap rationale: see top-level
      // `isInfrastructureMessageTypeV3` in v3_frame_codec.dart.
      case proto.MessageTypeV3.MTV3_GUARDIAN_SHARE_STORE:
      case proto.MessageTypeV3.MTV3_GUARDIAN_RESTORE_REQUEST:
      case proto.MessageTypeV3.MTV3_GUARDIAN_RESTORE_RESPONSE:
      // Wave 2B.3 (§10.2): channel-index gossip — see codec selector for rationale.
      case proto.MessageTypeV3.MTV3_CHANNEL_INDEX_EXCHANGE:
      // Deferred Key Exchange (rev3 §8.1.1) — BOOT path: sender does not yet
      // have recipient's Device-KEM-PK (that's what we're requesting).
      case proto.MessageTypeV3.MTV3_DEVICE_KEM_REQUEST:
      case proto.MessageTypeV3.MTV3_DEVICE_KEM_OFFER:
      // First-CR-Mailbox (rev3 §5.5b) — KEM path (sender has SeedPeer's
      // Device-KEM-PK from routing table).
      case proto.MessageTypeV3.MTV3_FIRST_CR_STORE:
      case proto.MessageTypeV3.MTV3_FIRST_CR_STORE_ACK:
      case proto.MessageTypeV3.MTV3_FIRST_CR_DELIVER:
      // §11.4.8: Anonymous Vote Re-Broadcaster — voter→R bundle + R→voter ACK
      case proto.MessageTypeV3.MTV3_POLL_ANON_SUBMIT:
      case proto.MessageTypeV3.MTV3_POLL_ANON_SUBMIT_ACK:
      // §9.5.7 System-Channel record gossip (S119 D1) — BOOT path
      case proto.MessageTypeV3.MTV3_SYSCHAN_DIGEST:
      case proto.MessageTypeV3.MTV3_SYSCHAN_SUMMARY:
      case proto.MessageTypeV3.MTV3_SYSCHAN_WANT:
      case proto.MessageTypeV3.MTV3_SYSCHAN_PUSH:
        return true;
      default:
        return false;
    }
  }

  // ── V3.0 Send API (Architecture v3.0 §2.6 lifecycle [c]) ──────────

  /// Route a fully-built [NetworkPacketV3] to the device identified by
  /// [deviceId]. Iterates DV routes cheapest-first (max 3), then falls back
  /// to the default-gateway last-resort path (Architecture §4.7). Sets
  /// `nextHopDeviceId` per attempt. Returns true on first kernel-accepted
  /// send. No ACK tracking here — that lives in the service layer alongside
  /// inner ApplicationFrame state. Returns false when the cascade is
  /// exhausted; callers (cleona_service.sendToUser) own S&F orchestration.
  Future<bool> sendToDevice(
      proto.NetworkPacketV3 packet, Uint8List deviceId,
      {String? excludeNextHopHex,
      bool isRelay = false,
      bool expectsReply = true}) async {
    final destHex = bytesToHex(deviceId);
    final myDeviceId = primaryIdentity.deviceNodeId;
    // §5.10.4 — bump the per-peer unACK'd counter BEFORE the send. Every
    // send to this device counts; positive signals from the same device
    // (DELIVERY_RECEIPT, DHT_PONG, PEER_LIST_PUSH) decrement. Reaching
    // [_stage4Threshold] without a decrement triggers Mesh-State Refresh.
    // Loopback short-circuits below skip the increment because the counter
    // is for *wire* round-trips with this peer, not local-delivery hits.
    // §3.1: deviceID is daemon-global, equality with myDeviceId is sufficient.
    final isLoopback = _bytesEqual(deviceId, myDeviceId);
    if (isLoopback) {
      // Loopback — never send, callers should short-circuit. Defensive:
      // dispatch directly to the local-delivery hook. Synthesize a
      // verified-snapshot: we are the sender, so the outer sig is
      // implicitly authenticated by our own keys.
      final loopbackSnapshot = SenderIdentitySnapshot(
        senderDeviceId: myDeviceId,
        senderUserId: Uint8List(0),
        outerSigStatus: OuterSigStatus.verified,
        verifiedDeviceEd25519Pk: _deviceKeys.sig.ed25519PublicKey,
        verifiedDeviceMlDsaPk: _deviceKeys.sig.mlDsaPublicKey,
        newKeyDetectedForSenderUser: false,
        receivedAt: DateTime.now(),
      );
      onApplicationFramePayload?.call(
          packet, InternetAddress('0.0.0.0'), 0, loopbackSnapshot);
      return true;
    }

    // §5.10.4 — wire-bound send: bump the unACK'd counter and check whether
    // the Stage-4 Mesh-Refresh threshold has been crossed *before* this
    // attempt. Fire-and-forget messages (DHT publishes, fragment stores)
    // skip the counter — they have no expected reply, so counting them
    // as "unacked" falsely triggers Mesh-Refresh and Re-Discovery cycles.
    if (expectsReply) {
      final newCount = (_unackedPacketsToPeer[destHex] ?? 0) + 1;
      _unackedPacketsToPeer[destHex] = newCount;
      if (newCount >= _stage4Threshold) {
        _triggerMeshRefresh(deviceId);
      }
    }

    // §3.7.2 relay-forwarding invariant: the packet's nextHopDeviceId must
    // always equal the *final destination* (deviceId), not the intermediate
    // relay hop. The relay node sees nextHopDeviceId != myDeviceId and
    // forwards toward the destination; _sendV3ViaHop uses hopDeviceId only
    // for the physical-address lookup and must NOT overwrite nextHopDeviceId.
    packet.nextHopDeviceId = deviceId;

    final routes = dvRouting.routesTo(destHex);
    var attempts = 0;
    const maxRouteAttempts = 3;
    for (final route in routes) {
      if (attempts >= maxRouteAttempts) break;
      if (!route.isAlive) continue;
      // Determine concrete next hop:
      //  - direct route → hopId is the destination itself
      //  - relay route  → hopId is the next relay device; packet.nextHopDeviceId
      //    stays == deviceId so the relay node forwards rather than delivers locally
      final hopId = route.isDirect ? deviceId : route.nextHop;
      if (hopId == null) continue;
      // §3.7.3 relay loop prevention: skip routes through the excluded node
      if (excludeNextHopHex != null && bytesToHex(hopId) == excludeNextHopHex) continue;
      attempts++;
      _log.info('sendToDevice ${destHex.substring(0, 8)}: DV route #$attempts '
          'via hop=${bytesToHex(hopId).substring(0, 8)} '
          '${route.isDirect ? "direct" : "relay"} cost=${route.cost}');
      final ok = await _sendV3ViaHop(packet, hopId);
      if (ok) {
        // §4.6.2 Stale-direct guard: a direct route's kernel-accept is NOT
        // proof of delivery — the peer may have switched networks (WiFi→
        // Mobilfunk). Only trust it if we received inbound traffic from the
        // destination within 30s. Otherwise mark as best-effort and continue
        // trying relay routes (which go through nodes with fresh addresses).
        if (route.isDirect) {
          final destPeer = routingTable.getPeer(deviceId);
          final inbound = destPeer?.freshestInboundAt;
          if (inbound == null ||
              DateTime.now().difference(inbound) > const Duration(seconds: 30)) {
            _log.info('sendToDevice ${destHex.substring(0, 8)}: direct route '
                'sent but no recent inbound (${inbound != null ? "${DateTime.now().difference(inbound).inSeconds}s ago" : "never"}) '
                '— continuing cascade');
            continue;
          }
        }
        return true;
      }
    }
    // Confirmed DV neighbor: fire-and-forget direct send, but do NOT stop
    // the cascade. "Confirmed" means we once received a hopCount==0 packet
    // from this peer — it does NOT mean the reverse path works (CGNAT Phone
    // receives from LAN node via relay with hopCount==0 punched, but Phone→
    // LAN direct is black-holed). Always fall through to the relay cascade
    // so at least one path with actual delivery evidence gets tried.
    if (dvRouting.neighbors.containsKey(destHex) &&
        isPeerConfirmed(destHex)) {
      _log.info('sendToDevice ${destHex.substring(0, 8)}: '
          'confirmed neighbor — direct + relay cascade');
      await _sendV3ViaHop(packet, deviceId);
    }

    // §8.1.1 Direct-target attempt: the target is in the routing table
    // (added via addPeersFromContactSeed) with addresses from the
    // ContactSeed, but is neither a DV neighbor nor confirmed — the
    // PING→PONG round-trip hasn't completed yet. Send UDP directly to
    // its reachable addresses (fire-and-forget). This handles the common
    // case where both nodes have direct IPv6 reachability on Mobilfunk
    // but the DV routing hasn't converged. The relay cascade below runs
    // regardless — belt-and-suspenders.
    if (!dvRouting.neighbors.containsKey(destHex)) {
      final targetPeer = routingTable.getPeer(deviceId);
      if (targetPeer != null) {
        final allAddrs = targetPeer.allConnectionTargets();
        final reachable = _filterNatContext(allAddrs, targetPeer)
            .where((a) => a.ip.isNotEmpty && a.port > 0 &&
                !a.isInBackoff && a.isReachableFromCurrentNetwork)
            .toList();
        if (reachable.isNotEmpty) {
          _log.info('sendToDevice ${destHex.substring(0, 8)}: '
              'direct-target attempt — ${reachable.length} reachable '
              'address(es) from routing table');
          for (final addr in reachable) {
            try {
              await transport.sendUdp(
                  packet, InternetAddress(addr.ip), addr.port);
            } catch (_) {}
          }
        }
      }
    }

    // Last-resort: try ALL DV neighbors as relay candidates.
    // Prefer the elected default gateway first, then remaining neighbors.
    // This ensures first-contact CRs (phone behind CGNAT with only seed peers
    // as neighbors) try every available relay path, not just one random winner.
    //
    // §3.7.3 relay-forward constraint: when forwarding someone else's packet
    // (isRelay=true), skip the neighbor spray entirely. Relay-forwarding
    // should use learned DV routes and default-GW only — broadcasting a
    // relay packet to all neighbors is flooding, not routing.
    if (isRelay) {
      _log.warn('sendToDevice ${destHex.substring(0, 8)}: relay cascade '
          'exhausted (routes=${dvRouting.routesTo(destHex).length}), '
          'skipping neighbor spray for relayed packet');
      return false;
    }

    // §4.7 Relay-Candidate Reachability Filter (Part 1):
    // Determine whether we need a dual-stack relay (cross-family send).
    // Cross-family: we are IPv4-only AND destination is IPv6-only →
    // the relay hop must bridge the protocol boundary (have both IPv4 and IPv6).
    final destPeer = routingTable.getPeer(deviceId);
    final needsDualStack = destPeer != null &&
        !PeerAddress.hasGlobalIpv6() &&   // we have no IPv6 ourselves
        _destIsIpv6Only(destPeer);         // destination only has IPv6 addrs

    final gwHex = dvRouting.defaultGatewayHex;
    final triedNeighbors = <String>{};
    if (gwHex != null && gwHex != destHex && !_isLocalIdentity(gwHex) &&
        gwHex != excludeNextHopHex) {
      triedNeighbors.add(gwHex);
      final gwBytes = hexToBytes(gwHex);
      final gwPeer = routingTable.getPeer(gwBytes);
      if (gwPeer != null) {
        // D3 Phase 2: skip GW if not admission-PoW verified.
        // §13.1.2 exception: isProtectedSeed peers (ContactSeed §8.1.1)
        // are exempt — bounded (≤5), ephemeral, integrity-anchored.
        if (!gwPeer.idPowVerified && !gwPeer.isProtectedSeed) {
          _log.debug('sendToDevice ${destHex.substring(0, 8)}: GW '
              '${gwHex.substring(0, 8)} skipped — not admission-verified');
        // §4.7 Relay-Candidate Reachability Filter: skip GW if unreachable from us.
        } else if (!_isHopReachableFromHere(gwPeer)) {
          _log.debug('sendToDevice ${destHex.substring(0, 8)}: GW '
              '${gwHex.substring(0, 8)} skipped — not reachable from current network');
        } else if (needsDualStack && !_hopIsDualStack(gwPeer)) {
          _log.debug('sendToDevice ${destHex.substring(0, 8)}: GW '
              '${gwHex.substring(0, 8)} skipped — cross-family send requires dual-stack hop');
        } else {
          _log.info('sendToDevice ${destHex.substring(0, 8)}: '
              'fall through to default-GW ${gwHex.substring(0, 8)}');
          final ok = await _sendV3ViaHop(packet, gwBytes);
          if (ok) return true;
        }
      }
    }

    // Fire-and-forget infrastructure messages (DHT_PING, FRAGMENT_STORE,
    // IDENTITY publishes, etc.) stop after DV-routes + direct-target + GW.
    // The N-neighbor relay spray is only warranted for request/response
    // messages (user messages, CR delivers) where delivery matters.
    // Without this gate, 174 DHT peers × 18 neighbors = 3000+ relay
    // attempts per round — O(peers × neighbors) traffic for zero benefit.
    if (!expectsReply) {
      _log.debug('sendToDevice ${destHex.substring(0, 8)}: fire-and-forget '
          '— skipping neighbor relay spray');
      return false;
    }

    // Last-resort neighbor relay: try up to _kMaxNeighborSpray eligible
    // neighbors as relay hops (request/response messages only).
    // GW is already tried above; remaining neighbors cover the CGNAT
    // First-CR case where seed peers are the only available relay path.
    // Cap prevents O(N) traffic when the neighbor table is large.
    const kMaxNeighborSpray = 5;
    var neighborsTried = 0;
    for (final neighborHex in dvRouting.neighbors.keys) {
      if (neighborsTried >= kMaxNeighborSpray) break;
      if (triedNeighbors.contains(neighborHex)) continue;
      if (neighborHex == destHex) continue;
      if (_isLocalIdentity(neighborHex)) continue;
      if (neighborHex == excludeNextHopHex) continue;
      triedNeighbors.add(neighborHex);
      final nBytes = hexToBytes(neighborHex);
      final nPeer = routingTable.getPeer(nBytes);
      if (nPeer == null) continue;
      if (!nPeer.idPowVerified && !nPeer.isProtectedSeed) continue;
      if (!_isHopReachableFromHere(nPeer)) continue;
      if (needsDualStack && !_hopIsDualStack(nPeer)) continue;
      neighborsTried++;
      _log.info('sendToDevice ${destHex.substring(0, 8)}: '
          'trying neighbor ${neighborHex.substring(0, 8)} as relay '
          '($neighborsTried/$kMaxNeighborSpray)');
      final ok = await _sendV3ViaHop(packet, nBytes);
      if (ok) return true;
    }

    _log.warn('sendToDevice ${destHex.substring(0, 8)}: cascade exhausted '
        '(routes=${routes.length}, neighbors=$neighborsTried/$kMaxNeighborSpray)');
    return false;
  }

  /// Internal: emit [packet] to the address(es) of the hop identified by
  /// [hopDeviceId]. Protocol Escalation per §4.1: UDP (auto-fragments
  /// >1200B via Transport.sendUdp) → TLS fallback if UDP fails on all
  /// targets and payload is large.
  Future<bool> _sendV3ViaHop(
      proto.NetworkPacketV3 packet, Uint8List hopDeviceId) async {
    // packet.nextHopDeviceId is set by the caller (sendToDevice) to the final
    // destination, not to hopDeviceId. This ensures relay nodes forward the
    // packet rather than delivering it locally. Do NOT overwrite it here.
    final hopHex = bytesToHex(hopDeviceId);
    var hopPeer = routingTable.getPeer(hopDeviceId);
    if (hopPeer == null) {
      // §3.1 B-1: fallback — caller may have passed a userId (legacy path).
      hopPeer = routingTable.getPeerByUserId(hopDeviceId);
      if (hopPeer != null) {
        _log.warn('_sendV3ViaHop ${hopHex.substring(0, 8)}: resolved via '
            'userId fallback — caller should pass deviceId');
      }
    }
    if (hopPeer == null) {
      _log.info('_sendV3ViaHop ${hopHex.substring(0, 8)}: peer not found in routing table');
      return false;
    }
    // §4.6 (V3.1.72): direct-confirmed is NOT a send gate. This is the
    // per-hop best-effort send primitive; the sendToDevice cascade decides
    // reachability (direct → relay → S&F) and RUDP-Light (DELIVERY_RECEIPT)
    // proves delivery. We still read direct-confirmed below to decide whether
    // a fire-and-forget UDP "ok" counts as delivered (confirmed peers) or
    // whether we must also try TLS and let the receipt decide (unconfirmed,
    // e.g. CGNAT / first-contact targets).
    final isConfirmed = isPeerConfirmed(hopHex);

    final allTargets = hopPeer.allConnectionTargets();
    final targets = _filterNatContext(allTargets, hopPeer)
        .where((a) => !a.isInBackoff && a.isReachableFromCurrentNetwork)
        .toList();
    if (targets.isEmpty) {
      final afterNat = _filterNatContext(allTargets, hopPeer);
      final backoffList = afterNat.where((a) => a.isInBackoff).map((a) => '${a.ip}:${a.port}').toList();
      final unreachList = afterNat.where((a) => !a.isReachableFromCurrentNetwork).map((a) => '${a.ip}:${a.port}').toList();
      _log.debug('_sendV3ViaHop ${hopHex.substring(0, 8)}: no reachable targets '
          '(all=${allTargets.map((a) => "${a.ip}:${a.port}").toList()}, '
          'backoff=$backoffList, unreach=$unreachList)');
      return false;
    }

    // §4.1 Protocol Escalation: always try UDP first (Transport.sendUdp
    // auto-fragments payloads >1200B with CFRA + NACK retry).
    final wireSize = packet.writeToBuffer().length;
    final isLargePayload = wireSize > maxFragmentPacketSize;
    // §4.1.1 Size-based TLS preference: payloads that need many UDP
    // fragments (>10) are unreliable through CGNAT — carrier NAT drops
    // large bursts silently and zero fragments arrive (no NACK possible).
    // TLS (TCP) handles segmentation + retransmission reliably. Try TLS
    // first for these payloads; fall through to UDP if TLS unavailable.
    final fragmentCount = isLargePayload
        ? (wireSize / maxFragmentPacketSize).ceil()
        : 0;
    final preferTls = fragmentCount > 10;
    _log.info('_sendV3ViaHop ${hopHex.substring(0, 8)}: wireSize=$wireSize '
        'large=$isLargePayload${preferTls ? " preferTls=true frags=$fragmentCount" : ""} '
        'confirmed=$isConfirmed '
        'targets=${targets.map((a) => "${a.ip}:${a.port}").join(",")}');
    if (preferTls) {
      for (final addr in targets) {
        if (!transport.tlsBulkCapable(InternetAddress(addr.ip), addr.port)) continue;
        try {
          final ok = await transport.sendBulkViaTLS(
              packet, InternetAddress(addr.ip), addr.port);
          if (ok) {
            addr.recordSuccess();
            _log.info('_sendV3ViaHop ${hopHex.substring(0, 8)}: '
                'TLS-first ${wireSize}B → ${addr.ip}:${addr.port} OK');
            return true;
          }
        } catch (e) {
          _log.info('_sendV3ViaHop ${hopHex.substring(0, 8)}: '
              'TLS-first to ${addr.ip}:${addr.port} failed: $e');
        }
      }
      _log.debug('_sendV3ViaHop ${hopHex.substring(0, 8)}: '
          'TLS-first failed on all targets, falling back to UDP fragmentation');
    }
    var udpSentAny = false;
    var udpSocketError = false;
    for (final addr in targets) {
      try {
        final ok = await transport.sendUdp(
            packet, InternetAddress(addr.ip), addr.port);
        if (ok) {
          udpSentAny = true;
          // Confirmed peers with recent bidirectional proof: early-return
          // on the first proven address — skip remaining targets.
          if (isConfirmed && addr.lastReceivedAt != null &&
              DateTime.now().difference(addr.lastReceivedAt!) < const Duration(minutes: 2)) {
            return true;
          }
        }
      } catch (e) {
        udpSocketError = true;
        _log.info('_sendV3ViaHop ${hopHex.substring(0, 8)}: UDP to ${addr.ip}:${addr.port} failed: $e');
      }
    }

    // §4.6.2 (V3.1.102): Confirmed peer + UDP sent = success.
    // DELIVERY_RECEIPT (RUDP-Light) is the architectural delivery proof,
    // not lastReceivedAt. A confirmed peer whose bidirectional proof
    // expired (>2 min idle) must NOT be penalised with recordFailure() —
    // that creates a death spiral (cf++ → backoff → no targets → peer
    // unreachable) contradicting the 1h direct-confirmed TTL (§4.6) and
    // the "no timer-based expiry" principle (§5.3). The sendToDevice
    // cascade still tries relay routes via the stale-direct guard (§4.6.2)
    // when freshestInboundAt > 30s.
    if (udpSentAny && isConfirmed) {
      return true;
    }

    // §4.6 (V3.1.72): for peers we are not direct-confirmed for (CGNAT,
    // first-contact), a UDP "ok" is only a local buffer write — the packet
    // may be black-holed. Try TLS on all targets (real delivery feedback);
    // otherwise return false so the cascade continues to relay routes, and
    // RUDP-Light (DELIVERY_RECEIPT) confirms actual delivery.
    if (!isConfirmed) {
      for (final addr in targets) {
        final ia = InternetAddress(addr.ip);
        if (!transport.tlsBulkCapable(ia, addr.port)) continue;
        try {
          final ok = await transport.sendBulkViaTLS(packet, ia, addr.port);
          if (ok) {
            addr.recordSuccess();
            return true;
          }
        } catch (e) {
          _log.info('_sendV3ViaHop ${hopHex.substring(0, 8)}: TLS to ${addr.ip}:${addr.port} failed: $e');
        }
      }
      return false;
    }

    // Only reachable for confirmed peers when ALL UDP sends threw socket
    // errors (udpSentAny == false). Record failure only on actual errors.
    if (udpSocketError) {
      for (final addr in targets) {
        addr.recordFailure();
      }
      _log.info('_sendV3ViaHop ${hopHex.substring(0, 8)}: all ${targets.length} targets failed '
          '(${targets.map((a) => "${a.ip}:${a.port} cf=${a.consecutiveFailures}").join(", ")})');
    }
    return false;
  }

  // ── Welle 5: INFRASTRUCTURE_FRAME sender helpers (§2.3.5 + §2.4.1) ─
  //
  // These three methods are the local stand-in for what will eventually
  // be a Subagent C network helper (`buildInfrastructureFrame`) plus a
  // Subagent A DeviceKem service (`encapsulateForDevice`) plus a
  // Subagent B resolver extension (`lookupDeviceKemRecord`). Until those
  // land in main, cleona_node.dart owns the whole pipeline inline so
  // the Welle-2-Teil-4-blocked sender migration (PEER_LIST_PUSH/SUMMARY,
  // ROUTE_UPDATE, REACHABILITY_RESPONSE, RELAY_ACK, DHT_*, etc.) can
  // ship without a cross-subagent merge dance. Consolidation happens at
  // the Hauptthread merge.

  /// Resolve the recipient's Device-KEM-PK pair (X25519 + ML-KEM-768) for
  /// InfrastructureFrame encap. Two-stage lookup per §4.3 step 4b:
  ///
  ///   1. **DeviceKemRecord (canonical, §3.5b)** — read from the local
  ///      `IdentityDhtHandler` replica cache. Records arrive there via
  ///      `IDENTITY_KEM_PUBLISH` from the publisher of the target device
  ///      (us, when we publish ours; or other replicators when they
  ///      forward). The record carries the device-bound KEM keypair the
  ///      sender wants — not the user-bound one.
  ///   2. **PeerInfo User-KEM (bridge fallback)** — when no DeviceKemRecord
  ///      is replicated locally yet (e.g. early-boot bootstrap peers, or
  ///      peers we have not seen via IDENTITY_KEM_PUBLISH), fall back to
  ///      the User-KEM-PK already cached on `PeerInfo`. This is a
  ///      best-effort bridge: callers that *only* hold User-KEM material
  ///      can still receive infrastructure traffic — the receiver-side
  ///      decap fails (different SK) and silently drops, which matches
  ///      §2.4.1 [10']. The send is therefore "fire-and-forget against the
  ///      best key we know"; the next round (after IDENTITY_KEM_PUBLISH
  ///      replication) will hit the canonical path.
  ///
  /// Returns `null` only when neither source has any KEM material — the
  /// sender then drops the InfraFrame entirely rather than building an
  /// unencryptable packet.
  ({Uint8List x25519Pk, Uint8List mlKemPk})? _lookupDeviceKemPk(
      Uint8List deviceId) {
    var peer = routingTable.getPeer(deviceId);
    if (peer == null) {
      peer = routingTable.getPeerByUserId(deviceId);
      if (peer != null) {
        _log.warn('_lookupDeviceKemPk ${bytesToHex(deviceId).substring(0, 8)}: '
            'resolved via userId fallback — caller should pass deviceId');
      }
    }
    if (peer == null) return null;

    // [1] Canonical: DeviceKemRecord from local 2D-DHT replica cache.
    final userId = peer.userId;
    if (userId != null) {
      final rec = identityDhtHandler.getKemRecord(userId, deviceId);
      if (rec != null && !rec.isExpired()) {
        return (x25519Pk: rec.deviceX25519Pk, mlKemPk: rec.deviceMlKemPk);
      }
    }

    // No Device-KEM record → return null. The BOOT-path allow-list
    // (isBootstrapMessageTypeV3) already covers every essential infra
    // message type. KEM-path messages (DHT_STORE, FRAGMENT_STORE,
    // PEER_STORE, RELAY_*) are dropped until Device-KEM records
    // propagate — correct: sending with wrong key (User-KEM) would
    // cause kemDecapFailed on the receiver anyway.
    return null;
  }

  /// Build a NetworkPacketV3 carrying an InfrastructureFrameV3 inner
  /// targeted at `recipientDeviceId`. Thin wrapper around
  /// [V3FrameCodec.buildInfrastructureFrame]: validates the §2.3.5 selector
  /// and resolves the recipient's Device-KEM-PK pair, then delegates the
  /// `[1']-[8']` pipeline (build → serialize → zstd → KEM-encrypt → Outer
  /// → Ed25519-only Device-Sig → PoW-skip) to the codec.
  ///
  /// Returns `null` when (a) `messageType` is outside the §2.3.5 selector
  /// list, or (b) no Device-KEM-PK is known for the recipient — caller
  /// treats both as "drop the message, no shouting" (§2.4.1 receiver
  /// pipeline drops on KEM-decap failure anyway, so a sender-side drop on
  /// missing PK is symmetric).
  proto.NetworkPacketV3? _buildInfraPacket({
    required proto.MessageTypeV3 messageType,
    required Uint8List innerPayload,
    required Uint8List recipientDeviceId,
  }) {
    if (!isInfrastructureMessageTypeV3(messageType)) {
      _log.warn('_buildInfraPacket: messageType $messageType not in §2.3.5 '
          'selector — refusing to build');
      return null;
    }
    // BOOT path: first-contact bootstrap RPCs ride a plaintext
    // InfrastructureFrameV3 (no KEM, no zstd). This is the only way to
    // break the chicken-and-egg loop where the recipient's Device-KEM-PK
    // is precisely what the bootstrap RPCs are trying to discover.
    // Closed-Network HMAC + Outer Device-Sig + inner-record sigs carry
    // the security properties on this path. See [isBootstrapMessageTypeV3]
    // for the strict allow-list and rationale per type.
    if (isBootstrapMessageTypeV3(messageType)) {
      _log.info(
          '_buildInfraPacket: BOOT-path ${messageType.name} → '
          '${bytesToHex(recipientDeviceId).substring(0, 8)} '
          '(plaintext InfrastructureFrameV3, no KEM)');
      return V3FrameCodec.buildBootstrapInfrastructureFrame(
        recipientDeviceId: recipientDeviceId,
        senderDeviceId: primaryIdentity.deviceNodeId,
        senderDeviceKeys: _deviceKeys.sig,
        messageType: messageType,
        payload: innerPayload,
      );
    }
    // KEM path: the recipient's Device-KEM-PK MUST be in the cache. If
    // it isn't, the message is dropped — the recipient cannot decrypt it
    // anyway, and the BOOT path above is reserved for the strict allow-
    // list of types that legitimately need to operate without a known PK.
    final pks = _lookupDeviceKemPk(recipientDeviceId);
    if (pks == null) {
      _log.debug(
          '_buildInfraPacket: no Device-KEM-PK for ${bytesToHex(recipientDeviceId).substring(0, 8)} '
          '— dropping ${messageType.name}');
      return null;
    }
    return V3FrameCodec.buildInfrastructureFrame(
      recipientDeviceId: recipientDeviceId,
      senderDeviceId: primaryIdentity.deviceNodeId,
      senderDeviceKeys: _deviceKeys.sig,
      messageType: messageType,
      payload: innerPayload,
      recipientDeviceX25519Pk: pks.x25519Pk,
      recipientDeviceMlKemPk: pks.mlKemPk,
    );
  }

  /// Convenience: build + send an InfrastructureFrame to a device. Returns
  /// false when (a) no Device-KEM-PK known (best-effort drop), (b) the DV
  /// cascade exhausts all routes. Fire-and-forget for callers that don't
  /// care about the cascade outcome.
  Future<bool> _sendInfra({
    required proto.MessageTypeV3 messageType,
    required Uint8List innerPayload,
    required Uint8List recipientDeviceId,
  }) async {
    final packet = _buildInfraPacket(
      messageType: messageType,
      innerPayload: innerPayload,
      recipientDeviceId: recipientDeviceId,
    );
    if (packet == null) return false;
    return sendToDevice(packet, recipientDeviceId,
        expectsReply: _isRequestResponseType(messageType));
  }

  /// True for message types that expect a reply (request/response patterns).
  /// False for fire-and-forget DHT publishes and stores — these should not
  /// drive the §5.10.4 unacked-packets counter because no reply is expected.
  ///
  /// DHT infrastructure queries (AUTH/LIVE/KEM_RETRIEVE, FIND_NODE) are
  /// classified as fire-and-forget despite expecting a DhtRpc-level response:
  /// they fan out to K=10 closest peers via _parallelSendAndWait, so the
  /// K-way redundancy replaces the per-query neighbor relay spray. DhtRpc
  /// handles its own timeouts independently of the unacked-packets counter.
  static bool _isRequestResponseType(proto.MessageTypeV3 type) {
    switch (type) {
      // Fire-and-forget: DHT publishes, fragment/peer stores, broadcasts
      case proto.MessageTypeV3.MTV3_IDENTITY_AUTH_PUBLISH:
      case proto.MessageTypeV3.MTV3_IDENTITY_LIVE_PUBLISH:
      case proto.MessageTypeV3.MTV3_IDENTITY_KEM_PUBLISH:
      case proto.MessageTypeV3.MTV3_FRAGMENT_STORE:
      case proto.MessageTypeV3.MTV3_FRAGMENT_RETRIEVE:
      case proto.MessageTypeV3.MTV3_PEER_STORE:
      case proto.MessageTypeV3.MTV3_PEER_RETRIEVE:
      case proto.MessageTypeV3.MTV3_PEER_LIST_PUSH:
      case proto.MessageTypeV3.MTV3_PEER_LIST_WANT:
      case proto.MessageTypeV3.MTV3_ROUTE_UPDATE:
      case proto.MessageTypeV3.MTV3_RESTORE_BROADCAST:
      case proto.MessageTypeV3.MTV3_KEY_ROTATION_BROADCAST:
      case proto.MessageTypeV3.MTV3_GUARDIAN_SHARE_STORE:
      // DHT infrastructure queries: K=10 fanout provides redundancy,
      // neighbor relay spray per query is O(K×N) for zero benefit.
      case proto.MessageTypeV3.MTV3_IDENTITY_AUTH_RETRIEVE:
      case proto.MessageTypeV3.MTV3_IDENTITY_LIVE_RETRIEVE:
      case proto.MessageTypeV3.MTV3_IDENTITY_KEM_RETRIEVE:
      case proto.MessageTypeV3.MTV3_DHT_FIND_NODE:
        return false;
      // Everything else: request/response (PING→PONG, user messages, CRs)
      default:
        return true;
    }
  }

  /// Public delegate to [_buildInfraPacket]. Service-layer callers that need
  /// access to the constructed packet bytes (e.g. §5.4 Reed-Solomon
  /// offline-delivery, which serializes the canonical InfraFrame packet for
  /// erasure-coded fragmentation) build via this entrypoint and then either
  /// send via [sendToDevice] + capture, or distribute via the offline path.
  proto.NetworkPacketV3? buildInfraPacket({
    required proto.MessageTypeV3 messageType,
    required Uint8List innerPayload,
    required Uint8List recipientDeviceId,
  }) =>
      _buildInfraPacket(
        messageType: messageType,
        innerPayload: innerPayload,
        recipientDeviceId: recipientDeviceId,
      );

  /// Serialize a built `NetworkPacketV3` to wire bytes (HMAC-tagged). Used by
  /// the §5.4 Reed-Solomon offline-delivery path to obtain the canonical wire
  /// bytes for fragmentation, identical to what would have been sent over UDP.
  /// The receiver's HMAC-verify in `dispatchReassembledPacket` accepts these
  /// bytes after Reed-Solomon reassembly.
  Uint8List serializePacketForOfflineDelivery(proto.NetworkPacketV3 packet) =>
      transport.serializeWithTag(packet);

  /// Public delegate to [_sendInfra]. Service-layer migrations that own the
  /// per-device fan-out (Welle 6 §6.3 RESTORE_BROADCAST and §7.4 Emergency
  /// KEY_ROTATION_BROADCAST) call this with `(messageType, innerPayload,
  /// recipientDeviceId)` after resolving the recipient's authorized device
  /// set via `IdentityResolver.resolve(...)`. Returns false on
  /// (a) `messageType` outside the §2.3.5 selector, (b) no Device-KEM-PK
  /// known for `recipientDeviceId`, or (c) the DV cascade exhausting all
  /// routes. Fire-and-forget — the offline-cascade (S&F + Reed-Solomon)
  /// remains the service-layer's responsibility.
  Future<bool> sendInfraTo({
    required proto.MessageTypeV3 messageType,
    required Uint8List innerPayload,
    required Uint8List recipientDeviceId,
  }) =>
      _sendInfra(
        messageType: messageType,
        innerPayload: innerPayload,
        recipientDeviceId: recipientDeviceId,
      );

  /// Direct UDP send of an InfrastructureFrame to a specific peer's
  /// address. Bypasses DV cascade — used for hole-punch / port-probe /
  /// ping / FIRST_CR_STORE where the caller already has the on-wire
  /// address. Returns false on KEM-PK miss or transport rejection.
  Future<bool> sendInfraDirect({
    required proto.MessageTypeV3 messageType,
    required Uint8List innerPayload,
    required Uint8List recipientDeviceId,
    required InternetAddress addr,
    required int port,
  }) async {
    final packet = _buildInfraPacket(
      messageType: messageType,
      innerPayload: innerPayload,
      recipientDeviceId: recipientDeviceId,
    );
    if (packet == null) return false;
    packet.nextHopDeviceId = recipientDeviceId;
    try {
      return await transport.sendUdp(packet, addr, port);
    } catch (e) {
      _log.debug('sendInfraDirect: transport error to ${addr.address}:$port: $e');
      return false;
    }
  }

  /// Build a BOOT-path infrastructure packet and deliver it via the full
  /// DV relay cascade ([sendToDevice]).  Unlike [sendInfraDirect] this
  /// works from CGNAT/mobile because the cascade falls through to relay
  /// hops when direct UDP is unreachable.
  Future<bool> sendInfraViaDeviceRoute({
    required proto.MessageTypeV3 messageType,
    required Uint8List innerPayload,
    required Uint8List recipientDeviceId,
  }) async {
    final packet = _buildInfraPacket(
      messageType: messageType,
      innerPayload: innerPayload,
      recipientDeviceId: recipientDeviceId,
    );
    if (packet == null) return false;
    return sendToDevice(packet, recipientDeviceId, expectsReply: false);
  }

  /// Resolve a user identifier to the set of authorized device-node-IDs
  /// via the 2D-DHT auth-manifest (Architecture §2.2.4). Wraps
  /// [identityResolver.resolve] and projects the result to deviceNodeIds.
  Future<List<Uint8List>> resolveUserToDevices(Uint8List userId) async {
    final devices = await identityResolver.resolve(userId);
    return devices
        .map((d) => Uint8List.fromList(d.deviceNodeId))
        .toList(growable: false);
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

    // Send PING to discovered peer (works same-subnet, may fail cross-NAT)
    _sendPing(from.address, peerPort);

    // NAT-compatible echo: send a discovery probe BACK via the discovery
    // socket to the actual source address:port. In NAT scenarios the
    // transport-port PING above is dropped (OPNsense only has a NAT
    // mapping for discovery port 41338, not for the transport port).
    // The echo uses the same port-41338 channel the probe arrived on,
    // so it traverses the existing NAT mapping. The remote side receives
    // our nodeId+port, adds us to its routing table, and can then
    // initiate transport-level traffic (creating its own NAT state).
    if (fromPort != peerPort) {
      localDiscovery.sendUnicastDiscovery(from.address, fromPort);
    }
  }

  void _onPeerDiscovered(Uint8List peerId, int peerPort, InternetAddress from, int fromPort) {
    _onDiscoveryReceived(peerId, peerPort, from, fromPort);
  }

  /// §5.3 Reverse-Relay-Path-Learning: identify which DV neighbor
  /// physically relayed a packet from [originatorHex] and add a relay
  /// route hint so the reply cascade can use the same relay.
  String? _learnReverseRelayPath(String originatorHex, String relayIp, int relayPort) {
    for (final neighborHex in dvRouting.neighborIds) {
      final peer = routingTable.getPeer(hexToBytes(neighborHex));
      if (peer == null) continue;
      for (final addr in peer.addresses) {
        if (addr.ip == relayIp) {
          final ct = connectionTypeFromPriority(addr.priority);
          final cost = connectionTypeCost(ct) + 10; // relay penalty
          final added = dvRouting.addRelayRouteHint(originatorHex, neighborHex, cost);
          if (added) {
            _log.info('Reverse-relay-path: ${originatorHex.substring(0, 8)} '
                'reachable via ${neighborHex.substring(0, 8)} (cost=$cost)');
          }
          return neighborHex;
        }
      }
    }
    return null;
  }

  /// Update or create a peer entry in the routing table.
  /// [peerId] is the deviceNodeId (per-device routing key).
  /// [userId] is the stable identity (optional, attached to PeerInfo for lookups).
  void _touchPeer(Uint8List peerId, String ip, int port,
      {bool isAuthoritative = false, Uint8List? userId,
       bool isUdp = true}) {
    final existing = routingTable.getPeer(peerId);
    if (existing != null) {
      existing.lastSeen = DateTime.now();
      // Phase 2: update userId if newly learned. Go through the routing
      // table so the secondary userId→peers index stays consistent —
      // otherwise the freshly-learned userId is invisible to O(1) lookups.
      if (userId != null && existing.userId == null) {
        routingTable.setPeerUserId(existing, userId);
      } else if (userId != null &&
          existing.userId != null &&
          !_bytesEqual(userId, existing.userId!)) {
        // Multi-identity: same device, different userId (e.g. two identities on
        // the same daemon). Register the additional userId in the secondary
        // index so resolveUserToDevices() can find this device for either
        // identity (§26 §3.1). Primary field stays unchanged.
        routingTable.addExtraUserIdIndex(peerId, userId);
      }

      // TLS (TCP) source ports are ephemeral — they are NOT the peer's
      // listening port and must never be stored as a reachable address.
      // A TLS-delivered packet proves the peer is alive (lastSeen updated
      // above), but the source port is a one-shot client port that the OS
      // assigns per connection. Storing it pollutes the address list with
      // dead ports that outrank the real UDP listening port in
      // allConnectionTargets() because they carry lastReceivedAt.
      // For TLS: credit the liveness signal to the best known address
      // with matching IP (if any), but do NOT add the ephemeral port.
      if (!isUdp && ip.isNotEmpty && ip != '0.0.0.0' && ip != '::') {
        for (final addr in existing.addresses) {
          if (addr.ip == ip) {
            addr.recordReceived();
            break;
          }
        }
        routingTable.addPeer(existing);
      } else {
      // Inbound packet from a known address is the only hard proof we
      // have that this address actually works. UDP sendto() returning OK
      // at the sender side does NOT prove delivery (kernel accepts the
      // packet for unroutable destinations like 192.0.0.4 too) — without
      // this hook, recordSuccess() would never fire for non-ack-worthy
      // traffic and stale addresses kept score=1.0 from artefactual
      // sender-side bumps.
      if (ip.isNotEmpty && ip != '0.0.0.0' && ip != '::') {
        for (final addr in existing.addresses) {
          if (addr.ip == ip && addr.port == port) {
            addr.recordReceived();
            break;
          }
        }
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
          final newAddr = PeerAddress(
            ip: ip,
            port: port,
            type: PeerAddress.classifyIp(ip),
          );
          newAddr.recordReceived();
          existing.addresses.add(newAddr);
        } else {
          for (final addr in existing.addresses) {
            if (addr.ip == ip && addr.port == port) {
              addr.recordReceived();
            }
          }
        }
      }
      routingTable.addPeer(existing);
      }
    } else {
      // TLS-only first contact: don't store the ephemeral port.
      // The peer will be learned properly via UDP discovery or gossip.
      if (!isUdp) return;
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
        final newAddr = PeerAddress(
          ip: ip,
          port: port,
          type: PeerAddress.classifyIp(ip),
        );
        newAddr.recordReceived();
        peer.addresses.add(newAddr);
      }
      routingTable.addPeer(peer);
    }

    if (isUdp && isAuthoritative && ip.isNotEmpty && _needsKeepalive(ip) &&
        port > 0) {
      // §4.6 IPv6-First: on Desktop, skip IPv4 keepalive if this peer has
      // a global IPv6 (no NAT pinhole needed). On Mobile, ALWAYS register —
      // keepalive is the dead-network detector that triggers force-recovery.
      final peerInfo = routingTable.getPeer(peerId);
      final hasGlobalIpv6 = peerInfo != null && peerInfo.allConnectionTargets().any((a) =>
          a.ip.contains(':') && !a.ip.toLowerCase().startsWith('fe80:') &&
          !a.ip.toLowerCase().startsWith('fd'));
      if (!hasGlobalIpv6 || Platform.isAndroid || Platform.isIOS) {
        udpKeepalive.register(bytesToHex(peerId), ip, port, peerId);
      }
    }

    // §5.5b: Deliver stored First-CR-Mailbox entries to this device.
    if (isUdp && isAuthoritative && ip.isNotEmpty && ip != '0.0.0.0' && ip != '::') {
      try {
        deliverFirstCrMailbox(peerId, InternetAddress(ip), port);
      } catch (_) {}
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
    // Welle 2A V3-direct: hand DhtRpc the typed request body directly.
    // Outer Device-Sig + KEM-AEAD are added by the InfraFrame pipeline in
    // `_sendInfra` (wired into `dhtRpc.sendFunction` at init).
    final body = Uint8List.fromList((proto.DhtFindNode()
          ..targetId = targetId
          ..senderId = primaryIdentity.nodeId)
        .writeToBuffer());

    final response = await dhtRpc.sendAndWait(
      proto.MessageTypeV3.MTV3_DHT_FIND_NODE,
      body,
      peer,
    );
    if (response == null) return [];

    try {
      final respData = proto.DhtFindNodeResponse.fromBuffer(response.payload);
      final result = <PeerInfo>[];
      for (final p in respData.closestPeers) {
        final info = PeerInfo.fromProto(p);
        if (info.networkChannel.isNotEmpty && info.networkChannel != networkChannel) continue;
        routingTable.addPeer(info);
        _verifyAdmissionPow(info.nodeId);
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
    // Welle 5 INFRASTRUCTURE_FRAME path. DHT_PING is sent unsolicited to
    // a freshly-discovered IP:port pair where we may not yet know the
    // recipient's deviceId — Kademlia-style discovery probes work that
    // way. We try to look the peer up by address; on miss we cannot
    // build an InfraFrame (no deviceId → no Device-KEM-PK) and silently
    // skip the ping. The catch-up path (_handleHello / _handlePong)
    // populates the routing table on the first reverse-direction
    // packet, after which subsequent pings have a deviceId to encrypt
    // against.
    //
    // TODO (Hauptthread merge — Welle 5 Subagent A+B): when DeviceKEM is
    // a first-class field on PeerInfo and discovery responses include
    // it, the address-to-deviceId lookup gets reliable. Today's
    // best-effort path is symmetric with §2.4.1 which silently drops
    // on KEM-PK mismatch anyway.
    PeerInfo? recipient;
    for (final p in routingTable.allPeers) {
      for (final a in p.allConnectionTargets()) {
        if (a.ip == ip && a.port == port) {
          recipient = p;
          break;
        }
      }
      if (recipient != null) break;
    }
    if (recipient == null) {
      _log.debug('_sendPing: no peer at $ip:$port — skipping discovery ping '
          '(deviceId unknown until reverse-direction packet)');
      return;
    }

    final ping = proto.DhtPing()
      ..senderId = primaryIdentity.deviceNodeId;

    await sendInfraDirect(
      messageType: proto.MessageTypeV3.MTV3_DHT_PING,
      innerPayload: ping.writeToBuffer(),
      recipientDeviceId: recipient.nodeId,
      addr: InternetAddress(ip),
      port: port,
    );
  }

  /// Check if a hex ID belongs to any registered local identity.
  /// Matches by userId (per-identity), or by daemon-global deviceNodeId
  /// (shared by all hosted identities, §3.1).
  bool _isLocalIdentity(String hex) {
    return _identities.containsKey(hex) ||
        bytesToHex(primaryIdentity.deviceNodeId) == hex;
  }

  /// Filter targets by NAT context: private IPs are only meaningful when our
  /// public IP matches the peer's public IP (same NAT). Without this check,
  /// 192.0.2.15 behind NAT-A gets sent to a device behind NAT-B — wasted traffic.
  List<PeerAddress> _filterNatContext(List<PeerAddress> targets, PeerInfo peer) {
    final myPublicIp = natTraversal.publicIpForNatContext;
    // If our "public" IP is actually a private IP (NAT module misdetection),
    // treat as unknown — don't block private targets based on bad data.
    final effectivePublicIp = (myPublicIp != null && _isPrivateIp(myPublicIp)) ? null : myPublicIp;
    return targets.where((addr) {
      // IPv6 global: no NAT context needed — always routable
      if (addr.ip.contains(':') && !addr.ip.toLowerCase().startsWith('fe80:')) return true;
      if (!_isPrivateIp(addr.ip)) return true;
      // Private-to-private: allow if both are in the same address class.
      // §4.7: CGNAT (100.64/10) has zero routing relationship to RFC 1918
      // — a mobile node on 100.65.x sending to 192.168.10.x is futile.
      // Cross-subnet RFC 1918 (e.g. 192.168.10.x ↔ 192.0.2.x) remains
      // permitted — reaches via the gateway router (OPNsense).
      if (_isPrivateIp(_localIp) && _isPrivateIp(addr.ip)) {
        final localCgnat = _isCgnat(_localIp);
        final targetCgnat = _isCgnat(addr.ip);
        if (localCgnat == targetCgnat) return true;
        // CGNAT ↔ RFC 1918: guaranteed unreachable, skip
        return false;
      }
      // Private IP: only try if same NAT (matching public IP) or unknown
      return effectivePublicIp == null || effectivePublicIp == peer.publicIp || peer.publicIp.isEmpty;
    }).toList();
  }

  // ── §4.7 Relay-Candidate Reachability Filters ────────────────────────

  /// §4.7 Part 1: True iff we (the sender) can actually reach [hopPeer].
  ///
  /// A relay hop we cannot reach is worthless: we would send the packet
  /// into a black hole. This mirrors the `isReachableFromCurrentNetwork`
  /// guard already applied per-address in `_sendV3ViaHop` — the difference
  /// is that here we filter whole hops in the neighbor-spray before even
  /// calling `_sendV3ViaHop`, avoiding the log spam and unnecessary TLS
  /// attempts for entirely unreachable candidates.
  ///
  /// "Reachable" = at least one non-backoff address on [hopPeer] passes
  /// `isReachableFromCurrentNetwork` (the same guard used in _sendV3ViaHop).
  bool _isHopReachableFromHere(PeerInfo hopPeer) {
    return hopPeer.allConnectionTargets().any(
      (a) => !a.isInBackoff && a.isReachableFromCurrentNetwork,
    );
  }

  /// §4.7 Part 1 — Cross-Family: true iff all of [destPeer]'s addresses are
  /// IPv6 (the destination is IPv6-only from our perspective).
  ///
  /// Used to detect the IPv4-only-sender → IPv6-only-destination scenario
  /// where a relay hop MUST be dual-stack (§4.7).
  bool _destIsIpv6Only(PeerInfo destPeer) {
    final addrs = destPeer.allConnectionTargets();
    if (addrs.isEmpty) return false;
    return addrs.every((a) => a.ip.contains(':'));
  }

  /// §4.7 Part 1 — Cross-Family: true iff [hopPeer] has at least one IPv4
  /// address reachable from here AND at least one IPv6 address that is
  /// reachable from the destination (i.e. is an IPv6 global address,
  /// irrespective of whether WE have IPv6 ourselves — the hop bridges for us).
  ///
  /// We use a structural check (has both IPv4 and IPv6 addresses in its
  /// address list) rather than a capabilities bitmask because:
  ///   a) The capabilities field is not yet populated by older peers.
  ///   b) A peer's address list IS the ground truth for what protocols it
  ///      has bound and advertised.
  bool _hopIsDualStack(PeerInfo hopPeer) {
    final addrs = hopPeer.allConnectionTargets();
    final hasIpv4 = addrs.any((a) => !a.ip.contains(':'));
    final hasIpv6 = addrs.any((a) => a.ip.contains(':') &&
        a.type == PeerAddressType.ipv6Global);
    return hasIpv4 && hasIpv6;
  }

  /// Public IP to advertise to peers: port-verified (UPnP/STUN) takes
  /// priority, then explicit manual override (DNAT on Bootstrap).
  /// `publicIpForNatContext` (ipify-only) is deliberately excluded —
  /// it has no port verification and would cause every node behind the
  /// same NAT to advertise the WAN IP with a non-DNAT'd local port.
  String? get _advertisedPublicIp =>
      natTraversal.publicIp ?? manualPublicIp;

  /// Public port to advertise. When `--public-ip` was set manually (Bootstrap
  /// / seed nodes), the listening port is authoritative — a NAT port-probe may
  /// detect a DNAT-translated port (e.g. Fritzbox maps external:8080 →
  /// internal:8081) which belongs to a DIFFERENT network channel (Live vs Beta)
  /// and must never be advertised.
  int? get _advertisedPublicPort =>
      manualPublicIp != null ? port : natTraversal.publicPort;

  /// §2.2.4: Liefert die aktuelle Adress-Liste dieses Nodes als
  /// `PeerAddressProto`-Bündel für die Liveness-Records. LAN-Adressen
  /// (`_localIps`) plus Public-IP aus NAT-Traversal (UPnP/PCP/external-probe).
  List<proto.PeerAddressProto> currentSelfAddresses() {
    final list = <proto.PeerAddressProto>[];
    for (final ip in _localIps) {
      if (ip.isEmpty || ip == '0.0.0.0' || ip == '::') continue;
      list.add(proto.PeerAddressProto()
        ..ip = ip
        ..port = port
        ..addressType = PeerAddress.typeToProto(PeerAddress.classifyIp(ip)));
    }
    final pubV4 = _advertisedPublicIp;
    final pubPort = _advertisedPublicPort ?? port;
    if (pubV4 != null && pubV4.isNotEmpty) {
      list.add(proto.PeerAddressProto()
        ..ip = pubV4
        ..port = pubPort
        ..addressType = proto.AddressType.IPV4_PUBLIC);
    }
    // §4.7 IPv6 Inbound Probe: always include the global IPv6 address.
    // On mobile carriers the inbound probe often fails (carrier stateful
    // firewall blocks unsolicited UDP), but the address is still valid for
    // outbound-initiated connections: if BOTH peers send to each other's
    // IPv6 simultaneously, the carrier firewall opens in both directions
    // (simultaneous-open). Suppressing the address entirely prevents peers
    // from ever attempting direct IPv6 delivery.
    final pubV6 = natTraversal.publicIpv6;
    if (pubV6 != null && pubV6.isNotEmpty) {
      list.add(proto.PeerAddressProto()
        ..ip = pubV6
        ..port = port
        ..addressType = proto.AddressType.IPV6_GLOBAL);
    }
    return list;
  }

  /// Send an envelope to a specific peer by node ID.
  /// V3 + §2.2.4: Cache-Hit → Dim-2 Resolution → S&F/Reed-Solomon/Mailbox-Pull.
  /// Kein Legacy-Resolution-Fallback (Hard-Cut, gebündelt mit Sec H-5 KEM v2).
  /// DV-Routing bleibt als TRANSPORT-Mechanismus aktiv für die aufgelösten
  /// Returns true if any peer has been confirmed reachable since this node
  /// started. Uses PeerInfo.lastSeen (set on PONG / actual message receipt)
  /// rather than PeerAddress.lastSuccess (set on OS-level send, which can
  /// succeed even when the peer is unreachable due to AP isolation).
  /// Ignores lastSeen values loaded from disk (previous sessions).
  bool _hasRecentlyReachablePeer() {
    // Spec-aligned reachability check (Architecture §5.10.5): a peer is
    // considered reachable in this session only if at least one
    // HMAC-validated, rate-limit-passed packet has actually arrived.
    // `PeerInfo.lastSeen` from disk-loaded entries is NOT a valid signal —
    // a single dead entry with a touched lastSeen would otherwise abort
    // Stage-5 Re-Discovery and leave the daemon mesh-isolated.
    return _authenticatedReceivesInSession > 0;
  }

  bool _hasCrossSubnetPeer() {
    if (_localIps.isEmpty) return false;
    final ownThirdOctets = <int>{};
    for (final ip in _localIps) {
      final parts = ip.split('.');
      if (parts.length == 4) {
        final c = int.tryParse(parts[2]);
        if (c != null) ownThirdOctets.add(c);
      }
    }
    if (ownThirdOctets.isEmpty) return false;
    for (final peer in routingTable.allPeers) {
      if (!isPeerConfirmed(peer.nodeIdHex)) continue;
      // A peer that also has an address on our own /24 is a same-subnet
      // peer with extra addresses (e.g. KVM libvirt bridge 192.168.122.1).
      // Only count peers that have NO address on our subnet — those are
      // genuine cross-subnet peers (e.g. Bootstrap on 192.168.178.x).
      bool hasLocalAddr = false;
      bool hasCrossAddr = false;
      for (final addr in peer.addresses) {
        final parts = addr.ip.split('.');
        if (parts.length == 4) {
          final c = int.tryParse(parts[2]);
          if (c != null) {
            if (ownThirdOctets.contains(c)) {
              hasLocalAddr = true;
            } else {
              hasCrossAddr = true;
            }
          }
        }
      }
      if (hasCrossAddr && !hasLocalAddr) return true;
    }
    return false;
  }

  // ── Maintenance ────────────────────────────────────────────────────

  void _maintenance() {
    // V3.1.111: 4h→24h so overnight-offline peers survive until morning.
    // evictStalePeers() catches zombies with high failure rates sooner.
    final peersBefore = routingTable.allPeers.map((p) => p.nodeIdHex).toSet();
    for (final peer in routingTable.allPeers) {
      final age = DateTime.now().difference(peer.lastSeen);
      if (age.inHours >= 24) {
        _log.info('Maintenance: peer ${peer.nodeIdHex.substring(0, 8)} age=${age.inSeconds}s will be pruned');
      }
    }
    final pruned = routingTable.prune(const Duration(hours: 24));
    if (pruned > 0) {
      _log.info('Maintenance: pruned $pruned stale peers');
      final peersAfter = routingTable.allPeers.map((p) => p.nodeIdHex).toSet();
      final removed = peersBefore.difference(peersAfter);
      for (final hex in removed) {
        _log.info('Maintenance: removed ${hex.substring(0, 8)} from routing table');
        dvRouting.removeNeighbor(hexToBytes(hex));
        udpKeepalive.unregister(hex);
      }
    }
    // H-3: Evict DV neighbors that are no longer in the routing table.
    // When routingTable.prune() evicts a peer, the DV _neighbors map may
    // still reference it. Gateway selection then scores a neighbor with no
    // addresses, leading to sends into the void.
    final dvNeighborIds = dvRouting.neighborIds;
    for (final nid in dvNeighborIds) {
      if (routingTable.getPeer(hexToBytes(nid)) == null) {
        _log.info('Maintenance: evicting zombie DV neighbor ${nid.substring(0, 8)}');
        dvRouting.removeNeighbor(hexToBytes(nid));
      }
    }
    // Deep GC: protected seeds survive the 4h prune for Doze-resilience
    // but should NOT pile up forever (retired devices from old QR scans).
    // Gated to at most once per hour inside the routing table itself.
    final staleSeeds = routingTable.pruneStaleSeeds(const Duration(days: 30));
    if (staleSeeds > 0) {
      _log.info('Maintenance: pruned $staleSeeds stale seed peers (>30d)');
    }
    // Evict peers with high failure count + old lastSeen + no alive DV routes.
    // Catches zombie peers (e.g. stale deviceIds) that accumulate failures
    // without being old enough for the 4h prune.
    final evicted = routingTable.evictStalePeers(
      hasAliveRoutes: (deviceHex) =>
          dvRouting.aliveRouteCountFor(deviceHex) > 0,
    );
    if (evicted.isNotEmpty) {
      for (final hex in evicted) {
        _log.info('Maintenance: evicted stale peer ${hex.substring(0, 8)} '
            '(high failures, no alive routes)');
        dvRouting.removeNeighbor(hexToBytes(hex));
        udpKeepalive.unregister(hex);
      }
    }
    // Prune expired DV routes (dead for >15 min, not refreshed).
    final expiredDests =
        dvRouting.pruneExpiredRoutes(const Duration(minutes: 15));
    if (expiredDests.isNotEmpty) {
      _log.info('Maintenance: pruned ${expiredDests.length} expired DV destinations');
    }
    // Prune stale addresses (>14 days without lastSuccess)
    var staleAddrs = 0;
    for (final peer in routingTable.allPeers) {
      staleAddrs += peer.pruneStaleAddresses();
    }
    if (staleAddrs > 0) {
      _log.info('Maintenance: removed $staleAddrs stale addresses');
    }

    // Prune cooldown/tracker maps to prevent unbounded growth on long-running
    // daemons. Each map has a documented TTL matching its operational window.
    final now = DateTime.now();
    _dvSeedWantCooldown.removeWhere((_, ts) => now.difference(ts).inMinutes > 15);
    _outstandingPeerListWants.removeWhere((_, ts) => now.difference(ts) > _solicitedReplyWindow);
    _peerKeyRequestCooldown.removeWhere((_, ts) => now.difference(ts).inMinutes > 5);
    _lastStalePkProbe.removeWhere((_, ts) => now.difference(ts) > _stalePkProbeThrottle * 2);
    _lastMeshRefresh.removeWhere((_, ts) => now.difference(ts) > _meshRefreshThrottle * 2);
    _lastRouteEpochSentTo.removeWhere((hex, _) => routingTable.getPeer(hexToBytes(hex)) == null);
    _unackedPacketsToPeer.removeWhere((hex, _) => routingTable.getPeer(hexToBytes(hex)) == null);
    _confirmedPeers.removeWhere((_, ts) => now.difference(ts) > _confirmedPeerTtl);

    // §4.5: if pruning/eviction dropped us to zero peers mid-session, (re-)arm
    // the isolated-node retry — only when it is not already running, so the
    // 15-min maintenance tick never resets an in-flight backoff.
    if (routingTable.peerCount == 0 && _isolatedNodeRetryTimer == null) {
      _armIsolatedNodeTimer();
    }

    // Safety net: if peers exist in the routing table but NONE are confirmed
    // (all unreachable), the phone is effectively isolated — yet the
    // isolated-node timer won't arm (peerCount > 0) and the zero-peer
    // recovery timer only starts from onNetworkChanged(). Re-bootstrap
    // immediately and arm the zero-peer recovery loop.
    if (routingTable.peerCount > 0 && _confirmedPeers.isEmpty &&
        _zeroPeerRecoveryTimer == null) {
      _log.info('Maintenance: 0 confirmed peers with ${routingTable.peerCount} '
          'in RT — triggering recovery cascade');
      for (final peer in routingTable.allPeers) {
        for (final addr in peer.addresses) {
          addr.consecutiveFailures = 0;
        }
      }
      _kademliaBootstrap();
      _startDiscoveryCascade();
      _zeroPeerRecoveryTimer?.cancel();
      _zeroPeerRecoveryTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
        if (!_running) { timer.cancel(); return; }
        if (_outboundRecentlyConfirmed) {
          _log.info('Zero-peer recovery (maintenance): outbound confirmed — stopping');
          timer.cancel();
          _zeroPeerRecoveryTimer = null;
          return;
        }
        _log.info('Zero-peer recovery (maintenance): still 0 confirmed — re-bootstrap');
        for (final peer in routingTable.allPeers) {
          for (final addr in peer.addresses) {
            addr.consecutiveFailures = 0;
          }
        }
        PeerAddress.networkChangeGraceUntil =
            DateTime.now().add(const Duration(seconds: 10));
        udpKeepalive.resetUnconfirmed();
        _kademliaBootstrap();
        _startDiscoveryCascade();
      });
    }

    // Cross-subnet discovery (§4.10): if no peer on a different /24 is known,
    // run a subnet scan. Architecturally replaces the removed bootstrap_seeds.json.
    if (!_hasCrossSubnetPeer()) {
      _log.info('Maintenance: no cross-subnet peer — starting subnet scan');
      localDiscovery.startSubnetScan(
          _localIps, () => _hasCrossSubnetPeer());
    }

    dvRouting.updateDefaultGateway();
    peerMessageStore.pruneExpired();
    _evictExpiredFirstCrMailbox();
    // V3.0: messageQueue.pruneExpired() entfällt — keine persistente SendQueue.
    _saveRoutingTable();
    // Snapshot the DV-table together with the routing table so the two
    // disk files stay coherent (Architektur §2.7.3). A crash between the
    // two writes can at worst leave a stale `dv_routing.json` referring
    // to peers no longer in `routing_table.json`; loadFromJson tolerates
    // that — the orphan routes simply prune within 30 s.
    _saveDvRouting();

    // §5.10.4 Solicited-Reply-Adoption: drop expired tracker entries
    // (no PUSH came back within the window). The handler also `remove`s
    // on first match, so this sweep only catches the no-reply case.
    final cutoff = DateTime.now().subtract(_solicitedReplyWindow);
    _outstandingPeerListWants.removeWhere((_, sentAt) => sentAt.isBefore(cutoff));
  }

  void _doPeerExchange() {
    final peers = routingTable.allPeers;
    if (peers.isEmpty) return;

    // §4.4: only exchange with confirmed peers.
    final confirmed = peers
        .where((p) => isPeerConfirmed(p.nodeIdHex))
        .toList()
      ..shuffle();
    for (final peer in confirmed.take(3)) {
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
    // Welle 5: §2.3.5 selector → INFRASTRUCTURE_FRAME path. Fire-and-forget.
    _sendInfra(
      messageType: proto.MessageTypeV3.MTV3_PEER_LIST_SUMMARY,
      innerPayload: summary.writeToBuffer(),
      recipientDeviceId: peer.nodeId,
    );
  }

  void _scheduleNetworkChange({bool force = false, void Function()? onComplete}) {
    if (_networkChangeInProgress) {
      _networkChangePending = true;
      if (force) _networkChangePendingForce = true;
      return;
    }
    _networkChangeInProgress = true;
    onNetworkChanged(force: force).whenComplete(() {
      _networkChangeInProgress = false;
      onComplete?.call();
      if (_networkChangePending) {
        _networkChangePending = false;
        final pendingForce = _networkChangePendingForce;
        _networkChangePendingForce = false;
        _scheduleNetworkChange(force: pendingForce);
      }
    });
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

    // §4.5: reset discovery gate — the cascade must re-confirm the mesh.
    _discoveryComplete = false;

    // Notify daemon/headless to re-query public IP
    onNetworkChangeDetected?.call();

    // 0. Abort any running subnet scan BEFORE reconnecting sockets — the scan
    // uses its own NativeUdpSender (FFI to WSASendTo) at 50 pps. If it runs
    // concurrently with reconnectUdpSockets(), the combined FFI burst can trip
    // the Dart VM's stack-guard on Windows (SEGFAULT, no error handler).
    localDiscovery.stopSubnetScan();

    // 0b. Deactivate mobile fallback (new network = fresh start via WiFi)
    transport.stopMobileFallback();

    // 1. Reset NAT + port mapping
    natTraversal.reset();
    await portMapper.reset();
    _portMapperPublicIpRetried = false;
    // Re-acquire port mapping in background
    portMapper.start();

    // 2. Fast discovery burst
    localDiscovery.triggerFastDiscovery();
    multicastDiscovery.triggerFastDiscovery();

    // 2b. Reconnect UDP sockets — Android invalidates sockets when the active
    // network interface changes (WiFi→mobile→WiFi). Without this, all
    // subsequent sends return 0 even though the interface is back.
    // Also reconnect the discovery socket — it suffers the same Dart IOCP
    // defect class on Windows (dead from birth or dies under load).
    await transport.reconnectUdpSockets();
    await localDiscovery.reconnectSocket();

    // 3. Update local IPs (all interfaces)
    _localIp = updatedIps.isNotEmpty ? updatedIps.first : '127.0.0.1';
    _localIps = updatedIps;
    PeerAddress.currentLocalIps = _localIps;
    _log.info('Network recovery: IPs ${updatedIps.join(", ")}');

    // 3a2. Backoff grace period: sends in the first 10s after a network
    // change often fail because the socket is still transitioning between
    // interfaces (WiFi→Mobilfunk). Without a grace period, these failures
    // poison the backoff counters and lock out the correct address.
    PeerAddress.networkChangeGraceUntil =
        DateTime.now().add(const Duration(seconds: 10));

    // 3b. Soft-reset of per-peer state (Architektur §2.7.2 / §7.6).
    // Per-address failure counters and exponential backoff are network-bound
    // and cleared outright — a peer unreachable on the old network may be
    // perfectly reachable on the new one.
    // §5.10.4: Clear accumulated unacked counters — failure evidence from the
    // old interface is void; without this, frozen counters suppress Stage-4
    // recovery against peers now reachable on the new interface.
    _unackedPacketsToPeer.clear();
    _lastMeshRefresh.clear();
    _meshRefreshGlobalBucket.clear();
    // Learned relay routes are NOT
    // cleared but marked `stale` (cost penalty +5, 30 s revalidation
    // deadline): a route that was working before the event almost always
    // still is, and the cost penalty just ensures fresh post-recovery
    // routes are preferred while the stale entry stays available as a
    // fallback. Routes that fail to revalidate within the deadline are
    // pruned by the timer below.
    for (final peer in routingTable.allPeers) {
      peer.markRelayStale();
      peer.consecutiveRouteFailures = 0;
      peer.consecutiveRelayFailures = 0;
      for (final addr in peer.addresses) {
        addr.consecutiveFailures = 0;
      }
    }

    // 3b2. Reset TLS fallback (peer stuck in TLS mode from old network would skip UDP)
    _tlsFallback.reset();

    // 3b3. Reset suspended keepalive peers — NAT context changed, give
    // unconfirmed peers another round of attempts.
    udpKeepalive.resetUnconfirmed();

    // 3b4. Keepalive address refresh: re-register each keepalive peer
    // with the best available public address. Without this, keepalive
    // stays locked to a stale private IP after switching to Mobilfunk
    // where only public IPs are reachable.
    for (final peer in routingTable.allPeers) {
      final publicAddrs = peer.allConnectionTargets()
          .where((a) => !PeerAddress.isPrivateIp(a.ip) && !a.ip.contains(':'))
          .toList();
      if (publicAddrs.isNotEmpty) {
        final best = publicAddrs.first;
        udpKeepalive.updateAddress(peer.nodeIdHex, best.ip, best.port);
      }
    }

    // 3c. DV-Routing: mark all routes as stale (cost +5, 30 s deadline)
    // instead of clearing. Topology knowledge survives transient events;
    // routes that re-confirm via PONG / DV-update lose the penalty,
    // routes that miss the deadline are pruned.
    final staleCount = dvRouting.markAllRoutesStale();
    _log.debug('Soft-reset: marked $staleCount DV-routes as stale (30s deadline)');
    _lastRouteUpdateSentTo.clear();
    _lastRouteEpochSentTo.clear();
    // F5: suppress catch-up for 15s after network change — delta propagation
    // via _flushDvUpdates still runs and ensures convergence.
    _networkChangeGraceUntil = DateTime.now().add(const Duration(seconds: 15));

    // Schedule the prune sweep for the soft-reset deadline. Routes /
    // relay-routes that did not revalidate via PONG / DV-update / Relay-
    // delivery within 30 s are dropped — replicating the prior "hard reset"
    // outcome exactly when revalidation actually fails, but only then.
    Future.delayed(const Duration(seconds: 30), () {
      if (!_running) return;
      final dropped = dvRouting.pruneStaleRoutes(const Duration(seconds: 30));
      var relayDropped = 0;
      for (final peer in routingTable.allPeers) {
        if (peer.pruneRelayIfStale(const Duration(seconds: 30))) {
          relayDropped++;
        }
      }
      if (dropped > 0 || relayDropped > 0) {
        _log.info(
            'Soft-reset prune: dropped $dropped DV-routes + $relayDropped relay-routes '
            'that did not revalidate within 30 s');
      }
    });

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

    // 4b. §4.5: Send PEER_LIST_WANT to restore _discoveryComplete after
    // network change. Step 4's PINGs produce PONGs but NOT PEER_LIST_PUSH.
    // Without this WANT, _discoveryComplete stays false → DV propagation,
    // Welcome, and Catch-Up route updates are blocked indefinitely (only
    // the 15-min maintenance timer would recover). The PUSH response
    // triggers _onDiscoveryComplete.
    {
      final wantTargets = <PeerInfo>[];
      for (final hex in _confirmedPeers.keys) {
        final peer = routingTable.getPeer(hexToBytes(hex));
        if (peer != null && !_isLocalIdentity(hex)) {
          wantTargets.add(peer);
        }
        if (wantTargets.length >= 3) break;
      }
      if (wantTargets.isEmpty) {
        for (final peer in routingTable.allPeers) {
          if (!_isLocalIdentity(peer.nodeIdHex)) {
            wantTargets.add(peer);
          }
          if (wantTargets.length >= 3) break;
        }
      }
      if (wantTargets.isNotEmpty) {
        final wantData = proto.PeerListWant();
        for (final peer in routingTable.allPeers.take(20)) {
          wantData.wantedNodeIds.add(peer.nodeId);
        }
        final wantBytes = wantData.writeToBuffer();
        _log.info('§4.5 Network change: PEER_LIST_WANT → '
            '${wantTargets.length} peers to restore discoveryComplete');
        for (final target in wantTargets) {
          for (final addr in _filterNatContext(
              target.allConnectionTargets(), target)) {
            sendInfraDirect(
              messageType: proto.MessageTypeV3.MTV3_PEER_LIST_WANT,
              innerPayload: wantBytes,
              recipientDeviceId: target.nodeId,
              addr: InternetAddress(addr.ip),
              port: addr.port,
            );
          }
          _outstandingPeerListWants[target.nodeIdHex] = DateTime.now();
        }
      }
    }

    // 5. Re-bootstrap
    await _kademliaBootstrap();

    // 5b. H-4 (§12.3 step 11): Notify service layer to re-publish Liveness
    // Record with updated addresses before we broadcast the address update.
    onAddressesChanged?.call();

    // 6. Broadcast address update
    _broadcastAddressUpdate(force: true);

    // 6a. §4.11: debounced rendezvous publish (10s) so contacts can
    // resolve our new address via Nostr after the IP changed.
    rendezvousManager?.onNetworkChanged();
    infraRendezvousManager?.onNetworkChanged();
    // §19.6.5: only republish if this device actually has something to
    // serve — an idle device with an empty BinaryFragmentStore stays
    // silent instead of emitting empty availability records on every
    // network change (Arbeitsregel #5).
    if (binaryHasContentToShare &&
        binaryRendezvousManager != null &&
        binaryRecordProvider != null) {
      binaryRendezvousManager!.onNetworkChanged(binaryRecordProvider!);
    }

    // 6b. §4.5 Discovery Cascade restart: if step 4's PINGs did not
    // re-establish connectivity (no PONG → discoveryComplete stays false),
    // the full 4-tier cascade provides structured fallback (stored peers at
    // ALL addresses → LAN → bootstrap → subnet scan). Critical for
    // WiFi→Mobilfunk transitions where step 4's PINGs went to stale LAN
    // addresses and the cascade's Tier 3 (bootstrap) is the only path.
    Future.delayed(const Duration(seconds: 3), () {
      if (!_running) return;
      if (!_discoveryComplete) {
        _log.info('Network change: no peer confirmed after 3s — restarting discovery cascade');
        _startDiscoveryCascade();
      }
    });

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
      // F2 (S123 UDP-dead RCA): gate on send-path liveness, not
      // `_confirmedPeers` (receive-only — a trickle from an unrelated peer
      // suppressed this exact fallback for 2h23min in the field even
      // though our own sends were black-holed).
      if (_outboundRecentlyConfirmed) return; // Send-path confirmed recently — no fallback needed
      if (transport.isMobileFallbackActive) return; // Already active
      _tryMobileFallback();
    });

    // 9. Proactive rendezvous: after 8s, ask any reachable peer about peers
    // that didn't re-confirm since the network change. Establishes relay
    // routes before the user sends a message → Layer-2 cascade picks them up.
    // Reduces dependency on Bootstrap as sole rendezvous point.
    // §4.11.11 trigger 2 piggy-backs here: re-resolve contacts that stayed
    // unreachable under the new network context via external rendezvous.
    Future.delayed(const Duration(seconds: 8), () {
      if (!_running) return;
      _tryProactiveRendezvous();
      requestContactResolve(reason: 'network-change');
    });

    // 10. §4.7 IPv6 Inbound Probe: if a global IPv6 is already known at the
    // time of the network change (e.g. mobile interface with SLAAC), issue a
    // fresh inbound probe. The probe is also triggered whenever
    // natTraversal.setPublicIpv6 is called externally (headless / GUI path)
    // via [probeIpv6InboundIfNeeded]. We fire here with a small delay so
    // the NAT reset (step 1) and discovery burst (step 2) have settled and
    // a confirmed peer is likely available.
    Future.delayed(const Duration(seconds: 3), () {
      if (!_running) return;
      _probeIpv6Inbound();
    });

    // 11. Zero-peer recovery loop: if after 60s still no confirmed peer,
    // periodically clear backoff and re-bootstrap. Without this, a phone
    // switching WiFi→Mobilfunk during a WAN IP rotation enters a
    // permanent deadlock: all addresses in backoff, all DV routes pruned,
    // all keepalive peers suspended — no recovery mechanism.
    _zeroPeerRecoveryTimer?.cancel();
    _zeroPeerRecoveryTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      if (!_running) { timer.cancel(); return; }
      // F2 (S123 UDP-dead RCA): stop only on confirmed send-path liveness —
      // `_confirmedPeers` (receive-only) let a Bootstrap trickle keep this
      // gate satisfied for 2h23min while the send path stayed dead.
      if (_outboundRecentlyConfirmed) {
        _log.info('Zero-peer recovery: outbound confirmed — stopping recovery loop');
        timer.cancel();
        _zeroPeerRecoveryTimer = null;
        return;
      }
      _log.info('Zero-peer recovery: still 0 confirmed peers — '
          'clearing backoff + re-bootstrap');
      for (final peer in routingTable.allPeers) {
        for (final addr in peer.addresses) {
          addr.consecutiveFailures = 0;
        }
      }
      PeerAddress.networkChangeGraceUntil =
          DateTime.now().add(const Duration(seconds: 10));
      udpKeepalive.resetUnconfirmed();
      _kademliaBootstrap();
      _startDiscoveryCascade();
    });
  }

  /// Ask any confirmed peer about peers/contacts not reconfirmed since the
  /// last network change. Establishes relay routes from the responses.
  Future<void> _tryProactiveRendezvous() async {
    if (!_confirmedPeers.values.any((ts) => DateTime.now().difference(ts) <= _confirmedPeerTtl)) return;
    final changeAt = _lastNetworkChangeAt;
    if (changeAt == null) return;

    final stale = routingTable.allPeers.where((p) {
      if (_isLocalIdentity(p.nodeIdHex)) return false;
      if (isPeerConfirmed(p.nodeIdHex)) return false;
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
        // Task #30 (Y): respect cooldown for recently-failed relays.
        if (peer.isRelayInCooldown(relayHex)) {
          _log.debug('Proactive rendezvous: ${peer.nodeIdHex.substring(0, 8)} '
              'via ${relayHex.substring(0, 8)} suppressed (cooldown)');
          return;
        }
        peer.relayViaNodeId = relayNodeId;
        peer.relaySetAt = DateTime.now();
        peer.consecutiveRelayFailures = 0;
        _log.info('Proactive rendezvous: relay learned ${peer.nodeIdHex.substring(0, 8)} '
            'via ${relayHex.substring(0, 8)}');
      });
    }
  }

  // ── §4.11.11 Reactive Resolve Triggers (V3.1.117) ───────────────────

  /// Requests a reactive rendezvous resolve for [userIdHex] (or ALL
  /// currently unreachable contacts when null).
  ///
  /// Gating (§4.11.11): unreachable filter, 15 min per-contact cooldown,
  /// 60 s batch gate. Edge-triggered by retry-exhausted, network-change+8s
  /// and discovery-complete — never by a periodic timer.
  void requestContactResolve({String? userIdHex, required String reason}) {
    final rm = rendezvousManager;
    if (rm == null || !_running) return;

    final now = DateTime.now();
    var added = 0;
    for (final c in rm.contactsSnapshot) {
      if (userIdHex != null && c.userIdHex != userIdHex) continue;
      if (_isContactReachable(c.userIdHex)) continue;
      final last = _rvResolveCooldown[c.userIdHex];
      if (last != null && now.difference(last) < _rvContactCooldown) continue;
      if (_rvPendingResolve.add(c.userIdHex)) added++;
    }
    if (added == 0) return;
    if (_rvBatchTimer != null) {
      _log.debug('§4.11.11 resolve[$reason]: $added contact(s) joined '
          'pending batch');
      return;
    }

    final lastBatch = _rvLastBatchAt;
    final sinceLast =
        lastBatch == null ? _rvBatchGate : now.difference(lastBatch);
    final wait =
        sinceLast >= _rvBatchGate ? _rvBatchCoalesce : _rvBatchGate - sinceLast;
    _log.info('§4.11.11 resolve[$reason]: $added contact(s) queued, '
        'batch in ${wait.inSeconds}s');
    _rvBatchTimer = Timer(wait, _runRvResolveBatch);
  }

  void _runRvResolveBatch() {
    _rvBatchTimer = null;
    if (!_running) return;
    _rvLastBatchAt = DateTime.now();

    // Prune awaiting-confirm entries whose PONG never came (10 min).
    _rvAwaitingConfirmAt.removeWhere((deviceHex, at) {
      final stale =
          DateTime.now().difference(at) > const Duration(minutes: 10);
      if (stale) _rvAwaitingConfirm.remove(deviceHex);
      return stale;
    });

    final rm = rendezvousManager;
    if (rm == null) {
      _rvPendingResolve.clear();
      return;
    }
    final now = DateTime.now();
    final contacts = <RendezvousContact>[];
    for (final c in rm.contactsSnapshot) {
      if (!_rvPendingResolve.contains(c.userIdHex)) continue;
      // Re-check at fire time — the contact may have come back while the
      // batch was pending.
      if (_isContactReachable(c.userIdHex)) continue;
      final last = _rvResolveCooldown[c.userIdHex];
      if (last != null && now.difference(last) < _rvContactCooldown) continue;
      contacts.add(c);
    }
    _rvPendingResolve.clear();
    if (contacts.isEmpty) return;
    unawaited(_resolveContactRendezvousFor(contacts, reason: 'reactive'));
  }

  /// A contact counts as reachable when ANY of its known devices is either
  /// recently confirmed (bidirectional UDP) or has a *recently confirmed*
  /// alive DV route.
  ///
  /// S121 field amendment: a bare `isAlive` route is NOT sufficient —
  /// relay routes without traffic are never pruned and survive for days,
  /// which suppressed the reactive Nostr resolve for genuinely offline
  /// contacts (Ingo's dead WLAN device, Eierphone during iOS suspension).
  /// The route must have been confirmed within the same TTL that governs
  /// peer confirmation.
  bool _isContactReachable(String userIdHex) {
    final devices = routingTable.getAllPeersForUserId(hexToBytes(userIdHex));
    final now = DateTime.now();
    for (final d in devices) {
      final devHex = bytesToHex(d.nodeId);
      if (isPeerConfirmed(devHex)) return true;
      if (dvRouting.routesTo(devHex).any((r) =>
          r.isAlive &&
          now.difference(r.lastConfirmed) <= _confirmedPeerTtl)) {
        return true;
      }
    }
    return false;
  }

  /// Shared Contact-Rendezvous resolve (§4.11.4): used by cascade Tier 3b
  /// (all contacts) and the §4.11.11 reactive path (filtered subset).
  /// Stamps the per-contact cooldown at attempt time and registers resolved
  /// devices for the contact-endpoint-confirmed outbox edge (§5.1).
  Future<void> _resolveContactRendezvousFor(List<RendezvousContact> contacts,
      {required String reason}) async {
    final rm = rendezvousManager;
    if (rm == null || contacts.isEmpty) return;

    final now = DateTime.now();
    for (final c in contacts) {
      _rvResolveCooldown[c.userIdHex] = now;
    }

    final deviceIds = <String, List<String>>{};
    for (final c in contacts) {
      final userIdBytes = hexToBytes(c.userIdHex);
      // Prefer cached manifest; fall back to live 2D-DHT lookup (§4.3) so
      // fresh contacts can still be resolved.
      final manifest = identityDhtHandler.getAuthManifest(userIdBytes);
      if (manifest != null) {
        deviceIds[c.userIdHex] =
            manifest.authorizedDeviceNodeIds.map(bytesToHex).toList();
      } else {
        final resolved = await identityResolver.resolve(userIdBytes);
        if (resolved.isNotEmpty) {
          deviceIds[c.userIdHex] =
              resolved.map((d) => bytesToHex(d.deviceNodeId)).toList();
        }
      }
    }

    final resolved =
        await rm.resolveContacts(contacts, contactDeviceIds: deviceIds);
    for (final ep in resolved) {
      final devHex = ep.deviceIdHex;
      if (devHex != null) {
        _rvAwaitingConfirm[devHex] = ep.contactUserIdHex;
        _rvAwaitingConfirmAt[devHex] = DateTime.now();
      }
      for (final addr in ep.addresses) {
        _sendPing(addr.ip, addr.port);
      }
    }
    if (resolved.isNotEmpty) {
      _log.info('§4.11 Contact-RV[$reason]: resolved '
          '${resolved.length} contact(s)');
    }
  }

  /// §5.1 third outbox edge: called from every peer-confirm site. If the
  /// device belongs to a contact we rendezvous-resolved, notify the service
  /// layer so the outbox can flush toward the now-reachable contact.
  void _notifyEndpointConfirmed(String deviceHex) {
    final userHex = _rvAwaitingConfirm.remove(deviceHex);
    _rvAwaitingConfirmAt.remove(deviceHex);
    if (userHex == null) return;
    _log.info('§4.11.11 contact-endpoint-confirmed: '
        '${userHex.substring(0, 8)} via device ${deviceHex.substring(0, 8)}');
    onContactEndpointConfirmed?.call(userHex);
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

    for (final altIp in alternativeIps) {
      for (final peer in probePeers) {
        // V3 InfraFrame is per-peer (KEM-encrypted under recipient's
        // Device-KEM-PK), so the probe packet is built fresh in the inner
        // loop. A KEM-PK miss yields null → skip this peer.
        final pingData = _buildPingPacket(peer.nodeId);
        if (pingData == null) continue;
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

  /// Build a raw V3 InfraFrame DHT_PING packet (HMAC-tagged wire bytes) for
  /// interface probing on a specific recipient device. Returns null on
  /// Device-KEM-PK miss — caller skips that peer.
  Uint8List? _buildPingPacket(Uint8List recipientDeviceId) {
    final ping = proto.DhtPing()
      ..senderId = primaryIdentity.deviceNodeId;
    final packet = _buildInfraPacket(
      messageType: proto.MessageTypeV3.MTV3_DHT_PING,
      innerPayload: Uint8List.fromList(ping.writeToBuffer()),
      recipientDeviceId: recipientDeviceId,
    );
    if (packet == null) return null;
    packet.nextHopDeviceId = recipientDeviceId;
    return transport.serializeWithTag(packet);
  }

  /// Change the listening port at runtime. Rebinds UDP+TLS, updates all peers.
  /// Throws SocketException if new port is unavailable.
  Future<void> changePort(int newPort) async {
    if (newPort == port) return;
    await transport.rebind(newPort);
    port = newPort;
    _log.info('Port changed to $newPort, broadcasting to peers');
    _broadcastAddressUpdate(force: true);
  }

  /// Broadcast our current address info to all peers.
  /// Called internally on network changes and externally by headless public IP polling.
  void broadcastAddressUpdate() => _broadcastAddressUpdate(force: true);

  /// §5.11 / §5.12 — Send a single firstParty self-broadcast PEER_LIST_PUSH
  /// (one entry: our own PeerInfo, carrying current Ed25519/ML-DSA + KEM PKs)
  /// to a specific recipient. Used by:
  ///   • §5.12 hot-path — answer to a DHT_PING with `pk_recovery_hint=true`.
  ///   • §5.11 new-neighbor event — fan-out to existing neighbors so the
  ///     mesh learns about a freshly-seen peer immediately.
  ///
  /// Loops over all hosted identities (Multi-Identity nodes broadcast each).
  void _pushSelfToPeer(Uint8List recipientDeviceId) {
    for (final ctx in _identities.values) {
      final pushData = proto.PeerListPush();
      pushData.peers.add(ctx.ownPeerInfo(
        localIp: _localIp,
        localPort: port,
        publicIp: _advertisedPublicIp,
        publicPort: _advertisedPublicPort,
        allLocalIps: _localIps,
        deviceEd25519PublicKey: _deviceKeys.sig.ed25519PublicKey,
        deviceMlDsaPublicKey: _deviceKeys.sig.mlDsaPublicKey,
        deviceIdPowNonce: _deviceKeys.admissionNonce,
      ).toProto(slim: true));
      _sendInfra(
        messageType: proto.MessageTypeV3.MTV3_PEER_LIST_PUSH,
        innerPayload: pushData.writeToBuffer(),
        recipientDeviceId: recipientDeviceId,
      );
    }
  }

  DateTime? _lastPushSelfBroadcast;

  /// §5.11 — broadcast self-PEER_LIST_PUSH to every neighbor *except* the
  /// given peer. Used on new-neighbor events: we tell the existing mesh
  /// about ourselves (which transitively informs them about the new edge,
  /// since our reachability has changed).
  void _pushSelfToNeighborsExcept(Uint8List excludeDeviceId) {
    // Throttle: at most once per 30s to prevent packet storms if the
    // caller fires repeatedly (e.g. stale-route revalidation race).
    final now = DateTime.now();
    if (_lastPushSelfBroadcast != null &&
        now.difference(_lastPushSelfBroadcast!).inSeconds < 30) {
      return;
    }
    _lastPushSelfBroadcast = now;

    final excludeHex = bytesToHex(excludeDeviceId);
    // §4.4: only push to confirmed peers.
    final targets = routingTable.allPeers
        .where((p) => p.nodeIdHex != excludeHex && isPeerConfirmed(p.nodeIdHex))
        .toList()
      ..shuffle();
    for (var i = 0; i < targets.length; i++) {
      if (i == 0) {
        _pushSelfToPeer(targets[i].nodeId);
      } else {
        final peer = targets[i];
        Future.delayed(
          Duration(milliseconds: 200 * i),
          () => _pushSelfToPeer(peer.nodeId),
        );
      }
    }
    if (targets.isNotEmpty) {
      _log.info('§5.11: new-peer-event → broadcasting PEER_LIST_PUSH to '
          '${targets.length} neighbors (200ms jitter)');
    }
  }

  /// §4.5: Push PeerInfo for our top-N known peers to a newly connected
  /// neighbor. The welcome ROUTE_UPDATE only carries (destination, cost) —
  /// no addresses, no userId. Without this push, the new peer would have to
  /// send PEER_LIST_WANT for every DV destination individually.
  void _pushTopNPeersToNewNeighbor(Uint8List recipientDeviceId) {
    final pushData = proto.PeerListPush();
    final recipientHex = bytesToHex(recipientDeviceId);
    var count = 0;
    for (final peer in routingTable.allPeers) {
      if (count >= 5) break;
      if (peer.nodeIdHex == recipientHex) continue;
      if (routingTable.isLocalNode(peer.nodeId)) continue;
      final route = dvRouting.bestRouteTo(peer.nodeIdHex);
      if (route == null || !route.isAlive) continue;
      pushData.peers.add(peer.toProto(gossipFilter: true));
      pushData.hopsFromSender.add(route.hopCount);
      pushData.costFromSender.add(route.cost);
      count++;
    }
    if (count > 0) {
      _sendInfra(
        messageType: proto.MessageTypeV3.MTV3_PEER_LIST_PUSH,
        innerPayload: pushData.writeToBuffer(),
        recipientDeviceId: recipientDeviceId,
      );
      _log.info('§4.5: Welcome peer-push → $count peers to '
          '${recipientHex.substring(0, 8)}');
    }
  }

  /// Initiate a port probe for an external IP (public API for daemon/headless ipify fallback).
  void probePublicPort(String externalIp) => _initiatePortProbe(externalIp);

  void _broadcastAddressUpdate({bool force = false}) {
    // Throttle: at most once per 30s unless forced (port change, startup).
    if (!force && _lastBroadcastTime != null &&
        DateTime.now().difference(_lastBroadcastTime!).inSeconds < 30) {
      _log.debug('_broadcastAddressUpdate: throttled (last ${DateTime.now().difference(_lastBroadcastTime!).inSeconds}s ago)');
      return;
    }
    _lastBroadcastTime = DateTime.now();
    // §4.4: only push to confirmed peers (direct packet in last 15 min).
    // Unconfirmed peers pull via Mesh-Refresh when they come back online.
    final peers = routingTable.allPeers
        .where((p) => isPeerConfirmed(p.nodeIdHex))
        .toList()
      ..shuffle();
    if (peers.isEmpty) {
      _log.debug('_broadcastAddressUpdate: 0 confirmed peers — skipped');
      return;
    }
    for (final ctx in _identities.values) {
      final pushData = proto.PeerListPush();
      pushData.peers.add(ctx.ownPeerInfo(
        localIp: _localIp,
        localPort: port,
        publicIp: _advertisedPublicIp,
        publicPort: _advertisedPublicPort,
        allLocalIps: _localIps,
        deviceEd25519PublicKey: _deviceKeys.sig.ed25519PublicKey,
        deviceMlDsaPublicKey: _deviceKeys.sig.mlDsaPublicKey,
        deviceIdPowNonce: _deviceKeys.admissionNonce,
      ).toProto(slim: true));
      final innerBytes = pushData.writeToBuffer();

      for (var i = 0; i < peers.length; i++) {
        final peer = peers[i];
        if (i == 0) {
          _sendInfra(
            messageType: proto.MessageTypeV3.MTV3_PEER_LIST_PUSH,
            innerPayload: innerBytes,
            recipientDeviceId: peer.nodeId,
          );
        } else {
          Future.delayed(
            Duration(milliseconds: 200 * i),
            () => _sendInfra(
              messageType: proto.MessageTypeV3.MTV3_PEER_LIST_PUSH,
              innerPayload: innerBytes,
              recipientDeviceId: peer.nodeId,
            ),
          );
        }
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

  /// Fires when the §4.5 discovery cascade completes (first PEER_LIST_PUSH
  /// with >=1 entry). Service-layer consumers use this to trigger one-shot
  /// retrieval of offline-period messages (S&F poll, DHT-fragment pull, CR
  /// rebroadcast). Edge-triggered, resets on network change.
  void Function()? onDiscoveryComplete;

  /// H-4: Called during network recovery (§12.3 step 11) so the service layer
  /// can trigger IdentityPublisher.onAddressesChanged() — re-publishes the
  /// Liveness Record with the new addresses before the address broadcast.
  void Function()? onAddressesChanged;

  PeerInfo _ownPeerInfo() {
    return primaryIdentity.ownPeerInfo(
      localIp: _localIp,
      localPort: port,
      publicIp: _advertisedPublicIp,
      publicPort: _advertisedPublicPort,
      allLocalIps: _localIps,
      deviceEd25519PublicKey: _deviceKeys.sig.ed25519PublicKey,
      deviceMlDsaPublicKey: _deviceKeys.sig.mlDsaPublicKey,
      deviceIdPowNonce: _deviceKeys.admissionNonce,
    );
  }

  // ── Persistence ────────────────────────────────────────────────────

  void _loadRoutingTable() {
    final file = File('$profileDir/routing_table.json');
    if (file.existsSync()) {
      try {
        final json = jsonDecode(file.readAsStringSync()) as List<dynamic>;
        routingTable.loadFromJson(json);
        // WIN-4: prune unreachable addresses from the persistent cache
        // (Carrier-NAT, private-IPv4-outside-local-subnet) before they
        // get used for outbound sends. Patch F prevents *new* pollution at
        // runtime; this audit cleans up entries written before Patch F
        // and addresses learned through DHT replication paths that don't
        // go through the runtime filter.
        final pruned = routingTable.auditAddresses(_localIps);
        if (pruned > 0) {
          _log.info('Routing-table audit: pruned $pruned unreachable addresses');
        }
        // Prune-protection for loaded peers: backdate lastSeen to just past
        // the findClosestPeers recent-cutoff (10 min) instead of faking
        // `now`. The touch exists ONLY so the 4h maintenance prune doesn't
        // remove loaded peers before they had a chance to respond — but
        // `lastSeen = now` also made every dead persisted peer count as
        // "recent" for 10 minutes, poisoning the recent/stale partition of
        // findClosestPeers: replicator selections right after startup went
        // to dead peers while the actually-live peer (genuinely recent via
        // _touchPeer on inbound traffic) lost the XOR race (found via D4
        // publisher self-verify MISS on VM verification, 2026-06-12).
        // Backdating keeps full prune protection (4h window) while loaded
        // peers honestly start as "stale" until they really respond.
        final loadedSeen =
            DateTime.now().subtract(const Duration(minutes: 11));
        for (final peer in routingTable.allPeers) {
          peer.lastSeen = loadedSeen;
        }
        _log.info('Loaded ${routingTable.peerCount} peers from routing table');
      } catch (e) {
        _log.warn('Failed to load routing table: $e');
      }
    }
  }

  void _saveRoutingTable() {
    try {
      _atomicWriteJson('$profileDir/routing_table.json', routingTable.toJson());
    } catch (e) {
      _log.warn('Failed to save routing table: $e');
    }
  }

  /// Load the persisted DV-table (Architektur §2.7.3).
  ///
  /// Companion to `_loadRoutingTable`: the routing table provides the
  /// *peer cache* (addresses, PKs), this provides the *topology* (direct
  /// neighbours, learned multi-hop routes, default gateway). Without
  /// loading the topology, every restart loses the Bellman-Ford state
  /// and a fresh daemon sees `peers=N` but `cascade exhausted (routes=0)`
  /// for every send until the first authenticated V3 receive from each
  /// peer rebuilds `_neighbors` from scratch — visibly fatal for nodes
  /// behind NATs whose peers expect *us* to ping first.
  ///
  /// All loaded routes are marked stale by `DvRoutingTable.loadFromJson`
  /// itself; we only need to schedule the same 30 s prune sweep that the
  /// soft-reset path uses, so routes that fail to revalidate disappear.
  void _loadDvRouting() {
    final file = File('$profileDir/dv_routing.json');
    if (!file.existsSync()) return;
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      dvRouting.loadFromJson(json);
      _log.info(
          'Loaded DV-routing: ${dvRouting.neighbors.length} neighbors, '
          '${dvRouting.routeCount} routes (all marked stale, 30s revalidation)');
      // Mirror the soft-reset prune sweep so loaded routes that nobody
      // re-confirms within 30 s are dropped — exactly as `onNetworkChanged`
      // does for live network-change events.
      Future.delayed(const Duration(seconds: 30), () {
        if (!_running) return;
        final dropped = dvRouting.pruneStaleRoutes(const Duration(seconds: 30));
        if (dropped > 0) {
          _log.info(
              'DV-routing boot prune: dropped $dropped routes that did not '
              'revalidate within 30 s');
        }
      });
    } catch (e) {
      _log.warn('Failed to load DV-routing: $e');
    }
  }

  void _saveDvRouting() {
    try {
      _atomicWriteJson('$profileDir/dv_routing.json', dvRouting.toJson());
    } catch (e) {
      _log.warn('Failed to save DV-routing: $e');
    }
  }

  void _saveConfirmedPeers() {
    try {
      final data = <String, int>{};
      for (final e in _confirmedPeers.entries) {
        if (DateTime.now().difference(e.value) <= _confirmedPeerTtl) {
          data[e.key] = e.value.millisecondsSinceEpoch;
        }
      }
      _atomicWriteJson('$profileDir/confirmed_peers.json', data);
    } catch (e) {
      _log.warn('Failed to save confirmed peers: $e');
    }
  }

  void _loadConfirmedPeers() {
    final file = File('$profileDir/confirmed_peers.json');
    if (!file.existsSync()) return;
    try {
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final e in data.entries) {
        final ts = DateTime.fromMillisecondsSinceEpoch(e.value as int);
        if (DateTime.now().difference(ts) <= _confirmedPeerTtl) {
          _confirmedPeers[e.key] = ts;
        }
      }
      _log.info('Loaded ${_confirmedPeers.length} confirmed peers from disk (warm-start hint)');
    } catch (e) {
      _log.warn('Failed to load confirmed peers: $e');
    }
  }

  /// Persist routing + DV tables NOW. Called from Android lifecycle (paused)
  /// so peer state survives process kills between maintenance ticks.
  void saveNetworkState() {
    _saveRoutingTable();
    _saveDvRouting();
    _saveConfirmedPeers();
  }

  void _loadFirstCrMailbox() {
    final file = File('$profileDir/first_cr_mailbox.json');
    if (!file.existsSync()) return;
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final entry in json.entries) {
        final list = (entry.value as List<dynamic>)
            .map((e) => _FirstCrMailboxEntry.fromJson(e as Map<String, dynamic>))
            .where((e) => !e.isExpired)
            .toList();
        if (list.isNotEmpty) _firstCrMailbox[entry.key] = list;
      }
      var total = 0;
      for (final list in _firstCrMailbox.values) total += list.length;
      _log.info('Loaded $total First-CR-Mailbox entries from disk');
    } catch (e) {
      _log.warn('Failed to load First-CR-Mailbox: $e');
    }
  }

  void _saveFirstCrMailbox() {
    try {
      final json = <String, dynamic>{};
      for (final entry in _firstCrMailbox.entries) {
        final live = entry.value.where((e) => !e.isExpired).toList();
        if (live.isNotEmpty) json[entry.key] = live.map((e) => e.toJson()).toList();
      }
      _atomicWriteJson('$profileDir/first_cr_mailbox.json', json);
    } catch (e) {
      _log.warn('Failed to save First-CR-Mailbox: $e');
    }
  }

  void _debouncedNetworkStateSave() {
    _networkStateSaveDebounce?.cancel();
    _networkStateSaveDebounce = Timer(const Duration(seconds: 10), () {
      if (!_running) return;
      saveNetworkState();
    });
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

  // ── Distance-Vector Routing (V3) ───────────────────────────────────

  /// Debounced route propagation: collects changes and sends after 2s.
  void _onDvRouteChanged(String destHex, int cost) {
    _dvPendingChanges.add(destHex);
    _dvPropagationDebounce?.cancel();
    _dvPropagationDebounce = Timer(const Duration(seconds: 2), _flushDvUpdates);
  }

  void _flushDvUpdates() {
    if (_dvPendingChanges.isEmpty) return;
    // §4.5: defer DV propagation until discovery completes — routes learned
    // during discovery come from the peer list, not from DV flooding.
    if (!_discoveryComplete) {
      _dvPropagationDebounce = Timer(const Duration(seconds: 2), _flushDvUpdates);
      return;
    }
    // V3.1.111: pass changed destinations to buildDeltaFor instead of
    // discarding the set and sending the full table via buildUpdateFor.
    final changedDests = Set<String>.from(_dvPendingChanges);
    _dvPendingChanges.clear();

    // For each neighbor an individual delta update (Split Horizon).
    // §4.4: only send to confirmed peers.
    var sent = 0;
    var heldDown = 0;
    final now = DateTime.now();
    for (final neighborHex in dvRouting.neighbors.keys) {
      if (!isPeerConfirmed(neighborHex)) continue;

      // §4.4 per-neighbor hold-down: suppress updates for 10s after last flush
      final holdUntil = _dvHoldDownUntil[neighborHex];
      if (holdUntil != null && now.isBefore(holdUntil)) {
        heldDown++;
        continue;
      }

      final entries = dvRouting.buildDeltaFor(neighborHex, changedDests);
      if (entries.isEmpty) continue;

      final peer = routingTable.getPeer(hexToBytes(neighborHex));
      if (peer == null) continue;

      _sendRouteUpdate(peer, entries);
      _lastRouteUpdateSentTo[neighborHex] = now;
      _lastRouteEpochSentTo[neighborHex] = dvRouting.routeEpoch;
      _dvHoldDownUntil[neighborHex] = now.add(_dvHoldDownDuration);
      sent++;
    }
    if (heldDown > 0) {
      // Re-schedule flush for held-down neighbors
      _dvPropagationDebounce?.cancel();
      _dvPropagationDebounce =
          Timer(_dvHoldDownDuration, _flushDvUpdates);
    }
    if (sent > 0) {
      _log.debug('DV: Flush sent delta updates to $sent neighbors '
          '(${changedDests.length} changed dests, $heldDown held-down)');
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
    // Welle 5: §2.3.5 selector → INFRASTRUCTURE_FRAME path.
    _sendInfra(
      messageType: proto.MessageTypeV3.MTV3_ROUTE_UPDATE,
      innerPayload: msg.writeToBuffer(),
      recipientDeviceId: peer.nodeId,
    );
  }

  /// Safety-Net: full route exchange with all neighbors every 1h.
  /// §5.12 cold-path — additionally piggybacks one firstParty self-broadcast
  /// PEER_LIST_PUSH per tick. With the periodic 120 s peer-exchange removed,
  /// this is the cold-path backstop ensuring every neighbor sees our current
  /// signing keys at least hourly even if no Stage-2 trigger ever fires.
  void _dvSafetyNetExchange() {
    final fullUpdate = dvRouting.buildFullUpdate();

    if (fullUpdate.isNotEmpty) {
      // §4.4: only send to confirmed peers.
      for (final neighborHex in dvRouting.neighbors.keys) {
        if (!isPeerConfirmed(neighborHex)) continue;
        final peer = routingTable.getPeer(hexToBytes(neighborHex));
        if (peer == null) continue;
        // For safety-net no Split Horizon — send all routes
        _sendRouteUpdate(peer, fullUpdate);
      }
      _log.debug('DV: Safety-net exchange sent ${fullUpdate.length} routes '
          'to ${dvRouting.neighbors.length} neighbors');
      // Update catch-up timestamps for all neighbors
      final now = DateTime.now();
      final epoch = dvRouting.routeEpoch;
      for (final neighborHex in dvRouting.neighbors.keys) {
        _lastRouteUpdateSentTo[neighborHex] = now;
        _lastRouteEpochSentTo[neighborHex] = epoch;
      }
    }

    // §5.12 cold-path — firstParty self-broadcast piggy-back. Loops every
    // hosted identity over every known peer, mirroring `_broadcastAddressUpdate`.
    if (routingTable.peerCount > 0) {
      _log.info('§5.12 cold-path: DV-safety-net firstParty self-broadcast '
          '→ ${routingTable.peerCount} peers');
      _broadcastAddressUpdate();
    }

    // §4.6 (V3.1.72) liveness heartbeat: refresh `direct-confirmed` for ALL
    // direct neighbors — incl. LAN/IPv6/same-WAN, which UdpKeepalive
    // deliberately skips — by sending a gate-bypassing direct PING (via
    // `_sendPing` → `sendInfraDirect`). A returning direct (hopCount==0)
    // PONG re-confirms the peer (§4.6). This is the SOLE periodic refresh of
    // direct-confirmed for non-NAT peers; without it, idle LAN/IPv6 contacts
    // would silently decay past the 1h TTL and the first new message to them
    // would have to fall back to relay. Jittered (150 ms/peer) to avoid a
    // burst; unconfirmed neighbors are pinged too (that is how they become
    // confirmed in the first place).
    var hbIdx = 0;
    for (final neighborHex in dvRouting.neighbors.keys) {
      final peer = routingTable.getPeer(hexToBytes(neighborHex));
      if (peer == null) continue;
      final targets = peer
          .allConnectionTargets()
          .where((a) => !a.isInBackoff && a.isReachableFromCurrentNetwork)
          .toList();
      if (targets.isEmpty) continue;
      final addr = targets.first;
      final delayMs = 150 * hbIdx++;
      Future.delayed(Duration(milliseconds: delayMs), () {
        if (!_running) return;
        _sendPing(addr.ip, addr.port);
      });
    }
    if (hbIdx > 0) {
      _log.debug('§4.6 liveness heartbeat: PINGing $hbIdx direct neighbors '
          '(150ms jitter)');
    }

    // §4.4 safety-net: piggy-back a PeerListSummary exchange so peers
    // detect stale/new entries via hash-check and pull deltas. This is
    // the periodic backstop for the event-driven _doPeerExchange() that
    // runs once at discovery-complete.
    _doPeerExchange();
  }

  /// Welcome-Update: send full route table to a newly discovered neighbor.
  /// Called 500ms after addDirectNeighbor (to let _touchPeer populate routing table).
  /// Always sends, even if our table is empty — this acts as a "hello" signal
  /// that tells the peer we (re)started and need their routes.
  void _sendWelcomeRouteUpdate(String neighborHex) {
    if (!isPeerConfirmed(neighborHex)) return;
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
    _lastRouteEpochSentTo[neighborHex] = dvRouting.routeEpoch;
    _log.info('DV: Welcome update sent ${fullUpdate.length} routes to ${neighborHex.substring(0, 8)}');
  }

  /// Catch-up: send a delta route update only if the routing table has
  /// actually changed since the last update to this neighbor.
  void _maybeSendCatchUpRouteUpdate(String neighborHex) {
    if (!isPeerConfirmed(neighborHex)) return;
    // F5-B: suppress during network-change grace period
    final grace = _networkChangeGraceUntil;
    if (grace != null && DateTime.now().isBefore(grace)) return;
    final currentEpoch = dvRouting.routeEpoch;
    final lastEpoch = _lastRouteEpochSentTo[neighborHex];
    if (lastEpoch != null && lastEpoch >= currentEpoch) return;
    // S128: throttle catch-up to prevent post-restart feedback loop
    final lastSent = _lastRouteUpdateSentTo[neighborHex];
    if (lastSent != null &&
        DateTime.now().difference(lastSent).inSeconds < 5) return;
    final peer = routingTable.getPeer(hexToBytes(neighborHex));
    if (peer == null) return;
    // F5-A: use delta with Split Horizon instead of full-table blast
    final delta = dvRouting.buildDeltaFor(
        neighborHex, dvRouting.allDestinations);
    if (delta.isEmpty) return;
    _sendRouteUpdate(peer, delta);
    _lastRouteUpdateSentTo[neighborHex] = DateTime.now();
    _lastRouteEpochSentTo[neighborHex] = currentEpoch;
    _log.info('DV: Catch-up delta sent ${delta.length} routes to ${neighborHex.substring(0, 8)} (epoch $currentEpoch)');
  }

  // ── NAT Keepalive Gate ──────────────────────────────────────────────

  /// Whether a peer at [peerIp] needs UDP keepalive to maintain a NAT
  /// pinhole. Returns false for LAN-reachable peers (no NAT involved).
  bool _needsKeepalive(String peerIp) {
    // IPv6: no NAT, but mobile carriers run stateful firewalls that drop
    // inbound UDP after 30-120s of silence. Keepalive is needed on Android/iOS.
    if (peerIp.contains(':')) {
      return Platform.isAndroid || Platform.isIOS;
    }

    // Private IPv4: same LAN or cross-subnet via local routing, no pinhole.
    if (_isPrivateIp(peerIp)) return false;

    // Public IPv4 identical to our own WAN IP: behind the same NAT,
    // no pinhole between us and this peer.
    final myPub = natTraversal.publicIpForNatContext;
    if (myPub != null && !myPub.contains(':') && peerIp == myPub) return false;

    return true;
  }

  // ── Hole Punch Success Callback ────────────────────────────────────

  void _onHolePunchSuccess(Uint8List peerNodeId, String ip, int port) {
    final peerHex = bytesToHex(peerNodeId);
    _log.info('Hole punch succeeded: ${peerHex.substring(0, 8)} at $ip:$port');

    // Bidirectional reachability confirmed — mark as confirmed peer so
    // _sendV3ViaHop can stop after first successful send (no scatter-shot).
    _confirmedPeers[peerHex] = DateTime.now();
    _notifyEndpointConfirmed(peerHex);
    if (!hasSessionConfirmedPeers) {
      hasSessionConfirmedPeers = true;
      _log.info('First session-confirmed peer: ${peerHex.substring(0, 8)}');
    }
    // §4.5: hole-punch success = first confirmed peer → disarm isolated-node retry.
    _disarmIsolatedNodeTimer();

    // Add/update punched address in peer's address list
    final peer = routingTable.getPeer(peerNodeId);
    if (peer != null) {
      // Add the punched public address with verified success
      final addr = PeerAddress(
        ip: ip,
        port: port,
        type: PeerAddress.classifyIp(ip),
      );
      addr.recordReceived();
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

  // ── IPv6 Inbound Probe (§4.7) ────────────────────────────────────────
  // A self-announced global IPv6 address is not guaranteed to be inbound-
  // reachable: mobile carriers frequently block incoming IPv6 flows while
  // allowing outbound. The probe issues ONE CPRB echo per network-join to
  // verify bidirectional reachability. On timeout the address is kept as
  // an advertise-only relay hint but excluded from Priority-3 Direct sends.
  //
  // Mechanics: identical to the existing IPv4 port probe — reuses
  // PeerReachabilityQuery with probeIp = our IPv6, handled by the same
  // _handleReachabilityQueryInfra path (which calls transport.sendPortProbe
  // via the IPv6 socket). On CPRB receipt the probe ID is resolved here and
  // natTraversal.confirmIpv6InboundReachable() is called.

  /// Pending IPv6 inbound probe: probeIdHex → ipv6Address being probed
  final Map<String, String> _pendingIpv6Probes = {};
  Timer? _ipv6ProbeTimer;

  /// Initiate a port probe after discovering external IP without port mapping.
  void _initiatePortProbe(String externalIp) {
    // Find a confirmed peer with a public IP (Internet peer) to act as prober
    final candidates = routingTable.allPeers
        .where((p) => isPeerConfirmed(p.nodeIdHex))
        .where((p) => p.publicIp.isNotEmpty && !_isPrivateIp(p.publicIp))
        .toList();

    if (candidates.isEmpty) {
      // No Internet peer available — try any confirmed peer
      // (might work if they can route to our public IP)
      final fallback = routingTable.allPeers
          .where((p) => isPeerConfirmed(p.nodeIdHex))
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

    // Send probe request to up to 2 candidates. Welle 5: §2.3.5 selector
    // → INFRASTRUCTURE_FRAME path.
    for (final prober in candidates.take(2)) {
      final query = proto.PeerReachabilityQuery(
        targetNodeId: primaryIdentity.deviceNodeId,
        queryId: probeId,
        probeIp: externalIp,
        probePort: port,
      );
      _sendInfra(
        messageType: proto.MessageTypeV3.MTV3_REACHABILITY_QUERY,
        innerPayload: query.writeToBuffer(),
        recipientDeviceId: prober.nodeId,
      );
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
  /// Dispatches to either the IPv4 port-probe handler or the IPv6 inbound
  /// probe handler depending on which pending-probe map owns the probeId.
  void _onPortProbeReceived(Uint8List probeId, InternetAddress from, int fromPort) {
    final probeIdHex = bytesToHex(probeId);

    // ── IPv6 inbound probe (§4.7) ─────────────────────────────────────
    final ipv6Addr = _pendingIpv6Probes.remove(probeIdHex);
    if (ipv6Addr != null) {
      _ipv6ProbeTimer?.cancel();
      _log.info('IPv6 inbound probe SUCCESS — $ipv6Addr:$port is reachable from outside! '
          '(probe from ${from.address}:$fromPort)');
      natTraversal.confirmIpv6InboundReachable();
      _broadcastAddressUpdate(force: true);
      return;
    }

    // ── IPv4 port probe (V3.1.33) ─────────────────────────────────────
    final externalIp = _pendingPortProbes.remove(probeIdHex);
    if (externalIp == null) {
      _log.debug('Port probe received but no pending probe for ${probeIdHex.substring(0, 8)}');
      return;
    }
    _portProbeTimer?.cancel();

    _log.info('Port probe SUCCESS — $externalIp:$port is reachable from outside! '
        '(probe from ${from.address}:$fromPort)');
    natTraversal.confirmPublicAddress(externalIp, port);
    _broadcastAddressUpdate(force: true);
  }

  /// §4.7 IPv6 Inbound Probe — verify that our self-announced global IPv6
  /// address actually accepts inbound UDP.
  ///
  /// Issued ONCE per network-join (called from [onNetworkChanged] after
  /// [natTraversal.publicIpv6] is set). If the CPRB echo arrives within
  /// 8 s → [natTraversal.confirmIpv6InboundReachable].
  /// On timeout → [natTraversal.markIpv6InboundUnreachable] so that
  /// [currentSelfAddresses] drops the address from Priority-3 Direct.
  ///
  /// No-op when:
  ///   • no global IPv6 is known (publicIpv6 == null)
  ///   • probe already passed for this address (ipv6InboundVerified == true)
  ///   • no confirmed peer available to act as echo agent
  void _probeIpv6Inbound() {
    final ipv6 = natTraversal.publicIpv6;
    if (ipv6 == null || ipv6.isEmpty) return;
    // Already confirmed for this address — no need to re-probe.
    if (natTraversal.ipv6InboundVerified == true) return;

    // Find a confirmed peer that can act as the echo agent. Prefer peers with
    // a global IPv6 address themselves (can use the IPv6 socket for the probe),
    // otherwise fall back to any confirmed peer (the peer uses whichever socket
    // transport.sendPortProbe picks for the destination address).
    final candidates = routingTable.allPeers
        .where((p) => isPeerConfirmed(p.nodeIdHex))
        .where((p) => !_isLocalIdentity(p.nodeIdHex))
        .toList();

    // Prefer peers that have a global IPv6 address themselves (more likely to
    // route via IPv6 socket to our probe address).
    final ipv6Peers = candidates
        .where((p) => p.addresses.any((a) =>
            a.type == PeerAddressType.ipv6Global &&
            a.isReachableFromCurrentNetwork))
        .toList();

    final prober = ipv6Peers.isNotEmpty ? ipv6Peers.first :
                   candidates.isNotEmpty ? candidates.first : null;
    if (prober == null) {
      _log.debug('IPv6 inbound probe: no confirmed peer available — deferring');
      return;
    }

    final probeId = SodiumFFI().randomBytes(16);
    final probeIdHex = bytesToHex(probeId);
    _pendingIpv6Probes[probeIdHex] = ipv6;

    // Ask the prober to send a CPRB to our IPv6 address. Reuses the existing
    // PeerReachabilityQuery.probeIp / probePort fields — the responder's
    // _handleReachabilityQueryInfra calls transport.sendPortProbe(ipv6, port)
    // which routes via the IPv6 socket.
    final query = proto.PeerReachabilityQuery(
      targetNodeId: primaryIdentity.deviceNodeId,
      queryId: probeId,
      probeIp: ipv6,
      probePort: port,
    );
    _sendInfra(
      messageType: proto.MessageTypeV3.MTV3_REACHABILITY_QUERY,
      innerPayload: query.writeToBuffer(),
      recipientDeviceId: prober.nodeId,
    );
    _log.info('IPv6 inbound probe sent to ${prober.nodeIdHex.substring(0, 8)} '
        'for $ipv6:$port');

    // Timeout: 8 s (generous for cross-network relay paths; §4.7 spec: "one
    // round-trip per join, no timer, no polling").
    _ipv6ProbeTimer?.cancel();
    _ipv6ProbeTimer = Timer(const Duration(seconds: 8), () {
      if (_pendingIpv6Probes.remove(probeIdHex) != null) {
        _log.info('IPv6 inbound probe TIMEOUT for $ipv6:$port');
        natTraversal.markIpv6InboundUnreachable();
        // No address-update broadcast needed: the address is still advertised
        // (relay hint), the only change is suppression from Priority-3 Direct
        // in currentSelfAddresses, which is evaluated lazily on each call.
      }
    });
  }

  /// §4.7 Public entry point: issue an IPv6 inbound probe if one has not yet
  /// completed for the current address. Called by headless.dart / main.dart /
  /// service_daemon.dart immediately after [natTraversal.setPublicIpv6].
  ///
  /// No-op when:
  ///   • probe already passed (ipv6InboundVerified == true)
  ///   • no IPv6 set yet
  ///   • no confirmed peer available (fire-and-forget — caller need not wait)
  void probeIpv6InboundIfNeeded() => _probeIpv6Inbound();

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

  static ConnectionType _connTypeFromProto(proto.ConnectionTypeProto p) {
    switch (p) {
      case proto.ConnectionTypeProto.CT_LAN_SAME_SUBNET:  return ConnectionType.lanSameSubnet;
      case proto.ConnectionTypeProto.CT_LAN_OTHER_SUBNET: return ConnectionType.lanOtherSubnet;
      case proto.ConnectionTypeProto.CT_WIFI_DIRECT:      return ConnectionType.wifiDirect;
      case proto.ConnectionTypeProto.CT_PUBLIC_UDP:       return ConnectionType.publicUdp;
      case proto.ConnectionTypeProto.CT_HOLE_PUNCH:       return ConnectionType.holePunch;
      case proto.ConnectionTypeProto.CT_RELAY:            return ConnectionType.relay;
      case proto.ConnectionTypeProto.CT_MOBILE:           return ConnectionType.mobile;
      case proto.ConnectionTypeProto.CT_MOBILE_RELAY:     return ConnectionType.mobileRelay;
    }
    // Unknown enum value (forward-compat) → default to publicUdp.
    return ConnectionType.publicUdp;
  }

  // ── Getters ────────────────────────────────────────────────────────

  String get nodeIdHex => primaryIdentity.nodeIdHex;
  String get localIp => _localIp;
  List<String> get localIps => _localIps;
  bool get isRunning => _running;

  /// Get own PeerInfo for sharing (QR code, etc.).
  PeerInfo get ownPeerInfo => _ownPeerInfo();

  // ── §4.5 Isolated-Node Re-Discovery ───────────────────────────────

  /// Arm the isolated-node retry timer for the next backoff step.
  ///
  /// Only arms when [routingTable.peerCount] == 0. In a populated mesh
  /// this is a no-op, so the timer is never live when peers exist.
  ///
  /// Backoff schedule: step 0 → 1 min, step 1 → 5 min, step 2+ → 30 min,
  /// cap 60 min. The cap means steps ≥ 2 fire at 30 min until a peer is
  /// found, never exceeding 60 min between attempts.
  void _armIsolatedNodeTimer() {
    if (!_running) return;
    if (routingTable.peerCount > 0) return; // populated mesh — never arm
    _isolatedNodeRetryTimer?.cancel();

    // Backoff: 1 min → 5 min → 30 min (capped at 60 min).
    const delaySchedule = [
      Duration(minutes: 1),
      Duration(minutes: 5),
      Duration(minutes: 30),
    ];
    const cap = Duration(minutes: 60);
    final rawDelay = _isolatedNodeRetryStep < delaySchedule.length
        ? delaySchedule[_isolatedNodeRetryStep]
        : delaySchedule.last;
    final delay = rawDelay > cap ? cap : rawDelay;

    _log.info('§4.5 Isolated-node retry: armed (step=$_isolatedNodeRetryStep, '
        'delay=${delay.inMinutes}min)');
    _isolatedNodeRetryTimer = Timer(delay, _isolatedNodeRetryTick);
  }

  /// Disarm the isolated-node retry timer. Called when the first peer is
  /// confirmed. Safe to call repeatedly — cancels only when the timer is
  /// still live.
  void _disarmIsolatedNodeTimer() {
    // Reset the backoff so a *future* isolation episode starts fresh at step 0,
    // even if the timer was not currently running.
    _isolatedNodeRetryStep = 0;
    if (_isolatedNodeRetryTimer == null) return;
    _isolatedNodeRetryTimer!.cancel();
    _isolatedNodeRetryTimer = null;
    _log.info('§4.5 Isolated-node retry: disarmed (first peer confirmed)');
  }

  /// Tick handler for the isolated-node re-discovery retry.
  ///
  /// Actions per tick (Architecture §4.5):
  ///   (a) LAN-Discovery burst (multicast + broadcast, 3×2s).
  ///   (b) Unicast re-probe of persisted WAN peer addresses from the
  ///       routing-table snapshot (public, non-private IPs only).
  ///   (c) Re-ping the cached Bootstrap addresses.
  ///
  /// After firing, the step counter advances and the timer re-arms for the
  /// next step — unless a peer was confirmed in the meantime (checked at
  /// tick entry).
  void _isolatedNodeRetryTick() {
    _isolatedNodeRetryTimer = null;
    if (!_running) return;

    // Disarm condition: a peer was confirmed while the timer was in flight.
    if (_confirmedPeers.values
        .any((ts) => DateTime.now().difference(ts) <= _confirmedPeerTtl)) {
      _log.info('§4.5 Isolated-node retry: tick skipped — peer confirmed '
          'while timer was in flight');
      return;
    }

    _log.info('§4.5 Isolated-node retry: tick step=$_isolatedNodeRetryStep');
    _isolatedNodeRetryStep++;

    // (a) LAN-Discovery burst (reuses existing fast-discovery primitives).
    try {
      localDiscovery.triggerFastDiscovery();
    } catch (e) {
      _log.debug('§4.5 localDiscovery burst error: $e');
    }
    try {
      multicastDiscovery.triggerFastDiscovery();
    } catch (e) {
      _log.debug('§4.5 multicastDiscovery burst error: $e');
    }

    // (b) Unicast re-probe of persisted WAN addresses from routing table.
    // Only public (non-private) IPs — private IPs are LAN-only and already
    // covered by the broadcast/multicast burst above.
    var wanProbes = 0;
    for (final peer in routingTable.allPeers) {
      if (_isLocalIdentity(peer.nodeIdHex)) continue;
      for (final addr in peer.allConnectionTargets()) {
        if (!_isPrivateIp(addr.ip) && addr.port > 0) {
          _sendPing(addr.ip, addr.port);
          wanProbes++;
        }
      }
    }
    if (wanProbes > 0) {
      _log.debug('§4.5 WAN re-probe: sent $wanProbes ping(s) to persisted public addresses');
    }

    // (c) Re-ping cached Bootstrap addresses.
    for (final bs in _isolatedNodeBootstrapAddrs) {
      _addBootstrapPeer(bs);
    }
    if (_isolatedNodeBootstrapAddrs.isNotEmpty) {
      _log.debug('§4.5 Bootstrap re-ping: ${_isolatedNodeBootstrapAddrs.length} address(es)');
    }

    // Re-arm for the next step (still no peer confirmed — we checked above).
    _armIsolatedNodeTimer();
  }

  // ── Shutdown ───────────────────────────────────────────────────────

  Future<void> stop() async {
    _running = false;
    _maintenanceTimer?.cancel();
    _peerExchangeTimer?.cancel();
    _dvSafetyNetTimer?.cancel();
    _dvPropagationDebounce?.cancel();
    _networkStateSaveDebounce?.cancel();
    _portProbeTimer?.cancel();
    _ipv6ProbeTimer?.cancel();
    _isolatedNodeRetryTimer?.cancel();
    _isolatedNodeRetryTimer = null;
    _zeroPeerRecoveryTimer?.cancel();
    _zeroPeerRecoveryTimer = null;
    _rvBatchTimer?.cancel();
    _rvBatchTimer = null;
    _rvPendingResolve.clear();
    _discoveryCascadeTimer?.cancel();
    _discoveryCascadeTimer = null;
    _discoveryComplete = false;
    _isolatedNodeBootstrapAddrs.clear();
    localDiscovery.stop();
    multicastDiscovery.stop();
    ackTracker.dispose();
    reachabilityProbe.dispose();
    natTraversal.dispose();
    udpKeepalive.dispose();
    _portMapperSub?.cancel();
    await portMapper.dispose();
    await peerMessageStore.dispose();
    // V3.0: kein messageQueue.dispose() mehr.
    dhtRpc.dispose();
    _saveRoutingTable();
    _saveDvRouting();
    await reputationManager.save(profileDir);
    await transport.stop();
    _log.info('Node stopped');
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

/// §4.7: True for CGNAT addresses (100.64.0.0/10, RFC 6598) and
/// DS-Lite well-known prefix (192.0.0.0/24, RFC 7335).
bool _isCgnat(String ip) {
  if (ip.startsWith('100.')) {
    final second = int.tryParse(ip.split('.')[1]) ?? 0;
    if (second >= 64 && second <= 127) return true;
  }
  return ip.startsWith('192.0.0.');
}

/// Check if two private IPs are in the same /24 subnet.
/// Same-subnet peers are directly reachable (L2); different-subnet peers may
/// be behind separate NATs. Cross-subnet routing behind the same gateway is
/// handled by the publicIp match in _filterNatContext, not here.
bool _samePrivateNetwork(String ip1, String ip2) {
  if (ip1.contains(':') || ip2.contains(':')) return false;
  final p1 = ip1.split('.');
  final p2 = ip2.split('.');
  if (p1.length != 4 || p2.length != 4) return false;
  return p1[0] == p2[0] && p1[1] == p2[1] && p1[2] == p2[2];
}

/// §5.10.4 Mesh-Refresh internal candidate record. Pairs a peer's deviceId
/// with the cost of the best DV route to it, so the WANT-burst can be
/// dispatched cheapest-first.
class _MeshRefreshCandidate {
  final Uint8List deviceId;
  final int cost;
  const _MeshRefreshCandidate(this.deviceId, this.cost);
}

/// Relay dedup cache: prevents the same relayed packet from being forwarded
/// more than once (§3.7.3 relay dedup). TTL-based eviction + LRU cap.
class RelayDedupCache {
  final int maxSize;
  final Duration ttl;
  final LinkedHashMap<String, DateTime> _cache = LinkedHashMap();

  RelayDedupCache({this.maxSize = 2048, this.ttl = const Duration(seconds: 30)});

  bool isDuplicate(String packetHash) {
    final cutoff = DateTime.now().subtract(ttl);
    _cache.removeWhere((_, t) => t.isBefore(cutoff));
    if (_cache.containsKey(packetHash)) return true;
    _cache[packetHash] = DateTime.now();
    if (_cache.length > maxSize) _cache.remove(_cache.keys.first);
    return false;
  }

  int get length => _cache.length;
}

/// Duplicate-frame cache (§2.4 step [3b]): drops byte-identical replays of
/// HMAC-valid NetworkPacketV3 frames. Keyed on the networkTag (the HMAC
/// covers the full packet incl. timestampMs). TTL 120s = 2× the ±60s
/// timestamp window — covers a frame first seen at ts-60s whose replay
/// stays inside the window until ts+60s. Entries are never refreshed on
/// hit, so insertion order == timestamp order and expiry eviction can pop
/// from the front in amortized O(1) (this sits in the per-packet hot path).
class FrameDedupCache {
  final int maxSize;
  final Duration ttl;
  final LinkedHashMap<String, DateTime> _cache = LinkedHashMap();

  FrameDedupCache({this.maxSize = 8192, this.ttl = const Duration(seconds: 120)});

  /// Returns true (= drop) if [frameTag] was already seen within [ttl];
  /// records it otherwise. LRU cap bounds memory under flood — eviction can
  /// re-open the replay window for evicted frames, which is acceptable
  /// because the flood itself is HMAC-gated, attributable and rate-limited.
  bool isDuplicate(String frameTag) {
    final now = DateTime.now();
    final cutoff = now.subtract(ttl);
    while (_cache.isNotEmpty && _cache.values.first.isBefore(cutoff)) {
      _cache.remove(_cache.keys.first);
    }
    if (_cache.containsKey(frameTag)) return true;
    _cache[frameTag] = now;
    if (_cache.length > maxSize) _cache.remove(_cache.keys.first);
    return false;
  }

  int get length => _cache.length;
}

/// §5.5b First-CR-Mailbox entry stored on a seed peer until the target
/// device comes online and retrieves it.
class _FirstCrMailboxEntry {
  final Uint8List recipientDeviceId;
  final Uint8List senderDeviceId;
  final Uint8List encryptedCrBlob;
  final DateTime storedAt;
  final Duration ttl;

  _FirstCrMailboxEntry({
    required this.recipientDeviceId,
    required this.senderDeviceId,
    required this.encryptedCrBlob,
    required this.storedAt,
    required this.ttl,
  });

  bool get isExpired => DateTime.now().isAfter(storedAt.add(ttl));

  String get dedupKey =>
      '${bytesToHex(senderDeviceId)}:${bytesToHex(recipientDeviceId)}';

  Map<String, dynamic> toJson() => {
    'recipientDeviceId': base64Encode(recipientDeviceId),
    'senderDeviceId': base64Encode(senderDeviceId),
    'encryptedCrBlob': base64Encode(encryptedCrBlob),
    'storedAtMs': storedAt.millisecondsSinceEpoch,
    'ttlMs': ttl.inMilliseconds,
  };

  factory _FirstCrMailboxEntry.fromJson(Map<String, dynamic> j) =>
      _FirstCrMailboxEntry(
        recipientDeviceId: base64Decode(j['recipientDeviceId'] as String),
        senderDeviceId: base64Decode(j['senderDeviceId'] as String),
        encryptedCrBlob: base64Decode(j['encryptedCrBlob'] as String),
        storedAt: DateTime.fromMillisecondsSinceEpoch(j['storedAtMs'] as int),
        ttl: Duration(milliseconds: j['ttlMs'] as int),
      );
}
