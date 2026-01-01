/// Link I/O — the listening side of the escalation stage `tcpOwnPort`
/// (E-116, E-117, E-118, E-120, E-123).
///
/// **The difference from the UDP side is not one of degree.** There the
/// MAC check is the first thing that happens, and a sender without `L_node`
/// produces **zero** state. Here that is structurally impossible:
/// `accept()` IS the state creation — the node owns socket and
/// descriptor before it may look at a single byte. Everything in this
/// file is a repair of this one fact.
///
/// **The four thresholds, in this order:**
///
/// | | what is decided | evidence |
/// |---|---|---|
/// | `accept` | pot B, pot U or rejection | `lib/core/link/admission.dart` |
/// | **4 B** | HTTP or link handshake | §19.6.5, E-117 |
/// | **48 B** | does the sender carry the `L_node`? | §2.6, field layout of flight 1 |
/// | **1 200 B** | the whole flight | E-116(1) |
///
/// **The switch is token-strict and has no fall-through** (E-117).
/// `GET ` and `HEAD` as complete four-byte tokens; everything else goes
/// into the handshake, and between the branches there is no way back. The
/// previously planned fall-through path is struck, because it **cannot heal**
/// the case it was intended for: it could fire at the earliest after
/// the HTTP header deadline, while the initiator has long since escalated after
/// `kLinkStageTimeout`.
///
/// **What this file does NOT do, and that is normative:** it does not close
/// immediately when the MAC fails. §2.6/E-83 verbatim — "The node reads,
/// stays silent, and closes on the sniff timeout that already exists (5 s).
/// **It does not close immediately: an immediate teardown after exactly 48
/// bytes read would itself be a signature.**" A counter-draft proposed exactly
/// that ("whoever does not pass it is closed immediately"); it is
/// rejected because it overrides a decision with a decision number
/// and produces the signature that the rest of this layer expensively avoids.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/link/admission.dart';
import 'package:cleona/core/link/connect.dart';
import 'package:cleona/core/link/handshake.dart';
import 'package:cleona/core/link/node_keys.dart';
import 'package:cleona/core/link/replay_buffer.dart';
import 'package:cleona/core/link/transport_selector.dart';
import 'package:cleona/core/link_io/link_demux.dart' show LinkDemux;
import 'package:cleona/core/link_io/tcp_connector.dart';
import 'package:cleona/core/link_io/udp_sockets.dart' show LinkAddressFamily;

/// Where a connection recognised as HTTP is handed over (E-118).
///
/// **Injected, not imported** — and the justification is testability,
/// not an import rule. A rule "`lib/core/link_io/` must not import
/// `lib/core/update/`" **does not exist** (searched with four
/// search phrasings across architecture doc, decision log, migration plan
/// and tree: no hit), `BinaryHttpServer` is a **permanent**
/// V4 module, and guard 4 checks counters in the source text, not import edges.
/// What the sink achieves is that this file is testable **without** the HTTP server
/// — the same pattern that `LinkConnector`, `LinkBinder` and
/// `LinkChannel` carry.
///
/// [subscription] is handed over **paused** and may only be
/// cancelled by the recipient when it needs no more bytes: a `cancel()` flips
/// `hasListener`, whereupon the runtime shuts down the receive direction of the raw
/// socket. This tree has already learned that expensively once.
typedef LinkHttpSink = void Function(
    Socket client, Uint8List buffered, StreamSubscription<Uint8List> sub);

/// What came out of binding an address family (E-101).
final class TcpBindReport {
  final LinkAddressFamily family;
  final Object? error;
  const TcpBindReport(this.family, this.error);
  bool get bound => error == null;
}

/// The TCP listener of the own data port.
final class TcpLinkListener {
  final NodeKeys keys;
  final LinkReplayBuffer replay;
  final LinkAdmission admission;
  final void Function(String) log;

  /// 32 B of randomness per handshake. `ElligatorFFI.keyPair` wipes the buffer, a
  /// seed must never be reused.
  final Uint8List Function() drawSeed;

