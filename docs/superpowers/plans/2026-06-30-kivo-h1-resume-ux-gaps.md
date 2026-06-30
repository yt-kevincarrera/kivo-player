# Resume Toast + UX Gaps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Close the remaining spec'd Hito-1 UX gaps that need no video-frame extraction: (1) resume toast + `auto/preguntar/off` modes (§11), (2) bottom-bar right time toggles total↔remaining (§8), (3) speed panel "save custom preset" + press-hold-to-accelerate the +/- (§7), (4) gesture dead zones near notch/nav bar (§6).

**Architecture:** Pure Flutter/Riverpod. Pure decision helpers (tested) + thin UI. Settings persist via `ref.read(settingsProvider.notifier).set(...)`. No new packages.

**Tech Stack:** Flutter, Riverpod, Hive-backed settings.

## Global Constraints

- On-brand styling: dark capsule `Colors.black.withValues(alpha: 0.5..0.85)`, accent = `Color(ref.watch(settingsProvider).accentColor)` (gold default `0xFFE8B84B`), sentence-case Spanish copy, `fmtDuration` from `core/format.dart` for times.
- Settings changes persist through `settingsProvider.notifier.set(next)` (Notifier already wired to Hive).
- No regression to existing resume save/restore, gesture mapping, or the seek bar's role as the sole `positionProvider` watcher.
- `flutter analyze` clean; `flutter test` green (currently 62/62). Pure helpers get unit tests.

---

### Task 1: Resume toast + auto/preguntar/off modes

**Files:**
- Create: `lib/player/resume/resume_plan.dart` (pure decision)
- Create: `lib/ui/player/controls/resume_prompt.dart` (provider + overlay widget)
- Modify: `lib/ui/player/player_screen.dart` (branch on behavior; trigger prompt; add overlay to stack)
- Test: `test/player/resume/resume_plan_test.dart`

**Interfaces:**
- Produces: `ResumePromptKind { none, undo, ask }`; `ResumePlan { Duration startAt; ResumePromptKind prompt; Duration savedPosition }`; `ResumePlan planResume(Duration? saved, String behavior)`; `resumePromptProvider` (`StateProvider<ResumePromptState?>`); `ResumePromptState { ResumePromptKind kind; Duration savedPosition }`; `ResumePrompt` widget.
- Consumes: `resumeServiceProvider.positionFor`, `settingsProvider.resumeBehavior`, `playerControllerProvider.seekTo`.

Current behavior (`player_screen.dart` `_start`): always opens at `resume.positionFor(path) ?? Duration.zero` — silent, ignores `resumeBehavior`. New behavior: `auto` resumes + shows an undo toast; `preguntar` opens at 0 and asks; `off` opens at 0 silently.

- [ ] **Step 1: Pure `resume_plan.dart`**

```dart
enum ResumePromptKind { none, undo, ask }

class ResumePlan {
  final Duration startAt;
  final ResumePromptKind prompt;
  final Duration savedPosition;
  const ResumePlan(this.startAt, this.prompt, this.savedPosition);
}

/// Decides where to start playback and whether to surface a resume prompt.
/// [behavior] is `settings.resumeBehavior`: 'auto' | 'ask' | 'off'.
ResumePlan planResume(Duration? saved, String behavior) {
  final s = saved ?? Duration.zero;
  if (s <= Duration.zero || behavior == 'off') {
    return const ResumePlan(Duration.zero, ResumePromptKind.none, Duration.zero);
  }
  if (behavior == 'ask') {
    return ResumePlan(Duration.zero, ResumePromptKind.ask, s); // start at 0, offer to jump
  }
  return ResumePlan(s, ResumePromptKind.undo, s); // 'auto' (default): resume + undo toast
}
```
NOTE: `resumeBehavior` stored values are `'auto'` | `'ask'` | `'off'` (the settings doc label "preguntar" maps to `'ask'`). Confirm the stored string in `kivo_settings.dart` defaults/serialization and use the real value.

