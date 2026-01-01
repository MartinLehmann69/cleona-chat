/* cleona_video_mock.c — hardware-free reference implementation of
 * cleona_video.h. SPEC §5 ("Mock-Backends — der eigentliche
 * Parallelisierungs-Hebel").
 *
 * What it is for: every consumer of the video ABI — the Dart pipeline, the
 * conformance harness (V0.4), the transport exemption (V1.11),
 * CALL_MEDIA_STATE (V1.12), the call UI — can be written and tested against
 * this before a single platform backend exists.
 *
 * What it deliberately does NOT do:
 *   - no threads. Frames are produced lazily inside cleona_video_read_encoded.
 *     A background producer would only add a way to leak.
 *   - no rate-control reaction to its own oversize drops. A test fixture that
 *     silently repairs the condition under test is useless.
 *   - no real texture. See CLEONA_VIDEO_MOCK_TEXTURE_ID.
 *
 * The synthetic bitstream is H.264-shaped, not H.264: Annex-B start codes and
 * plausible NAL types (SPS 0x67, PPS 0x68, IDR 0x65, non-IDR 0x41) around
 * deterministic filler. It is enough to test flag handling, size handling and
 * keyframe state; it is not decodable and is never meant to be.
 */

/* clock_gettime/CLOCK_MONOTONIC and nanosleep are POSIX.1-2008, not ISO C.
 * Must be defined before the first system header, or a strict -std=c11 build
 * (as opposed to CMake's default -std=gnu11) fails to see them. */
#if !defined(_WIN32) && !defined(_POSIX_C_SOURCE)
  #define _POSIX_C_SOURCE 200809L
#endif

#include "cleona_video_mock.h"

#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
  #include <windows.h>
  typedef CRITICAL_SECTION cv_lock_t;
  static void cv_lock_init(cv_lock_t* l)    { InitializeCriticalSection(l); }
  static void cv_lock_destroy(cv_lock_t* l) { DeleteCriticalSection(l); }
  static void cv_lock(cv_lock_t* l)         { EnterCriticalSection(l); }
  static void cv_unlock(cv_lock_t* l)       { LeaveCriticalSection(l); }
  static void cv_sleep_ms(int32_t ms)       { Sleep((DWORD)ms); }
  static int64_t cv_now_us(void) {
      LARGE_INTEGER f, c;
      QueryPerformanceFrequency(&f);
      QueryPerformanceCounter(&c);
      return (int64_t)((c.QuadPart * 1000000LL) / f.QuadPart);
  }
#else
  #include <pthread.h>
  #include <time.h>
  typedef pthread_mutex_t cv_lock_t;
  static void cv_lock_init(cv_lock_t* l)    { pthread_mutex_init(l, NULL); }
  static void cv_lock_destroy(cv_lock_t* l) { pthread_mutex_destroy(l); }
  static void cv_lock(cv_lock_t* l)         { pthread_mutex_lock(l); }
  static void cv_unlock(cv_lock_t* l)       { pthread_mutex_unlock(l); }
  static void cv_sleep_ms(int32_t ms) {
      struct timespec ts;
      ts.tv_sec  = ms / 1000;
      ts.tv_nsec = (long)(ms % 1000) * 1000000L;
      nanosleep(&ts, NULL);
  }
  static int64_t cv_now_us(void) {
      struct timespec ts;
      clock_gettime(CLOCK_MONOTONIC, &ts);
      return (int64_t)ts.tv_sec * 1000000LL + ts.tv_nsec / 1000;
  }
#endif

/* ---- lifecycle states, internal ---- */
#define ST_OPEN    0
#define ST_RUNNING 1
#define ST_CLOSED  2

/* Marker planted right after the NAL header byte of the last NAL unit:
 *   [0..4] frame index, 7 bits per byte, most significant group first,
 *          each byte stored as 0x80 | group
 *   [5]    camera index, stored as 0x80 | index
 *   [6]    0xA5
 *
 * Every marker byte therefore has bit 7 set and can never be 0x00 or 0x01.
 * That is not decoration: a plain big-endian index would write 00 00 00 01 for
 * frame 1, which is a literal Annex-B start code, and every start-code scan
 * over the frame — including the decoder's own NAL type lookup in
 * cleona_video_submit_encoded — would latch onto it. Caught by the smoke on
 * the first delta frame. */
#define MOCK_MARKER_LEN   7
#define MOCK_MARKER_MAGIC 0xA5

/* Smallest frame the layout can carry: start code + NAL header + marker. */
#define MOCK_MIN_DELTA_BYTES (4 + 1 + MOCK_MARKER_LEN)
/* Keyframe additionally carries SPS (4+1+4) and PPS (4+1+3). */
#define MOCK_SPS_BYTES (4 + 1 + 4)
#define MOCK_PPS_BYTES (4 + 1 + 3)
#define MOCK_MIN_KEY_BYTES (MOCK_SPS_BYTES + MOCK_PPS_BYTES + MOCK_MIN_DELTA_BYTES)

