# Kivo player zoom & configurable minimize playback — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add pinch-to-zoom with panning, a persistent zoom chip, and a user setting that decides whether minimizing the player pauses playback or keeps it running.

**Architecture:** `GestureDetector` throws when scale callbacks sit alongside both drag axes, so `PlayerGestures` moves its six drag handlers onto a single `onScale*` trio that dispatches by pointer count and dominant axis through one pure routing function. Zoom lives in a `ZoomNotifier` backed by pure math in `zoom_math.dart`, is painted by a local `Consumer` + `Transform` inside the video box, and is surfaced by a chip in its own overlay layer. The minimize behaviour becomes one cached boolean read at minimize time and consulted by `dispose()`.

**Tech Stack:** Flutter/Riverpod (`NotifierProvider`, `StateProvider`), `flutter_test`, the settings toolkit in `lib/ui/settings/widgets/setting_tiles.dart`, pure-math + test pattern of `lib/player/control/gesture_math.dart`.

**Spec:** `docs/superpowers/specs/2026-08-18-kivo-player-zoom-and-minimize-playback-design.md`

## Global Constraints

- **`flutter analyze` clean and the full `flutter test` suite green before every commit.** Never commit red.
- **Spanish user-facing copy.** Code, comments and test names in English.
- **Settings are immediate-apply:** every control does `ref.read(settingsProvider.notifier).set(s.copyWith(field: v))`. No local buffer.
- **Never call `ref.read` inside `State.dispose()`** — it throws and silently drops the work (this is what once broke resume-on-exit). Cache the notifier or service in a field during `initState`, and defer provider writes with `scheduleMicrotask` exactly as `player_screen.dart`'s `dispose()` already does for `_dismissApi`.
- **Do not add a `Co-Authored-By` trailer to commits.**
- **Do not build the APK mid-plan** — one release build to the Pixel 6 at the end.
- **Exact toolkit signatures** (match verbatim):
  - `SettingSwitch({required String title, String? subtitle, required bool value, required ValueChanged<bool> onChanged})`
  - `SettingSegmented<T>({required String title, String? subtitle, required List<(T, String)> options, required T value, required ValueChanged<T> onChanged})`
  - `SettingsCard({required List<Widget> children})`
- **`KivoSettings` is immutable with five parallel places per field:** the `final` declaration, the `required this.x` constructor param, the `KivoSettings.defaults()` value, the `copyWith` param + assignment, `toMap`, and `fromMap`. Missing one is the classic bug here — a field that silently resets on app restart.
- **Zoom scale floor is 1.0.** Zooming out below the natural frame is out of scope; `clampZoomOffset` must return `Offset.zero` whenever `scale <= 1`.

---

### Task 1: The five new settings fields

**Files:**
- Modify: `lib/core/settings/kivo_settings.dart` (declarations, constructor, `defaults()`, `copyWith`, `toMap`, `fromMap`)
- Test: `test/core/settings/kivo_settings_zoom_minimize_test.dart` (create)

**Interfaces:**
- Produces: `KivoSettings.pinchZoom` (`bool`, default `true`), `.zoomMax` (`double`, default `4.0`), `.zoomResetMode` (`String`, default `'exit'`, one of `'exit' | 'video' | 'never'`), `.zoomRemembered` (`double`, default `1.0`), `.minimizeKeepsPlaying` (`bool`, default `false`). Every later task consumes these.

- [ ] **Step 1: Write the failing test**

Create `test/core/settings/kivo_settings_zoom_minimize_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';

void main() {
  test('zoom and minimize fields have the documented defaults', () {
    final d = KivoSettings.defaults();
    expect(d.pinchZoom, true);
    expect(d.zoomMax, 4.0);
    expect(d.zoomResetMode, 'exit');
    expect(d.zoomRemembered, 1.0);
    expect(d.minimizeKeepsPlaying, false, reason: 'today\'s pause-on-minimize stays the default');
  });

  test('all five round-trip through toMap/fromMap', () {
    final changed = KivoSettings.defaults().copyWith(
      pinchZoom: false,
      zoomMax: 6.0,
      zoomResetMode: 'never',
      zoomRemembered: 2.5,
      minimizeKeepsPlaying: true,
    );
    final back = KivoSettings.fromMap(changed.toMap());
    expect(back.pinchZoom, false);
    expect(back.zoomMax, 6.0);
    expect(back.zoomResetMode, 'never');
    expect(back.zoomRemembered, 2.5);
    expect(back.minimizeKeepsPlaying, true);
  });

  test('a settings map written before these fields existed keeps working', () {
    final old = KivoSettings.defaults().toMap()
      ..remove('pinchZoom')
      ..remove('zoomMax')
      ..remove('zoomResetMode')
      ..remove('zoomRemembered')
      ..remove('minimizeKeepsPlaying');
    final back = KivoSettings.fromMap(old);
    expect(back.pinchZoom, true);
    expect(back.zoomMax, 4.0);
    expect(back.zoomResetMode, 'exit');
    expect(back.zoomRemembered, 1.0);
    expect(back.minimizeKeepsPlaying, false);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/settings/kivo_settings_zoom_minimize_test.dart`
Expected: FAIL — compile errors, `pinchZoom` isn't defined on `KivoSettings`.

- [ ] **Step 3: Add the fields**

In `lib/core/settings/kivo_settings.dart`, add to the `final` declaration block (next to the other gesture fields, after `hapticsOnGestures`):

```dart
  final bool pinchZoom;
  final double zoomMax;
  final String zoomResetMode;  // 'exit' | 'video' | 'never'
  final double zoomRemembered; // last pinch factor, only written in 'never' mode
  final bool minimizeKeepsPlaying;
```

Add to the constructor's required params:

```dart
    required this.pinchZoom,
    required this.zoomMax,
    required this.zoomResetMode,
    required this.zoomRemembered,
    required this.minimizeKeepsPlaying,
```

Add to `KivoSettings.defaults()`:

```dart
        pinchZoom: true,
        zoomMax: 4.0,
        zoomResetMode: 'exit',
        zoomRemembered: 1.0,
        minimizeKeepsPlaying: false,
```

Add to `copyWith`'s params and its body:

```dart
    bool? pinchZoom,
    double? zoomMax,
    String? zoomResetMode,
    double? zoomRemembered,
    bool? minimizeKeepsPlaying,
```

```dart
      pinchZoom: pinchZoom ?? this.pinchZoom,
      zoomMax: zoomMax ?? this.zoomMax,
      zoomResetMode: zoomResetMode ?? this.zoomResetMode,
      zoomRemembered: zoomRemembered ?? this.zoomRemembered,
      minimizeKeepsPlaying: minimizeKeepsPlaying ?? this.minimizeKeepsPlaying,
```

Add to `toMap`:

```dart
        'pinchZoom': pinchZoom,
        'zoomMax': zoomMax,
        'zoomResetMode': zoomResetMode,
        'zoomRemembered': zoomRemembered,
        'minimizeKeepsPlaying': minimizeKeepsPlaying,
```

Add to `fromMap` (note the `toDouble()` — JSON round-trips whole numbers as `int`, and `4` cast to `double` throws):

```dart
      pinchZoom: m['pinchZoom'] ?? d.pinchZoom,
      zoomMax: (m['zoomMax'] as num?)?.toDouble() ?? d.zoomMax,
      zoomResetMode: m['zoomResetMode'] ?? d.zoomResetMode,
      zoomRemembered: (m['zoomRemembered'] as num?)?.toDouble() ?? d.zoomRemembered,
      minimizeKeepsPlaying: m['minimizeKeepsPlaying'] ?? d.minimizeKeepsPlaying,
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/core/settings/`
Expected: PASS. Then `flutter analyze` clean and `flutter test` fully green.

- [ ] **Step 5: Commit**

