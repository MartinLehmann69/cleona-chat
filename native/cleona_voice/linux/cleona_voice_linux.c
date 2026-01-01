/* cleona_voice_linux.c — the Linux implementation of cleona_voice.h, backed by
 * PipeWire.
 *
 * Work package: docs/SPEC_VOICE_VIDEO_REWORK.md V1.1.
 * Architecture:  Cleona_Chat_Architecture_v3_0.md §10.4 ("Linux" row of the
 * platform matrix, and the Linux paragraph right below it).
 *
 * ---------------------------------------------------------------------------
 * THE TWO CHAINS, AND HOW THIS FILE PICKS BETWEEN THEM
 * ---------------------------------------------------------------------------
 * Linux is "the only platform without a guaranteed OS chain" (§10.4): there is
 * no single API every distribution answers the same way, the way VoiceProcessingIO
 * or WASAPI Communications do on their platforms. Architecture §10.4 and SPEC §7
 * (V1.1) both prescribe the same order of preference:
 *
 *   1. `libpipewire-module-echo-cancel`, which wraps AEC3 (chain_origin =
 *      CLEONA_VOICE_CHAIN_PIPEWIRE_FILTER).
 *   2. WebRTC's AudioProcessing linked directly (chain_origin =
 *      CLEONA_VOICE_CHAIN_LINKED_APM) — explicitly NOT speexdsp (measured
 *      reason in §10.4: speexdsp has neither a delay estimator nor a residual
 *      suppressor; ERLE collapses to +14.7 dB at a 300 ms echo path).
 *
 * BOTH paths go through the SAME module, `libpipewire-module-echo-cancel`,
 * loaded into THIS process's own pw_context via pw_context_load_module() —
 * verified empirically to work from an ordinary client process, not just from
 * the PipeWire daemon itself (see the four virtual nodes it creates, below).
 * This is deliberate and is the reason I2 holds on both paths: the module
 * unconditionally creates ONE correlated capture/playback pair — a virtual
 * "Echo Cancellation Source" node this file's capture stream connects to, and
 * a virtual "Echo Cancellation Sink" node this file's playback stream connects
 * to — regardless of which cancellation engine is plugged into it. What
 * differs between the two paths is only the `library.name` argument: real
 * AEC3 ("aec/libspa-aec-webrtc") for the preferred path, or an explicit
 * passthrough ("aec/libspa-aec-null") for the fallback, over which this file
 * layers its own linked webrtc::AudioProcessing (voice_apm_shim.*) — same
 * duplex plumbing, different engine.
 *
 * Skipping the module entirely and opening two independent pw_streams
 * straight at the default source and default sink was considered and
 * rejected: those two nodes are not guaranteed to share a clock (different
 * physical devices, e.g. a USB headset mic with built-in speakers), which is
 * exactly defect #1 of the superseded miniaudio stack (architecture §10.4,
 * "Superseded stack" table: "two independent ma_device instances on two
 * clocks"). If neither AEC library can be loaded — the module binary itself
 * is missing, which does not happen on a stock PipeWire desktop install where
 * pipewire-modules is a base dependency — cleona_voice_open() fails outright
 * (CLEONA_VOICE_ERR_BACKEND) rather than silently reproducing that defect.
 *
 * ---------------------------------------------------------------------------
 * WHY THE VERIFICATION REPORT (I11) SPLITS AEC/NS/AGC DIFFERENTLY PER PATH
 * ---------------------------------------------------------------------------
 * PIPEWIRE_FILTER: verified empirically (see the exploratory session that
 * produced this file — pw_context_load_module() with an explicit,
 * intentionally-wrong `library.name` FAILS THE WHOLE MODULE LOAD rather than
 * silently falling back to a different engine) that requesting
 * "aec/libspa-aec-webrtc" by name and getting a successful load really does
 * mean that plugin is instantiated. That is real evidence, not a guess. What
 * there is NO evidence for is whether AEC/NS/AGC are each *individually*
 * active inside it at runtime: the module exposes no client-visible
 * introspection API for that (`spa_audio_aec` in
 * <spa/interfaces/audio/aec.h> is an in-process SPA interface internal to the
 * module, never surfaced over the PipeWire protocol to another client).
 * Reporting FX_ENABLED here would be exactly the trap I11 exists to name:
 * "never guess ENABLED because we asked for it. Asking is not evidence."
 * This file therefore reports FX_UNKNOWN for all three on this path — a
 * legitimate, expected answer (cleona_voice.h, SPEC §6: "acceptance of a
 * backend means conformance green + report logged + a documented reason for
 * every effect that is not ENABLED" — this comment is that reason).
 *
 * LINKED_APM: the opposite situation. `voice_apm_shim.*` owns an
 * in-process webrtc::AudioProcessing object; `cleona_voice_apm_*_enabled()`
 * calls the component's own is_enabled() — a genuine readback, not a
 * restatement of the Enable() call. FX_ENABLED on this path is backed by
 * that readback.
 *
 * ---------------------------------------------------------------------------
 * THREADING
 * ---------------------------------------------------------------------------
 * One pw_thread_loop per session drives PipeWire's own callbacks (state
 * changes, format negotiation, process()). The public capture_read() /
 * playback_write() functions never run on that thread; they take a plain
 * pthread mutex the process() callbacks also take, exactly the shape
 * cleona_voice.h's threading section describes (one capture thread, one
 * playback thread, both distinct from the callback-owning loop thread).
 */

#include "../cleona_voice.h"
#include "voice_apm_shim.h"

#include <pipewire/pipewire.h>
#include <pipewire/impl-module.h>
#include <spa/param/audio/format-utils.h>
#include <spa/pod/builder.h>
#include <spa/utils/result.h>

#include <pthread.h>
#include <time.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

/* ==========================================================================
 * Process-wide single-session guard
 * ==========================================================================
 * A duplex voice session models one active call, matching every real voice
 * chain this ABI abstracts (Android's session-id model, VoiceProcessingIO,
 * WASAPI Communications). cleona_voice.h's own conformance test tolerates a
 * backend that refuses a second concurrent open() ("N3": "second concurrent
 * open() refused -- single-session backend, recorded not failed"), so this is
 * a documented scope limit, not an ABI violation.
 */
static pthread_mutex_t g_session_guard = PTHREAD_MUTEX_INITIALIZER;
static int             g_session_active = 0;
static uint32_t        g_open_seq = 0;

/* ==========================================================================
 * Session state
 * ========================================================================== */