struct cleona_video_session {
    cv_lock_t lock;

    int32_t state;
    cleona_video_config_t cfg;      /* negotiated, authoritative */

    /* knobs (cleona_video_mock_*) */
    int32_t knob_frame_bytes;       /* 0 = derive from bitrate/fps */
    int32_t knob_oversize_every;    /* <=0 = off */
    int32_t knob_oversize_overshoot;
    int32_t knob_pacing;
    int32_t knob_texture_available;
    int32_t knob_camera_count;
    int32_t knob_hw_encode, knob_hw_decode;
    int32_t knob_min_bitrate_kbps;  /* lowest supported step (Erratum 1) */

    /* capture / encode state */
    int32_t capture_enabled;
    int32_t force_keyframe;
    int32_t camera_index;
    int64_t frame_index;            /* index of the NEXT frame to produce */
    int64_t start_us;               /* monotonic base for pacing */
    int64_t next_due_us;            /* pacing: when the next frame is due */
    /* Presentation clock. Accumulated per frame rather than computed as
     * frame_index * 1e6 / fps, because fps changes at reconfigure time and the
     * multiplicative form would then jump backwards (Erratum 1). */
    int64_t pts_next_us;

    /* one produced-but-unread frame. Kept across an
     * ERR_BUFFER_TOO_SMALL so the caller can retry with a larger buffer
     * without losing the frame. */
    uint8_t* pending;
    int32_t  pending_cap;
    int32_t  pending_size;
    int32_t  pending_flags;
    int64_t  pending_pts_us;
    int32_t  has_pending;

    /* decode state */
    int32_t awaiting_keyframe;
    int64_t last_decoded_index;

    /* report counters — monotonic for the session lifetime */
    int64_t frames_captured, frames_encoded, frames_dropped_oversize;
    int64_t frames_decoded, decode_failures;
};

/* ==========================================================================
 * synthetic bitstream
 * ========================================================================== */

/* Deterministic filler that can never contain a 00 00 01 start-code prefix:
 * every byte lands in 0x20..0xDF. */
static uint8_t mock_filler(int64_t frame_index, int32_t offset) {
    uint32_t x = (uint32_t)(frame_index * 2654435761u) + (uint32_t)offset * 40503u;
    return (uint8_t)(0x20 + (x % 0xC0));
}

static int32_t write_nal(uint8_t* buf, int32_t cap, int32_t pos,
                         uint8_t nal_header, int32_t payload_len,
                         int64_t frame_index, int32_t camera, int32_t with_marker) {
    int32_t need = 4 + 1 + payload_len;
    if (pos + need > cap) return -1;
    buf[pos + 0] = 0x00;
    buf[pos + 1] = 0x00;
    buf[pos + 2] = 0x00;
    buf[pos + 3] = 0x01;
    buf[pos + 4] = nal_header;
    int32_t p = pos + 5;
    int32_t i = 0;
    if (with_marker) {
        for (int32_t k = 0; k < 5; k++) {
            int32_t shift = 7 * (4 - k);
            buf[p + k] = (uint8_t)(0x80 | ((frame_index >> shift) & 0x7F));
        }
        buf[p + 5] = (uint8_t)(0x80 | (camera & 0x7F));
        buf[p + 6] = MOCK_MARKER_MAGIC;
        i = MOCK_MARKER_LEN;
    }
    for (; i < payload_len; i++) {
        buf[p + i] = mock_filler(frame_index, p + i);
    }
    return pos + need;
}

/* Build one frame of exactly total_bytes into buf. Returns total_bytes or -1. */
static int32_t build_frame(uint8_t* buf, int32_t cap, int32_t total_bytes,
                           int32_t keyframe, int64_t frame_index, int32_t camera) {
    if (total_bytes > cap) return -1;
    int32_t pos = 0;
    if (keyframe) {
        if (total_bytes < MOCK_MIN_KEY_BYTES) return -1;
        pos = write_nal(buf, cap, pos, 0x67, 4, frame_index, camera, 0); /* SPS */
        if (pos < 0) return -1;
        pos = write_nal(buf, cap, pos, 0x68, 3, frame_index, camera, 0); /* PPS */
        if (pos < 0) return -1;
        pos = write_nal(buf, cap, pos, 0x65, total_bytes - pos - 5,
                        frame_index, camera, 1);                          /* IDR */
    } else {
        if (total_bytes < MOCK_MIN_DELTA_BYTES) return -1;
        pos = write_nal(buf, cap, pos, 0x41, total_bytes - 5,
                        frame_index, camera, 1);                          /* non-IDR */
    }
    if (pos != total_bytes) return -1;
    return total_bytes;
}

