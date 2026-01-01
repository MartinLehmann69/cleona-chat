/// The log lines of the post box that NAME the holders (measurement O2,
/// report S398-O2, finding 4): until now a deposit said
/// "to 3 neighbour(s)" and "NOT placed, 1 receipt(s)" — which holder was asked,
/// which one acknowledged, and whether a receipt came only after the result
/// was fixed could not be read from any log.
///
/// Log only: nothing here chooses a holder, changes a deadline or counts.
/// The addresses go into the report as `address:port`; the app's log sink
/// redacts them like every other address (`log_redaction.dart`).
library;

import 'dart:typed_data';

import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/post_box_disk.dart' show kIdLength, kValueLength;
import 'package:mycelium/post_box_holder.dart'
    show Neighbour, Send, kDepositHeader, kHereItIsHeader, kNodeIdentifierLength;
import 'package:mycelium/post_box_proof.dart';
import 'package:mycelium/post_box_runs.dart';
import 'package:mycelium/update_manifest_compartment.dart' show isManifestValue;
import 'package:mycelium/update_trace.dart';

/// How many `kind|sender` pairs [LengthLog] reports in the life of a node.
/// A fixed cap, not a window: whoever sends malformed packets from many
/// addresses writes at most this many lines (R-2).
const int kLengthNotedAtMost = 64;

/// The length a post-box packet must have, by kind. `null`: [packet] has it,
/// or is no post-box packet; otherwise what was expected, as text for the log.
String? lengthExpected(Uint8List packet) {
  if (packet.isEmpty) return null;
  final n = packet.length;
  const receipt = 1 + kIdLength + kNodeIdentifierLength + kRequestIdLength;
  const nothing = 1 + kValueLength + kRequestIdLength;
  const task = 1 + kRandomLength + kNodeIdentifierLength + kRequestIdLength;
  return switch (packet[0]) {
    kinds.kDeposit when n < kDepositHeader => 'at least $kDepositHeader B',
    kinds.kDeposited when n != receipt && n != kDeleteReceiptLength =>
      '$receipt B (receipt) or $kDeleteReceiptLength B (deletion)',
    kinds.kCollect when n != kCollectLength => '$kCollectLength B',
    kinds.kHereItIs when n < kHereItIsHeader => 'at least $kHereItIsHeader B',
    kinds.kNothingThere || kinds.kRefused when n != nothing => '$nothing B',
    kinds.kCollectTask when n != task => '$task B',
    kinds.kCollectProof when n != kProofLength => '$kProofLength B',
    _ => null,
  };
}

/// Names a post-box packet that is discarded for its length — kind, length,
/// expected length and sender — ONCE per kind and sender. The discard itself
/// stays silent on the wire (§11.6: an unparseable packet gets no answer);
/// without this line it was silent in the log too, and a holder speaking
/// another packet format could not be told from a holder that is off (S399
/// step 4: a holder on the format before the request identifier). Log only:
/// it decides nothing, the handlers discard as before.
class LengthLog {
  final void Function(String)? report;
  final Set<String> _noted = {};
  LengthLog(this.report);

  void check(Uint8List packet, Neighbour from) {
    final expected = lengthExpected(packet);
    if (expected == null || report == null) return;
    final kind = '0x${packet[0].toRadixString(16).padLeft(2, '0')}';
    if (_noted.length >= kLengthNotedAtMost) return;
    if (!_noted.add('$kind|${neighbourKey(from)}')) return;
    report!('post box: $kind of ${packet.length} B from ${neighbourKey(from)} '
        'discarded — expected $expected (reported once per kind and sender)');
  }
}

/// `a:p, b:p, c:p` — the holders in the order they were addressed.
String holdersNamed(List<Neighbour> holders) =>
    holders.map(neighbourKey).join(', ');

