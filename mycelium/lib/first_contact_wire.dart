/// The request (2) on the wire — built by the joiner, read by the issuer
/// (V4.2 §15.5, §15.5.1; proposal E, owner approval 28.09.2026).
///
/// ```
/// type 1 | random value 8 | counter 8 | time window 4 (u32 LE) | envelope
/// ```
///
/// The time window is the Unix time in minutes divided by ten — the one the
/// proof of work was computed for. Until proposal E it was not in the packet:
/// the issuer tried the current and the previous window, and a request that
/// had rested in a post box for more than ten minutes was discarded silently.
/// Now the issuer READS it and accepts it while it lies within the retention
/// of the post box ([ProofOfWork.windowAccepted]) — still one hash per
/// standing code, at most ten.
///
/// The window also anchors the day keys of (2) and (3): the first of the 31
/// belongs to the UTC day of this window (`first_contact_pair.dart`).
///
/// A separate file because `first_contact.dart` and
/// `first_contact_invitation.dart` stand at the line budget of 400; both
/// sides need these few lines, and one codec for both is one place.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/card.dart';
import 'package:mycelium/envelope.dart';
import 'package:mycelium/first_contact.dart' show Join;
import 'package:mycelium/first_contact_pair.dart';
import 'package:mycelium/introduction.dart';
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/proof_of_work.dart';

/// Length of the visible proof header before the envelope in packet (2):
/// random value (8 B) + counter (8 B) + time window (4 B). The type byte
/// before it does not count here.
const int proofOfWorkHeaderLength = ProofOfWork.randomValueLength + 8 + 4;

/// The UTC day a time window belongs to.
int dayOfWindow(int window) => window * ProofOfWork.windowSeconds ~/ 86400;

/// The visible header of a request: random value, counter, time window —
/// or `null` if [packet] is too short for it.
({Uint8List randomValue, int counter, int window})? requestHeaderRead(
    Uint8List packet) {
  if (packet.length < 1 + proofOfWorkHeaderLength) return null;
  final d = ByteData.sublistView(packet);
  return (
    randomValue: Uint8List.fromList(
        Uint8List.sublistView(packet, 1, 1 + ProofOfWork.randomValueLength)),
    counter: d.getUint64(1 + ProofOfWork.randomValueLength, Endian.little),
    window: d.getUint32(1 + ProofOfWork.randomValueLength + 8, Endian.little),
  );
}

/// The proof of work of a request (2), computed ahead for its [window].
typedef RequestProof = ({int window, Uint8List randomValue, int counter});

/// The proof for [card]'s request (2) in an isolate of its own, as the
/// deposit's (`post_box_proof_of_work.dart`): at the card's difficulty (20)
/// it took 13.2 s on the Windows lab machine, and computed on the event loop
/// it stopped IPC, cover stream and ladder for that long (S427-NT-1). It
/// depends only on the card and the window, not on the counterpart, so it
/// can be computed before the join starts. If the isolate fails, the
/// computation happens here.
Future<RequestProof> requestProofOfWork(Card card) async {
  final w = ProofOfWork.windowNow();
  (Uint8List, int) r;
  try {
    r = await Isolate.run(() {
      SodiumFFI();
      return ProofOfWork.generate(card.code, card.difficulty, timeWindow: w);
    });
  } on Object catch (e) {
    if (e is ProofOfWorkAborted) rethrow;
    r = ProofOfWork.generate(card.code, card.difficulty, timeWindow: w);
  }
  return (window: w, randomValue: r.$1, counter: r.$2);
}

/// Starts [b] with its proof computed off the event loop
/// ([requestProofOfWork]), then [then]. A `cleona:2:` line sends the request
/// (2) at once, so it starts once the proof is there; the QR/NFC round trip
/// sends the plea (0) now — it carries no proof — and only the request (2)
/// waits for it (S427 V-3: the plea had waited 8–16 s for a proof it does
/// not need). Should the computation fail, (2) computes as before.
void joinStartProven(Join b, void Function() then) {
  final proof = requestProofOfWork(b.card);
  if (b.lineBundle == null) {
    b.start(null, proof);
    then();
    return;
  }
  unawaited(proof
      .then((p) => b.start(p), onError: (Object _) => b.start())
      .whenComplete(then));
}

/// Builds the request (2) of [me] to [counterpart] for [card]: proof of work
/// for the card's code and difficulty in [window] (default: now) — or the
/// [proof] computed ahead for that window — then the sealed payload — code,
/// [answerCode], the own fixed [neighbour], the own day keys from the
/// window's day on, the [introduction].
Uint8List requestBuild({
  required Card card,
  required PostBox me,
  required Address counterpart,
  required Uint8List answerCode,
  required CardAddress? neighbour,
  required Introduction? introduction,
  required int window,
  RequestProof? proof,
}) {
  final (randomValue, counter) = proof != null && proof.window == window
      ? (proof.randomValue, proof.counter)
      : ProofOfWork.generate(card.code, card.difficulty, timeWindow: window);
  final content = requestContentBuild(card.code, answerCode, neighbour,
      dayKeysBuild(me, dayOfWindow(window)), introduction);
  final envelope =
      Envelope.seal(plaintext: content, recipient: counterpart, sender: me);
  final b = Uint8List(1 + proofOfWorkHeaderLength + envelope.length);
  b[0] = kinds.kRequest;
  b.setRange(1, 1 + ProofOfWork.randomValueLength, randomValue);
  final d = ByteData.sublistView(b);
  d.setUint64(1 + ProofOfWork.randomValueLength, counter, Endian.little);
  d.setUint32(1 + ProofOfWork.randomValueLength + 8, window, Endian.little);
  b.setRange(1 + proofOfWorkHeaderLength, b.length, envelope);
  return b;
}

/// Byte-wise comparison. Needed by both sides, therefore not private.
bool bytesEqual(Uint8List x, Uint8List y) {
  if (x.length != y.length) return false;
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}
