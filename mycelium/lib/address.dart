import 'dart:typed_data';

import 'package:cleona/core/config/network_channel.dart'
    show kIdentityDomainBytes;
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/identity/rotation_chain.dart';
import 'package:mycelium/envelope.dart' show EnvelopeBroken;

/// The public part of a post box — what one gives to a contact
/// so that they can send one something.
///
/// ── THREE PARTS THAT LIVE FOR DIFFERENT LENGTHS (S385 E1, S398 A) ─────────
///
/// The **identifier** is the founding value of V4.2 §4.1 and lives as long as
/// the identity: it does not change when the signing keys change (Emergency
/// Key Rotation, §4.5.4, D-33). The **signing part** (Ed25519 + ML-DSA-65)
/// stays until such a rotation. The **KEM part** (X25519 + ML-KEM-768)
/// changes every seven days (routine KEM rotation). From this follow three
/// comparisons, and they must not be confused:
///
///  * [sameIdentity] — the same human: the same identifier. Whoever asks
///    "does this come from the one I wrote to?" asks THAT.
///  * [sameKeys] — the same signing part.
///  * [equal] — the same bytes, `state` included. Only for the
///    question whether something has changed in a remembered copy.
///
/// **An address whose keys do not hash to its identifier is a ROTATED one**
/// ([rotated]). It is believed only with the rotation chain (§4.5.4): the
/// reader of the wire ([outBytes]) refuses it unless the caller has checked
/// the chain, and the envelope (`envelope.dart`) is the one place that does
/// so for sealed packets. Until S398 the identifier was computed from the
/// current signing keys, and every signing change made a NEW identifier and
/// a new contact (owner decision 14.09.2026, replaced by D-33).
///
/// [state] is the point in time of the KEM generation in milliseconds. It is
/// the order of two copies of the same identity ([adopt]) and
/// the start of the grace period for the previous generation. There is no state 0:
/// an address without a point in time would be older than every remembered one and would
/// never be adopted.
class Address {
  /// The identifier (§4.1) — the founding value, 32 B. See [identifier].
  final Uint8List _identifier;

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

  /// The rotation chain from [identifier] to the signing part (§4.5.4) —
  /// [RotationChain.none] for an identity that never rotated. It is NOT part
  /// of [toBytes]: on the wire it travels next to the address (envelope,
  /// bundle, text line), in memory next to it (`memory_contact.dart`). It
  /// rides on the object so that every place that keeps an address keeps
  /// its proof — and with it the founding key the pair secret needs
  /// ([foundingEd25519Pk], §4.3).
  final RotationChain chain;

  /// [identifier] is the founding identifier; without it the keys found it
  /// themselves — an identity that never rotated. Passing one that differs
  /// is a statement the CALLER stands for: a remembered contact whose chain
  /// was checked when it was adopted, or the own rotated post box.
  Address({
    Uint8List? identifier,
    required this.ed25519Pk,
    required this.mlDsaPk,
    required this.x25519Pk,
    required this.mlKemPk,
    required this.state,
    RotationChain? chain,
  })  : _identifier = identifier ?? _foundedBy(ed25519Pk, mlDsaPk),
        chain = chain ?? RotationChain.none {
    if (state <= 0) {
      throw ArgumentError('state must be > 0, was $state');
    }
    if (_identifier.length != 32) {
      throw ArgumentError('identifier must be 32 B, was ${_identifier.length}');
    }
  }

  /// 32 + 32 + 1952 + 32 + 1184 + 8 = 3240 B. Identifier, then the signature
  /// part, then the KEM part.
  static const int length = 32 +
      32 +
      OqsFFI.mlDsaPublicKeyLength +
      32 +
      OqsFFI.mlKemPublicKeyLength +
      8;

  /// Fixed order, fixed lengths — no length prefix needed.
  Uint8List toBytes() {
    final b = Uint8List(length);
    var i = 0;
    b.setRange(i, i += 32, _identifier);
    b.setRange(i, i += 32, ed25519Pk);
    b.setRange(i, i += OqsFFI.mlDsaPublicKeyLength, mlDsaPk);
    b.setRange(i, i += 32, x25519Pk);
    b.setRange(i, i += OqsFFI.mlKemPublicKeyLength, mlKemPk);
    ByteData.sublistView(b).setInt64(i, state, Endian.big);
    return b;
  }

