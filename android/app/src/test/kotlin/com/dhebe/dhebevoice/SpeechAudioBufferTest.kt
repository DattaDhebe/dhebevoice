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
        fun runNext() { tasks.removeFirst().run() }
        fun runAll() { while (tasks.isNotEmpty()) tasks.removeFirst().run() }
    }

    private val first = SpeechAudioKey("models", "First.", "F1", "en", 1f)
    private val second = first.copy(text = "Second.")
    private val third = first.copy(text = "Third.")

    @Test fun firstAudioIsReadyBeforeBackgroundWindowAndRollingHandoffReusesEveryEntry() {
        val executor = ManualExecutor()
        val files = mutableListOf<File>()
        val renders = mutableListOf<SpeechAudioKey>()
        val buffer = SpeechAudioBuffer(executor, {
            File.createTempFile("buffer-test", ".wav").also { files.add(it) }
        }, { key, file, _, _ -> renders.add(key); file.writeText(key.text) }, {})
        val keys = (1..10).map { first.copy(text = "Paragraph $it.") }
        try {
            val playing = buffer.take(keys[0], keys.subList(1, 9))
            executor.runNext()
            assertTrue(playing.ready.isDone)
            assertFalse(buffer.lookahead()!!.ready.isDone)
            assertEquals(8, executor.tasks.size)
            executor.runAll()
            assertEquals(9, files.count { it.exists() })
            buffer.releaseCurrent()
            val next = buffer.take(keys[1], keys.subList(2, 10))
            assertTrue(next.ready.isDone)
            assertTrue(buffer.lookahead()!!.ready.isDone)
            executor.runAll()
            assertEquals(keys, renders)
            assertEquals(9, files.count { it.exists() })
        } finally {
            buffer.clear()
            files.forEach { assertFalse(it.exists()) }
        }
    }

    @Test fun changingVoiceDiscardsWholeRollingWindowButNotCurrentSpeech() {
        val executor = ManualExecutor()
        val files = mutableListOf<File>()
        val buffer = SpeechAudioBuffer(executor, {
            File.createTempFile("buffer-test", ".wav").also { files.add(it) }
        }, { key, file, _, _ -> file.writeText(key.text) }, {})
        val upcoming = (1..8).map { first.copy(text = "Next $it.") }
        try {
            val playing = buffer.take(first, upcoming)
            executor.runAll()
            val changed = upcoming.map { it.copy(voice = "M2", language = "hi") }
            buffer.updateNext(changed)
            assertFalse(playing.cancelled)
            assertTrue(playing.file.exists())
            assertTrue(files.subList(1, 9).none { it.exists() })
            executor.runAll()
            assertTrue(buffer.take(changed[0], changed.drop(1)).ready.isDone)
        } finally {
            buffer.clear()
            files.forEach { assertFalse(it.exists()) }
        }
    }

    @Test fun oversizedWindowIsRejectedBeforeCancellingCurrentSpeech() {
        val executor = ManualExecutor()
        val buffer = SpeechAudioBuffer(executor, { File.createTempFile("buffer-test", ".wav") },
            { key, file, _, _ -> file.writeText(key.text) }, {})
        try {
            val playing = buffer.take(first, emptyList())
            executor.runAll()
            for (invalid in listOf(List(9) { second }, List(5) { second.copy(text = "a".repeat(300)) })) {
                try { buffer.updateNext(invalid); fail("Expected a window limit") }
                catch (_: IllegalArgumentException) { }
            }
            assertFalse(playing.cancelled)
            assertTrue(playing.file.exists())
            assertTrue(executor.tasks.isEmpty())
        } finally { buffer.clear() }
    }

    @Test fun twoAheadSurviveShortParagraphHandoffsAndStayBounded() {
        val executor = ManualExecutor()
        val files = mutableListOf<File>()
        val renders = mutableListOf<SpeechAudioKey>()
        val buffer = SpeechAudioBuffer(executor, {
            File.createTempFile("buffer-test", ".wav").also { files.add(it) }
        }, { key, file, _, _ -> renders.add(key); file.writeText(key.text) }, {})
        try {
            buffer.take(first, second, third)
            executor.runAll()
            assertEquals(listOf(first, second, third), renders)
            assertEquals(3, files.count { it.exists() })
            buffer.releaseCurrent()
            val fourth = first.copy(text = "Fourth.")
            val short = buffer.take(second, third, fourth)
            assertTrue(short.ready.isDone)
            assertTrue(buffer.lookahead()!!.ready.isDone)
            executor.runAll()
            assertEquals(3, files.count { it.exists() })
            buffer.releaseCurrent()
            assertTrue(buffer.take(third, fourth).ready.isDone)
            executor.runAll()
            assertEquals(listOf(first, second, third, fourth), renders)
        } finally {
            buffer.clear()
            files.forEach { assertFalse(it.exists()) }
        }
    }

    @Test fun voiceChangeInvalidatesBothAheadEntriesWithoutCancellingCurrentAudio() {
        val executor = ManualExecutor()
        val files = mutableListOf<File>()
        val buffer = SpeechAudioBuffer(executor, {
            File.createTempFile("buffer-test", ".wav").also { files.add(it) }
        }, { key, file, _, _ -> file.writeText(key.text) }, {})
        try {
            val active = buffer.take(first, second, third)
            executor.runAll()
            val old = buffer.lookahead()!!
            val changed = second.copy(voice = "M3", language = "hi")
            buffer.updateNext(changed, third.copy(voice = "M3", language = "hi"))
            assertFalse(active.cancelled)
            assertTrue(active.file.exists())
            assertTrue(old.cancelled)
            assertFalse(files[2].exists())
            executor.runAll()
            assertEquals(3, files.count { it.exists() })
            assertTrue(buffer.take(changed, null).ready.isDone)
        } finally {
            buffer.clear()
            files.forEach { assertFalse(it.exists()) }
        }
    }

    @Test fun repeatedTextUsesSeparateEntriesSoReleasingCurrentCannotDeleteFutureAudio() {
        val executor = ManualExecutor()
        val buffer = SpeechAudioBuffer(executor, { File.createTempFile("buffer-test", ".wav") },
            { key, file, _, _ -> file.writeText(key.text) }, {})
        try {
            val active = buffer.take(first, first, first)
            executor.runAll()
            val next = buffer.lookahead()!!
            assertNotSame(active, next)
            buffer.releaseCurrent()
            assertTrue(next.file.exists())
            assertSame(next, buffer.take(first, first))
            assertNotSame(next, buffer.lookahead())
            buffer.releaseCurrent()
            assertTrue(buffer.take(first, null).file.exists())
        } finally { buffer.clear() }
    }

    @Test fun cachedLookaheadKeepsPreparationAndCancelledEntriesStopReporting() {
        val executor = ManualExecutor()
        val buffer = SpeechAudioBuffer(executor, { File.createTempFile("buffer-test", ".wav") },
            { _, file, _, report -> report(SpeechPreparation("Refining voice", 2, 7)); file.writeText("audio") }, {})
        try {
            val active = buffer.take(first, second)
            var notifications = 0
            active.onPreparation = { notifications++ }
            executor.runAll()
            assertEquals(1, notifications)
            val ahead = buffer.lookahead()!!
            assertEquals(SpeechPreparation("Refining voice", 2, 7), ahead.preparation)
            assertSame(ahead, buffer.take(second, null))
            buffer.clear()
            ahead.onPreparation = { notifications++ }
            ahead.report(SpeechPreparation("Late progress", 7, 7))
            assertEquals(1, notifications)
        } finally { buffer.clear() }
    }

    @Test fun liveVoiceChangeOnlyReplacesLookaheadAndKeepsCurrentAudio() {
        val executor = ManualExecutor()
        val renders = mutableListOf<SpeechAudioKey>()
        val buffer = SpeechAudioBuffer(executor, { File.createTempFile("buffer-test", ".wav") },
            { key, output, _, _ -> renders.add(key); output.writeText(key.text) }, {})
        try {
            val active = buffer.take(first, second)
            executor.runAll()
            val old = buffer.lookahead()!!
            val changed = second.copy(voice = "M3", language = "hi")
            val next = buffer.updateNext(changed)
            assertFalse(active.cancelled)
            assertTrue(active.file.exists())
            assertTrue(old.cancelled)
            assertFalse(old.file.exists())
            assertSame(next, buffer.updateNext(changed))
            executor.runAll()
            assertSame(next, buffer.take(changed, null))
            assertEquals(listOf(first, second, changed), renders)
        } finally { buffer.clear() }
    }

    @Test fun nextSegmentIsReusedAndOnlyOneLookaheadIsKept() {
        val executor = ManualExecutor()
        val files = mutableListOf<File>()
        val renders = mutableListOf<SpeechAudioKey>()
        val buffer = SpeechAudioBuffer(executor, {
            File.createTempFile("buffer-test", ".wav").also { files.add(it) }
        }, { key, output, _, _ -> renders.add(key); output.writeText(key.text) }, {})
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
            { key, file, _, _ -> renders.add(key); file.writeText(key.text) }, {})
        try {
            buffer.take(first, second)
            val pending = buffer.take(second, third)
            assertFalse(pending.ready.isDone)
            executor.runAll()
            assertEquals(listOf(second, third), renders)
            assertTrue(pending.ready.isDone)
        } finally { buffer.clear() }
    }

    @Test fun changedVoiceLanguageSpeedStepsOrModelsCannotReuseStaleAudio() {
        for (changed in listOf(second.copy(voice = "M3"), second.copy(language = "hi"),
            second.copy(speed = 1.5f), second.copy(steps = 3), second.copy(directory = "other-models"))) {
            val executor = ManualExecutor()
            val renders = mutableListOf<SpeechAudioKey>()
            val buffer = SpeechAudioBuffer(executor, { File.createTempFile("buffer-test", ".wav") },
                { key, file, _, _ -> renders.add(key); file.writeText(key.text) }, {})
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
        }, { _, _, _, _ -> fail("Stopped jobs must not render") }, {})
        val active = buffer.take(first, (1..8).map { second.copy(text = "Next $it.") })
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
            { key, file, _, _ ->
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
        }, { _, file, isCancelled, _ ->
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
