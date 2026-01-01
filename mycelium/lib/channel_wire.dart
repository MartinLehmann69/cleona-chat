/// The packets `0x60`–`0x68` of a group or channel on the shared key (V4.2
/// §11.5, §16.2.5) — build and read, nothing else.
///
/// ```
/// 0x60 hold      request 8 | value 16 | collect pk 32 | generation pk 32
///                | author pk 32 | certificate 64 | signature 64
///                | proof flag 1 | [proof of work 16] | entry
/// 0x61 held      request 8 | verdict 1
/// 0x62 question  request 8 | state root 32 | generation pk 32 | n 1
///                | n × (value 16 | collect pk 32 | signature 64)
/// 0x63 same      request 8
/// 0x64 list      request 8 | part u16 | parts u16 | n 1 | n × (hash 16 | kind 1)
/// 0x65 fetch     request 8 | n 1 | n × hash 16
/// 0x66 entry     request 8 | value 16 | entry
/// 0x67 end       request 8 | handed out u16 | nothing here 1
/// 0x68 nudge     code 16 | wrap 16 | AES-256-GCM(entry)
/// ```
///
/// The signature on a hold is the author key's over the value, the entry and
/// the keeper's address; on a question each collect key's over the request,
/// the state root, its value and the keeper's address — a packet meant for
/// one keeper proves nothing at another.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mycelium/card_address.dart';
import 'package:mycelium/channel_chain.dart';
import 'package:mycelium/kinds.dart' as kinds;

const int kChannelRequestLength = 8;
const int kChannelProofLength = 16;

/// Hashes per `0x65`: one part of the splitter (1158 B) holds 70.
const int kHashesPerPacket = 70;

/// Listed entries per `0x64` (hash and kind, 17 B each).
const int kListedPerPacket = 67;

/// Values per question: today and the seven before (§16.2.5 step 4) fit one
/// part (8 × 112 B + 82 B).
const int kValuesPerQuestion = 8;

/// The verdicts of a `0x61`.
enum HeldVerdict {
  held, // 0 — kept, or kept already
  full, // 1 — 100 per author key or 1,000 per value reached
  invalid, // 2 — value, certificate or signature does not hold
  noKeeper, // 3 — this node does not keep (phone, no evidence, no room)
  proofWanted, // 4 — the first deposit under this value needs its proof
}

final Uint8List _kHoldDomain = utf8.encode('cleona-channel-hold/v1');
final Uint8List _kQuestionDomain = utf8.encode('cleona-channel-question/v1');

Uint8List _addressBytes(CardAddress a) {
  final b = BytesBuilder()..addByte(a.kind.index)..add(a.address);
  b.add([a.port >> 8, a.port & 0xFF]);
  return b.toBytes();
}

/// What the author key signs on a hold to [keeper].
Uint8List holdSigned(Uint8List value, Uint8List entry, CardAddress keeper) =>
    Uint8List.fromList(
        [..._kHoldDomain, ...value, ...entry, ..._addressBytes(keeper)]);

/// What a collect key signs in a question to [keeper].
Uint8List questionSigned(Uint8List request, Uint8List root, Uint8List value,
        CardAddress keeper) =>
    Uint8List.fromList([
      ..._kQuestionDomain, ...request, ...root, ...value,
      ..._addressBytes(keeper)
    ]);

/// A parsed `0x60`.
typedef Hold = ({
  Uint8List request,
  Uint8List value,
  Uint8List collectPk,
  Uint8List generationPk,
  Uint8List authorPk,
  Uint8List certificate,
  Uint8List signature,
  Uint8List? proof,
  Uint8List entry,
});

/// A parsed `0x62`: one item per asked value.
typedef Question = ({
  Uint8List request,
  Uint8List root,
  Uint8List generationPk,
  List<({Uint8List value, Uint8List collectPk, Uint8List signature})> items,
});

