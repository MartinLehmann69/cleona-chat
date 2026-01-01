// 2D-DHT Identity Resolution: Publisher-Side
//
// Pro Identitaet ein Instance. Owns Auth + Liveness Publish-Schedule:
//   - Cold-Start Wait (mind. 5 Peers, max 30s, sonst 60s Retry).
//   - Auth-Manifest Publish bei Start + alle 20h Refresh (TTL 24h).
//   - Liveness-Refresh alle 15min (foreground) bzw. 1h (background).
//   - Skip-on-no-change: keine Republish-Spam wenn Adressen gleich + nicht
//     im letzten 20% des TTL-Fensters.
//   - Address-Flap-Debounce: 3 schnelle Adressaenderungen binnen 5s
//     resultieren in genau einem Republish.
//   - Multi-Identity-Staffelung: `livenessInitialOffset = i * (period / N)`.
//
// Plan-Referenz:
//   docs/superpowers/plans/2026-04-26-2d-dht-identity-resolution.md
//   - Task 10 Step 10.3 (Hauptcode + Cold-Start + Auth-Publish)
//   - Task 11 (Liveness-Refresh + Skip-on-no-change + Address-Flap-Debounce —
//     Logik schon in Task 10 enthalten, plus @visibleForTesting Hook)
//   - Task 12 (seq-Recovery integration ueber IdentityContext.recoverAuthSeq —
//     Helfer existiert bereits in identity_context.dart, hier nichts zu tun.)

import 'dart:async';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/dht/kbucket.dart';
import 'package:cleona/core/identity_resolution/auth_manifest.dart';
import 'package:cleona/core/identity_resolution/device_kem_record.dart';
import 'package:cleona/core/identity_resolution/identity_dht_handler.dart';
import 'package:cleona/core/identity_resolution/liveness_record.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/core/node/identity_context.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;
import 'package:meta/meta.dart';

/// Sender contract for IdentityPublisher (Welle 2A V3-direct refactor).
///
/// Concrete implementation in `cleona_service.dart::_IdentityPublisherSender`
/// delegates to `CleonaNode.sendInfraTo(...)`. Tests provide their own
/// in-memory mocks. The contract takes the V3 message type and inner
/// payload bytes; serialization to `NetworkPacketV3` happens downstream.
abstract class IdentityPublisherSender {
  Future<void> send(
      proto.MessageTypeV3 messageType, Uint8List payload, PeerInfo peer);
}

/// Pro Identitaet ein Instance. Owns Auth + Liveness Publish-Schedule.
class IdentityPublisher {
  final IdentityContext identity;
  final RoutingTable routingTable;

  /// V3-direct sender contract (Welle 2A): `(MessageTypeV3, payload, peer)`.
  /// Production wiring is `_IdentityPublisherSender` in cleona_service.dart;
  /// tests inject simple in-memory recorders.
  final IdentityPublisherSender sender;

  /// D4 (§4.3 Publisher self-verify): request/response channel for the
  /// post-publish self-lookup. Production wiring is `CleonaNode.dhtRpc`
  /// (shape: `Future<DhtRpcResponse?> sendAndWait(MTV3, body, peer)`); kept
  /// `dynamic` so test mocks don't implement DhtRpc's full surface — same
  /// pattern as `IdentityResolver.dhtRpc`. Null → self-verify skipped.
  final dynamic dhtRpc;

  /// D4 observability hook: fired once per self-verify cycle with the
  /// outcome. Production wiring increments the
  /// `idSelfVerifyOk`/`idSelfVerifyMiss` network-stats counters.
  void Function(bool ok)? onSelfVerifyResult;

  // Adaptive TTL config
  static const Duration foregroundLiveTtl = Duration(minutes: 15);
  static const Duration backgroundLiveTtl = Duration(hours: 1);
  static const Duration authTtl = Duration(hours: 24);
  static const Duration authRefreshInterval = Duration(hours: 20);

  // Device-KEM-Record (Welle 5, §3.5b + §4.3): TTL auf 7 Tage angehoben, um
  // das Mailbox/S&F-Retention-Fenster zu matchen — ein bis zu 7 Tage offline
  // gegangener Kontakt bleibt KEM-aufloesbar, sodass ein Deferred-KEX-First-CR
  // (§8.1.1) noch verschluesselt und die First-CR-Mailbox (§5.5b) befuellt
  // werden kann. KEM-PK aendert sich nur bei Device-Key-Reset (Multi-Year),
  // daher ist die laengere TTL + seltenerer Republish traffic-negativ.
  static const Duration deviceKemTtl = Duration(days: 7);
  static const Duration deviceKemRefreshInterval = Duration(days: 3);

