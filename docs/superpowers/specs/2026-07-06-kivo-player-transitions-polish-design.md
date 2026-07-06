# Kivo — Pulido de transiciones del reproductor (apertura + salida)

**Fecha:** 2026-07-06
**Estado:** Aprobado para plan
**Alcance:** Cosmético. Dos unidades aisladas: (A) recuperar la animación de apertura "crecer desde el tile" (Hero perdido en el refactor de bottom-tabs) y (B) unificar la animación de encogido de salida para que back-botón y back-sistema encojan igual que el swipe-down.

---

## Contexto

Tras pasar a navegación por bottom-tabs, el reproductor se empuja en el **Navigator raíz** (`Navigator.of(context, rootNavigator: true).push(playerRoute())`) mientras el tile de la biblioteca vive en el **Navigator anidado** del tab. Los `Hero` solo animan dentro de un mismo `Navigator`, así que la animación Hero de apertura (tile → reproductor) dejó de dispararse; hoy la apertura es solo el `FadeTransition` de 240 ms de `playerRoute` ([lib/ui/player/player_route.dart](../../../lib/ui/player/player_route.dart)).

La salida tiene tres caminos y solo uno encoge:
- **Swipe-down:** `PlayerGestures._onVerticalEnd` anima su `_dismissAnim` (0→1), que escribe `dismissProvider`; `PlayerScreen.build` observa `dismissProvider` y aplica slide-down + scale + fade hacia el mini-player; al terminar hace `maybePop()`.
- **Back del top-bar:** `Navigator.of(context).maybePop()` ([lib/ui/player/controls/top_bar.dart:30](../../../lib/ui/player/controls/top_bar.dart)).
- **Back del sistema:** `PopScope(canPop:false)` → `onPopInvokedWithResult` hace minimize + `Navigator.pop()` inmediato ([lib/ui/player/player_screen.dart:379-398](../../../lib/ui/player/player_screen.dart)).

Los dos caminos de back llegan a `PopScope` con `dismissProvider == 0`, así que popean con el fade inverso plano (160 ms), **sin encoger**.

El `Hero` existente sigue en `PlayerScreen` (tag `libhero-<playbackPath>`) con el `flightShuttleBuilder` que suprime el pop-flight. Como el Hero cross-navigator ya no vuela, ese Hero es efectivamente inerte; este diseño lo reemplaza por el mecanismo de crecer-desde-rect y puede retirarse el Hero del tile y del player (ver Parte A, paso 5).

---

## Parte A — Apertura: crecer desde el tile

### A1. `playerRoute` recibe un `originRect` global opcional

`lib/ui/player/player_route.dart`:

```dart
Route<T> playerRoute<T>({Rect? originRect}) => PageRouteBuilder<T>(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (_, __, ___) => const PlayerScreen(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        // En reposo: sin wrappers, para no interferir con los Transform del
        // dismiss (scale/translate) que PlayerScreen aplica al minimizar.
        if (animation.isCompleted) return child;
        // Aperturas sin tile (file-picker, expandir-mini) y TODOS los cierres
        // (status == reverse): fade. El cierre encoge al mini-player; no debe
        // volar de regreso al tile.
        if (originRect == null || animation.status == AnimationStatus.reverse) {
          return FadeTransition(opacity: animation, child: child);
        }
        return GrowFromRect(
          animation: animation,
          origin: originRect,
          child: child,
        );
      },
    );
```

- `originRect` es un rect en coordenadas **globales** (de pantalla). Como el player se empuja en el Navigator raíz, cuyo overlay es de pantalla completa, no hace falta convertir coordenadas.
- `transitionDuration` sube a **300 ms** (era 240) para que el crecimiento se lea. `reverseTransitionDuration` queda en 160.

### A2. Helper puro de interpolación: `growRect`

Nuevo archivo `lib/ui/player/transition/grow_rect.dart` con una función pura testeable:

