/// The frame stream inside a link cell (AP-3a stage 1,
/// docs/MIGRATION_V3_TO_V4_0_MYZEL.md §4d.11 "The format: frame stream").
///
/// **This file freezes wire format** (guarded by
/// `test/smoke/smoke_link_cell.dart`). The [kCellPlaintextSize] bytes inside
/// a cell's AEAD ciphertext are a sequence of entries:
///
/// ```
/// entry = type(1) ‖ length(2, big endian) ‖ body(length)
/// ```
///
/// | type   | meaning                                                       |
/// |--------|---------------------------------------------------------------|
/// | `0x00` | PAD — rest of the cell is filler, parsing stops here. A cover |
/// |        | cell is a cell whose **first** inner byte is `0x00`.          |
/// | `0x01` | complete spore                                                |
/// | `0x02` | fragment start: `transfer(2) ‖ total_length(3) ‖ bytes`       |
/// | `0x03` | fragment continuation: `transfer(2) ‖ offset(3) ‖ bytes`      |
/// | `0x04` | control channel (plant-ack, subscription sync, entry records) |
/// |        | — the control channel's *inner* format is NOT part of the     |
/// |        | freeze                                                        |
/// | `0x05` | reserved for AP-7 (fountain symbols)                          |
///
/// **Unknown types are skipped via their `length` field.** That is the
/// built-in extension path: a stage-1 node that receives a frame type it
/// does not know (including the reserved `0x05`) skips its body and keeps
/// parsing. This behavior is mandatory and tested — without it every later
/// frame type would break the format.
///
/// Note PAD carries **no** length field: `0x00` means "ignore the rest of
/// the cell", exactly one byte, so padding always fits (any remaining
/// capacity ≥ 1 byte can hold it). Filler bytes after `0x00` are written as
/// zeros here; their value is receiver-ignored and NOT part of the freeze —
/// the whole stream is AEAD-encrypted, so filler content is invisible on
/// the wire either way.
///
/// A length field would violate axiom 3 in plaintext ("a header field by
/// which Cleona traffic could be recognized", v4 §2.1 — the WireGuard
/// mistake). Here the entire structure lives inside the AEAD ciphertext;
/// TLS 1.3 (RFC 8446 §5.2/§5.4) and QUIC (RFC 9000 §19.1) hide their record
/// types and padding the same way.
library;

import 'dart:typed_data';

import 'package:cleona/core/link/cell.dart';

/// Frame type byte values. Values are wire format — frozen.
abstract final class LinkFrameType {
  /// Padding: rest of the cell is filler. First-inner-byte `0x00` defines a
  /// cover cell.
  static const int pad = 0x00;

  /// A complete spore in one frame.
  static const int spore = 0x01;

  /// Fragment start: body is `transfer(2) ‖ gesamtlaenge(3) ‖ bytes`.
  static const int fragmentStart = 0x02;

  /// Fragment continuation: body is `transfer(2) ‖ offset(3) ‖ bytes`.
  static const int fragmentCont = 0x03;

  /// Control channel. Inner format not part of the AP-3a freeze.
  static const int control = 0x04;

  /// One fountain block of a bulk transfer (AP-7, architecture v4.1 §9.3).
  ///
  /// Body: a **sealed** fountain block, `kSealedBulkBlockBytes` = 1069 B
  /// (12 B nonce + 1041 B block + 16 B GCM tag, see
  /// `lib/core/bulk/bulk_block_seal.dart`). With the 3-byte frame header
  /// that is 1072 B against [kCellPlaintextSize] = 1172 — one block rides
  /// in **one** cell and is never fragmented (0x02/0x03).
  ///
  /// Claimed by AP-7 on 2026-08-30. Until then the constant was named
  /// `reservedFountain` and was deliberately absent from [known], so a
  /// stage-1 parser skipped such a frame like any unknown type. Renaming
  /// it does not change the wire: the value 0x05 is unchanged, and no
  /// released build ever emitted one.
  static const int fountain = 0x05;

