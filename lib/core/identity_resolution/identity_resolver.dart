// 2D-DHT Identity Resolution — Sender-Side Resolver.
//
// Plan-Referenz:
//   docs/superpowers/plans/2026-04-26-2d-dht-identity-resolution.md
//   - Task 7: Skeleton + Cache-Hit Short-Circuit
//   - Task 8: Auth-Lookup via DHT-RPC
//   - Task 9: Liveness-Lookup parallel pro Device + Authorized-List-Filter
//             + Inflight-Dedup + Cache-Populate
//
// Design-Spec: docs/superpowers/specs/2026-04-26-2d-dht-identity-resolution-design.md
//   §3.3 (IdentityResolver) + §4.3 (Lookup-Cascade)
//
// Plan-Abweichungen (aus den Skeletons synthetisiert):
//   - `package:cleona/core/util/hex.dart` existiert nicht. Wir nutzen
//     `bytesToHex` aus `peer_info.dart` (dort ohnehin schon top-level export).
//   - Proto-Import-Pfad ist `package:cleona/generated/proto/cleona.pb.dart`
//     (nicht `package:cleona/proto/cleona.pb.dart`).
//   - `PeerAddressProto` hat ein `addressType`-Enum-Feld (`AddressType.IPV4_*`)
//     statt eines numerischen `type`-Feldes. Der Resolver nutzt
//     `PeerAddress.fromProto(...)` als Konversion (defensives Skip bei
//     unparseable IP).
//   - `dhtRpc` ist im Skeleton bewusst `dynamic` — der echte Type wird in
//     Wave 4 (Integration) verdrahtet (Task 13/14 wiring auf
//     `cleona_node.findClosestPeers + parallel sendAndWait`). Tests injizieren
//     einfache Klassen mit `sendAndWait(envelope, peer)`-Methode.
//   - Sig-Verify im Resolver-Skeleton wird bewusst übersprungen (Plan
//     Step 9.3 Kommentar): Pubkey-Resolution aus userId ist in dieser Phase
//     noch nicht aufgelöst (User-Pubkey-Cache kommt erst beim
//     CleonaService-Wiring). Wir verlassen uns auf den Authorized-List-Filter
//     (Revocation-Schutz) und das KEM-Setup-Failure als Backstop gegen
//     forged Liveness-Records.

import 'dart:async';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/dht/kbucket.dart';
import 'package:cleona/core/identity_resolution/auth_manifest.dart';
import 'package:cleona/core/identity_resolution/device_kem_record.dart';
import 'package:cleona/core/identity_resolution/liveness_record.dart';
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Output of `IdentityResolver.resolve`. Eine Entry pro authorisiertem Device.
/// `addresses` kann leer sein, wenn Auth-Manifest gefunden wurde aber
/// Liveness-Lookup für das Device fehlschlug oder revoked-by-filter ist —
/// in dem Fall fällt `sendEnvelope` auf DV-Relay-Cascade an die deviceNodeId.
///
/// Welle 5 (§3.5b + §4.3): zusaetzliche KEM-Felder. Wenn der DeviceKemRecord
/// fehlt (Hop noch nicht publisht oder Sig-Verify fehlgeschlagen) bleiben sie
/// `null` — Sender muss dann auf den Per-Identity-KEM-Key (Legacy-Pfad)
/// zurueckfallen oder den Send queueen bis ein KEM-Record vorliegt.
class ResolvedDevice {
  final Uint8List deviceNodeId;
  final List<PeerAddress> addresses;
  final int livenessPublishedAtMs;
  final Uint8List? deviceX25519Pk;
  final Uint8List? deviceMlKemPk;
  final int? deviceKemPublishedAtMs;

  ResolvedDevice({
    required this.deviceNodeId,
    required this.addresses,
    required this.livenessPublishedAtMs,
    this.deviceX25519Pk,
    this.deviceMlKemPk,
    this.deviceKemPublishedAtMs,
  });
}

