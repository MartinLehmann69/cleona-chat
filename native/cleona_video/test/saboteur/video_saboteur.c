/* video_saboteur.c — a video backend that is conformant except for ONE injected
 * defect, selected at run time by the environment variable CLEONA_VIDEO_SABOTAGE.
 *
 * Work package: docs/SPEC_VOICE_VIDEO_REWORK.md V0.4.
 *
 * Why this exists is written out in the voice counterpart
 * (native/cleona_voice/test/saboteur/voice_saboteur.c): a conformance test that
 * has never been seen to fail is not evidence of conformance. Each negative
 * control runs the real harness against a backend that breaks exactly one
 * property and passes only when the harness reports exactly the check that
 * property belongs to.
 *
 * Construction: the mock is compiled in with its twelve ABI entry points renamed
 * to sabv_*, and the real names are defined here as forwarders. The saboteur is
 * therefore as conformant as the mock in every respect but one.
 *
 * Test-only. Built by native/cleona_video/test/CMakeLists.txt and by nothing
 * else.
 */

#define cleona_video_open                sabv_open
#define cleona_video_reconfigure         sabv_reconfigure
#define cleona_video_start               sabv_start
#define cleona_video_stop                sabv_stop
#define cleona_video_close               sabv_close
#define cleona_video_read_encoded        sabv_read_encoded
#define cleona_video_submit_encoded      sabv_submit_encoded
#define cleona_video_get_texture_id      sabv_get_texture_id
#define cleona_video_request_keyframe    sabv_request_keyframe
#define cleona_video_set_capture_enabled sabv_set_capture_enabled
#define cleona_video_switch_camera       sabv_switch_camera
#define cleona_video_get_report          sabv_get_report

#include "../../mock/cleona_video_mock.c"

#undef cleona_video_open
#undef cleona_video_reconfigure
#undef cleona_video_start
#undef cleona_video_stop
#undef cleona_video_close
#undef cleona_video_read_encoded
#undef cleona_video_submit_encoded
#undef cleona_video_get_texture_id
#undef cleona_video_request_keyframe
#undef cleona_video_set_capture_enabled
#undef cleona_video_switch_camera
#undef cleona_video_get_report

#include <stdlib.h>
#include <string.h>

enum {
    SABV_NONE = 0,
    SABV_OVERSIZE,        /* I9  — hands out a frame larger than the ceiling   */
    SABV_PTS_FROM_INDEX,  /* E1  — pts = index * 1e6 / fps, the named bug      */
    SABV_CAPTURE_CLOSED,  /* I12 — "own video off" reported as "session gone"  */
    SABV_NO_H264,         /* §10.6 — no mandatory interop level                */
    SABV_OPEN_ERR_SWAP,   /* E6b — unreachable rate reported as a caller bug   */
    SABV_LEAK             /* leak surface of open()                            */
};

static int sabv_mode(void) {
    static int cached = -1;
    if (cached >= 0) return cached;
    const char* v = getenv("CLEONA_VIDEO_SABOTAGE");
    if (!v || !*v)                            cached = SABV_NONE;
    else if (strcmp(v, "oversize") == 0)      cached = SABV_OVERSIZE;
    else if (strcmp(v, "pts_from_index") == 0) cached = SABV_PTS_FROM_INDEX;
    else if (strcmp(v, "capture_closed") == 0) cached = SABV_CAPTURE_CLOSED;
    else if (strcmp(v, "no_h264") == 0)       cached = SABV_NO_H264;
    else if (strcmp(v, "open_err_swap") == 0) cached = SABV_OPEN_ERR_SWAP;
    else if (strcmp(v, "leak") == 0)          cached = SABV_LEAK;
    else                                      cached = SABV_NONE;
    return cached;
}

/* Enough state for the defects. One harness process, one session at a time. */
static int32_t g_fps = 30;
static int64_t g_index = 0;
static int32_t g_capture_off = 0;
static int64_t g_read_count = 0;

