# Kivo — Mini-player (Diseño)

**Fecha:** 2026-07-01
**Estado:** Diseño aprobado.
**Contexto:** Hito 2 / bloque C. Al salir del reproductor (botón, back del sistema, o swipe-down) hoy siempre se cierra del todo. Se pidió que en su lugar se minimice a una barra inferior pausada, permitiendo seguir navegando la biblioteca y retomar el video sin perder el lugar. 2c (búsqueda/filtros) sigue después.

## 1. Alcance de la decisión

- **Toda salida minimiza** (botón del top bar, back del sistema, swipe-down) — ninguna cierra el reproductor del todo directamente. Cerrar del todo es una acción explícita desde la mini-barra.
- **Se pausa siempre** al minimizar (no hay reproducción en segundo plano).
- **Global:** la mini-barra flota sobre cualquier pantalla de la app (biblioteca, dentro de una carpeta, etc.), no solo en `LibraryScreen`.
- **Expandir:** tap en la barra reabre el reproductor reutilizando el flujo de reanudar existente (aceptamos un posible parpadeo/recarga breve — decisión consciente por simplicidad, no continuidad de sesión sin recarga).
- **Cerrar del todo:** botón X en la barra, o swipe lateral sobre ella (usando `Dismissible`).

## 2. Modelo de estado

Un solo booleano nuevo, app-scoped:

```dart
final playerMinimizedProvider = StateProvider<bool>((ref) => false);
```

- **Minimizar:** el handler `PopScope.onPopInvokedWithResult` de `PlayerScreen` (que ya guarda el progreso antes de hacer pop — fix de la ronda anterior) captura un frame de preview (§4), guarda progreso, pone `playerMinimizedProvider.state = true`, y recién entonces hace `navigator.pop()`.
- **`_start()`** (toda apertura de video, sea nueva o al reexpandir desde la mini-barra) resetea `playerMinimizedProvider = false` — nunca se "aterriza" minimizado.
- **Cerrar del todo desde la mini-barra:** solo `playerMinimizedProvider.state = false`. No hace falta tocar `currentVideoProvider` (nunca se limpia hoy; se sobreescribe en la próxima apertura) ni el resume (el progreso ya quedó guardado al minimizar — cerrar del todo no es "Reiniciar", el resume debe sobrevivir para la próxima vez que se abra ese video).

`currentVideoProvider` (ya existente) sigue siendo la fuente de la sesión activa (`displayName` para el título, `playbackPath` para reabrir). El motor de media_kit queda pausado en su posición — no se cierra — así que no se necesita ningún estado adicional de "sesión viva".

## 3. Dónde vive la barra

`app.dart` agrega un `builder:` al `MaterialApp` que envuelve el contenido del Navigator en un `Stack`, con `MiniPlayerBar` anclada al fondo (dentro de un `SafeArea`/respetando el inset inferior del sistema):

```dart
return MaterialApp(
  // ...theme/darkTheme/themeMode/home igual que hoy...
  builder: (context, child) => Stack(
    children: [
      if (child != null) child,
      const Positioned(left: 0, right: 0, bottom: 0, child: MiniPlayerBar()),
    ],
  ),
);
```

Este es el patrón estándar de Flutter para overlays persistentes sobre el Navigator (mismo enfoque que un mini-player de Spotify/YouTube). Cuando el reproductor está a pantalla completa, `playerMinimizedProvider` es `false`, así que `MiniPlayerBar` no dibuja nada (`SizedBox.shrink()`) — no compite visualmente con la ruta activa.

## 4. Preview pequeño (freeze-frame, no video en vivo)

Como sigue pausado, el preview es una **imagen estática** (un frame congelado), no una textura de video en vivo — más simple y coherente con "pausado".

- Se reutiliza el `FrameExtractor` (`kivo/frames`) — el mismo pipeline nativo que ya alimenta el scrub-preview del seek — en vez de depender del `id` de MediaStore (que no todos los `VideoSession` tienen, p.ej. los abiertos por file-picker). Esto cubre TODOS los videos por igual.
- Nuevo provider app-scoped: `final miniPlayerThumbnailProvider = StateProvider<Uint8List?>((ref) => null);`
- En el handler de pop de `PlayerScreen`, **antes** de que `dispose()` llame a `_frames.release()`: se pide un frame en la posición actual (`_frames.frameAt(_lastPosition.inMilliseconds)`) y sus bytes se guardan en `miniPlayerThumbnailProvider`. El extractor ya está "preparado" para este `playbackPath` (se llama `_frames.prepare(...)` en `_start()`), así que la extracción es rápida (mismo camino ya usado para el scrub, que debe responder de forma interactiva).
- `_start()` resetea `miniPlayerThumbnailProvider = null` (junto a `playerMinimizedProvider`) — un preview viejo nunca debe colgar de una sesión nueva.
- `MiniPlayerBar` muestra `Image.memory(bytes)` en un cuadro pequeño (~44x44, esquinas redondeadas) a la izquierda de la barra; si `bytes == null` (falló la extracción o aún no se generó), un ícono genérico de video como placeholder.

