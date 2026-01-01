/* cleona_voice_mock.c — hardware-free backend for cleona_voice.h.
 *
 * Work package: docs/SPEC_VOICE_VIDEO_REWORK.md §5 (V0.2).
 * Architecture:  Cleona_Chat_Architecture_v3_0.md §10.4.
 *
 * This is a real implementation of the ABI, not a stub. It exists so that
 * V1.5-V1.9, V1.12 and the whole UI can be built and tested before any
 * platform backend exists. That is only worth anything if the mock ENFORCES
 * the invariants rather than claiming them:
 *
 *   I2  one session owns both directions; duplex is reported as 1 and there is
 *       exactly one clock in the file — the synthetic device clock.
 *   I3  the sample rate is negotiated at open() and reported back. The mock
 *       can be configured to ignore rate_hint entirely, which is the case a
 *       caller most easily gets wrong.
 *   I4  the synthetic device produces chunks of VARYING size. Full frames are
 *       produced by internal buffering, exactly as a real platform layer must.
 *       No caller can ever observe a short frame, and no chunk is ever
 *       discarded for having the "wrong" size — which is defect #7 of the
 *       superseded stack (cleona_audio.c:151, :202).
 *   I5  there is no timer here. Frames become available because the device
 *       clock advanced; capture_read waits for that, playback_write returns
 *       immediately.
 *   I6  mic mute zeroes samples at generation time and keeps the cadence;
 *       output mute keeps accepting writes. Neither stops a stream, neither is
 *       reset by a route change (§10.4), and since erratum E6a both are visible
 *       in the report so that those two sentences can be checked instead of
 *       believed.
 *   I11 the default report contains an FX_UNKNOWN and never impersonates a
 *       real chain (CHAIN_MOCK / BACKEND_MOCK, both >= 100).
 *
 * Deliberately NOT modelled: an echo path. The mock has no acoustic model, so
 * it can say nothing about AEC quality — and it must not pretend otherwise.
 * Its report describes a fictional chain and is labelled as such.
 */

#include "cleona_voice_mock.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
  #define WIN32_LEAN_AND_MEAN
  #include <windows.h>
#else
  #include <pthread.h>
  #include <time.h>
  #include <errno.h>
#endif

#ifndef M_PI
  #define M_PI 3.14159265358979323846
#endif

/* ==========================================================================
 * Tiny portability layer (mutex, monotonic clock, sleep)
 * ==========================================================================
 * Small enough to keep in one file. The mock has to build wherever a platform
 * package is being developed, and pulling a threading dependency into a test
 * backend would be a poor trade. */

#if defined(_WIN32)
typedef CRITICAL_SECTION mock_mutex_t;
static void mock_mutex_init(mock_mutex_t* m)    { InitializeCriticalSection(m); }
static void mock_mutex_destroy(mock_mutex_t* m) { DeleteCriticalSection(m); }
static void mock_lock(mock_mutex_t* m)          { EnterCriticalSection(m); }
static void mock_unlock(mock_mutex_t* m)        { LeaveCriticalSection(m); }

static int64_t mock_now_ns(void) {
    static LARGE_INTEGER freq;
    LARGE_INTEGER now;
    if (freq.QuadPart == 0) QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&now);
    return (int64_t)((double)now.QuadPart * 1e9 / (double)freq.QuadPart);
}
static void mock_sleep_ms(int32_t ms) { Sleep((DWORD)(ms > 0 ? ms : 1)); }
#else
typedef pthread_mutex_t mock_mutex_t;
static void mock_mutex_init(mock_mutex_t* m)    { pthread_mutex_init(m, NULL); }
static void mock_mutex_destroy(mock_mutex_t* m) { pthread_mutex_destroy(m); }
static void mock_lock(mock_mutex_t* m)          { pthread_mutex_lock(m); }
static void mock_unlock(mock_mutex_t* m)        { pthread_mutex_unlock(m); }

