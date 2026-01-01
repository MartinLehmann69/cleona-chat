/* cleona_voice_android.c — the Android backend of the cleona_voice ABI.
 *
 * Work package: docs/SPEC_VOICE_VIDEO_REWORK.md V1.2.
 * Contract:     native/cleona_voice/cleona_voice.h (frozen).
 * Architecture: Cleona_Chat_Architecture_v3_0.md §10.4 (normative).
 *
 * ---------------------------------------------------------------------------
 * WHAT THIS FILE IS AND IS NOT
 * ---------------------------------------------------------------------------
 * It is a JNI facade and nothing else. Every audio decision — rate negotiation,
 * frame assembly, effect attachment, routing, the verification report — lives in
 * android/app/src/main/kotlin/chat/cleona/cleona/VoiceSession.kt, because §10.4
 * makes the Java API mandatory on Android: only `AudioRecord` exposes an audio
 * session id, and only with a session id can AEC/NS/AGC be attached AND read
 * back. A native audio path (AAudio/OpenSL) cannot produce the verification
 * report this ABI requires, which is defect 5 of the superseded stack.
 *
 * So there is deliberately no ring buffer, no resampler and no DSP here. Adding
 * any would recreate the two-clock arrangement I2 exists to forbid.
 *
 * ---------------------------------------------------------------------------
 * HOW THE JavaVM GETS HERE — READ BEFORE DEBUGGING "ERR_BACKEND ON OPEN"
 * ---------------------------------------------------------------------------
 * `JNI_OnLoad` is called by ART from `System.loadLibrary`, and only from there.
 * Dart's `DynamicLibrary.open()` calls plain `dlopen()`, which does NOT run
 * `JNI_OnLoad`. A process in which only Dart ever touched this library therefore
 * has no `JavaVM*`, and every entry point below fails cleanly with
 * CLEONA_VOICE_ERR_BACKEND instead of dereferencing NULL.
 *
 * The fix is one call on the Java side during app start:
 *
 *     VoiceSession.install(applicationContext)
 *
 * which loads the library through the runtime and supplies the Context that
 * AudioManager needs. `MainActivity.kt` belongs to work package V1.10, so V1.2
 * asks for that line rather than writing it — BUILD_REQUEST_V1.2.md §2.
 *
 * ---------------------------------------------------------------------------
 * ALLOCATION ON THE 50 Hz PATH
 * ---------------------------------------------------------------------------
 * `capture_read` and `playback_write` run 50 times a second per direction and
 * allocate nothing: the frame crosses the boundary through two direct
 * ByteBuffers allocated once per session, whose addresses are cached here. The
 * cold paths (routes, events, report) use PushLocalFrame/PopLocalFrame so that
 * their short-lived arrays cannot accumulate as local references on a long-lived
 * attached thread.
 */

#include <jni.h>
#include <pthread.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <android/log.h>

#include "../cleona_voice.h"

#define TAG "CleonaVoice"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN,  TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  TAG, __VA_ARGS__)

#define VOICE_CLASS "chat/cleona/cleona/VoiceSession"

/* ==========================================================================
 * Report marshalling width
 * ==========================================================================
 * The report crosses the JNI boundary as one int array plus one long array, in
 * cleona_voice_report_t's declaration order. Note what this is NOT: there is no
 * byte offset anywhere in this file. Every field is written through its struct
 * member, so the compiler owns the layout and erratum E6a's growth from 72 to
 * 80 bytes needed no arithmetic to be pulled along.
 *
 * What the two numbers below DO duplicate is the field COUNT, and that can
 * drift silently: a field appended to the struct that nobody adds here is
 * simply never marshalled, and the report then looks well-formed and is wrong —
 * the failure mode this whole ABI exists to remove. Hence two assertions rather
 * than a comment asking the next editor to remember.
 *
 * REPORT_INTS counts the int32 block INCLUDING the four format fields.
 */
#define REPORT_INTS  15
#define REPORT_LONGS 2