#define CVL_RING_FRAMES   8     /* headroom, same rationale as the mock's
                                  * MOCK_ACCUM_FRAMES: deep enough that a
                                  * briefly-late caller sees no spurious
                                  * over/underrun, shallow enough that a caller
                                  * which stopped altogether is reported. */
#define CVL_EVENT_QUEUE   16
#define CVL_MAX_FRAME_SAMPLES  (CLEONA_VOICE_RATE_MAX / CLEONA_VOICE_FRAME_HZ)  /* 960 @ 48kHz */

struct cleona_voice_session {
    pthread_mutex_t lock;
    pthread_cond_t  cond;      /* signalled on new capture data, on a state
                                 * change relevant to a waiter, or on stop() */

    struct pw_thread_loop *loop;
    struct pw_context     *context;
    struct pw_core        *core;

    struct pw_impl_module  *ec_module;
    struct pw_stream       *capture;    /* connects to the module's virtual "source" */
    struct pw_stream       *playback;   /* connects to the module's virtual "sink" */
    struct spa_hook         capture_listener;
    struct spa_hook         playback_listener;

    struct pw_registry     *registry;
    struct spa_hook         registry_listener;

    cleona_voice_format_t fmt;
    int32_t fmt_ready;          /* both directions negotiated and agree */
    int32_t open_error;         /* CLEONA_VOICE_ERR_* set during the open handshake */

    int32_t chain_origin;       /* CLEONA_VOICE_CHAIN_PIPEWIRE_FILTER / LINKED_APM */
    int32_t aec_state, ns_state, agc_state;

    cleona_voice_apm_t *apm;    /* non-NULL only on the LINKED_APM path */
    int16_t render_ring[CVL_RING_FRAMES * CVL_MAX_FRAME_SAMPLES];
    int32_t render_len;         /* samples currently queued, consumed FIFO */

    int32_t running;
    int32_t mic_muted;
    int32_t output_muted;

    /* Capture assembly buffer -- I4. Linear + memmove, mirroring the mock:
     * frame counts here are small (<=960 samples) so the copy cost is noise. */
    int16_t cap_accum[CVL_RING_FRAMES * CVL_MAX_FRAME_SAMPLES + CVL_MAX_FRAME_SAMPLES];
    int32_t cap_accum_len;

    /* Playback ring the app writes into (playback_write, never blocks -- I5)
     * and the device process() callback drains from, zero-filling on
     * starvation rather than waiting. */
    int16_t pb_ring[CVL_RING_FRAMES * CVL_MAX_FRAME_SAMPLES];
    int32_t pb_ring_head, pb_ring_len;

    int64_t underruns;   /* device wanted playback samples the ring didn't have */
    int64_t overruns;    /* a ring (capture or playback) overflowed */

    int32_t routes_mask, route_in, route_out;

    int32_t ev_type[CVL_EVENT_QUEUE], ev_arg[CVL_EVENT_QUEUE];
    int32_t ev_head, ev_count;

    char node_prefix[48];
};

/* ==========================================================================
 * Small helpers
 * ========================================================================== */

static int64_t cvl_now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void cvl_format_from_rate(cleona_voice_format_t* f, int32_t rate) {
    f->sample_rate   = rate;
    f->channels      = CLEONA_VOICE_CHANNELS;
    f->frame_samples = rate / CLEONA_VOICE_FRAME_HZ;
    f->frame_bytes   = f->frame_samples * f->channels * 2;
}

static void cvl_push_event_locked(cleona_voice_session_t* s, int32_t ev, int32_t arg) {
    if (s->ev_count == CVL_EVENT_QUEUE) {
        s->ev_head = (s->ev_head + 1) % CVL_EVENT_QUEUE;
        s->ev_count--;
    }
    int32_t tail = (s->ev_head + s->ev_count) % CVL_EVENT_QUEUE;
    s->ev_type[tail] = ev;
    s->ev_arg[tail]  = arg;
    s->ev_count++;
}

/* device.bus -> the route this backend maps it to. Desktop mapping (§10.4:
 * "macOS, Windows and Linux have no earpiece" -- ROUTE_EARPIECE is therefore
 * never produced here). This is this file's own reasoned completion of a gap
 * the architecture leaves unspecified for Linux specifically (it names the
 * desktop-wide "no earpiece" rule but not a bus->route table) -- flagged here
 * the same way route_policy.dart flags its own non-literal completions. */
static int32_t cvl_route_for_bus(const char* bus, const char* name) {
    if (bus && strcmp(bus, "bluetooth") == 0) return CLEONA_VOICE_ROUTE_BLUETOOTH;
    if (bus && strcmp(bus, "usb") == 0)       return CLEONA_VOICE_ROUTE_WIRED;
    if (name && (strstr(name, "headphone") || strstr(name, "headset")))
        return CLEONA_VOICE_ROUTE_WIRED;
    return CLEONA_VOICE_ROUTE_SPEAKER;
}

/* ==========================================================================
 * Registry: route enumeration (SPEC §4 "get_routes" / architecture's desktop
 * device-chooser model)
 * ==========================================================================
 * A one-shot synchronous scan at open()/on demand, plus a live listener that
 * turns Audio/Sink add/remove into CLEONA_VOICE_EV_ROUTES_CHANGED so the Dart
 * RoutePolicy (V1.5) sees headset arrival/removal without polling.
 */

/* Which route is "active" is resolved once, cheaply, in open() (see the
 * SPEAKER-first default right after the initial registry roundtrip below) --
 * not recomputed here. This listener's only job after that is (a) keep
 * routes_mask current as sinks come and go, and (b) tell the Dart RoutePolicy
 * (V1.5) that something changed, via CLEONA_VOICE_EV_ROUTES_CHANGED, so it can
 * re-read get_routes() and make the I7 call itself -- this backend never
 * picks a successor route on its own (see cvl_registry_global_remove below
 * and cleona_voice.h's note on the same point for the mock). */
