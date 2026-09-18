package com.example.dict

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.graphics.Rect
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.view.MotionEvent
import android.view.View
import android.widget.Button
import android.widget.TextView
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.Locale
import java.util.concurrent.Executors

class ProcessTextDialogActivity : Activity() {

    private var localTts: TextToSpeech? = null
    private var localTtsReady = false
    private var mediaPlayer: MediaPlayer? = null
    private var audioManager: AudioManager? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val audioExecutor = Executors.newSingleThreadExecutor()
    private val audioFocusListener = AudioManager.OnAudioFocusChangeListener { }

    private var lookupWord: String = ""

    private data class DictResult(
        val word: String,
        val phonetic: String?,
        val translation: String?
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.dialog_process_text)

        val rawText = intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
            ?: intent.getStringExtra(Intent.EXTRA_TEXT)
            ?: ""

        val cleaned = sanitizeLookupWord(rawText)
        if (cleaned.isEmpty()) {
            finish()
            return
        }

        lookupWord = cleaned
        initTts()
        initViews(cleaned)
    }

    override fun onDestroy() {
        stopPlayback()
        localTts?.stop()
        localTts?.shutdown()
        localTts = null
        abandonAudioFocus()
        audioExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun sanitizeLookupWord(raw: String): String {
        var t = raw.trim()
        if (t.isEmpty()) return ""

        // Strip surrounding quotes, punctuation and brackets
        t = t.replace(Regex("""^[\s"'“‘(\[{<]+"""), "")
            .replace(Regex("""[\s"'”’)\],.:;!?}>]+$"""), "")

        // CJK text
        val cjk = Regex("""[\u4e00-\u9fff]+""").find(t)
        if (cjk != null) {
            val matched = cjk.value
            return if (matched.length > 4) matched.substring(0, 4) else matched
        }

        // Latin word
        val latin = Regex("""[a-zA-Z]+(?:['’-][a-zA-Z]+)*""").find(t)
        return latin?.value ?: t
    }

    private fun initTts() {
        audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        localTts = TextToSpeech(this) { status ->
            if (status == TextToSpeech.SUCCESS) {
                localTts?.language = Locale.US
                localTtsReady = true
            }
        }
        localTts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {}
            override fun onDone(utteranceId: String?) {
                abandonAudioFocus()
                mainHandler.post {
                    findViewById<Button>(R.id.btnSpeak)?.text = "🔊 发音"
                }
            }
            @Deprecated("Deprecated in Java", ReplaceWith("onError(utteranceId, -1)"))
            override fun onError(utteranceId: String?) {
                abandonAudioFocus()
                mainHandler.post {
                    findViewById<Button>(R.id.btnSpeak)?.text = "🔊 发音"
                }
            }
            override fun onError(utteranceId: String?, errorCode: Int) {
                abandonAudioFocus()
                mainHandler.post {
                    findViewById<Button>(R.id.btnSpeak)?.text = "🔊 发音"
                }
            }
        })
    }

    private fun requestAudioFocus(ducking: Boolean) {
        val am = audioManager ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val focusRequest = AudioFocusRequest.Builder(
                    if (ducking) AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
                    else AudioManager.AUDIOFOCUS_GAIN_TRANSIENT
                )
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .build()
                    )
                    .setOnAudioFocusChangeListener(audioFocusListener)
                    .build()
                am.requestAudioFocus(focusRequest)
            } else {
                @Suppress("DEPRECATION")
                am.requestAudioFocus(
                    audioFocusListener,
                    AudioManager.STREAM_MUSIC,
                    if (ducking) AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
                    else AudioManager.AUDIOFOCUS_GAIN_TRANSIENT
                )
            }
        } catch (_: Exception) {}
    }

    private fun abandonAudioFocus() {
        val am = audioManager ?: return
        try {
            @Suppress("DEPRECATION")
            am.abandonAudioFocus(audioFocusListener)
        } catch (_: Exception) {}
    }

    private fun stopPlayback() {
        try {
            mediaPlayer?.stop()
            mediaPlayer?.release()
        } catch (_: Exception) {}
        mediaPlayer = null
        try {
            localTts?.stop()
        } catch (_: Exception) {}
    }

    private fun getAudioCacheFile(mode: String, accent: String, word: String): File {
        val sanitized = "${mode}_${accent}_${word.lowercase()}"
            .replace(Regex("""[^a-z0-9\u4e00-\u9fff]"""), "_")
        val cacheDir = File(filesDir, "audio")
        if (!cacheDir.exists()) {
            cacheDir.mkdirs()
        }
        return File(cacheDir, "$sanitized.mp3")
    }

    private fun speakWord(word: String, btnSpeak: Button) {
        val trimmed = word.trim()
        if (trimmed.isEmpty()) return

        stopPlayback()
        btnSpeak.text = "🔊 播放中…"

        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val mode = prefs.getString("flutter.tts_mode", "edge") ?: "edge"
        val ducking = prefs.getBoolean("flutter.tts_audio_ducking", true)
        val cacheEnabled = prefs.getBoolean("flutter.tts_cache_enabled", true)

        val isCjk = trimmed.any { it.code in 0x4E00..0x9FFF }
        if (isCjk || mode == "local") {
            speakLocal(trimmed, ducking, btnSpeak)
            return
        }

        audioExecutor.execute {
            val played = when (mode) {
                "youdao" -> {
                    val encoded = URLEncoder.encode(trimmed, "UTF-8")
                    val url = "https://dict.youdao.com/dictvoice?audio=$encoded&type=1"
                    val cacheFile = getAudioCacheFile("youdao", "us", trimmed)
                    playOrDownloadAudio(url, cacheFile, cacheEnabled, ducking, btnSpeak)
                }
                "baidu" -> {
                    val encoded = URLEncoder.encode(trimmed, "UTF-8")
                    val url = "https://fanyi.baidu.com/gettts?lan=en&text=$encoded&spd=3&source=dict"
                    val cacheFile = getAudioCacheFile("baidu", "us", trimmed)
                    playOrDownloadAudio(url, cacheFile, cacheEnabled, ducking, btnSpeak)
                }
                "edge" -> {
                    // If cached by Flutter, play directly
                    val cacheFile = getAudioCacheFile("edge", "us", trimmed)
                    if (cacheFile.exists() && cacheFile.length() > 0) {
                        playAudioFile(cacheFile, ducking, btnSpeak)
                    } else {
                        // Fallback to Youdao if edge audio is not yet cached
                        val encoded = URLEncoder.encode(trimmed, "UTF-8")
                        val url = "https://dict.youdao.com/dictvoice?audio=$encoded&type=1"
                        val youdaoCache = getAudioCacheFile("youdao", "us", trimmed)
                        playOrDownloadAudio(url, youdaoCache, cacheEnabled, ducking, btnSpeak)
                    }
                }
                else -> false
            }

            if (!played) {
                mainHandler.post {
                    speakLocal(trimmed, ducking, btnSpeak)
                }
            }
        }
    }

    private fun playOrDownloadAudio(
        urlStr: String,
        cacheFile: File,
        cacheEnabled: Boolean,
        ducking: Boolean,
        btnSpeak: Button
    ): Boolean {
        if (cacheFile.exists() && cacheFile.length() > 0) {
            return playAudioFile(cacheFile, ducking, btnSpeak)
        }

        val targetFile = if (cacheEnabled) cacheFile else File.createTempFile("tts_tmp", ".mp3", cacheDir)
        return try {
            val url = URL(urlStr)
            val conn = (url.openConnection() as HttpURLConnection).apply {
                connectTimeout = 4000
                readTimeout = 4000
                requestMethod = "GET"
                setRequestProperty("User-Agent", "Mozilla/5.0 PureDict/1.1.0")
            }
            conn.connect()
            if (conn.responseCode == 200) {
                conn.inputStream.use { input ->
                    FileOutputStream(targetFile).use { output ->
                        input.copyTo(output)
                    }
                }
                if (targetFile.exists() && targetFile.length() > 0) {
                    playAudioFile(targetFile, ducking, btnSpeak)
                } else {
                    targetFile.delete()
                    false
                }
            } else {
                false
            }
        } catch (_: Exception) {
            targetFile.delete()
            false
        }
    }

    private fun playAudioFile(file: File, ducking: Boolean, btnSpeak: Button): Boolean {
        return try {
            mainHandler.post {
                stopPlayback()
                val mp = MediaPlayer().apply {
                    setAudioAttributes(
                        AudioAttributes.Builder()
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .build()
                    )
                    setDataSource(file.absolutePath)
                    setOnPreparedListener { player ->
                        requestAudioFocus(ducking)
                        player.start()
                    }
                    setOnCompletionListener {
                        abandonAudioFocus()
                        stopPlayback()
                        btnSpeak.text = "🔊 发音"
                    }
                    setOnErrorListener { _, _, _ ->
                        abandonAudioFocus()
                        stopPlayback()
                        btnSpeak.text = "🔊 发音"
                        true
                    }
                    prepareAsync()
                }
                mediaPlayer = mp
            }
            true
        } catch (_: Exception) {
            mainHandler.post { btnSpeak.text = "🔊 发音" }
            false
        }
    }

    private fun speakLocal(word: String, ducking: Boolean, btnSpeak: Button) {
        requestAudioFocus(ducking)
        localTts?.speak(word, TextToSpeech.QUEUE_FLUSH, null, "quick_tts")
        mainHandler.postDelayed({
            btnSpeak.text = "🔊 发音"
        }, 1500)
    }

    private fun initViews(query: String) {
        val tvWord = findViewById<TextView>(R.id.tvWord)
        val tvPhonetic = findViewById<TextView>(R.id.tvPhonetic)
        val tvTranslation = findViewById<TextView>(R.id.tvTranslation)
        val tvStudyStatus = findViewById<TextView>(R.id.tvStudyStatus)
        val btnSpeak = findViewById<Button>(R.id.btnSpeak)
        val btnClose = findViewById<Button>(R.id.btnClose)
        val btnOpenApp = findViewById<Button>(R.id.btnOpenApp)
        val btnRemoveStudy = findViewById<TextView>(R.id.btnRemoveStudy)

        tvWord.text = query

        val result = queryDict(query)
        if (result != null) {
            tvWord.text = result.word
            if (!result.phonetic.isNullOrEmpty()) {
                tvPhonetic.text = "/${result.phonetic}/"
                tvPhonetic.visibility = View.VISIBLE
            } else {
                tvPhonetic.visibility = View.GONE
            }
            tvTranslation.text = formatTranslation(result.translation)
        } else {
            tvPhonetic.visibility = View.GONE
            tvTranslation.text = "词库中未找到此词，点击在完整词典中搜索"
        }

        // Auto-capture into study database if study mode is enabled
        val queryCount = recordStudyIfEnabled(result?.word ?: query)
        if (queryCount != null) {
            tvStudyStatus.text = "已加入背单词 · 查过 $queryCount 次"
            tvStudyStatus.visibility = View.VISIBLE
            btnRemoveStudy.visibility = View.VISIBLE
            btnRemoveStudy.setOnClickListener {
                removeFromStudy(result?.word ?: query)
                tvStudyStatus.text = "已移出生词库"
                btnRemoveStudy.visibility = View.GONE
            }
        } else {
            tvStudyStatus.visibility = View.GONE
            btnRemoveStudy.visibility = View.GONE
        }

        btnSpeak.setOnClickListener {
            val target = result?.word ?: query
            speakWord(target, btnSpeak)
        }

        btnClose.setOnClickListener {
            finish()
        }

        btnOpenApp.setOnClickListener {
            val target = result?.word ?: query
            val openIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra(Intent.EXTRA_TEXT, target)
            }
            startActivity(openIntent)
            finish()
        }
    }

    private fun formatTranslation(raw: String?): String {
        if (raw.isNullOrBlank()) return "暂无释义"
        return raw.replace("\\n", "\n").trim()
    }

    private fun findDbFile(name: String): File? {
        val candidates = listOf(
            File(filesDir, name),
            File(noBackupFilesDir, name),
            File(applicationInfo.dataDir, "app_flutter/$name"),
            File(applicationInfo.dataDir, "files/$name")
        )
        return candidates.firstOrNull { it.exists() }
    }

    private fun queryDict(raw: String): DictResult? {
        val dbFile = findDbFile("dict.sqlite") ?: return null
        val isCjk = raw.any { it.code in 0x4E00..0x9FFF }

        var db: SQLiteDatabase? = null
        return try {
            db = SQLiteDatabase.openDatabase(
                dbFile.absolutePath, null, SQLiteDatabase.OPEN_READONLY
            )
            val cursor = if (isCjk) {
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
            }

            cursor.use { c ->
                if (c.moveToFirst()) {
                    DictResult(
                        word = c.getString(0) ?: raw,
                        phonetic = c.getString(1),
                        translation = c.getString(2)
                    )
                } else null
            }
        } catch (_: Exception) {
            null
        } finally {
            db?.close()
        }
    }

    private fun recordStudyIfEnabled(word: String): Int? {
        if (!Regex("""^[a-zA-Z]+(?:['’-][a-zA-Z]+)*$""").matches(word)) return null

        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val studyEnabled = prefs.getBoolean("flutter.study_mode_enabled", true)
        if (!studyEnabled) return null

        val dbFile = findDbFile("user.db") ?: return null
        var db: SQLiteDatabase? = null
        return try {
            db = SQLiteDatabase.openDatabase(
                dbFile.absolutePath, null, SQLiteDatabase.OPEN_READWRITE
            )
            val now = System.currentTimeMillis()
            db.execSQL(
                """
                INSERT INTO user_words (word, in_study, query_count, last_queried_at, srs_stage, next_review_at, interval_days, ease_factor, lapse_count, created_at, updated_at, is_deleted)
                VALUES (?, 1, 1, ?, 0, NULL, 0, 2.5, 0, ?, ?, 0)
                ON CONFLICT(word) DO UPDATE SET
                    query_count = query_count + 1,
                    last_queried_at = excluded.last_queried_at,
                    updated_at = excluded.updated_at,
                    in_study = 1,
                    is_deleted = 0
                """.trimIndent(),
                arrayOf<Any?>(word, now, now, now)
            )

            db.execSQL(
                "INSERT INTO search_history (word, queried_at) VALUES (?, ?)",
                arrayOf<Any?>(word, now)
            )

            var count = 1
            db.rawQuery(
                "SELECT query_count FROM user_words WHERE word = ? COLLATE NOCASE LIMIT 1",
                arrayOf(word)
            ).use { c ->
                if (c.moveToFirst()) {
                    count = c.getInt(0)
                }
            }
            count
        } catch (_: Exception) {
            null
        } finally {
            db?.close()
        }
    }

    private fun removeFromStudy(word: String) {
        val dbFile = findDbFile("user.db") ?: return
        var db: SQLiteDatabase? = null
        try {
            db = SQLiteDatabase.openDatabase(
                dbFile.absolutePath, null, SQLiteDatabase.OPEN_READWRITE
            )
            val now = System.currentTimeMillis()
            db.execSQL(
                "UPDATE user_words SET in_study = 0, is_deleted = 1, updated_at = ? WHERE word = ? COLLATE NOCASE",
                arrayOf<Any?>(now, word)
            )
        } catch (_: Exception) {
        } finally {
            db?.close()
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (event.action == MotionEvent.ACTION_DOWN) {
            val card = findViewById<View>(R.id.cardContainer)
            if (card != null) {
                val rect = Rect()
                card.getGlobalVisibleRect(rect)
                if (!rect.contains(event.x.toInt(), event.y.toInt())) {
                    finish()
                    return true
                }
            }
        }
        return super.onTouchEvent(event)
    }
}
