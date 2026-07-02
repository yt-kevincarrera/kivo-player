# Kivo Hito 3 / 3d — Picture-in-Picture (Diseño)

**Fecha:** 2026-07-02
**Estado:** Diseño aprobado (el usuario delegó aprobación — "auto aprueba todo"). Último sub-proyecto del Hito 3.
**Contexto:** 3a/3b/3c/3e completos y verificados en el Pixel 6. PiP es casi todo trabajo nativo Android: la ventanita flotante y sus controles los dibuja el sistema (RemoteActions), no Kivo — hay poca UI propia (activar el botón que ya existe deshabilitado y ocultar los controles de Kivo mientras se está en PiP). Se apoya en la fontanería de canal nativo + ciclo de vida de Activity ya montada en 3e.

## 1. Comportamiento

- **Entrar en PiP:**
  1. Tocando el botón "Imagen en imagen" de la barra superior (hoy deshabilitado, se activa).
  2. Automáticamente al presionar Home (`onUserLeaveHint`) mientras hay reproducción — el caso esperado "aprieto home y el video se va a una ventanita".
- **Mientras se está en PiP:** la ventana muestra **solo el video** — Kivo oculta sus overlays (barras, gestos visuales, chip, etc.) vía un flag `pipModeProvider` que setea el callback nativo `onPictureInPictureModeChanged`. El aspect ratio de la ventana = aspect del video (fallback 16:9).
- **Controles del sistema en la ventana (RemoteActions):** retroceder 10s · play/pausa (alterna) · avanzar 10s. El ícono play/pausa se actualiza con el estado real.
- **Salir de PiP:** tocar la ventana restaura pantalla completa (Android trae la Activity al frente → `onPictureInPictureModeChanged(false)` → se restauran los controles). Cerrar la ventana (✕) destruye la Activity → `dispose()` pausa (comportamiento estándar).
- **Disponibilidad:** PiP requiere Android 8.0+ (API 26) y soporte del dispositivo. Si no está soportado, el botón se oculta y el Home cae al comportamiento de 3e (audio en segundo plano).

## 2. Coordinación con 3e (segundo plano / audio-only)

Home mientras reproduce ahora tiene dos destinos posibles: **PiP (video en ventanita)** o **audio en segundo plano (sin video)**. Regla:
- Si PiP está soportado y armado (estamos en el reproductor con un video) → Home entra en PiP. El video sigue visible en la ventanita.
- La **notificación multimedia de 3e NO se muestra mientras se está en PiP** (la ventanita ya tiene sus propios controles): el `BackgroundPlaybackCoordinator` consulta el flag de PiP y no arranca sesión mientras `pipMode == true`.
- Si el usuario cierra la ventanita de PiP → se destruye la Activity → pausa (estándar). El modo audio-only in-app (pantalla apagada explícita) sigue siendo el camino de 3e, independiente de PiP.

## 3. Arquitectura

**Motor:**
- `PlaybackEngine` gana `({int width, int height})? get videoSize` (dimensiones actuales del video para el aspect de la ventana; null si desconocidas). `MediaKitEngine` lo lee de `_player.state.width/height`. `FakePlaybackEngine` lo espeja como campo seteable.

**Frontera de plataforma (patrón `MediaSessionBridge`/`SubtitleFinder`):**
- **`lib/platform/interfaces/pip_controller.dart`**:
  - `class PipCallbacks { final void Function(bool inPip) onModeChanged; final void Function() onPlay, onPause; final void Function(int seconds) onSkip; }` (const, todos requeridos).
  - `abstract class PipController { Future<bool> isSupported(); void setCallbacks(PipCallbacks cb); Future<void> arm({required int width, required int height, required bool playing}); Future<void> disarm(); Future<void> enterNow(); Future<void> updateState({required int width, required int height, required bool playing}); }`
    - `arm`: activa el auto-PiP en Home con las dimensiones/estado actuales (guardado nativo para `onUserLeaveHint`).
    - `enterNow`: entra en PiP inmediatamente (botón).
    - `updateState`: refresca dims + estado playing (para el aspect y el ícono play/pausa de la RemoteAction).
    - `disarm`: al salir del reproductor.
