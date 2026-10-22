package dev.selector.kivo_player.startup

/** Orders native channel registration and the first Dart execution on the main thread. */
internal object EngineStartup {
    /** Preparing the process-owned engine never starts Dart. */
    fun <E> prepare(createEngine: () -> E, configureProcessChannels: (E) -> Unit): E {
        val engine = createEngine()
        configureProcessChannels(engine)
        return engine
    }

    /** Activity channels are rebound on every attachment; the isolate starts only once. */
    fun <E> configureAndStart(
        engine: E,
        configureChannels: (E) -> Unit,
        isExecutingDart: (E) -> Boolean,
        executeDart: (E) -> Unit,
    ) {
        configureChannels(engine)
        if (!isExecutingDart(engine)) executeDart(engine)
    }
}
