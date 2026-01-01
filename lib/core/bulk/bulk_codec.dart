// What sender and receiver of a bulk transfer need from a CODEC
// — and nothing else.
//
// ── WHY THIS FILE EXISTS SINCE S372 ──────────────────────────────
//
// Until 06.09.2026 `BulkSender` talked directly with
// `FountainEncoder` and `BulkReceiver` directly with `FountainDecoder`.
// That was right as long as there was ONE codec. With decision E-3 = D there
// are two, and the switch lies at the size:
//
//   < 32 KB                    cell path (no media lane at all)
//   32 KB .. < 256 KB          Reed-Solomon, stripes over cells
//   >= 256 KB                  rateless (fountain)
//
// **The wire does not change in the process.** A stripe fragment is
// 1024 B long — exactly [kFountainBlockPayloadBytes] —, carries the same
// 17 B header, is sealed by the same `sealBulkBlock`, put into the same
// `0x05` frame, held by the same holder and scanned by the same
// harvest. The only difference is HOW blocks are made from the object
// and how the object is made again from blocks.
//
// Exactly for that reason the switch lies here and not in the network: the
// band membership follows from `objectLength`, and `objectLength` is in the
// announce anyway (`BulkAnnounce`). Both sides compute the same
// function ([mediaCodecFor]) on the same number. **No new field, no
// new opcode, no wire change.**
//
// NO STATE, NO I/O.
library;

import 'dart:typed_data';

import 'bulk_keys.dart';
import 'bulk_params.dart';

/// Which codec carries a transfer.
enum BulkCodecKind {
  /// Rateless (LT/online class, E-42) — `lib/core/fountain/`. Arbitrarily
  /// many draws, overhead is an expected value.
  fountain,

  /// Reed-Solomon over stripes of `K` cells — `lib/core/codec/
  /// erasure_stripes.dart`. Finitely many blocks, overhead is a
  /// number.
  reedSolomon,
}

/// Which codec carries a MEDIA transfer of [objectLength] bytes.
///
/// ── IT IS THE ONLY PLACE WHERE THE SWITCH IS DECIDED ─────────────
///
/// Sender and receiver call the same function on the same number. Whoever
/// put a second calculation next to it here would build two codecs that
/// agree today and not tomorrow — and the error would be silent,
/// because a wrongly decoded set delivers bytes that look like
/// bytes. (It is then only caught by the final check in
/// `BulkReceiver.take`, i.e. after the full traffic.)
///
/// ── AND IT APPLIES ONLY TO MEDIA ─────────────────────────────────────
///
/// **Not to binary distribution** (`lib/core/update/`). Its
/// objects are program files, their blocks are pushed unsolicited by §26.6 as
/// COVER FILL, and their seeds come from
/// [KeyedSeeds] — both are properties of the rateless coding.
/// A delta patch under 256 KB would otherwise silently be put on
/// Reed-Solomon by this function, and the cover fill would push blocks that
/// no receiver expects. Therefore [BulkCodecKind.fountain] is the
/// DEFAULT of `BulkSender`/`BulkReceiver`, and only the media lane
/// explicitly passes the result of this function.
BulkCodecKind mediaCodecFor(int objectLength) =>
    objectLength < kFountainLowerBoundBytes
        ? BulkCodecKind.reedSolomon
        : BulkCodecKind.fountain;

/// What a sender draws blocks from.
///
/// The draw is NUMBERED (`draw` 0, 1, 2, …) and not
/// "infinite": only this way can a finite codec say when it is done
/// ([totalDraws]). The rateless codec returns `null` there and
/// thus means "as many as are asked for".
abstract interface class BulkBlockFactory {
  /// `k` — the number of source blocks.
  int get sourceBlocks;

  int get objectLength;

  /// How many draws there are at all — `null` means unlimited
  /// (rateless).
  ///
  /// **For Reed-Solomon that is the WHOLE set**, `ceil(k/K) * N`. A
  /// draw beyond that would yield a block the receiver already has;
  /// that it does not exist is the difference between "overhead
  /// is a number" and "overhead is an expected value".
  int? get totalDraws;

  /// The seed of the [draw]-th draw.
  ///
  /// It is the identifier of the block in the header and goes into the nonce
  /// (`BulkTransferKeys.blockNonce`); two draws with the same seed
  /// produce byte-identical sealed blocks, and the cache holds them
  /// once.
  int seedForDraw(int draw);

  /// The SEALED block for [seed] — ready for the frame.
  Uint8List sealedFor(int seed, BulkTransferKeys keys);
}

/// What a receiver can do with a scanned block.
///
/// Word for word like `FountainOffer`, but without its name: the same set of
/// outcomes applies to both codecs, and `BulkReceiver` should not have to know the
/// one in order to serve the other.
enum BulkCodecOffer {
  /// The block has resolved at least one source block.
  resolved,

  /// Accepted, but has not resolved anything yet.
  stored,

  /// Accepted, contributed nothing.
  redundant,

  /// This block already existed.
  duplicate,

  /// Does not belong to this object, or cannot be opened. **When
  /// scanning, the normal case.**
  foreign,

  /// Everything is already there.
  complete,
}

/// Where a receiver puts blocks.
abstract interface class BulkBlockSink {
  int get sourceBlocks;

  int get resolvedSourceBlocks;

  bool get isComplete;

  double get progress;

  /// Accepts a SEALED block — opening, checking and
  /// sorting in, all in one.
  ///
  /// **Opening belongs here and not to the caller**, because the
  /// two codecs have different block formats (format byte `0x01`
  /// versus `0x02`). A caller that opened it itself would have to guess
  /// which of the two it has in front of it — and exactly this guessing is the
  /// silent error that the own format byte stands against.
  BulkCodecOffer offerSealed(Uint8List sealed, BulkTransferKeys keys);

  /// The finished object, or `null` as long as something is missing. **Without
  /// content check** — that is step 5 in §26.6.1 and lies with
  /// `BulkReceiver`.
  Uint8List? takeObject();

  /// Forget everything and start from scratch (self-healing after a
  /// hash failure, §26.6.1).
  void reset();
}
