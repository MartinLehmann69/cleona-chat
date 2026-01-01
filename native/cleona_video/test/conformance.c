/* conformance.c — the video conformance test every backend must pass.
 *
 * Work package: docs/SPEC_VOICE_VIDEO_REWORK.md V0.4.
 * Architecture: Cleona_Chat_Architecture_v3_0.md §10.6 (normative), §10.3.1.
 *
 * ---------------------------------------------------------------------------
 * WHERE THIS CHECK LIST COMES FROM
 * ---------------------------------------------------------------------------
 * SPEC §6 enumerates nine mandatory checks for VOICE and none for video. This
 * list is therefore derived — from cleona_video.h, from invariants I9/I10/I11/
 * I12, and from Erratum E1 (§13). Each group states which of those it enforces,
 * so a reviewer can check the derivation instead of trusting it:
 *
 *   V1-V5   negotiation. A config is a request, not a promise: the backend may
 *           settle every field DOWNWARDS and never upwards, and it fails closed
 *           on a config it must not silently reinterpret. H.264 is the mandatory
 *           interop level — a backend that cannot produce it is not acceptance-
 *           ready, which is the video counterpart of duplex == 1 in voice.
 *   V1b     Erratum E6b. A failed open() states WHY in-band, in
 *           out_negotiated->max_frame_bytes, and does not conflate "the caller
 *           got it wrong" (ERR_INVALID) with "this link cannot carry video"
 *           (ERR_RATE_UNACHIEVABLE). Only the second one produces a text for the
 *           user, so a backend that swaps them makes Erratum E1's decision
 *           unreachable at open(). V15 is the same check for reconfigure.
 *   V6      lifecycle states.
 *   V7-V9   I9. No frame handed out ever exceeds negotiated.max_frame_bytes;
 *           the read buffer is sized at exactly that value, which the ABI says
 *           makes ERR_BUFFER_TOO_SMALL unreachable. pts strictly increasing. A
 *           decoder must be able to start, i.e. a keyframe arrives.
 *   V10     request_keyframe actually produces one.
 *   V11-V17 Erratum E1. The ceiling moves at run time: a rate change forces no
 *           keyframe, a geometry change forces one, a lowered ceiling is either
 *           met by scaling down or refused with ERR_RATE_UNACHIEVABLE and no
 *           side effects, and pts survives an fps increase (the exact
 *           frame_index * 1e6 / fps bug the header names).
 *   V18-V19 frames_dropped_oversize is a DEFECT counter, not a mechanism. The
 *           one documented benign tick — a reconfigure that lowers the ceiling
 *           while a frame is encoded and unread — is bounded by one per
 *           reconfigure, and the harness is built so that it cannot mistake it
 *           for a defect (see the comment at V18).
 *   V20-V21 I12. "Own video off" is not "session gone": capture off yields
 *           READ_TIMEOUT, never READ_CLOSED, and re-enabling forces a keyframe
 *           because the peer's decoder has been starved.
 *   V22-V25 the decode direction and the texture handle — the only two things
 *           that may cross this ABI (I10). Pixels never do.
 *   V26     camera switching.
 *   V27-V29 the verification report (I11): never a guess, never HW_YES without
 *           evidence, counters consistent.
 *   V30     teardown and leak surface.
 *
 * ---------------------------------------------------------------------------
 * HOW TO RUN IT AGAINST YOUR OWN BACKEND (V1.13-V1.16)
 * ---------------------------------------------------------------------------
 *     cmake -S native/cleona_video -B build/video && cmake --build build/video -j
 *     ./build/video/test/cleona_video_conformance_loader \
 *          /path/to/libcleona_video_vaapi.so --shipping
 *
 * or, for a static backend (iOS), from your own CMakeLists:
 *
 *     cleona_video_add_conformance_test(cleona_video_conformance_apple
 *                                       cleona_video_apple)
 *
 * Full instructions in test/CMakeLists.txt. Nothing in this file names a
 * backend, a resolution, a bitrate or a vendor constant: every number it uses
 * is either a request it then validates the answer against, or is derived from
 * what the backend reported.
 *
 * Exit codes: 0 conformant, 1 a check failed, 2 the backend could not be
 * exercised at all.
 */

/* clock_gettime and CLOCK_MONOTONIC are POSIX, not ISO C. A build with a strict
 * -std=c11 (rather than the gnu11 CMake selects by default) defines
 * __STRICT_ANSI__ and hides them, and the harness then fails to compile on the
 * very toolchains a device build is most likely to use. Must come before the
 * first system header. Same guard as native/cleona_video/mock/cleona_video_mock.c:26. */
#if !defined(_WIN32) && !defined(_POSIX_C_SOURCE)
  #define _POSIX_C_SOURCE 200809L
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "conformance_abi.h"
#include "conformance_harness.h"

#if defined(_WIN32)
  #define WIN32_LEAN_AND_MEAN
  #include <windows.h>
  static int64_t now_ms(void) { return (int64_t)GetTickCount64(); }
#else
  #include <time.h>
  static int64_t now_ms(void) {
      struct timespec ts;
      clock_gettime(CLOCK_MONOTONIC, &ts);
      return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
  }
#endif

/* ==========================================================================
 * The read buffer — sized at the ceiling, with a guard zone behind it
 * ==========================================================================
 * cleona_video.h: "Size it at negotiated.max_frame_bytes and
 * ERR_BUFFER_TOO_SMALL becomes unreachable, because no frame handed out here
 * ever exceeds it." The harness therefore passes exactly that as buf_cap — a
 * larger capacity would hide an oversize frame instead of catching it — and
 * puts a poisoned guard zone behind the buffer so a backend that writes past
 * buf_cap is caught rather than corrupting the harness silently.
 *
 * The guard poison is position-dependent so that a backend memset-ing a
 * constant into the tail cannot reproduce it by accident. */
#define GUARD_BYTES 64

static uint8_t* g_buf;          /* g_mfb + GUARD_BYTES */
static int32_t  g_mfb;          /* the ceiling currently in force */

static int64_t g_frames;        /* frames delivered to the harness */
static int32_t g_max_size;      /* largest frame this backend actually produced */
static int64_t g_last_pts = -1;
static int32_t g_viol_size;     /* frames larger than the ceiling (I9)        */
static int32_t g_viol_guard;    /* writes past buf_cap                        */
static int32_t g_viol_pts;      /* pts not strictly increasing                */
static int32_t g_viol_toosmall; /* ERR_BUFFER_TOO_SMALL at ceiling capacity   */
static int     g_viol_notes;    /* how many violations were printed in detail */

static uint8_t guard_poison(int32_t i) {
    uint32_t x = (uint32_t)i * 2654435761u;
    x ^= x >> 13;
    return (uint8_t)(x ^ 0xA5u);
}

/* (Re-)sizes the read buffer to the ceiling currently in force. */
static int set_ceiling(int32_t mfb) {
    uint8_t* nb = (uint8_t*)realloc(g_buf, (size_t)mfb + GUARD_BYTES);
    if (!nb) return -1;
    g_buf = nb;
    g_mfb = mfb;
    return 0;
}

/* Reads one frame and enforces, on EVERY frame, the invariants that must hold
 * for every frame. Returns the ABI return code. */