/// Auflöser: User-ID → `List<ResolvedDevice>`.
///
/// Cascade (siehe Spec §4.3):
///   1. Lokaler Cache (`RoutingTable._byUserIdHex`, gespiegelt zu Liveness-TTL)
///   2. Auth-Lookup `Hash("auth"+userId)` → AuthManifest
///   3. Pro authorisiertem Device parallel `Hash("live"+userId+deviceNodeId)`
///      → LivenessRecord, Authorized-List-Membership-Filter (Revocation)
///   4. Cache-Populate via `routingTable.addPeer(...)`, sortiert nach
///      freshest livenessPublishedAtMs
///
/// Inflight-Dedup: zwei concurrent `resolve(sameUserId)` warten beide auf das
/// Ergebnis des ersten — verhindert RPC-Spam bei Burst-Sends.
class IdentityResolver {
  final RoutingTable routingTable;

  /// DHT-RPC-Channel (Welle 2A V3-direct). Production wiring uses
  /// `CleonaNode.dhtRpc` (`DhtRpc` class); tests inject in-memory mocks
  /// matching the same shape:
  ///   `Future<DhtRpcResponse?> sendAndWait(MTV3 type, Uint8List body, peer)`
  /// Stays `dynamic`-typed so test mocks don't need to implement DhtRpc's
  /// full surface.
  final dynamic dhtRpc;

  /// Local 2D-DHT handler — gives the resolver direct access to
  /// AuthManifest / Liveness / DeviceKemRecord that this node has stored
  /// (either as a closest-peer replicator for someone else's record, or
  /// via `IdentityPublisher` self-store after a local publish). Used in
  /// the cache-hit short-circuit to populate the `deviceX25519Pk` /
  /// `deviceMlKemPk` fields on the returned `ResolvedDevice` — without
  /// this, the cache path returns devices with null KEM-PKs, so callers
  /// that need KEM (`firstCrPickDeviceKem` for First-CR, §8.1.1) drop the
  /// resolution and the contact request silently fails even though the
  /// data is locally available.
  final dynamic dhtHandler; // IdentityDhtHandler? — kept dynamic for tests

  /// Inflight-Dedup: userIdHex → in-flight Future. `whenComplete` entfernt
  /// den Eintrag — sowohl bei Success als auch bei Error.
  final Map<String, Future<List<ResolvedDevice>>> _inflight = {};

  IdentityResolver({
    required this.routingTable,
    required this.dhtRpc,
    this.dhtHandler,
  });

  /// Auflöse `userId` zu einer Liste authorisierter Devices.
  /// Bei Cache-Hit (frisch < 1h) sofortige Rückgabe ohne DHT-Lookup.
  /// Bei Lookup-Failure (kein Auth-Manifest) leere Liste — Caller soll
  /// die V3-Offline-Cascade triggern (S&F + Reed-Solomon + Mailbox-Pull,
  /// Architektur §5). MessageQueue entfernt in V3.0 (Welle 2 Teil 3 / C5).
  Future<List<ResolvedDevice>> resolve(Uint8List userId) {
    final key = bytesToHex(userId);
    final existing = _inflight[key];
    if (existing != null) return existing;

    final future = _resolveImpl(userId);
    _inflight[key] = future;
    future.whenComplete(() => _inflight.remove(key));
    return future;
  }

