/// The card neighbour's record key in the TEXT form of an invitation (V4.2
/// §11.9, §15.6; S407 a', owner decisions 09.10.2026: "Zu 1 = Ja", mixed
/// operation "B").
///
/// The card itself stays as 4.2.3 reads it (version `0x02`): its reader
/// (`Card.unpack`) rejects any other version, any neighbour flag but 0/1 and
/// every surplus byte, so the key cannot travel inside it. It travels BEHIND
/// the line instead:
///
/// ```
/// cleona:1:<card ‖ crc>.<base64url(record key 32 ‖ crc16(card ‖ key) 2)>
/// ```
///
/// The suffix stands behind every line this build issues: an all-zero key
/// says "no key known", and the suffix itself says the issuer reads keyed
/// neighbour lists ([Card.readsKeys]) — so the requester's first message
/// can carry its keyed list, and the issuer learns the same of it
/// (`neighbour_keys.dart`).
///
/// A 4.2.3 reader finds the line with `cleona:([12]):([A-Za-z0-9_-]+)` —
/// the match ends at the `.` — and never sees the suffix (`398a6e40`
/// `card_text.dart`, `outInvitationLine`, first match). This reader takes the
/// suffix only when its checksum binds it to exactly this card; a stray
/// full stop or a damaged suffix leaves the card without a key, never
/// without the card. QR and NFC carry the packed card in binary; a 4.2.3
/// reader rejects any byte more there, so they carry no key.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mycelium/card.dart';

/// Length of a record key (§11.9: the x-only secp256k1 key, BIP-340).
const int kRecordKeyLength = 32;

/// 32 B key + 2 B checksum, base64url without padding.
const int _suffixChars = 46;

final _suffix = RegExp(r'^\.([A-Za-z0-9_-]{46})(?![A-Za-z0-9_-])');

/// [line] with the suffix: the card neighbour's record key, or 32 zero bytes.
String withNeighbourKey(String line, Card k, int Function(Uint8List) crc) {
  final key = k.neighbourAddress?.recordKey ?? Uint8List(kRecordKeyLength);
  final c = crc(Uint8List.fromList([...k.pack(), ...key]));
  final body = base64Url
      .encode([...key, c & 0xFF, (c >> 8) & 0xFF]).replaceAll('=', '');
  assert(body.length == _suffixChars);
  return '$line.$body';
}

/// [card] flagged [Card.readsKeys] and with the record key that stands right
/// after [end] in [purged], when the suffix is there and its checksum fits
/// this card; otherwise [card] unchanged.
Card neighbourKeyRead(
    String purged, int end, Card card, int Function(Uint8List) crc) {
  final n = card.neighbourAddress;
  if (end > purged.length) return card;
  final m = _suffix.firstMatch(purged.substring(end));
  if (m == null) return card;
  final Uint8List raw;
  try {
    raw = base64Url.decode('${m.group(1)!}==');
  } on FormatException {
    return card;
  }
  final key = Uint8List.sublistView(raw, 0, kRecordKeyLength);
  final got = raw[kRecordKeyLength] | (raw[kRecordKeyLength + 1] << 8);
  if (crc(Uint8List.fromList([...card.pack(), ...key])) != got) return card;
  final none = key.every((b) => b == 0);
  return cardWithNeighbour(
      card, none || n == null ? n : n.withRecordKey(key), readsKeys: true);
}

/// [c] naming [neighbour] instead of its own — the same invitation.
Card cardWithNeighbour(Card c, CardAddress? neighbour, {bool? readsKeys}) => Card(
      channel: c.channel,
      letterKeyX25519: c.letterKeyX25519,
      fingerprint: c.fingerprint,
      ownAddresses: c.ownAddresses,
      neighbourAddress: neighbour,
      publisherKey: c.publisherKey,
      relay: c.relay,
      difficulty: c.difficulty,
      code: c.code,
      expiryUnixSeconds: c.expiryUnixSeconds,
      readsKeys: readsKeys ?? c.readsKeys,
    );
