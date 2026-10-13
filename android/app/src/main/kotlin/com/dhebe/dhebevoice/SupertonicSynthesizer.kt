package com.dhebe.dhebevoice

// Inference adapted from Supertone's MIT-licensed Java example.
// See assets/licenses/supertonic-code.txt. Model weights use OpenRAIL-M.
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.nio.LongBuffer
import java.text.Normalizer
import java.util.Random
import kotlin.math.ceil

class SupertonicSynthesizer(private val directory: File) : AutoCloseable {
    private val env = OrtEnvironment.getEnvironment()
    private val sessions = mutableListOf<OrtSession>()
    private val config = JSONObject(File(directory, "onnx/tts.json").readText())
    private val indexer = JSONArray(File(directory, "onnx/unicode_indexer.json").readText())
    private val sampleRate = config.getJSONObject("ae").getInt("sample_rate")
    @Volatile private var activeRun: OrtSession.RunOptions? = null

    init {
        try {
            OrtSession.SessionOptions().use { options ->
                options.setIntraOpNumThreads(2)
                options.setInterOpNumThreads(1)
                options.setMemoryPatternOptimization(false)
                for (name in listOf("duration_predictor", "text_encoder", "vector_estimator", "vocoder")) {
                    sessions.add(env.createSession(File(directory, "onnx/$name.onnx").path, options))
                }
            }
        } catch (error: Throwable) {
            close()
            throw error
        }
    }

    @Synchronized fun cancel() { activeRun?.setTerminate(true) }

    fun synthesize(text: String, language: String, voice: String, speed: Float, output: File, isCancelled: () -> Boolean) {
        require(Regex("[FM][1-5]").matches(voice))
        require(language in languages)
        require(text.length <= 300)
        val owned = mutableListOf<AutoCloseable>()
        fun <T : AutoCloseable> own(item: T): T { owned.add(item); return item }
        fun checkCancelled() { check(!isCancelled()) { "Cancelled" } }
        val options = own(OrtSession.RunOptions())
        synchronized(this) { activeRun = options }
        try {
            checkCancelled()
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
            val style = JSONObject(File(directory, "voice_styles/$voice.json").readText())
            fun styleTensor(name: String): OnnxTensor {
                val item = style.getJSONObject(name)
                val dims = item.getJSONArray("dims")
                val shape = LongArray(dims.length()) { dims.getLong(it) }
                val values = mutableListOf<Float>()
                fun flatten(a: JSONArray) {
                    for (i in 0 until a.length()) {
                        val v = a.get(i)
                        if (v is JSONArray) flatten(v) else values.add((v as Number).toFloat())
                    }
                }
                flatten(item.getJSONArray("data"))
                return own(tensor(values.toFloatArray(), shape))
            }
            val dpStyle = styleTensor("style_dp")
            val ttlStyle = styleTensor("style_ttl")
            val duration = sessions[0].run(mapOf("text_ids" to textIds, "style_dp" to dpStyle, "text_mask" to textMask), options).use {
                (it[0] as OnnxTensor).floatBuffer.get(0) / speed.coerceIn(0.5f, 2f)
            }
            require(duration.isFinite() && duration > 0 && duration <= 60) { "Invalid audio duration" }
            checkCancelled()
            val embedding = own(sessions[1].run(mapOf("text_ids" to textIds, "style_ttl" to ttlStyle, "text_mask" to textMask), options))
            val compress = config.getJSONObject("ttl").getInt("chunk_compress_factor")
            val dim = config.getJSONObject("ttl").getInt("latent_dim") * compress
            val chunk = config.getJSONObject("ae").getInt("base_chunk_size") * compress
            val length = ceil((duration * sampleRate).toInt().toDouble() / chunk).toInt()
            require(length in 1..1000)
            val shape = longArrayOf(1, dim.toLong(), length.toLong())
            val random = Random()
            var latent = FloatArray(dim * length) { random.nextGaussian().toFloat() }
            val latentMask = own(tensor(FloatArray(length) { 1f }, longArrayOf(1, 1, length.toLong())))
            val total = own(tensor(floatArrayOf(5f), longArrayOf(1)))
            for (step in 0 until 5) {
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
            }
            checkCancelled()
            tensor(latent, shape).use { finalLatent ->
                sessions[3].run(mapOf("latent" to finalLatent), options).use { result ->
                    checkCancelled()
                    val samples = (result[0] as OnnxTensor).floatBuffer
                    val count = minOf((duration * sampleRate).toInt(), samples.remaining())
                    require(count > 0)
                    val bytes = ByteBuffer.allocate(44 + count * 2).order(ByteOrder.LITTLE_ENDIAN)
                    bytes.put("RIFF".toByteArray()).putInt(36 + count * 2).put("WAVEfmt ".toByteArray())
                    bytes.putInt(16).putShort(1).putShort(1).putInt(sampleRate).putInt(sampleRate * 2)
                    bytes.putShort(2).putShort(16).put("data".toByteArray()).putInt(count * 2)
                    repeat(count) { bytes.putShort((samples.get().coerceIn(-1f, 1f) * 32767).toInt().toShort()) }
                    output.writeBytes(bytes.array())
                }
            }
        } finally {
            synchronized(this) { activeRun = null }
            owned.asReversed().forEach { it.close() }
        }
    }

    override fun close() { sessions.forEach { it.close() }; sessions.clear() }

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
