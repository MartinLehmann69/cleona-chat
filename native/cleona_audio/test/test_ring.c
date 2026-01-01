#include "../cleona_audio_ring.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>

static void test_basic_roundtrip(void) {
    cleona_ring_t ring;
    assert(cleona_ring_init(&ring, 4, 16) == 0);

    uint8_t in[16] = "hello-frame-001";
    uint8_t out[16] = {0};

    assert(cleona_ring_try_write(&ring, in) == 1);
    assert(cleona_ring_try_read(&ring, out) == 1);
    assert(memcmp(in, out, 16) == 0);

    cleona_ring_destroy(&ring);
    printf("PASS: basic_roundtrip\n");
}

static void test_overflow_drops(void) {
    cleona_ring_t ring;
    assert(cleona_ring_init(&ring, 2, 4) == 0);
    uint8_t a[4] = "AAAA", b[4] = "BBBB", c[4] = "CCCC";

    assert(cleona_ring_try_write(&ring, a) == 1);
    assert(cleona_ring_try_write(&ring, b) == 1);
    assert(cleona_ring_try_write(&ring, c) == 0); // full → drop
    int64_t dropped = atomic_load(&ring.frames_dropped);
    assert(dropped == 1);

    cleona_ring_destroy(&ring);
    printf("PASS: overflow_drops\n");
}

static void test_blocking_read_timeout(void) {
    cleona_ring_t ring;
    assert(cleona_ring_init(&ring, 4, 4) == 0);
    uint8_t out[4] = {0};

    int rc = cleona_ring_read(&ring, out, 50); // 50ms timeout, empty
    assert(rc == 0);

    cleona_ring_destroy(&ring);
    printf("PASS: blocking_read_timeout\n");
}

static void* writer_thread(void* arg) {
    cleona_ring_t* ring = (cleona_ring_t*)arg;
    usleep(20000); // 20ms delay
    uint8_t frame[4] = "DATA";
    cleona_ring_try_write(ring, frame);
    return NULL;
}

static void test_blocking_read_wakeup(void) {
    cleona_ring_t ring;
    assert(cleona_ring_init(&ring, 4, 4) == 0);

    pthread_t tid;
    pthread_create(&tid, NULL, writer_thread, &ring);

    uint8_t out[4] = {0};
    int rc = cleona_ring_read(&ring, out, 200); // should wake up after ~20ms
    assert(rc == 1);
    assert(memcmp(out, "DATA", 4) == 0);

    pthread_join(tid, NULL);
    cleona_ring_destroy(&ring);
    printf("PASS: blocking_read_wakeup\n");
}

static void* close_thread(void* arg) {
    cleona_ring_close((cleona_ring_t*)arg);
    return NULL;
}

static void test_close_aborts_read(void) {
    cleona_ring_t ring;
    assert(cleona_ring_init(&ring, 4, 4) == 0);

    pthread_t tid;
    pthread_create(&tid, NULL, close_thread, &ring);

    uint8_t out[4] = {0};
    int rc = cleona_ring_read(&ring, out, 5000);
    assert(rc == -1); // closed

    pthread_join(tid, NULL);
    cleona_ring_destroy(&ring);
    printf("PASS: close_aborts_read\n");
}

static void test_capacity_one(void) {
    cleona_ring_t ring;
    assert(cleona_ring_init(&ring, 1, 8) == 0);

    uint8_t a[8] = "ALPHA000";
    uint8_t b[8] = "BRAVO000";
    uint8_t out[8] = {0};

    // First write fills the ring
    assert(cleona_ring_try_write(&ring, a) == 1);
    // Second write fails (full)
    assert(cleona_ring_try_write(&ring, b) == 0);

    // Read drains
    assert(cleona_ring_try_read(&ring, out) == 1);
    assert(memcmp(out, "ALPHA000", 8) == 0);
    // Empty
    assert(cleona_ring_try_read(&ring, out) == 0);

    // Now writes succeed again
    assert(cleona_ring_try_write(&ring, b) == 1);
    assert(cleona_ring_try_read(&ring, out) == 1);
    assert(memcmp(out, "BRAVO000", 8) == 0);

    cleona_ring_destroy(&ring);
    printf("PASS: capacity_one\n");
}

int main(void) {
    test_basic_roundtrip();
    test_capacity_one();
    test_overflow_drops();
    test_blocking_read_timeout();
    test_blocking_read_wakeup();
    test_close_aborts_read();
    printf("\nAll ring-buffer tests passed.\n");
    return 0;
}
