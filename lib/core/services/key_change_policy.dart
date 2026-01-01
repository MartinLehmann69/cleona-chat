/// Key-Change-Detection policy for identity-key changes (§8.3 / SR-1).
///
/// Centralizes the rule that decides how a contact's verification level
/// reacts when that contact's identity key changes — in particular on an
/// accepted Emergency Key Rotation (§7.4b). A valid rotation chain does NOT
/// prove the rotation was authorized by the legitimate owner rather than a
/// seed-holding thief, so a soft re-key is never followed silently at full
/// trust: the verification level is reset and the UI is warned.
library;

/// Verification levels (§5.5). String-valued in the contact store
/// (`ContactInfo.verificationLevel`).
const Set<String> kVerifiedLevels = {'verified', 'trusted'};

/// Outcome of applying the key-change policy to a contact's current level.
class KeyChangeOutcome {
  /// The verification level the contact should hold after the change.
  final String newLevel;

  /// Whether the previous level was a *verified* trust state
  /// (`verified`/`trusted`) — drives how loudly the UI warns.
  final bool wasVerified;

  /// Whether the level actually changed (false when already `unverified`).
  final bool changed;

  const KeyChangeOutcome(this.newLevel, this.wasVerified, this.changed);
}

/// SR-1 (§7.4b step 6 / §8.3): an accepted Emergency Key Rotation resets the
/// contact's verification level — any non-`unverified` level drops to
/// `unverified` until the user actively re-verifies. The keys themselves are
/// applied by the caller (the rotation is cryptographically valid); this is
/// the *visibility* response, not a block.
///
/// ── THE ONE EXCEPTION THAT v4_1 §14.4 PROVIDES NORMATIVELY ────────────
///
/// §14.4, "Verification levels at sig rotation (normative)": "The contact's
/// verification level (verified/trusted) **is retained** if **both** are
/// present: (i) the continuity proof with the old key **and** (ii) the
/// lock-out quorum `max(2, ⌈M/2⌉)` (§14.8). If either is missing, the
/// visibility principle applies (§14.5): level drops back, visible warning,
/// the rotation is applied anyway. Rationale: a stolen device alone can
/// forge (i) — it holds the old key —, but not (ii)."
///
/// [oldSignatureValid] is proof (i): the caller has checked the old signature
/// against the stored anchor before coming here.
/// [quorumMet] is proof (ii).
///
/// WHY `singleDevice` DOES NOT RETAIN, although §14.8 says "with
/// exactly one device, the rule does not apply": for a
/// single-device identity proof (ii) does not exist — not because it was
/// provided, but because it cannot exist. The rationale that §14.4
/// gives for retaining ("a stolen device alone … cannot forge
/// (ii)") therefore does not hold there: whoever has the one device has
/// everything. Retaining would mean turning a missing check into a
/// passed result. The reset therefore stays the
/// default and is suspended ONLY with an actually proven quorum —
/// a narrowing of the reset, never a widening.
///
/// The default `false` keeps every caller that does not know the new arguments
/// on the previous behaviour.
KeyChangeOutcome onIdentityRotation(
  String currentLevel, {
  bool quorumMet = false,
  bool oldSignatureValid = false,
}) {
  final wasVerified = kVerifiedLevels.contains(currentLevel);
  if (quorumMet && oldSignatureValid && wasVerified) {
    // §14.4: both proofs are present — the level stays. `wasVerified`
    // stays true so that the UI nevertheless SHOWS the rotation:
    // keeping does not mean concealing.
    return KeyChangeOutcome(currentLevel, wasVerified, false);
  }
  final changed = currentLevel != 'unverified';
  return KeyChangeOutcome('unverified', wasVerified, changed);
}
