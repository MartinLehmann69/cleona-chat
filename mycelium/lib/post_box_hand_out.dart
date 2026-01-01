/// The holder's hand-out under the one rule of silence (V4.2 §11.3a, §8.2).
///
/// A `0x33` of two or more parts is a transmission that expects its end mark
/// (§11.3). Until S407 the holder went on to the next entry whatever the
/// end, and a repeated proof (`0x36`) under a running hand-out started the
/// whole list again: the bootstrap handed the same four entries to a phone
/// it could not reach every 1.1 s for eight minutes (13.10.2026, 441 ×
/// "hand-out … ended unconfirmed", 01:28–01:36). Each pass answered a proof
/// that did arrive (`PostBoxHolder.onProof` is the only caller of the
/// hand-out) — the way back to the collector was silent.
///
/// Now the transmissions to one collector count as one request under the
/// rule: an unconfirmed end is a silent sending, a delivered one starts the
/// count over; after the sending and three repeats without an end mark the
/// hand-out stops, the collector's address is declared to the transport
/// ([Silence.failedAddress]) and nothing more is handed to it until a
/// transmission to it is confirmed again — a later proof gets one entry,
/// not the list.
library;

import 'package:mycelium/post_box_holder.dart' show Neighbour;
import 'package:mycelium/silence.dart';
import 'package:mycelium/split_flow.dart' show SendEnd;

/// Collectors whose silence is counted — bounded like the holder's open
/// questions (§20.2); the least recently touched goes.
const int kHandOutSilentAtMost = 64;

class HandOutSilence {
  final Silence _silence;
  final Map<String, SilentRounds> _rounds = {};

  HandOutSilence(this._silence);

  /// The transmission of a `0x33` to [to] ended [end]. `true`: the next
  /// entry may go out.
  bool ended(Neighbour to, Object? end) {
    // Unreachable (its handshake failed and was declared) or the bound for
    // others (§20.2): the holder hands out later.
    if (end == SendEnd.unreachable || end == SendEnd.refused) return false;
    final k = '${to.$1.address}:${to.$2}';
    final r = _rounds.remove(k) ?? SilentRounds();
    _rounds[k] = r; // most recent last
    while (_rounds.length > kHandOutSilentAtMost) {
      _rounds.remove(_rounds.keys.first);
    }
    if (end != SendEnd.unconfirmed) {
      r.progress();
      return true;
    }
    if (r.silent >= kSendingsAtMost) return false; // already declared
    if (r.again()) return true;
    _silence.failedAddress(to.$1, to.$2, 'hand-out 0x33');
    return false;
  }
}
