/// Diagnosis of lane 3 at the sender (S412): which holders a transfer asks,
/// who refused and why, and which `0x53` matched no open. Only the beta
/// network writes ([traceOn]); nothing is sent and nothing is decided here.
///
/// Per transfer and per open, never per piece (S406 "A": nothing per packet
/// on the transport path) — at most one line per candidate, one per
/// transfer, and one per `0x53` that matches no open (an anomaly: a reply to
/// an address form the open did not go to, a late final count, a stranger).
///
/// Asked by the E2E runs 7 and before (S412-SMOKES-GRUPPE4.md, suites 3 and
/// 4): "no holder accepted" while other media suites ran beside, and the log
/// named neither the candidates nor the refusals.
library;

import 'dart:typed_data';

import 'package:mycelium/bulk_piece.dart' show tagHex;
import 'package:mycelium/card.dart' show CardAddress;
import 'package:mycelium/trace.dart' show traceOn;

String _short(Uint8List tag) => tagHex(tag).substring(0, 8);

/// Once per transfer, before the first open: the candidates in the order
/// they are asked and how many shares there are.
void bulkTraceCandidates(void Function(String)? report, Uint8List tag,
    List<CardAddress> candidates, int shares, {bool resumed = false}) {
  if (!traceOn || report == null) return;
  report('TRACE bulk ${_short(tag)}: ${candidates.length} candidate(s) for '
      '$shares share(s)${resumed ? ' (resumed)' : ''}: ${candidates.join(', ')}');
}

/// An open that did not get its count: [answer] `null` = no `0x53` within
/// the wait, else the count the holder [from] stated.
void bulkTraceRefused(void Function(String)? report, Uint8List tag,
    CardAddress from, int? answer, int count) {
  if (!traceOn || report == null) return;
  final why = answer == null
      ? 'no answer within the wait'
      : answer == 0 ? 'refused (count 0)' : 'count $answer of $count';
  report('TRACE bulk ${_short(tag)}: holder $from — $why');
}

/// A `0x53` from [from] that matches neither a waiting open nor a final
/// count. [waiting] are the addresses this placer waits on for the SAME
/// transfer — a reply from another form of one of them (loopback against
/// segment address) shows here.
void bulkTraceStray(void Function(String)? report, Uint8List tag,
    CardAddress from, int count, Iterable<String> waiting) {
  if (!traceOn || report == null) return;
  final w = waiting.toList();
  report('TRACE bulk ${_short(tag)}: 0x53 from $from (count $count) matches '
      'no open — waiting on ${w.isEmpty ? 'nothing for this transfer' : w.join(', ')}');
}
