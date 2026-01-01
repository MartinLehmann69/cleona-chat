/*
 * Copyright (c) 2016 Thomas Pornin <pornin@bolet.org>
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
 * BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
 * ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

/*
 * REDUCED HEADER FOR CLEONA (not an upstream file).
 *
 * Upstream BearSSL 0.6 compiles every source against src/inner.h, which
 * pulls in src/config.h and inc/bearssl.h, i.e. all thirteen public headers
 * (about 15 000 lines: TLS, X.509, RSA, EC, ...). Cleona vendors only the
 * seven source files that make up AES-256-GCM (README.txt). This header
 * replaces src/inner.h for exactly those files and carries nothing else:
 * every declaration below is copied from the upstream file named in its
 * section heading, with the Doxygen comments shortened; nothing was
 * reworded in code.
 *
 * One deliberate deviation: the byte codec functions keep only their
 * portable branch (byte-wise shifts). Upstream additionally has a branch
 * that reads and writes through unions on unaligned addresses when
 * BR_LE_UNALIGNED / BR_BE_UNALIGNED is detected (x86, POWER). That branch
 * computes the same values; dropping it removes the platform detection
 * block of src/inner.h (and its compiler-version probes) from the build.
 */

#ifndef CLEONA_BEARSSL_INNER_H__
#define CLEONA_BEARSSL_INNER_H__

#include <stddef.h>
#include <stdint.h>
#include <string.h>

/* ==================================================================== */
/* From inc/bearssl_block.h (class type for CTR implementations).        */

typedef struct br_block_ctr_class_ br_block_ctr_class;
struct br_block_ctr_class_ {
	size_t context_size;
	unsigned block_size;
	unsigned log_block_size;
	void (*init)(const br_block_ctr_class **ctx,
		const void *key, size_t key_len);
	uint32_t (*run)(const br_block_ctr_class *const *ctx,
		const void *iv, uint32_t cc, void *data, size_t len);
};

/* From inc/bearssl_block.h (aes_ct64, CTR keys and functions). */

typedef struct {
	const br_block_ctr_class *vtable;
	uint64_t skey[30];
	unsigned num_rounds;
} br_aes_ct64_ctr_keys;

extern const br_block_ctr_class br_aes_ct64_ctr_vtable;

void br_aes_ct64_ctr_init(br_aes_ct64_ctr_keys *ctx,
	const void *key, size_t len);

uint32_t br_aes_ct64_ctr_run(const br_aes_ct64_ctr_keys *ctx,
	const void *iv, uint32_t cc, void *data, size_t len);

/* ==================================================================== */
/* From inc/bearssl_hash.h (GHASH).                                      */

typedef void (*br_ghash)(void *y, const void *h, const void *data, size_t len);

void br_ghash_ctmul64(void *y, const void *h, const void *data, size_t len);

/* ==================================================================== */
/* From inc/bearssl_aead.h (AEAD class type, GCM context and functions). */

typedef struct br_aead_class_ br_aead_class;
struct br_aead_class_ {
	size_t tag_size;
	void (*reset)(const br_aead_class **cc, const void *iv, size_t len);
	void (*aad_inject)(const br_aead_class **cc,
		const void *data, size_t len);
	void (*flip)(const br_aead_class **cc);
	void (*run)(const br_aead_class **cc, int encrypt,
		void *data, size_t len);
	void (*get_tag)(const br_aead_class **cc, void *tag);
	uint32_t (*check_tag)(const br_aead_class **cc, const void *tag);
	void (*get_tag_trunc)(const br_aead_class **cc, void *tag, size_t len);
	uint32_t (*check_tag_trunc)(const br_aead_class **cc,
		const void *tag, size_t len);
};

typedef struct {
	const br_aead_class *vtable;
	const br_block_ctr_class **bctx;
	br_ghash gh;
	unsigned char h[16];
	unsigned char j0_1[12];
	unsigned char buf[16];
	unsigned char y[16];
	uint32_t j0_2, jc;
	uint64_t count_aad, count_ctr;
} br_gcm_context;

void br_gcm_init(br_gcm_context *ctx,
	const br_block_ctr_class **bctx, br_ghash gh);
