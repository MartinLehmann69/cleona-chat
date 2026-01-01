/* cleona_voice.h — the one boundary between Cleona and the operating system's
 * voice-communication chain.
 *
 * Architecture: Cleona_Chat_Architecture_v3_0.md §10.4 (normative).
 * Work package: docs/SPEC_VOICE_VIDEO_REWORK.md §4 (V0.2).
 *
 * ---------------------------------------------------------------------------
 * WHAT THIS IS
 * ---------------------------------------------------------------------------
 * Cleona performs NO audio DSP of its own (I1). Echo cancellation, noise
 * suppression and automatic gain control come from the OS voice chain — the
 * same chain a telephony call uses on the device. Cleona captures
 * already-processed PCM, encrypts it, ships it, and hands received PCM back to
 * the SAME OS session.
 *
 * Five native implementations sit behind this header (Android JNI/Kotlin,
 * Apple VoiceProcessingIO, Windows WASAPI Communications, Linux PipeWire, and
 * the hardware-free mock in mock/). In front of it there is exactly one Dart
 * binding (lib/core/calls/voice_session.dart) and one route policy.
 *
 * ---------------------------------------------------------------------------
 * NON-NEGOTIABLE INVARIANTS (SPEC §2) — every backend, no exceptions
 * ---------------------------------------------------------------------------
 *   I1  No DSP of our own. AEC/NS/AGC come from the OS.
 *   I2  Capture and playback live in ONE OS duplex session. `duplex` MUST be 1.
 *       Two independent devices on two clocks are the reason the previous
 *       stack's AEC never worked.
 *   I3  A sample rate is NEVER forced. The platform reports it; everything
 *       above computes with the reported value.
 *   I4  The frame size is GUARANTEED by the platform layer (which buffers
 *       internally), never assumed. The superseded stack assumed a constant
 *       callback frame count and silently dropped frames when the assumption
 *       broke (cleona_audio.c:151, :202).
 *   I5  Pacing is done by the output device. No timer in the playback path.
 *   I6  Mute keeps streams OPEN. Mic mute zeroes frames; output mute renders
 *       silence. A stream is never torn down for a mute.
 *   I7  When the active route disappears, fall back to the EARPIECE, never to
 *       the speaker. A phone does not blast the room when headphones are
 *       unplugged. (Policy lives in Dart; this ABI only has to make the route
 *       set observable and switchable without stream teardown.)
 *   I11 The verification report is a mandatory part of this ABI.
 *       CLEONA_VOICE_FX_UNKNOWN ("not_determinable") is a legitimate answer.
 *       Guessing CLEONA_VOICE_FX_ENABLED is a conformance failure. A gate
 *       derived from the same assumption as the thing it checks is worthless.
 *
 * ---------------------------------------------------------------------------
 * FRAME CONTRACT (architecture §10.4, "Frame contract")
 * ---------------------------------------------------------------------------
 *   Format         16-bit signed PCM, mono, interleaved. The only format all
 *                  five chains deliver without conversion.
 *   Sample rate    whatever the platform reports; cleona_voice_open() returns
 *                  it. Forcing 16 kHz excludes Android's fast path and fights
 *                  Apple's VPIO, which works at the hardware rate.
 *   Frame duration 20 ms, i.e. frame_samples == sample_rate / 50.
 *   Frame size     guaranteed by the platform layer, which buffers internally.
 *   Pacing         the output device, normatively.
 *   Duplex         mandatory. Without it there is no AEC.
 *
 * ---------------------------------------------------------------------------
 * THREADING
 * ---------------------------------------------------------------------------
 * A session is used from at most three threads concurrently:
 *   - one capture thread calling cleona_voice_capture_read() in a loop,
 *   - one playback thread calling cleona_voice_playback_write(),
 *   - any thread calling the control, event and report functions.
 * All functions except cleona_voice_close() are safe to call concurrently in
 * that arrangement. cleona_voice_close() requires that no other call is in
 * flight and that cleona_voice_stop() has returned.
 *
 * Only cleona_voice_capture_read() may block, and only for at most
 * `timeout_ms`. Everything else returns promptly; poll_event never blocks.
 */

