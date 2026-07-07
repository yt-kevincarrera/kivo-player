# Kivo — Bug 2: freeze al volver de segundo plano (proteger el proceso)

**Fecha:** 2026-07-07
**Estado:** Aprobado para plan
**Alcance:** Eliminar el freeze/ANR/SIGABRT que ocurre al dejar un video **pausado en segundo plano** el tiempo suficiente y volver. Enfoque **A** (elegido): mantener el proceso foreground-protegido mientras haya un video abierto (incluso pausado), para que Android no lo reclame parcialmente. NO se toca media_kit ni se dispone el engine (enfoque B, descartado por ahora).

---

## Causa raíz (confirmada 2026-07-07, evidencia de dispositivo)

El `Player` de mpv (media_kit) es un objeto nativo de por-vida-de-proceso (hilos propios + un callback FFI de wakeup) que **nunca se dispone** y está **desacoplado del ciclo de vida del isolate de Dart**. Cuando Android **reclama parcialmente** un proceso en background, **pausado** y **sin protección de foreground** (mata el isolate/hilo de UI o congela hilos dejando el mpv nativo a medias), ambos quedan desincronizados. Al volver:
- **SIGABRT:** el mpv nativo dispara su callback de wakeup contra el trampolín FFI de Dart ya borrado (`runtime_entry.cc:5122 Callback invoked after it has been deleted`; backtrace `abort → libflutter → [anon:FfiCallbackMetadata::TrampolinePage]`).
- **ANR:** un `mpv_set_property_string` síncrono desde Dart se bloquea para siempre en un condvar interno de mpv (`pthread_cond_wait`) que el worker congelado/muerto nunca señaliza → main thread trabado.

Un `am freeze`/thaw limpio **no** lo reproduce (el estado queda consistente); el disparador es el reclamo **parcial** bajo presión de memoria real (abrir muchas apps). Además: pausar antes de ir a background nunca crea sesión/FGS (`shouldHaveSession = _inBackground && _playing`), así que un video pausado en background hoy tiene **cero** protección de foreground → blanco ideal del reclamo.

**Estrategia del fix:** un foreground-service protegido es exento del *freezer* de apps en caché y de los últimos en morir; mantenerlo vivo mientras hay video abierto (playing o paused) elimina el reclamo parcial que desincroniza mpv. Si bajo presión extrema Android igual mata el FGS, es un kill **completo y limpio** → cold-start, no freeze.

## Componentes actuales relevantes

- `lib/player/background/background_playback.dart` — `BackgroundPlaybackCoordinator`: compuerta `shouldHaveSession` ([:131]), `_push` ([:124]), `_end` ([:148]), `didChangeAppLifecycleState` ([:109]).
- `android/.../PlaybackSessionHub.kt` — `update()` arranca el FGS sólo con `inBackground && playing` ([:39-50]); `channel` (`@Volatile`) nunca se anula.
- `android/.../PlaybackSessionService.kt` — `updateFromHub()` rama `!playing` hace `stopForeground(STOP_FOREGROUND_DETACH)` ([:199-213]).
- `android/.../MainActivity.kt` — `configureFlutterEngine` fija `PlaybackSessionHub.channel` ([:479]); `onDestroy` ([:568]) no lo anula; no hay `cleanUpFlutterEngine`.

## 1. Compuerta de sesión (Dart)

`background_playback.dart`:
- Cambiar la condición de `_push`:
  ```dart
  // antes: final shouldHaveSession = _inBackground && _playing && !pip;
  final shouldHaveSession = shouldHaveMediaSession(
    inBackground: _inBackground,
    hasVideo: _ref.read(currentVideoProvider) != null,
    inPip: _ref.read(pipModeProvider),
  );
  ```
- Extraer un helper **puro** testeable (en `background_playback.dart` o un archivo hermano):
  ```dart
  bool shouldHaveMediaSession({
    required bool inBackground,
    required bool hasVideo,
    required bool inPip,
  }) => inBackground && hasVideo && !inPip;
  ```
- El resto de `_push` no cambia: sigue seteando `_sessionActive = true` cuando corresponde y llamando `updateSession(..., playing: _playing, inBackground: _inBackground)`. Un video pausado en background ahora entra por la compuerta y crea/mantiene la sesión.
- `didChangeAppLifecycleState`: sin cambios de estructura — `paused` → `_inBackground=true; _push(force:true)`; `resumed` → `_inBackground=false; if (_sessionActive) _end(); if (_playing) acquireAudioFocus()`. (En foreground no hace falta notificación; `_end` la retira, como hoy.)
- El manejo de audio-focus no cambia (pausa = liberar focus; la protección FGS es independiente del focus).

