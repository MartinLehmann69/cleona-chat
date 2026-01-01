/* cleona_video_mock.h — test-only control surface of the mock video backend.
 *
 * The mock implements all of cleona_video.h without any hardware. It exists so
 * that the Dart pipeline (V0.3), the conformance harness (V0.4), the transport
 * exemption work (V1.11), CALL_MEDIA_STATE (V1.12) and the whole UI can be
 * built and tested before a single platform backend exists — SPEC §5.
 *
 * The functions in this header are NOT part of the ABI. They exist only in
 * libcleona_video_mock and must never be looked up by production code. A Dart
 * or C caller that needs them is a test.
 *
 * All knobs are per-session and take effect from the next produced frame on.
 * They are safe to call from any thread and in any lifecycle state after
 * open(). A NULL session is a no-op.
 */

#ifndef CLEONA_VIDEO_MOCK_H
#define CLEONA_VIDEO_MOCK_H

#include <stdint.h>

#include "cleona_video.h"

#ifdef __cplusplus
extern "C" {
#endif

/* The knobs are exported from libcleona_video_mock with default visibility,
 * exactly like the ABI entry points. They are not part of the ABI, but the
 * whole point of the mock (SPEC §5) is that Dart and the conformance harness
 * can drive it — and Dart can only reach a symbol through dlopen. Hiding them
 * would leave the mock drivable from C only. */
#if defined(_WIN32)
  #define CLEONA_VIDEO_MOCK_API __declspec(dllexport)
#else
  #define CLEONA_VIDEO_MOCK_API __attribute__((visibility("default")))
#endif

/* The synthetic texture id the mock reports when its texture path is enabled
 * (the default). ASCII "MOCK". It is deliberately a fixed, recognisable,
 * non-zero constant: it is NOT registered with any renderer, and handing it to
 * a real Flutter Texture widget produces a blank texture rather than a crash.
 * The point is that the texture-id path through the ABI and the Dart binding
 * is exercisable without a GPU. */
#define CLEONA_VIDEO_MOCK_TEXTURE_ID ((int64_t)0x4D4F434B)

/* Upper bounds the mock negotiates down to. Chosen so that a caller asking for
 * something larger visibly gets a smaller answer back — negotiation that never
 * changes anything is negotiation that was never tested. */
#define CLEONA_VIDEO_MOCK_MAX_WIDTH  1280
#define CLEONA_VIDEO_MOCK_MAX_HEIGHT 720
#define CLEONA_VIDEO_MOCK_MAX_FPS    30

/* How much larger a keyframe is than a delta frame in the synthetic stream. */
#define CLEONA_VIDEO_MOCK_KEYFRAME_FACTOR 5

/* Nominal size in bytes of a produced delta frame. 0 (the default) derives it
 * from the negotiated bitrate and fps: target_bitrate_kbps * 125 / fps.
 * Keyframes are CLEONA_VIDEO_MOCK_KEYFRAME_FACTOR times that. */
CLEONA_VIDEO_MOCK_API void cleona_video_mock_set_frame_bytes(cleona_video_session_t* s, int32_t bytes);

/* Produce every n-th frame deliberately larger than max_frame_bytes, so the I9
 * backstop and report.frames_dropped_oversize are testable. n <= 0 (the
 * default) disables the injection. The oversize frame is
 * max_frame_bytes + overshoot bytes; overshoot <= 0 uses 512.
 *
 * The mock deliberately does NOT react to its own drops by tightening rate
 * control — a real backend should, but a test fixture that silently repairs
 * the condition under test is useless. */
CLEONA_VIDEO_MOCK_API void cleona_video_mock_set_oversize_every(cleona_video_session_t* s,
                                          int32_t n, int32_t overshoot);

/* Pace produced frames at the negotiated fps (1, the default) or produce them
 * as fast as the caller reads (0). Tests turn pacing off; anything that wants
 * a realistic stream leaves it on. */
CLEONA_VIDEO_MOCK_API void cleona_video_mock_set_pacing(cleona_video_session_t* s, int32_t on);

/* Whether cleona_video_get_texture_id succeeds (1, the default) or returns
 * CLEONA_VIDEO_ERR_UNSUPPORTED (0), so both branches of the caller are
 * reachable. */
CLEONA_VIDEO_MOCK_API void cleona_video_mock_set_texture_available(cleona_video_session_t* s, int32_t on);

/* Number of cameras the mock pretends to have. Default 2, so
 * cleona_video_switch_camera succeeds. Set to 1 to make it return
 * CLEONA_VIDEO_ERR_UNSUPPORTED. The active camera index is encoded into every
 * produced frame (see cleona_video_mock_frame_camera). */
CLEONA_VIDEO_MOCK_API void cleona_video_mock_set_camera_count(cleona_video_session_t* s, int32_t n);

/* Lowest bitrate step the mock claims to support, in kbps. Default
 * CLEONA_VIDEO_MOCK_DEFAULT_MIN_BITRATE_KBPS.
 *
 * THIS IS THE KNOB THAT PRODUCES CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE
 * (Erratum 1). Deliberately not a boolean "force the error" switch: the error
 * is reached through the real mechanism — a ceiling under which no supported
 * step fits — so a test exercises the decision the backend actually makes, not
 * a shortcut around it. Two ways to reach it:
 *
 *   a) raise this floor above what the ceiling allows, or
 *   b) call cleona_video_reconfigure with a max_frame_bytes so small that even
 *      this floor overshoots it.
 *
 * Both leave the session untouched and running, exactly as the ABI requires.
 * Note that the mock still performs no per-frame rate control; this only
 * bounds what negotiation may settle on. */
#define CLEONA_VIDEO_MOCK_DEFAULT_MIN_BITRATE_KBPS 32
CLEONA_VIDEO_MOCK_API void cleona_video_mock_set_min_bitrate_kbps(
    cleona_video_session_t* s, int32_t kbps);

/* Force the values reported in report.hardware_encode / hardware_decode. The
 * mock defaults to CLEONA_VIDEO_HW_NO for both, which is the truth — it has no
 * hardware. Set CLEONA_VIDEO_HW_NOT_DETERMINABLE to exercise the I11
 * "not determinable" path in the report consumer. */
CLEONA_VIDEO_MOCK_API void cleona_video_mock_set_hardware(cleona_video_session_t* s,
                                    int32_t encode, int32_t decode);

/* ---- readers for the synthetic bitstream, for assertions in tests ----
 *
 * The mock emits Annex-B NAL units with plausible H.264 types: a keyframe is
 * SPS (0x67) + PPS (0x68) + IDR slice (0x65), a delta frame is a single
 * non-IDR slice (0x41). The seven bytes immediately after the NAL header byte
 * of the last NAL unit carry a marker so a test can identify the frame it just
 * read:
 *
 *     [0..4] frame index, 7 bits per byte, most significant group first,
 *            each byte stored as 0x80 | group
 *     [5]    camera index, stored as 0x80 | index
 *     [6]    0xA5 magic
 *
 * Every marker byte has bit 7 set and the filler bytes stay in 0x20..0xDF, so
 * no start-code sequence (00 00 01) can appear anywhere inside a frame by
 * accident. A plain big-endian frame index would write exactly 00 00 00 01 for
 * frame 1 and break every start-code scan over the frame — including the
 * decoder's own.
 *
 * Both readers return -1 if the buffer is not a well-formed mock frame. */
CLEONA_VIDEO_MOCK_API int32_t cleona_video_mock_frame_index(const uint8_t* data, int32_t size);
CLEONA_VIDEO_MOCK_API int32_t cleona_video_mock_frame_camera(const uint8_t* data, int32_t size);

#ifdef __cplusplus
}
#endif

#endif /* CLEONA_VIDEO_MOCK_H */
