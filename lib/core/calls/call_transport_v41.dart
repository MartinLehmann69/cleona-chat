// The Plane D implementation on `link_io/d_socket.dart` (§17.1/§17.3/
// §17.4). It replaces `call_transport_v3.dart`, which fell with the CUT on
// 2026-08-31 together with the whole V3 transport.
//
// ══ WHAT CARRIES HERE AND WHAT DOES NOT — read before the first call ═══════
//
// **Carries:** sealing and sending a D frame over an
// admitted session, taking in arriving frames, the
// signaling via the delivery layer, the cleanup.
//
// **SINCE S361 it also carries the path by which a session comes into being in operation**
// (§17.3): [openMediaPath] admits the session and runs the
// punch window against the candidates that INVITE/ANSWER carried.
//
// The sentence that stood here until S361 read: "there is nobody in `lib/`
// who ADMITS a session. [admitSession] is built and waits for its
// caller". That was true and was the SECOND of the two reasons for which
// a call was rejected. It stays as a correction instead of
// disappearing — an outdated status line that silently goes away
// is the mistake this project has made twice.
//
// **What is STILL MISSING, named instead of kept quiet:** the 10 s loss rule
// from §17.4 ("10 s without valid media frames end the session") has a
// reader for `DSession.lastFrameAt`, but no timer — [onMediaPathLost]
// still has no trigger in `lib/` to this day. And the media relay from §17.3
// ("media-relay opt-in via a dual-stack volunteer") is not built: if
// no pair carries, the answer is the honest refusal of the spec, not a
// detour.
//
// ══ TWO SEAMS OUTSIDE THIS FILE ══════════════════════════════
//
// 1. **The D socket is registered — since S360 (01.09.2026).** Until then
//    this said: `LinkDemux.dAdmission` (`link_demux.dart:284`) was set
//    NOWHERE in `lib/`, the only setting place in the tree being
//    `test/smoke/smoke_d_frame.dart:320`. That was true and was the first
//    of two reasons for which a call was rejected. It has now been built
//    by the node start: `V41Node.start` creates the cookie table
//    and hangs `dSocket.claim` into the demux, `attachV41` passes it
//    via `CleonaService.attachCallPlaneD` on to [attachPlaneD].
//    The sentence stays as a correction instead of disappearing — an
//    outdated status line that silently goes away is the mistake
//    this project has made twice.
//    Since S361 `attachV41` no longer passes just the socket, but
//    [CallPlaneD] — socket, own data port and the §17.3 address mirror.
//    The three come from the same node and therefore go as ONE piece;
//    three setters would be three opportunities to forget one.
// 2. **The signal line loses its information.** See [SignalDispatch].

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/calls/address_candidates.dart';
import 'package:cleona/core/calls/call_control_frame.dart';
import 'package:cleona/core/calls/call_transport.dart';
import 'package:cleona/core/calls/punch_window.dart';
import 'package:cleona/core/link_io/d_frame.dart';
import 'package:cleona/core/link_io/d_socket.dart';
import 'package:cleona/core/link_io/link_host.dart' show ObservedAddressBook;
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/sync/entry_record.dart' show EntryAddress;
import 'package:cleona/generated/proto/transport_v3.pb.dart' as proto;

/// The signaling delivery of the service layer (`sendToUser`). The
/// transport does NOT build signaling itself — it runs as an ordinary
/// cell under the pair tag (§17.2).
///
/// ── THE SEAM THAT IS MISSING HERE (report AP-Calls, 2026-08-31) ──────────
///
/// The caller today sets `skipL3: true`, and `sendeModus`
/// (`tagline/delivery_api.dart:113`) maps that to `SendMode.secure`.
/// So the information "this is signaling" is used up before it
/// reaches `V41Node.send` — and `placeSecure(signal: true)`
/// (`v41_node.dart:1721`), which would operate the own signal line with `signalTag`,
/// `kSignalRelays = 5` and `kRetentionSignal`, therefore has no caller in
/// `lib/`. An INVITE today lies on the
/// MESSAGE line: `m x R = 60` placements = 480 s of egress against a
/// TTL of 120 s (§17.2). The necessary change is in the report; it
/// touches `delivery_api.dart` and `v41_node.dart` and does not belong in
/// this file.
typedef SignalDispatch = Future<bool> Function(
  Uint8List recipientUserId,
  proto.MessageTypeV3 type,
  Uint8List payload,
);

// The assignments in the initializer deliberately stand next to `_log`, which is
// BUILT there and not passed in (A-5 rule: a CLogger without profileDir
// should not be constructible at all).
// ignore_for_file: prefer_initializing_formals

/// What the call transport needs from the NODE (§17.3/§17.4) — as one
/// piece, not as three setters.
///
/// The three items come from the same `V41Node` and become valid or invalid at the same
/// moment: the socket carries the cookie table,
/// the port is the one at which the other side must arrive, and the
/// mirror is the only source of an outer address. Three separate
/// setters would be three opportunities to forget one — and a
/// forgotten mirror is only noticed by the first caller behind a NAT.
final class CallPlaneD {
  /// The node's cookie table (§17.4).
  final DSocket socket;

