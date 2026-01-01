/// The D socket — admission for Plane D on the node's one UDP port (§17.4).
///
/// **There is no second port, and that decides the construction.** E-64
/// forecloses one, and a second `SO_REUSEADDR` socket on the same port is
/// documented broken (`udp_sockets.dart`, library comment). So a D-frame
/// shares the socket with the delivery layer's cells and handshake flights,
/// and the distinction has to fall in the demux. "The D socket" of §17.4 is
/// therefore not a socket at all — it is this table plus the branch
/// `LinkDemux` calls into it. The name is kept because §17.4 uses it.
///
/// **What §17.4 requires, quoted:** "the D socket responds **exclusively** to
/// packets with a valid AEAD under `call_key` plus a session cookie —
/// statelessly verifiable, no response to unknown parties, so there is **no
/// amplification surface** and no need for an address allowlist. Whoever does
/// not have the `call_key` from signaling does not exist for the socket."
///
/// **The receive path answers NOTHING to the UNAUTHENTICATED — and since S377
/// answers something to the authenticated in exactly two cases.** Until S377 this said: "no
/// send path that a received datagram can trigger". That was right for the
/// admission rule and has remained so: a datagram without a valid
/// AEAD under `call_key` still produces **zero bytes**, no response,
/// no error message, no log line — `smoke_d_frame.dart` section 4
/// measures that as a byte counter on a real socket. But the sentence was
/// phrased as a WHOLE and therefore no longer holds. What applies now:
///
///   * An authenticated frame from a NEW address triggers **one**
///     [DFrameKind.pathChallenge] to exactly that address
///     (§17.4 + RFC 9000 §8.2, owner approval 09.09.2026 on N-4).
///   * An authenticated [DFrameKind.pathChallenge] is answered with **one**
///     [DFrameKind.pathResponse] to its origin.
///
/// **Why this does NOT open the amplification surface, calculated.** §17.4
/// explicitly names "no amplification surface" as the reason for the admission rule.
/// Amplification means: more bytes out than in, without
/// prior effort. Here (a) every response requires a frame that
/// passed the AEAD under `call_key` — whoever does not have the key
/// still gets silence; (b) the factor is 128 B in to at most
/// 2 x 128 B out, i.e. 2, not the three- to hundredfold amplification
/// the rule stands against; (c) the challenge is capped
/// ([DSession.kMaxPathChallenges]) and has **no timer** — it arises
/// only on an arriving frame, never by itself (working rule 5).
///
/// **"Statelessly verifiable" — where this deviates, honestly.** A cookie
/// that is verifiable with *no* state at all is a MAC over the peer address
/// under a node secret. That is not what a call needs: a call already holds
/// per-session state (the `call_key`), so the cookie here is a lookup key
/// into that state, and the verification is `O(1)` rather than stateless in
/// the strict sense. What §17.4 buys with the phrase — no round trip, no
/// negotiation, no response to an unknown party — holds either way. The
/// difference is recorded rather than papered over.
///
/// **No source-address filter, deliberately.** §17.3 has both sides send "for
/// up to 30 s at 1 packet/s to all of the other side's candidates", and
/// §17.4 has an authenticated migration packet "from a new address" swing the
/// path over. An address allowlist would break both — which is why §17.4
/// says explicitly that the AEAD makes one unnecessary. The session is found
/// by cookie and proven by AEAD; where the bytes came from is not part of
/// either test.
///
/// **What is NOT built here.** The punch window (§17.3) itself, the address
/// candidates, the port prediction, and the 10 s loss timeout. Those live in
/// `lib/core/calls/punch_window.dart` and `address_candidates.dart`; this
/// module carries only what a punch needs from the socket.
///
/// **What S361 ADDED here, and why it belongs here and nowhere else.** A
/// punch sends to MANY addresses and learns which one carries from the
/// address an authenticated frame arrives FROM. Both halves are properties
/// of the datagram, and the datagram exists only in this module:
///
///   * [DSession.sendTo] seals through the session's own sequence counter
///     but puts the frame on the wire towards a given address. Sealing stays
///     in one place; only the destination is free.
///   * [DSession._deliver] now takes the datagram's origin and records it as
///     [DSession.confirmedPath] — §17.3's "carrying address pair".
///
/// **What S377 CHANGED about it.** The sentence at this place read: the
/// first entry confirms the path, "and swings the media path over on a
/// later frame from a NEW address". The second half-sentence has not been true
/// since S377 — a CHANGE no longer swings on the frame, it
/// triggers a challenge and swings only on its authenticated
/// response (§17.4 + RFC 9000 §8.2, see [DSession.kMaxPathChallenges] for
/// the derivation). The first entry has remained unchanged.
///
/// [DSession.lastFrameAt] is exposed so the 10 s loss rule has something to
/// read; `punch_window.dart` reads it, nothing else does yet.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/link_io/d_frame.dart';
import 'package:cleona/core/link_io/udp_sockets.dart';

