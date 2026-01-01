// The control flow of the bulk lane — four messages (§9.3).
//
// THE SPEC. §9.3: "Control flow — **announce** with a one-cell
// micro-preview, **request**, **refill**, **DECODED receipt** — rides the
// delivery layer in the chat's mode."
//
// That is the point: they are ORDINARY messages. They take the
// path the chat takes anyway (Speed or Secure), they have no
// own transport and no own clock. Therefore only the
// encoding stands here — no socket, no queue, no state.
//
// THE SIZE LIMIT. All four must fit into one cell: 1041 B
// content share of a one-cell spore. The announce is the only one that
// needs noteworthy space, and appendix A caps its preview
// explicitly at 979 B, "(one cell)".
//
// THIS RECALCULATION STOOD ONLY HERE IN THE COMMENT UNTIL 31.08. The
// constructor checks the PREVIEW against 979 B, the total length it does
// not check — and since the drawn root ALWAYS travels along, these are two
// different numbers: 40 B header + 32 B root + 979 B preview = 1051 B
// against a 1041 B cell. An announce with a full preview would thus have silently
// fragmented. [BulkAnnounce] now really recomputes it
// ([kAnnouncePreviewBudgetBytes]) — a comment that claims a check
// is not a check (S348).
//
// WHAT THE RECEIPT MEANS — and that is a delivery promise, not a
// diagnosis. §9.3: "Per-batch placement acknowledgments and relay signals
// are transport diagnostics and flip nothing (§9.2). … `delivered` flips
// exclusively on the recipient's DECODED receipt under `K_AB` (D2)."
// [BulkDecodedReceipt] is thus the ONLY thing that may flip the delivery status of a
// media message. A placement receipt may not — S354
// found exactly this defect on the cell path ("every unproven
// receipt flipped `delivered`"), and the bulk lane does not rebuild it.
//
// "UNDER `K_AB`" IS THE WORDING OF THE DOCUMENT AND MEANS THE
// CARRIER, not the transfer key: the receipt is an
// ordinary message and travels the cell path like any other. The
// TRANSFER key has no longer come from `K_AB` since 31.08.2026
// (`bulk_keys.dart`) — for the receipt that changes nothing, the sentence
// is only here so that the two things are not confused.
library;

import 'dart:typed_data';

import 'package:cleona/core/fountain/fountain_block.dart';

import 'bulk_keys.dart';
import 'bulk_params.dart';

/// Format version of all four control messages.
///
/// **0x02 since 31.08.2026.** The announce now ALWAYS carries the transfer root
/// instead of only in the group case (`bulk_keys.dart`, removed
/// pairwise branch); with that the flag byte was dropped and the length grew by
/// 32 B. A bumped version instead of a silent rebuild,
/// so that an announce in the old format is REJECTED and does not read 32 B
/// of preview as the root.
const int kBulkControlVersion = 0x02;

/// Marker bytes. They come BEFORE the version, so that a receiver recognises the kind
/// before it stumbles over the version.
const int kBulkAnnounceMarker = 0xB1;
const int kBulkRequestMarker = 0xB2;
const int kBulkRefillMarker = 0xB3;
const int kBulkReceiptMarker = 0xB4;

/// The fixed header of an announce:
/// `marker(1) ‖ version(1) ‖ hash(32) ‖ laenge(4) ‖ K_T(32) ‖ plen(2)`.
///
/// COMPUTED, NOT WRITTEN — whoever adds a field thereby
/// automatically changes the preview cap below as well.
const int kBulkAnnounceHeaderBytes = 1 + 1 + kBulkContentHashBytes + 4 + 32 + 2;

/// What is left of the cell for the micro-preview: **969 B**.
///
/// ── WHY NOT THE 979 B FROM APPENDIX A (31.08.2026) ─────────────────
///
/// Appendix A caps the preview at "<= 979 B, (one cell)". This number
/// applied to an announce WITHOUT transfer root — in the 1:1 case it was
/// left out because it was derivable from `K_AB`. Exactly this derivability has been
/// removed since 31.08. (`bulk_keys.dart`), the root always travels
/// along, and the header is thus 32 B longer. 979 B of preview would give
/// 72 B header + 979 B preview = 1051 B against a 1041 B cell — the
/// announce would silently fragment, and "(one cell)" would be broken.
///
/// The cap is therefore set to what REALLY fits into the cell,
/// and is computed from it instead of copied from the document. It
/// is stricter than appendix A, never looser — [kAnnouncePreviewMaxBytes]
/// stays as the document value and is its upper bound.
const int kAnnouncePreviewBudgetBytes =
    kFountainCellPayloadBytes - kBulkAnnounceHeaderBytes
            < kAnnouncePreviewMaxBytes
        ? kFountainCellPayloadBytes - kBulkAnnounceHeaderBytes
        : kAnnouncePreviewMaxBytes;

