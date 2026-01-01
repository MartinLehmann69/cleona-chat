/// What first contact additionally carries since proposal M (S391, §4.3,
/// §8.1, §15.2 of the proposal; owner approval 17.09.2026, D2 = a).
///
/// ── THE TWO PAYLOADS ─────────────────────────────────────────────────
///
/// ```
/// Request (2), in the seal:     code | answer code 16 B | neighbour (flag + address)
///                               | introduction (optional, `introduction.dart`)
/// Acceptance (3), in the seal:  0x01 | s_AB 32 B | introduction (optional)
/// Rejection (3):                0x00
/// ```
///
/// The **answer code** is a one-time code of the joiner: it registers it
/// with its fixed neighbour, and the acceptance comes there under it.
/// The **neighbour** is the fixed neighbour of the joiner — the inviter
/// has no card from it and learns it only here. **`s_AB`** is created by the
/// ACCEPTING side; an acceptance without it is no contact (`pair.dart`).
///
/// The proposal says "back in the bundle". The bundle (1) goes out
/// before the inviter knows who is asking, and is therefore not sealed
/// — only the acceptance (3) goes back sealed. It is the place.
///
/// ── WHY AN EXPANDO ─────────────────────────────────────────────────
///
/// [Join] and [Invitation] arise in the node (`node_join.dart`,
/// `node_invitation.dart`), but the pair data belongs to the mailbox.
/// [pairHook] hangs the connection on the identity's [PostBox] —
/// the same object that both carry as `me` —, without the node having to
/// pass it through.
library;

import 'dart:typed_data';

import 'package:mycelium/memory_invitation.dart' show Reader, MemoryError;
import 'package:mycelium/card_address.dart';
import 'package:mycelium/pair.dart' show kCodeLength, kPairRandomLength;
import 'package:mycelium/envelope.dart';
import 'package:mycelium/introduction.dart';

/// Sends [packet] under [code] to the neighbour [neighbour] (step 3 of
/// proposal M — built in part M2).
typedef CodeSend = void Function(
    Uint8List code, CardAddress neighbour, Uint8List packet);

/// The connection from first contact to the mailbox of an identity.
class PairHook {
  /// `s_AB` of an already existing contact — a recontact gets
  /// the same, otherwise the codes of both sides would not match.
  final Uint8List? Function(Address who) knownRandom;

  /// The accepting side has accepted [who]: `s_AB` and its neighbour.
  final void Function(Address who, Uint8List sAB, CardAddress? neighbour)
      onPair;

  /// The receipt (4) from [who] is there — the edge "new contact" on the
  /// inviting side.
  final void Function(Address who) onContactStands;

  /// The own fixed neighbour, or `null`.
  final CardAddress? Function() ownNeighbour;

  /// The route under a code.
  final CodeSend underCodeSend;

  PairHook({
    required this.knownRandom,
    required this.onPair,
    required this.onContactStands,
    required this.ownNeighbour,
    required this.underCodeSend,
  });
}

/// Per identity (its [PostBox]) the hook of its mailbox.
final Expando<PairHook> pairHook = Expando('pairHook');

/// The request payload after the code.
typedef RequestExtra = ({
  Uint8List answerCode,
  CardAddress? neighbour,
  Introduction? self,
});

/// Builds the payload of the request (2).
Uint8List requestContentBuild(Uint8List code, Uint8List answerCode,
    CardAddress? neighbour, Introduction? self) {
  if (answerCode.length != kCodeLength) {
    throw ArgumentError('Answer code must have $kCodeLength B');
  }
  final b = BytesBuilder()
    ..add(code)
    ..add(answerCode);
  optionalAddressWrite(b, neighbour);
  return introductionAppend(b.toBytes(), self);
}

/// Reads what stands behind the code of the request. Throws
/// [IntroductionError] on every form error — the request is then
/// rejected like one with a greeting that is too long.
RequestExtra requestExtraRead(Uint8List content, int from) {
  final l = Reader(Uint8List.sublistView(content, from));
  var consumed = 0;
  Uint8List read(int n) {
    consumed += n;
    return l.bytes(n);
  }

  try {
    final answerCode = read(kCodeLength);
    final neighbour = optionalAddressRead(read, 'neighbour of the request');
    return (
      answerCode: answerCode,
      neighbour: neighbour,
      self: introductionRead(content, from + consumed),
    );
  } on MemoryError catch (e) {
    throw IntroductionError('Request without answer code/neighbour: ${e.reason}');
  } on CardFormatError catch (e) {
    throw IntroductionError('neighbour of the request: $e');
  }
}

/// Builds the payload of an acceptance (3).
Uint8List acceptanceContentBuild(Uint8List sAB, Introduction? self) {
  if (sAB.length != kPairRandomLength) {
    throw ArgumentError('s_AB must have $kPairRandomLength B');
  }
  return introductionAppend(
      (BytesBuilder()
            ..addByte(1)
            ..add(sAB))
          .toBytes(),
      self);
}

/// Reads an acceptance (3): `s_AB` and the introduction. Throws
/// [IntroductionError] if `s_AB` is missing — an acceptance without it is
/// none (proposal M, D2 = a).
({Uint8List sAB, Introduction? self}) acceptanceContentRead(Uint8List content) {
  if (content.isEmpty || content[0] != 1) {
    throw IntroductionError('no acceptance');
  }
  if (content.length < 1 + kPairRandomLength) {
    throw IntroductionError('Acceptance without pair secret '
        '(${content.length - 1} B instead of $kPairRandomLength)');
  }
  return (
    sAB: Uint8List.fromList(
        Uint8List.sublistView(content, 1, 1 + kPairRandomLength)),
    self: introductionRead(content, 1 + kPairRandomLength),
  );
}
