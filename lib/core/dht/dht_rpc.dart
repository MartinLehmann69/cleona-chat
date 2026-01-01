import 'dart:async';
import 'dart:typed_data';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Pending RPC request awaiting response.
class _PendingRpc {
  final Completer<proto.MessageEnvelope> completer;
  final Timer timer;
  _PendingRpc(this.completer, this.timer);
}

/// DHT RPC layer: handles request/response matching with timeouts.
class DhtRpc {
  final CLogger _log;
  final Map<String, _PendingRpc> _pending = {};

  /// Callback to actually send an envelope.
  Future<bool> Function(proto.MessageEnvelope envelope, PeerInfo peer)? sendFunction;

  /// RTT tracking per peer (exponential moving average).
  final Map<String, Duration> _rttMap = {};

  /// Read-only access to RTT map for statistics dashboard.
  Map<String, Duration> get rttMap => Map.unmodifiable(_rttMap);

  DhtRpc({String? profileDir})
      : _log = CLogger.get('dht-rpc', profileDir: profileDir);

  /// Send a DHT RPC and wait for response.
  Future<proto.MessageEnvelope?> sendAndWait(
    proto.MessageEnvelope request,
    PeerInfo peer, {
    Duration? timeout,
  }) async {
    final rpcKey = _rpcKey(request);
    final rtt = _rttMap[bytesToHex(peer.nodeId)] ?? const Duration(seconds: 1);
    final effectiveTimeout = timeout ?? (rtt * 2 + const Duration(milliseconds: 50));

    final completer = Completer<proto.MessageEnvelope>();
    final timer = Timer(effectiveTimeout, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('DHT RPC timeout to ${peer.nodeIdHex.substring(0, 8)}'));
      }
      _pending.remove(rpcKey);
    });

    _pending[rpcKey] = _PendingRpc(completer, timer);

    // Also register wildcard keys for all addresses
    final targets = peer.allConnectionTargets();
    for (final addr in targets) {
      final altKey = '${addr.ip}:${addr.port}:${request.messageType.value}';
      _pending[altKey] = _PendingRpc(completer, timer);
    }

    final sent = await sendFunction?.call(request, peer);
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
  bool handleResponse(proto.MessageEnvelope response, String remoteAddress, int remotePort) {
    // Try multiple keys for matching
    final keys = [
      _rpcKey(response),
      '$remoteAddress:$remotePort:${_requestTypeFor(response.messageType).value}',
    ];

    for (final key in keys) {
      final pending = _pending.remove(key);
      if (pending != null && !pending.completer.isCompleted) {
        pending.timer.cancel();
        pending.completer.complete(response);
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
      final newMs = (existing.inMilliseconds * 0.8 + rtt.inMilliseconds * 0.2).round();
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

  String _rpcKey(proto.MessageEnvelope envelope) {
    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
    return '$senderHex:${envelope.messageType.value}:${envelope.timestamp}';
  }

  /// Map response type back to request type for matching.
  proto.MessageType _requestTypeFor(proto.MessageType responseType) {
    switch (responseType) {
      case proto.MessageType.DHT_PONG:
        return proto.MessageType.DHT_PING;
      case proto.MessageType.DHT_FIND_NODE_RESPONSE:
        return proto.MessageType.DHT_FIND_NODE;
      case proto.MessageType.DHT_STORE_RESPONSE:
        return proto.MessageType.DHT_STORE;
      case proto.MessageType.DHT_FIND_VALUE_RESPONSE:
        return proto.MessageType.DHT_FIND_VALUE;
      case proto.MessageType.FRAGMENT_STORE_ACK:
        return proto.MessageType.FRAGMENT_STORE;
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
