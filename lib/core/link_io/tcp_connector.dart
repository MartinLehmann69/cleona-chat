/// Link I/O — the outbound side of escalation stage `tcpOwnPort` (E-116,
/// E-121).
///
/// **What this file is.** A [LinkConnector] for one stage: it opens a TCP
/// connection to the peer's data port, runs the §2.6 handshake over it, and
/// reports the outcome. The listening side is **not** here yet: of the three
/// deadlines E-123 left open, (i) and (ii) are settled and built here — see
/// [TcpLinkChannel.idleLifetime] — while (iii), the gathering rule for the
/// first four bytes of the switch, belongs to the listener and is still open.
///
/// **Why the connection and not a datagram.** §2.1a carries `tcpOwnPort` as
/// the second rung of the ladder in §4.8, for networks that block UDP
/// outbound but permit arbitrary TCP ports. It uses the **same port number**
/// as UDP (§2.1a; E-60 gives the entry record exactly one port for both
/// protocols), and the connection stays open after the handshake and carries
/// the cell stream (E-116(5)) — one connection per cell would be neither a
/// constant rate nor inconspicuous (§4.3).
///
/// **Cell delimitation on the stream (E-116(1)).** Fixed 1,200-byte blocks,
/// back to back, no separator. A length frame would have to be readable
/// *before* decryption and would therefore be plaintext, which §2.1 forbids;
/// a length frame *inside* the AEAD is structurally impossible, because
/// whoever wants to decrypt would need to know the length already. Both wire
/// units are exactly 1,200 B anyway.
///
/// **What this connector must NOT do: impose a timeout of its own.** The
/// stage timeout belongs to `Link.connect` (§4.8), and a second timeout here
/// would silently take that decision away from the layer that owns it
/// (`connect.dart`, `LinkConnector` contract). The cleanup timer below is
/// **not** such a timeout — see [TcpLinkConnector.cleanupLifetime].
library;

import 'package:cleona/core/link/node_keys.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/link/cell.dart';
import 'package:cleona/core/link/connect.dart';
import 'package:cleona/core/link/handshake.dart';
import 'package:cleona/core/link/link_kdf.dart';
import 'package:cleona/core/link/transport_selector.dart';
import 'package:cleona/core/link_io/link_demux.dart' show LinkDemux;
import 'package:cleona/core/link_io/link_host.dart' show PeerNodeMaterial;

/// The OS errors that mean "explicitly refused" and escalate **at once**,
/// without waiting the stage out (E-116(6), §4.8).
///
/// **Why a table and not a name.** Dart surfaces the raw platform code in
/// `SocketException.osError.errorCode`, and the numbers differ per platform.
/// That they are raw is not an assumption: the Dart SDK's own connect path
/// branches on `Platform.isWindows ? 10060 /* WSAETIMEDOUT */ : 110
/// /* ETIMEDOUT */` when it synthesises a timeout — a branch that would be
/// pointless if the field were normalised. Matching on `osError.message`
/// instead is **not** an option: it comes from `strerror(3)` on POSIX and
/// from `FormatMessage` on Windows, where it is localised.
///
/// **`ETIMEDOUT` is deliberately absent.** E-116(6) reads the list in §4.8
/// faithfully: "administratively prohibited" does not arrive on Linux as an
/// error of its own but through `icmp_err_convert[]` — `ICMP_PKT_FILTERED`
/// and `ICMP_HOST_ANO` become `EHOSTUNREACH`, `ICMP_NET_ANO` becomes
/// `ENETUNREACH`. `ETIMEDOUT` means "the network is silent" and belongs in
/// the stage timeout, not in the refusal.
///
/// **Provenance per entry, because two of them are not verified here.**
/// Linux and Darwin values were taken from this tree, where they had been
/// established by measurement against the running platform:
/// `lib/core/network/android_udp_sender.dart` ("-101 ENETUNREACH, -113
/// EHOSTUNREACH, -111 ECONNREFUSED") and
/// `lib/core/network/ios_udp_sender.dart` ("EHOSTUNREACH = 65,
/// ECONNREFUSED = 61", and `e == 51 // ENETUNREACH`), the latter carrying
/// its own warning not to match Linux numbers against Darwin errno. Of the
/// Windows values only **`WSAEHOSTUNREACH` = 10065** came from this tree
/// (`lib/core/network/lan_discovery.dart`).
///
/// **All three source files are gone since the CUT of 2026-08-31**
/// (`lib/core/network/` holds zero files, measured 2026-09-03). The
/// provenance is therefore a HISTORICAL one — the numbers below were
/// measured, but the measurement no longer stands next to them in the
/// tree; it stands in the history. That is a reason to keep this
/// paragraph, not to shorten it.
///
/// The other two are taken from
/// Microsoft's published Winsock error codes (`winsock2.h`:
/// `WSAECONNREFUSED` = 10061, `WSAENETUNREACH` = 10051) and are **not
/// verified against a running Windows build** — flagged rather than
/// smoothed over, because the working rule of this project is that a
/// platform is not covered until it has been run there.
const Map<String, Set<int>> kLinkRefusedErrno = <String, Set<int>>{
  // ECONNREFUSED 111, EHOSTUNREACH 113, ENETUNREACH 101.
  'linux': <int>{111, 113, 101},
  // ECONNREFUSED 61, EHOSTUNREACH 65, ENETUNREACH 51.
  'macos': <int>{61, 65, 51},
  'ios': <int>{61, 65, 51},
  // Android is Linux.
  'android': <int>{111, 113, 101},
  // WSAECONNREFUSED 10061 (unverified), WSAEHOSTUNREACH 10065 (in tree),
  // WSAENETUNREACH 10051 (unverified).
  'windows': <int>{10061, 10065, 10051},
};