  /// Where HTTP goes. `null` means: there is no HTTP branch on this
  /// node, a token hit is then treated like any other
  /// initial value — it goes into the handshake and fails there silently.
  ///
  /// **SETTABLE AFTERWARDS, and the justification is an order, not
  /// style (S361).** The node stands in both composition points
  /// (`service_daemon.dart`, `main.dart`) **before** the services — it supplies
  /// them with the port. `BinaryHttpServer` however only arises in the service
  /// (`cleona_service_update.dart:516`), so the sink does not yet exist at
  /// the time this listener is constructed. A `final`
  /// field would leave only two ways out, and both are worse: creating the listener
  /// later (then every incoming TCP link in the start window falls
  /// to the floor) or inserting an intermediate sink that rebuilds the
  /// `null` case — and exactly that is the expensive one: it does not tear down,
  /// but lets the deadline run out (E-83, see [_handOverHttp]), and
  /// only this file can do that.
  ///
  /// [_handOverHttp] reads the field **at the moment of the switch**, not at
  /// construction; both paths — with and without sink — are thus preserved
  /// verbatim. The same pattern carries [lookupStatic] a
  /// hand's breadth further down.
  LinkHttpSink? httpSink;

  /// The port number. **The same as UDP** (§2.1a; E-60 gives the
  /// entry record exactly one port for both protocols).
  final int port;

  /// Deadline from `accept` to the first complete wire unit.
  ///
  /// **5 s from §2.6/E-83.** It also covers both thresholds before it: the four
  /// bytes of the switch and the 48 of the MAC. An own, shorter deadline for
  /// "fewer than four bytes" would be a signature — it would make the
  /// teardown time depend on the **byte count**, and exactly that is forbidden by E-83.
  final Duration sniffLifetime;

  /// Deadline after a passed MAC by which the flight must be complete.
  ///
  /// The full cascade run (`LinkDemux.defaultPendingLifetime`), the same
  /// number as for the wait marker of the opposite direction — not a new one.
  final Duration flightLifetime;

  /// Idle deadline that an accepted channel receives (E-123).
  ///
  /// The same hour as on the UDP path and at the connector, from the same
  /// transport-independent derivation. **As a parameter so that a guard
  /// can measure it without waiting an hour; not so that it is varied in
  /// operation** — verbatim the justification that
  /// `TcpLinkConnector.idleLifetime` carries. That it was missing here until
  /// 2026-08-21 was a gap of the same pattern, not a
  /// decision: the listener called `TcpLinkChannel.accepted` without it and
  /// got the default of one hour, whereby the responder side of its
  /// channel was not testable.
  final Duration channelIdleLifetime;

  /// Injected clock.
  ///
  /// **The listener is the one that feeds `LinkAdmission`** — and
  /// `admission.dart` assures in its header "not to read any clock it
  /// has not been given", takes the time as a **mandatory parameter without
  /// fallback** and is thus scrupulously injectable. The first
  /// version of this listener nonetheless passed it the **wall clock**
  /// at three places; thereby `unknownLifetime` (1.5 s) and
  /// `macCheckedLifetime` (6 s) were only testable via this path by real waiting,
  /// and the guard did just that (five `Future.delayed`,
  /// together 1.7 s). With deadlines of this size that still works; a
  /// deadline of ten minutes would **not** be testable that way.
  final DateTime Function() _now;

  final _accepted = StreamController<TcpLinkChannel>.broadcast();
  final _servers = <ServerSocket>[];
  var _closed = false;
  var _nextKey = 0;

  /// Looks up the static X25519 key for a position
  /// (decision C). Not set = every caller stays anonymous.
  StaticKeyLookup? lookupStatic;

