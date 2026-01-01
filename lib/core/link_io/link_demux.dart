/// The UDP demux of E-95, and the session table E-104 keys it on.
///
/// **What E-95 actually settles, and what it does not.** It settles how a
/// receiver tells a *bare* datagram from a *disguised* one: both MAC
/// families are computed unconditionally and the disjunction stands only
/// after every call has returned. It does **not** settle how a receiver
/// tells a handshake flight from a data cell — those share the socket, are
/// both exactly 1,200 B, and carry no plaintext discriminator by
/// construction. E-104 settles that second question: the **source endpoint**
/// is the key of a session table.
///
/// **The order is the security-relevant part, and since E-122 it does not
/// live here.** It lives in `lib/core/link/inbound_order.dart`, because
/// `tcpOwnPort` brings a second receiving path and an order that has to hold
/// in two places eventually holds in one. This file calls
/// `LinkInboundOrder.classify` and hands it three thunks.
///
/// **Two devices carry that, and the second was missing until a hostile
/// review found it.** The thunks make the *table lookups* unreachable before
/// the MAC families have run. They did **not** stop any other
/// state-dependent work from being hoisted in front: with `_expire()` — which
/// walks the session table, so O(table size) — moved ahead of the call, the
/// entire corpus stayed green, and this header still claimed the opposite.
/// Since then `_expire` demands a `MacChecked`, a token only
/// `LinkInboundOrder` can mint; hoisting it is now a **compile error**, not
/// a silent regression. Guard 12
/// (`test/smoke/smoke_link_inbound_order.dart`) holds the rest of the order,
/// proven against three injected defects.
///
/// **What stays here is the storage, and that is deliberate.** On UDP the
/// source endpoint is the *lookup* key of the session table (E-104); on a
/// stream transport the connection is the session and the endpoint pair is
/// only a *display* key (E-116(4)). A demux generalised over a
/// transport-neutral source would have carried the UDP lookup rule into a
/// place where it is wrong — that proposal was measured and rejected under
/// E-122. Hence thunks, not a map.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/link/cell.dart';
import 'package:cleona/core/link/connect.dart';
import 'package:cleona/core/link/handshake.dart';
import 'package:cleona/core/link/link_kdf.dart';
import 'package:cleona/core/link/inbound_order.dart';
import 'package:cleona/core/link/node_keys.dart';
import 'package:cleona/core/link/replay_buffer.dart';
import 'package:cleona/core/link/transport_selector.dart';
import 'package:cleona/core/link_io/udp_sockets.dart';

/// Thrown when a wait marker is cleared before flight 2 arrived.
///
/// **Why it does not propagate to the caller.** `Link.connect` catches
/// exclusively `TimeoutException` — any other exception from `attempt`
/// tore down the ENTIRE cascade run. `UdpLinkConnector.attempt` therefore catches this
/// one itself and maps it to `LinkRefused`: the run
/// escalates immediately instead of throwing or waiting out the full stage.
final class LinkPendingAbandoned implements Exception {
  final String reason;
  const LinkPendingAbandoned(this.reason);
  @override
  String toString() => 'LinkPendingAbandoned($reason)';
}

/// One established link over UDP.
///
/// Sealing and opening happen here and nowhere else, under the session's
/// own `sendKey`/`recvKey` (E-107). No caller of [send] chooses a direction.
final class UdpLinkChannel implements LinkChannel {
  @override
  Uint8List get deliveryKey => LinkKdf.deriveDeliveryKey(_session.linkKey);

  @override
  Uint8List? get peerPosition => _session.peerPosition;

  @override
  final LinkTransport transport;

  /// The peer this channel talks to. Also its key in the session table.
  final LinkEndpoint peer;

  final LinkSession _session;
  final UdpSocketSet _sockets;
  final InternetAddress _address;
  final int _port;
  final void Function(LinkEndpoint) _onClose;

  /// The cell that brought this channel out of the shadow (B-7).
  ///
  /// **Why it has to be held.** A promoted shadow becomes known to
  /// its consumer only WITH the promotion — the channel goes onto
  /// [LinkDemux.accepted] in the same act. An `add` at this
  /// moment would fall into a broadcast stream without listeners and would be
  /// gone without replacement: `StreamController.broadcast` does not buffer. But exactly the
  /// cell that proves the partner is the first genuine payload of the
  /// new session. It is therefore held here and handed to the FIRST
  /// subscriber afterwards.
  Uint8List? _held;

  late final StreamController<Uint8List> _inbound =
      StreamController<Uint8List>.broadcast(onListen: _release);
  var _closed = false;

  UdpLinkChannel._({
    required this.transport,
    required this.peer,
    required this._session,
    required this._sockets,
    required this._address,
    required this._port,
    required this._onClose,
  });

  /// Seals [inner] under the send key of this link and puts it
  /// on the line.
  ///
  /// **Throws after [close], and that is intentional (B-6).** A closed
  /// channel previously kept sending undeterred — under the old send key,
  /// to a partner that had long since replaced the session. That is a
  /// writing zombie, and nobody would have noticed it.
  ///
  /// **Rejected: silently discard.** The justification for that was the
  /// §2.6 silence posture — and it is out of place here. §2.6 governs what
  /// a node does **on the line** when a check fails:
  /// "no reply, no error packet, no measurable time difference". A call
  /// on a closed channel is a **local** programming error, it
  /// never reaches the line and is visible to no network observer.
  /// Swallowing it hides exactly the class of error one wants to see.
  @override
  void send(Uint8List inner) {
    if (_closed) {
      throw StateError('link channel to ${peer.key} is closed');
    }
    _sockets.send(sealCell(inner, _session.sendKey), _address, _port);
  }

