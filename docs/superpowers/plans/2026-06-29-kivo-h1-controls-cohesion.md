# Control Cohesion Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend Kivo's established "segmented dark+gold" control aesthetic (already shipped on the volume/brightness HUD + gold-ring play button) to the four controls that still feel off-style: hold-to-unlock, the ±10s skip buttons, the seek-by-gesture HUD, and the speed selector (hold-gesture ladder + button panel).

**Architecture:** Pure Flutter UI changes behind the existing widgets/providers. No new packages, no engine/platform changes. One small `CustomPainter` for the segmented ring. All colors come from `settingsProvider.accentColor` (configurable) or `KivoColors.gold`; segments follow the HUD convention `lit = accent`, `unlit = Colors.white.withValues(alpha: 0.18)`.

**Tech Stack:** Flutter, Riverpod, flutter_svg (bespoke `KivoIcon` duotone set).

## Global Constraints

- Segment convention (matches `hud_overlay.dart`): lit segment = accent color; unlit = `Colors.white.withValues(alpha: 0.18)`; rounded `2.5`.
- Capsule convention: `color: Colors.black.withValues(alpha: 0.5)`, pill/rounded corners; tabular figures (`FontFeature.tabularFigures()`) on numerics.
- Duotone `KivoIcon`s must be passed `color: Colors.white` (NOT `accent`) so the base stays white and only the `__ACCENT__` element renders gold. Passing `accent` collapses the duotone to mono — this is a bug to fix where it occurs.
- Accent is configurable: read `Color(ref.watch(settingsProvider).accentColor)` in widgets, never hardcode gold (except inside `KivoColors`-themed surfaces like the speed panel where `KivoColors.gold` is the themed default).
- `flutter test` must stay green (currently 59/59) and `flutter analyze` clean.
- No behavior/logic changes to gestures, skip amounts, speed math, or unlock semantics — visual/timing only (the one timing change: unlock hold duration 800ms → 450ms).

---

### Task 1: Hold-to-unlock — segmented radial ring + faster

**Files:**
- Modify: `lib/ui/player/controls/hold_to_unlock.dart`

**Interfaces:**
- Consumes: nothing new. `HoldToUnlock({onUnlock, accent})` signature unchanged.
- Produces: nothing consumed elsewhere.

Replace the smooth `CircularProgressIndicator` fill with a segmented ring (24 short radial ticks that light clockwise from the top as the hold progresses), and cut the hold duration from 800ms to 450ms. Keep: the long-press gestures, `HapticFeedback.selectionClick()` on start / `mediumImpact()` on complete, the reverse-on-release, the lock icon, and the label.

- [ ] **Step 1: Change duration to 450ms**

In the `AnimationController`, change `duration: const Duration(milliseconds: 800)` → `duration: const Duration(milliseconds: 450)`.

- [ ] **Step 2: Add the segmented-ring painter** (top-level, below the State class)

```dart
class _SegmentRingPainter extends CustomPainter {
  final double progress; // 0..1
  final Color accent;
  static const int segments = 24;
  _SegmentRingPainter(this.progress, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rOuter = size.width / 2 - 1;
    final rInner = rOuter - 5.5;
    final lit = (progress * segments).round();
    final unlitPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    final litPaint = Paint()
      ..color = accent
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < segments; i++) {
      final a = -math.pi / 2 + (i / segments) * 2 * math.pi; // start at top, clockwise
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        center + dir * rInner,
        center + dir * rOuter,
        i < lit ? litPaint : unlitPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_SegmentRingPainter old) =>
      old.progress != progress || old.accent != accent;
}
```

Add `import 'dart:math' as math;` at the top.

- [ ] **Step 3: Swap the indicator for the painter**

Replace the `AnimatedBuilder(... CircularProgressIndicator ...)` child inside the `Stack` with:

```dart
AnimatedBuilder(
  animation: _c,
  builder: (_, __) => CustomPaint(
    size: const Size(44, 44),
    painter: _SegmentRingPainter(_c.value, widget.accent),
  ),
),
```

Keep the centered `Icon(Icons.lock, color: widget.accent, size: 22)` and the surrounding `SizedBox(width: 44, height: 44, child: Stack(...))`.

- [ ] **Step 4: Analyze + test + commit**

