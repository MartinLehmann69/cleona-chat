/// Step 3: a first hop that does not answer hands the same sending to the
/// next possible hop, after the last to the shared node directly (V4.2 §8.1
/// "the only possible first hop"; S405, owner decision 06.10.2026, variant B
/// — the reasoning stands in `code_send.dart`).
///
/// Two signals mean "did not answer": a handshake towards the hop got no
/// answer (`Shell.onSilent`, flight 1 and three repeats, 3.2 s, §11.3a), or
/// the transmission of two or more parts to it ended without its end mark
/// (`SendEnd.unconfirmed`/`unreachable`, 1.1 s after the last part, §11.3;
/// [StepThreeRetry.watch]). The second covers a hop whose link still stands
/// but which has gone (S410 E2E run 5, AVM 4.07: a receipt lost via a
/// stopped node; owner 30.10.2026, fix B). A one-part sending
/// (`SendEnd.sent`) gives no verdict — §11.3 has no end mark for it; what
/// the hop does with it is the forwarder's business (§8.1), and the other
/// steps of the ladder run anyway (§7.1).
///
/// Out of `node_codes.dart` for the line budget (mycelium/README.md rule 2).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/card_address.dart';
import 'package:mycelium/cover_stream.dart' show kOpenSetAtMost;
import 'package:mycelium/forward.dart';
import 'package:mycelium/shell_link.dart' show kAnswerDeadline, kAttempts;
import 'package:mycelium/split.dart' show SendEnd;

/// The longest step 3 can take before the last resort goes out: every
/// candidate of the open set ([kOpenSetAtMost]) silent for its four answer
/// deadlines — a measure for probes. Nobody above the transport budgets
/// with it any more (S407-STILLE F-3): the join's plea is a request the
/// transport repeats and gives up (`node_join_plea.dart`). Field test
/// 06.10.2026: a join that timed itself gave up after 5 s while the hand-on
/// through three silent candidates took 4.8 s.
final Duration kStepThreeHandOnAtMost =
    kAnswerDeadline * (kAttempts * kOpenSetAtMost);

/// How long a sending waits for its hop's handshake verdict. Above the
/// shell's four answer deadlines (4 × 800 ms, `shell_link.dart`); after it the
/// entry is forgotten — the hop answered, or its link stood.
const Duration kHopVerdictAtMost = Duration(seconds: 5);

/// At most this many sendings wait for a verdict — the count is bounded
/// like everything a node holds for others' answers (§20.2).
const int kWaitingSendingsAtMost = 64;

class _Waiting {
  final Uint8List inside;
  final List<CardAddress> next;
  final List<CardAddress> later;
  final CardAddress? resort;
  final String code;
  final DateTime since;
  _Waiting(this.inside, this.next, this.later, this.resort, this.code, this.since);
}

/// The sendings of step 3 that wait for their first hop's verdict.
class StepThreeRetry {
  final Future<SendEnd> Function(Uint8List packet, CardAddress destination) _out;
  final void Function(String) _report;
  final DateTime Function() _now;
  final Map<String, List<_Waiting>> _byHop = {};

  /// Sendings handed on to a next hop or to the last resort — read only.
  int handedOn = 0;

  StepThreeRetry(this._out, this._report, {DateTime Function()? clock})
      : _now = clock ?? DateTime.now;

  static String _key(InternetAddress a, int port) => '${a.address}:$port';
  static String _keyOf(CardAddress c) => _key(
      InternetAddress.fromRawAddress(Uint8List.fromList(c.address)), c.port);

  /// [inside] (the `0x20`) went to [hop] inside a `0x22` naming [next];
  /// [later] and [resort] are what follows if [hop] does not answer.
  void sent(CardAddress hop, Uint8List inside, List<CardAddress> next,
      List<CardAddress> later, CardAddress? resort, String code) {
    _forgetOld();
    if (later.isEmpty && resort == null) return;
    if (_byHop.values.fold<int>(0, (n, l) => n + l.length) >= kWaitingSendingsAtMost) {
      return; // the bound: this sending keeps only its first hop
    }
    _byHop
        .putIfAbsent(_keyOf(hop), () => [])
        .add(_Waiting(inside, next, later, resort, code, _now()));
  }

  /// [end] is how the `0x22` to [hop] ended: without the hop's end mark the
  /// hop did not answer — as [silent] (§11.3, fix B). `sent` (one part) and
  /// `delivered` give no verdict. A hop whose handshake failed was told by
  /// the shell first; then nothing waits here for it any more.
  void watch(Future<SendEnd> end, CardAddress hop) => end.then((e) {
        if (e != SendEnd.unconfirmed && e != SendEnd.unreachable) return;
        silent(InternetAddress.fromRawAddress(Uint8List.fromList(hop.address)), hop.port);
      });

  /// [target]:[port] did not answer: a handshake (the shell) or the end
  /// mark of a transmission ([watch]).
  void silent(InternetAddress target, int port) {
    _forgetOld();
    final waiting = _byHop.remove(_key(target, port));
    if (waiting == null) return;
    for (final w in waiting) {
      final gone = '${target.address}:$port';
      handedOn++;
      if (w.later.isNotEmpty) {
        final hop = w.later.first;
        sent(hop, w.inside, w.next, w.later.skip(1).toList(), w.resort, w.code);
        watch(_out(Forwarder.buildDetour(w.next, w.inside), hop), hop);
        _report('Step 3: hop $gone did not answer — the same sending via the '
            'next possible hop $hop to ${w.next.join(", ")} under code ${w.code}');
      } else {
        _out(w.inside, w.resort!);
        _report('Step 3: hop $gone did not answer — no other hop: 0x20 to the '
            'own fixed neighbour ${w.resort}, which the recipient named too — '
            'LAST RESORT, that node sees both ends, under code ${w.code}');
      }
    }
  }

  void _forgetOld() {
    final limit = _now().subtract(kHopVerdictAtMost);
    _byHop.removeWhere((_, l) {
      l.removeWhere((w) => w.since.isBefore(limit));
      return l.isEmpty;
    });
  }
}
