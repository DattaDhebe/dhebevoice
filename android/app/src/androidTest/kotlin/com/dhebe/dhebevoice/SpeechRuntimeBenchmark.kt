package com.dhebe.dhebevoice

import android.app.Activity
import android.app.Instrumentation
import android.content.pm.ApplicationInfo
import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Manually invoked native benchmark; never packaged in the reader APK. */
class SpeechRuntimeBenchmark : Instrumentation() {
    private var configurations = listOf(2, 4, 2, 4)
    private var provider = "cpu"

    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        arguments?.getString("threads")?.let { value ->
            configurations = value.split(",").map { it.toInt() }
        }
        provider = arguments?.getString("provider") ?: "cpu"
        start()
    }

    override fun onStart() {
        val result = Bundle()
        var output: File? = null
        try {
            check(targetContext.packageName == "com.dhebe.dhebevoice.test" &&
                targetContext.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
                "Benchmark is restricted to DhebeVoice Test."
            }
            require(configurations.size in 1..6 && configurations.all { it in 1..4 })
            require(provider in setOf("cpu", "xnnpack"))
            val models = File(targetContext.filesDir, "voices/supertonic-3")
            check(File(models, "onnx/vocoder.onnx").isFile) { "Install the verified voice pack first." }
            output = File.createTempFile("speech-benchmark-", ".wav", targetContext.cacheDir)
            val rows = JSONArray()
            val texts = listOf(
                "The traveler rested beside the river.",
                "When morning arrived, the traveler followed the quiet river through the forest. " +
                    "Beyond the trees, a small village appeared in the warm light, and the long journey finally felt worthwhile."
            )
            for (threads in configurations) {
                val loadStarted = SystemClock.elapsedRealtime()
                SupertonicSynthesizer(models, threads, provider == "xnnpack").use { synth ->
                    val loadMs = SystemClock.elapsedRealtime() - loadStarted
                    synth.synthesize("The morning was calm.", "en", "M2", 1f, output) { false }
                    for (text in texts) {
                        val started = SystemClock.elapsedRealtime()
                        val stages = JSONObject()
                        synth.synthesize(text, "en", "M2", 1f, output,
                            onProgress = { _, _, stage -> stages.put(stage, SystemClock.elapsedRealtime() - started) }) { false }
                        val elapsed = SystemClock.elapsedRealtime() - started
                        val header = ByteBuffer.wrap(output.readBytes(), 0, 44).order(ByteOrder.LITTLE_ENDIAN)
                        val durationMs = header.getInt(40).toLong() * 1000 / header.getInt(28)
                        val row = JSONObject().put("provider", provider).put("threads", threads).put("chars", text.length)
                            .put("loadMs", loadMs).put("elapsedMs", elapsed).put("audioMs", durationMs)
                            .put("rtf", elapsed.toDouble() / durationMs).put("stagesMs", stages)
                        rows.put(row)
                        Log.i("DhebeVoiceBench", row.toString())
                    }
                }
            }
            val report = JSONObject().put("steps", 5).put("speed", 1).put("voice", "M2").put("runs", rows)
            File(targetContext.cacheDir, "speech-runtime-benchmark-$provider.json").writeText(report.toString(2))
            result.putString("results", report.toString())
            finish(Activity.RESULT_OK, result)
        } catch (error: Throwable) {
            result.putString("error", error.toString())
            Log.e("DhebeVoiceBench", "Benchmark failed", error)
            finish(Activity.RESULT_CANCELED, result)
        } finally {
            output?.delete()
        }
    }
}
