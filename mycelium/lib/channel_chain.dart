/// The key chain of a group or channel on the shared key (V4.2 §16.2.5).
///
/// ```
/// r_g ──"channel/day"──> D_g(d0) ──"channel/next-day"──> D_g(d0+1) …
///                         │
///                         └"channel/step"──> S_g(d,0) ──"channel/next-step"──> S_g(d,1) …
///                                              │
///                                              └"channel/post" ‖ id ──> the key of ONE post
/// r_g ──"channel/keeper"──> A_g ──"channel/collect" ‖ d──> collect key pair of day d
/// r_g ──"channel/generation"──> W_g ──> generation key pair (Ed25519)
/// ```
///
/// `r_g` never leaves the device that drew it. Every member holds the day
/// key, `A_g` and the generation public key; owner and admins also hold
/// `W_g`. Derivation runs forward only — a member that sees a later day or
/// step derives forward and never backward, and a device keeps what it
/// holds for the last [kKeepDays] UTC days.
///
/// Pure functions, no state and no network: the application keeps the
/// chain (`lib/core/service/cleona_service_shared_key*.dart`), the
/// keepers and the collector here see only the public halves.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';

final SodiumFFI _na = SodiumFFI();

/// The days a device keeps keys and a keeper keeps entries (§16.2.5).
const int kKeepDays = 7;

/// Lengths on the wire and in the entry header.
const int kRootLength = 32;
const int kChainKeyLength = 32;
const int kGenerationIdLength = 8;
const int kChannelValueLength = 16;
const int kEntryHashLength = 16;
const int kEntryIdLength = 16;
const int kSignPkLength = 32;
const int kSignatureLength = 64;

/// How far a member derives forward at most in one go — a post naming a
/// step or day beyond it is refused instead of costing unbounded hashing.
const int kStepsForwardAtMost = 4096;
const int kDaysForwardAtMost = 64;

Uint8List _info(String label, [List<int> extra = const []]) =>
    Uint8List.fromList([...utf8.encode(label), ...extra]);

Uint8List _kdf(Uint8List ikm, String label, [List<int> extra = const []]) =>
    _na.hkdfSha256(ikm, info: _info(label, extra), length: kChainKeyLength);

Uint8List _u32(int v) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.big);

/// A fresh root `r_g` and generation identifier.
({Uint8List root, Uint8List id}) newGeneration() => (
      root: _na.randomBytes(kRootLength),
      id: _na.randomBytes(kGenerationIdLength),
    );

/// `D_g(d0) = HKDF(r_g, "channel/day")`.
Uint8List dayKeyFirst(Uint8List root) => _kdf(root, 'channel/day');

/// `D_g(d+1) = HKDF(D_g(d), "channel/next-day")`.
Uint8List dayKeyNext(Uint8List dayKey) => _kdf(dayKey, 'channel/next-day');

/// `S_g(d, 0) = HKDF(D_g(d), "channel/step")`.
Uint8List stepKeyFirst(Uint8List dayKey) => _kdf(dayKey, 'channel/step');

/// `S_g(d, j+1) = HKDF(S_g(d, j), "channel/next-step")`.
Uint8List stepKeyNext(Uint8List step) => _kdf(step, 'channel/next-step');

/// `A_g = HKDF(r_g, "channel/keeper")`.
Uint8List keeperKey(Uint8List root) => _kdf(root, 'channel/keeper');

/// `W_g = HKDF(r_g, "channel/generation")`.
Uint8List generationKey(Uint8List root) => _kdf(root, 'channel/generation');

/// The Ed25519 key pair seeded with `W_g`; its public key is the
/// generation public key.
({Uint8List publicKey, Uint8List secretKey}) generationPair(Uint8List w) =>
    _na.generateEd25519KeyPairFromSeed(w);

/// The day's collect key pair, seeded with `HKDF(A_g, "channel/collect" ‖ d)`.
({Uint8List publicKey, Uint8List secretKey}) collectPair(Uint8List a, int day) =>
    _na.generateEd25519KeyPairFromSeed(_kdf(a, 'channel/collect', _u32(day)));

