/// The bundle — packet (1) of first contact, signed (S385, E1).
///
/// ── WHY IT MUST BE SIGNED ───────────────────────────────────────
///
/// Since E1 the card's fingerprint is the [Address.identifier], and that
/// depends only on the signing part. An unsigned bundle could be
/// rewritten on the way: real signing part, own KEM part —
/// the identifier would fit, and the attacker would read the request including Alice's
/// full address. And "on the way" is no exotic situation here: the
/// card itself can name a neighbour as a route.
///
/// ── WHY THE RANDOM VALUE OF THE PLEA BELONGS IN IT ───────────────────────
///
/// A signature only over the address would be replayable: an old
/// recording (previous generation — the one whose secret part was
/// discarded after seven days or stolen) would pass every check. What is signed is
/// therefore `domain ‖ random value of the plea ‖ address` — the random value travels
/// back anyway, that costs zero bytes (S385-E1-WIDERLEGUNG 2a).
///
/// Layout (behind kind byte and random value):
/// `address 3240 ‖ rotation chain 1 + 5357·n ‖ length of the ML-DSA signature
/// u16 ‖ Ed25519 64 ‖ ML-DSA`. The chain (§4.5.4, §15.2: "the bundle and the
/// text line of a rotated identity carry the chain") leads from the
/// identifier — the card's fingerprint — to the signing keys; it is not
/// under the signature, it proves itself.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/identity/rotation_chain.dart';
import 'package:mycelium/card_text.dart' show CardLine, kLineBundleLength;
import 'package:mycelium/envelope.dart';

/// Shortest bundle: address, empty chain, length field, Ed25519 signature —
/// the ML-DSA signature and the chain's links come on top.
const int kBundleMinLength = Address.length + 1 + 2 + 64;

/// Builds the signed bundle of [me] as an answer to the plea with
/// [random].
Uint8List bundleBuild(Uint8List random, PostBox me) {
  final address = me.address.toBytes();
  final sig = me.sign(_data(random, address));
  final b = BytesBuilder()
    ..add(address)
    ..add(me.address.chain.toWire())
    ..add((ByteData(2)..setUint16(0, sig.dsa.length, Endian.big))
        .buffer
        .asUint8List())
    ..add(sig.ed)
    ..add(sig.dsa);
  return b.toBytes();
}

/// Checks a bundle against the own plea with [random] and returns the
/// address signed in it — or throws [EnvelopeBroken]. Whether the
/// address matches the card is checked by the caller ([Address.identifier]).
Address bundleCheck(Uint8List random, Uint8List bundle) {
  if (bundle.length < kBundleMinLength) {
    throw EnvelopeBroken('bundle without signature (${bundle.length} B)');
  }
  final addressBytes =
      Uint8List.fromList(Uint8List.sublistView(bundle, 0, Address.length));
  final int chainLength;
  final Address address;
  try {
    chainLength = RotationChain.wireLengthAt(bundle, Address.length);
    final keys = ChainKeys(Uint8List.sublistView(addressBytes, 32, 64),
        Uint8List.sublistView(addressBytes, 64, 64 + OqsFFI.mlDsaPublicKeyLength));
    // A rotated address only with the chain that holds (`address.dart`).
    address = Address.outBytes(addressBytes,
        chain: RotationChain.fromWire(
            Uint8List.fromList(Uint8List.sublistView(bundle, Address.length,
                Address.length + chainLength)),
            keys));
  } on RotationChainError catch (e) {
    throw EnvelopeBroken('chain of the bundle: ${e.reason}');
  }
  final head = Address.length + chainLength;
  if (bundle.length < head + 2 + 64) {
    throw EnvelopeBroken('bundle without signature (${bundle.length} B)');
  }
  final dsaLength = ByteData.sublistView(bundle).getUint16(head, Endian.big);
  if (dsaLength > OqsFFI.mlDsaSignatureLength ||
      bundle.length != head + 2 + 64 + dsaLength) {
    throw EnvelopeBroken('signature does not fit into the bundle');
  }
  final ed = Uint8List.sublistView(bundle, head + 2, head + 2 + 64);
  final dsa = Uint8List.sublistView(bundle, head + 2 + 64);
  final data = _data(random, addressBytes);
  if (!SodiumFFI().verifyEd25519(data, ed, address.ed25519Pk) ||
      !(OqsFFI()..init()).mlDsaVerify(data, dsa, address.mlDsaPk)) {
    throw EnvelopeBroken('signature of the bundle does not verify');
  }
  return address;
}

final Uint8List _domain = utf8.encode('mycelium-bundle-1');

Uint8List _data(Uint8List random, Uint8List address) =>
    (BytesBuilder()
          ..add(_domain)
          ..add(random)
          ..add(address))
        .toBytes();

