import 'dart:async';
import 'dart:io' show InternetAddress;
import 'dart:typed_data';

import 'package:mycelium/card.dart';
import 'package:mycelium/ladder_target.dart';
import 'package:mycelium/silence.dart';
import 'package:mycelium/split_flow.dart' show SendEnd;
import 'package:mycelium/trace.dart' show traceOn, packetDescribe, packetId, hexShort;

/// [Target] lies next door (line budget, S398); re-exported here, so that no
/// caller needs two imports.
export 'package:mycelium/ladder_target.dart';

/// The ladder — the routes to the counterpart (V4.2 §3.4, §7.1; D-3, D-44).
///
/// > Steps are attempted **together**, never one after the other: steps 1
/// > and 3 leave at once; step 4 leaves as soon as its proof of work (§8.2)
/// > is ready. A step is never paused, resumed or repeated; only the
/// > acknowledgement ends a sending.
///
/// That is the whole behaviour, and this file holds no clock. Until S399 it
/// held three: an offset per step (10 ms, 300 ms), a probation period for
/// the route that carried last (500 ms) and a silence deadline (2 s) after
/// which steps a "sign of life" had paused were resumed. Each of them was
/// the repair of the one before, and together they lost and delayed
/// messages (S398 L-1, OP-32, N-1; `berichte/S398-ENTWURF-ZUSTELLWEG.md`).
/// The proof of work is step 4's natural offset: whoever acknowledges before
/// it is ready costs no deposit.
///
/// This file knows no network. It gets a function for every step and calls
/// each applicable one exactly once, inside [Ladder.send].
///
/// **D-4:** a message goes via steps 1, 3 and 4. Step 2 stays for the own
/// address (0x40/0x41) and the knock for calls; the ladder never plans it.
/// The value stays because an INCOMING packet can still come via it.
enum LadderStep {
  /// LAN address from the card; without it the search call in the own segment.
  lan,

  /// The public address — since D-4 only as an incoming step.
  public,

  /// Via a neighbour that both reach, by code (§8.1).
  neighbour,

  /// Deposit in the post box (§8.2).
  postBox,

  /// No network: the recipient is another identity of THIS node (§4.5.1
  /// "one daemon, one port, all identities at once"). The packet goes to
  /// the node's own receive side and nowhere else — the way a mail server
  /// hands mail for a local mailbox over without a connection, and an IP
  /// stack carries a packet to its own address over loopback. Over the
  /// network it could not arrive (B-19: the shell cannot carry a packet to
  /// its own address), and through a foreign neighbour or post box it would
  /// show that node two identities of this one in touch (S407 B-22).
  local,
}

/// A running sending. It ends at the acknowledgement or when the caller
/// gives up — never by itself.
class Shipment {
  final Uint8List packet;
  final Target target;
  final void Function(String)? _report;
  final List<LadderStep> _started = [];
  LadderStep? _winner;
  bool _finished = false;
  bool? _placed = false;

  Shipment._(this.packet, this.target, this._report);

  /// Completes when the sending has ended — the answer step 1 waits for.
  final Completer<void> _done = Completer<void>();

  Completer<bool>? _stepOne;

  /// Only for a step 1 that expects an answer ([Ladder.send] `answered`,
  /// `answeredByEndMark`), else `null`: completes `true` when step 1 and its
  /// repeats stayed without an answer (§11.3a "failed"), `false` when it was
  /// answered or the sending ended first. The layer above learns one of the
  /// two (§11.3a "answered, or failed").
  Future<bool>? get stepOneFailed => _stepOne?.future;

  /// The placing of step 4 (§8.2 "placing ends"): `null` while it runs,
  /// `true` once two holders acknowledged (the second `0x31`), `false` when
  /// it ended without that — or when step 4 left nothing at all.
  bool? get placed => _placed;

  /// Called once when the placing of step 4 has ended, with [placed].
  void Function(bool placed)? onPlacingEnd;

  void _placing(Future<bool>? run) {
    if (run == null) return;
    _placed = null;
    run.then((placed) {
      _placed = placed;
      onPlacingEnd?.call(placed);
    });
  }

