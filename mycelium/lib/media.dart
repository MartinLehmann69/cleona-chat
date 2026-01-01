import 'dart:math';
import 'dart:typed_data';

import 'package:mycelium/kinds.dart' as kinds;

import 'package:cleona/core/codec/reed_solomon.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';

/// P10 — large payloads.
///
/// A text message fits into a sealed envelope. An image does not.
/// For that there are three lanes, decided FIRST by size, then by
/// feasibility — never by silent preference:
///
/// | | Lane | when | where to |
/// |---|---|---|---|
/// | 1 | [Lane.inline] | < 256 KB | like every other packet |
/// | 2 | [Lane.streamed] | >= 256 KB, both there, under cap `C`, a volunteer | through the consenting neighbour, nothing is stored |
/// | 3 | [Lane.mass] | otherwise | once per piece at permanently reachable holders |
///
/// **The blocks are lane-neutral.** All three lanes carry the same
/// pieces from the same codec; they differ exclusively
/// in WHERE a piece goes. Therefore there are exactly two
/// packet kinds here and no field that names the lane: the recipient derives the
/// codec from the object length, which the announcement carries anyway.
///
/// This file knows no network. Going out and depositing come in as callbacks,
/// as in `forward.dart` and `post_box_deposit.dart`.
///
/// Here stands the SEND SIDE and the codec. The receive side
/// ([MediaReception]) has stood in `media_reception.dart` since 14.09.2026 —
/// the line budget of 400 does not carry both, and the cut lies where
/// the state begins. The detailed reasoning stands in the header of the
/// other file.
///
/// ## The codec — these numbers are set
/// [kStripeWidth] = 7 source blocks of [kBlock] = 1024 B each yield
/// [kPiecesPerStripe] = 7 + [kExtra] (4) pieces of 1024 B each.
/// Overhead 11/7 = 1.571 — deterministic, without a follow-up round: **any four
/// pieces per stripe may be missing.** The computation happens not
/// here but in `lib/core/codec/reed_solomon.dart`; this file only packs
/// and unpacks bytes.
///
/// ## Packet layout, kind 0x50 (announcement), 45 B
/// | Byte | Length | Content |
/// |---|---|---|
/// | 0 | 1 | 0x50 |
/// | 1 | 8 | identifier of the shipment, random |
/// | 9 | 4 | object length in B (u32 BE) — the whole codec follows from it |
/// | 13 | 32 | SHA-256 of the whole object |
///
/// ## Packet layout, kind 0x51 (one piece), 1044 B
/// | Byte | Length | Content |
/// |---|---|---|
/// | 0 | 1 | 0x51 |
/// | 1 | 8 | the same identifier |
/// | 9 | 2 | number of the stripe (u16 BE) |
/// | 11 | 1 | number of the piece in the stripe, 0..10 |
/// | 12 | 8 | SHA-256 over the 1024 B, shortened to 8 B |
/// | 20 | 1024 | the block |
///
/// 1044 B fit into exactly ONE part packet (`split.dart`: 1188 B payload) —
/// a piece is never split a second time on the wire.
///
/// The shortened checksum per piece recognises a CORRUPTED piece and
/// throws it away before it poisons the stripe; it is no proof of
/// authenticity. Authenticity is carried by the envelope around the object, and across everything
/// the 32 B checksum of the announcement: if it does not match, the
/// shipment fails loudly instead of silently.

const int kBlock = 1024;
const int kStripeWidth = 7; // K
const int kExtra = 4; // d
const int kPiecesPerStripe = kStripeWidth + kExtra; // N = 11
const int kStripeLength = kStripeWidth * kBlock; // 7168

/// From here on an object is no longer an inline object. Exactly 256 KB already
/// does NOT belong to lane 1 any more.
const int kInlineLimit = 256 * 1024;

