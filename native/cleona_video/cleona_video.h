/* cleona_video.h — the one boundary between Cleona and every platform video
 * stack. Frozen contract, work package V0.3 of docs/SPEC_VOICE_VIDEO_REWORK.md
 * (§4b). Authoritative background: Cleona_Chat_Architecture_v3_0.md §10.6
 * ("Native Video Stack") and §10.3.1 ("Transport treatment").
 *
 * ---------------------------------------------------------------------------
 * WHAT THIS ABI IS FOR
 * ---------------------------------------------------------------------------
 * The platform captures, the platform's hardware codec encodes and decodes,
 * and Cleona handles only the encrypted bitstream. Cleona performs no pixel
 * processing (§10.6).
 *
 *     camera -> platform surface -> hardware encoder -> [ this ABI ] -> Dart
 *     Dart -> [ this ABI ] -> hardware decoder -> texture -> Flutter
 *
 * Everything below this header is platform code. Everything above it is Dart
 * (lib/core/calls/video_pipeline.dart). Pixels never cross the line in either
 * direction — invariant I10. The only two things that cross are:
 *
 *   1. an encoded bitstream (cleona_video_read_encoded /
 *      cleona_video_submit_encoded), and
 *   2. an opaque texture id (cleona_video_get_texture_id).
 *
 * A backend that hands raw frames up, or expects raw frames down, is not
 * acceptance-ready. Neither is one that requires dart:ui to exist: the
 * superseded VideoEngine sat behind a Flutter-only factory, which is why
 * createVideoEngine stays null in the Linux/Windows daemon and desktop video
 * calls degrade to audio-only by construction (lib/main.dart:2163-2171). The
 * platform layer of §10.6 sits *below* this header and has no such dependency.
 *
 * ---------------------------------------------------------------------------
 * THE FRAME SIZE CEILING (I9) — READ THIS BEFORE IMPLEMENTING AN ENCODER
 * ---------------------------------------------------------------------------
 * Live media is plain UDP, AES-encrypted, fire-and-forget, and that is
 * normative at *every* layer, not only at the acknowledgement layer (§10.3.1).
 * A live-media frame is exempt from TLS escalation and from retransmission-
 * based fragment recovery (CFNK NACK) — invariant I8. Both instruments are
 * wrong for a payload with a 20-33 ms deadline: sendBulkViaTLS opens a fresh
 * TCP+TLS connection per payload, and the fragmenter's first NACK retry fires
 * after 500 ms, by which time the frame is stale.
 *
 * The consequence is a constraint on the *encoder*, not on the transport.
 * cleona_video_config_t::max_frame_bytes is where it is enforced. See the
 * field documentation below for the exact obligation and for what
 * cleona_video_report_t::frames_dropped_oversize counts.
 *
 * The ABI deliberately does NOT hard-code the numeric value of that ceiling.
 * It is derived from the plain-UDP delivery envelope, which is owned by the
 * transport package (V1.11, lib/core/network/udp_fragmenter.dart). Baking a
 * transport constant into the video ABI would create a second copy of a number
 * that only one package is allowed to change.
 *
 * ---------------------------------------------------------------------------
 * ERRATUM 1 (project owner, 2026-07-30) — THE CEILING MOVES, AND SILENCE IS
 * NEVER THE ANSWER
 * ---------------------------------------------------------------------------
 * The ceiling follows the available bandwidth and is therefore *not* fixed for
 * the lifetime of the session. It is re-derived from the running bandwidth
 * estimate and pushed down with cleona_video_reconfigure().
 *
 * The resulting obligation on every backend, in order:
 *
 *   1. bandwidth drops -> the caller lowers max_frame_bytes (and usually
 *      bitrate, fps or resolution with it) and calls reconfigure. The backend
 *      SCALES DOWN and keeps sending.
 *   2. not even the lowest supported step fits under the new ceiling ->
 *      reconfigure returns CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE. The caller then
 *      stops video and TELLS THE USER WHY, locally and at the peer (V1.12
 *      CALL_MEDIA_STATE carries the "I am sending video" flag).
 *
 * There is no third branch. A backend must never quietly stop producing
 * frames, and it must never quietly discard them: "no picture and no reason
 * given" is precisely the failure this section exists to remove.
 *
 * frames_dropped_oversize is consequently a DEFECT COUNTER, not a working
 * mechanism. In the field it must read 0. Any value above 0 means the scaling
 * in step 1 failed to keep up, or step 2 was not taken — see the field
 * documentation.
 *
 * ONE BENIGN EXCEPTION, stated so that nobody has to guess whether a 1 is a
 * bug: a reconfigure that lowers the ceiling while a frame is already encoded
 * and waiting to be read discards that frame and counts it. The frame was legal
 * when it was produced; it is dropped rather than delivered because the
 * guarantee "no frame handed out ever exceeds negotiated.max_frame_bytes" is
 * what every caller sizes its read buffer from, and breaking it would be worse
 * than losing one frame. The tick is therefore bounded by one per reconfigure,
 * and a caller that reconfigures right after a successful read never sees it.
 * A counter that tracks the reconfigure count is this exception; a counter that
 * grows with the frame rate is the defect.
 *
 * ---------------------------------------------------------------------------
 * ERRATUM 6b (project owner, 2026-07-30) — open() SAYS WHY IT FAILED
 * ---------------------------------------------------------------------------
 * Erratum 1 requires that video which cannot be carried is switched off AND
 * EXPLAINED. The explanation needs a reason, and open() had none: it returned
 * NULL for "you called me wrong" and for "this link cannot carry video" alike,
 * and this header recommended the detour of opening with a permissive ceiling
 * and calling reconfigure() to find out which. A caller that only ever sees
 * NULL shows either no text or the wrong one — the exact failure Erratum 1
 * exists to remove, at the one entry point Erratum 1 did not cover.
 *
 * The reason is therefore conveyed IN-BAND, without changing the signature:
 *
 *     on failure, if out_negotiated is non-NULL, the backend zeroes the whole
 *     struct and writes a negative CLEONA_VIDEO_ERR_* into
 *     out_negotiated->max_frame_bytes.
 *
 * That field is unambiguous as an error channel because max_frame_bytes <= 0
 * can never be a valid configuration — this header makes open() fail closed on
 * exactly that value — so a success and a failure can never be confused. It is
 * the same instrument the voice ABI uses: cleona_voice_open writes a negative
 * CLEONA_VOICE_ERR_* into out_format->sample_rate, for the same reason
 * (native/cleona_voice/cleona_voice.h).
 *
 * out_negotiated STAYS OPTIONAL. A caller that passes NULL gets NULL back and
 * no reason, exactly as before; by passing NULL it has declared that it does
 * not need the distinction. Making the argument mandatory would turn calls that
 * are legal today into caller bugs for no gain. The change is purely additive:
 * no call that works today changes its behaviour.
 *
 * WHICH CODE FOR WHICH CASE — and decided in this order:
 *
 *   1. CLEONA_VIDEO_ERR_INVALID            cfg is NULL, a field is out of
 *      range, or codec is an unknown positive value. A caller bug: the same
 *      call will fail again, and no link improves it.
 *      VALIDITY IS DECIDED FIRST. max_frame_bytes <= 0 is ERR_INVALID and never
 *      ERR_RATE_UNACHIEVABLE, even though a ceiling of zero is also trivially
 *      unreachable. It has to be that way round, or open() and reconfigure()
 *      would give different answers about the same configuration —
 *      reconfigure() already fixes it so (the conformance test asserts it as
 *      V15), and one ABI may not hold two opinions.
 *   2. CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE  cfg is well-formed, and no supported
 *      step — not the lowest resolution, not the lowest bitrate — produces
 *      frames that fit under cfg->max_frame_bytes. THIS is the one that carries
 *      a text to the user (Erratum 1), and separating it from case 1 is the
 *      entire purpose of this erratum.
 *   3. CLEONA_VIDEO_ERR_UNSUPPORTED        this device has no capture or encode
 *      path at all. A property of the device, not of the call and not of the
 *      link: degrade to audio-only and do not retry on a better connection.
 *   4. CLEONA_VIDEO_ERR_BACKEND            the configuration was fine and the
 *      device is capable, but this attempt failed (allocation, camera busy,
 *      codec init refused). Retryable in principle.
 *
 * The conformance test asserts 1 and 2 (check V1b) because only those two are
 * reproducible without hardware. 3 and 4 are fixed here anyway so that four
 * platform packages do not invent four different answers for them.
 *
 * ---------------------------------------------------------------------------
 * OWN VIDEO ON/OFF (I12)
 * ---------------------------------------------------------------------------
 * cleona_video_set_capture_enabled() switches off *our own* capture and
 * encode. There is no call in this ABI that stops the peer from sending, and
 * none may be added. Switching the peer's video off is deliberately not
 * provided (§10.6, "Own video on/off").
 *
 * ---------------------------------------------------------------------------
 * VERIFICATION REPORT (I11)
 * ---------------------------------------------------------------------------
 * cleona_video_get_report() is a normative part of this ABI, not a debug
 * extra. Where a backend cannot determine a property, it reports the
 * not-determinable value (-1 for the hardware_* fields). It never guesses, and
 * in particular never reports hardware acceleration it has not verified.
 *
 * ---------------------------------------------------------------------------
 * THREADING
 * ---------------------------------------------------------------------------
 * A session may be used concurrently by at most one reader thread (calling
 * cleona_video_read_encoded) and at most one writer thread (calling
 * cleona_video_submit_encoded), plus any number of threads calling the control
 * and report functions. cleona_video_close() must not race with any other call
 * on the same session; the caller serialises it. Backends implement this with
 * their own lock — the caller is not expected to hold one.
 *
 * ---------------------------------------------------------------------------
 * DEVIATION FROM THE LITERAL SPEC TEXT — recorded deliberately
 * ---------------------------------------------------------------------------
 * Struct layout, constant values and function signatures are taken verbatim
 * from SPEC §4b. Two things were added, neither of which changes the layout,
 * the constant values or the calling convention:
 *
 *   a) the CLEONA_VIDEO_API export macro, without which the Linux build (built
 *      with C_VISIBILITY_PRESET hidden, as native/cleona_audio is) exports
 *      nothing and the Windows build produces no import library. The precedent
 *      is native/cleona_audio/cleona_audio.h:10-14.
 *   b) named return-code, backend-id and lifecycle-state constants. SPEC §4b
 *      leaves the return semantics of every function open; §4 (voice) does not.
 *      Defining them once here is the entire point of a serialisation
 *      point — otherwise four platform packages invent four incompatible
 *      numberings.
 *
 * Any further change to this file after the freeze needs an erratum in
 * docs/SPEC_VOICE_VIDEO_REWORK.md and an announcement to every running
 * package, per §12 of that document.
 */