/// Classifies an OS error: a refusal, or silence.
///
/// Returns the [LinkRefused] to report, or **`null` for silence**.
///
/// **Why `null` and not a third `LinkAttempt` member.** `LinkAttempt` is
/// sealed and has exactly two members, deliberately: "silence is the absence
/// of any report, and it is expressed by a future that has not completed"
/// (`connect.dart`, `LinkAttempt`). A connector that answered `LinkRefused`
/// on a non-fatal error would escalate the run **at once** on an error §4.8
/// wants waited out — `ETIMEDOUT` above all, which means "the network is
/// silent" and belongs in the stage timeout.
///
/// **Top-level and pure so that a guard can reach it.** The behavioural path
/// through a real socket cannot produce a non-fatal `SocketException` on
/// demand — a peer that accepts and then stays quiet raises none at all —
/// so a guard that only drives the network path is blind to a defect that
/// turns silence into a refusal. Measured: with the classification inlined,
/// exactly that defect stayed green.
LinkRefused? classifyLinkSocketError(SocketException e, LinkEndpoint target,
    {String? platform}) {
  if (isLinkRefusedErrno(e, platform: platform)) {
    return LinkRefused('${target.key}: ${e.osError}');
  }
  return null;
}

/// Is [e] an explicit refusal on this platform (E-116(6))?
bool isLinkRefusedErrno(SocketException e, {String? platform}) {
  final code = e.osError?.errorCode;
  if (code == null) return false;
  final table = kLinkRefusedErrno[platform ?? Platform.operatingSystem];
  if (table == null) return false;
  // The native senders in this tree report errno negated; `SocketException`
  // does not. Both spellings are accepted so a caller that hands one on does
  // not silently fall through to "silence".
  return table.contains(code) || table.contains(-code);
}

/// One established link over TCP.
///
/// Sealing and opening happen here and nowhere else, under the session's own
/// `sendKey`/`recvKey` (E-107). No caller of [send] chooses a direction.
final class TcpLinkChannel implements LinkChannel {
  @override
  Uint8List get deliveryKey => LinkKdf.deriveDeliveryKey(_session.linkKey);

  @override
  Uint8List? get peerPosition => _session.peerPosition;

  @override
  final LinkTransport transport;

  /// The peer this channel talks to. On a stream transport the **connection**
  /// is the session (E-116(4)); this endpoint is the *display* key, not a
  /// lookup key, and nothing here indexes on it.
  final LinkEndpoint peer;

