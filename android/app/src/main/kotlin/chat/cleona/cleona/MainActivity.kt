package chat.cleona.cleona

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.OpenableColumns
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

class MainActivity : FlutterActivity() {
    private val CHANNEL = "chat.cleona/service"
    private val STORAGE_CHANNEL = "chat.cleona/storage"
    private val AUDIO_CHANNEL = "chat.cleona/audio"
    private val AUDIO_PERMISSIONS_CHANNEL = "chat.cleona/audio_permissions"
    private val FOREGROUND_SERVICE_CHANNEL = "chat.cleona/foreground_service"
    private val NOTIFICATION_MSG_CHANNEL = "chat.cleona/notification"
    private val VIBRATION_CHANNEL = "chat.cleona/vibration"
    private val SHARE_CHANNEL = "chat.cleona/share"
    private val UPDATE_CHANNEL = "chat.cleona/update"
    // S363, point 1 (option D): device credential confirmation via
    // `KeyguardManager`. Deliberately NOT `androidx.biometric`:
    //   * the dependency is missing (`android/app/build.gradle.kts` lists
    //     CameraX, concurrent-futures, Guava, security-crypto — no
    //     androidx.biometric, and `pubspec.yaml` no local_auth), and
    //   * `BiometricPrompt` requires a `FragmentActivity`; this class
    //     is `FlutterActivity`, and switching to
    //     `FlutterFragmentActivity` would touch `provideFlutterEngine`,
    //     `configureFlutterEngine` and the engine caching in
    //     `CleonaApplication` — the only risky move in the package.
    // The price: device credential only (PIN/pattern/password), no biometrics.
    private val KEYGUARD_CHANNEL = "chat.cleona/keyguard"
    // No own SESSION_BEHAVIOUR_CHANNEL constant here anymore: the
    // channel name is now defined in CleonaForegroundService.SESSION_BEHAVIOUR_CHANNEL
    // (single source of truth at the place that also makes
    // OUTGOING invokeMethod calls on this channel — see there).
    private val MSG_CHANNEL_ID = "cleona_messages"
    private val CALL_CHANNEL_ID = "cleona_calls"
    private val CALL_NOTIFICATION_ID = 42001
    private val NOTIFICATION_PERMISSION_CODE = 1001

    // ─────────────────────────────────────────────────────────────────────
    // Session behaviour (V1.10, docs/SPEC_VOICE_VIDEO_REWORK.md §7 "V1.10",
    // Cleona_Chat_Architecture_v3_0.md §10.4 "Session behaviour" table).
    // ─────────────────────────────────────────────────────────────────────

    // AudioFocus state (sessionBehaviourChannel, audioFocusRequest,
    // legacyAudioFocusListener, focusInterrupted) lived here until 2026-08-15 as
    // instance fields of this Activity. The same class of error as A-1: the focus
    // did not survive an Activity recreation during an ongoing call,
    // a later abandonAudioFocus became a no-op, other apps'
    // media playback stayed suppressed until the process ended. The fields
    // together with requestCallAudioFocus/abandonCallAudioFocus/onAudioFocusChange
    // have moved to CleonaForegroundService's companion object (see
    // there for the full rationale); the MethodChannel handler in
    // configureFlutterEngine below only calls the static methods
    // there.

    // PROXIMITY_SCREEN_OFF_WAKE_LOCK — held only while the active call route
    // is the earpiece (architecture §10.4, "Proximity": "screen off if and
    // only if the active route is the earpiece"). The decision itself is
    // Dart's (session_behaviour.dart, shouldMonitorProximity); this field
    // only executes it.
    private var proximityWakeLock: PowerManager.WakeLock? = null

    // Bug #U10b — RECORD_AUDIO runtime-permission-flow. We retain the
    // pending MethodChannel.Result across the system permission dialog so
    // the Dart side can await a single bool answer.
    private var pendingAudioPermissionResult: MethodChannel.Result? = null

    companion object {
        private const val REQUEST_AUDIO_PERMISSION = 1002
        private const val REQUEST_INSTALL_PERMISSION = 1003
        private const val REQUEST_CONFIRM_CREDENTIAL = 1004
    }

    // Samsung Auto-Blocker revokes REQUEST_INSTALL_PACKAGES after ~30 min.
    // We await the user's return from the settings screen so the install
    // happens within milliseconds of the grant — timer irrelevant.
    //
    // startActivityForResult + onActivityResult rather than the AndroidX
    // ActivityResultLauncher: FlutterActivity extends the framework Activity,
    // not ComponentActivity, so registerForActivityResult is unavailable here
    // (same request-code pattern as REQUEST_AUDIO_PERMISSION above).
    private var pendingInstallPermissionResult: MethodChannel.Result? = null
    private var pendingKeyguardResult: MethodChannel.Result? = null

    // Bug #U16: ACTION_SEND payload, drained by Dart via `chat.cleona/share`.
    // Shape: {"text": String?, "files": List<String>} (content:// → cacheDir copy).
    private var pendingShare: Map<String, Any>? = null