#ifndef CLEONA_VIDEO_H
#define CLEONA_VIDEO_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
  #define CLEONA_VIDEO_API __declspec(dllexport)
#else
  #define CLEONA_VIDEO_API __attribute__((visibility("default")))
#endif

/* ==========================================================================
 * Opaque session
 * ========================================================================== */

/* One session owns one capture+encode path and one decode+render path for one
 * call. Groups use one session per remote stream; the capture side of the
 * additional sessions is left disabled. */
typedef struct cleona_video_session cleona_video_session_t;

/* ==========================================================================
 * Codecs
 * ==========================================================================
 * H.264 Constrained Baseline is the mandatory interop level. The reasoning is
 * recorded in §10.6 ("Codec decision", project owner, 2026-07-30) so that it
 * is not re-opened without new facts: it is the only codec with hardware
 * encode *and* decode on all five platforms. Apple's VideoToolbox has no
 * VP8/VP9 encoder at all and no AV1 encoder either, so a royalty-free
 * mandatory level would leave the Apple platforms on software encode — exactly
 * the part of the superseded design that performs worst. Do not re-litigate
 * this here.
 *
 * HEVC / AV1 / VP9 are negotiated when both sides have hardware for them; only
 * the fallback level is fixed. */
#define CLEONA_VIDEO_CODEC_H264 1   /* mandatory interop level — §10.6 */
#define CLEONA_VIDEO_CODEC_HEVC 2
#define CLEONA_VIDEO_CODEC_AV1  3
#define CLEONA_VIDEO_CODEC_VP9  4

