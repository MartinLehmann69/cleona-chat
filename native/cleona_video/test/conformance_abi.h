/* conformance_abi.h — how the video conformance harness reaches a backend.
 *
 * Work package: docs/SPEC_VOICE_VIDEO_REWORK.md V0.4.
 *
 * Same construction as native/cleona_voice/test/conformance_abi.h, and for the
 * same reason: this harness is the acceptance criterion of V1.13-V1.16 (Linux,
 * Android, Apple and Windows video backends), so it must be able to certify a
 * backend it knows nothing about. Every call goes through the table CVID; no
 * line of conformance.c ever names a cleona_video_* symbol.
 *
 *   LINK MODE   (default)                 CLEONA_CONFORMANCE_LOAD undefined
 *       The table is filled with the linked symbols. Required where the backend
 *       is a static archive — on iOS all native code is merged statically and
 *       reached through DynamicLibrary.process(), so there is no library to
 *       dlopen.
 *
 *   LOAD MODE                             -DCLEONA_CONFORMANCE_LOAD
 *       dlopen()/GetProcAddress() on a path from the command line or from
 *       CLEONA_VIDEO_LIB. One prebuilt harness, any backend, no rebuild.
 *
 * The symbol set is exactly the twelve entry points of cleona_video.h.
 */

#ifndef CLEONA_VIDEO_CONFORMANCE_ABI_H
#define CLEONA_VIDEO_CONFORMANCE_ABI_H

#include <stddef.h>
#include <stdint.h>

#include "../cleona_video.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    cleona_video_session_t* (*open)(const cleona_video_config_t* cfg,
                                    cleona_video_config_t* out_negotiated);
    int32_t (*reconfigure)(cleona_video_session_t* s,
                           const cleona_video_config_t* cfg,
                           cleona_video_config_t* out_negotiated);
    int32_t (*start)(cleona_video_session_t* s);
    void    (*stop)(cleona_video_session_t* s);
    void    (*close)(cleona_video_session_t* s);
    int32_t (*read_encoded)(cleona_video_session_t* s, uint8_t* buf,
                            int32_t buf_cap, int32_t* out_size,
                            int32_t* out_flags, int64_t* out_pts_us,
                            int32_t timeout_ms);
    int32_t (*submit_encoded)(cleona_video_session_t* s, const uint8_t* data,
                              int32_t size, int32_t flags);
    int32_t (*get_texture_id)(cleona_video_session_t* s, int64_t* out_id);
    int32_t (*request_keyframe)(cleona_video_session_t* s);
    void    (*set_capture_enabled)(cleona_video_session_t* s, int32_t on);
    int32_t (*switch_camera)(cleona_video_session_t* s);
    void    (*get_report)(cleona_video_session_t* s, cleona_video_report_t* out);
} cleona_video_vtable_t;

/* The one table the harness calls through. Valid only after cvidbind_init(). */
extern cleona_video_vtable_t CVID;

/* Fills CVID. See the voice counterpart for the argument semantics; the
 * environment variable is CLEONA_VIDEO_LIB. Returns 0 on success. */
int cvidbind_init(const char* lib_path, char* err, size_t errcap);

const char* cvidbind_mode(void);     /* "link" or "load" */
const char* cvidbind_library(void);  /* loaded path, "" in link mode */
void cvidbind_shutdown(void);

#ifdef __cplusplus
}
#endif

#endif /* CLEONA_VIDEO_CONFORMANCE_ABI_H */