static int32_t read_one(cleona_video_session_t* s, int32_t timeout_ms,
                        int32_t* out_size, int32_t* out_flags) {
    int32_t size = 0, flags = 0;
    int64_t pts = 0;

    for (int32_t i = 0; i < GUARD_BYTES; i++) g_buf[g_mfb + i] = guard_poison(i);

    int32_t r = CVID.read_encoded(s, g_buf, g_mfb, &size, &flags, &pts, timeout_ms);

    if (r == CLEONA_VIDEO_ERR_BUFFER_TOO_SMALL) {
        g_viol_toosmall++;
        if (g_viol_notes++ < 5) {
            ch_note("!", "frame does not fit a buffer sized at the ceiling",
                    "required=%d ceiling=%d", size, g_mfb);
        }
        return r;
    }
    if (r != CLEONA_VIDEO_READ_FRAME) return r;

    g_frames++;
    if (size > g_max_size) g_max_size = size;

    if (size > g_mfb || size <= 0) {
        g_viol_size++;
        if (g_viol_notes++ < 5) {
            ch_note("!", "delivered frame violates max_frame_bytes (I9)",
                    "size=%d ceiling=%d", size, g_mfb);
        }
    }
    for (int32_t i = 0; i < GUARD_BYTES; i++) {
        if (g_buf[g_mfb + i] != guard_poison(i)) {
            g_viol_guard++;
            if (g_viol_notes++ < 5) {
                ch_note("!", "backend wrote past buf_cap",
                        "guard byte %d changed, reported size=%d cap=%d",
                        i, size, g_mfb);
            }
            break;
        }
    }
    if (pts <= g_last_pts) {
        g_viol_pts++;
        if (g_viol_notes++ < 5) {
            ch_note("!", "pts is not strictly increasing",
                    "previous=%lld current=%lld", (long long)g_last_pts,
                    (long long)pts);
        }
    }
    g_last_pts = pts;

    if (out_size)  *out_size = size;
    if (out_flags) *out_flags = flags;
    return r;
}

/* Reads n frames, returning how many were delivered. Keyframes counted. */
static int32_t read_n(cleona_video_session_t* s, int32_t n, int32_t* keyframes,
                      int32_t* last_size) {
    int32_t got = 0, keys = 0, size = 0, flags = 0;
    for (int32_t i = 0; i < n; i++) {
        if (read_one(s, 2000, &size, &flags) != CLEONA_VIDEO_READ_FRAME) break;
        got++;
        if (flags & CLEONA_VIDEO_FLAG_KEYFRAME) keys++;
        if (last_size) *last_size = size;
    }
    if (keyframes) *keyframes = keys;
    return got;
}

/* ==========================================================================
 * Helpers
 * ========================================================================== */

static const char* codec_name(int32_t c) {
    switch (c) {
        case CLEONA_VIDEO_CODEC_H264: return "h264";
        case CLEONA_VIDEO_CODEC_HEVC: return "hevc";
        case CLEONA_VIDEO_CODEC_AV1:  return "av1";
        case CLEONA_VIDEO_CODEC_VP9:  return "vp9";
        default:                      return "INVALID";
    }
}

static const char* hw_name(int32_t v) {
    switch (v) {
        case CLEONA_VIDEO_HW_YES:              return "yes";
        case CLEONA_VIDEO_HW_NO:               return "no";
        case CLEONA_VIDEO_HW_NOT_DETERMINABLE: return "not_determinable";
        default:                               return "INVALID";
    }
}

static int hw_is_defined(int32_t v) {
    return v == CLEONA_VIDEO_HW_YES || v == CLEONA_VIDEO_HW_NO
        || v == CLEONA_VIDEO_HW_NOT_DETERMINABLE;
}

static int submit_rc_is_defined(int32_t r) {
    return r == CLEONA_VIDEO_SUBMIT_ACCEPTED
        || r == CLEONA_VIDEO_SUBMIT_AWAITING_KEYFRAME
        || r == CLEONA_VIDEO_ERR_INVALID
        || r == CLEONA_VIDEO_ERR_STATE
        || r == CLEONA_VIDEO_ERR_DECODE;
}

static cleona_video_config_t make_cfg(int32_t codec, int32_t w, int32_t h,
                                      int32_t fps, int32_t kbps, int32_t mfb,
                                      int32_t kfi) {
    cleona_video_config_t c;
    memset(&c, 0, sizeof(c));
    c.codec = codec;
    c.width = w;
    c.height = h;
    c.fps = fps;
    c.target_bitrate_kbps = kbps;
    c.max_frame_bytes = mfb;
    c.keyframe_interval_frames = kfi;
    return c;
}

/* Erratum 6b: on a FAILED open the error code sits in max_frame_bytes and every
 * other field is zeroed, so a caller cannot mistake a leftover value in the
 * struct for a negotiated one. */
static int open_error_zeroed(const cleona_video_config_t* c) {
    return c->codec == 0 && c->width == 0 && c->height == 0 && c->fps == 0
        && c->target_bitrate_kbps == 0 && c->keyframe_interval_frames == 0;
}

/* "Never negotiated upwards" — the rule that holds for open and reconfigure
 * alike (cleona_video.h). */
static int never_up(const cleona_video_config_t* req,
                    const cleona_video_config_t* got) {
    return got->width  > 0 && got->width  <= req->width
        && got->height > 0 && got->height <= req->height
        && got->fps    > 0 && got->fps    <= req->fps
        && got->target_bitrate_kbps > 0
        && got->target_bitrate_kbps <= req->target_bitrate_kbps
        && got->max_frame_bytes > 0
        && got->max_frame_bytes <= req->max_frame_bytes;
}

/* ==========================================================================
 * Options
 * ========================================================================== */

typedef struct {
    const char* lib;
    const char* json;
    const char* expect[CH_MAX_EXPECT];
    int         expect_n;
    int         shipping;
} opts_t;

static void usage(const char* argv0) {
    printf(
"usage: %s [options] [backend-library]\n"
"\n"
"  backend-library     path to the backend to certify. Loader build only;\n"
"                      may also be given with --lib or in CLEONA_VIDEO_LIB.\n"
"  --lib <path>        same as the positional argument\n"
"  --json <path>       also write the machine-readable report to <path>\n"
"  --shipping          additionally assert the V1.13-V1.16 acceptance line:\n"
"                      a real capture/encode backend and hardware_encode = yes\n"
"  --expect-fail <ids> harness self-test: exactly these check ids must fail\n"
"  -h, --help          this text\n", argv0);
}

static int parse_args(int argc, char** argv, opts_t* o) {
    memset(o, 0, sizeof(*o));
    for (int i = 1; i < argc; i++) {
        const char* a = argv[i];
        if (strcmp(a, "-h") == 0 || strcmp(a, "--help") == 0) {
            usage(argv[0]);
            return 1;
        } else if (strcmp(a, "--lib") == 0 && i + 1 < argc) {
            o->lib = argv[++i];
        } else if (strcmp(a, "--json") == 0 && i + 1 < argc) {
            o->json = argv[++i];
        } else if (strcmp(a, "--shipping") == 0) {
            o->shipping = 1;
        } else if (strcmp(a, "--expect-fail") == 0 && i + 1 < argc) {
            static char buf[256];
            snprintf(buf, sizeof(buf), "%s", argv[++i]);
            char* p = buf;
            while (*p && o->expect_n < CH_MAX_EXPECT) {
                char* comma = strchr(p, ',');
                if (comma) *comma = '\0';
                if (*p) o->expect[o->expect_n++] = p;
                if (!comma) break;
                p = comma + 1;
            }
        } else if (a[0] == '-') {
            printf("unknown option: %s\n", a);
            usage(argv[0]);
            return 2;
        } else {
            o->lib = a;
        }
    }
    return 0;
}

/* ==========================================================================
 * The run
 * ========================================================================== */

