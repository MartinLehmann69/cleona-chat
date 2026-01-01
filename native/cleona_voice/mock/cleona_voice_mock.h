/* cleona_voice_mock.h — configuration surface of the hardware-free backend.
 *
 * Work package: docs/SPEC_VOICE_VIDEO_REWORK.md §5 (V0.2).
 *
 * WHY THIS IS A SEPARATE HEADER
 * -----------------------------
 * Everything declared here is OUTSIDE the ABI. cleona_voice.h is the contract
 * that five platform backends and the whole Dart side build against; if the
 * mock's knobs lived in it, a platform package could start depending on them
 * and the contract would quietly grow a test-only tail. Test code includes
 * both headers, production code includes only cleona_voice.h.
 *
 * WHAT THE MOCK IS FOR
 * --------------------
 * SPEC §5 calls the mocks "the actual parallelisation lever": V1.5-V1.9, V1.12
 * and all UI work can start before a single platform backend exists. That only
 * holds if the mock is honest — a mock that merely CLAIMS the invariants would
 * let those packages be built against a contract nothing enforces. So:
 *
 *   - I4 is enforced, not asserted. The mock's internal synthetic "device"
 *     deliberately produces chunks of VARYING size (like miniaudio, which
 *     explicitly does not guarantee a constant callback frame count —
 *     miniaudio.h:6812-6815, defect #7 of the superseded stack). The mock
 *     buffers them into exact frames, which is precisely the work every real
 *     platform layer has to do.
 *   - I6 is enforced, not asserted. Muting does not stop the clock: capture
 *     keeps delivering frames on the same 20 ms cadence, zeroed; playback
 *     keeps accepting writes while the output is muted.
 *   - I11 is enforced: the default effect configuration deliberately contains
 *     an FX_UNKNOWN, so the report path is exercised for the answer that is
 *     hardest to handle and easiest to fake.
 *
 * The mock never claims a real chain: it reports CLEONA_VOICE_CHAIN_MOCK and
 * CLEONA_VOICE_BACKEND_MOCK (both >= 100). A shipped build that emits either
 * is a bug, and that is a checkable release gate.
 */

#ifndef CLEONA_VOICE_MOCK_H
#define CLEONA_VOICE_MOCK_H

#include <stdint.h>

#include "../cleona_voice.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Separate export macro from CLEONA_VOICE_API on purpose: `nm -D` on the mock
 * then shows at a glance which symbols are the contract and which are the test
 * knobs. The build uses -fvisibility=hidden, so anything not annotated here is
 * library-private and cannot be depended on by accident. */
#if defined(_WIN32)
  #define CLEONA_VOICE_MOCK_API __declspec(dllexport)
#else
  #define CLEONA_VOICE_MOCK_API __attribute__((visibility("default")))
#endif

/* Configuration applied to the NEXT cleona_voice_open().
 *
 * Process-global on purpose: cleona_voice_open() takes only rate_hint and
 * out_format (the ABI is fixed), so there is no per-call channel to pass this
 * through. Set it before open(); it is copied into the session at open time
 * and later changes to the global do not affect a live session.
 *
 * A zeroed struct is NOT a valid configuration — use
 * cleona_voice_mock_config_default() and then override fields. */
typedef struct {
    /* Format the mock will "negotiate".
     * If `force_rate` > 0 the mock ignores rate_hint entirely and reports
     * force_rate — this is how a test exercises I3 ("the hint may be ignored,
     * that is not an error"). If 0, the mock honours a valid rate_hint and
     * otherwise falls back to `default_rate`. */
    int32_t force_rate;
    int32_t default_rate;          /* used when rate_hint is 0/invalid */

    /* Verification report content. */
    int32_t aec_state;             /* CLEONA_VOICE_FX_*    */
    int32_t ns_state;
    int32_t agc_state;
    int32_t chain_origin;          /* CLEONA_VOICE_CHAIN_*  */
    int32_t duplex;                /* normally 1; settable ONLY so that a
                                    * conformance harness can prove its own
                                    * duplex check actually fails when it must */

    /* Route model. */
    int32_t routes_available_mask; /* CLEONA_VOICE_ROUTE_BIT(...) | ... */
    int32_t route_active_in;
    int32_t route_active_out;

    /* Synthetic capture tone. 0 Hz produces digital silence. */
    int32_t tone_hz;
    int32_t tone_amplitude;        /* 0..32767 */

    /* Failure injection. */
    int32_t open_error;            /* if < 0, open() returns NULL and writes
                                    * this code into out_format->sample_rate */
    int32_t start_error;           /* if < 0, start() returns it            */

    /* Internal capture chunking. The synthetic device hands the mock chunks of
     * a pseudo-random size in [chunk_min, chunk_max] samples, so that the
     * frame-size guarantee is produced by real buffering. Set both to the
     * frame size to disable the jitter. */
    int32_t chunk_min;
    int32_t chunk_max;
} cleona_voice_mock_config_t;