## 2. Arranque del FGS (Kotlin)

`PlaybackSessionHub.update()`: arrancar el servicio siempre que `inBackground` (Dart ya sólo empuja updates de background cuando debe haber sesión), en vez de `inBackground && playing`:
```kotlin
// antes: if (inBackground && playing) PlaybackSessionService.start(context)
if (inBackground) PlaybackSessionService.start(context)
```
`start()` es idempotente (chequea `instance != null`). `refresh()` sigue igual.

## 3. No soltar la protección en pausa (Kotlin)

`PlaybackSessionService.updateFromHub()`: mientras el servicio exista (background + video), **siempre** mantenerse foreground — reproduciendo o pausado. Unificar las dos ramas para que la de pausa **no** haga `stopForeground(DETACH)`:
```kotlin
// Ambos estados (playing/paused) mantienen el servicio en foreground mientras exista.
if (!_foregrounded) {
  if (!safeStartForeground(notification)) return
  _foregrounded = true
} else {
  val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
  nm.notify(NOTIFICATION_ID, notification)
}
```
La notificación queda **ongoing/persistente** también en pausa. Ajustar `buildNotification` para que sea ongoing siempre (`setOngoing(true)`), ya que un FGS foreground implica notificación no descartable de todas formas. Los botones play/pausa/seek de la notificación permiten reanudar. El servicio se detiene (`PlaybackSessionService.stop`) sólo por la acción Stop de la notificación o por `_end()` (en resume) — sin cambios en esos caminos.

## 4. Guardas nativas (defensa en profundidad)

- `MainActivity`: anular `PlaybackSessionHub.channel = null` en `cleanUpFlutterEngine(flutterEngine)` (override) — se llama cuando el FlutterEngine se destruye/desasocia — para que un callback de audio-focus tardío no intente `invokeMethod` contra un `MethodChannel` de un engine muerto. Si `cleanUpFlutterEngine` no es el hook correcto en esta versión de Flutter embedding, hacerlo en `onDestroy` (verificar en implementación). `invokeDart` ya es null-safe (`channel?.invokeMethod`).
- Nota: esto endurece **nuestro** canal; el fix de peso contra el SIGABRT/ANR de mpv es §1–§3 (evitar el reclamo parcial).

## Unidades y límites

1. **`background_playback.dart`** — compuerta `shouldHaveMediaSession` (pura, testeable) + su uso.
2. **`PlaybackSessionHub.kt`** — arranque del FGS en background.
3. **`PlaybackSessionService.kt`** — foreground persistente en pausa (quitar el detach) + notificación ongoing.
4. **`MainActivity.kt`** — anular el channel al destruir el engine.

## Testing

- **Unit (Dart):** `shouldHaveMediaSession` → true sólo con `inBackground && hasVideo && !inPip`; false en foreground, sin video, o en PiP. (Cubre el cambio clave: pausado-en-background con video → true, donde antes daba false.)
- **Nativo (Kotlin):** sin unit test (comportamiento del OS); se valida con analyze + release build + checklist en dispositivo.
- **Checklist en dispositivo (release, Pixel 6, API 36):**
  - Abrir video → **pausar** → Home (background): aparece notificación de Kivo (persistente, en pausa) y el servicio queda foreground. (Log de control opcional: el servicio NO hace el detach en pausa.)
  - Con el video pausado en background, abrir muchas otras apps / presión de memoria un buen rato → volver a Kivo: **reproduce y abre otros videos sin congelarse** (antes: freeze/force-close).
  - Reproduciendo en background: sigue funcionando igual (no regresión) — notificación, controles, audio-focus/llamada.
  - Volver a foreground: la notificación se retira (`_end`), reproductor normal.
  - Stop desde la notificación: termina la sesión, para audio.
  - PiP: no aparece la notificación de sesión (compuerta excluye `inPip`) — sin regresión.

## Restricciones globales

- No tocar media_kit ni disponer el engine (enfoque B descartado).
- `START_NOT_STICKY` se mantiene (fuera de alcance).
- Un solo acento configurable; sin colores nuevos hardcodeados (la notificación no cambia de estilo).
- No `flutter run`; build release + `adb install` al Pixel 6 (`24231FDF6006ST`) al cerrar el módulo.
- Suite completa verde.
- No romper la reproducción en background actual (playing) ni el flujo de audio-focus/llamada telefónica.
