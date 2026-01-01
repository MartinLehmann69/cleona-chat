/// An entry of a group or channel on the shared key (V4.2 §16.2.5): what a
/// keeper holds, what a nudge carries, and what a member opens.
///
/// ```
/// kind 1 | generation u32 | generation id 8 | day u32 | step u32 | id 16
///        | nonce 12 | AES-256-GCM(body), the header as associated data
/// ```
///
/// Kind 1 is a post (its body the signed post of the application), kind 2
/// an inline object below 256 KB that a post names by its id (§9.4
/// "Loading images in a group or channel"). The key is
/// `HKDF(S_g(d, j), "channel/post" ‖ id)` (`channel_chain.dart`) — one key
/// per post, so a nonce never meets the same key twice. The AEAD is the one
/// of §4.3.
///
/// A keeper reads nothing of it: the header names a generation number, a
/// day and a step, never the group, the channel or an author.
library;

import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/channel_chain.dart';

final SodiumFFI _na = SodiumFFI();

const int kEntryPost = 1;
const int kEntryObject = 2;

const int _kNonceLength = 12;

/// Kind, generation, generation id, day, step, id.
const int kEntryHeadLength = 1 + 4 + kGenerationIdLength + 4 + 4 + kEntryIdLength;

/// The header of an entry, readable without a key.
class EntryHead {
  final int kind;
  final int generation;
  final Uint8List generationId;
  final int day;
  final int step;
  final Uint8List id;

  const EntryHead({
    required this.kind,
    required this.generation,
    required this.generationId,
    required this.day,
    required this.step,
    required this.id,
  });

  Uint8List toBytes() {
    final b = ByteData(kEntryHeadLength);
    var i = 0;
    b.setUint8(i++, kind);
    b.setUint32(i, generation);
    i += 4;
    final out = b.buffer.asUint8List();
    out.setRange(i, i + kGenerationIdLength, generationId);
    i += kGenerationIdLength;
    b.setUint32(i, day);
    i += 4;
    b.setUint32(i, step);
    i += 4;
    out.setRange(i, i + kEntryIdLength, id);
    return out;
  }

  /// The header of [entry], or `null` when it is too short or of an
  /// unknown kind.
  static EntryHead? of(Uint8List entry) {
    if (entry.length < kEntryHeadLength + _kNonceLength + 16) return null;
    final b = ByteData.sublistView(entry);
    final kind = b.getUint8(0);
    if (kind != kEntryPost && kind != kEntryObject) return null;
    var i = 1;
    final g = b.getUint32(i);
    i += 4;
    final gid = Uint8List.fromList(entry.sublist(i, i + kGenerationIdLength));
    i += kGenerationIdLength;
    final d = b.getUint32(i);
    i += 4;
    final j = b.getUint32(i);
    i += 4;
    return EntryHead(
        kind: kind,
        generation: g,
        generationId: gid,
        day: d,
        step: j,
        id: Uint8List.fromList(entry.sublist(i, i + kEntryIdLength)));
  }
}

/// Seals [body] under the step key [step] of the post's `(g, d, j)`.
Uint8List entrySeal(EntryHead head, Uint8List step, Uint8List body) {
  final h = head.toBytes();
  final nonce = _na.randomBytes(_kNonceLength);
  final ct = _na.aesGcmEncrypt(body, postKey(step, head.id), nonce, ad: h);
  return Uint8List.fromList([...h, ...nonce, ...ct]);
}

/// Opens [entry] with the step key of its `(g, d, j)`; `null` when it does
/// not open (wrong key, altered bytes).
Uint8List? entryOpen(Uint8List entry, Uint8List step) {
  final head = EntryHead.of(entry);
  if (head == null) return null;
  final h = Uint8List.sublistView(entry, 0, kEntryHeadLength);
  final nonce = Uint8List.sublistView(
      entry, kEntryHeadLength, kEntryHeadLength + _kNonceLength);
  final ct = Uint8List.sublistView(entry, kEntryHeadLength + _kNonceLength);
  try {
    return _na.aesGcmDecrypt(ct, postKey(step, head.id), nonce, ad: h);
  } on Object {
    return null;
  }
}
