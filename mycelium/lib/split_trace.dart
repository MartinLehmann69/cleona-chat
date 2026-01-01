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
/// Set aside for now by the TEMPORARY measurement [kTraceEveryEnd] (S427).
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

import 'package:mycelium/kinds.dart' as kinds;
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

/// TEMPORARY measurement (S427, owner 18.11.2026 F2 "A", case AVM 4.07: a
/// transmission Node1 → bootstrap left no line on either side). While `true`
/// every end at the sender writes, a clean one too, and every whole packet of
/// two or more parts at the recipient ([traceSplitWhole]) — the packet id joins
/// the two logs. It sets aside owner decision 07.10.2026 "A" (nothing per
/// packet on the transport path) for this measurement only, with the owner's
/// consent ("weil das bleibt ja nicht dauerhaft und ist nur für die Messung"). german-ok
/// It is REMOVED once the cause is proven — the constant, its two uses and
/// [traceSplitWhole].
const bool kTraceEveryEnd = true;

/// Station 4: [t] ended [how]. Written unless it was a delivery without
/// any request and with every part taken by the socket ([kTraceEveryEnd]).
void traceSplitEnd(void Function(String) say, Transmission t, SendEnd how) {
  if (!traceOn) return;
  if (!kTraceEveryEnd && how == SendEnd.delivered && t.requests == 0 && t.notTaken == 0) return;
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

/// TEMPORARY ([kTraceEveryEnd]): the recipient holds [whole], [count] parts of
/// [identifier] from [from]:[port], and hands it up — to the receiver its kind
/// names (the dispatch `node_helpers.dart` `assign`). Written before the hand-up,
/// so it stands even when the receiver throws.
void traceSplitWhole(void Function(String) say, Uint8List identifier, int count,
    Uint8List whole, InternetAddress from, int port) {
  if (!traceOn || !kTraceEveryEnd || count < 2) return;
  say('TRACE split in from ${from.address}:$port transmission ${hexShort(identifier)} '
      'whole ($count parts): ${packetDescribe(whole)} — handed up to ${_takerOf(whole)}');
}

String _takerOf(Uint8List p) {
  final s = p.isEmpty ? -1 : p[0];
  if (kinds.isFirstContact(s)) return 'first contact';
  if (kinds.isMessage(s)) return 'an identity (message)';
  if (kinds.isAmendment(s)) return 'an identity (amendment)';
  if (kinds.isForward(s)) return 'step 3 (forwarder)';
  if (kinds.isPostBox(s)) return 'the post box';
  if (kinds.isBoard(s)) return 'the board';
  if (kinds.isWho(s) || kinds.isOutsideRoute(s)) return 'the outside route';
  if (kinds.isMedia(s)) return 'media';
  if (kinds.isGroup(s)) return 'groups';
  if (kinds.isUpdate(s)) return 'update';
  if (kinds.isEnrolment(s)) return 'enrolment';
  if (kinds.isDurable(s)) return 'durable';
  return 'nobody (unknown kind)';
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

/// Test-only measurement (S419, `smoke_kem_rotation_mailbox`, RCA
/// `S419-RCA-SMOKE-KEM-ROTATION-VOLL.md` D3): one line per end mark sent by
/// the recipient and per end mark that reached the sender. Off by default —
/// a clean transmission writes nothing in the field (owner decision
/// 07.10.2026 "A", see the head of this file); only a smoke switches it on.
bool traceEndMarks = false;

/// The recipient holds [identifier] whole ([count] parts) and sends its end
/// mark to [to]:[port].
void traceSplitEndMarkSent(void Function(String) say, Uint8List identifier,
    int count, InternetAddress to, int port) {
  if (!traceEndMarks) return;
  say('TRACE split in: transmission ${hexShort(identifier)} whole '
      '($count parts) — end mark sent to ${to.address}:$port');
}

/// The sender got the end mark for [identifier] from [from]:[port]; [how]
/// is null while the transmission still runs (it is then delivered).
void traceSplitEndMarkCame(void Function(String) say, Uint8List identifier,
    InternetAddress from, int port, SendEnd? how) {
  if (!traceEndMarks) return;
  say('TRACE split out: end mark for ${hexShort(identifier)} from '
      '${from.address}:$port — '
      '${how == null ? "running: delivered" : "kept (${how.name}): released only"}');
}