/* ==========================================================================
 * Frame flags — bitmask, carried by read_encoded and submit_encoded
 * ========================================================================== */

/* Set on an intra-coded frame that a decoder can start from (an H.264 IDR
 * access unit, including its parameter sets). A decoder that has not yet seen
 * one cannot use anything else — see CLEONA_VIDEO_SUBMIT_AWAITING_KEYFRAME. */
#define CLEONA_VIDEO_FLAG_KEYFRAME 0x01

/* ==========================================================================
 * Return codes
 * ==========================================================================
 * SPEC §4b gives the signatures but not the return semantics. They are fixed
 * here so that all backends and the single Dart binding agree.
 *
 * Rule of thumb: 0 means "the call did what it says", negative means failure,
 * and the two functions with a genuinely tri-state outcome (read_encoded,
 * submit_encoded) get their own named positive values below. */
#define CLEONA_VIDEO_OK                    0
/* An argument is NULL, out of range, or internally inconsistent. Caller bug. */
#define CLEONA_VIDEO_ERR_INVALID          -1
/* The session is in the wrong lifecycle state for this call (e.g. start()
 * twice, read before start, any call after close). */
#define CLEONA_VIDEO_ERR_STATE            -2
/* The platform genuinely cannot do this — no second camera, no texture path,
 * no forced-keyframe control. Not an error the caller can fix by retrying;
 * it is a property of the device, and the caller degrades gracefully. */
#define CLEONA_VIDEO_ERR_UNSUPPORTED      -3
/* The underlying capture/codec stack failed (device lost, MFT reset, VAAPI
 * surface allocation failed, ...). Retryable in principle. */
#define CLEONA_VIDEO_ERR_BACKEND          -4
/* read_encoded only: buf_cap is smaller than the pending frame. The frame is
 * NOT consumed and *out_size carries the size required to read it. Callers
 * that size their buffer at negotiated.max_frame_bytes can never see this,
 * because no frame handed out by this ABI ever exceeds that value. */