## 5. La mini-barra (UI)

- **Contenido:** preview (§4) a la izquierda · título (`displayName`, una línea, ellipsis) · botón play/pause · botón X. Línea delgada de progreso dorado continua en el borde superior de la barra (no segmentada, dado el alto reducido).
- **Estética:** oscura/translúcida (`Colors.black.withValues(alpha: 0.92)` + elevación/sombra sutil), consistente con que el reproductor —incluso en su forma mini— se mantiene con la identidad visual oscura del player, no la del tema de biblioteca.
- **Tap** en la barra (fuera de los botones) → expande: `Navigator.push(MaterialPageRoute(builder: (_) => const PlayerScreen()))`, seguido del mismo `.then` de invalidación (`continueWatchingProvider`, `playedKeysProvider`) que usan `_push`/`_open` hoy.
- **Play/pause** en la barra actúa directo sobre el motor (pausa/reanuda) sin expandir.
- **X** → `playerMinimizedProvider.state = false`.
- **Swipe lateral** → `Dismissible` (widget nativo de Flutter) envolviendo la barra; al completarse el gesto, mismo efecto que X.

## 6. Animaciones

- El gesto de swipe-down **no cambia** — conserva su animación existente de encogido/fade (`_dismissAnim` en `PlayerGestures`); solo se le agrega la puesta de `playerMinimizedProvider = true` antes del pop.
- La mini-barra **aparece** con slide-up + fade (~220ms, `Curves.easeOutCubic`) cuando `playerMinimizedProvider` pasa a `true`, y **desaparece** con la animación inversa al volver a `false` (usar `AnimatedSlide`/`AnimatedOpacity` o un `AnimatedSwitcher` con transición custom sobre el propio `MiniPlayerBar`, ya que hoy no se dibuja nada cuando `minimized == false`).
- Salida por botón del top bar o back del sistema usa la transición de pop estándar de `MaterialPageRoute` (sin animación custom adicional) — unificar las 3 salidas con el mismo encogido del swipe queda fuera de alcance (ver §7).

## 7. Fuera de alcance

- Miniatura/preview en vivo (video real) en la barra — es un freeze-frame estático.
- Continuidad de sesión sin recarga al expandir (reload breve aceptado).
- Animación de encogido unificada para las salidas por botón/back del sistema (hoy solo el swipe-down la tiene).
- Reproducción en segundo plano / notificación de sistema.
- 2c (búsqueda/orden/filtros).

## 8. Archivos (orientativo)

```
lib/ui/player/state/mini_player_state.dart   (nuevo: playerMinimizedProvider, miniPlayerThumbnailProvider)
lib/ui/player/player_screen.dart             (PopScope: captura frame + set minimized antes del pop; _start(): reset ambos providers)
lib/ui/mini_player/mini_player_bar.dart      (nuevo: MiniPlayerBar — UI + tap/play-pause/X/swipe)
lib/app.dart                                 (MaterialApp.builder envuelve el Navigator + MiniPlayerBar)
```

## 9. Testing

- **Puro/widget:** `playerMinimizedProvider` se pone en `true` en el handler de pop y se resetea a `false` en `_start()`; `miniPlayerThumbnailProvider` se resetea a `null` en `_start()`. `MiniPlayerBar` no renderiza nada cuando `minimized == false`; renderiza título/preview/controles cuando `minimized == true` y hay sesión; tap expande (verifica push de `PlayerScreen`); botón X y swipe (`Dismissible`) ponen `minimized = false`; play/pause en la barra alterna el estado de reproducción sin expandir.
- **Device:** minimizar por las 3 vías se siente igual de fluido; el preview coincide aproximadamente con el frame donde se pausó; expandir reanuda cerca de la posición exacta (parpadeo breve aceptable); cerrar por X y por swipe lateral funcionan; la barra es visible al navegar a una carpeta y de vuelta; no interfiere con el pinch/scroll de la biblioteca debajo.
