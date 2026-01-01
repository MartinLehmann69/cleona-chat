// Offline AEC measurement — no microphone, no speaker, no device.
//
// Purpose (B14): decide whether speexdsp's echo canceller still earns its
// place on Android now that the capture stream is declared
// VOICE_COMMUNICATION (cleona_audio.c:210-218) and the platform HAL cancels
// echo before we ever see the samples. Two cancellers in series is not
// automatically better — the second one adapts against a reference signal
// whose echo is already gone, and a misadapted filter subtracts from the
// near-end speech instead.
//
// The question is pure DSP and therefore measurable without hardware. Every
// scenario below drives `cleona_audio_process_frame_for_test`, which runs the
// SAME chain as the live capture callback (speex_echo_cancellation +
// speex_preprocess_run, identical state, identical parameters).
//
// Reference latencies come from the Pixel 8 Pro measurement recorded in
// BUGFIX_CURRENT.md: 48 kHz native, FAST path 20 ms, mixer path 60 ms. The
// speex tail is fixed at 250 ms (cleona_audio.c:71-73).
//
//   ./test_aec
//
// Exit code 0 = all assertions held. The numbers are printed either way, so a
// failing run still tells you what the filter did.

#include "../cleona_audio.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SR            16000
#define FRAME         320          // 20 ms @ 16 kHz — production value
#define TOTAL_FRAMES  400          // 8 s: speex needs time to converge
#define MAXDELAY      8000         // 500 ms of delay line

static int failures = 0;

static void check(const char* name, int ok, const char* detail) {
    if (ok) {
        printf("  PASS: %s\n", name);
    } else {
        printf("  FAIL: %s — %s\n", name, detail ? detail : "");
        failures++;
    }
}

// Speech-like far-end: three harmonics with a slow amplitude envelope, plus a
// little noise so the adaptive filter sees a broadband, non-stationary signal
// (a pure tone would let it converge unrealistically well).
static double farend_sample(long n) {
    double t   = (double)n / SR;
    double env = 0.55 + 0.45 * sin(2.0 * M_PI * 2.3 * t);
    double s   = 0.60 * sin(2.0 * M_PI * 220.0 * t)
               + 0.30 * sin(2.0 * M_PI * 640.0 * t)
               + 0.15 * sin(2.0 * M_PI * 1550.0 * t);
    double nse = 0.02 * ((double)rand() / RAND_MAX * 2.0 - 1.0);
    return env * s + nse;
}

// Near-end talker, deliberately unrelated to the far-end signal.
static double nearend_sample(long n) {
    double t   = (double)n / SR;
    double env = 0.5 + 0.5 * sin(2.0 * M_PI * 1.1 * t + 0.7);
    return env * (0.55 * sin(2.0 * M_PI * 300.0 * t)
                + 0.25 * sin(2.0 * M_PI * 900.0 * t));
}

static int16_t clamp16(double v) {
    if (v >  32767.0) return  32767;
    if (v < -32768.0) return -32768;
    return (int16_t)v;
}

static double energy(const int16_t* buf, int n) {
    double e = 0.0;
    for (int i = 0; i < n; i++) e += (double)buf[i] * (double)buf[i];
    return e;
}

