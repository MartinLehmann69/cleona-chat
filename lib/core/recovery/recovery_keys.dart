// G-3, step 1: the key schedule of recovery (§13).
//
// ── WHAT STANDS HERE AND WHY ONLY THAT ──────────────────────────────────
//
// §13 has three stages: the recovery bundle (§13.3), the emergency call (§13.4)
// and the recovery broadcast (§13.5). All three hang on
// tags that can be derived EXCLUSIVELY from the 24-word phrase
// — that is the load-bearing property of the whole chapter:
//
//   §13.1.3: "The recovering user possesses exclusively
//   **self-referential** key material."
//
// This file builds exactly these derivations and nothing else. It
// does not talk to the network, it knows no contacts, it stores nothing
// and harvests nothing.
//
// CORRECTED (S361, against the S360 state of this comment): the third
// retention class now exists — `kRetentionManagement` = 2
// (`secure_frames.dart:241`), `kManagementKeepEpochs` = 31
// (`secure_mode.dart:394`), with its own branch in `SecureStore.expire`
// (`secure_mode.dart:576-577`). The budget decision has been made,
// it is no longer open. What remains is a wiring gap, no longer a
// deadline question: `v41_node.dart:1966` chooses the class exclusively
// between `kRetentionSignal` and `kRetentionNormal` — there is no
// setting place that ever chooses `kRetentionManagement` (`grep -rn
// kRetentionManagement lib/` only yields the definition, the validator
// `istBekannteAufbewahrung` and the `expire` branch).
//
// CORRECTED AGAIN (S362, 02.09.2026): the paragraph above describes
// the state of 01.09. and is outdated. Both blockages are gone:
//
//   * THE WIRING. `placeSecure` has taken a parameter
//     `management` since S361, and since S362 `placeUnderTag` sets the class
//     directly — the recovery bundle goes out entirely in
//     `kRetentionManagement`.
//   * S-2, the pair binding. `v41_node.dart` has with `placeUnderTag`,
//     `storeUnderTag` and `harvestUnderTags` an entrance and exit for
//     an ARBITRARY tag, without a peer. The derivations of this
//     file thus have callers in `lib/`; the path leads via
//     `tagline/recovery_line.dart` and
//     `service/cleona_service_recovery_bundle.dart`.
//
// WHAT REMAINS OPEN and is expressly NOT healed by this file
// — all reported, nothing secretly patched:
//
//   * The mobile 48h rule (§21.3.3) against the 31-day promise: a
//     mobile relay in the responsibility set throws the bundle away after
//     two days, no matter which class is on it.
//   * The HARVEST REACH, and that is a DEPENDENCY, not a
//     measurement of this tree. Measured HERE (state 02.09.2026):
//     `ernteEpochenPlan` samples [kHarvestEpochs] = 3 node epochs,
//     the management class holds [kManagementKeepEpochs] = 31 — the
//     storage thus lives longer than the harvest reaches back. A rework
//     of this reach ran at the same time in a DIFFERENT
//     working tree; how far the pointer reaches there is not
//     re-measured here and must not be passed on as measured.
//     The reach of the recovery bundle hangs on that rework.
//   * The OPENABLE HORIZON — until S362 the harder limit of the two,
//     since then CLOSED (owner decision 02.09.2026, "path 1 with
//     bracket"; measurement in
//     `docs/v4-redesign/S362-VORLAGE-oeffenbarer-horizont.md`):
//       - `MessageOpener.secretRetention` = 7 days stands unchanged
//         (`tagline/message_seal.dart`), but
//       - the opener now sees the predecessor. `tagline/v41_attach.dart`
//         wires `previousX25519Secret`/`previousMlKemSecret` to
//         `identity.previousX25519Sk`/`previousMlKemSk`, and
//         `MessageOpener.open` keeps it as second SELECTOR and as
//         second CAPSULE candidate. Both together are needed: the
//         selector decides BEFORE the capsule, an ML-KEM predecessor supplied
//         alone would have been an unentered branch.
//       - `IdentityContext.previousKeyRetention` stands at 32 days (the
//         bracket from §4.5.4 for the 31-day class), no longer at 7.
//     WHAT REMAINS OPEN: there is exactly ONE predecessor slot, which every
//     rotation overwrites. A device running continuously therefore still loses
//     generation N−1 after 7 days; the fallback fully carries
//     the case for which §14.4 invented the class (device
//     was off).
//     That did not hit the recovery bundle anyway: it is sealed symmetrically
//     under `bundleKey(seed)` (§13.3.3), seed-derived and
//     rotation-free, and its cells run past the opener (the
//     harvest return path of the tag line turns back in `v41_node.dart` BEFORE
//     `_harvestedFrom`). But it hits everything that ordinary
//     delivery carries with a long deadline — namely the
//     management class of the emergency rotation (§4.5.4/§14.4, 31 days
//     promised, around 7 days openable). Stage C with the owner, not
//     here.
//
// Prices and options in
// `docs/v4-redesign/S361-aufbewahrung-entwurf.md` and
// `docs/v4-redesign/S360-recovery-entwurf.md` (section 5).
//
// What however stands without any open question is the schedule itself.
// It is normed verbatim in §13, and every line below carries its
// quote. It is moreover the piece that every later stage needs:
// without `tag_R` there is nothing to store, without `H` no emergency call, without
// `tag_RR` no way back.
//
// ── WHAT THIS FILE DOES NOT CLAIM ───────────────────────────────────
//
// It restores nothing. Whoever calls it gets tags and a
// key, no contacts and no messages. A caller who
// makes "recovery is running" out of it lies.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/config/network_channel.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';

