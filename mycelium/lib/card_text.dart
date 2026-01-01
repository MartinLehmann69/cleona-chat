/// The invitation as TEXT — for copying and pasting instead of scanning.
///
/// Two forms (V4.2 §15.6):
///  * `cleona:1:<base64url>` — payload = `Card.pack()` + 2 B CRC-16;
///  * `cleona:2:<base64url>` — payload = `Card.pack()` ‖ `pk_inv` (32 B) ‖
///    key bundle (3168 B) ‖ Ed25519 signature (64 B) ‖ the issuer's rotation
///    chain (1 + 5357·n B, §4.5.4; count 0 while it never rotated) ‖ CRC-16
///    (proposal E, owner approval 28.09.2026; signature: owner decision T-a;
///    chain: proposal A, D-33).
///    With it a requester needs no bundle round trip (packets (0)/(1)) and
///    can leave its request in the issuer's invitation post box while the
///    issuer is off. QR and NFC keep carrying only the packed card.
///
/// **The signature (T-a).** The line's sealing keys are the invitation's own
/// (R-b) and not covered by the fingerprint; whoever alters the line in
/// transit could swap them and read the request. The issuer's identity
/// Ed25519 key — bound to the fingerprint — signs [lineSignedData]; the
/// reader checks it against the Ed25519 key in the line's bundle BEFORE
/// anything is sealed ([CardTextErrorKind.badSignature]). Ed25519 only: it is
/// checked once, at redemption, and protects the line only in transit.
///
/// The CRC is little endian, over everything before it — no hash callback
/// needed (card.dart keeps SHA-256 external), detects truncation/modification.
///
/// [outInvitationText] is TOLERANT: line breaks in the middle of the text,
/// embedding in other text, quotation marks/brackets around it,
/// invisible characters, missing prefix. Errors: [CardTextError], five
/// kinds. LENGTH BEFORE CHECKSUM: the size of a complete card
/// follows unambiguously from version byte, address count byte including type bytes,
/// neighbour flag, publisher-key flag and the count and length bytes of the relay
/// list (91 B without address, key and relays up to 413 B, V4.2 §15.2, §15.6, each
/// + 2 B CRC) — without
/// parsing the card; a `cleona:2:` line adds [kLineKeysLength], the chain's
/// count byte and 5357 B per link, the count read at its fixed offset. If the
/// length does not fit: [truncated] (too short or too long). If the length fits
/// but not the checksum: [tampered] — the text is complete, but
/// changed. Two causes, two pieces of advice ("copy more" vs.
/// "copy again"), which one would otherwise confuse.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/identity/rotation_chain.dart'
    show kChainLinkWireLength, kRotationChainMaxLinks;
import 'package:mycelium/card.dart';

/// The distinguishable error causes when reading an invitation text.
enum CardTextErrorKind {
  /// Neither "cleona:1:"/"cleona:2:" prefix nor plausible base64url text found.
  notFound,

  /// The length computed from version byte + address flags does NOT fit the
  /// length of the decoded bytes (too few or too many), also when there are not even
  /// enough bytes to read the flags — text was
  /// truncated on pasting or provided with extra characters.
  truncated,

  /// Length fits, but the CRC-16 checksum does not — complete text,
  /// but changed on the way (e.g. autocorrect, broken encoding).
  tampered,

  /// Length and checksum match, but `Card.unpack()` still rejects the
  /// bytes (e.g. unknown version byte) — a different version.
  wrongVersion,

  /// No valid base64url text (wrong length or characters outside
  /// the alphabet after cleaning).
  brokenChars,

  /// A `cleona:2:` line whose signature does not verify against the
  /// Ed25519 key in its own bundle — its keys were altered (T-a). Checked
  /// only where a verifier is passed ([outInvitationLine]).
  badSignature,
}

class CardTextError implements Exception {
  final CardTextErrorKind kind;
  final String message;
  CardTextError(this.kind, this.message);
  @override
  String toString() => 'KartentextFehler(${kind.name}): $message';
}

final _withPreamble = RegExp(r'cleona:([12]):([A-Za-z0-9_-]+)');
final _withoutPreamble = RegExp(r'[A-Za-z0-9_-]{40,}');

/// Length of `pk_inv` in a `cleona:2:` line.
const int kLineInvitationKeyLength = 32;

/// Length of the key bundle in a `cleona:2:` line: Ed25519 32 + ML-KEM-768
/// 1184 + ML-DSA-65 1952 (V4.2 §15.1). `bundle.dart` builds it and checks
/// its result against this number.
const int kLineBundleLength = 3168;

