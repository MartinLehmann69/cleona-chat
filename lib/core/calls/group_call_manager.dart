import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/calls/group_call_session.dart';
import 'package:cleona/core/calls/peer_hearing.dart';
import 'package:cleona/core/calls/collaboration/whiteboard_manager.dart';
import 'package:cleona/core/calls/collaboration/call_chat_manager.dart';
import 'package:cleona/core/calls/collaboration/call_file_manager.dart';
import 'package:cleona/core/calls/collaboration/screen_share_manager.dart';
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
import 'package:cleona/core/calls/call_consent.dart';
import 'package:cleona/core/calls/call_manager.dart' show CallManager;
import 'package:cleona/core/calls/call_control_frame.dart';
import 'package:cleona/core/calls/group_media_frame.dart';
import 'package:cleona/core/calls/group_media_admission.dart';
import 'package:cleona/core/calls/group_call_broker.dart';
import 'package:cleona/core/calls/group_call_crystal.dart';
import 'package:cleona/core/calls/group_call_ringing.dart';
import 'package:cleona/core/calls/punch_window.dart' show PunchOutcome;
import 'package:cleona/core/calls/call_transport.dart';
import 'package:cleona/core/link_io/d_frame.dart';
import 'package:cleona/core/identity/identity_context.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/core/service/harvest_event.dart';
import 'package:cleona/generated/proto/app_payloads.pb.dart' as proto;
import 'package:cleona/generated/proto/transport.pb.dart' as proto;

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

  /// V3 setup-path send callback — wired by [CleonaService] to its
  /// `sendToUser` orchestrator. Used for CALL_INVITE (group), CALL_ANSWER,
  /// CALL_REJECT, CALL_GROUP_LEAVE, CALL_GROUP_KEY_ROTATE.
  ///
  /// [groupId] names the group of the call in every signal (§17.2, §16.2.2):
  /// to a fellow member who is not a contact the signal goes over the group
  /// pair, and a group pair carries only what names a group both belong to
  /// (§15.7). Always set through [_signal].
  Future<bool> Function(
    Uint8List recipientUserId,
    proto.MessageType type,
    Uint8List payload, {
    Uint8List? groupId,
  })? sendViaUser;

  /// Observes the detached send [sent]: a throw is logged as [what], never
  /// left to the zone of `service_daemon.dart` (A-1, S351: everything outside
  /// its survival list is `exit(99)`).
  ///
  /// `then(…, onError:)` and not `catchError(… return false)`: the latter
  /// needs its handler to return the future's RUNTIME type, and a sender
  /// whose future is a `Future<Never>` (a closure that only throws) turned
  /// the caught error into a type error in the zone — measured with
  /// `smoke_group_call_multi_device` §9 once the busy rejection went through
  /// [sendViaUser] (S407-GA-P3).
  void _detached(Future<bool>? sent, String what) {
    sent?.then((_) {}, onError: (Object e, StackTrace st) {
      _log.error('$what threw (detached): $e\n$st');
    });
  }

  /// Hands the signal [payload] of [session] to [recipientHex] — naming the
  /// group of the call ([sendViaUser]).
  Future<bool>? _signal(GroupCallSession session, String recipientHex,
          proto.MessageType type, Uint8List payload) =>
      sendViaUser?.call(hexToBytes(recipientHex), type, payload,
          groupId: hexToBytes(session.groupIdHex));

  /// `major * 1000 + minor` of this build, carried in the group CALL_INVITE
  /// — the same field and the same E5 gate as the 1:1 INVITE
  /// ([CallManager.callerAppMajorMinor]). The receiver checks it BEFORE it
  /// looks at `isGroupCall` (`CallService.handleCallInvite`); without it
  /// the field is the proto3 default 0 and every group invitation was
  /// rejected as "incompatible caller version 0" (measured S398-W2).
  int _callerAppMajorMinor = 0;
  set callerAppMajorMinor(int v) => _callerAppMajorMinor = v;

  // UI callbacks
  void Function(GroupCallInfo info)? onIncomingGroupCall;
  void Function(GroupCallInfo info)? onGroupCallStarted;
  void Function(GroupCallInfo info)? onGroupCallEnded;
  void Function(String nodeIdHex, ParticipantState state)? onParticipantChanged;

  /// §17.2 "Missed call" in a group call (S408, S407-GAMUTE open point 1,
  /// owner variant B): "Whenever a call ends without having been answered —
  /// no `RING_ACK` within 10 s, the caller hanging up before an answer, or
  /// 60 s of ringing without an `ANSWER` — the caller sends the missed-call
  /// message." In a group call the call is the invitation of one member:
  /// the initiator starts the message once per member whose invitation ended
  /// unanswered — [memberHex], the group, the `callId`. `CleonaService`
  /// sends it as a group message to that member.
  void Function(String memberHex, String groupIdHex, Uint8List callId)?
      onMissedCall;

  /// How a fellow participant is heard may have changed (§17.7: media
  /// pair, broker, or one of the three notices) — the tile reads it from
  /// [GroupCallParticipantInfo.reach].
  void Function()? onReachChanged;

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
  /// `handleGroupCallAudioV3` (removed in S407) — i.e. via the DELIVERY
  /// LAYER.
  /// Exactly this path no longer exists in V4.1 (§17.1: "media does **not**
  /// run in delivery cells", and `call_service.handleCallVideo` says it
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

  /// Whether this device may hold a media pair with [peerHex] (§17.7): an
  /// accepted contact whose switch "allow calls" is on (§17 principle,
  /// RL-7, D-69; [callsAllowedWith]).
  ///
  /// Only such a pair gets Plane D material from this device — address
  /// candidates, session cookie, ephemeral key, ML-KEM ciphertext (§17.3:
  /// "only between contacts with call consent") — and only to such a pair
  /// does this device run a punch window. Material from any other
  /// participant is dropped on receipt. Whether the pair then CARRIES is
  /// the punch window's answer: a Plane D session exists only after it
  /// carried, and media and control frames travel only on a session.
  ///
  /// Until S407-GA-P3 the group path asked nothing of the kind: every
  /// participant got the material and a window (finding B-1,
  /// `S407-GRUPPENANRUF.md`); only the group-pair gate, built for another
  /// purpose, kept the signals from non-contacts.
  bool _callPairAdmissible(String peerHex) =>
      callsAllowedWith(contacts, peerHex);

  /// Whether [event] — a signal of the running [session] — names a group in
  /// its frame other than the call's. A signal over a group pair always names
  /// the group the gate admitted it for (§15.7, §16.2.2); one for another
  /// group is not this call's. A signal without a group (a contact of an
  /// older version) is judged by its `callId` alone, as before.
  bool _namesOtherGroup(GroupCallSession session, HarvestEvent event) {
    final g = event.groupId;
    if (g == null || bytesToHex(g) == session.groupIdHex) return false;
    _log.warn('${event.type.name} from '
        '${bytesToHex(Uint8List.fromList(event.senderUserId)).substring(0, 8)} '
        'names another group than the call — dropped (§16.2.2)');
    return true;
  }

  /// Gives [session] its broker bookkeeping and the forwarding of the pairs
  /// it carries (§17.7, `group_call_broker.dart`).
  void _attachBroker(GroupCallSession session) {
    final broker = GroupCallBroker(
      ownHex: identity.userIdHex,
      roster: () => session.rosterSorted,
      isJoined: (hex) =>
          session.participants[hex]?.state == ParticipantState.joined,
      send: (to, record) =>
          transport.sendControl(participantHex: to, record: record),
      request: (to, record, answeredBy, onFailed) {
        final error = transport.requestControl(
          participantHex: to,
          record: record,
          answeredBy: answeredBy,
          onFailed: onFailed,
        );
        // Not even queued (no session any more): failed at once — after
        // the caller's own bookkeeping, not inside it.
        if (error != null) scheduleMicrotask(onFailed);
      },
      capacity: () => BrokerCapacity.fromProbe(uploadProbe.observe(),
          sendsVideo: session.videoFramesSent > 0 && !session.videoSwitchedOff),
      ownRank: () => rankByte(uploadProbe.form, uploadProbe.power),
      rttOf: (hex) => session.rtt?.rttTo(hex),
      wantVideo: () => !session.videoSwitchedOff,
      onBinding: (peer, brokerHex) => brokerHex == null
          ? session.admission.unbindBroker(peer)
          : session.admission.bindBroker(peer, brokerHex),
      onChanged: () => onReachChanged?.call(),
      log: (line) => _log.info('Broker (§17.7): $line'),
    );
    session.broker = broker;
    session.pairRelay = PairRelay(targetsFor: broker.forwardTargets)
      ..onSendUnicast = (target, frame, type) =>
          _sendGroupLiveMediaFrame(target, type, frame);
  }

  /// [peerHex] is known to have joined: without a contact with call
  /// consent on THIS side there is no media pair with it, decided now
  /// (§17.7) — an edge for the broker.
  void _joinedEdge(GroupCallSession session, String peerHex) {
    if (peerHex == identity.userIdHex) return;
    if (!_callPairAdmissible(peerHex)) {
      session.broker?.setPairState(peerHex, MediaPairState.none);
    }
    _crystalEdge(session);
  }

  /// [peerHex] gives this device no Plane D material although this side
  /// would hold a media pair with it: the OTHER side has no contact with
  /// call consent, so there is no media pair either (§17.7).
  void _refusedByPeer(GroupCallSession session, String peerHex, String what) {
    if (!_callPairAdmissible(peerHex)) return;
    _log.info('${peerHex.substring(0, 8)} sends no Plane D material in its '
        '$what — no media pair with it (§17, §17.7)');
    session.broker?.setPairState(peerHex, MediaPairState.none);
    _crystalEdge(session);
  }

  /// [peerHex] sent Plane D material in [signal] although this device holds
  /// no media pair with it: nothing of it is kept, no window runs.
  void _dropPlaneDMaterial(String peerHex, String signal) {
    _log.info('Plane D material in the $signal of '
        '${peerHex.substring(0, 8)} dropped — no contact with calls '
        'allowed (§17, §17.3)');
  }

  // ── Initiator Flow ──────────────────────────────────────────────────

  /// Start a group call. Generates call_key, sends CALL_INVITE to all members
  /// — or, with [invitees], only to those members.
  ///
  /// [invitees] is the start from an event card (§18.1.7: "a click starts
  /// a group call with everyone who accepted"). The participant LIST stays
  /// the whole group even then: the callee builds it from the group
  /// (`handleGroupCallInvite`), and the sender slot of every media frame
  /// and the checksum of every tree assignment index the sorted list — a
  /// shorter list on one side would shift every index. Members outside
  /// [invitees] are simply not rung.
  Future<GroupCallSession?> startGroupCall(String groupIdHex,
      {Set<String>? invitees}) async {
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
    _attachBroker(session);
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
    //
    // Cookie and candidates go only to a member this device may hold a
    // media pair with (§17.3, [_callPairAdmissible]); every other member
    // rings with an INVITE that carries neither (§16.2.2).
    //
    // §17.2: from the moment the user starts the call each invited member
    // is being REACHED — shown "invited", not "ringing", until its RING_ACK
    // arrives ([handleGroupCallRingAck]); 10 s without one end its
    // invitation ([_invitationsEnded]).
    final rung = <String>{
      for (final member in group.members.values)
        if (member.nodeIdHex != identity.userIdHex &&
            (invitees == null || invitees.contains(member.nodeIdHex)))
          member.nodeIdHex,
    };
    session.ringing = GroupCallRinging(
      onNotReached: (gone) =>
          _invitationsEnded(session, gone, 'no RING_ACK within 10 s'),
      onNotAnswered: (member) =>
          _invitationsEnded(session, {member}, 'no ANSWER within 60 s'),
    )..startReaching(rung);
    Uint8List? ownCandidates;
    var invited = 0;
    for (final member in group.members.values) {
      if (!rung.contains(member.nodeIdHex)) continue;
      invited++;

      final invite = proto.CallInvite()
        ..callId = callId
        ..isGroupCall = true
        ..groupId = hexToBytes(groupIdHex)
        ..callerAppMajorMinor = _callerAppMajorMinor;
      if (_callPairAdmissible(member.nodeIdHex)) {
        final cookie = transport.newDCookie();
        session.localDCookies[member.nodeIdHex] = cookie;
        invite.callerDCookie = cookie;
        ownCandidates ??= await transport.localCandidatesPacked();
        if (ownCandidates.isNotEmpty) {
          invite.callerCandidates = ownCandidates;
        }
      }

      await _signal(session, member.nodeIdHex,
          proto.MessageType.MT_CALL_INVITE, invite.writeToBuffer());
    }

    _log.info('Group call started: ${session.callIdHex.substring(0, 8)} in group "${group.name}" with $invited invites'
        '${invitees == null ? "" : " (those who accepted, §18.1.7)"}');
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
    session.ringing?.stopRinging();

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
    // in the group path then without any time limit (since S407-GAMUTE a
    // ringing device stops by itself after 60 s, `GroupCallRinging`).
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
    //
    // Only to an initiator this device may hold a media pair with (§17.3);
    // to any other the ANSWER carries the binding marker (field 2, §17.2,
    // no address) and nothing of Plane D, and no window runs.
    final mediaPair = _callPairAdmissible(session.initiatorHex);
    if (mediaPair) {
      final ownCookie = transport.newDCookie();
      session.localDCookies[session.initiatorHex] = ownCookie;
      answer.calleeDCookie = ownCookie;
      final ownCandidates = await transport.localCandidatesPacked();
      if (ownCandidates.isNotEmpty) {
        answer.calleeCandidates = ownCandidates;
      }
    }

    await _signal(session, session.initiatorHex,
        proto.MessageType.MT_CALL_ANSWER, answer.writeToBuffer());

    // §17.3: the window runs FROM NOW, on both sides at once — the
    // initiator starts its own as soon as it has harvested this ANSWER.
    // Not awaited: it runs up to 30 s, and the call should already look
    // set up during that time. The same construction as in the 1:1 path
    // (`call_manager.dart`, `unawaited(_openMediaPath(call))`).
    if (mediaPair) {
      unawaited(_openParticipantMediaPath(session, session.initiatorHex));
    }

    _setupRttAndHealth(session);
    _initCollaboration(session); // §10.5 in-call collaboration
    // §10.2.1: announce our send_key to everyone already joined (the
    // initiator, plus any earlier joiners). They reciprocate via the handler.
    await _announceSendKeyToAllJoined(session);
    onGroupCallStarted?.call(session.toGroupCallInfo());
    _log.info('Group call accepted: ${session.callIdHex.substring(0, 8)}');
  }

  /// Reject an incoming group call.
  Future<void> rejectGroupCall(
      {String reason = CallManager.rejectReasonDeclined}) async {
    final session = _currentGroupCall;
    if (session == null || session.state != GroupCallState.ringing) return;

    session.state = GroupCallState.ended;
    session.ringing?.stopRinging();

    final reject = proto.CallReject()
      ..callId = session.callId
      ..reason = reason;
    await _signal(session, session.initiatorHex,
        proto.MessageType.MT_CALL_REJECT, reject.writeToBuffer());

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
    // An edge for the brokers (§17.7): its media pairs end, the pairs it
    // carried need another broker, and pairs with it end.
    session.broker?.participantLeft(nodeIdHex);

    // An edge of the crystal (§17.7): whoever hung below it or above it
    // finds its place again.
    _crystalEdge(session);

    // Owner transfer: if the departing participant was the tree owner,
    // elect a new owner deterministically (lowest lexicographic joined id).
    if (nodeIdHex == session.ownerHex) {
      final joined = session.joinedParticipantIds..sort();
      if (joined.isNotEmpty) {
        final newOwner = joined.first;
        _log.info('Owner transfer: ${nodeIdHex.substring(0, 8)} -> '
            '${newOwner.substring(0, 8)}');
        // Only the owner of a v4.2.3 tree (0x01) matters any more; the
        // crystal has no owner (§17.7: "not the one that started the call").
        session.ownerHex = newOwner;
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
          proto.MessageType.MT_CALL_GROUP_AUDIO);
    } else {
      // Fallback: direct send to the joined participants this device may
      // hold a media pair with (§17.7) — to any other there is no Plane D
      // session to carry it.
      for (final pId in session.joinedParticipantIds) {
        if (pId == identity.userIdHex || !_callPairAdmissible(pId)) continue;
        _sendGroupLiveMediaFrame(
          pId,
          proto.MessageType.MT_CALL_GROUP_AUDIO,
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
          proto.MessageType.MT_CALL_GROUP_VIDEO);
    } else {
      for (final pId in session.joinedParticipantIds) {
        if (pId == identity.userIdHex || !_callPairAdmissible(pId)) continue;
        _sendGroupLiveMediaFrame(
          pId,
          proto.MessageType.MT_CALL_GROUP_VIDEO,
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
      await _signal(
          session, pId, proto.MessageType.MT_CALL_GROUP_LEAVE, payload);
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
      await _signal(
          session, pId, proto.MessageType.MT_CALL_REJOIN, payload);
    }

    // Re-announce our send key (no global rotation -- authorized set unchanged)
    session.announcedSendKeyTo.clear();
    await _announceSendKeyToAllJoined(session);

    // Restart RTT and health monitoring
    _setupRttAndHealth(session);

    _log.info('Rejoined group call: ${session.callIdHex.substring(0, 8)}');
  }

  void _endCall(GroupCallSession session) {
    // §17.2 "the caller hanging up before an answer": every invitation still
    // being reached or ringing ends with the call — one HANGUP each (an
    // ANSWER to an initiator that is gone joins nothing). The session is
    // kept for a late RING_ACK ([handleGroupCallRingAck]).
    final ringing = session.ringing;
    if (session.direction == CallDirection.outgoing && ringing != null) {
      final open = ringing.endAll();
      _hangUp(session, open, 'the call ended before an answer');
      _missedCallFor(session, open);
      _lastEndedOutgoing = session;
      _lastEndedAt = DateTime.now();
    }
    session.state = GroupCallState.ended;
    onGroupCallEnded?.call(session.toGroupCallInfo());
    _cleanup();
  }

  void _cleanup() {
    _rttTimer?.cancel();
    _rttTimer = null;
    _healthTimer?.cancel();
    _healthTimer = null;
    _currentGroupCall?.relay?.clear();
    _currentGroupCall?.broker?.clear();
    _currentGroupCall?.crystal?.clear();
    _currentGroupCall?.ringing?.stopClocks();
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

  // ── The crystal (§17.7, from 7 participants on; S408 P6) ────────────
  //
  // Until S408 the tree owner (the initiator) built ONE tree over all
  // joined participants (`OverlayTree.build`, rooted at itself) and sent
  // each participant its place (`treeAssignment` 0x01, `treeSubtree` 0x06).
  // §17.7 says otherwise on three counts: the crystal is built "over media
  // pairs only", its root is "the participant highest by the ranking …,
  // not the one that started the call", and every node "takes as its
  // parent the media pair nearest the root that still has room under its
  // `f_i`". The central tree hung children on participants they hold no
  // media pair with (no session carries there, `sendMedia` → `noPath`), and
  // the owner could not even reach a participant that is no contact of it.
  // Now every participant builds its own place (`group_call_crystal.dart`).
  // The LAN clusters of the central build (`sameSubnet`) go with it: their
  // multicast was never built (`MediaRelay.onSendMulticast` stays unset).

  /// An edge of §17.7 — a join or leave, a media pair that started or
  /// ended, the line's limit: from 7 joined participants on the call is a
  /// crystal, and stays one (it "follows the role only where the role holds
  /// still"); every participant decides its own place again.
  void _crystalEdge(GroupCallSession session) {
    if (!identical(_currentGroupCall, session) ||
        session.state == GroupCallState.ended) {
      return;
    }
    final c = session.crystal;
    if (c != null) return c.reconsider();
    if (session.joinedParticipantIds.length <= maxParticipantsMesh) return;
    _startCrystal(session);
  }

  void _startCrystal(GroupCallSession session) {
    if (session.crystal != null) return;
    int fanOut() => crystalFanOut(
        BrokerCapacity.fromProbe(uploadProbe.observe(), sendsVideo: false)
            .usableBps,
        BrokerCapacity.voiceStreamBps);
    final crystal = GroupCallCrystal(
      ownHex: identity.userIdHex,
      roster: () => session.rosterSorted,
      mediaPairs: () => session.broker?.mediaPairs ?? const <String>{},
      isJoined: (hex) =>
          hex == identity.userIdHex ||
          session.participants[hex]?.state == ParticipantState.joined,
      fanOut: fanOut,
      ownRank: () =>
          crystalRank(uploadProbe.form, uploadProbe.power, fanOut()),
      request: (to, record, answeredBy, onFailed) {
        if (answeredBy == null) {
          transport.sendControl(participantHex: to, record: record);
          return;
        }
        final error = transport.requestControl(
            participantHex: to,
            record: record,
            answeredBy: answeredBy,
            onFailed: onFailed);
        if (error != null) scheduleMicrotask(onFailed);
      },
      onChanged: () => _crystalView(session),
      log: (line) => _log.info('Crystal (§17.7): $line'),
    );
    session.crystal = crystal;
    // The crystal carries from now on; no broker forwards beside it.
    session.broker?.suspend();
    _log.info('Group call ${session.callIdHex.substring(0, 8)} has '
        '${session.joinedParticipantIds.length} participants — the crystal '
        'forms over the media pairs (§17.7)');
    crystal.reconsider();
  }

  /// The own place in the crystal as the forwarding and the admission read
  /// it: the parent, the children, and per child who lies behind it
  /// (§17.5 "over its tree link towards that sender"). Everything not
  /// behind a child comes over the parent, so the view is complete.
  void _crystalView(GroupCallSession session) {
    final c = session.crystal;
    if (c == null || !identical(_currentGroupCall, session)) return;
    final me = identity.userIdHex;
    final parent = c.parent;
    final kids = c.children;
    if (parent == null && kids.isEmpty) {
      // No tree link (yet): until one exists the participant sends to its
      // media pairs directly, as in the mesh.
      session.relay = null;
      session.admission.treeViewComplete = false;
      onReachChanged?.call();
      return;
    }
    session.tree.fromNodeList([
      {'nodeIdHex': me, 'parentHex': parent, 'childrenHex': kids.keys.toList()},
      if (parent != null)
        {'nodeIdHex': parent, 'parentHex': null, 'childrenHex': <String>[me]},
      for (final k in kids.keys)
        {'nodeIdHex': k, 'parentHex': me, 'childrenHex': <String>[]},
    ], parent ?? me);
    for (final MapEntry(key: k, value: below) in kids.entries) {
      for (final m in below) {
        if (m != me) session.tree.attachBelow(m, k);
      }
    }
    session.admission.treeViewComplete = true;
    if (session.relay == null) _setupRelay(session);
    onReachChanged?.call();
  }

  void _setupRelay(GroupCallSession session) {
    session.relay = MediaRelay(
      tree: session.tree,
      ownNodeIdHex: identity.userIdHex,
    );
    session.relay!.onSendUnicast = (targetHex, frame, type) {
      _sendGroupLiveMediaFrame(targetHex, type, frame);
    };
    // No `onSendMulticast`: LAN multicast is not built (a multicast
    // datagram carries no Plane D AEAD). Unset, the
    // relay reaches the LAN members one by one over `onSendUnicast`.
    // Until S407 a callback stood here that sent to the CHILDREN again
    // instead of to the LAN members — every child got the frame twice,
    // and no LAN member got it at all.
    session.relay!.onChildCrashed = (crashedHex) {
      final participant = session.participants[crashedHex];
      if (participant != null && participant.state == ParticipantState.joined) {
        participant.state = ParticipantState.crashed;
        onParticipantChanged?.call(crashedHex, ParticipantState.crashed);
        transport.forgetParticipant(crashedHex);
        session.broker?.participantLeft(crashedHex);
        _log.info('Participant crashed: ${crashedHex.substring(0, 8)}');
        // An edge of the crystal (§17.7); no key rotation on crash.
        _crystalEdge(session);
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


  // S408 (P6): here stood `_broadcastTreeUpdate`, `_sendTreeAssignment` and
  // `_sendTreeSubtree` — the central tree owner sending each participant its
  // place (0x01) and its subtree (0x06). No build sends them any more; the
  // crystal forms over `treeOffer`/`treeJoin`/`treeAccept`. A v4.2.3 owner
  // may still send 0x01/0x06; they are taken only while this device runs no
  // crystal ([_applyTreeAssignment]).

  /// Accepts a control record from a participant (§17.1.1).
  ///
  /// Wired by `CallService` to `CallTransport.onControlRecord`.
  void handleControlRecord(String peerHex, ControlRecord record) {
    final session = _currentGroupCall;
    if (session == null) return;
    switch (record.type) {
      case ControlRecordType.treeAssignment:
        if (session.crystal == null) {
          _applyTreeAssignment(session, peerHex, record);
        }
      case ControlRecordType.treeSubtree:
        if (session.crystal == null) {
          _applyTreeSubtree(session, peerHex, record);
        }
      case ControlRecordType.treeOffer:
      case ControlRecordType.treeJoin:
      case ControlRecordType.treeAccept:
        // The crystal (§17.7) — only from a joined participant. A crystal
        // record proves the call left the mesh: this device joins the
        // crystal even if it has not yet learned of the seventh join.
        if (session.participants[peerHex]?.state != ParticipantState.joined) {
          return;
        }
        if (session.crystal == null) _startCrystal(session);
        session.crystal?.handle(peerHex, record);
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
      case ControlRecordType.relayAsk:
      case ControlRecordType.relayHave:
      case ControlRecordType.relayBind:
      case ControlRecordType.relayRefuse:
      case ControlRecordType.relayBound:
      case ControlRecordType.relayDrop:
        // The broker of the mesh (§17.7) — only from a participant.
        if (session.participants.containsKey(peerHex)) {
          session.broker?.handle(peerHex, record);
        }
      case ControlRecordType.lossReport:
        // The transport's (`loss_report.dart`); it does not pass it up.
        return;
      case ControlRecordType.lifeSign:
        // The peer sends the life sign, so the loss rule holds toward it
        // from now on (§17.4, D-74); a v4.2.3 peer never sends one. Only a
        // joined participant: the record rides a session of this call.
        if (session.participants[peerHex]?.state == ParticipantState.joined) {
          transport.watchPairLoss(peerHex);
        }
    }
  }

  /// The line has shown its limit (§17.1.1 loss reports, §17.7 "a broker's
  /// limit" — an edge): the broker of the running call decides again.
  void lineLimitShown() {
    _currentGroupCall?.broker?.limitShown();
    // `f_i` is known now — an edge of the crystal too.
    _currentGroupCall?.crystal?.reconsider();
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
    // §17.5: a participant without children takes every sender over its
    // parent, so its view is complete as it stands. One WITH children
    // must first learn who lies behind them (`treeSubtree`).
    session.admission.treeViewComplete = kinderHex.isEmpty;
    session.broker?.suspend();

    // THIS IS ENTERING THE TREE. Without this line the participant has
    // a plan and still forwards nothing.
    _setupRelay(session);

    _log.info('Tree assignment v${z.treeVersion} applied: parent '
        '${parentHex == null ? "— (Wurzel)" : parentHex.substring(0, 8)}, '
        '${kinderHex.length} children — forwarding is in place (§17.7)');
  }

  /// Learns who lies behind each of our down-links (§17.5, the record
  /// [ControlRecordType.treeSubtree]).
  ///
  /// Same gates as the assignment: only from the tree owner, only for
  /// the participant list we hold, and only for the tree version we
  /// applied — a subtree of another tree would bind senders to the wrong
  /// links.
  void _applyTreeSubtree(
      GroupCallSession session, String peerHex, ControlRecord record) {
    if (peerHex != session.ownerHex) return;
    final list = session.rosterSorted;
    final s = readTreeSubtree(record, list.length);
    if (s == null || s.roster != rosterHash(list)) {
      _log.warn('Tree subtree record from ${peerHex.substring(0, 8)} '
          'discarded: not well-formed or for another participant list');
      return;
    }
    if (s.treeVersion != session.tree.version) return;
    final me = identity.userIdHex;
    final down = session.tree.downLinksOf(me);
    for (final MapEntry(key: linkIdx, value: members) in s.subtreeOfLink.entries) {
      if (linkIdx >= list.length) continue;
      final link = list[linkIdx];
      if (!down.contains(link)) continue;
      for (final m in members) {
        if (m < list.length && list[m] != me) {
          session.tree.attachBelow(list[m], link);
        }
      }
    }
    session.admission.treeViewComplete = true;
    _log.info('Tree subtree v${s.treeVersion} applied: '
        '${s.subtreeOfLink.length} down-link(s) placed — every sender has '
        'its link (§17.5)');
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
    // §17 principle: a window sends probes to the other side's addresses
    // and shows ours to it — only between contacts with call consent.
    if (!_callPairAdmissible(participantHex)) {
      _log.info('Plane D: no punch window for '
          '${participantHex.substring(0, 8)} — no contact with calls '
          'allowed (§17, §17.7)');
      return;
    }
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
      _pairDecided(session, participantHex, MediaPairState.none);
      return;
    }
    if (!out.carried) {
      _log.error('Layer D does not carry for '
          '${participantHex.substring(0, 8)}: ${out.refusal} '
          '(${out.packetsSent} probes / ${out.bytesSent} B)');
      // "contacts whose address pair does not carry" — a pair for a
      // broker (§17.7).
      _pairDecided(session, participantHex, MediaPairState.none);
      return;
    }
    _log.info('Layer D carries for ${participantHex.substring(0, 8)}: '
        '${out.address!.address}:${out.port} (${out.packetsSent} probes / '
        '${out.bytesSent} B, §17.3)');
    _pairDecided(session, participantHex, MediaPairState.carrying);
  }

  /// The punch window decided the media pair with [peerHex] — an edge for
  /// the broker, if the call it ran for is still this one.
  void _pairDecided(
      GroupCallSession session, String peerHex, MediaPairState s) {
    if (!identical(_currentGroupCall, session)) return;
    // A media pair starts: from now on it is kept alive — the life sign
    // once now, then once per second while no voice runs on it (§17.4,
    // D-74).
    if (s == MediaPairState.carrying) transport.keepPairAlive(peerHex);
    session.broker?.setPairState(peerHex, s);
    _crystalEdge(session);
  }

  /// §17.4: "10 s without a valid frame end that media pair, not the call —
  /// an occasion of §17.7." The transport fired the loss rule it armed on
  /// [peerHex]'s first life sign ([CallTransport.watchPairLoss]); wired by
  /// `CallService` to `CallTransport.onMediaPathLost` beside the 1:1 call.
  ///
  /// The session ends (nothing more goes to a peer that does not hear), the
  /// participant stays in the call, and the broker of §17.7 looks for a way
  /// for the pair — the same edge as a media pair whose window did not carry.
  void mediaPairLost(String peerHex) {
    final session = _currentGroupCall;
    if (session == null ||
        session.participants[peerHex]?.state != ParticipantState.joined) {
      return;
    }
    _log.warn('Plane D: media pair with ${peerHex.substring(0, 8)} lost — '
        '10 s without a valid frame; the pair ends, not the call (§17.4)');
    transport.forgetParticipant(peerHex);
    session.broker?.setPairState(peerHex, MediaPairState.none);
    // In the crystal an ended media pair is an ended tree link (§17.7).
    _crystalEdge(session);
    onReachChanged?.call();
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
    // (`handleGroupCallAnswer`, `handleCallRejoin`,
    // `handleGroupCallSenderKey`) — without `unawaited`, without
    // `catchError`. A throw from `sendViaUser` thus ran into the
    // zone handler of `service_daemon.dart` and ended the daemon
    // (`exit(99)`, `:514`). `unawaited()` at the call sites would NOT
    // have cured that: it only suppresses the lint warning. The catching
    // happens here, in the body, and thus for all three at once.
    try {
      _ensureOwnSendKey(session);

      final ann = proto.GroupCallSenderKey()
        ..callId = session.callId
        ..senderNodeId = identity.nodeId
        ..sendKey = session.ownSendKey!
        ..keyVersion = session.ownSendKeyVersion;
      // The send key goes to EVERY participant (§17.5: "handed to every
      // participant end to end"); the Plane D material only to one this
      // device may hold a media pair with (§17.3, §16.2.2).
      if (_callPairAdmissible(participantUserHex)) {
        _ensurePairMaterialFor(session, participantUserHex);
        ann
          ..dEphX25519Pk = session.ephX25519Pk!
          ..dCookie = session.localDCookies[participantUserHex]!;
        final ct = session.ownKemCtFor[participantUserHex];
        if (ct != null) ann.dKemCiphertext = ct;
        final candidates = await transport.localCandidatesPacked();
        if (candidates.isNotEmpty) ann.dCandidates = candidates;
      }

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

      final ok = await _signal(session, participantUserHex,
          proto.MessageType.MT_CALL_GROUP_SENDER_KEY, ann.writeToBuffer());
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
  // `ApplicationFrame` (inner payload already verified by the V3 receive
  // pipeline in `cleona_service.handleApplicationFrame`), the
  // `senderDeviceId` lifted off the inbound `NetworkPacket`, and the
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
  /// group call** — see [CallManager.handleCallInvite] for
  /// the rationale (A-4, the ringtone depends on it).
  bool handleGroupCallInvite(HarvestEvent event) {
    if (_currentGroupCall != null) {
      _sendReject(event, CallManager.rejectReasonInAnotherCall);
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
    // The frame's group is the one the group-pair gate checked (§15.7:
    // both belong to it); the INVITE must name the same — otherwise a
    // fellow member of one group could ring a call of another.
    if (event.groupId != null && bytesToHex(event.groupId!) != groupIdHex) {
      _log.warn('GROUP_CALL_INVITE from ${senderHex.substring(0, 8)} names '
          'another group than its frame — dropped (§16.2.2)');
      return false;
    }

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
    //
    // Kept only from a caller this device may hold a media pair with
    // (§17.3); from any other it is dropped — an older or a foreign
    // sender may still put it in.
    if (_callPairAdmissible(senderHex)) {
      if (invite.callerDCookie.isNotEmpty) {
        session.peerDCookies[senderHex] =
            Uint8List.fromList(invite.callerDCookie);
      }
      if (invite.callerCandidates.isNotEmpty) {
        session.peerCandidates[senderHex] =
            Uint8List.fromList(invite.callerCandidates);
      }
    } else if (invite.callerDCookie.isNotEmpty ||
        invite.callerCandidates.isNotEmpty) {
      _dropPlaneDMaterial(senderHex, 'INVITE');
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
    _attachBroker(session);
    _joinedEdge(session, senderHex);
    // The initiator gave no Plane D material although this side would
    // hold a media pair with it: its side has no consent (§17.7).
    if (session.peerDCookies[senderHex] == null) {
      _refusedByPeer(session, senderHex, 'INVITE');
    }
    _ensureOwnSendKey(session); // §10.2.1 per-sender media key
    // §17.2: "Every device that rings sends a `RING_ACK` carrying its
    // ephemeral X25519 binding marker" — the same marker its ANSWER carries
    // ([acceptGroupCall] finds it drawn), drawn now as in the 1:1 path
    // (`CallManager.handleCallInvite`). "A ringing device stops by itself
    // after 60 s" ([_ringingOver]).
    _ensureOwnEph(session);
    _detached(
        _signal(
            session,
            senderHex,
            proto.MessageType.MT_CALL_RING_ACK,
            (proto.CallRingAck()
                  ..callId = session.callId
                  ..deviceMarker = session.ephX25519Pk!)
                .writeToBuffer()),
        'CALL_RING_ACK (group)');
    session.ringing = GroupCallRinging(onRingingOver: () => _ringingOver(session))
      ..startRinging();
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
  /// INVITE ([handleGroupCallInvite]), not from the ANSWER, and the
  /// per-sender keys (§10.2.1) come via
  /// `MT_CALL_GROUP_SENDER_KEY`. A second ANSWER thus never re-derived a
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
  void handleGroupCallAnswer(HarvestEvent event) {
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
    if (_namesOtherGroup(session, event)) return;

    final senderHex = bytesToHex(Uint8List.fromList(event.senderUserId));
    final participant = session.participants[senderHex];
    if (participant == null) return;

    // §17.2: an invitation that already ended (not reached, not answered in
    // 60 s) joins nothing; the late ANSWER gets one HANGUP, as a late
    // RING_ACK does, so the device that picked up does not sit in a call
    // nobody holds.
    final ringing = session.ringing;
    if (ringing != null && ringing.hasEnded(senderHex)) {
      _answerLateReply(session, senderHex,
          bytesToHex(Uint8List.fromList(answer.calleeEphX25519Pk)));
      return;
    }
    ringing?.closed(senderHex);

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
      _detached(
          _signal(session, senderHex, proto.MessageType.MT_CALL_REJECT,
              reject.writeToBuffer()),
          'CALL_REJECT(full)');
      return;
    }

    // §17.2: from here on this participant is bound to EXACTLY THIS device.
    if (answerKey != null) {
      session.boundAnswerKeys[senderHex] = answerKey;
    }

    // §17.3/§17.4: the participant's Plane D material. It comes from
    // THIS ANSWER, i.e. from the answer of the device that bound the
    // session — that of a second device has already been
    // intercepted above. Kept only from a participant this device may hold
    // a media pair with (§17.3).
    final mediaPair = _callPairAdmissible(senderHex);
    if (mediaPair) {
      if (answer.calleeDCookie.isNotEmpty) {
        session.peerDCookies[senderHex] =
            Uint8List.fromList(answer.calleeDCookie);
      }
      if (answer.calleeCandidates.isNotEmpty) {
        session.peerCandidates[senderHex] =
            Uint8List.fromList(answer.calleeCandidates);
      }
    } else if (answer.calleeDCookie.isNotEmpty ||
        answer.calleeCandidates.isNotEmpty) {
      _dropPlaneDMaterial(senderHex, 'ANSWER');
    }

    participant.state = ParticipantState.joined;
    participant.joinedAt = DateTime.now();
    onParticipantChanged?.call(senderHex, ParticipantState.joined);
    _registerLiveMediaDevice(session, senderHex, event.senderDeviceId);
    _joinedEdge(session, senderHex);
    if (mediaPair && answer.calleeDCookie.isEmpty) {
      _refusedByPeer(session, senderHex, 'ANSWER');
    }

    _log.info('Participant joined V3: ${senderHex.substring(0, 8)} '
        '(device=${_deviceLabel(event.senderDeviceId)})');

    // §17.3: see `acceptGroupCall` — both sides run their window
    // as soon as they have both halves. Not awaited, for the same
    // reason.
    if (mediaPair) unawaited(_openParticipantMediaPath(session, senderHex));

    final joinedCount = session.joinedParticipantIds.length;
    if (joinedCount >= 2 && session.state == GroupCallState.inviting) {
      session.state = GroupCallState.inCall;
      _setupRttAndHealth(session);
      onGroupCallStarted?.call(session.toGroupCallInfo());
      _log.info('Group call active with $joinedCount participants');
    }
    _crystalEdge(session);
    // §10.2.1: hand the newcomer our send_key (no global rotation on join —
    // backward secrecy is natural, the newcomer never held prior keys). The
    // newcomer reciprocates with its own key via handleGroupCallSenderKey.
    _announceSendKeyTo(session, senderHex);

    // §17.2: the session is bound for this participant — the OTHER
    // devices of the participant are still ringing and only learn of it via us.
    // The ANSWER went to OUR tag, not to theirs (§14.2 — every device
    // harvests the tag of its own identity). ONE cell to the
    // identity of the participant reaches them all.
    //
    // Not only at the second ANSWER: if it were so, the ringing of the
    // siblings would only end when a SECOND device picks up — and if none
    // picks up, only at its own 60 s limit (§17.2, `GroupCallRinging`).
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
      await _signal(session, participantUserHex,
          proto.MessageType.MT_CALL_CANCEL_OTHERS, cancel.writeToBuffer());
      _log.info('CANCEL_OTHERS (group) to '
          '${participantUserHex.substring(0, 8)} — the ringing on their '
          'other devices ends');
    } catch (e) {
      // Best effort like every other signal. If it is lost, the sibling
      // devices stop at their own 60 s limit (§17.2, `GroupCallRinging`).
      _log.warn('CANCEL_OTHERS (group) could not be sent: $e');
    }
  }

  /// V3 receive-handler for CALL_CANCEL_OTHERS (group, §17.2).
  ///
  /// Three outcomes, as in the 1:1 path ([CallManager.handleCallCancelOthers]),
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
  void handleGroupCallCancelOthers(HarvestEvent event) {
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
    if (_namesOtherGroup(session, event)) return;

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

  // ── §17.2 in the group call: RING_ACK, 10 s, 60 s (S407-GAMUTE H-1) ────

  /// The last call this device ended as initiator, for a RING_ACK that
  /// arrives after it (§17.2). One is enough: a device runs one group call
  /// at a time, and "completed `callId`s are remembered for 24 h".
  GroupCallSession? _lastEndedOutgoing;
  DateTime? _lastEndedAt;

  /// RING_ACK of a group call (§17.2): "When the callee's `RING_ACK`
  /// arrives, it really is ringing on their end … the 60-s answer timeout
  /// start[s] then". Returns whether the RING_ACK belonged to a group call
  /// of this device — the running one or the last one it ended; otherwise
  /// the 1:1 path takes it (`CallService.handleCallRingAck`).
  bool handleGroupCallRingAck(HarvestEvent event) {
    final proto.CallRingAck ack;
    try {
      ack = proto.CallRingAck.fromBuffer(event.payload);
    } catch (e) {
      return false;
    }
    final senderHex = bytesToHex(Uint8List.fromList(event.senderUserId));
    final marker = bytesToHex(Uint8List.fromList(ack.deviceMarker));
    final session = _currentGroupCall;
    if (session != null && _callIdMatches(session.callId, ack.callId)) {
      if (_namesOtherGroup(session, event)) return true;
      // At a callee it is a sibling device's RING_ACK — nothing to learn.
      if (session.direction != CallDirection.outgoing) return true;
      final participant = session.participants[senderHex];
      final ringing = session.ringing;
      if (participant == null || ringing == null) return true;
      if (ringing.ringAck(senderHex)) {
        participant.state = ParticipantState.ringing;
        onParticipantChanged?.call(senderHex, ParticipantState.ringing);
        _log.info('RING_ACK from ${senderHex.substring(0, 8)} — it really '
            'rings there; ${GroupCallRinging.answerLimit.inSeconds} s for '
            'its ANSWER (§17.2)');
      } else if (ringing.hasEnded(senderHex)) {
        _answerLateReply(session, senderHex, marker);
      }
      return true;
    }
    final ended = _lastEndedOutgoing;
    final at = _lastEndedAt;
    if (ended == null || at == null) return false;
    if (DateTime.now().difference(at) > const Duration(hours: 24)) {
      _lastEndedOutgoing = null;
      _lastEndedAt = null;
      return false;
    }
    if (!_callIdMatches(ended.callId, ack.callId)) return false;
    _answerLateReply(ended, senderHex, marker);
    return true;
  }

  /// §17.2: "a `RING_ACK` for a call the caller has already ended is
  /// answered with one `HANGUP`" — here per member whose invitation ended
  /// without an answer, once per device marker.
  void _answerLateReply(
      GroupCallSession session, String memberHex, String marker) {
    if (!(session.ringing?.claimLateReply(memberHex, marker) ?? false)) {
      return;
    }
    _log.info('Late reply from ${memberHex.substring(0, 8)} for the ended '
        'invitation of ${session.callIdHex.substring(0, 8)} — one HANGUP');
    _hangUp(session, {memberHex}, 'late reply');
  }

  /// One HANGUP to each of [members] (§17.2) — a call signal, sent once.
  void _hangUp(GroupCallSession session, Set<String> members, String why) {
    final payload = (proto.CallHangup()..callId = session.callId)
        .writeToBuffer();
    for (final m in members) {
      _detached(_signal(session, m, proto.MessageType.MT_CALL_HANGUP,
          payload), 'CALL_HANGUP (group, $why)');
    }
  }

  /// Invitations of [members] ended without an answer — not reached in 10 s
  /// or not answered in 60 s (§17.2). Each is shown gone and gets one
  /// HANGUP; the call ends if no invitation is open and nobody joined.
  void _invitationsEnded(
      GroupCallSession session, Set<String> members, String why) {
    if (!identical(_currentGroupCall, session)) return;
    final ended = <String>{};
    for (final m in members) {
      final p = session.participants[m];
      if (p == null || p.state == ParticipantState.joined ||
          p.state == ParticipantState.left) {
        continue;
      }
      p.state = ParticipantState.left;
      onParticipantChanged?.call(m, ParticipantState.left);
      ended.add(m);
      _log.info('Invitation of ${m.substring(0, 8)} ended: $why (§17.2)');
    }
    _hangUp(session, ended, why);
    _missedCallFor(session, ended);
    _endIfNobodyCame(session);
  }

  /// §17.2 "Missed call": each of [members] gets the missed-call message —
  /// started on the initiator only, once per member and call
  /// ([GroupCallRinging.claimMissed]), after its HANGUP, so that the
  /// member's ringing has its end before the entry arrives (as the 1:1 path,
  /// `CallManager.hangup`). A member that answered or declined never reaches
  /// here: its invitation was closed.
  void _missedCallFor(GroupCallSession session, Set<String> members) {
    final ringing = session.ringing;
    if (session.direction != CallDirection.outgoing || ringing == null) {
      return;
    }
    for (final m in members) {
      if (!ringing.claimMissed(m)) continue;
      _log.info('Missed-call message to ${m.substring(0, 8)} for '
          '${session.callIdHex.substring(0, 8)} (§17.2)');
      try {
        onMissedCall?.call(
            m, session.groupIdHex, Uint8List.fromList(session.callId));
      } catch (e) {
        _log.warn('Missed-call message could not be started: $e');
      }
    }
  }

  /// §17.2 "not reachable … ends the call": a group call nobody joined ends
  /// once no invitation is being reached or rings any more.
  void _endIfNobodyCame(GroupCallSession session) {
    if (!identical(_currentGroupCall, session) ||
        session.direction != CallDirection.outgoing ||
        session.state != GroupCallState.inviting ||
        (session.ringing?.anyOpen ?? false)) {
      return;
    }
    _log.info('Group call ${session.callIdHex.substring(0, 8)}: no '
        'invitation open, nobody joined — the call ends (§17.2)');
    _endCall(session);
  }

  /// §17.2: "A ringing device stops by itself after 60 s" — it tells the
  /// initiator once, as the 1:1 callee does (`rejectCall('timeout')`).
  void _ringingOver(GroupCallSession session) {
    if (!identical(_currentGroupCall, session) ||
        session.state != GroupCallState.ringing) {
      return;
    }
    _log.info('Group call ${session.callIdHex.substring(0, 8)} rang '
        '${GroupCallRinging.answerLimit.inSeconds} s without an answer — '
        'ringing ends (§17.2)');
    final reject = proto.CallReject()
      ..callId = session.callId
      ..reason = CallManager.rejectReasonTimeout;
    _detached(
        _signal(session, session.initiatorHex,
            proto.MessageType.MT_CALL_REJECT, reject.writeToBuffer()),
        'CALL_REJECT(timeout)');
    _endCall(session);
  }

  /// V3 receive-handler for CALL_REJECT (group).
  void handleGroupCallReject(HarvestEvent event) {
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
    if (_namesOtherGroup(session, event)) return;

    final senderHex = bytesToHex(Uint8List.fromList(event.senderUserId));
    final participant = session.participants[senderHex];
    if (participant == null) return;

    // §17.2 "60 s of ringing without an ANSWER": the member's device stopped
    // by itself (`_ringingOver`, REJECT "timeout") — unanswered, not
    // declined. Its REJECT usually arrives before the initiator's own 60 s
    // run out (it started ringing first), so it is read here. D-79: a device
    // answering that it is in another call is missed as well; a bare "busy"
    // (4.2.3-beta sends it for "reject" too) stays an ordinary rejection.
    final rangOut = (reject.reason == CallManager.rejectReasonTimeout ||
            reject.reason == CallManager.rejectReasonInAnotherCall) &&
        (session.ringing?.isOpen(senderHex) ?? false);

    participant.state = ParticipantState.left;
    onParticipantChanged?.call(senderHex, ParticipantState.left);
    _log.info('Participant rejected V3: ${senderHex.substring(0, 8)} '
        '(${reject.reason})');
    // Its invitation is closed; with no invitation open and nobody joined
    // the call is over (§17.2).
    session.ringing?.closed(senderHex);
    if (rangOut) _missedCallFor(session, {senderHex});
    _endIfNobodyCame(session);
  }

  /// V3 receive-handler for CALL_HANGUP (group).
  void handleGroupCallHangup(HarvestEvent event) {
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
    if (_namesOtherGroup(session, event)) return;

    final senderHex = bytesToHex(Uint8List.fromList(event.senderUserId));
    if (session.state == GroupCallState.ringing) {
      // §17.2: the caller's one HANGUP ends a ringing device — the caller
      // gave up, or ended this member's invitation (10 s / 60 s). Only the
      // initiator rang it; nobody else ends its ringing.
      if (senderHex == session.initiatorHex) {
        _log.info('Group call ${session.callIdHex.substring(0, 8)}: the '
            'initiator hung up before an answer — ringing ends (§17.2)');
        session.ringing?.stopRinging();
        _endCall(session);
      }
      return;
    }
    _participantLeft(session, senderHex);
  }

  /// V3 receive-handler for GROUP_CALL_LEAVE.
  void handleGroupCallLeave(HarvestEvent event) {
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
    if (_namesOtherGroup(session, event)) return;

    final senderHex = bytesToHex(Uint8List.fromList(event.senderUserId));
    _participantLeft(session, senderHex);
  }

  /// V3 receive-handler for CALL_REJOIN.
  void handleCallRejoin(HarvestEvent event) {
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
    if (_namesOtherGroup(session, event)) return;

    final senderHex = bytesToHex(Uint8List.fromList(event.senderUserId));
    final participant = session.participants[senderHex];
    if (participant == null) return;

    participant.state = ParticipantState.joined;
    participant.joinedAt = DateTime.now();
    onParticipantChanged?.call(senderHex, ParticipantState.joined);
    _registerLiveMediaDevice(session, senderHex, event.senderDeviceId);
    _log.info('Participant rejoined V3: ${senderHex.substring(0, 8)} '
        '(device=${_deviceLabel(event.senderDeviceId)}, no global rotation)');

    _crystalEdge(session);
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
  void handleCallTreeUpdate(HarvestEvent event) {
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
    // The whole node list: a complete view (§17.5 edge binding).
    session.admission.treeViewComplete = true;
    session.broker?.suspend();

    _setupRelay(session);

    _log.info('Tree updated V3: version=${update.version}, '
        'depth=${session.tree.depth}');
  }

  /// V3 receive-handler for CALL_RTT_PING.
  ///
  /// Live-class per §10.4.5; reply pong is dispatched on the per-call
  /// route cache via [_sendLiveMediaToParticipant] (no extra ML-DSA).
  void handleCallRttPing(HarvestEvent event) {
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
      proto.MessageType.MT_CALL_RTT_PONG,
      pong.writeToBuffer(),
    );
  }

  /// V3 receive-handler for CALL_RTT_PONG.
  void handleCallRttPong(HarvestEvent event) {
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
  // come via GROUP_CALL_SENDER_KEY (`handleGroupCallSenderKey`).

  /// V3 receive-handler for GROUP_CALL_SENDER_KEY (§10.2.1). Registers an
  /// authenticated peer's secret media key.
  ///
  /// SECURITY: the announcement's inner ApplicationFrame is signed by
  /// `frame.senderUserId` (verified upstream in the V3 receive pipeline). We
  /// require the announced `sender_node_id` to equal that authenticated id —
  /// so a participant can only register a key under its OWN identity and
  /// cannot frame another by announcing a key for the victim's id.
  void handleGroupCallSenderKey(HarvestEvent event) {
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
    if (_namesOtherGroup(session, event)) return;

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
      _joinedEdge(session, authedHex);
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
        _joinedEdge(session, hex);
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
    //
    // Only with a participant this device may hold a media pair with
    // (§17.3, §17.7); from any other the material is dropped and no pair
    // key forms — the send key below is kept all the same (§17.5).
    final mediaPair = _callPairAdmissible(authedHex);
    if (mediaPair) {
      _ensurePairMaterialFor(session, authedHex);
      if (ann.dEphX25519Pk.isNotEmpty) {
        session.peerEphPk[authedHex] = Uint8List.fromList(ann.dEphX25519Pk);
      }
      if (ann.dCookie.isNotEmpty) {
        session.peerDCookies[authedHex] = Uint8List.fromList(ann.dCookie);
      }
      if (ann.dCandidates.isNotEmpty) {
        session.peerCandidates[authedHex] =
            Uint8List.fromList(ann.dCandidates);
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
      if (ann.dCookie.isEmpty) _refusedByPeer(session, authedHex, 'sender key');
    } else if (ann.dEphX25519Pk.isNotEmpty ||
        ann.dCookie.isNotEmpty ||
        ann.dCandidates.isNotEmpty ||
        ann.dKemCiphertext.isNotEmpty) {
      _dropPlaneDMaterial(authedHex, 'GROUP_SENDER_KEY');
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
    if (mediaPair &&
        session.pairKeys.containsKey(authedHex) &&
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
  /// `handleGroupCallAudioV3` and `handleGroupCallVideoV3` (both removed
  /// in S407) took a `HarvestEvent` — i.e. a frame that the DELIVERY
  /// LAYER harvested.
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
        ? proto.MessageType.MT_CALL_GROUP_VIDEO
        : proto.MessageType.MT_CALL_GROUP_AUDIO;

    // ── WHO SENT IT — resolved from the header, not from the D cookie:
    // the cookie names the last hop. The rationale in full length is in
    // `group_media_frame.dart`.
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

    // ── OVER WHICH EDGE (§17.5, B-5 in S407-GRUPPENANRUF) ─────────────
    //
    // Every participant holds every sender's `send_key`, so the slot in
    // the header can name anyone. Until S407 it was believed: any
    // participant could inject frames as any other, and the receiver
    // played them and passed them on. Now a sender's frames are taken
    // only over the media pair with it, from its bound broker, or over
    // the tree link towards it. What is refused is neither played nor
    // forwarded — and the own frame, should it ever come back, is
    // refused as well (hearing oneself).
    final verdict = session.admission.judge(
      ownHex: identity.userIdHex,
      linkHex: peerHex,
      senderHex: senderHex,
      tree: session.relay != null ? session.tree : null,
    );
    if (verdict == EdgeVerdict.refused) {
      if (session.admission.refused++ % 250 == 0) {
        _log.debug('Group media: a frame for ${senderHex.substring(0, 8)} '
            'over ${peerHex.substring(0, 8)} refused — not its media pair, broker or '
            'tree link (§17.5); ${session.admission.refused} so far');
      }
      return;
    }

    if (frame.kind == DFrameKind.video) {
      session.videoFramesReceived++;
    } else {
      session.totalFramesReceived++;
    }

    // THIS IS THE FORWARDING. Without `session.relay` — i.e. without an
    // arrived tree assignment — nothing happens here, and exactly by this
    // the guard measures whether the tree is ENTERED and not merely
    // built.
    //
    // Over every tree link except the one the frame came by (§17.7, B-2
    // in S407-GRUPPENANRUF). A frame that did not come over a tree link
    // at all — a participant still meshing before its own assignment has
    // arrived — is played but not passed on: everyone else gets it from
    // that participant directly, and passing it into the tree as well
    // would deliver it twice (IEEE 802.1D: a frame received on a port
    // that is not forwarding is not forwarded).
    final relay = session.relay;
    if (relay != null &&
        session.tree.linksOf(identity.userIdHex).contains(peerHex)) {
      relay.forwardFrame(Uint8List.fromList(frame.payload), type,
          from: peerHex);
    } else if (relay == null && verdict == EdgeVerdict.mediaPair) {
      // In the mesh: a frame a member of a pair we carry as its broker
      // sent us itself goes on to the pair's other member (§17.7, one hop,
      // both directions) — and only such a frame.
      session.pairRelay?.forwardFrame(
          Uint8List.fromList(frame.payload), type,
          from: peerHex, senderHex: senderHex);
    }

    // AND THIS IS HEARING IT ONESELF. Forwarding and playing are two
    // duties, not one; until S369 only the first stood here.
    onGroupMediaBody?.call(senderHex, frame.kind, parsed.body);
  }

  // S407: here stood `handleGroupCallAudioV3` and `handleGroupCallVideoV3`
  // — the delivery-layer receive handlers for group media. They had no
  // caller (`call_service.handleCallGroupAudio/VideoV3` discard such a
  // frame, §17.1: "media does **not** run in delivery cells"), and they
  // passed every frame on over the tree without knowing the link it came
  // by — exactly what §17.7 ("every tree link except the one it came by")
  // and §17.5 (the edge binding) rule out. A path that can only break
  // both rules is removed, not adapted.

  /// V3 outer-reply busy auto-reject. The peer device-id is delivered
  /// directly on the inbound `NetworkPacket`, so no routing
  /// re-resolution is needed.
  void _sendReject(HarvestEvent event, String reason) {
    try {
      final invite = proto.CallInvite.fromBuffer(event.payload);
      final senderUserId = Uint8List.fromList(event.senderUserId);

      final reject = proto.CallReject()
        ..callId = invite.callId
        ..reason = reason;
      // §17.2: a rejection is a call signal to the USER, naming the group
      // of the call it refuses — to a caller that is no contact it goes
      // over the group pair (§16.2.2). Until S407-GA-P3 it went over
      // `transport.sendSignal` and only to a contact with KEM keys in the
      // address book (a V3 remnant: the delivery layer seals to the
      // contact's or the pair's own keys); a fellow member who is no
      // contact rang into a busy line and heard nothing back.
      //
      // A-1 (S352): `sendViaUser` can throw; the surrounding `try` is
      // synchronous and never catches the throw of an `async` function.
      _detached(
          sendViaUser?.call(
            senderUserId,
            proto.MessageType.MT_CALL_REJECT,
            reject.writeToBuffer(),
            groupId: invite.groupId.isEmpty
                ? null
                : Uint8List.fromList(invite.groupId),
          ),
          'Group busy rejection');
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
    proto.MessageType type,
    Uint8List payload,
  ) {
    final kind = type == proto.MessageType.MT_CALL_GROUP_VIDEO
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
    proto.MessageType type,
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

  /// Limit for VIDEO in a group call, separate from the voice limits above.
  ///
  /// §17.7: "Video is offered up to a participant count set by measurement
  /// (Appendix C); until that count is set, video is offered up to the mesh
  /// ceiling of 6." The measurement does not exist yet, so this is the mesh
  /// ceiling — in either topology. When the measurement sets a number, it
  /// goes here and nowhere else.
  static const int maxParticipantsVideo = maxParticipantsMesh;

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
  /// `PlaneDCallTransport` returns `noCarrier` there without exception (§17.1
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

  /// Copies the mixer's hearing of [nodeIdHex] (`peer_hearing.dart`) into
  /// the participant, for `get_group_call_state`.
  void updateParticipantHearing(String nodeIdHex, PeerHearing hearing) {
    final participant = _currentGroupCall?.participants[nodeIdHex];
    if (participant == null) return;
    participant
      ..framesHeard = hearing.framesHeard
      ..framesDuplicate = hearing.framesDuplicate
      ..toneHz = hearing.toneHz;
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
    proto.MessageType type,
    Uint8List payload,
  ) {
    for (final pId in session.joinedParticipantIds) {
      if (pId == identity.userIdHex) continue;
      _sendLiveMediaToParticipant(pId, type, payload);
    }
  }

  /// V3 receive-handler for MT_WHITEBOARD_STROKE.
  void handleWhiteboardStroke(HarvestEvent event) {
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

  /// V3 receive-handler for MT_WHITEBOARD_PAGE.
  void handleWhiteboardPage(HarvestEvent event) {
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

  /// V3 receive-handler for MT_CALL_CHAT.
  void handleCallChat(HarvestEvent event) {
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

  /// V3 receive-handler for MT_FILE_EXCHANGE.
  void handleFileExchange(HarvestEvent event) {
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

  /// V3 receive-handler for MT_CLIPBOARD_EXCHANGE.
  void handleClipboardExchange(HarvestEvent event) {
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

  /// V3 receive-handler for MT_SCREEN_SHARE_FRAME.
  void handleScreenShare(HarvestEvent event) {
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
