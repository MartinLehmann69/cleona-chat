// The seal around a single fountain block (§9.3, §17.6).
//
// THE SPEC. §9.3: "Both lanes carry the same rateless fountain blocks …
// **sealed under a transfer key**"; §17.6 on the stream lane: "frames are
// sealed under the transfer key (§9.3) and are random bytes to the
// volunteer".
//
// WHY PER BLOCK AND NOT ONCE AROUND THE WHOLE OBJECT. §9.3 says
// explicitly: "**Blocks are lane-neutral.** … A block received on
// either lane counts; a transfer interrupted on one lane finishes on the
// other with no byte of received progress lost." A block must thus be usable ON
// ITS OWN — which a seal around the whole object does not achieve,
// because its AEAD tag only comes at the end. And it has a second,
// bigger benefit: a smuggled-in block is rejected at the door
// instead of destroying the reconstruction. The class docs of
// `FountainDecoder` name exactly this case — "an attacker who can smuggle in a
// valid block header with a wrong payload destroys
// the reconstruction". With the seal per block he can no longer do that.
//
// THE SIZES, recomputed:
//
//   12  nonce (AES-256-GCM)
// 1041  block (17 B header + 1024 B payload, `fountain_block.dart`)
//   16  GCM tag
// ----
// 1069  sealed block
//
// What goes on the wire around it — op byte, hop counter, holder,
// epoch line —, is computed in `bulk_frames.dart`; that is also where it says why
// a bulk frame is NOT a PLACE frame and why it is not sealed.
// On the wire the cell is then, like any other, 1200 B long
// and indistinguishable from a cover cell.
library;

import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/fountain/fountain_block.dart';

import 'bulk_keys.dart';

/// Nonce length of AES-256-GCM.
const int kBulkNonceBytes = 12;

/// Length of the GCM tag.
const int kBulkTagBytes = 16;

/// A sealed block on the wire: 12 + 1041 + 16 = 1069 B.
const int kSealedBulkBlockBytes =
    kBulkNonceBytes + kFountainBlockBytes + kBulkTagBytes;

// `kBulkFrameBytes = 3 + kSealedBulkBlockBytes` STOOD HERE — REMOVED ON
// 2026-09-03. It belonged to the frame building that was removed from this
// file on 02.09.2026 (rationale further below, "THE FRAME BUILDING NO LONGER
// LIVES HERE"); the same rationale explicitly names it among the
// deleted names — it was the only one left standing. The 3 was the
// header of a `0x05` frame WITHOUT op byte; this wire format no longer
// exists. Today's frame is built in `bulk_frames.dart` and
// measured there (`kBulkBodyBytes`, `kBulkPlaceBytes`, `kBulkBlockBytes`).
//
// SEARCH SET (2026-09-03, over `lib/ test/ scripts/ proto/ android/ ios/
// macos/ windows/ linux/`): as a word 3 hits — the declaration and TWO
// comments that both list it as DELETED (`:111` here,
// `test/smoke/smoke_delivery_layer_unwalked_guard.dart:165`). As a
// string 0, in `snake_case` 0, in `proto/` 0, as re-export 0. With the
// removal both comments become true.

/// Seals [block] under the keys of [keys].
///
/// The nonce is DERIVED (`BulkTransferKeys.blockNonce`), not
/// drawn — the rationale is there. Consequence, and it is the point:
/// two seeders that draw the same seed on the same object produce
/// **byte-identical** sealed blocks, and the cache holds them once.
Uint8List sealBulkBlock(FountainBlock block, BulkTransferKeys keys) =>
    sealRawBlock(block.toBytes(), block.objectId, block.blockSeed, keys);

/// Seals the RAW bytes of a block — without interpreting them.
///
/// ── WHY THIS VERSION EXISTS SINCE S372 ────────────────────────────
///
/// There are two block formats that share the same wire: the
/// rateless block (format byte `0x01`, `fountain/fountain_block.dart`)
/// and the stripe fragment (`0x02`, `codec/erasure_stripes.dart`). They
/// are the same length, carry the same header layout and are sealed the
/// same way. The crypto therefore stands EXACTLY ONCE here; the two
/// codecs only bring their bytes.
///
/// A second seal function next to it would be the trap that the section
/// "THE FRAME BUILDING NO LONGER LIVES HERE" at the end of this file describes for the
/// frame building: two builders for the same format are two
/// formats.
Uint8List sealRawBlock(
    Uint8List raw, Uint8List objectId, int blockSeed, BulkTransferKeys keys) {
  if (raw.length != kFountainBlockBytes) {
    throw ArgumentError.value(raw.length, 'raw.length',
        'a bulk block is $kFountainBlockBytes B long');
  }
  final nonce = keys.blockNonce(objectId, blockSeed);
  final ct = SodiumFFI().aesGcmEncrypt(raw, keys.sealKey, nonce);
  final out = Uint8List(kSealedBulkBlockBytes);
  out.setRange(0, kBulkNonceBytes, nonce);
  out.setRange(kBulkNonceBytes, kSealedBulkBlockBytes, ct);
  return out;
}

