/* voice_saboteur.c — a backend that is conformant except for ONE injected
 * defect, selected at run time by the environment variable CLEONA_VOICE_SABOTAGE.
 *
 * Work package: docs/SPEC_VOICE_VIDEO_REWORK.md V0.4.
 *
 * ---------------------------------------------------------------------------
 * WHY THIS EXISTS
 * ---------------------------------------------------------------------------
 * A conformance test that has never been observed to fail is not evidence of
 * conformance — it is evidence of nothing. This project has produced that
 * failure three times: the S281 lab measurement bypassed the broken ring buffer
 * with a memcpy and "proved" a fix that was not there, and preflight check 5
 * never examined cleona_net because the path it looked at silently did not
 * exist, so it passed for years without checking anything.
 *
 * Every check this harness makes is therefore demonstrated to FAIL against a
 * backend that breaks exactly the property under examination, and to fail for
 * that reason and no other: the negative controls run with
 * --expect-fail <id>, which exits 0 only if the set of failed check ids is
 * EXACTLY the expected one (conformance_harness.c). "Something went red" is not
 * accepted as proof.
 *
 * ---------------------------------------------------------------------------
 * HOW IT IS BUILT
 * ---------------------------------------------------------------------------
 * The mock is compiled into this file with its twelve ABI entry points renamed
 * to sab_*, and the real names are then defined here as forwarders that inject
 * one defect. That keeps the saboteur exactly as conformant as the mock in
 * every respect except the one being demonstrated — a hand-written fake backend
 * would drift from the mock and start failing checks for uninteresting reasons.
 *
 * This library is test-only. It is built by native/cleona_voice/test/CMakeLists.txt
 * and by nothing else, and it is never linked into anything that ships.
 */

/* ---- the mock, with the ABI surface renamed ------------------------------ */
#define cleona_voice_open             sab_open
#define cleona_voice_start            sab_start
#define cleona_voice_stop             sab_stop
#define cleona_voice_close            sab_close
#define cleona_voice_capture_read     sab_capture_read
#define cleona_voice_playback_write   sab_playback_write
#define cleona_voice_set_mic_muted    sab_set_mic_muted
#define cleona_voice_set_output_muted sab_set_output_muted
#define cleona_voice_set_route        sab_set_route
#define cleona_voice_get_routes       sab_get_routes
#define cleona_voice_poll_event       sab_poll_event
#define cleona_voice_get_report       sab_get_report

#include "../../mock/cleona_voice_mock.c"

#undef cleona_voice_open
#undef cleona_voice_start
#undef cleona_voice_stop
#undef cleona_voice_close
#undef cleona_voice_capture_read
#undef cleona_voice_playback_write
#undef cleona_voice_set_mic_muted
#undef cleona_voice_set_output_muted
#undef cleona_voice_set_route
#undef cleona_voice_get_routes
#undef cleona_voice_poll_event
#undef cleona_voice_get_report

#include <stdlib.h>
#include <string.h>

/* ---- defect selection ---------------------------------------------------- */

enum {
    SAB_NONE = 0,
    SAB_SHORT_FRAME,        /* I4  — capture_read writes 4 samples too few   */
    SAB_DUPLEX,             /* I2  — report claims two separate devices      */
    SAB_ACCEPT_WRONG_SIZE,  /* §6.4 — playback_write pads instead of failing */
    SAB_FX_NO_ORIGIN,       /* I11 — an ENABLED effect with no chain origin  */
    SAB_ROUTE_NOT_IN_MASK,  /* §6.8 — active route missing from the mask     */
    SAB_LEAK,               /* §6.9 — leaks a block per open()               */
    /* ---- erratum E6a: the four mute-state checks ------------------------- */
    SAB_MIC_MUTE_NOT_REPORTED,    /* report.mic_muted stuck at 0             */
    SAB_OUTPUT_MUTE_NOT_REPORTED, /* report.output_muted stuck at 0          */
    SAB_MUTE_LOST_ON_ROUTE,       /* §10.4 — set_route resets both mutes     */
    SAB_MUTE_DIRTY_AFTER_OPEN     /* muted before anything asked for it      */
};