/// The announce: "I have something big for you".
///
/// It carries exactly what the receiver needs to get started:
///
/// * the **full** content hash — not the 8 B from the block header. The
///   final check depends on it (§26.6.1 step 5), and 8 B would not be
///   worth mentioning for that: against an attacker who may supply
///   blocks, 2^64 is no protection.
/// * the object length — `k` follows from it, and without it the
///   decoder cannot be set up.
/// * the drawn root `K_T` — ALWAYS, no longer only for groups.
///   Until 31.08. it was left out in the 1:1 case because it was "derivable from `K_AB` and
///   the content hash"; exactly this derivability was the
///   security flaw (`bulk_keys.dart`: `K_AB` is pure X25519, so
///   no PQ protection, no forward secrecy and a confirmation oracle).
///   It therefore travels along now — and because the announce goes as an ordinary
///   message over the cell path, it travels under X25519 +
///   ML-KEM-768 (`message_seal.dart:374`).
/// * the micro-preview. It is the reason why a Secure chat may send anything at all
///   without consent (§9.3: "at most the
///   one-cell micro-preview, at the ordinary §9.2 price").
final class BulkAnnounce {
  final Uint8List contentHash;
  final int objectLength;

  /// `K_T`, 32 B. No longer optional — see the class docs.
  final Uint8List transferRoot;

  final Uint8List preview;

  BulkAnnounce({
    required this.contentHash,
    required this.objectLength,
    required Uint8List transferRoot,
    Uint8List? preview,
  })  : transferRoot = Uint8List.fromList(transferRoot),
        preview = preview ?? Uint8List(0) {
    if (contentHash.length != kBulkContentHashBytes) {
      throw ArgumentError('Content hash must be $kBulkContentHashBytes B');
    }
    if (objectLength <= 0 || objectLength > kFountainMaxObjectBytes) {
      throw ArgumentError.value(objectLength, 'objectLength',
          'must lie in [1, $kFountainMaxObjectBytes]');
    }
    if (this.transferRoot.length != 32) {
      throw ArgumentError('K_T must be 32 B, is '
          '${this.transferRoot.length}');
    }
    // AGAINST THE CELL, not against the preview number alone: with the always
    // travelling root the cell is 10 B below appendix A's 979 B, and
    // an announce that bursts the cell silently fragments.
    if (this.preview.length > kAnnouncePreviewBudgetBytes) {
      throw ArgumentError(
          'Preview may be at most $kAnnouncePreviewBudgetBytes B '
          '(one cell: $kFountainCellPayloadBytes B minus '
          '$kBulkAnnounceHeaderBytes B header), is ${this.preview.length}');
    }
  }

  /// `marker(1) ‖ version(1) ‖ hash(32) ‖ laenge(4) ‖ K_T(32)
  ///  ‖ vorschaulaenge(2) ‖ vorschau`
  ///
  /// The flag byte was dropped: it said whether the root travels along, and
  /// it always travels along.
  Uint8List encode() {
    final out = Uint8List(kBulkAnnounceHeaderBytes + preview.length);
    out[0] = kBulkAnnounceMarker;
    out[1] = kBulkControlVersion;
    var off = 2;
    out.setRange(off, off + kBulkContentHashBytes, contentHash);
    off += kBulkContentHashBytes;
    ByteData.view(out.buffer).setUint32(off, objectLength, Endian.big);
    off += 4;
    out.setRange(off, off + 32, transferRoot);
    off += 32;
    out[off] = (preview.length >> 8) & 0xFF;
    out[off + 1] = preview.length & 0xFF;
    off += 2;
    out.setRange(off, off + preview.length, preview);
    return out;
  }

  static BulkAnnounce? decode(Uint8List b) {
    if (b.length < kBulkAnnounceHeaderBytes) return null;
    if (b[0] != kBulkAnnounceMarker) return null;
    if (b[1] != kBulkControlVersion) return null;
    var off = 2;
    final hash = Uint8List.fromList(b.sublist(off, off + kBulkContentHashBytes));
    off += kBulkContentHashBytes;
    final len = ByteData.view(b.buffer, b.offsetInBytes + off).getUint32(0, Endian.big);
    off += 4;
    final root = Uint8List.fromList(b.sublist(off, off + 32));
    off += 32;
    final plen = (b[off] << 8) | b[off + 1];
    off += 2;
    if (b.length < off + plen) return null;
    if (len <= 0 || len > kFountainMaxObjectBytes) return null;
    if (plen > kAnnouncePreviewBudgetBytes) return null;
    return BulkAnnounce(
      contentHash: hash,
      objectLength: len,
      transferRoot: root,
      preview: Uint8List.fromList(b.sublist(off, off + plen)),
    );
  }
}

