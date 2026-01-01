import 'dart:async';
import 'dart:typed_data';


import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/util/hex.dart';
import 'package:cleona/core/calls/call_arbitration.dart';
import 'package:cleona/core/calls/call_transport.dart';
import 'package:cleona/core/calls/media_format_version.dart';
import 'package:cleona/core/calls/punch_window.dart' show PunchOutcome;
import 'package:cleona/core/identity/identity_context.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/core/service/harvest_event.dart';
import 'package:cleona/generated/proto/app_payloads.pb.dart' as proto;
import 'package:cleona/generated/proto/transport_v3.pb.dart' as proto;
import 'package:cleona/core/sync/delivery_params.dart' show kInteractiveDeliveryTtl;

/// Represents an active or pending call with crypto state.
class CallSession {
  final Uint8List callId;
  final String peerNodeIdHex;
  final CallDirection direction;
  final bool isVideo;
  CallState state;
  DateTime startedAt;

  // Ephemeral key exchange for audio encryption
  Uint8List? ephX25519Pk;
  Uint8List? ephX25519Sk;
  Uint8List? sharedSecret; // 32 bytes AES-256 key for audio
  Uint8List? kemSharedSecret; // ML-KEM shared secret from caller's encapsulation

  // Audio frame counters for E2E verification
  int framesSent = 0;
  int framesReceived = 0;

  // Video frame counters
  int videoFramesSent = 0;
  int videoFramesReceived = 0;

  /// The peer's concrete device that performed the call handshake —
  /// captured from `senderDeviceId` on inbound CALL_INVITE (callee side)
  /// or CALL_ANSWER (caller side). Dual use: (a) registered with
  /// `CleonaNode.registerLiveMediaPeer` for this session's live-media PoW
  /// exemption (§13.1.2 exemption #4) — stored here so teardown
  /// unregisters exactly the device id this session added; (b) checked by
  /// the receive-side live-media fast path (Architecture §10.3) so only
  /// this exact device is trusted as plaintext-inner CALL_AUDIO/VIDEO
  /// source for the duration of the call.
  ///
  /// **On the V4.1 receive path the field stays `null`** (B-32, S349):
  /// `HarvestEvent.senderDeviceId` is `null` there, because §14.2 gives
  /// delivery no device level. Both uses above are
  /// V3 mechanics: the PoW exemption list is completely replaced by §17.4 with
  /// AEAD under the `call_key` plus session cookie ("Whoever does not have
  /// the `call_key` from signaling does not exist for the socket"). Without
  /// a device identifier there is consequently nothing to register — and nothing
  /// missing.
  Uint8List? peerDeviceId;

  /// The session cookie that THIS side handed out (§17.4), 8 B.
  ///
  /// It goes out as `caller_d_cookie` (INVITE) or `callee_d_cookie` (ANSWER).
  /// It must stay the same over the whole call: the
  /// other side stamps it on every frame it sends, and the
  /// demux finds the session via nothing else (`d_socket.dart`,
  /// step 2). A second cookie would be a session that only this
  /// side knows.
  Uint8List? localDCookie;

  /// The session cookie of the OTHER SIDE (§17.4), 8 B. Is stamped on everything
  /// this side sends.
  Uint8List? peerDCookie;

  /// Callee side: the audio/video format range that the CALLER named in the
  /// INVITE (§10.3.1/§10.4/§10.6, V1.18, S367). Set in
  /// `CallManager.handleCallInviteV3`, read in `acceptCall` for
  /// `MediaFormatVersion.negotiate`. `null` only as long as a call never
  /// came through the INVITE receive path (e.g. a session that a test
  /// constructs directly) — `acceptCall` falls back to the
  /// base format in that case, the same statement as a wire value of 0.
  MediaFormatRange? peerAudioFormatRange;
  MediaFormatRange? peerVideoFormatRange;

  /// The address candidates of the other side (§17.3), packed as they stood on the
  /// wire.
  ///
  /// Kept raw and not decoded: decoding happens in exactly one
  /// place, namely where the window runs. Two decoding places
  /// would be two readings of the same bytes.
  Uint8List? peerCandidates;

  /// Does the media path carry? `null` as long as the punch window has not
  /// run; otherwise the carrying pair as `adresse:port` or the
  /// reason why none carries.
  ///
  /// **The display needs the distinction.** For the case without a common family,
  /// §17.3 explicitly requires a "clear message"; a
  /// call that rings and then stays silent is exactly the opposite.
  String? mediaPathNote;

  /// Has this call already reported ONCE that Plane D carries nothing?
  ///
  /// A call sends up to 50 frames/s. Without this marker the
  /// report itself would be the damage — with it, it appears exactly once per call
  /// in the log, with reason (`call_service.dart`, `sendLiveMediaFrame`).
  bool mediaFailureLogged = false;

  /// Caller side: the ephemeral X25519 key from the ANSWER
  /// that bound this session (§17.2: "the first `ANSWER` binds the
  /// session to one device").
  ///
  /// It is at the same time the value that CANCEL_OTHERS carries — see
  /// `call_arbitration.dart` for the rationale why the ephemeral
  /// key and not the DeviceID names the device.
  Uint8List? boundAnswerKey;

  /// Caller side: is this call still at `reaching` (§17.2)?
  ///
  /// §17.2, lines 5409-5413: "After placing the INVITE, the caller shows
  /// ,reaching …' — **no** ringtone. Ringtone and the 60-s answer timeout
  /// start only once the callee's `RING_ACK` cell has been harvested (,it
  /// really is ringing on their end'). This means there is no fake ringing
  /// against a device that was never reached."
  ///
  /// `true` from placing the INVITE until the first harvested
  /// RING_ACK. After that — and only after that — the ringback tone and the
  /// 60 s answer deadline run.
  ///
  /// The state lives here and not in [state], because `CallState`
  /// (`service_types.dart`) does not know the value `reaching` and its index
  /// is part of the IPC contract via `CallInfo.toJson()`. As long as the value is
  /// missing there, [state] stays `ringing` and this flag carries the
  /// distinction.
  bool reaching = false;

  /// Caller side: the device markers from which a RING_ACK was harvested.
  ///
  /// §17.2: "`RING_ACK` carries the `deviceId`" — here the ephemeral marker
  /// instead of a device identifier (rationale in the field comment of
  /// `CallRingAck.device_marker`). As a set, so that a cell harvested
  /// repeatedly does not count as a second ringing device.
  final Set<String> ringingDeviceMarkers = <String>{};

  /// Caller side: is the session already bound to an ANSWER?
  ///
  /// Separate from [boundAnswerKey], because another side can theoretically answer without an
  /// ephemeral key (the group call path does). Then
  /// the session is bound, but not nameable — and a second
  /// ANSWER must still not overwrite the session key.
  bool answerBound = false;

  // ── THE PER-CALL ROUTE CACHE IS GONE (S357) ────────────────
  //
  // Here stood `cachedRoute`, `cachedRouteAt` and
  // `invalidateCachedRoute()`. They were WRITTEN and deleted, but
  // never READ anywhere in the tree — measured: the only read sites were
  // in `smoke_audio_stack_opts.dart`, i.e. in a test that
  // measured exclusively itself. That file was deleted along with the cache:
  // its own header called the route cache "this file's
  // surviving coverage", so nothing was left. A suite that
  // reports "No tests ran" and counts as green with exit 0 is worse
  // than none — that is the class of error from S348.
  //
  // The cause is a clean cut whose remainder was left lying around: AP-2 moved
  // the route cache into the adapter
  // (`call_transport_v3.dart`, `_routeCache`, with the note "Was previously
  // `_participantRouteCache` in `GroupCallManager`"). The field here
  // stayed.
  //
  // AND V4.1 NO LONGER HAS AN OBJECT FOR IT. The quoted §10.4.1 has been absorbed into
  // v4_1 §17.3, and §17.1 explicitly says "**No routes, only
  // address candidates**" — the media path is fixed with the first carrying
  // address pair, there is no routing table from which one could
  // cache. The cache is not merely unused, it
  // could not be restored in V4.1.
  //
  // With it goes the import of `network/peer_info.dart` — and with that the
  // only real network edge of this file (cut, step 0).

  /// Set once the receive-side live-media fast path has logged its
  /// "active" line for this call — prevents per-frame log spam (~50/s).
  bool liveMediaFastPathLogged = false;

