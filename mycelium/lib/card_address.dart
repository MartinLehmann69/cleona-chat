import 'dart:typed_data';

/// The network channel in which a card is valid. A beta card must be rejected in the
/// live application IMMEDIATELY and with a nameable reason.
const int kChannelLive = 0x00;
const int kChannelBeta = 0x01;

String channelName(int channel) => switch (channel) {
      kChannelLive => 'live',
      kChannelBeta => 'beta',
      _ => '0x${channel.toRadixString(16).padLeft(2, '0')}',
    };

/// SHA-256 over the key bundle.
const int kFingerprintLength = 32;


/// Where someone is reachable — and how to report a card as broken.
///
/// Moved out of `card.dart`: an address describes WHERE someone is,
/// a card WHAT the invitation is. Two things in one file are a
/// reason why nobody knows any more where something stands.
class CardFormatError implements Exception {
  final String message;
  CardFormatError(this.message);

  @override
  String toString() => 'KarteFormatFehler: $message';
}

/// A separate error kind for the ONE case that does not mean "broken", but
/// "does not belong here": the card is formally flawless, but carries
/// a different channel than the one in which it is read (beta card in the
/// live app or vice versa). The user should learn exactly that —
/// therefore a separate type and not merely a different text.
///
/// Inherits from [CardFormatError], so that every existing caller that
/// catches `on CardFormatError` still catches this case and it does not
/// fall through unhandled.
class CardChannelError extends CardFormatError {
  /// The channel value read in the card.
  final int readChannel;

  /// The channel in which the card was read.
  final int expectedChannel;

  CardChannelError(this.readChannel, this.expectedChannel)
      : super('foreign channel: card carries '
            '${channelName(readChannel)}, reading '
            '${channelName(expectedChannel)}');

  @override
  String toString() => 'KarteKanalFehler: $message';
}

/// What kind an address in the card is. The type byte stands BEFORE the
/// address, because otherwise its length would have to be guessed and a mistake
/// shifts every following field.
enum CardAddressType {
  ipv4(4, 4),
  ipv6(6, 16);

  /// The byte that stands in the card.
  final int byteValue;

  /// How many bytes the address occupies after that.
  final int addressLength;

  const CardAddressType(this.byteValue, this.addressLength);

  /// `null` for an unknown byte — the caller then rejects the WHOLE card
  /// instead of reading on.
  static CardAddressType? fromByte(int b) {
    for (final t in CardAddressType.values) {
      if (t.byteValue == b) return t;
    }
    return null;
  }

  /// `null` if neither of the two lengths fits.
  static CardAddressType? fromLength(int length) {
    for (final t in CardAddressType.values) {
      if (t.addressLength == length) return t;
    }
    return null;
  }
}

/// An IP address + port as it stands in the card. The type follows
/// from the length of the bytes passed: 4 → IPv4, 16 → IPv6, everything else
/// is rejected.
class CardAddress {
  /// 4 bytes for IPv4, 16 for IPv6.
  final Uint8List address;
  final CardAddressType kind;
  final int port;

  CardAddress(Uint8List address, this.port)
      : address = Uint8List.fromList(address),
        kind = CardAddressType.fromLength(address.length) ??
            (throw ArgumentError(
                'CardAddress needs 4 (IPv4) or 16 (IPv6) bytes, '
                'got ${address.length}')) {
    if (port < 0 || port > 0xFFFF) {
      throw ArgumentError(
          'CardAddress.port must be between 0 and 65535, was $port');
    }
  }

  /// Old name of the bytes, so that callers from the time before the type byte
  /// still compile. For [CardAddressType.ipv6] it is 16 bytes, not
  /// 4 — new code reads [address] and [kind].
  Uint8List get ipv4 => address;

  /// How many bytes this address occupies in the packed card:
  /// type byte + address + port.
  int get packedLength => 1 + kind.addressLength + 2;

  bool equal(CardAddress other) {
    if (port != other.port) return false;
    if (kind != other.kind) return false;
    if (address.length != other.address.length) return false;
    for (var i = 0; i < address.length; i++) {
      if (address[i] != other.address[i]) return false;
    }
    return true;
  }

  @override
  String toString() {
    if (kind == CardAddressType.ipv4) {
      return '${address[0]}.${address[1]}.${address[2]}.${address[3]}:$port';
    }
    final groups = <String>[];
    for (var i = 0; i < 16; i += 2) {
      groups.add(((address[i] << 8) | address[i + 1]).toRadixString(16));
    }
    // Without "::" shortening: unambiguously readable, and nobody parses that back.
    return '[${groups.join(':')}]:$port';
  }
}