  // K=10 closest. effectiveK = min(K, peerCount) at publish time.
  static const int targetK = 10;
  // Soft preference: wait this long for peerCount to reach `peerThreshold`
  // before publishing. After `coldStartTimeout`, publish with whatever peers
  // we have (>=1) and re-publish on every peer-join until threshold is hit.
  // peerThreshold is no longer a hard gate — small networks (LAN, 2-node
  // tests) MUST be able to publish AuthManifest/DeviceKemRecord, otherwise
  // identity resolution stalls indefinitely (§3.4/§3.5b/§4.3).
  static const int peerThreshold = 5;
  static const Duration coldStartTimeout = Duration(seconds: 30);
  static const Duration coldStartRetry = Duration(seconds: 60);
  static const Duration addressFlapDebounce = Duration(seconds: 5);

  /// D4 (§4.3): delay between Auth-publish and the one self-verify lookup —
  /// lets the replicator stores land before we probe them.
  static const Duration selfVerifyDelay = Duration(seconds: 10);

  bool _foreground = true;
  bool _running = false;
  Timer? _liveTimer;
  Timer? _authTimer;
  Timer? _kemTimer;
  Timer? _coldStartRetryTimer;
  // True once the initial coldStartTimeout window has elapsed. Switches the
  // peer-join wakeup gate from "peerThreshold reached" to "any peer
  // available" — see `onPeerJoined()` and `_waitForPeersThenPublish()`.
  bool _coldStartTimedOut = false;
  // D4: one-shot self-verify per Auth-publish cycle. The timer is replaced
  // on every new publish cycle and cancelled on stop().
  Timer? _selfVerifyTimer;
  AuthManifest? _lastAuthManifest;
  DateTime? _lastPublishedAt;
  List<proto.PeerAddressProto> _lastPublishedAddrs =
      const <proto.PeerAddressProto>[];
  Timer? _addressFlapDebounceTimer;

  /// Initial-Offset fuer Multi-Identity-Staffelung: i * (period / N).
  /// Gesetzt vom Owner (CleonaService) bevor `start()` gerufen wird, sodass
  /// N Identitaeten ihre Liveness-Refreshes auf der Zeitachse staffeln statt
  /// alle gleichzeitig zu feuern. Default: keine Staffelung.
  Duration livenessInitialOffset = Duration.zero;

  /// Test-Hook: ueberschreibt `_currentAddresses()` damit Smoke-Tests Adressen
  /// injizieren koennen ohne Transport/NAT zu instanziieren.
  List<proto.PeerAddressProto> Function()? _addressProviderHook;

  /// Welle 5 (§3.5b): liefert die Device-KEM-Pubkeys (X25519 + ML-KEM-768)
  /// fuer den DeviceKemRecord-Publish. Kommt in Welle 5 Teil 2 aus
  /// `lib/core/crypto/device_kem.dart` (Subagent A) — bis dahin Hook-injiziert.
  /// Returnt `null` wenn der Caller den KEM-Keypair noch nicht initialisiert
  /// hat; Publisher skipped dann den DeviceKemRecord-Publish.
  ({Uint8List x25519Pk, Uint8List mlKemPk})? Function()? _deviceKemPkProvider;

  /// Diagnostic logger for publish lifecycle (cold-start window, peer-join
  /// re-publish triggers, KEM-publish dispatch). Goes to the per-identity
  /// log so multi-identity setups are individually observable.
  ///
  /// 2026-05-08 diagnostic wave: switched from `late final` to constructor-
  /// initialised so the per-identity buffer entry exists immediately, even
  /// if no other code path on this publisher ever fires `_log.{info,warn,…}`.
  /// Without this, a missing publisher log line is ambiguous between
  /// "publisher never started" and "publisher started but logger was
  /// lazy-uninitialised". Eager init removes the second branch.
  final CLogger _log;

