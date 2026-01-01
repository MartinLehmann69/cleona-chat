import 'dart:typed_data';
import 'package:cleona/core/crypto/network_secret.dart';
import 'package:cleona/core/network/peer_info.dart';

/// K-bucket size (standard Kademlia parameter).
const int kBucketSize = 20;

/// Max addresses per peer. Prevents unbounded accumulation from gossip.
const int maxAddressesPerPeer = 15;

/// Number of bits in node IDs (SHA-256 → 256 bits).
const int idBitLength = 256;

/// Compute XOR distance between two 32-byte node IDs.
Uint8List xorDistance(Uint8List a, Uint8List b) {
  assert(a.length == 32 && b.length == 32);
  final result = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    result[i] = a[i] ^ b[i];
  }
  return result;
}

/// Compare two XOR distances. Returns negative if a < b, 0 if equal, positive if a > b.
int compareDistance(Uint8List a, Uint8List b) {
  for (var i = 0; i < 32; i++) {
    if (a[i] < b[i]) return -1;
    if (a[i] > b[i]) return 1;
  }
  return 0;
}

/// Get the bucket index for a given XOR distance (0-255).
/// Returns the index of the highest set bit.
int bucketIndex(Uint8List distance) {
  for (var i = 0; i < 32; i++) {
    if (distance[i] == 0) continue;
    // Find highest bit in this byte
    var byte = distance[i];
    var bit = 7;
    while (bit >= 0 && (byte & (1 << bit)) == 0) {
      bit--;
    }
    return 255 - (i * 8 + (7 - bit));
  }
  return 0; // Distance is zero (same node)
}

/// Result of a `KBucket.addPeer` call. `added` mirrors the previous boolean
/// return; `evicted` is the stale peer that was displaced to make room
/// (null on simple updates or when the bucket had spare capacity).
/// The outer `RoutingTable` uses `evicted` to keep its secondary index
/// consistent.
class KBucketAddResult {
  final bool added;
  final PeerInfo? evicted;
  const KBucketAddResult(this.added, this.evicted);
}

/// A single k-bucket in the Kademlia routing table.
class KBucket {
  final List<PeerInfo> peers = [];

