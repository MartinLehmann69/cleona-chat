/// The start of a shell — the handshake between two neighbours.
///
/// ── WHAT FOR ─────────────────────────────────────────────────────────────────
///
/// V4.2 §5.5 rule 3: „Every cover packet is sealed pairwise — filled or
/// empty." Until S389 mycelium had NO shared key between two neighbours:
/// the call carries a node identifier rolled per start, a
/// remembered neighbour is nothing but `ip:port`. A cover packet was therefore a
/// naked zero buffer (`cover_stream.dart`, measured S388 D2) — and real
/// traffic carried kind and splitter header in plaintext. Both together yield
/// exactly the sieve that rule 3 excludes: whoever looks separates filling
/// from traffic without knowing a single key.
///
/// This file builds the pairwise key. `shell.dart` uses it for
/// EVERY packet on the data port — cover as well as traffic, same size,
/// same appearance.
///
/// ── THE PROCEDURE (V4.2 §4.2) ────────────────────────────────────────────
///
/// „an Elligator2-encoded X25519 handshake on the outside, an ML-KEM-768
/// exchange on the inside, link key = KDF(kNetworkChannel ‖ x25519_ss ‖
/// mlkem_ss)". The derivation itself is NOT rebuilt here but taken from
/// `lib/core/link/link_kdf.dart` — a second handwritten
/// copy of a wire-relevant constant is the error class on which this
/// project has repeatedly got stuck.
///
/// ```
/// flight 1  (caller -> callee), TWO packets of 1200 B each:
///   part A:  E2(eph_a)                  32 B   ‖ kem_pk[0..1168)   1168 B
///   part B:  secondIdentifier(E2(eph_a)) 32 B  ‖ kem_pk[1168..1184)  16 B
///                                              ‖ random            1152 B
///
/// flight 2  (callee -> caller), ONE packet of 1200 B:
///            E2(eph_b) 32 B ‖ nonce 12 B
///          ‖ AEAD_{k_provisional}( kem_ct 1088 B ‖ random 52 B )  1156 B
/// ```
///
/// **Why flight 1 needs two packets.** A public ML-KEM-768
/// key measures 1184 B. With the 32 B of the Elligator share that is
/// 1216 B — more than the 1200 B to which §5.1 and §22.4.1 fix every packet.
/// The V4.1 handshake (`lib/core/link/handshake.dart`) got by with
/// one flight because it already KNEW the public ML-KEM key of the
/// callee from its entry and only put the 1088 B short
/// ciphertext on the wire. Such an entry a
/// mycelium neighbour does not have — it is an address, nothing else (§11.8). So
/// the public key itself must travel, and it does not fit into
/// one packet.
///
/// **Why the two packets lie with the CALLER and not with the callee.**
/// 2400 B out, 1200 B back: a forged sender gets HALF
/// of what it sends. The other way round it would be an amplifier of 2x. V3
/// already rejected the same trade at 4-5x.
///
/// **Why the second identifier is a hash and not a sequence number.** A
/// number in plaintext would be the recognition mark that rule 3 forbids —
/// an observer would have „packet with byte 0x01 at offset 0 = handshake".
/// `SHA-256(Domaene ‖ E2)` looks like randomness and can only be
/// assigned by whoever has also seen part A.
///
/// ── WHAT IS NOT HERE ─────────────────────────────────────────────────
///
/// No binding to an identity, no signature, no check of WHO
/// the neighbour is. The handshake is anonymous, and that is right: the
/// confidentiality of the content is carried by the envelope (§4), end to end.
/// The shell protects the COVER, not the content (§5.5 rule 3: „the
/// wrapper is secret to protect the cover, not the content").
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/link/elligator_ffi.dart';
import 'package:cleona/core/link/link_kdf.dart';

/// What lies on the data port — every packet, without exception. §5.1 („cover
/// packet size 1200 B — identical to a full part") and §22.4.1 („cell frame
/// fixed at 1200 B") name the same number; it therefore stands exactly once.
const int kShellSize = 1200;

/// The uniformly encoded X25519 part (Elligator2).
const int kUniform = 32;

/// AES-256-GCM: nonce in front, authenticator at the back.
const int kNonce = 12;
const int kCertifier = 16;

/// ML-KEM-768.
const int kKemKey = 1184;
const int kKemCipher = 1088;

/// How the public ML-KEM key falls onto the two parts.
const int kKemFront = kShellSize - kUniform; // 1168
const int kKemBack = kKemKey - kKemFront; // 16

/// The plaintext block of a data packet and the payload that fits into it
/// (2 B length field are deducted). `split.dart` aligns `kMaxPaket` to it.
const int kPlaintext = kShellSize - kNonce - kCertifier; // 1172
const int kPayloadAtMost = kPlaintext - 2; // 1170