  /// Local DHT-Handler — receives a self-store of every published record so
  /// own-publishes are retrievable by the local resolver and by any peer
  /// asking via `MTV3_IDENTITY_*_RETRIEVE`. Without this, the publisher
  /// only sends records to the k-closest *other* peers; in a 2-node setup
  /// where the publisher itself IS the closest peer to the dht-key, no
  /// node would have the record stored after the publish (replicators ask
  /// us, we don't have it because we never stored our own — the §4.3
  /// "publish goes to k-closest peers" semantics implicitly include the
  /// publisher when it ranks among the k-closest, which Kademlia does by
  /// convention; making the self-store explicit avoids the silent gap).
  final IdentityDhtHandler? dhtHandler;

  IdentityPublisher({
    required this.identity,
    required this.routingTable,
    required this.sender,
    this.dhtHandler,
    this.dhtRpc,
  }) : _log = CLogger.get('publisher', profileDir: identity.profileDir) {
    // 2026-05-08 diagnostic wave: emit an "alive" marker at construction
    // time so every newly-instantiated publisher leaves a trace in the
    // per-identity log. This is the topmost diagnostic — if THIS line is
    // missing for an identity, the publisher object was never created
    // (cleona_service.dart:705 path skipped or threw silently).
    _log.info('IdentityPublisher constructed for "${identity.displayName}" '
        '(userId=${bytesToHex(identity.userId).substring(0, 8)}, '
        'deviceNodeId=${bytesToHex(identity.deviceNodeId).substring(0, 8)})');
  }

  void setForeground(bool foreground) {
    _foreground = foreground;
    // Re-schedule timer with new period when running.
    if (_running) {
      _liveTimer?.cancel();
      _scheduleLiveness(initialDelay: _livenessRefreshInterval());
    }
  }

  Duration _livenessRefreshInterval() =>
      _foreground ? foregroundLiveTtl : backgroundLiveTtl;

  /// Startet den Publisher: wartet auf >= peerThreshold Peers (max
  /// coldStartTimeout), publisht dann Auth-Manifest und scheduled Liveness +
  /// Auth-Refresh-Timer. Gibt erst zurueck wenn der initiale Auth-Publish
  /// abgeschlossen ist (oder die Wait-Phase mit Cold-Start-Retry geparkt
  /// wurde — dann Future kommt zurueck, der Retry laeuft im Hintergrund).
  Future<void> start() async {
    // 2026-05-08 diagnostic wave: trace start() entry + state.
    _log.info('start() called: _running=$_running, '
        'peerCount=${routingTable.peerCount}, threshold=$peerThreshold');
    if (_running) return;
    _running = true;
    await _waitForPeersThenPublish();
  }

  void stop() {
    _running = false;
    _liveTimer?.cancel();
    _authTimer?.cancel();
    _kemTimer?.cancel();
    _coldStartRetryTimer?.cancel();
    _addressFlapDebounceTimer?.cancel();
    _selfVerifyTimer?.cancel();
    _coldStartTimedOut = false;
  }

  /// Wird von CleonaNode/Discovery aufgerufen wenn ein neuer Peer in die
  /// Routing-Table kommt. Weckt einen geparkten Cold-Start sofort auf, sobald
  /// peerThreshold erreicht ist — oder nach abgelaufenem coldStartTimeout
  /// auch mit einem einzigen verfuegbaren Peer (small-network fallback).
  ///
  /// Nach erfolgtem Erst-Publish: triggert ein Re-Publish solange peerCount
  /// noch unter peerThreshold ist, damit jeder neue Peer eine Replica
  /// abbekommt — die `findClosestPeers(targetK)`-Auswahl haengt von der
  /// aktuellen Routing-Table ab; ohne Re-Publish bliebe ein spaeter
  /// dazustossender Peer ohne lokale Replica.
  void onPeerJoined() {
    if (!_running) return;
    // 2026-05-08 diagnostic wave: every peer-join hits this path. Trace
    // the gating decision so we can correlate Bootstrap-peer-arrival
    // timestamps in `[node]` with the publisher's wakeup decision in
    // `[publisher]`.
    _log.info('onPeerJoined: peerCount=${routingTable.peerCount}, '
        'retryTimerParked=${_coldStartRetryTimer != null}, '
        'coldStartTimedOut=$_coldStartTimedOut, '
        'lastPublishedAt=${_lastPublishedAt != null}');
    if (_coldStartRetryTimer != null) {
      // Cold-start retry-loop is parked. Wake it up if we now have enough
      // peers OR (small-network fallback) we have at least 1 peer and the
      // initial cold-start window has already elapsed.
      final reachedThreshold = routingTable.peerCount >= peerThreshold;
      final smallNetworkReady = routingTable.peerCount >= 1 &&
          _coldStartTimedOut;
      if (reachedThreshold || smallNetworkReady) {
        _log.info('onPeerJoined: waking parked retry — '
            'reachedThreshold=$reachedThreshold, '
            'smallNetworkReady=$smallNetworkReady');
        _coldStartRetryTimer?.cancel();
        _coldStartRetryTimer = null;
        Future.microtask(_publishAuthAndStartLiveness);
        return;
      }
    } else if (_lastPublishedAt != null &&
        routingTable.peerCount > 0 &&
        routingTable.peerCount <= peerThreshold) {
      // Already published once but still under threshold — re-publish so the
      // newly-joined peer ends up in `findClosestPeers(targetK)` selection
      // and gets its own replica. Skip-on-no-change in `_publishLivenessNow`
      // protects against churn; AuthManifest/DeviceKem republish goes through
      // the regular refresh timers, but we kick a Liveness-burst now.
      Future.microtask(() => _publishLivenessNow(forceBypassSkip: true));
    }
    // Cold-Start-Wait laeuft synchron in `_waitForPeersThenPublish` — der
    // sieht den Threshold-Hit (oder den Small-Network-Fallback) selbst
    // beim naechsten 100ms-Tick.
  }

