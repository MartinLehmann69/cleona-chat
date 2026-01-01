/// The rotation chain of an identity — its wire form and its check, in ONE
/// place (V4.2 §4.5.4, D-33).
///
/// An Emergency Key Rotation keeps the identity: the identifier stays the
/// founding value `SHA-256(kIdentityDomain ‖ Ed25519_0 ‖ ML-DSA-65_0)` (§4.1),
/// and the new signing keys are bound to it by the chain. Per rotation one
/// link: the PREVIOUS key pair signs `newEd25519Pk ‖ newMlDsaPk`
/// ([StoredRotationLink.linkContentOf]) with Ed25519 AND ML-DSA-65 — the
/// chain is a long-lived verifiable artifact and therefore hybrid (§4.4.3).
///
/// Two consumers check it, and both call [RotationChain.holds]: the system
/// channel (`system_channel_records.dart`, records of a rotated author) and
/// the delivery layer (`package:mycelium`, the envelope, the key bundle and
/// the text line of first contact). Until this file existed the check stood
/// only in the system channel.
///
/// ── WIRE FORM (§4.5.4) ───────────────────────────────────────────────────
/// ```
/// n                     1 B, 0 = no chain, at most [kRotationChainMaxLinks]
/// K_0                   founding Ed25519 32 ‖ founding ML-DSA-65 1952 (n ≥ 1)
/// per link i = 1..n:    sigEd_i 64 ‖ sigDsa_i 3309   by K_{i-1} over K_i
///                       K_i 1984 only for i < n
/// ```
/// `K_n` is not on the wire: it is the pair of signing keys of the address
/// the chain accompanies, and the reader passes it in ([fromWire]). Length:
/// `1 + 5357·n`.
library;

import 'dart:typed_data';

import 'package:cleona/core/crypto/hd_wallet.dart';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/identity/identity_context.dart'
    show StoredRotationLink;

/// Upper limit for the number of links (E-A14). A DoS gate, not a statement
/// about plausible rotations: without it a chain with N invented links costs
/// the reader N ML-DSA checks. Far above any plausible number of emergency
/// rotations of one identity — a reached limit would lock the author out.
const int kRotationChainMaxLinks = 32;

/// One key position of the chain: Ed25519 + ML-DSA-65, 1984 B.
const int kChainKeysLength = 32 + OqsFFI.mlDsaPublicKeyLength;

/// The two signatures of one link: Ed25519 64 + ML-DSA-65 3309 B.
const int kChainSignaturesLength = 64 + OqsFFI.mlDsaSignatureLength;

/// What one link adds on the wire: its signatures and one key position
/// (either its own new keys or, for the last link, the founding keys that a
/// chain of length ≥ 1 carries in front) — 5357 B.
const int kChainLinkWireLength = kChainKeysLength + kChainSignaturesLength;

/// A chain whose bytes do not form one (short, too long, too many links).
class RotationChainError implements Exception {
  final String reason;
  RotationChainError(this.reason);
  @override
  String toString() => 'RotationChainError: $reason';
}

/// The signing keys of one position of the chain.
class ChainKeys {
  final Uint8List ed25519Pk;
  final Uint8List mlDsaPk;

  ChainKeys(this.ed25519Pk, this.mlDsaPk) {
    if (ed25519Pk.length != 32 ||
        mlDsaPk.length != OqsFFI.mlDsaPublicKeyLength) {
      throw RotationChainError('keys of ${ed25519Pk.length}/${mlDsaPk.length} '
          'B, expected 32/${OqsFFI.mlDsaPublicKeyLength} B');
    }
  }

  /// The identifier these keys found (§4.1) — only for K_0 the identity's.
  Uint8List get identifier => HdWallet.computeUserId(ed25519Pk, mlDsaPk);

  /// Key comparison, never a comparison of signature bytes: ML-DSA signs
  /// hedged, two signatures by the same key over the same content differ.
  bool same(ChainKeys other) =>
      _equal(ed25519Pk, other.ed25519Pk) && _equal(mlDsaPk, other.mlDsaPk);
}

