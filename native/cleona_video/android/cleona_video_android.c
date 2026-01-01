/* cleona_video_android.c — the Android backend of the cleona_video ABI.
 *
 * Work package: docs/SPEC_VOICE_VIDEO_REWORK.md V1.14.
 * Contract:     native/cleona_video/cleona_video.h (frozen).
 * Architecture: Cleona_Chat_Architecture_v3_0.md §10.6 (normative).
 *
 * ---------------------------------------------------------------------------
 * WHAT THIS FILE IS AND IS NOT
 * ---------------------------------------------------------------------------
 * A JNI facade and nothing else, following the precedent of
 * native/cleona_voice/android/cleona_voice_android.c (V1.2) to the letter: no
 * camera decision, no encoder/decoder state machine and no bitstream assembly
 * lives here. Every one of those lives in
 * android/app/src/main/kotlin/chat/cleona/cleona/VideoSession.kt, because the
 * platform objects this backend needs — Camera2's CameraManager, MediaCodec's
 * hardware-accelerated-codec lookup, and (for the decode side) a Flutter
 * TextureRegistry.SurfaceTextureEntry — are Java API surfaces with no NDK
 * equivalent for the last one. A Flutter `Texture` widget can only display a
 * texture id that Flutter's own renderer registered; a texture id manufactured
 * outside that registry (an NDK ANativeWindow/GL texture the Dart layer never
 * heard of) is not decodable by the widget, which is the video counterpart of
 * §10.4's argument for why voice needs the Java API on Android.
 *
 * ---------------------------------------------------------------------------
 * HOW THE JavaVM GETS HERE — READ BEFORE DEBUGGING "ERR_BACKEND ON OPEN"
 * ---------------------------------------------------------------------------
 * Identical mechanism to the voice backend. `JNI_OnLoad` only runs when ART
 * loads this library via `System.loadLibrary`; Dart's `DynamicLibrary.open()`
 * calls plain `dlopen()` and never triggers it. A process where only Dart
 * touched this library has no `JavaVM*`, and every entry point below fails
 * cleanly with CLEONA_VIDEO_ERR_BACKEND instead of dereferencing NULL.
 *
 * The fix is one call during app start:
 *
 *     VideoSession.install(applicationContext, flutterEngine.renderer)
 *
 * `MainActivity.kt` belongs to work package V1.10, so V1.14 asks for that line
 * rather than writing it — BUILD_REQUEST_V1.14.md §2.
 *
 * ---------------------------------------------------------------------------
 * NO PIXELS CROSS THIS FILE (I10)
 * ---------------------------------------------------------------------------
 * `cleona_video_read_encoded` and `cleona_video_submit_encoded` each carry a
 * raw native buffer already sized by the caller (Dart's `_readBuf`/
 * `_submitBuf`, or the conformance harness's ceiling-sized buffer). Rather
 * than copy that buffer's bytes into a persistent Kotlin-side buffer and back,
 * this file wraps the CALLER's pointer directly with `NewDirectByteBuffer` on
 * every call and hands that wrapper to Kotlin, which fills or reads it
 * in-place. Zero-copy, and — unlike the voice facade's per-session cached
 * buffer — correct across `cleona_video_reconfigure`, which can change
 * `max_frame_bytes` (and therefore the required buffer size) at any time
 * (Erratum 1): there is no cached size to invalidate because nothing is
 * cached.
 */

#include <jni.h>
#include <pthread.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <android/log.h>

#include "../cleona_video.h"

#define TAG "CleonaVideo"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN,  TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  TAG, __VA_ARGS__)

#define VIDEO_CLASS "chat/cleona/cleona/VideoSession"

/* cleona_video_config_t marshals as a 7-int array in DECLARATION ORDER:
 *   0 codec, 1 width, 2 height, 3 fps, 4 target_bitrate_kbps,
 *   5 max_frame_bytes, 6 keyframe_interval_frames.
 * That order is also the ABI's in-band error channel (Erratum 6b): index 5
 * doubles as the error code on a failed open()/reconfigure(). One offsets
 * table, no duplication of field order anywhere else in this file. */
#define CFG_INTS 7
#define CFG_MFB_INDEX 5

