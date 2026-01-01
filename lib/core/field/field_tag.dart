// V4 tag derivation — the fourth and last of the functions §21.9.1 point 9
// requires simulator and app to share (Arch v4 §2.4, §4.2; E-22/E-23/E-28,
// serialisation decided E-73).
//
// ATTENTION V4.1: `inboxShardPrefix` and `kShardPrefixBytes` have had NO
// consumer since the clear-out — they stem from the shard model that E-H
// replaces by metric responsibility (`H(T ‖ e)`, Arch §9.1). Whether the
// upper 4 B of the tag carry any meaning at all in V4.1 is decided by
// WP-0. Until then the function stays, so that the decision falls in
// one place and not on the side.
//
// THIS IS NOT THE START OF AP-3. This file holds stateless arithmetic only.
// (It once shared that trait with `field_pricing.dart` and `field_shard.dart`;
// both are gone with the field model, V4.1 §9.1/§22.4.1.) No counter
// bookkeeping, no expectation-set storage, no epoch scheduling — those are
// stateful and belong to the field runtime.
//
// ── What was already normative ──────────────────────────────────────────
//
//   tag_n = HKDF(K_AB, "tag" ‖ direction ‖ epoch ‖ n)          (§2.4)
//   epoch = floor(unixDays / 14), tolerance ±1                 (§2.4, E-22)
//   tag is 16 B on the wire                                    (§2.3a frame)
//   K_AB is the ONLY source; the invite secret never derives it (E-28)
//
// The KEX gate IS this derivation: "whoever cannot compute a tag never
// reaches the recipient" (§2.4, §8.6). There is no later filter stage.
//
// ── What E-73 added, because the formula alone is not an implementation ──
//
// (1) THE SHARD SPLICE. The tag hangs on `K_AB`, the shard on
//     `σ_B = HKDF(inbox_key_B, epoch)` (§4.2, E-39) — two different root
//     secrets. §4.2 said only "senders construct tags so that they fall into
//     σ_B", without an algorithm. Decided: the top **4 bytes** come from σ_B,
//     the remaining 12 from the pairwise KDF. Fixed width, not growing with
//     ℓ, so a tag survives a shard split — its upper bits do not move.
//
//     Why not the alternatives: deriving the whole tag from `K_AB` and
//     rejection-sampling until the prefix matches costs 2^ℓ attempts, i.e.
//     ~16 million HKDF calls per message at ℓ=24. Dropping the coupling puts
//     every contact in a different shard, so a recipient with 200 contacts
//     would need 200 subscriptions against a budget of 8 (§4.2). Feeding σ_B
//     into the KDF yields a uniform tag whose prefix is precisely NOT σ_B.
//
//     Price, already declared: whoever knows σ_B sees those 4 bytes. That is
//     RL-9 ("a malicious contact knows the epoch's inbox shard"), not a new
//     leak. 96 bits stay underivable.
//
// (2) SERIALISATION. Every byte that enters the hash is pinned here, because
//     sender and recipient computing it differently is the P-13 error class
//     one level down: no error, no report, the tag simply never matches.
//       * request exactly the bytes used — no derive-then-truncate
//       * salt/info split follows the pattern §3.3 sets for the per-message
//         KEM, so domain separation is visible in the same place as elsewhere
//       * `direction` is one byte, derived from the founding keys, so both
//         sides agree without negotiating
//       * `epoch` and `n` are fixed 8-byte big-endian. Without fixed width
//         the concatenation is ambiguous — `epoch=1, n=23` and `epoch=12,
//         n=3` would produce the same input and therefore the same tag. That
//         is a collision path in the delivery primitive, not a style issue.
//
// ── What this does not change ───────────────────────────────────────────
//
// `K_AB` is X25519-NIKE and NOT post-quantum secure (§8.8). A CRQC adversary
// holding an archived field can link tags retroactively — content stays
// protected, a pair's traffic volume becomes linkable. Nothing here claims
// otherwise.

import 'dart:typed_data';

import 'package:cleona/core/config/network_channel.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';

/// Tag length on the wire (§2.3a spore frame).
const int kTagBytes = 16;

/// Bytes of the tag taken from the inbox shard family σ_B (E-73).
///
/// Fixed at 4: ℓ reaches ~24 bits at a billion nodes (§4.2 scaling table), so
/// four bytes cover every field size the design contemplates, and a fixed
/// width means a tag planted before a split still matches after it.
const int kShardPrefixBytes = 4;

/// Bytes of the tag taken from the pairwise KDF. 96 bits of underivability.
const int kPairwiseBytes = kTagBytes - kShardPrefixBytes;

