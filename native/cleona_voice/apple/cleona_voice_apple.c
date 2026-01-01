/* cleona_voice_apple.c — the Apple voice backend: one VoiceProcessingIO
 * AudioUnit behind the cleona_voice.h ABI, shared by iOS and macOS.
 *
 * Work package: docs/SPEC_VOICE_VIDEO_REWORK.md V1.3.
 * Architecture:  Cleona_Chat_Architecture_v3_0.md §10.4 (normative).
 * ABI:           ../cleona_voice.h (frozen — SPEC §4).
 *
 * ===========================================================================
 * WHY THIS FILE EXISTS AT ALL
 * ===========================================================================
 * §10.4, defect row 3: "Apple's voice processing was unreachable: miniaudio
 * uses RemoteIO / HALOutput, never kAudioUnitSubType_VoiceProcessingIO, and
 * never sets mode = voiceChat" (miniaudio.h:33263, :34948-34950; grep
 * VoiceProcessingIO = 0; grep setMode = 0). The Apple chain was not
 * misconfigured, it was never addressed. Four rounds of echo fixes (S252, S268,
 * S278, S281) could not converge because none of them could reach it.
 *
 * This file addresses it. The three things SPEC §7 V1.3 makes mandatory are all
 * in cva_open_unit() below and each is verified by reading the value BACK:
 *
 *   kAUVoiceIOProperty_BypassVoiceProcessing    = 0   (voice processing ON)
 *   kAUVoiceIOProperty_VoiceProcessingEnableAGC = 1   (AGC explicitly ON —
 *                                                      §10.4 defect row 6: AGC
 *                                                      was never switched on in
 *                                                      the superseded stack)
 *   AVAudioSession category playAndRecord + mode voiceChat  (iOS, in
 *                                                cleona_voice_apple_ios.m)
 *
 * ===========================================================================
 * HOW THE INVARIANTS ARE EARNED (SPEC §2)
 * ===========================================================================
 * I1  No DSP here. There is not one filter, gain stage or resampler in this
 *     file. AEC/NS/AGC are VPIO's; the only sample manipulation is memset() for
 *     mute, which is the ABI's definition of mute, not signal processing.
 *
 * I2  ONE AudioUnit carries both directions. `duplex` is reported as 1 because
 *     there is exactly one AudioComponentInstance in the struct — not because a
 *     constant says so. VPIO's whole reason to exist is that the reference
 *     signal and the microphone signal are inside the same unit; the capacity-1
 *     ring between two independent ma_device clocks (§10.4 defect row 1) has no
 *     counterpart here.
 *
 * I3  The rate comes from cva_platform_hardware_rate(). `rate_hint` is passed
 *     to the platform layer as a preference and then ignored in favour of what
 *     the hardware reports. See cva_choose_rate() for the ONE case where this
 *     file overrides the hardware value — a rate outside the ABI's own
 *     normative bounds — and why that is a report, not a guess.
 *
 * I4  The render callbacks deliver a VARYING number of frames (Apple documents
 *     inNumberFrames as variable, and on iOS it changes with the route and with
 *     the app's foreground state). cleona_voice_capture_read() therefore never
 *     touches the callback size: samples go into a ring, and a caller gets a
 *     frame only once frame_samples of them exist. Nothing is ever dropped for
 *     having the "wrong" size — that is §10.4 defect row 7 (cleona_audio.c:151,
 *     :202), and it is the single most important check in the conformance test
 *     (C3).
 *
 * I5  cleona_voice_playback_write() copies into a ring and returns. The output
 *     device's render callback is the only clock in the playback path. There is
 *     no timer anywhere in this file.
 *
 * I6  set_mic_muted() zeroes the frame on the way out of capture_read() — the
 *     unit keeps running, the ring keeps filling, the cadence is untouched.
 *     set_output_muted() still CONSUMES from the playback ring and renders
 *     zeros, so no backlog can build (§10.4: the superseded
 *     _drainJitterBuffer returned early and produced a burst on re-enable).
 *     Neither ever stops a stream.
 *
 *     Erratum E6a: both states are also REPORTED (cleona_voice_get_report,
 *     `mic_muted` / `output_muted`). That is not a formality. This backend's
 *     mute lives on the read side of the capture ring and on the render side of
 *     the playback callback, which is invisible from outside: with a quiet room
 *     and a silent playback ring, a working mute and a mute that does nothing
 *     produce byte-identical output. Until the state is reported, "sound off"
 *     is unverifiable in principle — exactly the class of unfalsifiable claim
 *     §10.4 replaced this stack to get rid of.
 *
 * I7  Policy lives in Dart (RoutePolicy, V1.5). This file only makes the route
 *     set observable and the switch executable, and reports a defined error
 *     code when a route is not available — which is exactly what
 *     ERR_ROUTE_UNAVAILABLE is for on macOS, where there is no earpiece.
 *
 * I11 Every effect state in the report is a value READ BACK from the AudioUnit,
 *     never the value we wrote. Where Apple exposes no property to read — noise
 *     suppression — the answer is FX_UNKNOWN ("not_determinable"), not
 *     FX_ENABLED. See cva_probe_effects() for the full reasoning; the short
 *     version is that VPIO's documentation is not an observation.
 *
 * ===========================================================================
 * DOCUMENTED REASONS FOR EVERY EFFECT THAT IS NOT `ENABLED` (SPEC §6)
 * ===========================================================================
 * SPEC §6: "acceptance of a backend means conformance green + report logged + a
 * documented reason for every effect that is not ENABLED". The conformance
 * harness prints note N2 naming them but cannot write the reason. Here it is:
 *
 *   NS — reported as CLEONA_VOICE_FX_UNKNOWN, always.
 *        VoiceProcessingIO exposes exactly two settable/readable voice
 *        properties: kAUVoiceIOProperty_BypassVoiceProcessing and
 *        kAUVoiceIOProperty_VoiceProcessingEnableAGC. There is no
 *        noise-suppression property, so there is nothing to read back. Apple
 *        documents the VPIO chain as including noise suppression, but
 *        documentation is not an observation, and I11 is explicit that the
 *        report carries "what was READ BACK from the platform, not what was
 *        asked for". Upgrading NS to ENABLED on the strength of the
 *        BypassVoiceProcessing readback would derive one claim from a different
 *        claim's evidence — the exact move cleona_voice.h calls "a gate derived
 *        from the same assumption as the thing it checks".
 *
 *   AEC — ENABLED whenever BypassVoiceProcessing reads back as 0. That IS a
 *        direct readback of the switch that governs it, so it is an
 *        observation. If the readback fails, AEC is reported UNKNOWN.
 *
 *   AGC — whatever kAUVoiceIOProperty_VoiceProcessingEnableAGC reads back:
 *        ENABLED for 1, AVAILABLE_OFF for 0 (the unit kept it off despite the
 *        explicit request), UNAVAILABLE when the unit does not implement the
 *        property, UNKNOWN when it exists but cannot be read.
 *
 * ===========================================================================
 * KNOWN PROPERTIES OF THIS BACKEND (stated, not hidden)
 * ===========================================================================
 *  - The render callbacks take a short pthread mutex (a memcpy and two index
 *    updates, no allocation, no syscall). Apple discourages locks on the render
 *    thread; the alternative — a lock-free ring plus a semaphore signalled from
 *    the render thread — trades a bounded, uncontended lock for an unbounded
 *    set of orderings that cannot be tested on this branch at all (see the
 *    acceptance note in BUILD_REQUEST_V1.3.md: there is no Apple hardware in
 *    the loop). The critical sections are the smallest they can be.
 *  - EV_FORMAT_CHANGED is never emitted. The AudioUnit's client format is fixed
 *    for the lifetime of the session and the unit's own converter absorbs a
 *    hardware-rate change (e.g. an iOS route change to Bluetooth HFP). The
 *    format the caller was given therefore stays valid, which is precisely the
 *    condition under which the ABI does NOT require the event.
 *  - EV_INTERRUPTION_BEGIN/END are never emitted: interruption handling is
 *    V1.10's (see cleona_voice_apple_platform.h).
 *  - macOS declines route SWITCHES (ERR_ROUTE_UNSUPPORTED) while reporting the
 *    route SET truthfully. Reason in cleona_voice_apple_mac.c.
 *
 * ===========================================================================
 * S13 — "the mute state survives a route change" (§10.4), and why it holds
 * ===========================================================================
 * On iOS a route change is the NORMAL case, not the exception: headphones go
 * in, a Bluetooth headset connects, the phone goes to the ear. The failure mode
 * the check exists for — the microphone quietly going live again when a headset
 * is unplugged mid-call — would be discovered by a user, after the fact.
 *
 * This backend satisfies S13 structurally rather than by carrying the flags
 * across a rebuild, because there is no rebuild to carry them across:
 *
 *   - cleona_voice_set_route() touches `s->unit` not at all. It validates, asks
 *     the platform layer, re-reads the route set and queues an event. Every
 *     AudioComponentInstanceNew / AudioUnitInitialize / AudioUnitUninitialize /
 *     AudioComponentInstanceDispose / cva_ring_init / cva_ring_free in this
 *     file lives in cleona_voice_open() (or its error path) or in
 *     cleona_voice_close(); AudioOutputUnitStart/Stop live only in start/stop.
 *   - iOS switches the route on the LIVE AVAudioSession
 *     (overrideOutputAudioPort / setPreferredInput). The AudioUnit is never
 *     stopped, so §10.4 rule 4 holds too: the AEC stays converged.
 *   - macOS declines the switch outright, so nothing is at risk there.
 *   - `mic_muted` and `output_muted` are written in exactly two places in this
 *     file — the two setters — and read in three: the render callback, the
 *     capture read, and the report. No route path writes them.
 *
 * That reasoning is the ONLY evidence available on this branch: see
 * BUILD_REQUEST_V1.3.md §5 — the conformance test has never been run on either
 * Apple target, so S13 is argued from the code, not observed.
 */

