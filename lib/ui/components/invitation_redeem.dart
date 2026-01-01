/// Read and redeem a foreign invitation card — the ONE sequence for
/// paste (FAB dialog), QR scan, deep link and Android share.
///
/// Reading happens BEFORE sending in this process (§15.2/§15.3: channel and
/// expiry "before any packet leaves"); redeeming happens via the
/// service interface. The service checks the same card with the same
/// function once more — between display and press a card can
/// expire.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:cleona/core/contact/invitation_card_reader.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/ui/components/invitation_messages.dart';

class InvitationRedeem {
  InvitationRedeem._();

  static InvitationReading readText(String text) => readInvitationText(text,
      ownChannel: ownInvitationChannel(),
      nowUnixSeconds: invitationNowUnixSeconds());

  static InvitationReading readBytes(Uint8List packed) =>
      readInvitationBytes(packed,
          ownChannel: ownInvitationChannel(),
          nowUnixSeconds: invitationNowUnixSeconds());

  /// Does the finding carry a card — even an expired one or one from
  /// the other network? Then the UI shows it with its reason
  /// instead of scanning on.
  static bool isCard(InvitationReading r) =>
      r.ok ||
      r.error == InvitationReadError.expired ||
      r.error == InvitationReadError.wrongChannel;

  /// The sentence for the finding, `null` if the card is redeemable.
  static String? errorOf(AppLocale l, InvitationReading r) => r.ok
      ? null
      : invitationReadErrorText(l, r.error!, cardChannel: r.cardChannel);

  /// Sends the request and reports the outcome. [messenger], [locale]
  /// and [errorColor] are fetched by the caller BEFORE any `await` — a
  /// BuildContext must not cross an asynchronous gap.
  ///
  /// Exactly one of [text] and [packed] is set. An error of the
  /// interface is NOT caught: it belongs in the log, not in
  /// a message that says "failed" and conceals the reason.
  static Future<bool> send({
    required ICleonaService service,
    required ScaffoldMessengerState? messenger,
    required AppLocale locale,
    required Color errorColor,
    String? text,
    Uint8List? packed,
  }) async {
    assert((text == null) != (packed == null));
    final r = text != null
        ? await service.redeemInvitationText(text)
        : await service.redeemInvitationCardBytes(packed!);
    final ok = r.outcome == InvitationRedeemOutcome.requestSent;
    messenger?.showSnackBar(SnackBar(
      backgroundColor: ok ? null : errorColor,
      content: Text(invitationRedeemText(locale, r)),
    ));
    return ok;
  }
}
