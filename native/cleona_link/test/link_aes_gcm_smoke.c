// Gate for the AES-256-GCM software exports of native/cleona_link
// (v4_2 §4.2, D-130, S430; vendored BearSSL aes_ct64 + ghash_ctmul64 + gcm).
//
// Checks the two exported symbols only — the library that Dart loads, not
// the vendored sources directly:
//
//   1. NIST CAVP vectors (test/aes_gcm_vectors.h, gcmEncryptExtIV256.rsp,
//      25 vectors, 96-bit IV, 128-bit tag): encrypt yields CT || Tag byte
//      for byte; decrypt of CT || Tag yields PT.
//   2. Sabotage per vector: one flipped bit in the tag (a different bit per
//      vector, all 128 positions over the run), in the ciphertext (if
//      any), in the AD (if any), in the nonce and in the key — decrypt MUST
//      return -1, report length 0 and leave no plaintext in the output.
//   3. In-place use (c == m) for encrypt and decrypt, as libsodium allows.
//   4. clen < 16 MUST fail.
//
// Reverse probe: the same program, linked against cleona_link_saboteur
// (CLEONA_LINK_SABOTAGE flips a bit of every tag the encrypt produces),
// MUST fail with exit != 0. Built as smoke_link_aes_gcm_sabotage
// (CMakeLists.txt).

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "aes_gcm_vectors.h"

// Prototypes of the two exports (no header of its own — the ABI is the
// one of libsodium's crypto_aead_aes256gcm_encrypt/decrypt and is consumed
// by Dart FFI).
extern int cleona_link_aes256gcm_encrypt(
    uint8_t *c, unsigned long long *clen_p,
    const uint8_t *m, unsigned long long mlen,
    const uint8_t *ad, unsigned long long adlen,
    const uint8_t *nsec, const uint8_t *npub, const uint8_t *k);
extern int cleona_link_aes256gcm_decrypt(
    uint8_t *m, unsigned long long *mlen_p, uint8_t *nsec,
    const uint8_t *c, unsigned long long clen,
    const uint8_t *ad, unsigned long long adlen,
    const uint8_t *npub, const uint8_t *k);

#define MAX_BYTES 128

static int g_failures = 0;
static int g_checks = 0;

#define CHECK(cond, ...) do {                                   \
    g_checks++;                                                 \
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

static int all_zero(const uint8_t *p, size_t n)
{
    uint8_t acc = 0;
    for (size_t i = 0; i < n; i++) acc |= p[i];
    return acc == 0;
}

typedef struct {
    uint8_t key[32], iv[12];
    uint8_t pt[MAX_BYTES], aad[MAX_BYTES], ct[MAX_BYTES], tag[16];
    size_t pt_len, aad_len, ct_len;
} decoded;

static void decode(decoded *d, const aes_gcm_vector *v)
{
    if (from_hex(d->key, sizeof d->key, v->key) != 32
        || from_hex(d->iv, sizeof d->iv, v->iv) != 12
        || from_hex(d->tag, sizeof d->tag, v->tag) != 16) {
        fprintf(stderr, "vector with wrong key/iv/tag length\n");
        exit(2);
    }
    d->pt_len = from_hex(d->pt, sizeof d->pt, v->pt);
    d->aad_len = from_hex(d->aad, sizeof d->aad, v->aad);
    d->ct_len = from_hex(d->ct, sizeof d->ct, v->ct);
    if (d->ct_len != d->pt_len) {
        fprintf(stderr, "vector with CT length != PT length\n");
        exit(2);
    }
}

// Decrypt that MUST fail; checks rc, reported length and wiped output.
static void expect_reject(size_t idx, const char *what, const uint8_t *box,
                          size_t box_len, const uint8_t *aad, size_t aad_len,
                          const uint8_t *iv, const uint8_t *key)
{
    uint8_t out[MAX_BYTES + 1];
    unsigned long long out_len = 12345;
    memset(out, 0xA5, sizeof out);
    int rc = cleona_link_aes256gcm_decrypt(
        out, &out_len, NULL, box, box_len,
        aad_len ? aad : NULL, aad_len, iv, key);
    CHECK(rc == -1, "vector %zu: %s: decrypt returned %d, expected -1",
          idx, what, rc);
    CHECK(out_len == 0, "vector %zu: %s: reported length %llu, expected 0",
          idx, what, out_len);
    CHECK(box_len < 16 || all_zero(out, box_len - 16),
          "vector %zu: %s: output not wiped after rejection", idx, what);
}

