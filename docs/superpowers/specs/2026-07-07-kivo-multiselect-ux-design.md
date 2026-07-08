# Kivo — Pulido UX de la multi-selección (presión, háptico, acciones abajo)

**Fecha:** 2026-07-07
**Estado:** Aprobado para plan
**Alcance:** Tres refinamientos de UX sobre la multi-selección de la biblioteca ya entregada: (1) indicador visual al mantener presionado un tile; (2) feedback háptico al marcar; (3) mover las acciones batch (Compartir/Borrar) de la `SelectionAppBar` (arriba-derecha) a una barra **inferior** alcanzable con el pulgar. Vault sigue siendo futuro.

---

## Contexto

- `VideoTile` (`lib/ui/home/widgets/video_tile.dart`) es un `ConsumerStatefulWidget`; el long-press se cablea con un `GestureDetector(onLongPress: widget.onLongPress)` que envuelve `PressBounce` (modo pulse para el tap). Durante el hold no hay feedback visual.
- El feed (`video_density_feed.dart`) pasa `onLongPress: () => sel.toggle(v.uri)` y `onTap: (o) => selecting ? sel.toggle(v.uri) : onOpen(...)`, con `sel = ref.read(librarySelectionProvider.notifier)`.
- `SelectionAppBar` (`lib/ui/home/widgets/selection_app_bar.dart`) es la barra contextual superior: X · "N seleccionados" · Seleccionar todo · **Compartir · Borrar** (estos dos se mueven abajo). Resuelve `chosen = allVisible ∩ selected`.
- `HomeShell` (`lib/ui/home/home_shell.dart`) es `StatefulWidget`: `Scaffold(body: Column([Expanded(IndexedStack(LibraryScreen, SettingsScreen)), MiniPlayerBar()]), bottomNavigationBar: _BottomTabBar)`. La biblioteca y las carpetas viven dentro del tab Videos, así que el fondo (mini-player + tabs) es del HomeShell y aplica a ambas.
- `librarySelectionProvider` (`StateNotifier<Set<String>>`) — activo ⇔ no vacío.
- `mediaIndexProvider` — todos los videos indexados (fresco tras refresh).

## 1. Indicador de presión (long-press)

`VideoTile` muestra un `AnimatedScale` a **0.95** mientras se mantiene presionado, disparado por el `GestureDetector`:
- `onLongPressDown` → `setState(_pressing = true)`.
- `onLongPressCancel` / `onLongPressEnd` (o `onLongPressUp`) → `setState(_pressing = false)`.
- `AnimatedScale(scale: _pressing ? 0.95 : 1.0, duration: 220ms, curve: easeOut)` envolviendo el contenido del tile (por fuera del `PressBounce` de tap, para no interferir con el pulse del tap).

Un tap rápido apenas mueve la escala (la animación es más lenta que el tap → flash despreciable); un hold real se ve “hundiéndose” hacia la marca. Aplica a ambos layouts (cover y list-row).

## 2. Háptico al marcar

Al alternar la selección se dispara `HapticFeedback.selectionClick()` — tanto al **entrar** al modo por long-press como al alternar con tap. Se centraliza en los call sites del feed (`video_density_feed.dart`), envolviendo la llamada a `sel.toggle(v.uri)` con el háptico (un helper local `_toggle(sel, uri)` que hace `HapticFeedback.selectionClick(); sel.toggle(uri);`). El checkbox de cabecera de día (`sel.toggleAll`) también dispara el háptico. Incondicional (es una confirmación discreta esperada; no se ata a `hapticsOnGestures`, que es de gestos del reproductor).

Import: `package:flutter/services.dart` (`HapticFeedback`).

## 3. Acciones abajo (barra inferior alcanzable con el pulgar)

### 3.1 `SelectionAppBar` (arriba) queda solo con contexto
Quitar los `IconButton` de **Compartir** y **Borrar**. Deja: leading X (`sel.clear`), título "N seleccionado(s)", y **Seleccionar todo** (que necesita `allVisible`, ya presente). El parámetro `allVisible` se conserva para "Seleccionar todo".

