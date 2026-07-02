# Kivo H3/3b — Sleep Timer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sleep timer for the player — fixed-duration and "end of episode" modes, 10s warning toast with volume fade-out, global wall-clock state, activated from the (currently disabled) "Más opciones" top-bar button.

**Architecture:** A UI-independent `SleepTimerNotifier` (Riverpod `Notifier<SleepTimerState?>`) owns the ticker, the warning window, and the volume fade, calling only existing `PlaybackEngine` members (`pause`, `setVolume`). Three new UI pieces (more-menu sheet, timer panel sheet, warning toast overlay) plus a top-bar indicator all derive from that single provider. One new settings field remembers the last-used duration.

**Tech Stack:** Flutter, Riverpod (Notifier + ref.listen), fake_async for timer tests, existing `volumeMapping` from `gesture_math.dart`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-02-kivo-h3-3b-sleep-timer-design.md` — the authoritative requirements.
- The fade touches ONLY the player volume (`PlaybackEngine.setVolume`), NEVER the system volume (`DeviceControls.setSystemVolume`).
- Timer counts wall-clock time (`endsAt` absolute instant), not playback time: manual pause does NOT pause the timer.
- Timer is global state — it must survive `PlayerScreen` dispose (mini-player), video changes, and screen-off; it dies with the process (no AlarmManager).
- One-shot: after firing (pause done, volume restored) state returns to `null`.
- Warning window = 10 seconds, in BOTH modes. Toast actions: Extender (fixed → restart original duration; episode → cancel), Desactivar (cancel), ✕ (dismiss toast only, countdown continues).
- Manual volume adjustment during the fade cancels the fade silently but the timer keeps running and the toast stays.
- Duration selector: 8 segments × 15 min (max 120), stepper ±5 min, clamp 5–120. Last used duration persisted as `sleepTimerLastMinutes` (int, default 30).
- Visual language: bottom sheets styled like `track_picker.dart` (panel `KivoColors.panel`, radius 20 top, grabber, header+close); cards `Color(0xFF182036)` radius 13; gold `KivoColors.gold` for active; segmented meters (lit gold / `white 14%`); Material icons inside sheets (as track_picker does), `KivoIcons` only in the top bar.
- All copy in Spanish exactly as specified in each task (e.g. "Temporizador de apagado", "Iniciar · 45 min", "Pausando en 0:08", "Extender", "Desactivar", "Al terminar el episodio").
- No PiP changes (3d), no A-B loop (3c), no "N episodios", no autoplay.
- `KivoSettings` new fields touch all 6 insertion points: field, constructor, `defaults()`, `copyWith`, `toMap`, `fromMap`.
- Do NOT build/install the APK — the user triggers device builds manually later.
- `flutter analyze` clean and full `flutter test` green before every commit. Current suite: 170 tests.

---

### Task 1: Settings field + SleepTimerNotifier core (fixed mode: start/extend/cancel/warning/fade/fire)

**Files:**
- Modify: `lib/core/settings/kivo_settings.dart`
- Create: `lib/player/sleep/sleep_timer.dart`
- Test: `test/player/sleep/sleep_timer_test.dart`

**Interfaces:**
- Consumes: `PlaybackEngine.pause()/setVolume(double percent)` (exists); `volumePercentProvider` (`StateProvider<double>`, 0..150, from `lib/player/control/player_controller.dart`); `volumeMapping(double percent, double boostMax)` → `({double system01, double playerPercent})` (from `lib/player/control/gesture_math.dart`); `settingsProvider` (`KivoSettings` state) and `KivoSettings.volumeBoostMax` (int); `playbackEngineProvider`.
- Produces (Tasks 2–4 rely on these exact names):
  - `enum SleepTimerMode { fixed, episode }`
  - `class SleepTimerState { final SleepTimerMode mode; final Duration original; final Duration remaining; final bool warning; final int cycle; }` (const ctor with all named-required; `copyWith({Duration? remaining, bool? warning})`)
  - `final sleepClockProvider = Provider<DateTime Function()>((_) => DateTime.now);`
  - `final sleepTimerProvider = NotifierProvider<SleepTimerNotifier, SleepTimerState?>(SleepTimerNotifier.new);`
  - `SleepTimerNotifier` methods: `void startFixed(Duration d)`, `void startEpisode()` (Task 1 ships it as a stub that only sets state — Task 2 completes it), `void extend()`, `void cancel()`.
  - New settings field: `KivoSettings.sleepTimerLastMinutes` (`int`, default `30`).

- [ ] **Step 1: Add `sleepTimerLastMinutes` to KivoSettings (6 insertion points)**

In `lib/core/settings/kivo_settings.dart`, mirror the exact pattern of the neighboring `subtitleFontSize` field at each of the 6 standard points:

1. Field (after `final int subtitleBackgroundColor;`):
```dart
  final int sleepTimerLastMinutes;
```
2. Constructor: `required this.sleepTimerLastMinutes,`
3. `defaults()`: `sleepTimerLastMinutes: 30,`
4. `copyWith` parameter `int? sleepTimerLastMinutes,` and body `sleepTimerLastMinutes: sleepTimerLastMinutes ?? this.sleepTimerLastMinutes,`
5. `toMap()`: `'sleepTimerLastMinutes': sleepTimerLastMinutes,`
6. `fromMap()`: `sleepTimerLastMinutes: m['sleepTimerLastMinutes'] ?? d.sleepTimerLastMinutes,`

- [ ] **Step 2: Write the failing tests**

Create `test/player/sleep/sleep_timer_test.dart`:

```dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/control/player_controller.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/sleep/sleep_timer.dart';
import '../../fakes/fakes.dart';