static int64_t mock_now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000000000LL + (int64_t)ts.tv_nsec;
}
static void mock_sleep_ms(int32_t ms) {
    struct timespec ts;
    if (ms <= 0) ms = 1;
    ts.tv_sec  = ms / 1000;
    ts.tv_nsec = (long)(ms % 1000) * 1000000L;
    while (nanosleep(&ts, &ts) == -1 && errno == EINTR) { /* retry */ }
}
#endif

/* ==========================================================================
 * Session state
 * ========================================================================== */

#define MOCK_EVENT_QUEUE  16
/* Eight frames of headroom before the synthetic device starts counting
 * overruns. Deep enough that a caller which is briefly late does not see
 * spurious overruns, shallow enough that a caller which stopped reading
 * altogether is reported rather than buffered forever. */
#define MOCK_ACCUM_FRAMES  8

struct cleona_voice_session {
    mock_mutex_t lock;

    cleona_voice_format_t      fmt;
    cleona_voice_mock_config_t cfg;

    int32_t running;
    int32_t mic_muted;
    int32_t output_muted;

    int32_t routes_mask;
    int32_t route_in;
    int32_t route_out;

    int64_t underruns;
    int64_t overruns;

    int64_t capture_frames;
    int64_t playback_frames;
    int64_t muted_playback_frames;

    /* Synthetic device clock. samples_generated counts everything the device
     * has produced since start(); the difference to what the clock says is due
     * is what the next pump has to generate. */
    int64_t clock_origin_ns;
    int64_t samples_generated;
    double  tone_phase;
    uint32_t rng;

    /* Frame assembly buffer — the reason I4 holds. */
    int16_t* accum;
    int32_t  accum_len;
    int32_t  accum_cap;

    /* Event queue (FIFO ring). */
    int32_t ev_type[MOCK_EVENT_QUEUE];
    int32_t ev_arg[MOCK_EVENT_QUEUE];
    int32_t ev_head;
    int32_t ev_count;
};

/* ==========================================================================
 * Global pending configuration
 * ==========================================================================
 * cleona_voice_open() takes only (rate_hint, out_format) — the ABI is fixed —
 * so a test configures the next session through this global. It is copied into
 * the session at open() time; later changes do not reach a live session. */

static mock_mutex_t        g_cfg_lock;
static int                 g_cfg_lock_ready = 0;
static cleona_voice_mock_config_t g_cfg;
static int                 g_cfg_set = 0;

static void ensure_cfg_lock(void) {
    /* Not thread-safe against a first-ever concurrent open(); tests configure
     * from one thread before opening, which is the only supported use. */
    if (!g_cfg_lock_ready) {
        mock_mutex_init(&g_cfg_lock);
        g_cfg_lock_ready = 1;
    }
}

CLEONA_VOICE_MOCK_API void cleona_voice_mock_config_default(cleona_voice_mock_config_t* cfg) {
    if (!cfg) return;
    memset(cfg, 0, sizeof(*cfg));
    cfg->force_rate   = 0;
    cfg->default_rate = 48000;

    /* Three of the four effect states in one report, including the one that is
     * hardest to handle and easiest to fake (I11). A report path written only
     * for ENABLED would look correct against a happier default. */
    cfg->aec_state    = CLEONA_VOICE_FX_ENABLED;
    cfg->ns_state     = CLEONA_VOICE_FX_AVAILABLE_OFF;
    cfg->agc_state    = CLEONA_VOICE_FX_UNKNOWN;
    cfg->chain_origin = CLEONA_VOICE_CHAIN_MOCK;
    cfg->duplex       = 1;

    cfg->routes_available_mask = CLEONA_VOICE_ROUTE_BIT(CLEONA_VOICE_ROUTE_EARPIECE)
                               | CLEONA_VOICE_ROUTE_BIT(CLEONA_VOICE_ROUTE_SPEAKER)
                               | CLEONA_VOICE_ROUTE_BIT(CLEONA_VOICE_ROUTE_WIRED);
    cfg->route_active_in  = CLEONA_VOICE_ROUTE_UNKNOWN; /* resolved at start() */
    cfg->route_active_out = CLEONA_VOICE_ROUTE_EARPIECE;

    cfg->tone_hz        = 440;
    cfg->tone_amplitude = 8000;

    cfg->open_error  = 0;
    cfg->start_error = 0;

    /* Never a frame size, never a divisor of one — a test must not pass
     * because the chunking happened to line up. */
    cfg->chunk_min = 37;
    cfg->chunk_max = 311;
}

