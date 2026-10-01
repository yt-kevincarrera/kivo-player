package dev.selector.kivo_player

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedInputStream
import java.io.File
import java.io.FileInputStream
import java.io.InputStream
import java.io.OutputStream
import java.net.ServerSocket
import java.net.Socket
import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

/**
 * `kivo/cast`: the native half of "Enviar a la TV" (DLNA). Dart finds the TV
 * and drives it over UPnP; this side does what only Android can:
 *
 * - **serve** the video to the TV over HTTP, straight from the
 *   ContentResolver (a `content://` uri) or a file path, with byte ranges so
 *   the TV can seek;
 * - hold the **multicast lock** while Dart searches (Android drops multicast
 *   without it);
 * - **keep alive** while casting: a foreground service with a "Enviando a…"
 *   notification and a stop action, plus wake and Wi-Fi locks, so the stream
 *   does not die with the screen off.
 */
object CastBridge {
    private var channel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())
    private var multicastLock: WifiManager.MulticastLock? = null
    private var server: CastHttpServer? = null

    fun attach(messenger: BinaryMessenger, context: Context) {
        val app = context.applicationContext
        channel = MethodChannel(messenger, "kivo/cast").apply {
            setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "multicastLock" -> {
                            setMulticast(app, call.argument<Boolean>("on") == true)
                            result.success(null)
                        }
                        "serve" -> {
                            val source = call.argument<String>("source")!!
                            result.success(serve(app, source))
                        }
                        "stopServing" -> {
                            server?.stop()
                            server = null
                            result.success(null)
                        }
                        "keepAlive" -> {
                            if (call.argument<Boolean>("on") == true) {
                                CastService.start(app, call.argument<String>("device") ?: "")
                            } else {
                                CastService.stop(app)
                            }
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("cast", e.message, null)
                }
            }
        }
    }

    /** The notification's stop action: Dart ends the cast (and the service). */
    fun requestStop() = main.post { channel?.invokeMethod("stopRequested", null) }

    private fun setMulticast(context: Context, on: Boolean) {
        if (on) {
            if (multicastLock?.isHeld == true) return
            val wifi = context.getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock = wifi.createMulticastLock("kivo-cast").apply {
                setReferenceCounted(false)
                acquire()
            }
        } else {
            multicastLock?.let { if (it.isHeld) it.release() }
            multicastLock = null
        }
    }

    private fun serve(context: Context, source: String): Map<String, Any> {
        val src = CastSource.open(context, source)
        val s = server ?: CastHttpServer().also { it.start(); server = it }
        val path = s.publish(src)
        return mapOf("port" to s.port, "path" to path, "mime" to src.mime, "size" to src.size)
    }
}

/** One thing the server can hand out: how to (re)open it, its size and type. */
class CastSource(
    val size: Long,
    val mime: String,
    val ext: String,
    private val opener: () -> InputStream,
) {
    fun open(): InputStream = opener()

    companion object {
        fun open(context: Context, source: String): CastSource {
            val isUri = source.startsWith("content://") || source.startsWith("file://")
            val ext = (if (isUri) Uri.parse(source).lastPathSegment else source)
                ?.substringAfterLast('.', "")?.lowercase().orEmpty()
            return if (source.startsWith("content://")) {
                val uri = Uri.parse(source)
                // statSize is -1 for some providers: ask the provider instead,
                // and serve without a length (and so without ranges) if it
                // does not know either.
                val size = context.contentResolver.openFileDescriptor(uri, "r")!!
                    .use { it.statSize }
                    .takeIf { it >= 0 }
                    ?: queriedSize(context, uri)
                val mime = context.contentResolver.getType(uri)?.takeIf { it.startsWith("video/") }
                    ?: mimeFor(ext)
                CastSource(size, mime, ext.ifEmpty { "mp4" }) {
                    context.contentResolver.openInputStream(uri)!!
                }
            } else {
                val file = File(if (source.startsWith("file://")) Uri.parse(source).path!! else source)
                CastSource(file.length(), mimeFor(ext), ext.ifEmpty { "mp4" }) { FileInputStream(file) }
            }
        }

        private fun queriedSize(context: Context, uri: Uri): Long = try {
            context.contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)
                ?.use { c -> if (c.moveToFirst() && !c.isNull(0)) c.getLong(0) else -1L } ?: -1L
        } catch (e: Exception) {
            -1L
        }

        fun mimeFor(ext: String): String = when (ext) {
            "mkv" -> "video/x-matroska"
            "webm" -> "video/webm"
            "avi" -> "video/x-msvideo"
            "mov" -> "video/quicktime"
            "ts", "m2ts", "mts" -> "video/mp2t"
            "3gp" -> "video/3gpp"
            "wmv" -> "video/x-ms-wmv"
            "flv" -> "video/x-flv"
            else -> MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
                ?.takeIf { it.startsWith("video/") } ?: "video/mp4"
        }
    }
}

