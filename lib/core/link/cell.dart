/// Link-layer cell — the atomic wire unit of the V4 link layer (AP-3a
/// stage 1, docs/MIGRATION_V3_TO_V4_0_MYZEL.md §4d.11; architecture v4 §2.2).
///
/// **This file freezes wire format.** Every constant below is part of what
/// AP-3a freezes; changing any of them after release creates a second wire
/// format. The freeze is guarded by `test/smoke/smoke_link_cell.dart`.
///
/// On-wire layout of one cell (exactly [kCellSize] bytes of UDP payload —
/// payload, not packet):
///
/// ```
/// nonce(12, random) ‖ AES-256-GCM ciphertext(1172) ‖ tag(16)
/// ```
///
/// The size is derived, not chosen (§4d.11):
///
/// ```
/// 1280   IPv6 minimum MTU (RFC 8200 §5)
/// −  40  IPv6 header
/// −   8  UDP header
/// −  32  reserve for a future disguise header (§2.6a, E-69)
/// = 1200
/// ```
///
/// To an outside observer the whole cell is indistinguishable from random
/// bytes (axiom 3): the nonce is drawn fresh from the CSPRNG per cell and
/// the remainder is AEAD output. There is **no** plaintext discriminator —
/// no magic byte, no version field, no length field outside the ciphertext.
/// All structure (the frame stream, see `frame.dart`) lives inside the
/// AEAD ciphertext, the same way TLS 1.3 (RFC 8446 §5.2/§5.4) and QUIC
/// (RFC 9000 §19.1) hide record type and padding.
///
/// The nonce is random per cell as decided in §4d.11 ("nonce(12, random)").
/// Each link direction encrypts under its own key (`cell/init` vs
/// `cell/resp`, see `link_kdf.dart`), so the two directions never share a
/// nonce space.
library;

import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';

/// Total size of one cell on the wire: fixed 1200 bytes of UDP payload.
const int kCellSize = 1200;

/// AES-256-GCM nonce, drawn fresh from the CSPRNG for every cell.
const int kCellNonceSize = 12;

/// AES-256-GCM authentication tag.
const int kCellTagSize = 16;

/// Plaintext capacity of one cell: the inner frame stream is always exactly
/// this long (1200 − 12 − 16 = 1172). Shorter content is padded with a PAD
/// frame (`frame.dart`); longer content is fragmented (frame types
/// 0x02/0x03).
const int kCellPlaintextSize = kCellSize - kCellNonceSize - kCellTagSize;

/// Largest body a single frame entry can carry: the frame header costs
/// 3 bytes (`typ(1) ‖ laenge(2)`), leaving 1172 − 3 = 1169.
const int kMaxFrameBodySize = kCellPlaintextSize - 3;

/// Content share of a signature-free single-cell spore: 1169 − 128 = 1041
/// bytes (§4d.11 "Derived numbers"). The 128 bytes are the spore's own
/// framing overhead without signature. This is the reference size AP-7
/// tunes its fountain block size against — frozen here so AP-7 has a
/// compile-time anchor, even though the spore format itself is not part of
/// stage 1.
const int kSingleCellSporeContentSize = kMaxFrameBodySize - 128;

/// Seals one cell: encrypts an exactly [kCellPlaintextSize]-byte inner
/// frame stream under [cellKey] (32 bytes, one of the two directional keys
/// from `LinkKdf`) and returns exactly [kCellSize] bytes ready to be handed
/// to the transport as one UDP payload.
///
/// The sealed bytes are a pure function of (inner, key, nonce) — nothing
/// else. In particular there is no transport or disguise parameter: a
/// future disguise (§2.6a) is a wrapper *around* these bytes, never a
/// second encoding of them. `smoke_link_cell.dart` guards that invariant
/// (guard 5, wrapper proof).
Uint8List sealCell(Uint8List inner, Uint8List cellKey) {
  if (inner.length != kCellPlaintextSize) {
    throw ArgumentError(
        'sealCell: inner must be exactly $kCellPlaintextSize bytes, '
        'got ${inner.length}');
  }
  final sodium = SodiumFFI();
  final nonce = sodium.generateNonce(); // 12 random bytes
  // aesGcmEncrypt returns ciphertext with the 16-byte tag appended:
  // 1172 + 16 = 1188 bytes.
  final ct = sodium.aesGcmEncrypt(inner, cellKey, nonce);
  final cell = Uint8List(kCellSize);
  cell.setRange(0, kCellNonceSize, nonce);
  cell.setRange(kCellNonceSize, kCellSize, ct);
  return cell;
}

/// Opens one cell: verifies and decrypts [cell] (exactly [kCellSize] bytes)
/// under [cellKey] and returns the [kCellPlaintextSize]-byte inner frame
/// stream.
///
/// Throws [ArgumentError] on wrong size and [SodiumException] when
/// authentication fails — a cell that does not authenticate carries no
/// information and must be dropped silently by the caller (§2.6 posture:
/// silence, never an error reply on the wire).
Uint8List openCell(Uint8List cell, Uint8List cellKey) {
  if (cell.length != kCellSize) {
    throw ArgumentError(
        'openCell: cell must be exactly $kCellSize bytes, got ${cell.length}');
  }
  final sodium = SodiumFFI();
  final nonce = Uint8List.sublistView(cell, 0, kCellNonceSize);
  final ct = Uint8List.sublistView(cell, kCellNonceSize);
  final inner = sodium.aesGcmDecrypt(
      Uint8List.fromList(ct), cellKey, Uint8List.fromList(nonce));
  // AES-GCM is length-preserving: 1188-byte ct+tag always yields 1172.
  // This cannot fail if the arithmetic above holds; asserted for the freeze.
  assert(inner.length == kCellPlaintextSize);
  return inner;
}
