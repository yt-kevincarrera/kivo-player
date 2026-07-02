# Kivo H3/3c — A-B Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A-B segment loop — cycling pill chip (mark A → mark B → loop → off), gold range overlay on the seek bar, ±1s floating adjust popover, second entry in the "Más opciones" menu.

**Architecture:** A UI-independent `AbLoopNotifier` (Riverpod `Notifier<AbLoopState?>`) tracks phase (armedA/armedB/active) and the A/B marks, jumps to A when playback crosses B (direct `engine.seek`, bypassing the controller), and cancels on out-of-range user seeks (notified from `PlayerController.seekTo`) or video changes. Three UI pieces derive from it: the pill chip + popover (mounted in `ControlsOverlay`), the seek-bar range layer, and the menu row.

**Tech Stack:** Flutter, Riverpod, existing `positionProvider`/`durationProvider` stream providers, `FakePlaybackEngine` test fakes.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-02-kivo-h3-3c-ab-loop-design.md` — authoritative.
- Chip cycle: `begin()` (from menu) → `armedA`; `mark()` fixes A → `armedB`; `mark()` fixes B and starts the loop → `active`; `mark()` in `active` = cancel (chip disappears; re-entry only via menu).
- B marked earlier than A → swap. Minimum gap 1 second: a B mark closer than 1s to A is IGNORED (stay in `armedB`).
- Loop jump: position ≥ B → `engine.seek(A)` DIRECTLY on `playbackEngineProvider` — never through `PlayerController.seekTo` (that path is reserved for user seeks).
- User seek (any path through `PlayerController.seekTo`: seek bar, double-tap skip, gestures) with `active` loop and target outside `[A−1s, B+1s]` → cancel silently. In `armedA`/`armedB` seeks never cancel.
- Video change (`currentVideoProvider` changes) → cancel. NO persistence of any kind (no settings fields).
- Nudge (±1s from popover): clamps `0 ≤ A ≤ B−1s` and `A+1s ≤ B ≤ duration` (duration clamp only when known); after nudging, seek so the user can verify: nudgeA seeks to the new A; nudgeB seeks to `max(A, B − 2s)` (seeking exactly to B would instantly trigger the loop jump).
- Spanish copy exactly: menu row "Bucle A-B" / subtitle idle "Repetir un fragmento del video" / armed "Marcando…" / active "Activo · MM:SS–MM:SS"; chip labels "Marcar A", "Marcar B" (+ sub "A MM:SS"), active shows "MM:SS–MM:SS"; popover buttons "−1s"/"+1s".
- Visual language: chip = dark pill `Colors.black.withValues(alpha: 0.55)` radius 100, gold border/tint when active; popover = `rgba(10,14,26,0.92)`-style dark card radius 14; range band = gold `withValues(alpha: 0.28)`, markers 2.5px gold with "A"/"B" labels.
- No changes to `PlaybackEngine`, no changes to `KivoSettings`.
- `flutter analyze` clean and full `flutter test` green before every commit. Current suite: 194 tests.
- Do NOT build the APK mid-plan — one build at the very end (after final review) per the standing build-after-each-module rule.

---

### Task 1: AbLoopNotifier core + PlayerController hook

**Files:**
- Create: `lib/player/loop/ab_loop.dart`
- Modify: `lib/player/control/player_controller.dart` (seekTo notifies the loop)
- Test: `test/player/loop/ab_loop_test.dart`

**Interfaces:**
- Consumes: `positionProvider`/`durationProvider` (`StreamProvider<Duration>`, `lib/player/engine/playback_provider.dart`); `currentVideoProvider` (`lib/player/open/video_source.dart`); `playbackEngineProvider`.
- Produces (Tasks 2–3 rely on these exact names):
  - `enum AbLoopPhase { armedA, armedB, active }`
  - `class AbLoopState { final AbLoopPhase phase; final Duration? a; final Duration? b; const AbLoopState({required this.phase, this.a, this.b}); }`
  - `final abLoopProvider = NotifierProvider<AbLoopNotifier, AbLoopState?>(AbLoopNotifier.new);`
  - `AbLoopNotifier` methods: `void begin()`, `void mark()`, `void cancel()`, `void userSeeked(Duration target)`, `void nudgeA(int seconds)`, `void nudgeB(int seconds)`.

- [ ] **Step 1: Write the failing tests**

Create `test/player/loop/ab_loop_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/control/player_controller.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/loop/ab_loop.dart';
import 'package:kivo_player/player/open/video_source.dart';
import '../../fakes/fakes.dart';