#define CLEONA_VIDEO_ERR_BUFFER_TOO_SMALL -5
/* submit_encoded only: the decoder rejected the bitstream (malformed, wrong
 * codec, truncated). Counted in report.decode_failures. */
#define CLEONA_VIDEO_ERR_DECODE           -6
/* cleona_video_reconfigure (Erratum 1) and cleona_video_open (Erratum 6b): NO
 * supported step — not the lowest resolution, not the lowest bitrate —
 * produces frames that fit under cfg->max_frame_bytes. From reconfigure it is a
 * return value and the session is left untouched, keeping its previous
 * configuration; from open there is no session to keep and the code arrives
 * in-band in out_negotiated->max_frame_bytes (see Erratum 6b above).
 *
 * This is the one error code the caller must branch on rather than log. It is
 * the difference between "not right now" (scale down and carry on) and "not at
 * all on this link", and that distinction is what the user-facing text hangs
 * on: the caller stops video and states the reason, locally and at the peer.
 * Treating it as a generic failure re-creates the silent black picture. */
#define CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE -7

/* cleona_video_read_encoded outcomes. */
#define CLEONA_VIDEO_READ_FRAME    1   /* a frame was written to buf         */
#define CLEONA_VIDEO_READ_TIMEOUT  0   /* nothing available within timeout_ms */
/* The session was stopped or closed while waiting, or was never started.
 * Deliberately the same value as ERR_STATE — it is the same condition. */
#define CLEONA_VIDEO_READ_CLOSED   CLEONA_VIDEO_ERR_STATE

/* cleona_video_submit_encoded outcomes. */
#define CLEONA_VIDEO_SUBMIT_ACCEPTED           0
/* The frame was deliberately not decoded because no keyframe has been seen on
 * this session yet and this frame is not one. This is NOT a failure and is NOT
 * counted in report.decode_failures. The caller should ask the peer for a
 * keyframe (the peer calls cleona_video_request_keyframe on its own session).
 * The superseded stack had exactly this branch in Dart
 * (video_engine.dart:403-406); it belongs below the ABI, next to the decoder
 * that knows its own state. */
#define CLEONA_VIDEO_SUBMIT_AWAITING_KEYFRAME  1

/* ==========================================================================
 * Backend identifiers — report.capture_backend / report.encode_backend
 * ==========================================================================
 * Fixed centrally so the four platform packages (V1.13-V1.16) cannot invent
 * colliding numbers. Values follow the platform matrix in §10.6. A backend
 * that adds a variant appends a value here via an erratum; it never reuses
 * one. */
#define CLEONA_VIDEO_BACKEND_NONE                 0
#define CLEONA_VIDEO_BACKEND_MOCK                 1
#define CLEONA_VIDEO_BACKEND_ANDROID_CAMERAX      2
#define CLEONA_VIDEO_BACKEND_ANDROID_MEDIACODEC   3
#define CLEONA_VIDEO_BACKEND_APPLE_AVCAPTURE      4
#define CLEONA_VIDEO_BACKEND_APPLE_VIDEOTOOLBOX   5
#define CLEONA_VIDEO_BACKEND_WIN_MF_SOURCEREADER  6
#define CLEONA_VIDEO_BACKEND_WIN_MF_TRANSFORM     7
#define CLEONA_VIDEO_BACKEND_LINUX_V4L2           8
#define CLEONA_VIDEO_BACKEND_LINUX_PIPEWIRE       9
#define CLEONA_VIDEO_BACKEND_LINUX_VAAPI         10
#define CLEONA_VIDEO_BACKEND_LINUX_V4L2_M2M      11

/* ==========================================================================
 * Tri-state for the hardware_* report fields (I11)
 * ========================================================================== */
#define CLEONA_VIDEO_HW_NO               0
#define CLEONA_VIDEO_HW_YES              1
/* "I could not determine this." A legitimate answer. Reporting HW_YES without
 * having verified it is not. */
#define CLEONA_VIDEO_HW_NOT_DETERMINABLE (-1)

/* ==========================================================================
 * Configuration
 * ========================================================================== */