    // Deep link: cleona:// URI from ACTION_VIEW intent, drained by Dart.
    private var pendingDeepLink: String? = null

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return FlutterEngineCache.getInstance().get(CleonaApplication.ENGINE_ID)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // Engine is owned by CleonaApplication, do not destroy
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Binds libcleona_voice.so through the Java runtime (JNI_OnLoad) and
        // hands the Android voice backend (V1.2) an application context.
        // Without this, cleona_voice_open() always fails with
        // CLEONA_VOICE_ERR_BACKEND — see BUGFIX_CURRENT.md AV-V1.2 §2, addressed
        // to this file's owner (V1.10). install() is idempotent and swallows
        // UnsatisfiedLinkError on purpose (the .so and this line land in two
        // different commits by two different owners), so it is safe to call
        // here even before scripts/build-android-libs.sh ships the library.
        VoiceSession.install(applicationContext)

        // A-6 (MIGRATION §5.4, BUGFIX_CURRENT.md AV-V1.14 §4.2): the same
        // wiring for the video backend. It was MISSING until today —
        // `VideoSession.install()` was called tree-wide only in the
        // conformance harness, which is why `cleona_video_open()` in the
        // real app always returned CLEONA_VIDEO_ERR_BACKEND and every
        // video call since V1.14 was silently audio-only. The finding had to be found via
        // the source code, because this path additionally wrote to no
        // log file (A-5).
        //
        // The TextureRegistry adapter is needed because `VideoSession.kt`
        // deliberately does NOT type against `io.flutter.view.TextureRegistry`:
        // the on-device conformance harness compiles the file without the
        // Flutter classpath and would break on a direct import. It
        // passes `null` and falls back to the headless EGL variant.
        //
        // `flutterEngine.renderer` is the engine's TextureRegistry, and the
        // engine belongs to `CleonaApplication`, not to this Activity (see
        // `cleanUpFlutterEngine` above). It thus survives an
        // Activity recreation — the same ownership question that A-1 hinges on.
        VideoSession.install(
            applicationContext,
            FlutterVideoTextureProvider(flutterEngine.renderer),
        )

        // No camera MethodChannel any more (V3.1): the `chat.cleona/camera`
        // contract existed for the superseded Dart-side capture path
        // (video_capture_android.dart -> CameraXHandler.kt). Capture now lives
        // below the video ABI in VideoSession.kt, where the frames never enter
        // Dart at all (invariant I10, §10.6).