/* Offset of the last Annex-B start code, or -1. */
static int32_t last_start_code(const uint8_t* d, int32_t n) {
    int32_t found = -1;
    for (int32_t i = 0; i + 4 <= n; i++) {
        if (d[i] == 0 && d[i + 1] == 0 && d[i + 2] == 0 && d[i + 3] == 1) found = i;
    }
    return found;
}

static int32_t read_marker(const uint8_t* d, int32_t n, int32_t which) {
    if (!d || n <= 0) return -1;
    int32_t sc = last_start_code(d, n);
    if (sc < 0) return -1;
    int32_t p = sc + 5; /* skip start code + NAL header byte */
    if (p + MOCK_MARKER_LEN > n) return -1;
    if (d[p + 6] != MOCK_MARKER_MAGIC) return -1;
    for (int32_t k = 0; k < 6; k++) {
        if ((d[p + k] & 0x80) == 0) return -1;
    }
    if (which == 0) {
        int64_t v = 0;
        for (int32_t k = 0; k < 5; k++) v = (v << 7) | (d[p + k] & 0x7F);
        return (int32_t)v;
    }
    return (int32_t)(d[p + 5] & 0x7F);
}

int32_t cleona_video_mock_frame_index(const uint8_t* data, int32_t size) {
    return read_marker(data, size, 0);
}

int32_t cleona_video_mock_frame_camera(const uint8_t* data, int32_t size) {
    return read_marker(data, size, 1);
}

/* ==========================================================================
 * lifecycle
 * ========================================================================== */

static int32_t clamp_down(int32_t requested, int32_t ceiling) {
    return requested > ceiling ? ceiling : requested;
}

/* Nominal delta-frame size for a candidate configuration. Mirrors
 * nominal_bytes_locked() but works on a config that is not installed yet. */
static int32_t nominal_for(int32_t knob_frame_bytes, int32_t kbps, int32_t fps) {
    if (knob_frame_bytes > 0) return knob_frame_bytes;
    int64_t b = (int64_t)kbps * 125 / fps;   /* kbps * 1000 / 8 / fps */
    if (b < MOCK_MIN_KEY_BYTES) b = MOCK_MIN_KEY_BYTES;
    return (int32_t)b;
}

/* The single negotiation used by both cleona_video_open and
 * cleona_video_reconfigure — Erratum 1. One code path, so open() and a later
 * reconfigure() can never disagree about what this backend supports.
 *
 * Writes the accepted configuration to *out. Returns CLEONA_VIDEO_OK,
 * CLEONA_VIDEO_ERR_INVALID or CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE.
 *
 * Scaling policy of the mock, kept deliberately simple and visible:
 *   - geometry and fps are clamped to the mock's caps (down only);
 *   - if the resulting keyframe would not fit under max_frame_bytes, the
 *     bitrate is lowered to the largest value that does fit;
 *   - if that value is below the lowest supported step
 *     (knob_min_bitrate_kbps), nothing fits -> ERR_RATE_UNACHIEVABLE.
 *
 * Note this is negotiation, not rate control: it happens once per open/
 * reconfigure call, never per frame. The mock still performs no rate control
 * of its own while running.
 *
 * When knob_frame_bytes is pinned by a test, the frame size no longer follows
 * the bitrate, so there is nothing to scale — the pinned size either fits or
 * the answer is ERR_RATE_UNACHIEVABLE. */
