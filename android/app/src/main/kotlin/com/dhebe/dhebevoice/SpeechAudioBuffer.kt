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
)

/** One playing segment and one lookahead; never render a whole book into memory. */
internal class SpeechAudioBuffer(
    private val executor: Executor,
    private val createFile: () -> File,
    private val render: (SpeechAudioKey, File, () -> Boolean) -> Unit,
    private val cancelRender: () -> Unit,
) {
    class Entry(val key: SpeechAudioKey, val file: File) {
        val ready = CompletableFuture<File>()
        @Volatile var cancelled = false
    }

    private var current: Entry? = null
    private var ahead: Entry? = null
    private var running: Entry? = null

    @Synchronized fun take(key: SpeechAudioKey, next: SpeechAudioKey?): Entry {
        val reused = ahead?.takeIf {
            it.key == key && !it.cancelled && !it.ready.isCompletedExceptionally
        }
        cancel(current)
        if (ahead !== reused) cancel(ahead)
        current = reused ?: enqueue(key)
        ahead = next?.let { enqueue(it) }
        return current!!
    }

    @Synchronized fun releaseCurrent() {
        cancel(current)
        current = null
    }

    @Synchronized fun clear() {
        cancel(current)
        cancel(ahead)
        current = null
        ahead = null
    }

    private fun cancel(entry: Entry?) {
        if (entry == null) return
        entry.cancelled = true
        // Serialized with running transitions so a late cancel cannot kill the next job.
        if (running === entry) cancelRender() else entry.file.delete()
        entry.ready.completeExceptionally(CancellationException())
    }

    private fun enqueue(key: SpeechAudioKey): Entry {
        val entry = Entry(key, createFile())
        executor.execute {
            try {
                synchronized(this) {
                    if (entry.cancelled) throw CancellationException()
                    running = entry
                }
                render(key, entry.file) { entry.cancelled }
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
