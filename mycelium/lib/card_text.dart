/// The invitation as TEXT — for copying and pasting instead of scanning.
///
/// Form: `cleona:1:<base64url without padding>`, payload =
/// `Card.pack()` + 2 bytes CRC-16 (little endian). CRC instead of hash: no
/// callback needed (card.dart deliberately keeps SHA-256 external, see the
/// "OPEN SEAM" there), ten lines suffice, detects truncation/modification.
///
/// [outInvitationText] is TOLERANT: line breaks in the middle of the text,
/// embedding in other text, quotation marks/brackets around it,
/// invisible characters, missing prefix. Errors: [CardTextError], five
/// kinds. LENGTH BEFORE CHECKSUM: the size of a complete card
/// follows unambiguously from version byte, address count byte including type bytes,
/// neighbour flag and the count and length bytes of the relay list (90 B without
/// address and without relays up to 380 B, V4.2 §15.2, each + 2 B CRC) — without
/// parsing the card. If the length
/// does not fit: [truncated] (too short or too long). If the length fits but
/// not the checksum: [tampered] — the text is complete, but
/// changed. Two causes, two pieces of advice ("copy more" vs.
/// "copy again"), which one would otherwise confuse.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mycelium/card.dart';

/// The five distinguishable error causes when reading an invitation text.
enum CardTextErrorKind {
  /// Neither "cleona:1:" prefix nor plausible base64url text found.
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
}

class CardTextError implements Exception {
  final CardTextErrorKind kind;
  final String message;
  CardTextError(this.kind, this.message);
  @override
  String toString() => 'KartentextFehler(${kind.name}): $message';
}

final _withPreamble = RegExp(r'cleona:1:([A-Za-z0-9_-]+)');
final _withoutPreamble = RegExp(r'[A-Za-z0-9_-]{40,}');

/// Creates the invitation as one line of text.
String asInvitationText(Card k) {
  final payload = k.pack();
  final checksum = _crc16(payload);
  final total = Uint8List(payload.length + 2);
  total.setRange(0, payload.length, payload);
  total[payload.length] = checksum & 0xFF;
  total[payload.length + 1] = (checksum >> 8) & 0xFF;
  final b64 = base64Url.encode(total).replaceAll('=', '');
  return 'cleona:1:$b64';
}

/// Reads an invitation from arbitrary text, throws [CardTextError].
///
/// [expectedChannel] is the channel in which reading happens (live/beta). A
/// card with a foreign channel comes back as [CardTextErrorKind.wrongVersion]
/// — with the message from [CardChannelError], which names the channel
/// by name. Deliberately NO sixth error kind: the advice to the
/// user is the same as for a foreign version ("this invitation
/// does not belong in this app"), and every existing caller still catches
/// exactly five kinds.
Card outInvitationText(String input, {int expectedChannel = Card.channelLive}) {
  final purged = _purge(input).trim();
  if (purged.isEmpty) {
    throw CardTextError(CardTextErrorKind.notFound, 'empty input — no invitation');
  }

  final candidate = _withPreamble.firstMatch(purged)?.group(1) ??
      _withoutPreamble.firstMatch(purged)?.group(0);
  if (candidate == null) {
    throw CardTextError(CardTextErrorKind.notFound,
        'neither "cleona:1:…" prefix nor base64url text found in the given text');
  }

  final bytes = _debase64(candidate);
  if (bytes.length < 2) {
    throw CardTextError(CardTextErrorKind.truncated,
        'only ${bytes.length} byte(s) after decoding — too short for the checksum');
  }

  final payload = Uint8List.sublistView(bytes, 0, bytes.length - 2);
  final expectedLength = _expectedLength(payload);
  if (expectedLength != null && expectedLength != payload.length) {
    final toFew = payload.length < expectedLength;
    throw CardTextError(CardTextErrorKind.truncated,
        '${payload.length} instead of $expectedLength bytes of payload (computed from version byte '
        '+ address flags) — text was probably '
        '${toFew ? "abgeschnitten" : "mit Zusatzzeichen versehen"}');
  }

  final expectedCrc = _crc16(payload);
  final receivedCrc = bytes[bytes.length - 2] | (bytes[bytes.length - 1] << 8);
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

  try {
    return Card.unpack(payload, expectedChannel: expectedChannel);
  } on CardFormatError catch (e) {
    throw CardTextError(CardTextErrorKind.wrongVersion,
        'Length and checksum match, but the card cannot be unpacked: '
        '${e.message}');
  }
}

/// Reads version byte, the count byte of the own addresses with their
/// type bytes, the neighbour flag and count and length bytes of the relay list from
/// [payload] and computes from them the length of a COMPLETE card —
/// without parsing it.
/// `null` if [payload] is too short for that, the neighbour flag lies outside
/// 0/1, a type byte is unknown, the address count byte is above 4
/// or the relay list is invalid (count byte > 3, length 0 or > 64);
/// then the caller falls back on the checksum alone.
///
/// Layout (card.dart `pack`): version(1)+channel(1)+letter key(32)+
/// fingerprint(32) = 66 B, then count byte (0-4) and per own address
/// type(1)+address(4/16)+port(2), then neighbour flag + possibly the same 7/19 B,
/// then relay list (count byte + per length byte + text), then
/// difficulty(1)+code(16)+expiry(4).
/// Yields 90 B (no address, no relays) up to 380 B (V4.2 §15.2).
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

  // Relay list, then difficulty(1) + code(16) + expiry(4).
  final relay = relaysLengthFrom(payload, afterAddresses);
  if (relay == null) return null;
  return afterAddresses + relay + 1 + Card.codeLength + 4;
}

/// Removes invisible characters (zero-width space, BOM) and line breaks
/// (\r, \n) — turns a line wrapped by the mail program in the middle of the base64url text
/// back into a contiguous one. Real spaces/tabs
/// stay: never part of the alphabet, they act by themselves as a delimiter when searching (see below)
/// — also for brackets around it or a second
/// occurrence (the first find ends where the alphabet ends).
String _purge(String input) => input
    .replaceAll('​', '')
    .replaceAll('﻿', '')
    .replaceAll('\r', '')
    .replaceAll('\n', '');

/// Bring base64url without padding to a valid multiple of 4.
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

/// CRC-16 (reflected, polynomial 0xA001, init 0xFFFF), appended little
/// endian. Own implementation, see class doc above.
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
