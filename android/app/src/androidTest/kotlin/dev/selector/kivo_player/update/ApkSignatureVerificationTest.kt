package dev.selector.kivo_player.update

import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.io.RandomAccessFile
import java.security.MessageDigest
import java.util.zip.ZipFile

/** Exercises the device's real package parser, with its installed APK and no fixture secrets. */
@RunWith(AndroidJUnit4::class)
class ApkSignatureVerificationTest {
    @Suppress("DEPRECATION")
    @Test fun archiveLookupVerifiesSignaturesRatherThanOnlyExtractingCertificates() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val flags = PackageManager.GET_SIGNATURES or
            (if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else 0)
        val installed = context.packageManager.getPackageInfo(context.packageName, flags)
        val copy = File.createTempFile("kivo-signature-test-", ".apk", context.cacheDir)
        try {
            File(context.applicationInfo.sourceDir).copyTo(copy, overwrite = true)
            val intact = context.packageManager.getPackageArchiveInfo(copy.absolutePath, flags)
            assertNotNull("The installed signed APK must verify", intact)
            assertEquals(context.packageName, intact!!.packageName)
            assertFalse("Verified signing details must be present", signers(intact).isEmpty())
            assertEquals(signers(installed), signers(intact))

            val manifestBefore = ZipFile(copy).use { zip ->
                zip.getInputStream(zip.getEntry("AndroidManifest.xml")).use { it.readBytes() }
            }
            flipDexPayloadByte(copy)
            // The parseable manifest and embedded signer material were left intact.
            // A metadata-only certificate lookup would still report the original signers.
            val manifestAfter = ZipFile(copy).use { zip ->
                zip.getInputStream(zip.getEntry("AndroidManifest.xml")).use { it.readBytes() }
            }
            assertArrayEquals(manifestBefore, manifestAfter)
            val tampered = try {
                context.packageManager.getPackageArchiveInfo(copy.absolutePath, flags)
            } catch (_: Exception) { null }
            assertTrue("A changed DEX payload must fail signature verification",
                tampered == null || signers(tampered).isEmpty())
        } finally { copy.delete() }
    }

    @Suppress("DEPRECATION")
    private fun signers(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        return signatures?.map { signature ->
            DeltaPatch.hex(MessageDigest.getInstance("SHA-256").digest(signature.toByteArray()))
        }?.toSet() ?: emptySet()
    }

    /** Uses the central directory, so streamed local headers and APK signing blocks remain intact. */
    private fun flipDexPayloadByte(file: File) {
        RandomAccessFile(file, "rw").use { apk ->
            val first = maxOf(0L, apk.length() - 65_557)
            var end = apk.length() - 22
            while (end >= first) {
                apk.seek(end)
                if (readU32(apk) == 0x06054b50L) break
                end--
            }
            require(end >= first) { "ZIP end directory missing" }
            apk.seek(end + 16)
            var entry = readU32(apk)
            while (entry < end) {
                apk.seek(entry)
                require(readU32(apk) == 0x02014b50L) { "Invalid ZIP central entry" }
                apk.seek(entry + 20)
                val compressedSize = readU32(apk)
                apk.seek(entry + 28)
                val nameSize = readU16(apk)
                val extraSize = readU16(apk)
                val commentSize = readU16(apk)
                apk.seek(entry + 42)
                val local = readU32(apk)
                val name = ByteArray(nameSize)
                apk.seek(entry + 46)
                apk.readFully(name)
                if (String(name, Charsets.UTF_8).endsWith(".dex") && compressedSize > 16) {
                    apk.seek(local)
                    require(readU32(apk) == 0x04034b50L)
                    apk.seek(local + 26)
                    val localNameSize = readU16(apk)
                    val localExtraSize = readU16(apk)
                    val offset = local + 30 + localNameSize + localExtraSize + compressedSize / 2
                    apk.seek(offset)
                    val original = apk.readUnsignedByte()
                    apk.seek(offset)
                    apk.writeByte(original xor 1)
                    apk.fd.sync()
                    return
                }
                entry += 46 + nameSize + extraSize + commentSize
            }
            error("No DEX payload in installed APK")
        }
    }

    private fun readU16(file: RandomAccessFile): Int = file.readUnsignedByte() or (file.readUnsignedByte() shl 8)
    private fun readU32(file: RandomAccessFile): Long = readU16(file).toLong() or (readU16(file).toLong() shl 16)
}