  /// Wird vom NetworkChangeHandler aufgerufen wenn lokale Adressen wechseln
  /// (z.B. WiFi -> Mobilfunk, neue Public-IP via STUN/UPnP). Debounced 5s,
  /// dann genau ein Liveness-Republish. Der Debounce-Trigger umgeht
  /// `_skipBecauseNoChange` — der Caller hat explizit signalisiert dass sich
  /// etwas geaendert hat, also vertrauen wir dem Signal auch wenn unsere
  /// Adress-Liste in `_currentAddresses()` (race-bedingt) noch alt aussieht.
  void onAddressesChanged() {
    if (!_running) return;
    _addressFlapDebounceTimer?.cancel();
    _addressFlapDebounceTimer = Timer(addressFlapDebounce, () {
      _publishLivenessNow(forceBypassSkip: true);
    });
  }

  /// Test-Hook: triggert `_publishLivenessNow()` direkt aus Smoke-Tests, ohne
  /// `Timer`-Wartezeit. Nicht in Produktion verwenden — Skip-on-no-change
  /// und Debounce-Logik laufen normal.
  @visibleForTesting
  Future<void> publishLivenessNowForTest() async => _publishLivenessNow();

  /// Test-Hook: triggert `_publishAuthAndStartLiveness()` direkt. Wird vom
  /// Cold-Start-Test verwendet wo das `start()`-Future bereits zurueckgekehrt
  /// ist (Cold-Start-Retry geparkt) bevor 5 Peers verfuegbar waren.
  @visibleForTesting
  Future<void> publishAuthAndStartLivenessForTest() async =>
      _publishAuthAndStartLiveness();

  /// Test-/Phase-5-Hook: injiziert `_currentAddresses()`-Quelle. Default-
  /// Skeleton liefert leere Liste; Phase 5 wired das gegen
  /// `transport.localAddresses + nat.publicAddresses`.
  void setAddressProvider(List<proto.PeerAddressProto> Function() hook) {
    _addressProviderHook = hook;
  }

  /// Welle 5 (§3.5b): injiziert die Device-KEM-Pubkeys-Quelle fuer
  /// `_publishDeviceKemNow()`. CleonaService verdrahtet das in Welle 5 Teil 2
  /// gegen `DeviceKem.x25519Pk + DeviceKem.mlKemPk` (Subagent-A-Klasse).
  /// Wenn nicht gesetzt, wird der DeviceKemRecord-Publish silent geskippt.
  void setDeviceKemPkProvider(
      ({Uint8List x25519Pk, Uint8List mlKemPk})? Function() hook) {
    _deviceKemPkProvider = hook;
  }

  /// Test-Hook: triggert `_publishDeviceKemNow()` direkt aus Smoke-Tests.
  @visibleForTesting
  Future<void> publishDeviceKemNowForTest() async => _publishDeviceKemNow();

