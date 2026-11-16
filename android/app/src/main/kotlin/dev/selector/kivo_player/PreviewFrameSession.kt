package dev.selector.kivo_player

/** Decoder ownership, serialized by MainActivity's frame executor. */
internal interface PreviewFrameReader {
    fun frameAt(ms: Long): ByteArray?
    fun close()
}

internal class PreviewFrameSession(private val open: (String) -> PreviewFrameReader) {
    private var path: String? = null
    private var reader: PreviewFrameReader? = null

    fun prepare(source: String) {
        if (path == source) return
        release()
        // Playback must get first use of the hardware decoder. Merely opening
        // Kivo's player must never warm a competing MediaMetadataRetriever.
        path = source
    }

    fun frameAt(ms: Long): ByteArray? {
        val source = path ?: return null
        val current = reader ?: open(source).also { reader = it }
        return current.frameAt(ms)
    }

    /** Drop decoder resources after scrubbing, retaining the selected source. */
    fun suspend() {
        val previous = reader
        reader = null
        previous?.close()
    }

    fun release() {
        path = null
        suspend()
    }
}
