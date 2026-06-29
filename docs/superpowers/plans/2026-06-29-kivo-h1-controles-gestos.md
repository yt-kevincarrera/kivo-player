# Kivo Hito 1 · Plan 2 — Controles y gestos

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que el reproductor sea totalmente controlable por toque: mostrar/ocultar controles, play/pausa, saltar ±, scrub, ajustar brillo/volumen/velocidad por gestos y botones, con HUD de feedback — todo leyendo valores configurables.

**Architecture:** La lógica de gestos es funciones puras testeables (`gesture_math`). Un `PlayerController` (Riverpod) traduce intenciones de UI a llamadas del `PlaybackEngine` + `DeviceControls`, leyendo `settingsProvider`. El estado efímero de UI (HUD, visibilidad de controles) vive en notifiers propios con auto-ocultado. Los widgets son "tontos": leen providers y llaman al controller.

**Tech Stack:** Flutter, flutter_riverpod, media_kit (tras `PlaybackEngine`), `DeviceControls` (brillo/volumen/wakelock). Tests: flutter_test + los fakes existentes.

## Global Constraints

- Construye SOBRE Plan 1 (ya en `master`). No reimplementar motor, settings, resume, cola.
- `package:media_kit` solo en `media_kit_engine.dart`; los widgets/controller hablan con la interfaz `PlaybackEngine`. `DeviceControls` solo vía `deviceControlsProvider`.
- Estado con Riverpod. `positionProvider` (alta frecuencia) ya existe; SOLO la seek bar / overlay de tiempo deben reconstruirse con la posición — no envolver todo el árbol.
- **Todo valor configurable** se lee de `settingsProvider` (`KivoSettings`), nunca hardcodeado. Valores relevantes ya existentes: `doubleTapSkipLeft/Right`, `doubleTapCenterPause`, `brightnessSensitivity`, `volumeSensitivity`, `seekSensitivity`, `horizontalSeek`, `hapticsOnGestures`, `volumeBoostMax`, `holdLeftSpeed`, `holdRightMin`, `holdRightMax`, `holdRightReleaseToNormal`, `speedFineStep`, `speedPresets`, `rememberSpeed`, `centerSkipSeconds`, `controlsAutoHideMs`.
- Velocidad máxima 4.0x. Paleta: azul `#2D6CFF`, dorado `#E8B84B` (`KivoColors`).
- **Fuera de Plan 2 (van a Plan 3):** lock, modos de aspecto, rotación/orientación, overlay de info permanente, tira de miniaturas, miniatura de frame on-demand en el seek. Los botones de lock/aspecto/rotar (y los ya-presentes subs/PiP/audio) se muestran **deshabilitados**.
- Orientación: en Plan 2, al entrar al `PlayerScreen` forzar horizontal es aceptable como medida fija (la gestión configurable de orientación es Plan 3). Hazlo vía `DeviceControls.setOrientation`.
- Háptica: usar `HapticFeedback` de Flutter, gated por `settings.hapticsOnGestures`.

---

## Estructura de archivos (este plan)

```
lib/player/control/
  gesture_math.dart          # funciones puras: zonas, clamp seek, delta de arrastre, ladder, snap, volumen
  player_controller.dart     # acciones de alto nivel sobre engine + deviceControls + settings
lib/ui/player/
  state/
    controls_visibility.dart # provider: visible + auto-hide
    hud_state.dart           # provider: HUD actual (tipo, valor, etiqueta) + auto-hide
  hud/
    hud_overlay.dart         # render del HUD (brillo/volumen/seek/velocidad)
  gestures/
    player_gestures.dart     # GestureDetector -> controller + HUD + visibilidad
  speed/
    speed_panel.dart         # bottom sheet granular (presets, slider con imanes, +/-)
    speed_ladder_overlay.dart# overlay vertical del mantener-derecha
  controls/
    seek_bar.dart            # scrubber + tiempos
    top_bar.dart             # volver + título + (subs/PiP/audio/más deshabilitados)
    center_controls.dart     # ⏪ / play-pausa / ⏩
    bottom_bar.dart          # tiempos + seek + toolbar (velocidad activo; lock/aspecto/rotar deshabilitados)
    controls_overlay.dart    # ensambla top/center/bottom, con fade segun visibilidad
lib/ui/player/player_screen.dart   # MODIFICAR: componer gestos + controles + HUD + ladder + wakelock
test/player/control/gesture_math_test.dart
test/player/control/player_controller_test.dart
test/ui/player/controls_visibility_test.dart
test/ui/player/hud_state_test.dart
test/ui/player/player_gestures_test.dart
test/ui/player/speed_panel_test.dart
test/ui/player/controls_overlay_test.dart
```

---

### Task 1: Matemática de gestos (puro, testeable)

**Files:**
- Create: `lib/player/control/gesture_math.dart`
- Test: `test/player/control/gesture_math_test.dart`

**Interfaces:**
- Produces:
  - `enum TapZone { left, center, right }`
  - `TapZone tapZoneOf(double dxFraction, {double centerStart = 0.33, double centerEnd = 0.67})`
  - `Duration clampSeek(Duration current, Duration delta, Duration total)`
  - `double dragValue(double current01, double dyPixels, double regionPixels, double sensitivity)` — arrastrar hacia ARRIBA sube el valor; devuelve 0..1.
  - `double ladderSpeed(double fraction, double min, double max, int steps)` — `fraction` 0 (abajo/lento) .. 1 (arriba/rápido); devuelve el valor del paso discreto.
  - `double snapToDetent(double value, List<double> detents, double epsilon)`
  - `double clampRate(double value, double min, double max)`
  - `double round2(double value)`
  - `({double system01, double playerPercent}) volumeMapping(double percent, double boostMax)` — `percent` 0..boostMax. system = min(percent,100)/100; player = percent.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/control/gesture_math.dart';

