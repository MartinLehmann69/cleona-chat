package chat.cleona.cleona

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AudioEffect
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.ShortBuffer
import java.util.concurrent.Executor
import java.util.concurrent.locks.ReentrantLock

/**
 * Android backend of the `cleona_voice` ABI — work package V1.2.
 *
 * Contract: `native/cleona_voice/cleona_voice.h` (frozen).
 * Architecture: `Cleona_Chat_Architecture_v3_0.md` §10.4 (normative).
 * Spec: `docs/SPEC_VOICE_VIDEO_REWORK.md` §2 (I1-I7, I11), §4, §6, §7 "V1.2".
 *
 * ---------------------------------------------------------------------------
 * WHY KOTLIN AND NOT AAUDIO
 * ---------------------------------------------------------------------------
 * §10.4: "The Java API is mandatory on Android: only `AudioRecord` exposes a
 * session id, and only with a session id can the effects be attached **and**
 * read back. AAudio streams carry `AAUDIO_SESSION_ID_NONE` and are therefore
 * neither attachable nor verifiable." Defect 5 of the superseded stack was
 * exactly that. The verification report (I11) is not implementable on AAudio,
 * so the whole session lives here and `cleona_voice_android.c` is a thin JNI
 * facade with no audio logic of its own.
 *
 * Derived from `AudioDiagnostics.kt:117-160`, which already built the
 * `AudioRecord`, took the session id and created `AcousticEchoCanceler` /
 * `NoiseSuppressor` correctly. Two things are different here, and they are the
 * point of this package:
 *
 *   1. `AutomaticGainControl` is added. Defect 6 of the superseded stack: "AGC
 *      was never switched on at all".
 *   2. The effects are **started**. `AudioDiagnostics` only ever *constructed*
 *      them (deliberately — it is a read-only probe); the shipped audio path
 *      never constructed them at all. An effect that is created and never
 *      enabled does nothing, which is the historical defect this class exists
 *      to end.
 *
 * ---------------------------------------------------------------------------
 * WHAT "ONE OS DUPLEX SESSION" (I2) MEANS ON ANDROID
 * ---------------------------------------------------------------------------
 * Android has no single duplex handle. Its voice chain is engaged by the
 * combination the platform recognises as a telephony-shaped call:
 *
 *   - capture from `MediaRecorder.AudioSource.VOICE_COMMUNICATION`,
 *   - render with `AudioAttributes.USAGE_VOICE_COMMUNICATION`,
 *   - `AudioManager.MODE_IN_COMMUNICATION` while the session runs,
 *   - AEC/NS/AGC attached to the **record session id**.
 *
 * The AEC reference is then taken by the HAL from the device's own output mix.
 * That is the substantive difference to the superseded stack, which passed the
 * reference between two `ma_device` clocks through a capacity-1 ring
 * (`cleona_audio_ring.c:110-118`) and injected a zero reference frame whenever
 * the ring ran dry.
 *
 * `duplex` is therefore reported as 1 only when all of this is **read back**
 * from the platform, never because it was requested — see [computeDuplex].
 *
 * ---------------------------------------------------------------------------
 * THREADS
 * ---------------------------------------------------------------------------
 * Two threads are owned here, both started by [start] and joined by [stop]:
 *
 *   captureThread   blocks in `AudioRecord.read` and assembles **exactly**
 *                   [frameSamples] samples per frame before publishing one
 *                   (I4 — the superseded stack assumed a constant callback
 *                   size and dropped the frame when the assumption broke,
 *                   `cleona_audio.c:151`).
 *   playbackThread  blocks in `AudioTrack.write`. That blocking write is the
 *                   pacing (I5): the output device is the clock, and there is
 *                   no timer anywhere in this file's playback path.
 *
 * The ABI entry points are called from up to three foreign threads (see the
 * THREADING section of `cleona_voice.h`); every field they touch is guarded by
 * [lock] or is `@Volatile`.
 */