static void cvl_registry_global(void* data, uint32_t id, uint32_t permissions,
                                const char* type, uint32_t version,
                                const struct spa_dict* props) {
    (void)permissions; (void)version; (void)id;
    cleona_voice_session_t* s = (cleona_voice_session_t*)data;
    if (!props || !type || strcmp(type, PW_TYPE_INTERFACE_Node) != 0) return;
    const char* mclass = spa_dict_lookup(props, PW_KEY_MEDIA_CLASS);
    if (!mclass || strcmp(mclass, "Audio/Sink") != 0) return;
    /* Never count our own virtual echo-cancel sink as a physical route. */
    const char* nname = spa_dict_lookup(props, PW_KEY_NODE_NAME);
    if (nname && strstr(nname, s->node_prefix)) return;

    const char* bus = spa_dict_lookup(props, PW_KEY_DEVICE_BUS);
    int32_t route = cvl_route_for_bus(bus, nname);

    pthread_mutex_lock(&s->lock);
    s->routes_mask |= CLEONA_VOICE_ROUTE_BIT(route);
    if (s->running) cvl_push_event_locked(s, CLEONA_VOICE_EV_ROUTES_CHANGED, s->routes_mask);
    pthread_mutex_unlock(&s->lock);
}

static void cvl_registry_global_remove(void* data, uint32_t id) {
    (void)id;
    cleona_voice_session_t* s = (cleona_voice_session_t*)data;
    /* A sink vanished. Recomputing the exact resulting mask would need the
     * full entry list kept live (not just the initial scan's); instead this
     * mirrors the mock's own documented stance (cleona_voice_mock.c,
     * cleona_voice_mock_set_routes): if the currently active route no longer
     * resolves, report ROUTE_UNKNOWN rather than guess a successor -- I7's
     * fallback choice belongs to RoutePolicy in Dart, not to this backend. */
    pthread_mutex_lock(&s->lock);
    if (s->running) {
        s->route_out = CLEONA_VOICE_ROUTE_UNKNOWN;
        s->route_in  = CLEONA_VOICE_ROUTE_UNKNOWN;
        cvl_push_event_locked(s, CLEONA_VOICE_EV_ROUTES_CHANGED, s->routes_mask);
        pthread_cond_broadcast(&s->cond);
    }
    pthread_mutex_unlock(&s->lock);
}

static const struct pw_registry_events cvl_registry_events = {
    PW_VERSION_REGISTRY_EVENTS,
    .global = cvl_registry_global,
    .global_remove = cvl_registry_global_remove,
};

/* ==========================================================================
 * pw_core sync -- used to make the initial registry scan and the module-load
 * handshake deterministic instead of "pump the loop a few times and hope".
 * ========================================================================== */

struct cvl_core_wait { cleona_voice_session_t* s; int done; int pending_seq; };

static void cvl_core_done(void* data, uint32_t id, int seq) {
    struct cvl_core_wait* w = (struct cvl_core_wait*)data;
    if (id == PW_ID_CORE && seq == w->pending_seq) {
        w->done = 1;
        pthread_cond_broadcast(&w->s->cond);
    }
}

static const struct pw_core_events cvl_core_events = {
    PW_VERSION_CORE_EVENTS,
    .done = cvl_core_done,
};

/* Runs one core roundtrip so that everything queued before this call (module
 * load, registry binds) is guaranteed processed before it returns. Must be
 * called with the thread loop UNLOCKED (it locks internally, matching every
 * other public-ish helper in this file). Returns 0 on success, -1 on timeout. */
static int cvl_core_roundtrip(cleona_voice_session_t* s, int timeout_sec) {
    struct spa_hook core_listener;
    struct cvl_core_wait w = { .s = s, .done = 0 };

    pw_thread_loop_lock(s->loop);
    spa_zero(core_listener);
    pw_core_add_listener(s->core, &core_listener, &cvl_core_events, &w);
    w.pending_seq = pw_core_sync(s->core, PW_ID_CORE, 0);

    int64_t deadline = cvl_now_ms() + (int64_t)timeout_sec * 1000;
    while (!w.done && cvl_now_ms() < deadline) {
        pw_thread_loop_timed_wait(s->loop, 1);
    }
    spa_hook_remove(&core_listener);
    pw_thread_loop_unlock(s->loop);
    return w.done ? 0 : -1;
}

/* ==========================================================================
 * Format negotiation
 * ========================================================================== */

static const struct spa_pod* cvl_build_format_param(struct spa_pod_builder* b,
                                                     int32_t preferred_rate) {
    struct spa_pod_frame f;
    spa_pod_builder_push_object(b, &f, SPA_TYPE_OBJECT_Format, SPA_PARAM_EnumFormat);
    spa_pod_builder_add(b,
        SPA_FORMAT_mediaType,      SPA_POD_Id(SPA_MEDIA_TYPE_audio),
        SPA_FORMAT_mediaSubtype,   SPA_POD_Id(SPA_MEDIA_SUBTYPE_raw),
        SPA_FORMAT_AUDIO_format,   SPA_POD_Id(SPA_AUDIO_FORMAT_S16),
        SPA_FORMAT_AUDIO_channels, SPA_POD_Int(1),
        SPA_FORMAT_AUDIO_rate,     SPA_POD_CHOICE_RANGE_Int(preferred_rate,
                                       CLEONA_VOICE_RATE_MIN, CLEONA_VOICE_RATE_MAX),
        0);
    return spa_pod_builder_pop(b, &f);
}

/* ==========================================================================
 * Capture stream events
 * ========================================================================== */

static void cvl_capture_param_changed(void* data, uint32_t id, const struct spa_pod* param) {
    cleona_voice_session_t* s = (cleona_voice_session_t*)data;
    if (id != SPA_PARAM_Format || param == NULL) return;

    struct spa_audio_info_raw info;
    spa_zero(info);
    if (spa_format_audio_raw_parse(param, &info) < 0) return;
    if (info.format != SPA_AUDIO_FORMAT_S16 || info.channels != 1) return;
    if ((int32_t)info.rate < CLEONA_VOICE_RATE_MIN || (int32_t)info.rate > CLEONA_VOICE_RATE_MAX)
        return;

    pthread_mutex_lock(&s->lock);
    cleona_voice_format_t negotiated;
    cvl_format_from_rate(&negotiated, (int32_t)info.rate);
    if (s->fmt.sample_rate == 0) {
        s->fmt = negotiated;   /* capture is the format authority (I3) */
    } else if (s->fmt.sample_rate != negotiated.sample_rate) {
        /* The two ends of the duplex session disagree -- I2 cannot hold.
         * Recorded as a hard open failure rather than silently running two
         * clocks, the exact defect this whole rewrite exists to remove. */
        s->open_error = CLEONA_VOICE_ERR_BACKEND;
    }
    s->fmt_ready = 1;
    pthread_cond_broadcast(&s->cond);
    pthread_mutex_unlock(&s->lock);
}