  /// Add or update a peer. `result.added` is true if the peer was
  /// added/updated; `result.evicted` is the stale peer that had to be
  /// displaced (bucket-full path), or null.
  KBucketAddResult addPeer(PeerInfo peer) {
    final existingIdx = peers.indexWhere(
      (p) => _bytesEqual(p.nodeId, peer.nodeId),
    );

    if (existingIdx >= 0) {
      final existing = peers[existingIdx];
      // Architecture §17.3 PK provenance precedence:
      // - Never downgrade firstParty signing keys to thirdParty.
      // - When new claim is firstParty (or equal-or-higher source) it wins.
      // - When existing is firstParty and new is thirdParty, keep existing.
      final existingIsFirstParty = existing.pkSource == PkSource.firstParty;
      final newIsThirdParty = peer.pkSource == PkSource.thirdParty;
      if (existingIsFirstParty && newIsThirdParty) {
        // Existing has authoritative PK; foreign claim must not overwrite.
        peer.ed25519PublicKey = existing.ed25519PublicKey;
        peer.mlDsaPublicKey = existing.mlDsaPublicKey;
        // Welle 3 (§17.3): Device-Sig PKs follow the same provenance gate.
        peer.deviceEd25519PublicKey = existing.deviceEd25519PublicKey;
        peer.deviceMlDsaPublicKey = existing.deviceMlDsaPublicKey;
        peer.pkSource = existing.pkSource;
        peer.pkStale = existing.pkStale;
        // D3 (§13.1.2): Admission-Nonce folgt dem Device-PK, den sie
        // zertifiziert — gleiche Provenance-Schranke.
        peer.deviceIdPowNonce = existing.deviceIdPowNonce;
        peer.idPowVerified = existing.idPowVerified;
      } else {
        // Preserve known PK if new entry lacks it (regardless of provenance —
        // missing fields just inherit; provenance reflects the actual source).
        if (peer.ed25519PublicKey == null || peer.ed25519PublicKey!.isEmpty) {
          peer.ed25519PublicKey = existing.ed25519PublicKey;
          if (peer.pkSource == PkSource.none) peer.pkSource = existing.pkSource;
        }
        if (peer.mlDsaPublicKey == null || peer.mlDsaPublicKey!.isEmpty) {
          peer.mlDsaPublicKey = existing.mlDsaPublicKey;
        }
        // Welle 3: same inherit-when-missing rule for Device-Sig PKs.
        if (peer.deviceEd25519PublicKey == null ||
            peer.deviceEd25519PublicKey!.isEmpty) {
          peer.deviceEd25519PublicKey = existing.deviceEd25519PublicKey;
        }
        if (peer.deviceMlDsaPublicKey == null ||
            peer.deviceMlDsaPublicKey!.isEmpty) {
          peer.deviceMlDsaPublicKey = existing.deviceMlDsaPublicKey;
        }
        // D3 (§13.1.2): inherit-when-missing fuer die Admission-Nonce; das
        // Verified-Flag wandert nur mit, wenn die Nonce unveraendert bleibt
        // (neue Nonce → Re-Verifikation im Node-Layer).
        if (peer.deviceIdPowNonce == null ||
            peer.deviceIdPowNonce!.isEmpty) {
          peer.deviceIdPowNonce = existing.deviceIdPowNonce;
          peer.idPowVerified = existing.idPowVerified;
        } else if (existing.idPowVerified &&
            _bytesEqual(peer.deviceIdPowNonce!,
                existing.deviceIdPowNonce ?? Uint8List(0))) {
          peer.idPowVerified = true;
        }
        // §5.10.5: firstParty PK arrival clears stale status.
        if (peer.pkSource == PkSource.firstParty) peer.pkStale = false;
      }
      // X25519 + ML-KEM are KEM keys (encryption, not signing) — no provenance
      // gating. Inherit from existing if missing.
      if (peer.x25519PublicKey == null || peer.x25519PublicKey!.isEmpty) {
        peer.x25519PublicKey = existing.x25519PublicKey;
      }
      if (peer.mlKemPublicKey == null || peer.mlKemPublicKey!.isEmpty) {
        peer.mlKemPublicKey = existing.mlKemPublicKey;
      }
      // Public IP merge: firstParty self-broadcast is authoritative — if the
      // peer itself no longer advertises a publicIp, clear it (the old one
      // may be stale/unreachable). ThirdParty hearsay with missing publicIp
      // just means the gossiper didn't know it — preserve existing.
      //
      // Exception (M-4): if the firstParty broadcast has publicIp='' but we
      // already hold a non-private publicIp (learned via STUN / NAT-egress
      // from the UDP source address), the peer simply doesn't know its own
      // public IP. Clearing it would lose the only reachable address for
      // cross-NAT sends. Preserve the existing STUN-observed IP instead.
      if (peer.pkSource == PkSource.firstParty) {
        if (peer.publicIp.isEmpty && existing.publicIp.isNotEmpty && !_isPrivateIp(existing.publicIp)) {
          peer.publicIp = existing.publicIp;
          peer.publicPort = existing.publicPort;
        }
      } else if (peer.publicIp.isEmpty || _isPrivateIp(peer.publicIp)) {
        if (existing.publicIp.isNotEmpty && !_isPrivateIp(existing.publicIp)) {
          peer.publicIp = existing.publicIp;
          peer.publicPort = existing.publicPort;
        }
      }
      // Preserve authoritative local IP — PeerListPush from nodes that
      // only know this peer via relay will have localIp="" which must
      // NOT overwrite a valid address learned from direct PING/PONG.
      if (peer.localIp.isEmpty && existing.localIp.isNotEmpty) {
        peer.localIp = existing.localIp;
        peer.localPort = existing.localPort;
      }
      // Address list merge — provenance-aware (K-1/K-2).
      // Empty new list (e.g. legacy peers without addresses[]) → fully
      // inherit existing list as before.
      if (peer.addresses.isEmpty && existing.addresses.isNotEmpty) {
        peer.addresses.addAll(existing.addresses);
      } else if (peer.addresses.isNotEmpty && existing.addresses.isNotEmpty) {
        final existingByKey = <String, PeerAddress>{};
        for (final a in existing.addresses) {
          existingByKey['${a.ip}:${a.port}'] = a;
        }

        if (peer.pkSource == PkSource.firstParty) {
          // Peer is authoritative about its own addresses.
          // Transfer local counters for matching ip:port pairs.
          for (final fresh in peer.addresses) {
            final old = existingByKey.remove('${fresh.ip}:${fresh.port}');
            if (old != null) {
              fresh.successCount = old.successCount;
              fresh.failCount = old.failCount;
              fresh.score = old.score;
              fresh.lastSuccess = old.lastSuccess;
              fresh.lastAttempt = old.lastAttempt;
              fresh.lastReceivedAt = old.lastReceivedAt;
            }
          }
          // Addresses no longer advertised by the peer but confirmed by
          // received traffic: keep WITHOUT backoff (the NAT mapping is
          // provably live — symmetric NAT assigns different ports per
          // destination, so the peer can't know our specific mapping).
          // Addresses without receive confirmation get stale backoff.
          for (final orphan in existingByKey.values) {
            if (orphan.lastReceivedAt == null &&
                orphan.consecutiveFailures < 1) {
              orphan.consecutiveFailures = 1;
            }
            peer.addresses.add(orphan);
          }
          // Cap orphan accumulation: drop worst-scoring entries above budget.
          if (peer.addresses.length > maxAddressesPerPeer) {
            peer.addresses.sort((a, b) =>
                b.effectiveScore.compareTo(a.effectiveScore));
            peer.addresses.removeRange(
                maxAddressesPerPeer, peer.addresses.length);
          }
        } else {
          // thirdParty / none: gossip must not replace locally-confirmed
          // addresses. Existing list is the base; add genuinely new
          // addresses from gossip with zero counters.
          final merged = List<PeerAddress>.from(existing.addresses);
          final mergedKeys = <String>{};
          for (final a in merged) {
            mergedKeys.add('${a.ip}:${a.port}');
          }
          for (final fresh in peer.addresses) {
            final key = '${fresh.ip}:${fresh.port}';
            if (!mergedKeys.contains(key)) {
              merged.add(fresh);
              mergedKeys.add(key);
            }
          }
          // Cap: drop lowest-scoring unverified addresses when over budget.
          if (merged.length > maxAddressesPerPeer) {
            merged.sort((a, b) {
              // Verified (lastSuccess != null) before unverified
              final aV = a.lastSuccess != null ? 0 : 1;
              final bV = b.lastSuccess != null ? 0 : 1;
              if (aV != bV) return aV.compareTo(bV);
              return b.effectiveScore.compareTo(a.effectiveScore);
            });
            merged.removeRange(maxAddressesPerPeer, merged.length);
          }
          peer.addresses
            ..clear()
            ..addAll(merged);
        }
      }
      // Move to end (most recently seen)
      peers.removeAt(existingIdx);
      peers.add(peer);
      return const KBucketAddResult(true, null);
    }

    if (peers.length < kBucketSize) {
      peers.add(peer);
      return const KBucketAddResult(true, null);
    }

    // Bucket full — evict oldest if it's stale (> 4 hours)
    final staleCutoff = DateTime.now().subtract(const Duration(hours: 4));
    if (peers.first.lastSeen.isBefore(staleCutoff)) {
      final evicted = peers.removeAt(0);
      peers.add(peer);
      return KBucketAddResult(true, evicted);
    }

    return const KBucketAddResult(false, null); // Bucket full, no stale entries
  }