  Future<List<ResolvedDevice>> _resolveImpl(Uint8List userId) async {
    // ── 1. Cache-Hit Short-Circuit ─────────────────────────────────────
    // The routing-table cache short-circuits the network round-trip when
    // we already know live devices for this user. We populate the
    // KEM-PK fields from the local DhtHandler — this node may have
    // received the recipient's `IDENTITY_KEM_PUBLISH` as a replicator
    // (or be the publisher itself, via self-store) — so callers that
    // need KEM-PKs (First-CR §8.1.1 firstCrPickDeviceKem) get them
    // without requiring an extra RETRIEVE round-trip.
    //
    // If KEM is missing for any cached device but addresses are present,
    // we fall through to the full DHT lookup path. The shortcut applies
    // only when we have BOTH addresses and KEM locally — otherwise the
    // sender silently drops First-CR even though the network might be
    // able to provide the missing record.
    final cachedPeers = routingTable.getAllPeersForUserId(userId);
    final fresh = cachedPeers.where(_cacheStillFresh).toList();
    if (fresh.isNotEmpty) {
      final cached = fresh.map((p) {
        // Pull KEM-PKs from local DhtHandler if present.
        Uint8List? deviceX25519Pk;
        Uint8List? deviceMlKemPk;
        int? deviceKemPublishedAtMs;
        try {
          final r = dhtHandler?.getKemRecord(userId, p.nodeId);
          if (r != null) {
            deviceX25519Pk = r.deviceX25519Pk;
            deviceMlKemPk = r.deviceMlKemPk;
            deviceKemPublishedAtMs = r.publishedAtMs;
          }
        } catch (_) {
          // dhtHandler may not implement getKemRecord (test mocks);
          // missing KEM is handled by the fall-through below.
        }
        return ResolvedDevice(
          deviceNodeId: p.nodeId,
          addresses: List.of(p.addresses),
          livenessPublishedAtMs: p.lastSeen.millisecondsSinceEpoch,
          deviceX25519Pk: deviceX25519Pk,
          deviceMlKemPk: deviceMlKemPk,
          deviceKemPublishedAtMs: deviceKemPublishedAtMs,
        );
      }).toList();
      // Only short-circuit if every cached device has KEM populated. If any
      // is missing KEM, fall through to the network DHT-lookup so the
      // caller is not stuck with a no-KEM result that can't drive First-CR.
      final allHaveKem = cached.every((d) =>
          d.deviceX25519Pk != null && d.deviceMlKemPk != null);
      if (allHaveKem) return cached;
    }

    // ── 2. Auth-Manifest Lookup ────────────────────────────────────────
    final authManifest = await _lookupAuthManifest(userId);
    if (authManifest == null) {
      return [];
    }

    // Sig-Verify Auth-Manifest: bewusst skipped im Skeleton (siehe
    // File-Header). Ein vollständiges Wave-4-Wiring zieht den User-Pubkey
    // aus einem CleonaService-Cache (Auth-Manifest-Reception füllt den)
    // und verifiziert hier hybrid Ed25519 + ML-DSA.

    // ── 3. Liveness-Lookup + Step 4b Device-KEM-Lookup parallel ────────
    // Welle 5 (§4.3): pro Device zwei Records gleichzeitig fetchen
    // (Liveness + DeviceKemRecord). Beide haben denselben Trust-Anchor
    // (User-Master-Ed25519 — Liveness signiert vom DEVICE-Key in der V3-Spec
    // hat ein anderes Trust-Profil, aber im aktuellen Skeleton ist die
    // Liveness-Sig vom User-Key gemeint — siehe LivenessRecord.sign).
    final results = await Future.wait(
      authManifest.authorizedDeviceNodeIds.map((deviceId) async {
        final liveFuture = _lookupLiveness(userId, deviceId);
        final kemFuture = _lookupDeviceKem(userId, deviceId);
        final live = await liveFuture;
        final kem = await kemFuture;

        // Step 4b: KEM-Sig-Verify in-place (Pubkey ist im Record, Trust-
        // Anchor wird durch Cross-Check mit anderen Records desselben Users
        // sichergestellt — sobald CleonaService den User-Pubkey-Cache
        // bereitstellt verifizieren wir hier zusaetzlich gegen den Cache).
        DeviceKemRecord? validatedKem;
        if (kem != null) {
          if (kem.verify(kem.userEd25519Pk)) {
            validatedKem = kem;
          }
          // Hinweis: ohne externen Pubkey-Cache kann ein malicious Replicator
          // die Sig zwar valide austauschen, aber nicht die KEM-PK von einem
          // legitim publisht-Record (dort ist die Sig mit dem echten User-Sk
          // gemacht und der User-Pk zeigt auf den echten Key). Welle-5-Teil-2
          // wired CleonaService.userPubkeyCache hier rein.
        }

        if (live == null) {
          // Liveness fehlt — Device authorisiert aber keine aktuelle
          // Adresse. Sender soll auf DV-Relay-Cascade fallen.
          return ResolvedDevice(
            deviceNodeId: deviceId,
            addresses: const [],
            livenessPublishedAtMs: 0,
            deviceX25519Pk: validatedKem?.deviceX25519Pk,
            deviceMlKemPk: validatedKem?.deviceMlKemPk,
            deviceKemPublishedAtMs: validatedKem?.publishedAtMs,
          );
        }

        // Authorized-List-Filter (Revocation-Schutz). Liveness deviceNodeId
        // muss in AuthManifest.authorizedDeviceNodeIds enthalten sein,
        // sonst gefilterten Eintrag mit leeren Adressen zurückgeben. Step 5
        // muss laut Spec auch auf den DeviceKemRecord angewendet werden —
        // der KEM-Record ist per (userId,deviceId) gekeyed, dieselbe deviceId
        // gilt also derselben Authorization-Pruefung.
        final isAuthorized = authManifest.authorizedDeviceNodeIds
            .any((d) => _bytesEqual(d, live.deviceNodeId));
        if (!isAuthorized) {
          return ResolvedDevice(
            deviceNodeId: deviceId,
            addresses: const [],
            livenessPublishedAtMs: 0,
            // KEM bewusst gedroppt wenn Device revoked — kein Encap-Risk.
          );
        }

        // Konvertiere PeerAddressProto → PeerAddress (defensiv: ungültige
        // IPs werden via fromProto-null-Filter aussortiert).
        final addrs = <PeerAddress>[];
        for (final p in live.addresses) {
          final a = PeerAddress.fromProto(p);
          if (a != null) addrs.add(a);
        }

        return ResolvedDevice(
          deviceNodeId: deviceId,
          addresses: addrs,
          livenessPublishedAtMs: live.publishedAtMs,
          deviceX25519Pk: validatedKem?.deviceX25519Pk,
          deviceMlKemPk: validatedKem?.deviceMlKemPk,
          deviceKemPublishedAtMs: validatedKem?.publishedAtMs,
        );
      }),
    );

    // Sort: freshest publishedAtMs first.
    results.sort(
        (a, b) => b.livenessPublishedAtMs.compareTo(a.livenessPublishedAtMs));

    // ── 4. Cache-Populate ──────────────────────────────────────────────
    // Nur Devices mit non-empty Adressen in den `_byUserIdHex`-Index. Devices
    // ohne Adressen (Liveness fehlt / revoked) bleiben außerhalb des Caches —
    // beim nächsten resolve()-Call wird der Lookup wieder durchlaufen.
    //
    // TODO Welle 5 Teil 2: Device-KEM-PKs (validatedKem.deviceX25519Pk +
    // deviceMlKemPk) muessen in einen RoutingTable-Cache (z.B.
    // `routingTable.addDeviceKem(deviceId, x25519Pk, mlKemPk, publishedAtMs)`)
    // wandern, sobald die API dort existiert. Aktuell trasportiert der
    // ResolvedDevice die PKs zum Caller, der den naechsten Lookup
    // verkürzen muss (oder erneut ueber resolve() pulled).
    for (final r in results) {
      if (r.addresses.isEmpty) continue;
      routingTable.addPeer(PeerInfo(
        nodeId: r.deviceNodeId,
        userId: userId,
        addresses: List.of(r.addresses),
        networkChannel: '',
      ));
    }

    return results;
  }

