# Kivo Hito 1 · Plan 3a — Player polish (lock, aspect, rotation, info overlay)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Activate the four "polish" controls that are currently disabled placeholders — screen lock (with hold-to-unlock), aspect/zoom modes, orientation/rotation, and the always-on PotPlayer-style info overlay — wiring each to the existing player.

**Architecture:** Each feature gets a small Riverpod state unit (lock, aspect, orientation) with pure transition logic that is unit-tested; the gesture layer and controls read those providers; the info overlay is a dumb widget reading settings + position. No new dependencies.

**Tech Stack:** Flutter, flutter_riverpod, media_kit_video (the `Video` widget's `fit:`), the existing `DeviceControls` platform boundary. Tests: flutter_test.

## Global Constraints

- Builds on Plan 1 + Plan 2 (on `master`). Reuse existing providers; do not reimplement engine/gestures/controls.
- State via Riverpod; tunables come from `settingsProvider` (`KivoSettings`): `showInfoOverlay`, `infoOverlayContent`, `infoOverlayCorner`, `defaultAspectMode`, `rememberOrientationLock`.
- `package:media_kit` only in `media_kit_engine.dart`; `media_kit_video` allowed in UI; device hardware only via `deviceControlsProvider`.
- Only `SeekBar` (and the gesture seek read) watch `positionProvider` — the info overlay must isolate its time text in a small inner consumer so it doesn't rebuild the whole overlay tree per tick.
- Accent color: read `Color(ref.watch(settingsProvider).accentColor)` (never hardcode gold) for any accented element.
- The disabled buttons being activated live in `top_bar.dart` (the info 👁 toggle) and `bottom_bar.dart` (lock, aspect, rotate). subtitles/PiP/audio stay disabled (Hito 3).
- YAGNI: aspect modes = fit/fill/stretch (BoxFit-based); forced 16:9/4:3/original are out of scope for 3a.

---

## File structure (this plan)

```
lib/core/format.dart                         # fmtDuration + basenameOf (shared)
lib/ui/player/state/lock_state.dart          # lockProvider
lib/ui/player/state/aspect_state.dart        # AspectMode + aspectModeProvider + pure helpers
lib/ui/player/state/orientation_state.dart   # orientationProvider + nextOrientation
lib/ui/player/controls/info_overlay.dart     # persistent info overlay + infoOverlayText (pure)
lib/ui/player/gestures/player_gestures.dart  # MODIFY: gate when locked
lib/ui/player/controls/controls_overlay.dart # MODIFY: locked view (hold-to-unlock)
lib/ui/player/controls/bottom_bar.dart       # MODIFY: activate lock/aspect/rotate
lib/ui/player/controls/top_bar.dart          # MODIFY: activate info 👁 toggle
lib/ui/player/controls/seek_bar.dart         # MODIFY: use shared fmtDuration
lib/ui/player/player_screen.dart             # MODIFY: Video fit, info overlay, orientation
test/core/format_test.dart
test/ui/player/lock_state_test.dart
test/ui/player/aspect_state_test.dart
test/ui/player/orientation_state_test.dart
test/ui/player/info_overlay_test.dart
test/ui/player/lock_gesture_test.dart
```

---

### Task 1: Shared format helpers

**Files:**
- Create: `lib/core/format.dart`
- Modify: `lib/ui/player/controls/seek_bar.dart` (replace its local `fmtDuration` with the shared one)
- Test: `test/core/format_test.dart`

**Interfaces:**
- Produces: `String fmtDuration(Duration d)` (`m:ss` or `h:mm:ss`), `String basenameOf(String? path)` (filename from a `/`- or `\`-separated path; `'Kivo'` if null).

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/format.dart';

void main() {
  test('fmtDuration', () {
    expect(fmtDuration(const Duration(seconds: 65)), '01:05');
    expect(fmtDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
  });
  test('basenameOf handles both separators and null', () {
    expect(basenameOf('/movies/ep1.mkv'), 'ep1.mkv');
    expect(basenameOf(r'C:\v\ep2.mp4'), 'ep2.mp4');
    expect(basenameOf(null), 'Kivo');
  });
}
```

- [ ] **Step 2: Run → FAIL**

Run: `flutter test test/core/format_test.dart`

- [ ] **Step 3: Implement `lib/core/format.dart`**

```dart
String fmtDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
}

String basenameOf(String? path) {
  if (path == null || path.isEmpty) return 'Kivo';
  final p = path.replaceAll('\\', '/');
  final i = p.lastIndexOf('/');
  return i < 0 ? p : p.substring(i + 1);
}
```

- [ ] **Step 4: Point `seek_bar.dart` at the shared helper.** In `lib/ui/player/controls/seek_bar.dart`, delete its top-level `fmtDuration` definition and add `import '../../../core/format.dart';` (the `SeekBar` already calls `fmtDuration(...)`, which now resolves to the shared one).

- [ ] **Step 5: Run → PASS** (`flutter test test/core/format_test.dart`), then `flutter analyze` (clean — no duplicate `fmtDuration`).

- [ ] **Step 6: Commit**

```bash
git add lib/core/format.dart lib/ui/player/controls/seek_bar.dart test/core/format_test.dart
git commit -m "refactor: shared fmtDuration + basenameOf in core/format"
```

---

### Task 2: Lock state + gesture gating + hold-to-unlock

**Files:**
- Create: `lib/ui/player/state/lock_state.dart`
- Modify: `lib/ui/player/gestures/player_gestures.dart`, `lib/ui/player/controls/controls_overlay.dart`, `lib/ui/player/controls/bottom_bar.dart`
- Test: `test/ui/player/lock_state_test.dart`, `test/ui/player/lock_gesture_test.dart`

**Interfaces:**
- Consumes: `controlsVisibleProvider` (toggle), `KivoIcon`/`KivoIcons.lock`/`unlock`, `settingsProvider` (accent), playback state.
- Produces: `lockProvider` → `NotifierProvider<LockNotifier, bool>` with `lock()`, `unlock()`.

- [ ] **Step 1: Write the lock-state test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/ui/player/state/lock_state.dart';

void main() {
  test('lock/unlock toggles state', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(lockProvider), false);
    c.read(lockProvider.notifier).lock();
    expect(c.read(lockProvider), true);
    c.read(lockProvider.notifier).unlock();
    expect(c.read(lockProvider), false);
  });
}
```

- [ ] **Step 2: Run → FAIL**

- [ ] **Step 3: Implement `lock_state.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LockNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void lock() => state = true;
  void unlock() => state = false;
}