/* The last int32 must sit exactly at the end of a REPORT_INTS-wide run. Catches
 * an int32 inserted anywhere inside the block. */
_Static_assert(offsetof(cleona_voice_report_t, output_muted) ==
                   (REPORT_INTS - 1) * (int)sizeof(int32_t),
               "REPORT_INTS no longer matches the int32 block of "
               "cleona_voice_report_t — update the marshalling in "
               "cleona_voice_get_report() and VoiceSession.fillReport() too");

/* The int64 pair must start where a REPORT_INTS-wide int32 run ends, after
 * alignment. Catches an int32 APPENDED after the last one we know about, which
 * the assertion above cannot see. */
_Static_assert(offsetof(cleona_voice_report_t, underruns) ==
                   ((REPORT_INTS * (int)sizeof(int32_t) + 7) / 8) * 8,
               "cleona_voice_report_t gained an int32 field that "
               "REPORT_INTS does not account for");

/* ==========================================================================
 * Global JNI state, established once in JNI_OnLoad
 * ========================================================================== */

static JavaVM*  g_vm  = NULL;
static jclass   g_cls = NULL;   /* global ref to VoiceSession */

static jmethodID m_open;            /* static (I[I)LVoiceSession; */
static jmethodID m_capture_buffer;  /* ()Ljava/nio/ByteBuffer;    */
static jmethodID m_playback_buffer; /* ()Ljava/nio/ByteBuffer;    */
static jmethodID m_start;           /* ()I  */
static jmethodID m_stop;            /* ()V  */
static jmethodID m_release;         /* ()V  */
static jmethodID m_capture_read;    /* (I)I */
static jmethodID m_playback_write;  /* (I)I */
static jmethodID m_set_mic_muted;   /* (Z)V */
static jmethodID m_set_out_muted;   /* (Z)V */
static jmethodID m_set_route;       /* (I)I */
static jmethodID m_get_routes;      /* ([I)I */
static jmethodID m_poll_event;      /* ([I)I */
static jmethodID m_fill_report;     /* ([I[J)V */

static pthread_key_t g_tls_key;
static int           g_tls_ready = 0;

struct cleona_voice_session {
    jobject               obj;       /* global ref, the Kotlin session      */
    jobject               cap_ref;   /* global ref, keeps cap_addr alive    */
    jobject               pb_ref;    /* global ref, keeps pb_addr  alive    */
    int16_t*              cap_addr;  /* direct buffer, capture  direction   */
    int16_t*              pb_addr;   /* direct buffer, playback direction   */
    cleona_voice_format_t fmt;
};

/* ==========================================================================
 * Thread attachment
 * ==========================================================================
 * The ABI is called from foreign threads — Dart's FFI callers and, in the
 * conformance run, the harness thread. A thread attached here is detached again
 * by the pthread key destructor when it dies; detaching after every call would
 * cost a full attach on each of the 50 frames per second.
 */

static void detach_on_thread_exit(void* unused) {
    (void)unused;
    if (g_vm != NULL) {
        (*g_vm)->DetachCurrentThread(g_vm);
    }
}

static JNIEnv* jni_env(void) {
    JNIEnv* env = NULL;
    jint rc;

    if (g_vm == NULL) return NULL;

    rc = (*g_vm)->GetEnv(g_vm, (void**)&env, JNI_VERSION_1_6);
    if (rc == JNI_OK) return env;
    if (rc != JNI_EDETACHED) return NULL;

    if ((*g_vm)->AttachCurrentThread(g_vm, &env, NULL) != JNI_OK) {
        LOGE("AttachCurrentThread failed");
        return NULL;
    }
    if (g_tls_ready) {
        /* Any non-NULL value; the destructor only needs to run. */
        pthread_setspecific(g_tls_key, (void*)1);
    }
    return env;
}

/* Reports and clears a pending Java exception. Returns 1 if there was one. */
static int jni_threw(JNIEnv* env, const char* where) {
    if ((*env)->ExceptionCheck(env)) {
        LOGE("java exception in %s", where);
        (*env)->ExceptionDescribe(env);
        (*env)->ExceptionClear(env);
        return 1;
    }
    return 0;
}