static int32_t negotiate(const cleona_video_config_t* cfg,
                         int32_t knob_frame_bytes,
                         int32_t min_bitrate_kbps,
                         cleona_video_config_t* out) {
    if (!cfg || !out) return CLEONA_VIDEO_ERR_INVALID;

    /* Fail closed on everything the ABI declares mandatory. In particular
     * max_frame_bytes: an encoder without a ceiling violates I9 by
     * construction, so there is no sensible default to invent here. */
    if (cfg->width <= 0 || cfg->height <= 0 || cfg->fps <= 0) {
        return CLEONA_VIDEO_ERR_INVALID;
    }
    if (cfg->target_bitrate_kbps <= 0) return CLEONA_VIDEO_ERR_INVALID;
    if (cfg->max_frame_bytes <= 0) return CLEONA_VIDEO_ERR_INVALID;
    if (cfg->keyframe_interval_frames < 0) return CLEONA_VIDEO_ERR_INVALID;
    /* Erratum 7: an unknown direction is a caller bug, decided here with the
     * other field checks so it can never be reported as
     * ERR_RATE_UNACHIEVABLE (Erratum 6b, case 1). Note the encode-side fields
     * above are validated identically for DECODE_ONLY — the erratum
     * deliberately does not fork the validation path. */
    if (cfg->direction != CLEONA_VIDEO_DIR_DUPLEX &&
        cfg->direction != CLEONA_VIDEO_DIR_DECODE_ONLY) {
        return CLEONA_VIDEO_ERR_INVALID;
    }

    int32_t codec = cfg->codec;
    if (codec <= 0) {
        codec = CLEONA_VIDEO_CODEC_H264;          /* no preference */
    } else if (codec > CLEONA_VIDEO_CODEC_VP9) {
        return CLEONA_VIDEO_ERR_INVALID;          /* unknown value: caller bug */
    } else if (codec != CLEONA_VIDEO_CODEC_H264) {
        /* The mock has no hardware for anything, so it negotiates down to the
         * mandatory interop level instead of failing. */
        codec = CLEONA_VIDEO_CODEC_H264;
    }

    int32_t width  = clamp_down(cfg->width, CLEONA_VIDEO_MOCK_MAX_WIDTH);
    int32_t height = clamp_down(cfg->height, CLEONA_VIDEO_MOCK_MAX_HEIGHT);
    int32_t fps    = clamp_down(cfg->fps, CLEONA_VIDEO_MOCK_MAX_FPS);
    int32_t kbps   = cfg->target_bitrate_kbps;

    /* Largest nominal delta size whose keyframe still fits the ceiling. */
    int32_t nominal_budget = cfg->max_frame_bytes / CLEONA_VIDEO_MOCK_KEYFRAME_FACTOR;
    if (nominal_budget < MOCK_MIN_KEY_BYTES) {
        /* Not even the smallest frame this backend can emit fits. */
        return CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE;
    }

    if (nominal_for(knob_frame_bytes, kbps, fps) > nominal_budget) {
        if (knob_frame_bytes > 0) {
            /* Size is pinned by a test knob: no scaling available. */
            return CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE;
        }
        /* Scale the rate down to fit: bytes = kbps * 125 / fps. */
        int64_t fit_kbps = (int64_t)nominal_budget * fps / 125;
        if (fit_kbps < min_bitrate_kbps) {
            return CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE;
        }
        if (fit_kbps < kbps) kbps = (int32_t)fit_kbps;
    }

    out->codec                   = codec;
    out->width                   = width;
    out->height                  = height;
    out->fps                     = fps;
    out->target_bitrate_kbps     = kbps;
    out->max_frame_bytes         = cfg->max_frame_bytes;  /* never raised */
    out->keyframe_interval_frames =
        cfg->keyframe_interval_frames > 0 ? cfg->keyframe_interval_frames
                                          : fps * 2;      /* backend default */
    out->direction               = cfg->direction;        /* echoed, never changed */
    return CLEONA_VIDEO_OK;
}

/* Erratum 6b: the in-band error channel of cleona_video_open. A failing open()
 * zeroes out_negotiated and leaves a negative CLEONA_VIDEO_ERR_* in
 * max_frame_bytes, which can never be a valid negotiated value. A NULL
 * out_negotiated is a caller that declared it does not want the reason. */
static void write_open_error(cleona_video_config_t* out, int32_t code) {
    if (!out) return;
    memset(out, 0, sizeof(*out));
    out->max_frame_bytes = code;
}

cleona_video_session_t* cleona_video_open(const cleona_video_config_t* cfg,
                                          cleona_video_config_t* out_negotiated) {
    if (!cfg) {
        write_open_error(out_negotiated, CLEONA_VIDEO_ERR_INVALID);
        return NULL;
    }

    cleona_video_config_t accepted;
    /* Erratum 1: open() runs the same negotiation as reconfigure(). A session
     * whose very first configuration cannot be met is NOT created — returning
     * one would mean producing frames that are discarded from the first
     * moment, i.e. a black picture with no reason given, which is exactly what
     * the erratum forbids.
     *
     * Erratum 6b: and it says WHICH of the two it was. negotiate() already
     * separates "caller bug" (ERR_INVALID, validity decided first) from "no
     * step fits this ceiling" (ERR_RATE_UNACHIEVABLE); that verdict is simply
     * passed through instead of being flattened into a bare NULL. The detour
     * this comment used to recommend — open permissively, then reconfigure to
     * learn the reason — is no longer needed. */
    int32_t rc = negotiate(cfg, 0, CLEONA_VIDEO_MOCK_DEFAULT_MIN_BITRATE_KBPS,
                           &accepted);
    if (rc != CLEONA_VIDEO_OK) {
        write_open_error(out_negotiated, rc);
        return NULL;
    }

    cleona_video_session_t* s =
        (cleona_video_session_t*)calloc(1, sizeof(cleona_video_session_t));
    if (!s) {
        /* The configuration was fine and this backend is capable; this one
         * attempt failed. Retryable in principle — ERR_BACKEND, not
         * ERR_UNSUPPORTED (the mock always has a capture path). */
        write_open_error(out_negotiated, CLEONA_VIDEO_ERR_BACKEND);
        return NULL;
    }

    cv_lock_init(&s->lock);
    s->state = ST_OPEN;
    s->cfg = accepted;

    s->knob_frame_bytes        = 0;
    s->knob_oversize_every     = 0;
    s->knob_oversize_overshoot = 512;
    s->knob_pacing             = 1;
    s->knob_texture_available  = 1;
    s->knob_camera_count       = 2;
    s->knob_hw_encode          = CLEONA_VIDEO_HW_NO;  /* the truth, not a guess */
    s->knob_hw_decode          = CLEONA_VIDEO_HW_NO;
    s->knob_min_bitrate_kbps   = CLEONA_VIDEO_MOCK_DEFAULT_MIN_BITRATE_KBPS;

    /* Erratum 7: a DECODE_ONLY session never had a camera to enable. This is
     * the state, not a user-visible mute — set_capture_enabled cannot turn it
     * back on. */
    s->capture_enabled   = (accepted.direction == CLEONA_VIDEO_DIR_DECODE_ONLY) ? 0 : 1;
    s->awaiting_keyframe = 1;
    s->last_decoded_index = -1;

    if (out_negotiated) *out_negotiated = s->cfg;
    return s;
}

