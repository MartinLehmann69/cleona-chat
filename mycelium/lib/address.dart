import 'dart:typed_data';

import 'package:cleona/core/config/network_channel.dart'
    show kIdentityDomainBytes;
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/envelope.dart' show EnvelopeBroken;

/// The public part of a post box — what one gives to a contact
/// so that they can send one something.
///
/// ── TWO PARTS THAT LIVE FOR DIFFERENT LENGTHS (S385, E1) ─────────────────
///
/// The **signing part** (Ed25519 + ML-DSA-65) stays as long as the
/// identity exists. The **KEM part** (X25519 + ML-KEM-768) changes
/// every seven days (V4.2 §4.5.4, routine KEM rotation). From this follow
/// two comparisons, and they must not be confused:
///
///  * [sameIdentity] — the same human. Whoever asks "does this come from the one
///    I wrote to?" asks THAT. Until S385 [equal] stood there, and
///    every receipt of a recipient who had rotated in the meantime would have been
///    discarded as "from someone else".
///  * [equal] — the same bytes, `state` included. Only for the
///    question whether something has changed in a remembered copy.
///
/// [identifier] depends only on the signing part and is therefore the same across every
/// routine rotation: deposit, forwarding, card, contact and
/// history depend on it. If the signing keys change (lock-out,
/// recovery with new keys, emergency), that is a NEW
/// identifier — and thus a new contact. A chain that connects old and new
/// deliberately does not exist here (owner decision 14.09.2026).
///
/// [state] is the point in time of the KEM generation in milliseconds. It is
/// the order of two copies of the same identity ([adopt]) and
/// the start of the grace period for the previous generation. There is no state 0:
/// an address without a point in time would be older than every remembered one and would
/// never be adopted.
class Address {
  /// Ed25519, 32 B — signature.
  final Uint8List ed25519Pk;

  /// ML-DSA-65, 1952 B — signature.
  final Uint8List mlDsaPk;

  /// X25519, 32 B — the classical part of the lock. A separate
  /// key: derived from Ed25519 at founding (that is what the app does),
  /// independent after the first rotation.
  final Uint8List x25519Pk;

  /// ML-KEM-768, 1184 B — the post-quantum part of the lock.
  final Uint8List mlKemPk;

  /// Point in time of this KEM generation, milliseconds since 1970. Always > 0.
  final int state;

  Address({
    required this.ed25519Pk,
    required this.mlDsaPk,
    required this.x25519Pk,
    required this.mlKemPk,
    required this.state,
  }) {
    if (state <= 0) {
      throw ArgumentError('state must be > 0, was $state');
    }
  }

  /// 32 + 1952 + 32 + 1184 + 8 = 3208 B. The signature part in front.
  static const int length = 32 +
      OqsFFI.mlDsaPublicKeyLength +
      32 +
      OqsFFI.mlKemPublicKeyLength +
      8;

  /// Fixed order, fixed lengths — no length prefix needed.
  Uint8List toBytes() {
    final b = Uint8List(length);
    var i = 0;
    b.setRange(i, i += 32, ed25519Pk);
    b.setRange(i, i += OqsFFI.mlDsaPublicKeyLength, mlDsaPk);
    b.setRange(i, i += 32, x25519Pk);
    b.setRange(i, i += OqsFFI.mlKemPublicKeyLength, mlKemPk);
    ByteData.sublistView(b).setInt64(i, state, Endian.big);
    return b;
  }

  static Address outBytes(Uint8List b) {
    if (b.length != length) {
      throw EnvelopeBroken('address is ${b.length} B, expected $length B');
    }
    var i = 0;
    final ed = _cut(b, i, i += 32);
    final dsa = _cut(b, i, i += OqsFFI.mlDsaPublicKeyLength);
    final x = _cut(b, i, i += 32);
    final kem = _cut(b, i, i += OqsFFI.mlKemPublicKeyLength);
    final state = ByteData.sublistView(b).getInt64(i, Endian.big);
    if (state <= 0) throw EnvelopeBroken('address without a valid state');
    return Address(
        ed25519Pk: ed, mlDsaPk: dsa, x25519Pk: x, mlKemPk: kem, state: state);
  }

  /// The identifier of this identity — the ONE place where it is computed
  /// in mycelium, and verbatim V4.2 §4.1:
  /// `userId = SHA-256(kIdentityDomain ‖ ed25519Pk ‖ mlDsaPk)`.
  ///
  /// THERE IS ONE IDENTIFIER (owner decision "identifier = A", 15.09.2026):
  /// this value IS the app's UserID (`HdWallet.computeUserId`) and the
  /// fingerprint of the card (§15.2 "the identifier of §4.1"). Until S388
  /// `"myzel-kennung-1"` additionally stood in front; with that the identifier was a
  /// second value next to the UserID, and the seam had to translate between the two.
  /// The KEM keys do not belong in it — they rotate
  /// every 7 d, the identifier does not (§4.1).
  ///
  /// [kIdentityDomainBytes] separates the networks (V4.2 §4.1, "beta ≠ live"):
  /// without it the same keys on beta and live yielded the same
  /// deposit identifier, and a holder in both networks linked them (S387).
  late final Uint8List identifier = SodiumFFI().sha256(Uint8List.fromList([
    ...kIdentityDomainBytes,
    ...ed25519Pk,
    ...mlDsaPk,
  ]));

  /// The same signature part — the same identity, regardless of which
  /// KEM generation.
  bool sameIdentity(Address other) =>
      _equal(ed25519Pk, other.ed25519Pk) && _equal(mlDsaPk, other.mlDsaPk);

  /// Byte for byte the same address, [state] included.
  bool equal(Address other) =>
      sameIdentity(other) &&
      state == other.state &&
      _equal(x25519Pk, other.x25519Pk) &&
      _equal(mlKemPk, other.mlKemPk);

  /// The adoption rule — for EVERY path that wants to replace a remembered
  /// address: only the same identity, and only a higher [state].
  /// A tie is a second copy, a smaller one a straggler or
  /// a replay. A different signing part NEVER replaces — it
  /// is a different identifier, hence a different contact.
  static bool adopt(Address soFar, Address fresh) =>
      soFar.sameIdentity(fresh) && fresh.state > soFar.state;
}

/// Real copy of a view — the views outlive the buffer.
Uint8List _cut(Uint8List b, int from, int until) =>
    Uint8List.fromList(Uint8List.sublistView(b, from, until));

bool _equal(Uint8List x, Uint8List y) {
  if (x.length != y.length) return false;
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}
