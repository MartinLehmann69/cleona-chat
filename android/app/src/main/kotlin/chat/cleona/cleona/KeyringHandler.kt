package chat.cleona.cleona

import android.app.KeyguardManager
import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.UserNotAuthenticatedException
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import androidx.security.crypto.MasterKeys
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

// §3.7 OS Keyring: EncryptedSharedPreferences backed by AndroidKeyStore.
// AES-256-GCM value encryption, AES-256-SIV key encryption, hardware-backed
// master key on devices with StrongBox/TEE.
class KeyringHandler(private val context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL_NAME = "chat.cleona/keyring"
        private const val TAG = "KeyringHandler"
        private const val PREFS_NAME = "cleona_keyring"

        // ── S363, point 1 (option D): the lock on the 24 words ──────
        //
        // A SECOND store with a SECOND master key. Why not a
        // locked key for the existing store (option B of the
        // proposal `docs/v4-redesign/S363-VORLAGE-android-sperre-und-salt.md`):
        //
        //   * The master seed would gain nothing from it. It lies, as measured, TWICE
        //     — in the keyring AND as `master_seed.json.enc` under the
        //     raw key file `db.key` next to it; the proposal opened it in the
        //     emulator with libsodium alone, bypassing the keyring
        //     (finding F-4). A lock in front of an open door.
        //   * `MobileKeyringService.init` reads ALL entries at startup
        //     (`loadAll`). If a locked entry were in the same store,
        //     the startup itself would already prompt or fail.
        //   * The foreground service needs the seed, not the 24 words:
        //     `loadSeedPhrase()` has, as measured, THREE callers, all display
        //     or export, none in the receive path.
        //
        // If this store fails (no screen lock), the
        // unlocked store remains untouched — so only the phrase
        // falls back, not the whole profile.
        private const val PREFS_GATED = "cleona_keyring_gated"
        private const val GATED_KEY_ALIAS = "cleona_keyring_gated_master_key"

        // Time window of the auth-bound key in seconds.
        //
        // 300 is the library's default value — measured on the bytecode of the
        // version actually built
        // (`androidx.security:security-crypto:1.1.0-alpha06`,
        // `MasterKey.getDefaultAuthenticationValidityDurationSeconds()`
        // loads `sipush 300`). It is set EXPLICITLY here instead of
        // silently taken over, so that the number stands in one place
        // where a reader finds it.
        //
        // What the number means (platform behaviour, NOT measured — the
        // emulator could not be started in S363 for lack of disk space):
        // from API 30 on, the library calls
        // `setUserAuthenticationParameters(dauer, 3)`, and the 3 is
        // `AUTH_BIOMETRIC_STRONG or AUTH_DEVICE_CREDENTIAL`. The key
        // is thus usable for 300 s after the last unlock, after that
        // it requires a new confirmation.
        private const val GATED_AUTH_SECONDS = 300

        // Response identifiers of the bridge. They are part of the contract with
        // `lib/core/crypto/keyring_mobile.dart` — whoever changes something here
        // changes it there too.
        const val GATE_READY = "READY"
        const val GATE_NO_DEVICE_LOCK = "NO_DEVICE_LOCK"
        const val GATE_AUTH_REQUIRED = "AUTH_REQUIRED"
        const val GATE_INVALIDATED = "INVALIDATED"
        const val GATE_UNAVAILABLE = "UNAVAILABLE"
    }

    private var prefs: SharedPreferences? = null
    private var initError: String? = null

    private var gatedPrefs: SharedPreferences? = null
    /// Only for errors that do not resolve themselves (no
    /// screen lock, key permanently invalid). `AUTH_REQUIRED`
    /// EXPLICITLY does not belong here — the state passes with the
    /// next confirmation, and making it sticky would mean permanently
    /// disabling the lock the first time the window expires.
    private var gatedSticky: String? = null

    private fun isDeviceSecure(): Boolean = try {
        val km = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        km.isDeviceSecure
    } catch (e: Exception) {
        Log.w(TAG, "KeyguardManager unavailable", e)
        false
    }

    /// Walk the cause chain — AndroidKeyStore regularly wraps
    /// `UserNotAuthenticatedException` in a
    /// `GeneralSecurityException` or an `IllegalStateException` of the
    /// Tink layer below. Checking only `e` itself therefore reads
    /// "unknown error" where "please confirm" is written.
    private fun classify(e: Throwable): String {
        var cur: Throwable? = e
        var depth = 0
        while (cur != null && depth < 12) {
            when (cur) {
                is UserNotAuthenticatedException -> return GATE_AUTH_REQUIRED
                is KeyPermanentlyInvalidatedException -> return GATE_INVALIDATED
            }
            cur = cur.cause
            depth++
        }
        return GATE_UNAVAILABLE
    }

    /// The locked store. Returns `null` and writes the reason to
    /// [lastGateReason]; the caller reports it to the Dart side.
    private var lastGateReason: String = GATE_UNAVAILABLE

    private fun getGatedPrefs(): SharedPreferences? {
        gatedPrefs?.let { lastGateReason = GATE_READY; return it }
        gatedSticky?.let { lastGateReason = it; return null }
        if (!isDeviceSecure()) {
            // No PIN/pattern/password: an auth-bound key cannot
            // even be CREATED. That is finding F-1 of the proposal and
            // the reason why the salt (point 3) was built before this lock:
            // the path from here leads into the file fallback, and
            // its key was the same on Android in EVERY installation.
            gatedSticky = GATE_NO_DEVICE_LOCK
            lastGateReason = GATE_NO_DEVICE_LOCK
            return null
        }
        return try {
            val masterKey = MasterKey.Builder(context, GATED_KEY_ALIAS)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .setUserAuthenticationRequired(true, GATED_AUTH_SECONDS)
                .build()
            val p = EncryptedSharedPreferences.create(
                context,
                PREFS_GATED,
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
            gatedPrefs = p
            lastGateReason = GATE_READY
            p
        } catch (e: Exception) {
            val kind = classify(e)
            Log.w(TAG, "gated keyring unavailable ($kind)", e)
            if (kind == GATE_INVALIDATED) {
                // The user has removed or changed the screen lock;
                // the key is permanently gone and with it
                // the content. Clean up so that the next attempt does not
                // hang forever on a corpse — the CONTENT cannot be saved
                // anyway, so this is not data loss but
                // its cleanup.
                dropGate()
            }
            if (kind != GATE_AUTH_REQUIRED) gatedSticky = kind
            lastGateReason = kind
            null
        }
    }

    private fun dropGate() {
        gatedPrefs = null
        try {
            context.getSharedPreferences(PREFS_GATED, Context.MODE_PRIVATE)
                .edit().clear().commit()
        } catch (e: Exception) {
            Log.w(TAG, "could not clear $PREFS_GATED", e)
        }
        try {
            val ks = java.security.KeyStore.getInstance("AndroidKeyStore")
            ks.load(null)
            if (ks.containsAlias(GATED_KEY_ALIAS)) ks.deleteEntry(GATED_KEY_ALIAS)
        } catch (e: Exception) {
            Log.w(TAG, "could not delete $GATED_KEY_ALIAS", e)
        }
    }

    private fun getPrefs(): SharedPreferences? {
        if (prefs != null) return prefs
        if (initError != null) return null
        try {
            val masterKeyAlias = MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC)
            prefs = EncryptedSharedPreferences.create(
                PREFS_NAME,
                masterKeyAlias,
                context,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
            return prefs
        } catch (e: Exception) {
            Log.e(TAG, "EncryptedSharedPreferences init failed — keyring unavailable", e)
            initError = e.message ?: "unknown error"
            return null
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        // ── The locked store first ──────────────────────────────────
        //
        // It comes BEFORE the `getPrefs()` check because it is
        // independent of the unlocked store: a device whose
        // ordinary keyring does not open should still get a
        // clear answer about the lock (and vice versa).
        when (call.method) {
            "gateStatus" -> {
                getGatedPrefs()
                result.success(lastGateReason)
                return
            }
            "storeGated" -> {
                val name = call.argument<String>("name")
                val data = call.argument<String>("data")
                if (name == null || data == null) {
                    result.error("INVALID_ARGS", "name and data required", null)
                    return
                }
                val g = getGatedPrefs()
                if (g == null) {
                    result.error(lastGateReason, "gated keyring unavailable", null)
                    return
                }
                try {
                    g.edit().putString(name, data).commit()
                    result.success(true)
                } catch (e: Exception) {
                    val kind = classify(e)
                    Log.w(TAG, "gated store failed for \"$name\" ($kind)", e)
                    if (kind == GATE_INVALIDATED) dropGate()
                    result.error(kind, e.message ?: kind, null)
                }
                return
            }
            "loadGated" -> {
                val name = call.argument<String>("name")
                if (name == null) {
                    result.error("INVALID_ARGS", "name required", null)
                    return
                }
                val g = getGatedPrefs()
                if (g == null) {
                    result.error(lastGateReason, "gated keyring unavailable", null)
                    return
                }
                try {
                    result.success(g.getString(name, null))
                } catch (e: Exception) {
                    val kind = classify(e)
                    Log.w(TAG, "gated load failed for \"$name\" ($kind)", e)
                    if (kind == GATE_INVALIDATED) dropGate()
                    result.error(kind, e.message ?: kind, null)
                }
                return
            }
            "deleteGated" -> {
                val name = call.argument<String>("name")
                if (name == null) {
                    result.error("INVALID_ARGS", "name required", null)
                    return
                }
                val g = getGatedPrefs()
                if (g == null) {
                    result.error(lastGateReason, "gated keyring unavailable", null)
                    return
                }
                try {
                    g.edit().remove(name).commit()
                    result.success(true)
                } catch (e: Exception) {
                    val kind = classify(e)
                    Log.w(TAG, "gated delete failed for \"$name\" ($kind)", e)
                    result.error(kind, e.message ?: kind, null)
                }
                return
            }
        }

        val p = getPrefs()
        if (p == null) {
            result.error("KEYRING_UNAVAILABLE",
                "EncryptedSharedPreferences init failed: $initError", null)
            return
        }
        when (call.method) {
            "store" -> {
                val name = call.argument<String>("name")
                val data = call.argument<String>("data")
                if (name == null || data == null) {
                    result.error("INVALID_ARGS", "name and data required", null)
                    return
                }
                p.edit().putString(name, data).commit()
                result.success(true)
            }
            "load" -> {
                val name = call.argument<String>("name")
                if (name == null) {
                    result.error("INVALID_ARGS", "name required", null)
                    return
                }
                result.success(p.getString(name, null))
            }
            "delete" -> {
                val name = call.argument<String>("name")
                if (name == null) {
                    result.error("INVALID_ARGS", "name required", null)
                    return
                }
                p.edit().remove(name).commit()
                result.success(true)
            }
            "loadAll" -> {
                val all = mutableMapOf<String, String>()
                for ((key, value) in p.all) {
                    if (value is String) all[key] = value
                }
                result.success(all)
            }
            else -> result.notImplemented()
        }
    }
}
