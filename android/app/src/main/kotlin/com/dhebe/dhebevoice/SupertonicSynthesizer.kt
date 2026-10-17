package com.dhebe.dhebevoice

// Inference adapted from Supertone's MIT-licensed Java example.
// See assets/licenses/supertonic-code.txt. Model weights use OpenRAIL-M.
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.nio.FloatBuffer
import java.nio.LongBuffer
import java.text.Normalizer
import kotlin.math.ceil

class SupertonicSynthesizer(private val directory: File, intraOpThreads: Int = 2,
    useXnnpack: Boolean = false) : AutoCloseable {
    private val env = OrtEnvironment.getEnvironment()
    private val sessions = mutableListOf<OrtSession>()
    private val sessionOptions = OrtSession.SessionOptions()
    private val config = JSONObject(File(directory, "onnx/tts.json").readText())
    private val indexer = JSONArray(File(directory, "onnx/unicode_indexer.json").readText())
    private val sampleRate = config.getJSONObject("ae").getInt("sample_rate")
    private var closed = false
    @Volatile private var activeRun: OrtSession.RunOptions? = null
    private data class StyleValues(val shape: LongArray, val values: FloatArray)
    private var cachedVoice: String? = null
    private var cachedStyle: Map<String, StyleValues> = emptyMap()

    private fun voiceStyle(voice: String): Map<String, StyleValues> {
        if (cachedVoice == voice) return cachedStyle
        val style = JSONObject(File(directory, "voice_styles/$voice.json").readText())
        val parsed = listOf("style_dp", "style_ttl").associateWith { name ->
            val item = style.getJSONObject(name)
            val dims = item.getJSONArray("dims")
            val values = mutableListOf<Float>()
            fun flatten(array: JSONArray) {
                for (i in 0 until array.length()) {
                    val value = array.get(i)
                    if (value is JSONArray) flatten(value) else values.add((value as Number).toFloat())
                }
            }
            flatten(item.getJSONArray("data"))
            StyleValues(LongArray(dims.length()) { dims.getLong(it) }, values.toFloatArray())
        }
        cachedVoice = voice
        cachedStyle = parsed
        return parsed
    }

    init {
        try {
            require(intraOpThreads in 1..4)
            sessionOptions.setIntraOpNumThreads(if (useXnnpack) 1 else intraOpThreads)
            sessionOptions.setInterOpNumThreads(1)
            sessionOptions.setMemoryPatternOptimization(false)
            if (useXnnpack) {
                sessionOptions.addConfigEntry("session.intra_op.allow_spinning", "0")
                sessionOptions.addXnnpack(mapOf("intra_op_num_threads" to intraOpThreads.toString()))
            }
            for (name in listOf("duration_predictor", "text_encoder", "vector_estimator", "vocoder")) {
                sessions.add(env.createSession(File(directory, "onnx/$name.onnx").path, sessionOptions))
            }
        } catch (error: Throwable) {
            close()
            throw error
        }
    }

    @Synchronized fun cancel() { activeRun?.setTerminate(true) }

    fun synthesize(text: String, language: String, voice: String, speed: Float, output: File, steps: Int = 5,
        onProgress: (Int, Int, String) -> Unit = { _, _, _ -> }, isCancelled: () -> Boolean) {
        require(Regex("[FM][1-5]").matches(voice))
        require(language in languages)
        require(text.length <= 300)
        require(steps == 3 || steps == 5)
        val owned = mutableListOf<AutoCloseable>()
        fun <T : AutoCloseable> own(item: T): T { owned.add(item); return item }
        fun checkCancelled() { check(!isCancelled()) { "Cancelled" } }
        val options = own(OrtSession.RunOptions())
        synchronized(this) { activeRun = options }
        try {
            checkCancelled()
            onProgress(0, steps + 4, "Preparing text")
            val normalized = normalize(text, language)
            val points = normalized.codePoints().toArray()
            val ids = LongArray(points.size) { i ->
                val code = points[i]
                require(code < indexer.length()) { "Unsupported character" }
                indexer.getLong(code).also { require(it >= 0) { "Unsupported character" } }
            }
            fun tensor(values: FloatArray, shape: LongArray) =
                OnnxTensor.createTensor(env, FloatBuffer.wrap(values), shape)
            val textIds = own(OnnxTensor.createTensor(env, LongBuffer.wrap(ids), longArrayOf(1, ids.size.toLong())))
            val textMask = own(tensor(FloatArray(ids.size) { 1f }, longArrayOf(1, 1, ids.size.toLong())))
            val style = voiceStyle(voice)
            fun styleTensor(name: String): OnnxTensor {
                val item = style.getValue(name)
                return own(tensor(item.values, item.shape))
            }
            val dpStyle = styleTensor("style_dp")
            val ttlStyle = styleTensor("style_ttl")
            val duration = sessions[0].run(mapOf("text_ids" to textIds, "style_dp" to dpStyle, "text_mask" to textMask), options).use {
                (it[0] as OnnxTensor).floatBuffer.get(0) / speed.coerceIn(0.5f, 2f)
            }
            require(duration.isFinite() && duration > 0 && duration <= 60) { "Invalid audio duration" }
            checkCancelled()
            onProgress(1, steps + 4, "Encoding text")
            val embedding = own(sessions[1].run(mapOf("text_ids" to textIds, "style_ttl" to ttlStyle, "text_mask" to textMask), options))
            onProgress(2, steps + 4, "Refining voice")
            val compress = config.getJSONObject("ttl").getInt("chunk_compress_factor")
            val dim = config.getJSONObject("ttl").getInt("latent_dim") * compress
            val chunk = config.getJSONObject("ae").getInt("base_chunk_size") * compress
            val length = ceil((duration * sampleRate).toInt().toDouble() / chunk).toInt()
            require(length in 1..1000)
            val shape = longArrayOf(1, dim.toLong(), length.toLong())
            var latent = SpeechLatentNoise.create(voice, language, dim, length)
            val latentMask = own(tensor(FloatArray(length) { 1f }, longArrayOf(1, 1, length.toLong())))
            val total = own(tensor(floatArrayOf(steps.toFloat()), longArrayOf(1)))
            for (step in 0 until steps) {
                checkCancelled()
                tensor(latent, shape).use { noise ->
                    tensor(floatArrayOf(step.toFloat()), longArrayOf(1)).use { current ->
                        sessions[2].run(mapOf(
                            "noisy_latent" to noise, "text_emb" to (embedding[0] as OnnxTensor), "style_ttl" to ttlStyle,
                            "latent_mask" to latentMask, "text_mask" to textMask,
                            "current_step" to current, "total_step" to total
                        ), options).use { result ->
                            val buffer = (result[0] as OnnxTensor).floatBuffer
                            latent = FloatArray(buffer.remaining()).also { buffer.get(it) }
                        }
                    }
                }
                onProgress(step + 3, steps + 4, "Refining voice (${step + 1} of $steps)")
            }
            checkCancelled()
            onProgress(steps + 2, steps + 4, "Creating audio")
            tensor(latent, shape).use { finalLatent ->
                sessions[3].run(mapOf("latent" to finalLatent), options).use { result ->
                    checkCancelled()
                    val samples = (result[0] as OnnxTensor).floatBuffer
                    val count = minOf((duration * sampleRate).toInt(), samples.remaining())
                    require(count > 0)
                    onProgress(steps + 3, steps + 4, "Saving audio")
                    output.writeBytes(SpeechPcm.wav(samples, count, sampleRate))
                    onProgress(steps + 4, steps + 4, "Opening audio")
                }
            }
        } finally {
            synchronized(this) { activeRun = null }
            owned.asReversed().forEach { it.close() }
        }
    }

    override fun close() {
        if (closed) return
        closed = true
        sessions.forEach { it.close() }
        sessions.clear()
        sessionOptions.close()
        cachedVoice = null
        cachedStyle = emptyMap()
    }

    companion object {
        val languages = setOf("en", "ko", "ja", "ar", "bg", "cs", "da", "de", "el", "es", "et", "fi", "fr", "hi", "hr", "hu", "id", "it", "lt", "lv", "nl", "pl", "pt", "ro", "ru", "sk", "sl", "sv", "tr", "uk", "vi")
        fun normalize(source: String, language: String): String {
            var text = Normalizer.normalize(source, Normalizer.Form.NFKD)
            text = text.replace(Regex("[\\x{1F000}-\\x{1FAFF}\\x{2600}-\\x{27BF}]"), "")
                .replace(Regex("[\\u2013\\u2011\\u2014]"), "-")
                .replace(Regex("[\\u201C\\u201D]"), "\"")
                .replace(Regex("[\\u2018\\u2019\\u00B4`]"), "'")
                .replace(Regex("[_\\[\\]|/#\\u2190\\u2192]"), " ")
                .replace(Regex("[\\u2665\\u2606\\u2661\\u00A9\\\\]"), "")
                .replace("@", " at ").replace("e.g.,", "for example, ").replace("i.e.,", "that is, ")
                .replace(Regex("\\s+([,.!?;:'])"), "$1")
                .replace(Regex("\"{2,}"), "\"").replace(Regex("'{2,}"), "'")
                .replace(Regex("\\s+"), " ").trim()
            require(text.isNotEmpty()) { "No readable text" }
            if (text.last() !in ".!?;:,'\")]}\u2026\u3002\u300d\u300f\u3011\u3009\u300b\u203a\u00bb") text += "."
            return "<$language>$text</$language>"
        }
    }
}