#include "../cleona_voice.h"
#include "cleona_voice_apple_platform.h"

#include <AudioToolbox/AudioToolbox.h>
#include <TargetConditionals.h>

#include <errno.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>

/* ==========================================================================
 * Tunables — all expressed in FRAMES, never in samples or milliseconds, so
 * they mean the same thing at 8 kHz and at 48 kHz.
 * ========================================================================== */

/* Capture ring depth. Deep enough that a caller which is briefly late (a GC
 * pause, a UI frame) loses nothing, shallow enough that a caller which stopped
 * reading is reported as an overrun instead of accumulating minutes of audio. */
#define CVA_CAPTURE_FRAMES  16   /* 320 ms */

/* Playback ring depth. The jitter buffer upstream does the pacing; this only
 * has to absorb the burst a decoder hands over at once. cleona_voice_playback_
 * write() never blocks (I5), so a caller that overruns this is told through the
 * counter, not through backpressure. */
#define CVA_PLAYBACK_FRAMES 25   /* 500 ms */

#define CVA_EVENT_QUEUE     16

/* Upper bound on inNumberFrames we are prepared to render in one callback.
 * Set on the unit AND used to size the scratch buffer, so the two can never
 * disagree. 4096 is what iOS asks for when the screen is locked and the media
 * server hands out the large slice; asking for it up front avoids a
 * kAudioUnitErr_TooManyFramesToProcess at exactly the worst moment. */
#define CVA_MAX_FRAMES_PER_SLICE 4096

/* ==========================================================================
 * Sample ring — one producer (a render callback), one consumer (the ABI), the
 * session lock held by both. Drop-oldest on overflow, counted, never silent.
 * ========================================================================== */

