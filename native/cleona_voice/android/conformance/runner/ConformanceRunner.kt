package chat.cleona.voiceconformance

import android.app.Activity
import android.os.Bundle
import android.util.Log
import chat.cleona.cleona.VoiceSession
import java.io.File

/**
 * Native entry point of the V0.4 conformance harness.
 *
 * Declared in its own object so that the JNI symbol
 * `Java_chat_cleona_voiceconformance_ConformanceRunner_runNative` is fixed by
 * one small, stable class rather than by an Android component.
 *
 * Deliberately **not** `@JvmStatic`: for an `external` member of an object that
 * annotation makes it ambiguous whether the native method is the instance one
 * or the generated static bridge, and the two differ in the second JNI
 * parameter. As a plain member it is unambiguously the instance method, which
 * is what `conformance_jni.c` is written against.
 */
object ConformanceRunner {
    external fun runNative(
        outPath: String,
        jsonPath: String,
        shipping: Boolean,
        expectFail: String,
    ): Int
}

/**
 * On-device host for the conformance harness — work package V1.2.
 *
 * SPEC §10 gate 4 requires the conformance test to be green "on the target
 * platform". On Android the backend is only reachable through the Java API
 * (§10.4), so it needs three things an `adb shell` process cannot provide: an
 * ART runtime, an application `Context` for `AudioManager`, and a real
 * RECORD_AUDIO grant. This activity provides exactly those and nothing else —
 * it is a container for the harness, not a second implementation of it.
 *
 * It links the **same** `VoiceSession` class the app ships, from
 * `android/app/src/main/kotlin/chat/cleona/cleona/VoiceSession.kt`. Certifying
 * a copy would certify the copy.
 *
 * Launch (see conformance/run_conformance.sh):
 *
 *     am start -n chat.cleona.voiceconformance/.ConformanceActivity \
 *              --ez shipping true [--es expectFail C3]
 */
class ConformanceActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val shipping = intent?.getBooleanExtra(EXTRA_SHIPPING, true) ?: true
        val expectFail = intent?.getStringExtra(EXTRA_EXPECT_FAIL) ?: ""

        // filesDir, not the external one: on API 30+ /sdcard/Android/data is not
        // reliably readable from `adb shell`, whereas `run-as` reads this
        // directory on emulator and device alike because the APK is debuggable.
        val dir = filesDir
        val txt = File(dir, "conformance.txt")
        val json = File(dir, "conformance.json")
        val done = File(dir, "conformance.done")
        listOf(txt, json, done).forEach { runCatching { it.delete() } }

        Log.i(TAG, "output ${dir.absolutePath} shipping=$shipping expectFail='$expectFail'")

        // Off the main thread: the harness blocks for tens of seconds in
        // capture_read, and a blocked main thread would be killed by the
        // watchdog long before check 3 completed.
        Thread({
            var code = 2
            try {
                // Loads libcleona_voice.so THROUGH the runtime, which is what
                // makes ART call JNI_OnLoad and hand the backend its JavaVM,
                // and supplies the Context AudioManager needs. Exactly the call
                // the app has to make at start-up (BUILD_REQUEST_V1.2.md §2).
                VoiceSession.install(applicationContext)
                System.loadLibrary("cleona_voice_conformance")
                code = ConformanceRunner.runNative(
                    txt.absolutePath, json.absolutePath, shipping, expectFail
                )
            } catch (t: Throwable) {
                Log.e(TAG, "conformance run failed", t)
                runCatching { txt.appendText("FATAL host error: ${t.stackTraceToString()}\n") }
            } finally {
                Log.i(TAG, "conformance exit=$code")
                runCatching { done.writeText(code.toString()) }

                // Drop the task BEFORE killing the process. Without this,
                // ActivityManager sees a foreground activity whose process
                // died and dutifully restarts it: the device run logged two
                // PIDs (20557, then 20772 one second later) for a single
                // `am start`. The relaunch then deletes conformance.txt/json in
                // onCreate — which can happen between the script seeing
                // conformance.done and reading the output next to it. A rig
                // that can hand back a truncated result is the same class of
                // problem as one that certifies the wrong APK.
                runCatching { runOnUiThread { finishAndRemoveTask() } }
                Thread.sleep(300)

                // halt, not exit: shutdown hooks would race the audio threads,
                // and the exit code is the result we came for.
                Runtime.getRuntime().halt(code)
            }
        }, "conformance").start()
    }

    companion object {
        private const val TAG = "CleonaVoiceConf"
        const val EXTRA_SHIPPING = "shipping"
        const val EXTRA_EXPECT_FAIL = "expectFail"
    }
}
