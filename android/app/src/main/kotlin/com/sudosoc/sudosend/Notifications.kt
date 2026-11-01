package com.sudosoc.sudosend

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

object Notifications {
    const val CH_TRANSFERS = "transfers"
    const val CH_REQUESTS = "requests"
    const val CH_DONE = "done"

    const val ACTION_ACCEPT = "com.sudosoc.sudosend.ACCEPT"
    const val ACTION_DECLINE = "com.sudosoc.sudosend.DECLINE"
    const val ACTION_OPEN = "com.sudosoc.sudosend.OPEN"
    const val EXTRA_ID = "id"

    fun idOf(key: String): Int = 10_000 + (key.hashCode() and 0x3FFFFFFF) % 1_000_000

    fun createChannels(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CH_TRANSFERS, "Transfers in progress", NotificationManager.IMPORTANCE_LOW).apply {
                setShowBadge(false)
            }
        )
        nm.createNotificationChannel(
            NotificationChannel(CH_REQUESTS, "Incoming requests", NotificationManager.IMPORTANCE_HIGH)
        )
        nm.createNotificationChannel(
            NotificationChannel(CH_DONE, "Finished transfers", NotificationManager.IMPORTANCE_DEFAULT)
        )
    }

    private fun flags() = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

    fun openAppIntent(ctx: Context, action: String, id: String): PendingIntent {
        val intent = Intent(ctx, MainActivity::class.java)
            .setAction(action)
            .putExtra(EXTRA_ID, id)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(ctx, (action + id).hashCode(), intent, flags())
    }

    fun incoming(ctx: Context, id: String, title: String, text: String, accept: String, decline: String) {
        val declineIntent = PendingIntent.getBroadcast(
            ctx,
            (ACTION_DECLINE + id).hashCode(),
            Intent(ctx, NotificationActionReceiver::class.java).setAction(ACTION_DECLINE).putExtra(EXTRA_ID, id),
            flags(),
        )
        val n = NotificationCompat.Builder(ctx, CH_REQUESTS)
            .setSmallIcon(R.drawable.ic_stat_sudosend)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setAutoCancel(true)
            .setTimeoutAfter(120_000)
            .setContentIntent(openAppIntent(ctx, ACTION_OPEN, id))
            // Accept opens the app: the user should see the verification code.
            .addAction(0, accept, openAppIntent(ctx, ACTION_ACCEPT, id))
            .addAction(0, decline, declineIntent)
            .build()
        post(ctx, idOf(id), n)
    }

    fun info(ctx: Context, id: String, title: String, text: String) {
        val n = NotificationCompat.Builder(ctx, CH_DONE)
            .setSmallIcon(R.drawable.ic_stat_sudosend)
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(true)
            .setContentIntent(openAppIntent(ctx, ACTION_OPEN, id))
            .build()
        post(ctx, idOf(id), n)
    }

    fun cancel(ctx: Context, id: String) {
        NotificationManagerCompat.from(ctx).cancel(idOf(id))
    }

    private fun post(ctx: Context, notificationId: Int, n: android.app.Notification) {
        try {
            NotificationManagerCompat.from(ctx).notify(notificationId, n)
        } catch (e: SecurityException) {
            // Notification permission not granted — the in-app dialog still works.
        }
    }
}

class NotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Ringer.ACTION_STOP) {
            Ringer.stop(context)
            Bridge.emit("onRingStopped", null)
            return
        }
        val id = intent.getStringExtra(Notifications.EXTRA_ID) ?: return
        Notifications.cancel(context, id)
        if (intent.action == Notifications.ACTION_DECLINE) {
            Bridge.emit("onNotificationAction", mapOf("id" to id, "action" to "decline"))
        }
    }
}