CLEONA_VOICE_MOCK_API void cleona_voice_mock_config_desktop(cleona_voice_mock_config_t* cfg) {
    if (!cfg) return;
    cleona_voice_mock_config_default(cfg);
    /* No earpiece: macOS, Windows and Linux do not have one. This is the
     * configuration in which set_route(EARPIECE) must return
     * CLEONA_VOICE_ERR_ROUTE_UNAVAILABLE instead of silently doing nothing. */
    cfg->routes_available_mask = CLEONA_VOICE_ROUTE_BIT(CLEONA_VOICE_ROUTE_SPEAKER)
                               | CLEONA_VOICE_ROUTE_BIT(CLEONA_VOICE_ROUTE_WIRED);
    cfg->route_active_out = CLEONA_VOICE_ROUTE_SPEAKER;
    cfg->chain_origin     = CLEONA_VOICE_CHAIN_MOCK;
}

CLEONA_VOICE_MOCK_API void cleona_voice_mock_set_config(const cleona_voice_mock_config_t* cfg) {
    ensure_cfg_lock();
    mock_lock(&g_cfg_lock);
    if (cfg) {
        g_cfg = *cfg;
        g_cfg_set = 1;
    } else {
        g_cfg_set = 0;
    }
    mock_unlock(&g_cfg_lock);
}

/* ==========================================================================
 * Helpers
 * ========================================================================== */

static uint32_t xorshift32(uint32_t* state) {
    uint32_t x = *state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    *state = x ? x : 0x1234567u;
    return *state;
}

static int rate_is_valid(int32_t rate) {
    return rate >= CLEONA_VOICE_RATE_MIN
        && rate <= CLEONA_VOICE_RATE_MAX
        && (rate % CLEONA_VOICE_FRAME_HZ) == 0;
}

static void format_from_rate(cleona_voice_format_t* f, int32_t rate) {
    f->sample_rate   = rate;
    f->channels      = CLEONA_VOICE_CHANNELS;
    f->frame_samples = rate / CLEONA_VOICE_FRAME_HZ;
    f->frame_bytes   = f->frame_samples * f->channels * 2;
}

static void fail_open(cleona_voice_format_t* out_format, int32_t err) {
    /* In-band failure reporting, see cleona_voice.h: a negative value in
     * sample_rate can never be mistaken for a negotiated format. */
    if (out_format) {
        out_format->sample_rate   = err;
        out_format->channels      = 0;
        out_format->frame_samples = 0;
        out_format->frame_bytes   = 0;
    }
}

/* Queues an event. Caller holds the lock. On overflow the OLDEST entry is
 * dropped, as cleona_voice.h requires — the newest route mask must survive. */
static void push_event_locked(cleona_voice_session_t* s, int32_t ev, int32_t arg) {
    if (s->ev_count == MOCK_EVENT_QUEUE) {
        s->ev_head = (s->ev_head + 1) % MOCK_EVENT_QUEUE;
        s->ev_count--;
    }
    int32_t tail = (s->ev_head + s->ev_count) % MOCK_EVENT_QUEUE;
    s->ev_type[tail] = ev;
    s->ev_arg[tail]  = arg;
    s->ev_count++;
}

/* Advances the synthetic device up to the current clock and appends the
 * produced samples to the frame-assembly buffer. Caller holds the lock.
 *
 * This is where I4 is earned: chunk sizes vary, frames do not. */
