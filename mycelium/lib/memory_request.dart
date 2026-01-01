/// The waiting requests of an invitation in the file layout of the memory
/// (§15.4, E-1) — moved here from `memory_invitation.dart` when
/// proposal M (S391) gave every request two more fields and the file stood at
/// 400 lines. The same cut as there: one section, one file.
///
/// ```
/// count (1 B)
/// per request: who (Address.length)
///           | origin: type (1 B: 4 | 6) | address (4 | 16) | port (u16)
///           | arrived (u64, milliseconds)
///           | introduction: u16 length + bytes (0 = none)
///           | neighbour of the requester (flag + address)   — version 14
///           | answer code: flag (1 B) + 16 B               — version 14
/// ```
///
/// Neighbour and answer code must go along: the decision can fall hours after
/// the request (§12.5), and without them the inviter after a
/// restart knows neither the route under the answer code nor the fixed neighbour
/// of its new contact.
library;

import 'dart:typed_data';

import 'package:mycelium/address.dart';
import 'package:mycelium/invitation.dart' as inv;
import 'package:mycelium/memory_invitation.dart' show MemoryError, Reader;
import 'package:mycelium/card_address.dart';
import 'package:mycelium/pair.dart' show kCodeLength;
import 'package:mycelium/introduction.dart';

/// Writes the waiting requests of an invitation in the order in
/// which they wait — it IS the displacement order. At most
/// [inv.kBufferPerInvitation]; what goes beyond that cannot exist in operation
/// (the buffer caps itself) and is rejected instead of
/// silently truncated.
void requestsEncode(BytesBuilder b, List<inv.WaitingRequest> requests) {
  if (requests.length > inv.kBufferPerInvitation) {
    throw ArgumentError('${requests.length} waiting requests, at most '
        '${inv.kBufferPerInvitation} are provided');
  }
  b.addByte(requests.length);
  for (final a in requests) {
    b.add(a.who.toBytes());
    b.addByte(a.origin.kind.byteValue);
    b.add(a.origin.address);
    b.add(_u16(a.origin.port));
    b.add(_u64(a.at.millisecondsSinceEpoch));
    final v = a.introduction;
    final packed = v == null || v.empty ? Uint8List(0) : v.pack();
    b.add(_u16(packed.length));
    b.add(packed);
    optionalAddressWrite(b, a.neighbour);
    final c = a.answerCode;
    b.addByte(c == null ? 0 : 1);
    if (c != null) b.add(c);
  }
}

/// Reads them back — as [inv.LoadedRequest], i.e. still without the
/// invitation that answers them; that is bound by `first_contact_invitation.dart`
/// as soon as the waiting invitation arises.
///
/// Everything is rejected that the buffer would never have produced: more than
/// [inv.kBufferPerInvitation] entries, an unknown address type byte, an
/// invalid flag — such a file is bent.
List<inv.WaitingRequest> requestsDecode(Reader l) {
  final count = l.byte();
  if (count > inv.kBufferPerInvitation) {
    throw MemoryError('$count waiting requests, at most '
        '${inv.kBufferPerInvitation} are provided');
  }
  final out = <inv.WaitingRequest>[];
  for (var i = 0; i < count; i++) {
    final who = Address.outBytes(l.bytes(Address.length));
    final kind = CardAddressType.fromByte(l.byte());
    if (kind == null) throw MemoryError('unknown address type');
    final origin = CardAddress(l.bytes(kind.addressLength), l.u16());
    final at = DateTime.fromMillisecondsSinceEpoch(l.u64());
    final packed = l.bytes(l.u16());
    final Introduction? self;
    try {
      self = introductionRead(packed, 0);
    } on IntroductionError catch (e) {
      throw MemoryError('Introduction of a waiting request: '
          '${e.reason}');
    }
    final neighbour = optionalAddressRead(l.bytes, 'neighbour of the request');
    final Uint8List? answerCode = switch (l.byte()) {
      0 => null,
      1 => l.bytes(kCodeLength),
      final f => throw MemoryError('invalid answer code flag $f'),
    };
    out.add(inv.LoadedRequest(
        who: who,
        origin: origin,
        at: at,
        introduction: self,
        neighbour: neighbour,
        answerCode: answerCode));
  }
  return out;
}

Uint8List _u16(int v) =>
    (ByteData(2)..setUint16(0, v, Endian.big)).buffer.asUint8List();
Uint8List _u64(int v) =>
    (ByteData(8)..setUint64(0, v, Endian.big)).buffer.asUint8List();
