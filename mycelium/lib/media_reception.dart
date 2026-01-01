/// The receive side of the media layer: from the kinds 0x50/0x51 that the
/// node receives, a FINISHED object arises.
///
/// ## Why a separate file
/// On 14.09.2026 `media.dart` had 351 of 400 allowed lines, and the
/// interface to the node (source per packet, cap on the open
/// shipments, checks against a malicious packet) grows here, not
/// over there. The line budget has no exception mechanism — if it does not
/// fit, the design is wrong, not the limit.
///
/// The cut lies where the state begins: the send side in
/// `media.dart` is a pure function over bytes (pack, hand out,
/// done) and knows nothing beyond a dispatch. This file is the
/// only part of the layer with state across several packets and the
/// only one that hangs on the network. The computation still happens over there: here things are
/// sorted in and [objectFromPieces] is called, no codec of its own.
/// That is why `media.dart` does not import this file, and does not have
/// to.
///
/// ## How a node feeds it
/// Like `OutsideRoute.receive` and `PostBoxDeposit.receive`:
/// `receive(packet, from, fromPort)` from within the kind dispatch. Foreign
/// kinds are silently discarded — the dispatch sits with the caller.
/// An object is finished when [MediaReception.onObject] hands it out.
///
/// ## NO timer — as in `post_box_deposit.dart`
/// Assembly happens as soon as every stripe has [kStripeWidth] pieces.
/// If it never suffices, the verdict only falls when the caller
/// calls [MediaReception.complete]. A permanent clock was the error of the
/// old layer.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/media.dart';

/// Where a packet came from. The same form as `Neighbour` in
/// `post_box_deposit.dart`, but a name of its own: both types meet
/// in the node's kind dispatch, and two identically named
/// records from two layers would be a confusion there that the
/// compiler does not see.
typedef MediaSource = (InternetAddress address, int port);

/// A FINISHED object — complete, checked against the 32 B checksum of the
/// announcement, ready to be passed on.
///
/// [from] is WHO ANNOUNCED THE SHIPMENT (or where the first
/// packet of this identifier came from) — not necessarily the source of every piece:
/// on lane 3 the recipient fetches the pieces from several holders, the
/// sources then differ. It is an indication of origin, NOT a
/// proof of authenticity; authenticity is carried by the envelope around the object.
typedef OnMediaObject = void Function(
    Uint8List object, Uint8List identifier, MediaSource from);

/// A shipment that no longer comes about, with the reason in plain text.
typedef OnMediaFailure = void Function(Uint8List identifier, String reason);

/// How many shipments may be open at the same time.
///
/// The reason is the wiring itself: as soon as this class hangs on the
/// node's socket, ANYONE who can send a packet announces. Without a
/// cap the storage of half-finished shipments grows without limit, and a
/// single sender with random identifiers fills the working memory.
/// With a cap the oldest is displaced and reported loudly.
///
/// 32 is chosen, not computed: more than a handful of simultaneous
/// large transfers has no measured cause, and 32 half
/// shipments of at most [kAtMostObject] each are the case that a
/// node carries in the worst case.
const int kAtMostOpenShipments = 32;

class _Inbound {
  /// The 8 B of the identifier — in the key of `_open` they stand as text,
  /// here as bytes. Saves the way back from the text.
  final Uint8List identifier;

  /// Where the first packet of this shipment came from.
  final MediaSource origin;

  /// -1 = announcement not there yet.
  int length = -1;
  Uint8List? sum;

  /// Stripe no. -> (piece no. -> block).
  final Map<int, Map<int, Uint8List>> per = {};
  int pieces = 0;

  /// Stripes that have [kStripeWidth] pieces together. Counted along
  /// instead of recounted on every packet: otherwise a single
  /// arriving piece costs a pass over ALL stripes, and an
  /// announcement with 65535 stripes turns that into a lever.
  int fullStripe = 0;

  _Inbound(this.identifier, this.origin);
}

/// The receive side. One instance per node; it holds all running
/// shipments side by side, kept apart solely by the identifier.
class MediaReception {
  final OnMediaObject onObject;
  final OnMediaFailure? onFailure;

  /// See [kAtMostOpenShipments].
  final int atMostOpen;

  final Map<String, _Inbound> _open = {};

  /// Identifiers about which the verdict has already fallen — object handed out
  /// or failure reported.
  ///
  /// Without this list the first TRAILING packet creates the shipment a
  /// second time, and the half shipment lies around forever. That is
  /// not a special case but the rule: an object is finished as soon as
  /// every stripe has [kStripeWidth] pieces — the remaining four
  /// pieces of the last stripe arrive AFTERWARDS. Measured on
  /// 14.09.2026 on a 300 KB shipment: four stragglers, one open
  /// shipment that never went away again.
  ///
  /// Capped just like [_open] and for the same reason; Dart keeps the
  /// insertion order, the oldest goes first.
  final Set<String> _settled = <String>{};

  /// How many pieces were discarded: violated checksum, impossible
  /// piece number, or a stripe behind the end of the announced
  /// object. Diagnosis, not a regular path.
  int dropped = 0;

  /// How many packets came for an identifier about which a verdict had already
  /// fallen. No error — see [_settled].
  int followed = 0;

  MediaReception({
    required this.onObject,
    this.onFailure,
    this.atMostOpen = kAtMostOpenShipments,
  });

  /// How many shipments are currently lying around half-finished.
  int get openShipments => _open.length;

  /// A packet of kind 0x50 or 0x51; everything else is ignored.
  ///
  /// [from]/[fromPort] is WHERE it came from — for a piece collected from a post box
  /// thus the holder, not the sender.
  void receive(Uint8List packet, InternetAddress from, int fromPort) {
    if (packet.isEmpty) return;
    final source = (from, fromPort);
    if (packet[0] == kKindAnnouncement &&
        packet.length == kAnnouncementLength) {
      _announcement(packet, source);
    } else if (packet[0] == kKindPiece &&
        packet.length == kPiecePacketLength) {
      _piece(packet, source);
    }
  }