  /// The port on which this node's sockets REALLY lie.
  ///
  /// Not `advertisePort`: that is the announcement, this is the binding.
  /// A punch packet arrives at the binding or nowhere.
  final int ownPort;

  /// The node's §17.3 address mirror.
  final ObservedAddressBook observed;

  /// The CONFIRMED port mapping of the node (`V41Node.advertiseMapped`),
  /// or `null` — S376/A-1.
  ///
  /// ── WHY IT WAS MISSING HERE, AND WHAT THAT COST ────────────────────
  ///
  /// S373 created the port mapping and hooked it into the entry record
  /// (`V41Node.ownEntry`, second address) — but not into
  /// Plane D. §25.9 explicitly lists the mapping for INCOMING
  /// connections, and a call is the case in which that counts
  /// most: **whoever is only CALLED has no mirror.** The
  /// §17.3 mirror arises in flight 2 of a handshake, which the
  /// answering side WRITES; only whoever opened gets an observation about
  /// themselves (measured in `address_candidates.dart`, header, and
  /// in `smoke_call_punch_window.dart` section 1: "B, which only
  /// answered, has NO mirror candidate"). A callee
  /// behind NAT without its own outgoing handshakes thus named only
  /// PRIVATE addresses — the call fell back to the relay path §17.6,
  /// although the router had promised the forwarding.
  ///
  /// ── WHY A FUNCTION AND NOT A VALUE ─────────────────────────────
  ///
  /// `advertiseMapped` is a MUTABLE field of the node with its
  /// own lifecycle: it comes into being seconds to minutes AFTER the
  /// start, is renewed hourly and drops out when the router withdraws the
  /// grant or the network changes
  /// (`port_map_wiring.dart`, `V41Node.onNetworkChanged`). A value copied at
  /// attach time would almost always be `null` — `attachV41`
  /// runs at startup — and permanently wrong afterwards. The three other
  /// fields are fixed for the node's lifetime and therefore still stand
  /// there as values.
  final EntryAddress? Function()? mapped;

  const CallPlaneD({
    required this.socket,
    required this.ownPort,
    required this.observed,
    this.mapped,
  });
}

/// Plane D on `DSocket`.
class CallTransportV41 implements CallTransport {
  CallTransportV41({
    required SignalDispatch sendSignalViaUser,
    required String profileDir,
    CallPlaneD? planeD,
  })  : _sendSignalViaUser = sendSignalViaUser,
        _planeD = planeD,
        _log = CLogger.get('call-transport', profileDir: profileDir);

  final SignalDispatch _sendSignalViaUser;

  /// The Plane D cookie table of the NODE (§17.4).
  ///
  /// NOT `final`, and the reason is the construction order, not
  /// convenience: this transport comes into being in the constructor of `CallService`,
  /// i.e. with the service — the V4.1 node on the other hand comes into being once per
  /// PROCESS and is only attached to the service afterwards (`attachV41`).
  /// A `final` field would have required building the transport only after the node;
  /// exactly this order assurance has already brought `CallService`
  /// a `LateInitializationError` elsewhere
  /// (see the comment at the constructor there).
  CallPlaneD? _planeD;
  final CLogger _log;

  /// Attaches the node's Plane D. Called by `attachV41` as soon as
  /// node and service both stand.
  ///
  /// Idempotent with respect to the same piece; a DIFFERENT one replaces the
  /// previous one and drops the existing sessions — they
  /// belonged to the old cookie table and would be unfindable in the new demux.
  /// In operation that happens exactly once, namely when a
  /// node was restarted (port change, §22.6).
  void attachPlaneD(CallPlaneD? planeD) {
    if (identical(planeD, _planeD)) return;
    if (_planeD != null) forgetAllParticipants();
    _planeD = planeD;
    _log.info('Plane D: ${planeD == null ? 'deregistered' : 'registered on '
        'Port ${planeD.ownPort}'} (§17.3/§17.4)');
  }

  /// Counterpart (user hex) -> admitted Plane D session.
  ///
  /// **Keyed by the COUNTERPART, not by a device.** §14.2
  /// gives delivery no device level, and §17.4 does not need one either:
  /// the session is bound by `call_key` and cookie, not by an
  /// identifier.
  final _sessions = <String, DSession>{};
  final _subscriptions = <String, StreamSubscription<DFrame>>{};

  @override
  void Function(String peerHex, DFrame frame)? onMediaFrame;

  @override
  void Function(String peerHex, ControlRecord record)? onControlRecord;

  @override
  void Function(String peerHex)? onMediaPathLost;