  /// Which steps sent, in order — each at most once.
  List<LadderStep> get started => List.unmodifiable(_started);

  /// The step the acknowledgement came by, as far as the caller knows it.
  LadderStep? get winner => _winner;

  /// Whether the sending has ended. Step 4 asks this once its proof of work
  /// is ready: an ended sending deposits nothing (§7.1: a proof of work
  /// still running and a deposit not yet sent are dropped).
  bool get finished => _finished;

  /// The one stamping place of the node ([Silence.answeredBy]) — set by
  /// [Ladder.send].
  Silence? _silence;

  /// The acknowledgement is there (§9.2) — the one event that ends a
  /// sending. Nothing further is sent. [from]: the address the answer
  /// arrived from (`null`: a post box, or unknown). When it is the step-1
  /// address this sending went to, the answer came by step 1 and stamps that
  /// address (§11.8.4, S407-LB-P1 O-2); by any other way it stamps nothing
  /// here. Returns whether it stamped.
  bool acknowledged({LadderStep? via, CardAddress? from}) {
    if (_finished) return false;
    _finished = true;
    _done.complete();
    final lan = target.lan;
    final direct = from != null &&
        lan != null &&
        _started.contains(LadderStep.lan) &&
        from.equal(lan);
    if (direct) {
      via ??= LadderStep.lan;
      _silence?.answeredBy(
          InternetAddress.fromRawAddress(Uint8List.fromList(lan.address)),
          lan.port);
    }
    _winner = via;
    _report?.call('delivered${via == null ? "" : " via ${via.name}"}'
        '${traceOn ? " — TRACE ladder ${packetId(packet)} acknowledged" : ""}');
    return direct;
  }

  /// The caller gives up (§9.3: the application decides).
  void giveUp() {
    if (_finished) return;
    _finished = true;
    _done.complete();
    _report?.call('given up${traceOn ? " — TRACE ladder ${packetId(packet)} given up" : ""}');
  }

  void _send(LadderStep s, void Function() action) {
    _started.add(s);
    _report?.call('Step ${s.name} dispatched');
    // S405 (proposal D): which packet goes where on this step.
    if (traceOn) {
      _report?.call('TRACE ladder step ${s.name}: ${packetDescribe(packet)} ${switch (s) {
          LadderStep.lan => 'to ${target.lan}',
          LadderStep.neighbour => 'to the recipient\'s neighbour ${target.neighbour} under code '
              '${target.code == null ? "-" : hexShort(target.code!)}'
              '${target.neighbours.isEmpty ? "" : ", named ${target.neighbours.join(", ")}"}',
          LadderStep.postBox => 'into the post box${target.boxValue == null ? " under the day value" : " under the invitation value"}',
          LadderStep.public => 'to ${target.public}',
          LadderStep.local => 'to another identity of this node',
        }}');
    }
    action();
  }
}

typedef StepsSend = FutureOr<Object?> Function(
    Uint8List packet, CardAddress destination);

/// [target] is the whole [Target] of the shipment — the neighbour step needs the
/// code from it ([Target.code]).
typedef NeighbourSend = void Function(
    Uint8List packet, CardAddress destination, Target target);

/// Step 4 gets the whole [Target] (the identifier, and for a line join's
/// request the invitation value, OP-20) and [ended]: it asks this when its
/// proof of work is ready and leaves nothing when the sending has ended.
/// It returns its placing: `true` once two holders acknowledged, `false`
/// when it ended without that (§8.2 "placing ends"); `null` if it left
/// nothing at all. The future does not throw.
typedef DepositSend = Future<bool>? Function(
    Uint8List packet, Target target, bool Function() ended);

/// Searches the peer with this identifier (32 B) in the own segment.
typedef Search = void Function(Uint8List identifier);

class Ladder {
  final StepsSend direct;
  final NeighbourSend viaNeighbour;
  final DepositSend inPostBox;
  final Search? search;
  final void Function(String)? report;

  /// The local step ([LadderStep.local]): hands a packet to the node's own
  /// receive side. Without it a local sending has nowhere to go.
  final void Function(Uint8List packet)? here;