#ifndef CLEONA_VOICE_H
#define CLEONA_VOICE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
  #define CLEONA_VOICE_API __declspec(dllexport)
#else
  #define CLEONA_VOICE_API __attribute__((visibility("default")))
#endif

/* ==========================================================================
 * Format
 * ========================================================================== */

typedef struct cleona_voice_session cleona_voice_session_t;

typedef struct {
    int32_t sample_rate;     /* negotiated, e.g. 48000 — never assumed  */
    int32_t channels;        /* 1                                        */
    int32_t frame_samples;   /* sample_rate / 50  (20 ms)                */
    int32_t frame_bytes;     /* frame_samples * channels * 2             */
} cleona_voice_format_t;

/* Normative bounds on the negotiated format. Derived from SPEC §6 check 1 and
 * the frame-contract table in §10.4. A backend reporting outside these bounds
 * is not conformant — callers may reject it rather than compensate.
 *
 * These constants exist so that callers can VALIDATE what the platform
 * reported. They are explicitly NOT defaults and must never be used as a
 * substitute for the value returned by cleona_voice_open() (I3/I4). */
#define CLEONA_VOICE_RATE_MIN   8000
#define CLEONA_VOICE_RATE_MAX  48000
#define CLEONA_VOICE_FRAME_HZ     50   /* 20 ms frames */
#define CLEONA_VOICE_CHANNELS      1   /* mono, interleaved, S16 */

/* ==========================================================================
 * Effect state — I11: UNKNOWN is a legitimate answer, never guess ENABLED
 * ==========================================================================
 * UNAVAILABLE    the chain does not offer this effect on this device
 * AVAILABLE_OFF  the effect exists and is verifiably NOT running
 * ENABLED        the effect exists and was verifiably read back as running
 * UNKNOWN        the platform gives no way to read the state back.
 *                Rendered as "not_determinable" in the verification report.
 *                This is a permitted, expected answer on some chains — it is
 *                NOT an error and must never be upgraded to ENABLED because
 *                "we asked for it". Asking is not evidence.
 */
#define CLEONA_VOICE_FX_UNAVAILABLE    0
#define CLEONA_VOICE_FX_AVAILABLE_OFF  1
#define CLEONA_VOICE_FX_ENABLED        2
#define CLEONA_VOICE_FX_UNKNOWN        3

/* ==========================================================================
 * Where the chain comes from
 * ==========================================================================
 * If any of aec_state / ns_state / agc_state is CLEONA_VOICE_FX_ENABLED, then
 * chain_origin MUST NOT be CLEONA_VOICE_CHAIN_NONE (SPEC §6 check 7). An
 * enabled effect with no stated origin is exactly the unfalsifiable claim this
 * report exists to eliminate. */
#define CLEONA_VOICE_CHAIN_NONE            0
#define CLEONA_VOICE_CHAIN_ANDROID_HAL     1
#define CLEONA_VOICE_CHAIN_APPLE_VPIO      2
#define CLEONA_VOICE_CHAIN_WIN_ENDPOINT    3
#define CLEONA_VOICE_CHAIN_WIN_VOICE_DSP   4
#define CLEONA_VOICE_CHAIN_PIPEWIRE_FILTER 5
#define CLEONA_VOICE_CHAIN_LINKED_APM      6
/* 7..99 reserved for future real chains.
 * 100+ is the out-of-band range for non-shipping backends. The mock uses it so
 * that it never has to impersonate a real chain in a report — a mock that
 * claimed CHAIN_PIPEWIRE_FILTER would make the verification report lie, which
 * is the one thing this report may not do. A shipped build must never emit a
 * value >= 100; asserting that is a valid release gate. */
#define CLEONA_VOICE_CHAIN_MOCK          100

/* ==========================================================================
 * Backend identity (the `backend` field of the report)
 * ==========================================================================
 * SPEC §4 leaves this "platform-defined". It is defined HERE instead, because
 * the report is parsed by one shared Dart binding and written as one log line
 * per call: a per-platform private numbering would make that line undecodable
 * off-device. Numbers are a permanent registry — append only, never renumber. */
