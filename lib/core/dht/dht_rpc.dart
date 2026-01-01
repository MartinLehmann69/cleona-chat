import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Response delivered to the awaiting caller. Carries the V3 message type and
/// the inner payload bytes (the InfrastructureFrameV3 inner already, NOT the
/// outer NetworkPacketV3 wrapper). Decoding the typed proto (e.g.
/// `IdentityAuthResponse.fromBuffer(...)`) is the caller's responsibility.
typedef DhtRpcResponse = ({proto.MessageTypeV3 type, Uint8List payload});

/// Pending RPC request awaiting response.
class _PendingRpc {
  final Completer<DhtRpcResponse> completer;
  final Timer timer;
  _PendingRpc(this.completer, this.timer);
}

/// DHT RPC layer: handles request/response matching with timeouts.
///
/// V3 contract: keyed by `MessageTypeV3`. Requests carry `(type, body, peer)`;
/// responses arrive as `(type, payload)` tuples. The internal pending-table
/// is keyed by V3 type so the receive-side bridge in
/// `cleona_node._bridgeInfraResponseToDhtRpc` can route directly.
class DhtRpc {
  final CLogger _log;
  final Map<String, _PendingRpc> _pending = {};

  /// Callback to actually send an RPC. The DhtRpc layer hands off
  /// `(type, body, peer)` and the wireup in `cleona_node._init` plumbs that
  /// through the §2.3.5 InfrastructureFrame pipeline (Outer Device-Sig +
  /// KEM-AEAD inner).
  /// `messageId` is generated here and MUST end up in the outgoing
  /// InfrastructureFrame's `messageId` field — it is the correlator the
  /// responder echoes back in `inReplyTo` (§2.3.5).
  Future<bool> Function(proto.MessageTypeV3 type, Uint8List body, PeerInfo peer,
      Uint8List messageId)? sendFunction;

  final Random _rand = Random.secure();