typedef struct {
    int16_t* data;
    int32_t  cap;    /* samples */
    int32_t  head;   /* read index */
    int32_t  count;  /* samples available */
} cva_ring_t;

static int cva_ring_init(cva_ring_t* r, int32_t cap) {
    r->data = (int16_t*)calloc((size_t)cap, sizeof(int16_t));
    if (!r->data) return -1;
    r->cap = cap;
    r->head = 0;
    r->count = 0;
    return 0;
}

static void cva_ring_free(cva_ring_t* r) {
    free(r->data);
    r->data = NULL;
    r->cap = 0;
    r->head = 0;
    r->count = 0;
}

static void cva_ring_drop(cva_ring_t* r, int32_t n) {
    if (n > r->count) n = r->count;
    r->head = (r->head + n) % r->cap;
    r->count -= n;
}

/* Appends `n` samples. Returns how many samples had to be dropped from the
 * front to make room — 0 in the normal case. */
static int32_t cva_ring_push(cva_ring_t* r, const int16_t* src, int32_t n) {
    int32_t dropped = 0;
    if (n >= r->cap) {
        /* Cannot happen with the depths above (a callback slice is far smaller
         * than the ring), but a truncating memcpy here would be a silent data
         * corruption, so it is handled rather than assumed away. */
        dropped = r->count + (n - r->cap);
        src += (n - r->cap);
        n = r->cap;
        r->head = 0;
        r->count = 0;
    } else if (r->count + n > r->cap) {
        dropped = r->count + n - r->cap;
        cva_ring_drop(r, dropped);
    }
    for (int32_t i = 0; i < n; i++) {
        r->data[(r->head + r->count + i) % r->cap] = src[i];
    }
    r->count += n;
    return dropped;
}

/* Removes up to `n` samples into `dst`. Returns how many were actually
 * removed — the caller decides what a short read means. */
static int32_t cva_ring_pop(cva_ring_t* r, int16_t* dst, int32_t n) {
    if (n > r->count) n = r->count;
    for (int32_t i = 0; i < n; i++) {
        dst[i] = r->data[(r->head + i) % r->cap];
    }
    r->head = (r->head + n) % r->cap;
    r->count -= n;
    return n;
}

/* ==========================================================================
 * Session
 * ========================================================================== */

struct cleona_voice_session {
    pthread_mutex_t lock;
    pthread_cond_t  capture_cv;

    cleona_voice_format_t fmt;

    AudioUnit unit;          /* the single duplex VPIO instance — I2 */
    int       unit_ready;    /* AudioUnitInitialize succeeded */
    int32_t   running;

    cva_platform_t* plat;

    int32_t mic_muted;
    int32_t output_muted;

    cva_ring_t cap_ring;
    cva_ring_t pb_ring;
    int16_t*   scratch;      /* AudioUnitRender target, CVA_MAX_FRAMES_PER_SLICE */
    int32_t    scratch_cap;  /* in samples */

    /* Effect states, each a READBACK (I11), refreshed by cva_probe_effects(). */
    int32_t aec_state, ns_state, agc_state;

    int64_t underruns, overruns;

    int32_t ev_type[CVA_EVENT_QUEUE];
    int32_t ev_arg[CVA_EVENT_QUEUE];
    int32_t ev_head, ev_count;
};

/* ==========================================================================
 * Small helpers
 * ========================================================================== */

static void cva_fail_open(cleona_voice_format_t* out_format, int32_t err) {
    /* In-band failure reporting, cleona_voice.h: a negative value in
     * sample_rate can never be mistaken for a negotiated format. */
    if (out_format) {
        out_format->sample_rate   = err;
        out_format->channels      = 0;
        out_format->frame_samples = 0;
        out_format->frame_bytes   = 0;
    }
}

/* Caller holds the lock. On overflow the OLDEST entry goes, as cleona_voice.h
 * requires — the newest route mask must survive. */
static void cva_push_event_locked(cleona_voice_session_t* s, int32_t ev, int32_t arg) {
    if (s->ev_count == CVA_EVENT_QUEUE) {
        s->ev_head = (s->ev_head + 1) % CVA_EVENT_QUEUE;
        s->ev_count--;
    }
    int32_t tail = (s->ev_head + s->ev_count) % CVA_EVENT_QUEUE;
    s->ev_type[tail] = ev;
    s->ev_arg[tail]  = arg;
    s->ev_count++;
}

/* Route-change notification from the OS (CoreAudio listener thread on macOS,
 * NSNotificationCenter post on iOS). Reads the new mask and queues one event. */
static void cva_on_route_changed(void* ctx) {
    cleona_voice_session_t* s = (cleona_voice_session_t*)ctx;
    if (!s) return;
    int32_t mask = 0, rin = 0, rout = 0;
    cva_platform_routes(s->plat, &mask, &rin, &rout);
    pthread_mutex_lock(&s->lock);
    cva_push_event_locked(s, CLEONA_VOICE_EV_ROUTES_CHANGED, mask);
    pthread_mutex_unlock(&s->lock);
}

/* I3/C1: the ABI's own normative bounds (cleona_voice.h:109-112) say a
 * conformant backend reports 8000..48000 Hz with frame_samples == rate/50.
 *
 * Apple hardware routinely runs outside that: a macOS interface at 96 kHz or
 * 192 kHz is ordinary, and a rate that is not a multiple of 50 Hz cannot carry
 * an exact 20 ms frame at all. In both cases this function asks the AudioUnit's
 * own converter for 48 kHz instead — VPIO converts between the hardware format
 * and the client format itself, so nothing here resamples (I1 holds).
 *
 * This is NOT "forcing 16 kHz", which is what I3 forbids and what §10.4 calls
 * out for excluding Android's fast path and fighting Apple's VPIO. The hardware
 * rate is adopted whenever it is expressible in the ABI; the fallback applies
 * only where the ABI could not represent the value, and the value actually
 * negotiated is what cleona_voice_open() returns and what the report carries.
 * Nothing downstream ever sees an assumed number. */
