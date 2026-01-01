import 'dart:typed_data';
import 'package:cleona/core/calls/overlay_tree.dart';
import 'package:cleona/generated/proto/transport.pb.dart' as proto;

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

/// The forwarding of a broker in the mesh (§17.7, S407-GA-P5).
///
/// "one broker per pair, both directions, one hop, and only what it
/// received from the pair's members themselves." A frame goes on only when
/// the edge it came by IS its sender — a frame that already went through
/// another participant is never passed on, so no chain and no loop can
/// form. Its targets are the other members of the pairs the broker carries
/// for that sender ([targetsFor], from `GroupCallBroker.forwardTargets`);
/// video only to pairs whose video it carries.
///
/// No [RelayBudget] here: what a broker may carry it decided when it was
/// bound (its capacity under `f_i`), not frame by frame — a per-second cap
/// would cut the voice of pairs it has confirmed.
class PairRelay {
  PairRelay({required this.targetsFor});

  /// The other members for a frame [fromHex] sent itself.
  final List<String> Function(String fromHex, {required bool video})
      targetsFor;

  /// Sends one frame to one participant over its media pair.
  void Function(String targetHex, Uint8List frame, proto.MessageType type)?
      onSendUnicast;

  int framesRelayed = 0;

  /// Forwards [frame], which arrived over the media pair with [from] and
  /// names [senderHex] in its header. Returns the number of targets.
  int forwardFrame(Uint8List frame, proto.MessageType type,
      {required String from, required String senderHex}) {
    if (from != senderHex) return 0;
    final targets = targetsFor(from,
        video: type == proto.MessageType.MT_CALL_GROUP_VIDEO);
    for (final t in targets) {
      if (t == from) continue;
      onSendUnicast?.call(t, frame, type);
      framesRelayed++;
    }
    return targets.length;
  }
}

/// Media relay for the overlay multicast tree.
///
/// A frame that arrives over one tree link goes out over every other
/// tree link (§17.7) — parent, children and, at a cluster head, the LAN
/// members. LAN members can be reached one by one or by one multicast
/// ([onSendMulticast]).
class MediaRelay {
  final OverlayTree tree;
  final String ownNodeIdHex;
  final RelayBudget budget;
  final ChildHealthTracker healthTracker = ChildHealthTracker();

  // Callback: send frame to a specific peer via unicast. [type] is the
  // wire MessageType of the relayed frame (CALL_GROUP_AUDIO vs
  // CALL_GROUP_VIDEO) — the relay is content-agnostic, but the outgoing
  // envelope must carry the original type or the receiver parses a video
  // frame as GroupCallAudio (and vice versa).
  void Function(String targetNodeIdHex, Uint8List frame,
      proto.MessageType type)? onSendUnicast;

  // Callback: send frame via LAN multicast (reaches all local members).
  // Unset, the members are reached one by one over [onSendUnicast].
  void Function(Uint8List frame, proto.MessageType type)? onSendMulticast;

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

  /// Forward a media frame over every tree link except the one it came by
  /// (§17.7).
  ///
  /// [from] is the tree link the frame arrived over; `null` for an own
  /// frame, which goes out over every link. [type] identifies audio or
  /// video and is passed through to the send callbacks unchanged.
  ///
  /// ── UNTIL S407 THIS WENT TO THE CHILDREN ONLY (B-2) ─────────────────
  ///
  /// The tree was used as a source tree rooted at the initiator: a frame
  /// went down, never up. Every leaf was silent once its tree assignment
  /// had arrived — measured in S407-GRUPPENANRUF: "own frame of a1 ->
  /// sent=0". A tree shared by every speaker forwards over every link but
  /// the incoming one — the forwarding rule of a spanning tree (IEEE
  /// 802.1D: every forwarding port except the receiving port; core-based
  /// trees, RFC 2201). In a tree that rule never returns a frame to
  /// the link it came by, so no loop arises.
  ///
  /// Returns the number of targets the frame was forwarded to.
  int forwardFrame(Uint8List frame, proto.MessageType type, {String? from}) {
    final up = tree.upLinkOf(ownNodeIdHex);
    final down = tree.downLinksOf(ownNodeIdHex);
    final lan = tree.nodeFor(ownNodeIdHex)?.lanMemberHex ?? const <String>[];
    // A multicast reaches every LAN member at once — including the one a
    // frame came from. It is used only when the frame did not come from a
    // LAN member; otherwise the members are reached one by one, without
    // the incoming one.
    final multicast =
        onSendMulticast != null && lan.isNotEmpty && !lan.contains(from);
    final unicastTargets = <String>[
      if (up != null && up != from) up,
      for (final d in down)
        if (d != from && !(multicast && lan.contains(d))) d,
    ];
    final targetCount = unicastTargets.length + (multicast ? lan.length : 0);
    if (targetCount == 0) return 0;

    if (!budget.canRelay(frame.length)) {
      framesDropped++;
      return 0;
    }

    var sent = 0;
    for (final target in unicastTargets) {
      onSendUnicast?.call(target, frame, type);
      sent++;
    }
    if (multicast) {
      onSendMulticast!(frame, type);
      sent += lan.length;
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
