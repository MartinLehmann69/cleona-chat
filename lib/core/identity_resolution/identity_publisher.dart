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
import 'package:cleona/core/identity_resolution/liveness_record.dart';
import 'package:cleona/core/node/identity_context.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;
import 'package:meta/meta.dart';

/// Pro Identitaet ein Instance. Owns Auth + Liveness Publish-Schedule.
class IdentityPublisher {
  final IdentityContext identity;
  final RoutingTable routingTable;

  /// In Phase 5 typisiert (CleonaNode/EnvelopeSender). Skeleton akzeptiert
  /// jeden Sender mit `Future<void> send(MessageEnvelope, dynamic)`-Signatur.
  final dynamic sender;

  // Adaptive TTL config
  static const Duration foregroundLiveTtl = Duration(minutes: 15);
  static const Duration backgroundLiveTtl = Duration(hours: 1);
  static const Duration authTtl = Duration(hours: 24);
  static const Duration authRefreshInterval = Duration(hours: 20);

  // K=10 closest. effectiveK = min(K, peerCount) at publish time.
  static const int targetK = 10;
  static const int peerThreshold = 5;
  static const Duration coldStartTimeout = Duration(seconds: 30);
  static const Duration coldStartRetry = Duration(seconds: 60);
  static const Duration addressFlapDebounce = Duration(seconds: 5);

  bool _foreground = true;
  bool _running = false;
  Timer? _liveTimer;
  Timer? _authTimer;
  Timer? _coldStartRetryTimer;
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

  IdentityPublisher({
    required this.identity,
    required this.routingTable,
    required this.sender,
  });

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
    if (_running) return;
    _running = true;
    await _waitForPeersThenPublish();
  }

  void stop() {
    _running = false;
    _liveTimer?.cancel();
    _authTimer?.cancel();
    _coldStartRetryTimer?.cancel();
    _addressFlapDebounceTimer?.cancel();
  }

  /// Wird von CleonaNode/Discovery aufgerufen wenn ein neuer Peer in die
  /// Routing-Table kommt. Weckt einen geparkten Cold-Start sofort auf, sobald
  /// peerThreshold erreicht ist.
  void onPeerJoined() {
    if (!_running) return;
    if (routingTable.peerCount >= peerThreshold &&
        _coldStartRetryTimer != null) {
      _coldStartRetryTimer?.cancel();
      _coldStartRetryTimer = null;
      Future.microtask(_publishAuthAndStartLiveness);
      return;
    }
    // Cold-Start-Wait laeuft synchron in `_waitForPeersThenPublish` — der
    // sieht den Threshold-Hit von selbst beim naechsten 100ms-Tick.
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

  Future<void> _waitForPeersThenPublish() async {
    if (routingTable.peerCount >= peerThreshold) {
      await _publishAuthAndStartLiveness();
      return;
    }
    // Wait up to coldStartTimeout for peers to appear.
    final deadline = DateTime.now().add(coldStartTimeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!_running) return;
      if (routingTable.peerCount >= peerThreshold) {
        await _publishAuthAndStartLiveness();
        return;
      }
    }
    // Still no peers — schedule retry. Concurrent `onPeerJoined()` may also
    // wake us up earlier (it cancels this timer and triggers publish).
    _coldStartRetryTimer = Timer(coldStartRetry, () {
      _coldStartRetryTimer = null;
      if (!_running) return;
      _waitForPeersThenPublish();
    });
  }

  Future<void> _publishAuthAndStartLiveness() async {
    if (!_running) return;
    final seq = identity.bumpAuthManifestSeq();
    await identity.persistIdentityResolutionState();
    final manifest = AuthManifest.sign(
      identity,
      <Uint8List>[identity.deviceNodeId],
      ttlSeconds: authTtl.inSeconds,
      sequenceNumber: seq,
    );
    await _broadcastAuthManifest(manifest);
    _scheduleAuthRefresh();
    _scheduleLiveness(initialDelay: livenessInitialOffset);
    // Ersten Liveness-Publish sofort nach dem Auth durchziehen (dasselbe
    // closest-Set, kein Doppel-Schedule). Wenn `livenessInitialOffset > 0`
    // gilt nur das Refresh-Tempo, der Bootstrap-Publish soll noch JETZT raus,
    // sonst entsteht ein Adress-Loch zwischen Start und erstem Tick.
    await _publishLivenessNow();
  }

  Future<void> _broadcastAuthManifest(AuthManifest m) async {
    final authKey = _authKey(identity.userId);
    final closest = routingTable.findClosestPeers(authKey, count: targetK);
    final payload = m.toProto().writeToBuffer();
    for (final peer in closest) {
      final envelope = proto.MessageEnvelope()
        ..messageType = proto.MessageType.IDENTITY_AUTH_PUBLISH
        ..encryptedPayload = payload
        ..senderId = identity.userId
        ..senderDeviceNodeId = identity.deviceNodeId;
      try {
        await sender.send(envelope, peer);
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

    final liveKey = _liveKey(identity.userId, identity.deviceNodeId);
    final closest = routingTable.findClosestPeers(liveKey, count: targetK);
    final payload = r.toProto().writeToBuffer();
    for (final peer in closest) {
      final envelope = proto.MessageEnvelope()
        ..messageType = proto.MessageType.IDENTITY_LIVE_PUBLISH
        ..encryptedPayload = payload
        ..senderId = identity.userId
        ..senderDeviceNodeId = identity.deviceNodeId;
      try {
        await sender.send(envelope, peer);
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
