/// The content of a cover packet — and the switch that separates it at the recipient
/// from real traffic (S391, architecture §5.1, §5.5; suggestion W4).
///
/// ── WHAT LIES IN THE SHELL ──────────────────────────────────────────────
///
/// The shell (`shell.dart`) seals EVERY payload pairwise to 1200 B.
/// A cover packet ALWAYS hands it the full payload of
/// [kCoverPayload] B, whatever it carries — filling, update piece or
/// address entries thus look equally long even INSIDE the seal:
///
/// ```
/// content byte 1 | random 7 | zero 2 | random 2 (never 0xFFFF) | content | random
///   0x00 filling            content: nothing
///   0x01 update piece       content: length u16 LE | piece
///   0x02 address entries    content: `address_entries.dart` (ONE codec, own first)
///   0x03 code registration  content: length u16 LE | piece (`code_registration.dart`)
///   0x04 keep-alive         content: device code 16 | token 8 (§8.1)
/// ```
///
/// ── WHY THE TWO ZERO BYTES ─────────────────────────────────────────────
///
/// The shell knows only "empty" and "not empty"; it passes every non-empty
/// payload on to the splitter (`shell.dart`, `_onPacket`). A cover packet
/// with content must be branched off BEFORE the splitter, and for that it needs
/// a feature that no part packet ever carries. The content byte alone is
/// none: the splitter begins with an 8 B random identifier, and 3 in 256 of them
/// begin with 0x00-0x02.
///
/// The splitter's 12 B header (`split.dart`) has exactly one such place:
/// field 1 is the COUNT of parts, and `splitUp` never writes 0 there (an
/// empty shipment is one part). A packet with count 0 and field 2 not equal to
/// 0xFFFF is discarded by the splitter anyway (`seqNo >= count`). So the switch takes
/// nothing away from it that it would ever have processed — with and without
/// cover stream the same arrives at the top (§3.1). Guard of this coupling:
/// `test/smoke_cover_stream_content.dart`.
///
/// The content byte nevertheless stands at position 0 (W4): whoever reads a cover packet
/// reads first WHAT it is.
///
/// ── WHAT DOES NOT STAND HERE ─────────────────────────────────────────────────
///
/// No point in time, no target, no selection — that is decided by
/// `cover_stream.dart`. This file builds and reads bytes.
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:mycelium/address_entries.dart';
import 'package:mycelium/wire.dart' show PacketRoute;
import 'package:mycelium/card_address.dart' show CardFormatError;
import 'package:mycelium/shell_start.dart' show kPayloadAtMost;
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/split.dart' show kHeader;

/// The three content kinds (W4). Not packet kinds: they lie in a separate
/// number space behind the feature above and never reach the kind dispatch.
/// They are nevertheless assigned in `kinds.dart` (rule 4).
const int kContentFill = kinds.kCoverFill;
const int kContentPiece = kinds.kCoverPiece;
const int kContentEntries = kinds.kCoverEntries;
/// Codes for the fixed neighbour (§8.1, S391) — layout `code_registration.dart`.
const int kContentRegistration = kinds.kCoverRegistration;
/// The keep-alive (§8.1) — device code and token, `mapping_echo.dart`.
const int kContentKeepAlive = kinds.kCoverKeepAlive;

/// Device code (16 B) + token (8 B) of a keep-alive.
const int kKeepAliveContent = 24;

/// Length of EVERY cover payload — the full payload of the shell.
const int kCoverPayload = kPayloadAtMost;

/// The header is as long as the splitter's: the feature lies in its
/// count field (position 8-9).
const int kCoverHeader = kHeader;

/// The largest update piece that fits into a cover packet (1156 B). A
/// piece of the fetch path (`update_piece.dart`, 1042 B) fits.
const int kPieceAtMost = kCoverPayload - kCoverHeader - 2;

/// Is [payload] a cover packet with content? Only the feature, not the
/// validity — that is checked by [coverPayloadRead].
bool isCoverPayload(Uint8List payload) {
  if (payload.length < kCoverHeader) return false;
  final count = payload[8] | (payload[9] << 8);
  final field2 = payload[10] | (payload[11] << 8);
  return count == 0 && field2 != 0xFFFF;
}

