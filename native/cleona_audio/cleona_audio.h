#ifndef CLEONA_AUDIO_H
#define CLEONA_AUDIO_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
  #define CLEONA_AUDIO_API __declspec(dllexport)
#else
  #define CLEONA_AUDIO_API __attribute__((visibility("default")))
#endif

typedef struct cleona_audio_engine cleona_audio_engine_t;

// === Lifecycle ==============================================================

// Allocates ring buffers, initializes Speex AEC + NS state. Does NOT start audio devices.
// sample_rate: 16000  |  channels: 1 (mono)  |  frame_samples: 320 (20 ms @ 16 kHz). Max 480.
// ring_capacity_frames: 8 (≈ 160 ms buffer per direction)
CLEONA_AUDIO_API cleona_audio_engine_t* cleona_audio_create(
    int32_t sample_rate, int32_t channels,
    int32_t frame_samples, int32_t ring_capacity_frames);

// Open + start capture and playback devices via miniaudio.
// Returns 0 on success. Negative codes:
//   -1 = miniaudio context init failed
//   -2 = capture device open failed
//   -3 = playback device open failed
//   -4 = permission denied (Android)
//   -5 = already started
CLEONA_AUDIO_API int32_t cleona_audio_start(cleona_audio_engine_t* engine);

// Stop devices. Idempotent. Drains pending playback (max 100 ms timeout).
CLEONA_AUDIO_API void cleona_audio_stop(cleona_audio_engine_t* engine);

// Free. MUST call stop first.
CLEONA_AUDIO_API void cleona_audio_destroy(cleona_audio_engine_t* engine);

// === Capture (Dart Isolate consumes) ======================================

// Read exactly frame_samples PCM frames into out_pcm.
// Blocks up to timeout_ms on internal cond-var. AEC + NS already applied.
// Returns: 1 = got frame, 0 = timeout, -1 = stopped/error.
// out_pcm must have frame_samples * channels * sizeof(int16_t) bytes.
CLEONA_AUDIO_API int32_t cleona_audio_capture_read(
    cleona_audio_engine_t* engine,
    int16_t* out_pcm, int32_t timeout_ms);

// === Playback (Dart Main writes) ==========================================

// Push exactly frame_samples PCM frames to playback ring. Non-blocking.
// Returns: 1 = queued, 0 = ring full (frame dropped), -1 = stopped/error.
CLEONA_AUDIO_API int32_t cleona_audio_playback_write(
    cleona_audio_engine_t* engine,
    const int16_t* pcm, int32_t frame_samples);

// === Device Control ========================================================

CLEONA_AUDIO_API void cleona_audio_set_mute(cleona_audio_engine_t* engine, int32_t mute);

// Android only: route to speaker (1) vs earpiece/Bluetooth (0).
// Linux/Windows: no-op, returns 0.
CLEONA_AUDIO_API int32_t cleona_audio_set_speaker(cleona_audio_engine_t* engine, int32_t speaker_on);

// === DSP toggles (default: AEC on, NS on, AGC off) ========================

CLEONA_AUDIO_API void cleona_audio_set_aec(cleona_audio_engine_t* engine, int32_t enabled);
CLEONA_AUDIO_API void cleona_audio_set_ns (cleona_audio_engine_t* engine, int32_t enabled);
CLEONA_AUDIO_API void cleona_audio_set_agc(cleona_audio_engine_t* engine, int32_t enabled);

// === Diagnostics ===========================================================

typedef struct cleona_audio_stats {
    int64_t capture_frames_total;
    int64_t capture_frames_dropped;
    int64_t playback_frames_total;
    int64_t playback_frames_underrun;
    int32_t capture_backend;   // 1=alsa 2=pulse 3=wasapi 4=aaudio 5=opensl 6=coreaudio
    int32_t playback_backend;  // same enum
} cleona_audio_stats_t;

CLEONA_AUDIO_API void cleona_audio_get_stats(
    cleona_audio_engine_t* engine, cleona_audio_stats_t* out);

#ifdef __cplusplus
}
#endif

#endif // CLEONA_AUDIO_H
