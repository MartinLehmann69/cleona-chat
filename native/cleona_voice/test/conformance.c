/* conformance.c — the voice conformance test every backend must pass.
 *
 * Work package: docs/SPEC_VOICE_VIDEO_REWORK.md V0.4.
 * Mandatory checks: SPEC §6, all nine. Architecture: §10.4 (normative).
 *
 * Erratum E6a added four checks around the mute state — S12, C5c, C6b and S13.
 * S13 is the one that motivated the erratum: §10.4 requires that "the mute
 * states survive route changes", and until the report gained mic_muted and
 * output_muted that sentence could not be checked by anything, on any backend.
 *
 * ---------------------------------------------------------------------------
 * WHAT THIS IS FOR
 * ---------------------------------------------------------------------------
 * This is the acceptance criterion of V1.1 (PipeWire), V1.2 (Android HAL),
 * V1.3 (Apple VPIO) and V1.4 (WASAPI): "conformance test green on the target
 * platform" (SPEC §10, gate 4). Each of those packages proves itself with this
 * binary, alone, without waiting for the Dart side or for any other backend.
 *
 * It is NOT the V0.2 smoke in ../smoke/. That programme drives the mock through
 * its own knobs and proves that the mock behaves; this one knows nothing about
 * any implementation and proves that a backend keeps the contract.
 *
 * ---------------------------------------------------------------------------
 * HOW TO RUN IT AGAINST YOUR OWN BACKEND
 * ---------------------------------------------------------------------------
 * Shared library (Linux, Android, Windows, macOS) — no build integration:
 *
 *     cmake -S native/cleona_voice -B build/voice
 *     cmake --build build/voice -j
 *     ./build/voice/test/cleona_voice_conformance_loader \
 *          /path/to/libcleona_voice_pipewire.so --shipping
 *
 * Static library (iOS, or any target where dlopen is not the deployment model):
 * from your own CMakeLists, after native/cleona_voice/test has been added,
 *
 *     cleona_voice_add_conformance_test(cleona_voice_conformance_apple
 *                                       cleona_voice_apple)
 *
 * which builds this file against your target and registers it with ctest.
 *
 * Both are described in full in test/CMakeLists.txt. Nothing in this file names
 * a backend, a rate, a resolution or a vendor constant.
 *
 * ---------------------------------------------------------------------------
 * WHAT THE HARNESS REFUSES TO ASSUME
 * ---------------------------------------------------------------------------
 *  - the sample rate (I3). It asks for nothing and validates what it gets.
 *  - the frame size (I4). It reads it out of the negotiated format.
 *  - the route set. It reads the mask and works with whatever is in it.
 *  - the effect states (I11). All four values are legitimate answers; only an
 *    ENABLED without a stated chain origin is a failure.
 *  - the backend and chain ids, unless --shipping is given, where the only
 *    assertion is the one cleona_voice.h itself calls a release gate: a shipped
 *    build never reports a value in the non-shipping range (>= 100).
 *
 * ---------------------------------------------------------------------------
 * EXIT CODES
 * ---------------------------------------------------------------------------
 *   0  conformant
 *   1  at least one check failed
 *   2  the backend could not be exercised at all (open/start refused)
 * With --expect-fail the polarity is inverted; see conformance_harness.h.
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
 * Frame-size probe (SPEC §6 check 3) — the one that must not be fakeable
 * ==========================================================================
 * The buffer is poisoned before every read, the frame region must come back
 * fully overwritten, and a guard zone behind it must come back untouched.
 *
 * The V0.2 smoke used one constant poison value (0x5A5A) and relied on the
 * mock's synthetic tone never producing it. That reasoning does not survive
 * contact with a microphone: a real capture stream produces every 16-bit value,
 * so with 960 samples per frame and 200 frames the probability of at least one
 * genuine sample colliding with a fixed poison value is about 95%. On real
 * hardware that smoke would fail for the wrong reason roughly every other run,
 * and a check that cries wolf gets deleted.
 *
 * This harness therefore uses a POSITION- AND FRAME-DEPENDENT pattern and only
 * looks at the TRAILING RUN of surviving poison, which is what a short write
 * actually leaves behind:
 *
 *   trailing run >= 2  ->  hard defect. Two independent coincidences at two
 *                          specific positions is 2^-32 per frame; over the
 *                          whole run it is not a thing that happens.
 *   trailing run == 1  ->  "suspect". A single coincidence is 2^-16 per frame,
 *                          i.e. about one run in 300. Three suspects are
 *                          required before it counts as a defect (~5e-9 by
 *                          chance), while a backend that systematically drops
 *                          the last sample produces ~200 of them.
 *
 * That keeps the check unfakeable in the direction that matters — a backend
 * short-writing by any realistic amount is caught with certainty — without
 * being flaky on a real device.
 */