static void cvl_capture_process(void* data) {
    cleona_voice_session_t* s = (cleona_voice_session_t*)data;
    struct pw_buffer* b = pw_stream_dequeue_buffer(s->capture);
    if (!b) return;

    struct spa_buffer* buf = b->buffer;
    if (buf->datas[0].data == NULL) { pw_stream_queue_buffer(s->capture, b); return; }

    int32_t n_samples = (int32_t)(buf->datas[0].chunk->size / sizeof(int16_t));
    const int16_t* src = (const int16_t*)((uint8_t*)buf->datas[0].data +
                                          buf->datas[0].chunk->offset);

    pthread_mutex_lock(&s->lock);
    int32_t cap = (int32_t)(sizeof(s->cap_accum) / sizeof(s->cap_accum[0]));
    if (n_samples > 0) {
        if (s->cap_accum_len + n_samples > cap) {
            /* Consumer (capture_read) isn't keeping up. Drop this chunk and
             * count it -- silently overwriting is how the superseded far-end
             * ring produced a reference that jumped by 20 ms (architecture
             * §10.4, superseded-stack defect #1). */
            s->overruns++;
        } else if (s->mic_muted) {
            /* I6: the stream stays open and on cadence, only the content is
             * zeroed. The real samples are discarded here, not upstream, so
             * capture_read() never has to know mute happened. */
            memset(s->cap_accum + s->cap_accum_len, 0, (size_t)n_samples * sizeof(int16_t));
            s->cap_accum_len += n_samples;
        } else {
            memcpy(s->cap_accum + s->cap_accum_len, src, (size_t)n_samples * sizeof(int16_t));
            s->cap_accum_len += n_samples;
        }
        pthread_cond_broadcast(&s->cond);
    }
    pthread_mutex_unlock(&s->lock);

    pw_stream_queue_buffer(s->capture, b);
}

static const struct pw_stream_events cvl_capture_events = {
    PW_VERSION_STREAM_EVENTS,
    .param_changed = cvl_capture_param_changed,
    .process = cvl_capture_process,
};

/* ==========================================================================
 * Playback stream events
 * ========================================================================== */

static void cvl_playback_param_changed(void* data, uint32_t id, const struct spa_pod* param) {
    cleona_voice_session_t* s = (cleona_voice_session_t*)data;
    if (id != SPA_PARAM_Format || param == NULL) return;

    struct spa_audio_info_raw info;
    spa_zero(info);
    if (spa_format_audio_raw_parse(param, &info) < 0) return;
    if (info.format != SPA_AUDIO_FORMAT_S16 || info.channels != 1) return;

    pthread_mutex_lock(&s->lock);
    if (s->fmt.sample_rate != 0 && s->fmt.sample_rate != (int32_t)info.rate) {
        s->open_error = CLEONA_VOICE_ERR_BACKEND;   /* see capture's comment -- I2 */
    }
    pthread_cond_broadcast(&s->cond);
    pthread_mutex_unlock(&s->lock);
}

static void cvl_playback_process(void* data) {
    cleona_voice_session_t* s = (cleona_voice_session_t*)data;
    struct pw_buffer* b = pw_stream_dequeue_buffer(s->playback);
    if (!b) return;

    struct spa_buffer* buf = b->buffer;
    struct spa_data* d = &buf->datas[0];
    if (d->data == NULL) { pw_stream_queue_buffer(s->playback, b); return; }

    uint32_t want_samples = (uint32_t)(d->maxsize / sizeof(int16_t));
    if (b->requested > 0 && b->requested < want_samples) want_samples = (uint32_t)b->requested;

    int16_t* dst = (int16_t*)d->data;

    pthread_mutex_lock(&s->lock);
    uint32_t avail = (uint32_t)s->pb_ring_len;
    uint32_t take = avail < want_samples ? avail : want_samples;
    uint32_t cap = (uint32_t)(sizeof(s->pb_ring) / sizeof(s->pb_ring[0]));

    if (s->output_muted) {
        /* I6: the ring is still drained (so it never backs up into a
         * re-enable burst -- architecture §10.4's critique of the superseded
         * _drainJitterBuffer early-return) but the device gets silence. */
        memset(dst, 0, (size_t)take * sizeof(int16_t));
    } else {
        for (uint32_t i = 0; i < take; i++) {
            dst[i] = s->pb_ring[(s->pb_ring_head + i) % cap];
        }
    }
    if (take < want_samples) {
        memset(dst + take, 0, (size_t)(want_samples - take) * sizeof(int16_t));
        s->underruns++;
    }
    s->pb_ring_head = (uint32_t)(s->pb_ring_head + take) % cap;
    s->pb_ring_len -= (int32_t)take;
    pthread_mutex_unlock(&s->lock);

    d->chunk->offset = 0;
    d->chunk->stride = (int32_t)sizeof(int16_t);
    d->chunk->size   = want_samples * (uint32_t)sizeof(int16_t);

    pw_stream_queue_buffer(s->playback, b);
}

static const struct pw_stream_events cvl_playback_events = {
    PW_VERSION_STREAM_EVENTS,
    .param_changed = cvl_playback_param_changed,
    .process = cvl_playback_process,
};

/* ==========================================================================
 * open() -- module load, stream creation, format negotiation
 * ========================================================================== */

/* Builds the pw_context_load_module() args for one of the two chains. See the
 * file doc for why both go through the same module. `lib` is the SPA AEC
 * plugin name ("aec/libspa-aec-webrtc" or "aec/libspa-aec-null"); when it is
 * the webrtc plugin, aec.args additionally requests NS/AGC/HPF explicitly
 * (verified in the exploratory session to be accepted without error by this
 * module version) -- not because that request is trusted as a report value
 * (it isn't, see the file doc), but because leaving it unset would silently
 * depend on whatever this plugin's own default happens to be. */
static void cvl_build_module_args(char* out, size_t out_cap, const char* lib,
                                  const char* prefix) {
    int has_webrtc_extras = (strstr(lib, "webrtc") != NULL);
    snprintf(out, out_cap,
        "{ "
        "  library.name = %s "
        "%s"
        "  capture.props = { node.name = \"%s-hwcap\" media.role = Communication } "
        "  sink.props = { node.name = \"%s-sink\" node.description = \"Cleona Voice Sink\" } "
        "  source.props = { node.name = \"%s-source\" node.description = \"Cleona Voice Source\" } "
        "  playback.props = { node.name = \"%s-hwplay\" media.role = Communication } "
        "}",
        lib,
        has_webrtc_extras
            ? "  aec.args = \"{ webrtc.noise_suppression=true webrtc.gain_control=true "
              "webrtc.high_pass_filter=true }\" "
            : "",
        prefix, prefix, prefix, prefix);
}

