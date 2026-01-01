import 'dart:async';
import 'dart:typed_data';

import 'package:cleona/core/calls/group_call_session.dart';
import 'package:cleona/core/calls/lan_multicast.dart';
import 'package:cleona/core/calls/media_relay.dart';
import 'package:cleona/core/calls/rtt_measurement.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:fixnum/fixnum.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart' show bytesToHex, hexToBytes;
import 'package:cleona/core/node/cleona_node.dart';
import 'package:cleona/core/node/identity_context.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Manages group call signaling, overlay tree, and media relay.
///
/// Completely independent from [CallManager] (1:1 calls).
/// Uses a shared call_key for all participants (not per-pair DH).
class GroupCallManager {
  final IdentityContext identity;
  final CleonaNode node;
  final Map<String, ContactInfo> contacts;
  final Map<String, GroupInfo> groups;
  final CLogger _log;

  GroupCallSession? _currentGroupCall;
  Timer? _rttTimer;
  Timer? _healthTimer;
  Timer? _treeRebuildDebounce;

  /// Callback: CleonaService sends KEM-encrypted message to a recipient.
  /// Returns true if send succeeded.
  Future<bool> Function(String recipientHex, proto.MessageType type, Uint8List payload)? sendEncrypted;

  /// Callback: send unencrypted envelope (for audio frames — already encrypted with callKey).
  void Function(String recipientHex, proto.MessageType type, Uint8List payload)? sendDirect;

  // UI callbacks
  void Function(GroupCallInfo info)? onIncomingGroupCall;
  void Function(GroupCallInfo info)? onGroupCallStarted;
  void Function(GroupCallInfo info)? onGroupCallEnded;
  void Function(String nodeIdHex, ParticipantState state)? onParticipantChanged;
  void Function(Uint8List newKey, int version)? onKeyRotated;

  GroupCallManager({
    required this.identity,
    required this.node,
    required this.contacts,
    required this.groups,
    required String profileDir,
  }) : _log = CLogger.get('group-calls', profileDir: profileDir);

  GroupCallSession? get currentGroupCall => _currentGroupCall;
  bool get inGroupCall => _currentGroupCall?.state == GroupCallState.inCall;

  // ── Initiator Flow ──────────────────────────────────────────────────

  /// Start a group call. Generates call_key, sends CALL_INVITE to all members.
  Future<GroupCallSession?> startGroupCall(String groupIdHex) async {
    if (_currentGroupCall != null) {
      _log.warn('Already in a group call');
      return null;
    }

    final group = groups[groupIdHex];
    if (group == null) {
      _log.warn('Group $groupIdHex not found');
      return null;
    }

    final sodium = SodiumFFI();
    final callId = sodium.randomBytes(16);
    final callKey = sodium.randomBytes(32);

    final session = GroupCallSession(
      callId: callId,
      groupIdHex: groupIdHex,
      groupName: group.name,
      initiatorHex: identity.userIdHex,
      direction: CallDirection.outgoing,
      state: GroupCallState.inviting,
    );
    session.callKey = callKey;
    session.callKeyVersion = 1;

    // Add self as joined participant
    session.participants[identity.userIdHex] = GroupCallParticipant(
      nodeIdHex: identity.userIdHex,
      displayName: identity.displayName,
      state: ParticipantState.joined,
      joinedAt: DateTime.now(),
    );

    // Add all other group members as invited
    for (final member in group.members.values) {
      if (member.nodeIdHex == identity.userIdHex) continue;
      session.participants[member.nodeIdHex] = GroupCallParticipant(
        nodeIdHex: member.nodeIdHex,
        displayName: member.displayName,
        state: ParticipantState.invited,
      );
    }

    _currentGroupCall = session;

    // Send CALL_INVITE to each member (KEM-encrypted individually)
    final invite = proto.CallInvite()
      ..callId = callId
      ..isGroupCall = true
      ..groupId = hexToBytes(groupIdHex)
      ..groupCallKey = callKey;

    final payload = invite.writeToBuffer();
    for (final member in group.members.values) {
      if (member.nodeIdHex == identity.userIdHex) continue;
      session.participants[member.nodeIdHex]?.state = ParticipantState.ringing;
      await sendEncrypted?.call(member.nodeIdHex, proto.MessageType.CALL_INVITE, payload);
    }

    _log.info('Group call started: ${session.callIdHex.substring(0, 8)} in group "${group.name}" with ${group.members.length - 1} invites');
    return session;
  }