/// One admitted Plane D session: two cookies, one key, one peer address.
///
/// **Two cookies, not one.** §17.6: "the volunteer hands out two session
/// cookies". Each direction is found by the cookie of the side that
/// *receives* it, so [localCookie] is what arrives here and [remoteCookie] is
/// what this side stamps on what it sends. One shared cookie would make the
/// two directions of a call linkable by a single observed value and would
/// collide the moment a node relays for two sessions of the same pair.
final class DSession {
  /// The cookie this side handed out. Arriving frames carry it.
  final DCookie localCookie;

  /// The cookie the peer handed out. Outgoing frames carry it.
  final DCookie remoteCookie;

  /// The `call_key` from signaling (§17.2). 32 bytes.
  ///
  /// This module never derives, stores beyond the session, or rotates it.
  final Uint8List callKey;

  /// Where [send] sends to. **Not `final`, and that is §17.4**, not
  /// convenience: "an authenticated migration packet from a new address
  /// (valid AEAD + cookie) swings the media path over — a WLAN→LTE change
  /// survives the call without a delivery-layer round trip and without new
  /// signaling." The only writer is [_pivot]; whoever wanted to re-hang it
  /// from outside would bypass the authentication.
  ///
  /// **Since S377 "valid AEAD + cookie" no longer suffices for a CHANGE**
  /// — it additionally requires a passed path validation
  /// (RFC 9000 §8.2, [kMaxPathChallenges]). The first entry is
  /// unchanged. §17.4 says nothing about this; the addition is an
  /// owner decision of 09.09.2026 (proposal N-4).
  InternetAddress peerAddress;
  int peerPort;

  /// The address from which the last frame came that AUTHENTICATED —
  /// or `null` as long as none has come.
  ///
  /// This is the "carrying address pair" finding from §17.3 ("the first
  /// address pair on which valid AEAD responses arrive carries the
  /// session"). It is kept separate from [peerAddress] because the two
  /// answer different questions: where we send to, and where something
  /// genuine came from. Before the first genuine frame [peerAddress] is a
  /// GUESS (the first candidate), whereas [confirmedPath] is `null` — and
  /// only that may the layer above read as "the path carries".
  ({InternetAddress address, int port})? confirmedPath;

  /// Called when [confirmedPath] is set for the first time or changes to a
  /// DIFFERENT address (§17.4 path migration). Carries the new path.
  void Function(InternetAddress address, int port)? onPathConfirmed;