/// One link: the previous pair's two signatures over [next].
class ChainLink {
  final Uint8List sigEd25519;
  final Uint8List sigMlDsa;
  final ChainKeys next;

  ChainLink(this.sigEd25519, this.sigMlDsa, this.next);
}

/// The chain founding → current keys. Immutable.
class RotationChain {
  /// `K_0`, `null` exactly when there is no link.
  final ChainKeys? founding;
  final List<ChainLink> links;

  RotationChain._(this.founding, List<ChainLink> links)
      : links = List.unmodifiable(links);

  /// The chain of an identity that never rotated.
  static final RotationChain none = RotationChain._(null, const []);

  int get length => links.length;
  bool get isEmpty => links.isEmpty;

  /// `K_0 … K_n` — empty for [none].
  List<ChainKeys> get keys =>
      [?founding, for (final l in links) l.next];

  /// Wire length of a chain with [n] links: `1 + 5357·n`.
  static int wireLength(int n) => 1 + kChainLinkWireLength * n;

  /// The persisted chain of an identity (`IdentityContext.rotationChain`).
  /// Throws [RotationChainError] if the links do not follow each other —
  /// such a chain was never written by [IdentityContext.rotateIdentityFull].
  static RotationChain fromStored(List<StoredRotationLink> stored) =>
      fromExplicit([
        for (final l in stored)
          (
            oldEd25519Pk: l.oldEd25519Pk,
            oldMlDsaPk: l.oldMlDsaPk,
            newEd25519Pk: l.newEd25519Pk,
            newMlDsaPk: l.newMlDsaPk,
            sigEd25519: l.oldSignatureEd25519,
            sigMlDsa: l.oldSignatureMlDsa,
          )
      ]);

  /// A chain whose links each name their previous AND their new keys (the
  /// system channel's wire form). The previous keys of link i must be the
  /// new keys of link i-1; otherwise [RotationChainError].
  static RotationChain fromExplicit(
      List<
              ({
                Uint8List oldEd25519Pk,
                Uint8List oldMlDsaPk,
                Uint8List newEd25519Pk,
                Uint8List newMlDsaPk,
                Uint8List sigEd25519,
                Uint8List sigMlDsa,
              })>
          explicit) {
    if (explicit.isEmpty) return none;
    if (explicit.length > kRotationChainMaxLinks) {
      throw RotationChainError('${explicit.length} links, at most '
          '$kRotationChainMaxLinks');
    }
    final founding =
        ChainKeys(explicit.first.oldEd25519Pk, explicit.first.oldMlDsaPk);
    final links = <ChainLink>[];
    var previous = founding;
    for (final l in explicit) {
      if (!previous.same(ChainKeys(l.oldEd25519Pk, l.oldMlDsaPk))) {
        throw RotationChainError('link ${links.length + 1} does not start at '
            'the keys its predecessor ends at');
      }
      final next = ChainKeys(l.newEd25519Pk, l.newMlDsaPk);
      links.add(ChainLink(l.sigEd25519, l.sigMlDsa, next));
      previous = next;
    }
    return RotationChain._(founding, links);
  }

  /// Wire bytes — see the file header. `K_n` is left out.
  Uint8List toWire() {
    final b = BytesBuilder()..addByte(links.length);
    if (links.isEmpty) return b.toBytes();
    _keysWrite(b, founding!);
    for (var i = 0; i < links.length; i++) {
      final l = links[i];
      if (l.sigEd25519.length != 64 ||
          l.sigMlDsa.length != OqsFFI.mlDsaSignatureLength) {
        throw RotationChainError('link ${i + 1} carries signatures of '
            '${l.sigEd25519.length}/${l.sigMlDsa.length} B, the wire form '
            'names 64/${OqsFFI.mlDsaSignatureLength} B');
      }
      b.add(l.sigEd25519);
      b.add(l.sigMlDsa);
      if (i < links.length - 1) _keysWrite(b, l.next);
    }
    return b.toBytes();
  }

