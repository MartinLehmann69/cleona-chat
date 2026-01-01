/* cleona_voice_apple_live.h — liveness registry for the OS route-change
 * callbacks. Included by EXACTLY ONE translation unit per build
 * (cleona_voice_apple_ios.m or cleona_voice_apple_mac.c), which is why the
 * helpers are file-static.
 *
 * Work package: docs/SPEC_VOICE_VIDEO_REWORK.md V1.3.
 *
 * ---------------------------------------------------------------------------
 * THE PROBLEM THIS SOLVES
 * ---------------------------------------------------------------------------
 * Both OS route-change mechanisms can have a notification in flight while the
 * session is being torn down:
 *
 *   iOS    -[NSNotificationCenter removeObserver:] stops FUTURE deliveries. A
 *          block that is already executing on the posting thread keeps running.
 *   macOS  AudioObjectRemovePropertyListener() likewise does not join an
 *          already-dispatched listener invocation.
 *
 * The callback dereferences the platform object and, through it, the
 * cleona_voice_session_t. cleona_voice_close() frees both. Without
 * synchronisation that is a use-after-free at the end of every call — the kind
 * of defect that is found in the field, not on a branch that (per
 * BUILD_REQUEST_V1.3.md) has no Apple hardware in the loop at all.
 *
 * ---------------------------------------------------------------------------
 * HOW IT IS CLOSED
 * ---------------------------------------------------------------------------
 * One process-wide mutex plus a table of live platform pointers.
 *
 *   callback:  lock -> is `p` still in the table? -> if no, unlock and return
 *              WITHOUT dereferencing it; if yes, do the work, then unlock.
 *   teardown:  remove the OS listener -> lock -> drop `p` from the table ->
 *              unlock -> free.
 *
 * The pointer is only COMPARED before the liveness check, never dereferenced,
 * so a stale pointer is harmless. A callback that passed the check completes
 * before teardown can take the lock, and therefore before anything is freed.
 * The mutex is static storage and outlives every session, so it is always a
 * valid thing to lock.
 *
 * The table is fixed-size on purpose: a voice session is per call, and Cleona
 * has no path that holds more than a handful open (the conformance harness
 * opens a second one alongside the first — cleona_voice.h "N3"). Registration
 * failing when the table is full is reported as an error rather than growing a
 * heap structure inside a teardown path.
 */

#ifndef CLEONA_VOICE_APPLE_LIVE_H
#define CLEONA_VOICE_APPLE_LIVE_H

#include <pthread.h>
#include <stddef.h>

#define CVA_LIVE_MAX 8

static pthread_mutex_t cva_live_lock = PTHREAD_MUTEX_INITIALIZER;
static void* cva_live_tab[CVA_LIVE_MAX];

/* Returns 1 on success, 0 when the table is full. */
static int cva_live_add(void* p) {
    int ok = 0;
    pthread_mutex_lock(&cva_live_lock);
    for (int i = 0; i < CVA_LIVE_MAX; i++) {
        if (cva_live_tab[i] == NULL) { cva_live_tab[i] = p; ok = 1; break; }
    }
    pthread_mutex_unlock(&cva_live_lock);
    return ok;
}

static void cva_live_remove(void* p) {
    pthread_mutex_lock(&cva_live_lock);
    for (int i = 0; i < CVA_LIVE_MAX; i++) {
        if (cva_live_tab[i] == p) { cva_live_tab[i] = NULL; break; }
    }
    pthread_mutex_unlock(&cva_live_lock);
}

/* Caller must hold cva_live_lock. */
static int cva_live_contains_locked(void* p) {
    for (int i = 0; i < CVA_LIVE_MAX; i++) {
        if (cva_live_tab[i] == p) return 1;
    }
    return 0;
}

#endif /* CLEONA_VOICE_APPLE_LIVE_H */
