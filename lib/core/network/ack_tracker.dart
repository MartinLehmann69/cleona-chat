import 'dart:async';
import 'dart:typed_data';
import 'package:cleona/core/dht/dht_rpc.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Pending ACK entry for an outgoing message.
class _PendingAck {
  final String messageIdHex;
  final String recipientUserIdHex;
  final List<PeerAddress> usedAddresses;
  final DateTime sendTimestamp;
  final Timer timer;
  final Completer<bool> completer;

  /// null = direct send, non-null = relay nextHop nodeIdHex.
  final String? viaNextHopHex;

  /// 1 = direct, 2+ = relay (used for timeout calculation).
  final int estimatedHops;

  /// Serialized `NetworkPacketV3` for re-queue on ACK timeout (RUDP Light retry).
  /// Architecture Section 2.4.3: "On timeout → try next route."
  final Uint8List? serializedPacket;
  final Uint8List? recipientUserId;

  _PendingAck({
    required this.messageIdHex,
    required this.recipientUserIdHex,
    required this.usedAddresses,
    required this.sendTimestamp,
    required this.timer,
    required this.completer,
    this.viaNextHopHex,
    this.estimatedHops = 1,
    this.serializedPacket,
    this.recipientUserId,
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
  ///
  /// DV-6: cap is dynamic — `aliveRouteCount` callback (when set) lets
  /// the tracker scale the budget to the number of usable alternative
  /// routes. Default base cap when no callback is wired is `_baseRetries`.
  static const int _baseRetries = 3;
  static const int _maxRetriesHardCap = 8;
  final Map<String, int> _messageRetryCount = {};

  /// Callback when an ACK times out — used by service layer to downgrade
  /// message status from "sent" to "queued" (RUDP Light enforcement).
  void Function(String messageIdHex, String recipientUserIdHex)? onAckTimeout;

  /// Callback for RUDP Light retry: on ACK timeout, re-queue the message
  /// for immediate re-send via alternative route (Architecture Section 2.4.3).
  void Function(String messageIdHex, Uint8List serializedPacket, Uint8List recipientUserId)? onRetryNeeded;

  /// Callback when a route becomes unreachable (3x consecutive ACK timeout).
  /// V3.1: includes viaNextHopHex for surgical route-down.
  void Function(String peerNodeIdHex, {String? viaNextHopHex})? onRouteDown;

  /// DV-6: returns count of currently alive DV routes to `peerNodeIdHex`.
  /// Wired by cleona_node to query dvRouting at timeout time. The
  /// per-message retry budget scales with this number so peers with
  /// multiple alternatives get a deeper recovery window before
  /// onRouteDown fires (V3.0: kein lokales Re-Send-Park mehr — danach
  /// übernimmt S&F + Reed-Solomon + Mailbox-Pull, Architektur §5).
  int Function(String peerNodeIdHex)? aliveRouteCount;

  /// Callback when a DELIVERY_RECEIPT matches a pending send — proves
  /// end-to-end reachability to the recipient. The third argument
  /// `wasDirect` distinguishes direct-delivered receipts (UDP source
  /// address known, proves bidirectional UDP) from relay-delivered ones
  /// (from=0.0.0.0, proves only that *some* path works). DV-routing's
  /// `confirmRoute` should only fire on direct receipts; relay-delivered
  /// receipts must NOT short-circuit the relay cascade.
  /// (DV-1 §3.4: single source of truth for ACK→DV-success bridge.)
  void Function(String messageIdHex, String recipientUserIdHex, bool wasDirect)? onAckReceived;

  /// Fired when an end-to-end DELIVERY_RECEIPT returns over a RELAY path
  /// (`wasDirect=false`) for a message we sent via a known `nextHop`. The
  /// receipt proves that the specific relay route we used actually delivers,
  /// so the DV bridge marks *that* route `ackConfirmed` — the relay-side
  /// counterpart to `confirmRoute` on direct receipts (Architecture §4.4
  /// confirmed-beats-unconfirmed, review S-3). `destDeviceIdHex` is the ACK
  /// sender (= the recipient); `viaNextHopHex` is the relay we sent through.
  void Function(String destDeviceIdHex, String viaNextHopHex)? onRelayRouteConfirmed;

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
    String recipientUserIdHex,
    List<PeerAddress> usedAddresses,
    Duration timeout, {
    String? viaNextHopHex,
    int estimatedHops = 1,
    Uint8List? serializedPacket,
    Uint8List? recipientUserId,
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
      recipientUserIdHex: recipientUserIdHex,
      usedAddresses: usedAddresses,
      sendTimestamp: DateTime.now(),
      timer: timer,
      completer: completer,
      viaNextHopHex: viaNextHopHex,
      estimatedHops: estimatedHops,
      serializedPacket: serializedPacket,
      recipientUserId: recipientUserId,
    );

    return completer.future;
  }

  /// Handle incoming DELIVERY_RECEIPT (or other ACK).
  ///
  /// `wasDirect` indicates whether the receipt envelope arrived directly
  /// from the recipient (true: source IP known, bidirectional UDP proven)
  /// or via relay (false: from=0.0.0.0, only end-to-end reachability proven).
  /// Forwarded to `onAckReceived` so the central DV-bridge can decide
  /// whether to call `dvRouting.confirmRoute` (direct only) or just reset
  /// peer failure counters (both).
  ///
  /// Returns true if a pending entry was matched and resolved.
  bool handleAck(String messageIdHex, String senderNodeIdHex, {bool wasDirect = false}) {
    final entry = _pending.remove(messageIdHex);
    if (entry == null) return false;

    entry.timer.cancel();

    // Address-success bookkeeping is NOT done here. _sendDirectToPeer
    // sends to all active addresses concurrently and passes the full
    // list as `usedAddresses`; crediting all of them on a single ACK
    // would reward addresses that never delivered. The actual address
    // that worked is the one whose source IP/port shows up on the
    // returning DELIVERY_RECEIPT envelope — that is recorded by
    // _onEnvelopeReceived → _touchPeer in the inbound path, before
    // we get here. Relay-delivered receipts arrive with from=0.0.0.0
    // (no source address known), in which case no specific address is
    // credited — which is correct, the only thing proven is end-to-end
    // reachability via the relay path.

    // Reset ALL route failure counters for this peer — any working route
    // proves the peer is reachable.
    _routeConsecutiveFailures.removeWhere(
        (key, _) => key.startsWith('${entry.recipientUserIdHex}|'));

    // Clear retry counter on successful delivery
    _messageRetryCount.remove(messageIdHex);

    // Update RTT for this peer
    final elapsed = DateTime.now().difference(entry.sendTimestamp);
    try {
      final nodeId = _hexToBytes(entry.recipientUserIdHex);
      _rttSource.updateRtt(nodeId, elapsed);
    } catch (_) {
      // Invalid hex — skip RTT update
    }

    if (!entry.completer.isCompleted) {
      entry.completer.complete(true);
    }

    // §3.1 B-1: fire with the actual ACK sender's deviceId (from the
    // inbound DELIVERY_RECEIPT) so dvRouting.confirmRoute and
    // routingTable.getPeer operate on routing-layer IDs.
    onAckReceived?.call(messageIdHex, senderNodeIdHex, wasDirect);

    // S-3: an E2E receipt that came back over a relay path proves the relay
    // route we sent through delivers → let the DV bridge confirm that route.
    if (!wasDirect && entry.viaNextHopHex != null) {
      onRelayRouteConfirmed?.call(senderNodeIdHex, entry.viaNextHopHex!);
    }

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
    final routeKey = '${entry.recipientUserIdHex}|${entry.viaNextHopHex ?? "direct"}';
    final routeFailures = (_routeConsecutiveFailures[routeKey] ?? 0) + 1;
    _routeConsecutiveFailures[routeKey] = routeFailures;

    final msgShort = messageIdHex.length > 8 ? messageIdHex.substring(0, 8) : messageIdHex;
    final rcpShort = entry.recipientUserIdHex.length > 8 ? entry.recipientUserIdHex.substring(0, 8) : entry.recipientUserIdHex;
    final via = entry.viaNextHopHex != null
        ? ' via ${entry.viaNextHopHex!.substring(0, 8)}'
        : '';
    _log.debug('ACK timeout for $msgShort to $rcpShort$via — '
        '${entry.usedAddresses.length} addresses marked unreachable '
        '(route failures: $routeFailures/3)');

    // Notify service layer to downgrade message status (RUDP Light).
    onAckTimeout?.call(entry.messageIdHex, entry.recipientUserIdHex);

    // DV-5: Route-DOWN MUST fire BEFORE the retry, otherwise the retry's
    // synchronous sendEnvelope still sees the broken route as alive (cost=1)
    // and picks it again — wasting the third retry on an already-failed
    // path. With this ordering, the retry runs against a routing table
    // where the dead route has cost=infinity and Bellman-Ford fall-back
    // automatically chooses an alternative.
    if (routeFailures >= 3) {
      _log.info('Route DOWN: $rcpShort$via (3x consecutive ACK timeout)');
      onRouteDown?.call(entry.recipientUserIdHex, viaNextHopHex: entry.viaNextHopHex);
      _routeConsecutiveFailures.remove(routeKey);
    }

    // RUDP Light retry: re-queue for immediate re-send via alternative route.
    // Architecture Section 2.4.3: "On timeout → try next route."
    //
    // DV-6: Per-message retry cap is dynamic. Default base is 3, but for
    // peers with multiple alive DV routes the cap scales (2× alive count,
    // hard-clamped at 8) so a peer with three alternatives doesn't lose
    // its full recovery budget on a single broken route.
    if (entry.serializedPacket != null && entry.recipientUserId != null) {
      final retries = (_messageRetryCount[messageIdHex] ?? 0) + 1;
      final maxRetries = _computeMaxRetries(entry.recipientUserIdHex);
      if (retries <= maxRetries) {
        _messageRetryCount[messageIdHex] = retries;
        onRetryNeeded?.call(entry.messageIdHex, entry.serializedPacket!, entry.recipientUserId!);
      } else {
        _log.debug('ACK retry limit ($retries/$maxRetries) reached for $msgShort — '
            'message stays in queue for periodic drain');
        _messageRetryCount.remove(messageIdHex);
      }
    }
  }

  /// DV-6: Dynamic per-message retry cap. Returns `_baseRetries` when the
  /// `aliveRouteCount` callback is unset (test fixtures, callers without
  /// a wired DV-routing). Otherwise scales linearly with available routes
  /// and clamps to `[_baseRetries, _maxRetriesHardCap]`.
  int _computeMaxRetries(String peerNodeIdHex) {
    final count = aliveRouteCount?.call(peerNodeIdHex);
    if (count == null || count <= 1) return _baseRetries;
    final scaled = count * 2;
    if (scaled < _baseRetries) return _baseRetries;
    if (scaled > _maxRetriesHardCap) return _maxRetriesHardCap;
    return scaled;
  }

  /// V3 single source of truth: which `MessageTypeV3` warrants a
  /// DELIVERY_RECEIPT. The V3 receive pipeline (`handleApplicationFrame`)
  /// calls this to decide whether to auto-emit `MTV3_DELIVERY_RECEIPT`
  /// after dispatch.
  static bool isAckWorthyV3(proto.MessageTypeV3 type) {
    switch (type) {
      // Content
      case proto.MessageTypeV3.MTV3_TEXT:
      case proto.MessageTypeV3.MTV3_MEDIA_INLINE:
      case proto.MessageTypeV3.MTV3_MEDIA_ANNOUNCE:
      case proto.MessageTypeV3.MTV3_MEDIA_REQUEST:
      case proto.MessageTypeV3.MTV3_EDIT:
      case proto.MessageTypeV3.MTV3_DELETE:
      case proto.MessageTypeV3.MTV3_REACTION:
      // Group lifecycle
      case proto.MessageTypeV3.MTV3_GROUP_CREATE:
      case proto.MessageTypeV3.MTV3_GROUP_INVITE:
      case proto.MessageTypeV3.MTV3_GROUP_LEAVE:
      // Channel lifecycle
      case proto.MessageTypeV3.MTV3_CHANNEL_INVITE:
      case proto.MessageTypeV3.MTV3_CHANNEL_LEAVE:
      case proto.MessageTypeV3.MTV3_CHANNEL_ROLE_UPDATE:
      // Contact establishment
      case proto.MessageTypeV3.MTV3_CONTACT_REQUEST:
      case proto.MessageTypeV3.MTV3_CONTACT_REQUEST_RESPONSE:
      // Calendar
      case proto.MessageTypeV3.MTV3_CALENDAR_INVITE:
      case proto.MessageTypeV3.MTV3_CALENDAR_RSVP:
      case proto.MessageTypeV3.MTV3_CALENDAR_UPDATE:
      case proto.MessageTypeV3.MTV3_CALENDAR_DELETE:
      // Polls
      case proto.MessageTypeV3.MTV3_POLL_CREATE:
      case proto.MessageTypeV3.MTV3_POLL_VOTE:
      case proto.MessageTypeV3.MTV3_POLL_UPDATE:
      case proto.MessageTypeV3.MTV3_POLL_VOTE_ANONYMOUS:
      // Identity-layer infra warranting confirmation
      case proto.MessageTypeV3.MTV3_PROFILE_UPDATE:
      case proto.MessageTypeV3.MTV3_KEY_ROTATION_BROADCAST:
      case proto.MessageTypeV3.MTV3_RESTORE_BROADCAST:
      case proto.MessageTypeV3.MTV3_CHAT_CONFIG_UPDATE:
      case proto.MessageTypeV3.MTV3_IDENTITY_DELETED:
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