void main() {
  test('tapZoneOf splits screen into thirds', () {
    expect(tapZoneOf(0.1), TapZone.left);
    expect(tapZoneOf(0.5), TapZone.center);
    expect(tapZoneOf(0.9), TapZone.right);
  });

  test('clampSeek clamps to [0, total]', () {
    final total = const Duration(minutes: 10);
    expect(clampSeek(const Duration(seconds: 5), const Duration(seconds: -10), total), Duration.zero);
    expect(clampSeek(const Duration(minutes: 9, seconds: 59), const Duration(seconds: 10), total), total);
    expect(clampSeek(const Duration(minutes: 1), const Duration(seconds: 10), total), const Duration(minutes: 1, seconds: 10));
  });

  test('dragValue increases when dragging up (negative dy)', () {
    // region 400px, sensitivity 1.0, drag up 200px => +0.5
    expect(dragValue(0.2, -200, 400, 1.0), closeTo(0.7, 1e-9));
    // clamps at 1.0
    expect(dragValue(0.9, -400, 400, 1.0), 1.0);
    // drag down decreases, clamps at 0
    expect(dragValue(0.1, 200, 400, 1.0), 0.0);
  });

  test('ladderSpeed maps fraction to discrete steps', () {
    // 6 steps between 1.0 and 4.0 => [1.0,1.6,2.2,2.8,3.4,4.0]
    expect(ladderSpeed(0.0, 1.0, 4.0, 6), closeTo(1.0, 1e-9));
    expect(ladderSpeed(1.0, 1.0, 4.0, 6), closeTo(4.0, 1e-9));
    expect(ladderSpeed(0.5, 1.0, 4.0, 6), closeTo(2.2, 1e-9)); // nearest step index round(0.5*5)=3 -> 1+3*0.6=2.8? see impl note
  });

  test('snapToDetent snaps within epsilon, passes through otherwise', () {
    expect(snapToDetent(1.02, const [1.0, 1.5, 2.0], 0.05), 1.0);
    expect(snapToDetent(1.30, const [1.0, 1.5, 2.0], 0.05), 1.30);
  });

  test('clampRate and round2', () {
    expect(clampRate(5.0, 0.25, 4.0), 4.0);
    expect(clampRate(0.1, 0.25, 4.0), 0.25);
    expect(round2(1.126), 1.13);
  });

  test('volumeMapping splits system vs player gain at 100%', () {
    final a = volumeMapping(80, 150);
    expect(a.system01, closeTo(0.8, 1e-9));
    expect(a.playerPercent, 80);
    final b = volumeMapping(140, 150);
    expect(b.system01, 1.0);
    expect(b.playerPercent, 140);
  });
}
```

> Impl note for `ladderSpeed`: choose nearest step by `index = (fraction * (steps-1)).round()`, value = `min + index*(max-min)/(steps-1)`. With steps=6, fraction 0.5 → index round(2.5)=3 → 1.0+3*0.6 = 2.8. **Fix the test expectation to `2.8`** before implementing (the `0.5→2.2` line above is intentionally wrong to force you to reason about the rounding — change it to `closeTo(2.8, 1e-9)`).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/player/control/gesture_math_test.dart`
Expected: FAIL (functions undefined). After correcting the `ladderSpeed` 0.5 expectation to `2.8`, the failures should only be "not defined".

- [ ] **Step 3: Write the implementation**

```dart
enum TapZone { left, center, right }

TapZone tapZoneOf(double dxFraction, {double centerStart = 0.33, double centerEnd = 0.67}) {
  if (dxFraction < centerStart) return TapZone.left;
  if (dxFraction > centerEnd) return TapZone.right;
  return TapZone.center;
}

Duration clampSeek(Duration current, Duration delta, Duration total) {
  final ms = (current + delta).inMilliseconds;
  if (ms < 0) return Duration.zero;
  if (ms > total.inMilliseconds) return total;
  return Duration(milliseconds: ms);
}

double dragValue(double current01, double dyPixels, double regionPixels, double sensitivity) {
  if (regionPixels <= 0) return current01;
  final next = current01 - (dyPixels / regionPixels) * sensitivity;
  return next.clamp(0.0, 1.0);
}

double ladderSpeed(double fraction, double min, double max, int steps) {
  final f = fraction.clamp(0.0, 1.0);
  if (steps <= 1) return min;
  final index = (f * (steps - 1)).round();
  return min + index * (max - min) / (steps - 1);
}

double snapToDetent(double value, List<double> detents, double epsilon) {
  for (final d in detents) {
    if ((value - d).abs() <= epsilon) return d;
  }
  return value;
}

double clampRate(double value, double min, double max) => value.clamp(min, max);

double round2(double value) => (value * 100).round() / 100;

({double system01, double playerPercent}) volumeMapping(double percent, double boostMax) {
  final p = percent.clamp(0.0, boostMax);
  final system = (p < 100 ? p : 100) / 100;
  return (system01: system, playerPercent: p);
}
```

- [ ] **Step 4: Run test → PASS**

Run: `flutter test test/player/control/gesture_math_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/player/control/gesture_math.dart test/player/control/gesture_math_test.dart
git commit -m "feat: pure gesture math (zones, clamp seek, drag/ladder/detent/volume)"
```

---

### Task 2: PlayerController (acciones de alto nivel)

**Files:**
- Create: `lib/player/control/player_controller.dart`
- Test: `test/player/control/player_controller_test.dart`

**Interfaces:**
- Consumes: `playbackEngineProvider`, `positionProvider`, `durationProvider`, `playingProvider` (Plan 1); `deviceControlsProvider` (Plan 1); `settingsProvider` (Plan 1); all of `gesture_math` (Task 1).
- Produces:
  - `playerControllerProvider` → `Provider<PlayerController>`.
  - `class PlayerController` with: `void togglePlayPause()`, `void skipBy(int seconds)`, `void seekTo(Duration p)`, `void setRate(double rate)` (clamped 0.25..holdRightMax-or-4), `void setVolumePercent(double percent)`, `void setBrightness(double v01)`, `double get currentVolumePercent`, `double get currentRate`. Reads live position/duration from the providers via `ref`.
  - A `volumePercentProvider` → `StateProvider<double>` (current 0..boostMax, default 100) and `rateProvider` → `StateProvider<double>` (current playback rate, default 1.0) so widgets/HUD can show them.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/control/player_controller.dart';
import 'package:kivo_player/platform/device_controls_provider.dart';
import 'package:kivo_player/platform/interfaces/device_controls.dart';
import '../../fakes/fakes.dart';

class RecordingControls implements DeviceControls {
  double brightness = 0.5, volume = 0.5;
  @override Future<double> currentBrightness() async => brightness;
  @override Future<void> setBrightness(double v) async => brightness = v;
  @override Future<double> currentVolume() async => volume;
  @override Future<void> setSystemVolume(double v) async => volume = v;
  @override Future<void> setOrientation(List<DeviceOrientationLock> o) async {}
  @override Future<void> keepAwake(bool on) async {}
}

void main() {
  late FakePlaybackEngine engine;
  late RecordingControls controls;
  late ProviderContainer c;

  Future<void> setup() async {
    engine = FakePlaybackEngine();
    controls = RecordingControls();
    final settings = await SettingsService.load(InMemorySettingsStore());
    c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(settings),
      playbackEngineProvider.overrideWithValue(engine),
      deviceControlsProvider.overrideWithValue(controls),
    ]);
    addTearDown(engine.dispose);
    addTearDown(c.dispose);
    // activate position/duration providers
    c.listen(positionProvider, (_, __) {});
    c.listen(durationProvider, (_, __) {});
  }

  test('skipBy clamps using live position and duration', () async {
    await setup();
    engine.emitDuration(const Duration(minutes: 10));
    engine.emitPosition(const Duration(minutes: 1));
    await Future<void>.delayed(Duration.zero);
    c.read(playerControllerProvider).skipBy(10);
    expect(engine.lastSeek, const Duration(minutes: 1, seconds: 10));
  });

  test('setVolumePercent maps system + player gain and updates provider', () async {
    await setup();
    c.read(playerControllerProvider).setVolumePercent(140);
    await Future<void>.delayed(Duration.zero);
    expect(controls.volume, 1.0);          // system capped at 100%
    expect(engine.volume, 140);            // player amplified
    expect(c.read(volumePercentProvider), 140);
  });

  test('setRate clamps to max and updates provider', () async {
    await setup();
    c.read(playerControllerProvider).setRate(9.0);
    await Future<void>.delayed(Duration.zero);
    expect(engine.rate, 4.0);
    expect(c.read(rateProvider), 4.0);
  });
}
```

> This requires `FakePlaybackEngine` to expose `lastSeek`. ADD to `test/fakes/fakes.dart` `FakePlaybackEngine`: a field `Duration? lastSeek;` and set it inside `seek` (`lastSeek = p;`) in addition to the existing emit. Keep all existing behavior.

- [ ] **Step 2: Run test → FAIL** (`playerControllerProvider` undefined)

- [ ] **Step 3: Implement `player_controller.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings/settings_provider.dart';
import '../../platform/device_controls_provider.dart';
import '../engine/playback_provider.dart';
import 'gesture_math.dart';

