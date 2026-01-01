/* smoke_video_mock.c — V0.3 acceptance smoke for the video ABI and its mock.
 *
 * This is NOT the conformance test. The conformance harness is package V0.4
 * and will live in native/cleona_video/test/ — V0.3 does not own that
 * directory. This program covers exactly what the V0.3 acceptance demands and
 * nothing more:
 *
 *   1  format negotiation through cleona_video_open (down-negotiation, codec
 *      fallback to the mandatory H.264 interop level, fail-closed arguments)
 *   2  the keyframe flag in the bitstream actually read back
 *   3  a frame above max_frame_bytes is discarded and counted in
 *      report.frames_dropped_oversize, and is never handed to the caller (I9)
 *   4  cleona_video_request_keyframe
 *   5  clean stop / close without leaks
 *   6  Erratum 1: cleona_video_reconfigure — the ceiling moves at runtime, the
 *      backend scales down instead of discarding, and when nothing fits it
 *      says so with CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE instead of going quiet
 *
 * plus the neighbouring semantics that would otherwise be defined only in
 * prose: buffer-too-small keeps the frame, capture-off is not session-closed
 * (I12), the texture-id path, camera switching, and the decoder's
 * awaiting-keyframe state.
 *
 * Exit code 0 = all checks passed. Any failure prints the offending check and
 * exits 1 immediately — a smoke that keeps going after the first lie is a
 * smoke whose later output cannot be trusted.
 *
 * Leak check (run manually, needs no extra package beyond gcc):
 *   gcc -std=c11 -g -fsanitize=address,undefined -Inative/cleona_video \
 *       -Inative/cleona_video/mock -o /tmp/smoke_asan \
 *       native/cleona_video/smoke/smoke_video_mock.c \
 *       native/cleona_video/mock/cleona_video_mock.c -lpthread && /tmp/smoke_asan
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cleona_video.h"
#include "cleona_video_mock.h"

static int g_checks = 0;

static void check(int cond, const char* what, const char* detail) {
    g_checks++;
    if (cond) {
        printf("  ok   %-58s %s\n", what, detail ? detail : "");
    } else {
        printf("  FAIL %-58s %s\n", what, detail ? detail : "");
        exit(1);
    }
}

/* Same rigour, no line per frame: the per-frame invariants below run on every
 * single frame and would otherwise drown the interesting checks. Counted
 * exactly like the others, printed only when they fail. */
static void check_quiet(int cond, const char* what, const char* detail) {
    g_checks++;
    if (!cond) {
        printf("  FAIL %-58s %s\n", what, detail ? detail : "");
        exit(1);
    }
}

static void section(const char* name) {
    printf("\n[%s]\n", name);
}

/* Sizing: the caller sizes its read buffer at negotiated.max_frame_bytes, at
 * which point CLEONA_VIDEO_ERR_BUFFER_TOO_SMALL is unreachable. The smoke
 * deliberately allocates more so it can also probe the oversize path. */
#define BUFCAP 65536
static uint8_t g_buf[BUFCAP];

/* Samples kept for the decode-side checks. */
static uint8_t g_key_sample[BUFCAP];
static int32_t g_key_sample_len = 0;
static uint8_t g_delta_sample[BUFCAP];
static int32_t g_delta_sample_len = 0;

static int64_t g_last_pts = -1;
static int64_t g_delivered = 0;