  /// Called when this channel is finally closed — exactly once.
  ///
  /// ── WHAT FOR, AND WHY THERE WAS A LEAK WITHOUT IT ───────────────────────
  ///
  /// On the LISTENING side the bookkeeping of a connection ends with
  /// `LinkAdmission.release`. After a successful handshake however
  /// `_Conn._end` **no longer** calls it — it sets `_done` and hands the
  /// socket over to this channel. Without this report the
  /// admission would never learn of the end of a session, and the deadline of pot B
  /// (`LinkAdmission.knownLifetime`) would never start to run: the entry
  /// would remain for the whole process lifetime.
  ///
  /// Deliberately a bare callback and not a reference to
  /// `LinkAdmission`: an admission rule exists only on a stream,
  /// and the channel should not have to know anything about it.
  void Function()? onClosed;

  final LinkSession _session;
  final Socket _socket;

  /// The opened cells of this link.
  ///
  /// **The stream only starts when someone listens — and that is a fix,
  /// not polish.** A broadcast controller without subscribers
  /// **discards**; measured: `add(1)` before `listen`, `add(2)` after it yields
  /// `[2]`. The channel however is only handed out by `attempt` after
  /// its constructor has run — a subscriber is at this point
  /// structurally impossible. Every cell that opened before was thus
  /// **certainly** lost, not merely endangered in a race. Exactly
  /// that hit the `carryOver` path, i.e. the case for which E-116(5) keeps the
  /// stream open: if the partner puts flight 2 and its first cell into
  /// **one** write, the cell never arrived.
  ///
  /// **Why pausing and not buffering.** An own buffer
  /// would need an upper limit, and that would be a set number without
  /// derivation — this layer has enough of those. Instead the
  /// socket subscription stays **paused** until the first subscriber is there: then
  /// nothing backs up with us, but in the receive window of the operating
  /// system, which exists for exactly this purpose. Bytes already lying in the
  /// gather buffer (the `carryOver`) are handed over on start-up.
  ///
  /// Price, honestly named: a caller who accepts the channel and
  /// **never** subscribes leaves the connection standing — visible until the
  /// idle deadline clears it. That is better than buffering silently.
  late final StreamController<Uint8List> _inbound =
      StreamController<Uint8List>.broadcast(onListen: _start);

  /// The gathering buffer of E-116(1): bytes that have arrived but do not
  /// yet make a whole 1,200-byte block.
  ///
  /// It is bounded by construction — every complete block is consumed at
  /// once, so it never holds 1,200 bytes or more. **What is not bounded is
  /// how long a partial block may stand**; that deadline is E-123(i) and is
  /// deliberately not invented here. Until it is decided, a peer that sends
  /// 1,199 B and falls silent holds this buffer for as long as it holds the
  /// connection — the price §2.1a names for the gathering buffer, uncapped.
  final _gather = BytesBuilder(copy: false);

  var _closed = false;

  /// When a cell last **opened** under this channel.
  ///
  /// Refreshed only on authenticated delivery, not on
  /// arriving bytes — otherwise a partner sending garbage would keep the
  /// channel alive arbitrarily long. The same rule as on the UDP side,
  /// where `lastSeen` is likewise only set in the success branch.
  DateTime _lastOpened;

  /// Injected clock, so that a guard can set the idle deadline
  /// without waiting an hour.
  ///
  /// **Why a FUNCTION and not a point in time.** The first version
  /// took `required DateTime now` — a single value at construction —
  /// and then read the **wall clock** twice (`:352`, `:368`). The
  /// remaining-deadline calculation was thus only testable by real waiting, and the channel
  /// broke with the pattern the rest of the V4 line maintains
  /// (`link_demux.dart`: `final DateTime Function() _now`, fed at the
  /// composition point; `admission.dart` even as a mandatory parameter without
  /// fallback). An object with its own time calculation needs a clock that
  /// keeps going — not a point in time that stands still.
  final DateTime Function() _now;

