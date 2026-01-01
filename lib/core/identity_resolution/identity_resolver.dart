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
import 'package:cleona/core/identity_resolution/liveness_record.dart';
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Output of `IdentityResolver.resolve`. Eine Entry pro authorisiertem Device.
/// `addresses` kann leer sein, wenn Auth-Manifest gefunden wurde aber
/// Liveness-Lookup für das Device fehlschlug oder revoked-by-filter ist —
/// in dem Fall fällt `sendEnvelope` auf DV-Relay-Cascade an die deviceNodeId.
class ResolvedDevice {
  final Uint8List deviceNodeId;
  final List<PeerAddress> addresses;
  final int livenessPublishedAtMs;

  ResolvedDevice({
    required this.deviceNodeId,
    required this.addresses,
    required this.livenessPublishedAtMs,
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

  /// DHT-RPC-Channel. In Wave 4 (Phase 5 Integration) typisiert auf
  /// `CleonaNode`-Helper, hier `dynamic` für Test-Mocks. Erwartete API:
  ///   `Future<MessageEnvelope?> sendAndWait(MessageEnvelope envelope, peer)`
  final dynamic dhtRpc;

  /// Inflight-Dedup: userIdHex → in-flight Future. `whenComplete` entfernt
  /// den Eintrag — sowohl bei Success als auch bei Error.
  final Map<String, Future<List<ResolvedDevice>>> _inflight = {};

  IdentityResolver({required this.routingTable, required this.dhtRpc});

  /// Auflöse `userId` zu einer Liste authorisierter Devices.
  /// Bei Cache-Hit (frisch < 1h) sofortige Rückgabe ohne DHT-Lookup.
  /// Bei Lookup-Failure (kein Auth-Manifest) leere Liste — Caller soll
  /// MessageQueue.enqueue() für ack-worthy Envelopes.
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
    final cachedPeers = routingTable.getAllPeersForUserId(userId);
    final fresh = cachedPeers.where(_cacheStillFresh).toList();
    if (fresh.isNotEmpty) {
      return fresh
          .map((p) => ResolvedDevice(
                deviceNodeId: p.nodeId,
                addresses: List.of(p.addresses),
                livenessPublishedAtMs: p.lastSeen.millisecondsSinceEpoch,
              ))
          .toList();
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

    // ── 3. Liveness-Lookup parallel pro authorisiertem Device ──────────
    final results = await Future.wait(
      authManifest.authorizedDeviceNodeIds.map((deviceId) async {
        final live = await _lookupLiveness(userId, deviceId);
        if (live == null) {
          // Liveness fehlt — Device authorisiert aber keine aktuelle
          // Adresse. Sender soll auf DV-Relay-Cascade fallen.
          return ResolvedDevice(
            deviceNodeId: deviceId,
            addresses: const [],
            livenessPublishedAtMs: 0,
          );
        }

        // Authorized-List-Filter (Revocation-Schutz). Liveness deviceNodeId
        // muss in AuthManifest.authorizedDeviceNodeIds enthalten sein,
        // sonst gefilterten Eintrag mit leeren Adressen zurückgeben.
        final isAuthorized = authManifest.authorizedDeviceNodeIds
            .any((d) => _bytesEqual(d, live.deviceNodeId));
        if (!isAuthorized) {
          return ResolvedDevice(
            deviceNodeId: deviceId,
            addresses: const [],
            livenessPublishedAtMs: 0,
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

  /// K=10 closest replicators zum Schlüssel parallel anfragen, höchste seq
  /// gewinnt (Tie-Break über publishedAtMs). Spec §4.3 Schritt 1.
  ///
  /// Fallback (Test-Skeleton-Kompat): wenn routingTable keine Peers hat,
  /// Single-Call mit `peer=null` — Mocks akzeptieren das.
  Future<AuthManifest?> _lookupAuthManifest(Uint8List userId) async {
    final envelope = proto.MessageEnvelope()
      ..messageType = proto.MessageType.IDENTITY_AUTH_RETRIEVE
      ..encryptedPayload = (proto.IdentityAuthRetrieveRequest()..userId = userId)
          .writeToBuffer();

    final authKey = _authKey(userId);
    final closest = routingTable.findClosestPeers(authKey, count: 10);
    final responses = closest.isEmpty
        ? <dynamic>[await dhtRpc.sendAndWait(envelope, null)]
        : await Future.wait(closest.map((peer) async {
            try {
              return await dhtRpc.sendAndWait(envelope, peer);
            } catch (_) {
              return null;
            }
          }));

    AuthManifest? best;
    for (final response in responses) {
      if (response == null) continue;
      if (response.messageType != proto.MessageType.IDENTITY_AUTH_RESPONSE) {
        continue;
      }
      try {
        final p = proto.AuthManifestProto.fromBuffer(response.encryptedPayload);
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
    final envelope = proto.MessageEnvelope()
      ..messageType = proto.MessageType.IDENTITY_LIVE_RETRIEVE
      ..encryptedPayload = (proto.IdentityLiveRetrieveRequest()
            ..userId = userId
            ..deviceNodeId = deviceNodeId)
          .writeToBuffer();

    final closest =
        routingTable.findClosestPeers(_liveKey(userId, deviceNodeId), count: 10);
    final responses = closest.isEmpty
        ? <dynamic>[await dhtRpc.sendAndWait(envelope, null)]
        : await Future.wait(closest.map((peer) async {
            try {
              return await dhtRpc.sendAndWait(envelope, peer);
            } catch (_) {
              return null;
            }
          }));

    LivenessRecord? best;
    for (final response in responses) {
      if (response == null) continue;
      if (response.messageType != proto.MessageType.IDENTITY_LIVE_RESPONSE) {
        continue;
      }
      try {
        final p =
            proto.LivenessRecordProto.fromBuffer(response.encryptedPayload);
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

  // ── DHT-Schlüssel-Hashing (gleicher Pattern wie IdentityPublisher) ────────

  Uint8List _authKey(Uint8List userId) => _hashWithPrefix('auth', userId);

  Uint8List _liveKey(Uint8List userId, Uint8List deviceNodeId) {
    final combined = Uint8List(userId.length + deviceNodeId.length);
    combined.setRange(0, userId.length, userId);
    combined.setRange(userId.length, combined.length, deviceNodeId);
    return _hashWithPrefix('live', combined);
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