class VoiceSession private constructor(
    private val am: AudioManager,
    private val record: AudioRecord,
    private val track: AudioTrack,
    private val aec: AcousticEchoCanceler?,
    private val ns: NoiseSuppressor?,
    private val agc: AutomaticGainControl?,
    private val aecState: Int,
    private val nsState: Int,
    private val agcState: Int,
    /** Negotiated rate, as the platform accepted it — never a constant (I3). */
    private val sampleRate: Int,
    private val frameSamples: Int,
) {

    // ─── frame plumbing ──────────────────────────────────────────────────
    // One direct buffer per direction, allocated once. The JNI facade caches
    // their addresses at open() and memcpy()s through them, so the data path
    // allocates nothing per frame on either side of the boundary.

    private val frameBytes = frameSamples * 2

    private val captureBuf: ByteBuffer =
        ByteBuffer.allocateDirect(frameBytes).order(ByteOrder.nativeOrder())
    private val captureShorts: ShortBuffer = captureBuf.asShortBuffer()

    private val playbackBuf: ByteBuffer =
        ByteBuffer.allocateDirect(frameBytes).order(ByteOrder.nativeOrder())
    private val playbackShorts: ShortBuffer = playbackBuf.asShortBuffer()

    private val captureRing = FrameRing(frameSamples, CAPTURE_RING_FRAMES)
    private val playbackRing = FrameRing(frameSamples, PLAYBACK_RING_FRAMES)

    /** Scratch owned exclusively by the playback thread. */
    private val playbackScratch = ShortArray(frameSamples)
    private val silence = ShortArray(frameSamples)

    // ─── state ───────────────────────────────────────────────────────────

    private val lock = ReentrantLock()

    @Volatile private var running = false
    @Volatile private var closed = false

    /** Set when the platform reports the stream is gone; capture_read then
     *  answers CLOSED instead of pretending to time out. */
    @Volatile private var deviceLost = false

    @Volatile private var micMuted = false
    @Volatile private var outputMuted = false

    // Atomic, not plain longs: `overruns` is incremented by the capture thread
    // (ring full) and by whichever thread calls playback_write (ring full),
    // so a read-modify-write race is real. The report only has to be monotonic,
    // but a counter that silently loses increments is a counter that cannot be
    // used to argue about a field recording.
    private val underruns = java.util.concurrent.atomic.AtomicLong(0)
    private val overruns = java.util.concurrent.atomic.AtomicLong(0)

    private var captureThread: Thread? = null
    private var playbackThread: Thread? = null

    /**
     * Incremented by every [start]. Each audio thread captures the value it was
     * born with and exits as soon as it differs.
     *
     * Without it, stop/start in quick succession can run two capture threads at
     * once: [stop] waits only [THREAD_JOIN_MS] for the old thread, which may
     * still be inside a blocking `AudioRecord.read`, and by the time it wakes up
     * `running` has been set back to true by the next [start]. Two threads
     * draining one AudioRecord would halve the frame rate of each and produce
     * exactly the kind of intermittent, unreproducible symptom this rewrite
     * exists to stop shipping.
     */
    @Volatile private var generation = 0

    private val events = ArrayDeque<IntArray>()

    private var deviceCallback: AudioDeviceCallback? = null
    private var commDeviceListener: Any? = null
    private var callbackThread: HandlerThread? = null

    private val duplex: Int = computeDuplex()

    // ─────────────────────────────────────────────────────────────────────
    // Buffer handover to the JNI facade
    // ─────────────────────────────────────────────────────────────────────

    fun captureBuffer(): ByteBuffer = captureBuf

    fun playbackBuffer(): ByteBuffer = playbackBuf

    // ─────────────────────────────────────────────────────────────────────
    // Lifecycle
    // ─────────────────────────────────────────────────────────────────────

    /** @return [Abi.OK] or a negative `CLEONA_VOICE_ERR_*`. */
    fun start(): Int {
        lock.lock()
        try {
            if (closed) return Abi.ERR_CLOSED
            if (running) return Abi.ERR_ALREADY_STARTED

            enterCommunicationMode()

            try {
                record.startRecording()
            } catch (e: IllegalStateException) {
                Log.e(TAG, "AudioRecord.startRecording failed", e)
                leaveCommunicationMode()
                return Abi.ERR_BACKEND
            }
            if (record.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                Log.e(TAG, "AudioRecord did not enter RECORDING state")
                record.stop()
                leaveCommunicationMode()
                return Abi.ERR_BACKEND
            }

            try {
                track.play()
            } catch (e: IllegalStateException) {
                Log.e(TAG, "AudioTrack.play failed", e)
                record.stop()
                leaveCommunicationMode()
                return Abi.ERR_BACKEND
            }

            captureRing.reset()
            playbackRing.reset()
            deviceLost = false
            running = true
            val gen = ++generation

            registerRouteWatchers()
            ensureActiveRoute()

            captureThread = Thread({ captureLoop(gen) }, "cleona-voice-capture").apply {
                priority = Thread.MAX_PRIORITY
                start()
            }
            playbackThread = Thread({ playbackLoop(gen) }, "cleona-voice-playback").apply {
                priority = Thread.MAX_PRIORITY
                start()
            }
            return Abi.OK
        } finally {
            lock.unlock()
        }
    }

    /** Idempotent, and safe on a session that never started. The negotiated
     *  format survives, so the session can be started again (`cleona_voice.h`). */
    fun stop() {
        val capture: Thread?
        val playback: Thread?
        lock.lock()
        try {
            if (!running) return
            running = false
            capture = captureThread
            playback = playbackThread
            captureThread = null
            playbackThread = null
        } finally {
            lock.unlock()
        }

        // Wake both loops out of their blocking platform calls before joining.
        captureRing.wakeAll()
        playbackRing.wakeAll()

        try { capture?.join(THREAD_JOIN_MS) } catch (_: InterruptedException) {}
        try { playback?.join(THREAD_JOIN_MS) } catch (_: InterruptedException) {}

        lock.lock()
        try {
            runCatching { record.stop() }
                .onFailure { Log.w(TAG, "AudioRecord.stop", it) }
            runCatching { track.pause(); track.flush() }
                .onFailure { Log.w(TAG, "AudioTrack.stop", it) }
            unregisterRouteWatchers()
            leaveCommunicationMode()
            captureRing.reset()
            playbackRing.reset()
        } finally {
            lock.unlock()
        }
    }

    /** Releases every platform object. The instance is unusable afterwards. */
    fun release() {
        stop()
        lock.lock()
        try {
            if (closed) return
            closed = true
            // Effects hold a reference to the session, the AudioRecord owns it,
            // so they go first — same ordering as AudioDiagnostics.kt:158-164.
            runCatching { aec?.release() }
            runCatching { ns?.release() }
            runCatching { agc?.release() }
            runCatching { record.release() }
            runCatching { track.release() }
            events.clear()
        } finally {
            lock.unlock()
        }
        captureRing.wakeAll()
        playbackRing.wakeAll()
    }

    // ─────────────────────────────────────────────────────────────────────
    // Data path
    // ─────────────────────────────────────────────────────────────────────

    /**
     * @return [Abi.CAPTURE_FRAME] (one full frame is in [captureBuf]),
     *         [Abi.CAPTURE_TIMEOUT] (nothing written), or
     *         [Abi.CAPTURE_CLOSED].
     *
     * Nothing is written to the buffer unless a whole frame is returned — the
     * harness poisons the buffer and checks exactly that (SPEC §6 check 3).
     */
    fun captureRead(timeoutMs: Int): Int {
        if (closed) return Abi.CAPTURE_CLOSED
        if (!running) return Abi.CAPTURE_CLOSED

        val frame = captureRing.take(timeoutMs.toLong())
        if (frame == null) {
            // Distinguish "no data yet" from "the session went away underneath
            // us". Reporting a timeout for a dead stream would make a caller
            // loop forever on a device that will never speak again.
            if (closed || !running || deviceLost) return Abi.CAPTURE_CLOSED
            return Abi.CAPTURE_TIMEOUT
        }

        // I6: mute zeroes the frame; it never stops the stream, and it never
        // changes the cadence. Applied here rather than in the capture loop so
        // that unmuting takes effect on the very next frame.
        if (micMuted) {
            captureShorts.clear()
            captureShorts.put(silence, 0, frameSamples)
        } else {
            captureShorts.clear()
            captureShorts.put(frame, 0, frameSamples)
        }
        captureRing.recycle(frame)
        return Abi.CAPTURE_FRAME
    }

    /**
     * Takes one frame out of [playbackBuf]. Never blocks (I5): the frame is
     * handed to the playback ring and the output device paces it.
     *
     * @return [Abi.OK], or a negative `CLEONA_VOICE_ERR_*`.
     */
    fun playbackWrite(count: Int): Int {
        if (closed) return Abi.ERR_CLOSED
        if (!running) return Abi.ERR_NOT_STARTED
        // Rejected rather than padded or truncated (SPEC §6 check 4) — silent
        // adaptation here is how a rate mismatch becomes a mystery later.
        if (count != frameSamples) return Abi.ERR_FRAME_SIZE

        val slot = playbackRing.acquire()
        playbackShorts.clear()
        playbackShorts.get(slot, 0, frameSamples)
        if (!playbackRing.offerDropOldest(slot)) overruns.incrementAndGet()
        return Abi.OK
    }

    // ─────────────────────────────────────────────────────────────────────
    // Controls (I6, I7)
    // ─────────────────────────────────────────────────────────────────────

    fun setMicMuted(muted: Boolean) {
        // The stream deliberately keeps running. Stopping it diverges the
        // adaptive filter and produces about a second of echo on unmute
        // (§10.4, "Microphone mute"); the superseded C code already knew that.
        micMuted = muted
    }

    fun setOutputMuted(muted: Boolean) {
        // Playback keeps consuming frames and renders silence. Returning early
        // instead — what audio_engine.dart:353 did — backs the jitter buffer up
        // to its cap and produces a burst on re-enable.
        outputMuted = muted
    }

    fun setRoute(route: Int): Int {
        if (route <= Abi.ROUTE_UNKNOWN || route > Abi.ROUTE_BLUETOOTH) {
            return Abi.ERR_INVALID_ARG
        }
        if (closed) return Abi.ERR_CLOSED

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return setRouteLegacy(route)
        }

        val candidates = availableCommDevices().filter { routeOf(it) == route }
        if (candidates.isEmpty()) return Abi.ERR_ROUTE_UNAVAILABLE
        for (dev in candidates) {
            val ok = runCatching { am.setCommunicationDevice(dev) }
                .onFailure { Log.w(TAG, "setCommunicationDevice(${dev.type})", it) }
                .getOrDefault(false)
            if (ok) return Abi.OK
        }
        return Abi.ERR_BACKEND
    }

    /**
     * API 24-30 has no `setCommunicationDevice`. §10.4 names
     * `setSpeakerphoneOn` as the documented fallback below API 31. Wired and
     * Bluetooth selection is not expressible there, so it is refused with a
     * defined code instead of silently doing nothing.
     */
    @Suppress("DEPRECATION")
    private fun setRouteLegacy(route: Int): Int {
        val mask = routesMask()
        if (mask and (1 shl route) == 0) return Abi.ERR_ROUTE_UNAVAILABLE
        return when (route) {
            Abi.ROUTE_SPEAKER -> {
                runCatching { am.isSpeakerphoneOn = true }
                    .fold({ Abi.OK }, { Abi.ERR_BACKEND })
            }
            Abi.ROUTE_EARPIECE -> {
                runCatching { am.isSpeakerphoneOn = false }
                    .fold({ Abi.OK }, { Abi.ERR_BACKEND })
            }
            else -> Abi.ERR_ROUTE_UNSUPPORTED
        }
    }

    /** out[0] = mask, out[1] = active output route. */
    fun getRoutes(out: IntArray): Int {
        if (closed) return Abi.ERR_CLOSED
        out[0] = routesMask()
        out[1] = activeOutputRoute()
        return Abi.OK
    }

    // ─────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────

    /** out[0] = event, out[1] = arg. Never blocks. */
    fun pollEvent(out: IntArray): Int {
        lock.lock()
        try {
            val e = events.removeFirstOrNull()
            if (e == null) {
                out[0] = Abi.EV_NONE
                out[1] = 0
            } else {
                out[0] = e[0]
                out[1] = e[1]
            }
            return Abi.OK
        } finally {
            lock.unlock()
        }
    }

    private fun postEvent(event: Int, arg: Int) {
        lock.lock()
        try {
            // Overflow drops the OLDEST entries (`cleona_voice.h`), which is
            // also what keeps the newest EV_ROUTES_CHANGED — the one that
            // carries the current mask — alive.
            while (events.size >= EVENT_QUEUE_MAX) events.removeFirst()
            events.addLast(intArrayOf(event, arg))
        } finally {
            lock.unlock()
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Verification report (I11)
    // ─────────────────────────────────────────────────────────────────────

    /**
     * Every value here is an observation. The effect states were read back with
     * `getEnabled()` at open time (see [Companion.attachEffect]); nothing is
     * upgraded to ENABLED because it was asked for.
     */
    fun fillReport(ints: IntArray, longs: LongArray) {
        ints[0] = sampleRate
        ints[1] = 1
        ints[2] = frameSamples
        ints[3] = frameBytes
        ints[4] = aecState
        ints[5] = nsState
        ints[6] = agcState
        // The chain this backend addresses is the Android HAL voice chain, and
        // that is true whether or not a given effect turned out to be present:
        // chain_origin names WHERE the chain comes from, the three states above
        // say what is actually running in it.
        ints[7] = Abi.CHAIN_ANDROID_HAL
        ints[8] = Abi.BACKEND_ANDROID_AUDIORECORD
        ints[9] = duplex
        ints[10] = activeInputRoute()
        ints[11] = activeOutputRoute()
        ints[12] = routesMask()
        // Erratum E6a. Exactly 0 or 1, and read from the two fields the setters
        // write — not inferred from AudioManager.isMicrophoneMute or from
        // whether a stream happens to be running.
        //
        // For this backend that IS the platform state in the sense the header
        // means: the mute is applied here, by zeroing the capture frame
        // (captureRead) and by rendering silence (playbackLoop), so there is no
        // second, external owner of the value that could disagree. Android's own
        // AudioManager.isMicrophoneMute is a process-wide switch this backend
        // deliberately does not touch — reporting it would answer a different
        // question than the one asked.
        ints[13] = if (micMuted) 1 else 0
        ints[14] = if (outputMuted) 1 else 0
        longs[0] = underruns.get()
        longs[1] = overruns.get()
    }

    /**
     * I2, read back rather than asserted.
     *
     * `AudioRecord.getAudioSource()` and `AudioTrack.getStreamType()` are the
     * two properties Android lets us read back after construction. A track
     * built with `USAGE_VOICE_COMMUNICATION` reports `STREAM_VOICE_CALL`; if it
     * reported anything else the platform did not put the render side on the
     * voice path, and this session is not a duplex voice session no matter what
     * was requested.
     */
    private fun computeDuplex(): Int {
        val recOk = record.state == AudioRecord.STATE_INITIALIZED &&
            record.audioSource == MediaRecorder.AudioSource.VOICE_COMMUNICATION
        val trkOk = track.state == AudioTrack.STATE_INITIALIZED &&
            track.streamType == AudioManager.STREAM_VOICE_CALL
        if (!recOk || !trkOk) {
            Log.e(
                TAG,
                "not a duplex voice session: recordState=${record.state} " +
                    "source=${record.audioSource} trackState=${track.state} " +
                    "stream=${track.streamType}"
            )
        }
        return if (recOk && trkOk) 1 else 0
    }

    // ─────────────────────────────────────────────────────────────────────
    // Capture loop — I4 lives here
    // ─────────────────────────────────────────────────────────────────────

    private fun captureLoop(gen: Int) {
        while (running && !closed && gen == generation) {
            val slot = captureRing.acquire()
            var filled = 0
            var failed = false

            // AudioRecord.read returns "up to" the requested count. Assembling
            // the frame here is the whole of I4: the ABI promises the caller
            // exactly frameSamples, so a short device read is buffered, never
            // passed on and never dropped.
            while (filled < frameSamples && running && !closed && gen == generation) {
                val n = try {
                    record.read(slot, filled, frameSamples - filled)
                } catch (e: IllegalStateException) {
                    Log.e(TAG, "AudioRecord.read threw", e)
                    -1
                }
                when {
                    n > 0 -> filled += n
                    n == 0 -> Thread.sleep(1)
                    else -> {
                        Log.e(TAG, "AudioRecord.read = $n — capture stream lost")
                        deviceLost = true
                        failed = true
                        break
                    }
                }
            }

            if (failed || filled < frameSamples) {
                captureRing.recycle(slot)
                if (failed) break
                continue
            }
            if (!captureRing.offerDropOldest(slot)) overruns.incrementAndGet()
        }
        captureRing.wakeAll()
    }

    // ─────────────────────────────────────────────────────────────────────
    // Playback loop — I5 lives here
    // ─────────────────────────────────────────────────────────────────────

    private fun playbackLoop(gen: Int) {
        while (running && !closed && gen == generation) {
            val frame = playbackRing.take(FRAME_MS.toLong())
            val src: ShortArray
            if (frame == null) {
                // Nothing to render. Keep the device fed with silence rather
                // than letting it run dry: a gap in the render stream is a gap
                // in the HAL's AEC reference, and the counter records that it
                // happened.
                underruns.incrementAndGet()
                src = silence
            } else {
                if (outputMuted) {
                    src = silence
                } else {
                    System.arraycopy(frame, 0, playbackScratch, 0, frameSamples)
                    src = playbackScratch
                }
                playbackRing.recycle(frame)
            }

            // Blocking write: this call, and nothing else, sets the pace (I5).
            val n = try {
                track.write(src, 0, frameSamples, AudioTrack.WRITE_BLOCKING)
            } catch (e: IllegalStateException) {
                Log.e(TAG, "AudioTrack.write threw", e)
                -1
            }
            if (n < 0) {
                Log.e(TAG, "AudioTrack.write = $n — playback stream lost")
                break
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Routes
    // ─────────────────────────────────────────────────────────────────────

    private fun availableCommDevices(): List<AudioDeviceInfo> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            runCatching { am.availableCommunicationDevices }.getOrDefault(emptyList())
        } else {
            emptyList()
        }

    private fun routesMask(): Int {
        var mask = 0
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            for (d in availableCommDevices()) {
                val r = routeOf(d)
                if (r != Abi.ROUTE_UNKNOWN) mask = mask or (1 shl r)
            }
        } else {
            val devs = runCatching { am.getDevices(AudioManager.GET_DEVICES_OUTPUTS) }
                .getOrDefault(emptyArray())
            for (d in devs) {
                val r = routeOf(d)
                if (r != Abi.ROUTE_UNKNOWN) mask = mask or (1 shl r)
            }
        }
        // ROUTE_UNKNOWN is a state, not a route, and is never set in the mask
        // (`cleona_voice.h`).
        return mask and (1 shl Abi.ROUTE_UNKNOWN).inv()
    }

    private fun activeOutputRoute(): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val dev = runCatching { am.communicationDevice }.getOrNull()
            if (dev != null) {
                val r = routeOf(dev)
                if (r != Abi.ROUTE_UNKNOWN) return r
            }
            return Abi.ROUTE_UNKNOWN
        }
        return activeOutputRouteLegacy()
    }

    @Suppress("DEPRECATION")
    private fun activeOutputRouteLegacy(): Int {
        val mask = routesMask()
        val speakerOn = runCatching { am.isSpeakerphoneOn }.getOrDefault(false)
        if (speakerOn && mask and (1 shl Abi.ROUTE_SPEAKER) != 0) return Abi.ROUTE_SPEAKER
        if (mask and (1 shl Abi.ROUTE_WIRED) != 0) return Abi.ROUTE_WIRED
        if (mask and (1 shl Abi.ROUTE_BLUETOOTH) != 0) return Abi.ROUTE_BLUETOOTH
        if (mask and (1 shl Abi.ROUTE_EARPIECE) != 0) return Abi.ROUTE_EARPIECE
        if (mask and (1 shl Abi.ROUTE_SPEAKER) != 0) return Abi.ROUTE_SPEAKER
        return Abi.ROUTE_UNKNOWN
    }

    /**
     * The input route, only where it is genuinely observable.
     *
     * Android selects one *communication device* for both directions. When that
     * device carries its own microphone — a wired or Bluetooth headset — the
     * input route is that device. When it is the built-in earpiece or speaker,
     * the microphone is the built-in one, which this ABI's route enumeration
     * cannot express; the honest answer is then ROUTE_UNKNOWN rather than a
     * plausible-looking guess (I11). Only `route_active_out` is required to be
     * a real route on a started session.
     */
    private fun activeInputRoute(): Int =
        when (val out = activeOutputRoute()) {
            Abi.ROUTE_WIRED, Abi.ROUTE_BLUETOOTH -> out
            else -> Abi.ROUTE_UNKNOWN
        }

    /**
     * Makes sure a started session has a defined active route, which
     * `cleona_voice.h` requires and SPEC §6 check 8 asserts.
     *
     * This is not the route *policy* — that lives once, in Dart
     * (`RoutePolicy`, V1.5, I7). All this does is ensure the platform has
     * committed to some communication device, so that `get_routes` has
     * something true to report.
     */
    private fun ensureActiveRoute() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        if (runCatching { am.communicationDevice }.getOrNull() != null) return
        val devices = availableCommDevices()
        val preference = intArrayOf(
            Abi.ROUTE_WIRED, Abi.ROUTE_BLUETOOTH, Abi.ROUTE_EARPIECE, Abi.ROUTE_SPEAKER
        )
        for (want in preference) {
            val dev = devices.firstOrNull { routeOf(it) == want } ?: continue
            val ok = runCatching { am.setCommunicationDevice(dev) }.getOrDefault(false)
            if (ok) return
        }
        Log.w(TAG, "no communication device could be selected; mask=${routesMask()}")
    }

    private fun registerRouteWatchers() {
        // Event-driven, never polled (§10.4, "Headset detection and route
        // switching").
        val ht = HandlerThread("cleona-voice-routes").apply { start() }
        callbackThread = ht
        val handler = Handler(ht.looper)

        val cb = object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>?) {
                postEvent(Abi.EV_ROUTES_CHANGED, routesMask())
            }

            override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>?) {
                postEvent(Abi.EV_ROUTES_CHANGED, routesMask())
            }
        }
        runCatching { am.registerAudioDeviceCallback(cb, handler) }
            .onSuccess { deviceCallback = cb }
            .onFailure { Log.w(TAG, "registerAudioDeviceCallback", it) }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val exec = Executor { r -> handler.post(r) }
            val l = AudioManager.OnCommunicationDeviceChangedListener {
                postEvent(Abi.EV_ROUTES_CHANGED, routesMask())
            }
            runCatching { am.addOnCommunicationDeviceChangedListener(exec, l) }
                .onSuccess { commDeviceListener = l }
                .onFailure { Log.w(TAG, "addOnCommunicationDeviceChangedListener", it) }
        }
    }

    private fun unregisterRouteWatchers() {
        deviceCallback?.let { cb ->
            runCatching { am.unregisterAudioDeviceCallback(cb) }
        }
        deviceCallback = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (commDeviceListener as? AudioManager.OnCommunicationDeviceChangedListener)
                ?.let { runCatching { am.removeOnCommunicationDeviceChangedListener(it) } }
        }
        commDeviceListener = null
        callbackThread?.quitSafely()
        callbackThread = null
    }

    // ─────────────────────────────────────────────────────────────────────
    // Communication mode
    // ─────────────────────────────────────────────────────────────────────

    private fun enterCommunicationMode() {
        modeLock.lock()
        try {
            if (modeRefCount == 0) {
                savedMode = runCatching { am.mode }.getOrDefault(AudioManager.MODE_NORMAL)
                runCatching { am.mode = AudioManager.MODE_IN_COMMUNICATION }
                    .onFailure { Log.w(TAG, "setMode(MODE_IN_COMMUNICATION)", it) }
                val readBack = runCatching { am.mode }.getOrDefault(-1)
                if (readBack != AudioManager.MODE_IN_COMMUNICATION) {
                    // Recorded, not papered over: without this mode the HAL does
                    // not treat the streams as a call, and the effect states in
                    // the report are what will show the consequence.
                    Log.w(TAG, "audio mode did not take: requested IN_COMMUNICATION, got $readBack")
                } else {
                    Log.i(TAG, "audio mode = MODE_IN_COMMUNICATION")
                }
            }
            modeRefCount++
        } finally {
            modeLock.unlock()
        }
    }

    private fun leaveCommunicationMode() {
        modeLock.lock()
        try {
            if (modeRefCount == 0) return
            modeRefCount--
            if (modeRefCount == 0) {
                runCatching { am.mode = savedMode }
                    .onFailure { Log.w(TAG, "restoring audio mode", it) }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    runCatching { am.clearCommunicationDevice() }
                }
            }
        } finally {
            modeLock.unlock()
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    companion object {

        private const val TAG = "CleonaVoice"

        /** 20 ms frames, `sample_rate / 50` (`cleona_voice.h`, frame contract). */
        private const val FRAME_HZ = 50
        private const val FRAME_MS = 1000 / FRAME_HZ

        private const val CAPTURE_RING_FRAMES = 16    // 320 ms
        private const val PLAYBACK_RING_FRAMES = 8    // 160 ms
        private const val EVENT_QUEUE_MAX = 32
        private const val THREAD_JOIN_MS = 1500L

        private val modeLock = ReentrantLock()
        private var modeRefCount = 0
        private var savedMode = AudioManager.MODE_NORMAL

        @Volatile private var appContext: Context? = null

        /**
         * Loads `libcleona_voice.so` **through the Java runtime** and hands the
         * backend an application context.
         *
         * Both halves matter:
         *
         *  - `System.loadLibrary` is what makes ART call `JNI_OnLoad`, which is
         *    where the JNI facade captures the `JavaVM*`. Dart's
         *    `DynamicLibrary.open` calls plain `dlopen`, which does **not** run
         *    `JNI_OnLoad`; a process where only Dart ever touched the library
         *    has no VM pointer and `cleona_voice_open` refuses with
         *    `CLEONA_VOICE_ERR_BACKEND` rather than crashing. Calling this once
         *    during app start is therefore a hard requirement — see
         *    `BUILD_REQUEST_V1.2.md` §2, addressed to the owner of
         *    `MainActivity.kt` (V1.10).
         *  - `AudioManager` needs a `Context`; without one there is no route
         *    control and no communication mode.
         *
         * Idempotent and safe to call from any thread.
         */
        @JvmStatic
        fun install(context: Context) {
            appContext = context.applicationContext
            ensureLibraryLoaded()
        }

        @Volatile private var libraryLoaded = false

        /**
         * @return true when `libcleona_voice.so` is loaded and its `JNI_OnLoad`
         *         has run.
         *
         * Deliberately does **not** propagate `UnsatisfiedLinkError`. The two
         * halves of this backend land in two different commits by two different
         * owners: the Kotlin file here (V1.2) and the `.so` in `jniLibs`
         * (build owner, `BUILD_REQUEST_V1.2.md` §1). Between those commits the
         * library is genuinely absent, and an app that dies on start because a
         * voice backend is missing is a far worse failure than a call that
         * cannot start. The absence surfaces where it belongs instead: through
         * the ABI, as `CLEONA_VOICE_ERR_BACKEND` from `cleona_voice_open`.
         */
        @JvmStatic
        @Synchronized
        fun ensureLibraryLoaded(): Boolean {
            if (libraryLoaded) return true
            try {
                System.loadLibrary("cleona_voice")
                libraryLoaded = true
            } catch (e: UnsatisfiedLinkError) {
                Log.e(TAG, "libcleona_voice.so not in this build — voice calls " +
                    "will fail with ERR_BACKEND (BUILD_REQUEST_V1.2.md §1)", e)
            }
            return libraryLoaded
        }

        /**
         * The ABI constants this file mirrors from `cleona_voice.h`.
         *
         * The JNI facade compares this array against the header at
         * `JNI_OnLoad` and refuses to bind on a mismatch. Two copies of a
         * constant in two languages is exactly the kind of drift that produces
         * a report which is well-formed and wrong, so the copy is checked
         * rather than trusted.
         */
        @JvmStatic
        fun abiConstants(): IntArray = intArrayOf(
            Abi.OK, Abi.ERR_INVALID_ARG, Abi.ERR_CLOSED, Abi.ERR_NOT_STARTED,
            Abi.ERR_ALREADY_STARTED, Abi.ERR_FRAME_SIZE, Abi.ERR_ROUTE_UNAVAILABLE,
            Abi.ERR_ROUTE_UNSUPPORTED, Abi.ERR_BACKEND, Abi.ERR_NO_DEVICE,
            Abi.ERR_PERMISSION, Abi.ERR_UNSUPPORTED,
            Abi.CAPTURE_FRAME, Abi.CAPTURE_TIMEOUT, Abi.CAPTURE_CLOSED,
            Abi.FX_UNAVAILABLE, Abi.FX_AVAILABLE_OFF, Abi.FX_ENABLED, Abi.FX_UNKNOWN,
            Abi.ROUTE_UNKNOWN, Abi.ROUTE_EARPIECE, Abi.ROUTE_SPEAKER,
            Abi.ROUTE_WIRED, Abi.ROUTE_BLUETOOTH,
            Abi.EV_NONE, Abi.EV_ROUTES_CHANGED, Abi.EV_INTERRUPTION_BEGIN,
            Abi.EV_INTERRUPTION_END, Abi.EV_FORMAT_CHANGED,
            Abi.CHAIN_ANDROID_HAL, Abi.BACKEND_ANDROID_AUDIORECORD,
        )

        /**
         * `cleona_voice_open`.
         *
         * @param outFormat 4 ints — rate, channels, frame_samples, frame_bytes.
         *        On failure `outFormat[0]` carries the negative
         *        `CLEONA_VOICE_ERR_*`, which is the ABI's in-band error channel.
         */
        @JvmStatic
        fun openSession(rateHint: Int, outFormat: IntArray): VoiceSession? {
            outFormat.fill(0)
            val ctx = appContext
            if (ctx == null) {
                Log.e(TAG, "VoiceSession.install(context) was never called")
                outFormat[0] = Abi.ERR_BACKEND
                return null
            }
            val am = try {
                ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            } catch (e: Exception) {
                Log.e(TAG, "no AudioManager", e)
                outFormat[0] = Abi.ERR_BACKEND
                return null
            }

            // A missing RECORD_AUDIO does NOT raise SecurityException from the
            // AudioRecord constructor on Android: the platform hands back an
            // object in STATE_UNINITIALIZED and logs the denial itself. Without
            // this explicit check the failure surfaced as CLEONA_VOICE_ERR_
            // NO_DEVICE, and `cleona_voice.h` keeps a separate ERR_PERMISSION
            // precisely so callers "can distinguish 'no microphone' from
            // 'permission denied' without a second call". Measured with the
            // revoked-permission negative control.
            if (!hasRecordPermission(ctx)) {
                Log.e(TAG, "RECORD_AUDIO not granted")
                outFormat[0] = Abi.ERR_PERMISSION
                return null
            }

            var record: AudioRecord? = null
            var track: AudioTrack? = null
            var aec: AcousticEchoCanceler? = null
            var ns: NoiseSuppressor? = null
            var agc: AutomaticGainControl? = null
            var ok = false
            try {
                // ─── I3: the platform decides the rate. ──────────────────
                // The hint is tried first because the ABI says it is a hint;
                // the device's own output rate comes next, because that is the
                // rate the fast path runs at (§10.4: forcing 16 kHz "excludes
                // Android's fast path"). Everything after that is a descending
                // ladder, and whatever wins is what the report states.
                val nativeRate = runCatching {
                    am.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)?.toIntOrNull()
                }.getOrNull()
                val ladder = LinkedHashSet<Int>()
                if (rateHint > 0) ladder.add(rateHint)
                if (nativeRate != null) ladder.add(nativeRate)
                ladder.addAll(listOf(48000, 44100, 32000, 24000, 16000, 8000))

                var chosen = 0
                var minRec = 0
                for (rate in ladder) {
                    if (rate < 8000 || rate > 48000) continue
                    if (rate % FRAME_HZ != 0) continue
                    val mb = runCatching {
                        AudioRecord.getMinBufferSize(
                            rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT
                        )
                    }.getOrDefault(AudioRecord.ERROR)
                    if (mb <= 0) continue
                    val mt = runCatching {
                        AudioTrack.getMinBufferSize(
                            rate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT
                        )
                    }.getOrDefault(AudioTrack.ERROR)
                    if (mt <= 0) continue
                    chosen = rate
                    minRec = mb
                    break
                }
                if (chosen == 0) {
                    Log.e(TAG, "no usable capture rate; ladder=$ladder")
                    outFormat[0] = Abi.ERR_NO_DEVICE
                    return null
                }

                val frameSamples = chosen / FRAME_HZ
                val frameBytes = frameSamples * 2

                // ─── capture ─────────────────────────────────────────────
                val recBytes = maxOf(minRec, frameBytes * CAPTURE_RING_FRAMES)
                val rec = try {
                    AudioRecord(
                        MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                        chosen,
                        AudioFormat.CHANNEL_IN_MONO,
                        AudioFormat.ENCODING_PCM_16BIT,
                        recBytes
                    )
                } catch (e: SecurityException) {
                    // Not inferred from a permission check that could disagree
                    // with what the platform actually enforces — this IS the
                    // platform refusing.
                    Log.e(TAG, "RECORD_AUDIO denied", e)
                    outFormat[0] = Abi.ERR_PERMISSION
                    return null
                } catch (e: IllegalArgumentException) {
                    Log.e(TAG, "AudioRecord rejected ${chosen}Hz", e)
                    outFormat[0] = Abi.ERR_BACKEND
                    return null
                }
                record = rec
                if (rec.state != AudioRecord.STATE_INITIALIZED) {
                    // Re-check rather than assume: the grant can be withdrawn
                    // between the check above and the constructor, and the two
                    // causes need different answers from the caller.
                    val denied = !hasRecordPermission(ctx)
                    Log.e(TAG, "AudioRecord state=${rec.state} permissionDenied=$denied")
                    outFormat[0] = if (denied) Abi.ERR_PERMISSION else Abi.ERR_NO_DEVICE
                    return null
                }

                val sessionId = rec.audioSessionId
                Log.i(TAG, "capture session id=$sessionId rate=$chosen frame=$frameSamples")

                // ─── the OS voice chain (I1) ─────────────────────────────
                // Attached to the record session id, exactly as AudioDiagnostics
                // did — and then ENABLED, which is what never happened before.
                val aecR = attachEffect("AEC", AcousticEchoCanceler.isAvailable()) {
                    AcousticEchoCanceler.create(sessionId)
                }
                aec = aecR.effect as AcousticEchoCanceler?
                val nsR = attachEffect("NS", NoiseSuppressor.isAvailable()) {
                    NoiseSuppressor.create(sessionId)
                }
                ns = nsR.effect as NoiseSuppressor?
                val agcR = attachEffect("AGC", AutomaticGainControl.isAvailable()) {
                    AutomaticGainControl.create(sessionId)
                }
                agc = agcR.effect as AutomaticGainControl?

                // ─── render, on the same voice path ──────────────────────
                val trkBytes = maxOf(
                    runCatching {
                        AudioTrack.getMinBufferSize(
                            chosen, AudioFormat.CHANNEL_OUT_MONO,
                            AudioFormat.ENCODING_PCM_16BIT
                        )
                    }.getOrDefault(0),
                    frameBytes * PLAYBACK_RING_FRAMES
                )
                val trk = try {
                    AudioTrack.Builder()
                        .setAudioAttributes(
                            AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                                .build()
                        )
                        .setAudioFormat(
                            AudioFormat.Builder()
                                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                                .setSampleRate(chosen)
                                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                                .build()
                        )
                        .setBufferSizeInBytes(trkBytes)
                        .setTransferMode(AudioTrack.MODE_STREAM)
                        .build()
                } catch (e: Exception) {
                    Log.e(TAG, "AudioTrack.Builder failed", e)
                    outFormat[0] = Abi.ERR_BACKEND
                    return null
                }
                track = trk
                if (trk.state != AudioTrack.STATE_INITIALIZED) {
                    Log.e(TAG, "AudioTrack state=${trk.state}")
                    outFormat[0] = Abi.ERR_NO_DEVICE
                    return null
                }

                val session = VoiceSession(
                    am, rec, trk, aec, ns, agc,
                    aecR.state, nsR.state, agcR.state,
                    chosen, frameSamples
                )
                outFormat[0] = chosen
                outFormat[1] = 1
                outFormat[2] = frameSamples
                outFormat[3] = frameBytes
                Log.i(
                    TAG,
                    "opened: ${chosen}Hz frame=$frameSamples duplex=${session.duplex} " +
                        "aec=${aecR.state} ns=${nsR.state} agc=${agcR.state}"
                )
                ok = true
                return session
            } finally {
                if (!ok) {
                    runCatching { aec?.release() }
                    runCatching { ns?.release() }
                    runCatching { agc?.release() }
                    runCatching { record?.release() }
                    runCatching { track?.release() }
                }
            }
        }

        /**
         * Framework API rather than `ContextCompat` (which `AudioDiagnostics`
         * uses): this class is also compiled into the standalone conformance
         * APK, which has no androidx on its classpath, and
         * `Context.checkSelfPermission` has been available since API 23 while
         * the app's minSdk is 24.
         */
        private fun hasRecordPermission(ctx: Context): Boolean =
            ctx.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED

        private class EffectResult(val effect: AudioEffect?, val state: Int)

        /**
         * Creates one OS effect on the capture session, switches it on, and
         * then **reads the state back**.
         *
         * The read-back is the entire point (I11). `setEnabled()` returning
         * SUCCESS is a statement about the request; `getEnabled()` is a
         * statement about the effect. Where the platform gives no answer at
         * all, the answer recorded is UNKNOWN — never ENABLED, because
         * "we asked for it" is not evidence (`cleona_voice.h`).
         */
        private fun attachEffect(
            name: String,
            available: Boolean,
            create: () -> AudioEffect?,
        ): EffectResult {
            if (!available) {
                Log.i(TAG, "$name: not offered by this device")
                return EffectResult(null, Abi.FX_UNAVAILABLE)
            }
            val fx = try {
                create()
            } catch (e: Exception) {
                Log.w(TAG, "$name: create threw", e)
                null
            } catch (e: UnsatisfiedLinkError) {
                Log.w(TAG, "$name: create threw", e)
                null
            }
            if (fx == null) {
                // The device advertises the effect but would not hand us an
                // instance, so we can neither enable it nor read it back. The
                // HAL may still be applying it; we cannot tell, and saying so
                // is the correct answer.
                Log.w(TAG, "$name: available but create() returned null -> not determinable")
                return EffectResult(null, Abi.FX_UNKNOWN)
            }
            val rc = try {
                fx.setEnabled(true)
            } catch (e: Exception) {
                Log.w(TAG, "$name: setEnabled threw", e)
                AudioEffect.ERROR
            }
            val readBack = try {
                fx.enabled
            } catch (e: Exception) {
                Log.w(TAG, "$name: getEnabled threw -> not determinable", e)
                return EffectResult(fx, Abi.FX_UNKNOWN)
            }
            val state = if (readBack) Abi.FX_ENABLED else Abi.FX_AVAILABLE_OFF
            Log.i(
                TAG,
                "$name: setEnabled rc=$rc hasControl=${runCatching { fx.hasControl() }
                    .getOrDefault(false)} getEnabled=$readBack"
            )
            return EffectResult(fx, state)
        }
    }
}

