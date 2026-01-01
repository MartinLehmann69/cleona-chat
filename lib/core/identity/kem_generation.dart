// The freshness of a STORED copy of foreign KEM keys (§4.5.4).
//
// ── THE FINDING THAT MAKES THIS FILE NECESSARY (S363, 03.09.2026) ─────────
//
// A sender seals against `ContactInfo.x25519Pk` / `mlKemPk` and checks
// ONLY for `null` in doing so (`cleona_service.dart`, `sendToUser`,
// step 2). How old this copy is it does not know — `ContactInfo` carried
// no field for it, and the `rotationTimestamp` from the announcement went
// into the signature buffer and was then discarded
// (`_handleKeyRotation`).
//
// That has consequences, because according to §4.5.4 the recipient holds
// EXACTLY ONE previous generation ("Exactly **one** previous generation
// is retained"). A copy two rotation steps old can thus PROVABLY no
// longer be opened — and the failure is silent: the sender gets an
// ordinary storage receipt, the recipient increments
// `sealedForMeButUnopened`.
//
// ── WHY THE DEADLINE STANDS HERE AND NOT IN THE SERVICE ─────────────────────
//
// [kKemRotationInterval] is THE SAME quantity from which
// `IdentityContext.needsRotation()` decides. It stood there twice as a
// bare `7` without a named constant. A freshness rule bringing its own 7
// would hang on a number that coincides with the rotation interval by
// chance — exactly the construction that has already made a guard
// worthless three times in this project. That is why the number exists
// ONCE, and both sides read it here.
//
// This file is deliberately pure: no FFI, no file system, no clock. It
// can thus be checked without network and without profile.

/// The rotation interval of the long-lived KEM keys of an identity.
///
/// §4.5.4, row "Routine KEM rotation … every **7 days**". The value
/// controls two things and may therefore exist only ONCE:
///
///   * whether the OWN identity must rotate
///     (`IdentityContext.needsRotation`), and
///   * from when on a STORED foreign copy hits only the previous or no
///     held generation any more ([kemCopyFreshness]).
const Duration kKemRotationInterval = Duration(days: 7);

/// How a stored copy of foreign KEM keys stands in relation to the
/// recipient's generation retention (§4.5.4).
enum KemCopyFreshness {
  /// Younger than one rotation interval — it hits the CURRENT generation
  /// of the counterpart, as long as the counterpart rotates on schedule.
  current,

  /// Between one and two rotation intervals — in the worst case it hits
  /// the PREVIOUS generation. According to §4.5.4 the recipient still
  /// holds that, so the cell opens.
  predecessor,

  /// Two rotation intervals or older — beyond the ONE previous
  /// generation that §4.5.4 promises. A cell against it can no longer be
  /// opened at a recipient rotating on schedule.
  stale,

  /// There is no point in time against which to measure (legacy record
  /// before S363, or a contact without `acceptedAt`).
  ///
  /// **Not a synonym for [current].** A legacy record can be arbitrarily
  /// old; carrying it as fresh would be the same silent promise that this
  /// whole finding is.
  unknown,
}

/// How old the copy is at time [now], measured by [seenAt].
///
/// [seenAt] is the last point in time at which this copy DEMONSTRABLY
/// applied: the `rotationTimestamp` of the most recently applied
/// announcement, alternatively the acceptance time of the contact. `null` -> [KemCopyFreshness.unknown].
///
/// [interval] is the rotation interval; it is a parameter and not
/// hard-wired, so that the guard can check the limits without time travel.
KemCopyFreshness kemCopyFreshness({
  required DateTime? seenAt,
  required DateTime now,
  Duration interval = kKemRotationInterval,
}) {
  if (seenAt == null) return KemCopyFreshness.unknown;
  final age = now.difference(seenAt);
  // A copy from the FUTURE is not a fresh copy but a timestamp that is not
  // to be trusted. It is treated like a current one (not like an outdated
  // one), because a misset clock would otherwise report every contact of a
  // device as dead at once.
  if (age.isNegative) return KemCopyFreshness.current;
  if (age < interval) return KemCopyFreshness.current;
  if (age < interval * 2) return KemCopyFreshness.predecessor;
  return KemCopyFreshness.stale;
}

/// Whether a copy of this age PROVABLY no longer opens at a counterpart
/// rotating on schedule.
///
/// Only [KemCopyFreshness.stale] is a proof. [KemCopyFreshness.unknown]
/// explicitly is NOT — it is the absence of a measurement, and turning it
/// into a failure would mean discarding every legacy record.
bool isProvablyUnusable(KemCopyFreshness f) =>
    f == KemCopyFreshness.stale;

/// Whether an arriving rotation announcement may be applied.
///
/// ── WHY THIS IS A SEPARATE, CHECKABLE RULE (S363) ──────────────────
///
/// `CleonaService._handleKeyRotation` wrote the new keys unconditionally
/// into the contact record. The signed `rotationTimestamp` only went into
/// the signature buffer and was then discarded — the place was thus
/// order-blind: the announcement that ARRIVED last won, not the most
/// recent one.
///
/// Since S361 the node harvests up to 30 epochs back
/// (`harvestEpochsPlan`, `depth = kManagementKeepEpochs`), so an old
/// announcement regularly arrives after a newer one. Applied, it resets
/// the contact to a generation that the counterpart no longer carries —
/// and from then on every message to this contact is silently lost. The
/// same check is the replay protection.
///
/// [soFar] `null` means "no announcement ever applied" — then there is
/// nothing to compare and the first one counts.
///
/// A TIE is NOT progress: a second copy of the same announcement (the
/// storage places `m x R` = 60 copies, §9.2) carries nothing new and is
/// discarded.
bool announcementIsNew({
  required DateTime? soFar,
  required DateTime fresh,
}) {
  if (soFar == null) return true;
  return fresh.isAfter(soFar);
}
