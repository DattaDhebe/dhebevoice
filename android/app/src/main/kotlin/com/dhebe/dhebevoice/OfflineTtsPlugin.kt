package com.dhebe.dhebevoice

import android.content.Context
import android.app.ActivityManager
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.content.pm.ApplicationInfo
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** Owned by the Flutter engine, not the Activity, so background audio survives. */
class OfflineTtsPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private lateinit var audioBuffer: SpeechAudioBuffer
    private lateinit var chapterCache: SpeechChapterCache
    @Volatile private var synthesizer: SupertonicSynthesizer? = null
    @Volatile private var requestId: Int? = null
    private var directory: String? = null
    private var player: MediaPlayer? = null
    private var paused = false
    private var wakeLock: PowerManager.WakeLock? = null
    private var detached = false
    private var prepared = false
    private var playbackVolume = 1f
    private var lastCompletedAt: Long? = null
    private var activeAudio: SpeechAudioBuffer.Entry? = null
    private val preparedAhead = PreparedSpeechAudio<MediaPlayer> { it.release() }
    private var lookaheadPreparation: SpeechAudioBuffer.Entry? = null
    private val heartbeat = object : Runnable {
        override fun run() {
            val id = requestId
            if (id != null && prepared && player?.isPlaying == true) event(id, "activity")
            if (id != null && !detached) main.postDelayed(this, 2000)
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        val cache = File(context.cacheDir, "prepared-narration").apply { mkdirs() }
        worker.execute { cache.listFiles()?.filter { it.isFile && it.name.startsWith("speech-") }?.forEach { it.delete() } }
        val streamCache = File(context.cacheDir, "streamed-narration").apply { mkdirs() }
        worker.execute { streamCache.listFiles()?.filter { it.isFile && it.name.startsWith("speech-") }?.forEach { it.delete() } }
        chapterCache = SpeechChapterCache(worker,
            { File.createTempFile("speech-", ".wav", cache) }, ::renderSpeech, { synthesizer?.cancel() })
        audioBuffer = SpeechAudioBuffer(
            executor = worker,
            createFile = { File.createTempFile("speech-", ".wav", streamCache) },
            render = ::renderSpeech,
            cancelRender = { synthesizer?.cancel() },
            takePrepared = chapterCache::take,
        )
        channel = MethodChannel(binding.binaryMessenger, "com.dhebe.dhebevoice/offline_tts")
        channel.setMethodCallHandler(this)
    }

    private fun renderSpeech(key: SpeechAudioKey, output: File, cancelled: () -> Boolean, report: (SpeechPreparation) -> Unit) {
        val startedAt = SystemClock.elapsedRealtime()
        if (directory != key.directory || synthesizer == null) {
            report(SpeechPreparation("Loading neural voice model"))
            synthesizer?.close()
            synthesizer = null
            synthesizer = SupertonicSynthesizer(File(key.directory))
            directory = key.directory
        }
        synthesizer!!.synthesize(key.text, key.language, key.voice, key.speed, output, key.steps,
            onProgress = { completed, total, message -> report(SpeechPreparation(message, completed, total)) },
            isCancelled = cancelled)
        debugTiming("render chars=${key.text.length} steps=${key.steps} elapsedMs=${SystemClock.elapsedRealtime() - startedAt}")
    }

    private fun event(id: Int, name: String, message: String? = null, completed: Int? = null, total: Int? = null,
        segmentsDone: Int? = null, segmentsTotal: Int? = null) {
        if (!detached && requestId == id) channel.invokeMethod("event", mapOf("id" to id, "type" to name,
            "message" to message, "completed" to completed, "total" to total,
            "segmentsDone" to segmentsDone, "segmentsTotal" to segmentsTotal))
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "speak", "prepareChapter" -> {
                    if (!android.os.Process.is64Bit()) {
                        result.error("unsupported", "Offline neural voices require a 64-bit device. Android TTS is still available.", null)
                        return
                    }
                    if (synthesizer == null) {
                        val memory = ActivityManager.MemoryInfo()
                        (context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(memory)
                        if (memory.lowMemory || memory.availMem < 700L * 1024 * 1024) {
                            result.error("low_memory", "Not enough free memory for offline neural speech. Close other apps or use Android voices.", null)
                            return
                        }
                    }
                    val key = speechKey(call)
                    val id = call.argument<Int>("id")!!
                    if (call.method == "prepareChapter") {
                        val texts = call.argument<List<String>>("texts")!!
                        require(texts.isNotEmpty() && texts.all { it.isNotBlank() && it.length <= 300 })
                        stop()
                        requestId = id
                        wakeLock = (context.getSystemService(Context.POWER_SERVICE) as PowerManager)
                            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "DhebeVoice:PrepareChapter").apply { acquire(1800000) }
                        chapterCache.prepare(texts.map { key.copy(text = it) }) { done, count, stage ->
                            main.post { event(id, "preparing", stage.message, stage.completed, stage.total, done, count) }
                        }.whenComplete { _, error ->
                            main.post {
                                if (requestId != id || detached) return@post
                                if (error != null) {
                                    finish(id, "error", error.cause?.message ?: error.message ?: "Chapter preparation failed.")
                                } else {
                                    event(id, "chapterPrepared")
                                    requestId = null
                                    releaseWakeLock()
                                }
                            }
                        }
                        result.success(true)
                        return
                    }
                    val volume = call.argument<Double>("volume")!!.toFloat().coerceIn(0f, 1f)
                    val next = lookaheadKey(call, key, "nextText")
                    val following = lookaheadKey(call, key, "followingText")
                    require(following == null || next != null)
                    val upcoming = upcomingKeys(call, key, listOfNotNull(next, following))
                    // Unlike Stop, a normal segment handoff retains matching lookahead audio.
                    requestId = null
                    main.removeCallbacks(heartbeat)
                    releasePlayer()
                    val audio = audioBuffer.take(key, upcoming)
                    val warmedPlayer = preparedAhead.take(audio)
                    debugTiming("request=$id chars=${key.text.length} rendered=${audio.ready.isDone} decoderReady=${warmedPlayer != null}")
                    requestId = id
                    activeAudio = audio
                    audio.onPreparation = {
                        main.post { reportPreparation(id, audio) }
                    }
                    paused = false
                    playbackVolume = volume
                    reportPreparation(id, audio)
                    main.post(heartbeat)
                    wakeLock = (context.getSystemService(Context.POWER_SERVICE) as PowerManager)
                        .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "DhebeVoice:OfflineTts").apply { acquire(240000) }
                    if (warmedPlayer != null) {
                        activatePlayer(id, warmedPlayer, alreadyPrepared = true)
                    } else audio.ready.whenComplete { output, error ->
                        main.post {
                            if (requestId != id || detached || audio.cancelled) return@post
                            if (error != null) {
                                finish(id, "error", "Offline voice could not generate audio. Use shorter text or switch to Android voices.")
                            } else {
                                playAudio(id, output)
                            }
                        }
                    }
                    prepareLookahead()
                    result.success(true)
                }
                "preload" -> {
                    if (requestId != null && requestId == call.argument<Int>("id")) {
                        val key = speechKey(call)
                        val upcoming = upcomingKeys(call, key, listOfNotNull(key, lookaheadKey(call, key, "nextText")))
                        require(upcoming.firstOrNull() == key)
                        audioBuffer.updateNext(upcoming)
                        prepareLookahead()
                    }
                    result.success(null)
                }
                "pause" -> { paused = true; player?.let { if (prepared && it.isPlaying) it.pause() }; result.success(null) }
                "resume" -> {
                    val id = requestId
                    paused = false
                    if (id != null && prepared) player?.let { it.start(); event(id, "started") }
                    result.success(id != null)
                }
                "stop" -> { stop(); result.success(null) }
                "volume" -> {
                    playbackVolume = call.argument<Double>("value")!!.toFloat().coerceIn(0f, 1f)
                    player?.setVolume(playbackVolume, playbackVolume)
                    result.success(null)
                }
                "unload" -> {
                    stop()
                    worker.execute {
                        synthesizer?.close(); synthesizer = null; directory = null
                        main.post { result.success(null) }
                    }
                }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            if (call.method == "speak" || call.method == "prepareChapter") stop()
            result.error("offline_tts", "Offline voice operation failed. The chapter may be too large; turn off chapter preparation to stream it instead.", null)
        }
    }

    private fun speechKey(call: MethodCall): SpeechAudioKey {
        val root = File(call.argument<String>("directory")!!).canonicalFile
        require(root.path.startsWith(File(context.applicationInfo.dataDir).canonicalPath + File.separator))
        val text = call.argument<String>("text")!!
        val voice = call.argument<String>("voice")!!
        val language = call.argument<String>("language")!!
        val speed = call.argument<Double>("speed")!!.toFloat()
        val steps = call.argument<Int>("steps") ?: 5
        require(text.isNotBlank() && text.length <= 300)
        require(Regex("[FM][1-5]").matches(voice) && language in SupertonicSynthesizer.languages)
        require(speed.isFinite() && speed in 0.5f..2f)
        require(steps == 3 || steps == 5)
        return SpeechAudioKey(root.path, text, voice, language, speed, steps)
    }

    private fun lookaheadKey(call: MethodCall, key: SpeechAudioKey, argument: String): SpeechAudioKey? {
        val text = call.argument<String>(argument) ?: return null
        require(text.isNotBlank() && text.length <= 300)
        return key.copy(text = text)
    }

    private fun upcomingKeys(call: MethodCall, key: SpeechAudioKey, fallback: List<SpeechAudioKey>): List<SpeechAudioKey> {
        val texts = call.argument<List<String>>("upcomingTexts") ?: return fallback
        require(texts.size <= 8 && texts.sumOf { it.length } <= 1200)
        require(texts.all { it.isNotBlank() && it.length <= 300 })
        return texts.map { key.copy(text = it) }
    }

    private fun createPlayer(output: File): MediaPlayer {
        val audio = MediaPlayer()
        try {
            return audio.apply {
                setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                setWakeMode(context, PowerManager.PARTIAL_WAKE_LOCK)
                setVolume(playbackVolume, playbackVolume)
                setDataSource(output.path)
            }
        } catch (error: Exception) {
            audio.release()
            throw error
        }
    }

    private fun playAudio(id: Int, output: File) {
        try {
            activatePlayer(id, createPlayer(output), alreadyPrepared = false)
        } catch (_: Exception) {
            finish(id, "error", "Offline audio could not start.")
        }
    }

    private fun activatePlayer(id: Int, audio: MediaPlayer, alreadyPrepared: Boolean) {
        player = audio
        prepared = alreadyPrepared
        audio.setVolume(playbackVolume, playbackVolume)
        audio.setOnCompletionListener { if (player === it) finish(id, "completed") }
        audio.setOnErrorListener { failed, _, _ ->
            if (player === failed) finish(id, "error", "Offline audio could not play. Try Android voices.")
            true
        }
        audio.setOnPreparedListener {
            if (requestId != id || player !== it) return@setOnPreparedListener
            prepared = true
            if (!paused) { it.start(); speechStarted(id, it) }
            releaseWakeLock()
        }
        if (alreadyPrepared) {
            if (!paused) { audio.start(); speechStarted(id, audio) }
            releaseWakeLock()
        } else audio.prepareAsync()
    }

    private fun speechStarted(id: Int, audio: MediaPlayer) {
        val gap = lastCompletedAt?.let { SystemClock.elapsedRealtime() - it }
        debugTiming("started request=$id durationMs=${audio.duration} gapMs=${gap ?: -1}")
        lastCompletedAt = null
        event(id, "started")
    }

    private fun reportPreparation(id: Int, audio: SpeechAudioBuffer.Entry) {
        if (requestId != id || activeAudio !== audio || audio.cancelled || prepared) return
        val progress = audio.preparation
        event(id, "preparing", progress.message, progress.completed, progress.total)
    }

    private fun debugTiming(message: String) {
        if (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            // Timing only: never log the reader's text or model-file paths.
            Log.d("DhebeVoiceTTS", message)
        }
    }

    private fun prepareLookahead() {
        val entry = audioBuffer.lookahead()
        if (entry === lookaheadPreparation) return
        clearLookahead()
        if (entry == null) return
        lookaheadPreparation = entry
        entry.ready.whenComplete { output, error ->
            main.post {
                if (detached || entry.cancelled || lookaheadPreparation !== entry ||
                    audioBuffer.lookahead() !== entry || error != null) return@post
                try {
                    val audio = createPlayer(output)
                    val slot = preparedAhead.stage(entry, audio)
                    audio.setOnPreparedListener { preparedAhead.markReady(slot) }
                    audio.setOnErrorListener { _, _, _ ->
                        if (preparedAhead.owns(slot)) clearLookahead()
                        true
                    }
                    audio.prepareAsync()
                } catch (_: Exception) {
                    // Optional warmup must never stop the currently playing paragraph.
                    clearLookahead()
                }
            }
        }
    }

    private fun clearLookahead() {
        lookaheadPreparation = null
        preparedAhead.clear()
    }

    private fun finish(id: Int, type: String, message: String? = null) {
        if (requestId != id) return
        if (type == "completed") lastCompletedAt = SystemClock.elapsedRealtime()
        event(id, type, message)
        requestId = null
        main.removeCallbacks(heartbeat)
        releasePlayer()
        if (type == "completed") audioBuffer.releaseCurrent() else {
            clearLookahead()
            audioBuffer.clear()
            chapterCache.clear()
        }
    }
    private fun releaseWakeLock() { wakeLock?.let { if (it.isHeld) it.release() }; wakeLock = null }
    private fun releasePlayer() {
        activeAudio?.onPreparation = null
        activeAudio = null
        prepared = false
        player?.release(); player = null
        releaseWakeLock()
    }
    private fun stop() {
        lastCompletedAt = null
        requestId = null
        main.removeCallbacks(heartbeat)
        releasePlayer()
        clearLookahead()
        audioBuffer.clear()
        chapterCache.clear()
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detached = true
        stop()
        channel.setMethodCallHandler(null)
        worker.execute { synthesizer?.close(); synthesizer = null }
        worker.shutdown()
    }
}
