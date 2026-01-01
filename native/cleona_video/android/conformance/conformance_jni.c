/* conformance_jni.c — runs the V0.4 video conformance harness inside an app
 * process.
 *
 * Work package: docs/SPEC_VOICE_VIDEO_REWORK.md V1.14 (acceptance).
 *
 * Identical rationale to native/cleona_voice/android/conformance/conformance_jni.c
 * (V1.2): the harness is normally a command-line binary pushed to
 * /data/local/tmp (native/cleona_video/test/CMakeLists.txt, route A). That
 * works for a pure-native backend. This one is not: Camera2's CameraManager
 * needs a Context and, for the decode direction, a texture surface -- an
 * `adb shell` process has neither. So the unmodified harness sources are
 * compiled into a library and this shim calls their main() from inside an app
 * process. The harness itself is untouched -- this file only supplies argv
 * and a place for its stdout to go.
 */

#include <jni.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include <android/log.h>

#define TAG "CleonaVideoConf"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

/* conformance.c. Declared rather than included: the harness has no header for
 * its entry point, and it must stay exactly as V0.4 wrote it. */
extern int main(int argc, char** argv);

#define MAX_ARGV 8

JNIEXPORT jint JNICALL
Java_chat_cleona_videoconformance_ConformanceRunner_runNative(
    JNIEnv* env, jobject thiz,
    jstring j_out, jstring j_json, jboolean shipping, jstring j_expect_fail) {

    const char* out_path = NULL;
    const char* json_path = NULL;
    const char* expect_fail = NULL;
    char* argv[MAX_ARGV];
    int argc = 0;
    int rc;

    (void)thiz;

    if (j_out == NULL) {
        LOGE("no output path");
        return 2;
    }
    out_path = (*env)->GetStringUTFChars(env, j_out, NULL);
    if (out_path == NULL) return 2;

    if (j_json != NULL) json_path = (*env)->GetStringUTFChars(env, j_json, NULL);
    if (j_expect_fail != NULL) {
        expect_fail = (*env)->GetStringUTFChars(env, j_expect_fail, NULL);
    }

    /* An app process has no usable stdout -- it goes to /dev/null. Redirect
     * both streams to the file the caller will read back with adb. */
    if (freopen(out_path, "w", stdout) == NULL) {
        LOGE("freopen(%s) failed", out_path);
        (*env)->ReleaseStringUTFChars(env, j_out, out_path);
        if (json_path) (*env)->ReleaseStringUTFChars(env, j_json, json_path);
        if (expect_fail) (*env)->ReleaseStringUTFChars(env, j_expect_fail, expect_fail);
        return 2;
    }
    setvbuf(stdout, NULL, _IOLBF, 0);
    dup2(fileno(stdout), STDERR_FILENO);

    /* argv[0] is skipped by the harness's own parser; a non-option argument
     * would be taken as a backend library path, which LINK mode rejects. */
    argv[argc++] = (char*)"cleona_video_conformance";
    if (shipping) argv[argc++] = (char*)"--shipping";
    if (json_path != NULL && json_path[0] != '\0') {
        argv[argc++] = (char*)"--json";
        argv[argc++] = (char*)json_path;
    }
    if (expect_fail != NULL && expect_fail[0] != '\0') {
        argv[argc++] = (char*)"--expect-fail";
        argv[argc++] = (char*)expect_fail;
    }
    argv[argc] = NULL;

    LOGI("running video conformance harness, argc=%d", argc);
    rc = main(argc, argv);
    LOGI("video conformance harness exit=%d", rc);

    fflush(stdout);
    fflush(stderr);

    (*env)->ReleaseStringUTFChars(env, j_out, out_path);
    if (json_path) (*env)->ReleaseStringUTFChars(env, j_json, json_path);
    if (expect_fail) (*env)->ReleaseStringUTFChars(env, j_expect_fail, expect_fail);
    return (jint)rc;
}