static int sab_mode(void) {
    static int cached = -1;
    if (cached >= 0) return cached;
    const char* v = getenv("CLEONA_VOICE_SABOTAGE");
    if (!v || !*v)                              cached = SAB_NONE;
    else if (strcmp(v, "short_frame") == 0)     cached = SAB_SHORT_FRAME;
    else if (strcmp(v, "duplex") == 0)          cached = SAB_DUPLEX;
    else if (strcmp(v, "accept_wrong_size") == 0) cached = SAB_ACCEPT_WRONG_SIZE;
    else if (strcmp(v, "fx_no_origin") == 0)    cached = SAB_FX_NO_ORIGIN;
    else if (strcmp(v, "route_not_in_mask") == 0) cached = SAB_ROUTE_NOT_IN_MASK;
    else if (strcmp(v, "leak") == 0)            cached = SAB_LEAK;
    else if (strcmp(v, "mic_mute_not_reported") == 0)    cached = SAB_MIC_MUTE_NOT_REPORTED;
    else if (strcmp(v, "output_mute_not_reported") == 0) cached = SAB_OUTPUT_MUTE_NOT_REPORTED;
    else if (strcmp(v, "mute_lost_on_route") == 0)       cached = SAB_MUTE_LOST_ON_ROUTE;
    else if (strcmp(v, "mute_dirty_after_open") == 0)    cached = SAB_MUTE_DIRTY_AFTER_OPEN;
    else                                        cached = SAB_NONE;
    return cached;
}

/* The negotiated frame size, needed by two of the defects. A test double may
 * keep this in a global: there is exactly one harness process and it drives one
 * session at a time.
 *
 * The scratch buffer is static rather than allocated, deliberately: this file
 * runs under LeakSanitizer as part of the leak negative control, and a helper
 * buffer with no owner would show up as a leak of its own and mask the one
 * being demonstrated. It cost exactly that mistake once already. The size is
 * not a guess — cleona_voice.h bounds the rate at CLEONA_VOICE_RATE_MAX, so a
 * 20 ms frame can never exceed RATE_MAX / FRAME_HZ samples. */
#define SAB_MAX_FRAME_SAMPLES (CLEONA_VOICE_RATE_MAX / CLEONA_VOICE_FRAME_HZ)

static int32_t g_frame_samples = 0;
static int16_t g_scratch[SAB_MAX_FRAME_SAMPLES];

/* ---- the ABI, with one defect ------------------------------------------- */

CLEONA_VOICE_API cleona_voice_session_t* cleona_voice_open(
    int32_t rate_hint, cleona_voice_format_t* out_format) {
    cleona_voice_session_t* s = sab_open(rate_hint, out_format);
    if (s && out_format) {
        g_frame_samples = out_format->frame_samples;
    }
    if (s && sab_mode() == SAB_LEAK) {
        /* Deliberately unreachable afterwards: this is the block LeakSanitizer
         * has to report. Written to so that no optimiser may elide it. */
        volatile unsigned char* leaked = (unsigned char*)malloc(4096);
        if (leaked) leaked[0] = 0x5A;
    }
    return s;
}

CLEONA_VOICE_API int32_t cleona_voice_start(cleona_voice_session_t* s) {
    return sab_start(s);
}

CLEONA_VOICE_API void cleona_voice_stop(cleona_voice_session_t* s) {
    sab_stop(s);
}

CLEONA_VOICE_API void cleona_voice_close(cleona_voice_session_t* s) {
    sab_close(s);
}

CLEONA_VOICE_API int32_t cleona_voice_capture_read(cleona_voice_session_t* s,
                                                   int16_t* out,
                                                   int32_t timeout_ms) {
    if (sab_mode() != SAB_SHORT_FRAME || !out || g_frame_samples < 8 ||
        g_frame_samples > SAB_MAX_FRAME_SAMPLES) {
        return sab_capture_read(s, out, timeout_ms);
    }
    /* The defect the superseded stack had (cleona_audio.c:151): the platform
     * layer hands up whatever the device gave it. Here: four samples short,
     * which is far too small to hear and exactly what a poison-and-guard probe
     * is for. */
    int32_t r = sab_capture_read(s, g_scratch, timeout_ms);
    if (r == CLEONA_VOICE_CAPTURE_FRAME) {
        memcpy(out, g_scratch, (size_t)(g_frame_samples - 4) * sizeof(int16_t));
    }
    return r;
}

CLEONA_VOICE_API int32_t cleona_voice_playback_write(cleona_voice_session_t* s,
                                                     const int16_t* pcm,
                                                     int32_t frame_samples) {
    if (sab_mode() == SAB_ACCEPT_WRONG_SIZE && s && pcm) {
        /* Silently adapts instead of rejecting — the behaviour SPEC §6 check 4
         * exists to forbid, because it turns a rate mismatch into a mystery
         * three layers up. */
        int32_t r = sab_playback_write(s, pcm, g_frame_samples);
        (void)frame_samples;
        return r;
    }
    return sab_playback_write(s, pcm, frame_samples);
}

CLEONA_VOICE_API void cleona_voice_set_mic_muted(cleona_voice_session_t* s,
                                                 int32_t muted) {
    sab_set_mic_muted(s, muted);
}

