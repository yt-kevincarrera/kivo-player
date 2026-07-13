package dev.selector.kivo_player

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor.DartEntrypoint

/// Creates ONE FlutterEngine at process start and caches it for the process
/// lifetime. MainActivity reuses this cached engine (see provideFlutterEngine)
/// and does NOT destroy it when the Activity is torn down.
///
/// Why: media_kit's mpv Player is a process-lifetime native object with its own
/// threads and an FFI "wake up Dart" callback. With the default per-Activity
/// engine, Android could destroy the Activity (and its Dart isolate) while the
/// foreground service kept the PROCESS — and therefore mpv's threads — alive.
/// The isolate death deleted the FFI callback, but a surviving mpv thread later
/// fired it → `SIGABRT: Callback invoked after it has been deleted`. Pinning the
/// engine/isolate to the process lifetime makes it match mpv's, so the callback
/// is valid for as long as mpv exists.
class KivoApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        val engine = FlutterEngine(this) // auto-registers plugins
        engine.dartExecutor.executeDartEntrypoint(DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
    }

    companion object {
        const val ENGINE_ID = "kivo_main_engine"
    }
}
