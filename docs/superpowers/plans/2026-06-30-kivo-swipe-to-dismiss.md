# Swipe-to-Dismiss + Lateral Dead Zones Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add lateral (left/right) dead zones (~38dp, no accidental seek) and an interactive swipe-down-to-dismiss gesture in the top + lateral dead zones that slides the player out and pops it (snaps back under threshold).

**Architecture:** Pure-Dart zone helpers (tested) gate the gesture. `PlayerGestures` routes a downward drag starting in a dead zone to a `dismissProvider` (0→1), driving an `AnimationController` for snap-back/exit on release. `player_screen` renders the dismiss offset (translate + scale + fade) around its content.

**Tech Stack:** Flutter, Riverpod.

## Global Constraints

- Lateral dead-zone margin **38.0 dp**; dismiss top margin reuses the existing `_deadMargin = 24.0` + top inset. Dismiss threshold **0.25** of fraction, or downward fling velocity **> 700 px/s**.
- Dismiss zone = top strip OR lateral strips; the BOTTOM strip is NOT a dismiss zone (controls live there).
- Suppress horizontal seek when a drag starts in a lateral dead zone (the reported bug).
- Center area unchanged: brightness (left) / volume (right) vertical drags, horizontal seek.
- Never `ref.read(...)` in `dispose` (cached services only — known prior bug); dispose the AnimationController.
- `flutter analyze` clean; `flutter test` green (currently 75). Pure helpers unit-tested; gesture + animation verified on the Pixel 6.

---

### Task 1: Pure zone helpers

**Files:**
- Modify: `lib/player/control/gesture_math.dart`
- Test: `test/player/control/gesture_math_test.dart`

**Interfaces:**
- Produces: `bool inLateralDeadZone(double localX, double width, double margin)`; `bool inDismissZone(double localX, double localY, double width, double topInset, double lateralMargin, double topMargin)`.

- [ ] **Step 1: Write failing tests** (append to `gesture_math_test.dart`)

```dart
test('inLateralDeadZone: left/right edge strips, center is live', () {
  expect(inLateralDeadZone(10, 800, 38), isTrue);   // left strip
  expect(inLateralDeadZone(790, 800, 38), isTrue);  // right strip
  expect(inLateralDeadZone(400, 800, 38), isFalse); // center
});

test('inDismissZone: top strip and lateral strips true, center + bottom false', () {
  // width 800, height 400, topInset 24, lateralMargin 38, topMargin 24
  expect(inDismissZone(400, 10, 800, 24, 38, 24), isTrue);  // top strip (y<48)
  expect(inDismissZone(5, 200, 800, 24, 38, 24), isTrue);   // left lateral
  expect(inDismissZone(795, 200, 800, 24, 38, 24), isTrue); // right lateral
  expect(inDismissZone(400, 200, 800, 24, 38, 24), isFalse);// center
  expect(inDismissZone(400, 398, 800, 24, 38, 24), isFalse);// bottom (not a dismiss zone)
});
```

- [ ] **Step 2: Run — verify fail**

Run: `flutter test test/player/control/gesture_math_test.dart`
Expected: FAIL (functions undefined).

- [ ] **Step 3: Implement** (append to `gesture_math.dart`)

```dart
/// True when [localX] is in the left/right edge strips of width [margin].
bool inLateralDeadZone(double localX, double width, double margin) =>
    localX < margin || localX > width - margin;

/// True when a touch is in a swipe-to-dismiss zone: the top strip
/// ([topInset] + [topMargin]) or either lateral strip ([lateralMargin]).
/// The bottom strip is intentionally excluded (controls live there).
bool inDismissZone(double localX, double localY, double width,
        double topInset, double lateralMargin, double topMargin) =>
    localY < topInset + topMargin ||
    inLateralDeadZone(localX, width, lateralMargin);
```

- [ ] **Step 4: Run — verify pass; analyze**

Run: `flutter test test/player/control/gesture_math_test.dart` → PASS. `flutter analyze` → clean.

- [ ] **Step 5: Commit**

```bash
git add lib/player/control/gesture_math.dart test/player/control/gesture_math_test.dart
git commit -m "feat: lateral dead-zone + dismiss-zone gesture helpers"
```

---

### Task 2: Dismiss gesture wiring + render

**Files:**
- Create: `lib/ui/player/state/dismiss_state.dart`
- Modify: `lib/ui/player/gestures/player_gestures.dart`
- Modify: `lib/ui/player/player_screen.dart`

**Interfaces:**
- Consumes: `inLateralDeadZone`, `inDismissZone` (Task 1); existing `_dead`, `_topInset`, `_bottomInset`, `_width`, `_height`.
- Produces: `dismissProvider` (`StateProvider<double>`, 0=normal → 1=dismissed).

- [ ] **Step 1: Create `dismiss_state.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Player dismiss progress: 0 = at rest, 1 = fully swiped off-screen.
/// Driven live by a downward drag in a dead zone; animated on release.
final dismissProvider = StateProvider<double>((ref) => 0.0);
```

- [ ] **Step 2: `player_gestures.dart` — add the dismiss gesture**