/* ==========================================================================
 * ABI constant cross-check
 * ==========================================================================
 * VoiceSession.kt mirrors the constants of cleona_voice.h, because Kotlin
 * cannot include a C header. Two copies of one value in two languages drift,
 * and the drift would be invisible: the report would still be well-formed, just
 * wrong — the exact class of failure the verification report exists to end.
 *
 * So the copy is checked rather than trusted, at load time, once. The order here
 * is the order of VoiceSession.abiConstants().
 */
static int check_abi_constants(JNIEnv* env) {
    static const int32_t expect[] = {
        CLEONA_VOICE_OK, CLEONA_VOICE_ERR_INVALID_ARG, CLEONA_VOICE_ERR_CLOSED,
        CLEONA_VOICE_ERR_NOT_STARTED, CLEONA_VOICE_ERR_ALREADY_STARTED,
        CLEONA_VOICE_ERR_FRAME_SIZE, CLEONA_VOICE_ERR_ROUTE_UNAVAILABLE,
        CLEONA_VOICE_ERR_ROUTE_UNSUPPORTED, CLEONA_VOICE_ERR_BACKEND,
        CLEONA_VOICE_ERR_NO_DEVICE, CLEONA_VOICE_ERR_PERMISSION,
        CLEONA_VOICE_ERR_UNSUPPORTED,
        CLEONA_VOICE_CAPTURE_FRAME, CLEONA_VOICE_CAPTURE_TIMEOUT,
        CLEONA_VOICE_CAPTURE_CLOSED,
        CLEONA_VOICE_FX_UNAVAILABLE, CLEONA_VOICE_FX_AVAILABLE_OFF,
        CLEONA_VOICE_FX_ENABLED, CLEONA_VOICE_FX_UNKNOWN,
        CLEONA_VOICE_ROUTE_UNKNOWN, CLEONA_VOICE_ROUTE_EARPIECE,
        CLEONA_VOICE_ROUTE_SPEAKER, CLEONA_VOICE_ROUTE_WIRED,
        CLEONA_VOICE_ROUTE_BLUETOOTH,
        CLEONA_VOICE_EV_NONE, CLEONA_VOICE_EV_ROUTES_CHANGED,
        CLEONA_VOICE_EV_INTERRUPTION_BEGIN, CLEONA_VOICE_EV_INTERRUPTION_END,
        CLEONA_VOICE_EV_FORMAT_CHANGED,
        CLEONA_VOICE_CHAIN_ANDROID_HAL, CLEONA_VOICE_BACKEND_ANDROID_AUDIORECORD,
    };
    const jsize n = (jsize)(sizeof(expect) / sizeof(expect[0]));

    jmethodID mid = (*env)->GetStaticMethodID(env, g_cls, "abiConstants", "()[I");
    jintArray arr;
    jsize got;
    jint* vals;
    int bad = 0;
    jsize i;

    if (mid == NULL) {
        LOGE("VoiceSession.abiConstants() missing");
        return -1;
    }
    arr = (jintArray)(*env)->CallStaticObjectMethod(env, g_cls, mid);
    if (jni_threw(env, "abiConstants") || arr == NULL) return -1;

    got = (*env)->GetArrayLength(env, arr);
    if (got != n) {
        LOGE("abiConstants(): %d values, header expects %d", (int)got, (int)n);
        (*env)->DeleteLocalRef(env, arr);
        return -1;
    }
    vals = (*env)->GetIntArrayElements(env, arr, NULL);
    if (vals == NULL) {
        (*env)->DeleteLocalRef(env, arr);
        return -1;
    }
    for (i = 0; i < n; i++) {
        if (vals[i] != expect[i]) {
            LOGE("ABI constant %d drifted: Kotlin=%d header=%d",
                 (int)i, (int)vals[i], (int)expect[i]);
            bad = 1;
        }
    }
    (*env)->ReleaseIntArrayElements(env, arr, vals, JNI_ABORT);
    (*env)->DeleteLocalRef(env, arr);
    return bad ? -1 : 0;
}