void main() {
  late FakePlaybackEngine engine;
  late ProviderContainer c;

  Future<void> setUpContainer() async {
    engine = FakePlaybackEngine();
    final s = await SettingsService.load(InMemorySettingsStore());
    c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      // No deviceControlsProvider override needed: PlayerController.seekTo
      // only touches abLoop + engine; nothing in these tests reads it.
    ]);
    addTearDown(c.dispose);
    addTearDown(engine.dispose);
    c.listen(abLoopProvider, (_, __) {});
  }

  // Two microtask turns: StreamController delivery + StreamProvider hop.
  Future<void> pump() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> at(Duration pos) async {
    engine.emitPosition(pos);
    await pump();
  }

  test('begin → armedA; mark fixes A → armedB; mark fixes B → active', () async {
    await setUpContainer();
    final n = c.read(abLoopProvider.notifier);
    n.begin();
    expect(c.read(abLoopProvider)!.phase, AbLoopPhase.armedA);
    await at(const Duration(seconds: 60));
    n.mark();
    var st = c.read(abLoopProvider)!;
    expect(st.phase, AbLoopPhase.armedB);
    expect(st.a, const Duration(seconds: 60));
    await at(const Duration(seconds: 90));
    n.mark();
    st = c.read(abLoopProvider)!;
    expect(st.phase, AbLoopPhase.active);
    expect(st.a, const Duration(seconds: 60));
    expect(st.b, const Duration(seconds: 90));
  });

  test('marking B before A swaps them', () async {
    await setUpContainer();
    final n = c.read(abLoopProvider.notifier);
    n.begin();
    await at(const Duration(seconds: 90));
    n.mark();
    await at(const Duration(seconds: 60));
    n.mark();
    final st = c.read(abLoopProvider)!;
    expect(st.phase, AbLoopPhase.active);
    expect(st.a, const Duration(seconds: 60));
    expect(st.b, const Duration(seconds: 90));
  });

  test('a B mark closer than 1s to A is ignored', () async {
    await setUpContainer();
    final n = c.read(abLoopProvider.notifier);
    n.begin();
    await at(const Duration(seconds: 60));
    n.mark();
    await at(const Duration(seconds: 60, milliseconds: 400));
    n.mark();
    expect(c.read(abLoopProvider)!.phase, AbLoopPhase.armedB); // still waiting for B
  });

  test('mark in active phase cancels the loop', () async {
    await setUpContainer();
    final n = c.read(abLoopProvider.notifier);
    n.begin();
    await at(const Duration(seconds: 60));
    n.mark();
    await at(const Duration(seconds: 90));
    n.mark();
    n.mark();
    expect(c.read(abLoopProvider), isNull);
  });

  test('reaching B jumps back to A via a direct engine seek', () async {
    await setUpContainer();
    final n = c.read(abLoopProvider.notifier);
    n.begin();
    await at(const Duration(seconds: 60));
    n.mark();
    await at(const Duration(seconds: 90));
    n.mark();
    engine.lastSeek = null;
    await at(const Duration(seconds: 91));
    expect(engine.lastSeek, const Duration(seconds: 60));
    expect(c.read(abLoopProvider)!.phase, AbLoopPhase.active); // still looping
  });

  test('userSeeked outside the range cancels; inside does not', () async {
    await setUpContainer();
    final n = c.read(abLoopProvider.notifier);
    n.begin();
    await at(const Duration(seconds: 60));
    n.mark();
    await at(const Duration(seconds: 90));
    n.mark();
    n.userSeeked(const Duration(seconds: 75)); // inside
    expect(c.read(abLoopProvider), isNotNull);
    n.userSeeked(const Duration(seconds: 89, milliseconds: 500)); // within B+1s tolerance edge (inside)
    expect(c.read(abLoopProvider), isNotNull);
    n.userSeeked(const Duration(seconds: 120)); // outside
    expect(c.read(abLoopProvider), isNull);
  });

  test('userSeeked never cancels in armed phases', () async {
    await setUpContainer();
    final n = c.read(abLoopProvider.notifier);
    n.begin();
    n.userSeeked(const Duration(minutes: 10));
    expect(c.read(abLoopProvider), isNotNull);
    await at(const Duration(seconds: 60));
    n.mark();
    n.userSeeked(const Duration(minutes: 20));
    expect(c.read(abLoopProvider)!.phase, AbLoopPhase.armedB);
  });

  test('PlayerController.seekTo notifies the loop (out-of-range seek cancels)', () async {
    await setUpContainer();
    final n = c.read(abLoopProvider.notifier);
    n.begin();
    await at(const Duration(seconds: 60));
    n.mark();
    await at(const Duration(seconds: 90));
    n.mark();
    c.read(playerControllerProvider).seekTo(const Duration(minutes: 10));
    expect(c.read(abLoopProvider), isNull);
  });

  test('changing video cancels the loop', () async {
    await setUpContainer();
    final n = c.read(abLoopProvider.notifier);
    n.begin();
    await at(const Duration(seconds: 60));
    n.mark();
    await at(const Duration(seconds: 90));
    n.mark();
    c.read(currentVideoProvider.notifier).open(
      const VideoSession(playbackPath: '/v/ep2.mkv', displayName: 'ep2.mkv', queue: ['/v/ep2.mkv'], index: 0),
    );
    await pump();
    expect(c.read(abLoopProvider), isNull);
  });

  test('nudges clamp and seek to the verification point', () async {
    await setUpContainer();
    final n = c.read(abLoopProvider.notifier);
    engine.emitDuration(const Duration(seconds: 100));
    n.begin();
    await at(const Duration(seconds: 60));
    n.mark();
    await at(const Duration(seconds: 90));
    n.mark();

    n.nudgeA(-1); // 59
    var st = c.read(abLoopProvider)!;
    expect(st.a, const Duration(seconds: 59));
    expect(engine.lastSeek, const Duration(seconds: 59)); // verify jump to A

    n.nudgeB(1); // 91
    st = c.read(abLoopProvider)!;
    expect(st.b, const Duration(seconds: 91));
    expect(engine.lastSeek, const Duration(seconds: 89)); // B − 2s run-up

    // Clamp: A can't cross B−1s.
    for (var i = 0; i < 60; i++) {
      n.nudgeA(1);
    }
    st = c.read(abLoopProvider)!;
    expect(st.a, const Duration(seconds: 90)); // B(91s) − 1s

    // Clamp: B can't exceed duration.
    for (var i = 0; i < 30; i++) {
      n.nudgeB(1);
    }
    expect(c.read(abLoopProvider)!.b, const Duration(seconds: 100));
  });
}
```


- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/player/loop/ab_loop_test.dart`
Expected: FAIL — `ab_loop.dart` doesn't exist.

