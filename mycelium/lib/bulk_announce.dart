/// The announcement of a media transfer of lanes 2 and 3 (§9.4, §17.6,
/// D-29, D-30) — the payload the application sends as an ordinary sealed
/// message (`MTV3_MEDIA_ANNOUNCE`).
///
/// Two forms, told apart by the flag byte:
/// * **lane 3** — sent once the pieces lie with their holders; names them
///   (1 to [kHoldersAtMost]).
/// * **stream possible** ([BulkAnnouncement.stream], lane 2, §17.6
///   "Cascade and windows": announce → the recipient's request → volunteer)
///   — sent BEFORE anything is placed, with no holder (count 0). If the
///   stream does not come about, the sender places the object under the
///   SAME `K_T` and sends the lane 3 form afterwards (`MTV3_MEDIA_HOLDERS`):
///   the identifier stays the same, pieces are lane-neutral (§9.4).
///
/// It is the ONLY place `K_T` travels: the message is sealed like every
/// other one (§4.3), so the content of a transfer stays post-quantum sealed
/// although the holders see the pieces (§9.4 "The transfer key").
///
/// ## Layout
/// | Field | Size |
/// |---|---|
/// | `K_T` | 32 |
/// | object length | u32 BE |
/// | SHA-256 of the object | 32 |
/// | flags | u8: bit 0 [kAnnounceStream], every other bit 0 |
/// | number of holders | u8, 1 to [kHoldersAtMost]; 0 only with [kAnnounceStream] |
/// | per holder: type ‖ address ‖ port | 7 (IPv4) or 19 (IPv6), the card codec (`addressWrite`) |
/// | micro preview | the rest, at most [kAnnouncePreviewAtMost] |
///
/// With eleven IPv6 holders the fixed part is 279 B; with the preview the
/// announcement stays below 1.3 KB — two parts of `split.dart`, one message
/// against the bound of §8.2.
///
/// Pure functions: no socket, no clock, no state.
library;

import 'dart:typed_data';

import 'package:mycelium/bulk_piece.dart' show kHoldersAtMost, kTransferKeyLength;
import 'package:mycelium/card_address.dart'
    show CardAddress, CardFormatError, addressRead, addressWrite;
import 'package:mycelium/media.dart' show kAtMostObject;

/// The micro preview of an announcement — the budget of the offer this
/// replaces (969 B, "one cell"), kept: the preview shows in the bubble
/// before the object is collected, and a larger one would make every
/// announcement a third part on the wire for a picture 48 px wide.
const int kAnnouncePreviewAtMost = 969;

/// The fixed head before the holder list: `K_T`, length, SHA-256, flags,
/// count.
const int kAnnounceHead = kTransferKeyLength + 4 + 32 + 1 + 1;

/// Flag bit: the sender offers lane 2 and waits for the recipient's request
/// (§17.6). No 4.2 predecessor carried the byte — no compatibility branch
/// (D-21).
const int kAnnounceStream = 1; // bit 0 of a payload field, not a packet kind

/// What an announcement carries.
typedef BulkAnnouncement = ({
  Uint8List transferKey,
  int length,
  Uint8List sha256,
  List<CardAddress> holders,
  Uint8List preview,
  bool stream,
});

/// Packs an announcement. Throws [ArgumentError] on a field outside its
/// bound — the sender has a defect then, and it must not go out. [stream]
/// marks the form "stream possible"; it alone may name no holder.
Uint8List bulkAnnouncePack({
  required Uint8List transferKey,
  required int length,
  required Uint8List sha256,
  required List<CardAddress> holders,
  Uint8List? preview,
  bool stream = false,
}) {
  final pv = preview ?? Uint8List(0);
  if (transferKey.length != kTransferKeyLength) {
    throw ArgumentError('K_T of ${transferKey.length} B');
  }
  if (length <= 0 || length > kAtMostObject) {
    throw ArgumentError('object length $length — 1 to $kAtMostObject');
  }
  if (sha256.length != 32) throw ArgumentError('SHA-256 of ${sha256.length} B');
  if ((holders.isEmpty && !stream) || holders.length > kHoldersAtMost) {
    throw ArgumentError('${holders.length} holders — '
        '${stream ? 0 : 1} to $kHoldersAtMost');
  }
  if (pv.length > kAnnouncePreviewAtMost) {
    throw ArgumentError('preview of ${pv.length} B — at most '
        '$kAnnouncePreviewAtMost');
  }
  final b = BytesBuilder()
    ..add(transferKey)
    ..add([length >> 24 & 0xFF, length >> 16 & 0xFF, length >> 8 & 0xFF,
        length & 0xFF])
    ..add(sha256)
    ..addByte(stream ? kAnnounceStream : 0)
    ..addByte(holders.length);
  for (final h in holders) {
    addressWrite(b, h);
  }
  return (b..add(pv)).toBytes();
}

/// Reads an announcement; `null` if any field is outside its bound or the
/// bytes end early. There is no partial result: a guessed field would
/// point the collection at the wrong holders or the wrong object.
BulkAnnouncement? bulkAnnounceUnpack(Uint8List p) {
  if (p.length < kAnnounceHead) return null;
  var at = 0;
  Uint8List read(int n) {
    if (at + n > p.length) throw CardFormatError('announcement ends early');
    return Uint8List.fromList(Uint8List.sublistView(p, at, at += n));
  }

  try {
    final key = read(kTransferKeyLength);
    final length = ByteData.sublistView(read(4)).getUint32(0, Endian.big);
    final sha = read(32);
    final flags = read(1)[0];
    final count = read(1)[0];
    final stream = flags == kAnnounceStream;
    if (flags & ~kAnnounceStream != 0) return null;
    if (length == 0 || length > kAtMostObject) return null;
    if ((count == 0 && !stream) || count > kHoldersAtMost) return null;
    final holders = [
      for (var i = 0; i < count; i++) addressRead(read, 'holder ${i + 1}')
    ];
    final preview = read(p.length - at);
    if (preview.length > kAnnouncePreviewAtMost) return null;
    return (
      transferKey: key,
      length: length,
      sha256: sha,
      holders: holders,
      preview: preview,
      stream: stream,
    );
  } on CardFormatError {
    return null;
  } on ArgumentError {
    return null; // a port or address the codec refuses
  }
}