  /// Idle deadline of the channel — **one hour, transport-independent** (E-123).
  ///
  /// The number is not new and is not set anew here either: it is that
  /// of the UDP path (`LinkDemux.sessionIdleLifetime`), and its derivation
  /// names no transport — §4.3 exchanges a **constant** number of cells per tick
  /// and fills with cover when genuine material is missing; a link
  /// that was silent for an hour is no longer one. That holds on a stream
  /// unchanged.
  ///
  /// **This also settles the incomplete block (E-123(i)).**
  /// §2.1a assigns it no own deadline but says literally that it
  /// blocks its buffer "until that **connection** times out" — the
  /// deadline carrier is the connection, and that is this deadline. The buffer
  /// itself does not grow (see [_gather]); whoever sends 1 199 B and
  /// falls silent refreshes nothing and ages like one who sends nothing at all.
  /// An own, shorter deadline would moreover be a signature:
  /// it would make the teardown time depend on the **byte count** — exactly what
  /// E-83 forbids with "a teardown immediately after exactly 48 bytes read would
  /// itself be a signature".
  ///
  /// **What does NOT migrate here: the staggered deadline from E-114.** It
  /// keeps an entry short until the first cell has opened under it,
  /// and defends against an attacker who **forges a source address**
  /// and thus replaces the entry of a third party. On a stream this
  /// attacker is doubly excluded — the three-way handshake fails for him,
  /// and according to E-116(4) the connection is the session, so there is no
  /// endpoint-keyed slot to displace at all. The test "has
  /// something already opened here?" **separates nothing on a stream**: whoever conducts the
  /// handshake necessarily receives flight 2, thus holds the
  /// session key and can seal a valid cell at any time.
  /// "Creating an entry" and "proving an entry" are the same act
  /// of the same principal. The staggering is therefore dropped —
  /// **moot, not wrong**.
  final Duration idleLifetime;

  Timer? _idle;

  /// **The subscription of the handshake, not a new one.**
  ///
  /// A Dart `Socket` is a single-subscription stream: whoever subscribed to it during
  /// the handshake cannot subscribe to it a second time afterwards
  /// — `Bad state: Stream has already been listened to`. And the
  /// obvious way out, cancelling beforehand, is the worse error:
  /// a `cancel()` flips `_controller.hasListener`, whereupon the VM
  /// **shuts down the receive direction of the raw socket**. This tree has
  /// already learned that expensively once — `lib/core/network/transport.dart`
  /// carried the finding including "verified live" and the cancel-based
  /// previous version that made every sniffed TLS connection fail.
  /// **The file was deleted with the CUT of 2026-08-31** (measured on
  /// 2026-09-03: `lib/core/network/` has zero files); the finding lies
  /// only in the history now. It applies nonetheless — it is a property
  /// of the Dart VM, not of the deleted file.
  ///
  /// The connector therefore passes its subscription on, and here
  /// only the handler is swapped ([StreamSubscription.onData]).
  StreamSubscription<Uint8List>? _sub;

  /// The channel of the **responder** side, built by the listener.
  ///
  /// Own entry point, because Dart privacy applies per file and the listener
  /// lies in a different one. In substance the same channel: the role is
  /// already in the [LinkSession] (E-107, `sendKey`/`recvKey`), here
  /// nothing is chosen.
  factory TcpLinkChannel.accepted({
    required LinkTransport transport,
    required LinkEndpoint peer,
    required LinkSession session,
    required Socket socket,
    required StreamSubscription<Uint8List> subscription,
    DateTime Function()? now,
    Duration idleLifetime = LinkDemux.sessionIdleLifetime,
    Uint8List? carryOver,
    void Function()? onClosed,
  }) =>
      TcpLinkChannel._(
        transport: transport,
        peer: peer,
        session: session,
        socket: socket,
        subscription: subscription,
        now: now,
        idleLifetime: idleLifetime,
        carryOver: carryOver,
      )..onClosed = onClosed;

  TcpLinkChannel._({
    required this.transport,
    required this.peer,
    required LinkSession session,
    required Socket socket,
    required StreamSubscription<Uint8List> subscription,
    DateTime Function()? now,
    this.idleLifetime = LinkDemux.sessionIdleLifetime,
    Uint8List? carryOver,
    // ignore: prefer_initializing_formals
  })  : _session = session,
        // ignore: prefer_initializing_formals
        _socket = socket,
        _sub = subscription,
        _now = now ?? DateTime.now,
        _lastOpened = (now ?? DateTime.now)() {
    _armIdle();
    if (carryOver != null && carryOver.isNotEmpty) _gather.add(carryOver);
    subscription
      ..onData(_onBytes)
      ..onDone(() => unawaited(close()))
      ..onError((Object _) => unawaited(close()))
      // **Paused until someone listens.** See [_inbound].
      ..pause();
  }

