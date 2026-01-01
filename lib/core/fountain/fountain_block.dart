import 'dart:typed_data';

/// Reference size from AP-3a stage 1: the content share of a
/// signature-free single-cell spore.
///
/// Derivation (frozen, `docs/MIGRATION_V3_TO_V4_0_MYZEL.md` l. 3276):
/// cell 1200 B, of which 12 B nonce + 16 B GCM tag = 1172 B interior;
/// largest single entry 1172 - 3 (type + length) = 1169 B; minus
/// 128 B spore overhead = **1041 B**.
///
/// The fountain block is exactly this size. It is thus the largest block
/// that fits into **one** cell — cell type `0x05`, skipped as an unknown
/// type until AP-7.
const int kFountainCellPayloadBytes = 1041;

/// Header of an encoded block. 17 B.
const int kFountainHeaderBytes = 17;

/// Payload of an encoded block. 1024 B.
///
/// ── WHY 1024 AND NOT 1041 - x WITH AN ODD x ──────────────────────
///
/// 1041 - 17 = 1024. The split is chosen so that the **payload is a
/// power of two**, and the header gets what is left over.
/// Three reasons, all three computational:
///
/// 1. **The number of source blocks follows from the length.** `k =
///    ceil(objectLength / 1024)`. With 1024 that is a shift by 10 bits
///    instead of a division — per block, on both sides. And, more
///    importantly: `k` therefore does **not** need to go into the header.
///    That was the candidate that would otherwise have made it 4 B longer.
/// 2. **XOR runs in 64-bit words.** 1024 = 128 x 8 B, evenly. With an odd
///    length the inner loop would need a tail over the remaining bytes —
///    on the hottest path of the codec.
/// 3. **The header needs no more.** 17 B suffice exactly for version,
///    object identifier, object length and block seed (split below). An
///    18th byte would have no consumer.
///
/// The price: 17 B header on 1024 B payload = **1.66 % frame overhead**.
/// That adds to the overhead figure of the coding; the volume numbers in
/// §9 must carry both shares.
const int kFountainBlockPayloadBytes = 1024;

/// Total length of a block on the wire: 17 + 1024 = 1041.
const int kFountainBlockBytes =
    kFountainHeaderBytes + kFountainBlockPayloadBytes;

/// Format version in the first header byte.
///
/// ── EVERYTHING THAT HANGS ON THIS BYTE ──────────────────────────────────
///
/// Not only the header split. A block carries **no** information about
/// which source blocks it is mixed from — the recipient recomputes the
/// neighbourhood from `(k, blockSeed)` itself. Everything that goes into
/// this computation is thus format:
///
/// * the block payload of 1024 B (`k` follows from it),
/// * the random generator (`fountain_prng.dart`) including seeding,
/// * the degree distribution (`degree_distribution.dart`) **including
///   its two defaults** `defaultC` and `defaultFailureBound`.
///
/// Whoever changes one of these quantities changes the neighbourhood for
/// every `(k, blockSeed)` — and thereby makes every block unusable that
/// already lies in the fountain erasure cache. A round-trip test notices
/// **nothing** of this, because there both sides run the same new code.
/// Therefore: such a change increments this byte. The golden values in
/// `test/smoke/smoke_fountain.dart` are the gate that reminds of it.
const int kFountainVersion = 0x01;

/// Length of the object identifier in the header.
const int kFountainObjectIdBytes = 8;

/// Largest encodable object: the object length lies in the header as a
/// 4-B number. 4 GiB - 1 corresponds to 4 194 304 source blocks.
const int kFountainMaxObjectBytes = 0xFFFFFFFF;

