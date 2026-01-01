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

import 'dart:typed_data';

import 'package:mycelium/card.dart';
import 'package:mycelium/envelope.dart';
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

/// Builds the request (2) of [me] to [counterpart] for [card]: proof of work
/// for the card's code and difficulty in [window] (default: now), then the
/// sealed payload — code, [answerCode], the own fixed [neighbour], the own
/// day keys from the window's day on, the [introduction].
Uint8List requestBuild({
  required Card card,
  required PostBox me,
  required Address counterpart,
  required Uint8List answerCode,
  required CardAddress? neighbour,
  required Introduction? introduction,
  required int window,
}) {
  final (randomValue, counter) =
      ProofOfWork.generate(card.code, card.difficulty, timeWindow: window);
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