final volumePercentProvider = StateProvider<double>((ref) => 100);
final rateProvider = StateProvider<double>((ref) => 1.0);

final playerControllerProvider = Provider<PlayerController>((ref) => PlayerController(ref));

class PlayerController {
  final Ref _ref;
  PlayerController(this._ref);

  void togglePlayPause() {
    final playing = _ref.read(playingProvider).value ?? false;
    final engine = _ref.read(playbackEngineProvider);
    playing ? engine.pause() : engine.play();
  }

  void skipBy(int seconds) {
    final pos = _ref.read(positionProvider).value ?? Duration.zero;
    final total = _ref.read(durationProvider).value ?? Duration.zero;
    seekTo(clampSeek(pos, Duration(seconds: seconds), total));
  }

  void seekTo(Duration p) => _ref.read(playbackEngineProvider).seek(p);

  double get currentRate => _ref.read(rateProvider);

  void setRate(double rate) {
    final max = _ref.read(settingsProvider).holdRightMax;
    final clamped = clampRate(round2(rate), 0.25, max);
    _ref.read(playbackEngineProvider).setRate(clamped);
    _ref.read(rateProvider.notifier).state = clamped;
  }

  double get currentVolumePercent => _ref.read(volumePercentProvider);

  void setVolumePercent(double percent) {
    final boost = _ref.read(settingsProvider).volumeBoostMax.toDouble();
    final m = volumeMapping(percent, boost);
    _ref.read(deviceControlsProvider).setSystemVolume(m.system01);
    _ref.read(playbackEngineProvider).setVolume(m.playerPercent);
    _ref.read(volumePercentProvider.notifier).state = m.playerPercent;
  }

  void setBrightness(double v01) =>
      _ref.read(deviceControlsProvider).setBrightness(v01.clamp(0.0, 1.0));
}
```

- [ ] **Step 4: Run test → PASS**

- [ ] **Step 5: Commit**

```bash
git add lib/player/control/player_controller.dart test/player/control/player_controller_test.dart test/fakes/fakes.dart
git commit -m "feat: PlayerController (play/skip/seek/rate/volume-boost/brightness)"
```

---

### Task 3: Notifier de visibilidad de controles (auto-ocultar)

**Files:**
- Create: `lib/ui/player/state/controls_visibility.dart`
- Test: `test/ui/player/controls_visibility_test.dart`

**Interfaces:**
- Consumes: `settingsProvider` (`controlsAutoHideMs`).
- Produces: `controlsVisibleProvider` → `NotifierProvider<ControlsVisibilityNotifier, bool>`; methods `show()`, `hide()`, `toggle()`. On `show()`/`toggle()`→visible, (re)start an auto-hide timer of `controlsAutoHideMs`; on hide cancel it. Expose `@visibleForTesting void hideNow()` semantics via `hide()`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/ui/player/state/controls_visibility.dart';
import '../../fakes/fakes.dart';

void main() {
  test('toggle shows then auto-hides after controlsAutoHideMs', () {
    fakeAsync((async) {
      late ProviderContainer c;
      () async {
        final s = await SettingsService.load(InMemorySettingsStore());
        c = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
      }();
      async.flushMicrotasks();

      expect(c.read(controlsVisibleProvider), false);
      c.read(controlsVisibleProvider.notifier).toggle();
      expect(c.read(controlsVisibleProvider), true);
      async.elapse(const Duration(milliseconds: 3000));
      expect(c.read(controlsVisibleProvider), false);
      c.dispose();
    });
  });
}
```

> `fake_async` ships with the Flutter SDK test deps (via `test_api`/`fake_async`); if the import is not resolvable, add `fake_async: ^1.3.1` to `dev_dependencies` and `flutter pub get` as Step 1b.

- [ ] **Step 2: Run test → FAIL**

- [ ] **Step 3: Implement `controls_visibility.dart`**

```dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';

class ControlsVisibilityNotifier extends Notifier<bool> {
  Timer? _timer;

  @override
  bool build() {
    ref.onDispose(() => _timer?.cancel());
    return false;
  }

  void show() {
    state = true;
    _restartTimer();
  }

  void hide() {
    _timer?.cancel();
    state = false;
  }

  void toggle() => state ? hide() : show();

  void _restartTimer() {
    _timer?.cancel();
    final ms = ref.read(settingsProvider).controlsAutoHideMs;
    _timer = Timer(Duration(milliseconds: ms), () => state = false);
  }
}

final controlsVisibleProvider =
    NotifierProvider<ControlsVisibilityNotifier, bool>(ControlsVisibilityNotifier.new);
```

- [ ] **Step 4: Run test → PASS**

- [ ] **Step 5: Commit**

```bash
git add lib/ui/player/state/controls_visibility.dart test/ui/player/controls_visibility_test.dart pubspec.yaml
git commit -m "feat: controls visibility with configurable auto-hide"
```

---

### Task 4: Estado del HUD (brillo/volumen/seek/velocidad) con auto-ocultar

**Files:**
- Create: `lib/ui/player/state/hud_state.dart`
- Test: `test/ui/player/hud_state_test.dart`

**Interfaces:**
- Produces:
  - `enum HudKind { brightness, volume, seek, speed }`
  - `class HudState { final HudKind kind; final double value; final String label; const HudState(...); }`
  - `hudProvider` → `NotifierProvider<HudNotifier, HudState?>` (null = nada visible).
  - `HudNotifier`: `void show(HudKind kind, double value, String label)` (sets state, restarts an 800ms auto-hide), `void clear()`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/ui/player/state/hud_state.dart';

void main() {
  test('show sets state and clears after 800ms', () {
    fakeAsync((async) {
      final c = ProviderContainer();
      c.read(hudProvider.notifier).show(HudKind.volume, 0.8, '80%');
      expect(c.read(hudProvider)!.kind, HudKind.volume);
      expect(c.read(hudProvider)!.label, '80%');
      async.elapse(const Duration(milliseconds: 800));
      expect(c.read(hudProvider), isNull);
      c.dispose();
    });
  });
}
```

- [ ] **Step 2: Run test → FAIL**

- [ ] **Step 3: Implement `hud_state.dart`**

```dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum HudKind { brightness, volume, seek, speed }