  /// The types the parser delivers to the caller.
  ///
  /// `0x05` was added when AP-7 claimed it. Adding a type here is
  /// **additive for existing consumers**: `Reassembler.offer`
  /// (`tagline/reassembly.dart:71`) passes a non-fragment type through
  /// unchanged, and `CellTransport.classify`
  /// (`tagline/cell_transport.dart:192`) drops everything that is neither
  /// `control` nor `spore`. A 0x05 frame therefore reaches exactly the
  /// consumer that asks for it, and no other.
  static const Set<int> known = {
    spore,
    fragmentStart,
    fragmentCont,
    control,
    fountain,
  };
}

/// One parsed frame: type byte plus raw body. Bodies of fragment frames are
/// decoded further via [FragmentStartBody]/[FragmentContBody].
class LinkFrame {
  final int type;
  final Uint8List body;

  LinkFrame(this.type, this.body) {
    if (type < 0 || type > 0xFF) {
      throw ArgumentError('LinkFrame: type must be one byte, got $type');
    }
    if (type == LinkFrameType.pad) {
      throw ArgumentError(
          'LinkFrame: PAD is not a payload frame — padding is emitted by '
          'buildInner, never constructed by callers');
    }
    if (body.length > kMaxFrameBodySize) {
      throw ArgumentError(
          'LinkFrame: body exceeds $kMaxFrameBodySize bytes '
          '(got ${body.length}) — larger content must be fragmented '
          '(types 0x02/0x03)');
    }
  }

  /// Encoded size of this frame: 3-byte header plus body.
  int get encodedSize => 3 + body.length;
}

/// Builds the inner plaintext of one cell from [frames]: encodes each entry
/// as `typ(1) ‖ laenge(2, BE) ‖ koerper`, then pads the remainder with a
/// PAD frame. Always returns exactly [kCellPlaintextSize] bytes.
///
/// An empty [frames] list yields a cover cell (first inner byte `0x00`).
///
/// Throws [ArgumentError] when the frames do not fit into one cell — the
/// caller fragments (0x02/0x03) instead; this builder never splits.
Uint8List buildInner(List<LinkFrame> frames) {
  var needed = 0;
  for (final f in frames) {
    needed += f.encodedSize;
  }
  if (needed > kCellPlaintextSize) {
    throw ArgumentError(
        'buildInner: frames need $needed bytes, cell holds '
        '$kCellPlaintextSize — fragment instead');
  }
  final inner = Uint8List(kCellPlaintextSize); // zero-initialized
  var off = 0;
  for (final f in frames) {
    inner[off] = f.type;
    inner[off + 1] = (f.body.length >> 8) & 0xFF; // big endian
    inner[off + 2] = f.body.length & 0xFF;
    inner.setRange(off + 3, off + 3 + f.body.length, f.body);
    off += f.encodedSize;
  }
  // Remaining capacity (if any) starts with the PAD type byte 0x00 — which
  // the zero-initialized buffer already carries, as does the filler after
  // it. Written explicitly anyway so the intent survives a refactor of the
  // allocation above.
  if (off < kCellPlaintextSize) {
    inner[off] = LinkFrameType.pad;
  }
  return inner;
}

