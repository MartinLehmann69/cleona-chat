package chat.cleona.cleona

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
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
    }

    private var prefs: SharedPreferences? = null
    private var initError: String? = null

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