  void removePeer(Uint8List nodeId) {
    peers.removeWhere((p) => _bytesEqual(p.nodeId, nodeId));
  }

  bool containsPeer(Uint8List nodeId) {
    return peers.any((p) => _bytesEqual(p.nodeId, nodeId));
  }

  PeerInfo? getPeer(Uint8List nodeId) {
    for (final p in peers) {
      if (_bytesEqual(p.nodeId, nodeId)) return p;
    }
    return null;
  }
}

/// The Kademlia routing table: 256 k-buckets indexed by XOR distance.
class RoutingTable {
  final Uint8List ownNodeId; // Primary node ID (used for XOR distance)
  final Set<String> _localNodeIds = {}; // All local identity node IDs (hex)
  final List<KBucket> buckets = List.generate(idBitLength, (_) => KBucket());

  /// Default peer filter for `findClosestPeers`. When set, only peers
  /// passing this filter are returned for DHT operations (publish, retrieve,
  /// gossip). Peers that fail the filter stay in the table (persistence for
  /// restart) but are excluded from active operations. Set by CleonaNode to
  /// `isPeerConfirmed` after startup.
  bool Function(PeerInfo)? defaultPeerFilter;

  /// Secondary index: userIdHex → all peers (one per device) sharing that
  /// stable identity. Maintained in lockstep with the k-buckets so that
  /// `getPeerByUserId` / `getAllPeersForUserId` run in O(1) amortized,
  /// not an O(n) bucket scan. Peers with `userId == null` (legacy,
  /// pre-§26-Phase-2) are not indexed here and fall through to the
  /// linear fallback in the accessors below.
  final Map<String, List<PeerInfo>> _byUserIdHex = {};

