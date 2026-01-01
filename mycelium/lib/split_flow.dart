/// Flow per next hop (D-41 as amended by the delivery path A→B, S398/S399;
/// v4_2 §3.1, §11.3, §20.2, §20.3).
///
/// The splitter hands each next hop (address:port — the same key as the
/// shell's) at most ONE transmission of two or more parts at a time. The
/// next one starts on an edge, never on a tick:
///
/// * the recipient's **end mark** — an empty re-request, once per complete
///   transmission of two or more parts (§11.3) → [SendEnd.delivered];
/// * or, without end mark or request, 1.1 s (quiet period 300 ms + one
///   answer deadline 800 ms) after the last part → [SendEnd.unconfirmed].
///   The quiet clock exists only while a transmission runs, and it rests
///   while the shell still holds the hop's packets for a handshake: those
///   parts have not left yet;
/// * or the shell gives the hop up (no answer to the handshake) → the
///   running one, all waiting ones and every single part the shell held end
///   [SendEnd.unreachable], with one report; the ladder carries on its other
///   steps (§7.1).
///
/// **Nothing is evicted** (§20.2). Single-part packets never wait. The
/// node's own transmissions wait in order, without a bound: what the node
/// has accepted for sending (R-1). Others' transmissions — forwarding
/// (§8.1), a holder handing out (§8.2) — have a stated bound per target
/// ([kForeignWaitingPerHop], [kForeignWaitingBytesPerHop]); beyond it the
/// offer is refused at once ([SendEnd.refused]): the forwarder answers
/// `0x21`, the holder hands out later — an open refusal, never a silent loss.
///
/// **What it costs, named.** One packet (the end mark, 1200 B in the shell)
/// per transmission of two or more parts; one round trip per transmission
/// that waits behind another to the same hop. Nothing in idle.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

/// How a send ended — what the caller of `Splitter.send` learns.
enum SendEnd {
  /// One part, handed to the shell under a standing link, or released by
  /// the shell when its handshake completed; nothing waits for it.
  sent,

  /// The recipient's end mark arrived: it holds the transmission whole.
  delivered,

  /// Neither end mark nor request within the quiet period after the last part.
  unconfirmed,

  /// Others' transmission beyond the bound per target (§20.2): not taken.
  refused,

  /// The next hop did not answer the shell's handshake, or the node stopped.
  unreachable,
}

/// Others' transmissions waiting for one next hop — count and bytes
/// (§20.2 row "others' transmissions waiting for their next hop").
///
/// set, not measured — v4_2 §20.2 [OPEN]. The values are those of the
/// withdrawn D-41 wording (S398 OP-33 B), sized there for a holder's full
/// hand-out of one value (100 × ≈ 7.9 KB) and two of the largest lane-1
/// transmissions (2 × 424 583 B); with the hand-out entry by entry a holder
/// itself puts at most one transmission per collector in this row.
const int kForeignWaitingPerHop = 128;
const int kForeignWaitingBytesPerHop = 1 << 20;

/// The flow key of a next hop — the same form as the shell's.
String hopKey(InternetAddress a, int port) => '${a.address}:$port';

/// One transmission of two or more parts on its way to one next hop.
class Transmission {
  final List<Uint8List> parts; // full packets incl. header, index = seq no.
  final InternetAddress target;
  final int targetPort;

  /// The bytes the caller handed over — what the bound of others counts.
  final int bytes;
  final bool foreign;
  final Completer<SendEnd> _end = Completer();
  DateTime _started = DateTime(0);

  /// How it ended; `null` while it runs or waits.
  SendEnd? how;

  /// The hop gave up, or the drop deadline passed: a send loop still handing
  /// parts to the shell stops. The node's stop does not set it (R-1).
  bool cut = false;

  Transmission(this.parts, this.target, this.targetPort, this.bytes, this.foreign);

  Future<SendEnd> get end => _end.future;
  String get hop => hopKey(target, targetPort);

  void _close(SendEnd end) {
    if (_end.isCompleted) return;
    how = end;
    _end.complete(end);
  }

  bool isIdentifier(Uint8List id) {
    for (var i = 0; i < 8; i++) {
      if (parts.first[i] != id[i]) return false;
    }
    return true;
  }
}

class _Row {
  Transmission? running;
  final Queue<Transmission> waiting = Queue();
  int foreignWaiting = 0;
  int foreignBytes = 0;
  Timer? quiet;

  /// Single parts the shell holds for this hop's handshake.
  final List<Completer<SendEnd>> held = [];
  bool get empty => running == null && waiting.isEmpty && held.isEmpty;
}

class SplitFlow {
  /// Puts all parts of a transmission on the route.
  final void Function(Transmission t) _start;

  /// Whether the shell still holds packets for this hop (handshake running).
  final bool Function(InternetAddress target, int targetPort) _held;
  final void Function(String) _report;
  final Duration quietAfter;
  final Duration dropAfter;
  final Map<String, _Row> _rows = {};

  /// Counters for probes and the network statistics (§25) — read only.
  int delivered = 0;
  int unconfirmed = 0;
  int refused = 0;
  int unreachable = 0;

  SplitFlow(this._start, this._held, this._report,
      {required this.quietAfter, required this.dropAfter});

  /// Hops with a running transmission — the outgoing parts that wait for a
  /// re-request (§20.2 first row).
  int get running => _rows.values.where((r) => r.running != null).length;

