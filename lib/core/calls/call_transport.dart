// The Plane D API (§17). The call layer talks to the transport exclusively
// through this.
//
// ## Where this cut comes from
//
// §17 formulates the target state in one sentence: "The Plane D API is narrow
// and explicit; call code does not access transport internals." The
// actual state was the opposite — 32 code sites in three files depended
// directly on the V3 transport (routing table, wire frames, device keys,
// `sendToDevice`). The contract here collected them.
//
// ## What changed on 2026-08-31 (CUT)
//
// The V3 code is out, and with it `CallTransportV3` — the only
// implementation there ever was. The contract did NOT survive the move
// unchanged, and that is the honest version: six
// operations were V3 mechanics, not Plane D, and stood here only because
// V3 needed them.
//
//   * `selfDeviceId` and `sendSecuredToDevice` had **zero** callers in `lib/`
//     (measured 31.08.).
//   * `sendSignalReplyToDevice` addressed a DEVICE. §14.2 gives
//     delivery no device level, `HarvestEvent.senderDeviceId` is always
//     `null` on the V4.1 path — both call sites lay behind
//     `if (deviceId != null)` and were thus dead. §17.2 says what
//     applies instead: a rejection is "an ordinary 1:1 cell under
//     pairwise tags", i.e. [sendSignal].
//   * `admitMediaPeer` / `revokeMediaPeer` carried the V3 PoW exemption list.
//     §17.4 replaces it completely: "the D socket responds **exclusively**
//     to packets with a valid AEAD under `call_key` plus a session cookie …
//     Whoever does not have the `call_key` from signaling does not exist for
//     the socket." A list that nobody reads anymore is no admission.
//   * `userHexForDevice` answered the question "which user does
//     this sending device belong to". §17.4 deletes the question: a D frame is
//     authentic via AEAD under the `call_key`.
//   * `sendMediaToDevice` + `sendMediaToParticipant` merge into [sendMedia].
//     Plane D addresses a SESSION, named by the
//     counterpart — not a device and not a route ("No routes, only
//     address candidates", §17.1).
//
// Everything that is dropped without replacement in V4.1 does NOT appear here: no
// routing table, no `dvRouting`, no `natTraversal`, no wire frame.

import 'dart:typed_data';

import 'package:cleona/core/calls/punch_window.dart';
import 'package:cleona/core/calls/call_control_frame.dart';
import 'package:cleona/core/link_io/d_frame.dart';
import 'package:cleona/generated/proto/transport_v3.pb.dart' as proto;

/// Why a media frame could not be delivered. Deliberately passes
/// no transport state upwards — the call layer only needs the
/// distinction for log lines and the display.
enum MediaSendFailure {
  /// No admitted Plane D session to this counterpart (§17.4). In V3
  /// this was called "no routing entry"; in V4.1 it means "there is no
  /// carrying address pair" (§17.3) — for the call layer the same
  /// event.
  noPath,

  /// Target known, frame building failed.
  buildFailed,

  /// The payload fits into neither of the two size classes from §17.1.
  ///
  /// **Not an error of Plane D, but its declared limit.** A
  /// promotion into the next class would be a size difference on
  /// the wire — exactly the fingerprint the classes buy away. Whoever
  /// sees this has a codec to configure, not a frame to
  /// enlarge.
  tooLarge,

  /// Plane D has no carrier for this kind of frame.
  ///
  /// ── THIS SENTENCE HAS BEEN A DIFFERENT ONE SINCE S368 (05.09.2026) ─────────────
  ///
  /// Until then this said: "§17.1 knows three kinds: voice,
  /// video fragment, stream block. Everything else — key distribution,
  /// tree maintenance, RTT probes of a group call — is signaling […];
  /// the group topology is open in V4.1 (§17.5, K31-3)."
  ///
  /// Neither holds anymore. **§17.1.1 gives Plane D a FOURTH kind**
  /// ([DFrameKind.control]) and enumerates what it carries: speech level,
  /// readiness, presentation role, layout size, **tree assignments** and
  /// RTT probes. And **K31-3 was closed on 05.09.2026 by §17.7**;
  /// the group topology is no longer open, it is normative.
  ///
  /// The value stays and now means exactly one thing: **a payload
  /// that is not §17.1.1 information.** A whiteboard stroke, an
  /// in-call chat, a file from §10.5 are not control information; sending them via
  /// the control frame would mean doing exactly what §17.1.1
  /// rules out ("anything that would make it worth relaying by a node
  /// that is not a call participant"). They still have no carrier,
  /// and that is a statement, not a gap.
  ///
  /// Whoever wants to send tree maintenance or RTT takes [CallTransport.sendControl]
  /// — not [CallTransport.sendSecuredToParticipant].
  noCarrier,
}

