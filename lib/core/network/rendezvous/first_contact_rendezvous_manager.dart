/// First-Contact Rendezvous Manager (§4.11.10).
///
/// URI-scoped rendezvous for the very first contact between two devices that
/// exchanged a ContactSeed-URI over an asynchronous channel (clipboard,
/// e-mail, messenger). The URI carries a 32-byte random nonce (`r`); owner
/// (URI creator) and scanner (URI consumer) derive lookup tags + an
/// encryption key from it and publish/resolve EndpointRecords on the
/// external rendezvous substrate (Nostr) until the first CR round-trip
/// succeeds. QR/NFC are synchronous channels and do not use this path.
///
/// Traffic discipline (CLAUDE.md Arbeitsregel #5):
/// - Owner poll: first after 30s, then every 90s; after 30 min without a
///   hit, backoff to every 10 min. Stops on session done or 72h TTL.
/// - Scanner: publish at session start + epoch boundary + network change
///   (debounced); owner-resolve at session start and before CR retries
///   (rate-limited to once per 60s per session). No own retry timer.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/secp256k1_schnorr.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart' show PeerAddress;
import 'package:cleona/core/network/rendezvous/nostr_provider.dart';
import 'package:cleona/core/network/rendezvous/rendezvous_manager.dart'
    show RendezvousAddress;
import 'package:cleona/core/network/rendezvous/rendezvous_provider.dart';
import 'package:cleona/core/network/rendezvous/rendezvous_secret.dart';
import 'package:cleona/core/storage/atomic_json_writer.dart';

export 'package:cleona/core/network/rendezvous/rendezvous_secret.dart'
    show kFcRoleOwner, kFcRoleScanner;

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/// Hard session TTL from createdAtMs (§4.11.10).
const Duration kFcSessionTtl = Duration(hours: 72);

/// Owner poll schedule: initial delay, steady cadence, backoff threshold
/// and backoff cadence (Arbeitsregel #5: no traffic flooding).
const Duration kFcOwnerInitialPollDelay = Duration(seconds: 30);
const Duration kFcOwnerPollInterval = Duration(seconds: 90);
const Duration kFcOwnerBackoffAfter = Duration(minutes: 30);
const Duration kFcOwnerBackoffPollInterval = Duration(minutes: 10);

/// Debounce for network-change republish (same as RendezvousManager).
const Duration kFcNetworkChangeDebounce = Duration(seconds: 10);

/// Minimum interval between owner-tag resolves triggered by CR retries
/// (the CR retry backoff starts at 10s — without this cap every early
/// retry would hit all Nostr relays).
const Duration kFcScannerResolveMinInterval = Duration(seconds: 60);

// ---------------------------------------------------------------------------
// Session model
// ---------------------------------------------------------------------------

class FcSession {
  final Uint8List nonce;
  final String role; // kFcRoleOwner | kFcRoleScanner
  final int createdAtMs;
  bool done;

  /// Scanner-only: the contact this session bootstraps (userId keys the
  /// CR/done-tracking, deviceId keys the routing-table merge).
  final String? targetUserIdHex;
  final String? targetDeviceIdHex;

  /// Owner-only, runtime: scanner devices already resolved via the
  /// scanner-tag. An incoming First-CR from one of these marks the
  /// session done. Not persisted — rebuilt by the next poll hit.
  final Set<String> resolvedScannerDeviceHexes = {};

  /// Owner-only, runtime: last poll hit (resets the backoff clock).
  int lastHitAtMs = 0;

  /// Scanner-only, runtime: last owner-tag resolve (rate limit).
  int lastOwnerResolveAtMs = 0;

  FcSession({
    required this.nonce,
    required this.role,
    required this.createdAtMs,
    this.done = false,
    this.targetUserIdHex,
    this.targetDeviceIdHex,
  });

  String get nonceHex =>
      nonce.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  bool expiredAt(int nowMs) =>
      nowMs - createdAtMs > kFcSessionTtl.inMilliseconds;

  Map<String, dynamic> toJson() => {
        'n': base64Encode(nonce),
        'r': role,
        'c': createdAtMs,
        'd': done,
        if (targetUserIdHex != null) 'tu': targetUserIdHex,
        if (targetDeviceIdHex != null) 'td': targetDeviceIdHex,
      };

