/// READING an invitation card — before any packet (V4.2 §15.2, §15.3, §15.6).
///
/// Why this file stands in the app and not only in the seam: §15.3
/// requires that an expired card is rejected "before any packet leaves"
/// with its own sentence, and that one expiring soon warns on READING.
/// The UI must be able to show that before the user presses "Send" — on
/// the desktop, that is, in the GUI process, which has no delivery layer.
/// The service uses the same function when redeeming; there is thus ONE
/// place that turns a text into a finding.
///
/// Pure: no network, no clock (the time is passed in), no channel access
/// (the own channel is passed in). The format work is done by `mycelium`
/// (`card_text.dart`, `card.dart`, `card_expiry.dart`); here it is only
/// translated.
library;

import 'dart:typed_data';

import 'package:cleona/core/service/invitation_card_types.dart';
import 'package:mycelium/bundle.dart' show lineBundleFits;
import 'package:mycelium/card.dart';
import 'package:mycelium/card_expiry.dart';
import 'package:mycelium/card_text.dart';

/// The finding. Either [error] is set, or [card].
class InvitationReading {
  const InvitationReading._({
    this.card,
    this.error,
    this.cardChannel,
    this.daysLeft,
    this.pkInv,
    this.keyBundle,
    this.lineSignature,
    this.lineChain,
  });

  /// The line's Ed25519 signature (T-a) — the join re-forms the line with it.
  final Uint8List? lineSignature;

  /// The issuer's rotation chain in wire form (§15.6, D-33) — the join
  /// re-forms the line with it; one byte (count 0) while it never rotated.
  final Uint8List? lineChain;

  /// From a `cleona:2:` line (proposal E, `card_text.dart`): `pk_inv` and
  /// the issuer's key bundle; both `null` for `cleona:1:`, QR and NFC.
  final Uint8List? pkInv;
  final Uint8List? keyBundle;

  /// The card that was read — also set for [InvitationReadError.expired],
  /// so that the UI can explain WHAT has expired
  /// (`card.dart`: "An EXPIRED card does NOT throw here").
  final Card? card;

  final InvitationReadError? error;

  /// For [InvitationReadError.wrongChannel]: the channel of the card.
  final int? cardChannel;

  /// Set if fewer than `kWarningPeriodDays` remain (§15.3): the
  /// rounded-up number of remaining days, at least 1.
  final int? daysLeft;

  bool get ok => error == null;
  bool get expiresSoon => daysLeft != null;
}

/// Channel byte of the card for the channel of this app (§15.2: `0x00` live,
/// `0x01` beta). [isBeta] comes from the caller (`activeNetworkChannel`),
/// so that this file stays without `dart:io`.
int invitationChannelByte({required bool isBeta}) =>
    isBeta ? Card.channelBeta : Card.channelLive;

/// The name of a channel byte for the message from §15.2 ("this invitation
/// belongs to the beta network"). Technical term, not translated.
String invitationChannelName(int channel) =>
    channel == Card.channelBeta ? 'Beta' : 'Live';

/// Reads an invitation from arbitrary text (§15.6, tolerant). [verify] checks
/// the signature of a `cleona:2:` line (T-a) — passed by whoever redeems; the
/// reading for display passes none and stays without a crypto library.
InvitationReading readInvitationText(
  String input, {
  required int ownChannel,
  required int nowUnixSeconds,
  LineVerify? verify,
}) {
  final CardLine line;
  try {
    line = outInvitationLine(input,
        expectedChannel: ownChannel, verify: verify);
  } on CardTextError catch (e) {
    if (e.kind == CardTextErrorKind.wrongVersion) {
      // `outInvitationText` deliberately reports a foreign channel as
      // `wrongVersion` (card_text.dart: "Deliberately NO sixth error
      // kind"). §15.2, however, requires a sentence that NAMES the channel.
      // The decision is made not on the message text but on the format: if
      // the same text can be read without error in the OTHER channel, the
      // card is formally valid and belongs there.
      final other =
          ownChannel == Card.channelLive ? Card.channelBeta : Card.channelLive;
      try {
        outInvitationText(input, expectedChannel: other);
        return InvitationReading._(
            error: InvitationReadError.wrongChannel, cardChannel: other);
      } on CardTextError {
        // really a different version
      }
    }
    return InvitationReading._(error: _fromKind(e.kind));
  }
  // §15.6 "altered": whoever redeems (a verifier is passed) also checks that
  // the bundle founds the fingerprint or its chain leads there (D-33).
  if (verify != null && !lineBundleFits(line)) {
    return InvitationReading._(
        error: _fromKind(CardTextErrorKind.badSignature));
  }
  final r = _withExpiry(line.card, nowUnixSeconds);
  // A `cleona:2:` line (proposal E) also carries pk_inv and the key bundle —
  // the join then needs no bundle round trip.
  return line.bundle == null
      ? r
      : InvitationReading._(
          card: r.card,
          error: r.error,
          daysLeft: r.daysLeft,
          pkInv: line.pkInv,
          keyBundle: line.bundle,
          lineSignature: line.signature,
          lineChain: line.chain);
}

/// Reads a packed card (QR binary form, NFC record, §15.2).
InvitationReading readInvitationBytes(
  Uint8List packed, {
  required int ownChannel,
  required int nowUnixSeconds,
}) {
  try {
    return _withExpiry(
        Card.unpack(packed, expectedChannel: ownChannel), nowUnixSeconds);
  } on CardChannelError catch (e) {
    return InvitationReading._(
        error: InvitationReadError.wrongChannel,
        cardChannel: e.readChannel);
  } on CardFormatError {
    // §15.2: "A card is rejected as a whole" — without a checksum,
    // truncated cannot be separated from altered (§15.6 applies to the
    // text form). The binary form from a QR code has the error correction
    // of the QR code behind it; what fails here is a foreign version.
    return const InvitationReading._(error: InvitationReadError.wrongVersion);
  }
}

InvitationReading _withExpiry(Card card, int now) {
  switch (card.expiryStateAt(now)) {
    case ExpiryState.expired:
      return InvitationReading._(
          card: card, error: InvitationReadError.expired);
    case ExpiryState.expiresSoon:
      final rest = card.remainingSecondsAt(now) ?? 0;
      final tage = (rest + 86399) ~/ 86400;
      return InvitationReading._(card: card, daysLeft: tage < 1 ? 1 : tage);
    case ExpiryState.valid:
    case ExpiryState.unlimited:
      return InvitationReading._(card: card);
  }
}

InvitationReadError _fromKind(CardTextErrorKind kind) => switch (kind) {
      CardTextErrorKind.notFound => InvitationReadError.notFound,
      CardTextErrorKind.truncated => InvitationReadError.truncated,
      CardTextErrorKind.tampered => InvitationReadError.corrupted,
      CardTextErrorKind.wrongVersion => InvitationReadError.wrongVersion,
      CardTextErrorKind.brokenChars => InvitationReadError.badCharacters,
      CardTextErrorKind.badSignature => InvitationReadError.altered,
    };
