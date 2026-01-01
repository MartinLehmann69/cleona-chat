/// The packets of the durable-object class, `0x90`–`0x98` (v4_2 §11.5,
/// §16.0, §16.7) — build and read, nothing else. S407 SK-1.
///
/// | Kind | Layout | Length |
/// |---|---|---|
/// | 0x90 deposit | kind, channel 1, proof of work 16, signed object | 18 + object |
/// | 0x91 deposited | kind, channel 1, hash 16 | 18 B |
/// | 0x92 fetch | kind, identifier 20 [, blocks received u16] | 21 / 23 B |
/// | 0x93 piece | kind, fountain block 1041 | 1042 B |
/// | 0x94 not held | kind, identifier 20 | 21 B |
/// | 0x95 stock ask | kind, channel 1, T hours u16, state root 32 | 36 B |
/// | 0x96 stock answer | kind, channel 1, 0 "same" / 1 list, blocks of the §5.5 codec | 3 B / 3 + list |
/// | 0x97 fingerprint ask | kind, channel 1, random 8, fingerprint | 10 + fingerprint |
/// | 0x98 fingerprint answer | kind, channel 1, random 8, head or nothing | 10 B / 10 + head |
///
/// The "fountain state" of `0x92` (§11.5) is the number of blocks the
/// fetching node already took in; the holder sizes its answer from it and
/// from the object's length (`durable_serve.dart`). An answer is never
/// larger than what the object needs plus a margin — and every packet goes
/// through the shell, whose handshake a forged sender address cannot
/// complete, so a `0x92` cannot be turned against a third address.
library;

import 'dart:typed_data';

import 'package:cleona/core/fountain/fountain_block.dart';
import 'package:mycelium/durable_id.dart';
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/post_box_proof_of_work.dart' show kProofOfWorkLength;

/// The largest object the class carries: 64 KB (a report is ≈ 10 KB,
/// §5.6). Larger is refused before it is offered to the application.
const int kDurableObjectAtMost = 64 * 1024;

/// Length of the state root in `0x95`.
const int kStateRootBytes = 32;

/// T in `0x95` meaning "from the beginning" (a node that holds nothing).
const int kSinceBeginning = 0xFFFF;

/// Length of the random value that pairs `0x97` and `0x98`.
const int kAskRandomBytes = 8;

/// The largest fingerprint `0x97` carries.
const int kFingerprintAtMost = 256;

Uint8List _join(List<Object> parts) {
  final b = BytesBuilder(copy: false);
  for (final p in parts) {
    p is int ? b.addByte(p) : b.add(p as List<int>);
  }
  return b.takeBytes();
}

/// `0x90` — [proof] is the 16 B of `durable_proof.dart`.
Uint8List depositPacket(int channel, Uint8List proof, Uint8List object) {
  if (proof.length != kProofOfWorkLength) {
    throw ArgumentError('proof must be $kProofOfWorkLength B');
  }
  return _join([kinds.kDurableDeposit, channel, proof, object]);
}

({int channel, Uint8List proof, Uint8List object})? depositRead(Uint8List p) {
  const head = 2 + kProofOfWorkLength;
  if (p.length <= head || p[0] != kinds.kDurableDeposit) return null;
  if (p.length - head > kDurableObjectAtMost) return null;
  return (
    channel: p[1],
    proof: Uint8List.fromList(p.sublist(2, head)),
    object: Uint8List.fromList(p.sublist(head)),
  );
}

Uint8List depositedPacket(int channel, Uint8List hash) =>
    _join([kinds.kDurableDeposited, channel, hash]);

({int channel, Uint8List hash})? depositedRead(Uint8List p) {
  if (p.length != 2 + kIdentifierHashBytes ||
      p[0] != kinds.kDurableDeposited) {
    return null;
  }
  return (channel: p[1], hash: Uint8List.fromList(p.sublist(2)));
}

Uint8List fetchPacket(DurableId id, {int? received}) {
  final r = received?.clamp(0, 0xFFFF);
  return _join([
    kinds.kDurableFetch,
    id.toBytes(),
    if (r != null) ...[r >> 8, r & 0xFF],
  ]);
}