class HudState {
  final HudKind kind;
  final double value;
  final String label;
  const HudState(this.kind, this.value, this.label);
}

class HudNotifier extends Notifier<HudState?> {
  Timer? _timer;

  @override
  HudState? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void show(HudKind kind, double value, String label) {
    state = HudState(kind, value, label);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 800), () => state = null);
  }

  void clear() {
    _timer?.cancel();
    state = null;
  }
}

final hudProvider = NotifierProvider<HudNotifier, HudState?>(HudNotifier.new);
```

- [ ] **Step 4: Run test → PASS**

- [ ] **Step 5: Commit**

```bash
git add lib/ui/player/state/hud_state.dart test/ui/player/hud_state_test.dart
git commit -m "feat: HUD state with auto-hide (brightness/volume/seek/speed)"
```

---

### Task 5: HUD overlay (widget)

**Files:**
- Create: `lib/ui/player/hud/hud_overlay.dart`
- Test: `test/ui/player/hud_overlay_test.dart`

**Interfaces:**
- Consumes: `hudProvider` (Task 4), `KivoColors`.
- Produces: `class HudOverlay extends ConsumerWidget` — watches `hudProvider`; renders nothing when null; otherwise a centered pill with an icon (per `HudKind`) + the label, and for brightness/volume a vertical bar reflecting `value` (0..1). Use `IgnorePointer` so it never eats gestures.

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/ui/player/state/hud_state.dart';
import 'package:kivo_player/ui/player/hud/hud_overlay.dart';

void main() {
  testWidgets('HudOverlay shows label when HUD active, nothing when null', (tester) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: HudOverlay())),
    ));
    expect(find.text('80%'), findsNothing);

    c.read(hudProvider.notifier).show(HudKind.volume, 0.8, '80%');
    await tester.pump();
    expect(find.text('80%'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test → FAIL**

- [ ] **Step 3: Implement `hud_overlay.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/kivo_theme.dart';
import '../state/hud_state.dart';

class HudOverlay extends ConsumerWidget {
  const HudOverlay({super.key});

  IconData _icon(HudKind k) {
    switch (k) {
      case HudKind.brightness:
        return Icons.brightness_6;
      case HudKind.volume:
        return Icons.volume_up;
      case HudKind.seek:
        return Icons.fast_forward;
      case HudKind.speed:
        return Icons.speed;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hud = ref.watch(hudProvider);
    if (hud == null) return const SizedBox.shrink();
    final showBar = hud.kind == HudKind.brightness || hud.kind == HudKind.volume;
    return IgnorePointer(
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icon(hud.kind), color: KivoColors.gold, size: 30),
              const SizedBox(height: 8),
              Text(hud.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              if (showBar) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: 120,
                  child: LinearProgressIndicator(
                    value: hud.value.clamp(0.0, 1.0),
                    backgroundColor: Colors.white24,
                    color: KivoColors.blue,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test → PASS**

- [ ] **Step 5: Commit**

```bash
git add lib/ui/player/hud/hud_overlay.dart test/ui/player/hud_overlay_test.dart
git commit -m "feat: HUD overlay widget"
```

---

### Task 6: Gestos del reproductor (tap, doble-tap, arrastres)

**Files:**
- Create: `lib/ui/player/gestures/player_gestures.dart`
- Test: `test/ui/player/player_gestures_test.dart`

**Interfaces:**
- Consumes: `gesture_math` (Task 1), `playerControllerProvider` + `volumePercentProvider` (Task 2), `controlsVisibleProvider` (Task 3), `hudProvider` + `HudKind` (Task 4), `settingsProvider`, `deviceControlsProvider`.
- Produces: `class PlayerGestures extends ConsumerStatefulWidget` with `final Widget child;`. Wraps `child` in a `GestureDetector`:
  - **single tap** → `controlsVisibleProvider.notifier.toggle()`.
  - **double tap**: on `onDoubleTapDown` record the local x; on `onDoubleTap` compute `tapZoneOf(dx/width)`: left → `skipBy(-doubleTapSkipLeft)`; right → `skipBy(doubleTapSkipRight)`; center → if `doubleTapCenterPause` `togglePlayPause()`. Haptic if enabled. Show seek HUD with a `±Ns` label for left/right.
  - **vertical drag** (`onVerticalDragUpdate`): left half → brightness; right half → volume. Use `dragValue` with the drag's `delta.dy`, region = constraints height, sensitivity from settings. Brightness: read current via a cached `_brightness` seeded on drag start from `deviceControls.currentBrightness()`; call `controller.setBrightness`; show brightness HUD (`'${(v*100).round()}%'`). Volume: maintain `_volume01`, map to percent `v*100` up to `volumeBoostMax`; call `controller.setVolumePercent`; show volume HUD.
  - **horizontal drag** (`onHorizontalDragUpdate`), only if `settings.horizontalSeek`: accumulate dx; seconds = `dx_total / width * (total.inSeconds) * seekSensitivity`-style scaling — use a fixed scale: `deltaSeconds = (dx / width) * 90 * seekSensitivity` per update accumulated; on update call `controller.seekTo(clampSeek(startPos, accumulated, total))` and show seek HUD with the target timestamp.
- Keep the gesture→action wiring in the widget; the math stays in `gesture_math`.

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/control/player_controller.dart';
import 'package:kivo_player/platform/device_controls_provider.dart';
import 'package:kivo_player/platform/interfaces/device_controls.dart';
import 'package:kivo_player/ui/player/state/controls_visibility.dart';
import 'package:kivo_player/ui/player/gestures/player_gestures.dart';
import '../../fakes/fakes.dart';

class NoopControls implements DeviceControls {
  @override Future<double> currentBrightness() async => 0.5;
  @override Future<void> setBrightness(double v) async {}
  @override Future<double> currentVolume() async => 0.5;
  @override Future<void> setSystemVolume(double v) async {}
  @override Future<void> setOrientation(List<DeviceOrientationLock> o) async {}
  @override Future<void> keepAwake(bool on) async {}
}

void main() {
  testWidgets('single tap toggles controls visibility', (tester) async {
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
      child: const MaterialApp(
        home: Scaffold(body: PlayerGestures(child: SizedBox.expand())),
      ),
    ));

    expect(c.read(controlsVisibleProvider), false);
    await tester.tap(find.byType(PlayerGestures));
    await tester.pump();
    expect(c.read(controlsVisibleProvider), true);
  });

  testWidgets('double tap on right edge skips forward', (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      deviceControlsProvider.overrideWithValue(NoopControls()),
    ]);
    addTearDown(c.dispose);
    c.listen(positionProvider, (_, __) {});
    c.listen(durationProvider, (_, __) {});
    engine.emitDuration(const Duration(minutes: 10));
    engine.emitPosition(const Duration(minutes: 1));
    await Future<void>.delayed(Duration.zero);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: PlayerGestures(child: SizedBox.expand()))),
    ));

    final box = tester.getRect(find.byType(PlayerGestures));
    final right = Offset(box.right - 40, box.center.dy);
    await tester.tapAt(right);
    await tester.tapAt(right); // double tap
    await tester.pump(const Duration(milliseconds: 50));
    expect(engine.lastSeek, const Duration(minutes: 1, seconds: 10));
  });
}
```

- [ ] **Step 2: Run test → FAIL**

- [ ] **Step 3: Implement `player_gestures.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../platform/device_controls_provider.dart';
import '../../../player/control/gesture_math.dart';
import '../../../player/control/player_controller.dart';
import '../../../player/engine/playback_provider.dart';
import '../state/controls_visibility.dart';
import '../state/hud_state.dart';