  /// Listeners notified when a NEW peer (previously unknown deviceNodeId)
  /// is added to the table. Refresh of an existing entry does NOT fire.
  /// Used by §2.2.4 IdentityPublisher to wake parked cold-start retries.
  final List<void Function(PeerInfo)> _onPeerAddedListeners = [];

  RoutingTable(this.ownNodeId) {
    _localNodeIds.add(_bytesToHex(ownNodeId));
  }

  /// Register a listener invoked once per newly added peer (not on refresh).
  void addOnPeerAddedListener(void Function(PeerInfo) cb) {
    _onPeerAddedListeners.add(cb);
  }

  /// Remove a previously registered listener.
  void removeOnPeerAddedListener(void Function(PeerInfo) cb) {
    _onPeerAddedListeners.remove(cb);
  }

  /// Register a local node ID (identity) so it won't be added to the table.
  void addLocalNodeId(Uint8List nodeId) {
    _localNodeIds.add(_bytesToHex(nodeId));
  }

  /// Unregister a local node ID.
  void removeLocalNodeId(Uint8List nodeId) {
    _localNodeIds.remove(_bytesToHex(nodeId));
  }

  /// Check if a node ID belongs to a local identity.
  bool isLocalNode(Uint8List nodeId) {
    return _localNodeIds.contains(_bytesToHex(nodeId));
  }

  static String _bytesToHex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  /// Add or update a peer in the appropriate bucket.
  bool addPeer(PeerInfo peer) {
    if (isLocalNode(peer.nodeId)) return false; // Don't add any local identity
    // Defense-in-depth: HMAC filters wrong-network packets at transport layer,
    // but check channel string too in case of PeerList exchange.
    final ch = NetworkSecret.channel.name;
    if (peer.networkChannel.isNotEmpty && peer.networkChannel != ch) return false;

    // Capture the existing entry's userIdHex BEFORE the bucket update, so we
    // can unindex it if the user identity changes (or the entry is replaced
    // with a new PeerInfo object carrying a different userId).
    final existing = getPeer(peer.nodeId);
    final existingUserHex = existing?.userIdHex;
    final wasNew = existing == null;

    final dist = xorDistance(ownNodeId, peer.nodeId);
    final idx = bucketIndex(dist);
    final result = buckets[idx].addPeer(peer);
    if (!result.added) return false;

    // Secondary-index maintenance: reflect the post-add state.
    if (existing != null && existingUserHex != null) {
      if (existingUserHex == peer.userIdHex) {
        // Same userId refresh — update in place.
        _unindexFromUser(existingUserHex, peer.nodeId);
      } else {
        // Different userId (multi-identity: same device, new userId seen).
        // Keep the old userId indexed so both entries remain reachable via
        // resolveUserToDevices. Update the old list's peer reference to the
        // freshly-added object (the old PeerInfo was replaced in the bucket).
        final oldList = _byUserIdHex[existingUserHex];
        if (oldList != null) {
          final i =
              oldList.indexWhere((p) => _bytesEqual(p.nodeId, peer.nodeId));
          if (i >= 0) oldList[i] = peer; // keep entry, update reference
        }
      }
    }
    // A stale eviction may have displaced a DIFFERENT peer with its own
    // userIdHex — unindex that one too so we don't leak dangling refs.
    final evicted = result.evicted;
    if (evicted != null) {
      final evictedHex = evicted.userIdHex;
      if (evictedHex != null) _unindexFromUser(evictedHex, evicted.nodeId);
    }
    _indexPeer(peer);
    // Notify listeners only when a previously unknown deviceNodeId joined —
    // refresh of an existing entry must NOT trigger republishes.
    if (wasNew) {
      for (final cb in _onPeerAddedListeners) {
        try {
          cb(peer);
        } catch (_) {
          // Listener errors must not affect bucket state.
        }
      }
    }
    return true;
  }

