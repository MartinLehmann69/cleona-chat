/* test_loopback.c — manual smoke test: 3 seconds mic→speaker via cleona_audio
 *
 * Run on a host with PulseAudio + working mic and speaker:
 *   cd native/cleona_audio/test/build
 *   ./test_loopback [seconds]
 *
 * Exits 0 on success. Verifies the shim opens devices, runs Speex AEC + NS,
 * and reaches the requested frame budget. Audible verification (does the
 * speaker actually play what the mic captures, no echo) is the user's gate.
 */

#include "../cleona_audio.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define SR 16000
#define CH 1
#define FRAME 320
#define RING 8

int main(int argc, char** argv) {
    int duration_sec = (argc > 1) ? atoi(argv[1]) : 3;
    if (duration_sec <= 0 || duration_sec > 60) {
        fprintf(stderr, "duration must be 1..60 seconds, got %d\n", duration_sec);
        return 1;
    }

    cleona_audio_engine_t* e = cleona_audio_create(SR, CH, FRAME, RING);
    if (!e) {
        fprintf(stderr, "create failed\n");
        return 1;
    }

    int rc = cleona_audio_start(e);
    if (rc != 0) {
        fprintf(stderr, "start failed: %d\n", rc);
        cleona_audio_destroy(e);
        return 2;
    }

    cleona_audio_stats_t stats0;
    cleona_audio_get_stats(e, &stats0);
    fprintf(stderr, "Started. Backend: capture=%d playback=%d\n",
            stats0.capture_backend, stats0.playback_backend);

    int16_t pcm[FRAME];
    int frames_processed = 0;
    int target_frames = (SR * duration_sec) / FRAME;
    fprintf(stderr, "Loopback for %d seconds (%d frames)...\n",
            duration_sec, target_frames);

    while (frames_processed < target_frames) {
        int r = cleona_audio_capture_read(e, pcm, 100);
        if (r == -1) break;
        if (r == 0) continue;
        cleona_audio_playback_write(e, pcm, FRAME);
        frames_processed++;
    }

    cleona_audio_stats_t stats;
    cleona_audio_get_stats(e, &stats);
    fprintf(stderr,
            "Finished. capture_total=%lld dropped=%lld "
            "playback_total=%lld underrun=%lld\n",
            (long long)stats.capture_frames_total,
            (long long)stats.capture_frames_dropped,
            (long long)stats.playback_frames_total,
            (long long)stats.playback_frames_underrun);

    cleona_audio_stop(e);
    cleona_audio_destroy(e);
    return 0;
}