#define CLEONA_VOICE_BACKEND_UNKNOWN             0
#define CLEONA_VOICE_BACKEND_PIPEWIRE            1  /* Linux   — V1.1 */
#define CLEONA_VOICE_BACKEND_ANDROID_AUDIORECORD 2  /* Android — V1.2 */
#define CLEONA_VOICE_BACKEND_APPLE_VPIO          3  /* iOS/macOS — V1.3 */
#define CLEONA_VOICE_BACKEND_WASAPI              4  /* Windows — V1.4 */
/* 5..99 reserved. 100+ non-shipping, see CLEONA_VOICE_CHAIN_MOCK. */
#define CLEONA_VOICE_BACKEND_MOCK              100

/* ==========================================================================
 * Routes
 * ==========================================================================
 * `routes_available_mask` is a bitmask built with CLEONA_VOICE_ROUTE_BIT().
 *
 * CLEONA_VOICE_ROUTE_UNKNOWN is a state, not a route: it is NEVER set in the
 * mask. A started session MUST report route_active_out != ROUTE_UNKNOWN and
 * that route MUST be present in the mask (SPEC §6 check 8). Before
 * cleona_voice_start(), ROUTE_UNKNOWN is permitted — the platform may not have
 * resolved its device set yet, and guessing would violate I11 in spirit. */
#define CLEONA_VOICE_ROUTE_UNKNOWN   0
#define CLEONA_VOICE_ROUTE_EARPIECE  1
#define CLEONA_VOICE_ROUTE_SPEAKER   2
#define CLEONA_VOICE_ROUTE_WIRED     3
#define CLEONA_VOICE_ROUTE_BLUETOOTH 4

#define CLEONA_VOICE_ROUTE_BIT(r)  (1 << (r))

/* ==========================================================================
 * Events — polled, deliberately no callbacks across the FFI boundary
 * ==========================================================================
 * Polling is a design decision, not a shortcut: a callback would have to cross
 * the FFI/isolate boundary, which would couple every platform package to the
 * Dart-side isolate arrangement. Polling keeps the five platform packages
 * independent of each other and of Dart.
 *
 * `out_arg` per event:
 *   EV_NONE               out_arg = 0
 *   EV_ROUTES_CHANGED     out_arg = the new routes_available_mask
 *   EV_INTERRUPTION_BEGIN out_arg = 0 (reserved)
 *   EV_INTERRUPTION_END   out_arg = 0 (reserved)
 *   EV_FORMAT_CHANGED     out_arg = the new sample_rate. The caller MUST
 *                         re-read cleona_voice_get_report() and re-size its
 *                         buffers before the next capture_read (I3/I4).
 */
#define CLEONA_VOICE_EV_NONE               0
#define CLEONA_VOICE_EV_ROUTES_CHANGED     1
#define CLEONA_VOICE_EV_INTERRUPTION_BEGIN 2
#define CLEONA_VOICE_EV_INTERRUPTION_END   3
#define CLEONA_VOICE_EV_FORMAT_CHANGED     4

/* ==========================================================================
 * Return codes
 * ==========================================================================
 * SPEC §4 requires "a defined error code instead of failing silently" for
 * set_route on a platform without an earpiece, but does not enumerate the
 * codes. They are defined here and are binding for all five backends.
 *
 * RULE FOR CALLERS: test `< 0`, never `== -1`. Every failure is negative;
 * -1 is kept as the generic/argument failure so that older code testing
 * `== -1` still sees an error rather than a success.
 *
 * cleona_voice_capture_read() deliberately does NOT use this enum — it has its
 * own tri-state (see CLEONA_VOICE_CAPTURE_* below), because 0 there means
 * "timeout", not "success".
 */
