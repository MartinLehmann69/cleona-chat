/* voice_apm_shim.cpp — implementation of voice_apm_shim.h against
 * webrtc-audio-processing 1.3 (AEC3, builder/config API).
 *
 * See voice_apm_shim.h for why this file exists, why it is its own shared
 * library, and what the readbacks mean.
 */

#include "voice_apm_shim.h"

#include <new>

#include "api/scoped_refptr.h"
#include "modules/audio_processing/include/audio_processing.h"

using webrtc::AudioProcessing;
using webrtc::AudioProcessingBuilder;
using webrtc::StreamConfig;

/* The int16 interface requires one of these "native" rates (comment on
 * AudioProcessing::Initialize(const ProcessingConfig&) in 1.3: "only
 * NativeRate s be used"). Anything else is rejected at create time rather
 * than silently rounded. */
static bool is_native_rate(int32_t rate) {
    return rate == 8000 || rate == 16000 || rate == 32000 || rate == 48000;
}

struct cleona_voice_apm {
    /* AudioProcessingBuilder::Create() returns a new
     * rtc::RefCountedObject<AudioProcessingImpl> (audio_processing_builder_impl.cc);
     * the scoped_refptr holds the one reference and releases it in destroy(). */
    rtc::scoped_refptr<AudioProcessing> apm;
    StreamConfig stream;   /* mono at the session rate, both directions */
    int32_t samples_per_10ms;
};

extern "C" cleona_voice_apm_t* cleona_voice_apm_create(int32_t sample_rate_hz) {
    if (!is_native_rate(sample_rate_hz)) return nullptr;

    cleona_voice_apm_t* wrapper = new (std::nothrow) cleona_voice_apm_t();
    if (!wrapper) return nullptr;

    wrapper->apm = AudioProcessingBuilder().Create();
    if (!wrapper->apm) {
        delete wrapper;
        return nullptr;
    }

    /* The configuration of PipeWire's echo-cancel plugin for the same
     * library, with the arguments the preferred chain passes it
     * (cleona_voice_linux.c cvl_build_module_args: noise_suppression,
     * gain_control and high_pass_filter true; transient_suppression left at
     * the plugin default true) — spa/plugins/aec/aec-webrtc.cpp, PipeWire
     * 1.0.5, `#else` (webrtc 1.x) branch of webrtc_init2(). voice_detection
     * is left off: it only reports, it does not change the audio. */
    AudioProcessing::Config config;
    config.echo_canceller.enabled = true;
    config.echo_canceller.mobile_mode = false;
    config.gain_controller1.enabled = true;
    config.gain_controller1.mode = AudioProcessing::Config::GainController1::kAdaptiveDigital;
    config.gain_controller1.analog_level_minimum = 0;
    config.gain_controller1.analog_level_maximum = 255;
    config.gain_controller2.enabled = true;
    config.high_pass_filter.enabled = true;
    config.noise_suppression.enabled = true;
    config.noise_suppression.level = AudioProcessing::Config::NoiseSuppression::kHigh;
    config.transient_suppression.enabled = true;
    wrapper->apm->ApplyConfig(config);

    wrapper->stream = StreamConfig(sample_rate_hz, /*num_channels=*/1);
    webrtc::ProcessingConfig processing = {{
        wrapper->stream,   /* capture input */
        wrapper->stream,   /* capture output */
        wrapper->stream,   /* render input */
        wrapper->stream,   /* render output */
    }};
    if (wrapper->apm->Initialize(processing) != AudioProcessing::kNoError) {
        delete wrapper;   /* the scoped_refptr releases the APM */
        return nullptr;
    }

    wrapper->samples_per_10ms = sample_rate_hz / 100;
    return wrapper;
}

extern "C" void cleona_voice_apm_destroy(cleona_voice_apm_t* apm) {
    delete apm;   /* releases the APM reference */
}

extern "C" int32_t cleona_voice_apm_process_capture(cleona_voice_apm_t* apm,
                                                     int16_t* inout,
                                                     int32_t samples) {
    if (!apm || !inout) return -1;
    if (samples != apm->samples_per_10ms) return -1;

    /* src and dest may be the same memory (audio_processing.h of 1.3,
     * ProcessStream int16: "|src| and |dest| may use the same memory").
     * AudioProcessing::Error is already <= 0 (kNoError = 0). */
    return (int32_t)apm->apm->ProcessStream(inout, apm->stream, apm->stream, inout);
}

extern "C" int32_t cleona_voice_apm_process_render(cleona_voice_apm_t* apm,
                                                    const int16_t* in,
                                                    int32_t samples) {
    if (!apm || !in) return -1;
    if (samples != apm->samples_per_10ms) return -1;

    /* ProcessReverseStream writes a processed render frame to `dest`; the
     * caller's frame is the reference only and must stay untouched, so the
     * output goes to a scratch buffer (at most 480 samples: 48 kHz / 100). */
    int16_t scratch[480];
    return (int32_t)apm->apm->ProcessReverseStream(in, apm->stream, apm->stream, scratch);
}

extern "C" int32_t cleona_voice_apm_aec_enabled(const cleona_voice_apm_t* apm) {
    if (!apm) return 0;
    const AudioProcessing::Config c = apm->apm->GetConfig();
    return (c.echo_canceller.enabled && !c.echo_canceller.mobile_mode) ? 1 : 0;
}

extern "C" int32_t cleona_voice_apm_ns_enabled(const cleona_voice_apm_t* apm) {
    if (!apm) return 0;
    return apm->apm->GetConfig().noise_suppression.enabled ? 1 : 0;
}

extern "C" int32_t cleona_voice_apm_agc_enabled(const cleona_voice_apm_t* apm) {
    if (!apm) return 0;
    const AudioProcessing::Config c = apm->apm->GetConfig();
    return (c.gain_controller1.enabled || c.gain_controller2.enabled) ? 1 : 0;
}
