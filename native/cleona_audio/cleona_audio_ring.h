#ifndef CLEONA_AUDIO_RING_H
#define CLEONA_AUDIO_RING_H

#include <stdint.h>
#include <stddef.h>
#include <stdatomic.h>

#ifdef _WIN32
#  define WIN32_LEAN_AND_MEAN
#  include <windows.h>
   typedef CRITICAL_SECTION    cleona_mutex_t;
   typedef CONDITION_VARIABLE  cleona_cond_t;
#else
#  include <pthread.h>
   typedef pthread_mutex_t cleona_mutex_t;
   typedef pthread_cond_t  cleona_cond_t;
#endif

// SPSC ring of fixed-size frames (bytes per frame configured at init).
// Producer writes via try_write (non-blocking). Consumer reads via try_read.
// Cond-var on consumer side for wake-up.
typedef struct cleona_ring {
    uint8_t* buffer;           // capacity * frame_bytes
    int32_t capacity;          // power of 2 ideally, but not enforced
    int32_t frame_bytes;
    _Atomic int32_t write_idx; // monotonically increasing
    _Atomic int32_t read_idx;  // monotonically increasing
    cleona_mutex_t mutex;
    cleona_cond_t  cond;
    _Atomic int32_t closed;    // 1 = stopped, no more reads/writes
    _Atomic int64_t frames_dropped; // overflow counter (writer side)
} cleona_ring_t;

int  cleona_ring_init(cleona_ring_t* ring, int32_t capacity, int32_t frame_bytes);
void cleona_ring_destroy(cleona_ring_t* ring);
void cleona_ring_close(cleona_ring_t* ring); // wake all waiters

// Returns 1 on success, 0 if ring full (frame dropped — counter incremented).
// Non-blocking, safe from realtime audio thread.
int  cleona_ring_try_write(cleona_ring_t* ring, const void* frame);

// Returns 1 = got frame, 0 = timeout, -1 = closed.
// Blocks up to timeout_ms on cond-var.
int  cleona_ring_read(cleona_ring_t* ring, void* out_frame, int32_t timeout_ms);

// Returns 1 if frame consumed without blocking, 0 if empty.
int  cleona_ring_try_read(cleona_ring_t* ring, void* out_frame);

#endif