void main() {
  test('KivoSettings.sleepTimerLastMinutes defaults to 30 and round-trips', () {
    final d = KivoSettings.defaults();
    expect(d.sleepTimerLastMinutes, 30);
    final back = KivoSettings.fromMap(d.copyWith(sleepTimerLastMinutes: 45).toMap());
    expect(back.sleepTimerLastMinutes, 45);
  });

  // Shared harness: a controllable clock + container. `now` is mutated by the
  // test; the notifier's periodic ticker reads it through sleepClockProvider.
  late DateTime now;
  late FakePlaybackEngine engine;
  late ProviderContainer container;

  Future<ProviderContainer> makeContainer() async {
    engine = FakePlaybackEngine();
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      sleepClockProvider.overrideWithValue(() => now),
    ]);
    addTearDown(c.dispose);
    addTearDown(engine.dispose);
    // Keep the notifier alive for the whole test.
    c.listen(sleepTimerProvider, (_, __) {});
    return c;
  }

  test('startFixed sets state with original, remaining and no warning', () async {
    now = DateTime(2026, 1, 1, 22, 0, 0);
    container = await makeContainer();
    fakeAsync((async) {
      container.read(sleepTimerProvider.notifier).startFixed(const Duration(minutes: 30));
      final st = container.read(sleepTimerProvider)!;
      expect(st.mode, SleepTimerMode.fixed);
      expect(st.original, const Duration(minutes: 30));
      expect(st.remaining, const Duration(minutes: 30));
      expect(st.warning, false);
    });
  });

  test('ticker updates remaining and enters warning at <=10s', () async {
    now = DateTime(2026, 1, 1, 22, 0, 0);
    container = await makeContainer();
    fakeAsync((async) {
      container.read(sleepTimerProvider.notifier).startFixed(const Duration(minutes: 30));
      now = now.add(const Duration(minutes: 29, seconds: 52));
      async.elapse(const Duration(milliseconds: 300));
      final st = container.read(sleepTimerProvider)!;
      expect(st.warning, true);
      expect(st.remaining.inSeconds, lessThanOrEqualTo(10));
    });
  });

  test('fade lowers player volume during warning and restores it on fire', () async {
    now = DateTime(2026, 1, 1, 22, 0, 0);
    container = await makeContainer();
    fakeAsync((async) {
      container.read(volumePercentProvider.notifier).state = 100;
      container.read(sleepTimerProvider.notifier).startFixed(const Duration(minutes: 30));
      // Jump into the middle of the warning window: 5s remaining → factor 0.5.
      now = now.add(const Duration(minutes: 29, seconds: 55));
      async.elapse(const Duration(milliseconds: 300));
      expect(engine.volume, lessThan(100));
      // Cross endsAt → fire.
      now = now.add(const Duration(seconds: 6));
      async.elapse(const Duration(milliseconds: 300));
      expect(engine.lastPlayingCommand, false); // paused
      expect(engine.volume, 100); // restored to the user's mapped level
      expect(container.read(sleepTimerProvider), isNull); // one-shot
    });
  });

  test('extend restarts the original duration and restores volume', () async {
    now = DateTime(2026, 1, 1, 22, 0, 0);
    container = await makeContainer();
    fakeAsync((async) {
      container.read(volumePercentProvider.notifier).state = 100;
      final n = container.read(sleepTimerProvider.notifier);
      n.startFixed(const Duration(minutes: 30));
      now = now.add(const Duration(minutes: 29, seconds: 55));
      async.elapse(const Duration(milliseconds: 300));
      expect(container.read(sleepTimerProvider)!.warning, true);
      n.extend();
      final st = container.read(sleepTimerProvider)!;
      expect(st.warning, false);
      expect(st.remaining, const Duration(minutes: 30));
      expect(st.cycle, greaterThan(0)); // new cycle → toast reappears next time
      expect(engine.volume, 100);
    });
  });

  test('cancel clears state and restores volume', () async {
    now = DateTime(2026, 1, 1, 22, 0, 0);
    container = await makeContainer();
    fakeAsync((async) {
      container.read(volumePercentProvider.notifier).state = 100;
      final n = container.read(sleepTimerProvider.notifier);
      n.startFixed(const Duration(minutes: 30));
      now = now.add(const Duration(minutes: 29, seconds: 55));
      async.elapse(const Duration(milliseconds: 300));
      n.cancel();
      expect(container.read(sleepTimerProvider), isNull);
      expect(engine.volume, 100);
      // No pause on cancel:
      expect(engine.lastPlayingCommand, isNot(false));
    });
  });

  test('manual volume change during fade cancels the fade but not the timer', () async {
    now = DateTime(2026, 1, 1, 22, 0, 0);
    container = await makeContainer();
    fakeAsync((async) {
      container.read(volumePercentProvider.notifier).state = 100;
      container.read(sleepTimerProvider.notifier).startFixed(const Duration(minutes: 30));
      now = now.add(const Duration(minutes: 29, seconds: 55));
      async.elapse(const Duration(milliseconds: 300));
      expect(engine.volume, lessThan(100));
      // User adjusts volume mid-fade (gesture already applied its own engine volume).
      container.read(volumePercentProvider.notifier).state = 60;
      engine.volume = 77; // whatever the gesture set on the engine
      async.elapse(const Duration(milliseconds: 600));
      expect(engine.volume, 77); // fade no longer overrides
      expect(container.read(sleepTimerProvider), isNotNull); // timer still running
      expect(container.read(sleepTimerProvider)!.warning, true);
    });
  });
}
```

- [ ] **Step 3: Run to verify failure**

Run: `flutter test test/player/sleep/sleep_timer_test.dart`
Expected: FAIL — `sleep_timer.dart` does not exist / `sleepTimerLastMinutes` undefined.

- [ ] **Step 4: Implement `lib/player/sleep/sleep_timer.dart`**

```dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings/settings_provider.dart';
import '../control/gesture_math.dart';
import '../control/player_controller.dart';
import '../engine/playback_provider.dart';

