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
KeyChangeOutcome onIdentityRotation(String currentLevel) {
  final wasVerified = kVerifiedLevels.contains(currentLevel);
  final changed = currentLevel != 'unverified';
  return KeyChangeOutcome('unverified', wasVerified, changed);
}