#define CVA_FALLBACK_RATE 48000

static int32_t cva_choose_rate(double hw_rate) {
    int32_t r = (int32_t)(hw_rate + 0.5);
    if (r < CLEONA_VOICE_RATE_MIN || r > CLEONA_VOICE_RATE_MAX) return CVA_FALLBACK_RATE;
    if ((r % CLEONA_VOICE_FRAME_HZ) != 0) return CVA_FALLBACK_RATE;
    return r;
}

static void cva_format_from_rate(cleona_voice_format_t* f, int32_t rate) {
    f->sample_rate   = rate;
    f->channels      = CLEONA_VOICE_CHANNELS;
    f->frame_samples = rate / CLEONA_VOICE_FRAME_HZ;
    f->frame_bytes   = f->frame_samples * f->channels * 2;
}

/* ==========================================================================
 * VPIO render callbacks — the only two places that run on a real-time thread
 * ========================================================================== */

static OSStatus cva_input_cb(void* ref,
                             AudioUnitRenderActionFlags* flags,
                             const AudioTimeStamp* ts,
                             UInt32 bus,
                             UInt32 nframes,
                             AudioBufferList* io) {
    cleona_voice_session_t* s = (cleona_voice_session_t*)ref;
    (void)io;   /* NULL for an input callback — we supply our own buffer list */

    if (!s || !s->unit || nframes == 0) return noErr;

    /* I4 in its rawest form: nframes is whatever the OS felt like. It is not
     * checked against a frame size, it is not rejected, it is not padded. */
    if ((int32_t)nframes > s->scratch_cap) {
        /* The unit handed us more than it promised through
         * kAudioUnitProperty_MaximumFramesPerSlice. Rendering into a short
         * buffer would be a heap overflow; counting the loss is the only
         * honest option. */
        pthread_mutex_lock(&s->lock);
        s->overruns++;
        pthread_mutex_unlock(&s->lock);
        return noErr;
    }

    AudioBufferList abl;
    abl.mNumberBuffers = 1;
    abl.mBuffers[0].mNumberChannels = 1;
    abl.mBuffers[0].mDataByteSize   = (UInt32)nframes * 2u;
    abl.mBuffers[0].mData           = s->scratch;

    OSStatus st = AudioUnitRender(s->unit, flags, ts, bus, nframes, &abl);
    if (st != noErr) {
        pthread_mutex_lock(&s->lock);
        s->overruns++;
        pthread_mutex_unlock(&s->lock);
        return st;
    }

    pthread_mutex_lock(&s->lock);
    if (s->running) {
        int32_t dropped = cva_ring_push(&s->cap_ring, s->scratch, (int32_t)nframes);
        if (dropped > 0) s->overruns++;
        pthread_cond_signal(&s->capture_cv);
    }
    pthread_mutex_unlock(&s->lock);
    return noErr;
}

static OSStatus cva_render_cb(void* ref,
                              AudioUnitRenderActionFlags* flags,
                              const AudioTimeStamp* ts,
                              UInt32 bus,
                              UInt32 nframes,
                              AudioBufferList* io) {
    cleona_voice_session_t* s = (cleona_voice_session_t*)ref;
    (void)ts;
    (void)bus;

    if (!s || !io || io->mNumberBuffers < 1) return noErr;

    int16_t* dst = (int16_t*)io->mBuffers[0].mData;
    UInt32   cap = io->mBuffers[0].mDataByteSize / 2u;
    if (!dst || cap == 0) return noErr;
    if (nframes > cap) nframes = cap;

    pthread_mutex_lock(&s->lock);
    int32_t got = s->running ? cva_ring_pop(&s->pb_ring, dst, (int32_t)nframes) : 0;
    if (got < (int32_t)nframes) {
        memset(dst + got, 0, (size_t)((int32_t)nframes - got) * sizeof(int16_t));
        /* An underrun before the first playback_write is normal, not a defect;
         * the counter is monotonic evidence, not an alarm. */
        s->underruns++;
    }
    /* I6: output mute renders SILENCE but still CONSUMES, so the jitter buffer
     * upstream never builds a backlog that bursts on re-enable. The pop above
     * has already happened — only the samples are replaced. */
    int muted = s->output_muted;
    pthread_mutex_unlock(&s->lock);

    if (muted) {
        memset(dst, 0, (size_t)nframes * sizeof(int16_t));
        got = 0;
    }
    if (got == 0 && flags) *flags |= kAudioUnitRenderAction_OutputIsSilence;
    io->mBuffers[0].mDataByteSize = (UInt32)nframes * 2u;
    return noErr;
}

/* ==========================================================================
 * Effect probing — I11. Every value here is read back from the unit.
 * ========================================================================== */

static void cva_probe_effects(cleona_voice_session_t* s) {
    /* Defaults are the honest ones: without a unit there is nothing to read. */
    s->aec_state = CLEONA_VOICE_FX_UNKNOWN;
    s->ns_state  = CLEONA_VOICE_FX_UNKNOWN;
    s->agc_state = CLEONA_VOICE_FX_UNKNOWN;
    if (!s->unit) return;

    UInt32 bypass = 0;
    UInt32 size = (UInt32)sizeof(bypass);
    OSStatus st = AudioUnitGetProperty(s->unit,
                                       kAUVoiceIOProperty_BypassVoiceProcessing,
                                       kAudioUnitScope_Global, 0, &bypass, &size);
    if (st == noErr) {
        s->aec_state = (bypass == 0) ? CLEONA_VOICE_FX_ENABLED
                                     : CLEONA_VOICE_FX_AVAILABLE_OFF;
    }
    /* NS stays UNKNOWN unconditionally. The full reasoning is in the file
     * header under "DOCUMENTED REASONS"; the one-line version is that VPIO has
     * no NS property, so there is nothing to read back, and I11 forbids
     * promoting a documented behaviour to an observed one. */

    UInt32 agc = 0;
    size = (UInt32)sizeof(agc);
    st = AudioUnitGetProperty(s->unit,
                              kAUVoiceIOProperty_VoiceProcessingEnableAGC,
                              kAudioUnitScope_Global, 0, &agc, &size);
    if (st == noErr) {
        s->agc_state = (agc != 0) ? CLEONA_VOICE_FX_ENABLED
                                  : CLEONA_VOICE_FX_AVAILABLE_OFF;
    } else if (st == kAudioUnitErr_InvalidProperty) {
        s->agc_state = CLEONA_VOICE_FX_UNAVAILABLE;
    }
}