- [ ] **Step 3: Implement `lib/player/loop/ab_loop.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../engine/playback_provider.dart';
import '../open/video_source.dart';

enum AbLoopPhase { armedA, armedB, active }

/// Immutable A-B loop snapshot. `null` provider state = no loop. [a] is set
/// from [AbLoopPhase.armedB] on; [a] and [b] are both set in
/// [AbLoopPhase.active].
class AbLoopState {
  final AbLoopPhase phase;
  final Duration? a;
  final Duration? b;
  const AbLoopState({required this.phase, this.a, this.b});
}

final abLoopProvider =
    NotifierProvider<AbLoopNotifier, AbLoopState?>(AbLoopNotifier.new);

class AbLoopNotifier extends Notifier<AbLoopState?> {
  static const minGap = Duration(seconds: 1);
  static const seekTolerance = Duration(seconds: 1);

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  AbLoopState? build() {
    ref.listen(positionProvider, (_, next) {
      final pos = next.value;
      if (pos == null) return;
      _position = pos;
      final s = state;
      if (s != null && s.phase == AbLoopPhase.active && pos >= s.b!) {
        // The loop's own jump goes straight to the engine — user seeks go
        // through PlayerController.seekTo, which is the cancel path.
        ref.read(playbackEngineProvider).seek(s.a!);
      }
    });
    ref.listen(durationProvider, (_, next) {
      _duration = next.value ?? Duration.zero;
    });
    ref.listen(currentVideoProvider, (prev, next) {
      // The loop is a tool of the moment: it dies with its video.
      if (state != null && prev != next) state = null;
    });
    return null;
  }

  void begin() => state = const AbLoopState(phase: AbLoopPhase.armedA);

  void mark() {
    final s = state;
    if (s == null) return;
    switch (s.phase) {
      case AbLoopPhase.armedA:
        state = AbLoopState(phase: AbLoopPhase.armedB, a: _position);
      case AbLoopPhase.armedB:
        var a = s.a!;
        var b = _position;
        if (b < a) (a, b) = (b, a);
        if (b - a < minGap) return; // too tight — ignore this mark
        state = AbLoopState(phase: AbLoopPhase.active, a: a, b: b);
      case AbLoopPhase.active:
        cancel();
    }
  }

  void cancel() => state = null;

  /// Called from PlayerController.seekTo for every user-initiated seek.
  void userSeeked(Duration target) {
    final s = state;
    if (s == null || s.phase != AbLoopPhase.active) return;
    if (target < s.a! - seekTolerance || target > s.b! + seekTolerance) {
      cancel();
    }
  }

  void nudgeA(int seconds) {
    final s = state;
    if (s == null || s.phase != AbLoopPhase.active) return;
    var a = s.a! + Duration(seconds: seconds);
    final maxA = s.b! - minGap;
    if (a < Duration.zero) a = Duration.zero;
    if (a > maxA) a = maxA;
    state = AbLoopState(phase: AbLoopPhase.active, a: a, b: s.b);
    ref.read(playbackEngineProvider).seek(a); // hear the new start point
  }

  void nudgeB(int seconds) {
    final s = state;
    if (s == null || s.phase != AbLoopPhase.active) return;
    var b = s.b! + Duration(seconds: seconds);
    final minB = s.a! + minGap;
    if (b < minB) b = minB;
    if (_duration > Duration.zero && b > _duration) b = _duration;
    state = AbLoopState(phase: AbLoopPhase.active, a: s.a, b: b);
    // Seeking exactly to B would instantly trigger the jump — land 2s before
    // it (clamped to A) so the user hears the run-up into the loop point.
    var verify = b - const Duration(seconds: 2);
    if (verify < s.a!) verify = s.a!;
    ref.read(playbackEngineProvider).seek(verify);
  }
}
```

