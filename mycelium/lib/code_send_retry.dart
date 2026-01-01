/// Step 3: a first hop that does not answer hands the same sending to the
/// next possible hop, after the last to the shared node directly (V4.2 §8.1
/// "the only possible first hop"; S405, owner decision 06.10.2026, variant B
/// — the reasoning stands in `code_send.dart`).
///
/// The signal is the shell's: a handshake towards the hop got no answer
/// (`Shell.onSilent`, two answer deadlines, 1.6 s). A hop whose link stands
/// gets the packet at once and gives no signal — what it does with it is the
/// forwarder's business (§8.1), and the other steps of the ladder run anyway
/// (§7.1).
///
/// Out of `node_codes.dart` for the line budget (mycelium/README.md rule 2).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/card_address.dart';
import 'package:mycelium/cover_stream.dart' show kOpenSetAtMost;
import 'package:mycelium/forward.dart';
import 'package:mycelium/shell_link.dart' show kAnswerDeadline, kAttempts;

/// The longest step 3 can take before the last resort goes out: every
/// candidate of the open set ([kOpenSetAtMost]) silent for its two answer
/// deadlines. Whoever waits for an answer to a step-3 sending (the first
/// contact's bundle, `mailbox_invitation.dart`) must wait at least this
/// long on top of its own budget — field test 06.10.2026: the join gave up
/// after 5 s while the hand-on through three silent candidates took 4.8 s.
final Duration kStepThreeHandOnAtMost =
    kAnswerDeadline * (kAttempts * kOpenSetAtMost);

/// How long a sending waits for its hop's handshake verdict. Above the
/// shell's two answer deadlines (2 × 800 ms, `shell_link.dart`); after it the
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
  final void Function(Uint8List packet, CardAddress destination) _out;
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

  /// The shell reports: [target]:[port] did not answer a handshake.
  void silent(InternetAddress target, int port) {
    _forgetOld();
    final waiting = _byHop.remove(_key(target, port));
    if (waiting == null) return;
    for (final w in waiting) {
      final gone = '${target.address}:$port';
      handedOn++;
      if (w.later.isNotEmpty) {
        final hop = w.later.first;
        _out(Forwarder.buildDetour(w.next, w.inside), hop);
        _report('Step 3: hop $gone did not answer — the same sending via the '
            'next possible hop $hop to ${w.next.join(", ")} under code ${w.code}');
        sent(hop, w.inside, w.next, w.later.skip(1).toList(), w.resort, w.code);
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
