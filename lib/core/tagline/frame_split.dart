// Splitting across cell boundaries — the end-to-end layer (B-8).
//
// WHY IT MUST EXIST, and here and not deeper.
//
// §15.4 itself computes first contact at "**~11-14 cells**" and
// names the items: ML-DSA signature 3309 B, ML-KEM ciphertext 1088 B. A
// cell carries 1200 B, its onion message area 1041 B. The
// split is thus not an optimisation, but a normative
// precondition: without it the first message of a relationship cannot
// take place. Measured on 25.08.: the answer to a contact request
// measures ~3.4 KB and was rejected by the switch in `sendToUser` with
// `refuseTooLarge` — the latch before every first contact.
//
// Since S349 a second, inescapable case has been added: the
// day capsule (§4.3) alone measures 1088 B and must reach the
// recipient. The FIRST message of every day to every contact thus bursts
// the cell fundamentally, regardless of its content.
//
// WHY NOT THE FRAGMENTATION OF THE LINK LAYER. AP-3a already has one with
// `LinkFrameType.fragmentStart/Cont` — but it sits
// between two NEIGHBOURS. An onion is stripped by r1 and redeemed
// by r2; what A sends to B survives these stations only INSIDE
// the message area. A split at link level would be reassembled by r1
// and would be ineffective for the path A->B. It
// therefore belongs here: under the recipient's seal and under the
// onion, in an area that only A and B read.
//
// ONE FORM, NOT TWO. Even a message that fits into a single cell
// travels as "piece 1 of 1". That costs 10 B of header and spares
// the code the second path — exactly the reasoning with which `reassembly.dart`
// sends its reassembled frames through the same dispatcher as
// unfragmented ones. A distinguishing byte would moreover be something that r2
// SEES in the aggregate plaintext.
//
// WHAT r2 SEES ANYWAY, so that nothing is glossed over here: the aggregate
// carries a length field in plaintext per entry (`aggregate.dart`), so r2
// already knows the size of every piece. What is new is only the
// TOTAL length — and r2 could likewise infer that by counting the cells for the same
// path block (§7.3, declared Speed limit). It is
// no new class of information.
//
// ERRORS ARE SILENT (E-83), but counted.
library;

import 'dart:typed_data';

/// Header of a piece: `transferId(4) ‖ offset(3) ‖ total(3)`.
const int kSplitHeaderBytes = 10;

/// Largest payload that is reassembled at all.
///
/// §15.4 names "~11-14 cells" for the largest known case. 32 KB
/// leaves plenty of room and at the same time keeps the memory binding per
/// counterpart small — it is the attack surface, not the crypto.
const int kMaxSplitPayloadBytes = 32 * 1024;

/// Splits [payload] into pieces of at most [maxChunkBytes] payload.
///
/// What comes back are finished bodies `kopf ‖ stueck`, which the caller
/// queues unchanged as aggregate entries.
List<Uint8List> splitPayload(
  Uint8List payload, {
  required int transferId,
  required int maxChunkBytes,
}) {
  if (maxChunkBytes <= kSplitHeaderBytes) {
    throw ArgumentError('Chunk size $maxChunkBytes leaves no room '
        'for the header ($kSplitHeaderBytes B)');
  }
  if (payload.length > kMaxSplitPayloadBytes) {
    throw ArgumentError('Payload ${payload.length} B exceeds '
        '$kMaxSplitPayloadBytes B');
  }
  final use = maxChunkBytes - kSplitHeaderBytes;
  final out = <Uint8List>[];
  var off = 0;
  do {
    final end =
        (off + use < payload.length) ? off + use : payload.length;
    final piece = Uint8List(kSplitHeaderBytes + (end - off));
    piece[0] = (transferId >> 24) & 0xff;
    piece[1] = (transferId >> 16) & 0xff;
    piece[2] = (transferId >> 8) & 0xff;
    piece[3] = transferId & 0xff;
    piece[4] = (off >> 16) & 0xff;
    piece[5] = (off >> 8) & 0xff;
    piece[6] = off & 0xff;
    piece[7] = (payload.length >> 16) & 0xff;
    piece[8] = (payload.length >> 8) & 0xff;
    piece[9] = payload.length & 0xff;
    piece.setRange(kSplitHeaderBytes, piece.length,
        Uint8List.sublistView(payload, off, end));
    out.add(piece);
    off = end;
  } while (off < payload.length);
  return out;
}