CLEONA_VOICE_API void cleona_voice_set_output_muted(cleona_voice_session_t* s,
                                                    int32_t muted) {
    sab_set_output_muted(s, muted);
}

CLEONA_VOICE_API int32_t cleona_voice_set_route(cleona_voice_session_t* s,
                                                int32_t route) {
    int32_t r = sab_set_route(s, route);
    if (r == CLEONA_VOICE_OK && sab_mode() == SAB_MUTE_LOST_ON_ROUTE) {
        /* The defect erratum E6a exists for: the route switch silently clears
         * both mutes. On a real backend this is what happens when the switch is
         * implemented by tearing the OS session down and building a new one
         * without carrying the two flags across — the microphone goes live again
         * when a headset is unplugged mid-call, and nobody finds out until
         * afterwards.
         *
         * Applied only to a SUCCESSFUL switch, so that the harness's
         * invalid-argument probes (S4) do not clear the state as a side effect
         * and make an unrelated check look like the one that caught this. */
        sab_set_mic_muted(s, 0);
        sab_set_output_muted(s, 0);
    }
    return r;
}

CLEONA_VOICE_API int32_t cleona_voice_get_routes(cleona_voice_session_t* s,
                                                 int32_t* out_mask,
                                                 int32_t* out_active) {
    static int32_t calls = 0;
    int32_t r = sab_get_routes(s, out_mask, out_active);
    if (r == CLEONA_VOICE_OK && sab_mode() == SAB_ROUTE_NOT_IN_MASK &&
        out_mask && out_active && calls++ == 0) {
        *out_mask &= ~CLEONA_VOICE_ROUTE_BIT(*out_active);
        /* The active route is not in the mask it reports — the caller's device
         * chooser would show a set that does not contain what is playing.
         *
         * Applied to the FIRST call only, on purpose. Check 8 reads the routes
         * once; the later route checks (S5, S9) read them again to decide which
         * route to switch to, and a permanently inconsistent answer would make
         * THOSE fail as well. The negative control has to prove that check 8
         * catches this defect, not that an inconsistent backend eventually
         * upsets something somewhere. */
    }
    return r;
}

CLEONA_VOICE_API int32_t cleona_voice_poll_event(cleona_voice_session_t* s,
                                                 int32_t* out_event,
                                                 int32_t* out_arg) {
    return sab_poll_event(s, out_event, out_arg);
}

CLEONA_VOICE_API void cleona_voice_get_report(cleona_voice_session_t* s,
                                              cleona_voice_report_t* out) {
    static int32_t report_calls = 0;
    sab_get_report(s, out);
    if (!out || !s) return;
    report_calls++;
    switch (sab_mode()) {
        case SAB_DUPLEX:
            /* Two independent devices on two clocks — the arrangement I2 exists
             * to forbid, and the reason the superseded AEC never converged. */
            out->duplex = 0;
            break;
        case SAB_FX_NO_ORIGIN:
            /* "AEC is on" with nothing to point at. Exactly the unfalsifiable
             * claim the verification report was introduced to eliminate. */
            out->aec_state    = CLEONA_VOICE_FX_ENABLED;
            out->ns_state     = CLEONA_VOICE_FX_ENABLED;
            out->agc_state    = CLEONA_VOICE_FX_ENABLED;
            out->chain_origin = CLEONA_VOICE_CHAIN_NONE;
            break;
        case SAB_MIC_MUTE_NOT_REPORTED:
            /* set_mic_muted still works — the capture stream really does go
             * silent — but the report never says so. This is the state the ABI
             * was in before erratum E6a: the mute was real and unobservable, and
             * "did it take effect?" could only be answered from the signal
             * level, which says nothing in a quiet room. */
            out->mic_muted = 0;
            break;
        case SAB_OUTPUT_MUTE_NOT_REPORTED:
            /* The same for the output direction, where there is no signal-level
             * observable at all to fall back on. */
            out->output_muted = 0;
            break;
        case SAB_MUTE_DIRTY_AFTER_OPEN:
            /* Muted before anyone asked — an uninitialised field, or a platform
             * mute property inherited from a previous session. Injected into the
             * FIRST report only, which is the pre-start read S12 makes.
             *
             * Same reasoning as SAB_ROUTE_NOT_IN_MASK above: a permanently
             * stuck-at-1 mic_muted would also fail C5c's "set_mic_muted(0) reads
             * back as 0" half, and the negative control has to prove that S12
             * catches a dirty initial state — not that a thoroughly broken
             * backend eventually upsets something. */
            if (report_calls == 1) out->mic_muted = 1;
            break;
        default:
            break;
    }
}
