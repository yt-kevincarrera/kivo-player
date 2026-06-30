# Micro-Animations Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add tasteful micro-animations — a double-tap skip ripple, a play/pause morph, tactile press-bounce on center buttons, a chevron nudge on ±10s, and a growing seek knob while scrubbing.

**Architecture:** Each effect is a local `AnimationController` on a small widget (or a `StateProvider`-driven overlay). No new packages. On-brand (accent gold, dark). Perf-isolated.

**Tech Stack:** Flutter, Riverpod.

## Global Constraints

- Accent is configurable: `Color(ref.watch(settingsProvider).accentColor)`; never hardcode gold in widgets.
- Ripple accumulation window **1000 ms** (mirrors `SkipFeedback`); double-tap shows the ripple, NOT the center seek chip (`skipFeedbackProvider` stays for the ±10s buttons and the horizontal drag-seek).
- Dispose every `AnimationController`; cancel every `Timer` (via `ref.onDispose` for providers).
- Preserve existing behavior: skip amounts, tooltips/a11y on `IconButton`s, the play gold ring, seek scrub/commit, dead-zone/dismiss gestures.
- `flutter analyze` clean; `flutter test` green (currently 77). The `RippleController` accumulation is unit-tested; visuals are device-verified.

---

### Task 1: Double-tap skip ripple

**Files:**
- Create: `lib/ui/player/gestures/ripple_state.dart`
- Create: `lib/ui/player/gestures/ripple_overlay.dart`
- Modify: `lib/ui/player/gestures/player_gestures.dart` (`_onDoubleTap` → ripple)
- Modify: `lib/ui/player/player_screen.dart` (mount `RippleOverlay`)
- Test: `test/ui/player/gestures/ripple_controller_test.dart`

**Interfaces:**
- Produces: `RippleEvent {bool left; int seconds; int id}`; `rippleProvider` (`StateProvider<RippleEvent?>`); `rippleControllerProvider` (`Provider<RippleController>`); `RippleController.bump({required bool left, required int seconds})`; `RippleOverlay` widget.

- [ ] **Step 1: Create `ripple_state.dart`**

```dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RippleEvent {
  final bool left;     // true = rewind side, false = forward side
  final int seconds;   // accumulated magnitude for this side/window
  final int id;        // monotonic — re-triggers the overlay even if left/seconds repeat
  const RippleEvent(this.left, this.seconds, this.id);
}

final rippleProvider = StateProvider<RippleEvent?>((ref) => null);

final rippleControllerProvider = Provider<RippleController>((ref) {
  final c = RippleController(ref);
  ref.onDispose(c.dispose);
  return c;
});

/// Accumulates rapid same-side double-taps (within [_window]) and publishes a
/// [RippleEvent] for the overlay. Mirrors SkipFeedback's accumulation, but
/// drives the on-screen ripple instead of the seek HUD chip.
class RippleController {
  RippleController(this._ref);
  final Ref _ref;
  static const _window = Duration(milliseconds: 1000);
  int _total = 0;
  int _dir = 0; // -1 left, 1 right, 0 idle
  int _id = 0;
  Timer? _timer;

  void bump({required bool left, required int seconds}) {
    final dir = left ? -1 : 1;
    if (dir == _dir && (_timer?.isActive ?? false)) {
      _total += seconds;
    } else {
      _total = seconds;
      _dir = dir;
    }
    _id++;
    _ref.read(rippleProvider.notifier).state = RippleEvent(left, _total, _id);
    _timer?.cancel();
    _timer = Timer(_window, () {
      _total = 0;
      _dir = 0;
    });
  }

  void dispose() => _timer?.cancel();
}
```

- [ ] **Step 2: Write the failing test** — `test/ui/player/gestures/ripple_controller_test.dart`

```dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/ui/player/gestures/ripple_state.dart';

void main() {
  test('same-side double-taps accumulate within the window; id increments', () {
    fakeAsync((async) {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final r = c.read(rippleControllerProvider);

      r.bump(left: false, seconds: 10);
      var e = c.read(rippleProvider)!;
      expect(e.left, false);
      expect(e.seconds, 10);
      final firstId = e.id;

      r.bump(left: false, seconds: 10); // same side, within window
      e = c.read(rippleProvider)!;
      expect(e.seconds, 20);
      expect(e.id, greaterThan(firstId));
    });
  });

  test('opposite side resets the total', () {
    fakeAsync((async) {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final r = c.read(rippleControllerProvider);
      r.bump(left: false, seconds: 10);
      r.bump(left: true, seconds: 10); // switch side
      final e = c.read(rippleProvider)!;
      expect(e.left, true);
      expect(e.seconds, 10);
    });
  });

  test('window expiry resets the total', () {
    fakeAsync((async) {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final r = c.read(rippleControllerProvider);
      r.bump(left: false, seconds: 10);
      async.elapse(const Duration(milliseconds: 1200));
      r.bump(left: false, seconds: 10);
      expect(c.read(rippleProvider)!.seconds, 10);
    });
  });
}
```

- [ ] **Step 3: Run — verify fail**

Run: `flutter test test/ui/player/gestures/ripple_controller_test.dart` → FAIL (undefined).

- [ ] **Step 4: (file from Step 1 makes it pass) Run — verify pass**

Run: `flutter test test/ui/player/gestures/ripple_controller_test.dart` → PASS (3/3).

- [ ] **Step 5: Create `ripple_overlay.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/icons/kivo_icons.dart';
import '../../../core/settings/settings_provider.dart';
import 'ripple_state.dart';

/// Expanding wave + chevrons + accumulated seconds on the tapped half, on
/// double-tap. Renders nothing between animations. Never blocks gestures.
class RippleOverlay extends ConsumerStatefulWidget {
  const RippleOverlay({super.key});
  @override
  ConsumerState<RippleOverlay> createState() => _RippleOverlayState();
}

class _RippleOverlayState extends ConsumerState<RippleOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 450));
  int _lastId = 0;
  RippleEvent? _event;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(rippleProvider, (_, next) {
      if (next != null && next.id != _lastId) {
        _lastId = next.id;
        setState(() => _event = next);
        _c.forward(from: 0);
      }
    });

    final e = _event;
    if (e == null) return const SizedBox.shrink();
    final accent = Color(ref.watch(settingsProvider).accentColor);

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value;
          if (t >= 1.0) return const SizedBox.shrink();
          final fade = 1.0 - t;
          return Align(
            alignment: e.left ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: 0.32 * fade,
                    child: Transform.scale(
                      scale: 0.3 + t * 1.2,
                      child: Container(
                        width: 170,
                        height: 170,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: Colors.white),
                      ),
                    ),
                  ),
                  Opacity(
                    opacity: fade,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        KivoIcon(e.left ? KivoIcons.skipBack : KivoIcons.skipForward,
                            size: 34, color: Colors.white),
                        const SizedBox(height: 2),
                        Text('${e.seconds}s',
                            style: TextStyle(
                                color: accent,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 6: Route double-tap to the ripple** (`player_gestures.dart` `_onDoubleTap`)

In the `TapZone.left` case, replace `ref.read(skipFeedbackProvider).bump(-st.doubleTapSkipLeft);` with `ref.read(rippleControllerProvider).bump(left: true, seconds: st.doubleTapSkipLeft);`. In `TapZone.right`, replace `ref.read(skipFeedbackProvider).bump(st.doubleTapSkipRight);` with `ref.read(rippleControllerProvider).bump(left: false, seconds: st.doubleTapSkipRight);`. Keep `ctrl.skipBy(...)` and `_haptic()`. Add `import 'ripple_state.dart';`. (`skipFeedbackProvider` import stays — still used elsewhere? It is NOT used elsewhere in this file after this change; if the import becomes unused, remove it. The ±10s BUTTONS use `skipFeedbackProvider` in `center_controls.dart`, not here.)

- [ ] **Step 7: Mount the overlay** (`player_screen.dart`)

Add `import 'gestures/ripple_overlay.dart';` and insert `const Positioned.fill(child: RippleOverlay()),` into the body `Stack` (after `PlayerGestures`, before/around the controls — above the video, doesn't matter much since it's IgnorePointer; put it right after the `PlayerGestures` child).

- [ ] **Step 8: Analyze + test + commit**

`flutter analyze` clean; `flutter test` (77 + 3 = 80) green. Commit: `feat: double-tap skip ripple (wave + chevrons + accumulated seconds)`.

---

### Task 2: Center controls — morph + press-bounce + chevron nudge

**Files:**
- Modify: `lib/ui/player/controls/center_controls.dart`

**Interfaces:** Consumes existing `playerControllerProvider`, `playingProvider`, `settingsProvider`, `skipFeedbackProvider`, `KivoIcons`. Produces nothing external.

- [ ] **Step 1: Add `_PressBounce`** (private widget in the file)

```dart
class _PressBounce extends StatefulWidget {
  final Widget child;
  const _PressBounce({required this.child});
  @override
  State<_PressBounce> createState() => _PressBounceState();
}

