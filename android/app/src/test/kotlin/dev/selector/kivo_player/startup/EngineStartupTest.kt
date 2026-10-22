package dev.selector.kivo_player.startup

import org.junit.Assert.*
import org.junit.Test

/** The first Dart callback invokes the same startup methods without any scheduling delay. */
class EngineStartupTest {
    private class Engine {
        val handlers = mutableMapOf<String, (String) -> Any?>()
        var running = false
        var executions = 0
        var firstSdk = -1
        var firstScan: Any? = null
        var onExecute: (() -> Unit)? = null

        fun execute() {
            executions++
            running = true
            onExecute?.invoke()
        }

        fun startupCalls() {
            // AndroidAppInstaller.androidSdk returns 0 when its method has no handler.
            firstSdk = handlers["kivo/update"]?.invoke("androidSdk") as? Int ?: 0
            firstScan = handlers["kivo/media"]?.invoke("scan")
                ?: error("No implementation found for method scan on channel kivo/media; androidSdk=$firstSdk")
        }
    }

    private val activityChannels = listOf(
        "kivo/subtitles", "kivo/orientation", "kivo/frames", "kivo/media",
        "kivo/vault", "kivo/volume", "kivo/media_session", "kivo/pip", "kivo/update",
    )

    private fun configureChannels(engine: Engine, activity: Int) {
        for (channel in activityChannels) {
            engine.handlers[channel] = { method ->
                when {
                    channel == "kivo/update" && method == "androidSdk" -> 37
                    channel == "kivo/media" && method == "scan" -> listOf("content://media/external/video/media/1")
                    else -> activity
                }
            }
        }
    }

    private fun attach(engine: Engine, activity: Int) {
        EngineStartup.configureAndStart(
            engine,
            configureChannels = { configureChannels(it, activity) },
            isExecutingDart = { it.running },
            executeDart = { it.execute() },
        )
    }

    @Test fun processPreparationRegistersBridgesWithoutStartingDart() {
        val created = Engine()
        val engine = EngineStartup.prepare(
            createEngine = { created },
            configureProcessChannels = {
                it.handlers["kivo/launch"] = { "pending-video" }
                it.handlers["kivo/cast"] = { "ready" }
            },
        )

        assertSame(created, engine)
        assertFalse(engine.running)
        assertEquals(0, engine.executions)
        assertEquals("pending-video", engine.handlers.getValue("kivo/launch")("initialVideo"))
        assertEquals("ready", engine.handlers.getValue("kivo/cast")("status"))
    }

    @Test fun firstDartExecutionCanImmediatelyReadSdkAndScan() {
        val engine = EngineStartup.prepare({ Engine() }) {
            it.handlers["kivo/launch"] = { "pending-video" }
            it.handlers["kivo/cast"] = { "ready" }
        }
        engine.onExecute = {
            engine.startupCalls()
            assertTrue(engine.handlers.keys.containsAll(activityChannels))
            assertEquals("pending-video", engine.handlers.getValue("kivo/launch")("initialVideo"))
        }

        attach(engine, 1)

        assertEquals(37, engine.firstSdk)
        assertEquals(listOf("content://media/external/video/media/1"), engine.firstScan)
        assertEquals(1, engine.executions)
    }

    @Test fun activityRecreationRebindsChannelsWithoutReplacingOrRestartingTheEngine() {
        var enginesCreated = 0
        var processBridgesAttached = 0
        val cached = EngineStartup.prepare(
            createEngine = { enginesCreated++; Engine() },
            configureProcessChannels = {
                processBridgesAttached++
                it.handlers["kivo/launch"] = { "pending-video" }
                it.handlers["kivo/cast"] = { "ready" }
            },
        )
        val processLaunchHandler = cached.handlers["kivo/launch"]
        val processCastHandler = cached.handlers["kivo/cast"]

        attach(cached, 1)
        val firstActivityHandler = cached.handlers["kivo/media_session"]
        attach(cached, 2)

        assertEquals(1, enginesCreated)
        assertEquals(1, processBridgesAttached)
        assertEquals(1, cached.executions)
        assertNotSame(firstActivityHandler, cached.handlers["kivo/media_session"])
        assertEquals(2, cached.handlers.getValue("kivo/media_session")("activity"))
        assertSame(processLaunchHandler, cached.handlers["kivo/launch"])
        assertSame(processCastHandler, cached.handlers["kivo/cast"])
    }

    @Test fun failedActivityConfigurationNeverStartsDartWithIncompleteChannels() {
        val engine = EngineStartup.prepare({ Engine() }) { }

        assertThrows(IllegalStateException::class.java) {
            EngineStartup.configureAndStart(
                engine,
                configureChannels = { error("Channel registration failed") },
                isExecutingDart = { it.running },
                executeDart = { it.execute() },
            )
        }

        assertFalse(engine.running)
        assertEquals(0, engine.executions)
    }
}
