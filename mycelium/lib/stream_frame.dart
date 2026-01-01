/// Lane 2 of §9.4 — the packets of the relayed media stream (§17.6).
///
/// The stream carries the SAME sealed pieces as lane 3 (`bulk_piece.dart`):
/// a Reed-Solomon piece of `media.dart`, sealed under `HKDF(K_T,
/// "bulk/seal")` with the associated data tag ‖ stripe ‖ number. Pieces are
/// lane-neutral (§9.4), so a stream that breaks off hands what it has to
/// lane 3 without re-opening anything.
///
/// This file knows no socket and no clock; the volunteer
/// (`stream_volunteer.dart`), the sender (`stream_send.dart`) and the
/// recipient (`stream_receive.dart`) build and read their packets here.
///
/// ## Packet layouts (§11.5: 0x56–0x5A; every one fits ONE part)
/// | Kind | Layout | Length |
/// |---|---|---|
/// | 0x56 ask | kind, size u32 BE, random 16, zero 16 | 37 |
/// | 0x57 answer | kind, the same random 16, verdict u8, cookie S 8, cookie R 8 | 34 |
/// | 0x58 join | kind, cookie 8 — the volunteer echoes it once paired | 9 |
/// | 0x59 frame | kind, cookie 8, stripe u16 BE, no u8, sealed 1040, zero to 1158 | 1158 |
/// | 0x5A missing | kind, cookie 8, form u8, body (below) | ≥ 10 |
///
/// The ask carries 16 zero bytes so that the answer is never larger than
/// the question: an answer to a forged sender address amplifies nothing
/// (§17.4). The frame fills one part exactly (`kMaxPayload`), and the shell
/// brings every part to 1200 B — the 1200 B class of §17.1, byte-uniform
/// with the cell size.
///
/// `0x5A` forms: 0 request — round u8, n u16, n × (stripe u16, mask u16 of
/// the missing piece numbers); 1 done; 2 give up — n u16, n × stripe u16
/// (the stripes still undecodable); 3 mark — frames received u32. A long
/// request is split into parts like any packet (`split.dart`).
library;

import 'dart:typed_data';

import 'package:mycelium/bulk_piece.dart' show kSealedLength;
import 'package:mycelium/card_address.dart';
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/media.dart' show kCapC;
import 'package:mycelium/split.dart' show kMaxPayload;

/// `C` of §9.4 for the volunteer (D-1, D-14): 25 MB of payload — the size
/// at which §9.4 computes 3,488 stripes, so 25,000,000 B, not 25 MiB. The
/// one origin is `media.dart`'s [kCapC]; the lane choice and the volunteer
/// use the same number.
const int kStreamCap = kCapC;

const int kCookieLength = 8;
const int kAskRandomLength = 16;
const int kAskLength = 1 + 4 + kAskRandomLength + 16; // 37
const int kAnswerLength = 1 + kAskRandomLength + 1 + 2 * kCookieLength; // 34
const int kJoinLength = 1 + kCookieLength; // 9
const int kFrameHeader = 1 + kCookieLength + 3; // 12
const int kFrameLength = kMaxPayload; // 1158

/// Verdicts of `0x57`.
const int kVerdictGranted = 0;
const int kVerdictTooLarge = 1;
const int kVerdictBusy = 2;
const int kVerdictNoVolunteer = 3;

/// Forms of `0x5A`.
const int kMissingRequest = 0;
const int kMissingDone = 1;
const int kMissingGiveUp = 2;
const int kMissingMark = 3;

bool cookieSame(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    d |= a[i] ^ b[i];
  }
  return d == 0;
}

/// The cookie of a join, frame or missing packet; `null` for anything else.
Uint8List? streamCookie(Uint8List p) {
  if (p.length < 1 + kCookieLength) return null;
  final k = p[0];
  if (k != kinds.kStreamJoin && k != kinds.kStreamFrame &&
      k != kinds.kStreamMissing) {
    return null;
  }
  return Uint8List.sublistView(p, 1, 1 + kCookieLength);
}

