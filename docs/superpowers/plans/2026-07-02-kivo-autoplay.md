# Kivo — Autoplay-Next Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** When a video ends, auto-advance to the next in the folder queue — with a 3s corner "Próximo" overlay in the foreground (immediate/silent in background/PiP), a settings toggle (default on), and a new sleep-timer "stop after N episodes" mode.

**Architecture:** A new `PlaybackEngine.completedStream` drives PlayerScreen (the single owner of engine-open). On completion, a pure `shouldAutoplay(...)` decision gates advancing; foreground shows an `AutoplayOverlay` (3s ring) that then advances, background/PiP advances immediately. Advancing re-opens the engine via a factored `_openSession(...)`. The sleep timer gains an `episodes` mode that counts advances and stops after N.

**Tech Stack:** Flutter/Riverpod, media_kit `stream.completed`, existing FrameExtractor for the next-video thumbnail.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-02-kivo-autoplay-design.md` — authoritative.
- Autoplay only for library-opened videos with `queue.length > 1`; end of queue → stop, no overlay.
- Overlay is a bottom-right corner card, 3s countdown ring, "Reproducir" (advance now) / "Cancelar" (no advance) — FOREGROUND fullscreen only. Background/PiP → advance immediately, no overlay. Foreground vs background via `AppLifecycleState`.
- Suppress autoplay when: A-B loop is `active`; sleep timer will stop here (`episode` mode always; `episodes` mode with `episodesLeft <= 1`); or `autoplayNext` is false.
- `autoplayNext` setting: `bool`, default `true`, all 6 KivoSettings insertion points. No settings-screen UI yet (Hito 4); the value just persists and is honored.
- Owner-single-open: PlayerScreen owns `engine.open`. Autoplay works only while PlayerScreen is alive (fullscreen / home-backgrounded / PiP). Minimized-to-mini-player autoplay is explicitly OUT of v1 scope.
- Spanish copy: overlay label "Próximo", buttons "Reproducir"/"Cancelar"; sleep card "Tras N episodios" / "Deja correr el autoplay y detiene".
- Reuse the cached `VideoController` across advances (never recreate it). Don't disturb PlayerScreen's PopScope / dismiss / mini-player / resume / audio-only / PiP logic.
- `flutter analyze` clean and full `flutter test` green before every commit (current suite: 232).
- Do NOT build the release APK mid-plan — one build at the very end.

---

### Task 1: Foundations — completedStream, settings, queue/next model, pure decision

**Files:**
- Modify: `lib/player/engine/playback_engine.dart`, `lib/player/engine/media_kit_engine.dart`, `lib/player/engine/playback_provider.dart`
- Modify: `lib/core/settings/kivo_settings.dart`
- Modify: `lib/player/open/video_source.dart`
- Create: `lib/player/autoplay/autoplay_logic.dart`
- Create: `lib/ui/player/state/autoplay_state.dart`
- Modify: `test/fakes/fakes.dart`
- Test: `test/player/autoplay/autoplay_logic_test.dart`, `test/player/open/video_source_next_test.dart`

**Interfaces:**
- Produces (later tasks rely on these):
  - `Stream<bool> get completedStream` on `PlaybackEngine`; `FakePlaybackEngine.emitCompleted(bool)`.
  - `final completedProvider = StreamProvider<bool>((ref) => ref.watch(playbackEngineProvider).completedStream);`
  - `KivoSettings.autoplayNext` (`bool`, default `true`).
  - `VideoSession.queueNames` (`List<String>`, default `const []`); `CurrentVideoNotifier.peekNext()` → `VideoSession?`; `CurrentVideoNotifier.advanceTo(VideoSession)`.
  - `bool shouldAutoplay({required bool enabled, required bool hasNext, required bool loopActive, required bool sleepStopsHere})` in `autoplay_logic.dart`.
  - `autoplayPendingProvider` (`StateProvider<VideoSession?>`) and `autoplayConfirmProvider` (`StateProvider<bool>`) in `autoplay_state.dart`.

- [ ] **Step 1: Write failing tests**

`test/player/autoplay/autoplay_logic_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/autoplay/autoplay_logic.dart';

