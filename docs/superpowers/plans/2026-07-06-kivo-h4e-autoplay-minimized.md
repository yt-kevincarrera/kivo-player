# Kivo Hito 4e — Autoplay while minimized — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Advance the queue to the next video when the current one ends **while minimized** to the mini-player (the queue already advances when the player is expanded).

**Architecture:** Extract the track-defaults logic into a reusable function (Task 1), then add an app-level `AutoplayCoordinator` (Task 2) that — ONLY when `playerMinimizedProvider` is true (PlayerScreen destroyed, so its own `_onCompleted` isn't running → no double-advance) — listens to `completedProvider` and advances: `advanceTo(next)` + `engine.open(startAt)` + `engine.play()` + `applyDefaultTracks(...)` + sleep decrement + mini-thumbnail capture. Wired into `KivoApp` like `backgroundPlaybackProvider`.

**Tech Stack:** Flutter/Riverpod. Reuses `shouldAutoplay`, `peekNext`, `sleepStopsHere`, `planResume`, `selectAudio/SubtitleTrack`, `frameExtractorProvider`.

## Global Constraints

- **Coordinator acts ONLY when minimized** (`playerMinimizedProvider == true`); returns immediately otherwise. This is what prevents double-advance with PlayerScreen's expanded-case `_onCompleted`.
- **Minimized advance is immediate + playing** (no "Próximo" overlay — that's foreground-only) and respects `settings.autoplayNext`, the A-B loop (`loopActive` → no advance), and the sleep timer (`sleepStopsHere` → pause + cancel; `onAutoplayAdvance()` decrements "N episodes").
- **Task 1 is behavior-preserving** — `applyDefaultTracks` moves verbatim; existing tests stay green.
- **Mini-thumbnail on advance:** best-effort capture of the new video's first frame; failure falls back silently.
- **`flutter analyze` clean + full `flutter test` green before every commit** (current suite: 317).
- **Do NOT build the APK mid-plan.**

---

### Task 1: Extract `applyDefaultTracks` into a reusable function

**Files:**
- Create: `lib/player/tracks/apply_default_tracks.dart`
- Modify: `lib/ui/player/player_screen.dart` (remove the private `_applyDefaultTracks`; call the new function; clean now-unused imports)
- Test: `test/player/tracks/apply_default_tracks_test.dart`

**Interfaces:**
- Produces: `void applyDefaultTracks({required PlaybackEngine engine, required KivoSettings settings, required VideoSession session, required SubtitleFinder subtitleFinder})` — fire-and-forget; applies preferred audio/subtitle tracks (+ external subtitle by filename for library videos). Identical behavior to the old `PlayerScreen._applyDefaultTracks`.

- [ ] **Step 1: Write the failing test**

```dart
// test/player/tracks/apply_default_tracks_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/player/engine/playback_engine.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/tracks/apply_default_tracks.dart';
import 'package:kivo_player/platform/interfaces/subtitle_finder.dart';
import '../../fakes/fakes.dart';

class _NoSubs implements SubtitleFinder {
  @override
  Future<List<ExternalSubtitle>> findNear(String folder) async => const [];
}

void main() {
  test('applies the preferred audio track when it matches', () async {
    final e = FakePlaybackEngine();
    addTearDown(e.dispose);
    const session = VideoSession(
      playbackPath: '/v/a.mkv', displayName: 'a.mkv', queue: ['/v/a.mkv'], index: 0);
    applyDefaultTracks(
      engine: e,
      settings: KivoSettings.defaults().copyWith(preferredAudioLanguage: 'es'),
      session: session,
      subtitleFinder: _NoSubs());
    // Emit tracks so the .first calls resolve (no 2s timeout timer left pending).
    e.emitAudioTracks(const [
      MediaTrack(id: '1', title: 'EN', language: 'en'),
      MediaTrack(id: '2', title: 'ES', language: 'es'),
    ]);
    e.emitSubtitleTracks(const []);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(e.currentAudioTrackId, '2'); // the 'es' pick
  });
}
```

(If `FakePlaybackEngine` lacks `emitAudioTracks`/`emitSubtitleTracks` and/or `MediaTrack`'s constructor differs, add the two one-line emit helpers to `test/fakes/fakes.dart` — `void emitAudioTracks(List<MediaTrack> t) => _audioTracks.add(t);` and the subtitle twin — and use `MediaTrack`'s real constructor. `setAudioTrack` in the fake must set `currentAudioTrackId`; if it doesn't yet, that's an existing fake gap — make it record.)

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/player/tracks/apply_default_tracks_test.dart`
Expected: FAIL — `apply_default_tracks.dart` doesn't exist.

- [ ] **Step 3: Implement the extraction**

```dart
// lib/player/tracks/apply_default_tracks.dart
import '../../core/settings/kivo_settings.dart';
import '../../platform/interfaces/subtitle_finder.dart';
import '../engine/playback_engine.dart';
import '../open/video_source.dart';
import 'track_selection.dart';

/// Applies the user's default audio/subtitle choices when a video opens:
/// preferred-language embedded tracks first, then (for library videos with a
/// [VideoSession.folder]) an external subtitle file next to it whose filename
/// encodes the preferred language. Fire-and-forget; best-effort — a track/finder
/// error must never break playback start.
void applyDefaultTracks({
  required PlaybackEngine engine,
  required KivoSettings settings,
  required VideoSession session,
  required SubtitleFinder subtitleFinder,
}) {
  () async {
    final audioTracks = await engine.audioTracksStream.first.timeout(
      const Duration(seconds: 2), onTimeout: () => const <MediaTrack>[]);
    final audioPick = selectAudioTrack(
      tracks: audioTracks, preferredLanguage: settings.preferredAudioLanguage);
    if (audioPick != null) await engine.setAudioTrack(audioPick.id);

    final subtitleTracks = await engine.subtitleTracksStream.first.timeout(
      const Duration(seconds: 2), onTimeout: () => const <MediaTrack>[]);
    final subtitlePick = selectSubtitleTrack(
      tracks: subtitleTracks,
      enabledByDefault: settings.subtitlesEnabledByDefault,
      preferredLanguage: settings.preferredSubtitleLanguage);
    if (subtitlePick != null) {
      await engine.setSubtitleTrack(subtitlePick.id);
    } else if (settings.subtitlesEnabledByDefault &&
        settings.preferredSubtitleLanguage != null &&
        session.folder != null) {
      try {
        final externals = await subtitleFinder.findNear(session.folder!);
        for (final ext in externals) {
          if (languageFromFilename(ext.displayName) == settings.preferredSubtitleLanguage) {
            await engine.setExternalSubtitle(ext.uri, title: ext.displayName);
            break;
          }
        }
      } catch (_) {
        // Best-effort — native channel errors / empty folder never break start.
      }
    }
  }();
}
```

In `lib/ui/player/player_screen.dart`: delete the private `_applyDefaultTracks(...)` method entirely; add `import '../../player/tracks/apply_default_tracks.dart';`; replace its call site (inside `_openSession`, currently `if (!expandingFromMini) _applyDefaultTracks(engine, settings, session);`) with:
```dart
      if (!expandingFromMini) {
        applyDefaultTracks(
          engine: engine, settings: settings, session: session,
          subtitleFinder: ref.read(subtitleFinderProvider));
      }
```
Then remove any imports in `player_screen.dart` that are now unused (likely `track_selection.dart`, and possibly `track_selection`'s symbols / `MediaTrack` if nothing else in the file references them — run `flutter analyze` and delete whatever it flags as unused).

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/player/tracks/apply_default_tracks_test.dart` → pass.
Run: `flutter analyze lib/player/tracks/apply_default_tracks.dart lib/ui/player/player_screen.dart` → No issues. Then FULL suite `flutter test` → green (behavior-preserving; existing player/track tests must still pass).

- [ ] **Step 5: Commit**

```bash
git add lib/player/tracks/apply_default_tracks.dart lib/ui/player/player_screen.dart test/player/tracks/apply_default_tracks_test.dart test/fakes/fakes.dart
git commit -m "refactor(player): extract applyDefaultTracks into a reusable function"
```

---

### Task 2: `AutoplayCoordinator` (advance while minimized)

**Files:**
- Create: `lib/player/autoplay/autoplay_coordinator.dart`
- Modify: `lib/app.dart` (instantiate the coordinator)
- Test: `test/player/autoplay/autoplay_coordinator_test.dart`

**Interfaces:**
- Consumes: `applyDefaultTracks` (Task 1); `completedProvider`, `playbackEngineProvider` (`playback_provider.dart`); `playerMinimizedProvider`, `miniPlayerThumbnailProvider` (`ui/player/state/mini_player_state.dart`); `currentVideoProvider`, `resumeServiceProvider` (`player/open/video_source.dart`); `settingsProvider`; `shouldAutoplay` (`player/autoplay/autoplay_logic.dart`); `sleepStopsHere`, `sleepTimerProvider` (`player/sleep/sleep_timer.dart`); `abLoopProvider`, `AbLoopPhase` (`player/loop/ab_loop.dart`); `planResume` (`player/resume/resume_plan.dart`); `playedStoreProvider` (`player/library/played.dart`); `frameExtractorProvider` (`platform/frame_extractor_provider.dart`); `subtitleFinderProvider` (`platform/subtitle_finder_provider.dart`).
- Produces: `autoplayCoordinatorProvider`.

- [ ] **Step 1: Write the failing test**

```dart
// test/player/autoplay/autoplay_coordinator_test.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/frame_extractor_provider.dart';
import 'package:kivo_player/platform/subtitle_finder_provider.dart';
import 'package:kivo_player/player/autoplay/autoplay_coordinator.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/ui/player/state/mini_player_state.dart';
import '../../fakes/fakes.dart';

const _twoItem = VideoSession(
  playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv',
  queue: ['/v/ep1.mkv', '/v/ep2.mkv'], queueNames: ['ep1.mkv', 'ep2.mkv'],
  queueIds: ['1', '2'], index: 0);

Future<(ProviderContainer, FakePlaybackEngine)> _setup(WidgetTester t,
    {bool minimized = true, bool autoplay = true}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final engine = FakePlaybackEngine();
  addTearDown(engine.dispose);
  final s = await SettingsService.load(InMemorySettingsStore());
  await s.update(s.current.copyWith(autoplayNext: autoplay));
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    playbackEngineProvider.overrideWithValue(engine),
    resumeServiceProvider.overrideWithValue(FakeResumeService()),
    subtitleFinderProvider.overrideWithValue(FakeSubtitleFinder()),
    frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
    playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
  ]);
  addTearDown(c.dispose);
  c.read(currentVideoProvider.notifier).open(_twoItem);
  c.read(playerMinimizedProvider.notifier).state = minimized;
  c.read(autoplayCoordinatorProvider); // instantiate + start listening
  return (c, engine);
}

Future<void> _pump() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  testWidgets('minimized + autoplay on → completing advances to the next video', (t) async {
    final (c, engine) = await _setup(t);
    engine.emitCompleted(true);
    await _pump();
    // Resolve applyDefaultTracks' stream .first so no 2s timer lingers.
    engine.emitAudioTracks(const []);
    engine.emitSubtitleTracks(const []);
    await _pump();
    expect(engine.openedPath, '/v/ep2.mkv');
    expect(c.read(currentVideoProvider)!.index, 1);
    expect(engine.lastPlayingCommand, true);
  });

  testWidgets('NOT minimized → completing does not advance (PlayerScreen owns it)', (t) async {
    final (c, engine) = await _setup(t, minimized: false);
    engine.emitCompleted(true);
    await _pump();
    expect(engine.openedPath, isNull);
    expect(c.read(currentVideoProvider)!.index, 0);
  });

  testWidgets('autoplay off → completing does not advance', (t) async {
    final (c, engine) = await _setup(t, autoplay: false);
    engine.emitCompleted(true);
    await _pump();
    expect(engine.openedPath, isNull);
  });

  testWidgets('last video (no next) → completing does not advance', (t) async {
    final (c, engine) = await _setup(t);
    c.read(currentVideoProvider.notifier).advanceTo(
      c.read(currentVideoProvider.notifier).sessionAt(1)!); // move to last
    engine.openedPath = null; // ignore the advanceTo bookkeeping
    engine.emitCompleted(true);
    await _pump();
    expect(engine.openedPath, isNull);
  });
}
```

(Notes: `FakeResumeService`/`FakeSubtitleFinder`/`FakeFrameExtractor` — reuse from `test/fakes/fakes.dart` if present; otherwise add minimal stubs (ResumeService: `positionFor→null`, `record→noop`; SubtitleFinder: `findNear→[]`; FrameExtractor: `prepare→noop`, `frameAt→null`). `advanceTo`/`sessionAt` are on `CurrentVideoNotifier`. If `MediaTrack`/emit helpers were added in Task 1, they're available here too.)

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/player/autoplay/autoplay_coordinator_test.dart`
Expected: FAIL — `autoplayCoordinatorProvider` doesn't exist.

- [ ] **Step 3: Implement the coordinator**

```dart
// lib/player/autoplay/autoplay_coordinator.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings/settings_provider.dart';
import '../../platform/frame_extractor_provider.dart';
import '../../platform/subtitle_finder_provider.dart';
import '../../ui/player/state/mini_player_state.dart';
import '../engine/playback_provider.dart';
import '../library/played.dart';
import '../loop/ab_loop.dart';
import '../open/video_source.dart';
import '../resume/resume_plan.dart';
import '../sleep/sleep_timer.dart';
import '../tracks/apply_default_tracks.dart';
import 'autoplay_logic.dart';

/// App-level coordinator that advances the queue when a video ends WHILE
/// MINIMIZED to the mini-player. When the player is expanded, PlayerScreen owns
/// completion (its "Próximo" overlay); this returns immediately then, so there
/// is no double-advance (PlayerScreen is disposed while minimized). Instantiate
/// once by watching [autoplayCoordinatorProvider] (KivoApp does).
final autoplayCoordinatorProvider = Provider<AutoplayCoordinator>((ref) {
  final c = AutoplayCoordinator(ref);
  c.init();
  return c;
});

class AutoplayCoordinator {
  final Ref _ref;
  AutoplayCoordinator(this._ref);
  bool _advancing = false;

  void init() {
    _ref.listen(completedProvider, (_, next) {
      if (next.value == true) _onCompleted();
    });
  }

  void _onCompleted() {
    if (_advancing) return;
    // Expanded → PlayerScreen handles it (with the overlay). Only act minimized.
    if (!_ref.read(playerMinimizedProvider)) return;
    final settings = _ref.read(settingsProvider);
    final loopActive = _ref.read(abLoopProvider)?.phase == AbLoopPhase.active;
    final sleepStop = sleepStopsHere(_ref.read(sleepTimerProvider));
    final next = _ref.read(currentVideoProvider.notifier).peekNext();
    final go = shouldAutoplay(
      enabled: settings.autoplayNext,
      hasNext: next != null,
      loopActive: loopActive,
      sleepStopsHere: sleepStop,
    );
    if (!go) {
      if (sleepStop && next != null && settings.autoplayNext && !loopActive) {
        _ref.read(playbackEngineProvider).pause();
        _ref.read(sleepTimerProvider.notifier).cancel();
      }
      return;
    }
    _advance(next!);
  }

  Future<void> _advance(VideoSession next) async {
    _advancing = true;
    final engine = _ref.read(playbackEngineProvider);
    final settings = _ref.read(settingsProvider);
    try {
      _ref.read(sleepTimerProvider.notifier).onAutoplayAdvance();
      _ref.read(currentVideoProvider.notifier).advanceTo(next);
      _ref.read(playedStoreProvider).markPlayed(next.resumeKey);
      final plan = planResume(
        _ref.read(resumeServiceProvider).positionFor(next.resumeKey),
        settings.resumeBehavior);
      await engine.open(next.playbackPath, startAt: plan.startAt);
      await engine.play();
      applyDefaultTracks(
        engine: engine, settings: settings, session: next,
        subtitleFinder: _ref.read(subtitleFinderProvider));
      _refreshMiniThumb(next.playbackPath);
    } finally {
      _advancing = false;
    }
  }

  Future<void> _refreshMiniThumb(String path) async {
    try {
      final frames = _ref.read(frameExtractorProvider);
      await frames.prepare(path);
      final bytes = await frames.frameAt(Duration.zero);
      _ref.read(miniPlayerThumbnailProvider.notifier).state = bytes;
    } catch (_) {
      // Best-effort — a failed capture just leaves the previous/placeholder art.
    }
  }
}
```

Verify the exact names against source before relying on them: `planResume(Duration? savedPosition, String behavior)` and `ResumeService.positionFor(String key)` (see `player_screen._start`/`_openSession`); `sleepStopsHere(SleepTimerState)` + `SleepTimerNotifier.onAutoplayAdvance()`/`cancel()`; `abLoopProvider` value has `.phase` with `AbLoopPhase.active`. If any signature differs, match the real one (these are all already used by `player_screen.dart`).

In `lib/app.dart`, instantiate alongside the existing coordinator:
```dart
    ref.watch(backgroundPlaybackProvider);
    ref.watch(autoplayCoordinatorProvider); // advance the queue while minimized
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/player/autoplay/autoplay_coordinator_test.dart` → 4 pass.
Run: `flutter analyze lib/player/autoplay/autoplay_coordinator.dart lib/app.dart` → No issues. Then FULL suite `flutter test` → green.

- [ ] **Step 5: Commit**

```bash
git add lib/player/autoplay/autoplay_coordinator.dart lib/app.dart test/player/autoplay/autoplay_coordinator_test.dart
git commit -m "feat(autoplay): advance the queue while minimized (app-level coordinator)"
```

---

## Self-Review

**Spec coverage:** §2 coordinator + extraction + KivoApp wiring → Tasks 1-2. §3 interactions (no double-advance via minimized guard; sleep decrement/stop; mini-player auto-updates + thumb refresh; resume via planResume; A-B loop → no advance; last video → no advance) → Task 2 `_onCompleted`/`_advance`. §4 tests → per task. All covered.

**Placeholder scan:** No TBD/TODO; complete code. The "verify signatures against source" note is a safety instruction (these APIs are all used by player_screen already), not a placeholder. Fake-stub notes are conditional-adaptation guidance.

**Type consistency:** `applyDefaultTracks({engine, settings, session, subtitleFinder})` identical between Task 1 (def) and Task 2 (use). `_advance(VideoSession)`; `peekNext()`/`advanceTo()`/`sessionAt()` on `CurrentVideoNotifier`. Test order 1→2 (Task 2 imports `apply_default_tracks.dart`).

## Final verification (after Task 2)

1. `flutter analyze` → No issues. `flutter test` → all green.
2. Release build + install to the Pixel 6.
3. Device checklist (spec §4): open a video → minimize → tap the mini-bar play → let it finish → **advances to the next** in the mini-player (title + thumbnail update, keeps playing); expand mid-play → correct video; foreground autoplay overlay unchanged; sleep "N episodes" minimized stops where it should; a single-item queue minimized just stops at the end.
