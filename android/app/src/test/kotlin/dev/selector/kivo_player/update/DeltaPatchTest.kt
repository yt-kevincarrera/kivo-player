package dev.selector.kivo_player.update

import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.DataOutputStream
import java.io.File
import java.io.IOException
import java.util.zip.GZIPOutputStream

class DeltaPatchTest {
    @get:Rule val temporary = TemporaryFolder()
    private val baseBytes = "abcdefghijklmnop".toByteArray()
    private val targetBytes = "abcdHELLOmnop".toByteArray()

    private fun patch(
        base: File,
        targetHash: String,
        targetSize: Long = targetBytes.size.toLong(),
        operations: DataOutputStream.() -> Unit,
    ): File {
        val file = temporary.newFile()
        DataOutputStream(GZIPOutputStream(file.outputStream())).use {
            it.writeBytes("KIVODLT1")
            it.writeLong(base.length())
            it.writeLong(targetSize)
            it.write(hexBytes(DeltaPatch.sha256(base)))
            it.write(hexBytes(targetHash))
            it.operations()
        }
        return file
    }

    private fun DataOutputStream.copy(offset: Long, length: Long) {
        writeByte(1); writeLong(offset); writeLong(length)
    }

    private fun DataOutputStream.data(bytes: ByteArray) {
        writeByte(2); writeLong(bytes.size.toLong()); write(bytes)
    }

    private fun fixture(): Pair<File, String> {
        val base = temporary.newFile().apply { writeBytes(baseBytes) }
        val target = temporary.newFile().apply { writeBytes(targetBytes) }
        return base to DeltaPatch.sha256(target)
    }

    private fun decode(base: File, patch: File, targetHash: String, size: Long = targetBytes.size.toLong()): File {
        val output = temporary.newFile()
        DeltaPatch.apply(base, patch, output, baseBytes.size.toLong(), size,
            DeltaPatch.sha256(base), targetHash)
        return output
    }

    @Test fun copiesAndLiteralsReconstructExactly() {
        val (base, hash) = fixture()
        val patch = patch(base, hash) {
            copy(0, 4); data("HELLO".toByteArray()); copy(12, 4); writeByte(0)
        }
        assertArrayEquals(targetBytes, decode(base, patch, hash).readBytes())
    }

    @Test fun rejectsWrongBaseHashAndHeader() {
        val (base, hash) = fixture()
        val patch = patch(base, hash) { data(targetBytes); writeByte(0) }
        assertThrows(IOException::class.java) {
            DeltaPatch.apply(base, patch, temporary.newFile(), base.length(), targetBytes.size.toLong(), "0".repeat(64), hash)
        }
        val damaged = temporary.newFile().apply {
            val body = java.util.zip.GZIPInputStream(patch.inputStream()).readBytes()
            body[0] = 0
            GZIPOutputStream(outputStream()).use { it.write(body) }
        }
        assertThrows(IOException::class.java) { decode(base, damaged, hash) }
    }

    @Test fun rejectsWrongTargetHashAndRemovesPartialOutput() {
        val (base, hash) = fixture()
        val patch = patch(base, hash) { data("a".repeat(targetBytes.size).toByteArray()); writeByte(0) }
        val output = temporary.newFile()
        assertThrows(IOException::class.java) {
            DeltaPatch.apply(base, patch, output, base.length(), targetBytes.size.toLong(), DeltaPatch.sha256(base), hash)
        }
        assertFalse(output.exists())
    }

    @Test fun rejectsCopyOutOfBoundsAndIntegerOverflow() {
        val (base, hash) = fixture()
        for ((offset, length) in listOf(15L to 2L, -1L to 1L, Long.MAX_VALUE to 1L, 0L to Long.MAX_VALUE)) {
            val patch = patch(base, hash) { copy(offset, length); writeByte(0) }
            assertThrows(IOException::class.java) { decode(base, patch, hash) }
        }
    }

    @Test fun rejectsZeroLengthUnknownOperationsAndEarlyEnd() {
        val (base, hash) = fixture()
        val invalid: List<DataOutputStream.() -> Unit> = listOf(
            { copy(0, 0); writeByte(0) },
            { writeByte(2); writeLong(0); writeByte(0) },
            { writeByte(3) },
            { writeByte(0) },
        )
        for (operations in invalid) {
            assertThrows(IOException::class.java) { decode(base, patch(base, hash, operations = operations), hash) }
        }
    }

    @Test fun rejectsTruncatedLiteralAndMissingEnd() {
        val (base, hash) = fixture()
        for (operations in listOf<DataOutputStream.() -> Unit>(
            { writeByte(2); writeLong(targetBytes.size.toLong()); writeByte(1) },
            { data(targetBytes) },
        )) {
            assertThrows(IOException::class.java) { decode(base, patch(base, hash, operations = operations), hash) }
        }
    }

