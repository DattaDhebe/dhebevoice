package com.dhebe.dhebevoice

/** A prepared decoder for the single lookahead entry, never an autoplay queue. */
internal class PreparedSpeechAudio<T>(private val release: (T) -> Unit) {
    class Slot<T>(val entry: SpeechAudioBuffer.Entry, val player: T) {
        var ready = false
    }

    private var slot: Slot<T>? = null

    fun stage(entry: SpeechAudioBuffer.Entry, player: T): Slot<T> {
        clear()
        return Slot(entry, player).also { slot = it }
    }

    fun owns(candidate: Slot<T>): Boolean = slot === candidate && !candidate.entry.cancelled

    fun markReady(candidate: Slot<T>) {
        if (owns(candidate)) candidate.ready = true
    }

    fun take(entry: SpeechAudioBuffer.Entry): T? {
        val candidate = slot ?: return null
        slot = null
        if (candidate.entry === entry && candidate.ready && !entry.cancelled) return candidate.player
        release(candidate.player)
        return null
    }

    fun clear() {
        val previous = slot
        slot = null
        previous?.let { release(it.player) }
    }
}
