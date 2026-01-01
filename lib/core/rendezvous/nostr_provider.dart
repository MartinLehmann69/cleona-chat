/// Nostr relay client implementing [RendezvousProvider].
///
/// Architecture §4.11.6 (NIP-01, NIP-33 Parameterized Replaceable Events).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/secp256k1_schnorr.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/rendezvous/rendezvous_provider.dart';
import 'package:cleona/core/sync/external_entry.dart';
import 'package:cleona/core/util/uplink_state.dart';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/// Default relay set (S119 C2, verified via scripts/verify_nostr_relays.dart
/// on 2026-07-03). Non-empty intersection with the pre-C2 list (damus.io,
/// nos.lol, snort.social) is MANDATORY — deployed peers publish to the old
/// defaults, and a fresh install must query at least some common relays.
/// Removed: nostr.wine (write-restricted paid relay — publishes rejected),
/// relay.nostr.band (connect timeouts, field log + verification script).
const List<String> kDefaultNostrRelays = [
  'wss://relay.damus.io',
  'wss://nos.lol',
  'wss://relay.snort.social',
  'wss://relay.primal.net',
  'wss://offchain.pub',
  'wss://nostr.mom',
  'wss://nostr.oxtr.dev',
];

const Duration kRelayConnectTimeout = Duration(seconds: 10);
const Duration kRelayResponseTimeout = Duration(seconds: 10);

/// §4.11.11 (S119 C2): after the first resolve hit, keep collecting for this
/// window so slower relays can still deliver a higher-seq record — a stale
/// relay answering first must not win over a fresher record.
const Duration kResolveCollectWindow = Duration(milliseconds: 1750);

/// How many events a query fetches at most per relay and tag.
///
/// ── WHY THIS NUMBER MUST EXIST (S362) ────────────────────────────
///
/// The REQ filter below had no `limit`. Under a NETWORK-WIDE
/// SHARED tag — that is the daily tag of the external entry
/// (`ExternalTag.forDay`, derived from `kNetworkChannel`) — every
/// query thus loads EVERYTHING that was ever stored under this tag. And
/// storing happens with a throwaway key per event (v4_1 §11.3 wants
/// it that way), so no store replaces a previous one: the heap under a
/// tag grows monotonically over the day.
///
/// The price, calculated. A sealed entry record measures
/// 12 B nonce + 1371 B (`EntryRecord.encodedLength`, with ML-KEM-768 pubkey
/// 1184 B and one IPv4 host) + 16 B GCM tag = 1399 B; base64 in the
/// event content 1866 B; with the Nostr frame (id/pubkey/sig/d tag)
/// ≈ 2.3 KB per event. `ExternalEntrySource.fetch` asks 2 days x
/// 7 relays. On 29.08. 86 records came back this way ≈ 198 KB per
/// pass — and `_verabredungPflegen` repeats the pass every
/// 10 min as long as the node has too few partners: 144 x 198 KB
/// ≈ 28.5 MB/day. Working rule 5.
///
/// WHY 512 AND WHY THAT IS NOT A PRODUCT DECISION. The store into
/// which the response runs holds 512 records and takes from ONE
/// source at most a quarter of that (`EntryCache(capacity = 512)`,
/// quota `capacity ~/ 4 = 128`, `entry_record.dart:507/565`). A `limit`
/// of 512 can thus discard nothing the store would have kept.
/// Relays deliver under `limit` the NEWEST events first (NIP-01) —
/// for a cold start exactly the right selection, because an
/// entry record is the more usable the younger it is
/// (`EntryCache.dialCandidates` orders by the same consideration).
const int kRelayEventLimit = 512;

/// Idle time after which a pooled relay connection is closed. Long enough to
/// span a full publish cycle (N contacts × 2 epochs, sequential), short
/// enough not to hold sockets open indefinitely on mobile.
const Duration kRelayIdleClose = Duration(seconds: 30);

/// Passive health tracking (S119 C2): after this many consecutive transport
/// failures a relay is skipped until the cooldown elapses. Purely passive —
/// no probe traffic; a success resets the counter.
const int kRelayFailureThreshold = 3;
const Duration kRelayFailureCooldown = Duration(minutes: 10);