/// Uniform epoch definition (§2.4, E-22) — congruent with the default TTL.
const int kEpochDays = 14;

/// Domain separation for the tag line, following the §3.3 pattern.
const String kTagSaltLabel = 'cleona-tag/salt/v1';

/// Domain separation for the inbox-shard line (§4.2, E-39).
const String kInboxSaltLabel = 'cleona-inbox/salt/v1';

/// `epoch = floor(unixDays / 14)` (§2.4, E-22). Callers apply the ±1
/// tolerance; this function does not, because the tolerance is a lookup
/// policy, not a property of the epoch.
int epochOf(DateTime utc) =>
    (utc.toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay) ~/
    kEpochDays;

Uint8List _be64(int v) {
  final b = Uint8List(8);
  final d = ByteData.view(b.buffer);
  d.setUint64(0, v, Endian.big);
  return b;
}

Uint8List _label(String s) =>
    SodiumFFI().sha256(Uint8List.fromList(s.codeUnits));

/// Direction byte (E-73, T-2.3): `0x00` when the lexicographically smaller
/// founding public key is the sender, `0x01` otherwise.
///
/// Deterministic from the keys alone — both sides arrive at the same value
/// with no negotiation, and the two directions of a pair can never collapse
/// onto one tag line.
int directionByte(Uint8List senderFoundingPk, Uint8List recipientFoundingPk) {
  final n = senderFoundingPk.length < recipientFoundingPk.length
      ? senderFoundingPk.length
      : recipientFoundingPk.length;
  for (var i = 0; i < n; i++) {
    if (senderFoundingPk[i] != recipientFoundingPk[i]) {
      return senderFoundingPk[i] < recipientFoundingPk[i] ? 0x00 : 0x01;
    }
  }
  return senderFoundingPk.length <= recipientFoundingPk.length ? 0x00 : 0x01;
}

/// The inbox shard family σ_B = HKDF(inbox_key_B, epoch) (§4.2, E-22/E-39).
///
/// Returns exactly [kShardPrefixBytes] — the bytes that are used, not a
/// larger block that would then be truncated somewhere else.
Uint8List inboxShardPrefix(Uint8List inboxKey, int epoch) =>
    SodiumFFI().hkdfSha256(
      inboxKey,
      salt: _label(kInboxSaltLabel),
      info: _be64(epoch),
      length: kShardPrefixBytes,
    );

/// The pairwise half of the tag:
/// `HKDF(K_AB, "tag" ‖ direction ‖ epoch ‖ n ‖ kNetworkChannel)`.
Uint8List pairwiseTagPart(
  Uint8List kAb, {
  required int direction,
  required int epoch,
  required int counter,
  String? channel,
}) {
  // kNetworkChannel closes the tag line against the other network channel
  // (E-85, §2.4/§2.7). It sits LAST, after the three fixed-width fields:
  // the two literals in use are both 11 bytes by coincidence, not by design,
  // and a channel name of a different length placed anywhere else would
  // reintroduce the concatenation ambiguity this file guards against (see
  // the epoch/counter width comment above). Last, it is unambiguous at any
  // length.
  final info = BytesBuilder()
    ..add('tag'.codeUnits)
    ..addByte(direction)
    ..add(_be64(epoch))
    ..add(_be64(counter))
    ..add((channel ?? kNetworkChannel).codeUnits);
  return SodiumFFI().hkdfSha256(
    kAb,
    salt: _label(kTagSaltLabel),
    info: info.toBytes(),
    length: kPairwiseBytes,
  );
}

/// The full 16-byte tag: σ_B prefix spliced onto the pairwise part (E-73).
///
/// [shardPrefix] must be [kShardPrefixBytes] long — pass the result of
/// [inboxShardPrefix] for the **recipient's** inbox key and the same epoch
/// the tag is derived for.
Uint8List deriveTag({
  required Uint8List shardPrefix,
  required Uint8List kAb,
  required int direction,
  required int epoch,
  required int counter,
  String? channel,
}) {
  if (shardPrefix.length != kShardPrefixBytes) {
    throw ArgumentError(
        'shardPrefix must be $kShardPrefixBytes B, got ${shardPrefix.length}');
  }
  final out = Uint8List(kTagBytes);
  out.setRange(0, kShardPrefixBytes, shardPrefix);
  out.setRange(
      kShardPrefixBytes,
      kTagBytes,
      pairwiseTagPart(kAb,
          direction: direction,
          epoch: epoch,
          counter: counter,
          channel: channel));
  return out;
}
