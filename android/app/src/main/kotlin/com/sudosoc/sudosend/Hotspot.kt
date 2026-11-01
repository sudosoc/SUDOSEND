package com.sudosoc.sudosend

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.MethodChannel

/**
 * "No Wi-Fi? Make one." Starts an Android local-only hotspot (no internet,
 * just a private network) so another phone or laptop can join by scanning a
 * Wi-Fi QR code and SUDOSEND works with no router at all.
 */
object Hotspot {
    private var reservation: WifiManager.LocalOnlyHotspotReservation? = null

    @RequiresApi(Build.VERSION_CODES.O)
    fun start(ctx: Context, result: MethodChannel.Result) {
        reservation?.let {
            result.success(describe(it))
            return
        }
        val wifi = ctx.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        try {
            wifi.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                override fun onStarted(r: WifiManager.LocalOnlyHotspotReservation) {
                    reservation = r
                    result.success(describe(r))
                }

                override fun onStopped() {
                    reservation = null
                    Bridge.emit("onHotspotStopped", null)
                }

                override fun onFailed(reason: Int) {
                    val why = when (reason) {
                        ERROR_TETHERING_DISALLOWED -> "Hotspot is not allowed on this device"
                        ERROR_INCOMPATIBLE_MODE -> "Turn off the normal hotspot / tethering first"
                        else -> "Could not start the hotspot (code $reason). Turn on Location and try again."
                    }
                    result.error("failed", why, null)
                }
            }, Handler(Looper.getMainLooper()))
        } catch (e: SecurityException) {
            result.error("permission", "Permission needed to start a hotspot", null)
        } catch (e: IllegalStateException) {
            result.error("busy", e.message ?: "Hotspot busy", null)
        }
    }

    fun stop() {
        reservation?.close()
        reservation = null
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun describe(r: WifiManager.LocalOnlyHotspotReservation): Map<String, String?> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val c = r.softApConfiguration
            @Suppress("DEPRECATION")
            mapOf("ssid" to c.ssid, "password" to c.passphrase)
        } else {
            @Suppress("DEPRECATION")
            val c = r.wifiConfiguration
            @Suppress("DEPRECATION")
            mapOf("ssid" to c?.SSID?.trim('"'), "password" to c?.preSharedKey?.trim('"'))
        }
    }
}
