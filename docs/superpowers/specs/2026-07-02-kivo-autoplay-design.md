# Kivo — Autoplay al siguiente video (Diseño)

**Fecha:** 2026-07-02
**Estado:** Diseño aprobado (mockup: overlay "Próximo" en tarjeta de esquina; modo sleep-timer "N episodios"; toggle de ajustes). Feature comprometida post-Hito 3.
**Contexto:** Hito 3 completo y verificado. `VideoSession` ya tiene `queue: List<String>` (URIs de la carpeta) + `index`, pero nada lo consume para reproducción — hoy el video termina y se pausa. Esta feature enciende el auto-avance y reactiva el modo "detener tras N episodios" del sleep timer que se sacó de 3b.

## 1. Comportamiento

- **Disparo:** cuando el video llega a su fin natural (nueva señal `PlaybackEngine.completedStream`), si autoplay está habilitado y hay un siguiente en la cola → avanza al siguiente.
- **Overlay "Próximo" (solo en primer plano, reproductor a pantalla completa):** tarjeta en la esquina inferior derecha con miniatura del siguiente, etiqueta "Próximo", nombre, un **anillo dorado de cuenta regresiva de 3 s**, y botones **Reproducir** (avanza ya) / **Cancelar** (no avanza, el video queda pausado al final). Al llegar a 0 → avanza.
- **Fondo / PiP:** avanza **inmediatamente sin overlay** (una tarjeta que no se ve no tiene sentido) — cubre "escuchar una playlist con pantalla apagada". Foreground vs background se determina por `AppLifecycleState`.
- **Alcance:** solo videos con cola de carpeta (abiertos desde biblioteca, `queue.length > 1`). Los abiertos por file-picker son cola de 1 → no hay siguiente. Al final de la cola (último video) → se detiene, sin overlay.
- **Configurable:** setting `autoplayNext` (`bool`, default `true`). El toggle de UI vivirá en el panel del Hito 4; por ahora el valor persiste y autoplay lo respeta (sin UI de toggle todavía — no hay pantalla de ajustes aún).
- **Precedencia (autoplay se suprime si):**
  1. **Bucle A-B activo** (`abLoopProvider != null` en fase `active`) — el bucle gana; al llegar a B salta a A, nunca al siguiente video.
  2. **Sleep timer que detiene en este video:** modo "al terminar el episodio" (`SleepTimerMode.episode`) → se detiene al final, no avanza. Un timer de duración fija que dispara a mitad pausa (no hay "completed", así que no hay autoplay de todos modos).
  3. Autoplay **off** en settings.
- **Límite de alcance conocido (v1):** autoplay opera mientras `PlayerScreen` esté vivo (pantalla completa, o app en segundo plano por Home, o PiP — en todos esos casos la ruta del reproductor sigue montada). **Minimizado al mini-player** (PlayerScreen destruido) NO avanza en esta versión — queda como mejora futura (requeriría mover el `engine.open` a un controlador app-level). Se documenta; no se promete.

## 2. Modo "Detener tras N episodios" (sleep timer)

Reactiva lo que se sacó de 3b. Nuevo `SleepTimerMode.episodes` con un contador `episodesLeft`:
- Panel del sleep timer: tercera tarjeta "Tras N episodios" con stepper (1–10, default 3), bajo "Al terminar el episodio".
- Cada vez que autoplay **avanza**, decrementa `episodesLeft`. Cuando llega a 0, en lugar de avanzar → detiene (pausa + cancela el timer). Es decir: "reproducir N videos más y parar".
- Coordinación: el chequeo de precedencia de autoplay consulta el sleep timer — si está en modo `episodes` y `episodesLeft <= 1`, la N-ésima terminación **detiene en vez de avanzar** (fade + pausa, reusa la ventana de aviso existente del sleep timer).

## 3. Arquitectura

**Motor:**
- `PlaybackEngine` gana `Stream<bool> get completedStream` → `MediaKitEngine` lo mapea de `_player.stream.completed`. `FakePlaybackEngine` lo espeja con `emitCompleted(bool)`.

**Cola / sesión (`lib/player/open/video_source.dart`):**
- `VideoSession` gana `final List<String> queueNames` (nombres por índice, paralelo a `queue`; opcional, default `const []` para no romper los cientos de `VideoSession(...)` de tests). Se puebla en `openInFolder` desde los `VideoItem.name`.
- `CurrentVideoNotifier`:
  - `VideoSession? peekNext()` — construye (sin mutar) la sesión del `index+1` si existe (`nextUri = queue[i+1]`, `nextName = queueNames[i+1]` con fallback `basenameOf(nextUri)`, misma `folder`, misma `queue`/`queueNames`, `index: i+1`); null si es el último o cola de 1.
  - `void advanceTo(VideoSession next)` — `state = next` (mismo efecto que un open normal para los observers: título en la notificación, etc.).

