package com.sudosoc.sudosend

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Environment
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sudosend/net")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Android drops multicast/broadcast UDP without this lock,
                    // which would make discovery one-way.
                    "acquireMulticastLock" -> {
                        if (multicastLock == null) {
                            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                            multicastLock = wifi.createMulticastLock("sudosend-discovery").apply {
                                setReferenceCounted(false)
                                acquire()
                            }
                        }
                        result.success(true)
                    }
                    "releaseMulticastLock" -> {
                        releaseLock()
                        result.success(true)
                    }
                    "downloadsDir" -> {
                        @Suppress("DEPRECATION")
                        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                        result.success(dir.absolutePath)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun releaseLock() {
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
    }

    override fun onDestroy() {
        releaseLock()
        super.onDestroy()
    }
}