  /// Puts a negotiated Plane D session into operation (§17.4).
  ///
  /// THIS IS THE PLACE WHERE THE PUNCH WINDOW FROM §17.3 ENDS: "the
  /// first address pair on which valid AEAD responses arrive carries the
  /// session". The candidates come from INVITE/ANSWER, the `call_key` from
  /// the key negotiation of the signaling (§17.2), the two
  /// cookies are negotiated by §17.6.
  ///
  /// **The caller in `lib/` is [openMediaPath]** (S361). Until then
  /// this method had none — the standard failure form of this migration.
  DSession? admitSession({
    required String peerHex,
    required Uint8List callKey,
    required DCookie remoteCookie,
    required InternetAddress peerAddress,
    required int peerPort,
    DCookie? localCookie,
  }) {
    final socket = _planeD?.socket;
    if (socket == null) {
      _log.error('Plane D: session for ${_short(peerHex)} not possible — '
          'no D socket hangs on this service, the demux branch '
          'LinkDemux.dAdmission is empty for it (§17.4)');
      return null;
    }
    forgetParticipant(peerHex);
    final session = socket.open(
      callKey: callKey,
      remoteCookie: remoteCookie,
      peerAddress: peerAddress,
      peerPort: peerPort,
      localCookie: localCookie,
    );
    _sessions[peerHex] = session;
    _everAdmitted = true;
    _subscriptions[peerHex] = session.inbound.listen((frame) {
      // A PROBE IS NOT MEDIA. A punch frame (§17.3) carries no
      // payload; passed up, it would be for the JitterBuffer
      // (§17.5) an Opus frame of length 0 and the decoder would get
      // filler to hear. It has already had its effect before it
      // arrives here: `DSession._deliver` has made its ORIGIN the
      // carrying path.
      // THE SAME HAS APPLIED TO PATH VALIDATION SINCE S377. A
      // challenge and its response (§17.4 + RFC 9000 §8.2) are
      // transport control, not media; their effect is done before
      // they arrive here — `DSession._deliver` has challenged or
      // responded and, if it matched, switched the path.
      if (frame.kind == DFrameKind.punch ||
          frame.kind == DFrameKind.pathChallenge ||
          frame.kind == DFrameKind.pathResponse) {
        return;
      }
      // A CONTROL FRAME IS NOT MEDIA (§17.1.1: "It is **not** a media
      // frame — it carries no media and is never handed to a codec").
      // The same rationale as one line above, only with a
      // receiver instead of a waste bin: the records go to
      // [onControlRecord], not to the JitterBuffer.
      if (frame.kind == DFrameKind.control) {
        for (final r in readControlRecords(frame.payload)) {
          onControlRecord?.call(peerHex, r);
        }
        return;
      }
      onMediaFrame?.call(peerHex, frame);
    });
    _log.info('Layer D admitted for ${_short(peerHex)}: '
        '${peerAddress.address}:$peerPort, cookie local '
        '${session.localCookie.key.toRadixString(16)}');
    return session;
  }

  // ── The path to the session: §17.3 punch window ─────────────────────────

  @override
  Uint8List newDCookie() => DCookie.generate().bytes;

  /// The own candidates last determined — for the diagnostics in
  /// [mediaUnavailableReason]. `null` as long as never determined.
  List<CallCandidate>? _ownCandidates;

  @override
  Future<Uint8List> localCandidatesPacked() async {
    final d = _planeD;
    if (d == null) return Uint8List(0);
    final k = await ownCallCandidates(
        ownPort: d.ownPort, observed: d.observed, mapped: d.mapped?.call());
    _ownCandidates = k;
    _log.info('Plane D: ${k.length} own address candidates (§17.3): '
        '${k.join(", ")}');
    return encodeCandidates(k);
  }

  /// Running punch windows per counterpart — so that a hang-up aborts them.
  ///
  /// **Without this table a window would keep running after hang-up**: it
  /// holds its own loop and asks nobody whether the call still
  /// exists. 30 seconds of packets to a counterpart that has hung up
  /// would be exactly the kind of traffic that working rule 5 rules out.
  final _punches = <String, PunchWindow>{};