int32_t cleona_video_reconfigure(cleona_video_session_t* s,
                                 const cleona_video_config_t* cfg,
                                 cleona_video_config_t* out_negotiated) {
    if (!s || !cfg) return CLEONA_VIDEO_ERR_INVALID;

    cv_lock(&s->lock);
    if (s->state == ST_CLOSED) {
        cv_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_STATE;
    }

    /* Erratum 7: direction is fixed at open(). A session opened to decode
     * cannot grow a camera, so a mismatch is a caller bug and not a
     * negotiation outcome. Checked before negotiate() so the session is left
     * untouched, as every other failing reconfigure() leaves it. */
    if (cfg->direction != s->cfg.direction) {
        cv_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_INVALID;
    }

    cleona_video_config_t accepted;
    int32_t rc = negotiate(cfg, s->knob_frame_bytes, s->knob_min_bitrate_kbps,
                           &accepted);
    if (rc != CLEONA_VIDEO_OK) {
        /* Side-effect free on failure: the session keeps running exactly as it
         * was. On ERR_RATE_UNACHIEVABLE the caller stops own video and tells
         * the user why — it does not retry silently (Erratum 1). */
        cv_unlock(&s->lock);
        return rc;
    }

    const int32_t geometry_changed =
        accepted.width != s->cfg.width || accepted.height != s->cfg.height;

    s->cfg = accepted;

    if (geometry_changed) {
        /* The peer's decoder cannot continue from a reference picture of a
         * different size. Not a heuristic. */
        s->force_keyframe = 1;
    }

    /* A frame already produced under the previous configuration is still
     * delivered — unless it exceeds the ceiling that is now in force, in which
     * case handing it over would violate I9 for a limit already accepted. */
    if (s->has_pending && s->pending_size > s->cfg.max_frame_bytes) {
        s->has_pending = 0;
        s->pending_size = 0;
        s->frames_dropped_oversize++;
    }

    if (out_negotiated) *out_negotiated = s->cfg;
    cv_unlock(&s->lock);
    return CLEONA_VIDEO_OK;
}

int32_t cleona_video_start(cleona_video_session_t* s) {
    if (!s) return CLEONA_VIDEO_ERR_INVALID;
    cv_lock(&s->lock);
    if (s->state != ST_OPEN) {
        cv_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_STATE;
    }
    s->state = ST_RUNNING;
    s->start_us = cv_now_us();
    s->next_due_us = s->start_us;
    s->force_keyframe = 1;
    cv_unlock(&s->lock);
    return CLEONA_VIDEO_OK;
}

void cleona_video_stop(cleona_video_session_t* s) {
    if (!s) return;
    cv_lock(&s->lock);
    if (s->state == ST_RUNNING) s->state = ST_OPEN;
    s->has_pending = 0;
    s->pending_size = 0;
    /* Decoder state resets: after the next start() we again need a keyframe. */
    s->awaiting_keyframe = 1;
    cv_unlock(&s->lock);
}

void cleona_video_close(cleona_video_session_t* s) {
    if (!s) return;
    cleona_video_stop(s);
    cv_lock(&s->lock);
    s->state = ST_CLOSED;
    free(s->pending);
    s->pending = NULL;
    s->pending_cap = 0;
    cv_unlock(&s->lock);
    cv_lock_destroy(&s->lock);
    free(s);
}

/* ==========================================================================
 * capture / encode
 * ========================================================================== */

static int32_t nominal_bytes_locked(const cleona_video_session_t* s) {
    if (s->knob_frame_bytes > 0) return s->knob_frame_bytes;
    /* kbps -> bytes per frame: kbps * 1000 / 8 / fps == kbps * 125 / fps */
    int64_t b = (int64_t)s->cfg.target_bitrate_kbps * 125 / s->cfg.fps;
    if (b < MOCK_MIN_KEY_BYTES) b = MOCK_MIN_KEY_BYTES;
    return (int32_t)b;
}

