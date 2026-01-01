/// The report pseudonym of an identity (v4_2 §16.7 "Who the author is",
/// §4.4.3, §4.5.1, D-57). S407 SK-2.
///
/// Every report, +1 entry, vote and retraction in a system channel is signed
/// by this key and by no other key of the identity. It is
///
///   * an Ed25519 key (§4.4.3: the public object space is Ed25519 only,
///     D-56),
///   * derived from the master seed under its OWN label and the identity's
///     index — one per identity, the same on every device of the identity
///     (they share the seed), so the author can retract from any of them,
///   * never rotated: it is not bound to the identity's keys, so a key
///     rotation of the identity (§14.5) does not touch it and a report needs
///     no rotation chain,
///   * not a role pseudonym (§16.5): role pseudonyms are HD-derived secondary
///     identities and thus carry the identity label `cleona-ed25519-<index>`;
///     this label is a different one, so a report and a juror cannot be
///     linked by key.
///
/// The link between this key and the identity is published nowhere: an
/// object carries the pseudonym's public key only (live), or additionally
/// the UserID as stated by the author (beta, unsigned, D-57).
library;

import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';

class ReportPseudonym {
  /// The label of the derivation. A NEW label beside the existing ones of
  /// `hd_wallet.dart` (`cleona-ed25519-`, `cleona-mldsa-`, `cleona-mlkem-`,
  /// `cleona-file-enc-`, `cleona-shared-file-enc-v1`, `cleona-invite-root-v1`,
  /// `cleona-invite-v1`); it must never be reused for anything else.
  static const String kLabel = 'cleona-report-pseudonym-v1';

  final Uint8List publicKey;
  final Uint8List _secretKey;

  ReportPseudonym._(this.publicKey, this._secretKey);

  /// The report pseudonym of the identity at [identityIndex].
  ///
  /// `info` = [kLabel] ‖ 8 B big-endian index — the same unambiguous number
  /// encoding as `HdWallet.deriveInviteRoot` (text digits would let index 1
  /// and 12 collide with a suffix). No salt, as with every derivation of the
  /// master seed: it is 256 bit uniformly distributed already.
  factory ReportPseudonym.derive(Uint8List masterSeed, int identityIndex) {
    if (identityIndex < 0) {
      throw ArgumentError.value(identityIndex, 'identityIndex', 'must be >= 0');
    }
    if (masterSeed.length != 32) {
      throw ArgumentError('master seed must be 32 B');
    }
    final index = Uint8List(8);
    ByteData.view(index.buffer).setUint64(0, identityIndex, Endian.big);
    final info = BytesBuilder(copy: false)
      ..add(Uint8List.fromList(kLabel.codeUnits))
      ..add(index);
    final sodium = SodiumFFI();
    final seed = sodium.hkdfSha256(masterSeed, info: info.toBytes(), length: 32);
    final kp = sodium.generateEd25519KeyPairFromSeed(seed);
    return ReportPseudonym._(kp.publicKey, kp.secretKey);
  }

  /// A pseudonym from a random key — for tests and for the declared fact
  /// that pseudonyms are free (§16.8): anyone may make a fresh one.
  factory ReportPseudonym.random() {
    final kp = SodiumFFI().generateEd25519KeyPair();
    return ReportPseudonym._(kp.publicKey, kp.secretKey);
  }

  /// Ed25519 signature (64 B) over [message].
  Uint8List sign(Uint8List message) =>
      SodiumFFI().signEd25519(message, _secretKey);

  /// Checks an Ed25519 signature of [publicKey] over [message]. libsodium's
  /// verify refuses small-order public keys and non-canonical signatures.
  static bool verify(
      Uint8List message, Uint8List signature, Uint8List publicKey) {
    if (signature.length != 64 || publicKey.length != 32) return false;
    try {
      return SodiumFFI().verifyEd25519(message, signature, publicKey);
    } catch (_) {
      return false;
    }
  }
}