typedef struct {
    /* CLEONA_VIDEO_CODEC_*. On input: the caller's preference; <= 0 means "no
     * preference", which is treated as H264. An unknown positive value makes
     * cleona_video_open fail closed (returns NULL) — that is a caller bug, not
     * something to silently reinterpret. On output: the codec the backend will
     * actually produce, which is authoritative. Every backend MUST support
     * H264 in both directions; if the requested codec is unavailable the
     * backend negotiates down to H264 rather than failing. A backend that
     * cannot do H264 at all is not acceptance-ready — the video equivalent of
     * `duplex == 1` in the voice ABI. */
    int32_t codec;

    /* Requested capture geometry and frame rate. The backend may negotiate
     * these DOWN (to what the camera and encoder actually support) and never
     * up: the caller's values are upper bounds. Must all be > 0 on input. */
    int32_t width, height, fps;

    /* Target bitrate handed to the hardware rate controller. Cleona's
     * bandwidth_estimator sets it; Cleona does not do rate control itself
     * (§10.6, "Defaults"). May be negotiated down, never up. Must be > 0. */
    int32_t target_bitrate_kbps;

    /* I9: hard ceiling per encoded frame so it fits the plain-UDP envelope.
       The encoder MUST respect this — downscale rather than exceed.

       NOT A FIXED PROPERTY OF THE SESSION (Erratum 1). The value is derived
       from the running bandwidth estimate and is pushed down at any time with
       cleona_video_reconfigure(). A backend that treats it as a constant taken
       at open() cannot follow a link that degrades, which is the normal case
       on mobile.

       The obligation is to KEEP SENDING A SMALLER PICTURE, or to say clearly
       that it cannot:

       1. Stay under the ceiling by construction. Lower the resolution step,
          let the rate controller hold the budget, spread a keyframe across
          several send intervals, use forward error correction instead of
          retransmission (§10.3.1). The superseded default was 640x480 at
          30 fps and 800 kbps — ~3.3 kB per frame, three fragments per frame,
          90 fragments per second, plus keyframe bursts of 20-60 kB, i.e. 17-50
          fragments (§10.6, "Defaults"). That preset does not fit a small
          ceiling and is exactly what has to be scaled away.

       2. If not even the lowest supported step fits, reconfigure returns
          CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE and the caller switches own video
          off WITH A REASON SHOWN TO THE USER. Going quiet is not an option.

       DISCARDING IS NOT ONE OF THE TWO ANSWERS. It exists only as a
       last-resort backstop against a backend bug: a frame that still comes out
       larger than this value is discarded and counted in
       report.frames_dropped_oversize rather than handed over, because an
       undeliverable frame costs the same bandwidth as a deliverable one and
       arrives never. In a correct system that counter never moves. See its
       documentation in cleona_video_report_t.

       This ceiling applies to OUR OWN encoder only. cleona_video_submit_encoded
       does not reject an oversize frame from the peer — what the peer sends is
       the peer's transport problem, and rejecting it here would be a covert
       form of telling the peer what it may send (I12).

       Must be > 0 on input; cleona_video_open and cleona_video_reconfigure
       fail closed otherwise, because an encoder without a ceiling violates I9
       by construction. May be negotiated down, never up. The numeric value
       comes from the transport layer (V1.11) and is deliberately not
       hard-coded in this ABI.

       DOUBLES AS THE ERROR CHANNEL OF cleona_video_open (Erratum 6b). Because
       a value <= 0 is never a valid configuration, a failing open() writes a
       negative CLEONA_VIDEO_ERR_* here and zeroes every other field. On a
       successful open() or reconfigure() this field is always > 0, so the two
       cases cannot be mistaken for one another. */
    int32_t max_frame_bytes;

    /* Maximum number of frames between keyframes. 0 means "backend default".
     * Negative is invalid. Note this is an upper bound on the interval, not a
     * schedule: cleona_video_request_keyframe may insert one at any time. */
    int32_t keyframe_interval_frames;
} cleona_video_config_t;

/* ==========================================================================
 * Verification report (I11)
 * ==========================================================================
 * All counters are monotonic for the lifetime of the session. They are NOT
 * reset by stop()/start(); a session's counters describe the session.
 *
 * Relation between the encode-side counters, fixed here because it is
 * otherwise ambiguous:
 *
 *   frames_encoded          — every frame the encoder produced
 *   frames_dropped_oversize — of those, the ones killed by the I9 backstop;
 *                             a defect counter, expected to stay 0
 *   frames handed to the caller = frames_encoded - frames_dropped_oversize
 *
 * frames_captured counts what the camera delivered, which is >= frames_encoded
 * (an encoder may skip input frames under load or while capture is disabled).
 */