  Future<void> _waitForPeersThenPublish() async {
    // 2026-05-08 diagnostic wave: trace each entry into the cold-start
    // state machine + the branch decision so the "publisher never
    // publishes" investigation can pinpoint exactly which branch is
    // taken (or where the await hangs).
    _log.info('_waitForPeersThenPublish entry: peerCount='
        '${routingTable.peerCount}, threshold=$peerThreshold, '
        'coldStartTimedOut=$_coldStartTimedOut');
    // §3.4/§3.5b — Small-network semantics: publish as soon as ANY peer is
    // available. `peerThreshold` is no longer a hard gate (waiting for it
    // would stall identity resolution indefinitely on small LANs / 2-node
    // test setups, as the old code did). Instead:
    //
    //   1. If at least 1 peer is reachable → publish now. The selection
    //      `findClosestPeers(targetK)` returns `min(K, available)` peers,
    //      so a single-peer publish is well-defined.
    //   2. Subsequent peer-joins trigger a re-publish via `onPeerJoined()`
    //      until `peerCount >= peerThreshold`, ensuring late-arriving peers
    //      also receive a replica (so the eventual K-closest set is fully
    //      populated even if the publisher started from cold-zero).
    //   3. Discovery-burst grace: brief 1-second poll loop lets the
    //      multicast-discovery burst (up to ~5 peers in <1s on a healthy
    //      LAN, see lan_discovery.dart§burstInterval=2s) land before the
    //      first publish, avoiding 5 micro-publishes when one suffices.
    //   4. If after `coldStartTimeout` (30s) still no peer is reachable
    //      → schedule a retry timer; `onPeerJoined()` also wakes us.
    if (routingTable.peerCount >= peerThreshold) {
      _log.info('threshold path: peerCount >= threshold at entry');
      await _publishAuthAndStartLiveness();
      return;
    }
    // Phase 1: short discovery-burst grace.
    const Duration burstGrace = Duration(seconds: 1);
    final burstDeadline = DateTime.now().add(burstGrace);
    while (DateTime.now().isBefore(burstDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!_running) return;
      if (routingTable.peerCount >= peerThreshold) {
        await _publishAuthAndStartLiveness();
        return;
      }
    }
    // After the grace period: publish if any peer is present.
    if (routingTable.peerCount >= 1) {
      _log.info('post-burst path: peerCount >= 1 after grace');
      _coldStartTimedOut = true;
      await _publishAuthAndStartLiveness();
      return;
    }
    // Phase 2: still zero peers. Wait the longer cold-start window for
    // someone — anyone — to appear.
    _log.info('phase-2 entry: zero peers after burst, '
        'waiting up to ${(coldStartTimeout - burstGrace).inSeconds}s');
    final deadline = DateTime.now().add(coldStartTimeout - burstGrace);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!_running) return;
      if (routingTable.peerCount >= 1) {
        _log.info('phase-2 wakeup: peer arrived during cold-start window');
        _coldStartTimedOut = true;
        await _publishAuthAndStartLiveness();
        return;
      }
    }
    // Cold-start window fully elapsed and still nobody. Schedule retry.
    _log.info('cold-start window elapsed with 0 peers — scheduling retry '
        'in ${coldStartRetry.inSeconds}s');
    _coldStartTimedOut = true;
    _coldStartRetryTimer = Timer(coldStartRetry, () {
      _coldStartRetryTimer = null;
      if (!_running) return;
      _waitForPeersThenPublish();
    });
  }

  Future<void> _publishAuthAndStartLiveness() async {
    if (!_running) return;
    _log.info('publish-cycle starting (peerCount=${routingTable.peerCount}, '
        'coldStartTimedOut=$_coldStartTimedOut)');
    final seq = identity.bumpAuthManifestSeq();
    await identity.persistIdentityResolutionState();
    final manifest = AuthManifest.sign(
      identity,
      <Uint8List>[identity.deviceNodeId],
      ttlSeconds: authTtl.inSeconds,
      sequenceNumber: seq,
    );
    await _broadcastAuthManifest(manifest);
    // D4 (§4.3 Publisher self-verify): exactly ONE delayed self-lookup per
    // Auth-publish cycle. A new cycle replaces a still-pending timer.
    _lastAuthManifest = manifest;
    _selfVerifyTimer?.cancel();
    _selfVerifyTimer = Timer(selfVerifyDelay, () {
      _selfVerifyTimer = null;
      unawaited(_selfVerifyAuth(manifest));
    });
    _scheduleAuthRefresh();
    _scheduleLiveness(initialDelay: livenessInitialOffset);
    // Ersten Liveness-Publish sofort nach dem Auth durchziehen (dasselbe
    // closest-Set, kein Doppel-Schedule). Wenn `livenessInitialOffset > 0`
    // gilt nur das Refresh-Tempo, der Bootstrap-Publish soll noch JETZT raus,
    // sonst entsteht ein Adress-Loch zwischen Start und erstem Tick.
    await _publishLivenessNow();
    // Welle 5 (§3.5b + §4.3): Device-KEM-Record gleich mit publishen — derselbe
    // Trust-Anchor (User-Master-Ed25519-Sig), aber eigener Key-Space ("kem").
    // Skipped wenn Provider nicht gesetzt (Subagent-A-Wiring noch offen).
    await _publishDeviceKemNow();
    _scheduleDeviceKemRefresh();
  }

  Future<void> _broadcastAuthManifest(AuthManifest m) async {
    // Self-store first so the local DhtHandler can answer RETRIEVE requests
    // immediately — including those from peers who learned of us via
    // discovery and want to pick us as their k-closest replicator. Without
    // this, a 2-node setup stalls because the only candidate replicator (us)
    // doesn't have the record we just published.
    dhtHandler?.handleAuthPublish(m);
    final authKey = _authKey(identity.userId);
    // D4 (§4.3): subnet-diverse replicator selection — eclipse cost binding.
    final closest = routingTable.findClosestPeers(authKey,
        count: targetK,
        maxPerIpGroup: RoutingTable.diversityMaxPerIpGroup);
    final payload = Uint8List.fromList(m.toProto().writeToBuffer());
    for (final peer in closest) {
      // V3-direct: sender (CleonaNode.sendInfraTo) wraps in
      // InfrastructureFrameV3 with Outer Device-Sig + KEM-AEAD. The §2.3.5
      // selector (cleona_node.isInfrastructureMessageTypeV3) lists
      // MTV3_IDENTITY_AUTH_PUBLISH so the infra path applies.
      try {
        await sender.send(
            proto.MessageTypeV3.MTV3_IDENTITY_AUTH_PUBLISH, payload, peer);
      } catch (_) {
        // Fire-and-forget; replication factor toleriert einzelne Fehler.
      }
    }
  }

  void _scheduleAuthRefresh() {
    _authTimer?.cancel();
    _authTimer = Timer(authRefreshInterval, () async {
      if (!_running) return;
      await _publishAuthAndStartLiveness();
    });
  }

  /// D4 (§4.3 Publisher self-verify): one self-lookup per Auth-publish
  /// cycle. Fans `IDENTITY_AUTH_RETRIEVE` out to the current K-closest
  /// replicators — deliberately BYPASSING the local self-store (asking the
  /// local DhtHandler would trivially succeed). Pass: >= 1 response carries
  /// the manifest at the just-published seq (or newer — a refresh may have
  /// raced). Miss: warn + exactly ONE re-publish to a freshly computed
  /// replicator set; edge-triggered, no retry timer.
  ///
  /// Honest limitation (documented §4.3): a replicator that serves the
  /// publisher but censors third parties is indistinguishable from an
  /// honest one here — the structural defense is the subnet-diverse
  /// selection.
  Future<void> _selfVerifyAuth(AuthManifest published) async {
    if (!_running) return;
    if (dhtRpc == null) {
      _log.debug('D4 self-verify skipped: no dhtRpc wired');
      return;
    }
    final authKey = _authKey(identity.userId);
    final closest = routingTable.findClosestPeers(authKey,
        count: targetK,
        maxPerIpGroup: RoutingTable.diversityMaxPerIpGroup);
    if (closest.isEmpty) {
      // No remote replicators — nothing the publish could have landed on;
      // not a censorship signal, so no miss counter.
      _log.debug('D4 self-verify skipped: no replicators known');
      return;
    }

    final body = Uint8List.fromList(
        (proto.IdentityAuthRetrieveRequest()..userId = identity.userId)
            .writeToBuffer());
    var confirmed = 0;
    var responded = 0;
    await Future.wait(closest.map((peer) async {
      try {
        final response = await dhtRpc.sendAndWait(
            proto.MessageTypeV3.MTV3_IDENTITY_AUTH_RETRIEVE, body, peer);
        if (response == null) return;
        if (response.type !=
            proto.MessageTypeV3.MTV3_IDENTITY_AUTH_RESPONSE) {
          return;
        }
        responded++;
        final m = AuthManifest.fromProto(
            proto.AuthManifestProto.fromBuffer(response.payload));
        if (_bytesEqual(m.userId, identity.userId) &&
            m.sequenceNumber >= published.sequenceNumber) {
          confirmed++;
        }
      } catch (_) {
        // Per-peer failures squashed — a single bad replicator must not
        // fail the verify; the aggregate decides.
      }
    }));

    if (confirmed > 0) {
      _log.info('D4 self-verify OK: $confirmed/${closest.length} replicators '
          'serve AuthManifest seq>=${published.sequenceNumber}');
      onSelfVerifyResult?.call(true);
      return;
    }
    _log.warn('D4 self-verify MISS: 0/${closest.length} replicators serve '
        'AuthManifest seq=${published.sequenceNumber} '
        '($responded responded) — one re-publish to fresh set');
    onSelfVerifyResult?.call(false);
    if (!_running) return;
    // Exactly one re-publish (same record, no seq bump) to a freshly
    // computed diverse replicator set. NOT followed by another self-verify —
    // the next regular publish cycle verifies again.
    await _broadcastAuthManifest(published);
  }

  /// Test-Hook: triggert den D4-Self-Verify direkt, ohne Timer-Wartezeit.
  /// `manifest` default: der zuletzt publizierte.
  @visibleForTesting
  Future<void> selfVerifyAuthNowForTest({AuthManifest? manifest}) async {
    final m = manifest ?? _lastAuthManifest;
    if (m == null) return;
    await _selfVerifyAuth(m);
  }

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _scheduleLiveness({Duration? initialDelay}) {
    _liveTimer?.cancel();
    final delay = initialDelay ?? _livenessRefreshInterval();
    _liveTimer = Timer(delay, () async {
      if (!_running) return;
      await _publishLivenessNow();
      _scheduleLiveness(); // next tick
    });
  }

  Future<void> _publishLivenessNow({bool forceBypassSkip = false}) async {
    if (!_running) return;
    final addrs = _currentAddresses();
    if (!forceBypassSkip && _skipBecauseNoChange(addrs)) {
      return;
    }

    final seq = identity.bumpLivenessSeq();
    await identity.persistIdentityResolutionState();
    final r = LivenessRecord.sign(
      identity,
      identity.deviceNodeId,
      addrs,
      ttlSeconds: _livenessRefreshInterval().inSeconds,
      sequenceNumber: seq,
    );

    // Self-store: see `_broadcastAuthManifest` for rationale.
    dhtHandler?.handleLivePublish(r);
    final liveKey = _liveKey(identity.userId, identity.deviceNodeId);
    // D4 (§4.3): subnet-diverse replicator selection.
    final closest = routingTable.findClosestPeers(liveKey,
        count: targetK,
        maxPerIpGroup: RoutingTable.diversityMaxPerIpGroup);
    final payload = Uint8List.fromList(r.toProto().writeToBuffer());
    for (final peer in closest) {
      try {
        await sender.send(
            proto.MessageTypeV3.MTV3_IDENTITY_LIVE_PUBLISH, payload, peer);
      } catch (_) {
        // Fire-and-forget.
      }
    }
    _lastPublishedAt = DateTime.now();
    _lastPublishedAddrs = List<proto.PeerAddressProto>.from(addrs);
  }

  /// True wenn:
  ///   (a) wir schon einmal publisht haben UND
  ///   (b) noch < 80% des TTL-Fensters vergangen sind UND
  ///   (c) die Adress-Liste byte-aequivalent ist (addressType + ip + port).
  bool _skipBecauseNoChange(List<proto.PeerAddressProto> currentAddrs) {
    if (_lastPublishedAt == null) return false;
    final ageMs = DateTime.now().difference(_lastPublishedAt!).inMilliseconds;
    final ttlMs = _livenessRefreshInterval().inMilliseconds;
    if (ttlMs <= 0) return false;
    final ageRatio = ageMs / ttlMs;
    if (ageRatio >= 0.8) return false;
    if (_lastPublishedAddrs.length != currentAddrs.length) return false;
    for (var i = 0; i < currentAddrs.length; i++) {
      final a = _lastPublishedAddrs[i];
      final b = currentAddrs[i];
      if (a.addressType != b.addressType) return false;
      if (a.ip != b.ip) return false;
      if (a.port != b.port) return false;
    }
    return true;
  }

  List<proto.PeerAddressProto> _currentAddresses() {
    // Phase 5 wired das gegen transport.localAddresses + nat.publicAddresses.
    // Skeleton: leere Liste, ausser Hook gesetzt.
    final hook = _addressProviderHook;
    if (hook != null) return hook();
    return const <proto.PeerAddressProto>[];
  }

  // ---- DHT-Key-Derivation ----------------------------------------------

  // ── Device-KEM-Record (Welle 5, §3.5b + §4.3) ──────────────────────

  void _scheduleDeviceKemRefresh() {
    _kemTimer?.cancel();
    _kemTimer = Timer(deviceKemRefreshInterval, () async {
      if (!_running) return;
      await _publishDeviceKemNow();
      _scheduleDeviceKemRefresh(); // self-rescheduling
    });
  }

  Future<void> _publishDeviceKemNow() async {
    if (!_running) return;
    final provider = _deviceKemPkProvider;
    if (provider == null) {
      _log.warn('DeviceKem publish skipped: provider not set');
      return;
    }
    final kemPks = provider();
    if (kemPks == null) {
      _log.warn('DeviceKem publish skipped: KEM keypair not initialized');
      return;
    }

    final seq = identity.bumpDeviceKemSeq();
    await identity.persistIdentityResolutionState();
    final record = DeviceKemRecord.sign(
      userId: identity.userId,
      deviceId: identity.deviceNodeId,
      deviceX25519Pk: kemPks.x25519Pk,
      deviceMlKemPk: kemPks.mlKemPk,
      userEd25519Sk: identity.ed25519SecretKey,
      userEd25519Pk: identity.ed25519PublicKey,
      ttlSeconds: deviceKemTtl.inSeconds,
      sequenceNumber: seq,
    );

    // Self-store: see `_broadcastAuthManifest` for rationale.
    dhtHandler?.handleKemPublish(record);
    final kemKey = _kemKey(identity.userId, identity.deviceNodeId);
    // D4 (§4.3): subnet-diverse replicator selection.
    final closest = routingTable.findClosestPeers(kemKey,
        count: targetK,
        maxPerIpGroup: RoutingTable.diversityMaxPerIpGroup);
    final payload = Uint8List.fromList(record.toProto().writeToBuffer());
    _log.info('DeviceKem publish: targets=${closest.length} peers '
        '(routingTable.peerCount=${routingTable.peerCount}, targetK=$targetK)');
    var sent = 0;
    var failed = 0;
    for (final peer in closest) {
      try {
        await sender.send(
            proto.MessageTypeV3.MTV3_IDENTITY_KEM_PUBLISH, payload, peer);
        sent++;
      } catch (e) {
        // Fire-and-forget; replication factor toleriert einzelne Fehler.
        failed++;
      }
    }
    _log.info('DeviceKem publish complete: $sent ok, $failed failed');
  }

  /// `kem-key = SHA-256("kem" || userId || deviceId)`. Eigener Key-Space,
  /// independent von "auth"+userId und "live"+userId+deviceId. Strikt §4.3 +
  /// `proto/cleona.proto::DeviceKemRecordV3`-Comment.
  Uint8List _kemKey(Uint8List userId, Uint8List deviceId) {
    final combined = Uint8List(userId.length + deviceId.length);
    combined.setRange(0, userId.length, userId);
    combined.setRange(userId.length, combined.length, deviceId);
    return _hashWithPrefix('kem', combined);
  }

  /// `auth-key = SHA-256("auth" || userId)`. Replicas finden den Manifest
  /// ueber findClosestPeers(authKey).
  Uint8List _authKey(Uint8List userId) => _hashWithPrefix('auth', userId);

  /// `live-key = SHA-256("live" || userId || deviceNodeId)`. Pro Device ein
  /// eigener Key, sodass Multi-Device-Liveness sich nicht gegenseitig
  /// ueberschreibt.
  Uint8List _liveKey(Uint8List userId, Uint8List deviceNodeId) {
    final combined = Uint8List(userId.length + deviceNodeId.length);
    combined.setRange(0, userId.length, userId);
    combined.setRange(userId.length, combined.length, deviceNodeId);
    return _hashWithPrefix('live', combined);
  }

  Uint8List _hashWithPrefix(String prefix, Uint8List data) {
    final input = Uint8List(prefix.length + data.length);
    for (var i = 0; i < prefix.length; i++) {
      input[i] = prefix.codeUnitAt(i) & 0xff;
    }
    input.setRange(prefix.length, input.length, data);
    return SodiumFFI().sha256(input);
  }
}