static struct pw_stream* cvl_make_stream(cleona_voice_session_t* s,
                                         enum pw_direction dir,
                                         const char* target,
                                         int32_t preferred_rate,
                                         const struct pw_stream_events* events,
                                         struct spa_hook* listener) {
    struct pw_properties* props = pw_properties_new(
        PW_KEY_MEDIA_TYPE, "Audio",
        PW_KEY_MEDIA_CATEGORY, dir == PW_DIRECTION_INPUT ? "Capture" : "Playback",
        PW_KEY_MEDIA_ROLE, "Communication",
        PW_KEY_TARGET_OBJECT, target,
        PW_KEY_NODE_NAME, dir == PW_DIRECTION_INPUT ? "cleona-voice-capture"
                                                     : "cleona-voice-playback",
        NULL);

    struct pw_stream* stream = pw_stream_new(s->core,
        dir == PW_DIRECTION_INPUT ? "cleona-voice-capture" : "cleona-voice-playback",
        props);
    if (!stream) return NULL;

    pw_stream_add_listener(stream, listener, events, s);

    /* If capture already negotiated a rate (this is the playback stream being
     * connected second), prefer exactly that rate rather than the original
     * hint -- the two ends disagreeing is treated as an open() failure in
     * cvl_capture_param_changed()/cvl_playback_param_changed() (I2), so it is
     * worth biasing the proposal towards agreement instead of just hoping. */
    int32_t rate_pref = s->fmt.sample_rate != 0 ? s->fmt.sample_rate : preferred_rate;

    uint8_t buffer[512];
    struct spa_pod_builder b = SPA_POD_BUILDER_INIT(buffer, sizeof(buffer));
    const struct spa_pod* params[1];
    params[0] = cvl_build_format_param(&b, rate_pref);

    int flags = PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS | PW_STREAM_FLAG_RT_PROCESS;
    if (pw_stream_connect(stream, dir, PW_ID_ANY, (enum pw_stream_flags)flags,
                          params, 1) < 0) {
        pw_stream_destroy(stream);
        return NULL;
    }
    return stream;
}