final lockProvider = NotifierProvider<LockNotifier, bool>(LockNotifier.new);
```

- [ ] **Step 4: Gate `player_gestures.dart` when locked.** At the very top of the `build`'s returned `GestureDetector` logic, read the lock state and, when locked, only allow a tap to toggle the (lock-button) overlay; ignore every other gesture. Concretely, in `build`:

```dart
@override
Widget build(BuildContext context) {
  final locked = ref.watch(lockProvider);
  return LayoutBuilder(
    builder: (context, constraints) {
      _width = constraints.maxWidth;
      _height = constraints.maxHeight;
      if (locked) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ref.read(controlsVisibleProvider.notifier).toggle(),
          child: widget.child,
        );
      }
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ref.read(controlsVisibleProvider.notifier).toggle(),
        onDoubleTapDown: (d) => _lastTapDx = d.localPosition.dx,
        onDoubleTap: _onDoubleTap,
        onVerticalDragStart: _onVerticalStart,
        onVerticalDragUpdate: _onVerticalUpdate,
        onHorizontalDragStart: _onHorizontalStart,
        onHorizontalDragUpdate: _onHorizontalUpdate,
        onLongPressStart: _onLongPressStart,
        onLongPressMoveUpdate: _onLongPressMove,
        onLongPressEnd: _onLongPressEnd,
        child: widget.child,
      );
    },
  );
}
```
(`PlayerGestures` is a `ConsumerStatefulWidget`, so `ref.watch` works in its State's `build`.)

- [ ] **Step 5: Locked view in `controls_overlay.dart`.** When locked, show ONLY a centered "hold to unlock" lock button (gated by `controlsVisibleProvider` like the normal controls), not the top/center/bottom bars:

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final visible = ref.watch(controlsVisibleProvider);
  final locked = ref.watch(lockProvider);
  final accent = Color(ref.watch(settingsProvider).accentColor);
  return AnimatedOpacity(
    opacity: visible ? 1 : 0,
    duration: const Duration(milliseconds: 200),
    child: IgnorePointer(
      ignoring: !visible,
      child: locked
          ? Center(
              child: GestureDetector(
                onLongPress: () => ref.read(lockProvider.notifier).unlock(),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    KivoIcon(KivoIcons.lock, size: 30, color: accent),
                    const SizedBox(height: 6),
                    const Text('mantén para desbloquear',
                        style: TextStyle(color: Colors.white70, fontSize: 11)),
                  ]),
                ),
              ),
            )
          : Stack(children: [ /* existing top scrim+TopBar, Center CenterControls, bottom scrim+BottomBar */ ]),
    ),
  );
}
```
Keep the existing non-locked `Stack` children exactly as they are today; only wrap with the `locked ?` branch. Add imports for `lock_state.dart`, `settings_provider.dart`, `kivo_icons.dart` as needed.

