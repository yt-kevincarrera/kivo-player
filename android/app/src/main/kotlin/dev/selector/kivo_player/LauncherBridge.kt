package dev.selector.kivo_player

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Size
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executor

/**
 * `kivo/launch`: Kivo's surfaces outside the app — the launcher shortcuts
 * (long-press the icon) and the "Continuar viendo" home-screen widget — fed
 * from Dart's "Continuar viendo" list, and the taps that come back from them
 * (an intent carrying a MediaStore id, forwarded to Dart).
 */
object LauncherBridge {
    const val ACTION_OPEN_VIDEO = "dev.selector.kivo_player.OPEN_VIDEO"
    const val EXTRA_VIDEO_ID = "videoId"
    private const val PREFS = "kivo_continue"
    private const val KEY_ENTRIES = "entries"
    private const val THUMB_DIR = "continue-thumbs"

    private var channel: MethodChannel? = null
    private var pendingId: String? = null
    // The Dart side lives as long as the process (KivoApplication caches the
    // engine), and asks for the launch request once, at isolate start. After
    // that, a request has to be pushed to it, not stored for an ask that will
    // never come again — or a tap with the process already alive (backed out,
    // background playback, a launcher that recreates the activity) is lost.
    private var dartReady = false

    fun attach(messenger: BinaryMessenger, context: Context, executor: Executor) {
        val main = Handler(Looper.getMainLooper())
        channel = MethodChannel(messenger, "kivo/launch").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialVideo" -> {
                        dartReady = true
                        result.success(pendingId)
                        pendingId = null
                    }
                    "updateContinue" -> {
                        @Suppress("UNCHECKED_CAST")
                        val raw = call.arguments as? List<Map<String, Any?>> ?: emptyList()
                        executor.execute {
                            try {
                                update(context, raw)
                            } catch (e: Exception) {
                                android.util.Log.w("kivo/launch", "update failed: ${e.message}")
                            }
                            main.post { result.success(null) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /** An open request from a launch/new intent; null if the intent is not one. */
    fun videoIdOf(intent: Intent?): String? {
        if (intent?.action != ACTION_OPEN_VIDEO) return null
        // Reopened from Recents: the system replays the intent the task was
        // started with — that old tap must not reopen its video again.
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return null
        return intent.getStringExtra(EXTRA_VIDEO_ID)
    }

    /** The intent that started (or restarted) the activity. */
    fun onLaunchIntent(intent: Intent?) = deliver(videoIdOf(intent))

    /** A tap while the activity is already on top (singleTop). */
    fun onNewIntent(intent: Intent?) = deliver(videoIdOf(intent))

    private fun deliver(id: String?) {
        if (id == null) return
        val ch = channel
        if (dartReady && ch != null) ch.invokeMethod("openVideo", id) else pendingId = id
    }

    fun openIntent(context: Context, id: String): Intent =
        Intent(context, MainActivity::class.java)
            .setAction(ACTION_OPEN_VIDEO)
            .putExtra(EXTRA_VIDEO_ID, id)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)

    private fun update(context: Context, raw: List<Map<String, Any?>>) {
        val entries = JSONArray()
        val thumbs = File(context.filesDir, THUMB_DIR).apply { mkdirs() }
        val keep = mutableSetOf<String>()
        val shortcuts = mutableListOf<ShortcutInfoCompat>()
        for ((rank, m) in raw.withIndex()) {
            val id = m["id"] as? String ?: continue
            val uri = m["uri"] as? String ?: continue
            val name = m["name"] as? String ?: ""
            entries.put(JSONObject().apply {
                put("id", id)
                put("name", name)
                put("position", m["position"] as? String ?: "")
                put("fraction", (m["fraction"] as? Number)?.toDouble() ?: 0.0)
            })
            val thumbFile = File(thumbs, "$id.png")
            keep += thumbFile.name
            val bitmap = thumbnail(context, uri, id)
            if (bitmap != null) {
                thumbFile.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 90, it) }
            }
            val icon = bitmap?.let { IconCompat.createWithBitmap(squareCrop(it)) }
                ?: IconCompat.createWithResource(context, R.mipmap.ic_launcher)
            shortcuts += ShortcutInfoCompat.Builder(context, "continue_$id")
                .setShortLabel(name.take(24).ifEmpty { context.getString(R.string.widget_label) })
                .setLongLabel(name.take(60).ifEmpty { context.getString(R.string.widget_label) })
                .setIcon(icon)
                .setRank(rank)
                .setIntent(openIntent(context, id))
                .build()
        }
        thumbs.listFiles()?.filter { it.name !in keep }?.forEach { it.delete() }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY_ENTRIES, entries.toString()).apply()
        try {
            ShortcutManagerCompat.setDynamicShortcuts(context, shortcuts)
        } catch (e: Exception) {
            // Rate- or count-limited by the launcher: the widget still updates.
            android.util.Log.w("kivo/launch", "shortcuts not updated: ${e.message}")
        }
        ContinueWidgetProvider.updateAll(context)
    }

    fun entries(context: Context): List<JSONObject> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_ENTRIES, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { arr.getJSONObject(it) }
        } catch (e: Exception) {
            emptyList()
        }
    }

    fun thumbFile(context: Context, id: String) =
        File(File(context.filesDir, THUMB_DIR), "$id.png")

    private fun thumbnail(context: Context, uri: String, id: String): Bitmap? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            context.contentResolver.loadThumbnail(Uri.parse(uri), Size(480, 270), null)
        } else {
            @Suppress("DEPRECATION")
            MediaStore.Video.Thumbnails.getThumbnail(
                context.contentResolver, id.toLong(),
                MediaStore.Video.Thumbnails.MINI_KIND, null)
        }
    } catch (e: Exception) {
        null
    }

    /** Launcher icons are square; a 16:9 frame is centre-cropped, not squashed. */
    private fun squareCrop(b: Bitmap): Bitmap {
        val side = minOf(b.width, b.height)
        return Bitmap.createBitmap(b, (b.width - side) / 2, (b.height - side) / 2, side, side)
    }
}

