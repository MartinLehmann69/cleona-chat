import 'dart:typed_data';
import 'package:cleona/core/calls/overlay_tree.dart';
import 'package:cleona/core/calls/media_relay.dart';
import 'package:cleona/core/calls/rtt_measurement.dart';
import 'package:cleona/core/calls/collaboration/whiteboard_manager.dart';
import 'package:cleona/core/calls/collaboration/call_chat_manager.dart';
import 'package:cleona/core/calls/collaboration/call_file_manager.dart';
import 'package:cleona/core/calls/collaboration/screen_share_manager.dart';
import 'package:cleona/core/util/hex.dart' show bytesToHex;
import 'package:cleona/core/service/service_types.dart';

/// A participant in a group call.
class GroupCallParticipant {
  final String nodeIdHex;
  String displayName;
  ParticipantState state;
  DateTime? joinedAt;
  int framesReceived;
  bool isMuted;
  double audioLevel;

  GroupCallParticipant({
    required this.nodeIdHex,
    required this.displayName,
    this.state = ParticipantState.invited,
    this.joinedAt,
    this.framesReceived = 0,
    this.isMuted = false,
    this.audioLevel = 0.0,
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

  // S368: `callKey` and `callKeyVersion` are removed. They carried the
  // shared group key from `CallInvite.group_call_key`, which stood there
  // as "Retained for wire-compat". Measured before the removal: the
  // two fields were WRITTEN in exactly two places
  // (`group_call_manager.dart`, caller and callee side) and READ in
  // no place in all of `lib/` — the value crossed the wire and arrived
  // nowhere. A shared key cannot authenticate the sender in a group
  // anyway; that is done by the per-sender keys below.

  /// §10.2.1 per-sender media keys. `ownSendKey` is this participant's secret
  /// media key — known only to us, used to encrypt OUR outgoing audio/video.
  /// `peerSendKeys` maps an authenticated participant userId-hex to the secret
  /// key they announced (via dual-signed GroupCallSenderKey), used to decrypt
  /// THEIR frames. Because each key is secret to its owner, a relaying
  /// co-participant cannot forge frames as another sender.
  Uint8List? ownSendKey; // 32 bytes AES-256, secret to us
  int ownSendKeyVersion = 0;
  final Map<String, ({Uint8List key, int version})> peerSendKeys = {};

  /// Participants we have already announced our current ownSendKey to (by
  /// userId-hex) — lets reciprocation avoid re-announcing on every inbound key.
  final Set<String> announcedSendKeyTo = {};

  // ── Mehrgeraete-Schiedsspruch (§17.2) ────────────────────────────

  /// Our ephemeral X25519 key for THIS group call — freshly drawn per
  /// call AND per device in `acceptGroupCall()`.
  ///
  /// It is the value by which this device recognises itself in an incoming
  /// CANCEL_OTHERS. Without it there was **no attribute** in the group path
  /// that distinguishes a picking-up device from its siblings:
  /// the group `callKey` comes from the INVITE and is the same for
  /// all devices, and the `CallAnswer` carried nothing at all in the group path
  /// except the `callId`.
  ///
  /// NOT a device identifier — §14.1: the DeviceID is "not an addressing
  /// means". The same recognition value as in the 1:1 path
  /// (`CallSession.ephX25519Pk`), for the same reasons; see the
  /// file header of `call_arbitration.dart`.
  Uint8List? ephX25519Pk;

  /// The corresponding secret part. It is not needed for the arbitration
  /// (there only the public value counts), but generating
  /// half a key pair would be a lie about what is in
  /// `CallAnswer.callee_eph_x25519_pk` — and this place is the
  /// natural spot at which a later pairwise negotiation attaches.
  Uint8List? ephX25519Sk;

  /// Only filled at the INITIATOR: participant userId hex -> the ephemeral
  /// key of the device whose ANSWER BOUND for this participant.
  ///
  /// §17.2: "the first `ANSWER` binds the session to one device". In the
  /// group call that applies per participant: the initiator is the only one
  /// who sees all ANSWERs of a participant in an order, and
  /// thus the only possible arbiter — just as in the 1:1 path.
  final Map<String, Uint8List> boundAnswerKeys = {};

  // == PLANE D MATERIAL PER PAIR (§17.3/§17.4, decision E-1 = B) =========
  //
  // The Plane D path of a group call carries a PAIRWISE
  // `call_key` per hop, not a shared one for the round. §17.7 makes
  // every relay in the crystal itself a participant; a shared
  // hop key would thus let everyone forge being anyone else on every hop
  // — exactly the rationale with which §17.5 already puts the content on
  // per-sender keys.
  //
  // A DISTINCTION THAT MUST NOT BLUR: [ownSendKey]/[peerSendKeys]
  // above encrypt the CONTENT (per sender, survives every
  // forwarding). The maps here carry the HOP (per pair, ends at
  // every relay). Two AEADs, two purposes.

  /// The session cookie (§17.4) that WE handed out to this participant
  /// — it is on everything that comes from them to us.
  ///
  /// **One of its own per participant, not one for the whole call.** The
  /// D socket keys its session table by the LOCAL cookie
  /// (`d_socket.dart`, `_sessions[local.key]`) and throws on
  /// reuse ("is already admitted"). A call with a
  /// single cookie for all would have exactly one session, and the demux
  /// would assign the frames of all participants to the same counterpart.
  final Map<String, Uint8List> localDCookies = {};

  /// The cookie that the participant named to US — we stamp it on
  /// everything that goes to them.
  final Map<String, Uint8List> peerDCookies = {};

  /// The participant's packed address candidates (§17.3), as they
  /// stood in INVITE/ANSWER.
  final Map<String, Uint8List> peerCandidates = {};

  /// The participant's ephemeral X25519 share for this call.
  final Map<String, Uint8List> peerEphPk = {};

  /// The ML-KEM secret that WE generated for this participant —
  /// our encapsulation to their STATIC `mlKemPk`.
  ///
  /// Must be kept because the derivation only succeeds once
  /// the reverse direction is also there, and that arrives later.
  final Map<String, Uint8List> ownKemSecretFor = {};

  /// The corresponding ciphertext — it goes out to the participant so that they
  /// can decapsulate the same secret. Kept because the same
  /// address can be repeated (join, rejoin, rotation)
  /// and a SECOND ciphertext would be a second secret.
  final Map<String, Uint8List> ownKemCtFor = {};

  /// The ML-KEM secret that the PARTICIPANT generated — decapsulated by us from
  /// their ciphertext, with our static secret key.
  final Map<String, Uint8List> peerKemSecretFor = {};

  /// The derived pairwise `call_key` (32 B) per participant.
  ///
  /// **This is the key under which the Plane D session to exactly
  /// this counterpart runs** — the value that `openMediaPath` requires.
  /// It is NOT the media content key; see the distinction above.
  final Map<String, Uint8List> pairKeys = {};

  /// Participants for whom the punch window (§17.3) has already been
  /// run — it runs up to 30 s and must not start again per arriving cell
  /// (working rule 5).
  final Set<String> mediaPathStarted = {};

  /// The address on which Plane D REALLY carries to this participant
  /// — the finding of the punch window, not the guess.
  ///
  /// It is the information that `_rebuildTree` needs for `isSameSubnet`:
  /// until S368 the predicate got node hex and therefore returned `false`
  /// even for the same identifier twice.
  final Map<String, String> peerMediaAddress = {};

  /// The participant list into which every index of a control frame points
  /// (§17.1.1/§17.7).
  ///
  /// **Sorted, and that is the whole promise.** Both sides form it
  /// from the same set by the same rule; an order that depended on
  /// insertion would be a different one on two devices. The
  /// checksum in the tree assignment catches the case that the SETS
  /// diverge (a late join).
  List<String> get rosterSorted => participants.keys.toList()..sort();

  /// The place of a participant in [rosterSorted], or `null`.
  int? rosterIndexOf(String hex) {
    final i = rosterSorted.indexOf(hex);
    return i < 0 ? null : i;
  }

  /// Nullable override for tree ownership (initially null = use initiatorHex).
  String? _ownerHex;

  /// Current tree owner (falls back to initiatorHex if not overridden).
  String get ownerHex => _ownerHex ?? initiatorHex;

  /// Set a new tree owner.
  set ownerHex(String hex) => _ownerHex = hex;

  /// Check if a given ID is the current owner.
  bool isOwner(String myHex) => ownerHex == myHex;

  /// §13.1.2 exemption #4: participant userId-hex -> device id registered
  /// with `CleonaNode.registerLiveMediaPeer` for this session's live-media
  /// PoW exemption. **`CleonaNode` was deleted with the CUT of 2026-08-31**
  /// (measured 2026-09-03); the exemption list is V3 mechanics
  /// without a V4.1 counterpart — see `call_manager.dart` at the field of the same name.
  /// Tracked per-participant (not a flat `Set<Uint8List>`) so
  /// GROUP_LEAVE/HANGUP can unregister exactly the departing participant's
  /// device, and full teardown can unregister everyone still on it.
  final Map<String, Uint8List> registeredLiveMediaDeviceIds = {};

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

  // ── In-Call Collaboration (§10.5) ────────────────────────────────

  /// Whiteboard manager — initialized when collaboration starts.
  WhiteboardManager? whiteboard;

  /// Call chat manager — ephemeral in-call messaging.
  CallChatManager? callChat;

  /// File sharing manager.
  CallFileManager? fileManager;

  /// Screen share manager.
  ScreenShareManager? screenShare;

  /// Set once the receive-side live-media fast path (Architecture §10.3,
  /// F-C) has logged its "active" line for this group call — prevents
  /// per-frame log spam (audio alone runs at ~50 frames/sec).
  bool liveMediaFastPathLogged = false;

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
                  isMuted: p.isMuted,
                  audioLevel: p.audioLevel,
                ))
            .toList(),
        totalFramesSent: totalFramesSent,
        totalFramesReceived: totalFramesReceived,
        videoFramesSent: videoFramesSent,
        videoFramesReceived: videoFramesReceived,
      );
}