CLEONA_VOICE_API cleona_voice_session_t* cleona_voice_open(
    int32_t rate_hint, cleona_voice_format_t* out_format) {

    if (!out_format) return NULL;

    pthread_mutex_lock(&g_session_guard);
    if (g_session_active) {
        pthread_mutex_unlock(&g_session_guard);
        /* SPEC §6 N3 / cleona_voice.h I3 note: a single-session backend
         * refusing a second concurrent open() is a documented, tolerated
         * answer, not a conformance failure. */
        out_format->sample_rate = CLEONA_VOICE_ERR_BACKEND;
        out_format->channels = out_format->frame_samples = out_format->frame_bytes = 0;
        return NULL;
    }
    g_session_active = 1;
    uint32_t seq = ++g_open_seq;
    pthread_mutex_unlock(&g_session_guard);

    cleona_voice_session_t* s = (cleona_voice_session_t*)calloc(1, sizeof(*s));
    if (!s) {
        /* fail_backend dereferences s -- calloc failing means there is no s
         * to clean up, so this jumps past it, but the in-band error contract
         * (cleona_voice.h: "the backend writes a negative CLEONA_VOICE_ERR_*
         * into out_format->sample_rate") still has to hold even here. */
        out_format->sample_rate = CLEONA_VOICE_ERR_BACKEND;
        out_format->channels = out_format->frame_samples = out_format->frame_bytes = 0;
        goto fail_no_session;
    }

    pthread_mutex_init(&s->lock, NULL);
    pthread_cond_init(&s->cond, NULL);
    snprintf(s->node_prefix, sizeof(s->node_prefix), "cleona-voice-%d-%u",
            (int)getpid(), seq);

    int32_t preferred_rate = (rate_hint >= CLEONA_VOICE_RATE_MIN &&
                              rate_hint <= CLEONA_VOICE_RATE_MAX)
                            ? rate_hint : 48000;

    pw_init(NULL, NULL);
    s->loop = pw_thread_loop_new("cleona-voice", NULL);
    if (!s->loop) goto fail_backend;
    s->context = pw_context_new(pw_thread_loop_get_loop(s->loop), NULL, 0);
    if (!s->context) goto fail_backend;

    if (pw_thread_loop_start(s->loop) < 0) goto fail_backend;

    pw_thread_loop_lock(s->loop);
    s->core = pw_context_connect(s->context, NULL, 0);
    pw_thread_loop_unlock(s->loop);
    if (!s->core) goto fail_backend;

    /* --- module load: preferred chain, then the explicit-passthrough
     * fallback. See file doc for why both share the same module. ---
     *
     * CLEONA_VOICE_LINUX_FORCE_APM is a TEST-ONLY escape hatch, not a
     * production tuning knob: it exists because a dev machine that has the
     * AEC3 plugin installed (the common case, and true of the machine this
     * backend was verified on) has no other way to exercise the LINKED_APM
     * chain at all, and SPEC §7 (V1.1) requires this backend's acceptance
     * report to show BOTH chains actually running, not just the one that
     * happened to be available. It skips straight to the null-passthrough
     * module load below; it does not change what either chain does. */
    char args[768];
    pw_thread_loop_lock(s->loop);
    if (getenv("CLEONA_VOICE_LINUX_FORCE_APM")) {
        s->ec_module = NULL;
    } else {
        cvl_build_module_args(args, sizeof(args), "aec/libspa-aec-webrtc", s->node_prefix);
        s->ec_module = pw_context_load_module(s->context, "libpipewire-module-echo-cancel",
                                              args, NULL);
    }
    if (s->ec_module) {
        s->chain_origin = CLEONA_VOICE_CHAIN_PIPEWIRE_FILTER;
    } else {
        cvl_build_module_args(args, sizeof(args), "aec/libspa-aec-null", s->node_prefix);
        s->ec_module = pw_context_load_module(s->context, "libpipewire-module-echo-cancel",
                                              args, NULL);
        s->chain_origin = CLEONA_VOICE_CHAIN_LINKED_APM;
    }
    pw_thread_loop_unlock(s->loop);

    if (!s->ec_module) {
        /* Neither the AEC3 plugin nor the null passthrough could be loaded --
         * the module binary itself, or PipeWire's module search path, is
         * missing. Not a case this file papers over (file doc, "THE TWO
         * CHAINS"): open() fails rather than falling back to a two-clock
         * direct connection. */
        s->open_error = CLEONA_VOICE_ERR_BACKEND;
        goto fail_backend;
    }

    /* Let the module's own nodes register before we try to target them by
     * name (PW_KEY_TARGET_OBJECT resolves against the registry at connect
     * time; without this roundtrip the target may not exist yet). */
    if (cvl_core_roundtrip(s, 5) != 0) {
        s->open_error = CLEONA_VOICE_ERR_BACKEND;
        goto fail_backend;
    }

    char source_target[64], sink_target[64];
    snprintf(source_target, sizeof(source_target), "%s-source", s->node_prefix);
    snprintf(sink_target, sizeof(sink_target), "%s-sink", s->node_prefix);

    pw_thread_loop_lock(s->loop);
    s->capture = cvl_make_stream(s, PW_DIRECTION_INPUT, source_target, preferred_rate,
                                 &cvl_capture_events, &s->capture_listener);
    pw_thread_loop_unlock(s->loop);
    if (!s->capture) { s->open_error = CLEONA_VOICE_ERR_NO_DEVICE; goto fail_backend; }

    pw_thread_loop_lock(s->loop);
    s->playback = cvl_make_stream(s, PW_DIRECTION_OUTPUT, sink_target, preferred_rate,
                                  &cvl_playback_events, &s->playback_listener);
    pw_thread_loop_unlock(s->loop);
    if (!s->playback) { s->open_error = CLEONA_VOICE_ERR_NO_DEVICE; goto fail_backend; }

    /* Wait for both ends to negotiate a format (I2/I3). */
    pw_thread_loop_lock(s->loop);
    int64_t deadline = cvl_now_ms() + 5000;
    while (!s->fmt_ready && !s->open_error && cvl_now_ms() < deadline) {
        pw_thread_loop_timed_wait(s->loop, 1);
    }
    pw_thread_loop_unlock(s->loop);

    if (s->open_error) goto fail_backend;
    if (!s->fmt_ready || s->fmt.sample_rate == 0) {
        s->open_error = CLEONA_VOICE_ERR_BACKEND;
        goto fail_backend;
    }

    if (s->chain_origin == CLEONA_VOICE_CHAIN_LINKED_APM) {
        s->apm = cleona_voice_apm_create(s->fmt.sample_rate);
        if (!s->apm) {
            /* The rate PipeWire negotiated isn't one of APM's native rates.
             * Rather than resample (a whole new correctness surface) this
             * file fails open() honestly. */
            s->open_error = CLEONA_VOICE_ERR_BACKEND;
            goto fail_backend;
        }
        s->aec_state = cleona_voice_apm_aec_enabled(s->apm)
                     ? CLEONA_VOICE_FX_ENABLED : CLEONA_VOICE_FX_AVAILABLE_OFF;
        s->ns_state  = cleona_voice_apm_ns_enabled(s->apm)
                     ? CLEONA_VOICE_FX_ENABLED : CLEONA_VOICE_FX_AVAILABLE_OFF;
        s->agc_state = cleona_voice_apm_agc_enabled(s->apm)
                     ? CLEONA_VOICE_FX_ENABLED : CLEONA_VOICE_FX_AVAILABLE_OFF;
    } else {
        /* PIPEWIRE_FILTER: no client-visible readback exists -- see file doc. */
        s->aec_state = CLEONA_VOICE_FX_UNKNOWN;
        s->ns_state  = CLEONA_VOICE_FX_UNKNOWN;
        s->agc_state = CLEONA_VOICE_FX_UNKNOWN;
    }

    /* Route enumeration -- see the registry section. */
    pw_thread_loop_lock(s->loop);
    s->registry = pw_core_get_registry(s->core, PW_VERSION_REGISTRY, 0);
    spa_zero(s->registry_listener);
    pw_registry_add_listener(s->registry, &s->registry_listener, &cvl_registry_events, s);
    pw_thread_loop_unlock(s->loop);
    cvl_core_roundtrip(s, 3);   /* let the initial Audio/Sink globals arrive */

    pthread_mutex_lock(&s->lock);
    if (s->routes_mask == 0) s->routes_mask = CLEONA_VOICE_ROUTE_BIT(CLEONA_VOICE_ROUTE_SPEAKER);
    /* Desktop model (§10.4): SPEAKER is the always-present fallback identity
     * when no bus-specific route was found -- never left at ROUTE_UNKNOWN,
     * which would fail SPEC §6 check 8 the moment start() runs. */
    if (s->routes_mask & CLEONA_VOICE_ROUTE_BIT(CLEONA_VOICE_ROUTE_SPEAKER)) {
        s->route_out = CLEONA_VOICE_ROUTE_SPEAKER;
    } else {
        for (int32_t r = CLEONA_VOICE_ROUTE_EARPIECE; r <= CLEONA_VOICE_ROUTE_BLUETOOTH; r++) {
            if (s->routes_mask & CLEONA_VOICE_ROUTE_BIT(r)) { s->route_out = r; break; }
        }
    }
    s->route_in = s->route_out;
    pthread_mutex_unlock(&s->lock);

    *out_format = s->fmt;
    return s;

fail_backend:
    if (s->capture)  { pw_thread_loop_lock(s->loop); pw_stream_destroy(s->capture); pw_thread_loop_unlock(s->loop); }
    if (s->playback) { pw_thread_loop_lock(s->loop); pw_stream_destroy(s->playback); pw_thread_loop_unlock(s->loop); }
    if (s->ec_module) { pw_thread_loop_lock(s->loop); pw_impl_module_destroy(s->ec_module); pw_thread_loop_unlock(s->loop); }
    if (s->core)    { pw_thread_loop_lock(s->loop); pw_core_disconnect(s->core); pw_thread_loop_unlock(s->loop); }
    if (s->loop)    { pw_thread_loop_stop(s->loop); }
    if (s->context) pw_context_destroy(s->context);
    if (s->loop)    pw_thread_loop_destroy(s->loop);
    {
        int32_t err = s->open_error ? s->open_error : CLEONA_VOICE_ERR_BACKEND;
        pthread_mutex_destroy(&s->lock);
        pthread_cond_destroy(&s->cond);
        free(s);
        out_format->sample_rate = err;
        out_format->channels = out_format->frame_samples = out_format->frame_bytes = 0;
    }
fail_no_session:
    pthread_mutex_lock(&g_session_guard);
    g_session_active = 0;
    pthread_mutex_unlock(&g_session_guard);
    return NULL;
}