enum SleepTimerMode { fixed, episode }

/// Immutable snapshot of the running sleep timer. `null` provider state means
/// no timer. [cycle] increments on every (re)start so the warning toast can
/// tell a fresh warning window from one the user already dismissed with ✕.
class SleepTimerState {
  final SleepTimerMode mode;
  final Duration original;
  final Duration remaining;
  final bool warning;
  final int cycle;
  const SleepTimerState({
    required this.mode,
    required this.original,
    required this.remaining,
    required this.warning,
    required this.cycle,
  });

  SleepTimerState copyWith({Duration? remaining, bool? warning}) => SleepTimerState(
        mode: mode,
        original: original,
        remaining: remaining ?? this.remaining,
        warning: warning ?? this.warning,
        cycle: cycle,
      );
}

/// Injectable clock so tests can control wall-time.
final sleepClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

final sleepTimerProvider =
    NotifierProvider<SleepTimerNotifier, SleepTimerState?>(SleepTimerNotifier.new);

class SleepTimerNotifier extends Notifier<SleepTimerState?> {
  static const warningWindow = Duration(seconds: 10);
  static const _tickEvery = Duration(milliseconds: 250);

  Timer? _ticker;
  DateTime? _endsAt; // fixed mode only
  int _cycle = 0;

  // Fade bookkeeping. The fade multiplies the player volume the user actually
  // has (mapped through volumeMapping, system volume untouched); a manual
  // volume change mid-fade cancels the fade silently — clear awake signal.
  bool _fading = false;
  bool _fadeCancelled = false;
  double _fadeBase = 100;

  @override
  SleepTimerState? build() {
    ref.listen(volumePercentProvider, (prev, next) {
      if (_fading) _fadeCancelled = true;
    });
    ref.onDispose(() => _ticker?.cancel());
    return null;
  }

  DateTime get _now => ref.read(sleepClockProvider)();

  double get _userPlayerVolume {
    final boost = ref.read(settingsProvider).volumeBoostMax.toDouble();
    return volumeMapping(ref.read(volumePercentProvider), boost).playerPercent;
  }

  void startFixed(Duration d) {
    _endsAt = _now.add(d);
    // Restore-then-reset: extending from inside the warning window must undo
    // the partially-applied fade immediately.
    _stopFadeAndRestore();
    _cycle++;
    state = SleepTimerState(
      mode: SleepTimerMode.fixed,
      original: d,
      remaining: d,
      warning: false,
      cycle: _cycle,
    );
    _startTicker();
  }

  /// Episode mode is completed in the next task (position/duration tracking);
  /// this only establishes the state shape.
  void startEpisode() {
    _endsAt = null;
    _stopFadeAndRestore();
    _cycle++;
    state = SleepTimerState(
      mode: SleepTimerMode.episode,
      original: Duration.zero,
      remaining: Duration.zero,
      warning: false,
      cycle: _cycle,
    );
  }

  void extend() {
    final s = state;
    if (s == null) return;
    if (s.mode == SleepTimerMode.fixed) {
      startFixed(s.original);
    } else {
      cancel();
    }
  }

  void cancel() {
    _stopFadeAndRestore();
    _ticker?.cancel();
    _ticker = null;
    _endsAt = null;
    state = null;
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(_tickEvery, (_) => _tick());
  }

  void _tick() {
    final s = state;
    final endsAt = _endsAt;
    if (s == null || endsAt == null) return;
    final remaining = endsAt.difference(_now);
    if (remaining <= Duration.zero) {
      _fire();
      return;
    }
    final warning = remaining <= warningWindow;
    if (warning) _applyFade(remaining);
    // Only emit when something visible changed (second boundary or flag flip)
    // to avoid 4 rebuilds per second.
    if (warning != s.warning || remaining.inSeconds != s.remaining.inSeconds) {
      state = s.copyWith(remaining: remaining, warning: warning);
    }
  }

  void _fire() {
    final engine = ref.read(playbackEngineProvider);
    engine.pause();
    _stopFadeAndRestore();
    _ticker?.cancel();
    _ticker = null;
    _endsAt = null;
    state = null;
  }

  void _applyFade(Duration remaining) {
    if (_fadeCancelled) return;
    if (!_fading) {
      _fading = true;
      _fadeBase = _userPlayerVolume;
    }
    final factor =
        (remaining.inMilliseconds / warningWindow.inMilliseconds).clamp(0.0, 1.0);
    ref.read(playbackEngineProvider).setVolume(_fadeBase * factor);
  }

  void _stopFadeAndRestore() {
    if (_fading && !_fadeCancelled) {
      ref.read(playbackEngineProvider).setVolume(_userPlayerVolume);
    }
    _resetFade();
  }

  void _resetFade() {
    _fading = false;
    _fadeCancelled = false;
  }
}
```

- [ ] **Step 5: Run the new tests**

Run: `flutter test test/player/sleep/sleep_timer_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 6: Full verification**

Run: `flutter analyze` → "No issues found!". Run: `flutter test` → 177 passing (170 + 7).

- [ ] **Step 7: Commit**

