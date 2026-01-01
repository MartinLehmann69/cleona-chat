/// Layout of the packets on call port 41341 — build and read.
///
/// ── WHY THIS IS A SEPARATE FILE ──────────────────────────────────────
///
/// `neighbours.dart` stood at 364 of 400 lines when S385 added the search call
/// (call D). The budget has no exception mechanism. The cut
/// lies here because it carries: in THIS file stands what a packet
/// looks like; over there, who sends it when and what a find means.
///
/// The code bytes do NOT stand here but over there — they belong to the
/// call port's own number space, and `scripts/check-mycelium-rules.sh`
/// (rule 4) exempts exactly `neighbours.dart` from it. This file gets the
/// code as a value and assigns none.
///
/// Layout of neighbour call and answer:
///
/// ```
/// | 0      | 1..2                  | 3..                   |
/// | code   | data port, u16 little | identifier, characters |
/// ```
///
/// Search call and find carry a fixed field between data port and identifier
/// ([callPacketWithField], S388, proposal C): the search call 16 B random, the find
/// 64 B Ed25519 signature of the SOUGHT identity over [findData]. Without a
/// signature anyone in the segment could set a route.
///
/// What "identifier" means depends on the kind: in the neighbour call and its
/// answer the node identifier (drawn randomly per start, without reference to an
/// identity), in the search call and in the find the SOUGHT identity identifier.
///
/// Byte order: little endian, like the port in the 0x23 packet of the outside route
/// (`outside_route.dart`). A second order for the same thing in the same
/// tree would be a source of errors without any benefit.
///
/// ── WHY THE DATA PORT STANDS IN THE PACKET (S384) ────────────────────────────
///
/// Until S384 the packet carried only code byte and identifier, and the find was reported with
/// `d.port` — the sender port of the answer packet. That is always
/// 41341, because answering happens via the listener on the call port. Every
/// neighbour found via the call was thus remembered under an address
/// under which it accepts nothing; `node.dart` uses this list at
/// four places (post box deposit, forwarding, cover stream, fallback in
/// `Dienst.wegZu`), and the whole source "call in the segment" was thus dead.
/// It went unnoticed because every field probe took the address from the
/// invitation card.
library;

import 'dart:io' show InternetAddress;
import 'dart:math' show Random;
import 'dart:typed_data';

/// Code byte + data port (u16). After that comes the identifier up to the end.
const int _headerLength = 1 + 2;

/// The identifier has EXACTLY one length per kind and only characters [0-9a-f]
/// (BF-1, S388; V4.2 §11.6 "A packet that cannot be parsed is discarded
/// without an answer"). Until S388 "header plus at least one character" applied —
/// a foreign call with an identifier of one character reached
/// `node_call.dart`, which shortened it to 8 characters for the message, and
/// ended every mycelium process in the segment with a RangeError.
///
/// Neighbour call and answer: node identifier, 16 B as hex (`node_call.dart`).
const int kNodeIdentifierChars = 32;

/// Search call and find: identity identifier, 32 B as hex (`hexFrom`).
const int kIdentityIdentifierChars = 64;

/// Whether from [from] only characters [0-9a-f] stand — exactly what `hexFrom` writes.
bool _onlyHex(List<int> b, int from) {
  for (var i = from; i < b.length; i++) {
    final c = b[i];
    if (!((c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x66))) return false;
  }
  return true;
}

/// Throws if [k] is no node identifier — for the OWN value on
/// opening: an identifier that every reader discards would make the node silently
/// unfindable, and quietly being able to do less without saying so does not count.
void nodeIdCheck(String k) {
  if (k.length != kNodeIdentifierChars || !_onlyHex(k.codeUnits, 0)) {
    throw ArgumentError('Node identifier must have exactly $kNodeIdentifierChars '
        'characters [0-9a-f], had ${k.length} characters — every reader '
        'discards it otherwise (BF-1)');
  }
}

/// Builds a packet: code byte, data port, identifier. See [callPacketRead].
Uint8List callPacket(int code, int dataPort, String identifier) {
  final k = identifier.codeUnits;
  final p = Uint8List(_headerLength + k.length);
  p[0] = code;
  ByteData.sublistView(p).setUint16(1, dataPort, Endian.little);
  p.setRange(_headerLength, p.length, k);
  return p;
}