/* ==========================================================================
 * JNI_OnLoad
 * ========================================================================== */

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void* reserved) {
    JNIEnv* env = NULL;
    jclass local;

    (void)reserved;

    if ((*vm)->GetEnv(vm, (void**)&env, JNI_VERSION_1_6) != JNI_OK) {
        return JNI_ERR;
    }

    /* Idempotent on purpose. ART resolves JNI_OnLoad with a dlsym() on the
     * library handle, and that lookup also searches DT_NEEDED dependencies —
     * so loading ANY library that links against libcleona_voice.so runs this
     * function a second time. Observed with the conformance runner
     * (libcleona_voice_conformance.so links the backend): "android backend
     * bound" was logged twice. Without this guard the second pass would leak
     * the previous g_cls global reference and the previous pthread key, and
     * would do so again for every further dependent library. */
    if (g_vm != NULL) {
        return JNI_VERSION_1_6;
    }
    g_vm = vm;

    /* FindClass resolves against the class loader on the stack, which is the
     * app's because we are inside System.loadLibrary. Doing this later, from an
     * attached native thread, would search the system class loader and fail. */
    local = (*env)->FindClass(env, VOICE_CLASS);
    if (local == NULL) {
        LOGE("FindClass(%s) failed", VOICE_CLASS);
        (*env)->ExceptionClear(env);
        return JNI_ERR;
    }
    g_cls = (jclass)(*env)->NewGlobalRef(env, local);
    (*env)->DeleteLocalRef(env, local);
    if (g_cls == NULL) return JNI_ERR;

    m_open = (*env)->GetStaticMethodID(env, g_cls, "openSession",
                                       "(I[I)L" VOICE_CLASS ";");
    m_capture_buffer  = (*env)->GetMethodID(env, g_cls, "captureBuffer",
                                            "()Ljava/nio/ByteBuffer;");
    m_playback_buffer = (*env)->GetMethodID(env, g_cls, "playbackBuffer",
                                            "()Ljava/nio/ByteBuffer;");
    m_start           = (*env)->GetMethodID(env, g_cls, "start",          "()I");
    m_stop            = (*env)->GetMethodID(env, g_cls, "stop",           "()V");
    m_release         = (*env)->GetMethodID(env, g_cls, "release",        "()V");
    m_capture_read    = (*env)->GetMethodID(env, g_cls, "captureRead",    "(I)I");
    m_playback_write  = (*env)->GetMethodID(env, g_cls, "playbackWrite",  "(I)I");
    m_set_mic_muted   = (*env)->GetMethodID(env, g_cls, "setMicMuted",    "(Z)V");
    m_set_out_muted   = (*env)->GetMethodID(env, g_cls, "setOutputMuted", "(Z)V");
    m_set_route       = (*env)->GetMethodID(env, g_cls, "setRoute",       "(I)I");
    m_get_routes      = (*env)->GetMethodID(env, g_cls, "getRoutes",     "([I)I");
    m_poll_event      = (*env)->GetMethodID(env, g_cls, "pollEvent",     "([I)I");
    m_fill_report     = (*env)->GetMethodID(env, g_cls, "fillReport",  "([I[J)V");

    if (m_open == NULL || m_capture_buffer == NULL || m_playback_buffer == NULL ||
        m_start == NULL || m_stop == NULL || m_release == NULL ||
        m_capture_read == NULL || m_playback_write == NULL ||
        m_set_mic_muted == NULL || m_set_out_muted == NULL ||
        m_set_route == NULL || m_get_routes == NULL || m_poll_event == NULL ||
        m_fill_report == NULL) {
        LOGE("VoiceSession method lookup failed — Kotlin/JNI signature drift");
        (*env)->ExceptionClear(env);
        return JNI_ERR;
    }

    if (check_abi_constants(env) != 0) return JNI_ERR;

    if (pthread_key_create(&g_tls_key, detach_on_thread_exit) == 0) {
        g_tls_ready = 1;
    } else {
        LOGW("pthread_key_create failed; attached threads will not auto-detach");
    }

    LOGI("cleona_voice android backend bound");
    return JNI_VERSION_1_6;
}

