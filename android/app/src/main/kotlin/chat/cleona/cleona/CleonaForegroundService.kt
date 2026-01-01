package chat.cleona.cleona

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.content.res.AssetFileDescriptor
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import java.io.File

class CleonaForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "cleona_service"
        const val NOTIFICATION_ID = 1
        private const val TAG = "CleonaWatchdog"
        private const val WATCHDOG_INTERVAL_MS = 120_000L
        private const val WATCHDOG_GRACE_MS = 240_000L
        private const val HEARTBEAT_STALE_MS = 180_000L

        // Bug #U10b — singleton ref so MainActivity can promote/demote the
        // running service to MICROPHONE foreground-service-type at call
        // start/stop. CleonaForegroundService is started once at app boot
        // and persists for the process lifetime, so a single var is safe.
        @Volatile
        var instance: CleonaForegroundService? = null
            private set

        // ─── A-1: the ringtone belongs to the PROCESS, not the Activity ───
        //
        // Finding A-1 (MIGRATION §5.4, field RCA of 2026-08-07, Pixel 8 Pro):
        // the MediaPlayer was an instance field in `MainActivity`. After an
        // Activity recreation — app swiped from Recents and restarted,
        // same PID — the field of the NEW instance was `null`,
        // every `stopSound` thus a no-op, and the old player kept running until
        // the process ended. Re-measured on the device:
        // `wm_on_destroy_called` + same PID + new `wm_on_create_called`.
        //
        // Why HERE and not in the Activity: §5.4 requires that
        // platform-side media resources are owned process-wide. The
        // foreground service is the only lifetime on Android that matches the
        // Dart side (working rule #8, architecture §7.8/§16.2) — and
        // the field lives in the `companion object`, so it is still
        // the same even when the service recreates its instance. It is
        // thus tied to the process lifetime, not to an object lifetime.
        //
        // The context ALWAYS comes in as `applicationContext`, never as
        // Activity — otherwise ownership would only be moved, not solved.
        private const val SOUND_TAG = "CleonaSound"

        @Volatile
        private var loopingPlayer: MediaPlayer? = null

        /// Start ringtone (endless loop). A tone already playing
        /// is stopped first — multiple calls never create two players.
        @JvmStatic
        fun startLoopSound(context: Context, asset: String) {
            stopLoopSound()
            try {
                val afd: AssetFileDescriptor =
                    context.applicationContext.assets.openFd("flutter_assets/$asset")
                val mp = MediaPlayer()
                mp.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                afd.close()
                mp.isLooping = true
                mp.prepare()
                mp.start()
                loopingPlayer = mp
                Log.i(SOUND_TAG, "loop started: $asset")
            } catch (e: Exception) {
                // A-5: this used to be a silent `catch (e: Exception) {}`
                // with the comment "Sound playback is non-fatal". Non-fatal
                // does not mean invisible: that the sound path logged NOTHING
                // is the reason why A-1 could only be found by ear and A-6 only via
                // the source code.
                Log.w(SOUND_TAG, "loop start failed: $asset", e)
            }
        }

        /// Stop ringtone. Idempotent — without a playing tone it has no effect.
        @JvmStatic
        fun stopLoopSound() {
            val mp = loopingPlayer
            loopingPlayer = null
            if (mp == null) {
                Log.d(SOUND_TAG, "loop stop: nothing playing")
                return
            }
            try {
                if (mp.isPlaying) mp.stop()
                mp.release()
                Log.i(SOUND_TAG, "loop stopped")
            } catch (e: Exception) {
                Log.w(SOUND_TAG, "loop stop failed", e)
            }
        }

        /// Play a one-shot tone (notification). No shared
        /// state — the player cleans up after itself.
        @JvmStatic
        fun playAssetSound(context: Context, asset: String) {
            try {
                val afd: AssetFileDescriptor =
                    context.applicationContext.assets.openFd("flutter_assets/$asset")
                val mp = MediaPlayer()
                mp.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                afd.close()
                mp.prepare()
                mp.start()
                mp.setOnCompletionListener { it.release() }
            } catch (e: Exception) {
                Log.w(SOUND_TAG, "one-shot failed: $asset", e)
            }
        }

        // ─── AudioFocus belongs to the CALL, not the Activity ───
        //
        // The same finding as A-1 above, this time for audio focus instead of
        // the ringtone: `MainActivity` held `audioFocusRequest` and
        // `legacyAudioFocusListener` as instance fields. After an
        // Activity recreation during an ongoing call — app swiped from
        // Recents — the field of the NEW instance was `null`, a
        // later `abandonAudioFocus` thus a no-op, and the old
        // focus grant persisted until the process ended: other apps'
        // media playback stayed suppressed.
        //
        // Why HERE and not via `abandon` in `onDestroy()`: the focus
        // belongs to the CALL DURATION, not to the Activity lifetime — a
        // call keeps running in the foreground service even if the Activity
        // does not exist at the moment (working rule #8). An `abandon` in
        // `onDestroy()` would even be wrong: one would give up the focus in the
        // middle of a conversation just because the Activity is briefly gone. Therefore
        // the state lives in the `companion object`, not in the
        // service INSTANCE — just like `instance` and `loopingPlayer` above
        // it is thus tied to the process lifetime, not to an object lifetime.
        //
        // `focusInterrupted` moves along: it is part of the same
        // state machine (set in requestCallAudioFocus, read and
        // cleared in onAudioFocusChange, cleared in
        // abandonCallAudioFocus) and suffers from the same failure mode — if it stayed
        // in the Activity, an Activity recreation would reset it to
        // `false` although the focus is in fact still
        // interrupted, and a real AUDIOFOCUS_GAIN would then wrongly
        // be discarded as "no end of interruption".
        //
        // Return path to Dart: `onAudioFocusChange` does NOT call back via an
        // Activity — that would bind the service to a possibly dead
        // Activity, a leak in the other direction. Instead
        // `invokeSessionBehaviour` fetches the FlutterEngine directly from the
        // `FlutterEngineCache` (key `CleonaApplication.ENGINE_ID`) —
        // the same engine that `CleonaApplication.onCreate()` creates once
        // and that survives every Activity recreation (see
        // `MainActivity.getFlutterEngine()`, which reads the same cache entry).
        // Therefore no register/unregister callback is needed
        // between Activity and service: the receiver on the Dart side
        // is bound to the process, not to an Activity instance.
        // `SESSION_BEHAVIOUR_CHANNEL` is therefore defined here, no longer
        // in `MainActivity` — single source of truth at the place that now
        // sends.
        const val SESSION_BEHAVIOUR_CHANNEL = "chat.cleona/session_behaviour"

        private const val FOCUS_TAG = "CleonaAudioFocus"

        private val focusMainHandler = Handler(Looper.getMainLooper())

        @Volatile
        private var audioFocusRequest: AudioFocusRequest? = null

        @Suppress("DEPRECATION")
        @Volatile
        private var legacyAudioFocusListener: AudioManager.OnAudioFocusChangeListener? = null

        // True from AUDIOFOCUS_LOSS_TRANSIENT(_CAN_DUCK) until the matching
        // AUDIOFOCUS_GAIN — the round trip this class turns into
        // onInterruptionBegin/onInterruptionEnd. A plain AUDIOFOCUS_LOSS
        // (another app took focus for good, not just transiently) begins an
        // interruption but is not expected to end with a GAIN of our own, so
        // it does not set this flag — see onAudioFocusChange.
        @Volatile
        private var focusInterrupted = false

        /// Request focus for the call duration (AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE,
        /// architecture §10.4 "Session behaviour" table). EXCLUSIVE instead of
        /// plain GAIN_TRANSIENT, because a call is not "background music that
        /// may become a bit quieter", but what is supposed to be audible.
        @JvmStatic
        fun requestCallAudioFocus(context: Context): Boolean {
            val am = context.applicationContext
                .getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val listener = AudioManager.OnAudioFocusChangeListener { onAudioFocusChange(it) }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val attrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
                val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
                    .setAudioAttributes(attrs)
                    .setOnAudioFocusChangeListener(listener)
                    .build()
                val rc = am.requestAudioFocus(request)
                val granted = rc == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
                if (granted) {
                    audioFocusRequest = request
                    focusInterrupted = false
                    Log.i(FOCUS_TAG, "focus acquired (AudioFocusRequest)")
                } else {
                    Log.w(FOCUS_TAG, "focus request denied (AudioFocusRequest) rc=$rc")
                }
                return granted
            }

            // API 24-25: no AudioFocusRequest class. Same duration hint via
            // the deprecated overload — the same legacy path as before in
            // MainActivity, taken over unchanged.
            @Suppress("DEPRECATION")
            val rc = am.requestAudioFocus(
                listener, AudioManager.STREAM_VOICE_CALL,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE
            )
            val granted = rc == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            if (granted) {
                legacyAudioFocusListener = listener
                focusInterrupted = false
                Log.i(FOCUS_TAG, "focus acquired (legacy)")
            } else {
                Log.w(FOCUS_TAG, "focus request denied (legacy) rc=$rc")
            }
            return granted
        }

        /// Give the focus back. Idempotent — without held focus it has no effect
        /// (may e.g. arrive twice from Dart if a call aborts during
        /// teardown).
        @JvmStatic
        fun abandonCallAudioFocus(context: Context) {
            val am = context.applicationContext
                .getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val request = audioFocusRequest
                if (request == null) {
                    Log.d(FOCUS_TAG, "abandon: nothing held (AudioFocusRequest)")
                } else {
                    am.abandonAudioFocusRequest(request)
                    audioFocusRequest = null
                    Log.i(FOCUS_TAG, "focus abandoned (AudioFocusRequest)")
                }
            } else {
                @Suppress("DEPRECATION")
                val listener = legacyAudioFocusListener
                if (listener == null) {
                    Log.d(FOCUS_TAG, "abandon: nothing held (legacy)")
                } else {
                    @Suppress("DEPRECATION")
                    am.abandonAudioFocus(listener)
                    legacyAudioFocusListener = null
                    Log.i(FOCUS_TAG, "focus abandoned (legacy)")
                }
            }
            focusInterrupted = false
        }

        // Runs on whichever thread the platform delivers focus changes on
        // (documented as an arbitrary thread; in practice the main thread on
        // all tested API levels, but not guaranteed) — invokeMethod requires
        // the platform thread, hence invokeSessionBehaviour's
        // focusMainHandler.post rather than a bare call.
        private fun onAudioFocusChange(focusChange: Int) {
            when (focusChange) {
                AudioManager.AUDIOFOCUS_LOSS,
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                    // I2/I6: nothing here touches VoiceSession. This only
                    // tells Dart that a foreign call/app took the session, so
                    // the UI can show it (§10.4, "behaves like a telephony
                    // call").
                    focusInterrupted = true
                    Log.i(FOCUS_TAG, "onAudioFocusChange: LOSS-family ($focusChange) — interruption begin")
                    invokeSessionBehaviour("onInterruptionBegin", null)
                }
                AudioManager.AUDIOFOCUS_GAIN -> {
                    // Only an "interruption ended" if we were actually
                    // interrupted — the very first GAIN after a successful
                    // request also arrives here on some OEMs and must not be
                    // reported as an end-of-interruption with nothing to end.
                    if (focusInterrupted) {
                        focusInterrupted = false
                        Log.i(FOCUS_TAG, "onAudioFocusChange: GAIN — interruption end")
                        invokeSessionBehaviour(
                            "onInterruptionEnd",
                            // Android has no separate "should resume" signal —
                            // AUDIOFOCUS_GAIN itself IS the resume signal
                            // (session_behaviour.dart, InterruptionEndInfo).
                            mapOf("shouldResume" to true)
                        )
                    } else {
                        Log.d(FOCUS_TAG, "onAudioFocusChange: GAIN — initial grant, no interruption to end")
                    }
                }
                else -> Log.i(FOCUS_TAG, "onAudioFocusChange: unhandled focusChange=$focusChange")
            }
        }

        // No Activity return path (see the comment block at the top of this
        // section): the FlutterEngine lives process-wide in the
        // FlutterEngineCache, set once in
        // CleonaApplication.onCreate() and survives every
        // Activity recreation. A missing cache entry is only possible in the
        // window between process start and CleonaApplication.onCreate()
        // — no call can be running there anyway, so no
        // focus change can occur either.
        private fun invokeSessionBehaviour(method: String, args: Map<String, Any>?) {
            val engine = FlutterEngineCache.getInstance().get(CleonaApplication.ENGINE_ID)
            if (engine == null) {
                Log.w(FOCUS_TAG, "$method dropped — engine not cached yet")
                return
            }
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, SESSION_BEHAVIOUR_CHANNEL)
            focusMainHandler.post {
                try {
                    channel.invokeMethod(method, args)
                } catch (e: Throwable) {
                    Log.e(FOCUS_TAG, "invokeMethod($method) failed", e)
                }
            }
        }

        /// API 30+: re-call startForeground with the bitmask
        /// DATA_SYNC | MICROPHONE so the OS lets the process keep an
        /// AudioRecord stream open while in the background. Required by
        /// API 34+ when RECORD_AUDIO is used from a foreground service.
        fun promoteForCall(context: Context) {
            instance?._promoteForCall()
        }

        /// Demote back to DATA_SYNC after the call so the OS no longer
        /// shows the persistent "microphone in use" indicator.
        fun demoteAfterCall(context: Context) {
            instance?._demoteAfterCall()
        }

        /// §12.5 S254: re-acquire the timed WakeLock (30s) to keep the CPU
        /// active during a packet-processing window. Called from the Dart
        /// heartbeat timer on each tick to extend the lock while the isolate
        /// is alive. No-op if the service is not running.
        fun acquireWakeLock() {
            instance?.wakeLock?.acquire(30_000L)
        }

        // Cached title/text so createNotification() renders the last known
        // live status instead of the hard-coded default after onStartCommand
        // re-issues startForeground (Android 14 dismiss restore path).
        @Volatile var cachedTitle: String = "Cleona Chat"
            private set
        @Volatile var cachedText: String = "Verbinde…"
            private set

        /// Update the foreground notification text from anywhere.
        fun updateNotification(context: Context, title: String, text: String) {
            cachedTitle = title
            cachedText = text
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context, 0, intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )

            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(text)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setOngoing(true)
                .setContentIntent(pendingIntent)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setShowWhen(false)
                .build()

            val manager = context.getSystemService(NotificationManager::class.java)
            manager.notify(NOTIFICATION_ID, notification)
        }
    }

    private val watchdogHandler = Handler(Looper.getMainLooper())
    private val watchdogRunnable = object : Runnable {
        override fun run() {
            checkDartHeartbeat()
            watchdogHandler.postDelayed(this, WATCHDOG_INTERVAL_MS)
        }
    }

    // §16.2 lifecycle invariants (V3.1.117): the foreground-service type the
    // service should currently run under. _promoteForCall/_demoteAfterCall
    // toggle the MICROPHONE bit; onStartCommand re-issues startForeground
    // with this field so a promotion survives an OS restart of the service.
    @Volatile
    private var desiredType: Int = 0

    // True while the watchdog has replaced the notification with the
    // degraded "pausiert" text; cleared when a fresh heartbeat is seen.
    private var pausedNotificationShown = false

    // §12.5 S254: timed PARTIAL_WAKE_LOCK keeps the CPU active during
    // incoming-packet processing. 30s timeout prevents battery drain if
    // the release call is missed. Reference-counted so nested acquires
    // extend rather than conflict.
    private var wakeLock: PowerManager.WakeLock? = null

    private fun baseServiceType(): Int = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE ->
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ->
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        else -> 0
    }

    // Idempotent startForeground with the current desiredType. Never lets a
    // failure terminate the service: a rejected typed call falls back to the
    // untyped 2-arg form; a total failure is logged and the service keeps
    // running (the OS decides its fate — a service must not kill itself from
    // inside its own lifecycle, that recreates the restart loop).
    private fun startForegroundWithDesiredType() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && desiredType != 0) {
                startForeground(NOTIFICATION_ID, createNotification(), desiredType)
            } else {
                startForeground(NOTIFICATION_ID, createNotification())
            }
        } catch (e: Exception) {
            Log.e(TAG, "startForeground(type=$desiredType) failed: ${e.message} — falling back to untyped")
            try {
                startForeground(NOTIFICATION_ID, createNotification())
            } catch (e2: Exception) {
                Log.e(TAG, "untyped startForeground failed: ${e2.message} — continuing without promotion")
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
        // Fresh service start: a stale heartbeat file from a crashed previous
        // instance must not feed the watchdog before Dart stamps again.
        try {
            File(applicationContext.filesDir, ".cleona/.dart-heartbeat").delete()
        } catch (_: Exception) {}
        watchdogHandler.postDelayed(watchdogRunnable, WATCHDOG_GRACE_MS)
        // Boot as SPECIAL_USE (no time limit, API 34+) or DATA_SYNC (pre-34).
        // _promoteForCall() upgrades to MICROPHONE on demand.
        desiredType = baseServiceType()
        startForegroundWithDesiredType()
        // §12.5 S254: timed PARTIAL_WAKE_LOCK for incoming-packet processing.
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "cleona:fgs-packet-processing"
        ).apply {
            setReferenceCounted(false)
            acquire(30_000L)
        }
    }

    override fun onDestroy() {
        watchdogHandler.removeCallbacks(watchdogRunnable)
        try { wakeLock?.release() } catch (_: Exception) {}
        wakeLock = null
        if (instance === this) instance = null
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // §16.2: re-issue startForeground on every entry — no "already
        // running" short-circuit. After an OS kill + START_STICKY restart
        // this is the path that restores the foreground promotion.
        if (desiredType == 0) desiredType = baseServiceType()
        startForegroundWithDesiredType()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // Bug #U10b — re-call startForeground with the desired type bitmask.
    // The 3-arg form is API 29+ (Q). On older Android we fall back to the
    // 2-arg form, which means MICROPHONE-while-backgrounded won't be
    // honored — but minSdk in app/build.gradle.kts is high enough that
    // this branch is informational.
    private fun _promoteForCall() {
        desiredType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            baseServiceType() or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        } else 0
        startForegroundWithDesiredType()
    }

    private fun _demoteAfterCall() {
        desiredType = baseServiceType()
        startForegroundWithDesiredType()
    }

    // §16.2: the watchdog never kills the process — a service killing itself
    // from inside its own lifecycle recreates the OS-restart loop (Problem 10).
    // A stale Dart heartbeat degrades the notification to "pausiert" so the
    // user sees delivery has stopped; a fresh heartbeat restores it (Dart
    // overwrites with live status via updateServiceNotification anyway).
    private fun checkDartHeartbeat() {
        try {
            val heartbeatFile = File(applicationContext.filesDir, ".cleona/.dart-heartbeat")
            if (!heartbeatFile.exists()) return
            val epochMs = heartbeatFile.readText().trim().toLongOrNull() ?: return
            val staleMs = System.currentTimeMillis() - epochMs
            if (staleMs > HEARTBEAT_STALE_MS) {
                if (!pausedNotificationShown) {
                    Log.e(TAG, "Dart heartbeat stale by ${staleMs / 1000}s — showing paused notification")
                    pausedNotificationShown = true
                    updateNotification(
                        applicationContext,
                        "Cleona Chat",
                        "Pausiert — App öffnen, um fortzusetzen"
                    )
                }
            } else if (pausedNotificationShown) {
                // Recovered: restore the base notification. Dart's dedup
                // (_lastNotificationText) may suppress its next update, so
                // Kotlin must undo its own degradation.
                pausedNotificationShown = false
                val manager = getSystemService(NotificationManager::class.java)
                manager.notify(NOTIFICATION_ID, createNotification())
            }
        } catch (e: Exception) {
            Log.w(TAG, "Heartbeat check failed: ${e.message}")
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Cleona Chat",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Verbindungsstatus"
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            }
            manager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(cachedTitle)
            .setContentText(cachedText)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setShowWhen(false)
            .build()
    }
}
