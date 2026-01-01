/// The `0x22` "hand on to these addresses" — its layout and whom a
/// forwarder hands it to (V4.2 §8.1; proposal "contacts as fixed
/// neighbours", version 3, 6.2).
///
/// | Field | Bytes | Content |
/// |---|---|---|
/// | kind | 1 | `0x22` |
/// | hops left | 1 | starts at 3 |
/// | next addresses | 1 + n × (7 or 19) | count n (1–3), then type + address + port of each next neighbour |
/// | inner | rest | one `0x20` |
///
/// The recipient's fixed neighbours all hold the same codes (§8.1), so the
/// inner `0x20` is the same for each of them: the sender's device sends ONE
/// packet, and its own fixed neighbour hands the inner packet to each
/// address.
///
/// **No amplifier for strangers.** One packet in, three out — a forwarder
/// does that only for a device that registered codes with it
/// (`CodeTable.deviceAt`): the node's own people. For anybody else it uses
/// the first address only, exactly what a `0x22` did before it carried a
/// list. [detourSpread] is that rule.
///
/// Separate from `forward.dart`, which stands at the line budget.
library;

import 'dart:typed_data';

import 'package:mycelium/card_address.dart';
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/neighbour_list.dart';

/// Builds a `0x22` that hands [inner] (a `0x20`) to each of [next] (1–3).
Uint8List detourBuild(List<CardAddress> next, Uint8List inner,
    {required int hopCount}) {
  if (inner.isEmpty || inner[0] != kinds.kForward) {
    throw ArgumentError('a detour carries only a 0x20');
  }
  final b = BytesBuilder(copy: false)
    ..addByte(kinds.kDetour)
    ..addByte(hopCount);
  neighbourListWrite(b, next, least: 1);
  b.add(inner);
  return b.toBytes();
}

/// A read `0x22`.
typedef Detour = ({int hopCount, List<CardAddress> next, Uint8List inner});

/// Reads a `0x22`; throws [CardFormatError] or [FormatException] on a
/// broken packet — the caller turns both into its own error.
Detour detourRead(Uint8List packet) {
  if (packet.length < 3) throw const FormatException('0x22 too short');
  var pos = 2;
  Uint8List read(int n) {
    if (pos + n > packet.length) throw const FormatException('0x22 too short');
    return Uint8List.sublistView(packet, pos, pos += n);
  }

  final next = neighbourListRead(read, 'next address', least: 1);
  return (
    hopCount: packet[1],
    next: next,
    inner: Uint8List.fromList(Uint8List.sublistView(packet, pos)),
  );
}

/// The addresses a forwarder hands the inner packet to: every one of
/// [next] for a [registered] device, otherwise only the first. An address
/// with port 0 is never a target.
List<CardAddress> detourSpread(List<CardAddress> next, bool registered) => [
      for (final a in registered ? next : next.take(1))
        if (a.port != 0) a,
    ];
