# Kivo — Hito 4e: autoplay estando minimizado (diseño)

**Fecha:** 2026-07-06
**Estado:** Diseño aprobado por el usuario (enfoque + decisiones); arrancar directo.
**Contexto:** Hoy la lógica de terminación→avance (`_onCompleted`/`_advance`) vive en `PlayerScreen`, que se **destruye al minimizar** (el swipe/back hace `Navigator.pop` → `dispose` → `engine.pause`). El mini-player permite reanudar; si el video termina **estando minimizado**, la cola NO avanza (nadie escucha la terminación). 4e lo arregla con un coordinador a nivel de app que maneja **solo** el caso minimizado.

## 1. Decisiones (confirmadas)

- **Enfoque:** coordinador app-level que actúa **solo cuando está minimizado**; `PlayerScreen` queda intacto para el caso expandido (su `_onCompleted`/overlay "Próximo"). Sin doble-avance: al minimizar, `PlayerScreen` está destruido, así que su listener no corre. Se extrae un helper compartido para no duplicar la selección de pistas.
- **Miniatura del mini-player al avanzar minimizado:** capturar el **primer frame** del nuevo video (best-effort; si falla, placeholder).
- Minimizado avanza **directo** (sin overlay "Próximo", que es solo foreground) y **reproduciendo** (continúa la cadena).

## 2. Arquitectura

- **Nuevo `lib/player/autoplay/autoplay_coordinator.dart`:** `autoplayCoordinatorProvider` (Provider, instanciado una vez por `KivoApp` — igual que `backgroundPlaybackProvider`). En `init()` hace `ref.listen(completedProvider, ...)`.
  - `_onCompleted()`: si `!ref.read(playerMinimizedProvider)` → **return** (expandido; lo maneja `PlayerScreen`). Guard de re-entrancia `_advancing`. Luego, misma decisión que foreground: `loopActive = abLoopProvider.phase == active`; `sleepStop = sleepStopsHere(sleepTimer)`; `next = currentVideoProvider.notifier.peekNext()`; `go = shouldAutoplay(enabled: settings.autoplayNext, hasNext: next != null, loopActive: loopActive, sleepStopsHere: sleepStop)`. Si `!go`: si `sleepStop && next != null && settings.autoplayNext && !loopActive` → `engine.pause()` + `sleepTimer.cancel()`; return. Si `go` → `_advanceMinimized(next!)`.
  - `_advanceMinimized(next)`: `_advancing=true`; `sleepTimer.onAutoplayAdvance()`; `currentVideoProvider.notifier.advanceTo(next)`; `plan = planResume(resume.positionFor(next.resumeKey), settings.resumeBehavior)`; `await engine.open(next.playbackPath, startAt: plan.startAt)`; `await engine.play()`; `applyDefaultTracks(...)` (fire-and-forget); `_refreshMiniThumb(next.playbackPath)`; `finally _advancing=false`. (Sin resume-prompt, sin PiP arm, sin VideoController — no hay UI de PlayerScreen.)
  - `_refreshMiniThumb(path)`: `frames.prepare(path); final b = await frames.frameAt(Duration.zero); if (b != null) miniPlayerThumbnailProvider.state = b;` (best-effort en try/catch).
- **Extracción compartida:** mover `PlayerScreen._applyDefaultTracks` a una función top-level `applyDefaultTracks({required PlaybackEngine engine, required KivoSettings settings, required VideoSession session, required SubtitleFinder subtitleFinder})` en `lib/player/tracks/apply_default_tracks.dart`. `PlayerScreen._openSession` pasa a llamarla (con `ref.read(subtitleFinderProvider)`), y el coordinador también. Comportamiento idéntico (refactor).
- **`KivoApp`** (`app.dart`): `ref.watch(autoplayCoordinatorProvider)` para instanciarlo (junto al `backgroundPlaybackProvider` existente).

## 3. Interacciones cuidadas

- **Sin doble-avance:** expandido → PlayerScreen; minimizado → coordinador (PlayerScreen destruido). El guard `!minimized → return` lo garantiza.
- **Sleep "N episodios":** `onAutoplayAdvance()` se llama en el avance minimizado igual que en foreground; `sleepStopsHere` frena el avance y pausa cuando toca.
- **Mini-player se actualiza solo:** observa `currentVideoProvider` (título) y los streams de playing/posición/duración; `advanceTo` + `engine.open/play` los refresca. La miniatura se refresca explícitamente (§2).
- **Resume:** al avanzar, el nuevo video respeta `resumeBehavior` vía `planResume` (arranca en su posición guardada si aplica), sin prompt. El progreso del que termina lo guarda el timer del mini-player (ya existente).
- **A-B loop activo:** `shouldAutoplay` devuelve false si `loopActive` → no avanza (el loop sigue su curso).
- **Último video sin siguiente:** `next == null` → no avanza; el mini-player queda mostrando el video terminado en pausa.

## 4. Testing

- **Refactor `apply_default_tracks`:** los tests existentes del track picker + apertura siguen verdes (comportamiento idéntico).
- **Coordinador (`autoplay_coordinator_test.dart`):** con fakes (FakePlaybackEngine con `completedStream`, `currentVideoProvider` sembrado con cola de 2, `playerMinimizedProvider`):
  - minimizado + autoplayNext on + hay siguiente + emitir completed → `engine.lastOpened == next.playbackPath` y `currentVideoProvider.index` avanzó y se llamó play.
  - NO minimizado + completed → no avanza (engine no abre otro).
  - autoplayNext off + minimizado + completed → no avanza.
  - último video (sin siguiente) + minimizado + completed → no avanza.
  - sleep "N episodios" con stop-aquí → pausa en vez de avanzar.
- `flutter analyze` limpio + suite verde (actual: 317).
- **Device (Pixel 6):** abrir un video, minimizar, dar play en la mini-barra, dejar que termine → **avanza al siguiente** en el mini-player (título + miniatura actualizados, sigue reproduciendo); expandir a mitad y confirmar que sigue el video correcto; en foreground el autoplay con overlay "Próximo" sigue igual; sleep "N episodios" minimizado frena donde debe.

## 5. Descomposición del plan

1. Extraer `applyDefaultTracks` a `lib/player/tracks/apply_default_tracks.dart`; `PlayerScreen._openSession` la usa (refactor sin cambios de comportamiento). Tests existentes verdes.
2. `AutoplayCoordinator` + `autoplayCoordinatorProvider` + wiring en `KivoApp` + refresco de miniatura + tests.

## Fuera de alcance

- Cambiar el caso foreground (overlay "Próximo") — intacto.
- Avanzar mientras la app está en **segundo plano total** (pantalla apagada / otra app): fuera; 4e cubre minimizado con la app en primer plano (mini-player visible). (El audio en background ya sigue vía el coordinador de sesión; el auto-avance en background total es una posible mejora futura.)
- Unificar todo el engine-open en un solo dueño (refactor mayor descartado).