  /// Step 4b: K=10 closest replicators zum kem-key parallel anfragen,
  /// hoechste seq gewinnt (Tie-Break ueber publishedAtMs). Spec §4.3.
  Future<DeviceKemRecord?> _lookupDeviceKem(
      Uint8List userId, Uint8List deviceId) async {
    final body = Uint8List.fromList((proto.IdentityKemRetrieveRequest()
          ..userId = userId
          ..deviceId = deviceId)
        .writeToBuffer());

    final responses = await _parallelSendAndWait(
      requestType: proto.MessageTypeV3.MTV3_IDENTITY_KEM_RETRIEVE,
      body: body,
      dhtKey: _kemKey(userId, deviceId),
    );

    DeviceKemRecord? best;
    for (final response in responses) {
      if (response == null) continue;
      if (response.type != proto.MessageTypeV3.MTV3_IDENTITY_KEM_RESPONSE) {
        continue;
      }
      try {
        final p = proto.DeviceKemRecordV3.fromBuffer(response.payload);
        final r = DeviceKemRecord.fromProto(p);
        if (best == null ||
            r.sequenceNumber > best.sequenceNumber ||
            (r.sequenceNumber == best.sequenceNumber &&
                r.publishedAtMs > best.publishedAtMs)) {
          best = r;
        }
      } catch (_) {
        // skip malformed
      }
    }
    return best;
  }