/* ==========================================================================
 * Lifecycle
 * ========================================================================== */

static void write_open_error(cleona_voice_format_t* out_format, int32_t err) {
    /* The ABI's in-band error channel: a negative value in sample_rate, the
     * other three fields zeroed (cleona_voice.h). A sample_rate <= 0 is never a
     * valid format, so this cannot be confused with success. */
    if (out_format == NULL) return;
    out_format->sample_rate   = err;
    out_format->channels      = 0;
    out_format->frame_samples = 0;
    out_format->frame_bytes   = 0;
}

CLEONA_VOICE_API cleona_voice_session_t* cleona_voice_open(
    int32_t rate_hint, cleona_voice_format_t* out_format) {

    JNIEnv* env;
    jintArray fmt_arr;
    jobject   session_local;
    jobject   cap_local;
    jobject   pb_local;
    jint      fmt[4];
    cleona_voice_session_t* s;

    if (out_format == NULL) return NULL;

    if (g_vm == NULL || g_cls == NULL) {
        LOGE("cleona_voice_open before VoiceSession.install(context) — see "
             "BUILD_REQUEST_V1.2.md §2");
        write_open_error(out_format, CLEONA_VOICE_ERR_BACKEND);
        return NULL;
    }
    env = jni_env();
    if (env == NULL) {
        write_open_error(out_format, CLEONA_VOICE_ERR_BACKEND);
        return NULL;
    }

    if ((*env)->PushLocalFrame(env, 8) != 0) {
        write_open_error(out_format, CLEONA_VOICE_ERR_BACKEND);
        return NULL;
    }

    fmt_arr = (*env)->NewIntArray(env, 4);
    if (fmt_arr == NULL) {
        (*env)->PopLocalFrame(env, NULL);
        write_open_error(out_format, CLEONA_VOICE_ERR_BACKEND);
        return NULL;
    }

    session_local = (*env)->CallStaticObjectMethod(env, g_cls, m_open,
                                                   (jint)rate_hint, fmt_arr);
    if (jni_threw(env, "openSession")) {
        (*env)->PopLocalFrame(env, NULL);
        write_open_error(out_format, CLEONA_VOICE_ERR_BACKEND);
        return NULL;
    }

    (*env)->GetIntArrayRegion(env, fmt_arr, 0, 4, fmt);
    if (session_local == NULL) {
        /* Kotlin put the reason in fmt[0]; pass it through unchanged so the
         * caller can tell "no microphone" from "permission denied". */
        int32_t err = (fmt[0] < 0) ? (int32_t)fmt[0] : CLEONA_VOICE_ERR_BACKEND;
        (*env)->PopLocalFrame(env, NULL);
        write_open_error(out_format, err);
        return NULL;
    }

    cap_local = (*env)->CallObjectMethod(env, session_local, m_capture_buffer);
    pb_local  = (*env)->CallObjectMethod(env, session_local, m_playback_buffer);
    if (jni_threw(env, "buffers") || cap_local == NULL || pb_local == NULL) {
        (*env)->CallVoidMethod(env, session_local, m_release);
        (*env)->ExceptionClear(env);
        (*env)->PopLocalFrame(env, NULL);
        write_open_error(out_format, CLEONA_VOICE_ERR_BACKEND);
        return NULL;
    }

    s = (cleona_voice_session_t*)calloc(1, sizeof(*s));
    if (s == NULL) {
        (*env)->CallVoidMethod(env, session_local, m_release);
        (*env)->ExceptionClear(env);
        (*env)->PopLocalFrame(env, NULL);
        write_open_error(out_format, CLEONA_VOICE_ERR_BACKEND);
        return NULL;
    }

    s->cap_addr = (int16_t*)(*env)->GetDirectBufferAddress(env, cap_local);
    s->pb_addr  = (int16_t*)(*env)->GetDirectBufferAddress(env, pb_local);
    if (s->cap_addr == NULL || s->pb_addr == NULL) {
        LOGE("GetDirectBufferAddress returned NULL");
        (*env)->CallVoidMethod(env, session_local, m_release);
        (*env)->ExceptionClear(env);
        free(s);
        (*env)->PopLocalFrame(env, NULL);
        write_open_error(out_format, CLEONA_VOICE_ERR_BACKEND);
        return NULL;
    }

    s->obj     = (*env)->NewGlobalRef(env, session_local);
    s->cap_ref = (*env)->NewGlobalRef(env, cap_local);
    s->pb_ref  = (*env)->NewGlobalRef(env, pb_local);
    if (s->obj == NULL || s->cap_ref == NULL || s->pb_ref == NULL) {
        if (s->obj != NULL)     (*env)->DeleteGlobalRef(env, s->obj);
        if (s->cap_ref != NULL) (*env)->DeleteGlobalRef(env, s->cap_ref);
        if (s->pb_ref != NULL)  (*env)->DeleteGlobalRef(env, s->pb_ref);
        free(s);
        (*env)->PopLocalFrame(env, NULL);
        write_open_error(out_format, CLEONA_VOICE_ERR_BACKEND);
        return NULL;
    }

    s->fmt.sample_rate   = (int32_t)fmt[0];
    s->fmt.channels      = (int32_t)fmt[1];
    s->fmt.frame_samples = (int32_t)fmt[2];
    s->fmt.frame_bytes   = (int32_t)fmt[3];
    *out_format = s->fmt;

    (*env)->PopLocalFrame(env, NULL);
    return s;
}

