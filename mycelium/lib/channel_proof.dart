/// The proof of work on the first deposit under a channel value at a keeper
/// (V4.2 §16.2.5 step 2): `D_box` of §8.2, bound to that value.
///
/// The same procedure as the post box (`post_box_proof_of_work.dart`), bound
/// to the value instead of one packet: an author computes it once per value
/// and may show it to every keeper of its list, and a keeper asks it only
/// for a value it does not hold yet. Without it, holding 1,000 entries under
/// a value nobody reads would cost nothing.
///
/// Outdated after its time window (10 min, [ProofOfWork.windowSeconds]); the
/// keeper accepts the current and the previous window.
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/post_box_proof_of_work.dart' show kDifficultyDeposit;
import 'package:mycelium/proof_of_work.dart';

final Uint8List _kDomain = utf8.encode('mycelium-channel-value-1');

Uint8List _code(Uint8List value) => Uint8List.fromList(SodiumFFI()
    .sha256(Uint8List.fromList([..._kDomain, ...value]))
    .sublist(0, ProofOfWork.codeLength));

/// Computes the 16-B proof for [value], in an isolate of its own (the node's
/// event loop carries cover and calls).
Future<Uint8List> channelProof(Uint8List value) async {
  final code = _code(value);
  (Uint8List, int) r;
  try {
    r = await Isolate.run(() {
      SodiumFFI();
      return ProofOfWork.generate(code, kDifficultyDeposit);
    });
  } on Object catch (e) {
    if (e is ProofOfWorkAborted) rethrow;
    r = ProofOfWork.generate(code, kDifficultyDeposit);
  }
  final out = Uint8List(ProofOfWork.randomValueLength + 8)
    ..setRange(0, ProofOfWork.randomValueLength, r.$1);
  ByteData.sublistView(out)
      .setUint64(ProofOfWork.randomValueLength, r.$2, Endian.little);
  return out;
}

/// Whether [proof] is a current proof for [value].
bool channelProofHolds(Uint8List value, Uint8List proof) {
  if (proof.length != ProofOfWork.randomValueLength + 8) return false;
  final code = _code(value);
  final random = proof.sublist(0, ProofOfWork.randomValueLength);
  final counter = ByteData.sublistView(proof)
      .getUint64(ProofOfWork.randomValueLength, Endian.little);
  final now = ProofOfWork.windowNow();
  return ProofOfWork.check(code, random, counter, kDifficultyDeposit,
          timeWindow: now) ||
      ProofOfWork.check(code, random, counter, kDifficultyDeposit,
          timeWindow: now - 1);
}

/// The window a proof computed now belongs to — an author recomputes once
/// the keeper would no longer take it.
int channelProofWindow() => ProofOfWork.windowNow();
