// How long a media send takes — as a RANGE, not as a number.
//
// ── WHY A RANGE (owner decision 02.09.2026) ──────────────────
//
// The consent dialog from §9.3 ("Mode coupling") is meant to tell the user
// what the secure path costs. A SINGLE number cannot do that: the most
// expensive item of the calculation hangs on the number of relays this
// node KNOWS RIGHT NOW, and that differs by a factor of 6.7 between the
// lab and the field.
//
//   Field: m x R = `kDeliveryFamilies` (3) x `kResponsibleRelays` (20)
//                = 60 deposits per cell = 60 slots of 8 s = 480 s
//   Lab:   m x R = 3 x 3 = 9 deposits = 9 slots of 8 s = 72 s
//
// The same file would thus get a number differing sevenfold depending on
// the network size. A fixed number that is off sevenfold in the lab is
// ignored after two experiences — and an ignored dialog is exactly what
// §12 is meant to prevent ("the question must NEVER be answered out of
// habit").
//
// Therefore: LOWER BOUND from the set known today, UPPER BOUND from the
// nominal size [kResponsibleRelays]. Both ends are calculated, neither is
// guessed, and the range shrinks to a point by itself as soon as the node
// knows the full set.
//
// ── THE CALCULATION, ITEM BY ITEM ─────────────────────────────────
//
// 1. THE OFFER (`BulkAnnounce`). §9.3: "Control flow — announce with a
//    one-cell micro-preview, request, refill, DECODED receipt — rides the
//    delivery layer in the chat's mode." It is EXACTLY ONE cell:
//    `routeFor` (v41_routing.dart:211-215) does not even let a media
//    control type above the cell limit through (`refuseTooLarge`), and
//    [kAnnouncePreviewMaxBytes] caps the micro preview specifically for
//    that.
//
//    In a secure chat this one cell costs `m x R` deposits
//    (`V41Node.placeSecure`, v41_node.dart:2185-2229), in a speed chat one
//    pass-on. Both go as CONTROL FRAMES through the same drain, which
//    releases exactly one per [kSlotInterval]
//    (`cover_stream.dart:68`, `v41_node.dart:2240-2245`).
//
//    ONCE PER RECIPIENT. `_sendOnBulkLane` sends the offer in a loop over
//    `recipients` — a group with N members pays N x m x R. That is why
//    [recipients] stands in the calculation; without it the number would
//    be too small for every group.
//
// 2. THE BLOCKS. EXACTLY ONE deposit per block (§9.3, `bulk_placement.dart`
//    header) — there is no `m x R` here. Their clock is
//    [kBulkRateCellsPerSecond] (32 cells/s, appendix A), a property of the
//    egress (`media_bulk_transport.dart`, `placeOnce`).
//
//    How many blocks: `plannedMediaBlocksFor` — the same function that
//    `BulkSender.plannedBlocks` uses, not a replica. It knows both codecs
//    (§9.3, E-3 = D).
//
// ── WHAT THIS NUMBER IS NOT ─────────────────────────────────────────
//
// It is the time of the SENDER, not the time until display at the
// receiver. The receiver scans on ITS cadence (§8, §9.3: "the
// recipient **scans** the holding relays"); §12 states a ceiling of ~1 h
// for that. The dialog says so in addition — a number read as "then it is
// there" although it means "then it is gone" would be a promise the layer
// does not give.
//
// NO STATE, NO I/O. Every quantity comes in as an argument.
library;

import 'package:cleona/core/bulk/bulk_params.dart';
import 'package:cleona/core/bulk/bulk_sender.dart'
    show plannedMediaBlocksFor;
import 'package:cleona/core/sync/cover_stream.dart' show kSlotInterval;
import 'package:cleona/core/bulk/responsibility.dart'
    show kResponsibleRelays;
import 'package:cleona/core/sync/delivery_params.dart' show kDeliveryFamilies;

/// How many cells the offer of a transfer measures.
///
/// ONE, and that is not an assumption: `routeFor` rejects an offer above
/// the cell limit with `refuseTooLarge` (v41_routing.dart:211-215), and
/// [kAnnouncePreviewMaxBytes] caps the micro preview precisely for that
/// ("<= 979 B, so that the offer fits into ONE cell").
const int kAnnounceCells = 1;

/// The range that the consent dialog shows.
final class MediaSendEstimate {
  /// Size of the object in bytes — the input, so that the output stays
  /// recalculable.
  final int objectBytes;

  /// How many recipients get the offer (1:1 = 1, group = N).
  final int recipients;

  /// How many blocks the sender plans (`plannedMediaBlocksFor`).
  final int plannedBlocks;

  /// How many responsible relays this node reaches TODAY.
  final int relaysKnown;

  /// The nominal size of the responsibility set ([kResponsibleRelays]).
  final int relaysNominal;

  /// Lower bound in secure mode — calculated with [relaysKnown].
  final Duration secureLow;

  /// Upper bound in secure mode — calculated with [relaysNominal].
  final Duration secureHigh;

  /// The same transfer in speed mode: the offer goes out ONCE instead of
  /// `m x R` times.
  final Duration speed;

  const MediaSendEstimate({
    required this.objectBytes,
    required this.recipients,
    required this.plannedBlocks,
    required this.relaysKnown,
    required this.relaysNominal,
    required this.secureLow,
    required this.secureHigh,
    required this.speed,
  });

