import 'dart:async';
import 'dart:typed_data';
import 'package:cleona/core/dht/dht_rpc.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Pending ACK entry for an outgoing message.
class _PendingAck {
  final String messageIdHex;
  final String recipientNodeIdHex;
  final List<PeerAddress> usedAddresses;
  final DateTime sendTimestamp;
  final Timer timer;
  final Completer<bool> completer;

  /// null = direct send, non-null = relay nextHop nodeIdHex.
  final String? viaNextHopHex;

  /// 1 = direct, 2+ = relay (used for timeout calculation).
  final int estimatedHops;

  /// Serialized envelope for re-queue on ACK timeout (RUDP Light retry).
  /// Architecture Section 2.4.3: "On timeout → try next route."
  final Uint8List? serializedEnvelope;
  final Uint8List? recipientNodeId;

  _PendingAck({
    required this.messageIdHex,
    required this.recipientNodeIdHex,
    required this.usedAddresses,
    required this.sendTimestamp,
    required this.timer,
    required this.completer,
    this.viaNextHopHex,
    this.estimatedHops = 1,
    this.serializedEnvelope,
    this.recipientNodeId,
  });
}

/// RUDP Light ACK Tracker: tracks outgoing sends and matches DELIVERY_RECEIPTs.
///
/// For ACK-worthy message types, the tracker registers each send with a timeout.
/// When the corresponding DELIVERY_RECEIPT arrives, the addresses used for
/// sending are marked as confirmed (recordSuccess). On timeout, they are
/// marked as unreachable (recordFailure).
///
/// V3.1: Per-route failure tracking. Relay sends are tracked with longer
/// timeouts and Route-DOWN only kills the specific route that failed.
class AckTracker {
  final Map<String, _PendingAck> _pending = {};
  final DhtRpc _rttSource;
  final CLogger _log;

  /// Per-route consecutive ACK failure counter (V3.1).
  /// Key: "${peerHex}|${viaNextHopHex ?? 'direct'}"
  /// 3x timeout on same key → only THAT route is marked DOWN.
  final Map<String, int> _routeConsecutiveFailures = {};

  /// Per-message retry counter: limits how often a single message is
  /// re-queued after ACK timeout. Prevents infinite retry loops on Android
  /// where main-thread flooding degrades UI performance.
  /// Max 3 retries per message — after that, the message stays in the
  /// persistent MessageQueue for the 30s periodic drain.
  static const int _maxRetriesPerMessage = 3;
  final Map<String, int> _messageRetryCount = {};

  /// Callback when an ACK times out — used by service layer to downgrade
  /// message status from "sent" to "queued" (RUDP Light enforcement).
  void Function(String messageIdHex, String recipientNodeIdHex)? onAckTimeout;

  /// Callback for RUDP Light retry: on ACK timeout, re-queue the message
  /// for immediate re-send via alternative route (Architecture Section 2.4.3).
  void Function(String messageIdHex, Uint8List serializedEnvelope, Uint8List recipientNodeId)? onRetryNeeded;

  /// Callback when a route becomes unreachable (3x consecutive ACK timeout).
  /// V3.1: includes viaNextHopHex for surgical route-down.
  void Function(String peerNodeIdHex, {String? viaNextHopHex})? onRouteDown;

  /// Callback when a DELIVERY_RECEIPT matches a pending send — proves
  /// end-to-end reachability to the recipient (works for both direct and
  /// relay-delivered receipts, unlike dvRouting.confirmRoute which only
  /// fires for direct).
  void Function(String messageIdHex, String recipientNodeIdHex)? onAckReceived;

  AckTracker({required DhtRpc rttSource, String? profileDir})
      : _rttSource = rttSource,
        _log = CLogger.get('ack-tracker', profileDir: profileDir);

  /// Compute ACK timeout appropriate for the route type.
  /// Direct: 2*RTT + 50ms (existing behavior).
  /// Relay: max(baseRtt * 2 * hopCount, 8000ms) — minimum 8s for any relay.
  static Duration computeTimeout(Duration baseRtt, {int hopCount = 1}) {
    if (hopCount <= 1) {
      return Duration(milliseconds: baseRtt.inMilliseconds * 2 + 50);
    }
    final relayMs = baseRtt.inMilliseconds * 2 * hopCount;
    return Duration(milliseconds: relayMs.clamp(8000, 30000));
  }