  TcpLinkListener({
    required this.keys,
    required this.replay,
    required this.admission,
    required this.drawSeed,
    required this.log,
    required this.port,
    this.httpSink,
    this.sniffLifetime = const Duration(seconds: 5),
    this.flightLifetime = const Duration(milliseconds: 6000),
    this.channelIdleLifetime = LinkDemux.sessionIdleLifetime,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// The established links of this side.
  Stream<TcpLinkChannel> get accepted => _accepted.stream;

  /// Binds one listener per address family on [port].
  ///
  /// **E-101 applies here just as for UDP** (E-120): the listener is bound
  /// as soon as **at least one** family stands, and there is
  /// **one log line per missing family** — not one in total. E-71
  /// demands separating "family missing for lack of a node" from "family missing for lack of a
  /// partner", and a collective line does not achieve that.
  ///
  /// **The failure is silent (E-120, pattern E-96), not fatal.** E-99 lets
  /// the start fail if `bare` cannot bind, and justifies this
  /// by saying that a node without a bare listener is **deaf**. A node
  /// with a bound UDP listener is not deaf — it loses the incoming
  /// side of a **fallback** stage (§2.1a expressly lists `tcpOwnPort`
  /// as such) and stays fully reachable via `udpOwnPort`.
  Future<List<TcpBindReport>> start() async {
    final reports = <TcpBindReport>[];
    for (final family in LinkAddressFamily.values) {
      try {
        final s = await ServerSocket.bind(family.wildcard, port,
            shared: false, v6Only: family == LinkAddressFamily.v6);
        _servers.add(s);
        s.listen(_onConnection, onError: (Object e) {
          log('link tcp listen: ${family.name} stream error — $e');
        });
        reports.add(TcpBindReport(family, null));
      } catch (e) {
        log('link tcp listen: ${family.name} unavailable on port $port — $e');
        reports.add(TcpBindReport(family, e));
      }
    }
    return reports;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final s in _servers) {
      await s.close();
    }
    _servers.clear();
    if (!_accepted.isClosed) await _accepted.close();
  }

  void _onConnection(Socket client) {
    final now = _now();
    final key = 'c${_nextKey++}';
    final address = client.remoteAddress.address;

    final slot = admission.offer(key, address, now);
    if (slot == LinkAdmissionSlot.refused) {
      // **Rejecting means accepting and closing immediately (FIN).** Letting the SYN
      // be swallowed would be worse: the caller would then see
      // `ETIMEDOUT`, and `kLinkRefusedErrno` deliberately does NOT list that as a
      // refusal (E-116(6): "the network is silent"). An overloaded node
      // would be indistinguishable from a dead one, and the honest peer
      // burns its full stage timeout instead of escalating immediately.
      client.destroy();
      return;
    }

    _Conn(this, client, key, address).run();
  }

  void _emit(TcpLinkChannel ch) {
    if (!_accepted.isClosed) _accepted.add(ch);
  }
}

/// An accepted connection on its way through the four thresholds.
final class _Conn {
  final TcpLinkListener _l;
  final Socket _socket;
  final String _key;
  final String _address;

  final _gather = BytesBuilder(copy: false);
  late final StreamSubscription<Uint8List> _sub;
  Timer? _deadline;

  /// After a failed MAC, reading **continues and is discarded**.
  ///
  /// Continue reading, because E-83 forbids immediate closing. **Discard**,
  /// because otherwise an attacker with a 5 s deadline and 1 Gbit/s would push around 625 MB into
  /// a buffer nobody caps — the read upper limit before the
  /// handshake is unwritten in the corpus, and this rule is the
  /// only one that manages without a new number: what can no longer be learned
  /// is no longer kept.
  var _doomed = false;
  var _switched = false;
  var _macPassed = false;
  var _done = false;

  _Conn(this._l, this._socket, this._key, this._address);

  void run() {
    _arm(_l.sniffLifetime);
    _sub = _socket.listen(_onData,
        onDone: _end, onError: (Object _) => _end(), cancelOnError: true);
  }

  void _arm(Duration d) {
    _deadline?.cancel();
    _deadline = Timer(d, () {
      // Silence: no error packet, no response, no log line. A
      // log line here would be the observable difference §2.6 forbids.
      _end();
    });
  }

  void _end() {
    if (_done) return;
    _done = true;
    _deadline?.cancel();
    _l.admission.release(_key, _l._now());
    unawaited(_sub.cancel());
    _socket.destroy();
  }

