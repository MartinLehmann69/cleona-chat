import 'dart:async';
import 'dart:typed_data';

import 'package:mycelium/card.dart';
import 'package:mycelium/route_memory.dart';

/// [Route] and [RouteMemory] lie next door — they belong to the CALLER,
/// who stores them with its contacts; the ladder only reads them. Re-exported
/// here, so that no caller needs two imports.
export 'package:mycelium/route_memory.dart';

/// The ladder — four routes to the counterpart.
///
/// Two rules that belong together and that are easily played
/// against each other:
///
/// > **1. No step may hold up another.** There is no
/// > escalation and no waiting until a step fails — because
/// > "failed" can only be recognised by a deadline, and a deadline is
/// > exactly the waiting time one wants to avoid.
///
/// > **2. As soon as a route CARRIES, the more expensive ones stop sending.**
/// > Starting everything at once is right; letting everything keep running at once
/// > would be waste.
///
/// And because a carrying route can break away in the middle of the run — the
/// other side goes offline, the Wi-Fi changes —, the
/// routes put back are **resumed** when the carrying one
/// falls silent.
///
/// This file knows no network. It gets a function for every step
/// and calls it at the right time.
///
/// **D1 = a (proposal M, S391):** a shipment goes via steps 1, 3 and 4.
/// Step 2 stays for the own address (0x40/0x41) and the knock for
/// calls; a message to a public address would show everyone on the
/// path who is talking to whom. The ladder therefore never plans step 2; the value
/// stays because an INCOMING packet can still come via it
/// (`stepFrom`).
enum LadderStep {
  /// LAN address from the card; without it the search call in the own segment.
  lan,

  /// The public address — since D1 only as an incoming step.
  public,

  /// Via a neighbour that both reach.
  neighbour,

  /// Deposit in the post box.
  postBox;

  /// The larger, the more expensive. A sign of life on one step silences
  /// all more expensive ones.
  int get price => index;
}

/// When which step starts, counted from sending.
///
/// Steps 1 and 3 start practically together; the offset only serves
/// not to put three packets onto the same socket in the same microsecond.
///
/// Step 4 waits longer, and that is the only exception: it stores
/// data with THREE foreign nodes. But it does NOT wait for
/// the others to fail — only a fixed, short time.
const Duration kOffsetNeighbour = Duration(milliseconds: 10);
const Duration kOffsetPostBox = Duration(milliseconds: 300);

/// How long a carrying route may be silent before the
/// routes put back are resumed.
const Duration kSilenceDeadline = Duration(seconds: 2);

/// How long a proven route is tried alone before the whole
/// ladder is opened. Short enough that a counterpart who has moved
/// does not cost noticeably; long enough that a round trip in the LAN and over
/// an ordinary internet path fits in.
const Duration kProbationPeriod = Duration(milliseconds: 500);

/// Where sending is possible. Everything is optional.
class Target {
  final CardAddress? lan;

  /// The recipient's fixed neighbour — step 3 carries only with [code].
  final CardAddress? neighbour;

  /// All of the recipient's fixed neighbours (≤ 3, [neighbour] first) —
  /// step 3 names each in its one `0x22` (§8.1). Empty: [neighbour] alone.
  final List<CardAddress> neighbours;

  /// The code of this shipment (16 B, `pair.dart`) — under it the
  /// recipient's neighbour passes on (§8.1). If it is missing, step 3 drops out.
  final Uint8List? code;

  /// Identifier of the peer (32 B) — under it the post box step
  /// deposits, and the call searches for it. It belongs to the SHIPMENT:
  /// until S385 it was searched for afterwards and hit the oldest open
  /// shipment instead of this one (finding D, `smoke_deposit_identifier`).
  final Uint8List? identifier;

  /// Whether the post box step APPLIES — §7.1 starts "every applicable
  /// step", and which apply is said by the target: steps 1 and 3 via
  /// address and code, step 4 here. No order, no deadline.
  ///
  /// `false` means PROVEN reachable: the packet that this shipment
  /// answers just came in via [lan], and §8.2 keeps the
  /// post box for a recipient who is OFF. The silence of the ladder does not
  /// settle that — a shipment ends with the receipt (§7.1 "the
  /// remaining attempts are cancelled"), and to a receipt there is
  /// no receipt (§9.2). An ANSWER thus never ends by itself and deposits
  /// after [kOffsetPostBox], even if its recipient has long
  /// had it: measured 7 datagrams, 7886 B per holder, times three in the field, plus
  /// three proofs of work (`berichte/S389-BAU-QUITTUNG.md`).
  final bool postBoxApplicable;

  const Target({this.lan, this.neighbour, this.code, this.identifier,
      this.postBoxApplicable = true, this.neighbours = const []});

