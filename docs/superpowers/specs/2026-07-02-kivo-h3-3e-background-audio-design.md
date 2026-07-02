# Kivo Hito 3 / 3e — Segundo plano + Solo audio (Diseño)

**Fecha:** 2026-07-02
**Estado:** Diseño aprobado (mockups: centro "ondas + título" para Solo audio; menú con switch; notificación de referencia).
**Contexto:** Cuarto sub-proyecto de Hito 3, adelantado antes que 3d (PiP) por decisión del usuario. 3a/3b/3c completos y verificados en el Pixel 6. Es el sub-proyecto con más trabajo nativo Android (foreground service + MediaSession + audio focus).

## 1. Comportamiento

**Segundo plano automático:** si hay audio reproduciéndose y la app pasa a background (Home, cambio de app, pantalla apagada), el audio **sigue solo** — mpv no depende de la Activity; el trabajo es *dejar* de pausar y sostener el proceso. Aparece la **notificación multimedia**; al volver a la app la notificación se retira y todo queda como estaba (Android restaura el back stack: si estabas en el reproductor, seguís ahí). Si estaba **pausado** al salir, no hay notificación ni servicio (nada que sostener). Pausar desde la notificación mantiene la notificación (descartable con swipe, que termina la sesión); reanudar la re-fija.

Se elimina la línea `_engine.pause()` del `didChangeAppLifecycleState` de `PlayerScreen` (el "no background playback in Hito 1"). La pausa al **salir del reproductor dentro de la app** (dispose → library) no cambia. El mini-player convive: si minimizás y la app pasa a background con audio sonando, sigue igual (la coordinación es global, no de `PlayerScreen`).

**Notificación (MediaSession + MediaStyle):** título del video, play/pausa, −10s/+10s, seek bar arrastrable (la provee `MediaSession` con `ACTION_SEEK_TO` + posición/duración actualizadas), swipe para cerrar cuando está pausada (termina sesión). Tocarla abre la app tal como estaba. Las acciones viajan a Dart y ejecutan por los caminos existentes: play/pausa → engine; ±10s y seek → `PlayerController` (así el seek de notificación también cancela el bucle A-B si cae fuera del rango, consistente con 3c).

**Audio focus estándar (activo siempre que haya reproducción, también en primer plano):**
- Pérdida permanente (otra app toma reproducción) → pausa, no reanuda sola.
- Pérdida transitoria (llamada) → pausa; al recuperar el focus → reanuda solo si la pausa fue por el focus (no si el usuario pausó en el medio).
- Duck (GPS, asistente) → volumen del reproductor al 30% del nivel del usuario; al terminar, restaura. Mismo principio que el fade del sleep timer: **nunca** el volumen del sistema; restaurar recalculando con `volumeMapping`. Si el usuario ajusta el volumen durante el duck, el ajuste gana (el duck no restaura por encima).

**Modo "Solo audio" (in-app, mínimo):**
- Toggle en el menú ⋮ (tercera fila, con switch dorado; la fila conmuta al toque, no navega). Copy: "Solo audio" / "Apagar el video, seguir escuchando".
- Activo → el track de video se apaga en mpv (`vid=no`); la superficie queda **negra** con el centro aprobado: ícono de ondas dorado estático + título del archivo + etiqueta "SOLO AUDIO" (mismo show/hide que los controles — controles ocultos = negro casi total, mínimo consumo OLED). Controles, gestos, seek, velocidad, temporizador y bucle funcionan idéntico.
- Desactivo → `vid=auto`, el video vuelve al instante en la posición actual.
- **No persiste:** muere al cambiar de video y al salir del reproductor. Sin campo de settings.
- Interacción con subtítulos: con `vid=no` no hay frames donde libass queme subtítulos — es coherente (estás escuchando); al volver el video vuelven solos.

**Interacciones con lo existente:** el sleep timer (wall-clock, Dart) y el bucle A-B siguen corriendo en background — el isolate de Dart no se suspende en Android mientras el proceso viva; el foreground service lo protege de la muerte por memoria. El guardado periódico de progreso (timers de `PlayerScreen`/mini-player) también sigue. El duck del focus y el fade del sleep timer tocan ambos el volumen del reproductor: se aceptan tal cual (caso borde raro: duck durante fade → el más bajo gana momentáneamente y cada uno restaura por su lado con `volumeMapping`; sin coordinación extra — YAGNI).

## 2. Arquitectura

**Frontera de plataforma (patrón `SubtitleFinder`):**
- **`lib/platform/interfaces/media_session.dart`** — `class MediaSessionCallbacks { final void Function() onPlay, onPause; final void Function(int seconds) onSkip; final void Function(Duration) onSeek; final void Function() onFocusLoss, onFocusTransientLoss, onFocusRegained, onDuckStart, onDuckEnd, onStop; }` y `abstract class MediaSessionBridge { void setCallbacks(MediaSessionCallbacks cb); Future<void> updateSession({required String title, required Duration position, required Duration duration, required bool playing, required bool inBackground}); Future<void> endSession(); }`.
- **`lib/platform/android/android_media_session.dart`** — implementación por `MethodChannel('kivo/media_session')` (Dart→nativo: `update`/`end`; nativo→Dart: `setMethodCallHandler` para acciones y focus).
- **`lib/platform/media_session_provider.dart`** — `Provider<MediaSessionBridge>` throws-until-overridden; override en `main.dart`.

