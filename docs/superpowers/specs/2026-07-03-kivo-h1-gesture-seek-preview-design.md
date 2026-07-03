# Kivo — Preview de frame en el seek por swipe horizontal (diseño)

**Fecha:** 2026-07-03
**Estado:** Diseño aprobado por el usuario; arrancar directo.
**Contexto:** Feature diferida desde Hito 1 (`docs/.../2026-06-30-kivo-h1-seek-frame-preview-design.md` §"Fuera (diferido)": *"Preview en el gesto de arrastre horizontal… reutilizará el mismo preview más adelante"*). La seek bar ya muestra el bubble con miniatura; el swipe horizontal solo mostraba un HUD de texto (tiempo + delta) y hacía **seek en vivo**. Este es el último leftover concreto de Hitos 1–3.

## 1. Comportamiento

El gesto de arrastre horizontal pasa de *seek en vivo* a *previsualizar y confirmar al soltar*, replicando el patrón de la seek bar (`seek_bar.dart` `onChanged`/`onChangeEnd`):

- **Start** (`_onHorizontalStart`): siembra `_seekStart = positionProvider` y `_seekAccum = 0` (ya lo hace).
- **Update** (`_onHorizontalUpdate`): calcula `target` con la misma matemática existente (`_seekAccum += (delta.dx/_width)*90*seekSensitivity`, `clampSeek(_seekStart, …, total)`). **NO** llama `seekTo`. En su lugar:
  - `gestureSeekProvider.state = target` (nuevo `StateProvider<Duration?>`).
  - `seekPreviewControllerProvider.request(target)` — reutiliza el extractor, bucketing 1 s, LRU (30) y coalescing ya existentes.
  - Se **elimina** la llamada `hudProvider.show(HudKind.seek, …)` (la tarjeta central ya muestra tiempo + delta).
- **End** (`_onHorizontalEnd`, nuevo handler cableado en el `GestureDetector`):
  - `playerControllerProvider.seekTo(target)` (target = último `gestureSeekProvider`, o `_seekStart` si nulo).
  - `pendingSeekProvider.state = target` (para que la seek bar, si está visible, aguante hasta que la posición real alcance — consistencia con la barra).
  - `gestureSeekProvider.state = null` (oculta la tarjeta).
  - `seekPreviewFrameProvider.state = null` (evita el flash del frame anterior en el próximo swipe).
  - Háptico sutil (`_haptic()`, respeta `hapticsOnGestures`).
- **Gating** (sin cambios): si `_hDead` (dead zone vertical/lateral), `_holding` (hold-to-speed) o `!st.horizontalSeek`, el update retorna temprano y no toca `gestureSeekProvider`. `_onHorizontalEnd` solo confirma si hay un `gestureSeekProvider` no nulo.

**Provider nuevo, no reusar `scrubProvider`:** el gesto usa `gestureSeekProvider` propio para que la tarjeta central del gesto y el `SeekPreviewBubble` de la seek bar nunca se rendericen a la vez ni disparen la animación del thumb de la barra sin tocarla. `seekPreviewControllerProvider`, `seekPreviewFrameProvider`, `pendingSeekProvider` **sí** se reutilizan (un solo gesto activo a la vez).

## 2. UI — tarjeta central de preview

Nuevo widget `GestureSeekPreview` (`lib/ui/player/seek/gesture_seek_preview.dart`), montado en el `Stack` del player **independiente de los controles** (debe verse aunque los controles estén ocultos durante el swipe). Observa `gestureSeekProvider` + `seekPreviewFrameProvider` + `durationProvider`:

- Si `gestureSeekProvider == null` → `SizedBox.shrink()`.
- Reutiliza el look del `SeekPreviewBubble`: frame **160×90**, `BorderRadius` 8, borde **dorado** (`accentColor`) 1.5, fondo negro α0.8, `Image.memory(bytes, fit: cover, gaplessPlayback: true)`; si `bytes == null`, caja vacía (aparece al llegar el frame).
- Debajo (gap 4): pill negra α0.8 con **tiempo objetivo + delta**: `fmtDuration(target)` y, si `delta != 0`, `(±M:SS)`. Mismo lenguaje que los HUD.
- Posición: **centrado horizontal, tercio superior** (`Alignment(0, -0.4)`), coherente con los indicadores centrados ya reubicados; no pelea con la barra inferior.

## 3. Casos borde

- `horizontalSeek` off → nada (igual que hoy).
- Duración desconocida (0) → `clampSeek` limita a lo disponible; la tarjeta se muestra sin imagen hasta que llega el frame.
- Un swipe cancelado en dead zone / durante hold-to-speed / dismiss → no interfiere (ya gateado).
- `GestureSeekPreview` no escribe providers en `build` (solo lee) — sin efectos en construcción.

## 4. Archivos

- `lib/ui/player/seek/seek_preview.dart` — añadir `gestureSeekProvider` (`StateProvider<Duration?>`).
- `lib/ui/player/seek/gesture_seek_preview.dart` — **nuevo** widget.
- `lib/ui/player/gestures/player_gestures.dart` — reescribir `_onHorizontalUpdate`; añadir `_onHorizontalEnd`; cablear `onHorizontalDragEnd`.
- Montaje del widget: en el `Stack` del player (donde viven los overlays: `player_screen.dart` o `controls_overlay`/equivalente) — **fuera** de la capa que se oculta con los controles.

## 5. Testing

- **Puro:** `clampSeek` y `SeekPreviewController` (bucketing/LRU/coalescing) ya cubiertos — no se tocan.
- **Widget (`test/ui/player/gesture_seek_preview_test.dart`):**
  - `gestureSeekProvider == null` → nada renderizado.
  - Con target y frame (bytes de un PNG fake, extractor fake) → muestra la imagen + el label de tiempo; delta positivo/negativo con el signo correcto.
- **Device (Pixel 6):** swipe horizontal muestra la tarjeta con el frame del punto objetivo; el video **no** salta hasta soltar; al soltar aterriza en el punto correcto; con `horizontalSeek` off no aparece nada; con controles ocultos la tarjeta igual se ve.

## Fuera de alcance

- Cambiar la seek bar (ya tiene su bubble).
- Preview en el gesto **vertical** (brillo/volumen no lo necesitan).
- Thumbnails pre-generados / tira de miniaturas en el gesto.
- UI de configuración (Hito 4).