- [ ] **Step 6: Activate the lock button in `bottom_bar.dart`.** Replace the disabled lock `IconButton` with an active one that locks and hides the controls:

```dart
IconButton(
  color: Colors.white,
  icon: KivoIcon(KivoIcons.lock, size: 24, color: Colors.white),
  onPressed: () {
    ref.read(lockProvider.notifier).lock();
    ref.read(controlsVisibleProvider.notifier).hide();
  },
),
```
(Add imports for `lock_state.dart`, `controls_visibility.dart`.)

- [ ] **Step 7: Write the lock-gesture widget test** `test/ui/player/lock_gesture_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/platform/device_controls_provider.dart';
import 'package:kivo_player/platform/interfaces/device_controls.dart';
import 'package:kivo_player/ui/player/state/lock_state.dart';
import 'package:kivo_player/ui/player/gestures/player_gestures.dart';
import '../../fakes/fakes.dart';

class NoopControls implements DeviceControls {
  @override Future<double> currentBrightness() async => 0.5;
  @override Future<void> setBrightness(double v) async {}
  @override Future<double> currentVolume() async => 0.5;
  @override Future<void> setSystemVolume(double v) async {}
  @override Future<void> setOrientation(List<DeviceOrientationLock> o) async {}
  @override Future<void> keepAwake(bool on) async {}
  @override Future<void> setImmersive(bool on) async {}
}

void main() {
  testWidgets('when locked, a vertical drag does not change volume', (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      deviceControlsProvider.overrideWithValue(NoopControls()),
    ]);
    addTearDown(c.dispose);
    c.read(lockProvider.notifier).lock();

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: PlayerGestures(child: SizedBox.expand()))),
    ));

    final box = tester.getRect(find.byType(PlayerGestures));
    await tester.drag(find.byType(PlayerGestures), const Offset(0, -200));
    await tester.pump();
    expect(engine.volume, 100); // unchanged default — locked ignored the drag
  });
}
```

- [ ] **Step 8: Run tests → PASS** (`flutter test test/ui/player/lock_state_test.dart test/ui/player/lock_gesture_test.dart`), full suite, `flutter analyze` clean.

- [ ] **Step 9: Commit**