**Coordinador (Dart, global):**
- **`lib/player/background/background_playback.dart`** — `BackgroundPlaybackCoordinator` + `backgroundPlaybackProvider`. Observa el ciclo de vida de la app (WidgetsBindingObserver propio, registrado al construirse desde `main`), `playingProvider`, `positionProvider` (throttle ~1s), `durationProvider`, `currentVideoProvider` (título). Reglas: `inBackground && playing` → `updateSession(...)` (el nativo levanta foreground service + notificación si no existía); en background sigue empujando estado (posición 1/s, cambios de playing); `resumed` → `endSession()`. Callbacks nativos → `engine.play()/pause()`, `PlayerController.skipBy(±10)`, `PlayerController.seekTo`. Focus: implementa pausa/reanudación-si-pausó-el-focus y duck (30% vía `engine.setVolume(volumeMapping(...).playerPercent * 0.3)`, restaura al terminar; cancela si el usuario ajustó el volumen durante el duck — mismo patrón `volumePercentProvider`-listener del sleep timer).
- **Solo audio:** `audioOnlyProvider` (`NotifierProvider<AudioOnlyNotifier, bool>`) en el mismo archivo o en `lib/player/background/audio_only.dart`: `toggle()` llama `engine.setVideoTrackEnabled(!on)`; se resetea (y re-enciende el video) al cambiar de video y al salir del reproductor.

**Motor:**
- `PlaybackEngine` gana `Future<void> setVideoTrackEnabled(bool enabled)`; en `MediaKitEngine` = `NativePlayer.setProperty('vid', enabled ? 'auto' : 'no')`. `FakePlaybackEngine` gana el espejo (`videoTrackEnabled`).

**Nativo (Kotlin):**
- **`PlaybackSessionService.kt`** (nuevo) — `Service` foreground tipo `mediaPlayback`: `MediaSessionCompat` (playback state con `ACTION_PLAY|PAUSE|SEEK_TO|SKIP...`, posición/duración para la seek bar), `NotificationCompat.MediaStyle` (título, play/pausa, ±10s), canal de notificación "Reproducción". Recibe estado por el channel (vía `MainActivity` que mantiene la referencia) y reenvía acciones a Dart. `AudioFocusRequest` (`AUDIOFOCUS_GAIN`, `onAudioFocusChange` → eventos al channel). El servicio arranca con la primera `update` con `inBackground=true && playing=true` y termina con `end` o swipe.
- **`MainActivity.kt`** — registra el channel `kivo/media_session` y puentea con el service (patrón startService + estado compartido simple; el detalle fino queda al plan).
- **`AndroidManifest.xml`** — `<service android:foregroundServiceType="mediaPlayback">`, permisos `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `POST_NOTIFICATIONS`.
- **Permiso de notificaciones (Android 13+):** se pide en runtime la primera vez que se abre un video (junto al flujo existente de permisos de biblioteca ya hay precedente de pedir permisos; si se niega, todo funciona igual salvo que la notificación no se muestra — el audio en background sigue).

**UI:**
- **`lib/ui/player/audio_only/audio_only_view.dart`** — la capa negra + ondas + título + "SOLO AUDIO", apilada en `PlayerScreen` entre el `Video` y los gestos, visible cuando `audioOnlyProvider == true` (el centro sigue el show/hide de `controlsVisibleProvider`).
- **`lib/ui/player/more/more_menu.dart`** — tercera `_MenuRow` variante con `Switch` (mismo estilo que "Mostrar subtítulos" del track picker).
- **`lib/ui/player/player_screen.dart`** — quitar el pause de `didChangeAppLifecycleState` (queda el `_saveProgress()`).

## 3. Testing

- **Puro:** coordinador con `FakeMediaSessionBridge` (background+playing → update con datos correctos; resumed → end; pausa en background → update playing=false; acciones del bridge → engine/controller correctos; focus: pérdida pausa, transitoria pausa+reanuda solo si pausó el focus, duck baja a 30% y restaura, ajuste manual durante duck cancela restauración); `AudioOnlyNotifier` (toggle llama setVideoTrackEnabled, reset al cambiar de video re-enciende).
- **Widget:** fila del menú con switch conmuta el provider; `AudioOnlyView` aparece/desaparece con el provider y su centro sigue a los controles.
- **Device (Pixel 6, lo crítico — el nativo no tiene tests automatizados):** salir con Home reproduciendo → sigue sonando + notificación con seek/±10s/play-pausa funcionales; apagar pantalla → sigue; tocar la notificación → vuelve tal cual; pausar desde la notificación y swipe → termina; llamada entrante → pausa y reanuda al colgar; navegación GPS → duck y restaura; "Solo audio" → pantalla negra con ondas, video vuelve al instante al apagarlo; sleep timer dispara en background (pausa + notificación en pausa); bucle A-B sigue loopeando en background; batería/estabilidad tras ~30 min de pantalla apagada.

## Fuera de alcance

- Carátulas/artwork en la notificación (título solo).
- Deep-link de notificación a una ruta específica (Android restaura el back stack tal cual).
- Persistencia del modo Solo audio.
- Cola/siguiente-anterior en la notificación (no hay autoplay aún — feature futura comprometida).
- 3d (PiP) — siguiente y último sub-proyecto.
