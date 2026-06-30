package dev.selector.kivo_player

import android.content.pm.ActivityInfo
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
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
        super.onDestroy()
    }
}
