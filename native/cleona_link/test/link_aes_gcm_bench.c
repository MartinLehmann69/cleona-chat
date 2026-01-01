// Throughput of the AES-256-GCM software way (v4_2 §4.2, D-130, S431).
//
// The plan S430 §1 names a price: software AES on an old processor is slower
// than AES-NI, by how much is not measured; the lab probe without AES-NI
// measures it and checks that a video call (800 kbit/s) fits. This program
// measures exactly the exported functions the app uses
// (cleona_link_aes256gcm_encrypt/decrypt) — no libsodium involved.
//
// Two shapes:
//   1200-byte boxes  the size of one cell on the wire (§3) — the rate that
//                    matters for a call;
//   64 KiB boxes     bulk (files, storage).
// Each shape runs encrypt and decrypt for about 2 s of wall clock and prints
// MB/s and, for 1200 B, packets per second and the share of one core an
// 800 kbit/s stream needs (encrypt + decrypt of the same amount).
//
// Exit 1 if a decrypt fails (the timing would then measure an error path).
// Build: cmake -S native/cleona_link -B <dir> -DCLEONA_LINK_BUILD_SMOKE=ON
//        cmake --build <dir> --target bench_link_aes_gcm

#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

int cleona_link_aes256gcm_encrypt(
    uint8_t *c, unsigned long long *clen_p,
    const uint8_t *m, unsigned long long mlen,
    const uint8_t *ad, unsigned long long adlen,
    const uint8_t *nsec, const uint8_t *npub, const uint8_t *k);
int cleona_link_aes256gcm_decrypt(
    uint8_t *m, unsigned long long *mlen_p, uint8_t *nsec,
    const uint8_t *c, unsigned long long clen,
    const uint8_t *ad, unsigned long long adlen,
    const uint8_t *npub, const uint8_t *k);

static double now_s(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

#define MAX_BOX (64 * 1024)
static uint8_t g_m[MAX_BOX];
static uint8_t g_c[MAX_BOX + 16];
static uint8_t g_p[MAX_BOX];

static int run(size_t size, double seconds)
{
    uint8_t key[32], nonce[12], ad[16];
    unsigned long long clen = 0, plen = 0;
    unsigned long n_enc = 0, n_dec = 0;
    double t0, t_enc, t_dec;
    size_t i;

    for (i = 0; i < sizeof key; i++) key[i] = (uint8_t)(i * 7 + 1);
    for (i = 0; i < sizeof nonce; i++) nonce[i] = (uint8_t)(i * 13 + 5);
    for (i = 0; i < sizeof ad; i++) ad[i] = (uint8_t)(i + 0x40);
    for (i = 0; i < size; i++) g_m[i] = (uint8_t)(i * 31 + 3);

    t0 = now_s();
    do {
        nonce[0]++;
        cleona_link_aes256gcm_encrypt(g_c, &clen, g_m, size, ad, sizeof ad,
                                      NULL, nonce, key);
        n_enc++;
    } while (now_s() - t0 < seconds);
    t_enc = now_s() - t0;

    t0 = now_s();
    do {
        if (cleona_link_aes256gcm_decrypt(g_p, &plen, NULL, g_c, clen, ad,
                                          sizeof ad, nonce, key) != 0
            || plen != size) {
            printf("FAIL: decrypt of a %zu-byte box failed\n", size);
            return 1;
        }
        n_dec++;
    } while (now_s() - t0 < seconds);
    t_dec = now_s() - t0;

    {
        double enc_mbs = (double)n_enc * (double)size / t_enc / 1e6;
        double dec_mbs = (double)n_dec * (double)size / t_dec / 1e6;
        printf("  %6zu B boxes: encrypt %8.2f MB/s (%9.0f boxes/s), "
               "decrypt %8.2f MB/s (%9.0f boxes/s)\n",
               size, enc_mbs, (double)n_enc / t_enc,
               dec_mbs, (double)n_dec / t_dec);
        if (size == 1200) {
            // 800 kbit/s = 100 000 B/s, encrypted once and decrypted once.
            double share = 100000.0 / (enc_mbs * 1e6) + 100000.0 / (dec_mbs * 1e6);
            printf("  800 kbit/s video (encrypt + decrypt, 1200 B boxes): "
                   "%.3f %% of one core\n", share * 100.0);
        }
    }
    return 0;
}

int main(void)
{
    printf("bench_link_aes_gcm — AES-256-GCM software way (BearSSL aes_ct64 + ghash_ctmul64)\n");
    if (run(1200, 2.0) != 0) return 1;
    if (run(MAX_BOX, 2.0) != 0) return 1;
    printf("DONE\n");
    return 0;
}