typedef struct {
    /* CLEONA_VIDEO_CODEC_* actually in use. Matches out_negotiated->codec. */
    int32_t codec_in_use;
    /* CLEONA_VIDEO_HW_YES / _NO / _NOT_DETERMINABLE (1/0/unknown(-1)).
     * Never report YES without having verified it — I11. */
    int32_t hardware_encode, hardware_decode;
    /* What open() actually settled on. Repeated here so a single report line
     * in the log is self-contained (V1.7 logs one line per call). */
    int32_t negotiated_width, negotiated_height, negotiated_fps;
    /* CLEONA_VIDEO_BACKEND_*. */
    int32_t capture_backend, encode_backend;
    /* frames_dropped_oversize is a DEFECT COUNTER (Erratum 1), not evidence
     * that a safety net worked. The correct responses to a shrinking ceiling
     * are "scale down and keep sending" and "stop with a reason shown to the
     * user" — see cleona_video_reconfigure. A non-zero value means neither
     * happened in time, and the peer saw a gap nobody explained. Assert on it
     * in E2E; do not normalise it. */
    int64_t frames_captured, frames_encoded, frames_dropped_oversize;
    /* Decode side. decode_failures counts bitstreams the decoder rejected
     * (ERR_DECODE). It does NOT count frames deliberately skipped while
     * awaiting a keyframe — those are not failures. */
    int64_t frames_decoded, decode_failures;
} cleona_video_report_t;

/* ==========================================================================
 * Lifecycle
 * ==========================================================================
 *
 *   open ──► [OPEN] ──start──► [RUNNING] ──stop──► [OPEN] ──close──► gone
 *                                  └──────close───────────────────────┘
 *
 * stop() is idempotent and may be followed by start() again. close() implies
 * stop(). Calls on a closed session are undefined behaviour — the pointer is
 * dead; the caller nulls it.
 */

/* Negotiate a configuration and allocate the session. Does NOT touch the
 * camera or the encoder yet — that is start().
 *
 * cfg           must be non-NULL and internally valid (see the field docs).
 * out_negotiated may be NULL if the caller genuinely does not care, but every
 *               real caller does, for two reasons now: the backend is allowed
 *               to negotiate down and the caller must size its read buffer from
 *               out_negotiated->max_frame_bytes, AND this is the only place a
 *               failed open() states its reason (Erratum 6b).
 *
 * Returns the session, or NULL when the configuration is invalid or the backend
 * cannot open at all.
 *
 * ON FAILURE (Erratum 6b) the reason is written in-band: if out_negotiated is
 * non-NULL the backend zeroes the struct and puts a negative
 * CLEONA_VIDEO_ERR_* into out_negotiated->max_frame_bytes. The full case-to-code
 * mapping and the reason the field is unambiguous are in the Erratum 6b section
 * at the top of this header; in short:
 *
 *   ERR_INVALID            cfg NULL or a field out of range. Caller bug.
 *                          Decided BEFORE anything else, so max_frame_bytes <= 0
 *                          is this and never ERR_RATE_UNACHIEVABLE.
 *   ERR_RATE_UNACHIEVABLE  the config is well-formed but no supported step fits
 *                          cfg->max_frame_bytes. The link, not the caller —
 *                          this is the branch that shows the user a reason.
 *   ERR_UNSUPPORTED        no capture/encode path on this device at all.
 *   ERR_BACKEND            capable device, this attempt failed. Retryable.
 *
 * On SUCCESS out_negotiated->max_frame_bytes is always > 0, so a caller tests
 * the session pointer first and reads the field only when it is NULL.
 *
 * A caller that passes out_negotiated == NULL forgoes the reason: it still gets
 * NULL, and no error detail exists anywhere else — this ABI has no errno, no
 * thread-local state and no second entry point, by design. */
CLEONA_VIDEO_API cleona_video_session_t* cleona_video_open(const cleona_video_config_t* cfg,
                                         cleona_video_config_t* out_negotiated);