/// Length of the Ed25519 signature in a `cleona:2:` line (T-a).
const int kLineSignatureLength = 64;

/// What a `cleona:2:` line carries beyond the card: 32 + 3168 + 64 = 3264.
const int kLineKeysLength =
    kLineInvitationKeyLength + kLineBundleLength + kLineSignatureLength;

/// Ed25519 32 B at the front of the bundle, then ML-KEM-768 1184 B.
const int _bundleEdLength = 32;
const int _bundleKemLength = 1184;

/// A read invitation line: the card, and for `cleona:2:` also `pk_inv`, the
/// key bundle, the signature and the rotation chain (wire form); all `null`
/// for `cleona:1:`.
typedef CardLine = ({
  Card card,
  Uint8List? pkInv,
  Uint8List? bundle,
  Uint8List? signature,
  Uint8List? chain,
});

/// Checks an Ed25519 [signature] over [data] with [publicKey] — passed in by
/// the caller, so this file stays without a crypto library.
typedef LineVerify = bool Function(
    Uint8List data, Uint8List signature, Uint8List publicKey);

/// What the issuer signs (T-a): domain ‖ channel ‖ code ‖ expiry (u32 LE) ‖
/// pk_inv ‖ the invitation's X25519 key (the card's letter key) ‖ its
/// ML-KEM key (from the bundle).
Uint8List lineSignedData(Card k, Uint8List pkInv, Uint8List bundle) =>
    (BytesBuilder()
          ..add(utf8.encode('mycelium-line-v1'))
          ..addByte(k.channel)
          ..add(k.code)
          ..add((ByteData(4)..setUint32(0, k.expiryUnixSeconds, Endian.little))
              .buffer
              .asUint8List())
          ..add(pkInv)
          ..add(k.letterKeyX25519)
          ..add(Uint8List.sublistView(
              bundle, _bundleEdLength, _bundleEdLength + _bundleKemLength)))
        .toBytes();

/// Creates the invitation as one line of text in the card-only form
/// `cleona:1:` — still read everywhere; the issuer hands out [asInvitationLine].
String asInvitationText(Card k) => _line(1, k.pack());

/// Creates the `cleona:2:` line: card ‖ [pkInv] ‖ [bundle] ‖ [signature] ‖
/// [chain] (proposal E, T-a, A); [signature] over [lineSignedData], [chain]
/// the issuer's rotation chain in wire form (without it: count 0).
String asInvitationLine(
    Card k, Uint8List pkInv, Uint8List bundle, Uint8List signature,
    {Uint8List? chain}) {
  final c = chain ?? Uint8List(1);
  if (pkInv.length != kLineInvitationKeyLength ||
      bundle.length != kLineBundleLength ||
      signature.length != kLineSignatureLength ||
      c.isEmpty ||
      c.length != 1 + kChainLinkWireLength * c[0]) {
    throw ArgumentError('pk_inv ${pkInv.length} B / bundle ${bundle.length} B '
        '/ signature ${signature.length} B, expected $kLineInvitationKeyLength '
        '/ $kLineBundleLength / $kLineSignatureLength');
  }
  return _line(2, (BytesBuilder()
        ..add(k.pack())
        ..add(pkInv)
        ..add(bundle)
        ..add(signature)
        ..add(c))
      .toBytes());
}

String _line(int version, Uint8List payload) {
  final checksum = _crc16(payload);
  final total = Uint8List(payload.length + 2);
  total.setRange(0, payload.length, payload);
  total[payload.length] = checksum & 0xFF;
  total[payload.length + 1] = (checksum >> 8) & 0xFF;
  final b64 = base64Url.encode(total).replaceAll('=', '');
  return 'cleona:$version:$b64';
}

/// Reads an invitation from arbitrary text, throws [CardTextError].
///
/// [expectedChannel] is the channel in which reading happens (live/beta). A
/// card with a foreign channel comes back as [CardTextErrorKind.wrongVersion]
/// — with the message from [CardChannelError], which names the channel. No
/// error kind of its own: the advice is the same as for a foreign version
/// ("this invitation does not belong in this app").
Card outInvitationText(String input, {int expectedChannel = Card.channelLive}) =>
    outInvitationLine(input, expectedChannel: expectedChannel).card;