  /// Runs as soon as the first subscriber is there — and exactly once.
  ///
  /// `onListen` fires on a broadcast controller every time the
  /// listener count goes from 0 to 1; a caller who unsubscribes and
  /// subscribes again triggers it again. The stream must not notice any of that.
  void _start() {
    if (_started) return;
    _started = true;
    _drain();
    _sub?.resume();
  }

  var _started = false;

  void _onBytes(Uint8List chunk) {
    _gather.add(chunk);
    _drain();
  }

  /// Consumes every whole 1,200-B block the buffer holds.
  ///
  /// A chunk may carry several blocks, or a block may span several chunks;
  /// on a stream neither is exceptional, and both have to work on the first
  /// byte that arrives.
  void _drain() {
    if (_gather.length < kCellSize) return;
    final all = _gather.takeBytes();
    var offset = 0;
    while (all.length - offset >= kCellSize) {
      _deliver(Uint8List.sublistView(all, offset, offset + kCellSize));
      offset += kCellSize;
    }
    if (offset < all.length) {
      _gather.add(Uint8List.sublistView(all, offset));
    }
  }

  /// Opens one arriving cell. A cell that does not authenticate carries no
  /// information: no reply, no error packet, no log line — a log line here
  /// would be the observable difference §2.6 forbids.
  ///
  /// **What this does not do, and it is a gap, not a decision.** On a
  /// datagram transport a cell with a broken tag is harmless: the next
  /// datagram is a fresh unit. On a stream the block boundary may have been
  /// lost, in which case every following cell on this connection is lost
  /// too, and silence does not heal it. Whether the connection falls in that
  /// case is written in no document (§4d.15, finding 14).
  void _deliver(Uint8List cell) {
    Uint8List inner;
    try {
      inner = openCell(cell, _session.recvKey);
    } catch (_) {
      return;
    }
    _lastOpened = _now();
    if (!_inbound.isClosed) _inbound.add(inner);
  }

  /// Checks the idle deadline and re-arms itself.
  ///
  /// **One waking timer, not a timer per cell.** At a constant cell rate
  /// (§4.3) re-setting on every cell would be the most frequent timer operation
  /// of the whole node; instead this one wakes once per deadline and
  /// compares against [_lastOpened]. It only touches the channel when the deadline
  /// has really expired.
  void _armIdle([Duration? after]) {
    _idle?.cancel();
    if (_closed) return;
    _idle = Timer(after ?? idleLifetime, () {
      if (_closed) return;
      final rest = idleLifetime - _now().difference(_lastOpened);
      if (rest <= Duration.zero) {
        unawaited(close());
        return;
      }
      // **The REMAINING deadline, not a full new one.** The previous form
      // re-armed itself again and again for the full deadline and thus produced a fixed
      // grid from construction: `_lastOpened` moves, the grid does not.
      // Measured with a 300 ms deadline, a channel outlived its last cell by
      // 580 ms — **1.93 times**. The header sentence promises "one hour",
      // what was delivered was "between one and two". The number of
      // wake-up points stays the same or drops.
      _armIdle(rest);
    });
  }

  @override
  void send(Uint8List inner) {
    if (_closed) {
      throw StateError('link channel to ${peer.key} is closed');
    }
    _socket.add(sealCell(inner, _session.sendKey));
  }

  @override
  Stream<Uint8List> get inbound => _inbound.stream;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _idle?.cancel();
    _idle = null;
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
    _socket.destroy();
    if (!_inbound.isClosed) await _inbound.close();
    // FIRST the own teardown, THEN the report — the recipient of the
    // report must not see a half torn-down channel. Exactly once, because
    // `_closed` aborts above.
    onClosed?.call();
  }
}

/// The [LinkConnector] of stage `tcpOwnPort`.
final class TcpLinkConnector implements LinkConnector {
  /// Static material of the peer, by endpoint. Same shape as the UDP side.
  final PeerNodeMaterial? Function(LinkEndpoint peer) lookup;

  /// 32 B of randomness for one handshake. Injected so a guard can make a
  /// run reproducible; `ElligatorFFI.keyPair` wipes the buffer, so a seed
  /// must never be reused.
  final Uint8List Function() drawSeed;