void main() {
  test('shouldAutoplay is true only when enabled, has next, no loop, no sleep-stop', () {
    expect(shouldAutoplay(enabled: true, hasNext: true, loopActive: false, sleepStopsHere: false), true);
    expect(shouldAutoplay(enabled: false, hasNext: true, loopActive: false, sleepStopsHere: false), false);
    expect(shouldAutoplay(enabled: true, hasNext: false, loopActive: false, sleepStopsHere: false), false);
    expect(shouldAutoplay(enabled: true, hasNext: true, loopActive: true, sleepStopsHere: false), false);
    expect(shouldAutoplay(enabled: true, hasNext: true, loopActive: false, sleepStopsHere: true), false);
  });
}
```

`test/player/open/video_source_next_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/open/video_source.dart';

void main() {
  ProviderContainer makeC() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('peekNext returns the next session or null at the end', () {
    final c = makeC();
    final n = c.read(currentVideoProvider.notifier);
    n.open(const VideoSession(
      playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv',
      queue: ['/v/ep1.mkv', '/v/ep2.mkv'], queueNames: ['ep1.mkv', 'ep2.mkv'],
      index: 0, folder: 'Series',
    ));
    final next = n.peekNext();
    expect(next, isNotNull);
    expect(next!.playbackPath, '/v/ep2.mkv');
    expect(next.displayName, 'ep2.mkv');
    expect(next.index, 1);
    expect(next.folder, 'Series');

    n.advanceTo(next);
    expect(c.read(currentVideoProvider)!.index, 1);
    expect(c.read(currentVideoProvider.notifier).peekNext(), isNull); // last item
  });

  test('peekNext is null for a single-item (file-picker) queue', () {
    final c = makeC();
    final n = c.read(currentVideoProvider.notifier);
    n.openPath('/v/solo.mkv');
    expect(n.peekNext(), isNull);
  });

  test('peekNext falls back to basename when queueNames is short', () {
    final c = makeC();
    final n = c.read(currentVideoProvider.notifier);
    n.open(const VideoSession(
      playbackPath: '/v/a.mkv', displayName: 'a.mkv',
      queue: ['/v/a.mkv', '/v/b.mkv'], queueNames: [], index: 0,
    ));
    expect(n.peekNext()!.displayName, 'b.mkv');
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/player/autoplay/ test/player/open/video_source_next_test.dart`
Expected: FAIL — symbols don't exist.

- [ ] **Step 3: Implement completedStream**

`playback_engine.dart` (abstract): add `Stream<bool> get completedStream;`
`media_kit_engine.dart`: add `@override Stream<bool> get completedStream => _player.stream.completed;`
`playback_provider.dart`: add
```dart
final completedProvider = StreamProvider<bool>((ref) {
  return ref.watch(playbackEngineProvider).completedStream;
});
```
`test/fakes/fakes.dart` — in `FakePlaybackEngine`: add controller `final _completed = StreamController<bool>.broadcast();`, `@override Stream<bool> get completedStream => _completed.stream;`, `void emitCompleted(bool v) => _completed.add(v);`, and close it in `dispose()`.

- [ ] **Step 4: Implement settings field**

`kivo_settings.dart`: add `autoplayNext` at all 6 points (field `final bool autoplayNext;`, ctor `required this.autoplayNext,`, `defaults()` `autoplayNext: true,`, copyWith param `bool? autoplayNext,` + body `autoplayNext: autoplayNext ?? this.autoplayNext,`, `toMap` `'autoplayNext': autoplayNext,`, `fromMap` `autoplayNext: m['autoplayNext'] ?? d.autoplayNext,`).

- [ ] **Step 5: Implement queueNames + peekNext + advanceTo**

`video_source.dart` — add `final List<String> queueNames;` to `VideoSession` (constructor `this.queueNames = const [],`; add to any `copyWith` if present — there is none, skip). Populate in `openInFolder`:
```dart
  void openInFolder(VideoItem current, List<VideoItem> all) {
    final folder = folderQueueFor(all, current);
    final idx = folder.indexWhere((v) => v.uri == current.uri);
    state = VideoSession(
      playbackPath: current.uri,
      displayName: current.name,
      queue: folder.map((v) => v.uri).toList(),
      queueNames: folder.map((v) => v.name).toList(),
      index: idx < 0 ? 0 : idx,
      folder: current.folder,
    );
  }
```
Add methods to `CurrentVideoNotifier` (import `../../core/format.dart` is already imported for basenameOf):
```dart
  /// The next session in the folder queue, or null if there is none (single
  /// queue or already the last item). Does not mutate state.
  VideoSession? peekNext() {
    final s = state;
    if (s == null) return null;
    final next = s.index + 1;
    if (next >= s.queue.length) return null;
    final name = next < s.queueNames.length ? s.queueNames[next] : basenameOf(s.queue[next]);
    return VideoSession(
      playbackPath: s.queue[next],
      displayName: name,
      queue: s.queue,
      queueNames: s.queueNames,
      index: next,
      folder: s.folder,
    );
  }

  /// Advance the current session to [next] (used by autoplay). Observers
  /// (notification title, etc.) react as they would to any open.
  void advanceTo(VideoSession next) => state = next;
```

- [ ] **Step 6: Implement pure logic + state provider**

`lib/player/autoplay/autoplay_logic.dart`:
```dart
/// Whether an ended video should auto-advance to the next in the queue.
bool shouldAutoplay({
  required bool enabled,
  required bool hasNext,
  required bool loopActive,
  required bool sleepStopsHere,
}) =>
    enabled && hasNext && !loopActive && !sleepStopsHere;
```
`lib/ui/player/state/autoplay_state.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../player/open/video_source.dart';

/// The queued "next" session while the foreground countdown overlay is shown;
/// null when no autoplay is pending.
final autoplayPendingProvider = StateProvider<VideoSession?>((ref) => null);

/// Toggled true by the overlay when its 3s ring completes or the user taps
/// "Reproducir"; PlayerScreen listens, advances, and resets it to false.
final autoplayConfirmProvider = StateProvider<bool>((ref) => false);
```

- [ ] **Step 7: Run tests, analyze, full suite**

Run the two test files → PASS. `flutter analyze` → clean. `flutter test` → 238 passing (232 + 6: 1 logic + 3 next + you may split; count is approximate — report actual).

- [ ] **Step 8: Commit**

```bash
git add lib/player/engine/ lib/player/engine/playback_provider.dart lib/core/settings/kivo_settings.dart lib/player/open/video_source.dart lib/player/autoplay/ lib/ui/player/state/autoplay_state.dart test/fakes/fakes.dart test/player/autoplay/ test/player/open/video_source_next_test.dart
git commit -m "feat: autoplay foundations — completedStream, autoplayNext setting, peekNext, shouldAutoplay"
```

---

### Task 2: Sleep-timer "episodes" mode + panel card

(Done before the PlayerScreen wiring so the `sleepStopsHere` input exists.)

**Files:**
- Modify: `lib/player/sleep/sleep_timer.dart`
- Modify: `lib/ui/player/sleep/sleep_timer_panel.dart`
- Test: `test/player/sleep/sleep_timer_episodes_test.dart`, extend `test/ui/player/sleep/sleep_timer_panel_test.dart`

**Interfaces:**
- Consumes: `sleepTimerProvider`/`SleepTimerState`/`SleepTimerMode` (existing).
- Produces: `SleepTimerMode.episodes`; `SleepTimerState.episodesLeft` (`int`, 0 when N/A); `SleepTimerNotifier.startEpisodes(int n)`; `void onAutoplayAdvance()` (decrement; when it would drop below 1 it stops+pauses like a fire); `bool get stopsAtEpisodeEnd` on the notifier or a top-level helper `sleepStopsHere(SleepTimerState?)` → true if mode==episode, or mode==episodes && episodesLeft<=1.

- [ ] **Step 1: Write failing tests**

`test/player/sleep/sleep_timer_episodes_test.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/sleep/sleep_timer.dart';
import '../../fakes/fakes.dart';

void main() {
  late FakePlaybackEngine engine;
  late ProviderContainer c;
  Future<void> setUp_() async {
    engine = FakePlaybackEngine();
    final s = await SettingsService.load(InMemorySettingsStore());
    c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
    ]);
    addTearDown(c.dispose); addTearDown(engine.dispose);
    c.listen(sleepTimerProvider, (_, __) {});
  }

  test('startEpisodes sets mode and count; sleepStopsHere true only at last', () async {
    await setUp_();
    final n = c.read(sleepTimerProvider.notifier);
    n.startEpisodes(3);
    expect(c.read(sleepTimerProvider)!.mode, SleepTimerMode.episodes);
    expect(c.read(sleepTimerProvider)!.episodesLeft, 3);
    expect(sleepStopsHere(c.read(sleepTimerProvider)), false);
    n.onAutoplayAdvance(); // 3 -> 2
    expect(c.read(sleepTimerProvider)!.episodesLeft, 2);
    n.onAutoplayAdvance(); // 2 -> 1
    expect(sleepStopsHere(c.read(sleepTimerProvider)), true); // last one stops
  });

  test('episode mode always stops here', () async {
    await setUp_();
    c.read(sleepTimerProvider.notifier).startEpisode();
    expect(sleepStopsHere(c.read(sleepTimerProvider)), true);
  });

  test('sleepStopsHere is false with no timer or fixed mode', () async {
    await setUp_();
    expect(sleepStopsHere(null), false);
    c.read(sleepTimerProvider.notifier).startFixed(const Duration(minutes: 30));
    expect(sleepStopsHere(c.read(sleepTimerProvider)), false);
    c.read(sleepTimerProvider.notifier).cancel();
  });
}
```

- [ ] **Step 2: Run to verify failure** — `flutter test test/player/sleep/sleep_timer_episodes_test.dart` → FAIL.

- [ ] **Step 3: Implement in `sleep_timer.dart`**

Extend the enum: `enum SleepTimerMode { fixed, episode, episodes }`.
Add `final int episodesLeft;` to `SleepTimerState` (constructor `this.episodesLeft = 0,`; include in `copyWith` if the class has one — add an `episodesLeft` param there).
Add to `SleepTimerNotifier`:
```dart
  void startEpisodes(int n) {
    _endsAt = null;
    _episodeBaseline = null;
    _stopFadeAndRestore();
    _cycle++;
    state = SleepTimerState(
      mode: SleepTimerMode.episodes,
      original: Duration.zero,
      remaining: Duration.zero,
      warning: false,
      cycle: _cycle,
      episodesLeft: n.clamp(1, 10),
    );
  }

  /// Called by autoplay each time it advances to the next video. In
  /// `episodes` mode, decrement; the caller checks `sleepStopsHere` BEFORE
  /// advancing, so this only runs when an advance is actually allowed.
  void onAutoplayAdvance() {
    final s = state;
    if (s == null || s.mode != SleepTimerMode.episodes) return;
    state = SleepTimerState(
      mode: SleepTimerMode.episodes,
      original: s.original,
      remaining: s.remaining,
      warning: s.warning,
      cycle: s.cycle,
      episodesLeft: (s.episodesLeft - 1).clamp(0, 10),
    );
  }
```
Add a top-level helper:
```dart
/// True when a video ending should STOP rather than autoplay-advance,
/// because of the sleep timer: episode mode (stop at this end) or the last
/// of an N-episodes countdown.
bool sleepStopsHere(SleepTimerState? s) {
  if (s == null) return false;
  if (s.mode == SleepTimerMode.episode) return true;
  if (s.mode == SleepTimerMode.episodes) return s.episodesLeft <= 1;
  return false;
}
```
Note: the actual stop (pause) when `sleepStopsHere` is true is performed by the autoplay caller in Task 3 (it pauses + cancels the timer instead of advancing) — keep the existing fixed/episode fade/fire paths unchanged.

- [ ] **Step 4: Panel card in `sleep_timer_panel.dart`**

In the selector children (after the existing "Al terminar el episodio" `_EpisodeCard`), add a third card with a stepper for N (local state `int _episodes = 3;` in the sheet state). The "Iniciar" button, when this mode is selected, calls `n.startEpisodes(_episodes)`. Mirror the existing `_EpisodeCard`/stepper styling. Card copy: title "Tras N episodios", subtitle "Deja correr el autoplay y detiene", with a `−`/value/`+` stepper (1–10). Track selection with the existing selection mechanism (extend the current `_episodeSelected` bool to a small enum or add `_episodesSelected`): only one of {duration, episode, episodes} active at a time. Start button label: "Iniciar · Tras N episodios".

- [ ] **Step 5: Extend the panel test**

In `test/ui/player/sleep/sleep_timer_panel_test.dart`, add a test: tapping "Tras N episodios", adjusting the stepper, then "Iniciar" activates `sleepTimerProvider` with `mode == SleepTimerMode.episodes` and the chosen count. Clean up with `cancel()`.

- [ ] **Step 6: Run tests, analyze, full suite** → all green; report the new total.

- [ ] **Step 7: Commit**

```bash
git add lib/player/sleep/sleep_timer.dart lib/ui/player/sleep/sleep_timer_panel.dart test/player/sleep/sleep_timer_episodes_test.dart test/ui/player/sleep/sleep_timer_panel_test.dart
git commit -m "feat: sleep-timer 'stop after N episodes' mode + panel card"
```

---

### Task 3: PlayerScreen wiring — completed → decide → advance/overlay/reopen

**Files:**
- Modify: `lib/ui/player/player_screen.dart`
- Test: `test/ui/player/autoplay_wiring_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 1–2 (`completedProvider`, `autoplayNext`, `peekNext`/`advanceTo`, `shouldAutoplay`, `autoplayPendingProvider`, `abLoopProvider`, `sleepTimerProvider`/`sleepStopsHere`/`onAutoplayAdvance`).
- Produces: `_openSession(VideoSession)` (factored open), the completed-handler, and `_advance(VideoSession)`.

- [ ] **Step 1: Factor `_openSession` out of `_start`**

In `player_screen.dart`, extract the "open this session" body of `_start()` (from the `_resumeKey = session.resumeKey;` line through `_armPip();`, i.e. everything after the expand-from-mini/reset block that actually opens+configures the engine) into:
```dart
  Future<void> _openSession(VideoSession session, {required bool expandingFromMini}) async {
    final engine = ref.read(playbackEngineProvider);
    _resumeKey = session.resumeKey;
    ref.read(playedStoreProvider).markPlayed(_resumeKey!);
    final c = engine.createVideoController();
    if (c is VideoController) { _controller = c; setState(() {}); }
    if (!expandingFromMini) {
      final plan = planResume(
          _resume.positionFor(_resumeKey!), ref.read(settingsProvider).resumeBehavior);
      await engine.open(session.playbackPath, startAt: plan.startAt);
      if (plan.prompt != ResumePromptKind.none) {
        ref.read(resumePromptProvider.notifier).state =
            ResumePromptState(plan.prompt, plan.savedPosition);
      }
    }
    final settings = ref.read(settingsProvider);
    await engine.setSubtitleStyle(
      fontSize: settings.subtitleFontSize,
      textColorArgb: settings.subtitleTextColor,
      backgroundColorArgb: settings.subtitleBackgroundColor,
    );
    if (!expandingFromMini) _applyDefaultTracks(engine, settings, session);
    _frames.prepare(session.playbackPath);
    _armPip();
  }
```
Then `_start()` keeps its head (session read, `expandingFromMini`, the overlay-state resets incl. `dismissProvider`/`pipModeProvider`) and calls `await _openSession(session, expandingFromMini: expandingFromMini);` plus the volume/rate lines that were already there. Keep behavior identical for the initial open — verify existing PlayerScreen tests stay green.

- [ ] **Step 2: Add the completed listener + advance in `build()`**

Add imports: `import '../../player/autoplay/autoplay_logic.dart';`, `import 'state/autoplay_state.dart';`, `import '../../player/loop/ab_loop.dart';` (if not already), `import '../../player/sleep/sleep_timer.dart';` (for `sleepStopsHere`).

In `build()`, next to the other `ref.listen`s, add:
```dart
    ref.listen(completedProvider, (_, next) {
      if (next.value == true) _onCompleted();
    });
```
Add the handler methods to the state class:
```dart
  void _onCompleted() {
    final loopActive = ref.read(abLoopProvider)?.phase == AbLoopPhase.active;
    final sleepStop = sleepStopsHere(ref.read(sleepTimerProvider));
    final next = ref.read(currentVideoProvider.notifier).peekNext();
    final go = shouldAutoplay(
      enabled: ref.read(settingsProvider).autoplayNext,
      hasNext: next != null,
      loopActive: loopActive,
      sleepStopsHere: sleepStop,
    );
    if (!go) {
      // Sleep timer's N-episodes / episode mode reaching its stop: pause + end
      // the timer so the video rests at its end (matches the timer's intent).
      if (sleepStop && next != null && ref.read(settingsProvider).autoplayNext && !loopActive) {
        _engine.pause();
        ref.read(sleepTimerProvider.notifier).cancel();
      }
      return;
    }
    // Foreground fullscreen → countdown overlay; background/PiP → advance now.
    final foreground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (foreground) {
      ref.read(autoplayPendingProvider.notifier).state = next;
    } else {
      _advance(next!);
    }
  }

  void _advance(VideoSession next) {
    ref.read(autoplayPendingProvider.notifier).state = null;
    ref.read(sleepTimerProvider.notifier).onAutoplayAdvance();
    ref.read(currentVideoProvider.notifier).advanceTo(next);
    _openSession(next, expandingFromMini: false);
  }
```
Expose `_advance` for the overlay via a callback: simplest is to have the overlay call `advanceTo` + `_openSession` itself — but `_openSession` is private to the State. Instead, drive advance from the pending provider: the overlay only sets a "confirm" signal. To keep the open in PlayerScreen, add a listener:
```dart
    ref.listen(autoplayConfirmProvider, (_, next) {
      final pending = ref.read(autoplayPendingProvider);
      if (next && pending != null) _advance(pending);
    });
```
where `autoplayConfirmProvider` (defined in `autoplay_state.dart` in Task 1) is toggled by the overlay when the ring completes or "Reproducir" is tapped; reset to false inside `_advance`.

- [ ] **Step 3: Reset autoplay state in `_start` and `dispose`**

In `_start()`'s reset block add `ref.read(autoplayPendingProvider.notifier).state = null;` and `ref.read(autoplayConfirmProvider.notifier).state = false;`. In `dispose()` clear `autoplayPendingProvider` similarly (via cached notifier is unnecessary here since dispose already reads providers for other resets — but to be safe, clear it in `_start` of the next entry which already runs).

- [ ] **Step 4: Write the wiring test**

`test/ui/player/autoplay_wiring_test.dart` — pump `PlayerScreen` with a 2-item library queue (all provider overrides incl. `pipControllerProvider`, `subtitleFinderProvider`, etc. as existing PlayerScreen tests do), emit `engine.emitCompleted(true)`, and assert `autoplayPendingProvider` becomes the next session (foreground path). A second test: with `autoplayNext: false` (via settings), completion leaves `autoplayPendingProvider` null and no advance. A third: with an active A-B loop, completion does not set pending. Use the existing PlayerScreen-test harness in `player_screen_controls_test.dart` as the override template.

- [ ] **Step 5: Run tests, analyze, full suite** → all green; fix any PlayerScreen test that needs the new providers.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/player/player_screen.dart lib/ui/player/state/autoplay_state.dart test/ui/player/autoplay_wiring_test.dart
git commit -m "feat: PlayerScreen autoplay wiring — completed → decide → advance/reopen"
```

---

### Task 4: The "Próximo" corner overlay

**Files:**
- Create: `lib/ui/player/autoplay/autoplay_overlay.dart`
- Modify: `lib/ui/player/player_screen.dart` (mount it in the overlay stack, hidden in PiP)
- Test: `test/ui/player/autoplay_overlay_test.dart`

**Interfaces:**
- Consumes: `autoplayPendingProvider`, `autoplayConfirmProvider`, `FrameExtractor` (`frameExtractorProvider`) for the next thumbnail, `KivoColors`.
- Produces: `class AutoplayOverlay extends ConsumerStatefulWidget`.

- [ ] **Step 1: Create `autoplay_overlay.dart`**

A `ConsumerStatefulWidget` with a `late final AnimationController _ring` (3s). Watch `autoplayPendingProvider`; when it transitions null→non-null, `_ring.forward(from: 0)` and on completion set `autoplayConfirmProvider = true`. When it's null, hide (`SizedBox.shrink`) and reset the controller. Render a bottom-right `Positioned`/`Align` card (`rgba(10,14,26,0.92)`, radius 16, ~290px): row of [thumbnail 74×44 (FutureBuilder on `frameExtractorProvider.frameAt(Duration.zero)` — but the frame extractor is prepared for the CURRENT video; for the next video's thumb, use a placeholder play-glyph box if extraction isn't trivial — the spec allows placeholder], "PRÓXIMO" gold label + name, a 34px `CustomPaint`/`CircularProgressIndicator`-style ring showing `_ring.value` with the remaining seconds `((1-_ring.value)*3).ceil()` centered], then a row [Cancelar ghost → `autoplayPendingProvider = null` + `_ring.stop()`] [Reproducir gold → `autoplayConfirmProvider = true`]. Guard against setting providers during build (do it in listeners/callbacks, not build).

NOTE for the implementer: getting a real thumbnail of the NEXT video requires preparing the extractor for its path — out of scope; use a simple play-glyph placeholder box (the mockup's thumbnail is decorative). Keep it a static gold-bordered box with a ▶ glyph.

- [ ] **Step 2: Mount in PlayerScreen**

In the overlay `Stack`, inside the `if (!ref.watch(pipModeProvider)) ...[ ]` spread (so it hides in PiP), add `const Positioned.fill(child: AutoplayOverlay()),` near `ResumePrompt`/`SleepWarningToast`. Import it.

- [ ] **Step 3: Write the widget test**

`test/ui/player/autoplay_overlay_test.dart`: pump `AutoplayOverlay` in an `UncontrolledProviderScope` with a container; set `autoplayPendingProvider` to a session → pump → expect "Próximo" and the name visible; tap "Cancelar" → `autoplayPendingProvider` is null; re-set pending, tap "Reproducir" → `autoplayConfirmProvider` is true. Use `frameExtractorProvider.overrideWithValue(FakeFrameExtractor())`. Drain the 3s ring timer at the end (`tester.pump(const Duration(seconds: 4))`).

- [ ] **Step 4: Run tests, analyze, full suite** → all green.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/player/autoplay/autoplay_overlay.dart lib/ui/player/player_screen.dart test/ui/player/autoplay_overlay_test.dart
git commit -m "feat: 'Próximo' autoplay countdown overlay (3s corner card)"
```

---

## After all tasks

1. Whole-branch review (opus) with extra scrutiny on: the `_openSession` factoring not changing initial-open behavior (resume/tracks/style/PiP-arm); the completed→advance path not double-firing (completed can emit more than once) or racing the overlay confirm; `advanceTo`+`_openSession` reusing the cached VideoController cleanly (no texture flicker); the sleep `episodes` decrement happening exactly once per advance and stopping at the right count; background/PiP immediate-advance vs foreground-overlay branch; autoplay suppression correctness (loop/sleep/end-of-queue/disabled); no autoplay state stranded across opens.
2. Fix Critical/Important findings; record Minors in the ledger.
3. Build + install release, then report the device checklist from spec §4 (incl. the documented mini-player-minimized limitation).
