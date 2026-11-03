package dev.selector.kivo_player

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import org.junit.Assert.*
import org.junit.Test

class RealMediaMetadataTest {
    private fun chunk(tag: String, payload: ByteArray, version: Int = 0): ByteArray =
        ByteArrayOutputStream().also { bytes ->
            DataOutputStream(bytes).use {
                it.writeBytes(tag); it.writeInt(payload.size + 10)
                it.writeShort(version); it.write(payload)
            }
        }.toByteArray()

    private fun metadata(tag: String, prefix: Int, duration: Long, version: Int = 0): ByteArray =
        chunk(tag, ByteArrayOutputStream().also { bytes ->
            DataOutputStream(bytes).use {
                it.write(ByteArray(prefix)); it.writeInt(duration.toInt())
            }
        }.toByteArray(), version)

    private val header = chunk(".RMF", ByteArray(8))
    private fun duration(vararg chunks: ByteArray): Long = RealMediaMetadata.durationMs(
        ByteArrayInputStream(header + chunks.fold(byteArrayOf()) { a, b -> a + b }))

    @Test fun readsPropDurationInMilliseconds() {
        assertEquals(123456L, duration(metadata("PROP", 20, 123456)))
    }

    @Test fun readsMdprDurationAfterPrerollAndTakesLongestStream() {
        assertEquals(90000L, duration(metadata("PROP", 20, 0),
            metadata("MDPR", 26, 90000), metadata("MDPR", 26, 80000)))
    }

    @Test fun supportsVersionTwoAndUnsignedDurations() {
        assertEquals(3000000000L, duration(metadata("PROP", 20, 3000000000L, 2)))
        assertEquals(0L, duration(metadata("PROP", 20, 0xffffffffL)))
    }

    @Test fun skipsUnknownChunksAndStopsBeforeMediaPackets() {
        assertEquals(42000L, duration(chunk("CONT", ByteArray(75)),
            metadata("PROP", 20, 42000), chunk("DATA", byteArrayOf()),
            metadata("PROP", 20, 99000)))
    }

    @Test fun rejectsMalformedTruncatedAndNonRealMediaFiles() {
        assertEquals(0L, RealMediaMetadata.durationMs(ByteArrayInputStream(ByteArray(100))))
        assertEquals(0L, duration(metadata("PROP", 20, 12345).copyOf(32)))
        assertEquals(0L, duration("PROP".toByteArray() + byteArrayOf(0x7f, -1, -1, -1, 0, 0)))
        assertEquals(0L, duration("PROP".toByteArray() + ByteArray(6)))
    }

    @Test fun recognizesOnlyRealMediaExtensionsWithoutCaseSensitivity() {
        assertTrue(RealMediaMetadata.matches("video.RM"))
        assertTrue(RealMediaMetadata.matches("video.RmVb"))
        assertFalse(RealMediaMetadata.matches("video.mp4"))
        assertFalse(RealMediaMetadata.matches("video.rm.bak"))
    }
}