  /// How long an **abandoned** connection attempt is kept before it is torn
  /// down (E-121).
  ///
  /// **This is not a timeout in the sense the contract forbids.** It decides
  /// nothing about the outcome of an attempt: it neither completes nor fails
  /// the future this connector returned — it releases an operating-system
  /// resource that `Link.connect` has already stopped waiting for. That is
  /// the same distinction the demux's own housekeeping timer draws, and the
  /// same reason it is allowed to exist.
  ///
  /// **The value is `defaultPendingLifetime`, and it must not be
  /// `kLinkStageTimeout`.** `stageTimeout` is an ordinary overridable
  /// parameter of `Link.connect`; a cleanup timer pinned to its default
  /// would fire *before* a caller-raised stage timeout and tear down a
  /// connection the run is still waiting on — at which point the connector
  /// *would* be deciding the outcome. That is exactly the mistake E-115
  /// corrected for the pending slot, one layer down, and it is not repeated
  /// here. The full cascade run is the honest upper bound.
  final Duration cleanupLifetime;

  /// Idle deadline that an established channel receives (E-123).
  ///
  /// Default is `LinkDemux.sessionIdleLifetime` — the same hour as on
  /// the UDP path, from the same transport-independent derivation. As a
  /// parameter so that a guard can measure it without waiting an hour;
  /// **not** so that it is varied in operation.
  final Duration idleLifetime;

  final void Function(String) log;

  /// Injected clock for the channels this connector builds.
  ///
  /// Passed on as a **function**, not as a point in time: the channel
  /// computes its idle deadline over time, not once at
  /// construction. Default is the wall clock, as with `LinkDemux`.
  final DateTime Function() _now;

  /// The own node keys — only needed so that this node can identify itself
  /// to the callee (decision C). If they are missing,
  /// it calls anonymously.
  final NodeKeys? ownKeys;

