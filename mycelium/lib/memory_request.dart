/// The waiting requests of an invitation in the file layout of the memory
/// (§15.4, E-1) — moved here from `memory_invitation.dart` when
/// proposal M (S391) gave every request two more fields and the file stood at
/// 400 lines. The same cut as there: one section, one file.
///
/// ```
/// count (1 B)
/// per request: who (Address.length) + its rotation chain  — version 17
///           | origin: type (1 B: 4 | 6) | address (4 | 16) | port (u16)
///           | arrived (u64, milliseconds)
///           | introduction: u16 length + bytes (0 = none, S403)
///           | neighbour of the requester (flag + address)   — version 14
///           | answer code: flag (1 B) + 16 B               — version 14
/// ```
///
/// Neighbour and answer code must go along: the decision can fall hours after
/// the request (§12.5), and without them the inviter after a
/// restart knows neither the route under the answer code nor the fixed neighbour
/// of its new contact. The day keys and the mark "collected" of proposal E
/// do NOT stand here — they lie in the store of `memory_first_contact.dart`,
/// so that this file layout (version 16) stays as 4.2.0-beta wrote it.
///
/// The INTRODUCTION does not go along any more (S403, finding 4): name and
/// greeting of a waiting request are content, and content lives in the
/// identity's message store (§21.4.2 — the app keeps them in the pending
/// contact record; a restored request is never re-reported to the app, so
/// no reader lost anything). The u16 length field STAYS in the layout — the
/// memory's version does not change (owner decision 28.09.2026: a version
/// change would delete this file on every running device,
/// `memory_enforcer.dart`), and entries that an older build wrote still
/// parse: the reader consumes length and bytes and uses neither.
library;

import 'dart:typed_data';

import 'package:mycelium/invitation.dart' as inv;
import 'package:mycelium/memory_contact.dart'
    show addressChainRead, addressChainWrite;
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
    addressChainWrite(b, a.who);
    b.addByte(a.origin.kind.byteValue);
    b.add(a.origin.address);
    b.add(_u16(a.origin.port));
    b.add(_u64(a.at.millisecondsSinceEpoch));
    // §21.4.2 (S403, finding 4): the introduction is content and lives in
    // the identity's message store, not here. The field stays in the
    // layout (no version change — see the header), always as `0 = none`.
    b.add(_u16(0));
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
    final who = addressChainRead(l);
    final kind = CardAddressType.fromByte(l.byte());
    if (kind == null) throw MemoryError('unknown address type');
    final origin = CardAddress(l.bytes(kind.addressLength), l.u16());
    final at = DateTime.fromMillisecondsSinceEpoch(l.u64());
    final packed = l.bytes(l.u16());
    // The form is still checked — a bent file stays a bent file — but
    // the content is not used: entries of an older build parse the same
    // way, and the text lives in the message store (§21.4.2, S403).
    try {
      introductionRead(packed, 0);
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
        introduction: null,
        neighbour: neighbour,
        answerCode: answerCode));
  }
  return out;
}

Uint8List _u16(int v) =>
    (ByteData(2)..setUint16(0, v, Endian.big)).buffer.asUint8List();
Uint8List _u64(int v) =>
    (ByteData(8)..setUint64(0, v, Endian.big)).buffer.asUint8List();