({DurableId id, int? received})? fetchRead(Uint8List p) {
  if (p[0] != kinds.kDurableFetch) return null;
  if (p.length != 1 + kIdentifierBytes && p.length != 3 + kIdentifierBytes) {
    return null;
  }
  return (
    id: DurableId.read(p, 1),
    received: p.length == 3 + kIdentifierBytes
        ? (p[1 + kIdentifierBytes] << 8) | p[2 + kIdentifierBytes]
        : null,
  );
}

Uint8List durablePiecePacket(FountainBlock block) =>
    _join([kinds.kDurablePiece, block.toBytes()]);

FountainBlock? durablePieceRead(Uint8List p) =>
    p.length == 1 + kFountainBlockBytes && p[0] == kinds.kDurablePiece
        ? FountainBlock.fromBytes(p, 1)
        : null;

Uint8List notHeldPacket(DurableId id) =>
    _join([kinds.kDurableNotHeld, id.toBytes()]);

DurableId? notHeldRead(Uint8List p) =>
    p.length == 1 + kIdentifierBytes && p[0] == kinds.kDurableNotHeld
        ? DurableId.read(p, 1)
        : null;

Uint8List stockAskPacket(int channel, int sinceHours, Uint8List root) {
  if (root.length != kStateRootBytes) {
    throw ArgumentError('state root must be $kStateRootBytes B');
  }
  final t = sinceHours.clamp(0, kSinceBeginning);
  return _join([kinds.kDurableStockAsk, channel, t >> 8, t & 0xFF, root]);
}

({int channel, int sinceHours, Uint8List root})? stockAskRead(Uint8List p) {
  if (p.length != 4 + kStateRootBytes || p[0] != kinds.kDurableStockAsk) {
    return null;
  }
  return (
    channel: p[1],
    sinceHours: (p[2] << 8) | p[3],
    root: Uint8List.fromList(p.sublist(4)),
  );
}

/// `0x96` — [ids] `null`: "same".
Uint8List stockAnswerPacket(int channel, List<DurableId>? ids) => _join([
      kinds.kDurableStockAnswer,
      channel,
      ids == null ? 0 : 1,
      if (ids != null) identifierBlocksWrite(ids),
    ]);

/// [same] true: the roots agreed. Malformed: `null`.
({int channel, bool same, List<DurableId> ids})? stockAnswerRead(Uint8List p) {
  if (p.length < 3 || p[0] != kinds.kDurableStockAnswer) return null;
  if (p[2] == 0) return (channel: p[1], same: true, ids: const []);
  if (p[2] != 1) return null;
  final ids = identifierBlocksRead(p, 3);
  return ids == null ? null : (channel: p[1], same: false, ids: ids);
}

Uint8List fingerprintAskPacket(
        int channel, Uint8List random, Uint8List fingerprint) =>
    _join([kinds.kDurableFingerprintAsk, channel, random, fingerprint]);

({int channel, Uint8List random, Uint8List fingerprint})? fingerprintAskRead(
    Uint8List p) {
  const head = 2 + kAskRandomBytes;
  if (p.length <= head || p.length > head + kFingerprintAtMost) return null;
  if (p[0] != kinds.kDurableFingerprintAsk) return null;
  return (
    channel: p[1],
    random: Uint8List.fromList(p.sublist(2, head)),
    fingerprint: Uint8List.fromList(p.sublist(head)),
  );
}

/// `0x98` — [head] `null`: "unknown".
Uint8List fingerprintAnswerPacket(
        int channel, Uint8List random, Uint8List? head) =>
    _join([
      kinds.kDurableFingerprintAnswer,
      channel,
      random,
      if (head != null) head,
    ]);

({int channel, Uint8List random, Uint8List? head})? fingerprintAnswerRead(
    Uint8List p) {
  const head = 2 + kAskRandomBytes;
  if (p.length < head || p[0] != kinds.kDurableFingerprintAnswer) return null;
  if (p.length - head > kDurableObjectAtMost) return null;
  return (
    channel: p[1],
    random: Uint8List.fromList(p.sublist(2, head)),
    head: p.length == head ? null : Uint8List.fromList(p.sublist(head)),
  );
}
