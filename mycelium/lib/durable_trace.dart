/// Diagnosis of the durable-object class (S422, D-123 (10), RCA S420 BL-6):
/// ONE success line at every station of the way a system-channel object
/// takes — the failures already write their own `Durable: …` lines. Only the
/// beta network writes ([traceOn]); nothing is sent and nothing is decided
/// here.
///
/// Every line has the same shape, so one grep follows one object:
///
/// ```
/// TRACE durable <step> <8 hex of the object|ch=<channel>> … — <what happened>
/// ```
///
/// | Step | Where | Station |
/// |---|---|---|
/// | `deposit-in` | holder, `durable_serve.dart` | a `0x90` taken in, kept or not |
/// | `deposit-ack` | author, `durable_deposit.dart` | a `0x91` from a holder |
/// | `deposit-refused` | author, `durable_deposit.dart` | a `0x94` from a holder |
/// | `stock-ask` | asker, `durable_questions.dart` | a `0x95` sent, or pending |
/// | `stock-answer` | asker, `durable_questions.dart` | a `0x96` taken in |
/// | `fetched` | fetcher, `durable_fetch.dart` | a complete, matching object |
///
/// One line per request, answer or object — never per fountain block, and
/// in idle none (§16.7 "In idle … zero"): every step follows a deposit, an
/// edge or an opening of the application. No user content: identifiers,
/// channel numbers, counts and node keys only (`log_redaction.dart`).
library;

import 'dart:typed_data';

import 'package:mycelium/card_address.dart' show CardAddress;
import 'package:mycelium/durable_fetch.dart' show nodeKey;
import 'package:mycelium/durable_id.dart';
import 'package:mycelium/trace.dart' show traceOn;

/// The steps in the order of a complete run (deposit, then a reader).
const List<String> kDurableTraceSteps = <String>[
  'deposit-in',
  'deposit-ack',
  'deposit-refused',
  'stock-ask',
  'stock-answer',
  'fetched',
];

String _short(Uint8List hash) => hash
    .take(4)
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

void _line(void Function(String)? report, String step, String rest) {
  if (!traceOn || report == null) return;
  report('TRACE durable $step $rest');
}

/// Holder: a `0x90` from [from] was decided — [kept] answers `0x91`,
/// otherwise `0x94`, [why] names the reason.
void durableTraceDepositIn(void Function(String)? report, DurableId id,
        CardAddress from, int bytes, {required bool kept, required String why}) =>
    _line(report, 'deposit-in',
        '${_short(id.hash)} ch=${id.channel} $bytes B from ${nodeKey(from)} — '
        '$why, answered ${kept ? '0x91' : '0x94'}');

/// Author: holder [from] acknowledged (`0x91`); [acked] of [needed].
void durableTraceDepositAck(void Function(String)? report, Uint8List hash,
        int channel, CardAddress from, int acked, int needed) =>
    _line(report, 'deposit-ack',
        '${_short(hash)} ch=$channel from ${nodeKey(from)} — $acked of $needed');

/// Author: holder [from] refused (`0x94`); the next candidate is asked, the
/// holder does not count as failed.
void durableTraceDepositRefused(void Function(String)? report, Uint8List hash,
        int channel, CardAddress from) =>
    _line(report, 'deposit-refused',
        '${_short(hash)} ch=$channel from ${nodeKey(from)} — 0x94, next holder');

/// Author: a deposit starts (S424 M-4) — the [candidates] in the order they
/// are asked, and the nodes of the holder order [leftOut] because they were
/// reached and stayed silent earlier this run. Not in [kDurableTraceSteps]:
/// a diagnosis line, written once per deposit, never in idle.
/// [noteOf] (S425 N3-3 measurement): per candidate when its address was last
/// confirmed and whether it answered in this run — a candidate confirmed only
/// in an earlier run of the daemon is told apart.
void durableTraceDepositStart(void Function(String)? report, Uint8List hash,
        int channel, List<CardAddress> candidates, List<CardAddress> leftOut,
        {String Function(CardAddress)? noteOf}) =>
    _line(report, 'deposit-start',
        '${_short(hash)} ch=$channel — ${candidates.length} candidate(s): '
        '${candidates.map((c) => noteOf == null ? nodeKey(c) : '${nodeKey(c)} (${noteOf(c)})').join(', ')}; left out as failed: '
        '${leftOut.isEmpty ? 'none' : leftOut.map(nodeKey).join(', ')}');

/// Author: holder [holder] gave way without `0x91`/`0x94` (S424 M-4) —
/// [why] from [DurableAsk]; [reached]: the request reached it and it stayed
/// silent (failed only if it never showed the capability, S424 F-9),
/// otherwise the handshake was unanswered.
void durableTraceDepositGone(void Function(String)? report, Uint8List hash,
        int channel, CardAddress holder, String why, {required bool reached}) =>
    _line(report, 'deposit-gone',
        '${_short(hash)} ch=$channel from ${nodeKey(holder)} — $why, '
        '${reached ? 'reached and silent' : 'not reached'}, next holder');

/// Asker: an edge of §16.0 reached the stock questions, or the first capable
/// node became known and released an edge kept back (S429 VL2-4 measurement:
/// in run 20261119-000447 node1 asked for the stock for the first time 38 min
/// after its start, with no line naming why). Not in [kDurableTraceSteps]: a
/// diagnosis line, written at an edge or once per run, never in idle.
void durableTraceEdge(void Function(String)? report, String what) =>
    _line(report, 'edge', what);

/// Asker: a `0x95` for [channel] went to [to]; [to] `null`: no capable node
/// known, the question waits for the first one.
void durableTraceStockAsk(void Function(String)? report, int channel,
        CardAddress? to, {int? since, bool fetch = false}) =>
    _line(report, 'stock-ask',
        to == null
            ? 'ch=$channel pending — no capable node known'
            : 'ch=$channel since=${since ?? '-'} to ${nodeKey(to)} fetch=$fetch');

/// Asker: the `0x96` of [from] for [channel] — "same" or [ids] identifiers.
void durableTraceStockAnswer(void Function(String)? report, int channel,
        CardAddress from, {required bool same, int ids = 0}) =>
    _line(report, 'stock-answer',
        'ch=$channel from ${nodeKey(from)} — ${same ? 'same' : '$ids id(s)'}');

/// Fetcher: [id] is complete and matches its identifier.
void durableTraceFetched(void Function(String)? report, DurableId id,
        CardAddress namer, int bytes) =>
    _line(report, 'fetched',
        '${_short(id.hash)} ch=${id.channel} from ${nodeKey(namer)} ($bytes B)');