  @override
  Future<PunchOutcome> openMediaPath({
    required String peerHex,
    required Uint8List callKey,
    required Uint8List localCookie,
    required Uint8List remoteCookie,
    required List<int> peerCandidatesPacked,
  }) async {
    final d = _planeD;
    if (d == null) {
      return const PunchOutcome(
        refusal: 'No level D hangs on this service (§17.4).',
        packetsSent: 0,
        bytesSent: 0,
        roundCarried: -1,
      );
    }
    if (callKey.length != 32) {
      // §17.1: "AES-256-GCM under `call_key`" — 32 B, otherwise not at all.
      // The case is real and not theoretical: `call.sharedSecret` stays
      // `null` if the other side's ephemeral keys were missing.
      return PunchOutcome(
        refusal: 'No `call_key` from the signalling (§17.2): '
            '${callKey.length} B instead of 32. Without it there is no AEAD '
            'under which a probe could be authenticated.',
        packetsSent: 0,
        bytesSent: 0,
        roundCarried: -1,
      );
    }
    if (remoteCookie.length != kDCookieSize) {
      return PunchOutcome(
        refusal: 'The other side named no session cookie (§17.4): '
            '${remoteCookie.length} B instead of $kDCookieSize. Its demux would '
            'not find our frames.',
        packetsSent: 0,
        bytesSent: 0,
        roundCarried: -1,
      );
    }

    final peerCandidates = decodeCandidates(peerCandidatesPacked);
    // THE GUESS with which the session opens. §17.3 fixes the path
    // only "with the first viable address pair"; until then `peerAddress`
    // must be SOMETHING, and the first named candidate is the best
    // available guess. `DSession._deliver` replaces it with the
    // finding as soon as a frame authenticates.
    final firstAddress = peerCandidates.isEmpty
        ? InternetAddress.loopbackIPv4
        : peerCandidates.first.address;
    final firstPort =
        peerCandidates.isEmpty ? d.ownPort : peerCandidates.first.port;

    final session = admitSession(
      peerHex: peerHex,
      callKey: callKey,
      remoteCookie: DCookie.of(remoteCookie),
      localCookie: DCookie.of(localCookie),
      peerAddress: firstAddress,
      peerPort: firstPort,
    );
    if (session == null) {
      return const PunchOutcome(
        refusal: 'The level-D session could not be admitted '
            '(§17.4).',
        packetsSent: 0,
        bytesSent: 0,
        roundCarried: -1,
      );
    }

    final own = _ownCandidates ??
        await ownCallCandidates(
            ownPort: d.ownPort,
            observed: d.observed,
            mapped: d.mapped?.call());
    final window = PunchWindow(
      session: session,
      peerCandidates: peerCandidates,
      log: (m) => _log.info('[$peerHex] $m'),
    );
    _punches[peerHex]?.cancel();
    _punches[peerHex] = window;
    // REMEMBERED FOR THE NETWORK CHANGE (§17.4, S376/A-2). The window carries
    // the other side's candidates, but is discarded after its run;
    // a change of the own network comes minutes later and needs
    // exactly this list once more.
    _peerCandidates[peerHex] = peerCandidates;
    try {
      final out = await window.run(ownCandidates: own);
      if (!out.carried) {
        // DO NOT LEAVE A HALF SESSION STANDING. An admitted session without a
        // carrying path would make `sendMedia` look successful —
        // `_sessions[peerHex]` is occupied, `session.send` does not throw, and
        // the frames would go to the GUESS from above. Exactly the silent
        // call that `mediaUnavailableReason` is supposed to prevent.
        forgetParticipant(peerHex);
      }
      return out;
    } finally {
      if (identical(_punches[peerHex], window)) _punches.remove(peerHex);
    }
  }

  // ── §17.4 path migration, sending side (S376/A-2) ───────────────────────
  //
  // ══ WHAT WAS ALREADY THERE, MEASURED ═════════════════════════════════════
  //
  // The RECEIVING SIDE of path migration has been built since S361 and is
  // restricted: `DSession._deliver` takes an authenticated frame from
  // a new source address as the occasion for a path change; a
  // change (not the first entry) requires a HIGHER sequence number
  // (RFC 9000 §9.3), so that a recorded frame cannot redirect the stream.
  //
  // **SINCE S377 THIS IS THE FIRST OF TWO STAGES.** Until then the sentence above read
  // "... and switches `peerAddress`"; it no longer does that
  // immediately. The sequence number only defeats the REPLAY of a
  // recorded frame — not the attacker who suppresses the original
  // and delivers its duplicate first (its frame is the
  // first with this number). Therefore a change now triggers a
  // path challenge to the new address and only switches on its
  // authenticated response (§17.4 + RFC 9000 §8.2, owner approval
  // 09.09.2026 on N-4). Measured in `smoke_call_path_migration.dart`
  // section 4 and `smoke_call_punch_window.dart` section 9.
  //
  // **For the burst here that changes nothing** — it sends probes, and
  // a probe from a new address triggers on the other side exactly the
  // challenge it is supposed to trigger. The price: 256 B per
  // real path change (one challenge, one response, 128 B each),
  // once, in addition to the 1.1 to 3.4 kB computed below.
  //
  // ══ WHY THAT ALONE IS NOT ENOUGH ══════════════════════════════════
  //
  // The receiving side cannot kick itself off. It needs an
  // arriving frame — and in the hardest and most common case none
  // comes:
  //
  //   Both sides are in the same Wi-Fi and have found each other via the LOCAL
  //   candidates (§17.3: "local first", because that is the
  //   path without NAT). A switches to mobile data. A keeps sending to
  //   192.168.x.y — unreachable. B keeps sending to A's old
  //   Wi-Fi address — unreachable. **No frame arrives anywhere, so
  //   nothing migrates**, and after 10 s of loss detection the call is
  //   dead.
  //
  // The way out is exactly one packet to an address at which the
  // other side is STILL reachable — and that is in its
  // candidate list from INVITE/ANSWER, which this session already
  // had anyway. Therefore the sending side lives here and not in `d_socket.dart`:
  // there are no candidates there, only the one destination address.

  /// The other side's candidates per running session — the set that
  /// a migration burst addresses.
  final _peerCandidates = <String, List<CallCandidate>>{};

  /// Running migration bursts per counterpart, so that a second
  /// network change replaces the first instead of doubling it.
  final _migrations = <String, Timer>{};