/**
 * Constants mirrored from `native/cleona_voice/cleona_voice.h`.
 *
 * Checked against the header at `JNI_OnLoad` via
 * [VoiceSession.Companion.abiConstants]; the facade refuses to bind if they
 * drift apart.
 */
internal object Abi {
    const val OK = 0
    const val ERR_INVALID_ARG = -1
    const val ERR_CLOSED = -2
    const val ERR_NOT_STARTED = -3
    const val ERR_ALREADY_STARTED = -4
    const val ERR_FRAME_SIZE = -5
    const val ERR_ROUTE_UNAVAILABLE = -6
    const val ERR_ROUTE_UNSUPPORTED = -7
    const val ERR_BACKEND = -8
    const val ERR_NO_DEVICE = -9
    const val ERR_PERMISSION = -10
    const val ERR_UNSUPPORTED = -11

    const val CAPTURE_FRAME = 1
    const val CAPTURE_TIMEOUT = 0
    const val CAPTURE_CLOSED = -1

    const val FX_UNAVAILABLE = 0
    const val FX_AVAILABLE_OFF = 1
    const val FX_ENABLED = 2
    const val FX_UNKNOWN = 3

    const val ROUTE_UNKNOWN = 0
    const val ROUTE_EARPIECE = 1
    const val ROUTE_SPEAKER = 2
    const val ROUTE_WIRED = 3
    const val ROUTE_BLUETOOTH = 4

