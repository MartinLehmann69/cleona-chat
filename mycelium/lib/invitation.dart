import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:mycelium/invitation_buffer.dart';
import 'package:mycelium/card.dart' show Card, CardAddress;

/// [RequestBuffer], [WaitingRequest], [LoadedRequest] and the two
/// buffer limits stand in `invitation_buffer.dart` (reasoning for the
/// cut in its header) and are re-exported from here: every
/// caller still imports only `package:mycelium/invitation.dart`.
export 'package:mycelium/invitation_buffer.dart';

/// What the inviter knows about its own invitations.
///
/// This file knows no network and no card — it only holds the
/// state that the issuer enforces. The other side learns
/// nothing of it: the kind does NOT stand in the card, only the code and the
/// difficulty.

/// The two kinds that the user chooses when issuing.
enum Kind {
  /// A specific person. Consumed after the first ACCEPTED request.
  singleUse,

  /// Distributed to a group. Up to [Invitation.atMost] acceptances
  /// or until expiry.
  open,
}

/// Why a request did not get through. The caller decides what
/// of it leaks outside: a failed code check stays silent,
/// an authorised request declined by the user is
/// answered.
enum Rejection {
  unknownCode,
  expired,
  consumed,
  revoke,
}

/// Defaults. The deadlines differ deliberately: a publicly
/// distributed invitation stays visible longer than its occasion.
const int kDaysSingleUse = 90;
const int kDaysOpen = 7;
const int kAtMostOpen = 20;
const int kDifficultySingleUse = 20;
const int kDifficultyOpen = 22;

/// How many invitations may be valid at the same time. Without a cap
/// a user collects over years codes that they no longer know and
/// therefore also do not revoke.
const int kAtMostStanding = 10;

/// Grace period: this long after expiry the ISSUER still accepts a request
/// that presents the code of this invitation.
///
/// `v42/kap/ch15.md:262-266`: "A request placed while the code was valid
/// can arrive later, because it may have travelled through a post box that
/// holds packets for 7 days. The issuer therefore accepts requests bearing
/// a given code until **expiry + 7 d**."
///
/// The number is not generosity but the flip side of the
/// post box's holding period: a request that was sent on the last valid day
/// and rested for seven days is meant exactly as
/// it arrives. Without a grace period precisely the case would be rejected
/// for which the post box was built.
///
/// It sits with the ISSUER, not with the joiner. The issuer
/// alone knows how long it still listens; what stands in the card thereby stays
/// honest — it promises the expiry, not the expiry plus
/// seven days. That is why the reader's warning period stands as a separate
/// constant in `card_expiry.dart` and not as a reference to this one.
const int kGracePeriodDays = 7;

/// Seconds of the grace period.
const int kGracePeriodSeconds = kGracePeriodDays * 86400;

/// The expiry value of an indefinitely valid invitation (§15.3: "Unlimited is
/// written as `0xFFFFFFFF`"). The number is not assigned here but taken from
/// `card.dart` — it must be the same that the card reader recognises as
/// unlimited (`card_expiry.dart`).
const int kExpiryUnlimited = Card.expiryMax;

/// How many bytes the label carries at most. **SUGGESTION, not a default
/// from the document** — like `kAtMostRemembered`: §15.3 lists the label,
/// but names no length. It must be a cap, because the value comes from the
/// UI and ten invitations would otherwise make the file arbitrarily
/// large.
const int kLabelAtMostBytes = 64;

class Invitation {
  final Uint8List code;
  final Kind kind;
  final int expiryUnixSeconds;
  final int difficulty;

  /// Greater than 1 only for [Kind.open]: how many acceptances are admissible.
  final int atMost;

  /// Handed over face to face (NFC, QR on site): a request
  /// on it is accepted without a second question (V4.2 §15.5). A property
  /// at the issuer, not in the card — and therefore in memory, otherwise
  /// a card handed over in person before the restart would ask afterwards
  /// (ES-12). Only for [Kind.singleUse] (§15.5: "which is of the single kind").
  final bool inPerson;

  /// The label under which the issuer recognises this invitation
  /// ("Conference") — §15.3 "Attribution": every incoming request is
  /// attributed to the invitation that it used. Without it an
  /// issuer does not see WHICH of its up to ten invitations is being flooded.
  /// It does not stand in the card and never goes onto the wire; empty means:
  /// none assigned.
  final String label;

  int _accepted = 0;
  bool _revoke = false;

  /// The requests waiting for the user's decision (§12.5,
  /// §15.4). They hang on the INVITATION and not beside it: §15.4 counts
  /// "at most 20 per invitation", the revocation takes them along (B2), and with
  /// the invitation they go to disk — until S389 they were gone after a
  /// restart and the question to the user was lost (E-1).
  final RequestBuffer requests = RequestBuffer();

