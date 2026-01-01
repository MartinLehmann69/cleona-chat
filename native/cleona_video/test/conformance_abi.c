/* conformance_abi.c — the two ways to bind a video backend. See the header. */

/* dlfcn.h declares dlopen/dlsym behind a POSIX feature-test macro; a strict
 * -std=c11 build (CMake selects gnu11 by default, a device toolchain may not)
 * would hide them. Must come before the first system header. */
#if !defined(_WIN32) && !defined(_POSIX_C_SOURCE)
  #define _POSIX_C_SOURCE 200809L
#endif

#include "conformance_abi.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

cleona_video_vtable_t CVID;

static char g_library[1024] = "";

/* ==========================================================================
 * LOAD MODE
 * ========================================================================== */
#if defined(CLEONA_CONFORMANCE_LOAD)

#if defined(_WIN32)
  #define WIN32_LEAN_AND_MEAN
  #include <windows.h>
  static HMODULE g_handle = NULL;
  static void* sym_lookup(const char* name) {
      FARPROC p = GetProcAddress(g_handle, name);
      void* v = NULL;
      memcpy(&v, &p, sizeof(v));
      return v;
  }
  static void handle_close(void) { if (g_handle) FreeLibrary(g_handle); g_handle = NULL; }
#else
  #include <dlfcn.h>
  static void* g_handle = NULL;
  static void* sym_lookup(const char* name) { return dlsym(g_handle, name); }
  static void handle_close(void) { if (g_handle) dlclose(g_handle); g_handle = NULL; }
#endif

/* The value is copied, not cast: ISO C has no conversion from an object pointer
 * to a function pointer, and this package does not silence warnings. */
static int bind_one(void* slot, const char* name, char* err, size_t errcap) {
    void* p = sym_lookup(name);
    if (!p) {
        snprintf(err, errcap, "symbol not found in backend library: %s", name);
        return -1;
    }
    memcpy(slot, &p, sizeof(void*));
    return 0;
}

int cvidbind_init(const char* lib_path, char* err, size_t errcap) {
    const char* path = (lib_path && lib_path[0]) ? lib_path : getenv("CLEONA_VIDEO_LIB");
    if (!path || !path[0]) {
        snprintf(err, errcap,
                 "no backend library given. Pass it as an argument or set "
                 "CLEONA_VIDEO_LIB. This harness never guesses which library it "
                 "certified.");
        return -1;
    }

#if defined(_WIN32)
    g_handle = LoadLibraryA(path);
    if (!g_handle) {
        snprintf(err, errcap, "LoadLibrary(%s) failed, GetLastError=%lu",
                 path, (unsigned long)GetLastError());
        return -1;
    }
#else
    g_handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!g_handle) {
        const char* e = dlerror();
        snprintf(err, errcap, "dlopen(%s) failed: %s", path, e ? e : "unknown");
        return -1;
    }
#endif

    snprintf(g_library, sizeof(g_library), "%s", path);

    if (bind_one(&CVID.open,                "cleona_video_open",                err, errcap) ||
        bind_one(&CVID.reconfigure,         "cleona_video_reconfigure",         err, errcap) ||
        bind_one(&CVID.start,               "cleona_video_start",               err, errcap) ||
        bind_one(&CVID.stop,                "cleona_video_stop",                err, errcap) ||
        bind_one(&CVID.close,               "cleona_video_close",               err, errcap) ||
        bind_one(&CVID.read_encoded,        "cleona_video_read_encoded",        err, errcap) ||
        bind_one(&CVID.submit_encoded,      "cleona_video_submit_encoded",      err, errcap) ||
        bind_one(&CVID.get_texture_id,      "cleona_video_get_texture_id",      err, errcap) ||
        bind_one(&CVID.request_keyframe,    "cleona_video_request_keyframe",    err, errcap) ||
        bind_one(&CVID.set_capture_enabled, "cleona_video_set_capture_enabled", err, errcap) ||
        bind_one(&CVID.switch_camera,       "cleona_video_switch_camera",       err, errcap) ||
        bind_one(&CVID.get_report,          "cleona_video_get_report",          err, errcap)) {
        handle_close();
        return -1;
    }
    return 0;
}

const char* cvidbind_mode(void)    { return "load"; }
const char* cvidbind_library(void) { return g_library; }
void cvidbind_shutdown(void)       { handle_close(); }

/* ==========================================================================
 * LINK MODE
 * ========================================================================== */
#else

int cvidbind_init(const char* lib_path, char* err, size_t errcap) {
    if (lib_path && lib_path[0]) {
        snprintf(err, errcap,
                 "this harness was built in LINK mode and cannot load '%s'. "
                 "Rebuild with -DCLEONA_CONFORMANCE_LOAD to get the loader "
                 "variant, or link the harness against your backend.", lib_path);
        return -1;
    }
    CVID.open                = cleona_video_open;
    CVID.reconfigure         = cleona_video_reconfigure;
    CVID.start               = cleona_video_start;
    CVID.stop                = cleona_video_stop;
    CVID.close               = cleona_video_close;
    CVID.read_encoded        = cleona_video_read_encoded;
    CVID.submit_encoded      = cleona_video_submit_encoded;
    CVID.get_texture_id      = cleona_video_get_texture_id;
    CVID.request_keyframe    = cleona_video_request_keyframe;
    CVID.set_capture_enabled = cleona_video_set_capture_enabled;
    CVID.switch_camera       = cleona_video_switch_camera;
    CVID.get_report          = cleona_video_get_report;
    return 0;
}

const char* cvidbind_mode(void)    { return "link"; }
const char* cvidbind_library(void) { return g_library; }
void cvidbind_shutdown(void)       { }

#endif
