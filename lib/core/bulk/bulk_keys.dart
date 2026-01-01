// Keys and tags of a bulk transfer (§9.3).
//
// THE SPEC. §9.3: the blocks are "sealed under a transfer key derived
// from `K_AB` (pairwise) or from a random per-transfer key `K_T` travelling
// over each KEX-gated leg (groups — encode once, place once, member-count
// independent)", and placed at "the always-on relays (§22.6)
// responsible for the **transfer tag**".
//
// ── THE PAIRWISE BRANCH IS REMOVED (31.08.2026, owner decision) ─
//
// "V4 = B and wrap it securely in PQ." The pairwise branch could not
// hold that, and this was measured in the code, not inferred:
//
//   * `K_T = HKDF(K_AB, "media/<hash>")` depends entirely on `K_AB`.
//   * `K_AB` comes out of `deriveDeliveryPairKey`
//     (`tagline/pair_registry.dart:99-114`): `x25519ScalarMult` + HKDF.
//     **No ML-KEM.** Measured on 31.08.: `grep -i "kem|oqs"` over
//     `pair_registry.dart` finds ONE hit, and it is in a
//     comment (l. 132), not in the code.
//   * The cell path next to it is hybrid: `message_seal.dart:374`
//     `OqsFFI().mlKemEncapsulate(...)`, and `seal` mixes the
//     ML-KEM day capsule with the X25519 DH (`_combine`).
//
// The media content thus ran as the ONLY payload stream purely classically
// — appendix B-29 ("Content stays PQ end-to-end sealed on **both** lanes")
// was wrong against the built code. A capture today, a
// quantum computer later: every image ever sent falls.
//
// SECOND CONSEQUENCE OF THE SAME ROOT, and it weighs more than a first
// glance suggests: **no forward secrecy.** §15.2 makes `K_AB`
// explicitly rotation-proof — "`K_AB` survives every key rotation
// without a transition window". A founding key obtained once
// thus RETROACTIVELY opens every media transfer of this pair
// ever archived. The cell path does not have this flaw: there the
// session key per message is ephemeral.
//
// THIRD CONSEQUENCE, which is an attack in the field: the derivation was
// deterministic from (`K_AB`, content hash). Whoever has `K_AB` can compute the
// tag for ANY guessed content and check with the responsible relays
// whether it exists — a confirmation oracle "did A send this
// exact image to B?". A drawn root has no oracle.
//
// SINCE THEN THERE IS ONLY ONE ORIGIN:
//
//   K_T   = 32 random bytes, freshly drawn per transfer
//   tag   = HKDF(K_T, "bulk/tag")
//   seal  = HKDF(K_T, "bulk/seal")
//
// `K_T` ALWAYS travels along in the announce (`BulkAnnounce.transferRoot`), and the
// announce is an ordinary message on the cell path — i.e. under
// the hybrid of X25519 and ML-KEM-768. The content is thus PQ-protected on both
// lanes, as B-29 claimed.
//
// WHAT THE KEX GATE ACHIEVES HERE. The root can only be learned by whoever
// can open the announce, and that is the KEX-gated cell path. A
// remote non-contact can neither find nor fill the tag line of a foreign transfer
// (§10.1, the same property as for the
// Secure tag).
//
// WHAT IT COSTS, quantified: the content-addressed deduplication of TWO
// transfers of the same object to the same partner is lost — it
// depended precisely on the determinism. Within ONE transfer it stays
// unchanged (same root, same bytes, `BulkCache.place`
// deduplicates by `bulkBlockDigest`), and §26.6.1 (many desktops seed
// the same binary) is not affected: this case never ran over the
// pairwise branch — it has no `K_AB` — but over a SHARED
// root via [BulkTransferKeys.fromRoot], and that still exists. Measured on
// 31.08.: apart from `media_bulk_lane.dart`, `lib/` has not a
// single producer of `BulkTransferKeys`, and `KeyedSeeds` has zero
// callers.
//
// NO STATE, NO I/O apart from the crypto library.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/fountain/fountain_block.dart';

/// Length of the content hash a transfer depends on.
const int kBulkContentHashBytes = 32;

/// Salt of all bulk derivations. Separates them from the delivery layer
/// (`cleona-secure`) and from liveness — the same root must never yield the same key
/// in two domains.
final Uint8List _salt = Uint8List.fromList(utf8.encode('cleona-bulk'));

Uint8List _hkdf(Uint8List key, String info, [int length = 32]) =>
    SodiumFFI().hkdfSha256(key,
        salt: _salt,
        info: Uint8List.fromList(utf8.encode(info)),
        length: length);

