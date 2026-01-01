/// Link handshake MAC — the `MAC(L_node, E2(eph_pub) ‖ time_epoch)` field of
/// the `init` cell (AP-3a stage 2; architecture v4 §2.6, decisions E-78 and
/// E-80).
///
/// **This file freezes wire-relevant cryptography.** Guarded by
/// `test/smoke/smoke_link_mac.dart` (golden vectors + independent
/// recomputation from primitives).
///
/// ```
/// time_epoch = ⌊unix_seconds / 3600⌋        // one hour, 8 B big-endian
/// mac        = hmacSha256(L_node, E2(eph_pub) ‖ encodeEpoch(time_epoch))[0..16]
/// ```
///
/// Decisions carried by this layout:
///
/// - **The leading 16 bytes (E-80).** V4 §2.6 said "truncated to 16 B"
///   without saying *which* 16, and §2.4 forbids unspecified truncation
///   outright ("Exactly the bytes used are requested from HKDF … Nothing is
///   derived at a larger width and then truncated somewhere else"). HMAC
///   cannot be asked for an exact width, so the choice had to be made and it
///   is wire format. It follows the house, not taste: `network_secret.dart`
///   truncates in five places with `sublist(0, length)` (packet HMAC 8 B,
///   network tag 16 B, hint HMAC), and RFC 2104 §5 prescribes the leftmost
///   bits.
/// - **One hour, 8 bytes big-endian, acceptance ±1 (E-78).** Fixed width for
///   the reason §2.4 gives for tags: without it the concatenation is
///   ambiguous — a 32-byte `E2(eph_pub)` followed by a variable-width epoch
///   could be re-read as a different split. The hour is a **named
///   exception** to the single 14-day epoch of §2.4, which would leave a
///   captured `init` replayable for 14 to 42 days.
/// - **Clock tolerance and replay window are the same number.** ±1 epoch is
///   at most a two-hour window in both roles; widening one widens the other.
///   Cleona deliberately carries **no clock of its own** (E-78): setting the
///   system clock is the operating system's job, and an in-app time offset
///   would be a second clock with its own attack surface. Hence
///   [currentLinkEpoch] reads the system clock, and the only injection point
///   is the test-only `now` parameter.
/// - **Verification does the same work for all three epochs.** §2.6 requires
///   the check to run in constant time and the node to stay silent on
///   failure — "no measurable time difference". A loop that returned on the
///   first hit would run one, two or three HMACs depending on *which* epoch
///   matched, and that difference is measurable from outside. See
///   [verifyInitMac].
///
/// Not in this file, deliberately: the replay buffer of E-79 (a hit there is
/// treated *exactly* like a failed MAC, so it is the caller that must merge
/// the two into one silent branch), `L_node` generation, rotation and
/// persistence (E-81, §3.5.2), and the AEAD part of `init` (E-82).
///
/// The implementation uses only house primitives: `hmacSha256`
/// (lib/core/crypto/sodium_ffi.dart) and `constantTimeEquals`
/// (lib/core/crypto/constant_time.dart). No new cryptography.
library;

import 'dart:typed_data';

import 'package:cleona/core/crypto/constant_time.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';

abstract final class LinkMac {
  static final _sodium = SodiumFFI();

  /// Length of `L_node`, the per-node link key (§2.6: "32 B, randomly
  /// generated at first start, rotatable").
  static const int lNodeLength = 32;

  /// Length of `E2(eph_pub)`, the Elligator2-encoded ephemeral public key
  /// (§2.6, flight 1: 32 B).
  static const int e2EphPubLength = 32;

  /// Length of the MAC field on the wire: the **leading** 16 bytes of
  /// HMAC-SHA-256 (E-80).
  static const int macLength = 16;

  /// Width of the encoded `time_epoch`, in bytes (E-78: 8 B big-endian).
  static const int epochLength = 8;

  /// Seconds per link epoch (E-78: `⌊unix_seconds / 3600⌋`).
  static const int epochSeconds = 3600;

  /// Number of epochs accepted on either side of the current one (E-78:
  /// "The responder accepts epoch ±1"), giving an acceptance window of at
  /// most two hours.
  static const int epochTolerance = 1;