/// The REQ filter with which a tag is queried (NIP-01).
///
/// OWN FUNCTION instead of a literal in the body of `_fetchEvents`, namely
/// so that the cap is TESTABLE. A guard that instead searched the
/// source text for the string `'limit'` would be a
/// stand-in: it would stay green if the field stood there and the value
/// were wrong, and it would stay green if someone built a second,
/// uncapped REQ next to it. Against this function the STATEMENT can be
/// measured — "every query carries an upper limit, and it is
/// [kRelayEventLimit]".
Map<String, dynamic> nostrTagFilter(String tagHex) => {
      '#d': [tagHex],
      'kinds': [30078],
      // Justification and calculation: [kRelayEventLimit].
      'limit': kRelayEventLimit,
    };

// ---------------------------------------------------------------------------
// Nostr Event (NIP-01)
// ---------------------------------------------------------------------------

class NostrEvent {
  final String id;
  final String pubkey;
  final int createdAt;
  final int kind;
  final List<List<String>> tags;
  final String content;
  final String sig;

  const NostrEvent({
    required this.id,
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    required this.tags,
    required this.content,
    required this.sig,
  });

  /// Compute event id = SHA-256 of the canonical serialization.
  static String computeId(String pubkey, int createdAt, int kind,
      List<List<String>> tags, String content) {
    final serialized =
        '[0,"$pubkey",$createdAt,$kind,${jsonEncode(tags)},${jsonEncode(content)}]';
    final hash = SodiumFFI()
        .sha256(Uint8List.fromList(utf8.encode(serialized)));
    return _bytesToHex(hash);
  }