/// An encoded fountain block: header plus 1024 B payload.
///
/// ── THE HEADER ─────────────────────────────────────────────────────────
///
/// ```
/// Offset  Length  Field
///      0       1  version        (0x01)
///      1       8  objectId       prefix of the content hash, from the caller
///      9       4  objectLength   big endian, bytes of the original
///     13       4  blockSeed      big endian, seed of this block
/// ```
///
/// **No index, no block number, no `k`.** That is the point of rateless
/// coding (§9): a block is not "the 17th" of N, but one of 2^32
/// equivalent draws. `k` follows from `objectLength`, the neighbourhood
/// from `(k, blockSeed)`.
///
/// **Why the object identifier travels along at all**, although §26.6.1
/// provides a tag line of its own per platform and the line already
/// names the object: the harvest is a **scan**, not a query
/// (§26.6.1, §9). What falls out of the tag line is not guaranteed by a
/// protocol to be sorted correctly — on a version change old and new
/// blocks lie in the same line at the same time. Without the 8 B the
/// decoder would mix them and run through **silently wrong**: the peeling
/// loop does not notice foreign blocks, it folds them in. The 8 B are the
/// gate against that.
///
/// **What the 8 B are not:** an integrity check. They bind the block to
/// an object, they do not confirm the content. The full hash is checked by
/// the caller after reconstruction (§26.6.1 step 5); the codec itself
/// computes no hash and thus depends on no crypto library (E-42: pure
/// Dart).
class FountainBlock {
  /// Prefix of the content hash, [kFountainObjectIdBytes] bytes.
  final Uint8List objectId;

  /// Length of the original object in bytes.
  final int objectLength;

  /// Seed of this block; together with `k` it determines the neighbourhood.
  final int blockSeed;

  /// Exactly [kFountainBlockPayloadBytes] bytes.
  final Uint8List payload;

  FountainBlock({
    required this.objectId,
    required this.objectLength,
    required this.blockSeed,
    required this.payload,
  }) {
    if (objectId.length != kFountainObjectIdBytes) {
      throw ArgumentError(
        'objectId must be $kFountainObjectIdBytes B, '
        'is ${objectId.length}',
      );
    }
    if (payload.length != kFountainBlockPayloadBytes) {
      throw ArgumentError(
        'payload must be $kFountainBlockPayloadBytes B, '
        'is ${payload.length}',
      );
    }
    if (objectLength <= 0 || objectLength > kFountainMaxObjectBytes) {
      throw ArgumentError.value(
        objectLength,
        'objectLength',
        'must lie in [1, $kFountainMaxObjectBytes]',
      );
    }
    if (blockSeed < 0 || blockSeed > 0xFFFFFFFF) {
      throw ArgumentError.value(blockSeed, 'blockSeed', 'must be 32 bits');
    }
  }

  /// Number of source blocks of this object — derived, not transmitted.
  int get sourceBlocks => sourceBlockCount(objectLength);

  /// `k = ceil(objectLength / 1024)`.
  static int sourceBlockCount(int objectLength) =>
      (objectLength + kFountainBlockPayloadBytes - 1) ~/
      kFountainBlockPayloadBytes;

  /// Serialisiert zu [kFountainBlockBytes] Bytes.
  Uint8List toBytes() {
    final out = Uint8List(kFountainBlockBytes);
    out[0] = kFountainVersion;
    out.setRange(1, 9, objectId);
    final d = ByteData.view(out.buffer);
    d.setUint32(9, objectLength, Endian.big);
    d.setUint32(13, blockSeed, Endian.big);
    out.setRange(kFountainHeaderBytes, kFountainBlockBytes, payload);
    return out;
  }

  /// Reads a block from [bytes] starting at [offset].
  ///
  /// Returns `null` if the bytes are not a block of this format —
  /// too short, wrong version, or an object length outside the
  /// permissible range. **No `throw`:** the harvest scans foreign cells
  /// (§9), a miss is the normal case and not a protocol violation.
  static FountainBlock? fromBytes(Uint8List bytes, [int offset = 0]) {
    if (offset < 0 || bytes.length - offset < kFountainBlockBytes) return null;
    if (bytes[offset] != kFountainVersion) return null;
    final d = ByteData.view(bytes.buffer, bytes.offsetInBytes + offset);
    final len = d.getUint32(9, Endian.big);
    if (len <= 0) return null;
    final seed = d.getUint32(13, Endian.big);
    return FountainBlock(
      objectId: Uint8List.fromList(
        bytes.sublist(offset + 1, offset + 1 + kFountainObjectIdBytes),
      ),
      objectLength: len,
      blockSeed: seed,
      payload: Uint8List.fromList(
        bytes.sublist(
          offset + kFountainHeaderBytes,
          offset + kFountainBlockBytes,
        ),
      ),
    );
  }

  /// Do two identifiers belong to the same object?
  static bool sameObject(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() =>
      'FountainBlock(seed=$blockSeed, len=$objectLength, '
      'k=$sourceBlocks)';
}
