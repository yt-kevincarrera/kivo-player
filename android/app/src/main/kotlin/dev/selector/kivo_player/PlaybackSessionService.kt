package dev.selector.kivo_player

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.media.session.MediaButtonReceiver
import java.util.concurrent.Executors

/**
 * Foreground mediaPlayback service: owns the MediaSessionCompat and the
 * MediaStyle notification while audio plays in the background. All state
 * comes from [PlaybackSessionHub]; all actions go back to Dart through it.
 */
class PlaybackSessionService : Service() {
    companion object {
        private const val CHANNEL_ID = "kivo_playback"
        private const val NOTIFICATION_ID = 1001
        @Volatile private var instance: PlaybackSessionService? = null

        fun start(context: Context) {
            if (instance != null) { refresh(); return }
            val intent = Intent(context, PlaybackSessionService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun refresh() = instance?.updateFromHub()

        fun stop(context: Context) {
            instance?.let {
                // Boolean overload works on every supported API level (minSdk 21);
                // stopForeground(int) only exists from API 24.
                @Suppress("DEPRECATION")
                it.stopForeground(true)
                it.stopSelf()
            }
        }
    }

    private var session: MediaSessionCompat? = null

    // Notification artwork: the video's own thumbnail, loaded off the main
    // thread and cached per media uri.
    private val artExecutor = Executors.newSingleThreadExecutor()
    @Volatile private var artUri: String? = null
    @Volatile private var artBitmap: Bitmap? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createChannel()
        session = MediaSessionCompat(this, "KivoSession").apply {
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() = PlaybackSessionHub.invokeDart("play")
                override fun onPause() = PlaybackSessionHub.invokeDart("pause")
                override fun onSeekTo(pos: Long) =
                    PlaybackSessionHub.invokeDart("seekTo", mapOf("ms" to pos))
                override fun onRewind() =
                    PlaybackSessionHub.invokeDart("skip", mapOf("seconds" to -10))
                override fun onFastForward() =
                    PlaybackSessionHub.invokeDart("skip", mapOf("seconds" to 10))
                override fun onStop() = PlaybackSessionHub.invokeDart("stop")
            })
            isActive = true
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        MediaButtonReceiver.handleIntent(session, intent)
        updateFromHub()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        session?.release()
        session = null
        instance = null
        artExecutor.shutdown()
        super.onDestroy()
    }

    private fun ensureArtwork() {
        val uri = PlaybackSessionHub.mediaUri
        if (uri.isEmpty() || uri == artUri) return
        artUri = uri
        artBitmap = null
        artExecutor.submit {
            val bmp = try {
                val r = MediaMetadataRetriever()
                try {
                    if (uri.startsWith("content://")) {
                        r.setDataSource(this, Uri.parse(uri))
                    } else {
                        r.setDataSource(uri)
                    }
                    r.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                } finally {
                    r.release()
                }
            } catch (_: Exception) {
                null
            }
            // Only publish if the uri is still current, then repaint.
            if (artUri == uri) {
                artBitmap = bmp
                PlaybackSessionHub.runOnMain { updateFromHub() }
            }
        }
    }

    fun updateFromHub() {
        val s = session ?: return
        ensureArtwork()
        val playing = PlaybackSessionHub.playing
        s.setMetadata(
            MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, PlaybackSessionHub.title)
                .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, PlaybackSessionHub.durationMs)
                .apply { artBitmap?.let { putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, it) } }
                .build()
        )
        s.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(
                    PlaybackStateCompat.ACTION_PLAY or
                        PlaybackStateCompat.ACTION_PAUSE or
                        PlaybackStateCompat.ACTION_PLAY_PAUSE or
                        PlaybackStateCompat.ACTION_SEEK_TO or
                        PlaybackStateCompat.ACTION_REWIND or
                        PlaybackStateCompat.ACTION_FAST_FORWARD or
                        PlaybackStateCompat.ACTION_STOP
                )
                .setState(
                    if (playing) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED,
                    PlaybackSessionHub.positionMs,
                    if (playing) 1.0f else 0.0f
                )
                .build()
        )
        val notification = buildNotification(playing)
        // ALWAYS enter the foreground first: this service is started with
        // startForegroundService, and Android kills the process if a start
        // isn't matched by a startForeground within ~5s — a pause arriving
        // in the window before onStartCommand (sleep timer firing, a call,
        // the user pausing instantly) must not skip it.
        startForeground(NOTIFICATION_ID, notification)
        if (!playing) {
            // Paused: detach so the notification stays but can be swiped away.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_DETACH)
            } else {
                @Suppress("DEPRECATION") stopForeground(false)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(playing: Boolean): Notification {
        val contentIntent = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }
        val deleteIntent = MediaButtonReceiver.buildMediaButtonPendingIntent(
            this, PlaybackStateCompat.ACTION_STOP
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setLargeIcon(artBitmap)
            .setContentTitle(PlaybackSessionHub.title)
            .setContentText(if (playing) "Reproduciendo" else "En pausa")
            .setContentIntent(contentIntent)
            .setDeleteIntent(deleteIntent)
            .setOngoing(playing)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(
                android.R.drawable.ic_media_rew, "-10s",
                MediaButtonReceiver.buildMediaButtonPendingIntent(this, PlaybackStateCompat.ACTION_REWIND)
            )
            .addAction(
                if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                if (playing) "Pausa" else "Reproducir",
                MediaButtonReceiver.buildMediaButtonPendingIntent(this, PlaybackStateCompat.ACTION_PLAY_PAUSE)
            )
            .addAction(
                android.R.drawable.ic_media_ff, "+10s",
                MediaButtonReceiver.buildMediaButtonPendingIntent(this, PlaybackStateCompat.ACTION_FAST_FORWARD)
            )
            .setStyle(
                androidx.media.app.NotificationCompat.MediaStyle()
                    .setMediaSession(session?.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2)
            )
            .build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Reproducción", NotificationManager.IMPORTANCE_LOW
            )
            channel.setShowBadge(false)
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }
}