```bash
git add lib/core/settings/kivo_settings.dart lib/player/sleep/sleep_timer.dart test/player/sleep/sleep_timer_test.dart
git commit -m "feat: sleep timer core — fixed mode with warning window, fade-out and one-shot fire"
```

---

### Task 2: Episode mode (position/duration tracking, video-change re-apply)

**Files:**
- Modify: `lib/player/sleep/sleep_timer.dart`
- Test: `test/player/sleep/sleep_timer_episode_test.dart`

**Interfaces:**
- Consumes: everything Task 1 produced; `positionProvider`/`durationProvider` (`StreamProvider<Duration>` in `lib/player/engine/playback_provider.dart`); `currentVideoProvider` (`NotifierProvider<CurrentVideoNotifier, VideoSession?>` in `lib/player/open/video_source.dart`).
- Produces: fully working `startEpisode()`; episode `SleepTimerState` where `original` = remaining-at-start (for the panel's draining meter) and `remaining` = `duration − position` (updated on every position emission).

- [ ] **Step 1: Write the failing tests**

Create `test/player/sleep/sleep_timer_episode_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/control/player_controller.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/sleep/sleep_timer.dart';
import '../../fakes/fakes.dart';

void main() {
  late FakePlaybackEngine engine;
  late ProviderContainer container;

  Future<void> setUpContainer() async {
    engine = FakePlaybackEngine();
    final s = await SettingsService.load(InMemorySettingsStore());
    container = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
    ]);
    addTearDown(container.dispose);
    addTearDown(engine.dispose);
    container.listen(sleepTimerProvider, (_, __) {});
    // Streams are broadcast without replay: subscribe (via the providers the
    // notifier listens through) BEFORE emitting.
    container.listen(positionProvider, (_, __) {});
    container.listen(durationProvider, (_, __) {});
  }

  // Two microtask turns: one for the StreamController delivery, one for the
  // StreamProvider's AsyncValue hop.
  Future<void> pumpStreams() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  test('episode mode tracks remaining = duration - position', () async {
    await setUpContainer();
    container.read(sleepTimerProvider.notifier).startEpisode();
    engine.emitDuration(const Duration(minutes: 10));
    engine.emitPosition(const Duration(minutes: 4));
    await pumpStreams();
    final st = container.read(sleepTimerProvider)!;
    expect(st.mode, SleepTimerMode.episode);
    expect(st.remaining, const Duration(minutes: 6));
    expect(st.warning, false);
  });

  test('episode mode enters warning at <=10s from the end and fades', () async {
    await setUpContainer();
    container.read(volumePercentProvider.notifier).state = 100;
    container.read(sleepTimerProvider.notifier).startEpisode();
    engine.emitDuration(const Duration(minutes: 10));
    engine.emitPosition(const Duration(minutes: 9, seconds: 52));
    await pumpStreams();
    expect(container.read(sleepTimerProvider)!.warning, true);
    expect(engine.volume, lessThan(100));
  });

  test('episode mode fires at the end of the video (pause + restore + null)', () async {
    await setUpContainer();
    container.read(volumePercentProvider.notifier).state = 100;
    container.read(sleepTimerProvider.notifier).startEpisode();
    engine.emitDuration(const Duration(minutes: 10));
    engine.emitPosition(const Duration(minutes: 10));
    await pumpStreams();
    expect(engine.lastPlayingCommand, false);
    expect(engine.volume, 100);
    expect(container.read(sleepTimerProvider), isNull);
  });

  test('opening another video re-applies episode mode to the new video', () async {
    await setUpContainer();
    container.read(volumePercentProvider.notifier).state = 100;
    container.read(sleepTimerProvider.notifier).startEpisode();
    engine.emitDuration(const Duration(minutes: 10));
    engine.emitPosition(const Duration(minutes: 9, seconds: 55));
    await pumpStreams();
    expect(container.read(sleepTimerProvider)!.warning, true);

    // New video opens: warning resets, volume restored, mode stays active.
    container.read(currentVideoProvider.notifier).open(
      const VideoSession(playbackPath: '/v/ep2.mkv', displayName: 'ep2.mkv', queue: ['/v/ep2.mkv'], index: 0),
    );
    engine.emitDuration(const Duration(minutes: 20));
    engine.emitPosition(Duration.zero);
    await pumpStreams();
    final st = container.read(sleepTimerProvider)!;
    expect(st.mode, SleepTimerMode.episode);
    expect(st.warning, false);
    expect(engine.volume, 100);
  });

  test('extend in episode mode cancels the timer', () async {
    await setUpContainer();
    container.read(sleepTimerProvider.notifier).startEpisode();
    engine.emitDuration(const Duration(minutes: 10));
    engine.emitPosition(const Duration(minutes: 9, seconds: 55));
    await pumpStreams();
    container.read(sleepTimerProvider.notifier).extend();
    expect(container.read(sleepTimerProvider), isNull);
    // Playback untouched by the cancel itself:
    expect(engine.lastPlayingCommand, isNot(false));
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/player/sleep/sleep_timer_episode_test.dart`
Expected: FAIL — episode mode doesn't track position yet.

- [ ] **Step 3: Implement episode tracking in `sleep_timer.dart`**

Add to `SleepTimerNotifier` (and add import `../open/video_source.dart`):

In `build()`, after the existing `volumePercentProvider` listener, add:

```dart
    ref.listen(positionProvider, (prev, next) {
      final pos = next.value;
      if (pos != null) _onPosition(pos);
    });
    ref.listen(durationProvider, (prev, next) {
      final dur = next.value;
      if (dur != null) _duration = dur;
    });
    ref.listen(currentVideoProvider, (prev, next) {
      // New video while episode mode is active: re-apply to the new video —
      // reset the warning/fade so the countdown restarts from its length.
      if (state?.mode == SleepTimerMode.episode && prev != next) {
        _stopFadeAndRestore();
        _duration = null;
        _episodeBaseline = null;
        state = state!.copyWith(remaining: Duration.zero, warning: false);
      }
    });
```

Add fields:

```dart
  Duration? _duration;        // last known video duration
  Duration? _episodeBaseline; // remaining when episode mode engaged (meter 100%)
```

Add the position handler:

```dart
  void _onPosition(Duration pos) {
    final s = state;
    final dur = _duration;
    if (s == null || s.mode != SleepTimerMode.episode || dur == null || dur == Duration.zero) {
      return;
    }
    final remaining = dur - pos;
    if (remaining <= const Duration(milliseconds: 300)) {
      // Video reached its natural end. pause() is a safety belt — with no
      // autoplay the engine stops on the last frame anyway.
      _fire();
      return;
    }
    _episodeBaseline ??= remaining;
    final warning = remaining <= warningWindow;
    if (warning) _applyFade(remaining);
    if (warning != s.warning || remaining.inSeconds != s.remaining.inSeconds) {
      state = SleepTimerState(
        mode: SleepTimerMode.episode,
        original: _episodeBaseline!,
        remaining: remaining,
        warning: warning,
        cycle: s.cycle,
      );
    }
  }
```

Update `startEpisode()` to reset the new fields:

```dart
  void startEpisode() {
    _endsAt = null;
    _episodeBaseline = null;
    _stopFadeAndRestore();
    _cycle++;
    state = SleepTimerState(
      mode: SleepTimerMode.episode,
      original: Duration.zero,
      remaining: Duration.zero,
      warning: false,
      cycle: _cycle,
    );
  }
```

And in `cancel()` add `_episodeBaseline = null;` next to `_endsAt = null;`.

- [ ] **Step 4: Run the new tests, then everything**

Run: `flutter test test/player/sleep/sleep_timer_episode_test.dart` → PASS (5 tests).
Run: `flutter analyze` → clean. Run: `flutter test` → 182 passing (177 + 5).

- [ ] **Step 5: Commit**

```bash
git add lib/player/sleep/sleep_timer.dart test/player/sleep/sleep_timer_episode_test.dart
git commit -m "feat: sleep timer episode mode — end-of-video tracking with re-apply on video change"
```

---

### Task 3: More-options menu + sleep timer panel (selector + active view)

**Files:**
- Create: `lib/ui/player/more/more_menu.dart`
- Create: `lib/ui/player/sleep/sleep_timer_panel.dart`
- Modify: `lib/ui/player/controls/top_bar.dart` (activate the "Más opciones" button only — indicator comes in Task 4)
- Test: `test/ui/player/sleep/sleep_timer_panel_test.dart`

**Interfaces:**
- Consumes: `sleepTimerProvider`/`SleepTimerNotifier.startFixed/startEpisode/cancel/extend`, `SleepTimerState` (Task 1/2); `settingsProvider` notifier `.set(KivoSettings)` and `sleepTimerLastMinutes`; `KivoColors.panel/gold`; `fmtDuration(Duration)` from `lib/core/format.dart` (formats m:ss).
- Produces: `Future<void> showMoreMenu(BuildContext context, WidgetRef ref)`; `Future<void> showSleepTimerPanel(BuildContext context, WidgetRef ref)`.

- [ ] **Step 1: Create `lib/ui/player/more/more_menu.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/kivo_theme.dart';
import '../sleep/sleep_timer_panel.dart';

/// Mini menu behind the top bar's "Más opciones" button. The A-B loop entry
/// joins this menu in 3c.
Future<void> showMoreMenu(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: KivoColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
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
                showSleepTimerPanel(context, ref);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _MenuRow({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF182036),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 16, color: Colors.white70),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 1),
                  Text(subtitle,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.42), fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: Colors.white.withValues(alpha: 0.42)),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Create `lib/ui/player/sleep/sleep_timer_panel.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../player/sleep/sleep_timer.dart';

Future<void> showSleepTimerPanel(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: KivoColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    isScrollControlled: true,
    builder: (_) => const _SleepTimerSheet(),
  );
}