- [ ] **Step 4: Hook `PlayerController.seekTo`**

In `lib/player/control/player_controller.dart`, add the import `import '../loop/ab_loop.dart';` and change:

```dart
  void seekTo(Duration p) => _ref.read(playbackEngineProvider).seek(p);
```

to:

```dart
  void seekTo(Duration p) {
    // A user seek outside the active A-B range dissolves the loop — every
    // user-initiated seek funnels through here (seek bar, skips, gestures).
    _ref.read(abLoopProvider.notifier).userSeeked(p);
    _ref.read(playbackEngineProvider).seek(p);
  }
```

- [ ] **Step 5: Run tests, analyze, full suite**

Run: `flutter test test/player/loop/ab_loop_test.dart` → PASS (10 tests).
Run: `flutter analyze` → clean. Run: `flutter test` → 204 passing (194 + 10).

- [ ] **Step 6: Commit**

```bash
git add lib/player/loop/ab_loop.dart lib/player/control/player_controller.dart test/player/loop/ab_loop_test.dart
git commit -m "feat: A-B loop core — cycling marks, jump at B, seek-outside cancels"
```

---

### Task 2: Seek-bar range layer + menu entry

**Files:**
- Create: `lib/ui/player/loop/ab_range_layer.dart`
- Modify: `lib/ui/player/controls/seek_bar.dart` (stack the layer under the Slider)
- Modify: `lib/ui/player/more/more_menu.dart` (second row "Bucle A-B")
- Test: `test/ui/player/loop/ab_range_layer_test.dart`