/// Cap for lane 2, in B — `C` from §9.4.
///
/// **What `C` is:** the upper limit for the volume of ONE streamed
/// transfer. It protects neither the sender nor the recipient,
/// but the consenting neighbour through which the pieces run: above
/// `C` the transfer takes lane 3, even if both sides are online
/// and a volunteer would be available (`v42/kap/ch09.md:101-104`).
///
/// **The 0 is a placeholder, not a computed result and not an error.**
/// Re-measured on 14.09.2026: `v42/kap/ch09.md:81` lists `C` in the
/// parameter table explicitly as **open** — "the streamed lane stays
/// disabled until it is set". The number is thus an open
/// owner decision, and the 0 is the state "not yet
/// decided", not a value. 0 was chosen because [laneChoose] checks with
/// `capC > 0`: a cap not set switches the lane off,
/// instead of accidentally opening it for every length.
///
/// **What lane 2 still lacks besides `C`** (likewise measured 14.09.2026,
/// against `berichte/P10-medien.md:27`, which says "only the cap `C`"): the
/// lane has no sequence of its own in the tree. There is no packet kind with
/// which a neighbour is asked or consents (`kinds.dart` knows in the
/// media range exactly 0x50 and 0x51), and nobody determines [bothOnline]
/// or [volunteerThere] — both are default `false` and have in the
/// whole tree no caller that sets them. Setting `C` alone would
/// thus change nothing yet. What lies HERE and carries is the choice:
/// [laneChoose] delivers lane 2 with a passed-in `capC`
/// and is checkable exactly that way (see `test/smoke_media.dart`).
const int kCapC = 0;

/// From the registry, not set here — three modules had
/// already given themselves the same number once. Public because
/// `media_reception.dart` needs it too: there is ONE origin per number,
/// not two copies.
const int kKindAnnouncement = kinds.kMediaAnnouncement;
const int kKindPiece = kinds.kMediaPiece;
const int _kIdentifierLength = 8;
const int kAnnouncementLength = 1 + _kIdentifierLength + 4 + 32; // 45
const int kPieceHeader = 1 + _kIdentifierLength + 2 + 1 + 8; // 20
const int kPiecePacketLength = kPieceHeader + kBlock; // 1044

/// The largest object this format carries: the stripe number is
/// u16, so there are at most 65535 stripes of [kStripeLength] B each
/// (= 469,762,560 B). Not a chosen limit, but that of the layout —
/// therefore it stands here once and is used by the send side as well as by the
/// receive side, instead of appearing in two places as `0xFFFF`.
const int kAtMostObject = 0xFFFF * kStripeLength;

enum Lane { inline, streamed, mass }

/// An object that can no longer be assembled.
class MediaBroken implements Exception {
  final String reason;
  MediaBroken(this.reason);
  @override
  String toString() => 'MedienKaputt: $reason';
}

ReedSolomon? _rsBetween;
ReedSolomon get _rs =>
    _rsBetween ??= ReedSolomon.withParams(kPiecesPerStripe, kStripeWidth);

final _random = Random.secure();

/// How many stripes an object of this length has.
int stripeNumber(int length) =>
    length <= 0 ? 0 : (length + kStripeLength - 1) ~/ kStripeLength;

/// How many pieces arise in total.
int pieceNumber(int length) => stripeNumber(length) * kPiecesPerStripe;

/// The lane choice. First the size, then the feasibility.
///
/// [bothOnline] and [volunteerThere] are determined by the caller — this
/// file never asks the network by itself.
Lane laneChoose({
  required int length,
  bool bothOnline = false,
  bool volunteerThere = false,
  int capC = kCapC,
}) {
  if (length < kInlineLimit) return Lane.inline;
  if (capC > 0 && length <= capC && bothOnline && volunteerThere) {
    return Lane.streamed;
  }
  return Lane.mass;
}

/// Forms all stripes. Return: piece `s * 11 + n` is piece `n` of
/// stripe `s`, each exactly [kBlock] B. Pure function, no state.
List<Uint8List> stripeForm(Uint8List object) {
  if (object.isEmpty) throw ArgumentError('empty object');
  if (object.length > kAtMostObject) {
    throw ArgumentError('Object too large: ${object.length} B, maximum '
        '$kAtMostObject B (65535 stripes, the u16 number carries no '
        'more)');
  }
  final count = stripeNumber(object.length);
  final all = <Uint8List>[];
  final raw = Uint8List(kStripeLength);
  for (var s = 0; s < count; s++) {
    final from = s * kStripeLength;
    final until = min(from + kStripeLength, object.length);
    raw.fillRange(0, kStripeLength, 0); // remainder of the last stripe is 0
    raw.setRange(0, until - from, Uint8List.sublistView(object, from, until));
    all.addAll(_rs.encode(raw)); // encode copies, raw is reusable
  }
  return all;
}

