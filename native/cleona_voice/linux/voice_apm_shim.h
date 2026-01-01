/* voice_apm_shim.h — narrow C boundary around webrtc::AudioProcessing (APM).
 *
 * Work package: docs/SPEC_VOICE_VIDEO_REWORK.md V1.1 (Linux voice backend);
 * ported to webrtc-audio-processing 1.x in S410 (S410-VOICE-BAU.md).
 * Architecture: Cleona_Chat_Architecture_v4_2.md §17.5 ("Linux via PipeWire
 * duplex with the echo-cancel module, or failing that, a directly linked
 * WebRTC APM").
 *
 * WHY THIS EXISTS
 * ----------------
 * `cleona_voice_linux.c` is C11, matching every other cleona_voice backend and
 * the mock. WebRTC's AudioProcessing is a C++ virtual-interface API — there is
 * no C entry point. This file is the one place that boundary is crossed, so
 * the rest of the Linux backend never includes a C++ header.
 *
 * WHICH LIBRARY (S410, owner decision B 29.10.2026)
 * --------------------------------------------------
 * webrtc-audio-processing 1.3 — the AEC3-based rewrite (builder/config API,
 * EchoCanceller3), built from the pinned source by linux/webrtc_apm and linked
 * STATICALLY into its own shared object, libcleona_voice_apm.so. Until S410
 * this shim bound the system's 0.3.1 (the legacy EchoCancellation/
 * NoiseSuppression/GainControl component API) and was linked into
 * libcleona_voice.so itself; Ubuntu 26.04 no longer ships 0.3.x, so the whole
 * voice library — the preferred PipeWire chain included — failed to load
 * there (S410-I6-MESSUNG.md finding 2).
 *
 * WHY A SEPARATE LIBRARY, OPENED ONLY ON DEMAND
 * ----------------------------------------------
 * §17.5 makes the linked APM the fallback: "or failing that". The preferred
 * chain (the PipeWire echo-cancel module with its own AEC plugin) needs
 * nothing from here. libcleona_voice.so therefore does not link this library;
 * it dlopen()s libcleona_voice_apm.so from its own directory at the moment it
 * falls back (cleona_voice_linux.c, cvl_apm_load()). A missing or broken
 * fallback library can then fail only the fallback, never the preferred chain.
 *
 * The functions below are the library's whole export surface
 * (CLEONA_VOICE_APM_API; everything else, including every webrtc and abseil
 * symbol, is hidden — CMakeLists.txt of this directory). The loader
 * resolves exactly these names with dlsym(); the typedefs at the bottom are
 * the one shared definition of their signatures.
 *
 * WHAT "ENABLED" MEANS HERE
 * --------------------------
 * The `cleona_voice_apm_*_enabled()` getters read the APM object's own
 * configuration back with GetConfig() AFTER ApplyConfig() — what the library
 * holds, which is not always what was requested: ApplyConfig() reverts an
 * invalid gain_controller2 block to its defaults (enabled = false)
 * (audio_processing_impl.cc of 1.3, ApplyConfig: "Reverting to default
 * parameter set"). For AEC, `echo_canceller.enabled && !mobile_mode` is
 * exactly the condition under which the library instantiates EchoCanceller3
 * (audio_processing_impl.cc, InitializeEchoController). This is the same
 * strength of evidence the 0.3.x getters gave (their is_enabled() returned
 * the component's stored flag) — a readback, never a restatement of the
 * request (I11). Before the first processed frame no other self-report
 * exists: AudioProcessingStats (echo_return_loss_enhancement, …) are filled
 * only while frames are processed (ApmStatsReporter).
 */

#ifndef CLEONA_VOICE_LINUX_APM_SHIM_H
#define CLEONA_VOICE_LINUX_APM_SHIM_H

#include <stdint.h>

#if defined(__GNUC__)
#define CLEONA_VOICE_APM_API __attribute__((visibility("default")))
#else
#define CLEONA_VOICE_APM_API
#endif

