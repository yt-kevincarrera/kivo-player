package dev.selector.kivo_player

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction
import java.security.MessageDigest
import java.util.concurrent.Executor
import org.mozilla.universalchardet.UniversalDetector

/**
 * `kivo/subtitles`: hands mpv a UTF-8 copy of any external text subtitle.
 *
 * The bundled libmpv has no uchardet and no iconv, so it reads every
 * non-UTF-8 file as "UTF-8-BROKEN" (stray bytes as Latin-1). That is close
 * enough for Spanish in Latin-1 and garbage for Windows-1252's own range and
 * for every non-Latin script. Java has every charset decoder we need and
 * juniversalchardet does the guessing, so the conversion happens here instead.
 */
object SubtitleCharsets {
    private const val MAX_BYTES = 20 * 1024 * 1024
    private const val KEEP_FILES = 40
    private const val CACHE_DIR = "subtitles-utf8"
    private val TEXT_EXTS = setOf("srt", "ass", "ssa", "vtt", "sub", "smi", "txt")

    fun attach(messenger: BinaryMessenger, context: Context, executor: Executor) {
        val main = Handler(Looper.getMainLooper())
        MethodChannel(messenger, "kivo/subtitles").setMethodCallHandler { call, result ->
            when (call.method) {
                "prepare" -> {
                    val uri = call.argument<String>("uri")
                    if (uri == null) {
                        result.error("INVALID_ARG", "uri required", null)
                        return@setMethodCallHandler
                    }
                    val name = call.argument<String>("name")
                    val encoding = call.argument<String>("encoding")
                    executor.execute {
                        try {
                            val out = prepare(context, uri, name, encoding)
                            main.post { result.success(out) }
                        } catch (e: Exception) {
                            main.post { result.error("SUBTITLE_PREPARE_FAILED", e.toString(), null) }
                        }
                    }
                }
                "encodings" -> result.success(Charset.availableCharsets().keys.toList())
                "systemFont" -> executor.execute {
                    val out = try { systemFont(context) } catch (e: Exception) { null }
                    main.post { result.success(out) }
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Returns `{path, encoding, detected}`. `path` is [uri] itself when the file
     * can go to mpv untouched (already UTF-8, or binary like VobSub), otherwise
     * a converted copy in the cache.
     */
    fun prepare(context: Context, uri: String, name: String?, manual: String?): Map<String, Any?> {
        val bytes = read(context, uri)
        if (isBinary(bytes)) {
            return mapOf("path" to uri, "encoding" to null, "detected" to false)
        }
        val charsetName: String
        val detected: Boolean
        if (manual != null) {
            charsetName = manual
            detected = false
        } else {
            // UTF-16 first, BOM or not: mostly-ASCII UTF-16 is also "valid
            // UTF-8" (NUL is a legal byte), so the UTF-8 check alone would pass
            // it through untouched.
            val marked = bomCharset(bytes) ?: unmarkedUtf16(bytes)
            if (marked == "UTF-8" || (marked == null && isValidUtf8(bytes))) {
                return mapOf("path" to uri, "encoding" to "UTF-8", "detected" to true)
            }
            charsetName = marked ?: detect(bytes)
            detected = true
        }
        if (charsetName.equals("UTF-8", ignoreCase = true) && isValidUtf8(bytes)) {
            return mapOf("path" to uri, "encoding" to "UTF-8", "detected" to detected)
        }
        val text = String(bytes, Charset.forName(charsetName)).removePrefix("﻿")
        val file = cacheFile(context, uri, charsetName, name)
        // Write-then-rename: the same uri+charset maps to the same file, and
        // mpv may still be reading the previous copy of it.
        val tmp = File(file.path + ".tmp")
        tmp.writeText(text, Charsets.UTF_8)
        if (!tmp.renameTo(file)) {
            tmp.delete()
            throw IllegalStateException("could not write $file")
        }
        prune(file.parentFile)
        return mapOf("path" to file.absolutePath, "encoding" to charsetName, "detected" to detected)
    }

    /**
     * A font libass can use: this build has no font provider (no fontconfig),
     * so it sees only the files in `sub-fonts-dir`. The system's own Roboto is
     * copied once into the app's files dir — not linked into from /system/fonts
     * wholesale, because libass reads every file of that dir into memory.
     * Returns `{dir, family}`, or null when no candidate exists.
     */
    private fun systemFont(context: Context): Map<String, String>? {
        val candidates = listOf(
            "Roboto-Regular.ttf" to "Roboto",
            "RobotoStatic-Regular.ttf" to "Roboto",
            "DroidSans.ttf" to "Droid Sans",
        )
        val dir = File(context.filesDir, "subtitle-fonts").apply { mkdirs() }
        for ((name, family) in candidates) {
            val src = File("/system/fonts", name)
            if (!src.canRead()) continue
            val dst = File(dir, name)
            if (!dst.exists() || dst.length() != src.length()) {
                val tmp = File(dir, "$name.tmp")
                src.copyTo(tmp, overwrite = true)
                if (!tmp.renameTo(dst)) { tmp.delete(); continue }
            }
            // Only the chosen font in the dir: libass loads all of it.
            dir.listFiles()?.filter { it.name != name }?.forEach { it.delete() }
            return mapOf("dir" to dir.absolutePath, "family" to family)
        }
        return null
    }

    private fun read(context: Context, uri: String): ByteArray {
        val stream = when {
            uri.startsWith("content://") -> context.contentResolver.openInputStream(Uri.parse(uri))
                ?: throw IllegalStateException("no stream for $uri")
            uri.startsWith("file://") -> File(Uri.parse(uri).path!!).inputStream()
            else -> File(uri).inputStream()
        }
        return stream.use { input ->
            val out = java.io.ByteArrayOutputStream()
            val buf = ByteArray(64 * 1024)
            var total = 0
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                total += n
                if (total > MAX_BYTES) throw IllegalStateException("subtitle larger than $MAX_BYTES bytes")
                out.write(buf, 0, n)
            }
            out.toByteArray()
        }
    }

    /** A NUL in the first 4 KB of a file that is not UTF-16: not text (VobSub .sub). */
    private fun isBinary(bytes: ByteArray): Boolean {
        val bom = bomCharset(bytes)
        if (bom != null && bom.startsWith("UTF-16")) return false
        if (unmarkedUtf16(bytes) != null) return false
        val n = minOf(bytes.size, 4096)
        for (i in 0 until n) if (bytes[i] == 0.toByte()) return true
        return false
    }

    /**
     * UTF-16 saved without a BOM (some Windows tools do): mostly-ASCII text puts
     * a NUL in every other byte — the high byte, odd positions for LE and even
     * ones for BE. A binary format has NULs, but not in that regular pattern.
     */
    private fun unmarkedUtf16(b: ByteArray): String? {
        val pairs = minOf(b.size, 4096) / 2
        if (pairs < 8) return null
        var evenZeros = 0
        var oddZeros = 0
        for (i in 0 until pairs) {
            if (b[2 * i] == 0.toByte()) evenZeros++
            if (b[2 * i + 1] == 0.toByte()) oddZeros++
        }
        return when {
            oddZeros * 10 >= pairs * 3 && evenZeros * 20 <= pairs -> "UTF-16LE"
            evenZeros * 10 >= pairs * 3 && oddZeros * 20 <= pairs -> "UTF-16BE"
            else -> null
        }
    }

    private fun bomCharset(b: ByteArray): String? = when {
        b.size >= 3 && b[0] == 0xEF.toByte() && b[1] == 0xBB.toByte() && b[2] == 0xBF.toByte() -> "UTF-8"
        b.size >= 2 && b[0] == 0xFF.toByte() && b[1] == 0xFE.toByte() -> "UTF-16LE"
        b.size >= 2 && b[0] == 0xFE.toByte() && b[1] == 0xFF.toByte() -> "UTF-16BE"
        else -> null
    }

    private fun isValidUtf8(bytes: ByteArray): Boolean = try {
        Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(bytes))
        true
    } catch (e: CharacterCodingException) {
        false
    }

    /**
     * Mozilla's detector (juniversalchardet) — Android's public ICU does not
     * expose CharsetDetector. Its answer is used only if Java can decode it,
     * under Java's canonical name. ISO-8859-1 is promoted to windows-1252, its
     * superset (what browsers do): "Latin-1" subtitles almost always carry
     * Windows-1252's curly quotes in the 0x80–0x9F range Latin-1 leaves
     * undefined. No answer → the same Windows-1252 guess, the most common
     * non-UTF-8 subtitle encoding there is (and the only sane default for the
     * single-byte scripts the detector cannot tell apart, e.g. windows-1250).
     */
    private fun detect(bytes: ByteArray): String {
        try {
            val detector = UniversalDetector()
            detector.handleData(bytes, 0, bytes.size)
            detector.dataEnd()
            val raw = detector.detectedCharset
            // juniversalchardet's own spelling for the one it names differently
            // from Java; anything else Java cannot decode falls through below.
            val n = if (raw.equals("MACCYRILLIC", ignoreCase = true)) "x-MacCyrillic" else raw
            if (n != null) {
                if (n.equals("ISO-8859-1", ignoreCase = true)) return "windows-1252"
                if (Charset.isSupported(n)) return Charset.forName(n).name()
            }
        } catch (e: Exception) {
            android.util.Log.w("kivo/subtitles", "detection failed: ${e.message}")
        }
        return "windows-1252"
    }

    private fun cacheFile(context: Context, uri: String, charset: String, name: String?): File {
        val dir = File(context.cacheDir, CACHE_DIR).apply { mkdirs() }
        val digest = MessageDigest.getInstance("SHA-1")
            .digest("$uri|$charset".toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
        return File(dir, "$digest.${extensionOf(name, uri)}")
    }

    /** mpv/ffmpeg probe the content, but the extension is what picks the parser first. */
    private fun extensionOf(name: String?, uri: String): String {
        for (candidate in listOf(name, Uri.parse(uri).lastPathSegment, uri)) {
            val ext = candidate?.substringAfterLast('.', "")?.lowercase() ?: continue
            if (ext in TEXT_EXTS) return ext
        }
        return "srt"
    }

    private fun prune(dir: File?) {
        val files = dir?.listFiles() ?: return
        if (files.size <= KEEP_FILES) return
        files.sortedByDescending { it.lastModified() }.drop(KEEP_FILES).forEach { it.delete() }
    }
}
