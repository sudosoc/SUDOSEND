package com.sudosoc.sudosend

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.lang.ref.WeakReference

/** Native side of the `sudosend/native` method channel. */
object Bridge {
    private const val CHANNEL = "sudosend/native"

    lateinit var app: Context
    private var channel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())
    private var multicastLock: WifiManager.MulticastLock? = null

    var activity: WeakReference<Activity>? = null
    var pendingShare: Map<String, Any?>? = null
    private var pendingPermission: MethodChannel.Result? = null

    fun emit(method: String, args: Any?) {
        main.post { channel?.invokeMethod(method, args) }
    }

    fun attach(engine: FlutterEngine) {
        val ch = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "acquireMulticastLock" -> {
                        if (multicastLock == null) {
                            val wifi = app.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                            multicastLock = wifi.createMulticastLock("sudosend-discovery").apply {
                                setReferenceCounted(false)
                                acquire()
                            }
                        }
                        result.success(true)
                    }
                    "releaseMulticastLock" -> {
                        multicastLock?.let { if (it.isHeld) it.release() }
                        multicastLock = null
                        result.success(true)
                    }
                    "downloadsDir" -> {
                        @Suppress("DEPRECATION")
                        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                        result.success(dir.absolutePath)
                    }
                    "service" -> {
                        TransferService.update(
                            app,
                            call.argument<String>("mode") ?: "off",
                            call.argument<String>("title") ?: "SUDOSEND",
                            call.argument<String>("text") ?: "",
                            call.argument<Int>("progress") ?: -1,
                        )
                        result.success(true)
                    }
                    "notifyIncoming" -> {
                        Notifications.incoming(
                            app,
                            call.argument<String>("id") ?: "",
                            call.argument<String>("title") ?: "",
                            call.argument<String>("text") ?: "",
                            call.argument<String>("accept") ?: "Accept",
                            call.argument<String>("decline") ?: "Decline",
                        )
                        result.success(true)
                    }
                    "notify" -> {
                        Notifications.info(
                            app,
                            call.argument<String>("id") ?: "",
                            call.argument<String>("title") ?: "",
                            call.argument<String>("text") ?: "",
                        )
                        result.success(true)
                    }
                    "cancelNotification" -> {
                        Notifications.cancel(app, call.argument<String>("id") ?: "")
                        result.success(true)
                    }
                    "requestPermission" -> requestPermission(call.argument<String>("name") ?: "", result)
                    "takeShare" -> {
                        result.success(pendingShare)
                        pendingShare = null
                    }
                    "openFile" -> result.success(openFile(call.argument<String>("path") ?: ""))
                    "openUrl" -> result.success(openUrl(call.argument<String>("url") ?: ""))
                    "vaultSeal" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            result.success(KeystoreVault.seal(call.argument<ByteArray>("data")!!))
                        } else {
                            result.error("unsupported", "Android Keystore needs Android 6+", null)
                        }
                    }
                    "vaultOpen" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            result.success(KeystoreVault.open(call.argument<ByteArray>("data")!!))
                        } else {
                            result.error("unsupported", "Android Keystore needs Android 6+", null)
                        }
                    }
                    "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                    "abi" -> result.success(Build.SUPPORTED_ABIS.firstOrNull() ?: "")
                    "installApk" -> result.success(installApk(call.argument<String>("path") ?: ""))
                    "isLowRam" -> {
                        val am = app.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
                        result.success(am.isLowRamDevice || Runtime.getRuntime().availableProcessors() <= 4)
                    }
                    "startHotspot" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Hotspot.start(app, result)
                        } else {
                            result.error("unsupported", "Needs Android 8 or newer", null)
                        }
                    }
                    "ring" -> {
                        Ringer.start(
                            app,
                            call.argument<String>("name") ?: "",
                            call.argument<String>("title") ?: "SUDOSEND",
                            call.argument<String>("stop") ?: "Stop",
                        )
                        result.success(true)
                    }
                    "stopRing" -> {
                        Ringer.stop(app)
                        result.success(true)
                    }
                    "listApps" -> Apps.list(app, result)
                    "apkInfo" -> Apps.apkInfo(app, call.argument<String>("path") ?: "", result)
                    "installApks" -> Apps.install(app, call.argument<List<String>>("paths") ?: emptyList(), result)
                    "diskSpace" -> {
                        val path = call.argument<String>("path") ?: app.filesDir.path
                        val dir = File(path).let { if (it.exists()) it else app.filesDir }
                        val st = android.os.StatFs(dir.path)
                        result.success(listOf(st.availableBytes, st.totalBytes))
                    }
                    "p2pAttach" -> {
                        val ok = WifiDirect.attach(app)
                        if (ok) WifiDirect.advertise(app, call.argument<String>("name") ?: "", call.argument<String>("fp") ?: "")
                        result.success(ok)
                    }
                    "p2pScan" -> WifiDirect.startScan(app, result)
                    "p2pStopScan" -> {
                        WifiDirect.stopScan()
                        result.success(true)
                    }
                    "p2pConnect" -> WifiDirect.connect(call.argument<String>("address") ?: "", result)
                    "p2pDisconnect" -> WifiDirect.disconnect(result)
                    "stopHotspot" -> {
                        Hotspot.stop()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("native", e.message, null)
            }
        }
    }

    private fun requestPermission(name: String, result: MethodChannel.Result) {
        val permission = when (name) {
            "notifications" -> if (Build.VERSION.SDK_INT >= 33) Manifest.permission.POST_NOTIFICATIONS else null
            "storage" -> if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) Manifest.permission.WRITE_EXTERNAL_STORAGE else null
            "hotspot", "wifidirect" -> if (Build.VERSION.SDK_INT >= 33) Manifest.permission.NEARBY_WIFI_DEVICES else Manifest.permission.ACCESS_FINE_LOCATION
            else -> null
        }
        if (permission == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(true)
            return
        }
        if (app.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        val act = activity?.get()
        if (act == null || pendingPermission != null) {
            result.success(false)
            return
        }
        pendingPermission = result
        act.requestPermissions(arrayOf(permission), 4711)
    }

    fun onPermissionResult(granted: Boolean) {
        pendingPermission?.success(granted)
        pendingPermission = null
    }

    private fun openUrl(url: String): Boolean {
        val uri = android.net.Uri.parse(url)
        if (uri.scheme != "http" && uri.scheme != "https") return false
        return try {
            app.startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    /**
     * Hands a downloaded update to the system installer. Returns "ok",
     * "permission" (the user must allow installs from SUDOSEND first — the
     * settings screen is opened) or "error". Android itself refuses an APK
     * that is not signed with the same key as the installed app.
     */
    private fun installApk(path: String): String {
        val file = File(path)
        if (!file.exists()) return "error"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !app.packageManager.canRequestPackageInstalls()) {
            return try {
                app.startActivity(
                    Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        android.net.Uri.parse("package:${app.packageName}"))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                "permission"
            } catch (e: ActivityNotFoundException) {
                "error"
            }
        }
        val uri = FileProvider.getUriForFile(app, "${app.packageName}.files", file)
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            app.startActivity(intent)
            "ok"
        } catch (e: ActivityNotFoundException) {
            "error"
        }
    }

    private fun openFile(path: String): Boolean {
        val file = File(path)
        if (!file.exists()) return false
        val uri = FileProvider.getUriForFile(app, "${app.packageName}.files", file)
        val ext = MimeTypeMap.getFileExtensionFromUrl(file.name).lowercase()
        val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "*/*"
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, mime)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            app.startActivity(Intent.createChooser(intent, file.name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }
}
