# Kivo — Plan 3b (recortado): Preview de frame al hacer seek (Diseño)

**Fecha:** 2026-06-30
**Estado:** Diseño aprobado
**Hito:** 1 (núcleo del reproductor) — cierra la feature §9 del spec del Hito 1.

---

## 1. Alcance

**Dentro:** miniatura del frame en la posición de scrub, generada **on-demand**, mostrada en una burbuja sobre la barra de seek mientras se arrastra (spec Hito 1 §9, "Enfoque A").

**Fuera (diferido):**
- **Tira de miniaturas de la cola** (§8): la cola por carpeta es de **un solo elemento** con el flujo actual del file picker (Android copia el archivo a `.../cache/file_picker/<n>/clip.mp4`, cuyo directorio contiene solo esa copia, así que no hay hermanos). Una tira de miniaturas no tiene contenido que mostrar hasta que el **Hito 2 (biblioteca)** aporte acceso real a carpetas/árbol. Ver [[resume-and-dispose-gotchas]] punto 1.
- **Preview en el gesto de arrastre horizontal** (§6): reutilizará el mismo preview más adelante; este plan solo cablea la **barra de seek**.
- **Animación de onda (ripple)** del doble-tap: pulido, fuera de este plan.

## 2. Decisiones técnicas (aprobadas)

- **Extracción de frames:** `MediaMetadataRetriever` nativo de Android vía `MethodChannel`, detrás de una interfaz `FrameExtractor` en la frontera de plataforma (como `DeviceControls`). Es la vía estándar de Android para frames en cualquier timestamp (random-access por keyframe), sin segundo mpv y sin dependencia pub nueva. Solo Android por ahora (Android-first); iOS rellena la interfaz después.
- **No** se usa `media_kit screenshot()` (requeriría un segundo Player headless, pesado e incierto).

## 3. Frontera de plataforma — `FrameExtractor`

`lib/platform/interfaces/frame_extractor.dart`:
```dart
abstract class FrameExtractor {
  /// Prepara/reutiliza un extractor para [path]. Idempotente para el mismo path.
  Future<void> prepare(String path);
  /// Frame más cercano (keyframe) a [position]; null si no hay frame/preparado.
  Future<Uint8List?> frameAt(Duration position);
  /// Libera recursos nativos (llamar al cerrar o cambiar de video).
  Future<void> release();
}
```

`lib/platform/android/android_frame_extractor.dart` — `MethodChannel('kivo/frames')`:
- `prepare`: invoca `prepare` nativo con el path; el lado Kotlin crea un `MediaMetadataRetriever` y `setDataSource(path)`. Si ya está preparado para el mismo path, no-op.
- `frameAt`: invoca `frameAt` con `positionMs`; Kotlin hace `getScaledFrameAtTime(positionMs*1000, OPTION_CLOSEST_SYNC, targetW, targetH)` (o `getFrameAtTime` + escalado si la API < 27), comprime a JPEG (~75) y devuelve `ByteArray`. Corre en un `Executor`/coroutine de fondo para no bloquear el hilo de plataforma.
- `release`: libera el retriever.
- Ancho objetivo del thumbnail: **240 px** (alto proporcional), para fluidez y memoria.

`MainActivity.kt` registra el handler del canal `kivo/frames` (junto al existente `kivo/orientation`).

Provider: `frameExtractorProvider` (en `platform/device_controls_provider.dart` o un archivo nuevo `frame_extractor_provider.dart`), override en `main()` con la instancia Android.

## 4. Controlador de preview (Dart) — `SeekPreviewController`

`lib/ui/player/seek/seek_preview.dart` (nuevo subdir `seek/`):
- `scrubProvider` (`StateProvider<Duration?>`): posición de preview; `null` cuando no se arrastra.
- `SeekPreviewController` (provider) con:
  - **Bucketing**: redondea la posición a 1 s (`Duration(seconds: position.inSeconds)`) como clave.
  - **Caché LRU** de bytes por bucket (capacidad 30); evicción del más antiguo.
  - **Coalescing**: una sola petición `frameAt` en vuelo; si llega una nueva posición mientras tanto, se guarda como "pendiente" y se procesa al terminar la actual (las intermedias se descartan).
  - `requestFrame(Duration position)`: si el bucket está en caché → expone esos bytes; si no → encola/coalesce y al resolver expone bytes + cachea.
  - Expone los bytes actuales vía `seekPreviewFrameProvider` (`StateProvider<Uint8List?>`), que la burbuja observa.
