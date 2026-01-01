/* voice_apm_shim.cpp — implementation of voice_apm_shim.h.
 *
 * See voice_apm_shim.h for why this file exists and which library version it
 * binds (webrtc-audio-processing 0.3.1, the legacy AudioFrame/component API).
 */

#include "voice_apm_shim.h"

#include <cstring>

#include "webrtc/modules/audio_processing/include/audio_processing.h"
#include "webrtc/modules/interface/module_common_types.h"

using webrtc::AudioFrame;
using webrtc::AudioProcessing;

/* The legacy int16 path requires one of these "native" rates (comment on
 * AudioProcessing::Initialize(): "only NativeRates be used"). Anything else is
 * rejected at create time rather than silently rounded. */
static bool is_native_rate(int32_t rate) {
    return rate == 8000 || rate == 16000 || rate == 32000 || rate == 48000;
}

struct cleona_voice_apm {
    AudioProcessing* apm;
    int32_t sample_rate_hz;
    int32_t samples_per_10ms;
};

extern "C" cleona_voice_apm_t* cleona_voice_apm_create(int32_t sample_rate_hz) {
    if (!is_native_rate(sample_rate_hz)) return nullptr;

    AudioProcessing* apm = AudioProcessing::Create();
    if (!apm) return nullptr;

    /* Desktop, not a mobile modem path: EchoCancellation (not
     * EchoControlMobile). Moderate NS keeps the trade against speech
     * distortion the API itself documents; AGC in kAdaptiveDigital because
     * there is no analog level control on a PipeWire capture stream to couple
     * kAdaptiveAnalog to. Every Enable() call's return is checked — a failure
     * here means the corresponding cleona_voice_apm_*_enabled() readback will
     * honestly report 0, which is the point of doing the readback at all
     * instead of trusting the request. */
    apm->echo_cancellation()->set_suppression_level(
        webrtc::EchoCancellation::kHighSuppression);
    apm->echo_cancellation()->Enable(true);

    apm->noise_suppression()->set_level(webrtc::NoiseSuppression::kModerate);
    apm->noise_suppression()->Enable(true);

    apm->high_pass_filter()->Enable(true);

    apm->gain_control()->set_mode(webrtc::GainControl::kAdaptiveDigital);
    apm->gain_control()->Enable(true);

    cleona_voice_apm_t* wrapper = new (std::nothrow) cleona_voice_apm_t();
    if (!wrapper) {
        delete apm;
        return nullptr;
    }
    wrapper->apm = apm;
    wrapper->sample_rate_hz = sample_rate_hz;
    wrapper->samples_per_10ms = sample_rate_hz / 100;
    return wrapper;
}

extern "C" void cleona_voice_apm_destroy(cleona_voice_apm_t* apm) {
    if (!apm) return;
    delete apm->apm;
    delete apm;
}

/* Fills an AudioFrame from a mono S16 buffer of exactly `samples` samples at
 * the session's negotiated rate. Shared by the capture and render paths so
 * the two can never silently disagree on layout. */
static void fill_frame(AudioFrame* frame, const int16_t* pcm, int32_t samples,
                       int32_t rate) {
    frame->UpdateFrame(/*id=*/0, /*timestamp=*/0, pcm,
                       (size_t)samples, rate,
                       AudioFrame::kNormalSpeech, AudioFrame::kVadUnknown,
                       /*num_channels=*/1);
}

extern "C" int32_t cleona_voice_apm_process_capture(cleona_voice_apm_t* apm,
                                                     int16_t* inout,
                                                     int32_t samples) {
    if (!apm || !inout) return -1;
    if (samples != apm->samples_per_10ms) return -1;

    AudioFrame frame;
    fill_frame(&frame, inout, samples, apm->sample_rate_hz);

    /* AudioProcessing::Error is already <= 0 (kNoError = 0, every failure and
     * warning strictly negative), matching this shim's "negative on failure"
     * contract with no translation needed. */
    int32_t rc = (int32_t)apm->apm->ProcessStream(&frame);
    if (rc != AudioProcessing::kNoError) return rc;

    std::memcpy(inout, frame.data_, (size_t)samples * sizeof(int16_t));
    return 0;
}

extern "C" int32_t cleona_voice_apm_process_render(cleona_voice_apm_t* apm,
                                                    const int16_t* in,
                                                    int32_t samples) {
    if (!apm || !in) return -1;
    if (samples != apm->samples_per_10ms) return -1;

    AudioFrame frame;
    /* AnalyzeReverseStream()/ProcessReverseStream() take a non-const AudioFrame
     * pointer even though the input samples are only read for the (deprecated,
     * unused here) intelligibility path; the buffer we copy in belongs to this
     * stack frame, so mutation would be harmless even if it happened. */
    fill_frame(&frame, in, samples, apm->sample_rate_hz);

    int32_t rc = (int32_t)apm->apm->ProcessReverseStream(&frame);
    return rc;   /* already <= 0; 0 is kNoError */
}

extern "C" int32_t cleona_voice_apm_aec_enabled(const cleona_voice_apm_t* apm) {
    if (!apm) return 0;
    return apm->apm->echo_cancellation()->is_enabled() ? 1 : 0;
}

extern "C" int32_t cleona_voice_apm_ns_enabled(const cleona_voice_apm_t* apm) {
    if (!apm) return 0;
    return apm->apm->noise_suppression()->is_enabled() ? 1 : 0;
}

extern "C" int32_t cleona_voice_apm_agc_enabled(const cleona_voice_apm_t* apm) {
    if (!apm) return 0;
    return apm->apm->gain_control()->is_enabled() ? 1 : 0;
}
