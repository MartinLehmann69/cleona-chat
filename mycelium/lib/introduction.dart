/// The introduction — what a request and its answer say about the sender,
/// so that the one asked has anything to decide at all.
///
/// Until today the request (packet 2) carried the bare code as payload and
/// the answer (packet 3) a single decision byte. The one asked thus saw
/// nothing but a key address — he was to accept or
/// decline without knowing who is asking. That is the gap that
/// `berichte/S384-RESTLISTE.md` re-measured under 2.5 and 2.6.
///
/// This file knows neither network nor envelope. It defines two fields,
/// encodes them and — the point — CHECKS them on reading. A limit that
/// only the sender keeps is no limit: the sender is the
/// other side and does what it wants.
///
/// Wire format, appended to the payload INSIDE the seal:
///
/// ```
/// name     u16 LE length in bytes + UTF-8
/// greeting u16 LE length in bytes + UTF-8
/// ```
///
/// If the introduction is missing entirely, NOTHING stands there — no length field, no
/// zero byte. A request from a version without introduction is thus
/// still a valid request, and the good case "bare code" stays
/// byte for byte the same as before.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Maximum length of the name in BYTES after UTF-8.
///
/// Owner decision 4a of 13.09.2026: name at most 64 bytes, greeting
/// at most 280 bytes. The chapter source `v42/kap/ch15.md:395-399` counts
/// in CHARACTERS at this place ("counted in characters, not bytes"); the
/// decision counts in bytes and takes precedence. The difference is not
/// cosmetic — an emoji occupies four bytes, an umlaut two, and only the
/// byte count bounds what a reader actually has to read.
const int kNameAtMostBytes = 64;

/// Maximum length of the greeting in BYTES after UTF-8 (owner decision 4a,
/// 13.09.2026). See [kNameAtMostBytes].
const int kGreetingAtMostBytes = 280;

/// Cap over the WHOLE payload of a first-contact packet, introduction
/// included (`v42/kap/ch15.md:401-404`: "capped at 8 KB").
///
/// It is not binding today — code (16 B) + name (2+64) + greeting (2+280)
/// are at most 364 B. It still stands here and is checked, because
/// it is the place where a later decided image field hits
/// before it bursts the splitting of a packet.
const int kPayloadAtMostBytes = 8 * 1024;

/// Thrown on every violation of the limits or the wire format —
/// at the sender as at the recipient.
class IntroductionError implements Exception {
  final String reason;
  IntroductionError(this.reason);
  @override
  String toString() => 'VorstellungFehler: $reason';
}

/// Name and greeting. Both may be empty; both are limited in their length,
/// and the limit is enforced here — in the constructor, i.e.
/// also for every introduction that has just been read from the wire.
class Introduction {
  /// How the sender is displayed.
  final String name;

  /// Free text that stands next to the question.
  final String greeting;

  Introduction({this.name = '', this.greeting = ''}) {
    _capCheck('Name', name, kNameAtMostBytes);
    _capCheck('Greeting', greeting, kGreetingAtMostBytes);
  }

  /// Nothing to show — then no introduction at all belongs in the packet.
  bool get empty => name.isEmpty && greeting.isEmpty;

  /// Length of the name in bytes, as it is measured and bounded.
  int get nameBytes => utf8.encode(name).length;

  /// Length of the greeting in bytes.
  int get greetingBytes => utf8.encode(greeting).length;

  /// The four fields of the wire format, without the body before them.
  Uint8List pack() {
    final n = utf8.encode(name);
    final g = utf8.encode(greeting);
    return (BytesBuilder()
          ..add(_u16le(n.length))
          ..add(n)
          ..add(_u16le(g.length))
          ..add(g))
        .toBytes();
  }

  bool equal(Introduction other) => name == other.name && greeting == other.greeting;

  @override
  String toString() => 'Introduction($name, $greetingBytes B greeting)';
}

/// Appends [self] to [body] — the code for the request, the
/// decision byte for the answer. If [self] is null or empty,
/// nothing is added and [body] stays what it was.
Uint8List introductionAppend(Uint8List body, Introduction? self) {
  if (self == null || self.empty) return Uint8List.fromList(body);
  final out = (BytesBuilder()
        ..add(body)
        ..add(self.pack()))
      .toBytes();
  if (out.length > kPayloadAtMostBytes) {
    throw IntroductionError('Payload has ${out.length} B, at most '
        '$kPayloadAtMostBytes B');
  }
  return out;
}

/// Reads the introduction back from [content] from position [from].
///
/// Returns null if nothing more stands from there — a request without
/// introduction is still valid. Throws [IntroductionError] on every other
/// violation: field too long, truncated field, invalid UTF-8,
/// surplus bytes at the end, payload too large.
///
/// THAT is the place where the limits apply. A field that is too long is
/// REJECTED, not truncated: a truncated greeting would be attributed to its sender
/// although they never wrote it that way.
Introduction? introductionRead(Uint8List content, int from) {
  if (content.length > kPayloadAtMostBytes) {
    throw IntroductionError('Payload has ${content.length} B, at most '
        '$kPayloadAtMostBytes B');
  }
  if (from >= content.length) return null;
  var pos = from;

  String field(String what, int cap) {
    if (pos + 2 > content.length) {
      throw IntroductionError('$what: length field truncated');
    }
    final n = content[pos] | (content[pos + 1] << 8);
    pos += 2;
    if (n > cap) {
      throw IntroductionError(
          '$what has $n B, at most $cap B (owner decision 4a)');
    }
    if (pos + n > content.length) {
      throw IntroductionError('$what is truncated: $n B announced, '
          '${content.length - pos} present');
    }
    final raw = Uint8List.sublistView(content, pos, pos + n);
    pos += n;
    try {
      return utf8.decode(raw);
    } on FormatException catch (e) {
      throw IntroductionError('$what is not valid UTF-8: ${e.message}');
    }
  }

  final name = field('Name', kNameAtMostBytes);
  final greeting = field('Greeting', kGreetingAtMostBytes);
  if (pos != content.length) {
    throw IntroductionError(
        '${content.length - pos} surplus bytes after the introduction');
  }
  return Introduction(name: name, greeting: greeting);
}

void _capCheck(String what, String value, int cap) {
  final n = utf8.encode(value).length;
  if (n > cap) {
    throw IntroductionError(
        '$what has $n B, at most $cap B (owner decision 4a, '
        'counted in bytes after UTF-8, not in characters)');
  }
}

Uint8List _u16le(int value) {
  final b = ByteData(2)..setUint16(0, value, Endian.little);
  return b.buffer.asUint8List();
}