  /// Register an outgoing send for ACK tracking.
  ///
  /// Returns a Future that completes with `true` on ACK receipt,
  /// `false` on timeout. The caller should NOT await this —
  /// it runs asynchronously alongside the send flow.
  Future<bool> trackSend(
    String messageIdHex,
    String recipientNodeIdHex,
    List<PeerAddress> usedAddresses,
    Duration timeout, {
    String? viaNextHopHex,
    int estimatedHops = 1,
    Uint8List? serializedEnvelope,
    Uint8List? recipientNodeId,
  }) {
    // Deduplicate: if already tracked (e.g. resend), cancel old entry
    final existing = _pending.remove(messageIdHex);
    if (existing != null) {
      existing.timer.cancel();
      if (!existing.completer.isCompleted) {
        existing.completer.complete(false);
      }
    }

    final completer = Completer<bool>();
    final timer = Timer(timeout, () => _handleTimeout(messageIdHex));

    _pending[messageIdHex] = _PendingAck(
      messageIdHex: messageIdHex,
      recipientNodeIdHex: recipientNodeIdHex,
      usedAddresses: usedAddresses,
      sendTimestamp: DateTime.now(),
      timer: timer,
      completer: completer,
      viaNextHopHex: viaNextHopHex,
      estimatedHops: estimatedHops,
      serializedEnvelope: serializedEnvelope,
      recipientNodeId: recipientNodeId,
    );

    return completer.future;
  }

  /// Handle incoming DELIVERY_RECEIPT (or other ACK).
  ///
  /// Returns true if a pending entry was matched and resolved.
  bool handleAck(String messageIdHex, String senderNodeIdHex) {
    final entry = _pending.remove(messageIdHex);
    if (entry == null) return false;

    entry.timer.cancel();

    // Mark all used addresses as successfully delivering
    for (final addr in entry.usedAddresses) {
      addr.recordSuccess();
    }

    // Reset ALL route failure counters for this peer — any working route
    // proves the peer is reachable.
    _routeConsecutiveFailures.removeWhere(
        (key, _) => key.startsWith('${entry.recipientNodeIdHex}|'));

    // Clear retry counter on successful delivery
    _messageRetryCount.remove(messageIdHex);

    // Update RTT for this peer
    final elapsed = DateTime.now().difference(entry.sendTimestamp);
    try {
      final nodeId = _hexToBytes(entry.recipientNodeIdHex);
      _rttSource.updateRtt(nodeId, elapsed);
    } catch (_) {
      // Invalid hex — skip RTT update
    }

    if (!entry.completer.isCompleted) {
      entry.completer.complete(true);
    }

    onAckReceived?.call(messageIdHex, entry.recipientNodeIdHex);

    final msgShort = messageIdHex.length > 8 ? messageIdHex.substring(0, 8) : messageIdHex;
    final senderShort = senderNodeIdHex.length > 8 ? senderNodeIdHex.substring(0, 8) : senderNodeIdHex;
    final via = entry.viaNextHopHex != null
        ? ' via ${entry.viaNextHopHex!.substring(0, 8)}'
        : '';
    _log.debug('ACK received for $msgShort from $senderShort$via (${elapsed.inMilliseconds}ms)');

    return true;
  }

  /// Handle timeout for a pending ACK.
  void _handleTimeout(String messageIdHex) {
    final entry = _pending.remove(messageIdHex);
    if (entry == null) return;

    // Mark all used addresses as failed (only for direct sends)
    if (entry.viaNextHopHex == null) {
      for (final addr in entry.usedAddresses) {
        addr.recordFailure();
      }
    }

    if (!entry.completer.isCompleted) {
      entry.completer.complete(false);
    }

    // V3.1: Per-route failure tracking (compound key)
    final routeKey = '${entry.recipientNodeIdHex}|${entry.viaNextHopHex ?? "direct"}';
    final routeFailures = (_routeConsecutiveFailures[routeKey] ?? 0) + 1;
    _routeConsecutiveFailures[routeKey] = routeFailures;

    final msgShort = messageIdHex.length > 8 ? messageIdHex.substring(0, 8) : messageIdHex;
    final rcpShort = entry.recipientNodeIdHex.length > 8 ? entry.recipientNodeIdHex.substring(0, 8) : entry.recipientNodeIdHex;
    final via = entry.viaNextHopHex != null
        ? ' via ${entry.viaNextHopHex!.substring(0, 8)}'
        : '';
    _log.debug('ACK timeout for $msgShort to $rcpShort$via — '
        '${entry.usedAddresses.length} addresses marked unreachable '
        '(route failures: $routeFailures/3)');

    // Notify service layer to downgrade message status (RUDP Light).
    onAckTimeout?.call(entry.messageIdHex, entry.recipientNodeIdHex);

    // RUDP Light retry: re-queue for immediate re-send via alternative route.
    // Architecture Section 2.4.3: "On timeout → try next route."
    // The cascade will pick a different route because this route's failure
    // counter is now incremented.
    // Limit retries per message to avoid infinite retry loops that flood
    // the main thread (especially on Android where service runs in-process).
    if (entry.serializedEnvelope != null && entry.recipientNodeId != null) {
      final retries = (_messageRetryCount[messageIdHex] ?? 0) + 1;
      if (retries <= _maxRetriesPerMessage) {
        _messageRetryCount[messageIdHex] = retries;
        onRetryNeeded?.call(entry.messageIdHex, entry.serializedEnvelope!, entry.recipientNodeId!);
      } else {
        _log.debug('ACK retry limit ($retries/$_maxRetriesPerMessage) reached for $msgShort — '
            'message stays in queue for periodic drain');
        _messageRetryCount.remove(messageIdHex);
      }
    }

    // 3x consecutive timeout on same route → Route DOWN (surgical)
    if (routeFailures >= 3) {
      _log.info('Route DOWN: $rcpShort$via (3x consecutive ACK timeout)');
      onRouteDown?.call(entry.recipientNodeIdHex, viaNextHopHex: entry.viaNextHopHex);
      _routeConsecutiveFailures.remove(routeKey);
    }
  }

