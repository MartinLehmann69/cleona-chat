package chat.cleona.cleona

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AudioEffect
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import androidx.core.content.ContextCompat

/**
 * Read-only introspection of the platform echo-cancellation / noise-suppression
 * stack. Answers "does this device offer a HAL AEC at all, and would the
 * platform switch it on by itself for a VOICE_COMMUNICATION capture session".
 *
 * IMPORTANT — what this can NOT answer:
 * The live capture stream is opened by miniaudio inside libcleona_audio via
 * AAudio/OpenSL, not by a Kotlin AudioRecord. miniaudio requests
 * AAUDIO_SESSION_ID_NONE, so that stream has no audio-session id that could be
 * reached from Java/Kotlin, and there is no public API to enumerate the effects
 * attached to a foreign/native stream. Everything below is therefore either a
 * device property or a measurement taken on a *separate probe* session — never
 * a direct observation of the running capture stream.
 *
 * The probe deliberately only *constructs* an AudioRecord and never calls
 * startRecording(): the record track (and with it the platform's automatic
 * pre-processing attachment, driven by the device's audio_effects.xml
 * <preprocess><stream name="voice_communication">) is created by the AudioRecord
 * constructor, so the default-enabled state is already observable, while the
 * microphone hardware is never opened. That keeps the probe free of any
 * interference with the native capture stream and free of the mic indicator.
 *
 * Pure diagnostics: nothing here enables, disables or reconfigures an effect.
 */
object AudioDiagnostics {

    /** Sample rate / format the probe session uses — mirrors AudioEngine. */
    private const val PROBE_SAMPLE_RATE = 16000

    fun collect(context: Context, probe: Boolean): Map<String, Any?> {
        val out = LinkedHashMap<String, Any?>()

        // ── Device capability (static, no session needed) ────────────────
        out["aecAvailable"] = safeBool { AcousticEchoCanceler.isAvailable() }
        out["nsAvailable"] = safeBool { NoiseSuppressor.isAvailable() }
        out["aecImpl"] = effectImplementor(AudioEffect.EFFECT_TYPE_AEC)
        out["nsImpl"] = effectImplementor(AudioEffect.EFFECT_TYPE_NS)

        // ── AudioManager state at the moment of the call ─────────────────
        try {
            val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            out["mode"] = modeName(am.mode)
            @Suppress("DEPRECATION")
            out["speakerphoneOn"] = am.isSpeakerphoneOn
            out["micMute"] = am.isMicrophoneMute
            out["nativeOutputSampleRate"] =
                am.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)
            out["outputFramesPerBuffer"] =
                am.getProperty(AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                out["communicationDevice"] = try {
                    am.communicationDevice?.type?.toString()
                } catch (e: Exception) {
                    null
                }
            }
        } catch (e: Exception) {
            out["audioManagerError"] = e.javaClass.simpleName
        }

        // FEATURE_AUDIO_LOW_LATENCY / _PRO indicate that capture may take the
        // FAST/MMAP path — on that path the platform pre-processing chain is
        // bypassed entirely, which is why a device can report aecAvailable=true
        // and still deliver a completely unprocessed native stream.
        try {
            val pm = context.packageManager
            out["featureLowLatencyAudio"] =
                pm.hasSystemFeature(PackageManager.FEATURE_AUDIO_LOW_LATENCY)
            out["featureProAudio"] =
                pm.hasSystemFeature(PackageManager.FEATURE_AUDIO_PRO)
        } catch (e: Exception) {
            // non-fatal
        }

        // ── Probe session (separate from the native capture stream!) ─────
        if (probe) {
            collectProbe(context, out)
        }

        return out
    }

    /**
     * Opens (but never starts) an AudioRecord with the exact source miniaudio
     * requests — MediaRecorder.AudioSource.VOICE_COMMUNICATION — and reports
     * whether the platform attached AEC/NS to that session by default.
     *
     * A `true` here means: this device's effect configuration auto-applies
     * pre-processing to voice-communication capture sessions. It does NOT prove
     * that the same happened for the AAudio stream that miniaudio opened.
     */
    private fun collectProbe(context: Context, out: MutableMap<String, Any?>) {
        val granted = ContextCompat.checkSelfPermission(
            context, Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
        out["probePermission"] = granted
        if (!granted) {
            out["probeError"] = "no-record-permission"
            return
        }

        var record: AudioRecord? = null
        var aec: AcousticEchoCanceler? = null
        var ns: NoiseSuppressor? = null
        try {
            val minBuf = AudioRecord.getMinBufferSize(
                PROBE_SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )
            if (minBuf <= 0) {
                out["probeError"] = "min-buffer-$minBuf"
                return
            }
            record = AudioRecord(
                MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                PROBE_SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                minBuf
            )
            if (record.state != AudioRecord.STATE_INITIALIZED) {
                out["probeError"] = "record-state-${record.state}"
                return
            }
            val sessionId = record.audioSessionId
            out["probeSessionId"] = sessionId

            if (AcousticEchoCanceler.isAvailable()) {
                aec = AcousticEchoCanceler.create(sessionId)
                out["aecDefaultOn"] = aec?.enabled
                if (aec == null) out["aecCreate"] = "null"
            }
            if (NoiseSuppressor.isAvailable()) {
                ns = NoiseSuppressor.create(sessionId)
                out["nsDefaultOn"] = ns?.enabled
                if (ns == null) out["nsCreate"] = "null"
            }
        } catch (e: Exception) {
            out["probeError"] = "${e.javaClass.simpleName}:${e.message}"
        } catch (e: UnsatisfiedLinkError) {
            out["probeError"] = "UnsatisfiedLinkError"
        } finally {
            // Release in reverse order; the effects hold a reference to the
            // session, the AudioRecord owns it.
            try { aec?.release() } catch (_: Exception) {}
            try { ns?.release() } catch (_: Exception) {}
            try { record?.release() } catch (_: Exception) {}
        }
    }

    /** "<name>/<implementor>" of the first effect descriptor of [type]. */
    private fun effectImplementor(type: java.util.UUID): String? {
        return try {
            val descriptors = AudioEffect.queryEffects() ?: return null
            for (d in descriptors) {
                if (d.type == type) {
                    return "${d.name}/${d.implementor}"
                }
            }
            null
        } catch (e: Exception) {
            null
        }
    }

    private fun modeName(mode: Int): String = when (mode) {
        AudioManager.MODE_NORMAL -> "NORMAL"
        AudioManager.MODE_RINGTONE -> "RINGTONE"
        AudioManager.MODE_IN_CALL -> "IN_CALL"
        AudioManager.MODE_IN_COMMUNICATION -> "IN_COMMUNICATION"
        else -> "mode-$mode"
    }

    private inline fun safeBool(block: () -> Boolean): Boolean? = try {
        block()
    } catch (e: Exception) {
        null
    }
}
