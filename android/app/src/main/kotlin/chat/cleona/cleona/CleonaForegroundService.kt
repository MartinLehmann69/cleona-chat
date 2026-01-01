package chat.cleona.cleona

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
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

        /// Update the foreground notification text from anywhere.
        fun updateNotification(context: Context, title: String, text: String) {
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
    }

    override fun onDestroy() {
        watchdogHandler.removeCallbacks(watchdogRunnable)
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
            .setContentTitle("Cleona Chat")
            .setContentText("Verbinde\u2026")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setShowWhen(false)
            .build()
    }
}