void br_gcm_reset(br_gcm_context *ctx, const void *iv, size_t len);
void br_gcm_aad_inject(br_gcm_context *ctx, const void *data, size_t len);
void br_gcm_flip(br_gcm_context *ctx);
void br_gcm_run(br_gcm_context *ctx, int encrypt, void *data, size_t len);
void br_gcm_get_tag(br_gcm_context *ctx, void *tag);
uint32_t br_gcm_check_tag(br_gcm_context *ctx, const void *tag);
void br_gcm_get_tag_trunc(br_gcm_context *ctx, void *tag, size_t len);
uint32_t br_gcm_check_tag_trunc(br_gcm_context *ctx,
	const void *tag, size_t len);

extern const br_aead_class br_gcm_vtable;

/* ==================================================================== */
/* From src/inner.h (encoding/decoding, portable branch only).          */

static inline void
br_enc32le(void *dst, uint32_t x)
{
	unsigned char *buf;

	buf = dst;
	buf[0] = (unsigned char)x;
	buf[1] = (unsigned char)(x >> 8);
	buf[2] = (unsigned char)(x >> 16);
	buf[3] = (unsigned char)(x >> 24);
}

static inline void
br_enc32be(void *dst, uint32_t x)
{
	unsigned char *buf;

	buf = dst;
	buf[0] = (unsigned char)(x >> 24);
	buf[1] = (unsigned char)(x >> 16);
	buf[2] = (unsigned char)(x >> 8);
	buf[3] = (unsigned char)x;
}

static inline uint32_t
br_dec32le(const void *src)
{
	const unsigned char *buf;

	buf = src;
	return (uint32_t)buf[0]
		| ((uint32_t)buf[1] << 8)
		| ((uint32_t)buf[2] << 16)
		| ((uint32_t)buf[3] << 24);
}

static inline uint32_t
br_dec32be(const void *src)
{
	const unsigned char *buf;

	buf = src;
	return ((uint32_t)buf[0] << 24)
		| ((uint32_t)buf[1] << 16)
		| ((uint32_t)buf[2] << 8)
		| (uint32_t)buf[3];
}

static inline void
br_enc64be(void *dst, uint64_t x)
{
	unsigned char *buf;

	buf = dst;
	br_enc32be(buf, (uint32_t)(x >> 32));
	br_enc32be(buf + 4, (uint32_t)x);
}

static inline uint64_t
br_dec64be(const void *src)
{
	const unsigned char *buf;

	buf = src;
	return ((uint64_t)br_dec32be(buf) << 32)
		| (uint64_t)br_dec32be(buf + 4);
}

void br_range_dec32le(uint32_t *v, size_t num, const void *src);
void br_range_enc32le(void *dst, const uint32_t *v, size_t num);

static inline uint32_t
br_swap32(uint32_t x)
{
	x = ((x & (uint32_t)0x00FF00FF) << 8)
		| ((x >> 8) & (uint32_t)0x00FF00FF);
	return (x << 16) | (x >> 16);
}

/* ==================================================================== */
/* From src/inner.h (constant-time primitive).                           */

/*
 * Returns 1 if x == 0, 0 otherwise. Take care that the operand is signed.
 */
static inline uint32_t
EQ0(int32_t x)
{
	uint32_t q;

	q = (uint32_t)x;
	return ~(q | -q) >> 31;
}

/* ==================================================================== */
/* From src/inner.h (AES support functions, ct64 implementation).       */

void br_aes_ct64_ortho(uint64_t *q);
void br_aes_ct64_interleave_in(uint64_t *q0, uint64_t *q1, const uint32_t *w);
void br_aes_ct64_interleave_out(uint32_t *w, uint64_t q0, uint64_t q1);
void br_aes_ct64_bitslice_Sbox(uint64_t *q);
void br_aes_ct64_bitslice_encrypt(unsigned num_rounds,
	const uint64_t *skey, uint64_t *q);
unsigned br_aes_ct64_keysched(uint64_t *comp_skey,
	const void *key, size_t key_len);
void br_aes_ct64_skey_expand(uint64_t *skey,
	unsigned num_rounds, const uint64_t *comp_skey);

#endif