/// Takes a packet apart: `(identifier, data port)`, or `null` if
/// it does not fit.
///
/// Discarded on a wrong kind, on a length other than header plus
/// [kNodeIdentifierChars], on a character outside [0-9a-f] and on
/// data port 0. **Nothing is guessed** — a packet without a port field does not
/// exist, mycelium has not shipped, so there can be no legacy data.
(String, int)? callPacketRead(List<int> data, int expectedCode) {
  if (data.length != _headerLength + kNodeIdentifierChars) return null;
  if (data[0] != expectedCode) return null;
  final b = Uint8List.fromList(data);
  final dataPort = ByteData.sublistView(b).getUint16(1, Endian.little);
  if (dataPort == 0) return null; // nobody accepts anything under port 0
  if (!_onlyHex(b, _headerLength)) return null;
  return (String.fromCharCodes(b.skip(_headerLength)), dataPort);
}

/// Signs [data] as the identity [identifier] — `null` if this node
/// does not hold it (then no answer is given).
typedef Sign = Uint8List? Function(String identifier, Uint8List data);

/// A find for a running search: [data] is what the sought identity
/// must have signed ([findData]), [signature] what stood in the packet.
/// `true` only if the recipient ACCEPTED it after checking.
typedef OnFind = bool Function(String identifier, InternetAddress address,
    int port, Uint8List data, Uint8List signature);

/// Random value in the search call and signature in the find (proposal C).
const int kSuchRandomLength = 16;
const int kFindSignatureLength = 64;

/// A fresh random value for ONE search series — from the secure generator:
/// a guessable random value would let a find be signed in advance.
Uint8List suchRandom() => Uint8List.fromList(
    List<int>.generate(kSuchRandomLength, (_) => _dice.nextInt(256)));
final Random _dice = Random.secure();

/// Code, data port, [field], identifier — the layout of search call and find.
Uint8List callPacketWithField(
    int code, int dataPort, Uint8List field, String identifier) {
  final k = identifier.codeUnits;
  final p = Uint8List(_headerLength + field.length + k.length);
  p[0] = code;
  ByteData.sublistView(p).setUint16(1, dataPort, Endian.little);
  p.setRange(_headerLength, _headerLength + field.length, field);
  p.setRange(_headerLength + field.length, p.length, k);
  return p;
}

/// Reads [callPacketWithField]; `null` on a wrong kind, a length other
/// than header plus field plus [kIdentityIdentifierChars], a character
/// outside [0-9a-f] or data port 0. A packet in the layout without a field is
/// thus broken for these kinds, not "old".
({String identifier, int dataPort, Uint8List field})? callPacketWithFieldRead(
    List<int> data, int expectedCode, int fieldLength) {
  if (data.length != _headerLength + fieldLength + kIdentityIdentifierChars) {
    return null;
  }
  if (data[0] != expectedCode) return null;
  final b = Uint8List.fromList(data);
  final dataPort = ByteData.sublistView(b).getUint16(1, Endian.little);
  if (dataPort == 0) return null;
  final end = _headerLength + fieldLength;
  if (!_onlyHex(b, end)) return null;
  return (
    identifier: String.fromCharCodes(b.skip(end)),
    dataPort: dataPort,
    field: Uint8List.fromList(b.sublist(_headerLength, end)),
  );
}

/// What the sought identity signs: domain, the random value of THIS
/// search call, the identifier (as in the packet) and the data port of the find. The
/// domain separates the signature from every other Ed25519 signature
/// of the same identity (proof, deletion receipt). The IP address does
/// NOT stand in it: how the searcher sees the holder, the holder does not know.
Uint8List findData(Uint8List random, String identifier, int dataPort) =>
    (BytesBuilder()
          ..add(_findDomain)
          ..add(random)
          ..add(identifier.codeUnits)
          ..add([dataPort & 0xFF, dataPort >> 8]))
        .toBytes();

final Uint8List _findDomain = Uint8List.fromList('mycelium-find-1'.codeUnits);