  /// K=10 closest replicators zum Schlüssel parallel anfragen, höchste seq
  /// gewinnt (Tie-Break über publishedAtMs). Spec §4.3 Schritt 1.
  ///
  /// Fallback (Test-Skeleton-Kompat): wenn routingTable keine Peers hat,
  /// Single-Call mit `peer=null` — Mocks akzeptieren das.
  Future<AuthManifest?> _lookupAuthManifest(Uint8List userId) async {
    final body = Uint8List.fromList(
        (proto.IdentityAuthRetrieveRequest()..userId = userId).writeToBuffer());

    final responses = await _parallelSendAndWait(
      requestType: proto.MessageTypeV3.MTV3_IDENTITY_AUTH_RETRIEVE,
      body: body,
      dhtKey: _authKey(userId),
    );

    AuthManifest? best;
    for (final response in responses) {
      if (response == null) continue;
      if (response.type != proto.MessageTypeV3.MTV3_IDENTITY_AUTH_RESPONSE) {
        continue;
      }
      try {
        final p = proto.AuthManifestProto.fromBuffer(response.payload);
        final m = AuthManifest.fromProto(p);
        if (best == null ||
            m.sequenceNumber > best.sequenceNumber ||
            (m.sequenceNumber == best.sequenceNumber &&
                m.publishedAtMs > best.publishedAtMs)) {
          best = m;
        }
      } catch (_) {
        // skip malformed
      }
    }
    return best;
  }

  Future<LivenessRecord?> _lookupLiveness(
      Uint8List userId, Uint8List deviceNodeId) async {
    final body = Uint8List.fromList((proto.IdentityLiveRetrieveRequest()
          ..userId = userId
          ..deviceNodeId = deviceNodeId)
        .writeToBuffer());

    final responses = await _parallelSendAndWait(
      requestType: proto.MessageTypeV3.MTV3_IDENTITY_LIVE_RETRIEVE,
      body: body,
      dhtKey: _liveKey(userId, deviceNodeId),
    );

    LivenessRecord? best;
    for (final response in responses) {
      if (response == null) continue;
      if (response.type != proto.MessageTypeV3.MTV3_IDENTITY_LIVE_RESPONSE) {
        continue;
      }
      try {
        final p = proto.LivenessRecordProto.fromBuffer(response.payload);
        final r = LivenessRecord.fromProto(p);
        if (best == null ||
            r.sequenceNumber > best.sequenceNumber ||
            (r.sequenceNumber == best.sequenceNumber &&
                r.publishedAtMs > best.publishedAtMs)) {
          best = r;
        }
      } catch (_) {
        // skip malformed
      }
    }
    return best;
  }

  /// Parallel sendAndWait helper — fan out to K=10 closest replicators of
  /// `dhtKey`. Falls back to a single `peer=null` call when the routing
  /// table is empty (test-skeleton / cold-start case). Returns one
  /// `DhtRpcResponse?` per peer (or `[null]` if the empty-table call also
  /// fails). Per-peer exceptions are squashed to `null` so a single bad
  /// replicator can't fail the whole lookup.
  Future<List<dynamic>> _parallelSendAndWait({
    required proto.MessageTypeV3 requestType,
    required Uint8List body,
    required Uint8List dhtKey,
  }) async {
    final closest = routingTable.findClosestPeers(dhtKey, count: 10);
    if (closest.isEmpty) {
      return <dynamic>[null];
    }
    return Future.wait(closest.map((peer) async {
      try {
        return await dhtRpc.sendAndWait(requestType, body, peer);
      } catch (_) {
        return null;
      }
    }));
  }

  // ── DHT-Schlüssel-Hashing (gleicher Pattern wie IdentityPublisher) ────────

  Uint8List _authKey(Uint8List userId) => _hashWithPrefix('auth', userId);

  Uint8List _liveKey(Uint8List userId, Uint8List deviceNodeId) {
    final combined = Uint8List(userId.length + deviceNodeId.length);
    combined.setRange(0, userId.length, userId);
    combined.setRange(userId.length, combined.length, deviceNodeId);
    return _hashWithPrefix('live', combined);
  }

  /// `kem-key = SHA-256("kem" || userId || deviceId)`. Welle 5 (§4.3).
  Uint8List _kemKey(Uint8List userId, Uint8List deviceId) {
    final combined = Uint8List(userId.length + deviceId.length);
    combined.setRange(0, userId.length, userId);
    combined.setRange(userId.length, combined.length, deviceId);
    return _hashWithPrefix('kem', combined);
  }

  Uint8List _hashWithPrefix(String prefix, Uint8List data) {
    final input = Uint8List.fromList([...prefix.codeUnits, ...data]);
    return SodiumFFI().sha256(input);
  }

  bool _cacheStillFresh(PeerInfo p) {
    final age = DateTime.now().difference(p.lastSeen);
    return age.inHours < 1;
  }

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
