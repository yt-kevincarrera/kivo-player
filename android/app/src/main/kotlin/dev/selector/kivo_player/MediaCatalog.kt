package dev.selector.kivo_player

import android.content.ContentResolver
import android.content.ContentUris
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

/** Video rows plus accessible RealMedia files Android classified as audio/data. */
internal class MediaCatalog(private val resolver: ContentResolver) {
    fun scan(): ArrayList<HashMap<String, Any>> {
        val rows = ArrayList<HashMap<String, Any>>()
        val seen = HashSet<Long>()
        append(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, rows, seen)
        try {
            append(
                MediaStore.Files.getContentUri("external"), rows, seen,
                "LOWER(${MediaStore.MediaColumns.DISPLAY_NAME}) LIKE ? OR " +
                    "LOWER(${MediaStore.MediaColumns.DISPLAY_NAME}) LIKE ?",
                arrayOf("%.rm", "%.rmvb"),
            )
        } catch (e: RuntimeException) {
            // Scoped storage can hide audio/data rows when only video access
            // was granted. Keep the video library usable; Open file uses SAF.
            android.util.Log.w("kivo/media", "RealMedia rows unavailable: ${e.message}")
        }
        rows.sortByDescending { (it["dateAddedMs"] as Number).toLong() }
        return rows
    }

    private fun append(
        collection: Uri,
        out: ArrayList<HashMap<String, Any>>,
        seen: MutableSet<Long>,
        selection: String? = null,
        args: Array<String>? = null,
    ) {
        val columns = arrayOf(
            MediaStore.Video.Media._ID,
            MediaStore.Video.Media.DISPLAY_NAME,
            MediaStore.Video.Media.BUCKET_DISPLAY_NAME,
            MediaStore.Video.Media.DURATION,
            MediaStore.Video.Media.SIZE,
            MediaStore.Video.Media.DATE_ADDED,
            MediaStore.MediaColumns.DATE_MODIFIED,
            MediaStore.Video.Media.DATA,
            MediaStore.Video.Media.WIDTH,
            MediaStore.Video.Media.HEIGHT,
        )
        query(collection, columns, "${MediaStore.Video.Media.DATE_ADDED} DESC", selection, args)?.use { c ->
            val idC = c.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
            val nameC = c.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME)
            val bucketC = c.getColumnIndex(MediaStore.Video.Media.BUCKET_DISPLAY_NAME)
            val durC = c.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION)
            val sizeC = c.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE)
            val dateC = c.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_ADDED)
            val modifiedC = c.getColumnIndex(MediaStore.MediaColumns.DATE_MODIFIED)
            val dataC = c.getColumnIndex(MediaStore.Video.Media.DATA)
            val widthC = c.getColumnIndex(MediaStore.Video.Media.WIDTH)
            val heightC = c.getColumnIndex(MediaStore.Video.Media.HEIGHT)
            val relPathC = c.getColumnIndex(MediaStore.Video.Media.RELATIVE_PATH)
            while (c.moveToNext()) {
                val id = c.getLong(idC)
                if (!seen.add(id)) continue
                val data = if (dataC >= 0) c.getString(dataC) else null
                val uri = ContentUris.withAppendedId(collection, id)
                val name = c.getString(nameC) ?: ""
                var duration = c.getLong(durC)
                if (duration <= 0 && RealMediaMetadata.matches(name)) {
                    try {
                        resolver.openInputStream(uri)?.use { duration = RealMediaMetadata.durationMs(it) }
                    } catch (_: Exception) {
                        // Keep the rest of the library available if this file vanished.
                    }
                }
                val folder = (if (bucketC >= 0) c.getString(bucketC) else null)
                    ?.takeIf { it.isNotEmpty() } ?: data?.let { File(it).parentFile?.name } ?: ""
                out.add(hashMapOf(
                    "id" to id.toString(),
                    "uri" to uri.toString(),
                    "name" to name,
                    "folder" to folder,
                    "durationMs" to duration,
                    "sizeBytes" to c.getLong(sizeC),
                    "dateAddedMs" to c.getLong(dateC) * 1000L,
                    "dateModifiedMs" to (if (modifiedC >= 0) c.getLong(modifiedC) * 1000L else 0L),
                    "width" to (if (widthC >= 0) c.getInt(widthC) else 0),
                    "height" to (if (heightC >= 0) c.getInt(heightC) else 0),
                    "path" to relativePathOf(if (relPathC >= 0) c.getString(relPathC) else null, data),
                ))
            }
        }
    }

    fun query(
        uri: Uri,
        columns: Array<String>,
        sortOrder: String? = null,
        selection: String? = null,
        args: Array<String>? = null,
    ): Cursor? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return resolver.query(uri, columns, selection, args, sortOrder)
        }
        return try {
            resolver.query(uri, arrayOf(*columns, MediaStore.MediaColumns.RELATIVE_PATH), selection, args, sortOrder)
        } catch (e: RuntimeException) {
            // Preserve support for vendor providers without RELATIVE_PATH.
            android.util.Log.w("kivo/media", "RELATIVE_PATH unavailable; retrying: ${e.message}")
            resolver.query(uri, columns, selection, args, sortOrder)
        }
    }

    companion object {
        fun relativePathOf(relative: String?, data: String?): String {
            if (!relative.isNullOrEmpty()) return relative
            val parent = data?.takeIf { it.isNotEmpty() }?.let { File(it).parent } ?: return ""
            val root = Environment.getExternalStorageDirectory().absolutePath.trimEnd('/')
            if (!parent.startsWith("$root/") && parent != root) return ""
            val path = parent.removePrefix(root).trim('/')
            return if (path.isEmpty()) "" else "$path/"
        }
    }
}
