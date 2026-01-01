// Proof-of-Work SHA-256 iteration loop in C.
// Eliminates ~1M Dart<->C FFI transitions per PoW computation by keeping
// the entire hash iteration in native code.
//
// Links against libsodium for crypto_hash_sha256.

#include <stdint.h>
#include <string.h>
#include <sodium.h>

#ifdef _WIN32
  #define EXPORT __declspec(dllexport)
#else
  #define EXPORT __attribute__((visibility("default")))
#endif

// Find a nonce such that SHA-256(digest || nonce_8LE) has at least
// `difficulty` leading zero bits.
//
// digest:      32-byte pre-hashed payload (SHA-256 of the original data)
// difficulty:  number of leading zero bits required
// result_hash: 32-byte output buffer for the winning hash
//
// Returns the winning nonce (little-endian uint64 convention, matching
// Dart's Endian.little).
EXPORT uint64_t cleona_pow_find_nonce(
    const uint8_t *digest,
    int difficulty,
    uint8_t *result_hash
) {
    uint8_t buffer[40];
    memcpy(buffer, digest, 32);

    for (uint64_t nonce = 0; ; nonce++) {
        // All target platforms (x86_64, ARM64) are little-endian.
        memcpy(buffer + 32, &nonce, 8);
        crypto_hash_sha256(result_hash, buffer, 40);

        int remaining = difficulty;
        int pass = 1;
        for (int i = 0; i < 32 && remaining > 0; i++) {
            if (remaining >= 8) {
                if (result_hash[i] != 0) { pass = 0; break; }
                remaining -= 8;
            } else {
                if (result_hash[i] & (0xFF << (8 - remaining))) {
                    pass = 0;
                    break;
                }
                remaining = 0;
            }
        }
        if (pass) return nonce;
    }
}