  /// Remove a peer from the routing table.
  void removePeer(Uint8List nodeId) {
    final existing = getPeer(nodeId);
    if (existing != null) {
      final hex = existing.userIdHex;
      if (hex != null) _unindexFromUser(hex, nodeId);
    }
    final dist = xorDistance(ownNodeId, nodeId);
    final idx = bucketIndex(dist);
    buckets[idx].removePeer(nodeId);
  }

  /// Update a peer's userId after it has been added to the routing table.
  /// Keeps the secondary index consistent. Use this in preference to a
  /// direct `peer.userId = ...` assignment — otherwise lookups by the new
  /// userId will still go through the legacy linear fallback.
  void setPeerUserId(PeerInfo peer, Uint8List newUserId) {
    final oldHex = peer.userIdHex;
    peer.userId = newUserId;
    final newHex = peer.userIdHex;
    if (oldHex == newHex) return;
    if (oldHex != null) _unindexFromUser(oldHex, peer.nodeId);
    _indexPeer(peer);
  }

  /// Register a peer under an additional userId without changing its primary
  /// `userId` field. Used for multi-identity daemons: a single device nodeId
  /// can host several user identities — each one must appear in the secondary
  /// index so that `getAllPeersForUserId` / `getPeerByUserId` finds the device
  /// regardless of which identity the caller is looking up (§26 §3.1).
  void addExtraUserIdIndex(Uint8List deviceId, Uint8List extraUserId) {
    final peer = getPeer(deviceId);
    if (peer == null) return;
    final hex = _bytesToHex(extraUserId);
    final list = _byUserIdHex.putIfAbsent(hex, () => []);
    if (!list.any((p) => _bytesEqual(p.nodeId, deviceId))) {
      list.add(peer);
    }
  }

  void _indexPeer(PeerInfo peer) {
    final hex = peer.userIdHex;
    if (hex == null) return;
    final list = _byUserIdHex.putIfAbsent(hex, () => []);
    // Dedup by deviceNodeId in case a re-add slipped past the existing-check.
    if (!list.any((p) => _bytesEqual(p.nodeId, peer.nodeId))) {
      list.add(peer);
    }
  }

  void _unindexFromUser(String hex, Uint8List nodeId) {
    final list = _byUserIdHex[hex];
    if (list == null) return;
    list.removeWhere((p) => _bytesEqual(p.nodeId, nodeId));
    if (list.isEmpty) _byUserIdHex.remove(hex);
  }

  /// D4 (§4.3): default per-IP-group cap for diversity-aware replicator
  /// selection. With K=10 and cap 2, an attacker confined to one IP group
  /// holds at most 2 replicator slots while >= 8 candidates from other
  /// groups exist.
  static const int diversityMaxPerIpGroup = 2;

  /// Find the K closest peers to a target ID.
  /// Partitions into recent (seen < 10 min) and stale, preferring recent.
  ///
  /// `maxPerIpGroup` (D4, §4.3 Replicator & lookup diversity): when set,
  /// the selection prefers IP-subnet diversity — at most that many peers
  /// per `PeerInfo.ipDiversityGroup` are taken in preference order; the
  /// remaining slots are filled with the closest skipped peers, so the
  /// selection NEVER returns fewer peers than the undiversified one
  /// (single-subnet LANs keep full replication). Used by the identity
  /// publish/lookup paths and the fragment-store replicator selections;
  /// the DHT FIND_NODE response path stays distance-pure (null).
  List<PeerInfo> findClosestPeers(Uint8List targetId,
      {int count = kBucketSize,
      bool Function(PeerInfo)? filter,
      bool includeStale = false,
      int? maxPerIpGroup}) {
    final now = DateTime.now();
    final recentCutoff = now.subtract(const Duration(minutes: 10));

    final effectiveFilter = filter ?? (includeStale ? null : defaultPeerFilter);
    final allPeers = <PeerInfo>[];
    for (final bucket in buckets) {
      for (final p in bucket.peers) {
        if (effectiveFilter != null && !effectiveFilter(p)) continue;
        allPeers.add(p);
      }
    }

    // Sort by XOR distance to target
    allPeers.sort((a, b) {
      final distA = xorDistance(a.nodeId, targetId);
      final distB = xorDistance(b.nodeId, targetId);
      return compareDistance(distA, distB);
    });

    // Partition into recent and stale
    final recent = allPeers.where((p) => p.lastSeen.isAfter(recentCutoff)).toList();
    final stale = allPeers.where((p) => !p.lastSeen.isAfter(recentCutoff)).toList();

    // D4: diversity-aware take over the preference ordering (recent in
    // distance order, then stale in distance order).
    if (maxPerIpGroup != null) {
      return _diverseTake(
          <PeerInfo>[...recent, ...stale], count, maxPerIpGroup);
    }

    // Prefer recent peers
    final result = <PeerInfo>[];
    result.addAll(recent.take(count));
    if (result.length < count) {
      result.addAll(stale.take(count - result.length));
    }
    return result;
  }

