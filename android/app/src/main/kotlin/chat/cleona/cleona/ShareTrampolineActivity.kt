package chat.cleona.cleona

import android.app.Activity
import android.content.Intent
import android.os.Bundle

class ShareTrampolineActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val forward = Intent(this, MainActivity::class.java).apply {
            action = intent.action
            type = intent.type
            intent.extras?.let { putExtras(it) }
            if (intent.clipData != null) clipData = intent.clipData
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_GRANT_READ_URI_PERMISSION
        }
        startActivity(forward)
        finish()
    }
}
