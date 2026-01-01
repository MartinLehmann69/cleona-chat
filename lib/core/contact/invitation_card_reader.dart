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
  });

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

/// Reads an invitation from arbitrary text (§15.6, tolerant).
InvitationReading readInvitationText(
  String input, {
  required int ownChannel,
  required int nowUnixSeconds,
}) {
  final Card card;
  try {
    card = outInvitationText(input, expectedChannel: ownChannel);
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
  return _withExpiry(card, nowUnixSeconds);
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
    };