/// The transfer identifier of a piece, without consuming it.
///
/// WHAT FOR. The harvest book (`harvest_memo.dart`) only remembers tags when
/// the transfer is COMPLETE — for that it must know to which
/// transfer a piece belongs before the reassembler accepts it.
/// The header lies in plaintext before the seal (see the format note above),
/// so nothing is opened here that would not lie open anyway.
///
/// `null` if the body is too short for a header — then it belongs
/// to no transfer and the reassembler discards it right away
/// itself.
int? splitTransferId(Uint8List body) {
  if (body.length < kSplitHeaderBytes) return null;
  return (body[0] << 24) | (body[1] << 16) | (body[2] << 8) | body[3];
}

/// Reassembles split payloads — one instance per counterpart.
///
/// WHY PER COUNTERPART. The transfer identifier is chosen by the sender; it
/// is not unique across different senders, and a
/// shared pot would let one partner bind everyone's memory. With
/// one instance per session each can only use up its own share
/// — the same division that `CellTransport` already makes for the
/// link layer.
///
/// AT THIS PLACE NOTHING HAS BEEN CHECKED YET. The pieces are parts of
/// ONE seal and cannot be authenticated individually; whether they
/// belong together is only said by the AEAD after reassembly. Whoever
/// derives trust here derives it from a number the sender freely
/// chooses. Therefore the gates are the essential thing: a hard upper bound per
/// transfer, for the sum, for the number of transfers and
/// for the number of bookings per transfer.
///
/// GAPS ARE KEPT OPEN (field finding 30.08.). Until that day
/// this class accepted pieces only strictly in order: a piece with
/// `off != filled` — and a first piece with `off != 0` — threw the
/// whole transfer away. That was justified with "over one connection
/// cells come in order".
///
/// For SECURE this sentence holds: there the harvest fetches the cells from
/// a placement and passes them on in the order in which they
/// come back. For SPEED it does not hold, and not as an
/// exception, but as the rule. The pieces of ONE payload lie in
/// different slots, and every slot draws its first hop ANEW
/// (`CoverStream.drawPartner`, called per slot from `DeliveryNode.tick`;
/// `SpeedEgress._buildCell` takes `linkKeyToR1` from it). Two pieces
/// thus run via TWO DIFFERENT r1 to the same r2 and arrive there
/// in arbitrary order. And it affects practically every
/// message: the day capsule (§4.3) alone measures 1088 B, an
/// aggregate entry carries 1026 B payload — so even a 124 B
/// delivery receipt on the first day of a pair is two pieces.
///
/// Measured on 30.08. on node 1, in the direction that failed:
/// `zusammengesetzt 0, geoeffnet 0, Stuecke verworfen 19`. Pieces
/// arrived, no payload was ever finished. The opposite direction
/// (phone) reported at the same time `zusammengesetzt 1, geoeffnet 1`.
///
/// THE OLD ARGUMENT REMAINS ANSWERED, only by other gates. The
/// old comment explicitly cited the order as an
/// attack-surface argument ("keep many tiny holes open"). But keeping a
/// gap open costs nothing that an equally large piece
/// would not also cost: the buffer is bound from the FIRST piece in full
/// length `total`, never piece by piece. What an attacker can bind
/// is still capped by [maxOpenTransfers] and [maxBufferedBytes] —
/// both untouched. What the order capped incidentally and what a
/// gap management opens anew is the NUMBER of bookings per
/// transfer; that is what [maxPiecesPerTransfer] is for.
///
/// ERRORS ARE SILENT (E-83), but counted — and since 30.08. counted separately by
/// REASON, see [discarded].
final class PayloadReassembler {
  /// Largest sum over all open transfers of this counterpart.
  PayloadReassembler({
    int? maxOpenTransfers,
    int? maxBufferedBytes,
  })  : maxOpenTransfers = maxOpenTransfers ?? defaultMaxOpenTransfers,
        maxBufferedBytes = maxBufferedBytes ?? defaultMaxBufferedBytes;

