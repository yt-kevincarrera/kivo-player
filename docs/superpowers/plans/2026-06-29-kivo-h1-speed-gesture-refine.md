# Speed Gesture Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** On-device feedback refinements for the speed controls: (1) make the hold-right speed gesture use explicit, sensible detents `[1, 1.25, 1.5, 2, 3, 4]`, show its segmented meter on the OPPOSITE (left) edge like volume, and suppress the elaborate selector for the fixed-speed hold-LEFT (just a small badge); (2) polish the bottom-sheet speed panel so its preset chips are centered and on-style.

**Architecture:** Pure Flutter/Riverpod UI + one new configurable setting (`holdRightDetents`) + one new pure helper (`detentSpeed`). No engine/platform/package changes. (A separate one-line fix removing media_kit's stray buffering spinner already landed in commit `f4a03b4`.)

**Tech Stack:** Flutter, Riverpod, flutter_svg (`KivoIcon`).

## Global Constraints

- Hold-right detents default `[1.0, 1.25, 1.5, 2.0, 3.0, 4.0]`, stored as a new configurable setting `holdRightDetents` (the project rule is "everything configurable").
- Segment convention (matches HUD): lit = accent (`Color(st.accentColor)`); unlit = `Colors.white.withValues(alpha: 0.18)`; rounded `2.5`. Capsule tone `Colors.black.withValues(alpha: 0.5)`.
- Speed values shown to the user must strip trailing zeros: `1`, `1.25`, `1.5`, `2`, `3`, `4` (NOT `1.00x`).
- No regression to speed math, gesture wiring, `rememberSpeed`, `holdRightReleaseToNormal`, or the panel's slider/fine-step behavior.
- `flutter analyze` clean; `flutter test` green (currently 59/59). Settings serialization must round-trip the new field.

---

### Task 1: Hold-right detents + meter on opposite side + hold-left badge

**Files:**
- Modify: `lib/core/settings/kivo_settings.dart` (add `holdRightDetents`)
- Modify: `lib/player/control/gesture_math.dart` (add `detentSpeed`)
- Modify: `lib/ui/player/speed/speed_ladder_overlay.dart` (detent meter, left edge, hold-left badge)
- Modify: `lib/ui/player/gestures/player_gestures.dart` (use detents, set ladder flag)
- Test: `test/player/control/gesture_math_test.dart` (add `detentSpeed` test)
- Test: `test/ui/player/speed_ladder_test.dart` (update `holdRightSpeedFor` to new signature)

**Interfaces:**
- Produces: `KivoSettings.holdRightDetents` (`List<double>`); `detentSpeed(double fraction, List<double> detents) -> double`; `holdSpeedIsLadderProvider` (`StateProvider<bool>`); `holdRightSpeedFor(double localY, double height, List<double> detents) -> double` (signature changed — was `(localY, height, min, max)`).
- Consumes: `holdSpeedProvider` (unchanged: `StateProvider<double?>`), `settingsProvider`.

- [ ] **Step 1: Add `holdRightDetents` setting** (`kivo_settings.dart`)

Add the field next to `holdRightMax` (after line 13): `final List<double> holdRightDetents;`. Add `required this.holdRightDetents,` to the constructor (near `holdRightMax`). Add to `defaults()` (after `holdRightMax: 4.0,`): `holdRightDetents: const [1.0, 1.25, 1.5, 2.0, 3.0, 4.0],`. Add to `copyWith` params `List<double>? holdRightDetents,` and body `holdRightDetents: holdRightDetents ?? this.holdRightDetents,`. Add to `toMap`: `'holdRightDetents': holdRightDetents,`. Add to `fromMap` (mirror the `speedPresets` line): `holdRightDetents: (m['holdRightDetents'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? d.holdRightDetents,`.

- [ ] **Step 2: Add `detentSpeed` to `gesture_math.dart`** (keep `ladderSpeed` as-is — it's still unit-tested)

```dart
/// Maps a 0..1 fraction to the nearest detent in [detents] (index = round(f*(n-1))).
double detentSpeed(double fraction, List<double> detents) {
  if (detents.isEmpty) return 1.0;
  final f = fraction.clamp(0.0, 1.0);
  final index = (f * (detents.length - 1)).round();
  return detents[index];
}
```

- [ ] **Step 3: Add `detentSpeed` test** (`gesture_math_test.dart`)

```dart
test('detentSpeed snaps fraction to explicit detents', () {
  const d = [1.0, 1.25, 1.5, 2.0, 3.0, 4.0];
  expect(detentSpeed(0.0, d), 1.0);   // bottom -> first
  expect(detentSpeed(1.0, d), 4.0);   // top -> last
  expect(detentSpeed(0.5, d), 1.5);   // round(0.5*5)=3 -> index 3 = 2.0? -> verify below
});
```
NOTE to implementer: compute the expected middle value precisely — `round(0.5*5)=round(2.5)=3` (Dart rounds half away from zero → 3), so `detents[3] = 2.0`. Fix the third expectation to `expect(detentSpeed(0.5, d), 2.0);` and drop the stray comment. Add an empty-list guard assertion: `expect(detentSpeed(0.5, const []), 1.0);`.

- [ ] **Step 4: Rewrite `speed_ladder_overlay.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/icons/kivo_icons.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../player/control/gesture_math.dart';

final holdSpeedProvider = StateProvider<double?>((ref) => null);
// true while a hold-RIGHT (variable speed) is active → show the detent meter;
// false for hold-LEFT (fixed speed) → show only a compact badge.
final holdSpeedIsLadderProvider = StateProvider<bool>((ref) => false);

double holdRightSpeedFor(double localY, double height, List<double> detents) =>
    detentSpeed(height <= 0 ? 0 : (1 - (localY / height)).clamp(0.0, 1.0), detents);

String _fmtSpeed(double v) =>
    v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

class SpeedLadderOverlay extends ConsumerWidget {
  const SpeedLadderOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speed = ref.watch(holdSpeedProvider);
    if (speed == null) return const SizedBox.shrink();
    final isLadder = ref.watch(holdSpeedIsLadderProvider);
    final st = ref.watch(settingsProvider);
    final accent = Color(st.accentColor);

    // Hold-LEFT (fixed speed): a compact centered badge, no selector.
    if (!isLadder) {
      return IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              KivoIcon(KivoIcons.speed, size: 22, color: Colors.white),
              const SizedBox(width: 8),
              Text('${_fmtSpeed(speed)}x',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
            ]),
          ),
        ),
      );
    }

    // Hold-RIGHT (variable): detent meter on the LEFT edge + big centered readout.
    final detents = st.holdRightDetents;
    final idx = detents.indexWhere((d) => (d - speed).abs() < 1e-6);
    final lit = idx < 0 ? 0 : idx + 1;

    Widget seg(bool on) => Container(
          width: 22,
          height: 8,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: on ? accent : Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(2.5),
          ),
        );

    final capsule = Container(
      width: 58,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        KivoIcon(KivoIcons.speed, size: 26, color: Colors.white),
        const SizedBox(height: 12),
        for (var i = detents.length - 1; i >= 0; i--) seg(i < lit),
      ]),
    );

    return IgnorePointer(
      child: Stack(children: [
        Align(
          alignment: Alignment.center,
          child: Text('${_fmtSpeed(speed)}x',
              style: TextStyle(color: accent, fontSize: 48, fontWeight: FontWeight.bold)),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(padding: const EdgeInsets.only(left: 20), child: capsule),
        ),
      ]),
    );
  }
}
```

- [ ] **Step 5: Update `speed_ladder_test.dart`** to the new signature

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/ui/player/speed/speed_ladder_overlay.dart';

void main() {
  test('holdRightSpeedFor: top of screen = last detent, bottom = first', () {
    const d = [1.0, 1.25, 1.5, 2.0, 3.0, 4.0];
    expect(holdRightSpeedFor(0, 400, d), 4.0);    // y=0 -> fraction 1 -> last
    expect(holdRightSpeedFor(400, 400, d), 1.0);  // y=height -> fraction 0 -> first
  });
}
```
(Match the existing import path/style in the current test file; only the call signature and expectations change.)

- [ ] **Step 6: Wire `player_gestures.dart`**

In `_onLongPressStart`: in the `_holdLeft` branch, after setting rate/holdSpeedProvider, add `ref.read(holdSpeedIsLadderProvider.notifier).state = false;`. In the `else` (right) branch, change `holdRightSpeedFor(d.localPosition.dy, _height, st.holdRightMin, st.holdRightMax)` → `holdRightSpeedFor(d.localPosition.dy, _height, st.holdRightDetents)` and add `ref.read(holdSpeedIsLadderProvider.notifier).state = true;`.

In `_onLongPressMove`: change the `holdRightSpeedFor(...)` call to `holdRightSpeedFor(d.localPosition.dy, _height, st.holdRightDetents)`.

In `_onLongPressEnd`: after `ref.read(holdSpeedProvider.notifier).state = null;` add `ref.read(holdSpeedIsLadderProvider.notifier).state = false;`.

- [ ] **Step 7: Analyze + test + commit**

`flutter analyze` clean; `flutter test` green (the two updated tests + all others). Commit: `feat: explicit speed detents [1,1.25,1.5,2,3,4]; meter on opposite edge; compact hold-left badge`.

---

### Task 2: Polish the bottom-sheet speed panel

**Files:**
- Modify: `lib/ui/player/speed/speed_panel.dart`

**Interfaces:** Consumes `rateProvider`, `settingsProvider`, `playerControllerProvider`, `KivoColors`. Produces nothing new. The preset chips MUST remain tappable by their `'${p}x'` label (a widget test taps the `2.0x` chip).

Center the preset chips and tighten the panel so it reads as one cohesive, on-style sheet. Keep all behavior (slider, +/-, fine-step, snap, reset).

- [ ] **Step 1: Add a grab handle + center the chips**

In `SpeedPanel.build`, in the `Column` (currently `crossAxisAlignment: CrossAxisAlignment.stretch`):
1. Insert as the FIRST child a centered grab handle:
```dart
Center(
  child: Container(
    width: 40, height: 4,
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(2),
    ),
  ),
),
```
2. On the `Wrap` (the preset chips), add `alignment: WrapAlignment.center,`.

- [ ] **Step 2: Style the reset button on-brand**

Change the final `TextButton` to gold foreground:
```dart
Center(
  child: TextButton(
    style: TextButton.styleFrom(foregroundColor: KivoColors.gold),
    onPressed: () => ctrl.setRate(1.0),
    child: const Text('Restablecer (1x)'),
  ),
),
```

- [ ] **Step 3: Analyze + test + commit**

`flutter analyze` clean; `flutter test` green — confirm `speed_panel_test.dart` still passes (the `2.0x` chip is still a tappable `GestureDetector` with that exact label). Commit: `feat: speed panel grab handle + centered presets + on-brand reset`.

---

### Task 3: Accumulating skip feedback (rapid repeats sum the seconds)

**Files:**
- Create: `lib/ui/player/state/skip_feedback.dart`
- Modify: `lib/ui/player/controls/center_controls.dart` (skip buttons route through the accumulator)
- Modify: `lib/ui/player/gestures/player_gestures.dart` (`_onDoubleTap` left/right route through the accumulator)
- Test: `test/ui/player/skip_feedback_test.dart` (new)

**Interfaces:**
- Produces: `skipFeedbackProvider` (`Provider<SkipFeedback>`); `SkipFeedback.bump(int seconds)`.
- Consumes: `hudProvider` (HUD seek display), `playerControllerProvider` (the actual `skipBy` still happens at the call site).

When the user skips forward/back repeatedly within a short window (~1s), the seek HUD should show the cumulative total (`+10s` → `+20s` → `+30s`) instead of resetting to a single jump each time. The underlying `ctrl.skipBy(...)` still fires per event (so the net seek equals the displayed total). A direction change or window expiry resets the running total. This applies to BOTH the center skip buttons and the double-tap; the horizontal-drag scrub is unaffected (it shows an absolute target, not a delta).

- [ ] **Step 1: Create `skip_feedback.dart`**

```dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'hud_state.dart';

final skipFeedbackProvider = Provider<SkipFeedback>((ref) {
  final f = SkipFeedback(ref);
  ref.onDispose(f.dispose);
  return f;
});

/// Accumulates consecutive same-direction skips within [_window] and renders
/// the running total in the seek HUD. The actual seek (`skipBy`) is performed
/// by the caller; this only manages the cumulative display.
class SkipFeedback {
  SkipFeedback(this._ref);
  final Ref _ref;
  static const _window = Duration(milliseconds: 1000);
  int _total = 0;
  int _dir = 0;
  Timer? _timer;

  void bump(int seconds) {
    final dir = seconds.sign;
    if (dir == _dir && (_timer?.isActive ?? false)) {
      _total += seconds;
    } else {
      _total = seconds;
      _dir = dir;
    }
    final label = '${_total >= 0 ? '+' : '-'}${_total.abs()}s';
    _ref.read(hudProvider.notifier).show(HudKind.seek, _total >= 0 ? 1.0 : -1.0, label);
    _timer?.cancel();
    _timer = Timer(_window, () {
      _total = 0;
      _dir = 0;
    });
  }

  void dispose() => _timer?.cancel();
}
```

- [ ] **Step 2: Route the center skip buttons through it** (`center_controls.dart`)

For the back button `onPressed`, replace the body with:
```dart
onPressed: () {
  ctrl.skipBy(-skip);
  ref.read(skipFeedbackProvider).bump(-skip);
},
```
Forward button:
```dart
onPressed: () {
  ctrl.skipBy(skip);
  ref.read(skipFeedbackProvider).bump(skip);
},
```
(Remove the old direct `hudProvider.notifier).show(HudKind.seek, ...)` calls — the accumulator shows the HUD now. `center_controls.dart` will need `import '../state/skip_feedback.dart';`.)

- [ ] **Step 3: Route the double-tap through it** (`player_gestures.dart` `_onDoubleTap`)

In the `TapZone.left` case, replace the `hudProvider...show(...)` line with `ref.read(skipFeedbackProvider).bump(-st.doubleTapSkipLeft);` (keep `ctrl.skipBy(-st.doubleTapSkipLeft);` and `_haptic();`). In the `TapZone.right` case, replace with `ref.read(skipFeedbackProvider).bump(st.doubleTapSkipRight);`. Add `import '../state/skip_feedback.dart';`.

- [ ] **Step 4: Test** (`test/ui/player/skip_feedback_test.dart`) — use `fake_async` (already a dev dep) and a `ProviderContainer`

```dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/ui/player/state/hud_state.dart';
import 'package:kivo_player/ui/player/state/skip_feedback.dart';