  /// From the addresses that a caller holds for a peer
  /// ([Routes] — from its card, §15.2, and from what it has observed itself,
  /// §6.2). [lan] overrides the LAN role if the caller has a
  /// PROVEN route: the address from which the answered packet came.
  ///
  /// The card's way into the ladder. Until S390 this place was called
  /// `Ziel.ausKarte`, took a whole [Card] and had in `lib/`, `bin/`
  /// and `test/` **zero callers** — the application built its [Target] with
  /// `lan:` and nothing else (finding B-1).
  /// [neighbour] overrides the neighbour address of the routes (the current one from
  /// the pair instead of the one from the card). `w.public` is not read
  /// (D1).
  factory Target.outDueTo(Routes? w,
          {CardAddress? lan,
          CardAddress? neighbour,
          List<CardAddress> neighbours = const [],
          Uint8List? code,
          Uint8List? identifier,
          bool postBoxApplicable = true}) =>
      Target(
        lan: lan ?? w?.lan,
        neighbour: neighbours.firstOrNull ?? neighbour ?? w?.neighbour,
        neighbours: neighbours,
        code: code,
        identifier: identifier,
        postBoxApplicable: postBoxApplicable,
      );

  /// No step except the post box carries.
  bool get empty => lan == null && (neighbour == null || code == null);
}

/// A running sending.
class Shipment {
  final Uint8List packet;
  final Target target;
  final Duration silenceDeadline;
  final void Function(String)? _report;

  final Map<LadderStep, void Function()> _actions = {};
  final List<Timer> _timer = [];
  final List<LadderStep> _started = [];
  final Set<LadderStep> _silenced = {};

  LadderStep? _carries;
  LadderStep? _winner;
  Timer? _silenceClock;
  Timer? _probationClock;
  bool _finished = false;

  /// As long as only the remembered route runs and the others are not yet
  /// opened.
  bool _onProbe = false;

  /// Whether the remembered route has carried — the caller reads this to maintain the
  /// memory.
  bool get rememberedRouteCarried => _rememberedRouteCarried;
  bool _rememberedRouteCarried = false;

  /// Whether the whole ladder had to be opened.
  bool get ladderOpened => !_onProbe;

  Shipment._(this.packet, this.target, this.silenceDeadline, this._report);

  /// Which steps actually sent, in order.
  List<LadderStep> get started => List.unmodifiable(_started);

  /// The step that last showed a sign of life.
  LadderStep? get carries => _carries;

  /// The step via which the receipt came.
  LadderStep? get winner => _winner;

  /// The steps that are currently not sending because a cheaper route
  /// carries.
  Set<LadderStep> get silenced => Set.unmodifiable(_silenced);

  bool get finished => _finished;

  /// Something came from the other side via [s] — the route carries.
  ///
  /// That is NOT the receipt. A sign of life is anything that proves
  /// that the other side is reachable on this route: a
  /// re-request of missing part packets, an interim message, an
  /// arbitrary packet from it.
  void signOfLife(LadderStep s) {
    if (_finished) return;
    if (_onProbe) {
      _rememberedRouteCarried = true;
      _probationClock?.cancel();
      _report?.call('${s.name} carries — the other routes stay closed');
    }
    _carries = s;
    for (final t in LadderStep.values) {
      if (t.price > s.price && !_silenced.contains(t)) {
        _silenced.add(t);
        _report?.call('${t.name} stopped — ${s.name} carries');
      }
    }
    _silenceClockNew();
  }

  /// The receipt is there. From here on nothing more is sent, and nothing
  /// more resumed.
  void acknowledged({LadderStep? via}) {
    if (_finished) return;
    _winner = via ?? _carries ?? (_started.isEmpty ? null : _started.last);
    _report?.call('delivered via ${_winner?.name ?? "unknown"}');
    _close();
  }

  /// The caller gives up.
  void giveUp() {
    if (_finished) return;
    _report?.call('given up');
    _close();
  }

  void _silenceClockNew() {
    _silenceClock?.cancel();
    if (_silenced.isEmpty) return;
    _silenceClock = Timer(silenceDeadline, _silenceExpired);
  }

  /// The carrying route has fallen silent — the other side may have
  /// gone offline. The routes put back are
  /// resumed.
  void _silenceExpired() {
    if (_finished) return;
    final still = _silenced.toList()..sort((a, b) => a.price - b.price);
    _report?.call('${_carries?.name ?? "the route"} has been silent for '
        '${silenceDeadline.inMilliseconds} ms — resuming '
        '${still.map((e) => e.name).join(", ")}');
    _carries = null;
    _onProbe = false;
    _silenced.clear();
    for (final s in still) {
      final action = _actions[s];
      if (action != null) _send(s, action);
    }
  }