/// Builds a cover payload of exactly [kCoverPayload] B.
///
/// [piece] for [kContentPiece] and [kContentRegistration], [entries] for
/// [kContentEntries], [piece] of exactly [kKeepAliveContent] B for
/// [kContentKeepAlive].
/// Too many entries (`addressListWrite`) or a piece above
/// [kPieceAtMost] are a programming error of the caller.
Uint8List coverPayloadBuild(
  int kind,
  Random random, {
  Uint8List? piece,
  AddressList? entries,
}) {
  final b = BytesBuilder(copy: false);
  switch (kind) {
    case kContentFill:
      break;
    case kContentPiece || kContentRegistration:
      final s = piece ?? (throw ArgumentError('Piece missing'));
      if (s.length > kPieceAtMost) {
        throw ArgumentError('Piece ${s.length} B, at most $kPieceAtMost');
      }
      b
        ..addByte(s.length & 0xFF)
        ..addByte(s.length >> 8)
        ..add(s);
    case kContentEntries:
      addressListWrite(
          b, entries ?? (throw ArgumentError('Entries missing')));
    case kContentKeepAlive:
      final s = piece ?? (throw ArgumentError('Keep-alive content missing'));
      if (s.length != kKeepAliveContent) {
        throw ArgumentError('Keep-alive ${s.length} B, exactly $kKeepAliveContent');
      }
      b.add(s);
    default:
      throw ArgumentError('unknown content kind $kind');
  }
  final content = b.takeBytes();
  final p = Uint8List(kCoverPayload);
  for (var i = 0; i < p.length; i++) {
    p[i] = random.nextInt(256);
  }
  p[0] = kind;
  p[8] = 0;
  p[9] = 0;
  if (p[10] == 0xFF && p[11] == 0xFF) p[11] = random.nextInt(255);
  p.setRange(kCoverHeader, kCoverHeader + content.length, content);
  return p;
}

/// What a cover packet carried.
typedef CoverContent = ({
  int kind,
  Uint8List? piece,
  AddressList? entries,
  Uint8List? registration,
  Uint8List? keepAlive,
});

/// Reads a cover payload; `null` if it is not a valid one. An error
/// is never thrown — what comes from the wire is nothing on which the node
/// may fail.
CoverContent? coverPayloadRead(Uint8List p) {
  if (p.length != kCoverPayload || !isCoverPayload(p)) return null;
  var pos = kCoverHeader;
  Uint8List read(int n) {
    if (pos + n > p.length) throw CardFormatError('Cover packet too short');
    final r = Uint8List.sublistView(p, pos, pos + n);
    pos += n;
    return r;
  }

  try {
    switch (p[0]) {
      case kContentFill:
        return (
          kind: kContentFill,
          piece: null,
          entries: null,
          registration: null,
          keepAlive: null
        );
      case kContentPiece || kContentRegistration:
        final kind = p[0];
        final l = read(2);
        final n = l[0] | (l[1] << 8);
        if (n > kPieceAtMost) return null;
        final b = Uint8List.fromList(read(n));
        return (
          kind: kind,
          piece: kind == kContentPiece ? b : null,
          entries: null,
          registration: kind == kContentRegistration ? b : null,
          keepAlive: null
        );
      case kContentEntries:
        return (
          kind: kContentEntries,
          piece: null,
          entries: addressListRead(read),
          registration: null,
          keepAlive: null
        );
      case kContentKeepAlive:
        return (
          kind: kContentKeepAlive,
          piece: null,
          entries: null,
          registration: null,
          keepAlive: Uint8List.fromList(read(kKeepAliveContent))
        );
      default:
        return null;
    }
  } on Object {
    return null;
  }
}

/// The switch between shell and splitter: cover packets with content go to
/// [onCover], everything else unchanged upwards. Sending it passes through
/// unseen — it holds no buffer and no timer.
class CoverSwitch implements PacketRoute {
  final PacketRoute _bottom;
  final void Function(Uint8List payload, InternetAddress from, int fromPort)
      onCover;

  CoverSwitch(this._bottom, this.onCover);

  @override
  bool send(Uint8List packet, InternetAddress target, int targetPort) =>
      _bottom.send(packet, target, targetPort);

  @override
  void listen(
      void Function(Uint8List packet, InternetAddress from, int fromPort) onPacket) {
    _bottom.listen((p, from, fromPort) {
      if (isCoverPayload(p)) {
        onCover(p, from, fromPort);
      } else {
        onPacket(p, from, fromPort);
      }
    });
  }
}