  /// Default for [maxBufferedBytes] — an instance can get more.
  static const int defaultMaxBufferedBytes = 64 * 1024;

  /// How many bytes this reassembler may keep open.
  final int maxBufferedBytes;

  /// Largest number of simultaneously open transfers per counterpart.
  /// Default for [maxOpenTransfers].
  static const int defaultMaxOpenTransfers = 4;

  /// How many transfers may be open at the same time.
  ///
  /// CONFIGURABLE since the Speed path has ONE reassembler for ALL
  /// sessions (30.08.). Before there was one per session, so the cap applied
  /// per session — on merging it would otherwise effectively have been
  /// divided by three, and in the field transfers promptly tipped into
  /// discard. Whoever merges instances must merge their limits
  /// too.
  final int maxOpenTransfers;

  /// Largest number of individually booked pieces per transfer.
  ///
  /// NEW WITH THE GAP MANAGEMENT, and necessary only because of it. As long as
  /// reassembly was strictly in order, a
  /// transfer needed exactly ONE number (`filled`); the number of pieces was
  /// irrelevant. A gap, on the other hand, must be booked, and a booking
  /// costs memory that [maxBufferedBytes] does NOT see: the buffer is
  /// accounted with `total`, the bookkeeping on top is not. Without a cap
  /// a counterpart could create 32768 entries per transfer with 1 B pieces at random offsets
  /// and thus bind a multiple
  /// of what the 64 KB allow.
  ///
  /// 64 is plenty: the largest splittable payload measures
  /// [kMaxSplitPayloadBytes] = 32 KB, an aggregate entry carries
  /// `kMaxPieceBytes - kSplitHeaderBytes` = 1026 B payload, making
  /// 32 pieces for the largest legitimate case. The cap thus lies
  /// at twice what can ever occur.
  static const int maxPiecesPerTransfer = 64;

  /// Open transfers, keyed by IDENTIFIER AND TOTAL LENGTH.
  ///
  /// The identifier alone does not suffice since the Speed path has ONE
  /// reassembler for all senders (30.08.): it is 4 B long and
  /// is drawn per sender, so two senders occasionally collide.
  /// Before, the division by session isolated that halfway; afterwards
  /// the collisions met and threw each other away —
  /// visible in the field as `Stuecke verworfen … (Laenge 2)` on both
  /// nodes, while no message arrived.
  ///
  /// With the total length in the key two colliding
  /// transfers can coexist as long as they differ in length
  /// — the overwhelming normal case. Same identifier AND
  /// same length remains a real collision; it is then noticed as
  /// before as a length conflict or later at the AEAD.
  final Map<(int, int), _Part> _open = {};
  int _bound = 0;
  int _sequence = 0;

  int _formatError = 0;
  int _order = 0;
  int _memoryPressure = 0;
  int _lengthConflict = 0;
  int _double = 0;
  int _accepted = 0;

  /// Discarded pieces since the node has been running — the sum of all reasons.
  ///
  /// WHY SPLIT UP (30.08.). Until that day this was ONE counter with
  /// seven increment sites. In the field it thus said `Stuecke verworfen 19`
  /// and it was impossible to say WHICH reason the 19 were — format errors,
  /// order, memory pressure and length conflict look identical in the
  /// status line, but demand four different
  /// measures. The split costs three `int` per counterpart and
  /// spares the archaeology that 30.08. needed.
  ///
  /// The sum is kept so that `V41Node.status` can read it
  /// unchanged.
  int get discarded =>
      _formatError + _order + _memoryPressure + _lengthConflict;