/// The request: "go ahead and send" (§9.3 "request").
///
/// It carries only the object identifier. There is nothing more to say — the
/// receiver cannot name a block, because no block has a number
/// (§9: "no block is special, no index is allocated").
final class BulkRequest {
  final Uint8List objectId;

  BulkRequest(this.objectId) {
    if (objectId.length != kFountainObjectIdBytes) {
      throw ArgumentError('objectId must be $kFountainObjectIdBytes B');
    }
  }

  Uint8List encode() {
    final out = Uint8List(2 + kFountainObjectIdBytes);
    out[0] = kBulkRequestMarker;
    out[1] = kBulkControlVersion;
    out.setRange(2, out.length, objectId);
    return out;
  }

  static BulkRequest? decode(Uint8List b) {
    if (b.length != 2 + kFountainObjectIdBytes) return null;
    if (b[0] != kBulkRequestMarker || b[1] != kBulkControlVersion) return null;
    return BulkRequest(Uint8List.fromList(b.sublist(2)));
  }
}

/// The refill (§9.3 "refill"): "I am still missing n".
///
/// ONE NUMBER, NO LIST — and that is the difference from any ARQ.
/// §9.3: "the recipient … asks for refills as an ordinary message; the
/// sender then emits further blocks — no block is special, no index is
/// allocated." The sender then draws NEW seeds; it does not send
/// again what it has already sent. A list of missing pieces
/// could not even be kept here: the receiver does not know which
/// blocks exist, only how many source blocks it is still missing.
final class BulkRefillRequest {
  final Uint8List objectId;

  /// How many further blocks the receiver requests.
  final int wantedBlocks;

  BulkRefillRequest(this.objectId, this.wantedBlocks) {
    if (objectId.length != kFountainObjectIdBytes) {
      throw ArgumentError('objectId must be $kFountainObjectIdBytes B');
    }
    if (wantedBlocks < 0 || wantedBlocks > 0xFFFFFFFF) {
      throw ArgumentError.value(wantedBlocks, 'wantedBlocks', 'must be 32 bits');
    }
  }

  Uint8List encode() {
    final out = Uint8List(2 + kFountainObjectIdBytes + 4);
    out[0] = kBulkRefillMarker;
    out[1] = kBulkControlVersion;
    out.setRange(2, 2 + kFountainObjectIdBytes, objectId);
    ByteData.view(out.buffer)
        .setUint32(2 + kFountainObjectIdBytes, wantedBlocks, Endian.big);
    return out;
  }

  static BulkRefillRequest? decode(Uint8List b) {
    if (b.length != 2 + kFountainObjectIdBytes + 4) return null;
    if (b[0] != kBulkRefillMarker || b[1] != kBulkControlVersion) return null;
    final want = ByteData.view(b.buffer, b.offsetInBytes)
        .getUint32(2 + kFountainObjectIdBytes, Endian.big);
    return BulkRefillRequest(
        Uint8List.fromList(b.sublist(2, 2 + kFountainObjectIdBytes)), want);
  }
}

/// The DECODED receipt (§9.3, D2).
///
/// It carries the **full** content hash back, not the 8 B. Reason:
/// it is the statement "I have EXACTLY THIS object completely and
/// verified". With 8 B that would be a statement about 2^64 possible
/// objects, and the sender would flip its delivery status on a promise
/// that nobody made.
final class BulkDecodedReceipt {
  final Uint8List contentHash;

  BulkDecodedReceipt(this.contentHash) {
    if (contentHash.length != kBulkContentHashBytes) {
      throw ArgumentError('Content hash must be $kBulkContentHashBytes B');
    }
  }

  Uint8List encode() {
    final out = Uint8List(2 + kBulkContentHashBytes);
    out[0] = kBulkReceiptMarker;
    out[1] = kBulkControlVersion;
    out.setRange(2, out.length, contentHash);
    return out;
  }

  static BulkDecodedReceipt? decode(Uint8List b) {
    if (b.length != 2 + kBulkContentHashBytes) return null;
    if (b[0] != kBulkReceiptMarker || b[1] != kBulkControlVersion) return null;
    return BulkDecodedReceipt(Uint8List.fromList(b.sublist(2)));
  }

  /// Does this receipt match what was sent?
  ///
  /// Constant-time, and that is not decoration here: the comparison
  /// decides `delivered`, and an attacker may supply the value to be
  /// compared.
  bool matches(Uint8List expectedContentHash) =>
      bytesEqualConstantTime(contentHash, expectedContentHash);
}