void main() {
  test('consecutive same-direction skips accumulate within the window', () {
    fakeAsync((async) {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final f = c.read(skipFeedbackProvider);

      f.bump(10);
      expect(c.read(hudProvider)!.label, '+10s');
      async.elapse(const Duration(milliseconds: 300));
      f.bump(10);
      expect(c.read(hudProvider)!.label, '+20s');

      async.elapse(const Duration(milliseconds: 1200)); // window expires
      f.bump(10);
      expect(c.read(hudProvider)!.label, '+10s'); // reset
    });
  });

  test('direction change resets the running total', () {
    fakeAsync((async) {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final f = c.read(skipFeedbackProvider);
      f.bump(10);
      f.bump(-10); // opposite dir within window
      expect(c.read(hudProvider)!.label, '-10s');
    });
  });
}
```
NOTE to implementer: confirm `hudProvider`'s exposed state type and the field that holds the label (the brief assumes `.label`); read `hud_state.dart` and adapt the assertions to the real shape. If `hudProvider` has its own auto-hide timer that interferes under `fakeAsync`, assert immediately after `bump` (before elapsing) as shown.

- [ ] **Step 5: Analyze + test + commit**

`flutter analyze` clean; `flutter test` green. Commit: `feat: accumulating skip feedback (rapid repeats sum the seconds)`.

---

### Task 4: Accessibility tooltips on control buttons

**Files:**
- Modify: `lib/ui/player/controls/center_controls.dart`
- Modify: `lib/ui/player/controls/top_bar.dart`
- Modify: `lib/ui/player/controls/bottom_bar.dart`

**Interfaces:** none new. Adds the built-in `IconButton.tooltip` (which also feeds screen-reader semantics) to each enabled control button.

Add a Spanish `tooltip:` to every enabled control `IconButton`. Tooltips appear on long-press (touch) and hover, and are announced by TalkBack. Messages (sentence case, matching the app's Spanish voice):

- [ ] **Step 1: center_controls.dart** — back: `'Retroceder ${skip}s'`; play/pause: `playing ? 'Pausar' : 'Reproducir'`; forward: `'Avanzar ${skip}s'`.
- [ ] **Step 2: top_bar.dart** — read the file; add tooltips to each enabled button: back → `'Atrás'`, the info-overlay toggle → `'Información en pantalla'`. For the currently-disabled buttons (subtitles/pip/audio/more), add tooltips too if they render (harmless), otherwise skip — don't enable disabled controls.
- [ ] **Step 3: bottom_bar.dart** — read the file; add: speed → `'Velocidad'`, lock → `'Bloquear pantalla'`, aspect → `'Relación de aspecto'`, rotate → `'Rotar'`. Match whatever button widget is used (if not `IconButton`, wrap the child in a `Tooltip(message: ...)`).
- [ ] **Step 4: Analyze + test + commit**

`flutter analyze` clean; `flutter test` green (tooltips don't change behavior; if a widget test does `tester.tap` on a button now wrapped in `Tooltip`, it still works — `Tooltip` is transparent to taps). Commit: `feat: a11y tooltips on player control buttons`.

---

## After all tasks

1. `flutter test` green, `flutter analyze` clean.
2. Whole-branch review.
3. Release build to the Pixel 6 for on-device verification of: detents feel right, meter on the left during hold-right, no spinner during seek, compact badge (not the selector) on hold-left, centered/on-style panel, accumulating skip seconds on rapid repeats, and tooltips appearing on long-press.