```bash
git add lib/core/settings/kivo_settings.dart test/core/settings/kivo_settings_zoom_minimize_test.dart
git commit -m "feat(settings): fields for pinch zoom and minimize playback"
```

---

### Task 2: Minimizing can keep playing

**Files:**
- Modify: `lib/ui/player/player_screen.dart` (`_completeDismiss`, the `PopScope` fallback in `build`, `dispose`)
- Modify: `lib/ui/mini_player/mini_player_bar.dart` (the `Dismissible.onDismissed` and the close `IconButton`)
- Test: `test/ui/player/minimize_keeps_playing_test.dart` (create)

**Interfaces:**
- Consumes: `KivoSettings.minimizeKeepsPlaying` from Task 1.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Write the failing test**

Create `test/ui/player/minimize_keeps_playing_test.dart`. Model it on the container-and-overrides setup in `test/ui/player/player_gestures_test.dart`; assert against `FakePlaybackEngine` from `test/fakes/fakes.dart`. Read that fake first and use whatever it exposes to observe pause/play state (it backs `playingProvider`, so `container.read(playingProvider).value` is the assertion of record).

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/settings/settings_store.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/ui/mini_player/mini_player_bar.dart';
import 'package:kivo_player/ui/player/state/mini_player_state.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets('closing the mini-bar pauses the engine', (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
    ]);
    addTearDown(c.dispose);
    await tester.runAsync(() async {
      await engine.open('/video.mp4');
      await engine.play();
    });
    c.read(playerMinimizedProvider.notifier).state = true;

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: MiniPlayerBar())),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(engine.playing, false, reason: 'the mini-bar can no longer assume playback was already paused');
  });
}
```

If `FakePlaybackEngine` exposes no `playing` getter or no `open`, adapt to its real API rather than changing the fake — check `test/fakes/fakes.dart` first and use the same accessors the existing player tests use.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/player/minimize_keeps_playing_test.dart`
Expected: FAIL — the engine is still playing after the close tap.

- [ ] **Step 3: Make the mini-bar pause on close**

In `lib/ui/mini_player/mini_player_bar.dart`, both exits must stop playback before clearing the minimized flag. Replace the `Dismissible`'s callback:

```dart
            onDismissed: (_) {
              ref.read(playbackEngineProvider).pause();
              ref.read(playerMinimizedProvider.notifier).state = false;
            },
```

and the close button's:

```dart
                  IconButton(
                    icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                    onPressed: () {
                      ref.read(playbackEngineProvider).pause();
                      ref.read(playerMinimizedProvider.notifier).state = false;
                    },
                  ),
```

Add the `playback_provider.dart` import if it isn't there. Note the two callbacks live in different widgets (`_MiniPlayerBarState` and `_MiniPlayerContent`) — both have a `ref`.

- [ ] **Step 4: Gate the pause on minimize**

In `lib/ui/player/player_screen.dart`, add a field next to `_dismissing`:

```dart
  // Read ONCE at minimize time: dispose() must not touch `ref`.
  bool _keepPlayingOnMinimize = false;
```

In `_completeDismiss()`, decide before the animation and honour it after:

```dart
  void _completeDismiss() {
    if (_dismissing) return;
    _dismissing = true;
    _keepPlayingOnMinimize = ref.read(settingsProvider).minimizeKeepsPlaying;
    if (!_previewCaptured) _captureMiniPreview();
    _dismissCtl.value = ref.read(dismissProvider);
    _dismissCtl
        .animateTo(1.0, duration: Duration(milliseconds: dismissDurationMs(_dismissCtl.value)))
        .then((_) {
      if (!mounted) return;
      if (!_keepPlayingOnMinimize) _engine.pause();
      _saveProgress();
      ref.read(minimizedSessionKeyProvider.notifier).state = _resumeKey;
      ref.read(playerMinimizedProvider.notifier).state = true;
      Navigator.of(context).pop(); // unconditional pop — does not re-enter PopScope
    });
  }
```

In the `PopScope` fallback inside `build`, make the same read on its own path:

```dart
          _keepPlayingOnMinimize = ref.read(settingsProvider).minimizeKeepsPlaying;
          if (!_keepPlayingOnMinimize) _engine.pause();
          _saveProgress();
```

In `dispose()`, consult the cached field — never `ref`:

```dart
    _saveProgress(); // best-effort for in-app pop
    // Stop audio when leaving the player (the engine is a singleton) — unless
    // we are minimizing and the user asked playback to continue in the mini-bar.
    if (!_keepPlayingOnMinimize) _engine.pause();
```

- [ ] **Step 5: Extend the test to cover both settings**

Append to the same test file a case per setting value, driving the real minimize path. The simplest honest assertion at this layer is on the decision, not the animation: pump a `PlayerScreen` route is heavy, so instead assert `_keepPlayingOnMinimize`'s effect through the mini-bar contract already covered plus a settings round-trip. If pumping the full player proves impractical in the harness, state that in the commit message and keep the mini-bar test as the behavioural guard — do not fake a passing assertion.

```dart
  testWidgets('minimizeKeepsPlaying off still pauses on close', (tester) async {
    // Same body as above but with settings explicitly set to the default; the
    // mini-bar's close must pause regardless of the setting — the setting only
    // governs the minimize transition, not the close.
  });
```

Replace that comment with the actual copied body when writing the test — no placeholder bodies.

- [ ] **Step 6: Run the tests**

Run: `flutter test`
Expected: all green. Then `flutter analyze` clean.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/player/player_screen.dart lib/ui/mini_player/mini_player_bar.dart test/ui/player/minimize_keeps_playing_test.dart
git commit -m "feat(player): minimizing can keep playback running"
```

---

### Task 3: Zoom math

**Files:**
- Create: `lib/player/control/zoom_math.dart`
- Test: `test/player/control/zoom_math_test.dart` (create)

**Interfaces:**
- Produces: `clampZoomOffset(Offset offset, double scale, Size viewport) -> Offset` and `zoomAt({required double scale, required Offset offset, required double factor, required Offset focal, required Size viewport, required double max}) -> ({double scale, Offset offset})`. Tasks 4 and 6 consume both.

- [ ] **Step 1: Write the failing test**

Create `test/player/control/zoom_math_test.dart`:

```dart
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/control/zoom_math.dart';

