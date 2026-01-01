/// The proof of work on a durable-object deposit (`0x90`) — v4_2 §16.7
/// "Declared limits": every system-channel object costs `D_box` (§8.2),
/// under a second per object. S407 SK-1.
///
/// The procedure and the difficulty are the post box's
/// (`post_box_proof_of_work.dart`, [kDifficultyDeposit]) — reused, not
/// invented: the building block [ProofOfWork], 16 B on the wire
/// (`random 8 | counter u64 LE`), the current and the previous window of
/// 10 min are valid. Only the code differs, under its own label so that a
/// proof for one class never passes for the other:
/// `SHA-256("mycelium-durable-1" ‖ channel ‖ object)[0:16]`.
///
/// The proof is computed once per object and carried in every `0x90` of
/// that deposit; a holder checks it before it offers the object to the
/// application, and a deposit without a valid proof is refused (`0x94`).
/// An object fetched later (`0x92`) carries none: it was paid for once, at
/// the deposit, and its holders checked it there.
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/post_box_proof_of_work.dart'
    show kDifficultyDeposit, kProofOfWorkLength;
import 'package:mycelium/proof_of_work.dart';

final Uint8List _label = utf8.encode('mycelium-durable-1');

Uint8List _code(int channel, Uint8List object) => Uint8List.fromList(
    SodiumFFI()
        .sha256((BytesBuilder()
              ..add(_label)
              ..addByte(channel)
              ..add(object))
            .toBytes())
        .sublist(0, ProofOfWork.codeLength));

/// Computes the 16 B proof for [object] in [channel] — in an isolate of its
/// own, as the post box does (the node's event loop carries on).
Future<Uint8List> durableProof(int channel, Uint8List object) async {
  final code = _code(channel, object);
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
  final p = Uint8List(kProofOfWorkLength)
    ..setRange(0, ProofOfWork.randomValueLength, r.$1);
  ByteData.sublistView(p)
      .setUint64(ProofOfWork.randomValueLength, r.$2, Endian.little);
  return p;
}

/// Does [proof] carry the work for exactly [object] in [channel]?
bool durableProofCarries(int channel, Uint8List object, Uint8List proof) {
  if (proof.length != kProofOfWorkLength) return false;
  final code = _code(channel, object);
  final random = proof.sublist(0, ProofOfWork.randomValueLength);
  final counter = ByteData.sublistView(proof)
      .getUint64(ProofOfWork.randomValueLength, Endian.little);
  final now = ProofOfWork.windowNow();
  return ProofOfWork.check(code, random, counter, kDifficultyDeposit,
          timeWindow: now) ||
      ProofOfWork.check(code, random, counter, kDifficultyDeposit,
          timeWindow: now - 1);
}