#define CLEONA_VOICE_OK                     0
#define CLEONA_VOICE_ERR_INVALID_ARG      (-1)  /* NULL pointer / value out of range   */
#define CLEONA_VOICE_ERR_CLOSED           (-2)  /* session closed or never opened      */
#define CLEONA_VOICE_ERR_NOT_STARTED      (-3)  /* operation requires a running session*/
#define CLEONA_VOICE_ERR_ALREADY_STARTED  (-4)  /* start() on a running session        */
#define CLEONA_VOICE_ERR_FRAME_SIZE       (-5)  /* frame_samples != negotiated size    */
#define CLEONA_VOICE_ERR_ROUTE_UNAVAILABLE (-6) /* route valid but not in the current
                                                 * routes_available_mask — this is the
                                                 * code a desktop backend returns for
                                                 * ROUTE_EARPIECE (SPEC §4)            */
#define CLEONA_VOICE_ERR_ROUTE_UNSUPPORTED (-7) /* backend has no route control at all */
#define CLEONA_VOICE_ERR_BACKEND          (-8)  /* the platform API refused            */
#define CLEONA_VOICE_ERR_NO_DEVICE        (-9)  /* no usable capture/playback device   */
#define CLEONA_VOICE_ERR_PERMISSION      (-10)  /* microphone permission denied        */
#define CLEONA_VOICE_ERR_UNSUPPORTED     (-11)  /* not implemented by this backend     */

/* cleona_voice_capture_read() tri-state. */
#define CLEONA_VOICE_CAPTURE_FRAME     1   /* exactly frame_samples written to out */
#define CLEONA_VOICE_CAPTURE_TIMEOUT   0   /* nothing written, try again           */
#define CLEONA_VOICE_CAPTURE_CLOSED  (-1)  /* stopped or closed — leave the loop   */

/* ==========================================================================
 * Verification report (I11) — normative part of the ABI
 * ==========================================================================
 * The superseded stack could not answer "is the AEC running?" even in
 * principle. The replacement must, or the same mistake repeats.
 *
 * Logged exactly once per call (lib/core/calls/voice_report.dart) and
 * assertable in E2E. Every field is an observation, not an intention:
 *   - `*_state` is what was READ BACK from the platform, not what was asked
 *     for. If it cannot be read back, the answer is FX_UNKNOWN.
 *   - `duplex` MUST be 1. A backend that cannot deliver one OS duplex session
 *     is not acceptance-capable (I2).
 *   - `underruns`/`overruns` are monotonic counters since open().
 *
 * MUTE STATE (erratum E6a) — architecture §10.4, "In-call controls"
 * -----------------------------------------------------------------
 * §10.4 states normatively that "the mute states survive route changes". Until
 * E6a the ABI had no getter for them, so that sentence could not be checked at
 * all: the only observable was the capture signal level, and in a quiet room a
 * muted stream and an unmuted one look the same. A normative assurance the ABI
 * does not make observable is not enforceable — the same class of defect as the
 * superseded stack, which could not answer whether its AEC was running.
 *
 * `mic_muted` / `output_muted` therefore report, as a plain observation:
 *   - the state last set through cleona_voice_set_mic_muted() /
 *     cleona_voice_set_output_muted(), as exactly 0 or exactly 1. Not "some
 *     truthy value": the report is read field by field by one Dart binding and
 *     compared numerically by the conformance harness;
 *   - 0 / 0 after cleona_voice_open(), before anything was set;
 *   - UNCHANGED across cleona_voice_set_route() and across an
 *     EV_ROUTES_CHANGED. That is the §10.4 assurance, and it is now a
 *     conformance check (S13) rather than a promise;
 *   - NOTHING about whether a stream is running. I6 requires the streams to
 *     stay open while muted, so mic_muted == 1 with capture_read still
 *     returning frames on cadence is the CORRECT state, not a contradiction.
 *     Mute is content, not a lifetime signal. A backend that stops a stream on
 *     mute fails C5 regardless of what it reports here.
 *
 * A backend does not get to answer "unknown" here the way it may for an effect
 * state: it was told the value, so it knows it. If the platform owns a mute
 * property that can also be changed from outside the process, report the
 * platform's current value — that is still an observation, and it is the more
 * useful one.
 */