  /// The neighbour address its card named (§15.2), `null` = none. Set once
  /// on issuing, kept on disk — as long as the invitation stands, its
  /// readers hold this address, and the fixed seat does not leave it for a
  /// reachable one (S394 V6, `neighbourhood_seat.dart`).
  CardAddress? cardNeighbour;

  Invitation._({
    required this.code,
    required this.kind,
    required this.expiryUnixSeconds,
    required this.difficulty,
    required this.atMost,
    this.inPerson = false,
    this.label = '',
  }) {
    final n = utf8.encode(label).length;
    if (n > kLabelAtMostBytes) {
      throw ArgumentError('Label may be at most $kLabelAtMostBytes B '
          'long, was $n B');
    }
  }

  /// The expiry time for a choice of validity (§15.3). [days] `null`
  /// means "the [defaultDays] of the kind"; [unlimited] beats [days]. In ONE
  /// place, so that the two factories do not keep two calculations.
  static int _expiry(
      {required int defaultDays, int? days, required bool unlimited}) =>
      unlimited ? kExpiryUnlimited : _now() + (days ?? defaultDays) * 86400;

  /// Issues an invitation for a specific person.
  static Invitation forOnePerson({
    Random? random,
    int? days,
    bool unlimited = false,
    bool inPerson = false,
    String label = '',
  }) {
    return Invitation._(
      code: _roll(16, random ?? Random.secure()),
      kind: Kind.singleUse,
      expiryUnixSeconds:
          _expiry(defaultDays: kDaysSingleUse, days: days, unlimited: unlimited),
      difficulty: kDifficultySingleUse,
      atMost: 1,
      inPerson: inPerson,
      label: label,
    );
  }

  /// Restores an ISSUED invitation from memory —
  /// with its code, its expiry and its two counters (S388, ES-7/B3).
  ///
  /// The way back must lie here: the constructor is file-private,
  /// and the two other paths draw a new code. Until S388 the
  /// loaded invitation therefore stood as a second bundle next to this class
  /// (`Identitaet.geladeneEinladungen`) — without revocation, without cap, without
  /// answer on the wire.
  static Invitation outSplit({
    required Uint8List code,
    required Kind kind,
    required int expiryUnixSeconds,
    required int difficulty,
    required int atMost,
    required int accepted,
    required bool revoke,
    bool inPerson = false,
    String label = '',
    Iterable<WaitingRequest> waitingRequests = const [],
    CardAddress? cardNeighbour,
  }) {
    if (atMost < 1 || accepted < 0) {
      throw ArgumentError('atMost >= 1 and accepted >= 0, was '
          '$atMost/$accepted');
    }
    return Invitation._(
      code: code,
      kind: kind,
      expiryUnixSeconds: expiryUnixSeconds,
      difficulty: difficulty,
      atMost: atMost,
      inPerson: inPerson,
      label: label,
    )
      .._accepted = accepted
      .._revoke = revoke
      ..cardNeighbour = cardNeighbour
      ..requests.adopt(waitingRequests);
  }

  /// Issues an invitation that may be distributed.
  static Invitation openDistributed({
    Random? random,
    int? days,
    bool unlimited = false,
    int? atMost,
    String label = '',
  }) {
    return Invitation._(
      code: _roll(16, random ?? Random.secure()),
      kind: Kind.open,
      expiryUnixSeconds:
          _expiry(defaultDays: kDaysOpen, days: days, unlimited: unlimited),
      difficulty: kDifficultyOpen,
      atMost: atMost ?? kAtMostOpen,
      label: label,
    );
  }

  int get accepted => _accepted;
  bool get revoke => _revoke;

  /// Is it still valid? An invitation that is no longer valid is not
  /// deleted — it stays visible so that the user understands why
  /// a request no longer gets through.
  ///
  /// That is the question about the card's PROMISE and thus the
  /// basis for the cap from [kAtMostStanding]. It is NOT the
  /// question whether a request is still accepted — for that stands
  /// [acceptanceWindowOpenAt], which reaches [kGracePeriodDays] days further.
  bool validAt(int now) =>
      !_revoke && now <= expiryUnixSeconds && _accepted < atMost;

  /// Does the issuer still accept a request for this invitation?
  ///
  /// Like [validAt], only that the expiry is pushed out by [kGracePeriodSeconds].
  /// Revocation and consumption get NO grace period:
  /// both are decisions of the user that apply immediately, while
  /// the expiry is a time of day that a request in transit could not
  /// know.
  bool acceptanceWindowOpenAt(int now) =>
      !_revoke &&
      now <= expiryUnixSeconds + kGracePeriodSeconds &&
      _accepted < atMost;

