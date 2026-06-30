# Player Pain-Point Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Fix three on-device pain points: (1) controls auto-hide while the user is still interacting — the timer must reset on every control touch; (2) the hold-right speed gesture maps the full viewport height, so reaching 4x in portrait requires a huge swipe — make it finger-anchored and viewport-independent; (3) playback keeps running after leaving the player (and on backgrounding), which also blocks testing resume — pause on exit and on background.

**Architecture:** Pure Flutter/Riverpod. Pure helpers (tested) for the anchored-speed math; thin UI/lifecycle wiring. No new packages. The `MediaKitEngine` is a process-lifetime singleton with `pause()`; background playback is a later hito, so leaving the player must pause.

**Tech Stack:** Flutter, Riverpod, media_kit.

## Global Constraints

- No regression to existing gesture mapping, the segmented speed meter, resume SAVE, or controls show/hide semantics.
- Speed detents come from `settings.holdRightDetents` (default `[1.0,1.25,1.5,2.0,3.0,4.0]`). Anchored math must be viewport-height independent.
- `flutter analyze` clean; `flutter test` green (currently 66/66). Pure helpers get unit tests; update the existing `speed_ladder_test.dart` to the new signature.

---

### Task 1: Pause playback on exit and on background

**Files:** Modify `lib/ui/player/player_screen.dart`

**Interfaces:** Consumes `playbackEngineProvider` (`PlaybackEngine.pause()`).

The engine is an app singleton; today `dispose` saves progress but never pauses, so audio keeps playing after the player is popped, and backgrounding doesn't pause either. Pause on both.

- [ ] **Step 1: Cache the engine** alongside `_deviceControls`. In the class fields add `late final PlaybackEngine _engine;` and in `initState` (where `_deviceControls = ref.read(deviceControlsProvider);` is set) add `_engine = ref.read(playbackEngineProvider);`. Add the import `import '../../player/engine/playback_engine.dart';` if not present (the provider is in `playback_provider.dart`, already imported).