  /// The highest sequence number that has arrived authenticated under this
  /// session. −1 as long as none has come.
  ///
  /// **It is the FIRST of two stages, and it is borrowed.** Until S377
  /// this said "the condition" — singular; since path validation it is
  /// the preliminary stage that decides whether to challenge at all
  /// ([kMaxPathChallenges]). It is not replaced by that: without it
  /// every captured frame could trigger a challenge arbitrarily often,
  /// and that would be traffic an attacker
  /// without `call_key` can order.
  /// §17.4 demands only "valid AEAD + cookie" for the path change and says
  /// nothing about replay. Without a further condition, however, it suffices
  /// to capture ONE genuine frame and later resend it from any
  /// address in order to redirect the media stream there
  /// — an attack for which the attacker does not need the `call_key`.
  /// QUIC has the same spot and the same answer: a migration
  /// is only accepted on a packet with a HIGHER packet number
  /// (RFC 9000 §9.3, "An endpoint only changes the address to which it sends
  /// packets in response to the highest-numbered non-probing packet"). The
  /// condition is thus derived, not invented.
  ///
  /// The first entry (`confirmedPath == null`) does not need it: there
  /// is no path yet from which traffic could be diverted.
  int highestSeqSeen = -1;

  /// How often the same new address is challenged at most before
  /// this session falls silent towards it.
  ///
  /// **Three, and then silence — no timer, no polling.** There is
  /// no timer here and no retry loop: a challenge
  /// arises exclusively on an ARRIVING authenticated frame from
  /// this address. The cap thus does not limit an own cadence,
  /// but what a peer (or an attacker with suppressed
  /// originals) can order in responses: at most three per address.
  /// Three, because the migration burst of the other side
  /// (`call_transport_v41.dart`, `kMigrationRounds`) runs exactly three rounds
  /// — each round may challenge once, and there are no more rounds
  /// that could.
  static const int kMaxPathChallenges = 3;

  /// The open challenge: which bytes, to which address, how often
  /// already sent. `null` when none is open.
  ///
  /// **Exactly ONE, and the newest displaces the older.** Validating two
  /// simultaneously open paths would mean keeping two states,
  /// of which at most one is needed; and the
  /// displacement costs nothing, because on a genuine
  /// change the other side bursts for three rounds and the challenge thus
  /// follows. Whoever wants to displace needs an authenticated
  /// frame with a higher sequence number anyway — i.e. a suppressed original,
  /// not a free choice.
  ({Uint8List bytes, InternetAddress address, int port, int sent})?
      _openChallenge;

  /// The address currently being challenged — for guards and
  /// diagnostics. `null` when no challenge is open.
  ({InternetAddress address, int port})? get pendingPathTarget {
    final o = _openChallenge;
    return o == null ? null : (address: o.address, port: o.port);
  }

  /// How many challenges this session has sent.
  int pathChallengesSent = 0;

  /// How many responses this session has sent.
  int pathResponsesSent = 0;

  /// The wire bytes that challenges and responses together have
  /// cost. The PRICE of path validation, measured instead of estimated.
  int pathValidationBytesSent = 0;

  final UdpSocketSet _sockets;
  final void Function(DCookie) _onClose;
  final _inbound = StreamController<DFrame>.broadcast();

  var _sendSeq = 0;
  var _closed = false;

  /// When the last frame that **authenticated** arrived. Not "when the last
  /// datagram arrived": §17.4's loss rule counts valid media frames, and a
  /// forgery must not keep a dead session alive.
  DateTime? lastFrameAt;

  /// When an authenticated frame last came over the CONFIRMED path —
  /// i.e. over exactly the address [send] is currently sending to.
  ///
  /// ── WHY THIS IS NOT THE SAME AS [lastFrameAt] (S377) ──────────
  ///
  /// Until S377 the two were indistinguishable, because EVERY authenticated
  /// frame from a new address pulled the path there immediately: "a
  /// frame arrived" thus necessarily meant "the path on which we
  /// send carries". Since path validation that no longer holds — a
  /// frame from a not yet validated address sets [lastFrameAt] and
  /// leaves [peerAddress] untouched.
  ///
  /// The difference is measured and not theoretical: the
  /// migration burst (`call_transport_v41.dart`) aborted on [lastFrameAt]
  /// and, after validation was built, did so after ONE instead of three
  /// rounds — `smoke_call_path_migration.dart` section 2 reported this as
  /// "1 instead of 3". Cause: a burst addresses several candidates,
  /// the operating system picks a different source address per destination, and
  /// the other side challenges the second of them — its
  /// challenge came back and looked like "it carries again",
  /// although the carrying path was unchanged and silent. Whoever wants to abort
  /// must read THIS value.
  DateTime? lastCarryingFrameAt;

