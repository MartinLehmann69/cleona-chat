package chat.cleona.cleona

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache

class CleonaApplication : Application() {
    companion object {
        const val ENGINE_ID = "cleona_engine"
    }

    override fun onCreate() {
        super.onCreate()
        val engine = FlutterEngine(this)
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
    }
}