typedef struct {
    cleona_voice_format_t format;
    int32_t aec_state, ns_state, agc_state;   /* CLEONA_VOICE_FX_*     */
    int32_t chain_origin;                     /* CLEONA_VOICE_CHAIN_*  */
    int32_t backend;                          /* CLEONA_VOICE_BACKEND_* */
    int32_t duplex;                           /* 1 = single session — I2 */
    int32_t route_active_in, route_active_out;
    int32_t routes_available_mask;            /* bitmask of ROUTE_*    */
    /* E6a. Appended AFTER the existing int32 block and BEFORE the int64 pair on
     * purpose: the int32 block stays one contiguous run in declaration order, so
     * every field up to routes_available_mask keeps the offset it always had
     * (mic_muted at 52 takes over the 4 bytes that used to be pure alignment
     * padding). Only underruns/overruns shift, from 56/64 to 64/72. Putting them
     * anywhere else — e.g. next to duplex — would have moved six unrelated
     * fields for no gain. */
    int32_t mic_muted;      /* 1 = capture is muted, 0 = not. I6: the stream stays
                               open either way — this reports intent, not liveness. */
    int32_t output_muted;   /* 1 = playback renders silence, 0 = not. */
    int64_t underruns, overruns;
} cleona_voice_report_t;

/* ---- lifecycle ---- */

/* Opens ONE OS duplex voice session (I2) and negotiates the format.
 *
 * `rate_hint` is a hint and nothing more (I3). A backend that cannot get the
 * hinted rate returns its own rate — that is NOT an error. Pass 0 for "no
 * preference". Callers MUST use the returned format and MUST NOT assume the
 * hint was honoured.
 *
 * On success: returns a session and writes the negotiated format to
 * `out_format` (which must be non-NULL).
 *
 * On failure: returns NULL. The ABI has no out-of-band error channel by
 * design (no thread-local errno, no extra entry point), so the reason is
 * conveyed in-band: if `out_format` is non-NULL, the backend writes a negative
 * CLEONA_VOICE_ERR_* into `out_format->sample_rate` and zeroes the other three
 * fields. Callers can therefore distinguish "no microphone" from "permission
 * denied" without a second call. A sample_rate <= 0 is never a valid format,
 * so this cannot be confused with success.
 *
 * Does NOT start the streams — call cleona_voice_start(). */
CLEONA_VOICE_API cleona_voice_session_t* cleona_voice_open(
    int32_t rate_hint, cleona_voice_format_t* out_format);

/* Starts capture and playback of the single duplex session.
 * Returns CLEONA_VOICE_OK or a negative CLEONA_VOICE_ERR_*.
 * CLEONA_VOICE_ERR_ALREADY_STARTED if the session is already running. */
CLEONA_VOICE_API int32_t cleona_voice_start(cleona_voice_session_t* s);

/* Stops both directions. Idempotent; safe on a session that never started.
 * After stop(), cleona_voice_capture_read() returns CLEONA_VOICE_CAPTURE_CLOSED
 * and cleona_voice_playback_write() returns CLEONA_VOICE_ERR_NOT_STARTED.
 * A stopped session may be started again; the negotiated format is retained. */
CLEONA_VOICE_API void cleona_voice_stop(cleona_voice_session_t* s);

/* Releases the session. Calls stop() internally if needed. NULL is a no-op.
 * The pointer is invalid afterwards; no other call may be in flight. */
CLEONA_VOICE_API void cleona_voice_close(cleona_voice_session_t* s);

/* ---- data path ---- */

/* Reads exactly ONE frame of exactly format.frame_samples samples.
 *
 * I4: the frame size is guaranteed here. A backend whose device callback
 * delivers a varying number of samples MUST buffer internally until a full
 * frame is available. It must never return a short frame, and it must never
 * drop a partial frame the way the superseded stack did
 * (cleona_audio.c:151 — `if (frame_count != frame_samples) return;`).
 *
 * `out` must hold at least format.frame_bytes bytes.
 * Blocks at most `timeout_ms` (0 = poll, do not block).
 *
 * Returns CLEONA_VOICE_CAPTURE_FRAME (1)   — frame written,
 *         CLEONA_VOICE_CAPTURE_TIMEOUT (0) — nothing written, call again,
 *         CLEONA_VOICE_CAPTURE_CLOSED (-1) — session stopped/closed, stop looping.
 *
 * While the microphone is muted this keeps returning frames at the same
 * cadence — zeroed, but on time (I6). Callers must not use "no frames" as a
 * mute indication. */