/* ==========================================================================
 * Unit construction
 * ========================================================================== */

static int32_t cva_open_unit(cleona_voice_session_t* s) {
    AudioComponentDescription desc;
    memset(&desc, 0, sizeof(desc));
    desc.componentType         = kAudioUnitType_Output;
    /* THE line this whole work package exists for (§10.4 defect row 3). */
    desc.componentSubType      = kAudioUnitSubType_VoiceProcessingIO;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;

    AudioComponent comp = AudioComponentFindNext(NULL, &desc);
    if (!comp) return CLEONA_VOICE_ERR_UNSUPPORTED;

    OSStatus st = AudioComponentInstanceNew(comp, &s->unit);
    if (st != noErr || !s->unit) {
        s->unit = NULL;
        return CLEONA_VOICE_ERR_BACKEND;
    }

    const AudioUnitElement kInputBus  = 1;   /* microphone side */
    const AudioUnitElement kOutputBus = 0;   /* speaker side    */
    UInt32 on = 1;

    /* I2: both directions on ONE instance. Input is off by default on an
     * output unit, so it must be enabled explicitly; output is enabled
     * explicitly as well so the intent is visible rather than inherited. */
    st = AudioUnitSetProperty(s->unit, kAudioOutputUnitProperty_EnableIO,
                              kAudioUnitScope_Input, kInputBus, &on, sizeof(on));
    if (st != noErr) return CLEONA_VOICE_ERR_BACKEND;
    st = AudioUnitSetProperty(s->unit, kAudioOutputUnitProperty_EnableIO,
                              kAudioUnitScope_Output, kOutputBus, &on, sizeof(on));
    if (st != noErr) return CLEONA_VOICE_ERR_BACKEND;

    /* Client format: exactly the ABI's frame contract — S16, mono, interleaved
     * (§10.4: "the only format all five chains deliver without conversion"),
     * at the rate that was negotiated from the hardware. VPIO converts between
     * this and the hardware format internally; we do not. */
    AudioStreamBasicDescription asbd;
    memset(&asbd, 0, sizeof(asbd));
    asbd.mSampleRate       = (Float64)s->fmt.sample_rate;
    asbd.mFormatID         = kAudioFormatLinearPCM;
    asbd.mFormatFlags      = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    asbd.mFramesPerPacket  = 1;
    asbd.mChannelsPerFrame = (UInt32)CLEONA_VOICE_CHANNELS;
    asbd.mBitsPerChannel   = 16;
    asbd.mBytesPerFrame    = 2;
    asbd.mBytesPerPacket   = 2;

    st = AudioUnitSetProperty(s->unit, kAudioUnitProperty_StreamFormat,
                              kAudioUnitScope_Output, kInputBus,
                              &asbd, sizeof(asbd));
    if (st != noErr) return CLEONA_VOICE_ERR_BACKEND;
    st = AudioUnitSetProperty(s->unit, kAudioUnitProperty_StreamFormat,
                              kAudioUnitScope_Input, kOutputBus,
                              &asbd, sizeof(asbd));
    if (st != noErr) return CLEONA_VOICE_ERR_BACKEND;

    UInt32 max_slice = CVA_MAX_FRAMES_PER_SLICE;
    /* Advisory: a unit that refuses this still works, it just has to be trusted
     * to stay under the value it reports. The input callback checks the actual
     * slice size against the scratch buffer on every call regardless. */
    (void)AudioUnitSetProperty(s->unit, kAudioUnitProperty_MaximumFramesPerSlice,
                               kAudioUnitScope_Global, 0,
                               &max_slice, sizeof(max_slice));

    /* --- the two mandatory VPIO properties (SPEC §7 V1.3) --- */
    UInt32 bypass = 0;   /* 0 = voice processing ACTIVE */
    st = AudioUnitSetProperty(s->unit, kAUVoiceIOProperty_BypassVoiceProcessing,
                              kAudioUnitScope_Global, 0, &bypass, sizeof(bypass));
    if (st != noErr) return CLEONA_VOICE_ERR_BACKEND;

    UInt32 agc = 1;      /* §10.4 defect row 6: never switched on before */
    /* Deliberately NOT fatal. If a future OS drops the property, the call fails
     * and cva_probe_effects() reports agc = unavailable — which is a truthful
     * report, whereas refusing to open would take away a working call over an
     * effect the platform no longer exposes. */
    (void)AudioUnitSetProperty(s->unit, kAUVoiceIOProperty_VoiceProcessingEnableAGC,
                               kAudioUnitScope_Global, 0, &agc, sizeof(agc));

    AURenderCallbackStruct cb;
    cb.inputProc       = cva_input_cb;
    cb.inputProcRefCon = s;
    st = AudioUnitSetProperty(s->unit, kAudioOutputUnitProperty_SetInputCallback,
                              kAudioUnitScope_Global, 0, &cb, sizeof(cb));
    if (st != noErr) return CLEONA_VOICE_ERR_BACKEND;

    cb.inputProc       = cva_render_cb;
    cb.inputProcRefCon = s;
    st = AudioUnitSetProperty(s->unit, kAudioUnitProperty_SetRenderCallback,
                              kAudioUnitScope_Input, kOutputBus, &cb, sizeof(cb));
    if (st != noErr) return CLEONA_VOICE_ERR_BACKEND;

    st = AudioUnitInitialize(s->unit);
    if (st != noErr) {
        /* The one OSStatus worth translating: on iOS this is what a denied
         * microphone permission surfaces as once the session is active. */
        return (st == kAudioUnitErr_CannotDoInCurrentContext)
                   ? CLEONA_VOICE_ERR_NO_DEVICE
                   : CLEONA_VOICE_ERR_BACKEND;
    }
    s->unit_ready = 1;

    /* Read back what the unit ACTUALLY negotiated, rather than trusting that
     * the set calls above stuck. If the unit changed the rate on us, the ABI
     * format follows it — everything above the ABI computes with the reported
     * value (I3), so it must be the true one. */
    AudioStreamBasicDescription actual;
    UInt32 asize = (UInt32)sizeof(actual);
    memset(&actual, 0, sizeof(actual));
    if (AudioUnitGetProperty(s->unit, kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Output, kInputBus,
                             &actual, &asize) == noErr) {
        int32_t got = cva_choose_rate(actual.mSampleRate);
        if (got != s->fmt.sample_rate) cva_format_from_rate(&s->fmt, got);
    }

    cva_probe_effects(s);
    return CLEONA_VOICE_OK;
}

