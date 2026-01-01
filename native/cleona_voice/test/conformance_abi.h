/* conformance_abi.h — how the conformance harness reaches a backend.
 *
 * Work package: docs/SPEC_VOICE_VIDEO_REWORK.md V0.4.
 *
 * WHY AN INDIRECTION AT ALL
 * -------------------------
 * The conformance test in this directory is the acceptance criterion of nine
 * other work packages (V1.1-V1.4 voice, V1.13-V1.16 video). It therefore has to
 * run against a backend it knows nothing about: PipeWire, an Android HAL,
 * Apple's VoiceProcessingIO, WASAPI, or the hardware-free mock. If the test
 * called cleona_voice_open() directly, the choice of backend would be made at
 * link time by whoever built the binary, and a platform package would have to
 * copy or fork the test to point it at its own library.
 *
 * Everything the harness calls therefore goes through one function table, CV.
 * There are exactly two ways to fill it, selected at BUILD time:
 *
 *   LINK MODE   (default)                 CLEONA_CONFORMANCE_LOAD undefined
 *       The table is filled with the symbols the executable was linked
 *       against. Use this when the backend is a static library — iOS is the
 *       case that forces this mode to exist, because a shipped iOS build has
 *       no loadable .dylib of its own (all native code is merged statically and
 *       reached through DynamicLibrary.process()).
 *
 *   LOAD MODE                             -DCLEONA_CONFORMANCE_LOAD
 *       The table is filled with dlopen()/GetProcAddress() from a path given on
 *       the command line or in an environment variable. Use this on Linux,
 *       Android, Windows and macOS: one prebuilt harness binary can then be
 *       pointed at any backend without rebuilding anything.
 *
 * The harness source is identical in both modes. Nothing in conformance.c ever
 * names a cleona_voice_* symbol, which is also what keeps the test honest: it
 * cannot accidentally reach past the ABI into a particular implementation.
 *
 * SYMBOL SET
 * ----------
 * Exactly the twelve entry points of cleona_voice.h, no more. A backend that
 * exports fewer cannot be tested and cannot ship — the same twelve are the ones
 * the Dart binding looks up (see native/cleona_voice/BUILD_REQUEST.md §1).
 */

#ifndef CLEONA_VOICE_CONFORMANCE_ABI_H
#define CLEONA_VOICE_CONFORMANCE_ABI_H

#include <stddef.h>
#include <stdint.h>

#include "../cleona_voice.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    cleona_voice_session_t* (*open)(int32_t rate_hint,
                                    cleona_voice_format_t* out_format);
    int32_t (*start)(cleona_voice_session_t* s);
    void    (*stop)(cleona_voice_session_t* s);
    void    (*close)(cleona_voice_session_t* s);
    int32_t (*capture_read)(cleona_voice_session_t* s, int16_t* out,
                            int32_t timeout_ms);
    int32_t (*playback_write)(cleona_voice_session_t* s, const int16_t* pcm,
                              int32_t frame_samples);
    void    (*set_mic_muted)(cleona_voice_session_t* s, int32_t muted);
    void    (*set_output_muted)(cleona_voice_session_t* s, int32_t muted);
    int32_t (*set_route)(cleona_voice_session_t* s, int32_t route);
    int32_t (*get_routes)(cleona_voice_session_t* s, int32_t* out_mask,
                          int32_t* out_active);
    int32_t (*poll_event)(cleona_voice_session_t* s, int32_t* out_event,
                          int32_t* out_arg);
    void    (*get_report)(cleona_voice_session_t* s, cleona_voice_report_t* out);
} cleona_voice_vtable_t;

/* The one table the harness calls through. Valid only after cvbind_init(). */
extern cleona_voice_vtable_t CV;

/* Fills CV.
 *
 * lib_path  LOAD MODE: the backend library to open. NULL or "" means "take it
 *                      from the environment variable CLEONA_VOICE_LIB"; if that
 *                      is empty too, binding fails with a message rather than
 *                      silently falling back to whatever the loader would pick
 *                      up — a conformance run must always be able to name the
 *                      artefact it certified.
 *           LINK MODE: must be NULL or ""; a path is rejected, because honouring
 *                      it would report a result for a library that was never
 *                      loaded.
 * err/errcap  receives a human-readable reason on failure.
 *
 * Returns 0 on success, -1 on failure. */
int cvbind_init(const char* lib_path, char* err, size_t errcap);

/* "link" or "load" — goes into the machine-readable report so two runs of the
 * same harness can never be confused for one another. */
const char* cvbind_mode(void);

/* The library that was loaded, or "" in link mode. */
const char* cvbind_library(void);

/* Releases the loaded library. No-op in link mode. Called after the last ABI
 * call, never before — unloading a backend that still owns a session is a
 * crash, not a test result. */
void cvbind_shutdown(void);

#ifdef __cplusplus
}
#endif

#endif /* CLEONA_VOICE_CONFORMANCE_ABI_H */
