/// The wire form of the fetch path for the public update (V4.2 §26.6.1,
/// „The fetch path"; decision P1 of 14.09.2026) — build and read packets,
/// and the task of the holder. S387.
///
/// ## Why fountain blocks
/// §26.6.1: „A request names the object, never individual pieces." A
/// holder who does not learn WHICH pieces are missing must send pieces
/// of which each one helps — rateless blocks achieve that: any
/// ~k·(1+ε) different ones assemble the object (`lib/core/fountain/`,
/// the same block size 1024 B as `media.dart`). Indexed pieces
/// would demand either the list of missing ones — exactly what the request
/// must not name — or would run into the coupon collector problem (n·ln n).
///
/// ## Packet layout
/// | Kind | Layout | Length |
/// |---|---|---|
/// | 0x70 request | kind, object 32, task 16 | 49 B |
/// | 0x71 task | kind, object 32, task 16 | 49 B |
/// | 0x72 piece | kind, fountain block 1041 | 1042 B |
/// | 0x73 none | kind, object 32 | 33 B |
///
/// Object = SHA-256 of the whole object, as the manifest names it
/// (`binHash`). Its first 8 B are the object identifier in the fountain block.
/// 1042 B fit into ONE part packet (`split.dart`: 1188 B payload).
///
/// ## The task
/// A request (49 B) triggers up to [kPiecesPerAnswer] × 1042 B — to
/// a forged sender address that would be an amplification by roughly
/// seven hundred times. The holder therefore delivers only to a source that
/// returns its task, i.e. has RECEIVED it. Stateless:
/// `SHA-256(Geheimnis ‖ IP ‖ Port ‖ Fenster ‖ Objekt)[0:16]`; the current
/// and the previous window are valid. The same pattern as the task of the
/// post box (`post_box_proof.dart`), only without a table.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/fountain/fountain_block.dart';
import 'package:mycelium/kinds.dart' as kinds;

/// A neighbour: only its network address. The same form as `Neighbour` in
/// `post_box_holder.dart`, own name for the same reason as
/// `MedienQuelle`.
typedef UpdateNeighbour = (InternetAddress address, int port);

/// Sends a packet to a neighbour.
typedef UpdateSend = void Function(Uint8List packet, UpdateNeighbour target);

const int kObjectLength = 32;
const int kTaskLength = 16;
const int kPleaLength = 1 + kObjectLength + kTaskLength;
const int kNoLength = 1 + kObjectLength;
const int kPiecePacketLength = 1 + kFountainBlockBytes;

/// Pieces per answered request.
///
/// **Set PROVISIONALLY, not decided** — decision point in the
/// report `berichte/S387-BAU-UPDATE.md`. Price: 32 × 1042 B = 33 KB per
/// round from holder to assembler; a 30-MB object needs roughly 30 000
/// pieces, i.e. roughly 950 rounds. Larger means fewer requests and
/// larger bundles on the wire (loss with small receive buffers),
/// smaller means more requests.
const int kPiecesPerAnswer = 32;

/// Length of a task window. Provisional, as with the post box.
const Duration kTasksWindow = Duration(minutes: 10);

void _objectCheck(Uint8List object) {
  if (object.length != kObjectLength) {
    throw ArgumentError('Object must be $kObjectLength B, was ${object.length}');
  }
}

Uint8List _withObject(int kind, Uint8List object, [Uint8List? task]) {
  _objectCheck(object);
  if (task != null && task.length != kTaskLength) {
    throw ArgumentError('Task must be $kTaskLength B');
  }
  final b = BytesBuilder()
    ..addByte(kind)
    ..add(object);
  if (task != null) b.add(task);
  return b.toBytes();
}

/// 0x70 — the first time with 16 zero bytes as task.
Uint8List pleaPacket(Uint8List object, Uint8List task) =>
    _withObject(kinds.kPiecePlea, object, task);

/// 0x71.
Uint8List taskPacket(Uint8List object, Uint8List task) =>
    _withObject(kinds.kPieceTask, object, task);

/// 0x73.
Uint8List noPiecesPacket(Uint8List object) =>
    _withObject(kinds.kNoPieces, object);

/// 0x72.
Uint8List piecePacket(FountainBlock block) => (BytesBuilder()
      ..addByte(kinds.kUpdatePiece)
      ..add(block.toBytes()))
    .toBytes();

/// Reads 0x70 and 0x71 (same layout). Wrong length: `null`.
({Uint8List object, Uint8List task})? pleaOrTaskRead(Uint8List p) {
  if (p.length != kPleaLength) return null;
  return (
    object: Uint8List.fromList(p.sublist(1, 1 + kObjectLength)),
    task: Uint8List.fromList(p.sublist(1 + kObjectLength)),
  );
}

/// Reads 0x73. Wrong length: `null`.
Uint8List? noRead(Uint8List p) =>
    p.length == kNoLength ? Uint8List.fromList(p.sublist(1)) : null;

/// Reads 0x72. Wrong length or version: `null`.
FountainBlock? pieceRead(Uint8List p) =>
    p.length == kPiecePacketLength ? FountainBlock.fromBytes(p, 1) : null;

/// The 8-B object identifier of the fountain block for an object.
Uint8List fountainIdentifier(Uint8List object) =>
    Uint8List.fromList(object.sublist(0, kFountainObjectIdBytes));

/// Comparison without early exit.
bool sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    d |= a[i] ^ b[i];
  }
  return d == 0;
}

/// The first 4 B as text — for reports.
String objectShort(Uint8List object) => object
    .sublist(0, 4)
    .map((x) => x.toRadixString(16).padLeft(2, '0'))
    .join();

/// The stateless task of the holder (see header).
class Tasks {
  final Uint8List _secret;
  final DateTime Function() now;

  /// [secret] is only for tests; in operation 32 random bytes per process.
  Tasks({Uint8List? secret, this.now = DateTime.now})
      : _secret = secret ?? SodiumFFI().randomBytes(32);

  Uint8List forField(UpdateNeighbour source, Uint8List object, {int offset = 0}) {
    final window = now().millisecondsSinceEpoch ~/
            kTasksWindow.inMilliseconds +
        offset;
    final header = ByteData(6)
      ..setUint16(0, source.$2)
      ..setUint32(2, window & 0xFFFFFFFF);
    final data = (BytesBuilder()
          ..add(_secret)
          ..add(source.$1.rawAddress)
          ..add(header.buffer.asUint8List())
          ..add(object))
        .toBytes();
    return Uint8List.fromList(
        SodiumFFI().sha256(data).sublist(0, kTaskLength));
  }

  bool valid(UpdateNeighbour source, Uint8List object, Uint8List task) =>
      sameBytes(task, forField(source, object)) ||
      sameBytes(task, forField(source, object, offset: -1));
}
