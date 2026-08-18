# Kivo player zoom & configurable minimize playback — Design

**Date:** 2026-08-18
**Status:** Approved for implementation

## Goal

Two player features:

1. **Pinch-to-zoom inside the player** — pinch to scale the video, drag to pan
   around it while zoomed, a persistent chip showing the current factor, and a
   tap on that chip to restore 1×. Maximum factor and auto-reset behaviour are
   user-configurable.
2. **Configurable minimize playback** — minimizing the player currently pauses,
   unconditionally. Make it a setting: pause (today's behaviour, still the
   default) or keep playing in the mini-bar.

## Why now

Both are gaps a user hits with normal content. Wide-aspect video letterboxed on
a 20:9 phone wastes a third of the screen, and `AspectMode.fill`/`stretch` are
all-or-nothing crops with no way to choose *what* gets cropped — panning is the
missing half of that control. And the unconditional pause on minimize makes the
mini-bar half-useless: its own play button can resume playback, so "playing
while minimized" is already a supported engine state — the player just refuses
to hand it over.

## Non-goals

- Disabling mpv's video decode while minimized-and-playing. It would save
  battery (the mini-bar shows a frozen frame, not live video), but it crosses
  `BackgroundPlaybackCoordinator`'s `setVideoTrackEnabled` logic and the surface
  ANR that cost a whole plan to fix. Noted as a later optimization.
- Zoom in PiP or in the mini-bar. Zoom is a fullscreen-player concern.
- Double-tap-to-zoom. The pinch is the gesture; a second zoom affordance would
  collide with the existing double-tap skip zones.

## 1. The gesture constraint that shapes everything

`GestureDetector` **throws** when scale callbacks are registered alongside both
vertical and horizontal drag callbacks:

> Having both a vertical drag gesture recognizer and a scale gesture recognizer
> will result in the vertical drag gesture winning.

`PlayerGestures` registers both drag axes today, so pinch cannot be *added* — the
drag handling has to move under a single scale recognizer.

Two alternatives were considered and rejected:

- **A separate `RawGestureDetector` zoom layer over the existing detector.**
  Looks surgical, but drag recognizers claim the arena as soon as the first
  pointer passes touch slop — before a second finger lands. The pinch would fail
  intermittently.
- **`InteractiveViewer` around the video.** `PlayerGestures` is an opaque layer
  *above* the video box, so the viewer would never receive a touch. Fixing that
  means restructuring the stack, which lands back at the chosen approach plus an
  extra widget.

**Chosen:** one scale recognizer in `PlayerGestures` that dispatches to the
existing per-gesture logic. All the math in `player/control/gesture_math.dart`
survives unchanged; only how deltas arrive changes.

## 2. Zoom state

New `lib/ui/player/state/zoom_state.dart`:

```dart
class ZoomState {
  final double scale;   // 1.0 = no zoom
  final Offset offset;  // logical px translation, always pre-clamped
  const ZoomState({this.scale = 1.0, this.offset = Offset.zero});
  bool get active => scale > 1.001;
}

class ZoomNotifier extends Notifier<ZoomState> {
  void pinch({required double factor, required Offset focal, required Size viewport});
  void panBy(Offset delta, Size viewport);
  void reset();          // explicit user action (the chip) — always resets
  void onVideoChanged(); // resets only when zoomResetMode == 'video'
}

final zoomProvider = NotifierProvider<ZoomNotifier, ZoomState>(ZoomNotifier.new);
```

`build()` seeds `scale` from `settings.zoomRemembered` when
`zoomResetMode == 'never'`, otherwise `1.0`. `offset` always starts at
`Offset.zero` — a remembered framing means nothing in a different file.

Every mutation writes through the pure math below, so an out-of-bounds
`ZoomState` cannot exist.

## 3. Zoom math

New `lib/player/control/zoom_math.dart` (pure, no Flutter widgets — mirrors
`gesture_math.dart`, tested the same way):

```dart
/// Translation cannot exceed half the overflow, or an edge would show empty.
Offset clampZoomOffset(Offset offset, double scale, Size viewport);

/// Focal-anchored zoom: the point under the fingers stays under the fingers.
({double scale, Offset offset}) zoomAt({
  required double scale,
  required Offset offset,
  required double factor,
  required Offset focal,
  required Size viewport,
  required double max,
});
```