CLEONA_VOICE_API int32_t cleona_voice_start(cleona_voice_session_t* s) {
    JNIEnv* env;
    jint rc;

    if (s == NULL) return CLEONA_VOICE_ERR_CLOSED;
    env = jni_env();
    if (env == NULL) return CLEONA_VOICE_ERR_BACKEND;

    rc = (*env)->CallIntMethod(env, s->obj, m_start);
    if (jni_threw(env, "start")) return CLEONA_VOICE_ERR_BACKEND;
    return (int32_t)rc;
}

CLEONA_VOICE_API void cleona_voice_stop(cleona_voice_session_t* s) {
    JNIEnv* env;

    if (s == NULL) return;                /* documented no-op */
    env = jni_env();
    if (env == NULL) return;

    (*env)->CallVoidMethod(env, s->obj, m_stop);
    jni_threw(env, "stop");
}

CLEONA_VOICE_API void cleona_voice_close(cleona_voice_session_t* s) {
    JNIEnv* env;

    if (s == NULL) return;                /* documented no-op */
    env = jni_env();
    if (env == NULL) {
        /* Without a VM the Java objects cannot be released, but leaking the C
         * struct on top of that helps nobody. */
        free(s);
        return;
    }

    (*env)->CallVoidMethod(env, s->obj, m_release);
    jni_threw(env, "release");

    (*env)->DeleteGlobalRef(env, s->obj);
    (*env)->DeleteGlobalRef(env, s->cap_ref);
    (*env)->DeleteGlobalRef(env, s->pb_ref);
    free(s);
}

/* ==========================================================================
 * Data path
 * ========================================================================== */