**Lógica pura de decisión (`lib/player/autoplay/autoplay_logic.dart`):**
- `bool shouldAutoplay({required bool enabled, required bool hasNext, required bool loopActive, required bool sleepStopsHere})` → `enabled && hasNext && !loopActive && !sleepStopsHere`. Testeable sin UI.
- `sleepStopsHere` = sleep timer en modo `episode` (siempre detiene al final) O en modo `episodes` con `episodesLeft <= 1`.

**Estado UI:**
- `autoplayPendingProvider` (`StateProvider<VideoSession?>`, en `lib/ui/player/state/autoplay_state.dart`) — la sesión "próxima" mientras el overlay cuenta; null si no hay overlay pendiente.

**PlayerScreen (dueño único del open — evita doble-open y races):**
- `ref.listen(completedStream-provider)` → `_onCompleted()`: computa `shouldAutoplay` (lee settings `autoplayNext`, `peekNext() != null`, `abLoopProvider`, sleep timer); si no aplica → nada. Si aplica:
  - Foreground (app resumed) → `autoplayPendingProvider = peekNext()` (el overlay muestra la cuenta de 3 s).
  - Background/PiP → `_advance(peekNext())` inmediato.
- `_advance(next)`: `advanceTo(next)` + limpiar `autoplayPendingProvider` + `_openSession(next)` (factorizar de `_start` la parte de abrir: `engine.open`, `setSubtitleStyle`, `_applyDefaultTracks`, `_resumeKey`, reset de overlays, re-`_armPip`) + notificar al sleep timer (decrementar `episodes`). El `VideoController` cacheado se reusa (no se recrea).
- `completedStream` como `StreamProvider<bool>` nuevo en `playback_provider.dart` (`completedProvider`), consistente con position/duration/playing.

**Overlay (`lib/ui/player/autoplay/autoplay_overlay.dart`):**
- `AutoplayOverlay` (ConsumerStatefulWidget) montado en el stack de `PlayerScreen` (oculto en PiP, como el resto). Watch `autoplayPendingProvider`; cuando no es null, muestra la tarjeta con un `AnimationController` de 3 s (anillo dorado) + miniatura (via `FrameExtractor.frameAt(Duration.zero)` del next, o placeholder). Al completar el ticker o tocar "Reproducir" → `_advance`; "Cancelar" → limpia el provider (sin avanzar). Estilo: tarjeta `rgba(10,14,26,0.92)` radio 16, dorado, mismo lenguaje que el popover del bucle A-B.

**Sleep timer (`lib/player/sleep/sleep_timer.dart`):**
- `SleepTimerMode.episodes` + `int episodesLeft` en `SleepTimerState`. `startEpisodes(int n)`. `void onAutoplayAdvance()` decrementa; el chequeo `sleepStopsHere` lo lee. Cuando la N-ésima terminación detiene, reusa la pausa+fade existente.

**Settings (`lib/core/settings/kivo_settings.dart`):** `autoplayNext` (`bool`, default `true`) en los 6 puntos de inserción.

## 4. Testing

- **Puro:** `shouldAutoplay` (matriz enabled/hasNext/loop/sleep); `peekNext` (siguiente correcto, null al final y en cola de 1, fallback de nombre); `advanceTo` cambia la sesión; `SleepTimerMode.episodes` decrementa y detiene en la N-ésima; `completedStream` mapea.
- **Widget:** el overlay aparece con `autoplayPendingProvider`, el anillo cuenta y al terminar avanza; "Cancelar" limpia sin avanzar; "Reproducir" avanza ya; el overlay se oculta en PiP; el panel de sleep timer muestra la tarjeta "Tras N episodios" y el stepper inicia el modo.
- **Device (Pixel 6):** un video de biblioteca que termina → overlay 3 s → siguiente arranca; "Cancelar" lo frena; con pantalla apagada (Home) avanza solo sin overlay; en PiP avanza y la ventanita pasa al siguiente; bucle A-B activo → no avanza (loopea); "al terminar el episodio" (sleep) → para al final; "tras 2 episodios" → reproduce 2 y para; último de la carpeta → se detiene; minimizado al mini-player → (v1) no avanza.

## Fuera de alcance

- Autoplay estando minimizado al mini-player (v1 — mejora futura).
- Reordenar/elegir la cola manualmente (playlist UI).
- Autoplay entre carpetas distintas (solo dentro de la carpeta actual).
- UI del toggle en ajustes (llega con el panel del Hito 4; el setting ya persiste y se respeta).
- Cierra la feature de autoplay; sigue Hito 4 (panel de personalización).
