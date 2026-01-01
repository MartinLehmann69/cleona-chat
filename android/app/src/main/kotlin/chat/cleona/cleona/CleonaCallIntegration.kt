package chat.cleona.cleona

import android.annotation.SuppressLint
import android.content.ComponentName
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.DisconnectCause
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.telecom.VideoProfile
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap

/**
 * V3.2 — self-managed `ConnectionService` bridge (Android half).
 *
 * Architecture `Cleona_Chat_Architecture_v3_0.md` §10.4, "Session behaviour"
 * table, row "Call integration": *"CallKit (Apple) and a self-managed
 * ConnectionService (Android) — a later stage, deliberately after the two
 * layers above. Otherwise the call sounds right and behaves wrong."*
 * Staging table row 7 ("CallKit / ConnectionService | system integration").
 * Work package V3.2 in `docs/SPEC_VOICE_VIDEO_REWORK.md`.
 *
 * What this does: it tells the Android telephony stack that Cleona has a call
 * in progress, so the OS treats it like a call — a cellular call interrupts it
 * through the documented Telecom path instead of colliding with it, the system
 * knows a call is active while Cleona is in the background, and the hardware
 * hang-up / mute affordances (watch, headset button, car head unit) reach the
 * app.
 *
 * ── What this deliberately does NOT do (invariant I2, §10.4) ────────────────
 * Cleona does no audio DSP of its own and owns no audio route. The OS voice
 * session lives in `native/cleona_voice` (Android backend: [VoiceSession]);
 * audio focus and proximity live in [MainActivity] (work package V1.10). This
 * class therefore never calls `AudioManager`, never calls
 * `Connection.setAudioRoute`, never calls `Connection.setAudioModeIsVoip`, and
 * never requests audio focus. It only *observes*
 * [CleonaTelecomConnection.onCallAudioStateChanged] to keep the mute state in
 * sync with Dart.
 *
 * ── MethodChannel contract (identical on iOS/CallKit, by design) ────────────
 * Dart -> platform:
 *  - `reportIncomingCall`  {callId, displayName, hasVideo}
 *  - `reportOutgoingCall`  {callId, displayName, hasVideo}
 *  - `reportCallConnected` {callId}
 *  - `endCall`             {callId}
 *  - `setMuted`            {callId, muted}
 * Platform -> Dart:
 *  - `onAnswerCall` {callId}
 *  - `onEndCall`    {callId}
 *  - `onSetMuted`   {callId, muted}
 *
 * All Dart -> platform methods answer with a `Boolean`: `true` when Telecom
 * accepted the report, `false` when the platform cannot serve it (API < 26, no
 * `TelecomManager`, or an unknown `callId` — i.e. a call Telecom no longer
 * tracks). Hard failures (`SecurityException` from a missing
 * `MANAGE_OWN_CALLS`) come back as `result.error`.
 *
 * Everything top-level in this package is prefixed `Cleona…` on purpose:
 * [VoiceSession] and [VideoSession] live in the same package and already
 * collided once over generic top-level names (S296).
 */
object CleonaCallIntegration : MethodChannel.MethodCallHandler {

    const val CHANNEL_NAME = "chat.cleona/call_integration"

    private const val TAG = "CleonaCallInteg"

    /** Identifier of the self-managed [PhoneAccount] Cleona registers. */
    private const val PHONE_ACCOUNT_ID = "cleona_self_managed_v1"

    /**
     * Cleona's own call id, threaded through the Telecom round trip. Telecom
     * gives us no way to hand an object to the [CleonaConnectionService]; the
     * only channel is a [Bundle], so the id travels as a string extra and —
     * as a second, independent path — inside the SIP address user part (see
     * [addressFor] / [callIdFromRequest]).
     */
    private const val EXTRA_CALL_ID = "chat.cleona.telecom.CALL_ID"
    private const val EXTRA_DISPLAY_NAME = "chat.cleona.telecom.DISPLAY_NAME"
    private const val EXTRA_HAS_VIDEO = "chat.cleona.telecom.HAS_VIDEO"