  /// D4 greedy diversity selection: walk `ordered` (already in preference
  /// order), take a peer unless its IP group already holds `maxPerGroup`
  /// picks; afterwards fill remaining slots with the closest skipped peers
  /// in order. Total count is always `min(count, ordered.length)` — exactly
  /// what the undiversified take returns.
  static List<PeerInfo> _diverseTake(
      List<PeerInfo> ordered, int count, int maxPerGroup) {
    final result = <PeerInfo>[];
    final skipped = <PeerInfo>[];
    final groupCounts = <String, int>{};
    for (final p in ordered) {
      if (result.length >= count) break;
      final g = p.ipDiversityGroup;
      final c = groupCounts[g] ?? 0;
      if (c >= maxPerGroup) {
        skipped.add(p);
        continue;
      }
      groupCounts[g] = c + 1;
      result.add(p);
    }
    for (final p in skipped) {
      if (result.length >= count) break;
      result.add(p);
    }
    return result;
  }

  /// Get a specific peer by node ID (deviceNodeId).
  PeerInfo? getPeer(Uint8List nodeId) {
    final dist = xorDistance(ownNodeId, nodeId);
    final idx = bucketIndex(dist);
    return buckets[idx].getPeer(nodeId);
  }

  /// Get a peer by userId (stable identity, same across all devices).
  /// O(1) via the secondary index. When a user has several devices online
  /// (phone + laptop), returns the **freshest** entry (max lastSeen) so
  /// sends go to the most-recently-active device rather than whichever
  /// happened to be first in iteration order.
  ///
  /// Legacy fallback: peers stored before §26 Phase 2 may have
  /// `userId == null` and rely on `nodeId == userId`. They are not in the
  /// secondary index and are matched via a linear scan only when the
  /// index has no hit.
  PeerInfo? getPeerByUserId(Uint8List userId) {
    final hex = _bytesToHex(userId);
    final list = _byUserIdHex[hex];
    if (list != null && list.isNotEmpty) {
      var freshest = list[0];
      for (var i = 1; i < list.length; i++) {
        if (list[i].lastSeen.isAfter(freshest.lastSeen)) freshest = list[i];
      }
      return freshest;
    }
    for (final bucket in buckets) {
      for (final p in bucket.peers) {
        if (p.userId == null && _bytesEqual(p.nodeId, userId)) return p;
      }
    }
    return null;
  }

  /// Like [getPeer] but returns null when `lastSeen` is older than [maxAge].
  /// Forces callers in send-paths to fall through to a fresh resolver lookup
  /// instead of sending to a stale cached address. Address records are only
  /// authoritative for one Liveness-TTL window after their last refresh.
  PeerInfo? getFreshPeer(Uint8List nodeId, {required Duration maxAge}) {
    final p = getPeer(nodeId);
    if (p == null) return null;
    if (DateTime.now().difference(p.lastSeen) > maxAge) return null;
    return p;
  }

  /// Like [getPeerByUserId] but returns null when no entry's `lastSeen`
  /// falls within [maxAge]. Same rationale as [getFreshPeer].
  PeerInfo? getFreshPeerByUserId(Uint8List userId, {required Duration maxAge}) {
    final p = getPeerByUserId(userId);
    if (p == null) return null;
    if (DateTime.now().difference(p.lastSeen) > maxAge) return null;
    return p;
  }

