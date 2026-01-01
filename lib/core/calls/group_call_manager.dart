import 'dart:async';
import 'dart:typed_data';

import 'package:cleona/core/calls/group_call_session.dart';
import 'package:cleona/core/calls/lan_multicast.dart';
import 'package:cleona/core/calls/media_relay.dart';
import 'package:cleona/core/calls/rtt_measurement.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:fixnum/fixnum.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart' show bytesToHex, hexToBytes, PeerInfo;
import 'package:cleona/core/network/sender_identity_snapshot.dart';
import 'package:cleona/core/network/v3_frame_codec.dart';
import 'package:cleona/core/node/cleona_node.dart';
import 'package:cleona/core/node/identity_context.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Manages group call signaling, overlay tree, and media relay.
///
/// Completely independent from [CallManager] (1:1 calls).
/// Uses a shared call_key for all participants (not per-pair DH).
///
/// V3 Send Model (Architecture §10.2 + §10.3):
///   * Setup frames (CALL_INVITE/ANSWER/REJECT/HANGUP/GROUP_LEAVE/
///     GROUP_KEY_ROTATE/REJOIN-key-handoff) → `sendViaUser` callback.
///     Reaches all of the recipient user's authorized devices via the
///     `service.sendToUser` 2D-DHT-resolved fan-out (§26).
///   * Live-media frames (CALL_GROUP_AUDIO/VIDEO, CALL_RTT_PING/PONG,
///     CALL_TREE_UPDATE) and ephemeral outer-replies (busy auto-reject)
///     → built inline with `V3FrameCodec` (`applicationFlavor=false,
///     skipPoW=true` — Architecture §10.3) and dispatched via
///     `node.sendToDevice(packet, deviceId)`. Per-frame Identity-Resolution
///     would be fatal at 50 packets/s; the per-call route cache (§10.4.1)
///     short-circuits the lookup on the hot path.
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

  /// V3 setup-path send callback — wired by [CleonaService] to its
  /// `sendToUser` orchestrator. Used for CALL_INVITE (group), CALL_ANSWER,
  /// CALL_REJECT, CALL_GROUP_LEAVE, CALL_GROUP_KEY_ROTATE.
  Future<bool> Function(
    Uint8List recipientUserId,
    proto.MessageTypeV3 type,
    Uint8List payload,
  )? sendViaUser;

  // UI callbacks
  void Function(GroupCallInfo info)? onIncomingGroupCall;
  void Function(GroupCallInfo info)? onGroupCallStarted;
  void Function(GroupCallInfo info)? onGroupCallEnded;
  void Function(String nodeIdHex, ParticipantState state)? onParticipantChanged;

  /// §10.2.1 per-sender media keys. `onOwnSendKeyChanged` fires when our own
  /// secret media key is (re)generated → the encrypt side (capture isolate,
  /// video engine) must switch to it. `onPeerSendKey` fires when we learn an
  /// authenticated peer's send_key → the decrypt side (mixer, video receiver)
  /// must register it for that sender.
  void Function(Uint8List ownKey, int version)? onOwnSendKeyChanged;
  void Function(String senderUserHex, Uint8List key, int version)? onPeerSendKey;

  // Per-participant cached PeerInfo for live-media sendToDevice path.
  // Mirror of [CallSession.cachedRoute] but multi-target. Keyed by
  // participant userIdHex. Invalidated on DV-Routing route-down for the
  // associated deviceId.
  final Map<String, PeerInfo> _participantRouteCache = {};

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
    _ensureOwnSendKey(session); // §10.2.1 per-sender media key

    // Send CALL_INVITE to each member (KEM-encrypted individually, fan-out
    // to all of each member's authorized devices via sendToUser).
    // TODO(v3-sub-message): swap to `CallInviteV3` once defined.
    final invite = proto.CallInvite()
      ..callId = callId
      ..isGroupCall = true
      ..groupId = hexToBytes(groupIdHex)
      ..groupCallKey = callKey;

    final payload = invite.writeToBuffer();
    for (final member in group.members.values) {
      if (member.nodeIdHex == identity.userIdHex) continue;
      session.participants[member.nodeIdHex]?.state = ParticipantState.ringing;
      await sendViaUser?.call(
        hexToBytes(member.nodeIdHex),
        proto.MessageTypeV3.MTV3_CALL_INVITE,
        payload,
      );
    }

    _log.info('Group call started: ${session.callIdHex.substring(0, 8)} in group "${group.name}" with ${group.members.length - 1} invites');
    return session;
  }

  // ── Participant Flow ────────────────────────────────────────────────

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

    // Send CALL_ANSWER to initiator (multi-device fan-out via sendToUser).
    // TODO(v3-sub-message): swap to `CallAnswerV3` once defined.
    final answer = proto.CallAnswer()..callId = session.callId;
    await sendViaUser?.call(
      hexToBytes(session.initiatorHex),
      proto.MessageTypeV3.MTV3_CALL_ANSWER,
      answer.writeToBuffer(),
    );

    _setupRttAndHealth(session);
    // §10.2.1: announce our send_key to everyone already joined (the
    // initiator, plus any earlier joiners). They reciprocate via the handler.
    await _announceSendKeyToAllJoined(session);
    onGroupCallStarted?.call(session.toGroupCallInfo());
    _log.info('Group call accepted: ${session.callIdHex.substring(0, 8)}');
  }

  /// Reject an incoming group call.
  Future<void> rejectGroupCall({String reason = 'busy'}) async {
    final session = _currentGroupCall;
    if (session == null || session.state != GroupCallState.ringing) return;

    session.state = GroupCallState.ended;

    // TODO(v3-sub-message): swap to `CallRejectV3` once defined.
    final reject = proto.CallReject()
      ..callId = session.callId
      ..reason = reason;
    await sendViaUser?.call(
      hexToBytes(session.initiatorHex),
      proto.MessageTypeV3.MTV3_CALL_REJECT,
      reject.writeToBuffer(),
    );

    _currentGroupCall = null;
    _log.info('Group call rejected: $reason');
  }

  // ── Signaling Handlers ──────────────────────────────────────────────

  void _participantLeft(GroupCallSession session, String nodeIdHex) {
    final participant = session.participants[nodeIdHex];
    if (participant == null) return;

    participant.state = ParticipantState.left;
    onParticipantChanged?.call(nodeIdHex, ParticipantState.left);
    _participantRouteCache.remove(nodeIdHex);
    _log.info('Participant left: ${nodeIdHex.substring(0, 8)}');

    // Rebuild tree (member left) — initiator only.
    if (session.state == GroupCallState.inCall && session.isInitiator) {
      session.tree.removeParticipant(nodeIdHex);
      _broadcastTreeUpdate(session);
    }

    // End call if less than 2 participants remain, else apply forward secrecy.
    final joinedCount = session.joinedParticipantIds.length;
    if (joinedCount < 2 && session.state == GroupCallState.inCall) {
      _log.info('Group call ended: not enough participants ($joinedCount)');
      _endCall(session);
    } else if (session.state == GroupCallState.inCall) {
      // §10.2.1 forward secrecy: every remaining participant rotates its own
      // send_key so the departed node can no longer decrypt subsequent media.
      session.peerSendKeys.remove(nodeIdHex);
      rotateOwnSendKey(session);
    }
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

    // Send to tree children via MediaRelay (which calls _onSendUnicast /
    // _onSendMulticast — both end up at sendToDevice for live media).
    if (session.relay != null) {
      session.relay!.forwardFrame(Uint8List.fromList(payload));
    } else {
      // Fallback: direct send to all joined participants
      for (final pId in session.joinedParticipantIds) {
        if (pId == identity.userIdHex) continue;
        _sendLiveMediaToParticipant(
          pId,
          proto.MessageTypeV3.MTV3_CALL_GROUP_AUDIO,
          payload,
        );
      }
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
        _sendLiveMediaToParticipant(
          pId,
          proto.MessageTypeV3.MTV3_CALL_GROUP_VIDEO,
          payload,
        );
      }
    }
  }

  // ── Leave / End ─────────────────────────────────────────────────────

  /// Leave the group call gracefully.
  Future<void> leaveGroupCall() async {
    final session = _currentGroupCall;
    if (session == null) return;

    // Notify all joined participants via setup-path sendToUser fan-out.
    // TODO(v3-sub-message): swap to `GroupCallLeaveV3` once defined.
    final leave = proto.GroupCallLeave()..callId = session.callId;
    final payload = leave.writeToBuffer();

    for (final pId in session.joinedParticipantIds) {
      if (pId == identity.userIdHex) continue;
      await sendViaUser?.call(
        hexToBytes(pId),
        proto.MessageTypeV3.MTV3_CALL_GROUP_LEAVE,
        payload,
      );
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
    _participantRouteCache.clear();
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
      _sendLiveMediaToParticipant(
        targetHex,
        proto.MessageTypeV3.MTV3_CALL_GROUP_AUDIO,
        frame,
      );
    };
    session.relay!.onSendMulticast = (frame) {
      // LAN multicast — not implemented in this MVP, use unicast fallback.
      // Each child gets a sendToDevice via the per-call cached route.
      final children = session.tree.childrenOf(identity.userIdHex);
      for (final child in children) {
        _sendLiveMediaToParticipant(
          child,
          proto.MessageTypeV3.MTV3_CALL_GROUP_AUDIO,
          frame,
        );
      }
    };
    session.relay!.onChildCrashed = (crashedHex) {
      final participant = session.participants[crashedHex];
      if (participant != null && participant.state == ParticipantState.joined) {
        participant.state = ParticipantState.crashed;
        onParticipantChanged?.call(crashedHex, ParticipantState.crashed);
        _participantRouteCache.remove(crashedHex);
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

    // Tree update is live-media-class (per-call ephemeral, AMBIG-A3 = DEVICE
    // — high frequency on dynamic membership). Send via sendToDevice over
    // the per-call cached route. TODO(v3-sub-message): `CallTreeUpdateV3`.
    final payload = update.writeToBuffer();
    for (final pId in session.joinedParticipantIds) {
      if (pId == identity.userIdHex) continue;
      _sendLiveMediaToParticipant(
        pId,
        proto.MessageTypeV3.MTV3_CALL_TREE_UPDATE,
        payload,
      );
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
      // TODO(v3-sub-message): swap to `CallRttPingV3` once defined.
      final ping = proto.CallRttPing()
        ..callId = session.callId
        ..timestampUs = Int64(ts);
      _sendLiveMediaToParticipant(
        pId,
        proto.MessageTypeV3.MTV3_CALL_RTT_PING,
        ping.writeToBuffer(),
      );
    }
  }

  // ── §10.2.1 Per-Sender Media Keys ───────────────────────────────────

  /// Lazily generate our own secret media key (known only to us). Fires
  /// onOwnSendKeyChanged so the encrypt side switches to it.
  void _ensureOwnSendKey(GroupCallSession session) {
    if (session.ownSendKey != null) return;
    session.ownSendKey = SodiumFFI().randomBytes(32);
    session.ownSendKeyVersion = 1;
    onOwnSendKeyChanged?.call(session.ownSendKey!, session.ownSendKeyVersion);
  }

  /// Announce our current ownSendKey to one participant (setup-class: full
  /// Ed25519 + ML-DSA inner sig + KEM via sendViaUser). The recipient's
  /// inner-sig verification binds the key to us, so no other participant can
  /// register a key under our identity.
  Future<void> _announceSendKeyTo(
      GroupCallSession session, String participantUserHex) async {
    if (participantUserHex == identity.userIdHex) return;
    _ensureOwnSendKey(session);
    final ann = proto.GroupCallSenderKey()
      ..callId = session.callId
      ..senderNodeId = identity.nodeId
      ..sendKey = session.ownSendKey!
      ..keyVersion = session.ownSendKeyVersion;
    final ok = await sendViaUser?.call(
      hexToBytes(participantUserHex),
      proto.MessageTypeV3.MTV3_CALL_GROUP_SENDER_KEY,
      ann.writeToBuffer(),
    );
    if (ok == true) session.announcedSendKeyTo.add(participantUserHex);
  }

  Future<void> _announceSendKeyToAllJoined(GroupCallSession session) async {
    for (final pId in session.joinedParticipantIds) {
      await _announceSendKeyTo(session, pId);
    }
  }

  /// Forward secrecy on membership shrink (§10.2.1): regenerate our send_key
  /// and re-announce to the remaining joined set. The departed node's cached
  /// copy goes stale and cannot decrypt subsequent media.
  Future<void> rotateOwnSendKey(GroupCallSession session) async {
    session.ownSendKey = SodiumFFI().randomBytes(32);
    session.ownSendKeyVersion++;
    session.announcedSendKeyTo.clear();
    onOwnSendKeyChanged?.call(session.ownSendKey!, session.ownSendKeyVersion);
    await _announceSendKeyToAllJoined(session);
    _log.info('Own send_key rotated to version ${session.ownSendKeyVersion}');
  }

  // ── V3 Handlers (Welle 2B — Calls Cluster C3) ──────────────────────
  //
  // Per §10 + §10.5 + §23.3: each handler accepts the decrypted
  // `ApplicationFrameV3` (inner payload already verified by the V3 receive
  // pipeline in `cleona_service.handleApplicationFrame`), the
  // `senderDeviceId` lifted off the inbound `NetworkPacketV3`, and the
  // `SenderIdentitySnapshot` carrying outer-sig status (§2.4.0).
  //
  // For setup-class frames (CALL_INVITE/ANSWER/REJECT/HANGUP/GROUP_LEAVE/
  // GROUP_KEY_ROTATE/REJOIN) `snapshot.outerSigStatus` is informational —
  // the inner User-Sig was already verified upstream.
  //
  // For live-frame paths (CALL_GROUP_AUDIO/VIDEO, CALL_RTT_PING/PONG,
  // CALL_TREE_UPDATE) the §4.4.5 hot-path skip-zstd-ML-DSA semantic is
  // preserved — the receive side has nothing to do here besides parse and
  // dispatch into the existing relay/tree/RTT machinery (no extra crypto).

  /// V3 receive-handler for CALL_INVITE (group, is_group_call=true).
  void handleGroupCallInviteV3(
    proto.ApplicationFrameV3 frame,
    Uint8List senderDeviceId,
    SenderIdentitySnapshot? snapshot,
  ) {
    if (_currentGroupCall != null) {
      _sendRejectV3(frame, senderDeviceId, 'busy');
      return;
    }

    final proto.CallInvite invite;
    try {
      invite = proto.CallInvite.fromBuffer(frame.payload);
    } catch (e) {
      _log.warn('GROUP_CALL_INVITE V3: payload parse failed: $e');
      return;
    }
    if (!invite.isGroupCall) {
      _log.debug('GROUP_CALL_INVITE V3: isGroupCall=false — '
          'belongs to 1:1 CallManager, dropping');
      return;
    }

    final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
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

    if (invite.groupCallKey.isNotEmpty) {
      session.callKey = Uint8List.fromList(invite.groupCallKey);
      session.callKeyVersion = 1;
    }

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
      session.participants[senderHex] = GroupCallParticipant(
        nodeIdHex: senderHex,
        displayName: contacts[senderHex]?.effectiveName ?? senderHex.substring(0, 8),
        state: ParticipantState.joined,
      );
    }

    _currentGroupCall = session;
    _ensureOwnSendKey(session); // §10.2.1 per-sender media key
    onIncomingGroupCall?.call(session.toGroupCallInfo());
    _log.info('Incoming group call V3 from ${senderHex.substring(0, 8)} '
        '(device=${bytesToHex(senderDeviceId).substring(0, 8)}) in "$groupName"');
  }

  /// V3 receive-handler for CALL_ANSWER (group).
  void handleGroupCallAnswerV3(
    proto.ApplicationFrameV3 frame,
    Uint8List senderDeviceId,
    SenderIdentitySnapshot? snapshot,
  ) {
    final session = _currentGroupCall;
    if (session == null) return;

    final proto.CallAnswer answer;
    try {
      answer = proto.CallAnswer.fromBuffer(frame.payload);
    } catch (e) {
      _log.warn('GROUP_CALL_ANSWER V3: parse failed: $e');
      return;
    }
    if (!_callIdMatches(session.callId, answer.callId)) return;

    final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
    final participant = session.participants[senderHex];
    if (participant == null) return;

    participant.state = ParticipantState.joined;
    participant.joinedAt = DateTime.now();
    onParticipantChanged?.call(senderHex, ParticipantState.joined);

    _log.info('Participant joined V3: ${senderHex.substring(0, 8)} '
        '(device=${bytesToHex(senderDeviceId).substring(0, 8)})');

    final joinedCount = session.joinedParticipantIds.length;
    if (joinedCount >= 2 && session.state == GroupCallState.inviting) {
      session.state = GroupCallState.inCall;
      _rebuildTree(session);
      _setupRttAndHealth(session);
      onGroupCallStarted?.call(session.toGroupCallInfo());
      _log.info('Group call active with $joinedCount participants');
    } else if (session.state == GroupCallState.inCall) {
      _scheduleTreeRebuild(session);
    }
    // §10.2.1: hand the newcomer our send_key (no global rotation on join —
    // backward secrecy is natural, the newcomer never held prior keys). The
    // newcomer reciprocates with its own key via handleGroupCallSenderKeyV3.
    _announceSendKeyTo(session, senderHex);
  }

  /// V3 receive-handler for CALL_REJECT (group).
  void handleGroupCallRejectV3(
    proto.ApplicationFrameV3 frame,
    Uint8List senderDeviceId,
    SenderIdentitySnapshot? snapshot,
  ) {
    final session = _currentGroupCall;
    if (session == null) return;

    final proto.CallReject reject;
    try {
      reject = proto.CallReject.fromBuffer(frame.payload);
    } catch (e) {
      _log.warn('GROUP_CALL_REJECT V3: parse failed: $e');
      return;
    }
    if (!_callIdMatches(session.callId, reject.callId)) return;

    final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
    final participant = session.participants[senderHex];
    if (participant == null) return;

    participant.state = ParticipantState.left;
    onParticipantChanged?.call(senderHex, ParticipantState.left);
    _log.info('Participant rejected V3: ${senderHex.substring(0, 8)} '
        '(${reject.reason})');
  }

  /// V3 receive-handler for CALL_HANGUP (group).
  void handleGroupCallHangupV3(
    proto.ApplicationFrameV3 frame,
    Uint8List senderDeviceId,
    SenderIdentitySnapshot? snapshot,
  ) {
    final session = _currentGroupCall;
    if (session == null) return;

    final proto.CallHangup hangup;
    try {
      hangup = proto.CallHangup.fromBuffer(frame.payload);
    } catch (e) {
      _log.warn('GROUP_CALL_HANGUP V3: parse failed: $e');
      return;
    }
    if (!_callIdMatches(session.callId, hangup.callId)) return;

    final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
    _participantLeft(session, senderHex);
  }

  /// V3 receive-handler for GROUP_CALL_LEAVE.
  void handleGroupCallLeaveV3(
    proto.ApplicationFrameV3 frame,
    Uint8List senderDeviceId,
    SenderIdentitySnapshot? snapshot,
  ) {
    final session = _currentGroupCall;
    if (session == null) return;

    final proto.GroupCallLeave leave;
    try {
      leave = proto.GroupCallLeave.fromBuffer(frame.payload);
    } catch (e) {
      _log.warn('GROUP_CALL_LEAVE V3: parse failed: $e');
      return;
    }
    if (!_callIdMatches(session.callId, leave.callId)) return;

    final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
    _participantLeft(session, senderHex);
  }

  /// V3 receive-handler for CALL_REJOIN.
  void handleCallRejoinV3(
    proto.ApplicationFrameV3 frame,
    Uint8List senderDeviceId,
    SenderIdentitySnapshot? snapshot,
  ) {
    final session = _currentGroupCall;
    if (session == null || session.state != GroupCallState.inCall) return;

    final proto.CallRejoin rejoin;
    try {
      rejoin = proto.CallRejoin.fromBuffer(frame.payload);
    } catch (e) {
      _log.warn('CALL_REJOIN V3: parse failed: $e');
      return;
    }
    if (!_callIdMatches(session.callId, rejoin.callId)) return;

    final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
    final participant = session.participants[senderHex];
    if (participant == null) return;

    participant.state = ParticipantState.joined;
    participant.joinedAt = DateTime.now();
    onParticipantChanged?.call(senderHex, ParticipantState.joined);
    _log.info('Participant rejoined V3: ${senderHex.substring(0, 8)} '
        '(device=${bytesToHex(senderDeviceId).substring(0, 8)}, no global rotation)');

    if (session.isInitiator) {
      _scheduleTreeRebuild(session);
    }
    // §10.2.1: re-announce our send_key to the rejoiner (they re-announce
    // theirs). No global rotation — the authorized set did not change.
    session.announcedSendKeyTo.remove(senderHex);
    _announceSendKeyTo(session, senderHex);
  }

  /// V3 receive-handler for CALL_TREE_UPDATE.
  ///
  /// Live-class frame per §10.4.5 (high-frequency on dynamic membership) —
  /// no zstd / no ML-DSA on the wire; receive-side parses + applies the
  /// new tree directly. Only accepts updates from the call's initiator.
  void handleCallTreeUpdateV3(
    proto.ApplicationFrameV3 frame,
    Uint8List senderDeviceId,
    SenderIdentitySnapshot? snapshot,
  ) {
    final session = _currentGroupCall;
    if (session == null) return;

    final proto.CallTreeUpdate update;
    try {
      update = proto.CallTreeUpdate.fromBuffer(frame.payload);
    } catch (e) {
      _log.warn('CALL_TREE_UPDATE V3: parse failed: $e');
      return;
    }
    if (!_callIdMatches(session.callId, update.callId)) return;

    final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
    if (senderHex != session.initiatorHex) return;

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

    _setupRelay(session);

    _log.info('Tree updated V3: version=${update.version}, '
        'depth=${session.tree.depth}');
  }

  /// V3 receive-handler for CALL_RTT_PING.
  ///
  /// Live-class per §10.4.5; reply pong is dispatched on the per-call
  /// route cache via [_sendLiveMediaToParticipant] (no extra ML-DSA).
  void handleCallRttPingV3(
    proto.ApplicationFrameV3 frame,
    Uint8List senderDeviceId,
    SenderIdentitySnapshot? snapshot,
  ) {
    final session = _currentGroupCall;
    if (session == null || session.rtt == null) return;

    final proto.CallRttPing ping;
    try {
      ping = proto.CallRttPing.fromBuffer(frame.payload);
    } catch (e) {
      _log.warn('CALL_RTT_PING V3: parse failed: $e');
      return;
    }
    if (!_callIdMatches(session.callId, ping.callId)) return;

    final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));

    final pong = proto.CallRttPong()
      ..callId = session.callId
      ..echoTimestampUs = ping.timestampUs
      ..responderTimestampUs = Int64(DateTime.now().microsecondsSinceEpoch);

    _sendLiveMediaToParticipant(
      senderHex,
      proto.MessageTypeV3.MTV3_CALL_RTT_PONG,
      pong.writeToBuffer(),
    );
  }

  /// V3 receive-handler for CALL_RTT_PONG.
  void handleCallRttPongV3(
    proto.ApplicationFrameV3 frame,
    Uint8List senderDeviceId,
    SenderIdentitySnapshot? snapshot,
  ) {
    final session = _currentGroupCall;
    if (session == null || session.rtt == null) return;

    final proto.CallRttPong pong;
    try {
      pong = proto.CallRttPong.fromBuffer(frame.payload);
    } catch (e) {
      _log.warn('CALL_RTT_PONG V3: parse failed: $e');
      return;
    }
    if (!_callIdMatches(session.callId, pong.callId)) return;

    final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
    session.rtt!.handlePong(senderHex, pong.echoTimestampUs.toInt());
  }

  /// V3 receive-handler for GROUP_CALL_KEY_ROTATE.
  ///
  /// Setup-class frame (multi-device fan-out via sendToUser); inner User-Sig
  /// already verified upstream. Only accepts rotations from the initiator.
  /// DEPRECATED (§10.2.1): group media no longer uses a shared rotating key.
  /// Retained as a wire-compat no-op — per-sender keys arrive via
  /// GROUP_CALL_SENDER_KEY (handleGroupCallSenderKeyV3) instead.
  void handleGroupCallKeyRotateV3(
    proto.ApplicationFrameV3 frame,
    Uint8List senderDeviceId,
    SenderIdentitySnapshot? snapshot,
  ) {
    _log.debug('GROUP_CALL_KEY_ROTATE V3 ignored — superseded by per-sender '
        'keys (§10.2.1)');
  }

  /// V3 receive-handler for GROUP_CALL_SENDER_KEY (§10.2.1). Registers an
  /// authenticated peer's secret media key.
  ///
  /// SECURITY: the announcement's inner ApplicationFrame is signed by
  /// `frame.senderUserId` (verified upstream in the V3 receive pipeline). We
  /// require the announced `sender_node_id` to equal that authenticated id —
  /// so a participant can only register a key under its OWN identity and
  /// cannot frame another by announcing a key for the victim's id.
  void handleGroupCallSenderKeyV3(
    proto.ApplicationFrameV3 frame,
    Uint8List senderDeviceId,
    SenderIdentitySnapshot? snapshot,
  ) {
    final session = _currentGroupCall;
    if (session == null) return;

    final proto.GroupCallSenderKey ann;
    try {
      ann = proto.GroupCallSenderKey.fromBuffer(frame.payload);
    } catch (e) {
      _log.warn('GROUP_CALL_SENDER_KEY V3: parse failed: $e');
      return;
    }
    if (!_callIdMatches(session.callId, ann.callId)) return;

    final authedHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
    final announcedHex = bytesToHex(Uint8List.fromList(ann.senderNodeId));
    if (announcedHex != authedHex) {
      _log.warn('GROUP_CALL_SENDER_KEY V3: id mismatch '
          '(authed=${authedHex.substring(0, 8)} '
          'announced=${announcedHex.substring(0, 8)}) — drop');
      return;
    }
    if (!session.participants.containsKey(authedHex)) return;
    if (ann.sendKey.length != 32) return;

    final existing = session.peerSendKeys[authedHex];
    if (existing != null && ann.keyVersion <= existing.version) return;

    final key = Uint8List.fromList(ann.sendKey);
    session.peerSendKeys[authedHex] = (key: key, version: ann.keyVersion);
    onPeerSendKey?.call(authedHex, key, ann.keyVersion);
    _log.info('Registered send_key v${ann.keyVersion} for '
        '${authedHex.substring(0, 8)}');

    // Reciprocate so the pairwise exchange converges even if our own announce
    // raced or was lost (either side's inbound key triggers the response).
    if (!session.announcedSendKeyTo.contains(authedHex)) {
      _announceSendKeyTo(session, authedHex);
    }
  }

  /// V3 receive-handler for CALL_GROUP_AUDIO (relay frame to children).
  ///
  /// Live-frame path per §4.4.5 / §10.4.5 — skip-ML-DSA + skip-zstd. The
  /// inner `frame.payload` is the serialized [proto.GroupCallAudio]; relay
  /// duty just forwards the raw payload bytes downstream via MediaRelay.
  /// AES-GCM under `call_key` carries pro-frame authenticity (§4.4.5).
  void handleGroupCallAudioV3(
    proto.ApplicationFrameV3 frame,
    Uint8List senderDeviceId,
    SenderIdentitySnapshot? snapshot,
  ) {
    final session = _currentGroupCall;
    if (session == null || session.state != GroupCallState.inCall) return;

    session.totalFramesReceived++;

    if (session.relay != null) {
      session.relay!.forwardFrame(Uint8List.fromList(frame.payload));
    }
  }

  /// V3 receive-handler for CALL_GROUP_VIDEO (relay frame to children). Same live-frame semantics as
  /// [handleGroupCallAudioV3].
  void handleGroupCallVideoV3(
    proto.ApplicationFrameV3 frame,
    Uint8List senderDeviceId,
    SenderIdentitySnapshot? snapshot,
  ) {
    final session = _currentGroupCall;
    if (session == null || session.state != GroupCallState.inCall) return;

    session.videoFramesReceived++;

    if (session.relay != null) {
      session.relay!.forwardFrame(Uint8List.fromList(frame.payload));
    }
  }

  /// V3 outer-reply busy auto-reject. The peer device-id is delivered
  /// directly on the inbound `NetworkPacketV3`, so no routing
  /// re-resolution is needed.
  void _sendRejectV3(
    proto.ApplicationFrameV3 incoming,
    Uint8List senderDeviceId,
    String reason,
  ) {
    try {
      final invite = proto.CallInvite.fromBuffer(incoming.payload);
      final senderUserId = Uint8List.fromList(incoming.senderUserId);
      final senderHex = bytesToHex(senderUserId);
      final contact = contacts[senderHex];
      if (contact == null ||
          contact.x25519Pk == null ||
          contact.mlKemPk == null) {
        _log.debug('busy-reject V3: missing KEM pubkeys for '
            '${senderHex.substring(0, 8)} — drop');
        return;
      }

      // TODO(v3-sub-message): swap to `CallRejectV3` once defined.
      final reject = proto.CallReject()
        ..callId = invite.callId
        ..reason = reason;
      _sendV3PacketToDevice(
        targetDeviceId: senderDeviceId,
        peerUserId: senderUserId,
        peerX25519Pk: contact.x25519Pk!,
        peerMlKemPk: contact.mlKemPk!,
        type: proto.MessageTypeV3.MTV3_CALL_REJECT,
        payload: reject.writeToBuffer(),
        // Reject is setup-class; keep the hybrid outer + PoW for full §2.4
        // sender pipeline.
        applicationFlavor: true,
        skipPoW: false,
      );
    } catch (e) {
      _log.debug('busy-reject V3 build failed: $e');
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  /// Send a live-media (or per-call ephemeral) frame to a participant
  /// identified by their userIdHex. Resolves the participant's device
  /// via the routing table (cached per-session in
  /// [_participantRouteCache] — Architecture §10.4.1) and dispatches via
  /// `node.sendToDevice` with `applicationFlavor=false, skipPoW=true`
  /// (Ed25519-only outer, no PoW — Architecture §10.3).
  void _sendLiveMediaToParticipant(
    String participantHex,
    proto.MessageTypeV3 type,
    Uint8List payload,
  ) {
    final contact = contacts[participantHex];
    if (contact == null ||
        contact.x25519Pk == null ||
        contact.mlKemPk == null) {
      _log.debug('live-media: missing KEM pubkeys for '
          '${participantHex.substring(0, 8)}');
      return;
    }
    final peerUserId = hexToBytes(participantHex);
    PeerInfo? peer = _participantRouteCache[participantHex];
    if (peer == null) {
      peer = node.routingTable.getPeer(peerUserId) ??
          node.routingTable.getPeerByUserId(peerUserId);
      if (peer != null) {
        _participantRouteCache[participantHex] = peer;
      }
    }
    if (peer == null) {
      _log.debug('live-media: no peer for '
          '${participantHex.substring(0, 8)}');
      return;
    }

    _sendV3PacketToDevice(
      targetDeviceId: peer.nodeId,
      peerUserId: peerUserId,
      peerX25519Pk: contact.x25519Pk!,
      peerMlKemPk: contact.mlKemPk!,
      type: type,
      payload: payload,
      applicationFlavor: false,
      skipPoW: true,
    );
  }

  /// Build the V3 inner+outer for a single recipient device and dispatch
  /// via `node.sendToDevice`. Common path for live-media frames and
  /// outer-replies — the only knobs are `applicationFlavor` (Ed25519+ML-DSA
  /// vs Ed25519-only outer device-sig) and `skipPoW`.
  void _sendV3PacketToDevice({
    required Uint8List targetDeviceId,
    required Uint8List peerUserId,
    required Uint8List peerX25519Pk,
    required Uint8List peerMlKemPk,
    required proto.MessageTypeV3 type,
    required Uint8List payload,
    required bool applicationFlavor,
    required bool skipPoW,
  }) {
    try {
      final inner = proto.ApplicationFrameV3()
        ..version = 1
        ..recipientUserId = peerUserId
        ..senderUserId = identity.userId
        ..messageType = type
        ..messageId = SodiumFFI().randomBytes(16)
        ..timestampMs = Int64(DateTime.now().millisecondsSinceEpoch)
        ..payload = payload;
      final innerBytes = V3FrameCodec.buildAndEncryptInner(
        inner: inner,
        senderUserEd25519Sk: identity.signingEd25519Sk,
        senderUserMlDsaSk: identity.signingMlDsaSk,
        recipientUserX25519Pk: peerX25519Pk,
        recipientUserMlKemPk: peerMlKemPk,
      );
      final outer = V3FrameCodec.buildOuter(
        nextHopDeviceId: targetDeviceId,
        senderDeviceId: node.primaryIdentity.deviceNodeId,
        deviceKeys: node.deviceKeyPair,
        innerPayload: innerBytes,
        payloadType: proto.PayloadTypeV3.PAYLOAD_APPLICATION_FRAME,
        applicationFlavor: applicationFlavor,
        skipPoW: skipPoW,
      );
      // ignore: discarded_futures
      node.sendToDevice(outer, targetDeviceId);
    } catch (e) {
      _log.debug('V3 send build failed: $e');
    }
  }

  bool _callIdMatches(Uint8List a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
