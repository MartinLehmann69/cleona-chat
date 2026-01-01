import 'dart:async';
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
  Future<bool> Function(
          proto.MessageTypeV3 type, Uint8List body, PeerInfo peer)?
      sendFunction;

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
      _pending.remove(rpcKey);
    });

    _pending[rpcKey] = _PendingRpc(completer, timer);

    // Also register wildcard keys for all addresses so the response-side
    // matcher can find us by remote-address even when senderId in the
    // response doesn't match the peer's nodeId.
    final targets = peer.allConnectionTargets();
    for (final addr in targets) {
      final altKey = '${addr.ip}:${addr.port}:${requestType.value}';
      _pending[altKey] = _PendingRpc(completer, timer);
    }

    final sent = await sendFunction?.call(requestType, body, peer);
    if (sent != true) {
      timer.cancel();
      _pending.remove(rpcKey);
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
    int remotePort,
  ) {
    final requestType = _requestTypeFor(responseType);
    // Try multiple keys for matching.
    final keys = [
      _rpcKey(senderDeviceId, requestType),
      '$remoteAddress:$remotePort:${requestType.value}',
    ];

    for (final key in keys) {
      final pending = _pending.remove(key);
      if (pending != null && !pending.completer.isCompleted) {
        pending.timer.cancel();
        pending.completer.complete((type: responseType, payload: payload));
        // Clean up all aliases
        _pending.removeWhere((k, v) => v.completer == pending.completer);
        return true;
      }
    }
    return false;
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
