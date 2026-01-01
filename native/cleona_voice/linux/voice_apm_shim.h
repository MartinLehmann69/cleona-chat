/* voice_apm_shim.h — narrow C boundary around webrtc::AudioProcessing (APM).
 *
 * Work package: docs/SPEC_VOICE_VIDEO_REWORK.md V1.1 (Linux voice backend).
 * Architecture: Cleona_Chat_Architecture_v3_0.md §10.4.
 *
 * WHY THIS EXISTS
 * ----------------
 * `cleona_voice_linux.c` is C11, matching every other cleona_voice backend and
 * the mock. WebRTC's AudioProcessing (the library architecture §10.4 names as
 * the Linux fallback when the PipeWire echo-cancel filter is unavailable) is a
 * C++ virtual-interface API — there is no C entry point. This file is the one
 * place that boundary is crossed, so the rest of the Linux backend never
 * includes a C++ header.
 *
 * WHICH LIBRARY, AND THE VERSION WARNING THAT MUST SURVIVE INTO THE BUILD
 * -------------------------------------------------------------------------
 * `pkg-config webrtc-audio-processing` on this development machine (Ubuntu
 * 24.04) resolves to version 0.3.1 — a pre-AEC3 codebase (the legacy
 * `EchoCancellation`/`NoiseSuppression`/`GainControl` component API this shim
 * binds against). Architecture §10.4 names AEC3 as what the PipeWire filter
 * uses internally; measured on this machine (`ldd` on
 * `/usr/lib/x86_64-linux-gnu/spa-0.2/aec/libspa-aec-webrtc.so`), the PipeWire
 * filter itself links the SAME 0.3.1 library — so on THIS distribution the
 * "preferred" and "fallback" paths are not as far apart in quality as §10.4's
 * prose implies, and neither is AEC3. A newer distribution that ships
 * `webrtc-audio-processing-1` (the modern, AEC3-based rewrite with a
 * completely different C++ API — builder/config pattern, no
 * `EchoCancellation`/`NoiseSuppression` component objects) needs a second shim,
 * not a recompile of this one; see the CMakeLists.txt comment next to the
 * pkg-config lookup.
 *
 * WHAT "ENABLED" MEANS HERE, AND WHY IT DIFFERS FROM THE PIPEWIRE-FILTER PATH
 * -----------------------------------------------------------------------------
 * Every `cleona_voice_apm_*_enabled()` getter below calls the APM object's own
 * `is_enabled()` — a genuine readback of what the library reports about
 * itself, never a restatement of what was requested (I11: "what was READ BACK
 * from the platform, not what was asked for"). This is the one place in the
 * Linux backend where that readback is actually possible: the PipeWire filter
 * path has no client-visible introspection API for its internal AEC engine at
 * all (verified empirically — see cleona_voice_linux.c's file doc), so that
 * path reports FX_UNKNOWN throughout. This shim's readback is what lets the
 * LINKED_APM chain report FX_ENABLED with real evidence instead.
 */

#ifndef CLEONA_VOICE_LINUX_APM_SHIM_H
#define CLEONA_VOICE_LINUX_APM_SHIM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct cleona_voice_apm cleona_voice_apm_t;

/* Creates and configures one APM instance for a mono stream at `sample_rate_hz`
 * (must be one of the rates the legacy AudioFrame path accepts: 8000, 16000,
 * 32000, 48000 — anything else fails). Enables echo cancellation (non-mobile;
 * this is a desktop backend, not a phone modem path), noise suppression
 * (moderate), the high-pass filter, and gain control (adaptive digital — no
 * analog level coupling exists to a PipeWire capture stream). Returns NULL on
 * any failure; nothing partially configured survives a failed create. */
cleona_voice_apm_t* cleona_voice_apm_create(int32_t sample_rate_hz);

void cleona_voice_apm_destroy(cleona_voice_apm_t* apm);

/* Processes exactly one 10 ms mono S16 near-end (capture/microphone) frame IN
 * PLACE. `samples` MUST equal sample_rate_hz / 100; anything else is rejected
 * rather than reinterpreted. Call cleona_voice_apm_process_render() for the
 * matching far-end frame BEFORE this, when one exists, so the echo reference
 * is available to the cancellor for the frame it corresponds to.
 * Returns 0 on success, negative on failure (webrtc::AudioProcessing::Error,
 * negated so the caller's usual "< 0 is failure" convention holds). */
int32_t cleona_voice_apm_process_capture(cleona_voice_apm_t* apm,
                                         int16_t* inout, int32_t samples);

/* Feeds one 10 ms mono S16 far-end (render/reference) frame — the audio that
 * is being, or is about to be, played out — into the reverse stream. `samples`
 * MUST equal sample_rate_hz / 100. Never mutates `in`.
 * Returns 0 on success, negative on failure. */
int32_t cleona_voice_apm_process_render(cleona_voice_apm_t* apm,
                                        const int16_t* in, int32_t samples);

/* Genuine readbacks (I11) — 1 if the component's own is_enabled() says so, 0
 * otherwise. Never guessed from the Enable() call succeeding. */
int32_t cleona_voice_apm_aec_enabled(const cleona_voice_apm_t* apm);
int32_t cleona_voice_apm_ns_enabled(const cleona_voice_apm_t* apm);
int32_t cleona_voice_apm_agc_enabled(const cleona_voice_apm_t* apm);

#ifdef __cplusplus
}
#endif

#endif /* CLEONA_VOICE_LINUX_APM_SHIM_H */
