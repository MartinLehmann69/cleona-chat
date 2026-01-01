BearSSL 0.6 -- AES-256-GCM subset vendored for Cleona
======================================================

Why: v4_2 §4.2, decision D-130 (owner, 20.11.2026, S430). On a processor where
libsodium's crypto_aead_aes256gcm_is_available() returns 0 (no AES-NI/PCLMUL/
AVX, or ARMv8 without crypto extensions), Cleona runs the same AES-256-GCM in
software in constant time through the two exports
cleona_link_aes256gcm_encrypt/decrypt of native/cleona_link/cleona_link.c.
These files are the implementation behind them.

Origin
------
Project:  BearSSL, Thomas Pornin, https://www.bearssl.org/
Release:  0.6 (file dates in the archive: 2018-08-14), the latest release
Archive:  https://www.bearssl.org/bearssl-0.6.tar.gz
          fetched 20.11.2026, 765094 bytes
          SHA-256 6705bba1714961b41a728dfc5debbe348d2966c117649392f8c8139efc83ff14
Licence:  MIT (LICENSE.txt, from the archive root)

Files taken (and nothing else)
------------------------------
Each file is the upstream file with one difference: trailing blanks at the
end of four lines of the licence header (lines 4, 12, 15, 17; LICENSE.txt
lines 3, 11, 14, 16) are removed, because the repository's write path does not
keep trailing whitespace. Code and every other byte are unchanged. Check:

  diff <(sed 's/[ \t]*$//' <archive>/<upstream path>) <file>   -> no output

file             upstream path              lines  SHA-256 upstream / SHA-256 here
aes_ct64.c       src/symcipher/aes_ct64.c     398  755144aacacfb0eb9434876661655d16b91caa4f54fa46351dc626a56d9048f1
                                                   95eaa07ea5108d2cede5c6ca6f41ec93b10c0c9f79a94d58a2a6a058fe349af5
aes_ct64_enc.c   src/symcipher/aes_ct64_enc.c 115  3e2b380ddbc0f5d9bd3f8622d552e052a6361948ecc4077486a17273fa0148c4
                                                   4ecded1d2ddb3a858ea694b0b5b9525f7eed70b85ef349c527a380a5c6e51673
aes_ct64_ctr.c   src/symcipher/aes_ct64_ctr.c 114  713a6e5afafa06f9bd608d5552abba5d38f5790a7d58f2c397c9257904a2943f
                                                   3ff79d9d324b4ebfd6b26f5c02147666a5aafcca74ffa286e8fbf614b915d548
ghash_ctmul64.c  src/hash/ghash_ctmul64.c     154  a5a5986e621de05735fdfd257fd39f313400ff53631d575232c230d3184bc4b9
                                                   0b867e439c95e87c586780d6263b3451328e1d27ca526b57cdb9dea263fb0efb
gcm.c            src/aead/gcm.c               318  1bea4df57ed57cdcd3dc2a44e7dbbe5866ccf045e0722fb68a2801dffa2f640f
                                                   1e7fec4eaeddac0c7c0df5f783f90f7cc1d81cf95040ef7a83e110ef786de2d4
dec32le.c        src/codec/dec32le.c           38  fb45ce9e370d72c495dfbb08267e2fd32dcf5215c28df5d2db24f842b2d2d43a
                                                   f375c22e85ff4dc35566b0c3daedac73a42ef6586d932db8254cf37c36eba287
enc32le.c        src/codec/enc32le.c           38  7faa71643fc74570fd4c550974a075ec05485a0b3805cbdc826d662cb347e79b
                                                   d14eb98434d34899c88b0be58596e6b61cdf19ad591d5cfdb73d7a86f5815c91
LICENSE.txt      LICENSE.txt                   21  771bf18c8633ea69ec9b07d2e604c4b99b7bef41b0f5ce6385d24df4448f61ca
                                                   6e191a41695072bf0a9f230aa67c233055b9f1d35321be8297804223b33fb7bf

inner.h is NOT an upstream file. It replaces upstream src/inner.h (2532 lines,
which includes config.h and all thirteen public headers) with exactly the
declarations these seven files need, copied from src/inner.h,
inc/bearssl_block.h, inc/bearssl_hash.h and inc/bearssl_aead.h; its header
comment names the one deliberate deviation (byte codec: portable branch only).

What the files do -- read in full before vendoring (S430)
--------------------------------------------------------
aes_ct64.c       bitsliced AES S-box (Boyar-Peralta circuit), orthogonalisation,
                 key schedule, subkey expansion; 64-bit words, no tables
aes_ct64_enc.c   AES rounds on bitsliced state (four blocks in parallel)
aes_ct64_ctr.c   AES-CTR over the above; vtable br_aes_ct64_ctr_vtable
ghash_ctmul64.c  GHASH with constant-time 64-bit carry-less multiplication
                 (integer multiplications with masked "holes")
gcm.c            GCM frame: H = E(0), J0 from a 12-byte nonce, AAD/CTR/GHASH,
                 tag; tag check in constant time (OR of byte differences, EQ0)
dec32le.c/enc32le.c  little-endian word array <-> bytes

None of them opens files, touches the network, draws randomness or allocates
memory: the only library calls are memcpy and memset; all state lives in the
caller's context structures and on the stack.

Checks
------
native/cleona_link/test/link_aes_gcm_smoke.c   NIST CAVP vectors (25, 96-bit IV,
                                               128-bit tag) + sabotage cases;
                                               saboteur build must fail
test/smoke/smoke_aes_gcm_software.dart         10 000 random sets, software ==
                                               libsodium byte for byte, both ways
