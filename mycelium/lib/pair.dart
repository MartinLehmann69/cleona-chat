/// The pair secret and the codes (V4.2 §4.3, §8.1, §8.2, §15.2 —
/// proposal M, owner approval 17.09.2026, D2 = a).
///
/// ── WHAT FOR ─────────────────────────────────────────────────────────────────
///
/// A packet names neither person nor device. Instead of the identifier it carries
/// a **code** that changes per pair, direction and UTC day and without
/// `K_AB` looks like randomness. The fixed neighbour of the recipient knows only
/// the codes that the recipient device has registered with him (§8.1).
///
/// ```
/// dh_AB = X25519(ed2x(founding_sk_A), ed2x(founding_pk_B))
/// K_AB  = HKDF-SHA-256(dh_AB ‖ s_AB, salt = SHA-256("cleona-pair/v1"),
///                      info = sorted(founding_pk_A, founding_pk_B))
/// code(A→B, d) = first 16 B of HKDF(K_AB, "code" ‖ pk_A ‖ pk_B ‖ d)
/// ```
///
/// `s_AB` (32 random bytes) is produced by the accepting side at first contact
/// and returned sealed in the bundle; both keep it with the contact.
/// `dh_AB` binds to the founding keys, `s_AB` holds against a
/// future quantum computer that knows both public keys from cards.
///
/// **Founding key** is the identity's FOUNDING Ed25519 key on both sides,
/// also after an Emergency Key Rotation (§4.3, §4.5.4, D-33):
/// [Address.foundingEd25519Pk] — the current key before any rotation, the
/// first key of the chain after one — and [PostBox.secretParts]'
/// `foundingEd25519Sk` on the own side. `K_AB`, and with it every code,
/// survives every rotation (E-A1: `s_AB` is kept). **The price, named
/// (§4.3):** whoever holds a founding secret key AND `s_AB` — a thief of the
/// device state, not of the seed alone — keeps computing the pair's codes
/// after a rotation; it learns when the pair is addressed, never what.
///
/// **Day keys** (§8.2): per identity and UTC day an Ed25519 pair,
/// derived from the CURRENT signing key — never from the founding key, so
/// that an Emergency Key Rotation takes the post box away from whoever holds
/// the old keys. Contacts get the public parts; deposits are made under
/// [dayValue].
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/address.dart';
import 'package:mycelium/envelope.dart' show PostBox;

/// Length of a code and of a day value.
const int kCodeLength = 16;

/// Length of `s_AB`.
const int kPairRandomLength = 32;

/// How many days one shipment of the own day keys covers (§8.2) — the day-key
/// message and, since proposal E, the request (2) and the answer (3).
const int kDayKeyDays = 31;

final SodiumFFI _na = SodiumFFI();
final Uint8List _salt = _na.sha256(utf8.encode('cleona-pair/v1'));

/// The UTC day as an integer (days since 1970).
int utcDay(DateTime t) =>
    t.toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

Uint8List _dayBytes(int day) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, day, Endian.big);

int _comparison(Uint8List a, Uint8List b) {
  for (var i = 0; i < a.length && i < b.length; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return a.length - b.length;
}

/// The founding Ed25519 key of [a] — or [StateError] for a rotated address
/// whose chain this copy does not carry (no pair can be formed then).
Uint8List foundingPk(Address a) =>
    a.foundingEd25519Pk ??
    (throw StateError('rotated address without its chain — founding key '
        'unknown, no pair secret'));

/// `K_AB` from the view of [me] towards [counterpart] — both sides
/// compute the same value, from the FOUNDING keys (§4.3).
Uint8List pairSecret(PostBox me, Address counterpart, Uint8List sAB) {
  if (sAB.length != kPairRandomLength) {
    throw ArgumentError('s_AB must have $kPairRandomLength B, has ${sAB.length}');
  }
  final ownPk = foundingPk(me.address);
  final otherPk = foundingPk(counterpart);
  final dh = _na.x25519ScalarMult(
      _na.ed25519SkToX25519(me.secretParts().foundingEd25519Sk),
      _na.ed25519PkToX25519(otherPk));
  final first = _comparison(ownPk, otherPk) <= 0;
  final info = (BytesBuilder()
        ..add(first ? ownPk : otherPk)
        ..add(first ? otherPk : ownPk))
      .toBytes();
  return _na.hkdfSha256(
      (BytesBuilder()..add(dh)..add(sAB)).toBytes(),
      salt: _salt,
      info: info,
      length: 32);
}

/// The code of direction [fromPk] → [toPk] on UTC day [day] — both the
/// FOUNDING Ed25519 keys ([foundingPk], §4.3 "Codes").
Uint8List pairCode(Uint8List kAB,
    {required Uint8List fromPk, required Uint8List toPk, required int day}) {
  final info = (BytesBuilder()
        ..add(utf8.encode('code'))
        ..add(fromPk)
        ..add(toPk)
        ..add(_dayBytes(day)))
      .toBytes();
  return _na.hkdfSha256(kAB, info: info, length: kCodeLength);
}

/// The first-contact code of a card (§15.2): from its 16-B invitation code.
Uint8List firstContactCode(Uint8List invitationCode) => _na.hkdfSha256(
    invitationCode,
    info: Uint8List.fromList(utf8.encode('first-contact')),
    length: kCodeLength);

/// The key under which the content of a `0x23` is sealed (§8.1:
/// „one part, no message inside, only its own fixed neighbour sealed to the
/// recipient"). Used in `mailbox_pair.dart`.
///
/// Own context word next to `code` and `first-contact`: the same `K_AB`
/// carries several purposes, and one derived key per purpose
/// keeps them apart. A code must never at the same time be a seal key
/// — codes travel openly in the packet (`forward.dart`).
Uint8List suchSealKey(Uint8List kAB) => _na.hkdfSha256(kAB,
    info: Uint8List.fromList(utf8.encode('where-are-you')),
    length: cryptoSecretBoxKeyBytes);

/// Fresh 32 random bytes for `s_AB`.
Uint8List newPairRandom() => _na.randomBytes(kPairRandomLength);

/// The day key of [me] on the UTC day [day] (§8.2).
({Uint8List pk, Uint8List sk}) deriveDayKey(PostBox me, int day) =>
    dayKeyFrom(me.daySeed, day);

/// The day key on [day] from [daySeed] — the current one ([PostBox.daySeed])
/// or, for 7 days after an Emergency Key Rotation, the previous one
/// ([PostBox.previousDaySeed], §8.2).
({Uint8List pk, Uint8List sk}) dayKeyFrom(Uint8List daySeed, int day) {
  final seed = _na.hkdfSha256(
      daySeed,
      info: (BytesBuilder()
            ..add(utf8.encode('day-key'))
            ..add(_dayBytes(day)))
          .toBytes(),
      length: 32);
  final p = _na.generateEd25519KeyPairFromSeed(seed);
  return (pk: p.publicKey, sk: p.secretKey);
}

/// The value under which a post box deposits for this day key — and, in the
/// same form, for an invitation box key `pk_inv` (§15.1; random per
/// invitation, `bundle.dart` `invitationBoxFresh`), so a holder cannot tell
/// the two apart.
Uint8List dayValue(Uint8List dayPk) =>
    Uint8List.sublistView(_na.sha256(dayPk), 0, kCodeLength);