/// Opens a sealed block — or returns `null`.
///
/// **No `throw`.** The harvest SCANS (§26.6.1: "the cache is not
/// queried but scanned"); what falls out of a tag line may belong to another
/// transfer, may be old, may be garbage. A
/// miss is the normal case — the same stance as
/// `FountainBlock.fromBytes`.
///
/// Three reasons for `null`, all three silent:
///
/// 1. **Wrong length** — not a block of this format.
/// 2. **AEAD fails** — foreign transfer or forgery. The
///    difference is not visible from outside and need not
///    be.
/// 3. **Non-canonical nonce.** The nonce is derivable; if a
///    different one precedes it, the block is genuine, but not in the form that
///    the content-addressed storage presupposes. Whoever submits it like that
///    bypasses the cache's deduplication and can flood a tag line with
///    arbitrarily many versions of THE SAME block. Exactly for that reason
///    the canonical form is enforced here and not merely hoped for.
FountainBlock? openBulkBlock(Uint8List sealed, BulkTransferKeys keys) {
  final raw = openSealedBlockBytes(sealed, keys);
  if (raw == null) return null;
  final block = FountainBlock.fromBytes(raw);
  if (block == null) return null;
  if (!sealedNonceIsCanonical(sealed, block.objectId, block.blockSeed, keys)) {
    return null;
  }
  return block;
}

/// Unseals the bytes of a block — WITHOUT interpreting them.
///
/// The second half of [openBulkBlock], extracted so that the
/// stripe format (`0x02`) uses the same crypto and not its own.
/// **The caller MUST check [sealedNonceIsCanonical] afterwards** — reason
/// 3 in the docs of [openBulkBlock]: a non-canonical nonce bypasses
/// the cache's deduplication and lets a tag line be flooded with arbitrarily
/// many versions of the same block.
Uint8List? openSealedBlockBytes(Uint8List sealed, BulkTransferKeys keys) {
  if (sealed.length != kSealedBulkBlockBytes) return null;
  final nonce = Uint8List.fromList(sealed.sublist(0, kBulkNonceBytes));
  final ct = Uint8List.fromList(sealed.sublist(kBulkNonceBytes));
  try {
    return SodiumFFI().aesGcmDecrypt(ct, keys.sealKey, nonce);
  } catch (_) {
    return null;
  }
}

/// Is [sealed] preceded by the nonce that belongs to `(objectId, blockSeed)`?
bool sealedNonceIsCanonical(Uint8List sealed, Uint8List objectId,
    int blockSeed, BulkTransferKeys keys) {
  if (sealed.length != kSealedBulkBlockBytes) return false;
  final nonce = Uint8List.fromList(sealed.sublist(0, kBulkNonceBytes));
  return bytesEqualConstantTime(nonce, keys.blockNonce(objectId, blockSeed));
}

// ── THE FRAME BUILDING NO LONGER LIVES HERE (02.09.2026) ─────────────────
//
// Until today, `bulkFrame`, `bulkCellInner`, `bulkBlocksInCell`,
// `kBulkFrameBytes` and `kBulkBlockFitsOneCell` stood here. They built a
// `0x05` frame whose BODY was the bare sealed block — without
// op byte, without holder, without line. That was right as long as there was no
// holder side and nobody ever sent such a frame.
//
// Since the holder side exists, it is a TRAP. The body of a
// `0x05` frame now starts with an op byte
// (`bulk_frames.dart`); whoever built and sent `bulkCellInner(block)`
// delivered a frame whose first byte is the first byte
// of the nonce. `parseBulkFrame` reads an unknown opcode from it
// and silently drops it (E-83) — a block that leaves and never
// arrives, without an error becoming visible anywhere. Two builders
// for the same frame type are two wire formats.
//
// The frame building therefore stands in exactly one place:
// `lib/core/bulk/bulk_frames.dart`. This file does the SEAL and
// nothing else.

