package dev.selector.kivo_player

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ActivityInfo
import android.graphics.drawable.Icon
import android.os.Build
import android.graphics.Bitmap
import android.media.AudioManager
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.MediaStore
import android.util.Rational
import android.view.KeyEvent
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
    // --- kivo/volume ---
    // When true (player active), hardware volume keys are handled here and the
    // OS volume panel is suppressed; the library leaves this false.
    private var interceptVolume = false
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

    companion object {
        private const val PIP_ACTION = "dev.selector.kivo_player.PIP_ACTION"
        private const val PIP_EXTRA = "action"
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
                    else -> result.notImplemented()
                }
            }

        // ── kivo/volume ─────────────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kivo/volume")
            .setMethodCallHandler { call, result ->
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
            val dir = if (keyCode == KeyEvent.KEYCODE_VOLUME_UP)
                AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER
            audioManager.adjustStreamVolume(AudioManager.STREAM_MUSIC, dir, 0)
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        if (interceptVolume && isVolumeKey(keyCode)) return true
        return super.onKeyUp(keyCode, event)
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