  /// Pieces that were no valid header: too short for the header,
  /// `total` outside `[1, kMaxSplitPayloadBytes]`, empty piece, or
  /// `off + len > total`. If this rises, the source is broken or foreign —
  /// none of it can come from [splitPayload].
  int get discardedMalformed => _formatError;

  /// Pieces that OVERLAP with already placed ones without being identical
  /// to one of them.
  ///
  /// Until 30.08. this reason was called "order" and was the most frequent
  /// of all: it hit every piece that did not join exactly at `filled`.
  /// Since the gaps are kept open, mere
  /// order is no longer a reason; what remains is the real contradiction —
  /// two pieces that want to occupy the same place with different lengths.
  /// [splitPayload] never produces such a thing.
  int get discardedOutOfOrder => _order;

  /// What fell victim to the gates: a transfer that was displaced
  /// so that a new one has room; a new one for which there was no room
  /// even after displacing; a piece beyond [maxPiecesPerTransfer].
  ///
  /// CAUTION, MIXED UNIT: displacement counts a whole
  /// transfer as one, although several pieces lay in it. That was
  /// the same before the split and is recorded here so that the number
  /// in the field is not read as a piece count.
  int get discardedPressure => _memoryPressure;

  /// Pieces with a known identifier, but a different total length. The old
  /// state is thrown away with it (new attempt or
  /// overwrite attempt — in both cases it is worthless).
  int get discardedLengthConflict => _lengthConflict;

  /// Pieces that already lay exactly like this. NOT part of [discarded]: nothing
  /// is lost, the repetition is ineffective. If the number rises,
  /// the counterpart repeats — that is information about the path, not an
  /// error here.
  int get duplicatePieces => _double;

  /// Pieces that were actually booked (without the one-piece case,
  /// which never creates an entry). The counter-number to [discarded]: "19
  /// discarded" means something completely different depending on whether 0 or
  /// 200 were accepted beside it.
  int get piecesAccepted => _accepted;

  int get openTransfers => _open.length;
  int get bufferedBytes => _bound;