  /// Waiting transmissions, all hops.
  int get waiting => _rows.values.fold(0, (a, r) => a + r.waiting.length);

  /// Whether others' transmission of [bytes] to [target]:[port] is beyond
  /// the bound (§20.2): it would wait, and the row of others is full. The
  /// forwarder asks this before it hands a packet on (§8.1).
  bool refuses(InternetAddress target, int port, int bytes) {
    final row = _rows[hopKey(target, port)];
    if (row == null || row.running == null) return false; // starts at once
    return row.foreignWaiting + 1 > kForeignWaitingPerHop ||
        row.foreignBytes + bytes > kForeignWaitingBytesPerHop;
  }

  Future<SendEnd> offer(List<Uint8List> parts, InternetAddress target, int port,
      int bytes, {bool foreign = false}) {
    if (foreign && refuses(target, port, bytes)) {
      refused++;
      _report('Split: others\' transmission of $bytes B to '
          '${hopKey(target, port)} refused — the bound per target is reached (§20.2)');
      return Future.value(SendEnd.refused);
    }
    final t = Transmission(parts, target, port, bytes, foreign);
    final row = _rows.putIfAbsent(t.hop, _Row.new);
    if (row.running == null) {
      _run(row, t);
      return t.end;
    }
    row.waiting.add(t);
    if (foreign) {
      row.foreignWaiting++;
      row.foreignBytes += bytes;
    }
    return t.end;
  }

  /// A single part the shell holds for [target]'s handshake: ends
  /// [SendEnd.sent] when the handshake completes, [SendEnd.unreachable]
  /// when the hop does not answer.
  Future<SendEnd> heldSingle(InternetAddress target, int port) {
    final c = Completer<SendEnd>();
    _rows.putIfAbsent(hopKey(target, port), _Row.new).held.add(c);
    return c.future;
  }

  /// The running transmission to [hop] with [identifier], if any.
  Transmission? runningFor(String hop, Uint8List identifier) {
    final t = _rows[hop]?.running;
    return t != null && t.isIdentifier(identifier) ? t : null;
  }

  /// Parts of [t] went to the shell (its start, or an answer to a request):
  /// the quiet clock starts anew — if [t] still runs.
  void active(Transmission t) {
    final row = _rows[t.hop];
    if (row != null && identical(row.running, t)) _quiet(t.hop, row);
  }

  /// The end mark of the running transmission of [hop] arrived.
  void endMark(String hop) {
    final row = _rows[hop];
    if (row != null) _finish(hop, row, SendEnd.delivered);
  }

  /// The shell's handshake with [hop] completed: what it held has left.
  void released(String hop) {
    final row = _rows[hop];
    if (row == null) return;
    for (final c in row.held) {
      c.complete(SendEnd.sent);
    }
    row.held.clear();
    final t = row.running;
    if (t != null) {
      _quiet(hop, row);
    } else if (row.empty) {
      _rows.remove(hop);
    }
  }

  /// The shell gave [hop] up: everything for it ends, with ONE report.
  void unreachableHop(String hop) {
    final row = _rows.remove(hop);
    if (row == null) return;
    row.quiet?.cancel();
    for (final c in row.held) {
      c.complete(SendEnd.unreachable);
    }
    final all = [if (row.running != null) row.running!, ...row.waiting];
    if (all.isEmpty && row.held.isEmpty) return;
    unreachable += all.length + row.held.length;
    for (final t in all) {
      t.cut = true;
      t._close(SendEnd.unreachable);
    }
    _report('Split: $hop does not answer — ${all.length} transmission(s), '
        '${all.fold<int>(0, (a, t) => a + t.bytes)} B and ${row.held.length} '
        'single part(s) unreachable; the other steps of the ladder keep running');
  }

  /// Ends everything without a report; the node stops. A begun send loop is
  /// not cut (R-1): the owner waits for it before (`Splitter.finish`).
  void close() {
    for (final row in _rows.values) {
      row.quiet?.cancel();
      for (final t in [if (row.running != null) row.running!, ...row.waiting]) {
        t._close(SendEnd.unreachable);
      }
      for (final c in row.held) {
        c.complete(SendEnd.unreachable);
      }
    }
    _rows.clear();
  }

  void _run(_Row row, Transmission t) {
    row.running = t;
    t._started = DateTime.now();
    _quiet(t.hop, row);
    _start(t);
  }

  void _quiet(String hop, _Row row) {
    row.quiet?.cancel();
    row.quiet = Timer(quietAfter, () {
      row.quiet = null;
      final t = row.running;
      if (t == null || !identical(_rows[hop], row)) return;
      final over = DateTime.now().difference(t._started) > dropAfter;
      if (!over && _held(t.target, t.targetPort)) {
        _quiet(hop, row); // not left yet: the handshake decides
        return;
      }
      if (over) t.cut = true;
      _finish(hop, row, SendEnd.unconfirmed);
    });
  }

  void _finish(String hop, _Row row, SendEnd how) {
    final t = row.running;
    if (t == null) return;
    row.quiet?.cancel();
    row.quiet = null;
    row.running = null;
    if (how == SendEnd.delivered) {
      delivered++;
    } else {
      unconfirmed++;
    }
    t._close(how);
    if (row.waiting.isEmpty) {
      if (row.empty) _rows.remove(hop);
      return;
    }
    final next = row.waiting.removeFirst();
    if (next.foreign) {
      row.foreignWaiting--;
      row.foreignBytes -= next.bytes;
    }
    _run(row, next);
  }
}
