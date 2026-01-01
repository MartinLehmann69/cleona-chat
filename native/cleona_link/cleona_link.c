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
// with -fvisibility=hidden, so that the ~100 Monocypher symbols (and the
// BearSSL br_* symbols, see "AES-256-GCM in software" below) are NOT exported
// from the shared library; visible are exactly the five cleona_link_*
// functions below (three Elligator2, two AES-256-GCM). (cleona_pow has only
// one symbol of its own and links libsodium dynamically — the question does
// not arise there.)
//
// Why exactly these three Elligator2 symbols:
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
//
// AES-256-GCM IN SOFTWARE (v4_2 §4.2, D-130, S430). The two exports
// cleona_link_aes256gcm_encrypt/decrypt carry AES-256-GCM on a processor
// where libsodium's crypto_aead_aes256gcm_is_available() is 0 (no
// AES-NI/PCLMUL/AVX, or ARMv8 without crypto extensions): libsodium executes
// the AES instructions there unchecked and the process dies with an
// illegal-instruction fault (field report S430 WT-1). The implementation is
// BearSSL 0.6 aes_ct64 + ghash_ctmul64 + gcm, vendored under vendor/bearssl/
// (origin and checksums in vendor/bearssl/README.txt): bitsliced AES and
// GHASH in constant time, no tables, no special instructions.
//
// Contract = libsodium's combined mode, byte for byte, so that the Dart side
// binds both with the same function type and every byte on the wire and on
// disk stays the same:
//   encrypt: c = ciphertext || 16-byte tag, *clen_p = mlen + 16 (if not
//            NULL), 12-byte nonce, 32-byte key, optional AD; nsec unused.
//            Returns 0; -1 if mlen exceeds the GCM limit (libsodium aborts
//            there via sodium_misuse()).
//   decrypt: *mlen_p = 0 first; -1 if clen < 16 or the tag does not
//            verify — then m is wiped (libsodium does the same); otherwise
//            m = plaintext, *mlen_p = clen - 16, return 0.
// The tag is compared in constant time (br_gcm_check_tag, EQ0 over the OR
// of all byte differences). c and m may be the same buffer.

#include <stdint.h>
#include <string.h>
#include "vendor/monocypher/monocypher.h"
#include "vendor/bearssl/inner.h"

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

// ── AES-256-GCM in software (BearSSL aes_ct64 + ghash_ctmul64) ──────────────

#define CLEONA_AES256GCM_KEYBYTES  32U
#define CLEONA_AES256GCM_NPUBBYTES 12U
#define CLEONA_AES256GCM_ABYTES    16U
// GCM limit of NIST SP 800-38D (2^32 - 2 blocks), the same bound as
// libsodium's crypto_aead_aes256gcm_MESSAGEBYTES_MAX; SIZE_MAX keeps the
// bound honest on a 32-bit target.
#define CLEONA_AES256GCM_MESSAGEBYTES_MAX \
    ((unsigned long long)SIZE_MAX - CLEONA_AES256GCM_ABYTES < \
             16ULL * ((1ULL << 32) - 2ULL) \
         ? (unsigned long long)SIZE_MAX - CLEONA_AES256GCM_ABYTES \
         : 16ULL * ((1ULL << 32) - 2ULL))

#if defined(_MSC_VER)
  #define CLEONA_NOINLINE __declspec(noinline)
#else
  #define CLEONA_NOINLINE __attribute__((noinline))
#endif

// BearSSL keeps the expanded round keys (br_aes_ct64_ctr_run: sk_exp[120],
// 960 bytes) and key-stream blocks in its own stack frames and does not
// clear them. This call runs at the same depth right afterwards and
// overwrites that region; crypto_wipe writes through a volatile pointer,
// so the compiler cannot drop it. 4 KiB covers the deepest BearSSL frame
// chain used here (gcm_run -> ctr_run) with margin.
static CLEONA_NOINLINE void cleona_burn_stack(void)
{
    uint8_t scratch[4096];
    crypto_wipe(scratch, sizeof scratch);
}