static void pump_device_locked(cleona_voice_session_t* s) {
    if (!s->running) return;

    int64_t elapsed_ns = mock_now_ns() - s->clock_origin_ns;
    if (elapsed_ns < 0) elapsed_ns = 0;

    /* Samples the device clock says should exist by now. */
    int64_t due_total = (int64_t)((double)elapsed_ns * (double)s->fmt.sample_rate / 1e9);
    int64_t todo = due_total - s->samples_generated;
    if (todo <= 0) return;

    /* After a suspend or a debugger stop the clock can jump by seconds. A real
     * device drops that backlog rather than replaying it into the call; so does
     * this one, and it counts the loss instead of hiding it. */
    int64_t max_backlog = (int64_t)s->fmt.frame_samples * MOCK_ACCUM_FRAMES;
    if (todo > max_backlog) {
        s->samples_generated += (todo - max_backlog);
        s->overruns++;
        todo = max_backlog;
    }

    const double two_pi_f_over_rate =
        2.0 * M_PI * (double)s->cfg.tone_hz / (double)s->fmt.sample_rate;
    const int muted = s->mic_muted;
    const int16_t amp = (int16_t)(s->cfg.tone_amplitude);

    while (todo > 0) {
        int32_t span = s->cfg.chunk_max - s->cfg.chunk_min + 1;
        int32_t chunk = s->cfg.chunk_min;
        if (span > 1) chunk += (int32_t)(xorshift32(&s->rng) % (uint32_t)span);
        if ((int64_t)chunk > todo) chunk = (int32_t)todo;

        if (s->accum_len + chunk > s->accum_cap) {
            /* The consumer is not reading. Drop what does not fit and count it
             * — silently overwriting is how the superseded far-end ring
             * produced a reference that jumped by 20 ms (defect #1). */
            s->overruns++;
            s->samples_generated += todo;
            return;
        }

        for (int32_t i = 0; i < chunk; i++) {
            int16_t sample = 0;
            if (!muted && s->cfg.tone_hz > 0 && amp > 0) {
                sample = (int16_t)(sin(s->tone_phase) * (double)amp);
            }
            /* The phase advances even while muted: the "device" keeps running,
             * only the signal is gone. Restarting the phase on unmute would be
             * an audible click that no real input-mute produces. */
            s->tone_phase += two_pi_f_over_rate;
            if (s->tone_phase > 2.0 * M_PI) s->tone_phase -= 2.0 * M_PI;
            s->accum[s->accum_len + i] = sample;
        }

        s->accum_len += chunk;
        s->samples_generated += chunk;
        todo -= chunk;
    }
}

/* ==========================================================================
 * Lifecycle
 * ========================================================================== */