  void _onData(Uint8List chunk) {
    if (_done) return;
    if (_doomed) return; // read, discarded (see [_doomed])
    _gather.add(chunk);

    // ── Threshold 4 B: the switch ─────────────────────────────────────
    if (!_switched) {
      if (_gather.length < 4) return;
      final all = _gather.takeBytes();
      _gather.add(all);
      _switched = true;
      if (_isHttpToken(all)) {
        _handOverHttp(all);
        return;
      }
    }

    // ── Threshold 48 B: the `L_node` ──────────────────────────────────
    if (!_macPassed) {
      if (_gather.length < kAeadOffset1) return;
      final all = _gather.takeBytes();
      _gather.add(all);
      if (!LinkHandshake.acceptsInitMacPrefix(_l.keys, all)) {
        // **Do not close.** E-83: an immediate teardown after exactly 48
        // bytes read would itself be a signature. The deadline keeps running,
        // reading continues, nothing is kept any more.
        _doomed = true;
        _gather.clear();
        return;
      }
      _macPassed = true;
      _l.admission.macPassed(_key, _l._now());
      _arm(_l.flightLifetime);
    }

    // ── Threshold 1 200 B: the whole flight ──────────────────────────────
    if (_gather.length < kHandshakeFlightSize) return;
    final all = _gather.takeBytes();
    final flight1 = Uint8List.sublistView(all, 0, kHandshakeFlightSize);
    final carryOver = all.length > kHandshakeFlightSize
        ? Uint8List.fromList(all.sublist(kHandshakeFlightSize))
        : null;

    final result = LinkHandshake.handleFlight1(
      keys: _l.keys,
      replay: _l.replay,
      flight1: flight1,
      respSeed: _l.drawSeed(),
      lookupStatic: _l.lookupStatic,
    );
    if (result == null) {
      // MAC failure and replay hit are the same from outside (E-79).
      // Here too: do not close, but let the deadline run out.
      _doomed = true;
      _gather.clear();
      return;
    }

    _deadline?.cancel();
    _done = true;
    _socket.add(result.flight2);
    // **Only here** does the source address move into pot B: a complete,
    // expensive, valid handshake — not the mere setup, not the MAC.
    _l.admission.handshakeCompleted(_key, _address, _l._now());
    _l._emit(TcpLinkChannel.accepted(
      transport: const LinkTransport(TransportStage.tcpOwnPort, Disguise.bare),
      peer: LinkEndpoint(_address, _socket.remotePort),
      session: result.session,
      socket: _socket,
      subscription: _sub,
      now: _l._now,
      idleLifetime: _l.channelIdleLifetime,
      carryOver: carryOver,
      // THE END OF THIS SESSION IS THE END OF THIS CONNECTION. `_end`
      // no longer runs from here (`_done` is set), the socket belongs to the
      // channel. Without this report the deadline of pot B would never start
      // to run — see `TcpLinkChannel.onClosed`.
      onClosed: () => _l.admission.release(_key, _l._now()),
    ));
  }

  /// Do the first four bytes form a complete HTTP token? (E-117)
  ///
  /// **Complete tokens, not single bytes.** The V3 code decided on the
  /// first byte and thereby misrouted around every tenth uniformly distributed
  /// flight; with `GET ` and `HEAD` it is `2 · 2⁻³² = 2⁻³¹`, around **1 in
  /// 2.15 billion**. A flight that is hit anyway dies at the
  /// stage timeout and the initiator escalates.
  static bool _isHttpToken(Uint8List b) =>
      (b[0] == 0x47 && b[1] == 0x45 && b[2] == 0x54 && b[3] == 0x20) || // "GET "
      (b[0] == 0x48 && b[1] == 0x45 && b[2] == 0x41 && b[3] == 0x44); // "HEAD"

  void _handOverHttp(Uint8List buffered) {
    _done = true;
    _deadline?.cancel();
    // From here the slot belongs to the HTTP branch, which keeps its own cap and
    // its own header deadline.
    _l.admission.release(_key, _l._now());
    final sink = _l.httpSink;
    if (sink == null) {
      // No HTTP branch on this node. Silence until the deadline would be
      // pointless here — there is nothing left to learn —, but an immediate
      // teardown at exactly four bytes is the same signature that E-83 forbids.
      // So: let the deadline run out, keep nothing any more.
      _doomed = true;
      _done = false;
      _gather.clear();
      _arm(_l.sniffLifetime);
      return;
    }
    _sub.pause();
    sink(_socket, buffered, _sub);
  }
}
