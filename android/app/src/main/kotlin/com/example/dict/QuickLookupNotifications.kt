package com.example.dict

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.RemoteInput

/**
 * Renders a persistent notification with an inline RemoteInput field so users
 * can type a word straight from the notification shade. The lookup itself runs
 * in [LookupReceiver] (native SQLite query) and posts the result as a new
 * notification - no Flutter engine or Activity is launched for the query.
 */
object QuickLookupNotifications {
    const val CHANNEL_ID = "quick_lookup"
    const val NOTIFICATION_ID = 1001
    const val REMOTE_INPUT_KEY = "lookup_word"

    fun ensureChannel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            "快捷查词",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "在通知栏直接输入单词快速查词"
        }
        manager.createNotificationChannel(channel)
    }

    fun show(context: Context) {
        ensureChannel(context)

        // RemoteInput requires a mutable PendingIntent so the system can inject
        // the typed text back into the intent.
        val lookupIntent = Intent(context, LookupReceiver::class.java)
        val lookupPending = PendingIntent.getBroadcast(
            context,
            0,
            lookupIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )

        val openAppIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openAppPending = PendingIntent.getActivity(
            context,
            1,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val remoteInput = RemoteInput.Builder(REMOTE_INPUT_KEY)
            .setLabel("输入要查询的单词")
            .build()

        val action = NotificationCompat.Action.Builder(
            R.mipmap.ic_launcher,
            "查词",
            lookupPending
        )
            .addRemoteInput(remoteInput)
            .build()

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("词典")
            .setContentText("在下方输入框输入单词，快速查词")
            .addAction(action)
            .setOngoing(true)
            .setContentIntent(openAppPending)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()

        NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
    }

    fun hide(context: Context) {
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
    }
}