  /// How many rounds a migration burst sends at most.
  ///
  /// **Three, and the number is derived.** A punch window (§17.3)
  /// runs 30 rounds, because it must OPEN a NAT hole and for that both
  /// sides must send roughly simultaneously. Here there is nothing to
  /// open: the call stands, the other side is already sending, and the
  /// own outgoing packet opens the hole in the NEW network itself. What has to be
  /// bridged is solely PACKET LOSS. Three rounds survive two
  /// consecutive losses; with 5 % loss on a freshly
  /// established mobile link a residual probability of
  /// 1.25e-4 remains that the call dies at the change.
  static const int kMigrationRounds = 3;

  /// Interval between two rounds of a migration burst. Like §17.3
  /// ("1 packet/s") — the same rhythm, so that the bursts of a
  /// loose contact do not add up to a pattern of their own.
  static const Duration kMigrationInterval = Duration(seconds: 1);

  /// The network has changed — Wi-Fi to mobile data, cable pulled (§17.4).
  ///
  /// Attached to `CleonaService.onNetworkChanged` via
  /// `CallService.onNetworkChanged`. **There is no timer that
  /// calls this** — the edge is the operating system's event, and without
  /// it not a single packet occurs here (working rule 5).
  ///
  /// ── WHAT IT COSTS, computed ───────────────────────────────────────
  ///
  /// Per running call and change at most [kMigrationRounds] x
  /// (candidates + 1) frames of the voice class, i.e. with the
  /// at most `kMaxCallCandidates` = 8 named candidates
  /// 3 x 9 x 128 B = **3.4 kB**. For comparison: the voice frames of the same
  /// call cost 6.4 kB **per second and direction** (§17.1). The burst
  /// moreover aborts as soon as a frame from the other side
  /// authenticates again — as a rule after the FIRST round, i.e. 1.1 kB.
  ///
  /// Without a running call it costs **zero packets**: `_sessions` is empty.
  void onNetworkChanged() {
    if (_sessions.isEmpty) return;
    for (final peerHex in _sessions.keys.toList()) {
      _migrations.remove(peerHex)?.cancel();
      _migrationBurst(peerHex, 0, DateTime.now());
    }
  }

  void _migrationBurst(String peerHex, int round, DateTime start) {
    final session = _sessions[peerHex];
    if (session == null) {
      _migrations.remove(peerHex)?.cancel();
      return;
    }
    // ABORT AS SOON AS IT CARRIES AGAIN — and since S377 "carries" means
    // `lastCarryingFrameAt`, no longer `lastFrameAt`.
    //
    // ── WHY THE DISTINCTION BECAME NECESSARY, MEASURED ───────────────
    //
    // Here it said: "`lastFrameAt` is only set on a frame that passed the AEAD
    // — and such a frame has already pulled
    // `peerAddress` to its origin in `_deliver`." The second half of the sentence was
    // the load-bearing rationale and became wrong with path validation:
    // an authenticated frame from a not yet VALIDATED
    // address no longer pulls `peerAddress` along.
    //
    // The error was immediately measurable. A burst addresses several candidates;
    // the operating system chooses a different source address per destination
    // (127.0.0.1 for the loopback candidate, the LAN address for the
    // LAN candidate). The other side sees the second as a new path and
    // challenges it — and exactly this challenge arrived here as
    // "it carries again". `smoke_call_path_migration.dart` section 2
    // then reported "1 instead of 3 rounds": the burst aborted while
    // the carrying path was still silent. That would have given up a real
    // network change after the first round.
    final last = session.lastCarryingFrameAt;
    if (round > 0 && last != null && last.isAfter(start)) {
      _migrations.remove(peerHex)?.cancel();
      _log.info('Layer D: migration burst for ${_short(peerHex)} ended after ' // V3-TOUCH-OK: migration of a running call (§17.4), not V3
          'round $round — the other side is back (§17.4)');
      return;
    }
    if (round >= kMigrationRounds) {
      _migrations.remove(peerHex)?.cancel();
      _log.warn('Layer D: $kMigrationRounds migration rounds for ' // V3-TOUCH-OK: migration of a running call (§17.4), not V3
          '${_short(peerHex)} without answer — the 10 s loss rule from '
          '§17.4 decides now');
      return;
    }

    // The destinations: the other side's named candidates AND the last
    // carrying address. The latter is not always in the list — it may
    // come from port prediction or be an address that only the
    // other side's NAT generated — and in the most common case it is the
    // right one: if ONLY WE have changed, the other side is
    // reachable unchanged and one packet there suffices.
    final targets = <({InternetAddress address, int port})>[
      (address: session.peerAddress, port: session.peerPort),
    ];
    for (final k in _peerCandidates[peerHex] ?? const <CallCandidate>[]) {
      if (targets.any((z) => z.address == k.address && z.port == k.port)) {
        continue;
      }
      targets.add((address: k.address, port: k.port));
    }

    var packets = 0;
    var bytes = 0;
    for (final z in targets) {
      try {
        bytes += session.sendTo(
            DFrameKind.punch, Uint8List(0), z.address, z.port);
        packets++;
      } catch (e) {
        // As in `PunchWindow._senden`: one destination must not drag the others
        // down with it. Synchronously exactly one situation throws here today — an
        // address family that this node has not bound.
        _log.debug('Migration packet to ${z.address.address}:${z.port} ' // V3-TOUCH-OK: migration of a running call (§17.4), not V3
            'failed: $e');
      }
    }
    _log.info('Plane D: migration round ${round + 1}/$kMigrationRounds for ' // V3-TOUCH-OK: migration of a running call (§17.4), not V3
        '${_short(peerHex)} — $packets packets / $bytes B to '
        '${targets.length} targets (§17.4)');

    _migrations[peerHex] = Timer(kMigrationInterval, () {
      _migrationBurst(peerHex, round + 1, start);
    });
  }