Run `flutter analyze` (clean) and `flutter test` (59/59 — no test touches this widget). Commit: `feat: hold-to-unlock segmented ring, 450ms`.

---

### Task 2: ±10s double-chevron buttons + seek HUD capsule cohesion

**Files:**
- Modify: `lib/core/icons/kivo_icons.dart` (add two chevron icons)
- Modify: `lib/ui/player/controls/center_controls.dart` (skip buttons → chevron + gold number)
- Modify: `lib/ui/player/hud/hud_overlay.dart` (`_buildChip`: pill + duotone fix)

**Interfaces:**
- Produces: `KivoIcons.skipBack` and `KivoIcons.skipForward` (double-chevron duotone-base SVG strings), consumed by `center_controls.dart`.
- Consumes: `settingsProvider.centerSkipSeconds` (the `skip` int, already read in `center_controls`).

The ±10s buttons currently use `KivoIcons.replay10`/`forward10` (a circular arrow) plus a `Text('$skip')` overlay — the user rejected this style. Replace with a double chevron (`‹‹` / `››`) and the configurable seconds in accent gold below it. Also fix the seek HUD chip to be a matching dark pill and restore its duotone icon.

- [ ] **Step 1: Add chevron icons to `kivo_icons.dart`**

After the `forward10` definition (around line 54), add:

```dart
// ---- skip N seconds: double chevron (currentColor); seconds shown in gold by the caller ----
static final String skipBack = _wrap(
  '<g fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'
  '<path d="M11.5 6 L5.5 12 L11.5 18"/><path d="M18.5 6 L12.5 12 L18.5 18"/></g>',
);

static final String skipForward = _wrap(
  '<g fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'
  '<path d="M5.5 6 L11.5 12 L5.5 18"/><path d="M12.5 6 L18.5 12 L12.5 18"/></g>',
);
```

Leave `replay10`/`forward10` in place (harmless; may be reused later).

- [ ] **Step 2: Rebuild the skip buttons in `center_controls.dart`**

For BOTH skip buttons, replace the `icon:` (the `SizedBox` wrapping `Stack(KivoIcon(replay10/forward10) + Text('$skip'))`) with a compact column of the chevron over the seconds in accent. The back button uses `KivoIcons.skipBack`, the forward uses `KivoIcons.skipForward`. Keep `iconSize`, `color`, `padding`, `constraints`, `splashRadius`, and the existing `onPressed` (HUD show + `ctrl.skipBy`) unchanged. New `icon:` for the back button:

```dart
icon: Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    KivoIcon(KivoIcons.skipBack, size: 30, color: Colors.white),
    const SizedBox(height: 1),
    Text('${skip}s',
        style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w700, height: 1.0)),
  ],
),
```

Forward button: identical but `KivoIcons.skipForward`. (`accent` and `skip` are already in scope in `build`.)

- [ ] **Step 3: Fix the seek/speed chip in `hud_overlay.dart` (`_buildChip`)**

Two changes to `_buildChip`:
1. Make it a pill matching the capsule tone: `color: Colors.black.withValues(alpha: 0.5)` and `borderRadius: BorderRadius.circular(26)`; bump vertical padding to `14`.
2. Restore the duotone: change `KivoIcon(icon, size: 24, color: accent)` → `KivoIcon(icon, size: 24, color: Colors.white)` (the fast-fwd/rwd icons bake their own accent on the second triangle; passing `accent` collapses them to mono).
3. Add tabular figures to the label `TextStyle`: `fontFeatures: const [FontFeature.tabularFigures()]` (import `dart:ui` is already transitively available via material; if `FontFeature` is unresolved add `import 'dart:ui' show FontFeature;`).

Leave the `speed` icon path (passed for `HudKind.speed`) as-is functionally — `KivoIcons.speed` is single-tone so white is correct there too.

- [ ] **Step 4: Analyze + test + commit**

`flutter analyze` clean; `flutter test` — if `hud_overlay_test` or a center-controls test asserts on the old `Text('$skip')` or the chip color, update the assertion to match the new structure (the seconds text is now `'${skip}s'` in a `Column`; the chip is a pill). Commit: `feat: double-chevron skip buttons; seek HUD duotone pill`.

---

### Task 3: Speed selector — segmented meter (gesture) + restyled panel