**Interfaces:**
- Consumes: `abLoopProvider`, `AbLoopState`/`AbLoopPhase`, notifier `.begin()/.cancel()` (Task 1); `durationProvider`; `fmtDuration` (`lib/core/format.dart`); `controlsVisibleProvider` (`lib/ui/player/state/controls_visibility.dart`, notifier method `.show()`).
- Produces: `class AbRangeLayer extends ConsumerWidget` with `const AbRangeLayer({super.key})` — paints band+markers; keyed `const ValueKey('ab-range-paint')` on its CustomPaint (Task 2's own test and any later test finds it by that key).

- [ ] **Step 1: Create `lib/ui/player/loop/ab_range_layer.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../player/engine/playback_provider.dart';
import '../../../player/loop/ab_loop.dart';

/// Gold A-B range band + markers painted behind the seek bar's Slider.
/// Purely decorative: IgnorePointer so the Slider's gestures are untouched.
class AbRangeLayer extends ConsumerWidget {
  const AbRangeLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loop = ref.watch(abLoopProvider);
    final total = ref.watch(durationProvider).value ?? Duration.zero;
    if (loop == null || loop.a == null || total == Duration.zero) {
      return const SizedBox.shrink();
    }
    final totalMs = total.inMilliseconds.toDouble();
    final aFrac = (loop.a!.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final bFrac =
        loop.b == null ? null : (loop.b!.inMilliseconds / totalMs).clamp(0.0, 1.0);
    return IgnorePointer(
      child: CustomPaint(
        key: const ValueKey('ab-range-paint'),
        painter: _AbRangePainter(aFrac: aFrac, bFrac: bFrac, color: KivoColors.gold),
        size: Size.infinite,
      ),
    );
  }
}

class _AbRangePainter extends CustomPainter {
  final double aFrac;
  final double? bFrac;
  final Color color;
  // Matches the Slider's effective horizontal track inset (thumb radius).
  static const _inset = 11.0;
  const _AbRangePainter({required this.aFrac, required this.bFrac, required this.color});

  double _x(Size size, double frac) => _inset + frac * (size.width - 2 * _inset);

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final xa = _x(size, aFrac);
    if (bFrac != null) {
      final xb = _x(size, bFrac!);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(xa, cy - 4, xb, cy + 4),
          const Radius.circular(3),
        ),
        Paint()..color = color.withValues(alpha: 0.28),
      );
    }
    _marker(canvas, xa, cy, 'A');
    if (bFrac != null) _marker(canvas, _x(size, bFrac!), cy, 'B');
  }

  void _marker(Canvas canvas, double x, double cy, String label) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, cy), width: 2.5, height: 14),
        const Radius.circular(2),
      ),
      Paint()..color = color,
    );
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(color: color, fontSize: 7.5, fontWeight: FontWeight.w800),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x - tp.width / 2, cy - 7 - tp.height - 1));
  }

  @override
  bool shouldRepaint(_AbRangePainter old) =>
      old.aFrac != aFrac || old.bFrac != bFrac || old.color != color;
}
```

- [ ] **Step 2: Stack it in `lib/ui/player/controls/seek_bar.dart`**

Add the import `import '../loop/ab_range_layer.dart';` and wrap the existing `Expanded` child (the `AnimatedBuilder` with the `SliderTheme`/`Slider`) in a Stack:

```dart
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Positioned.fill(child: AbRangeLayer()),
              AnimatedBuilder(
                // ... the existing AnimatedBuilder subtree, UNCHANGED ...
              ),
            ],
          ),
        ),
```

Nothing else in the file changes — the layer sits behind the Slider and ignores pointers.

- [ ] **Step 3: Add the menu row in `lib/ui/player/more/more_menu.dart`**

The current sheet builder is not a Consumer, and the new row needs to watch loop state. Wrap the `Column` in a `Consumer` and add the second `_MenuRow`. Replace the `builder: (sheetContext) => SafeArea(...)` body so the children read:

```dart
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Consumer(
          builder: (context, sheetRef, _) {
            final loop = sheetRef.watch(abLoopProvider);
            final loopSubtitle = switch (loop?.phase) {
              null => 'Repetir un fragmento del video',
              AbLoopPhase.armedA || AbLoopPhase.armedB => 'Marcando…',
              AbLoopPhase.active =>
                'Activo · ${fmtDuration(loop!.a!)}–${fmtDuration(loop.b!)}',
            };
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                _MenuRow(
                  icon: Icons.bedtime_outlined,
                  title: 'Temporizador de apagado',
                  subtitle: 'Detener la reproducción automáticamente',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    showSleepTimerPanel(context, ref,
                        onBack: () => showMoreMenu(context, ref));
                  },
                ),
                const SizedBox(height: 8),
                _MenuRow(
                  icon: Icons.repeat_rounded,
                  title: 'Bucle A-B',
                  subtitle: loopSubtitle,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    if (loop == null) {
                      ref.read(abLoopProvider.notifier).begin();
                      // Chip lives in the controls overlay — make sure it's visible.
                      ref.read(controlsVisibleProvider.notifier).show();
                    } else {
                      ref.read(abLoopProvider.notifier).cancel();
                    }
                  },
                ),
              ],
            );
          },
        ),
      ),
    ),
```

Add imports: `import '../../../core/format.dart';`, `import '../../../player/loop/ab_loop.dart';`, `import '../state/controls_visibility.dart';`. Note the outer `ref` (the `showMoreMenu` parameter) is still used for actions — the inner `sheetRef` only powers the `watch` so the subtitle updates live while the sheet is open.

- [ ] **Step 4: Write the tests**

Create `test/ui/player/loop/ab_range_layer_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/loop/ab_loop.dart';
import 'package:kivo_player/ui/player/loop/ab_range_layer.dart';
import 'package:kivo_player/ui/player/more/more_menu.dart';
import '../../../fakes/fakes.dart';

Future<(ProviderContainer, FakePlaybackEngine)> _setUp(WidgetTester tester, Widget child) async {
  final engine = FakePlaybackEngine();
  addTearDown(engine.dispose);
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    playbackEngineProvider.overrideWithValue(engine),
  ]);
  addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(home: Scaffold(body: child)),
  ));
  await tester.pump();
  return (c, engine);
}

Future<void> _makeActiveLoop(WidgetTester tester, ProviderContainer c, FakePlaybackEngine engine) async {
  engine.emitDuration(const Duration(minutes: 10));
  c.read(abLoopProvider.notifier).begin();
  engine.emitPosition(const Duration(minutes: 2));
  await tester.pump();
  c.read(abLoopProvider.notifier).mark();
  engine.emitPosition(const Duration(minutes: 3));
  await tester.pump();
  c.read(abLoopProvider.notifier).mark();
  await tester.pump();
}

void main() {
  testWidgets('paints nothing without a loop, paints the range when active', (tester) async {
    final (c, engine) = await _setUp(tester, const SizedBox(width: 300, height: 48, child: AbRangeLayer()));
    expect(find.byKey(const ValueKey('ab-range-paint')), findsNothing);
    await _makeActiveLoop(tester, c, engine);
    expect(find.byKey(const ValueKey('ab-range-paint')), findsOneWidget);
  });

  testWidgets('menu row begins marking when no loop exists', (tester) async {
    final (c, _) = await _setUp(
      tester,
      Consumer(builder: (context, ref, _) => ElevatedButton(
        onPressed: () => showMoreMenu(context, ref),
        child: const Text('open'),
      )),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Bucle A-B'), findsOneWidget);
    expect(find.text('Repetir un fragmento del video'), findsOneWidget);
    await tester.tap(find.text('Bucle A-B'));
    await tester.pumpAndSettle();
    expect(c.read(abLoopProvider)!.phase, AbLoopPhase.armedA);
  });

  testWidgets('menu row shows the active range and cancels on tap', (tester) async {
    late ProviderContainer c;
    late FakePlaybackEngine engine;
    (c, engine) = await _setUp(
      tester,
      Consumer(builder: (context, ref, _) => ElevatedButton(
        onPressed: () => showMoreMenu(context, ref),
        child: const Text('open'),
      )),
    );
    await _makeActiveLoop(tester, c, engine);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Activo · 2:00–3:00'), findsOneWidget);
    await tester.tap(find.text('Bucle A-B'));
    await tester.pumpAndSettle();
    expect(c.read(abLoopProvider), isNull);
  });
}
```

NOTE for the implementer: the `Activo · 2:00–3:00` expectation assumes `fmtDuration(Duration(minutes: 2))` renders `2:00` — read `lib/core/format.dart` first and adjust the expected string to the real format if it differs (e.g. `02:00`).

- [ ] **Step 5: Run tests, analyze, full suite**

Run: `flutter test test/ui/player/loop/ab_range_layer_test.dart` → PASS (3 tests).
Run: `flutter analyze` → clean. Run: `flutter test` → 207 passing (204 + 3).

- [ ] **Step 6: Commit**

```bash
git add lib/ui/player/loop/ab_range_layer.dart lib/ui/player/controls/seek_bar.dart lib/ui/player/more/more_menu.dart test/ui/player/loop/ab_range_layer_test.dart
git commit -m "feat: A-B range on the seek bar + Bucle A-B menu entry"
```

---

### Task 3: Pill chip + adjust popover, mounted in ControlsOverlay

**Files:**
- Create: `lib/ui/player/loop/ab_loop_chip.dart`
- Modify: `lib/ui/player/controls/controls_overlay.dart` (mount the chip)
- Test: `test/ui/player/loop/ab_loop_chip_test.dart`

**Interfaces:**
- Consumes: `abLoopProvider`/`AbLoopPhase`, notifier `.mark()/.nudgeA()/.nudgeB()` (Task 1); `fmtDuration`; `KivoColors.gold`.
- Produces: `class AbLoopChip extends ConsumerStatefulWidget` — renders `SizedBox.shrink()` when no loop; pill chip otherwise; long-press in `active` opens the ±1s popover.

- [ ] **Step 1: Create `lib/ui/player/loop/ab_loop_chip.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/format.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../player/loop/ab_loop.dart';

/// Floating pill: tap cycles mark A → mark B → loop on → off. Long-press
/// while the loop runs opens the ±1s adjust popover (video stays visible —
/// every nudge seeks to the adjusted point so it can be verified live).
class AbLoopChip extends ConsumerStatefulWidget {
  const AbLoopChip({super.key});
  @override
  ConsumerState<AbLoopChip> createState() => _AbLoopChipState();
}

class _AbLoopChipState extends ConsumerState<AbLoopChip> {
  bool _popoverOpen = false;

  @override
  Widget build(BuildContext context) {
    final loop = ref.watch(abLoopProvider);
    if (loop == null) {
      if (_popoverOpen) _popoverOpen = false;
      return const SizedBox.shrink();
    }
    final n = ref.read(abLoopProvider.notifier);
    final active = loop.phase == AbLoopPhase.active;

    return TapRegion(
      onTapOutside: (_) {
        if (_popoverOpen) setState(() => _popoverOpen = false);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_popoverOpen && active) ...[
            _AdjustPopover(
              a: loop.a!,
              b: loop.b!,
              onNudgeA: n.nudgeA,
              onNudgeB: n.nudgeB,
            ),
            const SizedBox(height: 8),
          ],
          GestureDetector(
            onTap: () {
              if (_popoverOpen) {
                setState(() => _popoverOpen = false);
                return;
              }
              n.mark();
            },
            onLongPress: active ? () => setState(() => _popoverOpen = true) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: active ? KivoColors.gold.withValues(alpha: 0.16) : Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: active
                      ? KivoColors.gold
                      : KivoColors.gold.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.repeat_rounded,
                      size: 13, color: active ? KivoColors.gold : Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    switch (loop.phase) {
                      AbLoopPhase.armedA => 'Marcar A',
                      AbLoopPhase.armedB => 'Marcar B',
                      AbLoopPhase.active =>
                        '${fmtDuration(loop.a!)}–${fmtDuration(loop.b!)}',
                    },
                    style: TextStyle(
                      color: active ? KivoColors.gold : Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (loop.phase == AbLoopPhase.armedB) ...[
                    const SizedBox(width: 6),
                    Text(
                      'A ${fmtDuration(loop.a!)}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.42),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdjustPopover extends StatelessWidget {
  final Duration a;
  final Duration b;
  final void Function(int seconds) onNudgeA;
  final void Function(int seconds) onNudgeB;
  const _AdjustPopover({
    required this.a,
    required this.b,
    required this.onNudgeA,
    required this.onNudgeB,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 230,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xEB0A0E1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _row('A', a, onNudgeA),
          const SizedBox(height: 6),
          _row('B', b, onNudgeB),
        ],
      ),
    );
  }

  Widget _row(String label, Duration ts, void Function(int) onNudge) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: KivoColors.gold.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(7),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: const TextStyle(
                  color: KivoColors.gold, fontSize: 10, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 8),
        _StepBtn(label: '−1s', onTap: () => onNudge(-1)),
        Expanded(
          child: Text(
            fmtDuration(ts),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: KivoColors.gold,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        _StepBtn(label: '+1s', onTap: () => onNudge(1)),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _StepBtn({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
        ),
      );
}
```

(`FontFeature` is re-exported by material; add `import 'dart:ui' show FontFeature;` only if the analyzer complains. Note `_AdjustPopover`/`_StepBtn` reference `KivoColors` and `fmtDuration` from the same file's imports.)

- [ ] **Step 2: Mount in `lib/ui/player/controls/controls_overlay.dart`**

Add the import `import '../loop/ab_loop_chip.dart';` and, inside the inner (unlocked) `Stack` children — right after the bottom-bar `Positioned` — add:

```dart
                    const Positioned(
                      right: 14,
                      bottom: 116, // clear of the seek bar + button row
                      child: AbLoopChip(),
                    ),
```

Nothing else changes; the chip inherits the overlay's AnimatedOpacity/IgnorePointer show-hide behavior automatically.

- [ ] **Step 3: Write the widget tests**

Create `test/ui/player/loop/ab_loop_chip_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/loop/ab_loop.dart';
import 'package:kivo_player/ui/player/loop/ab_loop_chip.dart';
import '../../../fakes/fakes.dart';

void main() {
  late FakePlaybackEngine engine;
  late ProviderContainer c;

  Future<void> pumpChip(WidgetTester tester) async {
    engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(
        home: Scaffold(body: Align(alignment: Alignment.bottomRight, child: AbLoopChip())),
      ),
    ));
    await tester.pump();
  }

  testWidgets('hidden without loop; cycles Marcar A → Marcar B → range on taps', (tester) async {
    await pumpChip(tester);
    expect(find.text('Marcar A'), findsNothing);

    c.read(abLoopProvider.notifier).begin();
    engine.emitDuration(const Duration(minutes: 10));
    engine.emitPosition(const Duration(minutes: 2));
    await tester.pump();
    expect(find.text('Marcar A'), findsOneWidget);

    await tester.tap(find.text('Marcar A'));
    await tester.pump();
    expect(find.text('Marcar B'), findsOneWidget);

    engine.emitPosition(const Duration(minutes: 3));
    await tester.pump();
    await tester.tap(find.text('Marcar B'));
    await tester.pump();
    expect(find.textContaining('–'), findsOneWidget); // "2:00–3:00"

    // Tap once more: loop off, chip gone.
    await tester.tap(find.textContaining('–'));
    await tester.pump();
    expect(c.read(abLoopProvider), isNull);
    expect(find.text('Marcar A'), findsNothing);
    expect(find.textContaining('–'), findsNothing);
  });

  testWidgets('long-press opens the popover and nudges adjust + seek', (tester) async {
    await pumpChip(tester);
    c.read(abLoopProvider.notifier).begin();
    engine.emitDuration(const Duration(minutes: 10));
    engine.emitPosition(const Duration(minutes: 2));
    await tester.pump();
    c.read(abLoopProvider.notifier).mark();
    engine.emitPosition(const Duration(minutes: 3));
    await tester.pump();
    c.read(abLoopProvider.notifier).mark();
    await tester.pump();

    await tester.longPress(find.textContaining('–'));
    await tester.pump();
    expect(find.text('−1s'), findsNWidgets(2));
    expect(find.text('+1s'), findsNWidgets(2));

    engine.lastSeek = null;
    // First "−1s" is A's.
    await tester.tap(find.text('−1s').first);
    await tester.pump();
    expect(c.read(abLoopProvider)!.a, const Duration(minutes: 1, seconds: 59));
    expect(engine.lastSeek, const Duration(minutes: 1, seconds: 59));
  });

  testWidgets('tapping the chip while the popover is open only closes the popover', (tester) async {
    await pumpChip(tester);
    c.read(abLoopProvider.notifier).begin();
    engine.emitDuration(const Duration(minutes: 10));
    engine.emitPosition(const Duration(minutes: 2));
    await tester.pump();
    c.read(abLoopProvider.notifier).mark();
    engine.emitPosition(const Duration(minutes: 3));
    await tester.pump();
    c.read(abLoopProvider.notifier).mark();
    await tester.pump();

    await tester.longPress(find.textContaining('–'));
    await tester.pump();
    expect(find.text('−1s'), findsNWidgets(2));
    await tester.tap(find.textContaining('–'));
    await tester.pump();
    expect(find.text('−1s'), findsNothing); // popover closed…
    expect(c.read(abLoopProvider), isNotNull); // …loop still on
  });
}
```


- [ ] **Step 4: Run tests, analyze, full suite**

Run: `flutter test test/ui/player/loop/ab_loop_chip_test.dart` → PASS (3 tests).
Run: `flutter analyze` → clean. Run: `flutter test` → 210 passing (207 + 3).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/player/loop/ab_loop_chip.dart lib/ui/player/controls/controls_overlay.dart test/ui/player/loop/ab_loop_chip_test.dart
git commit -m "feat: A-B loop pill chip with ±1s adjust popover"
```

---

## After all tasks

1. Whole-branch review (opus model) over the 3c range with extra scrutiny on: the userSeeked cancel path vs the loop's own engine.seek jumps (no self-cancel); the position-listener jump not fighting the pendingSeek/scrub logic in seek_bar.dart; the chip's TapRegion/popover state not leaking when the loop dies externally (video change while popover open); and the painter's inset approximation vs the real Slider geometry.
2. Fix Critical/Important findings; record Minors in the ledger.
3. Build + install per the standing rule (`flutter build apk --release` + `adb install -r` + `am start` — NOT `flutter run`), then report the device checklist from spec §4.