CLEONA_VOICE_API cleona_voice_session_t* cleona_voice_open(
    int32_t rate_hint, cleona_voice_format_t* out_format) {

    if (!out_format) return NULL;   /* no channel to report anything through */

    cleona_voice_mock_config_t cfg;
    ensure_cfg_lock();
    mock_lock(&g_cfg_lock);
    if (g_cfg_set) {
        cfg = g_cfg;
    } else {
        cleona_voice_mock_config_default(&cfg);
    }
    mock_unlock(&g_cfg_lock);

    if (cfg.open_error < 0) {
        fail_open(out_format, cfg.open_error);
        return NULL;
    }

    /* I3: the hint is a hint. force_rate models a platform that simply has its
     * own rate — which is the normal case on Android and Apple. */
    int32_t rate;
    if (cfg.force_rate > 0) {
        rate = cfg.force_rate;
    } else if (rate_is_valid(rate_hint)) {
        rate = rate_hint;
    } else {
        rate = cfg.default_rate;
    }
    if (!rate_is_valid(rate)) {
        fail_open(out_format, CLEONA_VOICE_ERR_INVALID_ARG);
        return NULL;
    }

    if (cfg.chunk_min < 1) cfg.chunk_min = 1;
    if (cfg.chunk_max < cfg.chunk_min) cfg.chunk_max = cfg.chunk_min;

    cleona_voice_session_t* s =
        (cleona_voice_session_t*)calloc(1, sizeof(cleona_voice_session_t));
    if (!s) {
        fail_open(out_format, CLEONA_VOICE_ERR_BACKEND);
        return NULL;
    }

    format_from_rate(&s->fmt, rate);
    s->cfg = cfg;

    s->accum_cap = s->fmt.frame_samples * MOCK_ACCUM_FRAMES + cfg.chunk_max;
    s->accum = (int16_t*)calloc((size_t)s->accum_cap, sizeof(int16_t));
    if (!s->accum) {
        free(s);
        fail_open(out_format, CLEONA_VOICE_ERR_BACKEND);
        return NULL;
    }

    s->routes_mask = cfg.routes_available_mask;
    s->route_in    = cfg.route_active_in;
    s->route_out   = cfg.route_active_out;
    s->rng         = 0x9E3779B9u ^ (uint32_t)rate;
    s->tone_phase  = 0.0;

    mock_mutex_init(&s->lock);

    *out_format = s->fmt;
    return s;
}

CLEONA_VOICE_API int32_t cleona_voice_start(cleona_voice_session_t* s) {
    if (!s) return CLEONA_VOICE_ERR_CLOSED;

    mock_lock(&s->lock);
    if (s->cfg.start_error < 0) {
        int32_t err = s->cfg.start_error;
        mock_unlock(&s->lock);
        return err;
    }
    if (s->running) {
        mock_unlock(&s->lock);
        return CLEONA_VOICE_ERR_ALREADY_STARTED;
    }

    s->clock_origin_ns  = mock_now_ns();
    s->samples_generated = 0;
    s->accum_len         = 0;
    s->running           = 1;

    /* A started session must name its active output route (cleona_voice.h,
     * SPEC §6 check 8). If the configuration left it unresolved, take the
     * lowest-numbered available route rather than guessing "speaker" — the one
     * fallback I7 forbids. */
    if (s->route_out == CLEONA_VOICE_ROUTE_UNKNOWN ||
        !(s->routes_mask & CLEONA_VOICE_ROUTE_BIT(s->route_out))) {
        s->route_out = CLEONA_VOICE_ROUTE_UNKNOWN;
        for (int32_t r = CLEONA_VOICE_ROUTE_EARPIECE; r <= CLEONA_VOICE_ROUTE_BLUETOOTH; r++) {
            if (s->routes_mask & CLEONA_VOICE_ROUTE_BIT(r)) { s->route_out = r; break; }
        }
    }
    if (s->route_in == CLEONA_VOICE_ROUTE_UNKNOWN) {
        s->route_in = s->route_out;   /* one duplex session, one device pair */
    }

    mock_unlock(&s->lock);
    return CLEONA_VOICE_OK;
}

CLEONA_VOICE_API void cleona_voice_stop(cleona_voice_session_t* s) {
    if (!s) return;
    mock_lock(&s->lock);
    s->running   = 0;
    s->accum_len = 0;
    mock_unlock(&s->lock);
}

CLEONA_VOICE_API void cleona_voice_close(cleona_voice_session_t* s) {
    if (!s) return;
    cleona_voice_stop(s);
    mock_mutex_destroy(&s->lock);
    free(s->accum);
    free(s);
}

/* ==========================================================================
 * Data path
 * ========================================================================== */

