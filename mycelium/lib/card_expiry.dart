/// What a card says about its own expiry — as INFORMATION.
///
/// Why a separate file: `card.dart` is at 377 lines, the
/// line budget of `mycelium/README.md` knows no exception at 400. The
/// cut is not arbitrary but the same as for
/// `group_read.dart`: over there stands how a card is BUILT and PACKED
/// — the format, which is fixed byte by byte; here stands what a
/// reader may conclude from a field of this format. The format changes
/// with a new version, the conclusion with the clock.
///
/// The card format stays untouched. `ablauf` has stood in the card since the second
/// version (`card.dart:317`), it was just never looked at
/// (`berichte/S384-RESTLISTE.md`, point 2.14). The measured sizes
/// 96 / 110 / 146 B and the field order are the same as before.
///
/// NO DECISION. [Card.unpack] still does not throw for an expired
/// card — an expired card must stay readable and
/// displayable, otherwise the UI cannot explain WHAT
/// is going on, and instead of "expired, please get a new card" the user sees
/// only an incomprehensible format problem. This file delivers the
/// information; what happens with it is decided by the caller.
library;

import 'package:mycelium/card.dart';

/// How much remaining validity a card still has before the reader is warned.
///
/// `v42/kap/ch15.md:253-254`: "When less than 7 days of validity remain,
/// reading the card warns ... rather than proceeding without comment."
///
/// Seven days, the same number as the issuer's grace period
/// (`invitation.dart` `kGracePeriodDays`) — but DELIBERATELY a separate
/// constant and not a shared one. These are two different rules at two
/// different places: the grace period says how long the ISSUER still
/// listens; the warning period says from when on the READER had better ask for a new
/// card. That both are seven days today is an agreement
/// of the document, not a derivation — a shared constant would
/// claim that one follows from the other.
const int kWarningPeriodDays = 7;

/// Seconds of the warning period.
const int kWarningPeriodSeconds = kWarningPeriodDays * 86400;

/// What the clock says about a card.
enum ExpiryState {
  /// Valid, and for longer than [kWarningPeriodDays] days.
  valid,

  /// Still valid, but for fewer than [kWarningPeriodDays] days — the reader is
  /// warned, not prevented.
  expiresSoon,

  /// The expiry time is past. The card stays readable.
  expired,

  /// `0xFFFFFFFF` — valid indefinitely (`v42/kap/ch15.md:236`). Never
  /// expires and never warns.
  unlimited,
}

extension CardExpiry on Card {
  /// Does the card carry the unlimited validity `0xFFFFFFFF`?
  bool get unlimitedValid => expiryUnixSeconds == Card.expiryMax;

  /// The information. [nowUnixSeconds] is passed in instead of fetched
  /// from the clock itself, so that a test hits every edge without waiting.
  ExpiryState expiryStateAt(int nowUnixSeconds) {
    if (unlimitedValid) return ExpiryState.unlimited;
    if (nowUnixSeconds > expiryUnixSeconds) return ExpiryState.expired;
    if (expiryUnixSeconds - nowUnixSeconds < kWarningPeriodSeconds) {
      return ExpiryState.expiresSoon;
    }
    return ExpiryState.valid;
  }

  /// Is the expiry time past?
  bool isExpiredAt(int nowUnixSeconds) =>
      expiryStateAt(nowUnixSeconds) == ExpiryState.expired;

  /// Is it still valid, but expires in fewer than [kWarningPeriodDays] days?
  /// Deliberately separate from [isExpiredAt]: these are two different
  /// pieces of information, and a UI says two different
  /// sentences for them.
  bool expiresSoonAt(int nowUnixSeconds) =>
      expiryStateAt(nowUnixSeconds) == ExpiryState.expiresSoon;

  /// How many seconds remain. Null for unlimited validity, 0 for
  /// an expired card (never negative — "expired since when" is
  /// a different question and stands in [overdueSecondsAt]).
  int? remainingSecondsAt(int nowUnixSeconds) {
    if (unlimitedValid) return null;
    final rest = expiryUnixSeconds - nowUnixSeconds;
    return rest > 0 ? rest : 0;
  }

  /// How long the card has already been expired; 0 as long as it is valid. The
  /// number that the issuer needs to judge its grace period.
  int overdueSecondsAt(int nowUnixSeconds) {
    if (unlimitedValid) return 0;
    final route = nowUnixSeconds - expiryUnixSeconds;
    return route > 0 ? route : 0;
  }
}