  /// Whether this node holds a socket for the address family of [a] (§11.1,
  /// S394 V1). Step 1 to another family does not apply — it is not tried.
  final bool Function(CardAddress a) speaks;

  Ladder({
    required this.direct,
    required this.viaNeighbour,
    required this.inPostBox,
    this.search,
    this.report,
    this.here,
    bool Function(CardAddress a)? speaks,
    Silence? silence,
  })  : speaks = speaks ?? ((_) => true),
        silence = silence ?? Silence();

  /// Where step 1 of a sending that waits for its acknowledgement is
  /// repeated and given up (§11.3a) — the node's.
  final Silence silence;

  /// Sends [packet] off: every applicable step, now, once (§7.1).
  ///
  /// Which steps apply is said by the [target] alone: step 1 with a LAN
  /// address this node can speak to, step 3 with a neighbour AND a code
  /// (without the code the recipient's neighbour cannot assign anything,
  /// §8.1), step 4 where [Target.stepFour] (never for a signal, §17.2). Order inside this call:
  /// 1, 3, 4 — step 4 only starts its proof of work here.
  ///
  /// [answered]: the sending waits for its acknowledgement (§9.2) — its step 1
  /// is a packet that expects an answer and is repeated as §11.3a says until
  /// the acknowledgement ends the sending. A receipt or an amendment expects
  /// nothing and leaves once.
  ///
  /// [answeredByEndMark]: step 1 is a packet that expects an answer which
  /// may come long after it arrived — the request (2) of a QR/NFC join waits
  /// for the user's decision (§15.1). Its answer on the transport is the
  /// recipient's end mark: it holds the transmission whole (§11.3). Without
  /// one the request is repeated as §11.3a says (§15.1 "a lost packet is
  /// re-sent"); until S407-FLAKERCA it left once, and its loss let the
  /// join wait without end and without a line.
  ///
  /// [local]: the recipient is another identity of this node — then the
  /// local step is the only one (§4.5.1); [target] is not asked.
  Shipment send(Uint8List packet, Target target,
      {bool answered = false, bool answeredByEndMark = false, bool local = false}) {
    final s = Shipment._(packet, target, report).._silence = silence;
    if (local && here != null) {
      s._send(LadderStep.local, () => here!(packet));
      return s;
    }
    final lan = target.lan;
    if (lan != null && speaks(lan)) {
      s._send(LadderStep.lan, () {
        if (!answered && !answeredByEndMark) {
          direct(packet, lan);
          return;
        }
        final whole = Completer<void>(); // the end mark ([answeredByEndMark])
        final failed = s._stepOne = Completer<bool>();
        unawaited(silence.ask(answered ? s._done.future : whole.future,
            to: InternetAddress.fromRawAddress(Uint8List.fromList(lan.address)),
            port: lan.port,
            send: answered
                ? (_, __) => direct(packet, lan)
                : (_, __) async {
                    final end = await direct(packet, lan);
                    if (end == SendEnd.delivered && !whole.isCompleted) whole.complete();
                    return end;
                  },
            others: false,
            cancelled: () => s._finished,
            what: 'step 1')
            .then((at) => failed.complete(at == null && !s._finished)));
      });
    } else if (target.identifier case final identifier? when target.noAddress) {
      // No address at all — then, and ONLY then, the search call for the
      // peer's identifier (call D, S385; §7.2). A stale address still counts
      // as a way: it produces no answer, and the other steps carry.
      search?.call(identifier);
    }
    final neighbour = target.neighbour;
    if (neighbour != null && target.code != null) {
      s._send(LadderStep.neighbour, () => viaNeighbour(packet, neighbour, target));
    }
    if (target.stepFour) {
      s._send(LadderStep.postBox,
          () => s._placing(inPostBox(packet, target, () => s._finished)));
    }
    if (target.empty) {
      report?.call(target.signal
          ? 'no route known — a signal has no post box (§17.2): not carried'
          : 'no route known — only the post box remains');
    }
    return s;
  }
}