CLEONA_VOICE_API int32_t cleona_voice_capture_read(cleona_voice_session_t* s,
                                                   int16_t* out,
                                                   int32_t timeout_ms) {
    if (!s || !out) return CLEONA_VOICE_CAPTURE_CLOSED;
    if (timeout_ms < 0) timeout_ms = 0;

    const int64_t deadline_ns = mock_now_ns() + (int64_t)timeout_ms * 1000000LL;

    for (;;) {
        mock_lock(&s->lock);
        if (!s->running) {
            mock_unlock(&s->lock);
            return CLEONA_VOICE_CAPTURE_CLOSED;
        }

        pump_device_locked(s);

        if (s->accum_len >= s->fmt.frame_samples) {
            /* Exactly one frame, always the full frame — I4. */
            memcpy(out, s->accum, (size_t)s->fmt.frame_bytes);
            s->accum_len -= s->fmt.frame_samples;
            if (s->accum_len > 0) {
                memmove(s->accum, s->accum + s->fmt.frame_samples,
                        (size_t)s->accum_len * sizeof(int16_t));
            }
            s->capture_frames++;
            mock_unlock(&s->lock);
            return CLEONA_VOICE_CAPTURE_FRAME;
        }
        mock_unlock(&s->lock);

        int64_t now = mock_now_ns();
        if (now >= deadline_ns) return CLEONA_VOICE_CAPTURE_TIMEOUT;

        /* Wait outside the lock, in 1 ms steps, so stop() is observed promptly
         * and the deadline is honoured to roughly a millisecond. There is no
         * timer here: the clock that decides when a frame exists is the device
         * clock (I5). */
        mock_sleep_ms(1);
    }
}

CLEONA_VOICE_API int32_t cleona_voice_playback_write(cleona_voice_session_t* s,
                                                     const int16_t* pcm,
                                                     int32_t frame_samples) {
    if (!s)   return CLEONA_VOICE_ERR_CLOSED;
    if (!pcm) return CLEONA_VOICE_ERR_INVALID_ARG;

    mock_lock(&s->lock);
    if (!s->running) {
        mock_unlock(&s->lock);
        return CLEONA_VOICE_ERR_NOT_STARTED;
    }
    if (frame_samples != s->fmt.frame_samples) {
        /* Rejected, never adapted (SPEC §6 check 4). */
        mock_unlock(&s->lock);
        return CLEONA_VOICE_ERR_FRAME_SIZE;
    }

    /* The mock has no speaker, so the frame is swallowed — but the accounting
     * is real, and output mute changes nothing about acceptance (I6). */
    s->playback_frames++;
    if (s->output_muted) s->muted_playback_frames++;

    mock_unlock(&s->lock);
    return CLEONA_VOICE_OK;
}

/* ==========================================================================
 * Controls
 * ========================================================================== */

CLEONA_VOICE_API void cleona_voice_set_mic_muted(cleona_voice_session_t* s,
                                                 int32_t muted) {
    if (!s) return;
    mock_lock(&s->lock);
    /* Bring the device up to date under the OLD mute state first, so the
     * transition lands on a sample boundary instead of retroactively
     * rewriting samples that were already "captured". */
    pump_device_locked(s);
    s->mic_muted = muted ? 1 : 0;
    mock_unlock(&s->lock);
}

CLEONA_VOICE_API void cleona_voice_set_output_muted(cleona_voice_session_t* s,
                                                    int32_t muted) {
    if (!s) return;
    mock_lock(&s->lock);
    s->output_muted = muted ? 1 : 0;
    mock_unlock(&s->lock);
}

CLEONA_VOICE_API int32_t cleona_voice_set_route(cleona_voice_session_t* s,
                                                int32_t route) {
    if (!s) return CLEONA_VOICE_ERR_CLOSED;
    if (route <= CLEONA_VOICE_ROUTE_UNKNOWN || route > CLEONA_VOICE_ROUTE_BLUETOOTH) {
        return CLEONA_VOICE_ERR_INVALID_ARG;
    }

    mock_lock(&s->lock);
    if (!(s->routes_mask & CLEONA_VOICE_ROUTE_BIT(route))) {
        mock_unlock(&s->lock);
        /* The defined failure SPEC §4 asks for: a desktop chain returns this
         * for ROUTE_EARPIECE instead of quietly doing nothing. */
        return CLEONA_VOICE_ERR_ROUTE_UNAVAILABLE;
    }
    s->route_out = route;
    /* No stream teardown, and s->mic_muted / s->output_muted are deliberately
     * NOT touched here (architecture §10.4, "the mute states survive route
     * changes"). Since E6a the report exposes both, so a future edit that reset
     * them would be caught by conformance check S13 instead of surviving as a
     * comment nobody re-read. */
    mock_unlock(&s->lock);
    return CLEONA_VOICE_OK;
}