/* Produce exactly one frame. Returns 1 = frame is now pending,
 * 0 = frame was produced and discarded by the I9 backstop, -1 = internal
 * failure. Caller holds the lock. */
static int32_t produce_locked(cleona_video_session_t* s) {
    int64_t idx = s->frame_index++;

    /* Presentation clock advances for every produced frame, including the ones
     * the backstop discards below. Accumulated, not computed from idx and fps,
     * so that a reconfigure which raises fps again cannot make pts jump
     * backwards (Erratum 1). */
    int64_t pts = s->pts_next_us;
    s->pts_next_us += 1000000LL / s->cfg.fps;

    int32_t keyframe = s->force_keyframe || idx == 0 ||
        (s->cfg.keyframe_interval_frames > 0 &&
         (idx % s->cfg.keyframe_interval_frames) == 0);
    /* The request is consumed by producing the keyframe, even if the backstop
     * discards it below — the encoder did honour it. A real backend that keeps
     * losing forced keyframes to the ceiling must lower its preset. */
    s->force_keyframe = 0;

    int32_t nominal = nominal_bytes_locked(s);
    int32_t size = keyframe ? nominal * CLEONA_VIDEO_MOCK_KEYFRAME_FACTOR : nominal;

    int32_t inject = (s->knob_oversize_every > 0 && idx > 0 &&
                      (idx % s->knob_oversize_every) == 0);
    if (inject) {
        int32_t over = s->knob_oversize_overshoot > 0 ? s->knob_oversize_overshoot : 512;
        size = s->cfg.max_frame_bytes + over;
    }

    int32_t floor_bytes = keyframe ? MOCK_MIN_KEY_BYTES : MOCK_MIN_DELTA_BYTES;
    if (size < floor_bytes) size = floor_bytes;

    if (s->pending_cap < size) {
        uint8_t* nb = (uint8_t*)realloc(s->pending, (size_t)size);
        if (!nb) return -1;
        s->pending = nb;
        s->pending_cap = size;
    }
    if (build_frame(s->pending, s->pending_cap, size, keyframe, idx, s->camera_index) < 0) {
        return -1;
    }

    s->frames_captured++;
    s->frames_encoded++;

    if (size > s->cfg.max_frame_bytes) {
        /* I9 backstop. Never handed to the caller — an undeliverable frame
         * costs the same bandwidth as a deliverable one and arrives never. */
        s->frames_dropped_oversize++;
        s->has_pending = 0;
        return 0;
    }

    s->pending_size  = size;
    s->pending_flags = keyframe ? CLEONA_VIDEO_FLAG_KEYFRAME : 0;
    s->pending_pts_us = pts;
    s->has_pending = 1;
    return 1;
}

int32_t cleona_video_read_encoded(cleona_video_session_t* s,
                                  uint8_t* buf, int32_t buf_cap,
                                  int32_t* out_size, int32_t* out_flags,
                                  int64_t* out_pts_us, int32_t timeout_ms) {
    if (!s || !buf || buf_cap <= 0 || !out_size || !out_flags || !out_pts_us) {
        return CLEONA_VIDEO_ERR_INVALID;
    }

    const int64_t started = cv_now_us();
    const int32_t blocking = timeout_ms < 0;

    for (;;) {
        cv_lock(&s->lock);

        if (s->state != ST_RUNNING) {
            cv_unlock(&s->lock);
            return CLEONA_VIDEO_READ_CLOSED;
        }

        /* Erratum 7: a DECODE_ONLY session has no encoder, so a frame can
         * never arrive. Answered immediately and as READ_TIMEOUT — the session
         * is running, so READ_CLOSED would be a lie. The short-circuit is
         * before the pacing loop on purpose: a blocking read (timeout_ms < 0)
         * would otherwise wait for something that cannot happen. */
        if (s->cfg.direction == CLEONA_VIDEO_DIR_DECODE_ONLY) {
            cv_unlock(&s->lock);
            return CLEONA_VIDEO_READ_TIMEOUT;
        }

        if (s->has_pending) {
            if (s->pending_size > buf_cap) {
                /* Frame stays pending: the caller can retry with a bigger
                 * buffer without losing it. */
                *out_size = s->pending_size;
                cv_unlock(&s->lock);
                return CLEONA_VIDEO_ERR_BUFFER_TOO_SMALL;
            }
            memcpy(buf, s->pending, (size_t)s->pending_size);
            *out_size   = s->pending_size;
            *out_flags  = s->pending_flags;
            *out_pts_us = s->pending_pts_us;
            s->has_pending = 0;
            cv_unlock(&s->lock);
            return CLEONA_VIDEO_READ_FRAME;
        }

        /* "Own video off" is not "session gone" — I12. */
        if (s->capture_enabled) {
            int64_t now = cv_now_us();
            int32_t due = !s->knob_pacing || now >= s->next_due_us;
            if (due) {
                if (s->knob_pacing) {
                    s->next_due_us += 1000000LL / s->cfg.fps;
                    if (s->next_due_us < now) s->next_due_us = now;
                }
                int32_t r = produce_locked(s);
                cv_unlock(&s->lock);
                if (r < 0) return CLEONA_VIDEO_ERR_BACKEND;
                /* r == 0: dropped by the backstop. Keep looking — a caller
                 * must not see a phantom timeout because the encoder
                 * overshot; it could not tell that apart from a stalled
                 * camera. */
                continue;
            }
        }

        cv_unlock(&s->lock);

        if (!blocking) {
            int64_t elapsed_ms = (cv_now_us() - started) / 1000;
            if (elapsed_ms >= timeout_ms) return CLEONA_VIDEO_READ_TIMEOUT;
        }
        cv_sleep_ms(1);
    }
}

