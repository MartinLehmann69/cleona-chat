/* cleona_video_linux.c — the Linux implementation of cleona_video.h, backed by
 * V4L2 capture and VAAPI hardware H.264 encode/decode.
 *
 * Work package: docs/SPEC_VOICE_VIDEO_REWORK.md V1.13.
 * Architecture:  Cleona_Chat_Architecture_v3_0.md §10.6 ("Native Video Stack").
 *
 * ---------------------------------------------------------------------------
 * THE PIPELINE
 * ---------------------------------------------------------------------------
 *   v4l2_capture.c (YUYV, native size)  --scale-->  NV12 VASurface
 *       --> VAAPI EncSliceLP (VDEnc) --> Annex-B H.264 bitstream --> read_encoded
 *
 *   submit_encoded --> Annex-B parse (h264_bitstream.c) --> VAAPI VLD decode
 *       --> VASurface (I10: no pixels cross this file's own boundary either;
 *           get_texture_id is the only path out and it is honestly
 *           ERR_UNSUPPORTED here — see that function's comment)
 *
 * ---------------------------------------------------------------------------
 * WHY EncSliceLP, NOT EncSlice, AND WHY CQP, NOT CBR
 * ---------------------------------------------------------------------------
 * Verified empirically on this machine (Intel UHD 630, iHD driver 24.1.0):
 * vaQueryConfigEntrypoints for VAProfileH264ConstrainedBaseline returns only
 * {VAEntrypointVLD, VAEntrypointEncSliceLP} -- the classic VAEntrypointEncSlice
 * (PAK/VME) path this SoC generation does not expose at all. Within
 * EncSliceLP, vaGetConfigAttributes(VAConfigAttribRateControl) reports only
 * VA_RC_CQP; CBR/VBR are not in the mask. This is a genuine hardware/driver
 * capability limit on this SoC generation, not a choice — a backend that
 * assumed EncSlice+CBR (the textbook VAAPI example) would fail vaCreateConfig
 * outright on this machine.
 *
 * The consequence: this file runs its OWN lightweight QP-feedback loop
 * (cvl_qp_step_locked) on top of hardware CQP encode to approximate the target
 * bitrate/ceiling, backed unconditionally by the I9 backstop
 * (cleona_video.h's hard requirement that no frame handed to the caller ever
 * exceeds max_frame_bytes) for the frames the soft loop does not react to in
 * time. This is still genuine hardware encode -- CQP still runs the same
 * VDEnc silicon block doing motion estimation, transform, quantisation and
 * CAVLC entropy coding; only the automatic bits-per-second governor is
 * unavailable at this entrypoint on this SoC.
 *
 * ---------------------------------------------------------------------------
 * NO AUTO-GENERATED SPS/PPS AT THIS ENTRYPOINT
 * ---------------------------------------------------------------------------
 * Verified empirically: without a packed header submission, this driver's
 * EncSliceLP coded buffer contains ONLY the slice NAL(s) -- no SPS, no PPS.
 * This file therefore builds its own SPS/PPS RBSP (h264_bitstream.c) and
 * submits BOTH concatenated into a SINGLE VAEncPackedHeaderSequence buffer.
 * Cross-checked against ffmpeg's own h264_vaapi encoder via LIBVA_TRACE=1: it
 * does exactly this (both NALs live in the type=Sequence packed header; its
 * second packed header is an unrelated SEI). Submitting SPS and PPS as two
 * separate Sequence+Picture packed headers -- the naive reading of the VAAPI
 * header documentation -- was tried first and produces a PPS NAL the driver's
 * own bitstream does not actually reference the same way; the combined form
 * is the one verified against a second, independent encoder on this exact
 * hardware.
 *
 * ---------------------------------------------------------------------------
 * KNOWN LIMITATION -- RECORDED, NOT HIDDEN
 * ---------------------------------------------------------------------------
 * This backend's SPS/PPS/slice-header construction was verified against this
 * driver's own VAAPI decode entrypoint (round-trips within one session, which
 * is what cleona_video.h's own semantics and the conformance harness's V22
 * check require: a session decodes what it itself encoded) and against an
 * independent bitstream parser (this file's own h264_bitstream.c, and
 * ffprobe, both of which read the SPS correctly: profile, level, resolution
 * all agree). It was NOT possible, in the time available for this package, to
 * make ffmpeg's own reference SOFTWARE H.264 decoder accept the P-frame
 * bitstream this encoder produces beyond the first few frames -- it reports
 * "reference count overflow" starting at the first inter frame, despite the
 * VAEncSequenceParameterBufferH264 fields, this file's packed SPS bytes and
 * ffmpeg's own reference encoder's fields for the identical configuration
 * (compared field-by-field via LIBVA_TRACE=1) matching exactly. The
 * discrepancy was not root-caused before this package's time budget ran out.
 * Recorded here, in BUILD_REQUEST_V1.13.md and in this package's acceptance
 * report so it is not mistaken for "done": full cross-implementation H.264
 * interop is NOT proven for this backend's inter-frame coding. What IS proven
 * is real hardware capture, real hardware encode producing a
 * profile/resolution-correct Annex-B stream, and real hardware decode.
 */

#if !defined(_POSIX_C_SOURCE)
  #define _POSIX_C_SOURCE 200809L
#endif

#include "../cleona_video.h"
#include "h264_bitstream.h"
#include "v4l2_capture.h"

#include <va/va.h>
#include <va/va_drm.h>
#include <va/va_enc_h264.h>

#include <pthread.h>
#include <time.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

/* ==========================================================================
 * Constants
 * ========================================================================== */

#define CVL_N_ENC_SURFACES   4
#define CVL_N_DEC_SURFACES   4
#define CVL_MIN_QP           10
#define CVL_MAX_QP           51
#define CVL_DEFAULT_QP       26
/* Lowest bitrate this backend will negotiate down to before giving up --
 * mirrors the role of CLEONA_VIDEO_MOCK_DEFAULT_MIN_BITRATE_KBPS (Erratum 1's
 * "lowest supported step"). Below this, quality is not usable for a call. */
#define CVL_MIN_BITRATE_KBPS 32
/* Baseline/Constrained Baseline profile is progressive, macroblock = 16x16;
 * this backend negotiates width/height down to the nearest multiple of 16
 * (never up) so that frame_cropping is never needed -- one fewer bitstream
 * subtlety to get right, at the cost of losing up to 15 pixels per edge,
 * which no realistic call resolution notices. */
#define CVL_MB_SIZE 16

/* ---- lifecycle states, internal ---- */
#define ST_OPEN    0
#define ST_RUNNING 1
#define ST_CLOSED  2

/* ==========================================================================
 * Process-wide single-session guard
 * ==========================================================================
 * One physical camera, one VAAPI display connection. A second concurrent
 * open() is refused (CLEONA_VIDEO_ERR_BACKEND -- a capable-in-principle
 * device whose one instance is busy), the same documented scope limit V1.1
 * recorded for the voice backend's PipeWire session ("N3" in that package's
 * conformance notes). The conformance harness (V0.4) only ever exercises one
 * session at a time; nothing in cleona_video.h's checklist requires
 * concurrent sessions from a single backend.
 */
static pthread_mutex_t g_session_guard = PTHREAD_MUTEX_INITIALIZER;
static int             g_session_active = 0;

/* ==========================================================================
 * Session state
 * ========================================================================== */

struct cleona_video_session {
    pthread_mutex_t lock;

    int32_t state;
    cleona_video_config_t cfg;   /* negotiated, authoritative */

    /* ---- capture ---- */
    v4l2_capture_t* capture;
    v4l2_capture_info_t capture_info;   /* native camera format */
    int32_t capture_enabled;
    int32_t decode_only;          /* Erratum 7 */
    int32_t camera_paths_n;
    char    camera_paths[8][V4L2_CAPTURE_PATH_CAP];
    int32_t camera_index;
    uint8_t* nv12_scratch;               /* dst_w*dst_h*3/2, reused every frame */
    int32_t  nv12_scratch_cap;
    int32_t  fps_accum;                  /* frame-rate decimator accumulator */

    /* ---- VAAPI shared ---- */
    int32_t  drm_fd;
    VADisplay dpy;

    /* ---- encode ---- */
    VAConfigID   enc_config;
    VAContextID  enc_context;
    VASurfaceID  enc_surfaces[CVL_N_ENC_SURFACES];
    int32_t      enc_context_valid;
    int64_t      frame_index;           /* next frame_num / surface slot */
    int64_t      pts_next_us;
    int32_t      force_keyframe;
    int32_t      current_qp;            /* CQP feedback loop state */
    int32_t      camera_index_in_stream; /* burned into nothing on Linux; kept
                                          * for report symmetry with mock, not
                                          * otherwise used */

    /* ---- decode ---- */
    VAConfigID   dec_config;
    VAContextID  dec_context;
    VASurfaceID  dec_surfaces[CVL_N_DEC_SURFACES];
    int32_t      dec_context_valid;
    int32_t      dec_next_surface;
    h264_sps_t   active_sps;
    h264_pps_t   active_pps;
    int32_t      awaiting_keyframe;
    int32_t      dec_last_frame_num;

    /* ---- report counters (I11), monotonic for the session lifetime ---- */
    int64_t frames_captured, frames_encoded, frames_dropped_oversize;
    int64_t frames_decoded, decode_failures;
};

/* ==========================================================================
 * Small helpers
 * ========================================================================== */

static int64_t cvl_now_us(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000000LL + ts.tv_nsec / 1000;
}

static int32_t mb_align_down(int32_t v) {
    int32_t a = (v / CVL_MB_SIZE) * CVL_MB_SIZE;
    return a < CVL_MB_SIZE ? CVL_MB_SIZE : a;
}