  /// If the node already knows the full set, the range collapses into a
  /// point — then the dialog shows ONE number instead of "x to y".
  bool get collapsed => secureLow == secureHigh;

  /// Without a single known relay there is nothing to estimate: there would
  /// also be nothing to deposit. The dialog then says "unknown" instead of
  /// a number that follows from an empty set.
  bool get estimable => relaysKnown > 0;

  @override
  String toString() => 'MediaSendEstimate($objectBytes B, $recipients recip., '
      '$plannedBlocks blocks, R $relaysKnown..$relaysNominal, '
      'secure ${secureLow.inSeconds}..${secureHigh.inSeconds} s, '
      'speed ${speed.inSeconds} s)';
}

/// Computes the range from today's constants and [relaysKnown].
///
/// [relaysKnown] is the MEASURED set (`V41Delivery
/// .reachableResponsibleRelays`), not the nominal size. It is clamped to
/// `0..relaysNominal`: `responsibleRelays` never deposits more than the
/// nominal size, and a larger number would be an output without subject.
MediaSendEstimate estimateMediaSend({
  required int objectBytes,
  required int relaysKnown,
  int recipients = 1,
  int families = kDeliveryFamilies,
  int relaysNominal = kResponsibleRelays,
  Duration slot = kSlotInterval,
  int bulkRateCellsPerSecond = kBulkRateCellsPerSecond,
  int announceCells = kAnnounceCells,
}) {
  final r = relaysKnown < 0
      ? 0
      : (relaysKnown > relaysNominal ? relaysNominal : relaysKnown);
  final n = recipients < 1 ? 1 : recipients;
  // THE SAME number that `BulkSender.plannedBlocks` returns — also for the
  // Reed-Solomon band (S372). An own calculation here would be a displayed
  // duration that no code keeps: at 256 KB the dialog would show 548 blocks
  // against 407 on the wire, i.e. ~35 % too long.
  final blocks = plannedMediaBlocksFor(objectBytes);
  // The blocks run on THEIR clock (`R_bulk`), the offer on the slot clock.
  // Added, not maximised: `_sendOnBulkLane` FIRST deposits and THEN
  // announces ("FIRST DEPOSIT, THEN ANNOUNCE" — cleona_service.dart), so
  // the two items lie one after the other and not side by side.
  final blockDuration = Duration(
      milliseconds: (blocks * 1000 / bulkRateCellsPerSecond).ceil());
  Duration withCells(int cells) => blockDuration + slot * cells;
  return MediaSendEstimate(
    objectBytes: objectBytes,
    recipients: n,
    plannedBlocks: blocks,
    relaysKnown: r,
    relaysNominal: relaysNominal,
    secureLow: withCells(announceCells * n * families * r),
    secureHigh: withCells(announceCells * n * families * relaysNominal),
    speed: withCells(announceCells * n),
  );
}

/// What the user chose in the consent dialog from §9.3.
///
/// ── THERE IS NO STORE FOR IT, AND THAT IS THE POINT ──────────────
///
/// §9.3: "A Secure chat sends media only after an explicit
/// **per-transfer** consent naming the linkability; a remembered blanket
/// consent would be the silent mode switch §12 exists to prevent."
///
/// This value therefore travels as an ARGUMENT through `sendMediaMessage`
/// and is stored nowhere. Whoever filled it from a setting would have
/// broken the rule — not the send path that receives it.
enum SecureMediaChoice {
  /// "Send in secure mode" — the transfer stays on the chat's timeline, the
  /// offer is deposited `m x R` times.
  secure,

  /// "Speed for THIS file" — an EXPLICIT, one-time downgrade.
  ///
  /// It does not violate the hard rule "secure never SILENTLY to speed":
  /// the user chose it in a dialog that names the drawbacks. The chat stays
  /// secure — `setChatMode` is not touched, and the next message goes via
  /// the deposit again.
  speedThisTransfer,
}

/// What the user answered in the dialog — THREE states, not two.
///
/// A `bool?` cannot distinguish "explicitly cancelled" from "somehow
/// clicked away". The difference matters here, because the two
/// non-cancellations choose DIFFERENT paths and the cancellation none.
///
/// This type lives in the pure file and not at the dialog, so that a guard
/// can check [choiceFrom] without Flutter.
enum MediaConsentResult {
  /// The user stays in secure mode: the offer is deposited `m x R` times,
  /// the transfer needs the announced range.
  sendSecure,

  /// The user chose the fast path FOR THIS ONE FILE.
  sendFast,

  /// Back, without deciding.
  cancel,
}

/// Translates the dialog's answer into what the send path understands.
///
/// **[MediaConsentResult.cancel] has NO counterpart**, and that is the
/// point: `null` in the send path means "not consented", and then nothing
/// goes out in a secure chat (§9.3). A `cancel` accidentally mapped to
/// [SecureMediaChoice.secure] would be a consent that nobody gave — and
/// `secure` is the harmless-LOOKING mis-mapping here, which is precisely
/// why it is written out here.
SecureMediaChoice? choiceFrom(MediaConsentResult r) => switch (r) {
      MediaConsentResult.sendSecure => SecureMediaChoice.secure,
      MediaConsentResult.sendFast => SecureMediaChoice.speedThisTransfer,
      MediaConsentResult.cancel => null,
    };
