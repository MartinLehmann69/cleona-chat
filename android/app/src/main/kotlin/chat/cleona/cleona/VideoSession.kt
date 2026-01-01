package chat.cleona.cleona

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.params.StreamConfigurationMap
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLExt
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.util.Range
import android.util.Size
import android.view.Surface
import java.nio.ByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Android backend of the `cleona_video` ABI — work package V1.14.
 *
 * Contract: `native/cleona_video/cleona_video.h` (frozen).
 * Architecture: `Cleona_Chat_Architecture_v3_0.md` §10.6 (normative).
 * Spec: `docs/SPEC_VOICE_VIDEO_REWORK.md` §2 (I9, I10, I11, I12), §4b, §7 "V1.14",
 * §13 Errata E1, E6b.
 *
 * ---------------------------------------------------------------------------
 * WHAT LIVES HERE VS. IN THE JNI FACADE
 * ---------------------------------------------------------------------------
 * Same division of labour as `VoiceSession.kt` (V1.2): every platform decision
 * — camera selection, format negotiation, the encoder/decoder state machines,
 * the verification report — lives here; `cleona_video_android.c` is a thin JNI
 * forwarder with no video logic of its own. Two Java-only surfaces make this
 * mandatory rather than a style choice:
 *
 *   1. `CameraManager` (capture) needs a `Context`.
 *   2. A texture id usable by a Flutter `Texture` widget can only come from
 *      Flutter's own texture registry (see [VideoTextureProvider] below) — an
 *      NDK-manufactured `ANativeWindow`/GL texture the Dart layer never
 *      registered is not decodable by that widget. There is no NDK
 *      equivalent for this, the video analogue of §10.4's argument for why
 *      voice needs the Java API on Android.
 *
 * ---------------------------------------------------------------------------
 * NO PIXELS IN DART, AND NONE HERE EITHER (I10)
 * ---------------------------------------------------------------------------
 *     camera -> Camera2 capture session -> MediaCodec encoder input Surface
 *                                             (createInputSurface())
 *     MediaCodec decoder -> output Surface -> SurfaceTexture -> Flutter texture
 *
 * This class never touches a pixel: the encoder's input is a `Surface` the
 * camera writes into directly, and the decoder's output is a `Surface` a
 * renderer reads from directly. The only things that cross into or out of
 * Kotlin are encoded byte buffers (`readEncoded`/`submitEncoded`) and an
 * opaque texture id (`getTextureId`).
 *
 * ---------------------------------------------------------------------------
 * WHY CAMERA2, NOT CAMERAX (a disclosed, deliberate deviation from a backend
 * id name)
 * ---------------------------------------------------------------------------
 * `cleona_video.h` defines `CLEONA_VIDEO_BACKEND_ANDROID_CAMERAX` (2) as the
 * only Android capture-backend id and no `..._CAMERA2` alternative. This
 * class uses the platform `android.hardware.camera2` API directly rather than
 * the androidx CameraX library, for two reasons that are both outside this
 * package's ownership to change: (a) CameraX is not a dependency of the app
 * today and adding one is a `build.gradle.kts` change this package does not
 * own (SPEC §9 hotspot table; requested nowhere here because it is not
 * needed), and (b) CameraX's `Recorder`/`VideoCapture` use cases sit on top of
 * Camera2 for exactly the input-surface hookup this class does directly, so
 * the extra layer buys nothing for a two-endpoint camera->encoder pipeline
 * with no preview UI of its own.
 *
 * `report.captureBackend` therefore reports `CLEONA_VIDEO_BACKEND_ANDROID_CAMERAX`
 * as the closest defined id rather than inventing a new one — the frozen
 * header is not this package's file to extend, and doing so unilaterally
 * would let four platform packages invent four different numberings, which is
 * the exact failure the backend-id block in `cleona_video.h` exists to
 * prevent. This is flagged explicitly in the V1.14 acceptance report as a
 * finding for the header owner, not silently worked around. It does not
 * touch I11: the `hardware_encode`/`hardware_decode` fields — the ones I11 is
 * actually about — are independently verified from `MediaCodecInfo`, never
 * inferred from which capture API was used.
 *
 * ---------------------------------------------------------------------------
 * THE ONE TRAP THIS PACKAGE WAS BRIEFED ON: ERR_RATE_UNACHIEVABLE vs.
 * ERR_BACKEND
 * ---------------------------------------------------------------------------
 * `cleona_video.h`'s Erratum 6b names a known, undischargeable gap: the two
 * codes describe the BACKEND'S INTERNAL REASONING, not observable behaviour,
 * so the conformance harness cannot tell a backend that swaps them from one
 * that does not. On Android the realistic trigger is exactly the scenario the
 * V1.14 briefing named: another app holds the camera
 * (`CameraDevice.StateCallback.onError(ERROR_CAMERA_IN_USE)`). A backend that
 * reports that as "bandwidth too low" tells the user an untrue fact about
 * their own device.
 *
 * The discipline this class follows to keep the two apart, stated once here
 * so every call site below can point back to it:
 *
 *   PHASE 1 (link feasibility) touches NO camera and NO codec. It only reads
 *   `CameraCharacteristics` (a static, local, already-cached property lookup
 *   that does not acquire the camera and cannot fail with "camera busy") and
 *   an in-process preset ladder, and decides ONLY whether some achievable
 *   encoder step fits `cfg.maxFrameBytes`. This is the ONLY place
 *   `ERR_RATE_UNACHIEVABLE` is ever returned — see [choosePreset].
 *
 *   PHASE 2 (device feasibility) runs only after phase 1 has already
 *   committed to a preset. It opens the camera, builds the capture session,
 *   configures the encoder and decoder. Every failure here — camera in use,
 *   permission denied, codec init refused, device disconnected — maps to
 *   `ERR_BACKEND` (or, when no camera exists on the device at all,
 *   `ERR_UNSUPPORTED`) and NEVER to `ERR_RATE_UNACHIEVABLE`, because none of
 *   those failures says anything about the link's bandwidth. See
 *   [openCameraAndPipeline] and the exhaustive branch list in its doc.
 *
 * Because phase 1 commits to a preset before phase 2 ever runs, a device
 * failure in phase 2 structurally cannot produce the phase-1 verdict, and a
 * phase-1 refusal never reaches the camera at all. The two codes are kept
 * apart by data flow, not by a check that could be forgotten at a call site.
 */
/**
 * Erratum 7 — the camera-side constructor arguments are nullable.
 *
 * A DECODE_ONLY session acquires no camera at all, so there is no
 * [CameraManager], no camera id and no camera [HandlerThread] to hand it. They
 * are not "optional dependencies" in the usual sense: they are exactly the
 * things this direction is defined by NOT having. Every use site below is
 * inside a `!decodeOnly` branch or null-safe, and [decodeOnly] — not a null
 * check — is what the control functions decide on, so the intent stays
 * readable instead of being inferred from a missing object.
 */
