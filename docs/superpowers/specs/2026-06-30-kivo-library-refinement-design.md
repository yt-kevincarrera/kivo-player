# Kivo — Refinamiento de la biblioteca (Diseño)

**Fecha:** 2026-06-30
**Estado:** Diseño aprobado
**Contexto:** Segunda pasada sobre el rediseño de biblioteca (commits 19d156f→bf0769f) tras feedback en device con captura. El look mejoró pero quedó apretado, los toques fallan, y el pinch/animaciones se sienten mal. El mini-player (C) y 2c siguen después.

## Visión

La biblioteca se siente **espaciosa, táctil y pulida** — como una galería premium. Toques fiables, tipografía/miniaturas cómodas, y un pinch tipo galería con un **reflujo animado** de los tiles (sin fades raros).

## 1. Espaciado y densidad visual (no confundir con `libraryColumns`)

- **Filas de lista (1 col):** separación vertical real entre filas (~14px); hoy están pegadas. Márgenes laterales de página cómodos (~14–16px).
- **Cabeceras de sección** ("Hoy"/"Ayer") y la tira **"Continuar"**: más aire arriba/abajo.
- Nada de elementos tocándose; respiración general.

## 2. Tiles — fila de lista más grande y táctil

- **Miniatura de la fila de lista más grande:** ~150px de ancho (16:9), no ~110.
- **Texto más grande:** título ~15–16px (2 líneas, ellipsis), tamaño (`fmtSize`) ~13px en `onSurfaceVariant`.
- **Toda la fila es tappable:** el `GestureDetector`/área de toque envuelve miniatura **y** texto (hoy solo abre tocando la miniatura). El cover-grid (2/3 col) ya es tappable completo; mantener.
- Mantener el **progreso segmentado dorado** y el badge de duración en ambos modos.

## 3. Feedback de toque — pulso, no scale-down

- Quitar el `PressBounce` de escala-**hacia-abajo** sostenida (se ve horrible cuando tocas durante el scroll).
- Reemplazar por un **pulso al confirmar el tap**: escala 1.0→1.04→1.0 (~150ms, `Curves.easeOut`).
- **Crítico:** el feedback NO debe dispararse cuando un toque se convierte en scroll. Es decir, se activa en el *tap confirmado* (tap-up que no fue arrastre), no en el touch-down. (Esto elimina el "scale down" feo al empezar a hacer scroll.)
- Aplica a tiles (lista y cover), tarjetas de "Continuar" y de carpeta.

## 4. Chips de filtro

- Texto **`Todo`** (antes "Todas") | **`Carpetas`**. Activo = azul (`KivoColors.blue`), inactivo = `surfaceContainerHighest`.
- **Transición `Todo`↔`Carpetas`:** un **slide rápido** (deslizamiento horizontal, ~180–220ms, `Curves.easeOutCubic`) — NO el cross-fade actual (se ve "súper raro"). El nuevo contenido entra deslizando desde el lado correspondiente al sentido del cambio.

## 5. Pinch tipo galería (#7, #8) + reflujo animado (#9)

- **Cualquier dirección (#7):** el gesto de escala con 2 dedos debe ganar al scroll vertical y responder en **cualquier orientación** (in/out), como Google Fotos — no solo horizontal. El reconocedor de escala debe reclamar gestos de 2 punteros independientemente del ángulo.
- **Llegar a 2 columnas (#8):** el pinch cambia **de a una columna por "muesca"** con umbrales calibrados, de modo que **1↔2↔3** sean todas fáciles (hoy salta de 1 a 3). Una muesca = un paso de columna; reset del baseline por muesca; háptica por cambio. Persistir `libraryColumns`.
- **Reflujo animado por pasos (#9):** al cambiar de columnas (por pinch o por el icono de densidad), los tiles **se reacomodan animándose a su nuevo tamaño** (no fade). Implementación: un `AnimationController` (init en `initState`, ~260ms `Curves.easeOutCubic`) que, en cada cambio de columnas, lleva cada tile desde su escala relativa anterior (`prevTileExtent/newTileExtent`) hasta `1.0`, partiendo el grid ya en el nuevo conteo de columnas. Esto da el efecto "reacomodado": al pasar 3→2 los tiles crecen hacia su lugar, 2→3 encogen. Opacidad opcional muy sutil (0.9→1.0), nunca un cross-fade completo.
  - El borde **1-col (fila de lista) ↔ 2-col (cover grid)** cambia de tipo de layout; ahí basta un **settle rápido y limpio** (mismo controller; aparición con escala/slide corto), no un fade.
- **El icono de densidad** comparte el mismo setter de `libraryColumns`, así que dispara el mismo reflujo.

## 6. Animaciones — cuidar el detalle

- Reflujo de pinch/densidad (§5) y slide de chips (§4) son las dos transiciones clave; ambas deben sentirse fluidas y nativas, sin fades raros.
- Mantener la entrada sutil de secciones (fade/slide al aparecer) ya existente, pero verificar que no choque con el reflujo.
- Todo perf-safe: controllers locales bien dispuestos (init en initState, dispose), nada que trabe el scroll. (Lección del proyecto: AnimationController SIEMPRE en initState, nunca como `late final` field-initializer.)

## 7. Archivos (orientativo)

```
lib/ui/home/widgets/video_tile.dart      (fila de lista más grande, toda tappable; progreso/badge intactos)
lib/ui/widgets/press_bounce.dart         (pulso al tap-confirm en vez de scale-down sostenido; no dispara en scroll)
lib/ui/home/library_screen.dart          (espaciado, "Todo", chips slide, pinch any-dir + 2 cols, reflujo AnimationController)
lib/ui/home/widgets/continue_row.dart    (espaciado/tamaños coherentes)
lib/ui/home/folder_grid.dart             (pulso de toque coherente; espaciado)
```

## 8. Testing

- **Puro/widget:** la fila de lista abre al tocar el área de texto (tap en el título dispara onTap); chip dice "Todo"; cambiar a "Carpetas" muestra carpetas; pinch/icono cambian `libraryColumns` 1↔2↔3 y persisten. `flutter test` verde, `flutter analyze` limpio.
- **Device (Pixel 6):** espaciado cómodo; toques fiables en toda la fila; miniaturas/texto a buen tamaño; pulso de toque agradable (sin scale-down feo en scroll); slide de chips limpio; pinch en cualquier dirección, fácil llegar a 1/2/3; reflujo se ve como "reacomodado" (sin fade).

## Fuera

- Mini-player (C). Búsqueda/sort/filtros (2c). Personalización de tema (Hito 4).