  /// The wire length of the chain that starts at [offset] of [b], read from
  /// its count byte alone. Throws [RotationChainError] on a count above
  /// [kRotationChainMaxLinks] or when [b] ends before the chain does.
  static int wireLengthAt(Uint8List b, int offset) {
    if (offset >= b.length) {
      throw RotationChainError('no count byte at offset $offset');
    }
    final n = b[offset];
    if (n > kRotationChainMaxLinks) {
      throw RotationChainError('$n links, at most $kRotationChainMaxLinks');
    }
    final length = wireLength(n);
    if (offset + length > b.length) {
      throw RotationChainError('chain of $n link(s) needs $length B, '
          '${b.length - offset} B are left');
    }
    return length;
  }

  /// Reads the wire form; [current] is `K_n`, the keys of the address the
  /// chain accompanies. Checks the FORM only — whether it holds, says
  /// [holds]. Throws [RotationChainError].
  static RotationChain fromWire(Uint8List b, ChainKeys current) {
    final length = wireLengthAt(b, 0);
    if (length != b.length) {
      throw RotationChainError('chain of ${b.length} B, its count names '
          '$length B');
    }
    final n = b[0];
    if (n == 0) return none;
    var i = 1;
    Uint8List cut(int k) =>
        Uint8List.fromList(Uint8List.sublistView(b, i, i += k));
    ChainKeys keys() =>
        ChainKeys(cut(32), cut(OqsFFI.mlDsaPublicKeyLength));
    final founding = keys();
    final links = <ChainLink>[];
    for (var k = 1; k <= n; k++) {
      final ed = cut(64);
      final dsa = cut(OqsFFI.mlDsaSignatureLength);
      links.add(ChainLink(ed, dsa, k < n ? keys() : current));
    }
    return RotationChain._(founding, links);
  }

  /// Does the chain lead from [identifier] to [current]? (§4.5.4: "A chain
  /// holds if the founding keys hash to the identifier, every link verifies
  /// under both signatures against its predecessor, and the last link ends
  /// at the address's signing keys.")
  ///
  /// Without links: [current] must itself hash to [identifier].
  ///
  /// The order is deliberate: the cheap checks (count, one SHA-256, byte
  /// comparisons) first, then every Ed25519 signature, the ML-DSA ones last
  /// — a forged chain must not buy N ML-DSA checks.
  bool holds(Uint8List identifier, ChainKeys current) {
    try {
      if (links.isEmpty) return _equal(current.identifier, identifier);
      if (links.length > kRotationChainMaxLinks) return false;
      if (!_equal(founding!.identifier, identifier)) return false;
      if (!links.last.next.same(current)) return false;
      final sodium = SodiumFFI();
      var previous = founding!;
      for (final l in links) {
        if (!sodium.verifyEd25519(_content(l.next), l.sigEd25519,
            previous.ed25519Pk)) {
          return false;
        }
        previous = l.next;
      }
      final oqs = OqsFFI()..init();
      previous = founding!;
      for (final l in links) {
        if (!oqs.mlDsaVerify(_content(l.next), l.sigMlDsa, previous.mlDsaPk)) {
          return false;
        }
        previous = l.next;
      }
      return true;
    } on Object {
      return false;
    }
  }

  /// Is [k] one of `K_0 … K_{n-1}` — a key pair this chain has left behind?
  bool superseded(ChainKeys k) {
    final all = keys;
    for (var i = 0; i < all.length - 1; i++) {
      if (all[i].same(k)) return true;
    }
    return false;
  }

  /// Does the chain pass through [k] — `K_0 … K_n`?
  bool passesThrough(ChainKeys k) => keys.any((x) => x.same(k));

  static Uint8List _content(ChainKeys k) =>
      StoredRotationLink.linkContentOf(k.ed25519Pk, k.mlDsaPk);

  static void _keysWrite(BytesBuilder b, ChainKeys k) {
    b.add(k.ed25519Pk);
    b.add(k.mlDsaPk);
  }
}

bool _equal(Uint8List x, Uint8List y) {
  if (x.length != y.length) return false;
  var d = 0;
  for (var i = 0; i < x.length; i++) {
    d |= x[i] ^ y[i];
  }
  return d == 0;
}