/**
 * A minimal HTTP/1.1 server for the TV: GET and HEAD on the one published
 * path, with `Range: bytes=` support, DLNA's streaming headers, and nothing
 * else (every other path is a 404). The path carries a random token, so only
 * the TV Kivo told about it can fetch the video. One connection per request.
 */
class CastHttpServer {
    private var socket: ServerSocket? = null
    private val pool = Executors.newCachedThreadPool()
    @Volatile private var published: Pair<String, CastSource>? = null
    private val clients = ConcurrentHashMap.newKeySet<Socket>()
    val port: Int get() = socket?.localPort ?: 0

    fun start() {
        val s = ServerSocket(0)
        socket = s
        Thread({
            while (!s.isClosed) {
                val client = try { s.accept() } catch (e: Exception) { break }
                try {
                    pool.execute { handle(client) }
                } catch (e: RejectedExecutionException) {
                    // Stopped between accept() and here.
                    try { client.close() } catch (_: Exception) {}
                    break
                }
            }
        }, "kivo-cast-http").apply { isDaemon = true }.start()
    }

    fun publish(src: CastSource): String {
        val bytes = ByteArray(16).also { SecureRandom().nextBytes(it) }
        val token = bytes.joinToString("") { "%02x".format(it) }
        val path = "/v/$token.${src.ext}"
        published = path to src
        return path
    }

    fun stop() {
        published = null
        try { socket?.close() } catch (_: Exception) {}
        // A stream in progress blocks on socket I/O, which shutdownNow()
        // cannot interrupt: closing the sockets ends it, so a stopped cast
        // really stops sending.
        for (c in clients) try { c.close() } catch (_: Exception) {}
        clients.clear()
        pool.shutdownNow()
    }

    private fun handle(client: Socket) {
        clients.add(client)
        client.use { sock ->
            try {
                sock.soTimeout = 30_000
                val input = BufferedInputStream(sock.getInputStream())
                val requestLine = readLine(input) ?: return
                val headers = mutableMapOf<String, String>()
                while (true) {
                    val line = readLine(input) ?: break
                    if (line.isEmpty()) break
                    val i = line.indexOf(':')
                    if (i > 0) headers[line.substring(0, i).trim().lowercase()] = line.substring(i + 1).trim()
                }
                val parts = requestLine.split(' ')
                val method = parts.getOrNull(0) ?: ""
                val path = parts.getOrNull(1)?.substringBefore('?') ?: ""
                val out = sock.getOutputStream()
                val pub = published
                if (pub == null || path != pub.first || (method != "GET" && method != "HEAD")) {
                    writeHead(out, "404 Not Found", mapOf("Content-Length" to "0"))
                    return
                }
                serve(out, method == "HEAD", headers["range"], pub.second)
            } catch (_: Exception) {
                // The TV hung up mid-stream (a seek, a stop): nothing to do.
            } finally {
                clients.remove(sock)
            }
        }
    }

    private fun serve(out: OutputStream, headOnly: Boolean, range: String?, src: CastSource) {
        val size = src.size
        val common = linkedMapOf(
            "Content-Type" to src.mime,
            "transferMode.dlna.org" to "Streaming",
            "contentFeatures.dlna.org" to
                "DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000",
            "Connection" to "close",
        )
        if (size < 0) {
            // Unknown length: the whole stream, no ranges, no Content-Length.
            common["Accept-Ranges"] = "none"
            writeHead(out, "200 OK", common)
            if (!headOnly) src.open().use { copy(it, out, Long.MAX_VALUE) }
            return
        }
        common["Accept-Ranges"] = "bytes"
        val (start, end) = parseRange(range, size)
        if (start < 0) {
            writeHead(out, "416 Range Not Satisfiable",
                mapOf("Content-Range" to "bytes */$size", "Content-Length" to "0"))
            return
        }
        val length = end - start + 1
        common["Content-Length"] = length.toString()
        val status = if (range != null) {
            common["Content-Range"] = "bytes $start-$end/$size"
            "206 Partial Content"
        } else {
            "200 OK"
        }
        if (headOnly) {
            writeHead(out, status, common)
            return
        }
        src.open().use { input ->
            // Position BEFORE answering: a short skip must not send the
            // wrong bytes under a right-looking Content-Range.
            if (!skipFully(input, start)) {
                writeHead(out, "416 Range Not Satisfiable",
                    mapOf("Content-Range" to "bytes */$size", "Content-Length" to "0"))
                return
            }
            writeHead(out, status, common)
            copy(input, out, length)
        }
    }

