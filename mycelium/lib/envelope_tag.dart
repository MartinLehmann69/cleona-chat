/// The pair tag of the envelope — how a message between two parties that
/// share `K_AB` is authenticated (V4.2 §4.4.1, §4.4.3 "Cleona is deniable";
/// owner 15.10.2026, S407-UMSCHLAG).
///
/// ── WHAT IT REPLACES ─────────────────────────────────────────────────────
/// Until 4.2.3 every envelope carried, inside the seal, an Ed25519 and an
/// ML-DSA-65 signature of the sender (64 + 3,309 B). §4.4.3 rules that a 1:1
/// message and a group leg carry NO signature: the tag `HKDF(K_AB, …)`
/// authenticates the sender symmetrically — post-quantum-safe through `s_AB`
/// — and the recipient can prove nothing to a third party, because it could
/// have computed the same tag itself.
///
/// ── THE CONSTRUCTION (established procedure, not a new one) ─────────────
/// HMAC-SHA-256 (RFC 2104) under a key derived from `K_AB` with
/// HKDF-SHA-256 (RFC 5869) and its own context word, so the same `K_AB`
/// that makes codes and the `0x23` seal never also makes a tag (`pair.dart`
/// keeps one derived key per purpose). The MAC covers exactly the bytes the
/// signatures covered — header code, sender address, recipient identifier,
/// plaintext (`Envelope._charsData`) — so the recipient and the direction
/// stay bound. Checked in constant time.
///
/// ── WHO GETS WHICH FORM (§1.2 principle 8) ───────────────────────────────
/// A 4.2.3 reader knows only the signed form and DISCARDS the tagged one (its
/// `unseal` reads the length field 0xFFFF as "signature does not fit"). So
/// the tagged form goes only to a party that has itself shown it reads it
/// ([EnvelopePairs.tagKeyTo]); everyone else gets the signed form. Reading
/// takes both, always.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/address.dart';
import 'package:mycelium/post_box.dart';

/// The length of the tag: the full HMAC-SHA-256 output.
const int kEnvelopeTagLength = 32;

/// The value in the signature-length field that marks the tagged form. A
/// 4.2.3 reader refuses it (it exceeds the ML-DSA-65 signature length).
const int kEnvelopeTagMark = 0xFFFF;

/// What an identity knows about its pairs, for the envelope. Wired per post
/// box ([envelopePairsWire]); a post box without it seals signed and reads
/// only the signed form.
abstract interface class EnvelopePairs {
  /// `K_AB` towards [to] when [to] has shown it reads the tagged form,
  /// otherwise `null` (then the envelope is signed).
  Uint8List? tagKeyTo(Address to);

  /// Every `K_AB` the asserted sender [from] may arrive under — whatever it
  /// showed; empty for no pair. A contact has one; a group pair one per seed
  /// it may arrive under: the two sides learn of a new shared group one
  /// after the other and in between tag under different seeds (S407 B-12).
  List<Uint8List> tagKeysOf(Address from);

  /// [from] sent a tagged envelope that held: it reads the form.
  void tagShown(Address from);
}

final Expando<EnvelopePairs> _pairs = Expando('envelope pairs');

/// Wires [pairs] to the post box [me].
void envelopePairsWire(PostBox me, EnvelopePairs pairs) => _pairs[me] = pairs;

/// The pairs wired to [me], or `null`.
EnvelopePairs? envelopePairsOf(PostBox me) => _pairs[me];

final SodiumFFI _na = SodiumFFI();

/// The tag over [bound] under [kAB].
Uint8List envelopeTag(Uint8List kAB, Uint8List bound) {
  final key = _na.hkdfSha256(kAB,
      info: Uint8List.fromList(utf8.encode('cleona-envelope-tag/v1')),
      length: 32);
  return _na.hmacSha256(key, bound);
}

/// Whether [tag] is the tag over [bound] under [kAB] — constant time.
bool envelopeTagHolds(Uint8List kAB, Uint8List bound, Uint8List tag) {
  final want = envelopeTag(kAB, bound);
  if (tag.length != want.length) return false;
  var d = 0;
  for (var i = 0; i < want.length; i++) {
    d |= want[i] ^ tag[i];
  }
  return d == 0;
}