/// The Plane D API. The call layer talks to the transport exclusively
/// through this.
abstract class CallTransport {
  // ── Signaling (§17.2: ordinary 1:1 cells under pair tags) ────
  //
  // It runs via the delivery layer, not via Plane D. Addresses
  // a USER: "an INVITE is **one** cell — all of the callee's devices
  // harvest the same tag line and ring" (§17.2).

  /// Signaling message to all devices of the recipient.
  ///
  /// **ONCE. There is no repetition** — §17.2: "An INVITE is
  /// **placed once**; there is **no retransmission**". The reliability
  /// comes from the redundancy of the placement (`m x R_signal`, §17.2), not from
  /// the number of attempts.
  Future<bool> sendSignal({
    required Uint8List recipientUserId,
    required proto.MessageTypeV3 type,
    required Uint8List payload,
  });

  // ── Media (Plane D, own D-frame format §17.1) ───────────────────
  //
  // No PoW, no signature per frame, no zstd, never ACK-tracked,
  // unpaced. AES-256-GCM under the `call_key` carries the authenticity
  // of every single frame.

  /// Why Plane D cannot carry media today — or `null` if it
  /// can.
  ///
  /// **Why this stands in the contract and not in a footnote.** A call
  /// whose signaling goes through and whose media then silently
  /// peter out is the worst of all versions: the user sees a
  /// running conversation and hears nothing. Whoever starts a call asks
  /// here first and refuses with a REASON (`call_service.dart`,
  /// `onCallUnavailable`). The text is a diagnostic line for log and
  /// support, not a UI string — it is not translated.
  String? get mediaUnavailableReason;

  // ── The path to the session (§17.3 punch window) ─────────────────────────
  //
  // Three operations, and they are deliberately THREE: the cookie must be drawn
  // before the INVITE is built; the candidates must go into the same
  // INVITE; and the window can only run once the ANSWER is there. A
  // single operation could not serve these three points in time.

  /// A fresh session cookie (§17.4) for a new call, 8 B.
  ///
  /// It goes out as `caller_d_cookie` / `callee_d_cookie` and is what
  /// incoming frames of THIS side carry. The caller keeps it until
  /// the media path is opened.
  Uint8List newDCookie();

  /// The own address candidates (§17.3), packed for INVITE/ANSWER.
  ///
  /// Empty if this node cannot name any — then the
  /// other side starts no window, instead of sending against nothing.
  Future<Uint8List> localCandidatesPacked();

  /// Admits the Plane D session and runs the punch window (§17.3).
  ///
  /// What comes back is the FINDING: the carrying address pair or the reason
  /// why none carries. The reason belongs in the call UI —
  /// "no common connection type" is information that §17.3
  /// explicitly requires ("clear message"), not a silent failure.
  Future<PunchOutcome> openMediaPath({
    required String peerHex,
    required Uint8List callKey,
    required Uint8List localCookie,
    required Uint8List remoteCookie,
    required List<int> peerCandidatesPacked,
  });

  /// A media frame to the Plane D session with [peerHex].
  ///
  /// The session is pinned during connection setup (§17.3: "the media path
  /// is fixed with the first viable address pair"); its selection does not belong
  /// in this API. Fire-and-forget.
  ///
  /// [payload] goes into the frame as PLAINTEXT — the encryption is
  /// the AEAD of the D frame under the `call_key` (§17.1). Whoever passes in
  /// something already encrypted pays for the size twice and bursts the
  /// 176 B class.
  ///
  /// Returns `null` on success, otherwise the reason.
  MediaSendFailure? sendMedia({
    required String peerHex,
    required DFrameKind kind,
    required Uint8List payload,
  });

  /// Every D frame that arrived under an admitted session and
  /// authenticated.
  ///
  /// `seq` and payload come from the frame itself (§17.1: "inner:
  /// kind ‖ seq ‖ len ‖ body"); order and loss handling
  /// sits above it (§17.5, JitterBuffer).
  set onMediaFrame(void Function(String peerHex, DFrame frame)? cb);

  /// Per-call frame to a group participant that is NOT media —
  /// key distribution, tree maintenance, RTT probes.
  ///
  /// Stands here so that the group logic does not send by itself bypassing
  /// the contract.
  ///
  /// **Corrected S372:** this said "Its future depends on C-9/C-10/C-11
  /// (§17.5, ‚Still open: group-call topology')". K31-3 has been CLOSED since
  /// 05.09.2026 by §17.7 — v4_1 itself lists the entry
  /// as "CLOSED 2026-09-05 by §17.7". What is open is something different and
  /// smaller: §17.1 knows three frame kinds (voice, video fragment,
  /// stream block), and tree maintenance and RTT probes are none of them. The
  /// MEMBERSHIP no longer runs along here anyway since E-1 = B,
  /// but via `GroupCallSenderKey.joined_participants` on the
  /// delivery layer.
  MediaSendFailure? sendSecuredToParticipant({
    required String participantHex,
    required Uint8List peerX25519Pk,
    required Uint8List peerMlKemPk,
    required proto.MessageTypeV3 type,
    required Uint8List payload,
    bool expectsReply,
  });

