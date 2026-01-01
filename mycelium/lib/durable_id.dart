/// The identifier of a durable object and its codec (v4_2 §16.0, §5.5
/// content byte `0x05`, §11.5 answer `0x96`). S407 SK-1.
///
/// ── WHAT AN IDENTIFIER IS ─────────────────────────────────────────────────
///
/// 20 B: channel (1), age in hours (2, big endian), kind and size class (1),
/// the first 16 B of the SHA-256 of the signed object. It means "I hold
/// this object and hand it out" (§16.0) — only a holder names one.
///
/// The transport reads only the channel, the age and the hash. Kind and
/// size class are the application's byte (SK-2); the transport carries it
/// unchanged. Two identifiers are the SAME object when channel and hash
/// agree — the age changes with every hour and is not part of the identity.
///
/// ── THE CODEC (§5.5) ──────────────────────────────────────────────────────
///
/// count (1) | count × 20 B. In a cover packet at most [kIdentifiersPerCover]:
/// the cover content begins behind the 12 B header (`cover_stream_content.dart`),
/// so 1158 B remain, and 1 + 57 × 20 = 1141 B fit — 58 would need 1161 B
/// (finding in `mycelium/berichte/S407-SK1.md`: §5.5 says "at most 58").
/// The list answer `0x96` strings blocks of this codec one after the other,
/// each with at most [kIdentifiersPerBlock].
library;

import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';

/// Length of one identifier on the wire.
const int kIdentifierBytes = 20;

/// Length of the hash part.
const int kIdentifierHashBytes = 16;

/// At most so many identifiers ride in one cover packet (see header).
const int kIdentifiersPerCover = 57;

/// At most so many identifiers in one block of the codec (count is 1 B).
const int kIdentifiersPerBlock = 255;

/// Identifiers younger than this ride in the cover stream (§5.5 rule 2).
const int kCoverAgeHours = 24;

/// The two system channels (§16.7; build plan S407).
const int kChannelBugLog = 1;
const int kChannelFeatureRequests = 2;

class DurableId {
  final int channel;

  /// Age in hours as the naming node stated it when it named the object.
  final int ageHours;

  /// Kind and size class — the application's byte, carried unchanged.
  final int kindSize;
  final Uint8List hash;

  DurableId(this.channel, this.ageHours, this.kindSize, Uint8List hash)
      : hash = Uint8List.fromList(hash) {
    if (hash.length != kIdentifierHashBytes) {
      throw ArgumentError('hash must be $kIdentifierHashBytes B');
    }
    if (channel < 0 || channel > 0xFF || kindSize < 0 || kindSize > 0xFF) {
      throw ArgumentError('channel and kind are one byte each');
    }
  }

  /// The identifier of [object] in [channel]: the hash is computed here,
  /// age and kind are the caller's.
  factory DurableId.of(int channel, Uint8List object,
          {int ageHours = 0, int kindSize = 0}) =>
      DurableId(channel, ageHours.clamp(0, 0xFFFF), kindSize,
          objectHash(object));

  /// Reads 20 B at [offset].
  factory DurableId.read(Uint8List b, [int offset = 0]) {
    if (b.length < offset + kIdentifierBytes) {
      throw const FormatException('identifier too short');
    }
    return DurableId(
        b[offset],
        (b[offset + 1] << 8) | b[offset + 2],
        b[offset + 3],
        Uint8List.sublistView(b, offset + 4, offset + kIdentifierBytes));
  }

  Uint8List toBytes() {
    final a = ageHours.clamp(0, 0xFFFF);
    return Uint8List(kIdentifierBytes)
      ..[0] = channel
      ..[1] = a >> 8
      ..[2] = a & 0xFF
      ..[3] = kindSize
      ..setRange(4, kIdentifierBytes, hash);
  }

  /// The same identifier, older by [hours] — what a node states when it
  /// names an object it heard [hours] ago.
  DurableId olderBy(int hours) =>
      DurableId(channel, (ageHours + hours).clamp(0, 0xFFFF), kindSize, hash);

  /// Channel and hash — what makes two identifiers the same object.
  String get key =>
      '$channel:${hash.map((x) => x.toRadixString(16).padLeft(2, '0')).join()}';

  @override
  bool operator ==(Object other) => other is DurableId && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'DurableId(${key.substring(0, 10)}…, ${ageHours}h)';
}

/// The first 16 B of SHA-256 of [object].
Uint8List objectHash(Uint8List object) => Uint8List.fromList(
    SodiumFFI().sha256(object).sublist(0, kIdentifierHashBytes));

/// Writes one block of the codec: count | identifiers. At most
/// [kIdentifiersPerBlock]; more is a programming error of the caller.
void identifiersWrite(BytesBuilder b, List<DurableId> ids) {
  if (ids.length > kIdentifiersPerBlock) {
    throw ArgumentError('${ids.length} identifiers, at most $kIdentifiersPerBlock');
  }
  b.addByte(ids.length);
  for (final i in ids) {
    b.add(i.toBytes());
  }
}

/// Reads one block of the codec through [read] (throws on short input —
/// the caller catches, as with the address entries).
List<DurableId> identifiersRead(Uint8List Function(int n) read) {
  final n = read(1)[0];
  return [
    for (var i = 0; i < n; i++) DurableId.read(read(kIdentifierBytes)),
  ];
}

/// Strings blocks of the codec one after the other — the list of `0x96`.
Uint8List identifierBlocksWrite(List<DurableId> ids) {
  final b = BytesBuilder(copy: false);
  for (var i = 0; i < ids.length; i += kIdentifiersPerBlock) {
    final end = i + kIdentifiersPerBlock < ids.length
        ? i + kIdentifiersPerBlock
        : ids.length;
    identifiersWrite(b, ids.sublist(i, end));
  }
  return b.takeBytes();
}

/// Reads blocks up to the end of [p] from [offset]; `null` if malformed.
List<DurableId>? identifierBlocksRead(Uint8List p, int offset) {
  var pos = offset;
  Uint8List read(int n) {
    if (pos + n > p.length) throw const FormatException('short');
    final r = Uint8List.sublistView(p, pos, pos + n);
    pos += n;
    return r;
  }

  final out = <DurableId>[];
  try {
    while (pos < p.length) {
      out.addAll(identifiersRead(read));
    }
  } on Object {
    return null;
  }
  return out;
}