class _SleepTimerSheet extends ConsumerStatefulWidget {
  const _SleepTimerSheet();
  @override
  ConsumerState<_SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends ConsumerState<_SleepTimerSheet> {
  late int _minutes; // 5..120
  bool _episodeSelected = false;

  @override
  void initState() {
    super.initState();
    _minutes = ref.read(settingsProvider).sleepTimerLastMinutes.clamp(5, 120);
  }

  void _start() {
    final n = ref.read(sleepTimerProvider.notifier);
    if (_episodeSelected) {
      n.startEpisode();
    } else {
      n.startFixed(Duration(minutes: _minutes));
      final s = ref.read(settingsProvider);
      ref.read(settingsProvider.notifier).set(s.copyWith(sleepTimerLastMinutes: _minutes));
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(sleepTimerProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
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
            Row(
              children: [
                const Text('Temporizador de apagado',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.close_rounded, size: 15, color: Colors.white70),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (active == null) ..._selectorChildren() else ..._activeChildren(active),
          ],
        ),
      ),
    );
  }

  List<Widget> _selectorChildren() {
    return [
      const _Eyebrow('Duración'),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _StepButton(label: '−', onTap: () => setState(() {
            _minutes = (_minutes - 5).clamp(5, 120);
            _episodeSelected = false;
          })),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('$_minutes min',
                style: TextStyle(
                  color: _episodeSelected ? Colors.white38 : KivoColors.gold,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
          ),
          _StepButton(label: '+', onTap: () => setState(() {
            _minutes = (_minutes + 5).clamp(5, 120);
            _episodeSelected = false;
          })),
        ],
      ),
      const SizedBox(height: 8),
      _SegmentMeter(
        litFraction: _episodeSelected ? 0 : _minutes / 120,
        onSegmentTap: (i) => setState(() {
          _minutes = (i + 1) * 15;
          _episodeSelected = false;
        }),
      ),
      const _Eyebrow('O bien'),
      _EpisodeCard(
        selected: _episodeSelected,
        onTap: () => setState(() => _episodeSelected = !_episodeSelected),
      ),
      const SizedBox(height: 12),
      _PrimaryButton(
        label: _episodeSelected ? 'Iniciar · Al terminar el episodio' : 'Iniciar · $_minutes min',
        onTap: _start,
      ),
    ];
  }

