# Kivo — Refinamiento de biblioteca v3 (Diseño)

**Fecha:** 2026-07-01
**Estado:** Diseño aprobado (ejecución autónoma).
**Contexto:** Cuarta pasada sobre la biblioteca tras feedback en device. Corrige la semántica del badge "Nuevo", el inset horizontal, un fade residual al cambiar de pestaña, la actualización de "Continuar viendo", y afina el reflujo. Mini-player (C) y 2c siguen después.

## 1. Badge "Nuevo" = no reproducido (no "reciente")

- **Nuevo significado:** "Nuevo" marca videos que **nunca se han reproducido** (no los agregados hace poco). Descartar el helper `isNewVideo(<3 días)`.
- **Tracking de reproducidos:** las entradas de `resume` solo cubren videos en progreso (los terminados se borran), así que no bastan. Añadir un **set persistido de "reproducidos"** (Hive box `played`, claves = `video.name`, la misma clave que resume/continue).
  - `PlayedStore` (interface) + `HivePlayedStore` + `InMemoryPlayedStore` (tests). `playedStoreProvider` (override en `main.dart`) + `playedKeysProvider` (Provider que devuelve `Set<String>` de claves).
  - **Marcar reproducido al abrir:** en `PlayerScreen._start()`, tras conocer `_resumeKey`, `playedStore.markPlayed(_resumeKey!)` (fire-and-forget).
  - **Biblioteca:** `isNew = !ref.watch(playedKeysProvider).contains(v.name)`. Invalidar `playedKeysProvider` al volver del player (junto a `continueWatchingProvider`), para que el badge desaparezca tras reproducir.

## 2. Inset horizontal de las secciones de video

- Hoy Continuar usa `horizontal: 16` y las secciones de video `20` → solo 4px, se ven alineadas.
- Subir las secciones de video (cabeceras + lista/grid) a **`horizontal: 24`**; Continuar se queda en 16. Diferencia de 8px, claramente más adentro. (No tocar `continue_row.dart`.)

## 3. Quitar el fade residual al cambiar de pestaña

- Al alternar Todo↔Carpetas (PageView) los tiles hacen un **fade raro**: es la **animación de entrada** (`TweenAnimationBuilder` opacity 0→1 + translate) de cabeceras/tiles, que se re-ejecuta cuando el PageView reconstruye la página de videos al volver.
- **Quitar la animación de entrada** de secciones y tiles (renderizarlos directamente). El único movimiento del feed será el reflujo de densidad (§5). El slide del PageView ya es la transición de pestaña.

## 4. "Continuar viendo" se actualiza al instante

- **Causa raíz:** `continueWatchingProvider` se invalida en el `.then` del pop de ruta, pero el guardado de progreso ocurre en `PlayerScreen.dispose()`; la invalidación puede correr antes de que el guardado escriba → el video recién visto no aparece (o no de primero) hasta un refresh posterior.
- **Fix:** **guardar el progreso periódicamente durante la reproducción** (cada ~4s mientras reproduce) además de en `dispose()`. Así la entrada (con `updatedAt` reciente) ya existe antes de salir; al volver, la invalidación la ve y el video sale de primero al instante. También mejora seguridad ante cierres inesperados. (Un `Timer.periodic` en `initState`, cancelado en `dispose`, llamando al `_saveProgress()` existente — que ya filtra por duración/minSeconds.)

## 5. Afinar el reflujo (se siente un poco "buggy")

- El reflujo (`_reflowTile`, escala 0.92→1.0 en cambio de columnas) va mucho mejor pero se siente un poco brusco. Probable causa: la animación de entrada (§3) compite con el reflujo. Al quitar la entrada (§3), el reflujo queda solo.
- Afinar: mantener escala 0.92→1.0 pero curva **`Curves.easeInOut`** y duración **~320ms** para un asentamiento más suave; al reposo devolver el hijo sin transformar (escala 1.0 exacta). (Nada de fade.)

## Testing

- **Puro/widget:** `PlayedStore` marca/lee claves; `playedKeysProvider` refleja el set; `VideoTile` con `isNew:true` muestra "Nuevo"; biblioteca calcula `isNew=!played`. `flutter test` verde, `analyze` limpio.
- **Device:** "Nuevo" solo en no-reproducidos y desaparece tras abrir; secciones de video claramente más adentro que Continuar; sin fade al cambiar de pestaña; "Continuar" muestra el recién visto de primero al instante; reflujo suave.

## Fuera

- Acción real del menú ⋮ (futuro). Mini-player (C). 2c. Reflujo continuo pixel-perfect.