int main(int argc, char** argv) {
    opts_t o;
    int pr = parse_args(argc, argv, &o);
    if (pr == 1) return 0;
    if (pr != 0) return 2;

    char err[512];
    err[0] = '\0';
    if (cvidbind_init(o.lib, err, sizeof(err)) != 0) {
        printf("FATAL %s\n", err);
        return 2;
    }

    ch_begin("cleona_video conformance (derived from cleona_video.h, I9-I12, E1)",
             cvidbind_mode(), cvidbind_library());

    /* The configuration the harness asks for. Every number here is a REQUEST
     * whose answer is validated; none of them is assumed to be granted. */
    const int32_t REQ_W = 1280, REQ_H = 720, REQ_FPS = 30;
    const int32_t REQ_KBPS = 800;
    const int32_t REQ_MFB = 60000;   /* generous: the tight ceiling is exercised
                                      * later, through reconfigure, which is
                                      * where a real ceiling comes from (E1) */
    const int32_t KFI_SHORT = 30;    /* so a keyframe is reachable in one phase */
    const int32_t KFI_LONG  = 600;   /* so a periodic keyframe cannot fake V10  */

    /* ==================================================================== *
     * V1-V5 — negotiation
     * ==================================================================== */
    ch_section("negotiation (a config is a request, not a promise)");

    cleona_video_config_t bad;
    int fail_closed = 1;
    char why[256];
    why[0] = '\0';

    {
        cleona_video_session_t* t = CVID.open(NULL, NULL);
        if (t) { fail_closed = 0; strcat(why, "NULL-cfg "); CVID.close(t); }

        bad = make_cfg(CLEONA_VIDEO_CODEC_H264, REQ_W, REQ_H, REQ_FPS, REQ_KBPS, 0, 30);
        t = CVID.open(&bad, NULL);
        if (t) { fail_closed = 0; strcat(why, "mfb=0 "); CVID.close(t); }

        bad.max_frame_bytes = REQ_MFB;
        bad.codec = 99;
        t = CVID.open(&bad, NULL);
        if (t) { fail_closed = 0; strcat(why, "codec=99 "); CVID.close(t); }

        bad.codec = CLEONA_VIDEO_CODEC_H264;
        bad.fps = 0;
        t = CVID.open(&bad, NULL);
        if (t) { fail_closed = 0; strcat(why, "fps=0 "); CVID.close(t); }

        bad.fps = REQ_FPS;
        bad.width = 0;
        t = CVID.open(&bad, NULL);
        if (t) { fail_closed = 0; strcat(why, "width=0 "); CVID.close(t); }

        bad.width = REQ_W;
        bad.target_bitrate_kbps = 0;
        t = CVID.open(&bad, NULL);
        if (t) { fail_closed = 0; strcat(why, "bitrate=0 "); CVID.close(t); }

        bad.target_bitrate_kbps = REQ_KBPS;
        bad.keyframe_interval_frames = -1;
        t = CVID.open(&bad, NULL);
        if (t) { fail_closed = 0; strcat(why, "kfi=-1 "); CVID.close(t); }
    }
    ch_check("V1", "open() fails closed on an invalid configuration", fail_closed,
             "%s", fail_closed ? "NULL cfg, mfb=0, unknown codec, fps=0, width=0, "
                                 "bitrate=0, kfi<0 all rejected"
                               : why);

    /* ==================================================================== *
     * V1b — Erratum E6b: a failed open() says WHY, in-band.
     *
     * V1 above proves only that open() fails closed. Every one of its calls
     * passes out_negotiated == NULL, which is itself worth having: it proves
     * that forgoing the error channel is safe and stays legal. What V1 cannot
     * prove is that the caller can tell "I called this wrong" from "this link
     * cannot carry video". Without that distinction the caller of Erratum E1
     * shows no reason or the wrong one — the failure E1 exists to remove, at the
     * one entry point E1 did not cover.
     *
     * Same shape and same purpose as V15, which fixes exactly these two codes
     * for reconfigure. The two checks together are what stops open() and
     * reconfigure() from holding different opinions about one configuration.
     * ==================================================================== */
    {
        cleona_video_config_t bads[7];
        const char* bad_names[7] = {"NULL-cfg", "mfb=0", "codec=99", "fps=0",
                                    "width=0", "bitrate=0", "kfi=-1"};
        for (int i = 0; i < 7; i++) {
            bads[i] = make_cfg(CLEONA_VIDEO_CODEC_H264, REQ_W, REQ_H, REQ_FPS,
                               REQ_KBPS, REQ_MFB, 30);
        }
        /* mfb=0 is in this list deliberately. A ceiling of zero is also
         * trivially unreachable, so it is the one configuration that could
         * honestly justify either code — and the ABI fixes the tie as
         * ERR_INVALID, because reconfigure already answers that way (V15). */
        bads[1].max_frame_bytes = 0;
        bads[2].codec = 99;
        bads[3].fps = 0;
        bads[4].width = 0;
        bads[5].target_bitrate_kbps = 0;
        bads[6].keyframe_interval_frames = -1;

        int inv_ok = 1;
        char idetail[320];
        idetail[0] = '\0';
        for (int i = 0; i < 7; i++) {
            cleona_video_config_t out;
            /* Poisoned rather than zeroed: a backend that writes nothing at all
             * must not accidentally look like it reported a code. */
            memset(&out, 0x7F, sizeof(out));
            cleona_video_session_t* t = CVID.open(i == 0 ? NULL : &bads[i], &out);
            char one[64];
            if (t) {
                CVID.close(t);
                inv_ok = 0;
                snprintf(one, sizeof(one), "%s->opened ", bad_names[i]);
            } else {
                if (out.max_frame_bytes != CLEONA_VIDEO_ERR_INVALID ||
                    !open_error_zeroed(&out)) {
                    inv_ok = 0;
                }
                snprintf(one, sizeof(one), "%s->%d ", bad_names[i],
                         out.max_frame_bytes);
            }
            strncat(idetail, one, sizeof(idetail) - strlen(idetail) - 1);
        }

        /* Valid in every field and unachievable by construction: an Annex-B
         * start code alone is four bytes, so no codec on any platform encodes
         * an access unit into one. The same value and the same argument V14
         * uses for reconfigure. */
        cleona_video_config_t rate_req =
            make_cfg(CLEONA_VIDEO_CODEC_H264, REQ_W, REQ_H, REQ_FPS, REQ_KBPS, 1, 30);
        cleona_video_config_t out_rate;
        memset(&out_rate, 0x7F, sizeof(out_rate));
        cleona_video_session_t* t_rate = CVID.open(&rate_req, &out_rate);
        const int rate_opened = (t_rate != NULL);
        const int32_t rate_code = rate_opened ? 0 : out_rate.max_frame_bytes;
        if (t_rate) CVID.close(t_rate);
        const int rate_ok = !rate_opened &&
                            rate_code == CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE &&
                            open_error_zeroed(&out_rate);
        char rate_detail[48];
        if (rate_opened) {
            snprintf(rate_detail, sizeof(rate_detail), "opened a session");
        } else {
            snprintf(rate_detail, sizeof(rate_detail), "%d", rate_code);
        }

        ch_check("V1b", "a failed open() reports the reason in-band, and does "
                        "not swap the two reasons (E6b)",
                 inv_ok && rate_ok,
                 "caller bugs: %s(expect %d each, every other field zeroed); "
                 "mfb=1 -> %s (expect %d). ERR_INVALID means the call was wrong; "
                 "ERR_RATE_UNACHIEVABLE means the link cannot carry video and the "
                 "user is told why -- a backend that conflates them makes that "
                 "decision unreachable",
                 idetail, CLEONA_VIDEO_ERR_INVALID, rate_detail,
                 CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE);
    }

    /* H.264 is the mandatory interop level: the video counterpart of
     * duplex == 1. A backend that cannot deliver it is not acceptance-ready
     * (cleona_video.h, codec field). */
    cleona_video_config_t req_h264 =
        make_cfg(CLEONA_VIDEO_CODEC_H264, REQ_W, REQ_H, REQ_FPS, REQ_KBPS, REQ_MFB, 30);
    cleona_video_config_t got_h264;
    memset(&got_h264, 0, sizeof(got_h264));
    cleona_video_session_t* t264 = CVID.open(&req_h264, &got_h264);
    ch_check("V2", "H.264 is available (mandatory interop level)",
             t264 != NULL && got_h264.codec == CLEONA_VIDEO_CODEC_H264,
             "session=%s negotiated codec=%s",
             t264 ? "opened" : "NULL", codec_name(got_h264.codec));
    ch_check("V5", "open() negotiates downwards only, never upwards",
             t264 != NULL && never_up(&req_h264, &got_h264),
             "requested %dx%d@%d %dkbps mfb=%d -> negotiated %dx%d@%d %dkbps mfb=%d",
             req_h264.width, req_h264.height, req_h264.fps,
             req_h264.target_bitrate_kbps, req_h264.max_frame_bytes,
             got_h264.width, got_h264.height, got_h264.fps,
             got_h264.target_bitrate_kbps, got_h264.max_frame_bytes);
    if (t264) CVID.close(t264);

    {
        cleona_video_config_t req_np =
            make_cfg(0, REQ_W, REQ_H, REQ_FPS, REQ_KBPS, REQ_MFB, 30);
        cleona_video_config_t got_np;
        memset(&got_np, 0, sizeof(got_np));
        cleona_video_session_t* t = CVID.open(&req_np, &got_np);
        ch_check("V3", "codec <= 0 (no preference) is treated as H.264",
                 t != NULL && got_np.codec == CLEONA_VIDEO_CODEC_H264,
                 "codec 0 -> %s", codec_name(got_np.codec));
        if (t) CVID.close(t);
    }

    {
        /* An unavailable codec must negotiate DOWN to H.264 rather than fail.
         * A backend that really has the codec is allowed to grant it — the
         * check is that it never answers NULL and never answers something
         * outside the enumeration. */
        int ok4 = 1;
        char detail[192];
        detail[0] = '\0';
        const int32_t exotic[3] = {CLEONA_VIDEO_CODEC_HEVC, CLEONA_VIDEO_CODEC_AV1,
                                   CLEONA_VIDEO_CODEC_VP9};
        for (int i = 0; i < 3; i++) {
            cleona_video_config_t rq =
                make_cfg(exotic[i], REQ_W, REQ_H, REQ_FPS, REQ_KBPS, REQ_MFB, 30);
            cleona_video_config_t gt;
            memset(&gt, 0, sizeof(gt));
            cleona_video_session_t* t = CVID.open(&rq, &gt);
            char one[64];
            snprintf(one, sizeof(one), "%s->%s ", codec_name(exotic[i]),
                     t ? codec_name(gt.codec) : "NULL");
            strncat(detail, one, sizeof(detail) - strlen(detail) - 1);
            if (!t || (gt.codec != CLEONA_VIDEO_CODEC_H264 && gt.codec != exotic[i])) {
                ok4 = 0;
            }
            if (t) CVID.close(t);
        }
        ch_check("V4", "an unavailable codec negotiates down to H.264, never fails",
                 ok4, "%s", detail);
    }

    /* ==================================================================== *
     * The session under test.
     * ==================================================================== */
    cleona_video_config_t req =
        make_cfg(CLEONA_VIDEO_CODEC_H264, REQ_W, REQ_H, REQ_FPS, REQ_KBPS,
                 REQ_MFB, KFI_SHORT);
    cleona_video_config_t neg;
    memset(&neg, 0, sizeof(neg));
    cleona_video_session_t* s = CVID.open(&req, &neg);
    if (!s) return ch_abort("cleona_video_open returned NULL for a valid configuration");
    if (set_ceiling(neg.max_frame_bytes) != 0) {
        CVID.close(s);
        return ch_abort("out of memory sizing the read buffer");
    }

    ch_report_int("negotiated_width",  neg.width);
    ch_report_int("negotiated_height", neg.height);
    ch_report_int("negotiated_fps",    neg.fps);
    ch_report_int("target_bitrate_kbps", neg.target_bitrate_kbps);
    ch_report_int("max_frame_bytes_at_open", neg.max_frame_bytes);
    ch_report_str("codec", codec_name(neg.codec));

    ch_section("lifecycle");
    int32_t sz = 0, fl = 0;
    int64_t pt = 0;
    int32_t before_start = CVID.read_encoded(s, g_buf, g_mfb, &sz, &fl, &pt, 10);
    int32_t rc_start  = CVID.start(s);
    int32_t rc_start2 = CVID.start(s);
    ch_check("V6", "read before start is CLOSED; start twice is ERR_STATE",
             before_start == CLEONA_VIDEO_READ_CLOSED &&
             rc_start == CLEONA_VIDEO_OK &&
             rc_start2 == CLEONA_VIDEO_ERR_STATE,
             "read-before-start=%d start=%d start-again=%d (expect %d,0,%d)",
             before_start, rc_start, rc_start2,
             CLEONA_VIDEO_READ_CLOSED, CLEONA_VIDEO_ERR_STATE);
    if (rc_start != CLEONA_VIDEO_OK) {
        CVID.close(s);
        return ch_abort("cleona_video_start refused; nothing else can be tested");
    }

    /* Samples kept for the decode direction (V22). */
    uint8_t* key_sample = (uint8_t*)malloc((size_t)g_mfb);
    uint8_t* delta_sample = (uint8_t*)malloc((size_t)g_mfb);
    int32_t  key_len = 0, delta_len = 0;

    /* ==================================================================== *
     * V7-V9 — the ceiling, the clock, and the decoder's entry point.
     * This phase performs NO reconfigure, so frames_dropped_oversize must not
     * move at all (V18).
     * ==================================================================== */
    ch_section("frame delivery under the ceiling (I9)");

    cleona_video_report_t rp0, rp1;
    memset(&rp0, 0, sizeof(rp0));
    CVID.get_report(s, &rp0);

    int32_t keys = 0, got = 0, first_flags = 0, size = 0, flags = 0;
    int64_t t_phase = now_ms();
    for (int32_t i = 0; i <= KFI_SHORT; i++) {
        if (read_one(s, 2000, &size, &flags) != CLEONA_VIDEO_READ_FRAME) break;
        got++;
        if (got == 1) first_flags = flags;
        if (flags & CLEONA_VIDEO_FLAG_KEYFRAME) {
            keys++;
            if (!key_len && key_sample && size <= g_mfb) {
                memcpy(key_sample, g_buf, (size_t)size);
                key_len = size;
            }
        } else if (!delta_len && delta_sample && size <= g_mfb) {
            memcpy(delta_sample, g_buf, (size_t)size);
            delta_len = size;
        }
    }
    int64_t phase_ms = now_ms() - t_phase;

    ch_check("V9", "a keyframe arrives within keyframe_interval_frames + 1",
             got == KFI_SHORT + 1 && keys >= 1,
             "frames=%d/%d keyframes=%d in %lldms (negotiated interval %d)",
             got, KFI_SHORT + 1, keys, (long long)phase_ms,
             neg.keyframe_interval_frames);
    ch_note("N1", "first delivered frame carries the keyframe flag",
            "%s -- a stream that does not start with one costs the peer a "
            "round trip", (first_flags & CLEONA_VIDEO_FLAG_KEYFRAME) ? "yes" : "no");

    memset(&rp1, 0, sizeof(rp1));
    CVID.get_report(s, &rp1);
    ch_check("V18", "frames_dropped_oversize does not move without a reconfigure",
             rp1.frames_dropped_oversize == rp0.frames_dropped_oversize,
             "%lld -> %lld over %d delivered frames (a defect counter, not a "
             "mechanism -- E1)",
             (long long)rp0.frames_dropped_oversize,
             (long long)rp1.frames_dropped_oversize, got);

    /* ==================================================================== *
     * V11, V10 — reconfigure that changes only the rate, then request_keyframe.
     * The keyframe interval is widened first so that a periodic keyframe
     * cannot make V10 pass for the wrong reason.
     * ==================================================================== */
    ch_section("reconfigure and forced keyframes (Erratum E1)");

    int32_t lowering_reconfigures = 0;

    cleona_video_config_t rq = make_cfg(neg.codec, neg.width, neg.height, neg.fps,
                                        neg.target_bitrate_kbps / 2 + 1,
                                        neg.max_frame_bytes, KFI_LONG);
    cleona_video_config_t gt;
    memset(&gt, 0, sizeof(gt));
    int32_t rrc = CVID.reconfigure(s, &rq, &gt);
    if (rrc == CLEONA_VIDEO_OK) {
        if (set_ceiling(gt.max_frame_bytes) != 0) return ch_abort("out of memory");
        int32_t n = read_n(s, 1, &keys, &size);
        ch_check("V11", "a rate-only reconfigure does not force a keyframe",
                 n == 1 && keys == 0 && gt.width == neg.width && gt.height == neg.height,
                 "%d kbps -> %d kbps, geometry %dx%d unchanged, next frame keyframe=%d",
                 neg.target_bitrate_kbps, gt.target_bitrate_kbps,
                 gt.width, gt.height, keys);
        ch_check("V16", "reconfigure negotiates downwards only",
                 never_up(&rq, &gt),
                 "requested %dx%d@%d %dkbps mfb=%d -> %dx%d@%d %dkbps mfb=%d",
                 rq.width, rq.height, rq.fps, rq.target_bitrate_kbps, rq.max_frame_bytes,
                 gt.width, gt.height, gt.fps, gt.target_bitrate_kbps, gt.max_frame_bytes);
        neg = gt;
    } else {
        ch_check("V11", "a rate-only reconfigure is accepted", 0,
                 "reconfigure returned %d for a request the session already met", rrc);
        ch_note("V16", "not evaluated", "the rate-only reconfigure was refused");
    }

    int32_t rkf = CVID.request_keyframe(s);
    if (rkf == CLEONA_VIDEO_OK) {
        int32_t seen_key = 0, n = 0;
        for (int32_t i = 0; i < 3; i++) {
            if (read_one(s, 2000, &size, &flags) != CLEONA_VIDEO_READ_FRAME) break;
            n++;
            if (flags & CLEONA_VIDEO_FLAG_KEYFRAME) { seen_key = 1; break; }
        }
        ch_check("V10", "request_keyframe produces a keyframe",
                 seen_key,
                 "keyframe after %d frame(s), periodic interval widened to %d so "
                 "it cannot be a coincidence", n, KFI_LONG);
    } else if (rkf == CLEONA_VIDEO_ERR_UNSUPPORTED) {
        ch_note("V10", "backend has no forced-keyframe control",
                "ERR_UNSUPPORTED -- permitted by the ABI, but none of the four "
                "target platforms should need it. Justify it in the report.");
    } else {
        ch_check("V10", "request_keyframe produces a keyframe", 0,
                 "request_keyframe returned %d", rkf);
    }

    /* ==================================================================== *
     * V12 — a geometry change forces a keyframe.
     * ==================================================================== */
    rq = make_cfg(neg.codec, neg.width / 2, neg.height / 2, neg.fps,
                  neg.target_bitrate_kbps, neg.max_frame_bytes, KFI_LONG);
    memset(&gt, 0, sizeof(gt));
    rrc = CVID.reconfigure(s, &rq, &gt);
    if (rrc == CLEONA_VIDEO_OK) {
        if (set_ceiling(gt.max_frame_bytes) != 0) return ch_abort("out of memory");
        int geometry_changed = (gt.width != neg.width || gt.height != neg.height);
        int32_t n = read_n(s, 1, &keys, &size);
        if (geometry_changed) {
            ch_check("V12", "a geometry change forces a keyframe",
                     n == 1 && keys == 1,
                     "%dx%d -> %dx%d, next frame keyframe=%d (the peer cannot "
                     "continue from a reference picture of another size)",
                     neg.width, neg.height, gt.width, gt.height, keys);
        } else {
            ch_note("V12", "backend kept the geometry; forced keyframe not testable",
                    "requested %dx%d, still %dx%d", rq.width, rq.height,
                    gt.width, gt.height);
        }
        neg = gt;
    } else {
        ch_check("V12", "a geometry change is accepted", 0,
                 "reconfigure to %dx%d returned %d", rq.width, rq.height, rrc);
    }

    /* ==================================================================== *
     * V13 — the ceiling drops. Two conformant answers, one forbidden one.
     *
     * The tight ceiling is derived from what THIS backend just produced, not
     * from a number the harness invented: half of the largest frame it has
     * actually delivered so far, so the current configuration provably does NOT
     * fit under it and something has to give. A fixed byte count would be a
     * statement about one particular encoder, and a ceiling the backend already
     * meets would make the check vacuous — it would pass without anything
     * scaling.
     * ==================================================================== */
    int32_t tight = g_max_size > 1 ? g_max_size / 2 : neg.max_frame_bytes / 4;
    if (tight < 1) tight = 1;
    rq = make_cfg(neg.codec, neg.width, neg.height, neg.fps,
                  neg.target_bitrate_kbps, tight, KFI_LONG);
    memset(&gt, 0, sizeof(gt));
    rrc = CVID.reconfigure(s, &rq, &gt);
    if (rrc == CLEONA_VIDEO_OK) {
        lowering_reconfigures++;
        if (set_ceiling(gt.max_frame_bytes) != 0) return ch_abort("out of memory");
        int32_t n = read_n(s, 10, &keys, &size);
        /* read_one has already asserted size <= ceiling on every one of them;
         * the point here is that frames keep coming at all. */
        ch_check("V13", "a lowered ceiling is met by scaling down, not by silence",
                 n == 10 && gt.max_frame_bytes <= tight,
                 "ceiling %d -> %d, bitrate %d -> %d kbps, %d/10 frames delivered "
                 "afterwards", neg.max_frame_bytes, gt.max_frame_bytes,
                 neg.target_bitrate_kbps, gt.target_bitrate_kbps, n);
        neg = gt;
    } else if (rrc == CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE) {
        int32_t n = read_n(s, 5, &keys, &size);
        ch_check("V13", "an unmeetable ceiling is refused, and the session survives",
                 n == 5,
                 "ceiling %d -> %d refused with ERR_RATE_UNACHIEVABLE; %d/5 frames "
                 "still delivered under the previous configuration",
                 neg.max_frame_bytes, tight, n);
    } else {
        ch_check("V13", "a lowered ceiling is either met or refused explicitly", 0,
                 "reconfigure returned %d, which is neither OK nor "
                 "ERR_RATE_UNACHIEVABLE", rrc);
    }

    /* ==================================================================== *
     * V14 — nothing fits at all. This is the branch that switches video off
     * with a reason on the screen (E1, V1.12), so it must be distinguishable
     * from "scaled down" and must be side-effect free.
     *
     * max_frame_bytes = 1 is not a taste judgement: an Annex-B start code alone
     * is four bytes, so no codec on any platform can encode an access unit into
     * one byte. It is the only value that is unachievable by construction.
     * ==================================================================== */
    cleona_video_report_t before_fail;
    memset(&before_fail, 0, sizeof(before_fail));
    CVID.get_report(s, &before_fail);

    rq = make_cfg(neg.codec, neg.width, neg.height, neg.fps,
                  neg.target_bitrate_kbps, 1, KFI_LONG);
    memset(&gt, 0, sizeof(gt));
    int32_t runach = CVID.reconfigure(s, &rq, &gt);

    cleona_video_report_t after_fail;
    memset(&after_fail, 0, sizeof(after_fail));
    CVID.get_report(s, &after_fail);
    int32_t n_after = read_n(s, 3, &keys, &size);

    ch_check("V14", "an impossible ceiling yields ERR_RATE_UNACHIEVABLE, "
                    "side-effect free",
             runach == CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE &&
             after_fail.negotiated_width == before_fail.negotiated_width &&
             after_fail.negotiated_height == before_fail.negotiated_height &&
             after_fail.negotiated_fps == before_fail.negotiated_fps &&
             n_after == 3,
             "rc=%d (expect %d), geometry %dx%d@%d unchanged, %d/3 frames after",
             runach, CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE,
             after_fail.negotiated_width, after_fail.negotiated_height,
             after_fail.negotiated_fps, n_after);

    /* ==================================================================== *
     * V15 — argument validation. ERR_INVALID and ERR_RATE_UNACHIEVABLE mean
     * different things to the caller: one is a bug, the other is a decision to
     * stop video and tell the user why. A backend that conflates them makes
     * that decision unreachable.
     * ==================================================================== */
    int32_t inv_cfg  = CVID.reconfigure(s, NULL, &gt);
    int32_t inv_sess = CVID.reconfigure(NULL, &rq, &gt);
    cleona_video_config_t zero_mfb = rq;
    zero_mfb.max_frame_bytes = 0;
    int32_t inv_mfb = CVID.reconfigure(s, &zero_mfb, &gt);
    ch_check("V15", "reconfigure validates arguments as ERR_INVALID, not "
                    "UNACHIEVABLE",
             inv_cfg == CLEONA_VIDEO_ERR_INVALID &&
             inv_sess == CLEONA_VIDEO_ERR_INVALID &&
             inv_mfb == CLEONA_VIDEO_ERR_INVALID,
             "NULL cfg=%d NULL session=%d mfb=0 -> %d (expect %d each)",
             inv_cfg, inv_sess, inv_mfb, CLEONA_VIDEO_ERR_INVALID);

    /* ==================================================================== *
     * V17 — pts across an fps increase.
     *
     * "A backend that derives pts as frame_index * 1e6 / fps breaks this the
     * moment fps goes back up" (cleona_video.h). Lower the frame rate, read,
     * raise it again, read: read_one asserts strict monotonicity on every
     * single frame, so the check here only has to make the situation happen.
     * ==================================================================== */
    int64_t pts_before = g_last_pts;
    int32_t viol_before = g_viol_pts;
    int32_t low_fps = neg.fps / 3 > 0 ? neg.fps / 3 : 1;

    rq = make_cfg(neg.codec, neg.width, neg.height, low_fps,
                  neg.target_bitrate_kbps, neg.max_frame_bytes, KFI_LONG);
    memset(&gt, 0, sizeof(gt));
    int32_t rlow = CVID.reconfigure(s, &rq, &gt);
    int32_t n_low = 0, n_high = 0;
    int32_t rhigh = CLEONA_VIDEO_ERR_STATE;
    if (rlow == CLEONA_VIDEO_OK) {
        if (set_ceiling(gt.max_frame_bytes) != 0) return ch_abort("out of memory");
        n_low = read_n(s, 3, &keys, &size);
        rq = make_cfg(gt.codec, gt.width, gt.height, REQ_FPS,
                      gt.target_bitrate_kbps, gt.max_frame_bytes, KFI_LONG);
        cleona_video_config_t gt2;
        memset(&gt2, 0, sizeof(gt2));
        rhigh = CVID.reconfigure(s, &rq, &gt2);
        if (rhigh == CLEONA_VIDEO_OK) {
            if (set_ceiling(gt2.max_frame_bytes) != 0) return ch_abort("out of memory");
            n_high = read_n(s, 5, &keys, &size);
            neg = gt2;
        }
        ch_check("V17", "pts stays strictly increasing across an fps increase",
                 rhigh == CLEONA_VIDEO_OK && n_low == 3 && n_high == 5 &&
                 g_viol_pts == viol_before && g_last_pts > pts_before,
                 "fps %d -> %d -> %d, %d + %d frames, pts %lld -> %lld, "
                 "violations %d",
                 neg.fps, gt.fps, rhigh == CLEONA_VIDEO_OK ? REQ_FPS : gt.fps,
                 n_low, n_high, (long long)pts_before, (long long)g_last_pts,
                 g_viol_pts - viol_before);
    } else {
        ch_note("V17", "backend refused the fps change; pts-across-fps not tested",
                "reconfigure to %d fps returned %d", low_fps, rlow);
    }

    /* ==================================================================== *
     * V20, V21 — own video off (I12)
     * ==================================================================== */
    ch_section("own video off is not session gone (I12)");

    cleona_video_report_t cap0, cap1;
    memset(&cap0, 0, sizeof(cap0));
    CVID.get_report(s, &cap0);
    CVID.set_capture_enabled(s, 0);

    int32_t off_rc = CVID.read_encoded(s, g_buf, g_mfb, &sz, &fl, &pt, 200);
    memset(&cap1, 0, sizeof(cap1));
    CVID.get_report(s, &cap1);
    int64_t tex = 0;
    int32_t tex_rc = CVID.get_texture_id(s, &tex);

    ch_check("V20", "capture off: READ_TIMEOUT, never READ_CLOSED",
             off_rc == CLEONA_VIDEO_READ_TIMEOUT &&
             cap1.frames_captured == cap0.frames_captured,
             "read=%d (expect %d), frames_captured %lld -> %lld, texture rc=%d",
             off_rc, CLEONA_VIDEO_READ_TIMEOUT,
             (long long)cap0.frames_captured, (long long)cap1.frames_captured,
             tex_rc);

    CVID.set_capture_enabled(s, 1);
    int32_t n_on = read_n(s, 1, &keys, &size);
    ch_check("V21", "re-enabling capture forces a keyframe unconditionally",
             n_on == 1 && keys == 1,
             "frames=%d keyframe=%d (the peer's decoder was starved; a P-frame "
             "would be undecodable there)", n_on, keys);

    /* ==================================================================== *
     * V22-V25 — the decode direction and the texture handle (I10)
     * ==================================================================== */
    ch_section("decode direction and texture handle (I10)");

    if (key_len > 0 && delta_len > 0) {
        cleona_video_report_t d0, d1;
        memset(&d0, 0, sizeof(d0));
        CVID.get_report(s, &d0);

        int32_t r_delta_first = CVID.submit_encoded(s, delta_sample, delta_len, 0);
        memset(&d1, 0, sizeof(d1));
        CVID.get_report(s, &d1);
        int not_a_failure = (d1.decode_failures == d0.decode_failures) &&
                            (d1.frames_decoded == d0.frames_decoded);

        int32_t r_key = CVID.submit_encoded(s, key_sample, key_len,
                                            CLEONA_VIDEO_FLAG_KEYFRAME);
        int32_t r_delta = CVID.submit_encoded(s, delta_sample, delta_len, 0);
        cleona_video_report_t d2;
        memset(&d2, 0, sizeof(d2));
        CVID.get_report(s, &d2);

        ch_check("V22", "decoder waits for a keyframe, then accepts the stream",
                 r_delta_first == CLEONA_VIDEO_SUBMIT_AWAITING_KEYFRAME &&
                 not_a_failure &&
                 r_key == CLEONA_VIDEO_SUBMIT_ACCEPTED &&
                 r_delta == CLEONA_VIDEO_SUBMIT_ACCEPTED &&
                 d2.frames_decoded > d0.frames_decoded,
                 "delta-first=%d (expect %d, not counted as a failure), key=%d, "
                 "delta-after=%d, frames_decoded %lld -> %lld",
                 r_delta_first, CLEONA_VIDEO_SUBMIT_AWAITING_KEYFRAME, r_key,
                 r_delta, (long long)d0.frames_decoded, (long long)d2.frames_decoded);

        ch_check("V23", "submit_encoded validates its arguments",
                 CVID.submit_encoded(s, NULL, delta_len, 0) == CLEONA_VIDEO_ERR_INVALID &&
                 CVID.submit_encoded(s, delta_sample, 0, 0) == CLEONA_VIDEO_ERR_INVALID &&
                 CVID.submit_encoded(s, delta_sample, -1, 0) == CLEONA_VIDEO_ERR_INVALID,
                 "NULL data, size 0 and size -1 must all be %d",
                 CLEONA_VIDEO_ERR_INVALID);

        /* A malformed bitstream: a hardware decoder may reject it inline
         * (ERR_DECODE, the desirable answer) or asynchronously. What must not
         * happen is an undefined return code or a session that stops working,
         * so the verdict is on those two and the answer itself is recorded. */
        const uint8_t garbage[16] = {0xDE, 0xAD, 0xBE, 0xEF, 0xDE, 0xAD, 0xBE, 0xEF,
                                     0xDE, 0xAD, 0xBE, 0xEF, 0xDE, 0xAD, 0xBE, 0xEF};
        int32_t r_garbage = CVID.submit_encoded(s, garbage, 16, 0);
        int32_t n_survive = read_n(s, 1, &keys, &size);
        ch_check("V24", "a malformed bitstream gives a defined answer and the "
                        "session survives",
                 submit_rc_is_defined(r_garbage) && n_survive == 1,
                 "rc=%d (%s), %d/1 frame after", r_garbage,
                 r_garbage == CLEONA_VIDEO_ERR_DECODE ? "ERR_DECODE" : "other defined code",
                 n_survive);
    } else {
        ch_check("V22", "decode direction exercised", 0,
                 "no keyframe/delta sample could be captured (key=%d delta=%d bytes)",
                 key_len, delta_len);
    }

    tex = 0;
    tex_rc = CVID.get_texture_id(s, &tex);
    if (tex_rc == CLEONA_VIDEO_OK) {
        ch_check("V25", "texture id is a usable handle, NULL out is rejected",
                 tex != 0 &&
                 CVID.get_texture_id(s, NULL) == CLEONA_VIDEO_ERR_INVALID,
                 "id=0x%llX", (unsigned long long)tex);
    } else if (tex_rc == CLEONA_VIDEO_ERR_UNSUPPORTED) {
        ch_note("V25", "backend has no texture path",
                "ERR_UNSUPPORTED -- legitimate for a headless build, but a "
                "shipping backend has to render somewhere");
    } else {
        ch_check("V25", "get_texture_id answers OK or ERR_UNSUPPORTED", 0,
                 "rc=%d", tex_rc);
    }

    /* ==================================================================== *
     * V26 — camera switching
     * ==================================================================== */
    int32_t sw = CVID.switch_camera(s);
    if (sw == CLEONA_VIDEO_OK) {
        int32_t n = read_n(s, 1, &keys, &size);
        ch_check("V26", "the frame after a camera switch is a keyframe",
                 n == 1 && keys == 1, "frames=%d keyframe=%d", n, keys);
    } else if (sw == CLEONA_VIDEO_ERR_UNSUPPORTED) {
        ch_note("V26", "one camera only", "switch_camera = ERR_UNSUPPORTED");
    } else {
        ch_check("V26", "switch_camera answers OK or ERR_UNSUPPORTED", 0,
                 "rc=%d", sw);
    }

    /* ==================================================================== *
     * V7, V8, V19 — the cumulative invariants over every frame of the run.
     * ==================================================================== */
    ch_section("cumulative invariants over the whole run");

    ch_check("V7", "no delivered frame ever exceeded max_frame_bytes (I9)",
             g_viol_size == 0 && g_viol_guard == 0 && g_viol_toosmall == 0,
             "%lld frames, oversize=%d wrote-past-cap=%d buffer-too-small=%d "
             "(buffer capacity was always exactly the ceiling)",
             (long long)g_frames, g_viol_size, g_viol_guard, g_viol_toosmall);

    ch_check("V8", "pts strictly increasing over every delivered frame",
             g_viol_pts == 0, "%lld frames, violations=%d, last pts=%lldus",
             (long long)g_frames, g_viol_pts, (long long)g_last_pts);

    cleona_video_report_t rf;
    memset(&rf, 0, sizeof(rf));
    CVID.get_report(s, &rf);

    /* The benign exception, stated in cleona_video.h so nobody has to guess
     * whether a 1 is a bug: a reconfigure that lowers the ceiling while a frame
     * is already encoded and unread discards that frame and counts it. It is
     * bounded by one per lowering reconfigure. This harness performed exactly
     * `lowering_reconfigures` of them, so anything above that is the defect the
     * counter is named after, and anything at or below it is the exception. */
    ch_check("V19", "frames_dropped_oversize stayed within the benign exception",
             rf.frames_dropped_oversize <= lowering_reconfigures,
             "dropped=%lld, ceiling-lowering reconfigures=%d (E1: at most one "
             "per reconfigure; a counter that grows with the frame rate is the "
             "defect)",
             (long long)rf.frames_dropped_oversize, lowering_reconfigures);

    /* ==================================================================== *
     * V27-V29 — the verification report (I11)
     * ==================================================================== */
    ch_section("verification report (I11)");

    ch_check("V27", "report describes the current configuration and is honest",
             rf.codec_in_use == neg.codec &&
             hw_is_defined(rf.hardware_encode) && hw_is_defined(rf.hardware_decode) &&
             rf.negotiated_width == neg.width &&
             rf.negotiated_height == neg.height &&
             rf.negotiated_fps == neg.fps &&
             rf.capture_backend >= 0 && rf.encode_backend >= 0,
             "codec=%s hw_encode=%s hw_decode=%s %dx%d@%d capture_backend=%d "
             "encode_backend=%d",
             codec_name(rf.codec_in_use), hw_name(rf.hardware_encode),
             hw_name(rf.hardware_decode), rf.negotiated_width,
             rf.negotiated_height, rf.negotiated_fps, rf.capture_backend,
             rf.encode_backend);

    ch_check("V28", "counter relations hold",
             rf.frames_captured >= rf.frames_encoded &&
             rf.frames_encoded - rf.frames_dropped_oversize >= g_frames &&
             rf.frames_encoded > 0,
             "captured=%lld encoded=%lld dropped=%lld delivered=%lld "
             "decoded=%lld decode_failures=%lld",
             (long long)rf.frames_captured, (long long)rf.frames_encoded,
             (long long)rf.frames_dropped_oversize, (long long)g_frames,
             (long long)rf.frames_decoded, (long long)rf.decode_failures);

    cleona_video_report_t rnull;
    memset(&rnull, 0x7F, sizeof(rnull));
    CVID.get_report(NULL, &rnull);
    ch_check("V29", "report(NULL session) zero-fills and reports "
                    "not_determinable",
             rnull.frames_captured == 0 && rnull.frames_encoded == 0 &&
             rnull.hardware_encode == CLEONA_VIDEO_HW_NOT_DETERMINABLE &&
             rnull.hardware_decode == CLEONA_VIDEO_HW_NOT_DETERMINABLE,
             "no session is not evidence that there is no hardware");
    CVID.get_report(s, NULL);   /* documented no-op, must not crash */

    ch_report_str("codec_in_use",   codec_name(rf.codec_in_use));
    ch_report_str("hardware_encode", hw_name(rf.hardware_encode));
    ch_report_str("hardware_decode", hw_name(rf.hardware_decode));
    ch_report_int("capture_backend", rf.capture_backend);
    ch_report_int("encode_backend",  rf.encode_backend);
    ch_report_int("frames_captured", rf.frames_captured);
    ch_report_int("frames_encoded",  rf.frames_encoded);
    ch_report_int("frames_dropped_oversize", rf.frames_dropped_oversize);
    ch_report_int("frames_decoded",  rf.frames_decoded);
    ch_report_int("decode_failures", rf.decode_failures);
    ch_report_int("frames_delivered_to_caller", g_frames);
    ch_report_int("final_max_frame_bytes", neg.max_frame_bytes);

    if (o.shipping) {
        ch_check("V31", "shipping build: a real backend with hardware encode",
                 rf.capture_backend != CLEONA_VIDEO_BACKEND_MOCK &&
                 rf.encode_backend != CLEONA_VIDEO_BACKEND_MOCK &&
                 rf.hardware_encode == CLEONA_VIDEO_HW_YES,
                 "capture_backend=%d encode_backend=%d hardware_encode=%s "
                 "(V1.13-V1.16 acceptance)",
                 rf.capture_backend, rf.encode_backend, hw_name(rf.hardware_encode));
    } else {
        ch_note("V31", "backend identity (assert with --shipping)",
                "capture_backend=%d encode_backend=%d hardware_encode=%s",
                rf.capture_backend, rf.encode_backend, hw_name(rf.hardware_encode));
    }

    /* ==================================================================== *
     * V30 — teardown
     * ==================================================================== */
    /* ==================================================================== *
     * V32, V33, V34 — Erratum 7: a session may be decode-only.
     * ====================================================================
     * A group call opens one session PER REMOTE STREAM and the extra ones
     * carry no camera (cleona_video.h, session paragraph + Erratum 7). Two
     * things are checked, and the first one is the important one: a backend
     * that has not implemented the direction yet must FAIL CLOSED. Quietly
     * opening a duplex session instead would acquire a camera nobody asked
     * for and report an encoder that will never produce a frame — the caller
     * cannot tell that apart from a working decode-only session until the
     * picture never arrives.
     *
     * The docs' own requirement this serves: docs/CALLS.md's group-video
     * layout shows three remote tiles plus the local one at once, i.e. three
     * concurrent decoders on one device. A backend limited to a single
     * session cannot render that screen.
     */
    ch_section("decode-only sessions (Erratum 7)");
    {
        cleona_video_config_t rx_req =
            make_cfg(CLEONA_VIDEO_CODEC_H264, REQ_W, REQ_H, REQ_FPS, REQ_KBPS,
                     REQ_MFB, 30);
        rx_req.direction = CLEONA_VIDEO_DIR_DECODE_ONLY;

        cleona_video_config_t rx_neg;
        memset(&rx_neg, 0, sizeof(rx_neg));
        cleona_video_session_t* rx = CVID.open(&rx_req, &rx_neg);

        if (rx == NULL) {
            /* Legal intermediate state, named as such by the erratum — but it
             * has to be the RIGHT refusal. ERR_UNSUPPORTED says "this device
             * or this backend has no such path"; anything else would send the
             * caller down a retry or a user-facing bandwidth message. */
            ch_check("V32", "a backend without decode-only support fails "
                            "closed with ERR_UNSUPPORTED",
                     rx_neg.max_frame_bytes == CLEONA_VIDEO_ERR_UNSUPPORTED,
                     "open error code = %d (expected %d)",
                     rx_neg.max_frame_bytes, CLEONA_VIDEO_ERR_UNSUPPORTED);
            ch_note("V33", "decode-only not implemented by this backend",
                    "group video cannot render remote streams here -- see "
                    "docs/CALLS.md group layout");
        } else {
            /* Erratum 6b is unchanged for this direction: success still means
             * max_frame_bytes > 0, so the two cases stay distinguishable. */
            ch_check("V32", "decode-only open succeeds and echoes the "
                            "direction, Erratum 6b intact",
                     rx_neg.direction == CLEONA_VIDEO_DIR_DECODE_ONLY &&
                         rx_neg.max_frame_bytes > 0,
                     "direction=%d max_frame_bytes=%d",
                     rx_neg.direction, rx_neg.max_frame_bytes);

            int32_t rx_start = CVID.start(rx);
            int32_t rx_sz = 0, rx_fl = 0;
            int64_t rx_pt = 0;
            /* No encoder, so no frame can ever arrive -- but the session is
             * running, so this is a TIMEOUT and never READ_CLOSED. A blocking
             * read would hang here, which is why the ABI names the answer. */
            int32_t rx_read = CVID.read_encoded(rx, g_buf, g_mfb, &rx_sz,
                                                &rx_fl, &rx_pt, 10);
            int32_t rx_kf = CVID.request_keyframe(rx);
            int32_t rx_cam = CVID.switch_camera(rx);
            /* Accepted and ignored: a caller driving N sessions uniformly must
             * not have to special-case this one. */
            CVID.set_capture_enabled(rx, 0);
            CVID.set_capture_enabled(rx, 1);

            cleona_video_report_t rxr;
            memset(&rxr, 0, sizeof(rxr));
            CVID.get_report(rx, &rxr);

            ch_check("V33", "decode-only: read times out, encoder controls "
                            "report unsupported, report shows no encoder",
                     rx_start == CLEONA_VIDEO_OK &&
                         rx_read == CLEONA_VIDEO_READ_TIMEOUT &&
                         rx_kf == CLEONA_VIDEO_ERR_UNSUPPORTED &&
                         rx_cam == CLEONA_VIDEO_ERR_UNSUPPORTED &&
                         rxr.encode_backend == CLEONA_VIDEO_BACKEND_NONE &&
                         rxr.hardware_encode == CLEONA_VIDEO_HW_NO &&
                         rxr.frames_encoded == 0,
                     "start=%d read=%d keyframe=%d camera=%d encode_backend=%d "
                     "hw_encode=%d encoded=%lld",
                     rx_start, rx_read, rx_kf, rx_cam, rxr.encode_backend,
                     rxr.hardware_encode, (long long)rxr.frames_encoded);

            /* Direction is fixed at open: a session opened to decode cannot
             * grow a camera. */
            cleona_video_config_t flip = rx_req;
            flip.direction = CLEONA_VIDEO_DIR_DUPLEX;
            cleona_video_config_t flip_out;
            memset(&flip_out, 0, sizeof(flip_out));
            ch_check("V34", "reconfigure cannot change a session's direction",
                     CVID.reconfigure(rx, &flip, &flip_out) ==
                         CLEONA_VIDEO_ERR_INVALID,
                     "a decode-only session must not become duplex");

            CVID.stop(rx);
            CVID.close(rx);
        }
    }

    ch_section("teardown");

    /* V30 asks whether stop() PRESERVES the counters. Its baseline must
     * therefore be read immediately before the stop. It used to compare
     * against `rf`, snapshotted ~190 lines earlier at the end of the frame
     * checks -- but `s` is still RUNNING throughout everything in between, so
     * its encoder keeps advancing frames_encoded and any wall-clock time spent
     * there made the comparison fail for a reason that has nothing to do with
     * stop(). That stayed invisible only as long as the decode-only section
     * above did nothing: before Erratum 7 was implemented, open() refused
     * immediately and the block cost ~0 ms. Once a backend actually supports
     * the direction, the same block opens, starts, reads and closes real
     * sessions -- measured on Android (emulator-5554): V30 failed with
     * "encoded kept=52" against a stale baseline while every other field it
     * asserts was correct. */
    cleona_video_report_t rbefore_stop;
    memset(&rbefore_stop, 0, sizeof(rbefore_stop));
    CVID.get_report(s, &rbefore_stop);

    CVID.stop(s);
    int32_t r_after_stop = CVID.read_encoded(s, g_buf, g_mfb, &sz, &fl, &pt, 10);
    int32_t r_kf_stop = CVID.request_keyframe(s);
    int32_t r_sub_stop = key_len > 0
        ? CVID.submit_encoded(s, key_sample, key_len, CLEONA_VIDEO_FLAG_KEYFRAME)
        : CLEONA_VIDEO_ERR_STATE;
    CVID.stop(s);   /* idempotent */
    cleona_video_report_t rstop;
    memset(&rstop, 0, sizeof(rstop));
    CVID.get_report(s, &rstop);
    int32_t r_restart = CVID.start(s);

    ch_check("V30", "stop is idempotent, rejects work, keeps counters, restarts",
             r_after_stop == CLEONA_VIDEO_READ_CLOSED &&
             r_kf_stop == CLEONA_VIDEO_ERR_STATE &&
             r_sub_stop == CLEONA_VIDEO_ERR_STATE &&
             /* ">=", nicht "==": die Zusage heisst "stop() setzt die Zaehler
              * nicht zurueck". Gleichheit waere gegen einen laufenden Encoder
              * gar nicht zusicherbar -- zwischen dem Lesen des Ankers und dem
              * Lock in stop() liegt immer ein Fenster, in dem der Encode-Thread
              * noch einen Frame abliefern darf. Gemessen auf emulator-5554:
              * dieselbe Pruefung fiel in einem Lauf mit kept=58 durch und ging
              * im naechsten mit before=56 kept=56 durch, ohne Codeaenderung
              * dazwischen. Ein Backend, das die Zaehler wirklich verliert,
              * faellt weiterhin durch (0 >= 56 ist falsch). */
             rstop.frames_encoded >= rbefore_stop.frames_encoded &&
             r_restart == CLEONA_VIDEO_OK,
             "read=%d keyframe=%d submit=%d encoded before=%lld kept=%lld "
             "restart=%d",
             r_after_stop, r_kf_stop, r_sub_stop,
             (long long)rbefore_stop.frames_encoded,
             (long long)rstop.frames_encoded, r_restart);

    CVID.stop(s);
    CVID.close(s);
    s = NULL;
    CVID.stop(NULL);
    CVID.close(NULL);

    cleona_video_config_t gt3;
    memset(&gt3, 0, sizeof(gt3));
    cleona_video_session_t* s2 = CVID.open(&req_h264, &gt3);
    int reopened = (s2 != NULL);
    if (s2) CVID.close(s2);   /* opened, never started: the easiest leak path */
    ch_check("V30b", "open/close without start is repeatable; NULL calls are "
                     "no-ops", reopened,
             "second session %s; leak detection is the sanitizer's job",
             reopened ? "opened and closed" : "refused");

    free(key_sample);
    free(delta_sample);
    free(g_buf);
    g_buf = NULL;

    int code = ch_end(o.json, o.expect, o.expect_n);
    cvidbind_shutdown();
    return code;
}
