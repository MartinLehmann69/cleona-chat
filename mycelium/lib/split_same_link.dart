/// An end mark or request for a transmission that went to ANOTHER address
/// of the same counterpart (S426 N6-2, D73B-2, v4_2 §11.8.4): a multi-homed
/// counterpart answers from the address its routing picks, not the one it
/// was sent to (RFC 9000 §8.2.3). Measured: the workstation answers every
/// packet sent to its bridge address from its Wi-Fi address
/// (`S425-RCA-D73B-73W2.md`). Only addresses under ONE link count — the
/// packet opened under that link. Its own file: `split.dart` and
/// `split_flow.dart` are at the line budget.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/shell_counterpart.dart' show SameCounterpart;
import 'package:mycelium/split_flow.dart' show SplitFlow, Transmission;

/// The running or kept transmission [identifier] towards a hop that [same]
/// puts under one link with [from]:[fromPort]; `null` if there is none.
Transmission? answerableUnderLink(SplitFlow flow, Uint8List identifier,
    InternetAddress from, int fromPort, SameCounterpart? same) {
  if (same == null) return null;
  for (final hop in flow.hops.toList()) {
    final i = hop.lastIndexOf(':'); // `hopKey`: address, colon, port
    if (i < 0) continue;
    final a = InternetAddress.tryParse(hop.substring(0, i));
    final port = int.tryParse(hop.substring(i + 1));
    if (a == null || port == null || !same(a, port, from, fromPort)) continue;
    final t = flow.answerableFor(hop, identifier);
    if (t != null) return t;
  }
  return null;
}