`clampZoomOffset` bounds each axis to `±(scale - 1) / 2 × side`, and returns
`Offset.zero` whenever `scale <= 1`.

`zoomAt` computes `newScale = (scale * factor).clamp(1.0, max)` and
`newOffset = focal - (focal - offset) * (newScale / scale)` measured from the
viewport centre, then clamps.

**Deliberate consequence:** bounds are measured against the *viewport*, not the
letterboxed video rect. With `AspectMode.fit`, zooming and panning therefore
lets the user crop black bars away — which is the main reason to want this.

## 4. Applying the transform

Inside `videoBox` in `player_screen.dart`:

```dart
ClipRect(
  child: Consumer(builder: (context, ref, _) {
    final z = ref.watch(zoomProvider);
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..translate(z.offset.dx, z.offset.dy)..scale(z.scale),
      child: <existing video Stack>,
    );
  }),
)
```

`ClipRect` keeps the scaled frame from painting over the control overlays. The
`Consumer` is **local** on purpose: watching `zoomProvider` in the outer builder
would rebuild all ten overlay layers on every frame of a pinch.

`Transform` with `alignment: center` scales about the centre and then translates,
which is exactly the model `zoom_math` assumes.

## 5. Gesture routing

`PlayerGestures` keeps `onTap`, `onDoubleTapDown`, `onDoubleTap` and the three
`onLongPress*` handlers as they are. The six drag handlers become
`onScaleStart` / `onScaleUpdate` / `onScaleEnd` driving one intent:

```dart
enum DragIntent { none, undecided, zoom, pan, brightness, volume, seek, dismiss, rotate }
```

Routing, as a pure function in `gesture_math.dart` so every row below is a test
case:

| Condition (evaluated at the START position) | Intent |
|---|---|
| `pointerCount >= 2` and `settings.pinchZoom` | `zoom` |
| 1 pointer, `zoom.active` | `pan` |
| 1 pointer, no zoom, in the 38 px lateral strip | `dismiss` |
| 1 pointer, no zoom, in the vertical dead strips | `none` |
| 1 pointer, no zoom, centre band and controls hidden | `rotate` |
| 1 pointer, no zoom, `abs(dy) > abs(dx)` past slop | `brightness` (left half) / `volume` (right half) |
| 1 pointer, no zoom, `abs(dx) >= abs(dy)` past slop | `seek` |

Behaviour preserved explicitly:

- **Dead zones** are evaluated against `ScaleStartDetails.localFocalPoint`, not
  the moving focal point — same as the old `DragStartDetails.localPosition`.
- **The dismiss fling** reads `ScaleEndDetails.velocity.pixelsPerSecond.dy`
  instead of `primaryVelocity`, against the same 700 px/s threshold in
  `dismissCommit`.
- **`volumeGestureActiveProvider`** is cleared on every exit path from
  `onScaleEnd`, exactly as `_onVerticalEnd` does today.
- **Axis disambiguation** waits for a slop of 12 logical px before committing to
  an intent, so a small jitter can no longer pick the wrong gesture.
- **A second finger landing mid-drag** cancels the in-flight intent cleanly (an
  in-progress dismiss animates back to 0 via `api.cancel()`) and switches to
  `zoom`.
- **In `zoom` intent**, `d.focalPointDelta` is applied as pan as well, so a
  two-finger drag reframes without lifting.
- **While zoomed**, single-finger drags are pan only — brightness, volume, seek,
  minimize and rotate are suspended until 1×. Minimizing still works via the
  top-bar arrow and the system back button; the chip restores 1×.
- **`pinchZoom == false`** never produces a `zoom` intent, but does not clear an
  existing zoom — the chip stays available so the user can get out.

Deciding the axis in our own code rather than leaning on the gesture arena is
what makes it testable; it is also the only real behavioural risk in the change,
which is why the routing table is exhaustively covered.

## 6. The chip

