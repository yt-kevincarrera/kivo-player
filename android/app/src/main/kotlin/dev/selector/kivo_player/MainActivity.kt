package dev.selector.kivo_player

import android.app.DownloadManager
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

    // --- kivo/update ---
    // The download is owned by DownloadManager, not by this Activity: it keeps
    // going with Kivo backgrounded or killed. Dart holds the id (persisted in
    // settings) and polls downloadStatus while its UI is on screen. Nothing
    // installs automatically — installDownload only runs when the user taps
    // Instalar, so an update never hijacks the screen mid-video.
    private val downloadManager: DownloadManager
        get() = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager

    /** Queues the APK and returns its DownloadManager id, or -1 on failure. */
    private fun enqueueApk(url: String, fileName: String): Long {
        // App-private external files: no storage permission, and the manifest's
        // FileProvider already maps exactly this directory.
        val dest = File(getExternalFilesDir(null), fileName).apply { if (exists()) delete() }
        val req = DownloadManager.Request(Uri.parse(url))
            .setTitle("Kivo $fileName")
            .setMimeType("application/vnd.android.package-archive")
            // Visible while it runs, gone once it finishes. A completed-download
            // notification would offer a second, competing way to install.
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            .setDestinationUri(Uri.fromFile(dest))
        return try { downloadManager.enqueue(req) } catch (_: Exception) { -1L }
    }

    /** Null when the id is unknown — cleared by the system or by the user. */
    private fun queryDownload(id: Long): Map<String, Any?>? {
        if (id < 0) return null
        val cursor = try {
            downloadManager.query(DownloadManager.Query().setFilterById(id))
        } catch (_: Exception) { null } ?: return null
        cursor.use {
            if (!it.moveToFirst()) return null
            val status = it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            val reason = it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))
            return mapOf(
                "status" to when (status) {
                    DownloadManager.STATUS_PENDING -> "pending"
                    DownloadManager.STATUS_RUNNING -> "running"
                    DownloadManager.STATUS_PAUSED -> "paused"
                    DownloadManager.STATUS_SUCCESSFUL -> "done"
                    else -> "failed"
                },
                // Only read while paused. It is what separates "the system
                // parked this until you have Wi-Fi" from "a transfer hiccup,
                // retrying" — the difference the UI used to be unable to show.
                "reason" to if (reason == DownloadManager.PAUSED_WAITING_TO_RETRY) "retry" else "network",
                "received" to it.getLong(
                    it.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)),
                "total" to it.getLong(
                    it.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)),
            )
        }
    }

    private fun installDownload(id: Long): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            // Route the user to enable "install unknown apps" for Kivo, then they retry.
            try {
                startActivity(Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            } catch (_: Exception) {}
            return "needsPermission"
        }
        val uri = try { downloadManager.getUriForDownloadedFile(id) } catch (_: Exception) { null }
            ?: return "failed"
        return try {
            startActivity(Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            })
            "started"
        } catch (_: Exception) { "failed" }
    }

    /// Writes a captured frame into the gallery under Pictures/Kivo and
    /// returns its content:// uri, or null.
    ///
    /// On API 29+ the row is created IS_PENDING so the gallery never indexes a
    /// half-written file; the flag is cleared once the bytes are down. Below
    /// 29 there is no pending flag, and no runtime permission either, because
    /// the app writes through MediaStore rather than to the raw path.
    private fun saveImageToGallery(bytes: ByteArray, fileName: String): String? {
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }
        val values = android.content.ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/Kivo")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
        }

        var uri: android.net.Uri? = null
        return try {
            uri = contentResolver.insert(collection, values) ?: return null
            contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw java.io.IOException("no output stream for $uri")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
            }
            uri.toString()
        } catch (e: Exception) {
            // A half-written row would sit in the gallery as a broken image, so
            // take it back out rather than leave it.
            uri?.let { try { contentResolver.delete(it, null, null) } catch (_: Exception) {} }
            null
        }
    }

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

    // Reuse the process-lifetime engine warmed up in KivoApplication instead of
    // creating a per-Activity one, and keep it alive when this Activity is torn
    // down. This pins the Dart isolate (and mpv's FFI callback) to the process
    // lifetime — see KivoApplication for the crash this prevents.
    override fun provideFlutterEngine(context: Context): FlutterEngine? =
        io.flutter.embedding.engine.FlutterEngineCache.getInstance().get(KivoApplication.ENGINE_ID)
            ?: super.provideFlutterEngine(context)

    override fun shouldDestroyEngineWithHost(): Boolean = false

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
                                )
                                queryVideos(col, proj,
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
                                    // -1 whenever the column wasn't queried or isn't there.
                                    val relPathC = c.getColumnIndex(MediaStore.Video.Media.RELATIVE_PATH)
                                    while (c.moveToNext()) {
                                        val id = c.getLong(idC)
                                        val uri = ContentUris.withAppendedId(col, id).toString()
                                        val data = if (dataC >= 0) c.getString(dataC) else null
                                        var folder = if (bucketC >= 0) c.getString(bucketC) else null
                                        if (folder.isNullOrEmpty() && data != null) {
                                            folder = File(data).parentFile?.name
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
                                            "path" to relativePathOf(
                                                if (relPathC >= 0) c.getString(relPathC) else null, data),
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
                    // ── frame capture ─────────────────────────────────────
                    "saveImage" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val name = call.argument<String>("fileName")
                        if (bytes == null || name == null) {
                            result.error("INVALID_ARG", "bytes and fileName required", null)
                            return@setMethodCallHandler
                        }
                        result.success(saveImageToGallery(bytes, name))
                    }
                    "viewImage" -> {
                        val uri = call.argument<String>("uri")
                        if (uri == null) { result.error("INVALID_ARG", "uri required", null); return@setMethodCallHandler }
                        try {
                            startActivity(Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(Uri.parse(uri), "image/*")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                            })
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("VIEW_FAILED", e.message, null)
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
                            // API 30+: move to the system trash (recoverable for 30 days
                            // from the Files app) instead of a permanent delete.
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                                Environment.isExternalStorageManager()) {
                                val values = android.content.ContentValues().apply {
                                    put(MediaStore.MediaColumns.IS_TRASHED, 1)
                                }
                                val rows = contentResolver.update(u, values, null, null)
                                if (rows > 0) {
                                    result.success("ok")
                                } else {
                                    // Row not owned by us despite all-files-access (rare):
                                    // fall back to the system trash consent dialog.
                                    val pi = MediaStore.createTrashRequest(contentResolver, listOf(u), true)
                                    pendingFileOpResult = result
                                    startIntentSenderForResult(pi.intentSender, REQ_DELETE, null, 0, 0, 0)
                                }
                                return@setMethodCallHandler
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                val pi = MediaStore.createTrashRequest(contentResolver, listOf(u), true)
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
                            // API 30+: move all to the system trash instead of deleting
                            // outright — see the "delete" handler above.
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                                Environment.isExternalStorageManager()) {
                                val values = android.content.ContentValues().apply {
                                    put(MediaStore.MediaColumns.IS_TRASHED, 1)
                                }
                                var allTrashed = true
                                for (u in us) {
                                    if (contentResolver.update(u, values, null, null) <= 0) {
                                        allTrashed = false
                                    }
                                }
                                if (allTrashed) {
                                    result.success("ok")
                                } else {
                                    val pi = MediaStore.createTrashRequest(contentResolver, us, true)
                                    pendingFileOpResult = result
                                    startIntentSenderForResult(pi.intentSender, REQ_DELETE, null, 0, 0, 0)
                                }
                                return@setMethodCallHandler
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                val pi = MediaStore.createTrashRequest(contentResolver, us, true)
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
                            val vaultDir = vaultDir()
                            for (uriStr in uris) {
                                try {
                                    val u = Uri.parse(uriStr)
                                    val proj = arrayOf(
                                        MediaStore.Video.Media._ID,
                                        MediaStore.Video.Media.DISPLAY_NAME,
                                        MediaStore.Video.Media.DATA,
                                        MediaStore.Video.Media.DURATION,
                                        MediaStore.Video.Media.SIZE,
                                        MediaStore.Video.Media.DATE_ADDED,
                                        MediaStore.Video.Media.WIDTH,
                                        MediaStore.Video.Media.HEIGHT,
                                    )
                                    queryVideos(u, proj)?.use { c ->
                                        if (!c.moveToFirst()) return@use
                                        val id = c.getString(c.getColumnIndexOrThrow(MediaStore.Video.Media._ID))
                                        val name = c.getString(c.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME)) ?: "$id"
                                        val data = c.getColumnIndex(MediaStore.Video.Media.DATA).let { if (it >= 0) c.getString(it) else null }
                                        val rel = relativePathOf(
                                            c.getColumnIndex(MediaStore.Video.Media.RELATIVE_PATH)
                                                .let { if (it >= 0) c.getString(it) else null },
                                            data,
                                        )
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
                                } catch (e: Exception) {
                                    // Skip this uri but leave a trace: a batch that
                                    // silently hides fewer files than asked for is
                                    // indistinguishable from success.
                                    android.util.Log.w("kivo/vault", "hide skipped $uriStr: ${e.message}")
                                }
                            }
                            runOnUiThread { result.success(out) }
                        }
                    }
                    "unhide" -> {
                        val entries = call.argument<List<Map<String, Any?>>>("entries")
                        if (entries == null) { result.error("INVALID_ARG", "entries required", null); return@setMethodCallHandler }
                        ioExecutor.execute {
                            val succeeded = ArrayList<String>()
                            for (m in entries) {
                                val privatePath = m["privatePath"] as? String ?: continue
                                try {
                                    val src = File(privatePath)
                                    if (!src.exists()) continue
                                    val displayName = (m["displayName"] as? String)?.takeIf { it.isNotBlank() } ?: src.name
                                    val relPath = (m["relativePath"] as? String)?.trim('/')?.takeIf { it.isNotBlank() } ?: "Movies"
                                    val dateAddedMs = (m["dateAddedMs"] as? Number)?.toLong() ?: 0L

                                    // Move (rename, same-volume => instant) back into shared storage,
                                    // into the ORIGINAL folder, with a collision-safe name.
                                    val destDir = File(Environment.getExternalStorageDirectory(), relPath).apply { mkdirs() }
                                    var dest = File(destDir, displayName)
                                    if (dest.exists()) {
                                        val base = displayName.substringBeforeLast('.', displayName)
                                        val ext = displayName.substringAfterLast('.', "")
                                        var i = 1
                                        while (dest.exists()) {
                                            dest = File(destDir, if (ext.isEmpty()) "$base ($i)" else "$base ($i).$ext")
                                            i++
                                        }
                                    }
                                    val moved = src.renameTo(dest) || run {
                                        src.copyTo(dest, overwrite = false); src.delete(); dest.exists()
                                    }
                                    if (!moved) { android.util.Log.w("kivo/vault", "unhide: move failed for $privatePath"); continue }

                                    // Restore the file's timestamp so it doesn't read as brand-new,
                                    // then index it in MediaStore and best-effort restore DATE_ADDED
                                    // (read-only on some OS versions — the move already succeeded).
                                    if (dateAddedMs > 0) dest.setLastModified(dateAddedMs)
                                    try {
                                        android.media.MediaScannerConnection.scanFile(
                                            applicationContext, arrayOf(dest.absolutePath), arrayOf("video/*")
                                        ) { _, uri ->
                                            if (uri != null && dateAddedMs > 0) {
                                                try {
                                                    val cv = android.content.ContentValues().apply {
                                                        put(MediaStore.Video.Media.DATE_ADDED, dateAddedMs / 1000)
                                                        put(MediaStore.Video.Media.DATE_MODIFIED, dateAddedMs / 1000)
                                                    }
                                                    contentResolver.update(uri, cv, null, null)
                                                } catch (_: Exception) {}
                                            }
                                        }
                                    } catch (_: Exception) {}
                                    succeeded.add(privatePath)
                                } catch (e: Exception) {
                                    android.util.Log.w("kivo/vault", "unhide failed for $privatePath: ${e.message}")
                                }
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
                    "migrate" -> {
                        // One-time move of any legacy vault files out of the app-private
                        // Android/data dir (where moves are slow byte-copies) into the
                        // shared hidden folder (same-volume => instant renames). Returns
                        // [{old, new}] so Dart can rewrite the persisted privatePaths.
                        ioExecutor.execute {
                            val out = ArrayList<HashMap<String, String>>()
                            try {
                                val oldDir = File(getExternalFilesDir(null), "vault")
                                if (oldDir.isDirectory) {
                                    val newDir = vaultDir()
                                    oldDir.listFiles()?.forEach { f ->
                                        if (!f.isFile) return@forEach
                                        val dest = File(newDir, f.name)
                                        val moved = f.renameTo(dest) || run {
                                            f.copyTo(dest, overwrite = true); f.delete(); dest.exists()
                                        }
                                        if (moved) out.add(hashMapOf("old" to f.absolutePath, "new" to dest.absolutePath))
                                    }
                                }
                            } catch (_: Exception) {}
                            runOnUiThread { result.success(out) }
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

        // ── kivo/update ───────────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kivo/update")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAppVersion" -> result.success(
                        try { packageManager.getPackageInfo(packageName, 0).versionName } catch (_: Exception) { "" })
                    "primaryAbi" -> result.success(Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a")
                    "androidSdk" -> result.success(Build.VERSION.SDK_INT)
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        try {
                            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            result.success(null)
                        } catch (e: Exception) { result.error("OPEN_FAILED", e.message, null) }
                    }
                    "enqueueUpdate" -> {
                        val url = call.argument<String>("url")
                        val fileName = call.argument<String>("fileName") ?: "update.apk"
                        if (url == null) { result.error("INVALID_ARG", "url required", null); return@setMethodCallHandler }
                        result.success(enqueueApk(url, fileName))
                    }
                    // The channel codec sends a Dart int as Int32 or Int64 depending
                    // on its magnitude, so read every id as a Number.
                    "downloadStatus" -> result.success(
                        queryDownload(call.argument<Number>("id")?.toLong() ?: -1L))
                    "cancelDownload" -> {
                        val id = call.argument<Number>("id")?.toLong() ?: -1L
                        if (id >= 0) try { downloadManager.remove(id) } catch (_: Exception) {}
                        result.success(null)
                    }
                    "installDownload" -> result.success(
                        installDownload(call.argument<Number>("id")?.toLong() ?: -1L))
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

    // NOTE: we intentionally do NOT override cleanUpFlutterEngine to null
    // PlaybackSessionHub.channel anymore. The engine is now process-lifetime
    // (KivoApplication + shouldDestroyEngineWithHost=false), so it outlives this
    // Activity: nulling the channel on Activity teardown would break background
    // media controls, and the "late callback on a dead engine" it guarded
    // against can no longer happen (the engine never dies with the Activity).
    // configureFlutterEngine re-points the channel on each re-attach.

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

    /// MediaStore's RELATIVE_PATH column only exists from API 29 (Android 10) on.
    /// Below that the provider's SQLite schema has no such column, so naming it in
    /// a projection makes the WHOLE query fail to compile ("no such column
    /// relative_path") instead of just yielding -1 from getColumnIndex.
    private val hasRelativePath: Boolean
        get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

    /// Queries video rows with RELATIVE_PATH appended only where the OS version
    /// says it exists — and, if the provider rejects it anyway, retries without it.
    /// The version check covers stock Android; the retry covers vendor-forked
    /// providers that report API 29+ but still lack the column. Losing the column
    /// costs a folder name (derived from _data instead); losing the query costs
    /// the whole library.
    private fun queryVideos(
        uri: Uri,
        columns: Array<String>,
        sortOrder: String? = null,
    ): android.database.Cursor? {
        if (!hasRelativePath) return contentResolver.query(uri, columns, null, null, sortOrder)
        val withRelPath = arrayOf(*columns, MediaStore.Video.Media.RELATIVE_PATH)
        return try {
            contentResolver.query(uri, withRelPath, null, null, sortOrder)
        } catch (e: Exception) {
            android.util.Log.w("kivo/media",
                "query rejected ${MediaStore.Video.Media.RELATIVE_PATH} (${e.message}); retrying without it")
            contentResolver.query(uri, columns, null, null, sortOrder)
        }
    }

    /// The folder a row lives in, relative to the storage root, MediaStore style
    /// ("Movies/"). Read from RELATIVE_PATH where available, otherwise derived
    /// from the _data path so pre-Android-10 devices still get a real folder.
    private fun relativePathOf(relPath: String?, data: String?): String {
        if (!relPath.isNullOrEmpty()) return relPath
        val parent = data?.takeIf { it.isNotEmpty() }?.let { File(it).parent } ?: return ""
        val root = Environment.getExternalStorageDirectory().absolutePath.trimEnd('/')
        if (!parent.startsWith(root)) return "" // removable volume: unknown root
        val rel = parent.removePrefix(root).trim('/')
        return if (rel.isEmpty()) "" else "$rel/"
    }

    /// The vault directory: a hidden folder in shared storage (same volume as the
    /// user's media, so moves are instant renames, not byte copies). A .nomedia
    /// keeps it out of galleries. Created on first use.
    private fun vaultDir(): File = File(Environment.getExternalStorageDirectory(), ".KivoVault").apply {
        mkdirs()
        val noMedia = File(this, ".nomedia")
        if (!noMedia.exists()) try { noMedia.createNewFile() } catch (_: Exception) {}
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