```bash
git add lib/ui/player/state/lock_state.dart lib/ui/player/gestures/player_gestures.dart lib/ui/player/controls/controls_overlay.dart lib/ui/player/controls/bottom_bar.dart test/ui/player/lock_state_test.dart test/ui/player/lock_gesture_test.dart
git commit -m "feat: screen lock with hold-to-unlock; gestures+controls gated when locked"
```

---

### Task 3: Aspect modes (fit / fill / stretch)

**Files:**
- Create: `lib/ui/player/state/aspect_state.dart`
- Modify: `lib/ui/player/player_screen.dart` (Video `fit`), `lib/ui/player/controls/bottom_bar.dart` (aspect button)
- Test: `test/ui/player/aspect_state_test.dart`

**Interfaces:**
- Consumes: `settingsProvider` (`defaultAspectMode`).
- Produces: `enum AspectMode { fit, fill, stretch }`; `BoxFit boxFitFor(AspectMode)`; `AspectMode nextAspect(AspectMode)`; `AspectMode aspectFromSetting(String)`; `aspectModeProvider` → `NotifierProvider<AspectNotifier, AspectMode>` with `cycle()`.

- [ ] **Step 1: Write the test**

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/ui/player/state/aspect_state.dart';

void main() {
  test('nextAspect cycles fit->fill->stretch->fit', () {
    expect(nextAspect(AspectMode.fit), AspectMode.fill);
    expect(nextAspect(AspectMode.fill), AspectMode.stretch);
    expect(nextAspect(AspectMode.stretch), AspectMode.fit);
  });
  test('boxFitFor maps modes', () {
    expect(boxFitFor(AspectMode.fit), BoxFit.contain);
    expect(boxFitFor(AspectMode.fill), BoxFit.cover);
    expect(boxFitFor(AspectMode.stretch), BoxFit.fill);
  });
  test('aspectFromSetting parses, defaults to fit', () {
    expect(aspectFromSetting('fill'), AspectMode.fill);
    expect(aspectFromSetting('stretch'), AspectMode.stretch);
    expect(aspectFromSetting('16:9'), AspectMode.fit);
  });
}
```

- [ ] **Step 2: Run → FAIL**

- [ ] **Step 3: Implement `aspect_state.dart`**

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';

enum AspectMode { fit, fill, stretch }

BoxFit boxFitFor(AspectMode m) => switch (m) {
      AspectMode.fit => BoxFit.contain,
      AspectMode.fill => BoxFit.cover,
      AspectMode.stretch => BoxFit.fill,
    };

AspectMode nextAspect(AspectMode m) =>
    AspectMode.values[(m.index + 1) % AspectMode.values.length];

AspectMode aspectFromSetting(String s) => switch (s) {
      'fill' => AspectMode.fill,
      'stretch' => AspectMode.stretch,
      _ => AspectMode.fit,
    };

class AspectNotifier extends Notifier<AspectMode> {
  @override
  AspectMode build() => aspectFromSetting(ref.read(settingsProvider).defaultAspectMode);
  void cycle() => state = nextAspect(state);
}

final aspectModeProvider =
    NotifierProvider<AspectNotifier, AspectMode>(AspectNotifier.new);
```

- [ ] **Step 4: Apply the fit in `player_screen.dart`.** The `Video` widget gets `fit:` from the provider. Where the build returns `Video(controller: _controller!)`, change to:

```dart
Video(controller: _controller!, fit: boxFitFor(ref.watch(aspectModeProvider))),
```
Add `import 'state/aspect_state.dart';`. (Note: `_PlayerScreenState.build` already has `ref`; if the `Video` is built in a helper without `ref`, read it in `build` and pass down.)

- [ ] **Step 5: Activate the aspect button in `bottom_bar.dart`**

```dart
IconButton(
  color: Colors.white,
  icon: KivoIcon(KivoIcons.aspect, size: 24, color: Colors.white),
  onPressed: () => ref.read(aspectModeProvider.notifier).cycle(),
),
```
(Add `import '../state/aspect_state.dart';`.)

