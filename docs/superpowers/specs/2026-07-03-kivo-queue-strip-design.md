# Kivo — Tira de miniaturas de la cola (Diseño)

**Fecha:** 2026-07-03
**Estado:** Diseño aprobado por mockup; el usuario pidió arrancar directo.
**Contexto:** Feature diferida desde Hito 1 ("tira de miniaturas de la cola"), nunca construida — se esperó a tener la cola real (Hito 2) y ahora encaja con la cola de autoplay. `VideoSession` ya tiene `queue` (URIs) + `queueNames` + `index` (la lista mostrada de la biblioteca, en su orden/filtros). Reutiliza `ThumbnailImage(id)` + `thumbnailProvider.family(id)` (MediaStore, cacheado) ya usados por la biblioteca.

## 1. Comportamiento

- **Qué es:** una tira **horizontal desplazable** de miniaturas de la cola actual (= la lista mostrada que ya usa autoplay: mismo orden, filtros, búsqueda). Vive sobre la barra inferior de controles.
- **Cuándo aparece:** con los controles visibles (mismo tap que revela la barra), **solo si la cola tiene más de un video**, y **solo si `queueStripVisible` está activado** (default true). Un botón nuevo de cola (☰) en la barra inferior la muestra/oculta y **recuerda la preferencia** (persistida en settings).
- **Cada tarjeta:** miniatura 16:9 (~104×60), índice arriba-izquierda; la actual con **borde dorado + cinta "Ahora"** y nombre en dorado; las demás atenuadas con glifo ▶. Debajo, el nombre a 2 líneas.
- **Auto-scroll:** al aparecer (y al cambiar de video), la tira centra la tarjeta actual.
- **Tap:** saltar a ese video reusando el flujo de apertura del reproductor (misma animación/reseteo que autoplay), **sin contar como avance de autoplay** (no decrementa el modo "N episodios" del sleep timer — es una acción manual).
- **Solo audio:** la tira sigue disponible (saltar de pista con pantalla-negra tiene sentido). Se oculta en PiP (toda la capa de controles se oculta ahí).
- **Sin cola / cola de 1 / file-picker:** no se muestra (nada que listar).

## 2. Arquitectura

**Cola / sesión (`lib/player/open/video_source.dart`):**
- `VideoSession` gana `final List<String> queueIds` (paralelo a `queue`/`queueNames`, default `const []`) — los ids de MediaStore para las miniaturas. Se puebla en `openFromList` desde `VideoItem.id`; se propaga en `peekNext`.
- `CurrentVideoNotifier`:
  - `VideoSession? sessionAt(int index)` — construye (sin mutar) la sesión para cualquier índice válido de la cola (uri/name/id por índice, misma `queue`/`queueNames`/`queueIds`/`folder`); null si el índice está fuera de rango. `peekNext()` pasa a delegar en `sessionAt(index + 1)`.

**Estado UI:**
- `queueJumpProvider` (`StateProvider<int?>`, en `lib/ui/player/state/queue_strip_state.dart`) — el índice al que el usuario pidió saltar desde la tira; PlayerScreen lo escucha, salta y lo limpia. (Mismo patrón que `autoplayConfirmProvider`.)

**Settings (`lib/core/settings/kivo_settings.dart`):** `queueStripVisible` (`bool`, default `true`) en los 6 puntos de inserción. (Su toggle de UI definitivo llega con el panel del Hito 4; por ahora se conmuta con el botón ☰.)

**PlayerScreen (`lib/ui/player/player_screen.dart`):**
- Factorizar el avance para distinguir manual de autoplay: `_advance(VideoSession next, {bool countAsAutoplay = true})` — solo llama `sleepTimerProvider.notifier.onAutoplayAdvance()` cuando `countAsAutoplay`.
- `ref.listen(queueJumpProvider)`: al setearse un índice, `final s = sessionAt(idx); if (s != null) _advance(s, countAsAutoplay: false);` y limpiar `queueJumpProvider`.

**UI:**
- **`lib/ui/player/queue/queue_strip.dart`** — `QueueStrip` (ConsumerStatefulWidget): watch `currentVideoProvider` + `settingsProvider.queueStripVisible`; si `queue.length <= 1` o `!queueStripVisible` → `SizedBox.shrink()`. `ListView.builder` horizontal (altura fija ~92) de `_QueueCard`s; `ScrollController` que centra el índice actual en `initState`/post-frame y cuando cambia. `_QueueCard`: `ThumbnailImage(queueIds[i])` (o placeholder si el id no está), índice, borde/cinta dorada si `i == index`, nombre `queueNames[i]`. Tap → `ref.read(queueJumpProvider.notifier).state = i` + `controlsVisibleProvider.show()` (mantener controles visibles).
- **`lib/ui/player/controls/controls_overlay.dart`** — montar `QueueStrip` en el contenedor inferior, **encima** de `BottomBar` (Column: [QueueStrip, BottomBar]).
- **`lib/ui/player/controls/bottom_bar.dart`** — botón ☰ (cola) con `KivoIcons.queue` (nuevo, duotono) que conmuta `settings.queueStripVisible`; dorado cuando la tira está visible.
- **`lib/core/icons/kivo_icons.dart`** — `KivoIcons.queue` duotono (líneas de lista, una en acento).

## 3. Testing

- **Puro:** `queueIds` se puebla en `openFromList` y se propaga en `peekNext`; `sessionAt(i)` devuelve la sesión correcta por índice y null fuera de rango; `queueStripVisible` default true + round-trip.
- **Widget:** la tira se oculta con cola de 1 o `queueStripVisible=false`; muestra N tarjetas con la actual resaltada; tap setea `queueJumpProvider`; el botón ☰ conmuta `queueStripVisible`; (PlayerScreen) un `queueJumpProvider` seteado dispara `_advance(autoplay:false)` → reabre esa sesión y NO decrementa el sleep "N episodios".
- **Device (Pixel 6):** con una carpeta de varios videos, la tira aparece con los controles, centra la actual, tocar otra salta con su apertura; ☰ la oculta/muestra y lo recuerda; en Solo audio también salta; en PiP no aparece; salto manual no descuenta el sleep "N episodios".

## Fuera de alcance

- Reordenar la cola / arrastrar tarjetas.
- Duración por tarjeta (posible mejora futura; v1 muestra miniatura + índice + nombre).
- Cola entre carpetas distintas (sigue siendo la lista mostrada, igual que autoplay).
- UI del toggle en el panel de ajustes (llega con Hito 4; por ahora el botón ☰).
