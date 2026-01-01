import 'dart:typed_data';

import 'package:cleona/core/codec/compression.dart';

/// The aggregate: several messages in one cell.
///
/// TWO THINGS THAT BELONG TOGETHER HERE.
///
/// **Framing.** Until here aggregated messages were simply
/// concatenated — without a length field, and without anything anywhere
/// separating them again. Aggregating was write-only. With `laenge(2) ‖ inhalt`
/// per entry the aggregate is readable.
///
/// **Compression, and why exactly here.** §4.3 puts zstd "in the cell
/// assembly, before sealing" — and that is not a matter of taste, but
/// the only place where it brings anything:
///
///   * A cell is a fixed 1200 B on the wire. Compressing does not change
///     HOW MUCH is transferred, but how much FITS IN.
///   * Behind this place sealing happens. Ciphertext is not
///     compressible; whoever compresses after sealing compresses
///     noise.
///   * And per message individually it does not pay: a chat line of 60 B
///     does not carry the zstd frame header. Only several together share
///     enough structure for it to pay off. The calculation in §5.3
///     (~5 short messages per cell) presupposes compressed text.
///
/// WHAT MUST NEVER BE COMPRESSED TOGETHER: content for DIFFERENT
/// recipients. If one compresses externally determined and secret content in
/// one context, the packed length reveals something about the secret one —
/// that is the CRIME/BREACH pattern. Aggregation is per recipient (E-K),
/// so the aggregate belongs to one pair. This property is to be
/// preserved, not an accident.
///
/// NOTHING CHANGES ON THE WIRE: the result is padded to the fixed
/// size. How well the content could be packed is seen only by
/// whoever can open the cell.
abstract final class Aggregate {
  /// The content is uncompressed.
  static const int markerRaw = 0x00;

  /// The content is zstd-packed.
  static const int markerZstd = 0x01;

  /// Largest number of entries in an aggregate.
  static const int maxEntries = 64;

  /// Largest raw content that may be unpacked.
  ///
  /// Without a bound a few hundred bytes could unfold into megabytes,
  /// and the aggregate comes from the other side.
  static const int maxRawBytes = 8 * 1024;

  /// Builds the raw, framed content: `[laenge(2) ‖ inhalt]*`.
  static Uint8List frame(List<Uint8List> messages) {
    var n = 0;
    for (final m in messages) {
      if (m.length > 0xFFFF) throw ArgumentError('Entry too long');
      n += 2 + m.length;
    }
    final out = Uint8List(n);
    var o = 0;
    for (final m in messages) {
      out[o++] = (m.length >> 8) & 0xff;
      out[o++] = m.length & 0xff;
      out.setRange(o, o + m.length, m);
      o += m.length;
    }
    return out;
  }

  /// Packs [messages] into an aggregate of exactly [budget] bytes.
  ///
  /// Returns `null` if it does not fit — the caller then takes
  /// one entry fewer. An exception would be wrong here: "does not
  /// fit" is an answer, not an error.
  static Uint8List? pack(List<Uint8List> messages, int budget,
      {Uint8List Function(int)? filler}) {
    if (messages.length > maxEntries) return null;
    final raw = frame(messages);
    if (raw.length > maxRawBytes) return null;

    var marker = markerRaw;
    var content = raw;
    if (raw.isNotEmpty) {
      final small = ZstdCompression.instance.compress(raw);
      // The marker costs one byte; if packing brings less, it stays
      // raw. Already packed content — an image, an onion layer — is thus
      // not touched and does not get larger either.
      if (small.isNotEmpty && small.length < raw.length) {
        marker = markerZstd;
        content = small;
      }
    }
    // Header: `marker(1) ‖ laenge(2)`. The LENGTH must be included — without it
    // the unpacker would get the padding delivered along and would fail
    // on it. (Found exactly like this, 2026-08-22: the way back delivered zero
    // entries because zstd did not digest the appended filler bytes.)
    if (3 + content.length > budget) return null;
    if (content.length > 0xFFFF) return null;

    final out = Uint8List(budget);
    out[0] = marker;
    out[1] = (content.length >> 8) & 0xff;
    out[2] = content.length & 0xff;
    out.setRange(3, 3 + content.length, content);
    // The rest is padding. It lies in the ciphertext and cannot be told apart from payload
    // — but it must not consist of zeros,
    // otherwise a look at the plaintext reveals how much was really in it.
    if (filler != null && 3 + content.length < budget) {
      final rest = filler(budget - 3 - content.length);
      out.setRange(3 + content.length, budget, rest);
    }
    return out;
  }

  /// Reads an aggregate apart again.
  ///
  /// Everything malformed yields an empty list — silently (E-83).
  static List<Uint8List> unpack(Uint8List payload) {
    if (payload.length < 3) return const <Uint8List>[];
    final marker = payload[0];
    final len = (payload[1] << 8) | payload[2];
    if (3 + len > payload.length) return const <Uint8List>[];
    final field = Uint8List.sublistView(payload, 3, 3 + len);
    Uint8List raw;
    if (marker == markerRaw) {
      raw = field;
    } else if (marker == markerZstd) {
      try {
        raw = ZstdCompression.instance.decompress(field);
      } catch (_) {
        return const <Uint8List>[];
      }
      if (raw.length > maxRawBytes) return const <Uint8List>[];
    } else {
      return const <Uint8List>[];
    }

    final out = <Uint8List>[];
    var o = 0;
    while (o + 2 <= raw.length) {
      final len = (raw[o] << 8) | raw[o + 1];
      // Length 0 marks the end: padding lies behind it.
      if (len == 0) break;
      if (o + 2 + len > raw.length) break;
      out.add(Uint8List.fromList(raw.sublist(o + 2, o + 2 + len)));
      o += 2 + len;
      if (out.length > maxEntries) break;
    }
    return out;
  }
}
