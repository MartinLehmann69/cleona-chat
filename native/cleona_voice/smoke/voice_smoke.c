/* voice_smoke.c — V0.2 acceptance programme for the cleona_voice ABI.
 *
 * Work package: docs/SPEC_VOICE_VIDEO_REWORK.md V0.2.
 *
 * WHAT THIS IS, AND WHAT IT IS NOT
 * --------------------------------
 * SPEC §6 defines a conformance test that every backend must pass, living in
 * native/cleona_voice/test/conformance.c. That file belongs to work package
 * V0.4 and does not exist yet. V0.2 must nevertheless be provable on its own,
 * so this programme walks the same NINE mandatory checks against the mock, in
 * a directory (smoke/) that V0.4 does not own — the two can never collide.
 *
 * When V0.4 lands, this programme is superseded by the shared harness. Until
 * then it is the only executable evidence that the ABI and the mock agree.
 *
 * The checks are written to FAIL when the invariant is broken, not merely to
 * exercise the code path. Where a check could pass for the wrong reason, that
 * is called out in a comment next to it — a green test whose greenness cannot
 * fail is the exact failure mode the verification report exists to prevent
 * (architecture §10.4).
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

#include "../cleona_voice.h"
#include "../mock/cleona_voice_mock.h"

static int g_failures = 0;
static int g_checks   = 0;

static void report(int ok, const char* id, const char* what, const char* detail) {
    g_checks++;
    if (!ok) g_failures++;
    printf("%-4s %-6s %-52s %s\n", ok ? "PASS" : "FAIL", id, what,
           detail ? detail : "");
    fflush(stdout);
}

/* Poison value for the frame-size probe. Chosen so no synthetic tone sample
 * can ever equal it: the mock's default amplitude is 8000, and 0x5A5A = 23130.
 * Without that property the "was the frame really written" half of check 3
 * could pass by coincidence. */
#define POISON  ((int16_t)0x5A5A)
#define GUARD_SAMPLES 64

static const char* fx_name(int32_t v) {
    switch (v) {
        case CLEONA_VOICE_FX_UNAVAILABLE:   return "unavailable";
        case CLEONA_VOICE_FX_AVAILABLE_OFF: return "available_off";
        case CLEONA_VOICE_FX_ENABLED:       return "enabled";
        case CLEONA_VOICE_FX_UNKNOWN:       return "not_determinable";
        default:                            return "INVALID";
    }
}

static int fx_is_defined(int32_t v) {
    return v == CLEONA_VOICE_FX_UNAVAILABLE
        || v == CLEONA_VOICE_FX_AVAILABLE_OFF
        || v == CLEONA_VOICE_FX_ENABLED
        || v == CLEONA_VOICE_FX_UNKNOWN;
}