/* ==========================================================================
 * decode
 * ========================================================================== */

int32_t cleona_video_submit_encoded(cleona_video_session_t* s,
                                    const uint8_t* data, int32_t size,
                                    int32_t flags) {
    if (!s || !data || size <= 0) return CLEONA_VIDEO_ERR_INVALID;

    cv_lock(&s->lock);
    if (s->state != ST_RUNNING) {
        cv_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_STATE;
    }

    int32_t sc = last_start_code(data, size);
    if (sc < 0 || sc + 5 > size) {
        s->decode_failures++;
        cv_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_DECODE;
    }

    int32_t nal_type = data[sc + 4] & 0x1F;
    int32_t is_idr = (nal_type == 5);           /* 0x65 & 0x1F == 5 */
    int32_t claims_key = (flags & CLEONA_VIDEO_FLAG_KEYFRAME) != 0;

    /* The flags a peer sends and the bitstream it sends must agree. Feeding a
     * decoder a lie is a bug worth failing on, not worth papering over. */
    if (claims_key != is_idr) {
        s->decode_failures++;
        cv_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_DECODE;
    }

    if (s->awaiting_keyframe && !is_idr) {
        /* Not a failure: the decoder simply cannot start here. Not counted in
         * decode_failures. */
        cv_unlock(&s->lock);
        return CLEONA_VIDEO_SUBMIT_AWAITING_KEYFRAME;
    }

    s->awaiting_keyframe = 0;
    s->frames_decoded++;
    s->last_decoded_index = read_marker(data, size, 0);
    cv_unlock(&s->lock);
    return CLEONA_VIDEO_SUBMIT_ACCEPTED;
}

int32_t cleona_video_get_texture_id(cleona_video_session_t* s, int64_t* out_id) {
    if (!s || !out_id) return CLEONA_VIDEO_ERR_INVALID;
    cv_lock(&s->lock);
    if (s->state != ST_RUNNING) {
        cv_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_STATE;
    }
    if (!s->knob_texture_available) {
        cv_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_UNSUPPORTED;
    }
    /* Synthetic. Not registered with any renderer — see the constant's doc. */
    *out_id = CLEONA_VIDEO_MOCK_TEXTURE_ID;
    cv_unlock(&s->lock);
    return CLEONA_VIDEO_OK;
}

/* ==========================================================================
 * controls
 * ========================================================================== */

int32_t cleona_video_request_keyframe(cleona_video_session_t* s) {
    if (!s) return CLEONA_VIDEO_ERR_INVALID;
    cv_lock(&s->lock);
    if (s->state != ST_RUNNING) {
        cv_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_STATE;
    }
    /* Erratum 7: this asks OUR encoder, and a DECODE_ONLY session has none.
     * Getting the PEER to send a keyframe is signalling, not this ABI. */
    if (s->cfg.direction == CLEONA_VIDEO_DIR_DECODE_ONLY) {
        cv_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_UNSUPPORTED;
    }
    s->force_keyframe = 1;
    cv_unlock(&s->lock);
    return CLEONA_VIDEO_OK;
}

void cleona_video_set_capture_enabled(cleona_video_session_t* s, int32_t on) {
    if (!s) return;
    cv_lock(&s->lock);
    /* Erratum 7: accepted and ignored on a DECODE_ONLY session. A caller that
     * drives N sessions uniformly must not have to special-case this one, and
     * capture cannot be switched on for a camera that was never opened. */
    if (s->cfg.direction == CLEONA_VIDEO_DIR_DECODE_ONLY) {
        cv_unlock(&s->lock);
        return;
    }
    int32_t want = on ? 1 : 0;
    if (want && !s->capture_enabled) {
        /* The peer's decoder has been starved; a P-frame now would be
         * undecodable there. Unconditional, not a heuristic. */
        s->force_keyframe = 1;
        s->next_due_us = cv_now_us();
    }
    if (!want) {
        s->has_pending = 0;   /* nothing half-produced survives the switch-off */
    }
    s->capture_enabled = want;
    cv_unlock(&s->lock);
}