```dart
import 'package:flutter/widgets.dart';

/// Rect interpolado del crecimiento tile→pantalla. [t] es el valor de la curva
/// (0 = tile, 1 = pantalla completa). Devuelve [full] si [origin] es degenerado.
Rect growRect(Rect origin, Rect full, double t) {
  final c = t.clamp(0.0, 1.0);
  return Rect.lerp(origin, full, c) ?? full;
}
```

### A3. Widget `GrowFromRect`

En el mismo archivo `lib/ui/player/transition/grow_rect.dart`:

```dart
class GrowFromRect extends StatelessWidget {
  final Animation<double> animation;
  final Rect origin;
  final Widget child;
  const GrowFromRect({
    super.key,
    required this.animation,
    required this.origin,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final full = Offset.zero & size;
    final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: curve,
      builder: (context, _) {
        final t = curve.value;
        final rect = growRect(origin, full, t);
        // Matrix4 que mapea la pantalla completa dentro de [rect]: primero
        // trasladar a rect.topLeft, luego escalar (no uniforme) al tamaño de
        // rect. La distorsión momentánea del scale no-uniforme es imperceptible
        // en ~300 ms y es el patrón estándar de container-transform.
        final sx = full.width == 0 ? 1.0 : rect.width / full.width;
        final sy = full.height == 0 ? 1.0 : rect.height / full.height;
        final m = Matrix4.identity()
          ..translate(rect.left, rect.top)
          ..scale(sx, sy);
        return Opacity(
          // El contenido aparece un poco antes de llegar al tamaño completo.
          opacity: (t * 1.4).clamp(0.0, 1.0),
          child: ClipRect(
            child: Transform(
              transform: m,
              // Sin hit-tests durante el vuelo (el gesto llega al completar).
              transformHitTests: false,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
```

### A4. Plomería del `originRect` desde el tile

`lib/ui/home/widgets/video_tile.dart` pasa de `ConsumerWidget` a `ConsumerStatefulWidget`:

- El campo `onTap` cambia de `VoidCallback` a `void Function(Rect? origin)`.
- El State tiene un `GlobalKey _thumbKey = GlobalKey()` **estable** (campo, no recreado en build), colocado sobre el `ClipRRect` de 16:9 en **ambos** layouts (`_buildCover` y `_buildListRow`).
- El `PressBounce.onTap` de ambos layouts llama a un handler del State:

```dart
void _handleTap() {
  final box = _thumbKey.currentContext?.findRenderObject() as RenderBox?;
  Rect? origin;
  if (box != null && box.hasSize) {
    final topLeft = box.localToGlobal(Offset.zero);
    origin = topLeft & box.size;
  }
  widget.onTap(origin);
}
```

- El `GlobalKey` va en el `ClipRRect` que envuelve la miniatura 16:9 (el de `borderRadius` 12 en cover, el de `borderRadius` 8 en list-row) — así el rect es el de la miniatura, no el de toda la fila (que incluye la columna de texto y el botón de opciones en list-row).

### A5. Retirar el Hero inerte

- En `video_tile.dart`, quitar los dos `Hero(tag: 'libhero-${video.uri}', child: ThumbnailImage(...))` y dejar `ThumbnailImage(video.id)` directo (el Hero ya no vuela cross-navigator; el crecimiento lo aporta la ruta).
- En `lib/ui/player/player_screen.dart`, reemplazar el `Hero(... flightShuttleBuilder ...)` que envuelve `videoBox` (líneas ~449-463) por `videoBox` directo dentro del `Positioned.fill`. Eliminar la variable `heroTag` (línea ~407) que queda sin uso.

### A6. Sitios de push

- `lib/ui/home/library_screen.dart`:
  - `_open(VideoItem v, List<VideoItem> all, Rect? origin)` — nueva firma; el `VideoTile` lo invoca con `onTap: (origin) => _open(v, all, origin)`. Reenvía `playerRoute(originRect: origin)`.
  - `_openPath` / `_pick` (file-picker): siguen llamando `playerRoute()` sin rect → fade.