        // ── S363: device credential confirmation ──────────────────────────────
        //
        // The pattern (`startActivityForResult` + `onActivityResult`) already
        // exists in this class — REQUEST_INSTALL_PERMISSION below. No
        // dependency and no new base class is added here.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, KEYGUARD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isDeviceSecure" -> {
                        val km = getSystemService(Context.KEYGUARD_SERVICE) as android.app.KeyguardManager
                        result.success(km.isDeviceSecure)
                    }
                    "confirmDeviceCredential" -> {
                        val km = getSystemService(Context.KEYGUARD_SERVICE) as android.app.KeyguardManager
                        if (!km.isDeviceSecure) {
                            // No screen lock: there is nothing to
                            // confirm. `false` instead of an error, so that
                            // the Dart side takes the same branch as for
                            // a cancellation by the user.
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        val title = call.argument<String>("title")
                        val description = call.argument<String>("description")
                        @Suppress("DEPRECATION")
                        val intent = km.createConfirmDeviceCredentialIntent(title, description)
                        if (intent == null) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        // A still open call is answered before the
                        // next one overwrites it — otherwise the
                        // Dart side hangs forever on a Future that nobody
                        // resolves anymore.
                        pendingKeyguardResult?.success(false)
                        pendingKeyguardResult = result
                        startActivityForResult(intent, REQUEST_CONFIRM_CREDENTIAL)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startForegroundService" -> {
                    val intent = Intent(this, CleonaForegroundService::class.java)
                    startForegroundService(intent)
                    result.success(true)
                }
                "stopForegroundService" -> {
                    val intent = Intent(this, CleonaForegroundService::class.java)
                    stopService(intent)
                    result.success(true)
                }
                "updateServiceNotification" -> {
                    val title = call.argument<String>("title") ?: "Cleona Chat"
                    val text = call.argument<String>("text") ?: ""
                    CleonaForegroundService.updateNotification(this, title, text)
                    result.success(true)
                }
                "acquireWakeLock" -> {
                    CleonaForegroundService.acquireWakeLock()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Storage channel: free disk space query for dynamic Storage Budget
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getFreeDiskSpace" -> {
                    try {
                        val path = call.arguments as? String ?: filesDir.absolutePath
                        val stat = android.os.StatFs(path)
                        result.success(stat.availableBytes)
                    } catch (e: Exception) {
                        result.success(0L)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Audio channel: decode audio to WAV using Android MediaCodec (replaces ffmpeg)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "decodeToWav" -> {
                    val inputPath = call.argument<String>("inputPath")
                    val outputPath = call.argument<String>("outputPath")
                    if (inputPath == null || outputPath == null) {
                        result.error("INVALID_ARGS", "inputPath and outputPath required", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            val success = decodeAudioToWav(inputPath, outputPath)
                            runOnUiThread { result.success(success) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("DECODE_ERROR", e.message, null) }
                        }
                    }.start()
                }
                // "getAudioDiagnostics" was removed with the superseded audio
                // stack (V3.1). It introspected the AEC/NS effects that
                // libcleona_audio attached to a miniaudio capture stream; the
                // native OS voice session reports the same properties in-band
                // through cleona_voice_get_report (I11), where the answer comes
                // from the layer that actually owns the effects.
                else -> result.notImplemented()
            }
        }

        // Notification channel: post message notifications + play sounds
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_MSG_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "postNotification" -> {
                    val title = call.argument<String>("title") ?: "Cleona"
                    val body = call.argument<String>("body") ?: ""
                    val conversationId = call.argument<String>("conversationId") ?: ""
                    postMessageNotification(title, body, conversationId)
                    result.success(null)
                }
                "cancelNotification" -> {
                    val conversationId = call.argument<String>("conversationId") ?: ""
                    val manager = getSystemService(NotificationManager::class.java)
                    manager.cancel(conversationId.hashCode())
                    result.success(null)
                }
                "playSound" -> {
                    val asset = call.argument<String>("asset")
                    if (asset == null) {
                        result.error("INVALID_ARGS", "asset required", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        // A-1: ownership lies with the foreground service
                        // (process-wide), not with this Activity.
                        CleonaForegroundService.playAssetSound(
                            applicationContext, asset)
                        runOnUiThread { result.success(null) }
                    }.start()
                }
                "startLoopSound" -> {
                    val asset = call.argument<String>("asset")
                    if (asset == null) {
                        result.error("INVALID_ARGS", "asset required", null)
                        return@setMethodCallHandler
                    }
                    // A-1: see CleonaForegroundService.startLoopSound —
                    // the player belongs to the process, not to this Activity.
                    // Before, it survived every Activity recreation and was
                    // afterwards only stoppable by ending the process.
                    CleonaForegroundService.startLoopSound(
                        applicationContext, asset)
                    result.success(null)
                }
                "stopSound" -> {
                    CleonaForegroundService.stopLoopSound()
                    result.success(null)
                }
                "setCallAudioMode" -> {
                    val speaker = call.argument<Boolean>("speaker") ?: false
                    setCallAudioMode(speaker)
                    result.success(null)
                }
                "resetCallAudioMode" -> {
                    resetCallAudioMode()
                    result.success(null)
                }
                "updateBadge" -> {
                    val count = call.argument<Int>("count") ?: 0
                    updateBadgeCount(count)
                    result.success(null)
                }
                "showIncomingCall" -> {
                    val callerName = call.argument<String>("callerName") ?: "Unbekannt"
                    val callId = call.argument<String>("callId") ?: ""
                    showIncomingCallNotification(callerName, callId)
                    result.success(true)
                }
                "cancelIncomingCall" -> {
                    val manager = getSystemService(NotificationManager::class.java)
                    manager.cancel(CALL_NOTIFICATION_ID)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Vibration channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VIBRATION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "vibrate" -> {
                    val duration = call.argument<Int>("duration") ?: 200
                    triggerVibration(duration.toLong())
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Share receiver (Bug #U16): Dart drains pending ACTION_SEND payload.
        // Also: getOwnApkPath for "Cleona teilen" direct APK sharing.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "consumePendingShare" -> {
                    val share = pendingShare
                    pendingShare = null
                    result.success(share)
                }
                "getOwnApkPath" -> {
                    try {
                        val appInfo = packageManager.getApplicationInfo(packageName, 0)
                        val srcApk = File(appInfo.sourceDir)
                        val dstApk = File(cacheDir, "cleona-share.apk")
                        srcApk.copyTo(dstApk, overwrite = true)
                        result.success(dstApk.absolutePath)
                    } catch (e: Exception) {
                        result.error("APK_ERROR", e.message, null)
                    }
                }
                "getApkSourcePath" -> {
                    try {
                        val appInfo = packageManager.getApplicationInfo(packageName, 0)
                        result.success(appInfo.sourceDir)
                    } catch (e: Exception) {
                        result.error("APK_ERROR", e.message, null)
                    }
                }
                "consumePendingDeepLink" -> {
                    val link = pendingDeepLink
                    pendingDeepLink = null
                    result.success(link)
                }
                else -> result.notImplemented()
            }
        }

        // §19.6 In-network update: APK install via FileProvider content:// URI
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstallPackages" -> {
                    result.success(packageManager.canRequestPackageInstalls())
                }
                // S388: no update fetching over a metered connection
                // (owner decision 15.09.2026). The system's answer —
                // it covers mobile data AND a Wi-Fi marked as metered.
                "isActiveNetworkMetered" -> {
                    val cm = getSystemService(android.content.Context.CONNECTIVITY_SERVICE)
                        as android.net.ConnectivityManager
                    result.success(cm.isActiveNetworkMetered)
                }
                "openInstallPermissionSettings" -> {
                    val intent = android.content.Intent(
                        android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        android.net.Uri.parse("package:$packageName")
                    )
                    startActivity(intent)
                    result.success(null)
                }
                "requestInstallPermission" -> {
                    if (packageManager.canRequestPackageInstalls()) {
                        result.success(true)
                    } else {
                        pendingInstallPermissionResult?.success(false)
                        pendingInstallPermissionResult = result
                        val intent = android.content.Intent(
                            android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            android.net.Uri.parse("package:$packageName")
                        )
                        startActivityForResult(intent, REQUEST_INSTALL_PERMISSION)
                    }
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("MISSING_PATH", "path argument required", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            val srcFile = File(path)
                            val dstFile = File(cacheDir, "update.apk")
                            srcFile.copyTo(dstFile, overwrite = true)
                            runOnUiThread {
                                try {
                                    val uri = androidx.core.content.FileProvider.getUriForFile(
                                        this, "$packageName.fileprovider", dstFile
                                    )
                                    val intent = android.content.Intent(android.content.Intent.ACTION_VIEW).apply {
                                        setDataAndType(uri, "application/vnd.android.package-archive")
                                        addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                        addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                                    }
                                    startActivity(intent)
                                    result.success("ok")
                                } catch (e: Exception) {
                                    result.error("INSTALL_ERROR", e.message, null)
                                }
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("INSTALL_ERROR", e.message, null)
                            }
                        }
                    }.start()
                }
                "getInstallerPackageName" -> {
                    val installer = if (android.os.Build.VERSION.SDK_INT >= 30) {
                        try {
                            packageManager.getInstallSourceInfo(packageName).installingPackageName
                        } catch (e: Exception) { null }
                    } else {
                        @Suppress("DEPRECATION")
                        packageManager.getInstallerPackageName(packageName)
                    }
                    result.success(installer)
                }
                else -> result.notImplemented()
            }
        }

        // CalendarContract bridge — mirrors Cleona events into the Android
        // system calendar (Samsung / Google Calendar). Opt-in from
        // Settings; runtime-permission flow handled in Kotlin.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CalendarContractHandler.CHANNEL_NAME
        ).setMethodCallHandler(
            CalendarContractHandler(applicationContext, this)
        )

        // Clipboard bridge (Bug #U12) — surfaces binary clipboard items
        // (image/video/audio/file) so mixed clipboards (media + text) no
        // longer drop the media half on Android.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ClipboardHandler.CHANNEL_NAME
        ).setMethodCallHandler(ClipboardHandler(applicationContext))

        // OS Keyring (§3.7): EncryptedSharedPreferences backed by AndroidKeyStore
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            KeyringHandler.CHANNEL_NAME
        ).setMethodCallHandler(KeyringHandler(applicationContext))

        // Audio-permissions bridge (Bug #U10b) — RECORD_AUDIO runtime
        // permission for calls. has* returns the cached state, request*
        // shows the system dialog and resolves once onRequestPermissionsResult
        // fires. Concurrent requests are not supported (single result slot).
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AUDIO_PERMISSIONS_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasRecordAudioPermission" -> {
                    val granted = ContextCompat.checkSelfPermission(
                        this, Manifest.permission.RECORD_AUDIO
                    ) == PackageManager.PERMISSION_GRANTED
                    result.success(granted)
                }
                "requestRecordAudioPermission" -> {
                    if (ContextCompat.checkSelfPermission(
                            this, Manifest.permission.RECORD_AUDIO
                        ) == PackageManager.PERMISSION_GRANTED) {
                        result.success(true)
                    } else {
                        // If a previous request is still pending, fail it
                        // immediately so the new request gets the slot.
                        pendingAudioPermissionResult?.success(false)
                        pendingAudioPermissionResult = result
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.RECORD_AUDIO),
                            REQUEST_AUDIO_PERMISSION
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Foreground-service mic-type promotion bridge (Bug #U10b). Dart
        // calls promoteForCall before _audioEngine.start() so the OS
        // grants the mic stream (API 34+ enforcement) and demoteAfterCall
        // when the call ends so the persistent "microphone in use"
        // indicator goes away.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FOREGROUND_SERVICE_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "promoteForCall" -> {
                    CleonaForegroundService.promoteForCall(this)
                    result.success(true)
                }
                "demoteAfterCall" -> {
                    CleonaForegroundService.demoteAfterCall(this)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Call integration (V3.2): self-managed ConnectionService — architecture
        // §10.4 "Session behaviour" table, row "Call integration"; staging
        // table row 7. Everything lives in CleonaCallIntegration.
        CleonaCallIntegration.register(applicationContext, flutterEngine.dartExecutor.binaryMessenger)

        // Session behaviour (V1.10): AudioFocus, interruption, proximity —
        // architecture §10.4 "Session behaviour" table. requestAudioFocus/
        // abandonAudioFocus redirect to CleonaForegroundService — state
        // and return path to Dart live there, not here (see the
        // field comments above and CleonaForegroundService.kt). This Activity
        // only holds the incoming channel binding for the three methods.
        // setProximityMonitoring stays Activity-local — the WakeLock is
        // defensively released in onDestroy(), see there.
        val behaviourChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CleonaForegroundService.SESSION_BEHAVIOUR_CHANNEL
        )
        behaviourChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestAudioFocus" -> result.success(
                    CleonaForegroundService.requestCallAudioFocus(applicationContext)
                )
                "abandonAudioFocus" -> {
                    CleonaForegroundService.abandonCallAudioFocus(applicationContext)
                    result.success(null)
                }
                "setProximityMonitoring" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    setProximityMonitoring(enabled)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // POST_NOTIFICATIONS Runtime-Permission (API 33+)
        requestNotificationPermission()

        // §12.5 S254: request Doze-whitelist exemption so UDP delivery works
        // in Deep Doze. The system shows its own dialog — no custom UI needed.
        // Delayed by 5s so the notification permission dialog can be dismissed first.
        Handler(Looper.getMainLooper()).postDelayed({
            requestBatteryOptimizationExemption()
        }, 5000)

        // Create message notification channel (separate from foreground service)
        createMessageNotificationChannel()

        ensureForegroundService()

        // Bug #U16: cold-start via Share-Sheet — stash payload for Dart drain.
        // The Activity property `intent` is getIntent(), it contains the ACTION_SEND
        // payload. Before, the local service intent variable was passed here —
        // handleShareIntent discarded it because of the wrong action.
        handleShareIntent(intent)
        handleDeepLinkIntent(intent)
    }

    // §16.2 lifecycle invariant: always re-issue startForegroundService so
    // onStartCommand → startForeground restores the notification after
    // Android 14 user-dismiss or background START_STICKY restart failure.
    override fun onResume() {
        super.onResume()
        ensureForegroundService()
    }

    private fun ensureForegroundService() {
        startForegroundService(Intent(this, CleonaForegroundService::class.java))
    }

    // Defensive release only — a leaked PROXIMITY_SCREEN_OFF_WAKE_LOCK would
    // otherwise survive an Activity recreation the system decided to do
    // outside the configChanges list above (e.g. under memory pressure).
    // No AudioFocus cleanup here: since 2026-08-15 this Activity holds
    // no AudioFocus state at all (see field comment above). The
    // focus lives in CleonaForegroundService, belongs to the call duration, not
    // to the Activity lifetime, and a call keeps running in the foreground service
    // even if this Activity does not exist at the moment (working rule
    // #8) — abandoning here would be wrong, not merely superfluous.
    override fun onDestroy() {
        proximityWakeLock?.let { if (it.isHeld) it.release() }
        proximityWakeLock = null
        super.onDestroy()
    }

    // Warm-launch via Share-Sheet or deep link (singleTop reuses this activity).
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShareIntent(intent)
        handleDeepLinkIntent(intent)
    }

    // Resolves the pending RECORD_AUDIO MethodChannel.Result (Bug #U10b)
    // and otherwise lets the framework propagate to FlutterActivity (which
    // forwards to plugins via the request-permissions registry).
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_AUDIO_PERMISSION) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingAudioPermissionResult?.success(granted)
            pendingAudioPermissionResult = null
        }
    }

    // Resolves the pending REQUEST_INSTALL_PACKAGES MethodChannel.Result once
    // the user returns from ACTION_MANAGE_UNKNOWN_APP_SOURCES. resultCode is
    // always RESULT_CANCELED for that settings screen — the toggle state is
    // what matters, so we re-query the package manager instead. super() first
    // so FlutterActivity keeps forwarding results to plugins.
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_INSTALL_PERMISSION) {
            pendingInstallPermissionResult?.success(
                packageManager.canRequestPackageInstalls()
            )
            pendingInstallPermissionResult = null
        }
        // S363: the result of the device credential confirmation. Here the
        // resultCode really counts (unlike for the permission screen
        // above): RESULT_OK means "the user has identified themselves".
        if (requestCode == REQUEST_CONFIRM_CREDENTIAL) {
            pendingKeyguardResult?.success(resultCode == RESULT_OK)
            pendingKeyguardResult = null
        }
    }

    // Stashes cleona:// deep link URIs for Dart-side consumption.
    private fun handleDeepLinkIntent(intent: Intent?) {
        if (intent?.action != Intent.ACTION_VIEW) return
        val uri = intent.data ?: return
        if (uri.scheme != "cleona") return
        pendingDeepLink = uri.toString()
    }

    // Extracts EXTRA_TEXT + EXTRA_STREAM URIs into `pendingShare`. Content
    // URIs are copied into cacheDir so Dart can read them as file paths.
    private fun handleShareIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action ?: return
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return

        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
        val uris: List<Uri> = when (action) {
            Intent.ACTION_SEND -> {
                @Suppress("DEPRECATION")
                val u = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                if (u != null) listOf(u) else emptyList()
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                @Suppress("DEPRECATION")
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: emptyList()
            }
            else -> emptyList()
        }

        val files = mutableListOf<String>()
        val shareDir = File(cacheDir, "shared_in").apply { mkdirs() }
        for (uri in uris) {
            try {
                val name = queryDisplayName(uri) ?: "share_${System.currentTimeMillis()}"
                val sanitized = name.replace(Regex("[^A-Za-z0-9._-]"), "_")
                val dst = File(shareDir, "${System.currentTimeMillis()}_$sanitized")
                contentResolver.openInputStream(uri)?.use { input ->
                    dst.outputStream().use { output -> input.copyTo(output) }
                }
                if (dst.length() > 0) files.add(dst.absolutePath)
            } catch (_: Exception) { /* skip unreadable URI */ }
        }

        if (text.isNullOrBlank() && files.isEmpty()) return
        pendingShare = mapOf(
            "text" to (text ?: ""),
            "files" to files,
        )
    }

    private fun queryDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) c.getString(0) else null
            }
        } catch (_: Exception) { null }
    }

    private fun createMessageNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                MSG_CHANNEL_ID,
                "Nachrichten",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Benachrichtigungen bei neuen Nachrichten"
                setShowBadge(true)
                enableVibration(true)
            }
            val callChannel = NotificationChannel(
                CALL_CHANNEL_ID,
                "Anrufe",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Eingehende Cleona-Anrufe"
                setSound(null, null)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
            manager.createNotificationChannel(callChannel)
        }
    }

    private fun showIncomingCallNotification(callerName: String, callId: String) {
        val fullScreenIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("incoming_call", true)
            putExtra("call_id", callId)
        }
        val fullScreenPending = PendingIntent.getActivity(
            this, CALL_NOTIFICATION_ID, fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CALL_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(callerName)
            .setContentText("Eingehender Anruf")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setFullScreenIntent(fullScreenPending, true)
            .setAutoCancel(true)
            .setOngoing(true)
            .setTimeoutAfter(60000)
            .build()

        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(CALL_NOTIFICATION_ID, notification)
    }

    private fun postMessageNotification(title: String, body: String, conversationId: String) {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("conversationId", conversationId)
        }
        val pendingIntent = PendingIntent.getActivity(
            this, conversationId.hashCode(), intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        // setGroup ensures message notifications are grouped under the
        // badge-summary posted by updateBadgeCount — without it the summary
        // was a ghost header and tapping it did not dismiss the children.
        val notification = NotificationCompat.Builder(this, MSG_CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setGroup("cleona_messages")
            .build()

        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(conversationId.hashCode(), notification)
    }

    // A-1: `loopingPlayer`, `playAssetSound`, `startLoopSound` and
    // `stopLoopSound` lived here until 2026-08-15 — as instance fields and
    // methods of the Activity. They have moved to
    // `CleonaForegroundService`'s companion object, where they are tied to the
    // process lifetime instead of this Activity (MIGRATION §5.4,
    // finding A-1). The MethodChannel handler above calls them there.

    private fun setCallAudioMode(speaker: Boolean) {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        am.mode = AudioManager.MODE_IN_COMMUNICATION
        @Suppress("DEPRECATION")
        am.isSpeakerphoneOn = speaker
    }

    private fun resetCallAudioMode() {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        am.mode = AudioManager.MODE_NORMAL
        @Suppress("DEPRECATION")
        am.isSpeakerphoneOn = false
    }

    // ─────────────────────────────────────────────────────────────────────
    // Session behaviour (V1.10): AudioFocus. requestCallAudioFocus,
    // abandonCallAudioFocus and onAudioFocusChange lived here until 2026-08-15
    // — as private methods of this Activity. They have moved to
    // CleonaForegroundService's companion object (MIGRATION style
    // like A-1, full rationale there): the focus belongs to the CALL DURATION,
    // not to the Activity lifetime, and previously did not survive an
    // Activity recreation during an ongoing call —
    // with the consequence that a later abandonAudioFocus was a no-op and
    // other apps' media playback stayed suppressed until the process ended. The
    // MethodChannel handler in configureFlutterEngine above calls the
    // static methods there.
    // ─────────────────────────────────────────────────────────────────────

    // Held only while the active route is the earpiece — never while the
    // route is the speaker (architecture §10.4, "Proximity"). The decision
    // itself is Dart's (session_behaviour.dart shouldMonitorProximity); this
    // method only executes it and reports a level-not-supported device
    // explicitly rather than silently no-op-ing (same "never guess, state
    // it" posture as the ABI's I11, applied to this platform corner).
    private fun setProximityMonitoring(enabled: Boolean) {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (!enabled) {
            proximityWakeLock?.let { if (it.isHeld) it.release() }
            proximityWakeLock = null
            return
        }
        if (proximityWakeLock?.isHeld == true) return // already on
        if (!pm.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)) {
            Log.w("Cleona", "PROXIMITY_SCREEN_OFF_WAKE_LOCK not supported on this device")
            return
        }
        @Suppress("DEPRECATION")
        val wl = pm.newWakeLock(
            PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK, "cleona:call-proximity"
        )
        wl.acquire()
        proximityWakeLock = wl
    }

    private fun triggerVibration(durationMs: Long) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            val vibrator = manager.defaultVibrator
            vibrator.vibrate(VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION")
            val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(durationMs)
            }
        }
    }

    private fun updateBadgeCount(count: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            // Update badge via a silent summary notification.
            //
            // Previous bug: no contentIntent + no autoCancel meant the
            // summary was orphaned — tapping the in-tray badge did nothing
            // and it never went away. Now the summary routes to MainActivity
            // and auto-cancels on tap, which also dismisses all grouped
            // message notifications (setGroup on postMessageNotification).
            if (count > 0) {
                val intent = Intent(this, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
                }
                val pendingIntent = PendingIntent.getActivity(
                    this, 0, intent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
                val notification = NotificationCompat.Builder(this, MSG_CHANNEL_ID)
                    .setSmallIcon(R.mipmap.ic_launcher)
                    .setNumber(count)
                    .setGroup("cleona_messages")
                    .setGroupSummary(true)
                    .setContentTitle("Cleona Chat")
                    .setContentText("$count ungelesene Nachrichten")
                    .setSilent(true)
                    .setContentIntent(pendingIntent)
                    .setAutoCancel(true)
                    .build()
                manager.notify(0, notification)
            } else {
                manager.cancel(0)
            }
        }
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    NOTIFICATION_PERMISSION_CODE
                )
            }
        }
    }

    private fun requestBatteryOptimizationExemption() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (pm.isIgnoringBatteryOptimizations(packageName)) return
        try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
        } catch (e: Exception) {
            Log.w("Cleona", "Battery optimization exemption request failed: ${e.message}")
        }
    }

    /// Decode any audio format (AAC/M4A/OGG/MP3) to WAV (16kHz, mono, PCM16)
    /// using Android's MediaExtractor + MediaCodec. No ffmpeg needed.
    private fun decodeAudioToWav(inputPath: String, outputPath: String): Boolean {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(inputPath)

            // Find audio track
            var audioTrackIndex = -1
            var format: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val trackFormat = extractor.getTrackFormat(i)
                val mime = trackFormat.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/")) {
                    audioTrackIndex = i
                    format = trackFormat
                    break
                }
            }
            if (audioTrackIndex < 0 || format == null) return false

            extractor.selectTrack(audioTrackIndex)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: return false

            // Configure decoder
            val codec = MediaCodec.createDecoderByType(mime)
            codec.configure(format, null, null, 0)
            codec.start()

            val pcmOutput = ByteArrayOutputStream()
            val bufferInfo = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            val timeoutUs = 10_000L

            while (!outputDone) {
                // Feed input
                if (!inputDone) {
                    val inputIndex = codec.dequeueInputBuffer(timeoutUs)
                    if (inputIndex >= 0) {
                        val inputBuffer = codec.getInputBuffer(inputIndex) ?: continue
                        val sampleSize = extractor.readSampleData(inputBuffer, 0)
                        if (sampleSize < 0) {
                            codec.queueInputBuffer(inputIndex, 0, 0, 0,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(inputIndex, 0, sampleSize,
                                extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                // Drain output
                val outputIndex = codec.dequeueOutputBuffer(bufferInfo, timeoutUs)
                if (outputIndex >= 0) {
                    if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        outputDone = true
                    }
                    val outputBuffer = codec.getOutputBuffer(outputIndex) ?: continue
                    val chunk = ByteArray(bufferInfo.size)
                    outputBuffer.get(chunk)
                    pcmOutput.write(chunk)
                    codec.releaseOutputBuffer(outputIndex, false)
                }
            }

            // Read output format BEFORE stopping the codec
            val outputFormat = codec.outputFormat
            val sampleRate = outputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            val channels = outputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)

            codec.stop()
            codec.release()

            val rawPcm = pcmOutput.toByteArray()

            // Resample to 16kHz mono if needed
            val mono16k = resamplePcm(rawPcm, sampleRate, channels, 16000, 1)

            // Write WAV file
            writeWavFile(outputPath, mono16k, 16000, 1)
            return true

        } catch (e: Exception) {
            return false
        } finally {
            extractor.release()
        }
    }

    /// PCM channel mixing + resampling for whisper.cpp (16 kHz mono).
    ///
    /// Downsampling MUST low-pass first: a recording at 44.1 kHz decimated to
    /// 16 kHz without a filter folds everything above 8 kHz back into the
    /// speech band (sibilants, mic hiss), which measurably degrades
    /// transcription quality. Linear interpolation alone attenuates those
    /// frequencies far too weakly. ffmpeg (Linux/Windows path) filters
    /// properly — this is the Android equivalent.
    private fun resamplePcm(
        pcm: ByteArray, srcRate: Int, srcChannels: Int,
        dstRate: Int, dstChannels: Int
    ): ByteArray {
        val srcSamples = pcm.size / (2 * srcChannels)
        val srcBuf = ByteBuffer.wrap(pcm).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()

        // Mix to mono if needed
        var mono = ShortArray(srcSamples)
        for (i in 0 until srcSamples) {
            if (srcChannels == 1) {
                mono[i] = srcBuf.get(i)
            } else {
                var sum = 0L
                for (ch in 0 until srcChannels) {
                    sum += srcBuf.get(i * srcChannels + ch)
                }
                mono[i] = (sum / srcChannels).toInt().toShort()
            }
        }

        // Anti-aliasing: only needed when actually decimating.
        if (srcRate > dstRate) {
            // Cutoff at 85% of the destination Nyquist frequency — leaves the
            // speech band intact, kills what would otherwise alias.
            mono = lowPass(mono, srcRate, dstRate * 0.425)
        }

        // Resample via linear interpolation
        val ratio = srcRate.toDouble() / dstRate
        val dstSamples = (srcSamples / ratio).toInt()
        val result = ByteBuffer.allocate(dstSamples * 2).order(ByteOrder.LITTLE_ENDIAN)

        for (i in 0 until dstSamples) {
            val srcPos = i * ratio
            val idx = srcPos.toInt()
            val frac = srcPos - idx
            val s0 = mono[idx.coerceAtMost(srcSamples - 1)]
            val s1 = mono[(idx + 1).coerceAtMost(srcSamples - 1)]
            val sample = (s0 * (1.0 - frac) + s1 * frac).toInt().toShort()
            result.putShort(sample)
        }

        return result.array()
    }

    /// Windowed-sinc FIR low-pass (Blackman window, linear phase).
    ///
    /// 79 taps at a 6.8 kHz cutoff measure flat to 6 kHz (-0.5 dB), -38 to
    /// -43 dB at the 8 kHz fold point and -80 dB and beyond above 10 kHz —
    /// verified for both 44.1 and 48 kHz sources. Cost is 79 multiply-adds per
    /// input sample, which stays well below whisper inference itself.
    private fun lowPass(input: ShortArray, sampleRate: Int, cutoffHz: Double): ShortArray {
        val taps = 79
        val half = taps / 2
        val fc = cutoffHz / sampleRate          // normalized cutoff (cycles/sample)
        val kernel = DoubleArray(taps)
        var sum = 0.0
        for (i in 0 until taps) {
            val n = i - half
            val sinc = if (n == 0) 2.0 * fc
                       else Math.sin(2.0 * Math.PI * fc * n) / (Math.PI * n)
            // Blackman window
            val w = 0.42 - 0.5 * Math.cos(2.0 * Math.PI * i / (taps - 1)) +
                    0.08 * Math.cos(4.0 * Math.PI * i / (taps - 1))
            kernel[i] = sinc * w
            sum += kernel[i]
        }
        // Normalize to unity DC gain so the filter does not change loudness.
        for (i in 0 until taps) kernel[i] /= sum

        val output = ShortArray(input.size)
        for (i in input.indices) {
            var acc = 0.0
            for (k in 0 until taps) {
                val idx = i + k - half
                if (idx < 0 || idx >= input.size) continue  // zero-padded edges
                acc += input[idx] * kernel[k]
            }
            output[i] = acc.toInt().coerceIn(-32768, 32767).toShort()
        }
        return output
    }

    /// Write PCM data as WAV file (standard 44-byte header).
    private fun writeWavFile(path: String, pcm: ByteArray, sampleRate: Int, channels: Int) {
        val bitsPerSample = 16
        val byteRate = sampleRate * channels * bitsPerSample / 8
        val blockAlign = channels * bitsPerSample / 8
        val dataSize = pcm.size
        val fileSize = 36 + dataSize

        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        // RIFF header
        header.put("RIFF".toByteArray())
        header.putInt(fileSize)
        header.put("WAVE".toByteArray())
        // fmt chunk
        header.put("fmt ".toByteArray())
        header.putInt(16) // chunk size
        header.putShort(1) // PCM format
        header.putShort(channels.toShort())
        header.putInt(sampleRate)
        header.putInt(byteRate)
        header.putShort(blockAlign.toShort())
        header.putShort(bitsPerSample.toShort())
        // data chunk
        header.put("data".toByteArray())
        header.putInt(dataSize)

        val file = File(path)
        file.outputStream().use { out ->
            out.write(header.array())
            out.write(pcm)
        }
    }
}

/**
 * Thin adapter from Flutter's [TextureRegistry] to the flutter-free
 * seam type [VideoTextureProvider] from `VideoSession.kt`.
 *
 * Wording following the former BUILD_REQUEST_V1.14 §4.2
 * (BUGFIX_CURRENT.md AV-V1.14).
 */
private class FlutterVideoTextureProvider(
    private val registry: TextureRegistry,
) : VideoTextureProvider {
    override fun createSurfaceTexture(): VideoTextureEntry {
        val entry = registry.createSurfaceTexture()
        return object : VideoTextureEntry {
            override fun id() = entry.id()
            override fun surfaceTexture() = entry.surfaceTexture()
            override fun release() = entry.release()
        }
    }
}