CLEONA_VOICE_API int32_t cleona_voice_capture_read(cleona_voice_session_t* s,
                                                   int16_t* out,
                                                   int32_t timeout_ms);

/* Hands one decoded frame to the OS playback side of the SAME session.
 *
 * `frame_samples` MUST equal format.frame_samples; a mismatch is rejected with
 * CLEONA_VOICE_ERR_FRAME_SIZE rather than being padded or truncated (SPEC §6
 * check 4). Silent adaptation here is how a rate mismatch becomes a mystery
 * later.
 *
 * Never blocks (I5): pacing is the output device's job. If the caller is late,
 * the device underruns and the counter in the report moves — the write does
 * not wait.
 *
 * Returns CLEONA_VOICE_OK (0) on success, negative CLEONA_VOICE_ERR_* on
 * failure. Test `< 0`, not `== -1`. */
CLEONA_VOICE_API int32_t cleona_voice_playback_write(cleona_voice_session_t* s,
                                                     const int16_t* pcm,
                                                     int32_t frame_samples);

/* ---- controls (I6, I7) ---- */

/* Microphone mute. The capture stream STAYS OPEN and keeps running; frames are
 * zeroed or the platform's own input-mute property is used (I6).
 *
 * Stopping the stream instead diverges the adaptive filter and produces about
 * a second of echo on unmute. The superseded C code already knew this and kept
 * draining the reference while muted (cleona_audio.c:152-156); the insight
 * must survive the rewrite.
 *
 * Nothing is sent on the wire while muted — that is the caller's decision, not
 * this layer's.
 *
 * The state survives cleona_voice_set_route() and EV_ROUTES_CHANGED (§10.4) and
 * is readable back from cleona_voice_get_report().mic_muted, which is what makes
 * that sentence checkable (erratum E6a). */
CLEONA_VOICE_API void cleona_voice_set_mic_muted(cleona_voice_session_t* s,
                                                 int32_t muted);

/* Output mute ("sound off"), distinct from speakerphone. The playback stream
 * stays open and renders SILENCE (I6). playback_write keeps accepting frames
 * and keeps returning CLEONA_VOICE_OK; the caller keeps decrypting and the
 * jitter buffer keeps running normally.
 *
 * The superseded implementation did the opposite — _drainJitterBuffer returned
 * early while the speaker was off (audio_engine.dart:353), so the buffer filled
 * to its cap and produced a backlog burst on re-enable. Rejecting writes here
 * would recreate exactly that.
 *
 * Like the microphone mute, the state survives route changes and is readable
 * back from cleona_voice_get_report().output_muted (erratum E6a). */
CLEONA_VOICE_API void cleona_voice_set_output_muted(cleona_voice_session_t* s,
                                                    int32_t muted);

/* Switches the active output route WITHOUT tearing the stream down, so the AEC
 * stays converged. Where a platform forces a rebuild, that convergence cost is
 * documented as a known property of that backend.
 *
 * Returns:
 *   CLEONA_VOICE_OK                    switched (or already active)
 *   CLEONA_VOICE_ERR_INVALID_ARG       `route` is not a CLEONA_VOICE_ROUTE_*
 *                                      constant, or is ROUTE_UNKNOWN
 *   CLEONA_VOICE_ERR_ROUTE_UNAVAILABLE the constant is valid but the route is
 *                                      not in routes_available_mask. This is
 *                                      what a desktop backend returns for
 *                                      ROUTE_EARPIECE: macOS, Windows and
 *                                      Linux have no earpiece, and SPEC §4
 *                                      requires a defined code instead of a
 *                                      silent no-op. The UI reacts by showing
 *                                      a device chooser instead of a
 *                                      speakerphone button that does nothing.
 *   CLEONA_VOICE_ERR_ROUTE_UNSUPPORTED the backend has no route control at all
 *   CLEONA_VOICE_ERR_BACKEND           the platform API refused the switch
 *
 * Neither mute state is affected by a route switch: after this call,
 * cleona_voice_get_report() must report the same mic_muted and output_muted as
 * before it (§10.4, "the mute states survive route changes"; conformance check
 * S13). A backend that rebuilds its session to switch routes has to carry the
 * two flags across the rebuild — the user muted the microphone, not the
 * earpiece.
 *
 * I7 is a POLICY rule and lives once, in Dart (RoutePolicy, V1.5): when the
 * active route disappears the policy picks the earpiece, never the speaker.
 * This function only has to make that choice executable and its failure
 * visible. */