class _PressBounceState extends State<_PressBounce> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) => Listener(
        // Translucent so the IconButton beneath still gets the tap; we only
        // observe the press to drive the scale (no event consumed).
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1.0,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      );
}
```

- [ ] **Step 2: Morph the play/pause icon**

In `CenterControls.build`, wrap the play/pause `IconButton` in `_PressBounce`, and change its `icon:` to an `AnimatedSwitcher`:
```dart
_PressBounce(
  child: IconButton(
    key: const Key('kivo_play_pause'),
    iconSize: 56,
    color: Colors.white,
    tooltip: playing ? 'Pausar' : 'Reproducir',
    style: IconButton.styleFrom(
      shape: CircleBorder(side: BorderSide(color: accent, width: 2)),
    ),
    icon: AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, anim) =>
          ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child)),
      child: KivoIcon(playing ? KivoIcons.pause : KivoIcons.play,
          key: ValueKey(playing), size: 56, color: Colors.white),
    ),
    onPressed: ctrl.togglePlayPause,
  ),
),
```

- [ ] **Step 3: Extract `_SkipButton` with the nudge**

Replace the two inline skip `IconButton`s with a `_SkipButton`:
```dart
class _SkipButton extends ConsumerStatefulWidget {
  final bool forward;
  const _SkipButton({required this.forward});
  @override
  ConsumerState<_SkipButton> createState() => _SkipButtonState();
}

class _SkipButtonState extends ConsumerState<_SkipButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _nudge = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 220));
  late final Animation<double> _dx = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 1),
  ]).animate(CurvedAnimation(parent: _nudge, curve: Curves.easeOut));

  @override
  void dispose() {
    _nudge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.read(playerControllerProvider);
    final skip = ref.watch(settingsProvider).centerSkipSeconds;
    final accent = Color(ref.watch(settingsProvider).accentColor);
    final dir = widget.forward ? 1.0 : -1.0;
    return _PressBounce(
      child: IconButton(
        iconSize: 34,
        color: Colors.white,
        padding: const EdgeInsets.all(18),
        constraints: const BoxConstraints(minWidth: 68, minHeight: 68),
        splashRadius: 34,
        tooltip: widget.forward ? 'Avanzar ${skip}s' : 'Retroceder ${skip}s',
        icon: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _dx,
              builder: (_, child) =>
                  Transform.translate(offset: Offset(_dx.value * 4 * dir, 0), child: child),
              child: KivoIcon(
                  widget.forward ? KivoIcons.skipForward : KivoIcons.skipBack,
                  size: 30, color: Colors.white),
            ),
            const SizedBox(height: 1),
            Text('${skip}s',
                style: TextStyle(
                    color: accent, fontSize: 11, fontWeight: FontWeight.w700, height: 1.0)),
          ],
        ),
        onPressed: () {
          final s = widget.forward ? skip : -skip;
          ctrl.skipBy(s);
          ref.read(skipFeedbackProvider).bump(s);
          _nudge.forward(from: 0);
        },
      ),
    );
  }
}
```
Then in `CenterControls.build`, the row becomes: `const _SkipButton(forward: false)`, the play/pause `_PressBounce`, `const _SkipButton(forward: true)` (with the existing `SizedBox(width: 36)` spacers). Add `import '../state/skip_feedback.dart';` (already imported? verify — `center_controls.dart` imports it from the skip-feedback round). Remove now-unused `HudKind`/`hud_state` import only if it ends up unused.

- [ ] **Step 4: Analyze + test + commit**

`flutter analyze` clean; `flutter test` green — if `center_controls`/`player_screen_controls` tests find the play/pause by `Key('kivo_play_pause')` or tap the skip buttons, confirm they still pass (the key is preserved; `_SkipButton` is still an `IconButton` with the same tooltip/`onPressed`). If a test taps a skip button and asserts the skip, it still works. Commit: `feat: center controls play/pause morph + press-bounce + skip chevron nudge`.

---

### Task 3: Growing seek knob while scrubbing

**Files:**
- Modify: `lib/ui/player/controls/seek_bar.dart`

**Interfaces:** Consumes `scrubProvider` (existing). Produces nothing external.

- [ ] **Step 1: Make `SeekBar` stateful with a thumb animation**

Convert `SeekBar` from `ConsumerWidget` to `ConsumerStatefulWidget` + `SingleTickerProviderStateMixin`. Add:
```dart
late final AnimationController _thumbAnim = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 160));
```
Dispose it. In `build`, drive it from scrub state:
```dart
ref.listen(scrubProvider, (prev, next) {
  if (next != null) {
    _thumbAnim.forward();
  } else {
    _thumbAnim.reverse();
  }
});
```
(Keep the existing `pendingSeekProvider` position-sync `ref.listen` too.)

- [ ] **Step 2: Custom thumb shape**

```dart
class _GrowingThumbShape extends SliderComponentShape {
  final Animation<double> anim; // 0 = rest, 1 = scrubbing
  final Color color;
  const _GrowingThumbShape(this.anim, this.color);

