/// The contact card — what stands in the QR when someone invites. In the
/// norm: the invitation data (V4.2 §15.2, field table).
///
/// SIXTH VERSION (S406, E-3 A+A1, owner decision 07.10.2026): the
/// publisher-key flag and the publisher key (0 or 32 B) between the
/// neighbour address and the relay count, version byte `0x02`. A card of
/// version `0x01` is rejected as "unknown card version" before any other
/// field is read — no partial read (§15.2).
///
/// History in brief: the first version carried the complete keys and a
/// signature (6543 B, fits no QR); since the second it carries only what
/// a reader needs to REACH the issuer and send it something sealed —
/// letter key (32 B, the invitation's own X25519, R-b), fingerprint
/// (32 B, the identifier, survives every KEM rotation; the bundle is
/// matched against it, [matchesIdentifier]), addresses, a code (16 B) and
/// the expiry. The third added [channel], a type byte per address and
/// [difficulty]; the fourth the [relay] list (§11.9); the fifth (S390)
/// ONE list of own addresses in the issuer's order of preference (the
/// reader classifies them, `address_class.routesFromCard`); the sixth the
/// [publisherKey]. Address and relay codec: `card_address.dart`.
///
/// Sizes of the packed format (§15.2: 91 / 98 / 413), measured by
/// `test/smoke_card_publisher.dart` (text form) and the app smoke
/// `test/smoke/smoke_invitation_card_reader.dart` (QR version, level M):
///
/// | Case                                     | Card  | `cleona:1:` | QR M |
/// |------------------------------------------|-------|-------------|------|
/// | no address (CGNAT), no key, no relays    |  91 B |         133 | V6   |
/// | one own IPv4, no key, no relays          |  98 B |         143 | V6   |
/// | 4x IPv6 + neighbour + key + 3 relays     | 413 B |         563 | V16  |
///
/// The text form computes `ceil(n x 4 / 3)` base64url characters plus 9 for
/// the prefix (`card_text.dart`). The QR carries the BINARY form.
///
/// NO SIGNATURE. The card travels over a visible channel (Bob's
/// screen); a signature from a key whose fingerprint stands in
/// the same card secures nothing additional. The binding is provided by
/// matching the later received bundle against the fingerprint
/// ([matchesIdentifier]).
///
/// This file deliberately depends on nothing but `dart:core`, `dart:typed_data`
/// and `dart:convert` (base64url) — no FFI, no crypto library,
/// so that it stays testable without the native libs.
///
/// OPEN SEAM: [fingerprintFrom] needs a SHA-256 function from
/// outside; [Card.matchesIdentifier] only compares bytes. `package:crypto`
/// is NOT directly in `mycelium/pubspec.yaml` (only transitively via the
/// `cleona` dependency) — therefore this file passes the choice of the
/// hash function through to the caller as a callback ([CardHashFunction]).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mycelium/card_address.dart' as addr;
import 'package:mycelium/card_address.dart';

/// Thrown for every card that cannot be cleanly unpacked —
/// truncated, wrong version byte, invalid flag, unknown
/// address type, invalid relay list, surplus bytes at the end.
export 'package:mycelium/card_address.dart';

class Card {
  /// Version byte at the front of the packed format (§15.2: `0x02`, owner
  /// decision 07.10.2026, E-3 A1). Any other value rejects the whole card.
  static const int version = 2;

  /// Channel "live" — the value that a card from the live network carries.
  static const int channelLive = kChannelLive;

  /// Channel "beta".
  static const int channelBeta = kChannelBeta;

  /// Bob's letter key X25519, public. 32 B is the standard size
  /// of an X25519 key — see comment
  /// `lib/core/crypto/per_message_kem.dart:17` ("32 bytes — X25519
  /// ephemeral pubkey"), not named as a constant of its own in the code.
  static const int letterKeyLength = 32;

  /// SHA-256 digest size (FIPS 180-4), standard size — no own
  /// hash implementation in this file, see "OPEN SEAM".
  static const int fingerprintLength = kFingerprintLength;

  /// Random bytes of the code (spam protection).
  static const int codeLength = 16;

  /// Expiry time as u32 LE — upper limit for the Unix seconds that
  /// can be stored in 4 bytes (year 2106).
  static const int expiryMax = 0xFFFFFFFF;