New `lib/ui/player/zoom/zoom_chip.dart`, in the visual language of
`ab_loop_chip.dart`: `black` at 55% alpha, accent border, 11 px `w800` label with
`FontFeature.tabularFigures()` so the digits do not jitter between `1.9×` and
`2.0×`. Content: a `center_focus_strong` icon, the factor, and a faint `✕`.

- Rendered whenever `zoomProvider.active`, from its **own** `Positioned.fill` in
  the `player_screen` stack — not inside `ControlsOverlay`, because it must stay
  visible while the controls are hidden.
- `left: 14, bottom: 116`, mirroring `AbLoopChip` on the right, so with the
  controls up it sits clear of the seek bar and button row.
- Tap → `reset()` plus a light haptic, gated on `settings.hapticsOnGestures`.
- 160 ms fade + scale on enter/exit, matching the app's other micro-animations.

## 7. Settings

Five new `KivoSettings` fields (four with UI), each with `copyWith`, `toMap` and
a `fromMap` default so an existing settings map keeps working:

| Field | Default | UI |
|---|---|---|
| `pinchZoom: bool` | `true` | "Reproducción y gestos" → new **Zoom** card: switch "Zoom con pinch" |
| `zoomMax: double` | `4.0` | same card: `SettingSegmented` 2× / 4× / 6× / 8× |
| `zoomResetMode: String` | `'exit'` | same card: `SettingSegmented` "Al salir" / "Cada video" / "Nunca" |
| `zoomRemembered: double` | `1.0` | none — written only in `'never'` mode |
| `minimizeKeepsPlaying: bool` | `false` | "Reproducción avanzada" → "Reproducción" group, beside autoplay and PiP: "Seguir reproduciendo al minimizar" |

Reset semantics:

- `'exit'` (default) — zoom survives rotation, minimize/expand and queue
  advances; it drops when the player is left.
- `'video'` — additionally drops on every video change (autoplay, queue jump,
  next/previous), via `ZoomNotifier.onVideoChanged()`.
- `'never'` — the factor persists to disk and is re-applied on the next player
  entry; the offset is re-centred.

Who resets, precisely — the chip's `reset()` is unconditional, and it is the only
thing that clears zoom in `'never'` mode. Player exit clears it in `'exit'` and
`'video'` mode only. In `'never'` mode the factor is written to
`settings.zoomRemembered` when a pinch settles (on `onScaleEnd`, not on every
frame of the gesture — one disk write per pinch, not sixty), and `reset()` writes
`1.0` back.

## 8. Minimize without pausing

The pause lives in three places today, all reached through
`PlayerDismissApi.complete()`: `_completeDismiss()`, the `PopScope` fallback, and
`dispose()`. The setting therefore governs all three exits (swipe, top-bar
arrow, system back) — one decision point, no divergent behaviour.

`_completeDismiss()` reads the setting **once** and stores it in a
`_keepPlayingOnMinimize` field. `dispose()` consults that field, never `ref` —
reading a provider in `dispose()` throws and silently drops the work, which is
the exact bug that once broke resume-on-exit. The `PopScope` fallback makes the
same read on its own path.

One consequence must be handled, and does not exist today: closing the mini-bar
(the `✕` or a horizontal dismiss) assumed playback was already paused. Both
routes in `mini_player_bar.dart` must now **pause the engine** before clearing
`playerMinimizedProvider`.

Progress saving is unchanged: `_saveProgress()` still runs on minimize, and the
mini-bar's own 4-second timer already persists position while playing.

## 9. Testing

- `test/player/control/zoom_math_test.dart` — clamping at all four edges,
  focal anchoring, the `zoomMax` ceiling, and `scale == 1` forcing
  `offset == Offset.zero`.
- `test/player/control/gesture_math_test.dart` — one case per routing-table row,
  plus "second finger lands mid-dismiss".
- `test/core/settings/` — round-trip of the five fields, and defaults from a map
  written before they existed.
- Chip widget test — hidden at 1×, shows the factor above it, tap restores.
- Minimize widget test — with the setting on the engine receives no `pause()`;
  with it off it does.

`flutter analyze` clean and the full suite green before every commit. One
release build to the Pixel 6 when the module closes.