void main() {
  const viewport = Size(400, 800);

  test('no zoom means no translation is possible', () {
    expect(clampZoomOffset(const Offset(50, 50), 1.0, viewport), Offset.zero);
    expect(clampZoomOffset(const Offset(50, 50), 0.5, viewport), Offset.zero);
  });

  test('translation is bounded by half the overflow on each axis', () {
    // scale 2 over a 400x800 viewport => limits are 200 and 400.
    expect(clampZoomOffset(const Offset(500, 900), 2.0, viewport), const Offset(200, 400));
    expect(clampZoomOffset(const Offset(-500, -900), 2.0, viewport), const Offset(-200, -400));
    // inside the bounds it passes through untouched
    expect(clampZoomOffset(const Offset(30, -40), 2.0, viewport), const Offset(30, -40));
  });

  test('zoomAt clamps the scale into [1, max]', () {
    final centre = Offset(viewport.width / 2, viewport.height / 2);
    final up = zoomAt(scale: 1.0, offset: Offset.zero, factor: 99, focal: centre, viewport: viewport, max: 4.0);
    expect(up.scale, 4.0);
    final down = zoomAt(scale: 2.0, offset: Offset.zero, factor: 0.01, focal: centre, viewport: viewport, max: 4.0);
    expect(down.scale, 1.0);
    expect(down.offset, Offset.zero, reason: 'falling back to 1x must recentre');
  });

  test('a pinch centred on the viewport centre introduces no translation', () {
    final centre = Offset(viewport.width / 2, viewport.height / 2);
    final r = zoomAt(scale: 1.0, offset: Offset.zero, factor: 2.0, focal: centre, viewport: viewport, max: 4.0);
    expect(r.scale, 2.0);
    expect(r.offset.dx, closeTo(0, 1e-9));
    expect(r.offset.dy, closeTo(0, 1e-9));
  });

  test('a pinch keeps its focal point anchored', () {
    // Focal 100px left of centre; doubling the scale must push content right by 100px
    // so the same pixel stays under the fingers (before clamping).
    final focal = Offset(viewport.width / 2 - 100, viewport.height / 2);
    final r = zoomAt(scale: 1.0, offset: Offset.zero, factor: 2.0, focal: focal, viewport: viewport, max: 4.0);
    expect(r.scale, 2.0);
    expect(r.offset.dx, closeTo(100, 1e-9));
    expect(r.offset.dy, closeTo(0, 1e-9));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/player/control/zoom_math_test.dart`
Expected: FAIL — `zoom_math.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/player/control/zoom_math.dart`:

```dart
import 'dart:ui';

/// Zoom scale floor. Zooming out past the natural frame is out of scope: it
/// would letterbox an already-letterboxed video with nothing to show.
const double kZoomMin = 1.0;

/// Slop-free translation bound: with the frame scaled by [scale], the visible
/// rect can only slide by half the overflow before an edge would show empty.
/// Returns [Offset.zero] whenever there is no overflow to slide into.
Offset clampZoomOffset(Offset offset, double scale, Size viewport) {
  if (scale <= kZoomMin) return Offset.zero;
  final maxX = (scale - 1) * viewport.width / 2;
  final maxY = (scale - 1) * viewport.height / 2;
  return Offset(
    offset.dx.clamp(-maxX, maxX),
    offset.dy.clamp(-maxY, maxY),
  );
}

/// Focal-anchored zoom: multiplies [scale] by [factor] (clamped to
/// [kZoomMin]..[max]) and moves [offset] so the content under [focal] stays
/// under [focal]. [focal] is in the viewport's local coordinates; the transform
/// it feeds scales about the viewport CENTRE, so the focal point is measured
/// from there.
({double scale, Offset offset}) zoomAt({
  required double scale,
  required Offset offset,
  required double factor,
  required Offset focal,
  required Size viewport,
  required double max,
}) {
  final target = (scale * factor).clamp(kZoomMin, max < kZoomMin ? kZoomMin : max);
  if (target <= kZoomMin) return (scale: kZoomMin, offset: Offset.zero);
  final centre = Offset(viewport.width / 2, viewport.height / 2);
  final fromCentre = focal - centre;
  final ratio = target / scale;
  final next = fromCentre - (fromCentre - offset) * ratio;
  return (scale: target, offset: clampZoomOffset(next, target, viewport));
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/player/control/zoom_math_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/player/control/zoom_math.dart test/player/control/zoom_math_test.dart
git commit -m "feat(player): focal-anchored zoom math with translation bounds"
```

---

### Task 4: Zoom state

**Files:**
- Create: `lib/ui/player/state/zoom_state.dart`
- Test: `test/ui/player/state/zoom_state_test.dart` (create)

**Interfaces:**
- Consumes: `clampZoomOffset`, `zoomAt` (Task 3); `KivoSettings.zoomMax`, `.zoomResetMode`, `.zoomRemembered` (Task 1).
- Produces: `ZoomState({double scale, Offset offset})` with `bool get active`; `zoomProvider`; and on `ZoomNotifier`: `pinch({required double factor, required Offset focal, required Size viewport})`, `panBy(Offset delta, Size viewport)`, `reset()`, `onVideoChanged()`, `onPlayerExit()`, `persistIfRemembered()`. Tasks 5, 6 and 7 consume these exact names.

- [ ] **Step 1: Write the failing test**

Create `test/ui/player/state/zoom_state_test.dart`:

```dart
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/settings/settings_store.dart';
import 'package:kivo_player/ui/player/state/zoom_state.dart';

Future<ProviderContainer> _container({KivoSettings? settings}) async {
  final s = await SettingsService.load(InMemorySettingsStore());
  if (settings != null) await s.update(settings);
  final c = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  const viewport = Size(400, 800);
  final centre = Offset(viewport.width / 2, viewport.height / 2);

  test('starts inactive at 1x', () async {
    final c = await _container();
    expect(c.read(zoomProvider).scale, 1.0);
    expect(c.read(zoomProvider).active, false);
  });

  test('pinch scales and marks active, respecting zoomMax', () async {
    final c = await _container(settings: KivoSettings.defaults().copyWith(zoomMax: 2.0));
    c.read(zoomProvider.notifier).pinch(factor: 8.0, focal: centre, viewport: viewport);
    expect(c.read(zoomProvider).scale, 2.0);
    expect(c.read(zoomProvider).active, true);
  });

  test('panBy is a no-op while inactive and clamps while zoomed', () async {
    final c = await _container();
    final n = c.read(zoomProvider.notifier);
    n.panBy(const Offset(50, 50), viewport);
    expect(c.read(zoomProvider).offset, Offset.zero);
    n.pinch(factor: 2.0, focal: centre, viewport: viewport);
    n.panBy(const Offset(9999, 0), viewport);
    expect(c.read(zoomProvider).offset.dx, 200); // (2-1)*400/2
  });

  test('reset returns to 1x and recentres', () async {
    final c = await _container();
    final n = c.read(zoomProvider.notifier);
    n.pinch(factor: 3.0, focal: centre, viewport: viewport);
    n.panBy(const Offset(100, 100), viewport);
    n.reset();
    expect(c.read(zoomProvider).scale, 1.0);
    expect(c.read(zoomProvider).offset, Offset.zero);
  });

  test('onVideoChanged resets only in video mode', () async {
    final exit = await _container(settings: KivoSettings.defaults().copyWith(zoomResetMode: 'exit'));
    exit.read(zoomProvider.notifier).pinch(factor: 2.0, focal: centre, viewport: viewport);
    exit.read(zoomProvider.notifier).onVideoChanged();
    expect(exit.read(zoomProvider).scale, 2.0, reason: 'exit mode keeps zoom across the queue');

    final perVideo = await _container(settings: KivoSettings.defaults().copyWith(zoomResetMode: 'video'));
    perVideo.read(zoomProvider.notifier).pinch(factor: 2.0, focal: centre, viewport: viewport);
    perVideo.read(zoomProvider.notifier).onVideoChanged();
    expect(perVideo.read(zoomProvider).scale, 1.0);
  });

  test('onPlayerExit resets except in never mode', () async {
    final exit = await _container(settings: KivoSettings.defaults().copyWith(zoomResetMode: 'exit'));
    exit.read(zoomProvider.notifier).pinch(factor: 2.0, focal: centre, viewport: viewport);
    exit.read(zoomProvider.notifier).onPlayerExit();
    expect(exit.read(zoomProvider).scale, 1.0);

    final never = await _container(settings: KivoSettings.defaults().copyWith(zoomResetMode: 'never'));
    never.read(zoomProvider.notifier).pinch(factor: 2.0, focal: centre, viewport: viewport);
    never.read(zoomProvider.notifier).onPlayerExit();
    expect(never.read(zoomProvider).scale, 2.0);
  });

  test('never mode persists the settled factor and seeds from it', () async {
    final c = await _container(settings: KivoSettings.defaults().copyWith(zoomResetMode: 'never'));
    final n = c.read(zoomProvider.notifier);
    n.pinch(factor: 2.0, focal: centre, viewport: viewport);
    n.persistIfRemembered();
    await Future<void>.delayed(Duration.zero); // set() is async
    expect(c.read(settingsProvider).zoomRemembered, 2.0);

    // A fresh container over the same store seeds from the remembered factor.
    final again = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(c.read(settingsServiceProvider)),
    ]);
    addTearDown(again.dispose);
    expect(again.read(zoomProvider).scale, 2.0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/player/state/zoom_state_test.dart`
Expected: FAIL — `zoom_state.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/ui/player/state/zoom_state.dart`:

```dart
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../player/control/zoom_math.dart';

/// Pinch-zoom of the video surface. [offset] is always pre-clamped, so an
/// out-of-bounds state cannot exist — every mutation goes through zoom_math.
class ZoomState {
  final double scale;
  final Offset offset;
  const ZoomState({this.scale = kZoomMin, this.offset = Offset.zero});

  /// Slightly above 1 so float dust from a pinch that settled back at 1x does
  /// not keep the chip on screen.
  bool get active => scale > 1.001;
}

class ZoomNotifier extends Notifier<ZoomState> {
  @override
  ZoomState build() {
    final s = ref.read(settingsProvider);
    if (s.zoomResetMode != 'never') return const ZoomState();
    // The remembered FACTOR is restored; the framing is not — an offset from
    // another file means nothing here.
    return ZoomState(scale: s.zoomRemembered.clamp(kZoomMin, s.zoomMax));
  }

  void pinch({required double factor, required Offset focal, required Size viewport}) {
    final r = zoomAt(
      scale: state.scale, offset: state.offset, factor: factor,
      focal: focal, viewport: viewport, max: ref.read(settingsProvider).zoomMax,
    );
    state = ZoomState(scale: r.scale, offset: r.offset);
  }

  void panBy(Offset delta, Size viewport) {
    if (!state.active) return;
    state = ZoomState(
      scale: state.scale,
      offset: clampZoomOffset(state.offset + delta, state.scale, viewport),
    );
  }

  /// The chip. Unconditional — it is the only thing that clears zoom in
  /// 'never' mode.
  void reset() {
    state = const ZoomState();
    _persist(kZoomMin);
  }

  void onVideoChanged() {
    if (ref.read(settingsProvider).zoomResetMode == 'video') state = const ZoomState();
  }

  void onPlayerExit() {
    if (ref.read(settingsProvider).zoomResetMode != 'never') state = const ZoomState();
  }

  /// Called when a pinch SETTLES (gesture end), not per frame — one disk write
  /// per pinch instead of sixty.
  void persistIfRemembered() => _persist(state.scale);

  void _persist(double scale) {
    final s = ref.read(settingsProvider);
    if (s.zoomResetMode != 'never' || s.zoomRemembered == scale) return;
    ref.read(settingsProvider.notifier).set(s.copyWith(zoomRemembered: scale));
  }
}

final zoomProvider = NotifierProvider<ZoomNotifier, ZoomState>(ZoomNotifier.new);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/player/state/zoom_state_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/player/state/zoom_state.dart test/ui/player/state/zoom_state_test.dart
git commit -m "feat(player): zoom state with configurable max and reset modes"
```

---

### Task 5: Gesture routing as a pure function

**Files:**
- Modify: `lib/player/control/gesture_math.dart` (append)
- Test: `test/player/control/gesture_math_test.dart` (append)

**Interfaces:**
- Consumes: the existing `inLateralDeadZone`, `inVerticalDeadZone`, `inCenterRotateZone` in the same file.
- Produces: `enum DragIntent { none, zoom, pan, brightness, volume, seek, dismiss, rotate }`, `const double kIntentSlopPx`, and `DragIntent? dragIntentFor({...})` where **`null` means "not decided yet, keep waiting"** and `DragIntent.none` means "decided to ignore this drag". Task 6 consumes both.

- [ ] **Step 1: Write the failing test**

Append to `test/player/control/gesture_math_test.dart` (inside `main`), one case per routing-table row:

```dart
  group('dragIntentFor', () {
    const viewport = Size(400, 800);
    DragIntent? route({
      int pointerCount = 1,
      bool pinchZoomEnabled = true,
      bool zoomActive = false,
      required Offset start,
      Offset delta = const Offset(50, 0),
      bool controlsVisible = false,
    }) =>
        dragIntentFor(
          pointerCount: pointerCount,
          pinchZoomEnabled: pinchZoomEnabled,
          zoomActive: zoomActive,
          start: start,
          delta: delta,
          viewport: viewport,
          topInset: 0,
          bottomInset: 0,
          controlsVisible: controlsVisible,
        );

    test('two fingers zoom', () {
      expect(route(pointerCount: 2, start: const Offset(200, 400)), DragIntent.zoom);
    });

    test('two fingers do nothing when pinch zoom is off', () {
      expect(route(pointerCount: 2, pinchZoomEnabled: false, start: const Offset(200, 400)),
          DragIntent.none);
    });

    test('one finger pans while zoomed', () {
      expect(route(zoomActive: true, start: const Offset(200, 400)), DragIntent.pan);
    });

    test('the lateral strip dismisses, with no slop needed', () {
      expect(route(start: const Offset(10, 400), delta: Offset.zero), DragIntent.dismiss);
      expect(route(start: const Offset(395, 400), delta: Offset.zero), DragIntent.dismiss);
    });

    test('the vertical dead strips are ignored', () {
      expect(route(start: const Offset(200, 5), delta: Offset.zero), DragIntent.none);
      expect(route(start: const Offset(200, 795), delta: Offset.zero), DragIntent.none);
    });

    test('below the slop nothing is decided yet', () {
      expect(route(start: const Offset(200, 400), delta: const Offset(4, 4)), isNull);
    });

    test('the centre band rotates on a vertical drag when controls are hidden', () {
      expect(route(start: const Offset(200, 400), delta: const Offset(0, -60)), DragIntent.rotate);
    });

    test('the centre band does NOT rotate while the controls are up', () {
      expect(route(start: const Offset(200, 400), delta: const Offset(0, -60), controlsVisible: true),
          DragIntent.volume);
    });

    test('vertical drags are brightness on the left and volume on the right', () {
      expect(route(start: const Offset(80, 400), delta: const Offset(0, -60)), DragIntent.brightness);
      expect(route(start: const Offset(320, 400), delta: const Offset(0, -60)), DragIntent.volume);
    });

    test('horizontal drags seek', () {
      expect(route(start: const Offset(80, 400), delta: const Offset(60, 5)), DragIntent.seek);
    });

    test('a diagonal tie goes to seek', () {
      expect(route(start: const Offset(80, 400), delta: const Offset(40, 40)), DragIntent.seek);
    });
  });
```

Add `import 'package:flutter/painting.dart';` at the top of the test file for `Size`/`Offset`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/player/control/gesture_math_test.dart`
Expected: FAIL — `dragIntentFor` is not defined.

- [ ] **Step 3: Write the implementation**

Append to `lib/player/control/gesture_math.dart` (and add `import 'dart:ui';` at the top for `Offset`/`Size`):

```dart
/// What a drag inside the player is FOR. One scale recognizer owns every drag
/// now (pinch cannot coexist with two drag-axis recognizers), so the axis
/// decision is ours to make instead of the gesture arena's — which is what
/// makes it testable.
enum DragIntent { none, zoom, pan, brightness, volume, seek, dismiss, rotate }

/// Travel required before a one-finger drag commits to an axis. Small enough
/// to feel immediate, large enough that a jitter cannot pick the wrong gesture.
const double kIntentSlopPx = 12.0;

/// Routes a drag to its intent. [start] is where the gesture BEGAN (dead zones
/// are positional, exactly as the old per-axis drag handlers evaluated them);
/// [delta] is accumulated travel since then.
///
/// Returns `null` while the gesture has not travelled far enough to commit —
/// the caller keeps waiting. [DragIntent.none] is a decision: ignore this drag.
DragIntent? dragIntentFor({
  required int pointerCount,
  required bool pinchZoomEnabled,
  required bool zoomActive,
  required Offset start,
  required Offset delta,
  required Size viewport,
  required double topInset,
  required double bottomInset,
  required bool controlsVisible,
  double slop = kIntentSlopPx,
  double lateralMargin = kLateralEdgeMargin,
  double verticalMargin = kVerticalDeadMargin,
}) {
  if (pointerCount >= 2) return pinchZoomEnabled ? DragIntent.zoom : DragIntent.none;
  // While zoomed, one finger reframes. Brightness/volume/seek/minimize/rotate
  // are suspended until 1x — the chip is how you get back.
  if (zoomActive) return DragIntent.pan;
  // Positional, decided with no slop: minimize owns the lateral strips and
  // seek is already dead there.
  if (inLateralDeadZone(start.dx, viewport.width, lateralMargin)) return DragIntent.dismiss;
  if (inVerticalDeadZone(start.dy, viewport.height, topInset, bottomInset, verticalMargin)) {
    return DragIntent.none;
  }
  if (delta.distance < slop) return null;
  if (delta.dy.abs() > delta.dx.abs()) {
    if (!controlsVisible && inCenterRotateZone(start.dx, viewport.width)) return DragIntent.rotate;
    return start.dx < viewport.width / 2 ? DragIntent.brightness : DragIntent.volume;
  }
  return DragIntent.seek;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/player/control/gesture_math_test.dart`
Expected: PASS — the new group plus every pre-existing test in the file.

- [ ] **Step 5: Commit**

```bash
git add lib/player/control/gesture_math.dart test/player/control/gesture_math_test.dart
git commit -m "feat(player): pure drag-intent routing for the unified gesture layer"
```

---

### Task 6: Move PlayerGestures onto a scale recognizer

**Files:**
- Modify: `lib/ui/player/gestures/player_gestures.dart` (replace the six drag handlers with three scale handlers)
- Test: `test/ui/player/player_gestures_test.dart` (must stay green — it is the regression net), `test/ui/player/gestures/player_dismiss_delegation_test.dart` (same)
- Test: `test/ui/player/gestures/pinch_zoom_test.dart` (create)

**Interfaces:**
- Consumes: `DragIntent`, `kIntentSlopPx`, `dragIntentFor` (Task 5); `zoomProvider` and `ZoomNotifier.pinch/panBy/persistIfRemembered` (Task 4); `KivoSettings.pinchZoom` (Task 1).
- Produces: no new public API.

**This is the riskiest task in the plan.** The existing gesture tests are the contract: they must pass unchanged. If one needs editing, stop and say why rather than loosening it.

- [ ] **Step 1: Write the failing test**

Create `test/ui/player/gestures/pinch_zoom_test.dart`. Two-finger gestures need explicit pointers — `tester.startGesture` twice, then move both apart:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/settings/settings_store.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/platform/device_controls_provider.dart';
import 'package:kivo_player/ui/player/gestures/player_gestures.dart';
import 'package:kivo_player/ui/player/state/zoom_state.dart';
import '../../../fakes/fakes.dart';
import '../player_gestures_test.dart' show NoopControls;

void main() {
  Future<ProviderContainer> harness(WidgetTester tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      deviceControlsProvider.overrideWithValue(NoopControls()),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: PlayerGestures(child: SizedBox.expand()))),
    ));
    return c;
  }

  testWidgets('a two-finger spread zooms in', (tester) async {
    final c = await harness(tester);
    final centre = tester.getCenter(find.byType(PlayerGestures));

    final a = await tester.startGesture(centre - const Offset(20, 0));
    final b = await tester.startGesture(centre + const Offset(20, 0));
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await a.moveBy(const Offset(-16, 0));
      await b.moveBy(const Offset(16, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pump();

    expect(c.read(zoomProvider).active, true);
    expect(c.read(zoomProvider).scale, greaterThan(1.5));
  });

  testWidgets('one finger pans while zoomed and leaves volume alone', (tester) async {
    final c = await harness(tester);
    final viewport = tester.getSize(find.byType(PlayerGestures));
    c.read(zoomProvider.notifier).pinch(
        factor: 2.0,
        focal: Offset(viewport.width / 2, viewport.height / 2),
        viewport: viewport);

    final before = c.read(zoomProvider).offset;
    await tester.drag(find.byType(PlayerGestures), const Offset(0, -80));
    await tester.pump();

    expect(c.read(zoomProvider).offset.dy, lessThan(before.dy),
        reason: 'the drag reframed instead of changing volume');
  });

  testWidgets('the pinch is inert when the setting is off', (tester) async {
    final c = await harness(tester);
    await c.read(settingsProvider.notifier)
        .set(c.read(settingsProvider).copyWith(pinchZoom: false));
    final centre = tester.getCenter(find.byType(PlayerGestures));

    final a = await tester.startGesture(centre - const Offset(20, 0));
    final b = await tester.startGesture(centre + const Offset(20, 0));
    for (var i = 0; i < 5; i++) {
      await a.moveBy(const Offset(-16, 0));
      await b.moveBy(const Offset(16, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pump();

    expect(c.read(zoomProvider).active, false);
  });
}
```

If importing `NoopControls` from the sibling test file does not work in this harness, copy the class into the new file instead — do not weaken the test to avoid it.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/player/gestures/pinch_zoom_test.dart`
Expected: FAIL — no zoom happens; `PlayerGestures` has no scale handling.

- [ ] **Step 3: Rewrite the gesture layer**

In `lib/ui/player/gestures/player_gestures.dart`:

Add imports for `../state/zoom_state.dart`. Replace the drag-related state fields (`_leftSide`, `_isDismiss`, `_isCenterRotate`, `_vDead`, `_hDead`) with the intent machine, keeping every other field (`_holding`, `_holdLeft`, `_brightness`, `_volPct`, `_volCap`, `_seekStart`, `_seekAccum`, `_rotateDy`, `_dismissHaptic`, insets) as they are:

```dart
  DragIntent? _intent;      // null = not yet decided
  Offset _start = Offset.zero;
  Offset _accum = Offset.zero;
  double _lastScale = 1.0;
  bool _leftSide = true;    // still needed by the hold-speed handlers
```

Add the size helper and the three handlers:

```dart
  Size get _viewport => Size(_width, _height);

  void _onScaleStart(ScaleStartDetails d) {
    _start = d.localFocalPoint;
    _accum = Offset.zero;
    _lastScale = 1.0;
    _intent = null;
    _dismissHaptic = false;
    _decide(d.pointerCount);
  }

  /// Resolves the intent once enough is known, and seeds whatever that intent
  /// needs. Idempotent: a decided intent is never re-decided.
  void _decide(int pointerCount) {
    if (_intent != null) return;
    final st = ref.read(settingsProvider);
    final next = dragIntentFor(
      pointerCount: pointerCount,
      pinchZoomEnabled: st.pinchZoom,
      zoomActive: ref.read(zoomProvider).active,
      start: _start,
      delta: _accum,
      viewport: _viewport,
      topInset: _topInset,
      bottomInset: _bottomInset,
      controlsVisible: ref.read(controlsVisibleProvider),
    );
    if (next == null) return;
    _intent = next;
    switch (next) {
      case DragIntent.brightness:
        _leftSide = true;
        ref.read(deviceControlsProvider).currentBrightness().then((b) => _brightness = b);
      case DragIntent.volume:
        _leftSide = false;
        _volPct = ref.read(volumePercentProvider);
        _volCap = _volPct < 100 ? 100.0 : st.volumeBoostMax.toDouble();
        // Let player_screen's system-volume listener ignore hardware-key echo
        // during the drag, so a boost above 100% survives.
        ref.read(volumeGestureActiveProvider.notifier).state = true;
      case DragIntent.seek:
        _seekStart = ref.read(positionProvider).value ?? Duration.zero;
        _seekAccum = 0;
      case DragIntent.rotate:
        _rotateDy = 0;
      case DragIntent.zoom || DragIntent.pan || DragIntent.dismiss || DragIntent.none:
        break;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    // A second finger takes over: abandon whatever one-finger gesture was
    // underway rather than letting both fight over the same pointers.
    if (d.pointerCount >= 2 &&
        _intent != DragIntent.zoom &&
        ref.read(settingsProvider).pinchZoom) {
      _cancelIntent();
      _intent = DragIntent.zoom;
      _lastScale = d.scale;
    }
    _accum += d.focalPointDelta;
    if (_intent == null) {
      _decide(d.pointerCount);
      if (_intent == null) return;
    }
    if (_holding) return; // a hold-to-speed long-press owns this touch
    final zoom = ref.read(zoomProvider.notifier);
    switch (_intent!) {
      case DragIntent.none:
        return;
      case DragIntent.zoom:
        final factor = _lastScale == 0 ? 1.0 : d.scale / _lastScale;
        _lastScale = d.scale;
        zoom.pinch(factor: factor, focal: d.localFocalPoint, viewport: _viewport);
        // Two-finger drag reframes too, so a pinch can be aimed without lifting.
        zoom.panBy(d.focalPointDelta, _viewport);
      case DragIntent.pan:
        zoom.panBy(d.focalPointDelta, _viewport);
      case DragIntent.dismiss:
        final current = ref.read(dismissProvider);
        final fraction = (current + d.focalPointDelta.dy / _height).clamp(0.0, 1.0);
        ref.read(dismissProvider.notifier).state = fraction;
        if (!_dismissHaptic && fraction >= 0.25) {
          _dismissHaptic = true;
          _haptic(); // tick once when crossing the commit threshold
        }
      case DragIntent.rotate:
        _rotateDy += d.focalPointDelta.dy; // the rotate fires on end
      case DragIntent.brightness:
        final st = ref.read(settingsProvider);
        _brightness = dragValue(_brightness, d.focalPointDelta.dy, _height, st.brightnessSensitivity);
        ref.read(playerControllerProvider).setBrightness(_brightness);
        ref.read(hudProvider.notifier)
            .show(HudKind.brightness, _brightness, '${(_brightness * 100).round()}%');
      case DragIntent.volume:
        final st = ref.read(settingsProvider);
        _volPct = dragVolumePercent(_volPct, d.focalPointDelta.dy, _height, st.volumeSensitivity, _volCap);
        ref.read(playerControllerProvider).setVolumePercent(_volPct);
        ref.read(hudProvider.notifier).show(HudKind.volume, _volPct / 100, '${_volPct.round()}%');
      case DragIntent.seek:
        final st = ref.read(settingsProvider);
        if (!st.horizontalSeek) return;
        final total = ref.read(durationProvider).value ?? Duration.zero;
        _seekAccum += d.focalPointDelta.dx;
        final target = horizontalSeekTarget(
            start: _seekStart, accumPx: _seekAccum, widthPx: _width,
            total: total, sensitivity: st.seekSensitivity);
        // Preview, don't live-seek: the seek lands on release.
        ref.read(gestureSeekProvider.notifier).state = (target: target, from: _seekStart);
        ref.read(seekPreviewControllerProvider).request(target);
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    // Always clear the volume flag so hardware keys resume updating Kivo's
    // volume model, whatever this drag turned out to be.
    ref.read(volumeGestureActiveProvider.notifier).state = false;
    final intent = _intent;
    _intent = null;
    switch (intent) {
      case DragIntent.rotate:
        final dy = _rotateDy;
        _rotateDy = 0;
        // Directional, not a toggle: UP in portrait -> landscape, DOWN in
        // landscape -> portrait. Short or wrong-way drags do nothing.
        final target = swipeRotateTarget(ref.read(orientationProvider), dy);
        if (target != null) {
          ref.read(orientationProvider.notifier).rotateTo(target);
          _haptic();
        }
      case DragIntent.dismiss:
        final progress = ref.read(dismissProvider);
        final api = ref.read(playerDismissProvider);
        if (dismissCommit(progress, d.velocity.pixelsPerSecond.dy)) {
          if (api != null) {
            api.complete();
          } else {
            // Defensive fallback if no PlayerScreen published the API.
            ref.read(dismissProvider.notifier).state = 0;
            Navigator.of(context).maybePop();
          }
        } else {
          _cancelDismiss(api);
        }
      case DragIntent.seek:
        final gesture = ref.read(gestureSeekProvider);
        if (gesture == null) return; // never engaged (dead zone / seek off)
        ref.read(playerControllerProvider).seekTo(gesture.target);
        // Hold the bar at the target until real position catches up.
        ref.read(pendingSeekProvider.notifier).state = gesture.target;
        ref.read(gestureSeekProvider.notifier).state = null;
        // Drop the frame so the next swipe can't flash the previous target.
        ref.read(seekPreviewFrameProvider.notifier).state = null;
        _haptic();
      case DragIntent.zoom:
        ref.read(zoomProvider.notifier).persistIfRemembered();
      case DragIntent.pan || DragIntent.none || DragIntent.brightness ||
            DragIntent.volume || null:
        break;
    }
  }

  /// Unwinds a one-finger gesture that a second finger just stole.
  void _cancelIntent() {
    switch (_intent) {
      case DragIntent.dismiss:
        _cancelDismiss(ref.read(playerDismissProvider));
      case DragIntent.seek:
        ref.read(gestureSeekProvider.notifier).state = null;
        ref.read(seekPreviewFrameProvider.notifier).state = null;
      default:
        break;
    }
  }

  void _cancelDismiss(PlayerDismissApi? api) {
    if (api != null) {
      api.cancel();
    } else {
      ref.read(dismissProvider.notifier).state = 0;
    }
  }
```

In `build`, swap the six drag callbacks for the three scale ones (leave `onTap`, `onDoubleTapDown`, `onDoubleTap` and the three `onLongPress*` untouched):

```dart
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
```

Two notes for the implementer:
- `setBrightness` and `setVolumePercent` are on `playerControllerProvider` — keep using the same controller calls the old handlers used (`ctrl.setBrightness`, `ctrl.setVolumePercent`); the code above reads the provider inline, which is equivalent.
- Delete `_onVerticalStart/_onVerticalUpdate/_onVerticalEnd` and `_onHorizontalStart/_onHorizontalUpdate/_onHorizontalEnd` and the now-unused `_dead` helper only if nothing else references them. `flutter analyze` will name any leftover.

- [ ] **Step 4: Run the whole gesture suite**

Run: `flutter test test/ui/player/`
Expected: the new pinch tests PASS **and** `player_gestures_test.dart` plus `player_dismiss_delegation_test.dart` stay green. Then `flutter test` fully green and `flutter analyze` clean.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/player/gestures/player_gestures.dart test/ui/player/gestures/pinch_zoom_test.dart
git commit -m "feat(player): one scale recognizer owns every player drag, enabling pinch zoom"
```

---

### Task 7: Paint the zoom, and the chip

**Files:**
- Create: `lib/ui/player/zoom/zoom_chip.dart`
- Modify: `lib/ui/player/player_screen.dart` (the `videoBox` builder, and the overlay list)
- Test: `test/ui/player/zoom/zoom_chip_test.dart` (create)

**Interfaces:**
- Consumes: `zoomProvider`, `ZoomState.active`, `ZoomNotifier.reset()` (Task 4).
- Produces: `ZoomChip` (a `const`-constructible `ConsumerWidget`).

- [ ] **Step 1: Write the failing test**

Create `test/ui/player/zoom/zoom_chip_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/settings/settings_store.dart';
import 'package:kivo_player/ui/player/state/zoom_state.dart';
import 'package:kivo_player/ui/player/zoom/zoom_chip.dart';

void main() {
  Future<ProviderContainer> harness(WidgetTester tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: Stack(children: [Positioned.fill(child: ZoomChip())]))),
    ));
    return c;
  }

  testWidgets('hidden at 1x', (tester) async {
    await harness(tester);
    expect(find.textContaining('×'), findsNothing);
  });

  testWidgets('shows the factor once zoomed and restores on tap', (tester) async {
    final c = await harness(tester);
    c.read(zoomProvider.notifier)
        .pinch(factor: 1.8, focal: const Offset(200, 400), viewport: const Size(400, 800));
    await tester.pumpAndSettle();

    expect(find.text('1.8×'), findsOneWidget);

    await tester.tap(find.text('1.8×'));
    await tester.pumpAndSettle();

    expect(c.read(zoomProvider).active, false);
    expect(find.textContaining('×'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/player/zoom/zoom_chip_test.dart`
Expected: FAIL — `zoom_chip.dart` does not exist.

- [ ] **Step 3: Write the chip**

Create `lib/ui/player/zoom/zoom_chip.dart`:

```dart
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../state/zoom_state.dart';

/// Floating pill shown whenever the video is zoomed: the live factor plus a
/// tap-to-restore. It lives in its OWN overlay layer, not in ControlsOverlay,
/// because "am I zoomed, and how do I get out" must stay answerable while the
/// controls are hidden.
class ZoomChip extends ConsumerWidget {
  const ZoomChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zoom = ref.watch(zoomProvider);
    final accent = Color(ref.watch(settingsProvider).accentColor);
    return IgnorePointer(
      ignoring: !zoom.active,
      child: AnimatedOpacity(
        opacity: zoom.active ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: Align(
          alignment: Alignment.bottomLeft,
          // Mirrors AbLoopChip on the right: clear of the seek bar + button row.
          child: Padding(
            padding: const EdgeInsets.only(left: 14, bottom: 116),
            child: GestureDetector(
              onTap: () {
                ref.read(zoomProvider.notifier).reset();
                if (ref.read(settingsProvider).hapticsOnGestures) {
                  HapticFeedback.lightImpact();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: accent.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.center_focus_strong, size: 13, color: accent),
                    const SizedBox(width: 6),
                    Text(
                      '${zoom.scale.toStringAsFixed(1)}×',
                      style: TextStyle(
                        color: accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        // Tabular so the digits don't jitter 1.9x -> 2.0x.
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.close_rounded, size: 12,
                        color: Colors.white.withValues(alpha: 0.42)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

Note: the test asserts the chip's text is absent at 1×. `AnimatedOpacity` keeps the subtree mounted, so **return `const SizedBox.shrink()` when `!zoom.active`** instead of animating out, or wrap the animated child in an `if`. Choose the mounted-only-when-active form so the test's `findsNothing` is honest:

```dart
    if (!zoom.active) return const SizedBox.shrink();
```

placed right after reading `zoom`, with the `AnimatedOpacity`/`IgnorePointer` wrapper dropped and a `TweenAnimationBuilder` used for the 160 ms fade-in on mount (the pattern `mini_player_bar.dart` already uses).

- [ ] **Step 4: Wire it into the player**

In `lib/ui/player/player_screen.dart`, wrap the video stack in the transform. Replace the `videoBox`'s `child:` (the `_controller == null ? ... : Stack(...)`) so the `Stack` branch becomes:

```dart
                  : ClipRect(
                      child: Consumer(
                        builder: (context, ref, _) {
                          final z = ref.watch(zoomProvider);
                          return Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..translate(z.offset.dx, z.offset.dy)
                              ..scale(z.scale),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [ /* the existing Video + ColoredBox children, unchanged */ ],
                            ),
                          );
                        },
                      ),
                    ),
```

Copy the existing `Video(...)` and `if (!videoReady) const ColoredBox(color: Colors.black)` children in verbatim. Two things this shape buys, both deliberate: `ClipRect` stops the scaled frame painting over the control bars, and the **local** `Consumer` means a 60 fps pinch rebuilds only the transform instead of all ten overlay layers.

Add `ZoomChip` to the overlay list, next to the other `Positioned.fill` entries (it is inside the `if (!ref.watch(pipModeProvider))` block, so it is correctly absent in PiP):

```dart
                        const Positioned.fill(child: ZoomChip()),
```

Add the imports for `state/zoom_state.dart` and `zoom/zoom_chip.dart`.

- [ ] **Step 5: Run the tests**

Run: `flutter test`
Expected: green, including the existing `player_screen_controls_test.dart` and `video_ready_test.dart`. Then `flutter analyze` clean.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/player/zoom/zoom_chip.dart lib/ui/player/player_screen.dart test/ui/player/zoom/zoom_chip_test.dart
git commit -m "feat(player): render the zoom transform and its restore chip"
```

---

### Task 8: Reset wiring — player exit and video change

**Files:**
- Modify: `lib/ui/player/player_screen.dart` (`initState`/field for the cached notifier, `_openSession`, `dispose`)
- Test: `test/ui/player/zoom/zoom_reset_wiring_test.dart` (create)

**Interfaces:**
- Consumes: `ZoomNotifier.onPlayerExit()`, `.onVideoChanged()` (Task 4).
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Write the failing test**

Create `test/ui/player/zoom/zoom_reset_wiring_test.dart`. Pumping a whole `PlayerScreen` is heavy; assert the wiring at the notifier level plus the one thing that is genuinely structural — that the reset is deferred, not run inline during teardown:

```dart
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/settings/settings_store.dart';
import 'package:kivo_player/ui/player/state/zoom_state.dart';

void main() {
  const viewport = Size(400, 800);
  final centre = Offset(viewport.width / 2, viewport.height / 2);

  Future<ProviderContainer> container(String mode) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    await s.update(KivoSettings.defaults().copyWith(zoomResetMode: mode));
    final c = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
    addTearDown(c.dispose);
    return c;
  }

  test('exit mode: zoom survives a video change but not leaving the player', () async {
    final c = await container('exit');
    final n = c.read(zoomProvider.notifier);
    n.pinch(factor: 2.0, focal: centre, viewport: viewport);
    n.onVideoChanged();
    expect(c.read(zoomProvider).scale, 2.0);
    n.onPlayerExit();
    expect(c.read(zoomProvider).scale, 1.0);
  });

  test('video mode: every video change recentres', () async {
    final c = await container('video');
    final n = c.read(zoomProvider.notifier);
    n.pinch(factor: 2.0, focal: centre, viewport: viewport);
    n.onVideoChanged();
    expect(c.read(zoomProvider).scale, 1.0);
  });

  test('never mode: neither a video change nor leaving clears it', () async {
    final c = await container('never');
    final n = c.read(zoomProvider.notifier);
    n.pinch(factor: 2.0, focal: centre, viewport: viewport);
    n.onVideoChanged();
    n.onPlayerExit();
    expect(c.read(zoomProvider).scale, 2.0);
    n.reset(); // the chip is the only way out
    expect(c.read(zoomProvider).scale, 1.0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails or passes**

Run: `flutter test test/ui/player/zoom/zoom_reset_wiring_test.dart`
Expected: PASS — Task 4 already implements the notifier semantics. This test exists to pin them while Step 3 adds the call sites; if it fails, Task 4 is wrong and must be fixed before continuing.

- [ ] **Step 3: Add the call sites**

In `lib/ui/player/player_screen.dart`, cache the notifier alongside the other cached services (`_resume`, `_frames`, `_miniThumb`, `_deviceControls`) — the same pattern, for the same reason: `dispose()` must not touch `ref`:

```dart
  late final ZoomNotifier _zoom;
```

and in `initState` (next to the other cached reads):

```dart
    _zoom = ref.read(zoomProvider.notifier);
```

In `_openSession`, reset per-video zoom on a genuine video change (not when expanding the same session from the mini-bar):

```dart
    if (!expandingFromMini) _zoom.onVideoChanged();
```

Put it at the top of the method, beside the other `!expandingFromMini` work.

In `dispose`, defer the reset into a microtask — writing to a provider synchronously during tree finalization throws "Tried to modify a provider while the widget tree was building", which is exactly why the existing `_dismissApi` clear is deferred there:

```dart
    // Deferred for the same reason as the _dismissApi clear below: a synchronous
    // provider write during this frame's teardown throws.
    scheduleMicrotask(_zoom.onPlayerExit);
```

Add the `state/zoom_state.dart` import if Task 7 did not already.

- [ ] **Step 4: Run the tests**

Run: `flutter test`
Expected: fully green. Then `flutter analyze` clean.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/player/player_screen.dart test/ui/player/zoom/zoom_reset_wiring_test.dart
git commit -m "feat(player): honour the zoom reset mode on exit and video change"
```

---

### Task 9: The settings UI

**Files:**
- Modify: `lib/ui/settings/sections/playback_gestures_section.dart` (new Zoom card)
- Modify: `lib/ui/settings/sections/advanced_playback_section.dart` (minimize switch)
- Test: `test/ui/settings/zoom_minimize_settings_test.dart` (create)

**Interfaces:**
- Consumes: all five fields from Task 1; the toolkit signatures in Global Constraints.
- Produces: no new API.

- [ ] **Step 1: Write the failing test**

Create `test/ui/settings/zoom_minimize_settings_test.dart`. Follow the setup of an existing settings-section test in `test/ui/settings/` — read one first and mirror its container/pump shape:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/settings/settings_store.dart';
import 'package:kivo_player/ui/settings/sections/playback_gestures_section.dart';

void main() {
  testWidgets('the Zoom card toggles pinch zoom', (tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
    addTearDown(c.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: PlaybackGesturesSection()),
    ));

    await tester.scrollUntilVisible(find.text('Zoom con pinch'), 200);
    expect(c.read(settingsProvider).pinchZoom, true);
    await tester.tap(find.text('Zoom con pinch'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).pinchZoom, false);
  });
}
```

If `SettingSwitch`'s title is not itself tappable, tap the `Switch` found within that row instead — check `setting_tiles.dart` and target whatever the row actually exposes.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/settings/zoom_minimize_settings_test.dart`
Expected: FAIL — no "Zoom con pinch" row exists.

- [ ] **Step 3: Add the Zoom card**

In `lib/ui/settings/sections/playback_gestures_section.dart`, insert a new labelled card after the "Salto y seek" card (before "Sensibilidad de gestos"):

```dart
          const SizedBox(height: 16),
          _label(context, 'Zoom'),
          SettingsCard(children: [
            SettingSwitch(
                title: 'Zoom con pinch',
                subtitle: 'Pellizca para ampliar y arrastra para encuadrar',
                value: s.pinchZoom,
                onChanged: (v) => n.set(s.copyWith(pinchZoom: v))),
            SettingSegmented<double>(
                title: 'Zoom máximo', value: s.zoomMax,
                options: const [(2.0, '2×'), (4.0, '4×'), (6.0, '6×'), (8.0, '8×')],
                onChanged: (v) => n.set(s.copyWith(zoomMax: v))),
            SettingSegmented<String>(
                title: 'Reiniciar el zoom',
                subtitle: 'Cuándo vuelve solo a 1×',
                value: s.zoomResetMode,
                options: const [('exit', 'Al salir'), ('video', 'Cada video'), ('never', 'Nunca')],
                onChanged: (v) => n.set(s.copyWith(zoomResetMode: v))),
          ]),
```

- [ ] **Step 4: Add the minimize switch**

In `lib/ui/settings/sections/advanced_playback_section.dart`, inside the "Reproducción" card (beside `autoplayNext` and `pipAutoOnHome`):

```dart
            SettingSwitch(
                title: 'Seguir reproduciendo al minimizar',
                subtitle: 'Al minimizar, el audio continúa en la barra inferior',
                value: s.minimizeKeepsPlaying,
                onChanged: (v) => n.set(s.copyWith(minimizeKeepsPlaying: v))),
```

Match the local variable names that section already uses for the settings object and notifier (`s` / `n` in the gestures section — confirm before editing).

- [ ] **Step 5: Extend the test to cover the other three controls**

Add cases to the same file: tapping `6×` sets `zoomMax` to `6.0`; tapping `Cada video` sets `zoomResetMode` to `'video'`; and a second `testWidgets` pumping `AdvancedPlaybackSection` that toggles `minimizeKeepsPlaying` to `true`. Write them out fully, in the shape of Step 1's test.

- [ ] **Step 6: Run the tests**

Run: `flutter test`
Expected: fully green. Then `flutter analyze` clean.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/settings/sections/playback_gestures_section.dart lib/ui/settings/sections/advanced_playback_section.dart test/ui/settings/zoom_minimize_settings_test.dart
git commit -m "feat(settings): Zoom card and keep-playing-on-minimize switch"
```

---

### Task 10: Gesture map copy, and the release build

**Files:**
- Modify: `lib/ui/player/tutorial/gesture_map_content.dart` (document the pinch)
- Modify: `pubspec.yaml` (version bump)

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Document the pinch in the gesture map**

Read `lib/ui/player/tutorial/gesture_map_content.dart` and add an entry in its existing shape describing the new gesture — Spanish copy, matching the surrounding entries' tone: pinch with two fingers to zoom, drag with one finger to reframe while zoomed, tap the chip to return to 1×. Follow whatever data structure the file already uses; do not restructure it.

- [ ] **Step 2: Run the full suite**

Run: `flutter analyze && flutter test`
Expected: analyze clean, every test green. Record the final test count in the commit message.

- [ ] **Step 3: Bump the version**

In `pubspec.yaml`, bump the minor version and build number (currently `1.2.0+2007` — go to `1.3.0+2008`; this is a feature release).

- [ ] **Step 4: Commit**

```bash
git add lib/ui/player/tutorial/gesture_map_content.dart pubspec.yaml
git commit -m "docs(player): gesture map covers pinch zoom; bump to 1.3.0+2008"
```

- [ ] **Step 5: Release build to the device**

```bash
flutter build apk --release
```

Then install to the connected Pixel 6 and verify by hand, because none of it is unit-testable: the pinch feels anchored under the fingers; panning cannot push the frame off-screen; the chip shows a live factor and restores on tap; brightness/volume/seek/minimize still behave at 1×; a second finger mid-swipe does not leave a half-dismissed player; and with "Seguir reproduciendo al minimizar" on, minimizing keeps the audio going while closing the mini-bar stops it.

- [ ] **Step 6: Ship it**

Per the project's release convention, push a tag for the new version so the GitHub Release workflow builds and publishes it. Never hand-deliver a locally built APK.

---

## Self-Review

**Spec coverage:** §1 gesture constraint → Task 6. §2 zoom state → Task 4. §3 zoom math → Task 3. §4 transform → Task 7. §5 routing → Tasks 5 and 6. §6 chip → Task 7. §7 settings → Tasks 1 and 9. §8 minimize → Task 2. §9 testing → distributed across every task, with the manual matrix in Task 10. The spec's `'never'`-mode persistence rule (write on pinch settle, not per frame) is Task 4's `persistIfRemembered`, called from Task 6's `_onScaleEnd`. No gaps.

**Type consistency:** `dragIntentFor` returns `DragIntent?` in Tasks 5 and 6. `zoomAt` returns `({double scale, Offset offset})` in Tasks 3, 4. `ZoomNotifier` method names — `pinch`, `panBy`, `reset`, `onVideoChanged`, `onPlayerExit`, `persistIfRemembered` — are used identically in Tasks 4, 6, 7, 8. `kZoomMin` is defined in Task 3 and consumed in Task 4.

**Known risk:** Task 6 is the one place where existing behaviour can silently regress, which is why its gate is "the pre-existing gesture tests pass unchanged" rather than "the new tests pass".
