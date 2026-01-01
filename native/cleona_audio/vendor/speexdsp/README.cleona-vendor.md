# Vendored speexdsp 1.2.1

Local copy of speexdsp used by cleona_audio for echo cancellation (mdf.c) and
noise suppression / AGC (preprocess.c). Linked statically into
libcleona_audio.so so the shim has no external runtime dependency on a system
libspeexdsp.

## Provenance

- Upstream: https://github.com/xiph/speexdsp (tag `SpeexDSP-1.2.1`)
- Tarball: `https://github.com/xiph/speexdsp/archive/refs/tags/SpeexDSP-1.2.1.tar.gz`
- SHA256: `d17ca363654556a4ff1d02cc13d9eb1fc5a8642c90b40bd54ce266c3807b91a7`
- License: BSD-style (see `COPYING`)

## What's in this directory

- `include/speex/*.h` — public headers (verbatim from upstream)
- `include/speex/speexdsp_config_types.h` — written by us, replaces the
  autoconf-generated `.h.in` template. Maps `spx_intN_t` to `<stdint.h>` types.
- `libspeexdsp/*.c, *.h` — sources we actually compile. Subset of upstream:
  - mdf.c, preprocess.c — features Cleona uses
  - fftwrap.c, filterbank.c, resample.c, buffer.c, scal.c, jitter.c — used by
    the above (Makefile.am bundles all of these as one library)
  - kiss_fft.c, kiss_fftr.c, smallft.c — FFT backends
  - Headers: arch.h, fftwrap.h, filterbank.h, fixed_generic.h, fixed_debug.h,
    kiss_fft.h, _kiss_fft_guts.h, kiss_fftr.h, math_approx.h, os_support.h,
    pseudofloat.h, resample_neon.h, resample_sse.h, smallft.h, vorbis_psy.h
- `config.h` — written by us. Replaces autoconf-generated config.h. Selects
  floating-point math, KISS FFT, no SIMD. Sources include it via the
  `HAVE_CONFIG_H=1` define set in `CMakeLists.txt`.
- `CMakeLists.txt` — written by us. Builds `libspeexdsp` as a STATIC library
  with PIC enabled.

## What's NOT here (and why)

- `configure.ac`, `Makefile.am`, autotools machinery — replaced by CMake
- `doc/`, `html/`, `regression-fixes/`, `regressions/` — not used at runtime
- `testdenoise.c`, `testecho.c`, `testjitter.c`, `testresample{,2}.c` —
  upstream test programs, not needed (we have our own loopback test)
- `arm/`, `bfin.h`, `fixed_arm4.h`, `fixed_arm5e.h`, `fixed_bfin.h`,
  `misc_bfin.h`, `tmv/`, `ti/`, `symbian/`, `macosx/`, `win32/` — platform
  variants we don't target. We use the portable C path with floating-point.

## Updating

1. Download new tarball, verify SHA256 against an upstream source.
2. Replace files in `libspeexdsp/` and `include/speex/` (skip
   `speexdsp_config_types.h` — that's our static replacement).
3. Re-check `CMakeLists.txt`'s source list against `libspeexdsp/Makefile.am`.
4. Update the SHA256 in this README and in the upstream block of
   `CMakeLists.txt`.
5. `dart analyze` is not affected. Smoke build cleona_audio:
   `cd native/cleona_audio/build && cmake -GNinja .. && ninja`
