package com.dhebe.dhebevoice

import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class SpeechAudioBufferTest {
    private class ManualExecutor : Executor {
        val tasks = ArrayDeque<Runnable>()
        override fun execute(command: Runnable) { tasks.add(command) }
        fun runAll() { while (tasks.isNotEmpty()) tasks.removeFirst().run() }
    }

    private val first = SpeechAudioKey("models", "First.", "F1", "en", 1f)
    private val second = first.copy(text = "Second.")
    private val third = first.copy(text = "Third.")

    @Test fun nextSegmentIsReusedAndOnlyOneLookaheadIsKept() {
        val executor = ManualExecutor()
        val files = mutableListOf<File>()
        val renders = mutableListOf<SpeechAudioKey>()
        val buffer = SpeechAudioBuffer(executor, {
            File.createTempFile("buffer-test", ".wav").also { files.add(it) }
        }, { key, output, _ -> renders.add(key); output.writeText(key.text) }, {})
        try {
            val playing = buffer.take(first, second)
            executor.runAll()
            assertEquals(listOf(first, second), renders)
            buffer.releaseCurrent()
            assertFalse(playing.file.exists())
            val next = buffer.take(second, third)
            assertTrue(next.ready.isDone)
            assertEquals("Second.", next.ready.get().readText())
            executor.runAll()
            assertEquals(listOf(first, second, third), renders)
            assertEquals(2, files.count { it.exists() })
        } finally {
            buffer.clear()
            files.forEach { assertFalse(it.exists()) }
        }
    }

    @Test fun handoffWaitsForPendingLookaheadWithoutRenderingItTwice() {
        val executor = ManualExecutor()
        val renders = mutableListOf<SpeechAudioKey>()
        val buffer = SpeechAudioBuffer(executor, { File.createTempFile("buffer-test", ".wav") },
            { key, file, _ -> renders.add(key); file.writeText(key.text) }, {})
        try {
            buffer.take(first, second)
            val pending = buffer.take(second, third)
            assertFalse(pending.ready.isDone)
            executor.runAll()
            assertEquals(listOf(second, third), renders)
            assertTrue(pending.ready.isDone)
        } finally { buffer.clear() }
    }

    @Test fun changedVoiceLanguageSpeedOrModelsCannotReuseStaleAudio() {
        for (changed in listOf(second.copy(voice = "M3"), second.copy(language = "hi"),
            second.copy(speed = 1.5f), second.copy(directory = "other-models"))) {
            val executor = ManualExecutor()
            val renders = mutableListOf<SpeechAudioKey>()
            val buffer = SpeechAudioBuffer(executor, { File.createTempFile("buffer-test", ".wav") },
                { key, file, _ -> renders.add(key); file.writeText(key.text) }, {})
            try {
                buffer.take(first, second)
                executor.runAll()
                val next = buffer.take(changed, null)
                assertFalse(next.ready.isDone)
                executor.runAll()
                assertEquals(changed, renders.last())
            } finally { buffer.clear() }
        }
    }

    @Test fun stopDropsQueuedGenerationAndDeletesEveryTemporaryFile() {
        val executor = ManualExecutor()
        val files = mutableListOf<File>()
        val buffer = SpeechAudioBuffer(executor, {
            File.createTempFile("buffer-test", ".wav").also { files.add(it) }
        }, { _, _, _ -> fail("Stopped jobs must not render") }, {})
        val active = buffer.take(first, second)
        buffer.clear()
        executor.runAll()
        assertTrue(active.cancelled)
        assertTrue(active.ready.isCompletedExceptionally)
        assertTrue(files.none { it.exists() })
    }

    @Test fun failedLookaheadDoesNotFailCurrentAudioAndCanRetry() {
        val executor = ManualExecutor()
        var failAhead = true
        val buffer = SpeechAudioBuffer(executor, { File.createTempFile("buffer-test", ".wav") },
            { key, file, _ ->
                if (key == second && failAhead) error("generation failed")
                file.writeText(key.text)
            }, {})
        try {
            val active = buffer.take(first, second)
            executor.runAll()
            assertFalse(active.ready.isCompletedExceptionally)
            failAhead = false
            val retry = buffer.take(second, null)
            executor.runAll()
            assertEquals("Second.", retry.ready.get().readText())
        } finally { buffer.clear() }
    }

    @Test fun stopCancelsActiveInferenceAndIgnoresItsLateResult() {
        val executor = Executors.newSingleThreadExecutor()
        val started = CountDownLatch(1)
        val cancelled = CountDownLatch(1)
        val finished = CountDownLatch(1)
        val files = mutableListOf<File>()
        val buffer = SpeechAudioBuffer(executor, {
            File.createTempFile("buffer-test", ".wav").also { files.add(it) }
        }, { _, file, isCancelled ->
            started.countDown()
            assertTrue(cancelled.await(3, TimeUnit.SECONDS))
            assertTrue(isCancelled())
            file.writeText("Late audio")
            finished.countDown()
        }, { cancelled.countDown() })
        try {
            val active = buffer.take(first, second)
            assertTrue(started.await(3, TimeUnit.SECONDS))
            buffer.clear()
            assertTrue(finished.await(3, TimeUnit.SECONDS))
            assertTrue(active.ready.isCompletedExceptionally)
        } finally {
            cancelled.countDown()
            buffer.clear()
            executor.shutdown()
            assertTrue(executor.awaitTermination(3, TimeUnit.SECONDS))
            assertTrue(files.none { it.exists() })
        }
    }
}
