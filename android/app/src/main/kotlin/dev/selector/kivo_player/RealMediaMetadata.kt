package dev.selector.kivo_player

import java.io.DataInputStream
import java.io.IOException
import java.io.InputStream

/** Reads container duration without decoding or trusting Android's MIME type.
 * Chunk lengths include their 10-byte header; all integers are big endian.
 * Bounded to the header so malformed/streaming files cannot stall a scan.
 * Format reference: FFmpeg libavformat/rmdec.c, PROP and MDPR header fields.
 */
internal object RealMediaMetadata {
    fun matches(name: String): Boolean =
        name.endsWith(".rm", ignoreCase = true) || name.endsWith(".rmvb", ignoreCase = true)

    fun durationMs(stream: InputStream): Long {
        val input = DataInputStream(stream)
        var remaining = 1024L * 1024
        var duration = 0L
        try {
            repeat(256) { index ->
                if (remaining < 10) return duration
                val tag = input.readInt()
                val size = input.readInt().toLong() and 0xffffffffL
                val version = input.readUnsignedShort()
                if (index == 0 && tag != 0x2e524d46) return 0 // .RMF
                if (size < 10 || size > remaining) return duration
                remaining -= size
                var payload = size - 10
                if (tag == 0x44415441) return duration // DATA: never read packets
                // PROP: five uint32 fields; MDPR: stream id + six uint32 fields.
                val prefix = when (tag) {
                    0x50524f50 -> 20L // PROP
                    0x4d445052 -> 26L // MDPR
                    else -> -1L
                }
                if ((version == 0 || version == 2) && prefix >= 0 && payload >= prefix + 4) {
                    input.skipNBytesCompat(prefix)
                    val value = input.readInt().toLong() and 0xffffffffL
                    if (value != 0xffffffffL) duration = maxOf(duration, value)
                    payload -= prefix + 4
                }
                input.skipNBytesCompat(payload)
            }
        } catch (_: IOException) {
            // Truncated or inaccessible media stays an ordinary unknown duration.
        }
        return duration
    }

    private fun DataInputStream.skipNBytesCompat(count: Long) {
        var left = count
        while (left > 0) {
            val skipped = skip(left)
            if (skipped > 0) left -= skipped
            else { readByte(); left-- }
        }
    }
}