  // ── Signalisierung ────────────────────────────────────────────────────

  @override
  Future<bool> sendSignal({
    required Uint8List recipientUserId,
    required proto.MessageTypeV3 type,
    required Uint8List payload,
  }) =>
      _sendSignalViaUser(recipientUserId, type, payload);

  // ── Media ─────────────────────────────────────────────────────────────

  /// Has [admitSession] ever admitted anything during this runtime?
  ///
  /// The value only grows. Until S361 it was the condition in
  /// [mediaUnavailableReason]; it no longer is (rationale there). It
  /// stays as a MEASURED QUANTITY — a smoke can read from it whether a
  /// path really went through admission.
  var _everAdmitted = false;

  bool get everAdmitted => _everAdmitted;

  @override
  String? get mediaUnavailableReason {
    if (_planeD == null) {
      // SINCE S360 THE SENTENCE IS A DIFFERENT FINDING. Before, it said "is
      // set nowhere in lib/" — a statement about the tree. Now
      // `V41Node.start` sets the branch `LinkDemux.dAdmission`, and this
      // branch here means: no node hangs on THIS service. That has
      // exactly three causes, and they are all observable — therefore
      // they are in the text and not in a comment.
      return 'No D socket registered on this service, so the '
          'demux branch LinkDemux.dAdmission is empty for it (§17.4). '
          'Causes: V4.1 delivery is switched off (CLEONA_V41=0), '
          'attachV41 has not run for this identity, or the '
          'node was shut down.';
    }
    // ── WHAT IS ASKED HERE SINCE S361, AND WHAT NO LONGER ──────────
    //
    // Until S361 this held `if (!_everAdmitted)` — "has anyone ever admitted a
    // session". The comment at this place prescribed its
    // own successor, and it was right: the question
    // has to go, because it would have rejected the FIRST call of every process forever
    // as soon as the punch window exists.
    //
    // What is asked now is what can be decided at all BEFORE the call:
    // can the window run. What can only be decided DURING the call
    // — has the other side named candidates, is there a common
    // address family, does a pair carry — is in `PunchOutcome.refusal` and
    // belongs there: it is a statement about THIS call, not about
    // this node. Putting both into one getter would mean making a statement
    // about a counterpart that nobody has named yet.
    final port = _planeD!.ownPort;
    if (port < 1 || port > 65535) {
      return 'The node has no bound data port ($port), so there '
          'is no own address that the punch window from §17.3 could '
          'name.';
    }
    // The own candidates are NOT determined here: that is a
    // system call (`NetworkInterface.list`), and this getter runs in the
    // call path. It only reports what an EARLIER determination produced —
    // and if none has run yet, that is no reason to refuse: the first
    // runs when building the INVITE (`localCandidatesPacked`), i.e. right
    // after.
    final own = _ownCandidates;
    if (own != null && own.isEmpty) {
      return 'This node cannot name an own address (§17.3): neither '
          'a dialable local one nor an observed one. With CGNAT without an '
          'observable outer address this is not an error under §17.3, '
          'but the refusal — messages are unaffected.';
    }
    return null;
  }

  @override
  MediaSendFailure? sendMedia({
    required String peerHex,
    required DFrameKind kind,
    required Uint8List payload,
  }) {
    final session = _sessions[peerHex];
    if (session == null) return MediaSendFailure.noPath;
    // The class boundary is checked HERE and not left to `sealDFrame`:
    // the throw there is right (a promotion into the
    // next class would be a size difference on the wire, §17.1),
    // but at 50 frames/s it would come out as an exception. The contract has
    // a return value for exactly that.
    if (payload.length > kind.frameClass.payloadCapacity) {
      return MediaSendFailure.tooLarge;
    }
    try {
      session.send(kind, payload);
      return null;
    } catch (e) {
      _log.debug('Plane D: frame to ${_short(peerHex)} failed: $e');
      return MediaSendFailure.buildFailed;
    }
  }

