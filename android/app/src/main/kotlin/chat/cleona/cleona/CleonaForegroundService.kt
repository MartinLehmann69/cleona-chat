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
import android.os.IBinder
import androidx.core.app.NotificationCompat

class CleonaForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "cleona_service"
        const val NOTIFICATION_ID = 1

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

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())
    }

    override fun onDestroy() {
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val type = ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC or
                       ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            startForeground(NOTIFICATION_ID, createNotification(), type)
        } else {
            startForeground(NOTIFICATION_ID, createNotification())
        }
    }

    private fun _demoteAfterCall() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                createNotification(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(NOTIFICATION_ID, createNotification())
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            // Delete old channel (importance cannot be changed after creation)
            manager.deleteNotificationChannel("cleona_service")
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