/// Maps a byte bundle to a fingerprint of fixed size
/// (intended: SHA-256, 32 bytes). See "OPEN SEAM" above — this file
/// deliberately does not choose the hash function itself.
typedef CardHashFunction = Uint8List Function(Uint8List input);

/// At most this many OWN addresses does a card carry (§15.2,
/// owner decision 16.09.2026).
///
/// Four, and the number has a reason: a multihomed device needs two
/// address kinds on two connections — a phone with Wi-Fi and cellular,
/// each IPv4 and IPv6. Nobody needs more, and the cap is not
/// cosmetic: at error correction H the largest card (380 B) lies THREE
/// bytes below the jump to QR version 21 (measured 16.09.2026, §15.2).
/// A fifth address would cost a whole version there.
const int kOwnAddressesAtMost = 4;

/// Packed length of the address list: count byte + per entry type, address,
/// port.
int addressesLength(List<CardAddress> addresses) =>
    addresses.fold(1, (sum, a) => sum + a.packedLength);

/// Count byte (0–4) and then the addresses in the order in which they
/// stand — and the order IS the statement (§15.2: "in the issuer's
/// order of preference"). It is therefore never sorted or rearranged.
void addressesWrite(BytesBuilder output, List<CardAddress> addresses) {
  output.addByte(addresses.length);
  for (final a in addresses) {
    addressWrite(output, a);
  }
}

/// Reads the list via [read], which itself throws on a read past the end.
/// A count byte above [kOwnAddressesAtMost] rejects the WHOLE
/// card (§15.2: "rejected as a whole") — a guessed number would shift
/// every following field.
List<CardAddress> addressesRead(Uint8List Function(int length) read) {
  final number = read(1)[0];
  if (number > kOwnAddressesAtMost) {
    throw CardFormatError(
        'address count $number, at most $kOwnAddressesAtMost');
  }
  return [
    for (var i = 1; i <= number; i++) addressRead(read, 'own address $i')
  ];
}

/// Packed length of the address list from [offset], without unpacking it —
/// for the length probe of the text form (`card_text.dart`). `null` if the
/// payload is too short, the count byte too large or a type byte unknown.
int? addressesLengthFrom(Uint8List payload, int offset) {
  if (payload.length <= offset) return null;
  final number = payload[offset];
  if (number > kOwnAddressesAtMost) return null;
  var length = 1;
  for (var i = 0; i < number; i++) {
    final p = offset + length;
    if (payload.length <= p) return null;
    final kind = CardAddressType.fromByte(payload[p]);
    if (kind == null) return null;
    length += 1 + kind.addressLength + 2;
  }
  return length;
}

/// The card's relay list (V4.2 §15.2, §11.9): at most three entries,
/// each a length byte and the relay's address as text, at most 64
/// characters. Owner decision 15.09.2026 ("relay list ≤ 3 × 64").
const int kRelayAtMost = 3;
const int kRelayCharsAtMost = 64;

/// `null` if [r] is fit as a relay entry, otherwise the reason.
///
/// A character is a byte, visible ASCII: §15.2 counts three entries
/// of 64 characters as 195 B (3 × (1 + 64)) — that only works with one byte per
/// character. Spaces and control characters do not occur in an address.
String? relayShortage(String r) {
  if (r.isEmpty) return 'empty relay entry';
  if (r.length > kRelayCharsAtMost) {
    return 'relay entry with ${r.length} characters, at most '
        '$kRelayCharsAtMost';
  }
  for (final c in r.codeUnits) {
    if (c < 0x21 || c > 0x7E) {
      return 'relay entry with character 0x${c.toRadixString(16)} — only '
          'visible ASCII';
    }
  }
  return null;
}

/// Packed length of the list: count byte + per entry length byte + characters.
int relayLength(List<String> relay) =>
    relay.fold(1, (sum, r) => sum + 1 + r.length);

void relayWrite(BytesBuilder output, List<String> relay) {
  output.addByte(relay.length);
  for (final r in relay) {
    output
      ..addByte(r.length)
      ..add(r.codeUnits);
  }
}

/// Reads the list via [read], which itself throws on a read past the end.
/// Count byte > 3, length 0 or > 64 and an inadmissible character
/// reject the WHOLE card (§15.2: "rejected as a whole").
List<String> relayRead(Uint8List Function(int length) read) {
  final number = read(1)[0];
  if (number > kRelayAtMost) {
    throw CardFormatError(
        'relay count $number, at most $kRelayAtMost');
  }
  final relay = <String>[];
  for (var i = 1; i <= number; i++) {
    final length = read(1)[0];
    if (length == 0 || length > kRelayCharsAtMost) {
      throw CardFormatError('relay entry $i with length $length '
          '(allowed 1 to $kRelayCharsAtMost)');
    }
    final r = String.fromCharCodes(read(length));
    final shortage = relayShortage(r);
    if (shortage != null) throw CardFormatError(shortage);
    relay.add(r);
  }
  return List.unmodifiable(relay);
}