    /** skip() may stop short; reading the rest is the fallback. */
    private fun skipFully(input: InputStream, n: Long): Boolean {
        var left = n
        while (left > 0) {
            val skipped = input.skip(left)
            if (skipped > 0) { left -= skipped; continue }
            if (input.read() < 0) return false
            left--
        }
        return true
    }

    private fun copy(input: InputStream, out: OutputStream, max: Long) {
        val buf = ByteArray(64 * 1024)
        var left = max
        while (left > 0) {
            val n = input.read(buf, 0, minOf(buf.size.toLong(), left).toInt())
            if (n < 0) break
            out.write(buf, 0, n)
            left -= n
        }
        out.flush()
    }

    /** [start, end] for a `bytes=` range (inclusive); start = -1 if unsatisfiable. */
    private fun parseRange(header: String?, size: Long): Pair<Long, Long> {
        if (header == null || !header.startsWith("bytes=")) return 0L to size - 1
        val spec = header.removePrefix("bytes=").substringBefore(',').trim()
        val dash = spec.indexOf('-')
        if (dash < 0) return 0L to size - 1
        val a = spec.substring(0, dash).trim()
        val b = spec.substring(dash + 1).trim()
        return when {
            a.isEmpty() && b.isNotEmpty() -> { // the last N bytes
                val n = b.toLongOrNull() ?: return 0L to size - 1
                if (n <= 0L || size == 0L) return -1L to -1L
                maxOf(0L, size - n) to size - 1
            }
            else -> {
                val s = a.toLongOrNull() ?: return 0L to size - 1
                if (s >= size) return -1L to -1L
                val e = b.toLongOrNull()?.coerceAtMost(size - 1) ?: (size - 1)
                if (e < s) -1L to -1L else s to e
            }
        }
    }

    private fun writeHead(out: OutputStream, status: String, headers: Map<String, String>) {
        val sb = StringBuilder("HTTP/1.1 $status\r\n")
        for ((k, v) in headers) sb.append(k).append(": ").append(v).append("\r\n")
        sb.append("\r\n")
        out.write(sb.toString().toByteArray(Charsets.ISO_8859_1))
    }

    private fun readLine(input: InputStream): String? {
        val sb = StringBuilder()
        while (true) {
            val c = input.read()
            if (c < 0) return if (sb.isEmpty()) null else sb.toString()
            if (c == '\n'.code) return sb.toString().trimEnd('\r')
            sb.append(c.toChar())
            if (sb.length > 8192) return null
        }
    }
}

/**
 * Keeps the process (and so the HTTP server and Dart's UPnP polling) alive
 * while a video plays on the TV, and gives the user a way to stop it from
 * the notification shade.
 */
class CastService : Service() {
    companion object {
        private const val CHANNEL_ID = "kivo_cast"
        private const val NOTIFICATION_ID = 1002
        private const val ACTION_STOP = "dev.selector.kivo_player.CAST_STOP"
        private const val EXTRA_DEVICE = "device"

        fun start(context: Context, device: String) {
            val intent = Intent(context, CastService::class.java).putExtra(EXTRA_DEVICE, device)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CastService::class.java))
        }
    }

    private var wake: PowerManager.WakeLock? = null
    private var wifi: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            CastBridge.requestStop()
            return START_NOT_STICKY
        }
        val device = intent?.getStringExtra(EXTRA_DEVICE).orEmpty()
        createChannel()
        val notification = notification(device)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        acquireLocks()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        wake?.let { if (it.isHeld) it.release() }
        wifi?.let { if (it.isHeld) it.release() }
        super.onDestroy()
    }

    private fun acquireLocks() {
        if (wake?.isHeld != true) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wake = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "kivo:cast").apply {
                setReferenceCounted(false)
                acquire(6 * 60 * 60 * 1000L) // a long film, with a ceiling
            }
        }
        if (wifi?.isHeld != true) {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            @Suppress("DEPRECATION")
            wifi = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "kivo:cast").apply {
                setReferenceCounted(false)
                acquire()
            }
        }
    }

    private fun notification(device: String): Notification {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val stop = PendingIntent.getService(this, 0,
            Intent(this, CastService::class.java).setAction(ACTION_STOP), flags)
        val open = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(this, 0, it, flags)
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_kivo)
            .setContentTitle(getString(R.string.cast_notification_title, device))
            .setContentText(getString(R.string.cast_notification_text))
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(0, getString(R.string.cast_notification_stop), stop)
            .build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        nm.createNotificationChannel(NotificationChannel(
            CHANNEL_ID, getString(R.string.cast_channel_name), NotificationManager.IMPORTANCE_LOW))
    }
}