/* Read one frame and enforce the invariants that must hold for every frame. */
static int32_t read_one(cleona_video_session_t* s, int32_t max_frame_bytes,
                        int32_t* out_size, int32_t* out_flags, int32_t* out_idx) {
    int32_t size = 0, flags = 0;
    int64_t pts = 0;
    int32_t r = cleona_video_read_encoded(s, g_buf, BUFCAP, &size, &flags, &pts, 1000);
    if (r != CLEONA_VIDEO_READ_FRAME) return r;

    char d[128];
    snprintf(d, sizeof(d), "size=%d flags=0x%02x pts=%lldus", size, flags, (long long)pts);
    check_quiet(size <= max_frame_bytes, "delivered frame is within max_frame_bytes (I9)", d);
    check_quiet(pts > g_last_pts, "pts strictly increasing", d);
    g_last_pts = pts;
    g_delivered++;

    int32_t idx = cleona_video_mock_frame_index(g_buf, size);
    check_quiet(idx >= 0, "frame carries a well-formed mock marker", NULL);

    if ((flags & CLEONA_VIDEO_FLAG_KEYFRAME) && g_key_sample_len == 0) {
        memcpy(g_key_sample, g_buf, (size_t)size);
        g_key_sample_len = size;
    }
    if (!(flags & CLEONA_VIDEO_FLAG_KEYFRAME) && g_delta_sample_len == 0) {
        memcpy(g_delta_sample, g_buf, (size_t)size);
        g_delta_sample_len = size;
    }

    if (out_size)  *out_size = size;
    if (out_flags) *out_flags = flags;
    if (out_idx)   *out_idx = idx;
    return r;
}

