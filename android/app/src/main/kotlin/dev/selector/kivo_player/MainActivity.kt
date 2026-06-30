package dev.selector.kivo_player

import android.content.ContentUris
import android.content.pm.ActivityInfo
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    // --- kivo/frames ---
    private val frameExecutor = Executors.newSingleThreadExecutor()
    // --- kivo/media ---
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private var retriever: MediaMetadataRetriever? = null
    private var retrieverPath: String? = null

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
                if (call.method == "scan") {
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
                                    ))
                                }
                            }
                            runOnUiThread { result.success(out) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("SCAN_FAILED", e.message, null) }
                        }
                    }
                } else {
                    result.notImplemented()
                }
            }
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
        super.onDestroy()
    }
}