- [ ] **Step 2: Pause on background.** In `didChangeAppLifecycleState`, when `state == AppLifecycleState.paused`, pause (keep the existing `_saveProgress()` for paused/inactive):
```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
    _saveProgress();
  }
  if (state == AppLifecycleState.paused) {
    _engine.pause(); // no background playback in Hito 1
  }
}
```
(Pause only on `paused`, NOT `inactive` — `inactive` fires transiently, e.g. on the notification shade, and we don't want to pause then.)

- [ ] **Step 3: Pause on exit.** In `dispose`, pause the engine (it's reused by the next open, which calls `engine.open(..., play: true)`):
```dart
@override
void dispose() {
  WidgetsBinding.instance.removeObserver(this);
  _saveProgress(); // best-effort for in-app pop
  _engine.pause(); // stop audio when leaving the player (engine is a singleton)
  _deviceControls.setOrientation([DeviceOrientationLock.auto]);
  _deviceControls.keepAwake(false);
  _deviceControls.setImmersive(false);
  super.dispose();
}
```

- [ ] **Step 4: Analyze + test + commit** — `fix: pause playback on player exit and on background`

---

### Task 2: Controls auto-hide resets on every interaction

**Files:** Modify `lib/ui/player/controls/controls_overlay.dart`

**Interfaces:** Consumes `controlsVisibleProvider.notifier.show()` (already restarts the auto-hide timer).

Today the auto-hide timer only restarts on specific actions; touching buttons doesn't keep the controls alive, so they vanish mid-interaction. Wrap the visible controls in a `Listener` that calls `show()` on pointer down/move — this restarts the timer on any control interaction. It must NOT swallow events (buttons still work) and must NOT fire for taps in the empty middle (those reach `PlayerGestures` to toggle/hide).

- [ ] **Step 1:** In the unlocked branch, wrap the existing `IgnorePointer(ignoring: !visible, child: Stack(...))` (the top/center/bottom controls — NOT the scrim) in a `Listener`:
```dart
Listener(
  behavior: HitTestBehavior.deferToChild,
  onPointerDown: (_) => ref.read(controlsVisibleProvider.notifier).show(),
  onPointerMove: (_) => ref.read(controlsVisibleProvider.notifier).show(),
  child: IgnorePointer(
    ignoring: !visible,
    child: Stack(children: [ /* TopBar, CenterControls, BottomBar — unchanged */ ]),
  ),
),
```
Rationale: `deferToChild` means the `Listener` only registers a hit (and fires) when one of its children — the actual control widgets — is hit. Touching a button restarts the timer AND the button still receives the tap (Listener doesn't consume). Touching the empty middle hits no child here, so the event falls through to `PlayerGestures` below (toggle/hide) as before. The full-screen scrim `Positioned.fill` stays OUTSIDE this `Listener` (it's a separate always-ignoring layer).

NOTE: `show()` sets `state = true` (a no-op rebuild when already visible — Riverpod won't notify on an unchanged bool) and restarts the timer, so this won't cause spurious rebuilds while interacting.

- [ ] **Step 2: Analyze + test + commit** — `fix: reset controls auto-hide timer on any control interaction`

---

### Task 3: Finger-anchored hold-right speed (viewport-independent)

**Files:**
- Modify: `lib/player/control/gesture_math.dart` (add `anchoredDetentIndex`, `defaultHoldRightIndex`)
- Modify: `lib/ui/player/speed/speed_ladder_overlay.dart` (`holdRightSpeedFor` new signature)
- Modify: `lib/ui/player/gestures/player_gestures.dart` (track anchor + base index; use new signature)
- Test: `test/player/control/gesture_math_test.dart` (new helpers)
- Test: `test/ui/player/speed_ladder_test.dart` (new `holdRightSpeedFor` signature)

**Interfaces:**
- Produces: `int anchoredDetentIndex(double startY, double currentY, double stepPx, int count, int baseIndex)`; `int defaultHoldRightIndex(List<double> detents)`; `double holdRightSpeedFor(double startY, double currentY, double stepPx, List<double> detents, int baseIndex)` (signature changed from `(localY, height, detents)`).
- Consumes: `settings.holdRightDetents`.

Today `holdRightSpeedFor` maps the full viewport height to the detent range, so portrait (tall) requires a long swipe to reach 4x. New model (matches spec §7 "escalera anclada al dedo"): on press, anchor at the touch Y and start at a sensible base detent (nearest 2.0x); each `stepPx` (48 logical px) of vertical travel moves one detent (up = faster). Viewport-height independent.

- [ ] **Step 1: Pure helpers in `gesture_math.dart`**

```dart
/// Detent index for a finger-anchored hold-right drag: starts at [baseIndex]
/// and moves one detent per [stepPx] of vertical travel (up = faster).
/// Independent of viewport height.
int anchoredDetentIndex(
    double startY, double currentY, double stepPx, int count, int baseIndex) {
  if (count <= 0) return 0;
  final steps = stepPx <= 0 ? 0 : ((startY - currentY) / stepPx).round();
  return (baseIndex + steps).clamp(0, count - 1);
}

/// Starting detent for a hold-right press: the one nearest 2.0x (an instant,
/// familiar speed-up), so reaching the extremes is a short slide either way.
int defaultHoldRightIndex(List<double> detents) {
  if (detents.isEmpty) return 0;
  var best = 0;
  for (var i = 1; i < detents.length; i++) {
    if ((detents[i] - 2.0).abs() < (detents[best] - 2.0).abs()) best = i;
  }
  return best;
}
```

- [ ] **Step 2: Tests in `gesture_math_test.dart`**

```dart
test('defaultHoldRightIndex picks the detent nearest 2.0x', () {
  expect(defaultHoldRightIndex(const [1.0, 1.25, 1.5, 2.0, 3.0, 4.0]), 3);
  expect(defaultHoldRightIndex(const []), 0);
});
test('anchoredDetentIndex: up = faster, clamped, viewport-independent', () {
  expect(anchoredDetentIndex(300, 300, 48, 6, 3), 3);      // no move = base
  expect(anchoredDetentIndex(300, 300 - 96, 48, 6, 3), 5); // up 2 steps
  expect(anchoredDetentIndex(300, 300 + 144, 48, 6, 3), 0);// down 3 steps, clamped
  expect(anchoredDetentIndex(300, 0, 48, 6, 3), 5);        // clamp high
});
```

- [ ] **Step 3: `holdRightSpeedFor` in `speed_ladder_overlay.dart`** — change signature + body:
```dart
double holdRightSpeedFor(
        double startY, double currentY, double stepPx, List<double> detents, int baseIndex) =>
    detents.isEmpty
        ? 1.0
        : detents[anchoredDetentIndex(startY, currentY, stepPx, detents.length, baseIndex)];
```
(The overlay's meter rendering is unchanged — it still finds the current detent via `indexWhere`.)

- [ ] **Step 4: Update `speed_ladder_test.dart`** to the new signature:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/control/gesture_math.dart';
import 'package:kivo_player/ui/player/speed/speed_ladder_overlay.dart';

void main() {
  test('holdRightSpeedFor: finger-anchored, base ~2x, up = faster', () {
    const d = [1.0, 1.25, 1.5, 2.0, 3.0, 4.0];
    final base = defaultHoldRightIndex(d); // 3 -> 2.0x
    expect(holdRightSpeedFor(300, 300, 48, d, base), 2.0);       // no move
    expect(holdRightSpeedFor(300, 300 - 96, 48, d, base), 4.0);  // up 2 steps
    expect(holdRightSpeedFor(300, 300 + 144, 48, d, base), 1.0); // down 3 steps
  });
}
```

- [ ] **Step 5: Wire `player_gestures.dart`** — add fields `double _holdStartY = 0; int _holdBaseIndex = 0; static const double _holdStepPx = 48.0;`. In `_onLongPressStart`, the RIGHT (`else`) branch:
```dart
} else {
  _holdStartY = d.localPosition.dy;
  _holdBaseIndex = defaultHoldRightIndex(st.holdRightDetents);
  final v = holdRightSpeedFor(_holdStartY, d.localPosition.dy, _holdStepPx, st.holdRightDetents, _holdBaseIndex);
  ctrl.setRate(v);
  ref.read(holdSpeedProvider.notifier).state = v;
  ref.read(holdSpeedIsLadderProvider.notifier).state = true;
  _lastHoldSpeed = v;
}
```
In `_onLongPressMove`:
```dart
void _onLongPressMove(LongPressMoveUpdateDetails d) {
  if (_holdLeft) return;
  final st = ref.read(settingsProvider);
  final v = holdRightSpeedFor(_holdStartY, d.localPosition.dy, _holdStepPx, st.holdRightDetents, _holdBaseIndex);
  ref.read(playerControllerProvider).setRate(v);
  ref.read(holdSpeedProvider.notifier).state = v;
  if (v != _lastHoldSpeed) { _haptic(); _lastHoldSpeed = v; }
}
```
Add `import '../../../player/control/gesture_math.dart';` if `defaultHoldRightIndex` isn't already resolved there (gesture_math is already imported for other helpers — verify). Keep the dead-zone guard, `_holding`, the left branch, and `_onLongPressEnd` (with its `if (!_holding) return;`) unchanged.

- [ ] **Step 6: Analyze + test + commit** — `feat: finger-anchored hold-right speed (viewport-independent, base 2x)`

---

## After all tasks

1. `flutter test` green, `flutter analyze` clean.
2. Whole-branch review.
3. Release build to the Pixel 6 to verify: controls stay while you poke them; hold-right reaches 4x with a short slide in portrait; leaving the player (back) and backgrounding both stop the audio; re-opening the same file now shows the "Reanudado desde M:SS · Reiniciar" toast.