  // ── Participant Flow ────────────────────────────────────────────────

  /// Handle incoming CALL_INVITE with is_group_call=true.
  void handleGroupCallInvite(proto.MessageEnvelope envelope, Uint8List? decryptedPayload) {
    if (_currentGroupCall != null) {
      _sendReject(envelope, 'busy');
      return;
    }

    final invite = proto.CallInvite.fromBuffer(decryptedPayload ?? envelope.encryptedPayload);
    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
    final groupIdHex = bytesToHex(Uint8List.fromList(invite.groupId));

    final group = groups[groupIdHex];
    final groupName = group?.name ?? groupIdHex.substring(0, 8);

    final session = GroupCallSession(
      callId: Uint8List.fromList(invite.callId),
      groupIdHex: groupIdHex,
      groupName: groupName,
      initiatorHex: senderHex,
      direction: CallDirection.incoming,
      state: GroupCallState.ringing,
    );

    // Store the call key from invite
    if (invite.groupCallKey.isNotEmpty) {
      session.callKey = Uint8List.fromList(invite.groupCallKey);
      session.callKeyVersion = 1;
    }

    // Add known group members as participants
    if (group != null) {
      for (final member in group.members.values) {
        session.participants[member.nodeIdHex] = GroupCallParticipant(
          nodeIdHex: member.nodeIdHex,
          displayName: member.displayName,
          state: member.nodeIdHex == senderHex
              ? ParticipantState.joined
              : ParticipantState.invited,
        );
      }
    } else {
      // Minimal: just the initiator
      session.participants[senderHex] = GroupCallParticipant(
        nodeIdHex: senderHex,
        displayName: contacts[senderHex]?.effectiveName ?? senderHex.substring(0, 8),
        state: ParticipantState.joined,
      );
    }

    _currentGroupCall = session;
    onIncomingGroupCall?.call(session.toGroupCallInfo());
    _log.info('Incoming group call from ${senderHex.substring(0, 8)} in "$groupName"');
  }

  /// Accept an incoming group call.
  Future<void> acceptGroupCall() async {
    final session = _currentGroupCall;
    if (session == null || session.state != GroupCallState.ringing ||
        session.direction != CallDirection.incoming) {
      return;
    }

    session.state = GroupCallState.inCall;

    // Mark self as joined
    session.participants[identity.userIdHex] = GroupCallParticipant(
      nodeIdHex: identity.userIdHex,
      displayName: identity.displayName,
      state: ParticipantState.joined,
      joinedAt: DateTime.now(),
    );

    // Send CALL_ANSWER to initiator
    final answer = proto.CallAnswer()
      ..callId = session.callId;

    final envelope = identity.createSignedEnvelope(
      proto.MessageType.CALL_ANSWER,
      answer.writeToBuffer(),
      recipientId: hexToBytes(session.initiatorHex),
    );
    await node.sendEnvelope(envelope, hexToBytes(session.initiatorHex));

    _setupRttAndHealth(session);
    onGroupCallStarted?.call(session.toGroupCallInfo());
    _log.info('Group call accepted: ${session.callIdHex.substring(0, 8)}');
  }

  /// Reject an incoming group call.
  Future<void> rejectGroupCall({String reason = 'busy'}) async {
    final session = _currentGroupCall;
    if (session == null || session.state != GroupCallState.ringing) return;

    session.state = GroupCallState.ended;

    final reject = proto.CallReject()
      ..callId = session.callId
      ..reason = reason;

    final envelope = identity.createSignedEnvelope(
      proto.MessageType.CALL_REJECT,
      reject.writeToBuffer(),
      recipientId: hexToBytes(session.initiatorHex),
    );
    await node.sendEnvelope(envelope, hexToBytes(session.initiatorHex));

    _currentGroupCall = null;
    _log.info('Group call rejected: $reason');
  }

  // ── Signaling Handlers ──────────────────────────────────────────────