### 3.2 Nueva `SelectionBottomBar` (abajo)
`lib/ui/home/widgets/selection_bottom_bar.dart` — `ConsumerWidget` con dos acciones grandes (icono + etiqueta), theme-aware:
- **Compartir** (`share`) → `controller.shareMany(chosen)` + `sel.clear()`.
- **Borrar** (`delete`, color `error`) → confirm `AlertDialog` ("¿Borrar N videos?") → `maybeOfferAllFilesAccess(context, ref)` → `controller.deleteMany(chosen)` → SnackBar (ok/error) + `sel.clear()` en ok. `messenger` pre-capturado; guardas `context.mounted` tras cada await.
- `chosen` = `(ref.watch(mediaIndexProvider).valueOrNull ?? []).where((v) => selected.contains(v.uri)).toList()` — resuelto desde el índice ∩ seleccionadas (funciona en biblioteca y en carpeta sin depender de la lista visible; el índice es fresco). Acciones deshabilitadas si `chosen.isEmpty`.
- Envuelta en `SafeArea` (respeta la barra de gestos del sistema).

La lógica batch (confirm/offer/deleteMany/shareMany/snackbars) se **mueve** de `SelectionAppBar` a `SelectionBottomBar` (misma lógica, distinta ubicación y origen de `chosen`).

### 3.3 `HomeShell` conmuta el fondo en modo selección
`HomeShell` pasa a `ConsumerStatefulWidget`. Observa `librarySelectionProvider`:
- `final selecting = ref.watch(librarySelectionProvider).isNotEmpty;`
- `bottomNavigationBar: selecting ? const SelectionBottomBar() : _BottomTabBar(index: _index, onTap: _select)`.
- El `MiniPlayerBar` del `Column` se oculta en selección: `if (!selecting) const MiniPlayerBar()`.
- Al limpiar la selección, vuelven tabs + mini-player.

Cubre biblioteca y carpetas (ambas bajo el tab Videos). El `SelectionAppBar` superior sigue en `library_screen`/`folder_screen` (contexto + cerrar + seleccionar todo); las acciones viven abajo.

## Unidades y límites

1. **`video_tile.dart`** — `AnimatedScale` de presión en el long-press.
2. **`video_density_feed.dart`** — háptico en los toggles (tile + cabecera de día).
3. **`selection_app_bar.dart`** — quitar Compartir/Borrar (queda X + contador + seleccionar todo).
4. **`selection_bottom_bar.dart`** (nuevo) — Compartir/Borrar + lógica batch; `chosen` desde el índice.
5. **`home_shell.dart`** — `ConsumerStatefulWidget`; conmuta bottomNavigationBar y oculta mini-player en selección.

## Testing

- **Widget:**
  - `SelectionBottomBar`: muestra Compartir/Borrar; con `chosen` no vacío, tocar dispara `shareMany`/`deleteMany` (con `FakeMediaFileOps`/controller); vacío → deshabilitadas.
  - `HomeShell`: sin selección muestra tabs + mini-player; con `librarySelectionProvider` no vacío muestra `SelectionBottomBar` y oculta el mini-player.
  - `SelectionAppBar`: ya no muestra Compartir/Borrar; sí X + contador + Seleccionar todo.
- **Puro (si se extrae):** `chosenFromIndex(index, selected)` → filtra el índice por las uris seleccionadas.
- **Dispositivo (release, Pixel 6):**
  - Mantener presionado un tile → se ve el “hundimiento” (escala) durante el hold, y al marcarse hay un tic háptico.
  - En modo selección: los tabs se reemplazan por la barra inferior con Compartir/Borrar (alcanzable con el pulgar), el mini-player se oculta; arriba queda X + "N" + Seleccionar todo.
  - Compartir N / Borrar N desde la barra inferior funcionan (chooser / confirm+borrado); al terminar sale del modo y vuelven tabs + mini-player.
  - En una carpeta: mismo comportamiento (barra inferior de acciones).
  - Tocar tiles alterna con háptico; deseleccionar el último sale del modo (vuelven tabs/mini-player).

## Restricciones globales

- Un solo acento; sin colores nuevos hardcodeados (Borrar usa `colorScheme.error`).
- Reutiliza `videoActionsProvider.deleteMany/shareMany`, `maybeOfferAllFilesAccess`, `librarySelectionProvider` (no se re-implementan).
- `HomeShell` observa la selección vía Riverpod (sin estado global fuera de providers).
- No `flutter run`; build release + `adb install` al Pixel 6 al cerrar.
- Suite completa verde.
- No romper: navegación por tabs normal (sin selección), back del sistema en selección (sigue limpiando), la barra superior de contexto.