  void _send(LadderStep s, void Function() action) {
    if (_finished || _silenced.contains(s)) return;
    _started.add(s);
    _report?.call('Step ${s.name} dispatched');
    action();
  }

  void _close() {
    _finished = true;
    _silenceClock?.cancel();
    _probationClock?.cancel();
    for (final t in _timer) {
      t.cancel();
    }
    _timer.clear();
  }
}

typedef StepsSend = void Function(Uint8List packet, CardAddress destination);
/// [target] is the whole [Target] of the shipment — the neighbour step needs the
/// code from it ([Target.code]).
typedef NeighbourSend = void Function(
    Uint8List packet, CardAddress destination, Target target);
typedef DepositSend = void Function(Uint8List packet, Uint8List? forField);
/// Searches the peer with this identifier (32 B) in the own segment.
typedef Search = void Function(Uint8List identifier);

class Ladder {
  final StepsSend direct;
  final NeighbourSend viaNeighbour;
  final DepositSend inPostBox;
  final Search? search;
  final void Function(String)? report;

  /// Whether this node holds a socket for the address family of [a] (§11.1,
  /// S394 V1). Step 1 to another family does not apply — it is not tried.
  final bool Function(CardAddress a) speaks;

  final Duration offsetNeighbour;
  final Duration offsetPostBox;
  final Duration silenceDeadline;
  final Duration probationPeriod;

  Ladder({
    required this.direct,
    required this.viaNeighbour,
    required this.inPostBox,
    this.search,
    this.report,
    bool Function(CardAddress a)? speaks,
    this.offsetNeighbour = kOffsetNeighbour,
    this.offsetPostBox = kOffsetPostBox,
    this.silenceDeadline = kSilenceDeadline,
    this.probationPeriod = kProbationPeriod,
  }) : speaks = speaks ?? ((_) => true);

  /// Sends [packet] off.
  ///
  /// If [proven] is set, FIRST ONLY this one route runs. If it shows
  /// a sign of life within [probationPeriod], the
  /// others stay closed — that is the normal case with a counterpart with whom
  /// one has been talking for weeks, and it saves three of four routes. If it shows
  /// none, the whole ladder is opened.
  Shipment send(Uint8List packet, Target target, {Route? proven}) {
    final s = Shipment._(packet, target, silenceDeadline, report);

    if (target.lan case final lan? when speaks(lan)) {
      s._actions[LadderStep.lan] = () => direct(packet, lan);
    }
    // Step 3 applies only with a code: without it the recipient's
    // neighbour cannot assign anything (§8.1).
    if (target.neighbour != null && target.code != null) {
      s._actions[LadderStep.neighbour] =
          () => viaNeighbour(packet, target.neighbour!, target);
    }
    // If the step does not apply, it gets no function — then it can
    // neither be planned nor resumed after the silence deadline.
    if (target.postBoxApplicable) {
      s._actions[LadderStep.postBox] = () => inPostBox(packet, target.identifier);
    }

    final onProbe = proven != null && s._actions.containsKey(proven.step);
    if (onProbe) {
      s._onProbe = true;
      report?.call('${proven.step.name} carried last — '
          'first only this route');
      s._send(proven.step, s._actions[proven.step]!);
      s._probationClock = Timer(probationPeriod, () {
        if (s._finished || !s._onProbe) return;
        report?.call('no sign of life in '
            '${probationPeriod.inMilliseconds} ms — open the ladder');
        s._onProbe = false;
        _allRemaining(s, except: proven.step);
      });
      return s;
    }

    _allRemaining(s);
    if (target.empty) {
      report?.call('no route known — only the post box remains');
    }
    return s;
  }

  /// Opens the ladder: step 1 immediately without a timer — otherwise the
  /// fastest route costs a round through the event loop — the
  /// others offset.
  void _allRemaining(Shipment s, {LadderStep? except}) {
    final lan = s._actions[LadderStep.lan];
    if (lan != null && except != LadderStep.lan) s._send(LadderStep.lan, lan);
    // No route on step 1: then, and ONLY then, the search call for the
    // peer's identifier (call D, S385; §7.1 "plus a local call").
    // With a LAN address none goes out — not even the neighbour call, which
    // until S385 hung on every shipment here; it belongs to the start (G1).
    final identifier = s.target.identifier;
    if (lan == null && identifier != null) search?.call(identifier);
    if (except != LadderStep.neighbour) _plan(s, LadderStep.neighbour, offsetNeighbour);
    if (except != LadderStep.postBox) {
      _plan(s, LadderStep.postBox, offsetPostBox);
    }
  }

  void _plan(Shipment s, LadderStep step, Duration after) {
    final action = s._actions[step];
    if (action == null) return;
    s._timer.add(Timer(after, () => s._send(step, action)));
  }
}
