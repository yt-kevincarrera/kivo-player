# Kivo — Refinamiento de biblioteca v2 + bug de reanudación (Diseño)

**Fecha:** 2026-06-30
**Estado:** Diseño aprobado (el usuario pidió ejecutar autónomamente).
**Contexto:** Tercera pasada sobre la biblioteca tras feedback en device, + un bug de reanudación/reiniciar. Mini-player (C) y 2c siguen después.

## A. Tiles (fila de lista)

- **Preview y texto más grandes (#1, #5):** la miniatura de la fila de lista debe ser claramente prominente — ancho **~168px** (16:9), no debe verse más chica que el texto. Título **~16px** w600; tamaño (`fmtSize`) **~13–14px** `onSurfaceVariant`.
- **Etiqueta "Nuevo" (#4):** badge pequeño en videos recién agregados (agregados hace **< 3 días**, vía `dateAddedMs`). Píldora discreta (azul de marca o dorado) sobre/junto a la miniatura. `VideoTile` recibe `bool isNew` (default false); la biblioteca lo calcula.
- **Icono de opciones "⋮" (#7):** tres puntos verticales al final de cada fila (lado derecho), **solo visual por ahora** (sin acción / placeholder). `VideoTile` recibe `VoidCallback? onOptions` (si null, el icono igual se muestra pero no hace nada o muestra un no-op).
- Toda la fila sigue siendo tappable (logrado). Mantener progreso segmentado + badge de duración.

## B. LibraryScreen

- **Padding horizontal de las secciones de video (#2):** la lista/grid de videos NO debe alinearse al borde como "Continuar"; debe estar **más adentro** (más padding horizontal que la tira de Continuar). Ej.: Continuar mantiene su inset actual; las secciones de video usan un padding horizontal mayor (~20–24px) para que se note el escalón.
- **Menos padding vertical entre filas (#6):** se exageró; reducir el gap entre filas de lista a **~6–8px** (antes 14).
- **Transición de chips = SOLO slide (#3):** al pasar Todo↔Carpetas NO debe haber fade; debe ser un deslizamiento lateral limpio. Implementación: usar un **`PageView` controlado** (2 páginas: feed de videos / grilla de carpetas) — el tap en un chip hace `animateToPage` (~250ms `easeOutCubic`); deslizar lateralmente también cambia (bonus, estilo galería). Sin opacidad/fade.
- **Pinch por pasos garantizado (#8):** una sola gesto de pinch = **exactamente un paso de columna**, sin importar la magnitud. Al iniciar el pinch (`onScaleStart`) se arma un flag; en el primer cruce de un umbral pequeño (rel > ~1.08 = menos columnas / rel < ~0.92 = más columnas) se aplica **un** paso y se **bloquea** hasta que el gesto termine (`onScaleEnd` / nuevo `onScaleStart`). Así, estando en 1 col, cualquier pinch hacia afuera lleva a 2 (no salta a 3). Sigue siendo cualquier dirección (gate `pointerCount >= 2`). Háptica + persistir.
- **Reflujo suave (#9):** el escalado actual se ve "rápido y feo". Reemplazar por un **settle suave y sutil**: al cambiar de columnas, la grilla se re-acomoda inmediatamente (posiciones finales, scroll preservado) y los tiles hacen un **scale sutil 0.92→1.0** (NO el 2x violento de antes) con **`Curves.easeOutCubic` ~300ms**. Suave, sin fade, sin saltos violentos. (Un reflujo continuo tipo Google Fotos pixel-perfect requiere un layout no-sliver; queda fuera de alcance — priorizamos suavidad.)

## C. Bug: "Reiniciar" no persiste el reinicio

**Síntoma:** se reanuda un video, se toca "Reiniciar" (o "Desde el inicio"), se sale, y al volver a entrar arranca desde la reanudación vieja en vez de desde el principio.

**Causa raíz:** "Reiniciar" solo hace `seekTo(0)` en sesión; no borra la entrada persistida. Al salir, `ResumeService.record` **omite guardar si `position < minSeconds` (5s)** (`resume_service.dart:21`), así que la entrada vieja sobrevive. Además `_lastPosition` puede conservar el valor viejo si se sale de inmediato.

**Fix:** centralizar el reinicio en el player y hacerlo robusto:
- Nuevo `restartRequestProvider = StateProvider<int>((ref) => 0)` (tick).
- `ResumePrompt`: "Reiniciar" (modo undo) y "Desde el inicio" (modo ask) → `restartRequestProvider.notifier.state++` + cerrar el toast. ("Reanudar" sigue igual: `seekTo(saved)`.)
- `PlayerScreen`: en `build`, `ref.listen(restartRequestProvider, ...)` → `seekTo(Duration.zero)` + `_resume.clear(_resumeKey!)` (borra la persistencia) + `_lastPosition = Duration.zero` (evita que el guardado de salida re-escriba la posición vieja). Resetear `restartRequestProvider` a 0 en `_start()` (junto a los otros resets de estado por-entrada).
- Resultado: tras reiniciar, salir y volver arranca en 0; si el usuario mira >5s tras reiniciar, se guarda la nueva posición (correcto).

## Testing

- **Puro/widget:** `isNewVideo`/umbral 3 días (si se extrae helper); `VideoTile` muestra "Nuevo" cuando `isNew`, muestra el icono de opciones, abre al tocar texto; resume: tras un `restartRequest`, `_resume.clear` se llama y un re-`planResume` da `startAt = 0`. `flutter test` verde, `analyze` limpio.
- **Device:** previews/texto cómodos; "Nuevo" en recientes; ⋮ visible; secciones de video más adentro que Continuar; gap de filas menor; chips solo-slide; pinch 1→2→3 por pasos fácil; reflujo suave; y el bug de reiniciar resuelto (reiniciar+salir+entrar = desde el inicio).

## Fuera

- Acción real del menú ⋮ (futuro). Reflujo continuo pixel-perfect (Hito posterior si se desea). Mini-player (C). 2c.