  /// Single source of truth: which message types warrant a DELIVERY_RECEIPT.
  static bool isAckWorthy(proto.MessageType type) {
    switch (type) {
      // Content messages
      case proto.MessageType.TEXT:
      case proto.MessageType.IMAGE:
      case proto.MessageType.VIDEO:
      case proto.MessageType.GIF:
      case proto.MessageType.FILE:
      case proto.MessageType.VOICE_MESSAGE:
      case proto.MessageType.EMOJI_REACTION:
      case proto.MessageType.MEDIA_ANNOUNCEMENT:
      case proto.MessageType.MEDIA_ACCEPT:
      case proto.MessageType.MESSAGE_EDIT:
      case proto.MessageType.MESSAGE_DELETE:
      // Group messages
      case proto.MessageType.GROUP_CREATE:
      case proto.MessageType.GROUP_INVITE:
      case proto.MessageType.GROUP_LEAVE:
      case proto.MessageType.GROUP_KEY_UPDATE:
      // Channel messages
      case proto.MessageType.CHANNEL_POST:
      case proto.MessageType.CHANNEL_INVITE:
      case proto.MessageType.CHANNEL_LEAVE:
      case proto.MessageType.CHANNEL_ROLE_UPDATE:
      // Contact management
      case proto.MessageType.CONTACT_REQUEST:
      case proto.MessageType.CONTACT_REQUEST_RESPONSE:
      // Calendar (§23)
      case proto.MessageType.CALENDAR_INVITE:
      case proto.MessageType.CALENDAR_RSVP:
      case proto.MessageType.CALENDAR_UPDATE:
      case proto.MessageType.CALENDAR_DELETE:
      // Polls (§24) — snapshots are ephemeral broadcasts and stay ack-less
      case proto.MessageType.POLL_CREATE:
      case proto.MessageType.POLL_VOTE:
      case proto.MessageType.POLL_UPDATE:
      case proto.MessageType.POLL_VOTE_ANONYMOUS:
      case proto.MessageType.POLL_VOTE_REVOKE:
      // Infrastructure that warrants confirmation
      case proto.MessageType.PROFILE_UPDATE:
      case proto.MessageType.KEY_ROTATION_BROADCAST:
      case proto.MessageType.RESTORE_BROADCAST:
      case proto.MessageType.CHAT_CONFIG_UPDATE:
      case proto.MessageType.CHAT_CONFIG_RESPONSE:
      case proto.MessageType.IDENTITY_DELETED:
        return true;
      default:
        return false;
    }
  }

  /// Number of pending ACKs (for diagnostics).
  int get pendingCount => _pending.length;

  /// Per-route consecutive failure count (for diagnostics).
  /// Uses compound key "${peerHex}|${viaNextHopHex ?? 'direct'}".
  int routeFailureCount(String peerNodeIdHex, {String? viaNextHopHex}) {
    final key = '$peerNodeIdHex|${viaNextHopHex ?? "direct"}';
    return _routeConsecutiveFailures[key] ?? 0;
  }

  /// Legacy per-peer failure count (sum across all routes).
  int peerFailureCount(String peerNodeIdHex) {
    int total = 0;
    for (final entry in _routeConsecutiveFailures.entries) {
      if (entry.key.startsWith('$peerNodeIdHex|')) {
        total += entry.value;
      }
    }
    return total;
  }

  /// Cancel all pending timers and clean up.
  void dispose() {
    for (final entry in _pending.values) {
      entry.timer.cancel();
      if (!entry.completer.isCompleted) {
        entry.completer.complete(false);
      }
    }
    _pending.clear();
    _routeConsecutiveFailures.clear();
    _messageRetryCount.clear();
  }

  /// Convert hex string to bytes.
  static Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }
}