  CallSession({
    required this.callId,
    required this.peerNodeIdHex,
    required this.direction,
    this.isVideo = false,
    this.state = CallState.idle,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();

  String get callIdHex => bytesToHex(callId);

  CallInfo toCallInfo() => CallInfo(
        callId: callIdHex,
        peerNodeIdHex: peerNodeIdHex,
        direction: direction,
        isVideo: isVideo,
        state: state,
        startedAt: startedAt,
        framesSent: framesSent,
        framesReceived: framesReceived,
        videoFramesSent: videoFramesSent,
        videoFramesReceived: videoFramesReceived,
      );
}

/// The signaling of a call (§17.2).
///
/// **Two paths, and both go via the DELIVERY LAYER — not via
/// Plane D.** §17.2: signaling is "ordinary 1:1 cells under
/// pairwise tags — flowless, anonymous, indistinguishable from any other
/// traffic on the delivery layer".
///
///   * INVITE/ANSWER/HANGUP/RING_ACK/CANCEL_OTHERS → `sendViaUser`
///     (== `CleonaService.sendToUser`). ONE cell to the user; all
///     devices of the recipient harvest the same tag line and ring
///     (§17.2, §14.2).
///   * The busy rejection → `CallTransport.sendSignal`, the same path.
///
/// The MEDIA go nowhere through this class. They run via Plane D
/// (§17.1), and their state is in `CallTransport.mediaUnavailableReason`.
class CallManager {
  final IdentityContext identity;
  /// AP-2b: the Plane D API instead of the raw node. Before, this said
  /// `final CleonaNode node;` — the call layer saw the routing table,
  /// wire frames and device keys (MIGRATION §5.5).
  final CallTransport transport;
  final Map<String, ContactInfo> contacts;
  final CLogger _log;

  CallSession? _currentCall;
  Timer? _ringingTimeout;

  /// Memory for ended calls (§17.2: "completed `callId`s are
  /// remembered for 24 h (late duplicates are no-ops)").
  ///
  /// A device that finds INVITE and CANCEL_OTHERS in THE SAME harvest
  /// must survive the order in which the INVITE comes
  /// last — the placement yields no order. Until S357 there was
  /// a second reason (the caller repeated its INVITE 19 times
  /// at a three-second interval, a device then rang again); the
  /// repetition was dropped with §17.2, the memory stays.
  final TerminatedCallLedger terminatedCalls;

  /// Ringing timeout in seconds (auto-hangup if not answered).
  static const int ringingTimeoutSec = 60;

  /// §17.2: deadline for the state `reaching`, in seconds.
  ///
  /// According to §17.2 the 60 s answer deadline may only begin with the harvested RING_ACK.
  /// If none ever comes, the call still needs an end — otherwise
  /// the caller would stand on "reaching …" indefinitely.
  ///
  /// The value is NOT invented and since S357 no longer stands
  /// there twice: it is the TTL class "interactive" of the DELIVERY LAYER
  /// (`kInteractiveDeliveryTtl`, §17.2), and that belongs there, not
  /// in the call layer. A copy would be exactly the drift that nobody
  /// notices — `smoke_v41_signaling_ttl.dart` keeps both together.
  ///
  /// **CORRECTION OF THE PREVIOUS VERSION (S357).** Here it said: "After 120 s the
  /// INVITE has expired at the relays and can no longer ring anywhere."
  /// That is the TARGET state from §17.2 and was claimed as the actual state.
  /// Measured (S357): `SecureStore.keepEpochs` was preset to `kHarvestEpochs`
  /// = 3, with `kEpochSeconds = 86400` — a signal cell lay
  /// at the relays for **three days** back then, as long as any other.
  ///
  /// **Two changes since then, both measured.** S358 introduced the
  /// signal class `kRetentionSignal`: an INVITE cell drops
  /// after `kSignalKeepBuckets` buckets, i.e. after 121-240 s, no longer
  /// with the ordinary deadline. S363 (D2) raised the ordinary deadline
  /// from 3 to `kNormalKeepEpochs` = 14 days — which no longer affects the
  /// signal cell, precisely because it has its own class.
  /// The deadline here is thus
  /// the deadline of the CALLER ("this long I stand on reaching"), not
  /// that of the cell. The two only coincide once the class is also on
  /// the wire; see `kInteractiveDeliveryTtl`.
  static const int reachingTimeoutSec = 120;

  /// Self-test: the deadline above IS the TTL class of the delivery layer.
  ///
  /// As an `assert` and not as an initializer, because `reachingTimeoutSec`
  /// is a `const int` constant of the public interface and
  /// as such should stay directly readable in `switch` cases and tests.
  static bool debugTtlMatchesDeliveryClass() =>
      reachingTimeoutSec == kInteractiveDeliveryTtl.inSeconds;

  Timer? _reachingTimeout;

  /// `major * 1000 + minor` for the current build. Set on outgoing
  /// CALL_INVITE so the receiver's E5 version gate can reject incompatible
  /// builds before anything rings.
  int _callerAppMajorMinor = 0;
  set callerAppMajorMinor(int v) => _callerAppMajorMinor = v;

  // Callbacks for UI
  void Function(CallSession call)? onIncomingCall;
  void Function(CallSession call)? onCallAccepted;

  /// §17.2: the first RING_ACK has been harvested — "it really is ringing on their
  /// end". ONLY NOW may the ringback tone play.
  ///
  /// The consumer is `call_service.dart`. Before this version it started
  /// the tone directly in `startCall()`, even before the crypto pipeline — i.e.
  /// against a device of which nobody knew whether it would ever be reached.
  /// §17.2: "This means there is no fake ringing against a device that was
  /// never reached."
  void Function(CallSession call)? onRemoteRinging;
  void Function(CallSession call, String reason)? onCallRejected;
  void Function(CallSession call)? onCallEnded;

  /// V3 setup-path send callback — wired by `CleonaService` to its
  /// `sendToUser` orchestrator (Architecture §2.6.2 / §10.1). Used for
  /// CALL_INVITE/ANSWER/REJECT/HANGUP. Returns true if at least one
  /// device-leg of the recipient fan-out dispatched.
  ///
  /// **Without `outLegs` (S357).** The parameter existed solely for the
  /// INVITE repetition that §17.2 forbids; it goes with it.
  Future<bool> Function(
    Uint8List recipientUserId,
    proto.MessageTypeV3 type,
    Uint8List payload,
  )? sendViaUser;

  // Temporarily holds caller's ephemeral PK until we accept
  Uint8List? _callerEphPk;
  Uint8List? _callerKemCt; // KEM ciphertext from caller

  CallManager({
    required this.identity,
    required this.transport,
    required this.contacts,
    required String profileDir,
    DateTime Function()? clock,
  })  : _log = CLogger.get('calls', profileDir: profileDir),
        terminatedCalls = TerminatedCallLedger(clock: clock);

  CallSession? get currentCall => _currentCall;
  bool get inCall => _currentCall?.state == CallState.inCall;
  bool get isRinging => _currentCall?.state == CallState.ringing;

  /// Plane D carries no media for this call (§17.3).
  ///
  /// Carries the call and the diagnostic line from `PunchOutcome.refusal`.
  /// For the case without a common address family, §17.3
  /// explicitly requires a "clear message"; whoever wires nothing here leaves
  /// the user sitting in front of a silent conversation.
  void Function(CallSession call, String reason)? onMediaPathUnavailable;

  /// Initiate a call to a contact.
  Future<CallSession?> startCall(String peerNodeIdHex, {bool video = false}) async {
    if (_currentCall != null) {
      _log.warn('Already in a call');
      return null;
    }

    final sodium = SodiumFFI();
    final callId = sodium.randomBytes(16);

    // Generate ephemeral X25519 keypair for call encryption
    final ephKp = sodium.generateX25519KeyPair();

    final session = CallSession(
      callId: callId,
      peerNodeIdHex: peerNodeIdHex,
      direction: CallDirection.outgoing,
      isVideo: video,
      state: CallState.ringing,
    );
    session.ephX25519Pk = ephKp.publicKey;
    session.ephX25519Sk = ephKp.secretKey;

    // ML-KEM-768 encapsulation for post-quantum security
    Uint8List? kemCt;
    final contact = contacts[peerNodeIdHex];
    if (contact?.mlKemPk != null) {
      try {
        final oqs = OqsFFI();
        final kem = oqs.mlKemEncapsulate(contact!.mlKemPk!);
        kemCt = kem.ciphertext;
        session.kemSharedSecret = kem.sharedSecret;
      } catch (e) {
        _log.warn('KEM encapsulation failed: $e');
      }
    }

    _currentCall = session;

    // Send CALL_INVITE with ephemeral public key.
    // TODO(v3-sub-message): use a dedicated `CallInviteV3` proto once that
    // sub-message lands. The V3 wire-format is sub-message-agnostic — the
    // bytes payload is opaque to the codec.
    final invite = proto.CallInvite()
      ..callId = callId
      ..callerEphX25519Pk = ephKp.publicKey
      ..isVideo = video
      ..callerAppMajorMinor = _callerAppMajorMinor
      // ── Format negotiation, the OFFER (§10.3.1/§10.4/§10.6, V1.18,
      // S367) — `media_format_version.dart`'s own file docs: "Pure
      // logic ... The wiring ... belongs to V2.1". Always set, not
      // only for video: every call carries audio, and a callee who
      // does not yet know whether it will be a video call (it reads `is_video`
      // from the same INVITE) needs the video range right along with it anyway.
      ..callerAudioFormatMin = MediaFormatVersion.audio.min
      ..callerAudioFormatMax = MediaFormatVersion.audio.max
      ..callerVideoFormatMin = MediaFormatVersion.video.min
      ..callerVideoFormatMax = MediaFormatVersion.video.max;
    if (kemCt != null) {
      invite.callerKemCiphertext = kemCt;
    }

    // ── PLANE D: COOKIE AND CANDIDATES (§17.3/§17.4) ─────────────────
    //
    // §17.3: "INVITE and ANSWER carry the address candidates of both
    // sides". They must go in HERE and cannot be supplied
    // later: according to §17.2 the INVITE goes out exactly ONCE, there is
    // no repetition into which one could add something.
    //
    // The cookie is likewise drawn now and kept in the session.
    // It is what INCOMING frames of this side will carry
    // — the callee stamps it on everything it sends.
    session.localDCookie = transport.newDCookie();
    invite.callerDCookie = session.localDCookie!;
    final candidates = await transport.localCandidatesPacked();
    if (candidates.isNotEmpty) invite.callerCandidates = candidates;
    _log.info('CALL_INVITE carries ${candidates.length} B of address candidates '
        'and a session cookie (§17.3/§17.4)');

    final inviteBytes = invite.writeToBuffer();
    final recipientId = hexToBytes(peerNodeIdHex);

    // §17.2: NO ringback tone and NO 60 s answer deadline as long as it is not
    // established that it is really ringing at the callee. Both start
    // in [handleCallRingAckV3]. Here only the deadline runs after which the
    // INVITE has expired at the relays anyway.
    session.reaching = true;
    _startReachingTimeout();

    // The send is NOT awaited: `sendToUser` runs the full inner pipeline
    // (KEM + Ed25519 + ML-DSA + PoW — seconds on mobile) followed by the
    // whole L1/L2 route cascade. Blocking on it delayed the call UI by
    // exactly that long. The session already exists in state `ringing`, so
    // the caller can open the call screen immediately; failure surfaces
    // through the ringing timeout / onCallEnded like any unanswered call.
    unawaited(_sendInvite(recipientId, inviteBytes, peerNodeIdHex));

    return session;
  }

  /// The INVITE goes out EXACTLY ONCE (§17.2).
  ///
  /// ── WHY THERE IS NO REPETITION SCHEDULE HERE ANYMORE (S357) ───────────
  ///
  /// §17.2 verbatim: "An INVITE is **placed once**; there is **no
  /// retransmission** — which is why its survival on the recipient's tag
  /// line is a delivery property, not a detail: the 120 s TTL must exceed
  /// the recipient's harvest interval, and the R≈20 redundancy with m=3
  /// (§9) ensures the INVITE is placed even across partly-hostile
  /// relays."
  ///
  /// The reliability thus comes from the REDUNDANCY of the placement, not
  /// from the number of attempts. What stood here until S357 was the
  /// V3 model — "UDP has no delivery guarantee" — and on the
  /// V4.1 line it was harmful for two measured reasons:
  ///
  ///   1. **The cheap branch was dead.** The repetition wanted to
  ///      resend cached fan-out legs. On the
  ///      V4.1 path, however, `CleonaService.sendToUser` returns at the end of the
  ///      V4.1 branch (`cleona_service.dart:9943`), some 280
  ///      lines BEFORE the only place that fills `outLegs`
  ///      (`:10220`). `legs` thus always stayed empty, `reusable` always
  ///      `false` — every repetition took the expensive branch.
  ///   2. **And the expensive branch is a whole Secure placement.** It
  ///      costs `m x R` = `kDeliveryFamilies` x `kResponsibleRelays`
  ///      = 3 x 20 = 60 control frames (`V41Node.placeSecure`), with
  ///      an outflow of one cell per `kSlotInterval` = 8 s. 20
  ///      placements (1 + 19) are 1200 cells = 9600 s of egress for
  ///      ONE call attempt — more than a hundred times what a
  ///      call may ring, and far above the cap of the
  ///      control queue (`kMaxControlBacklog` = 120), at which the rest
  ///      would have been discarded anyway.
  ///
  /// ── AND WHY A `try/catch` STANDS AROUND IT (A-1 class, S357) ──────
  ///
  /// The caller attaches this method with `unawaited(...)` — deliberately,
  /// because the inner pipeline (KEM + Ed25519 + ML-DSA + placement) needs seconds
  /// and the call UI should open immediately. If
  /// `sendViaUser` throws, the returned `Future` then has NO
  /// observer: the throw runs into the zone handler of
  /// `service_daemon.dart` (~L424), and `StateError` is not on
  /// its survival list — `exit(99)`, the whole daemon.
  ///
  /// **This is not a hypothetical throw.** `CleonaService.sendToUser`
  /// throws at this point regularly if `K_AB` cannot be formed
  /// (`v41PairKeyFor`: `StateError('K_AB nicht bildbar')`) — and exactly
  /// that is the state for a contact without founding keys on both sides,
  /// i.e. for a call shortly after the first contact.
  ///
  /// MEASURED before this block existed
  /// (`smoke_call_multi_device_ring.dart`, section 10):
  ///
  ///     "FAIL: CallManager.startCall: ein werfendes sendViaUser entkommt
  ///           nicht — Zonen-Fehler: 1"
  ///
  /// The S352 guard had not covered this path: it sat on the
  /// REPETITION (`resendSignalLeg`), not on the first send.
  /// Here a `try/catch` really does catch — unlike in the case described in
  /// S351, it stands INSIDE the `async` function,
  /// not around its call.
  Future<void> _sendInvite(Uint8List recipientId, Uint8List inviteBytes,
      String peerNodeIdHex) async {
    bool sent;
    try {
      sent = await sendViaUser?.call(
            recipientId,
            proto.MessageTypeV3.MTV3_CALL_INVITE,
            inviteBytes,
          ) ??
          false;
    } catch (e, st) {
      _log.error('CALL_INVITE to ${peerNodeIdHex.substring(0, 8)} threw '
          '(detached): $e\n$st');
      // No abort of its own: the call ends via the regular
      // `reaching` deadline, like every call that reaches nobody.
      return;
    }
    _log.info('CALL_INVITE placed once at '
        '${peerNodeIdHex.substring(0, 8)}: ${sent ? "OK" : "FEHLGESCHLAGEN"} '
        '(§17.2: no repetition — the redundancy lies in the store)');
  }

  /// Accept an incoming call.
  Future<void> acceptCall() async {
    final call = _currentCall;
    if (call == null || call.state != CallState.ringing || call.direction != CallDirection.incoming) {
      return;
    }

    // ── FORMAT NEGOTIATION (§10.3.1/§10.4/§10.6, V1.18, S367) ────────────
    //
    // Before any crypto work: an incompatible format is a reason for
    // rejection, not an occasion to compute KEM/DH first. Audio is
    // mandatory (every call carries audio); video only with `call.isVideo` —
    // an audio call does not negotiate a video range it never uses.
    // `?? Basisformat` covers the edge case named in `peerAudioFormatRange`'s field comment:
    // a session that never came through `handleCallInviteV3`.
    const baseFormat =
        MediaFormatRange(MediaFormatVersion.kBaselineFormat, MediaFormatVersion.kBaselineFormat);
    final audioDecision = MediaFormatVersion.negotiate(
      peer: call.peerAudioFormatRange ?? baseFormat,
      own: MediaFormatVersion.audio,
      kind: 'audio',
    );
    if (!audioDecision.isAgreed) {
      _log.warn('Call rejected — ${audioDecision.detail}');
      await rejectCall(reason: 'incompatible_media_format');
      return;
    }
    MediaFormatDecision? videoDecision;
    if (call.isVideo) {
      videoDecision = MediaFormatVersion.negotiate(
        peer: call.peerVideoFormatRange ?? baseFormat,
        own: MediaFormatVersion.video,
        kind: 'video',
      );
      if (!videoDecision.isAgreed) {
        _log.warn('Call rejected — ${videoDecision.detail}');
        await rejectCall(reason: 'incompatible_media_format');
        return;
      }
    }

    final sodium = SodiumFFI();

    // The ephemeral pair was already drawn while ringing and went out with
    // the RING_ACK (§17.2). Do NOT regenerate it here: the
    // marker must be the same over the whole call — otherwise the
    // caller's CANCEL_OTHERS names a value that this device no longer
    // knows, and the winner would hang up its own call. The branch
    // for `null` is the fallback path in case a call comes here without the
    // INVITE path.
    if (call.ephX25519Pk == null || call.ephX25519Sk == null) {
      final ephKp = sodium.generateX25519KeyPair();
      call.ephX25519Pk = ephKp.publicKey;
      call.ephX25519Sk = ephKp.secretKey;
    }

    // ML-KEM-768 encapsulation (callee → caller's ML-KEM PK)
    Uint8List? kemCt;
    Uint8List? kemSecret;
    final contact = contacts[call.peerNodeIdHex];
    if (contact?.mlKemPk != null) {
      try {
        final oqs = OqsFFI();
        final kem = oqs.mlKemEncapsulate(contact!.mlKemPk!);
        kemCt = kem.ciphertext;
        kemSecret = kem.sharedSecret;
      } catch (e) {
        _log.warn('KEM encapsulation failed: $e');
      }
    }

    // Decapsulate caller's KEM ciphertext
    Uint8List? callerKemSecret;
    if (_callerKemCt != null && _callerKemCt!.isNotEmpty) {
      try {
        final oqs = OqsFFI();
        callerKemSecret = oqs.mlKemDecapsulate(_callerKemCt!, identity.mlKemSecretKey);
      } catch (e) {
        _log.warn('KEM decapsulation failed: $e');
      }
    }

    // Derive shared secret: HKDF-SHA256(DH + KEM) — per CALLS.md spec
    if (_callerEphPk != null) {
      final dhSecret =
          sodium.x25519ScalarMult(call.ephX25519Sk!, _callerEphPk!);
      // IKM: DH secret + KEM secrets (hybrid post-quantum)
      final ikm = <int>[
        ...dhSecret,
        ...?callerKemSecret,
        ...?kemSecret,
      ];
      call.sharedSecret = sodium.hkdfSha256(
        Uint8List.fromList(ikm),
        info: Uint8List.fromList('cleona-call-v1'.codeUnits),
        length: 32,
      );
      _callerEphPk = null;
      _callerKemCt = null;
    }

    call.state = CallState.inCall;
    _cancelRingingTimeout();

    // TODO(v3-sub-message): swap to `CallAnswerV3` once defined.
    final answer = proto.CallAnswer()
      ..callId = call.callId
      ..calleeEphX25519Pk = call.ephX25519Pk!
      // Format negotiation, the RESULT (§10.4, V1.18, S367). Video stays
      // 0 (-> base format at the caller) for an audio call — that is
      // correct, the caller does not check `selected_video_format` at all in that case
      // (`call.isVideo` identical on both sides, from
      // the same INVITE).
      ..selectedAudioFormat = audioDecision.selected;
    if (videoDecision != null) {
      answer.selectedVideoFormat = videoDecision.selected;
    }
    if (kemCt != null) {
      answer.calleeKemCiphertext = kemCt;
    }

    // ── LEVEL D: THE SECOND HALF OF THE EXCHANGE (§17.3/§17.4) ───────
    call.localDCookie = transport.newDCookie();
    answer.calleeDCookie = call.localDCookie!;
    final candidates = await transport.localCandidatesPacked();
    if (candidates.isNotEmpty) answer.calleeCandidates = candidates;

    await sendViaUser?.call(
      hexToBytes(call.peerNodeIdHex),
      proto.MessageTypeV3.MTV3_CALL_ANSWER,
      answer.writeToBuffer(),
    );
    // A-2: the precondition above was checked BEFORE the only `await`, and
    // the send path includes PoW — measured 480 ms (MIGRATION §5.4). In this
    // window an incoming HANGUP, a local rejectCall() or the
    // ringing timeout may have cleared the session. `onCallAccepted` opens
    // microphone and camera; without re-checking that happens for a call
    // that no longer exists. `identical` instead of `==`, because CallSession defines no
    // value comparison and two calls can carry the same callId.
    if (!identical(_currentCall, call) || call.state != CallState.inCall) {
      _log.info('Call torn down during answer send — media not started');
      return;
    }
    onCallAccepted?.call(call);
    _log.info('Call accepted with ${call.peerNodeIdHex.substring(0, 8)}');

    // §17.3: the window runs FROM NOW, on BOTH sides at once —
    // the caller starts its own as soon as it has harvested this ANSWER.
    // Not awaited: it runs up to 30 s, and the call should already look
    // set up during that time (the frames fall to
    // `MediaSendFailure.noPath` until the finding, loudly instead of silently).
    unawaited(_openMediaPath(call));
  }

  /// Runs the punch window from §17.3 for [call].
  ///
  /// **The outcome is HANDLED, not merely logged.** For the case without a common address family,
  /// §17.3 explicitly requires a "clear
  /// message"; a call that rings and then stays silent is exactly
  /// what §17 rules out at this point. If no pair carries,
  /// the call ends with a reason.
  Future<void> _openMediaPath(CallSession call) async {
    final cookieLocal = call.localDCookie;
    final cookieForeign = call.peerDCookie;
    final key = call.sharedSecret;
    if (cookieLocal == null || cookieForeign == null || key == null) {
      call.mediaPathNote = 'The other side named no level-D material '
          '(§17.3/§17.4) — cookie or call_key is missing.';
      _log.warn('Layer D: no punch window for '
          '${call.peerNodeIdHex.substring(0, 8)} — ${call.mediaPathNote}');
      onMediaPathUnavailable?.call(call, call.mediaPathNote!);
      return;
    }
    final PunchOutcome out;
    try {
      out = await transport.openMediaPath(
        peerHex: call.peerNodeIdHex,
        callKey: key,
        localCookie: cookieLocal,
        remoteCookie: cookieForeign,
        peerCandidatesPacked: call.peerCandidates ?? const <int>[],
      );
    } catch (e, st) {
      // A-1 class: the caller attaches this method with `unawaited(...)`.
      // A throw without an observer runs into the zone handler of
      // `service_daemon.dart` and ends the whole daemon.
      _log.error('Layer D: the punch window for '
          '${call.peerNodeIdHex.substring(0, 8)} threw detached: $e\n$st');
      call.mediaPathNote = 'The punch window (§17.3) ended with an '
          'error: $e';
      onMediaPathUnavailable?.call(call, call.mediaPathNote!);
      return;
    }
    if (out.carried) {
      call.mediaPathNote = '${out.address!.address}:${out.port}';
      _log.info('Layer D carries for '
          '${call.peerNodeIdHex.substring(0, 8)}: ${call.mediaPathNote} '
          '(${out.packetsSent} probes / ${out.bytesSent} B, §17.3)');
      return;
    }
    call.mediaPathNote = out.refusal;
    _log.error('Layer D does not carry for '
        '${call.peerNodeIdHex.substring(0, 8)}: ${out.refusal} '
        '(${out.packetsSent} probes / ${out.bytesSent} B)');
    onMediaPathUnavailable?.call(call, out.refusal ?? 'unbekannt');
  }

  /// Reject an incoming call.
  ///
  /// Local-first teardown (see [hangup] for rationale). A reject that
  /// throws on the wire must NOT leave the ringing call object active.
  Future<void> rejectCall({String reason = 'busy'}) async {
    final call = _currentCall;
    if (call == null || call.state != CallState.ringing) return;

    _cancelRingingTimeout();
    call.state = CallState.ended;
    _currentCall = null;
    _unregisterLiveMediaPeer(call);
    // §17.2: the own termination counts just as much as a foreign one. The caller
    // repeats its INVITE every 3 s; without this entry the
    // device rings again fractions of a second after the rejection, because the next
    // repetition was already in transit when the REJECT went out.
    terminatedCalls.record(call.callId);
    _log.info('Call rejected (local teardown done): $reason');

    // Best-effort wire signal — failure does not undo the teardown.
    try {
      // TODO(v3-sub-message): swap to `CallRejectV3` once defined.
      final reject = proto.CallReject()
        ..callId = call.callId
        ..reason = reason;
      await sendViaUser?.call(
        hexToBytes(call.peerNodeIdHex),
        proto.MessageTypeV3.MTV3_CALL_REJECT,
        reject.writeToBuffer(),
      );
    } catch (e) {
      _log.warn('Reject signal send failed (call already torn down locally): $e');
    }

    // A-3: symmetry with hangup() and handleCallRejectV3 — EVERY teardown path
    // reports the termination to the outside. rejectCall was the only one without
    // a callback; ringtone, voice/video engine and the telecom connection
    // kept running afterwards. Consequential above all because _startRingingTimeout
    // itself calls rejectCall(reason: 'timeout') after 60 s — an unanswered
    // incoming call thus rang indefinitely.
    //
    // `onCallEnded` and not `onCallRejected`: both consumers in
    // call_service.dart clean up identically, but for the user the timeout case
    // is an ended call, not a rejected one.
    //
    // After the try/catch, because the local teardown is already complete
    // and the report must not depend on whether the REJECT reached the line.
    // No double fire: the guard above (state != ringing)
    // and `_currentCall = null` make every second call a no-op.
    onCallEnded?.call(call);
  }

  /// Hang up an active call.
  ///
  /// The cleanup order is deliberately local-first:
  /// 1) Tear down the local call state (state=ended, _currentCall=null,
  ///    onCallEnded → CleonaService stops the audio engine).
  /// 2) AFTER that, send CALL_HANGUP to the other side on a best-effort basis.
  ///
  /// So the call does NOT stay stuck "active" locally if `sendViaUser`
  /// throws, hangs or the multi-identity wiring drops the send
  /// (`sendToUser` returns `false` on senderUserId mismatch). From
  /// the user's point of view "hangup" is a local act; the network signal to
  /// the other side is politeness. Without this order
  /// `_currentCall` can stay `!= null` after `hangup()` (B-7,
  /// test gui-33-video-calls 33.10).
  Future<void> hangup() async {
    final call = _currentCall;
    if (call == null) return;

    _cancelRingingTimeout();
    call.state = CallState.ended;
    onCallEnded?.call(call);
    _currentCall = null;
    _unregisterLiveMediaPeer(call);
    terminatedCalls.record(call.callId);
    _log.info('Call ended (local teardown done)');

    // Best-effort signal to the remote side. Failures here do not undo
    // the local teardown above.
    try {
      // TODO(v3-sub-message): swap to `CallHangupV3` once defined.
      final hangup = proto.CallHangup()..callId = call.callId;
      await sendViaUser?.call(
        hexToBytes(call.peerNodeIdHex),
        proto.MessageTypeV3.MTV3_CALL_HANGUP,
        hangup.writeToBuffer(),
      );
    } catch (e) {
      _log.warn('Hangup signal send failed (call already torn down locally): $e');
    }
  }

  // ── Incoming message handling (V3 — called from CleonaService) ──
  //
  // V3 receive-side handlers take an `ApplicationFrameV3` (whose
  // `payload` is the already-decrypted + user-sig-verified inner
  // proto-bytes) plus the wire-level `senderDeviceId` from
  // `NetworkPacketV3`, plus the `SenderIdentitySnapshot` produced by
  // §2.4 [4] outer-sig-verify.

  /// V3: handle inbound CALL_INVITE.
  ///
  /// `frame.senderUserId` is the inviter's user-id (== `peerNodeIdHex`
  /// for 1:1 calls in the current build). `senderDeviceId` is the
  /// concrete device that sent the invite — used by the busy auto-reject
  /// path.
  /// Returns `true` if this INVITE created a **new ringing call**.
  ///
  /// A-4: The caller hangs the ringtone on this. The method used to be
  /// `void` and the caller assumed an INVITE always meant "it
  /// is ringing now". Two outcomes disprove that — the repetition
  /// of the same INVITE (the sender repeats every 3 s) and the
  /// busy rejection. In both cases nothing may ring.
  bool handleCallInviteV3(HarvestEvent event) {
    final proto.CallInvite invite;
    try {
      invite = proto.CallInvite.fromBuffer(event.payload);
    } catch (e) {
      // The same buffer used to be parsed twice, both times without
      // safeguard. A malformed INVITE thus flew as an exception out of
      // the handler into the receive path. A parse error is not a ringing
      // call — this outcome says no more than that.
      _log.warn('CALL_INVITE V3: payload parse failed: $e');
      return false;
    }
    final invitedCallId = Uint8List.fromList(invite.callId);

    // §17.2: "completed `callId`s are remembered for 24 h (late duplicates
    // are no-ops)." Two real cases, not a theoretical one: the caller's 19
    // INVITE repetitions overtake every teardown, and on
    // the harvest tag INVITE and CANCEL_OTHERS lie side by side without guaranteed
    // order (§8: the device pulls its tag at its
    // own pace).
    if (terminatedCalls.isTerminated(invitedCallId)) {
      _log.debug('INVITE for a call that has already ended '
          '(${bytesToHex(invitedCallId).substring(0, 8)}) — no ringing');
      return false;
    }

    if (_currentCall != null) {
      if (_callIdMatches(_currentCall!.callId, invite.callId)) {
        _log.debug('Duplicate INVITE for current call — ignoring');
        return false;
      }
      _sendRejectV3(event, 'busy');
      return false;
    }

    final senderHex = bytesToHex(Uint8List.fromList(event.senderUserId));

    if (invite.callerEphX25519Pk.isNotEmpty) {
      _callerEphPk = Uint8List.fromList(invite.callerEphX25519Pk);
    }
    if (invite.callerKemCiphertext.isNotEmpty) {
      _callerKemCt = Uint8List.fromList(invite.callerKemCiphertext);
    }

    final session = CallSession(
      callId: Uint8List.fromList(invite.callId),
      peerNodeIdHex: senderHex,
      direction: CallDirection.incoming,
      isVideo: invite.isVideo,
      state: CallState.ringing,
    );
    _currentCall = session;

    // ── FORMAT NEGOTIATION: WHAT THE CALLER OFFERS (§10.3.1/§10.4/§10.6,
    // V1.18, S367) ────────────────────────────────────────────────────
    //
    // Only record, do not evaluate — just like for Plane D below:
    // evaluation only happens on pick-up (`acceptCall`,
    // `MediaFormatVersion.negotiate`). Always set (not behind an
    // `isNotEmpty` guard like the bytes fields below): 0/0 is a
    // VALID wire value with its own meaning here
    // (`MediaFormatVersion.rangeFromWire` normalises it to the
    // base format [1,1], see its file docs "A MISSING FIELD IS
    // A STATEMENT").
    session.peerAudioFormatRange = MediaFormatVersion.rangeFromWire(
        invite.callerAudioFormatMin, invite.callerAudioFormatMax);
    session.peerVideoFormatRange = MediaFormatVersion.rangeFromWire(
        invite.callerVideoFormatMin, invite.callerVideoFormatMax);

    // ── PLANE D: WHAT THE CALLER NAMED (§17.3/§17.4) ───────────
    //
    // Only record, do not evaluate. Evaluation happens on pick-up
    // ([acceptCall]) — before that there is no `call_key` under which a
    // probe could be authenticated, and a window without a key
    // would be 30 s of traffic without any effect.
    //
    // Empty fields are a STATEMENT (proto3 delivers empty bytes): the
    // caller named none, so none is started either.
    if (invite.callerDCookie.isNotEmpty) {
      session.peerDCookie = Uint8List.fromList(invite.callerDCookie);
    }
    if (invite.callerCandidates.isNotEmpty) {
      session.peerCandidates = Uint8List.fromList(invite.callerCandidates);
    }

    // The V3 admission (PoW exemption list, §13.1.2 exemption 4) fell with the
    // CUT. §17.4 replaces it completely: "the D socket responds
    // **exclusively** to packets with a valid AEAD under `call_key` plus a
    // session cookie … Whoever does not have the `call_key` from signaling
    // does not exist for the socket." There is nothing left to register here.
    //
    // The field stays and stays `null` (B-32): §14.2 gives delivery
    // no device level, `HarvestEvent.senderDeviceId` is always `null` on the
    // V4.1 path. No substitute value.
    session.peerDeviceId = event.senderDeviceId;

    _startRingingTimeout();

    // §17.2 RING_ACK: "it really is ringing on their end". Until here the caller stands
    // on `reaching` and hears NOTHING; only this cell starts
    // the ringback tone and answer deadline at its end.
    //
    // The ephemeral key pair is drawn NOW and not only in
    // [acceptCall]: the RING_ACK must already carry the marker, and there should be
    // ONE marker over the whole call — the same one that later goes out as
    // `CallAnswer.callee_eph_x25519_pk` and that CANCEL_OTHERS
    // names. Two separate markers would be two things that can diverge.
    // A device that rings and never picks up has then generated a
    // key pair and never used it — the price of one X25519
    // generation, against a cell that says nothing without a marker.
    final ringKp = SodiumFFI().generateX25519KeyPair();
    session.ephX25519Pk = ringKp.publicKey;
    session.ephX25519Sk = ringKp.secretKey;
    unawaited(_sendRingAck(session));

    onIncomingCall?.call(session);
    _log.info(
        'V3 incoming ${invite.isVideo ? "video" : "audio"} call from ${senderHex.substring(0, 8)}');
    return true;
  }

  /// RING_ACK (§17.2) to the IDENTITY of the caller.
  ///
  /// One cell per ringing device — unlike CANCEL_OTHERS this is
  /// not a fan-out that could be saved: the statement "it is ringing
  /// at MY end" can only be made by the ringing device itself. §17.2
  /// explicitly reckons with several ("all of the callee's devices …
  /// ring. `RING_ACK` carries the `deviceId`").
  ///
  /// Best effort: if it is lost, the caller stays on `reaching` until
  /// the deadline from [reachingTimeoutSec] runs out. That is the safe
  /// direction — a ringback tone without ringing would be exactly the deception
  /// that §17.2 rules out.
  Future<void> _sendRingAck(CallSession call) async {
    final marker = call.ephX25519Pk;
    if (marker == null) return;
    try {
      final ack = proto.CallRingAck()
        ..callId = call.callId
        ..deviceMarker = marker;
      await sendViaUser?.call(
        hexToBytes(call.peerNodeIdHex),
        proto.MessageTypeV3.MTV3_CALL_RING_ACK,
        ack.writeToBuffer(),
      );
      _log.info('RING_ACK to ${call.peerNodeIdHex.substring(0, 8)} — the '
          'caller may now hear a ringback tone');
    } catch (e) {
      _log.warn('RING_ACK could not be sent: $e');
    }
  }

  /// V3: handle inbound CALL_ANSWER.
  ///
  /// **Here the arbitration between several devices of the callee happens**
  /// (§17.2: "the first `ANSWER` binds the session to one device").
  /// Detailed rationale in `call_arbitration.dart`; the three rules
  /// in the body are:
  ///
  ///   1. Only the CALLER evaluates an ANSWER. A device that is itself the
  ///      callee must never apply an ANSWER to its own call
  ///      — §14.2 lets every cell addressed to the identity arrive at
  ///      EVERY device, so every handler must check the direction
  ///      instead of assuming it.
  ///   2. The first ANSWER binds. Every further one leaves the negotiated
  ///      session key untouched.
  ///   3. After binding, ONE CANCEL_OTHERS cell goes to the identity
  ///      of the callee; it reaches all remaining devices at once
  ///      (§14.2 — one delivery, not N).
  void handleCallAnswerV3(HarvestEvent event) {
    final answer = proto.CallAnswer.fromBuffer(event.payload);
    final call = _currentCall;
    if (call == null || !_callIdMatches(call.callId, answer.callId)) return;

    // Rule 1. This check used to be missing; it costs nothing and closes
    // the whole class of error "addressed to the identity, so arrived at all
    // devices" for this handler.
    if (call.direction != CallDirection.outgoing) {
      _log.debug('CALL_ANSWER on a call in which we ourselves are the '
          'callee — ignored');
      return;
    }

    final answerKey = answer.calleeEphX25519Pk.isEmpty
        ? null
        : Uint8List.fromList(answer.calleeEphX25519Pk);

    // Rule 2. The race: two devices of the callee pick up so close
    // together that both ANSWERs are in transit. At the caller
    // they arrive ONE AFTER THE OTHER — it is the only point in the system at
    // which the two events have an order, and thus the
    // only possible arbiter. The one processed first wins.
    //
    // Without this lock the second ANSWER would re-derive the session key
    // (`call.sharedSecret` further below) — the caller would then have
    // the key of device B while device A sends. A
    // conversation without sound, without an error message.
    if (call.answerBound) {
      final bound = call.boundAnswerKey;
      if (bound != null && CancelOthers.namesUs(answerKey, bound)) {
        // The same ANSWER a second time — a repetition on the
        // line, not a second device. No CANCEL_OTHERS needed.
        _log.debug('Wiederholte ANSWER desselben Geraets — ignoriert');
        return;
      }
      _log.info('Second ANSWER for the same call — the session stays with the '
          'device that answered first, CANCEL_OTHERS is repeated');
      // Repeated and not kept quiet: that a second ANSWER arrives
      // is the evidence that the first CANCEL_OTHERS has not
      // (or not yet) reached the device. One cell, not N — and only in the
      // race case.
      unawaited(_sendCancelOthers(call));
      return;
    }

    if (call.ephX25519Sk != null && answer.calleeEphX25519Pk.isNotEmpty) {
      final sodium = SodiumFFI();
      final calleePk = Uint8List.fromList(answer.calleeEphX25519Pk);
      final dhSecret = sodium.x25519ScalarMult(call.ephX25519Sk!, calleePk);

      Uint8List? calleeKemSecret;
      if (answer.calleeKemCiphertext.isNotEmpty) {
        try {
          final oqs = OqsFFI();
          calleeKemSecret = oqs.mlKemDecapsulate(
            Uint8List.fromList(answer.calleeKemCiphertext),
            identity.mlKemSecretKey,
          );
        } catch (e) {
          _log.warn('KEM decapsulation failed: $e');
        }
      }

      final ikm = <int>[
        ...dhSecret,
        ...?call.kemSharedSecret,
        ...?calleeKemSecret,
      ];
      call.sharedSecret = sodium.hkdfSha256(
        Uint8List.fromList(ikm),
        info: Uint8List.fromList('cleona-call-v1'.codeUnits),
        length: 32,
      );
    }

    // Pin live media to the answering device and allowlist it for PoW-less
    // frames (§13.1.2 exemption #4, §10.3) — the caller learns the callee's
    // concrete device id only now (CALL_INVITE fan-out went to every
    // authorized device of the peer user; only one answers).
    //
    // B-32: On the V4.1 path the identifier is `null` (§14.2). The binding to
    // "exactly this device" is achieved there by the `call_key` (§17.4), not by a
    // list (§17.4).
    call.peerDeviceId = event.senderDeviceId;

    _cancelRingingTimeout();
    call.state = CallState.inCall;

    // Rule 2/3: from here on the session is bound. `answerBound` is set even
    // if no ephemeral key came along — otherwise a
    // second ANSWER could still overwrite the session key after all.
    call.answerBound = true;
    call.boundAnswerKey = answerKey;

    // ── FORMAT NEGOTIATION, CHECKING THE COUNTER-CHOICE (§10.4, V1.18, S367) ──
    //
    // `MediaFormatVersion.verifySelection`'s own file docs: "A
    // defective or malicious peer can thus not force a format that
    // we never offered — not even if we could
    // speak it in principle." `own` and `offered` are always
    // the same range here: in `startCall` the caller always offers its
    // full `MediaFormatVersion.audio`/`.video`, there is no
    // narrower subset that would be "offered but not spoken".
    final audioVerify = MediaFormatVersion.verifySelection(
      wireSelected: answer.selectedAudioFormat,
      own: MediaFormatVersion.audio,
      offered: MediaFormatVersion.audio,
    );
    var formatOk = audioVerify.isAgreed;
    if (!formatOk) {
      _log.warn('CALL_ANSWER: ${audioVerify.detail} — call is being ended');
    } else if (call.isVideo) {
      final videoVerify = MediaFormatVersion.verifySelection(
        wireSelected: answer.selectedVideoFormat,
        own: MediaFormatVersion.video,
        offered: MediaFormatVersion.video,
      );
      formatOk = videoVerify.isAgreed;
      if (!formatOk) {
        _log.warn('CALL_ANSWER: ${videoVerify.detail} — call is being ended');
      }
    }
    if (!formatOk) {
      unawaited(hangup());
      return;
    }

    // ── PLANE D: WHAT THE CALLEE NAMED (§17.3/§17.4) ────────
    //
    // ONLY HERE, not further up: only the BINDING ANSWER may deposit its
    // cookie. A second ANSWER (second device, race)
    // already returns above — it must not redirect the media path to a
    // device whose call is about to end via CANCEL_OTHERS.
    if (answer.calleeDCookie.isNotEmpty) {
      call.peerDCookie = Uint8List.fromList(answer.calleeDCookie);
    }
    if (answer.calleeCandidates.isNotEmpty) {
      call.peerCandidates = Uint8List.fromList(answer.calleeCandidates);
    }

    onCallAccepted?.call(call);
    _log.info('V3 call answered by ${call.peerNodeIdHex.substring(0, 8)}');

    unawaited(_sendCancelOthers(call));
    // §17.3: both sides start at the same time — the callee with
    // sending its ANSWER, the caller with harvesting it.
    unawaited(_openMediaPath(call));
  }

  /// CANCEL_OTHERS (§17.2) to the IDENTITY of the callee.
  ///
  /// ONE cell for all remaining devices — §14.2: "One delivery
  /// serves all devices." The caller deliberately does not iterate over devices;
  /// it does not know them and need not know them (§14.1).
  ///
  /// The carrier is the own type `MTV3_CALL_CANCEL_OTHERS` (88) with the
  /// payload `CallCancelOthers`. Before, the arbitration piggybacked on
  /// `MTV3_CALL_REJECT`; why it no longer does so and why the old
  /// piggyback path is nevertheless understood on RECEIPT is stated in
  /// `call_arbitration.dart`.
  Future<void> _sendCancelOthers(CallSession call) async {
    final boundKey = call.boundAnswerKey;
    if (boundKey == null) {
      // Without an ephemeral key there is no value by which the
      // picking-up device could recognise itself — a CANCEL_OTHERS
      // would then ALSO make the winning device hang up. Better that
      // a sibling device keeps ringing than that the running
      // conversation breaks off.
      _log.warn('CANCEL_OTHERS skipped: the binding ANSWER carried no '
          'ephemeral key');
      return;
    }
    try {
      final cancel = proto.CallCancelOthers()
        ..callId = call.callId
        ..boundAnswerKey = boundKey;
      await sendViaUser?.call(
        hexToBytes(call.peerNodeIdHex),
        proto.MessageTypeV3.MTV3_CALL_CANCEL_OTHERS,
        cancel.writeToBuffer(),
      );
      _log.info('CANCEL_OTHERS sent to '
          '${call.peerNodeIdHex.substring(0, 8)} — the ringing on the '
          'other devices ends');
    } catch (e) {
      // Best effort like every other signal: the call runs, the ringing
      // of the siblings ends at the latest with their 60 s time limit.
      _log.warn('CANCEL_OTHERS could not be sent: $e');
    }
  }

  /// V3: handle inbound CALL_RING_ACK (§17.2).
  ///
  /// §17.2, lines 5409-5413: "After placing the INVITE, the caller shows
  /// ,reaching …' — **no** ringtone. Ringtone and the 60-s answer timeout
  /// start only once the callee's `RING_ACK` cell has been harvested (,it
  /// really is ringing on their end'). This means there is no fake ringing
  /// against a device that was never reached."
  ///
  /// The FIRST harvested RING_ACK triggers the transition. Every further one
  /// only adds a device to the count: the INVITE is ONE cell to the
  /// identity and makes all devices ring (§14.2), so the acknowledgement
  /// comes N-fold. A second ringback tone start would be audible.
  ///
  /// Only at the CALLER. A RING_ACK that arrives at a callee
  /// is that of a sibling device harvesting the same tag (§14.2) —
  /// it tells it nothing it does not already know.
  void handleCallRingAckV3(HarvestEvent event) {
    final proto.CallRingAck ack;
    try {
      ack = proto.CallRingAck.fromBuffer(event.payload);
    } catch (e) {
      _log.warn('CALL_RING_ACK: payload not readable: $e');
      return;
    }
    final call = _currentCall;
    if (call == null || !_callIdMatches(call.callId, ack.callId)) return;
    if (call.direction != CallDirection.outgoing) {
      _log.debug('CALL_RING_ACK on a call in which we ourselves are the '
          'callee — ignored');
      return;
    }
    if (call.state != CallState.ringing) return;

    // Without a marker nothing can be counted, but the statement "it is ringing"
    // still stands. The transition depends on the statement, not on the
    // marker.
    final marker = ack.deviceMarker.isEmpty
        ? null
        : bytesToHex(Uint8List.fromList(ack.deviceMarker));
    if (marker != null && !call.ringingDeviceMarkers.add(marker)) {
      // The same cell harvested a second time — no further device.
      return;
    }

    if (!call.reaching) {
      _log.debug('Further RING_ACK — now ringing on '
          '${call.ringingDeviceMarkers.length} devices');
      return;
    }

    call.reaching = false;
    _cancelReachingTimeout();
    // §17.2: NOW — and not a second earlier — ringback tone and
    // answer deadline begin.
    _startRingingTimeout();
    onRemoteRinging?.call(call);
    _log.info('RING_ACK collected from ${call.peerNodeIdHex.substring(0, 8)} — '
        'it is really ringing; ringback tone and '
        '${ringingTimeoutSec}s answer deadline start');
  }

  /// V3: handle inbound CALL_CANCEL_OTHERS (§17.2) — the own type.
  ///
  /// The body does nothing but unpack and check; the arbitration
  /// itself is in [_handleCancelOthers] and is the same for both
  /// carriers.
  ///
  /// Two checks, and both are necessary because the value comes from outside:
  ///
  ///   * **Parsing can fail.** A malformed buffer must not carry an
  ///     exception out of the receive path — every other call handler
  ///     catches here likewise.
  ///   * **An empty binding key or one of the wrong length is
  ///     discarded.** Without it the winning device could not
  ///     recognise itself, and the cell would take away its own call.
  ///     Discarding is the safe direction: in the worst case
  ///     a sibling device keeps ringing until its 60 s time limit, instead of
  ///     a running conversation breaking off.
  void handleCallCancelOthersV3(HarvestEvent event) {
    final proto.CallCancelOthers cancel;
    try {
      cancel = proto.CallCancelOthers.fromBuffer(event.payload);
    } catch (e) {
      _log.warn('CALL_CANCEL_OTHERS: payload not readable: $e');
      return;
    }
    if (cancel.boundAnswerKey.length != CancelOthers.boundKeyLength) {
      _log.warn('CALL_CANCEL_OTHERS without a usable binding key '
          '(${cancel.boundAnswerKey.length} instead of '
          '${CancelOthers.boundKeyLength} bytes) — discarded');
      return;
    }
    _handleCancelOthers(Uint8List.fromList(cancel.callId),
        Uint8List.fromList(cancel.boundAnswerKey));
  }

  /// V3: handle inbound CALL_REJECT — **and the OLD CANCEL_OTHERS piggyback path**
  /// (§17.2).
  ///
  /// The piggyback path is no longer sent (that is done by
  /// [handleCallCancelOthersV3]'s counterpart `_sendCancelOthers` via
  /// `MTV3_CALL_CANCEL_OTHERS`). It is still understood, so that a
  /// second own device with the old state can still pronounce the arbitration.
  /// [CancelOthers.tryDecode] separates strictly; anything that
  /// does not fit exactly is an ordinary rejection. Rationale:
  /// `call_arbitration.dart`, section "Backward compatibility".
  void handleCallRejectV3(HarvestEvent event) {
    final reject = proto.CallReject.fromBuffer(event.payload);
    final rejectedCallId = Uint8List.fromList(reject.callId);

    // Old piggyback path, receive direction only (see method header).
    final boundKey = CancelOthers.tryDecode(reject.reason);
    if (boundKey != null) {
      _handleCancelOthers(rejectedCallId, boundKey);
      return;
    }

    final call = _currentCall;
    if (call == null || !_callIdMatches(call.callId, reject.callId)) {
      // §17.2: "terminal types (`REJECT`, `HANGUP`) dominate any later
      // out-of-order arrival." A rejection harvested BEFORE the corresponding INVITE
      // used to vanish without effect — and the INVITE afterwards
      // made the device ring. Recording it costs one map entry.
      terminatedCalls.record(rejectedCallId);
      return;
    }

    // The rejection of a SECOND device after a first one has already picked
    // up. The case is not constructed: the INVITE makes all devices
    // ring (§14.2); if one picks up, the others are still ringing
    // until CANCEL_OTHERS reaches them. If in this window someone on the
    // laptop presses "reject", its rejection goes to us.
    //
    // Without this guard it would end the RUNNING conversation with the
    // phone — and on top of that send an abort to all devices of the
    // callee. The §17.2 rule "terminal types dominate" means the
    // reordering of messages from ONE remote side, not the rejection of one
    // device against the acceptance of another: the call is already
    // bound, and binding happens exactly once.
    //
    // No additional CANCEL_OTHERS as a response: the rejecting device
    // has already cleaned itself up with its rejection (`rejectCall`
    // cleans up locally first).
    if (call.direction == CallDirection.outgoing && call.answerBound) {
      _log.info('Decline from a second device after the call is already '
          'bound — ignored, the conversation continues');
      return;
    }

    _cancelRingingTimeout();
    call.state = CallState.ended;
    terminatedCalls.record(call.callId);
    onCallRejected?.call(call, reject.reason);
    _currentCall = null;
    _unregisterLiveMediaPeer(call);
    _log.info('V3 call rejected: ${reject.reason}');

    // The rejection came from ONE device of the callee — the others
    // keep ringing. They only learn of it via us: the rejection went to
    // OUR tag, not to theirs (§14.2 — every device harvests the tag
    // of its own identity).
    //
    // The carrier is CALL_HANGUP and not CANCEL_OTHERS: here there is no
    // winner to spare, the call is over for the whole identity.
    // §17.2: "terminal types (`REJECT`, `HANGUP`) dominate any later
    // out-of-order arrival."
    //
    // Only as the caller. A rejection that arrives at a callee is
    // nothing to which it would be allowed to respond with an abort to the other side.
    if (call.direction == CallDirection.outgoing) {
      unawaited(_sendHangupToPeer(call, 'Declined by a device'));
    }
  }

  /// CALL_HANGUP to the IDENTITY of the other side — one cell, all devices.
  ///
  /// A side effect that counts: without this path, for an
  /// unanswered call ALL devices of the callee would send their
  /// own 'timeout' rejection after 60 s (each considers itself the only one). With it
  /// the first rejection ends the ringing everywhere, and it stays at
  /// one rejection plus one abort.
  Future<void> _sendHangupToPeer(CallSession call, String why) async {
    try {
      final hangup = proto.CallHangup()..callId = call.callId;
      await sendViaUser?.call(
        hexToBytes(call.peerNodeIdHex),
        proto.MessageTypeV3.MTV3_CALL_HANGUP,
        hangup.writeToBuffer(),
      );
      _log.info('CALL_HANGUP to ${call.peerNodeIdHex.substring(0, 8)} '
          '($why) — the ringing on the other devices ends');
    } catch (e) {
      _log.warn('CALL_HANGUP ($why) could not be sent: $e');
    }
  }

  /// CANCEL_OTHERS on the callee's side (§17.2).
  ///
  /// Three outcomes, and the middle one is the one everything hinges on:
  ///
  ///   * **No matching call** — the cell was harvested before the INVITE
  ///     or the device cleaned up long ago. Record it, so that a
  ///     subsequent INVITE does not ring after all.
  ///   * **We are the picking-up device** — the named key is
  ///     our own. Do nothing. Without this branch the device that
  ///     has just picked up would hang up its own call: the cell goes to
  ///     the IDENTITY and therefore also reaches the winner (§14.2).
  ///   * **We are not** — end the ringing. Even if this
  ///     device itself has just picked up (race): the caller has
  ///     decided, and it is the only one that can decide.
  void _handleCancelOthers(Uint8List callId, Uint8List boundKey) {
    final call = _currentCall;
    if (call == null || !_callIdMatches(call.callId, callId)) {
      terminatedCalls.record(callId);
      _log.debug('CANCEL_OTHERS for a call not (or no longer) running here '
          '(${bytesToHex(callId).substring(0, 8)}) — noted');
      return;
    }

    if (call.direction != CallDirection.incoming) {
      // At the caller CANCEL_OTHERS makes no sense — it is the sender.
      _log.debug('CANCEL_OTHERS on an outgoing call — ignored');
      return;
    }

    if (CancelOthers.namesUs(call.ephX25519Pk, boundKey)) {
      _log.info('CANCEL_OTHERS names our own ephemeral key — '
          'this device holds the conversation, nothing to do');
      return;
    }

    _cancelRingingTimeout();
    call.state = CallState.ended;
    terminatedCalls.record(call.callId);
    _currentCall = null;
    _unregisterLiveMediaPeer(call);
    // `onCallEnded` and not `onCallRejected`: for the user the call was
    // not rejected, it is being taken next door. The same distinction
    // as for A-3 (a time limit is an ended call, not a rejected one).
    // Both consumers in `call_service.dart` clean up identically, the
    // difference is the meaning.
    onCallEnded?.call(call);
    _log.info('Call accepted on another own device — ringing '
        'ended here (§17.2 CANCEL_OTHERS)');
  }

  /// V3: handle inbound CALL_HANGUP.
  void handleCallHangupV3(HarvestEvent event) {
    final hangup = proto.CallHangup.fromBuffer(event.payload);
    final call = _currentCall;
    if (call == null || !_callIdMatches(call.callId, hangup.callId)) {
      // §17.2, as with REJECT: the abort dominates a later arriving
      // INVITE. If the caller gives up while one of its 19
      // INVITE repetition packets is still in transit, it would otherwise
      // start ringing AFTER the abort.
      terminatedCalls.record(Uint8List.fromList(hangup.callId));
      return;
    }

    _cancelRingingTimeout();
    call.state = CallState.ended;
    terminatedCalls.record(call.callId);
    onCallEnded?.call(call);
    _currentCall = null;
    _unregisterLiveMediaPeer(call);
    _log.info('V3 call hung up by remote');
  }

  /// Clear the Plane D session of this call (§17.4).
  ///
  /// Until the CUT this held the revocation of the V3 PoW exemption list
  /// (the PoW exemption list). The list no longer exists — §17.4
  /// binds admission to `call_key` plus session cookie, and what
  /// is to be revoked is consequently the SESSION. Must run on **every**
  /// teardown path; the five call sites are exactly the five
  /// that cleared the list before.
  void _unregisterLiveMediaPeer(CallSession call) {
    transport.forgetParticipant(call.peerNodeIdHex);
    call.peerDeviceId = null;
  }

  /// Busy rejection of an INVITE that is not accepted (§17.2).
  ///
  /// **An ordinary 1:1 cell under the pair tag**, to the USER.
  /// Until the CUT a case distinction stood here: if a
  /// `senderDeviceId` came with the INVITE, the rejection went device-addressed
  /// (via a device-addressed operation), otherwise to the user. The
  /// device-bound
  /// branch was dead on the V4.1 path — §14.2 gives delivery no
  /// device level, `HarvestEvent.senderDeviceId` is always `null` there —
  /// and it fell with the operation. What remains is the path that
  /// §17.2 provides anyway.
  void _sendRejectV3(HarvestEvent event, String reason) {
    try {
      final invite = proto.CallInvite.fromBuffer(event.payload);
      final senderUserId = Uint8List.fromList(event.senderUserId);

      final reject = proto.CallReject()
        ..callId = invite.callId
        ..reason = reason;

      // A-1 (S352): `transport.sendSignal` passes straight through to `sendViaUser`
      // (== `CleonaService.sendToUser`) — whose own docs state
      // that it CAN throw. The surrounding `try` of this function is
      // synchronous and never catches the throw of an `async` function; without
      // `.catchError` this would be the `exit(99)` trap from
      // `service_daemon.dart`'s zone handler.
      transport
          .sendSignal(
            recipientUserId: senderUserId,
            type: proto.MessageTypeV3.MTV3_CALL_REJECT,
            payload: reject.writeToBuffer(),
          )
          .catchError((Object e, StackTrace st) {
        _log.error('Busy rejection threw (detached): $e\n$st');
        return false;
      });
    } catch (e) {
      _log.debug('Busy decline could not be built: $e');
    }
  }

  // ── Ringing Timeout ─────────────────────────────────────────────

  /// §17.2: deadline for `reaching` — runs until a RING_ACK has been harvested.
  ///
  /// If it expires, not a single device of the callee was reached.
  /// For the caller that is an ended call like every unanswered one;
  /// §17.2, lines 5431-5434 provides for the follow-up as an ordinary
  /// cell ("the caller's `reaching` cancellation can be followed up as
  /// a normal cell (,missed call')") — that lies in the service layer, not
  /// here.
  void _startReachingTimeout() {
    _cancelReachingTimeout();
    _reachingTimeout = Timer(Duration(seconds: reachingTimeoutSec), () {
      final call = _currentCall;
      if (call == null || !call.reaching) return;
      _log.info('No RING_ACK within ${reachingTimeoutSec}s — no device '
          'of the callee was reached (§17.2 TTL class), hanging up');
      hangup();
    });
  }

  void _cancelReachingTimeout() {
    _reachingTimeout?.cancel();
    _reachingTimeout = null;
  }

  void _startRingingTimeout() {
    _cancelRingingTimeout();
    _ringingTimeout = Timer(Duration(seconds: ringingTimeoutSec), () {
      final call = _currentCall;
      if (call == null || call.state != CallState.ringing) return;

      _log.info('Ringing timeout (${ringingTimeoutSec}s) — auto-hangup');
      if (call.direction == CallDirection.outgoing) {
        hangup();
      } else {
        rejectCall(reason: 'timeout');
      }
    });
  }

  void _cancelRingingTimeout() {
    _ringingTimeout?.cancel();
    _ringingTimeout = null;
    // The `reaching` deadline is attached here too: both are "wait for this
    // call". Here and not at each of the eight cleanup places — otherwise
    // the timer would survive exactly the place one forgets, and hang up
    // a call that no longer exists seconds later.
    //
    // A THIRD TIMER STOOD HERE UNTIL S357: the repetition schedule of the
    // INVITE. It was dropped without replacement with §17.2 (see [_sendInvite]);
    // so there is nothing left to clear.
    _cancelReachingTimeout();
  }

  bool _callIdMatches(Uint8List a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
