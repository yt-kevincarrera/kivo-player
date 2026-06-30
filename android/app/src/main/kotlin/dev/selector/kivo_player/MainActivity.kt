package dev.selector.kivo_player

import android.content.pm.ActivityInfo
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    // --- kivo/frames ---
    private val frameExecutor = Executors.newSingleThreadExecutor()
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
                                    r.setDataSource(path)
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
                        val ms = call.argument<Int>("ms")
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
                                val us = ms.toLong() * 1_000L
                                val raw: Bitmap? = if (Build.VERSION.SDK_INT >= 27) {
                                    r.getScaledFrameAtTime(
                                        us,
                                        MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                                        240,
                                        135,
                                    )
                                } else {
                                    val full = r.getFrameAtTime(
                                        us,
                                        MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                                    )
                                    if (full != null) {
                                        val w = full.width
                                        val h = full.height
                                        if (w > 0) {
                                            val targetW = 240
                                            val targetH = (h * targetW) / w
                                            val scaled = Bitmap.createScaledBitmap(
                                                full, targetW, targetH, true,
                                            )
                                            if (scaled !== full) full.recycle()
                                            scaled
                                        } else {
                                            full
                                        }
                                    } else {
                                        null
                                    }
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
    }

    override fun onDestroy() {
        retriever?.release()
        retriever = null
        retrieverPath = null
        frameExecutor.shutdown()
        super.onDestroy()
    }
}
