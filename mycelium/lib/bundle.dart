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
/// `address 3208 ‖ length of the ML-DSA signature u16 ‖ Ed25519 64 ‖ ML-DSA`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/envelope.dart';

/// Shortest bundle: address, length field, Ed25519 signature — the
/// ML-DSA signature comes on top.
const int kBundleMinLength = Address.length + 2 + 64;

/// Builds the signed bundle of [me] as an answer to the plea with
/// [random].
Uint8List bundleBuild(Uint8List random, PostBox me) {
  final address = me.address.toBytes();
  final sig = me.sign(_data(random, address));
  final b = BytesBuilder()
    ..add(address)
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
  final addressBytes = Uint8List.sublistView(bundle, 0, Address.length);
  final address = Address.outBytes(Uint8List.fromList(addressBytes));
  final dsaLength =
      ByteData.sublistView(bundle).getUint16(Address.length, Endian.big);
  if (dsaLength > OqsFFI.mlDsaSignatureLength ||
      bundle.length != kBundleMinLength + dsaLength) {
    throw EnvelopeBroken('signature does not fit into the bundle');
  }
  final ed = Uint8List.sublistView(
      bundle, Address.length + 2, kBundleMinLength);
  final dsa = Uint8List.sublistView(bundle, kBundleMinLength);
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