  static FcSession? fromJson(Map<String, dynamic> j) {
    try {
      final nonce = Uint8List.fromList(base64Decode(j['n'] as String));
      if (nonce.length != 32) return null;
      return FcSession(
        nonce: nonce,
        role: j['r'] as String,
        createdAtMs: j['c'] as int,
        done: j['d'] as bool? ?? false,
        targetUserIdHex: j['tu'] as String?,
        targetDeviceIdHex: j['td'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// FirstContactRendezvousManager (§4.11.10)
// ---------------------------------------------------------------------------

class FirstContactRendezvousManager {
  final List<RendezvousProvider> _providers;
  final CLogger _log;
  final String? _profileDir;

  Uint8List? _deviceId;
  List<RendezvousAddress> Function()? _addressProvider;

  /// Fired when the other side's EndpointRecord was resolved and decrypted.
  /// The service merges the addresses into the routing table and sends
  /// PINGs (simultaneous-open: both sides send → carrier firewalls open
  /// bidirectionally). Fired on EVERY poll hit while the session is active
  /// so the PINGs are repeated (§4.11.10).
  void Function(FcSession session, String deviceIdHex,
      List<EndpointAddress> addresses)? onEndpointResolved;

  final Map<String, FcSession> _sessions = {}; // nonceHex → session
  final Map<String, Timer> _pollTimers = {}; // nonceHex → owner poll timer
  Timer? _epochTimer;
  Timer? _debounceTimer;
  int _seq = 0;
  bool _disposed = false;

  FirstContactRendezvousManager({
    List<RendezvousProvider>? providers,
    String? profileDir,
  })  : _providers = providers ?? [NostrProvider(profileDir: profileDir)],
        _profileDir = profileDir,
        _log = CLogger.get('fc-rv', profileDir: profileDir);

  void init({
    required Uint8List deviceId,
    required List<RendezvousAddress> Function() addressProvider,
  }) {
    _deviceId = deviceId;
    _addressProvider = addressProvider;
    _loadSessions();
  }

  /// Active (not done, not expired) sessions — for tests/introspection.
  List<FcSession> get activeSessions => _sessions.values
      .where((s) => !s.done &&
          !s.expiredAt(DateTime.now().millisecondsSinceEpoch))
      .toList();

  // -------------------------------------------------------------------------
  // Session lifecycle
  // -------------------------------------------------------------------------

  /// Owner side: a clipboard/share URI carrying [nonce] was handed out.
  /// Publishes our EndpointRecord under the owner-tag and starts polling
  /// the scanner-tag. Idempotent per nonce (re-copying the same URI does
  /// not create a second session).
  void startOwnerSession(Uint8List nonce) {
    if (_disposed || nonce.length != 32) return;
    final s = _upsertSession(nonce, kFcRoleOwner);
    if (s == null) return;
    unawaited(_publishFor(s));
    _scheduleOwnerPoll(s, kFcOwnerInitialPollDelay);
    _ensureEpochTimer();
    _saveSessions();
    _log.info('FC-RV: owner session started '
        '(nonce ${s.nonceHex.substring(0, 8)}…)');
  }

  /// Scanner side: a URI carrying [nonce] for contact
  /// [targetUserIdHex]/[targetDeviceIdHex] was pasted. Resolves the
  /// owner-tag once (fresher addresses than `a=`) and publishes our own
  /// EndpointRecord under the scanner-tag. Idempotent per nonce.
  void startScannerSession(
      Uint8List nonce, String targetUserIdHex, String targetDeviceIdHex) {
    if (_disposed || nonce.length != 32) return;
    final s = _upsertSession(nonce, kFcRoleScanner,
        targetUserIdHex: targetUserIdHex.toLowerCase(),
        targetDeviceIdHex: targetDeviceIdHex.toLowerCase());
    if (s == null) return;
    unawaited(_publishFor(s));
    unawaited(_resolveOwnerTag(s, force: true));
    _ensureEpochTimer();
    _saveSessions();
    _log.info('FC-RV: scanner session started for '
        '${targetUserIdHex.substring(0, 8)}… '
        '(nonce ${s.nonceHex.substring(0, 8)}…)');
  }

  FcSession? _upsertSession(Uint8List nonce, String role,
      {String? targetUserIdHex, String? targetDeviceIdHex}) {
    final hex =
        nonce.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final existing = _sessions[hex];
    if (existing != null) {
      if (existing.done ||
          existing.expiredAt(DateTime.now().millisecondsSinceEpoch)) {
        return null; // finished sessions are never revived
      }
      return existing;
    }
    final s = FcSession(
      nonce: Uint8List.fromList(nonce),
      role: role,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      targetUserIdHex: targetUserIdHex,
      targetDeviceIdHex: targetDeviceIdHex,
    );
    _sessions[hex] = s;
    return s;
  }

  /// Owner done-hook: an inbound First-CR from [senderDeviceHex] was
  /// processed. Any owner session that already resolved this scanner
  /// device is complete (§4.11.10 session end).
  void onFirstCrReceived(String senderDeviceHex) {
    var changed = false;
    for (final s in _sessions.values) {
      if (s.done || s.role != kFcRoleOwner) continue;
      if (s.resolvedScannerDeviceHexes.contains(senderDeviceHex)) {
        _finishSession(s, 'first-CR from resolved scanner '
            '${senderDeviceHex.substring(0, 8)}…');
        changed = true;
      }
    }
    if (changed) _saveSessions();
  }

  /// Scanner done-hook: the CR to [targetUserIdHex] was confirmed
  /// (DELIVERY_RECEIPT / CR-Response accepted).
  void onCrConfirmed(String targetUserIdHex) {
    var changed = false;
    final targetLower = targetUserIdHex.toLowerCase();
    for (final s in _sessions.values) {
      if (s.done || s.role != kFcRoleScanner) continue;
      if (s.targetUserIdHex == targetLower) {
        _finishSession(s, 'CR confirmed for '
            '${targetUserIdHex.substring(0, 8)}…');
        changed = true;
      }
    }
    if (changed) _saveSessions();
  }

  void _finishSession(FcSession s, String reason) {
    s.done = true;
    _pollTimers.remove(s.nonceHex)?.cancel();
    _log.info('FC-RV: session ${s.nonceHex.substring(0, 8)}… done ($reason)');
    _maybeStopEpochTimer();
  }

  // -------------------------------------------------------------------------
  // Publish (both roles)
  // -------------------------------------------------------------------------

  Future<void> _publishFor(FcSession s) async {
    if (_disposed || s.done) return;
    final devId = _deviceId;
    final addrFn = _addressProvider;
    if (devId == null || addrFn == null) return;

    // Same address filter as RendezvousManager.publishForAllContacts:
    // only externally reachable addresses (public IPv4 + global IPv6).
    final publicAddresses = addrFn()
        .where((a) => !PeerAddress.isPrivateIp(a.ip))
        .toList();
    if (publicAddresses.isEmpty) {
      _log.debug('FC-RV publish: no public addresses, skipping '
          '(session ${s.nonceHex.substring(0, 8)}…)');
      return;
    }

    _seq++;
    final record = EndpointRecord(
      addresses: publicAddresses
          .map((a) => EndpointAddress(a.ip, a.port))
          .toList(),
      seq: _seq,
      publishedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
      deviceId: devId,
    );

    final nostrSk = deriveFcNostrSecretKey(s.nonce, devId);
    final nostrKp = secp256k1KeypairFromSecret(nostrSk);

    var publishCount = 0;
    for (final epoch in [currentEpochString(), nextEpochString()]) {
      final tag = computeFcTag(s.nonce, epoch, s.role);
      final key = deriveFcKey(s.nonce, epoch);
      final encrypted = encryptEndpointRecord(record, key, tag);

      for (final provider in _providers) {
        if (!provider.isAvailable) continue;
        try {
          if (provider is NostrProvider) {
            await provider.publishWithKey(tag, encrypted, nostrKp.secretKey);
          } else {
            await provider.publish(tag, encrypted);
          }
          publishCount++;
        } catch (e) {
          _log.debug('FC-RV publish failed: $e');
        }
      }
    }
    _log.info('FC-RV: published ${s.role} record to $publishCount '
        'provider-epoch pairs (session ${s.nonceHex.substring(0, 8)}…, '
        'seq=$_seq, ${publicAddresses.length} public addresses)');
  }

  // -------------------------------------------------------------------------
  // Owner poll (scanner-tag)
  // -------------------------------------------------------------------------

  void _scheduleOwnerPoll(FcSession s, Duration delay) {
    if (_disposed) return;
    _pollTimers.remove(s.nonceHex)?.cancel();
    _pollTimers[s.nonceHex] = Timer(delay, () => _ownerPollTick(s));
  }

  Future<void> _ownerPollTick(FcSession s) async {
    _pollTimers.remove(s.nonceHex);
    if (_disposed || s.done) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (s.expiredAt(nowMs)) {
      _log.info('FC-RV: owner session ${s.nonceHex.substring(0, 8)}… '
          'expired (72h TTL)');
      _saveSessions(); // prunes expired entries
      _maybeStopEpochTimer();
      return;
    }

    final hit = await _resolveRole(s, kFcRoleScanner,
        onHit: (deviceIdHex, addresses) {
      final isNew = s.resolvedScannerDeviceHexes.add(deviceIdHex);
      if (isNew) {
        _log.info('FC-RV: owner resolved scanner device '
            '${deviceIdHex.substring(0, 8)}… '
            '(${addresses.length} addresses)');
      }
      // Fire on every hit — the service repeats the PINGs each time
      // (simultaneous-open) as long as the session is active.
      onEndpointResolved?.call(s, deviceIdHex, addresses);
    });

    if (hit) s.lastHitAtMs = nowMs;

    // Backoff: 90s cadence; after 30 min without a hit → 10 min cadence.
    final sinceActivity = nowMs -
        (s.lastHitAtMs > 0 ? s.lastHitAtMs : s.createdAtMs);
    final next = sinceActivity > kFcOwnerBackoffAfter.inMilliseconds
        ? kFcOwnerBackoffPollInterval
        : kFcOwnerPollInterval;
    _scheduleOwnerPoll(s, next);
  }

  // -------------------------------------------------------------------------
  // Scanner resolve (owner-tag)
  // -------------------------------------------------------------------------

  /// Resolve the owner-tag for the scanner session bootstrapping
  /// [targetUserIdHex]. Called at session start and from the existing CR
  /// retry path (`_retryPendingContactRequests`) — rate-limited here so
  /// the early 10s/20s retry ticks do not hammer the relays.
  Future<void> resolveOwnerForContact(String targetUserIdHex) async {
    final targetLower = targetUserIdHex.toLowerCase();
    for (final s in _sessions.values.toList()) {
      if (s.done || s.role != kFcRoleScanner) continue;
      if (s.targetUserIdHex != targetLower) continue;
      await _resolveOwnerTag(s);
    }
  }

  Future<void> _resolveOwnerTag(FcSession s, {bool force = false}) async {
    if (_disposed || s.done) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (s.expiredAt(nowMs)) return;
    if (!force &&
        nowMs - s.lastOwnerResolveAtMs <
            kFcScannerResolveMinInterval.inMilliseconds) {
      return;
    }
    s.lastOwnerResolveAtMs = nowMs;

    await _resolveRole(s, kFcRoleOwner, onHit: (deviceIdHex, addresses) {
      _log.info('FC-RV: scanner resolved owner device '
          '${deviceIdHex.substring(0, 8)}… (${addresses.length} addresses)');
      onEndpointResolved?.call(s, deviceIdHex, addresses);
    });
  }

  // -------------------------------------------------------------------------
  // Shared resolve helper
  // -------------------------------------------------------------------------

  /// Resolve records published under [role]'s tag for session [s]
  /// (current + previous epoch, all providers). Dedups by publishing
  /// device. Returns true if at least one record decrypted.
  Future<bool> _resolveRole(FcSession s, String role,
      {required void Function(String deviceIdHex,
              List<EndpointAddress> addresses)
          onHit}) async {
    var anyHit = false;
    final seenDevices = <String>{};
    for (final epoch in [currentEpochString(), previousEpochString()]) {
      final tag = computeFcTag(s.nonce, epoch, role);
      final key = deriveFcKey(s.nonce, epoch);

      final records = await Future.wait(_providers
          .where((p) => p.isAvailable)
          .map((p) => p.resolve(tag).catchError((_) => null)));

      for (final signed in records) {
        if (signed == null) continue;
        final ep = decryptEndpointRecord(signed, key, tag);
        if (ep == null || ep.addresses.isEmpty) continue;
        final devHex = ep.deviceId
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        if (!seenDevices.add(devHex)) continue;
        anyHit = true;
        onHit(devHex, ep.addresses);
      }
    }
    return anyHit;
  }

  // -------------------------------------------------------------------------
  // Triggers: network change + epoch boundary
  // -------------------------------------------------------------------------

  /// Debounced republish of all active sessions after a network change
  /// (same pattern as RendezvousManager).
  void onNetworkChanged() {
    if (_disposed || activeSessions.isEmpty) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(kFcNetworkChangeDebounce, () {
      for (final s in activeSessions) {
        unawaited(_publishFor(s));
      }
    });
  }

  /// Resume persisted sessions after startup (called from the service's
  /// discovery-complete hook — network is up by then). Republishes records
  /// (the on-relay copies may predate the current epoch) and re-arms the
  /// owner poll timers.
  void resumeSessions() {
    if (_disposed) return;
    final active = activeSessions;
    if (active.isEmpty) return;
    for (final s in active) {
      unawaited(_publishFor(s));
      if (s.role == kFcRoleOwner) {
        _scheduleOwnerPoll(s, kFcOwnerInitialPollDelay);
      } else {
        unawaited(_resolveOwnerTag(s, force: true));
      }
    }
    _ensureEpochTimer();
    _log.info('FC-RV: resumed ${active.length} persisted session(s)');
  }

  /// One shared timer that fires shortly after each 6h epoch boundary and
  /// republishes all active sessions (records must stay resolvable across
  /// the whole 72h session TTL). Self-rescheduling; stops itself when no
  /// active sessions remain.
  void _ensureEpochTimer() {
    if (_disposed || _epochTimer != null) return;
    final now = DateTime.now().toUtc();
    final epochMs = kRendezvousEpochHours * 3600 * 1000;
    final sinceEpochStart = now.millisecondsSinceEpoch % epochMs;
    // +30s past the boundary so publish lands cleanly in the new epoch.
    final untilNext = Duration(
        milliseconds: epochMs - sinceEpochStart + 30 * 1000);
    _epochTimer = Timer(untilNext, () {
      _epochTimer = null;
      final active = activeSessions;
      if (active.isEmpty) {
        _saveSessions(); // prune expired
        return;
      }
      for (final s in active) {
        unawaited(_publishFor(s));
      }
      _ensureEpochTimer();
    });
  }

  void _maybeStopEpochTimer() {
    if (activeSessions.isEmpty) {
      _epochTimer?.cancel();
      _epochTimer = null;
    }
  }

  // -------------------------------------------------------------------------
  // Persistence (profileDir JSON, atomic — pattern: AtomicJsonWriter)
  // -------------------------------------------------------------------------

  String? get _sessionsPath =>
      _profileDir == null ? null : '$_profileDir/fc_rendezvous.json';

  void _loadSessions() {
    final path = _sessionsPath;
    if (path == null) return;
    try {
      final json = AtomicJsonWriter.readJsonFile(path);
      if (json == null) return;
      final list = json['sessions'] as List<dynamic>? ?? [];
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      var loaded = 0;
      for (final e in list) {
        final s = FcSession.fromJson(e as Map<String, dynamic>);
        // Keep done-but-unexpired sessions too: the done marker blocks a
        // stale URI re-paste from reviving a finished session (upsert
        // checks the in-memory map). Expired ones are pruned.
        if (s == null || s.expiredAt(nowMs)) continue;
        _sessions[s.nonceHex] = s;
        if (!s.done) loaded++;
      }
      if (loaded > 0) {
        _log.info('FC-RV: loaded $loaded persisted active session(s)');
      }
    } catch (e) {
      _log.warn('FC-RV: failed to load sessions: $e');
    }
  }

  void _saveSessions() {
    final path = _sessionsPath;
    if (path == null) return;
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      // Persist non-expired sessions (including done ones — a done marker
      // prevents a stale URI re-paste from reviving a finished session).
      final list = _sessions.values
          .where((s) => !s.expiredAt(nowMs))
          .map((s) => s.toJson())
          .toList();
      AtomicJsonWriter.writeJsonFile(path, {'sessions': list});
    } catch (e) {
      _log.warn('FC-RV: failed to save sessions: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  void dispose() {
    _disposed = true;
    for (final t in _pollTimers.values) {
      t.cancel();
    }
    _pollTimers.clear();
    _epochTimer?.cancel();
    _epochTimer = null;
    _debounceTimer?.cancel();
    for (final provider in _providers) {
      if (provider is NostrProvider) provider.dispose();
    }
    _saveSessions();
  }
}