/// Notes when [key]'s receipt to [h] came — and whether the run was already
/// placed then. The first receipt of a holder counts. A run is never fixed
/// as NOT placed while a receipt can still arrive (S398, OP-19 part C), so
/// "after placed" is the only case of a receipt after the result.
void ackNoted(DepositRun h, String key) {
  final t = h.sentAt;
  if (t == null || h.ackMs.containsKey(key)) return;
  h.ackMs[key] = DateTime.now().difference(t).inMilliseconds;
  if (h.placed == true) h.afterPlaced.add(key);
}

/// The final line of a deposit run: per addressed holder when its receipt
/// came (`acked in N ms`, with `(after placed)` when two nodes had already
/// acknowledged) or that none came before its transmission ended (`silent`).
/// The result is read from [DepositRun.placed],
/// never recomputed (S398, OP-22: two computations contradicted each other).
String depositOutcome(DepositRun h, String valueShort) {
  final parts = [
    for (final n in h.asked)
      switch (h.ackMs[neighbourKey(n)]) {
        null => '${neighbourKey(n)} silent',
        final ms when h.afterPlaced.contains(neighbourKey(n)) =>
          '${neighbourKey(n)} acked in $ms ms (after placed)',
        final ms => '${neighbourKey(n)} acked in $ms ms',
      },
  ];
  final p = h.placed;
  final r = p == null ? 'open' : (p ? 'placed' : 'NOT placed');
  return 'deposit under $valueShort ended ($r, ${h.node} node(s)): '
      '${parts.join('; ')}';
}

/// What [t] still waits for, for the log: no task yet, or per unanswered
/// value `received/announced` (`?`: no `0x33`, `0x34` or `0x37` came).
String talkOpen(Conversation t) {
  if (t.random == null) return '${neighbourKey(t.holder)} no task';
  final open = [
    for (final v in t.of.ask.keys)
      if (!t.done(v))
        '${v.substring(0, 8)} ${t.received(v)}/${t.expected[v] ?? '?'}'
  ];
  return '${neighbourKey(t.holder)} ${open.join(', ')}';
}

/// The holder's way out with its hand-outs readable: every `0x33` with how
/// its transmission ended, and a `0x34`/`0x37` whose send ended otherwise
/// than sent — a hand-out that stops is silent otherwise (§8.2).
Send answersLogged(Send send, void Function(String)? report) {
  return (p, to) {
    final s = send(p, to);
    final k = p.isEmpty ? 0 : p[0];
    final answer =
        k == kinds.kHereItIs || k == kinds.kNothingThere || k == kinds.kRefused;
    // §26.5.4: what this holder hands out under the public manifest value.
    if (answer && p.length > kValueLength && isManifestValue(p.sublist(1, 1 + kValueLength))) {
      updateTrace('manifest-answer',
          reason: '0x${k.toRadixString(16)} of ${p.length} B to ${neighbourKey(to)} — '
              '${k == kinds.kHereItIs ? 'the held manifest' : k == kinds.kNothingThere ? 'nothing held' : 'refused'}');
    }
    if (report == null || s is! Future || !answer) return s;
    final value = p.length > 4 ? asHex(p.sublist(1, 5)) : '';
    return s.then((end) {
      final e = '$end'.split('.').last;
      if (k == kinds.kHereItIs || (e != 'sent' && e != 'delivered')) {
        report('hand-out: 0x${k.toRadixString(16)} of ${p.length} B under '
            '$value to ${neighbourKey(to)} ended $e');
      }
      return end;
    });
  };
}

/// The final line of a collection run, written once every asked holder is
/// done: per holder how many pieces it handed out, that its link ended
/// unanswered, or that its question was dropped at an edge.
String collectOutcome(CollectionRun a) {
  final parts = [
    for (final t in a.talks.values)
      '${neighbourKey(t.holder)} ${switch (t.end) {
        TalkEnd.unreachable => 'unreachable',
        TalkEnd.dropped => 'not put',
        TalkEnd.quiet => '${t.pieces} piece(s), then silent',
        _ => '${t.pieces} piece(s)',
      }}',
  ];
  return 'collect: ${a.ask.length} value(s), ${a.found.length} new piece(s): '
      '${parts.join('; ')}';
}
