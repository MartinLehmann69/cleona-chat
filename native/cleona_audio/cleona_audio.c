#include "cleona_audio.h"
#include "cleona_audio_ring.h"
#include "miniaudio.h"
#include <speex/speex_echo.h>
#include <speex/speex_preprocess.h>
#include <stdlib.h>
#include <string.h>
#include <stdatomic.h>

#define CLEONA_AUDIO_MAX_FRAME_SAMPLES 480   // covers up to 30ms @ 16kHz or 10ms @ 48kHz

struct cleona_audio_engine {
    int32_t sample_rate;
    int32_t channels;
    int32_t frame_samples;
    int32_t frame_bytes;       // frame_samples * channels * 2
    int32_t ring_capacity;

    ma_context context;
    ma_device  capture_dev;
    ma_device  playback_dev;
    int32_t    capture_started;
    int32_t    playback_started;
    int32_t    context_inited;     // 1 = ma_context_init succeeded, must uninit

    cleona_ring_t capture_ring;
    cleona_ring_t playback_ring;

    SpeexEchoState*       aec;
    SpeexPreprocessState* preproc;
    cleona_ring_t far_end_ring;     // playback writes, capture reads (1-frame cap, atomic via SPSC ring)
    int16_t* far_end_scratch;       // capture-thread-private scratch buffer for AEC

    _Atomic int32_t aec_enabled;  // 1 = on, 0 = off
    _Atomic int32_t ns_enabled;
    _Atomic int32_t agc_enabled;
    _Atomic int32_t muted;

    _Atomic int64_t playback_underruns;
};

CLEONA_AUDIO_API cleona_audio_engine_t* cleona_audio_create(
    int32_t sample_rate, int32_t channels,
    int32_t frame_samples, int32_t ring_capacity_frames) {

    if (sample_rate <= 0 || channels <= 0 || frame_samples <= 0 || ring_capacity_frames <= 0) return NULL;
    if (channels != 1) return NULL; // V1: mono only
    if (frame_samples > CLEONA_AUDIO_MAX_FRAME_SAMPLES) return NULL;

    cleona_audio_engine_t* e = (cleona_audio_engine_t*)calloc(1, sizeof(*e));
    if (!e) return NULL;

    e->sample_rate   = sample_rate;
    e->channels      = channels;
    e->frame_samples = frame_samples;
    e->frame_bytes   = frame_samples * channels * 2;
    e->ring_capacity = ring_capacity_frames;

    if (cleona_ring_init(&e->capture_ring,  ring_capacity_frames, e->frame_bytes) != 0) goto fail_capture_ring;
    if (cleona_ring_init(&e->playback_ring, ring_capacity_frames, e->frame_bytes) != 0) goto fail_playback_ring;
    if (cleona_ring_init(&e->far_end_ring, 1, e->frame_bytes) != 0) goto fail_far_end_ring;

    // Speex AEC: tail = 250ms @ sample_rate
    int32_t tail_samples = (sample_rate * 250) / 1000; // 4000 @ 16kHz
    e->aec = speex_echo_state_init(frame_samples, tail_samples);
    if (!e->aec) goto fail_aec;
    speex_echo_ctl(e->aec, SPEEX_ECHO_SET_SAMPLING_RATE, &sample_rate);

    e->preproc = speex_preprocess_state_init(frame_samples, sample_rate);
    if (!e->preproc) goto fail_preproc;

    int on = 1, off = 0;
    speex_preprocess_ctl(e->preproc, SPEEX_PREPROCESS_SET_DENOISE, &on);   // NS default on
    speex_preprocess_ctl(e->preproc, SPEEX_PREPROCESS_SET_AGC,     &off);  // AGC default off
    speex_preprocess_ctl(e->preproc, SPEEX_PREPROCESS_SET_ECHO_STATE, e->aec);

    e->far_end_scratch = (int16_t*)calloc((size_t)frame_samples, sizeof(int16_t));
    if (!e->far_end_scratch) goto fail_far_end_scratch;

    atomic_store(&e->aec_enabled, 1);
    atomic_store(&e->ns_enabled,  1);
    atomic_store(&e->agc_enabled, 0);
    atomic_store(&e->muted,       0);
    atomic_store(&e->playback_underruns, 0);

    return e;

fail_far_end_scratch:
    speex_preprocess_state_destroy(e->preproc);
fail_preproc:
    speex_echo_state_destroy(e->aec);
fail_aec:
    cleona_ring_destroy(&e->far_end_ring);
fail_far_end_ring:
    cleona_ring_destroy(&e->playback_ring);
fail_playback_ring:
    cleona_ring_destroy(&e->capture_ring);
fail_capture_ring:
    free(e);
    return NULL;
}