  /// Default difficulty of an invitation to a SINGLE person: 20
  /// leading zero bits. Openly distributed invitations set it higher
  /// (`lib/invitation.dart`: `kDifficultySingleUse` 20, `kDifficultyOpen`
  /// 22). The card carries only the NUMBER, not the invitation kind.
  static const int difficultyDefault = 20;

  /// At most this many relays does a card carry (§15.2).
  static const int relayAtMost = kRelayAtMost;

  /// The publisher key: the x-only secp256k1 key under which the issuing
  /// device publishes its address record (§11.9, BIP-340: 32 B).
  static const int publisherKeyLength = 32;

  /// Size of the packed format without the own addresses, the neighbour
  /// address, the publisher key and the relay list — version(1) +
  /// channel(1) + letter key(32) + fingerprint(32) + neighbour flag(1) +
  /// publisher-key flag(1) + difficulty(1) + code(16) + expiry(4) = 89 B.
  /// Added to that are the address list (at least 1 B count byte), with
  /// flag=1 the neighbour address (7 or 19 B), with flag=1 the publisher key
  /// (32 B) and the relay list (at least 1 B) — together at least 91 B
  /// (§15.2).
  static const int bodyLength =
      1 + 1 + letterKeyLength + fingerprintLength + 1 + 1 + 1 + codeLength + 4;

  /// For error messages: a nameable name instead of a bare number.
  static String channelName(int channelNo) => addr.channelName(channelNo);

  /// 0x00 = live, 0x01 = beta. A beta card in the live app (and
  /// vice versa) is rejected immediately — see [CardChannelError].
  final int channel;

  final Uint8List letterKeyX25519;
  final Uint8List fingerprint;
  /// The addresses under which the issuer is reachable — at most
  /// [kOwnAddressesAtMost], **in its order of preference** (§15.2,
  /// §22.6: cable, Wi-Fi and VPN before cellular).
  ///
  /// ── WHY NO ROLES STAND HERE ANY MORE ────────────────────────────
  ///
  /// Until S390 these were two fields: `lanAdresse` (mandatory) and
  /// `oeffentlicheAdresse` (optional). That forced a node with a global
  /// IPv6 AND a segment-local IPv4 into a choice that nobody had decided
  /// — the format had simply arisen before dual stack.
  ///
  /// The second point weighed heavier: the classification stood IN the card. But whether an
  /// address is segment-local is a fact about the READER, not
  /// about the issuer — whether its `192.168.1.5` lies in your segment
  /// is decided by your segment. A classification written along was thus
  /// a second truth that could be wrong already at the reader's next network change.
  /// It falls without replacement; classifying is done by
  /// `address_class.dart` (`routesFromCard`), where `outTheSegment` is used.
  ///
  /// Empty is allowed and means something: a device in cellular behind
  /// CGNAT has no address that is of use to another (§15.2, count byte
  /// `0`). It says so instead of inventing one.
  final List<CardAddress> ownAddresses;

  /// A neighbour via which Bob is reachable — needed when Bob is not directly
  /// reachable behind NAT/CGNAT and the public address is
  /// therefore worthless — an ordinary node that both sides
  /// reach (V4.2 §11.7: no node has a special role).
  final CardAddress? neighbourAddress;

  /// The relays that the issuer knows (§11.9) — at most three, each
  /// at most 64 characters of visible ASCII. A hint for the reader's source 4
  /// (§11.8), no delivery information. Immutable.
  final List<String> relay;

  /// The issuer's publisher key (§15.2, §11.9) — set only while the issuing
  /// device actually publishes its address record; `null` = flag `0x00`. A
  /// reader whose card addresses no longer answer looks the current ones up
  /// under it (`publisher_lookup.dart`).
  final Uint8List? publisherKey;

  /// Leading zero bits that a proof of work must have before the
  /// holder of this card even looks at a request.
  final int difficulty;

  final Uint8List code;

  /// Expiry time as u32 LE Unix seconds; [expiryMax] (`0xFFFFFFFF`)
  /// means unlimited. What it means is answered by `card_expiry.dart` —
  /// only the field stands here. This class NEVER compares it with a clock:
  /// a format that could be unpacked differently depending on the time of day would be
  /// no format.
  final int expiryUnixSeconds;