    @Test fun rejectsTrailingDecodedBytesAndDamagedGzip() {
        val (base, hash) = fixture()
        val trailing = patch(base, hash) { data(targetBytes); writeByte(0); writeByte(1) }
        assertThrows(IOException::class.java) { decode(base, trailing, hash) }
        val gzip = patch(base, hash) { data(targetBytes); writeByte(0) }
        val corrupt = temporary.newFile().apply {
            writeBytes(gzip.readBytes().also { it[it.size - 8] = (it[it.size - 8].toInt() xor 1).toByte() })
        }
        assertThrows(IOException::class.java) { decode(base, corrupt, hash) }
    }

    @Test fun rejectsOversizedDeclaredOutputAndCancellation() {
        val (base, hash) = fixture()
        val patch = patch(base, hash) { data(targetBytes); writeByte(0) }
        assertThrows(IOException::class.java) { decode(base, patch, hash, DeltaPatch.MAX_APK_BYTES + 1) }
        assertThrows(IOException::class.java) {
            DeltaPatch.apply(base, patch, temporary.newFile(), base.length(), targetBytes.size.toLong(), DeltaPatch.sha256(base), hash) { true }
        }
    }

    @Test fun operationCountIsBounded() {
        val base = temporary.newFile().apply { writeBytes(byteArrayOf(42)) }
        val target = temporary.newFile().apply { writeBytes(ByteArray(1_000_001) { 42 }) }
        val hash = DeltaPatch.sha256(target)
        val patch = patch(base, hash, target.length()) { repeat(1_000_001) { copy(0, 1) }; writeByte(0) }
        assertThrows(IOException::class.java) {
            DeltaPatch.apply(base, patch, temporary.newFile(), base.length(), target.length(), DeltaPatch.sha256(base), hash)
        }
    }

    @Test fun releasedSignedApksRoundTripWhenFixtureIsAvailable() {
        val manifestPath = System.getenv("KIVO_DELTA_MANIFEST")
        val baseDirectory = System.getenv("KIVO_DELTA_BASE_DIR")
        val targetDirectory = System.getenv("KIVO_DELTA_TARGET_DIR")
        val generatedFixturePaths = listOf(manifestPath, baseDirectory, targetDirectory)
        if (generatedFixturePaths.any { !it.isNullOrBlank() }) {
            assertTrue("Generated release fixture requires manifest, base, and target paths",
                generatedFixturePaths.all { !it.isNullOrBlank() })
            val manifestFile = File(manifestPath!!)
            val manifest = org.json.JSONObject(manifestFile.readText())
            val artifacts = manifest.getJSONArray("artifacts")
            val artifact = (0 until artifacts.length()).map { artifacts.getJSONObject(it) }
                .firstOrNull { it.getJSONArray("patches").length() > 0 }
            assumeTrue("Valid release uses full APKs without useful delta patches", artifact != null)
            val patchDescriptor = artifact!!.getJSONArray("patches").getJSONObject(0)
            val baseSize = patchDescriptor.getLong("fromSize")
            val baseHash = patchDescriptor.getString("fromSha256")
            val base = File(baseDirectory!!).walkTopDown()
                .filter { it.isFile && it.length() == baseSize }
                .firstOrNull { DeltaPatch.sha256(it) == baseHash }
                ?: throw AssertionError("Exact base APK for generated delta was not found")
            val target = File(targetDirectory!!, artifact.getString("apk"))
            val patch = File(manifestFile.parentFile, patchDescriptor.getString("file"))
            val output = temporary.newFile()
            val targetHash = artifact.getString("sha256")
            val targetSize = artifact.getLong("size")
            assertTrue("Generated target APK exists", target.isFile)
            assertTrue("Generated delta patch exists", patch.isFile)
            assertEquals(targetSize, target.length())
            assertEquals(targetHash, DeltaPatch.sha256(target))
            assertEquals(patchDescriptor.getLong("size"), patch.length())
            assertEquals(patchDescriptor.getString("sha256"), DeltaPatch.sha256(patch))
            DeltaPatch.apply(base, patch, output, baseSize, targetSize, baseHash, targetHash)
            assertEquals(targetHash, DeltaPatch.sha256(output))
            assertArrayEquals(target.readBytes(), output.readBytes())
            return
        }
        val path = System.getenv("KIVO_DELTA_FIXTURE_DIR")
        assumeTrue("Optional downloaded release fixture", !path.isNullOrEmpty())
        val root = File(path!!)
        val base = File(root, "kivo-v1.31.0-arm64-v8a.apk")
        val target = File(root, "kivo-v1.31.1-arm64-v8a.apk")
        val patch = File(root, "production/kivo-v1.31.1-arm64-v8a-from-v1.31.0.kdelta")
        val output = temporary.newFile()
        val hash = DeltaPatch.sha256(target)
        DeltaPatch.apply(base, patch, output, base.length(), target.length(), DeltaPatch.sha256(base), hash)
        assertEquals("daefbb9336eb26043c05817a97084e1df3415ebb1ba66679264deab8713c9a6b", hash)
        assertEquals(hash, DeltaPatch.sha256(output))
        assertArrayEquals(target.readBytes(), output.readBytes())
    }

    private fun hexBytes(value: String): ByteArray = value.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
}