  /// §26 Phase 3: Get ALL peers for a userId (one per device).
  /// O(1) via the secondary index. Returns a defensive copy so callers
  /// can't mutate the index by editing the list.
  List<PeerInfo> getAllPeersForUserId(Uint8List userId) {
    final hex = _bytesToHex(userId);
    final result = <PeerInfo>[];
    final list = _byUserIdHex[hex];
    if (list != null) result.addAll(list);
    // Legacy fallback: peers with userId == null whose nodeId matches.
    for (final bucket in buckets) {
      for (final p in bucket.peers) {
        if (p.userId == null && _bytesEqual(p.nodeId, userId)) {
          if (!result.any((r) => _bytesEqual(r.nodeId, p.nodeId))) {
            result.add(p);
          }
        }
      }
    }
    return result;
  }

  /// §26 Phase 4: Remove a specific peer by its nodeId (deviceNodeId).
  /// Returns true if the peer was found and removed.
  bool removePeerByNodeId(Uint8List nodeId) {
    final existing = getPeer(nodeId);
    if (existing != null) {
      final hex = existing.userIdHex;
      if (hex != null) _unindexFromUser(hex, nodeId);
    }
    final dist = xorDistance(ownNodeId, nodeId);
    final idx = bucketIndex(dist);
    final bucket = buckets[idx];
    final before = bucket.peers.length;
    bucket.removePeer(nodeId);
    return bucket.peers.length < before;
  }

  /// Get all peers in the routing table.
  List<PeerInfo> get allPeers {
    final result = <PeerInfo>[];
    for (final bucket in buckets) {
      result.addAll(bucket.peers);
    }
    return result;
  }

  /// Get the total number of peers.
  int get peerCount {
    var count = 0;
    for (final bucket in buckets) {
      count += bucket.peers.length;
    }
    return count;
  }

  /// Timestamp of the last `pruneStaleSeeds` sweep. Gates the deep GC to
  /// at most once per `minInterval` — the normal `prune(4h)` is already
  /// doing the heavy lifting for non-seed peers, so the seed sweep is
  /// pure hygiene.
  DateTime? _lastSeedGcAt;

  /// Evict **protected seed peers** whose lastSeen is older than [maxAge].
  /// Unlike `prune(maxAge)` (which skips `isProtectedSeed`), this GC
  /// exists to drop retired devices whose QR/NFC/URI seed would otherwise
  /// stick around forever — §27 Doze-resilience only needs a seed peer
  /// to survive *days*, not *months*. Gated to `minInterval` (default
  /// one hour) so the periodic-maintenance path stays cheap.
  /// Returns the number of seed peers actually removed.
  int pruneStaleSeeds(
    Duration maxAge, {
    Duration minInterval = const Duration(hours: 1),
  }) {
    final now = DateTime.now();
    if (_lastSeedGcAt != null && now.difference(_lastSeedGcAt!) < minInterval) {
      return 0;
    }
    _lastSeedGcAt = now;
    final cutoff = now.subtract(maxAge);
    var removed = 0;
    for (final bucket in buckets) {
      bucket.peers.removeWhere((p) {
        if (!p.isProtectedSeed || !p.lastSeen.isBefore(cutoff)) return false;
        final hex = p.userIdHex;
        if (hex != null) _unindexFromUser(hex, p.nodeId);
        removed++;
        return true;
      });
    }
    return removed;
  }

  /// Prune peers older than the given duration.
  /// Protected seed peers (from QR/NFC scans) are never pruned — they ensure
  /// the device can re-bootstrap after Android Doze (§27). Long-idle seeds
  /// are GC'd separately by `pruneStaleSeeds`.
  /// Returns the number of pruned peers.
  int prune(Duration maxAge) {
    final cutoff = DateTime.now().subtract(maxAge);
    var pruned = 0;
    for (final bucket in buckets) {
      bucket.peers.removeWhere((p) {
        if (p.isProtectedSeed || !p.lastSeen.isBefore(cutoff)) return false;
        final hex = p.userIdHex;
        if (hex != null) _unindexFromUser(hex, p.nodeId);
        pruned++;
        return true;
      });
    }
    return pruned;
  }

