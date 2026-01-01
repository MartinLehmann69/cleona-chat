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
import android.os.Process
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

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
        watchdogHandler.postDelayed(watchdogRunnable, WATCHDOG_GRACE_MS)
        // Boot as SPECIAL_USE (no time limit, API 34+) or DATA_SYNC (pre-34).
        // _promoteForCall() upgrades to MICROPHONE on demand.
        // try/catch: defence-in-depth against ForegroundServiceStartNotAllowedException
        // crash loops (Android can reject startForeground for exhausted quotas).
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID,
                    createNotification(),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                )
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    createNotification(),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                )
            } else {
                startForeground(NOTIFICATION_ID, createNotification())
            }
        } catch (e: Exception) {
            Log.e(TAG, "startForeground failed: ${e.message} — falling back to untyped")
            try { startForeground(NOTIFICATION_ID, createNotification()) } catch (_: Exception) {}
        }
    }

    override fun onDestroy() {
        watchdogHandler.removeCallbacks(watchdogRunnable)
        if (instance === this) instance = null
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // Bug #U10b — re-call startForeground with the desired type bitmask.
    // The 3-arg form is API 29+ (Q). On older Android we fall back to the
    // 2-arg form, which means MICROPHONE-while-backgrounded won't be
    // honored — but minSdk in app/build.gradle.kts is high enough that
    // this branch is informational.
    private fun _promoteForCall() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                val type = ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE or
                           ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                startForeground(NOTIFICATION_ID, createNotification(), type)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val type = ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC or
                           ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                startForeground(NOTIFICATION_ID, createNotification(), type)
            } else {
                startForeground(NOTIFICATION_ID, createNotification())
            }
        } catch (e: Exception) {
            Log.e(TAG, "promoteForCall failed: ${e.message}")
        }
    }

    private fun _demoteAfterCall() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID,
                    createNotification(),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                )
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    createNotification(),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                )
            } else {
                startForeground(NOTIFICATION_ID, createNotification())
            }
        } catch (e: Exception) {
            Log.e(TAG, "demoteAfterCall failed: ${e.message}")
        }
    }

    private fun checkDartHeartbeat() {
        try {
            val heartbeatFile = File(applicationContext.filesDir, ".cleona/.dart-heartbeat")
            if (!heartbeatFile.exists()) return
            val epochMs = heartbeatFile.readText().trim().toLongOrNull() ?: return
            val staleMs = System.currentTimeMillis() - epochMs
            if (staleMs > HEARTBEAT_STALE_MS) {
                Log.e(TAG, "Dart heartbeat stale by ${staleMs / 1000}s — killing process for START_STICKY restart")
                Process.killProcess(Process.myPid())
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