  /// The current link epoch, `⌊unix_seconds / 3600⌋`.
  ///
  /// [now] exists for tests only; production always reads the system clock,
  /// because E-78 rules out an app-internal time offset.
  ///
  /// Floor division, not truncation: `~/` rounds toward zero, which would
  /// disagree with `⌊⌋` for timestamps before 1970. Unreachable in practice,
  /// but the spec says floor.
  static int currentLinkEpoch({DateTime? now}) {
    final millis = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final seconds = _floorDiv(millis, 1000);
    return _floorDiv(seconds, epochSeconds);
  }

  /// Encodes [epoch] as 8 bytes big-endian (E-78).
  ///
  /// The width is fixed and unconditional — that is the whole point. A
  /// minimal-width encoding would make `E2(eph_pub) ‖ epoch` ambiguous, the
  /// same failure §2.4 names for tag inputs.
  ///
  /// Negative epochs (pre-1970 clocks) encode as two's complement, the
  /// natural reading of "8 bytes big-endian" for a signed 64-bit integer.
  /// The spec does not name a signedness; nothing in the protocol can reach
  /// that range without a system clock set before 1970.
  static Uint8List encodeEpoch(int epoch) {
    final out = Uint8List(epochLength);
    var v = epoch;
    for (var i = epochLength - 1; i >= 0; i--) {
      out[i] = v & 0xff;
      v >>= 8;
    }
    return out;
  }

  /// Computes the `init` MAC for an explicit [epoch].
  ///
  /// `mac = hmacSha256(lNode, e2EphPub ‖ encodeEpoch(epoch))[0..16]` — the
  /// **leading** 16 bytes (E-80).
  ///
  /// Throws [ArgumentError] if [lNode] is not [lNodeLength] bytes or
  /// [e2EphPub] is not [e2EphPubLength] bytes. A short `L_node` would be
  /// zero-padded silently by `hmacSha256` (RFC 2104 key normalization), and
  /// a silently weakened key is exactly what must not happen here.
  static Uint8List computeInitMac(
      Uint8List lNode, Uint8List e2EphPub, int epoch) {
    _requireLength('L_node', lNode, lNodeLength);
    _requireLength('E2(eph_pub)', e2EphPub, e2EphPubLength);

    final data = Uint8List(e2EphPubLength + epochLength)
      ..setRange(0, e2EphPubLength, e2EphPub)
      ..setRange(e2EphPubLength, e2EphPubLength + epochLength,
          encodeEpoch(epoch));

    final full = _sodium.hmacSha256(lNode, data);
    return Uint8List.fromList(full.sublist(0, macLength));
  }

  /// Verifies [mac] against the current epoch and its two neighbours
  /// (E-78: acceptance ±1, effective window up to 2 h).
  ///
  /// **Every call does the same work**, regardless of which epoch matches or
  /// whether any does: exactly `2 * epochTolerance + 1` HMACs are computed
  /// and exactly that many full-length constant-time comparisons are run, in
  /// a fixed order. There is deliberately no early `return true` on the
  /// first hit — that would make the runtime say *which* epoch matched,
  /// which is the "measurable time difference" §2.6 rules out. The
  /// byte-level comparison is [constantTimeEquals], so the position of a
  /// differing byte does not leak either.
  ///
  /// A `false` here must lead to silence, not to an error reply (§2.6), and
  /// it must be indistinguishable from a replay-buffer hit (E-79).
  ///
  /// [now] exists for tests only; see [currentLinkEpoch].
  static bool verifyInitMac(
      Uint8List lNode, Uint8List e2EphPub, Uint8List mac,
      {DateTime? now}) {
    _requireLength('L_node', lNode, lNodeLength);
    _requireLength('E2(eph_pub)', e2EphPub, e2EphPubLength);
    _requireLength('mac', mac, macLength);

    final base = currentLinkEpoch(now: now);
    var hits = 0;
    for (var delta = -epochTolerance; delta <= epochTolerance; delta++) {
      final candidate = computeInitMac(lNode, e2EphPub, base + delta);
      // Accumulate; never short-circuit. Both arms of the select are
      // constants, so the loop count and the number of compared bytes stay
      // independent of the secret.
      hits += constantTimeEquals(candidate, mac) ? 1 : 0;
    }
    return hits > 0;
  }

  static void _requireLength(String what, Uint8List value, int expected) {
    if (value.length != expected) {
      throw ArgumentError(
          'LinkMac: $what must be $expected bytes, got ${value.length}');
    }
  }

  /// Floor division for positive [b]; Dart's `~/` truncates toward zero.
  static int _floorDiv(int a, int b) {
    final q = a ~/ b;
    return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q;
  }
}