CLEONA_AUDIO_API void cleona_audio_destroy(cleona_audio_engine_t* e) {
    if (!e) return;
    // Defensive: ensure devices are stopped (caller MUST call stop first per
    // header contract, but FFI-bridge bugs should not become use-after-free).
    if (e->capture_started || e->playback_started || e->context_inited) {
        cleona_audio_stop(e);
    }
    free(e->far_end_scratch);
    if (e->preproc) speex_preprocess_state_destroy(e->preproc);
    if (e->aec)     speex_echo_state_destroy(e->aec);
    cleona_ring_destroy(&e->far_end_ring);
    cleona_ring_destroy(&e->capture_ring);
    cleona_ring_destroy(&e->playback_ring);
    free(e);
}

// === miniaudio Audio-Thread Callbacks =====================================

static void capture_callback(ma_device* dev, void* output_unused, const void* input, ma_uint32 frame_count) {
    (void)output_unused;
    cleona_audio_engine_t* e = (cleona_audio_engine_t*)dev->pUserData;
    if (!e) return;
    if ((int32_t)frame_count != e->frame_samples) return; // unexpected — drop
    if (atomic_load(&e->muted)) return;

    int16_t cleaned[CLEONA_AUDIO_MAX_FRAME_SAMPLES]; // sized to clamp; actual use = e->frame_samples
    const int16_t* src = (const int16_t*)input;

    if (atomic_load(&e->aec_enabled)) {
        // Try-read latest far-end frame; if empty (pure capture, no playback yet) use silence
        if (!cleona_ring_try_read(&e->far_end_ring, e->far_end_scratch)) {
            memset(e->far_end_scratch, 0, (size_t)e->frame_bytes);
        }
        speex_echo_cancellation(e->aec, src, e->far_end_scratch, cleaned);
        if (atomic_load(&e->ns_enabled)) {
            speex_preprocess_run(e->preproc, cleaned);
        }
        cleona_ring_try_write(&e->capture_ring, cleaned);
    } else {
        if (atomic_load(&e->ns_enabled)) {
            // copy then in-place NS (Speex preprocess takes int16_t*)
            memcpy(cleaned, src, (size_t)e->frame_bytes);
            speex_preprocess_run(e->preproc, cleaned);
            cleona_ring_try_write(&e->capture_ring, cleaned);
        } else {
            cleona_ring_try_write(&e->capture_ring, src);
        }
    }
}

static void playback_callback(ma_device* dev, void* output, const void* input_unused, ma_uint32 frame_count) {
    (void)input_unused;
    cleona_audio_engine_t* e = (cleona_audio_engine_t*)dev->pUserData;
    if (!e) { memset(output, 0, frame_count * 2); return; }
    if ((int32_t)frame_count != e->frame_samples) {
        memset(output, 0, (size_t)frame_count * 2);
        return;
    }

    int16_t buf[CLEONA_AUDIO_MAX_FRAME_SAMPLES];
    if (cleona_ring_try_read(&e->playback_ring, buf)) {
        memcpy(output, buf, (size_t)e->frame_bytes);
        cleona_ring_try_write(&e->far_end_ring, buf);  // atomic SPSC handoff to capture thread
    } else {
        memset(output, 0, (size_t)e->frame_bytes);
        static const int16_t zero_frame[CLEONA_AUDIO_MAX_FRAME_SAMPLES] = {0};
        cleona_ring_try_write(&e->far_end_ring, zero_frame);
        atomic_fetch_add(&e->playback_underruns, 1);
    }
}

// === Lifecycle: Start / Stop ===============================================

CLEONA_AUDIO_API int32_t cleona_audio_start(cleona_audio_engine_t* e) {
    if (!e) return -1;
    if (e->capture_started || e->playback_started) return -5;

    // Initialize miniaudio context (auto-pick first available backend)
    ma_context_config ctx_cfg = ma_context_config_init();
    if (ma_context_init(NULL, 0, &ctx_cfg, &e->context) != MA_SUCCESS) return -1;
    e->context_inited = 1;

    // Capture device
    ma_device_config cap_cfg = ma_device_config_init(ma_device_type_capture);
    cap_cfg.capture.format    = ma_format_s16;
    cap_cfg.capture.channels  = e->channels;
    cap_cfg.sampleRate        = e->sample_rate;
    cap_cfg.periodSizeInFrames = e->frame_samples;
    cap_cfg.dataCallback      = capture_callback;
    cap_cfg.pUserData         = e;
    if (ma_device_init(&e->context, &cap_cfg, &e->capture_dev) != MA_SUCCESS) {
        ma_context_uninit(&e->context); e->context_inited = 0; return -2;
    }

    // Playback device
    ma_device_config play_cfg = ma_device_config_init(ma_device_type_playback);
    play_cfg.playback.format    = ma_format_s16;
    play_cfg.playback.channels  = e->channels;
    play_cfg.sampleRate         = e->sample_rate;
    play_cfg.periodSizeInFrames = e->frame_samples;
    play_cfg.dataCallback       = playback_callback;
    play_cfg.pUserData          = e;
    if (ma_device_init(&e->context, &play_cfg, &e->playback_dev) != MA_SUCCESS) {
        ma_device_uninit(&e->capture_dev);
        ma_context_uninit(&e->context); e->context_inited = 0; return -3;
    }

    if (ma_device_start(&e->capture_dev)  != MA_SUCCESS) goto fail_start_capture;
    e->capture_started = 1;
    if (ma_device_start(&e->playback_dev) != MA_SUCCESS) goto fail_start_playback;
    e->playback_started = 1;

    return 0;

fail_start_playback:
    ma_device_stop(&e->capture_dev);
    ma_device_uninit(&e->playback_dev);
    ma_device_uninit(&e->capture_dev);
    ma_context_uninit(&e->context);
    e->context_inited = 0;
    e->capture_started = 0;
    return -3;
fail_start_capture:
    ma_device_uninit(&e->playback_dev);
    ma_device_uninit(&e->capture_dev);
    ma_context_uninit(&e->context);
    e->context_inited = 0;
    return -2;
}