CLEONA_VOICE_API int32_t cleona_voice_set_route(cleona_voice_session_t* s,
                                                int32_t route);

/* Writes the current route bitmask to *out_mask and the active OUTPUT route to
 * *out_active. Both pointers must be non-NULL.
 * The active route is always present in the mask on a started session
 * (SPEC §6 check 8). Returns CLEONA_VOICE_OK or negative. */
CLEONA_VOICE_API int32_t cleona_voice_get_routes(cleona_voice_session_t* s,
                                                 int32_t* out_mask,
                                                 int32_t* out_active);

/* ---- events ---- */

/* Non-blocking. Dequeues at most one event.
 * Writes CLEONA_VOICE_EV_NONE and 0 when the queue is empty — that is the
 * normal, expected case and NOT an error.
 *
 * The RETURN VALUE is a status, not the event: CLEONA_VOICE_OK when an event
 * (possibly EV_NONE) was written, negative CLEONA_VOICE_ERR_* otherwise.
 * Read the event from *out_event.
 *
 * Both out pointers must be non-NULL. Events are delivered in order; a backend
 * whose internal queue overflows drops the OLDEST entries and must ensure the
 * newest EV_ROUTES_CHANGED survives, since it carries the current mask. */
CLEONA_VOICE_API int32_t cleona_voice_poll_event(cleona_voice_session_t* s,
                                                 int32_t* out_event,
                                                 int32_t* out_arg);

/* ---- report (I11) ---- */

/* Fills the verification report. Never fails, never blocks, never guesses.
 * If `s` is NULL the struct is zeroed, which yields duplex == 0 and therefore
 * reads as a conformance failure rather than as a plausible session.
 * Safe to call before start() — route fields may then be ROUTE_UNKNOWN. */
CLEONA_VOICE_API void cleona_voice_get_report(cleona_voice_session_t* s,
                                              cleona_voice_report_t* out);

/* Layout guard. The Dart binding declares this struct field by field
 * (lib/core/calls/voice_report.dart / voice_session.dart); a silent layout
 * drift between C and Dart would misread every field after the offset that
 * moved. 15 x int32 = 60 bytes, 4 bytes of padding so the int64 pair is
 * 8-aligned, 2 x int64 = 80. (Before erratum E6a it was 13 x int32 = 52 + 4
 * padding + 16 = 72; mic_muted and output_muted are the two added words.)
 * Asserted only on 64-bit GCC/Clang targets (arm64, x86_64), where the layout
 * is unambiguous. It is deliberately skipped elsewhere rather than guessed:
 * i386 System V aligns int64_t to 4 and would legitimately produce 68 (76 with
 * E6a). All shipping Cleona targets are 64-bit (preflight.sh checks arm64-v8a
 * and x86_64 jniLibs only). */
#if defined(__SIZEOF_POINTER__) && (__SIZEOF_POINTER__ == 8)
_Static_assert(sizeof(cleona_voice_report_t) == 80,
               "cleona_voice_report_t layout changed — update the Dart binding "
               "in lib/core/calls/voice_session.dart in the same commit");
_Static_assert(sizeof(cleona_voice_format_t) == 16,
               "cleona_voice_format_t layout changed — update the Dart binding");
#endif

#ifdef __cplusplus
}
#endif

#endif /* CLEONA_VOICE_H */
