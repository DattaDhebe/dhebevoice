package com.dhebe.dhebevoice

import org.junit.Assert.*
import org.junit.Test

class SpeechLatentNoiseTest {
    @Test fun sameVoiceAndLanguageHaveRepeatableVariation() {
        assertArrayEquals(SpeechLatentNoise.create("M2", "en", 4, 100),
            SpeechLatentNoise.create("M2", "en", 4, 100), 0f)
    }

    @Test fun durationDoesNotRerollOtherChannels() {
        val short = SpeechLatentNoise.create("M2", "en", 4, 50)
        val long = SpeechLatentNoise.create("M2", "en", 4, 100)
        for (channel in 0 until 4) {
            assertArrayEquals(short.copyOfRange(channel * 50, (channel + 1) * 50),
                long.copyOfRange(channel * 100, channel * 100 + 50), 0f)
        }
        assertFalse(short.copyOfRange(0, 50).contentEquals(short.copyOfRange(50, 100)))
    }

    @Test fun differentNarratorsAndLanguagesHaveSeparateVariation() {
        val baseline = SpeechLatentNoise.create("M2", "en", 4, 100)
        assertFalse(baseline.contentEquals(SpeechLatentNoise.create("M1", "en", 4, 100)))
        assertFalse(baseline.contentEquals(SpeechLatentNoise.create("M2", "hi", 4, 100)))
    }

    @Test fun samplesRemainFiniteGaussianNoise() {
        val values = SpeechLatentNoise.create("F1", "en", 64, 500)
        assertTrue(values.all { it.isFinite() })
        assertEquals(0.0, values.map { it.toDouble() }.average(), 0.03)
        assertEquals(1.0, values.map { it.toDouble() * it }.average(), 0.04)
    }
}