/// The same packet under another cookie — what the volunteer forwards.
Uint8List cookieSwap(Uint8List p, Uint8List cookie) =>
    Uint8List.fromList(p)..setRange(1, 1 + kCookieLength, cookie);

// ── 0x56 / 0x57 ──────────────────────────────────────────────────────────

Uint8List askPacket(int size, Uint8List random) {
  final p = Uint8List(kAskLength)..[0] = kinds.kStreamAsk;
  ByteData.sublistView(p).setUint32(1, size, Endian.big);
  return p..setRange(5, 5 + kAskRandomLength, random);
}

({int size, Uint8List random})? readAsk(Uint8List p) =>
    p.length == kAskLength && p[0] == kinds.kStreamAsk
        ? (
            size: ByteData.sublistView(p).getUint32(1, Endian.big),
            random: Uint8List.fromList(p.sublist(5, 5 + kAskRandomLength)),
          )
        : null;

typedef StreamAnswer = ({
  Uint8List random,
  int verdict,
  Uint8List senderCookie,
  Uint8List recipientCookie,
});

Uint8List answerPacket(StreamAnswer a) => Uint8List(kAnswerLength)
  ..[0] = kinds.kStreamAnswer
  ..setRange(1, 17, a.random)
  ..[17] = a.verdict
  ..setRange(18, 26, a.senderCookie)
  ..setRange(26, 34, a.recipientCookie);

StreamAnswer? readAnswer(Uint8List p) =>
    p.length == kAnswerLength && p[0] == kinds.kStreamAnswer
        ? (
            random: Uint8List.fromList(p.sublist(1, 17)),
            verdict: p[17],
            senderCookie: Uint8List.fromList(p.sublist(18, 26)),
            recipientCookie: Uint8List.fromList(p.sublist(26, 34)),
          )
        : null;

// ── 0x58 / 0x59 ──────────────────────────────────────────────────────────

Uint8List joinPacket(Uint8List cookie) => Uint8List(kJoinLength)
  ..[0] = kinds.kStreamJoin
  ..setRange(1, kJoinLength, cookie);

bool isJoin(Uint8List p) => p.length == kJoinLength && p[0] == kinds.kStreamJoin;

Uint8List framePacket(Uint8List cookie, int stripe, int no, Uint8List sealed) {
  final p = Uint8List(kFrameLength)
    ..[0] = kinds.kStreamFrame
    ..setRange(1, 1 + kCookieLength, cookie);
  ByteData.sublistView(p).setUint16(9, stripe, Endian.big);
  p[11] = no;
  return p..setRange(kFrameHeader, kFrameHeader + kSealedLength, sealed);
}

({int stripe, int no, Uint8List sealed})? readFrame(Uint8List p) =>
    p.length == kFrameLength && p[0] == kinds.kStreamFrame
        ? (
            stripe: ByteData.sublistView(p).getUint16(9, Endian.big),
            no: p[11],
            sealed: Uint8List.fromList(
                p.sublist(kFrameHeader, kFrameHeader + kSealedLength)),
          )
        : null;

// ── 0x5A ─────────────────────────────────────────────────────────────────

/// What a request names: stripe -> bit mask of the missing piece numbers.
typedef Missing = Map<int, int>;

Uint8List _missingHead(Uint8List cookie, int form, int body) =>
    Uint8List(1 + kCookieLength + 1 + body)
      ..[0] = kinds.kStreamMissing
      ..setRange(1, 1 + kCookieLength, cookie)
      ..[1 + kCookieLength] = form;

Uint8List requestPacket(Uint8List cookie, int round, Missing m) {
  final p = _missingHead(cookie, kMissingRequest, 3 + 4 * m.length);
  final b = ByteData.sublistView(p)
    ..setUint8(10, round)
    ..setUint16(11, m.length, Endian.big);
  var at = 13;
  for (final e in m.entries) {
    b
      ..setUint16(at, e.key, Endian.big)
      ..setUint16(at + 2, e.value, Endian.big);
    at += 4;
  }
  return p;
}

