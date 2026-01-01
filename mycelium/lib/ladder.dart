import 'dart:typed_data';

import 'package:mycelium/card.dart';
import 'package:mycelium/ladder_target.dart';
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

  /// The acknowledgement is there (§9.2) — the one event that ends a
  /// sending. Nothing further is sent.
  void acknowledged({LadderStep? via}) {
    if (_finished) return;
    _finished = true;
    _winner = via;
    _report?.call('delivered${via == null ? "" : " via ${via.name}"}'
        '${traceOn ? " — TRACE ladder ${packetId(packet)} acknowledged" : ""}');
  }

  /// The caller gives up (§9.3: the application decides).
  void giveUp() {
    if (_finished) return;
    _finished = true;
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
        }}');
    }
    action();
  }
}

typedef StepsSend = void Function(Uint8List packet, CardAddress destination);

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

  /// Whether this node holds a socket for the address family of [a] (§11.1,
  /// S394 V1). Step 1 to another family does not apply — it is not tried.
  final bool Function(CardAddress a) speaks;

  Ladder({
    required this.direct,
    required this.viaNeighbour,
    required this.inPostBox,
    this.search,
    this.report,
    bool Function(CardAddress a)? speaks,
  }) : speaks = speaks ?? ((_) => true);

  /// Sends [packet] off: every applicable step, now, once (§7.1).
  ///
  /// Which steps apply is said by the [target] alone: step 1 with a LAN
  /// address this node can speak to, step 3 with a neighbour AND a code
  /// (without the code the recipient's neighbour cannot assign anything,
  /// §8.1), step 4 where [Target.postBoxApplicable]. Order inside this call:
  /// 1, 3, 4 — step 4 only starts its proof of work here.
  Shipment send(Uint8List packet, Target target) {
    final s = Shipment._(packet, target, report);
    final lan = target.lan;
    if (lan != null && speaks(lan)) {
      s._send(LadderStep.lan, () => direct(packet, lan));
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
    if (target.postBoxApplicable) {
      s._send(LadderStep.postBox,
          () => s._placing(inPostBox(packet, target, () => s._finished)));
    }
    if (target.empty) {
      report?.call('no route known — only the post box remains');
    }
    return s;
  }
}
