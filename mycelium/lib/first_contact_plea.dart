/// The bundle request (0) and its way back — v4_2 §15.5 "The way back for
/// the bundle" (owner decision A, 24.09.2026, S394-7).
///
/// | Field | Bytes | |
/// |---|---|---|
/// | type | 1 | `0x01` |
/// | random value | 16 | echoed in the bundle (1) |
/// | reply code | 16 | only with a fixed neighbour |
/// | requester's fixed neighbour | 7 / 19 | type + address + port |
///
/// 17 B without, 40 B (IPv4) or 52 B (IPv6) with a way back. Until S394 the
/// request was 17 B only: the issuer could answer only the address the
/// request came from — through a neighbour (§8.1) that is the forwarder, who
/// discarded the bundle. A first contact through step 3 alone (mobile data,
/// CGNAT) never came about.
library;

import 'dart:typed_data';

import 'package:mycelium/card_address.dart';
import 'package:mycelium/bundle.dart';
import 'package:mycelium/envelope.dart' show PostBox;
import 'package:mycelium/first_contact.dart' show FirstContactError, PacketKind, Report, Send;
import 'package:mycelium/first_contact_pair.dart' show pairHook;

/// Lengths of the anonymous bundle request: bare, IPv4 and IPv6 way back.
const Set<int> kBundlePleaLengths = {17, 40, 52};

/// Appends reply code and fixed neighbour to a bundle request in [b] —
/// nothing when the requester has no fixed neighbour.
void bundlePleaWayBackWrite(
    BytesBuilder b, Uint8List replyCode, CardAddress? neighbour) {
  if (neighbour == null) return;
  if (replyCode.length != 16) {
    throw ArgumentError('reply code must have 16 B, has ${replyCode.length}');
  }
  b.add(replyCode);
  addressWrite(b, neighbour);
}

/// The bundle (1): type, the request's random value echoed, the own bundle.
Uint8List bundleAnswerBuild(Uint8List randomValue, PostBox me) =>
    (BytesBuilder()
          ..addByte(PacketKind.bundle.code)
          ..add(randomValue)
          ..add(bundleBuild(randomValue, me)))
        .toBytes();

/// Packet (1) for [me]'s invitation: hand out the own bundle. It is public —
/// nothing is given away here that is not public anyway.
/// §15.5 "The way back for the bundle": directly when the request came
/// directly; under the reply code through the named neighbour when it came
/// through one — [from] is then the forwarder's address (S394-7).
/// (Moved here from `first_contact_invitation.dart`, line budget, S411.)
void bundlePleaCame(Uint8List packet, CardAddress from, bool forwarded,
    PostBox me, Send send, Report? report) {
  final r = bundlePleaRead(packet);
  final bundle = bundleAnswerBuild(r.randomValue, me);
  final back = r.replyCode != null && r.neighbour != null;
  report?.call(!forwarded ? 'Bundle handed out directly' : back
      ? 'Bundle handed out under the reply code'
      : 'Bundle request through a neighbour without a way back — not answerable');
  if (!forwarded) send(bundle, from);
  if (forwarded && back) pairHook[me]?.underCodeSend(r.replyCode!, r.neighbour!, bundle);
}

/// Reads a bundle request (0). Throws [FirstContactError] on a length the
/// document does not name or on a broken address.
({Uint8List randomValue, Uint8List? replyCode, CardAddress? neighbour})
    bundlePleaRead(Uint8List packet) {
  if (!kBundlePleaLengths.contains(packet.length)) {
    throw FirstContactError('bundle request has ${packet.length} B, '
        'expected one of $kBundlePleaLengths');
  }
  final randomValue = Uint8List.sublistView(packet, 1, 17);
  if (packet.length == 17) {
    return (randomValue: randomValue, replyCode: null, neighbour: null);
  }
  var pos = 33;
  Uint8List read(int n) {
    if (pos + n > packet.length) {
      throw FirstContactError('bundle request ends inside the neighbour');
    }
    return Uint8List.sublistView(packet, pos, pos += n);
  }

  try {
    final neighbour = addressRead(read, 'neighbour of the bundle request');
    if (pos != packet.length) {
      throw FirstContactError('bundle request: ${packet.length - pos} B left over');
    }
    return (
      randomValue: randomValue,
      replyCode: Uint8List.sublistView(packet, 17, 33),
      neighbour: neighbour,
    );
  } on CardFormatError catch (e) {
    throw FirstContactError('bundle request: $e');
  }
}