  void handleGroupCallAnswer(proto.MessageEnvelope envelope) {
    final session = _currentGroupCall;
    if (session == null) return;

    final answer = proto.CallAnswer.fromBuffer(envelope.encryptedPayload);
    if (!_callIdMatches(session.callId, answer.callId)) return;

    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
    final participant = session.participants[senderHex];
    if (participant == null) return;

    participant.state = ParticipantState.joined;
    participant.joinedAt = DateTime.now();
    onParticipantChanged?.call(senderHex, ParticipantState.joined);

    _log.info('Participant joined: ${senderHex.substring(0, 8)}');

    // Check if we have enough participants to start the call
    final joinedCount = session.joinedParticipantIds.length;
    if (joinedCount >= 2 && session.state == GroupCallState.inviting) {
      session.state = GroupCallState.inCall;
      _rebuildTree(session);
      _setupRttAndHealth(session);
      onGroupCallStarted?.call(session.toGroupCallInfo());
      _log.info('Group call active with $joinedCount participants');
    } else if (session.state == GroupCallState.inCall) {
      // New participant joined an active call — rebuild tree + rotate key
      _scheduleTreeRebuild(session);
      _rotateCallKey(session);
    }
  }

  void handleGroupCallReject(proto.MessageEnvelope envelope) {
    final session = _currentGroupCall;
    if (session == null) return;

    final reject = proto.CallReject.fromBuffer(envelope.encryptedPayload);
    if (!_callIdMatches(session.callId, reject.callId)) return;

    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
    final participant = session.participants[senderHex];
    if (participant == null) return;

    participant.state = ParticipantState.left;
    onParticipantChanged?.call(senderHex, ParticipantState.left);
    _log.info('Participant rejected: ${senderHex.substring(0, 8)} (${reject.reason})');
  }

  void handleGroupCallHangup(proto.MessageEnvelope envelope) {
    final session = _currentGroupCall;
    if (session == null) return;

    final hangup = proto.CallHangup.fromBuffer(envelope.encryptedPayload);
    if (!_callIdMatches(session.callId, hangup.callId)) return;

    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
    _participantLeft(session, senderHex);
  }

  void handleGroupCallLeave(proto.MessageEnvelope envelope) {
    final session = _currentGroupCall;
    if (session == null) return;

    final leave = proto.GroupCallLeave.fromBuffer(envelope.encryptedPayload);
    if (!_callIdMatches(session.callId, leave.callId)) return;

    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
    _participantLeft(session, senderHex);
  }

  void _participantLeft(GroupCallSession session, String nodeIdHex) {
    final participant = session.participants[nodeIdHex];
    if (participant == null) return;

    participant.state = ParticipantState.left;
    onParticipantChanged?.call(nodeIdHex, ParticipantState.left);
    _log.info('Participant left: ${nodeIdHex.substring(0, 8)}');

    // Rebuild tree and rotate key (member left)
    if (session.state == GroupCallState.inCall && session.isInitiator) {
      session.tree.removeParticipant(nodeIdHex);
      _broadcastTreeUpdate(session);
      _rotateCallKey(session);
    }

    // End call if less than 2 participants remain
    final joinedCount = session.joinedParticipantIds.length;
    if (joinedCount < 2 && session.state == GroupCallState.inCall) {
      _log.info('Group call ended: not enough participants ($joinedCount)');
      _endCall(session);
    }
  }

  void handleCallRejoin(proto.MessageEnvelope envelope) {
    final session = _currentGroupCall;
    if (session == null || session.state != GroupCallState.inCall) return;

    final rejoin = proto.CallRejoin.fromBuffer(envelope.encryptedPayload);
    if (!_callIdMatches(session.callId, rejoin.callId)) return;

    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
    final participant = session.participants[senderHex];
    if (participant == null) return;

    // Rejoin: re-mark as joined, NO key rotation (per architecture)
    participant.state = ParticipantState.joined;
    participant.joinedAt = DateTime.now();
    onParticipantChanged?.call(senderHex, ParticipantState.joined);
    _log.info('Participant rejoined: ${senderHex.substring(0, 8)} (no key rotation)');

    if (session.isInitiator) {
      _scheduleTreeRebuild(session);
      // Send current call key to rejoining participant
      _sendKeyToParticipant(session, senderHex);
    }
  }

  // ── Tree Management ─────────────────────────────────────────────────

  void handleCallTreeUpdate(proto.MessageEnvelope envelope) {
    final session = _currentGroupCall;
    if (session == null) return;

    final update = proto.CallTreeUpdate.fromBuffer(envelope.encryptedPayload);
    if (!_callIdMatches(session.callId, update.callId)) return;

    // Only accept tree updates from initiator
    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
    if (senderHex != session.initiatorHex) return;

    // Only accept newer versions
    if (update.version <= session.tree.version) return;

    final initiatorHex = bytesToHex(Uint8List.fromList(update.initiatorNodeId));
    session.tree.fromNodeList(
      update.nodes.map((n) => {
            'nodeIdHex': bytesToHex(Uint8List.fromList(n.nodeId)),
            'parentHex': n.parentNodeId.isEmpty ? null : bytesToHex(Uint8List.fromList(n.parentNodeId)),
            'childrenHex': n.childNodeIds.map((c) => bytesToHex(Uint8List.fromList(c))).toList(),
          }).toList(),
      initiatorHex,
    );
    session.tree.version = update.version;

    // Setup relay
    _setupRelay(session);

    _log.info('Tree updated: version=${update.version}, depth=${session.tree.depth}');
  }

