/// Diagnosis of a transmission of two or more parts at every station
/// (S412, proposal D-1 of `S411-RCA-LAUF7-C-ZERLEGTE-UEBERTRAGUNG.md` C-4,
/// owner approval for behaviour-neutral diagnosis).
///
/// The question it answers after a run: at which station, and why, did the
/// parts of a transmission get lost? Five stations (the fourth with the
/// release of a transmission kept after its end, D-90):
///
/// | station | where | line |
/// |---|---|---|
/// | sender, send loop | `split.dart` `_sendLoop` | `TRACE split out transmission … not taken by the socket` |
/// | recipient, re-request | `split.dart` `_onRest` | `TRACE split in from … transmission … round …` |
/// | sender, request it no longer knows | `split.dart` `_onMissingRequest` | `TRACE split out: … does not run (any more)` |
/// | sender, end of a transmission | `split_flow.dart` `_finish` | `TRACE split out transmission … (packet …) to …: <end> after …` |
/// | sender, release of one kept after its end (D-90) | `split_flow.dart` `_release` | `TRACE split out transmission … kept after its end, released at …` |
/// | forwarder, hand-on | `node_codes.dart` (forwarder's send) | `TRACE step3 hand-on … as transmission …: <end> after …` |
///
/// **A clean transmission writes nothing in the splitter** (S406, owner
/// decision 07.10.2026 "A": nothing per packet on the transport path): each
/// splitter line stands only where something went wrong — a part the socket
/// did not take, a re-request round, a request for an unknown transmission,
/// an end that is not a delivery without any request. The forwarder's line
/// belongs to the step-3 layer, which writes per packet anyway (`TRACE step3`).
///
/// **The handle across nodes** is the first 4 B of the transmission
/// identifier (hex, as in `TRACE split … FAILED`) and the packet id
/// ([packetId], the same bytes at sender, forwarder and recipient). Neither
/// is an address, so the log redaction (`lib/core/log/log_redaction.dart`)
/// leaves both as they are; addresses get a marker salted per process and
/// do not join two logs — the port does.
///
/// Every function reads and writes a line: no packet, no clock, no decision.
/// On in the beta network only ([traceOn]).
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/split.dart' show kHeader;
import 'package:mycelium/split_flow.dart' show SendEnd, Transmission;
import 'package:mycelium/trace.dart' show hexShort, packetDescribe, packetId, traceOn;

/// The new transmission behind the future of a send of two or more parts —
/// set by the splitter, read by the forwarder's line. Weak: it holds nothing.
final Expando<String> _transmissionOf = Expando('transmission');

/// `split.dart` `send`: [end] belongs to the transmission whose first part is
/// [first], of [count] parts.
void traceTransmissionTag(Future<SendEnd> end, Uint8List first, int count) {
  if (traceOn) _transmissionOf[end] = '${hexShort(first)} ($count parts)';
}

/// Station 1: the send loop handed [notTaken] of the parts of [t] to a
/// socket that did not take them (send buffer full, shell closed).
void traceSplitNotTaken(void Function(String) say, Transmission t, int notTaken) {
  if (!traceOn || notTaken == 0) return;
  say('TRACE split out transmission ${hexShort(t.parts.first)} to ${t.hop}: '
      '$notTaken of ${t.parts.length} part(s) not taken by the socket (§11.1)');
}

/// Station 2: the recipient asks for what is missing — [round] counted
/// from the first request, [idle] rounds in a row without progress (D-43).
void traceSplitRound(void Function(String) say, Uint8List identifier, int round,
    int idle, int held, int count, InternetAddress from, int port) {
  if (!traceOn) return;
  say('TRACE split in from ${from.address}:$port transmission ${hexShort(identifier)} '
      'round $round ($idle without progress): $held of $count part(s) held, '
      '${count - held} asked again (§11.3)');
}

/// Station 3: a request ([asked] parts; 0 = the end mark) for a
/// transmission this node does not run (any more) — discarded. Since D-90
/// only for one released already (30 s since it began, a later one ended,
/// its end mark) or never sent by this node.
void traceSplitUnknownRequest(void Function(String) say, Uint8List identifier,
    int asked, InternetAddress from, int port) {
  if (!traceOn) return;
  say('TRACE split out: ${asked == 0 ? "end mark" : "request for $asked part(s)"} '
      'from ${from.address}:$port for transmission ${hexShort(identifier)}, which '
      'this node does not run (any more) — discarded (§11.3)');
}

/// Station 4: [t] ended [how]. Written unless it was a delivery without
/// any request and with every part taken by the socket.
void traceSplitEnd(void Function(String) say, Transmission t, SendEnd how) {
  if (!traceOn) return;
  if (how == SendEnd.delivered && t.requests == 0 && t.notTaken == 0) return;
  final now = DateTime.now();
  final whole = BytesBuilder(copy: false);
  for (final p in t.parts) {
    whole.add(Uint8List.sublistView(p, kHeader));
  }
  say('TRACE split out transmission ${hexShort(t.parts.first)} (packet '
      '${packetId(whole.takeBytes())}) to ${t.hop}: ${how.name} after '
      '${now.difference(t.started).inMilliseconds} ms, last part out '
      '${now.difference(t.lastOut).inMilliseconds} ms before, ${t.parts.length} '
      'part(s), ${t.requests} request(s) answered with ${t.again} part(s) again, '
      '${t.notTaken} not taken by the socket${t.cut ? ", cut at the drop deadline" : ""}');
}

/// Station 4, continued (D-90): [t] ended unconfirmed for its flow, was kept
/// answerable, and is released now — at [why]. Written always: its end was
/// already not clean, and only this line tells whether a late request was
/// answered and whether its end mark came after all.
void traceSplitKeptEnd(void Function(String) say, Transmission t, String why) {
  if (!traceOn) return;
  say('TRACE split out transmission ${hexShort(t.parts.first)} to ${t.hop}: kept '
      'after its end, released at $why, '
      '${DateTime.now().difference(t.started).inMilliseconds} ms after it began; '
      '${t.late} late request(s) answered, ${t.again} part(s) again in all (§11.3)');
}

/// Station 5, the forwarder (§8.1): the packet [p] handed on to
/// [target]:[port], the new transmission it went out as, and how that ended.
/// It only watches [end] — nothing is repeated or judged here. One part has
/// no end mark to wait for and writes nothing (its `TRACE step3 out` says it).
void traceHandOn(void Function(String) say, Uint8List p, InternetAddress target,
    int port, Future<SendEnd> end) {
  if (!traceOn) return;
  final as = _transmissionOf[end];
  if (as == null) return;
  final since = DateTime.now();
  final what = packetDescribe(p);
  unawaited(end.then((how) => say('TRACE step3 hand-on $what to ${target.address}:'
      '$port as transmission $as: ${how.name} after '
      '${DateTime.now().difference(since).inMilliseconds} ms')));
}
