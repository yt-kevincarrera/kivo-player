package dev.selector.kivo_player

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MediaCatalogInstrumentedTest {
    @Test
    fun realMediaAudioRowsAreListedWithoutOrdinaryAudioOrDuplicates() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        if (Build.VERSION.SDK_INT >= 33) {
            instrumentation.uiAutomation.grantRuntimePermission(context.packageName, "android.permission.READ_MEDIA_VIDEO")
        }
        val resolver = context.contentResolver
        val writableCollection = MediaStore.Files.getContentUri(
            if (Build.VERSION.SDK_INT >= 29) MediaStore.VOLUME_EXTERNAL_PRIMARY else "external")
        val prefix = "kivo-catalog-${System.nanoTime()}"
        val fixtures = listOf(
            "$prefix.RM" to "audio/x-pn-realaudio",
            "$prefix.RMVB" to "application/vnd.rn-realmedia-vbr",
            "$prefix-video.rm" to "video/vnd.rn-realvideo",
            "$prefix.mp3" to "audio/mpeg",
        )
        val inserted = fixtures.map { (name, mime) ->
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                if (Build.VERSION.SDK_INT >= 29) {
                    put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/KivoCatalogTest/")
                }
            }
            resolver.insert(writableCollection, values)!!
        }
        try {
            val rows = MediaCatalog(resolver).scan()
            val ours = rows.filter { (it["name"] as String).startsWith(prefix) }
            assertEquals(fixtures.take(3).map { it.first }.toSet(), ours.map { it["name"] }.toSet())
            assertEquals(3, ours.size)
            val audioRow = ours.single { it["name"] == "$prefix.RM" }
            assertTrue((audioRow["uri"] as String).contains("/file/"))
            assertEquals(0L, audioRow["durationMs"])
        } finally {
            inserted.forEach { resolver.delete(it, null, null) }
        }
    }
}