int main(void) {
    char d[192];

    printf("cleona_video mock smoke — ABI: cleona_video.h (SPEC V0.3)\n");

    /* ==================================================================== */
    section("1. open / negotiation");

    /* Fail-closed arguments. max_frame_bytes is the interesting one: an
     * encoder without a ceiling violates I9 by construction, so there is no
     * default to invent. */
    check(cleona_video_open(NULL, NULL) == NULL, "open(NULL cfg) returns NULL", NULL);

    cleona_video_config_t bad = {CLEONA_VIDEO_CODEC_H264, 640, 480, 30, 800, 0, 30};
    check(cleona_video_open(&bad, NULL) == NULL,
          "open with max_frame_bytes == 0 fails closed (I9)", NULL);

    bad.max_frame_bytes = 8000;
    bad.codec = 99;
    check(cleona_video_open(&bad, NULL) == NULL,
          "open with unknown codec id fails closed", NULL);

    bad.codec = CLEONA_VIDEO_CODEC_H264;
    bad.fps = 0;
    check(cleona_video_open(&bad, NULL) == NULL, "open with fps == 0 fails closed", NULL);

    /* out_negotiated may be NULL — a caller that genuinely does not care. */
    bad.fps = 30;
    cleona_video_session_t* tmp = cleona_video_open(&bad, NULL);
    check(tmp != NULL, "open with out_negotiated == NULL is allowed", NULL);
    cleona_video_close(tmp);

    /* The real session. Deliberately asks for more than the mock can do, and
     * for a codec the mock has no hardware for, so that negotiation visibly
     * changes something. */
    cleona_video_config_t want = {
        .codec = CLEONA_VIDEO_CODEC_AV1,
        .width = 1920, .height = 1080, .fps = 60,
        .target_bitrate_kbps = 800,
        .max_frame_bytes = 8000,
        .keyframe_interval_frames = 30,
    };
    cleona_video_config_t got;
    memset(&got, 0, sizeof(got));
    cleona_video_session_t* s = cleona_video_open(&want, &got);
    check(s != NULL, "open succeeds", NULL);

    snprintf(d, sizeof(d), "codec %d -> %d", want.codec, got.codec);
    check(got.codec == CLEONA_VIDEO_CODEC_H264,
          "unavailable codec negotiates down to H.264, not a failure", d);
    snprintf(d, sizeof(d), "%dx%d@%d -> %dx%d@%d", want.width, want.height, want.fps,
             got.width, got.height, got.fps);
    check(got.width == CLEONA_VIDEO_MOCK_MAX_WIDTH &&
          got.height == CLEONA_VIDEO_MOCK_MAX_HEIGHT &&
          got.fps == CLEONA_VIDEO_MOCK_MAX_FPS,
          "geometry and fps are negotiated down, never up", d);
    snprintf(d, sizeof(d), "%d -> %d", want.max_frame_bytes, got.max_frame_bytes);
    check(got.max_frame_bytes <= want.max_frame_bytes,
          "max_frame_bytes is never raised by the backend", d);
    check(got.keyframe_interval_frames == 30, "keyframe interval honoured", NULL);

    /* Not const: Erratum 1 lets the ceiling move at runtime, and the per-frame
     * assertion in read_one has to follow it. */
    int32_t MFB = got.max_frame_bytes;

    /* ==================================================================== */
    section("2. lifecycle");

    check(cleona_video_read_encoded(s, g_buf, BUFCAP, &(int32_t){0}, &(int32_t){0},
                                    &(int64_t){0}, 10) == CLEONA_VIDEO_READ_CLOSED,
          "read before start returns READ_CLOSED", NULL);
    check(cleona_video_start(s) == CLEONA_VIDEO_OK, "start", NULL);
    check(cleona_video_start(s) == CLEONA_VIDEO_ERR_STATE, "start twice returns ERR_STATE", NULL);

    cleona_video_mock_set_pacing(s, 0);       /* run at full speed */
    cleona_video_mock_set_frame_bytes(s, 1000);

    /* ==================================================================== */
    section("3. keyframe flag in the read bitstream");

    int32_t size = 0, flags = 0, idx = 0;
    check(read_one(s, MFB, &size, &flags, &idx) == CLEONA_VIDEO_READ_FRAME,
          "first read delivers a frame", NULL);
    snprintf(d, sizeof(d), "idx=%d size=%d", idx, size);
    check(idx == 0, "first frame has index 0", d);
    check((flags & CLEONA_VIDEO_FLAG_KEYFRAME) != 0,
          "first frame carries CLEONA_VIDEO_FLAG_KEYFRAME", d);
    check(size == 1000 * CLEONA_VIDEO_MOCK_KEYFRAME_FACTOR,
          "keyframe is larger than a delta frame", d);
    check(g_buf[0] == 0 && g_buf[1] == 0 && g_buf[2] == 0 && g_buf[3] == 1 &&
          g_buf[4] == 0x67,
          "keyframe bitstream starts with an Annex-B SPS NAL (0x67)", NULL);

    int keys_seen = 0;
    for (int i = 1; i <= 30; i++) {
        check_quiet(read_one(s, MFB, &size, &flags, &idx) == CLEONA_VIDEO_READ_FRAME,
                    "read delivers a frame", NULL);
        if (idx != i) { printf("  FAIL frame index %d, expected %d\n", idx, i); exit(1); }
        int isk = (flags & CLEONA_VIDEO_FLAG_KEYFRAME) != 0;
        if (isk) keys_seen++;
        if (i < 30 && isk)  { printf("  FAIL unexpected keyframe at idx %d\n", i); exit(1); }
        if (i == 30 && !isk) { printf("  FAIL missing keyframe at idx 30\n"); exit(1); }
    }
    check(keys_seen == 1, "exactly one keyframe over keyframe_interval_frames=30",
          "frames 1..30");
    check(g_delta_sample_len > 0, "a delta frame sample was captured", NULL);

    /* ==================================================================== */
    section("4. request_keyframe");

    check(cleona_video_request_keyframe(s) == CLEONA_VIDEO_OK, "request_keyframe accepted", NULL);
    check(cleona_video_request_keyframe(s) == CLEONA_VIDEO_OK,
          "request_keyframe is idempotent before the next frame", NULL);
    check(read_one(s, MFB, &size, &flags, &idx) == CLEONA_VIDEO_READ_FRAME, "read", NULL);
    snprintf(d, sizeof(d), "idx=%d", idx);
    check((flags & CLEONA_VIDEO_FLAG_KEYFRAME) != 0,
          "the frame after request_keyframe is a keyframe", d);

    /* ==================================================================== */
    section("5. max_frame_bytes backstop (I9)");

    cleona_video_report_t r0, r1;
    cleona_video_get_report(s, &r0);
    check(r0.frames_dropped_oversize == 0, "no oversize drops so far", NULL);

    cleona_video_mock_set_oversize_every(s, 2, 512);   /* every 2nd frame too big */
    for (int i = 0; i < 5; i++) {
        check_quiet(read_one(s, MFB, &size, &flags, &idx) == CLEONA_VIDEO_READ_FRAME,
                    "read delivers a frame while oversize frames are injected", NULL);
    }
    cleona_video_mock_set_oversize_every(s, 0, 0);
    cleona_video_get_report(s, &r1);

    snprintf(d, sizeof(d), "encoded +%lld, dropped +%lld, delivered 5",
             (long long)(r1.frames_encoded - r0.frames_encoded),
             (long long)(r1.frames_dropped_oversize - r0.frames_dropped_oversize));
    check(r1.frames_dropped_oversize - r0.frames_dropped_oversize == 5,
          "frames_dropped_oversize counted every discarded frame", d);
    check(r1.frames_encoded - r0.frames_encoded == 10,
          "frames_encoded counts produced frames, drops included", d);
    check(r1.frames_captured - r0.frames_captured == 10,
          "frames_captured advanced for the discarded frames too", d);
    /* The delivered-frame invariant from the header: an oversize frame is
     * never handed out. read_one already asserts size <= max_frame_bytes on
     * every single delivered frame, so this holding across 5 reads with 5
     * injected oversize frames is the actual proof. */

    /* ==================================================================== */
    section("6. buffer too small keeps the frame");

    cleona_video_get_report(s, &r0);
    int32_t need = 0, f2 = 0;
    int64_t p2 = 0;
    int32_t rc = cleona_video_read_encoded(s, g_buf, 10, &need, &f2, &p2, 1000);
    snprintf(d, sizeof(d), "rc=%d out_size=%d", rc, need);
    check(rc == CLEONA_VIDEO_ERR_BUFFER_TOO_SMALL, "small buffer returns ERR_BUFFER_TOO_SMALL", d);
    check(need > 10, "out_size reports the size that would be required", d);

    int32_t size2 = 0;
    check(read_one(s, MFB, &size2, &flags, &idx) == CLEONA_VIDEO_READ_FRAME,
          "retry with a large enough buffer succeeds", NULL);
    check(size2 == need, "the retry delivers the very same frame", NULL);
    cleona_video_get_report(s, &r1);
    check(r1.frames_encoded - r0.frames_encoded == 1,
          "the rejected read did not consume or re-encode a frame", NULL);

    /* ==================================================================== */
    section("7. own video off is not session closed (I12)");

    cleona_video_get_report(s, &r0);
    cleona_video_set_capture_enabled(s, 0);
    int32_t s3 = 0, f3 = 0;
    int64_t p3 = 0;
    rc = cleona_video_read_encoded(s, g_buf, BUFCAP, &s3, &f3, &p3, 30);
    check(rc == CLEONA_VIDEO_READ_TIMEOUT,
          "capture off: read returns READ_TIMEOUT, not READ_CLOSED", NULL);
    cleona_video_get_report(s, &r1);
    check(r1.frames_captured == r0.frames_captured, "capture off: frames_captured frozen", NULL);
    check(cleona_video_get_texture_id(s, &(int64_t){0}) == CLEONA_VIDEO_OK,
          "capture off: the session and its texture stay alive", NULL);

    cleona_video_set_capture_enabled(s, 1);
    check(read_one(s, MFB, &size, &flags, &idx) == CLEONA_VIDEO_READ_FRAME, "read", NULL);
    check((flags & CLEONA_VIDEO_FLAG_KEYFRAME) != 0,
          "re-enabling capture forces a keyframe unconditionally", NULL);

    /* ==================================================================== */
    section("8. texture id");

    int64_t tex = 0;
    check(cleona_video_get_texture_id(s, &tex) == CLEONA_VIDEO_OK, "get_texture_id succeeds", NULL);
    snprintf(d, sizeof(d), "id=0x%llX (synthetic, no renderer)", (unsigned long long)tex);
    check(tex == CLEONA_VIDEO_MOCK_TEXTURE_ID, "mock reports its documented synthetic id", d);
    check(cleona_video_get_texture_id(s, NULL) == CLEONA_VIDEO_ERR_INVALID,
          "get_texture_id(NULL out) returns ERR_INVALID", NULL);

    cleona_video_mock_set_texture_available(s, 0);
    check(cleona_video_get_texture_id(s, &tex) == CLEONA_VIDEO_ERR_UNSUPPORTED,
          "backend without a texture path returns ERR_UNSUPPORTED", NULL);
    cleona_video_mock_set_texture_available(s, 1);

    /* ==================================================================== */
    section("9. camera switching");

    check(cleona_video_switch_camera(s) == CLEONA_VIDEO_OK, "switch_camera succeeds", NULL);
    check(read_one(s, MFB, &size, &flags, &idx) == CLEONA_VIDEO_READ_FRAME, "read", NULL);
    int32_t cam = cleona_video_mock_frame_camera(g_buf, size);
    snprintf(d, sizeof(d), "camera=%d", cam);
    check(cam == 1, "frames now come from the other camera", d);
    check((flags & CLEONA_VIDEO_FLAG_KEYFRAME) != 0,
          "the frame after a camera switch is a keyframe", d);

    cleona_video_mock_set_camera_count(s, 1);
    check(cleona_video_switch_camera(s) == CLEONA_VIDEO_ERR_UNSUPPORTED,
          "single-camera device returns ERR_UNSUPPORTED", NULL);
    cleona_video_mock_set_camera_count(s, 2);

    /* ==================================================================== */
    section("10. reconfigure — the ceiling moves at runtime (Erratum 1)");

    /* Let the bitrate drive the frame size again: the pinned test size would
     * make the scaling decision vacuous. */
    cleona_video_mock_set_frame_bytes(s, 0);
    cleona_video_report_t rr0, rr1;
    cleona_video_get_report(s, &rr0);

    cleona_video_config_t rcfg;
    cleona_video_config_t rgot;

    /* (a) pure rate change that already fits: accepted as requested, and it
     *     must NOT force a keyframe. keyframe_interval_frames is widened so a
     *     periodic keyframe cannot fake the result. */
    rcfg = (cleona_video_config_t){CLEONA_VIDEO_CODEC_H264, 1280, 720, 30,
                                   300, 8000, 600};
    memset(&rgot, 0, sizeof(rgot));
    check(cleona_video_reconfigure(s, &rcfg, &rgot) == CLEONA_VIDEO_OK,
          "rate-only reconfigure accepted", NULL);
    snprintf(d, sizeof(d), "%d kbps, kf interval %d",
             rgot.target_bitrate_kbps, rgot.keyframe_interval_frames);
    check(rgot.target_bitrate_kbps == 300,
          "a request that already fits is taken as-is", d);
    check(rgot.width == 1280 && rgot.height == 720, "geometry unchanged", NULL);
    MFB = rgot.max_frame_bytes;
    check(read_one(s, MFB, &size, &flags, &idx) == CLEONA_VIDEO_READ_FRAME, "read", NULL);
    snprintf(d, sizeof(d), "size=%d flags=0x%02x", size, flags);
    check((flags & CLEONA_VIDEO_FLAG_KEYFRAME) == 0,
          "a rate-only change does not force a keyframe", d);
    check(size == 300 * 125 / 30, "frame size follows the new bitrate", d);

    /* (b) the ceiling drops below what the current rate produces: the backend
     *     must SCALE DOWN and keep sending, not go quiet. */
    rcfg.max_frame_bytes = 3000;
    memset(&rgot, 0, sizeof(rgot));
    check(cleona_video_reconfigure(s, &rcfg, &rgot) == CLEONA_VIDEO_OK,
          "reconfigure to a smaller ceiling is accepted", NULL);
    snprintf(d, sizeof(d), "requested 300 kbps -> accepted %d kbps, ceiling %d",
             rgot.target_bitrate_kbps, rgot.max_frame_bytes);
    check(rgot.target_bitrate_kbps < 300, "the bitrate was scaled down to fit", d);
    check(rgot.max_frame_bytes == 3000, "the new ceiling is what was asked for", d);
    MFB = rgot.max_frame_bytes;
    check(read_one(s, MFB, &size, &flags, &idx) == CLEONA_VIDEO_READ_FRAME,
          "frames keep coming after scaling down", NULL);

    /* (c) a resolution step: this one MUST force a keyframe, because the peer
     *     cannot continue from a reference picture of a different size. */
    rcfg.width = 640;
    rcfg.height = 480;
    rcfg.target_bitrate_kbps = rgot.target_bitrate_kbps;
    memset(&rgot, 0, sizeof(rgot));
    check(cleona_video_reconfigure(s, &rcfg, &rgot) == CLEONA_VIDEO_OK,
          "resolution step accepted", NULL);
    snprintf(d, sizeof(d), "%dx%d", rgot.width, rgot.height);
    check(rgot.width == 640 && rgot.height == 480, "new geometry in out_negotiated", d);
    MFB = rgot.max_frame_bytes;
    check(read_one(s, MFB, &size, &flags, &idx) == CLEONA_VIDEO_READ_FRAME, "read", NULL);
    snprintf(d, sizeof(d), "size=%d flags=0x%02x", size, flags);
    check((flags & CLEONA_VIDEO_FLAG_KEYFRAME) != 0,
          "a geometry change forces a keyframe", d);
    check(size <= MFB, "the forced keyframe still fits the ceiling", d);

    /* (d) nothing fits at all: the caller has to be able to tell this apart
     *     from "scaled down", because this is the case that switches video off
     *     and puts a reason on the screen. */
    cleona_video_config_t before_fail = rgot;
    rcfg.max_frame_bytes = 100;          /* below one minimal frame */
    check(cleona_video_reconfigure(s, &rcfg, &rgot) ==
              CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE,
          "ceiling below the smallest possible frame -> ERR_RATE_UNACHIEVABLE", NULL);

    /* (e) same verdict reached through the lowest supported step rather than
     *     through the physical minimum. */
    cleona_video_mock_set_min_bitrate_kbps(s, 500);
    rcfg.max_frame_bytes = 3000;
    rcfg.target_bitrate_kbps = 800;
    check(cleona_video_reconfigure(s, &rcfg, &rgot) ==
              CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE,
          "no supported step under the ceiling -> ERR_RATE_UNACHIEVABLE", NULL);
    cleona_video_mock_set_min_bitrate_kbps(s, 0);   /* back to the default */

    /* A failed reconfigure is side-effect free and the session keeps running. */
    cleona_video_get_report(s, &rr1);
    check(rr1.negotiated_width == before_fail.width &&
          rr1.negotiated_height == before_fail.height,
          "a rejected reconfigure leaves the session untouched", NULL);
    MFB = before_fail.max_frame_bytes;
    check(read_one(s, MFB, &size, &flags, &idx) == CLEONA_VIDEO_READ_FRAME,
          "the session is still running after a rejected reconfigure", NULL);

    /* (f) argument validation */
    check(cleona_video_reconfigure(s, NULL, &rgot) == CLEONA_VIDEO_ERR_INVALID,
          "reconfigure(NULL cfg) -> ERR_INVALID", NULL);
    check(cleona_video_reconfigure(NULL, &rcfg, &rgot) == CLEONA_VIDEO_ERR_INVALID,
          "reconfigure(NULL session) -> ERR_INVALID", NULL);
    rcfg.max_frame_bytes = 0;
    check(cleona_video_reconfigure(s, &rcfg, &rgot) == CLEONA_VIDEO_ERR_INVALID,
          "reconfigure with max_frame_bytes == 0 -> ERR_INVALID, not UNACHIEVABLE",
          NULL);
    rcfg.max_frame_bytes = before_fail.max_frame_bytes;

    /* (g) THE POINT OF THE ERRATUM: scaling down instead of discarding.
     *     frames_dropped_oversize is a defect counter and must not have moved
     *     across any of the above. */
    cleona_video_get_report(s, &rr1);
    snprintf(d, sizeof(d), "dropped %lld -> %lld",
             (long long)rr0.frames_dropped_oversize,
             (long long)rr1.frames_dropped_oversize);
    check(rr1.frames_dropped_oversize == rr0.frames_dropped_oversize,
          "clean scaling discarded nothing (defect counter stayed put)", d);

    /* ==================================================================== */
    section("11. decode side");

    check(g_key_sample_len > 0 && g_delta_sample_len > 0,
          "keyframe and delta samples available for submit", NULL);

    cleona_video_get_report(s, &r0);
    rc = cleona_video_submit_encoded(s, g_delta_sample, g_delta_sample_len, 0);
    check(rc == CLEONA_VIDEO_SUBMIT_AWAITING_KEYFRAME,
          "delta before any keyframe: SUBMIT_AWAITING_KEYFRAME", NULL);
    cleona_video_get_report(s, &r1);
    check(r1.decode_failures == r0.decode_failures,
          "awaiting-keyframe is not counted as a decode failure", NULL);
    check(r1.frames_decoded == r0.frames_decoded, "and not counted as decoded", NULL);

    rc = cleona_video_submit_encoded(s, g_key_sample, g_key_sample_len,
                                     CLEONA_VIDEO_FLAG_KEYFRAME);
    check(rc == CLEONA_VIDEO_SUBMIT_ACCEPTED, "keyframe accepted", NULL);
    rc = cleona_video_submit_encoded(s, g_delta_sample, g_delta_sample_len, 0);
    check(rc == CLEONA_VIDEO_SUBMIT_ACCEPTED, "delta accepted once a keyframe was seen", NULL);
    cleona_video_get_report(s, &r1);
    check(r1.frames_decoded - r0.frames_decoded == 2, "frames_decoded == 2", NULL);

    const uint8_t garbage[16] = {0xDE, 0xAD, 0xBE, 0xEF, 0xDE, 0xAD, 0xBE, 0xEF,
                                 0xDE, 0xAD, 0xBE, 0xEF, 0xDE, 0xAD, 0xBE, 0xEF};
    cleona_video_get_report(s, &r0);
    check(cleona_video_submit_encoded(s, garbage, 16, 0) == CLEONA_VIDEO_ERR_DECODE,
          "malformed bitstream returns ERR_DECODE", NULL);
    cleona_video_get_report(s, &r1);
    check(r1.decode_failures - r0.decode_failures == 1, "decode_failures incremented", NULL);

    check(cleona_video_submit_encoded(s, g_key_sample, g_key_sample_len, 0)
              == CLEONA_VIDEO_ERR_DECODE,
          "flags contradicting the bitstream returns ERR_DECODE", NULL);
    check(cleona_video_submit_encoded(s, NULL, 10, 0) == CLEONA_VIDEO_ERR_INVALID,
          "submit(NULL data) returns ERR_INVALID", NULL);

    /* ==================================================================== */
    section("12. verification report (I11)");

    cleona_video_get_report(s, &r1);
    check(r1.codec_in_use == CLEONA_VIDEO_CODEC_H264, "codec_in_use matches the negotiation", NULL);
    check(r1.capture_backend == CLEONA_VIDEO_BACKEND_MOCK &&
          r1.encode_backend == CLEONA_VIDEO_BACKEND_MOCK, "backends identified", NULL);
    /* Deliberately compared against the CURRENT configuration, not against the
     * one open() returned: after Erratum 1 the report has to follow every
     * reconfigure, otherwise the one log line per call describes a session
     * that stopped existing at the first bandwidth change. */
    snprintf(d, sizeof(d), "open gave %dx%d, report says %dx%d",
             got.width, got.height, r1.negotiated_width, r1.negotiated_height);
    check(r1.negotiated_width == before_fail.width &&
          r1.negotiated_height == before_fail.height &&
          r1.negotiated_fps == before_fail.fps,
          "report follows the reconfigured geometry, not the one from open", d);
    check(r1.hardware_encode == CLEONA_VIDEO_HW_NO &&
          r1.hardware_decode == CLEONA_VIDEO_HW_NO,
          "mock reports HW_NO — the truth, not a guess", NULL);

    cleona_video_mock_set_hardware(s, CLEONA_VIDEO_HW_NOT_DETERMINABLE,
                                   CLEONA_VIDEO_HW_NOT_DETERMINABLE);
    cleona_video_get_report(s, &r1);
    check(r1.hardware_encode == -1 && r1.hardware_decode == -1,
          "not_determinable is representable and survives the round trip", NULL);

    snprintf(d, sizeof(d), "encoded=%lld dropped=%lld delivered=%lld",
             (long long)r1.frames_encoded, (long long)r1.frames_dropped_oversize,
             (long long)g_delivered);
    check(r1.frames_encoded - r1.frames_dropped_oversize == g_delivered,
          "frames_encoded - frames_dropped_oversize == frames handed to the caller", d);

    cleona_video_report_t rnull;
    memset(&rnull, 0x7F, sizeof(rnull));
    cleona_video_get_report(NULL, &rnull);
    check(rnull.frames_captured == 0 &&
          rnull.hardware_encode == CLEONA_VIDEO_HW_NOT_DETERMINABLE,
          "report(NULL session) zero-fills and reports not_determinable", NULL);
    cleona_video_get_report(s, NULL);   /* must not crash */

    /* ==================================================================== */
    section("13. stop / close");

    cleona_video_stop(s);
    check(cleona_video_read_encoded(s, g_buf, BUFCAP, &s3, &f3, &p3, 10)
              == CLEONA_VIDEO_READ_CLOSED, "read after stop returns READ_CLOSED", NULL);
    check(cleona_video_request_keyframe(s) == CLEONA_VIDEO_ERR_STATE,
          "request_keyframe after stop returns ERR_STATE", NULL);
    check(cleona_video_submit_encoded(s, g_key_sample, g_key_sample_len,
                                      CLEONA_VIDEO_FLAG_KEYFRAME) == CLEONA_VIDEO_ERR_STATE,
          "submit after stop returns ERR_STATE", NULL);
    cleona_video_stop(s);   /* idempotent */

    cleona_video_get_report(s, &r1);
    check(r1.frames_encoded > 0, "counters survive stop (they describe the session)", NULL);

    /* reconfigure is valid before start() and after stop(), not only while
     * running — a caller may well know the ceiling before it opens the camera. */
    check(cleona_video_reconfigure(s, &before_fail, &rgot) == CLEONA_VIDEO_OK,
          "reconfigure works on a stopped (not closed) session", NULL);

    check(cleona_video_start(s) == CLEONA_VIDEO_OK, "restart after stop", NULL);
    cleona_video_mock_set_pacing(s, 0);
    check(cleona_video_submit_encoded(s, g_delta_sample, g_delta_sample_len, 0)
              == CLEONA_VIDEO_SUBMIT_AWAITING_KEYFRAME,
          "stop reset the decoder: a keyframe is required again", NULL);

    cleona_video_close(s);
    cleona_video_stop(NULL);
    cleona_video_close(NULL);
    check(1, "stop(NULL) and close(NULL) are no-ops", NULL);

    /* open without ever starting, then close — the allocation path that leaks
     * most easily. */
    cleona_video_session_t* s2 = cleona_video_open(&want, NULL);
    check(s2 != NULL, "open again", NULL);
    cleona_video_close(s2);

    printf("\nALL %d CHECKS PASSED\n", g_checks);
    return 0;
}
