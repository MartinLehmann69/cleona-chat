import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/calls/group_call_session.dart';
import 'package:cleona/core/calls/collaboration/whiteboard_manager.dart';
import 'package:cleona/core/calls/collaboration/call_chat_manager.dart';
import 'package:cleona/core/calls/collaboration/call_file_manager.dart';
import 'package:cleona/core/calls/collaboration/screen_share_manager.dart';
import 'package:cleona/core/calls/lan_multicast.dart';
import 'package:cleona/core/calls/media_relay.dart';
import 'package:cleona/core/calls/rtt_measurement.dart';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/calls/upload_probe.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/calls/punch_window.dart';
import 'package:fixnum/fixnum.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/util/hex.dart' show bytesToHex, hexToBytes;
import 'package:cleona/core/calls/call_arbitration.dart';
import 'package:cleona/core/calls/call_control_frame.dart';
import 'package:cleona/core/calls/group_media_frame.dart';
import 'package:cleona/core/calls/punch_window.dart' show PunchOutcome;
import 'package:cleona/core/calls/call_transport.dart';
import 'package:cleona/core/link_io/d_frame.dart';
import 'package:cleona/core/identity/identity_context.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/core/service/harvest_event.dart';
import 'package:cleona/generated/proto/app_payloads.pb.dart' as proto;
import 'package:cleona/generated/proto/transport_v3.pb.dart' as proto;

/// How a group call multiplies its media.
///
/// **Two values, no third option** — at least not in this
/// code. `sendGroupAudioFrame` has exactly two branches: [MediaRelay] if
/// `session.relay` is set, otherwise a loop over all who have joined. The
/// tiering from the S367 proposal (LAN multicast as step 1) is not a
/// third value of this enum, but a property of INDIVIDUAL edges in the
/// tree — it is in `TreeNode.isLanClusterHead`.
enum GroupCallTopology {
  /// Every participant sends every frame to every other one. Upload
  /// `(N-1) x bitrate`, grows linearly with the group, latency minimal (one
  /// hop). The fallback branch in `sendGroupAudioFrame`.
  mesh,

  /// Everyone sends to at most [OverlayTree.maxFanOut] children and forwards
  /// what they receive. Upload constant, latency grows with the
  /// depth. The [MediaRelay] branch in `sendGroupAudioFrame`.
  tree,
}

/// Manages group call signaling, overlay tree, and media relay.
///
/// Completely independent from [CallManager] (1:1 calls).
///
/// **The Plane D path carries a PAIRWISE `call_key` per hop**
/// (owner decision E-1 = B, 06.09.2026). Until then this said "Uses a
/// shared call_key for all participants (not per-pair DH)" — the opposite.
/// §17.7 makes every relay in the crystal itself a participant; a
/// shared hop key would thus let every participant forge being any other
/// on every hop. The carrier of the pair material is
/// `GroupCallSenderKey` — the message that according to §10.2.1 flies over
/// exactly this pair set anyway.
///
/// V3 Send Model (Architecture §10.2 + §10.3):
///   * Setup frames (CALL_INVITE/ANSWER/REJECT/HANGUP/GROUP_LEAVE/
///     GROUP_KEY_ROTATE/REJOIN-key-handoff) → `sendViaUser` callback.
///     Reaches all of the recipient user's authorized devices via the
///     `service.sendToUser` 2D-DHT-resolved fan-out (§26).
///   * Control information (tree assignment, RTT probes, speech level,
///     readiness) → `CallTransport.sendControl` as a CONTROL FRAME of
///     Plane D (§17.1.1, fourth frame kind, 176 B voice class, 1 Hz
///     bundled).
///
///     **Until S368 the opposite stood here:** "Live-media frames
///     (CALL_GROUP_AUDIO/VIDEO, CALL_RTT_PING/PONG, CALL_TREE_UPDATE) →
///     `CallTransport.sendSecuredToParticipant`. Plane D has NO
///     carrier for them […] as long as the group topology is open (§17.5,
///     C-9/C-10/C-11, K31-3)." That was true and was the reason why
///     nobody except the initiator entered the forwarding tree.
///     §17.1.1 gives Plane D the fourth frame kind, and §17.7 closed K31-3
///     on 05.09.2026; the topology is no longer open
///     but normative.
///
///     ADDED S378: MEMBERSHIP, unaffected by this, has run since
///     E-1 = B not via the tree but via `GroupCallSenderKey`
///     (`joined_participants`), which the delivery layer carries.
///   * Media frames (CALL_GROUP_AUDIO/VIDEO) → `CallTransport.sendMedia`
///     as D frames (§17.1).
class GroupCallManager {
  final IdentityContext identity;
  /// AP-2b: the Plane D API instead of the raw node (MIGRATION §5.5).
  final CallTransport transport;
  final Map<String, ContactInfo> contacts;
  final Map<String, GroupInfo> Function() _getGroups;
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

  /// A group media frame whose sender could be resolved.
  ///
  /// **Until S369 the return path was missing here entirely.** [handleGroupMediaFrame]
  /// only passed the frame on to the tree children and never gave it to
  /// anyone itself; what was played was exclusively what came in via
  /// [handleGroupCallAudioV3] — i.e. via the DELIVERY LAYER.
  /// Exactly this path no longer exists in V4.1 (§17.1: "media does **not**
  /// run in delivery cells", and `call_service.handleCallVideoV3` says it
  /// verbatim). A node thus forwarded and heard nothing
  /// itself.
  ///
  /// [senderHex] is already resolved via `rosterSorted`, [body] is the
  /// body WITHOUT the header from `group_media_frame.dart`.
  void Function(String senderHex, DFrameKind kind, Uint8List body)?
      onGroupMediaBody;

  // Per-participant cached PeerInfo for live-media sendToDevice path.
  // Mirror of [CallSession.cachedRoute] but multi-target. Keyed by
  // participant userIdHex. Invalidated on DV-Routing route-down for the
  // associated deviceId.

  /// The upload probe of this NODE — not of this call.
  ///
  /// Passed in instead of built here, because it measures a property of the
  /// line and not of the conversation: the same node conducts
  /// 1:1 calls and group calls over the same line, and a value that
  /// fell back to `unknown` when switching between the two would be empty exactly
  /// when it is needed. `CallService` holds the one
  /// instance and feeds it from both send paths.
  final UploadProbe uploadProbe;

  GroupCallManager({
    required this.identity,
    required this.transport,
    required this.contacts,
    required this._getGroups,
    required String profileDir,
    UploadProbe? uploadProbe,
  })  : uploadProbe = uploadProbe ?? UploadProbe(),
        _log = CLogger.get('group-calls', profileDir: profileDir);

  GroupCallSession? get currentGroupCall => _currentGroupCall;
  bool get inGroupCall => _currentGroupCall?.state == GroupCallState.inCall;

  // ── Initiator Flow ──────────────────────────────────────────────────