  /// Build and sign a Nostr event with a throwaway secp256k1 keypair.
  static NostrEvent create({
    required int kind,
    required List<List<String>> tags,
    required String content,
    required Uint8List secretKey,
    required Uint8List publicKey,
  }) {
    final pubkeyHex = _bytesToHex(publicKey);
    final createdAt = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final id = computeId(pubkeyHex, createdAt, kind, tags, content);
    final idBytes = _hexToBytes(id);
    final sig = schnorrSign(secretKey, idBytes);
    return NostrEvent(
      id: id,
      pubkey: pubkeyHex,
      createdAt: createdAt,
      kind: kind,
      tags: tags,
      content: content,
      sig: _bytesToHex(sig),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'pubkey': pubkey,
        'created_at': createdAt,
        'kind': kind,
        'tags': tags,
        'content': content,
        'sig': sig,
      };

  static NostrEvent? fromJson(Map<String, dynamic> j) {
    try {
      return NostrEvent(
        id: j['id'] as String,
        pubkey: j['pubkey'] as String,
        createdAt: j['created_at'] as int,
        kind: j['kind'] as int,
        tags: (j['tags'] as List)
            .map((t) => (t as List).map((e) => e.toString()).toList())
            .toList(),
        content: j['content'] as String,
        sig: j['sig'] as String,
      );
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// NostrProvider (§4.11.6)
// ---------------------------------------------------------------------------

class NostrProvider implements RendezvousProvider {
  final List<String> relayUris;
  final CLogger _log;
  final Map<String, _RelayConnection> _connections = {};
  bool _disposed = false;

  NostrProvider({List<String>? relays, String? profileDir})
      : relayUris = relays ?? kDefaultNostrRelays,
        _log = CLogger.get('nostr', profileDir: profileDir);

  @override
  bool get isAvailable => true;

  _RelayConnection _conn(String uri) =>
      _connections.putIfAbsent(uri, () => _RelayConnection(uri, _log));

  /// S119 C2: passive health gate. Relays with >= kRelayFailureThreshold
  /// consecutive failures are skipped during the cooldown. If EVERY relay is
  /// in cooldown (e.g. the whole previous network was broken), all are used
  /// anyway — a blanket skip would deadlock recovery after a network change.
  List<String> _usableRelays() {
    final usable = relayUris.where((u) => _conn(u).isUsable).toList();
    return usable.isEmpty ? relayUris : usable;
  }

  /// Close pooled connections and stop idle timers.
  void dispose() {
    _disposed = true;
    for (final c in _connections.values) {
      c.close();
    }
    _connections.clear();
  }

  // -------------------------------------------------------------------------
  // Publish (§4.11.6 — Publish flow, pooled connections)
  // -------------------------------------------------------------------------

  /// Publish with an externally provided secp256k1 secret key (deterministic).
  ///
  /// Replaces the own previous record under the same tag in place
  /// (NIP-33). When that is wanted and when not: contract in
  /// `rendezvous_provider.dart`.
  @override
  Future<void> publishWithKey(Uint8List lookupTag, SignedEndpointRecord record,
      Uint8List nostrSecretKey) async {
    final kp = secp256k1PubkeyFromSecret(nostrSecretKey);
    await _publishEvent(lookupTag, record, nostrSecretKey, kp);
  }

  /// Throwaway key pair per event — the stores lie NEXT to each other.
  ///
  /// Unlinkable over time, but not replacing: every renewed store
  /// under the same tag is an additional record on the relay.
  /// The AEAD nonce is new each time, so the deduplication by
  /// ciphertext in [resolveMulti] does not apply either. Whoever
  /// stores more often than once per tag takes [publishWithKey].
  ///
  /// CORRECTED 02.09.2026 (S362). Here it additionally said "no `limit` in the
  /// REQ filter, so every query loads the whole heap". That no longer
  /// holds: [nostrTagFilter] caps every query at
  /// [kRelayEventLimit] events per relay. The heap still
  /// arises — it is just no longer transmitted without limit.
  @override
  Future<void> publish(Uint8List lookupTag, SignedEndpointRecord record) async {
    final kp = generateSecp256k1Keypair();
    await _publishEvent(lookupTag, record, kp.secretKey, kp.publicKey);
  }

  /// Stores RAW bytes under a tag.
  ///
  /// The V4.1 cold-start cascade (§11.3) passes through an encrypted
  /// entry record, not a `SignedEndpointRecord`. The content
  /// of an event was only Base64 of bytes anyway — the detour via
  /// the V3 type was coupling, not a necessity.
  /// Fetches RAW chunks from ALL reachable relays.
  ///
  /// Unlike [resolve] the "best" one is not chosen — on cold start
  /// one wants every entry point one can get, and the selection
  /// is made by the cascade, not by the fetch.
  Future<List<Uint8List>> resolveRaw(Uint8List lookupTag) async {
    if (_disposed) return const <Uint8List>[];
    final tagHex = _bytesToHex(lookupTag);
    final out = <Uint8List>[];
    for (final uri in _usableRelays()) {
      try {
        out.addAll(await _conn(uri).fetchAllRaw(tagHex));
      } catch (_) {
        // A relay that does not answer is a relay without content.
      }
    }
    return out;
  }

  Future<void> publishRaw(Uint8List lookupTag, Uint8List content) async {
    final kp = generateSecp256k1Keypair();
    await _publishBytes(lookupTag, content, kp.secretKey, kp.publicKey);
  }

  Future<void> _publishEvent(Uint8List lookupTag, SignedEndpointRecord record,
          Uint8List secretKey, Uint8List publicKey) async =>
      _publishBytes(lookupTag, record.serialize(), secretKey, publicKey);

  Future<void> _publishBytes(Uint8List lookupTag, Uint8List content,
      Uint8List secretKey, Uint8List publicKey) async {
    if (_disposed) return;
    final tagHex = _bytesToHex(lookupTag);
    final contentB64 = base64Encode(content);

    final event = NostrEvent.create(
      kind: 30078,
      tags: [
        ['d', tagHex]
      ],
      content: contentB64,
      secretKey: secretKey,
      publicKey: publicKey,
    );

    final relays = _usableRelays();
    var successCount = 0;

    await Future.wait(relays.map((uri) async {
      try {
        await _conn(uri).publishEvent(event);
        successCount++;
      } catch (e) {
        _log.debug('Nostr publish to $uri failed: $e');
      }
    }));

    _log.info('Nostr publish: $successCount/${relays.length} relays '
        '(${relayUris.length - relays.length} in cooldown) '
        'for tag ${tagHex.substring(0, 8)}…');

    // ── THE EDGE OF THE INTERNET LEG (S373) ──────────────────────────
    //
    // This number has always stood here and had NO reader in `lib/` —
    // re-measured. It IS the observation "I get outside":
    // no additional packet, no timer, no own probe, only the
    // evaluation of an event that takes place anyway
    // (working rule #5). An own reachability check would be the
    // obvious alternative and is rejected — it would cost traffic,
    // put a regular pattern on the exit and answer
    // a different question.
    //
    // ONLY WITH A NON-EMPTY RELAY LIST. A round without a single
    // queried peer (all in cool-down) is not an observation
    // about the NETWORK but one about the own configuration. Booking it
    // as a failure would let a node lose its internet leg
    // because its relay list is currently cooling down.
    if (relays.isNotEmpty) {
      UplinkState.instance.note(reached: successCount > 0);
    }
  }

  // -------------------------------------------------------------------------
  // Resolve (§4.11.6 — Resolve flow, collect window at highest seq)
  // -------------------------------------------------------------------------

  @override
  Future<SignedEndpointRecord?> resolve(Uint8List lookupTag) async {
    if (_disposed) return null;
    final tagHex = _bytesToHex(lookupTag);
    _log.debug('Nostr resolve: querying tag ${tagHex.substring(0, 8)}…');

    final relays = _usableRelays();
    final completer = Completer<SignedEndpointRecord?>();
    SignedEndpointRecord? best;
    var pending = relays.length;
    Timer? collectTimer;

    void finish() {
      collectTimer?.cancel();
      if (!completer.isCompleted) completer.complete(best);
    }

    for (final uri in relays) {
      _conn(uri).fetchLatest(tagHex).then((record) {
        if (record != null) {
          final b = best;
          if (b == null || record.seq > b.seq) best = record;
          // §4.11.11: first hit opens the collect window; later hits from
          // slower relays can still replace `best` if their seq is higher.
          collectTimer ??= Timer(kResolveCollectWindow, finish);
        }
      }).catchError((e) {
        _log.debug('Nostr resolve from $uri failed: $e');
        return null;
      }).whenComplete(() {
        pending--;
        if (pending == 0) finish();
      });
    }

    return completer.future.timeout(
      kRelayConnectTimeout + kRelayResponseTimeout,
      onTimeout: () {
        collectTimer?.cancel();
        _log.debug('Nostr resolve: timeout for tag ${tagHex.substring(0, 8)}…');
        return best;
      },
    );
  }

  /// Like [resolve] but returns ALL records from all relays (deduped by
  /// content), not just the highest-seq one.
  ///
  /// WITHOUT CALLERS — re-measured 01.09.2026 (S361), second search pattern
  /// `resolveMulti` across `lib/` and `test/`: zero hits except this
  /// declaration. The sentence "Used by BinaryRendezvousManager to discover
  /// multiple provider devices" stood here and was wrong.
  ///
  /// The consequence is a separate, larger finding than the signing key
  /// above: ALL four managers read via `resolve(tag)`
  /// (`binary_rendezvous_manager.dart:299`,
  /// `first_contact_rendezvous_manager.dart:439`,
  /// `infra_rendezvous_manager.dart:179`, `rendezvous_manager.dart:216`),
  /// because the contract `RendezvousProvider` only knows this one method.
  /// `resolve` takes `fetchLatest` per relay, i.e. EXACTLY ONE record —
  /// the one with the highest `seq`. Thus the
  /// NIP-33 multi-publisher property that v3_0 §4.11.9, §4.11.10
  /// and §19.6.5 expressly promise ("The resolver query returns events
  /// from ALL infra nodes") is broken on the READ SIDE — regardless
  /// of which signing key the store takes.
  ///
  /// Sharper still: `seq` is a DEVICE-LOCAL counter advanced via `rendezvous_seq`
  /// (`binary_rendezvous_manager.dart:167-180`).
  /// Under a network-wide shared tag therefore always the same
  /// device wins — the one with the longest operating life —, not the freshest
  /// or nearest. A second scanner of the same invitation (§4.11.10,
  /// "Multiple scanners of the same URI coexist") is invisible to the owner.
  ///
  /// NOT fixed in S361: the fix is an extension of the contract plus
  /// a selection rule per manager, and first contact is worked on in a
  /// separate branch (`s361/erstkontakt`). It stands here so that
  /// the next session does not search for it again.
  Future<List<SignedEndpointRecord>> resolveMulti(Uint8List lookupTag) async {
    if (_disposed) return [];
    final tagHex = _bytesToHex(lookupTag);

    final relays = _usableRelays();
    final allRecords = <SignedEndpointRecord>[];
    final seen = <String>{};

    final futures = relays.map((uri) =>
        _conn(uri).fetchAll(tagHex).catchError((_) => <SignedEndpointRecord>[]));
    final results = await Future.wait(futures).timeout(
      kRelayConnectTimeout + kRelayResponseTimeout,
      onTimeout: () => [],
    );
    for (final batch in results) {
      for (final record in batch) {
        final key = base64Encode(record.ciphertext);
        if (seen.add(key)) allRecords.add(record);
      }
    }
    return allRecords;
  }
}

// ---------------------------------------------------------------------------
// _RelayConnection — one pooled WebSocket per relay (S119 C2)
// ---------------------------------------------------------------------------

/// A lazily connected, reused WebSocket to a single relay.
///
/// Pre-C2 the provider opened one WebSocket PER EVENT (N contacts × 2 epochs
/// per publish cycle) — dozens of connects in a burst, which is exactly what
/// public relays rate-limit. Now a cycle reuses one connection per relay;
/// the socket closes after [kRelayIdleClose] without pending work.
class _RelayConnection {
  final String uri;
  final CLogger _log;

  WebSocket? _ws;
  Future<WebSocket>? _connecting;
  Timer? _idleTimer;
  int _subCounter = 0;
  int _pendingOps = 0;
  bool _closed = false;

  /// eventId → completer for the relay's ["OK", eventId, bool, msg].
  final Map<String, Completer<void>> _pendingOks = {};

  /// subId → active REQ subscription.
  final Map<String, _ActiveSub> _activeSubs = {};

  // Passive health tracking (S119 C2).
  int _consecutiveFailures = 0;
  DateTime? _lastFailureAt;

  _RelayConnection(this.uri, this._log);

  bool get isUsable {
    if (_consecutiveFailures < kRelayFailureThreshold) return true;
    final last = _lastFailureAt;
    return last == null ||
        DateTime.now().difference(last) > kRelayFailureCooldown;
  }

  void _recordSuccess() {
    if (_consecutiveFailures >= kRelayFailureThreshold) {
      _log.info('Nostr relay $uri recovered');
    }
    _consecutiveFailures = 0;
  }

  void _recordFailure() {
    _consecutiveFailures++;
    _lastFailureAt = DateTime.now();
    if (_consecutiveFailures == kRelayFailureThreshold) {
      _log.info('Nostr relay $uri unhealthy after '
          '$_consecutiveFailures consecutive failures — cooldown '
          '${kRelayFailureCooldown.inMinutes}min');
    }
  }

  Future<WebSocket> _ensureConnected() {
    final ws = _ws;
    if (ws != null && ws.readyState == WebSocket.open) {
      return Future.value(ws);
    }
    final pending = _connecting;
    if (pending != null) return pending;
    final future =
        WebSocket.connect(uri).timeout(kRelayConnectTimeout).then((socket) {
      _connecting = null;
      _ws = socket;
      socket.listen(_onMessage,
          onError: (_) => _teardown(), onDone: _teardown);
      return socket;
    }).catchError((Object e) {
      _connecting = null;
      throw e;
    });
    _connecting = future;
    return future;
  }

  void _onMessage(dynamic data) {
    try {
      final msg = jsonDecode(data as String) as List;
      if (msg.isEmpty) return;
      switch (msg[0]) {
        case 'OK':
          if (msg.length >= 3) {
            final completer = _pendingOks.remove(msg[1] as String);
            if (completer != null && !completer.isCompleted) {
              if (msg[2] == true) {
                completer.complete();
              } else {
                final reason = msg.length > 3 ? msg[3] : 'rejected';
                completer
                    .completeError(Exception('Relay rejected: $reason'));
              }
            }
          }
        case 'EVENT':
          if (msg.length >= 3) {
            _activeSubs[msg[1] as String]
                ?.onEvent(msg[2] as Map<String, dynamic>);
          }
        case 'EOSE':
        case 'CLOSED':
          if (msg.length >= 2) {
            _activeSubs[msg[1] as String]?.onEose();
          }
      }
    } catch (_) {}
  }

  void _teardown() {
    _ws = null;
    for (final completer in _pendingOks.values) {
      if (!completer.isCompleted) {
        completer.completeError(
            const SocketException('WebSocket closed before OK'));
      }
    }
    _pendingOks.clear();
    for (final sub in _activeSubs.values) {
      sub.onEose();
    }
    _activeSubs.clear();
  }

  void _armIdleTimer() {
    _idleTimer?.cancel();
    if (_closed || _pendingOps > 0) return;
    _idleTimer = Timer(kRelayIdleClose, () {
      if (_pendingOps == 0) {
        _ws?.close().catchError((_) => null);
        _ws = null;
      }
    });
  }

  void close() {
    _closed = true;
    _idleTimer?.cancel();
    _ws?.close().catchError((_) => null);
    _teardown();
  }

  /// Send ["EVENT", …] and await the relay's OK for this event id.
  Future<void> publishEvent(NostrEvent event) async {
    _pendingOps++;
    try {
      final ws = await _ensureConnected();
      final completer = Completer<void>();
      _pendingOks[event.id] = completer;
      ws.add(jsonEncode(['EVENT', event.toJson()]));
      try {
        await completer.future.timeout(kRelayResponseTimeout);
      } finally {
        _pendingOks.remove(event.id);
      }
      _recordSuccess();
    } catch (e) {
      _recordFailure();
      rethrow;
    } finally {
      _pendingOps--;
      _armIdleTimer();
    }
  }

  /// REQ the tag, collect EVENTs until EOSE, return the highest-seq record
  /// this relay has (a relay may hold several via replaceable-event races).
  Future<SignedEndpointRecord?> fetchLatest(String tagHex) async {
    final all = await fetchAll(tagHex);
    SignedEndpointRecord? best;
    for (final r in all) {
      if (best == null || r.seq > best.seq) best = r;
    }
    return best;
  }

  /// REQ the tag, collect EVENTs until EOSE, return ALL valid records
  /// (one per Nostr pubkey / device).
  /// Like [fetchAll], but without interpreting the content.
  Future<List<Uint8List>> fetchAllRaw(String tagHex) async {
    final raw = <Uint8List>[];
    for (final eventJson in await _fetchEvents(tagHex)) {
      final event = NostrEvent.fromJson(eventJson);
      if (event == null) continue;
      try {
        raw.add(Uint8List.fromList(base64Decode(event.content)));
      } catch (_) {}
    }
    return raw;
  }

  Future<List<SignedEndpointRecord>> fetchAll(String tagHex) async {
    final results = <SignedEndpointRecord>[];
    for (final eventJson in await _fetchEvents(tagHex)) {
      final event = NostrEvent.fromJson(eventJson);
      if (event == null) continue;
      try {
        final record = SignedEndpointRecord.deserialize(
            Uint8List.fromList(base64Decode(event.content)));
        if (record != null) results.add(record);
      } catch (_) {}
    }
    return results;
  }

  /// Fetches the raw events for a tag. Common substructure of
  /// [fetchAll] and [fetchAllRaw] — interpreting the content does not belong
  /// in the fetch.
  Future<List<dynamic>> _fetchEvents(String tagHex) async {
    _pendingOps++;
    final subId = 'rv${_subCounter++}';
    try {
      final ws = await _ensureConnected();
      final sub = _ActiveSub();
      _activeSubs[subId] = sub;
      ws.add(jsonEncode(['REQ', subId, nostrTagFilter(tagHex)]));
      await sub.done.future
          .timeout(kRelayResponseTimeout, onTimeout: () {});
      try {
        _ws?.add(jsonEncode(['CLOSE', subId]));
      } catch (_) {}
      _recordSuccess();
      return sub.events;
    } catch (e) {
      _recordFailure();
      rethrow;
    } finally {
      _activeSubs.remove(subId);
      _pendingOps--;
      _armIdleTimer();
    }
  }

}

class _ActiveSub {
  final List<Map<String, dynamic>> events = [];
  final Completer<void> done = Completer<void>();

  void onEvent(Map<String, dynamic> event) => events.add(event);

  void onEose() {
    if (!done.isCompleted) done.complete();
  }
}

// ---------------------------------------------------------------------------
// Hex helpers (local, no peer_info dependency)
// ---------------------------------------------------------------------------

String _bytesToHex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _hexToBytes(String hex) {
  final result = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < result.length; i++) {
    result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return result;
}


/// The seam to the cold-start cascade (§11.3, stage A).
///
/// RESTORED 2026-08-22. This provider had been deleted in V4.1
/// — justified with §26.6.4, of which it later turned out
/// that it does not decide the cold start at all, but only how an
/// INVITATION resolves. The decision "all three sources" reverses the
/// clearing at this place.
///
/// The provider stays as it was: pooled connections, failure counting
/// per relay, throwaway key pairs per event (so that a query returns ALL
/// publishers instead of only the last one). New is only that
/// it can do raw bytes — the detour via the V3 record type was coupling,
/// not a necessity.
final class NostrRendezvous implements ExternalRendezvous {
  final NostrProvider provider;

  NostrRendezvous(this.provider);

  @override
  bool get isAvailable => provider.isAvailable;

  @override
  Future<void> publish(Uint8List lookupTag, Uint8List blob) =>
      provider.publishRaw(lookupTag, blob);

  @override
  Future<List<Uint8List>> resolve(Uint8List lookupTag) =>
      provider.resolveRaw(lookupTag);
}