_Static_assert(offsetof(cleona_video_config_t, max_frame_bytes) ==
                   CFG_MFB_INDEX * (int)sizeof(int32_t),
               "CFG_MFB_INDEX no longer matches cleona_video_config_t's "
               "field order -- update the marshalling here and in "
               "VideoSession.kt's writeCfg()/readCfg()");
_Static_assert(sizeof(cleona_video_config_t) == CFG_INTS * sizeof(int32_t),
               "cleona_video_config_t gained/lost a field that CFG_INTS "
               "does not account for");

/* cleona_video_report_t marshals as 8 ints + 5 longs, in declaration order. */
#define REPORT_INTS  8
#define REPORT_LONGS 5

_Static_assert(offsetof(cleona_video_report_t, encode_backend) ==
                   (REPORT_INTS - 1) * (int)sizeof(int32_t),
               "REPORT_INTS no longer matches the int32 block of "
               "cleona_video_report_t");
_Static_assert(offsetof(cleona_video_report_t, frames_captured) ==
                   ((REPORT_INTS * (int)sizeof(int32_t) + 7) / 8) * 8,
               "cleona_video_report_t gained an int32 field that "
               "REPORT_INTS does not account for");

/* ==========================================================================
 * Global JNI state, established once in JNI_OnLoad
 * ========================================================================== */

static JavaVM* g_vm  = NULL;
static jclass  g_cls = NULL;   /* global ref to VideoSession */

static jmethodID m_open;              /* static ([I[I)LVideoSession; */
static jmethodID m_reconfigure;       /* ([I[I)I  */
static jmethodID m_start;             /* ()I      */
static jmethodID m_stop;              /* ()V      */
static jmethodID m_release;           /* ()V      */
static jmethodID m_read_encoded;      /* (Ljava/nio/ByteBuffer;II[I[J)I */
static jmethodID m_submit_encoded;    /* (Ljava/nio/ByteBuffer;II)I */
static jmethodID m_get_texture_id;    /* ([J)I    */
static jmethodID m_request_keyframe;  /* ()I      */
static jmethodID m_set_capture_enabled; /* (Z)V   */
static jmethodID m_switch_camera;     /* ()I      */
static jmethodID m_fill_report;       /* ([I[J)V  */

static pthread_key_t g_tls_key;
static int           g_tls_ready = 0;

struct cleona_video_session {
    jobject obj;   /* global ref, the Kotlin session */
};

/* ==========================================================================
 * Thread attachment — identical policy to cleona_voice_android.c.
 * ========================================================================== */

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
        pthread_setspecific(g_tls_key, (void*)1);
    }
    return env;
}

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
 * ABI constant cross-check — same rationale as cleona_voice_android.c: two
 * copies of a constant in two languages drift silently, and a report that is
 * well-formed and wrong is exactly the failure I11 exists to end.
 * ========================================================================== */
