// Step-0 gate for native/cleona_link (migration plan §4d.2 step 0).
//
// Checks the three exported shim symbols against the TEST VECTORS OF THE
// UPSTREAM (test/elligator_vectors.h, unchanged from Monocypher 4.0.3
// tests/tis-ci-vectors.h) and the round trip rev → map:
//
//   1. map vectors (elligator_dir): uniform bytes → curve point.
//   2. rev vectors (elligator_inv): curve point + tweak → uniform bytes,
//      INCLUDING the failure cases: rev returns -1 if the point is not
//      encodable — only roughly half are. A test that does not
//      handle that is wrong; the upstream vectors contain both cases
//      and the expected value is checked exactly here.
//   3. round trip via key_pair: hidden → map → curve point → rev (with
//      random tweak) MUST succeed (the point stems from the image of the
//      mapping) → map reproduces the starting point byte-identically.
//   4. random inputs to rev: the failure rate must lie close to 1/2
//      (deterministic PRNG, fixed bounds) — proves that the
//      -1 branch really runs in normal operation and not only in
//      hand-picked vectors.
//
// Reverse probe: the same program, linked against cleona_link_saboteur
// (CLEONA_LINK_SABOTAGE flips a bit in the map result), MUST fail with exit != 0.
// Built as smoke_link_elligator_sabotage (CMakeLists.txt).
//
// Deliberately ONLY via the three exported symbols — the test checks the
// library that Dart loads later, not the vendored sources directly.

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "elligator_vectors.h"

// Prototypes of the three shim exports (no header of its own — like cleona_pow
// the ABI is consumed by Dart FFI, not by C includers).
extern void cleona_link_elligator_map(uint8_t curve[32],
                                      const uint8_t hidden[32]);
extern int  cleona_link_elligator_rev(uint8_t hidden[32],
                                      const uint8_t curve[32], uint8_t tweak);
extern void cleona_link_elligator_key_pair(uint8_t hidden[32],
                                           uint8_t secret_key[32],
                                           uint8_t seed[32]);

static int g_failures = 0;

#define CHECK(cond, ...) do {                                   \
    if (!(cond)) {                                              \
        g_failures++;                                           \
        printf("FAIL %s:%d: ", __FILE__, __LINE__);             \
        printf(__VA_ARGS__);                                    \
        printf("\n");                                           \
    }                                                           \
} while (0)

