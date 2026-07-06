# Kivo — Swipe-abajo desde arriba = rotar (diseño)

**Fecha:** 2026-07-06
**Estado:** Diseño aprobado por el usuario; arrancar directo.
**Contexto:** Hoy el arrastre vertical que empieza en la franja superior **o** en los laterales minimiza el reproductor (`inDismissZone` = top strip OR lateral strips, en `gesture_math.dart`, usado por `player_gestures.dart`). El usuario quiere reasignar el swipe-abajo desde arriba a **rotar la pantalla**, dejando los laterales para minimizar.

## 1. Comportamiento

- **Franja superior** (justo bajo la zona de gestos del sistema, `y < topInset + margin`), **swipe hacia abajo** → rota: `orientationProvider.cycle()` (alterna portrait↔landscape, igual que el botón de rotar). **Discreto**: al soltar (`onVerticalDragEnd`), si el arrastre neto fue hacia **abajo** y superó un umbral de distancia (~48 px), rota, con un háptico sutil (respeta `hapticsOnGestures`). No es un arrastre "en vivo" (no mueve nada mientras arrastras).
- **Franjas laterales** (bordes izq/der, `inLateralDeadZone`), arrastre vertical → **siguen minimizando** (sin cambios en esa rama).
- La franja superior **se quita** del dismiss: minimizar queda solo por los laterales.
- **Solo audio** (bloqueado a portrait, sin rotar): el swipe-abajo desde arriba **no hace nada** (coherente con que ahí la rotación está deshabilitada y el botón de rotar está oculto).
- Prioridad de zonas en `onVerticalDragStart`: (1) top → rotar; (2) lateral → dismiss; (3) resto → brillo (izq) / volumen (der). El top se evalúa primero, así que las esquinas superiores cuentan como rotar.

## 2. Cambios

**`lib/player/control/gesture_math.dart`:**
- Nuevo `bool inTopRotateZone(double localY, double topInset, double topMargin) => localY < topInset + topMargin;`
- Eliminar `inDismissZone` (su clausula "top OR lateral" ya no aplica); el dismiss pasa a usar `inLateralDeadZone` directamente.

**`lib/ui/player/gestures/player_gestures.dart`:**
- `_onVerticalStart`: primero `_isTopRotate = inTopRotateZone(dy, _topInset, _deadMargin)` → si true, `_rotateDy = 0` y `return` (no engancha dismiss ni brillo/volumen). Si no, `_isDismiss = inLateralDeadZone(dx, _width, _lateralMargin)` (dismiss ya solo lateral); resto igual.
- `_onVerticalUpdate`: si `_isTopRotate`, acumula `_rotateDy += d.delta.dy` y `return` (no toca dismiss/brillo/volumen).
- `_onVerticalEnd`: si `_isTopRotate` → `_isTopRotate = false`; si `_rotateDy >= 48` (hacia abajo) **y** no está en Solo audio (`!ref.read(audioOnlyProvider)`), `ref.read(orientationProvider.notifier).cycle()` + `_haptic()`. Reset `_rotateDy = 0`.
- Nuevos campos `bool _isTopRotate = false; double _rotateDy = 0;`. Imports de `orientation_state.dart` y `audio_only.dart`.

## 3. Testing

- **Puro (`gesture_math_test.dart`):** `inTopRotateZone` true en la franja superior, false debajo; actualizar el test de `inDismissZone` (que se elimina) → el dismiss ahora es `inLateralDeadZone` (ya cubierto).
- **Widget (`player_gestures_test.dart` o nuevo):** un drag vertical hacia abajo que empieza en la franja superior dispara `orientationProvider.cycle()` (portrait→landscape); un drag hacia abajo desde el centro NO rota; en Solo audio, el drag superior no rota. (Usar el `NoopControls`/overrides existentes de los tests de gestos.)
- **Device (Pixel 6):** swipe-abajo desde arriba alterna vertical/horizontal con háptico; swipe vertical desde un borde lateral minimiza; en Solo audio el swipe superior no hace nada; el swipe superior ya no minimiza.

## Fuera de alcance

- Rotación "en vivo" siguiendo el dedo.
- Cambiar la semántica de `cycle()` (sigue alternando portrait↔landscape).
- Gestos nuevos en otras zonas.