- [ ] **Step 2: Test `resume_plan_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/resume/resume_plan.dart';

void main() {
  test('off or no-saved → start at zero, no prompt', () {
    expect(planResume(const Duration(seconds: 90), 'off').prompt, ResumePromptKind.none);
    expect(planResume(null, 'auto').prompt, ResumePromptKind.none);
    expect(planResume(Duration.zero, 'auto').prompt, ResumePromptKind.none);
  });
  test('auto → resume at saved + undo toast', () {
    final p = planResume(const Duration(seconds: 90), 'auto');
    expect(p.startAt, const Duration(seconds: 90));
    expect(p.prompt, ResumePromptKind.undo);
    expect(p.savedPosition, const Duration(seconds: 90));
  });
  test('ask → start at zero, ask prompt carries saved position', () {
    final p = planResume(const Duration(seconds: 90), 'ask');
    expect(p.startAt, Duration.zero);
    expect(p.prompt, ResumePromptKind.ask);
    expect(p.savedPosition, const Duration(seconds: 90));
  });
}
```

- [ ] **Step 3: `resume_prompt.dart` (provider + overlay)**

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../player/control/player_controller.dart';
import '../../../player/resume/resume_plan.dart';

class ResumePromptState {
  final ResumePromptKind kind;
  final Duration savedPosition;
  const ResumePromptState(this.kind, this.savedPosition);
}

final resumePromptProvider = StateProvider<ResumePromptState?>((ref) => null);

/// Bottom-centered, auto-dismissing resume toast/prompt. `undo` = "Reanudado
/// desde M:SS · Reiniciar"; `ask` = "¿Reanudar desde M:SS?" with two choices.
class ResumePrompt extends ConsumerStatefulWidget {
  const ResumePrompt({super.key});
  @override
  ConsumerState<ResumePrompt> createState() => _ResumePromptState();
}

