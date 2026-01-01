import 'dart:typed_data';
import 'package:cleona/core/calls/overlay_tree.dart';
import 'package:cleona/core/calls/media_relay.dart';
import 'package:cleona/core/calls/rtt_measurement.dart';
import 'package:cleona/core/network/peer_info.dart' show bytesToHex;
import 'package:cleona/core/service/service_types.dart';

/// A participant in a group call.
class GroupCallParticipant {
  final String nodeIdHex;
  String displayName;
  ParticipantState state;
  DateTime? joinedAt;
  int framesReceived;

  GroupCallParticipant({
    required this.nodeIdHex,
    required this.displayName,
    this.state = ParticipantState.invited,
    this.joinedAt,
    this.framesReceived = 0,
  });
}

/// Represents an active group call session with crypto state and tree management.
class GroupCallSession {
  final Uint8List callId;
  final String groupIdHex;
  final String groupName;
  final String initiatorHex;
  final CallDirection direction;
  GroupCallState state;
  DateTime startedAt;

  /// Participants: nodeIdHex -> GroupCallParticipant
  final Map<String, GroupCallParticipant> participants = {};

  /// Shared encryption key (all participants use the same key).
  Uint8List? callKey; // 32 bytes AES-256
  int callKeyVersion = 0;

  /// Overlay multicast tree for media relay.
  OverlayTree tree = OverlayTree(maxFanOut: 3);
  MediaRelay? relay;
  RttMeasurement? rtt;

  /// Audio frame counter.
  int totalFramesSent = 0;
  int totalFramesReceived = 0;
  int _audioSeqNum = 0;

  /// Monotonic audio sequence number.
  int get nextAudioSeqNum => _audioSeqNum++;

  /// Video frame counter.
  int videoFramesSent = 0;
  int videoFramesReceived = 0;
  int _videoSeqNum = 0;

  /// Monotonic video sequence number.
  int get nextVideoSeqNum => _videoSeqNum++;

  GroupCallSession({
    required this.callId,
    required this.groupIdHex,
    required this.groupName,
    required this.initiatorHex,
    required this.direction,
    this.state = GroupCallState.idle,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();

  String get callIdHex => bytesToHex(callId);

  /// Whether we are the initiator (tree root, responsible for tree builds).
  bool get isInitiator => direction == CallDirection.outgoing;

  /// List of joined participant node IDs (for tree construction).
  List<String> get joinedParticipantIds =>
      participants.entries
          .where((e) => e.value.state == ParticipantState.joined)
          .map((e) => e.key)
          .toList();

  /// Convert to IPC-facing GroupCallInfo.
  GroupCallInfo toGroupCallInfo() => GroupCallInfo(
        callId: callIdHex,
        groupIdHex: groupIdHex,
        groupName: groupName,
        initiatorHex: initiatorHex,
        state: state,
        startedAt: startedAt,
        participants: participants.values
            .map((p) => GroupCallParticipantInfo(
                  nodeIdHex: p.nodeIdHex,
                  displayName: p.displayName,
                  state: p.state,
                ))
            .toList(),
        totalFramesSent: totalFramesSent,
        totalFramesReceived: totalFramesReceived,
        videoFramesSent: videoFramesSent,
        videoFramesReceived: videoFramesReceived,
      );
}
