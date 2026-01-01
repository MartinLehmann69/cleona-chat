/// The pure rules of the recovery bundle (§13.3.4): how long it lies, when it
/// is renewed, which values a search and a renewal ask, the holders a card
/// names, and what the application can find among the bundles read before a
/// renewal (D-103, D-107). The box that sends lives in
/// `mailbox_recovery_bundle.dart`, which exports this file.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/card_address.dart' show CardAddress;
import 'package:mycelium/pair.dart' show dayValue, utcDay;
import 'package:mycelium/post_box_deposit.dart'
    show DayPair, Neighbour, Question, kAtMostAge, kAtMostValues;

/// How long a bundle lies with its holders: the retention of every post-box
/// entry (§8.2, D-6) — nothing longer, a holder cannot tell a bundle apart.
const Duration kBundleLife = kAtMostAge;

/// Renewed at an edge from this age of the last deposit on (E2-a): a device
/// with an edge at least every four days keeps its bundle alive.
const Duration kBundleRenewAfter = Duration(days: 3);

/// The box key pair of UTC day `d` — from the application (E3-a).
typedef BoxKeyFor = DayPair Function(int day);

/// Is a renewal due at [now]? Never before a first deposit took place is it
/// NOT due; a clock set back (last after now) makes it not due.
bool bundleRenewDue(DateTime? last, DateTime now) =>
    last == null || now.difference(last) >= kBundleRenewAfter;

/// The ONE question of a search: the box values of today and the six days
/// before, each with its pair (a holder hands out only against the proof).
List<Question> bundleAsk(BoxKeyFor keyFor, DateTime now) {
  final today = utcDay(now);
  return [
    for (var d = 0; d < kAtMostValues; d++)
      if (keyFor(today - d) case final p) (value: dayValue(p.pk), pair: p),
  ];
}

/// The question before a renewal (§13.3.4): the box values of the days since
/// [last] (the own last deposit), beginning with the day AFTER it (owner
/// 06.11.2026: under the day of the own deposit lies the own bundle, which
/// would be handed out at every renewal), newest first — at most the
/// retention. Empty when no such day has begun.
List<Question> renewAsk(BoxKeyFor keyFor, DateTime last, DateTime now) {
  final today = utcDay(now);
  final from = utcDay(last) + 1;
  return [
    for (var d = today; d >= from && today - d < kAtMostValues; d--)
      if (keyFor(d) case final p) (value: dayValue(p.pk), pair: p),
  ];
}

/// What the application finds among the bundles read before a renewal
/// (§13.3.4, D-103, D-107).
enum BundleFinding {
  /// None continues this device's keys: renew.
  none,

  /// A recovery retired this device: lay and ask nothing any more.
  retired,

  /// One continues these keys while other own devices share the identity: a
  /// sibling changed them, and its key package (§14.7 Type 16) comes with
  /// this device's own collection. Lay nothing now; nothing is deleted.
  behind,
}

/// The holders a card names: its own addresses and its neighbour.
List<Neighbour> cardHolders(List<CardAddress> own, CardAddress? neighbour) => [
      for (final c in [...own, if (neighbour != null) neighbour])
        (InternetAddress.fromRawAddress(Uint8List.fromList(c.address)), c.port),
    ];