  /// A CONTROL RECORD to a group participant (§17.1.1).
  ///
  /// The carrier that [sendSecuredToParticipant] never had. It takes no
  /// proto message but a [ControlRecord] — and the difference
  /// is not taste but the size class: a control frame
  /// carries 85 B, a `CallTreeUpdate` proto measures at 30 participants
  /// 1134 B (measured 05.09.2026). What §17.1.1 enumerates fits into 85 B;
  /// what does not fit in was never control information.
  ///
  /// **It is not sent immediately.** §17.1.1: "Bundling is mandatory, not
  /// an optimization. All pending messages of one tick travel in one
  /// frame, at **1 Hz**" (owner decision 05.09.2026; until then the document
  /// said 2 Hz, because 85.6 B did not fit into the 85 B of the
  /// 128 B class at the time). The record is thus queued and sent with the
  /// next tick; `null` means "queued", not "on
  /// the wire". Whoever wants to measure the wire measures the tick.
  ///
  /// Return value as everywhere: `null` = accepted, otherwise the reason.
  MediaSendFailure? sendControl({
    required String participantHex,
    required ControlRecord record,
  });

  /// Every CONTROL RECORD that arrived under an admitted session
  /// (§17.1.1).
  ///
  /// **Separate from [onMediaFrame], and that is the point.** A
  /// control frame is "**not** a media frame — it carries no media and is
  /// never handed to a codec" (§17.1.1). Sending it through the same return line
  /// would mean leaving the distinction to the JitterBuffer
  /// — exactly the mistake that `DFrameKind.punch` has already avoided once for its
  /// own kind.
  set onControlRecord(
      void Function(String peerHex, ControlRecord record)? cb);

  /// Why the TREE MAINTENANCE of a group call does not carry on this transport
  /// — or `null` if it carries.
  ///
  /// **The same design as [mediaUnavailableReason], and for the same
  /// reason.** A forwarding tree whose `CALL_TREE_UPDATE` disappears
  /// in transit is the worst of all versions: the initiator builds
  /// a tree, only sends to its three children, and all the others
  /// never learn that they should forward. Whoever ties a promise to the
  /// tree topology — a participant limit, for example —
  /// asks here first.
  ///
  /// **The answer is not a proxy for "the tree carries".** It
  /// answers exactly one of the two preconditions, namely whether
  /// tree maintenance has a carrier. The second — whether there is a
  /// Plane D session to a group participant at all — does not lie
  /// in the transport but with the caller.
  ///
  /// **Both have been fulfilled since S368.** Until then this said:
  /// "`GroupCallManager` calls [openMediaPath] for group participants today
  /// nowhere (measured 05.09.2026, S368: zero hits outside
  /// `call_manager.dart`)." That was the second part of the finding; it was
  /// closed with `GroupCallManager._openParticipantMediaPath`, which
  /// obtains the same four pieces from INVITE and ANSWER as the
  /// 1:1 path — both cookies, the `call_key` and the candidates.
  ///
  /// Diagnostic line for log and proposals, not a UI string —
  /// it is not translated.
  String? get treeMaintenanceUnavailableReason;

  // ── State that the call layer really needs ────────────────────

  /// The media path to a peer no longer carries.
  ///
  /// §17.4: "10 s without valid media frames end the session (UI:
  /// ,connection lost'), independent of signaling." For the call layer
  /// it is the same event as the V3 route downgrade: the call no longer
  /// holds.
  set onMediaPathLost(void Function(String peerHex)? cb);

  /// Cost estimate for the path to a participant, for building the
  /// overlay multicast tree of a group call. [fallback] is
  /// returned if no estimate is available.
  ///
  /// **There is nothing to estimate, and that is decided.**
  ///
  /// Corrected S372: this said "Open in V4.1, not decided. §17.5
  /// explicitly lists the group call topology as open
  /// (C-9/C-10/C-11) … exactly that the delivery layer does not provide."
  /// §17.7 has decided it since 05.09.2026, and the objection did not quite hold
  /// even before: WITHIN a call participants are very much
  /// addressable (address candidates and punch window, §17.3) — since
  /// E-1 = B with a pairwise `call_key` per hop. What §17.7 requires for the
  /// selection is moreover NOT the path cost, but
  /// "reachable at all -> link type -> power source -> measured usable
  /// upload -> RTT as a tie-break". An invented cost value would be
  /// worse than the fallback value: the spanning tree on top would look
  /// weighted and would not be.
  int routeCostTo(String participantHex, {int fallback});

  /// End the Plane D session to a participant (participant leaves
  /// the call).
  void forgetParticipant(String participantHex);

  /// End all level-D sessions (call ends).
  void forgetAllParticipants();
}