/// The same derivation, but for callers OUTSIDE this file.
///
/// ── WHY IT IS PUBLIC, AND ONLY IT ──────────────────────────
///
/// There is exactly one such caller: `update/binary_fountain.dart`
/// computes the root of an update binary from its content hash
/// (`K_T = HKDF(binaryHash, "update/root")`, option B of the proposal
/// `docs/v4-redesign/S365-VORLAGE-dritter-weg-und-wurzel.md`, section
/// 1.3, chosen by the owner).
///
/// It could do the same calculation with its own salt — any
/// fixed value would do, because the root need not be secret, only
/// the SAME at all nodes. Exactly for that reason it stands here: two
/// salts for the same purpose are two places where someone later
/// changes one. The information domain is the same (`cleona-bulk`),
/// the info marker separates them (`update/root` versus `bulk/tag`,
/// `bulk/seal`, `nonce/...`, `seed/...`).
Uint8List bulkHkdf(Uint8List key, String info, [int length = 32]) =>
    _hkdf(key, info, length);

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

/// Constant-time comparison of two byte sequences of equal length.
///
/// For the hash comparison after reconstruction (§26.6.1 step 5).
/// A comparison that aborts early reveals via its run time how many
/// leading bytes match — for a hash that an attacker may supply,
/// that is the difference between 2^256 and 32 x 256 attempts.
bool bytesEqualConstantTime(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// The identifier that goes into every block header: the first 8 B of the
/// content hash (§26.6.1 step 5, `FountainBlock.objectId`).
///
/// **It is not an integrity check.** It binds a block to an
/// object; the content is confirmed solely by the full hash after
/// reconstruction (`BulkReceiver.take`).
Uint8List objectIdFromContentHash(Uint8List contentHash) {
  if (contentHash.length != kBulkContentHashBytes) {
    throw ArgumentError(
        'Content hash must be $kBulkContentHashBytes B, is '
        '${contentHash.length}');
  }
  return Uint8List.fromList(
      contentHash.sublist(0, kFountainObjectIdBytes));
}

/// The content hash of an object: SHA-256 over exactly the bytes the
/// receiver reconstructs.
///
/// THE CODEC DOES NOT COMPUTE IT (E-42: pure Dart, no FFI). It is
/// computed here because the binding depends on libsodium anyway — and
/// it is needed **in exactly two places**: at the sender for the
/// announce, at the receiver for the final check.
Uint8List bulkContentHash(Uint8List object) => SodiumFFI().sha256(object);

/// The keys of a transfer.
final class BulkTransferKeys {
  /// `K_T` — the root. Everything else follows from it.
  final Uint8List root;

  /// The transfer tag: placing and scanning happen under it.
  final Uint8List tag;

  /// The seal key per block.
  final Uint8List sealKey;

  BulkTransferKeys._(this.root, this.tag, this.sealKey);

  /// From a known root — the path of the RECEIVER (it reads it
  /// from the announce) and the path of several seeders of the same object
  /// (§26.6.1: they share `K_T` so that their blocks are byte-identical and
  /// the cache holds them once).
  factory BulkTransferKeys.fromRoot(Uint8List root) {
    if (root.length != 32) {
      throw ArgumentError('K_T must be 32 B, is ${root.length}');
    }
    return BulkTransferKeys._(
      Uint8List.fromList(root),
      _hkdf(root, 'bulk/tag'),
      _hkdf(root, 'bulk/seal'),
    );
  }

  /// A fresh, DRAWN root — the sender's only path.
  ///
  /// ── WHY THERE IS NO SECOND ONE ANYMORE (31.08.2026) ──────────────────
  ///
  /// Until today this held `BulkTransferKeys.pairwise({kAb, contentHash})`
  /// with `K_T = HKDF(K_AB, "media/<hash>")`. The three reasons for which
  /// the branch was removed — no PQ cover, no forward secrecy,
  /// a confirmation oracle — are written out in the header of this
  /// file. They were measured in the code, not assumed.
  ///
  /// `group()` was the name of the survivor, because at first it was only the group case.
  /// The name fell with the branch: the root is now
  /// ALWAYS drawn, 1:1 as in the group, and it ALWAYS travels along in the announce
  /// (`BulkAnnounce.transferRoot`). The announce is an ordinary
  /// message on the cell path, i.e. under X25519 + ML-KEM-768
  /// (`message_seal.dart:374`) — that is where the PQ cover of the content comes from.
  factory BulkTransferKeys.fresh() =>
      BulkTransferKeys.fromRoot(SodiumFFI().randomBytes(32));

  /// The nonce of a block — **derived, not drawn**.
  ///
  /// ── WHY DETERMINISTIC ────────────────────────────────────────────
  ///
  /// The cache is content-addressed: it deduplicates by the bytes it
  /// holds (`BulkCache.place`). With a drawn nonce the same
  /// block from two seeders would yield two different byte sequences, and the cache
  /// would hold it twice — the deduplication would be ineffective, exactly where
  /// §26.6.1 needs it (many desktops seed the same binary).
  ///
  /// ── WHY THIS IS SAFE HERE ────────────────────────────────────────
  ///
  /// A reused GCM nonce is catastrophic if it covers a DIFFERENT plaintext
  /// twice. Here it covers the same one twice:
  /// `FountainEncoder.blockAt` is deterministic, so the plaintext
  /// is a function of (object, seed). And the nonce depends on both —
  /// via `objectId` on the object, via `sealKey` on the root.
  ///
  /// SINCE 31.08. THIS IS EVEN EASIER TO PROVE than before: the
  /// root is DRAWN per transfer (`fresh`), so the
  /// nonce space of two transfers is disjoint with probability 1 - 2^-256.
  /// The detour needed before ("the object is contained pairwise
  /// in `K_T` via the content hash") is dropped along with the pairwise branch.
  Uint8List blockNonce(Uint8List objectId, int blockSeed) =>
      _hkdf(sealKey, 'nonce/${_hex(objectId)}/$blockSeed', 12);
}

/// Where a seeder gets its seeds from.
///
/// ── THIS IS A DECISION, NOT A DERIVATION (AP-7, point 5) ────────
///
/// Both paths are built, because both have a price and the cheaper one
/// depends on the number of seeders:
///
/// **[sequential]** — seed = running index. A seeder produces
/// 0, 1, 2, …; two seeders thus produce **the same** blocks.
///   * Price: no independent redundancy. If block 17 fails at a
///     holder, it is missing for every seeder alike — two seeders
///     buy zero additional coverage.
///   * Gain: the cache holds every block exactly once, no matter how many
///     seed. With a 150 MB binary and 1 000 seeding desktops that is
///     the difference between ~190 MB and ~190 GB in the network. And the
///     refill is trivial: the sender keeps counting.
///
/// **[keyed]** — seed = 4 B from `HKDF(seederGeheimnis, "<objekt>/<i>")`.
/// Two seeders produce practically disjoint sets.
///   * Price: the network volume grows linearly with the number of seeders, and
///     a receiver harvests more than it needs.
///   * Gain: coverage. Every additional seeder repairs losses
///     at the others. With 2^32 seeds and 205 000 blocks (200 MB)
///     the seeds of ONE seeder are expected to collide 0.005 times
///     — negligible, and a collision only costs
///     one wasted block (`FountainOffer.duplicate`).
///
/// **Default: [sequential].** Rationale: today's consumer — the
/// media bulk lane — has EXACTLY ONE seeder (the sender), and there
/// [keyed] is strictly more expensive without any benefit. The argument that same
/// blocks are linkable across seeders does not hold here: the
/// blocks are sealed under `sealKey`, a holder sees random bytes.
/// Where several seed — binary distribution (§26.6.1) — the
/// caller chooses [keyed]; that is why this is a parameter and not a constant.
enum BulkSeedPolicy { sequential, keyed }

/// Returns the seed for the [index]-th block of this seeder.
abstract interface class BulkSeedSource {
  BulkSeedPolicy get policy;
  int seedAt(int index);
}

/// Consecutive from 0 (default).
final class SequentialSeeds implements BulkSeedSource {
  const SequentialSeeds();

  @override
  BulkSeedPolicy get policy => BulkSeedPolicy.sequential;

  @override
  int seedAt(int index) {
    if (index < 0) throw ArgumentError.value(index, 'index', 'must be >= 0');
    return index & 0xFFFFFFFF;
  }
}

/// Derived from a seeder-local secret — deterministic (an
/// abort can be resumed) and different across seeders.
final class KeyedSeeds implements BulkSeedSource {
  final Uint8List _seederSecret;
  final String _objectHex;

  KeyedSeeds({required Uint8List seederSecret, required Uint8List objectId})
      : _seederSecret = Uint8List.fromList(seederSecret),
        _objectHex = _hex(objectId);

  @override
  BulkSeedPolicy get policy => BulkSeedPolicy.keyed;

  @override
  int seedAt(int index) {
    if (index < 0) throw ArgumentError.value(index, 'index', 'must be >= 0');
    final h = _hkdf(_seederSecret, 'seed/$_objectHex/$index', 4);
    return (h[0] << 24) | (h[1] << 16) | (h[2] << 8) | h[3];
  }
}
