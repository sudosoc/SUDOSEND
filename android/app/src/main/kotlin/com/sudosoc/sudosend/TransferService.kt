package com.sudosoc.sudosend

import android.app.Notification
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Foreground service that keeps the process (and the cached Flutter engine)
 * alive while files move, or while "receive in background" is on. During an
 * active transfer it also holds a Wi-Fi lock and a partial wake lock so the
 * radio and CPU don't sleep when the screen turns off.
 */
class TransferService : Service() {
    companion object {
        private const val NOTIFICATION_ID = 4711
        private var instance: TransferService? = null

        fun update(ctx: Context, mode: String, title: String, text: String, progress: Int) {
            if (mode == "off") {
                instance?.shutdown()
                return
            }
            val running = instance
            if (running != null) {
                running.apply(mode, title, text, progress)
                return
            }
            val intent = Intent(ctx, TransferService::class.java)
                .putExtra("mode", mode)
                .putExtra("title", title)
                .putExtra("text", text)
                .putExtra("progress", progress)
            try {
                ContextCompat.startForegroundService(ctx, intent)
            } catch (e: Exception) {
                // Android 12+ refuses to start foreground services from the
                // background. The transfer continues while the process lives.
            }
        }
    }

    private var wifiLock: WifiManager.WifiLock? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val mode = intent?.getStringExtra("mode") ?: "idle"
        val notification = build(
            intent?.getStringExtra("title") ?: "SUDOSEND",
            intent?.getStringExtra("text") ?: "",
            intent?.getIntExtra("progress", -1) ?: -1,
        )
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC else 0
        ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, type)
        setLocks(mode == "active")
        return START_NOT_STICKY
    }

    fun apply(mode: String, title: String, text: String, progress: Int) {
        try {
            NotificationManagerCompat.from(this).notify(NOTIFICATION_ID, build(title, text, progress))
        } catch (e: SecurityException) {
        }
        setLocks(mode == "active")
    }

    private fun build(title: String, text: String, progress: Int): Notification {
        val b = NotificationCompat.Builder(this, Notifications.CH_TRANSFERS)
            .setSmallIcon(R.drawable.ic_stat_sudosend)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(Notifications.openAppIntent(this, Notifications.ACTION_OPEN, "service"))
        if (progress in 0..100) b.setProgress(100, progress, false)
        return b.build()
    }

    private fun setLocks(active: Boolean) {
        if (active) {
            if (wifiLock == null) {
                val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                @Suppress("DEPRECATION")
                val wifiMode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                } else {
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF
                }
                wifiLock = wifi.createWifiLock(wifiMode, "sudosend:transfer").apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }
            if (wakeLock == null) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "sudosend:transfer").apply {
                    setReferenceCounted(false)
                    acquire(6 * 60 * 60 * 1000L)
                }
            }
        } else {
            releaseLocks()
        }
    }

    private fun releaseLocks() {
        wifiLock?.let { if (it.isHeld) it.release() }
        wifiLock = null
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }

    fun shutdown() {
        releaseLocks()
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    // Android 14/15 data-sync time limit reached.
    override fun onTimeout(startId: Int) {
        shutdown()
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        shutdown()
    }

    override fun onDestroy() {
        releaseLocks()
        instance = null
        super.onDestroy()
    }
}