/// Assembles an object of length [length] from the pieces present.
/// [per] is ordered by stripe: stripe no. -> (piece no. ->
/// block). Throws [MediaBroken] as soon as a stripe stays below
/// [kStripeWidth] pieces.
Uint8List objectFromPieces(Map<int, Map<int, Uint8List>> per, int length) {
  final count = stripeNumber(length);
  final full = Uint8List(count * kStripeLength);
  for (var s = 0; s < count; s++) {
    final there = per[s];
    if (there == null || there.length < kStripeWidth) {
      throw MediaBroken('stripe $s has ${there?.length ?? 0} of '
          '$kStripeWidth needed pieces');
    }
    full.setRange(s * kStripeLength, (s + 1) * kStripeLength,
        _rs.decode(there, kStripeLength));
  }
  return Uint8List.fromList(Uint8List.sublistView(full, 0, length));
}

Uint8List _announcementPacket(Uint8List identifier, int length, Uint8List sum) {
  final p = Uint8List(kAnnouncementLength);
  p[0] = kKindAnnouncement;
  p.setRange(1, 9, identifier);
  ByteData.sublistView(p).setUint32(9, length, Endian.big);
  p.setRange(13, 45, sum);
  return p;
}

Uint8List _piecePacket(Uint8List identifier, int stripe, int no, Uint8List block) {
  final p = Uint8List(kPiecePacketLength);
  p[0] = kKindPiece;
  p.setRange(1, 9, identifier);
  ByteData.sublistView(p).setUint16(9, stripe, Endian.big);
  p[11] = no;
  p.setRange(12, 20, Uint8List.sublistView(SodiumFFI().sha256(block), 0, 8));
  p.setRange(kPieceHeader, kPiecePacketLength, block);
  return p;
}

/// What a dispatch has done — enough to recompute it without looking into the
/// callbacks.
typedef Dispatch = ({Lane lane, Uint8List identifier, int pieces, int bytes});

/// Where a finished packet goes. The caller decides what the lane
/// means: lane 1 like every other packet, lane 2 through the consenting
/// neighbour, lane 3 deposit at the permanently reachable holders.
///
/// **A FUNCTION, not a [Wire] — and that is not taste.** Measured
/// on 14.09.2026 at the outside route (`outside_route.dart:69-75`): everything that
/// leaves the node's socket goes through `split.dart` and carries
/// its 12 B header. A packet sent out raw arrived on the
/// other side in the `Splitter`, had no valid header and was dropped.
/// Two ways out on the same socket are one too many. This file
/// therefore may not even import `wire.dart` — `test/
/// smoke_media.dart` checks that on the file itself.
typedef Out = void Function(Lane lane, Uint8List packet);

/// The send side. No state beyond a dispatch — whoever sends the same
/// bytes twice sends two independent shipments with two
/// identifiers.
class MediaSender {
  /// The default way out. An instance per node has only this one —
  /// whoever needs a different one per recipient passes it along with [send].
  final Out out;

  /// Cap for lane 2. 0 = lane 2 switched off, see [kCapC].
  final int capC;

  MediaSender({required this.out, this.capC = kCapC});

  /// Packs [object] into announcement + pieces and hands every packet individually
  /// to the way out.
  ///
  /// [out] overrides the route for EXACTLY THIS dispatch. With it
  /// the caller binds the target: this file knows no recipient and should
  /// know none, but the layer above knows it at the call site and
  /// encloses it in the function passed along — e.g.
  /// `medien.sende(bytes, hinaus: (spur, p) => knoten.sendeAn(kontakt, p))`.
  /// Without specification the route from the constructor applies. A [Wire] is allowed at
  /// neither of the two places, see [Out].
  Dispatch send(
    Uint8List object, {
    bool bothOnline = false,
    bool volunteerThere = false,
    Out? out,
  }) {
    final route = out ?? this.out;
    final lane = laneChoose(
      length: object.length,
      bothOnline: bothOnline,
      volunteerThere: volunteerThere,
      capC: capC,
    );
    final pieces = stripeForm(object);
    final identifier = Uint8List.fromList(
        List<int>.generate(_kIdentifierLength, (_) => _random.nextInt(256)));
    route(lane,
        _announcementPacket(identifier, object.length, SodiumFFI().sha256(object)));
    for (var i = 0; i < pieces.length; i++) {
      route(
          lane,
          _piecePacket(identifier, i ~/ kPiecesPerStripe,
              i % kPiecesPerStripe, pieces[i]));
    }
    return (
      lane: lane,
      identifier: identifier,
      pieces: pieces.length,
      bytes: kAnnouncementLength + pieces.length * kPiecePacketLength,
    );
  }
}