/* ==========================================================================
 * start() / stop() / close()
 * ========================================================================== */

CLEONA_VOICE_API int32_t cleona_voice_start(cleona_voice_session_t* s) {
    if (!s) return CLEONA_VOICE_ERR_CLOSED;

    pthread_mutex_lock(&s->lock);
    if (s->running) { pthread_mutex_unlock(&s->lock); return CLEONA_VOICE_ERR_ALREADY_STARTED; }
    s->running = 1;
    s->cap_accum_len = 0;
    s->pb_ring_head = 0;
    s->pb_ring_len = 0;
    pthread_mutex_unlock(&s->lock);
    return CLEONA_VOICE_OK;
}

CLEONA_VOICE_API void cleona_voice_stop(cleona_voice_session_t* s) {
    if (!s) return;
    pthread_mutex_lock(&s->lock);
    s->running = 0;
    pthread_cond_broadcast(&s->cond);
    pthread_mutex_unlock(&s->lock);
}

CLEONA_VOICE_API void cleona_voice_close(cleona_voice_session_t* s) {
    if (!s) return;
    cleona_voice_stop(s);

    pw_thread_loop_lock(s->loop);
    if (s->capture)  pw_stream_destroy(s->capture);
    if (s->playback) pw_stream_destroy(s->playback);
    if (s->registry) pw_proxy_destroy((struct pw_proxy*)s->registry);
    if (s->ec_module) pw_impl_module_destroy(s->ec_module);
    if (s->core) pw_core_disconnect(s->core);
    pw_thread_loop_unlock(s->loop);

    pw_thread_loop_stop(s->loop);
    pw_context_destroy(s->context);
    pw_thread_loop_destroy(s->loop);
    pw_deinit();

    if (s->apm) cleona_voice_apm_destroy(s->apm);

    pthread_mutex_destroy(&s->lock);
    pthread_cond_destroy(&s->cond);
    free(s);

    pthread_mutex_lock(&g_session_guard);
    g_session_active = 0;
    pthread_mutex_unlock(&g_session_guard);
}

/* ==========================================================================
 * Data path
 * ========================================================================== */

/* Runs the LINKED_APM chain over one 20 ms frame already extracted from
 * cap_accum, in place. Splits into two 10 ms halves (APM's native unit) and,
 * for each half, feeds the matching render-reference half first so the
 * cancellor has something to cancel against -- see voice_apm_shim.h for what
 * "matching" does and does not guarantee here (no delay estimation beyond
 * APM's own internal handling; documented, not hidden). Never fails the read:
 * an APM error degrades to "pass the samples through uncancelled" rather than
 * losing the frame, because a missed capture frame would itself violate I4. */
static void cvl_apply_apm_capture(cleona_voice_session_t* s, int16_t* frame,
                                  int32_t frame_samples) {
    int32_t half = frame_samples / 2;
    if (half <= 0) return;

    for (int32_t part = 0; part < 2; part++) {
        int16_t ref[CVL_MAX_FRAME_SAMPLES / 2];
        pthread_mutex_lock(&s->lock);
        int32_t avail = s->render_len < half ? s->render_len : half;
        if (avail > 0) {
            memcpy(ref, s->render_ring, (size_t)avail * sizeof(int16_t));
            memmove(s->render_ring, s->render_ring + avail,
                    (size_t)(s->render_len - avail) * sizeof(int16_t));
            s->render_len -= avail;
        }
        pthread_mutex_unlock(&s->lock);
        if (avail < half) memset(ref + avail, 0, (size_t)(half - avail) * sizeof(int16_t));

        cleona_voice_apm_process_render(s->apm, ref, half);
        cleona_voice_apm_process_capture(s->apm, frame + part * half, half);
    }
}

CLEONA_VOICE_API int32_t cleona_voice_capture_read(cleona_voice_session_t* s,
                                                   int16_t* out,
                                                   int32_t timeout_ms) {
    if (!s || !out) return CLEONA_VOICE_CAPTURE_CLOSED;
    if (timeout_ms < 0) timeout_ms = 0;

    int64_t deadline = cvl_now_ms() + timeout_ms;

    pthread_mutex_lock(&s->lock);
    for (;;) {
        if (!s->running) { pthread_mutex_unlock(&s->lock); return CLEONA_VOICE_CAPTURE_CLOSED; }
        if (s->cap_accum_len >= s->fmt.frame_samples) {
            memcpy(out, s->cap_accum, (size_t)s->fmt.frame_bytes);
            s->cap_accum_len -= s->fmt.frame_samples;
            if (s->cap_accum_len > 0) {
                memmove(s->cap_accum, s->cap_accum + s->fmt.frame_samples,
                        (size_t)s->cap_accum_len * sizeof(int16_t));
            }
            break;
        }
        int64_t now = cvl_now_ms();
        if (now >= deadline) { pthread_mutex_unlock(&s->lock); return CLEONA_VOICE_CAPTURE_TIMEOUT; }
        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &ts);
        int64_t wait_ms = deadline - now;
        if (wait_ms > 50) wait_ms = 50;   /* re-check s->running periodically */
        ts.tv_sec  += wait_ms / 1000;
        ts.tv_nsec += (wait_ms % 1000) * 1000000L;
        if (ts.tv_nsec >= 1000000000L) { ts.tv_sec++; ts.tv_nsec -= 1000000000L; }
        pthread_cond_timedwait(&s->cond, &s->lock, &ts);
    }
    pthread_mutex_unlock(&s->lock);

    if (s->chain_origin == CLEONA_VOICE_CHAIN_LINKED_APM && s->apm) {
        cvl_apply_apm_capture(s, out, s->fmt.frame_samples);
    }
    return CLEONA_VOICE_CAPTURE_FRAME;
}