// ─────────────────────────────────────────────────────────────────────────
// THE TWO STIPULATIONS THAT §13 LEAVES OPEN
// ─────────────────────────────────────────────────────────────────────────
//
// §13 writes the derivations as `HKDF(k, "recovery" ‖ i)`. What the
// concatenation sign means in bytes and which salt the HKDF takes
// does not stand there — it stands nowhere, because it is an implementation question.
// Both values are fixed here ONCE and then frozen:
//
//   1. `‖` means: literals as UTF-8, integers as 8 bytes
//      big-endian ([_be64]). Fixed length, thus unambiguous — the same
//      justification that `kIdentityDomainBytes` gives for its concatenation
//      ("no separator, no length prefix … fixed length").
//   2. The salt is [_salt] and NOT that of the delivery layer
//      (`secure_mode.dart` takes `cleona-secure`). Separate salts
//      means: a recovery tag can collide with no pair tag,
//      not even if someone later happens to choose
//      the same `info` string.
//
// **Both are wire-relevant.** Whoever changes them makes every recovery bundle
// lying in the network unfindable — not broken, but
// unfindable, which is worse, because nothing reports an error.
// `smoke_v41_recovery_keys.dart` nails them down with test vectors.

const String _salt = 'cleona-recovery';

Uint8List _hkdf(Uint8List key, List<int> info) => SodiumFFI().hkdfSha256(
      key,
      salt: Uint8List.fromList(utf8.encode(_salt)),
      info: Uint8List.fromList(info),
      length: 32,
    );

/// An integer as 8 bytes big-endian — the `‖` from §13 for numbers.
Uint8List be64(int v) {
  final out = Uint8List(8);
  var x = v;
  for (var i = 7; i >= 0; i--) {
    out[i] = x & 0xff;
    x >>= 8;
  }
  return out;
}

List<int> _chain(List<Object> parts) {
  final out = <int>[];
  for (final t in parts) {
    if (t is String) {
      out.addAll(utf8.encode(t));
    } else if (t is int) {
      out.addAll(be64(t));
    } else if (t is Uint8List) {
      out.addAll(t);
    } else {
      throw ArgumentError('only String, int and Uint8List: ${t.runtimeType}');
    }
  }
  return out;
}

// ─────────────────────────────────────────────────────────────────────────
// THE EPOCH OF RECOVERY (§13.3.1)
// ─────────────────────────────────────────────────────────────────────────

/// §13.3.1 verbatim: "The recovery epoch is **14 d** (distinct from the
/// liveness epoch of §6/§9, which is far shorter)."
///
/// The delivery layer computes with `kEpochSeconds` = 86400
/// (`responsibility.dart`). This number has nothing to do with it and must
/// not be confused with it — exactly that is what the parenthetical sentence
/// above warns against.
const int kRecoveryEpochSeconds = 14 * 86400;

/// §13.3.1: „harvests the line for **current + 2 previous** epochs
/// (42 d coverage), which fully covers the bundle's 31-day TTL".
const int kRecoveryHarvestEpochs = 3;

