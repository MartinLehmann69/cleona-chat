/// Lane 3 of §9.4 — the `0x54` that names WHICH stripes a collector still
/// lacks (S407 M-3).
///
/// The `from stripe` form (`bulk_piece.dart`) says "everything from stripe
/// N on". After a stream that fell back (§17.6) the collector holds stripes
/// scattered over the whole object, so N is small and the holder hands out
/// again the pieces of every complete stripe above it — measured 08.10.2026:
/// 626 pieces for 3 new stripes, about 20 s at `R_bulk`. The selective form
/// names the open stripes, as the stream's `0x5A` request does (§11.3): the
/// holder hands out only what is still missing.
///
/// | Kind | Form | Layout | Length |
/// |---|---|---|---|
/// | 0x54 | wanted | kind, tag 16, first stripe u32 BE, bitmap | 22 to 1158 |
///
/// Bit `k` of the bitmap (byte `k >> 3`, bit `k & 7`, lowest first) stands
/// for stripe `first + k`; a set bit = still open. The length tells the
/// three forms apart: 17 plain, 21 from stripe, 22 and more wanted. When
/// the open stripes run to the end without a gap, the shorter `from stripe`
/// form says the same; when the bitmap would not fit one part, too.
///
/// OLDER 4.2 HOLDERS (S407-KOMPAT #2). A 4.2.3 holder reads only the plain
/// and the from-stripe form and drops a longer `0x54` without a word. So
/// the "wanted" form goes only to a holder not known to be one of those
/// ([WantedSpeakers]); a holder that leaves it unanswered gets the
/// from-stripe form at the transport's first repeat (§11.3a,
/// `bulk_collect_ask.dart`) and from then on only that form. A holder that
/// answers the wanted form reads it.
library;

import 'dart:typed_data';

import 'package:mycelium/bulk_piece.dart'
    show collectPacket, kTagPacketLength, readCollect;
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/split.dart' show kMaxPayload;

const int _head = kTagPacketLength + 4; // 21

/// The `0x54` for [open] (ascending: the stripes below seven pieces) of an
/// object of [stripes] stripes.
Uint8List collectWantedPacket(Uint8List tag, List<int> open, int stripes) {
  if (open.isEmpty) return collectPacket(tag, stripes);
  final first = open.first, last = open.last;
  final tail = last == stripes - 1 && open.length == stripes - first;
  final bytes = ((last - first) >> 3) + 1;
  if (tail || _head + bytes > kMaxPayload) return collectPacket(tag, first);
  final p = Uint8List(_head + bytes)
    ..[0] = kinds.kBulkCollect
    ..setRange(1, kTagPacketLength, tag);
  ByteData.sublistView(p).setUint32(kTagPacketLength, first, Endian.big);
  for (final s in open) {
    final k = s - first;
    p[_head + (k >> 3)] |= 1 << (k & 7);
  }
  return p;
}

/// A `0x54` in any of its three forms: the tag, whether a stripe is asked,
/// and how to say it in a log line. `null` for another kind or length.
({Uint8List tag, bool Function(int stripe) wants, String says})?
    readCollectWanted(Uint8List p) {
  final c = readCollect(p);
  if (c != null) {
    return (tag: c.tag, wants: (s) => s >= c.from, says: 'from stripe ${c.from}');
  }
  if (p.length <= _head || p[0] != kinds.kBulkCollect) return null;
  final first = ByteData.sublistView(p).getUint32(kTagPacketLength, Endian.big);
  final bits = Uint8List.fromList(p.sublist(_head));
  var n = 0;
  for (final b in bits) {
    for (var x = b; x != 0; x &= x - 1) {
      n++;
    }
  }
  bool wants(int s) {
    final k = s - first;
    return k >= 0 && (k >> 3) < bits.length && bits[k >> 3] & (1 << (k & 7)) != 0;
  }

  return (
    tag: Uint8List.fromList(p.sublist(1, kTagPacketLength)),
    wants: wants,
    says: '$n open stripe(s) from stripe $first',
  );
}

/// Which holders read the "wanted" form, learned from their answers. No
/// clock: the transport's repeat is the "no answer" (§11.3a).
class WantedSpeakers {
  final Set<String> _speak = {}, _old = {}, _waits = {};

  /// The packet of the [sending]-th sending (0: the first, then the
  /// transport's repeats) of a round's [ask] to [holder]; [old] is the
  /// from-stripe form of the same round.
  Uint8List packet(Uint8List ask, Uint8List old, String holder, int sending) {
    if (ask.length <= _head || _speak.contains(holder)) return ask;
    if (_old.contains(holder)) return old;
    if (sending == 0) {
      _waits.add(holder);
      return ask;
    }
    // The wanted form stayed without an answer: an older 4.2 holder.
    _waits.remove(holder);
    _old.add(holder);
    return old;
  }

  /// [holder] answered: if only the wanted form had gone to it, it reads it.
  void heard(String holder) {
    if (_waits.remove(holder)) _speak.add(holder);
  }
}