// Runs `TOTAL_FRAMES` frames through the real chain.
//   delay_samples : acoustic echo delay; <0 disables the echo entirely
//   echo_gain     : linear attenuation of the echo path
//   with_near     : mix in a near-end talker
// Returns energies of the last 60% of the run (after convergence) via out-params.
static void run_scenario(double delay_samples, double echo_gain, int with_near,
                         double* echo_in_energy, double* residual_energy,
                         double* near_in_energy, double* near_out_energy) {
    cleona_audio_engine_t* e = cleona_audio_create(SR, 1, FRAME, 8);
    if (!e) { fprintf(stderr, "cleona_audio_create failed\n"); exit(1); }

    static double farline[MAXDELAY];
    memset(farline, 0, sizeof(farline));
    long widx = 0;

    int16_t far[FRAME], near[FRAME], out[FRAME], echo_only[FRAME], near_only[FRAME];
    *echo_in_energy = *residual_energy = *near_in_energy = *near_out_energy = 0.0;

    const int settle = (TOTAL_FRAMES * 2) / 5;   // ignore the first 40%
    long n = 0;
    srand(12345);                                // deterministic run

    for (int f = 0; f < TOTAL_FRAMES; f++) {
        for (int i = 0; i < FRAME; i++, n++) {
            double fs = farend_sample(n);
            farline[widx % MAXDELAY] = fs;

            double echo = 0.0;
            if (delay_samples >= 0.0) {
                long ridx = widx - (long)delay_samples;
                if (ridx >= 0) echo = echo_gain * farline[ridx % MAXDELAY];
            }
            double nearv = with_near ? nearend_sample(n) : 0.0;

            far[i]       = clamp16(fs    * 20000.0);
            echo_only[i] = clamp16(echo  * 20000.0);
            near_only[i] = clamp16(nearv * 20000.0);
            near[i]      = clamp16((echo + nearv) * 20000.0);
            widx++;
        }

        if (cleona_audio_process_frame_for_test(e, near, far, out) != 0) {
            fprintf(stderr, "process_frame_for_test failed\n");
            exit(1);
        }

        if (f >= settle) {
            *echo_in_energy  += energy(echo_only, FRAME);
            *residual_energy += energy(out,       FRAME);
            *near_in_energy  += energy(near_only, FRAME);
            *near_out_energy += energy(out,       FRAME);
        }
    }
    cleona_audio_destroy(e);
}

static double db_ratio(double num, double den) {
    if (den <= 0.0) return 0.0;
    return 10.0 * log10((num + 1e-9) / (den + 1e-9));
}

int main(void) {
    printf("=== speexdsp AEC offline measurement (B14) ===\n");
    printf("sample_rate=%d frame=%d (%.0f ms) tail=250 ms frames=%d\n\n",
           SR, FRAME, 1000.0 * FRAME / SR, TOTAL_FRAMES);

    double ein, res, nin, nout;

    // ── 1. FAST path, 20 ms echo delay ───────────────────────────────
    printf("1. Echo at 20 ms (Pixel 8 Pro FAST path)\n");
    run_scenario(0.020 * SR, 0.45, 0, &ein, &res, &nin, &nout);
    double erle20 = db_ratio(ein, res);
    printf("     ERLE = %+.1f dB\n", erle20);
    check("speex attenuates a 20 ms echo by >6 dB", erle20 > 6.0, "no useful cancellation");

    // ── 2. Mixer path, 60 ms echo delay ──────────────────────────────
    printf("2. Echo at 60 ms (mixer path)\n");
    run_scenario(0.060 * SR, 0.45, 0, &ein, &res, &nin, &nout);
    double erle60 = db_ratio(ein, res);
    printf("     ERLE = %+.1f dB\n", erle60);
    check("speex attenuates a 60 ms echo by >6 dB", erle60 > 6.0, "no useful cancellation");

    // ── 3. Beyond the 250 ms tail ────────────────────────────────────
    printf("3. Echo at 300 ms (beyond the 250 ms tail)\n");
    run_scenario(0.300 * SR, 0.45, 0, &ein, &res, &nin, &nout);
    double erle300 = db_ratio(ein, res);
    printf("     ERLE = %+.1f dB\n", erle300);
    check("an echo past the tail is measurably worse than at 20 ms",
          erle300 < erle20, "tail limit not observable");

    // ── 4. Double compensation: near-end speech, NO echo ─────────────
    //
    // This is the decisive scenario. If the platform AEC already removed the
    // echo, this is exactly what speex sees: a reference signal that is loud,
    // and a near-end that contains none of it. A well-behaved canceller must
    // leave the speech alone.
    printf("4. Double compensation — near-end speech, echo already removed\n");
    run_scenario(-1.0, 0.0, 1, &ein, &res, &nin, &nout);
    double loss = db_ratio(nin, nout);
    printf("     near-end attenuation = %+.1f dB (0 = untouched, >0 = speech lost)\n", loss);
    check("speex does not attenuate clean near-end speech by more than 3 dB",
          loss < 3.0, "second canceller damages the near-end signal");

    printf("\n=== Result: %s ===\n", failures == 0 ? "all checks passed" : "FAILURES");
    printf("ERLE 20ms=%+.1f dB  60ms=%+.1f dB  300ms=%+.1f dB  "
           "near-end loss without echo=%+.1f dB\n", erle20, erle60, erle300, loss);
    return failures == 0 ? 0 : 1;
}
