/// The contact card — what stands in the QR when someone invites.
///
/// FOURTH VERSION (relay list, S388). The version byte stays at 1 because
/// nothing has shipped yet and consequently there is no card out there
/// that carries an earlier version. Spec: V4.2 §15.2.
///
/// The first version carried the complete keys (Ed25519 +
/// ML-DSA-65 + X25519 + ML-KEM-768) and a signature over them — 6543/6549
/// bytes, fits into no QR code. The layout since the second version
/// carries only what Alice needs to REACH Bob and IMMEDIATELY send him something
/// encrypted:
///
///  1. Bob's X25519 (32 B) at the time of the card — since E1 NOT for
///     sealing: it changes every 7 d, the card is valid 90 d
///  2. The fingerprint (32 B) = Bob's identifier, `Address.identifier`, only
///     over the signing part — the card survives every KEM rotation.
///     The bundle later travels SIGNED over the network; after the
///     signature its identifier is checked here ([matchesIdentifier])
///  3. Three addresses: LAN address (mandatory), public address
///     (optional) and neighbour address (optional) — a neighbour via which
///     Bob is reachable when he is not directly reachable behind NAT/CGNAT
///     and the public address is therefore worthless
///  4. A code: 16 random bytes + expiry time (Unix seconds, u32 LE)
///     — spam protection, nothing else
///
/// The third version added [channel] (0x00 live, 0x01 beta, every
/// other value rejects, [CardChannelError]), one type byte before each
/// address (4/6; an unknown type rejects the WHOLE card, a
/// guessed length would shift every following field) and [difficulty] (1 B,
/// leading zero bits of the proof of work — the reader must know it).
///
/// The fourth version adds [relay] (§11.9): count byte (0–3) and per
/// entry length byte (1–64) + address as text, behind the neighbour address.
/// Codec in `card_address.dart`.
///
/// The fifth version (S390) replaces LAN and public address with
/// ONE list of own addresses with count byte (0-4), in the
/// issuer's order of preference. The roles go away: which address
/// is segment-local is computed by the READER (`address_class.routesFromCard`).
///
/// Measured sizes of the packed format (§15.2: 90 / 97 / 380):
///
/// | Case                             | Card  | + 2 B checksum   | + prefix  |
/// |----------------------------------|-------|------------------|-----------|
/// | no address (CGNAT), no relays    |  90 B |             92 B |       132 |
/// | one own IPv4, no relays          |  97 B |             99 B |       141 |
/// | 4x IPv6 + neighbour + 3 relays   | 380 B |            382 B |       519 |
///
/// The text form computes `ceil(n x 4 / 3)` base64url characters plus 9 for
/// `cleona:1:`. The QR carries the BINARY form: at error correction M
/// version 6 (41x41) for the smallest and version 15 (77x77) for the
/// largest card (measured 16.09.2026, §15.2).
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
  /// Version byte at the front of the packed format. Stays at 1: nothing has
  /// shipped yet, so there is no card of an older version out there.
  static const int version = 1;

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

  /// Size of the packed format without the own addresses, without the
  /// neighbour address and without the relay list — version(1) + channel(1) +
  /// letter key(32) + fingerprint(32) + neighbour flag(1) +
  /// difficulty(1) + code(16) + expiry(4) = 88 B. Added to that are the
  /// address list (at least 1 B count byte), with flag=1 the neighbour address
  /// (7 or 19 B) and the relay list (at least 1 B) — together
  /// at least 90 B (§15.2).
  static const int bodyLength = 1 + 1 + letterKeyLength + fingerprintLength + 1 + 1 + codeLength + 4;

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
    List<String> relay = const [],
    this.difficulty = difficultyDefault,
    required Uint8List code,
    required this.expiryUnixSeconds,
  })  : letterKeyX25519 = Uint8List.fromList(letterKeyX25519),
        fingerprint = Uint8List.fromList(fingerprint),
        ownAddresses = List.unmodifiable(ownAddresses),
        relay = List.unmodifiable(relay),
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
