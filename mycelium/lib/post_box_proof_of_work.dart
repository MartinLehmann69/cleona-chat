import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/proof_of_work.dart';

/// The proof of computation on the deposit (0x30) — S385, proposal holder,
/// owner decision F3: the cap of 100 per day value (until S391: per
/// identifier) is supposed to protect the RECIPIENT, not just the holder.
///
/// Without proof it cost nothing to deposit 100 packets under a foreign value;
/// the cap then threw the real post out, because with the
/// FIFO cap the attacker's packets are always the NEWEST (proposal
/// B4, measured in `smoke_holder`: 100 of 100 places then belonged
/// to the attacker). The sender stays anonymous towards the holder (V4.2
/// §4.4.3) — he cannot prove anything, but he can pay.
///
/// The building block is [ProofOfWork] (`proof_of_work.dart`, the same procedure as the
/// contact request, V4.2 §15.5.1) and NOT `ProofOfWork` from
/// `lib/core/crypto`: that one returns a V3 protobuf.
///
/// **Bound to exactly this packet.** The code of the proof is
/// `SHA-256("mycelium-deposit-2" ‖ id ‖ Tageswert ‖ Inhalt)[0:16]` (since S391
/// under the day value instead of the identifier, proposal M). A proof
/// thus carries no other id, no other value, no other
/// content; a repetition of the same packet is at the holder a duplicate
/// of the same id and occupies no second place.
///
/// **Outdated after a time window** (10 min, [ProofOfWork.windowSeconds]):
/// computing ahead in stock does not work. The holder accepts the current and the
/// previous window — a packet that was computed shortly before the change
/// would otherwise never arrive. The clock is the wall clock of both sides, as with
/// first contact (`first_contact_invitation.dart`).
///
/// Wire form, 16 B between day value and content, like the header of the request
/// (`first_contact.dart` `nachweisKopfLaenge`):
/// `Zufallswert (8) | Zaehler (u64 LE)`.

/// Leading zero bits that a 0x30 must show. Measured and justified in
/// `berichte/S385-BAU-HALTER.md`, section 8 (`bin/store_proof_probe.dart`).
const int kDifficultyDeposit = 18;

const int kProofOfWorkLength = ProofOfWork.randomValueLength + 8;

final Uint8List _kDeposit = utf8.encode('mycelium-deposit-2');

Uint8List _code(Uint8List id, Uint8List value, Uint8List content) =>
    Uint8List.fromList(SodiumFFI()
        .sha256((BytesBuilder()
              ..add(_kDeposit)
              ..add(id)
              ..add(value)
              ..add(content))
            .toBytes())
        .sublist(0, ProofOfWork.codeLength));

/// Computes the proof for a 0x30 and returns the 16 B wire form.
///
/// In an isolate of its own: the node carries on the same event loop
/// cover stream, ladder and calls, and a computation of a few hundred
/// milliseconds would otherwise stop everything. If the isolate fails, the computation happens
/// here — the same trade-off as `ProofOfWork.computeAsync`
/// (`lib/core/crypto/proof_of_work.dart`, „FFI loading on Android").
Future<Uint8List> depositProofOfWork(
    Uint8List id, Uint8List value, Uint8List content) async {
  final code = _code(id, value, content);
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
  final header = Uint8List(kProofOfWorkLength)..setRange(0, ProofOfWork.randomValueLength, r.$1);
  ByteData.sublistView(header).setUint64(ProofOfWork.randomValueLength, r.$2, Endian.little);
  return header;
}

/// Does [header] (16 B) carry the proof for exactly this packet? One
/// SHA-256 over the content, then at most two checks.
bool depositProofOfWorkCarries(
    Uint8List id, Uint8List value, Uint8List content, Uint8List header) {
  if (header.length != kProofOfWorkLength) return false;
  final code = _code(id, value, content);
  final randomValue = header.sublist(0, ProofOfWork.randomValueLength);
  final counter = ByteData.sublistView(header)
      .getUint64(ProofOfWork.randomValueLength, Endian.little);
  final now = ProofOfWork.windowNow();
  return ProofOfWork.check(code, randomValue, counter, kDifficultyDeposit,
          timeWindow: now) ||
      ProofOfWork.check(code, randomValue, counter, kDifficultyDeposit,
          timeWindow: now - 1);
}