CLEONA_VIDEO_API cleona_video_session_t* cleona_video_open(
    const cleona_video_config_t* cfg, cleona_video_config_t* out_negotiated) {
    cleona_video_session_t* s = sabv_open(cfg, out_negotiated);
    if (s && out_negotiated) {
        g_fps = out_negotiated->fps > 0 ? out_negotiated->fps : 30;
        if (sabv_mode() == SABV_NO_H264 && cfg &&
            cfg->codec == CLEONA_VIDEO_CODEC_H264) {
            /* Answers "I gave you HEVC" to a caller that asked for the mandatory
             * interop level. A peer on another platform would then have no
             * common codec — the video equivalent of a backend that cannot do
             * duplex. Only the explicit-H264 request is affected, so the "no
             * preference" and "negotiate down" paths stay conformant and the
             * negative control fails exactly one check. */
            out_negotiated->codec = CLEONA_VIDEO_CODEC_HEVC;
        }
    }
    if (!s && out_negotiated && sabv_mode() == SABV_OPEN_ERR_SWAP &&
        out_negotiated->max_frame_bytes == CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE) {
        /* E6b: "this link cannot carry video" reported as "you called me wrong".
         * A caller obeying the ABI then treats a link condition as a bug in
         * itself — it shows no reason, or the wrong one, which is the failure
         * Erratum E1 exists to remove. Only the unachievable answer is
         * rewritten; every genuinely invalid config still gets ERR_INVALID, so
         * this control fails exactly one check. */
        out_negotiated->max_frame_bytes = CLEONA_VIDEO_ERR_INVALID;
    }
    if (s && sabv_mode() == SABV_LEAK) {
        volatile unsigned char* leaked = (unsigned char*)malloc(4096);
        if (leaked) leaked[0] = 0x5A;
    }
    return s;
}

CLEONA_VIDEO_API int32_t cleona_video_reconfigure(cleona_video_session_t* s,
                                                  const cleona_video_config_t* cfg,
                                                  cleona_video_config_t* out_negotiated) {
    int32_t r = sabv_reconfigure(s, cfg, out_negotiated);
    if (r == CLEONA_VIDEO_OK && out_negotiated && out_negotiated->fps > 0) {
        g_fps = out_negotiated->fps;
    }
    return r;
}

CLEONA_VIDEO_API int32_t cleona_video_start(cleona_video_session_t* s) {
    return sabv_start(s);
}

CLEONA_VIDEO_API void cleona_video_stop(cleona_video_session_t* s) {
    sabv_stop(s);
}

CLEONA_VIDEO_API void cleona_video_close(cleona_video_session_t* s) {
    sabv_close(s);
}

CLEONA_VIDEO_API int32_t cleona_video_read_encoded(cleona_video_session_t* s,
                                                   uint8_t* buf, int32_t buf_cap,
                                                   int32_t* out_size,
                                                   int32_t* out_flags,
                                                   int64_t* out_pts_us,
                                                   int32_t timeout_ms) {
    if (sabv_mode() == SABV_CAPTURE_CLOSED && g_capture_off) {
        /* "Own video off" reported as "session gone". A caller obeying the ABI
         * leaves its read loop here and the call loses the peer's picture too,
         * which is exactly what I12 forbids. */
        return CLEONA_VIDEO_READ_CLOSED;
    }

    int32_t r = sabv_read_encoded(s, buf, buf_cap, out_size, out_flags,
                                  out_pts_us, timeout_ms);
    if (r != CLEONA_VIDEO_READ_FRAME) return r;

    g_read_count++;

    if (sabv_mode() == SABV_OVERSIZE && (g_read_count % 7) == 0 &&
        buf && buf_cap > 0 && out_size) {
        /* Every seventh frame is handed out one byte beyond the capacity the
         * caller declared. Intermittent on purpose: a backend that overshot on
         * every frame would also starve the rest of the harness, and the
         * negative control has to prove that the ceiling check catches this,
         * not that everything falls over. */
        buf[buf_cap] = 0xFF;
        *out_size = buf_cap + 1;
    }

    if (sabv_mode() == SABV_PTS_FROM_INDEX && out_pts_us) {
        /* The bug cleona_video.h names: pts derived from the frame index and
         * the CURRENT fps. Monotonic as long as fps only falls, and it walks
         * backwards the moment fps goes up again. */
        *out_pts_us = g_index * 1000000LL / (g_fps > 0 ? g_fps : 30);
        g_index++;
    }
    return r;
}

CLEONA_VIDEO_API int32_t cleona_video_submit_encoded(cleona_video_session_t* s,
                                                     const uint8_t* data,
                                                     int32_t size, int32_t flags) {
    return sabv_submit_encoded(s, data, size, flags);
}

CLEONA_VIDEO_API int32_t cleona_video_get_texture_id(cleona_video_session_t* s,
                                                     int64_t* out_id) {
    return sabv_get_texture_id(s, out_id);
}

CLEONA_VIDEO_API int32_t cleona_video_request_keyframe(cleona_video_session_t* s) {
    return sabv_request_keyframe(s);
}

CLEONA_VIDEO_API void cleona_video_set_capture_enabled(cleona_video_session_t* s,
                                                       int32_t on) {
    g_capture_off = on ? 0 : 1;
    sabv_set_capture_enabled(s, on);
}

CLEONA_VIDEO_API int32_t cleona_video_switch_camera(cleona_video_session_t* s) {
    return sabv_switch_camera(s);
}

CLEONA_VIDEO_API void cleona_video_get_report(cleona_video_session_t* s,
                                              cleona_video_report_t* out) {
    sabv_get_report(s, out);
}