// ── 1 + 2. NIST vectors and sabotage per vector ─────────────────────────────
static void test_vectors(void)
{
    size_t rejects = 0;
    for (size_t i = 0; i < NB_AES_GCM_VECTORS; i++) {
        decoded d;
        decode(&d, &aes_gcm_vectors[i]);
        const uint8_t *aad = d.aad_len ? d.aad : NULL;

        // Encrypt: CT || Tag.
        uint8_t box[MAX_BYTES + 16];
        unsigned long long box_len = 0;
        int rc = cleona_link_aes256gcm_encrypt(
            box, &box_len, d.pt, d.pt_len, aad, d.aad_len, NULL, d.iv, d.key);
        CHECK(rc == 0, "vector %zu: encrypt returned %d", i, rc);
        CHECK(box_len == d.pt_len + 16,
              "vector %zu: encrypt length %llu, expected %zu", i, box_len,
              d.pt_len + 16);
        CHECK(memcmp(box, d.ct, d.ct_len) == 0,
              "vector %zu: ciphertext differs from NIST", i);
        CHECK(memcmp(box + d.ct_len, d.tag, 16) == 0,
              "vector %zu: tag differs from NIST", i);

        // Decrypt the NIST CT || Tag (not our own output).
        uint8_t ref[MAX_BYTES + 16];
        memcpy(ref, d.ct, d.ct_len);
        memcpy(ref + d.ct_len, d.tag, 16);
        uint8_t out[MAX_BYTES + 1];
        unsigned long long out_len = 0;
        rc = cleona_link_aes256gcm_decrypt(
            out, &out_len, NULL, ref, d.ct_len + 16, aad, d.aad_len, d.iv,
            d.key);
        CHECK(rc == 0, "vector %zu: decrypt returned %d", i, rc);
        CHECK(out_len == d.pt_len, "vector %zu: decrypt length %llu", i,
              out_len);
        CHECK(memcmp(out, d.pt, d.pt_len) == 0,
              "vector %zu: plaintext differs from NIST", i);

        // Sabotage: one flipped bit in the tag (position spread over all
        // 128 bits across the vectors: 5 bits per vector, 25 vectors).
        for (unsigned b = 0; b < 5; b++) {
            unsigned bit = (unsigned)(i * 5 + b) % 128;
            uint8_t bad[MAX_BYTES + 16];
            memcpy(bad, ref, d.ct_len + 16);
            bad[d.ct_len + bit / 8] ^= (uint8_t)(1u << (bit % 8));
            expect_reject(i, "flipped tag bit", bad, d.ct_len + 16, d.aad,
                          d.aad_len, d.iv, d.key);
            rejects++;
        }
        if (d.ct_len > 0) {
            uint8_t bad[MAX_BYTES + 16];
            memcpy(bad, ref, d.ct_len + 16);
            bad[i % d.ct_len] ^= 0x80;
            expect_reject(i, "flipped ciphertext bit", bad, d.ct_len + 16,
                          d.aad, d.aad_len, d.iv, d.key);
            rejects++;
        }
        if (d.aad_len > 0) {
            uint8_t bad_aad[MAX_BYTES];
            memcpy(bad_aad, d.aad, d.aad_len);
            bad_aad[d.aad_len - 1] ^= 0x01;
            expect_reject(i, "flipped AD bit", ref, d.ct_len + 16, bad_aad,
                          d.aad_len, d.iv, d.key);
            rejects++;
        } else {
            // AD added where there was none.
            const uint8_t extra[1] = {0};
            expect_reject(i, "AD added", ref, d.ct_len + 16, extra, 1, d.iv,
                          d.key);
            rejects++;
        }
        {
            uint8_t bad_iv[12];
            memcpy(bad_iv, d.iv, 12);
            bad_iv[11] ^= 0x01;
            expect_reject(i, "flipped nonce bit", ref, d.ct_len + 16, d.aad,
                          d.aad_len, bad_iv, d.key);
            rejects++;
        }
        {
            uint8_t bad_key[32];
            memcpy(bad_key, d.key, 32);
            bad_key[0] ^= 0x01;
            expect_reject(i, "flipped key bit", ref, d.ct_len + 16, d.aad,
                          d.aad_len, d.iv, bad_key);
            rejects++;
        }
    }
    printf("  NIST vectors:       %zu checked (encrypt + decrypt)\n",
           (size_t)NB_AES_GCM_VECTORS);
    printf("  sabotage cases:     %zu rejected as required\n", rejects);
}

// ── 3. In-place use (c == m) ────────────────────────────────────────────────
static void test_in_place(void)
{
    decoded d;
    decode(&d, &aes_gcm_vectors[NB_AES_GCM_VECTORS - 1]);  // 51 B PT, 90 B AD
    uint8_t buf[MAX_BYTES + 16];
    memcpy(buf, d.pt, d.pt_len);
    unsigned long long len = 0;
    int rc = cleona_link_aes256gcm_encrypt(
        buf, &len, buf, d.pt_len, d.aad, d.aad_len, NULL, d.iv, d.key);
    CHECK(rc == 0 && len == d.pt_len + 16, "in-place encrypt rc=%d len=%llu",
          rc, len);
    CHECK(memcmp(buf, d.ct, d.ct_len) == 0 &&
              memcmp(buf + d.ct_len, d.tag, 16) == 0,
          "in-place encrypt differs from NIST");
    rc = cleona_link_aes256gcm_decrypt(
        buf, &len, NULL, buf, d.pt_len + 16, d.aad, d.aad_len, d.iv, d.key);
    CHECK(rc == 0 && len == d.pt_len, "in-place decrypt rc=%d len=%llu", rc,
          len);
    CHECK(memcmp(buf, d.pt, d.pt_len) == 0, "in-place decrypt differs");
    printf("  in-place:           encrypt + decrypt checked\n");
}

// ── 4. Too short ────────────────────────────────────────────────────────────
static void test_too_short(void)
{
    uint8_t key[32] = {0}, iv[12] = {0}, box[15] = {0}, out[16];
    unsigned long long out_len = 99;
    int rc = cleona_link_aes256gcm_decrypt(out, &out_len, NULL, box,
                                           sizeof box, NULL, 0, iv, key);
    CHECK(rc == -1 && out_len == 0, "clen 15: rc=%d len=%llu", rc, out_len);
    printf("  too short:          clen < 16 rejected\n");
}

int main(void)
{
    printf("smoke_link_aes_gcm — AES-256-GCM software exports (BearSSL 0.6)\n");
    test_vectors();
    test_in_place();
    test_too_short();
    if (g_failures == 0) {
        printf("PASS: all %d AES-256-GCM checks green\n", g_checks);
        return 0;
    }
    printf("FAIL: %d of %d check(s) failed\n", g_failures, g_checks);
    return 1;
}