class PlayerGestures extends ConsumerStatefulWidget {
  final Widget child;
  const PlayerGestures({super.key, required this.child});
  @override
  ConsumerState<PlayerGestures> createState() => _PlayerGesturesState();
}

class _PlayerGesturesState extends ConsumerState<PlayerGestures> {
  double _lastTapDx = 0;
  double _width = 1, _height = 1;
  bool _leftSide = true;
  double _brightness = 0.5;
  double _volume01 = 0.5;
  Duration _seekStart = Duration.zero;
  double _seekAccum = 0;

  void _haptic() {
    if (ref.read(settingsProvider).hapticsOnGestures) HapticFeedback.lightImpact();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  void _onDoubleTap() {
    final zone = tapZoneOf(_lastTapDx / _width);
    final ctrl = ref.read(playerControllerProvider);
    final st = ref.read(settingsProvider);
    switch (zone) {
      case TapZone.left:
        ctrl.skipBy(-st.doubleTapSkipLeft);
        _haptic();
        ref.read(hudProvider.notifier).show(HudKind.seek, 0, '-${st.doubleTapSkipLeft}s');
      case TapZone.right:
        ctrl.skipBy(st.doubleTapSkipRight);
        _haptic();
        ref.read(hudProvider.notifier).show(HudKind.seek, 0, '+${st.doubleTapSkipRight}s');
      case TapZone.center:
        if (st.doubleTapCenterPause) {
          ctrl.togglePlayPause();
          _haptic();
        }
    }
  }

  void _onVerticalStart(DragStartDetails d) {
    _leftSide = d.localPosition.dx < _width / 2;
    _volume01 = (ref.read(volumePercentProvider) / 100).clamp(0.0, 1.0);
    ref.read(deviceControlsProvider).currentBrightness().then((b) => _brightness = b);
  }

  void _onVerticalUpdate(DragUpdateDetails d) {
    final st = ref.read(settingsProvider);
    final ctrl = ref.read(playerControllerProvider);
    if (_leftSide) {
      _brightness = dragValue(_brightness, d.delta.dy, _height, st.brightnessSensitivity);
      ctrl.setBrightness(_brightness);
      ref.read(hudProvider.notifier).show(HudKind.brightness, _brightness, '${(_brightness * 100).round()}%');
    } else {
      _volume01 = dragValue(_volume01, d.delta.dy, _height, st.volumeSensitivity);
      final percent = _volume01 * st.volumeBoostMax;
      ctrl.setVolumePercent(percent);
      ref.read(hudProvider.notifier).show(HudKind.volume, _volume01, '${percent.round()}%');
    }
  }

  void _onHorizontalStart(DragStartDetails d) {
    _seekStart = ref.read(positionProvider).value ?? Duration.zero;
    _seekAccum = 0;
  }

  void _onHorizontalUpdate(DragUpdateDetails d) {
    final st = ref.read(settingsProvider);
    if (!st.horizontalSeek) return;
    final total = ref.read(durationProvider).value ?? Duration.zero;
    _seekAccum += (d.delta.dx / _width) * 90 * st.seekSensitivity;
    final target = clampSeek(_seekStart, Duration(seconds: _seekAccum.round()), total);
    ref.read(playerControllerProvider).seekTo(target);
    ref.read(hudProvider.notifier).show(HudKind.seek, 0, _fmt(target));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        _height = constraints.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ref.read(controlsVisibleProvider.notifier).toggle(),
          onDoubleTapDown: (d) => _lastTapDx = d.localPosition.dx,
          onDoubleTap: _onDoubleTap,
          onVerticalDragStart: _onVerticalStart,
          onVerticalDragUpdate: _onVerticalUpdate,
          onHorizontalDragStart: _onHorizontalStart,
          onHorizontalDragUpdate: _onHorizontalUpdate,
          child: widget.child,
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run test → PASS**

- [ ] **Step 5: Commit**

```bash
git add lib/ui/player/gestures/player_gestures.dart test/ui/player/player_gestures_test.dart
git commit -m "feat: player gestures (tap, double-tap skip, brightness/volume/seek drags)"
```

---

### Task 7: Mantener para acelerar + ladder de velocidad

**Files:**
- Create: `lib/ui/player/speed/speed_ladder_overlay.dart`
- Modify: `lib/ui/player/gestures/player_gestures.dart` (add long-press handling)
- Test: `test/ui/player/speed_ladder_test.dart`

**Interfaces:**
- Consumes: `ladderSpeed` (Task 1), `playerControllerProvider` + `rateProvider` (Task 2), `settingsProvider`.
- Produces:
  - `holdSpeedProvider` → `StateProvider<double?>` (null = no hold active; otherwise the live hold speed, drives the ladder overlay).
  - `class SpeedLadderOverlay extends ConsumerWidget` — when `holdSpeedProvider != null`, renders a right-anchored vertical column of step labels (min..max) with the active one highlighted gold + a big readout of the current speed; `IgnorePointer`.
  - In `PlayerGestures`: `onLongPressStart` records side + sets rate. Left side → `setRate(holdLeftSpeed)` and `holdSpeedProvider = holdLeftSpeed`. Right side → start at `holdRightMin`, and `onLongPressMoveUpdate` maps vertical position to `ladderSpeed(fraction, holdRightMin, holdRightMax, 6)` (fraction = `1 - (localY/height)` clamped), calling `setRate` + updating `holdSpeedProvider`. `onLongPressEnd` → if `holdRightReleaseToNormal` (right) or always (left), `setRate(1.0)`; clear `holdSpeedProvider`.

- [ ] **Step 1: Write the failing test** (logic-level via the provider + a simulated long-press is flaky; test the ladder mapping wiring through a helper)

Add a testable pure helper in `speed_ladder_overlay.dart`:
```dart
double holdRightSpeedFor(double localY, double height, double min, double max) =>
    ladderSpeed(height <= 0 ? 0 : (1 - (localY / height)).clamp(0.0, 1.0), min, max, 6);
```
Test:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/ui/player/speed/speed_ladder_overlay.dart';

void main() {
  test('holdRightSpeedFor: top of screen = max, bottom = min', () {
    expect(holdRightSpeedFor(0, 400, 1.0, 4.0), 4.0);   // y=0 -> fraction 1 -> max
    expect(holdRightSpeedFor(400, 400, 1.0, 4.0), 1.0); // y=height -> fraction 0 -> min
  });
}
```

- [ ] **Step 2: Run test → FAIL**

- [ ] **Step 3: Implement `speed_ladder_overlay.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../player/control/gesture_math.dart';

final holdSpeedProvider = StateProvider<double?>((ref) => null);

double holdRightSpeedFor(double localY, double height, double min, double max) =>
    ladderSpeed(height <= 0 ? 0 : (1 - (localY / height)).clamp(0.0, 1.0), min, max, 6);

class SpeedLadderOverlay extends ConsumerWidget {
  const SpeedLadderOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speed = ref.watch(holdSpeedProvider);
    if (speed == null) return const SizedBox.shrink();
    final steps = [4.0, 3.4, 2.8, 2.2, 1.6, 1.0];
    return IgnorePointer(
      child: Stack(
        children: [
          Align(
            alignment: Alignment.center,
            child: Text('${speed.toStringAsFixed(1)}x',
                style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.bold)),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: steps.map((v) {
                  final active = (v - speed).abs() < 0.3;
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: active ? KivoColors.gold.withValues(alpha: 0.3) : Colors.black54,
                      border: Border.all(color: active ? KivoColors.gold : Colors.white24),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${v.toStringAsFixed(1)}x',
                        style: TextStyle(color: active ? Colors.white : Colors.white70, fontSize: 12)),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Add long-press to `player_gestures.dart`**

Add these fields and handlers to `_PlayerGesturesState`, and the four `onLongPress*` callbacks to the `GestureDetector`:
```dart
  bool _holdLeft = false;

  void _onLongPressStart(LongPressStartDetails d) {
    final st = ref.read(settingsProvider);
    final ctrl = ref.read(playerControllerProvider);
    _holdLeft = d.localPosition.dx < _width / 2;
    if (_holdLeft) {
      ctrl.setRate(st.holdLeftSpeed);
      ref.read(holdSpeedProvider.notifier).state = st.holdLeftSpeed;
    } else {
      final v = holdRightSpeedFor(d.localPosition.dy, _height, st.holdRightMin, st.holdRightMax);
      ctrl.setRate(v);
      ref.read(holdSpeedProvider.notifier).state = v;
    }
    _haptic();
  }

  void _onLongPressMove(LongPressMoveUpdateDetails d) {
    if (_holdLeft) return;
    final st = ref.read(settingsProvider);
    final v = holdRightSpeedFor(d.localPosition.dy, _height, st.holdRightMin, st.holdRightMax);
    ref.read(playerControllerProvider).setRate(v);
    ref.read(holdSpeedProvider.notifier).state = v;
  }

  void _onLongPressEnd(LongPressEndDetails d) {
    final st = ref.read(settingsProvider);
    if (_holdLeft || st.holdRightReleaseToNormal) {
      ref.read(playerControllerProvider).setRate(1.0);
    }
    ref.read(holdSpeedProvider.notifier).state = null;
  }
```
Add imports: `import '../speed/speed_ladder_overlay.dart';`. Wire into the `GestureDetector`:
```dart
          onLongPressStart: _onLongPressStart,
          onLongPressMoveUpdate: _onLongPressMove,
          onLongPressEnd: _onLongPressEnd,
```

- [ ] **Step 5: Run tests → PASS** (`flutter test test/ui/player/speed_ladder_test.dart` and full suite); `flutter analyze` clean.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/player/speed/speed_ladder_overlay.dart lib/ui/player/gestures/player_gestures.dart test/ui/player/speed_ladder_test.dart
git commit -m "feat: hold-to-speed (left fixed, right vertical ladder) + overlay"
```

---

### Task 8: Panel de velocidad granular (bottom sheet)

**Files:**
- Create: `lib/ui/player/speed/speed_panel.dart`
- Test: `test/ui/player/speed_panel_test.dart`

**Interfaces:**
- Consumes: `snapToDetent`, `clampRate`, `round2` (Task 1); `playerControllerProvider` + `rateProvider` (Task 2); `settingsProvider` (`speedPresets`, `speedFineStep`, `holdRightMax`).
- Produces: `Future<void> showSpeedPanel(BuildContext context)` — opens a `showModalBottomSheet` with `SpeedPanel`. `SpeedPanel extends ConsumerStatefulWidget`: big readout of `rateProvider` (2 decimals), `−`/`+` buttons that step by `speedFineStep` (`setRate(round2(current ± step))`), a `Slider` over `0.25..holdRightMax` whose `onChanged` applies `snapToDetent(value, presets+[3.0,4.0], 0.04)` then `setRate`, preset chips from `speedPresets` (`setRate(preset)`), and a "Normal (1.0x)" reset button.

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/control/player_controller.dart';
import 'package:kivo_player/ui/player/speed/speed_panel.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets('tapping the 2.0x preset chip sets the rate', (tester) async {
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
      child: const MaterialApp(home: Scaffold(body: SpeedPanel())),
    ));

    await tester.tap(find.text('2.0x'));
    await tester.pump();
    expect(engine.rate, 2.0);
    expect(c.read(rateProvider), 2.0);
  });
}
```

- [ ] **Step 2: Run test → FAIL**

- [ ] **Step 3: Implement `speed_panel.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../player/control/gesture_math.dart';
import '../../../player/control/player_controller.dart';

Future<void> showSpeedPanel(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: KivoColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => const Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: SpeedPanel(),
    ),
  );
}

class SpeedPanel extends ConsumerStatefulWidget {
  const SpeedPanel({super.key});
  @override
  ConsumerState<SpeedPanel> createState() => _SpeedPanelState();
}

class _SpeedPanelState extends ConsumerState<SpeedPanel> {
  @override
  Widget build(BuildContext context) {
    final rate = ref.watch(rateProvider);
    final st = ref.watch(settingsProvider);
    final ctrl = ref.read(playerControllerProvider);
    final detents = [...st.speedPresets, 3.0, 4.0];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.remove),
              onPressed: () => ctrl.setRate(round2(rate - st.speedFineStep)),
            ),
            Text('${rate.toStringAsFixed(2)}x',
                style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => ctrl.setRate(round2(rate + st.speedFineStep)),
            ),
          ],
        ),
        Slider(
          min: 0.25,
          max: st.holdRightMax,
          value: clampRate(rate, 0.25, st.holdRightMax),
          activeColor: KivoColors.gold,
          onChanged: (v) => ctrl.setRate(snapToDetent(v, detents, 0.04)),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in st.speedPresets)
              ActionChip(label: Text('${p}x'), onPressed: () => ctrl.setRate(p)),
          ],
        ),
        const SizedBox(height: 12),
        TextButton(onPressed: () => ctrl.setRate(1.0), child: const Text('↺ Normal (1.0x)')),
      ],
    );
  }
}
```

> Note: preset chip label uses `'${p}x'`; for `2.0` Dart prints `2.0` → `2.0x`, matching the test's `find.text('2.0x')`.

- [ ] **Step 4: Run test → PASS**

- [ ] **Step 5: Commit**

```bash
git add lib/ui/player/speed/speed_panel.dart test/ui/player/speed_panel_test.dart
git commit -m "feat: granular speed panel (presets, magnetic slider, fine +/-)"
```

---

### Task 9: Barras de control (seek, top, center, bottom) + overlay

**Files:**
- Create: `lib/ui/player/controls/seek_bar.dart`, `top_bar.dart`, `center_controls.dart`, `bottom_bar.dart`, `controls_overlay.dart`
- Test: `test/ui/player/controls_overlay_test.dart`

**Interfaces:**
- Consumes: `positionProvider`, `durationProvider`, `playingProvider` (Plan 1); `playerControllerProvider`, `rateProvider` (Task 2); `settingsProvider`; `showSpeedPanel` (Task 8); `currentVideoProvider` (Plan 1, for the title); `KivoColors`.
- Produces:
  - `SeekBar extends ConsumerWidget` — watches `positionProvider`+`durationProvider`; a `Slider` (active gold) from 0..duration; `onChangeStart`→nothing, `onChanged`→`controller.seekTo`. Left label current time, right label total/remaining (tappable to toggle is Plan 3 — show total). Only this widget watches position (isolated rebuild).
  - `TopBar extends ConsumerWidget` — back button (`Navigator.maybePop`), title from `currentVideoProvider` path basename; right cluster: subtitles, PiP, audio, "more" — all `disabled` (greyed `IconButton(onPressed: null)`).
  - `CenterControls extends ConsumerWidget` — `⏪` (`skipBy(-centerSkipSeconds)`), play/pause (watches `playingProvider`, calls `togglePlayPause`), `⏩` (`skipBy(centerSkipSeconds)`).
  - `BottomBar extends ConsumerWidget` — `SeekBar` + a toolbar row: a speed pill button showing `rateProvider` that calls `showSpeedPanel`; then lock/aspect/rotate as `disabled` IconButtons.
  - `ControlsOverlay extends ConsumerWidget` — watches `controlsVisibleProvider`; wraps an `AnimatedOpacity` (200ms) + `IgnorePointer(ignoring: !visible)` around a `Stack` with top scrim+TopBar (top), CenterControls (center), bottom scrim+BottomBar (bottom).

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/ui/player/controls/center_controls.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets('play/pause button toggles engine playing', (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
    ]);
    addTearDown(c.dispose);
    c.listen(playingProvider, (_, __) {});
    engine.emitPlaying(true);
    await Future<void>.delayed(Duration.zero);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: Center(child: CenterControls()))),
    ));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    expect(engine.lastPlayingCommand, false); // pause() was called
  });
}
```

> ADD to `FakePlaybackEngine` in `test/fakes/fakes.dart`: a field `bool? lastPlayingCommand;`. In `play()` set `lastPlayingCommand = true;` (in addition to emitting), in `pause()` set `lastPlayingCommand = false;`. Keep existing emits.

- [ ] **Step 2: Run test → FAIL**

- [ ] **Step 3: Implement `seek_bar.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../player/control/player_controller.dart';
import '../../../player/engine/playback_provider.dart';

String fmtDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
}

