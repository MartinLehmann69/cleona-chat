/// The `0x54` of a lane-3 collection round as a request under the one rule
/// of silence (V4.2 §11.3a, §9.4).
///
/// Until S407 a holder that did not answer a round's `0x54` left the round
/// open until the next edge, and the one thing that brought a restarted
/// holder back within the collection was the shell re-sending what went
/// out under the old key (`smoke_bulk_lane` case 4, "the ask plus one
/// edge"). That second repeat path is gone (S407-STILLE F-6): every holder's
/// `0x54` is now repeated by the transport until that holder answers — any
/// piece, "nothing here" or end of pass of that collection is its answer —
/// or its address has failed.
///
/// OLDER 4.2 HOLDERS (S407-KOMPAT #2, S407-INTEGRATION). A 4.2.3 holder
/// drops the "wanted" form without a word. The transport's first repeat of
/// an unanswered wanted form is therefore the from-stripe form, and that
/// holder gets only that form from then on ([WantedSpeakers]) — the repeat
/// is the one clock, no wait of its own.
library;

import 'dart:async';
import 'dart:io' show InternetAddress;
import 'dart:typed_data';

import 'package:mycelium/bulk_collection.dart';
import 'package:mycelium/bulk_want.dart' show WantedSpeakers;
import 'package:mycelium/card.dart' show CardAddress;
import 'package:mycelium/silence.dart';

/// The answers a round waits for, per collection and holder (`$holder`),
/// and the speakers that learn from them.
final Expando<({Map<String, Completer<void>> waits, WantedSpeakers speakers})>
    _heard = Expando('bulkHeard');

/// Sends [ask] to every holder of [c], each as a request with repeats;
/// [old] is the from-stripe form of the same round for an older holder.
void bulkAskRound(Silence silence, BulkCollection c, Uint8List ask,
    Uint8List old, WantedSpeakers speakers,
    void Function(Uint8List packet, CardAddress to) send) {
  bulkAskEnd(c); // a new round: the waits of the old one end
  final heard = <String, Completer<void>>{};
  _heard[c] = (waits: heard, speakers: speakers);
  for (final h in c.holders) {
    final w = heard['$h'] = Completer<void>();
    var sending = 0;
    unawaited(silence.ask(w.future,
        to: InternetAddress.fromRawAddress(Uint8List.fromList(h.address)),
        port: h.port,
        send: (_, __) => send(speakers.packet(ask, old, '$h', sending++), h),
        others: false,
        // A round that ended or was replaced ([bulkAskEnd]) completes its
        // waits without an answer: that is no answer and stamps nothing
        // (§11.8.4, S407-LB-P1 O-1).
        cancelled: () => !identical(_heard[c]?.waits, heard),
        what: 'media collect 0x54'));
  }
}

/// [from] answered [c] in this round.
void bulkHeard(BulkCollection c, CardAddress from) {
  final r = _heard[c];
  final w = r?.waits['$from'];
  if (w == null || w.isCompleted) return;
  r!.speakers.heard('$from');
  w.complete();
}

/// [c] is done, failed or asks anew: nothing is repeated for it any more.
void bulkAskEnd(BulkCollection c) {
  for (final w in _heard[c]?.waits.values ?? const <Completer<void>>[]) {
    if (!w.isCompleted) w.complete();
  }
  _heard[c] = null;
}