/// §13.3.4: „The TTL is 31 days".
const Duration kRecoveryBundleTtl = Duration(days: 31);

/// §13.3.4: „renewal with every recovery-epoch change, i.e., every 14
/// days … A renewal per epoch leaves a single missed date without
/// consequence (14 + 14 < 31)".
const Duration kRecoveryRenewalInterval =
    Duration(seconds: kRecoveryEpochSeconds);

/// §13.4.6: emergency-call lifetime „**31 d**, no renewal".
const Duration kRestoreBeaconTtl = Duration(days: 31);

/// The running number of the 14-day epoch at a point in time.
///
/// ── WITHOUT OFFSET, AND THAT IS A DECISION ──────────────────────
///
/// `responsibility.dart` staggers the delivery epochs per tag
/// (`epochOffsetFor`), so that not all nodes roll at the same time.
/// Here that is NOT possible without paying a price: the
/// emergency call identifier `H` (§13.4.2) is also computed by the CONTACT, namely
/// from `founding_pk_A` alone. Both sides must hit the same epoch.
/// An offset from `founding_pk_A` would be known to both sides
/// and would work — it is deliberately NOT built here, because §13.4.2 already
/// handles the edge blur differently: "1 identifier per contact
/// and epoch, so **3 with ±1 tolerance**". Whoever wants the offset later
/// changes a wire-relevant quantity; that is a proposal,
/// not a refactoring.
int recoveryEpochFor(DateTime utc) =>
    (utc.toUtc().millisecondsSinceEpoch ~/ 1000) ~/ kRecoveryEpochSeconds;

/// The epochs a recovery queries: current + 2
/// previous (§13.3.1).
List<int> recoveryHarvestEpochs(DateTime utc) {
  final e = recoveryEpochFor(utc);
  return [for (var i = 0; i < kRecoveryHarvestEpochs; i++) e - i];
}

// ─────────────────────────────────────────────────────────────────────────
// STEP 1 — THE RECOVERY BUNDLE (§13.3.1)
// ─────────────────────────────────────────────────────────────────────────
//
//   recovery_key(i) = HKDF(seed, "recovery" ‖ i)
//   σ_R(i, e)       = HKDF(recovery_key(i), "recovery-line"  ‖ epoch_e)
//   tag_R(i, e, j)  = HKDF(recovery_key(i), "recovery" ‖ epoch_e ‖ j)

/// `recovery_key(i)` — the root of the bundle tag line of an identity.
///
/// [identityIndex] is the HD index from §4.5.1. §13.3.1: "**One bundle
/// per identity.** … the index parameter follows the HKDF pattern of the
/// HD derivation".
Uint8List recoveryKey(Uint8List seed, int identityIndex) {
  _checkSeed(seed);
  _checkIndex(identityIndex);
  return _hkdf(seed, _chain(['recovery', identityIndex]));
}

/// `σ_R(i, e)` — the harvest line under which the bundle is searched.
///
/// §13.3.1: "the recovering user harvests `σ_R(i)` for the three epochs
/// and matches via a local hash lookup against `tag_R` — the same
/// mechanism as any other harvest, no special path, no query."
Uint8List recoveryLine(Uint8List recoveryKeyI, int epoch) =>
    _hkdf(_checkKey(recoveryKeyI),
        _chain(['recovery-line', epoch]));

/// `tag_R(i, e, j)` — the tag of the j-th block of the bundle.
///
/// §13.3.1 lists `j` as "block index". §13.3.2 says how many there are:
/// at ~32 KB the bundle is larger than a cell (1200 B) and
/// rides "**Reed-Solomon erasure coding (N=10, K=7, 1.43x overhead, 3
/// peers may fail)**" — "At a fragment size of ~1.1 KB that is ~29
/// source fragments; with the 1.43x erasure overhead, roughly **42
/// fragments per identity and renewal**".
Uint8List recoveryBundleTag(Uint8List recoveryKeyI, int epoch, int block) {
  if (block < 0) throw ArgumentError('Block index negative: $block');
  return _hkdf(_checkKey(recoveryKeyI),
      _chain(['recovery', epoch, block]));
}