/// The length of the list from [offset], only from count and length bytes — for
/// the text reader, which must separate "truncated" from "tampered" without
/// parsing. `null` if the bytes for it are missing or invalid.
int? relaysLengthFrom(Uint8List payload, int offset) {
  if (payload.length <= offset) return null;
  final number = payload[offset];
  if (number > kRelayAtMost) return null;
  var pos = offset + 1;
  for (var i = 0; i < number; i++) {
    if (payload.length <= pos) return null;
    final length = payload[pos];
    if (length == 0 || length > kRelayCharsAtMost) return null;
    pos += 1 + length;
  }
  return pos - offset;
}

/// Computes the fingerprint over [bundle] with [hash] and checks that
/// the result has the expected fingerprint size.
Uint8List fingerprintFrom(Uint8List bundle, CardHashFunction hash) {
  final fp = hash(bundle);
  if (fp.length != kFingerprintLength) {
    throw ArgumentError(
        'Hash function must deliver $kFingerprintLength bytes, '
        'delivered ${fp.length}');
  }
  return fp;
}

/// The three addresses under which a peer can be reachable —
/// what §7.1 calls "up to three addresses of the recipient from the card (§15.2)":
/// LAN (step 1), public (step 2), neighbour (step 3).
///
/// One record instead of three individual values, because the three are ALWAYS
/// needed together: §7.1 starts "every applicable step" simultaneously,
/// and WHICH applies is decided on exactly this record. Whoever passes through a
/// single address rebuilds the narrowing at which steps 2
/// and 3 did not even start until S390
/// (`berichte/S390-EVAL-NACHRICHT.md`, finding B-1).
typedef Routes = ({
  CardAddress? lan,
  CardAddress? public,
  CardAddress? neighbour,
});

/// Not a single direct address ([w] `null` included) — steps 1
/// to 3 then all do not apply, and §8.2 carries alone. An
/// offline recipient is therefore NOT an error (§9.1).
///
/// As a function and not as an extension on [Routes]: the application uses
/// `package:mycelium` under a prefix (`lib/core/service/cleona_service
/// .dart`), and an extension would only be cumbersome to call from there.
bool routesEmpty(Routes? w) =>
    w == null ||
    (w.lan == null && w.public == null && w.neighbour == null);

/// Type byte + address + port (u16 LE). The type byte stands AT THE FRONT so that the
/// reader does not have to guess the length — a guessed one would shift every
/// following field (§15.2 "rejected as a whole").
///
/// ONE codec for card AND memory: until S390 it lay privately in
/// `card.dart`, and the memory could therefore only do IPv4 without a type byte.
void addressWrite(BytesBuilder output, CardAddress address) {
  output
    ..addByte(address.kind.byteValue)
    ..add(address.address)
    ..addByte(address.port & 0xFF)
    ..addByte((address.port >> 8) & 0xFF);
}

/// Flag byte `0x00` (missing) or `0x01` (follows), then the address.
void optionalAddressWrite(BytesBuilder output, CardAddress? address) {
  if (address == null) {
    output.addByte(0);
    return;
  }
  output.addByte(1);
  addressWrite(output, address);
}

/// Reads via [read], which itself throws on a read past the end.
/// An unknown type byte rejects with [CardFormatError]; [fieldName]
/// stands in the message so that the reader knows WHICH address is broken.
CardAddress addressRead(
    Uint8List Function(int length) read, String fieldName) {
  final typeByte = read(1)[0];
  final kind = CardAddressType.fromByte(typeByte);
  if (kind == null) {
    throw CardFormatError(
        'unknown address type for $fieldName: $typeByte (expected '
        '${CardAddressType.ipv4.byteValue} = IPv4 or '
        '${CardAddressType.ipv6.byteValue} = IPv6)');
  }
  final ip = read(kind.addressLength);
  final b = read(2);
  return CardAddress(ip, b[0] | (b[1] << 8));
}

/// Counterpart to [optionalAddressWrite]. Every flag byte except
/// `0x00` and `0x01` rejects — the same "all or nothing" as §15.2.
CardAddress? optionalAddressRead(
    Uint8List Function(int length) read, String fieldName) {
  final flag = read(1)[0];
  if (flag == 1) return addressRead(read, fieldName);
  if (flag != 0) {
    throw CardFormatError(
        'invalid flag for $fieldName: $flag (expected 0 or 1)');
  }
  return null;
}