  List<Widget> _activeChildren(SleepTimerState st) {
    final total = st.original.inMilliseconds;
    final frac = total == 0 ? 0.0 : (st.remaining.inMilliseconds / total).clamp(0.0, 1.0);
    return [
      const SizedBox(height: 4),
      Center(
        child: Text(fmtDuration(st.remaining),
            style: const TextStyle(
              color: KivoColors.gold,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            )),
      ),
      Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 10),
          child: Text(
            st.mode == SleepTimerMode.fixed
                ? 'restante · de ${st.original.inMinutes} min'
                : 'hasta el final del episodio',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.42),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
      _SegmentMeter(litFraction: frac, onSegmentTap: null),
      const SizedBox(height: 14),
      if (st.mode == SleepTimerMode.fixed)
        Row(
          children: [
            Expanded(child: _GhostButton(label: 'Desactivar', onTap: () => ref.read(sleepTimerProvider.notifier).cancel())),
            const SizedBox(width: 8),
            Expanded(
              child: _PrimaryButton(
                label: 'Extender +${st.original.inMinutes}',
                onTap: () => ref.read(sleepTimerProvider.notifier).extend(),
              ),
            ),
          ],
        )
      else
        _GhostButton(label: 'Desactivar', onTap: () => ref.read(sleepTimerProvider.notifier).cancel()),
    ];
  }
}

class _Eyebrow extends StatelessWidget {
  final String label;
  const _Eyebrow(this.label);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
        child: Text(label.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            )),
      );
}

class _StepButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _StepButton({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
        ),
      );
}

/// The signature segmented meter: 8 segments × 15 min. Tapping segment i sets
/// (i+1)×15 min (when [onSegmentTap] is non-null); a null callback renders the
/// read-only draining variant used while the timer runs.
class _SegmentMeter extends StatelessWidget {
  final double litFraction; // 0..1
  final ValueChanged<int>? onSegmentTap;
  const _SegmentMeter({required this.litFraction, required this.onSegmentTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 8; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i == 7 ? 0 : 5),
                  child: GestureDetector(
                    onTap: onSegmentTap == null ? null : () => onSegmentTap!(i),
                    child: Container(
                      height: 22,
                      decoration: BoxDecoration(
                        color: (i + 1) / 8 <= litFraction + 0.001
                            ? KivoColors.gold
                            : Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (onSegmentTap != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                for (var i = 0; i < 8; i++)
                  Expanded(
                    child: Text('${(i + 1) * 15}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.42),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        )),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  const _EpisodeCard({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? KivoColors.gold.withValues(alpha: 0.16) : const Color(0xFF182036),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
              color: selected ? KivoColors.gold.withValues(alpha: 0.5) : Colors.transparent),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: selected
                    ? KivoColors.gold.withValues(alpha: 0.16)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(Icons.movie_outlined,
                  size: 16, color: selected ? KivoColors.gold : Colors.white70),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Al terminar el episodio',
                      style: TextStyle(
                        color: selected ? KivoColors.gold : Colors.white,
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      )),
                  const SizedBox(height: 1),
                  Text('Se detiene cuando termine este video',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.42), fontSize: 11)),
                ],
              ),
            ),
            if (selected) const Icon(Icons.check_rounded, size: 18, color: KivoColors.gold),
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryButton({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: KivoColors.gold,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: const TextStyle(
                  color: Color(0xFF231705), fontWeight: FontWeight.w800, fontSize: 13.5)),
        ),
      );
}

class _GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _GhostButton({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
        ),
      );
}
```

Note: `FontFeature` needs `import 'dart:ui' show FontFeature;` — add it if the analyzer asks (Flutter's material.dart usually re-exports it via painting).

- [ ] **Step 3: Activate the more button in `lib/ui/player/controls/top_bar.dart`**

Replace the disabled more button line:

```dart
        IconButton(color: Colors.white38, tooltip: 'Más opciones', icon: KivoIcon(KivoIcons.more, size: 24, opacity: 0.38), onPressed: null),
```

with:

```dart
        Builder(
          builder: (context) => IconButton(
            color: Colors.white,
            tooltip: 'Más opciones',
            icon: KivoIcon(KivoIcons.more, size: 24, color: Colors.white),
            onPressed: () => showMoreMenu(context, ref),
          ),
        ),