CLEONA_VOICE_API int32_t cleona_voice_get_routes(cleona_voice_session_t* s,
                                                 int32_t* out_mask,
                                                 int32_t* out_active) {
    if (!s) return CLEONA_VOICE_ERR_CLOSED;
    if (!out_mask || !out_active) return CLEONA_VOICE_ERR_INVALID_ARG;
    mock_lock(&s->lock);
    *out_mask   = s->routes_mask;
    *out_active = s->route_out;
    mock_unlock(&s->lock);
    return CLEONA_VOICE_OK;
}

/* ==========================================================================
 * Events
 * ========================================================================== */

CLEONA_VOICE_API int32_t cleona_voice_poll_event(cleona_voice_session_t* s,
                                                 int32_t* out_event,
                                                 int32_t* out_arg) {
    if (!s) return CLEONA_VOICE_ERR_CLOSED;
    if (!out_event || !out_arg) return CLEONA_VOICE_ERR_INVALID_ARG;

    mock_lock(&s->lock);
    if (s->ev_count == 0) {
        *out_event = CLEONA_VOICE_EV_NONE;   /* the normal case, not an error */
        *out_arg   = 0;
    } else {
        *out_event = s->ev_type[s->ev_head];
        *out_arg   = s->ev_arg[s->ev_head];
        s->ev_head = (s->ev_head + 1) % MOCK_EVENT_QUEUE;
        s->ev_count--;
    }
    mock_unlock(&s->lock);
    return CLEONA_VOICE_OK;
}

/* ==========================================================================
 * Report (I11)
 * ========================================================================== */

CLEONA_VOICE_API void cleona_voice_get_report(cleona_voice_session_t* s,
                                              cleona_voice_report_t* out) {
    if (!out) return;
    memset(out, 0, sizeof(*out));
    if (!s) return;   /* zeroed => duplex == 0 => reads as a failure, correctly */

    mock_lock(&s->lock);
    out->format       = s->fmt;
    out->aec_state    = s->cfg.aec_state;
    out->ns_state     = s->cfg.ns_state;
    out->agc_state    = s->cfg.agc_state;
    out->chain_origin = s->cfg.chain_origin;
    out->backend      = CLEONA_VOICE_BACKEND_MOCK;
    out->duplex       = s->cfg.duplex;
    out->route_active_in      = s->route_in;
    out->route_active_out     = s->route_out;
    out->routes_available_mask = s->routes_mask;
    /* E6a. Straight out of the session state, which is the only place a mute
     * lives here — there is nothing to derive it from and nothing to guess. The
     * route functions below deliberately do not touch these two fields, which is
     * what makes "the mute states survive route changes" (§10.4) true by
     * construction rather than by promise. */
    out->mic_muted    = s->mic_muted;
    out->output_muted = s->output_muted;
    out->underruns    = s->underruns;
    out->overruns     = s->overruns;
    mock_unlock(&s->lock);
}

/* ==========================================================================
 * Mock-only controls (not part of the ABI)
 * ========================================================================== */

CLEONA_VOICE_MOCK_API int32_t cleona_voice_mock_push_event(cleona_voice_session_t* s,
                                     int32_t event, int32_t arg) {
    if (!s) return -1;
    mock_lock(&s->lock);
    push_event_locked(s, event, arg);
    mock_unlock(&s->lock);
    return 0;
}