  Card({
    this.channel = channelLive,
    required Uint8List letterKeyX25519,
    required Uint8List fingerprint,
    List<CardAddress> ownAddresses = const [],
    this.neighbourAddress,
    Uint8List? publisherKey,
    List<String> relay = const [],
    this.difficulty = difficultyDefault,
    required Uint8List code,
    required this.expiryUnixSeconds,
  })  : letterKeyX25519 = Uint8List.fromList(letterKeyX25519),
        fingerprint = Uint8List.fromList(fingerprint),
        ownAddresses = List.unmodifiable(ownAddresses),
        relay = List.unmodifiable(relay),
        publisherKey =
            publisherKey == null ? null : Uint8List.fromList(publisherKey),
        code = Uint8List.fromList(code) {
    if (channel != channelLive && channel != channelBeta) {
      throw ArgumentError(
          'channel must be $channelLive (live) or $channelBeta (beta), was $channel');
    }
    if (this.letterKeyX25519.length != letterKeyLength) {
      throw ArgumentError(
          'letterKeyX25519 must be $letterKeyLength bytes long, was ${this.letterKeyX25519.length}');
    }
    if (this.fingerprint.length != fingerprintLength) {
      throw ArgumentError(
          'fingerprint must be $fingerprintLength bytes long, was ${this.fingerprint.length}');
    }
    if (this.ownAddresses.length > kOwnAddressesAtMost) {
      throw ArgumentError('at most $kOwnAddressesAtMost own '
          'addresses, got ${this.ownAddresses.length}');
    }
    final pk = this.publisherKey;
    if (pk != null && pk.length != publisherKeyLength) {
      throw ArgumentError(
          'publisherKey must be $publisherKeyLength bytes long, was ${pk.length}');
    }
    if (this.relay.length > relayAtMost) {
      throw ArgumentError(
          'at most $relayAtMost relays, got ${this.relay.length}');
    }
    for (final r in this.relay) {
      final shortage = relayShortage(r);
      if (shortage != null) throw ArgumentError(shortage);
    }
    if (difficulty < 0 || difficulty > 0xFF) {
      throw ArgumentError(
          'difficulty must be between 0 and 255 (one byte), was $difficulty');
    }
    if (this.code.length != codeLength) {
      throw ArgumentError(
          'code must be $codeLength bytes long, was ${this.code.length}');
    }
    if (expiryUnixSeconds < 0 || expiryUnixSeconds > expiryMax) {
      throw ArgumentError(
          'expiryUnixSeconds must be between 0 and $expiryMax (u32), was $expiryUnixSeconds');
    }
  }

  /// The size that [pack] will return — without packing.
  int get packedLength =>
      bodyLength +
      addressesLength(ownAddresses) +
      (neighbourAddress?.packedLength ?? 0) +
      (publisherKey?.length ?? 0) +
      relayLength(relay);

  /// Checks the identifier of a bundle received later over the network and
  /// checked BEFOREHAND for its signature against the fingerprint of
  /// this card. The identifier is computed by `Address.identifier`; this file
  /// stays without crypto. Without a prior signature check a match says
  /// nothing about the KEM part (`bundle.dart`).
  bool matchesIdentifier(Uint8List identifier) =>
      _bytesEqual(identifier, fingerprint);

  /// Packs the card into a compact binary format.
  Uint8List pack() {
    final output = BytesBuilder();
    output.addByte(version);
    output.addByte(channel);
    output.add(letterKeyX25519);
    output.add(fingerprint);
    addressesWrite(output, ownAddresses);
    optionalAddressWrite(output, neighbourAddress);
    final pk = publisherKey;
    output.addByte(pk == null ? 0 : 1);
    if (pk != null) output.add(pk);
    relayWrite(output, relay);
    output.addByte(difficulty);
    output.add(code);
    output.add(_u32le(expiryUnixSeconds));
    return output.toBytes();
  }