/// The plaintext block of flight 2 — 32 B Elligator and 12 B nonce lie
/// in front, 16 B authenticator behind.
const int kFlight2Plaintext =
    kShellSize - kUniform - kNonce - kCertifier; // 1140

final SodiumFFI _sodium = SodiumFFI();
final OqsFFI _oqs = OqsFFI();
ElligatorFFI get _elligator => ElligatorFFI();

final Uint8List _domainPartB =
    Uint8List.fromList(utf8.encode('mycelium-shell-partB/v1'));

/// Label of the provisional key under which flight 2 is locked.
/// Own label next to the cell keys of the link layer — the same salt,
/// separate domain.
const String _infoProvisional = 'shell/provisional/v1';

/// The identifier under which part B belongs to part A.
Uint8List secondIdentifier(Uint8List uniform) {
  final b = BytesBuilder()
    ..add(_domainPartB)
    ..add(uniform);
  return _sodium.sha256(b.toBytes());
}

/// Brings two unassigned packets into order (part A, part B) —
/// or `null` if they do not belong together.
///
/// The order is NOT presupposed: UDP may reorder, and two
/// packets are exactly the case in which that shows.
(Uint8List, Uint8List)? sort(Uint8List x, Uint8List y) {
  if (x.length != kShellSize || y.length != kShellSize) return null;
  if (_fits(x, y)) return (x, y);
  if (_fits(y, x)) return (y, x);
  return null;
}

bool _fits(Uint8List a, Uint8List b) {
  final should = secondIdentifier(Uint8List.sublistView(a, 0, kUniform));
  for (var i = 0; i < kUniform; i++) {
    if (should[i] != b[i]) return false;
  }
  return true;
}

/// A running handshake on the side of the CALLER.
///
/// Holds the ephemeral secrets until flight 2 comes. A start is never
/// reused: one of its own for each neighbour, gone after completion.
class Start {
  /// E2(eph_a) — at the same time what the tie is decided on
  /// (see `shell.dart`).
  final Uint8List uniform;
  final Uint8List _x25519Secret;
  final Uint8List _kemSecret;

  /// The two packets of flight 1, ready for sending.
  final Uint8List partA;
  final Uint8List partB;

  Start._(this.uniform, this._x25519Secret, this._kemSecret, this.partA,
      this.partB);
}

/// Creates a handshake and builds flight 1.
Start beginShellHandshake() {
  _oqs.init();
  final e = _elligator.keyPair(_sodium.randomBytes(kUniform));
  final kem = _oqs.mlKemKeypair();

  final a = Uint8List(kShellSize);
  a.setRange(0, kUniform, e.hidden);
  a.setRange(kUniform, kShellSize, kem.publicKey.sublist(0, kKemFront));

  final b = Uint8List(kShellSize);
  b.setRange(0, kUniform, secondIdentifier(e.hidden));
  b.setRange(kUniform, kUniform + kKemBack,
      kem.publicKey.sublist(kKemFront, kKemKey));
  // Randomness, not zeros: the filling lies openly on the wire, and a
  // block of zeros would be exactly the recognition mark that rule 3
  // excludes.
  b.setRange(kUniform + kKemBack, kShellSize,
      _sodium.randomBytes(kShellSize - kUniform - kKemBack));

  return Start._(e.hidden, e.secretKey, kem.secretKey, a, b);
}

/// The side of the CALLEE: from flight 1 come flight 2 and the key.
///
/// `null` if the two parts do not fit together or the computation
/// fails. There is NO result type that distinguishes „MAC wrong" from „broken"
/// — the caller would have nothing by which he could distinguish,
/// and thus cannot accidentally break the guarantee.
({Uint8List packet, Uint8List key, Uint8List uniformCaller})? answerShellHandshake(
    Uint8List partA, Uint8List partB) {
  if (partA.length != kShellSize || partB.length != kShellSize) {
    return null;
  }
  if (!_fits(partA, partB)) return null;
  try {
    _oqs.init();
    final uniformA = Uint8List.sublistView(partA, 0, kUniform);
    final kemPk = Uint8List(kKemKey)
      ..setRange(0, kKemFront, partA, kUniform)
      ..setRange(kKemFront, kKemKey, partB, kUniform);

    final e = _elligator.keyPair(_sodium.randomBytes(kUniform));
    final xSecret =
        _sodium.x25519ScalarMult(e.secretKey, _elligator.map(uniformA));
    final provisional = _provisional(xSecret);

    final kem = _oqs.mlKemEncapsulate(kemPk);
    final plaintext = Uint8List(kFlight2Plaintext)
      ..setRange(0, kKemCipher, kem.ciphertext);
    // The rest of the block is randomness — see above, no zeros.
    plaintext.setRange(kKemCipher, plaintext.length,
        _sodium.randomBytes(plaintext.length - kKemCipher));

    final nonce = _sodium.generateNonce();
    final box = _sodium.aesGcmEncrypt(plaintext, provisional, nonce,
        ad: _binding(uniformA, e.hidden));

    final p = Uint8List(kShellSize)
      ..setRange(0, kUniform, e.hidden)
      ..setRange(kUniform, kUniform + kNonce, nonce)
      ..setRange(kUniform + kNonce, kShellSize, box);

    return (
      packet: p,
      key: LinkKdf.deriveLinkKey(
          x25519Ss: xSecret, mlkemSs: kem.sharedSecret),
      uniformCaller: Uint8List.fromList(uniformA),
    );
  } on Object {
    return null;
  }
}