- `lib/ui/home/folder_screen.dart`: `_open` idéntico — nueva firma con `Rect? origin`, `onTap: (origin) => _open(v, all, origin)`, `playerRoute(originRect: origin)`.
- `lib/ui/mini_player/mini_player_bar.dart`: expandir sigue con `playerRoute()` sin rect → fade.

---

## Parte B — Salida: funnel de encogido unificado

### B1. API compartida por provider

Nuevo archivo `lib/ui/player/state/player_dismiss_state.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Acciones del encogido de salida del reproductor, publicadas por PlayerScreen
/// (que posee el AnimationController) para que los gestos y los caminos de back
/// disparen el mismo encogido. Null mientras no hay un PlayerScreen montado.
class PlayerDismissApi {
  final void Function() complete; // encoge → minimiza → pop
  final void Function() cancel;   // vuelve a 0 (drag no confirmado)
  const PlayerDismissApi({required this.complete, required this.cancel});
}

final playerDismissProvider = StateProvider<PlayerDismissApi?>((ref) => null);
```

### B2. `PlayerScreen` posee el controller y publica la API

`lib/ui/player/player_screen.dart` (el State ya es un `ConsumerState`; añadir `SingleTickerProviderStateMixin` si no lo tiene — verificar en implementación):

- Campo `late final AnimationController _dismissCtl;` (reemplaza la responsabilidad que tenía `_dismissAnim` en `PlayerGestures`), `duration: 300ms`, con listener que escribe `dismissProvider`.
- Campo `bool _dismissing = false;` (guard anti-reentrada).
- En `initState`: crear `_dismissCtl` con el listener; **registrar la API** en un post-frame callback para evitar modificar un provider durante el montaje:

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (!mounted) return;
  ref.read(playerDismissProvider.notifier).state = PlayerDismissApi(
    complete: _completeDismiss,
    cancel: _cancelDismiss,
  );
});
```

- En `dispose`: `_dismissCtl.dispose();` y limpiar la API. El reproductor es una ruta de pantalla completa que nunca coexiste con otra instancia, así que anular sin condición es seguro:

```dart
ref.read(playerDismissProvider.notifier).state = null;
```

- Métodos:

```dart
void _completeDismiss() {
  if (_dismissing) return;
  _dismissing = true;
  if (!_previewCaptured) _captureMiniPreview();
  _dismissCtl.value = ref.read(dismissProvider);
  // Duración proporcional a lo que resta, para que un back desde 0 tarde ~240ms
  // y un swipe casi completo termine rápido.
  final remaining = 1.0 - _dismissCtl.value;
  _dismissCtl
      .animateTo(1.0, duration: Duration(milliseconds: (240 * remaining).round().clamp(80, 240)))
      .then((_) {
    if (!mounted) return;
    _engine.pause();
    _saveProgress();
    ref.read(minimizedSessionKeyProvider.notifier).state = _resumeKey;
    ref.read(playerMinimizedProvider.notifier).state = true;
    Navigator.of(context).pop(); // pop() incondicional (no re-entra PopScope)
  });
}