  DSession._(
    this._sockets,
    this._onClose, {
    required this.localCookie,
    required this.remoteCookie,
    required this.callKey,
    required this.peerAddress,
    required this.peerPort,
  });

  /// Every frame that arrived under this session and authenticated.
  Stream<DFrame> get inbound => _inbound.stream;

  /// The sequence number the next [send] will carry.
  int get nextSeq => _sendSeq;

  /// Seals [payload] as one [kind] frame and puts it on the wire.
  ///
  /// Returns the wire length, which is always the class size — 160 for
  /// speech, 1200 for a video fragment or a stream block, never anything in
  /// between and never anything shorter because the payload was small.
  ///
  /// **Throws after [close], and that is deliberate** — the same rule
  /// `UdpLinkChannel.send` follows (B-6). A closed session that kept sending
  /// would send under a key the peer has torn down; swallowing the call
  /// hides a local programming error that never reaches the wire and is
  /// invisible to any network observer, so §2.6's silence does not apply.
  int send(DFrameKind kind, Uint8List payload) =>
      sendTo(kind, payload, peerAddress, peerPort);

  /// Like [send], but to an explicit address — the send path of the
  /// punch window (§17.3: "both sides send … **to all of the other
  /// side's candidates**").
  ///
  /// **Why through the session and not past the socket.** Sealing
  /// stays in ONE place, and above all the sequence counter stays ONE:
  /// punch frames and media frames run under the same cookie and
  /// the same key, so they must share the same counter.
  /// Two counters would yield two frames with the same number — and the
  /// migration condition ([highestSeqSeen]) would thereby be worthless on the
  /// other side.
  int sendTo(DFrameKind kind, Uint8List payload, InternetAddress address,
      int port) {
    if (_closed) {
      throw StateError('D session ${localCookie.key.toRadixString(16)} '
          'is closed');
    }
    final frame = sealDFrame(
      cookie: remoteCookie,
      callKey: callKey,
      kind: kind,
      seq: _sendSeq,
      payload: payload,
    );
    // 32-bit counter, wraps after 2^32 frames — 2.7 years at the 50 frames/s
    // of §17.1. The wrap is defined rather than left to overflow into a
    // negative int, which `sealDFrame` would then refuse.
    _sendSeq = (_sendSeq + 1) & 0xFFFFFFFF;
    _sockets.send(frame, address, port);
    return frame.length;
  }

