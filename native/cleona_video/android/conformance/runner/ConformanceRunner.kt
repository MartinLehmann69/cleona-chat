package chat.cleona.videoconformance

import android.app.Activity
import android.os.Bundle
import android.util.Log
import chat.cleona.cleona.VideoSession
import java.io.File

/**
 * Native entry point of the V0.4 conformance harness (video variant).
 *
 * See native/cleona_voice/android/conformance/runner/ConformanceRunner.kt for
 * why this is a plain member of a stable `object` rather than `@JvmStatic`.
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
 * On-device host for the video conformance harness — work package V1.14.
 *
 * SPEC §10 gate 4 requires the conformance test to be green "on the target
 * platform". On Android the backend is only reachable through the Java API
 * (Camera2's `CameraManager` needs a `Context`), so this activity provides
 * exactly that and nothing else — a container for the harness, not a second
 * implementation of it.
 *
 * It links the SAME `VideoSession` class the app ships, from
 * `android/app/src/main/kotlin/chat/cleona/cleona/VideoSession.kt`. Certifying
 * a copy would certify the copy.
 *
 * No `VideoTextureProvider` is installed here (this is a plain
 * `android.app.Activity`, not a Flutter one) — `VideoSession`'s headless EGL
 * fallback (see its `HeadlessTexture` class) is exactly what makes the decode
 * direction exercisable outside a Flutter engine.
 *
 * Launch (see conformance/run_conformance.sh):
 *
 *     am start -n chat.cleona.videoconformance/.ConformanceActivity \
 *              --ez shipping true [--es expectFail V7]
 */
class ConformanceActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val shipping = intent?.getBooleanExtra(EXTRA_SHIPPING, true) ?: true
        val expectFail = intent?.getStringExtra(EXTRA_EXPECT_FAIL) ?: ""

        // filesDir, not the external one -- see the voice runner's identical
        // comment for why `run-as` needs this directory specifically.
        val dir = filesDir
        val txt = File(dir, "conformance.txt")
        val json = File(dir, "conformance.json")
        val done = File(dir, "conformance.done")
        listOf(txt, json, done).forEach { runCatching { it.delete() } }

        Log.i(TAG, "output ${dir.absolutePath} shipping=$shipping expectFail='$expectFail'")

        // Off the main thread: the harness blocks for tens of seconds across
        // camera open, encode/decode phases and reconfigure round-trips, and a
        // blocked main thread would be killed by the watchdog long before it
        // finished.
        Thread({
            var code = 2
            try {
                // No TextureRegistry passed -- see the class doc. Loads
                // libcleona_video.so THROUGH the runtime, which is what makes
                // ART call JNI_OnLoad and hand the backend its JavaVM, and
                // supplies the Context CameraManager needs. Exactly the call
                // the app has to make at start-up (BUILD_REQUEST_V1.14.md §2).
                VideoSession.install(applicationContext, null)
                System.loadLibrary("cleona_video_conformance")
                code = ConformanceRunner.runNative(
                    txt.absolutePath, json.absolutePath, shipping, expectFail
                )
            } catch (t: Throwable) {
                Log.e(TAG, "conformance run failed", t)
                runCatching { txt.appendText("FATAL host error: ${t.stackTraceToString()}\n") }
            } finally {
                Log.i(TAG, "conformance exit=$code")
                runCatching { done.writeText(code.toString()) }

                // Drop the task BEFORE killing the process -- see
                // BUILD_REQUEST_V1.2.md's identical finding for the voice
                // runner: without this, ActivityManager restarts the activity
                // when its process dies, and the restart deletes
                // conformance.txt/json in onCreate in exactly the window the
                // script might be reading them.
                runCatching { runOnUiThread { finishAndRemoveTask() } }
                Thread.sleep(300)

                // halt, not exit: shutdown hooks would race the camera/codec
                // threads, and the exit code is the result we came for.
                Runtime.getRuntime().halt(code)
            }
        }, "conformance").start()
    }

    companion object {
        private const val TAG = "CleonaVideoConf"
        const val EXTRA_SHIPPING = "shipping"
        const val EXTRA_EXPECT_FAIL = "expectFail"
    }
}
