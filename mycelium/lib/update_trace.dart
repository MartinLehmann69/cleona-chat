/// Diagnosis of the update path (S406-UPD2, owner order 07.10.2026: "build
/// in debug code, trace the fault bit by bit and end to end").
///
/// ONE line per event of the update path, on both sides — holder and
/// receiver — from the manifest to the installation. Every line has the same
/// shape, so one grep follows one update:
///
/// ```
/// TRACE update <step> seq=<sequence|-> v=<version|-> obj=<8 hex|-> plat=<platform|-> — <reason>
/// ```
///
/// The steps, in the order of a complete run, are listed in
/// [kUpdateTraceSteps]; `test/smoke/smoke_update_trace.dart` holds a run in
/// the process to that order.
///
/// No clock, no packet, no decision: every function writes a line and
/// returns. The lines go to the process-wide sink of `trace.dart`
/// ([traceNote]) — the node's report, whose TRACE lines the start paths put
/// on the TRACE level of the log file (`hostStart` `traceReport`, S406-DIAG).
/// On in the beta network only ([traceOn]).
library;

import 'dart:typed_data';

import 'package:mycelium/trace.dart' show traceNote, traceOn;

export 'package:mycelium/trace.dart' show traceOn;

/// The steps of the update path. Holder side first (what a holder does
/// before anyone asks), then the receiver in the order of a run.
const List<String> kUpdateTraceSteps = <String>[
  // holder
  'manifest-file', // a manifest file of the node handed to the carrier
  'manifest-held', // kept in the own post box under the public value
  'manifest-known', // the carrier's compartment took (or ignored) a manifest
  'object-hold', // a complete object held for others (path, size)
  'object-check', // the held object checked (SHA-256 against its name)
  'manifest-answer', // the post box answered a question for the manifest
  'task-out', // a piece request answered with a task
  'pieces-out', // pieces handed out (to whom, how many, first block)
  'no-pieces-out', // a piece request answered with "no pieces" (why)
  // receiver
  'ask', // a moment asks for the manifest (which moment)
  'ask-holders', // the neighbours asked under the manifest value
  'manifest-in', // a manifest arrived in the compartment (taken / why not)
  'manifest-decision', // newer / same seq higher / same / older / not valid
  'load-decision', // collect yes/no with every reason
  'retry-moment', // a moment hands the same target to the offer again
  'collect-start', // the collection for one target begins
  'target', // the target (object, seq, kind) set; a former one discarded
  'partial', // the target's partial state opened: new / resumed from disk
  'fetch-start', // the fetch path asks its holders
  'task-in', // a task arrived from the holder
  'round', // one answer at one holder: pieces, new, resolved, rtt
  'ask-again', // a request without any answer asked once more (§8.2)
  'holder-next', // the fetch path turns to the next holder (why)
  'object-complete', // the target object complete, SHA-256 matches
  'fetch-end', // the fetch path ended (object / without result)
  'verify', // SHA-256 and signature: expected / actual
  'discard', // a state discarded (why)
  'collect-end', // the collection ended (state)
  'offer-ready', // checked and ready: offered to the surface
  'click', // the click on "Installieren"
  'install', // the installation handed to the system
];

/// The first 4 B of [object] as hex — a 32-B hash, its 8-B fountain
/// identifier, or a hex text of either.
String updateObjectShort(Object? object) {
  if (object == null) return '-';
  if (object is Uint8List) {
    final n = object.length < 4 ? object.length : 4;
    return object
        .sublist(0, n)
        .map((x) => x.toRadixString(16).padLeft(2, '0'))
        .join();
  }
  final s = '$object';
  return s.isEmpty ? '-' : (s.length <= 8 ? s : s.substring(0, 8));
}

/// The line of [step] — without the leading `TRACE ` of the sink.
String updateTraceLine(String step,
        {int? seq,
        String? version,
        Object? object,
        String? platform,
        String? reason}) =>
    'update $step seq=${seq ?? '-'} v=${version ?? '-'} '
    'obj=${updateObjectShort(object)} plat=${platform ?? '-'}'
    '${reason == null || reason.isEmpty ? '' : ' — $reason'}';

/// Writes the line of [step] to the process-wide sink ([traceNote]).
void updateTrace(String step,
    {int? seq,
    String? version,
    Object? object,
    String? platform,
    String? reason}) {
  if (!traceOn) return;
  assert(kUpdateTraceSteps.contains(step), 'unknown update trace step $step');
  traceNote(updateTraceLine(step,
      seq: seq,
      version: version,
      object: object,
      platform: platform,
      reason: reason));
}