/// `bundle_key = HKDF(seed, "recovery-enc")` (§13.3.3).
///
/// ── THE MISSING FORWARD SECRECY STANDS IN THE DOCUMENT, NOT HERE ───
///
/// §13.3.3 verbatim: "**by construction, the recovery bundle is not
/// forward-secret.** Whoever obtains the seed and has archived the
/// responsible relays can read every bundle within the archive window,
/// and with it the complete contact list **and the Shared Key**. This is
/// not an implementation deficiency but the definition of the matter."
///
/// That is not a finding of this file and must not be treated as one:
/// a backup that the phrase alone is supposed to open cannot have a
/// key that the phrase does not contain.
Uint8List bundleKey(Uint8List seed) {
  _checkSeed(seed);
  return _hkdf(seed, _chain(['recovery-enc']));
}

// ─────────────────────────────────────────────────────────────────────────
// DER IDENTITAETS-MERKER (§13.7)
// ─────────────────────────────────────────────────────────────────────────

/// `tag_M(i, e) = HKDF(seed, "identity-marker" ‖ i ‖ epoch_e)` (§13.7).
///
/// The marker is the termination criterion of the identity derivation:
/// §13.7 "the recovering user derives indices in ascending order and
/// harvests the marker for each index. The **first index without a
/// marker** ends the derivation".
///
/// And it is the CHEAP existence check: "a single delivery per index
/// instead of ~42 (§13.3.2), before the actual bundle harvest begins."
Uint8List identityMarkerTag(Uint8List seed, int identityIndex, int epoch) {
  _checkSeed(seed);
  _checkIndex(identityIndex);
  return _hkdf(seed, _chain(['identity-marker', identityIndex, epoch]));
}

// ─────────────────────────────────────────────────────────────────────────
// STEP 2 — THE DISTRESS CALL (§13.4.2) AND ITS RETURN PATH (§13.4.3)
// ─────────────────────────────────────────────────────────────────────────

/// `H = SHA-256(kIdentityDomain ‖ "restore" ‖ founding_pk_A ‖ epoch_e)`
/// (§13.4.2, normative).
///
/// ── THE ONLY TAG OF THIS CHAPTER THAT A STRANGER COMPUTES ───────
///
/// §13.4.2: "A contact checks by harvesting under the self-computed `H`
/// of their contacts — they know each contact's `founding_pk` and can
/// form `H`."
///
/// And what it does NOT reveal: "The tag `H` is an opaque hash: whoever
/// does **not** have `founding_pk_A` sees ,someone is recovering,` not
/// ,A is recovering.`"
///
/// [foundingEd25519Pk] is the FOUNDING key (§15.2), not the
/// current one. It is the only one that survives every rotation — and the
/// only one a contact certainly has from its contact record.
Uint8List restoreBeaconId(Uint8List foundingEd25519Pk, int epoch) {
  if (foundingEd25519Pk.length != 32) {
    throw ArgumentError(
        'Founding key must be 32 B, is ${foundingEd25519Pk.length}');
  }
  return SodiumFFI().sha256(Uint8List.fromList(<int>[
    ...kIdentityDomainBytes,
    ..._chain(['restore', foundingEd25519Pk, epoch]),
  ]));
}

/// The three identifiers under which a contact looks after an emergency call.
///
/// §13.4.2: "1 identifier per contact and epoch, so **3 with ±1
/// tolerance**". The tolerance is not a convenience, but the substitute for
/// the missing epoch offset (see [recoveryEpochFor]).
List<Uint8List> restoreBeaconIdsAround(
    Uint8List foundingEd25519Pk, DateTime utc) {
  final e = recoveryEpochFor(utc);
  return [
    for (final d in const [-1, 0, 1]) restoreBeaconId(foundingEd25519Pk, e + d)
  ];
}

/// `restore_key = HKDF(seed, "restore")` (§13.4.3) — „derivable only by A".
Uint8List restoreKey(Uint8List seed) {
  _checkSeed(seed);
  return _hkdf(seed, _chain(['restore']));
}

/// `σ_RR(e) = HKDF(restore_key, "restore-resp-line" ‖ e)` (§13.4.3).
///
/// The collection line on which A collects the responses of its contacts.
/// "A harvests `σ_RR` during recovery: **1 temporary harvest line**."
Uint8List restoreResponseLine(Uint8List restoreKeyA, int epoch) =>
    _hkdf(_checkKey(restoreKeyA),
        _chain(['restore-resp-line', epoch]));

