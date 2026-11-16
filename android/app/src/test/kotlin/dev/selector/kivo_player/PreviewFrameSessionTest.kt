package dev.selector.kivo_player

import org.junit.Assert.*
import org.junit.Test

class PreviewFrameSessionTest {
    @Test fun openingVideoDoesNotAllocateACompetingThumbnailDecoder() {
        var opened = 0
        var decoded = 0
        val session = PreviewFrameSession {
            opened++
            object : PreviewFrameReader {
                override fun frameAt(ms: Long): ByteArray { decoded++; return byteArrayOf(1) }
                override fun close() { }
            }
        }
        session.prepare("/storage/drive/Aida 11x36.avi")
        assertEquals("Opening playback alone must not grab MediaCodec for a thumbnail", 0, opened)
        assertEquals(0, decoded)
        session.frameAt(42_000)
        assertEquals(1, opened)
        assertEquals("Only the explicitly requested preview is decoded", 1, decoded)
        session.release()
    }
    @Test fun suspendingFreesTheDecoderAndLaterPreviewsReuseTheSource() {
        val opened = mutableListOf<String>()
        var closed = 0
        var decoded = 0
        val session = PreviewFrameSession { path ->
            opened += path
            object : PreviewFrameReader {
                override fun frameAt(ms: Long): ByteArray { decoded++; return byteArrayOf(ms.toByte()) }
                override fun close() { closed++ }
            }
        }
        session.prepare("a")
        session.frameAt(1)
        session.frameAt(2)
        assertEquals(listOf("a"), opened)
        assertEquals(2, decoded)
        session.suspend()
        assertEquals(1, closed)
        session.frameAt(3)
        assertEquals(listOf("a", "a"), opened)
        session.prepare("b")
        assertEquals(2, closed)
        assertEquals(2, opened.size)
        session.frameAt(4)
        assertEquals(listOf("a", "a", "b"), opened)
        session.release()
        assertEquals(3, closed)
        assertNull(session.frameAt(5))
        session.release()
        assertEquals(3, closed)
    }

    @Test fun failedOpenDoesNotPoisonTheNextSource() {
        val session = PreviewFrameSession { path ->
            if (path == "bad") throw IllegalStateException("unsupported format")
            object : PreviewFrameReader {
                override fun frameAt(ms: Long) = byteArrayOf(42)
                override fun close() { }
            }
        }
        session.prepare("bad")
        try { session.frameAt(0); fail("Expected failure") } catch (_: IllegalStateException) { }
        session.prepare("good")
        assertArrayEquals(byteArrayOf(42), session.frameAt(0))
        session.release()
    }

}
