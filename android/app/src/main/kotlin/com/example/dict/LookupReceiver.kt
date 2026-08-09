package com.example.dict

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.RemoteInput
import java.io.File
import java.util.Locale

/**
 * Handles words typed into the notification shade's RemoteInput. Queries the
 * offline dictionary SQLite directly (no Flutter engine needed) and posts the
 * result as a new notification.
 */
class LookupReceiver : BroadcastReceiver() {
    companion object {
        const val EXTRA_QUERY = "query"
        private const val RESULT_CHANNEL_ID = "quick_lookup_result"
        private const val RESULT_NOTIFICATION_ID = 1002
    }

    override fun onReceive(context: Context, intent: Intent) {
        val query = readRemoteInput(intent) ?: return
        val result = queryDict(context, query)
        postResult(context, query, result)
    }

    private fun readRemoteInput(intent: Intent): String? =
        RemoteInput.getResultsFromIntent(intent)
            ?.getCharSequence(QuickLookupNotifications.REMOTE_INPUT_KEY)
            ?.toString()
            ?.trim()
            ?.takeIf { it.isNotEmpty() }

    private fun queryDict(context: Context, raw: String): String? {
        val dbFile = File(context.filesDir, "dict.sqlite")
        if (!dbFile.exists()) return null

        val isCjk = raw.any { it.code in 0x4E00..0x9FFF }
        var db: SQLiteDatabase? = null
        return try {
            db = SQLiteDatabase.openDatabase(
                dbFile.absolutePath, null, SQLiteDatabase.OPEN_READONLY
            )
            if (isCjk) {
                db.rawQuery(
                    """
                    SELECT w.word, w.phonetic, w.translation
                    FROM zh_index z JOIN words w ON w.word = z.word
                    WHERE z.seg = ? COLLATE NOCASE
                    GROUP BY w.word
                    ORDER BY CASE WHEN w.translation LIKE ? THEN 0 ELSE 1 END,
                             CASE WHEN w.frq > 0 THEN w.frq ELSE 1000000 END
                    LIMIT 1
                    """.trimIndent(),
                    arrayOf(raw, "%$raw%")
                )
            } else {
                db.rawQuery(
                    """
                    SELECT word, phonetic, translation FROM words
                    WHERE word = ? COLLATE NOCASE LIMIT 1
                    """.trimIndent(),
                    arrayOf(raw)
                )
            }.use { cursor ->
                if (cursor.moveToFirst()) {
                    val word = cursor.getString(0)
                    val phonetic = cursor.getString(1)
                    val translation = cursor.getString(2)
                    val head = if (phonetic.isNullOrEmpty()) word else "$word [$phonetic]"
                    val body = translation
                        ?.replace('\n', ' ')
                        ?.take(160)
                        ?: ""
                    "$head\n$body".trim()
                } else null
            }
        } catch (_: Exception) {
            null
        } finally {
            db?.close()
        }
    }

    private fun postResult(context: Context, query: String, result: String?) {
        ensureChannel(context)
        val content = if (result == null) {
            "未找到 \"$query\"，点击在词典中搜索"
        } else result

        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(Intent.EXTRA_TEXT, query)
        }
        val openPending = android.app.PendingIntent.getActivity(
            context,
            1,
            openIntent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                android.app.PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, RESULT_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("查词结果")
            .setContentText(content)
            .setStyle(NotificationCompat.BigTextStyle().bigText(content))
            .setContentIntent(openPending)
            .setAutoCancel(true)
            .build()
        NotificationManagerCompat.from(context).notify(RESULT_NOTIFICATION_ID, notification)
    }

    private fun ensureChannel(context: Context) {
        val manager = context.getSystemService(android.app.NotificationManager::class.java)
        val channel = android.app.NotificationChannel(
            RESULT_CHANNEL_ID,
            "查词结果",
            android.app.NotificationManager.IMPORTANCE_HIGH
        ).apply { description = "通知栏查词的查询结果" }
        manager.createNotificationChannel(channel)
    }
}
