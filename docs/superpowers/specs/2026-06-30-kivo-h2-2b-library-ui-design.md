# Kivo — Hito 2, sub-proyecto 2b: UI de biblioteca (Diseño)

**Fecha:** 2026-06-30
**Estado:** Diseño aprobado
**Hito:** 2 (biblioteca) — sub-proyecto **2b**. Sobre 2a (índice MediaStore). 2c (búsqueda/sort/filtros) viene después.

## Visión

La pantalla principal de Kivo: un **feed de todos los videos agrupado por día** (estilo galería), con tiles cinematográficos + progreso segmentado dorado, **pinch para densidad** (1↔2↔3 columnas, persistido), una fila **"Continuar viendo"**, y un tab secundario de **Carpetas**. Reemplaza la lista básica temporal de 2a. Estética: mezcla del layout cinematográfico (miniatura manda) con el lenguaje segmentado dark+gold del reproductor. Altamente interactiva y performante.

## Navegación

- **Control segmentado discreto** arriba: **[Videos | Carpetas]** — pequeño y sutil (no protagonista; tipografía ~12-13, alto ~28, no ocupa toda la barra). Activo en azul (`KivoColors.blue` = elemento activo); inactivo gris. Default: Videos.
- Tocar un video → `PlayerScreen` con **hero transition** (la miniatura se expande hacia el video). Reusa `currentVideoProvider.openInFolder(item, <videos de su carpeta>)` para que la cola sea su carpeta.
- Tab Carpetas → grilla de carpetas → tocar carpeta → sus videos (mismo estilo de tile + densidad).

## Tab "Videos"

1. **Continuar viendo** (si hay): fila horizontal con scroll + snap, arriba del feed. Cada tarjeta = cápsula oscura (estilo B) con miniatura, **progreso segmentado dorado**, y el tiempo de reanudación; tocar → reanuda. Ordenada por **más reciente** (ver `updatedAt`).
2. **Feed por fecha:** todos los videos agrupados por día con encabezados relativos: **Hoy**, **Ayer**, luego la fecha corta (p.ej. "12 jun") y por mes/año para lo más antiguo. Orden: más nuevo primero (por `dateAddedMs`). Agrupación = helper puro `groupByDay(items, now)` (testeable).
3. **Tile cinematográfico:** miniatura 16:9 (cover), título sobre un degradado inferior, badge de duración (`fmtDuration`) arriba-derecha, y **progreso segmentado dorado** en el borde inferior cuando hay posición de resume (segmentos lit = fracción vista). A 1 columna el tile es grande (ancho completo); a 2-3 columnas se compacta (título debajo si no cabe encima).
4. **Densidad (pinch):** un `GestureDetector` de escala sobre la grilla cambia columnas **1 → 2 → 3** (pinch out baja densidad / in sube), con feedback háptico al cambiar; se persiste en `settings.libraryColumns` (default **1**). Implementación: `GridView`/`SliverGrid` perezoso por densidad.

## Tab "Carpetas"

Grilla de **tarjetas-cápsula** (estilo B): miniatura de portada (primer video de la carpeta), nombre, y conteo en **pill dorado** ("N vids"). Tocar → pantalla con los videos de esa carpeta (mismo tile + densidad; sin necesidad de agrupar por fecha dentro de carpeta — orden natural por nombre).

## Miniaturas

`MediaIndexer` gana **`Future<Uint8List?> thumbnail(String id)`**. Android: `MediaStore.loadThumbnail(uri, Size, null)` (API 29+) con fallback `MediaStore.Video.Thumbnails.getThumbnail` (≤28); corre en el executor de fondo; tamaño objetivo ~`320x180`; JPEG. Una **caché en memoria** (LRU por id, p.ej. 200) en un provider; el tile pide `thumbnail(id)` y muestra **shimmer** mientras carga, **fade-in** al llegar (`AnimatedSwitcher`/`AnimatedOpacity`). Las miniaturas NO usan el `FrameExtractor` del reproductor (ese es para el preview de seek on-demand; aquí MediaStore las cachea a nivel sistema, mucho más barato para una grilla).

## Continuar viendo (resume)