  @override
  Stream<Uint8List> get inbound => _inbound.stream;

  /// Opens one arriving cell without delivering it. `null` means it does not
  /// authenticate — the caller then does nothing at all (§2.6 posture:
  /// silence).
  ///
  /// Separate from delivering since B-7: the shadow branch must **know** whether
  /// a cell opens BEFORE it puts the channel into operation. Two callers,
  /// one decryption — the error path stays the same.
  Uint8List? _open(Uint8List cell) {
    try {
      return openCell(cell, _session.recvKey);
    } catch (_) {
      // Carries no information. No reply, no error packet, no log line —
      // a log line here would be the observable difference §2.6 forbids.
      return null;
    }
  }

  /// Opens one arriving cell and hands it to the consumer. Returns false when
  /// it does not authenticate.
  bool _deliver(Uint8List cell) {
    final inner = _open(cell);
    if (inner == null) return false;
    if (!_inbound.isClosed) _inbound.add(inner);
    return true;
  }

  /// Holds back [inner] until this channel has its first listener (B-7).
  void _hold(Uint8List inner) => _held = inner;

  /// Hands over the held cell as soon as someone listens.
  ///
  /// Via a microtask, not directly: an `add` from within `onListen`
  /// runs while the listener's registration is not yet complete,
  /// and Dart then does not deliver it.
  void _release() {
    final held = _held;
    if (held == null) return;
    _held = null;
    scheduleMicrotask(() {
      if (!_inbound.isClosed) _inbound.add(held);
    });
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _onClose(peer);
    if (!_inbound.isClosed) await _inbound.close();
  }
}

/// One entry of the session table (E-104).
final class _Session {
  final UdpLinkChannel channel;
  DateTime lastSeen;

  /// Has a cell ever opened under this entry? (V-B)
  ///
  /// As long as not, the short deadline applies. The responder creates its session
  /// already on a valid flight 1, **before** anything came back from the
  /// partner — whoever knows the recipient's `L_node` (as do
  /// **all its peers**, it is constant per node) and forges the source address
  /// of a third party thereby replaces that party's entry.
  bool delivered = false;

  /// A second, NOT YET PROVEN handshake under the same endpoint
  /// (B-7).
  ///
  /// It arises when a flight 1 hits an already **proven** session.
  /// It is not in the table, is not reported on `accepted`
  /// and gets nothing sent — it waits for a cell to open under
  /// it. Only then does it take the place of the old
  /// session. An attacker who can only forge an endpoint never gets
  /// beyond this state.
  ///
  /// There is at most ONE per entry, and it ages with the short
  /// deadline ([LinkDemux.pendingLifetime]) — the same consideration as for the
  /// wait markers: what grows by foreign address needs a cap.
  _Session? shadow;

  _Session(this.channel, this.lastSeen);

  /// Closes this entry together with its shadow. Every place that takes an entry
  /// out of the table calls this — otherwise the shadow would remain as an
  /// open `StreamController` that nobody can reach any more.
  Future<void> closeAll() async {
    final s = shadow;
    shadow = null;
    if (s != null) await s.channel.close();
    await channel.close();
  }
}

/// An outbound handshake waiting for its flight 2.
final class _Pending {
  final InitiatorPending pending;
  final LinkTransport transport;
  final InternetAddress address;
  final int port;
  final Completer<UdpLinkChannel> completer;
  final DateTime startedAt;

  /// The partner's static X25519 public key — the one quantity
  /// that makes the tie-breaker from V-A computable.
  final Uint8List peerStatic;

  /// Set when this side has lost the simultaneous-open case
  /// (V-A). The completer then waits for the responder session.
  bool yielded = false;

  /// Clears the marker without touching the completer (B-1).
  late final Timer timer;

  _Pending(this.pending, this.transport, this.address, this.port,
      this.completer, this.startedAt, this.peerStatic);
}

/// Routes every arriving datagram to a handshake, a session, or to silence.
final class LinkDemux {
  /// Looks up the static X25519 key for a position
  /// (decision C). If it is not set, every caller stays anonymous —
  /// exactly as before.
  StaticKeyLookup? lookupStatic;

  /// Lifetime of an idle session, and the cap on the table.
  ///
  /// **Both numbers are `ConnectState`'s, and deliberately so (E-89).** That
  /// table sits one layer up, is keyed on the *same* destination address,
  /// and E-89 already fixed one hour and 256 entries for it. Picking
  /// different figures here would mean two answers to one question in
  /// neighbouring code. An hour of idleness cannot hit a live link either:
  /// §4.3 exchanges a constant number of cells every tick and fills with
  /// cover when real material is missing, so a link that has been silent
  /// for an hour is not a link any more.
  static const Duration sessionIdleLifetime = Duration(hours: 1);

