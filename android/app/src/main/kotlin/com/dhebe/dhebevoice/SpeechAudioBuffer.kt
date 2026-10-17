package com.dhebe.dhebevoice

import java.io.File
import java.util.concurrent.CancellationException
import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executor

internal data class SpeechAudioKey(
    val directory: String,
    val text: String,
    val voice: String,
    val language: String,
    val speed: Float,
    val steps: Int = 5,
)

internal data class SpeechPreparation(val message: String, val completed: Int? = null, val total: Int? = null)

/** Start the current segment immediately; generate a bounded rolling window behind it. */
internal class SpeechAudioBuffer(
    private val executor: Executor,
    private val createFile: () -> File,
    private val render: (SpeechAudioKey, File, () -> Boolean, (SpeechPreparation) -> Unit) -> Unit,
    private val cancelRender: () -> Unit,
    private val takePrepared: (SpeechAudioKey) -> File? = { null },
) {
    class Entry(val key: SpeechAudioKey, val file: File) {
        val ready = CompletableFuture<File>()
        @Volatile var cancelled = false
        @Volatile var preparation = SpeechPreparation("Waiting for speech generation")
            private set
        @Volatile var onPreparation: (() -> Unit)? = null

        fun report(value: SpeechPreparation) {
            if (cancelled) return
            preparation = value
            onPreparation?.invoke()
        }
    }

    private var current: Entry? = null
    private var ahead: List<Entry> = emptyList()
    private var running: Entry? = null

    @Synchronized fun lookahead(): Entry? = ahead.firstOrNull()

    @Synchronized fun updateNext(key: SpeechAudioKey, following: SpeechAudioKey? = null): Entry =
        updateNext(listOfNotNull(key, following))

    @Synchronized fun updateNext(upcoming: List<SpeechAudioKey>): Entry {
        validate(upcoming)
        require(upcoming.isNotEmpty())
        val remaining = ahead.toMutableList()
        ahead = upcoming.map { reuseOrEnqueue(remaining, it) }
        remaining.forEach { cancel(it) }
        return ahead.first()
    }

    @Synchronized fun take(key: SpeechAudioKey, next: SpeechAudioKey?, following: SpeechAudioKey? = null): Entry =
        take(key, listOfNotNull(next, following))

    @Synchronized fun take(key: SpeechAudioKey, upcoming: List<SpeechAudioKey>): Entry {
        validate(upcoming)
        val remaining = ahead.toMutableList()
        cancel(current)
        current = reuseOrEnqueue(remaining, key)
        ahead = upcoming.map { reuseOrEnqueue(remaining, it) }
        remaining.forEach { cancel(it) }
        return current!!
    }

    private fun validate(upcoming: List<SpeechAudioKey>) {
        require(upcoming.size <= 8 && upcoming.sumOf { it.text.length } <= 1200)
        require(upcoming.all { it.text.isNotBlank() && it.text.length <= 300 })
    }

    private fun reuseOrEnqueue(remaining: MutableList<Entry>, key: SpeechAudioKey): Entry {
        val index = remaining.indexOfFirst {
            it.key == key && !it.cancelled && !it.ready.isCompletedExceptionally
        }
        return if (index >= 0) remaining.removeAt(index) else enqueue(key)
    }

    @Synchronized fun releaseCurrent() {
        cancel(current)
        current = null
    }

    @Synchronized fun clear() {
        cancel(current)
        ahead.forEach { cancel(it) }
        current = null
        ahead = emptyList()
    }

    private fun cancel(entry: Entry?) {
        if (entry == null) return
        entry.cancelled = true
        entry.onPreparation = null
        // Serialized with running transitions so a late cancel cannot kill the next job.
        if (running === entry) cancelRender() else entry.file.delete()
        entry.ready.completeExceptionally(CancellationException())
    }

    private fun enqueue(key: SpeechAudioKey): Entry {
        val cached = takePrepared(key)
        val entry = Entry(key, cached ?: createFile())
        if (cached != null) {
            entry.report(SpeechPreparation("Opening prepared audio"))
            entry.ready.complete(cached)
            return entry
        }
        executor.execute {
            try {
                synchronized(this) {
                    if (entry.cancelled) throw CancellationException()
                    running = entry
                }
                render(key, entry.file, { entry.cancelled }, entry::report)
                if (entry.cancelled) throw CancellationException()
                entry.ready.complete(entry.file)
            } catch (error: Throwable) {
                entry.file.delete()
                entry.ready.completeExceptionally(error)
            } finally {
                synchronized(this) {
                    if (running === entry) running = null
                    if (entry.cancelled) entry.file.delete()
                }
            }
        }
        return entry
    }
}