static int hex_nibble(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

// Decodes a vector hex string; returns the byte length.
static size_t from_hex(uint8_t *out, size_t cap, const char *hex)
{
    size_t n = strlen(hex);
    if (n % 2 != 0 || n / 2 > cap) {
        fprintf(stderr, "vector format broken: '%s'\n", hex);
        exit(2);
    }
    for (size_t i = 0; i < n / 2; i++) {
        int hi = hex_nibble(hex[2 * i]);
        int lo = hex_nibble(hex[2 * i + 1]);
        if (hi < 0 || lo < 0) {
            fprintf(stderr, "vector format broken: '%s'\n", hex);
            exit(2);
        }
        out[i] = (uint8_t)((hi << 4) | lo);
    }
    return n / 2;
}

// Deterministic PRNG (splitmix64) — reproducible runs, fixed
// statistical bounds without flakiness.
static uint64_t g_rng_state = 0x9e3779b97f4a7c15ULL;
static uint64_t rng_next64(void)
{
    uint64_t z = (g_rng_state += 0x9e3779b97f4a7c15ULL);
    z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
    z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
    return z ^ (z >> 31);
}
static void rng_fill(uint8_t *buf, size_t n)
{
    for (size_t i = 0; i < n; i++) {
        if (i % 8 == 0) {
            uint64_t v = rng_next64();
            memcpy(buf + i, &v, (n - i) < 8 ? (n - i) : 8);
            i += 7;
        }
    }
}

// ── 1. Upstream-Vektoren: map (uniforme Bytes → Kurvenpunkt) ────────────────
static void test_dir_vectors(void)
{
    size_t pairs = nb_elligator_dir_vectors / 2;
    for (size_t i = 0; i < pairs; i++) {
        uint8_t hidden[32], expected[32], curve[32];
        from_hex(hidden,   32, elligator_dir_vectors[2 * i]);
        from_hex(expected, 32, elligator_dir_vectors[2 * i + 1]);
        cleona_link_elligator_map(curve, hidden);
        CHECK(memcmp(curve, expected, 32) == 0,
              "map vector %zu: output does not match upstream", i);
    }
    printf("  map vectors:        %zu checked\n", pairs);
}

// ── 2. Upstream-Vektoren: rev (Kurvenpunkt → uniforme Bytes, inkl. -1) ──────
static void test_inv_vectors(void)
{
    size_t quads = nb_elligator_inv_vectors / 4;
    size_t fail_cases = 0;
    for (size_t i = 0; i < quads; i++) {
        uint8_t point[32], tweak, failure, expected[32], hidden[32];
        uint8_t tmp[32];
        from_hex(point, 32, elligator_inv_vectors[4 * i]);
        from_hex(tmp,   32, elligator_inv_vectors[4 * i + 1]); tweak   = tmp[0];
        from_hex(tmp,   32, elligator_inv_vectors[4 * i + 2]); failure = tmp[0];
        size_t explen = from_hex(expected, 32, elligator_inv_vectors[4 * i + 3]);

        int check = cleona_link_elligator_rev(hidden, point, tweak);
        CHECK((uint8_t)check == failure,
              "rev vector %zu: return %d, upstream expects 0x%02x",
              i, check, failure);
        if (failure == 0x00) {
            CHECK(explen == 32 && memcmp(hidden, expected, 32) == 0,
                  "rev vector %zu: hidden does not match upstream", i);
        } else {
            fail_cases++;
        }
    }
    printf("  rev vectors:        %zu checked (%zu thereof -1 cases)\n",
           quads, fail_cases);
    // The vector set must contain both branches, otherwise it does not check the
    // -1 path.
    CHECK(fail_cases > 0 && fail_cases < quads,
          "upstream vector set does not cover both rev outcomes");
}

// ── 3. Round-Trip: key_pair → map → rev → map ───────────────────────────────
static void test_round_trip(void)
{
    enum { N = 1000 };
    for (int i = 0; i < N; i++) {
        uint8_t seed[32], hidden[32], sk[32];
        rng_fill(seed, 32);
        cleona_link_elligator_key_pair(hidden, sk, seed);
        // Monocypher contract: seed is now wiped.
        CHECK(memcmp(seed, (uint8_t[32]){0}, 32) == 0,
              "round trip %d: key_pair did not wipe the seed", i);

        uint8_t curve[32];
        cleona_link_elligator_map(curve, hidden);

        // curve stems from the image of the mapping → rev MUST succeed,
        // independent of the tweak (encodability does not depend on the tweak).
        uint8_t tweak = (uint8_t)rng_next64();
        uint8_t hidden2[32];
        int check = cleona_link_elligator_rev(hidden2, curve, tweak);
        CHECK(check == 0,
              "round trip %d: rev failed on a representable point", i);
        if (check != 0) continue;

        // rev → map must reproduce the starting point byte-identically.
        // (hidden2 itself may deviate from hidden: tweak chooses root
        // and MSB padding bits.)
        uint8_t curve2[32];
        cleona_link_elligator_map(curve2, hidden2);
        CHECK(memcmp(curve2, curve, 32) == 0,
              "round trip %d: rev->map does not reproduce the point", i);
    }
    printf("  round trip:         %d keypairs, rev->map reproduced\n", N);
}

// ── 4. Random inputs: the -1 branch carries in normal operation ────────────────
static void test_random_rev(void)
{
    enum { N = 1000 };
    int failures = 0;
    for (int i = 0; i < N; i++) {
        uint8_t input[32], hidden[32];
        rng_fill(input, 32);
        uint8_t tweak = (uint8_t)rng_next64();
        int check = cleona_link_elligator_rev(hidden, input, tweak);
        if (check != 0) {
            failures++;
            continue;
        }
        // Success branch: the result must be a consistent representative
        // — map(hidden) delivers a point whose re-encoding
        // and decoding yield the same point.
        uint8_t p[32], hidden2[32], p2[32];
        cleona_link_elligator_map(p, hidden);
        int c2 = cleona_link_elligator_rev(hidden2, p, (uint8_t)rng_next64());
        CHECK(c2 == 0, "random rev %d: re-encoding a decoded point failed", i);
        if (c2 != 0) continue;
        cleona_link_elligator_map(p2, hidden2);
        CHECK(memcmp(p2, p, 32) == 0,
              "random rev %d: rev->map not stable", i);
    }
    printf("  random rev:         %d inputs, %d rejected (-1)\n", N, failures);
    // Only roughly half of all points is encodable. Bounds deliberately
    // wide (binomial N=1000, p~0.5: >6 sigma), deterministic PRNG.
    CHECK(failures >= 350 && failures <= 650,
          "rev rejection rate %d/%d is not compatible with ~1/2", failures, N);
}

int main(void)
{
    printf("smoke_link_elligator — Stufe-0-Gate (Monocypher 4.0.3 vectors)\n");
    test_dir_vectors();
    test_inv_vectors();
    test_round_trip();
    test_random_rev();
    if (g_failures == 0) {
        printf("PASS: all elligator gates green\n");
        return 0;
    }
    printf("FAIL: %d check(s) failed\n", g_failures);
    return 1;
}