  /// Reads an address and attaches [chain]. A [rotated] one is refused
  /// unless [chain] leads from its identifier to its keys, or [proven]: the
  /// caller checks right after (the envelope's acceptance, which may spare
  /// the chain check when it already holds these keys) or reads its own
  /// encrypted memory, which holds only what was checked.
  static Address outBytes(Uint8List b,
      {RotationChain? chain, bool proven = false}) {
    if (b.length != length) {
      throw EnvelopeBroken('address is ${b.length} B, expected $length B');
    }
    var i = 0;
    final identifier = _cut(b, i, i += 32);
    final ed = _cut(b, i, i += 32);
    final dsa = _cut(b, i, i += OqsFFI.mlDsaPublicKeyLength);
    final x = _cut(b, i, i += 32);
    final kem = _cut(b, i, i += OqsFFI.mlKemPublicKeyLength);
    final state = ByteData.sublistView(b).getInt64(i, Endian.big);
    if (state <= 0) throw EnvelopeBroken('address without a valid state');
    final a = Address(
        identifier: identifier,
        ed25519Pk: ed,
        mlDsaPk: dsa,
        x25519Pk: x,
        mlKemPk: kem,
        state: state,
        chain: chain);
    if (a.rotated && !proven && !a.chain.holds(identifier, a.signingKeys)) {
      throw EnvelopeBroken('address whose keys do not found its identifier, '
          'without a rotation chain');
    }
    return a;
  }

  /// The identifier of this identity, verbatim V4.2 §4.1 over the FOUNDING
  /// keys: `userId = SHA-256(kIdentityDomain ‖ ed25519Pk_0 ‖ mlDsaPk_0)`.
  ///
  /// THERE IS ONE IDENTIFIER (owner decision "identifier = A", 15.09.2026;
  /// D-33, 28.09.2026): this value IS the app's UserID
  /// (`HdWallet.computeUserId` over the founding keys) and the fingerprint
  /// of the card (§15.2 "the identifier of §4.1"), before and after every
  /// Emergency Key Rotation. The KEM keys do not belong in it — they rotate
  /// every 7 d, the identifier does not (§4.1).
  ///
  /// [kIdentityDomainBytes] separates the networks (V4.2 §4.1, "beta ≠ live"):
  /// without it the same keys on beta and live yielded the same
  /// deposit identifier, and a holder in both networks linked them (S387).
  Uint8List get identifier => _identifier;

  /// The signing part as a position of the rotation chain.
  ChainKeys get signingKeys => ChainKeys(ed25519Pk, mlDsaPk);

  /// The founding Ed25519 key — the one `K_AB` and the codes hang on (§4.3):
  /// the current one before any rotation, `K_0` of the [chain] after one.
  /// `null` for a rotated address whose chain this copy does not carry
  /// (a contact the app made known without it): no pair can be formed then.
  Uint8List? get foundingEd25519Pk =>
      chain.founding?.ed25519Pk ?? (rotated ? null : ed25519Pk);

  /// The same address with other KEM keys and [state] — identifier, signing
  /// part and chain stay (routine KEM rotation, the invitation's own sealing
  /// keys).
  Address withKem(Uint8List x25519, Uint8List mlKem, int state) => Address(
      identifier: _identifier,
      ed25519Pk: ed25519Pk,
      mlDsaPk: mlDsaPk,
      x25519Pk: x25519,
      mlKemPk: mlKem,
      state: state,
      chain: chain);

  /// The keys of this address are not the founding keys: the identity has
  /// rotated (§4.5.4), and only its chain connects them to [identifier].
  late final bool rotated =
      !_equal(_foundedBy(ed25519Pk, mlDsaPk), _identifier);

  /// The same identity, regardless of which keys or which KEM generation.
  /// Safe to use as the ONE identity comparison because no [rotated]
  /// address gets past [outBytes] or the envelope without its chain.
  bool sameIdentity(Address other) => _equal(_identifier, other._identifier);

  /// The same signing part (§4.5.4 compares keys, never signature bytes).
  bool sameKeys(Address other) =>
      _equal(ed25519Pk, other.ed25519Pk) && _equal(mlDsaPk, other.mlDsaPk);

  /// Byte for byte the same address, [state] included.
  bool equal(Address other) =>
      sameIdentity(other) &&
      sameKeys(other) &&
      state == other.state &&
      _equal(x25519Pk, other.x25519Pk) &&
      _equal(mlKemPk, other.mlKemPk);

  /// The adoption rule — for EVERY path that wants to replace a remembered
  /// address: only the same identity, only a higher [state], and only the
  /// same signing part — or fresh keys whose [chain] passes through the
  /// remembered ones (§4.5.4 "what a receiver accepts": "keys a chain
  /// connects to them"). The chain rides on the fresh copy only if it was
  /// checked where it came in (the envelope, the bundle, the text line). A
  /// tie is a second copy, a smaller one a straggler or a replay; keys that
  /// are an EARLIER link than the remembered ones are superseded and never
  /// adopted (the fresh chain does not pass through the later keys).
  static bool adopt(Address soFar, Address fresh) =>
      soFar.sameIdentity(fresh) &&
      fresh.state > soFar.state &&
      (soFar.sameKeys(fresh) ||
          fresh.chain.passesThrough(soFar.signingKeys));
}

Uint8List _foundedBy(Uint8List ed, Uint8List dsa) =>
    SodiumFFI().sha256(Uint8List.fromList([
      ...kIdentityDomainBytes,
      ...ed,
      ...dsa,
    ]));

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