int32_t cleona_video_switch_camera(cleona_video_session_t* s) {
    if (!s) return CLEONA_VIDEO_ERR_INVALID;
    cv_lock(&s->lock);
    if (s->state != ST_RUNNING) {
        cv_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_STATE;
    }
    /* Erratum 7: no camera at all on a DECODE_ONLY session. */
    if (s->cfg.direction == CLEONA_VIDEO_DIR_DECODE_ONLY ||
        s->knob_camera_count < 2) {
        cv_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_UNSUPPORTED;
    }
    s->camera_index = (s->camera_index + 1) % s->knob_camera_count;
    s->force_keyframe = 1;
    s->has_pending = 0;
    cv_unlock(&s->lock);
    return CLEONA_VIDEO_OK;
}

void cleona_video_get_report(cleona_video_session_t* s, cleona_video_report_t* out) {
    if (!out) return;
    if (!s) {
        memset(out, 0, sizeof(*out));
        /* "No session" is not evidence that there is no hardware — I11. */
        out->hardware_encode = CLEONA_VIDEO_HW_NOT_DETERMINABLE;
        out->hardware_decode = CLEONA_VIDEO_HW_NOT_DETERMINABLE;
        return;
    }
    cv_lock(&s->lock);
    const int32_t decode_only =
        (s->cfg.direction == CLEONA_VIDEO_DIR_DECODE_ONLY);
    out->codec_in_use            = s->cfg.codec;
    /* Erratum 7: on a DECODE_ONLY session the absence of an encoder is known,
     * not undetermined — HW_NO, never HW_NOT_DETERMINABLE. */
    out->hardware_encode         = decode_only ? CLEONA_VIDEO_HW_NO
                                               : s->knob_hw_encode;
    out->hardware_decode         = s->knob_hw_decode;
    out->negotiated_width        = s->cfg.width;
    out->negotiated_height       = s->cfg.height;
    out->negotiated_fps          = s->cfg.fps;
    out->capture_backend         = decode_only ? CLEONA_VIDEO_BACKEND_NONE
                                               : CLEONA_VIDEO_BACKEND_MOCK;
    out->encode_backend          = decode_only ? CLEONA_VIDEO_BACKEND_NONE
                                               : CLEONA_VIDEO_BACKEND_MOCK;
    out->frames_captured         = s->frames_captured;
    out->frames_encoded          = s->frames_encoded;
    out->frames_dropped_oversize = s->frames_dropped_oversize;
    out->frames_decoded          = s->frames_decoded;
    out->decode_failures         = s->decode_failures;
    cv_unlock(&s->lock);
}

/* ==========================================================================
 * mock-only knobs (not part of the ABI)
 * ========================================================================== */

void cleona_video_mock_set_frame_bytes(cleona_video_session_t* s, int32_t bytes) {
    if (!s) return;
    cv_lock(&s->lock);
    s->knob_frame_bytes = bytes > 0 ? bytes : 0;
    cv_unlock(&s->lock);
}

void cleona_video_mock_set_oversize_every(cleona_video_session_t* s,
                                          int32_t n, int32_t overshoot) {
    if (!s) return;
    cv_lock(&s->lock);
    s->knob_oversize_every = n;
    s->knob_oversize_overshoot = overshoot > 0 ? overshoot : 512;
    cv_unlock(&s->lock);
}

void cleona_video_mock_set_pacing(cleona_video_session_t* s, int32_t on) {
    if (!s) return;
    cv_lock(&s->lock);
    s->knob_pacing = on ? 1 : 0;
    cv_unlock(&s->lock);
}

void cleona_video_mock_set_texture_available(cleona_video_session_t* s, int32_t on) {
    if (!s) return;
    cv_lock(&s->lock);
    s->knob_texture_available = on ? 1 : 0;
    cv_unlock(&s->lock);
}

void cleona_video_mock_set_camera_count(cleona_video_session_t* s, int32_t n) {
    if (!s) return;
    cv_lock(&s->lock);
    s->knob_camera_count = n > 0 ? n : 1;
    if (s->camera_index >= s->knob_camera_count) s->camera_index = 0;
    cv_unlock(&s->lock);
}

void cleona_video_mock_set_hardware(cleona_video_session_t* s,
                                    int32_t encode, int32_t decode) {
    if (!s) return;
    cv_lock(&s->lock);
    s->knob_hw_encode = encode;
    s->knob_hw_decode = decode;
    cv_unlock(&s->lock);
}

void cleona_video_mock_set_min_bitrate_kbps(cleona_video_session_t* s, int32_t kbps) {
    if (!s) return;
    cv_lock(&s->lock);
    s->knob_min_bitrate_kbps =
        kbps > 0 ? kbps : CLEONA_VIDEO_MOCK_DEFAULT_MIN_BITRATE_KBPS;
    cv_unlock(&s->lock);
}