  Uint8List _newMessageId() {
    final b = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      b[i] = _rand.nextInt(256);
    }
    return b;
  }

  /// RTT tracking per peer (exponential moving average).
  final Map<String, Duration> _rttMap = {};

  /// Read-only access to RTT map for statistics dashboard.
  Map<String, Duration> get rttMap => Map.unmodifiable(_rttMap);

  DhtRpc({String? profileDir})
      : _log = CLogger.get('dht-rpc', profileDir: profileDir);

  /// Send a DHT RPC and wait for response.
  ///
  /// `requestType` is the V3 request type (e.g. `MTV3_IDENTITY_AUTH_RETRIEVE`).
  /// `body` is the inner payload bytes (typed-proto-serialized).
  /// `peer` is the recipient.
  ///
  /// Returns the response tuple (`type` is the matched response type,
  /// `payload` is the inner bytes) on success, or `null` on send failure /
  /// timeout / generic error.
  Future<DhtRpcResponse?> sendAndWait(
    proto.MessageTypeV3 requestType,
    Uint8List body,
    PeerInfo peer, {
    Duration? timeout,
  }) async {
    // §2.3.5 — primary correlator. The legacy `(peer, type)` and
    // `(ip:port, type)` keys stay registered as a fallback for peers that do
    // not yet echo `inReplyTo`, but they are ambiguous by construction: two
    // concurrent lookups of the same type to the same peer (two FIND_NODE on
    // different targets — Kademlia routine) collide on them.
    final messageId = _newMessageId();
    final msgKey = bytesToHex(messageId);
    final rpcKey = _rpcKey(peer.nodeId, requestType);
    final rtt = _rttMap[bytesToHex(peer.nodeId)] ?? const Duration(seconds: 1);
    final effectiveTimeout =
        timeout ?? (rtt * 2 + const Duration(milliseconds: 50));

    final completer = Completer<DhtRpcResponse>();
    // Race-guard: if the timer fires while sendFunction is still executing
    // (awaited below), the completeError has no listener yet → zone-level
    // unhandled error → daemon exit(99). A no-op error sink prevents zone
    // escalation; the await below still catches the error normally.
    unawaited(completer.future.then((_) {}, onError: (_) {}));
    final timer = Timer(effectiveTimeout, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException(
            'DHT RPC timeout to ${peer.nodeIdHex.substring(0, 8)}'));
      }
      // Remove exactly OUR entries. The previous `_pending.remove(rpcKey)`
      // removed whatever sat under the shared key — after a second request
      // to the same (peer, type) had overwritten it, the expiring timer of
      // the FIRST request deregistered the SECOND one, which then always ran
      // into a timeout even though its response was on the wire.
      _dropEntriesOf(completer);
    });

    final entry = _PendingRpc(completer, timer);
    _pending[msgKey] = entry;

    // Legacy fallback keys. An overwrite here must not leave the previous
    // caller hanging: its primary messageId key survives, so it can still be
    // matched by an `inReplyTo`-capable responder — and if the responder is
    // legacy, its own timer resolves it.
    _pending[rpcKey] = entry;
    for (final addr in peer.allConnectionTargets()) {
      _pending['${addr.ip}:${addr.port}:${requestType.value}'] = entry;
    }

    final sent = await sendFunction?.call(requestType, body, peer, messageId);
    if (sent != true) {
      timer.cancel();
      _dropEntriesOf(completer);
      return null;
    }

    final startTime = DateTime.now();
    try {
      final response = await completer.future;
      // Update RTT
      final elapsed = DateTime.now().difference(startTime);
      _updateRtt(peer.nodeId, elapsed);
      return response;
    } on TimeoutException {
      _log.debug('RPC timeout to ${peer.nodeIdHex.substring(0, 8)}');
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Handle an incoming response, matching it to a pending request.
  ///
  /// `responseType` is the V3 response type (e.g. `MTV3_IDENTITY_AUTH_RESPONSE`).
  /// `payload` is the inner payload bytes from the InfrastructureFrameV3.
  /// `senderDeviceId` is the device-id of the responder (from the outer
  /// frame); used as the primary matching key. `remoteAddress`/`remotePort`
  /// are the wire-source of the packet, used as a fallback matcher.
  bool handleResponse(
    proto.MessageTypeV3 responseType,
    Uint8List payload,
    Uint8List senderDeviceId,
    String remoteAddress,
    int remotePort, {
    Uint8List? inReplyTo,
  }) {
    final requestType = _requestTypeFor(responseType);
    // §2.3.5 — `inReplyTo` first. It is unambiguous; the two tuple keys below
    // are the pre-V3.1.159 fallback and can match the wrong pending request
    // when two same-type lookups to the same peer are in flight.
    final keys = <String>[
      if (inReplyTo != null && inReplyTo.isNotEmpty) bytesToHex(inReplyTo),
      _rpcKey(senderDeviceId, requestType),
      '$remoteAddress:$remotePort:${requestType.value}',
    ];

    for (final key in keys) {
      final pending = _pending[key];
      if (pending != null && !pending.completer.isCompleted) {
        pending.timer.cancel();
        pending.completer.complete((type: responseType, payload: payload));
        _dropEntriesOf(pending.completer);
        return true;
      }
    }
    // Stale aliases of an already-completed request: drop them so a late
    // duplicate cannot keep resurfacing.
    for (final key in keys) {
      final p = _pending[key];
      if (p != null && p.completer.isCompleted) _pending.remove(key);
    }
    return false;
  }

  /// Remove every pending entry (primary key + all legacy aliases) that
  /// belongs to [c]. Identity comparison, not equality — two different
  /// requests never share a completer.
  void _dropEntriesOf(Completer<DhtRpcResponse> c) {
    _pending.removeWhere((_, v) => identical(v.completer, c));
  }

  void _updateRtt(Uint8List nodeId, Duration rtt) {
    final key = bytesToHex(nodeId);
    final existing = _rttMap[key];
    if (existing != null) {
      // Exponential moving average: 0.8 * old + 0.2 * new
      final newMs = (existing.inMilliseconds * 0.8 + rtt.inMilliseconds * 0.2)
          .round();
      _rttMap[key] = Duration(milliseconds: newMs);
    } else {
      _rttMap[key] = rtt;
    }
  }

  /// Public RTT update — used by AckTracker to feed the shared RTT map.
  void updateRtt(Uint8List nodeId, Duration rtt) => _updateRtt(nodeId, rtt);

  Duration getRtt(Uint8List nodeId) {
    return _rttMap[bytesToHex(nodeId)] ?? const Duration(seconds: 1);
  }

  /// Pending-table key: `peerHex:requestTypeValue`. The InfrastructureFrame
  /// has no timestamp field, and the (peer, type) tuple is sufficient for
  /// RPC matching given that callers don't issue duplicate concurrent
  /// requests for the same (peer, type) pair.
  String _rpcKey(Uint8List peerNodeId, proto.MessageTypeV3 requestType) {
    final peerHex = bytesToHex(peerNodeId);
    return '$peerHex:${requestType.value}';
  }

  /// Map response type back to request type for matching.
  proto.MessageTypeV3 _requestTypeFor(proto.MessageTypeV3 responseType) {
    switch (responseType) {
      case proto.MessageTypeV3.MTV3_DHT_PONG:
        return proto.MessageTypeV3.MTV3_DHT_PING;
      case proto.MessageTypeV3.MTV3_DHT_FIND_NODE_RESPONSE:
        return proto.MessageTypeV3.MTV3_DHT_FIND_NODE;
      case proto.MessageTypeV3.MTV3_DHT_STORE_RESPONSE:
        return proto.MessageTypeV3.MTV3_DHT_STORE;
      case proto.MessageTypeV3.MTV3_DHT_FIND_VALUE_RESPONSE:
        return proto.MessageTypeV3.MTV3_DHT_FIND_VALUE;
      case proto.MessageTypeV3.MTV3_FRAGMENT_STORE_ACK:
        return proto.MessageTypeV3.MTV3_FRAGMENT_STORE;
      case proto.MessageTypeV3.MTV3_FRAGMENT_RETRIEVE_RESPONSE:
        return proto.MessageTypeV3.MTV3_FRAGMENT_RETRIEVE;
      case proto.MessageTypeV3.MTV3_IDENTITY_AUTH_RESPONSE:
        return proto.MessageTypeV3.MTV3_IDENTITY_AUTH_RETRIEVE;
      case proto.MessageTypeV3.MTV3_IDENTITY_LIVE_RESPONSE:
        return proto.MessageTypeV3.MTV3_IDENTITY_LIVE_RETRIEVE;
      case proto.MessageTypeV3.MTV3_IDENTITY_KEM_RESPONSE:
        return proto.MessageTypeV3.MTV3_IDENTITY_KEM_RETRIEVE;
      default:
        return responseType;
    }
  }

  void dispose() {
    for (final pending in _pending.values) {
      pending.timer.cancel();
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(StateError('DhtRpc disposed'));
      }
    }
    _pending.clear();
  }
}