  /// Evict peers that exceed both a failure threshold AND an age threshold.
  /// A peer is evicted only if:
  ///   - `consecutiveRouteFailures >= failureThreshold`
  ///   - `lastSeen` is older than `ageThreshold`
  ///   - `hasAliveRoutes` returns false (caller provides a checker so this
  ///     class does not depend on DvRoutingTable directly)
  ///   - peer is NOT a protected seed
  ///
  /// Called lazily during other operations, not on a timer.
  /// Returns the list of evicted deviceNodeId hex strings.
  List<String> evictStalePeers({
    int failureThreshold = 10,
    Duration ageThreshold = const Duration(minutes: 15),
    bool Function(String deviceHex)? hasAliveRoutes,
  }) {
    final cutoff = DateTime.now().subtract(ageThreshold);
    final evicted = <String>[];

    for (final bucket in buckets) {
      bucket.peers.removeWhere((p) {
        if (p.isProtectedSeed) return false;
        if (p.consecutiveRouteFailures < failureThreshold) return false;
        if (!p.lastSeen.isBefore(cutoff)) return false;
        if (hasAliveRoutes != null && hasAliveRoutes(p.nodeIdHex)) return false;

        final hex = p.userIdHex;
        if (hex != null) _unindexFromUser(hex, p.nodeId);
        evicted.add(p.nodeIdHex);
        return true;
      });
    }

    return evicted;
  }

  /// Serialize to JSON for persistence.
  List<Map<String, dynamic>> toJson() {
    return allPeers.map((p) => p.toJson()).toList();
  }

  /// Load peers from JSON.
  void loadFromJson(List<dynamic> json) {
    for (final entry in json) {
      try {
        final peer = PeerInfo.fromJson(entry as Map<String, dynamic>);
        addPeer(peer);
      } catch (_) {
        // Skip invalid entries
      }
    }
  }

  /// WIN-4: One-shot audit of persisted addresses on daemon start.
  /// Removes addresses that we know cannot be routable from this host:
  ///   - Carrier-NAT (100.64.0.0/10 RFC 6598, 192.0.0.0/24)
  ///   - Private IPv4 outside of any local /24 (e.g. 10.0.2.x emulator
  ///     NAT addresses on a 192.168.x host)
  /// Returns total count of pruned addresses (for logging).
  ///
  /// Public IPv4 (non-private, non-CGNAT) and all IPv6 are kept as-is —
  /// the cost-sort and address-score machinery handles their decay.
  /// Hairpinning-self-loop pruning (own public IP) requires NAT-discovery
  /// to have completed; deferred to a later audit-pass.
  int auditAddresses(Iterable<String> currentLocalIps) {
    final localIps = currentLocalIps.toList();
    var pruned = 0;
    for (final peer in allPeers) {
      peer.addresses.removeWhere((addr) {
        if (PeerAddress.isCarrierNAT(addr.ip)) {
          pruned++;
          return true;
        }
        // Private IPv4 not in any local /24 → unreachable from here.
        // Skip the check for IPv6 entirely (no /24 concept).
        if (!addr.ip.contains(':') &&
            PeerAddress.isPrivateIp(addr.ip) &&
            !PeerAddress.isInLocalSubnet(addr.ip, localIps)) {
          pruned++;
          return true;
        }
        return false;
      });
    }
    return pruned;
  }
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _isPrivateIp(String ip) {
  if (ip.contains(':')) {
    final lower = ip.toLowerCase();
    return lower.startsWith('fe80:') || lower.startsWith('fc') ||
           lower.startsWith('fd') || lower == '::1';
  }
  if (ip.startsWith('10.')) return true;
  if (ip.startsWith('172.')) {
    final second = int.tryParse(ip.split('.')[1]);
    if (second != null && second >= 16 && second <= 31) return true;
  }
  if (ip.startsWith('192.168.')) return true;
  if (ip.startsWith('127.')) return true;
  if (ip.startsWith('100.')) {
    final second = int.tryParse(ip.split('.')[1]) ?? 0;
    if (second >= 64 && second <= 127) return true;
  }
  if (ip.startsWith('192.0.0.')) return true;
  return false;
}
