package com.dhebe.dhebevoice

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.abs

internal object SpeechPcm {
    /** Remove only near-silent edges; retain consonant margins and every internal pause. */
    fun audibleRange(samples: FloatBuffer, count: Int, sampleRate: Int): IntRange {
        require(count > 0 && count <= samples.remaining() && sampleRate > 0)
        val offset = samples.position()
        val threshold = 0.0001f
        var first = 0
        while (first < count && abs(samples.get(offset + first)) < threshold) first++
        if (first == count) return 0 until count
        var last = count - 1
        while (last > first && abs(samples.get(offset + last)) < threshold) last--
        return maxOf(0, first - sampleRate * 80 / 1000)..minOf(count - 1, last + sampleRate * 140 / 1000)
    }

    fun wav(samples: FloatBuffer, count: Int, sampleRate: Int): ByteArray {
        val range = audibleRange(samples, count, sampleRate)
        val size = range.last - range.first + 1
        val bytes = ByteBuffer.allocate(44 + size * 2).order(ByteOrder.LITTLE_ENDIAN)
        bytes.put("RIFF".toByteArray()).putInt(36 + size * 2).put("WAVEfmt ".toByteArray())
        bytes.putInt(16).putShort(1).putShort(1).putInt(sampleRate).putInt(sampleRate * 2)
        bytes.putShort(2).putShort(16).put("data".toByteArray()).putInt(size * 2)
        val offset = samples.position()
        for (index in range) {
            val sample = samples.get(offset + index)
            bytes.putShort((if (sample.isFinite()) sample.coerceIn(-1f, 1f) * 32767 else 0f).toInt().toShort())
        }
        return bytes.array()
    }
}