  /// Opens one arriving datagram. `true` when it authenticated.
  ///
  /// Records the path finding from §17.3/§17.4: the origin of a frame
  /// that AUTHENTICATED is the carrying address pair. A forgery
  /// never arrives here — `openDFrame` has discarded it beforehand.
  ///
  /// ══ THE ORDER IS THE STATEMENT (S377) ═════════════════════════
  ///
  /// 1. **A valid response swings** — before everything else, so that the
  ///    following step 3 does not see the just validated path again as
  ///    "new" and challenge itself.
  /// 2. **First entry** (`confirmedPath == null`) swings unchanged
  ///    immediately. There is no path there from which traffic could be
  ///    diverted — the same exception that RFC 9000 §8.1 makes for the
  ///    original path.
  /// 3. **A CHANGE challenges instead of swinging.** Two stages:
  ///    the sequence number ([highestSeqSeen], RFC 9000 §9.3) decides whether
  ///    at all, and the authenticated response decides whether
  ///    to swing (RFC 9000 §8.2).
  /// 4. **A challenge is answered**, to its origin.
  ///
  /// The running call meanwhile stays on the OLD path:
  /// [peerAddress]/[peerPort] are not touched in step 3, and
  /// [send] keeps sending there. An unanswered challenge
  /// therefore costs the call nothing except the 128 B it was.
  bool _deliver(
      Uint8List datagram, DateTime now, InternetAddress from, int fromPort) {
    final frame = openDFrame(datagram, callKey, localCookie);
    if (frame == null) return false;
    lastFrameAt = now;

    // 1. The response to an open challenge — the only way in
    //    which an EXISTING path still changes since S377.
    if (frame.kind == DFrameKind.pathResponse) {
      _checkAnswer(frame.payload, from, fromPort);
    }

    final soFar = confirmedPath;
    if (soFar == null) {
      // 2. Ersteintritt (§17.3 „the first address pair on which valid AEAD
      //    responses arrive carries the session").
      _pivot(from, fromPort);
    } else if ((soFar.address != from || soFar.port != fromPort) &&
        frame.seq > highestSeqSeen) {
      // 3. Change: stage 1 passed, now trigger stage 2.
      _requestOut(from, fromPort);
    }
    if (frame.seq > highestSeqSeen) highestSeqSeen = frame.seq;

    // Does the path on which we SEND carry? Evaluated after steps 1-3,
    // so that a just validated change counts as carrying immediately.
    final current = confirmedPath;
    if (current != null && current.address == from && current.port == fromPort) {
      lastCarryingFrameAt = now;
    }

    // 4. A challenge is answered — to its ORIGIN, not
    //    to [peerAddress]. RFC 9000 §8.2.2: the response belongs on the path
    //    on which the challenge came, otherwise it proves nothing about it.
    if (frame.kind == DFrameKind.pathChallenge &&
        frame.payload.length == kDPathChallengeSize) {
      _send(DFrameKind.pathResponse, Uint8List.fromList(frame.payload), from,
          fromPort, answer: true);
    }

    if (!_inbound.isClosed) _inbound.add(frame);
    return true;
  }

  void _pivot(InternetAddress address, int port) {
    confirmedPath = (address: address, port: port);
    peerAddress = address;
    peerPort = port;
    onPathConfirmed?.call(address, port);
  }

  /// Stage 2: a challenge to [address]:[port].
  ///
  /// The same address gets at most [kMaxPathChallenges] of them, and
  /// then never again — until a DIFFERENT address displaces the open one
  /// or a response resolves it. The bytes stay THE SAME on a
  /// repetition: they lie inside the AEAD, an observer
  /// never sees them, so a repetition reveals nothing — and a
  /// single open value makes the check in [_checkAnswer]
  /// unambiguous.
  void _requestOut(InternetAddress address, int port) {
    final open = _openChallenge;
    if (open != null && open.address == address && open.port == port) {
      if (open.sent >= kMaxPathChallenges) return; // Silence.
      _openChallenge = (
        bytes: open.bytes,
        address: address,
        port: port,
        sent: open.sent + 1
      );
      _send(DFrameKind.pathChallenge, open.bytes, address, port,
          answer: false);
      return;
    }
    final bytes = newPathChallenge();
    _openChallenge =
        (bytes: bytes, address: address, port: port, sent: 1);
    _send(DFrameKind.pathChallenge, bytes, address, port, answer: false);
  }

  /// Checks a response against the open challenge. If it matches, the path is
  /// swung.
  ///
  /// Three conditions, all three necessary: the response must come FROM the
  /// challenged address (otherwise it proves nothing about it),
  /// it must have the same length, and it must match byte by byte. The
  /// comparison runs without early exit — it is behind the AEAD
  /// and thus closed to a guesser anyway, but a comparison that
  /// is only safe because of a second gate is a dependency
  /// nobody has written down.
  void _checkAnswer(Uint8List given, InternetAddress from, int fromPort) {
    final open = _openChallenge;
    if (open == null) return;
    if (open.address != from || open.port != fromPort) return;
    if (given.length != open.bytes.length) return;
    var diff = 0;
    for (var i = 0; i < given.length; i++) {
      diff |= given[i] ^ open.bytes[i];
    }
    if (diff != 0) return;
    _openChallenge = null;
    _pivot(from, fromPort);
  }

