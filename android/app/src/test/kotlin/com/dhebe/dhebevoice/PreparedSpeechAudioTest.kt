package com.dhebe.dhebevoice

import org.junit.Assert.*
import org.junit.Test
import java.io.File

class PreparedSpeechAudioTest {
    private val key = SpeechAudioKey("models", "Next paragraph.", "M3", "en", 1f)
    private fun entry(key: SpeechAudioKey = this.key) = SpeechAudioBuffer.Entry(key, File("unused.wav"))

    @Test fun preparedDecoderIsTransferredOnlyToItsExactAudioEntry() {
        val released = mutableListOf<String>()
        val cache = PreparedSpeechAudio<String> { released.add(it) }
        val next = entry()
        val slot = cache.stage(next, "ready-player")
        cache.markReady(slot)
        assertEquals("ready-player", cache.take(next))
        cache.clear()
        assertTrue(released.isEmpty())
        assertFalse(cache.owns(slot))
    }

    @Test fun incompleteDecoderIsReleasedAndFallsBackToNormalPreparation() {
        val released = mutableListOf<String>()
        val cache = PreparedSpeechAudio<String> { released.add(it) }
        val next = entry()
        val slot = cache.stage(next, "preparing-player")
        assertNull(cache.take(next))
        cache.markReady(slot)
        assertFalse(cache.owns(slot))
        assertEquals(listOf("preparing-player"), released)
    }

    @Test fun changingVoiceLanguageOrFileCannotReuseThePreviousDecoder() {
        for (replacement in listOf(key.copy(voice = "F2"), key.copy(language = "hi"), key)) {
            val released = mutableListOf<String>()
            val cache = PreparedSpeechAudio<String> { released.add(it) }
            val slot = cache.stage(entry(), "old-player")
            cache.markReady(slot)
            assertNull(cache.take(entry(replacement)))
            assertEquals(listOf("old-player"), released)
        }
    }

    @Test fun stopRejectsLatePreparationAndReleasesExactlyOnce() {
        val released = mutableListOf<String>()
        val cache = PreparedSpeechAudio<String> { released.add(it) }
        val next = entry()
        val slot = cache.stage(next, "player")
        cache.clear()
        cache.clear()
        cache.markReady(slot)
        assertNull(cache.take(next))
        assertEquals(listOf("player"), released)
    }

    @Test fun cancelledEntryAndReplacedLookaheadCannotBeClaimed() {
        val released = mutableListOf<String>()
        val cache = PreparedSpeechAudio<String> { released.add(it) }
        val old = entry()
        val slot = cache.stage(old, "old")
        cache.markReady(slot)
        val next = entry(key.copy(text = "Following paragraph."))
        val replacement = cache.stage(next, "new")
        cache.markReady(replacement)
        next.cancelled = true
        assertNull(cache.take(next))
        assertEquals(listOf("old", "new"), released)
    }
}