/* ==========================================================================
 * ABI — lifecycle
 * ========================================================================== */

CLEONA_VOICE_API cleona_voice_session_t* cleona_voice_open(
    int32_t rate_hint, cleona_voice_format_t* out_format) {

    if (!out_format) return NULL;
    (void)rate_hint;   /* I3: a hint, and this backend takes the hardware rate.
                        * Recorded here rather than silently absent so a reader
                        * does not go looking for the place that honours it. */

    cleona_voice_session_t* s =
        (cleona_voice_session_t*)calloc(1, sizeof(cleona_voice_session_t));
    if (!s) {
        cva_fail_open(out_format, CLEONA_VOICE_ERR_BACKEND);
        return NULL;
    }

    pthread_mutex_init(&s->lock, NULL);
    pthread_cond_init(&s->capture_cv, NULL);
    s->aec_state = CLEONA_VOICE_FX_UNKNOWN;
    s->ns_state  = CLEONA_VOICE_FX_UNKNOWN;
    s->agc_state = CLEONA_VOICE_FX_UNKNOWN;

    int32_t rc = cva_platform_open(cva_on_route_changed, s, &s->plat);
    if (rc != CLEONA_VOICE_OK) {
        pthread_cond_destroy(&s->capture_cv);
        pthread_mutex_destroy(&s->lock);
        free(s);
        cva_fail_open(out_format, rc);
        return NULL;
    }

    cva_format_from_rate(&s->fmt, cva_choose_rate(cva_platform_hardware_rate(s->plat)));

    rc = cva_open_unit(s);
    if (rc != CLEONA_VOICE_OK) {
        if (s->unit) {
            if (s->unit_ready) AudioUnitUninitialize(s->unit);
            AudioComponentInstanceDispose(s->unit);
        }
        cva_platform_close(s->plat);
        pthread_cond_destroy(&s->capture_cv);
        pthread_mutex_destroy(&s->lock);
        free(s);
        cva_fail_open(out_format, rc);
        return NULL;
    }

    /* Buffers are sized from the NEGOTIATED frame size, after the unit had its
     * say — never from a constant (I4). */
    s->scratch_cap = CVA_MAX_FRAMES_PER_SLICE;
    s->scratch = (int16_t*)calloc((size_t)s->scratch_cap, sizeof(int16_t));
    if (!s->scratch
        || cva_ring_init(&s->cap_ring, s->fmt.frame_samples * CVA_CAPTURE_FRAMES) != 0
        || cva_ring_init(&s->pb_ring,  s->fmt.frame_samples * CVA_PLAYBACK_FRAMES) != 0) {
        cleona_voice_close(s);
        cva_fail_open(out_format, CLEONA_VOICE_ERR_BACKEND);
        return NULL;
    }

    *out_format = s->fmt;
    return s;
}

CLEONA_VOICE_API int32_t cleona_voice_start(cleona_voice_session_t* s) {
    if (!s) return CLEONA_VOICE_ERR_CLOSED;
    pthread_mutex_lock(&s->lock);
    if (s->running) {
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VOICE_ERR_ALREADY_STARTED;
    }
    if (!s->unit || !s->unit_ready) {
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VOICE_ERR_CLOSED;
    }
    /* A restart must not replay whatever the previous run left behind. */
    cva_ring_drop(&s->cap_ring, s->cap_ring.count);
    cva_ring_drop(&s->pb_ring,  s->pb_ring.count);
    s->running = 1;
    pthread_mutex_unlock(&s->lock);

    OSStatus st = AudioOutputUnitStart(s->unit);
    if (st != noErr) {
        pthread_mutex_lock(&s->lock);
        s->running = 0;
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VOICE_ERR_BACKEND;
    }

    /* Re-read the effect states now that the chain is actually running: a
     * property that answered before the unit started is weaker evidence than
     * one that answers while it is processing. */
    cva_probe_effects(s);
    return CLEONA_VOICE_OK;
}

CLEONA_VOICE_API void cleona_voice_stop(cleona_voice_session_t* s) {
    if (!s) return;
    pthread_mutex_lock(&s->lock);
    int was_running = s->running;
    s->running = 0;
    /* Wake every capture_read waiter so none of them sits out its full timeout
     * before it learns the session is gone. */
    pthread_cond_broadcast(&s->capture_cv);
    pthread_mutex_unlock(&s->lock);

    if (was_running && s->unit) AudioOutputUnitStop(s->unit);
}