/// The line bundle of [a] with the INVITATION's ML-KEM key [mlKemPk] — the
/// key bundle as the `cleona:2:` line carries it (V4.2 §15.1, §15.6):
/// Ed25519 ‖ ML-KEM-768 ‖ ML-DSA-65, [kLineBundleLength] B. Ed25519 and
/// ML-DSA are the identity's (the fingerprint covers only them); the sealing
/// keys are the invitation's own (owner decision R-b), the X25519 one in the
/// card's letter key (§15.2).
Uint8List lineBundleBuild(Address a, Uint8List mlKemPk) {
  final b = (BytesBuilder()
        ..add(a.ed25519Pk)
        ..add(mlKemPk)
        ..add(a.mlDsaPk))
      .toBytes();
  if (b.length != kLineBundleLength) {
    throw StateError('line bundle has ${b.length} B, the line format '
        'names $kLineBundleLength');
  }
  return b;
}

/// The address the line names: the three keys of [bundle] and the card's
/// letter key [x25519Pk]. The line carries no generation time, so the
/// address gets the smallest one (1): every signed copy of the same identity
/// replaces it ([Address.adopt]) — the answer (3) carries one. Whether it
/// matches the card's fingerprint is checked by the caller, exactly as for
/// packet (1) ([Address.identifier]). Throws [EnvelopeBroken] on a length
/// other than [kLineBundleLength].
///
/// [chain] is the line's rotation chain in wire form (§15.6); with at least
/// one link the address takes [fingerprint] as its identifier, and the chain
/// must lead from it to the bundle's keys — otherwise [EnvelopeBroken] (the
/// reader reports the line as altered, §15.6).
Address lineBundleAddress(Uint8List bundle, Uint8List x25519Pk,
    {Uint8List? chain, Uint8List? fingerprint}) {
  if (bundle.length != kLineBundleLength) {
    throw EnvelopeBroken('line bundle has ${bundle.length} B, '
        'expected $kLineBundleLength');
  }
  var i = 0;
  Uint8List cut(int n) =>
      Uint8List.fromList(Uint8List.sublistView(bundle, i, i += n));
  final ed = cut(32);
  final kem = cut(OqsFFI.mlKemPublicKeyLength);
  final dsa = cut(OqsFFI.mlDsaPublicKeyLength);
  RotationChain c;
  try {
    c = chain == null
        ? RotationChain.none
        : RotationChain.fromWire(chain, ChainKeys(ed, dsa));
  } on RotationChainError catch (e) {
    throw EnvelopeBroken('chain of the line: ${e.reason}');
  }
  final a = Address(
      identifier: c.isEmpty ? null : fingerprint,
      ed25519Pk: ed,
      mlDsaPk: dsa,
      x25519Pk: Uint8List.fromList(x25519Pk),
      mlKemPk: kem,
      state: 1,
      chain: c);
  if (a.rotated && !c.holds(a.identifier, a.signingKeys)) {
    throw EnvelopeBroken('the chain of the line does not lead from the '
        'fingerprint to its keys');
  }
  return a;
}

/// Does the bundle of a `cleona:2:` line belong to its card (§15.6
/// "altered")? Its keys hash to the fingerprint, or its chain leads from the
/// fingerprint to them. `true` for a `cleona:1:` line (nothing to check).
bool lineBundleFits(CardLine line) {
  final bundle = line.bundle;
  if (bundle == null) return true;
  try {
    final a = lineBundleAddress(bundle, line.card.letterKeyX25519,
        chain: line.chain, fingerprint: line.card.fingerprint);
    return line.card.matchesIdentifier(a.identifier);
  } on EnvelopeBroken {
    return false;
  }
}

/// A fresh key pair for sealing to ONE invitation (owner decision R-b):
/// X25519 and ML-KEM-768 at RANDOM, never derived — a key derived from the
/// signing key would let whoever obtains that key later open every recorded
/// request of every past invitation (the identity's KEM keys are random for
/// the same reason). Kept with the invitation record, gone with it.
KemParts invitationKemFresh() {
  final x = SodiumFFI().generateX25519KeyPair();
  final k = (OqsFFI()..init()).mlKemKeypair();
  return (
    x25519Pk: x.publicKey,
    x25519Sk: x.secretKey,
    mlKemPk: k.publicKey,
    mlKemSk: k.secretKey,
  );
}

/// A fresh invitation box key pair `pk_inv`/`sk_inv` (V4.2 §15.1, E-A4):
/// Ed25519 at RANDOM, kept with the invitation record. Derived from the
/// signing key it would let whoever obtains that key — or the seed of an
/// identity that never rotated — collect and delete every request, and an
/// Emergency Key Rotation would strand every standing line.
({Uint8List pk, Uint8List sk}) invitationBoxFresh() {
  final p = SodiumFFI().generateEd25519KeyPair();
  return (pk: p.publicKey, sk: p.secretKey);
}

/// [me] with the invitation's sealing keys [kem] in place of its own — what
/// opens a request sealed from a `cleona:2:` line. The signing part, the
/// chain and the book are the identity's, so the envelope's signature check
/// (over the identifier) and its acceptance hold unchanged.
PostBox invitationPostBox(PostBox me, KemParts kem) => me.withKem(kem);
