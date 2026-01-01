/// Sentences for the invitation card (V4.2 §15.2, §15.3, §15.6) — ONE place.
///
/// Every finding, every refusal and every outcome has exactly one sentence. The
/// UI names the reason and does not guess one; §15.6 assigns each of the
/// five read findings its own advice, §15.2 demands for the
/// foreign channel a sentence that names the channel, §15.3 for the
/// expired card "ask for a fresh one".
library;

import 'dart:typed_data';

import 'package:cleona/core/config/network_channel.dart';
import 'package:cleona/core/contact/invitation_card_reader.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/invitation_card_types.dart';
import 'package:cleona/core/util/hex.dart' show bytesToHex;

/// Channel byte of this app (§15.2).
int ownInvitationChannel() => invitationChannelByte(
    isBeta: activeNetworkChannel == NetworkChannel.beta);

int invitationNowUnixSeconds() =>
    DateTime.now().millisecondsSinceEpoch ~/ 1000;

String invitationReadErrorText(AppLocale l, InvitationReadError e,
    {int? cardChannel}) {
  final own = ownInvitationChannel();
  return switch (e) {
    InvitationReadError.notFound => l.get('card_err_not_found'),
    InvitationReadError.truncated => l.get('card_err_truncated'),
    InvitationReadError.corrupted => l.get('card_err_corrupted'),
    InvitationReadError.wrongVersion => l.get('card_err_wrong_version'),
    InvitationReadError.badCharacters => l.get('card_err_bad_characters'),
    InvitationReadError.wrongChannel => l.tr('card_err_wrong_channel', {
        // Without a reported channel it can only be the other of the two —
        // §15.2 knows exactly two values, every third is `wrongVersion`.
        'card': invitationChannelName(cardChannel ?? (own == 0 ? 1 : 0)),
        'own': invitationChannelName(own),
      }),
    InvitationReadError.expired => l.get('card_err_expired'),
  };
}

String invitationIssueRefusalText(AppLocale l, InvitationIssueRefusal r) =>
    switch (r) {
      InvitationIssueRefusal.notConnected => l.get('card_not_connected'),
      InvitationIssueRefusal.capReached =>
        l.tr('card_cap_reached', {'max': '$kInvitationStandingCap'}),
      InvitationIssueRefusal.otherIdentityStanding =>
        l.get('card_other_identity'),
      InvitationIssueRefusal.failed => l.get('card_issue_failed'),
    };

String invitationRedeemText(AppLocale l, InvitationRedeemResult r) =>
    switch (r.outcome) {
      InvitationRedeemOutcome.requestSent => l.get('contact_request_sent'),
      InvitationRedeemOutcome.readError => invitationReadErrorText(
          l, r.readError ?? InvitationReadError.notFound,
          cardChannel: r.cardChannel),
      InvitationRedeemOutcome.ownCard => l.get('card_err_own'),
      InvitationRedeemOutcome.alreadyContact =>
        l.get('card_err_already_contact'),
      InvitationRedeemOutcome.noAnswer => l.get('card_err_no_answer'),
      InvitationRedeemOutcome.notConnected => l.get('card_not_connected'),
      InvitationRedeemOutcome.failed => l.get('card_redeem_failed'),
    };

/// "Valid until …" or "Valid indefinitely" (§15.3, `0xFFFFFFFF`).
String invitationExpiryText(AppLocale l, int expiryUnixSeconds) {
  if (expiryUnixSeconds == kInvitationExpiryUnlimited) {
    return l.get('card_valid_unlimited');
  }
  final d = DateTime.fromMillisecondsSinceEpoch(expiryUnixSeconds * 1000)
      .toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return l.tr('card_valid_until', {
    'date': '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}',
  });
}

/// §15.3: „expires in X days — an answer may no longer be possible".
String invitationExpiryWarning(AppLocale l, int daysLeft) =>
    l.tr('card_warn_expires_soon', {'n': '$daysLeft'});

/// The first 8 bytes of the identifier, in groups of four — for comparing
/// over a second channel, not for typing.
String invitationFingerprintText(AppLocale l, Uint8List fingerprint) {
  final hex = bytesToHex(
      Uint8List.sublistView(fingerprint, 0, fingerprint.length.clamp(0, 8)));
  final groups = <String>[
    for (var i = 0; i < hex.length; i += 4)
      hex.substring(i, (i + 4).clamp(0, hex.length)),
  ];
  return l.tr('card_fingerprint', {'fp': groups.join(' ')});
}