  @override
  MediaSendFailure? sendSecuredToParticipant({
    required String participantHex,
    required Uint8List peerX25519Pk,
    required Uint8List peerMlKemPk,
    required proto.MessageTypeV3 type,
    required Uint8List payload,
    bool expectsReply = false,
  }) {
    // NO CARRIER FOR AN ARBITRARY PROTO PAYLOAD — AND NO
    // INVENTED ONE. The sentence that stood here until S368 was broader:
    // "§17.1 knows three frame kinds […] key distribution, tree maintenance
    // and RTT probes are none of them […] group topology open (§17.5,
    // C-9/C-10/C-11, K31-3)."
    //
    // **Two of its three pieces have been wrong since 05.09.2026.** §17.1.1
    // gives Plane D a fourth frame kind, and §17.7 closes K31-3.
    // Tree maintenance and RTT probes very much have a carrier since then —
    // [sendControl]. The sentence stays as a CORRECTION instead of
    // disappearing; an outdated status line that silently
    // goes away is the mistake this project has made several times.
    //
    // What STILL has no carrier, and why: this method takes
    // an arbitrary proto payload. §17.1.1 enumerates exhaustively what
    // a control frame carries, and says in addition what it may never carry —
    // "media payload, key material beyond the session's own tree
    // bookkeeping, or anything that would make it worth relaying by a node
    // that is not a call participant". A whiteboard stroke (§10.5) is
    // exactly that. It moreover does not fit: 85 B per frame.
    //
    // ADDED S378 (merge): KEY DISTRIBUTION was also in the
    // quoted sentence and has no longer belonged there since E-1 = B
    // — it runs via `GroupCallSenderKey` on the
    // delivery layer, together with the Plane D pair material and the
    // round. The branch that built §17.1.1 is older than this
    // decision and could not name it.
    _log.debug('Plane D: ${type.name} to ${_short(participantHex)} has '
        'no carrier — an arbitrary proto payload is not a '
        '§17.1.1 control message. Tree maintenance and RTT run via '
        'sendControl.');
    return MediaSendFailure.noCarrier;
  }

  @override
  String? get treeMaintenanceUnavailableReason {
    // ── UNTIL S368 THIS GETTER ALWAYS RETURNED A REASON ──────────
    //
    // The text read: "Tree maintenance (CALL_TREE_UPDATE) has no carrier on Plane D:
    // §17.1 knows three frame kinds […] group topology
    // open (§17.5, K31-3)." It was true, and it prescribed its own
    // successor: "Whoever builds the carrier (option A of the
    // S368 proposal: fourth frame kind in §17.1) changes both places
    // together — then the participant limit in
    // `GroupCallManager` lifts by itself."
    //
    // The carrier is built ([DFrameKind.control], §17.1.1), and the
    // limit lifts by itself exactly like that: `effectiveTopology` asks
    // this getter.
    //
    // ── WHAT IS ASKED HERE, AND WHAT EXPLICITLY NOT ────────────
    //
    // What is asked is what can be decided about this NODE BEFORE the call:
    // does a Plane D hang on it. What is not asked is whether there is a session to a
    // specific participant — that is a statement about
    // a counterpart that nobody has named yet at call time, and it
    // is in `PunchOutcome.refusal`. The same separation as in
    // [mediaUnavailableReason], for the same reason.
    final d = _planeD;
    if (d == null) {
      return 'No D socket registered on this service, so tree '
          'maintenance does not carry either (§17.4). Causes: V4.1 delivery is '
          'switched off (CLEONA_V41=0), attachV41 has not run for this identity, '
          'or the node was shut down.';
    }
    if (d.ownPort < 1 || d.ownPort > 65535) {
      return 'The node has no bound data port (${d.ownPort}), '
          'so no control frame can go out (§17.1.1).';
    }
    return null;
  }

  // ── Steuerebene (§17.1.1) ─────────────────────────────────────────────

  /// What waits for the next tick per counterpart.
  ///
  /// §17.1.1 makes bundling MANDATORY, not an optimisation:
  /// unbundled, the control plane in a fully meshed
  /// 50-participant round would cost **398 kbps**. Bundled at 1 Hz it is **63 kbps**
  /// (31 kbps at 25 participants; in the star 1.3 kbps at the leaf).
  ///
  /// **Bundling stays mandatory — only the rate has been halved.**"
  final _pendingControl = <String, List<ControlRecord>>{};

  /// The 2 Hz tick from §17.1.1. Runs only as long as something is waiting — a
  /// timer that inspects an empty list twice per second in every call
  /// would be exactly the idle activity that working rule 5 rules out.
  Timer? _controlTick;

