package com.dhebe.dhebevoice

import org.junit.Assert.*
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

class SpeechPcmTest {
    @Test fun trimsExcessSilenceButRetainsConsonantMargins() {
        val samples = FloatArray(1000) { if (it in 200..799) .25f else 0f }
        assertEquals(120..939, SpeechPcm.audibleRange(FloatBuffer.wrap(samples), samples.size, 1000))
    }

    @Test fun internalPausesAndNarratorAmplitudeAreNotNormalizedAway() {
        val samples = FloatArray(1000) {
            when (it) {
                in 200..299 -> .1f
                in 700..799 -> .2f
                else -> 0f
            }
        }
        val wav = ByteBuffer.wrap(SpeechPcm.wav(FloatBuffer.wrap(samples), samples.size, 1000))
            .order(ByteOrder.LITTLE_ENDIAN)
        assertEquals(820 * 2, wav.getInt(40))
        assertEquals((.1f * 32767).toInt().toShort(), wav.getShort(44 + 80 * 2))
        assertEquals(0.toShort(), wav.getShort(44 + 400 * 2))
        assertEquals((.2f * 32767).toInt().toShort(), wav.getShort(44 + 580 * 2))
    }

    @Test fun quietSpeechIsKeptAndSamplesWithoutExtraSilenceStayUnchanged() {
        val quiet = FloatArray(300) { .00015f }
        assertEquals(0..299, SpeechPcm.audibleRange(FloatBuffer.wrap(quiet), quiet.size, 1000))
        val silence = FloatArray(300)
        assertEquals(0..299, SpeechPcm.audibleRange(FloatBuffer.wrap(silence), silence.size, 1000))
    }

    @Test fun respectsBufferOffsetsAndWritesAValidMonoWavWithoutMovingTheInput() {
        val input = FloatBuffer.wrap(floatArrayOf(0f, 0f, .1f, -.2f))
        input.position(2)
        val bytes = SpeechPcm.wav(input, 2, 44100)
        val wav = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        assertEquals(2, input.position())
        assertEquals("RIFF", String(bytes.copyOfRange(0, 4)))
        assertEquals(44100, wav.getInt(24))
        assertEquals(4, wav.getInt(40))
        assertEquals((-.2f * 32767).toInt().toShort(), wav.getShort(46))
    }
}
