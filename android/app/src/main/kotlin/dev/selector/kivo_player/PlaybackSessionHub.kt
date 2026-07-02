package dev.selector.kivo_player

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * Process-wide hub between the Dart coordinator, the foreground service and
 * audio focus. MainActivity owns the MethodChannel and registers it here;
 * the service reads state and reports actions back through [invokeDart].
 */
object PlaybackSessionHub {
    @Volatile var channel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // Latest state pushed from Dart.
    @Volatile var title: String = "Kivo"
    @Volatile var positionMs: Long = 0
    @Volatile var durationMs: Long = 0
    @Volatile var playing: Boolean = false

    private var focusRequest: AudioFocusRequest? = null
    private var focusHeld = false

    fun invokeDart(method: String, args: Map<String, Any?>? = null) {
        mainHandler.post { channel?.invokeMethod(method, args) }
    }

    fun update(context: Context, title: String, positionMs: Long, durationMs: Long, playing: Boolean, inBackground: Boolean) {
        this.title = title
        this.positionMs = positionMs
        this.durationMs = durationMs
        this.playing = playing
        if (playing) requestFocus(context)
        if (inBackground && playing) {
            PlaybackSessionService.start(context)
        }
        PlaybackSessionService.refresh()
    }

    fun end(context: Context) {
        abandonFocus(context)
        PlaybackSessionService.stop(context)
    }

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS -> { focusHeld = false; invokeDart("focusLoss") }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> invokeDart("focusTransientLoss")
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> invokeDart("duckStart")
            AudioManager.AUDIOFOCUS_GAIN -> {
                // A gain after a duck ends the duck; after a transient loss it resumes.
                invokeDart("duckEnd")
                invokeDart("focusRegained")
            }
        }
    }

    private fun requestFocus(context: Context) {
        if (focusHeld) return
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val granted: Int
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                        .build()
                )
                .setOnAudioFocusChangeListener(focusListener)
                .build()
            focusRequest = req
            granted = am.requestAudioFocus(req)
        } else {
            @Suppress("DEPRECATION")
            granted = am.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
        }
        focusHeld = granted == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    private fun abandonFocus(context: Context) {
        if (!focusHeld) return
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { am.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            am.abandonAudioFocus(focusListener)
        }
        focusHeld = false
    }
}