    /** Host part of the synthetic SIP address. Never resolved, never dialled. */
    private const val ADDRESS_HOST = "cleona.chat"

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var appContext: Context? = null

    @Volatile
    private var channel: MethodChannel? = null

    @Volatile
    private var phoneAccountRegistered = false

    /** callId -> live Telecom connection. Written from the Telecom callbacks. */
    private val connections = ConcurrentHashMap<String, CleonaTelecomConnection>()

    /**
     * Self-managed Telecom needs API 26 —
     * [PhoneAccount.CAPABILITY_SELF_MANAGED] and
     * [Connection.PROPERTY_SELF_MANAGED] were both added in O. `minSdk` is 24
     * (Flutter default, `android/app/build.gradle.kts` uses
     * `flutter.minSdkVersion`), so 24/25 must degrade to a no-op rather than
     * crash: on those devices the call still works, it just has no system
     * integration.
     */
    private val isSupported: Boolean
        get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O

    // ── Registration (called once from MainActivity.configureFlutterEngine) ──

    fun register(context: Context, messenger: BinaryMessenger) {
        appContext = context.applicationContext
        val ch = MethodChannel(messenger, CHANNEL_NAME)
        ch.setMethodCallHandler(this)
        channel = ch
    }

    // ── Dart -> platform ────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "reportIncomingCall" -> result.success(
                    reportCall(call, incoming = true)
                )
                "reportOutgoingCall" -> result.success(
                    reportCall(call, incoming = false)
                )
                "reportCallConnected" -> {
                    val id = call.argument<String>("callId")
                    if (id == null) {
                        result.error("INVALID_ARGS", "callId required", null)
                        return
                    }
                    val conn = connections[id]
                    if (conn == null) {
                        Log.w(TAG, "reportCallConnected for unknown callId=$id")
                        result.success(false)
                        return
                    }
                    conn.setActive()
                    result.success(true)
                }
                "endCall" -> {
                    val id = call.argument<String>("callId")
                    if (id == null) {
                        result.error("INVALID_ARGS", "callId required", null)
                        return
                    }
                    val conn = connections.remove(id)
                    if (conn == null) {
                        // Not an error: Telecom may already have torn the
                        // connection down (remote hang-up, onAbort), in which
                        // case Dart's endCall is simply late.
                        result.success(false)
                        return
                    }
                    conn.finish(DisconnectCause.LOCAL)
                    result.success(true)
                }
                "setMuted" -> {
                    val id = call.argument<String>("callId")
                    val muted = call.argument<Boolean>("muted")
                    if (id == null || muted == null) {
                        result.error("INVALID_ARGS", "callId and muted required", null)
                        return
                    }
                    val conn = connections[id]
                    if (conn == null) {
                        result.success(false)
                        return
                    }
                    // Telecom exposes no public API for a self-managed
                    // ConnectionService to change the system mute state —
                    // `InCallService.setMuted` belongs to the system dialer,
                    // which a self-managed app is not. The actual muting is
                    // done by the voice session (V1.x), not here. Recording
                    // the state is what keeps a later system-side echo of the
                    // same value from bouncing back into Dart as a spurious
                    // `onSetMuted`.
                    conn.lastKnownMuted = muted
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        } catch (e: SecurityException) {
            // MANAGE_OWN_CALLS missing, or the OEM refuses self-managed
            // registration. Surface it — silently degrading is exactly the
            // failure mode §10.4 forbids.
            Log.e(TAG, "Telecom rejected ${call.method}", e)
            result.error("TELECOM_DENIED", e.message ?: "SecurityException", null)
        } catch (e: Throwable) {
            Log.e(TAG, "${call.method} failed", e)
            result.error("TELECOM_FAILED", e.message ?: e.javaClass.simpleName, null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun reportCall(call: MethodCall, incoming: Boolean): Boolean {
        val callId = call.argument<String>("callId") ?: return false
        val displayName = call.argument<String>("displayName") ?: ""
        val hasVideo = call.argument<Boolean>("hasVideo") ?: false

        val ctx = appContext ?: return false
        if (!isSupported) return false
        val handle = ensurePhoneAccount(ctx) ?: return false
        val tm = ctx.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
            ?: return false

        val callExtras = Bundle().apply {
            putString(EXTRA_CALL_ID, callId)
            putString(EXTRA_DISPLAY_NAME, displayName)
            putBoolean(EXTRA_HAS_VIDEO, hasVideo)
        }
        val address = addressFor(callId)

        if (incoming) {
            val extras = Bundle().apply {
                putParcelable(TelecomManager.EXTRA_INCOMING_CALL_ADDRESS, address)
                putBundle(TelecomManager.EXTRA_INCOMING_CALL_EXTRAS, callExtras)
                // Second copy at the top level: which of the two bundles the
                // ConnectionRequest ends up carrying is not contractual, and
                // callIdFromRequest reads both.
                putAll(callExtras)
            }
            tm.addNewIncomingCall(handle, extras)
        } else {
            val extras = Bundle().apply {
                putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, handle)
                putBundle(TelecomManager.EXTRA_OUTGOING_CALL_EXTRAS, callExtras)
                putAll(callExtras)
                if (hasVideo) {
                    putInt(
                        TelecomManager.EXTRA_START_CALL_WITH_VIDEO_STATE,
                        VideoProfile.STATE_BIDIRECTIONAL
                    )
                }
            }
            tm.placeCall(address, extras)
        }
        return true
    }

    // ── Telecom -> Dart ─────────────────────────────────────────────────────

    internal fun notifyAnswer(callId: String) = invoke("onAnswerCall", mapOf("callId" to callId))

    internal fun notifyEnd(callId: String) = invoke("onEndCall", mapOf("callId" to callId))

    internal fun notifyMuted(callId: String, muted: Boolean) =
        invoke("onSetMuted", mapOf("callId" to callId, "muted" to muted))

    private fun invoke(method: String, args: Map<String, Any>) {
        val ch = channel ?: run {
            // The channel is bound in MainActivity.configureFlutterEngine, so
            // it exists from the first Activity attach onwards. A Telecom
            // callback before that would have nowhere to go.
            Log.w(TAG, "$method dropped — channel not registered yet")
            return
        }
        mainHandler.post {
            try {
                ch.invokeMethod(method, args)
            } catch (e: Throwable) {
                Log.e(TAG, "invokeMethod($method) failed", e)
            }
        }
    }

    // ── Connection factory, called by CleonaConnectionService ───────────────

    internal fun createConnection(
        context: Context,
        request: ConnectionRequest?,
        incoming: Boolean
    ): Connection {
        val callId = callIdFromRequest(request)
            ?: return Connection.createFailedConnection(
                DisconnectCause(DisconnectCause.ERROR, "missing Cleona call id")
            )
        val bundle = mergedExtras(request)
        val displayName = bundle?.getString(EXTRA_DISPLAY_NAME).orEmpty()
        val hasVideo = bundle?.getBoolean(EXTRA_HAS_VIDEO, false) ?: false

        val conn = CleonaTelecomConnection(callId)
        conn.setAddress(addressFor(callId), TelecomManager.PRESENTATION_ALLOWED)
        if (displayName.isNotEmpty()) {
            conn.setCallerDisplayName(displayName, TelecomManager.PRESENTATION_ALLOWED)
        }
        // CAPABILITY_MUTE only. Hold is deliberately not advertised: the
        // MethodChannel contract has no hold callbacks, and advertising a
        // capability the app cannot serve is how a call "sounds right and
        // behaves wrong" (§10.4).
        conn.connectionCapabilities = Connection.CAPABILITY_MUTE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            conn.connectionProperties = Connection.PROPERTY_SELF_MANAGED
        }
        conn.videoState = if (hasVideo) {
            VideoProfile.STATE_BIDIRECTIONAL
        } else {
            VideoProfile.STATE_AUDIO_ONLY
        }
        // No setAudioModeIsVoip(), no setAudioRoute() — invariant I2, see the
        // class KDoc.

        connections[callId] = conn
        if (incoming) conn.setRinging() else conn.setDialing()
        return conn
    }

    /**
     * Telecom refused to create the connection (e.g. an ongoing cellular call
     * that outranks a self-managed one). Dart must learn that the call it just
     * reported does not exist, or it waits for an answer that can never come.
     */
    internal fun onCreateFailed(request: ConnectionRequest?) {
        val callId = callIdFromRequest(request) ?: return
        connections.remove(callId)
        notifyEnd(callId)
    }

    /** Called by [CleonaTelecomConnection] once it has torn itself down. */
    internal fun forget(callId: String) {
        connections.remove(callId)
    }

    // ── Helpers ─────────────────────────────────────────────────────────────

    private fun ensurePhoneAccount(ctx: Context): PhoneAccountHandle? {
        if (!isSupported) return null
        val tm = ctx.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
            ?: return null
        val handle = PhoneAccountHandle(
            ComponentName(ctx, CleonaConnectionService::class.java),
            PHONE_ACCOUNT_ID
        )
        if (phoneAccountRegistered) return handle

        val label = try {
            ctx.applicationInfo.loadLabel(ctx.packageManager).toString()
        } catch (_: Throwable) {
            "Cleona"
        }
        val account = PhoneAccount.builder(handle, label)
            // CAPABILITY_SELF_MANAGED and nothing else. A self-managed account
            // must not also claim CALL_PROVIDER / CONNECTION_MANAGER /
            // SIM_SUBSCRIPTION. CAPABILITY_VIDEO_CALLING is deliberately not
            // claimed either: the per-connection videoState is what Telecom
            // needs, Cleona renders its own video UI, and the account-level
            // flag has not been verified against a device (see report).
            // No PhoneAccount.EXTRA_LOG_SELF_MANAGED_CALLS: Cleona calls stay
            // out of the system call log.
            .setCapabilities(PhoneAccount.CAPABILITY_SELF_MANAGED)
            .addSupportedUriScheme(PhoneAccount.SCHEME_SIP)
            .build()
        tm.registerPhoneAccount(account)
        phoneAccountRegistered = true
        return handle
    }

    /**
     * Synthetic address. Telecom insists on a [Uri] whose scheme the account
     * declared; nothing ever dials it. The call id is url-encoded into the
     * user part so [callIdFromRequest] has a fallback that survives extras
     * being dropped.
     */
    private fun addressFor(callId: String): Uri =
        Uri.fromParts(PhoneAccount.SCHEME_SIP, "${Uri.encode(callId)}@$ADDRESS_HOST", null)

    private fun mergedExtras(request: ConnectionRequest?): Bundle? {
        val extras = request?.extras ?: return null
        if (extras.containsKey(EXTRA_CALL_ID)) return extras
        extras.getBundle(TelecomManager.EXTRA_INCOMING_CALL_EXTRAS)
            ?.let { if (it.containsKey(EXTRA_CALL_ID)) return it }
        extras.getBundle(TelecomManager.EXTRA_OUTGOING_CALL_EXTRAS)
            ?.let { if (it.containsKey(EXTRA_CALL_ID)) return it }
        return null
    }

    private fun callIdFromRequest(request: ConnectionRequest?): String? {
        mergedExtras(request)?.getString(EXTRA_CALL_ID)?.let { if (it.isNotEmpty()) return it }
        // Fallback: recover the id from the address user part.
        val ssp = request?.address?.schemeSpecificPart ?: return null
        val user = ssp.substringBefore('@')
        if (user.isEmpty()) return null
        return Uri.decode(user)
    }
}