- [ ] **Step 6: Run → PASS**, full suite, `flutter analyze` clean.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/player/state/aspect_state.dart lib/ui/player/player_screen.dart lib/ui/player/controls/bottom_bar.dart test/ui/player/aspect_state_test.dart
git commit -m "feat: aspect modes (fit/fill/stretch) cycled by the aspect button"
```

---

### Task 4: Orientation / rotation

**Files:**
- Create: `lib/ui/player/state/orientation_state.dart`
- Modify: `lib/ui/player/controls/bottom_bar.dart` (rotate button), `lib/ui/player/player_screen.dart` (apply on enter)
- Test: `test/ui/player/orientation_state_test.dart`

**Interfaces:**
- Consumes: `deviceControlsProvider`, `DeviceOrientationLock` (Plan 1).
- Produces: `DeviceOrientationLock nextOrientation(DeviceOrientationLock)`; `orientationProvider` → `NotifierProvider<OrientationNotifier, DeviceOrientationLock>` with `cycle()` and `apply()`.

- [ ] **Step 1: Write the test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/platform/device_controls_provider.dart';
import 'package:kivo_player/platform/interfaces/device_controls.dart';
import 'package:kivo_player/ui/player/state/orientation_state.dart';

class RecCtrls implements DeviceControls {
  List<DeviceOrientationLock>? lastOrientation;
  @override Future<double> currentBrightness() async => 0.5;
  @override Future<void> setBrightness(double v) async {}
  @override Future<double> currentVolume() async => 0.5;
  @override Future<void> setSystemVolume(double v) async {}
  @override Future<void> setOrientation(List<DeviceOrientationLock> o) async => lastOrientation = o;
  @override Future<void> keepAwake(bool on) async {}
  @override Future<void> setImmersive(bool on) async {}
}

void main() {
  test('nextOrientation cycles landscape->portrait->auto->landscape', () {
    expect(nextOrientation(DeviceOrientationLock.landscape), DeviceOrientationLock.portrait);
    expect(nextOrientation(DeviceOrientationLock.portrait), DeviceOrientationLock.auto);
    expect(nextOrientation(DeviceOrientationLock.auto), DeviceOrientationLock.landscape);
  });
  test('cycle() updates state and applies to device controls', () {
    final ctrls = RecCtrls();
    final c = ProviderContainer(overrides: [deviceControlsProvider.overrideWithValue(ctrls)]);
    addTearDown(c.dispose);
    expect(c.read(orientationProvider), DeviceOrientationLock.landscape);
    c.read(orientationProvider.notifier).cycle();
    expect(c.read(orientationProvider), DeviceOrientationLock.portrait);
    expect(ctrls.lastOrientation, [DeviceOrientationLock.portrait]);
  });
}
```

- [ ] **Step 2: Run → FAIL**

- [ ] **Step 3: Implement `orientation_state.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../platform/device_controls_provider.dart';
import '../../../platform/interfaces/device_controls.dart';

DeviceOrientationLock nextOrientation(DeviceOrientationLock c) => switch (c) {
      DeviceOrientationLock.landscape => DeviceOrientationLock.portrait,
      DeviceOrientationLock.portrait => DeviceOrientationLock.auto,
      DeviceOrientationLock.auto => DeviceOrientationLock.landscape,
    };

class OrientationNotifier extends Notifier<DeviceOrientationLock> {
  @override
  DeviceOrientationLock build() => DeviceOrientationLock.landscape;

  void apply() => ref.read(deviceControlsProvider).setOrientation([state]);

  void cycle() {
    state = nextOrientation(state);
    apply();
  }
}

final orientationProvider =
    NotifierProvider<OrientationNotifier, DeviceOrientationLock>(OrientationNotifier.new);
```

- [ ] **Step 4: Activate the rotate button in `bottom_bar.dart`**

