package dev.selector.kivo_player.update

import java.io.BufferedInputStream
import java.io.DataInputStream
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.RandomAccessFile
import java.security.MessageDigest
import java.util.zip.GZIPInputStream

/** Bounded, streaming KIVODLT1 decoder. It never loads either APK into memory. */
object DeltaPatch {
    const val MAX_APK_BYTES = 512L * 1024 * 1024
    const val MAX_PATCH_BYTES = 256L * 1024 * 1024
    private const val MAX_OPERATIONS = 1_000_000
    private const val BUFFER_SIZE = 64 * 1024

    fun sha256(file: File, cancelled: () -> Boolean = { false }): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(BUFFER_SIZE)
            while (true) {
                checkCancelled(cancelled)
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return hex(digest.digest())
    }

    fun apply(
        base: File,
        patch: File,
        output: File,
        baseSize: Long,
        targetSize: Long,
        baseSha256: String,
        targetSha256: String,
        cancelled: () -> Boolean = { false },
    ) {
        requireSize(baseSize, MAX_APK_BYTES)
        requireSize(targetSize, MAX_APK_BYTES)
        requireSize(patch.length(), MAX_PATCH_BYTES)
        require(base.canonicalFile != output.canonicalFile) { "Output replaces base" }
        require(patch.canonicalFile != output.canonicalFile) { "Output replaces patch" }
        if (base.length() != baseSize || sha256(base, cancelled) != baseSha256) {
            throw IOException("Installed APK does not match patch base")
        }
        val digest = MessageDigest.getInstance("SHA-256")
        try {
            DataInputStream(GZIPInputStream(BufferedInputStream(patch.inputStream()))).use { input ->
                val magic = ByteArray(8).also(input::readFully)
                if (!magic.contentEquals("KIVODLT1".toByteArray(Charsets.US_ASCII)) ||
                    input.readLong() != baseSize || input.readLong() != targetSize ||
                    hex(ByteArray(32).also(input::readFully)) != baseSha256 ||
                    hex(ByteArray(32).also(input::readFully)) != targetSha256
                ) throw IOException("Patch header mismatch")
                RandomAccessFile(base, "r").use { source ->
                    FileOutputStream(output).use { destination ->
                        val buffer = ByteArray(BUFFER_SIZE)
                        var written = 0L
                        var operations = 0
                        while (true) {
                            checkCancelled(cancelled)
                            val opcode = input.readUnsignedByte()
                            if (opcode == 0) {
                                if (written != targetSize || input.read() != -1) {
                                    throw IOException("Patch output size or trailing data mismatch")
                                }
                                break
                            }
                            if (++operations > MAX_OPERATIONS) throw IOException("Too many patch operations")
                            val offset = if (opcode == 1) input.readLong() else 0L
                            if (opcode != 1 && opcode != 2) throw IOException("Unknown patch operation")
                            val length = input.readLong()
                            if (length <= 0 || length > targetSize - written) {
                                throw IOException("Patch output bounds exceeded")
                            }
                            if (opcode == 1) {
                                if (offset < 0 || length > baseSize || offset > baseSize - length) {
                                    throw IOException("Patch source bounds exceeded")
                                }
                                source.seek(offset)
                            }
                            var remaining = length
                            while (remaining > 0) {
                                checkCancelled(cancelled)
                                val count = minOf(remaining, buffer.size.toLong()).toInt()
                                if (opcode == 1) source.readFully(buffer, 0, count)
                                else input.readFully(buffer, 0, count)
                                destination.write(buffer, 0, count)
                                digest.update(buffer, 0, count)
                                remaining -= count
                            }
                            written += length
                        }
                        if (hex(digest.digest()) != targetSha256) throw IOException("Reconstructed APK hash mismatch")
                        destination.fd.sync()
                    }
                }
            }
        } catch (failure: Exception) {
            output.delete()
            throw failure
        }
    }

    private fun requireSize(size: Long, limit: Long) {
        if (size <= 0 || size > limit) throw IOException("Artifact size exceeds limit")
    }

    private fun checkCancelled(cancelled: () -> Boolean) {
        if (cancelled()) throw IOException("Update cancelled")
    }

    fun hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it) }
}