CLEONA_VOICE_API void cleona_voice_close(cleona_voice_session_t* s) {
    if (!s) return;
    cleona_voice_stop(s);

    if (s->unit) {
        if (s->unit_ready) AudioUnitUninitialize(s->unit);
        AudioComponentInstanceDispose(s->unit);
        s->unit = NULL;
        s->unit_ready = 0;
    }
    /* After the unit is gone no callback can still reference the session, so
     * the platform listeners can be removed and the buffers released. */
    cva_platform_close(s->plat);
    s->plat = NULL;

    cva_ring_free(&s->cap_ring);
    cva_ring_free(&s->pb_ring);
    free(s->scratch);
    s->scratch = NULL;

    pthread_cond_destroy(&s->capture_cv);
    pthread_mutex_destroy(&s->lock);
    free(s);
}

/* ==========================================================================
 * ABI — data path
 * ========================================================================== */

CLEONA_VOICE_API int32_t cleona_voice_capture_read(cleona_voice_session_t* s,
                                                   int16_t* out,
                                                   int32_t timeout_ms) {
    if (!s || !out) return CLEONA_VOICE_CAPTURE_CLOSED;

    struct timeval tv0;
    gettimeofday(&tv0, NULL);
    int64_t deadline_us = (int64_t)tv0.tv_sec * 1000000 + tv0.tv_usec
                        + (int64_t)(timeout_ms > 0 ? timeout_ms : 0) * 1000;

    pthread_mutex_lock(&s->lock);
    for (;;) {
        if (!s->running) {
            pthread_mutex_unlock(&s->lock);
            return CLEONA_VOICE_CAPTURE_CLOSED;
        }
        if (s->cap_ring.count >= s->fmt.frame_samples) {
            /* I4: exactly one frame, never a short one, never a partial drop. */
            cva_ring_pop(&s->cap_ring, out, s->fmt.frame_samples);
            int muted = s->mic_muted;
            pthread_mutex_unlock(&s->lock);
            /* I6: the stream stayed open and the cadence is untouched; only the
             * samples are zeroed. Zeroing HERE rather than at production means
             * the mute takes effect on the very next frame instead of after the
             * ring has drained — the caller asked for silence now, not in
             * 320 ms. */
            if (muted) memset(out, 0, (size_t)s->fmt.frame_bytes);
            return CLEONA_VOICE_CAPTURE_FRAME;
        }

        struct timeval tv;
        gettimeofday(&tv, NULL);
        int64_t now_us = (int64_t)tv.tv_sec * 1000000 + tv.tv_usec;
        if (timeout_ms <= 0 || now_us >= deadline_us) {
            pthread_mutex_unlock(&s->lock);
            /* Contract: nothing is written to `out` on a timeout. */
            return CLEONA_VOICE_CAPTURE_TIMEOUT;
        }

        /* Relative wait: macOS/iOS have no pthread_condattr_setclock, so a
         * CLOCK_REALTIME absolute deadline would jump with a clock adjustment.
         * pthread_cond_timedwait_relative_np is the Apple-native answer. */
        int64_t rem_us = deadline_us - now_us;
        struct timespec rel;
        rel.tv_sec  = (time_t)(rem_us / 1000000);
        rel.tv_nsec = (long)((rem_us % 1000000) * 1000);
        int wr = pthread_cond_timedwait_relative_np(&s->capture_cv, &s->lock, &rel);
        if (wr != 0 && wr != ETIMEDOUT) {
            /* A wait that cannot wait would turn this loop into a spin until
             * the deadline. Reporting a timeout is both truthful (no frame was
             * produced) and bounded. */
            pthread_mutex_unlock(&s->lock);
            return CLEONA_VOICE_CAPTURE_TIMEOUT;
        }
        /* Otherwise loop once more: on ETIMEDOUT the frame may have arrived
         * together with the timeout, and returning TIMEOUT with data in the
         * ring would put a frame of latency into every call for no reason. */
    }
}

CLEONA_VOICE_API int32_t cleona_voice_playback_write(cleona_voice_session_t* s,
                                                     const int16_t* pcm,
                                                     int32_t frame_samples) {
    if (!s || !pcm) return CLEONA_VOICE_ERR_INVALID_ARG;

    pthread_mutex_lock(&s->lock);
    if (!s->running) {
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VOICE_ERR_NOT_STARTED;
    }
    if (frame_samples != s->fmt.frame_samples) {
        pthread_mutex_unlock(&s->lock);
        /* SPEC §6 check 4: rejected, never padded or truncated. Silent
         * adaptation here is how a rate mismatch becomes a mystery later. */
        return CLEONA_VOICE_ERR_FRAME_SIZE;
    }
    /* I5: copy and return. The output device paces; if the caller is early, the
     * ring absorbs it, and if it is far too early the counter says so. */
    int32_t dropped = cva_ring_push(&s->pb_ring, pcm, frame_samples);
    if (dropped > 0) s->overruns++;
    pthread_mutex_unlock(&s->lock);
    return CLEONA_VOICE_OK;
}

/* ==========================================================================
 * ABI — controls
 * ========================================================================== */

CLEONA_VOICE_API void cleona_voice_set_mic_muted(cleona_voice_session_t* s,
                                                 int32_t muted) {
    if (!s) return;
    pthread_mutex_lock(&s->lock);
    s->mic_muted = muted ? 1 : 0;
    pthread_mutex_unlock(&s->lock);
    /* Nothing is stopped, nothing is reconfigured. §10.4: stopping the stream
     * diverges the adaptive filter and produces about a second of echo on
     * unmute — the superseded C code already knew this (cleona_audio.c:152-156)
     * and the insight survives the rewrite. */
}

CLEONA_VOICE_API void cleona_voice_set_output_muted(cleona_voice_session_t* s,
                                                    int32_t muted) {
    if (!s) return;
    pthread_mutex_lock(&s->lock);
    s->output_muted = muted ? 1 : 0;
    pthread_mutex_unlock(&s->lock);
}