class VideoSession private constructor(
    private val cameraManager: CameraManager?,
    initialCameraId: String,
    private val cameraThread: HandlerThread?,
    private val cameraHandler: Handler?,
    initialNegotiated: VConfig,
) {
    /** Erratum 7: fixed at open(), never renegotiated. A session opened to
     *  decode cannot grow a camera — [reconfigure] rejects a direction flip. */
    private val decodeOnly: Boolean = initialNegotiated.direction == VAbi.DIR_DECODE_ONLY

    /** The currently active camera. Mutable because [switchCamera] changes it;
     *  every call site below reads this field rather than the constructor
     *  argument, or a post-switch reconfigure() would silently reopen the
     *  camera the session started with. */
    private var cameraId: String = initialCameraId
    // ─────────────────────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────────────────────

    private val lock = ReentrantLock()

    @Volatile private var state = ST_OPEN
    private var negotiated: VConfig = initialNegotiated

    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var encoder: MediaCodec? = null
    private var encoderInputSurface: Surface? = null
    private var decoder: MediaCodec? = null
    private var decoderSurface: Surface? = null
    private var textureEntry: VideoTextureEntry? = null
    private var headlessTexture: HeadlessTexture? = null

    private var encodeThread: Thread? = null
    private var decodeOutThread: Thread? = null
    private var decodeInThread: Thread? = null
    @Volatile private var generation = 0

    /** Erratum 7: a decode-only session never had a camera. That is its state,
     *  not a user mute — [setCaptureEnabled] cannot lift it. */
    @Volatile private var captureEnabled = !decodeOnly

    /** Single flag meaning "issue `PARAMETER_KEY_REQUEST_SYNC_FRAME` before the
     *  next produced frame". This is a REQUEST, not a label: whether a frame
     *  actually IS a keyframe is decided exclusively by
     *  `MediaCodec.BUFFER_FLAG_KEY_FRAME` in [encodeLoop] — never by this
     *  flag directly. A fresh encoder configuration (start(), a geometry
     *  restart in reconfigure()) already guarantees its first output frame is
     *  a keyframe by MediaCodec contract, so setting this there is a harmless,
     *  defensive redundancy, not the mechanism V9/V10/V12/V21/V26 rely on for
     *  a RUNNING encoder — [requestKeyframe], [setCaptureEnabled] and the
     *  periodic schedule are the paths that actually need it, because those
     *  keep the same encoder instance running. */
    @Volatile private var pendingSyncFrameRequest = true
    private var framesSinceKeyframe = 0

    // Codec-config bytes (SPS/PPS) buffered from BUFFER_FLAG_CODEC_CONFIG and
    // prepended to the next keyframe -- see encodeLoop().
    @Volatile private var pendingConfigBytes: ByteArray? = null

    // Presentation clock: accumulated per frame, never `index * 1e6 / fps`, so
    // that a reconfigure which raises fps again cannot walk pts backwards
    // (Erratum 1, mirrors the mock's pts_next_us). Origin is the first raw
    // encoder timestamp seen, so pts "starts near zero at first start()"
    // per the ABI's read_encoded doc.
    private var ptsOriginUs = -1L
    private var lastPtsUs = -1L

    // ─── report counters — AtomicLong so fillReport() never blocks the data
    // path, matching VoiceSession.kt's rationale for underruns/overruns. ───
    private val framesCaptured = AtomicLong(0)
    private val framesEncoded = AtomicLong(0)
    private val framesDroppedOversize = AtomicLong(0)
    private val framesDecoded = AtomicLong(0)
    private val decodeFailures = AtomicLong(0)
    // Erratum 7: with no encoder, its absence is KNOWN, not undetermined —
    // HW_NO and BACKEND_NONE, never HW_NOT_DETERMINABLE. configureEncoder()
    // is the only writer of these two and never runs for a decode-only
    // session, so the values set here are final.
    @Volatile private var hardwareEncode =
        if (decodeOnly) VAbi.HW_NO else VAbi.HW_NOT_DETERMINABLE
    @Volatile private var hardwareDecode = VAbi.HW_NOT_DETERMINABLE
    @Volatile private var encodeBackendId =
        if (decodeOnly) VAbi.BACKEND_NONE else VAbi.BACKEND_ANDROID_MEDIACODEC
    @Volatile private var decodeBackendId = VAbi.BACKEND_ANDROID_MEDIACODEC

    // ─── the encoded-frame output ring, drained by readEncoded() ───────────
    private val outputRing = VideoFrameRing(OUTPUT_RING_CAPACITY)
    // Held across an ERR_BUFFER_TOO_SMALL so the caller can retry with a
    // bigger buffer without losing the frame -- same contract the mock and
    // the JNI-facing struct field documentation both describe.
    private var pendingTooSmall: EncodedFrame? = null

    // ─── the decoder input queue, drained by the decode-in thread ──────────
    private val inputQueue = InputQueue(INPUT_QUEUE_CAPACITY)
    @Volatile private var awaitingKeyframe = true

    private var cameraIndex = 0
    /** Erratum 7: not `lateinit` any more. A decode-only session never
     *  enumerates cameras, and a `lateinit` read would then throw
     *  `UninitializedPropertyAccessException` straight through JNI instead of
     *  returning the ERR_UNSUPPORTED the ABI promises. */
    private var cameraIds: List<String> = emptyList()

    init {
        if (cameraManager != null) {
            cameraIds = listCameraIds(cameraManager)
            cameraIndex = cameraIds.indexOf(cameraId).coerceAtLeast(0)
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Lifecycle: start / stop / release
    // ─────────────────────────────────────────────────────────────────────

    /** `cleona_video_start`. */
    fun start(): Int = lock.withLock {
        if (state == ST_CLOSED) return VErr.ERR_STATE
        if (state == ST_RUNNING) return VErr.ERR_STATE
        val gen = ++generation
        val rc = openCameraAndPipeline(negotiated)
        if (rc != VErr.OK) {
            teardownPipelineLocked()
            return rc
        }
        state = ST_RUNNING
        launchDataThreadsLocked(gen)
        return VErr.OK
    }

    /** Resets per-run state and launches the three data-path threads against
     *  [gen]. Shared by [start] and reconfigure()'s geometry-change restart
     *  path (both success and post-failure fallback) so the two can never
     *  drift apart -- a session with a live pipeline but no threads driving
     *  it would hang every future readEncoded()/submitEncoded() silently.
     *  Caller holds [lock] and has already set `encoder`/`decoder` (via
     *  [openCameraAndPipeline]) for the generation being launched. */
    private fun launchDataThreadsLocked(gen: Int) {
        pendingSyncFrameRequest = true
        framesSinceKeyframe = 0
        awaitingKeyframe = true
        // ptsOriginUs is reset (a brand-new MediaCodec instance has its own
        // raw presentation-time clock starting near zero, so the old offset
        // is meaningless) -- but lastPtsUs is deliberately NOT reset here.
        // encodeLoop() re-anchors the new origin against the surviving
        // lastPtsUs (observed on device: a geometry-change restart inside
        // reconfigure() resetting both made pts visibly walk backwards
        // across the restart -- V8/"pts is not strictly increasing",
        // previous=1075480 current=0 -- which is exactly the bug this
        // class's own doc on pts warns every backend against). A restart
        // during `start()`'s very first call is unaffected either way:
        // lastPtsUs is already -1 at that point (session-initial value), so
        // the anchor still lands at pts=0 for the first frame, matching
        // "starts near zero at first start()" (cleona_video.h).
        ptsOriginUs = -1L
        pendingConfigBytes = null
        outputRing.reset()
        pendingTooSmall = null
        inputQueue.reset()

        // Erratum 7: no camera and no encoder, so there is nothing for the
        // encode thread to drive. encodeLoop() would return immediately on its
        // `val codec = encoder ?: return`, but a group call with three remote
        // tiles (docs/CALLS.md) would still have started three threads to do
        // nothing. stop() joins these null-safely.
        if (!decodeOnly) {
            encodeThread = Thread({ encodeLoop(gen) }, "cleona-video-encode").apply {
                priority = Thread.MAX_PRIORITY
                start()
            }
        }
        decodeOutThread = Thread({ decodeOutLoop(gen) }, "cleona-video-decode-out").apply {
            start()
        }
        decodeInThread = Thread({ decodeInLoop(gen) }, "cleona-video-decode-in").apply {
            start()
        }
    }

    /** `cleona_video_stop`. Idempotent; drops everything queued. */
    fun stop() {
        val gen: Int
        lock.withLock {
            if (state != ST_RUNNING) return
            state = ST_OPEN
            gen = ++generation
            teardownPipelineLocked()
        }
        outputRing.wakeAll()
        inputQueue.wakeAll()
        runCatching { encodeThread?.join(THREAD_JOIN_MS) }
        runCatching { decodeOutThread?.join(THREAD_JOIN_MS) }
        runCatching { decodeInThread?.join(THREAD_JOIN_MS) }
        encodeThread = null
        decodeOutThread = null
        decodeInThread = null
        pendingTooSmall = null
        outputRing.reset()
        inputQueue.reset()
    }

    /** `cleona_video_close`. Releases every platform object. */
    fun release() {
        stop()
        lock.withLock {
            if (state == ST_CLOSED) return
            state = ST_CLOSED
            runCatching { textureEntry?.release() }
            textureEntry = null
            runCatching { headlessTexture?.release() }
            headlessTexture = null
            runCatching { cameraThread?.quitSafely() }
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Negotiation — Erratum 1
    // ─────────────────────────────────────────────────────────────────────

    /** `cleona_video_reconfigure`. `out[CFG_MFB]` carries the negotiated
     *  ceiling on OK, or is left to the caller's zeroed array on refusal —
     *  the ABI defines reconfigure's failure channel as the return code, not
     *  the out array (unlike open()'s Erratum 6b in-band channel). */
    fun reconfigure(cfg: IntArray, out: IntArray): Int = lock.withLock {
        if (state == ST_CLOSED) return VErr.ERR_STATE
        val req = VConfig.fromInts(cfg) ?: return VErr.ERR_INVALID
        if (!req.isValid()) return VErr.ERR_INVALID
        // Erratum 7: the direction is fixed at open() — a session opened to
        // decode cannot grow a camera. Checked before anything else touches
        // hardware, so a refused reconfigure leaves the session untouched like
        // every other one (Erratum 1, side-effect freedom).
        if (req.direction != negotiated.direction) return VErr.ERR_INVALID

        // PHASE 1 discipline applies here exactly as in openSession(): decide
        // achievability from characteristics + arithmetic only, before
        // touching any hardware. See the class doc's "one trap" section.
        val preset = if (decodeOnly) {
            chooseDecodeOnlyPreset(req) ?: return VErr.ERR_RATE_UNACHIEVABLE
        } else {
            val chars = runCatching { cameraManager!!.getCameraCharacteristics(cameraId) }
                .getOrNull() ?: return VErr.ERR_BACKEND
            choosePreset(chars, req) ?: return VErr.ERR_RATE_UNACHIEVABLE
        }

        val geometryChanged = preset.width != negotiated.width || preset.height != negotiated.height
        val next = negotiated.copy(
            codec = VAbi.CODEC_H264,
            width = preset.width,
            height = preset.height,
            fps = preset.fps,
            targetBitrateKbps = preset.bitrateKbps,
            maxFrameBytes = req.maxFrameBytes,
            keyframeIntervalFrames = if (req.keyframeIntervalFrames > 0) req.keyframeIntervalFrames else negotiated.keyframeIntervalFrames,
        )

        if (state == ST_RUNNING) {
            if (geometryChanged) {
                // The peer's decoder cannot continue from a reference picture
                // of a different size -- restart camera + encoder with the
                // new geometry. A failure here is a device condition
                // (ERR_BACKEND), not a link condition: phase 1 already
                // proved a step fits: getting the hardware to actually run it
                // is a separate question.
                val gen = ++generation
                teardownPipelineLocked()
                val rc = openCameraAndPipeline(next)
                if (rc != VErr.OK) {
                    // Side-effect free on failure (cleona_video.h): fall back
                    // to the previous configuration rather than leaving the
                    // session half-torn-down. openCameraAndPipeline() closes
                    // whatever it partially opened before returning a
                    // non-OK code (see its own doc), so there is nothing left
                    // to tear down before retrying with the old config.
                    val fallbackRc = openCameraAndPipeline(negotiated)
                    if (fallbackRc == VErr.OK) {
                        // The old encode/decode threads already exited (their
                        // captured `gen` no longer matches `generation`,
                        // bumped above) -- new ones are required, or
                        // readEncoded()/submitEncoded() would hang forever
                        // against a live but undriven pipeline.
                        launchDataThreadsLocked(gen)
                    }
                    return rc
                }
                launchDataThreadsLocked(gen)
            } else {
                // Pure rate change: dynamic bitrate via PARAMETER_KEY_VIDEO_BITRATE,
                // no restart, no forced keyframe (cleona_video.h: "a pure rate
                // change does not force one").
                runCatching {
                    encoder?.setParameters(Bundle().apply {
                        putInt(MediaCodec.PARAMETER_KEY_VIDEO_BITRATE, next.targetBitrateKbps * 1000)
                    })
                }.onFailure {
                    Log.w(TAG, "setParameters(VIDEO_BITRATE) failed", it)
                    return VErr.ERR_BACKEND
                }
                // A frame already encoded under the previous ceiling and
                // still pending is discarded if it no longer fits the NEW
                // ceiling -- the one documented benign tick of
                // frames_dropped_oversize (Erratum 1).
                val pending = outputRing.peekNewest()
                if (pending != null && pending.data.size > next.maxFrameBytes) {
                    outputRing.dropNewest()
                    framesDroppedOversize.incrementAndGet()
                }
                if (pendingTooSmall != null && pendingTooSmall!!.data.size > next.maxFrameBytes) {
                    pendingTooSmall = null
                    framesDroppedOversize.incrementAndGet()
                }
            }
        }

        negotiated = next
        writeCfgInto(out, next)
        return VErr.OK
    }

    // ─────────────────────────────────────────────────────────────────────
    // Data path
    // ─────────────────────────────────────────────────────────────────────

    /** `cleona_video_read_encoded`. `buf` is the CALLER's buffer, wrapped by
     *  the JNI facade with `NewDirectByteBuffer` fresh on every call -- see
     *  `cleona_video_android.c`'s file header for why nothing is cached here. */
    fun readEncoded(buf: ByteBuffer, bufCap: Int, timeoutMs: Int, outMeta: IntArray, outPts: LongArray): Int {
        if (state != ST_RUNNING) return VErr.ERR_STATE
        // Erratum 7: no encoder, so a frame can never arrive -- but the session
        // is running, so this is a TIMEOUT and not READ_CLOSED/ERR_STATE.
        // Before the ring, because a blocking read (timeoutMs < 0) would
        // otherwise wait forever on something that cannot happen. After the
        // state check, so a stopped session still reports ERR_STATE.
        if (decodeOnly) return VErr.READ_TIMEOUT

        val frame = pendingTooSmall ?: run {
            val f = outputRing.take(timeoutMs.toLong()) ?: return if (state != ST_RUNNING) VErr.ERR_STATE else VErr.READ_TIMEOUT
            f
        }
        if (frame.data.size > bufCap) {
            pendingTooSmall = frame
            outMeta[0] = frame.data.size
            outMeta[1] = frame.flags
            return VErr.ERR_BUFFER_TOO_SMALL
        }
        pendingTooSmall = null
        buf.clear()
        buf.put(frame.data)
        outMeta[0] = frame.data.size
        outMeta[1] = frame.flags
        outPts[0] = frame.ptsUs
        return VErr.READ_FRAME
    }

    /** `cleona_video_submit_encoded`. Never blocks: valid input is handed to
     *  [inputQueue] and drained by [decodeInLoop]; invalid input is rejected
     *  synchronously. */
    fun submitEncoded(buf: ByteBuffer, size: Int, flags: Int): Int {
        if (state != ST_RUNNING) return VErr.ERR_STATE
        val data = ByteArray(size)
        buf.rewind()
        buf.get(data, 0, size)

        val nalType = annexBFirstNalType(data)
        if (nalType < 0) {
            // Not a parseable Annex-B NAL at all -- the malformed-bitstream
            // case conformance.c's V24 exercises. Rejected before it ever
            // reaches the decoder, matching the mock's policy of returning
            // ERR_DECODE rather than feeding a hardware decoder garbage that
            // might hang or crash it.
            decodeFailures.incrementAndGet()
            return VErr.ERR_DECODE
        }
        val isKeyframe = (flags and VAbi.FLAG_KEYFRAME) != 0
        val bitstreamIsIdr = nalType == NAL_TYPE_IDR || nalType == NAL_TYPE_SPS
        if (isKeyframe != bitstreamIsIdr) {
            // The peer's flag and its own bitstream disagree. Feeding the
            // decoder a lie is worse than refusing it (cleona_video.h,
            // submit_encoded doc).
            decodeFailures.incrementAndGet()
            return VErr.ERR_DECODE
        }

        if (awaitingKeyframe && !isKeyframe) {
            return VErr.SUBMIT_AWAITING_KEYFRAME
        }
        if (isKeyframe) awaitingKeyframe = false

        val bufferFlags = if (isKeyframe) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0

        // Fast path: hand the frame straight to the decoder on THIS thread
        // when an input buffer is immediately free.
        // `dequeueInputBuffer(0)` is non-blocking by Android's own contract
        // (timeoutUs=0 means "do not wait"), so this keeps "never blocks"
        // (cleona_video.h). It exists to remove a thread hand-off from the
        // critical path: queuing onto [inputQueue] for [decodeInLoop] to pick
        // up adds a wait for that thread to be scheduled and a condition-
        // variable signal round trip. OBSERVED ON DEVICE (Pixel 8 Pro):
        // without this fast path, the conformance harness's V22 -- which
        // checks `frames_decoded` immediately after submit_encoded returns,
        // with no sleep -- lost that race consistently (decoded=0 right
        // after submission, yet the SAME two frames showed up decoded by the
        // time a later check re-read the report, proving the frames were
        // never lost, only slow to complete relative to the harness's
        // zero-wait check). submit_encoded's own contract forbids fixing
        // this by blocking here to wait for the decode to finish; the
        // correct fix is removing self-inflicted latency instead.
        //
        // A stale `decoder` reference (torn down concurrently by
        // reconfigure()'s geometry-change restart) throws on these calls;
        // caught and treated as "fast path unavailable", falling through to
        // the queued path below, which is generation-scoped in
        // [decodeInLoop] and therefore already race-safe.
        val d = decoder
        if (d != null) {
            val idx = try {
                d.dequeueInputBuffer(0)
            } catch (e: Exception) {
                -1
            }
            if (idx >= 0) {
                try {
                    val ib = d.getInputBuffer(idx)
                    ib?.clear()
                    ib?.put(data)
                    d.queueInputBuffer(idx, 0, data.size, 0, bufferFlags)
                    return VErr.SUBMIT_ACCEPTED
                } catch (e: Exception) {
                    Log.w(TAG, "direct queueInputBuffer failed, falling back to the queue", e)
                    // Falls through -- the buffer index above is abandoned;
                    // MediaCodec reclaims un-queued dequeued buffers on the
                    // next stop()/flush(), and this path is only reached on
                    // an exception that already indicates something is
                    // wrong with continuing to drive this codec instance
                    // directly.
                }
            }
        }

        if (!inputQueue.offer(data, bufferFlags)) {
            // Queue full: the decoder is falling behind. Dropping is the
            // right call for a live-media path (I8) -- this frame is stale by
            // the time it could be fed anyway. Counted as a decode failure
            // since it was accepted-in-principle but never reached the
            // decoder.
            decodeFailures.incrementAndGet()
            return VErr.ERR_DECODE
        }
        return VErr.SUBMIT_ACCEPTED
    }

    /** `cleona_video_get_texture_id`. */
    fun getTextureId(out: LongArray): Int {
        if (state != ST_RUNNING) return VErr.ERR_STATE
        val id = textureEntry?.id() ?: headlessTexture?.id ?: return VErr.ERR_UNSUPPORTED
        out[0] = id
        return VErr.OK
    }

    /** `cleona_video_request_keyframe`. Idempotent, collapses into the next
     *  produced frame (cleona_video.h). */
    fun requestKeyframe(): Int {
        if (state != ST_RUNNING) return VErr.ERR_STATE
        // Erratum 7: this asks OUR encoder, and a decode-only session has none.
        // Asking the PEER for a keyframe is signalling, not this ABI.
        if (decodeOnly) return VErr.ERR_UNSUPPORTED
        pendingSyncFrameRequest = true
        return VErr.OK
    }

    /** `cleona_video_set_capture_enabled` — I12, the only video mute in this
     *  ABI. Pauses the camera's repeating request rather than tearing the
     *  session down: the encoder and decoder stay alive, so the peer's
     *  picture keeps running (cleona_video.h). */
    fun setCaptureEnabled(on: Boolean) = lock.withLock {
        if (state != ST_RUNNING) return
        // Erratum 7: accepted and ignored. Capture is already off and cannot be
        // switched on. A caller driving N sessions uniformly must not have to
        // special-case this one.
        if (decodeOnly) return
        if (on == captureEnabled) return
        if (on) {
            runCatching {
                captureSession?.setRepeatingRequest(buildCaptureRequest(), null, cameraHandler)
            }.onFailure { Log.w(TAG, "resume repeating request failed", it) }
            // The peer's decoder has been starved; any P-frame now would be
            // undecodable there (cleona_video.h) -- unconditional, not a
            // heuristic.
            pendingSyncFrameRequest = true
        } else {
            runCatching { captureSession?.stopRepeating() }
                .onFailure { Log.w(TAG, "stopRepeating failed", it) }
        }
        captureEnabled = on
    }

    /** `cleona_video_switch_camera`. The negotiated format is unchanged, so
     *  no renegotiation is needed -- only the camera device and capture
     *  session restart; encoder, decoder and their threads are untouched. */
    fun switchCamera(): Int = lock.withLock {
        if (state != ST_RUNNING) return VErr.ERR_STATE
        // Erratum 7: a decode-only session has no camera at all. Explicit
        // rather than relying on cameraIds being empty, so the intent is in the
        // code instead of in a counter.
        if (decodeOnly || cameraIds.size < 2) return VErr.ERR_UNSUPPORTED
        val nextIndex = (cameraIndex + 1) % cameraIds.size
        val nextId = cameraIds[nextIndex]
        val previousId = cameraId

        teardownCameraOnlyLocked()
        cameraId = nextId
        val opened = openCameraDeviceBlocking(cameraId)
        if (opened == null) {
            // Fall back to the previous camera rather than leaving the
            // session cameraless. A camera-open failure here is a device
            // condition (ERR_BACKEND), matching the "one trap" discipline:
            // switching cameras is never a bandwidth question.
            cameraId = previousId
            openCameraDeviceBlocking(cameraId)?.let { cameraDevice = it }
            rebuildCaptureSessionBlocking(negotiated)
            return VErr.ERR_BACKEND
        }
        cameraDevice = opened
        cameraIndex = nextIndex
        val rc = rebuildCaptureSessionBlocking(negotiated)
        if (rc != VErr.OK) return rc
        pendingSyncFrameRequest = true
        outputRing.reset()
        pendingTooSmall = null
        return VErr.OK
    }

    // ─────────────────────────────────────────────────────────────────────
    // Verification report (I11)
    // ─────────────────────────────────────────────────────────────────────

    fun fillReport(ints: IntArray, longs: LongArray) {
        val neg = negotiated
        ints[0] = VAbi.CODEC_H264
        ints[1] = hardwareEncode
        ints[2] = hardwareDecode
        ints[3] = neg.width
        ints[4] = neg.height
        ints[5] = neg.fps
        // See the class doc: CAMERAX is the closest defined id for a Camera2
        // capture path, a disclosed deviation, not a guess about hardware.
        // Erratum 7: with no capture path there is no backend to name.
        // hardwareEncode/encodeBackendId already carry HW_NO/BACKEND_NONE from
        // construction, since configureEncoder() never runs for this direction.
        ints[6] = if (decodeOnly) VAbi.BACKEND_NONE else VAbi.BACKEND_ANDROID_CAMERAX
        ints[7] = encodeBackendId
        longs[0] = framesCaptured.get()
        longs[1] = framesEncoded.get()
        longs[2] = framesDroppedOversize.get()
        longs[3] = framesDecoded.get()
        longs[4] = decodeFailures.get()
    }

    // ═════════════════════════════════════════════════════════════════════
    // Phase 1 — link feasibility. Touches no camera, no codec (see class doc).
    // ═════════════════════════════════════════════════════════════════════

    // ═════════════════════════════════════════════════════════════════════
    // Phase 2 — device feasibility. Every failure below is ERR_BACKEND or
    // ERR_UNSUPPORTED, never ERR_RATE_UNACHIEVABLE — see class doc.
    // ═════════════════════════════════════════════════════════════════════

    /** Opens the camera, builds the capture session and configures the
     *  encoder + decoder for [cfg]. Caller holds [lock]. Every return path is
     *  annotated with WHY it chose the code it did (V1.14 briefing §3). */
    private fun openCameraAndPipeline(cfg: VConfig): Int {
        // Erratum 7: a decode-only session builds neither camera nor encoder,
        // and open() must not fail because either is missing. What remains is
        // exactly the decode path — configureDecoder() also acquires the
        // texture the decoder renders into (acquireDecodeSurfaceLocked), so
        // this single call is the complete decode-only pipeline. Skipping
        // rebuildCaptureSessionBlocking() is not optional: it returns
        // ERR_BACKEND outright without a cameraDevice and an encoder surface.
        if (decodeOnly) return configureDecoder(cfg)

        val device = openCameraDeviceBlocking(cameraId)
            ?: return VErr.ERR_BACKEND // reason logged in openCameraDeviceBlocking;
        // every branch there is a device condition (busy / disconnected /
        // service error / permission), never a bandwidth condition -- phase 1
        // already proved a preset fits before this function was ever called.
        cameraDevice = device

        val encRc = configureEncoder(cfg)
        if (encRc != VErr.OK) {
            device.close()
            cameraDevice = null
            return encRc
        }
        val decRc = configureDecoder(cfg)
        if (decRc != VErr.OK) {
            releaseEncoderLocked()
            device.close()
            cameraDevice = null
            return decRc
        }
        return rebuildCaptureSessionBlocking(cfg)
    }

    /** Opens [id]. Returns null on ANY failure and logs which of the four
     *  device-level reasons it was — all four map to ERR_BACKEND at the call
     *  site above except "no camera at all", which is caught earlier by
     *  [choosePreset] failing to find output sizes and therefore never
     *  reaches this function in the open() path (see [openSession]). */
    private fun openCameraDeviceBlocking(id: String): CameraDevice? {
        val ctx = appContext ?: run {
            Log.e(TAG, "openCameraDeviceBlocking before VideoSession.install(context, ...)")
            return null
        }
        if (ctx.checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            // Permission denial is retryable (the user can grant it and the
            // caller can try again) -- ERR_BACKEND, not a link condition and
            // not "device has no camera at all". Camera2's own contract:
            // openCamera() would throw SecurityException here anyway; this
            // check produces a defined log line instead of relying on the
            // exception message.
            Log.e(TAG, "CAMERA permission not granted")
            return null
        }
        // Erratum 7: a decode-only session has no CameraManager. It never
        // reaches this function -- openCameraAndPipeline() returns before it
        // and switchCamera() refuses with ERR_UNSUPPORTED -- so this is a
        // guard against a future caller, not a live path. Returning null (the
        // documented "device condition" answer) rather than `!!` keeps that
        // hypothetical bug a logged ERR_BACKEND instead of a crash in JNI.
        val manager = cameraManager ?: run {
            Log.e(TAG, "openCameraDeviceBlocking on a decode-only session")
            return null
        }
        val latch = CountDownLatch(1)
        var result: CameraDevice? = null
        var errorReason = "none"
        try {
            manager.openCamera(id, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    result = camera
                    latch.countDown()
                }
                override fun onDisconnected(camera: CameraDevice) {
                    errorReason = "disconnected"
                    runCatching { camera.close() }
                    latch.countDown()
                }
                override fun onError(camera: CameraDevice, error: Int) {
                    // THE TRAP, DISCHARGED: every one of these five platform
                    // error codes is a property of the DEVICE at this moment
                    // (another app holds it, too many cameras open, admin
                    // policy, HAL/service fault) -- none of them is a
                    // statement about available bandwidth. This callback
                    // therefore only ever contributes to an ERR_BACKEND
                    // decision at the call site; ERR_RATE_UNACHIEVABLE is
                    // physically unreachable from here because this function
                    // has no maxFrameBytes in scope to compare against.
                    errorReason = when (error) {
                        CameraDevice.StateCallback.ERROR_CAMERA_IN_USE -> "camera in use by another app/process"
                        CameraDevice.StateCallback.ERROR_MAX_CAMERAS_IN_USE -> "too many cameras in use system-wide"
                        CameraDevice.StateCallback.ERROR_CAMERA_DISABLED -> "camera disabled by device policy"
                        CameraDevice.StateCallback.ERROR_CAMERA_DEVICE -> "fatal camera device error"
                        CameraDevice.StateCallback.ERROR_CAMERA_SERVICE -> "fatal camera service error"
                        else -> "unknown error $error"
                    }
                    runCatching { camera.close() }
                    latch.countDown()
                }
            }, cameraHandler)
        } catch (e: CameraAccessException) {
            Log.e(TAG, "openCamera($id) threw CameraAccessException", e)
            return null
        } catch (e: SecurityException) {
            Log.e(TAG, "openCamera($id) denied", e)
            return null
        } catch (e: IllegalArgumentException) {
            Log.e(TAG, "openCamera($id) rejected the id", e)
            return null
        }
        if (!latch.await(CAMERA_OPEN_TIMEOUT_MS, TimeUnit.MILLISECONDS)) {
            Log.e(TAG, "openCamera($id) timed out after ${CAMERA_OPEN_TIMEOUT_MS}ms")
            return null
        }
        if (result == null) {
            Log.e(TAG, "openCamera($id) failed: $errorReason")
        }
        return result
    }

    private fun configureEncoder(cfg: VConfig): Int {
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, cfg.width, cfg.height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, cfg.targetBitrateKbps * 1000)
            setInteger(MediaFormat.KEY_FRAME_RATE, cfg.fps)
            // Effectively "never" -- this backend drives every keyframe
            // itself (periodic schedule + request_keyframe), so the
            // encoder's own automatic I-frame timer must not also fire, or
            // V9/V10/V12/V26's exact-keyframe-count assumptions would race
            // an independent, undocumented device timer.
            setFloat(MediaFormat.KEY_I_FRAME_INTERVAL, 3600f)
            setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline)
        }
        val (name, hw) = findCodecFor(format, encoder = true) ?: run {
            Log.e(TAG, "no H.264 encoder available at all")
            return VErr.ERR_UNSUPPORTED
        }
        // BITRATE_MODE_CBR gives the hardware rate controller a tighter
        // instantaneous budget than VBR, which helps -- but does not
        // guarantee -- staying under max_frame_bytes; the I9 backstop in
        // encodeLoop() is what actually enforces the ceiling.
        val caps = runCatching {
            MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
                .first { it.name == name }
                .getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC)
                .encoderCapabilities
        }.getOrNull()
        if (caps?.isBitrateModeSupported(MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR) == true) {
            format.setInteger(MediaFormat.KEY_BITRATE_MODE, MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR)
        }

        val codec = try {
            MediaCodec.createByCodecName(name)
        } catch (e: Exception) {
            Log.e(TAG, "MediaCodec.createByCodecName($name) failed", e)
            return VErr.ERR_BACKEND
        }
        try {
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            val surface = codec.createInputSurface()
            codec.start()
            encoder = codec
            encoderInputSurface = surface
            hardwareEncode = hw
            encodeBackendId = VAbi.BACKEND_ANDROID_MEDIACODEC
            return VErr.OK
        } catch (e: Exception) {
            Log.e(TAG, "encoder configure/start failed for $name", e)
            runCatching { codec.release() }
            return VErr.ERR_BACKEND
        }
    }

    private fun configureDecoder(cfg: VConfig): Int {
        val surface = acquireDecodeSurfaceLocked() ?: run {
            Log.e(TAG, "no decode surface available (no TextureRegistry installed and " +
                "the headless EGL fallback failed)")
            return VErr.ERR_BACKEND
        }
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, cfg.width, cfg.height)
        val (name, hw) = findCodecFor(format, encoder = false) ?: run {
            Log.e(TAG, "no H.264 decoder available at all")
            return VErr.ERR_UNSUPPORTED
        }
        val codec = try {
            MediaCodec.createByCodecName(name)
        } catch (e: Exception) {
            Log.e(TAG, "MediaCodec.createByCodecName($name) failed", e)
            return VErr.ERR_BACKEND
        }
        try {
            codec.configure(format, surface, null, 0)
            codec.start()
            decoder = codec
            decoderSurface = surface
            hardwareDecode = hw
            decodeBackendId = VAbi.BACKEND_ANDROID_MEDIACODEC
            return VErr.OK
        } catch (e: Exception) {
            Log.e(TAG, "decoder configure/start failed for $name", e)
            runCatching { codec.release() }
            return VErr.ERR_BACKEND
        }
    }

    private fun acquireDecodeSurfaceLocked(): Surface? {
        val provider = textureProvider
        if (provider != null) {
            val entry = runCatching { provider.createSurfaceTexture() }.getOrNull() ?: return null
            textureEntry = entry
            return Surface(entry.surfaceTexture())
        }
        // No Flutter engine (the on-device conformance harness, which hosts
        // this class in a plain android.app.Activity — see
        // native/cleona_video/android/conformance/). A self-managed EGL
        // context keeps the decoder's producer side drained so it never
        // stalls waiting on a consumer nobody provided.
        val h = HeadlessTexture.create() ?: return null
        headlessTexture = h
        return Surface(h.surfaceTexture)
    }

    private fun rebuildCaptureSessionBlocking(cfg: VConfig): Int {
        val device = cameraDevice ?: return VErr.ERR_BACKEND
        val surface = encoderInputSurface ?: return VErr.ERR_BACKEND
        val latch = CountDownLatch(1)
        var ok = false
        try {
            @Suppress("DEPRECATION")
            device.createCaptureSession(listOf(surface), object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    captureSession = session
                    ok = runCatching {
                        session.setRepeatingRequest(buildCaptureRequest(), null, cameraHandler)
                    }.isSuccess
                    latch.countDown()
                }
                override fun onConfigureFailed(session: CameraCaptureSession) {
                    Log.e(TAG, "createCaptureSession.onConfigureFailed")
                    latch.countDown()
                }
            }, cameraHandler)
        } catch (e: Exception) {
            Log.e(TAG, "createCaptureSession threw", e)
            return VErr.ERR_BACKEND
        }
        if (!latch.await(CAMERA_OPEN_TIMEOUT_MS, TimeUnit.MILLISECONDS) || !ok) {
            Log.e(TAG, "capture session did not configure within ${CAMERA_OPEN_TIMEOUT_MS}ms")
            return VErr.ERR_BACKEND
        }
        return VErr.OK
    }

    private fun buildCaptureRequest(): CaptureRequest {
        val device = cameraDevice!!
        val builder = device.createCaptureRequest(CameraDevice.TEMPLATE_RECORD)
        builder.addTarget(encoderInputSurface!!)
        builder.set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO)
        val chars = runCatching { cameraManager?.getCameraCharacteristics(cameraId) }.getOrNull()
        val ranges = chars?.get(
            android.hardware.camera2.CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES
        )?.toList().orEmpty()
        pickFpsRangeFor(ranges, negotiated.fps)?.let {
            builder.set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, it)
        }
        return builder.build()
    }

    private fun teardownPipelineLocked() {
        runCatching { captureSession?.stopRepeating() }
        runCatching { captureSession?.close() }
        captureSession = null
        runCatching { cameraDevice?.close() }
        cameraDevice = null
        releaseEncoderLocked()
        releaseDecoderLocked()
    }

    private fun teardownCameraOnlyLocked() {
        runCatching { captureSession?.stopRepeating() }
        runCatching { captureSession?.close() }
        captureSession = null
        runCatching { cameraDevice?.close() }
        cameraDevice = null
    }

    private fun releaseEncoderLocked() {
        runCatching { encoder?.stop() }
        runCatching { encoder?.release() }
        encoder = null
        runCatching { encoderInputSurface?.release() }
        encoderInputSurface = null
    }

    /** Releases the decoder AND the texture/surface [acquireDecodeSurfaceLocked]
     *  created for it. The two are 1:1 with the decoder's lifetime: a geometry
     *  change in [reconfigure] tears the whole pipeline down and calls
     *  [configureDecoder] again, which acquires a brand-new texture. Without
     *  releasing the old one here first, every geometry-changing reconfigure
     *  would leak a Flutter texture (or, in the conformance harness, a GL
     *  context and its thread). */
    private fun releaseDecoderLocked() {
        runCatching { decoder?.stop() }
        runCatching { decoder?.release() }
        decoder = null
        runCatching { decoderSurface?.release() }
        decoderSurface = null
        runCatching { textureEntry?.release() }
        textureEntry = null
        runCatching { headlessTexture?.release() }
        headlessTexture = null
    }

    // ═════════════════════════════════════════════════════════════════════
    // Threads
    // ═════════════════════════════════════════════════════════════════════

    /** Drains the encoder's output side: assembles SPS/PPS + IDR into one
     *  keyframe, enforces the I9 ceiling, and pushes into [outputRing]. */
    private fun encodeLoop(gen: Int) {
        val codec = encoder ?: return
        val info = MediaCodec.BufferInfo()
        while (generation == gen && state == ST_RUNNING) {
            if (pendingSyncFrameRequest) {
                pendingSyncFrameRequest = false
                runCatching {
                    codec.setParameters(Bundle().apply {
                        putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0)
                    })
                }
            }
            val idx = try {
                codec.dequeueOutputBuffer(info, ENCODER_DEQUEUE_TIMEOUT_US)
            } catch (e: MediaCodec.CodecException) {
                Log.e(TAG, "encoder dequeueOutputBuffer threw", e)
                break
            }
            if (idx == MediaCodec.INFO_TRY_AGAIN_LATER || idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                continue
            }
            if (idx < 0) continue
            val buf = codec.getOutputBuffer(idx)
            if (buf == null) {
                codec.releaseOutputBuffer(idx, false)
                continue
            }
            val bytes = ByteArray(info.size)
            buf.position(info.offset)
            buf.limit(info.offset + info.size)
            buf.get(bytes)
            codec.releaseOutputBuffer(idx, false)

            if ((info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) {
                pendingConfigBytes = bytes
                continue
            }

            if (!captureEnabled) {
                // A straggler from the camera pipeline's inherent latency:
                // stopRepeating() (setCaptureEnabled(false)) stops NEW
                // capture requests, but a frame already in flight through the
                // camera HAL / encoder input surface can still surface here
                // shortly afterward -- observed on device: exactly one frame
                // arrived after mute before this fix. I12 requires "own
                // video off" to behave as an immediate mute from the
                // caller's observable perspective (frames_captured must not
                // advance, read_encoded must not deliver), so the straggler
                // is discarded in software rather than counted or handed
                // out. The hardware's pipeline latency is not the caller's
                // problem.
                continue
            }

            framesCaptured.incrementAndGet()
            framesEncoded.incrementAndGet()

            // The ONLY source of truth for "is this a keyframe": the
            // encoder's own flag. pendingSyncFrameRequest is a REQUEST
            // consumed at the top of this loop (line above), never a label —
            // labelling a frame as a keyframe without the encoder having
            // actually produced an IDR would send a peer a bitstream its
            // flags lie about, exactly what cleona_video_submit_encoded's own
            // doc calls out as "feeding a decoder a lie".
            val isKey = (info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME) != 0
            var payload = bytes
            if (isKey) {
                val cfgBytes = pendingConfigBytes
                if (cfgBytes != null) {
                    payload = cfgBytes + bytes
                    pendingConfigBytes = null
                }
                framesSinceKeyframe = 0
            } else {
                framesSinceKeyframe++
                // Standard GOP-boundary semantics: a keyframe every
                // keyframeIntervalFrames frames means indices 0, kfi, 2*kfi, ...
                // -- so the request must be issued one frame BEFORE the
                // boundary is reached, for the boundary frame itself to be
                // the keyframe. OBSERVED ON DEVICE: triggering at
                // framesSinceKeyframe >= kfi (one frame later than this)
                // pushed the periodic keyframe past the conformance
                // harness's KFI_SHORT-sized read window (kfi=30, window=31
                // reads) into the very next phase's first read, which that
                // phase (a rate-only reconfigure, V11) asserts must NOT
                // produce a keyframe. The off-by-one was a real scheduling
                // bug, not a test artefact: a real periodic encoder places
                // its I-frames ON the GOP boundary, not one frame past it.
                if (negotiated.keyframeIntervalFrames > 0 &&
                    framesSinceKeyframe >= negotiated.keyframeIntervalFrames - 1) {
                    // Due for the NEXT produced frame -- request it now so
                    // that frame carries it (matches the request_keyframe()
                    // mechanism, one code path for both).
                    pendingSyncFrameRequest = true
                }
            }

            val rawPts = info.presentationTimeUs
            if (ptsOriginUs < 0) {
                // Anchor the new encoder generation's raw clock so the first
                // frame continues from lastPtsUs, not from zero (see
                // launchDataThreadsLocked's doc). lastPtsUs is -1 only before
                // the very first frame of the session, giving origin=rawPts
                // and pts=0 for that frame, matching "starts near zero at
                // first start()".
                ptsOriginUs = rawPts - (lastPtsUs + 1)
            }
            var pts = rawPts - ptsOriginUs
            if (pts <= lastPtsUs) pts = lastPtsUs + 1 // defensive monotonic clamp
            lastPtsUs = pts

            val ceiling = negotiated.maxFrameBytes
            if (payload.size > ceiling) {
                // I9 backstop. Documented as a defect counter in the field;
                // here it can legitimately fire once right after a
                // ceiling-lowering reconfigure raced this thread, which is
                // the one benign case cleona_video.h names.
                framesDroppedOversize.incrementAndGet()
                continue
            }
            outputRing.offer(EncodedFrame(payload, if (isKey) VAbi.FLAG_KEYFRAME else 0, pts))
        }
    }

    /** Drains [inputQueue] into the decoder's input side. */
    private fun decodeInLoop(gen: Int) {
        val codec = decoder ?: return
        while (generation == gen && state == ST_RUNNING) {
            val item = inputQueue.take(200) ?: continue
            var idx = -1
            var tries = 0
            while (idx < 0 && tries < 25 && generation == gen && state == ST_RUNNING) {
                idx = try {
                    codec.dequeueInputBuffer(DECODER_DEQUEUE_TIMEOUT_US)
                } catch (e: MediaCodec.CodecException) {
                    Log.e(TAG, "decoder dequeueInputBuffer threw", e)
                    -1
                }
                tries++
            }
            if (idx < 0) {
                decodeFailures.incrementAndGet()
                continue
            }
            try {
                val ib = codec.getInputBuffer(idx)
                ib?.clear()
                ib?.put(item.data)
                codec.queueInputBuffer(idx, 0, item.data.size, 0, item.flags)
            } catch (e: Exception) {
                Log.e(TAG, "queueInputBuffer failed", e)
                decodeFailures.incrementAndGet()
            }
        }
    }

    /** Drains the decoder's output side, rendering into [decoderSurface]. No
     *  pixels come back to Kotlin (I10) — `releaseOutputBuffer(idx, true)`
     *  hands the frame straight to the Surface's buffer queue. */
    private fun decodeOutLoop(gen: Int) {
        val codec = decoder ?: return
        val info = MediaCodec.BufferInfo()
        while (generation == gen && state == ST_RUNNING) {
            val idx = try {
                codec.dequeueOutputBuffer(info, DECODER_DEQUEUE_TIMEOUT_US)
            } catch (e: MediaCodec.CodecException) {
                Log.e(TAG, "decoder dequeueOutputBuffer threw", e)
                break
            }
            when {
                idx == MediaCodec.INFO_TRY_AGAIN_LATER -> continue
                idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> continue
                idx >= 0 -> {
                    codec.releaseOutputBuffer(idx, true)
                    framesDecoded.incrementAndGet()
                }
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    companion object {
        private const val TAG = "CleonaVideo"

        private const val ST_OPEN = 0
        private const val ST_RUNNING = 1
        private const val ST_CLOSED = 2

        private const val OUTPUT_RING_CAPACITY = 6
        private const val INPUT_QUEUE_CAPACITY = 6
        private const val THREAD_JOIN_MS = 1500L
        private const val CAMERA_OPEN_TIMEOUT_MS = 4000L
        private const val ENCODER_DEQUEUE_TIMEOUT_US = 20_000L
        private const val DECODER_DEQUEUE_TIMEOUT_US = 20_000L

        private const val NAL_TYPE_IDR = 5
        private const val NAL_TYPE_SPS = 7

        // ─────────────────────────────────────────────────────────────────
        // Preset ladder tuning — engineering judgement, not a spec-mandated
        // number (unlike max_frame_bytes itself, which V1.11 owns and this
        // package only consumes). Deliberately conservative: a worse-quality
        // preset that reliably stays under the ceiling is safer than a
        // tighter one that occasionally trips the I9 backstop, because the
        // conformance harness (and real calls) read a bounded number of
        // frames per phase and a run of backstop drops reads as a stall.
        // ─────────────────────────────────────────────────────────────────
        private val BITRATE_STEPS = doubleArrayOf(1.0, 0.65, 0.45, 0.3, 0.2, 0.13, 0.08)
        private const val MIN_BITRATE_KBPS = 48
        // Empirical multiplier from average bits-per-frame to a worst-case
        // I-frame size for a Baseline H.264 encoder at moderate motion. Real
        // encoders vary; this is deliberately generous (see CEILING_SAFETY_MARGIN
        // below for the second line of defence).
        private const val KEYFRAME_FACTOR = 7.0
        private const val KEYFRAME_OVERHEAD_BYTES = 200
        // Only half the requested ceiling is budgeted against the estimate,
        // leaving headroom for encoders whose actual keyframe exceeds this
        // heuristic and for P-frames occasionally running above their
        // nominal size under motion.
        private const val CEILING_SAFETY_MARGIN = 0.5

        private fun estimateWorstCaseKeyframeBytes(bitrateKbps: Int, fps: Int): Int {
            val bytesPerFrame = (bitrateKbps.toLong() * 1000 / 8 / max(fps, 1))
            return (bytesPerFrame * KEYFRAME_FACTOR).toInt() + KEYFRAME_OVERHEAD_BYTES
        }

        /** PHASE 1 (see the class doc's "one trap" section): the single
         *  negotiation entry point used by both [openSession] and
         *  [reconfigure], touching no camera and no codec — only static
         *  `CameraCharacteristics` and arithmetic. Mirrors the mock's single
         *  `negotiate()` so open() and a later reconfigure() can never
         *  disagree about what this backend supports. Returns null when
         *  nothing achievable fits `req.maxFrameBytes` — the ONLY condition
         *  under which this backend returns ERR_RATE_UNACHIEVABLE anywhere. */
        private fun choosePreset(chars: CameraCharacteristics, req: VConfig): Preset? {
            val map = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                ?: return null
            val sizes = runCatching { map.getOutputSizes(android.media.MediaCodec::class.java) }
                .getOrNull()?.toList().orEmpty()
            if (sizes.isEmpty()) return null

            val fpsRanges = chars.get(
                CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES
            )?.toList().orEmpty()
            val fps = pickFps(fpsRanges, req.fps)

            // Resolution ladder: every camera-reported size that is <= requested
            // on both axes (never negotiate up), largest area first.
            val resSteps = sizes.filter { it.width <= req.width && it.height <= req.height }
                .distinct()
                .sortedByDescending { it.width.toLong() * it.height }
                .ifEmpty {
                    // The camera's smallest MediaCodec-class size still exceeds
                    // the request on one axis (unusual, but not a link
                    // condition) -- fall back to the globally smallest size the
                    // camera offers; still capped downward relative to itself.
                    listOf(sizes.minByOrNull { it.width.toLong() * it.height } ?: return null)
                }

            val reqArea = (req.width.toLong() * req.height).coerceAtLeast(1)

            for (size in resSteps) {
                val areaRatio = (size.width.toLong() * size.height).toDouble() / reqArea
                for (mult in BITRATE_STEPS) {
                    val bitrateKbps = max(
                        MIN_BITRATE_KBPS,
                        (req.targetBitrateKbps * areaRatio * mult).toInt()
                    )
                    val estimate = estimateWorstCaseKeyframeBytes(bitrateKbps, fps)
                    if (estimate <= req.maxFrameBytes * CEILING_SAFETY_MARGIN) {
                        return Preset(size.width, size.height, fps, bitrateKbps)
                    }
                }
            }
            return null
        }

        /**
         * Erratum 7 — the camera-free counterpart of [choosePreset].
         *
         * A decode-only session has no sensor that could cap the geometry, so
         * the requested width/height/fps stand as-is; they remain meaningful
         * because the decoder and the texture are sized from them. What does
         * NOT change is the rate arithmetic: the erratum keeps the encode-side
         * fields' validity rules intact precisely so open() and reconfigure()
         * cannot disagree about the same configuration (Erratum 6b case 1).
         * The bitrate ladder is therefore walked exactly as in [choosePreset],
         * just with an area ratio of 1.0 — `null` still means
         * ERR_RATE_UNACHIEVABLE. This mirrors the Linux backend, which runs its
         * one negotiate() against `cfg->width/height/fps` when decode-only.
         */
        private fun chooseDecodeOnlyPreset(req: VConfig): Preset? {
            for (mult in BITRATE_STEPS) {
                val bitrateKbps = max(MIN_BITRATE_KBPS, (req.targetBitrateKbps * mult).toInt())
                val estimate = estimateWorstCaseKeyframeBytes(bitrateKbps, req.fps)
                if (estimate <= req.maxFrameBytes * CEILING_SAFETY_MARGIN) {
                    return Preset(req.width, req.height, req.fps, bitrateKbps)
                }
            }
            return null
        }

        // ─── install / library loading ──────────────────────────────────

        @Volatile private var appContext: Context? = null
        @Volatile private var textureProvider: VideoTextureProvider? = null
        @Volatile private var libraryLoaded = false

        /**
         * Loads `libcleona_video.so` **through the Java runtime** and hands the
         * backend an application context plus a texture provider.
         *
         * [registry] is nullable so this class also runs, texture-less-Flutter,
         * inside the on-device conformance harness (a plain `android.app.Activity`
         * with no Flutter engine) — see [acquireDecodeSurfaceLocked]'s headless
         * fallback. `MainActivity.kt` (V1.10) is expected to pass a real one —
         * see BUILD_REQUEST_V1.14.md §2 for the exact adapter.
         */
        @JvmStatic
        fun install(context: Context, registry: VideoTextureProvider?) {
            appContext = context.applicationContext
            textureProvider = registry
            ensureLibraryLoaded()
        }

        @JvmStatic
        @Synchronized
        fun ensureLibraryLoaded(): Boolean {
            if (libraryLoaded) return true
            try {
                System.loadLibrary("cleona_video")
                libraryLoaded = true
            } catch (e: UnsatisfiedLinkError) {
                Log.e(TAG, "libcleona_video.so not in this build -- video calls " +
                    "will fail with ERR_BACKEND (BUILD_REQUEST_V1.14.md §1)", e)
            }
            return libraryLoaded
        }

        /** Mirrors `cleona_video_android.c`'s `check_abi_constants` list, in the
         *  same order. Two copies of a constant in two languages drift, and the
         *  drift would be invisible without this check (same rationale as
         *  VoiceSession.kt's `abiConstants()`). */
        @JvmStatic
        fun abiConstants(): IntArray = intArrayOf(
            VErr.OK, VErr.ERR_INVALID, VErr.ERR_STATE, VErr.ERR_UNSUPPORTED, VErr.ERR_BACKEND,
            VErr.ERR_BUFFER_TOO_SMALL, VErr.ERR_DECODE, VErr.ERR_RATE_UNACHIEVABLE,
            VErr.READ_FRAME, VErr.READ_TIMEOUT,
            VErr.SUBMIT_ACCEPTED, VErr.SUBMIT_AWAITING_KEYFRAME,
            VAbi.FLAG_KEYFRAME,
            VAbi.CODEC_H264, VAbi.CODEC_HEVC, VAbi.CODEC_AV1, VAbi.CODEC_VP9,
            VAbi.HW_NO, VAbi.HW_YES, VAbi.HW_NOT_DETERMINABLE,
            VAbi.BACKEND_ANDROID_CAMERAX, VAbi.BACKEND_ANDROID_MEDIACODEC,
        )

        /**
         * `cleona_video_open`.
         *
         * @param cfgInts 7 ints: codec, width, height, fps, targetBitrateKbps,
         *        maxFrameBytes, keyframeIntervalFrames (cleona_video_config_t's
         *        declaration order).
         * @param out same 7 slots. On success: the negotiated configuration. On
         *        failure: every slot zero except index 5 (max_frame_bytes),
         *        which carries the negative `CLEONA_VIDEO_ERR_*` — Erratum 6b's
         *        in-band error channel, produced here so the JNI facade only
         *        has to pass it through.
         */
        @JvmStatic
        fun openSession(cfgInts: IntArray, out: IntArray): VideoSession? {
            fun fail(code: Int): VideoSession? {
                out.fill(0)
                out[VConfig.MFB_INDEX] = code
                return null
            }

            val req = VConfig.fromInts(cfgInts) ?: return fail(VErr.ERR_INVALID)
            if (!req.isValid()) return fail(VErr.ERR_INVALID)

            // Erratum 7: a decode-only session acquires no camera, so none of
            // the camera work below applies to it -- and none of it may be
            // allowed to fail it either. A device with no camera at all is
            // exactly the case the erratum exists for: the participant could
            // otherwise not SEE the others merely because it cannot BE seen.
            // The decoder and its texture are built later, in start() ->
            // openCameraAndPipeline(), which for this direction reduces to
            // configureDecoder() alone.
            if (req.direction == VAbi.DIR_DECODE_ONLY) {
                val preset = chooseDecodeOnlyPreset(req)
                if (preset == null) {
                    Log.i(TAG, "no achievable rate fits maxFrameBytes=${req.maxFrameBytes} " +
                        "at ${req.fps} fps (decode-only) -- ERR_RATE_UNACHIEVABLE")
                    return fail(VErr.ERR_RATE_UNACHIEVABLE)
                }
                val negotiated = VConfig(
                    codec = VAbi.CODEC_H264,
                    width = preset.width, height = preset.height, fps = preset.fps,
                    targetBitrateKbps = preset.bitrateKbps,
                    maxFrameBytes = req.maxFrameBytes,
                    keyframeIntervalFrames =
                        if (req.keyframeIntervalFrames > 0) req.keyframeIntervalFrames
                        else preset.fps * 2,
                    direction = req.direction,   // echoed, never renegotiated (Erratum 7)
                )
                writeCfgInto(out, negotiated)
                // No CameraManager, no camera id, no camera HandlerThread --
                // see the constructor's Erratum 7 note.
                return VideoSession(null, "", null, null, negotiated)
            }

            val ctx = appContext ?: run {
                Log.e(TAG, "VideoSession.install(context, registry) was never called")
                return fail(VErr.ERR_BACKEND)
            }
            val manager = try {
                ctx.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            } catch (e: Exception) {
                Log.e(TAG, "no CameraManager", e)
                return fail(VErr.ERR_BACKEND)
            }
            val ids = listCameraIds(manager)
            if (ids.isEmpty()) {
                // A genuine property of the device -- no camera hardware at
                // all. Not retryable on a better link (ERR_UNSUPPORTED), and
                // structurally never confusable with ERR_RATE_UNACHIEVABLE:
                // this branch runs before choosePreset() is even reachable.
                Log.e(TAG, "no cameras on this device")
                return fail(VErr.ERR_UNSUPPORTED)
            }
            val cameraId = ids[0]

            // ── PHASE 1: link feasibility, no hardware touched ───────────
            // getCameraCharacteristics() reads a static, already-cached
            // property table from the camera service; it does not acquire
            // the camera and cannot fail with "camera busy" -- see the class
            // doc's "one trap" section.
            val chars = try {
                manager.getCameraCharacteristics(cameraId)
            } catch (e: CameraAccessException) {
                Log.e(TAG, "getCameraCharacteristics failed", e)
                return fail(VErr.ERR_BACKEND)
            }
            val preset = choosePreset(chars, req)
            if (preset == null) {
                Log.i(TAG, "no achievable preset fits maxFrameBytes=${req.maxFrameBytes} " +
                    "for ${req.width}x${req.height}@${req.fps} (link too slow) -- " +
                    "ERR_RATE_UNACHIEVABLE, no camera was opened")
                return fail(VErr.ERR_RATE_UNACHIEVABLE)
            }

            val negotiated = VConfig(
                codec = VAbi.CODEC_H264,
                width = preset.width, height = preset.height, fps = preset.fps,
                targetBitrateKbps = preset.bitrateKbps,
                maxFrameBytes = req.maxFrameBytes,
                keyframeIntervalFrames = if (req.keyframeIntervalFrames > 0) req.keyframeIntervalFrames else preset.fps * 2,
                direction = req.direction,   // echoed, never renegotiated (Erratum 7)
            )

            // ── PHASE 2 begins only now: the first hardware object this
            // whole call chain acquires is the camera thread, and it is
            // acquired only after phase 1 has already committed to a preset.
            val cameraThread = HandlerThread("cleona-video-camera").apply { start() }
            val cameraHandler = Handler(cameraThread.looper)
            // On success `out` carries the negotiated configuration (never
            // left zeroed) -- the caller sizes its read buffer from
            // out.maxFrameBytes and a zeroed struct here would silently
            // produce a zero-capacity buffer on every subsequent read.
            writeCfgInto(out, negotiated)
            return VideoSession(manager, cameraId, cameraThread, cameraHandler, negotiated)
        }

        private fun listCameraIds(manager: CameraManager): List<String> {
            val ids = runCatching { manager.cameraIdList.toList() }.getOrDefault(emptyList())
            fun facing(id: String): Int? = runCatching {
                manager.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING)
            }.getOrNull()
            val back = ids.filter { facing(it) == CameraCharacteristics.LENS_FACING_BACK }
            val front = ids.filter { facing(it) == CameraCharacteristics.LENS_FACING_FRONT }
            val other = ids.filterNot { it in back || it in front }
            return back + front + other
        }

        private fun findCodecFor(format: MediaFormat, encoder: Boolean): Pair<String, Int>? {
            val list = MediaCodecList(MediaCodecList.REGULAR_CODECS)
            val name = if (encoder) {
                runCatching { list.findEncoderForFormat(format) }.getOrNull()
            } else {
                runCatching { list.findDecoderForFormat(format) }.getOrNull()
            } ?: return null
            val info = list.codecInfos.firstOrNull { it.name == name } ?: return null
            // I11: never report HW_YES without verification. isHardwareAccelerated()
            // is API 29+; below that this backend honestly reports
            // NOT_DETERMINABLE rather than guessing from the codec name (a
            // "c2.android."/"OMX.google." prefix heuristic is not verification).
            val hw = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                if (info.isHardwareAccelerated) VAbi.HW_YES else VAbi.HW_NO
            } else {
                VAbi.HW_NOT_DETERMINABLE
            }
            return name to hw
        }

        private fun pickFps(ranges: List<Range<Int>>, requested: Int): Int {
            if (ranges.isEmpty()) return requested
            val atOrBelow = ranges.filter { it.upper <= requested }
            val best = atOrBelow.maxByOrNull { it.upper } ?: ranges.minByOrNull { it.upper }
            return min(requested, best?.upper ?: requested).coerceAtLeast(1)
        }

        private fun pickFpsRangeFor(ranges: List<Range<Int>>, fps: Int): Range<Int>? {
            if (ranges.isEmpty()) return null
            ranges.firstOrNull { fps in it.lower..it.upper }?.let { return Range(fps, fps).let { r ->
                if (fps in it.lower..it.upper) r else it
            } }
            return ranges.minByOrNull { abs(it.upper - fps) }
        }

        /** First NAL unit type after the last Annex-B start code, or -1 when
         *  none is found — the same detection strategy the mock and the
         *  saboteur use, so a malformed-bitstream negative control behaves
         *  identically in spirit across backends. */
        private fun annexBFirstNalType(data: ByteArray): Int {
            var sc = -1
            var i = 0
            while (i + 4 <= data.size) {
                if (data[i] == 0.toByte() && data[i + 1] == 0.toByte() &&
                    data[i + 2] == 0.toByte() && data[i + 3] == 1.toByte()) {
                    sc = i
                }
                i++
            }
            if (sc < 0 || sc + 4 >= data.size) return -1
            return data[sc + 4].toInt() and 0x1F
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════
// Return codes mirrored from native/cleona_video/cleona_video.h. Checked
// against the header at JNI_OnLoad via VideoSession.Companion.abiConstants();
// the facade refuses to bind if they drift apart.
//
// NOT named `Abi`: VoiceSession.kt declares a top-level `internal object Abi`
// in this same package with DIFFERENT values for the same names (its
// ERR_UNSUPPORTED is -11, this one's is -3). Two of them is a Kotlin
// redeclaration error, and the version that compiled would have been chosen
// by accident.
// ═════════════════════════════════════════════════════════════════════════
internal object VErr {
    const val OK = 0
    const val ERR_INVALID = -1
    const val ERR_STATE = -2
    const val ERR_UNSUPPORTED = -3
    const val ERR_BACKEND = -4
    const val ERR_BUFFER_TOO_SMALL = -5
    const val ERR_DECODE = -6
    const val ERR_RATE_UNACHIEVABLE = -7

    const val READ_FRAME = 1
    const val READ_TIMEOUT = 0

    const val SUBMIT_ACCEPTED = 0
    const val SUBMIT_AWAITING_KEYFRAME = 1
}

internal object VAbi {
    const val CODEC_H264 = 1
    const val CODEC_HEVC = 2
    const val CODEC_AV1 = 3
    const val CODEC_VP9 = 4

    const val FLAG_KEYFRAME = 0x01

    const val HW_NO = 0
    const val HW_YES = 1
    const val HW_NOT_DETERMINABLE = -1

    const val BACKEND_NONE = 0
    const val BACKEND_MOCK = 1
    const val BACKEND_ANDROID_CAMERAX = 2
    const val BACKEND_ANDROID_MEDIACODEC = 3

    /** Session direction — Erratum 7. */
    const val DIR_DUPLEX = 0
    const val DIR_DECODE_ONLY = 1
}

/**
 * Minimal seam onto Flutter's texture registry.
 *
 * Defined here rather than importing `io.flutter.view.TextureRegistry`
 * directly so this file — and the on-device conformance harness that
 * compiles it standalone with no Flutter classpath at all (see
 * `native/cleona_video/android/conformance/run_conformance.sh`) — do not
 * require the Flutter embedding jar to build. `MainActivity.kt` (V1.10) is
 * expected to satisfy this with a thin adapter around
 * `io.flutter.view.TextureRegistry.SurfaceTextureEntry` — see
 * BUILD_REQUEST_V1.14.md §2 for the exact adapter code.
 */
interface VideoTextureProvider {
    fun createSurfaceTexture(): VideoTextureEntry
}

interface VideoTextureEntry {
    fun id(): Long
    fun surfaceTexture(): SurfaceTexture
    fun release()
}

// ═════════════════════════════════════════════════════════════════════════
// Value types
// ═════════════════════════════════════════════════════════════════════════

/** One encoded frame waiting to be read. */
private data class EncodedFrame(val data: ByteArray, val flags: Int, val ptsUs: Long)

/** `cleona_video_config_t`'s Kotlin mirror. Field order matches the struct
 *  (and the 7-int marshalling array `cleona_video_android.c` uses)
 *  exactly. */
private data class VConfig(
    val codec: Int,
    val width: Int,
    val height: Int,
    val fps: Int,
    val targetBitrateKbps: Int,
    val maxFrameBytes: Int,
    val keyframeIntervalFrames: Int,
    /** CLEONA_VIDEO_DIR_* — Erratum 7. 0 = duplex, the pre-erratum meaning. */
    val direction: Int,
) {
    fun isValid(): Boolean =
        width > 0 && height > 0 && fps > 0 && targetBitrateKbps > 0 &&
            maxFrameBytes > 0 && keyframeIntervalFrames >= 0 &&
            // Erratum 7: an unknown direction is a caller bug, decided with
            // the other field checks so it can never surface as
            // ERR_RATE_UNACHIEVABLE.
            (direction == VAbi.DIR_DUPLEX || direction == VAbi.DIR_DECODE_ONLY) &&
            // codec <= 0 means "no preference" (treated as H264 downstream);
            // an unknown POSITIVE value is a caller bug that must fail closed
            // (cleona_video.h: "An unknown positive value makes
            // cleona_video_open fail closed").
            (codec <= 0 || codec in VAbi.CODEC_H264..VAbi.CODEC_VP9)

    companion object {
        const val MFB_INDEX = 5

        fun fromInts(a: IntArray): VConfig? {
            if (a.size != 8) return null
            return VConfig(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7])
        }
    }
}

private fun writeCfgInto(out: IntArray, c: VConfig) {
    out[0] = c.codec; out[1] = c.width; out[2] = c.height; out[3] = c.fps
    out[4] = c.targetBitrateKbps; out[5] = c.maxFrameBytes; out[6] = c.keyframeIntervalFrames
    out[7] = c.direction
}

/** One achievable encoder step from the preset ladder (Phase 1). */
private data class Preset(val width: Int, val height: Int, val fps: Int, val bitrateKbps: Int)

// ═════════════════════════════════════════════════════════════════════════
// Bounded, drop-oldest frame ring for the encoder->readEncoded() hand-off.
// Mirrors VoiceSession.kt's FrameRing in shape (recycling would not help
// here since frames are variable-length byte arrays, so this ring holds
// EncodedFrame objects directly rather than recycled fixed-size slots).
// ═════════════════════════════════════════════════════════════════════════
private class VideoFrameRing(private val capacity: Int) {
    private val lock = ReentrantLock()
    private val notEmpty = lock.newCondition()
    private val queue = ArrayDeque<EncodedFrame>(capacity)

    /** Set by [wakeAll] (called from `stop()`) and cleared by [reset] (called
     *  at the start of every run). Needed because a negative `timeoutMs`
     *  (cleona_video.h: "blocks until a frame arrives or the session stops")
     *  has no deadline of its own to expire — without this flag a waiter
     *  woken by [wakeAll] with an still-empty queue would simply re-enter
     *  `await()` and block forever. */
    @Volatile private var closed = false

    fun offer(frame: EncodedFrame) = lock.withLock {
        while (queue.size >= capacity) queue.removeFirst()
        queue.addLast(frame)
        notEmpty.signal()
    }

    /** @param timeoutMs 0 polls, negative blocks until a frame arrives or the
     *  session stops (matches `cleona_video_read_encoded`'s contract). */
    fun take(timeoutMs: Long): EncodedFrame? {
        lock.lock()
        try {
            if (timeoutMs < 0) {
                while (queue.isEmpty() && !closed) {
                    notEmpty.await()
                }
                return queue.removeFirstOrNull()
            }
            var remaining = timeoutMs * 1_000_000L
            while (queue.isEmpty()) {
                if (closed || remaining <= 0L) return null
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

    fun peekNewest(): EncodedFrame? = lock.withLock { queue.lastOrNull() }
    fun dropNewest() = lock.withLock { if (queue.isNotEmpty()) queue.removeLast() }
    fun wakeAll() = lock.withLock { closed = true; notEmpty.signalAll() }
    fun reset() = lock.withLock { queue.clear(); closed = false }
}

/** Bounded queue feeding the decoder input side. Same block-with-deadline
 *  shape as [VideoFrameRing]; see its doc for the `closed` flag's purpose. */
private class InputQueue(private val capacity: Int) {
    data class Item(val data: ByteArray, val flags: Int)

    private val lock = ReentrantLock()
    private val notEmpty = lock.newCondition()
    private val queue = ArrayDeque<Item>(capacity)
    @Volatile private var closed = false

    fun offer(data: ByteArray, flags: Int): Boolean = lock.withLock {
        if (queue.size >= capacity) return false
        queue.addLast(Item(data, flags))
        notEmpty.signal()
        true
    }

    fun take(timeoutMs: Long): Item? {
        lock.lock()
        try {
            var remaining = timeoutMs * 1_000_000L
            while (queue.isEmpty()) {
                if (closed || remaining <= 0L) return null
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

    fun wakeAll() = lock.withLock { closed = true; notEmpty.signalAll() }
    fun reset() = lock.withLock { queue.clear(); closed = false }
}

// ═════════════════════════════════════════════════════════════════════════
// Headless decode surface for the on-device conformance harness, which hosts
// VideoSession in a plain android.app.Activity with no Flutter engine and
// therefore no TextureRegistry (see VideoTextureProvider's doc). Without a
// consumer draining the decoder's output Surface, MediaCodec's producer side
// eventually blocks waiting for a free buffer -- this class is that consumer:
// a minimal off-screen EGL context that attaches the SurfaceTexture and
// drains it on every "frame available" callback.
// ═════════════════════════════════════════════════════════════════════════
private class HeadlessTexture private constructor(
    private val thread: HandlerThread,
    val surfaceTexture: SurfaceTexture,
    private val display: EGLDisplay,
    private val context: EGLContext,
    private val eglSurface: EGLSurface,
) {
    val id: Long = System.identityHashCode(surfaceTexture).toLong() and 0xFFFFFFFFL

    fun release() {
        runCatching {
            EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
            EGL14.eglDestroySurface(display, eglSurface)
            EGL14.eglDestroyContext(display, context)
        }
        runCatching { surfaceTexture.release() }
        runCatching { thread.quitSafely() }
    }

    companion object {
        private const val TAG = "CleonaVideoHeadlessTex"

        fun create(): HeadlessTexture? {
            val thread = HandlerThread("cleona-video-headless-gl").apply { start() }
            val handler = Handler(thread.looper)
            var result: HeadlessTexture? = null
            val latch = CountDownLatch(1)
            handler.post {
                result = runCatching { buildOnThread(thread) }
                    .onFailure { Log.e(TAG, "headless EGL/SurfaceTexture setup failed", it) }
                    .getOrNull()
                latch.countDown()
            }
            if (!latch.await(2000, TimeUnit.MILLISECONDS) || result == null) {
                thread.quitSafely()
                return null
            }
            return result
        }

        private fun buildOnThread(thread: HandlerThread): HeadlessTexture {
            val display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
            val version = IntArray(2)
            EGL14.eglInitialize(display, version, 0, version, 1)

            val attribs = intArrayOf(
                EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT,
                EGL14.EGL_RED_SIZE, 8, EGL14.EGL_GREEN_SIZE, 8, EGL14.EGL_BLUE_SIZE, 8,
                EGL14.EGL_NONE,
            )
            val configs = arrayOfNulls<EGLConfig>(1)
            val numConfigs = IntArray(1)
            EGL14.eglChooseConfig(display, attribs, 0, configs, 0, 1, numConfigs, 0)
            val config = configs[0] ?: error("eglChooseConfig returned no config")

            val ctxAttribs = intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE)
            val context = EGL14.eglCreateContext(display, config, EGL14.EGL_NO_CONTEXT, ctxAttribs, 0)

            val pbufferAttribs = intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE)
            val eglSurface = EGL14.eglCreatePbufferSurface(display, config, pbufferAttribs, 0)
            EGL14.eglMakeCurrent(display, eglSurface, eglSurface, context)

            val texIds = IntArray(1)
            GLES20.glGenTextures(1, texIds, 0)
            GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, texIds[0])

            val surfaceTexture = SurfaceTexture(texIds[0])
            val handler = Handler(thread.looper)
            surfaceTexture.setOnFrameAvailableListener({ st ->
                // Drain on the same GL thread that owns the context.
                runCatching { st.updateTexImage() }
            }, handler)

            return HeadlessTexture(thread, surfaceTexture, display, context, eglSurface)
        }
    }
}