class _ResumePromptState extends ConsumerState<ResumePrompt> {
  Timer? _timer;
  void _clear() {
    _timer?.cancel();
    ref.read(resumePromptProvider.notifier).state = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(resumePromptProvider, (_, next) {
      _timer?.cancel();
      if (next != null) {
        _timer = Timer(
          Duration(seconds: next.kind == ResumePromptKind.ask ? 8 : 5),
          () => ref.read(resumePromptProvider.notifier).state = null,
        );
      }
    });

    final s = ref.watch(resumePromptProvider);
    if (s == null) return const SizedBox.shrink();
    final accent = Color(ref.watch(settingsProvider).accentColor);
    final ctrl = ref.read(playerControllerProvider);
    final pos = fmtDuration(s.savedPosition);

    Widget action(String label, VoidCallback onTap) => TextButton(
          style: TextButton.styleFrom(foregroundColor: accent),
          onPressed: onTap,
          child: Text(label),
        );

    final children = <Widget>[];
    if (s.kind == ResumePromptKind.undo) {
      children.add(Flexible(child: Text('Reanudado desde $pos',
          style: const TextStyle(color: Colors.white))));
      children.add(action('Reiniciar', () { ctrl.seekTo(Duration.zero); _clear(); }));
    } else {
      children.add(Flexible(child: Text('¿Reanudar desde $pos?',
          style: const TextStyle(color: Colors.white))));
      children.add(action('Desde el inicio', _clear));
      children.add(action('Reanudar', () { ctrl.seekTo(s.savedPosition); _clear(); }));
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 96),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Wire `player_screen.dart`**

In `_start`, replace the `startAt` computation + `engine.open(...)` so it uses `planResume`:
```dart
final plan = planResume(resume.positionFor(session.path), ref.read(settingsProvider).resumeBehavior);
// ... create controller ...
await engine.open(session.path, startAt: plan.startAt);
if (plan.prompt != ResumePromptKind.none) {
  ref.read(resumePromptProvider.notifier).state =
      ResumePromptState(plan.prompt, plan.savedPosition);
}
```
Add `const Positioned.fill(child: ResumePrompt())` to the Stack (above HudOverlay is fine — it's bottom-anchored). Add imports for `resume_plan.dart` and `resume_prompt.dart`. Keep the rest of `_start` (rate restore) unchanged.

- [ ] **Step 5: Analyze + test + commit** — `feat: resume toast with undo + auto/ask/off modes`

---

### Task 2: Bottom-bar right time toggles total ↔ remaining

**Files:** Modify `lib/ui/player/controls/seek_bar.dart`

**Interfaces:** Produces `showRemainingProvider` (`StateProvider<bool>`). `SeekBar` stays the sole `positionProvider` watcher.

- [ ] **Step 1:** Add at top of file: `final showRemainingProvider = StateProvider<bool>((ref) => false);`
- [ ] **Step 2:** Replace the trailing `Text(fmtDuration(total), ...)` with a tappable widget:
```dart
GestureDetector(
  onTap: () => ref.read(showRemainingProvider.notifier).update((v) => !v),
  behavior: HitTestBehavior.opaque,
  child: Text(
    ref.watch(showRemainingProvider)
        ? '-${fmtDuration(total - pos < Duration.zero ? Duration.zero : total - pos)}'
        : fmtDuration(total),
    style: const TextStyle(color: Colors.white, fontSize: 12),
  ),
),
```
- [ ] **Step 3: Analyze + test + commit** — `feat: bottom-bar time toggles total/remaining`

---

### Task 3: Speed panel — save custom preset + press-hold +/- accelerate

**Files:** Modify `lib/ui/player/speed/speed_panel.dart`

**Interfaces:** Consumes `settingsProvider.notifier.set` (persist presets), `playerControllerProvider.setRate`, `round2`.

- [ ] **Step 1: Press-hold-to-accelerate the +/- buttons.** Replace each `IconButton` (minus/plus) with a small repeating-press widget. Add this private widget to the file:
```dart
class _RepeatButton extends StatefulWidget {
  final Widget icon;
  final VoidCallback onStep;
  const _RepeatButton({required this.icon, required this.onStep});
  @override
  State<_RepeatButton> createState() => _RepeatButtonState();
}

class _RepeatButtonState extends State<_RepeatButton> {
  Timer? _timer;
  void _start() {
    widget.onStep();
    var period = 320;
    _timer = Timer.periodic(Duration(milliseconds: period), (t) {
      widget.onStep();
      if (period > 60) { // accelerate
        period = (period * 0.82).round();
        t.cancel();
        _start2(period);
      }
    });
  }
  void _start2(int period) {
    _timer = Timer.periodic(Duration(milliseconds: period), (_) => widget.onStep());
  }
  void _stop() { _timer?.cancel(); _timer = null; }
  @override
  void dispose() { _timer?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: widget.onStep,
        onLongPressDown: (_) {},
        onLongPress: _start,
        onLongPressUp: _stop,
        onLongPressCancel: _stop,
        child: Padding(padding: const EdgeInsets.all(12), child: widget.icon),
      );
}
```
NOTE to implementer: the two-stage accelerate above is illustrative — implement a clean version: a single `Timer.periodic` whose first few ticks are slower then settle to ~70ms is fine. Keep tap = one step (`onStep`), long-press = repeat that accelerates, released on up/cancel. The single tap must still fire exactly one `setRate` step. Use `_RepeatButton(icon: KivoIcon(KivoIcons.minus,...), onStep: () => ctrl.setRate(round2(rate - st.speedFineStep)))` and the plus equivalent. Add `import 'dart:async';`.

- [ ] **Step 2: Save custom preset.** In the preset `Wrap`, after the preset chips, append an "add" chip shown only when the current `rate` isn't already a preset:
```dart
if (!st.speedPresets.any((p) => (p - rate).abs() < 0.001))
  GestureDetector(
    onTap: () {
      final next = [...st.speedPresets, round2(rate)]..sort();
      ref.read(settingsProvider.notifier).set(st.copyWith(speedPresets: next));
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: KivoColors.gold),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        KivoIcon(KivoIcons.plus, size: 16, color: KivoColors.gold),
        const SizedBox(width: 4),
        Text('Guardar ${round2(rate)}x',
            style: const TextStyle(color: KivoColors.gold, fontWeight: FontWeight.w600, fontSize: 13)),
      ]),
    ),
  ),
```
Keep existing chip behavior (tap = setRate; gold-active highlight) untouched.

- [ ] **Step 3: Analyze + test + commit** — `feat: speed panel save-preset + press-hold +/- accelerate`. Confirm `speed_panel_test.dart` still passes (the `2.0x` chip is unchanged).

---

### Task 4: Gesture dead zones (notch / nav bar)

**Files:**
- Modify: `lib/player/control/gesture_math.dart` (add `inVerticalDeadZone`)
- Modify: `lib/ui/player/gestures/player_gestures.dart` (gate drags + long-press by dead zones)
- Test: `test/player/control/gesture_math_test.dart` (add cases)

**Interfaces:** Produces `bool inVerticalDeadZone(double localY, double height, double topInset, double bottomInset, double margin)`.

- [ ] **Step 1: Pure helper** in `gesture_math.dart`:
```dart
/// True when a touch at [localY] falls in the top/bottom dead strips reserved
/// for system gestures (notch / nav bar), = system inset + [margin].
bool inVerticalDeadZone(double localY, double height, double topInset,
        double bottomInset, double margin) =>
    localY < topInset + margin || localY > height - bottomInset - margin;
```

- [ ] **Step 2: Test** (`gesture_math_test.dart`):
```dart
test('inVerticalDeadZone: top and bottom strips, middle is live', () {
  expect(inVerticalDeadZone(10, 400, 20, 30, 24), isTrue);   // within top inset+margin
  expect(inVerticalDeadZone(390, 400, 20, 30, 24), isTrue);  // within bottom strip
  expect(inVerticalDeadZone(200, 400, 20, 30, 24), isFalse); // live middle
});
```

- [ ] **Step 3: Gate gestures** in `player_gestures.dart`. Capture system insets in `build` (`final mq = MediaQuery.of(context); _topInset = mq.viewPadding.top; _bottomInset = mq.viewPadding.bottom;` — add fields `double _topInset = 0, _bottomInset = 0;` and a `static const _deadMargin = 24.0;`). Add a helper `bool _dead(double dy) => inVerticalDeadZone(dy, _height, _topInset, _bottomInset, _deadMargin);` Then:
  - `_onVerticalStart`: add a field `bool _vDead = false;`; set `_vDead = _dead(d.localPosition.dy);` at the top; if `_vDead` return early (don't seed). In `_onVerticalUpdate`: `if (_vDead) return;` near the existing `if (_holding) return;`.
  - `_onHorizontalStart`: set `bool _hDead = _dead(d.localPosition.dy);` (field); in `_onHorizontalUpdate` add `if (_hDead) return;`.
  - `_onLongPressStart`: `if (_dead(d.localPosition.dy)) { _holding = false; return; }` BEFORE setting `_holding = true` / rate — so a long-press starting in a dead strip does nothing.
  Keep `onTap` (toggle controls) and double-tap working everywhere (taps near edges are harmless; only drags/long-press are gated).

- [ ] **Step 4: Analyze + test + commit** — `feat: gesture dead zones near notch/nav bar`

---

## After all tasks

1. `flutter test` green, `flutter analyze` clean.
2. Whole-branch review.
3. Release build to the Pixel 6 to verify: resume toast (auto) + ask mode, time toggle, save-preset + press-hold +/-, and that edge swipes (notch/nav) no longer trigger brightness/volume/speed.

(Deferred to a later round: double-tap ripple animation §6; then the frame-extraction block 3b = thumbnail queue strip §8 + seek frame preview §9.)