  void handleCallRttPing(proto.MessageEnvelope envelope) {
    final session = _currentGroupCall;
    if (session == null || session.rtt == null) return;

    final ping = proto.CallRttPing.fromBuffer(envelope.encryptedPayload);
    if (!_callIdMatches(session.callId, ping.callId)) return;

    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));

    // Send PONG back
    final pong = proto.CallRttPong()
      ..callId = session.callId
      ..echoTimestampUs = ping.timestampUs
      ..responderTimestampUs = Int64(DateTime.now().microsecondsSinceEpoch);

    final env = identity.createSignedEnvelope(
      proto.MessageType.CALL_RTT_PONG,
      pong.writeToBuffer(),
      recipientId: hexToBytes(senderHex),
    );
    node.sendEnvelope(env, hexToBytes(senderHex));
  }

  void handleCallRttPong(proto.MessageEnvelope envelope) {
    final session = _currentGroupCall;
    if (session == null || session.rtt == null) return;

    final pong = proto.CallRttPong.fromBuffer(envelope.encryptedPayload);
    if (!_callIdMatches(session.callId, pong.callId)) return;

    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
    session.rtt!.handlePong(senderHex, pong.echoTimestampUs.toInt());
  }

  void handleGroupCallKeyRotate(proto.MessageEnvelope envelope, Uint8List? decryptedPayload) {
    final session = _currentGroupCall;
    if (session == null) return;

    final rotation = proto.GroupCallKeyRotate.fromBuffer(
        decryptedPayload ?? envelope.encryptedPayload);
    if (!_callIdMatches(session.callId, rotation.callId)) return;

    // Only accept from initiator
    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
    if (senderHex != session.initiatorHex) return;

    // Only accept newer versions
    if (rotation.keyVersion <= session.callKeyVersion) return;

    session.callKey = Uint8List.fromList(rotation.newCallKey);
    session.callKeyVersion = rotation.keyVersion;

    onKeyRotated?.call(session.callKey!, rotation.keyVersion);
    _log.info('Key rotated to version ${rotation.keyVersion}');
  }

  // ── Audio Frame Routing ─────────────────────────────────────────────

  /// Send own audio frame via the overlay tree.
  void sendGroupAudioFrame(Uint8List encryptedFrame) {
    final session = _currentGroupCall;
    if (session == null || session.state != GroupCallState.inCall) return;

    session.totalFramesSent++;

    // Wrap in GroupCallAudio proto
    final audio = proto.GroupCallAudio()
      ..callId = session.callId
      ..senderNodeId = identity.nodeId
      ..sequenceNumber = session.nextAudioSeqNum
      ..encryptedAudio = encryptedFrame;

    final payload = audio.writeToBuffer();

    // Send to tree children via MediaRelay
    if (session.relay != null) {
      session.relay!.forwardFrame(Uint8List.fromList(payload));
    } else {
      // Fallback: direct send to all joined participants
      for (final pId in session.joinedParticipantIds) {
        if (pId == identity.userIdHex) continue;
        sendDirect?.call(pId, proto.MessageType.CALL_GROUP_AUDIO, payload);
      }
    }
  }

  /// Handle incoming CALL_GROUP_AUDIO (relay to children if not leaf node).
  void handleGroupCallAudio(proto.MessageEnvelope envelope) {
    final session = _currentGroupCall;
    if (session == null || session.state != GroupCallState.inCall) return;

    session.totalFramesReceived++;

    // Relay to our tree children (if we have any)
    if (session.relay != null) {
      session.relay!.forwardFrame(Uint8List.fromList(envelope.encryptedPayload));
    }
  }

  // ── Video Frame Routing ──────────────────────────────────────────────

  /// Send own video frame via the overlay tree.
  void sendGroupVideoFrame(Uint8List serializedVideoFrame) {
    final session = _currentGroupCall;
    if (session == null || session.state != GroupCallState.inCall) return;

    session.videoFramesSent++;

    // Wrap in GroupCallVideo proto
    final video = proto.GroupCallVideo()
      ..callId = session.callId
      ..senderNodeId = identity.nodeId
      ..videoFrameData = serializedVideoFrame;

    final payload = video.writeToBuffer();

    // Send to tree children via MediaRelay
    if (session.relay != null) {
      session.relay!.forwardFrame(Uint8List.fromList(payload));
    } else {
      for (final pId in session.joinedParticipantIds) {
        if (pId == identity.userIdHex) continue;
        sendDirect?.call(pId, proto.MessageType.CALL_GROUP_VIDEO, payload);
      }
    }
  }

  /// Handle incoming CALL_GROUP_VIDEO (relay to children if not leaf node).
  void handleGroupCallVideo(proto.MessageEnvelope envelope) {
    final session = _currentGroupCall;
    if (session == null || session.state != GroupCallState.inCall) return;

    session.videoFramesReceived++;

    // Relay to our tree children (if we have any)
    if (session.relay != null) {
      session.relay!.forwardFrame(Uint8List.fromList(envelope.encryptedPayload));
    }
  }

  // ── Leave / End ─────────────────────────────────────────────────────

  /// Leave the group call gracefully.
  Future<void> leaveGroupCall() async {
    final session = _currentGroupCall;
    if (session == null) return;

    // Notify all joined participants
    final leave = proto.GroupCallLeave()..callId = session.callId;
    final payload = leave.writeToBuffer();

    for (final pId in session.joinedParticipantIds) {
      if (pId == identity.userIdHex) continue;
      final env = identity.createSignedEnvelope(
        proto.MessageType.CALL_GROUP_LEAVE,
        payload,
        recipientId: hexToBytes(pId),
      );
      await node.sendEnvelope(env, hexToBytes(pId));
    }

    _endCall(session);
    _log.info('Left group call: ${session.callIdHex.substring(0, 8)}');
  }

  void _endCall(GroupCallSession session) {
    session.state = GroupCallState.ended;
    onGroupCallEnded?.call(session.toGroupCallInfo());
    _cleanup();
  }

  void _cleanup() {
    _rttTimer?.cancel();
    _rttTimer = null;
    _healthTimer?.cancel();
    _healthTimer = null;
    _treeRebuildDebounce?.cancel();
    _treeRebuildDebounce = null;
    _currentGroupCall?.relay?.clear();
    _currentGroupCall = null;
  }

  // ── Tree Construction (initiator only) ──────────────────────────────

  void _rebuildTree(GroupCallSession session) {
    if (!session.isInitiator) return;

    final participants = session.joinedParticipantIds;
    if (participants.length < 2) return;

    session.tree.build(
      participants: participants,
      initiatorHex: session.initiatorHex,
      routeCost: (a, b) {
        final route = node.dvRouting.bestRouteTo(b);
        return route?.cost.toInt() ?? 10;
      },
      rtt: session.rtt,
      sameSubnet: (a, b) => isSameSubnet(a, b),
    );

    _setupRelay(session);
    _broadcastTreeUpdate(session);
    _log.info('Tree built: ${participants.length} nodes, depth=${session.tree.depth}');
  }

  void _scheduleTreeRebuild(GroupCallSession session) {
    _treeRebuildDebounce?.cancel();
    _treeRebuildDebounce = Timer(const Duration(milliseconds: 500), () {
      _rebuildTree(session);
    });
  }

  void _setupRelay(GroupCallSession session) {
    session.relay = MediaRelay(
      tree: session.tree,
      ownNodeIdHex: identity.userIdHex,
    );
    session.relay!.onSendUnicast = (targetHex, frame) {
      sendDirect?.call(targetHex, proto.MessageType.CALL_GROUP_AUDIO, frame);
    };
    session.relay!.onSendMulticast = (frame) {
      // LAN multicast — not implemented in this MVP, use unicast fallback
      final children = session.tree.childrenOf(identity.userIdHex);
      for (final child in children) {
        sendDirect?.call(child, proto.MessageType.CALL_GROUP_AUDIO, frame);
      }
    };
    session.relay!.onChildCrashed = (crashedHex) {
      final participant = session.participants[crashedHex];
      if (participant != null && participant.state == ParticipantState.joined) {
        participant.state = ParticipantState.crashed;
        onParticipantChanged?.call(crashedHex, ParticipantState.crashed);
        _log.info('Participant crashed: ${crashedHex.substring(0, 8)}');
        if (session.isInitiator) {
          session.tree.handleCrash(crashedHex);
          _broadcastTreeUpdate(session);
          // No key rotation on crash (per architecture)
        }
      }
    };
  }

  Future<void> _broadcastTreeUpdate(GroupCallSession session) async {
    if (!session.isInitiator) return;
    session.tree.version++;

    final nodeList = session.tree.toNodeList();
    final update = proto.CallTreeUpdate()
      ..callId = session.callId
      ..initiatorNodeId = identity.nodeId
      ..version = session.tree.version;

    for (final n in nodeList) {
      final treeNode = proto.OverlayTreeNode()
        ..nodeId = hexToBytes(n['nodeIdHex'] as String);
      if (n['parentHex'] != null) {
        treeNode.parentNodeId = hexToBytes(n['parentHex'] as String);
      }
      for (final childHex in (n['childrenHex'] as List<dynamic>)) {
        treeNode.childNodeIds.add(hexToBytes(childHex as String));
      }
      update.nodes.add(treeNode);
    }

    final payload = update.writeToBuffer();
    for (final pId in session.joinedParticipantIds) {
      if (pId == identity.userIdHex) continue;
      final env = identity.createSignedEnvelope(
        proto.MessageType.CALL_TREE_UPDATE,
        payload,
        recipientId: hexToBytes(pId),
      );
      await node.sendEnvelope(env, hexToBytes(pId));
    }
  }

  // ── RTT + Health ────────────────────────────────────────────────────

  void _setupRttAndHealth(GroupCallSession session) {
    session.rtt = RttMeasurement(
      callId: session.callId,
      ownNodeIdHex: identity.userIdHex,
    );

    // Periodic RTT measurement (every 5s)
    _rttTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _sendRttPings(session);
    });

    // Crash detection (every 1s)
    _healthTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (session.relay != null) {
        session.relay!.checkForCrashes();
      }
    });
  }

  void _sendRttPings(GroupCallSession session) {
    if (session.rtt == null) return;
    for (final pId in session.joinedParticipantIds) {
      if (pId == identity.userIdHex) continue;
      final ts = session.rtt!.createPing(pId);
      final ping = proto.CallRttPing()
        ..callId = session.callId
        ..timestampUs = Int64(ts);
      final env = identity.createSignedEnvelope(
        proto.MessageType.CALL_RTT_PING,
        ping.writeToBuffer(),
        recipientId: hexToBytes(pId),
      );
      node.sendEnvelope(env, hexToBytes(pId));
    }
  }

  // ── Key Rotation ────────────────────────────────────────────────────

  Future<void> _rotateCallKey(GroupCallSession session) async {
    if (!session.isInitiator) return;

    final sodium = SodiumFFI();
    final newKey = sodium.randomBytes(32);
    session.callKeyVersion++;
    session.callKey = newKey;

    // Send new key to all joined participants (KEM-encrypted)
    final rotation = proto.GroupCallKeyRotate()
      ..callId = session.callId
      ..newCallKey = newKey
      ..keyVersion = session.callKeyVersion;

    final payload = rotation.writeToBuffer();
    for (final pId in session.joinedParticipantIds) {
      if (pId == identity.userIdHex) continue;
      await sendEncrypted?.call(pId, proto.MessageType.CALL_GROUP_KEY_ROTATE, payload);
    }

    onKeyRotated?.call(newKey, session.callKeyVersion);
    _log.info('Key rotated to version ${session.callKeyVersion}');
  }

  Future<void> _sendKeyToParticipant(GroupCallSession session, String nodeIdHex) async {
    if (session.callKey == null) return;

    final rotation = proto.GroupCallKeyRotate()
      ..callId = session.callId
      ..newCallKey = session.callKey!
      ..keyVersion = session.callKeyVersion;

    await sendEncrypted?.call(
        nodeIdHex, proto.MessageType.CALL_GROUP_KEY_ROTATE, rotation.writeToBuffer());
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  void _sendReject(proto.MessageEnvelope incoming, String reason) {
    try {
      final invite = proto.CallInvite.fromBuffer(incoming.encryptedPayload);
      final reject = proto.CallReject()
        ..callId = invite.callId
        ..reason = reason;
      final env = identity.createSignedEnvelope(
        proto.MessageType.CALL_REJECT,
        reject.writeToBuffer(),
        recipientId: Uint8List.fromList(incoming.senderId),
      );
      node.sendEnvelope(env, Uint8List.fromList(incoming.senderId));
    } catch (_) {}
  }

  bool _callIdMatches(Uint8List a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