- La lógica de bucketing/LRU/coalescing es **pura y testeable** (separada de la llamada `FrameExtractor`, que se mockea).

## 5. Barra de seek — cambio de comportamiento

`lib/ui/player/controls/seek_bar.dart`:
- `onChanged(v)`: actualiza `scrubProvider = Duration(ms: v)` + `controlsVisible.show()` + `seekPreview.requestFrame(...)`. **NO** llama `seekTo` (deja de thrashear el player en vivo).
- `onChangeEnd(v)`: `playerController.seekTo(Duration(ms: v))`; `scrubProvider = null` (oculta la burbuja).
- La etiqueta de tiempo izquierda muestra la posición de scrub cuando `scrubProvider != null`, si no la posición real (para feedback inmediato del destino). El toggle total↔restante de la derecha se mantiene.

## 6. UI — burbuja de preview

`lib/ui/player/seek/seek_preview_bubble.dart`:
- Visible solo cuando `scrubProvider != null`.
- Posicionada **sobre** la barra de seek, anclada horizontalmente a la fracción del scrub (clamp a los bordes con un margen).
- Contenido: el frame (`Image.memory`, esquinas redondeadas, borde dorado `accent` 1.5 px) con el **timestamp** debajo (`fmtDuration`, dark capsule). Mientras el frame carga: placeholder oscuro del mismo tamaño (sin spinner).
- Se compone en el `Stack` del `player_screen` (o dentro del overlay de controles, sobre la barra inferior). Decisión de implementación: dentro de `bottom_bar`/`seek_bar` con un overlay `Positioned`, para anclar al thumb correctamente.

## 7. Ciclo de vida

`player_screen.dart`:
- Cachear `_frames = ref.read(frameExtractorProvider)` en `initState` (patrón obligatorio — **nunca `ref` en dispose**, ver [[resume-and-dispose-gotchas]] punto 2).
- En `_start`: tras abrir, `_frames.prepare(session.path)`.
- En `dispose`: `_frames.release()` (con el ref cacheado).

## 8. Performance

- `OPTION_CLOSEST_SYNC` → grabs alineados a keyframe (rápidos, sin decodificar entre keyframes).
- Escalado a 240 px + JPEG → bytes pequeños, memoria baja.
- Bucketing 1 s + LRU + coalescing → como mucho ~1 grab por segundo de scrub, reusando los repetidos.
- Extracción en hilo de fondo nativo → sin jank en el hilo de UI/plataforma.
- `scrubProvider`/`seekPreviewFrameProvider` aislados → solo la burbuja y la etiqueta de tiempo se redibujan; el resto del árbol intacto.

## 9. Testing

- **Unitario (Dart, lógica pura):** bucketing (posiciones cercanas → mismo bucket), LRU (evicción del más antiguo a capacidad 30), coalescing (varias posiciones rápidas → una sola en vuelo + procesa la última pendiente). `FrameExtractor` mockeado (Fake que devuelve bytes deterministas y registra las posiciones pedidas).
- **Widget:** la burbuja aparece con `scrubProvider != null` y se oculta con `null`; `onChangeEnd` dispara `seekTo` y limpia el scrub.
- **Device:** validar la extracción nativa real (frame correcto, fluidez, sin jank) en el Pixel 6.

## 10. Estructura de archivos

```
lib/platform/interfaces/frame_extractor.dart        (interfaz)
lib/platform/android/android_frame_extractor.dart   (impl Android)
lib/platform/frame_extractor_provider.dart          (provider, override en main)
lib/ui/player/seek/seek_preview.dart                (controller + providers + lógica pura)
lib/ui/player/seek/seek_preview_bubble.dart         (UI burbuja)
android/.../MainActivity.kt                          (canal kivo/frames)
```
Modificados: `seek_bar.dart` (comportamiento), `player_screen.dart` (lifecycle), `main.dart` (override provider).