  /// The deadline of an entry under which a cell has **never** opened
  /// (V-B). It is the same short deadline as for a pending dial:
  /// one full cascade run.
  ///
  /// **Why staggered instead of one deadline for all.** A poisoned
  /// entry never delivers anything and thus ages out in seconds; a genuine
  /// session delivers immediately and gets the hour. Without the staggering
  /// an entry slipped in by a forger kept the genuine
  /// partner in the dark **for an hour**: its cells arrive under
  /// the same key, do not open, and `lastSeen` is only refreshed on
  /// authenticated delivery — it learns nothing and does
  /// not handshake anew.
  ///
  /// **What this is not:** a prevention. The replacement still
  /// takes place, only its damage is limited from an hour to seconds.
  /// It can only be prevented where the
  /// entry record is created — AP-3b.
  ///
  /// **Rejected: early discarding after repeated failure to open.** That
  /// would be an error counter at the most sensitive spot and would become a
  /// kill primitive: whoever can forge deliberately produces failures and
  /// throws out foreign sessions. Worse than the blackhole.
  static const int maxSessions = 256;

  /// Default deadline of an unanswered wait marker: **one full
  /// cascade run**.
  ///
  /// **Not the stage timeout, and that is a correction (V-C).** The
  /// previous form set the deadline exactly to `kLinkStageTimeout` = 1.5 s
  /// with the justification that a marker surviving the stage timeout
  /// belongs to a run nobody is waiting for any more. That was wrong:
  /// `stageTimeout` is a **parameter** of `Link.connect`, and if a
  /// caller raises it, the arriving, entirely legitimate flight 2 itself kills
  /// the marker it answers. Measured with `stageTimeout = 5 s` and
  /// a flight 2 after 2 s: `established = false` after 5 018 ms.
  ///
  /// The number is **derived, not set**: V4 §4.8 computes the full
  /// run itself — "4 × 1.5 s = **6 s**, **60 %** of one tick". A
  /// marker thus lives as long as a complete run can take.
  ///
  /// It remains a **hygiene upper limit**, not a delivery measure: it
  /// never decides the outcome of a handshake, it only clears the
  /// space. A caller who raises `stageTimeout` above the default raises
  /// this deadline along with it — for that it is injectable at the composition point.
  static const Duration defaultPendingLifetime =
      Duration(milliseconds: 4 * 1500);

  final UdpSocketSet sockets;
  final NodeKeys keys;
  final LinkReplayBuffer replay;
  final LinkLogSink log;

  /// Injected clock, so guards can run the table without waiting an hour.
  final DateTime Function() _now;

  final _sessions = <String, _Session>{};
  final _pending = <String, _Pending>{};
  final _accepted = StreamController<UdpLinkChannel>.broadcast();

  /// The Plane D branch (§17.4). `null` means: this node handles no
  /// calls, and the branch then costs one null check per datagram.
  ///
  /// **Bare `bool Function(LinkDatagram)?`, and that is the same
  /// consideration as for `UdpSocketSet.onWireBytesSent`.** A field of type
  /// `DSocket?` would be an import edge from the demux file to the
  /// D module — not a cycle, but the order below would then hang on a
  /// concrete class instead of a contract, and the guard could
  /// no longer hold it against a deliberately falsified version. The
  /// contract is: if the function returns `true`, the datagram is claimed
  /// and ends here.
  bool Function(LinkDatagram datagram)? dAdmission;

  /// Where the own address as observed by the partner is reported
  /// (§17.3). `null` means: this node collects no observations.
  ///
  /// **Bare function, not `ObservedAddressBook?`** — the same consideration
  /// as for [dAdmission] one line above: a field of the book's type
  /// would be an import edge from the demux file to `link_host.dart`, and
  /// that is a **cycle** (the host imports the demux). The contract
  /// is: here comes the statement of EXACTLY ONE partner, named by the
  /// endpoint under which he made it. Whoever collects them decides
  /// what several statements mean — the demux does not decide that.
  void Function(LinkEndpoint partner, ObservedAddress observed)? onObservedSelf;

  /// The last branch: a datagram that is NEITHER flight 1 nor flight 2 nor
  /// a cell of an existing session.
  ///
  /// ── WHAT FOR (S372, the directed entry) ────────────────────────────
  ///
  /// A node that only knows `ip:port` of a host can NOT
  /// talk to it: flight 1 is authenticated with the peer's `L_node`
  /// (`link_mac.dart`) and encrypted against its static
  /// keys — all three are in the entry record, which first has to be
  /// fetched. That is the chicken-and-egg situation of the cold start, and it was
  /// solved until S372 via a SECOND fixed port (41340, reachable from the
  /// whole internet). This branch replaces it: the
  /// record request arrives on the data port, sealed and in
  /// the same 1200 B class as everything else here
  /// (`tagline/entry_portal.dart`).
  ///
  /// ── WHY IT STANDS AT THE VERY END ─────────────────────────────────────
  ///
  /// E-95 forbids VARIABLE work BEFORE the MAC family; here work
  /// stands AFTER it, namely behind all three branches. A datagram
  /// that a session has claimed does not even get this far — which is
  /// right: whoever already has a session with us has our
  /// record and does not ask for it.
  ///
  /// `true` means "claimed"; `false` means silence as before.
  bool Function(LinkDatagram datagram)? onUnclaimed;