CLEONA_VOICE_API int32_t cleona_voice_playback_write(cleona_voice_session_t* s,
                                                     const int16_t* pcm,
                                                     int32_t frame_samples) {
    if (!s)   return CLEONA_VOICE_ERR_CLOSED;
    if (!pcm) return CLEONA_VOICE_ERR_INVALID_ARG;

    pthread_mutex_lock(&s->lock);
    if (!s->running) { pthread_mutex_unlock(&s->lock); return CLEONA_VOICE_ERR_NOT_STARTED; }
    if (frame_samples != s->fmt.frame_samples) {
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VOICE_ERR_FRAME_SIZE;
    }

    uint32_t cap = (uint32_t)(sizeof(s->pb_ring) / sizeof(s->pb_ring[0]));
    if ((uint32_t)s->pb_ring_len + (uint32_t)frame_samples > cap) {
        /* Never blocks (I5) -- the caller is producing faster than the device
         * consumes. Drop and count rather than wait. */
        s->overruns++;
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VOICE_OK;
    }
    uint32_t tail = (uint32_t)((s->pb_ring_head + s->pb_ring_len) % (int32_t)cap);
    for (int32_t i = 0; i < frame_samples; i++) {
        s->pb_ring[(tail + (uint32_t)i) % cap] = pcm[i];
    }
    s->pb_ring_len += frame_samples;

    if (s->chain_origin == CLEONA_VOICE_CHAIN_LINKED_APM) {
        int32_t rcap = (int32_t)(sizeof(s->render_ring) / sizeof(s->render_ring[0]));
        if (s->render_len + frame_samples <= rcap) {
            memcpy(s->render_ring + s->render_len, pcm, (size_t)frame_samples * sizeof(int16_t));
            s->render_len += frame_samples;
        }
        /* If the render ring is full, the reference is simply not extended --
         * cvl_apply_apm_capture() already degrades gracefully to zeros when
         * starved, so this is a quality loss, never a correctness one. */
    }
    pthread_mutex_unlock(&s->lock);
    return CLEONA_VOICE_OK;
}

/* ==========================================================================
 * Controls
 * ========================================================================== */

CLEONA_VOICE_API void cleona_voice_set_mic_muted(cleona_voice_session_t* s, int32_t muted) {
    if (!s) return;
    pthread_mutex_lock(&s->lock);
    s->mic_muted = muted ? 1 : 0;
    pthread_mutex_unlock(&s->lock);
}

CLEONA_VOICE_API void cleona_voice_set_output_muted(cleona_voice_session_t* s, int32_t muted) {
    if (!s) return;
    pthread_mutex_lock(&s->lock);
    s->output_muted = muted ? 1 : 0;
    pthread_mutex_unlock(&s->lock);
}

CLEONA_VOICE_API int32_t cleona_voice_set_route(cleona_voice_session_t* s, int32_t route) {
    if (!s) return CLEONA_VOICE_ERR_CLOSED;
    if (route <= CLEONA_VOICE_ROUTE_UNKNOWN || route > CLEONA_VOICE_ROUTE_BLUETOOTH)
        return CLEONA_VOICE_ERR_INVALID_ARG;

    pthread_mutex_lock(&s->lock);
    if (!(s->routes_mask & CLEONA_VOICE_ROUTE_BIT(route))) {
        pthread_mutex_unlock(&s->lock);
        /* ROUTE_EARPIECE on a desktop lands here -- exactly the defined
         * failure cleona_voice.h documents for platforms with no earpiece. */
        return CLEONA_VOICE_ERR_ROUTE_UNAVAILABLE;
    }
    if (route == s->route_out) {
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VOICE_OK;   /* already there */
    }
    pthread_mutex_unlock(&s->lock);
    /* V1.1 does not implement live output-device reassignment (it would need
     * to move the module's internal playback substream to a different sink,
     * which PipeWire only supports via a full reconnect -- rule 4 in
     * route_policy.dart forbids exactly that teardown). Declining is a
     * legitimate, ABI-defined answer (SPEC §6 "S9": "backend declined the
     * route switch ... legitimate answer and is recorded, not failed"). */
    return CLEONA_VOICE_ERR_ROUTE_UNSUPPORTED;
}

CLEONA_VOICE_API int32_t cleona_voice_get_routes(cleona_voice_session_t* s,
                                                 int32_t* out_mask, int32_t* out_active) {
    if (!s) return CLEONA_VOICE_ERR_CLOSED;
    if (!out_mask || !out_active) return CLEONA_VOICE_ERR_INVALID_ARG;
    pthread_mutex_lock(&s->lock);
    *out_mask = s->routes_mask;
    *out_active = s->route_out;
    pthread_mutex_unlock(&s->lock);
    return CLEONA_VOICE_OK;
}

/* ==========================================================================
 * Events
 * ========================================================================== */

CLEONA_VOICE_API int32_t cleona_voice_poll_event(cleona_voice_session_t* s,
                                                 int32_t* out_event, int32_t* out_arg) {
    if (!s) return CLEONA_VOICE_ERR_CLOSED;
    if (!out_event || !out_arg) return CLEONA_VOICE_ERR_INVALID_ARG;

    pthread_mutex_lock(&s->lock);
    if (s->ev_count == 0) {
        *out_event = CLEONA_VOICE_EV_NONE;
        *out_arg = 0;
    } else {
        *out_event = s->ev_type[s->ev_head];
        *out_arg   = s->ev_arg[s->ev_head];
        s->ev_head = (s->ev_head + 1) % CVL_EVENT_QUEUE;
        s->ev_count--;
    }
    pthread_mutex_unlock(&s->lock);
    return CLEONA_VOICE_OK;
}

/* ==========================================================================
 * Report (I11)
 * ========================================================================== */

CLEONA_VOICE_API void cleona_voice_get_report(cleona_voice_session_t* s,
                                              cleona_voice_report_t* out) {
    if (!out) return;
    memset(out, 0, sizeof(*out));
    if (!s) return;

    pthread_mutex_lock(&s->lock);
    out->format       = s->fmt;
    out->aec_state    = s->aec_state;
    out->ns_state     = s->ns_state;
    out->agc_state    = s->agc_state;
    out->chain_origin = s->chain_origin;
    out->backend      = CLEONA_VOICE_BACKEND_PIPEWIRE;
    out->duplex       = 1;   /* I2: one module instance, one correlated pair, always */
    out->route_active_in  = s->route_in;
    out->route_active_out = s->route_out;
    out->routes_available_mask = s->routes_mask;
    /* Erratum E6a: a plain observation of the state last set through
     * set_mic_muted() / set_output_muted(), never derived from the stream.
     * Both fields are already normalised to exactly 0 or 1 at the setter
     * (see cleona_voice_set_mic_muted), so no second normalisation here —
     * one place that decides, one place to get it wrong. Muted is not a
     * defect: I6 requires the stream to stay open, and C5/C5b prove it does. */
    out->mic_muted    = s->mic_muted;
    out->output_muted = s->output_muted;
    out->underruns = s->underruns;
    out->overruns  = s->overruns;
    pthread_mutex_unlock(&s->lock);
}