/// The channel value: the first 16 B of SHA-256 over the collect public key
/// and the generation public key. It changes every day and with every
/// generation, and names neither the group nor a member.
Uint8List channelValue(Uint8List collectPk, Uint8List generationPk) =>
    Uint8List.fromList(_na
        .sha256(Uint8List.fromList([...collectPk, ...generationPk]))
        .sublist(0, kChannelValueLength));

/// The key of one post or inline object: `HKDF(S_g(d, j), "channel/post" ‖ id)`.
Uint8List postKey(Uint8List step, Uint8List id) =>
    _kdf(step, 'channel/post', id);

/// Derives forward from [fromKey] at [from] to [to] with [next]; `null` when
/// [to] lies before [from] (never backward) or beyond [atMost].
Uint8List? forward(Uint8List fromKey, int from, int to,
    Uint8List Function(Uint8List) next, int atMost) {
  if (to < from || to - from > atMost) return null;
  var k = fromKey;
  for (var i = from; i < to; i++) {
    k = next(k);
  }
  return k;
}

/// The day key of [day] from a held one at [heldDay].
Uint8List? dayKeyAt(Uint8List held, int heldDay, int day) =>
    forward(held, heldDay, day, dayKeyNext, kDaysForwardAtMost);

/// The step key [j] from a held one at [heldJ] of the same day.
Uint8List? stepKeyAt(Uint8List held, int heldJ, int j) =>
    forward(held, heldJ, j, stepKeyNext, kStepsForwardAtMost);

// ── Author keys and their certificate ─────────────────────────────────────

final Uint8List _kCertificate = utf8.encode('cleona-channel-author/v1');

Uint8List _certificateBytes(
        int generation, Uint8List generationId, Uint8List authorPk) =>
    Uint8List.fromList(
        [..._kCertificate, ..._u32(generation), ...generationId, ...authorPk]);

/// The certificate of an author key: a signature with the generation secret
/// key over the author key and `g` (number and identifier).
Uint8List certify(Uint8List generationSk, int generation,
        Uint8List generationId, Uint8List authorPk) =>
    _na.signEd25519(
        _certificateBytes(generation, generationId, authorPk), generationSk);

/// Whether [certificate] holds for [authorPk] under [generationPk].
bool certificateHolds(Uint8List generationPk, int generation,
    Uint8List generationId, Uint8List authorPk, Uint8List certificate) {
  if (certificate.length != kSignatureLength ||
      generationPk.length != kSignPkLength ||
      authorPk.length != kSignPkLength) {
    return false;
  }
  try {
    return _na.verifyEd25519(
        _certificateBytes(generation, generationId, authorPk),
        certificate,
        generationPk);
  } on Object {
    return false;
  }
}

/// A fresh author key pair for one generation.
({Uint8List publicKey, Uint8List secretKey}) newAuthorPair() =>
    _na.generateEd25519KeyPair();

Uint8List sign(Uint8List bytes, Uint8List sk) => _na.signEd25519(bytes, sk);

bool verifies(Uint8List bytes, Uint8List signature, Uint8List pk) {
  if (signature.length != kSignatureLength || pk.length != kSignPkLength) {
    return false;
  }
  try {
    return _na.verifyEd25519(bytes, signature, pk);
  } on Object {
    return false;
  }
}

// ── Hashes ────────────────────────────────────────────────────────────────

/// The hash an entry is named by: the first 16 B of its SHA-256.
Uint8List entryHash(Uint8List entry) =>
    Uint8List.fromList(_na.sha256(entry).sublist(0, kEntryHashLength));

/// The state root of §16.0: SHA-256 over the sorted 16-byte hashes.
Uint8List stateRoot(Iterable<Uint8List> hashes) {
  final sorted = hashes.map(hexOf).toSet().toList()..sort();
  final b = BytesBuilder();
  for (final h in sorted) {
    b.add(hexBytes(h));
  }
  return _na.sha256(b.toBytes());
}

String hexOf(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List hexBytes(String h) => Uint8List.fromList([
      for (var i = 0; i + 1 < h.length; i += 2)
        int.parse(h.substring(i, i + 2), radix: 16)
    ]);

/// The UTC day number of [t] (days since 1970-01-01).
int channelDay(DateTime t) =>
    t.toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