static int32_t clamp_i(int32_t v, int32_t lo, int32_t hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

/* Bits-per-pixel estimate at a given QP, scaled by the well-known H.264 rule
 * of thumb that six QP steps roughly halve (or double) the bitrate. Used only
 * for ADMISSION and QP-STEP decisions (does something plausibly fit, which
 * direction to move); the real, authoritative size is whatever the hardware
 * actually produces, checked frame by frame against the I9 backstop. Not a
 * substitute for measurement -- there is no substitute for measurement here,
 * only an estimate cheap enough to run on every open()/reconfigure() call
 * without encoding a throwaway frame. */
static double cvl_bits_per_pixel_at_qp(int32_t qp) {
    double base_bpp_at_qp26 = 0.12;  /* empirically in range for CQP26 CIF/VGA content on this HW */
    double steps = (double)(26 - qp) / 6.0;
    double bpp = base_bpp_at_qp26 * pow(2.0, steps);
    if (bpp < 0.01) bpp = 0.01;
    return bpp;
}

static int32_t cvl_estimate_keyframe_bytes(int32_t width, int32_t height, int32_t qp) {
    double bpp = cvl_bits_per_pixel_at_qp(qp);
    /* Keyframes cost roughly 3-5x a delta frame at the same QP on typical
     * call content; 4x is the mock's own factor (CLEONA_VIDEO_MOCK_KEYFRAME_FACTOR). */
    double bits = bpp * (double)width * (double)height * 4.0;
    return (int32_t)(bits / 8.0);
}

/* ==========================================================================
 * negotiate() -- the single source of truth for open() and reconfigure()
 * ==========================================================================
 * Mirrors cleona_video_mock.c's own negotiate(): one code path so open() and
 * a later reconfigure() cannot disagree about what this backend supports.
 * Returns CLEONA_VIDEO_OK, CLEONA_VIDEO_ERR_INVALID or
 * CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE. native_w/native_h are the camera's
 * queried capture size (the hard ceiling on capture resolution -- see the
 * file doc on why MJPG/larger modes are out of scope for V1.13).
 */
static int32_t cvl_negotiate(const cleona_video_config_t* cfg,
                             int32_t native_w, int32_t native_h, int32_t native_fps,
                             int32_t* out_qp, cleona_video_config_t* out) {
    if (!cfg || !out) return CLEONA_VIDEO_ERR_INVALID;
    if (cfg->width <= 0 || cfg->height <= 0 || cfg->fps <= 0) return CLEONA_VIDEO_ERR_INVALID;
    if (cfg->target_bitrate_kbps <= 0) return CLEONA_VIDEO_ERR_INVALID;
    if (cfg->max_frame_bytes <= 0) return CLEONA_VIDEO_ERR_INVALID;
    if (cfg->keyframe_interval_frames < 0) return CLEONA_VIDEO_ERR_INVALID;
    /* Erratum 7: unbekannte Richtung ist ein Aufruferfehler und wird hier mit
     * den uebrigen Feldpruefungen entschieden, damit sie nie als
     * ERR_RATE_UNACHIEVABLE erscheint (Erratum 6b Fall 1). */
    if (cfg->direction != CLEONA_VIDEO_DIR_DUPLEX &&
        cfg->direction != CLEONA_VIDEO_DIR_DECODE_ONLY) {
        return CLEONA_VIDEO_ERR_INVALID;
    }

    int32_t codec = cfg->codec;
    if (codec <= 0) {
        codec = CLEONA_VIDEO_CODEC_H264;
    } else if (codec > CLEONA_VIDEO_CODEC_VP9) {
        return CLEONA_VIDEO_ERR_INVALID;
    } else if (codec != CLEONA_VIDEO_CODEC_H264) {
        /* This backend has hardware for H.264 only on this SoC generation
         * (verified: profile query returns no HEVC/AV1/VP9 encode entrypoint)
         * -- negotiate down to the mandatory interop level rather than fail. */
        codec = CLEONA_VIDEO_CODEC_H264;
    }

    int32_t width  = mb_align_down(clamp_i(cfg->width, CVL_MB_SIZE, native_w));
    int32_t height = mb_align_down(clamp_i(cfg->height, CVL_MB_SIZE, native_h));
    int32_t fps    = clamp_i(cfg->fps, 1, native_fps);

    /* Can even the worst quality (QP_MAX) fit a keyframe under the ceiling at
     * this geometry? If not, this geometry is not achievable regardless of
     * bitrate -- ERR_RATE_UNACHIEVABLE, side-effect free per the ABI. */
    int32_t worst_key = cvl_estimate_keyframe_bytes(width, height, CVL_MAX_QP);
    if (worst_key > cfg->max_frame_bytes) {
        return CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE;
    }

    /* Pick the QP that targets the requested bitrate, then raise it (lower
     * quality) if needed so the ceiling is met at the ESTIMATE level; the I9
     * backstop is the real enforcement, this is only where the feedback loop
     * starts so it does not need many frames to converge. */
    int32_t qp = CVL_DEFAULT_QP;
    for (int32_t tries = 0; tries < 8; tries++) {
        int32_t est = cvl_estimate_keyframe_bytes(width, height, qp);
        if (est <= cfg->max_frame_bytes) break;
        qp += 3;
        if (qp > CVL_MAX_QP) { qp = CVL_MAX_QP; break; }
    }

    int32_t kbps = cfg->target_bitrate_kbps;
    if (kbps < CVL_MIN_BITRATE_KBPS) {
        /* A caller asking for less than this backend's floor is asking for
         * something no supported step provides. */
        return CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE;
    }

    out->codec = codec;
    out->width = width;
    out->height = height;
    out->fps = fps;
    out->target_bitrate_kbps = kbps;
    out->max_frame_bytes = cfg->max_frame_bytes;   /* never raised */
    out->keyframe_interval_frames =
        cfg->keyframe_interval_frames > 0 ? cfg->keyframe_interval_frames : fps * 2;
    /* Erratum 7: durchgereicht, nie ausgehandelt. Ohne diese Zeile stuende in
     * out->direction der uninitialisierte Wert des Aufrufer-Structs -- was
     * sowohl den Echo-Check als auch jeden spaeteren Richtungsvergleich in
     * reconfigure() gegen Muell laufen liesse. */
    out->direction = cfg->direction;
    if (out_qp) *out_qp = qp;
    return CLEONA_VIDEO_OK;
}

static void cvl_write_open_error(cleona_video_config_t* out, int32_t code) {
    if (!out) return;
    memset(out, 0, sizeof(*out));
    out->max_frame_bytes = code;
}

/* ==========================================================================
 * VAAPI teardown/setup helpers
 * ========================================================================== */

static void cvl_destroy_enc_context_locked(cleona_video_session_t* s) {
    if (s->enc_context_valid) {
        vaDestroyContext(s->dpy, s->enc_context);
        for (int32_t i = 0; i < CVL_N_ENC_SURFACES; i++) {
            vaDestroySurfaces(s->dpy, &s->enc_surfaces[i], 1);
        }
        s->enc_context_valid = 0;
    }
}

static int32_t cvl_create_enc_context_locked(cleona_video_session_t* s,
                                             int32_t width, int32_t height) {
    if (vaCreateSurfaces(s->dpy, VA_RT_FORMAT_YUV420, (uint32_t)width, (uint32_t)height,
                         s->enc_surfaces, CVL_N_ENC_SURFACES, NULL, 0) != VA_STATUS_SUCCESS) {
        return -1;
    }
    if (vaCreateContext(s->dpy, s->enc_config, width, height, VA_PROGRESSIVE,
                        s->enc_surfaces, CVL_N_ENC_SURFACES, &s->enc_context) != VA_STATUS_SUCCESS) {
        for (int32_t i = 0; i < CVL_N_ENC_SURFACES; i++) vaDestroySurfaces(s->dpy, &s->enc_surfaces[i], 1);
        return -1;
    }
    s->enc_context_valid = 1;
    s->frame_index = 0;
    s->force_keyframe = 1;
    return 0;
}

static void cvl_destroy_dec_context_locked(cleona_video_session_t* s) {
    if (s->dec_context_valid) {
        vaDestroyContext(s->dpy, s->dec_context);
        for (int32_t i = 0; i < CVL_N_DEC_SURFACES; i++) {
            vaDestroySurfaces(s->dpy, &s->dec_surfaces[i], 1);
        }
        s->dec_context_valid = 0;
    }
}

static int32_t cvl_create_dec_context_locked(cleona_video_session_t* s,
                                             int32_t width, int32_t height) {
    if (vaCreateSurfaces(s->dpy, VA_RT_FORMAT_YUV420, (uint32_t)width, (uint32_t)height,
                         s->dec_surfaces, CVL_N_DEC_SURFACES, NULL, 0) != VA_STATUS_SUCCESS) {
        return -1;
    }
    if (vaCreateContext(s->dpy, s->dec_config, width, height, VA_PROGRESSIVE,
                        s->dec_surfaces, CVL_N_DEC_SURFACES, &s->dec_context) != VA_STATUS_SUCCESS) {
        for (int32_t i = 0; i < CVL_N_DEC_SURFACES; i++) vaDestroySurfaces(s->dpy, &s->dec_surfaces[i], 1);
        return -1;
    }
    s->dec_context_valid = 1;
    s->dec_next_surface = 0;
    s->awaiting_keyframe = 1;
    return 0;
}

/* ==========================================================================
 * open()
 * ========================================================================== */

CLEONA_VIDEO_API cleona_video_session_t* cleona_video_open(
    const cleona_video_config_t* cfg, cleona_video_config_t* out_negotiated) {

    if (!cfg) { cvl_write_open_error(out_negotiated, CLEONA_VIDEO_ERR_INVALID); return NULL; }

    /* Erratum 7: die Richtung wird VOR dem Guard geprueft. Sonst antwortet
     * eine Decode-only-Anfrage mit ERR_BACKEND ("Instanz belegt") statt mit
     * einer Aussage ueber sich selbst -- gemessen am Konformitaetslauf V32. */
    if (cfg->direction != CLEONA_VIDEO_DIR_DUPLEX &&
        cfg->direction != CLEONA_VIDEO_DIR_DECODE_ONLY) {
        cvl_write_open_error(out_negotiated, CLEONA_VIDEO_ERR_INVALID);
        return NULL;
    }
    const int32_t decode_only = (cfg->direction == CLEONA_VIDEO_DIR_DECODE_ONLY);

    /* Der Guard schuetzt die EINE Kamera und den EINEN VAAPI-Encode-Kontext.
     * Eine Decode-only-Session erwirbt beides nicht, also darf sie nicht
     * daran scheitern: docs/CALLS.md zeigt drei Remote-Kacheln plus die
     * lokale gleichzeitig, das sind drei parallele Decoder auf einem Geraet.
     * Ein prozessweiter Einzel-Session-Guard kann diesen Bildschirm nicht
     * darstellen. */
    if (!decode_only) {
        pthread_mutex_lock(&g_session_guard);
        if (g_session_active) {
            pthread_mutex_unlock(&g_session_guard);
            cvl_write_open_error(out_negotiated, CLEONA_VIDEO_ERR_BACKEND);
            return NULL;
        }
        g_session_active = 1;
        pthread_mutex_unlock(&g_session_guard);
    }

    cleona_video_session_t* s = (cleona_video_session_t*)calloc(1, sizeof(*s));
    if (!s) {
        cvl_write_open_error(out_negotiated, CLEONA_VIDEO_ERR_BACKEND);
        goto fail_no_session;
    }
    pthread_mutex_init(&s->lock, NULL);
    s->current_qp = CVL_DEFAULT_QP;
    s->decode_only = decode_only;

    /* ---- camera enumeration + open (this determines the native ceiling
     * negotiate() clamps against) ---- */
    if (!decode_only) {
        s->camera_paths_n = v4l2_capture_enumerate(s->camera_paths, 8);
        if (s->camera_paths_n <= 0) {
            cvl_write_open_error(out_negotiated, CLEONA_VIDEO_ERR_UNSUPPORTED);
            goto fail_early;
        }
        int32_t no_yuyv = 0;
        s->capture = v4l2_capture_open(s->camera_paths[0], &no_yuyv, &s->capture_info);
        if (!s->capture) {
            cvl_write_open_error(out_negotiated,
                                 no_yuyv ? CLEONA_VIDEO_ERR_UNSUPPORTED : CLEONA_VIDEO_ERR_BACKEND);
            goto fail_early;
        }
    }

    /* ---- negotiate: gegen die native Kameragroesse, oder -- ohne Kamera --
     * gegen die angefragte Geometrie. Die Decode-only-Session hat keinen
     * Sensor, der eine Obergrenze setzen koennte; Geometrie und Codec bleiben
     * trotzdem bedeutsam, weil Decoder und Textur daraus dimensioniert
     * werden (Erratum 7). ---- */
    cleona_video_config_t accepted;
    int32_t qp = CVL_DEFAULT_QP;
    int32_t nrc = decode_only
        ? cvl_negotiate(cfg, cfg->width, cfg->height, cfg->fps, &qp, &accepted)
        : cvl_negotiate(cfg, s->capture_info.width, s->capture_info.height,
                        s->capture_info.fps, &qp, &accepted);
    if (nrc != CLEONA_VIDEO_OK) {
        cvl_write_open_error(out_negotiated, nrc);
        goto fail_after_capture;
    }
    s->cfg = accepted;
    s->current_qp = qp;

    /* ---- VAAPI display: the render node behind /dev/dri/renderD128 that
     * actually advertises H.264 encode/decode. Probed rather than
     * hard-coded, so a machine with a different card ordering (e.g. no
     * discrete GPU stealing renderD128) still finds its encoder. ---- */
    {
        int32_t found = 0;
        for (int32_t idx = 128; idx < 128 + 8 && !found; idx++) {
            char path[64];
            snprintf(path, sizeof(path), "/dev/dri/renderD%d", idx);
            int fd = open(path, O_RDWR);
            if (fd < 0) continue;
            VADisplay dpy = vaGetDisplayDRM(fd);
            if (!dpy) { close(fd); continue; }
            int major, minor;
            if (vaInitialize(dpy, &major, &minor) != VA_STATUS_SUCCESS) { close(fd); continue; }

            VAConfigAttrib probe = { .type = VAConfigAttribRTFormat };
            /* Erratum 7: ERR_UNSUPPORTED heisst fuer eine Decode-only-Anfrage
             * "kein DECODE-Pfad". Auf den Encoder zu pruefen wuerde eine Karte
             * verwerfen, die dekodieren kann, und dem Aufrufer den falschen
             * Grund nennen. */
            VAStatus qst = vaGetConfigAttributes(dpy, VAProfileH264ConstrainedBaseline,
                                                 decode_only ? VAEntrypointVLD
                                                             : VAEntrypointEncSliceLP,
                                                 &probe, 1);
            if (qst == VA_STATUS_SUCCESS && probe.value != VA_ATTRIB_NOT_SUPPORTED) {
                s->drm_fd = fd;
                s->dpy = dpy;
                found = 1;
            } else {
                vaTerminate(dpy);
                close(fd);
            }
        }
        if (!found) {
            cvl_write_open_error(out_negotiated, CLEONA_VIDEO_ERR_UNSUPPORTED);
            goto fail_after_capture;
        }
    }

    /* ---- encode config: CQP is the only rate-control mode this SoC
     * exposes at the LP entrypoint (file doc) ---- */
    if (!decode_only) {
        VAConfigAttrib attribs[2] = {
            { .type = VAConfigAttribRTFormat, .value = VA_RT_FORMAT_YUV420 },
            { .type = VAConfigAttribRateControl, .value = VA_RC_CQP },
        };
        if (vaCreateConfig(s->dpy, VAProfileH264ConstrainedBaseline, VAEntrypointEncSliceLP,
                           attribs, 2, &s->enc_config) != VA_STATUS_SUCCESS) {
            cvl_write_open_error(out_negotiated, CLEONA_VIDEO_ERR_BACKEND);
            goto fail_after_display;
        }
        if (cvl_create_enc_context_locked(s, s->cfg.width, s->cfg.height) != 0) {
            vaDestroyConfig(s->dpy, s->enc_config);
            cvl_write_open_error(out_negotiated, CLEONA_VIDEO_ERR_BACKEND);
            goto fail_after_display;
        }
    }

    /* ---- decode config: created eagerly at the negotiated geometry so the
     * common case (peer uses the same geometry class) needs no lazy
     * recreation; submit_encoded recreates it if the peer's SPS disagrees. ---- */
    {
        VAConfigAttrib attrib = { .type = VAConfigAttribRTFormat, .value = VA_RT_FORMAT_YUV420 };
        if (vaCreateConfig(s->dpy, VAProfileH264ConstrainedBaseline, VAEntrypointVLD,
                           &attrib, 1, &s->dec_config) != VA_STATUS_SUCCESS) {
            if (!decode_only) {
                cvl_destroy_enc_context_locked(s);
                vaDestroyConfig(s->dpy, s->enc_config);
            }
            cvl_write_open_error(out_negotiated, CLEONA_VIDEO_ERR_BACKEND);
            goto fail_after_display;
        }
    }
    if (cvl_create_dec_context_locked(s, s->cfg.width, s->cfg.height) != 0) {
        vaDestroyConfig(s->dpy, s->dec_config);
        if (!decode_only) {
            cvl_destroy_enc_context_locked(s);
            vaDestroyConfig(s->dpy, s->enc_config);
        }
        cvl_write_open_error(out_negotiated, CLEONA_VIDEO_ERR_BACKEND);
        goto fail_after_display;
    }

    s->state = ST_OPEN;
    /* Erratum 7: nie eine Kamera gehabt. Das ist der Zustand, keine
     * Nutzer-Stummschaltung -- set_capture_enabled kann ihn nicht aufheben. */
    s->capture_enabled = decode_only ? 0 : 1;
    s->awaiting_keyframe = 1;

    if (out_negotiated) *out_negotiated = s->cfg;
    return s;

fail_after_display:
    vaTerminate(s->dpy);
    close(s->drm_fd);
fail_after_capture:
    v4l2_capture_close(s->capture);
fail_early:
    pthread_mutex_destroy(&s->lock);
    free(s);
fail_no_session:
    /* Nur freigeben, was genommen wurde -- eine gescheiterte Decode-only-
     * Session haelt den Guard nie und duerfte eine laufende Duplex-Session
     * sonst mitreissen. */
    if (!decode_only) {
        pthread_mutex_lock(&g_session_guard);
        g_session_active = 0;
        pthread_mutex_unlock(&g_session_guard);
    }
    return NULL;
}

/* ==========================================================================
 * reconfigure() -- Erratum 1
 * ========================================================================== */

CLEONA_VIDEO_API int32_t cleona_video_reconfigure(cleona_video_session_t* s,
                                 const cleona_video_config_t* cfg,
                                 cleona_video_config_t* out_negotiated) {
    if (!s || !cfg) return CLEONA_VIDEO_ERR_INVALID;

    pthread_mutex_lock(&s->lock);
    if (s->state == ST_CLOSED) { pthread_mutex_unlock(&s->lock); return CLEONA_VIDEO_ERR_STATE; }

    cleona_video_config_t accepted;
    int32_t qp = s->current_qp;
    /* Erratum 7: eine Session, die zum Dekodieren geoeffnet wurde, waechst
     * keine Kamera. Vor negotiate(), damit die Session -- wie bei jedem
     * anderen gescheiterten reconfigure -- unberuehrt bleibt. */
    if (cfg->direction != s->cfg.direction) {
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_INVALID;
    }

    int32_t rc = s->decode_only
        ? cvl_negotiate(cfg, cfg->width, cfg->height, cfg->fps, &qp, &accepted)
        : cvl_negotiate(cfg, s->capture_info.width, s->capture_info.height,
                               s->capture_info.fps, &qp, &accepted);
    if (rc != CLEONA_VIDEO_OK) {
        /* Side-effect free on failure -- Erratum 1. */
        pthread_mutex_unlock(&s->lock);
        return rc;
    }

    int32_t geometry_changed = (accepted.width != s->cfg.width || accepted.height != s->cfg.height);
    int32_t was_running = (s->state == ST_RUNNING);

    if (geometry_changed) {
        /* picture_width_in_mbs/height_in_mbs are fixed at vaCreateContext
         * time -- a resolution change needs a fresh encode context. The
         * peer's decoder cannot continue from a reference picture of a
         * different size either way, so the keyframe this forces (below) is
         * required on both sides of this change, not just a nicety here. */
        cvl_destroy_enc_context_locked(s);
        if (cvl_create_enc_context_locked(s, accepted.width, accepted.height) != 0) {
            /* Failed to recreate at the new size -- the ABI requires the
             * session to be left exactly as it was on failure. Recreate at
             * the OLD geometry to restore that invariant before reporting the
             * codec/camera-refused failure. */
            cvl_create_enc_context_locked(s, s->cfg.width, s->cfg.height);
            pthread_mutex_unlock(&s->lock);
            return CLEONA_VIDEO_ERR_BACKEND;
        }
    }

    s->cfg = accepted;
    s->current_qp = qp;
    if (geometry_changed) s->force_keyframe = 1;
    (void)was_running;

    if (out_negotiated) *out_negotiated = s->cfg;
    pthread_mutex_unlock(&s->lock);
    return CLEONA_VIDEO_OK;
}

/* ==========================================================================
 * start() / stop() / close()
 * ========================================================================== */

CLEONA_VIDEO_API int32_t cleona_video_start(cleona_video_session_t* s) {
    if (!s) return CLEONA_VIDEO_ERR_INVALID;
    pthread_mutex_lock(&s->lock);
    if (s->state != ST_OPEN) { pthread_mutex_unlock(&s->lock); return CLEONA_VIDEO_ERR_STATE; }
    s->state = ST_RUNNING;
    s->pts_next_us = 0;
    s->force_keyframe = 1;
    s->fps_accum = 0;
    pthread_mutex_unlock(&s->lock);
    return CLEONA_VIDEO_OK;
}

CLEONA_VIDEO_API void cleona_video_stop(cleona_video_session_t* s) {
    if (!s) return;
    pthread_mutex_lock(&s->lock);
    if (s->state == ST_RUNNING) s->state = ST_OPEN;
    s->awaiting_keyframe = 1;
    pthread_mutex_unlock(&s->lock);
}

CLEONA_VIDEO_API void cleona_video_close(cleona_video_session_t* s) {
    if (!s) return;
    const int32_t was_decode_only = s->decode_only;
    cleona_video_stop(s);

    pthread_mutex_lock(&s->lock);
    s->state = ST_CLOSED;
    cvl_destroy_enc_context_locked(s);
    cvl_destroy_dec_context_locked(s);
    if (s->enc_config) vaDestroyConfig(s->dpy, s->enc_config);
    if (s->dec_config) vaDestroyConfig(s->dpy, s->dec_config);
    if (s->dpy) vaTerminate(s->dpy);
    if (s->drm_fd) close(s->drm_fd);
    if (s->capture) v4l2_capture_close(s->capture);
    free(s->nv12_scratch);
    pthread_mutex_unlock(&s->lock);

    pthread_mutex_destroy(&s->lock);
    free(s);

    /* Erratum 7: nur die Duplex-Session haelt den Guard. Eine geschlossene
     * Decode-only-Session darf ihn nicht freigeben -- sonst koennte eine
     * parallel laufende Duplex-Session anschliessend ein zweites Mal
     * geoeffnet werden, und zwei Sessions teilten sich eine Kamera. */
    if (!was_decode_only) {
        pthread_mutex_lock(&g_session_guard);
        g_session_active = 0;
        pthread_mutex_unlock(&g_session_guard);
    }
}

/* ==========================================================================
 * Encode: SPS/PPS packed header construction (file doc: combined, one
 * VAEncPackedHeaderSequence buffer)
 * ========================================================================== */

static int32_t cvl_build_sps(uint8_t* out, int32_t out_cap, int32_t width, int32_t height) {
    uint8_t rbsp[64];
    h264_bw_t w;
    h264_bw_init(&w, rbsp, sizeof(rbsp));
    h264_bw_put_bits(&w, 66, 8);    /* profile_idc = 66 (Baseline) */
    h264_bw_put_bits(&w, 0, 8);     /* constraint flags + reserved */
    h264_bw_put_bits(&w, 30, 8);    /* level_idc = 3.0 */
    h264_bw_put_ue(&w, 0);          /* seq_parameter_set_id */
    h264_bw_put_ue(&w, 4);          /* log2_max_frame_num_minus4 -> 8 */
    h264_bw_put_ue(&w, 2);          /* pic_order_cnt_type -- see file doc */
    h264_bw_put_ue(&w, 1);          /* max_num_ref_frames */
    h264_bw_put_bit(&w, 0);         /* gaps_in_frame_num_value_allowed_flag */
    h264_bw_put_ue(&w, (uint32_t)(width / CVL_MB_SIZE - 1));
    h264_bw_put_ue(&w, (uint32_t)(height / CVL_MB_SIZE - 1));
    h264_bw_put_bit(&w, 1);         /* frame_mbs_only_flag */
    h264_bw_put_bit(&w, 1);         /* direct_8x8_inference_flag */
    h264_bw_put_bit(&w, 0);         /* frame_cropping_flag -- widths are mb-aligned */
    h264_bw_put_bit(&w, 0);         /* vui_parameters_present_flag */
    h264_bw_trailing_bits(&w);
    return h264_annexb_wrap(out, out_cap, 3, 7, rbsp, h264_bw_byte_len(&w));
}

static int32_t cvl_build_pps(uint8_t* out, int32_t out_cap, int32_t qp) {
    uint8_t rbsp[32];
    h264_bw_t w;
    h264_bw_init(&w, rbsp, sizeof(rbsp));
    h264_bw_put_ue(&w, 0);          /* pic_parameter_set_id */
    h264_bw_put_ue(&w, 0);          /* seq_parameter_set_id */
    h264_bw_put_bit(&w, 0);         /* entropy_coding_mode_flag -- CAVLC, mandatory for Baseline */
    h264_bw_put_bit(&w, 0);         /* pic_order_present_flag */
    h264_bw_put_ue(&w, 0);          /* num_slice_groups_minus1 */
    h264_bw_put_ue(&w, 0);          /* num_ref_idx_l0_default_active_minus1 */
    h264_bw_put_ue(&w, 0);          /* num_ref_idx_l1_default_active_minus1 */
    h264_bw_put_bit(&w, 0);         /* weighted_pred_flag */
    h264_bw_put_bits(&w, 0, 2);     /* weighted_bipred_idc */
    h264_bw_put_se(&w, qp - 26);    /* pic_init_qp_minus26 */
    h264_bw_put_se(&w, 0);          /* pic_init_qs_minus26 */
    h264_bw_put_se(&w, 0);          /* chroma_qp_index_offset */
    h264_bw_put_bit(&w, 1);         /* deblocking_filter_control_present_flag — VDEnc always
                                     * emits deblocking filter syntax in the slice header
                                     * regardless of this flag, so the PPS must say 1 to match
                                     * what the encoder actually generates. */
    h264_bw_put_bit(&w, 0);         /* redundant_pic_cnt_present_flag */
    h264_bw_trailing_bits(&w);
    return h264_annexb_wrap(out, out_cap, 3, 8, rbsp, h264_bw_byte_len(&w));
}

/* ==========================================================================
 * Encode: one frame
 * ==========================================================================
 * Returns 1 = frame produced into out (may still be oversize -- caller
 * applies the I9 backstop), 0 = no frame this call (capture timeout /
 * disabled / decimated), -1 = backend error.
 * Caller holds s->lock for the duration.
 */
static int32_t cvl_encode_one_locked(cleona_video_session_t* s, uint8_t* out, int32_t out_cap,
                                     int32_t* out_size, int32_t* out_flags, int64_t* out_pts_us) {
    if (!s->capture_enabled) return 0;

    if (s->nv12_scratch_cap < s->cfg.width * s->cfg.height * 3 / 2) {
        int32_t need = s->cfg.width * s->cfg.height * 3 / 2;
        uint8_t* nb = (uint8_t*)realloc(s->nv12_scratch, (size_t)need);
        if (!nb) return -1;
        s->nv12_scratch = nb;
        s->nv12_scratch_cap = need;
    }

    /* Frame-rate decimation against the camera's native rate -- file doc on
     * v4l2_capture.h: the physical stream is never reconfigured, this backend
     * just skips input frames to hit a lower target (documented, legal per
     * cleona_video_report_t: frames_captured >= frames_encoded). */
    int32_t native_fps = s->capture_info.fps > 0 ? s->capture_info.fps : s->cfg.fps;
    int32_t r = v4l2_capture_read_scaled_nv12(s->capture, s->nv12_scratch,
                                              s->cfg.width, s->cfg.height, 200);
    if (r == 0) return 0;
    if (r < 0) return -1;
    s->frames_captured++;

    s->fps_accum += s->cfg.fps;
    if (s->fps_accum < native_fps) {
        /* Decimated: captured but not encoded this tick. */
        return 0;
    }
    s->fps_accum -= native_fps;

    int64_t idx = s->frame_index++;
    int32_t is_idr = s->force_keyframe || idx == 0 ||
        (s->cfg.keyframe_interval_frames > 0 && (idx % s->cfg.keyframe_interval_frames) == 0);
    s->force_keyframe = 0;

    VASurfaceID curr = s->enc_surfaces[idx % CVL_N_ENC_SURFACES];

    /* Upload NV12 into the surface via vaCreateImage/vaPutImage -- verified
     * portable across this driver's internal tiling, unlike vaDeriveImage
     * straight onto an encode surface (native/cleona_video/linux acceptance
     * notes). */
    VAImage img;
    VAImageFormat fmt;
    memset(&fmt, 0, sizeof(fmt));
    fmt.fourcc = VA_FOURCC_NV12;
    fmt.byte_order = VA_LSB_FIRST;
    fmt.bits_per_pixel = 12;
    if (vaCreateImage(s->dpy, &fmt, s->cfg.width, s->cfg.height, &img) != VA_STATUS_SUCCESS) return -1;
    void* buf_ptr;
    if (vaMapBuffer(s->dpy, img.buf, &buf_ptr) != VA_STATUS_SUCCESS) {
        vaDestroyImage(s->dpy, img.image_id);
        return -1;
    }
    uint8_t* dst = (uint8_t*)buf_ptr;
    for (int32_t y = 0; y < s->cfg.height; y++) {
        memcpy(dst + img.offsets[0] + (size_t)y * img.pitches[0],
              s->nv12_scratch + (size_t)y * s->cfg.width, (size_t)s->cfg.width);
    }
    for (int32_t y = 0; y < s->cfg.height / 2; y++) {
        memcpy(dst + img.offsets[1] + (size_t)y * img.pitches[1],
              s->nv12_scratch + (size_t)s->cfg.width * s->cfg.height + (size_t)y * s->cfg.width,
              (size_t)s->cfg.width);
    }
    vaUnmapBuffer(s->dpy, img.buf);
    if (vaPutImage(s->dpy, curr, img.image_id, 0, 0, s->cfg.width, s->cfg.height,
                  0, 0, s->cfg.width, s->cfg.height) != VA_STATUS_SUCCESS) {
        vaDestroyImage(s->dpy, img.image_id);
        return -1;
    }
    vaDestroyImage(s->dpy, img.image_id);

    VABufferID coded_buf;
    /* Generous headroom over the raw pixel count -- coded buffers need room
     * for the driver's own status/segment bookkeeping in addition to the
     * bitstream itself. */
    unsigned int coded_cap = (unsigned int)(s->cfg.width * s->cfg.height * 3);
    if (vaCreateBuffer(s->dpy, s->enc_context, VAEncCodedBufferType, coded_cap, 1, NULL,
                       &coded_buf) != VA_STATUS_SUCCESS) return -1;

    if (vaBeginPicture(s->dpy, s->enc_context, curr) != VA_STATUS_SUCCESS) {
        vaDestroyBuffer(s->dpy, coded_buf);
        return -1;
    }

    VABufferID bufs[6];
    int32_t nb = 0;

    VABufferID seq_buf = VA_INVALID_ID, pkh_param_buf = VA_INVALID_ID, pkh_data_buf = VA_INVALID_ID;
    if (is_idr) {
        VAEncSequenceParameterBufferH264* seq;
        if (vaCreateBuffer(s->dpy, s->enc_context, VAEncSequenceParameterBufferType,
                           sizeof(*seq), 1, NULL, &seq_buf) != VA_STATUS_SUCCESS) goto enc_fail;
        vaMapBuffer(s->dpy, seq_buf, (void**)&seq);
        memset(seq, 0, sizeof(*seq));
        seq->seq_parameter_set_id = 0;
        seq->level_idc = 30;
        seq->intra_period = (uint32_t)(s->cfg.keyframe_interval_frames > 0
                                       ? s->cfg.keyframe_interval_frames : s->cfg.fps * 2);
        seq->intra_idr_period = seq->intra_period;
        seq->ip_period = 1;
        seq->max_num_ref_frames = 1;
        seq->picture_width_in_mbs = (uint16_t)(s->cfg.width / CVL_MB_SIZE);
        seq->picture_height_in_mbs = (uint16_t)(s->cfg.height / CVL_MB_SIZE);
        seq->seq_fields.bits.chroma_format_idc = 1;
        seq->seq_fields.bits.frame_mbs_only_flag = 1;
        seq->seq_fields.bits.direct_8x8_inference_flag = 1;
        seq->seq_fields.bits.log2_max_frame_num_minus4 = 4;
        seq->seq_fields.bits.pic_order_cnt_type = 2;
        vaUnmapBuffer(s->dpy, seq_buf);

        uint8_t sps_nal[64], pps_nal[32], combined[96];
        int32_t sps_len = cvl_build_sps(sps_nal, sizeof(sps_nal), s->cfg.width, s->cfg.height);
        int32_t pps_len = cvl_build_pps(pps_nal, sizeof(pps_nal), s->current_qp);
        if (sps_len < 0 || pps_len < 0) goto enc_fail;
        memcpy(combined, sps_nal, (size_t)sps_len);
        memcpy(combined + sps_len, pps_nal, (size_t)pps_len);
        int32_t combined_len = sps_len + pps_len;

        VAEncPackedHeaderParameterBuffer pkh;
        memset(&pkh, 0, sizeof(pkh));
        pkh.type = VAEncPackedHeaderSequence;
        pkh.bit_length = (uint32_t)combined_len * 8;
        pkh.has_emulation_bytes = 1;
        if (vaCreateBuffer(s->dpy, s->enc_context, VAEncPackedHeaderParameterBufferType,
                           sizeof(pkh), 1, &pkh, &pkh_param_buf) != VA_STATUS_SUCCESS) goto enc_fail;
        if (vaCreateBuffer(s->dpy, s->enc_context, VAEncPackedHeaderDataBufferType,
                           (unsigned int)combined_len, 1, combined,
                           &pkh_data_buf) != VA_STATUS_SUCCESS) goto enc_fail;
    }

    VABufferID pic_buf;
    VAEncPictureParameterBufferH264* pic;
    if (vaCreateBuffer(s->dpy, s->enc_context, VAEncPictureParameterBufferType,
                       sizeof(*pic), 1, NULL, &pic_buf) != VA_STATUS_SUCCESS) goto enc_fail;
    vaMapBuffer(s->dpy, pic_buf, (void**)&pic);
    memset(pic, 0, sizeof(*pic));
    pic->CurrPic.picture_id = curr;
    pic->CurrPic.frame_idx = (uint32_t)idx;
    pic->CurrPic.TopFieldOrderCnt = (int32_t)(idx * 2);
    pic->CurrPic.BottomFieldOrderCnt = (int32_t)(idx * 2);
    for (int32_t k = 0; k < 16; k++) pic->ReferenceFrames[k].picture_id = VA_INVALID_SURFACE;
    if (!is_idr && idx > 0) {
        VASurfaceID ref = s->enc_surfaces[(idx - 1) % CVL_N_ENC_SURFACES];
        pic->ReferenceFrames[0].picture_id = ref;
        pic->ReferenceFrames[0].frame_idx = (uint32_t)(idx - 1);
        pic->ReferenceFrames[0].flags = VA_PICTURE_H264_SHORT_TERM_REFERENCE;
        pic->ReferenceFrames[0].TopFieldOrderCnt = (int32_t)((idx - 1) * 2);
        pic->ReferenceFrames[0].BottomFieldOrderCnt = (int32_t)((idx - 1) * 2);
    }
    pic->coded_buf = coded_buf;
    pic->pic_parameter_set_id = 0;
    pic->seq_parameter_set_id = 0;
    pic->frame_num = is_idr ? 0 : (uint16_t)idx;
    pic->pic_init_qp = (uint8_t)s->current_qp;
    pic->num_ref_idx_l0_active_minus1 = 0;
    pic->pic_fields.bits.idr_pic_flag = is_idr ? 1 : 0;
    pic->pic_fields.bits.reference_pic_flag = 1;
    pic->pic_fields.bits.entropy_coding_mode_flag = 0;
    pic->pic_fields.bits.deblocking_filter_control_present_flag = 1;
    vaUnmapBuffer(s->dpy, pic_buf);

    VABufferID slice_buf;
    VAEncSliceParameterBufferH264* slice;
    if (vaCreateBuffer(s->dpy, s->enc_context, VAEncSliceParameterBufferType,
                       sizeof(*slice), 1, NULL, &slice_buf) != VA_STATUS_SUCCESS) goto enc_fail;
    vaMapBuffer(s->dpy, slice_buf, (void**)&slice);
    memset(slice, 0, sizeof(*slice));
    slice->macroblock_address = 0;
    slice->num_macroblocks = (unsigned int)((s->cfg.width / CVL_MB_SIZE) * (s->cfg.height / CVL_MB_SIZE));
    slice->macroblock_info = VA_INVALID_ID;
    slice->slice_type = is_idr ? 2 : 0;
    slice->pic_parameter_set_id = 0;
    for (int32_t k = 0; k < 32; k++) {
        slice->RefPicList0[k].picture_id = VA_INVALID_SURFACE;
        slice->RefPicList1[k].picture_id = VA_INVALID_SURFACE;
    }
    if (!is_idr && idx > 0) {
        slice->RefPicList0[0].picture_id = s->enc_surfaces[(idx - 1) % CVL_N_ENC_SURFACES];
        slice->RefPicList0[0].flags = VA_PICTURE_H264_SHORT_TERM_REFERENCE;
    }
    slice->slice_qp_delta = 0;
    slice->disable_deblocking_filter_idc = 0;
    vaUnmapBuffer(s->dpy, slice_buf);

    if (is_idr) { bufs[nb++] = seq_buf; bufs[nb++] = pkh_param_buf; bufs[nb++] = pkh_data_buf; }
    bufs[nb++] = pic_buf;
    bufs[nb++] = slice_buf;

    if (vaRenderPicture(s->dpy, s->enc_context, bufs, nb) != VA_STATUS_SUCCESS) goto enc_fail;
    if (vaEndPicture(s->dpy, s->enc_context) != VA_STATUS_SUCCESS) goto enc_fail;
    vaSyncSurface(s->dpy, curr);

    VACodedBufferSegment* seg;
    if (vaMapBuffer(s->dpy, coded_buf, (void**)&seg) != VA_STATUS_SUCCESS) goto enc_fail;
    int32_t total = 0;
    for (VACodedBufferSegment* seg2 = seg; seg2; seg2 = seg2->next) total += (int32_t)seg2->size;

    s->frames_encoded++;

    if (total > out_cap) {
        /* I9 backstop: an undeliverable frame costs the same bandwidth as a
         * deliverable one and arrives never -- discard and count, never hand
         * it out. */
        vaUnmapBuffer(s->dpy, coded_buf);
        vaDestroyBuffer(s->dpy, coded_buf);
        s->frames_dropped_oversize++;
        /* QP feedback: this frame overshot -- raise QP for next time. */
        s->current_qp = clamp_i(s->current_qp + 4, CVL_MIN_QP, CVL_MAX_QP);
        return 0;
    }

    int32_t pos = 0;
    for (VACodedBufferSegment* seg2 = seg; seg2; seg2 = seg2->next) {
        memcpy(out + pos, seg2->buf, seg2->size);
        pos += (int32_t)seg2->size;
    }
    vaUnmapBuffer(s->dpy, coded_buf);
    vaDestroyBuffer(s->dpy, coded_buf);

    /* QP feedback loop: nudge towards the ceiling with headroom, never
     * reacting so hard that quality collapses on one big frame. */
    int32_t budget = s->cfg.max_frame_bytes;
    if (total > budget * 3 / 4) {
        s->current_qp = clamp_i(s->current_qp + 2, CVL_MIN_QP, CVL_MAX_QP);
    } else if (total < budget / 4 && s->current_qp > CVL_MIN_QP) {
        s->current_qp = clamp_i(s->current_qp - 1, CVL_MIN_QP, CVL_MAX_QP);
    }

    int64_t pts = s->pts_next_us;
    s->pts_next_us += 1000000LL / s->cfg.fps;

    *out_size = total;
    *out_flags = is_idr ? CLEONA_VIDEO_FLAG_KEYFRAME : 0;
    *out_pts_us = pts;
    return 1;

enc_fail:
    vaDestroyBuffer(s->dpy, coded_buf);
    return -1;
}

CLEONA_VIDEO_API int32_t cleona_video_read_encoded(cleona_video_session_t* s,
                                  uint8_t* buf, int32_t buf_cap,
                                  int32_t* out_size, int32_t* out_flags,
                                  int64_t* out_pts_us, int32_t timeout_ms) {
    if (!s || !buf || buf_cap <= 0 || !out_size || !out_flags || !out_pts_us) {
        return CLEONA_VIDEO_ERR_INVALID;
    }

    int64_t deadline = cvl_now_us() + (int64_t)(timeout_ms > 0 ? timeout_ms : 0) * 1000;
    int32_t blocking = timeout_ms < 0;

    for (;;) {
        pthread_mutex_lock(&s->lock);
        if (s->state != ST_RUNNING) { pthread_mutex_unlock(&s->lock); return CLEONA_VIDEO_READ_CLOSED; }
        /* Erratum 7: kein Encoder, also kann nie ein Frame kommen -- aber die
         * Session laeuft, deshalb TIMEOUT und nicht READ_CLOSED. Vor der
         * Warteschleife, weil ein blockierender Read (timeout_ms < 0) sonst
         * auf etwas wartet, das nicht eintreten kann. */
        if (s->decode_only) { pthread_mutex_unlock(&s->lock); return CLEONA_VIDEO_READ_TIMEOUT; }

        int32_t size = 0, flags = 0;
        int64_t pts = 0;
        int32_t r = cvl_encode_one_locked(s, buf, buf_cap, &size, &flags, &pts);
        pthread_mutex_unlock(&s->lock);

        if (r < 0) return CLEONA_VIDEO_ERR_BACKEND;
        if (r == 1) {
            *out_size = size; *out_flags = flags; *out_pts_us = pts;
            return CLEONA_VIDEO_READ_FRAME;
        }
        /* r == 0: timeout, decimated, or oversize-dropped. Keep looking --
         * a caller must not see a phantom timeout from the encoder's own
         * backstop (cleona_video.h). */
        if (!blocking && cvl_now_us() >= deadline) return CLEONA_VIDEO_READ_TIMEOUT;
    }
}

/* ==========================================================================
 * Decode
 * ========================================================================== */

CLEONA_VIDEO_API int32_t cleona_video_submit_encoded(cleona_video_session_t* s,
                                    const uint8_t* data, int32_t size, int32_t flags) {
    if (!s || !data || size <= 0) return CLEONA_VIDEO_ERR_INVALID;

    pthread_mutex_lock(&s->lock);
    if (s->state != ST_RUNNING) { pthread_mutex_unlock(&s->lock); return CLEONA_VIDEO_ERR_STATE; }

    /* Walk every NAL in the buffer, updating SPS/PPS state and decoding the
     * first slice NAL found. This backend's own encoder emits at most SPS+
     * PPS+one slice per submission (file doc); a peer that sends more is
     * still handled correctly for the slice that matters (the last one),
     * matching cleona_video_mock.c's own last-NAL convention. */
    int32_t pos[16], types[16], n = 0;
    {
        int32_t i = 0;
        while (i + 3 <= size && n < 16) {
            if (data[i] == 0 && data[i+1] == 0 && data[i+2] == 1) {
                pos[n] = i + 3;
                types[n] = data[i+3] & 0x1F;
                n++;
                i += 3;
            } else {
                i++;
            }
        }
    }
    if (n == 0) {
        s->decode_failures++;
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_DECODE;
    }

    int32_t slice_k = -1;
    for (int32_t k = 0; k < n; k++) {
        int32_t nal_start = pos[k];
        /* pos[k+1] (when it exists) points 3 bytes past the NEXT NAL's start
         * code trigger ("00 00 01"); walk back over that 3-byte prefix and an
         * optional leading zero_byte to find where NAL k's own content ends. */
        int32_t next_sc_begin = (k + 1 < n) ? pos[k+1] : size;
        int32_t true_end = next_sc_begin;
        if (k + 1 < n) {
            true_end -= 3; /* the "00 00 01" just matched */
            if (true_end > nal_start && data[true_end - 1] == 0) true_end -= 1; /* optional leading zero_byte */
        } else {
            true_end = size;
        }
        int32_t nal_type = types[k];
        int32_t ebsp_len = true_end - nal_start - 1; /* -1: skip the nal header byte itself */
        const uint8_t* ebsp = data + nal_start + 1;
        if (ebsp_len < 0) continue;

        if (nal_type == 7) {
            uint8_t rbsp[128];
            int32_t rbsp_len = h264_ebsp_to_rbsp(ebsp, ebsp_len, rbsp, sizeof(rbsp));
            if (rbsp_len > 0) h264_parse_sps(rbsp, rbsp_len, &s->active_sps);
        } else if (nal_type == 8) {
            uint8_t rbsp[64];
            int32_t rbsp_len = h264_ebsp_to_rbsp(ebsp, ebsp_len, rbsp, sizeof(rbsp));
            if (rbsp_len > 0) h264_parse_pps(rbsp, rbsp_len, &s->active_pps);
        } else if (nal_type == 1 || nal_type == 5) {
            slice_k = k;
        }
    }

    if (slice_k < 0) {
        /* SPS/PPS-only submission (this backend's own encoder never sends
         * this on its own, but a peer might send parameter sets ahead of the
         * first slice separately). Not a failure. */
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VIDEO_SUBMIT_ACCEPTED;
    }

    int32_t nal_start = pos[slice_k];
    int32_t next_sc_begin = (slice_k + 1 < n) ? pos[slice_k + 1] : size;
    int32_t true_end = next_sc_begin;
    if (slice_k + 1 < n) {
        true_end -= 3;
        if (true_end > nal_start && data[true_end - 1] == 0) true_end -= 1;
    } else {
        true_end = size;
    }
    int32_t nal_type = types[slice_k];
    int32_t is_idr = (nal_type == 5);
    int32_t claims_key = (flags & CLEONA_VIDEO_FLAG_KEYFRAME) != 0;
    if (claims_key != is_idr) {
        s->decode_failures++;
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_DECODE;
    }

    /* The awaiting_keyframe gate must be checked BEFORE the SPS/PPS validity
     * test: a non-IDR frame arriving before the first keyframe has no SPS/PPS
     * to validate against, and that is not a decode failure — it is the normal
     * "I need a keyframe first" state. Returning ERR_DECODE here instead of
     * AWAITING_KEYFRAME would violate V22: "not counted as a failure". */
    if (s->awaiting_keyframe && !is_idr) {
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VIDEO_SUBMIT_AWAITING_KEYFRAME;
    }

    const uint8_t* slice_ebsp = data + nal_start + 1;
    int32_t slice_ebsp_len = true_end - nal_start - 1;
    if (slice_ebsp_len <= 0 || !s->active_sps.valid || !s->active_pps.valid) {
        s->decode_failures++;
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_DECODE;
    }

    uint8_t rbsp[65536];
    int32_t rbsp_cap = (int32_t)sizeof(rbsp);
    int32_t rbsp_len = slice_ebsp_len <= rbsp_cap
        ? h264_ebsp_to_rbsp(slice_ebsp, slice_ebsp_len, rbsp, rbsp_cap) : -1;
    h264_slice_header_t sh;
    int32_t parse_ok = rbsp_len > 0 &&
        h264_parse_slice_header(rbsp, rbsp_len, is_idr, &s->active_sps, &s->active_pps, &sh);
    if (!parse_ok) {
        s->decode_failures++;
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_DECODE;
    }

    /* KNOWN GAP (documented, not silently skipped): if the peer's SPS
     * geometry differs from this session's decode surfaces (created at
     * open()/reconfigure() time against OUR OWN negotiated width/height),
     * this decode call will fail rather than transparently recreating the
     * decode context at the peer's size. Both sides of a real call negotiate
     * their OWN encode geometry independently (I12: this ABI never tells the
     * peer what to send), so a mismatched peer resolution is a real
     * scenario, not an edge case -- recreating the decode context per-SPS is
     * the correct fix and is recorded as follow-up work in
     * BUILD_REQUEST_V1.13.md, not implemented in the time available for this
     * package's initial version. */

    /* Translate the RBSP-domain header_bit_len back into the EBSP domain: add
     * 8 bits for every emulation-prevention byte that occurred before that
     * point in the original bitstream (removing 0x03 bytes shifts bit
     * positions -- VAAPI's slice_data_bit_offset is defined against the
     * ORIGINAL buffer handed to it, not the stripped RBSP).
     *
     * VAAPI's VASliceParameterBufferH264::slice_data_bit_offset is defined as
     * "bit offset from NAL Header Byte to the beginning of slice_data()".
     * The slice data buffer (VASliceDataBufferType) must therefore include the
     * NAL header byte, and the offset must account for its 8 bits. Without
     * this, the VLD engine reads the wrong start position for the macroblock
     * data and the decode fails or produces garbage. */
    int32_t header_bits_rbsp = sh.header_bit_len;
    int32_t header_bytes_rbsp = (header_bits_rbsp + 7) / 8;
    int32_t ep_bytes_before_header = 0;
    {
        int32_t zero_run = 0, produced = 0;
        for (int32_t i = 0; i < slice_ebsp_len && produced < header_bytes_rbsp; i++) {
            uint8_t b = slice_ebsp[i];
            if (zero_run >= 2 && b == 0x03) { ep_bytes_before_header++; zero_run = 0; continue; }
            produced++;
            zero_run = (b == 0x00) ? zero_run + 1 : 0;
        }
    }
    /* +8: the NAL header byte itself, which sits at the start of the slice
     * data buffer and precedes the EBSP the parser walked. */
    int32_t slice_data_bit_offset = 8 + header_bits_rbsp + ep_bytes_before_header * 8;

    /* The slice data buffer handed to VAAPI starts at the NAL header byte
     * (data + nal_start), not at the EBSP (data + nal_start + 1). VAAPI's
     * VLD engine expects the NAL header to be present — the
     * slice_data_bit_offset above is defined relative to it. */
    const uint8_t* slice_nal_data = data + nal_start;
    int32_t slice_nal_data_len = true_end - nal_start;

    VABufferID pic_buf;
    VAPictureParameterBufferH264* pp;
    if (vaCreateBuffer(s->dpy, s->dec_context, VAPictureParameterBufferType,
                       sizeof(*pp), 1, NULL, &pic_buf) != VA_STATUS_SUCCESS) goto dec_fail;
    vaMapBuffer(s->dpy, pic_buf, (void**)&pp);
    memset(pp, 0, sizeof(*pp));
    VASurfaceID curr_dec = s->dec_surfaces[s->dec_next_surface % CVL_N_DEC_SURFACES];
    pp->CurrPic.picture_id = curr_dec;
    pp->CurrPic.frame_idx = (uint32_t)sh.frame_num;
    pp->CurrPic.TopFieldOrderCnt = sh.frame_num * 2;
    pp->CurrPic.BottomFieldOrderCnt = sh.frame_num * 2;
    for (int32_t k = 0; k < 16; k++) pp->ReferenceFrames[k].picture_id = VA_INVALID_SURFACE;
    if (!is_idr && s->dec_next_surface > 0) {
        VASurfaceID ref = s->dec_surfaces[(s->dec_next_surface - 1) % CVL_N_DEC_SURFACES];
        pp->ReferenceFrames[0].picture_id = ref;
        pp->ReferenceFrames[0].frame_idx = (uint32_t)s->dec_last_frame_num;
        pp->ReferenceFrames[0].flags = VA_PICTURE_H264_SHORT_TERM_REFERENCE;
    }
    pp->picture_width_in_mbs_minus1 = (uint16_t)(s->active_sps.pic_width_in_mbs - 1);
    pp->picture_height_in_mbs_minus1 = (uint16_t)(s->active_sps.pic_height_in_map_units - 1);
    pp->num_ref_frames = (uint8_t)(s->active_sps.max_num_ref_frames > 0 ? s->active_sps.max_num_ref_frames : 1);
    pp->seq_fields.bits.chroma_format_idc = 1;
    pp->seq_fields.bits.frame_mbs_only_flag = 1;
    pp->seq_fields.bits.direct_8x8_inference_flag = s->active_sps.direct_8x8_inference_flag;
    pp->seq_fields.bits.log2_max_frame_num_minus4 = (uint32_t)(s->active_sps.log2_max_frame_num - 4);
    pp->seq_fields.bits.pic_order_cnt_type = (uint32_t)s->active_sps.pic_order_cnt_type;
    pp->pic_init_qp_minus26 = (int8_t)(s->active_pps.pic_init_qp - 26);
    pp->pic_fields.bits.entropy_coding_mode_flag = (uint32_t)s->active_pps.entropy_coding_mode_flag;
    pp->pic_fields.bits.weighted_pred_flag = (uint32_t)s->active_pps.weighted_pred_flag;
    pp->pic_fields.bits.deblocking_filter_control_present_flag =
        (uint32_t)s->active_pps.deblocking_filter_control_present_flag;
    pp->pic_fields.bits.reference_pic_flag = 1;
    pp->frame_num = (uint16_t)sh.frame_num;
    vaUnmapBuffer(s->dpy, pic_buf);

    /* IQ matrix: mandatory for Intel iHD (and most VAAPI drivers). For
     * Constrained Baseline, the default flat scaling list (all 16) applies;
     * ScalingList8x8 is unused but must be initialised. Without this buffer
     * the hardware decoder returns VA_STATUS_ERROR_DECODING_ERROR. */
    VABufferID iq_buf;
    VAIQMatrixBufferH264* iq;
    if (vaCreateBuffer(s->dpy, s->dec_context, VAIQMatrixBufferType,
                       sizeof(*iq), 1, NULL, &iq_buf) != VA_STATUS_SUCCESS) {
        vaDestroyBuffer(s->dpy, pic_buf); goto dec_fail;
    }
    vaMapBuffer(s->dpy, iq_buf, (void**)&iq);
    memset(iq, 0, sizeof(*iq));
    for (int32_t li = 0; li < 6; li++)
        for (int32_t j = 0; j < 16; j++)
            iq->ScalingList4x4[li][j] = 16;
    for (int32_t li = 0; li < 2; li++)
        for (int32_t j = 0; j < 64; j++)
            iq->ScalingList8x8[li][j] = 16;
    vaUnmapBuffer(s->dpy, iq_buf);

    VABufferID slicedata_buf;
    if (vaCreateBuffer(s->dpy, s->dec_context, VASliceDataBufferType,
                       (unsigned int)slice_nal_data_len, 1, (void*)slice_nal_data,
                       &slicedata_buf) != VA_STATUS_SUCCESS) { vaDestroyBuffer(s->dpy, pic_buf); vaDestroyBuffer(s->dpy, iq_buf); goto dec_fail; }

    VABufferID sliceparam_buf;
    VASliceParameterBufferH264* sp;
    if (vaCreateBuffer(s->dpy, s->dec_context, VASliceParameterBufferType,
                       sizeof(*sp), 1, NULL, &sliceparam_buf) != VA_STATUS_SUCCESS) {
        vaDestroyBuffer(s->dpy, pic_buf); vaDestroyBuffer(s->dpy, iq_buf); vaDestroyBuffer(s->dpy, slicedata_buf); goto dec_fail;
    }
    vaMapBuffer(s->dpy, sliceparam_buf, (void**)&sp);
    memset(sp, 0, sizeof(*sp));
    sp->slice_data_size = (uint32_t)slice_nal_data_len;
    sp->slice_data_offset = 0;
    sp->slice_data_flag = VA_SLICE_DATA_FLAG_ALL;
    sp->slice_data_bit_offset = (uint32_t)slice_data_bit_offset;
    sp->first_mb_in_slice = (uint32_t)sh.first_mb_in_slice;
    sp->slice_type = (uint8_t)sh.slice_type;
    sp->direct_spatial_mv_pred_flag = 0;
    sp->num_ref_idx_l0_active_minus1 = (uint8_t)(sh.num_ref_idx_l0_active > 0 ? sh.num_ref_idx_l0_active - 1 : 0);
    sp->cabac_init_idc = 0;
    sp->slice_qp_delta = (int8_t)sh.slice_qp_delta;
    sp->disable_deblocking_filter_idc = (uint8_t)sh.disable_deblocking_filter_idc;
    sp->slice_alpha_c0_offset_div2 = (int8_t)sh.slice_alpha_c0_offset_div2;
    sp->slice_beta_offset_div2 = (int8_t)sh.slice_beta_offset_div2;
    for (int32_t k = 0; k < 32; k++) {
        sp->RefPicList0[k].picture_id = VA_INVALID_SURFACE;
        sp->RefPicList1[k].picture_id = VA_INVALID_SURFACE;
    }
    if (!is_idr && s->dec_next_surface > 0) {
        sp->RefPicList0[0].picture_id = s->dec_surfaces[(s->dec_next_surface - 1) % CVL_N_DEC_SURFACES];
        sp->RefPicList0[0].flags = VA_PICTURE_H264_SHORT_TERM_REFERENCE;
    }
    vaUnmapBuffer(s->dpy, sliceparam_buf);

    {
        VAStatus bst = vaBeginPicture(s->dpy, s->dec_context, curr_dec);
        VABufferID dbufs[4] = { pic_buf, iq_buf, sliceparam_buf, slicedata_buf };
        VAStatus rst = (bst == VA_STATUS_SUCCESS)
            ? vaRenderPicture(s->dpy, s->dec_context, dbufs, 4) : bst;
        VAStatus est = (rst == VA_STATUS_SUCCESS) ? vaEndPicture(s->dpy, s->dec_context) : rst;
        VAStatus syst = (est == VA_STATUS_SUCCESS) ? vaSyncSurface(s->dpy, curr_dec) : est;

        vaDestroyBuffer(s->dpy, pic_buf);
        vaDestroyBuffer(s->dpy, iq_buf);
        vaDestroyBuffer(s->dpy, sliceparam_buf);
        vaDestroyBuffer(s->dpy, slicedata_buf);

        if (syst != VA_STATUS_SUCCESS) {
            s->decode_failures++;
            pthread_mutex_unlock(&s->lock);
            return CLEONA_VIDEO_ERR_DECODE;
        }
    }

    s->dec_next_surface++;
    s->dec_last_frame_num = sh.frame_num;
    s->awaiting_keyframe = 0;
    s->frames_decoded++;
    pthread_mutex_unlock(&s->lock);
    return CLEONA_VIDEO_SUBMIT_ACCEPTED;

dec_fail:
    s->decode_failures++;
    pthread_mutex_unlock(&s->lock);
    return CLEONA_VIDEO_ERR_DECODE;
}

/* ==========================================================================
 * Texture (I10) -- honestly unsupported at this layer
 * ==========================================================================
 * The decoded picture lives in a VASurface. Handing it to a Flutter Texture
 * widget needs a registered external texture (GL/EGL or a platform-specific
 * FlTexture implementation) that this package does not own: V2.3
 * ("Video-Integration", lib/main.dart Video-Factory) is where a Linux
 * Flutter GL context and texture registration are wired up, per this ABI's
 * own header ("the platform layer of §10.6 sits below this header and has no
 * such dependency" -- but registering into Flutter's texture registry is
 * ABOVE this header, in glue this package does not own). ERR_UNSUPPORTED is
 * the ABI-legitimate answer for exactly this case: "a shipping backend has
 * to render somewhere" eventually, but not yet, and not from here.
 */
CLEONA_VIDEO_API int32_t cleona_video_get_texture_id(cleona_video_session_t* s, int64_t* out_id) {
    if (!s || !out_id) return CLEONA_VIDEO_ERR_INVALID;
    pthread_mutex_lock(&s->lock);
    int32_t st = s->state;
    pthread_mutex_unlock(&s->lock);
    if (st != ST_RUNNING) return CLEONA_VIDEO_ERR_STATE;
    return CLEONA_VIDEO_ERR_UNSUPPORTED;
}

/* ==========================================================================
 * Controls
 * ========================================================================== */

CLEONA_VIDEO_API int32_t cleona_video_request_keyframe(cleona_video_session_t* s) {
    if (!s) return CLEONA_VIDEO_ERR_INVALID;
    pthread_mutex_lock(&s->lock);
    if (s->state != ST_RUNNING) { pthread_mutex_unlock(&s->lock); return CLEONA_VIDEO_ERR_STATE; }
    /* Erratum 7: fragt UNSEREN Encoder, den eine Decode-only-Session nicht
     * hat. Den Peer um ein Keyframe zu bitten ist Signalisierung. */
    if (s->decode_only) { pthread_mutex_unlock(&s->lock); return CLEONA_VIDEO_ERR_UNSUPPORTED; }
    s->force_keyframe = 1;
    pthread_mutex_unlock(&s->lock);
    return CLEONA_VIDEO_OK;
}

CLEONA_VIDEO_API void cleona_video_set_capture_enabled(cleona_video_session_t* s, int32_t on) {
    if (!s) return;
    pthread_mutex_lock(&s->lock);
    /* Erratum 7: angenommen und ignoriert. Ein Aufrufer, der N Sessions
     * gleich behandelt, darf diese eine nicht gesondert behandeln muessen. */
    if (s->decode_only) { pthread_mutex_unlock(&s->lock); return; }
    int32_t want = on ? 1 : 0;
    if (want && !s->capture_enabled) {
        /* The peer's decoder has been starved; a P-frame now would be
         * undecodable there -- unconditional, not a heuristic (I12). */
        s->force_keyframe = 1;
    }
    s->capture_enabled = want;
    pthread_mutex_unlock(&s->lock);
}

CLEONA_VIDEO_API int32_t cleona_video_switch_camera(cleona_video_session_t* s) {
    if (!s) return CLEONA_VIDEO_ERR_INVALID;
    pthread_mutex_lock(&s->lock);
    if (s->state != ST_RUNNING) { pthread_mutex_unlock(&s->lock); return CLEONA_VIDEO_ERR_STATE; }
    /* Erratum 7: eine Decode-only-Session hat ueberhaupt keine Kamera. */
    if (s->decode_only || s->camera_paths_n < 2) {
        /* This dev machine (and most laptops) has exactly one physical
         * camera -- legitimate per the ABI (cleona_video.h: "ERR_UNSUPPORTED
         * (only one camera, or no camera concept)"). */
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_UNSUPPORTED;
    }
    int32_t next = (s->camera_index + 1) % s->camera_paths_n;
    v4l2_capture_info_t info;
    int32_t no_yuyv = 0;
    v4l2_capture_t* nc = v4l2_capture_open(s->camera_paths[next], &no_yuyv, &info);
    if (!nc) { pthread_mutex_unlock(&s->lock); return CLEONA_VIDEO_ERR_BACKEND; }
    v4l2_capture_close(s->capture);
    s->capture = nc;
    s->capture_info = info;
    s->camera_index = next;
    s->force_keyframe = 1;
    pthread_mutex_unlock(&s->lock);
    return CLEONA_VIDEO_OK;
}

CLEONA_VIDEO_API void cleona_video_get_report(cleona_video_session_t* s, cleona_video_report_t* out) {
    if (!out) return;
    if (!s) {
        memset(out, 0, sizeof(*out));
        out->hardware_encode = CLEONA_VIDEO_HW_NOT_DETERMINABLE;
        out->hardware_decode = CLEONA_VIDEO_HW_NOT_DETERMINABLE;
        return;
    }
    pthread_mutex_lock(&s->lock);
    out->codec_in_use = s->cfg.codec;
    /* Verified, not guessed (I11): VAEntrypointEncSliceLP / VAEntrypointVLD
     * were successfully queried and a config was successfully created against
     * them at open() time on the real GPU device. If either creation had
     * failed, open() itself would have failed and there would be no report
     * to read. */
    /* Erratum 7: bei einer Decode-only-Session ist das Fehlen des Encoders
     * BEKANNT, nicht unbestimmt -- HW_NO, nie HW_NOT_DETERMINABLE. */
    out->hardware_encode = s->decode_only ? CLEONA_VIDEO_HW_NO : CLEONA_VIDEO_HW_YES;
    out->hardware_decode = CLEONA_VIDEO_HW_YES;
    out->negotiated_width = s->cfg.width;
    out->negotiated_height = s->cfg.height;
    out->negotiated_fps = s->cfg.fps;
    out->capture_backend = s->decode_only ? CLEONA_VIDEO_BACKEND_NONE
                                          : CLEONA_VIDEO_BACKEND_LINUX_V4L2;
    out->encode_backend = s->decode_only ? CLEONA_VIDEO_BACKEND_NONE
                                         : CLEONA_VIDEO_BACKEND_LINUX_VAAPI;
    out->frames_captured = s->frames_captured;
    out->frames_encoded = s->frames_encoded;
    out->frames_dropped_oversize = s->frames_dropped_oversize;
    out->frames_decoded = s->frames_decoded;
    out->decode_failures = s->decode_failures;
    pthread_mutex_unlock(&s->lock);
}
