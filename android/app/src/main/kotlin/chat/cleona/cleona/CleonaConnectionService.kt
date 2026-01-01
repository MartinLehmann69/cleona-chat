package chat.cleona.cleona

import android.telecom.CallAudioState
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.DisconnectCause
import android.telecom.PhoneAccountHandle
import android.util.Log

/**
 * V3.2 — the `ConnectionService` half of Cleona's self-managed Telecom
 * integration. All policy, all state and the MethodChannel live in
 * [CleonaCallIntegration]; this class is the component Telecom binds to
 * (`android.telecom.ConnectionService` intent filter, `BIND_TELECOM_
 * CONNECTION_SERVICE` permission, see `AndroidManifest.xml`).
 *
 * Architecture §10.4, "Session behaviour" table, row "Call integration";
 * staging table row 7. Work package V3.2.
 *
 * Invariant I2 applies here too: no audio route is set, no `AudioManager`
 * mode is touched, no audio focus is requested. See [CleonaCallIntegration].
 */
class CleonaConnectionService : ConnectionService() {

    companion object {
        private const val TAG = "CleonaConnService"
    }

    override fun onCreateIncomingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ): Connection = CleonaCallIntegration.createConnection(this, request, incoming = true)

    override fun onCreateOutgoingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ): Connection = CleonaCallIntegration.createConnection(this, request, incoming = false)

    // API 26+. Telecom refused the call (typically: a cellular call already
    // owns the audio). Without this, Dart would keep waiting for an answer
    // that can never arrive — the silent-failure mode §10.4 forbids.
    override fun onCreateIncomingConnectionFailed(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ) {
        Log.w(TAG, "Telecom refused the incoming connection")
        CleonaCallIntegration.onCreateFailed(request)
    }

    override fun onCreateOutgoingConnectionFailed(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ) {
        Log.w(TAG, "Telecom refused the outgoing connection")
        CleonaCallIntegration.onCreateFailed(request)
    }
}

/**
 * One live Telecom connection == one Cleona call. Every override here does
 * exactly two things: move the Telecom state machine, and tell Dart. It never
 * starts, stops or routes audio — that is [VoiceSession]'s job (invariant I2,
 * §10.4).
 *
 * The class name is prefixed on purpose: [VoiceSession] and [VideoSession]
 * share this package and already collided once over generic top-level names
 * (S296).
 */
class CleonaTelecomConnection(private val callId: String) : Connection() {

    companion object {
        private const val TAG = "CleonaTelecomConn"
    }

    /**
     * Last mute value either side has seen. Written from two directions:
     * Telecom's [onCallAudioStateChanged] and Dart's `setMuted`. Comparing
     * against it is what keeps a state change from ping-ponging — Dart mutes,
     * the system echoes the same value back, and without this the echo would
     * arrive in Dart as a fresh `onSetMuted`.
     */
    @Volatile
    var lastKnownMuted: Boolean = false

    /** Guards against a double teardown (e.g. onReject followed by endCall). */
    @Volatile
    private var finished = false

    override fun onAnswer() {
        onAnswer(videoState)
    }

    override fun onAnswer(videoState: Int) {
        // No setActive() here. The call is active once Cleona's media path is
        // up, which Dart signals with `reportCallConnected`. Claiming ACTIVE
        // before the voice session exists is precisely "sounds right, behaves
        // wrong".
        CleonaCallIntegration.notifyAnswer(callId)
    }

    override fun onReject() {
        CleonaCallIntegration.notifyEnd(callId)
        finish(DisconnectCause.REJECTED)
    }

    override fun onDisconnect() {
        CleonaCallIntegration.notifyEnd(callId)
        finish(DisconnectCause.LOCAL)
    }

    override fun onAbort() {
        CleonaCallIntegration.notifyEnd(callId)
        finish(DisconnectCause.CANCELED)
    }

    // `CallAudioState` / `onCallAudioStateChanged` are deprecated as of API 34
    // in favour of `CallEndpoint` / `onCallEndpointChanged` + the API-34
    // `onMuteStateChanged`. minSdk here is 24, and the deprecated callback is
    // the one every supported API level delivers, so it stays the single path
    // — overriding both would report the same transition twice on 34+.
    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onCallAudioStateChanged(state: CallAudioState?) {
        val muted = state?.isMuted ?: return
        if (muted == lastKnownMuted) return
        lastKnownMuted = muted
        CleonaCallIntegration.notifyMuted(callId, muted)
    }

    /**
     * API 26+, self-managed only: Telecom asks the app to put up its own
     * incoming-call UI. Cleona already does that on its own timeline — the
     * incoming-call notification with the full-screen intent is raised from
     * Dart via `chat.cleona/notification` (`MainActivity`, `cleona_calls`
     * channel) at the moment `CALL_INVITE` arrives, which is also the moment
     * `reportIncomingCall` fires. Posting a second one here would double it,
     * so this override only records that Telecom asked.
     */
    override fun onShowIncomingCallUi() {
        Log.i(TAG, "Telecom requested the incoming-call UI for $callId")
    }

    /**
     * Terminal transition. Idempotent, so Dart's `endCall` racing a system
     * hang-up cannot disconnect twice.
     */
    internal fun finish(cause: Int) {
        if (finished) return
        finished = true
        setDisconnected(DisconnectCause(cause))
        destroy()
        CleonaCallIntegration.forget(callId)
    }
}