    const val EV_NONE = 0
    const val EV_ROUTES_CHANGED = 1
    const val EV_INTERRUPTION_BEGIN = 2
    const val EV_INTERRUPTION_END = 3
    const val EV_FORMAT_CHANGED = 4

    const val CHAIN_ANDROID_HAL = 1
    const val BACKEND_ANDROID_AUDIORECORD = 2
}

/**
 * Maps an [AudioDeviceInfo] to a `CLEONA_VOICE_ROUTE_*`.
 *
 * Types that this ABI's five-value enumeration cannot express map to
 * ROUTE_UNKNOWN and are then excluded from the mask, rather than being folded
 * into the nearest-looking route.
 */
internal fun routeOf(dev: AudioDeviceInfo): Int = when (dev.type) {
    AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> Abi.ROUTE_EARPIECE
    AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> Abi.ROUTE_SPEAKER
    AudioDeviceInfo.TYPE_BUILTIN_SPEAKER_SAFE -> Abi.ROUTE_SPEAKER
    AudioDeviceInfo.TYPE_WIRED_HEADSET,
    AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
    AudioDeviceInfo.TYPE_USB_HEADSET,
    AudioDeviceInfo.TYPE_USB_DEVICE,
    AudioDeviceInfo.TYPE_USB_ACCESSORY,
    -> Abi.ROUTE_WIRED
    AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
    AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
    -> Abi.ROUTE_BLUETOOTH
    else -> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            (dev.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
                dev.type == AudioDeviceInfo.TYPE_BLE_SPEAKER)
        ) {
            Abi.ROUTE_BLUETOOTH
        } else {
            Abi.ROUTE_UNKNOWN
        }
    }
}