  TcpLinkConnector({
    required this.lookup,
    this.ownKeys,
    required this.drawSeed,
    required this.log,
    this.cleanupLifetime = LinkDemux.defaultPendingLifetime,
    this.idleLifetime = LinkDemux.sessionIdleLifetime,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  @override
  Future<LinkAttempt> attempt(
      LinkEndpoint target, LinkTransport transport) async {
    if (transport.stage != TransportStage.tcpOwnPort) {
      return LinkRefused('this connector serves tcpOwnPort only, '
          'not ${transport.stage.name}');
    }

    final material = lookup(target);
    if (material == null) {
      return LinkRefused('no node material for ${target.key}');
    }

    final InternetAddress address;
    try {
      address = InternetAddress(target.host);
    } catch (e) {
      return LinkRefused('unparsable address ${target.host}: $e');
    }

    // ── Setup, with a handle on the running attempt (E-121) ──────────────
    //
    // `Socket.connect` only returns a future; whoever discards it has
    // no handle on the running connection attempt any more, and it keeps
    // running. Measured: a discarded future leaves an
    // ESTABLISHED connection at the partner and holds its file descriptor; without
    // cleanup an abandoned attempt binds it on Linux with
    // `tcp_syn_retries` = 6 for around 127 s (1+2+4+8+16+32+64). `startConnect`
    // provides the handle.
    final ConnectionTask<Socket> task;
    try {
      task = await Socket.startConnect(address, target.port);
    } on SocketException catch (e) {
      return _classify(e, target);
    }

    var settled = false;
    Socket? live;
    StreamSubscription<Uint8List>? liveSub;

    // The cleaner needs BOTH halves. Measured: a `cancel()` BEFORE
    // completion frees the descriptor; a `cancel()` AFTER
    // completion is a no-op — the socket stays writable. Whoever only
    // cancels clears half of the case.
    //
    // **It runs over the WHOLE attempt, not only over the
    // connection setup.** The first version already set `settled` as soon as
    // the TCP stood, and cancelled the timer — but on every reachable
    // partner the SYN phase is the short one. The long one is waiting for
    // flight 2, which §4.8 expressly lists as "may fail to arrive", and exactly
    // that was uncovered: measured, 20 abandoned attempts against
    // an accepting, silent partner kept their 20 descriptors even after
    // 8.5 s — beyond the cleanup deadline AND beyond the full cascade run.
    // E-121's decision text only speaks of the abandoned "connect"; that was
    // not a broken stipulation, but an unclosed gap.
    //
    // **The contract is preserved:** the timer still completes NO
    // future. `flight2.future` stays open, silence stays
    // non-completion (§4.8) — it only frees the operating system resource
    // nobody is waiting for any more.
    final cleanup = Timer(cleanupLifetime, () {
      if (settled) return;
      task.cancel();
      unawaited(task.socket
          .then((Socket s) => s.destroy())
          .catchError((Object _) {}));
      unawaited(liveSub?.cancel());
      live?.destroy();
      log('link tcp: abandoned attempt to ${target.key} torn down');
    });

    final Socket socket;
    try {
      socket = await task.socket;
    } on SocketException catch (e) {
      settled = true;
      cleanup.cancel();
      return _classify(e, target);
    }
    live = socket;

    // ── §2.6 handshake over the stream ───────────────────────────────────
    final pending = LinkHandshake.buildFlight1(
      lNode: material.lNode,
      nX25519Pub: material.x25519Public,
      nMlKemPub: material.mlKemPublic,
      seed: drawSeed(),
      claimPosition: ownKeys?.lNode,
      ownStaticX25519Secret: ownKeys?.nX25519Secret,
    );

    final flight2 = Completer<Uint8List>();
    final gather = BytesBuilder(copy: false);
    Uint8List carryOver = Uint8List(0);
    late final StreamSubscription<Uint8List> sub;
    sub = socket.listen(
      (Uint8List chunk) {
        if (flight2.isCompleted) return;
        gather.add(chunk);
        if (gather.length < kHandshakeFlightSize) return;
        final all = gather.takeBytes();
        // Whatever came after flight 2 is already cell stream. It is handed
        // to the channel instead of dropped — on a stream the peer may put
        // its first cell in the same segment.
        if (all.length > kHandshakeFlightSize) {
          carryOver =
              Uint8List.fromList(all.sublist(kHandshakeFlightSize));
        }
        flight2
            .complete(Uint8List.sublistView(all, 0, kHandshakeFlightSize));
      },
      onDone: () {
        if (!flight2.isCompleted) {
          flight2.completeError(
              const SocketException('peer closed before flight 2'));
        }
      },
      onError: (Object e) {
        if (!flight2.isCompleted) flight2.completeError(e);
      },
      cancelOnError: true,
    );
    liveSub = sub;

    try {
      socket.add(pending.flight1);
      // **No own deadline on the wait.** How long to wait for flight 2
      // is decided by `Link.connect` via its `stageTimeout` — the
      // connector may set nothing here. If the response fails to arrive,
      // this future stays open, and exactly that is the form in which §4.8
      // expresses "the network discards silently".
      final reply = await flight2.future;
      final session = LinkHandshake.openFlight2(pending, reply);
      settled = true;
      cleanup.cancel();
      if (session == null) {
        // Not a failure one may report: a response that does not
        // open is indistinguishable from one that fails to arrive, and
        // §2.6 demands silence. The run runs into its stage timeout.
        // Here cancel IS right — the connection ends anyway.
        await sub.cancel();
        socket.destroy();
        return Completer<LinkAttempt>().future;
      }
      // **Do not cancel.** The subscription moves into the channel; see
      // the justification at [TcpLinkChannel._sub].
      return LinkEstablished(TcpLinkChannel._(
        transport: transport,
        peer: target,
        session: session,
        socket: socket,
        subscription: sub,
        now: _now,
        idleLifetime: idleLifetime,
        carryOver: carryOver,
      ));
    } on SocketException catch (e) {
      settled = true;
      cleanup.cancel();
      await sub.cancel();
      socket.destroy();
      return _classify(e, target);
    }
  }

  /// Maps an OS error to a refusal, or to silence.
  ///
  /// A non-fatal error is **not** reported: `LinkAttempt` is sealed and has
  /// no member for it, deliberately — "silence is the absence of any report,
  /// and it is expressed by a future that has not completed". A connector
  /// that answered `LinkRefused` here would escalate the run at once on an
  /// error §4.8 wants waited out.
  Future<LinkAttempt> _classify(SocketException e, LinkEndpoint target) {
    final refused = classifyLinkSocketError(e, target);
    if (refused != null) return Future<LinkAttempt>.value(refused);
    log('link tcp: non-fatal error to ${target.key} — ${e.osError}; '
        'the stage runs into its timeout');
    return Completer<LinkAttempt>().future;
  }
}
