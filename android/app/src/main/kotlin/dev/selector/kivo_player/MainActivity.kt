package dev.selector.kivo_player

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RecoverableSecurityException
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ActivityInfo
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Environment
import android.graphics.Bitmap
import android.media.AudioManager
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.MediaStore
import android.util.Rational
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {
    // --- kivo/frames ---
    private val frameExecutor = Executors.newSingleThreadExecutor()
    // --- kivo/media ---
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private var retriever: MediaMetadataRetriever? = null
    private var retrieverPath: String? = null
    // --- kivo/volume ---
    // When true (player active), hardware volume keys are handled here and the
    // OS volume panel is suppressed; the library leaves this false.
    private var interceptVolume = false
    private var volumeChannel: MethodChannel? = null
    private val audioManager by lazy {
        getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }

    // --- kivo/pip ---
    private var pipChannel: MethodChannel? = null
    private var pipArmed = false
    private var pipWidth = 16
    private var pipHeight = 9
    private var pipPlaying = false
    private var pipReceiverRegistered = false
    private val pipSupported: Boolean
        get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE)

    // --- kivo/media file ops (delete/rename consent) ---
    private var pendingFileOpResult: MethodChannel.Result? = null
    private var pendingRenameUri: android.net.Uri? = null
    private var pendingRenameFinalName: String? = null

    companion object {
        private const val PIP_ACTION = "dev.selector.kivo_player.PIP_ACTION"
        private const val PIP_EXTRA = "action"
        private const val REQ_DELETE = 4011
        private const val REQ_RENAME = 4012
    }

    private val pipReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.getStringExtra(PIP_EXTRA)) {
                "play" -> pipChannel?.invokeMethod("play", null)
                "pause" -> pipChannel?.invokeMethod("pause", null)
                "rewind" -> pipChannel?.invokeMethod("skip", mapOf("seconds" to -10))
                "forward" -> pipChannel?.invokeMethod("skip", mapOf("seconds" to 10))
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── kivo/orientation ──────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kivo/orientation")
            .setMethodCallHandler { call, result ->
                if (call.method == "set") {
                    requestedOrientation = when (call.argument<String>("mode")) {
                        "sensorLandscape" -> ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                        "sensorPortrait"  -> ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT
                        else              -> ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

        // ── kivo/frames ───────────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kivo/frames")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "prepare" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("INVALID_ARG", "path is required", null)
                            return@setMethodCallHandler
                        }
                        frameExecutor.submit {
                            try {
                                if (retrieverPath != path) {
                                    retriever?.release()
                                    val r = MediaMetadataRetriever()
                                    // content:// URIs (MediaStore library) need the
                                    // Context+Uri overload; setDataSource(String) only
                                    // handles file paths/URLs.
                                    if (path.startsWith("content://")) {
                                        r.setDataSource(this@MainActivity, Uri.parse(path))
                                    } else {
                                        r.setDataSource(path)
                                    }
                                    // Warm the decoder so the first scrub frame isn't a
                                    // ~half-second cold-start (discard the result).
                                    try {
                                        r.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)?.recycle()
                                    } catch (_: Exception) {}
                                    retriever = r
                                    retrieverPath = path
                                }
                                runOnUiThread { result.success(null) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("PREPARE_FAILED", e.message, null)
                                }
                            }
                        }
                    }

                    "frameAt" -> {
                        // Accept Int or Long: the channel codec encodes a Dart
                        // int as Long once it exceeds 32 bits (very long videos).
                        val ms = (call.argument<Number>("ms"))?.toLong()
                        if (ms == null) {
                            result.error("INVALID_ARG", "ms is required", null)
                            return@setMethodCallHandler
                        }
                        frameExecutor.submit {
                            try {
                                val r = retriever
                                if (r == null) {
                                    runOnUiThread {
                                        result.error("NOT_PREPARED", "call prepare first", null)
                                    }
                                    return@submit
                                }
                                val us = ms * 1_000L
                                // Grab the full frame (already in display orientation) and
                                // scale from the real bitmap dims — aspect- and rotation-
                                // correct. getScaledFrameAtTime is avoided: it requires a
                                // POSITIVE height, so there's no clean "preserve aspect" call.
                                val full = r.getFrameAtTime(
                                    us,
                                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                                )
                                val raw: Bitmap? = if (full != null && full.width > 0) {
                                    val targetW = 240
                                    val targetH = (full.height * targetW / full.width).coerceAtLeast(1)
                                    val scaled = Bitmap.createScaledBitmap(full, targetW, targetH, true)
                                    if (scaled !== full) full.recycle()
                                    scaled
                                } else {
                                    full
                                }
                                if (raw == null) {
                                    runOnUiThread { result.success(null) }
                                    return@submit
                                }
                                val bos = ByteArrayOutputStream()
                                raw.compress(Bitmap.CompressFormat.JPEG, 75, bos)
                                raw.recycle()
                                val bytes = bos.toByteArray()
                                runOnUiThread { result.success(bytes) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("FRAME_FAILED", e.message, null)
                                }
                            }
                        }
                    }

                    "release" -> {
                        frameExecutor.submit {
                            try {
                                retriever?.release()
                                retriever = null
                                retrieverPath = null
                                runOnUiThread { result.success(null) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("RELEASE_FAILED", e.message, null)
                                }
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        // ── kivo/media ────────────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kivo/media")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scan" -> {
                        ioExecutor.execute {
                            val out = ArrayList<HashMap<String, Any>>()
                            try {
                                val col = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                                val proj = arrayOf(
                                    MediaStore.Video.Media._ID,
                                    MediaStore.Video.Media.DISPLAY_NAME,
                                    MediaStore.Video.Media.BUCKET_DISPLAY_NAME,
                                    MediaStore.Video.Media.DURATION,
                                    MediaStore.Video.Media.SIZE,
                                    MediaStore.Video.Media.DATE_ADDED,
                                    MediaStore.Video.Media.DATA,
                                    MediaStore.Video.Media.WIDTH,
                                    MediaStore.Video.Media.HEIGHT,
                                    MediaStore.Video.Media.RELATIVE_PATH,
                                )
                                contentResolver.query(col, proj, null, null,
                                    "${MediaStore.Video.Media.DATE_ADDED} DESC")?.use { c ->
                                    val idC = c.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
                                    val nameC = c.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME)
                                    val bucketC = c.getColumnIndex(MediaStore.Video.Media.BUCKET_DISPLAY_NAME)
                                    val durC = c.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION)
                                    val sizeC = c.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE)
                                    val dateC = c.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_ADDED)
                                    val dataC = c.getColumnIndex(MediaStore.Video.Media.DATA)
                                    val widthC = c.getColumnIndex(MediaStore.Video.Media.WIDTH)
                                    val heightC = c.getColumnIndex(MediaStore.Video.Media.HEIGHT)
                                    val relPathC = c.getColumnIndex(MediaStore.Video.Media.RELATIVE_PATH)
                                    while (c.moveToNext()) {
                                        val id = c.getLong(idC)
                                        val uri = ContentUris.withAppendedId(col, id).toString()
                                        var folder = if (bucketC >= 0) c.getString(bucketC) else null
                                        if (folder.isNullOrEmpty() && dataC >= 0) {
                                            folder = c.getString(dataC)?.let { File(it).parentFile?.name }
                                        }
                                        out.add(hashMapOf(
                                            "id" to id.toString(),
                                            "uri" to uri,
                                            "name" to (c.getString(nameC) ?: ""),
                                            "folder" to (folder ?: ""),
                                            "durationMs" to c.getLong(durC),
                                            "sizeBytes" to c.getLong(sizeC),
                                            "dateAddedMs" to c.getLong(dateC) * 1000L, // DATE_ADDED is seconds
                                            "width" to (if (widthC >= 0) c.getInt(widthC) else 0),
                                            "height" to (if (heightC >= 0) c.getInt(heightC) else 0),
                                            "path" to (if (relPathC >= 0) (c.getString(relPathC) ?: "") else ""),
                                        ))
                                    }
                                }
                                runOnUiThread { result.success(out) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("SCAN_FAILED", e.message, null) }
                            }
                        }
                    }
                    "thumbnail" -> {
                        val id = call.argument<String>("id")
                        if (id == null) { result.error("INVALID_ARG", "id required", null); return@setMethodCallHandler }
                        ioExecutor.execute {
                            var bytes: ByteArray? = null
                            try {
                                val uri = ContentUris.withAppendedId(
                                    MediaStore.Video.Media.EXTERNAL_CONTENT_URI, id.toLong())
                                val bmp = if (Build.VERSION.SDK_INT >= 29) {
                                    contentResolver.loadThumbnail(uri, android.util.Size(320, 180), null)
                                } else {
                                    @Suppress("DEPRECATION")
                                    MediaStore.Video.Thumbnails.getThumbnail(
                                        contentResolver, id.toLong(),
                                        MediaStore.Video.Thumbnails.MINI_KIND, null)
                                }
                                if (bmp != null) {
                                    val bos = java.io.ByteArrayOutputStream()
                                    bmp.compress(Bitmap.CompressFormat.JPEG, 80, bos)
                                    bytes = bos.toByteArray()
                                }
                            } catch (_: Exception) {}
                            runOnUiThread { result.success(bytes) }
                        }
                    }
                    "findSubtitles" -> {
                        val folder = call.argument<String>("folder")
                        if (folder == null) { result.error("INVALID_ARG", "folder required", null); return@setMethodCallHandler }
                        ioExecutor.execute {
                            val out = ArrayList<HashMap<String, Any>>()
                            try {
                                val col = MediaStore.Files.getContentUri("external")
                                val proj = arrayOf(
                                    MediaStore.Files.FileColumns._ID,
                                    MediaStore.Files.FileColumns.DISPLAY_NAME,
                                )
                                val exts = listOf("srt", "vtt", "ass", "ssa", "sub")
                                val likeClauses = exts.joinToString(" OR ") {
                                    "${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE ?"
                                }
                                val selection = "${MediaStore.Files.FileColumns.BUCKET_DISPLAY_NAME} = ? AND ($likeClauses)"
                                val args = arrayOf(folder) + exts.map { "%.$it" }.toTypedArray()
                                contentResolver.query(col, proj, selection, args, null)?.use { c ->
                                    val idC = c.getColumnIndexOrThrow(MediaStore.Files.FileColumns._ID)
                                    val nameC = c.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DISPLAY_NAME)
                                    while (c.moveToNext()) {
                                        val id = c.getLong(idC)
                                        val uri = ContentUris.withAppendedId(col, id).toString()
                                        out.add(hashMapOf(
                                            "uri" to uri,
                                            "displayName" to (c.getString(nameC) ?: ""),
                                        ))
                                    }
                                }
                                runOnUiThread { result.success(out) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("FIND_SUBTITLES_FAILED", e.message, null) }
                            }
                        }
                    }
                    "share" -> {
                        val uri = call.argument<String>("uri")
                        if (uri == null) { result.error("INVALID_ARG", "uri required", null); return@setMethodCallHandler }
                        try {
                            val send = Intent(Intent.ACTION_SEND).apply {
                                type = "video/*"
                                putExtra(Intent.EXTRA_STREAM, Uri.parse(uri))
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(Intent.createChooser(send, null))
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("SHARE_FAILED", e.message, null)
                        }
                    }
                    "delete" -> {
                        val uri = call.argument<String>("uri")
                        if (uri == null) { result.error("INVALID_ARG", "uri required", null); return@setMethodCallHandler }
                        if (pendingFileOpResult != null) { result.success("error"); return@setMethodCallHandler }
                        val u = Uri.parse(uri)
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                                Environment.isExternalStorageManager()) {
                                contentResolver.delete(u, null, null)
                                result.success("ok")
                                return@setMethodCallHandler
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                val pi = MediaStore.createDeleteRequest(contentResolver, listOf(u))
                                pendingFileOpResult = result
                                startIntentSenderForResult(pi.intentSender, REQ_DELETE, null, 0, 0, 0)
                            } else {
                                try {
                                    contentResolver.delete(u, null, null)
                                    result.success("ok")
                                } catch (e: RecoverableSecurityException) {
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                        pendingFileOpResult = result
                                        startIntentSenderForResult(
                                            e.userAction.actionIntent.intentSender, REQ_DELETE, null, 0, 0, 0)
                                    } else {
                                        result.success("error")
                                    }
                                }
                            }
                        } catch (e: Exception) {
                            pendingFileOpResult = null
                            result.success("error")
                        }
                    }
                    "rename" -> {
                        val uri = call.argument<String>("uri")
                        val base = call.argument<String>("name")
                        if (uri == null || base == null) { result.error("INVALID_ARG", "uri+name required", null); return@setMethodCallHandler }
                        if (pendingFileOpResult != null) { result.success(mapOf("status" to "error")); return@setMethodCallHandler }
                        val u = Uri.parse(uri)
                        // Preserve the current extension.
                        val currentName = queryDisplayName(u) ?: ""
                        val dot = currentName.lastIndexOf('.')
                        val ext = if (dot > 0) currentName.substring(dot) else ""
                        val finalName = base + ext
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                                Environment.isExternalStorageManager()) {
                                val values = android.content.ContentValues().apply {
                                    put(MediaStore.Video.Media.DISPLAY_NAME, finalName)
                                }
                                contentResolver.update(u, values, null, null)
                                result.success(mapOf("status" to "ok", "newName" to finalName))
                                return@setMethodCallHandler
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                val pi = MediaStore.createWriteRequest(contentResolver, listOf(u))
                                pendingFileOpResult = result
                                pendingRenameUri = u
                                pendingRenameFinalName = finalName
                                startIntentSenderForResult(pi.intentSender, REQ_RENAME, null, 0, 0, 0)
                            } else {
                                val values = android.content.ContentValues().apply {
                                    put(MediaStore.Video.Media.DISPLAY_NAME, finalName)
                                }
                                contentResolver.update(u, values, null, null)
                                result.success(mapOf("status" to "ok", "newName" to finalName))
                            }
                        } catch (e: Exception) {
                            pendingFileOpResult = null
                            pendingRenameUri = null
                            pendingRenameFinalName = null
                            result.success(mapOf("status" to "error"))
                        }
                    }
                    "shareMany" -> {
                        val uris = call.argument<List<String>>("uris")
                        if (uris == null) { result.error("INVALID_ARG", "uris required", null); return@setMethodCallHandler }
                        try {
                            val list = ArrayList<Uri>(uris.map { Uri.parse(it) })
                            val send = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                                type = "video/*"
                                putParcelableArrayListExtra(Intent.EXTRA_STREAM, list)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(Intent.createChooser(send, null))
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("SHARE_FAILED", e.message, null)
                        }
                    }
                    "deleteMany" -> {
                        val uris = call.argument<List<String>>("uris")
                        if (uris == null) { result.error("INVALID_ARG", "uris required", null); return@setMethodCallHandler }
                        if (pendingFileOpResult != null) { result.success("error"); return@setMethodCallHandler }
                        val us = uris.map { Uri.parse(it) }
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                                Environment.isExternalStorageManager()) {
                                for (u in us) contentResolver.delete(u, null, null)
                                result.success("ok")
                                return@setMethodCallHandler
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                val pi = MediaStore.createDeleteRequest(contentResolver, us)
                                pendingFileOpResult = result
                                startIntentSenderForResult(pi.intentSender, REQ_DELETE, null, 0, 0, 0)
                            } else {
                                for (u in us) contentResolver.delete(u, null, null)
                                result.success("ok")
                            }
                        } catch (e: Exception) {
                            pendingFileOpResult = null
                            result.success("error")
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ── kivo/vault ────────────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kivo/vault")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hide" -> {
                        val uris = call.argument<List<String>>("uris")
                        if (uris == null) { result.error("INVALID_ARG", "uris required", null); return@setMethodCallHandler }
                        ioExecutor.execute {
                            val out = ArrayList<HashMap<String, Any>>()
                            val vaultDir = File(getExternalFilesDir(null), "vault").apply { mkdirs() }
                            for (uriStr in uris) {
                                try {
                                    val u = Uri.parse(uriStr)
                                    val proj = arrayOf(
                                        MediaStore.Video.Media._ID,
                                        MediaStore.Video.Media.DISPLAY_NAME,
                                        MediaStore.Video.Media.DATA,
                                        MediaStore.Video.Media.RELATIVE_PATH,
                                        MediaStore.Video.Media.DURATION,
                                        MediaStore.Video.Media.SIZE,
                                        MediaStore.Video.Media.DATE_ADDED,
                                        MediaStore.Video.Media.WIDTH,
                                        MediaStore.Video.Media.HEIGHT,
                                    )
                                    contentResolver.query(u, proj, null, null, null)?.use { c ->
                                        if (!c.moveToFirst()) return@use
                                        val id = c.getString(c.getColumnIndexOrThrow(MediaStore.Video.Media._ID))
                                        val name = c.getString(c.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME)) ?: "$id"
                                        val data = c.getColumnIndex(MediaStore.Video.Media.DATA).let { if (it >= 0) c.getString(it) else null }
                                        val rel = c.getColumnIndex(MediaStore.Video.Media.RELATIVE_PATH).let { if (it >= 0) (c.getString(it) ?: "") else "" }
                                        val dur = c.getLong(c.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION))
                                        val size = c.getLong(c.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE))
                                        val date = c.getLong(c.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_ADDED)) * 1000L
                                        val w = c.getColumnIndex(MediaStore.Video.Media.WIDTH).let { if (it >= 0) c.getInt(it) else 0 }
                                        val h = c.getColumnIndex(MediaStore.Video.Media.HEIGHT).let { if (it >= 0) c.getInt(it) else 0 }
                                        val ext = name.substringAfterLast('.', "mp4")
                                        val dest = File(vaultDir, "$id.$ext")
                                        var moved = false
                                        if (data != null) {
                                            val src = File(data)
                                            moved = src.renameTo(dest) || run {
                                                src.copyTo(dest, overwrite = true); src.delete()
                                            }
                                        }
                                        if (!moved && data == null) {
                                            // no filesystem path (rare): stream-copy then delete row
                                            contentResolver.openInputStream(u)?.use { input ->
                                                dest.outputStream().use { input.copyTo(it) }
                                            }
                                            moved = dest.exists()
                                            // Guard against a truncated/failed copy: compare the
                                            // copied file's length to the MediaStore SIZE already
                                            // read for this row. A mismatch means the stream copy
                                            // did not fully complete — do not delete the MediaStore
                                            // row or report this uri as hidden.
                                            if (moved && dest.length() != size) {
                                                dest.delete()
                                                moved = false
                                            }
                                        }
                                        if (moved) {
                                            try { contentResolver.delete(u, null, null) } catch (_: Exception) {}
                                            out.add(hashMapOf(
                                                "id" to id, "privatePath" to dest.absolutePath,
                                                "displayName" to name, "originalRelativePath" to rel,
                                                "durationMs" to dur, "sizeBytes" to size, "dateAddedMs" to date,
                                                "width" to w, "height" to h,
                                            ))
                                        }
                                    }
                                } catch (_: Exception) { /* skip this uri */ }
                            }
                            runOnUiThread { result.success(out) }
                        }
                    }
                    "unhide" -> {
                        val paths = call.argument<List<String>>("paths")
                        if (paths == null) { result.error("INVALID_ARG", "paths required", null); return@setMethodCallHandler }
                        ioExecutor.execute {
                            val succeeded = ArrayList<String>()
                            for (p in paths) {
                                try {
                                    val src = File(p)
                                    if (!src.exists()) continue
                                    val values = android.content.ContentValues().apply {
                                        put(MediaStore.Video.Media.DISPLAY_NAME, src.name)
                                        put(MediaStore.Video.Media.MIME_TYPE, "video/*")
                                        put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/")
                                        put(MediaStore.Video.Media.IS_PENDING, 1)
                                    }
                                    val col = MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                                    val dest = contentResolver.insert(col, values)
                                    if (dest == null) continue
                                    contentResolver.openOutputStream(dest)?.use { out -> src.inputStream().use { it.copyTo(out) } }
                                    values.clear(); values.put(MediaStore.Video.Media.IS_PENDING, 0)
                                    contentResolver.update(dest, values, null, null)
                                    src.delete()
                                    succeeded.add(p)
                                } catch (_: Exception) { /* skip this path */ }
                            }
                            runOnUiThread { result.success(succeeded) }
                        }
                    }
                    "deleteForever" -> {
                        val paths = call.argument<List<String>>("paths")
                        if (paths == null) { result.error("INVALID_ARG", "paths required", null); return@setMethodCallHandler }
                        ioExecutor.execute {
                            val succeeded = ArrayList<String>()
                            for (p in paths) {
                                try {
                                    val f = File(p)
                                    f.delete()
                                    if (!f.exists()) succeeded.add(p)
                                } catch (_: Exception) { /* skip this path */ }
                            }
                            runOnUiThread { result.success(succeeded) }
                        }
                    }
                    "thumbnail" -> {
                        val path = call.argument<String>("path")
                        if (path == null) { result.error("INVALID_ARG", "path required", null); return@setMethodCallHandler }
                        ioExecutor.execute {
                            var bytes: ByteArray? = null
                            try {
                                val mmr = android.media.MediaMetadataRetriever()
                                mmr.setDataSource(path)
                                val bmp = mmr.getFrameAtTime(1_000_000, android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                                mmr.release()
                                if (bmp != null) {
                                    val scaled = Bitmap.createScaledBitmap(bmp, 320, (320.0 * bmp.height / bmp.width).toInt().coerceAtLeast(1), true)
                                    val bos = java.io.ByteArrayOutputStream()
                                    scaled.compress(Bitmap.CompressFormat.JPEG, 80, bos)
                                    bytes = bos.toByteArray()
                                }
                            } catch (_: Exception) {}
                            runOnUiThread { result.success(bytes) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ── kivo/volume ─────────────────────────────────────────────────────────
        val volume = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kivo/volume")
        volumeChannel = volume
        volume.setMethodCallHandler { call, result ->
            if (call.method == "setKeyInterception") {
                interceptVolume = call.argument<Boolean>("on") ?: false
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        // ── kivo/media_session ────────────────────────────────────────────────
        val sessionChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kivo/media_session")
        PlaybackSessionHub.channel = sessionChannel
        sessionChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    PlaybackSessionHub.update(
                        applicationContext,
                        call.argument<String>("title") ?: "Kivo",
                        call.argument<String>("mediaUri") ?: "",
                        (call.argument<Number>("positionMs") ?: 0).toLong(),
                        (call.argument<Number>("durationMs") ?: 0).toLong(),
                        call.argument<Boolean>("playing") ?: false,
                        call.argument<Boolean>("inBackground") ?: false,
                    )
                    result.success(null)
                }
                "end" -> {
                    PlaybackSessionHub.end(applicationContext)
                    result.success(null)
                }
                "acquireFocus" -> {
                    PlaybackSessionHub.acquireFocus(applicationContext)
                    result.success(null)
                }
                "releaseFocus" -> {
                    PlaybackSessionHub.releaseFocus(applicationContext)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // ── kivo/pip ──────────────────────────────────────────────────────────
        val pip = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kivo/pip")
        pipChannel = pip
        pip.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(pipSupported)
                "arm" -> {
                    pipArmed = true
                    pipWidth = (call.argument<Number>("width") ?: 16).toInt().coerceAtLeast(1)
                    pipHeight = (call.argument<Number>("height") ?: 9).toInt().coerceAtLeast(1)
                    pipPlaying = call.argument<Boolean>("playing") ?: false
                    result.success(null)
                }
                "disarm" -> { pipArmed = false; result.success(null) }
                "updateState" -> {
                    pipWidth = (call.argument<Number>("width") ?: pipWidth).toInt().coerceAtLeast(1)
                    pipHeight = (call.argument<Number>("height") ?: pipHeight).toInt().coerceAtLeast(1)
                    pipPlaying = call.argument<Boolean>("playing") ?: pipPlaying
                    // Refresh params live if already floating.
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && isInPictureInPictureMode) {
                        setPictureInPictureParams(buildPipParams())
                    }
                    result.success(null)
                }
                "enterNow" -> { enterPip(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }

    // While the player is active, swallow the hardware volume keys and adjust
    // STREAM_MUSIC ourselves with flag 0 (no FLAG_SHOW_UI) so the OS volume
    // panel never appears. The volume change still fires VolumeController's
    // listener on the Dart side, which drives Kivo's own HUD. Returning true
    // consumes the event so the framework's default (which shows the panel)
    // never runs. Outside the player interceptVolume is false → normal OS behavior.
    private fun isVolumeKey(keyCode: Int) =
        keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (interceptVolume && isVolumeKey(keyCode)) {
            // Forward the press to Dart, which owns the whole 0..boostMax range
            // (system volume for 0..100, media_kit software gain above). We no
            // longer adjust STREAM_MUSIC here: that capped at 100 and, once at
            // the max, produced no volume-change event so Kivo's HUD never showed.
            val dir = if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) 1 else -1
            val maxIndex = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            volumeChannel?.invokeMethod("volumeKey", mapOf("dir" to dir, "maxIndex" to maxIndex))
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        if (interceptVolume && isVolumeKey(keyCode)) return true
        return super.onKeyUp(keyCode, event)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // PlaybackSessionHub.channel is set in configureFlutterEngine and never
        // cleared otherwise; a late audio-focus callback could invokeMethod on
        // a dead engine's channel. Null it here before the engine goes away.
        PlaybackSessionHub.channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        // Release on the executor thread so it can't race an in-flight frameAt;
        // shutdown() still lets this already-submitted task run to completion.
        frameExecutor.submit {
            retriever?.release()
            retriever = null
            retrieverPath = null
        }
        frameExecutor.shutdown()
        ioExecutor.shutdown()
        // Destroying straight from PiP (close ✕ / swipe from recents) may skip
        // onPictureInPictureModeChanged(false) where the receiver is normally
        // unregistered — unregister here too or Android logs a leaked receiver.
        if (pipReceiverRegistered) {
            try { unregisterReceiver(pipReceiver) } catch (_: Exception) {}
            pipReceiverRegistered = false
        }
        super.onDestroy()
    }

    private fun queryDisplayName(uri: android.net.Uri): String? {
        return try {
            contentResolver.query(uri, arrayOf(MediaStore.Video.Media.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) c.getString(0) else null
            }
        } catch (_: Exception) { null }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQ_DELETE -> {
                val r = pendingFileOpResult
                pendingFileOpResult = null
                r?.success(if (resultCode == RESULT_OK) "ok" else "cancelled")
            }
            REQ_RENAME -> {
                val r = pendingFileOpResult
                val u = pendingRenameUri
                val finalName = pendingRenameFinalName
                pendingFileOpResult = null
                pendingRenameUri = null
                pendingRenameFinalName = null
                if (resultCode != RESULT_OK || u == null || finalName == null) {
                    r?.success(mapOf("status" to "cancelled"))
                    return
                }
                try {
                    val values = android.content.ContentValues().apply {
                        put(MediaStore.Video.Media.DISPLAY_NAME, finalName)
                    }
                    contentResolver.update(u, values, null, null)
                    r?.success(mapOf("status" to "ok", "newName" to finalName))
                } catch (e: Exception) {
                    r?.success(mapOf("status" to "error"))
                }
            }
        }
    }

    private fun remoteAction(iconRes: Int, title: String, action: String, requestCode: Int): RemoteAction {
        val intent = Intent(PIP_ACTION).setPackage(packageName).putExtra(PIP_EXTRA, action)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val pi = PendingIntent.getBroadcast(this, requestCode, intent, flags)
        val icon = Icon.createWithResource(this, iconRes)
        return RemoteAction(icon, title, title, pi)
    }

    private fun buildPipParams(): PictureInPictureParams {
        // Android requires the aspect between ~0.42 and ~2.39; clamp to be safe.
        val ratio = pipWidth.toFloat() / pipHeight.toFloat()
        val clamped = ratio.coerceIn(0.45f, 2.35f)
        val rational = Rational((clamped * 1000).toInt(), 1000)
        val actions = listOf(
            remoteAction(android.R.drawable.ic_media_rew, "Retroceder", "rewind", 1),
            if (pipPlaying) {
                remoteAction(android.R.drawable.ic_media_pause, "Pausa", "pause", 2)
            } else {
                remoteAction(android.R.drawable.ic_media_play, "Reproducir", "play", 2)
            },
            remoteAction(android.R.drawable.ic_media_ff, "Avanzar", "forward", 3),
        )
        return PictureInPictureParams.Builder()
            .setAspectRatio(rational)
            .setActions(actions)
            .build()
    }

    private fun enterPip() {
        if (!pipSupported) return
        if (!pipReceiverRegistered) {
            val filter = IntentFilter(PIP_ACTION)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(pipReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                registerReceiver(pipReceiver, filter)
            }
            pipReceiverRegistered = true
        }
        try {
            enterPictureInPictureMode(buildPipParams())
        } catch (_: Exception) {
            // Some OEM builds throw if PiP is disabled by the user; ignore.
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (pipArmed && pipPlaying && pipSupported) enterPip()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: android.content.res.Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("modeChanged", mapOf("inPip" to isInPictureInPictureMode))
        if (!isInPictureInPictureMode && pipReceiverRegistered) {
            // Left PiP (restored or closed) — drop the receiver; re-registered on next enter.
            try { unregisterReceiver(pipReceiver) } catch (_: Exception) {}
            pipReceiverRegistered = false
        }
    }
}