CLEONA_VOICE_API int32_t cleona_voice_capture_read(cleona_voice_session_t* s,
                                                   int16_t* out,
                                                   int32_t timeout_ms) {
    JNIEnv* env;
    jint rc;

    if (s == NULL || out == NULL) return CLEONA_VOICE_CAPTURE_CLOSED;
    env = jni_env();
    if (env == NULL) return CLEONA_VOICE_CAPTURE_CLOSED;

    rc = (*env)->CallIntMethod(env, s->obj, m_capture_read, (jint)timeout_ms);
    if (jni_threw(env, "captureRead")) return CLEONA_VOICE_CAPTURE_CLOSED;

    /* Copy ONLY for a whole frame. On a timeout the caller's buffer must come
     * back untouched — the harness poisons it and checks exactly that
     * (conformance.c, "wrote_on_timeout"). */
    if (rc == CLEONA_VOICE_CAPTURE_FRAME) {
        memcpy(out, s->cap_addr, (size_t)s->fmt.frame_bytes);
    }
    return (int32_t)rc;
}

CLEONA_VOICE_API int32_t cleona_voice_playback_write(cleona_voice_session_t* s,
                                                     const int16_t* pcm,
                                                     int32_t frame_samples) {
    JNIEnv* env;
    jint rc;

    if (s == NULL) return CLEONA_VOICE_ERR_CLOSED;
    if (pcm == NULL) return CLEONA_VOICE_ERR_INVALID_ARG;
    env = jni_env();
    if (env == NULL) return CLEONA_VOICE_ERR_BACKEND;

    /* Stage the frame only when it is the right size. Kotlin re-checks and owns
     * the precedence between "closed", "not started" and "wrong frame size"; the
     * guard here exists so a wrong size can never overrun the staging buffer. */
    if (frame_samples == s->fmt.frame_samples) {
        memcpy(s->pb_addr, pcm, (size_t)s->fmt.frame_bytes);
    }

    rc = (*env)->CallIntMethod(env, s->obj, m_playback_write, (jint)frame_samples);
    if (jni_threw(env, "playbackWrite")) return CLEONA_VOICE_ERR_BACKEND;
    return (int32_t)rc;
}

/* ==========================================================================
 * Controls
 * ========================================================================== */

CLEONA_VOICE_API void cleona_voice_set_mic_muted(cleona_voice_session_t* s,
                                                 int32_t muted) {
    JNIEnv* env;
    if (s == NULL) return;
    env = jni_env();
    if (env == NULL) return;
    (*env)->CallVoidMethod(env, s->obj, m_set_mic_muted,
                           muted ? JNI_TRUE : JNI_FALSE);
    jni_threw(env, "setMicMuted");
}

CLEONA_VOICE_API void cleona_voice_set_output_muted(cleona_voice_session_t* s,
                                                    int32_t muted) {
    JNIEnv* env;
    if (s == NULL) return;
    env = jni_env();
    if (env == NULL) return;
    (*env)->CallVoidMethod(env, s->obj, m_set_out_muted,
                           muted ? JNI_TRUE : JNI_FALSE);
    jni_threw(env, "setOutputMuted");
}

CLEONA_VOICE_API int32_t cleona_voice_set_route(cleona_voice_session_t* s,
                                                int32_t route) {
    JNIEnv* env;
    jint rc;

    if (s == NULL) return CLEONA_VOICE_ERR_CLOSED;
    env = jni_env();
    if (env == NULL) return CLEONA_VOICE_ERR_BACKEND;

    rc = (*env)->CallIntMethod(env, s->obj, m_set_route, (jint)route);
    if (jni_threw(env, "setRoute")) return CLEONA_VOICE_ERR_BACKEND;
    return (int32_t)rc;
}