**Files:**
- Modify: `lib/ui/player/speed/speed_ladder_overlay.dart` (hold-gesture overlay → segmented meter)
- Modify: `lib/ui/player/speed/speed_panel.dart` (button panel → gold-active presets)

**Interfaces:**
- Consumes: `holdSpeedProvider` (double?), `settingsProvider` (`holdRightMin`, `holdRightMax`, `speedPresets`, `speedFineStep`), `ladderSpeed`/`round2`/`clampRate`/`snapToDetent` from `gesture_math.dart`, `rateProvider`, `playerControllerProvider`. All already imported in the respective files.
- Produces: nothing new.

#### 3a. `speed_ladder_overlay.dart` — segmented vertical meter

Replace the right-aligned column of bordered speed-label chips with a right-edge dark capsule containing a `speed` duotone icon + a vertical segmented meter whose fill = `(speed - min) / (max - min)`. Keep the large centered readout, but render it in accent. Keep `holdSpeedProvider`/`holdRightSpeedFor`/the `IgnorePointer` wrapper.

- [ ] **Step 1: Replace the build body** (keep imports + `holdSpeedProvider` + `holdRightSpeedFor`)

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final speed = ref.watch(holdSpeedProvider);
  if (speed == null) return const SizedBox.shrink();
  final st = ref.watch(settingsProvider);
  final accent = Color(st.accentColor);
  final min = st.holdRightMin, max = st.holdRightMax;
  final fill = max <= min ? 0.0 : ((speed - min) / (max - min)).clamp(0.0, 1.0);
  const segCount = 16;
  final lit = (fill * segCount).round();

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
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        KivoIcon(KivoIcons.speed, size: 26, color: Colors.white),
        const SizedBox(height: 12),
        SizedBox(
          height: 220,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (var i = segCount - 1; i >= 0; i--) seg(i < lit)],
          ),
        ),
      ],
    ),
  );

  return IgnorePointer(
    child: Stack(
      children: [
        Align(
          alignment: Alignment.center,
          child: Text('${speed.toStringAsFixed(1)}x',
              style: TextStyle(color: accent, fontSize: 48, fontWeight: FontWeight.bold)),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 20),
            child: capsule,
          ),
        ),
      ],
    ),
  );
}
```

Add imports: `import '../../../core/icons/kivo_icons.dart';` (KivoIcon + KivoIcons). The `ladderSpeed` import via `gesture_math.dart` stays (used by `holdRightSpeedFor`).

#### 3b. `speed_panel.dart` — gold-active presets + accent readout

Match the dark+gold language: accent the readout, give the preset chips a clear gold "active" state (active = the chip value equals the current rate), keep the slider gold.

- [ ] **Step 2: Accent the readout**

Change the readout `Text('${rate.toStringAsFixed(2)}x', ...)` color from `Colors.white` to `KivoColors.gold`.

- [ ] **Step 3: Gold-active preset chips**

Replace the `Wrap(... ActionChip ...)` block with custom chips that highlight the active preset:

```dart
Wrap(
  spacing: 8,
  runSpacing: 8,
  children: [
    for (final p in st.speedPresets)
      GestureDetector(
        onTap: () => ctrl.setRate(p),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: (p - rate).abs() < 0.001
                ? KivoColors.gold.withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: 0.06),
            border: Border.all(
              color: (p - rate).abs() < 0.001 ? KivoColors.gold : Colors.white24,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('${p}x',
              style: TextStyle(
                color: (p - rate).abs() < 0.001 ? KivoColors.gold : Colors.white70,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              )),
        ),
      ),
  ],
),
```

Leave the `+`/`-` `IconButton`s, the `Slider` (already `activeColor: KivoColors.gold`), and the `↺ Normal (1.0x)` `TextButton` functionally unchanged.

- [ ] **Step 4: Analyze + test + commit**

`flutter analyze` clean; `flutter test` 59/59 (no test touches these overlays — verify). Commit: `feat: speed gesture segmented meter; gold-active speed presets`.

---

## After all tasks

1. `flutter test` green, `flutter analyze` clean.
2. Final whole-branch review (opus) over the cohesion range.
3. Release build to the Pixel 6 for on-device visual verification of all four (the device is the real judge per the user's flow).