/// Parses the inner plaintext of one cell back into its payload frames.
///
/// - Stops at a PAD byte (`0x00`) — the rest of the cell is filler.
/// - **Skips unknown types via their length field** (the extension path,
///   see library docs). Skipped frames are not delivered.
/// - Throws [FormatException] on a truncated entry (length field pointing
///   past the end of the cell). That can only come from a peer violating
///   the format — the AEAD tag already proved the bytes authentic, so this
///   is a hard protocol error, not damage in transit.
List<LinkFrame> parseInner(Uint8List inner) {
  if (inner.length != kCellPlaintextSize) {
    throw ArgumentError(
        'parseInner: inner must be exactly $kCellPlaintextSize bytes, '
        'got ${inner.length}');
  }
  final frames = <LinkFrame>[];
  var off = 0;
  while (off < inner.length) {
    final type = inner[off];
    if (type == LinkFrameType.pad) break; // rest of the cell is filler
    if (off + 3 > inner.length) {
      throw FormatException(
          'parseInner: entry header truncated at offset $off');
    }
    final len = (inner[off + 1] << 8) | inner[off + 2]; // big endian
    final bodyStart = off + 3;
    final bodyEnd = bodyStart + len;
    if (bodyEnd > inner.length) {
      throw FormatException(
          'parseInner: entry at offset $off declares $len body bytes, '
          'only ${inner.length - bodyStart} remain');
    }
    if (LinkFrameType.known.contains(type)) {
      frames.add(
          LinkFrame(type, Uint8List.fromList(inner.sublist(bodyStart, bodyEnd))));
    }
    off = bodyEnd;
  }
  return frames;
}

/// Body of a fragment-start frame (`0x02`):
/// `transfer(2, BE) ‖ gesamtlaenge(3, BE) ‖ bytes`.
class FragmentStartBody {
  /// Transfer ID, 2 bytes: 0..65535.
  final int transferId;

  /// Total length of the fragmented payload, 3 bytes: 0..16777215.
  final int totalLength;

  final Uint8List bytes;

  FragmentStartBody(this.transferId, this.totalLength, this.bytes) {
    _checkTransferId(transferId);
    _check3Byte('totalLength', totalLength);
  }

  Uint8List encode() {
    final out = Uint8List(5 + bytes.length);
    out[0] = (transferId >> 8) & 0xFF;
    out[1] = transferId & 0xFF;
    out[2] = (totalLength >> 16) & 0xFF;
    out[3] = (totalLength >> 8) & 0xFF;
    out[4] = totalLength & 0xFF;
    out.setRange(5, out.length, bytes);
    return out;
  }

  static FragmentStartBody decode(Uint8List body) {
    if (body.length < 5) {
      throw FormatException(
          'FragmentStartBody: need at least 5 bytes, got ${body.length}');
    }
    final transferId = (body[0] << 8) | body[1];
    final totalLength = (body[2] << 16) | (body[3] << 8) | body[4];
    return FragmentStartBody(
        transferId, totalLength, Uint8List.fromList(body.sublist(5)));
  }
}

/// Body of a fragment-continuation frame (`0x03`):
/// `transfer(2, BE) ‖ offset(3, BE) ‖ bytes`.
class FragmentContBody {
  /// Transfer ID, 2 bytes: 0..65535. Matches the fragment start.
  final int transferId;

  /// Byte offset of [bytes] within the reassembled payload, 3 bytes.
  final int offset;

  final Uint8List bytes;

  FragmentContBody(this.transferId, this.offset, this.bytes) {
    _checkTransferId(transferId);
    _check3Byte('offset', offset);
  }

  Uint8List encode() {
    final out = Uint8List(5 + bytes.length);
    out[0] = (transferId >> 8) & 0xFF;
    out[1] = transferId & 0xFF;
    out[2] = (offset >> 16) & 0xFF;
    out[3] = (offset >> 8) & 0xFF;
    out[4] = offset & 0xFF;
    out.setRange(5, out.length, bytes);
    return out;
  }

  static FragmentContBody decode(Uint8List body) {
    if (body.length < 5) {
      throw FormatException(
          'FragmentContBody: need at least 5 bytes, got ${body.length}');
    }
    final transferId = (body[0] << 8) | body[1];
    final offset = (body[2] << 16) | (body[3] << 8) | body[4];
    return FragmentContBody(
        transferId, offset, Uint8List.fromList(body.sublist(5)));
  }
}

void _checkTransferId(int v) {
  if (v < 0 || v > 0xFFFF) {
    throw ArgumentError('transferId must fit 2 bytes (0..65535), got $v');
  }
}

void _check3Byte(String name, int v) {
  if (v < 0 || v > 0xFFFFFF) {
    throw ArgumentError('$name must fit 3 bytes (0..16777215), got $v');
  }
}