void _cancelDismiss() {
  _dismissCtl.value = ref.read(dismissProvider);
  _dismissCtl.animateBack(0.0);
}
```

- El listener de `_dismissCtl`:

```dart
_dismissCtl.addListener(() {
  ref.read(dismissProvider.notifier).state = _dismissCtl.value;
});
```

Nota sobre no resetear `dismissProvider` tras el pop: igual que hoy, se deja en 1.0; `PlayerScreen._start()` lo resetea a 0 en la próxima apertura. La lógica actual (`_start` línea ~158 `dismissProvider = 0`) se conserva.

### B3. `PopScope` funnelea a `complete()`

`lib/ui/player/player_screen.dart`, `onPopInvokedWithResult`:

```dart
onPopInvokedWithResult: (didPop, result) {
  if (didPop) return;
  final api = ref.read(playerDismissProvider);
  if (api != null) {
    api.complete();
  } else {
    // Fallback (API aún no registrada, ventana de 1 frame): comportamiento
    // previo inmediato.
    _engine.pause();
    _saveProgress();
    if (!_previewCaptured) _captureMiniPreview();
    ref.read(minimizedSessionKeyProvider.notifier).state = _resumeKey;
    ref.read(playerMinimizedProvider.notifier).state = true;
    Navigator.of(context).pop();
  }
},
```

Esto cubre **back del sistema** (PopScope directo) y **back del top-bar** (`maybePop()` → bloqueado por `canPop:false` → `onPopInvoked`). El top-bar **no cambia**.

### B4. `PlayerGestures` delega en la API

`lib/ui/player/gestures/player_gestures.dart`:

- Eliminar `late final AnimationController _dismissAnim;`, su creación en `initState` y su `dispose`. Quitar `SingleTickerProviderStateMixin` **solo si** no lo usa otro controller del mismo State (verificar en implementación; si lo comparte, dejar el mixin).
- `_onVerticalEnd`, rama de dismiss (líneas ~185-208):

```dart
if (!_isDismiss) return;
_isDismiss = false;
final progress = ref.read(dismissProvider);
final velocityY = d.primaryVelocity ?? 0;
final commit = progress >= 0.25 || velocityY > 700;
final api = ref.read(playerDismissProvider);
if (commit) {
  if (api != null) {
    api.complete();
  } else {
    ref.read(dismissProvider.notifier).state = 0; // fallback defensivo
    Navigator.of(context).maybePop();
  }
} else {
  api?.cancel();
}
```

- El seguimiento durante el drag (`_onVerticalUpdate` escribiendo `dismissProvider` directo) **no cambia**.

---

## Unidades y límites

1. **`grow_rect.dart`** (`growRect` + `GrowFromRect`): puro/visual, sin dependencias del dominio. Consumido solo por `player_route.dart`.
2. **`player_route.dart`**: decide fade vs crecer según `originRect`/dirección.
3. **`video_tile.dart`**: captura y emite el rect global de la miniatura.
4. **`player_dismiss_state.dart` + PlayerScreen**: única fuente del encogido; API publicada por provider.
5. **`player_gestures.dart` / PopScope**: consumidores de la API.

---

## Testing

Por ser UI/animación, tests pragmáticos:

- **Unit** (`test/ui/player/transition/grow_rect_test.dart`): `growRect`
  - `t=0` → `origin`; `t=1` → `full`; `t=0.5` → `Rect.lerp(origin, full, 0.5)`.
  - `t` fuera de [0,1] se clampa.
  - `origin` degenerado (`Rect.zero`) no lanza.
- **Widget** (`test/ui/player/player_dismiss_test.dart`): montar un PlayerScreen mínimo (o un stub que registre la API), simular back del sistema y verificar que `dismissProvider` transita a 1.0 **antes** de que la ruta popee (bombear frames intermedios y aseverar un valor intermedio > 0 y < 1, luego 1.0). Si montar PlayerScreen completo es inviable en test, cubrir `PlayerDismissApi` con un test que verifique que `complete()` mueve el provider vía un controller de prueba.
- **Checklist en dispositivo** (release, Pixel 6):
  - Abrir desde tile de **biblioteca** (cover) → crece desde la miniatura.
  - Abrir desde tile de **carpeta** → crece desde la miniatura.
  - Abrir desde tile en modo **lista** → crece desde la miniatura izquierda (no desde toda la fila).
  - Abrir por **file-picker** y por **expandir mini-player** → fade suave (sin salto).
  - Salir por **swipe-down**, **back del top-bar** y **back del sistema** → los tres encogen idéntico hacia el mini-player.
  - Scrollear para que el tile de origen quede fuera de vista, abrir otro, salir → sin glitch.

---

## Restricciones globales

- Un solo acento configurable (oro por defecto); nada hardcodeado nuevo de color en estas transiciones.
- No `flutter run`; build release + `adb install` al Pixel 6 (`24231FDF6006ST`) tras cerrar el módulo.
- Mantener el patrón de providers de Riverpod del proyecto; no introducir estado global fuera de providers.
- El cierre sigue minimizando al mini-player (no vuelve al tile).
```