/// The side of the CALLER: from flight 2 comes the key. `null` = does not fit
/// (and that is all the caller learns).
Uint8List? complete(Start b, Uint8List flight2) {
  if (flight2.length != kShellSize) return null;
  try {
    _oqs.init();
    final uniformB = Uint8List.sublistView(flight2, 0, kUniform);
    final xSecret =
        _sodium.x25519ScalarMult(b._x25519Secret, _elligator.map(uniformB));
    final nonce = Uint8List.sublistView(flight2, kUniform, kUniform + kNonce);
    final box = Uint8List.sublistView(flight2, kUniform + kNonce);
    final plaintext = _sodium.aesGcmDecrypt(
        Uint8List.fromList(box), _provisional(xSecret),
        Uint8List.fromList(nonce),
        ad: _binding(b.uniform, uniformB));
    final ss = _oqs.mlKemDecapsulate(
        plaintext.sublist(0, kKemCipher), b._kemSecret);
    return LinkKdf.deriveLinkKey(x25519Ss: xSecret, mlkemSs: ss);
  } on Object {
    return null;
  }
}

/// Both Elligator shares as authenticated additional data. They bind flight 2 to
/// EXACTLY this flight 1: an answer to another handshake does not open,
/// not even from the same neighbour. That is the reason why
/// two simultaneously begun handshakes cannot be confused.
Uint8List _binding(Uint8List a, Uint8List b) =>
    (BytesBuilder()..add(a)..add(b)).toBytes();

Uint8List _provisional(Uint8List xSecret) => _sodium.hkdfSha256(
      xSecret,
      salt: LinkKdf.salt,
      info: Uint8List.fromList(utf8.encode(_infoProvisional)),
      length: 32,
    );

// ── The data packet ────────────────────────────────────────────────────────
//
// Here, not in `shell.dart`: the format of the wire belongs in the file
// that owns the format. `shell.dart` decides WHEN sending happens, and
// not HOW a packet looks.

/// Packs [payload] into a packet of exactly [kShellSize] B.
///
/// The filling behind the payload stays zero — it lies INSIDE the
/// seal and from outside is ciphertext like every other byte. Only the
/// filling of the handshake must be random, because it lies open.
Uint8List pack(Uint8List payload, Uint8List key) {
  final plaintext = Uint8List(kPlaintext);
  ByteData.sublistView(plaintext).setUint16(0, payload.length, Endian.little);
  plaintext.setRange(2, 2 + payload.length, payload);
  final nonce = _sodium.generateNonce();
  final box = _sodium.aesGcmEncrypt(plaintext, key, nonce);
  return Uint8List(kShellSize)
    ..setRange(0, kNonce, nonce)
    ..setRange(kNonce, kShellSize, box);
}

/// Opens a packet. `null` = does not fit — and the caller learns nothing more:
/// „wrong key", „tampered" and „nonsense" are the same
/// case and must remain so.
Uint8List? unpack(Uint8List packet, Uint8List key) {
  if (packet.length != kShellSize) return null;
  try {
    final plaintext = _sodium.aesGcmDecrypt(
        Uint8List.sublistView(packet, kNonce),
        key,
        Uint8List.sublistView(packet, 0, kNonce));
    final n = ByteData.sublistView(plaintext).getUint16(0, Endian.little);
    if (n > kPayloadAtMost) return null;
    return Uint8List.sublistView(plaintext, 2, 2 + n);
  } on Object {
    return null;
  }
}

/// Byte equality of two sequences.
bool equal(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Lexicographically smaller — decides the tie of two handshakes
/// in the same way on BOTH sides (see `shell.dart`).
bool smaller(Uint8List a, Uint8List b) {
  for (var i = 0; i < a.length && i < b.length; i++) {
    if (a[i] != b[i]) return a[i] < b[i];
  }
  return a.length < b.length;
}