Add `with SingleTickerProviderStateMixin` to `_PlayerGesturesState`. Add fields:
```dart
static const double _lateralMargin = 38.0;
bool _dismissing = false;
double _dismissFraction = 0.0;
bool _dismissHaptic = false;
late final AnimationController _dismissAnim = AnimationController(
  vsync: this, duration: const Duration(milliseconds: 220))
  ..addListener(() {
    ref.read(dismissProvider.notifier).state = _dismissAnim.value;
  });
```
Add `@override void dispose() { _dismissAnim.dispose(); super.dispose(); }`.

In `build`, the lateral margin needs `_width` (already captured in LayoutBuilder). Add a helper:
```dart
bool _inDismiss(double dx, double dy) =>
    inDismissZone(dx, dy, _width, _topInset, _lateralMargin, _deadMargin);
```

In `_onVerticalStart` — route dismiss-zone drags to dismiss (before the existing brightness/volume logic). Replace the body so it reads:
```dart
void _onVerticalStart(DragStartDetails d) {
  _vDead = _dead(d.localPosition.dy);
  // A downward drag starting in the top/lateral dead zones dismisses the player.
  if (_inDismiss(d.localPosition.dx, d.localPosition.dy)) {
    _dismissing = true;
    _dismissFraction = 0.0;
    _dismissHaptic = false;
    _dismissAnim.stop();
    return;
  }
  if (_vDead) return;
  if (_holding) return;
  _leftSide = d.localPosition.dx < _width / 2;
  _volPct = ref.read(volumePercentProvider);
  _volCap = _volPct < 100
      ? 100.0
      : ref.read(settingsProvider).volumeBoostMax.toDouble();
  ref.read(deviceControlsProvider).currentBrightness().then((b) => _brightness = b);
}
```

In `_onVerticalUpdate` — handle dismiss first:
```dart
void _onVerticalUpdate(DragUpdateDetails d) {
  if (_dismissing) {
    _dismissFraction =
        (_dismissFraction + d.delta.dy / (_height * 0.5)).clamp(0.0, 1.0);
    ref.read(dismissProvider.notifier).state = _dismissFraction;
    if (!_dismissHaptic && _dismissFraction >= 0.25) {
      _dismissHaptic = true;
      _haptic();
    }
    return;
  }
  if (_vDead) return;
  if (_holding) return;
  // ... existing brightness/volume body unchanged ...
}
```
(Keep the existing brightness/volume code after these guards.)

Add `_onVerticalEnd` and wire it:
```dart
void _onVerticalEnd(DragEndDetails d) {
  if (!_dismissing) return;
  _dismissing = false;
  final fling = (d.primaryVelocity ?? 0) > 700;
  final exit = _dismissFraction >= 0.25 || fling;
  _dismissAnim.value = _dismissFraction;
  if (exit) {
    _dismissAnim.animateTo(1.0, curve: Curves.easeIn).whenComplete(() {
      if (mounted) Navigator.of(context).maybePop();
    });
  } else {
    _dismissAnim.animateBack(0.0, curve: Curves.easeOut);
  }
}
```
In the `GestureDetector` (the unlocked branch), add `onVerticalDragEnd: _onVerticalEnd,` alongside the existing vertical handlers.

Suppress seek in lateral zones — in `_onHorizontalStart`, change `_hDead = _dead(d.localPosition.dy);` to:
```dart
_hDead = _dead(d.localPosition.dy) ||
    inLateralDeadZone(d.localPosition.dx, _width, _lateralMargin);
```
(`_onHorizontalUpdate` already bails on `_hDead`.)

Add imports if missing: `import 'package:flutter/material.dart';` already present; `import '../state/dismiss_state.dart';`. `gesture_math.dart` already imported.

- [ ] **Step 3: `player_screen.dart` — render the dismiss transform**

Import `import 'state/dismiss_state.dart';`. Wrap the body `Stack` in a `Consumer` so only the wrapper rebuilds on dismiss changes. Replace `body: Stack(children: [...])` with:
```dart
body: Consumer(
  builder: (context, ref, child) {
    final d = ref.watch(dismissProvider);
    final h = MediaQuery.of(context).size.height;
    return Transform.translate(
      offset: Offset(0, d * h),
      child: Transform.scale(
        scale: 1 - d * 0.06,
        child: Opacity(opacity: (1 - d * 0.4).clamp(0.0, 1.0), child: child),
      ),
    );
  },
  child: Stack(
    children: [ /* existing Positioned.fill children unchanged */ ],
  ),
),
```

- [ ] **Step 4: Analyze + test + commit**

`flutter analyze` clean; `flutter test` green (the gesture/animation isn't unit-tested — verified on device; ensure no existing test broke). Commit:
```bash
git add lib/ui/player/state/dismiss_state.dart lib/ui/player/gestures/player_gestures.dart lib/ui/player/player_screen.dart
git commit -m "feat: interactive swipe-down-to-dismiss in top/lateral dead zones; suppress lateral seek"
```

---

## After all tasks

1. `flutter test` green, `flutter analyze` clean.
2. Whole-branch review.
3. Release build to the Pixel 6: verify swiping down from the top or a side edge drags the player down (follows finger) and dismisses past threshold / snaps back under it; side edges no longer trigger seek; brightness/volume/seek intact in the center.