Uint8List donePacket(Uint8List cookie) => _missingHead(cookie, kMissingDone, 0);

Uint8List giveUpPacket(Uint8List cookie, List<int> stripes) {
  final p = _missingHead(cookie, kMissingGiveUp, 2 + 2 * stripes.length);
  final b = ByteData.sublistView(p)..setUint16(10, stripes.length, Endian.big);
  for (var i = 0; i < stripes.length; i++) {
    b.setUint16(12 + 2 * i, stripes[i], Endian.big);
  }
  return p;
}

Uint8List markPacket(Uint8List cookie, int received) {
  final p = _missingHead(cookie, kMissingMark, 4);
  ByteData.sublistView(p).setUint32(10, received, Endian.big);
  return p;
}

typedef MissingRead = ({
  int form,
  int round,
  Missing request,
  List<int> stripes,
  int received,
});

/// Reads any `0x5A`; `null` if a length does not match its form.
MissingRead? readMissing(Uint8List p) {
  if (p.length < 10 || p[0] != kinds.kStreamMissing) return null;
  final b = ByteData.sublistView(p);
  final form = p[9];
  MissingRead r({int round = 0, Missing? request, List<int>? stripes,
          int received = 0}) =>
      (
        form: form,
        round: round,
        request: request ?? const {},
        stripes: stripes ?? const [],
        received: received,
      );
  switch (form) {
    case kMissingDone:
      return p.length == 10 ? r() : null;
    case kMissingMark:
      return p.length == 14 ? r(received: b.getUint32(10, Endian.big)) : null;
    case kMissingGiveUp:
      if (p.length < 12) return null;
      final n = b.getUint16(10, Endian.big);
      if (p.length != 12 + 2 * n) return null;
      return r(stripes: [
        for (var i = 0; i < n; i++) b.getUint16(12 + 2 * i, Endian.big)
      ]);
    case kMissingRequest:
      if (p.length < 13) return null;
      final n = b.getUint16(11, Endian.big);
      if (p.length != 13 + 4 * n) return null;
      final m = <int, int>{};
      for (var i = 0; i < n; i++) {
        m[b.getUint16(13 + 4 * i, Endian.big)] =
            b.getUint16(15 + 4 * i, Endian.big);
      }
      return r(round: p[10], request: m);
  }
  return null;
}

// ── STREAM_OFFER (§17.6 "Session") ───────────────────────────────────────

/// The offer the sender places as an ordinary delivery: where the
/// recipient joins and with which cookie. `K_T`, length and SHA-256 travel
/// in the announcement (§9.4); the offer names none of them.
typedef StreamOffer = ({List<CardAddress> volunteer, Uint8List cookie});

/// n u8 (1..2) ‖ n × address (the card codec) ‖ cookie 8. Two addresses at
/// most: one per family, so that a recipient of either family can join.
Uint8List streamOfferPack(StreamOffer o) {
  if (o.volunteer.isEmpty || o.volunteer.length > 2 ||
      o.cookie.length != kCookieLength) {
    throw ArgumentError('offer: one or two volunteer addresses, cookie 8 B');
  }
  final b = BytesBuilder()..addByte(o.volunteer.length);
  for (final a in o.volunteer) {
    addressWrite(b, a);
  }
  return (b..add(o.cookie)).toBytes();
}

StreamOffer? streamOfferRead(Uint8List p) {
  var at = 0;
  Uint8List read(int n) {
    if (at + n > p.length) throw const FormatException('short offer');
    return Uint8List.sublistView(p, at, at += n);
  }

  try {
    final n = read(1)[0];
    if (n < 1 || n > 2) return null;
    final v = [for (var i = 0; i < n; i++) addressRead(read, 'volunteer')];
    final c = Uint8List.fromList(read(kCookieLength));
    return at == p.length ? (volunteer: v, cookie: c) : null;
  } on Object {
    return null;
  }
}
