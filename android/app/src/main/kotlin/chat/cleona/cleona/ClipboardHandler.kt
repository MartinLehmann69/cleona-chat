package chat.cleona.cleona

import android.content.ClipboardManager
import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Bug #U12 — Android clipboard bridge for binary items.
 *
 * Flutter's Clipboard API only exposes text, so mixed clipboards (image +
 * caption text) silently dropped the media half. This channel iterates
 * ClipData items, resolves the first media/file URI, copies it to cacheDir
 * (producer apps may revoke access on focus loss), and hands {path, mime,
 * filename} to Dart. The Dart layer prefers this over text, matching
 * Linux/macOS priority.
 */
class ClipboardHandler(private val context: Context) : MethodChannel.MethodCallHandler {
    companion object { const val CHANNEL_NAME = "chat.cleona/clipboard" }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "readMediaItem") result.success(readMediaItem())
        else result.notImplemented()
    }

    private fun readMediaItem(): Map<String, String>? {
        try {
            val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager ?: return null
            val clip = cm.primaryClip ?: return null
            val resolver = context.contentResolver
            for (i in 0 until clip.itemCount) {
                val uri = clip.getItemAt(i).uri ?: continue
                val mime = resolveMime(resolver, uri) ?: continue
                if (!isMediaOrFile(mime)) continue
                val path = copyToCache(resolver, uri, mime) ?: continue
                return mapOf("path" to path, "mimeType" to mime, "filename" to File(path).name)
            }
        } catch (_: Throwable) { /* SecurityException on focus loss — treat as empty */ }
        return null
    }

    private fun resolveMime(resolver: ContentResolver, uri: Uri): String? {
        resolver.getType(uri)?.let { return it }
        val ext = MimeTypeMap.getFileExtensionFromUrl(uri.toString())
        if (!ext.isNullOrEmpty())
            MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext.lowercase())?.let { return it }
        return null
    }

    private fun isMediaOrFile(mime: String) = mime.startsWith("image/") ||
        mime.startsWith("video/") || mime.startsWith("audio/") ||
        (mime.startsWith("application/") && mime != "application/x-gtk-text-buffer-contents")

    private fun copyToCache(resolver: ContentResolver, uri: Uri, mime: String): String? {
        val ext = MimeTypeMap.getSingleton().getExtensionFromMimeType(mime) ?: "bin"
        val dst = File(context.cacheDir, "clipboard_${System.currentTimeMillis()}.$ext")
        return try {
            resolver.openInputStream(uri)?.use { input ->
                dst.outputStream().use { output -> input.copyTo(output) }
            }
            if (dst.length() > 0) dst.absolutePath else null
        } catch (_: Throwable) { null }
    }
}