- `ResumeStore` hoy: `secondsFor/put/remove`. Se amplía:
  - cada registro guarda `{seconds, updatedAt}` (ms epoch) en vez de solo `int`; `put(key, seconds, updatedAt)`.
  - nuevo `List<ResumeEntry> entries()` → `{key, seconds, updatedAt}`, para listar.
  - **Migración:** registros viejos (int plano) se leen con `updatedAt = 0` (van al final del orden).
- `continueWatchingProvider`: une `entries()` con el índice (por `name == key`), descarta los que no estén en el índice o ya terminados, ordena por `updatedAt` desc. Cada item lleva su `VideoItem` + fracción vista (`seconds*1000 / durationMs`).
- `player_screen._saveProgress` pasa a `record(key, pos, dur, nowMs)` (inyectar `nowMs` para testear; en runtime `DateTime.now().millisecondsSinceEpoch`).

## Setting nuevo

`libraryColumns` (int, default 1) en `KivoSettings` (campo + defaults + copyWith + toMap + fromMap), persistido. La densidad del feed lo lee/escribe.

## Estética / tema

Dark (negro), tiles `#1C2230`-ish, cápsulas `Colors.black`/`#161A21` con borde sutil, **dorado** = progreso/acentos/pills, **azul** = tab activo/seleccionado. Bordes redondeados (12 tiles, 10 cápsulas). Coherente con el reproductor.

## Interacciones / performance

- `GridView.builder`/slivers perezosos; miniaturas async + caché → scroll fluido.
- **Press-scale** en tiles (reusar el patrón `_PressBounce`/AnimatedScale del reproductor).
- **Shimmer** placeholder + **fade-in** de miniatura.
- **Hero** miniatura → reproductor.
- **Pinch** con háptica al cruzar densidad.
- Transición suave entre tabs (cross-fade) y al entrar a una carpeta.
- Providers aislados (índice, continuar-viendo, miniaturas, densidad) → rebuilds mínimos.

## Testing

- **Puro:** `groupByDay(items, now)` (Hoy/Ayer/fecha/mes, orden); `continueWatching` join+orden (con `entries()` mock + índice fake); resume `record(... , nowMs)`/`entries()` round-trip + migración de registro viejo; `libraryColumns` serialización.
- **Widget:** feed lista por secciones de fecha con `FakeMediaIndexer`; pinch cambia columnas + persiste; tab switch Videos↔Carpetas; tile muestra progreso/duración; tap → openInFolder + push player; shimmer→fade del thumbnail (thumbnail fake).
- **Device:** miniaturas reales de MediaStore, fluidez del scroll/pinch, hero transition, continuar-viendo real.

## Estructura de archivos (orientativa)

```
lib/platform/interfaces/media_indexer.dart        (+ thumbnail(id))
lib/platform/android/android_media_indexer.dart    (+ thumbnail impl)
lib/player/library/library_grouping.dart           (groupByDay — puro)
lib/player/library/continue_watching.dart          (continueWatchingProvider)
lib/player/library/thumbnail_cache.dart            (provider de caché + carga)
lib/player/resume/resume_store.dart                (ResumeEntry + entries() + updatedAt)
lib/player/resume/resume_service.dart              (record con nowMs)
lib/core/settings/kivo_settings.dart               (+ libraryColumns)
lib/ui/home/library_screen.dart                    (tabs + cuerpo) — reemplaza el slice de OpenScreen
lib/ui/home/widgets/video_tile.dart                (tile cinematográfico + progreso)
lib/ui/home/widgets/continue_row.dart              (fila continuar viendo)
lib/ui/home/widgets/folder_grid.dart               (tab carpetas)
lib/ui/home/widgets/thumbnail_image.dart           (shimmer + fade-in)
```
(El file picker + share-intent del slice de 2a se conservan, como acción secundaria en la barra y entrada por intent.)

## Fuera de 2b

Búsqueda, sort, filtros (2c). Persistencia del índice en Hive (MediaStore on-demand sigue bien). Siguiente/anterior en el reproductor con la cola (la cola ya existe desde 2a; el control UI de next/prev se puede sumar cuando se diseñe).