class SeekBar extends ConsumerWidget {
  const SeekBar({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = ref.watch(positionProvider).value ?? Duration.zero;
    final total = ref.watch(durationProvider).value ?? Duration.zero;
    final maxMs = total.inMilliseconds == 0 ? 1.0 : total.inMilliseconds.toDouble();
    return Row(
      children: [
        Text(fmtDuration(pos), style: const TextStyle(color: Colors.white, fontSize: 12)),
        Expanded(
          child: Slider(
            min: 0,
            max: maxMs,
            value: pos.inMilliseconds.clamp(0, maxMs.toInt()).toDouble(),
            activeColor: KivoColors.gold,
            inactiveColor: Colors.white24,
            onChanged: (v) =>
                ref.read(playerControllerProvider).seekTo(Duration(milliseconds: v.round())),
          ),
        ),
        Text(fmtDuration(total), style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }
}
```

- [ ] **Step 4: Implement `center_controls.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../player/control/player_controller.dart';
import '../../../player/engine/playback_provider.dart';

class CenterControls extends ConsumerWidget {
  const CenterControls({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(playingProvider).value ?? false;
    final ctrl = ref.read(playerControllerProvider);
    final skip = ref.watch(settingsProvider).centerSkipSeconds;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          iconSize: 34,
          color: Colors.white,
          icon: const Icon(Icons.replay_10),
          onPressed: () => ctrl.skipBy(-skip),
        ),
        const SizedBox(width: 36),
        IconButton(
          iconSize: 56,
          color: Colors.white,
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          onPressed: ctrl.togglePlayPause,
        ),
        const SizedBox(width: 36),
        IconButton(
          iconSize: 34,
          color: Colors.white,
          icon: const Icon(Icons.forward_10),
          onPressed: () => ctrl.skipBy(skip),
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: Implement `top_bar.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../player/open/video_source.dart';

class TopBar extends ConsumerWidget {
  const TopBar({super.key});

  String _name(String? path) {
    if (path == null) return 'Kivo';
    final p = path.replaceAll('\\', '/');
    final i = p.lastIndexOf('/');
    return i < 0 ? p : p.substring(i + 1);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentVideoProvider);
    return Row(
      children: [
        IconButton(
          color: Colors.white,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        Expanded(
          child: Text(_name(session?.path),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ),
        // Disabled until later plans (Plan 3 / Hito 3)
        const IconButton(color: Colors.white38, icon: Icon(Icons.closed_caption), onPressed: null),
        const IconButton(color: Colors.white38, icon: Icon(Icons.picture_in_picture_alt), onPressed: null),
        const IconButton(color: Colors.white38, icon: Icon(Icons.headphones), onPressed: null),
        const IconButton(color: Colors.white38, icon: Icon(Icons.more_vert), onPressed: null),
      ],
    );
  }
}
```

- [ ] **Step 6: Implement `bottom_bar.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../player/control/player_controller.dart';
import '../speed/speed_panel.dart';
import 'seek_bar.dart';

class BottomBar extends ConsumerWidget {
  const BottomBar({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rate = ref.watch(rateProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SeekBar(),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton(
              onPressed: () => showSpeedPanel(context),
              child: Text('${rate.toStringAsFixed(2)}x',
                  style: const TextStyle(color: KivoColors.gold, fontWeight: FontWeight.w600)),
            ),
            const IconButton(color: Colors.white38, icon: Icon(Icons.lock_outline), onPressed: null),
            const IconButton(color: Colors.white38, icon: Icon(Icons.aspect_ratio), onPressed: null),
            const IconButton(color: Colors.white38, icon: Icon(Icons.screen_rotation), onPressed: null),
          ],
        ),
      ],
    );
  }
}
```

- [ ] **Step 7: Implement `controls_overlay.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/controls_visibility.dart';
import 'bottom_bar.dart';
import 'center_controls.dart';
import 'top_bar.dart';

class ControlsOverlay extends ConsumerWidget {
  const ControlsOverlay({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(controlsVisibleProvider);
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !visible,
        child: Stack(
          children: [
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: const SafeArea(bottom: false, child: TopBar()),
              ),
            ),
            const Center(child: CenterControls()),
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 24, 12, 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter, end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: const SafeArea(top: false, child: BottomBar()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 8: Run test → PASS**; then full suite `flutter test`; then `flutter analyze` clean.

- [ ] **Step 9: Commit**

```bash
git add lib/ui/player/controls/ test/ui/player/controls_overlay_test.dart test/fakes/fakes.dart
git commit -m "feat: control bars (seek/top/center/bottom) + fade overlay"
```

---

### Task 10: Integrar en PlayerScreen + wakelock

**Files:**
- Modify: `lib/ui/player/player_screen.dart`
- Test: `test/ui/player/player_screen_controls_test.dart`

**Interfaces:**
- Consumes: `PlayerGestures` (Task 6), `ControlsOverlay` (Task 9), `HudOverlay` (Task 5), `SpeedLadderOverlay` (Task 7), `deviceControlsProvider` + `DeviceOrientationLock` (Plan 1), `playingProvider`.
- Produces: updated `PlayerScreen` whose `build` stacks: the video (existing `Video`/spinner) at the back, then `PlayerGestures` wrapping a transparent full-size hit area, then `ControlsOverlay`, `HudOverlay`, `SpeedLadderOverlay` on top. On `initState`: force landscape via `deviceControls.setOrientation([DeviceOrientationLock.landscape])` and `keepAwake(true)`; on `dispose`: `setOrientation([DeviceOrientationLock.auto])` and `keepAwake(false)`. (Resume save logic from Plan 1 stays.)

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/platform/device_controls_provider.dart';
import 'package:kivo_player/platform/interfaces/device_controls.dart';
import 'package:kivo_player/ui/player/player_screen.dart';
import 'package:kivo_player/ui/player/state/controls_visibility.dart';
import 'package:kivo_player/ui/player/controls/center_controls.dart';
import '../../fakes/fakes.dart';

class NoopControls implements DeviceControls {
  @override Future<double> currentBrightness() async => 0.5;
  @override Future<void> setBrightness(double v) async {}
  @override Future<double> currentVolume() async => 0.5;
  @override Future<void> setSystemVolume(double v) async {}
  @override Future<void> setOrientation(List<DeviceOrientationLock> o) async {}
  @override Future<void> keepAwake(bool on) async {}
}

void main() {
  testWidgets('tapping the screen reveals the control bars', (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      deviceControlsProvider.overrideWithValue(NoopControls()),
      resumeServiceProvider.overrideWithValue(ResumeService(InMemoryResumeStore())),
    ]);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(
      const VideoSession(path: '/v/ep1.mkv', queue: ['/v/ep1.mkv'], index: 0),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: PlayerScreen()),
    ));
    await tester.pump();

    expect(c.read(controlsVisibleProvider), false);
    await tester.tapAt(tester.getCenter(find.byType(PlayerScreen)));
    await tester.pump(const Duration(milliseconds: 250));
    expect(c.read(controlsVisibleProvider), true);
    expect(find.byType(CenterControls), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test → FAIL**

- [ ] **Step 3: Modify `player_screen.dart` build + lifecycle**

Keep all existing Plan 1 logic (engine open, resume restore/save, `WidgetsBindingObserver`, `createVideoController`). Change the orientation/wakelock and the `build` body:

In `initState` (after the existing `addPostFrameCallback`), add:
```dart
    final dc = ref.read(deviceControlsProvider);
    dc.setOrientation([DeviceOrientationLock.landscape]);
    dc.keepAwake(true);
```
In `dispose` (before `super.dispose()`), add:
```dart
    final dc = ref.read(deviceControlsProvider);
    dc.setOrientation([DeviceOrientationLock.auto]);
    dc.keepAwake(false);
```
Replace the `Scaffold` body so the video sits behind the gesture layer and overlays:
```dart
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: _controller == null
                  ? const CircularProgressIndicator()
                  : Video(controller: _controller!),
            ),
          ),
          const Positioned.fill(child: PlayerGestures(child: SizedBox.expand())),
          const Positioned.fill(child: ControlsOverlay()),
          const Positioned.fill(child: HudOverlay()),
          const Positioned.fill(child: SpeedLadderOverlay()),
        ],
      ),
    );
```
Add imports:
```dart
import '../../platform/device_controls_provider.dart';
import '../../platform/interfaces/device_controls.dart';
import 'gestures/player_gestures.dart';
import 'controls/controls_overlay.dart';
import 'hud/hud_overlay.dart';
import 'speed/speed_ladder_overlay.dart';
```

- [ ] **Step 4: Run test → PASS**; full suite `flutter test`; `flutter analyze` clean.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/player/player_screen.dart test/ui/player/player_screen_controls_test.dart
git commit -m "feat: compose gestures + controls + HUD + speed ladder in PlayerScreen; landscape + wakelock"
```

---

## Self-Review (cobertura del spec, este plan)

- **§6 Gestos** — tap (Task 3+6), doble-tap ±skip por zona + centro pausa (Task 6), arrastre brillo/volumen con boost + HUD (Tasks 4/5/6 + `volumeMapping`), arrastre horizontal seek (Task 6), zonas muertas: el `SafeArea` en las barras y la lógica por mitades cubren el caso básico; las franjas-muertas dedicadas se afinan en Plan 3 (anotado). ✓
- **§7 Velocidad** — mantener-izq fijo (Task 7), mantener-der ladder vertical momentáneo (Task 7), panel granular 2 decimales + imanes + presets + fino (Task 8). Máx 4.0x respetado vía `clampRate`/`holdRightMax`. ✓
- **§8 Controles** — barra superior (Task 9, con subs/PiP/audio/más deshabilitados), centro ⏪/play/⏩ (Task 9), barra inferior tiempos+seek+toolbar con velocidad activa y lock/aspecto/rotar deshabilitados (Task 9), aparición/fade por tap (Tasks 3/9). Overlay de info permanente, tira de miniaturas y miniatura de frame quedan para Plan 3 (fuera de alcance declarado). ✓
- **Háptica configurable** — Task 6 (`hapticsOnGestures`). ✓
- **Wakelock + landscape** — Task 10. ✓

**Placeholder scan:** sin TBD/TODO; cada paso con código real. Las ediciones a `fakes.dart` (lastSeek, lastPlayingCommand) están señaladas explícitamente en las tareas que las necesitan. ✓

**Type consistency:** `PlayerController` (skipBy/seekTo/setRate/setVolumePercent/togglePlayPause/setBrightness), `volumePercentProvider`/`rateProvider`, `controlsVisibleProvider`, `hudProvider`/`HudKind`/`HudState`, `holdSpeedProvider`/`holdRightSpeedFor`, `gesture_math` (tapZoneOf/clampSeek/dragValue/ladderSpeed/snapToDetent/clampRate/round2/volumeMapping) usados consistentemente entre tareas y tests. ✓

## Notas para Plan 3
Lock (deshabilita gestos+controles, candado mantener-para-desbloquear), modos de aspecto, rotación/orientación configurable, overlay de info permanente con toggle persistido, tira de miniaturas de la cola, y miniatura de frame on-demand en el seek (2ª instancia mpv). Reactivar los botones hoy deshabilitados (lock/aspecto/rotar) y los de Hito 3 (subs/PiP/audio).
