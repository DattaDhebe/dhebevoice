package com.dhebe.dhebevoice

import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

class SupertonicSynthesizerTest {
    @Test fun normalizationKeepsNarrationPunctuation() {
        assertEquals("<en>Hello, world.</en>", SupertonicSynthesizer.normalize(" Hello , world ", "en"))
        assertEquals("<en>\"Hello!\"</en>", SupertonicSynthesizer.normalize("\u201cHello!\u201d", "en"))
    }

    @Test fun modelProducesRealAudioAndCancels() {
        val path = System.getenv("DHEBEVOICE_TEST_MODELS")
        assumeTrue(path != null)
        val output = File.createTempFile("dhebevoice-test", ".wav")
        try {
            SupertonicSynthesizer(File(path!!)).use { synth ->
                synth.synthesize("Once upon a time, a traveler found a quiet village.", "en", "F1", 1f, output) { false }
                val audio = output.readBytes()
                assertEquals("RIFF", String(audio.copyOfRange(0, 4)))
                assertTrue(audio.size > 44100)
                assertTrue(audio.drop(44).any { it != 0.toByte() })
                synth.synthesize("The next paragraph uses the same narrator.", "en", "F1", 1f, output) { false }
                assertTrue(output.length() > 44100)
                synth.synthesize("\u0928\u092e\u0938\u094d\u0924\u0947. \u092f\u0939 \u090f\u0915 \u0915\u0939\u093e\u0928\u0940 \u0939\u0948\u0964", "hi", "M3", 1f, output) { false }
                assertTrue(output.length() > 44100)
                try {
                    synth.synthesize("This must be cancelled.", "en", "M1", 1f, output) { true }
                    fail("Cancelled generation must fail")
                } catch (_: IllegalStateException) { }
            }
        } finally { output.delete() }
    }
}