class _Reader {
  final Uint8List b;
  int i;
  _Reader(this.b) : i = 1;
  Uint8List take(int n) {
    if (i + n > b.length) throw const FormatException('short');
    final out = Uint8List.fromList(b.sublist(i, i + n));
    i += n;
    return out;
  }

  int byte() => take(1)[0];
  int u16() {
    final x = take(2);
    return (x[0] << 8) | x[1];
  }

  Uint8List rest() => take(b.length - i);
}

Uint8List hold(Hold h) {
  final b = BytesBuilder()
    ..addByte(kinds.kChannelHold)
    ..add(h.request)
    ..add(h.value)
    ..add(h.collectPk)
    ..add(h.generationPk)
    ..add(h.authorPk)
    ..add(h.certificate)
    ..add(h.signature)
    ..addByte(h.proof == null ? 0 : 1);
  if (h.proof != null) b.add(h.proof!);
  b.add(h.entry);
  return b.toBytes();
}

Hold? holdRead(Uint8List p) {
  if (p.isEmpty || p[0] != kinds.kChannelHold) return null;
  try {
    final r = _Reader(p);
    final request = r.take(kChannelRequestLength);
    final value = r.take(kChannelValueLength);
    final collectPk = r.take(kSignPkLength);
    final generationPk = r.take(kSignPkLength);
    final authorPk = r.take(kSignPkLength);
    final certificate = r.take(kSignatureLength);
    final signature = r.take(kSignatureLength);
    final withProof = r.byte() == 1;
    final proof = withProof ? r.take(kChannelProofLength) : null;
    final entry = r.rest();
    if (entry.isEmpty) return null;
    return (
      request: request, value: value, collectPk: collectPk,
      generationPk: generationPk, authorPk: authorPk,
      certificate: certificate, signature: signature, proof: proof,
      entry: entry,
    );
  } on FormatException {
    return null;
  }
}

Uint8List held(Uint8List request, HeldVerdict v) =>
    Uint8List.fromList([kinds.kChannelHeld, ...request, v.index]);

({Uint8List request, HeldVerdict verdict})? heldRead(Uint8List p) {
  if (p.length != 1 + kChannelRequestLength + 1 || p[0] != kinds.kChannelHeld) {
    return null;
  }
  final v = p.last;
  if (v >= HeldVerdict.values.length) return null;
  return (
    request: Uint8List.fromList(p.sublist(1, 1 + kChannelRequestLength)),
    verdict: HeldVerdict.values[v],
  );
}

Uint8List question(Question q) {
  final b = BytesBuilder()
    ..addByte(kinds.kChannelQuestion)
    ..add(q.request)
    ..add(q.root)
    ..add(q.generationPk)
    ..addByte(q.items.length);
  for (final it in q.items) {
    b
      ..add(it.value)
      ..add(it.collectPk)
      ..add(it.signature);
  }
  return b.toBytes();
}

Question? questionRead(Uint8List p) {
  if (p.isEmpty || p[0] != kinds.kChannelQuestion) return null;
  try {
    final r = _Reader(p);
    final request = r.take(kChannelRequestLength);
    final root = r.take(32);
    final generationPk = r.take(kSignPkLength);
    final n = r.byte();
    if (n == 0 || n > kValuesPerQuestion) return null;
    final items = [
      for (var k = 0; k < n; k++)
        (
          value: r.take(kChannelValueLength),
          collectPk: r.take(kSignPkLength),
          signature: r.take(kSignatureLength),
        )
    ];
    if (r.i != p.length) return null;
    return (
      request: request, root: root, generationPk: generationPk, items: items
    );
  } on FormatException {
    return null;
  }
}

Uint8List same(Uint8List request) =>
    Uint8List.fromList([kinds.kChannelSame, ...request]);

/// One listed entry: its hash and the kind byte of its header (post or
/// inline object, `channel_entry.dart`) — so that a member fetches an inline
/// image only as "always load images" allows (§9.4) without fetching it to
/// learn what it is.
typedef Listed = ({Uint8List hash, int kind});

