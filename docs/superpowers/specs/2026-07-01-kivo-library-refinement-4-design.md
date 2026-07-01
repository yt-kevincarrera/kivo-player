# Kivo — Refinamiento de biblioteca v4 (Diseño)

**Fecha:** 2026-07-01
**Estado:** Diseño aprobado (ejecución autónoma).
**Contexto:** Quinta pasada. Corrige el parpadeo residual al cambiar Todo↔Carpetas, la actualización stale de "Continuar viendo" (bug de carrera confirmado), y unifica visualmente las vistas de Carpetas con la página principal. Mini-player (C) y 2c siguen después.

## 1. Parpadeo al cambiar Todo↔Carpetas (causa raíz confirmada)

- **Causa raíz:** `ThumbnailImage` usa `ref.watch(thumbnailProvider(id))`, un `FutureProvider.autoDispose.family`. `PageView` (con `children:`) usa `SliverChildListDelegate`, que por defecto **descarta el Element de la página fuera de pantalla** cuando excede el `cacheExtent` (muy inferior al ancho de una página). Al volver a "Todo", cada `ThumbnailImage` se reconstruye desde cero, el provider autoDispose se re-crea, y el `AnimatedSwitcher` interno repite el ciclo placeholder→imagen para **todos los tiles a la vez** → eso es el "parpadeo".
- **Fix:** envolver cada página del `PageView` (`_videosTab`/`_foldersTab`) en un widget con `AutomaticKeepAliveClientMixin` (`wantKeepAlive = true`) para que Flutter **retenga el Element** aunque esté fuera de pantalla. Esto también preserva la posición de scroll entre cambios de pestaña (bonus). No se toca `ThumbnailImage` ni el provider.

## 2. "Continuar viendo" stale (bug de carrera confirmado)

- **Causa raíz:** las 3 salidas del reproductor (botón atrás del top bar, gesto/botón atrás del sistema, swipe-down) todas terminan en `Navigator.of(context).maybePop()`. La pantalla que empujó la ruta (`LibraryScreen`/`FolderScreen`) reacciona con `.then((_) => invalidate(...))`, que se dispara **casi de inmediato** al llamar `pop()`. Pero el guardado final más preciso (`_saveProgress()`) corre en `PlayerScreen.dispose()`, que Flutter invoca **después** de que termina la animación de transición de salida de la ruta (~300ms más tarde). El invalidate llega antes que la escritura final → dato stale (mitigado parcialmente por el guardado periódico de 4s, pero no siempre alcanza a tener una entrada reciente, y nunca contiene los últimos segundos vistos).
- **Fix (un solo punto de intercepción, cubre las 3 salidas):** envolver el contenido de `PlayerScreen` en `PopScope(canPop: false, onPopInvokedWithResult: ...)`. Cuando se detecta un intento de pop, **esperar** `_saveProgress()` y solo entonces llamar `Navigator.of(context).pop()` manualmente. Como las 3 salidas ya usan `maybePop()`/el mecanismo estándar de pop, todas quedan interceptadas por este único cambio en `player_screen.dart` — sin tocar `top_bar.dart` ni `player_gestures.dart`. El guardado en `dispose()` se mantiene como red de seguridad (ya es idempotente).

## 3. Unificar el estilo de "Carpetas" con la página principal

- **Extraer un widget compartido `VideoDensityFeed`** (pinch de densidad, reflujo animado, cambio lista/grid según `libraryColumns`, wiring de "Nuevo"/progreso/tamaño) desde `LibraryScreen._videosTab`, parametrizado por:
  - `videos`, `onOpen(VideoItem current, List<VideoItem> all)`.
  - `groupByDate` (bool): `true` en la pestaña "Todo" (secciones Hoy/Ayer/...), `false` dentro de una carpeta (lista/grid plana, sin cabeceras de fecha).
  - `showContinueRow` (bool): `true` solo en "Todo".
- `LibraryScreen._videosTab` pasa a ser un envoltorio delgado que instancia `VideoDensityFeed(...)`. El fix del parpadeo (§1) se aplica en `LibraryScreen` alrededor de las páginas del `PageView`.
- `FolderScreen` reemplaza su `GridView.builder` plano por `VideoDensityFeed(videos: videos, onOpen: ..., groupByDate: false, showContinueRow: false)` — mismo pinch, reflujo, alternancia lista/grid, inset (24px), badge "Nuevo", progreso segmentado y `PressBounce` que en la página principal.
- **`FolderGrid` (la grilla de carpetas en sí):** pulir para sentirse consistente — inset de la grilla a **24px** (antes 12), tipografía del nombre de carpeta a **13px** (antes 11), mantener la píldora dorada de conteo. No se le aplica el sistema de densidad (las carpetas no son videos), solo el pulido visual/espaciado.

## Testing

- **Puro/widget:** `VideoDensityFeed` renderiza lista a 1 col y grid a 2/3; con `groupByDate:false` no muestra cabeceras de fecha; con `showContinueRow:false` no muestra "Continuar". `FolderScreen` usa el widget compartido y abre un video al tocar. Guardar-antes-de-pop: test de `PlayerController`/`ResumeService` a nivel de servicio ya cubre `record`/`clear`; agregar (si es práctico) una prueba de widget que confirme que `PopScope` intercepta el pop y llama `_saveProgress` antes de `Navigator.pop`. `flutter test` verde, `analyze` limpio.
- **Device:** cambiar Todo↔Carpetas repetidamente sin parpadeo visible en las miniaturas ni pérdida de scroll; ver un video un rato, salir por CUALQUIERA de las 3 vías (botón, back del sistema, swipe-down), y confirmar que aparece de primero en "Continuar" al instante; entrar a una carpeta y confirmar que se ve/comporta igual que la pestaña "Todo" (mismo pinch, reflujo, tiles, Nuevo, inset); la grilla de carpetas se ve más espaciosa y legible.

## Fuera

- Mini-player (C). 2c. Acción real del menú ⋮.
