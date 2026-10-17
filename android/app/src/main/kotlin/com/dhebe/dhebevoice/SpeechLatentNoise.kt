package com.dhebe.dhebevoice

import java.util.Random

/** Keep the generative variation stable instead of rerolling every paragraph. */
internal object SpeechLatentNoise {
    fun create(voice: String, language: String, channels: Int, length: Int): FloatArray {
        require(channels > 0 && length > 0)
        val seed = 42L + 31L * voice.hashCode() + language.hashCode()
        return FloatArray(Math.multiplyExact(channels, length)).also { samples ->
            for (channel in 0 until channels) {
                // Independent channel streams retain their prefix when audio duration changes.
                val random = Random(seed + channel * 1_000_003L)
                for (frame in 0 until length) {
                    samples[channel * length + frame] = random.nextGaussian().toFloat()
                }
            }
        }
    }
}