```

and add the import `import '../more/more_menu.dart';`. Note the disabled button currently sits between the subtitles and audio buttons order: back · info · subtítulos · PiP (disabled) · audio · more — keep the position, only activate it.

- [ ] **Step 4: Write the widget tests**

Create `test/ui/player/sleep/sleep_timer_panel_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/sleep/sleep_timer.dart';
import 'package:kivo_player/ui/player/more/more_menu.dart';
import 'package:kivo_player/ui/player/sleep/sleep_timer_panel.dart';
import '../../../fakes/fakes.dart';

Future<ProviderContainer> _pump(WidgetTester tester, {required bool viaMenu}) async {
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
    child: MaterialApp(
      theme: KivoTheme.dark(),
      home: Scaffold(
        body: Center(
          child: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () => viaMenu ? showMoreMenu(context, ref) : showSleepTimerPanel(context, ref),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('more menu shows the timer entry and navigates to the panel', (tester) async {
    await _pump(tester, viaMenu: true);
    expect(find.text('Temporizador de apagado'), findsOneWidget);
    await tester.tap(find.text('Temporizador de apagado'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Iniciar ·'), findsOneWidget);
  });

  testWidgets('stepper adjusts minutes and the start button label follows', (tester) async {
    await _pump(tester, viaMenu: false);
    expect(find.text('Iniciar · 30 min'), findsOneWidget); // default from settings
    await tester.tap(find.text('+'));
    await tester.pump();
    expect(find.text('Iniciar · 35 min'), findsOneWidget);
  });

  testWidgets('starting a fixed timer activates the provider and persists the minutes', (tester) async {
    final c = await _pump(tester, viaMenu: false);
    await tester.tap(find.text('+')); // 35
    await tester.pump();
    await tester.tap(find.text('Iniciar · 35 min'));
    await tester.pumpAndSettle();
    final st = c.read(sleepTimerProvider);
    expect(st, isNotNull);
    expect(st!.mode, SleepTimerMode.fixed);
    expect(st.original, const Duration(minutes: 35));
    expect(c.read(settingsProvider).sleepTimerLastMinutes, 35);
    c.read(sleepTimerProvider.notifier).cancel(); // clean up the real ticker
  });

  testWidgets('episode card selects episode mode and starts it', (tester) async {
    final c = await _pump(tester, viaMenu: false);
    await tester.tap(find.text('Al terminar el episodio'));
    await tester.pump();
    await tester.tap(find.text('Iniciar · Al terminar el episodio'));
    await tester.pumpAndSettle();
    expect(c.read(sleepTimerProvider)!.mode, SleepTimerMode.episode);
  });

  testWidgets('active view shows countdown and Desactivar cancels', (tester) async {
    final c = await _pump(tester, viaMenu: false);
    c.read(sleepTimerProvider.notifier).startFixed(const Duration(minutes: 30));
    await tester.pump();
    expect(find.textContaining('restante'), findsOneWidget);
    await tester.tap(find.text('Desactivar'));
    await tester.pump();
    expect(c.read(sleepTimerProvider), isNull);
  });
}
```

- [ ] **Step 5: Run tests, analyze, full suite**

Run: `flutter test test/ui/player/sleep/sleep_timer_panel_test.dart` → PASS (5 tests).
Run: `flutter analyze` → clean. Run: `flutter test` → 187 passing (182 + 5).

- [ ] **Step 6: Commit**

```bash
git add lib/ui/player/more/more_menu.dart lib/ui/player/sleep/sleep_timer_panel.dart lib/ui/player/controls/top_bar.dart test/ui/player/sleep/sleep_timer_panel_test.dart
git commit -m "feat: more-options menu + sleep timer panel with segmented duration meter"
```

---

### Task 4: Warning toast + top-bar indicator + PlayerScreen mount

**Files:**
- Create: `lib/ui/player/sleep/sleep_warning_toast.dart`
- Modify: `lib/ui/player/controls/top_bar.dart` (indicator on the more button)
- Modify: `lib/ui/player/player_screen.dart` (mount the toast overlay)
- Test: `test/ui/player/sleep/sleep_warning_toast_test.dart`

**Interfaces:**
- Consumes: `sleepTimerProvider`, `SleepTimerState.{warning, remaining, cycle}`, notifier `.extend()/.cancel()` (Tasks 1–2); `fmtDuration`; `settingsProvider.accentColor`.
- Produces: `class SleepWarningToast extends ConsumerStatefulWidget` — self-contained overlay, visible only while `state?.warning == true` and not dismissed for the current `cycle`.

- [ ] **Step 1: Create `lib/ui/player/sleep/sleep_warning_toast.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/format.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../player/sleep/sleep_timer.dart';

/// Bottom toast shown during the sleep timer's 10s warning window, over the
/// fade-out. ✕ dismisses only the toast for this warning cycle; the countdown
/// and fade continue. Positioned like ResumePrompt (bottom-centered capsule).
class SleepWarningToast extends ConsumerStatefulWidget {
  const SleepWarningToast({super.key});
  @override
  ConsumerState<SleepWarningToast> createState() => _SleepWarningToastState();
}

class _SleepWarningToastState extends ConsumerState<SleepWarningToast> {
  int _dismissedCycle = -1;

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(sleepTimerProvider);
    if (st == null || !st.warning || st.cycle == _dismissedCycle) {
      return const SizedBox.shrink();
    }
    final n = ref.read(sleepTimerProvider.notifier);
    final secondsLeft = st.remaining.inSeconds.clamp(0, 10);

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 96),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          constraints: const BoxConstraints(maxWidth: 420),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: KivoColors.gold.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.bedtime_outlined, size: 14, color: KivoColors.gold),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: 'Pausando en ',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                        children: [
                          TextSpan(
                            text: fmtDuration(st.remaining),
                            style: const TextStyle(
                              color: KivoColors.gold,
                              fontWeight: FontWeight.w800,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _dismissedCycle = st.cycle),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.close_rounded,
                          size: 15, color: Colors.white.withValues(alpha: 0.42)),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 8),
                child: Row(
                  children: [
                    for (var i = 0; i < 10; i++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: i == 9 ? 0 : 3),
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: i < secondsLeft
                                  ? KivoColors.gold
                                  : Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(9),
                    onTap: () => n.cancel(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      child: Text('Desactivar',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5)),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(9),
                    onTap: () => n.extend(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: KivoColors.gold,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Text('Extender',
                          style: TextStyle(
                              color: Color(0xFF231705),
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

(`FontFeature` comes from `dart:ui`; material re-exports it — add `import 'dart:ui' show FontFeature;` only if the analyzer complains.)

- [ ] **Step 2: Mount the toast in `lib/ui/player/player_screen.dart`**

In the overlay `Stack` (currently ending with `const Positioned.fill(child: ResumePrompt()),`), add immediately after the ResumePrompt line:

```dart
                      const Positioned.fill(child: SleepWarningToast()),
```

and add the import `import 'sleep/sleep_warning_toast.dart';`. Touch nothing else in this file — it contains delicate PopScope/mini-player/resume logic.

- [ ] **Step 3: Add the indicator to the more button in `lib/ui/player/controls/top_bar.dart`**

Replace the Task-3 more button `Builder` with:

```dart
        Builder(
          builder: (context) {
            final sleep = ref.watch(sleepTimerProvider);
            final active = sleep != null;
            return IconButton(
              color: active ? accent : Colors.white,
              tooltip: 'Más opciones',
              icon: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  KivoIcon(KivoIcons.more, size: active ? 20 : 24, color: active ? accent : Colors.white),
                  if (active)
                    Text(
                      fmtDuration(sleep.remaining),
                      style: TextStyle(
                        color: accent,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
              onPressed: () => showMoreMenu(context, ref),
            );
          },
        ),
```

Add imports: `import '../../../core/format.dart';` and `import '../../../player/sleep/sleep_timer.dart';` (plus `dart:ui` FontFeature if needed).

- [ ] **Step 4: Write the widget tests**

Create `test/ui/player/sleep/sleep_warning_toast_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/sleep/sleep_timer.dart';
import 'package:kivo_player/ui/player/sleep/sleep_warning_toast.dart';
import '../../../fakes/fakes.dart';

void main() {
  late FakePlaybackEngine engine;
  late ProviderContainer c;

  Future<void> pumpToast(WidgetTester tester) async {
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
      child: const MaterialApp(home: Scaffold(body: SleepWarningToast())),
    ));
  }

  // Drives the notifier into a warning state without waiting real minutes:
  // episode mode + position 8s from the end.
  Future<void> enterWarning(WidgetTester tester) async {
    c.read(sleepTimerProvider.notifier).startEpisode();
    engine.emitDuration(const Duration(minutes: 10));
    engine.emitPosition(const Duration(minutes: 9, seconds: 52));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('hidden with no timer; visible in warning with countdown', (tester) async {
    await pumpToast(tester);
    expect(find.textContaining('Pausando en'), findsNothing);
    await enterWarning(tester);
    expect(find.textContaining('Pausando en'), findsOneWidget);
    expect(find.text('Extender'), findsOneWidget);
    expect(find.text('Desactivar'), findsOneWidget);
  });

  testWidgets('Desactivar cancels the timer', (tester) async {
    await pumpToast(tester);
    await enterWarning(tester);
    await tester.tap(find.text('Desactivar'));
    await tester.pump();
    expect(c.read(sleepTimerProvider), isNull);
    expect(find.textContaining('Pausando en'), findsNothing);
  });

  testWidgets('Extender in episode mode cancels (keeps watching)', (tester) async {
    await pumpToast(tester);
    await enterWarning(tester);
    await tester.tap(find.text('Extender'));
    await tester.pump();
    expect(c.read(sleepTimerProvider), isNull);
  });

  testWidgets('close (✕) hides the toast but the timer keeps running', (tester) async {
    await pumpToast(tester);
    await enterWarning(tester);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(find.textContaining('Pausando en'), findsNothing);
    expect(c.read(sleepTimerProvider), isNotNull);
    expect(c.read(sleepTimerProvider)!.warning, true);
  });
}
```

- [ ] **Step 5: Run tests, analyze, full suite**

Run: `flutter test test/ui/player/sleep/sleep_warning_toast_test.dart` → PASS (4 tests).
Run: `flutter analyze` → clean. Run: `flutter test` → 191 passing (187 + 4). If any pre-existing PlayerScreen test needs an extra pump for the new overlay, fix the test with the minimal change and report it.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/player/sleep/sleep_warning_toast.dart lib/ui/player/controls/top_bar.dart lib/ui/player/player_screen.dart test/ui/player/sleep/sleep_warning_toast_test.dart
git commit -m "feat: sleep warning toast + top-bar countdown indicator"
```

---

## After all tasks

1. Whole-branch review (opus model) over the full 3b range (spec commit → last task commit) with extra scrutiny on: the fade never touching system volume; notifier lifecycle (ticker cancelled on cancel/fire/dispose; no leaks); episode-mode listener correctness (broadcast streams, video-change reset); and that `player_screen.dart` received only the single overlay line + import.
2. Fix Critical/Important findings, record Minors in the ledger.
3. Do NOT build the APK — the user triggers device builds manually. Report the device-test checklist instead (from the spec §5).