  /// Unpacks a card from [bytes]. Throws [CardFormatError] on
  /// truncated data, data with an unknown version, an invalid flag,
  /// an unknown address type or an invalid relay list, or
  /// overlong data — and [CardChannelError] if the card is formally
  /// in order but carries a different channel than [expectedChannel].
  ///
  /// An EXPIRED card does NOT throw here: it must stay readable and displayable,
  /// otherwise instead of "expired, please ask for a new one"
  /// the user only sees a format problem. The verdict is given by `card_expiry.dart`.
  static Card unpack(Uint8List bytes, {int expectedChannel = channelLive}) {
    var pos = 0;

    Uint8List read(int length) {
      if (length < 0 || pos + length > bytes.length) {
        throw CardFormatError(
            'Card is truncated: expected $length bytes from position $pos, '
            'only ${bytes.length - pos} present');
      }
      final chunk = Uint8List.fromList(
          Uint8List.sublistView(bytes, pos, pos + length));
      pos += length;
      return chunk;
    }

    int u32() {
      final b = read(4);
      return b[0] | (b[1] << 8) | (b[2] << 16) | (b[3] << 24);
    }

    // Addresses are read by `card_address.dart` — the same codec that the
    // memory also uses. A guessed address type shifts every
    // following field, therefore it rejects the WHOLE card.
    CardAddress? optionalAddress(String fieldName) =>
        optionalAddressRead(read, fieldName);

    final readVersion = read(1)[0];
    if (readVersion != version) {
      throw CardFormatError(
          'unknown card version: $readVersion (expected $version)');
    }
    final readChannel = read(1)[0];
    if (readChannel != expectedChannel) {
      throw CardChannelError(readChannel, expectedChannel);
    }
    final letterKeyX25519 = read(letterKeyLength);
    final fingerprint = read(fingerprintLength);
    final ownAddresses = addressesRead(read);
    final neighbourAddress = optionalAddress('neighbour address');
    final publisherFlag = read(1)[0];
    if (publisherFlag != 0 && publisherFlag != 1) {
      throw CardFormatError(
          'invalid flag for publisher key: $publisherFlag (expected 0 or 1)');
    }
    final publisherKey = publisherFlag == 1 ? read(publisherKeyLength) : null;
    final relay = relayRead(read);

    final difficulty = read(1)[0];
    final code = read(codeLength);
    final expiry = u32();

    if (pos != bytes.length) {
      throw CardFormatError(
          'card has ${bytes.length - pos} surplus bytes at the end');
    }

    return Card(
      channel: readChannel,
      letterKeyX25519: letterKeyX25519,
      fingerprint: fingerprint,
      ownAddresses: ownAddresses,
      neighbourAddress: neighbourAddress,
      publisherKey: publisherKey,
      relay: relay,
      difficulty: difficulty,
      code: code,
      expiryUnixSeconds: expiry,
    );
  }

  /// The text form for the QR code: base64url of the packed card.
  String asText() => base64Url.encode(pack());

  /// Kehrwert von [asText].
  static Card outText(String text, {int expectedChannel = channelLive}) =>
      Card.unpack(base64Url.decode(text), expectedChannel: expectedChannel);

  /// Compares two cards by content (all fields byte by byte), for tests.
  bool contentEqual(Card other) {
    bool addressEqual(CardAddress? a, CardAddress? b) =>
        (a == null && b == null) || (a != null && b != null && a.equal(b));

    return channel == other.channel &&
        _bytesEqual(letterKeyX25519, other.letterKeyX25519) &&
        _bytesEqual(fingerprint, other.fingerprint) &&
        ownAddresses.length == other.ownAddresses.length &&
        [
          for (var i = 0; i < ownAddresses.length; i++)
            ownAddresses[i].equal(other.ownAddresses[i])
        ].every((x) => x) &&
        addressEqual(neighbourAddress, other.neighbourAddress) &&
        ((publisherKey == null && other.publisherKey == null) ||
            (publisherKey != null &&
                other.publisherKey != null &&
                _bytesEqual(publisherKey!, other.publisherKey!))) &&
        relay.join('\n') == other.relay.join('\n') &&
        relay.length == other.relay.length &&
        difficulty == other.difficulty &&
        _bytesEqual(code, other.code) &&
        expiryUnixSeconds == other.expiryUnixSeconds;
  }
}

Uint8List _u32le(int value) {
  final b = ByteData(4)..setUint32(0, value, Endian.little);
  return b.buffer.asUint8List();
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