  /// Expired, but still within the grace period — the state that a
  /// UI must be able to explain ("expired, but still accepts until
  /// …").
  bool inGracePeriodAt(int now) =>
      !_revoke &&
      now > expiryUnixSeconds &&
      now <= expiryUnixSeconds + kGracePeriodSeconds;

  /// The user revokes. For a distributed invitation that is the
  /// actual tool: it is revoked as soon as the occasion is over.
  void withdraw() => _revoke = true;

  /// Checks an incoming request. Returns null if it
  /// passes.
  ///
  /// IMPORTANT: this is NOT yet an acceptance. Consumption happens only when the
  /// user has agreed — otherwise a stranger burns a
  /// single-use invitation with a junk request before the user is
  /// even asked.
  Rejection? check(Uint8List presentedCode, {int? now}) {
    final t = now ?? _now();
    if (!_equal(presentedCode, code)) return Rejection.unknownCode;
    if (_revoke) return Rejection.revoke;
    // Expiry PLUS grace period — see [kGracePeriodDays]. A request that has rested in the
    // post box arrives up to seven days late,
    // without its sender having done anything wrong.
    if (t > expiryUnixSeconds + kGracePeriodSeconds) {
      return Rejection.expired;
    }
    if (_accepted >= atMost) return Rejection.consumed;
    return null;
  }

  /// The user has agreed. Only here is it consumed.
  void acceptedThroughUser() {
    _accepted++;
  }
}

/// All own invitations. Enforces the cap and finds the matching one
/// for a presented code.
class Invitations {
  final List<Invitation> _list = [];

  List<Invitation> get all => List.unmodifiable(_list);

  /// Those still valid — the set that the cap [kAtMostStanding]
  /// bounds and that the user sees as "my open invitations".
  List<Invitation> standing({int? now}) {
    final t = now ?? _now();
    return _list.where((e) => e.validAt(t)).toList();
  }

  /// The set against which a proof of work is checked: the standing ones
  /// PLUS those that have expired but are still within the grace period
  /// ([kGracePeriodDays]). Without this second group the grace period would run
  /// into nothing — the proof of the late-arriving request would no longer
  /// find its code at all, and the request would be discarded before anyone
  /// asks about the expiry.
  ///
  /// Cut off at [kAtMostStanding] entries, standing ones first.
  /// That is intentional: the check costs one SHA-256 call per entry,
  /// and the promised upper bound of ten hashes before the first unsealing
  /// (`v42/kap/ch15.md:427-429`) must not be raised by the grace period. Whoever has ten
  /// fresh invitations standing thereby loses the grace period of the
  /// oldest — the price is known and lies lower than a
  /// check-cost upper bound that grows with time.
  List<Invitation> accepting({int? now}) {
    final t = now ?? _now();
    final out = _list.where((e) => e.validAt(t)).toList();
    out.addAll(_list.where((e) => e.inGracePeriodAt(t) && e.acceptanceWindowOpenAt(t)));
    return out.length <= kAtMostStanding
        ? out
        : out.sublist(0, kAtMostStanding);
  }

  /// Creates an invitation. Throws if the cap is reached — the
  /// caller must then first withdraw one.
  void admit(Invitation e, {int? now}) {
    if (standing(now: now).length >= kAtMostStanding) {
      throw StateError('at most $kAtMostStanding standing '
          'invitations — withdraw one first');
    }
    _list.add(e);
  }

  /// Admits an invitation restored from memory —
  /// WITHOUT checking the cap: it already stood when it was issued,
  /// and a restart must not kill a card that was given. New invitations
  /// still go through [admit] and count the restored ones along.
  /// A code never stands twice in the list.
  void resume(Invitation e) {
    if (toCode(e.code) != null) {
      throw StateError('this code is already in the list');
    }
    _list.add(e);
  }

  /// Searches the invitation for a presented code.
  Invitation? toCode(Uint8List presented) {
    for (final e in _list) {
      if (_equal(e.code, presented)) return e;
    }
    return null;
  }

  /// Withdraws everything at once — the emergency exit when a user
  /// no longer knows what they have distributed.
  int allWithdraw() {
    var n = 0;
    for (final e in _list) {
      if (!e.revoke) {
        e.withdraw();
        n++;
      }
    }
    return n;
  }
}

int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

Uint8List _roll(int n, Random r) {
  final b = Uint8List(n);
  for (var i = 0; i < n; i++) {
    b[i] = r.nextInt(256);
  }
  return b;
}

/// Comparison without early exit — the running time should not reveal
/// how many bytes of a guessed code were right.
bool _equal(Uint8List x, Uint8List y) {
  if (x.length != y.length) return false;
  var d = 0;
  for (var i = 0; i < x.length; i++) {
    d |= x[i] ^ y[i];
  }
  return d == 0;
}
