// cleona_link — Elligator2 for the V4 link handshake (architecture v4 §2.6).
//
// Why this shim exists (E-42, §20.4.1; migration plan §4d.5): the
// handshake needs the encoding "existing X25519 public key → uniform
// bytes". libsodium does not export this direction (re-measured: only
// crypto_core_ed25519_from_uniform — the opposite direction, and Ed25519 instead of
// X25519). The implementation is supplied by Monocypher 4.0.3, vendored under
// vendor/monocypher/ (version pinned, not "latest"; licence
// BSD-2-Clause OR CC0-1.0, SPDX line 10 of the vendored header).
//
// Pattern: native/cleona_pow/cleona_pow.c — thin shim, platform-dependent
// EXPORT macro, as few symbols as possible. Deliberate deviation: it is built
// with -fvisibility=hidden, so that the ~100 Monocypher symbols are NOT exported from
// the shared library; visible are exactly the three
// cleona_link_* functions below. (cleona_pow has only one symbol of its own and
// links libsodium dynamically — the question does not arise there.)
//
// Why exactly these three symbols:
//   cleona_link_elligator_rev       sending direction: curve point → uniform
//                                   bytes. That is the direction that justifies the shim
//                                   (§2.6: E2(eph_pub)).
//   cleona_link_elligator_map       receiving direction: uniform bytes →
//                                   curve point, for decoding the
//                                   incoming E2(eph_pub).
//   cleona_link_elligator_key_pair  key generation with an already uniform
//                                   public part — §4d.5: "for the handshake
//                                   the more convenient entry, because the
//                                   retry loop does not wander into
//                                   application code". Only roughly
//                                   half of all curve points is encodable;
//                                   without this symbol Dart would have to run the
//                                   redraw loop itself.
//
// Contract details for the later Dart FFI binding:
//   - rev returns -1 if the point is not encodable; hidden is then
//     undefined. tweak (1 byte of randomness) chooses root and MSB padding bits;
//     whether a point is encodable does NOT depend on the tweak.
//   - key_pair WIPES the passed seed (Monocypher contract,
//     crypto_wipe(seed, 32) in vendor/monocypher/monocypher.c) — the
//     caller must not reuse the buffer afterwards.
//   - key_pair has NO constant runtime (two attempts on average). That
//     is decidedly harmless: the loop runs before any
//     wire contact on discarded candidates (migration plan §4d.5,
//     "caveat"). Constant time is required where a secret
//     can be correlated — at the MAC check of the responder
//     (step 2), not here.
//
// CLEONA_LINK_SABOTAGE is the reverse probe of the gate (migration plan
// §4d.4 point 7 analogously; pattern native/cleona_voice/test/saboteur): a
// second, deliberately broken library against which the vector test
// MUST FAIL — a gate that stayed green against the defect proves
// nothing. The production build never sets the macro.

#include <stdint.h>
#include "vendor/monocypher/monocypher.h"

#ifdef _WIN32
  #define EXPORT __declspec(dllexport)
#else
  #define EXPORT __attribute__((visibility("default")))
#endif

// Uniform bytes → X25519 curve point (u-coordinate). Total function.
EXPORT void cleona_link_elligator_map(
    uint8_t curve[32],
    const uint8_t hidden[32]
) {
    crypto_elligator_map(curve, hidden);
#ifdef CLEONA_LINK_SABOTAGE
    curve[0] ^= 0x01;  // Reverse probe: one flipped bit in the result.
#endif
}

// X25519 curve point → uniform bytes. Returns 0 on success, -1 if the
// point is not encodable (roughly half of all points).
EXPORT int cleona_link_elligator_rev(
    uint8_t hidden[32],
    const uint8_t curve[32],
    uint8_t tweak
) {
    return crypto_elligator_rev(hidden, curve, tweak);
}

// Key pair with a guaranteed encodable (already uniformly encoded)
// public part. CAUTION: seed is wiped by Monocypher (in-out buffer).
EXPORT void cleona_link_elligator_key_pair(
    uint8_t hidden[32],
    uint8_t secret_key[32],
    uint8_t seed[32]
) {
    crypto_elligator_key_pair(hidden, secret_key, seed);
}