CLEONA_VOICE_API int32_t cleona_voice_set_route(cleona_voice_session_t* s,
                                                int32_t route) {
    if (!s) return CLEONA_VOICE_ERR_CLOSED;
    if (route < CLEONA_VOICE_ROUTE_EARPIECE || route > CLEONA_VOICE_ROUTE_BLUETOOTH) {
        /* Covers ROUTE_UNKNOWN (0), negatives and out-of-range alike. */
        return CLEONA_VOICE_ERR_INVALID_ARG;
    }

    int32_t mask = 0, rin = 0, rout = 0;
    cva_platform_routes(s->plat, &mask, &rin, &rout);
    if (route == rout) return CLEONA_VOICE_OK;      /* already active */
    if (!(mask & CLEONA_VOICE_ROUTE_BIT(route))) {
        /* The code SPEC §4 requires instead of a silent no-op — and the one a
         * macOS build returns for ROUTE_EARPIECE, every time. */
        return CLEONA_VOICE_ERR_ROUTE_UNAVAILABLE;
    }

    int32_t rc = cva_platform_set_route(s->plat, route);
    if (rc == CLEONA_VOICE_OK) {
        cva_platform_routes(s->plat, &mask, &rin, &rout);
        pthread_mutex_lock(&s->lock);
        cva_push_event_locked(s, CLEONA_VOICE_EV_ROUTES_CHANGED, mask);
        pthread_mutex_unlock(&s->lock);
    }
    return rc;
}

CLEONA_VOICE_API int32_t cleona_voice_get_routes(cleona_voice_session_t* s,
                                                 int32_t* out_mask,
                                                 int32_t* out_active) {
    if (!out_mask || !out_active) return CLEONA_VOICE_ERR_INVALID_ARG;
    if (!s) return CLEONA_VOICE_ERR_CLOSED;
    int32_t mask = 0, rin = 0, rout = 0;
    /* Read live from the OS on every call rather than from a cache: a cached
     * route is an old observation wearing the clothes of a current one. */
    cva_platform_routes(s->plat, &mask, &rin, &rout);
    *out_mask = mask;
    *out_active = rout;
    return CLEONA_VOICE_OK;
}

/* ==========================================================================
 * ABI — events
 * ========================================================================== */

CLEONA_VOICE_API int32_t cleona_voice_poll_event(cleona_voice_session_t* s,
                                                 int32_t* out_event,
                                                 int32_t* out_arg) {
    if (!out_event || !out_arg) return CLEONA_VOICE_ERR_INVALID_ARG;
    if (!s) return CLEONA_VOICE_ERR_CLOSED;

    pthread_mutex_lock(&s->lock);
    if (s->ev_count == 0) {
        pthread_mutex_unlock(&s->lock);
        *out_event = CLEONA_VOICE_EV_NONE;
        *out_arg = 0;
        return CLEONA_VOICE_OK;
    }
    *out_event = s->ev_type[s->ev_head];
    *out_arg   = s->ev_arg[s->ev_head];
    s->ev_head = (s->ev_head + 1) % CVA_EVENT_QUEUE;
    s->ev_count--;
    pthread_mutex_unlock(&s->lock);
    return CLEONA_VOICE_OK;
}

/* ==========================================================================
 * ABI — verification report (I11)
 * ========================================================================== */

CLEONA_VOICE_API void cleona_voice_get_report(cleona_voice_session_t* s,
                                              cleona_voice_report_t* out) {
    if (!out) return;
    memset(out, 0, sizeof(*out));
    /* A NULL session yields duplex == 0, which reads as a conformance failure
     * rather than as a plausible session — cleona_voice.h says so explicitly. */
    if (!s) return;

    /* Fresh readback rather than a value cached at open(): the report's whole
     * purpose is to answer "is the chain running NOW". */
    cva_probe_effects(s);

    int32_t mask = 0, rin = 0, rout = 0;
    cva_platform_routes(s->plat, &mask, &rin, &rout);

    pthread_mutex_lock(&s->lock);
    out->format       = s->fmt;
    out->aec_state    = s->aec_state;
    out->ns_state     = s->ns_state;
    out->agc_state    = s->agc_state;
    /* The chain origin is stated because a VPIO instance exists and is
     * initialized — not because an effect happened to read back as on. */
    out->chain_origin = s->unit_ready ? CLEONA_VOICE_CHAIN_APPLE_VPIO
                                      : CLEONA_VOICE_CHAIN_NONE;
    out->backend      = CLEONA_VOICE_BACKEND_APPLE_VPIO;
    /* I2: one AudioComponentInstance carries capture AND playback. This is a
     * property of the construction above, not a claim. */
    out->duplex       = s->unit_ready ? 1 : 0;
    out->route_active_in  = rin;
    out->route_active_out = rout;
    out->routes_available_mask = mask;
    /* Erratum E6a. A plain observation of what was last handed to
     * set_mic_muted() / set_output_muted() — deliberately NOT derived from the
     * AudioUnit or from AVAudioSession.
     *
     * Deriving it would be wrong twice over on this backend. VPIO has no input
     * mute property this file uses (the mute lives on the read side of the
     * capture ring and on the render side of the playback callback), so there
     * is nothing on the unit to read; and even where a platform state existed,
     * inferring "the caller asked for mute" from "the stream looks quiet" is
     * the kind of second-hand answer I11 rejects everywhere else in this
     * report. The caller told us the value, so we know it.
     *
     * Both fields are already normalised to exactly 0 or 1 by the setters,
     * which is where the one and only normalisation belongs. Copying them here
     * without a second `? 1 : 0` is what keeps the two places from ever
     * disagreeing about what a non-zero argument meant. */
    out->mic_muted    = s->mic_muted;
    out->output_muted = s->output_muted;
    out->underruns = s->underruns;
    out->overruns  = s->overruns;
    pthread_mutex_unlock(&s->lock);
}