/* Re-negotiate a running (or merely opened) session — Erratum 1.
 *
 * WHY THIS EXISTS. max_frame_bytes follows the available bandwidth, so it
 * cannot be a property fixed at open(). When the bandwidth estimate moves, the
 * caller recomputes the ceiling and pushes a new configuration down here. This
 * is the mechanism that lets a call keep a picture on a degrading link instead
 * of going black without explanation.
 *
 * COVERS BOTH GRANULARITIES with one entry point, deliberately: a pure rate
 * change (target_bitrate_kbps and/or fps, geometry unchanged) and a resolution
 * step change. A backend decides for itself which of the two it can actually
 * do; what it must not do is accept the call and then keep producing frames
 * that no longer fit.
 *
 * cfg            the new request. Same validity rules as cleona_video_open:
 *                every field > 0 except keyframe_interval_frames (0 = backend
 *                default), max_frame_bytes strictly > 0.
 * out_negotiated receives the values the backend actually accepted. May be
 *                NULL, but every real caller wants it — the answer is
 *                authoritative and is usually smaller than the request.
 *
 * Returns:
 *   CLEONA_VIDEO_OK                     accepted; out_negotiated is written
 *   CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE  no supported step fits under
 *                                       cfg->max_frame_bytes. The session is
 *                                       UNCHANGED and still running with its
 *                                       previous configuration. The caller
 *                                       stops own video and shows the user the
 *                                       reason — it does not retry silently.
 *   CLEONA_VIDEO_ERR_INVALID            s or cfg NULL, or a field out of range
 *   CLEONA_VIDEO_ERR_STATE              the session is closed
 *   CLEONA_VIDEO_ERR_BACKEND            the codec/camera refused the change
 *
 * SEMANTICS THE BACKENDS MUST SHARE:
 *
 *  - Takes effect from the NEXT frame produced. A frame already produced under
 *    the previous configuration is still delivered, unless it exceeds the NEW
 *    max_frame_bytes — in that case it is discarded and counted, because
 *    handing it over would violate I9 for a ceiling that is already in force.
 *  - A change of width or height FORCES A KEYFRAME. The peer's decoder cannot
 *    continue from a reference picture of a different size. A pure rate change
 *    does not force one.
 *  - The negotiation rules of open() continue to apply unchanged: the backend
 *    may settle every field DOWNWARDS and never upwards, and it may lower
 *    max_frame_bytes but never raise it above what the caller asked for.
 *  - Counters are NOT reset. A session's report describes the session, across
 *    every reconfiguration it lived through.
 *  - Presentation timestamps stay strictly increasing across the change. A
 *    backend that derives pts as frame_index * 1e6 / fps breaks this the
 *    moment fps goes back up; accumulate the per-frame step instead.
 *  - Failure is side-effect free. After ERR_RATE_UNACHIEVABLE or ERR_INVALID
 *    the session is exactly as it was.
 *  - I12 is untouched: this is a statement about what WE send. Nothing here
 *    reaches the peer's encoder, and no counterpart may be added.
 *
 * Valid before start() and while running. */
CLEONA_VIDEO_API int32_t cleona_video_reconfigure(cleona_video_session_t* s,
                                 const cleona_video_config_t* cfg,
                                 cleona_video_config_t* out_negotiated);

/* Start capture, encoder and decoder.
 * Returns CLEONA_VIDEO_OK, ERR_INVALID (s == NULL), ERR_STATE (already
 * started), or ERR_BACKEND (camera/codec refused). */
CLEONA_VIDEO_API int32_t cleona_video_start(cleona_video_session_t* s);

/* Stop capture, encoder and decoder and drop everything queued. Idempotent;
 * a NULL session is a no-op. A reader blocked in cleona_video_read_encoded is
 * released and gets CLEONA_VIDEO_READ_CLOSED. Decoder keyframe state is reset,
 * so after the next start() the decoder again waits for a keyframe. Counters
 * are not reset. */
CLEONA_VIDEO_API void    cleona_video_stop(cleona_video_session_t* s);

/* Release the session. Implies stop(). A NULL session is a no-op. The pointer
 * is invalid afterwards. Must not race with any other call on the session. */
CLEONA_VIDEO_API void    cleona_video_close(cleona_video_session_t* s);

/* ==========================================================================
 * Data path — Dart never sees pixels (I10)
 * ========================================================================== */

/* Read one encoded frame.
 *
 * buf        receives the frame; buf_cap is its capacity. Size it at
 *            negotiated.max_frame_bytes and ERR_BUFFER_TOO_SMALL becomes
 *            unreachable, because no frame handed out here ever exceeds it.
 * out_size   frame size in bytes on success; on ERR_BUFFER_TOO_SMALL the size
 *            that WOULD be required. May not be NULL.
 * out_flags  bitmask of CLEONA_VIDEO_FLAG_*. May not be NULL.
 * out_pts_us presentation timestamp in microseconds on a monotonic capture
 *            clock that starts near zero at the first start(). Strictly
 *            increasing across the frames of one session. May not be NULL.
 * timeout_ms how long to wait for a frame. 0 polls, negative blocks until a
 *            frame arrives or the session stops.
 *
 * Returns CLEONA_VIDEO_READ_FRAME (1), CLEONA_VIDEO_READ_TIMEOUT (0),
 * CLEONA_VIDEO_READ_CLOSED (-2), ERR_INVALID (-1) or
 * ERR_BUFFER_TOO_SMALL (-5).
 *
 * Frames killed by the I9 backstop are invisible here: the implementation
 * skips them internally and keeps looking until the timeout expires. A caller
 * must not see a phantom timeout just because the encoder overshot — it would
 * have no way to tell that apart from a stalled camera.
 *
 * While capture is disabled (cleona_video_set_capture_enabled(s, 0)) this
 * returns READ_TIMEOUT, never READ_CLOSED. "Own video off" is not "session
 * gone" (I12). */
CLEONA_VIDEO_API int32_t cleona_video_read_encoded(cleona_video_session_t* s,
                                  uint8_t* buf, int32_t buf_cap,
                                  int32_t* out_size, int32_t* out_flags,
                                  int64_t* out_pts_us, int32_t timeout_ms);