  void _announcement(Uint8List packet, MediaSource from) {
    final identifier = packet.sublist(1, 9);
    final length = ByteData.sublistView(packet).getUint32(9, Endian.big);
    // Check before every creation: an announcement above 4 GB otherwise costs
    // through the stripe count alone more than the shipment would ever be worth.
    if (length <= 0 || length > kAtMostObject) {
      onFailure?.call(
          identifier,
          'announcement names $length B — outside 1..$kAtMostObject, '
          'the stripe number (u16) does not carry more');
      return;
    }
    final e = _entry(identifier, from);
    if (e == null) return; // verdict has fallen, this is trailing
    e.length = length;
    e.sum = packet.sublist(13, kAnnouncementLength);
    // What came in before the announcement and lies behind the end of the now
    // known object is thrown out — and the two counters are
    // formed anew afterwards, otherwise they would count stripes that do not
    // exist, and the shipment would count as complete.
    final count = stripeNumber(length);
    final before = e.per.length;
    e.per.removeWhere((s, _) => s >= count);
    if (e.per.length != before) dropped += before - e.per.length;
    e.pieces = 0;
    e.fullStripe = 0;
    for (final m in e.per.values) {
      e.pieces += m.length;
      if (m.length >= kStripeWidth) e.fullStripe++;
    }
    _try(identifier, e);
  }

  void _piece(Uint8List packet, MediaSource from) {
    final block = packet.sublist(kPieceHeader);
    final should = Uint8List.sublistView(SodiumFFI().sha256(block), 0, 8);
    for (var i = 0; i < 8; i++) {
      if (packet[12 + i] != should[i]) {
        dropped++;
        return; // corrupted — never let it into a stripe
      }
    }
    final no = packet[11];
    if (no >= kPiecesPerStripe) {
      dropped++;
      return;
    }
    final identifier = packet.sublist(1, 9);
    final stripeNo = ByteData.sublistView(packet).getUint16(9, Endian.big);
    final e = _entry(identifier, from);
    if (e == null) return; // verdict has fallen, this is trailing
    if (e.length > 0 && stripeNo >= stripeNumber(e.length)) {
      dropped++; // points behind the end of the announced object
      return;
    }
    final stripe = e.per.putIfAbsent(stripeNo, () => {});
    if (stripe.containsKey(no)) return; // Dublette
    stripe[no] = block;
    e.pieces++;
    if (stripe.length == kStripeWidth) e.fullStripe++;
    _try(identifier, e);
  }

  /// Fetches the entry for [identifier] or creates it; in doing so displaces the
  /// oldest open shipment if [atMostOpen] is reached. Dart
  /// keeps the insertion order, so `keys.first` is the oldest.
  _Inbound? _entry(Uint8List identifier, MediaSource from) {
    final h = _hex(identifier);
    final there = _open[h];
    if (there != null) return there;
    if (_settled.contains(h)) {
      followed++;
      return null;
    }
    if (_open.length >= atMostOpen) {
      final old = _open[_open.keys.first]!;
      _settle(old.identifier);
      onFailure?.call(
          old.identifier,
          'evicted: more than $atMostOpen open transfers, '
          '${old.pieces} pieces were there');
    }
    final fresh = _Inbound(identifier, from);
    _open[h] = fresh;
    return fresh;
  }

  /// Verdict fallen: out of the open shipments, into the settled
  /// ones. The only place that removes from [_open] — otherwise there would
  /// at some point be a removal without a [_settled] note, and the
  /// straggler would create the shipment again.
  void _settle(Uint8List identifier) {
    _open.remove(_hex(identifier));
    _settled.add(_hex(identifier));
    while (_settled.length > atMostOpen) {
      _settled.remove(_settled.first);
    }
  }

  /// A verdict about [identifier] falls now, even if pieces are still
  /// outstanding: either the object comes, or [onFailure] reports
  /// why. Afterwards the shipment is forgotten.
  bool complete(Uint8List identifier) {
    final e = _open[_hex(identifier)];
    if (e == null) return false;
    if (_try(identifier, e)) return true;
    // _try has already reported (checksum, assembly) and
    // cleared away — then do not report a second time here.
    if (!_open.containsKey(_hex(identifier))) return false;
    _settle(identifier);
    onFailure?.call(
        identifier,
        e.length < 0
            ? 'no announcement, ${e.pieces} pieces are there'
            : 'only ${e.pieces} of ${pieceNumber(e.length)} pieces, '
                'at least $kStripeWidth per stripe needed');
    return false;
  }

  /// How many pieces have arrived so far — diagnosis, not a regular path.
  int arrived(Uint8List identifier) => _open[_hex(identifier)]?.pieces ?? 0;

  bool _try(Uint8List identifier, _Inbound e) {
    if (e.length < 0) return false;
    if (e.fullStripe < stripeNumber(e.length)) return false;
    Uint8List object;
    try {
      object = objectFromPieces(e.per, e.length);
    } on Object catch (f) {
      _settle(identifier);
      onFailure?.call(identifier, 'assembly failed: $f');
      return false;
    }
    final actual = SodiumFFI().sha256(object);
    final should = e.sum!;
    for (var i = 0; i < 32; i++) {
      if (actual[i] != should[i]) {
        _settle(identifier);
        onFailure?.call(identifier, 'checksum of the object does not hold');
        return false;
      }
    }
    _settle(identifier);
    onObject(object, identifier, e.origin);
    return true;
  }
}

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