/// `tag_RR(e) = HKDF(restore_key, "restore-resp" ‖ e)` (§13.4.3).
///
/// ── THE SINGLE-USE-TAG INVARIANT EXPLICITLY DOES NOT APPLY HERE ───────
///
/// §13.4.3 verbatim: „`tag_RR` is a family following the **R-26
/// pattern** (many deliveries under one tag) — the same concession the
/// invite family (§15.3.2) makes. The single-use-tag invariant
/// deliberately does not apply here; it is a collection inbox for a
/// limited time."
///
/// The declared price stands next to it: „Whoever sees the distress call
/// knows `tag_RR` and can place deliveries under the family (junk) and
/// **see** the responses — but not **read** them."
Uint8List restoreResponseTag(Uint8List restoreKeyA, int epoch) =>
    _hkdf(_checkKey(restoreKeyA), _chain(['restore-resp', epoch]));

// ─────────────────────────────────────────────────────────────────────────
// DIE VERSIEGELUNG DES BUENDELS (§13.3.3)
// ─────────────────────────────────────────────────────────────────────────

/// Nonce length of AES-256-GCM, as `sodium_ffi.dart` keeps it.
const int kBundleNonceBytes = 12;

/// Seals [plaintext] symmetrically under [key] (§13.3.3: "The bundle
/// is sealed **symmetrically**, with a key from the seed … AEAD as in
/// §4.3").
///
/// [nonce] must be 12 B and must NEVER repeat under the same [key]
/// — with AES-GCM a nonce repetition is not a
/// quality defect but the loss of authenticity. The
/// caller passes it in, because only he knows what his
/// renewal cadence is; the tag [recoveryBundleTag] is NOT suitable as
/// nonce (it repeats if the same epoch is renewed
/// twice).
///
/// The result carries the nonce in front, so that a recipient — i.e. the
/// recovering user himself — does not have to remember anything on the side.
Uint8List sealBundle(Uint8List key, Uint8List nonce, Uint8List plaintext,
    {Uint8List? ad}) {
  _checkKey(key);
  if (nonce.length != kBundleNonceBytes) {
    throw ArgumentError('Nonce must be $kBundleNonceBytes B, '
        'is ${nonce.length}');
  }
  final ct = SodiumFFI().aesGcmEncrypt(plaintext, key, nonce, ad: ad);
  final out = Uint8List(nonce.length + ct.length)
    ..setRange(0, nonce.length, nonce)
    ..setRange(nonce.length, nonce.length + ct.length, ct);
  return out;
}

/// Opens what [sealBundle] sealed.
///
/// Returns `null` if the AEAD does not carry — falsified
/// content, wrong key, truncated cell. **`null` does not mean
/// "no bundle found"**: §13.2.3 demands that an
/// unsuccessful search is not an error and none is invented. The
/// difference between "nothing found" and "found, but
/// unusable" belongs in the caller, not here.
Uint8List? openBundle(Uint8List key, Uint8List sealed, {Uint8List? ad}) {
  _checkKey(key);
  if (sealed.length <= kBundleNonceBytes) return null;
  final nonce = Uint8List.sublistView(sealed, 0, kBundleNonceBytes);
  final ct = Uint8List.sublistView(sealed, kBundleNonceBytes);
  try {
    return SodiumFFI()
        .aesGcmDecrypt(Uint8List.fromList(ct), key, Uint8List.fromList(nonce),
            ad: ad);
  } catch (_) {
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────

Uint8List _checkKey(Uint8List k) {
  if (k.length != 32) {
    throw ArgumentError('Key must be 32 B, is ${k.length}');
  }
  return k;
}

void _checkSeed(Uint8List seed) {
  // §13.1.1: "24 words = 264 bits (256 bits of entropy + 8-bit SHA-256
  // checksum)" — the entropy is 32 B, and `seed_phrase.dart` outputs
  // exactly that. A 64 B master seed also passes, because
  // `HdWallet` computes with it internally; everything else is a caller error
  // and shows up here, not only at a tag that never hits.
  if (seed.length != 32 && seed.length != 64) {
    throw ArgumentError('Seed must be 32 or 64 B, is ${seed.length}');
  }
}

void _checkIndex(int i) {
  if (i < 0) throw ArgumentError('identityIndex negative: $i');
}