/* Fills `cfg` with the default configuration:
 *   default_rate = 48000, mono, 20 ms  -> frame_samples 960
 *   aec = ENABLED, ns = AVAILABLE_OFF, agc = UNKNOWN
 *     (three of the four states in one report, including the
 *      "not_determinable" case, so the report path cannot be written for the
 *      happy answer only)
 *   chain_origin = CLEONA_VOICE_CHAIN_MOCK, duplex = 1
 *   routes = EARPIECE | SPEAKER | WIRED, active out = EARPIECE
 *     (an earpiece is present by default so that RoutePolicy's I7 fallback is
 *      testable against the mock; use cleona_voice_mock_config_desktop() for
 *      the no-earpiece case)
 *   tone 440 Hz at amplitude 8000
 *   chunk_min = 37, chunk_max = 311 samples (deliberately coprime-ish and
 *     never equal to a frame, so no test can accidentally pass because the
 *     chunk size happened to match) */
CLEONA_VOICE_MOCK_API void cleona_voice_mock_config_default(cleona_voice_mock_config_t* cfg);

/* Like _default(), but models a desktop chain: no earpiece
 * (routes = SPEAKER | WIRED, active out = SPEAKER), so that
 * cleona_voice_set_route(s, CLEONA_VOICE_ROUTE_EARPIECE) returns
 * CLEONA_VOICE_ERR_ROUTE_UNAVAILABLE — the case SPEC §4 calls out. */
CLEONA_VOICE_MOCK_API void cleona_voice_mock_config_desktop(cleona_voice_mock_config_t* cfg);

/* Installs the configuration used by the next cleona_voice_open().
 * Passing NULL restores cleona_voice_mock_config_default(). */
CLEONA_VOICE_MOCK_API void cleona_voice_mock_set_config(const cleona_voice_mock_config_t* cfg);

/* Queues an event for cleona_voice_poll_event(). Returns 0, or -1 if the
 * session is NULL or the queue is full. Used to simulate route changes,
 * interruptions and format changes without hardware. */
CLEONA_VOICE_MOCK_API int32_t cleona_voice_mock_push_event(cleona_voice_session_t* s,
                                     int32_t event, int32_t arg);

/* Simulates a route change originating from the platform (headset plugged in,
 * Bluetooth connected/disconnected): replaces the mask, optionally moves the
 * active output route, and queues EV_ROUTES_CHANGED carrying the new mask.
 * If `new_active_out` is CLEONA_VOICE_ROUTE_UNKNOWN the active route is left
 * alone unless it just disappeared from the mask — in which case it is set to
 * ROUTE_UNKNOWN so that the Dart RoutePolicy has to make the I7 decision
 * instead of the mock silently making it. */
CLEONA_VOICE_MOCK_API int32_t cleona_voice_mock_set_routes(cleona_voice_session_t* s,
                                     int32_t new_mask,
                                     int32_t new_active_out);

/* Bumps the underrun / overrun counters so the report path can be tested
 * without provoking real timing faults. */
CLEONA_VOICE_MOCK_API void cleona_voice_mock_add_underruns(cleona_voice_session_t* s, int64_t n);
CLEONA_VOICE_MOCK_API void cleona_voice_mock_add_overruns(cleona_voice_session_t* s, int64_t n);

/* Observability for tests: how many frames the mock has handed out / taken in,
 * and how many playback frames were swallowed while the output was muted.
 * Any out pointer may be NULL. */
CLEONA_VOICE_MOCK_API void cleona_voice_mock_get_counters(cleona_voice_session_t* s,
                                    int64_t* out_capture_frames,
                                    int64_t* out_playback_frames,
                                    int64_t* out_muted_playback_frames);

/* Overrides the negotiated format at runtime and queues EV_FORMAT_CHANGED,
 * so the I3 re-negotiation path ("re-read the report, re-size the buffers")
 * can be exercised. Returns CLEONA_VOICE_OK or a negative error. */
CLEONA_VOICE_MOCK_API int32_t cleona_voice_mock_force_format(cleona_voice_session_t* s,
                                       int32_t new_rate);

#ifdef __cplusplus
}
#endif

#endif /* CLEONA_VOICE_MOCK_H */
