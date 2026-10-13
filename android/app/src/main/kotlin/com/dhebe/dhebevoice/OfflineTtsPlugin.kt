package com.dhebe.dhebevoice

import android.content.Context
import android.app.ActivityManager
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
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
    @Volatile private var synthesizer: SupertonicSynthesizer? = null
    @Volatile private var requestId: Int? = null
    private var directory: String? = null
    private var player: MediaPlayer? = null
    private var paused = false
    private var audioFile: File? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var detached = false
    private var prepared = false
    private var playbackVolume = 1f
    private val heartbeat = object : Runnable {
        override fun run() {
            val id = requestId
            if (id != null && prepared && player?.isPlaying == true) event(id, "activity")
            if (id != null && !detached) main.postDelayed(this, 2000)
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.dhebe.dhebevoice/offline_tts")
        channel.setMethodCallHandler(this)
    }

    private fun event(id: Int, name: String, message: String? = null) {
        if (!detached && requestId == id) channel.invokeMethod("event", mapOf("id" to id, "type" to name, "message" to message))
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "speak" -> {
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
                    val path = call.argument<String>("directory")!!
                    val root = File(path).canonicalFile
                    require(root.path.startsWith(File(context.applicationInfo.dataDir).canonicalPath + File.separator))
                    val text = call.argument<String>("text")!!
                    val voice = call.argument<String>("voice")!!
                    val language = call.argument<String>("language")!!
                    val id = call.argument<Int>("id")!!
                    val speed = call.argument<Double>("speed")!!.toFloat()
                    val volume = call.argument<Double>("volume")!!.toFloat().coerceIn(0f, 1f)
                    require(text.length <= 300 && text.isNotBlank())
                    stop()
                    requestId = id
                    paused = false
                    playbackVolume = volume
                    main.post(heartbeat)
                    wakeLock = (context.getSystemService(Context.POWER_SERVICE) as PowerManager)
                        .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "DhebeVoice:OfflineTts").apply { acquire(240000) }
                    val output = File.createTempFile("narration-", ".wav", context.cacheDir)
                    audioFile = output
                    worker.execute {
                        try {
                            if (requestId != id) { output.delete(); return@execute }
                            if (directory != root.path || synthesizer == null) {
                                synthesizer?.close()
                                synthesizer = null
                                synthesizer = SupertonicSynthesizer(root)
                                directory = root.path
                            }
                            synthesizer!!.synthesize(text, language, voice, speed, output) { requestId != id }
                            main.post {
                                if (requestId != id || detached) { output.delete(); return@post }
                                try {
                                    player = MediaPlayer().apply {
                                        setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                                        setWakeMode(context, PowerManager.PARTIAL_WAKE_LOCK)
                                        setVolume(playbackVolume, playbackVolume)
                                        setDataSource(output.path)
                                        setOnCompletionListener {
                                            finish(id, "completed")
                                        }
                                        setOnErrorListener { _, _, _ ->
                                            finish(id, "error", "Offline audio could not play. Try Android voices.")
                                            true
                                        }
                                        setOnPreparedListener {
                                            prepared = true
                                            if (requestId == id && !paused) { start(); event(id, "started") }
                                            releaseWakeLock()
                                        }
                                        prepareAsync()
                                    }
                                } catch (_: Exception) {
                                    finish(id, "error", "Offline audio could not start.")
                                }
                            }
                        } catch (_: Throwable) {
                            output.delete()
                            main.post {
                                if (requestId == id) {
                                    finish(id, "error", "Offline voice could not generate audio. Use shorter text or switch to Android voices.")
                                }
                            }
                        }
                    }
                    result.success(true)
                }
                "pause" -> { paused = true; player?.let { if (it.isPlaying) it.pause() }; result.success(null) }
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
        } catch (_: Exception) { result.error("offline_tts", "Offline voice operation failed.", null) }
    }

    private fun finish(id: Int, type: String, message: String? = null) {
        if (requestId != id) return
        event(id, type, message)
        requestId = null
        main.removeCallbacks(heartbeat)
        releasePlayer()
    }
    private fun releaseWakeLock() { wakeLock?.let { if (it.isHeld) it.release() }; wakeLock = null }
    private fun releasePlayer() {
        prepared = false
        player?.release(); player = null
        audioFile?.delete(); audioFile = null
        releaseWakeLock()
    }
    private fun stop() {
        requestId = null
        main.removeCallbacks(heartbeat)
        synthesizer?.cancel()
        releasePlayer()
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detached = true
        stop()
        channel.setMethodCallHandler(null)
        worker.execute { synthesizer?.close(); synthesizer = null }
        worker.shutdown()
    }
}