  /// §17.1.1: **1 Hz** (owner decision 05.09.2026; until then 2 Hz).
  ///
  /// ── WHY 1 Hz ONLY WORKS NOW ─────────────────────────────────────
  ///
  /// §17.1.1 used to explicitly rule out 1 Hz: "1 Hz does not
  /// fit (85.6 B of payload against 85 B of capacity)". This calculation
  /// depended on the 85 B payload of the 128 B class. Since the voice class
  /// measures 176 B, it carries **133 B**, and the 85.6 B of a 1 Hz tick
  /// fit in with **47 B to spare** (117 B / 31 B to spare on 05.09.2026).
  /// The control load is thus halved: 63 instead of 125 kbps at 50
  /// participants.
  ///
  /// **Measured, not computed** (`smoke_call_plane_d`, section 5b,
  /// two real nodes on loopback): at 42 B per record **three**
  /// records fit into one tick, so seven records force a real
  /// overflow — and all seven arrive. `packControlRecords` takes
  /// only what fits, `_flushControl` keeps the rest for the next tick;
  /// nothing is lost and nothing rises into the 1200 B class.
  ///
  /// ── THE PRICE, NAMED AND ACCEPTED ──────────────────────────────
  ///
  /// A change of speaker becomes visible up to **one second** late.
  /// **Nothing is built to counter that** — in particular there is no
  /// special path "send speaker change immediately outside the tick". Such
  /// a frame would have its own rate, and its own rate is
  /// exactly the leak that the shared size class is meant to close: the
  /// control traffic would then have its peak when someone starts to speak.
  /// The media tree is not rebuilt on a speaker change anyway
  /// (§17.7: "speaker change […] **no** — change which streams are
  /// forwarded, leave the tree standing").
  static const Duration controlTickInterval = Duration(seconds: 1);

  @override
  MediaSendFailure? sendControl({
    required String participantHex,
    required ControlRecord record,
  }) {
    if (_planeD == null) return MediaSendFailure.noCarrier;
    if (record.value.length > kControlRecordMaxValue) {
      // DO NOT CHUNK. Everything that §17.1.1 enumerates is small; what
      // does not fit in was never control information and belongs on
      // signaling (§17.2).
      return MediaSendFailure.tooLarge;
    }
    // The SESSION is already checked here and not only in the tick: a
    // record that lies in a queue for 500 ms only to fail at a
    // missing path hides from the caller for half a
    // second that it is sending into nothing.
    if (_sessions[participantHex] == null) return MediaSendFailure.noPath;
    (_pendingControl[participantHex] ??= <ControlRecord>[]).add(record);
    _controlTick ??= Timer.periodic(controlTickInterval, (_) => _flushControl());
    return null;
  }

  /// One tick: per counterpart ONE frame with everything that fits in.
  void _flushControl() {
    if (_pendingControl.isEmpty) {
      // No idling: the tick stops as soon as nothing is waiting anymore, and
      // starts afresh at the next [sendControl].
      _controlTick?.cancel();
      _controlTick = null;
      return;
    }
    for (final peer in _pendingControl.keys.toList()) {
      final queue = _pendingControl[peer]!;
      final session = _sessions[peer];
      if (session == null) {
        // The participant is gone. Its records go with it — passing them on to the
        // next tick would mean keeping a queue for
        // a counterpart that no longer exists.
        _pendingControl.remove(peer);
        continue;
      }
      final body = packControlRecords(queue,
          capacity: DFrameKind.control.frameClass.payloadCapacity);
      if (body.isEmpty) {
        _pendingControl.remove(peer);
        continue;
      }
      try {
        session.send(DFrameKind.control, body);
      } catch (e) {
        _log.debug('Plane D: control frame to ${_short(peer)} failed: $e');
      }
      // What did not fit in stays for the next tick —
      // `packControlRecords` has taken exactly those it sent.
      if (queue.isEmpty) _pendingControl.remove(peer);
    }
    if (_pendingControl.isEmpty) {
      _controlTick?.cancel();
      _controlTick = null;
    }
  }

  // ── State ─────────────────────────────────────────────────────────────

  @override
  int routeCostTo(String participantHex, {int fallback = 10}) {
    // §17.1: "No routes, only address candidates." There is nothing to
    // estimate, so nothing is estimated. An invented value would be
    // worse than the fallback value: the spanning tree on top would look
    // weighted and would not be.
    return fallback;
  }

  @override
  void forgetParticipant(String participantHex) {
    _pendingControl.remove(participantHex);
    if (_pendingControl.isEmpty) {
      _controlTick?.cancel();
      _controlTick = null;
    }
    _punches.remove(participantHex)?.cancel();
    _migrations.remove(participantHex)?.cancel();
    _peerCandidates.remove(participantHex);
    _subscriptions.remove(participantHex)?.cancel();
    final session = _sessions.remove(participantHex);
    if (session == null) return;
    unawaited(session.close().catchError((Object e) {
      _log.debug('Plane D: closing the session to '
          '${_short(participantHex)} threw: $e');
    }));
  }

  @override
  void forgetAllParticipants() {
    // NOT JUST `_sessions`. A punch window can be running while
    // `_sessions` has already lost the entry again (the outcome
    // `forgetParticipant` in [openMediaPath]). Going only via `_sessions`
    // would let exactly this window keep running.
    // THREE SETS SINCE S376. A migration burst runs on a timer
    // and thus survives a `_sessions.remove` just like a window;
    // its candidate list depends on the same identifier.
    for (final peer in <String>{
      ..._sessions.keys,
      ..._punches.keys,
      ..._migrations.keys,
      ..._peerCandidates.keys,
    }) {
      forgetParticipant(peer);
    }
  }

  static String _short(String hex) =>
      hex.length >= 8 ? hex.substring(0, 8) : hex;
}