CLEONA_VOICE_MOCK_API int32_t cleona_voice_mock_set_routes(cleona_voice_session_t* s,
                                     int32_t new_mask,
                                     int32_t new_active_out) {
    if (!s) return CLEONA_VOICE_ERR_CLOSED;
    mock_lock(&s->lock);
    s->routes_mask = new_mask;
    if (new_active_out != CLEONA_VOICE_ROUTE_UNKNOWN) {
        s->route_out = new_active_out;
    } else if (!(new_mask & CLEONA_VOICE_ROUTE_BIT(s->route_out))) {
        /* The active route just vanished. The mock does NOT pick a successor:
         * that decision is I7 and belongs to RoutePolicy in Dart (V1.5). A
         * mock that silently fell back to the speaker would hide exactly the
         * bug the invariant exists to prevent. */
        s->route_out = CLEONA_VOICE_ROUTE_UNKNOWN;
    }
    /* Same as set_route: the mute state is not part of the route model and is
     * not reset here (§10.4). This is the EV_ROUTES_CHANGED half of that
     * assurance — the one a shared-library conformance run cannot reach, because
     * it has no way to make an arbitrary backend change its route set. The smoke
     * programme checks it through this knob (smoke/voice_smoke.c, S2b). */
    push_event_locked(s, CLEONA_VOICE_EV_ROUTES_CHANGED, new_mask);
    mock_unlock(&s->lock);
    return CLEONA_VOICE_OK;
}

CLEONA_VOICE_MOCK_API void cleona_voice_mock_add_underruns(cleona_voice_session_t* s, int64_t n) {
    if (!s) return;
    mock_lock(&s->lock);
    s->underruns += n;
    mock_unlock(&s->lock);
}

CLEONA_VOICE_MOCK_API void cleona_voice_mock_add_overruns(cleona_voice_session_t* s, int64_t n) {
    if (!s) return;
    mock_lock(&s->lock);
    s->overruns += n;
    mock_unlock(&s->lock);
}

CLEONA_VOICE_MOCK_API void cleona_voice_mock_get_counters(cleona_voice_session_t* s,
                                    int64_t* out_capture_frames,
                                    int64_t* out_playback_frames,
                                    int64_t* out_muted_playback_frames) {
    if (!s) return;
    mock_lock(&s->lock);
    if (out_capture_frames)        *out_capture_frames        = s->capture_frames;
    if (out_playback_frames)       *out_playback_frames       = s->playback_frames;
    if (out_muted_playback_frames) *out_muted_playback_frames = s->muted_playback_frames;
    mock_unlock(&s->lock);
}

CLEONA_VOICE_MOCK_API int32_t cleona_voice_mock_force_format(cleona_voice_session_t* s,
                                       int32_t new_rate) {
    if (!s) return CLEONA_VOICE_ERR_CLOSED;
    if (!rate_is_valid(new_rate)) return CLEONA_VOICE_ERR_INVALID_ARG;

    mock_lock(&s->lock);
    format_from_rate(&s->fmt, new_rate);

    int32_t needed = s->fmt.frame_samples * MOCK_ACCUM_FRAMES + s->cfg.chunk_max;
    if (needed > s->accum_cap) {
        int16_t* grown = (int16_t*)realloc(s->accum, (size_t)needed * sizeof(int16_t));
        if (!grown) {
            mock_unlock(&s->lock);
            return CLEONA_VOICE_ERR_BACKEND;
        }
        s->accum = grown;
        s->accum_cap = needed;
    }
    /* Re-base the device clock: samples already generated were counted at the
     * old rate and cannot be reinterpreted at the new one. */
    s->accum_len         = 0;
    s->samples_generated = 0;
    s->clock_origin_ns   = mock_now_ns();

    push_event_locked(s, CLEONA_VOICE_EV_FORMAT_CHANGED, new_rate);
    mock_unlock(&s->lock);
    return CLEONA_VOICE_OK;
}