```dart
IconButton(
  color: Colors.white,
  icon: KivoIcon(KivoIcons.rotate, size: 24, color: Colors.white),
  onPressed: () => ref.read(orientationProvider.notifier).cycle(),
),
```
(Add `import '../state/orientation_state.dart';`.)

- [ ] **Step 5: Apply on enter in `player_screen.dart`.** In `initState`, the Plan 2 code calls `_deviceControls.setOrientation([DeviceOrientationLock.landscape])`. Keep forcing landscape on entry, but route it through the provider so the rotate button stays in sync — in the post-frame callback (where `ref` is valid) add:

```dart
ref.read(orientationProvider.notifier).apply();
```
(The provider's default is `landscape`, so `apply()` sets landscape — same behavior as before, but now the rotate button mutates the same state. You may remove the direct `_deviceControls.setOrientation([landscape])` line from initState since `apply()` replaces it; keep the `dispose` reset to `auto` as-is.)

- [ ] **Step 6: Run → PASS**, full suite, `flutter analyze` clean.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/player/state/orientation_state.dart lib/ui/player/controls/bottom_bar.dart lib/ui/player/player_screen.dart test/ui/player/orientation_state_test.dart
git commit -m "feat: orientation cycle (landscape/portrait/auto) via rotate button"
```

---

### Task 5: Persistent info overlay + info toggle

**Files:**
- Create: `lib/ui/player/controls/info_overlay.dart`
- Modify: `lib/ui/player/controls/top_bar.dart` (activate 👁 toggle), `lib/ui/player/player_screen.dart` (compose overlay)
- Test: `test/ui/player/info_overlay_test.dart`

**Interfaces:**
- Consumes: `settingsProvider` (`showInfoOverlay`, `infoOverlayContent`, `infoOverlayCorner`), `currentVideoProvider` (path), `positionProvider`, `durationProvider`, `fmtDuration`/`basenameOf` (Task 1), `KivoIcons.info`.
- Produces: `String infoOverlayText(String content, String name, Duration pos, Duration dur)`; `InfoOverlay` widget; `Alignment infoCornerAlignment(String corner)`.

- [ ] **Step 1: Write the test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/ui/player/controls/info_overlay.dart';
import '../../fakes/fakes.dart';

void main() {
  test('infoOverlayText formats name + time', () {
    expect(
      infoOverlayText('name_time', 'ep1.mkv', const Duration(seconds: 65), const Duration(minutes: 10)),
      'ep1.mkv   01:05 / 10:00',
    );
    expect(infoOverlayText('name', 'ep1.mkv', Duration.zero, Duration.zero), 'ep1.mkv');
  });

  testWidgets('InfoOverlay hidden when showInfoOverlay is false', (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final store = InMemorySettingsStore();
    await store.write(KivoSettings.defaults().copyWith(showInfoOverlay: false).toMap());
    final s = await SettingsService.load(store);
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
    ]);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(
        const VideoSession(path: '/v/ep1.mkv', queue: ['/v/ep1.mkv'], index: 0));

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: InfoOverlay())),
    ));
    expect(find.textContaining('ep1.mkv'), findsNothing);
  });
}
```

- [ ] **Step 2: Run → FAIL**

- [ ] **Step 3: Implement `info_overlay.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../player/engine/playback_provider.dart';
import '../../../player/open/video_source.dart';

String infoOverlayText(String content, String name, Duration pos, Duration dur) {
  switch (content) {
    case 'name':
      return name;
    case 'remaining':
      return '$name   -${fmtDuration(dur - pos)}';
    case 'name_time':
    default:
      return '$name   ${fmtDuration(pos)} / ${fmtDuration(dur)}';
  }
}

Alignment infoCornerAlignment(String corner) => switch (corner) {
      'tr' => Alignment.topRight,
      'bl' => Alignment.bottomLeft,
      'br' => Alignment.bottomRight,
      _ => Alignment.topLeft,
    };

class InfoOverlay extends ConsumerWidget {
  const InfoOverlay({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    if (!settings.showInfoOverlay) return const SizedBox.shrink();
    final name = basenameOf(ref.watch(currentVideoProvider)?.path);
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: infoCornerAlignment(settings.infoOverlayCorner),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: _InfoText(name: name, content: settings.infoOverlayContent),
          ),
        ),
      ),
    );
  }
}

// Isolated so only the time text rebuilds on each position tick.
class _InfoText extends ConsumerWidget {
  final String name;
  final String content;
  const _InfoText({required this.name, required this.content});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = ref.watch(positionProvider).value ?? Duration.zero;
    final dur = ref.watch(durationProvider).value ?? Duration.zero;
    return Text(
      infoOverlayText(content, name, pos, dur),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        shadows: [Shadow(color: Colors.black, blurRadius: 6)],
      ),
    );
  }
}
```

- [ ] **Step 4: Activate the info 👁 toggle in `top_bar.dart`.** Add an active `IconButton` (before the disabled cluster) that flips `showInfoOverlay` and persists it:

```dart
IconButton(
  color: Colors.white,
  icon: KivoIcon(KivoIcons.info, size: 24, color: Colors.white),
  onPressed: () {
    final s = ref.read(settingsProvider);
    ref.read(settingsProvider.notifier).set(s.copyWith(showInfoOverlay: !s.showInfoOverlay));
  },
),
```
(Add `import '../../../core/settings/settings_provider.dart';`.)

- [ ] **Step 5: Compose `InfoOverlay` in `player_screen.dart`.** Add it to the Stack ABOVE the video but it must be visible even when controls are hidden, so place it after `ControlsOverlay` (always-on; it self-hides via the setting). In the `Stack` children (after `Positioned.fill(child: ControlsOverlay())`), add:

```dart
const Positioned.fill(child: InfoOverlay()),
```
Add `import 'controls/info_overlay.dart';`. (Order: video → PlayerGestures → ControlsOverlay → InfoOverlay → HudOverlay → SpeedLadderOverlay. InfoOverlay is `IgnorePointer`, so it never blocks gestures.)

- [ ] **Step 6: Run → PASS** (`flutter test test/ui/player/info_overlay_test.dart`), full suite, `flutter analyze` clean.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/player/controls/info_overlay.dart lib/ui/player/controls/top_bar.dart lib/ui/player/player_screen.dart test/ui/player/info_overlay_test.dart
git commit -m "feat: persistent info overlay (name + time) with 👁 toggle (persisted)"
```

---

## Self-Review (spec coverage)

- **Lock** (spec §8 "Lock"): Task 2 — locks, hides controls/gestures, hold-to-unlock. ✓
- **Aspect modes** (spec §8 toolbar / §UX): Task 3 — fit/fill/stretch via `Video.fit`. Forced 16:9/4:3/original explicitly deferred (Global Constraints). ✓ (scoped)
- **Rotation** (spec §8; the 180° feedback): Task 4 — cycle landscape/portrait/auto; landscape maps to both sensor sides (fixes 180° flip). ✓
- **Persistent info overlay** (spec §8 "Overlay de info permanente"): Task 5 — name + actual/total, corner + content configurable, 👁 toggle persisted via settings. ✓
- **Placeholder scan:** none — every step has complete code. ✓
- **Type consistency:** `lockProvider`, `aspectModeProvider`/`AspectMode`/`boxFitFor`/`nextAspect`, `orientationProvider`/`nextOrientation`, `InfoOverlay`/`infoOverlayText`/`infoCornerAlignment`, `fmtDuration`/`basenameOf` consistent across tasks and tests. ✓

## Out of scope → Plan 3b
Thumbnail queue strip (sibling video thumbnails, tap-to-switch) and on-demand seek frame preview — both require video frame extraction (new dependency / 2nd mpv instance). Separate plan.