/* The file the loader opens, next to libcleona_voice.so. */
#define CLEONA_VOICE_APM_LIBRARY "libcleona_voice_apm.so"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct cleona_voice_apm cleona_voice_apm_t;

/* Creates and configures one APM instance for a mono stream at `sample_rate_hz`
 * (must be one of the rates the int16 interface accepts: 8000, 16000, 32000,
 * 48000 — "only NativeRates be used", audio_processing.h of 1.3; anything else
 * fails). The configuration is the one PipeWire's own echo-cancel plugin
 * applies to the same library for the preferred chain with the arguments
 * cleona_voice_linux.c passes it (spa/plugins/aec/aec-webrtc.cpp, PipeWire
 * 1.0.5, webrtc 1.x branch): AEC3 (desktop, not mobile), noise suppression
 * kHigh, high-pass filter, transient suppression, gain control 1 in
 * kAdaptiveDigital (no analog level coupling exists to a PipeWire capture
 * stream) plus gain control 2. The fallback thereby processes like the
 * preferred chain instead of by a second, different recipe.
 * Returns NULL on any failure; nothing partially configured survives a failed
 * create. */
CLEONA_VOICE_APM_API cleona_voice_apm_t* cleona_voice_apm_create(int32_t sample_rate_hz);

CLEONA_VOICE_APM_API void cleona_voice_apm_destroy(cleona_voice_apm_t* apm);

/* Processes exactly one 10 ms mono S16 near-end (capture/microphone) frame IN
 * PLACE. `samples` MUST equal sample_rate_hz / 100; anything else is rejected
 * rather than reinterpreted. Call cleona_voice_apm_process_render() for the
 * matching far-end frame BEFORE this, when one exists, so the echo reference
 * is available to the canceller for the frame it corresponds to.
 * Returns 0 on success, negative on failure (webrtc::AudioProcessing::Error,
 * already <= 0). */
CLEONA_VOICE_APM_API int32_t cleona_voice_apm_process_capture(cleona_voice_apm_t* apm,
                                                              int16_t* inout,
                                                              int32_t samples);

/* Feeds one 10 ms mono S16 far-end (render/reference) frame — the audio that
 * is being, or is about to be, played out — into the reverse stream. `samples`
 * MUST equal sample_rate_hz / 100. Never mutates `in`.
 * Returns 0 on success, negative on failure. */
CLEONA_VOICE_APM_API int32_t cleona_voice_apm_process_render(cleona_voice_apm_t* apm,
                                                             const int16_t* in,
                                                             int32_t samples);

/* Readbacks (see "WHAT ENABLED MEANS HERE") — 1 if the configuration the
 * library holds has the effect on, 0 otherwise. */
CLEONA_VOICE_APM_API int32_t cleona_voice_apm_aec_enabled(const cleona_voice_apm_t* apm);
CLEONA_VOICE_APM_API int32_t cleona_voice_apm_ns_enabled(const cleona_voice_apm_t* apm);
CLEONA_VOICE_APM_API int32_t cleona_voice_apm_agc_enabled(const cleona_voice_apm_t* apm);

/* Signatures as the loader resolves them with dlsym(). */
typedef cleona_voice_apm_t* (*cleona_voice_apm_create_fn)(int32_t);
typedef void (*cleona_voice_apm_destroy_fn)(cleona_voice_apm_t*);
typedef int32_t (*cleona_voice_apm_process_capture_fn)(cleona_voice_apm_t*, int16_t*, int32_t);
typedef int32_t (*cleona_voice_apm_process_render_fn)(cleona_voice_apm_t*, const int16_t*, int32_t);
typedef int32_t (*cleona_voice_apm_enabled_fn)(const cleona_voice_apm_t*);

#ifdef __cplusplus
}
#endif

#endif /* CLEONA_VOICE_LINUX_APM_SHIM_H */