  /// Accepts a piece.
  ///
  /// Returns the complete payload as soon as it is together —
  /// otherwise `null`. A payload that fitted into one piece comes back on the
  /// first call.
  Uint8List? offer(Uint8List body) {
    if (body.length < kSplitHeaderBytes) {
      _formatError++;
      return null;
    }
    final id = (body[0] << 24) | (body[1] << 16) | (body[2] << 8) | body[3];
    final off = (body[4] << 16) | (body[5] << 8) | body[6];
    final total = (body[7] << 16) | (body[8] << 8) | body[9];
    final piece = Uint8List.sublistView(body, kSplitHeaderBytes);

    if (total < 1 || total > kMaxSplitPayloadBytes) {
      _formatError++;
      return null;
    }
    if (piece.isEmpty) {
      // A piece without content never advances the transfer, but
      // occupies a booking. [splitPayload] produces it only for an empty
      // payload, and that already fails at `total < 1`.
      _formatError++;
      return null;
    }
    if (off + piece.length > total) {
      _formatError++;
      return null;
    }

    // The most frequent case first: everything in one piece. It binds no
    // memory and needs no entry.
    if (off == 0 && piece.length == total) {
      return Uint8List.fromList(piece);
    }

    final key = (id, total);
    var t = _open[key];
    if (t == null) {
      // NO `off != 0` LATCH ANYMORE. Which piece of a payload arrives first
      // is decided in Speed mode by the path, not the sender
      // (see class header). A piece from the middle therefore opens the
      // transfer just like the first — the costs are
      // the same, because the buffer is bound with `total` anyway.
      _placeMakeRoom(total);
      if (_bound + total > maxBufferedBytes) {
        _memoryPressure++;
        return null;
      }
      t = _Part(total, _sequence++);
      _open[key] = t;
      _bound += total;
    } else if (t.total != total) {
      // UNREACHABLE SINCE THE COMPOSITE KEY (30.08.): the
      // length is IN the key, so a hit has it by
      // construction. The branch stays as a defence — whoever later shortens the
      // key back to the bare identifier falls in
      // here instead of into a silent overwriter. `discarded
      // LengthConflict` can no longer fire since; that is intentional
      // and no gap.
      // The same identifier with a different total length: either a new
      // attempt or an overwrite attempt. In both cases the
      // old state is worthless.
      _route(key);
      _lengthConflict++;
      return null;
    }

    // WHAT ALREADY LIES IS NOT OVERWRITTEN.
    //
    // The same place with the same length is a repetition — it
    // stays ineffective, and EXACTLY ineffective: do not add to
    // `filled` a second time, otherwise the sum would reach `total` while a
    // hole remains.
    final alreadyThere = t.pieces[off];
    if (alreadyThere != null) {
      if (alreadyThere == piece.length) {
        _double++;
      } else {
        _order++;
      }
      return null;
    }
    for (final e in t.pieces.entries) {
      if (off < e.key + e.value && e.key < off + piece.length) {
        _order++;
        return null;
      }
    }
    if (t.pieces.length >= maxPiecesPerTransfer) {
      _memoryPressure++;
      return null;
    }

    t.buffer.setRange(off, off + piece.length, piece);
    t.pieces[off] = piece.length;
    t.filled += piece.length;
    _accepted++;

    // WHY THE SUM SUFFICES — and why overlaps are therefore rejected
    // instead of painted over. `filled` is the sum of the lengths of all
    // booked pieces. Each lies entirely in `[0, total)` (checked above)
    // and none overlaps another (just checked). Non-
    // overlapping intervals in `[0, total)` with total measure `total`
    // cover the interval completely — `filled == total` thus means:
    // not a byte is missing. With overwriting instead of rejecting
    // this conclusion would be wrong: the sum could reach `total` while
    // a hole remains. The AEAD would catch that (the seal would burst), but
    // indistinguishable from a key problem — and exactly this
    // indistinguishability was what forced the archaeology on 30.08.
    // The error should find an answer here, not there.
    if (t.filled < t.total) return null;
    _route(key);
    return t.buffer;
  }

  void _route((int, int) key) {
    final t = _open.remove(key);
    if (t != null) _bound -= t.total;
  }

  /// Makes room by letting the oldest incomplete transfer give way.
  ///
  /// Not rejecting the NEW one: otherwise a counterpart could permanently
  /// block the channel with four corpses.
  void _placeMakeRoom(int coming) {
    while (_open.length >= maxOpenTransfers ||
        (_open.isNotEmpty && _bound + coming > maxBufferedBytes)) {
      (int, int)? oldestId;
      var oldestSequence = 1 << 62;
      _open.forEach((k, t) {
        if (t.sequence < oldestSequence) {
          oldestSequence = t.sequence;
          oldestId = k;
        }
      });
      final toDelete = oldestId;
      if (toDelete == null) return;
      _route(toDelete);
      _memoryPressure++;
    }
  }
}

final class _Part {
  final int total;
  final int sequence;
  final Uint8List buffer;

  /// What already lies: offset -> length. Only non-overlapping
  /// entries, capped by [PayloadReassembler.maxPiecesPerTransfer].
  final Map<int, int> pieces = {};

  /// Sum of the lengths in [pieces]. Redundant, but the only value that
  /// is read per piece on the hot path.
  int filled = 0;

  _Part(this.total, this.sequence) : buffer = Uint8List(total);
}