int main(void) {
    char detail[512];

    printf("cleona_voice V0.2 smoke — SPEC §6 checks 1-9 against the mock backend\n");
    printf("-----------------------------------------------------------------------\n");

    /* ------------------------------------------------------------------
     * Check 1 — open() yields a plausible, self-consistent format.
     *
     * The rate_hint is deliberately 16000 while the mock's default rate is
     * 48000: I3 says the hint may be ignored and that this is NOT an error.
     * A caller that assumed its hint was honoured would break here.
     * ------------------------------------------------------------------ */
    cleona_voice_mock_config_t cfg;
    cleona_voice_mock_config_default(&cfg);
    cfg.force_rate = 48000;              /* platform has its own rate */
    cleona_voice_mock_set_config(&cfg);

    cleona_voice_format_t fmt;
    memset(&fmt, 0, sizeof(fmt));
    cleona_voice_session_t* s = cleona_voice_open(16000, &fmt);

    if (!s) {
        snprintf(detail, sizeof(detail), "open() returned NULL, err=%d", fmt.sample_rate);
        report(0, "1", "open() yields a plausible format", detail);
        printf("\nFATAL: no session — remaining checks cannot run.\n");
        return 1;
    }

    int ok1 = fmt.sample_rate >= CLEONA_VOICE_RATE_MIN
           && fmt.sample_rate <= CLEONA_VOICE_RATE_MAX
           && fmt.channels == CLEONA_VOICE_CHANNELS
           && fmt.frame_samples == fmt.sample_rate / CLEONA_VOICE_FRAME_HZ
           && fmt.frame_bytes   == fmt.frame_samples * fmt.channels * 2;
    snprintf(detail, sizeof(detail),
             "rate=%d ch=%d frame_samples=%d frame_bytes=%d (hint 16000 ignored, per I3)",
             fmt.sample_rate, fmt.channels, fmt.frame_samples, fmt.frame_bytes);
    report(ok1, "1", "open() yields a plausible format", detail);

    int32_t rc = cleona_voice_start(s);
    if (rc != CLEONA_VOICE_OK) {
        snprintf(detail, sizeof(detail), "start() = %d", rc);
        report(0, "-", "start()", detail);
        cleona_voice_close(s);
        return 1;
    }

    /* ------------------------------------------------------------------
     * Check 2 — report.duplex == 1 (I2).
     * ------------------------------------------------------------------ */
    cleona_voice_report_t rep;
    cleona_voice_get_report(s, &rep);
    snprintf(detail, sizeof(detail), "duplex=%d backend=%d", rep.duplex, rep.backend);
    report(rep.duplex == 1, "2", "report.duplex == 1 (one OS duplex session)", detail);

    /* ------------------------------------------------------------------
     * Check 3 — 200 consecutive capture_read always deliver exactly
     *           frame_samples, never a deviating size (I4).
     *
     * Verified in both directions:
     *   under-write: the frame region must no longer contain POISON, which no
     *                tone sample can produce (see the POISON comment);
     *   over-write:  the guard region beyond the frame must still be POISON.
     * ------------------------------------------------------------------ */
    const int32_t N3 = 200;
    int16_t* buf = (int16_t*)malloc((size_t)(fmt.frame_samples + GUARD_SAMPLES) * sizeof(int16_t));
    if (!buf) { printf("FATAL: out of memory\n"); cleona_voice_close(s); return 1; }

    int32_t got = 0, timeouts = 0, closed = 0, short_frames = 0, overwrites = 0;
    for (int32_t i = 0; i < N3; i++) {
        for (int32_t k = 0; k < fmt.frame_samples + GUARD_SAMPLES; k++) buf[k] = POISON;
        int32_t r = cleona_voice_capture_read(s, buf, 200);
        if (r == CLEONA_VOICE_CAPTURE_FRAME) {
            got++;
            int poisoned_in_frame = 0;
            for (int32_t k = 0; k < fmt.frame_samples; k++) {
                if (buf[k] == POISON) { poisoned_in_frame = 1; break; }
            }
            if (poisoned_in_frame) short_frames++;
            for (int32_t k = fmt.frame_samples; k < fmt.frame_samples + GUARD_SAMPLES; k++) {
                if (buf[k] != POISON) { overwrites++; break; }
            }
        } else if (r == CLEONA_VOICE_CAPTURE_TIMEOUT) {
            timeouts++;
        } else {
            closed++;
            break;
        }
    }
    int ok3 = (got == N3) && (short_frames == 0) && (overwrites == 0)
              && (timeouts == 0) && (closed == 0);
    snprintf(detail, sizeof(detail),
             "frames=%d/%d short=%d overwrite=%d timeout=%d closed=%d",
             got, N3, short_frames, overwrites, timeouts, closed);
    report(ok3, "3", "200x capture_read deliver exactly frame_samples", detail);

    /* ------------------------------------------------------------------
     * Check 4 — playback_write with the wrong frame size is REJECTED.
     *
     * Both directions are probed: too small and too large. A backend that
     * padded or truncated instead would turn a rate mismatch into a mystery
     * three layers up.
     * ------------------------------------------------------------------ */
    int16_t* pb = (int16_t*)calloc((size_t)fmt.frame_samples * 2, sizeof(int16_t));
    if (!pb) { printf("FATAL: out of memory\n"); free(buf); cleona_voice_close(s); return 1; }

    int32_t r_ok    = cleona_voice_playback_write(s, pb, fmt.frame_samples);
    int32_t r_small = cleona_voice_playback_write(s, pb, fmt.frame_samples - 1);
    int32_t r_big   = cleona_voice_playback_write(s, pb, fmt.frame_samples * 2);
    int32_t r_zero  = cleona_voice_playback_write(s, pb, 0);
    int ok4 = (r_ok == CLEONA_VOICE_OK)
           && (r_small == CLEONA_VOICE_ERR_FRAME_SIZE)
           && (r_big   == CLEONA_VOICE_ERR_FRAME_SIZE)
           && (r_zero  == CLEONA_VOICE_ERR_FRAME_SIZE);
    snprintf(detail, sizeof(detail), "exact=%d small=%d big=%d zero=%d (expect 0,-5,-5,-5)",
             r_ok, r_small, r_big, r_zero);
    report(ok4, "4", "playback_write rejects a wrong frame size", detail);

    /* ------------------------------------------------------------------
     * Check 5 — set_mic_muted(1) keeps the capture stream OPEN and on the
     *           same cadence (I6).
     *
     * Two properties, both required:
     *   a) the same number of frames arrives in the same wall-clock time as
     *      unmuted — a stream that was stopped would time out instead;
     *   b) the frames are silent — mute must actually mute.
     * Only (a)+(b) together distinguish "muted stream" from "stopped stream"
     * and from "mute did nothing".
     * ------------------------------------------------------------------ */
    const int32_t N5 = 50;   /* 50 x 20 ms = 1.0 s per phase */

    int64_t t0 = now_ms();
    int32_t unmuted_frames = 0;
    for (int32_t i = 0; i < N5; i++) {
        if (cleona_voice_capture_read(s, buf, 200) == CLEONA_VOICE_CAPTURE_FRAME) unmuted_frames++;
    }
    int64_t unmuted_ms = now_ms() - t0;

    cleona_voice_set_mic_muted(s, 1);

    t0 = now_ms();
    int32_t muted_frames = 0, nonsilent = 0;
    for (int32_t i = 0; i < N5; i++) {
        if (cleona_voice_capture_read(s, buf, 200) == CLEONA_VOICE_CAPTURE_FRAME) {
            muted_frames++;
            for (int32_t k = 0; k < fmt.frame_samples; k++) {
                if (buf[k] != 0) { nonsilent++; break; }
            }
        }
    }
    int64_t muted_ms = now_ms() - t0;

    /* The first muted frame may still carry pre-mute samples that the device
     * had already produced — that is correct behaviour, not a defect, so one
     * non-silent frame is tolerated. Two would mean the mute did not take. */
    int64_t drift = muted_ms > unmuted_ms ? muted_ms - unmuted_ms : unmuted_ms - muted_ms;
    int ok5 = (muted_frames == N5) && (unmuted_frames == N5)
           && (nonsilent <= 1) && (drift <= 200);
    snprintf(detail, sizeof(detail),
             "unmuted %d frames/%lldms, muted %d frames/%lldms, non-silent=%d",
             unmuted_frames, (long long)unmuted_ms,
             muted_frames, (long long)muted_ms, nonsilent);
    report(ok5, "5", "mic mute keeps the stream open and on cadence", detail);
    cleona_voice_set_mic_muted(s, 0);

    /* ------------------------------------------------------------------
     * Check 6 — set_output_muted(1) keeps playback_write accepting (I6).
     *
     * The superseded implementation returned early from the drain loop while
     * the speaker was off (audio_engine.dart:353), so the jitter buffer filled
     * to its cap and burst on re-enable. Rejecting writes here would recreate
     * exactly that.
     * ------------------------------------------------------------------ */
    cleona_voice_set_output_muted(s, 1);
    int32_t accepted = 0;
    for (int32_t i = 0; i < 25; i++) {
        if (cleona_voice_playback_write(s, pb, fmt.frame_samples) == CLEONA_VOICE_OK) accepted++;
    }
    int64_t swallowed = 0;
    cleona_voice_mock_get_counters(s, NULL, NULL, &swallowed);
    int ok6 = (accepted == 25) && (swallowed >= 25);
    snprintf(detail, sizeof(detail), "accepted=%d/25 rendered_as_silence=%lld",
             accepted, (long long)swallowed);
    report(ok6, "6", "output mute keeps playback_write accepting", detail);
    cleona_voice_set_output_muted(s, 0);

    /* ------------------------------------------------------------------
     * Check 7 — every effect state is one of the four defined values, and
     *           chain_origin is set whenever any state is ENABLED (I11).
     * ------------------------------------------------------------------ */
    cleona_voice_get_report(s, &rep);
    int states_defined = fx_is_defined(rep.aec_state)
                      && fx_is_defined(rep.ns_state)
                      && fx_is_defined(rep.agc_state);
    int any_enabled = rep.aec_state == CLEONA_VOICE_FX_ENABLED
                   || rep.ns_state  == CLEONA_VOICE_FX_ENABLED
                   || rep.agc_state == CLEONA_VOICE_FX_ENABLED;
    int chain_ok = !any_enabled || rep.chain_origin != CLEONA_VOICE_CHAIN_NONE;
    /* The mock's default deliberately contains a not_determinable state, so
     * this check also proves the report path handles the answer that cannot
     * be faked into "enabled". */
    int has_unknown = rep.aec_state == CLEONA_VOICE_FX_UNKNOWN
                   || rep.ns_state  == CLEONA_VOICE_FX_UNKNOWN
                   || rep.agc_state == CLEONA_VOICE_FX_UNKNOWN;
    int ok7 = states_defined && chain_ok && has_unknown;
    snprintf(detail, sizeof(detail), "aec=%s ns=%s agc=%s chain=%d",
             fx_name(rep.aec_state), fx_name(rep.ns_state), fx_name(rep.agc_state),
             rep.chain_origin);
    report(ok7, "7", "effect states defined; chain_origin set when ENABLED", detail);

    /* ------------------------------------------------------------------
     * Check 8 — get_routes returns a mask that contains the active route.
     * ------------------------------------------------------------------ */
    int32_t mask = 0, active = 0;
    int32_t rr = cleona_voice_get_routes(s, &mask, &active);
    int ok8 = (rr == CLEONA_VOICE_OK)
           && (active != CLEONA_VOICE_ROUTE_UNKNOWN)
           && ((mask & CLEONA_VOICE_ROUTE_BIT(active)) != 0)
           && ((mask & CLEONA_VOICE_ROUTE_BIT(CLEONA_VOICE_ROUTE_UNKNOWN)) == 0);
    snprintf(detail, sizeof(detail), "rc=%d mask=0x%02x active=%d", rr, mask, active);
    report(ok8, "8", "get_routes: active route is present in the mask", detail);

    /* ------------------------------------------------------------------
     * Supplementary — §4 semantics that only a wrong backend gets wrong.
     * Not part of the nine, but cheap here and load-bearing for V1.5/V1.6.
     * ------------------------------------------------------------------ */

    /* S1: poll_event is non-blocking and answers EV_NONE when idle. */
    int32_t ev = -1, arg = -1;
    int32_t pe = cleona_voice_poll_event(s, &ev, &arg);
    int okS1 = (pe == CLEONA_VOICE_OK) && (ev == CLEONA_VOICE_EV_NONE) && (arg == 0);
    snprintf(detail, sizeof(detail), "rc=%d event=%d arg=%d", pe, ev, arg);
    report(okS1, "S1", "poll_event returns EV_NONE when idle", detail);

    /* S2: a simulated route change surfaces through poll_event with the new
     * mask, and the mock does NOT pick a successor route — that decision is
     * I7 and belongs to RoutePolicy (V1.5). */
    int32_t new_mask = CLEONA_VOICE_ROUTE_BIT(CLEONA_VOICE_ROUTE_EARPIECE)
                     | CLEONA_VOICE_ROUTE_BIT(CLEONA_VOICE_ROUTE_SPEAKER)
                     | CLEONA_VOICE_ROUTE_BIT(CLEONA_VOICE_ROUTE_BLUETOOTH);
    cleona_voice_mock_set_routes(s, new_mask, CLEONA_VOICE_ROUTE_BLUETOOTH);
    ev = -1; arg = -1;
    cleona_voice_poll_event(s, &ev, &arg);
    cleona_voice_get_routes(s, &mask, &active);
    int okS2 = (ev == CLEONA_VOICE_EV_ROUTES_CHANGED) && (arg == new_mask)
            && (mask == new_mask) && (active == CLEONA_VOICE_ROUTE_BLUETOOTH);
    snprintf(detail, sizeof(detail), "event=%d arg=0x%02x mask=0x%02x active=%d",
             ev, arg, mask, active);
    report(okS2, "S2", "simulated route change surfaces via poll_event", detail);

    /* S2b: the mute state survives BOTH kinds of route change (§10.4, erratum
     * E6a) — an explicit set_route and an externally driven EV_ROUTES_CHANGED.
     *
     * The conformance harness (V0.4) can only exercise the first: it talks to an
     * unknown backend through the ABI and has no way to make one change its
     * route set from the outside. The second half is only reachable through the
     * mock's own knob, so it is checked here. Both mutes are set first, so a
     * backend keeping only one of them would be caught.
     *
     * The mask handed to mock_set_routes is the same one S2 installed, so S3's
     * assumption that WIRED is absent still holds. */
    cleona_voice_set_mic_muted(s, 1);
    cleona_voice_set_output_muted(s, 1);
    cleona_voice_get_report(s, &rep);
    int mute_before = (rep.mic_muted == 1) && (rep.output_muted == 1);

    int32_t rs2b = cleona_voice_set_route(s, CLEONA_VOICE_ROUTE_SPEAKER);
    cleona_voice_get_report(s, &rep);
    int mute_after_set_route = (rep.mic_muted == 1) && (rep.output_muted == 1);

    cleona_voice_mock_set_routes(s, new_mask, CLEONA_VOICE_ROUTE_EARPIECE);
    ev = -1; arg = -1;
    cleona_voice_poll_event(s, &ev, &arg);
    cleona_voice_get_report(s, &rep);
    int mute_after_event = (rep.mic_muted == 1) && (rep.output_muted == 1);

    cleona_voice_set_mic_muted(s, 0);
    cleona_voice_set_output_muted(s, 0);
    cleona_voice_get_report(s, &rep);
    int mute_cleared = (rep.mic_muted == 0) && (rep.output_muted == 0);

    int okS2b = mute_before && (rs2b == CLEONA_VOICE_OK) && mute_after_set_route
             && (ev == CLEONA_VOICE_EV_ROUTES_CHANGED) && mute_after_event
             && mute_cleared;
    snprintf(detail, sizeof(detail),
             "muted=%d set_route(rc=%d)->%d event=%d->%d unmuted->%d",
             mute_before, rs2b, mute_after_set_route, ev, mute_after_event,
             mute_cleared);
    report(okS2b, "S2b", "mute state survives set_route and EV_ROUTES_CHANGED",
           detail);

    /* S3: set_route to a route that is not available returns the defined code
     * instead of silently doing nothing (SPEC §4). WIRED was just removed from
     * the mask by S2. */
    int32_t sr = cleona_voice_set_route(s, CLEONA_VOICE_ROUTE_WIRED);
    int32_t sr_bad = cleona_voice_set_route(s, CLEONA_VOICE_ROUTE_UNKNOWN);
    int okS3 = (sr == CLEONA_VOICE_ERR_ROUTE_UNAVAILABLE)
            && (sr_bad == CLEONA_VOICE_ERR_INVALID_ARG);
    snprintf(detail, sizeof(detail), "unavailable=%d invalid=%d (expect -6,-1)", sr, sr_bad);
    report(okS3, "S3", "set_route reports unavailable routes explicitly", detail);

    free(pb);
    free(buf);

    /* ------------------------------------------------------------------
     * Check 9 — clean stop/close, and stop() is observable.
     *
     * The leak half of check 9 is delegated to the sanitizer: build with
     * -DCLEONA_VOICE_ASAN=ON and any leak here aborts the process with a
     * non-zero status, which is the acceptance signal. Valgrind is not
     * installed on this machine; ASan/LSan covers the same ground.
     * ------------------------------------------------------------------ */
    cleona_voice_stop(s);
    int16_t probe[8];
    int32_t after_stop_read  = cleona_voice_capture_read(s, probe, 20);
    int32_t after_stop_write = cleona_voice_playback_write(s, probe, fmt.frame_samples);
    int ok9a = (after_stop_read == CLEONA_VOICE_CAPTURE_CLOSED)
            && (after_stop_write == CLEONA_VOICE_ERR_NOT_STARTED);
    snprintf(detail, sizeof(detail), "read=%d write=%d (expect -1,-3)",
             after_stop_read, after_stop_write);
    report(ok9a, "9a", "after stop(): reads report closed, writes rejected", detail);

    cleona_voice_stop(s);          /* idempotent */
    cleona_voice_close(s);
    cleona_voice_close(NULL);      /* NULL is a no-op */
    report(1, "9b", "stop() idempotent, close() completes, close(NULL) safe",
           "leak detection via ASan/LSan exit status");

    /* ------------------------------------------------------------------
     * Desktop configuration: no earpiece. The case SPEC §4 names explicitly.
     * A second session also proves open/close is repeatable within a process.
     * ------------------------------------------------------------------ */
    cleona_voice_mock_config_desktop(&cfg);
    cleona_voice_mock_set_config(&cfg);
    cleona_voice_format_t dfmt;
    memset(&dfmt, 0, sizeof(dfmt));
    cleona_voice_session_t* d = cleona_voice_open(0, &dfmt);
    int okS4 = 0;
    if (d && cleona_voice_start(d) == CLEONA_VOICE_OK) {
        int32_t e = cleona_voice_set_route(d, CLEONA_VOICE_ROUTE_EARPIECE);
        int32_t sp = cleona_voice_set_route(d, CLEONA_VOICE_ROUTE_SPEAKER);
        okS4 = (e == CLEONA_VOICE_ERR_ROUTE_UNAVAILABLE) && (sp == CLEONA_VOICE_OK);
        snprintf(detail, sizeof(detail), "earpiece=%d speaker=%d (expect -6,0)", e, sp);
        cleona_voice_stop(d);
        cleona_voice_close(d);
    } else {
        snprintf(detail, sizeof(detail), "desktop session could not be opened");
    }
    report(okS4, "S4", "desktop chain: earpiece unavailable, speaker works", detail);

    /* ------------------------------------------------------------------
     * open() failure path: the in-band error code (cleona_voice.h).
     * ------------------------------------------------------------------ */
    cleona_voice_mock_config_default(&cfg);
    cfg.open_error = CLEONA_VOICE_ERR_PERMISSION;
    cleona_voice_mock_set_config(&cfg);
    cleona_voice_format_t efmt;
    memset(&efmt, 0, sizeof(efmt));
    cleona_voice_session_t* e = cleona_voice_open(0, &efmt);
    int okS5 = (e == NULL) && (efmt.sample_rate == CLEONA_VOICE_ERR_PERMISSION);
    snprintf(detail, sizeof(detail), "session=%p sample_rate=%d (expect NULL,-10)",
             (void*)e, efmt.sample_rate);
    report(okS5, "S5", "failed open() reports its reason in-band", detail);
    cleona_voice_mock_set_config(NULL);

    printf("-----------------------------------------------------------------------\n");
    printf("%d checks, %d failures\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
