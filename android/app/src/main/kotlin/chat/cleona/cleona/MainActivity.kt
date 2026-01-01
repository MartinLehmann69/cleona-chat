package chat.cleona.cleona

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.AssetFileDescriptor
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaPlayer
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

class MainActivity : FlutterActivity() {
    private val CHANNEL = "chat.cleona/service"
    private val STORAGE_CHANNEL = "chat.cleona/storage"
    private val AUDIO_CHANNEL = "chat.cleona/audio"
    private val NOTIFICATION_MSG_CHANNEL = "chat.cleona/notification"
    private val VIBRATION_CHANNEL = "chat.cleona/vibration"
    private val MSG_CHANNEL_ID = "cleona_messages"
    private val NOTIFICATION_PERMISSION_CODE = 1001
    private var cameraHandler: CameraXHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Camera channel for video calls (Phase 3b)
        cameraHandler = CameraXHandler(
            this,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CameraXHandler.CHANNEL_NAME)
        )

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
                        try {
                            playAssetSound(asset)
                            runOnUiThread { result.success(null) }
                        } catch (e: Exception) {
                            runOnUiThread { result.success(null) } // non-fatal
                        }
                    }.start()
                }
                "updateBadge" -> {
                    val count = call.argument<Int>("count") ?: 0
                    updateBadgeCount(count)
                    result.success(null)
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

        // CalendarContract bridge — mirrors Cleona events into the Android
        // system calendar (Samsung / Google Calendar). Opt-in from
        // Settings; runtime-permission flow handled in Kotlin.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CalendarContractHandler.CHANNEL_NAME
        ).setMethodCallHandler(
            CalendarContractHandler(applicationContext, this)
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // POST_NOTIFICATIONS Runtime-Permission (API 33+)
        requestNotificationPermission()

        // Create message notification channel (separate from foreground service)
        createMessageNotificationChannel()

        // Foreground Service starten
        val intent = Intent(this, CleonaForegroundService::class.java)
        startForegroundService(intent)
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
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
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

    private fun playAssetSound(asset: String) {
        try {
            val afd: AssetFileDescriptor = assets.openFd("flutter_assets/$asset")
            val mp = MediaPlayer()
            mp.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
            afd.close()
            mp.prepare()
            mp.start()
            mp.setOnCompletionListener { it.release() }
        } catch (e: Exception) {
            // Sound playback is non-fatal
        }
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
                    .setPriority(NotificationCompat.PRIORITY_MIN)
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

    // Zurück-Taste = in den Hintergrund statt beenden
    @Deprecated("Use onBackPressedDispatcher")
    override fun onBackPressed() {
        moveTaskToBack(true)
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

    /// Simple PCM resampling (linear interpolation) and channel mixing.
    private fun resamplePcm(
        pcm: ByteArray, srcRate: Int, srcChannels: Int,
        dstRate: Int, dstChannels: Int
    ): ByteArray {
        val srcSamples = pcm.size / (2 * srcChannels)
        val srcBuf = ByteBuffer.wrap(pcm).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()

        // Mix to mono if needed
        val mono = ShortArray(srcSamples)
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