/// Like [outInvitationText], and for a `cleona:2:` line also `pk_inv`, the
/// key bundle and the signature. Without a prefix the length decides: exactly
/// the card, or the card plus [kLineKeysLength]. With [verify] the signature
/// of a `cleona:2:` line is checked ([CardTextErrorKind.badSignature]).
CardLine outInvitationLine(String input,
    {int expectedChannel = Card.channelLive, LineVerify? verify}) {
  final purged = _purge(input).trim();
  if (purged.isEmpty) {
    throw CardTextError(CardTextErrorKind.notFound, 'empty input — no invitation');
  }

  final prefixed = _withPreamble.firstMatch(purged);
  final candidate =
      prefixed?.group(2) ?? _withoutPreamble.firstMatch(purged)?.group(0);
  if (candidate == null) {
    throw CardTextError(CardTextErrorKind.notFound,
        'neither "cleona:1:…"/"cleona:2:…" prefix nor base64url text found in the given text');
  }

  final bytes = _debase64(candidate);
  if (bytes.length < 2) {
    throw CardTextError(CardTextErrorKind.truncated,
        'only ${bytes.length} byte(s) after decoding — too short for the checksum');
  }

  final payload = Uint8List.sublistView(bytes, 0, bytes.length - 2);
  final cardLength = _expectedLength(payload);
  final lineLength = cardLength == null ? null : _lineLength(payload, cardLength);
  // `cleona:2:` by its prefix; without one, by the length alone.
  final two = prefixed != null
      ? prefixed.group(1) == '2'
      : lineLength != null && payload.length == lineLength;
  final expectedLength =
      cardLength == null ? null : (two ? lineLength : cardLength);
  final receivedCrc = bytes[bytes.length - 2] | (bytes[bytes.length - 1] << 8);
  // A complete text of another card version (its checksum holds over all of
  // it): its layout is unknown, so its length says nothing — "wrong version",
  // not "truncated" (§15.6; E-3 A1: a 0x01 card is "unknown card version").
  if (payload.isNotEmpty &&
      payload[0] != Card.version &&
      _crc16(payload) == receivedCrc) {
    throw CardTextError(CardTextErrorKind.wrongVersion,
        'unknown card version: ${payload[0]} (expected ${Card.version})');
  }
  if (expectedLength != null && expectedLength != payload.length) {
    final toFew = payload.length < expectedLength;
    throw CardTextError(CardTextErrorKind.truncated,
        '${payload.length} instead of $expectedLength bytes of payload (computed from version byte '
        '+ address flags) — text was probably '
        '${toFew ? "abgeschnitten" : "mit Zusatzzeichen versehen"}');
  }

  final expectedCrc = _crc16(payload);
  if (expectedCrc != receivedCrc) {
    // Length demonstrably matches (see above), yet wrong checksum -> the
    // text arrived completely, but was changed on the way. Without a
    // verified length (flags invalid/too short) only "truncated" remains.
    if (expectedLength != null) {
      throw CardTextError(CardTextErrorKind.tampered,
          'The inserted text is complete (length matches), but damaged '
          '— please copy it once more');
    }
    throw CardTextError(CardTextErrorKind.truncated,
        'Checksum does not match (expected 0x${expectedCrc.toRadixString(16)}, '
        'received 0x${receivedCrc.toRadixString(16)}) — text was probably '
        'truncated on insertion or altered on the way');
  }

  final cardBytes =
      two ? Uint8List.sublistView(payload, 0, cardLength) : payload;
  final CardLine line;
  try {
    final card = Card.unpack(cardBytes, expectedChannel: expectedChannel);
    if (!two) {
      return (card: card, pkInv: null, bundle: null, signature: null, chain: null);
    }
    var i = cardLength!;
    Uint8List cut(int n) =>
        Uint8List.fromList(Uint8List.sublistView(payload, i, i += n));
    line = (
      card: card,
      pkInv: cut(kLineInvitationKeyLength),
      bundle: cut(kLineBundleLength),
      signature: cut(kLineSignatureLength),
      chain: cut(payload.length - i),
    );
  } on CardFormatError catch (e) {
    throw CardTextError(CardTextErrorKind.wrongVersion,
        'Length and checksum match, but the card cannot be unpacked: '
        '${e.message}');
  }
  // T-a: before anything is sealed to its keys. No verifier (the pure reading
  // for display) checks nothing; whoever redeems passes one.
  if (verify != null &&
      !verify(lineSignedData(line.card, line.pkInv!, line.bundle!),
          line.signature!,
          Uint8List.sublistView(line.bundle!, 0, _bundleEdLength))) {
    throw CardTextError(CardTextErrorKind.badSignature,
        'the signature of the line does not verify — its keys were altered');
  }
  return line;
}