  @override
  Size getPreferredSize(bool enabled, bool isDiscrete) => const Size.fromRadius(11);

  @override
  void paint(PaintingContext context, Offset center,
      {required Animation<double> activationAnimation,
      required Animation<double> enableAnimation,
      required bool isDiscrete,
      required TextPainter labelPainter,
      required RenderBox parentBox,
      required SliderThemeData sliderTheme,
      required TextDirection textDirection,
      required double value,
      required double textScaleFactor,
      required Size sizeWithOverflow}) {
    final radius = 7.0 + 4.0 * anim.value; // 7 → 11
    context.canvas.drawCircle(center, radius, Paint()..color = color);
  }
}
```

- [ ] **Step 3: Wrap the `Slider` in a `SliderTheme`** with the custom thumb, repainting on `_thumbAnim`:

```dart
Expanded(
  child: SliderTheme(
    data: SliderTheme.of(context).copyWith(
      thumbShape: _GrowingThumbShape(_thumbAnim, accent),
      overlayShape: SliderComponentShape.noOverlay,
    ),
    child: Slider(
      min: 0,
      max: maxMs,
      value: shownPos.inMilliseconds.clamp(0, maxMs.toInt()).toDouble(),
      activeColor: accent,
      inactiveColor: Colors.white24,
      onChanged: (v) { /* existing onChanged body unchanged */ },
      onChangeEnd: (v) { /* existing onChangeEnd body unchanged */ },
    ),
  ),
),
```
The thumb shape needs to repaint as `_thumbAnim` ticks: pass `_thumbAnim` as the `Animation` (it IS a `Listenable`); `SliderComponentShape.paint` is called by the framework when the slider repaints, but to force repaints during the 160ms tween, wrap the whole `Slider` in an `AnimatedBuilder(animation: _thumbAnim, builder: (_, child) => SliderTheme(...))` so each tick rebuilds the SliderTheme with a fresh shape reading the new value. (Simplest correct approach — rebuild the SliderTheme subtree on each tick.)

Concretely:
```dart
Expanded(
  child: AnimatedBuilder(
    animation: _thumbAnim,
    builder: (context, _) => SliderTheme(
      data: SliderTheme.of(context).copyWith(
        thumbShape: _GrowingThumbShape(_thumbAnim, accent),
        overlayShape: SliderComponentShape.noOverlay,
      ),
      child: Slider( /* as above */ ),
    ),
  ),
),
```

- [ ] **Step 4: Analyze + test + commit**

`flutter analyze` clean; `flutter test` green — `seek_bar_test.dart` taps/drags the slider; confirm it still finds the `Slider` and the scrub/commit behavior is unchanged (only the thumb visual changed). Commit: `feat: seek knob grows while scrubbing`.

---

## After all tasks

1. `flutter test` green, `flutter analyze` clean.
2. Whole-branch review.
3. Release build to the Pixel 6: double-tap shows the ripple (wave + chevrons + accumulating seconds, no chip); play/pause morphs; center buttons bounce on press; ±10s chevrons nudge; the seek knob grows while dragging. All smooth, no jank.