  StreamSubscription<LinkDatagram>? _subscription;

  /// The actually used deadline of the wait markers.
  final Duration pendingLifetime;

  LinkDemux({
    required this.sockets,
    required this.keys,
    required this.replay,
    required this.log,
    this.pendingLifetime = defaultPendingLifetime,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Links a peer opened towards this node.
  Stream<UdpLinkChannel> get accepted => _accepted.stream;

  int get sessionCount => _sessions.length;
  int get pendingCount => _pending.length;

  /// How many sessions have PROVEN themselves — under them at least
  /// once a cell has opened (V-B). Only these are protected against displacement
  /// by a mere flight 1 (B-7).
  int get deliveredSessionCount =>
      _sessions.values.where((s) => s.delivered).length;

  /// How many unproven second handshakes are currently waiting (B-7). In
  /// normal operation 0; permanently > 0 means that someone is injecting flights 1 under
  /// foreign source endpoints.
  int get shadowCount => _sessions.values.where((s) => s.shadow != null).length;

  void start() {
    _subscription ??= sockets.inbound.listen(onDatagram);
  }

  /// Registers an outbound handshake and returns the future of its channel.
  ///
  /// The slot is keyed on the endpoint the flight was sent to, because that
  /// is the endpoint flight 2 comes back from — flight 2 carries **no**
  /// `L_node` MAC (§2.6) and is therefore not recognisable on its own
  /// (E-111). Giving it one would have been a wire change to §2.6, which
  /// AP-3a freezes, and it would buy nothing this table does not already
  /// provide.
  Future<UdpLinkChannel> awaitFlight2({
    required LinkEndpoint target,
    required InitiatorPending pending,
    required LinkTransport transport,
    required InternetAddress address,
    required int port,
    required Uint8List peerStatic,
  }) {
    final completer = Completer<UdpLinkChannel>();
    final entry = _Pending(
        pending, transport, address, port, completer, _now(), peerStatic);
    // Own one-shot timer per marker (B-1). The previous form relied
    // on `_expire()` — and that ran exclusively on the arrival of a
    // datagram. A node that connects to dead partners and itself
    // receives nothing thus accumulated without limit: measured 30 markers after
    // 30 different dead targets, after 2 s idle still 30, and
    // a single incoming datagram swept them all away.
    //
    // The timer does NOT touch the completer. It thus decides nothing
    // about the outcome of the attempt — the timeout authority stays entirely
    // with `Link.connect` (§4.8, E-98), as the contract of
    // `UdpLinkConnector` demands.
    entry.timer = Timer(pendingLifetime, () {
      if (identical(_pending[target.key], entry)) _pending.remove(target.key);
    });
    // **One marker per target, and the displaced one is SERVED (B-5).** Two
    // simultaneous dials of the same target share this slot; the
    // previous form silently overwrote it, and the loser waited for
    // a completer nobody fulfilled any more — measured, it waited out the
    // full stage and then reported failure (1 521 ms against 42 ms of the
    // winner). Now it is cancelled immediately; `UdpLinkConnector.attempt`
    // maps that to `LinkRefused`, so the run escalates without delay
    // instead of waiting into the void for a stage.
    //
    // **Rejected: coalescing** — the second connect gets the future of the
    // first. That is the more elegant semantics and was built, but measured
    // wrong: a retry after a FAILED run then falls back
    // on its dead future as long as its marker still lives (up
    // to 6 s, V-C). The milestone smoke fails exactly on that — it dials
    // again after a deliberately falsified round. The demux cannot
    // know that the first caller has given up: `Link.connect`
    // discards its future without a signal. Coalescing would only be viable with
    // a cancellation signal from the frozen surface.
    final displaced = _pending[target.key];
    if (displaced != null) {
      displaced.timer.cancel();
      if (!displaced.completer.isCompleted) {
        displaced.completer.completeError(
            const LinkPendingAbandoned('superseded by a newer attempt'));
      }
    }
    _pending[target.key] = entry;
    return completer.future;
  }

  /// Drops a pending slot whose cascade stage has given up.
  void cancelPending(LinkEndpoint target) {
    // Cancel the timer too. Without this it stayed armed for up to a full deadline
    // and then ran into the void via the identity check —
    // without consequence, but it was the only one of the three exit points from
    // `_pending` that left its timer standing (`awaitFlight2` and `close`
    // cancel it). Found while building the lifecycle guard.
    _pending.remove(target.key)?.timer.cancel();
  }

  /// The classification of E-95 and E-104, in the order they must run.
  void onDatagram(LinkDatagram datagram) {
    // **A single clock reading per datagram (P-1).** The previous form read
    // `_now()` twice — once for the MAC check, once in
    // `_handleInit`. Exactly on an hour boundary the MAC could be re-evaluated on the
    // second read with a different epoch and a valid
    // `init` silently discarded. Measured: real, but without consequence — no
    // replay let through (the discard enters nothing into the ring buffer) and
    // no misrouting. A value that holds twice closes the edge
    // nonetheless, and it costs nothing.
    final now = _now();
    final origin = datagram.origin;

    // ── Branch 0: Plane D (§17.4) ────────────────────────────────────────
    //
    // **Why an O(1) lookup stands BEFORE the crypto, derived.**
    //
    // (1) Correctness, and that is the compelling part. Branch 3
    //     (`_claimAsCell`) looks up under the SOURCE ENDPOINT and
    //     claims the datagram **even if the cell does not
    //     open** — so it says there, with reason. The source endpoint is
    //     however a COARSER key than the cookie: E-64 gives a
    //     node exactly one port, the D-frame shares it with the
    //     delivery layer (see the header of `udp_sockets.dart`), so
    //     a call partner who is at the same time a sync partner has THE SAME
    //     `LinkEndpoint`. And a stream frame of the 1200 B class is
    //     byte for byte as long as a cell — §17.6 explicitly wants that
    //     ("byte-uniform with the cell size"). If Plane D stood behind
    //     branch 3, the session table would silently swallow every such frame.
    //     That is not an edge case: the nodes one
    //     phones with are exactly those one synchronises with.
    //     Measured in `test/smoke/smoke_d_frame.dart`, section 5, against
    //     the deliberately falsified order.
    //
    // (2) It is CONSTANT work, and E-95 only forbids variable work before it.
    //     A length comparison and a lookup in a hash table under
    //     a 64-bit key — the cost does not depend on how
    //     much state this node holds. Exactly that was the finding behind
    //     `MacChecked`: `_expire()` is O(table size) and once ran
    //     before it (6.2 µs empty against 145 µs with 4 096 entries). The
    //     cookie lookup does not have this property.
    //
    // (3) What it nonetheless reveals, and why it costs nothing. Whether a
    //     datagram hits a live cookie is distinguishable as computational
    //     effort. But: the cookie stands IN PLAINTEXT on the
    //     line. Whoever knows it has just seen it fly by — he
    //     learns nothing he does not already have. The leak that E-95
    //     closes is a different one: there the order reveals whether the
    //     node knows a partner that the observer does NOT know.
    //
    // (4) The price of the opposite direction. If Plane D stood at the end,
    //     every media frame would pay the full MAC family — at 50 frames/s per
    //     direction (§17.1) on a path that §17.1 explicitly keeps free
    //     of every resolution and route chain.
    //
    // **Open and not mine to decide:** E-95 phrases step 1
    // as "before everything else". This branch stands before it. The justification
    // above is complete, the SPEC is not — that belongs before the
    // owner as a proposal, not updated in the architecture document.
    if (dAdmission?.call(datagram) ?? false) return;

    // ── The order lives in `LinkInboundOrder` since E-122 ───────────
    //
    // It lives there because `tcpOwnPort` brings a second receive path
    // and an order that must hold in two places will at some point hold in
    // one. What stays here is the storage — that is transport-
    // specific and remains so: on UDP the source endpoint is the
    // lookup key (E-104), on a stream the connection is the
    // session and the endpoint pair only a display key (E-116(4)).
    // That is why this function passes thunks in and not a table.
    //
    // Only the bare MAC family is computable today. `MAC_hdr` of the
    // disguised one runs over `E2(eph_pub)`, and in a short-header
    // datagram this value is not present at all — an open point that hangs on the
    // specification of the disguise, not on AP-3a (V4 §2.6a, W-2).
    final branch = LinkInboundOrder.classify(
      keys: keys,
      unit: datagram.data,
      now: now,
      // **Hygiene only after the MAC.** `_expire()` once stood BEFORE it
      // and was thus variable work — O(table size) — before the
      // constant-time check; measured 6.2 µs with an empty table against
      // 145 µs with 4 096 entries. It was not a sender leak
      // (`removeWhere` runs over all entries, not over the
      // sender's), but the header sentence promises constant work before
      // variable work, and behind the MAC it costs nobody anything.
      afterMacCheck: (MacChecked proof) => _expire(now, proof),
      claimsAsFlight2: () => _claimAsFlight2(datagram, origin),
      claimsAsCell: () => _claimAsCell(datagram, origin, now),
    );

    if (branch == LinkInboundBranch.init) {
      final own = _pending[origin.key];
      if (own != null && !own.yielded) {
        // ── Simultaneous open (V-A) ────────────────────────────────
        //
        // A flight 1 from an endpoint to which WE are currently connecting ourselves.
        // Without a rule each side keeps the session of its self-initiated
        // handshake, and the two do not pair: measured, both report
        // success, both tables hold a session, and zero cells arrive
        // — until the idle expiry kicks in after an hour.
        //
        // Every SYMMETRIC rule fails. "The responder wins" lets
        // both keep their responder session, each of which stems from the
        // ephemeral key of the other side; "the initiator
        // wins" is the current state. The case can only be resolved
        // asymmetrically. TCP prescribes its own handling for it
        // (RFC 9293 §3.5, MUST-10); QUIC does not even know the case, because
        // it has fixed client and server roles — that is not a solution
        // but an avoidance, and it is not open to us.
        //
        // The comparison is computable because BOTH sides in exactly this
        // case hold the other side's material. From flight 1 alone it would
        // not be: it carries no static key of the initiator.
        if (_ownKeyWins(own.peerStatic)) {
          // We are the initiator. The other side's flight 1 is discarded;
          // it yields and answers ours.
          return;
        }
        // We yield: the responder session becomes the session.
        own.yielded = true;
      }
      _handleInit(datagram, origin, now);
      // Whatever came of it, this datagram is spoken for. A replay hit ends
      // here in silence and does NOT fall through to the table (E-79).
      return;
    }

    // Branches 2 and 3 have already executed the thunks. What remains is the
    // entry branch (S372); after that `unclaimed` means silence —
    // no response, no error, no log line.
    if (branch == LinkInboundBranch.unclaimed) {
      onUnclaimed?.call(datagram);
    }
  }

  /// Branch 2 of the order: an outgoing dial is waiting for its flight 2.
  ///
  /// Claims the datagram **only** if it really opens as the expected
  /// flight 2. **No swallowing (N-2):** the previous form turned around
  /// here and claimed already on the mere existence of a wait marker.
  /// A live marker thereby blinded the established session to the same
  /// endpoint — its data cells are not a flight 2, but still did
  /// not go on to branch 3. A redial onto a live link
  /// thus cost its cells until the marker expired.
  bool _claimAsFlight2(LinkDatagram datagram, LinkEndpoint origin) {
    final pending = _pending[origin.key];
    if (pending == null) return false;

    final session = LinkHandshake.openFlight2(pending.pending, datagram.data);
    if (session == null) return false;

    pending.timer.cancel();
    _pending.remove(origin.key);

    // §17.3: the partner has mirrored back under which address it
    // saw us arrive. It is reported WITH the partner who
    // made it — an observation without an author could later no longer
    // be held against a second one. `null` (old state, or a partner
    // who mirrors nothing) reports nothing at all.
    final observed = session.observedSelf;
    if (observed != null) onObservedSelf?.call(origin, observed);

    final channel = _channel(
        origin, session, pending.transport, pending.address, pending.port);
    _remember(origin, channel);
    if (!pending.completer.isCompleted) {
      pending.completer.complete(channel);
    }
    return true;
  }

  /// Branch 3 of the order: an established link.
  ///
  /// Claims the datagram as soon as a session stands under this key
  /// — **even if** the sealed cell does not open. A
  /// cell whose AEAD fails is claimed and ends in silence; it
  /// does not move on.
  bool _claimAsCell(
      LinkDatagram datagram, LinkEndpoint origin, DateTime now) {
    final session = _sessions[origin.key];
    if (session == null) return false;

    if (session.channel._deliver(datagram.data)) {
      session.lastSeen = now;
      // From here on the full hour applies (V-B): something has opened under this entry,
      // so it is not a slipped-in shell.
      session.delivered = true;
      return true;
    }

    // ── B-7: the shadow gets its chance ───────────────────────
    //
    // The cell did not open under the table entry. If an
    // unproven second handshake stands under the same endpoint, EXACTLY
    // THIS is the moment in which it can prove itself: a partner that
    // has restarted speaks under new keys from the old
    // endpoint.
    //
    // **Why this does not violate E-95.** E-95 forbids variable
    // work BEFORE the MAC family; here work stands after it. And it is
    // capped: at most one shadow per entry, at most one
    // additional AEAD opening per cell, and only while the shadow
    // lives (short deadline).
    final shadow = session.shadow;
    if (shadow == null) return true;
    final inner = shadow.channel._open(datagram.data);
    if (inner == null) return true;

    // PROVEN. The shadow takes the place of the old session.
    session.shadow = null;
    shadow
      ..lastSeen = now
      ..delivered = true;
    _sessions[origin.key] = shadow;
    // CLOSE the old one, don't just forget it: its consumer needs
    // its `onDone` (B-2). `close()` runs via [_forget], and that
    // only removes on identity — the just registered shadow stays
    // in place (B-3).
    unawaited(session.channel.close());
    // FIRST HOLD, THEN REPORT: the consumer learns of the channel with
    // this line and only subscribes to it afterwards.
    shadow.channel._hold(inner);
    if (!_accepted.isClosed) _accepted.add(shadow.channel);
    return true;
  }

  /// Does the own static node key win the tie-breaker (V-A)?
  ///
  /// Lexicographic byte comparison, the smaller counts as initiator. The
  /// direction is arbitrary; all that matters is that BOTH sides
  /// compare the same pair and the same one wins.
  bool _ownKeyWins(Uint8List peerStatic) {
    final own = keys.nX25519Public;
    final n = own.length < peerStatic.length ? own.length : peerStatic.length;
    for (var i = 0; i < n; i++) {
      if (own[i] != peerStatic[i]) return own[i] < peerStatic[i];
    }
    return own.length < peerStatic.length;
  }

  void _handleInit(LinkDatagram datagram, LinkEndpoint origin, DateTime now) {
    // Fresh 32 B per handshake. `ElligatorFFI.keyPair` wipes the buffer,
    // so it must not be reused — a seed drawn once and kept would repeat
    // the responder's ephemeral key across handshakes.
    final seed = SodiumFFI().randomBytes(32);

    final result = LinkHandshake.handleFlight1(
      lookupStatic: lookupStatic,
      keys: keys,
      replay: replay,
      flight1: datagram.data,
      respSeed: seed,
      now: now,
      // §17.3 "observed address" instead of STUN. Here — and ONLY here — is the
      // source address known at all: it comes from the operating system with the
      // datagram, not from its content. `lib/core/link/` must not open `dart:io`
      // (header of `connect.dart`), therefore it is brought into the
      // transport-neutral form at THIS layer boundary and passed on as a value,
      // instead of handing `InternetAddress` down.
      observed: _observe(datagram),
    );
    if (result == null) return; // MAC ok but replayed, or later failure

    final address = datagram.source;
    sockets.send(result.flight2, address, datagram.sourcePort);

    final channel = _channel(
        origin,
        result.session,
        const LinkTransport(TransportStage.udpOwnPort, Disguise.bare),
        address,
        datagram.sourcePort);

    // ── B-7: PROVE BEFORE DISPLACING ────────────────────────────────
    //
    // If a session already stands under this endpoint, under which a cell
    // has once OPENED, it is no longer replaced by a mere flight 1.
    //
    // **The attack that forces this (S375, P3/1).** A flight 1 needs
    // only the recipient's public node material (RL-13/B-18) and
    // a forged source address; the attacker never sees flight 2 and
    // does not need it. Until now `_remember` registered the new session
    // unconditionally and closed the old one (B-2) — and this `close()`
    // runs in the node above in `V41Node._dropPartner`, thus takes
    // `readiness.forgetPartner` and `delivery.pending.forgetPartner` along.
    // A datagram of 1200 B thereby closed the live session of a
    // third party; repeated every few seconds, the victim stayed permanently
    // `searching`. V-B only limited the lifetime of the slipped-in
    // shell, not the `close()` of the genuine session.
    //
    // **Rejected: displace only with the same `peerPosition`.** The
    // position is a CLAIM in flight 1. `LinkHandshake._tryKeySet`
    // looks it up in the store and sets it without demanding
    // proof — the penalty for a lie is an unusable
    // key, not a rejection (that is intended there: a
    // rejection would be an oracle about whom this node knows).
    // Positions are public (RL-13). The attacker thus simply claims the
    // victim's as well, and the rule protected nothing. Measured in
    // `test/smoke/smoke_link_session_displacement.dart`, section 2.
    //
    // **Rejected: don't register at all.** That would be safe and would have
    // walled up the RESTART path. Since S374 the device port is stable, a
    // restarted partner thus comes back under THE SAME endpoint;
    // its cells do not open under the old entry, and
    // `lastSeen` only refreshes on authenticated delivery — it
    // would be unreachable until the idle expiry ([sessionIdleLifetime], one hour).
    // A restart is not an edge case.
    //
    // Therefore: the new handshake waits as a SHADOW. Flight 2 is already
    // out (§2.6 knows no visible rejection), but the channel
    // goes neither into the table nor onto `accepted`. It takes the
    // place of the old session exactly when a cell opens under it
    // — see [_claimAsCell].
    final standing = _sessions[origin.key];
    if (standing != null && standing.delivered) {
      final before = standing.shadow;
      standing.shadow = _Session(channel, now);
      // At most one. The displaced one is closed (B-2) — its
      // `close()` runs via [_forget] and does not touch the table entry,
      // because it is not identical to it (B-3).
      if (before != null) unawaited(before.channel.close());
      // NO `_accepted.add`, and the own wait marker is NOT
      // fulfilled either: a channel that has not proven itself does not go into
      // operation. A waiting own dial runs into its stage
      // timeout and escalates — the same picture as with a lost
      // flight 2, and the timeout authority stays with `Link.connect` (E-98).
      return;
    }

    _remember(origin, channel);

    // If this side has lost the simultaneous case (V-A), the
    // responder session fulfils the own connect: it reports success with this
    // channel instead of waiting for a flight 2 that will no longer come.
    final own = _pending[origin.key];
    if (own != null && own.yielded) {
      own.timer.cancel();
      _pending.remove(origin.key);
      if (!own.completer.isCompleted) own.completer.complete(channel);
      return;
    }

    if (!_accepted.isClosed) _accepted.add(channel);
  }

  /// The source address of the datagram as a transport-neutral value.
  ///
  /// `null` if the operating system delivers something that is not an address —
  /// this has never been observed, but a throw here would tear down the receive path
  /// of a node on a foreign datagram. Without an observation the
  /// handshake is still completed, just without a mirror.
  static ObservedAddress? _observe(LinkDatagram datagram) {
    try {
      return ObservedAddress.fromRaw(
          datagram.source.rawAddress, datagram.sourcePort);
    } on ArgumentError {
      return null;
    }
  }

  UdpLinkChannel _channel(LinkEndpoint peer, LinkSession session,
      LinkTransport transport, InternetAddress address, int port) {
    // `late final` plus closure: the channel needs itself in its
    // own close callback, so that `_forget` can remove by IDENTITY
    // and not by key.
    late final UdpLinkChannel channel;
    channel = UdpLinkChannel._(
      transport: transport,
      peer: peer,
      session: session,
      sockets: sockets,
      address: address,
      port: port,
      onClose: (p) => _forget(p, channel),
    );
    return channel;
  }

  /// Removes the table entry of [peer] — but only if [channel]
  /// really stands there.
  ///
  /// **Why the identity check (B-3).** Two sessions to the same
  /// endpoint carry the same key; that is intended by E-104,
  /// because a NAT rebind MUST supersede the old session. The previous form
  /// removed by key — and thereby closing an
  /// OUTDATED channel threw the LIVE session out of the table. Measured:
  /// afterwards `sessionCount` 1 → 0, and the partner's next cell found
  /// no session any more and vanished into silence.
  ///
  /// **The shadow falls with it (B-7).** If the entry is removed because its
  /// own channel was closed, there is nobody left who could promote a
  /// waiting shadow — it would remain as an open
  /// `StreamController`. The partner handshakes anew instead,
  /// and the next flight 1 then finds an empty slot.
  void _forget(LinkEndpoint peer, UdpLinkChannel channel) {
    final current = _sessions[peer.key];
    if (current != null && identical(current.channel, channel)) {
      _sessions.remove(peer.key);
      final shadow = current.shadow;
      current.shadow = null;
      if (shadow != null) unawaited(shadow.channel.close());
    }
  }

  /// Registers [channel] as the session of [peer].
  ///
  /// **Every exit from the table closes its channel (B-2).** There are
  /// four of them — overwrite and LRU eviction here, idle expiry in
  /// [_expire], full teardown in [close]. Previously none closed: the
  /// `StreamController` of the displaced channel stayed open, and its
  /// consumer got no `onDone`, thus waited silently for data that
  /// had long since gone to the new channel.
  ///
  /// Closing here has only been safe since B-3: `close()` runs via
  /// [_forget], and that only removes if the table entry is identical to
  /// the closing channel — the just registered new one stays in place.
  void _remember(LinkEndpoint peer, UdpLinkChannel channel) {
    final displaced = _sessions[peer.key];
    _sessions[peer.key] = _Session(channel, _now());
    if (displaced != null && !identical(displaced.channel, channel)) {
      // Together with the shadow (B-7) — the displaced entry is gone, its
      // waiting second handshake thus has no place any more.
      unawaited(displaced.closeAll());
    }
    if (_sessions.length <= maxSessions) return;
    // Least recently seen goes first — the same eviction E-89 gives the
    // neighbouring table.
    // On a TIE `a` wins, i.e. the one registered first. The
    // previous form (`a.isBefore(b) ? a : b`) took `b` on equal `lastSeen`
    // — the LATER entry — and thereby evicted the youngest
    // instead of the oldest, i.e. the opposite of its own promise. Under
    // `DateTime.now()` this does not show, because microseconds and the
    // handshake work in between practically rule out a tie;
    // under an injected or coarsely resolving clock it very much does. Found
    // while building the lifecycle guard.
    final oldest = _sessions.entries
        .reduce((a, b) => b.value.lastSeen.isBefore(a.value.lastSeen) ? b : a);
    final evicted = _sessions.remove(oldest.key);
    if (evicted != null) unawaited(evicted.closeAll());
  }

  /// Clears expired **sessions**. Wait markers are cleared by their own timer
  /// (B-1); two mechanisms for the same task would be one too many.
  /// Clears expired entries.
  ///
  /// **Requires the [MacChecked] proof, and that is the point.** This
  /// work is O(table size) and therefore must not run before the
  /// constant-time check (§2.6, E-95). Previously that was a
  /// promise in the file header; now it is a type condition — `_expire(now)`
  /// before `classify` **no longer compiles**.
  void _expire(DateTime now, MacChecked _) {
    final stale = <_Session>[];
    _sessions.removeWhere((_, s) {
      final limit = s.delivered ? sessionIdleLifetime : pendingLifetime;
      final gone = now.difference(s.lastSeen) > limit;
      if (gone) stale.add(s);
      return gone;
    });
    for (final s in stale) {
      unawaited(s.closeAll());
    }
    // Shadows age with the SHORT deadline (B-7), regardless of how
    // long their entry has stood. A shadow that has not proven itself in a full
    // cascade run is no longer one — it is either
    // slipped in or belongs to a caller who has long since given
    // up. Without this line a forgery would remain until the end of the
    // session and occupy the partner's one shadow slot.
    for (final s in _sessions.values) {
      final shadow = s.shadow;
      if (shadow == null) continue;
      if (now.difference(shadow.lastSeen) <= pendingLifetime) continue;
      s.shadow = null;
      unawaited(shadow.channel.close());
    }
  }

  /// Shuts down the demux.
  ///
  /// **Channels are closed, wait markers served (B-2).** Previously
  /// this method only emptied the two tables: no channel got a
  /// `done`, and an `attempt` running at stop time waited
  /// **forever** — the connector deliberately waits without its own timeout,
  /// so there was nothing that would have woken it.
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;

    // Together with the shadow (B-7): a never promoted channel also keeps a
    // `StreamController` open and owes its waiter a `done`.
    final entries = _sessions.values.toList();
    _sessions.clear();
    for (final e in entries) {
      await e.closeAll();
    }

    final waiting = _pending.values.toList();
    _pending.clear();
    for (final p in waiting) {
      p.timer.cancel();
      if (!p.completer.isCompleted) {
        p.completer.completeError(
            const LinkPendingAbandoned('demux shut down'));
      }
    }

    if (!_accepted.isClosed) await _accepted.close();
  }
}
