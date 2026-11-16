package dev.selector.kivo_player

import android.app.UiModeManager
import android.Manifest
import android.content.pm.PackageManager
import android.content.Context
import android.content.BroadcastReceiver
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.util.Log
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.storage.StorageManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executor

/** Mounted storage only. All operations are read-only and obey Android access. */
internal class TvStorageBrowser(private val context: Context) {
    private data class Volume(val root: File, val name: String, val removable: Boolean)

    private fun mounted(): List<Volume> {
        val out = linkedMapOf<String, Volume>()
        fun add(root: File, name: String, removable: Boolean) {
            val canonical = root.canonicalFile
            if (canonical.isDirectory) out[canonical.path] = Volume(canonical, name, removable)
        }
        val storage = context.getSystemService(Context.STORAGE_SERVICE) as StorageManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            for (volume in storage.storageVolumes) {
                if (volume.state != Environment.MEDIA_MOUNTED && volume.state != Environment.MEDIA_MOUNTED_READ_ONLY) continue
                volume.directory?.let { add(it, volume.getDescription(context), volume.isRemovable) }
            }
        } else {
            // Public app-directory APIs supply mounted roots even on builds
            // without DocumentsUI. Never inspect other apps' private folders.
            for (appDir in context.getExternalFilesDirs(null)) {
                if (appDir == null) continue
                val prefix = appDir.absolutePath.substringBefore("/Android/")
                if (prefix == appDir.absolutePath) continue
                val root = File(prefix)
                add(root, if (Environment.isExternalStorageRemovable(appDir)) root.name else "Internal storage",
                    Environment.isExternalStorageRemovable(appDir))
            }
            // Some TV builds omit USB app directories from getExternalFilesDirs.
            File("/storage").listFiles()?.filter { it.name != "self" && it.name != "emulated" }
                ?.forEach { candidate ->
                    if (candidate.isDirectory && candidate.canRead()) add(candidate, candidate.name, true)
                }
        }
        if (out.isEmpty()) add(Environment.getExternalStorageDirectory(), "Internal storage", false)
        return out.values.toList()
    }

    private fun checked(path: String): File {
        val file = File(path).canonicalFile
        require(mounted().any { file == it.root || file.path.startsWith(it.root.path + File.separator) }) {
            "Path is outside mounted shared storage"
        }
        return file
    }

    fun volumes(): List<Map<String, Any>> = mounted().map {
        mapOf("path" to it.root.path, "name" to it.name, "removable" to it.removable)
    }

    private fun video(file: File): Map<String, Any> = mapOf(
        "id" to "tv:${file.path}", "uri" to Uri.fromFile(file).toString(),
        "name" to file.name, "folder" to (file.parentFile?.name ?: ""),
        "durationMs" to 0, "sizeBytes" to file.length(),
        "dateAddedMs" to file.lastModified(), "filePath" to file.path,
    )

    private fun children(directory: File): List<File> = TvStorageFiles.children(directory)

    fun list(path: String): List<Map<String, Any>> = children(checked(path)).map {
        video(it) + ("directory" to it.isDirectory)
    }

    fun browse(path: String): Map<String, Any> {
        val directory = checked(path)
        val limited = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
            !Environment.isExternalStorageManager()
        else context.checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED
        val direct = try { children(directory).map { video(it) + ("directory" to it.isDirectory) } }
            catch (e: SecurityException) { if (!limited) throw e else emptyList() }
        val indexed = if (!limited) emptyList() else try {
            MediaCatalog(context.contentResolver).scan { path ->
                File(path).canonicalPath.startsWith(directory.path + File.separator)
            }
        } catch (e: RuntimeException) {
            Log.w("kivo/storage", "Media query unavailable: ${e.javaClass.simpleName}")
            emptyList()
        }
        Log.i("kivo/storage", "Browse limited=$limited direct=${direct.size} indexed=${indexed.size}")
        return mapOf("entries" to TvStorageFiles.merge(directory, direct, indexed), "accessLimited" to limited)
    }

    fun rescan(path: String, done: () -> Unit) {
        val directory = checked(path)
        require(directory.isDirectory) { "Storage is disconnected" }
        MediaScannerConnection.scanFile(context, arrayOf(directory.path), null) { _, uri ->
            Log.i("kivo/storage", "Media scan completed indexed=${uri != null}")
            done()
        }
    }

    fun scanRemovable(): List<Map<String, Any>> {
        val out = ArrayList<Map<String, Any>>()
        for (volume in mounted().filter { it.removable }) {
            val pending = java.util.ArrayDeque<File>()
            pending.add(volume.root)
            while (pending.isNotEmpty()) {
                val directory = pending.removeFirst()
                // A denied subtree must not blank the readable portion of a USB
                // drive. The browser exposes permission recovery for that folder.
                val files = try { children(directory) } catch (_: SecurityException) { continue }
                    catch (_: IllegalStateException) { continue }
                for (file in files) {
                    if (file.isDirectory) pending.add(file) else out.add(video(file))
                }
            }
        }
        return out
    }

    fun thumbnail(path: String): ByteArray? {
        val file = checked(path)
        val retriever = MediaMetadataRetriever()
        var bitmap: Bitmap? = null
        return try {
            retriever.setDataSource(file.path)
            bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1)
                retriever.getScaledFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 640, 360)
            else retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            bitmap?.let { frame -> ByteArrayOutputStream().use { bytes ->
                frame.compress(Bitmap.CompressFormat.JPEG, 80, bytes)
                bytes.toByteArray()
            } }
        } finally {
            bitmap?.recycle()
            retriever.release()
        }
    }

    companion object {
        fun isTelevision(context: Context): Boolean =
            (context.getSystemService(Context.UI_MODE_SERVICE) as UiModeManager).currentModeType ==
                Configuration.UI_MODE_TYPE_TELEVISION

        fun attach(context: Context, messenger: BinaryMessenger, executor: Executor, post: (() -> Unit) -> Unit) {
            MethodChannel(messenger, "kivo/device").setMethodCallHandler { call, result ->
                if (call.method == "isTelevision") result.success(isTelevision(context)) else result.notImplemented()
            }
            val browser = TvStorageBrowser(context)
            EventChannel(messenger, "kivo/storage_events").setStreamHandler(object : EventChannel.StreamHandler {
                private var receiver: BroadcastReceiver? = null
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    val app = context.applicationContext
                    val listener = object : BroadcastReceiver() {
                        override fun onReceive(context: Context?, intent: Intent?) {
                            events.success(intent?.action)
                        }
                    }
                    val filter = IntentFilter().apply {
                        addAction(Intent.ACTION_MEDIA_MOUNTED)
                        addAction(Intent.ACTION_MEDIA_UNMOUNTED)
                        addAction(Intent.ACTION_MEDIA_EJECT)
                        addAction(Intent.ACTION_MEDIA_REMOVED)
                        addDataScheme("file")
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
                        app.registerReceiver(listener, filter, Context.RECEIVER_EXPORTED)
                    else app.registerReceiver(listener, filter)
                    receiver = listener
                }
                override fun onCancel(arguments: Any?) {
                    receiver?.let { context.applicationContext.unregisterReceiver(it) }
                    receiver = null
                }
            })
            MethodChannel(messenger, "kivo/storage").setMethodCallHandler { call, result ->
                if (call.method !in setOf("volumes", "list", "browse", "rescan", "scanRemovable", "thumbnail")) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                executor.execute {
                    try {
                        if (call.method == "rescan") {
                            browser.rescan(requireNotNull(call.argument<String>("path"))) {
                                post { result.success(null) }
                            }
                            return@execute
                        }
                        val value = when (call.method) {
                            "volumes" -> browser.volumes()
                            "list" -> browser.list(requireNotNull(call.argument<String>("path")))
                            "browse" -> browser.browse(requireNotNull(call.argument<String>("path")))
                            "scanRemovable" -> browser.scanRemovable()
                            else -> browser.thumbnail(requireNotNull(call.argument<String>("path")))
                        }
                        post { result.success(value) }
                    } catch (e: Exception) {
                        post { result.error(if (e is SecurityException) "ACCESS_DENIED" else "STORAGE_UNAVAILABLE", e.message, null) }
                    }
                }
            }
        }
    }
}
