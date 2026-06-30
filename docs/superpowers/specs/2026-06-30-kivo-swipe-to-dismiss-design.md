# Kivo — Swipe-down-to-dismiss + lateral dead zones (Diseño)

**Fecha:** 2026-06-30
**Estado:** Diseño aprobado
**Hito:** 1 (polish de gestos)

## Problema

Al intentar salir del reproductor con un gesto desde el borde, se dispara el **seek horizontal** (no hay zonas muertas laterales; solo arriba/abajo). El usuario quiere (1) franjas muertas laterales un pelín más grandes que no disparen seek, y (2) un gesto de **arrastrar hacia abajo para cerrar** el reproductor con animación, estilo visor de fotos.

## Decisiones (aprobadas)

- **Interactivo**: el reproductor sigue el dedo hacia abajo; al soltar, si pasa el umbral se desliza y cierra, si no regresa.
- **Zonas**: franja superior + franjas laterales izq/der. En esas zonas se suprime el seek; un arrastre hacia abajo cierra.

## Zonas muertas

- Hoy: `inVerticalDeadZone(localY, height, topInset, bottomInset, margin=24)` (franjas arriba/abajo) gatea brillo/volumen y seek.
- **Nuevo**: franjas laterales izq/der de ~**38 dp** (`_lateralMargin`). Helper puro `inLateralDeadZone(localX, width, margin)`.
- **Seek**: `_onHorizontalStart/Update` ahora también bailan si el toque empieza en una franja lateral (deja de correr el video al salir por el borde).
- **Zona de cierre (dismiss zone)** = franja superior (`localY < topInset + margin`) **o** franja lateral (`inLateralDeadZone`). NO incluye la franja inferior (ahí viven los controles). Helper puro `inDismissZone(localX, localY, width, topInset, lateralMargin, topMargin)`.

## Gesto de cierre (interactivo)

En `PlayerGestures` (ya arbitra los arrastres verticales para brillo/volumen):
- `onVerticalDragStart`: si el inicio cae en la **dismiss zone** → `_dismissing = true` (no brillo/volumen). Si cae en la franja inferior (dead) → ignora. Resto → brillo/volumen como hoy.
- `onVerticalDragUpdate` (cuando `_dismissing`): acumula el desplazamiento; `fraction = (deltaYDown / (height * 0.5)).clamp(0,1)` (solo hacia abajo). Escribe `dismissProvider = fraction`. Háptica ligera al cruzar el umbral (0.25) una vez.
- `onVerticalDragEnd` (cuando `_dismissing`): si `fraction >= 0.25` o velocidad hacia abajo alta → **cerrar**; si no → **regresar**. Resetea `_dismissing`.

Animación de snap/salida: `PlayerGestures` gana `SingleTickerProviderStateMixin` + un `AnimationController` que, al soltar, anima `dismissProvider` de su valor actual a `0` (regresa) o a `1` (sale) — al llegar a `1`, `Navigator.of(context).maybePop()`. Durante el arrastre el provider lo maneja el dedo; el controller solo corre en el release.

## Render del desplazamiento

`dismissProvider` (`StateProvider<double>`, 0 normal → 1 fuera). `player_screen` envuelve el `Stack` del cuerpo en un consumidor que aplica, según `d = dismissProvider`:
- `Transform.translate(offset: Offset(0, d * height))` (sigue el dedo / sale por abajo),
- `Opacity(1 - d * 0.4)` (se atenúa),
- `Transform.scale(1 - d * 0.06)` (encoge un pelín).
Aislado en su propio consumidor para que solo el wrapper se redibuje (no todo el árbol). Fondo negro del Scaffold detrás (se ve el negro al deslizar).

## Estructura de archivos

```
lib/player/control/gesture_math.dart      (+ inLateralDeadZone, inDismissZone — puros, testeados)
lib/ui/player/gestures/player_gestures.dart  (dismiss routing + AnimationController + lateral seek suppression)
lib/ui/player/state/dismiss_state.dart     (dismissProvider)
lib/ui/player/player_screen.dart           (Transform/Opacity/Scale wrapper)
```

## Testing

- **Unitario (puro):** `inLateralDeadZone` (bordes izq/der vs centro), `inDismissZone` (top + laterales true; centro y franja inferior false).
- **Widget/manual:** el arrastre-abajo en zona → cierra/regresa; brillo/volumen/seek intactos en el centro; seek suprimido en laterales. La animación + pop se validan en device.

## Fuera

- Cerrar desde la franja inferior (controles). Gestos de cierre en otras direcciones. Animación de ruta personalizada (se usa el pop estándar tras deslizar a 1).