  /// Start a group call. Generates call_key, sends CALL_INVITE to all members.
  Future<GroupCallSession?> startGroupCall(String groupIdHex) async {
    if (_currentGroupCall != null) {
      _log.warn('Already in a group call');
      return null;
    }

    final group = _getGroups()[groupIdHex];
    if (group == null) {
      _log.warn('Group $groupIdHex not found');
      return null;
    }

    final sodium = SodiumFFI();
    final callId = sodium.randomBytes(16);

    final session = GroupCallSession(
      callId: callId,
      groupIdHex: groupIdHex,
      groupName: group.name,
      initiatorHex: identity.userIdHex,
      direction: CallDirection.outgoing,
      state: GroupCallState.inviting,
    );

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
    // §17.3/E-1 = B: the INITIATOR too needs an ephemeral pair. Until
    // S372 only the callee drew it (`acceptGroupCall`), because it solely
    // served the multi-device arbitration — which the initiator pronounces
    // itself. As the DH share of the pairwise `call_key` every side
    // now needs it.
    _ensureOwnEph(session);
    _initCollaboration(session); // §10.5 in-call collaboration

    // Send CALL_INVITE to each member (KEM-encrypted individually, fan-out
    // to all of each member's authorized devices via sendToUser).
    //
    // ── ONE INVITE OF ITS OWN PER MEMBER, SINCE S368 ─────────────────────
    //
    // Until then ONE `payload` was built and sent to all. That worked
    // as long as the INVITE carried nothing pairwise. Since it carries the
    // Plane D material from §17.3/§17.4, it no longer works: the
    // session cookie is the key under which `DSocket` keeps the
    // session table (`d_socket.dart`, `_sessions[local.key]`), and
    // handing out the same number twice would mean not being able to open the second session
    // at all — `open` then throws.
    //
    // The candidates on the other hand are determined ONCE: they are a
    // property of this node, not of the counterpart, and their
    // determination is a system call (`NetworkInterface.list`).
    final ownCandidates = await transport.localCandidatesPacked();
    for (final member in group.members.values) {
      if (member.nodeIdHex == identity.userIdHex) continue;
      session.participants[member.nodeIdHex]?.state = ParticipantState.ringing;

      final invite = proto.CallInvite()
        ..callId = callId
        ..isGroupCall = true
        ..groupId = hexToBytes(groupIdHex);
      final cookie = transport.newDCookie();
      session.localDCookies[member.nodeIdHex] = cookie;
      invite.callerDCookie = cookie;
      if (ownCandidates.isNotEmpty) {
        invite.callerCandidates = ownCandidates;
      }

      await sendViaUser?.call(
        hexToBytes(member.nodeIdHex),
        proto.MessageTypeV3.MTV3_CALL_INVITE,
        invite.writeToBuffer(),
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

    // §17.2 multi-device arbitration: the ephemeral X25519 key is
    // the ONLY attribute by which the initiator can tell apart the devices of ONE participant
    // — and by which this device recognises itself in an
    // incoming CANCEL_OTHERS.
    //
    // Before, the group ANSWER carried only the `callId`. So the
    // initiator could not distinguish a participant's second ANSWER from a
    // repetition of the first, no CANCEL_OTHERS ever went
    // out, and the participant's other devices kept ringing —
    // in the group path without any time limit, because here there is no
    // `_startRingingTimeout` as in the 1:1 path.
    //
    // A real key pair and not 32 random bytes: the field is called
    // `callee_eph_x25519_pk`, and what is in it should be exactly that.
    //
    // Since E-1 = B the same value carries twice: it is additionally the
    // DH share of every pairwise `call_key` of this call (§17.3). One
    // pair per call and device suffices for that — every PAIR still
    // gets its own result, because the counter-share differs per
    // pair.
    _ensureOwnEph(session);

    // Send CALL_ANSWER to initiator (multi-device fan-out via sendToUser).
    final answer = proto.CallAnswer()
      ..callId = session.callId
      ..calleeEphX25519Pk = session.ephX25519Pk!;

    // §17.3/§17.4: the second half of the exchange. Only with it do
    // BOTH sides have both cookies and both candidate lists — that is the
    // point in time from which the punch window can run on both sides at
    // once.
    final ownCookie = transport.newDCookie();
    session.localDCookies[session.initiatorHex] = ownCookie;
    answer.calleeDCookie = ownCookie;
    final ownCandidates = await transport.localCandidatesPacked();
    if (ownCandidates.isNotEmpty) {
      answer.calleeCandidates = ownCandidates;
    }

    await sendViaUser?.call(
      hexToBytes(session.initiatorHex),
      proto.MessageTypeV3.MTV3_CALL_ANSWER,
      answer.writeToBuffer(),
    );

    // §17.3: the window runs FROM NOW, on both sides at once — the
    // initiator starts its own as soon as it has harvested this ANSWER.
    // Not awaited: it runs up to 30 s, and the call should already look
    // set up during that time. The same construction as in the 1:1 path
    // (`call_manager.dart`, `unawaited(_openMediaPath(call))`).
    unawaited(_openParticipantMediaPath(session, session.initiatorHex));

    _setupRttAndHealth(session);
    _initCollaboration(session); // §10.5 in-call collaboration
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
    transport.forgetParticipant(nodeIdHex);
    _unregisterLiveMediaDevice(session, nodeIdHex);
    _log.info('Participant left: ${nodeIdHex.substring(0, 8)}');

    // Rebuild tree (member left) — owner only.
    if (session.state == GroupCallState.inCall && session.isOwner(identity.userIdHex)) {
      session.tree.removeParticipant(nodeIdHex);
      _broadcastTreeUpdate(session);
    }

    // Owner transfer: if the departing participant was the tree owner,
    // elect a new owner deterministically (lowest lexicographic joined id).
    if (nodeIdHex == session.ownerHex) {
      final joined = session.joinedParticipantIds..sort();
      if (joined.isNotEmpty) {
        final newOwner = joined.first;
        _log.info('Owner transfer: ${nodeIdHex.substring(0, 8)} -> '
            '${newOwner.substring(0, 8)}');
        session.ownerHex = newOwner;
        if (newOwner == identity.userIdHex) {
          _rebuildTree(session);
        }
      }
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

    // ── COMPACT INSTEAD OF PROTO (S368/S369) ──────────────────────────────
    //
    // Here stood a `GroupCallAudio`. Measured with `writeToBuffer()` at
    // 70 B Opus: `call_id` 18 B, `sender_node_id` 34 B, a second
    // `sequence_number` read by nobody 2-3 B, the media field 104 B
    // (102 B content + 2 B framing) — together **158 B**, with sequence numbers
    // from 128 on **159 B**, against the then 85 B class capacity (since
    // 06.09.2026 it is 133 B).
    //
    // What remains is what the receiving side really needs: ONE byte of
    // origin, and the mixer packet unchanged. That is 103 B at 70 B
    // Opus — 55 B saved and **still 18 B too many**. The derivation
    // and the reason why even omission does not make it are in
    // `group_media_frame.dart` and at [_sendGroupLiveMediaFrame].
    final payload = packGroupMedia(
      session.rosterIndexOf(identity.userIdHex) ?? kUnknownSender,
      encryptedFrame,
    );

    // Send to tree children via MediaRelay (which calls _onSendUnicast /
    // _onSendMulticast — both end up at sendToDevice for live media).
    if (session.relay != null) {
      session.relay!.forwardFrame(Uint8List.fromList(payload),
          proto.MessageTypeV3.MTV3_CALL_GROUP_AUDIO);
    } else {
      // Fallback: direct send to all joined participants
      for (final pId in session.joinedParticipantIds) {
        if (pId == identity.userIdHex) continue;
        _sendGroupLiveMediaFrame(
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

    // The same compact form as for audio. Video does fit into its
    // class (`DFrameClass.stream`, 1157 B payload), but two formats
    // for the same subject would be two readers and two sources of error —
    // and the 52 B that `call_id` and `sender_node_id` cost are, for
    // video too, the bandwidth of two additional tiles.
    final payload = packGroupMedia(
      session.rosterIndexOf(identity.userIdHex) ?? kUnknownSender,
      serializedVideoFrame,
    );

    // Send to tree children via MediaRelay
    if (session.relay != null) {
      session.relay!.forwardFrame(Uint8List.fromList(payload),
          proto.MessageTypeV3.MTV3_CALL_GROUP_VIDEO);
    } else {
      for (final pId in session.joinedParticipantIds) {
        if (pId == identity.userIdHex) continue;
        _sendGroupLiveMediaFrame(
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

  /// Attempt to rejoin a group call after connection loss.
  /// Sends CALL_REJOIN to all joined participants, re-announces send key.
  Future<void> rejoinGroupCall() async {
    final session = _currentGroupCall;
    if (session == null) return;
    if (session.state == GroupCallState.ended) return;

    // Mark self as joined again
    session.state = GroupCallState.inCall;
    final self = session.participants[identity.userIdHex];
    if (self != null) {
      self.state = ParticipantState.joined;
      self.joinedAt = DateTime.now();
    }

    // Send CALL_REJOIN to all joined participants
    final rejoin = proto.CallRejoin()..callId = session.callId;
    final payload = rejoin.writeToBuffer();
    for (final pId in session.joinedParticipantIds) {
      if (pId == identity.userIdHex) continue;
      await sendViaUser?.call(
        hexToBytes(pId),
        proto.MessageTypeV3.MTV3_CALL_REJOIN,
        payload,
      );
    }

    // Re-announce our send key (no global rotation -- authorized set unchanged)
    session.announcedSendKeyTo.clear();
    await _announceSendKeyToAllJoined(session);

    // Restart RTT and health monitoring
    _setupRttAndHealth(session);

    _log.info('Rejoined group call: ${session.callIdHex.substring(0, 8)}');
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
    // §10.5 Collaboration cleanup
    _currentGroupCall?.whiteboard?.dispose();
    _currentGroupCall?.callChat?.dispose();
    _currentGroupCall?.fileManager?.dispose();
    _currentGroupCall?.screenShare?.dispose();
    final session = _currentGroupCall;
    if (session != null) _unregisterAllLiveMediaDevices(session);
    _currentGroupCall = null;
    transport.forgetAllParticipants();
  }

  // ── Tree Construction (initiator only) ──────────────────────────────

  void _rebuildTree(GroupCallSession session) {
    if (!session.isOwner(identity.userIdHex)) return;

    final participants = session.joinedParticipantIds;
    if (participants.length < 2) return;

    session.tree.build(
      participants: participants,
      initiatorHex: session.initiatorHex,
      routeCost: (a, b) => transport.routeCostTo(b, fallback: 10),
      rtt: session.rtt,
      // ── UNTIL S368 THIS LINE WAS A FACADE — NOT ANYMORE ───
      //
      // The finding, measured on 05.09.2026: `isSameSubnet` expects two
      // IP ADDRESSES and compares the /24 prefix for IPv4
      // (`lan_multicast.dart`). What was passed in, however, were the entries
      // from `joinedParticipantIds` — user identifiers in hex.
      // `InternetAddress` throws on them, the throw is caught, and the
      // function returns `false`:
      //
      //     isSameSubnet(hex, hex)         = false
      //     isSameSubnet(hex, THE SAME)    = false     <- even then
      //     isSameSubnet("192.168.10.5", "192.168.10.9") = true
      //
      // Consequence: `_detectLanClusters` NEVER formed a cluster,
      // `TreeNode.isLanClusterHead` NEVER became `true`, and
      // `MediaRelay.onSendMulticast` — the only path to
      // `CallLanMulticast` — was NEVER called.
      //
      // **What was missing was not the function but its feed.**
      // `63bef041` recorded the finding and explicitly changed NO
      // behaviour, with the rationale: "There is no address at all for a
      // group participant […] `GroupCallManager` calls
      // `transport.openMediaPath` NOWHERE." Exactly that is different now —
      // `_openParticipantMediaPath` enters the punch window's finding
      // into `session.peerMediaAddress`, and here it is
      // available.
      //
      // **A participant without an address clusters with nobody**, not even
      // with itself: as long as the punch window has not carried,
      // "same subnet" is not a question one answers with `false`,
      // but one that cannot be asked. Both
      // lead to the same result here, but for the right reason.
      //
      // **Not built along with it: sending via multicast.** Reasons 2 and 3
      // from `63bef041` stand unchanged — a sender does not learn
      // whether a local listener is there, and a multicast datagram
      // carries no Plane D AEAD. `onSendMulticast` therefore still
      // falls back to unicast per child; what changes is
      // solely that cluster detection is no longer blind.
      // For OURSELVES there is no address here: `peerMediaAddress` holds
      // the punch window's finding PER COUNTERPART, and none runs
      // against ourselves. That is not a gap — a cluster of two
      // participants in the same segment also arises without us, and GUESSING an
      // own address (say the first local interface)
      // would be exactly the facade that this line was until today.
      sameSubnet: (a, b) {
        final addrA = session.peerMediaAddress[a];
        final addrB = session.peerMediaAddress[b];
        if (addrA == null || addrB == null) return false;
        return isSameSubnet(addrA, addrB);
      },
    );

    _setupRelay(session);
    _broadcastTreeUpdate(session);
    _log.info('Tree built: ${participants.length} nodes, depth=${session.tree.depth}');

    // WHO ENTERS THIS TREE BESIDES US — answered, not left
    // open. Without this line a field log sees a built tree and
    // concludes from it that forwarding happens; in fact only
    // the initiator then sends to three children, and all the others mesh.
    final why = transport.treeMaintenanceUnavailableReason;
    if (why != null) {
      _log.warn('The tree stays with the initiator: $why — the remaining '
          '${participants.length - 1} participants keep meshing, and the '
          'enforced upper limit is therefore $maxParticipants '
          '(${effectiveTopology.name}), not $maxParticipantsTree');
    }
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
    session.relay!.onSendUnicast = (targetHex, frame, type) {
      _sendGroupLiveMediaFrame(targetHex, type, frame);
    };
    session.relay!.onSendMulticast = (frame, type) {
      // LAN multicast — not implemented in this MVP, use unicast fallback.
      // Each child gets a sendToDevice via the per-call cached route.
      final children = session.tree.childrenOf(identity.userIdHex);
      for (final child in children) {
        _sendGroupLiveMediaFrame(child, type, frame);
      }
    };
    session.relay!.onChildCrashed = (crashedHex) {
      final participant = session.participants[crashedHex];
      if (participant != null && participant.state == ParticipantState.joined) {
        participant.state = ParticipantState.crashed;
        onParticipantChanged?.call(crashedHex, ParticipantState.crashed);
        transport.forgetParticipant(crashedHex);
        _log.info('Participant crashed: ${crashedHex.substring(0, 8)}');
        if (session.isOwner(identity.userIdHex)) {
          session.tree.handleCrash(crashedHex);
          _broadcastTreeUpdate(session);
          // No key rotation on crash (per architecture)
        }
      }
    };
  }

  // ── S378: here stood the S368 version of _openParticipantMediaPath ──
  //
  // It took ONE shared `call_key` from the INVITE
  // (`CallInvite.group_call_key`). The owner decision **E-1 = B** then
  // replaced it with PAIRWISE keys: §17.7 makes every
  // relay in the crystal itself a participant, a shared
  // hop key would thus let everyone forge being anyone else on every hop.
  // The version in force stands further below and draws its
  // key from `session.pairKeys`; its derivation is there.
  //
  // With that the reason to bring `group_call_key` back into the proto also
  // disappears — it has no reader again.


  /// Distributes the plan — as an assignment PER PARTICIPANT, via the
  /// control plane (§17.1.1).
  ///
  /// ── WHY NO LONGER THE `CallTreeUpdate` PROTO ───────────────────
  ///
  /// Until S368 a `CallTreeUpdate` with the complete
  /// node list went to every participant here, via
  /// [_sendLiveMediaToParticipant] -> `sendSecuredToParticipant`. This
  /// path returned `noCarrier`, so none ever arrived. It cannot either:
  /// measured on 05.09.2026 this proto measures **270 B at 6
  /// nodes and 1134 B at 30** — against the 85 B that a control frame
  /// carried at the time (since 06.09.2026 it is 133 B). That would be 4 or 14
  /// frames at 1 Hz — with 133 B 3 or 9 —, i.e. several seconds for
  /// a plan that is outdated at the first change.
  ///
  /// A participant only needs two pieces of information from it anyway: who is
  /// my parent, who are my children. As indices into the sorted
  /// participant list that measures `6 + Kinderzahl` bytes and fits at every
  /// group size into ONE frame (rationale and model in §17.1.1:
  /// the star compaction there likewise addresses participants via
  /// their position, not via their identifier).
  Future<void> _broadcastTreeUpdate(GroupCallSession session) async {
    if (!session.isOwner(identity.userIdHex)) return;
    session.tree.version++;
    for (final pId in session.joinedParticipantIds) {
      if (pId == identity.userIdHex) continue;
      _sendTreeAssignment(session, pId);
    }
  }

  /// The assignment for EXACTLY ONE participant.
  void _sendTreeAssignment(GroupCallSession session, String participantHex) {
    final list = session.rosterSorted;
    final parent = session.tree.parentOf(participantHex);
    final parentIdx = parent == null ? kNoParent : list.indexOf(parent);
    if (parentIdx < 0) {
      // A parent that is not in the list is not a parent one can
      // name. Sending it would mean sending an index
      // that the receiver resolves to a STRANGER.
      _log.warn('Tree assignment for ${participantHex.substring(0, 8)} '
          'skipped: the parent is not in the participant list');
      return;
    }
    final kinder = <int>[];
    for (final k in session.tree.childrenOf(participantHex)) {
      final i = list.indexOf(k);
      if (i >= 0) kinder.add(i);
    }
    final record = buildTreeAssignment(
      treeVersion: session.tree.version,
      roster: rosterHash(list),
      parentIndex: parentIdx,
      childIndices: kinder,
    );
    final error =
        transport.sendControl(participantHex: participantHex, record: record);
    if (error != null) {
      _log.debug('Tree assignment to ${participantHex.substring(0, 8)} '
          'not accepted (${error.name})');
      return;
    }
    _log.info('Tree assignment v${session.tree.version} to '
        '${participantHex.substring(0, 8)}: parent '
        '${parentIdx == kNoParent ? "—" : parentIdx}, children $kinder '
        '(${record.wireLength} B in the control frame, §17.1.1)');
  }

  /// Accepts a control record from a participant (§17.1.1).
  ///
  /// Wired by `CallService` to `CallTransport.onControlRecord`.
  void handleControlRecord(String peerHex, ControlRecord record) {
    final session = _currentGroupCall;
    if (session == null) return;
    switch (record.type) {
      case ControlRecordType.treeAssignment:
        _applyTreeAssignment(session, peerHex, record);
      case ControlRecordType.rttPing:
        // The answer carries the same marker back. Only thereby
        // does the probe measure the run time and not the harvest cadence
        // (§17.1.1, reason 2).
        transport.sendControl(
          participantHex: peerHex,
          record: ControlRecord(ControlRecordType.rttPong, record.value),
        );
      case ControlRecordType.rttPong:
        // `handlePong` computes `jetzt - echo`. What is passed back is thus
        // the ORIGINAL timestamp from the ping, not the current
        // time — otherwise the measured run time would always be 0.
        final echo = _readMicros(record.value);
        if (echo != null) session.rtt?.handlePong(peerHex, echo);
      case ControlRecordType.speechLevel:
        if (record.value.isNotEmpty) {
          updateParticipantAudioLevel(peerHex, record.value[0] / 255.0);
        }
      case ControlRecordType.readiness:
        _log.debug('Readiness from ${peerHex.substring(0, 8)}: '
            '${record.value.isEmpty ? "—" : record.value[0]}');
    }
  }

  void _applyTreeAssignment(
      GroupCallSession session, String peerHex, ControlRecord record) {
    // ONLY FROM THE TREE OWNER. A plan from anyone would be an
    // invitation to re-hang a foreign participant's tree.
    if (peerHex != session.ownerHex) {
      _log.warn('Tree assignment from ${peerHex.substring(0, 8)} discarded — '
          'not the tree owner (${session.ownerHex.substring(0, 8)})');
      return;
    }
    final z = readTreeAssignment(record);
    if (z == null) {
      _log.warn('Tree assignment from ${peerHex.substring(0, 8)} is not '
          'well-formed — discarded (§17.1.1)');
      return;
    }
    final list = session.rosterSorted;
    // THE CHECKSUM IS THE ENTIRE PROTECTION OF THE INDEX SCHEME. If the
    // indices point into a list other than the own one, the assignment makes
    // this node the child of a stranger. That is worse than no
    // assignment, so it is discarded and reported.
    if (rosterHash(list) != z.roster) {
      _log.warn('Tree assignment v${z.treeVersion} discarded: it points to '
          'a different participant list (0x${z.roster.toRadixString(16)} '
          'instead of 0x${rosterHash(list).toRadixString(16)}) — probably a '
          'late join that has not reached us yet');
      return;
    }
    if (z.treeVersion <= session.tree.version) return;

    final me = identity.userIdHex;
    final parentHex = z.isRoot || z.parentIndex >= list.length
        ? null
        : list[z.parentIndex];
    final kinderHex = <String>[
      for (final i in z.childIndices)
        if (i < list.length) list[i],
    ];

    // The local tree gets exactly as much as [MediaRelay] asks:
    // `childrenOf(ich)` and `parentOf(ich)`. A complete tree would
    // not only be unnecessary here but unsupported — this node has never
    // seen the rest.
    final node = <Map<String, dynamic>>[
      {'nodeIdHex': me, 'parentHex': parentHex, 'childrenHex': kinderHex},
      if (parentHex != null)
        {'nodeIdHex': parentHex, 'parentHex': null, 'childrenHex': <String>[me]},
      for (final k in kinderHex)
        {'nodeIdHex': k, 'parentHex': me, 'childrenHex': <String>[]},
    ];
    session.tree.fromNodeList(node, parentHex ?? me);
    session.tree.version = z.treeVersion;

    // THIS IS ENTERING THE TREE. Without this line the participant has
    // a plan and still forwards nothing.
    _setupRelay(session);

    _log.info('Tree assignment v${z.treeVersion} applied: parent '
        '${parentHex == null ? "— (Wurzel)" : parentHex.substring(0, 8)}, '
        '${kinderHex.length} children — forwarding is in place (§17.7)');
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

  /// RTT probes via the CONTROL PLANE (§17.1.1), not via the
  /// delivery layer.
  ///
  /// Until S368 a `CallRttPing` proto went here via
  /// [_sendLiveMediaToParticipant] — i.e. via a path that
  /// returned `noCarrier`; no probe ever arrived, and
  /// `RttMeasurement` never had a measured value. §17.1.1 names the reason
  /// why the probe does not belong on the delivery layer anyway:
  /// there the measured value would be the harvest cadence and not the
  /// run time, "and a spanning tree over it is unweighted".
  void _sendRttPings(GroupCallSession session) {
    if (session.rtt == null) return;
    for (final pId in session.joinedParticipantIds) {
      if (pId == identity.userIdHex) continue;
      final ts = session.rtt!.createPing(pId);
      transport.sendControl(
        participantHex: pId,
        record: ControlRecord(ControlRecordType.rttPing, _writeMicros(ts)),
      );
    }
  }

  /// A timestamp in microseconds, 8 B big endian.
  ///
  /// Eight bytes and not four: `DateTime.now().microsecondsSinceEpoch`
  /// is around 1.8e15 in 2026 and fits into no 32 bits. A
  /// truncated timestamp would yield a run time that turns negative once every 71
  /// minutes.
  static Uint8List _writeMicros(int us) {
    final b = Uint8List(8);
    for (var i = 7; i >= 0; i--) {
      b[i] = us & 0xFF;
      us >>= 8;
    }
    return b;
  }

  static int? _readMicros(Uint8List b) {
    if (b.length != 8) return null;
    var v = 0;
    for (var i = 0; i < 8; i++) {
      v = (v << 8) | b[i];
    }
    return v;
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

  /// Our ephemeral X25519 pair for THIS call — once per call and
  /// device, not per pair.
  ///
  /// It carries two things at once, and that is no coincidence: it is the
  /// attribute of the multi-device arbitration (§17.2, `boundAnswerKeys`) AND
  /// the DH share of every pairwise `call_key` (§17.3, E-1 = B). A
  /// pair of its own per counterpart would not be needed: the counter-share differs per
  /// pair, so the DH result does too.
  void _ensureOwnEph(GroupCallSession session) {
    if (session.ephX25519Pk != null && session.ephX25519Sk != null) return;
    final kp = SodiumFFI().generateX25519KeyPair();
    session.ephX25519Pk = kp.publicKey;
    session.ephX25519Sk = kp.secretKey;
  }

  /// Our HALF of the Plane D material for exactly one pair (§17.3/§17.4).
  ///
  /// Synchronous and callable multiple times: the derivation only succeeds once
  /// the reverse direction has also arrived, and that can come BEFORE or AFTER our
  /// own address. Both paths must find the same half
  /// — a second cookie or a second encapsulation would
  /// invalidate the other side's pair key.
  void _ensurePairMaterialFor(
      GroupCallSession session, String participantUserHex) {
    _ensureOwnEph(session);
    if (!session.localDCookies.containsKey(participantUserHex)) {
      // ONE OF ITS OWN PER PAIR. The D socket keys its session table
      // by the local cookie and throws on reuse.
      session.localDCookies[participantUserHex] = transport.newDCookie();
    }
    if (session.ownKemSecretFor.containsKey(participantUserHex)) return;
    // ML-KEM TO THE PARTNER'S STATIC KEY — not to an
    // ephemeral one. That is the reason why a third party cannot form the pair key:
    // the round runs via the initiator, the
    // ephemeral share could theoretically pass through its hands —
    // but only the receiver itself can decapsulate.
    final pk = contacts[participantUserHex]?.mlKemPk;
    if (pk == null) {
      // NAMED, NOT SILENT. The pair key still comes into being (from the
      // DH alone), but without a PQ share — and that belongs in the log, not in
      // the assumption that it will be fine. Symmetric: if we lack its
      // key, it lacks our ciphertext, both sides leave out the same
      // share and arrive at the same result.
      _log.warn('Plane D: no static ML-KEM key for '
          '${participantUserHex.substring(0, 8)} — the pair key '
          'is created WITHOUT a PQ share (§17.3).');
      return;
    }
    try {
      final kem = OqsFFI().mlKemEncapsulate(pk);
      session.ownKemSecretFor[participantUserHex] = kem.sharedSecret;
      session.ownKemCtFor[participantUserHex] = kem.ciphertext;
    } catch (e) {
      _log.warn('Plane D: ML-KEM encapsulation to '
          '${participantUserHex.substring(0, 8)} failed: $e — the '
          'pair key is created without a PQ share.');
    }
  }

  /// The pairwise `call_key` (§17.3, E-1 = B), as soon as both halves are
  /// there. `null` as long as one is missing.
  ///
  /// ── THE SAME DERIVATION AS IN THE 1:1 PATH, THREE ADJUSTMENTS ────────────
  ///
  /// The model is `call_manager.dart` (`HKDF-SHA256(dh ‖ kem ‖ kem)`).
  /// What differs:
  ///
  ///   1. **The order does not come from the role.** In the 1:1 case there
  ///      are caller and callee; between two group participants
  ///      there are not. It is therefore decided lexicographically: the
  ///      smaller UserID is A. Both sides compute the same.
  ///   2. **Own domain.** `info` carries a different text than the
  ///      1:1 key and additionally the `callId` — the same
  ///      participant in two simultaneous calls gets two
  ///      keys.
  ///   3. **One ephemeral pair for all counterparts**, not one per
  ///      pair (see [_ensureOwnEph]).
  Uint8List? _derivePairKey(GroupCallSession session, String peerHex) {
    final ownSk = session.ephX25519Sk;
    final peerPk = session.peerEphPk[peerHex];
    if (ownSk == null || peerPk == null) return null;

    final sodium = SodiumFFI();
    final Uint8List dh;
    try {
      dh = sodium.x25519ScalarMult(ownSk, peerPk);
    } catch (e) {
      _log.warn('Plane D: DH with ${peerHex.substring(0, 8)} '
          'failed: $e — no pair key.');
      return null;
    }

    final ownKem = session.ownKemSecretFor[peerHex];
    final peerKem = session.peerKemSecretFor[peerHex];
    // A is the lexicographically smaller UserID. `kem_A` is the
    // secret that A GENERATED (A encapsulates to B) — on A's side the
    // own one, on B's side the decapsulated one.
    final weAreA = identity.userIdHex.compareTo(peerHex) < 0;
    final ikm = <int>[
      ...dh,
      ...?(weAreA ? ownKem : peerKem),
      ...?(weAreA ? peerKem : ownKem),
    ];
    final info = <int>[
      ...utf8.encode('cleona-group-pair-v1'),
      ...session.callId,
    ];
    return sodium.hkdfSha256(
      Uint8List.fromList(ikm),
      info: Uint8List.fromList(info),
      length: 32,
    );
  }

  /// Runs the punch window from §17.3 for ONE group participant.
  ///
  /// ── TWO AEADs, AND THEY STAY SEPARATE ────────────────────────────
  ///
  /// The key that goes in here is the **hop** key: the
  /// pairwise secret from [_derivePairKey], under which the AEAD of the
  /// D frame runs and on which, according to §17.4, the entire admission of the
  /// D socket depends ("the D socket responds **exclusively** to packets
  /// with a valid AEAD under `call_key` plus a session cookie"). It ends
  /// at every relay.
  ///
  /// The **content** of a media frame lies below that under
  /// `GroupCallSession.ownSendKey`/`peerSendKeys` — per SENDER, according to
  /// §10.2.1, and it survives every forwarding step.
  /// `sendGroupAudioFrame` therefore gets its frame already
  /// encrypted.
  ///
  /// **Whoever merges the two takes away either the content's
  /// sender authenticity or the hop's admission check.** §17.7
  /// makes every relay in the crystal itself a participant; a
  /// shared hop key would thus let everyone forge being anyone
  /// else on every hop. That is the owner decision E-1 = B.
  Future<void> _openParticipantMediaPath(
      GroupCallSession session, String participantHex) async {
    if (participantHex == identity.userIdHex) return;
    final local = session.localDCookies[participantHex];
    final foreign = session.peerDCookies[participantHex];
    final key = session.pairKeys[participantHex];
    if (local == null || foreign == null || key == null) {
      // REFUSED WITH A NAME, NOT SILENTLY. For the case without a
      // carrying pair, §17.3 explicitly requires a "clear message"; a participant
      // who joins and then stays silent is exactly what §17 rules out
      // here.
      final missing = local == null
          ? 'unser Cookie'
          : foreign == null
              ? 'the cookie of the other side'
              : 'the pairwise call_key';
      _log.warn('Plane D: no punch window for '
          '${participantHex.substring(0, 8)} — missing: $missing '
          '(§17.3/§17.4).');
      return;
    }
    final PunchOutcome out;
    try {
      out = await transport.openMediaPath(
        peerHex: participantHex,
        callKey: key,
        localCookie: local,
        remoteCookie: foreign,
        peerCandidatesPacked:
            session.peerCandidates[participantHex] ?? const <int>[],
      );
    } catch (e, st) {
      // A-1 CLASS. The caller attaches this method detached. A
      // throw without an observer runs into the zone handler of
      // `service_daemon.dart` and ends the WHOLE daemon (`exit(99)`).
      // Therefore the body catches itself — `unawaited()` alone catches
      // nothing in Dart.
      _log.error('Layer D: the punch window for '
          '${participantHex.substring(0, 8)} threw detached: $e\n$st');
      return;
    }
    if (!out.carried) {
      _log.error('Layer D does not carry for '
          '${participantHex.substring(0, 8)}: ${out.refusal} '
          '(${out.packetsSent} probes / ${out.bytesSent} B)');
      return;
    }
    _log.info('Layer D carries for ${participantHex.substring(0, 8)}: '
        '${out.address!.address}:${out.port} (${out.packetsSent} probes / '
        '${out.bytesSent} B, §17.3)');
  }

  /// Announce our current ownSendKey to one participant (setup-class: full
  /// Ed25519 + ML-DSA inner sig + KEM via sendViaUser). The recipient's
  /// inner-sig verification binds the key to us, so no other participant can
  /// register a key under our identity.
  ///
  /// **Since E-1 = B the same cell carries the Plane D pair material**
  /// (§17.3/§17.4). That is not an appendage but the rationale for
  /// the choice of carrier: §10.2.1 forces EVERY pair into this
  /// exchange anyway, so the cell already flies over exactly the pair set
  /// that needs a pairwise `call_key`. Four fields cost zero
  /// additional cells; a message of its own would have doubled the setup cells
  /// (working rule 5).
  Future<void> _announceSendKeyTo(
      GroupCallSession session, String participantUserHex) async {
    if (participantUserHex == identity.userIdHex) return;
    // ── A-1: THE WHOLE BODY LIES IN THE try ────────────────────────────
    //
    // Three call sites attach this method as a `void` expression
    // (`handleGroupCallAnswerV3`, `handleCallRejoinV3`,
    // `handleGroupCallSenderKeyV3`) — without `unawaited`, without
    // `catchError`. A throw from `sendViaUser` thus ran into the
    // zone handler of `service_daemon.dart` and ended the daemon
    // (`exit(99)`, `:514`). `unawaited()` at the call sites would NOT
    // have cured that: it only suppresses the lint warning. The catching
    // happens here, in the body, and thus for all three at once.
    try {
      _ensureOwnSendKey(session);
      _ensurePairMaterialFor(session, participantUserHex);

      final ann = proto.GroupCallSenderKey()
        ..callId = session.callId
        ..senderNodeId = identity.nodeId
        ..sendKey = session.ownSendKey!
        ..keyVersion = session.ownSendKeyVersion
        ..dEphX25519Pk = session.ephX25519Pk!
        ..dCookie = session.localDCookies[participantUserHex]!;
      final ct = session.ownKemCtFor[participantUserHex];
      if (ct != null) ann.dKemCiphertext = ct;
      final candidates = await transport.localCandidatesPacked();
      if (candidates.isNotEmpty) ann.dCandidates = candidates;

      // THE ROUND, AND ONLY FROM THE INITIATOR. Without it a
      // non-initiator never learns that another non-initiator has joined
      // (measured 06.09.2026) — and then neither the
      // sender-key meshing of §10.2.1 nor a pair key
      // forms between them.
      if (session.isInitiator) {
        for (final pId in session.joinedParticipantIds) {
          ann.joinedParticipants.add(hexToBytes(pId));
        }
      }

      final ok = await sendViaUser?.call(
        hexToBytes(participantUserHex),
        proto.MessageTypeV3.MTV3_CALL_GROUP_SENDER_KEY,
        ann.writeToBuffer(),
      );
      if (ok == true) session.announcedSendKeyTo.add(participantUserHex);
    } catch (e, st) {
      _log.error('GROUP_CALL_SENDER_KEY to '
          '${participantUserHex.substring(0, 8)} threw: $e\n$st');
    }
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
  ///
  /// Returns `true` if this INVITE created a **new ringing
  /// group call** — see [CallManager.handleCallInviteV3] for
  /// the rationale (A-4, the ringtone depends on it).
  bool handleGroupCallInviteV3(HarvestEvent event) {
    if (_currentGroupCall != null) {
      _sendRejectV3(event, 'busy');
      return false;
    }

    final proto.CallInvite invite;
    try {
      invite = proto.CallInvite.fromBuffer(event.payload);
    } catch (e) {
      _log.warn('GROUP_CALL_INVITE V3: payload parse failed: $e');
      return false;
    }
    if (!invite.isGroupCall) {
      _log.debug('GROUP_CALL_INVITE V3: isGroupCall=false — '
          'belongs to 1:1 CallManager, dropping');
      return false;
    }

    final senderHex = bytesToHex(Uint8List.fromList(event.senderUserId));
    final groupIdHex = bytesToHex(Uint8List.fromList(invite.groupId));

    final group = _getGroups()[groupIdHex];
    final groupName = group?.name ?? groupIdHex.substring(0, 8);

    final session = GroupCallSession(
      callId: Uint8List.fromList(invite.callId),
      groupIdHex: groupIdHex,
      groupName: groupName,
      initiatorHex: senderHex,
      direction: CallDirection.incoming,
      state: GroupCallState.ringing,
    );

    // S378: here the S368 version took over `invite.group_call_key` as
    // the shared `call_key` of the round. E-1 = B instead derives the Plane D
    // key PAIRWISE (§17.3/§17.4, `pairKeys`); the
    // proto field thus has no reader again.

    // §17.3/§17.4: the initiator's Plane D material. Without it there is
    // no punch window later — and without a punch window no session
    // over which media or control frames could run. Empty is a
    // statement ("this caller sets up no Plane D window"), not an
    // error; `acceptGroupCall` reports the case by name.
    if (invite.callerDCookie.isNotEmpty) {
      session.peerDCookies[senderHex] =
          Uint8List.fromList(invite.callerDCookie);
    }
    if (invite.callerCandidates.isNotEmpty) {
      session.peerCandidates[senderHex] =
          Uint8List.fromList(invite.callerCandidates);
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
        '(device=${_deviceLabel(event.senderDeviceId)}) in "$groupName"');
    return true;
  }

  /// V3 receive-handler for CALL_ANSWER (group).
  ///
  /// **Here the arbitration between several devices of ONE
  /// participant happens** (§17.2: "the first `ANSWER` binds the session to one
  /// device"). The situation is the same as in the 1:1 path, only per participant:
  ///
  ///   * The group INVITE goes to the UserID of every member and thus
  ///     makes ALL devices of the member ring (§14.2 — "One delivery
  ///     serves all devices").
  ///   * The ANSWER goes to the INITIATOR's tag. The sibling devices
  ///     never harvest it; none can know on its own that another one
  ///     has picked up.
  ///   * Only the initiator sees all ANSWERs of a participant in an
  ///     order. It is the only possible arbiter.
  ///
  /// What was missing before this version was not only the CANCEL_OTHERS — the
  /// ATTRIBUTE was missing: the group `CallAnswer` carried nothing besides the `callId`,
  /// so a participant's second ANSWER could not be distinguished from a
  /// repetition of the first. The binding value is
  /// now `callee_eph_x25519_pk` (see [acceptGroupCall]).
  ///
  /// **The 1:1 trap "second ANSWER overwrites the session key"
  /// does NOT exist here** — checked: the group `callKey` comes from the
  /// INVITE ([handleGroupCallInviteV3]), not from the ANSWER, and the
  /// per-sender keys (§10.2.1) come via
  /// `MTV3_CALL_GROUP_SENDER_KEY`. A second ANSWER thus never re-derived a
  /// key here. But it ran through three OTHER side effects
  /// unconditionally, and the binding lock below closes them too:
  ///
  ///   1. `_registerLiveMediaDevice` overwrites the identifier of the device that
  ///      answered FIRST with that of the second — the media binding
  ///      moved to the LOSING device. (The registration itself has been
  ///      without consequence since the CUT, §17.4; the overwrite would not stay so
  ///      as soon as admission depends on a session again.)
  ///   2. `_announceSendKeyTo` sends our send key a second
  ///      time to the same UserID (working rule 5).
  ///   3. `onParticipantChanged` fires again and `_scheduleTreeRebuild`
  ///      rebuilds the tree without cause.
  void handleGroupCallAnswerV3(HarvestEvent event) {
    final session = _currentGroupCall;
    if (session == null) return;

    final proto.CallAnswer answer;
    try {
      answer = proto.CallAnswer.fromBuffer(event.payload);
    } catch (e) {
      _log.warn('GROUP_CALL_ANSWER V3: parse failed: $e');
      return;
    }
    if (!_callIdMatches(session.callId, answer.callId)) return;

    final senderHex = bytesToHex(Uint8List.fromList(event.senderUserId));
    final participant = session.participants[senderHex];
    if (participant == null) return;

    // ── §17.2: the first ANSWER binds ────────────────────────────────
    // Comes BEFORE the capacity check: a participant who is already in
    // must not run against the limit through its second device
    // and get a 'full' sent to itself.
    final answerKey = answer.calleeEphX25519Pk.isEmpty
        ? null
        : Uint8List.fromList(answer.calleeEphX25519Pk);
    final bound = session.boundAnswerKeys[senderHex];
    if (bound != null) {
      if (CancelOthers.namesUs(answerKey, bound)) {
        _log.debug('Wiederholte ANSWER desselben Geraets von '
            '${senderHex.substring(0, 8)} — ignoriert');
        return;
      }
      _log.info('Second device of ${senderHex.substring(0, 8)} has '
          'picked up — the session stays with the first to answer, '
          'CANCEL_OTHERS goes out (again)');
      // Repeated and not kept quiet: that a second ANSWER
      // arrives is the evidence that the first CANCEL_OTHERS has not
      // (or not yet) reached the device. One cell, not N — and only
      // in the race case.
      unawaited(_sendGroupCancelOthers(session, senderHex, bound));
      return;
    }
    if (answerKey == null && participant.state == ParticipantState.joined) {
      // A participant with an old state: its ANSWER carries no
      // ephemeral key, so there is nothing to bind and nothing to
      // name. A CANCEL_OTHERS without a binding value would also take from the
      // participant the device that is currently speaking — none goes
      // out. What takes effect here nevertheless: the three side effects above do not
      // run a second time.
      _log.info('Further ANSWER from ${senderHex.substring(0, 8)} without '
          'ephemeral key (old state) — join already '
          'recorded, no arbitration possible');
      return;
    }

    // Enforce participant limit (Phase 3c): reject if we are already at max.
    final currentJoined = session.joinedParticipantIds.length;
    if (currentJoined >= maxParticipants) {
      _log.info('Group call full ($currentJoined/$maxParticipants), '
          'rejecting ${senderHex.substring(0, 8)}');
      participant.state = ParticipantState.left;
      final reject = proto.CallReject()
        ..callId = session.callId
        ..reason = 'full';
      // DETACHED, BUT OBSERVED. The `Future` is thrown away here
      // (the rejection is of no further interest to us), and an
      // unobserved Future error goes into the zone of
      // `service_daemon.dart` (~L424) — there everything outside the
      // survival list is `exit(99)`. A full group call must not kill a
      // daemon. The only other non-awaited
      // `sendViaUser` site in `lib/core/calls/` (S351).
      sendViaUser
          ?.call(
            hexToBytes(senderHex),
            proto.MessageTypeV3.MTV3_CALL_REJECT,
            reject.writeToBuffer(),
          )
          .catchError((Object e, StackTrace st) {
        _log.error('CALL_REJECT(full) threw (detached): $e\n$st');
        return false;
      });
      return;
    }

    // §17.2: from here on this participant is bound to EXACTLY THIS device.
    if (answerKey != null) {
      session.boundAnswerKeys[senderHex] = answerKey;
    }

    // §17.3/§17.4: the participant's Plane D material. It comes from
    // THIS ANSWER, i.e. from the answer of the device that bound the
    // session — that of a second device has already been
    // intercepted above.
    if (answer.calleeDCookie.isNotEmpty) {
      session.peerDCookies[senderHex] =
          Uint8List.fromList(answer.calleeDCookie);
    }
    if (answer.calleeCandidates.isNotEmpty) {
      session.peerCandidates[senderHex] =
          Uint8List.fromList(answer.calleeCandidates);
    }

    participant.state = ParticipantState.joined;
    participant.joinedAt = DateTime.now();
    onParticipantChanged?.call(senderHex, ParticipantState.joined);
    _registerLiveMediaDevice(session, senderHex, event.senderDeviceId);

    _log.info('Participant joined V3: ${senderHex.substring(0, 8)} '
        '(device=${_deviceLabel(event.senderDeviceId)})');

    // §17.3: see `acceptGroupCall` — both sides run their window
    // as soon as they have both halves. Not awaited, for the same
    // reason.
    unawaited(_openParticipantMediaPath(session, senderHex));

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

    // §17.2: the session is bound for this participant — the OTHER
    // devices of the participant are still ringing and only learn of it via us.
    // The ANSWER went to OUR tag, not to theirs (§14.2 — every device
    // harvests the tag of its own identity). ONE cell to the
    // identity of the participant reaches them all.
    //
    // Not only at the second ANSWER: if it were so, the ringing of the
    // siblings would only end when a SECOND device picks up — and if none
    // picks up, not at all. In the group path there is also no
    // time limit that would end it by itself.
    if (answerKey != null) {
      unawaited(_sendGroupCancelOthers(session, senderHex, answerKey));
    }
  }

  /// CANCEL_OTHERS (§17.2) to the IDENTITY of a participant.
  ///
  /// ONE cell for all remaining devices of this participant — §14.2:
  /// "One delivery serves all devices." The initiator deliberately does not iterate
  /// over devices; it does not know them and need not know them
  /// (§14.1).
  ///
  /// It goes to exactly ONE participant and not to the round: the
  /// ringing that ends here only runs on the sibling devices of this
  /// one. A broadcast would be N-1 deliveries for nothing.
  Future<void> _sendGroupCancelOthers(GroupCallSession session,
      String participantUserHex, Uint8List boundKey) async {
    try {
      final cancel = proto.CallCancelOthers()
        ..callId = session.callId
        ..boundAnswerKey = boundKey;
      await sendViaUser?.call(
        hexToBytes(participantUserHex),
        proto.MessageTypeV3.MTV3_CALL_CANCEL_OTHERS,
        cancel.writeToBuffer(),
      );
      _log.info('CANCEL_OTHERS (group) to '
          '${participantUserHex.substring(0, 8)} — the ringing on their '
          'other devices ends');
    } catch (e) {
      // Best effort like every other signal. Unlike in the 1:1 path there is
      // NO time limit here that ends the ringing by itself — that
      // stands as an open point in the report, not as a silent stopgap here.
      _log.warn('CANCEL_OTHERS (group) could not be sent: $e');
    }
  }

  /// V3 receive-handler for CALL_CANCEL_OTHERS (group, §17.2).
  ///
  /// Three outcomes, as in the 1:1 path ([CallManager.handleCallCancelOthersV3]),
  /// and the middle one is the one everything hinges on:
  ///
  ///   * **No matching call** — nothing to do. A memory for
  ///     ended group calls does not exist here; the group INVITE is
  ///     not repeated either (`startGroupCall` sends it once), so
  ///     the occasion that existed in the 1:1 path is missing.
  ///   * **We are the picking-up device** — the named key is
  ///     our own. Do nothing. Without this branch the device
  ///     that has just picked up would leave its own group call: the cell
  ///     goes to the IDENTITY and therefore also reaches the winner
  ///     (§14.2).
  ///   * **We are not** — end the ringing. Even if this
  ///     device itself has just picked up (race): the initiator has
  ///     decided, and it is the only one that can decide.
  ///
  /// At the INITIATOR the cell makes no sense — it is the sender.
  void handleGroupCallCancelOthersV3(HarvestEvent event) {
    final session = _currentGroupCall;
    if (session == null) return;

    final proto.CallCancelOthers cancel;
    try {
      cancel = proto.CallCancelOthers.fromBuffer(event.payload);
    } catch (e) {
      _log.warn('GROUP_CALL_CANCEL_OTHERS: payload not readable: $e');
      return;
    }
    if (!_callIdMatches(session.callId, cancel.callId)) return;

    // Without a usable binding key the winning device could not
    // recognise itself — the cell would take away its own
    // group call. Discarding is the safe direction.
    if (cancel.boundAnswerKey.length != CancelOthers.boundKeyLength) {
      _log.warn('GROUP_CALL_CANCEL_OTHERS without a usable '
          'binding key (${cancel.boundAnswerKey.length} instead of '
          '${CancelOthers.boundKeyLength} bytes) — discarded');
      return;
    }

    if (session.direction != CallDirection.incoming) {
      _log.debug('GROUP_CALL_CANCEL_OTHERS at the initiator — ignored');
      return;
    }

    // Only from the INITIATOR. It is the arbiter (§17.2); an arbitrary
    // fellow participant must not throw us out of the call.
    final senderHex = bytesToHex(Uint8List.fromList(event.senderUserId));
    if (senderHex != session.initiatorHex) {
      _log.warn('GROUP_CALL_CANCEL_OTHERS from '
          '${senderHex.substring(0, 8)}, not from the initiator '
          '(${session.initiatorHex.substring(0, 8)}) — discarded');
      return;
    }

    if (CancelOthers.namesUs(session.ephX25519Pk,
        Uint8List.fromList(cancel.boundAnswerKey))) {
      _log.info('CANCEL_OTHERS (group) names our own ephemeral '
          'key — this device is in the group call, nothing to do');
      return;
    }

    _log.info('Group call accepted on another own device — '
        'ringing ended here (§17.2 CANCEL_OTHERS)');
    _endCall(session);
  }

  /// V3 receive-handler for CALL_REJECT (group).
  void handleGroupCallRejectV3(HarvestEvent event) {
    final session = _currentGroupCall;
    if (session == null) return;

    final proto.CallReject reject;
    try {
      reject = proto.CallReject.fromBuffer(event.payload);
    } catch (e) {
      _log.warn('GROUP_CALL_REJECT V3: parse failed: $e');
      return;
    }
    if (!_callIdMatches(session.callId, reject.callId)) return;

    final senderHex = bytesToHex(Uint8List.fromList(event.senderUserId));
    final participant = session.participants[senderHex];
    if (participant == null) return;

    participant.state = ParticipantState.left;
    onParticipantChanged?.call(senderHex, ParticipantState.left);
    _log.info('Participant rejected V3: ${senderHex.substring(0, 8)} '
        '(${reject.reason})');
  }

  /// V3 receive-handler for CALL_HANGUP (group).
  void handleGroupCallHangupV3(HarvestEvent event) {
    final session = _currentGroupCall;
    if (session == null) return;

    final proto.CallHangup hangup;
    try {
      hangup = proto.CallHangup.fromBuffer(event.payload);
    } catch (e) {
      _log.warn('GROUP_CALL_HANGUP V3: parse failed: $e');
      return;
    }
    if (!_callIdMatches(session.callId, hangup.callId)) return;

    final senderHex = bytesToHex(Uint8List.fromList(event.senderUserId));
    _participantLeft(session, senderHex);
  }

  /// V3 receive-handler for GROUP_CALL_LEAVE.
  void handleGroupCallLeaveV3(HarvestEvent event) {
    final session = _currentGroupCall;
    if (session == null) return;

    final proto.GroupCallLeave leave;
    try {
      leave = proto.GroupCallLeave.fromBuffer(event.payload);
    } catch (e) {
      _log.warn('GROUP_CALL_LEAVE V3: parse failed: $e');
      return;
    }
    if (!_callIdMatches(session.callId, leave.callId)) return;

    final senderHex = bytesToHex(Uint8List.fromList(event.senderUserId));
    _participantLeft(session, senderHex);
  }

  /// V3 receive-handler for CALL_REJOIN.
  void handleCallRejoinV3(HarvestEvent event) {
    final session = _currentGroupCall;
    if (session == null || session.state != GroupCallState.inCall) return;

    final proto.CallRejoin rejoin;
    try {
      rejoin = proto.CallRejoin.fromBuffer(event.payload);
    } catch (e) {
      _log.warn('CALL_REJOIN V3: parse failed: $e');
      return;
    }
    if (!_callIdMatches(session.callId, rejoin.callId)) return;

    final senderHex = bytesToHex(Uint8List.fromList(event.senderUserId));
    final participant = session.participants[senderHex];
    if (participant == null) return;

    participant.state = ParticipantState.joined;
    participant.joinedAt = DateTime.now();
    onParticipantChanged?.call(senderHex, ParticipantState.joined);
    _registerLiveMediaDevice(session, senderHex, event.senderDeviceId);
    _log.info('Participant rejoined V3: ${senderHex.substring(0, 8)} '
        '(device=${_deviceLabel(event.senderDeviceId)}, no global rotation)');

    if (session.isOwner(identity.userIdHex)) {
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
  /// new tree directly. Only accepts updates from the current tree owner.
  void handleCallTreeUpdateV3(HarvestEvent event) {
    final session = _currentGroupCall;
    if (session == null) return;

    final proto.CallTreeUpdate update;
    try {
      update = proto.CallTreeUpdate.fromBuffer(event.payload);
    } catch (e) {
      _log.warn('CALL_TREE_UPDATE V3: parse failed: $e');
      return;
    }
    if (!_callIdMatches(session.callId, update.callId)) return;

    final senderHex = bytesToHex(Uint8List.fromList(event.senderUserId));
    if (senderHex != session.ownerHex) return;

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
  void handleCallRttPingV3(HarvestEvent event) {
    final session = _currentGroupCall;
    if (session == null || session.rtt == null) return;

    final proto.CallRttPing ping;
    try {
      ping = proto.CallRttPing.fromBuffer(event.payload);
    } catch (e) {
      _log.warn('CALL_RTT_PING V3: parse failed: $e');
      return;
    }
    if (!_callIdMatches(session.callId, ping.callId)) return;

    final senderHex = bytesToHex(Uint8List.fromList(event.senderUserId));

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
  void handleCallRttPongV3(HarvestEvent event) {
    final session = _currentGroupCall;
    if (session == null || session.rtt == null) return;

    final proto.CallRttPong pong;
    try {
      pong = proto.CallRttPong.fromBuffer(event.payload);
    } catch (e) {
      _log.warn('CALL_RTT_PONG V3: parse failed: $e');
      return;
    }
    if (!_callIdMatches(session.callId, pong.callId)) return;

    final senderHex = bytesToHex(Uint8List.fromList(event.senderUserId));
    session.rtt!.handlePong(senderHex, pong.echoTimestampUs.toInt());
  }

  // S368: `handleGroupCallKeyRotateV3` is removed. The body was a
  // no-op, explicitly "Retained as a wire-compat no-op" — a
  // message type that this line only still accepted so that an older
  // remote side may send it. With it the dispatcher entry
  // (`cleona_service_receive.dart`), the forwarding
  // (`call_service.handleCallGroupKeyRotateV3`) and the protocol message
  // `GroupCallKeyRotate` together with type number 81 have fallen. Per-sender keys
  // come via GROUP_CALL_SENDER_KEY (`handleGroupCallSenderKeyV3`).

  /// V3 receive-handler for GROUP_CALL_SENDER_KEY (§10.2.1). Registers an
  /// authenticated peer's secret media key.
  ///
  /// SECURITY: the announcement's inner ApplicationFrame is signed by
  /// `frame.senderUserId` (verified upstream in the V3 receive pipeline). We
  /// require the announced `sender_node_id` to equal that authenticated id —
  /// so a participant can only register a key under its OWN identity and
  /// cannot frame another by announcing a key for the victim's id.
  void handleGroupCallSenderKeyV3(HarvestEvent event) {
    final session = _currentGroupCall;
    if (session == null) return;

    final proto.GroupCallSenderKey ann;
    try {
      ann = proto.GroupCallSenderKey.fromBuffer(event.payload);
    } catch (e) {
      _log.warn('GROUP_CALL_SENDER_KEY V3: parse failed: $e');
      return;
    }
    if (!_callIdMatches(session.callId, ann.callId)) return;

    final authedHex = bytesToHex(Uint8List.fromList(event.senderUserId));
    final announcedHex = bytesToHex(Uint8List.fromList(ann.senderNodeId));
    if (announcedHex != authedHex) {
      _log.warn('GROUP_CALL_SENDER_KEY V3: id mismatch '
          '(authed=${authedHex.substring(0, 8)} '
          'announced=${announcedHex.substring(0, 8)}) — drop');
      return;
    }
    if (!session.participants.containsKey(authedHex)) return;
    if (ann.sendKey.length != 32) return;

    // §13.1.2 exemption #4: the sender-key mesh handshake is how a
    // participant learns another participant's concrete device id when
    // they aren't the initiator (who learns it via CALL_ANSWER) — e.g. an
    // invitee learns the initiator's device id here, once the initiator
    // reciprocates its key. Register regardless of key-version freshness
    // below (an id can be learned even if this particular key round is
    // stale).
    _registerLiveMediaDevice(session, authedHex, event.senderDeviceId);

    // ── THE SELF-STATEMENT: WHOEVER SPEAKS HERE IS IN ─────────────────
    //
    // The sender has been checked against the outer identifier (above,
    // `announcedHex != authedHex` -> drop). That it is in this call
    // it thus says about ITSELF — no third-party statement, nothing to
    // believe. Without this line `joinedParticipantIds` stayed {me, initiator}
    // forever at every non-initiator (measured 06.09.2026),
    // and thus neither the sender-key meshing of
    // §10.2.1 nor a pair key between two non-initiators formed.
    final sender = session.participants[authedHex]!;
    if (sender.state != ParticipantState.joined) {
      sender.state = ParticipantState.joined;
      sender.joinedAt ??= DateTime.now();
      onParticipantChanged?.call(authedHex, ParticipantState.joined);
      _log.info('Participant ${authedHex.substring(0, 8)} has joined '
          '(from its own key handshake, §10.2.1)');
    }

    // ── THE INITIATOR'S ROUND ──────────────────────────────────────
    //
    // A third-party statement, but one without consequence: it carries no authorisation.
    // Someone named falsely gets an address that ends in no
    // pair key, because they cannot supply the counter-material.
    // Only the initiator fills the field (§17.2 arbiter, §17.7
    // root); from anyone else it is ignored.
    final newKnown = <String>[];
    if (authedHex == session.initiatorHex) {
      for (final raw in ann.joinedParticipants) {
        final hex = bytesToHex(Uint8List.fromList(raw));
        if (hex == identity.userIdHex) continue;
        final p = session.participants[hex];
        if (p == null) continue; // not a group member — nothing to do
        if (p.state == ParticipantState.joined) continue;
        p.state = ParticipantState.joined;
        p.joinedAt ??= DateTime.now();
        onParticipantChanged?.call(hex, ParticipantState.joined);
        newKnown.add(hex);
      }
      if (newKnown.isNotEmpty) {
        _log.info('Round from the initiator: ${newKnown.length} more '
            'participants known — '
            '${newKnown.map((h) => h.substring(0, 8)).join(", ")}');
      }
    }

    // ── PLANE D PAIR MATERIAL (§17.3/§17.4, E-1 = B) ───────────────────
    //
    // Our half first, and INDEPENDENTLY of whether we have already
    // addressed them: the derivation needs both, and which one is there
    // first is decided by the race on the line.
    _ensurePairMaterialFor(session, authedHex);
    if (ann.dEphX25519Pk.isNotEmpty) {
      session.peerEphPk[authedHex] = Uint8List.fromList(ann.dEphX25519Pk);
    }
    if (ann.dCookie.isNotEmpty) {
      session.peerDCookies[authedHex] = Uint8List.fromList(ann.dCookie);
    }
    if (ann.dCandidates.isNotEmpty) {
      session.peerCandidates[authedHex] = Uint8List.fromList(ann.dCandidates);
    }
    if (ann.dKemCiphertext.isNotEmpty &&
        !session.peerKemSecretFor.containsKey(authedHex)) {
      try {
        session.peerKemSecretFor[authedHex] = OqsFFI().mlKemDecapsulate(
          Uint8List.fromList(ann.dKemCiphertext),
          identity.mlKemSecretKey,
        );
      } catch (e) {
        // Named, not silent: the pair key then comes into being without
        // our receive share — and thus deviates from the result of the
        // other side. The punch window then runs into nothing, and
        // exactly this line says why.
        _log.warn('Plane D: ML-KEM decapsulation from '
            '${authedHex.substring(0, 8)} failed: $e');
      }
    }
    final pair = _derivePairKey(session, authedHex);
    if (pair != null) {
      session.pairKeys[authedHex] = pair;
    }

    final existing = session.peerSendKeys[authedHex];
    final fresh = existing == null || ann.keyVersion > existing.version;
    if (fresh) {
      final key = Uint8List.fromList(ann.sendKey);
      session.peerSendKeys[authedHex] = (key: key, version: ann.keyVersion);
      onPeerSendKey?.call(authedHex, key, ann.keyVersion);
      _log.info('Registered send_key v${ann.keyVersion} for '
          '${authedHex.substring(0, 8)}');
    }

    // Reciprocate so the pairwise exchange converges even if our own announce
    // raced or was lost (either side's inbound key triggers the response).
    if (!session.announcedSendKeyTo.contains(authedHex)) {
      unawaited(_announceSendKeyTo(session, authedHex));
    }

    // Address the newly known participants. THAT is the
    // step that lets the meshing come into being in the first place — and
    // it costs not one cell more than §10.2.1 requires anyway.
    for (final hex in newKnown) {
      if (session.announcedSendKeyTo.contains(hex)) continue;
      unawaited(_announceSendKeyTo(session, hex));
    }

    // §17.3: the window runs as soon as both halves are there — on
    // both sides at once. ONCE per participant: it runs up to 30 s,
    // and a second attempt per arriving cell would be exactly the
    // traffic that working rule 5 rules out.
    if (session.pairKeys.containsKey(authedHex) &&
        session.peerDCookies.containsKey(authedHex) &&
        session.mediaPathStarted.add(authedHex)) {
      unawaited(_openParticipantMediaPath(session, authedHex));
    }
  }

  /// V3 receive-handler for CALL_GROUP_AUDIO (relay frame to children).
  ///
  /// Live-frame path per §4.4.5 / §10.4.5 — skip-ML-DSA + skip-zstd. The
  /// inner `frame.payload` is the serialized [proto.GroupCallAudio]; relay
  /// duty just forwards the raw payload bytes downstream via MediaRelay.
  /// AES-GCM under `call_key` carries pro-frame authenticity (§4.4.5).
  /// A GROUP media frame that arrived via Plane D (§17.1).
  ///
  /// ── WHY THIS PATH IS NEEDED ───────────────────────────────────
  ///
  /// [handleGroupCallAudioV3] and [handleGroupCallVideoV3] take a
  /// `HarvestEvent` — i.e. a frame that the DELIVERY LAYER harvested.
  /// A Plane D frame never arrives there; it comes via
  /// `CallTransport.onMediaFrame`. Measured on 05.09.2026, this
  /// return path ran exclusively into the 1:1 call: `call_service.dart` checks
  /// `callManager.currentCall` and discarded everything that did not match —
  /// a group frame was thus silently dropped, even if a
  /// session would have carried it.
  ///
  /// ── WHAT CARRIES HERE AND WHAT DOES NOT, MEASURED ───────────────────────
  ///
  /// **Video carries.** It rides on `DFrameClass.stream` (1200 B,
  /// 1157 B payload); a `GroupCallVideo` with identifier, sender and
  /// one fragment fits in.
  ///
  /// **Audio now carries too** — since the voice class measures 176 B
  /// (owner decision 06.09.2026; 160 B on 05.09.). A group frame
  /// costs `index(1) ‖ seq(4) ‖ nonce(12) ‖ Opus ‖ send_key-Marke(16)` =
  /// **33 B plus Opus**, against **133 B** of payload.
  ///
  /// **And it carries completely since the encoder is capped.** Until
  /// 06.09.2026, 0.3-1.0 % of group frames were dropped: Opus fits here
  /// up to 100 B, and the frames reached further — 95 B, then 110 B, then
  /// 116 B, depending on the amount of signal. The reason was not the class but
  /// that 28 kbit/s was a TARGET and not a cap. Since
  /// `OPUS_SET_VBR = 0` (`OpusFFI._configureEncoder`) every
  /// Opus frame measures exactly `opusCbrFrameBytes` = 70 B; a group frame thus
  /// **always measures 103 B** and has 30 B of headroom. Measured, not computed:
  /// a single frame size across 4000 frames at 48 and 16 kHz and
  /// across 200 stimulus frames each at all five admitted sample rates,
  /// zero rejections by the sealer in both cases.
  ///
  /// Frames that are too large would still be rejected when SENDING as
  /// [MediaSendFailure.tooLarge] and would not arrive here —
  /// the path stays, it just has nothing left to do.
  void handleGroupMediaFrame(String peerHex, DFrame frame) {
    final session = _currentGroupCall;
    if (session == null || session.state != GroupCallState.inCall) return;
    if (!session.participants.containsKey(peerHex)) return;

    final type = frame.kind == DFrameKind.video
        ? proto.MessageTypeV3.MTV3_CALL_GROUP_VIDEO
        : proto.MessageTypeV3.MTV3_CALL_GROUP_AUDIO;
    if (frame.kind == DFrameKind.video) {
      session.videoFramesReceived++;
    } else {
      session.totalFramesReceived++;
    }

    // THIS IS THE FORWARDING. Without `session.relay` — i.e. without an
    // arrived tree assignment — nothing happens here, and exactly by this
    // the guard measures whether the tree is ENTERED and not merely
    // built.
    session.relay?.forwardFrame(Uint8List.fromList(frame.payload), type);

    // AND THIS IS HEARING IT ONESELF. Forwarding and playing are two
    // duties, not one; until S369 only the first stood here.
    _deliverGroupMediaBody(session, frame);
  }

  /// Resolves the sender from the header and passes the body up.
  ///
  /// The index comes from `rosterSorted` and not from the D cookie: the
  /// cookie names the last hop. The rationale in full length is
  /// in `group_media_frame.dart`.
  void _deliverGroupMediaBody(GroupCallSession session, DFrame frame) {
    final sink = onGroupMediaBody;
    if (sink == null) return;

    final parsed = unpackGroupMedia(Uint8List.fromList(frame.payload));
    if (parsed == null || !parsed.hasSender) return;

    final roster = session.rosterSorted;
    if (parsed.senderIndex >= roster.length) {
      // The participant sets have diverged (a join that
      // we have not seen yet). Discard, do not guess — a
      // guessed place would attribute the frame to a FOREIGN speaker.
      _log.debug('Group media: sender slot ${parsed.senderIndex} lies '
          'outside the list (${roster.length}) — dropped');
      return;
    }

    final senderHex = roster[parsed.senderIndex];
    // The own frame comes back via the tree if we ourselves
    // forward. Mixing it would mean hearing oneself.
    if (senderHex == identity.userIdHex) return;

    sink(senderHex, frame.kind, parsed.body);
  }

  void handleGroupCallAudioV3(HarvestEvent event) {
    final session = _currentGroupCall;
    if (session == null || session.state != GroupCallState.inCall) return;

    session.totalFramesReceived++;

    if (session.relay != null) {
      session.relay!.forwardFrame(Uint8List.fromList(event.payload),
          proto.MessageTypeV3.MTV3_CALL_GROUP_AUDIO);
    }
  }

  /// V3 receive-handler for CALL_GROUP_VIDEO (relay frame to children). Same live-frame semantics as
  /// [handleGroupCallAudioV3].
  void handleGroupCallVideoV3(HarvestEvent event) {
    final session = _currentGroupCall;
    if (session == null || session.state != GroupCallState.inCall) return;

    session.videoFramesReceived++;

    if (session.relay != null) {
      session.relay!.forwardFrame(Uint8List.fromList(event.payload),
          proto.MessageTypeV3.MTV3_CALL_GROUP_VIDEO);
    }
  }

  /// V3 outer-reply busy auto-reject. The peer device-id is delivered
  /// directly on the inbound `NetworkPacketV3`, so no routing
  /// re-resolution is needed.
  void _sendRejectV3(HarvestEvent event, String reason) {
    try {
      final invite = proto.CallInvite.fromBuffer(event.payload);
      final senderUserId = Uint8List.fromList(event.senderUserId);
      final senderHex = bytesToHex(senderUserId);
      final contact = contacts[senderHex];
      if (contact == null ||
          contact.x25519Pk == null ||
          contact.mlKemPk == null) {
        _log.debug('busy-reject V3: missing KEM pubkeys for '
            '${senderHex.substring(0, 8)} — drop');
        return;
      }

      final reject = proto.CallReject()
        ..callId = invite.callId
        ..reason = reason;
      // §17.2: a rejection is an ordinary 1:1 cell under the
      // pair tag, to the USER. The device-addressed branch that stood next to it here until
      // the CUT was dead on the V4.1 path (§14.2:
      // `HarvestEvent.senderDeviceId` is always `null`) and fell with
      // `sendSignalReplyToDevice`.
      //
      // A-1 (S352): `transport.sendSignal` passes straight through to `sendViaUser`,
      // which can throw; the surrounding `try` is synchronous and never catches
      // the throw of an `async` function.
      transport
          .sendSignal(
            recipientUserId: senderUserId,
            type: proto.MessageTypeV3.MTV3_CALL_REJECT,
            payload: reject.writeToBuffer(),
          )
          .catchError((Object e, StackTrace st) {
        _log.error('Group busy rejection threw (detached): $e\n$st');
        return false;
      });
    } catch (e) {
      _log.debug('busy-reject V3 build failed: $e');
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  /// §13.1.2 exemption #4: register `deviceId` as `participantHex`'s
  /// live-media PoW-exempt device for this session. Idempotent — if the
  /// participant re-announces the same device id (e.g. reciprocated
  /// sender-key), this just overwrites the map entry with the same value.
  /// If the participant's device id *changed* (multi-device switch during
  /// a call), unregisters the stale id first so the allowlist doesn't leak
  /// an entry for a device no longer part of the call.
  ///
  /// **[deviceId] may be `null`** (B-32, S349). The V4.1 receive path
  /// carries no device identifier — §14.2: "The delivery path has **no
  /// device level**." Then there is nothing to register, and nothing is
  /// invented either: a substitute value (say the UserID) would land in
  /// `registeredLiveMediaDeviceIds` under an identifier that denotes no device
  /// and that the teardown consequently cannot sensibly
  /// revoke either. The V4.1 admission runs via AEAD under
  /// the `call_key` together with the session cookie (§17.4) anyway, not via a list.
  ///
  /// An already registered older value is NOT revoked in this case:
  /// "I do not know" is no statement that the
  /// device learned earlier no longer takes part.
  void _registerLiveMediaDevice(
      GroupCallSession session, String participantHex, Uint8List? deviceId) {
    if (deviceId == null) {
      _log.debug('Live media admission for ${participantHex.substring(0, 8)} '
          'skipped: the receive path carries no device identifier (V4.1, '
          '§14.2) — §17.4 carries the admission via the call_key');
      return;
    }
    // The V3 PoW exemption list fell with the CUT; §17.4 replaces it
    // with AEAD under the `call_key` plus session cookie. The identifier
    // is still recorded because `_deviceLabel` and the teardown paths
    // read it for their log lines — nothing is registered anywhere anymore.
    session.registeredLiveMediaDeviceIds[participantHex] = deviceId;
  }

  /// Clear the Plane D session to `participantHex` (GROUP_LEAVE /
  /// CALL_HANGUP / drop below two participants via [_participantLeft]).
  ///
  /// Until the CUT this revoked the V3 PoW exemption list. What is to be revoked
  /// now is the SESSION (§17.4).
  void _unregisterLiveMediaDevice(
      GroupCallSession session, String participantHex) {
    session.registeredLiveMediaDeviceIds.remove(participantHex);
    transport.forgetParticipant(participantHex);
  }

  /// Clear all Plane D sessions of this call — the local teardown
  /// ([_cleanup]) must not leave an open session behind for a call
  /// that no longer exists.
  void _unregisterAllLiveMediaDevices(GroupCallSession session) {
    for (final participantHex
        in session.registeredLiveMediaDeviceIds.keys.toList()) {
      transport.forgetParticipant(participantHex);
    }
    session.registeredLiveMediaDeviceIds.clear();
  }

  /// Device identifier for log lines. `—` means: the receive path carries
  /// none (V4.1, §14.2) — information, not a gap.
  String _deviceLabel(Uint8List? deviceId) =>
      deviceId == null ? '—' : bytesToHex(deviceId).substring(0, 8);

  /// A group media frame to a participant, via Plane D
  /// (§17.1).
  ///
  /// [payload] is a frame according to `group_media_frame.dart`
  /// (`index(1) ‖ koerper`), whose body is already encrypted under the `send_key`
  /// of the sender
  /// (§17.5: "for groups, **a separate `send_key` per
  /// sender** is needed, because a shared group key cannot provide sender
  /// authenticity"). The D frame seals over it a second time under
  /// the `call_key` — that is NOT double effort without purpose here,
  /// but the two different statements from §17.5: the `send_key`
  /// says WHO speaks, the `call_key` says that the frame belongs to this
  /// call.
  ///
  /// **AUDIO FITS INTO ITS CLASS — since 05.09.2026, and the numbers
  /// before were wrong in two places.** `DFrameClass.voice` carries
  /// **117 B** (previously 85 B).
  ///
  /// | Form | Overhead | at 70 B Opus | at 95 B (maximum) |
  /// |---|---|---|---|
  /// | `GroupCallAudio` (until S368) | 88 B | **158/159 B** | 183 B |
  /// | this format (index 1 B, S369) | 33 B | **103 B** | **128 B** |
  /// | ciphertext ALONE, without any header | 16 B | 86 B | 111 B |
  /// | capacity, old (128 B class) | — | **85 B** | 85 B |
  /// | capacity, new (160 B class) | — | **117 B** | 117 B |
  ///
  /// **Why the class had to grow and omission was not enough:**
  /// the ciphertext alone — Opus 70 B plus the 16 B AES-GCM tag
  /// that §17.5 requires ("a separate `send_key` per sender") — measured 86 B
  /// and was thus one byte above the old class **before a single
  /// header field existed**. There was no field left to remove.
  ///
  /// Measured with the real libopus, back then still at a TARGET bitrate without
  /// cap (28 kbit/s, DTX+FEC on, VBR): p50 = 70 B, p90 = 78 B,
  /// p99 = 85 B, max = 91-95 B. **The number 70 was then the MEAN
  /// and not the upper bound** — with the old class 100 % of
  /// group frames were dropped, with the 160 B class 1.2 % (those above 84 B Opus).
  ///
  /// Since 06.09.2026, 70 B is both at once: mean and
  /// upper bound, because `OPUS_SET_VBR = 0` fixes every frame at exactly this
  /// size. Since then the table above only reads in
  /// the column "at 70 B Opus".
  ///
  /// A frame that is too large still comes back as [MediaSendFailure.tooLarge]
  /// and is discarded instead of promoted into the 1200 B class;
  /// a promotion would be a size difference on the wire
  /// (§17.1). **The class has grown AND the codec has been capped since
  /// 06.09.2026** — until then "the codec is not
  /// throttled" applied here, and exactly for that reason a remainder stayed. The class applies to
  /// 1:1 and group alike, so that an
  /// observer outside the call cannot tell the two apart by the
  /// frame size. **VIDEO was never affected**: it
  /// rides on `DFrameClass.stream` with 1157 B payload.
  ///
  /// The addition that used to be here, "the group topology is open
  /// anyway (§17.5, K31-3)", has been dropped — §17.7 closed K31-3 on 05.09.2026.
  void _sendGroupLiveMediaFrame(
    String participantHex,
    proto.MessageTypeV3 type,
    Uint8List payload,
  ) {
    final kind = type == proto.MessageTypeV3.MTV3_CALL_GROUP_VIDEO
        ? DFrameKind.video
        : DFrameKind.voice;
    final failure = transport.sendMedia(
      peerHex: participantHex,
      kind: kind,
      payload: payload,
    );
    if (failure != null) {
      _log.debug('Plane D: ${type.name} to '
          '${participantHex.substring(0, 8)} dropped (${failure.name})');
      return;
    }
    // ONLY ON SUCCESS. A frame that the transport rejected with `noPath`
    // was never on the line and proves nothing about it. What is counted
    // is the wire length of the size class (§17.1), not the payload
    // — otherwise the measured upload collapses in every speaking pause.
    uploadProbe.recordSent(kind.frameClass.wireSize);
  }

  /// Send a live-media (or per-call ephemeral) frame to a participant
  /// identified by their userIdHex. Resolves the participant's device
  /// via the routing table (cached per-session in
  /// [_participantRouteCache] — Architecture §10.4.1) and dispatches via
  /// `CallTransport.sendSecuredToParticipant`. The flag combination
  /// (Ed25519-only outer, no PoW — architecture §10.3) sits in the
  /// adapter since AP-2b, bound to the operation instead of the call site.
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
    final failure = transport.sendSecuredToParticipant(
      participantHex: participantHex,
      peerX25519Pk: contact.x25519Pk!,
      peerMlKemPk: contact.mlKemPk!,
      type: type,
      payload: payload,
      expectsReply: false,
    );
    if (failure != null) {
      _log.debug('live-media: no path to '
          '${participantHex.substring(0, 8)}');
    }
  }

  // ── S378, merge: WHICH NUMBER APPLIES HERE ────────────────────
  //
  // Two versions met. The older one (S368, 05.09.2026)
  // built the structure below: two caps, and it is measured which one
  // applies. The younger one (S376/A-3, 08.09.2026) was owner decision
  // **V-8 = A** and set ONE fixed number, 25, with this rationale:
  //
  //   "§17.7 gives caps per topology, not globally: 6 for full mesh, 30
  //   for the crystal. […] The control plane is a full mesh up to 25 and
  //   a star above that (§17.1.1) — the star does not exist in this tree.
  //   25 is the smaller of the two and thus the largest number
  //   that presupposes NO unbuilt plane."
  //
  // Both still apply, and both together yield exactly the following:
  // the 25 is the TREE cap (there the control plane limit takes effect,
  // hence 25 instead of 30), the 6 the FULL MESH cap from §17.7. V-8
  // could not have meant the full mesh case: in that tree the
  // carrier was missing (`treeMaintenanceUnavailableReason` had zero
  // hits there), so there was no second topology to distinguish at all.
  //
  // The complete derivation of the 25 is in the proposal on V-8 = A.

  // ── Participant limit: bound to the topology, not guessed ────
  //
  // Until S368 a single number stood here:
  //
  //     /// Maximum number of participants in a group call
  //     /// (Phase 3c Full Mesh MVP).
  //     static const int maxParticipants = 8;
  //
  // The 8 came from the meshing era and was bound to nothing. It
  // is neither the limit of meshing nor that of the tree — it lies
  // between the two, so it is too large for the one and an order of
  // magnitude too small for the other.
  //
  // Both numbers below are computed, not chosen. Basis:
  // `docs/v4-redesign/S368-VORLAGE-gruppenanruf-baum-bandbreite.md` §3.1,
  // Opus target rate 28 kbit/s per voice stream (§17.5), K = 4 simultaneously
  // forwarded speakers.

  /// Limit for MESHING — everyone sends to everyone.
  ///
  /// The upload grows linearly with the group: `(N-1) x 28 kbit/s`. At 6
  /// that is 140 kbit/s, at 8 already 196, at 20 then 532. 6 is the
  /// number at which even a weak mobile upload still carries the audio
  /// (S368 proposal §3.4: weak mobile ~3 Mbit/s gross, but
  /// meshing additionally pays N-1 packet streams, not just N-1 times the
  /// rate).
  ///
  /// **Smaller than the previous 8, and that is intentional.** A number that
  /// only stood higher because it was never recomputed is no
  /// promise — it is an estimate that looks like a promise.
  static const int maxParticipantsMesh = 6;

  /// Limit in the FORWARDING TREE — everyone sends to at most
  /// [OverlayTree.maxFanOut] children.
  ///
  /// The load per node is **independent** of N: `3 x K x 28` = 336
  /// kbit/s, whether the group has 8 or 50 participants. What grows with N is
  /// solely the DEPTH (logarithmically) and thus the latency — at fan-out 3,
  /// 30 participants are three levels, i.e. 45-75 ms additional latency
  /// (S368 proposal §3.3). At 50 it would be four levels and 60-100 ms; 30
  /// is the limit at which the latency is not yet noticeable for speech.
  ///
  /// **This number is not sharp today** — see [effectiveTopology].
  static const int maxParticipantsTree = 25;

  /// Which topology REALLY carries the media of a group call today.
  ///
  /// **What is asked is the statement, not a proxy.** "The file
  /// `overlay_tree.dart` is imported" and "`tree.build` is called"
  /// are both true and both irrelevant: the tree only carries once its
  /// PLAN arrives at the participants. Exactly that is asked by
  /// [CallTransport.treeMaintenanceUnavailableReason].
  ///
  /// ── WHAT STOOD HERE UNTIL S368, AND WHY IT IS GONE ─────────────────
  ///
  /// "`_broadcastTreeUpdate` sends `CALL_TREE_UPDATE` via
  /// [_sendLiveMediaToParticipant] -> `sendSecuredToParticipant`, and
  /// `CallTransportV41` returns `noCarrier` there without exception (§17.1
  /// knows three frame kinds, tree maintenance is none of them). […] As long as that
  /// is so, `maxParticipantsTree` would be a promise that the program
  /// does not keep."
  ///
  /// That was true on the morning of 05.09.2026 and has no longer been true since the
  /// afternoon: the tree assignment runs via
  /// `transport.sendControl` as a control frame (§17.1.1), the receiver
  /// applies it in `_applyTreeAssignment` and calls [_setupRelay] there.
  ///
  /// ── THE GETTER ITSELF IS UNCHANGED, AND THAT IS THE POINT ──────
  ///
  /// It still asks the STATEMENT and not a proxy: "the
  /// file `overlay_tree.dart` is imported" and "`tree.build` is
  /// called" are both true and both irrelevant. The tree only carries
  /// once its plan arrives at the participants — and exactly that is asked by
  /// [CallTransport.treeMaintenanceUnavailableReason]. Because the answer
  /// has become a different one, the limit is also a different one; no number
  /// had to be touched for that.
  ///
  /// **What the getter does NOT answer**: whether a Plane D session exists to a
  /// SPECIFIC participant. That is a statement per
  /// counterpart (`PunchOutcome`), not one about the node. §17.7 binds
  /// the crystal limit explicitly to "a media relay path
  /// actually carries" — where a single path does not carry, the
  /// tree loses this branch, not its limit.
  GroupCallTopology get effectiveTopology =>
      transport.treeMaintenanceUnavailableReason == null
          ? GroupCallTopology.tree
          : GroupCallTopology.mesh;

  /// The limit actually enforced — that of the topology from
  /// [effectiveTopology], never that of the other one.
  int get maxParticipants => switch (effectiveTopology) {
        GroupCallTopology.mesh => maxParticipantsMesh,
        GroupCallTopology.tree => maxParticipantsTree,
      };

  /// Update a participant's audio level (called from CallService when
  /// AudioMixer reports levels).
  void updateParticipantAudioLevel(String nodeIdHex, double level) {
    final session = _currentGroupCall;
    if (session == null) return;
    final participant = session.participants[nodeIdHex];
    if (participant == null) return;
    participant.audioLevel = level;
  }

  /// Update a participant's mute state (inferred from sustained silence).
  void updateParticipantMuteState(String nodeIdHex, bool isMuted) {
    final session = _currentGroupCall;
    if (session == null) return;
    final participant = session.participants[nodeIdHex];
    if (participant == null) return;
    participant.isMuted = isMuted;
  }

  bool _callIdMatches(Uint8List a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ── §10.5 In-Call Collaboration ───────────────────────────────────

  /// UI callbacks for collaboration state changes.
  void Function()? onCollaborationChanged;

  /// Fired when screen share starts, stops, or changes quality preset.
  /// `null` preset = stopped (restore camera defaults).
  void Function(ScreenSharePreset? preset)? onScreenSharePresetChanged;

  /// Initialize all collaboration managers for a call session.
  void _initCollaboration(GroupCallSession session) {
    final profileDir = _log.profileDir ?? '';

    session.whiteboard = WhiteboardManager(
      ownUserIdHex: identity.userIdHex,
      ownDisplayName: identity.displayName,
      profileDir: profileDir,
    );
    session.whiteboard!.onSendToAll = (type, payload) {
      _sendCollaborationToAll(session, type, payload);
    };

    session.callChat = CallChatManager(
      ownUserIdHex: identity.userIdHex,
      ownDisplayName: identity.displayName,
      profileDir: profileDir,
    );
    session.callChat!.onSendToAll = (type, payload) {
      _sendCollaborationToAll(session, type, payload);
    };

    session.fileManager = CallFileManager(
      ownUserIdHex: identity.userIdHex,
      ownDisplayName: identity.displayName,
      profileDir: profileDir,
    );
    session.fileManager!.onSendToAll = (type, payload) {
      _sendCollaborationToAll(session, type, payload);
    };

    session.screenShare = ScreenShareManager(
      ownUserIdHex: identity.userIdHex,
      profileDir: profileDir,
    );
    session.screenShare!.onSendToAll = (type, payload) {
      _sendCollaborationToAll(session, type, payload);
    };
    session.screenShare!.onReconfigurePipeline = (preset) {
      onScreenSharePresetChanged?.call(preset);
    };

    _log.info('Collaboration managers initialized');
  }

  /// Send collaboration data to all joined participants via live-media path.
  void _sendCollaborationToAll(
    GroupCallSession session,
    proto.MessageTypeV3 type,
    Uint8List payload,
  ) {
    for (final pId in session.joinedParticipantIds) {
      if (pId == identity.userIdHex) continue;
      _sendLiveMediaToParticipant(pId, type, payload);
    }
  }

  /// V3 receive-handler for MTV3_WHITEBOARD_STROKE.
  void handleWhiteboardStrokeV3(HarvestEvent event) {
    final session = _currentGroupCall;
    if (session == null || session.state != GroupCallState.inCall) return;
    if (session.whiteboard == null) return;

    try {
      final stroke = proto.WhiteboardStroke.fromBuffer(event.payload);
      session.whiteboard!.handleRemoteStroke(stroke);
      onCollaborationChanged?.call();
    } catch (e) {
      _log.debug('Whiteboard stroke parse error: $e');
    }
  }

  /// V3 receive-handler for MTV3_WHITEBOARD_PAGE.
  void handleWhiteboardPageV3(HarvestEvent event) {
    final session = _currentGroupCall;
    if (session == null || session.state != GroupCallState.inCall) return;
    if (session.whiteboard == null) return;

    try {
      final page = proto.WhiteboardPage.fromBuffer(event.payload);
      session.whiteboard!.handleRemotePage(page);
      onCollaborationChanged?.call();
    } catch (e) {
      _log.debug('Whiteboard page parse error: $e');
    }
  }

  /// V3 receive-handler for MTV3_CALL_CHAT.
  void handleCallChatV3(HarvestEvent event) {
    final session = _currentGroupCall;
    if (session == null || session.state != GroupCallState.inCall) return;
    if (session.callChat == null) return;

    try {
      final msg = proto.CallChatMessage.fromBuffer(event.payload);
      session.callChat!.handleRemoteMessage(msg);
      onCollaborationChanged?.call();
    } catch (e) {
      _log.debug('Call chat parse error: $e');
    }
  }

  /// V3 receive-handler for MTV3_FILE_EXCHANGE.
  void handleFileExchangeV3(HarvestEvent event) {
    final session = _currentGroupCall;
    if (session == null || session.state != GroupCallState.inCall) return;
    if (session.fileManager == null) return;

    try {
      final share = proto.CallFileShare.fromBuffer(event.payload);
      session.fileManager!.handleRemoteFileShare(share);
      onCollaborationChanged?.call();
    } catch (e) {
      _log.debug('File exchange parse error: $e');
    }
  }

  /// V3 receive-handler for MTV3_CLIPBOARD_EXCHANGE.
  void handleClipboardExchangeV3(HarvestEvent event) {
    final session = _currentGroupCall;
    if (session == null || session.state != GroupCallState.inCall) return;
    if (session.fileManager == null) return;

    try {
      final exchange = proto.CallClipboardExchange.fromBuffer(event.payload);
      session.fileManager!.handleRemoteClipboard(exchange);
      onCollaborationChanged?.call();
    } catch (e) {
      _log.debug('Clipboard exchange parse error: $e');
    }
  }

  /// V3 receive-handler for MTV3_SCREEN_SHARE_FRAME.
  void handleScreenShareV3(HarvestEvent event) {
    final session = _currentGroupCall;
    if (session == null || session.state != GroupCallState.inCall) return;
    if (session.screenShare == null) return;

    try {
      final control = proto.ScreenShareControl.fromBuffer(event.payload);
      session.screenShare!.handleRemoteControl(control);
      onCollaborationChanged?.call();
    } catch (e) {
      _log.debug('Screen share control parse error: $e');
    }
  }
}