/// Reads version byte, the count byte of the own addresses with their
/// type bytes, the neighbour flag, the publisher-key flag and count and length
/// bytes of the relay list from [payload] and computes from them the length of
/// a COMPLETE card — without parsing it (V4.2 §15.6; the version byte is not
/// among the bytes read, so a damaged one stays "tampered").
/// `null` if [payload] is too short for that, a flag lies outside 0/1, a type
/// byte is unknown, the address count byte is above 4 or the relay list is invalid
/// (count byte > 3, length 0 or > 64); then the checksum alone decides.
///
/// Layout (card.dart `pack`): version(1)+channel(1)+letter key(32)+
/// fingerprint(32) = 66 B, then count byte (0-4) and per own address
/// type(1)+address(4/16)+port(2), then neighbour flag + possibly the same 7/19 B,
/// then publisher-key flag + possibly 32 B, then relay list (count byte + per
/// length byte + text), then difficulty(1)+code(16)+expiry(4): 91 to 413 B.
int? _expectedLength(Uint8List payload) {
  const beforeCountByte =
      1 + 1 + Card.letterKeyLength + Card.fingerprintLength;

  // Count byte (0-4) and then per entry type+address+port — without
  // unpacking a single address.
  final addresses = addressesLengthFrom(payload, beforeCountByte);
  if (addresses == null) return null;

  final beforeNeighbourFlag = beforeCountByte + addresses;
  if (payload.length <= beforeNeighbourFlag) return null;
  final neighbourFlag = payload[beforeNeighbourFlag];
  if (neighbourFlag != 0 && neighbourFlag != 1) return null;

  var afterAddresses = beforeNeighbourFlag + 1;
  if (neighbourFlag == 1) {
    if (payload.length <= afterAddresses) return null;
    final kind = CardAddressType.fromByte(payload[afterAddresses]);
    if (kind == null) return null;
    afterAddresses += 1 + kind.addressLength + 2;
  }

  // Publisher-key flag (§15.2), then 0 or 32 B.
  if (payload.length <= afterAddresses) return null;
  final publisherFlag = payload[afterAddresses];
  if (publisherFlag != 0 && publisherFlag != 1) return null;
  afterAddresses += 1 + (publisherFlag == 1 ? Card.publisherKeyLength : 0);

  // Relay list, then difficulty(1) + code(16) + expiry(4).
  final relay = relaysLengthFrom(payload, afterAddresses);
  if (relay == null) return null;
  return afterAddresses + relay + 1 + Card.codeLength + 4;
}

/// The payload length of a complete `cleona:2:` line whose card is
/// [cardLength] B: card + [kLineKeysLength] + the chain, whose count byte
/// stands at its fixed offset (§15.6). A payload that ends before it is
/// expected to carry at least the count byte; a count above
/// [kRotationChainMaxLinks] gives `null` (the checksum decides).
int? _lineLength(Uint8List payload, int cardLength) {
  final at = cardLength + kLineKeysLength;
  if (payload.length <= at) return at + 1;
  final n = payload[at];
  if (n > kRotationChainMaxLinks) return null;
  return at + 1 + kChainLinkWireLength * n;
}

/// Removes invisible characters (zero-width space, BOM) and line breaks
/// (\r, \n) — a line wrapped by a mail program becomes contiguous again.
/// Spaces/tabs stay: outside the alphabet, they delimit the search (also
/// against brackets or a second occurrence).
String _purge(String input) => input
    .replaceAll('​', '')
    .replaceAll('﻿', '')
    .replaceAll('\r', '')
    .replaceAll('\n', '');

Uint8List _debase64(String candidate) {
  final rest = candidate.length % 4;
  final String padded;
  switch (rest) {
    case 0:
      padded = candidate;
    case 2:
      padded = '$candidate==';
    case 3:
      padded = '$candidate=';
    default:
      throw CardTextError(CardTextErrorKind.brokenChars,
          'invalid length for base64url: ${candidate.length} characters (remainder $rest at /4)');
  }
  try {
    return base64Url.decode(padded);
  } on FormatException catch (e) {
    throw CardTextError(CardTextErrorKind.brokenChars,
        'no valid base64url text: ${e.message}');
  }
}

/// CRC-16 (reflected, polynomial 0xA001, init 0xFFFF), see the library doc.
int _crc16(Uint8List data) {
  var crc = 0xFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      if (crc & 1 != 0) {
        crc = (crc >> 1) ^ 0xA001;
      } else {
        crc >>= 1;
      }
    }
  }
  return crc & 0xFFFF;
}