static int check_abi_constants(JNIEnv* env) {
    static const int32_t expect[] = {
        CLEONA_VIDEO_OK, CLEONA_VIDEO_ERR_INVALID, CLEONA_VIDEO_ERR_STATE,
        CLEONA_VIDEO_ERR_UNSUPPORTED, CLEONA_VIDEO_ERR_BACKEND,
        CLEONA_VIDEO_ERR_BUFFER_TOO_SMALL, CLEONA_VIDEO_ERR_DECODE,
        CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE,
        CLEONA_VIDEO_READ_FRAME, CLEONA_VIDEO_READ_TIMEOUT,
        CLEONA_VIDEO_SUBMIT_ACCEPTED, CLEONA_VIDEO_SUBMIT_AWAITING_KEYFRAME,
        CLEONA_VIDEO_FLAG_KEYFRAME,
        CLEONA_VIDEO_CODEC_H264, CLEONA_VIDEO_CODEC_HEVC,
        CLEONA_VIDEO_CODEC_AV1, CLEONA_VIDEO_CODEC_VP9,
        CLEONA_VIDEO_HW_NO, CLEONA_VIDEO_HW_YES, CLEONA_VIDEO_HW_NOT_DETERMINABLE,
        CLEONA_VIDEO_BACKEND_ANDROID_CAMERAX, CLEONA_VIDEO_BACKEND_ANDROID_MEDIACODEC,
    };
    const jsize n = (jsize)(sizeof(expect) / sizeof(expect[0]));

    jmethodID mid = (*env)->GetStaticMethodID(env, g_cls, "abiConstants", "()[I");
    jintArray arr;
    jsize got;
    jint* vals;
    int bad = 0;
    jsize i;

    if (mid == NULL) {
        LOGE("VideoSession.abiConstants() missing");
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

    /* Idempotent for the same reason cleona_voice_android.c documents: ART
     * resolves JNI_OnLoad via dlsym on the library handle, which also walks
     * DT_NEEDED, so any dependent library (the conformance harness .so links
     * this backend) re-triggers it. */
    if (g_vm != NULL) {
        return JNI_VERSION_1_6;
    }
    g_vm = vm;

    local = (*env)->FindClass(env, VIDEO_CLASS);
    if (local == NULL) {
        LOGE("FindClass(%s) failed", VIDEO_CLASS);
        (*env)->ExceptionClear(env);
        return JNI_ERR;
    }
    g_cls = (jclass)(*env)->NewGlobalRef(env, local);
    (*env)->DeleteLocalRef(env, local);
    if (g_cls == NULL) return JNI_ERR;

    m_open = (*env)->GetStaticMethodID(env, g_cls, "openSession",
                                       "([I[I)L" VIDEO_CLASS ";");
    m_reconfigure = (*env)->GetMethodID(env, g_cls, "reconfigure", "([I[I)I");
    m_start       = (*env)->GetMethodID(env, g_cls, "start",   "()I");
    m_stop        = (*env)->GetMethodID(env, g_cls, "stop",    "()V");
    m_release     = (*env)->GetMethodID(env, g_cls, "release", "()V");
    m_read_encoded = (*env)->GetMethodID(env, g_cls, "readEncoded",
                                         "(Ljava/nio/ByteBuffer;II[I[J)I");
    m_submit_encoded = (*env)->GetMethodID(env, g_cls, "submitEncoded",
                                           "(Ljava/nio/ByteBuffer;II)I");
    m_get_texture_id = (*env)->GetMethodID(env, g_cls, "getTextureId", "([J)I");
    m_request_keyframe = (*env)->GetMethodID(env, g_cls, "requestKeyframe", "()I");
    m_set_capture_enabled = (*env)->GetMethodID(env, g_cls, "setCaptureEnabled", "(Z)V");
    m_switch_camera = (*env)->GetMethodID(env, g_cls, "switchCamera", "()I");
    m_fill_report = (*env)->GetMethodID(env, g_cls, "fillReport", "([I[J)V");

    if (m_open == NULL || m_reconfigure == NULL || m_start == NULL ||
        m_stop == NULL || m_release == NULL || m_read_encoded == NULL ||
        m_submit_encoded == NULL || m_get_texture_id == NULL ||
        m_request_keyframe == NULL || m_set_capture_enabled == NULL ||
        m_switch_camera == NULL || m_fill_report == NULL) {
        LOGE("VideoSession method lookup failed -- Kotlin/JNI signature drift");
        (*env)->ExceptionClear(env);
        return JNI_ERR;
    }

    if (check_abi_constants(env) != 0) return JNI_ERR;

    if (pthread_key_create(&g_tls_key, detach_on_thread_exit) == 0) {
        g_tls_ready = 1;
    } else {
        LOGW("pthread_key_create failed; attached threads will not auto-detach");
    }

    LOGI("cleona_video android backend bound");
    return JNI_VERSION_1_6;
}

/* ==========================================================================
 * Config marshalling helpers
 * ========================================================================== */

static void cfg_to_jint(const cleona_video_config_t* c, jint out[CFG_INTS]) {
    out[0] = c->codec;
    out[1] = c->width;
    out[2] = c->height;
    out[3] = c->fps;
    out[4] = c->target_bitrate_kbps;
    out[5] = c->max_frame_bytes;
    out[6] = c->keyframe_interval_frames;
}

static void jint_to_cfg(const jint in[CFG_INTS], cleona_video_config_t* c) {
    c->codec                   = (int32_t)in[0];
    c->width                   = (int32_t)in[1];
    c->height                  = (int32_t)in[2];
    c->fps                     = (int32_t)in[3];
    c->target_bitrate_kbps     = (int32_t)in[4];
    c->max_frame_bytes         = (int32_t)in[5];
    c->keyframe_interval_frames = (int32_t)in[6];
}

/* Erratum 6b: on failure, zero the struct and put the negative error code
 * where max_frame_bytes lives. Identical policy to the voice facade's
 * write_open_error() and to the mock's write_open_error(). */
static void write_open_error(cleona_video_config_t* out, int32_t code) {
    if (out == NULL) return;
    memset(out, 0, sizeof(*out));
    out->max_frame_bytes = code;
}

/* ==========================================================================
 * Lifecycle
 * ========================================================================== */

CLEONA_VIDEO_API cleona_video_session_t* cleona_video_open(
    const cleona_video_config_t* cfg, cleona_video_config_t* out_negotiated) {

    JNIEnv* env;
    jintArray cfg_arr, out_arr;
    jint cfg_in[CFG_INTS], out_vals[CFG_INTS];
    jobject session_local;
    cleona_video_session_t* s;

    if (cfg == NULL) {
        write_open_error(out_negotiated, CLEONA_VIDEO_ERR_INVALID);
        return NULL;
    }
    if (g_vm == NULL || g_cls == NULL) {
        LOGE("cleona_video_open before VideoSession.install(context, registry) "
             "-- see BUILD_REQUEST_V1.14.md §2");
        write_open_error(out_negotiated, CLEONA_VIDEO_ERR_BACKEND);
        return NULL;
    }
    env = jni_env();
    if (env == NULL) {
        write_open_error(out_negotiated, CLEONA_VIDEO_ERR_BACKEND);
        return NULL;
    }

    if ((*env)->PushLocalFrame(env, 8) != 0) {
        write_open_error(out_negotiated, CLEONA_VIDEO_ERR_BACKEND);
        return NULL;
    }

    cfg_to_jint(cfg, cfg_in);
    cfg_arr = (*env)->NewIntArray(env, CFG_INTS);
    out_arr = (*env)->NewIntArray(env, CFG_INTS);
    if (cfg_arr == NULL || out_arr == NULL) {
        (*env)->PopLocalFrame(env, NULL);
        write_open_error(out_negotiated, CLEONA_VIDEO_ERR_BACKEND);
        return NULL;
    }
    (*env)->SetIntArrayRegion(env, cfg_arr, 0, CFG_INTS, cfg_in);

    session_local = (*env)->CallStaticObjectMethod(env, g_cls, m_open, cfg_arr, out_arr);
    if (jni_threw(env, "openSession")) {
        (*env)->PopLocalFrame(env, NULL);
        write_open_error(out_negotiated, CLEONA_VIDEO_ERR_BACKEND);
        return NULL;
    }
    (*env)->GetIntArrayRegion(env, out_arr, 0, CFG_INTS, out_vals);

    if (session_local == NULL) {
        /* Kotlin already placed the ERR_* code at out_vals[CFG_MFB_INDEX] and
         * zeroed the rest -- the exact in-band shape Erratum 6b specifies.
         * Passed through unchanged rather than re-derived, for the same reason
         * cleona_voice_android.c passes the voice equivalent through
         * unchanged: Kotlin is closer to the failure and knows which of
         * ERR_INVALID / ERR_UNSUPPORTED / ERR_BACKEND / ERR_RATE_UNACHIEVABLE
         * it actually is. */
        cleona_video_config_t err_cfg;
        jint_to_cfg(out_vals, &err_cfg);
        int32_t code = err_cfg.max_frame_bytes;
        if (code >= 0) {
            /* Kotlin returned null without setting a negative code -- a bug in
             * the backend, not a documented outcome. Fail closed rather than
             * report a bogus "success shape" with a non-negative error slot. */
            LOGE("openSession returned null with a non-negative error slot (%d)", code);
            code = CLEONA_VIDEO_ERR_BACKEND;
        }
        (*env)->PopLocalFrame(env, NULL);
        write_open_error(out_negotiated, code);
        return NULL;
    }

    s = (cleona_video_session_t*)calloc(1, sizeof(*s));
    if (s == NULL) {
        /* Session opened on the Kotlin side but the C wrapper could not be
         * allocated -- release what was already created. */
        LOGE("calloc failed for cleona_video_session_t");
        (*env)->PopLocalFrame(env, NULL);
        write_open_error(out_negotiated, CLEONA_VIDEO_ERR_BACKEND);
        return NULL;
    }
    s->obj = (*env)->NewGlobalRef(env, session_local);
    if (s->obj == NULL) {
        free(s);
        (*env)->PopLocalFrame(env, NULL);
        write_open_error(out_negotiated, CLEONA_VIDEO_ERR_BACKEND);
        return NULL;
    }

    if (out_negotiated != NULL) {
        jint_to_cfg(out_vals, out_negotiated);
    }

    (*env)->PopLocalFrame(env, NULL);
    return s;
}

CLEONA_VIDEO_API int32_t cleona_video_reconfigure(cleona_video_session_t* s,
                                 const cleona_video_config_t* cfg,
                                 cleona_video_config_t* out_negotiated) {
    JNIEnv* env;
    jintArray cfg_arr, out_arr;
    jint cfg_in[CFG_INTS], out_vals[CFG_INTS];
    jint rc;

    if (s == NULL || cfg == NULL) return CLEONA_VIDEO_ERR_INVALID;
    env = jni_env();
    if (env == NULL) return CLEONA_VIDEO_ERR_BACKEND;

    if ((*env)->PushLocalFrame(env, 4) != 0) return CLEONA_VIDEO_ERR_BACKEND;

    cfg_to_jint(cfg, cfg_in);
    cfg_arr = (*env)->NewIntArray(env, CFG_INTS);
    out_arr = (*env)->NewIntArray(env, CFG_INTS);
    if (cfg_arr == NULL || out_arr == NULL) {
        (*env)->PopLocalFrame(env, NULL);
        return CLEONA_VIDEO_ERR_BACKEND;
    }
    (*env)->SetIntArrayRegion(env, cfg_arr, 0, CFG_INTS, cfg_in);

    rc = (*env)->CallIntMethod(env, s->obj, m_reconfigure, cfg_arr, out_arr);
    if (jni_threw(env, "reconfigure")) {
        (*env)->PopLocalFrame(env, NULL);
        return CLEONA_VIDEO_ERR_BACKEND;
    }
    (*env)->GetIntArrayRegion(env, out_arr, 0, CFG_INTS, out_vals);
    (*env)->PopLocalFrame(env, NULL);

    if (rc == CLEONA_VIDEO_OK && out_negotiated != NULL) {
        jint_to_cfg(out_vals, out_negotiated);
    }
    return (int32_t)rc;
}

CLEONA_VIDEO_API int32_t cleona_video_start(cleona_video_session_t* s) {
    JNIEnv* env;
    jint rc;
    if (s == NULL) return CLEONA_VIDEO_ERR_INVALID;
    env = jni_env();
    if (env == NULL) return CLEONA_VIDEO_ERR_BACKEND;
    rc = (*env)->CallIntMethod(env, s->obj, m_start);
    if (jni_threw(env, "start")) return CLEONA_VIDEO_ERR_BACKEND;
    return (int32_t)rc;
}

CLEONA_VIDEO_API void cleona_video_stop(cleona_video_session_t* s) {
    JNIEnv* env;
    if (s == NULL) return;
    env = jni_env();
    if (env == NULL) return;
    (*env)->CallVoidMethod(env, s->obj, m_stop);
    jni_threw(env, "stop");
}

CLEONA_VIDEO_API void cleona_video_close(cleona_video_session_t* s) {
    JNIEnv* env;
    if (s == NULL) return;
    env = jni_env();
    if (env == NULL) {
        free(s);
        return;
    }
    (*env)->CallVoidMethod(env, s->obj, m_release);
    jni_threw(env, "release");
    (*env)->DeleteGlobalRef(env, s->obj);
    free(s);
}

/* ==========================================================================
 * Data path — Dart never sees pixels (I10)
 * ========================================================================== */

CLEONA_VIDEO_API int32_t cleona_video_read_encoded(cleona_video_session_t* s,
                                  uint8_t* buf, int32_t buf_cap,
                                  int32_t* out_size, int32_t* out_flags,
                                  int64_t* out_pts_us, int32_t timeout_ms) {
    JNIEnv* env;
    jobject bytebuf;
    jintArray meta;
    jlongArray pts;
    jint meta_vals[2];
    jlong pts_val[1];
    jint rc;

    if (s == NULL || buf == NULL || buf_cap <= 0 || out_size == NULL ||
        out_flags == NULL || out_pts_us == NULL) {
        return CLEONA_VIDEO_ERR_INVALID;
    }
    env = jni_env();
    if (env == NULL) return CLEONA_VIDEO_ERR_BACKEND;

    if ((*env)->PushLocalFrame(env, 6) != 0) return CLEONA_VIDEO_ERR_BACKEND;

    /* Zero-copy wrap of the CALLER's buffer -- see the file header. Valid only
     * for the duration of this call; no reference to it is kept. */
    bytebuf = (*env)->NewDirectByteBuffer(env, buf, buf_cap);
    meta = (*env)->NewIntArray(env, 2);
    pts  = (*env)->NewLongArray(env, 1);
    if (bytebuf == NULL || meta == NULL || pts == NULL) {
        (*env)->PopLocalFrame(env, NULL);
        return CLEONA_VIDEO_ERR_BACKEND;
    }

    rc = (*env)->CallIntMethod(env, s->obj, m_read_encoded, bytebuf,
                               (jint)buf_cap, (jint)timeout_ms, meta, pts);
    if (jni_threw(env, "readEncoded")) {
        (*env)->PopLocalFrame(env, NULL);
        return CLEONA_VIDEO_ERR_BACKEND;
    }

    if (rc == CLEONA_VIDEO_READ_FRAME || rc == CLEONA_VIDEO_ERR_BUFFER_TOO_SMALL) {
        (*env)->GetIntArrayRegion(env, meta, 0, 2, meta_vals);
        *out_size  = (int32_t)meta_vals[0];
        *out_flags = (int32_t)meta_vals[1];
        if (rc == CLEONA_VIDEO_READ_FRAME) {
            (*env)->GetLongArrayRegion(env, pts, 0, 1, pts_val);
            *out_pts_us = (int64_t)pts_val[0];
        }
    }
    (*env)->PopLocalFrame(env, NULL);
    return (int32_t)rc;
}

CLEONA_VIDEO_API int32_t cleona_video_submit_encoded(cleona_video_session_t* s,
                                    const uint8_t* data, int32_t size,
                                    int32_t flags) {
    JNIEnv* env;
    jobject bytebuf;
    jint rc;

    if (s == NULL) return CLEONA_VIDEO_ERR_STATE;
    if (data == NULL || size <= 0) return CLEONA_VIDEO_ERR_INVALID;
    env = jni_env();
    if (env == NULL) return CLEONA_VIDEO_ERR_STATE;

    if ((*env)->PushLocalFrame(env, 2) != 0) return CLEONA_VIDEO_ERR_STATE;

    /* Same zero-copy wrap as read_encoded. `data` is declared const in the
     * ABI; NewDirectByteBuffer's non-const parameter is a JNI signature
     * artefact, not licence to write -- Kotlin's readEncoded/submitEncoded
     * pair only ever reads through this one. */
    bytebuf = (*env)->NewDirectByteBuffer(env, (void*)(uintptr_t)data, size);
    if (bytebuf == NULL) {
        (*env)->PopLocalFrame(env, NULL);
        return CLEONA_VIDEO_ERR_STATE;
    }

    rc = (*env)->CallIntMethod(env, s->obj, m_submit_encoded, bytebuf,
                               (jint)size, (jint)flags);
    if (jni_threw(env, "submitEncoded")) {
        (*env)->PopLocalFrame(env, NULL);
        return CLEONA_VIDEO_ERR_STATE;
    }
    (*env)->PopLocalFrame(env, NULL);
    return (int32_t)rc;
}

CLEONA_VIDEO_API int32_t cleona_video_get_texture_id(cleona_video_session_t* s,
                                                      int64_t* out_id) {
    JNIEnv* env;
    jlongArray arr;
    jlong val[1];
    jint rc;

    if (s == NULL) return CLEONA_VIDEO_ERR_STATE;
    if (out_id == NULL) return CLEONA_VIDEO_ERR_INVALID;
    env = jni_env();
    if (env == NULL) return CLEONA_VIDEO_ERR_STATE;

    if ((*env)->PushLocalFrame(env, 2) != 0) return CLEONA_VIDEO_ERR_STATE;
    arr = (*env)->NewLongArray(env, 1);
    if (arr == NULL) {
        (*env)->PopLocalFrame(env, NULL);
        return CLEONA_VIDEO_ERR_STATE;
    }
    rc = (*env)->CallIntMethod(env, s->obj, m_get_texture_id, arr);
    if (jni_threw(env, "getTextureId")) {
        (*env)->PopLocalFrame(env, NULL);
        return CLEONA_VIDEO_ERR_STATE;
    }
    if (rc == CLEONA_VIDEO_OK) {
        (*env)->GetLongArrayRegion(env, arr, 0, 1, val);
        *out_id = (int64_t)val[0];
    }
    (*env)->PopLocalFrame(env, NULL);
    return (int32_t)rc;
}

CLEONA_VIDEO_API int32_t cleona_video_request_keyframe(cleona_video_session_t* s) {
    JNIEnv* env;
    jint rc;
    if (s == NULL) return CLEONA_VIDEO_ERR_STATE;
    env = jni_env();
    if (env == NULL) return CLEONA_VIDEO_ERR_STATE;
    rc = (*env)->CallIntMethod(env, s->obj, m_request_keyframe);
    if (jni_threw(env, "requestKeyframe")) return CLEONA_VIDEO_ERR_STATE;
    return (int32_t)rc;
}

CLEONA_VIDEO_API void cleona_video_set_capture_enabled(cleona_video_session_t* s,
                                                        int32_t on) {
    JNIEnv* env;
    if (s == NULL) return;
    env = jni_env();
    if (env == NULL) return;
    (*env)->CallVoidMethod(env, s->obj, m_set_capture_enabled, on ? JNI_TRUE : JNI_FALSE);
    jni_threw(env, "setCaptureEnabled");
}

CLEONA_VIDEO_API int32_t cleona_video_switch_camera(cleona_video_session_t* s) {
    JNIEnv* env;
    jint rc;
    if (s == NULL) return CLEONA_VIDEO_ERR_STATE;
    env = jni_env();
    if (env == NULL) return CLEONA_VIDEO_ERR_STATE;
    rc = (*env)->CallIntMethod(env, s->obj, m_switch_camera);
    if (jni_threw(env, "switchCamera")) return CLEONA_VIDEO_ERR_STATE;
    return (int32_t)rc;
}

/* ==========================================================================
 * Verification report (I11)
 * ========================================================================== */

CLEONA_VIDEO_API void cleona_video_get_report(cleona_video_session_t* s,
                                              cleona_video_report_t* out) {
    JNIEnv* env;
    jintArray  ints;
    jlongArray longs;
    jint  iv[REPORT_INTS];
    jlong lv[REPORT_LONGS];

    if (out == NULL) return;
    memset(out, 0, sizeof(*out));
    /* "No session" is not evidence that there is no hardware (I11) -- same
     * rule the mock and the header both state. */
    out->hardware_encode = CLEONA_VIDEO_HW_NOT_DETERMINABLE;
    out->hardware_decode = CLEONA_VIDEO_HW_NOT_DETERMINABLE;
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

    out->codec_in_use      = (int32_t)iv[0];
    out->hardware_encode   = (int32_t)iv[1];
    out->hardware_decode   = (int32_t)iv[2];
    out->negotiated_width  = (int32_t)iv[3];
    out->negotiated_height = (int32_t)iv[4];
    out->negotiated_fps    = (int32_t)iv[5];
    out->capture_backend   = (int32_t)iv[6];
    out->encode_backend    = (int32_t)iv[7];
    out->frames_captured         = (int64_t)lv[0];
    out->frames_encoded          = (int64_t)lv[1];
    out->frames_dropped_oversize = (int64_t)lv[2];
    out->frames_decoded          = (int64_t)lv[3];
    out->decode_failures         = (int64_t)lv[4];
}