CLEONA_AUDIO_API void cleona_audio_stop(cleona_audio_engine_t* e) {
    if (!e) return;
    if (e->capture_started)  { ma_device_stop(&e->capture_dev);  ma_device_uninit(&e->capture_dev);  e->capture_started  = 0; }
    if (e->playback_started) { ma_device_stop(&e->playback_dev); ma_device_uninit(&e->playback_dev); e->playback_started = 0; }
    cleona_ring_close(&e->capture_ring);
    cleona_ring_close(&e->playback_ring);
    if (e->context_inited) {
        ma_context_uninit(&e->context);
        e->context_inited = 0;
    }
}

// === Capture / Playback API ================================================

CLEONA_AUDIO_API int32_t cleona_audio_capture_read(cleona_audio_engine_t* e, int16_t* out_pcm, int32_t timeout_ms) {
    if (!e || !out_pcm) return -1;
    return cleona_ring_read(&e->capture_ring, out_pcm, timeout_ms);
}

CLEONA_AUDIO_API int32_t cleona_audio_playback_write(cleona_audio_engine_t* e, const int16_t* pcm, int32_t frame_samples) {
    if (!e || !pcm) return -1;
    if (frame_samples != e->frame_samples) return -1;
    return cleona_ring_try_write(&e->playback_ring, pcm);
}

// === Device Control ========================================================

CLEONA_AUDIO_API void cleona_audio_set_mute(cleona_audio_engine_t* e, int32_t mute) {
    if (!e) return;
    atomic_store(&e->muted, mute ? 1 : 0);
}

CLEONA_AUDIO_API int32_t cleona_audio_set_speaker(cleona_audio_engine_t* e, int32_t on) {
    (void)e; (void)on;
    // Android-specific routing — handled via Kotlin AudioManager; no-op here.
    return 0;
}

CLEONA_AUDIO_API void cleona_audio_set_aec(cleona_audio_engine_t* e, int32_t enabled) {
    if (!e) return; atomic_store(&e->aec_enabled, enabled ? 1 : 0);
}
CLEONA_AUDIO_API void cleona_audio_set_ns(cleona_audio_engine_t* e, int32_t enabled) {
    if (!e) return;
    atomic_store(&e->ns_enabled, enabled ? 1 : 0);
    int v = enabled ? 1 : 0;
    speex_preprocess_ctl(e->preproc, SPEEX_PREPROCESS_SET_DENOISE, &v);
}
CLEONA_AUDIO_API void cleona_audio_set_agc(cleona_audio_engine_t* e, int32_t enabled) {
    if (!e) return;
    atomic_store(&e->agc_enabled, enabled ? 1 : 0);
    int v = enabled ? 1 : 0;
    speex_preprocess_ctl(e->preproc, SPEEX_PREPROCESS_SET_AGC, &v);
}

// === Stats =================================================================

static int32_t backend_to_enum(ma_backend b) {
    switch (b) {
        case ma_backend_alsa:       return 1;
        case ma_backend_pulseaudio: return 2;
        case ma_backend_wasapi:     return 3;
        case ma_backend_aaudio:     return 4;
        case ma_backend_opensl:     return 5;
        case ma_backend_coreaudio:  return 6;
        default: return 0;
    }
}

CLEONA_AUDIO_API void cleona_audio_get_stats(cleona_audio_engine_t* e, cleona_audio_stats_t* out) {
    if (!e || !out) return;
    memset(out, 0, sizeof(*out));
    int32_t w = atomic_load(&e->capture_ring.write_idx);
    int32_t r = atomic_load(&e->capture_ring.read_idx);
    out->capture_frames_total   = w; // monotonic
    out->capture_frames_dropped = atomic_load(&e->capture_ring.frames_dropped);

    int32_t pw = atomic_load(&e->playback_ring.write_idx);
    int32_t pr = atomic_load(&e->playback_ring.read_idx);
    out->playback_frames_total    = pw;
    out->playback_frames_underrun = atomic_load(&e->playback_underruns);

    if (e->capture_started)  out->capture_backend  = backend_to_enum(e->context.backend);
    if (e->playback_started) out->playback_backend = backend_to_enum(e->context.backend);
    (void)r; (void)pr;
}