Uint8List listPacket(
    Uint8List request, int part, int parts, List<Listed> items) {
  final b = BytesBuilder()
    ..addByte(kinds.kChannelList)
    ..add(request)
    ..add([part >> 8, part & 0xFF, parts >> 8, parts & 0xFF])
    ..addByte(items.length);
  for (final it in items) {
    b
      ..add(it.hash)
      ..addByte(it.kind);
  }
  return b.toBytes();
}

({Uint8List request, int part, int parts, List<Listed> items})? listRead(
    Uint8List p) {
  if (p.isEmpty || p[0] != kinds.kChannelList) return null;
  try {
    final r = _Reader(p);
    final request = r.take(kChannelRequestLength);
    final part = r.u16(), parts = r.u16();
    final n = r.byte();
    if (n > kListedPerPacket) return null;
    final items = [
      for (var k = 0; k < n; k++) (hash: r.take(kEntryHashLength), kind: r.byte())
    ];
    if (r.i != p.length || part >= parts) return null;
    return (request: request, part: part, parts: parts, items: items);
  } on FormatException {
    return null;
  }
}

Uint8List fetch(Uint8List request, List<Uint8List> hashes) {
  final b = BytesBuilder()
    ..addByte(kinds.kChannelFetch)
    ..add(request)
    ..addByte(hashes.length);
  for (final h in hashes) {
    b.add(h);
  }
  return b.toBytes();
}

({Uint8List request, List<Uint8List> hashes})? fetchRead(Uint8List p) {
  if (p.isEmpty || p[0] != kinds.kChannelFetch) return null;
  try {
    final r = _Reader(p);
    final request = r.take(kChannelRequestLength);
    final n = r.byte();
    if (n == 0 || n > kHashesPerPacket) return null;
    final hashes = [for (var k = 0; k < n; k++) r.take(kEntryHashLength)];
    if (r.i != p.length) return null;
    return (request: request, hashes: hashes);
  } on FormatException {
    return null;
  }
}

Uint8List entryPacket(Uint8List request, Uint8List value, Uint8List entry) =>
    Uint8List.fromList([kinds.kChannelEntry, ...request, ...value, ...entry]);

({Uint8List request, Uint8List value, Uint8List entry})? entryRead(
    Uint8List p) {
  if (p.length <= 1 + kChannelRequestLength + kChannelValueLength ||
      p[0] != kinds.kChannelEntry) {
    return null;
  }
  const v = 1 + kChannelRequestLength;
  return (
    request: Uint8List.fromList(p.sublist(1, v)),
    value: Uint8List.fromList(p.sublist(v, v + kChannelValueLength)),
    entry: Uint8List.fromList(p.sublist(v + kChannelValueLength)),
  );
}

Uint8List end(Uint8List request, int handedOut, {bool nothingHere = false}) =>
    Uint8List.fromList([
      kinds.kChannelEnd, ...request, handedOut >> 8, handedOut & 0xFF,
      nothingHere ? 1 : 0
    ]);

({Uint8List request, int handedOut, bool nothingHere})? endRead(Uint8List p) {
  if (p.length != 1 + kChannelRequestLength + 3 || p[0] != kinds.kChannelEnd) {
    return null;
  }
  const i = 1 + kChannelRequestLength;
  return (
    request: Uint8List.fromList(p.sublist(1, i)),
    handedOut: (p[i] << 8) | p[i + 1],
    nothingHere: p[i + 2] == 1,
  );
}

/// The request identifier every answer of a keeper names (`0x61`, `0x63`,
/// `0x64`, `0x66`, `0x67`), or `null` for another kind.
Uint8List? requestOf(Uint8List p) {
  if (p.length < 1 + kChannelRequestLength) return null;
  switch (p[0]) {
    case kinds.kChannelHeld || kinds.kChannelSame || kinds.kChannelList ||
          kinds.kChannelEntry || kinds.kChannelEnd:
      return Uint8List.fromList(p.sublist(1, 1 + kChannelRequestLength));
  }
  return null;
}
