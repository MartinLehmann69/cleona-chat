/// One request of the durable-object class: sent ONCE, answered or failed
/// (v4_2 §11.3a "The transport alone handles silence", owner 13.10.2026).
/// S407 SK-1.
///
/// §11.3a: the layers above the transport hand a packet to it and learn one
/// of two things — answered, or failed; they do not repeat, count or time
/// anything themselves. The repeats (at most three) are built ONCE in the
/// transport by a separate work package. Until that request path exists,
/// this class is the one place where the durable-object class waits for an
/// answer: it sends once, waits the answer wait that belongs to the request,
/// and reports "failed" when nothing came. No repeat, no counter.
///
/// **Made to be replaced.** Every request of `0x90`, `0x92`, `0x95` and
/// `0x97` goes through [DurableAsk] and nowhere else, with the same three
/// calls — [start], [answered], and the failure callback. A transport-level
/// request that repeats on silence takes its place inside this file; the
/// callers do not change.
///
/// **Where the wait starts** — at the end of the transmission as §11.3
/// defines it (§8.2 "placing ends", D-41). The splitter's future says how
/// it ended ([SendEnd]):
/// * [SendEnd.sent] — one part, gone: the wait is [kDurableAnswerWait]
///   (1.1 s, quiet period 300 ms + answer deadline 800 ms, `split_flow.dart`);
/// * [SendEnd.delivered] / [SendEnd.unconfirmed] — two or more parts, the
///   transmission's own 1.1 s already lies behind it (or the end mark came):
///   the answer itself gets the answer deadline, [kDurableAfterEndWait];
/// * [SendEnd.unreachable] / [SendEnd.refused] — the shell's handshake
///   stayed unanswered or the hop refused: failed at once (§11.6).
///
/// [SendEnd.unconfirmed] counts as not reached (§11.3, S426 N6-2).
///
/// The failure says whether the node was REACHED (S420, BL-2): only a node
/// that took the request and stayed silent lacks the capability (§16.0
/// "Older 4.2 versions … never asked twice"). A node the request never
/// reached says nothing about its capability and is asked again at the next
/// edge (§16.7 "deposited again at every edge").
library;

import 'dart:async';

import 'package:mycelium/split.dart' show SendEnd;

/// The answer wait after a single part (§11.3, D-41).
const Duration kDurableAnswerWait = Duration(milliseconds: 1100);

/// The answer wait after a transmission of two or more parts has ended.
const Duration kDurableAfterEndWait = Duration(milliseconds: 800);

class DurableAsk {
  final Future<SendEnd> Function() _send;
  /// [reached]: the request reached the node — one part handed over, or the
  /// recipient's end mark came — and no answer came; false when the
  /// transmission itself failed (unreachable, refused, send error) or ended
  /// without end mark (§11.3: "counts as that hop not answering", S426 N6-2).
  final void Function(String why, bool reached) _failed;
  final Duration answerWait;
  final Duration afterEndWait;
  Timer? _wait;
  bool _started = false;
  bool _done = false;

  DurableAsk(this._send, this._failed,
      {this.answerWait = kDurableAnswerWait,
      this.afterEndWait = kDurableAfterEndWait});

  bool get done => _done;

  void start() {
    if (_done || _started) return;
    _started = true;
    _send().then(_ended,
        onError: (Object e) => _fail('send failed: $e', reached: false));
  }

  void _ended(SendEnd end) {
    if (_done) return;
    if (end == SendEnd.unreachable || end == SendEnd.refused) {
      _fail('transmission ${end.name}', reached: false);
      return;
    }
    // §11.3: two or more parts without the recipient's end mark — under a
    // standing link (own or borrowed, D-92 A.3) the only end of a
    // transmission that never arrived (S426 N6-2). An older 4.2 version
    // sends the end mark for every kind (4.2.3 `split.dart`), so it is still
    // reached when it took the object and stays silent (§16.0).
    final reached = end != SendEnd.unconfirmed;
    _wait = Timer(
        end == SendEnd.sent ? answerWait : afterEndWait,
        () => _fail(reached ? 'no answer' : 'no answer, no end mark',
            reached: reached));
  }

  /// The answer arrived.
  void answered() => _end();

  /// The caller gave up (the node stops, the run ended otherwise).
  void cancel() => _end();

  void _end() {
    _done = true;
    _wait?.cancel();
    _wait = null;
  }

  void _fail(String why, {required bool reached}) {
    if (_done) return;
    _end();
    _failed(why, reached);
  }
}
