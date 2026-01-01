import 'dart:typed_data';
import 'package:cleona/core/calls/overlay_tree.dart';

/// Per-call relay budget to prevent abuse.
class RelayBudget {
  final int maxBytesPerSecond;
  final int maxFramesPerSecond;

  int _bytesThisSecond = 0;
  int _framesThisSecond = 0;
  DateTime _windowStart = DateTime.now();

  RelayBudget({
    this.maxBytesPerSecond = 500000, // 500 KB/s (enough for audio + video)
    this.maxFramesPerSecond = 200, // 200 frames/s (4 streams × 50 fps)
  });

  /// Check if relaying a frame of [size] bytes is within budget.
  bool canRelay(int size) {
    _rollWindow();
    return _bytesThisSecond + size <= maxBytesPerSecond &&
        _framesThisSecond < maxFramesPerSecond;
  }

  /// Record a relayed frame.
  void recordRelay(int size) {
    _rollWindow();
    _bytesThisSecond += size;
    _framesThisSecond++;
  }

  void _rollWindow() {
    final now = DateTime.now();
    if (now.difference(_windowStart).inMilliseconds >= 1000) {
      _bytesThisSecond = 0;
      _framesThisSecond = 0;
      _windowStart = now;
    }
  }

  /// Current utilization (0.0 to 1.0).
  double get utilization {
    _rollWindow();
    final byteRatio = _bytesThisSecond / maxBytesPerSecond;
    final frameRatio = _framesThisSecond / maxFramesPerSecond;
    return byteRatio > frameRatio ? byteRatio : frameRatio;
  }
}

/// Tracks last-seen time per tree child for crash detection.
class ChildHealthTracker {
  final Map<String, DateTime> _lastSeen = {};

  void recordFrame(String childHex) {
    _lastSeen[childHex] = DateTime.now();
  }

  /// Returns children that haven't sent any frame within [timeoutMs].
  List<String> deadChildren(int timeoutMs) {
    final now = DateTime.now();
    return _lastSeen.entries
        .where(
            (e) => now.difference(e.value).inMilliseconds > timeoutMs)
        .map((e) => e.key)
        .toList();
  }

  /// Record a specific timestamp for a child (for testing).
  void setLastSeen(String childHex, DateTime time) {
    _lastSeen[childHex] = time;
  }

  void removeChild(String hex) => _lastSeen.remove(hex);
  void clear() => _lastSeen.clear();
}

/// Media relay for the overlay multicast tree.
///
/// When this node receives a media frame from its parent in the tree,
/// it forwards the frame to all its children. Children can be either
/// unicast targets (different subnet) or LAN multicast targets
/// (same subnet, via ff02::cleona:call).
class MediaRelay {
  final OverlayTree tree;
  final String ownNodeIdHex;
  final RelayBudget budget;
  final ChildHealthTracker healthTracker = ChildHealthTracker();

  // Callback: send frame to a specific peer via unicast.
  void Function(String targetNodeIdHex, Uint8List frame)? onSendUnicast;

  // Callback: send frame via LAN multicast (reaches all local members).
  void Function(Uint8List frame)? onSendMulticast;

  // Callback: a child is detected as crashed.
  void Function(String crashedNodeIdHex)? onChildCrashed;

  // Stats
  int framesRelayed = 0;
  int bytesRelayed = 0;
  int framesDropped = 0;

  MediaRelay({
    required this.tree,
    required this.ownNodeIdHex,
    RelayBudget? budget,
  }) : budget = budget ?? RelayBudget();

  /// Forward a received media frame to all tree children.
  ///
  /// Called when this node receives a CALL_AUDIO or CALL_VIDEO frame
  /// from its parent (or from itself if this is the root/source).
  ///
  /// Returns the number of targets the frame was forwarded to.
  int forwardFrame(Uint8List frame) {
    final myNode = tree.nodeFor(ownNodeIdHex);
    if (myNode == null || myNode.childrenHex.isEmpty) return 0;

    if (!budget.canRelay(frame.length)) {
      framesDropped++;
      return 0;
    }

    var sent = 0;

    // Forward to each child
    for (final childHex in myNode.childrenHex) {
      // Send to child directly — if the child is a LAN cluster head,
      // it will multicast to its own LAN members.
      onSendUnicast?.call(childHex, frame);
      sent++;
    }

    // If we are a LAN cluster head, multicast to local members
    if (myNode.isLanClusterHead && myNode.lanMemberHex.isNotEmpty) {
      if (onSendMulticast != null) {
        onSendMulticast!(frame);
        sent += myNode.lanMemberHex.length;
      } else {
        // Fallback: unicast to each LAN member
        for (final memberHex in myNode.lanMemberHex) {
          onSendUnicast?.call(memberHex, frame);
          sent++;
        }
      }
    }

    if (sent > 0) {
      budget.recordRelay(frame.length * sent);
      framesRelayed++;
      bytesRelayed += frame.length * sent;
    }

    return sent;
  }

  /// Record that we received a frame FROM a child (uplink monitoring).
  void recordChildFrame(String childHex) {
    healthTracker.recordFrame(childHex);
  }

  /// Check for crashed children. Returns list of crashed node IDs.
  List<String> checkForCrashes() {
    final dead = healthTracker.deadChildren(OverlayTree.crashTimeoutMs);
    for (final hex in dead) {
      healthTracker.removeChild(hex);
      onChildCrashed?.call(hex);
    }
    return dead;
  }

  /// Clear all state.
  void clear() {
    healthTracker.clear();
    framesRelayed = 0;
    bytesRelayed = 0;
    framesDropped = 0;
  }
}