/**
 * Fixed-capacity frame ring with slot recycling.
 *
 * Two properties matter and neither is available from a plain queue:
 *
 *  - **No allocation on the audio path.** Slots are recycled, so a 50 Hz
 *    duplex session does not hand the collector 96 kB/s of short arrays.
 *  - **Drop the oldest, never the newest.** When the consumer is late, the
 *    stale frame is the worthless one. Dropping the incoming frame instead
 *    would build a permanent latency floor — the same mistake
 *    `_drainJitterBuffer` made on the playback side (`audio_engine.dart:353`).
 */
private class FrameRing(private val frameSamples: Int, private val capacity: Int) {

    private val lock = ReentrantLock()
    private val notEmpty = lock.newCondition()
    private val queue = ArrayDeque<ShortArray>(capacity)
    private val free = ArrayDeque<ShortArray>(capacity + 2)

    fun acquire(): ShortArray {
        lock.lock()
        try {
            free.removeFirstOrNull()?.let { return it }
        } finally {
            lock.unlock()
        }
        return ShortArray(frameSamples)
    }

    fun recycle(slot: ShortArray) {
        lock.lock()
        try {
            if (free.size < capacity + 2) free.addLast(slot)
        } finally {
            lock.unlock()
        }
    }

    /** @return false when an old frame had to be dropped to make room. */
    fun offerDropOldest(slot: ShortArray): Boolean {
        var dropped = false
        lock.lock()
        try {
            while (queue.size >= capacity) {
                val old = queue.removeFirst()
                if (free.size < capacity + 2) free.addLast(old)
                dropped = true
            }
            queue.addLast(slot)
            notEmpty.signal()
        } finally {
            lock.unlock()
        }
        return !dropped
    }

    /** @return a frame, or null on timeout / wake-up. */
    fun take(timeoutMs: Long): ShortArray? {
        lock.lock()
        try {
            var remaining = timeoutMs * 1_000_000L
            while (queue.isEmpty()) {
                if (remaining <= 0L) return null
                remaining = notEmpty.awaitNanos(remaining)
            }
            return queue.removeFirst()
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
            return null
        } finally {
            lock.unlock()
        }
    }

    fun wakeAll() {
        lock.lock()
        try {
            notEmpty.signalAll()
        } finally {
            lock.unlock()
        }
    }

    fun reset() {
        lock.lock()
        try {
            while (queue.isNotEmpty()) {
                val s = queue.removeFirst()
                if (free.size < capacity + 2) free.addLast(s)
            }
        } finally {
            lock.unlock()
        }
    }
}
