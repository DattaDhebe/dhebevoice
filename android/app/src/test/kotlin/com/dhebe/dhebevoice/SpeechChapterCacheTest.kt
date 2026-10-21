package com.dhebe.dhebevoice

import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class SpeechChapterCacheTest {
    private class ManualExecutor : Executor {
        val tasks = ArrayDeque<Runnable>()
        override fun execute(command: Runnable) { tasks.add(command) }
        fun runAll() { while (tasks.isNotEmpty()) tasks.removeFirst().run() }
    }
    private val first = SpeechAudioKey("models", "First.", "M2", "en", 1f)
    private val second = first.copy(text = "Second.")

    @Test fun chapterPreparesFullyBeforeItCanBeTakenAndTransfersFilesToPlayback() {
        val executor = ManualExecutor()
        val files = mutableListOf<File>()
        val progress = mutableListOf<Int>()
        val cache = SpeechChapterCache(executor,
            { File.createTempFile("chapter-test", ".wav").also { files.add(it) } },
            { key, file, _, report -> report(SpeechPreparation("Refining", 2, 9)); file.writeText(key.text) }, {})
        val buffer = SpeechAudioBuffer(executor, { error("Prepared speech must be reused") },
            { _, _, _, _ -> error("Prepared speech must not render again") }, {}, cache::take)
        try {
            val ready = cache.prepare(listOf(first, second, first)) { done, _, _ -> progress.add(done) }
            assertNull(cache.take(first))
            executor.runAll()
            assertTrue(ready.isDone && !ready.isCompletedExceptionally)
            assertEquals(listOf(0, 1, 1, 2, 2, 3), progress)
            val playing = buffer.take(first, second, first)
            assertTrue(playing.ready.isDone)
            assertTrue(buffer.lookahead()!!.ready.isDone)
            cache.clear()
            assertTrue(playing.file.exists())
            buffer.releaseCurrent()
            assertTrue(buffer.take(second, first).ready.isDone)
            assertEquals(2, files.count { it.exists() })
        } finally {
            cache.clear()
            buffer.clear()
            files.forEach { assertFalse(it.exists()) }
        }
    }

    @Test fun voiceLanguageRateAndQualityMustMatchPreparedAudioExactly() {
        val executor = ManualExecutor()
        val cache = SpeechChapterCache(executor, { File.createTempFile("chapter-test", ".wav") },
            { key, file, _, _ -> file.writeText(key.text) }, {})
        try {
            cache.prepare(listOf(first)) { _, _, _ -> }
            executor.runAll()
            for (different in listOf(first.copy(voice = "F1"), first.copy(language = "hi"),
                first.copy(speed = 1.5f), first.copy(steps = 3), first.copy(directory = "other"))) {
                assertNull(cache.take(different))
            }
            val audio = cache.take(first)!!
            assertEquals("First.", audio.readText())
            audio.delete()
        } finally { cache.clear() }
    }

    @Test fun stopBeforeWorkStartsNeverRendersOrCreatesAudio() {
        val executor = ManualExecutor()
        val cache = SpeechChapterCache(executor, { error("Cancelled job must not create files") },
            { _, _, _, _ -> error("Cancelled job must not render") }, {})
        val ready = cache.prepare(listOf(first, second)) { _, _, _ -> }
        cache.clear()
        executor.runAll()
        assertTrue(ready.isCompletedExceptionally)
    }

    @Test fun sizeLimitAndRenderErrorsDiscardPartialChaptersAndPermitRetry() {
        val executor = ManualExecutor()
        val files = mutableListOf<File>()
        val cache = SpeechChapterCache(executor,
            { File.createTempFile("chapter-test", ".wav").also { files.add(it) } },
            { key, file, _, _ -> file.writeText(key.text) }, {}, maxBytes = 8, reserveBytes = 0)
        try {
            val tooLarge = cache.prepare(listOf(first, second)) { _, _, _ -> }
            executor.runAll()
            assertTrue(tooLarge.isCompletedExceptionally)
            assertNull(cache.take(first))
            assertTrue(files.none { it.exists() })
            val retry = cache.prepare(listOf(first)) { _, _, _ -> }
            executor.runAll()
            assertFalse(retry.isCompletedExceptionally)
            val file = cache.take(first)!!
            file.delete()
            assertTrue(files.none { it.exists() })
        } finally { cache.clear() }
    }

    @Test fun invalidChaptersAreRejectedBeforeAnyWorkIsQueued() {
        val executor = ManualExecutor()
        val cache = SpeechChapterCache(executor, { error("No files expected") },
            { _, _, _, _ -> error("No inference expected") }, {})
        for (keys in listOf(emptyList(), List(401) { first }, List(200) { first.copy(text = "a".repeat(300)) })) {
            try { cache.prepare(keys) { _, _, _ -> }; fail("Expected a chapter limit") }
            catch (_: IllegalArgumentException) { }
        }
        assertTrue(executor.tasks.isEmpty())
    }

    @Test fun missingTemporaryDirectoryReportsAnErrorBeforeRendering() {
        val executor = ManualExecutor()
        val cache = SpeechChapterCache(executor, { File("chapter-without-parent.wav") },
            { _, _, _, _ -> error("Invalid storage must not start inference") }, {})
        val ready = cache.prepare(listOf(first)) { _, _, _ -> }
        executor.runAll()
        assertTrue(ready.isCompletedExceptionally)
        try { ready.join(); fail("Expected a storage error") }
        catch (error: java.util.concurrent.CompletionException) {
            assertTrue(error.cause is IllegalStateException)
            assertTrue(error.cause!!.message!!.contains("Temporary audio storage"))
        }
        assertNull(cache.take(first))
        cache.clear()
    }

    @Test fun stopCancelsActiveChapterInferenceAndDeletesLateOutput() {
        val executor = Executors.newSingleThreadExecutor()
        val started = CountDownLatch(1)
        val cancelled = CountDownLatch(1)
        val files = mutableListOf<File>()
        val cache = SpeechChapterCache(executor,
            { File.createTempFile("chapter-test", ".wav").also { files.add(it) } },
            { _, file, isCancelled, _ ->
                started.countDown()
                assertTrue(cancelled.await(3, TimeUnit.SECONDS))
                assertTrue(isCancelled())
                file.writeText("Late result")
            }, { cancelled.countDown() })
        try {
            val ready = cache.prepare(listOf(first, second)) { _, _, _ -> }
            assertTrue(started.await(3, TimeUnit.SECONDS))
            cache.clear()
            assertTrue(ready.isCompletedExceptionally)
        } finally {
            cancelled.countDown()
            cache.clear()
            executor.shutdown()
            assertTrue(executor.awaitTermination(3, TimeUnit.SECONDS))
            assertTrue(files.none { it.exists() })
        }
    }
}
