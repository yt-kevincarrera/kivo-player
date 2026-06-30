# Kivo — Pasada de micro-animaciones (Diseño)

**Fecha:** 2026-06-30
**Estado:** Diseño aprobado
**Hito:** 1 (polish)

## Alcance

Animaciones táctiles/"bonitas", todas baratas (AnimationControllers sobre widgets chicos), on-brand (dorado configurable, oscuro):

1. **Ripple de doble-tap** (spec Hito 1 §6, "animación de onda").
2. **Morph play/pausa.**
3. **Press táctil** en botones centrales.
4. **Nudge de chevrons** ±10s.
5. **Knob del seek crece** al arrastrar.

Fuera: animar el cambio de aspecto/rotación; stagger de barras; count-up del readout de velocidad.

## 1. Ripple de doble-tap

Archivos: `lib/ui/player/gestures/ripple_state.dart`, `lib/ui/player/gestures/ripple_overlay.dart`; modifica `player_gestures.dart`, `player_screen.dart`.

- `RippleEvent { bool left; int seconds; int id }`. `rippleProvider = StateProvider<RippleEvent?>`.
- `RippleController` (Provider): acumula como `SkipFeedback` — saltos del mismo lado dentro de una ventana de **1000 ms** suman `seconds`; cambio de lado o expiración reinicia. Cada `bump(left, delta)` incrementa un `id` monotónico y publica `RippleEvent(left, total, id)`. Ventana vía `Timer` (cancelar en `dispose` con `ref.onDispose`).
- `_onDoubleTap` (en `player_gestures.dart`): los casos `left`/`right` llaman `ref.read(rippleControllerProvider).bump(left: …, …)` **en vez de** `skipFeedbackProvider.bump(...)` (el chip ya no sale en doble-tap). `ctrl.skipBy(...)` y `_haptic()` se mantienen. El caso `center` (pausa) sin cambios. Los botones ±10s y el drag-seek siguen usando el chip (`skipFeedbackProvider`).
- `RippleOverlay` (ConsumerStatefulWidget + SingleTickerProviderStateMixin): observa `rippleProvider`; al cambiar `id`, `controller.forward(from: 0)` (~450ms, `Curves.easeOut`). Render: en la **mitad** tocada (Align izq/der), una **onda radial** (un círculo que escala de ~0.3→1.4 con opacidad 0.35→0, dibujado con `CustomPaint` o un `Container` circular en `Transform.scale`+`Opacity`) detrás de los **chevrons** (`KivoIcons.skipBack`/`skipForward`, blanco) + el texto **"${seconds}s"** (dorado), que aparecen y se desvanecen con la onda. `IgnorePointer` (no bloquea gestos). Cuando no hay animación activa → `SizedBox.shrink()`.
- Se compone en el `Stack` de `player_screen` (encima del video, debajo de los controles, dentro del wrapper de dismiss).

## 2. Morph play/pausa

Archivo: `center_controls.dart`.
- El `icon:` del botón play/pausa pasa a un `AnimatedSwitcher` (duration 200ms) con `transitionBuilder` = `ScaleTransition` + `FadeTransition`; child keyed por `playing` (`KivoIcon(playing ? pause : play, key: ValueKey(playing))`). Mantiene tamaño 56, color, aro dorado.

## 3. Press táctil (botones centrales)

Archivo: `center_controls.dart`.
- Widget reutilizable `_PressBounce` (StatefulWidget): envuelve un hijo en un `Listener` (`onPointerDown` → `_pressed=true`; `onPointerUp`/`onPointerCancel` → `_pressed=false`) + `AnimatedScale(scale: _pressed ? 0.92 : 1.0, duration 90ms, curve easeOut)`. El `Listener` **no consume** el evento (el `IconButton` interno sigue recibiendo el tap; tooltip/a11y/aro intactos). Se envuelven los tres botones centrales (⏪, play/pausa, ⏩).

## 4. Nudge de chevrons (±10s)

Archivo: `center_controls.dart`.
- Extraer un `_SkipButton` (ConsumerStatefulWidget + SingleTickerProviderStateMixin) para cada botón de salto: posee un `AnimationController` (~220ms). `onPressed` hace el salto (igual que hoy: `ctrl.skipBy` + `rippleController`/feedback ya viven en gestos — aquí es el botón, que usa `skipFeedbackProvider` como hoy) y dispara `controller.forward(from:0)`. El chevron se traslada con un tween que va `0 → ±4px → 0` (back = −4 para retroceder, +4 para avanzar) vía `Curves.easeOut`; el "${skip}s" no se mueve. Mantiene `_PressBounce`, tamaño, color, tooltip.

## 5. Knob del seek crece al arrastrar

Archivo: `seek_bar.dart`.
- `SeekBar` pasa a `ConsumerStatefulWidget` + `SingleTickerProviderStateMixin` con un `AnimationController _thumbAnim` (~160ms). `ref.listen(scrubProvider)`: al pasar a no-null → `forward`; a null → `reverse`.
- `_GrowingThumbShape extends SliderComponentShape`: recibe el `AnimationController` como `Listenable` (repaint) y pinta el thumb con radio `lerp(7, 11, anim.value)` en `accent`. `SliderTheme(data: SliderThemeData(thumbShape: _GrowingThumbShape(_thumbAnim, accent), ...))` envuelve el `Slider`. El resto del `SeekBar` (scrub/commit, etiquetas, toggle) sin cambios.

## Performance

- Ripple: el overlay solo monta los hijos durante la animación (~450ms); fuera, `SizedBox.shrink()`. `IgnorePointer`.
- Morph/press/nudge/thumb: AnimationControllers locales sobre widgets pequeños; repaint acotado (el thumb shape repinta solo el slider).
- Sin rebuilds del árbol grande: el ripple vía su provider aislado; el thumb vía su shape Listenable.

## Testing

- **Unitario (puro/controller):** acumulación del `RippleController` (mismo lado suma dentro de ventana; cambio de lado reinicia; `id` incrementa) con `fake_async`.
- **Widget:** `RippleOverlay` invisible sin evento; al setear `rippleProvider` aparece chevron + "${n}s". Morph: el `AnimatedSwitcher` cambia de ícono al alternar `playing`.
- **Device:** sensación de cada animación (onda, morph, press, nudge, knob), fluidez, sin jank.

## Estructura de archivos

```
lib/ui/player/gestures/ripple_state.dart      (RippleEvent + rippleProvider + RippleController)
lib/ui/player/gestures/ripple_overlay.dart    (RippleOverlay)
lib/ui/player/gestures/player_gestures.dart   (doble-tap → rippleController)
lib/ui/player/player_screen.dart              (monta RippleOverlay en el Stack)
lib/ui/player/controls/center_controls.dart   (morph + _PressBounce + _SkipButton nudge)
lib/ui/player/controls/seek_bar.dart          (_GrowingThumbShape + controller)
```
