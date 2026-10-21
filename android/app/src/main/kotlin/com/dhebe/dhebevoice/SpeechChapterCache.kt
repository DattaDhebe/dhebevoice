package com.dhebe.dhebevoice

import java.io.File
import java.util.concurrent.CancellationException
import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executor

/** Disk-backed chapter audio. Only one inference runs and no whole chapter enters RAM. */
internal class SpeechChapterCache(
    private val executor: Executor,
    private val createFile: () -> File,
    private val render: (SpeechAudioKey, File, () -> Boolean, (SpeechPreparation) -> Unit) -> Unit,
    private val cancelRender: () -> Unit,
    private val maxBytes: Long = 256L * 1024 * 1024,
    private val reserveBytes: Long = 64L * 1024 * 1024,
) {
    private class Job {
        val ready = CompletableFuture<Unit>()
        val files = mutableListOf<Pair<SpeechAudioKey, File>>()
        @Volatile var cancelled = false
        var running = false
    }
    private var job: Job? = null

    @Synchronized fun prepare(
        keys: List<SpeechAudioKey>,
        report: (Int, Int, SpeechPreparation) -> Unit,
    ): CompletableFuture<Unit> {
        require(keys.isNotEmpty() && keys.size <= 400 && keys.sumOf { it.text.length } <= 50_000) {
            "This chapter is too large to prepare at once. Choose a shorter section or turn off chapter preparation."
        }
        clear()
        val next = Job()
        job = next
        executor.execute {
            var output: File? = null
            try {
                var bytes = 0L
                keys.forEachIndexed { index, key ->
                    synchronized(this) {
                        if (next.cancelled) throw CancellationException()
                        next.running = true
                    }
                    val file = createFile()
                    output = file
                    val parent = checkNotNull(file.parentFile) {
                        "Temporary audio storage is unavailable. Please try again."
                    }
                    check(parent.usableSpace >= reserveBytes) {
                        "Not enough storage to prepare this chapter. Free space or turn off chapter preparation."
                    }
                    render(key, file, { next.cancelled }) { stage ->
                        if (!next.cancelled) report(index, keys.size, stage)
                    }
                    bytes += file.length()
                    check(bytes <= maxBytes && parent.usableSpace >= reserveBytes) {
                        "Chapter audio exceeds the temporary storage limit. Choose a shorter section or turn off chapter preparation."
                    }
                    synchronized(this) {
                        if (next.cancelled) throw CancellationException()
                        next.files.add(key to file)
                        output = null
                        next.running = false
                    }
                    report(index + 1, keys.size, SpeechPreparation("Preparing chapter"))
                }
                synchronized(this) {
                    if (next.cancelled) throw CancellationException()
                    next.ready.complete(Unit)
                }
            } catch (error: Throwable) {
                synchronized(this) {
                    next.cancelled = true
                    next.files.forEach { it.second.delete() }
                    next.files.clear()
                    next.ready.completeExceptionally(error)
                }
            } finally {
                output?.delete()
                synchronized(this) { next.running = false }
            }
        }
        return next.ready
    }

    @Synchronized fun take(key: SpeechAudioKey): File? {
        val current = job ?: return null
        if (current.cancelled || !current.ready.isDone || current.ready.isCompletedExceptionally) return null
        val index = current.files.indexOfFirst { it.first == key }
        if (index < 0) return null
        return current.files.removeAt(index).second.takeIf { it.exists() }
    }

    @Synchronized fun clear() {
        val previous = job ?: return
        job = null
        previous.cancelled = true
        if (previous.running) cancelRender()
        previous.files.forEach { it.second.delete() }
        previous.files.clear()
        previous.ready.completeExceptionally(CancellationException())
    }
}