EXPORT int cleona_link_aes256gcm_encrypt(
    uint8_t *c, unsigned long long *clen_p,
    const uint8_t *m, unsigned long long mlen,
    const uint8_t *ad, unsigned long long adlen,
    const uint8_t *nsec, const uint8_t *npub, const uint8_t *k
) {
    br_aes_ct64_ctr_keys bc;
    br_gcm_context gc;

    (void)nsec;
    if (clen_p != NULL) {
        *clen_p = 0;
    }
    if (mlen > CLEONA_AES256GCM_MESSAGEBYTES_MAX
        || adlen > (unsigned long long)SIZE_MAX) {
        return -1;
    }

    br_aes_ct64_ctr_init(&bc, k, CLEONA_AES256GCM_KEYBYTES);
    br_gcm_init(&gc, &bc.vtable, br_ghash_ctmul64);
    br_gcm_reset(&gc, npub, CLEONA_AES256GCM_NPUBBYTES);
    if (adlen > 0) {
        br_gcm_aad_inject(&gc, ad, (size_t)adlen);
    }
    br_gcm_flip(&gc);
    if (mlen > 0) {
        memmove(c, m, (size_t)mlen);
        br_gcm_run(&gc, 1, c, (size_t)mlen);
    }
    br_gcm_get_tag(&gc, c + mlen);
#ifdef CLEONA_LINK_SABOTAGE
    c[mlen] ^= 0x01;  // Reverse probe: one flipped bit in the tag.
#endif

    crypto_wipe(&bc, sizeof bc);
    crypto_wipe(&gc, sizeof gc);
    cleona_burn_stack();
    if (clen_p != NULL) {
        *clen_p = mlen + CLEONA_AES256GCM_ABYTES;
    }
    return 0;
}

EXPORT int cleona_link_aes256gcm_decrypt(
    uint8_t *m, unsigned long long *mlen_p, uint8_t *nsec,
    const uint8_t *c, unsigned long long clen,
    const uint8_t *ad, unsigned long long adlen,
    const uint8_t *npub, const uint8_t *k
) {
    br_aes_ct64_ctr_keys bc;
    br_gcm_context gc;
    unsigned long long mlen;
    uint8_t tag[CLEONA_AES256GCM_ABYTES];
    uint32_t ok;

    (void)nsec;
    if (mlen_p != NULL) {
        *mlen_p = 0;
    }
    if (clen < CLEONA_AES256GCM_ABYTES
        || clen - CLEONA_AES256GCM_ABYTES > CLEONA_AES256GCM_MESSAGEBYTES_MAX
        || adlen > (unsigned long long)SIZE_MAX) {
        return -1;
    }
    mlen = clen - CLEONA_AES256GCM_ABYTES;
    // Tag copied out first: with m == c, decrypting in place must not
    // overwrite it (it lies behind the ciphertext, so it would not — the
    // copy keeps that independent of the layout).
    memcpy(tag, c + mlen, CLEONA_AES256GCM_ABYTES);

    br_aes_ct64_ctr_init(&bc, k, CLEONA_AES256GCM_KEYBYTES);
    br_gcm_init(&gc, &bc.vtable, br_ghash_ctmul64);
    br_gcm_reset(&gc, npub, CLEONA_AES256GCM_NPUBBYTES);
    if (adlen > 0) {
        br_gcm_aad_inject(&gc, ad, (size_t)adlen);
    }
    br_gcm_flip(&gc);
    if (mlen > 0) {
        // GHASH runs over the ciphertext before the key stream is applied
        // (br_gcm_run with encrypt == 0), so decrypting into m is the
        // standard order; m is wiped below if the tag does not verify.
        memmove(m, c, (size_t)mlen);
        br_gcm_run(&gc, 0, m, (size_t)mlen);
    }
    ok = br_gcm_check_tag(&gc, tag);

    crypto_wipe(&bc, sizeof bc);
    crypto_wipe(&gc, sizeof gc);
    crypto_wipe(tag, sizeof tag);
    cleona_burn_stack();
    if (ok != 1) {
        if (mlen > 0) {
            crypto_wipe(m, (size_t)mlen);
        }
        return -1;
    }
    if (mlen_p != NULL) {
        *mlen_p = mlen;
    }
    return 0;
}