/** The "Continuar viendo" widget: the newest unfinished video, one tap away. */
class ContinueWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, views(context))
    }

    companion object {
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, ContinueWidgetProvider::class.java))
            if (ids.isEmpty()) return
            val v = views(context)
            for (id in ids) manager.updateAppWidget(id, v)
        }

        private fun views(context: Context): RemoteViews {
            val v = RemoteViews(context.packageName, R.layout.widget_continue)
            val first = LauncherBridge.entries(context).firstOrNull()
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            if (first == null) {
                v.setViewVisibility(R.id.widget_content, View.GONE)
                v.setViewVisibility(R.id.widget_empty, View.VISIBLE)
                val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
                if (launch != null) {
                    v.setOnClickPendingIntent(R.id.widget_root,
                        PendingIntent.getActivity(context, 0, launch, flags))
                }
                return v
            }
            val id = first.getString("id")
            v.setViewVisibility(R.id.widget_content, View.VISIBLE)
            v.setViewVisibility(R.id.widget_empty, View.GONE)
            v.setTextViewText(R.id.widget_title, first.optString("name"))
            v.setTextViewText(R.id.widget_subtitle,
                context.getString(R.string.widget_continue_at, first.optString("position")))
            v.setProgressBar(R.id.widget_progress, 1000,
                (first.optDouble("fraction", 0.0) * 1000).toInt().coerceIn(0, 1000), false)
            val thumb = LauncherBridge.thumbFile(context, id)
            if (thumb.exists()) {
                BitmapFactory.decodeFile(thumb.absolutePath)?.let {
                    v.setImageViewBitmap(R.id.widget_thumb, it)
                }
            } else {
                v.setImageViewResource(R.id.widget_thumb, R.drawable.widget_placeholder)
            }
            v.setOnClickPendingIntent(R.id.widget_root,
                PendingIntent.getActivity(context, id.hashCode(), LauncherBridge.openIntent(context, id), flags))
            return v
        }
    }
}
