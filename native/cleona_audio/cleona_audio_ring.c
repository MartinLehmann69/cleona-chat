#define _POSIX_C_SOURCE 200809L
#include "cleona_audio_ring.h"
#include <stdlib.h>
#include <string.h>

#ifndef _WIN32
#  include <time.h>
#  include <errno.h>
#endif

/* Platform-portable mutex + cond-var primitives. Win32 condition variables
 * have a different lifecycle (no destroy needed) and use relative timeouts;
 * the public ring API hides these differences behind cleona_ring_*. */

int cleona_ring_init(cleona_ring_t* ring, int32_t capacity, int32_t frame_bytes) {
    ring->buffer = (uint8_t*)calloc((size_t)capacity * frame_bytes, 1);
    if (!ring->buffer) return -1;
    ring->capacity = capacity;
    ring->frame_bytes = frame_bytes;
    atomic_store(&ring->write_idx, 0);
    atomic_store(&ring->read_idx, 0);
    atomic_store(&ring->closed, 0);
    atomic_store(&ring->frames_dropped, 0);
#ifdef _WIN32
    InitializeCriticalSection(&ring->mutex);
    InitializeConditionVariable(&ring->cond);
#else
    if (pthread_mutex_init(&ring->mutex, NULL) != 0) {
        free(ring->buffer); ring->buffer = NULL; return -2;
    }
    if (pthread_cond_init(&ring->cond, NULL) != 0) {
        pthread_mutex_destroy(&ring->mutex);
        free(ring->buffer); ring->buffer = NULL; return -3;
    }
#endif
    return 0;
}

void cleona_ring_destroy(cleona_ring_t* ring) {
    if (!ring) return;
#ifdef _WIN32
    DeleteCriticalSection(&ring->mutex);
    /* CONDITION_VARIABLE has no destroy on Win32 */
#else
    pthread_cond_destroy(&ring->cond);
    pthread_mutex_destroy(&ring->mutex);
#endif
    free(ring->buffer);
    ring->buffer = NULL;
}

void cleona_ring_close(cleona_ring_t* ring) {
    atomic_store(&ring->closed, 1);
#ifdef _WIN32
    EnterCriticalSection(&ring->mutex);
    WakeAllConditionVariable(&ring->cond);
    LeaveCriticalSection(&ring->mutex);
#else
    pthread_mutex_lock(&ring->mutex);
    pthread_cond_broadcast(&ring->cond);
    pthread_mutex_unlock(&ring->mutex);
#endif
}

int cleona_ring_try_write(cleona_ring_t* ring, const void* frame) {
    int32_t w = atomic_load(&ring->write_idx);
    int32_t r = atomic_load(&ring->read_idx);
    if (w - r >= ring->capacity) {
        atomic_fetch_add(&ring->frames_dropped, 1);
        return 0; // full
    }
    int32_t slot = w % ring->capacity;
    memcpy(ring->buffer + (size_t)slot * ring->frame_bytes, frame, ring->frame_bytes);
    atomic_store(&ring->write_idx, w + 1);
    // Signal consumer (with mutex to avoid lost-wakeup)
#ifdef _WIN32
    EnterCriticalSection(&ring->mutex);
    WakeConditionVariable(&ring->cond);
    LeaveCriticalSection(&ring->mutex);
#else
    pthread_mutex_lock(&ring->mutex);
    pthread_cond_signal(&ring->cond);
    pthread_mutex_unlock(&ring->mutex);
#endif
    return 1;
}

int cleona_ring_try_read(cleona_ring_t* ring, void* out_frame) {
    int32_t w = atomic_load(&ring->write_idx);
    int32_t r = atomic_load(&ring->read_idx);
    if (r >= w) return 0; // empty
    int32_t slot = r % ring->capacity;
    memcpy(out_frame, ring->buffer + (size_t)slot * ring->frame_bytes, ring->frame_bytes);
    atomic_store(&ring->read_idx, r + 1);
    return 1;
}

int cleona_ring_read(cleona_ring_t* ring, void* out_frame, int32_t timeout_ms) {
    if (atomic_load(&ring->closed)) return -1;
    if (cleona_ring_try_read(ring, out_frame)) return 1;

#ifdef _WIN32
    /* Win32 SleepConditionVariableCS uses RELATIVE ms timeouts. We compute the
     * deadline tick once and shrink the per-iteration timeout on spurious
     * wakeups so total wait approximates the requested budget. */
    DWORD remaining = (timeout_ms < 0) ? INFINITE : (DWORD)timeout_ms;
    ULONGLONG start = GetTickCount64();
    EnterCriticalSection(&ring->mutex);
    int rc = 0;
    while (!atomic_load(&ring->closed)) {
        if (cleona_ring_try_read(ring, out_frame)) { rc = 1; break; }
        BOOL ok = SleepConditionVariableCS(&ring->cond, &ring->mutex, remaining);
        if (!ok) { /* timeout or error */ rc = 0; break; }
        if (timeout_ms >= 0) {
            ULONGLONG elapsed = GetTickCount64() - start;
            if (elapsed >= (ULONGLONG)timeout_ms) { rc = 0; break; }
            remaining = (DWORD)((ULONGLONG)timeout_ms - elapsed);
        }
    }
    LeaveCriticalSection(&ring->mutex);
#else
    /* POSIX pthread_cond_timedwait uses absolute timespec deadlines. */
    struct timespec deadline;
    clock_gettime(CLOCK_REALTIME, &deadline);
    deadline.tv_sec  += timeout_ms / 1000;
    deadline.tv_nsec += (long)(timeout_ms % 1000) * 1000000L;
    if (deadline.tv_nsec >= 1000000000L) {
        deadline.tv_sec  += 1;
        deadline.tv_nsec -= 1000000000L;
    }

    pthread_mutex_lock(&ring->mutex);
    int rc = 0;
    while (!atomic_load(&ring->closed)) {
        if (cleona_ring_try_read(ring, out_frame)) { rc = 1; break; }
        int wait_rc = pthread_cond_timedwait(&ring->cond, &ring->mutex, &deadline);
        if (wait_rc == ETIMEDOUT) { rc = 0; break; }
    }
    pthread_mutex_unlock(&ring->mutex);
#endif

    // Frame already consumed → keep it, even on concurrent close.
    if (rc == 1) return 1;
    if (atomic_load(&ring->closed)) return -1;
    return rc;
}