/* Submit one encoded frame from the peer. The decoder renders into its own
 * texture; nothing is returned to the caller but a status.
 *
 * data/size  the bitstream as it came off the wire (already decrypted).
 * flags      bitmask of CLEONA_VIDEO_FLAG_*, as the peer reported it. If
 *            FLAG_KEYFRAME is set the backend may trust it; a backend that
 *            also inspects the bitstream and finds a contradiction returns
 *            ERR_DECODE rather than feeding its decoder a lie.
 *
 * Returns CLEONA_VIDEO_SUBMIT_ACCEPTED (0),
 * CLEONA_VIDEO_SUBMIT_AWAITING_KEYFRAME (1), ERR_INVALID (-1),
 * ERR_STATE (-2) or ERR_DECODE (-6).
 *
 * Never blocks. Does not enforce max_frame_bytes on the incoming direction —
 * see the note on that field. */
CLEONA_VIDEO_API int32_t cleona_video_submit_encoded(cleona_video_session_t* s,
                                    const uint8_t* data, int32_t size,
                                    int32_t flags);

/* Get the renderer texture id the decoder draws into, for a Flutter Texture
 * widget with an external texture id.
 *
 * Returns CLEONA_VIDEO_OK with *out_id set, ERR_INVALID, ERR_STATE (not
 * started), or ERR_UNSUPPORTED when this backend has no texture path at all
 * (headless test builds, the mock in its default-off mode). *out_id is only
 * meaningful when the return value is OK. The id is stable between start()
 * and stop(); a caller must re-query it after every start(). */
CLEONA_VIDEO_API int32_t cleona_video_get_texture_id(cleona_video_session_t* s, int64_t* out_id);

/* Ask the encoder for a keyframe as soon as possible.
 *
 * Returns CLEONA_VIDEO_OK when the request was accepted, in which case the
 * next frame produced carries FLAG_KEYFRAME. Idempotent — repeated calls
 * before the next frame collapse into one. Returns ERR_UNSUPPORTED on an
 * encoder with no forced-keyframe control (none of the four target platforms;
 * kept for honesty), ERR_INVALID or ERR_STATE.
 *
 * Note the asymmetry with the I9 backstop: a forced keyframe is exactly the
 * frame most likely to overshoot max_frame_bytes. A backend that cannot
 * produce a keyframe under the ceiling must lower the preset, not exceed it. */
CLEONA_VIDEO_API int32_t cleona_video_request_keyframe(cleona_video_session_t* s);

/* Switch our own capture on or off. THIS IS THE ONLY VIDEO MUTE IN THIS ABI
 * (I12) — there is no counterpart that stops the peer from sending, and none
 * may be added.
 *
 * off: the capture session stops delivering, frames_captured stops advancing,
 *      and read_encoded returns READ_TIMEOUT. The session, the decoder and the
 *      texture stay alive, so the peer's picture keeps running.
 * on:  capture resumes and the next frame produced is a keyframe, implicitly
 *      and unconditionally — the peer's decoder has been starved and any
 *      P-frame we sent now would be undecodable.
 *
 * The state change is what CALL_MEDIA_STATE carries on the wire (V1.12): one
 * flag, "I am sending video". The receiver shows "video off" instead of a
 * frozen frame. The superseded toggleVideoMute() paused locally and signalled
 * nothing (call_service.dart:481), so the peer's last frame froze indefinitely.
 *
 * A no-op on a NULL session. Idempotent. */
CLEONA_VIDEO_API void    cleona_video_set_capture_enabled(cleona_video_session_t* s, int32_t on);

/* Switch to the next camera (front/back on mobile, next enumerated device on
 * desktop), cycling.
 *
 * The negotiated format does not change, so the caller never has to
 * renegotiate; a backend whose second camera cannot deliver the negotiated
 * format either scales to it or returns ERR_UNSUPPORTED and stays on the
 * current camera. The next frame produced after a successful switch is a
 * keyframe.
 *
 * Returns CLEONA_VIDEO_OK, ERR_UNSUPPORTED (only one camera, or no camera
 * concept), ERR_INVALID, ERR_STATE, or ERR_BACKEND. */
CLEONA_VIDEO_API int32_t cleona_video_switch_camera(cleona_video_session_t* s);

/* Fill the verification report (I11). Logged once per call by the Dart layer
 * and assertable in E2E.
 *
 * A NULL out is a no-op. A NULL session zero-fills out and sets the
 * hardware_* fields to CLEONA_VIDEO_HW_NOT_DETERMINABLE — "no session" is not
 * evidence that there is no hardware. Valid in every lifecycle state after
 * open(). */
CLEONA_VIDEO_API void    cleona_video_get_report(cleona_video_session_t* s,
                                cleona_video_report_t* out);

#ifdef __cplusplus
}
#endif

#endif /* CLEONA_VIDEO_H */