  /// A path-validation frame onto the line. Counts along.
  ///
  /// **A failed send attempt does not tear down the receive path.**
  /// [sendTo] throws on a closed session and can fail on an unbound
  /// address family; neither may propagate upwards
  /// here, because the running call hangs on the OLD path and does
  /// not depend on this challenge. Silence, as everywhere on
  /// this path (§2.6).
  void _send(DFrameKind kind, Uint8List bytes, InternetAddress address,
      int port, {required bool answer}) {
    try {
      pathValidationBytesSent += sendTo(kind, bytes, address, port);
      if (answer) {
        pathResponsesSent++;
      } else {
        pathChallengesSent++;
      }
    } catch (_) {
      // Silence.
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _onClose(localCookie);
    if (!_inbound.isClosed) await _inbound.close();
  }
}

/// The cookie table of §17.4 and the demux branch that consults it.
final class DSocket {
  final UdpSocketSet sockets;

  /// Keyed on the 64-bit form of the cookie — see [DCookie] for why an `int`
  /// and not a string.
  final _sessions = <int, DSession>{};

  final DateTime Function() _now;

  DSocket({required this.sockets, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  int get sessionCount => _sessions.length;

  /// Admits a session. [localCookie] is what this side hands the peer.
  ///
  /// The cookie is drawn here by default rather than handed in, so that
  /// nothing above this module can accidentally reuse one across sessions.
  DSession open({
    required Uint8List callKey,
    required DCookie remoteCookie,
    required InternetAddress peerAddress,
    required int peerPort,
    DCookie? localCookie,
  }) {
    final local = localCookie ?? DCookie.generate();
    if (_sessions.containsKey(local.key)) {
      throw StateError('DSocket.open: cookie ${local.key.toRadixString(16)} '
          'is already admitted');
    }
    final session = DSession._(
      sockets,
      _forget,
      localCookie: local,
      remoteCookie: remoteCookie,
      callKey: callKey,
      peerAddress: peerAddress,
      peerPort: peerPort,
    );
    _sessions[local.key] = session;
    return session;
  }

  void _forget(DCookie cookie) => _sessions.remove(cookie.key);

  /// The Plane D branch of the demux. Returns whether this datagram is
  /// spoken for.
  ///
  /// Three steps, in this order, and the order is the whole point:
  ///
  /// 1. **Length.** A datagram whose length is neither 160 nor 1200 cannot
  ///    be a D-frame. One integer comparison, no allocation.
  /// 2. **Cookie.** The first eight bytes, read as an integer, into a hash
  ///    map. `O(1)`, no crypto, and the cost does not depend on how many
  ///    sessions this node holds — which is why placing it ahead of the MAC
  ///    families does not create the "how much do you know" leak E-95 closes
  ///    (that one is about *variable* work; see `link_demux.dart` for the
  ///    full derivation).
  /// 3. **AEAD.** Only now, and only under the one key the cookie named.
  ///
  /// **A cookie hit claims the datagram even when the AEAD fails.** The same
  /// rule the session branch follows: a unit claimed by an exact key is
  /// spoken for and ends in silence rather than travelling on. Here the key
  /// is exact in a strong sense — a delivery cell whose first eight bytes
  /// equal a live cookie has probability 2^-64 — so nothing legitimate is
  /// ever swallowed by it.
  ///
  /// **No answer, in either outcome.** Not on a miss, not on a forgery, not
  /// on a valid frame. That is the "no amplification surface" of §17.4, and
  /// it is measured as a byte count in `smoke_d_frame.dart`, not asserted
  /// here.
  bool claim(LinkDatagram datagram) {
    if (DFrameClass.ofWireSize(datagram.data.length) == null) return false;
    final session = _sessions[DCookie.keyOf(datagram.data)];
    if (session == null) return false;
    session._deliver(
        datagram.data, _now(), datagram.source, datagram.sourcePort);
    return true;
  }

  Future<void> close() async {
    final open = _sessions.values.toList();
    _sessions.clear();
    for (final s in open) {
      await s.close();
    }
  }
}
