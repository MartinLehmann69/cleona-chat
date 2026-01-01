/* conformance_abi.c — the two ways to bind a backend. See conformance_abi.h. */

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

cleona_voice_vtable_t CV;

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

/* dlsym returns an object pointer that POSIX guarantees is usable as a function
 * pointer; ISO C has no conversion for that, so the value is copied rather than
 * cast. A cast would make -Wpedantic complain, and silencing a warning is not
 * something this package does. */
static int bind_one(void* slot, const char* name, char* err, size_t errcap) {
    void* p = sym_lookup(name);
    if (!p) {
        snprintf(err, errcap, "symbol not found in backend library: %s", name);
        return -1;
    }
    memcpy(slot, &p, sizeof(void*));
    return 0;
}

int cvbind_init(const char* lib_path, char* err, size_t errcap) {
    const char* path = (lib_path && lib_path[0]) ? lib_path : getenv("CLEONA_VOICE_LIB");
    if (!path || !path[0]) {
        snprintf(err, errcap,
                 "no backend library given. Pass it as an argument or set "
                 "CLEONA_VOICE_LIB. This harness never guesses which library it "
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
    /* RTLD_NOW so a backend missing a dependency fails here with a readable
     * message instead of half-way through check 3. RTLD_LOCAL so two backends
     * exporting the same ABI can never bleed into each other. */
    g_handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!g_handle) {
        const char* e = dlerror();
        snprintf(err, errcap, "dlopen(%s) failed: %s", path, e ? e : "unknown");
        return -1;
    }
#endif

    snprintf(g_library, sizeof(g_library), "%s", path);

    if (bind_one(&CV.open,             "cleona_voice_open",             err, errcap) ||
        bind_one(&CV.start,            "cleona_voice_start",            err, errcap) ||
        bind_one(&CV.stop,             "cleona_voice_stop",             err, errcap) ||
        bind_one(&CV.close,            "cleona_voice_close",            err, errcap) ||
        bind_one(&CV.capture_read,     "cleona_voice_capture_read",     err, errcap) ||
        bind_one(&CV.playback_write,   "cleona_voice_playback_write",   err, errcap) ||
        bind_one(&CV.set_mic_muted,    "cleona_voice_set_mic_muted",    err, errcap) ||
        bind_one(&CV.set_output_muted, "cleona_voice_set_output_muted", err, errcap) ||
        bind_one(&CV.set_route,        "cleona_voice_set_route",        err, errcap) ||
        bind_one(&CV.get_routes,       "cleona_voice_get_routes",       err, errcap) ||
        bind_one(&CV.poll_event,       "cleona_voice_poll_event",       err, errcap) ||
        bind_one(&CV.get_report,       "cleona_voice_get_report",       err, errcap)) {
        handle_close();
        return -1;
    }
    return 0;
}

const char* cvbind_mode(void)    { return "load"; }
const char* cvbind_library(void) { return g_library; }
void cvbind_shutdown(void)       { handle_close(); }

/* ==========================================================================
 * LINK MODE
 * ========================================================================== */
#else

int cvbind_init(const char* lib_path, char* err, size_t errcap) {
    if (lib_path && lib_path[0]) {
        snprintf(err, errcap,
                 "this harness was built in LINK mode and cannot load '%s'. "
                 "Rebuild with -DCLEONA_CONFORMANCE_LOAD to get the loader "
                 "variant, or link the harness against your backend.", lib_path);
        return -1;
    }
    CV.open             = cleona_voice_open;
    CV.start            = cleona_voice_start;
    CV.stop             = cleona_voice_stop;
    CV.close            = cleona_voice_close;
    CV.capture_read     = cleona_voice_capture_read;
    CV.playback_write   = cleona_voice_playback_write;
    CV.set_mic_muted    = cleona_voice_set_mic_muted;
    CV.set_output_muted = cleona_voice_set_output_muted;
    CV.set_route        = cleona_voice_set_route;
    CV.get_routes       = cleona_voice_get_routes;
    CV.poll_event       = cleona_voice_poll_event;
    CV.get_report       = cleona_voice_get_report;
    return 0;
}

const char* cvbind_mode(void)    { return "link"; }
const char* cvbind_library(void) { return g_library; }
void cvbind_shutdown(void)       { }

#endif