- **`lib/platform/android/android_pip_controller.dart`** — `MethodChannel('kivo/pip')`. Dart→nativo: `isSupported`/`arm`/`disarm`/`enterNow`/`updateState`. Nativo→Dart (`setMethodCallHandler`): `modeChanged{inPip}`, `play`, `pause`, `skip{seconds}`.
- **`lib/platform/pip_controller_provider.dart`** — `Provider<PipController>` throws-until-overridden; override en `main.dart`.

**Estado / UI:**
- **`pipModeProvider`** (`StateProvider<bool>`, en `lib/ui/player/state/pip_state.dart`) — true mientras la ventana está en PiP. Lo setea el callback `onModeChanged`.
- **`lib/ui/player/player_screen.dart`**: cachear `_pip = ref.read(pipControllerProvider)` en initState; `setCallbacks` (play→engine, pause→engine, skip→`PlayerController.skipBy`, modeChanged→`pipModeProvider`); `arm(...)` al iniciar y `updateState(...)` cuando cambian dims/playing (vía `ref.listen` de `playingProvider` + un intento tras cargar el video); `disarm()` en dispose. Ocultar overlays cuando `pipMode == true` (envolver el stack de overlays en un `if (!pipMode)` o `Visibility`), dejando solo el `Video`.
- **`lib/ui/player/controls/top_bar.dart`**: activar el botón PiP → `pip.enterNow()`; ocultarlo si `!isSupported` (se resuelve una vez y se cachea).
- **`lib/player/background/background_playback.dart`**: no arrancar sesión mientras `pipMode == true` (leer el provider) — evita notificación duplicada durante PiP.

**Nativo (Kotlin):**
- **`MainActivity.kt`**: canal `kivo/pip`; guarda estado armado (dims, playing, supported); `override fun onUserLeaveHint()` → si armado && playing && supported → `enterPip()`; `override fun onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)` → `invokeDart("modeChanged", {inPip})`; `enterPip()` construye `PictureInPictureParams` (aspect `Rational(width, height)` clamp a rangos válidos, `setActions([rewind, playPause, forward])`) y llama `enterPictureInPictureMode(params)`; RemoteActions vía `PendingIntent` broadcast a un `BroadcastReceiver` interno → `invokeDart("play"/"pause"/"skip")`. `updateState` recalcula params (aspect + ícono play/pausa) y, si ya se está en PiP, `setPictureInPictureParams`.
- **`AndroidManifest.xml`**: `android:supportsPictureInPicture="true"` en la Activity (los `configChanges` ya incluyen screenSize/smallestScreenSize/screenLayout/orientation, así que la Activity no se recrea al entrar/salir de PiP).

## 4. Testing

- **Puro/widget (Dart):** `FakePipController` registra `armed`/`enterNow`/`updateState`/`disarm`; el botón PiP llama `enterNow` (y se oculta si `isSupported` false); `pipModeProvider` oculta los overlays cuando true (widget test: en PiP no se encuentran las barras, sí el Video); las callbacks nativas (play/pause/skip/modeChanged) enrutan a engine/controller/provider; el coordinador de 3e no arranca sesión con `pipMode == true`.
- **Device (Pixel 6 — el nativo es la aceptación real):** botón PiP → ventanita con el video en su aspect; Home reproduciendo → entra en PiP solo; los 3 controles (⏪10 · ⏯ · ⏩10) funcionan y el ícono play/pausa refleja el estado; tocar la ventana restaura pantalla completa con los controles; cerrar la ventana pausa/termina; NO aparece la notificación de 3e mientras se está en PiP; al volver de PiP el reproductor queda como estaba; en un dispositivo/OS sin PiP el botón no aparece y Home cae a audio en segundo plano.

## Fuera de alcance

- Controles extra en la ventana (velocidad, subtítulos) — la RemoteAction se limita a 3 acciones (límite práctico de PiP + claridad).
- PiP en iOS (proyecto Android-first).
- Autoplay / cola en PiP (feature futura comprometida, aparte).
- Cierra el Hito 3; sigue Hito 4 (panel de personalización) y la feature de autoplay comprometida.
