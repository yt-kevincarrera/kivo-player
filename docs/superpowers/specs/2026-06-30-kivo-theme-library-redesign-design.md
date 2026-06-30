# Kivo — Tema claro/oscuro + rediseño de biblioteca (Diseño)

**Fecha:** 2026-06-30
**Estado:** Diseño aprobado
**Contexto:** Rediseño del look de la biblioteca (sobre 2b) + sistema de tema. Tras feedback en device. El **mini-player** (C) y **2c** (búsqueda/sort/filtros) van después.

## Visión

Una biblioteca más limpia, discreta y "premium" inspirada en una app de referencia, con **tema claro/oscuro/auto**. El reproductor sigue oscuro siempre; el tema aplica a la biblioteca y el chrome. Marca constante: **azul** (elemento activo) + **dorado** (progreso/acentos).

## 1. Sistema de tema

- `KivoTheme.light()` y `KivoTheme.dark()` (`ThemeData` completos con `ColorScheme`). Colores suaves: **oscuro NO negro puro** (fondo ~`#0F1218`, superficies `#181C24`/`#1E222B`); **claro cálido** (fondo `#F4F4F2`, superficies `#FFFFFF`). Texto/sec por tema.
- Setting **`themeMode`** (`'auto' | 'light' | 'dark'`, default **`auto`**) en `KivoSettings` (campo/defaults/copyWith/toMap/fromMap). `MaterialApp` usa `theme: light, darkTheme: dark, themeMode:` derivado del setting.
- Las superficies de **biblioteca/chrome** leen de `Theme.of(context)`/`ColorScheme` (no `KivoColors` fijos). Marca: `KivoColors.blue`/`gold` permanecen como acentos en ambos temas.
- **El reproductor (`PlayerScreen` y overlays) se mantiene oscuro siempre** — no se re-tematiza; el video es inmersivo. Esto acota el refactor a la biblioteca/chrome.
- (Personalización fina del tema = Hito 4; aquí solo claro/oscuro/auto.)

## 2. Barra superior

- **Logo "Kivo"** (wordmark) a la izquierda.
- Iconos a la derecha: **densidad** (cicla 1→2→3, funciona ya) · **recientes/orden** y **buscar** (visuales pero **diferidos a 2c** — se muestran deshabilitados con tooltip "próximamente", o se omiten; decisión de implementación: omitir hasta 2c para no tener botones muertos, dejando solo densidad).
- **Chips discretos** debajo (o en la misma fila): **`Todas`** (feed por fecha) | **`Carpetas`** (grilla de carpetas). Activo en azul, inactivos sutiles. (Más chips de filtro en 2c.)

## 3. Densidad (pinch pulido + animado) + icono

- **Mantener el pinch** pero bien hecho: `onScaleUpdate` con umbral cómodo (cambiar de columna al cruzar ~0.85 / ~1.18 de escala acumulada), **una sola mano** tolerada (no exige gesto perfectamente horizontal). `libraryColumns` 1↔2↔3, persistido, con háptica al cambiar.
- **Animar el cambio de grilla:** al cambiar de densidad, transición suave entre layouts (cross-fade/scale ~250ms, `Curves.easeOut`) — no un salto seco. (Implementación sugerida: `AnimatedSwitcher` con la grilla keyed por `libraryColumns`, o escalar los tiles durante el pinch y asentar al soltar.)
- **Icono de densidad** en la barra como alternativa de una mano (mismo `libraryColumns`, misma animación).

## 4. Tiles — dos modos

`VideoTile` adapta su layout a la densidad:
- **1 columna = fila de lista limpia:** miniatura 16:9 a la izquierda (~100px, badge de duración + **progreso segmentado dorado** en el borde inferior si hay resume), título (2 líneas) + **tamaño** (`X MB`) a la derecha, en colores del tema.
- **2/3 columnas = tile-cover (galería):** miniatura cover 16:9, título sobre degradado, badge de duración, **progreso segmentado dorado** en el borde inferior si hay resume.
- **Importante:** el **progreso segmentado** va en AMBOS modos cuando el video está a medias (se omitió en el mockup, no en el código).
- Press-scale (`PressBounce`), thumbnail con **fade-in** (shimmer/placeholder), `Hero` al reproductor (ya existe).

## 5. "Continuar"

- Sección arriba del feed (en el tab `Todas`): label cuidado ("Continuar", limpio, sin el "viendo" pesado) + fila horizontal con snap. Tarjetas = cápsula del tema con miniatura, **progreso segmentado dorado**, y el tiempo/loque resta.
- **Orden: más reciente primero** (por `updatedAt`, ya implementado en `continueWatchingProvider`).

## 6. Animaciones (cuidar el detalle)

- **Reflujo de grilla** al cambiar densidad (ver §3).
- **Entrada de secciones/grupos** del feed: fade/slide sutil al aparecer (sin exagerar; barato).
- **Press-scale** en tiles, tarjetas de continuar, chips.
- **Thumbnail fade-in** (ya hecho).
- **Transición suave** al cambiar chip Todas↔Carpetas (cross-fade) y al entrar a una carpeta.
- **Hero** tile→player (ya hecho).
- Todo perf-safe (controllers locales; nada que trabe el scroll).

## 7. Quitar / cambiar

- Quitar el `onScaleUpdate`/pinch actual roto y reemplazar por el pinch pulido + animado.
- Quitar los **tabs gordos** (`_DiscreetTabs` segmentado) → reemplazar por los **chips**.
- Re-tematizar las superficies de biblioteca (LibraryScreen, VideoTile/ListRow, ContinueRow, FolderGrid, FolderScreen) a colores del tema.

## 8. Archivos (orientativo)

```
lib/core/theme/kivo_theme.dart          (light() + dark())
lib/core/settings/kivo_settings.dart    (+ themeMode)
lib/app.dart                            (theme/darkTheme/themeMode)
lib/ui/home/library_screen.dart         (barra: logo+iconos+chips; pinch pulido+animado; reflujo)
lib/ui/home/widgets/video_tile.dart     (modo lista 1-col vs cover; progreso en ambos)
lib/ui/home/widgets/video_list_row.dart (si conviene separar el modo lista)
lib/ui/home/widgets/continue_row.dart   (pulido + tema)
lib/ui/home/widgets/folder_grid.dart    (tema)
lib/ui/home/folder_screen.dart          (tema)
```

## 9. Testing

- **Puro/widget:** `themeMode` serialización + default auto; `MaterialApp` aplica el modo (light/dark/auto). Densidad: pinch/icono cambian `libraryColumns` (1↔3) + persiste; tile renderiza fila en 1-col y cover en 2-3; progreso segmentado visible cuando hay fracción; chip Todas↔Carpetas cambia la vista; continue order recent-first (ya cubierto).
- **Device:** look claro/oscuro/auto, pinch cómodo + reflujo animado, animaciones de secciones/press fluidas, legibilidad en ambos temas.

## Fuera

- Mini-player (C). Búsqueda/sort/filtros + activar recientes/buscar (2c). Personalización de tema (Hito 4).