/* Shared shape of get_routes and poll_event: both hand back two ints. */
static int32_t two_int_call(cleona_voice_session_t* s, jmethodID mid,
                            int32_t* out_a, int32_t* out_b, const char* where) {
    JNIEnv* env;
    jintArray arr;
    jint vals[2];
    jint rc;

    if (s == NULL) return CLEONA_VOICE_ERR_CLOSED;
    if (out_a == NULL || out_b == NULL) return CLEONA_VOICE_ERR_INVALID_ARG;
    env = jni_env();
    if (env == NULL) return CLEONA_VOICE_ERR_BACKEND;

    if ((*env)->PushLocalFrame(env, 4) != 0) return CLEONA_VOICE_ERR_BACKEND;
    arr = (*env)->NewIntArray(env, 2);
    if (arr == NULL) {
        (*env)->PopLocalFrame(env, NULL);
        return CLEONA_VOICE_ERR_BACKEND;
    }
    rc = (*env)->CallIntMethod(env, s->obj, mid, arr);
    if (jni_threw(env, where)) {
        (*env)->PopLocalFrame(env, NULL);
        return CLEONA_VOICE_ERR_BACKEND;
    }
    (*env)->GetIntArrayRegion(env, arr, 0, 2, vals);
    (*env)->PopLocalFrame(env, NULL);

    if (rc == CLEONA_VOICE_OK) {
        *out_a = (int32_t)vals[0];
        *out_b = (int32_t)vals[1];
    }
    return (int32_t)rc;
}

CLEONA_VOICE_API int32_t cleona_voice_get_routes(cleona_voice_session_t* s,
                                                 int32_t* out_mask,
                                                 int32_t* out_active) {
    return two_int_call(s, m_get_routes, out_mask, out_active, "getRoutes");
}

CLEONA_VOICE_API int32_t cleona_voice_poll_event(cleona_voice_session_t* s,
                                                 int32_t* out_event,
                                                 int32_t* out_arg) {
    return two_int_call(s, m_poll_event, out_event, out_arg, "pollEvent");
}

/* ==========================================================================
 * Verification report (I11)
 * ========================================================================== */

CLEONA_VOICE_API void cleona_voice_get_report(cleona_voice_session_t* s,
                                              cleona_voice_report_t* out) {
    JNIEnv* env;
    jintArray  ints;
    jlongArray longs;
    jint  iv[REPORT_INTS];
    jlong lv[REPORT_LONGS];

    if (out == NULL) return;

    /* A zeroed report yields duplex == 0 and therefore reads as a conformance
     * failure rather than as a plausible session (cleona_voice.h). Also the
     * correct answer whenever anything below refuses. */
    memset(out, 0, sizeof(*out));
    if (s == NULL) return;

    env = jni_env();
    if (env == NULL) return;
    if ((*env)->PushLocalFrame(env, 4) != 0) return;

    ints  = (*env)->NewIntArray(env, REPORT_INTS);
    longs = (*env)->NewLongArray(env, REPORT_LONGS);
    if (ints == NULL || longs == NULL) {
        (*env)->PopLocalFrame(env, NULL);
        return;
    }
    (*env)->CallVoidMethod(env, s->obj, m_fill_report, ints, longs);
    if (jni_threw(env, "fillReport")) {
        (*env)->PopLocalFrame(env, NULL);
        return;
    }
    (*env)->GetIntArrayRegion(env, ints, 0, REPORT_INTS, iv);
    (*env)->GetLongArrayRegion(env, longs, 0, REPORT_LONGS, lv);
    (*env)->PopLocalFrame(env, NULL);

    out->format.sample_rate   = (int32_t)iv[0];
    out->format.channels      = (int32_t)iv[1];
    out->format.frame_samples = (int32_t)iv[2];
    out->format.frame_bytes   = (int32_t)iv[3];
    out->aec_state             = (int32_t)iv[4];
    out->ns_state              = (int32_t)iv[5];
    out->agc_state             = (int32_t)iv[6];
    out->chain_origin          = (int32_t)iv[7];
    out->backend               = (int32_t)iv[8];
    out->duplex                = (int32_t)iv[9];
    out->route_active_in       = (int32_t)iv[10];
    out->route_active_out      = (int32_t)iv[11];
    out->routes_available_mask = (int32_t)iv[12];
    /* Erratum E6a. Kotlin already normalises these to exactly 0 or 1; they are
     * passed straight through rather than re-derived, because the value the
     * setter was given is the observation the ABI asks for. */
    out->mic_muted             = (int32_t)iv[13];
    out->output_muted          = (int32_t)iv[14];
    out->underruns             = (int64_t)lv[0];
    out->overruns              = (int64_t)lv[1];
}
