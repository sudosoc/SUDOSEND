package com.sudosoc.sudosend

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import androidx.core.content.IntentCompat
import io.flutter.embedding.android.FlutterActivity
import java.io.File
import java.lang.ref.WeakReference

class MainActivity : FlutterActivity() {
    override fun getCachedEngineId(): String = SudoSendApp.ENGINE_ID

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Bridge.activity = WeakReference(this)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        Bridge.activity = WeakReference(this)
    }

    override fun onDestroy() {
        if (Bridge.activity?.get() === this) Bridge.activity = null
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 4711) {
            Bridge.onPermissionResult(grantResults.isNotEmpty() && grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED)
        }
    }

    private fun handleIntent(intent: Intent?) {
        intent ?: return
        when (intent.action) {
            Intent.ACTION_SEND, Intent.ACTION_SEND_MULTIPLE -> {
                importShare(intent)
                // Consume the intent so a rotation doesn't import it twice.
                intent.action = Intent.ACTION_MAIN
            }
            Notifications.ACTION_ACCEPT, Notifications.ACTION_OPEN -> {
                val id = intent.getStringExtra(Notifications.EXTRA_ID) ?: return
                val action = if (intent.action == Notifications.ACTION_ACCEPT) "accept" else "open"
                if (action == "accept") Notifications.cancel(this, id)
                Bridge.emit("onNotificationAction", mapOf("id" to id, "action" to action))
                intent.action = Intent.ACTION_MAIN
            }
        }
    }

    /** Copies shared content into the cache (content:// URIs are not files). */
    private fun importShare(intent: Intent) {
        val uris = ArrayList<Uri>()
        if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            IntentCompat.getParcelableArrayListExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)?.let { uris.addAll(it) }
        } else {
            IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)?.let { uris.add(it) }
        }
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
        val resolver = contentResolver
        val root = File(cacheDir, "shared")
        Thread {
            root.listFiles()?.forEach { it.deleteRecursively() }
            val dir = File(root, System.currentTimeMillis().toString()).apply { mkdirs() }
            val files = ArrayList<Map<String, Any>>()
            for ((index, uri) in uris.withIndex()) {
                try {
                    var name = "shared-$index"
                    resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                        if (c.moveToFirst() && !c.isNull(0)) name = c.getString(0)
                    }
                    name = name.replace(Regex("[/\\\\\\u0000]"), "_").ifBlank { "shared-$index" }
                    var target = File(dir, name)
                    var n = 1
                    while (target.exists()) target = File(dir, "${n++}-$name")
                    resolver.openInputStream(uri)?.use { input ->
                        target.outputStream().use { output -> input.copyTo(output, 256 * 1024) }
                    }
                    files.add(mapOf("path" to target.absolutePath, "name" to target.name, "size" to target.length()))
                } catch (e: Exception) {
                    // Skip items we cannot read.
                }
            }
            val payload = HashMap<String, Any?>()
            payload["files"] = files
            payload["text"] = if (files.isEmpty()) text else null
            Bridge.pendingShare = payload
            Bridge.emit("onShare", null)
        }.start()
    }
}
