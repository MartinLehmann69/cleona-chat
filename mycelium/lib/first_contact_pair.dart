/// What first contact additionally carries since proposal M (S391, §4.3,
/// §8.1, §15.2 of the proposal; owner approval 17.09.2026, D2 = a).
///
/// ── THE TWO PAYLOADS ─────────────────────────────────────────────────
///
/// ```
/// Request (2), in the seal:     code | answer code 16 B | neighbour (flag + address)
///                               | 31 day keys × 32 B | introduction (optional)
/// Acceptance (3), in the seal:  0x01 | s_AB 32 B | 31 day keys × 32 B
///                               | fixed neighbours (count + ≤ 3 addresses, §9.2)
///                               | introduction (optional)
/// Rejection (3):                0x00
/// ```
///
/// **Day keys** (proposal E, owner approval 28.09.2026): the sender's 31
/// public day keys (§8.2) — they are the edge "new contact", so a first
/// contact needs no day-key message of its own. The first of them belongs to
/// the UTC day of the request's time window (visible in its header, §15.5.1)
/// on BOTH packets: the answer names no time, and the requester knows its own
/// request. Without them the post box would be circular — the answer to a
/// request collected from a post box has no other way to its sender.
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
import 'package:mycelium/neighbour_list.dart';
import 'package:mycelium/pair.dart'
    show kCodeLength, kPairRandomLength, kDayKeyDays, deriveDayKey;
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

  /// The accepting side has accepted [who]: `s_AB`, its neighbour and the
  /// day keys its request carried (proposal E).
  final void Function(Address who, Uint8List sAB, CardAddress? neighbour,
      Map<int, Uint8List> dayKeys) onPair;

  /// The receipt (4) from [who] is there — the edge "new contact" on the
  /// inviting side.
  final void Function(Address who) onContactStands;

  /// The own fixed neighbour, or `null`.
  final CardAddress? Function() ownNeighbour;

  /// The route under a code.
  final CodeSend underCodeSend;

  /// The fixed neighbours this identity names to a contact (§9.2) — they
  /// ride in the acceptance (3). Without it: none.
  final List<CardAddress> Function()? namedNeighbours;

  /// Leaves [packet] in the post box under [value], with the holders [named]
  /// first (§8.2) — for an answer to a request collected from a post box
  /// that has no contact behind it (the rejection, proposal E).
  final void Function(Uint8List packet, Uint8List value, List<CardAddress> named)?
      boxSend;

  PairHook({
    required this.knownRandom,
    required this.onPair,
    required this.onContactStands,
    required this.ownNeighbour,
    required this.underCodeSend,
    this.namedNeighbours,
    this.boxSend,
  });
}

/// Per identity (its [PostBox]) the hook of its mailbox.
final Expando<PairHook> pairHook = Expando('pairHook');

/// The request payload after the code.
typedef RequestExtra = ({
  Uint8List answerCode,
  CardAddress? neighbour,
  Map<int, Uint8List> dayKeys,
  Introduction? self,
});

/// Length of the day keys in (2) and (3): [kDayKeyDays] × 32 B.
const int kDayKeysLength = kDayKeyDays * 32;

/// The public day keys of [me] from UTC day [fromDay] on, [kDayKeyDays] of them.
Uint8List dayKeysBuild(PostBox me, int fromDay) {
  final b = BytesBuilder();
  for (var d = fromDay; d < fromDay + kDayKeyDays; d++) {
    b.add(deriveDayKey(me, d).pk);
  }
  return b.toBytes();
}

/// Builds the payload of the request (2); [dayKeys] from [dayKeysBuild].
Uint8List requestContentBuild(Uint8List code, Uint8List answerCode,
    CardAddress? neighbour, Uint8List dayKeys, Introduction? self) {
  if (answerCode.length != kCodeLength || dayKeys.length != kDayKeysLength) {
    throw ArgumentError('Answer code must have $kCodeLength B, day keys '
        '$kDayKeysLength B');
  }
  final b = BytesBuilder()
    ..add(code)
    ..add(answerCode);
  optionalAddressWrite(b, neighbour);
  b.add(dayKeys);
  return introductionAppend(b.toBytes(), self);
}

Map<int, Uint8List> _dayKeysRead(Uint8List Function(int n) read, int fromDay) =>
    {for (var d = fromDay; d < fromDay + kDayKeyDays; d++) d: read(32)};

/// Reads what stands behind the code of the request. Throws
/// [IntroductionError] on every form error — the request is then
/// rejected like one with a greeting that is too long.
/// [fromDay] is the UTC day of the request's time window (header).
RequestExtra requestExtraRead(Uint8List content, int from, int fromDay) {
  final l = Reader(Uint8List.sublistView(content, from));
  var consumed = 0;
  Uint8List read(int n) {
    consumed += n;
    return l.bytes(n);
  }

  try {
    final answerCode = read(kCodeLength);
    final neighbour = optionalAddressRead(read, 'neighbour of the request');
    final dayKeys = _dayKeysRead(read, fromDay);
    return (
      answerCode: answerCode,
      neighbour: neighbour,
      dayKeys: dayKeys,
      self: introductionRead(content, from + consumed),
    );
  } on MemoryError catch (e) {
    throw IntroductionError(
        'Request without answer code/neighbour/day keys: ${e.reason}');
  } on CardFormatError catch (e) {
    throw IntroductionError('neighbour of the request: $e');
  }
}

/// Builds the payload of an acceptance (3).
Uint8List acceptanceContentBuild(Uint8List sAB, Uint8List dayKeys,
    List<CardAddress> neighbours, Introduction? self) {
  if (sAB.length != kPairRandomLength || dayKeys.length != kDayKeysLength) {
    throw ArgumentError('s_AB must have $kPairRandomLength B, day keys '
        '$kDayKeysLength B');
  }
  final b = BytesBuilder()
    ..addByte(1)
    ..add(sAB)
    ..add(dayKeys);
  neighbourListWrite(b, neighbourListClean(neighbours));
  return introductionAppend(b.toBytes(), self);
}

/// An acceptance (3) as read.
typedef Acceptance = ({
  Uint8List sAB,
  Map<int, Uint8List> dayKeys,
  List<CardAddress> neighbours,
  Introduction? self,
});

/// Reads an acceptance (3); [fromDay] as for [requestExtraRead]. Throws
/// [IntroductionError] if `s_AB` or the day keys are missing — an acceptance
/// without them is none (proposal M, D2 = a; proposal E).
Acceptance acceptanceContentRead(Uint8List content, int fromDay) {
  if (content.isEmpty || content[0] != 1) {
    throw IntroductionError('no acceptance');
  }
  final l = Reader(Uint8List.sublistView(content, 1));
  var consumed = 1;
  Uint8List read(int n) {
    consumed += n;
    return l.bytes(n);
  }

  try {
    final sAB = read(kPairRandomLength);
    final dayKeys = _dayKeysRead(read, fromDay);
    final neighbours = neighbourListRead(read, 'neighbours of the acceptance');
    return (
      sAB: sAB,
      dayKeys: dayKeys,
      neighbours: neighbours,
      self: introductionRead(content, consumed),
    );
  } on MemoryError catch (e) {
    throw IntroductionError('Acceptance without pair secret/day keys: '
        '${e.reason}');
  } on CardFormatError catch (e) {
    throw IntroductionError('neighbours of the acceptance: $e');
  }
}