#define GUARD_SAMPLES 64

static int16_t poison_at(int32_t k, uint32_t salt) {
    uint32_t x = (uint32_t)k * 2654435761u ^ (salt * 2246822519u);
    x ^= x >> 15;
    x *= 2654435761u;
    x ^= x >> 13;
    return (int16_t)(uint16_t)(x & 0xFFFFu);
}

/* ==========================================================================
 * Small helpers
 * ========================================================================== */

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

static const char* route_name(int32_t r) {
    switch (r) {
        case CLEONA_VOICE_ROUTE_UNKNOWN:   return "unknown";
        case CLEONA_VOICE_ROUTE_EARPIECE:  return "earpiece";
        case CLEONA_VOICE_ROUTE_SPEAKER:   return "speaker";
        case CLEONA_VOICE_ROUTE_WIRED:     return "wired";
        case CLEONA_VOICE_ROUTE_BLUETOOTH: return "bluetooth";
        default:                           return "INVALID";
    }
}

static int event_is_defined(int32_t e) {
    return e >= CLEONA_VOICE_EV_NONE && e <= CLEONA_VOICE_EV_FORMAT_CHANGED;
}

/* Mean absolute amplitude of a frame — used only to describe what mute did,
 * never on its own as a verdict (see check 5). */
static double mean_abs(const int16_t* p, int32_t n) {
    double acc = 0.0;
    for (int32_t i = 0; i < n; i++) {
        int32_t v = p[i];
        acc += (v < 0) ? -(double)v : (double)v;
    }
    return n > 0 ? acc / (double)n : 0.0;
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
"                      may also be given with --lib or in CLEONA_VOICE_LIB.\n"
"  --lib <path>        same as the positional argument\n"
"  --json <path>       also write the machine-readable report to <path>\n"
"  --shipping          additionally assert that the backend does not report\n"
"                      the non-shipping id range (>= 100). Platform packages\n"
"                      run with this; the mock cannot pass it, by design.\n"
"  --expect-fail <ids> harness self-test: comma-separated check ids that MUST\n"
"                      fail and no others. Used by the negative controls.\n"
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
    if (cvbind_init(o.lib, err, sizeof(err)) != 0) {
        printf("FATAL %s\n", err);
        return 2;
    }

    ch_begin("cleona_voice conformance (SPEC section 6, checks 1-9)",
             cvbind_mode(), cvbind_library());

    /* ==================================================================== *
     * Check 1 — open() yields a plausible, self-consistent format.
     *
     * rate_hint is 0, "no preference" (cleona_voice.h). Asking for a specific
     * rate here would test the harness's taste, not the backend: I3 says the
     * platform decides and that ignoring a hint is not an error.
     * ==================================================================== */
    ch_section("open and negotiated format");

    cleona_voice_format_t fmt;
    memset(&fmt, 0, sizeof(fmt));
    cleona_voice_session_t* s = CV.open(0, &fmt);
    if (!s) {
        char reason[256];
        snprintf(reason, sizeof(reason),
                 "cleona_voice_open(0, &fmt) returned NULL, in-band error code "
                 "%d in out_format->sample_rate", fmt.sample_rate);
        return ch_abort(reason);
    }

    int ok1 = fmt.sample_rate >= CLEONA_VOICE_RATE_MIN
           && fmt.sample_rate <= CLEONA_VOICE_RATE_MAX
           && fmt.channels == CLEONA_VOICE_CHANNELS
           && fmt.frame_samples > 0
           && fmt.frame_samples == fmt.sample_rate / CLEONA_VOICE_FRAME_HZ
           && fmt.frame_bytes   == fmt.frame_samples * fmt.channels * 2;
    ch_check("C1", "open() yields a plausible, self-consistent format", ok1,
             "rate=%d ch=%d frame_samples=%d frame_bytes=%d",
             fmt.sample_rate, fmt.channels, fmt.frame_samples, fmt.frame_bytes);

    if (fmt.sample_rate % CLEONA_VOICE_FRAME_HZ != 0) {
        ch_note("N1", "sample rate is not a multiple of 50 Hz",
                "rate=%d -> a 20 ms frame is %d.%02d samples and cannot be exact",
                fmt.sample_rate,
                fmt.sample_rate / CLEONA_VOICE_FRAME_HZ,
                (fmt.sample_rate % CLEONA_VOICE_FRAME_HZ) * 2);
    }

    if (fmt.frame_samples <= 0) {
        return ch_abort("negotiated frame_samples <= 0; nothing else can be tested");
    }

    /* ==================================================================== *
     * S12 (erratum E6a) — the report's mute state starts at 0/0.
     *
     * Read BEFORE start(), which cleona_voice.h explicitly permits. This is the
     * only moment at which "nothing has been muted yet" is a fact rather than an
     * assumption, so it is the only moment at which a backend that comes up with
     * a stale or uninitialised mute flag can be told apart from one that does
     * not. Everything after this point has called a setter.
     *
     * The struct is poisoned with 0x5A rather than zeroed: get_report() is
     * documented to FILL the report, and a check whose expected value is also
     * the value of an untouched buffer proves nothing.
     * ==================================================================== */
    cleona_voice_report_t rep0;
    memset(&rep0, 0x5A, sizeof(rep0));
    CV.get_report(s, &rep0);
    ch_check("S12", "mute state after open() is 0/0 (E6a)",
             rep0.mic_muted == 0 && rep0.output_muted == 0,
             "mic_muted=%d output_muted=%d (buffer poisoned with 0x5A5A5A5A "
             "beforehand, so an unwritten field cannot read as 0)",
             rep0.mic_muted, rep0.output_muted);

    int32_t rc = CV.start(s);
    if (rc != CLEONA_VOICE_OK) {
        char reason[192];
        snprintf(reason, sizeof(reason), "cleona_voice_start() returned %d", rc);
        CV.close(s);
        return ch_abort(reason);
    }

    /* ==================================================================== *
     * Checks 2, 7, 8 — the verification report (I11) and the route model.
     * ==================================================================== */
    ch_section("verification report (I11) and routes");

    cleona_voice_report_t rep;
    memset(&rep, 0, sizeof(rep));
    CV.get_report(s, &rep);

    ch_check("C2", "report.duplex == 1 (one OS duplex session, I2)",
             rep.duplex == 1, "duplex=%d backend=%d", rep.duplex, rep.backend);

    int states_defined = fx_is_defined(rep.aec_state)
                      && fx_is_defined(rep.ns_state)
                      && fx_is_defined(rep.agc_state);
    int any_enabled = rep.aec_state == CLEONA_VOICE_FX_ENABLED
                   || rep.ns_state  == CLEONA_VOICE_FX_ENABLED
                   || rep.agc_state == CLEONA_VOICE_FX_ENABLED;
    int chain_ok = !any_enabled || rep.chain_origin != CLEONA_VOICE_CHAIN_NONE;
    ch_check("C7", "effect states defined; chain_origin set when ENABLED",
             states_defined && chain_ok,
             "aec=%s ns=%s agc=%s chain_origin=%d",
             fx_name(rep.aec_state), fx_name(rep.ns_state),
             fx_name(rep.agc_state), rep.chain_origin);

    /* SPEC §6: "acceptance of a backend means conformance green + report
     * logged + a documented reason for every effect that is not ENABLED".
     * The harness cannot write that reason, but it can make sure nobody
     * forgets which ones need one. */
    if (rep.aec_state != CLEONA_VOICE_FX_ENABLED ||
        rep.ns_state  != CLEONA_VOICE_FX_ENABLED ||
        rep.agc_state != CLEONA_VOICE_FX_ENABLED) {
        ch_note("N2", "effects not ENABLED need a documented reason (SPEC 6)",
                "aec=%s ns=%s agc=%s -- state the reason in the acceptance report",
                fx_name(rep.aec_state), fx_name(rep.ns_state),
                fx_name(rep.agc_state));
    }

    int32_t mask = 0, active = 0;
    int32_t rr = CV.get_routes(s, &mask, &active);
    int ok8 = (rr == CLEONA_VOICE_OK)
           && (active != CLEONA_VOICE_ROUTE_UNKNOWN)
           && (active >= CLEONA_VOICE_ROUTE_EARPIECE)
           && (active <= CLEONA_VOICE_ROUTE_BLUETOOTH)
           && ((mask & CLEONA_VOICE_ROUTE_BIT(active)) != 0)
           && ((mask & CLEONA_VOICE_ROUTE_BIT(CLEONA_VOICE_ROUTE_UNKNOWN)) == 0);
    ch_check("C8", "get_routes: active route is present in the mask", ok8,
             "rc=%d mask=0x%02x active=%d(%s)", rr, mask, active, route_name(active));

    /* The report must describe THIS session, not the state at open(). */
    ch_check("S8", "report.format equals the negotiated format",
             rep.format.sample_rate == fmt.sample_rate &&
             rep.format.channels == fmt.channels &&
             rep.format.frame_samples == fmt.frame_samples &&
             rep.format.frame_bytes == fmt.frame_bytes,
             "report %d Hz / %d samples vs open %d Hz / %d samples",
             rep.format.sample_rate, rep.format.frame_samples,
             fmt.sample_rate, fmt.frame_samples);

    ch_check("S7", "get_routes rejects NULL out-pointers",
             CV.get_routes(s, NULL, &active) < 0 &&
             CV.get_routes(s, &mask, NULL) < 0,
             "both must be negative");

    if (o.shipping) {
        ch_check("S11", "shipping build: no non-shipping backend/chain id",
                 rep.backend < 100 && rep.chain_origin < 100,
                 "backend=%d chain_origin=%d (>= 100 is the mock range)",
                 rep.backend, rep.chain_origin);
    } else {
        ch_note("S11", "backend identity (assert with --shipping)",
                "backend=%d chain_origin=%d", rep.backend, rep.chain_origin);
    }

    ch_report_int("sample_rate",    fmt.sample_rate);
    ch_report_int("channels",       fmt.channels);
    ch_report_int("frame_samples",  fmt.frame_samples);
    ch_report_int("frame_bytes",    fmt.frame_bytes);
    ch_report_str("aec",            fx_name(rep.aec_state));
    ch_report_str("ns",             fx_name(rep.ns_state));
    ch_report_str("agc",            fx_name(rep.agc_state));
    ch_report_int("chain_origin",   rep.chain_origin);
    ch_report_int("backend",        rep.backend);
    ch_report_int("duplex",         rep.duplex);
    ch_report_int("route_active_in",  rep.route_active_in);
    ch_report_int("route_active_out", rep.route_active_out);
    ch_report_int("routes_mask",    rep.routes_available_mask);
    /* E6a. Snapshot right after start(), i.e. before any setter ran — so these
     * two are the same 0/0 that S12 asserted, now also in the machine-readable
     * object an acceptance report is compared from. */
    ch_report_int("mic_muted",      rep.mic_muted);
    ch_report_int("output_muted",   rep.output_muted);

    /* ==================================================================== *
     * Check 3 — 200 consecutive capture_read deliver exactly frame_samples.
     * The single most important check in this file (I4).
     * ==================================================================== */
    ch_section("frame size guarantee (I4)");

    const int32_t N3 = 200;
    const int32_t READ_TIMEOUT_MS = 500;
    const int64_t BUDGET_MS = 30000;

    size_t buf_n = (size_t)(fmt.frame_samples + GUARD_SAMPLES);
    int16_t* buf = (int16_t*)malloc(buf_n * sizeof(int16_t));
    int16_t* pb  = (int16_t*)calloc((size_t)fmt.frame_samples * 2, sizeof(int16_t));
    if (!buf || !pb) {
        free(buf); free(pb);
        CV.close(s);
        return ch_abort("out of memory");
    }

    int32_t got = 0, timeouts = 0, closed = 0;
    int32_t hard_short = 0, suspects = 0, overwrites = 0, timeout_writes = 0;
    int32_t longest_run = 0;
    int32_t bad_rc = 0;
    int64_t t_start = now_ms();

    for (int32_t i = 0; i < N3 && (now_ms() - t_start) < BUDGET_MS; i++) {
        uint32_t salt = (uint32_t)i + 1u;
        for (size_t k = 0; k < buf_n; k++) buf[k] = poison_at((int32_t)k, salt);

        int32_t r = CV.capture_read(s, buf, READ_TIMEOUT_MS);

        if (r == CLEONA_VOICE_CAPTURE_FRAME) {
            got++;
            /* trailing run of surviving poison inside the frame region */
            int32_t run = 0;
            for (int32_t k = fmt.frame_samples - 1; k >= 0; k--) {
                if (buf[k] == poison_at(k, salt)) run++;
                else break;
            }
            if (run > longest_run) longest_run = run;
            if (run >= 2)      hard_short++;
            else if (run == 1) suspects++;

            for (int32_t k = fmt.frame_samples;
                 k < fmt.frame_samples + GUARD_SAMPLES; k++) {
                if (buf[k] != poison_at(k, salt)) { overwrites++; break; }
            }
        } else if (r == CLEONA_VOICE_CAPTURE_TIMEOUT) {
            timeouts++;
            /* "nothing written" is part of the contract for a timeout. */
            for (size_t k = 0; k < buf_n; k++) {
                if (buf[k] != poison_at((int32_t)k, salt)) { timeout_writes++; break; }
            }
            i--;   /* a timeout is not a frame; keep asking for 200 frames */
            if (timeouts > N3) break;
        } else if (r == CLEONA_VOICE_CAPTURE_CLOSED) {
            closed++;
            break;
        } else {
            bad_rc++;
            break;
        }
    }

    int ok3 = (got == N3) && (hard_short == 0) && (suspects < 3)
           && (overwrites == 0) && (closed == 0) && (bad_rc == 0)
           && (timeout_writes == 0);
    ch_check("C3", "200x capture_read deliver exactly frame_samples (I4)", ok3,
             "frames=%d/%d short=%d suspect=%d longest_poison_run=%d "
             "overwrite=%d timeouts=%d closed=%d bad_rc=%d wrote_on_timeout=%d",
             got, N3, hard_short, suspects, longest_run, overwrites,
             timeouts, closed, bad_rc, timeout_writes);

    /* ==================================================================== *
     * Check 4 — playback_write rejects a wrong frame size.
     * ==================================================================== */
    ch_section("playback path");

    int32_t r_ok    = CV.playback_write(s, pb, fmt.frame_samples);
    int32_t r_small = CV.playback_write(s, pb, fmt.frame_samples - 1);
    int32_t r_big   = CV.playback_write(s, pb, fmt.frame_samples * 2);
    int32_t r_zero  = CV.playback_write(s, pb, 0);
    int32_t r_neg   = CV.playback_write(s, pb, -1);
    int ok4 = (r_ok == CLEONA_VOICE_OK)
           && (r_small == CLEONA_VOICE_ERR_FRAME_SIZE)
           && (r_big   == CLEONA_VOICE_ERR_FRAME_SIZE)
           && (r_zero  == CLEONA_VOICE_ERR_FRAME_SIZE)
           && (r_neg   == CLEONA_VOICE_ERR_FRAME_SIZE);
    ch_check("C4", "playback_write rejects a wrong frame size", ok4,
             "exact=%d small=%d big=%d zero=%d negative=%d (expect 0,-5,-5,-5,-5)",
             r_ok, r_small, r_big, r_zero, r_neg);

    {
        const int32_t NW = 50;
        int64_t tw = now_ms();
        int32_t acc = 0;
        for (int32_t i = 0; i < NW; i++) {
            if (CV.playback_write(s, pb, fmt.frame_samples) == CLEONA_VOICE_OK) acc++;
        }
        int64_t el = now_ms() - tw;
        /* 50 frames are 1000 ms of audio. Anything that paced them would take
         * about that long; the write path must not (I5 — the output device
         * paces, not the caller). */
        ch_check("S3", "playback_write never blocks (I5)",
                 acc == NW && el < 200,
                 "accepted=%d/%d elapsed=%lldms for 1000 ms of audio",
                 acc, NW, (long long)el);
    }

    /* ==================================================================== *
     * Check 5 — mic mute keeps the capture stream open and on cadence (I6).
     * ==================================================================== */
    ch_section("mute behaviour (I6)");

    const int32_t N5 = 50;   /* 50 x 20 ms = one second per phase */
    int64_t t0 = now_ms();
    int32_t unmuted_frames = 0;
    double unmuted_level = 0.0;
    for (int32_t i = 0; i < N5; i++) {
        if (CV.capture_read(s, buf, READ_TIMEOUT_MS) == CLEONA_VOICE_CAPTURE_FRAME) {
            unmuted_frames++;
            unmuted_level += mean_abs(buf, fmt.frame_samples);
        }
    }
    int64_t unmuted_ms = now_ms() - t0;
    if (unmuted_frames > 0) unmuted_level /= (double)unmuted_frames;

    CV.set_mic_muted(s, 1);

    t0 = now_ms();
    int32_t muted_frames = 0;
    double muted_level = 0.0;
    for (int32_t i = 0; i < N5; i++) {
        if (CV.capture_read(s, buf, READ_TIMEOUT_MS) == CLEONA_VOICE_CAPTURE_FRAME) {
            muted_frames++;
            /* The first muted frame may still carry samples the device had
             * already produced before the mute took effect. Excluded from the
             * level, counted for the cadence. */
            if (muted_frames > 1) muted_level += mean_abs(buf, fmt.frame_samples);
        }
    }
    int64_t muted_ms = now_ms() - t0;
    if (muted_frames > 1) muted_level /= (double)(muted_frames - 1);

    int64_t drift = muted_ms > unmuted_ms ? muted_ms - unmuted_ms
                                          : unmuted_ms - muted_ms;
    /* Cadence is the contract: a stream that was stopped instead of muted
     * would time out (50 x 500 ms) or report CLOSED, both of which this
     * catches with a wide margin. The tolerance is deliberately generous so a
     * loaded device does not produce a false verdict. */
    int ok5 = (muted_frames == N5) && (unmuted_frames == N5)
           && (drift <= unmuted_ms / 2 + 300);
    ch_check("C5", "mic mute keeps the capture stream open and on cadence", ok5,
             "unmuted %d frames/%lldms level=%.0f, muted %d frames/%lldms level=%.0f",
             unmuted_frames, (long long)unmuted_ms, unmuted_level,
             muted_frames, (long long)muted_ms, muted_level);

    /* Whether mute actually silences is checked only when there WAS a signal to
     * silence. In a quiet room the unmuted level is already near zero and the
     * comparison would be vacuous — reporting that honestly is better than a
     * check that passes because nothing happened. */
    if (unmuted_level >= 64.0) {
        ch_check("C5b", "mic mute actually removes the signal",
                 muted_level <= unmuted_level / 8.0,
                 "unmuted=%.0f muted=%.0f (threshold %.0f)",
                 unmuted_level, muted_level, unmuted_level / 8.0);
    } else {
        ch_note("C5b", "mic mute level comparison not conclusive",
                "unmuted level %.1f is too low to prove muting; cadence checked "
                "in C5", unmuted_level);
    }

    /* C5c (erratum E6a) — "did set_mic_muted do anything?" answered from the
     * report instead of from the signal. C5b can only answer it when there was
     * a signal to remove, which on a real device in a quiet room there is not;
     * that gap is exactly what E6a closes. The output flag is read at the same
     * time and must still be 0 — a backend with one shared mute flag for both
     * directions is a real mistake and is caught here, not in the field. */
    cleona_voice_report_t repm;
    memset(&repm, 0x5A, sizeof(repm));
    CV.get_report(s, &repm);              /* still muted at this point */
    int32_t mic_while_muted = repm.mic_muted;
    int32_t out_while_mic_muted = repm.output_muted;

    CV.set_mic_muted(s, 0);

    memset(&repm, 0x5A, sizeof(repm));
    CV.get_report(s, &repm);
    int32_t mic_after_unmute = repm.mic_muted;

    ch_check("C5c", "set_mic_muted is observable in the report (E6a)",
             mic_while_muted == 1 && mic_after_unmute == 0 &&
             out_while_mic_muted == 0,
             "set_mic_muted(1) -> mic_muted=%d (expect 1), set_mic_muted(0) -> "
             "mic_muted=%d (expect 0); output_muted was %d while only the "
             "microphone was muted (expect 0)",
             mic_while_muted, mic_after_unmute, out_while_mic_muted);

    /* ==================================================================== *
     * Check 6 — output mute keeps playback_write accepting (I6).
     * ==================================================================== */
    CV.set_output_muted(s, 1);
    int32_t accepted = 0;
    for (int32_t i = 0; i < 25; i++) {
        if (CV.playback_write(s, pb, fmt.frame_samples) == CLEONA_VOICE_OK) accepted++;
    }
    ch_check("C6", "output mute keeps playback_write accepting", accepted == 25,
             "accepted=%d/25", accepted);

    /* C6b (erratum E6a) — the output direction has no signal-level observable at
     * all: playback_write accepting a frame looks identical muted and unmuted,
     * which is precisely what C6 requires. Before E6a "sound off" was therefore
     * unverifiable in every direction. */
    cleona_voice_report_t repo;
    memset(&repo, 0x5A, sizeof(repo));
    CV.get_report(s, &repo);              /* still output-muted at this point */
    int32_t out_while_muted = repo.output_muted;
    int32_t mic_while_out_muted = repo.mic_muted;

    CV.set_output_muted(s, 0);

    memset(&repo, 0x5A, sizeof(repo));
    CV.get_report(s, &repo);
    int32_t out_after_unmute = repo.output_muted;

    ch_check("C6b", "set_output_muted is observable in the report (E6a)",
             out_while_muted == 1 && out_after_unmute == 0 &&
             mic_while_out_muted == 0,
             "set_output_muted(1) -> output_muted=%d (expect 1), "
             "set_output_muted(0) -> output_muted=%d (expect 0); mic_muted was "
             "%d while only the output was muted (expect 0)",
             out_while_muted, out_after_unmute, mic_while_out_muted);

    /* ==================================================================== *
     * Events and routes — §4 semantics the ABI fixes for all backends.
     * ==================================================================== */
    ch_section("events and route control");

    int32_t ev = -1, arg = -1;
    t0 = now_ms();
    int32_t pe = CV.poll_event(s, &ev, &arg);
    int64_t poll_ms = now_ms() - t0;
    ch_check("S1", "poll_event is non-blocking and returns a defined event",
             pe == CLEONA_VOICE_OK && event_is_defined(ev) && poll_ms < 50,
             "rc=%d event=%d arg=%d elapsed=%lldms", pe, ev, arg,
             (long long)poll_ms);
    ch_check("S1b", "poll_event rejects NULL out-pointers",
             CV.poll_event(s, NULL, &arg) < 0 && CV.poll_event(s, &ev, NULL) < 0,
             "both must be negative");

    t0 = now_ms();
    int32_t rpoll = CV.capture_read(s, buf, 0);
    int64_t rpoll_ms = now_ms() - t0;
    ch_check("S2", "capture_read(timeout_ms = 0) polls instead of blocking",
             (rpoll == CLEONA_VOICE_CAPTURE_FRAME ||
              rpoll == CLEONA_VOICE_CAPTURE_TIMEOUT) && rpoll_ms < 50,
             "rc=%d elapsed=%lldms", rpoll, (long long)rpoll_ms);

    ch_check("S4", "set_route rejects ROUTE_UNKNOWN and out-of-range values",
             CV.set_route(s, CLEONA_VOICE_ROUTE_UNKNOWN) == CLEONA_VOICE_ERR_INVALID_ARG &&
             CV.set_route(s, 99) == CLEONA_VOICE_ERR_INVALID_ARG &&
             CV.set_route(s, -1) == CLEONA_VOICE_ERR_INVALID_ARG,
             "all three must be %d", CLEONA_VOICE_ERR_INVALID_ARG);

    CV.get_routes(s, &mask, &active);
    int32_t other = CLEONA_VOICE_ROUTE_UNKNOWN, absent = CLEONA_VOICE_ROUTE_UNKNOWN;
    for (int32_t r = CLEONA_VOICE_ROUTE_EARPIECE; r <= CLEONA_VOICE_ROUTE_BLUETOOTH; r++) {
        if ((mask & CLEONA_VOICE_ROUTE_BIT(r)) && r != active && other == CLEONA_VOICE_ROUTE_UNKNOWN) other = r;
        if (!(mask & CLEONA_VOICE_ROUTE_BIT(r)) && absent == CLEONA_VOICE_ROUTE_UNKNOWN) absent = r;
    }

    if (absent != CLEONA_VOICE_ROUTE_UNKNOWN) {
        int32_t ra = CV.set_route(s, absent);
        ch_check("S5", "set_route to an unavailable route reports it explicitly",
                 ra == CLEONA_VOICE_ERR_ROUTE_UNAVAILABLE ||
                 ra == CLEONA_VOICE_ERR_ROUTE_UNSUPPORTED,
                 "route %s -> %d (expect %d or %d, never a silent 0)",
                 route_name(absent), ra, CLEONA_VOICE_ERR_ROUTE_UNAVAILABLE,
                 CLEONA_VOICE_ERR_ROUTE_UNSUPPORTED);
    } else {
        ch_note("S5", "every route is available; unavailable path not reachable",
                "mask=0x%02x", mask);
    }

    if (other != CLEONA_VOICE_ROUTE_UNKNOWN) {
        /* S13 (erratum E6a) — architecture §10.4, "In-call controls": the mute
         * states survive route changes. Both directions are muted BEFORE the
         * switch and read back after it.
         *
         * This is the assurance the ABI could not carry until E6a. It matters in
         * practice because a backend that switches routes by rebuilding its OS
         * session has to carry the two flags across that rebuild by hand, and
         * the failure mode — the microphone silently going live again when a
         * headset is unplugged mid-call — is one a user finds out about after
         * the fact. */
        CV.set_mic_muted(s, 1);
        CV.set_output_muted(s, 1);

        int32_t rs = CV.set_route(s, other);
        int32_t after_mask = 0, after_active = 0;
        CV.get_routes(s, &after_mask, &after_active);

        cleona_voice_report_t repr;
        memset(&repr, 0x5A, sizeof(repr));
        CV.get_report(s, &repr);
        if (rs == CLEONA_VOICE_OK) {
            ch_check("S13", "the mute state survives a route change (10.4)",
                     repr.mic_muted == 1 && repr.output_muted == 1,
                     "muted both, switched %s -> %s, then mic_muted=%d "
                     "output_muted=%d (both must still be 1)",
                     route_name(active), route_name(other),
                     repr.mic_muted, repr.output_muted);
        } else {
            /* No switch happened, so nothing was put at risk. Recorded rather
             * than passed: a check that "passes" because the operation it
             * examines never ran is the failure mode this harness exists to
             * avoid. */
            ch_note("S13", "route switch declined; mute survival not exercised",
                    "set_route(%s) = %d; mic_muted=%d output_muted=%d",
                    route_name(other), rs, repr.mic_muted, repr.output_muted);
        }
        CV.set_mic_muted(s, 0);
        CV.set_output_muted(s, 0);
        /* A backend without route control answers ERR_ROUTE_UNSUPPORTED; that
         * is a legitimate answer and is recorded, not failed. What must never
         * happen is a switch that tears the capture stream down. */
        int32_t frames_after = 0;
        for (int32_t i = 0; i < 10; i++) {
            if (CV.capture_read(s, buf, READ_TIMEOUT_MS) == CLEONA_VOICE_CAPTURE_FRAME)
                frames_after++;
        }
        if (rs == CLEONA_VOICE_OK) {
            ch_check("S9", "route switch keeps the capture stream running",
                     after_active == other && frames_after == 10,
                     "switched to %s, active=%s, %d/10 frames after the switch",
                     route_name(other), route_name(after_active), frames_after);
        } else {
            ch_note("S9", "backend declined the route switch",
                    "set_route(%s) = %d; %d/10 frames still delivered",
                    route_name(other), rs, frames_after);
        }
    } else {
        ch_note("S9", "only one route available; switch not exercised",
                "mask=0x%02x active=%s", mask, route_name(active));
        ch_note("S13", "only one route available; mute survival not exercised",
                "mask=0x%02x active=%s -- there is no second route to switch to",
                mask, route_name(active));
    }

    /* Counters are monotonic since open() (cleona_voice.h). */
    cleona_voice_report_t rep2;
    memset(&rep2, 0, sizeof(rep2));
    CV.get_report(s, &rep2);
    ch_check("S10", "underrun/overrun counters are monotonic",
             rep2.underruns >= rep.underruns && rep2.overruns >= rep.overruns,
             "underruns %lld -> %lld, overruns %lld -> %lld",
             (long long)rep.underruns, (long long)rep2.underruns,
             (long long)rep.overruns, (long long)rep2.overruns);
    ch_report_int("underruns", rep2.underruns);
    ch_report_int("overruns",  rep2.overruns);

    /* A second, differently hinted open on a fresh session: I3 says the hint
     * may be ignored and that this is not an error. Recorded, never failed. */
    {
        cleona_voice_format_t hfmt;
        memset(&hfmt, 0, sizeof(hfmt));
        cleona_voice_session_t* h = CV.open(16000, &hfmt);
        if (h) {
            ch_note("N3", "rate_hint handling (I3: ignoring it is not an error)",
                    "hint 16000 -> negotiated %d Hz", hfmt.sample_rate);
            CV.close(h);
        } else {
            ch_note("N3", "second concurrent open() refused",
                    "err=%d -- single-session backend, recorded not failed",
                    hfmt.sample_rate);
        }
    }

    /* ==================================================================== *
     * Check 9 — clean stop/close.
     * ==================================================================== */
    ch_section("teardown (SPEC check 9)");

    CV.stop(s);
    int32_t after_stop_read  = CV.capture_read(s, buf, 20);
    int32_t after_stop_write = CV.playback_write(s, pb, fmt.frame_samples);
    ch_check("C9a", "after stop(): reads report closed, writes rejected",
             after_stop_read == CLEONA_VOICE_CAPTURE_CLOSED &&
             after_stop_write == CLEONA_VOICE_ERR_NOT_STARTED,
             "read=%d write=%d (expect %d,%d)", after_stop_read, after_stop_write,
             CLEONA_VOICE_CAPTURE_CLOSED, CLEONA_VOICE_ERR_NOT_STARTED);

    CV.stop(s);   /* idempotent */
    int32_t restart = CV.start(s);
    int32_t restart_frames = 0;
    if (restart == CLEONA_VOICE_OK) {
        for (int32_t i = 0; i < 5; i++) {
            if (CV.capture_read(s, buf, READ_TIMEOUT_MS) == CLEONA_VOICE_CAPTURE_FRAME)
                restart_frames++;
        }
    }
    cleona_voice_report_t rep3;
    memset(&rep3, 0, sizeof(rep3));
    CV.get_report(s, &rep3);
    ch_check("C9b", "stop() is idempotent and a stopped session restarts",
             restart == CLEONA_VOICE_OK && restart_frames == 5 &&
             rep3.format.frame_samples == fmt.frame_samples,
             "start-after-stop=%d frames=%d/5 frame_samples retained=%d",
             restart, restart_frames, rep3.format.frame_samples);

    CV.stop(s);
    CV.close(s);
    s = NULL;
    CV.close(NULL);   /* documented no-op */
    CV.stop(NULL);
    ch_check("C9c", "close() completes; close(NULL)/stop(NULL) are no-ops", 1,
             "leak detection is the sanitizer's half of check 9");

    /* The allocation path that leaks most easily: open without ever starting. */
    cleona_voice_format_t ofmt;
    memset(&ofmt, 0, sizeof(ofmt));
    cleona_voice_session_t* s2 = CV.open(0, &ofmt);
    int reopened = (s2 != NULL);
    if (s2) CV.close(s2);
    ch_check("C9d", "open/close without start is repeatable in one process",
             reopened, "second session %s", reopened ? "opened and closed" : "refused");

    cleona_voice_report_t rnull;
    memset(&rnull, 0x7F, sizeof(rnull));
    CV.get_report(NULL, &rnull);
    ch_check("S6", "get_report(NULL) zero-fills, so it reads as a failure",
             rnull.duplex == 0 && rnull.format.sample_rate == 0,
             "duplex=%d sample_rate=%d", rnull.duplex, rnull.format.sample_rate);

    free(buf);
    free(pb);

    int code = ch_end(o.json, o.expect, o.expect_n);
    cvbind_shutdown();
    return code;
}
