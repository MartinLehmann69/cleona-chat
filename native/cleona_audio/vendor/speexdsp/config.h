/* Static config for vendored speexdsp 1.2.1 build under cleona_audio.
 * Replaces autoconf-generated config.h. Tuned for Cleona's call audio:
 *   - 16 kHz mono PCM (320 samples / 20 ms frames)
 *   - Floating-point math (modern CPUs all have FPU; AEC quality > fixed-point)
 *   - KISS FFT (vendored, no external FFT dependency)
 *   - No SIMD (portable; 16 kHz mono load is trivial)
 */

#ifndef CLEONA_SPEEXDSP_CONFIG_H
#define CLEONA_SPEEXDSP_CONFIG_H

/* Build flavor */
#define FLOATING_POINT 1
#define USE_KISS_FFT 1

/* speexdsp is static-linked into libcleona_audio, so the public-API tag on
 * its functions doesn't need to actually export anything from the resulting
 * shared object — the cleona_audio_* surface is the only public API.
 * Define EXPORT cross-platform so MSVC stops choking on GCC's
 * __attribute__((visibility(...))) syntax. */
#if defined(_MSC_VER)
#  define EXPORT
#elif defined(__GNUC__) || defined(__clang__)
#  define EXPORT __attribute__((visibility("default")))
#else
#  define EXPORT
#endif

/* Sources test C99 VLAs via VAR_ARRAYS. Modern compilers all support these. */
#if !defined(_MSC_VER)
#  define VAR_ARRAYS 1
#endif

/* Math libs available */
#define HAVE_STDINT_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_INTTYPES_H 1

/* Don't enable SIMD here - sources have runtime fallbacks. Building portably keeps
 * cross-compile simple and 16 kHz mono mdf+preprocess fits easily inside one core's
 * budget without SSE/NEON. If we ever need it, add per-arch defines in the
 * CMakeLists.txt and gate them on CMAKE_SYSTEM_PROCESSOR. */

#endif /* CLEONA_SPEEXDSP_CONFIG_H */
